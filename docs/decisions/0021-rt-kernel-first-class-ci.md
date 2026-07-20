# ADR 0021 — The PREEMPT_RT kernel variant is built by CI on every gated run and released as separate first-class assets

**Status:** Accepted (2026-07-18) — decided by @mcfbytes
**Impact:** `Makefile` (new `rt-external-deps`/`rt-legal-info` targets; `rt` now
hard-asserts `CONFIG_PREEMPT_RT=y` in the built kernel),
`.github/actions/buildroot-build` (new `variant` input), `.github/workflows/build.yml`
(new gating `build-rt` job + RT artifacts), `.github/workflows/release.yml` (new
`build-rt` job; five RT release assets, SHA256SUMS + attestation coverage),
`docs/rt-beta-kernel.md` (§5/§6/§7 updated).
**Relates to:** ADR 0018 (release versioning — the RT image bakes the same
`MISTER_VERSION`), ADR 0020 §4 (the precedent for release assets that live outside
`release_YYYYMMDD.7z`/db.json), docs/rt-beta-kernel.md (the variant itself).

## 1. The problem

`make rt` (docs/rt-beta-kernel.md) merged as a scaffold: config layering verified,
patches verified, **never once built end-to-end** — its own §6 table said so. A build
target that CI never exercises rots silently: any defconfig, patch-series, or package
change can break the RT variant and nothing goes red until someone runs a 3-hour local
build by hand. Meanwhile the variant's whole purpose (PREEMPT_RT latency testing on
hardware) needs a trustworthy, provenance-attested artifact to flash — which only CI
can produce.

## 2. Decision

1. **CI builds the RT variant on every gated run.** `build.yml` gains a `build-rt` job
   behind the same docs-gate as `build`, PRs included, and it is wired into the
   required `status` job — a PR that breaks `make rt` goes red. This deliberately
   roughly doubles a cold run's runner minutes; the demotion levers (restrict
   `build-rt` to push/dispatch via a one-line `if:`, drop it from `status`'s needs)
   are documented in the workflow for the day the cost stops paying for itself.
   Per-push artifacts are the **kernel only** (`mister-rt-kernel-<sha>`, one file
   named `zImage_dtb-rt`) plus a manifest-only SBOM (`legal-info-rt-<sha>`) — the
   full RT image set ships only in releases, keeping per-push artifact storage flat.

2. **Releases ship the RT variant as five separate first-class assets**, built by a
   `build-rt` job parallel to `build` from the same tagged commit:
   `linux-rt.img`, `zImage_dtb-rt`, `buildroot-rt.config`, `linux-rt.config`,
   `legal-info-rt.tar.gz` (sources included, host-sources excluded — a release
   distributes the 7.2 kernel binary, so the GPL accompanying-source obligation
   applies to it exactly as to main). The RT lines are appended to `SHA256SUMS` in
   `publish` (the first place both bundles coexist); provenance attestation extends
   to `linux-rt.img` + `zImage_dtb-rt`.

   **Naming rationale:** `-rt` suffix everywhere, so the merged `dist/` can never
   collide with or be mistaken for the main seven-asset set — and `zImage_dtb-rt`
   is byte-for-byte the on-device filename docs/rt-beta-kernel.md documents for
   u-boot.txt's `bootimage=/linux/zImage_dtb-rt`, so download → copy → boot needs
   no rename. `linux-rt.img` exists because the RT rootfs is the only place 7.2
   kernel modules live; the main `linux.img` carries 6.18 modules only.

3. **No duplicated build recipe.** `.github/actions/buildroot-build` gains a
   `variant` input (`main`, the default, is byte-identical in behavior *and cache
   key strings* to before; `rt` skips the configure step — `make rt` generates its
   own never-cached `output-rt/.config` — runs `make rt`/`rt-legal-info`, and uses
   `rt-external-deps` as its dl-completeness oracle). The Makefile grows those two
   `rt-*` targets (upstream Buildroot vocabulary, `rt-*` prefix precedent), and the
   `rt` target now **hard-asserts `CONFIG_PREEMPT_RT=y` in the built kernel's
   .config** — merge_config.sh only warns when a fragment symbol is dropped, so
   without this the pipeline could ship a plain 7.2 kernel labeled RT.

