# CI pipeline reference

This is the relocation target for the detailed rationale, incident history, and
measured numbers that the workflows and composite actions keep out of their
inline comments. Every inline comment of the form `See docs/ci.md#<anchor>`
points at a section here. The split rule: an inline comment keeps the
imperative ("MUST", "NEVER", a trap warning) plus the run ID that makes it
credible, and this document keeps the narrative, the measurements, and the
"we tried X and it failed" reasoning behind it.

Read top-to-bottom once: orientation, then the shared build recipe, then
caching (the biggest trap cluster), then each workflow, then cross-cutting
conventions, then the incident index.

This file lives in `docs/` alongside two documents that cover adjacent but
distinct ground and are deliberately not folded in here: `docs/renovate.md`
(the Renovate onboarding policy — what `renovate.json` manages, the
automerge posture, the hash-provenance rules a human must follow by hand)
and `docs/reproducibility.md` (the A9 constraint itself — what "byte-identical
across two builds" means and why it matters, as opposed to how
`reproducibility.yml` mechanically proves it, which is Part VII below). Where
this document explains a workflow's mechanics, it cross-links the constraint
or policy document rather than restating it.

---

## Part I — Orientation

<a id="pipeline-map"></a>
### Pipeline map

Five workflows, one shared build recipe:

