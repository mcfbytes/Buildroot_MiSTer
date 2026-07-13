# Reproducibility (A9)

**Task:** P4.3. **Constraint index:** A9. **Depends on:** P2.5 (`BR2_REPRODUCIBLE` +
pinned ext4 generation), P4.1 (`build.yml`, the build recipe this document's CI job
reuses). **CI:** `.github/workflows/reproducibility.yml`.

## The goal

**A9 — ext4 generation must be pinned.** Two independent builds of the same commit
must produce **byte-identical** `linux.img` and `zImage_dtb`. This matters for three
concrete reasons, not reproducibility as an abstract virtue:

- **Trust.** A user (or this project) can verify a downloaded release actually came
  from the pinned source at the tagged commit by rebuilding it and comparing hashes —
  meaningless if two runs of the same build can legitimately disagree.
- **Debugging.** If a device behaves differently after "the same" image was reflashed,
  a non-reproducible build leaves open the question of whether the *image itself*
  changed underneath the user. Reproducibility closes that question.
- **CI caching correctness.** `build.yml` (P4.1) layers four input caches (Buildroot
  tarball, `dl/`, host toolchain, ccache) under the build for speed. Reproducibility is
  the property that lets those caches be trusted as *inputs only* — if the build were
  sensitive to incidental state (timestamps, directory-scan order, a stray temp file),
  a cache hit could silently produce a different image than a cache miss would have,
  and nobody would notice.

## How this is delivered

Four mechanisms combine, all landed in P2.5 (`configs/mister_de10nano_defconfig`):

1. **`BR2_REPRODUCIBLE=y`.** Buildroot's own reproducible-build mode. Exports
   `SOURCE_DATE_EPOCH` pinned to Buildroot's own pinned-tree last-commit date (constant
   as long as the pinned Buildroot tarball doesn't change — see the root `Makefile`'s
   `BUILDROOT_VERSION`/`BUILDROOT_SHA256` pin), and — via `fs/common.mk`'s
   `ROOTFS_REPRODUCIBLE` hook — touches every file under `TARGET_DIR` to that same
   timestamp before any rootfs image (tar or ext2) is generated. This pins file mtimes
   inside the image and, to the extent ordering is driven by `TARGET_DIR`'s own stable
   directory order, file ordering too.

2. **Pinned ext4 generation options.** `BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS` in the
   defconfig hard-codes three things `BR2_REPRODUCIBLE` does **not** cover by itself:
   - **UUID and directory-hash-seed** (`-U`, `-E hash_seed=`) — both
     `/dev/urandom`-backed when left implicit (this e2fsprogs's `mke2fs.c`), so leaving
     either out would make the image's own superblock bytes non-reproducible even with
     `SOURCE_DATE_EPOCH` pinned. Fixed to two one-time `/proc/sys/kernel/random/uuid`
     draws, deliberately different from stock's own UUID (so a user with an old stock
     SD-card backup never sees a UUID collision).
   - **The ext4 feature set** (`-O has_journal,ext_attr,...,^metadata_csum_seed,
     ^orphan_file`), pinned to exactly stock's 14 features rather than inherited from
     this Buildroot's e2fsprogs defaults — the P2.5 commit caught this Buildroot's
     e2fsprogs 1.47.3 defaulting to two *additional* features (`metadata_csum_seed`,
     `orphan_file`) added upstream after stock's image was built. Left un-pinned, a
     future e2fsprogs bump could silently add more, changing the image's feature bits
     (and therefore its bytes) out from under the pin.
   - **Block size** (`-b 4096`) — already what this image size would default to, made
     explicit for the same "don't trust defaults across a bump" reason.

