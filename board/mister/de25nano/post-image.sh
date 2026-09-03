#!/bin/sh
#
# post-image.sh — assemble the DE25-Nano SD-card image (D2.4).
#
# Buildroot calls this after every image build (BR2_ROOTFS_POST_IMAGE_SCRIPT,
# system/Config.in: "executed from the main Buildroot source directory as the
# current directory", first argument = BINARIES_DIR). It does three things and
# no more:
#
#   1. Generates $BINARIES_DIR/extlinux/extlinux.conf from the template below.
#      Every name and every kernel argument on this card has exactly ONE
#      author, and it is this script: the genimage config lists file names, the
#      checker asserts them, and neither invents them.
#   2. Runs genimage via Buildroot's own support/scripts/genimage.sh against
#      board/mister/de25nano/genimage-sdcard.cfg, producing
#      $BINARIES_DIR/sdcard-de25.img.
#   3. Hands the result to scripts/check-sdcard-de25.sh, which is the one and
#      only place the layout assertions live. A checker failure is a nonzero
#      exit, which Buildroot treats as a failed build (its Makefile runs
#      post-image scripts as ordinary recipe lines, with no `|| true`).
#
# It does NOT re-derive the boot chain. That is docs/de25-boot-chain.md §2/§8.3
# and the genimage config's header; the short version is that the factory SPL
# in QSPI — which nothing we ship ever writes (ADR 0029 D4) — reads a file
# called `u-boot.itb` from a FAT filesystem on partition 1, and that is our
# whole interface to the board's boot firmware.
#
# THE MISSING u-boot.itb CASE. Until D2.2 lands BR2_TARGET_UBOOT there is no
# FIT in BINARIES_DIR, and a card without one is a card that cannot boot. The
# default is therefore to FAIL. Set DE25_ALLOW_NO_UBOOT=1 to downgrade that to
# "skip the card, build succeeds" — for kernel/rootfs iteration and for the
# dry-run harness only. It is an opt-in with a loud message, never a default,
# because a silently u-boot.itb-less image is exactly the artifact somebody
# writes to a card and then debugs at a dead serial console for an hour.
#
# Usage: post-image.sh BINARIES_DIR [buildroot-config-name...]
#   (Buildroot always passes BINARIES_DIR first; any BR2_ROOTFS_POST_SCRIPT_ARGS
#   follow it and are ignored here.)
#
# Environment (all supplied by Buildroot's EXTRA_ENV, package/Makefile.in:362):
#   BUILD_DIR   genimage's scratch dir lives at $BUILD_DIR/genimage.tmp. If
#               unset, derived from BINARIES_DIR — see the assertion below for
#               why an EMPTY value must never reach genimage.sh.
#   BR2_CONFIG  read by genimage.sh only, for its optional bmaptool step.

set -eu

prog="post-image.sh(de25nano)"
board_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# board/mister/de25nano -> repo root is three levels up.
repo_root=$(CDPATH='' cd -- "$board_dir/../../.." && pwd)

genimage_cfg="$board_dir/genimage-sdcard.cfg"
checker="$repo_root/scripts/check-sdcard-de25.sh"

# ---------------------------------------------------------------------------
# The names. Changing one here means changing it in genimage-sdcard.cfg too —
# which is why check_cfg_mentions() below refuses to run if they drift apart.
# ---------------------------------------------------------------------------
FIT_NAME=u-boot.itb                          # SPL_FS_LOAD_PAYLOAD_NAME, boot-chain §8.3
KERNEL_NAME=Image                            # BR2_LINUX_KERNEL_IMAGE=y (uncompressed)
DTB_NAME=socfpga_agilex5_de25nano.dtb        # BR2_LINUX_KERNEL_CUSTOM_DTS_PATH basename
ROOTFS_NAME=rootfs.ext4                      # BR2_TARGET_ROOTFS_EXT2 + _EXT2_4
SDCARD_NAME="sdcard-de25.img"                # the `image` section in the cfg

# Kernel command line, and the two halves of it that can silently produce a
# board that looks dead:
#
#   root=/dev/mmcblk0p2  — the INTERIM p2 decision. ADR 0029 D3 fixes the
#     partition count and p1's FAT type ONLY; p2's filesystem is still an open
#     owner decision (implementation-path §6.3, §8 Q7). For this developer-OS
#     card p2 is the ext4 rootfs written verbatim and mounted directly: no
#     loop-mounted linux.img, no initramfs. See docs/de25-sdcard.md.
#
#   console=ttyS0,115200 — the DE25-Nano's header UART is HPS **uart1**
#     (serial@10c02100), aliased serial0 with stdout-path "serial0:115200n8" in
#     board/mister/de25nano/socfpga_agilex5_de25nano.dts. It is the only
#     enabled 8250 port, so it is ttyS0 under any 8250 numbering rule. uart0 is
#     the SoC Development Kit's console and is a different board.
#     `earlycon` (no argument) picks the port up from stdout-path.
ROOT_DEV=/dev/mmcblk0p2
CONSOLE_ARG=ttyS0,115200
BOOTARGS="root=$ROOT_DEV rw rootwait console=$CONSOLE_ARG earlycon"