## 3. Cache strategy (and the 10 GB ceiling)

Buildroot cross-toolchains bake their absolute `O=` path in, so `output/host` and
`output-rt/host` can never share a cache entry. The rt variant therefore gets its own
key namespaces:

- **dl:** `br-dl-rt-<ver>-<hash(defconfig + mister_rt.fragment)>`, with restore-keys
  falling back through `br-dl-rt-<ver>-` to the **main** `br-dl-<ver>-` prefix. The
  fallback is safe against the action's documented stamp-coupling hazard: the rt
  host-toolchain cache's stamps only assert host tarballs (which the main dl has),
  and the 7.2 kernel's own stamps live in `output-rt/build/linux-*`, never cached.
- **host toolchain:** `br-rt-host-<ws_fp>-<ver>-<tc_hash>`, where the fingerprint is
  the main deny-list computation plus the same filter run over the rt fragment
  (which currently contributes nothing — correct: only a fragment line that could
  affect the toolchain should bust it).
- **initramfs toolchain:** main-only; `make rt` has no initramfs stage.
- **ccache:** shared with main (relocatable; distinct object keys coexist).

Main-variant key strings are unchanged, so existing entries keep hitting and
`reproducibility.yml` (which calls the action with no inputs) is untouched. The
additions (~2-3 GB br-rt-host, up to ~3 GB br-dl-rt) can push the repo past GitHub's
10 GB cache ceiling; that is acceptable because eviction is LRU and every cache is a
pure accelerator with a self-healing cold path. Cheapest relief levers, in order:
shrink `ccache-max-size`, then drop the rt dl save (its main-dl fallback keeps rt
warm-ish for free).

## 4. Explicitly OPEN: RT in the 7z / db.json

