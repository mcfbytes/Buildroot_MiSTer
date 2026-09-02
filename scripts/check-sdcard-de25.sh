#!/bin/sh
#
# check-sdcard-de25.sh — static verification of a built `sdcard-de25.img`
# (D2.4). No hardware, no boot: everything below is asserted from the raw image
# file alone, the same posture as check-sdcard.sh / check-linux-img.sh /
# check-zimage-dtb.sh.
#
# THIS IS NOT scripts/check-sdcard.sh WITH DIFFERENT CONSTANTS, and it must
# never be refactored into one. That script asserts the Cyclone V BootROM's
# contract: MBR p1 = FAT32, MBR p2 = type 0xA2 whose raw head is a byte-exact
# `uboot.img`. On Agilex 5 that mechanism does not exist — the SDM boots the
# FSBL out of QSPI and the FSBL reads a FILESYSTEM ("No 0xA2 analogue [V]",
# docs/de25-boot-chain.md §2). The two checkers assert opposite things about
# partition 2 on purpose; see docs/de25-readiness-ledger.md coupling (b), which
# says in as many words: write a sibling checker for the Agilex layout instead
# of relaxing the DE10 constants.
#
# The assertions, and why each one exists:
#
#  1. PARTITION TABLE IS MBR, WITH EXACTLY TWO PARTITIONS, AND NO 0xA2.
#     MBR because that is the only partition-table type any evidence says a
#     DE25-Nano has been seen booting from (board/mister/de25nano/
#     genimage-sdcard.cfg's `partition-table-type` note has the full argument
#     and its two citations). Exactly two, because ADR 0029 D3 fixes the
#     partition COUNT — a third partition means somebody re-opened a settled
#     decision without saying so. No 0xA2, because a 0xA2 partition here is
#     DE10 lore transplanted onto a board whose BootROM does not scan for it:
#     harmless in itself, and a reliable sign that the DE10's genimage config
#     or its `updateboot` habits are being cargo-culted across.
#
#  2. p1 IS FAT32, LABELLED, AND HOLDS THE FOUR FILES THE BOOT CHAIN NEEDS.
#     `u-boot.itb` is the whole interface between this card and the board's
#     boot firmware: the factory SPL loads it BY NAME from a FAT filesystem on
#     partition 1 (CONFIG_SPL_FS_FAT=y, SYS_MMCSD_FS_BOOT_PARTITION=1,
#     docs/de25-boot-chain.md §2 step 4 / §8.3). `Image`, the DTB and
#     `extlinux/extlinux.conf` are what U-Boot proper then needs. FAT32
#     specifically — not FAT16 — because the partition-type byte says 0x0c and
#     a type byte that lies about its filesystem is how a card boots on one
#     reader and not another.
#
#     p1 IS AN ALLOW-LIST, NOT A REQUIRED-SET: anything beyond those four
#     entries fails the image. U-Boot's distro boot runs `scan_dev_for_scripts`
#     immediately after `scan_dev_for_extlinux` on the SAME partition, so a
#     stray `/boot.scr` is not decoration — it executes the moment extlinux
#     fails, before any prompt, with the whole U-Boot command set available. A
#     `uboot.env` is refused for a different reason: the card deliberately
#     ships none (docs/de25-uboot.md §10), and a seeded one would override the
#     compiled-in environment on every already-written card, forever.
#
#  3. u-boot.itb IS THE FIT THIS BUILD PRODUCED, AND ONE THE FACTORY SPL CAN
#     ACTUALLY EXECUTE. Three assertions, because the file being present under
#     the right name proves nothing about what is inside it: (a) byte-identical
#     to the build's own `u-boot.itb`; (b) `dumpimage -l` shows the
#     de25-uboot.md §6.1 contract — images `uboot` (load 0x80200000), `atf`
#     (load 0x80000000), `fdt-0`, and a default configuration signed `crc32`;
#     (c) the decompiled FIT declares no `rsa`/`required`/`sha<n>`
#     verification. (c) matters most and is the least obvious: the factory SPL
#     is built with `CONFIG_SPL_FIT_SIGNATURE=y` and its control DTB carries NO
#     KEYS (boot-chain §7 row 6, §8.3), so a FIT demanding key verification
#     strands the board at SPL on EVERY boot — which, with no serial console
#     attached, is indistinguishable from a bad card.
#
#  4. extlinux.conf PARSES, NAMES THE RIGHT ROOT DEVICE AND CONSOLE, AND
#     MENTIONS NO FLASH. `root=/dev/mmcblk0p2` is the interim p2 decision
#     (docs/de25-sdcard.md); `console=ttyS0,115200` is HPS uart1, the only
#     enabled 8250 port on this board, and getting it wrong produces a board
#     that looks dead rather than one that prints an error. The `sf probe` /
#     `ubi` / `mtd` grep is the paper-thin but real enforcement of "nothing on
#     this card references QSPI": a QSPI write on this board is brick-class,
#     recoverable only with JTAG and a PC, with no RSU safety net
#     (docs/de25-boot-chain.md §6, §7 rows 1/5/10/11/12).
#
#  5. p2 IS A CLEAN ext4 LABELLED `rootfs`. Written verbatim from Buildroot's
#     rootfs.ext4 (BR2_TARGET_ROOTFS_EXT2 + _EXT2_4). `e2fsck -fn` is the cheap
#     proof that the bytes genimage copied are a filesystem and not a truncated
#     one; the `extent` feature is what distinguishes an actual ext4 from an
#     ext2 image that merely got named .ext4.
#
#  6. THE IMAGE FITS A BUDGET. p1 (256 MiB) + p2 (rootfs.ext4, 256 MiB today) +
#     1 MiB of alignment ≈ 513 MiB. $EXPECT_MAX_IMAGE_BYTES defaults to 768 MiB:
#     enough headroom that a modest rootfs bump does not trip it, tight enough
#     that a runaway one does. Raise it deliberately, in the commit that grows
#     the rootfs — never to make a red run go green.
#
# Usage:
#   scripts/check-sdcard-de25.sh <sdcard-de25.img> [reference-images-dir]
#
#   [reference-images-dir]  where the PRISTINE build artifacts live — the
#                           `u-boot.itb` that assertion 3a compares against.
#                           Defaults to $DE25_REF_DIR, then $BINARIES_DIR, then
#                           the image's own directory (Buildroot puts both in
#                           BINARIES_DIR), then <repo>/output-de25/images.
#
# Environment overrides (all optional; each is pinned, not derived, and must be
# kept in sync BY HAND with board/mister/de25nano/genimage-sdcard.cfg and
# board/mister/de25nano/post-image.sh — there is no source of truth to read
# them from at check time, the same caveat check-linux-img.sh's header gives):
#   $EXPECT_FAT_LABEL       default DE25BOOT
#   $EXPECT_ROOTFS_LABEL    default rootfs
#   $EXPECT_DTB_NAME        default socfpga_agilex5_de25nano.dtb
#   $EXPECT_ROOT_DEV        default /dev/mmcblk0p2
#   $EXPECT_CONSOLE         default ttyS0,115200
#   $EXPECT_MAX_IMAGE_BYTES default 805306368 (768 MiB)
#   $MIN_BOOT_PART_SECTORS  default 524288 (256 MiB)
#
# Host tools: sfdisk (util-linux), mtools (mdir/mcopy/mlabel), e2fsprogs
# (dumpe2fs/e2fsck), u-boot-tools (dumpimage), dtc, dd, cmp. Resolved from
# $DE25_HOST_DIR/{bin,sbin}, then BINARIES_DIR/../host/{bin,sbin}, then this
# repo's output-de25/host/{bin,sbin}, then PATH — so a Buildroot build that
# produced the image can always check it: BR2_PACKAGE_HOST_GENIMAGE pulls in
# host-mtools and host-dosfstools, BR2_TARGET_ROOTFS_EXT2 pulls in
# host-e2fsprogs, and BR2_TARGET_UBOOT's FIT support pulls in host-uboot-tools
# (dumpimage) and host-dtc. dumpimage is NOT a distro tool, which is exactly
# why the search list is longer than a bare PATH lookup: an unfindable
# dumpimage would leave assertion 3 unrunnable, and a checker that skips the
# FIT is how a card ships carrying a FIT nobody ever opened. A missing tool is
# exit 2, never a silent skip. Unlike check-sdcard.sh there is NO root
# loop-mount fallback — mtools has never been optional for anyone who can
# build this image.
#
# Exit: 0 = all assertions pass; 1 = a contract violation; 2 = usage/IO/tooling
# error.

