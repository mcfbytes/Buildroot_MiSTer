# db.json versioning: why `linux.version` is release-date-driven, not image-version-driven

**Task:** P4.5. **Depends on the facts established in:** `docs/downloader-contract.md`
§1/§3/§12 (P0.6), and the "OPEN QUESTION" flagged in `.github/workflows/release.yml`'s
"derive RELEASE_DATE" step (P4.4, `phase4-release-eng` branch). **Consumed by:**
`scripts/gen-db-json.py`, `.github/workflows/publish-db.yml`.

## The problem

The Downloader decides whether to apply a Linux update with a **strict string
inequality**, not an ordering comparison (`docs/downloader-contract.md` §3):

```python
current_linux_version = self.get_current_linux_version()   # reads /MiSTer.version
if current_linux_version == linux['version'][-6:]:
    return  # no update
```

`/MiSTer.version` is written at build time by `board/mister/de10nano/post-build.sh`,
which derives its 6-byte `YYMMDD` stamp from `SOURCE_DATE_EPOCH`. `configs/
mister_de10nano_defconfig` pins `SOURCE_DATE_EPOCH` to **Buildroot's own last-commit
date** — fixed as long as `BUILDROOT_VERSION` doesn't change (that pin is exactly what
makes two independent builds of the same commit byte-identical, P2.5/A9's reproducibility
requirement).

Consequence: **every release built from the same `BUILDROOT_VERSION`** — which will be
the common case (kernel-only bumps, package bumps, driver/config changes — anything
short of a Buildroot point-release bump) — **bakes the IDENTICAL `/MiSTer.version`.** If
`db.json`'s `linux.version` were derived from that same baked-in value (or from the
`release_YYYYMMDD.7z` filename, which `release.yml` itself derives from it, for a
different, narrower reason — see that file's own comment), two such releases would
publish an **identical** `version` string. A user already on release N, checking for
release N+1, would see no difference and never be offered it.

## The chosen mitigation

`scripts/gen-db-json.py` derives `linux.version` from the **release's own real-world
publish date** (`--published-at`, the GitHub Release's `publishedAt` timestamp — see
`.github/workflows/publish-db.yml`) — **not** from `/MiSTer.version` and **not** from the
archive filename. `linux.hash`/`linux.size` are computed from the actual uploaded
`release_YYYYMMDD.7z` asset, which **does** differ release-to-release whenever the
content differs, regardless of what `/MiSTer.version` says.

This guarantees: as long as two releases aren't published on the same calendar day (UTC),
their `db.json` `version` strings differ from each other, and — because the baked-in
`/MiSTer.version` is some fixed date drawn from Buildroot's own commit history, unrelated
to our real-world release calendar — from the currently-installed value on any device that
already updated. **The Downloader's inequality check fires, and the update proceeds.**
This is the fix for "a new release never gets offered."

## The residual trade-off (flagged, not silently resolved)

Because `linux.version` is now **decoupled** from `/MiSTer.version`, the inverse failure
mode is traded in: after a device installs one of our releases, its on-device
`/MiSTer.version` is whatever `post-build.sh` baked in (constant, per above) — it does
**not** advance to match whatever `db.json` said at the time. On the **next** Downloader
run, if `db.json` hasn't changed (no new release yet), the comparison is still
`<baked-in constant> != <last-published db.json version>` — which was already true before
the update, and remains true after it. **The update looks "available" again, every single
run, until the next real release changes `db.json`'s version** (which only delays, rather
than resolves, the same comparison).

Practically: this is not a *correctness* bug (the same, already-current archive just gets
re-downloaded, re-verified, and re-flashed — content-identical, per `docs/
downloader-contract.md` §7's `rsync` semantics) but it is a **wasteful and non-trivial
side effect worth naming plainly**:
* every scheduled Downloader run re-downloads the ~90+ MB archive;
* `updateboot` re-runs unconditionally on every such "update," which **erases U-Boot's
  saved environment at sector 1 and re-flashes `uboot.img`** every time (`docs/
  downloader-contract.md` §8) — cycling writes to the boot partition far more often than
  a real content change would justify;
* the reboot flag gets raised on every run, so an affected device may reboot on a schedule
  that has nothing to do with whether anything actually changed.

This is the same *family* of problem `docs/downloader-contract.md` §3 calls "the
exact-byte-match hazard" (a mismatched `/MiSTer.version` makes the inequality permanently
true) — here the mismatch is a **deliberate, chosen trade-off** rather than a whitespace
bug, made because the alternative (never offering a new release to an already-updated
device) was judged worse. **This should not be considered a closed question.** The
durable fix belongs in `post-build.sh`/`configs/mister_de10nano_defconfig` (P2.6), not
here: have `post-build.sh` accept a build-time override (e.g. an env var the release
workflow sets to that release's own real date) for `/MiSTer.version` specifically, while
leaving `SOURCE_DATE_EPOCH` itself pinned for every *other* reproducibility guarantee
(file mtimes, ext4 superblock timestamps) it protects. That change is out of scope for
P4.5 (no Buildroot build, no changes to files owned by P2.6/P4.4) and is called out here
so a human decides on it — and, ideally, lands it — **before two real releases ship
back to back** from an already-subscribed user base.

## Summary

| | Derived from | Distinct per release? | Matches on-device value after install? |
|---|---|---|---|
| `/MiSTer.version` (baked into the image) | `SOURCE_DATE_EPOCH` = Buildroot's pinned commit date | No (constant per `BUILDROOT_VERSION`) | — |
| `db.json` `linux.version` (this task, chosen) | The GitHub Release's real publish date | Yes (barring same-day releases) | No — decoupled by design; see trade-off above |
| `db.json` `linux.version` (rejected alternative) | `/MiSTer.version` / the archive filename | No — the original bug | Yes, but never triggers a second update |

Both columns can't simultaneously be "yes" without a P2.6 change to how
`/MiSTer.version` itself is derived. This task picks the column that keeps updates
flowing, and documents the cost.
