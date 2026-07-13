# ADR 0018 — `db.json`'s `linux.version` is derived from the release's publish date, not from `/MiSTer.version`

**Status:** Proposed (2026-07-13) — authored by the P4.5 agent; **needs human ratification
before two real releases ship back to back** (see "Open question" below).
**Impact:** `scripts/gen-db-json.py`, `.github/workflows/publish-db.yml` (this task, P4.5);
longer-term, a candidate follow-up to `board/mister/de10nano/post-build.sh` /
`configs/mister_de10nano_defconfig` (P2.6, out of scope here).
**Supersedes:** nothing formal — this is the first ADR to address db.json's version
field. It resolves the "OPEN QUESTION" `.github/workflows/release.yml` (P4.4,
`phase4-release-eng` branch) explicitly left for "P4.5 and/or P2.6."
**Full rationale:** `docs/db-json-versioning.md` (this task) — this ADR is the short,
decision-record form of that document; read the longer doc for the mechanism and the
residual trade-off in detail.

## The problem, stated plainly

`configs/mister_de10nano_defconfig` pins `SOURCE_DATE_EPOCH` to Buildroot's own
last-commit date — a deliberate, valuable choice (P2.5/A9: it's what makes two
independent builds of the same commit produce byte-identical images). One side effect:
`board/mister/de10nano/post-build.sh` derives `/MiSTer.version`'s 6-byte `YYMMDD` stamp
from that same pinned epoch, so **every release built from the same `BUILDROOT_VERSION`
bakes an identical `/MiSTer.version`** — regardless of how different the kernel, patches,
or packages inside it actually are.

The Downloader's entire update-detection mechanism (`docs/downloader-contract.md` §3) is
a **strict string inequality** between the running system's `/MiSTer.version` and
`db.json`'s `linux.version[-6:]`. If `db.json`'s version tracked the baked-in value, two
back-to-back releases from the same Buildroot pin would publish the same version string,
and a user already on the first release would never be offered the second.

## Decision

`scripts/gen-db-json.py` derives `linux.version` from the **GitHub Release's own real
publish date** (`publishedAt`), independent of `/MiSTer.version` and independent of the
`release_YYYYMMDD.7z` filename (which itself traces back to the baked-in value — see
`release.yml`'s "derive RELEASE_DATE" step). `linux.hash`/`linux.size` come from the
actual uploaded release asset, which does vary release-to-release by content, regardless
of what `/MiSTer.version` says.

This makes `db.json`'s advertised version **distinct per release** (barring two releases
published the same UTC calendar day), which is sufficient to make the Downloader's
inequality check fire and offer every real release to already-subscribed devices. This is
the problem this ADR is scoped to fix.

## Open question — NOT resolved by this ADR, flagged for a human decision

Decoupling `db.json`'s version from `/MiSTer.version` trades one failure mode for
another: after a device installs a release, its on-device `/MiSTer.version` does **not**
advance to match whatever `db.json` said — it stays at the Buildroot-pinned constant.
Until the *next* real release changes `db.json` again, the same inequality that
correctly triggered the last update **remains true**, so every intervening Downloader run
sees "update available" again — re-downloading the archive and re-running `updateboot`
(which unconditionally erases U-Boot's saved environment and re-flashes `uboot.img`,
`docs/downloader-contract.md` §8) even though nothing has actually changed.

This is not silently accepted as fine: `docs/db-json-versioning.md` names it explicitly
and proposes the durable fix — have `post-build.sh` accept a build-time override for
`/MiSTer.version` specifically (e.g. an env var the release workflow sets to that
release's real date), leaving `SOURCE_DATE_EPOCH` itself untouched for every other
reproducibility guarantee it protects (file mtimes, ext4 superblock timestamps). That
change touches P2.6/P4.4-owned files and was out of scope for this task (P4.5: no
Buildroot build, author YAML/scripts/docs only). **A human must decide whether to accept
the residual re-flash-on-every-run behavior as an interim beta-phase cost, or land the
P2.6 override before the first two real releases ship back to back** — this ADR's
"Proposed" status, rather than "Accepted," reflects that this half of the decision is
still open.