set -eu

prog=${0##*/}
fail=0

# --- pinned layout contract --------------------------------------------------
BOOT_PART_NUM=1
BOOT_PART_TYPE=c              # 0x0c, FAT32 LBA -- genimage-sdcard.cfg
ROOTFS_PART_NUM=2
ROOTFS_PART_TYPE=83           # 0x83, Linux    -- genimage-sdcard.cfg
EXPECT_PART_COUNT=2           # ADR 0029 D3: two partitions, full stop
FORBIDDEN_PART_TYPE=a2        # the Cyclone V BootROM's type byte; alien here

: "${EXPECT_FAT_LABEL:=DE25BOOT}"
: "${EXPECT_ROOTFS_LABEL:=rootfs}"
: "${EXPECT_DTB_NAME:=socfpga_agilex5_de25nano.dtb}"
: "${EXPECT_ROOT_DEV:=/dev/mmcblk0p2}"
: "${EXPECT_CONSOLE:=ttyS0,115200}"
: "${EXPECT_MAX_IMAGE_BYTES:=805306368}"
: "${MIN_BOOT_PART_SECTORS:=524288}"

EXPECT_KERNEL_NAME=Image
EXPECT_FIT_NAME=u-boot.itb
EXTLINUX_PATH=extlinux/extlinux.conf

# Substrings that must not appear anywhere in extlinux.conf. Matched
# case-insensitively and as plain substrings, deliberately over-broad: there is
# no legitimate word containing "ubi" or "mtd" in a boot configuration for a
# board whose flash we are forbidden to touch.
QSPI_FORBIDDEN='sf probe
ubi
mtd'

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }

usage() {
	echo "usage: $prog <sdcard-de25.img> [reference-images-dir]" >&2
	exit 2
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
img=$1
ref_dir_arg=${2:-}
[ -f "$img" ] || { echo "$prog: no such file: $img" >&2; exit 2; }

img_dir=$(CDPATH='' cd -- "$(dirname -- "$img")" && pwd)
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

# --- where the PRISTINE build artifacts live (assertion 2a's reference) ------
# In a real build this is BINARIES_DIR, which is also where sdcard-de25.img
# itself lands -- so $img_dir is the right answer almost always. The explicit
# arg and $DE25_REF_DIR exist for checking an image that has been moved away
# from its build tree (a copy under test, a release artifact).
ref_dir=${ref_dir_arg:-${DE25_REF_DIR:-${BINARIES_DIR:-}}}
if [ -z "$ref_dir" ]; then
	if [ -f "$img_dir/$EXPECT_FIT_NAME" ]; then
		ref_dir=$img_dir
	else
		ref_dir="$repo_root/output-de25/images"
	fi
fi

# --- host tools -------------------------------------------------------------
# Searched in order: $DE25_HOST_DIR (an explicit Buildroot HOST_DIR), the one
# implied by the image's own location (BINARIES_DIR/../host, Buildroot's
# layout), this repo's output-de25/host, then PATH. dumpimage in particular is
# NOT a distro tool -- it comes from host-uboot-tools, which the DE25 build
# enables for exactly this purpose (docs/de25-uboot.md §10) -- so PATH alone
# would leave assertion 2b silently unrunnable, which is how a checker ends up
# passing a FIT it never opened.
tool_dirs="${DE25_HOST_DIR:+$DE25_HOST_DIR/bin $DE25_HOST_DIR/sbin} \
$img_dir/../host/bin $img_dir/../host/sbin \
$repo_root/output-de25/host/bin $repo_root/output-de25/host/sbin"

find_tool() {  # find_tool NAME -> absolute path, or exit 2
	for _d in $tool_dirs; do
		if [ -x "$_d/$1" ]; then
			echo "$_d/$1"
			return 0
		fi
	done
	if command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
		return 0
	fi
	echo "$prog: cannot find '$1' (looked in $tool_dirs and PATH)" >&2
	exit 2
}

sfdisk_bin=$(find_tool sfdisk)
mdir_bin=$(find_tool mdir)
mcopy_bin=$(find_tool mcopy)
mlabel_bin=$(find_tool mlabel)
dumpe2fs_bin=$(find_tool dumpe2fs)
e2fsck_bin=$(find_tool e2fsck)
dumpimage_bin=$(find_tool dumpimage)
dtc_bin=$(find_tool dtc)
command -v dd >/dev/null 2>&1 || { echo "$prog: dd not found on PATH" >&2; exit 2; }
command -v cmp >/dev/null 2>&1 || { echo "$prog: cmp not found on PATH" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/check-sdcard-de25.XXXXXX")
# shellcheck disable=SC2329 # invoked indirectly via `trap cleanup EXIT` below
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

img_bytes=$(wc -c <"$img" | tr -d ' ')
printf '%s: %s (%s bytes)\n' "$prog" "$img" "$img_bytes"

# =============================================================================
# 0. Size budget
# =============================================================================
if [ "$img_bytes" -le "$EXPECT_MAX_IMAGE_BYTES" ]; then
	ok "image size $img_bytes bytes <= \$EXPECT_MAX_IMAGE_BYTES ($EXPECT_MAX_IMAGE_BYTES)"
else
	bad "image size $img_bytes bytes EXCEEDS \$EXPECT_MAX_IMAGE_BYTES ($EXPECT_MAX_IMAGE_BYTES) -- raise the budget deliberately, in the commit that grew the card"
fi

# =============================================================================
# 1. Partition table: MBR, exactly two partitions, no 0xA2
# =============================================================================
dump=$("$sfdisk_bin" -d "$img" 2>/dev/null) ||
	{ echo "$prog: sfdisk -d failed on $img (not a partitioned image?)" >&2; exit 2; }

# sfdisk -d prints `label: dos` for MBR and `label: gpt` for GPT.
label_line=$(printf '%s\n' "$dump" | sed -n 's/^label:[[:space:]]*//p' | head -n1)
if [ "$label_line" = "dos" ]; then
	ok "partition table is MBR/dos (the only type a DE25-Nano has been observed booting from -- genimage-sdcard.cfg's partition-table-type note)"
else
	bad "partition table is '$label_line', expected 'dos' (MBR). GPT support in the FACTORY SPL is unproven, not disproven -- changing this needs a hardware retest, not a desk decision"
fi

# Independent of sfdisk's opinion: a real GPT (or a protective-MBR hybrid)
# carries the "EFI PART" signature at LBA 1. Checked separately so a
# hybrid/protective layout cannot pass by looking like plain dos above.
gpt_sig=$(dd if="$img" bs=1 skip=512 count=8 status=none 2>/dev/null | tr -d '\0' || true)
if [ "$gpt_sig" = "EFI PART" ]; then
	bad "a GPT header signature ('EFI PART') is present at LBA 1 -- this image is GPT or MBR/GPT hybrid"
else
	ok "no GPT header signature at LBA 1"
fi

# One "<name>N : start=..., size=..., type=..." line per MBR slot, in
# partition-table order, so the Nth match is unambiguously MBR partition N
# regardless of how sfdisk names the device from our image path.
part_lines=$(printf '%s\n' "$dump" | grep -E '^[^[:space:]]+[0-9]+[[:space:]]*:.*start=') || true
part_count=$(printf '%s\n' "$part_lines" | grep -c . || true)
note "sfdisk -d reports $part_count partition(s)"

if [ "$part_count" -eq "$EXPECT_PART_COUNT" ]; then
	ok "exactly $EXPECT_PART_COUNT partitions (ADR 0029 D3)"
else
	bad "$part_count partition(s), expected exactly $EXPECT_PART_COUNT (ADR 0029 D3 fixes the partition count)"
fi

field() {  # field LINE NAME -> value
	printf '%s\n' "$1" | sed -n "s/.*[[:space:]]$2=[[:space:]]*\\([^,[:space:]]*\\).*/\\1/p"
}
get_part() {  # get_part N -> the Nth partition-table line, or empty
	printf '%s\n' "$part_lines" | sed -n "${1}p"
}

a2_seen=0
_n=0
while [ "$_n" -lt "$part_count" ]; do
	_n=$(( _n + 1 ))
	_t=$(field "$(get_part "$_n")" type | tr 'A-F' 'a-f')
	[ "$_t" = "$FORBIDDEN_PART_TYPE" ] && a2_seen=1
done
if [ "$a2_seen" -eq 0 ]; then
	ok "no 0x$FORBIDDEN_PART_TYPE partition (there is no BootROM raw-partition scan on Agilex 5 -- boot-chain §2 'No 0xA2 analogue')"
else
	bad "a 0x$FORBIDDEN_PART_TYPE partition is present -- that is the Cyclone V BootROM's contract (docs/boot-chain.md §2.1) and it means nothing on this board. DE10 layout lore has been cargo-culted here"
fi

boot_line=$(get_part "$BOOT_PART_NUM")
rootfs_line=$(get_part "$ROOTFS_PART_NUM")

boot_start=""
if [ -z "$boot_line" ]; then
	bad "MBR partition $BOOT_PART_NUM (FAT boot) not found"
else
	boot_start=$(field "$boot_line" start)
	boot_size=$(field "$boot_line" size)
	boot_type=$(field "$boot_line" type | tr 'A-F' 'a-f')
	note "partition $BOOT_PART_NUM: start=$boot_start size=$boot_size(sectors) type=$boot_type"
	if [ "$boot_type" = "$BOOT_PART_TYPE" ]; then
		ok "partition $BOOT_PART_NUM type=0x$BOOT_PART_TYPE (FAT32 LBA) -- the partition SYS_MMCSD_FS_BOOT_PARTITION=1 makes the factory SPL read"
	else
		bad "partition $BOOT_PART_NUM type='$boot_type', expected '$BOOT_PART_TYPE' (0x0c FAT32 LBA)"
	fi
	if [ "$boot_size" -ge "$MIN_BOOT_PART_SECTORS" ]; then
		ok "partition $BOOT_PART_NUM size $boot_size sectors >= $MIN_BOOT_PART_SECTORS (256 MiB floor)"
	else
		bad "partition $BOOT_PART_NUM size $boot_size sectors < $MIN_BOOT_PART_SECTORS (256 MiB floor)"
	fi
fi

rootfs_start=""
rootfs_size=""
if [ -z "$rootfs_line" ]; then
	bad "MBR partition $ROOTFS_PART_NUM (ext4 rootfs) not found"
else
	rootfs_start=$(field "$rootfs_line" start)
	rootfs_size=$(field "$rootfs_line" size)
	rootfs_type=$(field "$rootfs_line" type | tr 'A-F' 'a-f')
	note "partition $ROOTFS_PART_NUM: start=$rootfs_start size=$rootfs_size(sectors) type=$rootfs_type"
	if [ "$rootfs_type" = "$ROOTFS_PART_TYPE" ]; then
		ok "partition $ROOTFS_PART_NUM type=0x$ROOTFS_PART_TYPE (Linux)"
	else
		bad "partition $ROOTFS_PART_NUM type='$rootfs_type', expected '$ROOTFS_PART_TYPE' (0x83 Linux)"
	fi
fi

# =============================================================================
# 2. p1: FAT32, labelled, and the four files
# =============================================================================
mt() {  # mt TOOL ARGS... -- run an mtools binary against p1 at its byte offset
	_tool=$1; shift
	MTOOLS_SKIP_CHECK=1 "$_tool" -i "${img}@@${boot_offset}" "$@"
}

if [ -z "$boot_start" ]; then
	bad "cannot inspect p1 -- partition $BOOT_PART_NUM was not found above"
else
	boot_offset=$(( boot_start * 512 ))

	# FAT width, read straight out of the BPB rather than trusted from the
	# partition-type byte: FAT32's filesystem-type string lives at offset 0x52
	# of the boot sector (FAT12/16 put theirs at 0x36 instead), so this is the
	# one place the image itself says which it is.
	fat_type=$(dd if="$img" bs=1 skip=$(( boot_offset + 82 )) count=8 status=none 2>/dev/null | tr -d '\0' || true)
	case $fat_type in
		FAT32*)
			ok "p1 filesystem is FAT32 (BPB fs-type = '$fat_type'), matching its 0x0c type byte"
			;;
		*)
			bad "p1 BPB fs-type at offset 0x52 is '$fat_type', not FAT32 -- mkfs.vfat picks FAT16 at this size unless '-F 32' is forced (genimage-sdcard.cfg extraargs)"
			;;
	esac

	if mt "$mlabel_bin" -s :: > "$work/mlabel.out" 2> "$work/mlabel.err"; then
		# mlabel prints " Volume label is DE25BOOT   " -- note the LEADING
		# space and the FAT 11-character padding on the right. Both are
		# stripped here; anchoring on a bare "^Volume" silently never matches.
		fat_label=$(sed -n 's/^[[:space:]]*Volume label is[[:space:]]*//p' "$work/mlabel.out" \
			| head -n1 | sed 's/[[:space:]]*$//')
		if [ "$fat_label" = "$EXPECT_FAT_LABEL" ]; then
			ok "p1 volume label = '$EXPECT_FAT_LABEL'"
		else
			bad "p1 volume label = '${fat_label:-<none>}', expected '$EXPECT_FAT_LABEL'"
		fi
	else
		bad "could not read p1's volume label (mlabel failed)"
		sed 's/^/    /' "$work/mlabel.err" >&2
	fi

	actual="$work/p1-inventory.txt"
	if mt "$mdir_bin" -b -/ :: > "$work/mdir.out" 2> "$work/mdir.err"; then
		tr -d '\r' < "$work/mdir.out" \
			| sed -e 's#^::##' -e 's#^/##' -e '/^$/d' \
			| LC_ALL=C sort -u > "$actual"
		note "p1 holds $(wc -l < "$actual" | tr -d ' ') entries"
		for want in "$EXPECT_FIT_NAME" "$EXPECT_KERNEL_NAME" "$EXPECT_DTB_NAME" "$EXTLINUX_PATH"; do
			if grep -qxF "$want" "$actual"; then
				ok "p1 holds $want"
			else
				bad "p1 is MISSING $want"
			fi
		done
		# p1 IS AN ALLOW-LIST, NOT A REQUIRED-SET. Anything not on the list
		# below fails the image, and this is the assertion with the sharpest
		# teeth on the card.
		#
		# Why extras cannot be "informational": U-Boot's distro boot runs
		# `scan_dev_for_scripts` IMMEDIATELY AFTER `scan_dev_for_extlinux` on
		# the same partition. So a stray `/boot.scr` is not inert decoration
		# -- it is code that executes the moment extlinux fails for any
		# reason, before anyone gets a prompt, with the full U-Boot command
		# set available to it. A `boot.scr` containing a flash-erase command
		# is a brick-class payload that this checker used to wave through.
		#
		# `uboot.env` is on the list of named offenders for a different
		# reason: the card DELIBERATELY ships no environment file
		# (docs/de25-uboot.md §10). A seeded one silently OVERRIDES the
		# compiled-in environment forever after, so the next release's
		# bootcmd/bootargs/boot_targets change would be ignored on every
		# already-written card. Its appearance means somebody re-opened that
		# decision without saying so.
		#
		# When p1 legitimately grows a file -- a core.rbf, say -- add it here
		# and to genimage-sdcard.cfg's `files` list in the same commit. That
		# is the point: growing the card is a decision, not an accident.
		extras=$(grep -vxF -e "$EXPECT_FIT_NAME" -e "$EXPECT_KERNEL_NAME" \
			-e "$EXPECT_DTB_NAME" -e "$EXTLINUX_PATH" -e 'extlinux/' "$actual" || true)
		if [ -z "$extras" ]; then
			ok "p1 holds nothing beyond the four expected files (no boot.scr, no *.scr, no uboot.env)"
		else
			bad "p1 holds entries outside the allow-list -- p1 is an allow-list, not a required-set:"
			printf '%s\n' "$extras" | sed 's/^/    + /' >&2
			note "A stray boot.scr / *.scr EXECUTES: distro boot runs scan_dev_for_scripts"
			note "  right after scan_dev_for_extlinux on this same partition, so it runs the"
			note "  moment extlinux fails -- with the whole U-Boot command set available."
			note "A uboot.env must not ship either: the card deliberately has none"
			note "  (docs/de25-uboot.md §10); a seeded one overrides the compiled-in"
			note "  environment on every already-written card, forever."
			note "If p1 is meant to grow a file, add it to this allow-list AND to"
			note "  genimage-sdcard.cfg's files list in the same commit."
		fi
	else
		bad "could not read p1's file inventory (mdir failed -- is p1 a FAT filesystem at all?)"
		sed 's/^/    /' "$work/mdir.err" >&2
		: > "$actual"
	fi

	# ---------------------------------------------------------------------
	# 3. u-boot.itb -- the file the factory SPL actually executes
	# ---------------------------------------------------------------------
	# Three independent assertions, because each of the first two can be
	# satisfied by something that still does not boot:
	#
	#  (a) byte-identical to the build's own u-boot.itb. Catches a swapped,
	#      truncated or hand-edited FIT outright.
	#  (b) dumpimage -l: the contract terms from docs/de25-uboot.md §6.1 --
	#      images `uboot` (load 0x80200000), `atf` (load 0x80000000) and
	#      `fdt-0`, plus a default configuration whose signature algo is
	#      crc32. A FIT that parses but loads U-Boot at the wrong address is
	#      a silent no-boot.
	#  (c) NO key-based verification anywhere. The factory SPL is built with
	#      CONFIG_SPL_FIT_SIGNATURE=y and its control DTB carries NO KEYS
	#      (docs/de25-boot-chain.md §7 row 6, §8.3), so a FIT that DEMANDS a
	#      verification the SPL cannot perform strands the board at SPL on
	#      every boot -- and without a serial console that is
	#      indistinguishable from a bad card. Grepping the decompiled FIT for
	#      rsa/required/sha<n> is cruder than parsing it, deliberately: it
	#      catches the property in any spelling, on images as well as on
	#      configurations, including nodes dumpimage does not summarise.
	itb="$work/u-boot.itb"
	if mt "$mcopy_bin" "::/$EXPECT_FIT_NAME" "$itb" > "$work/mcopy-itb.out" 2> "$work/mcopy-itb.err"; then

		# (a) -------------------------------------------------------------
		ref_itb="$ref_dir/$EXPECT_FIT_NAME"
		if [ -f "$ref_itb" ]; then
			if cmp -s "$itb" "$ref_itb"; then
				ok "p1's $EXPECT_FIT_NAME is byte-identical to $ref_itb"
			else
				bad "p1's $EXPECT_FIT_NAME DIFFERS from $ref_itb -- the card carries a FIT this build did not produce"
			fi
		else
			bad "no reference $EXPECT_FIT_NAME at $ref_itb -- cannot prove the card's FIT is the one this build produced (pass the images dir as argument 2, or set \$DE25_REF_DIR)"
		fi

		# (b) -------------------------------------------------------------
		if "$dumpimage_bin" -l "$itb" > "$work/dumpimage.out" 2> "$work/dumpimage.err"; then
			di="$work/dumpimage.out"

			check_fit_image() {  # check_fit_image NAME EXPECTED_LOAD
				if ! grep -qE "^ Image [0-9]+ \($1\)\$" "$di"; then
					bad "$EXPECT_FIT_NAME has no image named '$1' (factory-SPL FIT contract, de25-uboot.md §6.1)"
					return
				fi
				_load=$(awk -v n="$1" '
					$0 ~ "^ Image [0-9]+ \\(" n "\\)$" { inb = 1; next }
					inb && /^ (Image|Default|Configuration)/ { inb = 0 }
					inb && /Load Address:/ { print $3; exit }' "$di")
				if [ "$_load" = "$2" ]; then
					ok "$EXPECT_FIT_NAME image '$1' loads at $2"
				else
					bad "$EXPECT_FIT_NAME image '$1' loads at '${_load:-<none>}', expected $2"
				fi
			}

			check_fit_image uboot 0x80200000
			check_fit_image atf 0x80000000

			if grep -qE '^ Image [0-9]+ \(fdt-0\)$' "$di"; then
				ok "$EXPECT_FIT_NAME has the 'fdt-0' image"
			else
				bad "$EXPECT_FIT_NAME has no 'fdt-0' image"
			fi

			def_cfg=$(sed -n "s/^ Default Configuration: '\\(.*\\)'\$/\\1/p" "$di" | head -n1)
			if [ -n "$def_cfg" ]; then
				ok "$EXPECT_FIT_NAME names a default configuration: '$def_cfg'"
			else
				bad "$EXPECT_FIT_NAME names no default configuration -- board_fit_config_name_match() falls back to /configurations/default, and there would be none"
			fi

			sign_algo=$(sed -n 's/^  Sign algo:[[:space:]]*//p' "$di" | head -n1)
			case $sign_algo in
				crc32*)
					ok "$EXPECT_FIT_NAME signature algo is crc32 ('$sign_algo') -- an integrity stamp, no keys" ;;
				'')
					bad "$EXPECT_FIT_NAME's default configuration carries no signature node at all (expected a crc32 integrity stamp)" ;;
				*)
					bad "$EXPECT_FIT_NAME signature algo is '$sign_algo', expected crc32 -- the factory SPL has FIT_SIGNATURE on with NO keys, so anything else is a card that strands at SPL on every boot" ;;
			esac
		else
			bad "dumpimage -l could not parse p1's $EXPECT_FIT_NAME -- it is not a FIT image"
			sed 's/^/    /' "$work/dumpimage.err" >&2
		fi

		# (c) -------------------------------------------------------------
		if "$dtc_bin" -I dtb -O dts -o "$work/itb.dts" "$itb" >/dev/null 2>&1; then
			if key_hits=$(grep -inE 'rsa|required|sha[0-9]' "$work/itb.dts"); then
				bad "$EXPECT_FIT_NAME declares key-based verification -- the factory SPL has no keys and would refuse to boot it:"
				printf '%s\n' "$key_hits" | sed 's/^/    /' >&2
			else
				ok "$EXPECT_FIT_NAME declares no rsa/required/sha<n> verification"
			fi
		else
			bad "dtc could not decompile p1's $EXPECT_FIT_NAME as a device tree -- a FIT *is* a DTB, so this is not one"
		fi
	else
		bad "could not read $EXPECT_FIT_NAME from p1"
		sed 's/^/    /' "$work/mcopy-itb.err" >&2
	fi

	# ---------------------------------------------------------------------
	# 4. extlinux.conf
	# ---------------------------------------------------------------------
	conf="$work/extlinux.conf"
	if mt "$mcopy_bin" "::/$EXTLINUX_PATH" "$conf" > "$work/mcopy.out" 2> "$work/mcopy.err"; then
		conf_body=$(tr -d '\r' < "$conf" | sed -e 's/^[[:space:]]*//' -e '/^#/d' -e '/^$/d')

		default_label=$(printf '%s\n' "$conf_body" | sed -n 's/^default[[:space:]]\{1,\}//p' | head -n1)
		if [ -n "$default_label" ]; then
			ok "extlinux.conf names a default entry: '$default_label'"
			if printf '%s\n' "$conf_body" | grep -qE "^label[[:space:]]+$default_label\$"; then
				ok "extlinux.conf has a matching 'label $default_label' block"
			else
				bad "extlinux.conf's 'default $default_label' names a label that does not exist -- U-Boot would find no entry to boot"
			fi
		else
			bad "extlinux.conf has no 'default' directive"
		fi

		for key in kernel fdt append; do
			if printf '%s\n' "$conf_body" | grep -qE "^${key}[[:space:]]"; then
				ok "extlinux.conf has a '$key' directive"
			else
				bad "extlinux.conf has no '$key' directive"
			fi
		done

		# The kernel and DTB it names must actually be on this partition.
		for key in kernel fdt; do
			val=$(printf '%s\n' "$conf_body" | sed -n "s/^${key}[[:space:]]\{1,\}//p" | head -n1)
			rel=${val#/}
			if [ -z "$rel" ]; then
				continue
			elif grep -qxF "$rel" "$actual"; then
				ok "extlinux.conf's $key '$val' exists on p1"
			else
				bad "extlinux.conf's $key '$val' is NOT on p1 -- U-Boot would abort mid-boot"
			fi
		done

		append=$(printf '%s\n' "$conf_body" | sed -n 's/^append[[:space:]]\{1,\}//p' | head -n1)
		note "append = $append"
		case " $append " in
			*" root=$EXPECT_ROOT_DEV "*)
				ok "kernel args name root=$EXPECT_ROOT_DEV (the interim p2 decision -- docs/de25-sdcard.md)" ;;
			*)  bad "kernel args do not name root=$EXPECT_ROOT_DEV" ;;
		esac
		case " $append " in
			*" console=$EXPECT_CONSOLE "*)
				ok "kernel args name console=$EXPECT_CONSOLE (HPS uart1, the board's header UART)" ;;
			*)  bad "kernel args do not name console=$EXPECT_CONSOLE -- a wrong console makes the board look dead rather than print an error" ;;
		esac
		case " $append " in
			*" rootwait "*) ok "kernel args include rootwait (the SD controller probes asynchronously)" ;;
			*) bad "kernel args do not include rootwait -- the root device may not exist yet when the kernel looks for it" ;;
		esac

		# The QSPI grep. Over-broad on purpose; see QSPI_FORBIDDEN above.
		# Iterated with IFS=newline rather than through a pipe, so the hits
		# file is written by THIS shell and not by a subshell whose variables
		# would evaporate.
		hits="$work/qspi-hits.txt"
		: > "$hits"
		_oldifs=$IFS
		IFS='
