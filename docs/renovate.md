# Renovate onboarding (`renovate.json`)

TASKS.md P4.6. This document explains what `renovate.json` (and its
companion `.github/workflows/renovate-hash-sync.yml`) manages, what is
deliberately excluded, the automerge policy, and the hash-provenance rules
a human must follow for the pins Renovate cannot safely finish on its own.

## Status: live

Renovate is **installed on this repository** and this config is active.

`renovate.json` validates clean against the official tool — run this before
pushing any change to it:

```sh
npx --package renovate -- renovate-config-validator renovate.json
```

That check is not optional busywork: an **invalid Renovate config makes Renovate
skip the repository silently**. It does not fail loudly, and there is no CI
signal for it — the only symptom is that dependency PRs quietly stop appearing,
which is exactly the failure you would not notice for months.

What is still unproven is the *behavior* of the custom managers below, as opposed
to their syntax. Renovate reads its config from the **default branch**, so the
managers only start producing PRs once this file is on `master`. TASKS.md P4.6's
"Done when" —

> a real or synthetic Renovate PR for a Buildroot point release opens with
> passing CI; the pin file's regex manager is covered by a Renovate config test

— is therefore **not yet met**: no custom manager here has produced a real PR.
Treat each one as reviewed-and-schema-valid, not battle-tested, and see
["Unverified / what to check on first run"](#unverified--what-to-check-on-first-run)
for the specific pieces most likely to need a fix on the first live run.

## What is managed

| Pin | File(s) | Mechanism | Hash companion |
|---|---|---|---|
| Buildroot release | `Makefile` (`BUILDROOT_VERSION`) | `customManagers` regex, `github-tags` datasource, `allowedVersions` locked to `2026.02.x` | `BUILDROOT_SHA256` — **manual**, see below |
| Kernel | `configs/mister_de10nano_defconfig` (`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`) | `customManagers` regex + a `customDatasources` entry over `kernel.org/releases.json`, filtered to `moniker=longterm` and the `6.18.` prefix; `allowedVersions` locked to `6.18.y` as defense in depth | `board/mister/de10nano/patches/linux/linux.hash` — auto-refreshed by `renovate-hash-sync.yml` from kernel.org's signed `sha256sums.asc` |
| 9 driver commit-SHA pins | `package/{rtl8812au,rtl8814au-morrownr,rtl8821au-morrownr,rtl8821cu-morrownr,rtl8188fu,rtl8188eu-aircrack-ng,rtl88x2bu,xone,midilink}/*.mk` | `customManagers` regex per package, `git-refs` datasource tracking the upstream default branch's HEAD via `currentDigest` | matching `.hash` file — auto-refreshed by `renovate-hash-sync.yml` |
| munt tag pin | `package/munt/munt.mk` | `github-tags` datasource, custom `regex:` versioning for the `munt_MAJOR_MINOR_PATCH` tag scheme | `package/munt/munt.hash` — auto-refreshed |
| bcm20702-firmware **commit** pin | `package/bcm20702-firmware/bcm20702-firmware.mk` | `git-refs` datasource tracking `master` HEAD via `currentDigest`. **Was** a `github-tags`/`loose` tag pin until 2026-07-19 — see "Why this one is a commit pin" below | `package/bcm20702-firmware/bcm20702-firmware.hash` — auto-refreshed |
| libchdr commit-SHA pin (Main_MiSTer shared-lib refactor; labeled `lib-pin`) | `package/libchdr/libchdr.mk` | `customManagers` regex, `git-refs` datasource tracking `rtissera/libchdr`'s `master` HEAD via `currentDigest` (a commit pin, not the stale `v0.3.0` tag — see the .mk's header) | `package/libchdr/libchdr.hash` — auto-refreshed by `renovate-hash-sync.yml`'s generic loop (standard `$(call github,...)` archive tarball) |
| lzma-sdk tag pin (Main_MiSTer shared-lib refactor; labeled `lib-pin`) | `package/lzma-sdk/lzma-sdk.mk` | `customManagers` regex, `github-tags` datasource over `ip7z/7zip`, `loose` versioning. Only the `LZMA_SDK_VERSION` line is managed — `LZMA_SDK_SOURCE` derives from it via `$(subst)` in the .mk | `package/lzma-sdk/lzma-sdk.hash` — auto-refreshed by `renovate-hash-sync.yml`'s **bespoke lzma-sdk step** (release-*asset* URL, dots-stripped filename `7z2602-src.tar.xz`; does not fit the generic loop) |
| 3 sdcard payload pins (`update_all.sh`, `wifi.sh`, `_Console` cores snapshot; labeled `sdcard-payload-pin`) | `scripts/fetch-sdcard-payload.sh` (`PINNED_UPDATE_ALL_COMMIT`, `PINNED_WIFI_SH_COMMIT`, `PINNED_CORES_COMMIT`) | `customManagers` regex per pin, `git-refs` datasource tracking the upstream default branch HEAD via `currentDigest` (`theypsilon/Update_All_MiSTer`, `MiSTer-devel/Scripts_MiSTer`, `MiSTer-devel/Distribution_MiSTer`) | `PINNED_{UPDATE_ALL,WIFI_SH}_SHA256`/`_SIZE` in the same script — auto-refreshed by `renovate-hash-sync.yml`'s **bespoke sdcard-payload step**; the cores commit has no companion hash (cores are fetched by content — see the script's header) |
| CI container digests | `ubuntu:26.04@sha256:...` in `build.yml`, `release.yml`, `reproducibility.yml`'s `container:` blocks | Renovate's built-in `github-actions` manager, `docker` datasource, `pinDigests: true` | n/a — digest updates carry their own content-hash |
| GitHub Actions | every SHA-pinned `uses:` line (with a `# vX.Y.Z` comment) across `build.yml`, `release.yml`, `reproducibility.yml`, `publish-db.yml` | Renovate's built-in `github-actions` manager (no custom config needed — it already understands "SHA-pinned + trailing semver comment" and updates both together) | n/a |