- **`build.yml`** — runs on every push to `master` and every PR. Builds the
  image with `.github/actions/buildroot-build`, builds the PREEMPT_RT kernel
  variant matrix first (`build-kernel`), runs the parity/ABI suite, uploads CI
  artifacts. See [`#gate-vs-paths-ignore`](#gate-vs-paths-ignore) for the
  trigger design.
- **`release.yml`** — runs on `v*` tags (plus a manual dispatch for the opt-in
  full sdcard image). Rebuilds from scratch rather than adopting `build.yml`'s
  run (see [`#rebuild-not-adopt`](#rebuild-not-adopt)), assembles
  `release_YYYYMMDD.7z`, and publishes a draft GitHub Release.
- **`publish-db.yml`** — triggers on the release being *published* (not
  drafted). Regenerates and deploys `db.json` to GitHub Pages, which is the
  only thing the on-device Downloader actually reads.
- **`reproducibility.yml`** — manual-only double build that proves two
  independent builds of the same commit are byte-identical.
- **`renovate-hash-sync.yml`** — triggers on a Renovate PR, refreshes the
  companion `.hash` files a version/commit bump invalidates.

`lint.yml` and `fork-sync.yml` lint the CI itself and watch the upstream
kernel fork; they don't build anything.

<a id="recipe-boundary"></a>
### Caller vs recipe ownership boundary

`.github/actions/buildroot-build` owns everything from "make the runner able
to build" through "the variant's images exist in `output/images/`ν(main) or
`output-<name>/images/`" (kernel variant). The caller owns what is genuinely
its own: which ref to check out, and what to do with the images afterwards.

The same split applies to `.github/actions/kernel-leg`: it owns the build +
job-summary + artifact-staging steps; the caller owns `runs-on`,
`timeout-minutes`, `strategy.matrix`, `needs`, `if`, and its own `Checkout`
step. A composite action cannot set any of those (they're per-job wiring, not
part of the recipe's body), and `uses: ./.github/actions/kernel-leg` only
resolves once the repo running it is already checked out.

<a id="why-shared-recipe"></a>
### Why one shared build recipe

`build.yml`, `release.yml` and `reproducibility.yml` each had their own
copy-pasted version of the build steps. `build.yml` then took **five failed
runs** to get right:

- ENOSPC (no disk reclaim)
- missing defconfig step
- root-configure ordering
- busted toolchain caches (twice, different causes)

None of those five fixes reached the other two workflows, which would each
have failed the same way the first time anyone pushed a tag or ran the
reproducibility check. That is the whole case for `.github/actions/buildroot-build`:
the recipe is subtle, hard-won, and must exist exactly once. Read its header
before touching how the build runs.

The same duplication existed for the kernel-variant leg (measured 85 vs 91
code lines with comments stripped, 72 identical between `build.yml`'s and
`release.yml`'s copies) and for the parity/ABI verification trio — both are
now `.github/actions/kernel-leg` and `.github/actions/verify-image`
respectively, for the identical reason.

<a id="no-container-disk-reclaim"></a>
### No `container:`, and why disk reclaim must run first

A stock GitHub-hosted runner has ~14 GB free; `output/` alone is 24 GB. Run
**29295920820** died 1h37m in with ENOSPC in host-gcc. The fix — reclaiming
the ~30 GB of preinstalled toolchains the build never uses — moves the runner
from ~16 GB free to ~40 GB free, and it MUST run first, before any other step
touches disk.

This is also why no job that builds the image may use `container:`: the
preinstalled software being reclaimed lives on the runner **host**, which a
container job cannot reach to delete. `rm` is used directly rather than a
third-party action, to avoid another supply-chain dependency; `df` runs
before/after so a future disk regression shows up in the log instead of as a
mysterious compiler error 90 minutes in.

`reproducibility.yml`'s two-leg matrix relies on this too — it does not
weaken the "two independent builds" comparison: the environment is still held
constant across both legs (same runner image, same shared action), and
Buildroot bootstraps its own host toolchain from pinned sources anyway, so the
distro does not leak into the target output.

---

## Part II — Variants and the kernel-only build

<a id="variants"></a>
### Variants: main vs kernel-only

The `variant` input to `.github/actions/buildroot-build` selects which build
the recipe runs:

- **`main`** (the default) — the two-stage 6.18 image. Byte-identical
  behavior, and byte-identical cache **key strings**, to before the `variant`
  input existed, so existing callers (`reproducibility.yml` passes no inputs)
  and existing cache entries are unaffected.
- **Any other name** is a KERNEL-ONLY variant (ADR 0021 as amended
  2026-07-18). It must have a fragment at `configs/mister_<name>.fragment`,
  and *fragment existence is the entire registry*: everything else — the make
  targets (`make <name>`, `<name>-legal-info`, `<name>-external-deps`), the
  output dir (`output-<name>/`), the cache key namespaces
  (`br-dl-<name>-*`, `br-<name>-host-*`) — is derived from the name.

Adding a kernel variant to CI is therefore **one fragment + the Makefile
targets, with no change to the composite action and no workflow matrix entry
to add either**: `build.yml` and `release.yml` each derive their `kernel:`
matrix from this same fragment registry via `scripts/list-kernel-variants.sh`,
so this existence check IS the registry both matrices read.

Validation happens **once**, in `buildroot-build`'s fingerprint step, before
any cache is restored or any build work starts, so a typo'd variant dies in
seconds rather than after a multi-hour build. The character whitelist on the
variant name keeps a hostile/typo'd value from ever reaching a path or cache
key. Everything variant-shaped downstream (step-level `if:`s, cache
keys/paths, which make targets run) reads the env this step computes once —
same compute-once/consume-twice reasoning as the cache keys
([`#cache-keys`](#cache-keys)).

A kernel variant builds `configs/mister_kernel_defconfig` + its fragment:
`zImage_dtb` plus a depmod'd module tree in `output-<name>/`, sharing `dl/`
and ccache with main but its own host-toolchain cache (a cross-toolchain
bakes its absolute `O=` path in, so `output/host` and `output-<name>/host` can
never share a cache entry). There is no configure step for variants (`make
<name>` generates `output-<name>/.config` itself and it is never cached, so it
can never be stale — see [`#configure-buildroot`](#configure-buildroot)), but
the initramfs stage DOES run: every kernel embeds the stage-1 cpio
(`external.mk`'s fixup applies to any `BR2_LINUX_KERNEL=y` build; a zImage
without it cannot boot).

`configs/mister_kernel_defconfig` is a manually mirrored **copy** of the main
defconfig's toolchain/kernel stanzas. `scripts/check-kernel-defconfig-sync.sh`
asserts the copy has not drifted, and it runs in **two** places: inside
`buildroot-build`'s fingerprint step (before any cache work — a drifted
toolchain stanza would build wrong under a cache key that then pins the wrong
toolchain in) and again as its own step in `build.yml`'s `build` job, which
catches the main-only edit path (main defconfig changed, mirror forgotten) in
seconds rather than waiting for a kernel leg to fail.

What still needs a hand-edit for a new variant (nothing above does): the
release-notes prose in `release.yml`'s `publish` job (a human-readable
description of what the variant is) and `scripts/mk-sdcard.sh`'s single
hardcoded bonus-kernel slot (one card, one bonus kernel, by that script's own
design, not a variant list). See `docs/rt-beta-kernel.md`'s "Adding a future
kernel variant" paragraph for the full accounting.

<a id="kernel-variant-matrix"></a>
### Kernel-variant matrix design

`build-kernel` (both workflows) runs a one-job matrix, one leg per kernel
variant, **before** the main `build` job, because `build` merges every leg's
depmod'd module tree into the ONE shipped `linux.img` (via
`.github/actions/merge-kernel-modules`).

Each leg hands the matrix's caller an artifact carrying: `zImage_dtb-<name>`,
`linux-<name>.config`, the depmod'd modules tar + its kernel version, and
`legal-info-<name>.tar.gz`. What's *inside* that legal-info tarball differs
by caller:

- `build.yml`'s leg (`full-legal-info: false`) ships a **manifest-only SBOM**
  — a CI push distributes nothing, so the GPL source tarballs stay out.
- `release.yml`'s leg (`full-legal-info: true`) ships the **FULL kernel
  GPL-source bundle** (~250-300 MB) — a release DISTRIBUTES the variant
  kernel binary, so the source obligation is real.

No `MISTER_VERSION` derivation happens in a kernel-only build: there is no
rootfs to write `/MiSTer.version` into, and the duplicate derivation step the
old two-image release design carried (see
[`#old-two-image-design-retired`](#old-two-image-design-retired)) is gone,
not forgotten.

Downstream in `release.yml`'s `publish` job, the release asset list and the
provenance attestation `subject-path` are also derived (globbed off `dist/`,
not named), so adding a variant needs no edit there either.

<a id="build-step"></a>
### Build step & fail-in-CI-not-on-device

`make all`'s recipe is `all: initramfs ...`, so **one invocation builds both
stages**: the static-musl initramfs and the main glibc rootfs + kernel +
`linux.img`. `BR2_CCACHE` propagates through `MAKEFLAGS` to both sub-builds,
so the musl toolchain gets ccache too — musl and glibc objects have distinct
ccache keys, so they coexist safely in one cache.

`MISTER_VERSION`, if the caller exported it to `$GITHUB_ENV` (`release.yml`
does, per ADR 0018), is inherited here and baked into `/MiSTer.version` by
`post-build.sh`. Left unset everywhere else, which keeps ordinary builds
reproducible (see [`#repro-mister-version-unset`](#repro-mister-version-unset)
for why that matters specifically to `reproducibility.yml`).

For a kernel variant, `make <name>` runs the stage-1 initramfs (a prerequisite
of every kernel target — its cpio is embedded into the zImage) followed by
the kernel-only Buildroot build into `output-<name>/`, ending by staging the
variant's depmod'd module tree into `work/extra-modules-overlay/` (unused by
this action's own job; the CALLER ships the tree via the kernel artifact
instead). The Makefile's variant target **hard-asserts** the built kernel's
config (e.g. RT's `CONFIG_PREEMPT_RT=y`), so a fragment regression fails
**here, loudly, in CI** — not silently on a device.

<a id="configure-buildroot"></a>
### Configuring Buildroot

Buildroot needs `output/.config` before `make all`. A fresh checkout has only
the tracked defconfig, so the build dies instantly with "Please configure
Buildroot first" — run **29293209070** failed exactly there, **after a
52-minute stage 1**. `output/.config` is therefore regenerated
**unconditionally on every run**: the defconfig is the reproducible source of
truth, and doing it every time also stops a stale cached `output/.config`
from silently overriding a defconfig change.

This step is MAIN-ONLY: `make <variant>` generates `output-<variant>/.config`
itself (kernel-only defconfig + `merge_config.sh` of the variant fragment),
and no cache ever carries a variant `.config`, so it regenerates fresh every
run — the staleness this step exists to prevent cannot occur for a kernel
variant in the first place.

---

## Part III — Caching (read this part in order; the sections are interdependent)

<a id="cache-budget-and-sizing"></a>
### Cache inventory & budget

Five input caches restore/save across the build: the Buildroot release
tarball, `dl/` (package sources), the variant's host cross-toolchain, the
initramfs host toolchain, and ccache. Mind GitHub's **10 GB per-repo LRU
ceiling** — it evicts least-recently-used entries once the repo crosses it.

Measured on the first green cold run (**29300460591**, 4-vCPU
`ubuntu-latest`):

| Metric | Value |
|---|---|
| wall time | 3h19m47s cold |
| `output/` | 24 GB — the reason the container had to go |
| `dl/` | 2.7 GB |
| ccache | 1.1 GB of a 4 GB cap (28%, no evictions) |
| disk at end | 8.4 GB free of 72 GB |

**ccache IS working as designed — before "fixing" a small cache, read this
section.** Warm run **29529993571** reported **34945 hits / 34967 cacheable
calls — 99.94%, 22 misses** — at 0.8 GB of the 4 GB cap. The three sizes you
will see for "the ccache" are all the same data: ~0.8 GB of real payload, 664
MiB as the zstd cache entry (ccache 4.x already compresses its objects, so
the tarball barely shrinks), and ~1.1 GB from `du`, which rounds ~35k small
objects up to 4 KB blocks. **The ceiling here is the NUMBER of distinct
compilations, not the length of the build**: ~35k objects at ~23 KB each is
~0.8 GB and that is the whole population. Nor is the 4 GB cap the constraint
— at 21-28% it has never evicted.

Warm runs are also **smaller** than cold ones on purpose: the host-toolchain
cache (#3) restores `output/host` WITH its per-package stamps, so host
gcc/binutils/glibc never invoke a compiler at all and never reach ccache. The
two caches are substitutes for each other. A small ccache next to a healthy
`br-host` cache hit is the system working, not a leak.

**Now that variants share the 10 GB ceiling:** main's set is ~7 GB (2.7 GB
dl + ~3 GB br-host + br-initramfs-host + ~0.7 GB ccache + the tiny tarball).
Each kernel variant adds ~2-3 GB (`br-<name>-host` — the cross-toolchain
dominates it) plus up to ~3 GB (`br-dl-<name>` — its content mostly overlaps
`br-dl`, but GitHub cache entries are opaque blobs, so overlap is not
deduplicated). That can put the repo over the ceiling, which is survivable by
design: eviction is LRU, every cache here is a pure accelerator, and an
evicted entry means a cold, self-healing rebuild (see
[`#cache-coupling`](#cache-coupling)), never a wrong one. If eviction thrash
ever hurts, the cheapest levers in order: shrink `ccache-max-size`, then drop
the variant `dl/` SAVE (the restore-keys fallback to the main `dl/` prefix
keeps variant builds mostly warm for free — see
[`#variant-dl-fallback`](#variant-dl-fallback)).

<a id="ws-fp"></a>
### WS_FP: the workspace-path fingerprint

`WS_FP` fingerprints the workspace path. A Buildroot cross-toolchain bakes its
prefix/sysroot in as an **absolute path** — it is NOT relocatable (proof:
`make sdk` ships a `relocate-sdk.sh` precisely because of this). Restoring a
toolchain built at `/__w/...` into a build at `/home/runner/work/...` hands
you a subtly broken compiler. Keying the toolchain caches on the workspace
path means any future move auto-busts them, instead of relying on a human to
remember to bump a hand-maintained suffix.

ccache does **not** need this — it IS relocatable, via
`BR2_CCACHE_USE_BASEDIR` passed to `make`.

<a id="toolchain-fingerprint"></a>
### Toolchain fingerprint: deny-list, not allow-list

Hashing the *whole* defconfig would evict the 1-3 GB cross-toolchain on every
package add (`BR2_PACKAGE_NANO=y` → a 3h20m cold rebuild, for a package that
cannot touch the compiler). The obvious fix — an **allow-list** of
"toolchain-ish" symbols — is the wrong *shape*, and the first version of this
code proved it: the pattern `^BR2_(...|ARM|CPU|arm)` silently missed
`BR2_cortex_a9=y`, which is lowercase and starts with neither. Switching a9 →
a7 keeps every NEON/VFP line identical, so the fingerprint would not have
changed, the cortex-a9 toolchain would have been restored **with its stamps**,
and every target binary would have been built with the wrong `-mcpu`.
Silently.

So invert it: hash everything **except** what provably cannot affect the
toolchain. The asymmetry is the whole point —

- a wrong DENY-list over-busts → a wasted rebuild. Safe.
- a wrong ALLOW-list under-busts → a stale, WRONG compiler, which Buildroot
  does not detect (it wants a `make clean`). Not safe.

Excluded, with reasons:

- `BR2_PACKAGE_*` — target packages; cannot change the compiler. A restored
  `output/host` that is merely incomplete is self-healing — a missing
  host-* package has no stamp, so Buildroot simply builds it.
- `BR2_LINUX_KERNEL_*` — the kernel we build (including the version bumped
  monthly). Distinct from `BR2_KERNEL_HEADERS_*` (the headers glibc is
  compiled against), which is **not** excluded and correctly still busts the
  cache.

Comments are stripped **before** filtering: these defconfigs are heavily
annotated, with both trailing comments (`BR2_ROOTFS_MERGED_USR=y  # why`) and
indented continuation lines, and most of those annotations hang off the
`BR2_PACKAGE_` lines being excluded. Keeping them would mean editing a
comment about a WiFi driver evicts the cross-toolchain and costs a 3h20m
rebuild. Only a `#` that begins a line or follows whitespace is treated as a
comment marker (values like the ext2 `MKFS_OPTIONS` contain `^` and `,` but
never a bare `#`), so this cannot corrupt a symbol's value.

Which defconfig gets fingerprinted is the variant's: main hashes the image
defconfig; a kernel variant hashes the kernel-only base
(`configs/mister_kernel_defconfig` — whose filtered residue is a non-empty
toolchain stanza, so the sentinel assert below holds for it too) and then
appends its fragment's residue. Kernel variants run the SAME strip/filter
over the variant's fragment and append. TODAY this appends nothing for `rt` —
the fragment only carries `BR2_LINUX_KERNEL_*` lines, all deny-listed above —
and that is the deny-list doing its job, not a bug: a kernel-version bump in
the fragment cannot evict the variant's cross-toolchain, while any future
fragment line that COULD affect it (say a `BR2_KERNEL_HEADERS_` change)
correctly busts that variant's key and only that key.

But "selected zero lines" is `grep` exit 1, and this step's shell runs with
`pipefail` — supplied by GitHub's own `shell: bash` invocation (`bash
--noprofile --norc -eo pipefail {0}`, composite steps included), **not** by
the `set -eu` at the top of the script — so the empty (correct!) result must
be tolerated explicitly or the whole variant dies right here. `|| [ $? -eq 1
]` converts exactly that exit into success while a real grep failure (exit
>= 2) still aborts the step. The defconfig filter above needs no such guard:
its residue is asserted non-empty by the sentinel assert, for main and kernel
defconfigs alike.

Fail loud if the defconfig is ever renamed/reformatted such that this
produces an empty or degenerate fingerprint: a frozen cache key is the worst
outcome available here. The sentinel assert checks the two lines
(`^BR2_arm`, `^BR2_cortex`) that no ARM defconfig can lack and that nothing
legitimate ever removes.

<a id="cache-keys"></a>
### Cache keys: compute once, consume twice

The two toolchain cache keys (`BR_HOST_KEY` and the initramfs key) are
computed **once**, in the fingerprint step, and consumed by both a restore
step and a save step further down. They used to be written as inline
`hashFiles(...)` expressions, which was fine while one combined
`actions/cache` step did both halves — but restore and save are separate
steps now (see [`#cache-save-policy`](#cache-save-policy)), and a key
duplicated across two steps is a key that can be edited in one of them. The
failure mode is silent: restore looks under one key, save writes another,
nothing ever hits again, and the only symptom is a build that is
mysteriously always cold. Compute once, reference twice.

`sha256sum` is used rather than `hashFiles()` because this is shell, not an
expression context. The digest only has to be stable and content-derived, and
both halves read the same env var either way, so the algorithm choice is
irrelevant.

The variant-resolved host-toolchain key + paths, and the two make targets
that differ per variant, all come out of this same step. Main's key STRING is
byte-identical to what this step emitted before the `variant` input existed,
so existing cache entries keep hitting. A kernel variant gets its own
name-derived key namespace (`br-<name>-host-…`) because a Buildroot
cross-toolchain bakes its absolute `O=` prefix in (see
[`#ws-fp`](#ws-fp)): `output/host` and `output-<name>/host` are **not**
interchangeable and must **never** share an entry.

<a id="cache-coupling"></a>
### Cache coupling: #2 (dl/) and #3 (toolchain) — the flagship trap

**#2 (`dl/`) and #3 (the host toolchain) restores are COUPLED. Never restore
#3 without #2.**

An earlier version of this reasoning claimed "`dl/` has no such hazard — the
worst a partial `dl/` can do is miss a file the next run re-downloads." That
is **false**, and it cost run **29534917900** a 46-minute build.

Buildroot records "this package's source is downloaded" as a **stamp file**,
not by looking in `dl/`:

```
pkg-generic.mk:849   $(2)_TARGET_SOURCE = $$($(2)_DIR)/.stamp_downloaded
```

That stamp lives in `output/build/`, which cache #3 restores. The bytes live
in `dl/`, which cache #2 restores. Two keys, two lifetimes — so they **can**
disagree, and when they do, Buildroot believes the stamp. Restore #3 without
#2 and every host package is "already downloaded" with nothing on disk to
show for it. `make all` doesn't care (those packages are already built), so
the build goes green all the way to the image — and then `make legal-info`,
which actually opens the tarballs, dies on the first one:

```
cp: cannot stat '.../dl/ccache/ccache-4.12.3.tar.xz': No such file
```

Hence the `if:` on the toolchain-restore steps: a toolchain cache may only be
restored when `dl/` came back too, because its stamps are **assertions about
`dl/`'s contents**. A `dl/` miss therefore forces a genuinely cold build,
which re-downloads everything and leaves both caches consistent. Expensive
and self-healing, which beats cheap and silently broken.

`make source` does **not** rescue this — it resolves to the same
`.stamp_downloaded` and skips exactly the packages that need fetching. `make
-B source` would force the download, but `-B` re-touches every stamp, and
`.stamp_extracted` depends on `.stamp_downloaded` (`pkg-generic.mk:960`), so
the next `make all` would re-extract, re-patch, re-configure and rebuild
every host package — discarding the very cache being protected. There is no
cheap validation.

The `if:` on the host-toolchain restore reads
`steps.dl-cache.outputs.cache-matched-key != '' || steps.dl-cache-variant.outputs.cache-matched-key != ''`
— `cache-matched-key` is non-empty for BOTH an exact hit and a restore-keys
hit, i.e. "`dl/` came back with something". Only one of the two `dl/` restore
steps ever runs (the other's outputs are empty strings), so the `||` reads as
"the `dl/` restore for THIS variant matched". Skip the toolchain restore when
it didn't, and this build goes cold — which is the point, not a regression.

The initramfs host-toolchain cache (#4) is coupled to `dl/` for the identical
reason: that stage shares the one `BR2_DL_DIR` with every build here, so its
stamps make the same claims about the same `dl/`.

<a id="dl-cache"></a>
### The dl/ cache

`dl/` — every package source tarball (2.7 GB measured) — is keyed on the full
defconfig (adding a package needs new sources), but `restore-keys` falls back
to the version alone so an imperfect match still hydrates everything that did
NOT change instead of re-downloading the whole package set. `dl/` lives at
the **repo root** (survives `make clean`) — never move it under `output/`.

Exactly ONE of #2 (main) / #2b (kernel variant) runs per invocation; the
skipped step's outputs read as empty strings, which is what the combined
`if:`s and the `||` in the save step rely on.

<a id="variant-dl-fallback"></a>
### Variant dl/ fallback to main

A kernel variant's `dl/` restore (#2b) uses its own name-derived key, not
main's: a variant config needs sources main never fetches (e.g. RT's 7.2-rc3
kernel snapshot), and cache keys are immutable — under a shared key,
whichever variant saved first would lock the others' gaps in forever.

`restore-keys` falls back through the variant's own prefix to the **main**
`dl/` prefix, so a cold variant run warm-starts from ~everything main already
fetched. That fallback is safe **despite** the #2/#3 coupling documented
above: the variant host-toolchain cache's stamps (#3, keyed
`br-<name>-host`) only assert HOST-package tarballs — and the kernel-only
config's host set (cross-toolchain, host-kmod, …) is a strict **subset** of
main's, so a fallback-restored main `dl/` satisfies every one of those
stamps — while the variant kernel's own `.stamp_downloaded` lives in
`output-<name>/build/linux-*`, which is never cached, so no stale stamp can
vouch for a file only the variant config needs.

<a id="cache-save-policy"></a>
### Cache save policy: dl/ saves always(), toolchains save GREEN-ONLY

`actions/cache` declares `post-if: success()` (read it at the pinned SHA — it
is the last line of its `action.yml`). Its save runs as a POST step, so that
condition means: a job that FAILS saves nothing. Not a quirk — the documented
design.

That policy is right for the toolchains (#3/#4) and **wrong** for the
downloads, and the difference is stamps. A half-built `output/host` saved
from a build that died mid-way would come back WITH its per-package stamps,
and Buildroot would believe them and build straight into a broken tree. Never
save those from a failure.

Meanwhile `hendrikmuhs/ccache-action` declares **no** `post-if`, so it saves
on every run including failures. That asymmetry is why run **29529993731**
(failed at 46 min) uploaded 696 MB of ccache and saved no `dl/` at all — and
why this repo kept re-fetching 2.7 GB of sources, including a full ~70s git
fetch of glibc from sourceware.org, on every red build. Red builds are the
majority here, so "save only on green" meant "almost never save".

So: `dl/` restores early, saves explicitly at the end under `if: always()`.
Placed after `legal-info`, because `make legal-info` itself fetches the
source tarballs of any package it cannot already find in `dl/`.

The toolchain saves (#3/#4), by contrast, are **GREEN BUILDS ONLY. No
`always()` here is deliberate** — the one place in this file where the
**absence** of `always()` is load-bearing rather than an oversight. An `if:`
with no status function has an implicit `success() &&`, so a red build skips
these saves entirely. These carry the per-package stamps, and a half-built
`output/host` restored WITH its stamps is a poisoned toolchain that persists
across every future run until someone notices and force-evicts it.

<a id="ccache-key"></a>
### ccache key naming

The key is passed as the bare `${{ env.BUILDROOT_VERSION }}`, **not**
`ccache-<version>`: the action prepends its own variant prefix (`keyPrefix =
ccacheVariant + "-"`, `src/restore.ts`), so the `ccache-` spelling produced
the stuttering `ccache-ccache-2026.02.3-...` entries visible in `gh cache
list`. Passing the bare version yields `ccache-2026.02.3-<ts>`.

The trailing timestamp is the action's own, and it is **load-bearing — do
not** reach for `append-timestamp: false` to stop cache entries accumulating.
A GitHub cache key is immutable, so the only way to refresh a cache is to
write a NEW key; with the timestamp off, the first save would own
`ccache-<version>` forever, every later save would be rejected as already
existing, and the cache would freeze at its first contents while the hit rate
decayed. The timestamped key is a prefix match on restore (hence "Cache hit
for restore-key" in the logs), so the newest entry always wins.

<a id="dl-completeness"></a>
### dl/ completeness before save

**The trap this guards against:** a GitHub cache key is **immutable** —
whoever writes it first owns it until the key itself changes. `dl/` is saved
under `br-dl-<version>-<defconfig-hash>`, which only rotates when the
defconfig does, i.e. possibly not for weeks. So a build that died in its
first minutes, saving a nearly-empty `dl/`, would not merely be useless: it
would **lock that stub in**. Every later run would exact-hit it, restore
almost nothing, re-download the rest — and, because an exact hit suppresses
the save, never repair it. Strictly worse than not caching at all.

A late failure is the common one here and is exactly what we want to keep:
run **29529993731** died at 46 min, after `MODPOST`, with `dl/` fully
populated. Buildroot fetches each package's source before building it, so
"got deep into the build" implies "downloaded nearly everything".

**Ask Buildroot, do not guess.** The first cut of this used a 2 GB size
floor, and run **29534917900** proved a size floor cannot work: `dl/`
finished that run at 2.5 GB — comfortably "complete" — while missing the one
tarball `legal-info` needed. A tree can be the right size and still be
missing the file that matters, so the check measures the thing actually
cared about.

`make external-deps` (`<name>-external-deps` for a kernel variant) is the
oracle. It runs with `-B` (`buildroot/Makefile:860`), so unlike `make source`
it consults no stamps and cannot be fooled by the `.stamp_downloaded` problem
above; it just prints the basename of every file `dl/` is supposed to
contain.

It **MUST** be invoked with the same `BR2_CCACHE=y` as the real build. That
flag is a command-line override rather than a defconfig symbol, and it pulls
`host-ccache` plus blake3/hiredis/xxhash/zstd into the package graph — five
tarballs that a bare `make external-deps` does not list at all. Verified both
ways locally: without the flag the list is **158 files** and omits
`ccache-4.12.3.tar.xz` (i.e. it would have missed the exact failure this
guards against); with it, **163** including it. The `br-dl` cache KEY hashes
only the defconfig and is likewise blind to this — harmless while
`BR2_CCACHE=y` is constant in CI, and a trap the day it is not.

Bare basenames only: the wrapper Makefile echoes its own recipe and a
hostshim notice onto stdout (for a kernel variant, also the
`.config`-generation recipe's `cd`/`merge_config.sh` lines); every such line
contains a `/`, `=` or a space. The leading `^#` filter exists for one more
variant case: if the build died before `make <variant>` generated
`output-<variant>/.config`, the `.config` rule re-runs HERE and kconfig
prints its "configuration written to" trailer — two bare `#` lines that match
none of the other patterns. No legitimate basename contains `/`, `=` or a
space, or starts with `#`.

<a id="dl-cache-save"></a>
### dl/ cache save: key resolution and variant isolation

`cache-hit != 'true'` skips the upload when the primary key was an exact
match (nothing to add, and the save would be rejected anyway). A
restore-keys match leaves `cache-hit` false, which is what's wanted: `dl/`
was hydrated from an older entry and has since grown, so it's worth re-saving
under the new key.

Variant plumbing: only ONE of the two `dl/` restore steps ran, and a skipped
step's outputs are empty — so both `cache-hit` conditions collapse to "the
restore that ran was not an exact hit", and the `||` in `key:` resolves to
the primary key of whichever restore ran. The save therefore lands under the
same key namespace it was restored from (`br-dl-…` or `br-dl-<name>-…`),
which is what keeps a variant's warm-start-from-main fallback from ever
**writing into main's key space**.

<a id="apt-deps"></a>
### apt dependencies

The package list is Buildroot's own documented mandatory set, plus repo
extras:

- `git` — xone, munt, midilink and the morrownr Realtek forks are fetched at
  pinned git commits (see `package/*/*.mk`).
- `bison`/`flex`/`gawk` — kernel Kbuild's documented minimum.
- `ca-certificates` — without it every HTTPS package mirror fails TLS
  outright.
- `python3` — `scripts/abi/needed-symbols.py` + Buildroot infra.
- `libssl`/`libncurses`/`pkg-config`/`texinfo` — probed by third-party
  configure scripts even when cross-compiling.
- `qemu-user` — `ci-tests.sh` runs target binaries under `qemu-arm`.
- `e2fsprogs` — `dumpe2fs` fallback for `check-linux-img.sh`.

`EXTRA_APT` goes through the environment rather than being interpolated
straight into the script body — see
[`#branch-name-injection`](#branch-name-injection) for why.

<a id="release-apt-packages"></a>
### Release job apt packages (host-only tools)

`release.yml`'s call to `buildroot-build` adds `extra-apt-packages: p7zip-full
genimage mtools dosfstools xz-utils jq`. `p7zip-full` assembles
`release_YYYYMMDD.7z` — on Ubuntu 24.04+ it is a transitional package pulling
in `7zip`, which still ships `/usr/bin/7z` and `/usr/bin/7za`. NOTE this is a
**different** 7za than the pinned ARM static one fetched later in the same
job (see [`#stock-payload-verification`](#stock-payload-verification)): this
one only creates/inspects the archive on the x86_64 runner, while the pinned
ARM binary is what actually proves on-device compatibility.

The rest (`genimage`, `mtools`, `dosfstools`, `xz-utils`, `jq`) are the
build-HOST tools `scripts/mk-sdcard.sh` needs to assemble `sdcard.img.xz`:
`genimage` builds the hdimage, `mtools`+`dosfstools` build/populate the FAT32
payload partition, `xz-utils` compresses the image, and `jq` parses the
`_Console` cores listing for the opt-in full variant. None of these enter the
shipped rootfs — they live on `PATH` only. `xz-utils` is already in the build
action's mandatory set; naming it here again is a harmless duplicate, kept
for intent.

---

## Part IV — Composite action internals

<a id="composite-input-validation"></a>
### Composite-action input validation must run first

Composite-action inputs are **always strings** (there is no boolean type), so
a caller typing `"yes"`/`"True"`/a trailing space is a real, easy mistake.
`.github/actions/kernel-leg`'s "Validate inputs" step runs FIRST, before the
multi-hour build, for the same fail-fast reason `build.yml` documents for its
own serial gate ("runs in about a second... failing fast instead of after a
possible 300-minute build") — the same shape `.github/actions/merge-kernel-modules`
("Reject unknown phase") and `.github/actions/verify-image` ("Validate
skip-qemu-system") also use as their own step 0. Catching a typo after a
240-minute kernel build — which also auto-skips `build` behind it — would
burn the whole leg's runner time. The per-step `case` blocks further down are
kept as cheap belt-and-braces so each step still refuses to act on a value it
did not validate itself.

<a id="unique-glob-guard"></a>
### Uniqueness-guarded globs, everywhere a kernel tree is found

Every place this pipeline globs for "the" kernel build tree
(`output-$KERNEL/build/linux-[0-9]*/` and siblings) uses a **uniqueness-guarded
array**, never `ls -d ... | head -1`: parsing `ls` is SC2012, and `head -1`
would silently render (or stage) the WRONG kernel's version/config/module
tree with a stale sibling tree present from a version bump. The glob pattern
itself (`linux-[0-9]*`) also has to exclude `linux-firmware-*` and
`linux-headers-*` siblings, which is why it's anchored on a leading digit.

This shows up in three places with three different failure modes if it's
ever weakened:

1. `kernel-leg`'s job-summary step — best-effort; any count other than
   exactly one leaves the fact `n/a` rather than failing the leg.
2. `kernel-leg`'s "Stage the kernel artifact" step — `shopt -s nullglob` is
   required here too, or a zero-match glob leaves the *literal pattern
   string* in the array and the guard would report "found 1" for an empty
   build (the count in the error must be truthful).
3. `release.yml`'s "Copy buildroot.config and linux.config" step mirrors the
   exact same `nullglob` + uniqueness-guard shape.

<a id="kernel-artifact-transport"></a>
### Kernel artifact: inter-job transport, not a deliverable

The kernel leg's uploaded artifact is **inter-job transport**, not something
a human downloads: the `build` job downstream needs the module tree (and its
merge-assert needs the kernel version), so — unlike the main job's
push/dispatch-gated uploads — this uploads on **all** events, PRs included.
`build.yml`'s leg is ~15 MB (modules tar + kernel + config + manifest-only
SBOM), negligible next to the image artifacts. `release.yml`'s leg ships the
full GPL source bundle instead of the manifest-only SBOM, so it runs ~250-300
MB instead — still negligible next to the image artifacts.

<a id="ci-lib-explicit-fallback"></a>
### ci-lib.sh: explicit fallback, not a silent abort

Job-summary steps `source scripts/ci-lib.sh` for shared helpers
(`ci_lib_sz`, `ci_lib_package_legal_info`,
`ci_lib_check_release_asset_size`). Where the step is best-effort (a
job-summary table), the `source` is followed by an explicit `||` fallback
that defines a stub `ci_lib_sz() { echo "n/a"; }` and emits a `::warning::` —
because GitHub's own run-step shell already carries an implicit `-e`, and a
missing `ci-lib.sh` must not silently blank every size cell in the table or
abort a step whose entire purpose is "best-effort, never fail the build". See
also [`#ci-lib-source-fallback`](#ci-lib-source-fallback) for the identical
pattern in `release.yml`. Where the step is NOT best-effort (staging an
actual release asset, e.g. `kernel-leg`'s "Stage the kernel artifact" step),
`source scripts/ci-lib.sh` has no fallback and is allowed to abort the step —
a missing helper there is a real repo-integrity bug, not a cosmetic gap.

<a id="merge-kernel-modules"></a>
### merge-kernel-modules: two phases, one action, called twice

`build.yml` and `release.yml` each carried their own byte-for-byte copy of
the "Download kernel-variant artifacts" + "Populate the extra-modules
overlay" pair, and the "Assert every kernel-variant module tree merged"
guard. Same mechanism, same script, same failure modes — now one action,
called with a `phase` input.

The merge is not one contiguous block in the calling job: the overlay must be
populated **before** `.github/actions/buildroot-build` runs (Buildroot rsyncs
the overlay into `TARGET_DIR` at target-finalize, so it has to exist first),
and the merge can only be **asserted** once the image has actually been
built. A single composite action cannot straddle a step that belongs to the
caller (the build action runs in between), so the `phase` input picks which
half runs:

- `phase: download` — "Download kernel-variant artifacts" + "Populate the
  extra-modules overlay from the kernel legs". Call this BEFORE
  `buildroot-build`.
- `phase: verify` — "Assert every kernel-variant module tree merged into the
  image". Call this AFTER `buildroot-build`.

Composite-action inputs are always strings, so every `if:` gating a phase
step compares `== 'download'` / `== 'verify'` literally, never as a
truthiness check.

<a id="merge-kernel-modules-fail-loud"></a>
### merge-kernel-modules: fail loud on an unrecognised phase

Every phase step is gated with `if: inputs.phase == 'download'` /
`== 'verify'` and has **no else-branch**. An unrecognised value (a typo, a
stray caller that drops the `with:` block entirely, wrong case) would
otherwise make the whole composite a silent no-op that exits 0 — including
the "Assert every kernel-variant module tree merged" guard, whose entire
purpose is to fail here instead of on a device. The "Reject unknown phase"
step exists precisely to make that impossible.

<a id="verify-image-overview"></a>
### verify-image: replacing a hand-synced duplicate trio

`build.yml` and `release.yml` each carried their own byte-for-byte copy of
the "Run parity test suite" / "Upload parity-suite results" / "ABI / SONAME
parity checker" trio, including a hand-synced
`CI_TESTS_SKIP_QEMU_SYSTEM=1` that a comment in each said had to be kept in
sync by hand. That is exactly the kind of duplication this action removes:
the flag is now ONE input, `skip-qemu-system`, default `"true"`
(byte-identical behavior to the old hard-coded `"1"`), with the override
available to any caller that wants the full six-boot QEMU system-kernel check
(a manual/nightly run). Do not re-inline a copy of this trio into either
workflow.

Composite-action inputs are always strings — every comparison against
`inputs.skip-qemu-system` is `== 'true'`, never a truthiness check.

`CI_TESTS_SKIP_QEMU_SYSTEM=1` skips `scripts/test-initramfs.sh`, the one
sub-check that boots a QEMU *system* kernel six times and can take several
minutes on its own. Unset it in a manual/nightly run to get the full suite.

`if: always()` on the parity-results upload is the whole point of that step:
the artifact is worth having precisely when the test step FAILED, and a
failed step would otherwise abort the job before it's ever uploaded.
`ci-tests.sh` also emits a `::error::` annotation per failure (so the run UI
names the broken check without opening the log) and prints a FAILURES digest
as its last output — the uploaded file is the same list, machine-readable,
for pasting into a bug or diffing across runs. A ~2 KB text file; negligible
next to the image artifacts.

<a id="release-abi-check"></a>
### ABI check in a clean checkout

`scripts/check-abi.sh` asserts the ABI/loader contract
(`docs/abi-contract.md` §13.1) against the freshly built rootfs: the 12
`DT_NEEDED` SONAMEs at the same major, the glibc-2.34 merge stubs, the
loader, `/MiSTer.version`'s byte shape, and — when the gitignored stock
binary is present — the stock MiSTer's dynamic-link resolution under
`qemu-user`. A missing SONAME or a dropped compat stub fails the build here.
It also writes an "ABI / SONAME parity" section onto the run's Summary page.

The two stock-binary gates (A-10/A-22) **SKIP, not fail**, in a clean CI
checkout where `work/` does not exist (the stock binary lives there,
gitignored). That is expected behavior, not a broken check — see
[`#stock-payload-open-decision`](#stock-payload-open-decision) for the
broader context on why this repo doesn't vendor that binary.

---

## Part V — build.yml

<a id="kernel-gate-cascade"></a>
### Why `build-kernel` cannot be demoted with a bare `if:`

This build costs ~3h20m cold, and since ADR 0021 the kernel-variant matrix
(`build-kernel`) runs **serially before** `build` (the image build consumes
the legs' module trees, so it cannot start until they finish). That
serialization is a deliberate trade: it adds roughly the kernel legs'
wall-clock (~+1 h warm, more cold) to every gated PR run, in exchange for one
shipped image carrying every kernel's modules.

If that trade ever stops paying, the cost levers are: shrink the matrix, or
demote `build-kernel` to push/dispatch-only. That demotion is **not** a
one-line `if:` — three other places hard-code "the kernel legs always ran",
and skipping the job without touching them turns every PR run red instead of
main-only:

1. `build`'s own `if:` uses no status function, so a skipped `needs` skips
   `build` itself (the needs-cascade rule the `status` job documents) — it
   would need an `always() && build_needed`-style guard instead.
2. The `status` truth table (see
   [`#status-job-rationale`](#status-job-rationale)) treats a skipped
   `build-kernel` while `build_needed=true` as a workflow bug — it would need
   a policy-skip success path added.
3. `merge-kernel-modules`'s "Populate the extra-modules overlay" step
   hard-errors on zero modules tars (the download step itself tolerates an
   unmatched pattern) — that guard would need relaxing, accepting that PR
   images then carry only main's modules.

<a id="push-trigger-scope"></a>
### push trigger scoped to master

`push:` is scoped to `branches: [master]`. It used to be a bare `push:`,
which — next to `pull_request:` — meant **every commit on a PR branch built
twice**, once per event, ~6h40m of runner time for one commit. They didn't
even cancel each other: the concurrency group keys on `github.ref`, and the
two events see different refs (`refs/heads/<branch>` vs
`refs/pull/N/merge`), so both ran to completion. This was confirmed from the
run history, not deduced — every SHA in `gh run list` appeared twice, once
`push` and once `pull_request`.

Now: PRs build once via `pull_request`, master builds once post-merge via
`push`. A branch pushed with no PR open doesn't build, which is the point.

`lint.yml` deliberately repeats this exact split, even though that job is
cheap enough that skipping the discipline would be tempting — see
[`#push-pr-trigger-split`](#push-pr-trigger-split).

<a id="gate-vs-paths-ignore"></a>
### Doc-only skip is a job decision, not paths-ignore

Doc-only changes don't compile, and skipping the build for them is decided by
the `gate` job, **not** by a `paths-ignore:` on the trigger. That was the
obvious implementation and it is a trap, because it is incompatible with
branch protection: `paths-ignore` stops the workflow from running **at all**,
so a required "Build" check is never reported, sits pending forever, and a
docs-only PR can never merge. A skipped **job** has the same problem —
"skipped" is not "success" to branch protection. So the workflow always runs,
and the thing that is safe to mark required is the `status` job at the
bottom, which always reports (see
[`#status-job-rationale`](#status-job-rationale)).

<a id="gate-denylist"></a>
### The gate is a denylist, not an allowlist

`gate`'s `is_doc()` classifies **only** paths that provably cannot affect a
compile as doc-only (`docs/*`, `*.md`, `LICENSE`, `.editorconfig`,
`.gitignore`). Everything else — `board/`, `configs/`, `package/`,
`scripts/`, `Makefile`, `external.*`, `Config.in`, and `.github/` itself —
builds.

The allowlist ("build only when these paths change") is the tempting
alternative and it fails the wrong way: add a build-relevant path, forget to
list it, and CI goes green having compiled nothing. The denylist fails toward
building — it wastes minutes, it never hides a break. Same reasoning as
`clean` erroring rather than skipping in the top-level Makefile: a tree that
looks tested and isn't is worse than one that obviously wasn't.

This was verified once, by hand, before writing the list: no `.md` is read by
the Makefile, `external.mk`, `Config.in` or `post-build.sh`. **Re-verify that
claim before trusting this list again** if the build's own file-reading
surface ever changes.

<a id="kernel-leg-timeout"></a>
### Kernel leg timeout: an estimate, not a measurement

`build-kernel`'s `timeout-minutes: 240` is an **estimate** at the time it was
set: cross-toolchain from scratch (~1h of main's measured 3h19m) + the
stage-1 initramfs (~30 min cold, its toolchain cached separately) + one
kernel build. 240 leaves roughly 2x slack over that estimate while still
killing a hung leg well before GitHub's silent 6-hour default. Re-derive this
number from real kernel-leg runs once they exist rather than trusting the
estimate indefinitely.

<a id="build-timeouts"></a>
### Main build timeout: a real measurement

`build`'s `timeout-minutes: 300` comes from a real measurement rather than a
guess: the first green cold build (run **29300460591** — empty caches,
4-vCPU runner) took **3h19m47s**. 300 is ~1.5x that, so a legitimately slow
cold build still finishes while a genuinely hung one is killed ahead of
GitHub's silent 6-hour default.

A cold build is **not** the rare case: any change to the toolchain
fingerprint (see [`#toolchain-fingerprint`](#toolchain-fingerprint)) busts
the cross-toolchain cache. Ordinary package adds do NOT — those stay warm and
are far quicker.

<a id="patch-lint-placement"></a>
### Kernel patch-header lint: deliberately before the build

`scripts/lint-kernel-patches.sh` runs deliberately **before** the build, and
deliberately in the `build` job rather than a job of its own: it needs no
kernel tree and no network, runs in about a second, and so costs no extra
runner minutes while failing fast instead of after a possible 300-minute
build.

It guards an interface the build itself cannot: Buildroot applies these
patches with `patch -p1`, which ignores mail headers, so a malformed `From:`
builds green and only breaks when the series is replayed as git history with
`git am`. With no arguments it lints BOTH series — the carried one Buildroot
applies, and `linux-patches-upstream/`, which is carried only for the
exported tree. The second needs this check more than the first: nothing else
in this repo reads those files at all, so `git am` at export time is the
only thing that ever exercises their headers, and an export happens rarely
enough for a defect to sit there for months undetected.

<a id="kernel-defconfig-lockstep"></a>
### Kernel-defconfig lockstep check, run twice

Same fail-fast reasoning as the patch lint: the kernel-only base defconfig is
a manually mirrored copy of the main defconfig's toolchain/kernel stanzas
(see [`#variants`](#variants)), and `scripts/check-kernel-defconfig-sync.sh`
asserts the copy has not drifted. The composite action (`buildroot-build`)
runs it for every kernel leg too; running it here, in `build.yml`'s own
`build` job, as well, catches the main-only edit path (main defconfig
changed, mirror forgotten) in seconds, without waiting for a kernel leg to
fail.

<a id="kernel-module-overlay"></a>
### Kernel module overlay: download then populate

`Download + populate kernel-variant module overlay` (phase: download) must
run before the image build — see
[`#merge-kernel-modules`](#merge-kernel-modules) for the mechanism. `Assert
kernel-variant module trees merged` (phase: verify) runs after, and is what
catches a silent overlay miss — a kernel leg artifact that downloaded but
never actually landed inside `linux.img`.

<a id="build-summary-step"></a>
### Build overview job-summary step

Surfaces the facts a reviewer usually opens the log to hunt for — kernel/
glibc versions, image sizes, `/MiSTer.version`, package count — as a table on
the run's Summary tab. Runs right after the build so it renders ABOVE the
ABI/SONAME section `scripts/check-abi.sh` appends later. Best-effort: every
fact is guarded and defaults to `n/a`; a missing one never fails the build.
`release.yml` has an equivalent step; see
[`#ci-lib-explicit-fallback`](#ci-lib-explicit-fallback) for the shared
sourcing pattern both use.

<a id="parity-suite"></a>
### Parity suite + ABI/SONAME checker invocation

`build.yml`'s "Run parity suite + ABI/SONAME checker" step calls
`.github/actions/verify-image` with `skip-qemu-system: "true"`, matching the
`CI_TESTS_SKIP_QEMU_SYSTEM=1` this job always ran historically; pass
`"false"` for the full six-boot QEMU suite. See
[`#verify-image-overview`](#verify-image-overview) for the full action
rationale.

<a id="abi-checker-overlap"></a>
### ABI checker vs ci-tests.sh: intentional redundancy

`scripts/check-abi.sh` (P2.2) is the authoritative ABI/SONAME checker.
`ci-tests.sh`'s own "ABI / stock-binary smoke" section separately carries a
lightweight interim of the two highest-value qemu-user gates (A-10/A-22) —
this overlap is cheap and **intentional**, not duplication to clean up.

<a id="artifact-upload-gating"></a>
### Upload build artifacts: push + dispatch, not pull_request

Uploads run on `push` and `workflow_dispatch`, **not** on `pull_request`
runs, to avoid doubling artifact storage for every PR revision on top of its
eventual push to the target branch. A manual `workflow_dispatch` DOES upload:
fetching the built image is usually the whole reason someone triggers a build
by hand, and without this a manual run finishes green but publishes nothing —
which is exactly what happened once `workflow_dispatch` was added as a
trigger without updating this gate.

The SBOM/legal-info upload (see
[`#legal-info-2gib-cap`](#legal-info-2gib-cap) for why it excludes
`sources/`/`host-sources/`) uses the identical gate.

<a id="status-job-rationale"></a>
### The `status` job: what gets marked required, and why

`status`, not `build`, is the job to mark as the required branch-protection
check — `build` is skipped on doc-only changes, and branch protection does
not count a skipped check as a passing one, so requiring `build` directly
would wedge exactly the PRs the `gate` job is meant to make cheap.

`status` always runs (`if: always()`), so it always reports, and turns the
upstream results into one honest answer via this table:

| Condition | Result |
|---|---|
| job succeeded | pass (it compiled, it worked) |
| all skipped, no need | pass (docs only; nothing to compile — the point) |
| gate itself sick | **FAIL** (if we cannot tell whether a build was needed, we have not established one wasn't) |
| anything else | fail |

`build-kernel` is **deliberately gating** (ADR 0021): its kernels ship as
first-class release assets AND their modules ride inside `linux.img`, so a PR
that breaks a kernel leg must not merge green. `needs` on the matrix job
aggregates all its legs, so one result covers however many variants the
matrix grows to.

`needs.<job>.result` is used rather than `success()`/`failure()`, which would
fold "skipped" into the wrong bucket — the whole table above exists because
skipped needs its own honest branch, not "pass" or "fail" by accident of
which helper function was used.

---

## Part VI — release.yml

<a id="release-consumers"></a>
### Release consumers: three downstream actors

`release.yml` builds via the same recipe as `build.yml`, then assembles a
GitHub Release consumable by three completely different downstream actors:

1. **A human** downloading `linux.img` / `zImage_dtb` / configs / SBOM
   directly from the Release page.
2. **The on-device `Downloader_MiSTer`** (`LinuxUpdater`), which NEVER talks
   to GitHub Releases directly — it fetches whatever URL a `db.json`'s
   `linux.url` field names (a separate job, `publish-db.yml`) and feeds it
   straight to a PINNED, OLD, STATIC ARM `7za` binary it already has on the
   SD card. That binary only ever sees `release_YYYYMMDD.7z`. Every assertion
   in `release.yml` about extraction/layout exists to protect **this** actor,
   because nothing else in the pipeline will catch a mistake there — see
   `docs/downloader-contract.md` §4-§8, §12.
3. **A human opting into the PREEMPT_RT / Linux-7.2 beta** (ADR 0021 as
   amended 2026-07-18, `docs/rt-beta-kernel.md`): `zImage_dtb-rt`,
   `linux-rt.config`, `legal-info-rt.tar.gz`, built KERNEL-ONLY by the
   `build-kernel` matrix job from the same tagged commit. The RT kernel's
   MODULES ride inside the ordinary `linux.img` (the `build` job merges
   every kernel leg's depmod'd tree via `work/extra-modules-overlay/`), so
   opting in is copying one file + one `u-boot.txt` line — no separate RT
   rootfs exists anymore. The kernel file itself is deliberately NOT inside
   `release_YYYYMMDD.7z` and NEVER referenced by `db.json` — pushing an RT
   kernel at every subscribed device stays an OPEN human decision in ADR 0021.

<a id="rebuild-not-adopt"></a>
### Why release.yml rebuilds and re-verifies instead of adopting build.yml's run

A release must be built from the tagged commit by a job whose provenance is
attested, not adopted from some earlier run's artifacts. But the **build
itself** is no longer duplicated code — it was, and that was a latent bug:
the five fixes `build.yml` needed to go green (no container, disk reclaim,
defconfig step, non-root, workspace-keyed toolchain caches) never reached
this file, so the first real tag push would have failed here. The recipe now
lives once, in `.github/actions/buildroot-build`.

Same reasoning, applied to verification: because the image is rebuilt rather
than adopted, it is also **re-verified** rather than trusted. This workflow
runs the full non-hardware suite `build.yml` runs — `scripts/ci-tests.sh`
(P3.12) then `scripts/check-abi.sh` (P2.2) — against its own fresh build of
the tagged commit, before packaging. Running only one of that pair would be
an incoherent middle: the "the commit already passed `build.yml` on master"
argument for skipping either applies equally to both, and a `v*` tag can
point at a commit master never saw.

<a id="stock-payload-sourcing"></a>
### Stock payload sourcing

The ONE thing `release.yml` cannot do itself: vendor the stock `uboot.img` /
`files/linux/` auxiliary payload (`updateboot`, config templates,
`u-boot.txt_example`, `MidiLink.INI`, `ppp_options`, the samba/user-startup/
wpa_supplicant templates, `gamecontrollerdb/`, `mt32-rom-data/`,
`soundfonts/`). G6 forbids committing binaries to git, and several of those
files ARE binary (`uboot.img`; arguably the ROM/soundfont payloads). So this
workflow **fetches** them, at release time, from the exact same
commit-pinned stock archive `docs/reference-materials.md` /
`docs/downloader-contract.md` already verified byte-for-byte in this repo:

```
https://raw.githubusercontent.com/MiSTer-devel/SD-Installer-Win64_MiSTer/
  b8531c7848526d9a8227841923cc4a493cb6e631/release_20250402.7z
MD5 8dc3acae7d758a80a363fbd7ad31d95d
SHA-256 5d087d9c501b2bc50aaf918146e7bf30e5981c08268d5a0e67a3233a4da642ba
93,727,644 bytes
```

All three (MD5, SHA-256, size) are checked BEFORE anything is extracted from
it. Individual `uboot.img`/`updateboot` hashes are re-checked too
(`docs/downloader-contract.md` §8, §12.1) as belt-and-suspenders.

The pinned ARM static `7za` used to verify the round trip is the **exact**
binary the real on-device Downloader fetches once and reuses forever
(`docs/downloader-contract.md` §4). Its own upstream URL is a floating branch
ref (`raw/master/7za.gz`), not a commit pin — that is a pre-existing fact of
the Downloader's own source (`constants.py`), not something this workflow can
fix without deviating from what real devices actually fetch. The MD5 check
is the actual security control: any substituted content fails the build
loudly instead of silently.

<a id="stock-payload-verification"></a>
### Stock payload verification order

`scripts/verify-stock-payload.sh` implements a strict order, mirroring
`docs/downloader-contract.md` §2's own ordering: MD5+size check, then a
SEPARATE `7z` internal-CRC test, for the same reason the real Downloader does
both — MUST fully verify before extracting a single byte.

Extraction uses exactly the pattern+destination the real Downloader uses
(`docs/downloader-contract.md` §5) — only `files/linux/*` exists afterwards;
the Windows-installer-only members (`files/MiSTer`, `files/menu.rbf`,
`files/MiSTer_example.ini`, `files/Scripts/`, the `.exe`) are never extracted
and never shipped: they come from separate MiSTer-devel projects, not from
this Buildroot tree, and the Downloader never reads them either.

Our own release archive is assembled with **plain solid LZMA2**, not stock's
BCJ2 filter (`docs/downloader-contract.md` §4's explicit recommendation — BCJ2
is an artifact of the Windows 7-Zip GUI auto-detecting x86 executables in
*its* archive, irrelevant to ours). It is then verified with the **exact**
pinned ARM static `7za` the real Downloader uses — not a modern host `7z`
(§4's explicit "testing anything less specific doesn't prove the
constraint") — under `qemu-arm`, since it's a static ARM binary. Both `7za t`
(integrity) and `7za x -y ... files/linux/*` (extraction) are exercised,
exactly the Downloader's own two invocations.

The archive member list is then diff'd against the assembled `release-stage/`
tree using `7z l -slt`. That command prints a "Path = " line for the
**archive itself** in its header block, before a `----------` separator and
the per-member list — everything up to and including that separator must be
skipped, or the archive's own filename corrupts the comparison as a phantom
extra member. A second, explicit, human-readable cross-check against the
documented canonical member set (`docs/reference-materials.md` §2,
`docs/verification/stock-release-20250402.md`) catches a silently-empty
stock archive passing the (vacuous) diff.

`scripts/verify-stock-payload.sh`'s four call sites (`fetch-stock`,
`verify-stock`, `extract-stock`, `verify-uboot`, `roundtrip`,
`verify-layout`) are runnable standalone; the `STOCK_*` hash/size pins live
only in `release.yml`'s job-level `env:` block, not duplicated into the
script.

<a id="stock-payload-open-decision"></a>
### Open decision: third-party payload dependency

This is a real, working, hash-pinned source for the stock payload, not a
fabrication — but it is still a dependency on a **third-party repo's git
blob** outside this project's control, and `mt32-rom-data/`/`soundfonts/`
carry content this project did not author. Both are pre-existing facts of
every MiSTer distribution (this workflow does not introduce them), but a
human should sanity-check this sourcing choice before the first real tag
push, not just this comment. Flagged as an open decision, not a settled one.

<a id="tag-convention"></a>
### Tag convention (unratified)

No tag convention exists anywhere in this repo as of the workflow's
authoring (`git tag -l` was empty; `TASKS.md` never specifies one). `v*`
(e.g. `v1.0.0`, `v2026.07.13-1`) was picked purely because the task brief
suggested it as a default — it is **not** derived from any existing project
decision and should be revisited/ratified by a human.

<a id="mister-version-coupling"></a>
### MiSTer.version / filename / db.json coupling (load-bearing)

`docs/downloader-contract.md` §3/§12 requires the `db.json` `linux.version`
field's last 6 characters to equal, byte-for-byte, the `/MiSTer.version`
baked into `linux.img`. `release.yml` doesn't publish `db.json`
(`publish-db.yml`'s job), but it DOES name the release archive
`release_YYYYMMDD.7z`, and that filename has always
(`docs/verification/stock-release-*.md`) matched the version the archive
carries.

Per ADR 0018 that version is now **SET** from the tagged commit: the "Derive
release version" step derives a 6-digit YYMMDD from the tagged commit's UTC
date and exports `MISTER_VERSION`, and `post-build.sh` bakes exactly that
into `/MiSTer.version`. Deliberately **not** from `SOURCE_DATE_EPOCH` (pinned
to a constant for reproducibility — every release would have claimed the
same version and the Downloader, which compares `db.json`'s `version` to the
on-device `/MiSTer.version`, would have re-flashed on every single run).

The "Extract and validate /MiSTer.version from the built image" step then
VERIFIES the built image carries exactly the version requested (a real
image/tooling-mismatch guard) and republishes it as `RELEASE_DATE` for the
archive name / `SHA256SUMS` / `db.json`, which must all agree.

This resolves the old constant-version hazard: distinct tags → distinct
commit dates → distinct `/MiSTer.version` + `release_YYYYMMDD.7z` + `db.json`
version, so the Downloader offers the update and then sees the box as
up-to-date. (Two tags on the SAME commit still map to one YYMMDD — same
granularity as stock; fine unless back-to-back same-day releases are ever
needed.)

`publish-db.yml`'s "Generate db.json" step recovers this same 6-digit YYMMDD
from the archive filename and passes it to `gen-db-json.py` as `--version` —
archive name, image stamp, and published version are the same value by
construction, never independently derived.

<a id="manual-full-sdcard-dispatch"></a>
### Manual workflow_dispatch: opt-in full sdcard variant

Manual dispatch builds ONLY the opt-in full sdcard variant (bundles
`_Console` cores) — tagged pushes already produce the minimal
`sdcard.img.xz`. **MUST be dispatched against a tag ref**, not a branch: the
GitHub UI's "Use workflow from" ref picker accepts tags, so `github.ref_name`
becomes the release tag and the `publish` job attaches the assets to that
tag's draft release. A dispatch on a branch still builds + verifies the
images in `build`, but the `publish` job is guarded to tag refs regardless
(see [`#publish-job-scope`](#publish-job-scope)), so it never mints a
branch-named release — it just burns a full ~5h build for nothing.

<a id="sdcard-timing-6h-cap"></a>
### sdcard build timing and the 6-hour runner cap

The measured cold main build is **3h19m** (~199 min; run **29300460591**),
plus fetching+verifying the ~90 MB stock archive, assembling the 7z, the
pinned-ARM-7za round trip, and hashing everything. The sdcard steps add
`mk-sdcard.sh` step 1 (the installer initramfs — a small static-musl
Buildroot build with its own toolchain, ~1 h) and step 2 (the kernel relink).

**Crucially, step 2 does NOT do a second from-scratch Buildroot build**: it
REUSES the completed main build in `output/` and only re-links the kernel
with the installer initramfs (~15 min each way, snapshotting+restoring
`output/` so the shipped kernel is untouched — see
`scripts/mk-sdcard.sh`'s `build_installer_kernel`). That reuse is deliberate
and is what keeps the whole job around ~5 h, comfortably inside
GitHub-hosted runners' HARD ~6 h (360 min) wall-clock cap.

An **earlier design** ran a fresh full Buildroot build (internal glibc
toolchain + rootfs, ~3 h) per sdcard step in a new `O=`; two of those stacked
on the main build overran the 360-min cap and the release **never
published**. Do not reintroduce a from-scratch `O=` here without moving the
sdcard assembly to its own job/workflow.

<a id="dist-layout"></a>
### dist/ layout contract

The SEVEN main filenames staged first are exactly the seven release assets
`TASKS.md` P4.4 names — the Downloader-contract set, untouched. On top of
them `dist/` carries, per kernel variant, three `-<name>`-suffixed extras
taken from the leg artifacts (`zImage_dtb-<name>`, `linux-<name>.config`,
`legal-info-<name>.tar.gz` — ADR 0021 as amended; for today's matrix that is
the three `-rt` files), plus the separately-contracted sdcard images (see
[`#sdcard-contract`](#sdcard-contract)). Everything from the staging step on
writes into `dist/` or reads from it; `publish` uploads it verbatim.

The "Copy buildroot.config and linux.config" step uses `shopt -s nullglob`
so a zero-match glob yields an EMPTY array, keeping the count in the guard
error truthful — see [`#unique-glob-guard`](#unique-glob-guard) for the
shared pattern with `kernel-leg`'s staging step.

<a id="legal-info-2gib-cap"></a>
### legal-info.tar.gz: host-sources exclusion and the 2 GiB asset cap

A RELEASE distributes the image, so this one DOES carry the GPL
"accompanying source": `legal-info/sources/` holds the upstream tarball of
every package shipped, alongside `manifest.csv` (package, version, license,
upstream URL) and the license texts.

`host-sources/` is excluded, deliberately. That is the source for the
BUILD-TIME toolchain (host-gcc, host-binutils, host-glibc, ...) — none of
which is distributed in `linux.img` or `zImage_dtb`. The GPL obligation
attaches to the binaries conveyed, not to the compiler that produced them
(which is itself freely available upstream, pinned by version+hash in
`host-manifest.csv`, which IS shipped). Buildroot emits `host-sources/` for
completeness, not because distribution requires it.

This is not merely a size optimisation, though it is that too: with
`host-sources/` included, the archive measured **2109 MiB**, and GitHub
rejects any single release asset over **2 GiB** — so the first real tag push
would have failed right at the upload. The guard makes that failure mode
loud and early instead of a mysterious 500 from the API.

`build.yml`'s SBOM-only legal-info artifact excludes both `sources/` AND
`host-sources/` for a different reason: a CI push distributes nothing, so
there's no GPL obligation to carry either — see
[`#build-summary-step`](#build-summary-step)'s sibling context in
`build.yml`. With both excluded that artifact went from 2109 MB (24x the
images it accompanies, 87 MB) down to ~4 MB of manifest, license texts,
`buildroot.config`, and source hashes.

<a id="old-two-image-design-retired"></a>
### Retired two-image release design

An earlier release design built and published the main image and the RT beta
image separately, which needed a publish-side append step: the RT bundle
first met the main bundle in the `publish` job, so `SHA256SUMS` had to be
generated once for main and then appended to for RT. Since kernel variants
became a matrix that runs BEFORE the single `build` job (ADR 0021 as
amended), every asset — main seven + all kernel-variant extras — lives in
ONE `dist/` now, `SHA256SUMS` is generated ONCE covering everything, and
there is no publish-side merge/append step anymore. Historical contrast only:
explains why the "no longer needed" absences in `release.yml`
(no per-variant MISTER_VERSION derivation, no append step, no second bundle
download in `publish`) are deliberate, not oversights.

<a id="sdcard-contract"></a>
### sdcard images are standalone assets

The sdcard installer images (TASKS.md P5.3, ADR 0017 §4 amended by ADR 0020)
are SEPARATE, standalone flashable assets — deliberately **NOT** inside
`release_YYYYMMDD.7z` and **NEVER** referenced by `db.json`. They therefore do
not touch the `SHA256SUMS` list (the Downloader-contract seven plus the
kernel-variant extras) nor the pinned-ARM-7za verification path; the sdcard
steps run AFTER all of that so the already-fetched+verified `stock_release.7z`
can be reused instead of re-downloading ~90 MB.

`scripts/mk-sdcard.sh` does its own installer-initramfs build + kernel relink
off the completed `make all`, and ships the RT kernel from the leg artifact
(not a local `output-rt/` build) as `zImage_dtb-rt` on the card's FAT
payload — one flashable card, both kernels.

Reuse of the stock archive already verified above happens by seeding
`fetch-sdcard-payload.sh`'s own cache with it: that script re-checks
size+MD5+SHA-256 before trusting the cache, so this is a hand-off of
already-verified bytes, not a bypass. The job-level `STOCK_*` env is
inherited by both `mk-sdcard.sh` and `fetch-sdcard-payload.sh`, keeping the
pins in lockstep with the block this workflow already verifies.

The minimal sdcard build is skipped ONLY on an opt-in full-sdcard dispatch
(see [`#manual-full-sdcard-dispatch`](#manual-full-sdcard-dispatch)): that run
targets an already-released tag whose minimal `sdcard.img.xz` is already
attached, so rebuilding it here is pure redundancy — and each
`mk-sdcard.sh` run does a ~30 min kernel relink, so a needless second one
risks the job's ~6 h cap.

<a id="disk-usage-double-sample"></a>
### Disk & cache usage: a second, differently-timed sample

The `buildroot-build` action reports disk & cache usage too
(`if: always()`), but that sample is taken right after `make all` /
`legal-info` — BEFORE this job downloads+extracts the stock archive a second
time under qemu, assembles `release_${RELEASE_DATE}.7z`, and builds+
xz-compresses `sdcard.img` and (opt-in) `sdcard-full.img`, which are the
steps most likely to actually exhaust the runner's disk. This is therefore a
second, differently-timed sample — **not a duplicate** — and is the only
place a post-packaging disk-exhaustion failure would be visible. Do not
remove it as "redundant" with the build action's own sample.

<a id="artifact-naming-slash-trap"></a>
### Artifact naming: the `/` trap

`upload-artifact` **rejects `/`** in artifact names, and every branch in
this repo is slash-named (`feat/…`, `feature/…`). Every artifact that a
single run both writes and reads is therefore named by **sha**, never
`ref_name`:

- `release.yml`'s "Upload release asset bundle" (`release-dist-<sha>`) —
  `publish` (same run, same sha) is the only consumer.
- `kernel-leg`'s "Upload kernel artifact" (per-variant, sha-keyed).
- `build.yml`'s `mister-images-<sha>` and `legal-info-<sha>`.
- `verify-image`'s `ci-tests-results-<sha>` parity-suite upload.

Tags (`v*`) never contain `/`, so tag pushes never cared either way —
sha-naming is used uniformly so one mechanism covers both callers. A
ref_name-keyed name would kill a branch dispatch right after the multi-hour
kernel/image build finishes, and auto-skip downstream jobs with it.

<a id="publish-job-scope"></a>
### Publish job scope & permissions

`publish` attests provenance and creates the GitHub Release. It is a
separate job on purpose: it needs write scopes (`contents`, `id-token`,
`attestations`) that the build jobs must **NOT** have, and it needs none of
their disk reclaim or apt setup — `gh` and
`actions/attest-build-provenance`'s OIDC/Sigstore flow just work on a bare
GitHub-hosted Ubuntu runner. `needs: build` covers the kernel matrix
transitively (`build` itself needs `build-kernel`).

<a id="release-draft-gate"></a>
### Release draft gate

The release is created as a **DRAFT**, deliberately: this project's stated
posture elsewhere (`TASKS.md` P4.6, "Automerge stays OFF — a human reviews
green PRs") is that automation proposes and a human approves before anything
user-facing goes live. A draft here also means `publish-db.yml` (triggered
"on release", i.e. the `released` webhook event, which a draft does not
fire) **cannot** regenerate/publish `db.json` until a human clicks "Publish
release" — a deliberate gate between "CI built and verified an image" and
"every subscribed MiSTer in the field is offered this update". Flagged as a
decision a human should confirm, not silently assumed correct forever.

<a id="gh-repo-bug"></a>
### The GH_REPO bug

`gh` resolves the target repo from a git remote or `$GH_REPO` **only** — it
does **not** consult `$GITHUB_REPOSITORY`. The `publish` job deliberately has
no `actions/checkout` (nothing here needs the source tree), so the CWD
(`$GITHUB_WORKSPACE`) is an empty non-git dir. Without `GH_REPO`, every `gh
release view/create/upload` call dies at repo resolution with "failed to run
git: fatal: not a git repository" **before** it reaches the API: the upsert
`if gh release view` then swallows that as a false condition (`set -e` is
inert inside `if`) and misroutes into the else branch, whose `gh release
create` fails identically and aborts the step under `set -eu` — **a green
~9h build produces NO release**.

`GH_REPO: ${{ github.repository }}` hands `gh` the base repo directly, no
checkout needed. This checkout-less shape is inherited byte-for-byte from
`origin/master`'s publish job (the bug pre-dates this repo's CI rework); it
is fixed here rather than carried forward silently.

<a id="release-assets-array"></a>
### Release asset list construction

The sdcard installer images are attached unconditionally-per-existence:
`sdcard.img.xz` is always built; the full variant only when the opt-in
dispatch input was set. Attach whichever the build job actually staged into
`dist/`.

The per-variant kernel assets (today: the three `rt` files) are **not
named** here, for the same future-matrix reason as `build`'s staging step and
its `SHA256SUMS` generation — so a future `configs/mister_foo.fragment` needs
no edit here either. They are **not globbed** either: the "Verify every
kernel variant's assets survived the artifact round trip" step
(`publish`'s first real step) already expanded the registry (via
`dist/SHA256SUMS`, the only witness to it available in this checkout-less
job — see [`#variants`](#variants) for why no
`scripts/list-kernel-variants.sh` is on disk here) and asserted, BY NAME,
that all three files exist for EVERY variant. This asset list is just read
back from `$RUNNER_TEMP/variant-assets.txt`, the file that verify step wrote
— a glob-and-count here could only ever notice the ALL-missing case, and
would happily publish a release short one variant's worth of assets.

Added **unconditionally**, unlike the sdcard pair: the `build-kernel` matrix
runs on every trigger that reaches `publish`, so at least one variant's
assets existing is guaranteed — zero variants is a bug, not a valid empty
state, and the verify step has already failed the job in that case.

**Upsert, not create-only**: a tagged push already created this draft, so
the opt-in full-sdcard dispatch (which runs AGAINST that existing tag) must
ADD `sdcard-full.img.xz` to the draft rather than fail with an
already-exists error. This also lets a re-pushed/corrected tag re-attach
assets once the first run has finished. `gh release create` only ever
creates; `gh release upload --clobber` refreshes in place.

The release-notes prose (the human-readable "PREEMPT_RT beta" paragraph) is
**not** derived from the variant registry — it stays a hand-edit for any
future variant, same as `scripts/mk-sdcard.sh`'s single hardcoded
`MISTER_RT_ZIMAGE` bonus-kernel slot (one card/one bonus kernel by that
script's own design, not a variant list). See `docs/rt-beta-kernel.md`'s
"Adding a future kernel variant" paragraph for the full accounting of what is
and isn't automatic.

<a id="attest-provenance-scope"></a>
### Build-provenance attestation scope

Attests ONLY the shipped image/kernel binaries — per `TASKS.md` P4.4's scope
extended by ADR 0021 — not the whole `dist/` directory (`SHA256SUMS`/
`legal-info*`/the `.config` files are build metadata, not the shipped bits).
Every kernel-variant zImage is a binary a human boots; the one `linux.img`
now carries every variant's modules, so attesting it covers all of them too.

`dist/zImage_dtb-*` is a **glob**, not the single `-rt` name: `actions/
attest-build-provenance` resolves `subject-path` with `@actions/glob`, so
this covers whatever the kernel-variant matrix actually built — today that's
`rt`, a future `foo` needs no edit here. **NOTE**: the action does NOT fail
per pattern — it resolves the whole newline-separated set through ONE
`@actions/glob` call and errors only if the COMBINED match set is empty,
which `dist/linux.img` on the first line guarantees it never is. A
zero-match `dist/zImage_dtb-*` would therefore attest two subjects instead of
three and report **success**. The "Verify every kernel variant's assets
survived the artifact round trip" step (see
[`#release-assets-array`](#release-assets-array)) is what makes a variant
asset going missing between `build` and `publish` fail loudly — do NOT rely
on the attestation action to catch that itself.

<a id="ci-lib-source-fallback"></a>
### ci-lib.sh sourcing in release.yml's summary step

`release.yml`'s "Release overview (job summary)" step follows the identical
explicit-fallback pattern documented at
[`#ci-lib-explicit-fallback`](#ci-lib-explicit-fallback): `source
scripts/ci-lib.sh || { ...stub ci_lib_sz...; }`, so a missing helper degrades
the summary table to `n/a` cells instead of aborting a best-effort step.

---

## Part VII — reproducibility.yml

<a id="reproducibility-workflow"></a>
### What reproducibility.yml proves, and what it doesn't

See `docs/reproducibility.md` for the A9 constraint itself — what
"byte-identical" is required to mean and why it matters (trust, debugging,
CI cache correctness). What follows here is only the mechanics of how
`reproducibility.yml` proves it in CI.

A9 requires: pinned ext4 feature set, fixed UUID/hash-seed,
`SOURCE_DATE_EPOCH`, `BR2_REPRODUCIBLE=y` (all landed in P2.5 —
`configs/mister_de10nano_defconfig`) combine to make `linux.img` and
`zImage_dtb` byte-identical across two independent builds of the same
commit. P2.5 proved that ONCE, locally, for two image-generation passes over
the SAME already-built `output/` tree — it deliberately did not prove it
across two genuinely independent builds (fresh checkout, fresh runner, fresh
`output/target`), because "build discipline forbids `make clean` on the
shared tree" in an interactive session. That is exactly the gap this
workflow closes: two SEPARATE GitHub-hosted runners, each doing a full
two-stage build from a clean checkout of the same commit, comparing the two
resulting image hashes and failing loudly on any mismatch.

Structure: a `build` job with a 2-leg matrix (`build-id: [a, b]`) so the
build recipe is written ONCE but actually executed twice, on two independent
runners assigned by GitHub Actions (no guarantee of, and no attempt to
force, the same physical host — that's the point: this stands in for "two
different developers' machines"). Each leg uploads a small
`SHA256SUMS`-style artifact; a dependent `compare` job downloads both and
diffs them.

<a id="input-vs-output-caches"></a>
### Input caches vs output caches: the one rule this file must not violate

The four caches this workflow restores (Buildroot tarball, `dl/`, host
toolchain, ccache) are all **inputs** — source tarballs, a compiled
cross-toolchain, compiled-object reuse hints — that a real independent build
is entitled to share (a real-world reproducibility bug in, say, package
source content or compiler version would still need to be caught, but caching
the *toolchain build* is caching an input, not the artifact under test).

`output/target` and `output/images` — the actual rootfs assembly and the two
files being compared — are **deliberately never cached here** (`build.yml`'s
own four caches don't touch those two paths either), so both legs assemble
the target rootfs and generate both images completely fresh, every run.
Caching either would make the "two independent builds" comparison compare a
cache against itself — passing even when the underlying build is not
actually reproducible.

<a id="no-image-upload"></a>
### Why no image upload

Uploading `linux.img` (hundreds of MB) from both legs just to diff two
64-byte sha256 lines would roughly double this workflow's artifact storage
and transfer time for zero benefit — the per-leg `SHA256SUMS`-style file is
authoritative for the `compare` job's one job (detect a mismatch), and
`build.yml` (P4.1) already uploads the actual images from its own `push` runs
for anyone who needs the bytes. If a mismatch is ever caught here, the fix is
to re-run locally with the exact same recipe (this file's build steps) and
bisect — the images produced by THAT investigation are the ones worth
keeping, not a permanently-retained copy from every green run.

<a id="manual-trigger-only"></a>
### Manual-only trigger

`workflow_dispatch`, deliberately **not** `push`/`pull_request`. This is a
double build — 2x the cost of a normal one — and its shared INPUT caches
(`dl/`, host toolchain, ccache; same keys as `build.yml`) are only warm AFTER
`build.yml` has run. Wiring it to `push` would burn two *cold* builds on
every commit, in parallel with `build.yml` (3 cold Buildroot builds at once).
Instead: let `build.yml` seed the caches, then run this on demand:

```
gh workflow run reproducibility.yml --ref <branch>
```

(Add a `schedule:` here later if a periodic warm-cache check is wanted.)

<a id="repro-mister-version-unset"></a>
### MISTER_VERSION must stay unset here

`MISTER_VERSION` is deliberately left **UNSET** in this workflow's call to
`buildroot-build`, so `post-build.sh` falls back to the constant
`SOURCE_DATE_EPOCH` date (ADR 0018). A release build overrides it; a
reproducibility build must **not**, or the two legs would disagree the
moment they straddle midnight UTC.

<a id="hash-bare-filenames"></a>
### Hash from inside output/images/, not by full path

Images are hashed from **inside** `output/images/` (`cd output/images && sha256sum ...`),
not `sha256sum output/images/...`, so the recorded filenames are bare
(`linux.img`, `zImage_dtb`), not full paths — the two legs'
`GITHUB_WORKSPACE` paths happen to match today (both GitHub-hosted Ubuntu
runners under the same container image), but bare filenames make the later
`diff` correct **by construction** instead of by coincidence.

---

## Part VIII — publish-db.yml

<a id="publish-db-overview"></a>
### publish-db.yml: what it publishes and why it matters

`Downloader_MiSTer`'s `LinuxUpdater` never talks to GitHub Releases directly
— every subscribed device instead polls whatever URL its `downloader.ini` /
drop-in `db_url` names, and reads a `linux` key out of that JSON document
(`docs/downloader-contract.md` §1). This workflow is the **only** thing that
produces and publishes that document for this project. Get it wrong and
every subscribed device either never updates again, or updates when it
shouldn't, or crashes the whole Downloader run with an uncaught traceback
(§10) — see [`#schema-self-check-independent-gate`](#schema-self-check-independent-gate)
for why that last failure mode gets a dedicated, independent gate.

<a id="stable-pages-url"></a>
### The stable-URL requirement

`TASKS.md` P4.5's "Done when: ... URL is stable across releases": this job
ALWAYS deploys to the same GitHub Pages site — the repo's default
Actions-based Pages environment, whose URL never changes release to release
(for this repo: `https://mcfbytes.github.io/Buildroot_MiSTer/`, so `db.json`
lives at `https://mcfbytes.github.io/Buildroot_MiSTer/db.json` — see
`docs/downloader-contract.md` §9.5/§11.3 for the exact onboarding
`downloader.ini` line users add, which names this same URL literally). Every
run **overwrites** the previous deployment; there is deliberately no
per-release path or query string, because the entire point is that users
configure the `db_url` **once** and every future release simply becomes
available at it.

<a id="pages-prereq"></a>
### One-time GitHub Pages setup prerequisite

A human must enable "Settings → Pages → Build and deployment → Source:
GitHub Actions" on this repository **once**, before the first run of this
workflow can successfully deploy. `actions/deploy-pages` fails clearly if
this hasn't been done; it is not something a workflow file can flip on its
own.

<a id="concurrency-single-pages-target"></a>
### Concurrency: single Pages deploy target

Only one publish (and therefore one Pages deployment) in flight at a time —
there is exactly one `db.json`/Pages target for the whole repo, regardless of
which release triggered a given run, so two runs racing each other is a
correctness risk (an older run finishing last would overwrite a newer
publish), not just wasted CI time. `cancel-in-progress: false` is deliberate
too: letting a partially-applied Pages deployment get cancelled makes
reasoning about "which `db.json` is currently live" a bigger question than
making the next run simply wait its turn.

<a id="least-privilege-permissions"></a>
### Least-privilege permissions pattern

Least privilege at the workflow level (`contents: read`); the job elevates
only what actually deploying to Pages requires: `pages`/`id-token` are what
`actions/deploy-pages` needs (OIDC-based deployment, the same mechanism
`attest-build-provenance` uses in `release.yml`); `contents: read` is enough
for `gh release view`/`download` against a public release — no write scope
anywhere in this job, since it never touches the release itself, only reads
from it.

<a id="release-asset-contract"></a>
### release_YYYYMMDD.7z asset contract

Exactly one `release_YYYYMMDD.7z` asset is expected per `release.yml`'s
(P4.4) own asset set. `scripts/resolve-release-asset.sh` fails loudly, not
silently, on zero or multiple matches — either indicates a release built by
something other than this project's own `release.yml`, or a naming
regression in it. The ADR 0018 version rule this script enforces (db
version = YYMMDD = the archive's own filename, byte-for-byte matching
`/MiSTer.version`, and matching stock's own 6-char YYMMDD format — verified:
e.g. `"250402"` for `release_20250402.7z`) lives in the script's own header.
The version is derived from the **filename**, NOT `publishedAt` (which can
differ from the build/commit date and would break the version-equality
check).

<a id="asset-hash-from-live-download"></a>
### Hash/size from the live downloaded asset

`docs/downloader-contract.md` §12 item 3: `linux.hash`/`linux.size` must come
from the **actual uploaded release asset**, not a pre-upload local copy —
this job has no access to any pre-upload copy anyway (it runs in a
completely separate workflow invocation from `release.yml`), so downloading
fresh from the published Release URL satisfies this directly, rather than
needing a special self-check re-download.

<a id="schema-self-check-independent-gate"></a>
### Schema self-check as an independent gate

A SECOND, independent gate on the exact file about to be uploaded to Pages —
not merely trusting `gen-db-json.py`'s own internal check. This is
`TASKS.md` P4.5's explicitly mandated "schema self-check ... against a
vendored copy of the Downloader's expectations"
(`scripts/db_entity_contract.py`; see that file's header for why it's a
hand-mirrored reimplementation rather than a live fetch of upstream source).
`TASKS.md` P4.5's "Done when" requires this to run in CI, not just locally.

---

## Part IX — fork-sync.yml

<a id="fork-sync-why"></a>
### Why fork-sync.yml exists

This repo is the source of truth for the MiSTer kernel, but the fork
(`MiSTer-devel/Linux-Kernel_MiSTer`) is a live repo other people commit to.
Anything landing there after our last reconciliation is something we do not
have and nobody has decided about. Nothing else forces that question — and
the question does not get asked on its own: the fork sat on 5.15.1 through
210 stable releases partly because no moment ever said "these N commits are
unaccounted for".

`scripts/check-fork-sync.sh` diffs `docs/kernel-recon/fork-sync.conf` (the
last RECONCILED commit per fork branch) against the fork's live HEADs, and
this workflow opens an issue listing whatever has landed since. The queue
becomes a fact rather than a memory.

<a id="fork-sync-v6-18"></a>
### The MiSTer-v6.18 direction matters most

The direction that matters most is MiSTer-v6.18: once PR #75 merges
upstream, commits landing there are changes made to OUR series by other
people, and they **must** flow back into one of the two patch directories or
the next `make export` silently erases them:
`board/mister/de10nano/linux-patches/` if our image wants the change too, or
`board/mister/de10nano/linux-patches-upstream/` if the exported tree needs it
and our image deliberately does not (see that directory's README). That is
the failure this workflow exists to prevent.

<a id="fork-sync-cost"></a>
### Cost: cheap enough to schedule

Two compare API calls and no clone — seconds, weekly. It deliberately does
NOT check out the kernel (~300 MB) or build anything; "what is new upstream"
does not need either. This is why it can be a schedule rather than something
manual: it is far below the noise floor of the build workflow. (Contrast
`build.yml`, whose cold path is ~3h.)

<a id="fork-sync-issue-queue"></a>
### One issue, updated — not one per run

A weekly job that opens a fresh issue is a job people mute, and a muted queue
is the same as no queue. It finds its own open issue by label, edits it in
place, and closes it when the queue empties.

<a id="fork-sync-exit-codes"></a>
### Exit-code semantics: 1 is normal, 2 is a bug

Exit 1 from `scripts/check-fork-sync.sh` means "commits need triage", which
is a normal state and must not fail the job — a red X every week trains
people to ignore it. Exit 2 is a real error and MUST fail. The report is the
product; the exit code only routes it.

The script runs exactly ONCE, with `--markdown`, and that output is used for
both the log and the issue body. An earlier cut called the script twice —
plain for the log, `--markdown` for the body with `|| true` to swallow the
expected exit 1 — which was wrong twice over: `|| true` also swallows exit
2, so a broken run could file an issue with an empty body and still go
green; and two invocations are two sets of API calls that can disagree if one
hits a transient failure.

---

## Part X — lint.yml

<a id="lint-ci-overview"></a>
### lint.yml: linting the CI itself

Every workflow and composite action in `.github/` is shell glued together
with YAML, and every `scripts/*.sh` is shell full stop. Neither category gets
any syntax or semantics checking until a run actually exercises the broken
line — which, for a `runs-on:` typo or an unquoted glob in a rarely-hit
branch, can be months. Cheap (a two-binary download, no build) and scoped by
`paths:` so it never fires on the 3-hour image build's pushes.

<a id="push-pr-trigger-split"></a>
### push/pull_request split, applied even though this job is cheap

`push` scoped to `master`, `pull_request` covers everything else — exactly
the split `build.yml` documents at length (see
[`#push-trigger-scope`](#push-trigger-scope)). An unscoped `push` here would
double-run this job on every commit to an open PR branch (once for
`refs/heads/<branch>`, once for `refs/pull/N/merge`), which is the
anti-pattern `build.yml` calls out by name. Applied here even though this job
is cheap enough that skipping the discipline would be tempting — the house
rule is the house rule.

<a id="actionlint-composite-action-gap"></a>
### The actionlint + composite-action shellcheck gap

`actionlint` catches the YAML/expression class of bug (bad `runs-on:`, wrong
context, undefined `needs:`, mistyped `${{ }}`) in every workflow AND in
locally-referenced composite actions (`uses: ./...`) — that recursion is how
`.github/actions/buildroot-build`'s `action.yml` gets its YAML/schema
validated without being linted directly (passing an `action.yml` path to
`actionlint` directly does not work — see
[`#actionlint-project-mode`](#actionlint-project-mode)).

`shellcheck` is verified only through workflow-level `run:` blocks, though:
actionlint's shellcheck integration does **not** descend into a composite
action's `runs.steps[].run` bodies. This was tested directly against
actionlint 1.7.7 — shellcheck-flagged shell injected into a composite
action's `run:` produces **zero findings** in project mode, while the
identical text at workflow level is flagged. That left every composite
action under `.github/actions/*/action.yml` — `buildroot-build`,
`kernel-leg`, `merge-kernel-modules`, `verify-image`, and any future addition
— checked for YAML validity but NOT shellchecked by anything in this job: a
known, growing gap.

Extending this job to shellcheck composite-action `run:` bodies was
considered and deliberately deferred at first (doing it immediately would
also surface pre-existing shellcheck findings already living in
`buildroot-build`'s `run:` bodies, out of scope for a kernel-leg-only change
and would flip a currently-green job red for unrelated code).
`scripts/shellcheck-composite-actions.sh` (added in this same change) is what
finally closes the gap: it parses each `action.yml`'s `runs.steps[].run` into
a temp script and shellchecks that. See that script's own header for the
extraction mechanics.

`scripts/*.sh` sit outside any workflow's `run:` block entirely, so they get
their own explicit shellcheck pass — see
[`#shellcheck-scripts-coverage`](#shellcheck-scripts-coverage) — the
composite-action gap doesn't apply to them, since they're just scripts
invoked by path.

<a id="shellcheck-version-drift"></a>
### shellcheck version: soft warning, not a gate

`actionlint`'s own shellcheck integration needs `shellcheck` on `PATH`.
GitHub-hosted Ubuntu runner images ship it preinstalled; the "Verify
shellcheck is available" step fails loudly and early (rather than getting a
confusing "shellcheck disabled" actionlint warning later) if that ever stops
being true.

Unlike `actionlint` (pinned by version + sha256, see
[`#actionlint-pin`](#actionlint-pin)), shellcheck here is whatever the runner
image ships — there's no equivalent pin, because bundling our own would mean
a container or a second binary download, both rejected for the same
house-style reasons as actionlint's docker-image alternative (see
[`#actionlint-pin`](#actionlint-pin)). `SHELLCHECK_EXPECTED_VERSION` is not
enforced — a runner-image bump is not itself a bug — but a mismatch is
surfaced as a `::warning::` so a gate that goes red on an unrelated PR is
immediately traceable to "shellcheck version changed" instead of looking
like a real new bug. `'0.11.0'` was the version observed on the runner image
as of 2026-07-20, not a hard requirement — bump it to match reality whenever
the warning fires and the drift is confirmed benign.

<a id="actionlint-pin"></a>
### actionlint pin: binary + checksum, not curl|sh

Pinned by version + sha256, not an unpinned `curl | sh` installer — same
trust model as the rest of this repo's pinned-tool fetches (see
`renovate-hash-sync.yml`). A docker-image pin (`rhysd/actionlint:1.7.7`) was
the other option and does bundle shellcheck, but every other job in this repo
deliberately runs WITHOUT a `container:` (see
[`#no-container-disk-reclaim`](#no-container-disk-reclaim)) and a container
here would be the one exception for no strong reason — a plain binary
download matches house style and keeps this job's shellcheck the same one
the "Verify shellcheck is available" step just checked, rather than a second
copy baked into the image.

The checksum is actionlint's own published `actionlint_1.7.7_checksums.txt`
for the `linux_amd64` asset — **MUST re-verify** a new value at
https://github.com/rhysd/actionlint/releases before bumping
`ACTIONLINT_VERSION`.

<a id="actionlint-project-mode"></a>
### actionlint project-mode auto-discovery

No file arguments: actionlint's project-mode auto-discovery finds
`.github/workflows/*.yml` AND recurses into every LOCALLY-referenced
composite action (`uses: ./.github/actions/...`) to check its `runs:` steps
too — that is the only way this version of actionlint checks composite
actions at all, and it IS metadata/YAML-schema checking only (see
[`#actionlint-composite-action-gap`](#actionlint-composite-action-gap): the
`run:` shell bodies inside a composite action are not shellchecked by this).

Passing an `action.yml` path directly (e.g. `./actionlint
.github/actions/buildroot-build/action.yml`) makes it validate the file
against the **workflow** schema instead (`"on"`/`"jobs"` missing errors),
since actionlint has no standalone composite-action entry point.
`.github/actionlint.yaml` (self-hosted-runner labels) is picked up
automatically from the project root.

<a id="shellcheck-scripts-coverage"></a>
### shellcheck scripts/**/*.sh: recursive find, not a glob

`scripts/*.sh` are invoked from workflows via `run: scripts/foo.sh ...`,
never inlined into a `run:` block, so actionlint's shellcheck integration
never sees their contents — this step is what covers them.

`find scripts -name '*.sh'` (not a bare `scripts/*.sh` glob) is deliberate:
it also reaches `scripts/inventory/*.sh` and `scripts/triage/*.sh`, which a
non-recursive glob would silently skip. `-x` follows `# shellcheck source=`
directives (e.g. `check-abi.sh` sourcing `scripts/inventory/common.sh`) so a
real typo in the sourced file is still caught, not just the top-level
script. This does NOT cover `.github/actions/*/action.yml` `run:` bodies
either — see [`#actionlint-composite-action-gap`](#actionlint-composite-action-gap)
for the step that finally closes that separate gap.

---

## Part XI — renovate-hash-sync.yml

<a id="renovate-hash-sync-overview"></a>
### The problem this workflow solves, and its two triggers

`renovate.json`'s custom managers can bump a version string or a commit SHA,
but Renovate itself has no way to recompute a tarball's sha256 — that
requires actually fetching the artifact. Every pin this repo tracks has a
companion `.hash` file that must move in lockstep, or Buildroot's own hash
check fails the build **CLOSED** (safe, but the PR is red and useless
without a human manually redoing the hash by hand).

**Trigger 1 — automatic**: only for PRs opened by Renovate itself (the
`github.actor` check), only on branches in THIS repo (never a fork — pushing
back requires write access the default token does not get on a
fork-originated PR), and only when a file this workflow actually knows how to
fix has changed. Idempotent by design: it always recomputes from the
branch's current file content and only commits if the recomputed hash
differs from what's already there, so re-runs (e.g. a second Renovate push
to the same PR) are harmless no-ops once the hash is already correct.

**Trigger 2 — manual**, via `workflow_dispatch` with a `branch` input — see
[`#renovate-hash-sync-dispatch-trap`](#renovate-hash-sync-dispatch-trap) for
why this escape hatch has to exist at all and the trap in how to use it.

`configs/mister_kernel_defconfig` copies the main defconfig's kernel stanza,
so a 6.18 bump touches BOTH files (one Renovate PR, same depName) — both are
listed in `paths:` so a bump is still picked up if a future change ever moves
the kernel version into the copy alone. `configs/mister_rt.fragment` is
deliberately **absent** from `paths:`: its `-rc` hash cannot be
auto-refreshed (no signed manifest upstream — see
[`#renovate-hash-sync-not-automated`](#renovate-hash-sync-not-automated)), so
triggering this workflow for it would do nothing but burn a runner.

<a id="renovate-hash-sync-safety-model"></a>
### Safety model, cases 1-4: why a locally-computed sha256 is legitimate here

1. **The 12 github-sourced packages** (`package/*/*.mk` + their `.hash`): the
   11 driver/firmware pins plus `libchdr` (a userspace shared library — the
   Main_MiSTer shared-lib refactor — but the exact same
   `$(call github,...)` commit-archive shape). Their own `.hash` file
   headers already say the hash is "locally computed" — GitHub publishes no
   signed manifest for a commit/tag archive tarball, so `sha256sum` of a
   freshly-fetched tarball from the ACTUAL pinned owner/repo/ref IS the
   legitimate, standard-practice source for these (see e.g.
   `package/xone/xone.hash`'s own comment, and `pkg-download.mk` / the
   Buildroot manual). Automating exactly what a human would otherwise type
   by hand is safe here.

2. **The kernel tarball hash** (`board/mister/de10nano/patches/linux/linux.hash`),
   refreshed from kernel.org's own PGP-clearsigned `sha256sums.asc` for the
   matching v6.x series — the same URL and same trust model `docs/renovate.md`
   and the `.hash` file's own header already document as the ONLY legitimate
   source. This step does **not** verify the PGP signature (no keyring
   management here yet) — it fetches the manifest over HTTPS and greps the
   matching line, which is exactly the same trust level as the manual
   transcription process it replaces, not a regression. Verifying the
   clearsign signature is a worthwhile future hardening step, not implemented
   here.

3. **The lzma-sdk tarball hash** (`package/lzma-sdk/lzma-sdk.hash`). Same
   trust model as case 1 (upstream publishes NO checksums at all — none on
   the release, none on 7-zip.org; see the `.hash` file's own header), but it
   cannot ride the generic loop: the tarball is a GitHub release **asset**,
   not a commit/tag archive, and its filename derives from the version with
   the dots stripped (`7z2602-src.tar.xz` for 26.02), so it gets its own
   bespoke step.

4. **The sdcard payload single-file pins** (`scripts/fetch-sdcard-payload.sh`):
   `update_all.sh` and `wifi.sh` are pinned by commit AND by sha256+size;
   `renovate.json`'s git-refs managers bump the `PINNED_*_COMMIT`, and the
   sha256/size companions are recomputed from the raw file at the new commit
   — the same fetch-and-hash practice as case 1. The `_Console` cores commit
   (`PINNED_CORES_COMMIT`) has no companion hash and is deliberately not
   handled (see that script's own header).

<a id="renovate-hash-sync-not-automated"></a>
### Deliberately not automated

- **`BUILDROOT_SHA256`** (root Makefile). Per the Makefile's own header
  comment, this value is ONLY legitimate when transcribed from Buildroot's
  GPG-signed release manifest
  (`https://buildroot.org/downloads/buildroot-<ver>.tar.gz.sign`) — a
  locally-computed `sha256sum` of the downloaded tarball is explicitly
  forbidden there (circular; certifies nothing; would bless a
  tampered/truncated tarball). This workflow will NOT invent that value. A
  Buildroot-version-bump PR from Renovate is EXPECTED to stay red at `make
  buildroot-verify` until a human runs `make buildroot-showsig
  BUILDROOT_VERSION=<new>` and pastes the signed hash into the Makefile by
  hand — see `docs/renovate.md`.
- **`cabextract`, `linux-firmware-extra`, `xow-firmware`** — not tracked by
  `renovate.json` at all (no machine-readable upstream release feed for the
  first two; `xow-firmware` pins opaque Microsoft Update `.cab` GUIDs, not a
  version). See `docs/renovate.md`.
- **The RT beta's `-rc` kernel hash** (`configs/mister_rt.fragment`) — TOFU-
  pinned, no signed manifest exists for a `-rc` snapshot upstream; refreshed
  by hand per that hash file's documented procedure.

<a id="renovate-hash-sync-dispatch-trap"></a>
### Manual dispatch escape hatch, and its trap

The manual escape hatch exists because **nothing else** can re-drive this
workflow after a bug in it is fixed:

- the `pull_request` trigger's `paths:` filter does not list this workflow
  file itself, so pushing a fix to it triggers nothing;
- the actor gate skips the job when a human pushes the fix to the branch;
- and a re-run replays the workflow definition from the commit the original
  run was created against, so it re-executes the OLD code.

All three held simultaneously on run **29669946883**, which ran the same
broken kernel-URL code three times across two separate fixes.

**The trap**: the ref you dispatch **FROM** (which supplies this workflow
file) and the `branch` input you dispatch **AT** (which gets checked out and
pushed to) are deliberately different things. Dispatch from a branch whose
copy of THIS FILE is the one you want to run (normally the default branch),
and name the branch you want FIXED in the `branch` input. Conflating them is
exactly the run-29669946883 trap.

<a id="renovate-hash-sync-verification-status"></a>
### Verification status

Only the kernel step is proven against a real PR (**#41**, kernel 6.18.38 →
6.18.39). That run found two bugs the original header used to understate: an
unanchored defconfig grep that built a URL containing a newline (bug **#42**
— see [`#renovate-hash-sync-kernel-grep-bug`](#renovate-hash-sync-kernel-grep-bug)),
and the fact that a fetch failure was only ever a `::warning::` — so the job
reported **SUCCESS three times** while silently leaving `linux.hash` stale.
A green run elsewhere in this workflow can therefore mean "silently
skipped", not "verified correct". Read every warn-and-skip path in this
workflow as "this can go green without doing anything" until proven
otherwise by a real PR run.

<a id="renovate-hash-sync-branch-validation"></a>
### Branch-name validation & default-branch guard

**Reject** ref-namespace forms rather than normalising them away. git
resolves several spellings to the same branch, so a plain string comparison
against the default branch is only sound once these are excluded. Verified
with `git push --dry-run`, all three reach `master`:

```
master              ->  master     (caught by the compare below)
refs/heads/master   ->  master     (bypasses a naive compare)
heads/master        ->  master     (bypasses it too)
```

Rejecting is deliberate, not laziness: `TARGET_BRANCH` is consumed by BOTH
`actions/checkout` and the final `git push`, so the value validated here must
be the exact value those steps use. Normalising would mean re-exporting
through `$GITHUB_ENV` and relying on it overriding the job-level `env:` for
later steps — a subtlety not worth betting a force-push to the default
branch on.

<a id="pin-conventions"></a>
### actions/checkout pin convention

The same `actions/checkout` pin is used in every workflow in this repo,
including here — kept in sync so Renovate's own github-actions manager
(`renovate.json`) tracks exactly **one** `actions/checkout` dependency, not
two (or more) drifting copies.

<a id="companion-hash-first-line-only"></a>
### Companion .hash file contract: only the first sha256 line is machine-owned

Every one of the 12 github-sourced `.mk`/`.hash` pairs follows the identical
Buildroot convention:

```
<PKG>_VERSION = <commit-sha-or-tag>
<PKG>_SITE    = $(call github,<owner>,<repo>,$(<PKG>_VERSION))
```

and the resulting downloaded/hashed tarball is always named
`<package-dir-name>-<VERSION>.tar.gz` by Buildroot's own github helper (NOT
`<repo-name>-<VERSION>.tar.gz` — checked against every existing `.hash` file
in this tree before writing the loop). **Only the FIRST `sha256` line** (the
tarball itself) is ever rewritten; any further lines (LICENSE, individual
source files hashed for provenance) are left untouched — if one of those
legitimately changed too, the build's own hash check will fail closed and a
human will need to re-derive that specific line by hand.

The lzma-sdk step follows the identical only-first-line rule: the
`DOC/License.txt` and `DOC/readme.txt` provenance lines beneath the tarball
hash are left untouched by the same reasoning.

<a id="renovate-hash-sync-kernel-grep-bug"></a>
### Kernel step traps: bug #42 and the load-bearing `|| true`

**ANCHOR THIS GREP.** The defconfig explains the
`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` setting in a comment that quotes it
verbatim ("... free-form string
`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="<version>"`, which Kconfig ..."), so
an **unanchored** match returns TWO lines. That made `$kver` a two-line
string, `cut` then ran per-line, and the series came out as `"v6\n6.x"` —
producing a URL with an embedded newline that `curl` rejected outright
("Malformed input to a URL function"). Because a fetch failure is only a
warning here, the run went **green** while silently leaving `linux.hash`
stale. Anchoring plus `tail -1` keeps it to the real setting;
`scripts/export-kernel-tree.sh` reads the same file the same way.

The `|| true` after every extraction in this workflow is **load-bearing**
under `set -euo pipefail`: with no match, `grep` exits 1, `pipefail`
propagates that to the command substitution, and because these are plain
assignments, `set -e` aborts the step right there — before the explicit
empty-check that produces a real diagnostic ever runs. Swallowing the exit
status with `|| true` lets that check run and emit its diagnostic instead of
failing silently and confusingly. This pattern repeats in three more places
in this workflow (the github-package loop's `version`/`owner`/`repo`
extraction, the lzma-sdk `version` extraction, and the sdcard payload's
`commit` extraction) — in every case it exists so that the *other* pins in
the same loop, and the later steps, still get a chance to run and be
reported on, rather than one file's parse bug taking out everything after
it via an unhandled `set -e` abort.

Match by **exact string**, not a regex rebuilt inside `awk -v`, when
replacing the matched line in `linux.hash`: passing a regex through `awk -v`
would have its backslash escapes eaten, silently turning `\.` into "any
character".

<a id="renovate-hash-sync-rt-line-clobber"></a>
### RT-line clobber trap

Match the RELEASE tarball line SPECIFICALLY, never "the first sha256 line":
`linux.hash` also carries entries this step must NOT manage — notably the RT
beta's kernel (`configs/mister_rt.fragment`). A first-line match would
clobber whichever entry happened to be on top.

Scope the match to THIS pin's **major series** (`linux-<major>.*.tar.xz`).
An extension-only match (`linux-*.tar.xz`) is not enough: it is sufficient
only while the RT pin is an `-rc`, because Buildroot fetches `-rc` as a cgit
snapshot (`.tar.gz`). The moment that pin reaches a stable mainline release
it becomes `linux-7.2.tar.xz` — which the old pattern also matched.
**Verified**: with the RT line first, a 6.18 bump OVERWROTE it and left the
stale 6.18 line intact, producing two 6.18 entries and no RT entry at all.
The major-scoped match keeps the two pins on their own lines regardless of
order.

An RT kernel bump still always needs its hash refreshed BY HAND, per the
hash file's documented TOFU procedure — this step never touches that line
either way.

<a id="renovate-hash-sync-outcomes-gate"></a>
### The per-pin outcomes ledger and the job-summary gate

Added after run 29669946883 (see
[`#renovate-hash-sync-dispatch-trap`](#renovate-hash-sync-dispatch-trap)):
every warn-and-skip (and previously-silent-skip) path in this workflow now
records a per-pin outcome (`refreshed` / `already-current` / `skipped` /
`failed`) to `$HASH_SYNC_OUTCOMES_FILE`, and the "Build job summary" step
near the end of the job renders that as a table on `$GITHUB_STEP_SUMMARY` —
a skip is now visible on the run's Summary tab without opening a log — and
turns two specific conditions into a job failure:

- **(a)** any pin whose outcome is `failed` (this workflow's OWN regex could
  not parse/extract something out of a file it controls — a bug here, not
  an external hiccup), and
- **(b)** every tracked pin coming back skipped-or-failed with nothing
  refreshed or already-current, which is precisely the run-29669946883
  signature (nothing happened, yet the job would otherwise report green).

A genuine network blip on ONE pin while the rest succeed is still a
legitimate warn+skip — that case is common (upstream hiccups, a
not-yet-published release asset) and does not by itself fail the job;
Buildroot's own hash check still fails THE BUILD closed on that one stale
hash either way, so a single skipped pin is safe to leave for the next push
to retry, not safe to leave invisible.

**Follow-up hardening (same day)**: the kernel step's three `exit 1` aborts
(empty `$kver`, malformed `$kver`, ambiguous `linux.hash`) were converted to
`exit 0` so steps 3-4 still run and get their own pins reported — but that
alone silently dropped the guard those aborts used to provide for free:
previously a halted job meant NOTHING later could commit or push, so a bug
recorded by the kernel step also blocked, say, an lzma-sdk refresh from
landing on the PR branch. A dedicated "Check for a recorded workflow bug
before pushing anything" step (right before "Commit and push") now
recomputes that guard explicitly from the outcomes file — ANY pin recorded
`failed` this run suppresses the push, regardless of which of the four steps
recorded it. This step **MUST** run and be evaluated BEFORE the push; the
summary/gate step at the end of the job deliberately runs LAST (so it can
report on a push that already happened), which is exactly wrong for this
particular check, hence it is its own separate step.

`$HASH_SYNC_OUTCOMES_FILE` is scoped by `github.run_id`/`github.run_attempt`
rather than relying on the github-package loop being the first and only
writer, so an earlier abort (branch validation, checkout) can no longer
cause the summary step to render a stale/previous run's outcomes as this
run's. It is a **bare filename**, not a full path, in the job-level `env:`
block: the `runner` context (needed to reach `runner.temp`) is not available
in a job-level `env:` block (only `github`/`inputs`/`matrix`/`needs`/
`secrets`/`strategy`/`vars` are) — every step prefixes it with `$RUNNER_TEMP`
instead, which IS a plain process environment variable the runner exports
into every step's shell, no context expression required. Kept outside the
git checkout so it can never be accidentally `git add`-ed.

The summary/gate step runs on `!cancelled()` rather than `always()`: this
table's whole job is to make a skip impossible to miss, so it must still run
even if an earlier step aborted uncleanly on something unanticipated — but
`!cancelled()` (not `always()`) is deliberate too, because `always()` also
fires when GitHub cancels the run outright (this job's own concurrency group
does exactly that on every subsequent push to the same Renovate PR), and on
cancellation nothing was actually wrong — synthesizing "failed" rows and a
"workflow bug" error for pins whose steps were simply never given the chance
to run would train readers to distrust this very table. A pin whose step
never reached it (an unhandled `set -e` abort mid-loop, not one of that
step's own handled warn/fail branches) gets a distinct **"not-run"** outcome,
counted toward the fail gate but kept out of the "workflow bug" error
message specifically — it is not, itself, proof of a parse/regex bug the way
a recorded `failed` is.

`HASH_SYNC_PACKAGES` (the 12 github-sourced package pins) is a single
hoisted variable, not two independently-hardcoded lists, so step 1's loop and
the job-summary gate's pin roster at the bottom of the job cannot drift
apart.

---

## Cross-cutting conventions

<a id="branch-name-injection"></a>
### Branch name is attacker-controlled input

A branch name is attacker-controlled text on a PR from an untrusted
contributor (`github.event.pull_request.head.ref` in
`renovate-hash-sync.yml`). It is resolved **once**, as a shell variable via
`env:`, rather than repeated at each use site as an inline `${{ }}`
expansion — that closes the script-injection vector actionlint flags for
this exact pattern. Expanding an untrusted value into the script body before
bash sees it is a command-injection vector; the shell-variable form (plus
`git push origin -- "HEAD:$TARGET_BRANCH"`, where `--` stops a branch named
like an option from being parsed as one) is the safe shape.

`EXTRA_APT` in `.github/actions/buildroot-build` follows the identical
pattern for a different reason (not attacker input today, but the safe form
costs nothing): it goes through the environment rather than being
interpolated straight into the script body, because `${{ }}` inside a `run:`
block is textual substitution — the classic Actions script-injection
footgun — and the value being "ours today" doesn't make the safe form free
to skip.

(`#composite-input-validation` and `#verify-image-overview` are covered in
Part IV above, alongside the other composite-action internals.)

---

## Incident index

| Run ID / bug | What happened | Section |
|---|---|---|
| 29295920820 | ENOSPC 1h37m into host-gcc; no disk reclaim | [`#no-container-disk-reclaim`](#no-container-disk-reclaim) |
| 29293209070 | Build died at "Please configure Buildroot first" after a 52-min stage 1; no defconfig step | [`#configure-buildroot`](#configure-buildroot) |
| 29300460591 | First green cold build: 3h19m47s, 24GB output/, 2.7GB dl/, 1.1GB ccache (28%) | [`#cache-budget-and-sizing`](#cache-budget-and-sizing), [`#build-timeouts`](#build-timeouts) |
| 29529993571 | Warm run: 34945/34967 ccache hits (99.94%), 22 misses, 0.8GB payload | [`#cache-budget-and-sizing`](#cache-budget-and-sizing) |
| 29529993731 | Red build at 46 min saved 696MB ccache, zero dl/ (post-if asymmetry) | [`#cache-save-policy`](#cache-save-policy) |
| 29534917900 | Restoring toolchain cache without dl/ went green then died at legal-info; also proved a 2GB size floor insufficient | [`#cache-coupling`](#cache-coupling), [`#dl-completeness`](#dl-completeness) |
| bug #42 | Unanchored defconfig grep returned 2 lines; malformed kernel-tarball URL; job reported green 3x while linux.hash stayed stale | [`#renovate-hash-sync-kernel-grep-bug`](#renovate-hash-sync-kernel-grep-bug) |
| (verified repro) | RT-line clobber: first-line/extension-only match let a 6.18 bump overwrite the RT hash entry | [`#renovate-hash-sync-rt-line-clobber`](#renovate-hash-sync-rt-line-clobber) |
| 29669946883 | Manual dispatch replayed the same broken kernel-URL code 3x across 2 fixes (ref-vs-branch confusion) | [`#renovate-hash-sync-dispatch-trap`](#renovate-hash-sync-dispatch-trap) |
| PR #41 | Only proven real-world run of the kernel hash-sync step (6.18.38 → 6.18.39) | [`#renovate-hash-sync-verification-status`](#renovate-hash-sync-verification-status) |
| (build.yml history) | Every SHA in `gh run list` built twice (push + pull_request) before the trigger scope fix, ~6h40m/commit | [`#push-trigger-scope`](#push-trigger-scope) |
| (measured) | legal-info.tar.gz with host-sources/ included: 2109 MiB, over GitHub's 2 GiB per-asset cap | [`#legal-info-2gib-cap`](#legal-info-2gib-cap) |
| (earlier design) | From-scratch sdcard Buildroot build overran the 360-min runner cap; release never published | [`#sdcard-timing-6h-cap`](#sdcard-timing-6h-cap) |
| (inherited bug) | `gh` ignores `$GITHUB_REPOSITORY`; a green ~9h build produced no release without `GH_REPO` | [`#gh-repo-bug`](#gh-repo-bug) |
| (verified locally) | `make external-deps` without `BR2_CCACHE=y` undercounts dl/ needs: 158 vs 163 files, misses ccache itself | [`#dl-completeness`](#dl-completeness) |
| (verified locally) | An allow-list toolchain fingerprint silently missed `BR2_cortex_a9=y` (lowercase, no ARM/CPU prefix) | [`#toolchain-fingerprint`](#toolchain-fingerprint) |
