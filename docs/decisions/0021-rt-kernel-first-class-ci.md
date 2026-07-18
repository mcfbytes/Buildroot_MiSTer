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
