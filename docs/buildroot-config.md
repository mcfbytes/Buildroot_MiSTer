# Buildroot configuration — fragments, stacks, and the reasoning behind every line

This document is the rationale for everything under `configs/`. The fragments
themselves carry only one-line section pointers (`§N.M` below) and a short
`WARNING:` next to each trap symbol; **every fact, measurement and citation
that used to live as an inline comment in the monolithic defconfigs is here**,
organised by fragment and section. When a fragment line changes, the matching
section here changes in the same commit.

History: until 2026-09 the DE10-Nano image was `configs/mister_de10nano_defconfig`
(~2,000 lines, three-quarters comments), the kernel-only base was a hand-mirrored
copy in `configs/mister_kernel_defconfig`, and the DE25-Nano developer OS was a
standalone `configs/mister_de25nano_defconfig`. All three were split into the
fragment stacks described in §1; the resolved `.config` of every stack was proved
byte-identical to what the old files produced before they were deleted (§11).

Contents:

1. [Layout and mechanism](#1-layout-and-mechanism)
2. [`common.fragment`](#2-commonfragment)
3. [`de10nano.fragment`](#3-de10nanofragment)
4. [`kernel-only.fragment`](#4-kernel-onlyfragment)
5. [`de10nano-image.fragment`](#5-de10nano-imagefragment)
6. [`de25nano.fragment`](#6-de25nanofragment)
7. [`mister_rt.fragment`](#7-mister_rtfragment)
8. [`mister_initramfs_defconfig`](#8-mister_initramfs_defconfig)
9. [`mister_installer_defconfig`](#9-mister_installer_defconfig)
10. [Placement decisions — what is common, what is board-only, and why](#10-placement-decisions)
11. [Checks, golden hashes, and the identity proof](#11-checks-golden-hashes-and-the-identity-proof)

---

## 1. Layout and mechanism

```
configs/
  fragments/
    stacks.mk                the ONE place that says which fragments form which config
    common.fragment          policy shared by every board and every kernel variant
    de10nano.fragment        DE10-Nano board layer: arch/ABI, headers series, kernel stanza
    de10nano-image.fragment  DE10-Nano shipped image: board hooks, ext4 contract, packages, system config
    kernel-only.fragment     turns a board stack into the kernel-only base variants build on
    de25nano.fragment        DE25-Nano developer OS (aarch64), layered on common only
    golden.sha256            sha256 of each stack's normalised resolved .config (§11)
  mister_rt.fragment         the RT / 7.2 kernel variant, layered on the kernel-only stack
  mister_initramfs_defconfig stage-1 initramfs cpio (standalone Buildroot config, §8)
  mister_installer_defconfig SD-card installer cpio (standalone Buildroot config, §9)
```

`stacks.mk`, in merge order:

| Stack | Fragments | Output dir | Make entry point |
|---|---|---|---|
| `de10nano` | `common de10nano de10nano-image` | `output/` | `make de10nano-defconfig` (and `make all`) |
| `de10nano-kernel` | `common de10nano kernel-only` | — (base only) | used by every kernel variant |
| `de25nano` | `common de25nano` | `output-de25/` | `make de25nano-defconfig` (and `make de25`) |
| `rt` (variant) | `de10nano-kernel` + `configs/mister_rt.fragment` | `output-rt/` | `make rt` |

**Generation** is the idiom `make rt` has used since ADR 0021: Buildroot's own
`support/kconfig/merge_config.sh -m` concatenates the stack's fragments into
`<O>/.config` (the first fragment is its base file, each later one is merged
on; it warns on any symbol a later fragment redefines), then `make olddefconfig`
resolves every symbol the fragments do not mention to its Kconfig default. That
resolves to the **byte-identical** `.config` that `make mister_<board>_defconfig`
produced — the only difference is `BR2_DEFCONFIG`, which is where
`savedefconfig` writes (§11).

**Consequences worth knowing**

- `make savedefconfig` now writes `output/defconfig` (Buildroot's default when
  `BR2_DEFCONFIG` names no file) instead of clobbering a tracked file. Fold a
  `menuconfig` experiment back into the right fragment by hand. This is an
  improvement: the old monolith's header warned that every `savedefconfig`
  round-trip silently dropped its comments and scattered its deliberately
  contiguous blocks (the debug-tooling block above all), and it kept happening.
- The old target names (`make mister_de10nano_defconfig`,
  `mister_kernel_defconfig`, `mister_de25nano_defconfig`) print a pointer to the
  new ones and fail; CI's configure step is `make de10nano-defconfig`.
- `output/.config` is generated once and then never touched by `make all` (no
  file prerequisites on the rule, so a `menuconfig` edit is not silently
  discarded — the Makefile's own comment explains). Regenerate deliberately
  with `make de10nano-defconfig` / `make de25nano-defconfig` / `make rt-clean`.
- A symbol belongs in **exactly one** fragment of a stack. A symbol set in
  `common` and overridden per board should have been board-only in the first
  place; `scripts/check-config-fragments.sh` fails on any redefinition (the
  rt fragment's kernel version + patch-dir overrides are the one allowlisted
  exception, §7).
- The kernel-only base shares `common` + `de10nano` with the image **by
  construction**. That replaces the old hand-mirrored copy; §4 and §11 say what
  the lockstep check still guards.
- Adding a board = a new `<board>.fragment` (+ optionally `<board>-image`), a
  `<BOARD>_FRAGMENTS` line in `stacks.mk`, a `BR_MAKE_<BOARD>` / `.config` rule
  pair in the Makefile mirroring the DE25's, a golden line (§11), and rows in
  `scripts/lib/board-expectations.sh`. Adding a kernel variant is unchanged
  from ADR 0021: one `configs/mister_<name>.fragment`, its Makefile targets, and
  nothing else (CI derives the matrix from the fragment glob; the fragment
  check picks it up automatically and expects it to override only what
  `ALLOWED_OVERRIDES` lists).
- `merge_config.sh` matches symbols with `grep -w`, so a fragment comment that
  quotes a symbol name defined by an EARLIER fragment is harmless (only real
  `BR2_X=` / `# BR2_X is not set` lines in the later fragment count as
  definitions), but keep comments in the fragments to one-line pointers anyway:
  the old files' verbatim-quoted symbols are exactly what produced double
  matches for Renovate's regex managers (`renovate.json`'s header) and for
  `scripts/hash-sync-kernel.sh` (bug #42).
- `# BR2_X is not set` lines are configuration, not commentary: `conf` reads
  them as an explicit `=n`. Several are load-bearing (§4.1, §5.19, §5.22,
  §5.24). Do not "clean them up".

---

## 2. `common.fragment`

Buildroot policy that every stack — both boards **and** the kernel-only base —
sets identically. Seven symbols. §10 explains why several symbols that look
shared (`BR2_TARGET_GENERIC_ROOT_PASSWD`, the ext4 rootfs choice) are
deliberately *not* here.

### 2.1 Toolchain: C++ — `BR2_TOOLCHAIN_BUILDROOT_CXX=y`

`libstdc++.so.6` is a *toolchain*-provided library, not a package
(`docs/abi-contract.md` §2.2 rows L5/L6 say so explicitly), and T8 requires it
to export `GLIBCXX_3.4.21` + `CXXABI_1.3.9`. Main_MiSTer is C++, so this is
non-optional for the project — and since it is a toolchain knob rather than a
package it belongs with the toolchain (P1.2) rather than in P2.1's package set.
GCC 14.3 satisfies T8 with enormous margin (T8 needs only GCC >= 5.1); verified
by `readelf` in the P1.2 acceptance run.

The kernel itself does not need C++, but the kernel-only stack keeps it on
purpose: partial mirroring is how two toolchains drift, and the whole toolchain
stanza is what the lockstep check compares (§4).

On the DE25 the same reasoning applies: every future consumer of that board
(starting with any Main_MiSTer port) is C++. It costs one toolchain rebuild to
add later and nothing to have now.

glibc is not a line anywhere: it is already the default C library for the
internal toolchain (`toolchain-buildroot`'s own `default
BR2_TOOLCHAIN_BUILDROOT_GLIBC`) — see `docs/decisions/0001-toolchain.md` for the
full evaluation (internal vs Bootlin external). musl is a non-goal (PLAN §3) and
would not even start the stock binary (`abi-contract.md` §1.3).

### 2.2 Download integrity — `BR2_DOWNLOAD_FORCE_CHECK_HASHES=y`

Empties Buildroot's `BR_NO_CHECK_HASH_FOR` exemption, so every download —
the pinned custom kernel tarball above all — MUST have a hash line or the
build fails closed at download time. It only forces the checking of hashes
that *exist*: where Buildroot finds the kernel's hash file is a board-fragment
matter (`BR2_GLOBAL_PATCH_DIR`, §3.3 and §6.3), and a kernel-version bump must
update `board/mister/de10nano/patches/linux/linux.hash` in the same commit
(that file's header says where the value must come from; the RT fragment's
§7.1 records the coupling in detail).

### 2.3 Kernel: pinned custom version, DTS support

`BR2_LINUX_KERNEL=y`, `BR2_LINUX_KERNEL_CUSTOM_VERSION=y`,
`BR2_LINUX_KERNEL_DTS_SUPPORT=y`. Every stack builds a kernel from an
explicitly pinned version (the value itself is per board, §3.4 / §6.4, and is
what Renovate bumps) and ships a device tree. The kernel-only stack exists
precisely to build this kernel with no userland (§4).

### 2.4 Reproducibility — `BR2_REPRODUCIBLE=y`

Byte-identical builds from the same commit (P2.5's "done when"). Exports
`SOURCE_DATE_EPOCH` (pinned to `work/buildroot`'s OWN last commit date —
top-level buildroot `Makefile:538-540` — constant as long as that pinned tree
doesn't change) and, via `fs/common.mk`'s `ROOTFS_REPRODUCIBLE` hook, touches
every `TARGET_DIR` file to it before any rootfs image is built. Does NOT, by
itself, pin mke2fs's UUID/hash-seed — see §5.2 for why those are pinned
separately on the DE10.

For the kernel-only stack it is not cosmetic even though that rootfs never
ships: `linux.mk` gates `KBUILD_BUILD_VERSION/USER/HOST/TIMESTAMP` on
`BR2_REPRODUCIBLE` (`work/buildroot/linux/linux.mk:169-175`), so without it the
variant kernel bakes the build machine's real hostname/user/wallclock into its
UTS banner — and a `release.yml` re-run on the same tag (a flow that workflow
explicitly supports) would mint a byte-different `zImage_dtb-<variant>` and
`SHA256SUMS` line, unlike every other shipped binary.

For the DE25 it is reproducibility groundwork, not a byte-identical-image
guarantee yet: it pins `SOURCE_DATE_EPOCH` and the kernel's `KBUILD_BUILD_*`
stamps, so `Image` and the module tree rebuild identically from the same
commit; `rootfs.ext4` does NOT, because mke2fs's UUID and hash seed are still
random there (the DE10 pins them via `_MKFS_OPTIONS`; the DE25 does not yet —
§6.6). Cheap, and the release lane (D2.8, "attested artifacts") will want it;
adopting it now means the first release is not the commit that discovers what
`BR2_REPRODUCIBLE` changes.

See also `docs/reproducibility.md` and `docs/decisions/0018-db-json-version-is-release-date-driven.md`.

### 2.5 Merged /usr — `BR2_ROOTFS_MERGED_USR=y`

`/bin`, `/sbin`, `/lib` are symlinks into `/usr`. Stock parity, and
load-bearing: Buildroot's own `support/scripts/check-merged -t overlay -u`
validates `BR2_ROOTFS_OVERLAY`'s shape against this at target-finalize, so
flipping it off would start rejecting the DE10 rootfs-overlay tree.

For the kernel-only stack: kernel modules physically install under
`usr/lib/modules/<kver>/` (`lib -> usr/lib`), which is the exact path the main
rootfs uses — the module tree copied out of that build's `target/` must line up
byte-for-path with where `work/extra-modules-overlay/` drops it into the main
image, or depmod's indexes point nowhere.

For the DE25, the same forward-looking reason: any future variant-module
overlay for that board has to agree with its main image about that path.

---

## 3. `de10nano.fragment`

The DE10-Nano **board layer**: everything a kernel variant must agree with the
shipped image on — arch/ABI, the headers series, the kernel stanza, the patch
and hash registry, the build-time depmod knob and the post-image script. Shared
by the `de10nano` and `de10nano-kernel` stacks; `scripts/check-kernel-defconfig-sync.sh`
fails if any symbol of these families appears in a fragment only one stack uses.

### 3.1 Arch / ABI — `BR2_arm`, `BR2_cortex_a9`, `BR2_ARM_ENABLE_NEON`, `BR2_ARM_ENABLE_VFP`, `BR2_ARM_FPU_NEON`

arm / cortex-a9 / NEON / VFPv3 / EABIhf reproduces the stock `MiSTer` binary's
own `readelf -A` tags (`abi-contract.md` §1.1, T1-T4). `BR2_ARM_FPU_NEON` is the
Buildroot FPU choice that reproduces "Tag_FP_arch: VFPv3" +
"Tag_Advanced_SIMD_arch: NEONv1" together (gcc `-mfpu=neon` — NEON mandates the
32-register VFPv3 variant; cortex-a9 only `select`s
`BR2_ARM_CPU_MAYBE_HAS_{NEON,VFPV3}`, so `ENABLE_NEON`/`ENABLE_VFP` are both
required or Buildroot silently falls back to a narrower FPU).

EABIhf itself is NOT a line because it is already Buildroot's default the
moment a CPU with an FPU is selected (`arch/Config.in.arm`: `default
BR2_ARM_EABIHF if BR2_ARM_CPU_HAS_FPU`) — savedefconfig correctly drops it as
non-divergent; verified present via readelf in the P1.2 acceptance run.

This is the P1.2 toolchain & arch/ABI work; PLAN.md §3 / `docs/abi-contract.md`
§1 are where the requirements come from, `docs/decisions/0001-toolchain.md` is
the toolchain evaluation. (The P1.2 defconfig deliberately shipped no rootfs
*packages* beyond Buildroot's own defaults — BusyBox + the toolchain's own
runtime libraries: libc, the post-2.34 libpthread/librt compat stubs,
libstdc++, installed by the toolchain, not by package selection. The ten
DT_NEEDED *packages* — zlib, bzip2, libpng, freetype, imlib2, bluez, L7-L12 —
were P2.1's job, §5.)

The stage-1 initramfs (§8) and the installer (§9) pin the same five lines —
same silicon; not an ABI requirement there, it just has to run on a Cortex-A9.

### 3.2 Kernel headers SERIES — `BR2_KERNEL_HEADERS_6_18=y`

Pins the headers SERIES explicitly. This overrides Buildroot's own default of
`BR2_KERNEL_HEADERS_AS_KERNEL` (`package/linux-headers/Config.in.host:5`), and
the override is load-bearing. **DO NOT "fix" it to AS_KERNEL to keep the headers
in lockstep with the kernel** — verified by A/B-ing the defconfig through `make
defconfig`:

```
BR2_KERNEL_HEADERS_6_18=y     -> BR2_TOOLCHAIN_HEADERS_AT_LEAST="6.18"
BR2_KERNEL_HEADERS_AS_KERNEL  -> BR2_TOOLCHAIN_HEADERS_AT_LEAST="2.6"
```

glibc is configured `--enable-kernel=$(BR2_TOOLCHAIN_HEADERS_AT_LEAST)`
(`package/glibc/glibc.mk:131`). Under AS_KERNEL our kernel version arrives as
the free-form string `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, which Kconfig
cannot compare numerically to select `BR2_TOOLCHAIN_HEADERS_AT_LEAST_6_18` — so
it silently falls back to the floor, 2.6. That would build glibc with ~15 years
of dead compatibility code and runtime syscall-fallback paths for kernels this
board will never run, and drop every 6.18-era fast path. The series pin is the
only way Buildroot learns the headers version here.

(An earlier version of this rationale justified the pin with "this defconfig
does not build a kernel itself" — that was simply false, `BR2_LINUX_KERNEL=y`
is set. Right setting, wrong reason, which is how it nearly got reverted.)

ACCEPTED CONSEQUENCE: the series resolves to whatever 6.18.x Buildroot pins for
it (`package/linux-headers/Config.in.host`, the `default "6.18.34" if
BR2_KERNEL_HEADERS_6_18` line — 6.18.34 at the time of writing, moved from
6.18.33 by the Buildroot 2026.02 -> 2026.05 bump) while the kernel is newer
(6.18.40 when this was last re-checked), so the headers lag the kernel
slightly. That is correct and harmless: headers older than the running kernel
is the supported direction, because the kernel's uapi is forward-compatible by
guarantee. Re-checked 2026-07-25 for the 6.18.40 bump: the uapi delta between
6.18.34 and 6.18.40 is FOUR added lines across THREE files, all additive —

- `include/uapi/linux/bpf.h` — two explicit `__u32 :32;` pads (`bpf_prog_info`, `bpf_map_info`)
- `include/uapi/linux/tee.h` — one explicit `__u32 :32;` pad
- `include/uapi/linux/if_link.h` — one new enum member, `IFLA_BOND_LACP_STRICT`, appended before `__IFLA_BOND_MAX`

`arch/arm/include/uapi/` is byte-identical. The `__u32 :32;` lines make padding
the compiler was ALREADY inserting explicit (both structs are
`__attribute__((aligned(8)))`), so they are not an ABI change at all; the
bonding netlink attribute is additive and this board does not use bonding, tee
or bpf uapi. Checked with `git diff v6.18.34 v6.18.40 -- include/uapi/
arch/arm/include/uapi/` (equivalently: diff the two extracted tarballs over
those two paths).

**RE-CHECK THAT DIFF ON ANY BUMP, patchlevel included — of the KERNEL or of
BUILDROOT**, since the 2026.05 bump moved the headers end of the range on its
own. It is tempting to assume only a series bump can move uapi; every line
above disproves it, since 6.18.34 -> 6.18.40 is itself a patchlevel range.
Stable rules discourage uapi changes but do not forbid them, so the diff is
the authority, not the version numbers. (This block was last found stale by
Copilot review on PR #67: it still said 6.18.33/6.18.38 after the kernel had
moved to 6.18.40 and Buildroot had moved the headers pin to 6.18.34 — neither
of which Renovate can rewrite, because both live in prose. The kernel pin has
moved again since — read it off the fragment, not off this paragraph.)

Also note linux-headers only applies `BR2_LINUX_KERNEL_PATCH` /
`BR2_GLOBAL_PATCH_DIR` under AS_KERNEL (`package/linux-headers/linux-headers.mk:82`),
so the series pin means our carried patches do not reach the headers tree.
Verified irrelevant: no patch in `board/mister/de10nano/linux-patches/`
MODIFIES a header under `include/uapi` or `arch/arm/include/uapi` (checked
against the patches' `+++ b/` target paths: zero hits). Some do mention uapi
headers in prose — 0001 cites `include/uapi/linux/fb.h` to explain an ioctl
number — but none change one; the series is drivers, one DTS, and fs/exfat.

The same point is made from the other side in §6.2: a Buildroot bump moves
the point release inside a headers series on its own (2026.02 -> 2026.05 moved
this one from 6.18.33 to 6.18.34 with no kernel bump at all), which is why the
re-check discipline above names Buildroot bumps as well as kernel bumps.

### 3.3 Global patch dir = the kernel-tarball hash registry — `BR2_GLOBAL_PATCH_DIR`

`$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/patches`. Load-bearing even
in the kernel-only stack, which has no packages to patch: it is where Buildroot
finds `board/mister/de10nano/patches/linux/linux.hash`, the ONLY thing that
hash-verifies a pinned custom kernel download (see that file's header for why
Buildroot's own lookup misses its shipped hashes — it resolves the kernel's
hash file to `linux/linux.hash`, a path that does not exist in the release; the
real hashes live in `linux/from-6.17/linux.hash`, which that lookup never
consults). That file is the repo's kernel-tarball hash registry: it carries
both the DE10's 6.18.y line and the 7.2.y line the RT variant and the DE25
track, and `scripts/hash-sync-kernel.sh` is its single automated writer. The
DE25's patch dir reaches it by symlink (§6.3).

It also carries the DE10's `bluez5_utils` patch set, which is the reason the
DE25 does NOT point at this directory (§6.3).

### 3.4 Kernel stanza

```
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.48"          (Renovate-managed)
BR2_LINUX_KERNEL_PATCH=".../board/mister/de10nano/linux-patches"
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=".../board/mister/de10nano/linux.config"
BR2_LINUX_KERNEL_LZ4=y
BR2_LINUX_KERNEL_ZIMAGE=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="intel/socfpga/socfpga_cyclone5_de10nano"
```

- The version is the 6.18 LTS line; the exact patch level is deliberately not
  repeated in prose anywhere because stable `.y` releases land weekly.
  `renovate.json`'s `kernel-longterm-6.18` manager rewrites this ONE line (the
  kernel-only stack shares this fragment, so the old "bump both defconfigs"
  hazard is gone), and `.github/workflows/renovate-hash-sync.yml` refreshes the
  companion hash in `linux.hash` from kernel.org's signed `sha256sums.asc`.
  `scripts/ci-tests.sh`, `scripts/hash-sync-kernel.sh`,
  `scripts/export-kernel-tree.sh`, `scripts/lint-kernel-patches.sh`,
  `scripts/test-initramfs.sh` and `scripts/test-sdcard-install.sh` all read the
  value off this fragment (anchored to `^`, last match — bug #42).
- `linux-patches/` is the carried MiSTer series (README "Repository layout";
  `docs/kernel-recon/`). The beta variant substitutes its own subset dir (§7.2).
- `linux.config` is a MINIMAL defconfig: an absent `CONFIG_X` is NOT "off" —
  read the resolved `output/build/linux-*/.config`. It is shared with the
  kernel-only stack and so with every kernel variant (their `CONFIG_*` deltas
  are `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` fragments, §7.3). The stage-1
  initramfs cpio is NOT named here — `external.mk`'s `LINUX_KCONFIG_FIXUP_CMDS`
  hook injects `CONFIG_INITRAMFS_SOURCE` at kconfig-fixup time (it keys on
  `BR2_LINUX_KERNEL=y` + `BR2_arm=y`, not on which stack), because
  `package/pkg-kconfig.mk:19-20` makes `make linux-update-defconfig` /
  `linux-savedefconfig` HARD-FAIL as soon as any fragment file is configured,
  and those are the commands that regenerate `linux.config`. That is also why
  the Makefile's kernel-variant targets depend on `initramfs`: without the
  cpio the kernel kconfig-fixup fails hard, and a variant zImage without it
  would panic on the FAT root at boot (`docs/boot-chain.md` I1/I2).
- LZ4 compression + zImage + the in-tree Cyclone V DE10-Nano DTS: stock parity
  (`docs/boot-chain.md`, A3). U-Boot loads `zImage_dtb`, which §3.6 assembles.

### 3.5 Host kmod with xz — `BR2_PACKAGE_HOST_KMOD_XZ=y`

`linux.config` sets `CONFIG_MODULE_COMPRESS_XZ=y`, so the `.ko` land as
`.ko.xz` and the build-time depmod (`LINUX_RUN_DEPMOD`, a target-finalize hook)
must be able to read them. HOST kmod, "support xz-compressed modules" — one of
two different things despite the shared prefix; the TARGET half
(`BR2_PACKAGE_KMOD_TOOLS`, depmod/insmod/lsmod/modinfo/modprobe/rmmod on the
device) is an image matter, §5.30. Both stacks need this one, so it lives here.

### 3.6 Post-image: zImage_dtb assembly — `BR2_ROOTFS_POST_IMAGE_SCRIPT`

P1.11 (A3): `../../board/mister/de10nano/post-image.sh` assembles `zImage_dtb`
(plain `cat zImage dtb`) and asserts its U-Boot contract
(`scripts/check-zimage-dtb.sh`) after every image build. Post-image scripts run
with `$(BR_DIR)` (`work/buildroot/`) as CWD (`system/Config.in`: "executed from
the main Buildroot source directory"), so this path is relative to THAT
directory, not `BR2_EXTERNAL` — verified against the working reference wrapper
at `/mnt/source/sb-enema` (`../../sb_enema/board/sb-enema/post-image.sh` from a
BR_DIR one level deeper than ours). A build-time checker failure here fails
`make all` (Buildroot's Makefile runs post-image scripts as plain recipe lines;
a nonzero exit stops make).

The same script serves the kernel-only stack: its `linux.img` half self-gates
on `BR2_TARGET_ROOTFS_EXT2` (absent there), so a kernel-only build gets the
kernel artifact and its contract check with nothing else. `post-image.sh` also
hard-links `rootfs.ext2` to `linux.img` for the image (§5.2).

---

## 4. `kernel-only.fragment`

Turns a board stack into the shared KERNEL-ONLY base that kernel variants
(`make rt`, and any future sibling; CI's `build-kernel` legs) build against
(`docs/rt-beta-kernel.md`, ADR 0021 as amended 2026-07-18).

**This is NOT a second image.** It exists so a variant can build a `zImage_dtb`
+ a depmod'd module tree in its own `O=` WITHOUT rebuilding the ~300 MB
userland: same toolchain, same kernel stanza, no target packages. The
per-variant delta lives in `configs/mister_<variant>.fragment`, merged on top by
the top-level Makefile. With NO variant fragment merged, this stack builds the
main 6.18 kernel — which is exactly what makes the lockstep testable.

**LOCKSTEP.** Every toolchain/kernel symbol this stack shares with the image
MUST carry the identical value, or the variant kernel is built by a different
toolchain / from different sources than the image it plugs into. Before the
fragment split this was a hand-mirrored copy held in line by
`scripts/check-kernel-defconfig-sync.sh` comparing two files; a copy can drift,
and the failure mode of drift is the quiet kind (wrong `-mcpu`, wrong headers).
Now the two stacks share `common` + `de10nano` by construction, and the check
guards the construction instead: (0) every toolchain/kernel-family symbol must
live in a fragment BOTH stacks use, (1) any symbol both stacks define must
agree, (2) the sentinels (arch, CPU, headers series, C++) must be present, (3)
choice-family name sets must match — because a kconfig CHOICE carries its
value in its NAME, so a headers or CPU bump on one side drops the old name and
adds a new one and no shared symbol ever disagrees. `scripts/check-config-fragments.sh`
(c) then proves the RESOLVED configs still agree once package `select`s are in
play (§11). CI runs the text-level check for every kernel variant before any
cache is restored and both checks in `build.yml`'s `lint-config` job.

Known follow-up, and it has now HAPPENED ONCE: the DE25 kernel pin (§6.4)
has no Renovate manager and shares `linux.hash` by symlink (§6.3), so an rt
bump handled by `hash-sync-kernel.sh --pin=rt` replaces the 7.2.y hash line
rather than adding one — and the DE25, still pinned to the old point release,
loses the only hash that verifies its tarball. 2026-09-02: Renovate's rt bump
7.2.2 -> 7.2.3 did exactly that; the DE25 pin was moved to 7.2.3 in the same
series of commits and the two are back in step (the RT variant and the DE25
have always pinned the same tarball, which is the whole reason the hash file
is shared). Had they not been moved together the DE25 build would have failed
CLOSED at download — the fail-safe direction, but a failure nonetheless.
Either a DE25 manager with the same depName as rt (one PR moves both) or a
hash-sync rule that keeps every line a fragment still pins is the standing
fix; neither is taken here.

### 4.1 No init, no shell, no BusyBox — `BR2_INIT_NONE`, `BR2_SYSTEM_BIN_SH_NONE`, `# BR2_PACKAGE_BUSYBOX is not set`

This target rootfs is never booted (it exists only to receive the module
install + depmod). All THREE lines are needed: init/sh choices default to
BusyBox, and `BR2_PACKAGE_BUSYBOX` is `default y` in its own right
(`package/busybox/Config.in`), so without the explicit not-set it quietly
builds anyway — verified by loading the config through kconfig with and without
the line. The not-set line is configuration, not a comment (§1).

### 4.2 Rootfs: tar, and ONLY tar — `BR2_TARGET_ROOTFS_TAR=y`

Deliberate, and load-bearing twice over:

1. depmod runs from `LINUX_TARGET_FINALIZE_HOOKS` (`linux.mk`), and
   target-finalize only runs when at least one rootfs image is built — tar is
   the cheapest one there is. Drop this and the module tree ships WITHOUT
   `modules.dep`/`modules.alias`, i.e. no autoload on device.
2. the tar doubles as the module-transport artifact: CI's `build-kernel` legs
   tar `target/usr/lib/modules` into the kernel artifact that the main build
   job unpacks into `work/extra-modules-overlay/`.

No ext2/no `linux.img` here — this rootfs is never flashed or shipped, which
is also why there is NO `BR2_ROOTFS_POST_BUILD_SCRIPT` (`post-build.sh` only
bakes `/MiSTer.version` into a rootfs that ships; this one doesn't) and why the
ext4 symbols are an image-fragment matter rather than a `common` one (§10).
The Makefile's `rt` recipe checks for exactly one module tree under
`output-rt/target/usr/lib/modules/` and points here if it finds zero.

---

## 5. `de10nano-image.fragment`

Everything that makes the DE10-Nano stack the SHIPPED MiSTer image rather than
a kernel-only build: board hooks, the ext4 `linux.img` contract, the full
package set, and system configuration. Nothing in it may touch the toolchain
or the kernel stanza (those are §3); package selection is by design invisible
to CI's toolchain-cache fingerprint (`docs/ci.md#toolchain-fingerprint`).

### 5.1 Board hooks: post-build script, rootfs overlays

`BR2_ROOTFS_POST_BUILD_SCRIPT="../../board/mister/de10nano/post-build.sh"` —
same `$(BR_DIR)`-relative path idiom as the post-image script (§3.6);
`post-build.sh` stamps `/MiSTer.version` and applies parity fixups.

`BR2_ROOTFS_OVERLAY` — P2.3, init & config parity overlay (`docs/init-parity.md`).
Copied onto `TARGET_DIR` after every package installs, before the permission
table and filesystem image are built (`system/system.mk`) — same
`BR2_EXTERNAL_MISTER_PATH`-relative form as `mister_initramfs_defconfig`'s own
`BR2_ROOTFS_OVERLAY`, just pointed at the full-rootfs overlay tree instead of
the initramfs one.

The SECOND entry (ADR 0021 as amended 2026-07-18) is the gitignored
`work/extra-modules-overlay/`, where kernel-variant builds stage their depmod'd
`usr/lib/modules/<kver>/` trees (`make rt` locally; CI's build-kernel
artifacts) so the ONE shipped `linux.img` carries every variant's modules.
Empty -> byte-identical image; the Makefile's `all` `mkdir -p`'s it because
Buildroot fails on a missing overlay path. NOTE: this line is part of the
toolchain-fingerprint deny-list residue in `.github/actions/buildroot-build` (it
is neither `BR2_PACKAGE_` nor `BR2_LINUX_KERNEL`), so ADDING it busted the
br-host cache exactly once — one deliberate ~3h cold main build on the PR
that introduced it. Changing it again would do the same.

### 5.2 Image generation: ext4 `linux.img`, reproducible (P2.5, A9)

Mechanism: `BR2_TARGET_ROOTFS_EXT2` (ext4 variant, `BR2_TARGET_ROOTFS_EXT2_4`),
NOT genimage. The stock artifact (`linux/linux.img`) is a single loop-mounted
ext4 filesystem with NO partition table — our `/init` losetup's + mounts it
directly (`docs/boot-chain.md`; confirmed on hardware in P1.13). genimage
exists to assemble MULTI-PARTITION disk images (MBR/GPT, bootloader + several
filesystems); here there is exactly one filesystem and nothing else to lay
out, so it would add a whole config layer to produce byte-for-byte what
`BR2_TARGET_ROOTFS_EXT2` already produces directly — Buildroot's own manual
recommends going straight to the fs/ target when no partition table is
needed, which is this case. `post-image.sh` (extended, not forked) hard-links
the resulting `output/images/rootfs.ext2` to `output/images/linux.img` (see
that script for why `rootfs.ext2`, not the `rootfs.ext4` convenience symlink
Buildroot also creates, is the canonical name here).

`BR2_TARGET_ROOTFS_EXT2_LABEL="rootfs"` — stock parity; some tooling keys on
the volume label. Kconfig's own default is already "rootfs"; explicit so a
future Buildroot default change can't silently change it under us.

`BR2_TARGET_ROOTFS_EXT2_SIZE="512M"` — 512 MiB (task text), not stock's
375 MiB. P2.1's full rootfs, once actually built into this ext4 image (with
journal/inode-table/GDT overhead), used ~198 MiB of the 512 -> measured 61.4%
free (`dumpe2fs -h`: 80433 free / 131072 total blocks), comfortably above
P2.7's 15% floor, with headroom for A8 (the updater mounts the NEW image rw and
copies 5 user-files into `/etc` before flashing) and for future package growth
without another resize. (Later measurements: §5.41, §5.45.)

`BR2_TARGET_ROOTFS_EXT2_INODE_SIZE=256` — Buildroot's own default (256).
DELIBERATE divergence from stock's 128: a 128-byte inode hits the Y2K38
timestamp problem (`mke2fs(8)` says so explicitly). Costs us nothing —
inode_size is invisible to the mount/ABI contract. (An int-type Kconfig symbol
can't carry a trailing same-line comment the way the bool/string ones can —
`conf --defconfig` treats anything after the digits as part of the value and
rejects it; verified via the "invalid for BR2_TARGET_ROOTFS_EXT2_INODE_SIZE"
warning this produced before the note was moved off the line.)

`BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS` — pinned explicitly, not left to mke2fs
defaults. Three independent reasons, each checked against the real stock
artifact (`work/extracted/files/linux/linux.img`) and this Buildroot's actual
e2fsprogs 1.47.3, not assumed:

1. FEATURE SET. `dumpe2fs -h` on the real stock `linux.img` gives exactly:
   `has_journal ext_attr resize_inode dir_index filetype extent 64bit flex_bg
   sparse_super large_file huge_file dir_nlink extra_isize metadata_csum`.
   This build's e2fsprogs 1.47.3 default `ext4` fs_type
   (`output/host/etc/mke2fs.conf`) gives that SAME 14 features PLUS
   `metadata_csum_seed` and `orphan_file` — two features e2fsprogs added to its
   own defaults some time after stock's image was built. That is the "drift
   across e2fsprogs versions" the task warned about, caught in the act: left to
   defaults, THIS build already diverges from stock's feature set, and a future
   e2fsprogs bump could add more. So every feature is forced on or off
   explicitly (`^`), not inherited from `mke2fs.conf`. This also overrides
   `fs/ext2/Config.in`'s own default of `-O ^64bit` (chosen upstream for
   pre-2017.02 U-Boot bootloaders that can't read a 64bit ext4). Irrelevant
   here: U-Boot never reads `linux.img` at all (only `uboot.img`/`zImage_dtb`
   off the FAT partition — `docs/boot-chain.md`); `linux.img` is loop-mounted
   by the KERNEL, which has supported the 64bit feature since 3.18. Stock
   itself ships 64bit ON, confirming the kernel side is fine with it.
2. UUID (`-U`) and directory-hash-seed (`-E hash_seed=`) are BOTH
   `uuid_generate()` — i.e. `/dev/urandom`-backed and RANDOM — when not given
   explicitly (this e2fsprogs's `misc/mke2fs.c:3325` and `:3348`), and the hash
   seed is written into the superblock at creation time regardless of whether
   any directory actually becomes htree-indexed. Leaving either implicit makes
   the image's own superblock bytes non-reproducible even with
   `BR2_REPRODUCIBLE=y` and an identical `TARGET_DIR` — `BR2_REPRODUCIBLE` only
   pins `SOURCE_DATE_EPOCH` (timestamps, below); it does not touch mke2fs's own
   UUID/seed generation. The two fixed values are two separate
   `/proc/sys/kernel/random/uuid` draws, pinned once and never regenerated —
   deliberately DIFFERENT from stock's own UUID
   (`50ef310c-47b9-4c1c-a2fe-d0202d02b6b4`) so a user who still has a stock
   SD-card backup lying around never has two filesystems with the identical
   UUID visible to the same host at once.
3. `-b 4096`: already what `mke2fs.conf`'s `[defaults]` section would pick for
   an image this size, made explicit for the same "don't trust the defaults to
   hold across an e2fsprogs bump" reason as (1).

`SOURCE_DATE_EPOCH` (via `BR2_REPRODUCIBLE`, §2.4) covers the remaining source
of mke2fs non-determinism: this e2fsprogs (`lib/ext2fs/initialize.c`) reads
`SOURCE_DATE_EPOCH` for the filesystem's own created/last-write superblock
timestamps, and `fs/common.mk`'s `ROOTFS_REPRODUCIBLE` hook touches every file
under `TARGET_DIR` to that same timestamp before ANY rootfs image (tar or ext2)
is generated — so file mtimes inside the image are pinned too, and so is file
ORDERING to the extent it's driven by `TARGET_DIR`'s own (stable,
un-mutated-between-builds) directory order — see the P2.5 acceptance run for
the actual two-build byte-identical proof.

`scripts/check-linux-img.sh` asserts this whole contract against the built
image (label, UUID, hash seed, size, sorted feature set); its expected values
MUST be kept in sync with this fragment by hand — there is no single source
of truth to derive them from at build time. See also `docs/reproducibility.md`.

### 5.3 P2.1 — the full package set: provenance and preamble

Source of truth: `docs/package-manifest.md` §6 "Ready-to-paste BR2_PACKAGE_*
list" (P0.7's deliverable). §5.4–§5.23 are that list, applied verbatim, EXCEPT
for the imlib2 loader sub-options (§5.6) which P0.7 did not include — it mapped
SONAMEs, not `dlopen()`'d plugins, and `abi-contract.md` §2.2 explicitly warns
imlib2's loaders are invisible to a DT_NEEDED/SONAME scan (they're dlopen'd
from `usr/lib/imlib2/loaders/*.so` at runtime) and must be turned on by hand or
`menu.png`/`menu.jpg` backgrounds silently fail to load. Verified against
`docs/stock-inventory/shared-libraries.md`'s on-device loader list
(argb/bmp/bz2/ff/gif/ico/id3/jpeg/lbm/png/pnm/tga/xpm/zlib) — everything
except gif/id3/jpeg/png/tiff builds into imlib2 unconditionally with no
Buildroot Config.in gate, so enabling those five reproduces stock's loader set
exactly (`package/imlib2/Config.in`, checked against the then-pinned Buildroot
2026.02.3 and NOT re-checked since the 2026.05 bump — a dated finding, not a
standing guarantee).

Every symbol was cross-checked against the actual pinned Buildroot tree's
`Config.in` files (not from memory) before being pasted — see the P2.1 task's
verification pass. `BR2_PACKAGE_UTIL_LINUX_BINARIES` IS enabled (§5.11): stock
actually ships the real util-linux mount/umount/blkid/fdisk/dmesg/agetty/...
(2.36.2 ELF binaries, not BusyBox — verified against `work/imgroot`), so
shipping the util-linux programs is the parity-correct choice. The earlier
"covered by BusyBox" note was wrong about what stock shipped. See
`docs/util-linux-parity.md`. Samba's AD DC / ADS / smbtorture sub-options are
deliberately left unset (standalone file server only, manifest §5 Drop list) —
BusyBox and every other package is otherwise the full manifest, ungated.

`BR2_ENABLE_LOCALE` is deliberately NOT listed even though the manifest
recommends it: it is already `=y` in the built `output/` (glibc's own default
for this toolchain, confirmed in `output/.config`) and it lives in the
*toolchain* Kconfig menu — P1.2's hazard ("Buildroot silently ignores
toolchain menu changes on an incremental build") means touching that menu at
all is a make-clean-and-rebuild-from-scratch decision. Since the effective
value doesn't change (y -> y), adding it buys nothing and only invites that
risk for zero benefit. `BR2_ENABLE_LOCALE` only compiles locale *support* into
glibc; it does not generate any locale *data*. That is a separate knob — §5.44
— and leaving it empty is what shipped an image with no
`/usr/lib/locale/locale-archive` at all.

### 5.4 compression

- `BR2_PACKAGE_ZLIB=y` — meta-prompt (the virtual package).
- `BR2_PACKAGE_ZLIB_NG=y` — NOT `BR2_PACKAGE_ZLIB` alone: the concrete
  provider. zlib-ng in `ZLIB_COMPAT` mode, not classic zlib. `package/zlib`'s
  Config.in is a virtual package with a choice between `BR2_PACKAGE_LIBZLIB`
  and `BR2_PACKAGE_ZLIB_NG`; `ZLIB_NG_ARCH_SUPPORTS` is `default y if BR2_arm`
  (and `BR2_aarch64`, so this survives a 64-bit port). `zlib-ng.mk` builds
  `-DZLIB_COMPAT=1`, so it installs `libz.so.1` and every consumer follows
  transparently.

  BLAST RADIUS, measured on the rig before making the switch. Inside
  Main_MiSTer the dynamic libz is used by exactly two things:
  `support/uef/uef_reader.cpp` (gzip-wrapped UEF tape images — BBC Micro /
  Acorn Electron only), and libpng16/Imlib2 for the OSD background images and
  boot logo (`video.cpp:3822+`). It is NOT used for CHD: stock compiles libchdr
  in statically and that copy includes `<miniz.h>`, whose compat macros rewrite
  `inflate -> mz_inflate`, so every CD core decodes through miniz inside the
  binary. Verified from the published release binary, not just the Makefile.

  Verified on-device with the library preloaded: PNG decode through imlib2 ->
  libpng -> zlib succeeds identically, gzip round-trips, and curl reports
  "zlib/1.3.1.zlib-ng" while still working. No package we enable selects
  `BR2_PACKAGE_ZLIB_FORCE_LIBZLIB` (only assimp/clamav/quazip do, none of them
  ours).

  WHY: measured CHD decode win for the greenfield firmware, which unlike stock
  links the SHARED libchdr and so does reach system zlib — audio hunks p90 -10
  to -11%, max -7 to -15%. See `harness/rig/chd-decode-optimization.md` in
  Main_MiSTer for the numbers. (`docs/abi-contract.md` records the zlib-ng
  2.3.3 selection.)
- `BR2_PACKAGE_BZIP2=y`, `BR2_PACKAGE_XZ=y`, `BR2_PACKAGE_LZO=y`.
- `BR2_PACKAGE_ZSTD=y` — `libzstd.so.1` + the zstd CLI (upstream has no
  sub-option to omit the CLI). Needed by libchdr (CHD v5 zstd hunks) and flips
  minizip-ng's `MZ_ZSTD=ON`.
- `BR2_PACKAGE_MINIZIP=y` — IS minizip-ng 4.0.3 (zlib-ng/minizip-ng); the
  concrete provider matters here exactly like the ZLIB provider above: this
  is NOT the classic zlib-contrib zip.h/unzip.h library (that one is
  `BR2_PACKAGE_MINIZIP_ZLIB`, next). Buildroot forces `-DMZ_COMPAT=OFF`
  (`work/buildroot/package/minizip/minizip.mk`), so there is no zip.h/unzip.h
  compat layer at all — the `mz_zip.h` native API is here for an eventual
  Main_MiSTer port to it. Installs `libminizip-ng.so.4` + `minizip-ng.pc`.
  Feature set under THIS configuration (`minizip.mk` keys each `MZ_*` feature
  off other `BR2_PACKAGE_*` symbols): bzip2 + openssl (pkcrypt/wzaes) +
  lzma-via-xz + zlib + zstd (the ZSTD=y above); NO iconv — `BR2_ENABLE_LOCALE=y`,
  so minizip's `select BR2_PACKAGE_LIBICONV if !BR2_ENABLE_LOCALE` stays off.
- `BR2_PACKAGE_MINIZIP_ZLIB=y` — the CLASSIC zlib-contrib minizip (zlib 1.3.1's
  `contrib/minizip`, autotools) — a SEPARATE package from minizip-ng. SONAME
  `libminizip.so.1`, the zip.h/unzip.h API (`zipOpen`/`unzOpen`). Enabled for
  backward compatibility: the current Main_MiSTer shared-lib cleanup links
  `libminizip.so.1` (a NEEDED entry in the MiSTer binary), so the target must
  ship it or MiSTer fails at exec with "cannot open shared object file". It
  coexists with minizip-ng — distinct SONAME (`.so.1` vs `-ng.so.4`) and
  non-overlapping symbols (`zipOpen`/`unzOpen` vs `mz_*`), so both load
  conflict-free.

### 5.5 Main_MiSTer shared libs

The BR2_EXTERNAL half of the Main_MiSTer shared-lib refactor (no task ID —
referenced by name): Main stops vendoring `lib/{lzma,zstd,miniz,libchdr}` and
links Buildroot-provided shared libraries; the upstream half (zstd, minizip-ng)
is §5.4. Both packages are authored under `package/`; see
`docs/main-shared-libs.md`.

- `BR2_PACKAGE_LZMA_SDK=y` — 7-Zip LZMA SDK 26.02 as `liblzma-sdk.so.<ver>`;
  the full-version SONAME is the deliberate loud-ABI-event policy: the Main
  binary lives on `/media/fat` and SURVIVES rootfs reflashes, so an SDK bump
  must refuse-to-load, not corrupt (`package/lzma-sdk/lzma-sdk.mk`).
- `BR2_PACKAGE_LIBCHDR=y` — `libchdr.so.0`; commit-pinned past v0.3.0 for the
  Findzstd pkg-config fallback (the tag cannot configure against Buildroot's
  zstd); system zlib/zstd/lzma-sdk via our 3 patches; exports `chd_*` ONLY
  (version script), so no symbol collisions with minizip-ng et al.

### 5.6 graphics / fonts

`BR2_PACKAGE_FREETYPE`, `BR2_PACKAGE_LIBPNG`, `BR2_PACKAGE_JPEG` (meta-prompt),
`BR2_PACKAGE_JPEG_TURBO` (default on ARM/NEON; builds `-DWITH_JPEG8=ON` ->
`libjpeg.so.8`, matching stock exactly), `BR2_PACKAGE_TIFF`, `BR2_PACKAGE_GIFLIB`,
`BR2_PACKAGE_IMLIB2` (critical ABI-contract SONAME `libImlib2.so.1`),
`BR2_PACKAGE_IMLIB2_{JPEG,PNG,GIF,TIFF,ID3}` — loader plugins, dlopen'd, NOT
in the manifest's paste list, added per `abi-contract.md`'s explicit warning
(§5.3): without these `menu.png`/background images silently fail to load with
no DT_NEEDED signal — `BR2_PACKAGE_LIBXKBCOMMON`, `BR2_PACKAGE_SDL2`.

### 5.7 audio

`BR2_PACKAGE_ALSA_LIB` (provides libasound + libatopology together),
`BR2_PACKAGE_LIBAO`, `BR2_PACKAGE_LIBVORBIS` (provides vorbis + vorbisenc +
vorbisfile together), `BR2_PACKAGE_LIBOGG`, `BR2_PACKAGE_MPG123` (provides
libmpg123 + libout123 together), `BR2_PACKAGE_LIBID3TAG`,
`BR2_PACKAGE_LIBMODPLUG`, `BR2_PACKAGE_FLUIDSYNTH`,
`BR2_PACKAGE_FLUIDSYNTH_ALSA_LIB` (ALSA-seq MIDI backend — needed for stock's
ALSA MIDI device list to match, P3.8).

### 5.8 MIDI / MT-32 (P3.8) and ALSA CLI tools (P3.15)

munt (mt32d) + MidiLink reproduce stock's MIDI/MT-32 stack: MidiLink
(`usr/sbin/midilink`, `usr/sbin/mlinkutil`) is the ALSA-seq client that shells
out to mt32d (munt) or fluidsynth on demand. Neither has an upstream Buildroot
package — both authored under `package/`. See `docs/midi-mt32-parity.md`.
`BR2_PACKAGE_MUNT=y`, `BR2_PACKAGE_MIDILINK=y`.

alsa-utils MIDI tools — stock ships amidi/aplaymidi/arecordmidi/aseqdump/
aseqnet/aconnect (`docs/stock-inventory/binaries-needed-full.txt`), the tooling
that exercises the ALSA-seq MIDI graph: `BR2_PACKAGE_ALSA_UTILS` +
`_ACONNECT`, `_AMIDI`, `_APLAYMIDI`, `_ARECORDMIDI`, `_ASEQDUMP`, `_ASEQNET`.

General (non-MIDI) ALSA CLI tools (P3.15) — stock ships all of these
(`docs/stock-inventory/binaries-needed-full.txt`); the P3.8 MIDI pass
deliberately left them for this separate general-ALSA-parity pass. alsactl
(mixer save/restore), alsamixer/amixer (volume), aplay/arecord (`APLAY`
provides both), alsabat (`BAT`), alsaloop, alsatplg, alsaucm, iecset (S/PDIF
status bits), speaker-test (channel test tones) — every one of these is
present in `binaries-needed-full.txt`: `_ALSACTL`, `_ALSALOOP`, `_ALSAMIXER`,
`_ALSATPLG`, `_ALSAUCM`, `_AMIXER`, `_APLAY`, `_BAT`, `_IECSET`,
`_SPEAKER_TEST`. NOT enabled: alsaconf — stock never shipped it (it has an
option here but no stock binary to match). One stock ALSA binary has no parity
path at all: `usr/bin/aserver` IS in stock, but alsa-utils 1.2.15 exposes no
`BR2_PACKAGE_ALSA_UTILS_*` target for it (dropped upstream), so it cannot be
selected — see `docs/midi-mt32-parity.md` section 5.

### 5.9 crypto / TLS

`BR2_PACKAGE_OPENSSL=y` (meta-prompt), `BR2_PACKAGE_LIBOPENSSL=y` — NOT
`BR2_PACKAGE_OPENSSL` alone: the concrete provider. 1.1 -> 3.6.2, SONAME
`.so.1.1` -> `.so.3`, harmless (everything rebuilt together, see the risk
table). `BR2_PACKAGE_GNUTLS`, `BR2_PACKAGE_LIBGCRYPT`, `BR2_PACKAGE_LIBSSH2`.
nettle, gmp, libtasn1, libgpg-error, libffi are all pulled in transitively as
dependencies of gnutls/gcrypt/samba4/python3 — do not set separately (the
debug-tooling block, §5.42, relies on that for GMP).

`BR2_PACKAGE_CA_CERTIFICATES=y` — CA trust store (found missing on hardware):
without it, curl's default CA path `/etc/ssl/certs/ca-certificates.crt` is
absent and every HTTPS verify fails ("error adding trust anchors"), which also
breaks Downloader_MiSTer's HTTPS fetches. Installs the Mozilla bundle as
`ca-certificates.crt` + OpenSSL hashed symlinks (curl + python default
context). The `cacert.pem`/`cert.pem` aliases the Downloader
(`DEFAULT_CACERT_FILE=/etc/ssl/certs/cacert.pem`) and stock expect are added
as overlay symlinks -> `ca-certificates.crt`. Functional parity with stock's
`cacert.pem` CA story. Deliberately kept explicit here even though azcopy
(§5.38) would `select` it, so it survives azcopy being switched off again.

### 5.10 networking / D-Bus / GLib

`BR2_PACKAGE_LIBCURL`, `BR2_PACKAGE_LIBCURL_CURL` (installs the `curl` CLI
binary — off by default, stock ships it, community scripts use it),
`BR2_PACKAGE_LIBCURL_OPENSSL` (TLS backend parity: stock's curl links
libcrypto/libssl, not GnuTLS).

`BR2_PACKAGE_WGET=y` — GNU wget, stock parity restored (issue #130,
2026-09-01). Stock ships a real GNU wget ELF at `usr/bin/wget` linked against
`libgnutls.so.30`, `libnettle.so.8`, `libpcre.so.1`, `libuuid.so.1` and
`libz.so.1` (`docs/stock-inventory/binaries-needed-full.txt:351`), plus GNU
wget's own `/etc/wgetrc` — 4945 bytes, see `etc-configs.md:1097` — a file
BusyBox's applet never reads. Stock's BusyBox 1.33.1 ALSO had the wget applet
compiled in (`busybox-applets.md:278`), but the GNU ELF owned the path, so the
applet was unreachable as `wget` — the same "two providers, one path" shape as
ifup/util-linux/lsof. This image previously shipped ONLY the BusyBox applet,
with `CONFIG_FEATURE_WGET_HTTPS` and `CONFIG_FEATURE_WGET_OPENSSL` both off, so
`SSL_SUPPORTED` was 0 and every https:// URL died at `networking/wget.c:578`
with "wget: not an http or ftp url:" — while curl worked, which is exactly how
issue #130 was reported. The recorded reason for leaving wget out was the
PCRE1 removal note (§5.15: "the only stock consumers were wget/zsh, neither of
which we build"). That premise is stale: this Buildroot's `wget.mk:16` passes
`--disable-pcre` UNCONDITIONALLY, so GNU wget does not want PCRE1 at all, and
`wget.mk:67` gives it `--enable-pcre2` against the `BR2_PACKAGE_PCRE2` we
already ship. Nothing here resurrects PCRE1. TLS backend is GnuTLS, matching
stock, and for free: `wget.mk:26` prefers `BR2_PACKAGE_GNUTLS` over OpenSSL
when both are present, and we set both. Built and readelf'd, not predicted
(2026-09-01): the resolved DT_NEEDED is `libgnutls.so.30`, `libnettle.so.8`,
`libuuid.so.1`, `libz.so.1`, `libc.so.6` and `ld-linux-armhf.so.3` — identical
to stock's — plus `libpcre2-8.so.0` where stock had `libpcre.so.1`, plus
`libunistring.so.5`, which stock's older wget did not link. The last one is
free: `BR2_PACKAGE_LIBUNISTRING` was already set and the .so was already in
the image before this change. libpsl, libidn2 and c-ares stay out
(`wget.mk:18/40/60` take their `--without`/`--disable` branches), which is also
what stock did — none of the three is in stock's list either. The installed
`/etc/wgetrc` is 4945 bytes, byte-for-byte stock's size, and the ARM binary's
`--version` banner reports "+https ... +ssl/gnutls" under qemu-arm.
Prerequisites were already satisfied, nothing else had to change:
`BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y` (§5.15), `BR2_USE_WCHAR=y` and
`BR2_USE_MMU=y`. The colliding BusyBox applet is turned off in
`board/mister/de10nano/busybox.fragment` so this binary wins deterministically
(same idiom as ifup/ifdown and the util-linux block). Real GNU wget 1.25.0 w/
GnuTLS — https works, `/etc/wgetrc` is read (stock parity).

`BR2_PACKAGE_DBUS`, `BR2_PACKAGE_DBUS_CPP` (dbusxx-introspect; low-value but
zero-cost parity), `BR2_PACKAGE_DBUS_GLIB`, `BR2_PACKAGE_LIBEVENT`,
`BR2_PACKAGE_LIBNL`, `BR2_PACKAGE_IPTABLES`, `BR2_PACKAGE_LIBGLIB2`,
`BR2_PACKAGE_GOBJECT_INTROSPECTION`.

### 5.11 util-linux / e2fsprogs / disk & fs tools

`BR2_PACKAGE_UTIL_LINUX` + `_LIBBLKID`, `_LIBFDISK`, `_LIBMOUNT`,
`_LIBSMARTCOLS`, `_LIBUUID` — each lib sub-option defaults to "n": must be
listed explicitly or the corresponding SONAME won't be built.

util-linux BINARIES + programs — stock parity (usbmount work). Stock ships
real util-linux 2.36.2 ELF binaries for mount/umount/blkid/fdisk/dmesg/agetty/
hwclock/... (NOT BusyBox — verified against `work/imgroot`), so we ship them
too (2.41.4 here). The util-linux `mount` matters functionally: it dispatches
`mount -t ntfs` to the `/sbin/mount.ntfs -> ntfs-3g` helper, which BusyBox
mount cannot do (no `CONFIG_FEATURE_MOUNT_HELPERS`) — that is how NTFS USB
drives auto-mount under usbmount, exactly like stock. The overlapping BusyBox
applets are turned off in `board/mister/de10nano/busybox.fragment` so these
win deterministically (same idiom as ifupdown). The libs above are already
selected; BINARIES re-selects them harmlessly. Full stock<->ours program map:
`docs/util-linux-parity.md`.

- `_BINARIES` — basic set: blkid, blockdev, dmesg, fdisk/sfdisk, findfs,
  findmnt, flock, fstrim, getopt, hexdump, lsblk, lscpu, mkswap,
  setarch(+linux32/64), setsid, swapon/swapoff, ... (stock's set)
- `_MOUNT` — mount + umount, the functional core (helper dispatch to mount.ntfs)
- `_MOUNTPOINT` — mountpoint
- `_AGETTY` — serial-console getty; inittab uses it, replacing BusyBox getty (stock parity)
- `_HWCLOCK` — hwclock (manual/debug; no S05rtc, like stock; `docs/rtc-parity.md`)
- `_FSCK`, `_PARTX` (addpart/delpart/partx/resizepart), `_SCHEDUTILS`
  (chrt/ionice/taskset), `_IRQTOP` (irqtop/lsirq), `_KILL`, `_MORE`,
  `_NEWGRP`, `_NOLOGIN`, `_RENAME`, `_SETTERM`, `_SWITCH_ROOT`
- NB: util-linux `raw` (stock had `/sbin/raw`) is intentionally NOT enabled —
  its Config.in `depends on !BR2_TOOLCHAIN_HEADERS_AT_LEAST_5_14` and our 6.18
  headers are >= 5.14, so the raw(8) char-device interface (removed from the
  kernel in 5.14) is unbuildable. Obsolete; no BusyBox `raw` applet either, so
  nothing is lost.

`BR2_PACKAGE_E2FSPROGS`, `BR2_PACKAGE_PARTED`.

`BR2_PACKAGE_NTFS_3G=y` — stock has no NTFS driver at all (kernel side); this
is userland-only parity for exFAT/NTFS USB drives via FUSE, matches stock's
ntfs-3g. `BR2_PACKAGE_NTFS_3G_NTFSPROGS=y` — T5 (2026-07-27): mkfs.ntfs/ntfsfix
DID NOT LAND with NTFS_3G alone — a real oversight, not a deliberate omission,
found while auditing stock's util binaries. `BR2_PACKAGE_NTFS_3G=y` alone only
builds the ntfs-3g FUSE driver + mount.ntfs-3g; the rest of ntfsprogs
(mkntfs/mkfs.ntfs, ntfsfix, ntfsclone, ntfsresize, ntfslabel, ...) is gated by
this separate sub-option, which defaults to "n" with no dependency of its own
(`package/ntfs-3g/Config.in:27-30` — "config BR2_PACKAGE_NTFS_3G_NTFSPROGS /
bool 'ntfsprogs' / help / Install NTFS utilities.", no "default", no "depends
on"). Confirmed via the .mk too: without this symbol `ntfs-3g.mk` passes
`--disable-ntfsprogs` to configure (`ntfs-3g.mk:32-34`). PATHS ARE SPLIT, and
not the way "ntfsprogs" suggests — `ntfsprogs/Makefile.am:17` puts `ntfsfix`
(with ntfsinfo/ntfscluster/ntfsls/ntfscat/ntfscmp) in `bin_PROGRAMS` ->
`/usr/bin`, while `:18`'s `sbin_PROGRAMS` holds
mkntfs/ntfslabel/ntfsundelete/ntfsresize/ntfsclone/ntfscp -> `/usr/sbin`, and
the install-exec-hook at `:166-169` adds the `mkfs.ntfs -> mkntfs` symlink
beside mkntfs in sbin. `ntfs-3g.mk` passes no `--exec-prefix` override (unlike
`dosfstools.mk:13`'s `--exec-prefix=/`), so bindir really is `/usr/bin`. Stock
lands exactly the same way — `work/imgroot` has `usr/bin/ntfsfix` and
`usr/sbin/{mkntfs,mkfs.ntfs}`, and NO `usr/sbin/ntfsfix`. `scripts/ci-tests.sh`'s
T5 block asserts both paths in that split. Worth spelling out because the
first draft of that gate asserted `usr/sbin/ntfsfix` — which would have failed
deterministically on the first real build; it was caught in review, before any
build ran, not at runtime.

`BR2_PACKAGE_KMOD`, `BR2_PACKAGE_INOTIFY_TOOLS`, `BR2_PACKAGE_JQ`,
`BR2_PACKAGE_EXPAT`, `BR2_PACKAGE_POPT`, `BR2_PACKAGE_READLINE`,
`BR2_PACKAGE_NCURSES`.

`BR2_PACKAGE_NCURSES_WCHAR=y` — WIDE-CHAR ncurses. Not cosmetic — it is an
ABI-contract fix. Plain `BR2_PACKAGE_NCURSES` builds the NARROW
`libncurses.so.6`; the wide `libncursesw.so.6` only comes from `--enable-widec`
(this symbol). `docs/package-manifest.md:193` lists the required SONAME as
`libncursesw.so.6`, stock ships exactly that, and 35 stock binaries (bash,
dialog, clear, dmesg, alsamixer, ...) DT_NEEDED it — so a libncursesw-linked
ARM binary dropped on the device would fail to start against our narrow lib.
This was shipped narrow by omission: the manifest mapped the libncursesw
SONAME to `BR2_PACKAGE_NCURSES` without noting that the "w" requires this
second symbol. It also restores wide-char curses in Python (the build symlinks
`libncurses.so -> libncursesw.so`, so `_curses`/`_curses_panel`/`readline` all
relink against the wide lib): our narrow `_curses` lacks the wide-char
key-read API — the `window.get_wch()` method and its module-level companion
`_curses.unget_wch`, both compiled in only against ncursesw. A TUI that reads
a keystroke via `window.get_wch()` — e.g. to catch the UP arrow — hits
`AttributeError` on narrow ncurses and commonly falls back to line mode, where
the arrow just echoes as `^[[A` instead of being captured. Enabling widec is
what stock has and what makes `window.get_wch()` work. Narrow -> wide is a
clean-rebuild change.

`BR2_PACKAGE_SLANG`, `BR2_PACKAGE_NEWT`, `BR2_PACKAGE_GPM`,
`BR2_PACKAGE_LIBARCHIVE` (keep the library — samba4 can use it; do NOT package
archivemount itself, see the Drop list §5.29), `BR2_PACKAGE_LIBFUSE` (ditto —
real dependents may want it even though archivemount itself is dropped).

### 5.12 USB / input

`BR2_PACKAGE_LIBUSB`, `BR2_PACKAGE_LIBUSB_COMPAT` (legacy libusb-0.1 API shim —
still NEEDed by name, `libusb-0.1.so.4`, in stock's binary set),
`BR2_PACKAGE_LIBEVDEV`, `BR2_PACKAGE_LIBINPUT`, `BR2_PACKAGE_MTDEV`.

`BR2_PACKAGE_USBMOUNT=y` — USB mass-storage automount, stock parity. Stock
ships the Debian `usbmount` package (udev `RUN+=` rule ->
`/usr/share/usbmount/usbmount`) that mounts sd*/ub* block devices under
`/media/usb0..7` on hotplug and unmounts on removal. Buildroot's usbmount is the
same tool (0.0.22, patched to read udev's `ID_FS_*` env instead of shelling out
to blkid — functionally identical to stock's 0.0.24 script). It needs udev
(`BR2_PACKAGE_HAS_UDEV` — eudev, §5.15) and `select`s
`BR2_PACKAGE_LOCKFILE_PROGS` (-> the liblockfile already enabled, §5.15) for
the lockfile-create serialisation in its add path. run-parts/logger/expr are
BusyBox applets, all present. The stock-tuned `usbmount.conf` (adds
exfat/ntfs/fuseblk + NTFS/fuseblk mount opts, which upstream 0.0.22's default
omits) ships in the rootfs-overlay and overrides the package's default — see
`docs/usb-automount-parity.md`.

### 5.13 Bluetooth

`BR2_PACKAGE_BLUEZ5_UTILS=y`. `BR2_PACKAGE_BLUEZ5_UTILS_CLIENT=y` — NOT in the
manifest — discovered during P2.1 verification: DEPRECATED (below) `depends on
BLUEZ5_UTILS_CLIENT || BLUEZ5_UTILS_TOOLS`, and stock ships
`usr/bin/bluetoothctl` (needs CLIENT) + `usr/bin/gatttool` (also needs CLIENT),
per `docs/stock-inventory/binaries-needed-full.txt`.
`BR2_PACKAGE_BLUEZ5_UTILS_TOOLS=y` — NOT in the manifest — the other half of
DEPRECATED's prerequisite; stock also ships hciattach/l2ping which live under
TOOLS. `BR2_PACKAGE_BLUEZ5_UTILS_DEPRECATED=y` — hciconfig/hcitool/sdptool/
rfcomm/l2ping/hcidump — all present in stock, gated by this option upstream
now. Depends on CLIENT or TOOLS (`package/bluez5_utils/Config.in`) — silently
unsatisfiable without them; confirmed missing from `output/.config` before
this fix. `BR2_PACKAGE_BLUEZ5_UTILS_PLUGINS_SIXAXIS=y` — PS3 controller BT
pairing (selects `_PLUGINS_HID` transitively — don't set that too). Requires
the eudev choice (§5.15). See `docs/bluetooth-parity.md`.

### 5.14 PAM / capabilities

`BR2_PACKAGE_LINUX_PAM`, `BR2_PACKAGE_LIBCAP`, `BR2_PACKAGE_LIBCAP_NG`.

### 5.15 misc small libraries / tools

- `BR2_PACKAGE_DTC=y` — libfdt. `BR2_PACKAGE_DTC_PROGRAMS=y` — T5 (2026-07-27):
  the DTC line alone ships ONLY the library — `package/dtc/Config.in` says so
  explicitly ("Note that only the library is installed. If you want the
  programs, say 'y' here, and to 'dtc programs', below"). The `dtc` CLI itself
  (plus convert-dtsv0/fdtdump/fdtget/fdtput/dtdiff) needs this separate
  sub-option, which was never set — so this image had never actually shipped
  the `dtc` binary despite DTC=y being on since P2.1. dtdiff additionally
  needs bash, already on (`BR2_PACKAGE_BASH=y`, wifi.sh).
- `BR2_PACKAGE_SUDO=y`.
- `BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y` — NOT in the manifest — discovered during
  P2.1 verification: `BR2_PACKAGE_I2C_TOOLS` "depends on
  BR2_PACKAGE_BUSYBOX_SHOW_OTHERS" (`package/i2c-tools/Config.in`); without
  this, I2C_TOOLS=y is silently unsatisfiable and Kconfig drops it with no
  error (confirmed: it doesn't land in `output/.config` without this line).
  Also gates LSOF (§5.32) and GNU wget (§5.10).
- `BR2_PACKAGE_I2C_TOOLS=y` — for the i2c-gpio RTC add-on, P3.11
  (`docs/rtc-parity.md`). No sub-options gate any of its tools.
- `BR2_PACKAGE_JIMTCL=y` — NOT just an obscure shell — usb_modeswitch's
  dispatcher (3G/LTE modem support) needs it.
- `BR2_PACKAGE_LIBLOCKFILE=y`, `BR2_PACKAGE_LIBXML2=y`, `BR2_PACKAGE_FILE=y` (libmagic).
- `BR2_PACKAGE_MEMTOOL=y` — memtool (T3, addon.tar §3c): stock's
  `usr/bin/memtool` looked like an unsourceable ARM blob in the first
  reconciliation pass ("ARM ELF" with no provenance) — it is not. `strings` on
  the stock binary yields pengutronix memtool's exact usage text ("memtool is
  divided into subcommands", the "Usage: md [-bwlqsx] REGION" / "Usage: mw
  [-bwlqd] OFFSET DATA..." lines), and addon.tar's `usr/bin/md` + `usr/bin/mw`
  are symlinks -> memtool (argv[0] dispatch), matching pengutronix's md/mw
  subcommand model. Buildroot packages that exact tool (`package/memtool`,
  2018.03.0 — upstream's last release), so this is a plain package enable, not
  a (D)-infeasible item. Only `usr/bin/fpga` remains without public source
  (`docs/stock-reconciliation.md` §3c). The package installs only
  `/usr/bin/memtool` (`bin_PROGRAMS` in its Makefile.am — no symlinks); stock's
  md/mw argv[0] sugar is reproduced by two overlay symlinks instead
  (`memtool.c:475` dispatches on `basename(argv[0])`, verified in the pinned
  2018.03.0 tarball, so `md`/`mw` and `memtool md`/`memtool mw` are the same
  operations).
- `BR2_PACKAGE_PCRE2=y` — `libpcre2-8.so.0`, the PCRE1 replacement. PCRE1
  (`libpcre.so.1`) was REMOVED upstream in Buildroot 2026.05 (EOL, unmaintained;
  it is now a `Config.in.legacy` stub that hard-stops the build). Nothing in
  this image needs it: the stock MiSTer binary does not link it (verified — no
  `-lpcre`, no DT_NEEDED), Python uses its built-in sre engine (not PCRE), and
  2026.05's slang dropped its pcre module (`--with-pcre=no`). The only stock
  consumers were wget/zsh — and GNU wget, since re-added, wants PCRE2 (§5.10).
  See `docs/package-manifest.md` for the recorded parity deviation. PCRE2 is
  already `select`'d transitively by libglib2 and libselinux; listed
  explicitly so it can never be silently dropped.
- `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y` — eudev needs its "/dev
  management" choice (`system/Config.in`) switched away from the
  `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS` default — NOT in the manifest,
  discovered during P2.1 verification: `BR2_PACKAGE_EUDEV=y` alone is silently
  unsatisfiable (depends on `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV`, which
  the manifest's paste list never sets) and Kconfig drops it with no error.
  This one line cascades to fix THREE other silently-dropped symbols:
  `BR2_PACKAGE_LIBINPUT` (depends on `BR2_PACKAGE_HAS_UDEV`, only select'd by
  eudev) and `BLUEZ5_UTILS_PLUGINS_SIXAXIS` (same). Confirmed: none of the four
  landed in `output/.config` until this line was added. It selects
  `BR2_PACKAGE_EUDEV` automatically.
- `BR2_PACKAGE_EUDEV=y` — NOT mdev — PLAN §3 explicit requirement (kept
  explicit for readability even though the choice above already selects it).

### 5.16 lftp

`BR2_PACKAGE_LFTP=y` — provides all 4 bundled `liblftp-*.so` together.

### 5.17 Python (A6 / P3.9) and the btctl runtime

`BR2_PACKAGE_PYTHON3=y` — 3.14.6 — no legacy-version toggle exists in Buildroot
2026.05; see the P3.9 risk entry. Extension modules (P3.9) — match stock's 3.9
lib-dynload set exactly. SSL + ZLIB are HARD BLOCKERS: without them
Downloader_MiSTer crashes on `import ssl` and cannot read its own
`db.json.zip` (proven under qemu-user, `docs/python-compat.md`). openssl/zlib
target libs are already built. BZIP2/XZ (`_lzma`)/PYEXPAT/READLINE/CURSES round
out stock parity. (SQLITE/DECIMAL deliberately omitted — stock's Python 3.9
shipped neither.) `BR2_PACKAGE_PYTHON3_{SSL,ZLIB,BZIP2,XZ,PYEXPAT,READLINE,CURSES}=y`.

btctl runtime (T3, addon.tar §3c). Stock's OSD Bluetooth pairing flow is a
Python script: Main_MiSTer `popen()`s the absolute path `/usr/sbin/btpair`
(`work/Main_MiSTer/menu.cpp:7102`) and later runs "btctl disconnect <mac>"
(`input.cpp:5581`), and btpair is a 12-line wrapper whose whole job is running
`btctl pair`. btctl (vendored into the overlay, see §3c) opens with `import
dbus`, `import dbus.service`, `dbus.mainloop.glib` and `from gi.repository
import GLib` — i.e. classic dbus-python plus PyGObject. Stock ships exactly
those bindings for its python3.9 (verified in
`work/imgroot/usr/lib/python3.9/site-packages/`: `dbus/`, `_dbus_bindings.so`,
`_dbus_glib_bindings.so`, `gi/`, `PyGObject-3.36.1.egg-info`). Without both,
btctl dies on its first import and OSD pairing silently does nothing. Cost
check before enabling: python-gobject's one heavyweight dependency
(gobject-introspection, which drags in host-qemu) is ALREADY paid —
`BR2_PACKAGE_GOBJECT_INTROSPECTION=y` in §5.10 — and dbus-python needs only
dbus + libglib2, both long since on. python-dbus-fast/-next (the asyncio
reimplementations Buildroot also carries) were considered and rejected: btctl
uses the dbus-python API surface (`dbus.service.Object` agents, mainloop
glue), and rewriting a proven stock script to a different binding is exactly
the kind of unverifiable-off-target churn this project avoids.
`BR2_PACKAGE_DBUS_PYTHON=y` (`dbus.mainloop.glib` — btctl's bus + agent),
`BR2_PACKAGE_PYTHON_GOBJECT=y` (`gi.repository.GLib` — btctl's main loop).

### 5.18 Samba

`BR2_PACKAGE_SAMBA4=y` — a single package covers ~125 of the 251 SONAMEs (see
manifest §1). Deliberately NOT set (standalone file server only, not a domain
controller/member): `BR2_PACKAGE_SAMBA4_AD_DC`, `BR2_PACKAGE_SAMBA4_ADS`,
`BR2_PACKAGE_SAMBA4_SMBTORTURE`. See `docs/samba-parity.md`.

### 5.19 daemons / user-facing binaries (manifest §2)

`BR2_PACKAGE_OPENSSH=y`. **`# BR2_PACKAGE_OPENSSH_SANDBOX is not set`** —
deliberately NOT set (Buildroot defaults it to y, i.e. `--with-sandbox`). Our
kernel carries `# CONFIG_SECCOMP is not set` (`linux.config:48`), matching
stock (`docs/stock-inventory/stock-linux.config:592`), so
`prctl(PR_SET_SECCOMP)` returns EINVAL. Through openssh 10.3 that was only a
`debug()` and sshd ran the pre-auth child unsandboxed — which is what this
image has silently done for its entire life; the seccomp sandbox was never
once active here. openssh 10.4 (upstream 7ab700f, "Make failure to set SECCOMP
or NO_NEW_PRIVS fatal") turned it into `fatal()`. The LISTENER still binds and
listens normally, but the pre-auth privsep child of sshd-session then dies
status 255 on every single connection, before any auth — so the box looks
like it is serving SSH while refusing every client, password and key alike.
That regression reached us via Buildroot 2026.05.1 -> 2026.05.2, which bumped
openssh 10.3p1 -> 10.5p1 and so crossed the 10.4 boundary. `--without-sandbox`
selects `SANDBOX_NULL` — verified on the rebuild: `config.h` gets
`#define SANDBOX_NULL 1` and none of sshd, sshd-session or sshd-auth carries a
seccomp string any more. That restores the posture the image actually had all
along (the sandbox never engaged). Setting `CONFIG_SECCOMP=y` instead is the
beyond-parity fix (`post-build.sh:22` already lists it as such), but it would
arm that armhf/glibc syscall allowlist for the first time ever and needs a
real build-and-SSH test, not a hotfix. NB: configure-time flag — changing it
requires `make openssh-dirclean` before the rebuild, or the stale
`--with-sandbox` stamp ships the same broken sshd. See `docs/ssh-ftp-parity.md`.

`BR2_PACKAGE_PROFTPD=y`.

`BR2_PACKAGE_WPA_SUPPLICANT=y`; `_NL80211=y` (default y already, listed for
clarity); `_WEXT=y` (stock's interfaces file passes "-D nl80211,wext" — both
drivers needed); `_DEBUG_SYSLOG=y` — compiles in the "-s" (log-to-syslog)
flag. Stock's `/etc/network/interfaces` invokes "wpa_supplicant -s ...";
without `CONFIG_DEBUG_SYSLOG` the -s is unknown -> wpa_supplicant rejects the
args and dumps its usage text to the console at every boot (once per wlanN
stanza). Enabling it makes -s valid so the pre-up starts cleanly and logs to
syslog, not the console — exact stock parity (P3.4 hardware fix). `_WPA3=y` —
SAE/OWE/DPP — WPA3-Personal support. BEYOND stock (stock's wpa_supplicant 2.9
had no WPA3, so WPA3 networks were unjoinable). Our 2.11 + the morrownr 88x2bu
driver do SAE over nl80211. Requested for hardware testing on a real WPA3
network. `_CLI=y` + `_PASSPHRASE=y` — T5: wpa_cli (interactive/scriptable
control of a running wpa_supplicant — status, scan, reassociate, list/select
saved networks) + wpa_passphrase (turns an ASCII passphrase into the PSK hex
blob `wpa_supplicant.conf` wants, so a script never has to embed the plaintext
passphrase). Highest value-per-byte item in the T5 pass and squarely WiFi
work: both are sub-options of the wpa_supplicant package already built, not a
new package. CLI selects `WPA_SUPPLICANT_CTRL_IFACE` (the Unix-socket control
API) automatically — don't also list that symbol by hand, it would just be
redundant with the select (`package/wpa_supplicant/Config.in:137-141`).
Neither has any other dependency (verified against the pinned Config.in).

WiFi userland parity (P3.4) — the community wifi.sh (Scripts_MiSTer) and the
stock WiFi stack need these; all four are in stock's rootfs. See
`docs/wifi-parity.md`. (`CONFIG_CFG80211_WEXT=y` is already resolved in our
kernel, so iwlist/iwgetid's legacy WEXT ioctls work against the cfg80211-only
Realtek drivers.) `BR2_PACKAGE_BASH=y` (wifi.sh shebang), `BR2_PACKAGE_DIALOG=y`
(wifi.sh interactive menus), `BR2_PACKAGE_WIRELESS_TOOLS=y` +
`_IWCONFIG=y` (iwmulticall: iwconfig + iwlist/iwgetid symlinks),
`BR2_PACKAGE_IW=y` (stock ships `usr/sbin/iw`, nl80211 CLI — parity; the
overlay's `70-persistent-net.rules` pre-up depends on it),
`BR2_PACKAGE_IPROUTE2=y` (stock's `/usr/sbin/ip` — wifi.sh's link up/down
fallback).

`BR2_SYSTEM_BIN_SH_BASH=y` — **`/bin/sh` is bash, and so is root's login
shell** (issue #144). Stock has `/bin/sh -> bash` and
`root:x:0:0:root:/root:/bin/bash`; until this symbol was added we shipped
Buildroot's defaults, BusyBox ash as `/bin/sh` and root on `/bin/sh`, with
nothing recording the difference. That matters in two places: a user script
in `/media/fat/Scripts` with a `#!/bin/sh` shebang and bash syntax runs on
stock and may not on ash (`docs/stock-reconciliation.md`'s `usr/bin/timidity`
row is the one case that was checked by hand — its `function` keyword happens
to be in ash's bash-compat set), and an interactive root session over ssh or
the console gets ash's line editing and no bash history. One symbol does both
halves: Buildroot's `SKELETON_INIT_COMMON_SET_BIN_SH` finalize hook runs
`ln -sf bash /bin/sh` **and** `sed '/^root:/s,[^/]*$,bash,' /etc/passwd`
(`package/skeleton-init-common/skeleton-init-common.mk`), so no post-build
edit is needed and the result is byte-for-byte stock's layout. The symbol
depends on `BR2_PACKAGE_BUSYBOX_SHOW_OTHERS` (§5.15, already on) — without
it kconfig silently drops the choice back to BusyBox, which is why the
fragment carries a WARNING next to it. BusyBox's own `ash` applet stays
built and listed in `/etc/shells`, exactly as on stock; only what `sh`
resolves to changes. Scripts invoked as `sh` get bash in POSIX mode
(`argv[0]` is `sh`), same as stock. `scripts/ci-tests.sh` asserts both
halves against `rootfs.tar` (P3.4 section) and runs the dhcpcd timezone hook
under the target's bash in POSIX mode as well as under ash.

### 5.20 On-device text editors, ifupdown, BusyBox fragment, dhcpcd, ntp, cifs

Editors (stock parity): stock ships `usr/bin/joe`, `usr/bin/nano` AND
`usr/bin/vim` (P0.3 inventory, `binaries-needed-full.txt:149/218/348`). We
shipped none of them — only BusyBox's built-in `vi`.
`docs/package-manifest.md:665` had flagged this as a deliberate P2.7
size-budget call ("keep the light ones... if the community expects them"),
left unresolved. Resolved: people SSH into a MiSTer to edit
`wpa_supplicant.conf` / `MiSTer.ini`, and BusyBox vi is a hostile way to do
that for most users. joe: ~0.65 MiB (`docs/stock-inventory/disk-usage.md`),
needs MMU only. nano: small; needs wchar + ncurses (both already on). vim is
NOT enabled — it is the heavy one, and its libgpm dependency is already
satisfied (`BR2_PACKAGE_GPM=y`) if we ever want full parity.
`BR2_PACKAGE_JOE=y`, `BR2_PACKAGE_NANO=y`.

`BR2_PACKAGE_IFUPDOWN=y` — ifupdown package (stock parity): stock ships the
real ifupdown, not busybox's ifup applet. busybox ifup mangles the interfaces
file's pre-up "$IFACE", so wpa_supplicant is called with bad args and dumps
its usage text twice at every boot. The busybox.fragment disables busybox's
IFUP/IFDOWN so ifupdown's `/sbin/ifup` wins (== `usr/sbin/ifup` under
usr-merge, stock's exact path). P3.4.

`BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES` — `board/mister/de10nano/busybox.fragment`
on top of `package/busybox/busybox.config`; the applet set this image ships
(and every "collides with a BusyBox applet — disabled in busybox.fragment"
note in this document) is decided there (§5.23).

`BR2_PACKAGE_DHCPCD=y`, `BR2_PACKAGE_NTP=y` (classic ntpd, matches stock — NOT
chrony/openntpd), `BR2_PACKAGE_CIFS_UTILS=y`.

### 5.21 Midnight Commander (T3, stock parity, addon.tar §3c UX closure)

Stock ships mc 4.8.25 (`strings` on `work/imgroot/usr/bin/mc`) as THE on-device
file manager, and it is load-bearing for MiSTer's media-player UX, not just a
convenience: addon.tar overlays `etc/mc/mc.ext` with `Open=` handlers for
aplay/mpg123/vgmplay/timidity/m3u_play/vhd_mount, ships a MiSTer skin, and
`usr/bin/timidity` plays `$MC_EXT_SELECTED` — an mc-set variable, so that
script is mc-integration by construction. Without mc, four of the §3c helpers
lose the UI they were written for.

Version gap that matters: Buildroot's is 4.8.33, and upstream REPLACED the
`mc.ext` format with `mc.ext.ini` in 4.8.29 — read from the pinned tarball's
own changelog, not from memory: mc-4.8.33 `NEWS:191` is the "Version 4.8.29"
header, `NEWS:203` "Port mc.ext to INI format and rename to mc.ext.ini (#4141,
#3742, #3191)", `NEWS:205` "There is no fallback to previous mc.ext format".
(NOT 4.8.28, whose section starts at `NEWS:249` and still carries plain mc.ext
bugfixes at `NEWS:281-282`.) Stock's `etc/mc/mc.ext` therefore CANNOT be
carried verbatim — 4.8.33 would ignore it outright. The MiSTer handlers are
ported into the overlay's `etc/mc/mc.ext.ini` instead; see that file's header
and `docs/stock-reconciliation.md` §3c for the per-handler mapping.

Screen backend: ncurses (`BR2_PACKAGE_NCURSES=y`; slang deliberately not
enabled as the backend). mc's `select BR2_PACKAGE_NCURSES_WCHAR if
BR2_PACKAGE_NCURSES` is a no-op here — `NCURSES_WCHAR=y` is already set
(§5.11), so the narrow->wide SONAME/clean-rebuild trap documented there is not
re-triggered by this line.

RUNTIME DEPENDENCY, worth knowing before someone debugs it the hard way: mc
needs ALL THREE of its XDG dirs to be creatable, not just the one we vendor.
`mc_config_init_config_paths()` (4.8.33 `lib/mcconfig/paths.c:183-188`) builds
`~/.config/mc`, `~/.cache/mc` AND `~/.local/share/mc` via `mc_config_mkdir()`
(`:104-112`, `g_mkdir_with_parents 0700` -> `mc_propagate_error` on failure),
and `src/main.c:315-320` treats that error as fatal (`mc_event_deinit(NULL);
goto startup_exit_falure;`). The overlay ships only
`root/.config/mc/{ini,panels.ini}` — the other two must be created at runtime,
on a root filesystem the kernel mounts READ-ONLY (cmdline `... loop=linux/linux.img
ro rootwait`, `docs/boot-chain.md:323`; the inittab remount is deliberately
commented out at `etc/inittab:53`). What makes mc work at all is
`/etc/profile:31`'s `mount -o remount,rw /`, which runs on the first login
shell. So mc invoked before ANY login shell has run on a fresh boot (e.g.
straight from a Main_MiSTer Scripts entry) dies with "Cannot create
/root/.cache/mc directory". This is PARITY, not a regression: stock's
addon.tar ships those same two mc files and no `~/.cache/mc` or
`~/.local/share/mc` either (`tar tvf` on the pinned archive: under `./root/`
only `.config/mc/{ini,panels.ini}` and `.ssh/environment`), and stock's
`/etc/profile` carries the identical remount at `:23` — so stock behaves
exactly the same way. Deliberately NOT "fixed" by shipping empty
`root/.cache/mc` + `root/.local/share/mc` in the overlay: that would diverge
from stock, and the overlay's rsync chmod (`--chmod=u=rwX,go=rX`,
`system/system.mk:64-68`) would create them 0755 where mc wants 0700. Recorded
here instead; revisit only if a Scripts-launched mc is ever actually wanted.
`BR2_PACKAGE_MC=y` — stock `usr/bin/mc`, file manager + the §3c media-helper
launcher UI.

### 5.22 NFS client userland (ADR 0022) — reverses P3.10's "kernel-only NFS" call

The kernel has carried the whole NFS client all along (NFS_FS/V2/V3/V4/V4_1/
V4_2, SUNRPC, LOCKD_V4, NFS_USE_KERNEL_DNS — `docs/netfs-parity.md`), but with
no mount.nfs helper `mount -t nfs` could not work AT ALL: util-linux's mount
execs `/sbin/mount.<type>` for a network fs, and there is no BusyBox fallback
— its mount applet is disabled outright in our build (`# CONFIG_MOUNT is not
set`, and `# CONFIG_FEATURE_MOUNT_NFS is not set` with it; the latter is
v2/v3-only anyway). Supplying `/sbin/mount.nfs` (+ the `mount.nfs4` symlink) is
the entire point. `BR2_PACKAGE_NFS_UTILS=y`. `BR2_PACKAGE_NFS_UTILS_NFSV4=y` —
NFSv4/4.1/4.2 -> nfsidmap + rpc.idmapd. Buildroot hard-couples
`--enable-nfsv4` to `--enable-blkmapd`, which is why lvm2 gets pulled in
(trimmed below).

**`# BR2_PACKAGE_NFS_UTILS_RPC_NFSD is not set`** — CLIENT ONLY; this line is
load-bearing, not decoration. Upstream defaults `BR2_PACKAGE_NFS_UTILS_RPC_NFSD`
to y, and leaving it alone would install rpc.nfsd/rpc.mountd/exportfs + an
S60nfs init script, select rpcbind, and — the real trap — fire
`NFS_UTILS_LINUX_CONFIG_FIXUPS`, whose `KCONFIG_ENABLE_OPT` would flip on the
in-kernel NFS *server* underneath our deliberate `# CONFIG_NFSD is not set`.
We are a client; the server stays off on both sides.

**`# BR2_PACKAGE_LVM2_STANDARD_INSTALL is not set`** — lvm2 is not a feature we
want; it arrives solely as the blkmapd dependency above (blkmapd links
libdevicemapper for the pNFS block layout, which no home NAS uses). Upstream
defaults to installing the full LVM suite; keep only dmsetup +
libdevicemapper so we do not ship an unused volume manager on a games console.

### 5.23 rsync, BusyBox

`BR2_PACKAGE_RSYNC=y`. `BR2_PACKAGE_BUSYBOX=y` — 1.38.0 in this Buildroot
(`busybox.mk:7`; `output/build/busybox-1.38.0`), always on. Parity with STOCK's
274-applet set — stock runs 1.33.1, count from its own `busybox --list` under
qemu-arm, see `docs/stock-inventory/busybox-applets.md` — is a P2.3 config
concern, not a package-selection one; the applet set this image actually ships
is decided by `board/mister/de10nano/busybox.fragment` on top of
`package/busybox/busybox.config`.

### 5.24 P3.1/v9: Realtek USB WiFi — MAINLINE-FIRST out-of-tree driver policy

EXACTLY ONE out-of-tree Realtek WiFi fork is selected: rtl8852cu-morrownr, for
the RTL8852CU/RTL8832CU (Wi-Fi 6E) — see below. It is the only Realtek USB
chip 6.18.40 cannot drive at all, so it is the only chip that satisfies ADR
0016's exception rule. Until v10.2 this section said "NO out-of-tree Realtek
WiFi fork is selected any more"; that was true when written and is no longer.

Every Realtek USB chip MiSTer's 5.15 stock drove with a vendor fork is still
handled by an IN-KERNEL driver (`board/mister/de10nano/linux.config`) —
enabling both would bind-fight on the same USB IDs, so each of THOSE forks'
packages remains DISABLED (`# ... is not set`):

| fork package (not set) | in-kernel driver |
|---|---|
| `BR2_PACKAGE_RTL8188EU_AIRCRACK_NG` (8188eu), `BR2_PACKAGE_RTL8188FU` (8188fu) | rtl8xxxu (`CONFIG_RTL8XXXU=m`, already on; 8710bu too) |
| `BR2_PACKAGE_RTL8821CU_MORROWNR` (8811cu, 8821cu) | rtw88_8821cu (`CONFIG_RTW88_8821CU=m`) |
| `BR2_PACKAGE_RTL88X2BU` (8822bu) | rtw88_8822bu (`CONFIG_RTW88_8822BU=m`, HW-verified WPA3) |
| rtl8814au-morrownr (8814au; package kept, unselected, no not-set line needed) | rtw88_8814au (`CONFIG_RTW88_8814AU=m`, merged in 6.16) |
| `BR2_PACKAGE_RTL8812AU` (8812au) | rtw88_8812au (`CONFIG_RTW88_8812AU=m`, merged in 6.13) |
| `BR2_PACKAGE_RTL8821AU_MORROWNR` (8811au, 8821au) | rtw88_8821au (`CONFIG_RTW88_8821AU=m`, merged in 6.13) |

The last two rows are the newest: RTL8812AU and RTL8811AU/RTL8821AU were ADR
0016's only standing exceptions ("no mainline USB driver"), and that is simply
no longer true — the shared rtw88_88xxa core landed in 6.13, after that ADR
was written. Mainline goes through mac80211 (WPA3/SAE/PMF work properly, the
concrete defect that drove the 8822bu switch) and stays maintained, whereas
the morrownr forks need hand-written compat patches every kernel bump.
Coverage was diffed, not assumed, and NOTHING is lost. The two forks' USB-ID
tables list 57 IDs, mainline rtw88_8812au + rtw88_8821au list 50, and the 50
are a strict subset of the 57. Every one of the 7 remaining IDs is claimed by
a DIFFERENT in-kernel driver this image already builds — the forks' tables
simply over-claimed IDs belonging to other chips, and mainline attributes them
correctly: 5 to rtw88_8814au (056e:400b, 056e:400d, 0b05:1817, 2001:331a,
7392:a834 — e.g. 0b05:1817 is the ASUS USB-AC68, a 4x4 RTL8814AU), 1 to
rtl8xxxu (07b8:8179, an RTL8188EUS), and 1 to rtw88_8822bu/8822cu (13b1:0043,
the Linksys WUSB6300 v2 — RTL8822BU; only the v1, 13b1:003f, is a true
8812AU, and mainline's 8812au table does carry it). Verified by grepping the
pinned kernel tree for each ID. See `docs/wifi-parity.md` §6 for the worked
diff. The disabled packages stay sourced (Config.in) as a selectable fallback.

rtl8188eu-aircrack-ng / rtl8821au-morrownr / rtl8821cu-morrownr /
rtl8814au-morrownr / rtl8852cu-morrownr carry a fork suffix, NOT plain
rtl8188eu/rtl8821au/rtl8821cu — so as not to collide with Buildroot's own
same-named upstream packages (different forks; re-confirmed present on the
pinned tree 2026-07-25) on the Kconfig symbol and Make namespace.
(rtl8814au-morrownr and rtl8852cu-morrownr have no upstream twin to collide
with — re-checked 2026-07-27 — and take the suffix only for a uniform morrownr
naming scheme.) Buildroot's own rtl8188eu/rtl8821au/rtl8821cu/rtl8812au-aircrack-ng
packages are left OFF — our pins stay in control, not Buildroot's release
cadence (A9 reproducibility).

- RTL8812AU: now the in-kernel mac80211 rtw88_8812au driver
  (`CONFIG_RTW88_8812AU` in linux.config, merged upstream in 6.13 via the
  shared rtw88_88xxa core), NOT the OOT rtl8812au package. To revert: re-add
  `BR2_PACKAGE_RTL8812AU=y` and drop `CONFIG_RTW88_8812AU` from linux.config.
- RTL8814AU: now the in-kernel mac80211 rtw88_8814au driver
  (`CONFIG_RTW88_8814AU`, merged upstream in 6.16), NOT the OOT
  rtl8814au-morrownr package. The `package/` definition is kept but unselected
  (the OOT fork gets no API updates past kernel 6.14; running both would
  conflict on the same USB IDs). To revert: re-add
  `BR2_PACKAGE_RTL8814AU_MORROWNR=y` and drop `CONFIG_RTW88_8814AU`.
- RTL8811AU/RTL8821AU: now the in-kernel mac80211 rtw88_8821au driver
  (`CONFIG_RTW88_8821AU`, same 6.13 rtw88_88xxa core as 8812au), NOT the OOT
  rtl8821au-morrownr package. To revert: re-add
  `BR2_PACKAGE_RTL8821AU_MORROWNR=y` and drop `CONFIG_RTW88_8821AU`.
- RTL8822BU (0bda:b812): SWITCHED to the MAINLINE rtw88 driver (kernel
  `CONFIG_RTW88_8822BU=m`) instead of the out-of-tree 88x2bu. Mainline goes
  through mac80211, so WPA3/SAE/PMF work correctly (the out-of-tree 88x2bu
  advertised SAE+CMAC but failed WPA3-only association, status_code=1 —
  verified on hardware). rtw88 USB support for this chip landed in mainline
  ~6.2, AFTER stock's 5.15 froze — which is why the out-of-tree driver was
  needed then and isn't now. The out-of-tree package is left OFF to avoid a
  bind conflict on the same USB ID; re-enable it (and drop RTW88_8822BU) to
  fall back. See `docs/wifi-parity.md`.

**RTL8852CU / RTL8832CU** (Wi-Fi 6E, 2x2, 2.4/5/6 GHz USB) —
`BR2_PACKAGE_RTL8852CU_MORROWNR=y`, the ONE out-of-tree WiFi fork this image
ships (v10.2). This reverses the "zero out-of-tree WiFi drivers" state v10
reached, deliberately and under ADR 0016's own unchanged rule: keep a fork
only where mainline has no USB driver for the chip. Mainline 6.18.40 has
none. rtw89 carries the 8852C chip HAL (`rtw8852c.c`, `rtw8852c_rfk.c`,
`rtw8852c_table.c`) but its ONLY bus file for that HAL is the PCIe one —
`rtw8852ce.c` is present, `rtw8852cu.c` does not exist — and the only Kconfig
symbol offered is `RTW89_8852CE`, "depends on PCI"
(`drivers/net/wireless/realtek/rtw89/Kconfig:113-122`). This board has no PCIe
(`CONFIG_PCI` unset), so even that is unreachable. Directory listing checked on
the pinned tree, not assumed; note the same directory DOES ship `rtw8851bu.c`
and `rtw8852bu.c`, so this is an 8852C-specific gap, not "rtw89 has no USB".
Net effect before this line: an RTL8852CU dongle got NO driver whatsoever. It
was the last open USB WiFi gap from the v10.1 audit (`docs/wifi-parity.md` §7).

Bind conflict: NONE. The fork's tree is multi-chip but upstream enables only
`CONFIG_RTL8852C`, and its USB ID table is `#ifdef`-partitioned per chip, so
the built module claims just nine IDs (0bda:c85a/c832/c85d, 0db0:991d,
2c4e:0127, 3574:6251, 35b2:0502, 35bc:0101, 35bc:0102). All nine were grepped
against `drivers/net/wireless/` and `drivers/bluetooth/` in 6.18.40: zero
matches. Near misses worth knowing: rtw89_8852bu holds 35bc:0100/0108 and
btusb holds 2c4e:0128. The fork's compiled-OUT 8852B/8851B blocks WOULD
collide (with rtw89_8852bu, rtw89_8851bu and mt7921u), which is why the chip
switches must stay as upstream ships them — see
`package/rtl8852cu-morrownr/*.mk`.

No firmware toggle needed: this vendor tree links its firmware in as a C array
(`LOAD_FW_HEADER_FROM_DRIVER`) instead of calling `request_firmware()`, unlike
mainline rtw89 which needs `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW89` (already on
for 8851BU/8852BU). Expect a LARGE .ko in return — ~15 MB of the source tree
is firmware arrays; the built size has not been measured.

Caveats, stated plainly: upstream's README declares 5.15-6.14 as
Realtek-tested and 6.15-7.1 as community-supported, so 6.18.40 is in the
weaker band; and the package needs a `KSRC=` override to build under Buildroot
at all (the driver's `EXTRA_CFLAGS`->`ccflags-y` translation is gated on a
kernel-version probe that looks at the BUILD HOST's `/lib/modules`). Both are
documented with file:line evidence in
`package/rtl8852cu-morrownr/rtl8852cu-morrownr.mk`. To revert: drop the line.
Nothing in linux.config needs changing with it — there is no in-kernel driver
to turn back on.

### 5.25 P3.2: xone (Xbox One/Series accessory driver, PLAN.md §4.1 class D/E)

`BR2_PACKAGE_XONE=y`, `BR2_PACKAGE_XOW_FIRMWARE=y`. Commit-pinned,
hash-verified, sourced from dlundqvist/xone — the actively maintained fork;
medusalix/xone (the original, and what stock's fork vendored) is explicitly in
"maintenance mode" per its own README. See `package/xone/xone.mk` for the full
fork-choice comparison. xow-firmware fetches and extracts the Xbox Wireless
Dongle firmware from Microsoft's own driver package at BUILD TIME (never
committed to git, G6) and installs it under both stock's literal filename
(`xow_dongle.bin`, for parity — `docs/stock-inventory/firmware.md`) and the
name this driver fork actually requests (`xone_dongle_02fe.bin`, a symlink to
the same bytes). ACCEPTED maintainer decision, 2026-07-13 —
`docs/decisions/0003-xone-firmware.md`.

### 5.26 dualsensectl: DualSense operator CLI (userspace, not a driver)

`BR2_PACKAGE_DUALSENSECTL=y`. Reaches the DualSense features hid-playstation
exposes no interface for at all — adaptive trigger effects, speaker/headphone
routing, output volume, rumble/trigger attenuation, microphone mode and
volume, player/mic LED dimming, BT power-off, firmware info. STRICTLY ADDITIVE
to the DualSense kernel patches (0033 player_id LED, 0037 mic-mute -> BTN_Z,
0042 stock lightbar LED names): those back Main_MiSTer's sysfs-LED and
input-event ABIs, which no userspace hidraw client can serve.
`docs/dualsense-tooling.md` has the analysis; `package/dualsensectl/dualsensectl.mk`
has the pin.

Nothing invokes it automatically — no init script, no udev rule. It and
hid-playstation both write DS_OUTPUT reports to the same pad and the fields
they share (the lightbar above all) are last-writer-wins, so this stays an
operator tool run from a shell.

It selects `BR2_PACKAGE_HIDAPI` and `BR2_PACKAGE_DBUS`. Neither appears as its
own line, and neither needs to: dbus is already explicitly set (§5.10), and
savedefconfig omits any symbol a select already forces. Verified by
regenerating: `make savedefconfig` before and after this change differ by
exactly one line, `BR2_PACKAGE_DUALSENSECTL=y`.

THE SELECTS ARE NOT JUST hidapi+libgudev — READ THIS BEFORE TRIMMING.
hidapi's Config.in carries `select BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_COPY if
BR2_TOOLCHAIN_USES_GLIBC` (for its runtime UTF conversion of USB string
descriptors). This image is glibc and that symbol was OFF, so enabling
dualsensectl flips it on, and with `BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_LIST` empty
that copies ALL of glibc's gconv charset modules to the target: 253 .so files,
~6.4 MiB apparent, more after ext4 4 KiB block rounding.

That is left ON DELIBERATELY rather than pinned to a minimal list, because it
closes a gap this repo already documented as load-bearing: glibc built these
modules all along (they are in the sysroot) but nothing ever installed them,
so `/usr/lib/gconv` did not exist on the target at all. Stock ships them
(`docs/package-manifest.md` §1 "glibc iconv/gconv charset modules" — libCNS,
libGB, libJIS, libKSC et al are in stock's own SONAME inventory), and that
same doc lists gconv in its "Not recommended to drop (tempting by size, but
load-bearing)" set, reason: "needed for any non-ASCII filename over SMB". So
this is a stock-parity fix that arrived as a side effect — accepted on its own
merits, not smuggled in. Guarding it: `scripts/ci-tests.sh` asserts the modules
are present, so they cannot silently vanish if dualsensectl is ever turned off
again. Pinning `GCONV_LIBS_LIST` to a guessed subset would risk silently
breaking exactly the SMB filename case the manifest calls out. ~6.4 MiB is ~3%
of the last measured 222 MiB of free image space. (This is also why
`BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_*` is a designed divergence between the image
and the kernel-only stack in `scripts/check-config-fragments.sh`, §11.)

### 5.27 ltunify: Logitech Unifying receiver pairing (userspace, not a driver)

`BR2_PACKAGE_LTUNIFY=y`. Closes the one Logitech gap the kernel cannot: the
PAIRING HANDSHAKE. Every other part is already covered and needs nothing added
— `CONFIG_HID_LOGITECH_DJ` (linux.config) gives each paired device its own
input node with its own logical VID/PID, which is what Main_MiSTer identifies
pads and keyboards by, and it `select`s `CONFIG_HID_LOGITECH_HIDPP`
(`drivers/hid/Kconfig:697`), which is why HIDPP is =y in the resolved .config
while being absent from our minimal defconfig. Stock has exactly the same four
symbols. A device that came pre-paired in its box therefore works with nothing
installed at all.

Pairing is the exception: no sysfs knob, no ioctl, no kernel interface of any
kind. ltunify writes the HID++ 1.0 registers itself over `/dev/hidraw*`.
~40 KiB installed and it links against nothing but libc — this is the cheapest
package in the image, not a size question.

LIMITS ARE REAL AND ARE HANDLED IN THE WRAPPER, NOT HERE. ltunify supports
Unifying (c52b/c532) and Nano (c52f/c534) only; it does NOT support Bolt
(c548) or Lightspeed (c539/c53a/c53f/c543). It also assumes the first hidraw
node it finds is the receiver you meant — wrong when two are plugged in, and
wrong again for a single NANO receiver, which owns two nodes because
`logi_dj_probe`'s "no HID++ collection -> -ENODEV" guard is recvr_type_dj-only.
`/usr/sbin/mister-pair-logitech` (rootfs overlay) groups nodes by physical USB
device, classifies by product ID independently of driver (Bolt is bound by
hid-multitouch here, so a driver-first filter would not even see it), refuses
the unsupported families by name, and pins the choice with ltunify's `-d`
flag. `Scripts/pair_logitech.sh` is its launcher on the data partition, the
same shim shape ADR 0026 established for `check_storage.sh`.

NOT SOLAAR, which is the maintained tool and does cover Bolt: its only
`console_scripts` entry point routes through `solaar.gtk`, which imports
`solaar.ui`, which requires Gtk 3.0 — on an image with zero X11/GTK packages.
`docs/logitech-pairing.md` §2 has the comparison and the recheck conditions.

No new selects worth noting: `select BR2_PACKAGE_LIBEXECINFO if
!BR2_TOOLCHAIN_USES_GLIBC` is inert here (this image is glibc), so this is a
one-line change with no transitive tail — unlike dualsensectl above.

### 5.28 P3.3: /lib/firmware population

PLAN.md §3/§4.1, module loading & firmware infra — the
module-autoload/depmod/kmod/xz-compress half is already done (§3.5, §5.30).
Source of truth: `docs/firmware-parity.md` (the inventory -> sub-option mapping
+ the built-vs-stock diff). Target: `docs/stock-inventory/firmware.md`'s
66-file inventory (`xow_dongle.bin`, the 67th stock file, is P3.2's
xow-firmware, §5.25, not repeated here).

linux-firmware itself (`BR2_PACKAGE_LINUX_FIRMWARE`) is a meta-option with no
files of its own — every actual file comes from a sub-option, each picked
because it is the SMALLEST upstream grouping that contains an inventory file
(Buildroot's own file lists are coarse per sub-option, so some non-inventory
sibling files ride along — a documented superset, not a problem; see the
parity doc). `regulatory.db`/`.p7s` come from a SEPARATE package
(wireless-regdb, not linux-firmware — upstream split them out after the
kernel gained direct .db-loading support in 4.15).

Buildroot stamping trap: changing linux-firmware SUB-options on an incremental
build installs nothing and exits 0 — `make linux-firmware-dirclean` first.

| symbol | files / reason |
|---|---|
| `_MEDIATEK_MT7601U` | `mt7601u.bin` (top-level, via WHENCE-driven symlink — see parity doc for the build-verified proof) |
| `_MEDIATEK_MT7610E` | `mediatek/mt7610e.bin` |
| `_MEDIATEK_MT7650` | `mt7650.bin` — filed under Buildroot's "Bluetooth firmware" menu (MT7650 is a WiFi+BT combo chip) but is the ONLY toggle that installs this WiFi file; stock's own inventory attributes it to rt2800usb, not to Bluetooth |
| `_MEDIATEK_MT76X2E` | `mediatek/mt7662.bin` + `mediatek/mt7662_rom_patch.bin` (top-level via symlink) — also what the in-tree mt76x2u USB driver requests (`mt76x2/usb_mcu.c`), not a separate `mt7662u.bin` (see parity doc: stock's own `mediatek/mt7662u.bin` / `mt7662u_rom_patch.bin` are the OLD out-of-tree name, superseded, not reproduced) |
| `_MEDIATEK_MT7921` | `WIFI_RAM_CODE_MT7961*.bin` — MT7921U (`mt7921u.ko`, WiFi6 USB; the USB part reports as MT7961) |
| `_MEDIATEK_MT7925` | `WIFI_RAM_CODE_MT7925*.bin` — MT7925U (`mt7925u.ko`, WiFi6E USB) |
| `_RALINK_RT2XX` | `rt2870.bin` (rt2800usb, `FIRMWARE_RT2870`) + siblings |
| `_RTL_81XX` | rtlwifi 8188e/8192c/8192d/8192s/8192eu family |
| `_RTL_87XX` | rtlwifi 8712u/8723a/8723b family |
| `_RTL_87XX_BT` | rtl_bt 8723a/8723b/8723bs/8761a/8761bu family |
| `_RTL_88XX_BT` | `rtl_bt/rtl88*.bin` glob — covers 8812ae/8821a/8821c/8822b/8822cu in one option |
| `_RTL_RTW88` | `rtw88/rtw8822b_fw.bin` etc. — firmware for the MAINLINE rtw88 driver we now use for RTL8822BU (replacing out-of-tree 88x2bu); also covers 8821cu/8822cu rtw88 |
| `_RTL_RTW89` | `rtw89/*.bin` — mainline rtw89 (RTL8851BU/RTL8852BU WiFi6/6E USB) |
| `_ATHEROS_9271` | `ar9271.fw` + `htc_9271*` — ath9k_htc (AR9271 802.11n USB) |
| `_ATHEROS_7010` | `ar7010*.fw` + `htc_7010*` — ath9k_htc (AR7010-based 802.11n USB) |
| `_ATHEROS_9170` | `carl9170-1.fw` — carl9170 (AR9170 802.11n USB) |
| `_MEDIATEK_MT7921_BT` | v10.2 Bluetooth firmware for combo/BT dongles whose driver we already build (`docs/bluetooth-parity.md`); same class of gap as ath3k below — the driver binds, then dies at `request_firmware()`. `mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin` — the BT half of the MT7921AU combo dongle whose WiFi half we already ship. Requested by `btmtk.c`; without it WiFi works and BT does not |
| `_MEDIATEK_MT7922_BT` | `mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin` — btusb carries MT7922 USB IDs, so this is a reachable USB path, not just the M.2 part |
| `_MEDIATEK_MT7925_BT` | `mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin` — BT half of the MT7925U combo |
| `_QUALCOMM_6174A_BT` | `qca/rampatch_usb_00000302.bin` + `qca/nvm_usb_00000302.bin` — QCA ROME 6174A over USB. btusb requests exactly the "_usb_" names (`btusb.c`: "qca/rampatch_usb_%08x.bin"), and its QCA path is self-contained — it needs no `CONFIG_BT_QCA`, so this firmware is the only missing piece. 132 KiB |
| `_ATHEROS_6004` | `ath6k/AR6004/hw1.2` + `hw1.3` (132 KiB) — ath6kl_usb (`CONFIG_ATH6KL_USB=m`, new in v10.1; AR6003/AR6004 802.11n USB) |
| `_REDPINE_RS9113` | `rsi/rs9113_*.rps` — rsi_usb |
| `_REDPINE_RS9116` | `rsi/rs9116_wlan.rps`, requested by `rsi_91x_hal.c:35` (both toggles needed; `CONFIG_RSI_USB=m`) |
| `_AR3011` | `ath3k-1.fw` — the ath3k driver (`CONFIG_BT_ATH3K=m`, already on) for AR3011 USB Bluetooth. The driver was built but its firmware was NEVER installed, so every AR3011 dongle failed at `request_firmware()`; this closes that gap |
| `_AR3012_USB` | `ar3k/*.dfu` — AR3012 USB Bluetooth patch/config RAM images, loaded by the same ath3k driver (and by btusb for the newer AR3012 IDs) |
| `_BRCM_BCM43XX` | `brcm/brcmfmac4373.bin` + the 43xx SDIO/PCIe siblings — brcmfmac (`CONFIG_BRCMFMAC=m`, new). Implicitly `select`s `BR2_PACKAGE_LINUX_FIRMWARE_CYPRESS_CYW43XX` (`cypress/cyfmac*`, the same silicon post-acquisition) |
| `_BRCM_BCM43XXX` | `brcm/brcmfmac43143.bin`, `43236b.bin`, `43242a.bin`, `43569.bin` — the four BCM43xx USB parts brcmfmac drives; `select`s `_CYPRESS_CYW43XXX` |
| `BR2_PACKAGE_WIRELESS_REGDB` | `regulatory.db` + `regulatory.db.p7s` (separate from linux-firmware, see above) |

NOT enabled: `_QUALCOMM_9377_BT`. Its two files are `qca/rampatch_00230302.bin`
/ `nvm_00230302.bin` — the NON-usb names, which only the UART path (hci_qca,
`CONFIG_BT_HCIUART`, not built) ever requests. No consumer here. NOT enabled:
`_LINUX_FIRMWARE_IBT` (Intel Bluetooth, `intel/ibt-*`). 30 MiB, and Intel BT
controllers ship essentially only on M.2 WiFi+BT combo cards, which this board
cannot host — there is no realistic external Intel BT USB dongle.
`CONFIG_BT_INTEL` is nonetheless built because `CONFIG_BT_HCIBTUSB` `select`s
it unconditionally (it cannot be turned off while btusb is on), so this is a
DELIBERATE driver-without-firmware, unlike the ath3k/mt7663 cases which were
accidental. Flip this on if an Intel BT dongle ever needs to work.

`BR2_PACKAGE_LINUX_FIRMWARE_EXTRA=y` — ten files that NO linux-firmware
sub-option covers, even though upstream linux-firmware carries them and this
project's pinned kernel has an in-tree consumer for each (verified by grep
against the actual built kernel source, not assumed; last checked on 6.18.40 —
re-grep on a kernel bump rather than trusting this line — see
`package/linux-firmware-extra/linux-firmware-extra.mk` and
`docs/firmware-parity.md` for the per-file citation). Same upstream tarball and
hash-pin as linux-firmware itself, just a different subset kept. Four are
stock-parity files; the other five are NOT (stock ships none of them) —
`mediatek/mt7663*` x4 back `CONFIG_MT7663U=m` and `rtlwifi/rtl8192dufw.bin`
backs `CONFIG_RTL8192DU=m`, both enabled beyond stock, and each would
otherwise probe and then fail at `request_firmware()`. See `docs/wifi-parity.md`
§6.2, §7.

`BR2_PACKAGE_BCM20702_FIRMWARE=y` — Broadcom BCM20702 BT dongle firmware
(P3.14): `brcm/BCM20702A1-0b05-17cb.hcd`, the one brcm .hcd stock ships (35000
bytes) but mainline linux-firmware lacks. Hash-pinned build-time fetch, never
a committed blob — same maintainer-approved vendor-firmware posture as xow
(ADR 0003). See `package/bcm20702-firmware/`.

### 5.29 Explicitly NOT carried forward (manifest §5 Drop list)

A note, not config — nothing is set by it:

- archivemount (broken in stock; its deps libarchive/libfuse ARE kept, §5.11, for others)
- adplay / adplug / binio — no Buildroot package, no known MiSTer use
- libhid / libhid-detach-device — no Buildroot package, superseded API
- jack1/jack2 (libjack) — dangling in stock, unused by MiSTer
- rtorrent / libtorrent — unused BitTorrent client, SONAME already drifted

### 5.30 kmod (target half)

Two different things, despite the shared prefix: `BR2_PACKAGE_HOST_KMOD_XZ` is
HOST kmod ("support xz-compressed modules", so the host depmod that runs at
build time can read the `.ko.xz` we ship) and lives in the board fragment
(§3.5) because the kernel-only stack needs it too; `BR2_PACKAGE_KMOD_TOOLS=y`
is TARGET kmod — installs depmod/insmod/lsmod/modinfo/modprobe/rmmod on the
device — and is image-only.

### 5.31 T5 — utility binaries stock ships that this image left out (2026-07-27)

A filename diff of stock's `/bin`,`/sbin`,`/usr/bin`,`/usr/sbin` (`work/imgroot`)
against our `rootfs.tar` found 315 differences. Most are noise — a full Perl
install, python3.9-versioned scripts, GNU long-form duplicates of BusyBox
applets already covered by the util-linux/coreutils blocks elsewhere. The
packages in §5.32–§5.41 are the real gaps: each is confirmed present in this
pinned `work/buildroot/package/` tree, and its Config.in was read (not assumed)
for hidden `select`s, sub-options that default to "n", and toolchain
prerequisites BEFORE being added — three of those reads found a genuine
collision with a BusyBox applet that is already ON in this image (lsof, lsusb,
mkdosfs — plus chvt/deallocvt/openvt/setkeycodes via kbd); see
`board/mister/de10nano/busybox.fragment` for the disables that resolve them,
same non-deterministic-last-install-wins idiom as the existing ifup/ifdown and
util-linux blocks in that file.

The BusyBox-applet half of this same task (stat, timeout, tac, shuf, comm,
split, expand, groups, nc) lives entirely in busybox.fragment — nothing to
enable in the Buildroot config for those nine. wpa_cli/wpa_passphrase
(`WPA_SUPPLICANT_CLI`/`_PASSPHRASE`) are also part of this task but live with
the rest of the wpa_supplicant block (§5.19); `BR2_PACKAGE_NTFS_3G_NTFSPROGS`
and `BR2_PACKAGE_DTC_PROGRAMS` are likewise placed next to their
already-existing parent lines (§5.11, §5.15) rather than duplicated.

Explicitly REJECTED (maintainer's call, not a gap missed) — recorded so the
decision is durable and doesn't get "rediscovered" as an oversight later;
full reasoning in `docs/package-manifest.md`'s Drop list (§5):

- perl — anyone who needs it can build their own image from this repo; no
  MiSTer-specific consumer was found (stock's own init/service scripts are
  all shell, not Perl — package-manifest.md §5).
- vim — BusyBox vi AND nano (§5.20) already cover on-device editing; vim is
  the heaviest of stock's three editors.
- screen — tmux (§5.35) is this image's terminal multiplexer. Not both.
- gdb — (the on-device, TARGET debugger, as opposed to gdbserver) — host gdb
  + gdbserver cross-debugging is judged the better shape for this project,
  and a target debugger is 4-8 MB. NOTE, so this doesn't read as inconsistent
  with §5.42: `BR2_PACKAGE_GDB`/`_GDB_DEBUGGER=y` ARE set, but by the DEBUG
  TOOLING block, for the separate, still-open RT-latency investigation
  (`docs/debug-tooling.md`) — that is a dated, revert-as-one-unit decision,
  not a reversal of this one.
- ltrace — narrow, frequently broken on ARM (a known, longstanding upstream
  limitation, not specific to this toolchain); strace (§5.32) supersedes it
  for what this image needs.
- unrar — non-free (RARLAB) licence. (The "rule G6" this line used to cite is
  about not committing binaries to git, not about licensing — PLAN.md §2;
  corrected in passing 2026-07-27.) Not needed anyway: MiSTer release
  archives are .7z, not .rar, and `BR2_PACKAGE_7ZIP` (§5.37) closes that gap.
  7-Zip additionally brings RAR/RAR5 **extraction** along for free, under
  LGPL-2.1+ with the unRAR restriction (a no-reverse-engineering-of-the-RAR-
  compressor clause — see `package/7zip/7zip.mk`'s license comment), which is
  a different and far weaker thing than vendoring RARLAB's own non-free
  unrar. Compressing to .rar is still not possible, and nothing here needs it.

### 5.32 T5: process / file / syscall inspection

- `BR2_PACKAGE_HTOP=y` — interactive process viewer. Needs `BR2_USE_MMU`
  (fork()) + dynamic libs (dlopen()) — both already true on this glibc/ARM
  target. Selects `BR2_PACKAGE_NCURSES`, already =y, so this is a
  zero-marginal-dependency add (`package/htop/Config.in`).
- `BR2_PACKAGE_STRACE=y` — syscall tracer. Was first enabled TEMPORARILY by
  the DEBUG TOOLING block (§5.42) for the field-hang/RT-latency work; this
  line promotes it to a PERMANENT part of the package set, so strace keeps
  shipping once that block is eventually deleted. The old monolith set it
  twice (once here, once inside the debug block, "same value, last one wins",
  kept so the block stayed contiguous); the fragment sets it ONCE, here — a
  second definition is a redefinition `scripts/check-config-fragments.sh`
  rejects, and it was also a kconfig "override: reassigning" warning on every
  configure. Deleting the debug block therefore no longer removes strace,
  which is exactly what T5 intended.
- `BR2_PACKAGE_LSOF=y` — lsof(8). Needs `BR2_USE_MMU` (fork()) and
  `BR2_PACKAGE_BUSYBOX_SHOW_OTHERS` (already =y, for i2c-tools) — no new
  dependency. COLLIDES with BusyBox's own `lsof` applet (`CONFIG_LSOF=y` in the
  base config) — disabled in busybox.fragment, see that file for the full
  citation.

### 5.33 T5: USB / input / joystick & force-feedback

- `BR2_PACKAGE_USBUTILS=y` — lsusb, usb-devices, lsusb.py (removed by the
  package's own install rule when no target python3 — irrelevant here, we DO
  ship python3, but the C lsusb is what matters). Needs
  `BR2_TOOLCHAIN_HAS_THREADS`, gcc >= 4.9 and `BR2_PACKAGE_HAS_UDEV` (hwdb) —
  all already true (eudev is on, P2.1). Selects LIBUSB (already =y). We did
  NOT already get lsusb from anywhere else — verified no `BR2_PACKAGE_USBUTILS`
  and no busybox-provided lsusb.py equivalent were previously on, so this is a
  clean add, not a fix for a regression. COLLIDES with BusyBox's own `lsusb`
  applet — disabled in busybox.fragment.
- `BR2_PACKAGE_EVTEST=y` — evtest — dumps `/dev/input/eventN` activity. No
  dependencies beyond libc.
- `BR2_PACKAGE_LINUXCONSOLETOOLS=y` + `_JOYSTICK=y` + `_FORCEFEEDBACK=y` — on a
  games console, arguably the single most valuable package in this whole T5
  pass: joystick calibration (jstest, jscal, jscal-store/-restore,
  evdev-joystick) and force-feedback testing (fftest, ffcfstress, ffmvforce,
  ffset). FORCEFEEDBACK needs dynamic libs (already true) and selects
  `BR2_PACKAGE_SDL2`, already =y (§5.6) — zero marginal cost. Side effect, not
  asked for but harmless: the package's top-level `select
  LINUXCONSOLETOOLS_INPUTATTACH if !JOYSTICK && !FORCEFEEDBACK` does NOT fire
  (both are on), but INPUTATTACH's OWN "default y"
  (`package/linuxconsoletools/Config.in`) still applies since nothing sets it
  off — so `inputattach` (legacy serial-joystick/GPS attach helper) lands too,
  unconditionally by upstream default. Small, harmless, not worth suppressing.

### 5.34 T5: filesystem tools (FAT/exFAT)

Both need `BR2_USE_WCHAR`, already true (glibc). dosfstools' three programs
each default to "n" with NO indication of that in the parent's prompt text —
confirmed by reading `dosfstools.mk` directly: each of
FATLABEL/FSCK_FAT/MKFS_FAT is wrapped in its own `ifeq (...,y)` install guard,
so leaving any one unset means that binary (and its compat symlinks) simply
does not install, silently. All three are wanted (fatlabel, fsck.vfat via
FSCK_FAT, mkfs.vfat via MKFS_FAT are the task's explicit list), so all three
are set. MKFS_FAT's compat symlinks include `mkdosfs` — collides with
BusyBox's own applet of that name, disabled in busybox.fragment.

- `BR2_PACKAGE_DOSFSTOOLS=y`; `_FATLABEL=y` (fatlabel + dosfslabel compat
  symlink); `_FSCK_FAT=y` (fsck.fat, + fsck.vfat/fsck.msdos/dosfsck compat
  symlinks); `_MKFS_FAT=y` (mkfs.fat, + mkdosfs/mkfs.msdos/mkfs.vfat compat
  symlinks — mkdosfs collision above).
- `BR2_PACKAGE_EXFATPROGS=y` — mkfs.exfat, fsck.exfat, dump.exfat — no
  sub-options, no collision (BusyBox has no exFAT support of any kind to
  collide with). The stage-1 initramfs builds it too, for the on-demand repair
  path (§8.6).

### 5.35 T5: serial / terminal

- `BR2_PACKAGE_PICOCOM=y` — minimal serial terminal. No dependencies. Does NOT
  collide with BusyBox's `microcom` applet — different binary name.
- `BR2_PACKAGE_LRZSZ=y` — rz/sz (X/Y/Zmodem) — stock ships them
  (`docs/stock-reconciliation.md` §3c). Needs `!BR2_STATIC_LIBS` (dynamic,
  already true — lrzsz redefines `error()`/`error_at_line()` and clashes with
  a static libc's own). Installs rz/sz plus SIX bonus compat symlinks —
  lrz/rb/rx -> rz and lsz/sb/sx -> sz, counted off `lrzsz.mk:21-26` one `ln
  -sf` at a time (rx/sx are easy to miss) — that stock's addon.tar does not
  have: harmless extras, not a divergence that matters.
- `BR2_PACKAGE_TMUX=y` — terminal multiplexer — chosen over screen (see the
  rejected list, §5.31; not both). Needs `BR2_USE_MMU` (fork()), `BR2_USE_WCHAR`
  (mbtowc()) and `BR2_ENABLE_LOCALE` (runtime UTF-8 locale) — all three
  already true (`BR2_GENERATE_LOCALE="en_US.UTF-8"`, §5.44). Selects
  `BR2_PACKAGE_LIBEVENT` (already =y, §5.10) and `BR2_PACKAGE_NCURSES` (already
  =y) — no new dependency weight.

### 5.36 T5: network diagnostics

- `BR2_PACKAGE_ETHTOOL=y` — examine/tune the ethernet NIC. No dependencies.
  `ETHTOOL_PRETTY_PRINT` is a sub-option that DOES default to "y" (unlike
  dosfstools' three above), so it is not listed separately — confirmed in
  `package/ethtool/Config.in`.
- `BR2_PACKAGE_SOCAT=y` — multipurpose socket relay/debug tool. Needs
  `BR2_USE_MMU` (fork()), already true.
- `BR2_PACKAGE_TCPDUMP=y` — selects `BR2_PACKAGE_LIBPCAP` automatically
  (`package/tcpdump/Config.in`) — not listed separately, it is a plain
  `select`, not a default-off sub-option. `TCPDUMP_SMB` ("smb dump support",
  the package's own Config.in calls it "possibly-buggy") deliberately left off
  — not asked for, adds risk for nothing this image needs.
- `BR2_PACKAGE_IPERF3=y` — active bandwidth measurement. Needs
  `BR2_TOOLCHAIN_HAS_ATOMIC` + `_THREADS`, both already true on this glibc/ARM
  toolchain.

### 5.37 T5: archival — `package/7zip` (OURS), not upstream's `p7zip`

7z support is the highest-value item here: MiSTer release archives are .7z,
so without it on-device extraction of a downloaded release is impossible.

THIS IS `package/7zip` (OURS), NOT upstream's `package/p7zip` — and the swap is
not a preference, it closes a real hole. The Downloader hardcodes
`/media/fat/linux/7za` and, when that file is absent, DOWNLOADS p7zip 16.02
(2016-05-21, ARM, dynamically linked) from
`SD-Installer-Win64_MiSTer/raw/master/7za.gz` to fill it. Our build now ships
a statically-linked 7-Zip 26.02 into that exact path via both payload routes,
so the fetch never fires. Full mechanism + evidence: ADR 0023,
`docs/downloader-contract.md` §4. p7zip itself is dead upstream since 16.02
and carried on only by a community fork at 17.06 (2022), so "the latest
p7zip" would still be four years stale against 7-Zip's own Linux support.

Same four toolchain deps p7zip had, all still satisfied and all still real
(they are not copied over blindly): `BR2_TOOLCHAIN_HAS_SYNC_4` for
`C/Threads.c:783`'s `__sync_add_and_fetch` on a 4-byte LONG,
`BR2_INSTALL_LIBSTDCPP` because the link driver is g++ (C++ was already
pulled in for Main_MiSTer/T1-T4, §2.1), `BR2_TOOLCHAIN_HAS_THREADS` for the
`-lpthread` the makefile hardcodes, and `BR2_USE_WCHAR` because 7-Zip's
UString is wchar_t-based throughout.

There is no 7za/7zr Kconfig `choice` to pin here the way p7zip needed: 7-Zip
builds ONE full application (`7zz`) and the old 7za/7zr split is a matter of
which upstream Bundles/ target you compile, not a runtime mode. `7za` is
installed as an alias to it — see `package/7zip/7zip.mk`. That also makes the
old "7za's extra zip/cab/arj/... support is not needed" note moot: it comes
along at zero cost, and zip/lzop below plus the busybox xz/bzip2/gzip applets
stay for the compress-side and applet-parity reasons in their own notes.
`BR2_PACKAGE_7ZIP=y`.

- `BR2_PACKAGE_ZIP=y` — zip/PKZIP-compatible archiver. No dependencies.
  BusyBox has `unzip` but no `zip` applet of its own — no collision.
- `BR2_PACKAGE_LZOP=y` — lzop compressor. Selects `BR2_PACKAGE_LZO`, already =y
  (§5.4). Installs ONLY the `lzop` binary (verified by reading the upstream
  1.04 Makefile.am: `bin_PROGRAMS = src/lzop`, no unlzop/lzopcat symlinks) —
  does not collide with BusyBox's own `unlzop`/`lzopcat` applets
  (decompress-only, different names, still on). BusyBox's OWN `lzop`
  (compressing) applet is separately already off in the base config, so
  there is nothing to disable even if it did share the name.

### 5.38 Off-device backup: Azure Storage CLI — package present, NOT enabled

`# BR2_PACKAGE_AZCOPY is not set`. azcopy (`package/azcopy`, BR2_EXTERNAL —
upstream Buildroot has none) pushes the exFAT data partition's
saves/screenshots/config to Azure Storage straight from the board. It WORKS:
it was built, installed and exercised end-to-end on real hardware (132 MiB
uploaded, md5-verified round trip, incremental `sync`, Azure Files, plan files
on exFAT). `docs/azcopy.md` section 4 has the transcript.

IT IS OFF BECAUSE OF SIZE, and only because of size. 41,007,016 bytes =
39.1 MiB installed — the second-largest package in the image after samba4's
~49 MiB, and about a fifth of the free space `linux.img` has left
(`scripts/check-size-budget.sh` on the 2026-08-17 build: 195 MiB / 38.1% free).
The budget would still pass at ~30.5% free. "Would still pass" is not the same
as "is worth spending", and for a tool most users will never run it is not:
azcopy ships as a standalone downloadable artifact instead, where the people
who want it pay the 8.3 MiB (xz) download and nobody else pays anything. See
`docs/azcopy.md` section 1.

WHY IT IS SO BIG, since that is the obvious next question: almost none of it
is AzCopy. Measured by linking each dependency tree on its own for ARMv7 — an
empty Go binary is 1.2 MB, +Azure SDK is 5.5 MB, and +Google Cloud Storage is
27.6 MB. GCS drags in gRPC, protobuf and the Envoy go-control-plane xDS protos,
none of which a MiSTer backup will ever execute. AzCopy's own code is ~1.3 MB
of symbols. `docs/azcopy.md` section 1 also prices the surgery to cut it out
(~20 files, a permanently-carried patch across credential handling).

TURNING IT ON is one line — replace the not-set line with
`BR2_PACKAGE_AZCOPY=y` and the package builds, installs `/usr/bin/azcopy` and
its `/etc/profile.d/azcopy.sh` defaults, and selects `BR2_PACKAGE_HOST_GO`
(build-time only, nothing from it ships) plus `BR2_PACKAGE_CA_CERTIFICATES`
(already =y in its own right, §5.9, and deliberately kept explicit there so it
survives azcopy being switched off again). Enabling it also pulls host-go's
five-stage from-source bootstrap into the build — measured at ~4.2 min, plus
~12 s to compile azcopy itself, so WALL CLOCK is not the concern. DISK is:
host-go's module cache measured 1.7 GiB, and `docs/ci.md`'s disk-and-cache
budget was written without it. Check that before turning it on in CI.
(`release.yml` enables it for the standalone artifact by appending the line
to `output/.config` after `make de10nano-defconfig` + `olddefconfig`.)

ARMv7 IS NOT AN UPSTREAM-SUPPORTED TARGET for AzCopy: Microsoft publishes
linux/amd64 and linux/arm64 binaries only, and two defects had to be patched
to build and run at all (`package/azcopy/0001-*`, `0002-*`).

### 5.39 T5: hardware buses

dtc (`BR2_PACKAGE_DTC_PROGRAMS`) and i2c-tools (`BR2_PACKAGE_I2C_TOOLS`) are
also part of this task's Group 3 list, but both are handled where their
existing line already lives (§5.15): DTC_PROGRAMS is set right next to
`BR2_PACKAGE_DTC=y` (it was library-only until then), and
`BR2_PACKAGE_I2C_TOOLS=y` was already fully on (P3.11, RTC add-on) with no
sub-options gating any of its tools — nothing to add there.
`BR2_PACKAGE_SPI_TOOLS=y` — spi-config, spi-pipe — Linux spidev command-line
helpers. No dependencies at all beyond autoreconf (host-side only).

### 5.40 T5: Bluetooth CLI

`BR2_PACKAGE_BLUEZ_TOOLS=y` — bt-adapter, bt-agent, bt-device, bt-network,
bt-obex. Depends on `BR2_PACKAGE_BLUEZ5_UTILS` (already =y, §5.13),
`BR2_USE_MMU` and `BR2_USE_WCHAR` (both true) and `BR2_TOOLCHAIN_HAS_THREADS`
(true). Selects DBUS, DBUS_GLIB, LIBGLIB2 — ALL THREE already =y (§5.10) — and
READLINE, already =y (§5.11) — so this is a genuinely
zero-marginal-dependency add, every one of its `select`s was already paid
for. NOTE for whoever reads this next to T3: stock's `usr/sbin/btctl`/`btpair`
scripts (vendored, `docs/stock-reconciliation.md` §3c) are dbus-python +
PyGObject talking to bluetoothd directly (§5.17), NOT wrappers around these
bt-* CLI tools — the two are independent Bluetooth control paths that happen
to ship together, not a dependency of one on the other.

### 5.41 T5: console / keyboard

`BR2_PACKAGE_KBD=y`. kbd is the SAME upstream package stock's own
loadkeys/setfont/showkey/dumpkeys came from (kbd-2.9.0 here; verified stock's
strings match this family in `board/mister/de10nano/rootfs-overlay/etc/inittab`'s
own note 3). T3 already vendored `etc/kbd.map` and restored the guarded
inittab lines (`[ -x /usr/bin/loadkeys ] && ...`) in anticipation of this line
landing — see `docs/stock-reconciliation.md` §3c ("etc/kbd.map",
"consolefonts" rows) and `etc/inittab`'s note 3. Needs `BR2_USE_MMU` (fork())
and gcc >= 4.9 (`_Generic`) — both already true.
`--disable-vlock/--disable-tests` (`package/kbd/kbd.mk`) are upstream
Buildroot's own choices, not touched here. COLLIDES with four BusyBox
console-tools applets that are already on — chvt, deallocvt, openvt,
setkeycodes — all four disabled in busybox.fragment; see that file for the
full citation (kbd's own `src/Makefile.am` PROGS list + `configure.ac`'s
`KEYCODES_PROGS` default).

setfont's font: kbd 2.9.0 ships its own `data/consolefonts/default8x16.psfu`
and installs it to `/usr/share/consolefonts` (`data/Makefile.am:45-49`) — the
exact directory stock's own setfont hardcodes — so bare `setfont` (our guarded
inittab line) resolves without any extra data file needing to be vendored;
matching or not matching stock's exact filename (`default8x16.psfu.gz`) does
not matter either way: setfont's own lookup (kbd-2.9.0
`src/libkfont/setfont.c:417`, `findfont()` -> `kbdfile_find()`) tries the bare
name AND every configured decompressor's suffix (`kbdfile.c:241-267`,
`maybe_pipe_open()`) before giving up, so it finds `default8x16.psfu` OR
`default8x16.psfu.gz` equally well, transparently decompressing via a pipe if
needed. Whether the installed file actually ends up named .psfu or .psfu.gz
depends on whether THIS build host has gzip at kbd's configure time
(`data/Makefile.am`'s install-consolefonts runs `configure.ac`'s
`enable_compress=auto` -> "gzip -n" check first) — not verified against a real
build for this task; check `output/target/usr/share/consolefonts/` on the next
one if the exact filename ever matters. Either way, functionally identical,
not a gap.

SIZE, honestly: that one font is not the only thing that lands. kbd's
`install-data-hook` (`data/Makefile.am:73`) unconditionally runs FOUR install
rules — install-keymaps, install-consolefonts, install-consoletrans,
install-unimaps — there is no Buildroot/configure knob to install only the
one font. Read directly from the pinned 2.9.0 tarball: `data/consolefonts`
(209 files, 1.5 MiB), `data/keymaps` (281 files minus a handful ignored by
`IGNORE_KEYMAPS`, 3.1 MiB), `data/consoletrans` (500 KiB), `data/unimaps`
(368 KiB) — ~5.5 MiB of uncompressed source. configure's default
(`enable_compress=auto`) gzips fonts+keymaps at BUILD time if a host gzip
exists (it does, on any real build host), so the INSTALLED size is smaller
than 5.5 MiB, but by how much was not measured here (no build was run for
this task) — do not assume a specific number without checking
`output/target/usr/share/{consolefonts,keymaps,consoletrans,unimaps}/du -sh`
on the next real build. Not a blocker: `./scripts/check-size-budget.sh
output/images/linux.img` on the last built image reports 512 MiB total,
290 MiB USED, 222 MiB / 43.4% FREE against a 15% threshold — so even the
full 5.5 MiB uncompressed worst case is ~2.5% of the headroom. Two caveats on
that number, stated rather than glossed: it is measured on an image built
BEFORE T3/T5's ~21 new packages, so real free space after this lands is
lower; and the 290 MiB figure is the USED half, not the free half (an easy
swap to make — `docs/package-manifest.md`'s Drop-list §5 zoneinfo row is the
companion discussion of what "not a concern" looks like at this scale, and
of why block usage beats the byte column for many-small-files trees like
these). Re-run that script after the next real build rather than trusting
either number here. This is still real data this image did not carry before,
useful beyond the one keymap/font stock actually used, and
`docs/package-manifest.md` §5's consolefonts/keymaps row is updated to say so.

### 5.42 DEBUG TOOLING — TEMPORARY, REMOVE AS ONE BLOCK

Everything between the `>>> DEBUG TOOLING` banner and the matching `>>> END
DEBUG TOOLING` banner in the fragment is on-device debugging/profiling
tooling, enabled on request for the field hard-hang investigation and for RT
latency measurement. It is NOT stock parity, it is NOT part of the P2.1
package manifest, and it is expected to be removed once those investigations
close. Full rationale, per-package sizes, on-device usage and the exact
revert recipe: `docs/debug-tooling.md`.

TO REVERT: delete the whole block (banner to banner) and re-run `make
de10nano-defconfig && make all`. Nothing outside this block and the matching
`CONFIG_COREDUMP` block in `board/mister/de10nano/linux.config` depends on any
of it.

The block is deliberately contiguous and `BR2_PACKAGE_`-only so that (a) it
can be deleted with one editor motion, and (b) it cannot evict the CI
cross-toolchain cache: `.github/actions/buildroot-build`'s toolchain
fingerprint filters out every `^BR2_PACKAGE_` line, so adding these costs no
cold 3h rebuild (`docs/ci.md#toolchain-fingerprint`).

The old monolith warned that `make savedefconfig` DISSOLVES this block: it
rewrote the file from kconfig's own state, which knows nothing about banners —
the comments went, and the symbols scattered into the generated ordering,
after which "delete the block" was no longer a one-motion operation. That
hazard is gone with the fragment split (§1: savedefconfig no longer writes
into a tracked file).

- `BR2_PACKAGE_GDB=y`, `BR2_PACKAGE_GDB_SERVER=y`, `BR2_PACKAGE_GDB_DEBUGGER=y`
  — gdbserver AND the full on-device debugger. Both are asked for explicitly:
  gdbserver for the normal cross-debug flow (host cross-gdb over TCP), the
  full debugger so a core file can be opened on the device itself with no
  host toolchain present, which is the realistic flow for a field hard-hang
  report from a beta tester. NOTE on `BR2_PACKAGE_GDB_SERVER`:
  `package/gdb/Config.in` `select`s it whenever GDB_DEBUGGER is off, so it
  would be implied by GDB alone TODAY — but that select disappears the moment
  `GDB_DEBUGGER=y` (which is the case here), so it must be listed explicitly
  or enabling the full debugger would silently DROP gdbserver. Setting it is
  not redundant. GDB_DEBUGGER pulls in `BR2_PACKAGE_{GMP,MPFR,READLINE,ZLIB}` by
  select. Three of the four are already on and stay on after this block is
  deleted, but for TWO different reasons, worth keeping straight: readline and
  zlib are set EXPLICITLY (§5.11, §5.4); GMP is NOT set at all — it arrives
  transitively via gnutls/gcrypt (§5.9, which says do not set it separately).
  Only MPFR is genuinely new, and it too arrives transitively rather than
  being listed — do NOT add a line for it, or it would outlive this block's
  deletion, which is the one thing this arrangement exists to prevent.
  `BR2_USE_WCHAR=y` is a GDB_DEBUGGER dependency and is already satisfied
  (glibc + `BR2_ENABLE_LOCALE`). `GDB_TUI` / `GDB_PYTHON` are deliberately NOT
  enabled: neither was requested and both only add on-device UI weight.
- strace — syscall tracing, no dependencies at all on this toolchain — was in
  this block and is now permanent (§5.32); `strace -k` (stack traces on each
  syscall) additionally wants `BR2_PACKAGE_LIBUNWIND`, which is deliberately
  left off; see `docs/debug-tooling.md` "what is deliberately NOT enabled".
- `BR2_PACKAGE_LINUX_TOOLS_PERF=y`, `BR2_PACKAGE_LINUX_TOOLS_PERF_NEEDS_HOST_PYTHON3=y`
  — perf, built from OUR kernel's own `tools/perf` (`BR2_PACKAGE_LINUX_TOOLS_PERF`
  selects the `BR2_PACKAGE_LINUX_TOOLS` meta-symbol, which is part of the
  linux package, not a standalone one — so perf is rebuilt whenever the
  kernel is). The kernel side needs nothing from us:
  `package/linux-tools/linux-tool-perf.mk.in` force-enables
  `CONFIG_PERF_EVENTS` via `KCONFIG_ENABLE_OPT` at kconfig-fixup time, and in
  this tree that fixup is already a no-op — `CONFIG_PERF_EVENTS=y`,
  `CONFIG_ARM_PMU=y` and `CONFIG_HW_PERF_EVENTS=y` all resolve on by kconfig
  default and are live in the built .config today (verified against
  `output/build/linux-<pinned version>/.config`; last confirmed on 6.18.39).
  Hardware counters are wired too: `socfpga.dtsi` has the `arm,cortex-a9-pmu`
  node with both per-CPU PMU interrupts, so `perf stat` gets real
  cycle/instruction counts rather than software events only.
  `_NEEDS_HOST_PYTHON3` is NOT optional on this kernel and NOT cosmetic: since
  ~6.0 perf generates `pmu-events.c` at build time by running
  `tools/perf/pmu-events/jevents.py`, and the pinned kernel still does (that
  file is present in the unpacked tree; last confirmed on 6.18.39). Without
  this symbol Buildroot never adds host-python3 to `PERF_DEPENDENCIES` and the
  perf build fails on whatever python3 the *host* happens to have, or none.
- `BR2_PACKAGE_RT_TESTS=y` — rt-tests — cyclictest et al., the standard
  PREEMPT_RT latency harness. This is what actually measures the RT kernel's
  wakeup latency on hardware, which `docs/rt-beta-kernel.md` still lists as an
  open TODO (the RT kernel boots; its latency has never been measured).
  Selects `BR2_PACKAGE_NUMACTL` transitively — again, do not list numactl, it
  must disappear with this block. hwlatdetect is a Python script and installs
  because `BR2_PACKAGE_PYTHON3=y`.

### 5.43 System configuration

Everything from here on lives in Buildroot's *System configuration* menu. In
the old monolith they were once scattered — `BR2_ROOTFS_MERGED_USR` sat on
line 1, ABOVE the file's own header comment, and `BR2_TARGET_GENERIC_ROOT_PASSWD`
was stranded directly under the "explicitly NOT carried forward" note, where
it read as part of the drop list — and were grouped with no value change.
Merged /usr now lives in `common.fragment` (§2.5). NOTE this menu is NOT the
toolchain menu, so the P1.2 "incremental builds silently ignore toolchain
menu changes" hazard (§5.3) does not apply to anything in this section.

`BR2_TARGET_GENERIC_ROOT_PASSWD=""` — empty = passwordless root, matching
stock. Per-device SSH host keys are generated on first boot instead (ADR 0015;
`docs/ssh-ftp-parity.md`). §10 says why this line is per image fragment rather
than in `common`.

### 5.44 locale data (stock parity; fixes update_all.sh)

`BR2_GENERATE_LOCALE="en_US.UTF-8"`. Distinct from `BR2_ENABLE_LOCALE` (=y,
toolchain menu, §5.3): that one compiles locale *support* into glibc, this
one actually *generates* the locale data. With it empty — the Buildroot
default — the Makefile never registers its `GENERATE_GLIBC_LOCALES`
target-finalize hook and never builds host-localedef, so the image shipped
with no `/usr/lib/locale` at all. Our own rootfs-overlay `/etc/profile`
exports `LC_ALL=en_US.UTF-8`, so *every* login shell printed "setlocale:
LC_ALL: cannot change locale (en_US.UTF-8)", and anything calling
`setlocale(LC_CTYPE, "")` hard-failed — notably `update_all.sh`, which died on
`locale.Error: unsupported locale setting` before doing any work.

Stock's `/usr/lib/locale` is a single 2.9 MB locale-archive
(`docs/stock-inventory/disk-usage.md`), which is exactly the artifact
`support/misc/gen-glibc-locales.mk` produces. en_US.UTF-8 is what
`/etc/profile` asks for and is already in `BR2_ENABLE_LOCALE_WHITELIST`
("C en_US"), so locale-purge keeps it. This lives in the *System
configuration* menu (`work/buildroot/system/Config.in:575`), NOT the toolchain
menu — it only adds a host package and a finalize hook, so it does not
trigger the from-scratch-rebuild hazard.

### 5.45 timezone / tzdata (stock parity)

`BR2_TARGET_TZ_INFO=y`, `BR2_TARGET_TZ_ZONELIST="default"`,
`BR2_TARGET_LOCALTIME="Etc/UTC"`.

We shipped NO tzdata at all: no `/usr/share/zoneinfo`, no `/etc/localtime`.
So the timezone did not survive a reboot and `TZ=America/New_York` could not
resolve. `package-manifest.md` §5's Drop list floated trimming zoneinfo and
hedged — "international users likely rely on the full zoneinfo set for TZ=" —
and that caveat is exactly what bit. Not dropped on purpose; just never
enabled.

Stock's `/usr/share/zoneinfo` contains BOTH `posix/` and `right/` subtrees
(verified against the extracted stock rootfs), which is precisely what
Buildroot's tzdata installs with the "default" zonelist — so stock *was*
plain Buildroot tzdata, and this reproduces it 1:1. No zone present in stock
is missing from ours. `BR2_TARGET_LOCALTIME="Etc/UTC"` also reproduces stock's
`/etc/timezone` byte-for-byte ("Etc/UTC").

Costs ~4.9 MB of ext4 *blocks* (1,191 mostly-tiny zone files, each rounding
up to a 4 KiB block) — NOT the 1.57 MiB that disk-usage.md's byte column
implies. Either way: not a size concern. `./scripts/check-size-budget.sh
output/images/linux.img` on the last built image reports 512 MiB total,
290 MiB USED, 222 MiB / 43.4% FREE against the 15% threshold. (290 is the
used half, not the free half — an earlier revision of this note had the two
swapped. The measurement also predates T3/T5's ~21 new packages, so real free
space after those land is lower; re-run the script, do not trust a number
cached in prose.)

NOTE: `BR2_TARGET_LOCALTIME` makes tzdata install `/etc/localtime` as a
symlink to `../usr/share/zoneinfo/Etc/UTC`. That is NOT what stock does and
NOT what makes the setting persist. Stock points `/etc/localtime` at a file
on the FAT data partition, which is the only thing that survives reflashing
the rootfs — our rootfs-overlay ships that symlink and overwrites tzdata's,
because Buildroot rsyncs `BR2_ROOTFS_OVERLAY` *after* package install
(`Makefile:816`). See `board/mister/de10nano/rootfs-overlay/etc/localtime`.

That symlink is dangling on a FRESH card — `/media/fat/linux/timezone` does
not exist yet, so glibc silently falls back to UTC and stays there. The
overlay's `usr/lib/dhcpcd/dhcpcd-hooks/90-timezone` fills it in once, the
first time the box gets an address, from a geo-IP lookup (ADR 0025). It needs
the full zonelist to have a zone to copy, and the `posix/` subtree
specifically — the same path the community `timezone.sh` copies from.

---

## 6. `de25nano.fragment`

D2.1: a bare developer OS for the Terasic DE25-Nano (Intel/Altera Agilex 5,
HPS = 2x Cortex-A76 + 2x Cortex-A55, aarch64).

Plan: `docs/de25-nano-tasks.md`, task D2.1 (Phase D2). Decisions:
`docs/de25-implementation-path.md` §1 (the nine owner decisions); ADR 0027
(multi-board readiness); ADR 0027 Decision 6 as formalised by D2.7 (the
release scope is a BARE DEVELOPER OS); ADR 0029.

### 6.1 What this is, and — more importantly — what it is not

This builds an aarch64 toolchain, a mainline 7.2.3 kernel, a minimal BusyBox
ext4 rootfs that boots to a serial login with ethernet up, the bootloader that
loads them (TF-A BL31 inside a mainline U-Boot FIT, §6.9) and the SD-card image
that carries the lot (§6.11). That is the whole scope. There are NO MiSTer
packages here, NO DE10 packages, and nothing beyond what a developer needs to
get a shell on the board. That is not an oversight or a staging state — it is
the accepted release scope for this board until the upstream MiSTer framework
grows an aarch64 story (`de25-nano-tasks.md` D2.7 / Phase D3).

THE DE10 IS NOT AFFECTED BY THIS FRAGMENT. The de25nano stack is `common` +
`de25nano` (§1); nothing from `de10nano.fragment`, `de10nano-image.fragment`,
`kernel-only.fragment` or `mister_rt.fragment` is in it, and the DE25 gets its
OWN Buildroot output directory (`output-de25/`, `make de25`) exactly the way
the RT variant and the two initramfs stages get theirs. No `BR2_` symbol is
shared between the boards outside `common.fragment`. Two FILES are shared by
path, each with its own reason and its own guard: the kernel-tarball hash
registry (a symlink, §6.3) and the MiSTer kernel-config fragment
(`board/mister/common/linux-mister.fragment`, proved a no-op on the DE10 by
`scripts/check-kernel-fragment-noop.sh`, §6.5).

WHY THE OLD FILE WAS NOT THE OUTPUT OF `savedefconfig` — and why the fragment
still is not. The DE10 monolith's header explained that it WAS canonical
savedefconfig output and that its comments got dropped on every regeneration.
The DE25 file was hand-written and hand-maintained for the same reason the
DE10's comments kept getting hand-restored: on a board with no hardware
validation yet, the reasoning is the deliverable. It has been round-tripped
through `savedefconfig` to prove every symbol really exists — but the file
itself is not the machine's output.

ROUND-TRIP RESULT, re-run 2026-09-02 after the bootloader stanza landed
(Buildroot 2026.05.2). savedefconfig ADDED nothing (so no symbol is
implied-but-unstated) and DROPPED exactly six lines as non-divergent from a
kconfig default:

- `BR2_LINUX_KERNEL_IMAGE`, `BR2_TARGET_ROOTFS_EXT2_LABEL`,
  `BR2_TARGET_GENERIC_ROOT_PASSWD`;
- `BR2_TARGET_ARM_TRUSTED_FIRMWARE_BL31` (selected by
  `BR2_TARGET_UBOOT_NEEDS_ATF_BL31`), `BR2_TARGET_UBOOT_NEEDS_ATF_BL31_BIN`
  (the default of its choice), `BR2_TARGET_UBOOT_USE_DEFCONFIG` (the default
  of its choice).

All six are kept anyway, for the reason §5.2 gives for the DE10's own
EXT2_LABEL line: a Buildroot default is not a promise. The three bootloader
ones are worth the redundancy for a second reason — "BL31 only, no FIP", "BL31
as a raw `.bin`, not an ELF" and "an in-tree board defconfig, not a custom
config file" are the three facts a reader most needs from that stanza, and
inferring them from a select and two choice defaults is not reading.
`BR2_LINUX_KERNEL_IMAGE` is the sharpest case — the "Kernel binary format"
choice carries `default BR2_LINUX_KERNEL_ZIMAGE if BR2_arm || BR2_armeb` and
NO default for aarch64 (`linux/Config.in:242-244`), so on this architecture it
resolves to whichever entry upstream happens to list first. That is not
something a boot artifact should depend on. (`scripts/check-config-fragments.sh`
(b) now proves each of those six survives olddefconfig on every run, §11.)

### 6.2 Architecture & toolchain — `BR2_aarch64`, `BR2_cortex_a76_a55`, `BR2_KERNEL_HEADERS_7_0`

- aarch64, cortex-a76.cortex-a55 big.LITTLE: the Agilex 5 HPS is a 2xA76 +
  2xA55 cluster. `BR2_cortex_a76_a55` is Buildroot's own name for that tuning
  target and resolves to `-mcpu=cortex-a76.cortex-a55`
  (`work/buildroot/arch/Config.in.arm:474`, `:945`). It selects
  `BR2_ARM_CPU_ARMV8A` + `FP_ARMV8` and needs GCC >= 9; this Buildroot's
  internal toolchain is GCC 14.x, so that floor is met with room to spare.
  NOTE it is a *tuning* choice, not an ISA restriction: the generated code
  runs on either cluster, which is the entire point of the big.LITTLE tuple.
  **Do NOT "simplify" it to `BR2_cortex_a76`** — that would tune for the big
  core only and schedule badly on the A55s.

  There is no NEON/VFP stanza here, unlike the DE10's. On AArch64 Advanced
  SIMD and FP are mandatory parts of the base ISA, so Buildroot has no
  `BR2_ARM_ENABLE_NEON` / `BR2_ARM_FPU_*` knobs on this architecture at all.
  Their absence is correct, not a dropped line (`scripts/lib/board-expectations.sh`
  carries the `BR2_ARM_` family prefix for this board precisely so an empty
  set is a legitimate match).
- Internal Buildroot toolchain, glibc, with C++ (`BR2_TOOLCHAIN_BUILDROOT_CXX`
  comes from `common`, §2.1). glibc is already the default C library for the
  internal toolchain, so it is not a line (savedefconfig drops non-divergent
  symbols); musl is a project-wide non-goal.
- `BR2_KERNEL_HEADERS_7_0`: pins the headers SERIES explicitly, for exactly
  the reason §3.2 spells out at length — do not "fix" it to
  `BR2_KERNEL_HEADERS_AS_KERNEL` to keep headers in lockstep with the kernel.
  Under AS_KERNEL the kernel version arrives as the free-form string
  `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, which kconfig cannot compare
  numerically, so `BR2_TOOLCHAIN_HEADERS_AT_LEAST` silently falls back to its
  2.6 floor and glibc gets configured `--enable-kernel=2.6`: fifteen years of
  dead compatibility code and syscall-fallback paths for kernels this board
  will never run.

  WHY 7_0 AND NOT 7_2. Buildroot 2026.05.2 offers NO 7.2 headers series.
  `package/linux-headers/Config.in.host` tops out at `BR2_KERNEL_HEADERS_7_0`
  (`:55-58`, resolving to 7.0.14 at `:477`); the series list is
  5.10/5.15/6.1/6.6/6.12/6.18/7.0. 7_0 is therefore the newest series
  Buildroot has that is <= our 7.2.3 kernel, and headers OLDER than the
  running kernel is the supported direction — the kernel's uapi is
  forward-compatible by guarantee. §3.2 documents the diff-the-uapi
  discipline that comes with this; the same discipline applies here on any
  kernel or Buildroot bump, and the range to diff is 7.0.14 -> 7.2.3.

  RE-CHECK ON EVERY BUILDROOT BUMP: a Buildroot bump moves the point release
  inside a series on its own, and the day Buildroot adds a 7.2 series this
  pin should move to it in a deliberate commit.

### 6.3 Download integrity — `BR2_GLOBAL_PATCH_DIR` (DE25) and the shared hash file

`BR2_DOWNLOAD_FORCE_CHECK_HASHES` comes from `common` (§2.2).
`BR2_GLOBAL_PATCH_DIR="$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de25nano/patches"`
is load-bearing here for exactly ONE reason, and it is not patches: it is
where Buildroot finds `<dir>/linux/linux.hash`, the only thing that
hash-verifies a pinned custom kernel download. Buildroot's own lookup
resolves the kernel's hash file to `linux/linux.hash`, a path that does not
exist in the release (its real hashes live in `linux/from-6.17/linux.hash`,
which that lookup never consults), so without this the 7.2.3 tarball would
download with a "no hash file" WARNING and never be verified — and
`BR2_DOWNLOAD_FORCE_CHECK_HASHES` cannot save you, because it only forces the
checking of hashes that exist. The full mechanism is written up in the hash
file's own header.

THE HASH FILE IS SHARED WITH THE DE10, BY SYMLINK, ON PURPOSE.
`board/mister/de25nano/patches/linux/linux.hash` is a relative symlink to
`board/mister/de10nano/patches/linux/linux.hash`. That file is already the
repo's kernel-tarball hash registry: it carries BOTH pins (the DE10's 6.18.y
line and the 7.2.y line the RT variant tracks), its header records the
provenance rule for each, and `scripts/hash-sync-kernel.sh` is its single
automated writer. The DE25 pins 7.2.3 — the same tarball the RT variant
already pins — so a second copy of that sha256 could only ever drift out of
sync with the one the sync script maintains. A symlink cannot drift.

CONSEQUENCE, say it out loud: bumping the DE25 kernel version means editing
`board/mister/de10nano/patches/linux/linux.hash`, a de10nano path, in the same
commit. That cross-board reach is deliberate and is the reason this
paragraph is this long. (The alternative — pointing `BR2_GLOBAL_PATCH_DIR`
straight at the de10nano patches directory — was rejected: it would also hand
this board the DE10's bluez5_utils patch set, and it would make the board
directory non-self-contained, which is the specific coupling
`docs/de25-readiness-ledger.md` exists to stop spreading.) This is also why
`BR2_GLOBAL_PATCH_DIR` is a board symbol and not a `common` one (§10).

The `de25nano/patches/linux/` directory contains the hash symlink and nothing
else — no global patches are applied to the kernel from here. Carried kernel
patches live in `BR2_LINUX_KERNEL_PATCH` (§6.4) instead.

### 6.4 Kernel — mainline 7.2.3

`BR2_LINUX_KERNEL`, `BR2_LINUX_KERNEL_CUSTOM_VERSION` come from `common` (§2.3);
`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="7.2.3"` is here.

WHY 7.2 AND NOT THE DE10'S 6.18 (`docs/de25-implementation-path.md` §5, and
decision 7, which supersedes decision 6's openness):
`drivers/clk/socfpga/clk-agilex5.c` does not exist before v6.19. Mainline 6.18
ships the `intel,agilex5-clkmgr` binding, the clock-ID header and the DT node
— and no driver at all. On a 6.18 base every consumer of `&clkmgr`, mmc0 and
all three gmacs included, defers forever, so the board cannot boot from SD.
Basing on 6.18 would mean carrying a whole SoC clock driver when a mainline
route exists one release later, which decision 5 (mainline-first, strongly)
forbids without a justification that no mainline route existed. 7.2 is chosen
over 6.19 because 6.19 is EOL and because this repo already builds and
patches the 7.2.y line for the RT variant — so the DE25 is a new instance of
an existing pattern rather than a third kernel line.

The cost, stated honestly: 7.2 is not LTS, so this board inherits the RT
beta's bump treadmill (`docs/rt-beta-kernel.md`). Re-open the choice if
kernel.org designates a 7.x release longterm. The tarball is already
hash-pinned in the shared `linux.hash` (the RT variant tracks the same 7.2.3),
so this costs no new download and no new TOFU value. The DE25 pin has no
Renovate manager today (`renovate.json`'s 6.18 manager deliberately excludes
this file; the 7.2 manager matches only the rt fragment).

`BR2_LINUX_KERNEL_PATCH="$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de25nano/linux-patches"`
— carried patches for this board. Wired up independently of the series
itself, so adding or removing a patch is a one-file change and never a config
change — Buildroot applies whatever `*.patch` the directory holds, in
`series`/sort order, and is perfectly happy with an empty one. What is
expected to land there, per `docs/de25-implementation-path.md`: decision 8's
sdhci-cadence 40-bit DMA-mask patch — an UPSTREAMABLE carry, to be submitted,
not a permanent fork, and COUPLED to the board DTS (the driver's bare
`cdns,sd4hc` match entry has no `.data`, so the quirk needs a new match entry
and therefore a new compatible string in mmc0); and the subset of the DE10's
40-patch series that D0.3 triaged as shared/portable and that a compile test
against aarch64/7.2 confirms. Do NOT assume the DE10's `linux-patches/` series
applies here: 4 of the 40 differ in content between the main and beta series
alone, and the beta series' 6.18-vs-7.2 re-anchoring lessons apply again for
aarch64.

### 6.5 Kernel config, image format, device tree, no initramfs

KERNEL CONFIG = a pinned minimal base + the shared MiSTer driver fragment:
`# BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG is not set`,
`BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y`,
`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=".../board/mister/de25nano/linux.config"`,
`BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=".../board/mister/common/linux-mister.fragment"`.

THIS SUPERSEDES THE WAVE-1 WIRING, which was the kernel's own arm64
`defconfig` (`BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG`) plus
`board/mister/de25nano/linux.fragment`. The idea there was that arm64
`defconfig` is the configuration mainline actually CI-tests, so every symbol
we do not name tracks upstream for free. What it actually produced was 1,481
modules and a 41.9 MB `Image`: mainline's arm64 `defconfig` is a distro kernel
for every SoC ARM ships, and **no fragment can subtract from it** — a
`# CONFIG_X is not set` line in a merged fragment loses to a `select` from
anything the base left on. The rationale, the measurements and the
per-subsystem justification are in `docs/de25-kernel-config.md`; the short
version is 1,481 → 92 modules, 90 MB → 2.4 MiB of installed modules, 41.9 MB →
20.7 MB `Image`, with the DE10's exact installed-module name set.

So this board now ships a pinned base the way the DE10 does
(`board/mister/de25nano/linux.config`, this board's minimal arm64 + Agilex 5
base), and the delta over it is one fragment.

THE FRAGMENT IS SHARED WITH THE DE10, BY PATH, ON PURPOSE.
`board/mister/common/linux-mister.fragment` is the arch-neutral MiSTer
driver/feature set, and it is proven a no-op against the DE10's resolved
6.18.48 config by `scripts/check-kernel-fragment-noop.sh` — so a symbol added
there for this board cannot silently change the DE10's kernel. The base and
the fragment share no symbol. This is the kernel-config counterpart of the
hash-registry symlink in §6.3: one file, two boards, an automated check that
the sharing stays honest.

NOTE THE SYMBOL NAME — this is `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`, and it is
NOT `BR2_LINUX_KERNEL_USE_DEFCONFIG`. That other option means "an in-tree
defconfig NAMED <x>" and appends `_defconfig` to
`BR2_LINUX_KERNEL_DEFCONFIG` (`linux/linux.mk:360-361`), so asking it for
arm64's plain `defconfig` would build `defconfig_defconfig` — a file that does
not exist. (`BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG`, the wave-1 choice, is
the one that means literally `make ARCH=arm64 defconfig` —
`linux.mk:362-372`, and its own help text names ARM64 as the case it exists
for.) Getting this wrong fails late, in the kernel build, not at configure
time. The wave-1 choice is stated as `is not set` rather than simply dropped,
so the change of shape is visible in the fragment rather than inferable from
an absence — and `scripts/check-config-fragments.sh` (b) proves that not-set
line really resolves that way.

`BR2_LINUX_KERNEL_IMAGE=y` — uncompressed `Image`, not `Image.gz`. This is the
Agilex/U-Boot FIT convention: the FIT image U-Boot loads carries its own
compression metadata, so a pre-gzipped kernel would be either
double-compressed or mislabelled. Whether we later gzip anything is a
phase-2 decision that belongs with the U-Boot and genimage work (D2.2/D2.4).
The Makefile's `de25` recipe asserts `images/Image` exists.

DEVICE TREE — `BR2_LINUX_KERNEL_DTS_SUPPORT` (from `common`) +
`BR2_LINUX_KERNEL_CUSTOM_DTS_PATH=".../board/mister/de25nano/socfpga_agilex5_de25nano.dts"`:
the DE25-Nano board file, authored on mainline's `socfpga_agilex5.dtsi` (it
`#include`s the dtsi out of the kernel tree, so a custom path does not mean a
from-scratch device tree). Node set and every per-line justification:
`docs/de25-dts-rationale.md`; the node set itself is
`docs/de25-implementation-path.md` §3.1. Depends on the two carried patches in
`board/mister/de25nano/linux-patches` (0101 sdhci-cadence 40-bit mask +
binding, 0102 intel,agilex5-svc match). Ships with the SMMU disabled for wave
1 — see the rationale §4 for why the SMMU-on shape cannot program the fabric
on mainline. CUSTOM_DTS_PATH and INTREE_DTS_NAME are alternatives, not
complements; mainline's socdk board file was the placeholder before D2.3
landed and is not the DE25-Nano (no mmc0, fpga-mgr or fpga-region). The
Makefile asserts the .dtb by GLOB, not by name, for exactly this reason.

NO STAGE-1 INITRAMFS ON THIS BOARD, and that is a design point rather than a
gap. The DE10 embeds an armv7 BusyBox cpio into its zImage because U-Boot
passes `-` for bootz's initrd argument and the real root is a loop-mounted
ext4 image sitting on a FAT partition (`docs/boot-chain.md`). The DE25 boots a
plain ext4 root partition directly (decision 3: p1 FAT, p2 everything else),
so there is nothing for a stage-1 to do. `external.mk`'s initramfs-embedding
kernel fixup is guarded off for this build (it keys on `BR2_arm`) — see the
guard's comment there.

### 6.6 Root filesystem — ext4 on p2, modest and plain

`BR2_TARGET_ROOTFS_EXT2=y`, `BR2_TARGET_ROOTFS_EXT2_4=y`,
`BR2_TARGET_ROOTFS_EXT2_LABEL="rootfs"`, `BR2_TARGET_ROOTFS_EXT2_SIZE="256M"`.
This is a developer OS, not the DE10's shipped `linux.img`. 256 MiB
comfortably holds BusyBox + the toolchain runtime with room for a developer to
scp things in. There is deliberately none of the DE10's ceremony here — no
pinned UUID/hash-seed, no forced feature list, no hard-link to `linux.img` —
because none of it has a contract to satisfy yet: no Downloader channel, no
stock artifact to be byte-compatible with, and no reproducibility lane (D2.8
is where a release lane, and with it the question of pinning mke2fs's
randomness, gets designed). Buildroot also emits a rootfs tarball by default
(`BR2_TARGET_ROOTFS_TAR` is `default y`); it is left on, since it is nearly
free and is the convenient form for `tar -x` onto a card partition before
genimage exists (D2.4). `BR2_REPRODUCIBLE` comes from `common` — §2.4 records
what it does and does not guarantee here.

### 6.7 System configuration

`BR2_ROOTFS_MERGED_USR` comes from `common` (§2.5).

Serial console — `BR2_TARGET_GENERIC_GETTY_PORT="ttyS0"`,
`BR2_TARGET_GENERIC_GETTY_BAUDRATE_115200=y`. The DE25-Nano's header UART is
the HPS **uart1** (`serial@10c02100`, `snps,dw-apb-uart`, 16550-compatible) —
not uart0, which is the SoC Development Kit's console. The board DTS enables
only uart1 and aliases it `serial0` with `stdout-path = "serial0:115200n8"`
(`board/mister/de25nano/socfpga_agilex5_de25nano.dts`, "Console UART"; every
reference tree agrees, `docs/de25-dts-rationale.md` U1 [V]). It is the only
enabled 8250 port, so it is ttyS0 whichever numbering rule 8250 applies.
115200 8N1 is what every reference asks for and what the board's USB-UART
bridge uses, so anything else means a garbled login prompt rather than a
missing one. This is the ONE line whose failure mode is "the board looks
dead". The kernel side of it comes from the fragment (8250 + 8250_DW +
8250_CONSOLE, all =y) and the `console=` argument comes from U-Boot's
bootargs, which is phase 2 — so a first boot may need `console=ttyS0,115200`
passed by hand.

`BR2_TARGET_GENERIC_HOSTNAME="de25"`,
`BR2_TARGET_GENERIC_ISSUE="Welcome to MiSTer DE25-Nano (developer OS)"`.

`BR2_TARGET_GENERIC_ROOT_PASSWD=""` — empty = passwordless root, the same
posture as the DE10 image. On this board it is additionally the only way in:
there is no network provisioning, no `authorized_keys`, and no per-device SSH
host-key machinery yet (ADR 0015 is a DE10 rootfs-overlay feature and is not
carried here).

### 6.8 Packages — none, deliberately

BusyBox is Buildroot's own default (`BR2_PACKAGE_BUSYBOX` is `default y` in
`package/busybox/Config.in`) and so does not appear as a line; it is the
entire userland. Nothing else is enabled: no MiSTer packages, no DE10
packages, no out-of-tree WiFi or controller drivers, no debug tooling. When
something is eventually needed here, add it in a commit that says which task
authorised it — the empty package list is the D2.1/D2.7 scope decision made
visible, and a package added "just to have it" quietly repeals that decision.
The fragment split did not change this: the DE10 package set lives in
`de10nano-image.fragment`, which is not in the DE25 stack (§10).

ONE STANDING OBLIGATION IS ALREADY BOOKED AGAINST THAT EMPTY LIST, and the
fragment carries it as a WARNING so it cannot be missed at the moment it
matters. `board/mister/de25nano/linux.config` carries
`# CONFIG_SECCOMP is not set` (a MiSTer posture, matching stock and the DE10 —
`docs/de25-kernel-config.md` §3.1; `SECCOMP` is `default y` on arm64, so wave 1
had it on). `BR2_PACKAGE_OPENSSH_SANDBOX` is `default y` in Buildroot, and
since openssh 10.4 a failed `prctl(PR_SET_SECCOMP)` is `fatal()` rather than
`debug()`. The combination is an `sshd` that binds and listens while killing
every connection preauth, password and key alike — the DE10 hit exactly this
and fixes it with `# BR2_PACKAGE_OPENSSH_SANDBOX is not set` (§5.19 has the
full write-up). Nothing is broken on the DE25 today, because it ships no
openssh; but the day `BR2_PACKAGE_OPENSSH=y` is added to `de25nano.fragment`,
`# BR2_PACKAGE_OPENSSH_SANDBOX is not set` must be added in the same commit.
It is a configure-time flag, so flipping it later also needs
`make openssh-dirclean` or the stale stamp ships the broken sshd.

### 6.9 Bootloader — ATF BL31 + mainline U-Boot, packaged as `u-boot.itb`

D2.4's buildable half. Full write-up, including the per-line rationale for
`board/mister/de25nano/uboot.fragment` and the QSPI-write audit table:
`docs/de25-uboot.md`. Contract: `docs/de25-implementation-path.md` §6.1–§6.3;
`docs/de25-boot-chain.md` §2, §3, §5 and the §7 brick-risk register.

WHAT THIS BUILDS, AND WHAT IT DOES NOT. It builds exactly two artifacts:
`images/bl31.bin` (ATF) and `images/u-boot.itb` (a binman FIT carrying BL31 +
U-Boot proper + our U-Boot dtb). It does NOT build or ship an SPL. On this
board the FSBL is Terasic's U-Boot SPL, resident in QSPI inside the factory
phase-1 bitstream, and it is NEVER touched — posture 1. The SDM on this board
cannot boot from the microSD at all, so the QSPI seam is permanent and any
write to it is brick-class with a JTAG-only recovery. That is why the U-Boot
fragment's largest block is about making a QSPI write structurally impossible
rather than merely unlikely.

The SPL is nevertheless COMPILED — see `uboot.fragment`'s "SPL" block for the
one-line Kconfig reason (`select BINMAN if SPL_ATF`, and `BINMAN` has no
prompt). Nothing of it is shipped: `BR2_TARGET_UBOOT_SPL` is deliberately
absent from the fragment, so Buildroot copies no `spl/*` file into `images/`.
That is the answer to `de25-implementation-path.md` §8 Q6, and it is negative.

**ARM Trusted Firmware.** `BR2_TARGET_ARM_TRUSTED_FIRMWARE=y`,
`_CUSTOM_VERSION=y`, `_CUSTOM_VERSION_VALUE="v2.15.0"`, `_PLATFORM="agilex5"`,
`_BL31=y`, `_IMAGES="bl31.bin"`.

Mainline TF-A v2.15.0. Buildroot 2026.05.2's newest offer is v2.12
(`boot/arm-trusted-firmware/Config.in`), which has no Agilex 5 platform, so a
custom version is not a preference here — it is the only route.
`plat/intel/soc/agilex5/` exists at v2.15.0 and its `socfpga_plat_def.h` sets
`BL31_BASE 0x80000000`, which is exactly the load/entry address the SoC64
binman FIT description hardcodes for the `atf` image. Verified against the
tag; the pairing with U-Boot 2026.07 is still [U] — nobody has booted it.

The version string is the git TAG (`v2.15.0`, with the leading `v`), because
`ARM_TRUSTED_FIRMWARE_SITE_METHOD` is git: Buildroot clones
`git.trustedfirmware.org/TF-A/trusted-firmware-a.git` and generates the
tarball itself. Hash provenance is in the `.hash` file's header.

BL31 only. No BL2 and no FIP: BL2's job on this SoC is done by the factory
SPL, and a FIP is the packaging format for a chain we do not own. `_BL31` is
selected anyway by `BR2_TARGET_UBOOT_NEEDS_ATF_BL31` below; it is stated in the
fragment because "which ATF images exist" is a fact the configuration should
assert rather than leave to be inferred. `_IMAGES` defaults to `"*.bin"`, which
would copy whatever the platform's release directory happens to contain; naming
the one file we ship keeps `images/` auditable and makes the Makefile's `de25`
assertion and that line describe the same thing.

**U-Boot.** `BR2_TARGET_UBOOT=y`, `_BUILD_SYSTEM_KCONFIG=y`,
`_CUSTOM_VERSION=y`, `_CUSTOM_VERSION_VALUE="2026.07"`, `_USE_DEFCONFIG=y`,
`_BOARD_DEFCONFIG="socfpga_agilex5"`, `_CONFIG_FRAGMENT_FILES`,
`_CUSTOM_DTS_PATH`, `_NEEDS_ATF_BL31=y`, `_NEEDS_ATF_BL31_BIN=y`,
`_USE_BINMAN=y`, `_NEEDS_OPENSSL=y`, `_FORMAT_ITB=y`,
`# BR2_TARGET_UBOOT_FORMAT_BIN is not set`.

Mainline v2026.07 (released 2026-07-07; v2026.10 was at -rc when this was
written). Buildroot 2026.05.2 ships 2026.04, so again a custom version.

NOTE THE BUILD-SYSTEM LINE, it is not optional.
`BR2_TARGET_UBOOT_BUILD_SYSTEM` defaults to KCONFIG *only* if
`BR2_TARGET_UBOOT_LATEST_VERSION` is set (`boot/uboot/Config.in:11-12`); on a
custom version it falls back to LEGACY, which would try `make <board>_config`
and fail on a tree that has had no such target for a decade.

Mainline has NO DE25-Nano board — `board/terasic/` has `de0-nano-soc`,
`de1-soc`, `de10-nano`, `de10-standard` and `sockit`, and there is no
`configs/*de25*` anywhere in the tree. `socfpga_agilex5_defconfig` (the SoC
Development Kit) is the base; `uboot.fragment` is the whole delta and every
line of it is commented.

The board device tree, and the `-u-boot.dtsi` that goes with it: Buildroot
copies BOTH files into `arch/arm/dts/` before the build (`uboot.mk`'s
`UBOOT_CUSTOM_DTS_PATH` is a plain `cp -f <list> <dir>`); U-Boot then builds
`$(CONFIG_DEFAULT_DEVICE_TREE).dtb` because `scripts/Makefile.dts` adds it to
`dtb-y`, and auto-includes `<board>-u-boot.dtsi` BY NAME. Both files therefore
have to travel together and be named consistently with the fragment's
`CONFIG_DEFAULT_DEVICE_TREE`. They live in a `uboot-dts/` subdirectory because
the U-Boot board file and the KERNEL board file share a basename by convention
and must not share a directory.

BL31 goes INSIDE the FIT. `_NEEDS_ATF_BL31` makes uboot depend on
arm-trusted-firmware, copies `images/bl31.bin` into the U-Boot build tree
before the build, and passes `BL31=<path>`; binman's `atf` image picks it up as
a blob-ext named `bl31.bin`. The `_BIN` (rather than `_ELF`) form is what the
SoC64 binman description asks for.

`u-boot.itb` is produced by BINMAN, not by the legacy `u-boot.itb:` Makefile
rule (that one is gated on `U_BOOT_ITS`, set only under the deprecated
`SPL_FIT_GENERATOR`). `BR2_TARGET_UBOOT_USE_BINMAN` tells Buildroot the same
thing — it drops `u-boot.itb` from `UBOOT_MAKE_TARGET`, adds the three host
python packages binman needs (jsonschema, pyyaml, yamllint) and passes
`BINMAN_INDIRS` so binman can find blobs in `images/`. It also selects
`BR2_TARGET_UBOOT_NEEDS_PYTHON3` / `_PYELFTOOLS` / `_PYLIBFDT`, which is why
those three are not separate lines.

`_NEEDS_OPENSSL` brings host-openssl in for the U-Boot host tools:
`CONFIG_TOOLS_LIBCRYPTO` is `default y` and `mkimage` links libcrypto. Without
it the build silently depends on whatever openssl headers the developer's
machine happens to have, which is exactly the class of thing this project pins.

Ship the FIT and nothing else. `BR2_TARGET_UBOOT_FORMAT_BIN` is `default y` in
Buildroot and is turned OFF: `u-boot.bin` is a raw image with no place in this
board's boot chain, and an `images/` directory that contains only what goes on
the card is what makes the card-image step's file list reviewable.

### 6.10 Host tools — `dumpimage`/`mkimage`, with FIT support

`BR2_PACKAGE_HOST_UBOOT_TOOLS=y`, `BR2_PACKAGE_HOST_UBOOT_TOOLS_FIT_SUPPORT=y`.

host-uboot-tools gives us `host/bin/dumpimage` and `host/bin/mkimage`.
`dumpimage` is how the FIT's shape is checked against the factory SPL contract
(`de25-implementation-path.md` §6.1) — image list, load addresses, the default
configuration's firmware/loadables/fdt, and the fact that the only integrity
stamp is a crc32 with no rsa key. That check is not decoration: the factory SPL
is built with `FIT_SIGNATURE` on and no keys, so an unsigned crc32 FIT is what
it accepts and a key-requiring one would strand every board.

FIT_SUPPORT is the trap. It is **not** `default y`: with it off,
`dumpimage -l u-boot.itb` prints nothing at all and exits 0, which is a
verification step that always passes and never checks anything. Found the hard
way on the first build. (It selects `BR2_PACKAGE_HOST_DTC`.)

### 6.11 SD-card image (D2.4)

`BR2_PACKAGE_HOST_GENIMAGE=y`, `BR2_PACKAGE_HOST_MTOOLS=y`,
`BR2_PACKAGE_HOST_DOSFSTOOLS=y`,
`BR2_ROOTFS_POST_IMAGE_SCRIPT=".../board/mister/de25nano/post-image.sh"`.

Two partitions, fixed by the factory SPL's `CONFIG_SPL_FS_FAT` + boot
partition 1: p1 FAT32 (`u-boot.itb`, `Image`, the dtb,
`extlinux/extlinux.conf`), p2 the ext4 root of §6.6, written directly (an
interim p2 decision — `docs/de25-sdcard.md`). There is explicitly NO shared SD
card with the DE10 (ADR 0029 D3). Layout:
`board/mister/de25nano/genimage-sdcard.cfg`; assembled and verified by
`post-image.sh` + `scripts/check-sdcard-de25.sh`.

host-genimage does NOT pull in mtools or dosfstools itself
(`package/genimage/genimage.mk`: `HOST_GENIMAGE_DEPENDENCIES = host-pkgconf
host-libconfuse`) and genimage's vfat handler shells out to `mcopy` and
`mkdosfs` BY NAME, so on a runner without them the card build fails inside
genimage rather than at configure time. host-e2fsprogs is already implied by
`BR2_TARGET_ROOTFS_EXT2` (`fs/ext2/ext2.mk`), which is where the checker gets
`dumpe2fs` and `e2fsck`; `sfdisk` comes from the host's util-linux, as for the
DE10's checker.

`BR2_ROOTFS_POST_IMAGE_SCRIPT` is a per-board symbol for the same reason the
DE10's is (§10): both boards set it, to different scripts. Without
`u-boot.itb` in `images/` this FAILS the build by design;
`DE25_ALLOW_NO_UBOOT=1` in the environment downgrades it to a loud skip.

---

## 7. `mister_rt.fragment`

The RT / Linux-7.2 "beta" kernel variant — the BUILDROOT-config layer of the
variant, layered on the kernel-only stack (`common` + `de10nano` +
`kernel-only`, §4) at build time by `make rt` (Buildroot's
`support/kconfig/merge_config.sh`, §1). Everything not listed in the fragment
is inherited from that stack unchanged — same armv7-a / Cortex-A9 toolchain,
same 6.18-pinned kernel headers (so the userland ABI is identical),
rootfs-tar only. Three things change: the kernel version, its patch set, and
its kernel-config delta. (The base has NO packages, so the old full-image
variant's "disable the 7.x-incompatible OOT WiFi drivers" lines are gone —
there is nothing to disable; the OOT-WiFi story for RT is in
`docs/rt-beta-kernel.md` §4.) The two overrides (version, patch dir) are the
ONE allowlisted redefinition in `scripts/check-config-fragments.sh` (§11).

⚠ 7.2-rc4 booted and ran MiSTer on real hardware (2026-07-20), and 7.2-rc7
again on 2026-08-14; the currently pinned 7.2 FINAL line has NOT been booted.
Every version bump re-opens that question — the variant is beta precisely
because the pin moves faster than hardware testing. That is now a slower
clock than it was: as of 2026-08-17 this pin tracks the 7.2.y line, not
mainline, so the next bump is a stable point release rather than the next
-rc. See `docs/rt-beta-kernel.md` for status, design, and the open TODOs.

Do not confuse the two fragment layers: `configs/mister_rt.fragment` is
Buildroot config (`BR2_*`); `board/mister/de10nano/linux-rt.fragment` (named
by §7.3) is KERNEL config (`CONFIG_*`) and is where `CONFIG_PREEMPT_RT` actually
lives. The Makefile's `rt` recipe asserts `CONFIG_PREEMPT_RT=y` in the built
kernel's `.config` because merge_config.sh only WARNS when a fragment symbol
is dropped and olddefconfig silently discards symbols whose dependencies fail.

Adding a future kernel variant `foo` = a sibling `configs/mister_foo.fragment`
like this one + `foo`/`foo-clean`/... Makefile targets + nothing else in CI
(the workflows derive the matrix from the fragment glob; §1).

### 7.1 The 7.2 kernel — `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="7.2.3"`

Just override the version value; the base stack already sets
`BR2_LINUX_KERNEL_CUSTOM_VERSION=y`.

2026-08-17: this pin CROSSED THE -rc BOUNDARY. 7.2 released on 2026-08-16 and
the value became a plain mainline release, not a snapshot. Three things
changed with it, and all three are why the crossing was a deliberate commit
rather than one more automated -rc bump:

1. The ARTIFACT. `linux/linux.mk` branches on the literal substring "-rc"
   (`linux/linux.mk:35`). While it matched, Buildroot fetched a cgit-generated
   snapshot — `linux-<ver>.tar.GZ` from https://git.kernel.org/torvalds/t.
   Without it, the ordinary release tarball `linux-7.2.tar.XZ` comes from
   `$(BR2_KERNEL_MIRROR)/linux/kernel/v7.x` — the series directory is computed
   as `v$(firstword $(subst ., ,$(LINUX_VERSION))).x`, so a two-component
   "7.2" resolves to v7.x correctly. Verified against the real mirror, not
   assumed.
2. The PROVENANCE. kernel.org publishes no signed manifest for an -rc, so the
   old hash was TOFU. `linux-7.2.tar.xz` IS covered by the PGP-signed
   `sha256sums.asc`; `linux.hash`'s own header records the transcription and
   the signature check. Strictly stronger — do not reintroduce a TOFU value
   here without moving back to an -rc, which this pin no longer does.
3. The KERNEL RELEASE STRING, hence the module directory: 7.2.0-rc7 -> 7.2.0.
   7.2's own Makefile reads VERSION=7 PATCHLEVEL=2 SUBLEVEL=0 EXTRAVERSION=
   (checked in the pristine tarball). Note the asymmetry, which is exactly the
   thing that looks like a mistake in a diff and is not: the TARBALL is
   two-component (`linux-7.2.tar.xz` — kernel.org publishes no linux-7.2.0),
   while the kernel it builds calls itself three-component (7.2.0). Both
   spellings are correct and neither is a typo for the other. (Point releases
   since — 7.2.3 today — are three-component in both places.)

On a version bump, `make rt-clean` is MANDATORY before `make rt` — the old
kernel tree survives in `output-rt/build/` otherwise and `rt` refuses to guess
which of two trees to validate (see the Makefile's rt recipe).

COUPLED to `board/mister/de10nano/patches/linux/linux.hash`: the base stack's
`BR2_DOWNLOAD_FORCE_CHECK_HASHES` (§2.2) empties Buildroot's
`BR_NO_CHECK_HASH_FOR` exemption, so the tarball MUST have a sha256 line there
or the build fails closed at download. Bump the version here -> update that
line in the same commit (its header says where the value must come from).
`renovate.json`'s `kernel-rt-7.2` manager bumps this line and
`scripts/hash-sync-kernel.sh --pin=rt` refreshes the hash (it REFUSES any
`-rc` value, by design).

### 7.2 Beta patch set — `BR2_LINUX_KERNEL_PATCH=".../board/mister/de10nano/linux-patches-beta"`

`linux-patches-beta/` is a series-file-driven SUBSET of `linux-patches/`:
symlinks to the shared patch files, EXCEPT 0001, 0015, 0030 and 0037, which
are real re-anchored copies — Buildroot applies patches with `patch -F0`
(fuzz zero), and those four patches' 6.18 context or APIs drifted upstream
(see the series file's header; note 0015 was once wrongly believed upstreamed
in 7.2 — it is not: 7.2 has no FAML/FAMR controller types, and 0037 was once
wrongly written off as cosmetic — it is not, it shifts the DualSense button
indices). 0031 was a fifth until 2026-07-25, when the SHARED patch was
re-anchored onto context both trees agree on and the copy became a symlink
again — see the series header for why that is the preferred move over a
re-anchored copy. The shared 6.18 patches are otherwise deliberately
untouched, keeping them byte-identical to stock.

The series drops exactly ONE shared patch, and only because 7.2 already has
it: `0047-btusb-mercusys-ma530-2c4e-0115`, a backport of mainline ce21a5cf3d1f
(Mercusys MA530/MA550H, USB 2c4e:0115) whose first release IS 7.2. The 6.18
image needs it because 6.18.y never received the commit; this kernel does
not, and listing it would not be harmlessly redundant — at -F0 against
pristine v7.2 the hunk FAILS ("Hunk #1 FAILED at 786"), which would break the
build. It goes away on its own the day the stock pin leaves 6.18.y. Nothing
else is dropped: all 40 entries (the other 36 shared + the four beta-local
patches 0043/0044/0045 — the UIO set — and 0046, the ramoops crash-record
reservation) apply to 7.2 FINAL at -F0 — verified 2026-08-17 through
Buildroot's own `apply-patches.sh` against a freshly extracted pristine
`linux-7.2.tar.xz` whose sha256 matched the signed manifest: 40/40 applied,
exit 0, ZERO hunks taking fuzz (80 hunks land at an offset, which -F0
permits). No re-anchor was needed anywhere: the four re-anchored copies
(0001, 0015, 0030, 0037) carry over unchanged and, with all four beta-local
patches, land at zero offset.

0038-0042 were the last gap — listed nowhere in the beta series from
2026-07-24 until 2026-08-17, on the ASSUMPTION they would need re-anchoring.
Measured, they needed none: plain symlinks, clean at -F0, and `drivers/hid/`
cross-compiles for ARM with all five in (hid-nintendo.o and hid-playstation.o
both build, zero warnings). The three runs that day nest: 34/34 (70 offsets)
on the rc7 -> 7.2 bump, 35/35 (70) once 0046 landed, 40/40 (80) with
0038-0042 symlinked in. See `docs/rt-beta-kernel.md` §2 and §6. And BUILT, not
just applied: `make rt` is green on all 40 from a clean tree (2026-08-17) —
exit 0, release 7.2.0, `CONFIG_PREEMPT_RT=y`, zImage_dtb 9303550 bytes, 90
modules. Still NOT BOOTED; that is per-version and open. (This note
previously read "drops only 0030 + 0037 ... all 29 listed", which went stale
when those two were re-anchored and re-included; 0037 in particular is NOT
cosmetic — see the series header. It then read "drops NOTHING, full stop" from
2026-08-17 until 2026-08-24, when 0047 landed in the shared dir. The 40/40
measurement is unaffected: 0047 was never in the series, so the run that
produced it is still a run of the whole series.)

### 7.3 RT + 7.x kernel-config delta — `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`

`$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/linux-rt.fragment`, layered
on the shared `linux.config` (§3.4). This is where `CONFIG_PREEMPT_RT` lives,
plus the `CONFIG_UIO*` + cmdline set the doorbells need and the `CONFIG_PSTORE*`
set the ramoops node needs (`docs/rt-beta-kernel.md` §8/§9). This symbol is
NEW in the variant, not an override (the base stack sets no kernel-config
fragment, for the `linux-update-defconfig` reason in §3.4).

---

## 8. `mister_initramfs_defconfig`

STAGE 1 of the two-stage build (TASKS.md P1.10 / A1, PLAN.md §5,
`docs/decisions/0002-initramfs.md`). A standalone Buildroot config (not a
fragment stack — nothing in it is shared with the image stacks; see §10),
driven by the top-level Makefile's `initramfs` target into `output-initramfs/`.

This config builds ONE artifact: `output-initramfs/images/rootfs.cpio`, a few
hundred KB of static BusyBox plus our `/init`. The main build (the de10nano
stack) then embeds that cpio into the kernel via `CONFIG_INITRAMFS_SOURCE` —
see `external.mk`, where the path is injected into the kernel .config, and
the top-level Makefile, which sequences stage 1 before stage 2.

**NEVER set `BR2_TARGET_ROOTFS_INITRAMFS` in the MAIN config to do this.** That
option embeds the entire ~300 MB target rootfs into the kernel image. It is
the trap A1 exists to name. Two configs, one cpio.

Why this is a whole second Buildroot config and not a flag on the first one:
the two rootfses have opposite requirements. The target rootfs must be
glibc/shared, because the stock MiSTer binary is linked against it (ADR 0001,
abi-contract §1.3). This one must be static, because it lives inside the
zImage and every byte is a byte of kernel. `BR2_STATIC_LIBS` is not even
offered with glibc ("static only needs a toolchain w/ uclibc or musl" —
Buildroot `Config.in:684`), so the C library choice differs too. None of that
is a conflict: nothing in the initramfs is an ABI surface. It runs BusyBox,
calls mount(2)/losetup, and is deleted from RAM by switch_root before
`/sbin/init` starts. It never meets Main_MiSTer.

### 8.1 Arch/ABI — same silicon as the main build (ADR 0001)

`BR2_arm`, `BR2_cortex_a9`, `BR2_ARM_ENABLE_NEON`, `BR2_ARM_ENABLE_VFP`,
`BR2_ARM_FPU_NEON` — not an ABI requirement here; it just has to run on a
Cortex-A9 (§3.1).

### 8.2 Toolchain: musl, static-only — `BR2_TOOLCHAIN_BUILDROOT_MUSL`, `BR2_KERNEL_HEADERS_6_18`, `BR2_STATIC_LIBS`

musl is chosen *because* it permits `BR2_STATIC_LIBS` (glibc does not) and
because a static musl BusyBox is roughly half the size of a static glibc one.
The main build stays on glibc; see the note above on why that is not an
inconsistency. The headers series pin follows §3.2.

### 8.3 No init system — `BR2_INIT_NONE`

The kernel execs `/init` from the cpio directly; there is no `/sbin/init`, no
inittab and no S-scripts in stage 1.

### 8.4 Device nodes: dynamic/devtmpfs — `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS`

This is not cosmetic. Buildroot's `fs/cpio/cpio.mk` only mknod's
`/dev/console` (c 5 1) in the NON-static branch, and the kernel needs that
node to exist *before* `/init` runs or `/init` has no stdin/stdout/stderr and
the rescue shell is unreachable. Choosing STATIC device creation here would
also make cpio.mk symlink `/init -> sbin/init` instead of leaving ours alone.
The Makefile's `initramfs-verify` asserts `/dev/console` is in the cpio.

### 8.5 BusyBox config and `/init` — `BR2_PACKAGE_BUSYBOX_CONFIG`, `BR2_ROOTFS_OVERLAY`

Our own minimal config, `board/mister/de10nano/initramfs-busybox.config` (see
the header of that file for how it was generated and which symbols are
load-bearing — `CONFIG_FEATURE_MOUNT_FLAGS` above all). `BR2_STATIC_LIBS`
makes `busybox.mk` force `CONFIG_STATIC` on top of it. The overlay
`board/mister/de10nano/initramfs-overlay` is `/init` itself.

### 8.6 fsck.exfat for the on-demand repair path (ADR 0026) — `BR2_PACKAGE_EXFATPROGS`, `BR2_ROOTFS_POST_BUILD_SCRIPT`

`/media/fat` is exFAT, has no journal, and is never cleanly unmounted — not
even by the OSD's own "Reboot", which is a direct write to the HPS reset
controller (`Main:fpga_io.cpp:588-605`) that never reaches init's `::shutdown`
entries. So the volume-dirty flag (`fs/exfat/super.c:512`) is effectively
always set and nothing ever repairs the lost clusters an unlucky power cut
leaves behind.

The initramfs is the ONLY place a repair can run. The root filesystem is
`linux/linux.img`, a file *on* the partition being checked, so once the
system is up the block device can never be released: fsck.exfat's repair mode
opens `O_RDWR|O_EXCL` and a mount holds an exclusive bdev claim
(`fs/super.c:1617`) whether it is ro or rw. Check-then-boot, or not at all.

It runs ONLY when `Scripts/check_storage.sh` has left a marker, never on a
plain boot — see the `fsck_if_requested()` section of the initramfs `/init`
for why the dirty flag alone is not a usable trigger.

The only dependency is `BR2_USE_WCHAR`, which musl satisfies; the installer
config (§9) already builds this package on the same musl+static toolchain.
`board/mister/de10nano/initramfs-post-build.sh` (`BR2_ROOTFS_POST_BUILD_SCRIPT`)
then deletes the five binaries we do not use (dump.exfat, exfat2img,
exfatlabel, mkfs.exfat, tune.exfat — 476 KB of zImage for tools stage 1
cannot invoke) — see there for why that is done in post-build. The Makefile's
`initramfs-verify` asserts `usr/sbin/fsck.exfat` is present and the five are
absent.

### 8.7 Output: a cpio, uncompressed — `BR2_TARGET_ROOTFS_CPIO`, `# BR2_TARGET_ROOTFS_TAR is not set`

Uncompressed is deliberate (`docs/boot-chain.md` I3). The cpio ends up inside
the zImage, which is itself LZ4-compressed (`CONFIG_KERNEL_LZ4`, stock parity),
so compressing it here would just be compressing it twice — and it would
additionally require a matching `CONFIG_RD_*` decompressor in the kernel.
`copy` is the default in the kernel's `usr/Makefile` for a plain .cpio, so
this needs nothing on the kernel side. (`external.mk` nonetheless sets the
kernel's `CONFIG_INITRAMFS_COMPRESSION_GZIP` explicitly — its comment explains
the no-default choice trap.)

### 8.8 Reproducibility (A9) — `BR2_REPRODUCIBLE`

The cpio is embedded in the zImage, so if the cpio is not byte-reproducible
then `zImage_dtb` is not either, and P4.3's double-build job fails for a
reason that has nothing to do with the kernel.

---

## 9. `mister_installer_defconfig`

The THROWAWAY INSTALLER OS (TASKS.md P5.3,
`docs/decisions/0020-sdcard-exfat-reformat-installer.md`, PLAN.md §8/§9). A
standalone Buildroot config, built into `output-installer/` by
`scripts/mk-sdcard.sh` (step 1/7) or the Makefile's `installer` escape hatch.

This config builds ONE artifact: `output-installer/images/rootfs.cpio`, a
static BusyBox + exfatprogs + util-linux(sfdisk) rootfs that
`scripts/mk-sdcard.sh` embeds into a SECOND, dedicated kernel build to produce
the installer's `zImage_dtb`. That image ships as `linux/zImage_dtb` on the
shipped `sdcard.img`'s FAT32 partition — it is NEVER `output/images/zImage_dtb`
(the real MiSTer kernel) and NEVER runs on a card that has already been
installed (ADR 0020 §2.1: the reformat replaces this kernel with the real one,
which is the primary re-run guard).

WHY THIS EXISTS AT ALL (read ADR 0020 §1 first): mr-fusion's "auto-resize" is
not a filesystem grow-in-place — MiSTer's data partition is exFAT, and Linux
has no resize-in-place tool for exFAT. So a fresh card ships small (fast
write, small download) and an on-device first-boot installer OS repartitions
+ reformats it to fill whatever medium the user actually has, then hands off
to the real MiSTer. This config is that installer OS's rootfs. Its `/init`
(`board/mister/de10nano/installer-overlay/init`) does the
sfdisk/mkfs.exfat/copy-back/MAC-gen/dd-uboot.img/reboot dance described in ADR
0020 §2.

Relationship to `mister_initramfs_defconfig` (STAGE 1, §8): this is a SIBLING
of stage 1, not a variant of the main target config: same static musl
throwaway-cpio shape (`BR2_INIT_NONE`, `BR2_TARGET_ROOTFS_CPIO`, no shared
libc), because the installer runs from RAM exactly like stage 1's `/init` does
and is deleted the moment it reboots into the real system. It is deliberately
BASED ON `mister_initramfs_defconfig` line-for-line
(arch/toolchain/init/device-creation/output/reproducibility all copied
verbatim — §8 has the reasoning behind each) and adds exactly what the
installer's job needs on top:

- `BR2_PACKAGE_EXFATPROGS` -> mkfs.exfat (ADR 0020 §2 step 3; `-n MiSTer_Data`).
  Depends on `BR2_USE_WCHAR`, which the musl toolchain choice already selects.
- `BR2_PACKAGE_UTIL_LINUX` + `_BINARIES` -> sfdisk (repartition to the real
  medium size) and blkid (belt-and-suspenders re-run guard, ADR 0020 §2.1:
  skip the reformat if the data partition is already exFAT labelled
  MiSTer_Data and already holds `linux/linux.img`). Buildroot's util-linux
  "basic set" is not further sub-selectable — enabling it for sfdisk also
  pulls in blkid, blockdev, dmesg, findfs, hexdump, mkfs, wipefs etc. as a
  bundle. That overlaps some BusyBox applets (dmesg, findfs) already in the
  stage-1 BusyBox set; the overlap is harmless (both are real, separate
  binaries; the installer's `/init` names whichever it wants) and is NOT a
  reason to drop either side.
- A few extra BusyBox applets stage 1 does not need: cp (for the payload ->
  tmpfs -> exFAT copies), dd (uboot.img -> the 0xA2 partition), reboot (the
  final handoff), blockdev and hexdump (MAC-address generation from
  `/dev/urandom`). See `board/mister/de10nano/installer-busybox.config`'s
  header for exactly which `CONFIG_` symbols that required and why —
  `BR2_PACKAGE_BUSYBOX_CONFIG` names that file.

What it deliberately does NOT add: e2fsprogs. The installer only ever `cp`'s
`linux/linux.img` as an opaque byte blob (never fscks or resizes its ext4
contents; that partition's size is fixed at build time, only the exFAT data
partition around it grows) and never builds one, so there is nothing for
e2fsprogs to do here. Re-add it if a later `/init` revision needs to
inspect/repair `linux.img`.

**NOT `BR2_TARGET_ROOTFS_INITRAMFS`. NOT the main config with a flag.** Same
trap A1 names for stage 1 (§8) applies here verbatim: a fourth Buildroot
output dir (`output-installer/`), a fourth small cpio, never the ~300 MB
target rootfs.

Per-symbol notes beyond §8's:

- Arch/ABI (§8.1): the installer runs on the same Cortex-A9 the production
  system does, briefly, once, in RAM.
- Toolchain (§8.2): everything in this cpio is deleted from RAM within
  seconds of the reformat finishing, so there is no ABI surface to keep
  glibc-compatible for. `BR2_TOOLCHAIN_USES_MUSL` auto-selects `BR2_USE_WCHAR`,
  which is what `BR2_PACKAGE_EXFATPROGS`'s "depends on BR2_USE_WCHAR" needs —
  nothing extra to set for that.
- `BR2_INIT_NONE` (§8.3): unlike stage 1, this `/init` never switch_roots into
  anything: it does its reformat dance and calls `reboot` directly (ADR 0020
  §2, last step). PID 1 must still never exit without warning — see
  `board/mister/de10nano/installer-overlay/init` for the rescue-shell
  contract this config's BusyBox set exists to support
  (CTTYHACK/SETSID/ASH_TEST/FEATURE_SH_MATH are all carried over from stage 1
  for exactly that reason).
- Device nodes (§8.4): same load-bearing reasoning — `/dev/console` must exist
  before `/init` runs, or there is no stdin/stdout/stderr and a rescue shell
  is unreachable.
- `BR2_ROOTFS_OVERLAY` = `board/mister/de10nano/installer-overlay`: `/init`
  itself. A SEPARATE overlay from stage 1's — this is a different program
  with a different job (reformat-and-handoff, not mount-and-switch_root).
  This line is the fixed interface the rest of the sdcard-image plumbing
  (`mk-sdcard.sh`, the installer kernel relink) targets.
- Output (§8.7): this cpio is embedded inside the installer's own zImage
  (itself LZ4-compressed, `CONFIG_KERNEL_LZ4`, stock parity), so compressing
  it here would compress it twice and need a matching `CONFIG_RD_*`
  decompressor for no benefit. `copy` is the kernel `usr/Makefile`'s default
  for a plain .cpio — nothing extra needed on the kernel-config side of the
  relink either.
- Reproducibility (§8.8): the cpio ends up embedded in the installer
  `zImage_dtb` that ships inside `sdcard.img(.xz)` release assets, so the same
  double-build rationale P4.3 applies to the main build applies here too.

---

## 10. Placement decisions

The split was decided symbol by symbol by reading the old DE10, kernel-only
and DE25 files side by side. Rules applied, in order:

1. A symbol set identically in ALL THREE (image, kernel-only, DE25) is
   `common`, unless it would move a CI cache key (rule 4).
2. A symbol both DE10 stacks need and the DE25 does not, or needs with a
   different value, is `de10nano` (board layer).
3. A symbol only the shipped image needs is `de10nano-image`; only the
   kernel-only base, `kernel-only`; only the DE25, `de25nano`.
4. The DE10 build must be provably unchanged, INCLUDING its CI cache keys: the
   toolchain-fingerprint residue of each stack (stripped, deny-list-filtered,
   sorted — `docs/ci.md#toolchain-fingerprint`) must be byte-identical to the
   old single file's. It is (§11).
5. The DE25 is a bare developer OS by decision (ADR 0027 D6, ADR 0029): NO
   DE10 package or MiSTer symbol may reach its stack, whatever "arch-neutral"
   would otherwise suggest. So "common" is the genuinely shared policy, not
   the bulk of the DE10 file — the bulk (the package set) is DE10-only by
   construction, in `de10nano-image`.

The judgement calls, each recorded here:

| Symbol(s) | Placed in | Why not elsewhere |
|---|---|---|
| `BR2_TOOLCHAIN_BUILDROOT_CXX`, `BR2_DOWNLOAD_FORCE_CHECK_HASHES`, `BR2_LINUX_KERNEL`, `BR2_LINUX_KERNEL_CUSTOM_VERSION`, `BR2_LINUX_KERNEL_DTS_SUPPORT`, `BR2_REPRODUCIBLE`, `BR2_ROOTFS_MERGED_USR` | `common` | Set identically by all three old files (rule 1); each has a per-stack rationale in §2. |
| `BR2_TARGET_GENERIC_ROOT_PASSWD=""` | `de10nano-image` **and** `de25nano` (not `common`) | Identical in all three resolved configs (it is the Kconfig default, so the kernel-only stack gets it anyway), and the owner asked for users/passwd in common — but it is neither `BR2_PACKAGE_` nor `BR2_LINUX_KERNEL`, so adding it to the kernel-only stack's text would change the kernel-variant toolchain-fingerprint and bust every variant's host-toolchain cache exactly once (an exact-key cache, no restore-keys). Kept per image fragment so both fingerprints stay byte-identical (rule 4). It is also meaningless for a rootfs that never boots. Revisit if a third image stack appears. |
| `BR2_TARGET_ROOTFS_EXT2`, `_EXT2_4`, `_EXT2_LABEL="rootfs"` | `de10nano-image` **and** `de25nano` (duplicated across sibling stacks) | Identical on both boards but NOT in the kernel-only stack, which is rootfs-tar only by design (§4.2); putting them in `common` would give the kernel-only base an ext4 image (and make `post-image.sh`'s `linux.img` half fire), or need a `# ... is not set` override in `kernel-only` — the one thing fragments must never do (§1). Duplication across mutually exclusive stacks is not an override; the check permits it. |
| `BR2_GLOBAL_PATCH_DIR` | per board | Same purpose (the kernel hash registry) but a different directory on each board, for the reason §6.3 gives (the DE10 dir also carries bluez5 patches). |
| `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, `BR2_LINUX_KERNEL_PATCH` | per board (`de10nano` / `de25nano`); overridden by `mister_rt.fragment` | Different lines and different series; the only allowlisted redefinition in the tree is rt's (§7). |
| `BR2_PACKAGE_HOST_KMOD_XZ`, `BR2_ROOTFS_POST_IMAGE_SCRIPT` | `de10nano` (board), not `de10nano-image` | The kernel-only stack needs both (build-time depmod of `.ko.xz`; `zImage_dtb` assembly) — §3.5, §3.6. `BR2_ROOTFS_POST_IMAGE_SCRIPT` is now set by BOTH boards, to different scripts (the DE25's assembles the card, §6.11), so it is a per-board symbol on both sides rather than a `common` one. `BR2_PACKAGE_HOST_KMOD_XZ` is set by **both** board fragments (`de10nano` and `de25nano`), each for its own depmod: the shared kernel fragment (`board/mister/common/linux-mister.fragment`) sets `CONFIG_MODULE_COMPRESS_XZ`, so build-time depmod on either board needs host kmod with xz or it silently ships an empty `modules.dep` (§3.5; the DE25 hit exactly that on its first wave-2 card). It is not in `common` for the rule-4 reason above (`common` is in the kernel-only stack's fingerprint text). |
| `BR2_ROOTFS_POST_BUILD_SCRIPT`, `BR2_ROOTFS_OVERLAY` | `de10nano-image` | Image-only by design (§4.2: `post-build.sh` stamps a rootfs that ships). |
| `BR2_TARGET_ROOTFS_EXT2_SIZE`, `_INODE_SIZE`, `_MKFS_OPTIONS` | `de10nano-image` | The DE25's 256 MiB ext4 has none of the DE10's contracts yet (§6.6). |
| The whole package set, `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV`, `BR2_GENERATE_LOCALE`, `BR2_TARGET_TZ_*`, `BR2_TARGET_LOCALTIME` | `de10nano-image` | Rule 5. Locale/timezone are arch-neutral and the owner's target listed them as common candidates, but the DE25 old file set none of them and giving a bare developer OS tzdata/locale data is a scope decision D2.x should take explicitly, not a side effect of a refactor. |
| `BR2_INIT_NONE`, `BR2_SYSTEM_BIN_SH_NONE`, `# BR2_PACKAGE_BUSYBOX is not set`, `BR2_TARGET_ROOTFS_TAR` | `kernel-only` | Exactly the old kernel defconfig minus what it shared with the image (§4). |
| DE25 getty/hostname/issue, `BR2_KERNEL_HEADERS_7_0`, `USE_CUSTOM_CONFIG`, `CUSTOM_CONFIG_FILE`, `CONFIG_FRAGMENT_FILES`, `# USE_ARCH_DEFAULT_CONFIG is not set`, `IMAGE`, `CUSTOM_DTS_PATH` | `de25nano` | Board-specific by nature (§6). The kernel-config pair names DE25 files; the *fragment* file it names is shared with the DE10 by path, but that sharing is a file, not a symbol (§6.5). |
| The whole DE25 bootloader stanza (`BR2_TARGET_ARM_TRUSTED_FIRMWARE*`, `BR2_TARGET_UBOOT*`) | `de25nano` | The DE10 has no bootloader in its Buildroot config at all — its boot chain is the stock/Terasic one, assembled outside Buildroot (`docs/boot-chain.md`). Nothing to share, so no `common` question arises. |
| `BR2_PACKAGE_HOST_UBOOT_TOOLS`, `_FIT_SUPPORT`, `BR2_PACKAGE_HOST_GENIMAGE`, `BR2_PACKAGE_HOST_MTOOLS`, `BR2_PACKAGE_HOST_DOSFSTOOLS` | `de25nano` | Host tooling for the FIT and the card image (§6.10, §6.11), and DE25-only in fact: the DE10 stack sets none of these five. Note the near-miss — `de10nano-image` sets `BR2_PACKAGE_DOSFSTOOLS` (+ `_FATLABEL`, `_FSCK_FAT`, `_MKFS_FAT`), the TARGET package that ships `mkfs.fat` on the board, which is a different symbol from `BR2_PACKAGE_HOST_DOSFSTOOLS`. Not a `common` candidate on either count, and rule 4 says so twice over: `common` is in the kernel-only stack, so a `BR2_PACKAGE_HOST_*` line added there would move the kernel-variant toolchain fingerprint and bust every variant's host-toolchain cache, exactly as recorded for `BR2_TARGET_GENERIC_ROOT_PASSWD` above. |
| `mister_initramfs_defconfig`, `mister_installer_defconfig` | left standalone | They share five arch lines and `BR2_KERNEL_HEADERS_6_18` with `de10nano.fragment` but differ on the toolchain (musl, static) and everything else; a "de10nano-arch" micro-fragment would save six lines at the price of a fourth stack shape and a toolchain-fingerprint change for the initramfs host cache (`BR_INITRAMFS_HOST_KEY` hashes that file). Not worth it; their comments moved here (§8, §9) for the same reason as the others. |
| `BR2_PACKAGE_STRACE=y` twice in the old DE10 file | once, in the T5 section of `de10nano-image` | A duplicate within one fragment is a redefinition the check rejects and a kconfig "override: reassigning" warning; T5 had already made strace permanent (§5.32, §5.42). Resolved config unchanged. |

Symbol counts (assignments + explicit not-set lines): `common` 7;
`de10nano` 16; `kernel-only` 3 + 1 not-set; `de10nano-image` 257 + 10 not-set;
`de25nano` 45 + 2 not-set. de10nano stack total 280 + 10 not-set — the old
file had 281 assignment lines, of which one was the duplicate `BR2_PACKAGE_STRACE=y`, so
the SET of symbols is identical; de10nano-kernel stack 26 + 1, exactly the
old kernel defconfig's; de25nano stack 52 + 2 not-set, exactly the old DE25
defconfig's (26 + 0 at the split; the bootloader, host-tool and card stanzas of
§6.9–§6.11 and the kernel-config switch of §6.5 arrived with wave 2 and were
ported symbol-for-symbol, the resulting stack symbol set diffed line-for-line
against the last version of the deleted file).

---

## 11. Checks, golden hashes, and the identity proof

**`scripts/check-kernel-defconfig-sync.sh`** (text level, no Buildroot; runs
in every kernel leg before any cache restore and in `build.yml`'s `lint-config`
job): §4 lists its four asserts over the merged text of the `de10nano` and
`de10nano-kernel` stacks. `BOARD=` selects the expectation row in
`scripts/lib/board-expectations.sh`; the compared pair is fixed.

**`scripts/check-config-fragments.sh`** (needs the pinned Buildroot tree,
which it unpacks via `make buildroot-unpack` if absent; config-only, no
compile; ~4 s warm; runs in `lint-config`): for each stack in `stacks.mk` plus
`de10nano-kernel` + every `configs/mister_*.fragment`:

- (a) no symbol is defined by two fragments of one stack — checked from the
  fragment text AND from merge_config.sh's own "redefined" output;
  `ALLOWED_OVERRIDES` (rt: `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`,
  `BR2_LINUX_KERNEL_PATCH`) is the only exception;
- (b) every effective fragment line survives olddefconfig verbatim — a
  `# X is not set` line must come back as exactly that line, so a misspelt
  not-set symbol (absent from the resolved config in either form) is caught
  too — the silently-dropped-symbol class (unmet dependency, renamed option
  after a Buildroot bump, typo);
- (c) the resolved `de10nano` and `de10nano-kernel` configs agree on every
  symbol outside `LOCKSTEP_DIVERGENCE_PREFIXES` (packages, init/shell,
  rootfs images, overlay/post-build, device creation, system configuration,
  `BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_*` — the hidapi select of §5.26 —
  `BR2_GDB_VERSION`, `BR2_DEFCONFIG`);
- (d) the sha256 of the NORMALISED resolved `.config` equals
  `configs/fragments/golden.sha256` for the pinned `BUILDROOT_VERSION`;
- (e) path consumers: every `configs/fragments/<file>` named in the code/CI
  surface (`Makefile`, `scripts/`, `.github/`, `renovate.json` — not docs)
  exists, and `action.yml`'s two `hashFiles()` lists equal the `DE10NANO` /
  `DE10NANO_KERNEL` stacks' files. A fragment rename that updates `stacks.mk`
  would otherwise pass (a)-(d) while the dl-cache keys, Renovate's
  `managerFilePatterns`, the workflow path filter and the scripts that read
  a pin by filename (`hash-sync-kernel.sh`, `ci-tests.sh`,
  `test-initramfs.sh`, `test-sdcard-install.sh`, `export-kernel-tree.sh`,
  `lint-kernel-patches.sh`) all went silently stale.

**Host independence of (d).** `olddefconfig` is run with Buildroot's host
inputs pinned on the make command line (`HOSTARCH=x86_64`,
`HOSTCC_VERSION=14` — Buildroot derives `BR2_HOSTARCH`,
`BR2_HOST_GCC_AT_LEAST_*` and every host-gated package from them, and both are
`:=` variables a command-line assignment overrides), so the resolved config
the check reasons about is a pure function of (fragments, Buildroot version).
Normalisation then keeps only the SET symbols (`BR2_X=…`; `# … is not set`
lines are dropped — lossless for drift, since a symbol flipping on or off
shows as a set line appearing or vanishing, and the not-set list is exactly
where host-gated symbols come and go between machines) and drops, belt and
braces, the set symbols that are host- or checkout-derived even so:
`BR2_HOSTARCH`, `BR2_HOST_GCC_VERSION`, `BR2_HOST_GCC_AT_LEAST_*`;
`BR2_PACKAGE_*_ARCH_SUPPORTS`, `BR2_PACKAGE_HOST_GO_BIN_HOST_ARCH`,
`BR2_PACKAGE_PROVIDES_HOST_RUSTC` (HOSTARCH-derived); the
`depends on BR2_HOST_GCC_AT_LEAST_*` consumers that are `=y` here —
`BR2_PACKAGE_GOBJECT_INTROSPECTION`, `BR2_PACKAGE_HOST_GOBJECT_INTROSPECTION`,
`BR2_PACKAGE_HOST_QEMU*`, `BR2_PACKAGE_LIBGLIB2_BOOTSTRAP`,
`BR2_PACKAGE_PYTHON_GOBJECT` (measured: the only set lines that move between
`HOSTCC_VERSION` 4.9/5/9/14, at the gcc >= 8 floor; the fragment ones are
still proved by (b)); `BR2_VERSION`, `BR2_EXTERNAL_MISTER_*` (git-describe,
absolute path); `BR2_DEFCONFIG`; and the two kernel-version symbols Renovate
moves weekly, `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` and kconfig's derived
`BR2_LINUX_KERNEL_VERSION` (landing proved by (b)). Measured 2026-09-02: the
de10nano hash is identical for the real host (gcc 15), `HOSTARCH=aarch64`,
and `HOSTCC_VERSION` 9, 5 and 4.9, and unchanged by bumping the 6.18, rt and
DE25 kernel pins. So the hash moves ONLY when the resolved configuration
really changes.

**Buildroot bumps.** A bump changes Kconfig defaults and is EXPECTED to move
every hash. Two outcomes, deliberately different: a pinned version with **no
golden line at all** is a `::warning` — the check prints the new lines ready
to paste and the build proceeds, so the automated bump PR still proves it
builds — and `.github/workflows/renovate-hash-sync.yml` case 8
(`scripts/hash-sync-golden.sh`) records the new lines in that PR by running
this tree's `--update-golden` against the freshly unpacked, hash-verified
tarball. A mismatch against a **recorded** line is drift and fails. By hand:
`scripts/check-config-fragments.sh --update-golden --keep`, read
`output-config-check/<stack>/normalised.config` against the previous good
run, commit with that reading in the message (`docs/renovate.md` case 8).

**The identity proof at the split (2026-09-02, Buildroot 2026.05.2).** Before
the monoliths were deleted, each old file was loaded with `make
mister_<x>_defconfig` (the rt variant through the old `defconfig + merge +
olddefconfig` recipe) and `savedefconfig`'d; after, each stack was generated
through the new Makefile path. For all four stacks the resolved `.config`
differed only in `BR2_DEFCONFIG` (old: the deleted file's path; new:
`$(CONFIG_DIR)/defconfig`) and `BR2_EXTERNAL_MISTER_VERSION` (git-describe of
the dirty worktree); `savedefconfig` output was byte-identical; the four
golden hashes recorded in `golden.sha256` are byte-equal to the normalised
hashes of the OLD path's configs; and the toolchain-fingerprint residue of
both DE10 stacks is byte-identical to the old files', so no CI cache key
moved. The same identity was checked for `mister_initramfs_defconfig` and
`mister_installer_defconfig` after their comments moved here (only comments
changed; the resolved configs are byte-identical, `BR2_DEFCONFIG` included,
since the files kept their names).

SINCE THE SPLIT, one golden line has moved on purpose: `de25nano`, when the
DE25 wave-2 work (§6.5's kernel-config switch and the §6.9–§6.11 bootloader,
host-tool and card stanzas) was ported into `de25nano.fragment`. The
`de10nano`, `de10nano-kernel` and `rt` lines are unchanged from the split, and
must stay so — the DE25 shares no stack with them, so a DE25 change that moves
any of the other three is a bug in the change, not in the hash.