die() {
	echo "$prog: FATAL: $*" >&2
	exit 1
}

note() { printf '%s: %s\n' "$prog" "$*"; }

[ $# -ge 1 ] || die "usage: $prog BINARIES_DIR"
binaries_dir=$1
[ -d "$binaries_dir" ] || die "BINARIES_DIR '$binaries_dir' is not a directory"
binaries_dir=$(CDPATH='' cd -- "$binaries_dir" && pwd)

[ -f "$genimage_cfg" ] || die "genimage config not found: $genimage_cfg"
[ -x "$checker" ] || die "checker not found or not executable: $checker"

# --- the cfg and this script must agree on every file name -------------------
# Cheap, and it catches the one class of drift that would otherwise surface as
# a genimage "file not found" three steps later, or worse as a card missing a
# file nobody notices until it does not boot.
check_cfg_mentions() {
	grep -q -- "$1" "$genimage_cfg" ||
		die "genimage-sdcard.cfg does not mention '$1' — this script and that config have drifted apart; fix both in the same commit"
}
for _n in "$FIT_NAME" "$KERNEL_NAME" "$DTB_NAME" "$ROOTFS_NAME" "$SDCARD_NAME"; do
	check_cfg_mentions "$_n"
done

# --- locate Buildroot's genimage wrapper -------------------------------------
# THE BUILDROOT WAY, and it is worth saying why rather than calling genimage
# directly: support/scripts/genimage.sh already handles the two things that are
# easy to get wrong by hand — it passes an EMPTY --rootpath (genimage copies
# the whole rootpath into its tmpdir, so handing it TARGET_DIR would waste
# minutes and gigabytes for an image type that never reads it), and it wipes
# GENIMAGE_TMP first, which genimage insists be empty.
#
# Normal case: cwd is the Buildroot source directory, so ./support/... resolves.
# The other two entries exist so this script is runnable stand-alone (the
# dry-run harness, and anyone re-assembling a card from an existing
# output-de25/ without a full rebuild).
genimage_sh=${DE25_GENIMAGE_SH:-}
if [ -z "$genimage_sh" ]; then
	for _c in "$PWD/support/scripts/genimage.sh" \
	          "$repo_root/work/buildroot/support/scripts/genimage.sh"; do
		if [ -x "$_c" ]; then
			genimage_sh=$_c
			break
		fi
	done
fi
[ -n "$genimage_sh" ] && [ -x "$genimage_sh" ] ||
	die "Buildroot's support/scripts/genimage.sh not found (cwd=$PWD); set \$DE25_GENIMAGE_SH"

# --- BUILD_DIR must be non-empty before genimage.sh sees it ------------------
# genimage.sh does `GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"` and then
# `rm -rf "${GENIMAGE_TMP}"` with no guard of its own. An empty BUILD_DIR turns
# that into an rm -rf on an absolute path at the filesystem root. Buildroot
# always exports it (package/Makefile.in:362); this derives Buildroot's own
# layout ($(BASE_DIR)/build beside $(BASE_DIR)/images) when it is absent, and
# refuses to continue if the result is still empty.
if [ -z "${BUILD_DIR:-}" ]; then
	BUILD_DIR=$(CDPATH='' cd -- "$binaries_dir/.." && pwd)/build
	note "BUILD_DIR was unset; using $BUILD_DIR"
fi
[ -n "$BUILD_DIR" ] || die "BUILD_DIR is empty — refusing to hand that to genimage.sh"
mkdir -p "$BUILD_DIR"
export BUILD_DIR
export BINARIES_DIR="$binaries_dir"

# =============================================================================
# 1. Inputs
# =============================================================================
# Every missing input is reported, not just the first: someone whose build is
# missing both the kernel and the rootfs should learn that in one run.
missing=""
for _f in "$KERNEL_NAME" "$DTB_NAME" "$ROOTFS_NAME"; do
	[ -f "$binaries_dir/$_f" ] || missing="$missing $_f"
done
if [ -n "$missing" ]; then
	echo "$prog: FATAL: missing from $binaries_dir:$missing" >&2
	echo "$prog:   $KERNEL_NAME     <- BR2_LINUX_KERNEL_IMAGE=y" >&2
	echo "$prog:   $DTB_NAME        <- BR2_LINUX_KERNEL_CUSTOM_DTS_PATH" >&2
	echo "$prog:   $ROOTFS_NAME     <- BR2_TARGET_ROOTFS_EXT2 + BR2_TARGET_ROOTFS_EXT2_4" >&2
	exit 1
fi

if [ ! -f "$binaries_dir/$FIT_NAME" ]; then
	if [ "${DE25_ALLOW_NO_UBOOT:-0}" = 1 ]; then
		note "WARNING: no $FIT_NAME in $binaries_dir, and DE25_ALLOW_NO_UBOOT=1 —"
		note "WARNING: SKIPPING $SDCARD_NAME. The kernel and rootfs are built; there"
		note "WARNING: is NO SD-card image, and nothing produced by this build can boot"
		note "WARNING: a DE25-Nano. Unset DE25_ALLOW_NO_UBOOT to make this a hard error."
		# A card from an EARLIER run must not survive this one: the de25 recipe
		# reports whatever sdcard-de25.img it finds, and a stale image would make
		# the skip above a lie. Remove the card and its p1 filesystem image.
		rm -f "$binaries_dir/$SDCARD_NAME" "$binaries_dir/boot-de25.vfat"
		exit 0
	fi
	die "no $FIT_NAME in $binaries_dir.
       The factory SPL loads that FIT by name from p1 and nothing else will do
       (docs/de25-boot-chain.md §2 step 4, §8.3), so a card without it cannot
       boot. It comes from BR2_TARGET_UBOOT + BR2_TARGET_ARM_TRUSTED_FIRMWARE
       in configs/fragments/de25nano.fragment (docs/buildroot-config.md §6.9),
       so a missing FIT means that stanza did not build.
       To build the kernel and rootfs anyway and skip the card, re-run with
       DE25_ALLOW_NO_UBOOT=1."
fi

note "inputs in $binaries_dir:"
for _f in "$FIT_NAME" "$KERNEL_NAME" "$DTB_NAME" "$ROOTFS_NAME"; do
	printf '  %-32s %s bytes\n' "$_f" "$(wc -c <"$binaries_dir/$_f" | tr -d ' ')"
done

# =============================================================================
# 2. Stage the FAT payload's one generated file: extlinux/extlinux.conf
# =============================================================================
# genimage's vfat handler copies the `extlinux` DIRECTORY out of --inputpath
# (= BINARIES_DIR) recursively, so this is where it has to land. Written to a
# temp file and renamed, so an interrupted run never leaves a half-written
# boot configuration for the next one to package.
extlinux_dir="$binaries_dir/extlinux"
extlinux_conf="$extlinux_dir/extlinux.conf"
mkdir -p "$extlinux_dir"
tmp_conf="$extlinux_conf.tmp.$$"
trap 'rm -f "$tmp_conf"' EXIT

cat > "$tmp_conf" <<EOF
# extlinux.conf — MiSTer DE25-Nano developer OS.
#
# GENERATED by board/mister/de25nano/post-image.sh. Every value here is a
# variable in that script; editing this file on the card is a debugging move,
# not a fix, and the next image build overwrites it.
#
# Read by U-Boot PROPER (its extlinux bootmeth / distro sysboot path), never by
# the factory SPL — the SPL's only interest in this partition is $FIT_NAME
# (docs/de25-boot-chain.md §2 step 4). Paths below are absolute within this
# same FAT partition.
#
# Nothing here may reference the board's QSPI flash, by any spelling: no
# flash-probe command, no flash-volume or raw-flash device name. A QSPI write
# is brick-class on this board, with JTAG-and-a-PC recovery and no RSU safety
# net (docs/de25-boot-chain.md §6, §7 rows 1/5/10/11/12).
# scripts/check-sdcard-de25.sh greps this file for the three spellings and
# fails the build on any hit — which is also why this notice does not spell
# them out.

# Tenths of a second. One entry, so this only ever costs a second of boot.
timeout 10
default de25

label de25
	menu label MiSTer DE25-Nano developer OS
	kernel /$KERNEL_NAME
	fdt /$DTB_NAME
	append $BOOTARGS
EOF

mv "$tmp_conf" "$extlinux_conf"
trap - EXIT
note "wrote $extlinux_conf"
sed 's/^/  | /' "$extlinux_conf"

# =============================================================================
# 3. Assemble
# =============================================================================
note "running $genimage_sh -c $genimage_cfg"
"$genimage_sh" -c "$genimage_cfg" || die "genimage failed assembling $SDCARD_NAME"

sdcard="$binaries_dir/$SDCARD_NAME"
[ -f "$sdcard" ] ||
	die "genimage reported success but produced no $sdcard"
note "wrote $sdcard ($(wc -c <"$sdcard" | tr -d ' ') bytes)"

# =============================================================================
# 4. The one and only contract check
# =============================================================================
"$checker" "$sdcard"
