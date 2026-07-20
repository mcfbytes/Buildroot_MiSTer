#!/bin/sh
#
# post-image.sh — assemble zImage_dtb (TASKS.md P1.11, constraint A3).
#
# Buildroot calls this after every image build (BR2_ROOTFS_POST_IMAGE_SCRIPT,
# system/Config.in: "executed from the main Buildroot source directory as the
# current directory", first argument = BINARIES_DIR). It concatenates the built
# zImage with our patched DTB using plain `cat` -- U-Boot computes
# fdt_addr = loadaddr + *(loadaddr+0x2C), i.e. exactly the zImage's declared end
# (docs/boot-chain.md §7; scripts/check-zimage-dtb.sh's own header). Anything
# other than a byte-exact concatenation (padding, a different tool, alignment)
# breaks that arithmetic silently.
#
# This script does NOT re-derive the contract -- it produces the artifact with
# `cat`, then hands it to scripts/check-zimage-dtb.sh, which is the one and only
# place the header/DTB/budget assertions live. A checker failure here is a
# nonzero exit, which Buildroot treats as a failed build (Makefile:848-853 runs
# post-image scripts as ordinary recipe lines with no `|| true`).
#
# Usage: post-image.sh BINARIES_DIR [buildroot-config-name...]
#   (Buildroot always passes BINARIES_DIR first; any BR2_ROOTFS_POST_SCRIPT_ARGS
#   follow it and are ignored here.)

set -eu

prog="post-image.sh"
board_dir=$(cd "$(dirname "$0")" && pwd)
# board/mister/de10nano -> repo root is three levels up.
repo_root=$(cd "$board_dir/../../.." && pwd)
checker="$repo_root/scripts/check-zimage-dtb.sh"

die() {
	echo "$prog: FATAL: $*" >&2
	exit 1
}