'
		for pat in $QSPI_FORBIDDEN; do
			if grep -qiF -- "$pat" "$conf"; then
				printf '%s\n' "$pat" >> "$hits"
			fi
		done
		IFS=$_oldifs
		if [ ! -s "$hits" ]; then
			ok "extlinux.conf mentions none of: sf probe / ubi / mtd (nothing on this card references QSPI)"
		else
			bad "extlinux.conf mentions QSPI-flash machinery: $(tr '\n' ' ' < "$hits")"
			note "a QSPI write on this board is brick-class with JTAG-and-a-PC recovery and no RSU (boot-chain §6, §7 rows 1/5/10/11/12)"
		fi
	else
		bad "could not read $EXTLINUX_PATH from p1"
		sed 's/^/    /' "$work/mcopy.err" >&2
	fi
fi

# =============================================================================
# 5. p2: a clean ext4 labelled `rootfs`
# =============================================================================
if [ -z "$rootfs_start" ]; then
	bad "cannot inspect p2 -- partition $ROOTFS_PART_NUM was not found above"
else
	p2="$work/p2.img"
	# conv=sparse keeps this cheap: a Buildroot rootfs.ext4 is mostly holes.
	dd if="$img" of="$p2" bs=512 skip="$rootfs_start" count="$rootfs_size" \
		conv=sparse status=none 2>/dev/null ||
		{ echo "$prog: dd failed extracting partition $ROOTFS_PART_NUM" >&2; exit 2; }

	if hdr=$("$dumpe2fs_bin" -h "$p2" 2>/dev/null); then
		ok "p2 is an ext2/3/4 filesystem (dumpe2fs -h succeeded)"

		p2_label=$(printf '%s\n' "$hdr" | sed -n 's/^Filesystem volume name:[[:space:]]*//p')
		if [ "$p2_label" = "$EXPECT_ROOTFS_LABEL" ]; then
			ok "p2 volume label = '$EXPECT_ROOTFS_LABEL'"
		else
			bad "p2 volume label = '$p2_label', expected '$EXPECT_ROOTFS_LABEL' (BR2_TARGET_ROOTFS_EXT2_LABEL)"
		fi

		features=$(printf '%s\n' "$hdr" | sed -n 's/^Filesystem features:[[:space:]]*//p')
		note "p2 features: $features"
		case " $features " in
			*" extent "*)
				ok "p2 has the 'extent' feature -- it is a real ext4, not an ext2 image wearing the name" ;;
			*)  bad "p2 lacks the 'extent' feature -- BR2_TARGET_ROOTFS_EXT2_4 selects ext4, and this is not one" ;;
		esac

		if "$e2fsck_bin" -fn "$p2" > "$work/e2fsck.out" 2>&1; then
			ok "p2 is fsck-clean (e2fsck -fn)"
		else
			bad "e2fsck -fn found problems on p2 (exit $?) -- the partition may be truncated"
			sed 's/^/    /' "$work/e2fsck.out" >&2
		fi
	else
		bad "p2 is not an ext2/3/4 filesystem (dumpe2fs -h failed)"
	fi
fi

# =============================================================================
if [ "$fail" -eq 0 ]; then
	echo "$prog: all assertions passed"
else
	echo "$prog: CONTRACT VIOLATED" >&2
fi
exit "$fail"