That is **18 customManagers entries** (Buildroot, kernel, 9 driver commits,
munt, bcm20702-firmware — 10 commit pins in total once bcm20702 is counted —
libchdr, lzma-sdk, and the 3 sdcard payload pins)
plus the two built-in managers
(`docker` digests, `github-actions`), covering every version/commit/digest pin
this repository maintains by hand except the four listed below.

### Why `bcm20702-firmware` is a commit pin, not a tag pin

Changed 2026-07-19, for two independent reasons.

**The tag ordering was wrong, and it fired.** The `_pN` suffix is a patch level
*on top of* the base version, so `v12.0.1.1105_p4` is **newer** than
`v12.0.1.1105`. Renovate's `loose` versioning sorted the bare tag higher and
proposed `v12.0.1.1105` as an upgrade — a **2.5-year downgrade**
(`v12.0.1.1105` is from 2020-05-02; the pinned `_p4` is from 2022-10-10). The
`needs-manual-version-check` label was doing its job: a human caught it, and
automerge is off everywhere, so nothing bad merged.

**Upstream stopped tagging anyway.** The newest tag is from 2022-10-10, but
`master` is still active — three firmware commits on 2026-07-08 ("Add support
for multiple INF files", "Add build version of firmware", "Add 6.5.1.6820
retrospective version"). A tag pin could no longer see real updates at all.

Teaching `loose` a bespoke scheme (as `munt` does with a `regex:` versioning)
was the other option. A commit pin was chosen instead because it removes the
ordering question entirely rather than encoding a fragile rule about someone
else's tag conventions, and because it matches how the 9 other untagged
upstreams here are already pinned.

**Why this is safe despite tracking a branch:** the package installs exactly
**one** file, and the `.mk` carries an inline `sha256sum -c` of that `.hcd`
which fails the build **closed** if it ever changes. The switch itself was a
verified no-op — `brcm/BCM20702A1-0b05-17cb.hcd` is byte-identical at
`v12.0.1.1105_p4` and at `master` HEAD (`02204ae0…`, 35000 bytes, matching
stock). So this only unblocks *future* firmware updates; it changed nothing in
the image.

## What is deliberately NOT managed, and why

- **`package/xow-firmware`** — pins two Microsoft Windows Update driver
  `.cab` files by opaque GUID+commit-style identifiers
  (`1cd6a87c-...-e19f60808b...cab`). These are not a version or a git ref
  of any kind; there is no datasource that could meaningfully propose an
  "update" here. Left fully manual.

- **`package/cabextract`** (pinned at `1.11`) — sourced from
  `cabextract.org.uk`, a static project page with no machine-readable
  release feed (no JSON/Atom/tags API). Renovate's `customDatasources` can
  scrape `html`, but this is a stable, extremely low-churn C library used
  for exactly one firmware-extraction step; not worth the scraper
  maintenance burden right now. Left manual — revisit if this project's
  Renovate usage expands to `html`-format custom datasources for other
  reasons.

- **`package/linux-firmware-extra`** (pinned at `20251011`) — this is a
  **hard, deliberate coupling**, not just a missing datasource: its `.hash`
  file is copied verbatim from `work/buildroot/package/linux-firmware`'s own
  hash (see that package's `.mk`/`.hash` comments), because it deliberately
  re-downloads the *identical* upstream tarball Buildroot's own bundled
  `linux-firmware` package already pins, just keeping a different file
  subset. Bumping `LINUX_FIRMWARE_EXTRA_VERSION` independently of whatever
  version Buildroot's own vendored copy uses would fetch a **mismatched**
  tarball. This has to move in lockstep with a Buildroot-internal package
  version, which isn't something Renovate can see from outside the
  unpacked Buildroot tree. Left manual.

- **`release.yml`'s pinned stock reference archive**
  (`b8531c7848526d9a8227841923cc4a493cb6e631` /
  `release_20250402.7z`, referenced via a `raw.githubusercontent.com` URL in
  the `STOCK_RELEASE_URL` env var) — this is **not a dependency to bump**.
  It is a frozen compatibility pin: the whole point is that our
  `uboot.img`/`files/linux/` payload stays byte-identical to *this specific*
  stock release forever (see `release.yml`'s own header and
  `docs/downloader-contract.md` §8/§12). No manager in `renovate.json`
  matches a `raw.githubusercontent.com` URL, so this is excluded by
  construction, not by an explicit ignore rule — documented here so nobody
  "helpfully" wires one up later.

## The hash-sync mechanism (`.github/workflows/renovate-hash-sync.yml`)

Renovate can bump a version string or a commit SHA; it cannot recompute a
tarball's sha256 itself. Every pin above has a companion hash that must move
with it, or the build fails **closed** — safe, but the PR is red and useless
without a human intervening. `renovate-hash-sync.yml` closes that gap for
the cases where it can be done correctly and cheaply, and is explicit about
the one case where it deliberately does nothing.

**Triggers on**: `pull_request` (opened/synchronize), only when
`github.actor == 'renovate[bot]'` and the PR's head repo is this repo (never
a fork — a fork PR's default token cannot push back to it anyway). It always
recomputes from the branch's current file content and only commits if the
result actually differs, so re-runs on an already-correct PR are harmless
no-ops.

**...and manually**, via `workflow_dispatch` with a required `branch` input.

This escape hatch is not a convenience — without it there is **no way at all**
to re-drive this workflow after fixing a bug in it. Three things block every
other route, and all three held at once on
[run 29669946883](https://github.com/mcfbytes/Buildroot_MiSTer/actions/runs/29669946883),
which executed the same broken kernel-URL code three times across two separate
fixes:

| route | why it fails |
|---|---|
| push the fix to the branch | the `paths:` filter doesn't list the workflow file, so nothing triggers |
| a maintainer merges the fix in | the `renovate[bot]` actor gate skips the job |
| re-run the failed run | a re-run replays the workflow definition from the commit the *original* run was created against — so it re-executes the old code |

Only Renovate itself moving the branch head, or this manual trigger, gets new
code to run.

> **The ref you dispatch *from* and the branch you dispatch *at* are different
> things, deliberately.** GitHub runs the workflow definition from the ref you
> dispatch on, while this workflow checks out and pushes to `inputs.branch`.
> So dispatch **from the default branch** (which has the fixed workflow) and
> put the branch you want *repaired* — e.g.
> `renovate/kernel-longterm-6.18-6.x` — in the input. Dispatching *on* the
> stale branch would just run its stale copy again, which is the whole trap.

Manual runs refuse to target the default branch: this workflow commits and
pushes, and an auto-generated hash commit must go through a PR. `workflow_dispatch`
is already restricted to collaborators with write access, so this does not
widen who can drive the workflow.

The input must be a **plain branch name**, not a ref. git resolves several
spellings to the same branch — `master`, `refs/heads/master` and `heads/master`
all push to `master` (verified with `git push --dry-run`) — so a naive string
comparison against the default branch is only sound once the ref forms are
excluded. They are rejected outright rather than normalised, because the same
value is consumed by both `actions/checkout` and the final `git push`: what gets
validated has to be exactly what those steps use. The name is also run through
`git check-ref-format --branch`, which rejects embedded spaces, `..`, a leading
`-`, and the rest.

**What it fixes automatically, and why each case is safe:**

1. **The 12 github-archive `.hash` files** (the 9 commit pins + munt +
   bcm20702-firmware + libchdr — the last a userspace shared library from
   the Main_MiSTer shared-lib refactor, but the exact same
   `$(call github,...)` tarball shape as the driver pins). Every one of
   these `.hash` files' own header comment
   already documents that GitHub publishes no signed manifest for a
   commit/tag archive tarball, and that a **locally-computed** `sha256sum`
   of a freshly-fetched tarball from the real pinned owner/repo/ref is
   standard, accepted practice here (see e.g. `package/xone/xone.hash`).
   Automating exactly what a human already does by hand is safe. The
   workflow parses `<PKG>_VERSION` and the `$(call github,owner,repo,...)`
   line out of each `.mk`, downloads
   `https://github.com/<owner>/<repo>/archive/<version>.tar.gz`, and rewrites
   only the tarball's own hash line (never touching a `LICENSE`/other-member
   line beneath it).

2. **The kernel tarball hash**
   (`board/mister/de10nano/patches/linux/linux.hash`) — derived under **two
   independent PGP signatures**, both verified against public keys committed
   in `.github/keys/` (never fetched at run time). See
   [ADR 0022](decisions/0022-kernel-hash-gpg-verification.md) for the full
   rationale.

   * **path A** — `linux-<version>.tar.sign`, signed by the stable
     maintainer (Greg Kroah-Hartman, fingerprint cross-checkable against
     <https://www.kernel.org/signature.html>). The `.sign` covers the
     *uncompressed* tar, so the workflow decompresses the `.tar.xz` it
     actually downloaded and verifies that stream, then computes the
     `.tar.xz` sha256 itself.
   * **path B** — `sha256sums.asc`, signed by the kernel.org checksum
     autosigner, parsed **only** from the plaintext gpg emits after
     verifying (never grepped from the raw `.asc`, which would make the
     check decorative).

   Both must verify **and agree on the hash**, or the step fails hard and
   refuses to touch `linux.hash`. Verification is pinned by *fingerprint*
   via gpg's `--status-fd` `VALIDSIG` line, not by exit status or
   human-readable output. A signature failure is treated as a supply-chain
   event and is never downgraded to the warn-and-skip path used for network
   errors.

   Note the asymmetry recorded in ADR 0022 §4: the maintainer key's
   fingerprint is published by kernel.org, while the autosigner key is
   **TOFU-pinned** — kernel.org publishes neither that key nor its
   fingerprint. Path B is corroboration, not the foundation; kernel.org
   itself says the checksums are "NOT intended to replace developer
   signatures".

3. **The lzma-sdk tarball hash** (`package/lzma-sdk/lzma-sdk.hash`) — a
   **bespoke step**, because lzma-sdk cannot ride the generic loop of
   case 1: its tarball is a GitHub release **asset**
   (`https://github.com/ip7z/7zip/releases/download/<ver>/...`), not a
   commit/tag archive, and the filename derives from the version with the
   dots stripped (`LZMA_SDK_SOURCE = 7z$(subst .,,$(LZMA_SDK_VERSION))-src.tar.xz`,
   so `26.02` → `7z2602-src.tar.xz`). The trust model is the same as
   case 1's — upstream publishes **no checksums anywhere** (no checksum
   assets, none in the release body, none on 7-zip.org; checked at pin
   time, per the `.hash` file's own header), so a locally-computed
   `sha256sum` of the freshly-fetched asset is the legitimate source. The
   step derives the asset URL from the PR's new `LZMA_SDK_VERSION`,
   downloads it, and rewrites **only the first `sha256` line** of the
   `.hash` file — the `DOC/License.txt` / `DOC/readme.txt` provenance lines
   beneath it are never touched.

4. **The sdcard payload script pins** (`scripts/fetch-sdcard-payload.sh`) — a
   second **bespoke step**: `update_all.sh` (theypsilon/Update_All_MiSTer)
   and `wifi.sh` (MiSTer-devel/Scripts_MiSTer) are pinned by commit **and**
   by sha256+size in the same script. Renovate's `git-refs` managers bump
   the `PINNED_*_COMMIT` values; the step then fetches the raw file at the
   new commit and rewrites the `PINNED_*_SHA256`/`_SIZE` lines in place —
   the same fetch-and-hash practice as case 1. The `_Console` cores snapshot
   commit (`PINNED_CORES_COMMIT`) has no companion hash and is deliberately
   not handled (individual cores are fetched by content — see the script's
   own header).

**What it deliberately does NOT fix:**

- **`BUILDROOT_SHA256`** (root `Makefile`). Per the Makefile's own header
  comment, this value is legitimate **only** when transcribed from
  Buildroot's GPG-signed release manifest
  (`https://buildroot.org/downloads/buildroot-<version>.tar.gz.sign`). A
  locally-computed `sha256sum` of the downloaded tarball is explicitly
  forbidden there — it would be circular (it blesses whatever bytes were
  received, tampered or not) and defeats the entire point of pinning a
  hash. `renovate-hash-sync.yml` will not invent this value.

  **The manual step, every time Renovate bumps `BUILDROOT_VERSION`:**

  ```
  make buildroot-showsig BUILDROOT_VERSION=<new-version>
  ```

  Take the `SHA256:` line from that signed manifest and paste it into
  `BUILDROOT_SHA256` in the `Makefile`, on the same PR branch, then push.
  Until that happens, the PR is **expected** to be red — `make
  buildroot-verify` (invoked by `make all` in CI) fails loudly and exactly
  names this fix in its own error message. **A red PR here is the safe
  failure mode, not a bug**: it is strictly better than a green PR that
  quietly ships a wrong/unverified hash.

## Automerge: OFF, everywhere

`automerge: false` and `platformAutomerge: false` are set at the top level
of `renovate.json` and nothing in `packageRules` overrides them. Every green
PR — Buildroot, kernel, driver pins, container digests, GitHub Actions —
requires a human to click merge. This is a hard project requirement, not a
default left in place by accident.

## Confirmed: every Renovate PR triggers the full build+test CI

`build.yml` (P4.1) triggers on `push` **and** `pull_request` with no branch
filter — so a Renovate PR (like any other PR) automatically runs the full
two-stage Buildroot build, `scripts/ci-tests.sh` (the P3.12 parity suite),
and the ABI/SONAME checker. For the kernel specifically, this is the whole
mechanized point (PLAN.md §13): a patch-apply break in any of the carried
Linux patches turns the PR **red** the moment `make all` tries to build the
bumped kernel source, before a human ever needs to notice by hand.

**One gap, carried over from a previous phase's own deliberate decision, not
introduced here:** `reproducibility.yml` (P4.3) is `workflow_dispatch`-only —
its own header explains why (a double build is 2x the cost of build.yml,
and wiring it to every `pull_request` would burn three cold Buildroot builds
in parallel on every commit). It does **not** auto-run on a Renovate PR. For
a Buildroot or kernel bump specifically — the two pins most likely to affect
reproducibility — a maintainer should manually dispatch it before merging:

```
gh workflow run reproducibility.yml --ref <renovate-branch>
```

This is flagged, not silently worked around, because reproducibility.yml's
manual-only trigger was a considered cost trade-off from P4.3, and
overriding it here would be a scope-creep decision this task shouldn't make
unilaterally.

## Unverified / what to check on first run

None of the following has been exercised against a live Renovate instance
(the repo isn't onboarded yet — see "Status" above). Check these first, in
roughly this priority order, once Renovate actually runs:

1. **The `customDatasources.kernelLongterm618` JSONata transform.** Written
   by hand against kernel.org's documented `releases.json` shape
   (`{"releases": [{"version": "...", "moniker": "longterm", ...}, ...]}`);
   never evaluated by a real Renovate JSONata engine. If the kernel PR never
   appears, check this first — the Renovate Dependency Dashboard issue will
   show a lookup error if the transform is malformed.
2. **`fileMatch` vs `managerFilePatterns`.** This config follows the
   `/mnt/source/sb-enema/renovate.json` reference template's use of
   `fileMatch` for `customManagers`. Renovate has been migrating this key to
   `managerFilePatterns`; if Renovate auto-opens a `renovate/config-migration`
   PR renaming these keys, that is expected and safe to accept.
3. **The `git-refs` `currentValueTemplate` branch names** (`main` vs
   `master`, and `aircrack-ng/rtl8188eus`'s unusual `v5.3.9` default branch,
   verified via `git ls-remote --symref` at authoring time, 2026-07-13). If
   any of these upstreams ever renames its default branch, that one
   manager will silently stop finding new commits (not fail loudly) until
   this file is updated.
4. ~~**`winterheart/broadcom-bt-firmware`'s tag ordering.**~~ **Resolved
   2026-07-19 by switching to a commit pin** — the concern was real and it
   fired. See "Why this one is a commit pin" below.
5. **`renovate-hash-sync.yml`'s push permissions.** Assumes Renovate opens
   PRs from branches in this repo (not a fork), which is standard for the
   GitHub App/Mend-hosted integration once installed directly on this repo.
   If that assumption is ever wrong, the workflow's own repo-equality guard
   makes it a no-op rather than a confusing permission-denied failure.

## `git-submodules` is enabled but currently inert

`renovate.json` turns on Renovate's built-in `git-submodules` manager (as
the `/mnt/source/sb-enema/renovate.json` reference does for its
`secureboot_objects` submodule). As of this writing, **this repository has
no git submodules** — the setting is a harmless no-op today. It is left on
because Phase 5 planning (see the `phase5-plan-uboot-fork` branch) already
scopes a `u-boot_MiSTer` fork as a submodule pin; when that lands, Renovate
will start tracking it automatically with no further `renovate.json` change
required.

## Kernel/Buildroot bump scope, restated

Both the Buildroot and kernel `customManagers` entries are intentionally
narrow: `allowedVersions` locks Buildroot to the `2026.02.x` line and the
kernel to `6.18.y`. Neither is meant to propose a Buildroot major/minor
bump or a kernel LTS-line change — those are larger undertakings (new
toolchain defaults, a fresh patch-carry audit) that deserve a deliberate,
human-initiated upgrade, not a routine Renovate PR.