[ $# -ge 1 ] || die "usage: $prog BINARIES_DIR"
binaries_dir=$1
[ -d "$binaries_dir" ] || die "BINARIES_DIR '$binaries_dir' is not a directory"
[ -x "$checker" ] || die "checker not found or not executable: $checker"

# --- locate the zImage --------------------------------------------------------
# Standard Buildroot install location for BR2_LINUX_KERNEL_ZIMAGE=y
# (linux/linux.mk LINUX_INSTALL_IMAGES -> $(BINARIES_DIR)/zImage). Fall back to
# searching the kernel build tree in case the image-install step is not wired
# yet -- this keeps the script usable stand-alone against a bare kernel build
# (see the top-level Makefile's `zimage-dtb` target).
zimage="$binaries_dir/zImage"
if [ ! -f "$zimage" ]; then
	zimage=$(find "$binaries_dir/../build" -maxdepth 6 -path '*/arch/arm/boot/zImage' 2>/dev/null | head -n1 || true)
fi
[ -n "$zimage" ] && [ -f "$zimage" ] || die "no zImage found under '$binaries_dir' (or its build/ tree)"

# --- locate our DTB ------------------------------------------------------------
# Standard Buildroot install location once BR2_LINUX_KERNEL_INTREE_DTS_NAME
# names it (linux/linux.mk LINUX_INSTALL_DTB -> $(BINARIES_DIR)/<basename>.dtb,
# BR2_LINUX_KERNEL_DTB_KEEP_DIRNAME is not set here). Same build-tree fallback
# as the zImage above.
dtb_name=socfpga_cyclone5_de10nano.dtb
dtb="$binaries_dir/$dtb_name"
if [ ! -f "$dtb" ]; then
	dtb=$(find "$binaries_dir/../build" -maxdepth 9 -path "*/arch/arm/boot/dts/intel/socfpga/$dtb_name" 2>/dev/null | head -n1 || true)
fi
[ -n "$dtb" ] && [ -f "$dtb" ] || die "no $dtb_name found under '$binaries_dir' (or its build/ tree) -- did P1.7's DTS patch apply?"

echo "$prog: zImage = $zimage ($(wc -c <"$zimage") bytes)"
echo "$prog: dtb    = $dtb ($(wc -c <"$dtb") bytes)"

# --- assemble, atomically -------------------------------------------------------
# Plain cat, nothing else -- the whole point of A3. Write to a temp file and
# rename on success so a failed/interrupted run never leaves a stale or partial
# zImage_dtb behind for a later step to trust.
out="$binaries_dir/zImage_dtb"
tmp="$out.tmp.$$"
trap 'rm -f "$tmp"' EXIT
cat "$zimage" "$dtb" > "$tmp"
mv "$tmp" "$out"
trap - EXIT

echo "$prog: wrote $out ($(wc -c <"$out") bytes)"

# --- the one and only contract check --------------------------------------------
"$checker" "$out"

################################################################################
# P2.5 (A9) — linux.img: the flashable, loop-mounted rootfs image.
#
# KERNEL-ONLY CONFIGS SKIP THIS HALF. configs/mister_kernel_defconfig (the
# kernel-variant base, ADR 0021 as amended 2026-07-18) reuses this script for
# the zImage_dtb assembly above but builds only a rootfs TAR — there is no
# rootfs.ext2 and nothing to ship as linux.img. Gate on what the DRIVING
# config declares (Buildroot exports BR2_CONFIG, the path to the active
# .config, to every post-image script), NOT on whether rootfs.ext2 happens to
# exist: for the main config a missing rootfs.ext2 must stay the hard failure
# it always was, and when BR2_CONFIG is absent (the standalone `make
# zimage-dtb` escape hatch) the old strict behaviour is preserved too.
if [ -n "${BR2_CONFIG:-}" ] && [ -f "${BR2_CONFIG:-}" ] \
	&& ! grep -q '^BR2_TARGET_ROOTFS_EXT2=y' "$BR2_CONFIG"; then
	echo "$prog: BR2_TARGET_ROOTFS_EXT2 not set in $BR2_CONFIG (kernel-only config) -- skipping linux.img assembly"
	exit 0
fi

################################################################################
# BR2_TARGET_ROOTFS_EXT2 (ext4 variant, see configs/mister_de10nano_defconfig
# for why that mechanism and not genimage) writes the actual filesystem to
# BINARIES_DIR/rootfs.ext2 -- that name is fixed by fs/ext2/ext2.mk
# regardless of the ext2/3/4 GEN choice; Buildroot additionally symlinks
# rootfs.ext4 -> rootfs.ext2 as a convenience, but rootfs.ext2 is the file
# that actually exists. Our /init and stock's U-Boot bootargs both expect a
# real file at linux/linux.img (docs/boot-chain.md) -- a plain regular file,
# not a symlink, so a release archive that ships linux.img alone (without
# also shipping rootfs.ext2) still works. `ln` (hard link, same filesystem,
# BINARIES_DIR to itself) gets that for free, instantly, without doubling
# the ~190 MB actually-used footprint of a sparse 512 MiB image the way a
# plain `cp` would risk if sparseness weren't preserved. Removed and
# recreated on every run so a stale linux.img from a previous mkfs options
# change can never survive under a fresh name.
img_checker="$repo_root/scripts/check-linux-img.sh"
[ -x "$img_checker" ] || die "linux.img checker not found or not executable: $img_checker"

rootfs_ext2="$binaries_dir/rootfs.ext2"
[ -f "$rootfs_ext2" ] || die "no rootfs.ext2 found at '$rootfs_ext2' -- did BR2_TARGET_ROOTFS_EXT2 run?"

linux_img="$binaries_dir/linux.img"
rm -f "$linux_img"
ln "$rootfs_ext2" "$linux_img"

echo "$prog: wrote $linux_img ($(wc -c <"$linux_img") bytes, hardlink of $rootfs_ext2)"

# --- the ext4 feature-set / label / UUID / no-secrets contract check -----------
"$img_checker" "$linux_img" "$binaries_dir/../host/sbin"