3. **Pinned Buildroot + kernel + patches.** The root `Makefile` pins
   `BUILDROOT_VERSION`/`BUILDROOT_SHA256` (verified against Buildroot's GPG-clearsigned
   release manifest, never against a downloaded tarball's own hash — see the
   `Makefile`'s `buildroot-showsig` comment). The kernel version, `linux.config`, and
   every patch under `board/mister/de10nano/linux-patches/` are checked into this repo.
   Nothing an CI or a developer's local build touches is fetched from a floating
   reference — same commit means same Buildroot tree, same kernel source, same patches,
   same defconfig.

4. **A checked-in config, not a locally-generated one.** `configs/mister_de10nano_defconfig`
   and `configs/mister_initramfs_defconfig` are committed. There is no `menuconfig`
   step between "clone this commit" and "build this image" — the defconfig fully
   determines the build.

## What the CI job asserts

`.github/workflows/reproducibility.yml` (triggers: `push`, `pull_request`,
`workflow_dispatch`; `timeout-minutes: 90` per build leg) runs the **same two-stage
build recipe as `build.yml`** (P4.1: `make initramfs`, then `make all`, same pinned
`ubuntu:26.04` container digest, same four *input* caches — Buildroot tarball, `dl/`,
host toolchain, ccache) on **two independent runners**, via a `strategy: matrix:
build-id: [a, b]`. Each leg:

- Builds from a **fresh checkout** of the same commit — `output/target` and
  `output/images` are never cached or shared between legs, only restored-from-scratch
  every run, so each leg's rootfs assembly and image generation happen completely
  independently. (The four *input* caches are shared across legs deliberately — see
  the workflow file's header comment for why that does not weaken the comparison.)
- Hashes `output/images/linux.img` and `output/images/zImage_dtb` with `sha256sum`
  and uploads that manifest (not the images themselves — see the workflow's "why no
  image upload" comment) as an artifact named `repro-hashes-a` / `repro-hashes-b`.

A dependent `compare` job downloads both manifests and diffs them (filename-normalized,
so only the hash values are compared). **Any mismatch fails the job**, printing both
legs' full hash listings so a diff investigation can start immediately from whichever
file (`linux.img` vs `zImage_dtb`) actually disagreed. A match prints the single
agreed-upon hash pair.

**Done when** (TASKS.md P4.3): this job is green on two consecutive commits.

## Residual nondeterminism: status

**Not yet proven by an actual double-build CI run — this section is honest about that,
not a green checkmark asserted in advance.** Two things are true and worth
distinguishing:

- **P2.5 (the defconfig/mechanism work) already demonstrated byte-identical output
  once**, locally, across two independent image-generation passes over the *same*
  already-built `output/` tree (that commit's message records the matching sha256).
  That is real evidence the mechanism (§"How this is delivered" above) works for the
  image-generation step itself.
- **What P2.5 explicitly did not attempt** — "full clean-rebuild determinism not run;
  build discipline forbids `make clean` on the shared tree" (P2.5 commit message) — is
  exactly what this workflow now automates: two genuinely independent builds, fresh
  checkouts, separate runners, full `make initramfs && make all` each, not just the
  image-generation tail end of one build re-run. That is a strictly stronger claim than
  P2.5's local proof, and it has not run yet as of this writing.

**No residual nondeterminism has been observed** — but "none observed" here means
"none observed in the narrower P2.5 check", not "the CI job in this file has run
clean". Until `reproducibility.yml` has actually gone green (ideally on two consecutive
commits, per the TASKS.md done-when), treat A9 as **designed-for and partially
verified, not yet fully proven**.

When the workflow does run — whether it passes immediately or catches a mismatch —
this section should be updated with:

- The date and commit of the first real double-build run, and its result.
- If a mismatch was ever caught: which file differed (`linux.img` or `zImage_dtb`),
  what byte-level tool (e.g. `cmp -l`, `diffoscope`) found as the root cause, and the
  fix — likely candidates, if one ever surfaces, are things §"How this is delivered"
  above does not yet pin: build-path embedding (`BR2_REPRODUCIBLE` does not rewrite
  every possible absolute-path leak the way `BR2_CCACHE_USE_BASEDIR` does for ccache
  specifically), parallel-make-driven non-determinism in a package that writes an
  unordered manifest or archive, or a kernel-build timestamp/UTS-version string not
  swept up by `SOURCE_DATE_EPOCH`.
- Any newly-discovered non-determinism source that is *not* one of the categories
  already pinned above, and the specific defconfig/patch/script change that closed it.

## Related

- `configs/mister_de10nano_defconfig` — the `BR2_REPRODUCIBLE` + ext4-options block
  (search `BR2_REPRODUCIBLE` / `BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS`).
- `scripts/check-linux-img.sh` — asserts the pinned size/label/UUID/hash-seed/feature-set
  contract (and the ADR 0015 no-baked-keys invariant) on every build; runs automatically
  via `BR2_ROOTFS_POST_IMAGE_SCRIPT`, so both legs of the reproducibility job also get
  this check for free inside their own `make all`.
- `docs/decisions/0015-per-device-ssh-host-keys.md` — why SSH host keys are generated
  on first boot rather than at build time: baking a key at build time would either
  break reproducibility (a fresh random key each build) or bake one shared key into
  every image (recreating the exact stock bug this ADR fixes).
- `.github/workflows/build.yml` (P4.1) — the single-build CI job this workflow's build
  steps are drawn from; see that file for the full caching rationale shared by both.