`zImage_dtb-rt` does **not** go inside `release_YYYYMMDD.7z` and RT gets **no**
db.json entry (docs/rt-beta-kernel.md §7 TODO #4 is thereby only half-closed). Adding
either would push RT bytes to every Downloader-subscribed device in the field — for a
kernel that has never booted on hardware. That is a human decision about the update
channel, not a CI wiring detail, and it stays open until the variant has hardware
validation behind it. `publish-db.yml` selects assets by the `^release_[0-9]+\.7z$`
regex, so the RT assets cannot leak into db.json by accident in the meantime.

## Consequences

- Every gated CI run proves `make rt` still builds, `check-abi.sh` still passes on
  the RT rootfs, and the built kernel is genuinely RT — the scaffold can no longer
  rot silently. (`ci-tests.sh` deliberately does not run against RT: it hardcodes
  the `output/` + `output-initramfs/` layout.)
- A cold gated run costs roughly two full builds' runner minutes; the demotion
  levers are documented in `build.yml` rather than left to be rediscovered.
- The release asset list grows by five; the seven-asset Downloader contract, the
  pinned-7za verification path, and db.json are all byte-untouched.
- First green `build-rt` run is still pending as of this ADR (rt-beta-kernel.md §6);
  hardware boot/latency validation remains the variant's own TODO list.

---

## Amended 2026-07-18 — one image, matrixed kernel-only builds

Decided by @mcfbytes before the original design's first green run, superseding
the sections above where they conflict (the original text is kept intact as the
record of what was first accepted).

### What changed

1. **ONE shipped `linux.img`, carrying every kernel's modules.** The measured
   main module tree is **4.9 MB** (firmware, 26 MB, was already shared and
   version-independent); linux.img is a fixed 512 MiB ext4 with ~268 MB free.
   A second module tree (~5-8 MB) is negligible, which dissolves the coupling
   that justified a whole second image: the RT variant's modules now ride
   inside the ordinary `linux.img` under `usr/lib/modules/7.2.0-rc3*/`, next
   to `6.18.38/`. **`linux-rt.img` and `buildroot-rt.config` are DROPPED as
   release assets**; the RT set is now three files — `zImage_dtb-rt`,
   `linux-rt.config`, `legal-info-rt.tar.gz` (kernel-only GPL sources,
   ~250-300 MB instead of a full image's bundle). Switching kernels is a
   u-boot.txt one-liner in both directions; **no rootfs flash is ever needed
   for RT anymore**.

2. **Kernel variants are KERNEL-ONLY Buildroot builds.** A new tracked base,
   `configs/mister_kernel_defconfig` (the main defconfig's toolchain + kernel
   stanzas mirrored, `BR2_TARGET_ROOTFS_TAR=y` so target-finalize — and thus
   depmod — runs, no packages), takes the per-variant fragment on top exactly
   as before. The copy is held in lockstep by the new
   `scripts/check-kernel-defconfig-sync.sh`, run by the composite action for
   every kernel variant (before any cache work) and as a build.yml lint.
   `make rt` builds it into `output-rt/` and stages the depmod'd tree into
   `work/extra-modules-overlay/` (gitignored; appended to the main
   defconfig's `BR2_ROOTFS_OVERLAY`; empty dir → byte-identical image), with
   a per-variant stamp so version bumps and `rt-clean` remove exactly their
   own tree. The kernel-only build embeds the same stage-1 initramfs cpio as
   main (external.mk's fixup applies to any `BR2_LINUX_KERNEL=y` build, and a
   zImage without the cpio cannot boot), so `rt` depends on `initramfs` —
   the original design's parallel `build-rt` job never ordered that and would
   have failed at kernel kconfig-fixup on its first real run.

3. **Serial pipeline: gate → `build-kernel` [matrix] → `build` → status/
   publish.** The kernel legs are a one-element job matrix
   (`strategy: matrix: kernel: [rt]`); `build` needs the matrix, downloads
   each leg's depmod'd modules tar into the overlay, runs the unchanged
   `make all`, and hard-asserts every downloaded kver ends up under
   `output/target/usr/lib/modules/`. Accepted cost: ~+1 h PR wall-clock
   versus the old parallel shape (the image build cannot start until the
   kernels exist). Adding a kernel variant is one fragment + Makefile targets
   + one matrix entry. The v1 leftovers this removes: the publish-side
   SHA256SUMS append, the main-vs-RT release_date cross-check, the RT-image
   debugfs `/MiSTer.version` validation, the RT `check-abi.sh` leg (the
   merged image is checked once, in `build`, and A-25 now checks every kver
   tree in it), and the duplicated MISTER_VERSION derivation (a kernel-only
   build bakes nothing).

4. **The sdcard installer image carries both kernels**: `zImage_dtb-rt` joins
   the FAT payload (`mister-payload/linux/`, docs/verification/
   sdcard-payload.md), so one flashable card boots either kernel via the same
   u-boot.txt line. `make sdcard` therefore now requires `make rt` (or
   `MISTER_RT_ZIMAGE=`) alongside `make all`.

5. **Variant cache derivations — §3's key formulas are superseded.** A kernel
   variant's dl key and host-toolchain fingerprint now derive from
   `configs/mister_kernel_defconfig` **plus** the variant fragment, not from
   the main defconfig §3 named: the dl key is
   `br-dl-<name>-<ver>-<hash(kernel_defconfig + fragment)>` and the
   fingerprint runs the deny-list filter over those same two files. A
   main-defconfig edit therefore no longer rotates the variant caches — only
   kernel-defconfig/fragment edits do (a toolchain-relevant main edit still
   reaches them, because `check-kernel-defconfig-sync.sh` forces the mirrored
   stanza to change in the same commit). And §3's "`make rt` has no initramfs
   stage" is inverted by item 2: every kernel leg embeds the stage-1 cpio, so
   every variant **restores and saves** the shared `br-initramfs-host` cache
   under its unchanged, variant-independent key (a kernel leg that runs first
   warms it for the main build). Main-variant key strings remain byte-identical
   throughout; the composite action's own comments are the authoritative
   walkthrough.

### Known regression accepted

The kernel-only build has **no packages**, so no OOT modules (xone, the
Realtek OOT set) are built for the variant kernel — the RT module tree is
in-tree-only. The original full-image design would have shipped a 7.2 `xone`.
Open item: a variant OOT-module story, if RT hardware testing wants it.

### The §4 open question, revisited but still open

RT stays out of `release_YYYYMMDD.7z` and db.json. Note, though, that this
amendment **strengthens** the eventual case for inclusion: the one image now
carries the RT modules, so a Downloader-updated device would receive kernel
and modules coherently instead of an orphan kernel. The blocker remains
hardware validation, not plumbing — the decision stays a human one.

## Amended 2026-07-20 — the kernel-variant registry is derived, not a matrix literal (item D)

Decided by @mcfbytes, correcting item 3 of the 2026-07-18 amendment above (kept
intact above as the record of what was decided at the time, per this ADR's own
"superseding the sections above where they conflict" convention — nothing
above is rewritten in place).

Item 3 above still describes the kernel-variant job as a one-element matrix
literal (`strategy: matrix: kernel: [rt]`) and says "Adding a kernel variant is
one fragment + Makefile targets + one matrix entry." Neither is accurate
anymore, and the second claim was already misleading the moment `release.yml`
grew its own copy of the same matrix: it actually meant one entry in EACH of
two files, silently driftable apart. Both `build.yml`'s `gate` job and
`release.yml`'s new `kernel-variants` job now derive `strategy.matrix.kernel`
via `fromJSON()` of `scripts/list-kernel-variants.sh`'s output, which reads
`configs/mister_*.fragment` — the same existence-check registry
`.github/actions/buildroot-build/action.yml` already enforces — instead of
either workflow hand-typing its own `kernel: [...]` list. That script's own
header is the authoritative walkthrough of the mechanism and its failure
modes (exit non-zero with no JSON on stdout, rather than emitting `[]`, which
GitHub Actions would run as zero legs and report as a green no-op).

Adding a kernel variant `foo` today is: `configs/mister_foo.fragment` plus its
`foo`/`foo-clean`/`foo-*` Makefile targets (docs/rt-beta-kernel.md §2; `main`
is reserved for the full-image build and is rejected by the script). Both
workflows' build matrices, `release.yml`'s release-asset list, and its
provenance-attestation `subject-path` all pick `foo` up automatically — the
attestation `subject-path` is now globbed off `dist/` rather than named, and
the release-asset list is derived per-variant from the variant names recorded
in `dist/SHA256SUMS` (the checkout-less `publish` job cannot run
`scripts/list-kernel-variants.sh`). A dedicated verify step then asserts by
name, for every variant, that all three of its files are present before either
list is used — a zero-match *or* partial-loss check, not just a zero-match
one, so a release can no longer be published short a variant's worth of
assets. That step is also what covers the attestation, which cannot police
itself: `actions/attest-build-provenance` globs its whole `subject-path` set
as a unit and errors only when the *combined* match set is empty, which the
always-present `dist/linux.img` guarantees it never is. Still requiring a human hand-edit for a new variant: the
release-notes prose in `release.yml`'s `publish` job (it describes what the
variant *is*, for a human reader) and `scripts/mk-sdcard.sh`'s bonus
real-time-kernel slot (`MISTER_RT_ZIMAGE` / `zImage_dtb-rt`), which is a
single hardcoded slot by that script's own design — one flashable card, one
bonus kernel — not a variant list. See docs/rt-beta-kernel.md's "Adding a
future kernel variant" paragraph for the same accounting kept in sync with
the code.
