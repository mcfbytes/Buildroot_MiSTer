#!/usr/bin/env bash
#
# mk-sdcard.sh -- assemble the dd/Etcher-writable SD-card installer image from a finished
# `make all` (ADR 0020, ADR 0033). Pure assembly: no Buildroot build, no kernel relink.
#
#   scripts/mk-sdcard.sh                  # -> output/images/sdcard.img(.xz)
#   SDCARD_CORES=1 scripts/mk-sdcard.sh   # -> output/images/sdcard-full.img(.xz)
#
# The card boots the SAME zImage_dtb Downloader users get; its stage-1 /init runs the
# installer only because genimage puts the installer flag on this image (p3 + LBA 1024).
# Step by step, and why: docs/installer-build.md.
#
# Host tools: genimage, mtools, dosfstools, xz-utils, gzip, cmp, cpio. They never enter the image.

set -o errexit
set -o nounset
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly OUTPUT_DIR="$REPO_ROOT/output"

# --- inputs: everything comes from `make all` ---------------------------------
readonly OUR_LINUX_IMG="$OUTPUT_DIR/images/linux.img"
readonly OUR_ZIMAGE_DTB="$OUTPUT_DIR/images/zImage_dtb"
readonly OUR_PAYLOAD_7ZA="$OUTPUT_DIR/images/7za"                # ADR 0023
readonly OUR_INITRAMFS="$OUTPUT_DIR/images/mister-initramfs.cpio"
readonly OUR_FLAG="$OUTPUT_DIR/images/mister-install-flag.bin"   # package/mister-initramfs
# The flag as /init will compare it: taken from the embedded cpio, not trusted from images/.
readonly CPIO_FLAG_BIN="usr/lib/mister/install-flag.bin"
readonly CPIO_FLAG_CONF="usr/lib/mister/install-flag.conf"
readonly GENIMAGE_CFG="$REPO_ROOT/board/mister/de10nano/genimage-sdcard.cfg"

# --- staging + assembly scratch ---------------------------------------------
# STAGE_DIR is fetch-sdcard-payload.sh's default too, so its .fetch-cache/ stays warm.
STAGE_DIR="${STAGE_DIR:-$REPO_ROOT/output-sdcard-stage}"
readonly STAGE_DIR
readonly PAYLOAD_DIR="$STAGE_DIR/mister-payload"
readonly FATROOT_LINUX_DIR="$STAGE_DIR/linux"
readonly FATROOT_MENU_RBF="$STAGE_DIR/menu.rbf"
readonly PAYLOAD_MENU_RBF="$PAYLOAD_DIR/menu.rbf"

readonly BUILD_DIR="$REPO_ROOT/output-sdcard-build"
readonly GENIMAGE_INPUTS="$BUILD_DIR/inputs"
readonly GENIMAGE_TMP="$BUILD_DIR/genimage.tmp"
readonly GENIMAGE_ROOT="$BUILD_DIR/empty-root"
readonly GENIMAGE_OUT="$BUILD_DIR/out"
# The input names genimage-sdcard.cfg hard-codes (keep in sync with it).
readonly VFAT_IMAGE_NAME="sdcard-payload.vfat"
readonly UBOOT_INPUT_NAME="uboot.img"
readonly FLAG_INPUT_NAME="install-flag.bin"
readonly GENIMAGE_IMAGE_NAME="sdcard.img"
readonly FAT_LABEL="MISTER"   # cosmetic; U-Boot and the installer go by partition number

SDCARD_CORES="${SDCARD_CORES:-0}"
readonly SDCARD_CORES
if [ "$SDCARD_CORES" = "1" ]; then
	readonly FINAL_IMG="$OUTPUT_DIR/images/sdcard-full.img"
else
	readonly FINAL_IMG="$OUTPUT_DIR/images/sdcard.img"
fi

log() { printf 'mk-sdcard: %s\n' "$*"; }
err() { printf 'mk-sdcard: ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

require_host_tools() {
	local missing="" t
	for t in du awk stat gzip cmp cpio od mkfs.vfat mcopy xz; do
		command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
	done
	if [ -n "$missing" ]; then
		err "missing required host tool(s):$missing"
		err "e.g.: sudo apt-get install genimage mtools dosfstools xz-utils"
		exit 1
	fi
}

# Prefer Buildroot's own host genimage, else the PATH one.
resolve_genimage() {
	if [ -x "$OUTPUT_DIR/host/bin/genimage" ]; then
		printf '%s' "$OUTPUT_DIR/host/bin/genimage"
	elif command -v genimage >/dev/null 2>&1; then
		command -v genimage
	else
		die "genimage not found (neither $OUTPUT_DIR/host/bin/genimage nor on PATH)"
	fi
}

require_prerequisites() {
	local f
	for f in "$OUR_LINUX_IMG" "$OUR_ZIMAGE_DTB" "$OUR_PAYLOAD_7ZA" "$OUR_INITRAMFS" "$OUR_FLAG"; do
		[ -f "$f" ] || die "missing $f -- run 'make all' before 'make sdcard'"
	done
	[ -f "$GENIMAGE_CFG" ] || die "missing genimage config: $GENIMAGE_CFG"
	[ -x "$REPO_ROOT/scripts/fetch-sdcard-payload.sh" ] || die "missing/non-executable scripts/fetch-sdcard-payload.sh"
	[ "$(stat -c %s "$OUR_FLAG")" = 512 ] || die "$OUR_FLAG is not one 512-byte sector"

	# The card has ONE kernel, so it must carry the installer; prove it from the kernel's own build.
	cpio -t --quiet < "$OUR_INITRAMFS" | grep -qx 'usr/libexec/mister-installer/install' ||
		die "$OUR_INITRAMFS has no installer -- BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER is off"
	local kver inc
	kver="$(sed -n 's/^BR2_LINUX_KERNEL_VERSION="\(.*\)"$/\1/p' "$OUTPUT_DIR/.config" 2>/dev/null)"
	inc="$OUTPUT_DIR/build/linux-$kver/usr/initramfs_inc_data"
	[ -n "$kver" ] && [ -f "$inc" ] || die "cannot find the kernel's embedded initramfs ($inc)"
	gzip -dc "$inc" | cmp -s - "$OUR_INITRAMFS" ||
		die "$OUR_ZIMAGE_DTB does not embed the current $OUR_INITRAMFS -- run 'make linux-rebuild all'"
	[ ! "$inc" -nt "$OUR_ZIMAGE_DTB" ] || die "$OUR_ZIMAGE_DTB is older than its kernel build -- run 'make all'"

	mkdir -p "$BUILD_DIR"
	cpio -i --quiet --to-stdout "$CPIO_FLAG_BIN" < "$OUR_INITRAMFS" > "$BUILD_DIR/flag.bin"
	cpio -i --quiet --to-stdout "$CPIO_FLAG_CONF" < "$OUR_INITRAMFS" > "$BUILD_DIR/flag.conf"
	[ "$(stat -c %s "$BUILD_DIR/flag.bin")" = 512 ] && [ -s "$BUILD_DIR/flag.conf" ] ||
		die "$OUR_INITRAMFS has no $CPIO_FLAG_BIN / $CPIO_FLAG_CONF"
	cmp -s "$BUILD_DIR/flag.bin" "$OUR_FLAG" ||
		die "$OUR_FLAG is not the cpio's own $CPIO_FLAG_BIN -- run 'make mister-initramfs-rebuild all'"
}

# check_flag_entry IMG -- entry FLAG_SLOT and LBA FLAG_LBA are what the cpio's probe accepts.
check_flag_entry() {
	local img=$1 want got slot type lba sectors
	# shellcheck source=board/mister/common/initramfs-overlay/usr/lib/mister/install-flag.conf
	want="$(set -u; . "$BUILD_DIR/flag.conf"; printf '%s %s %s %s' "$FLAG_SLOT" "$FLAG_TYPE" "$FLAG_LBA" "$FLAG_SECTORS")"
	read -r slot type lba sectors <<<"$want"
	# shellcheck disable=SC2046  # sixteen decimal words
	set -- $(od -An -tu1 -j $(( 446 + 16 * (slot - 1) )) -N16 "$img")
	[ $# -eq 16 ] || die "cannot read MBR entry $slot of $img"
	got="$5 $(( $9 | (${10} << 8) | (${11} << 16) | (${12} << 24) )) $(( ${13} | (${14} << 8) | (${15} << 16) | (${16} << 24) ))"
	[ "$got" = "$type $lba $sectors" ] ||
		die "MBR entry $slot of $img is '$got' (type start size); the probe wants '$type $lba $sectors' -- genimage-sdcard.cfg drifted"
	dd if="$img" bs=512 skip="$lba" count=1 status=none | cmp -s - "$BUILD_DIR/flag.bin" ||
		die "the flag block at LBA $lba of $img is not the cpio's $CPIO_FLAG_BIN"
}

stage_payload() {
	log "step 1/5: fetching + staging the stock payload (SDCARD_CORES=$SDCARD_CORES)"
	export STAGE_DIR SDCARD_CORES
	"$REPO_ROOT/scripts/fetch-sdcard-payload.sh" "$STAGE_DIR"
	[ -d "$PAYLOAD_DIR/linux" ] || die "fetch-sdcard-payload.sh did not produce $PAYLOAD_DIR/linux"
}

# Our linux.img (gzipped: it must never transit the mem=511M installer's RAM) and 7za go in
# the payload; the ONE kernel goes at the FAT root, where U-Boot loads it. ADR 0033 §3.
overlay_our_outputs() {
	log "step 2/5: overlaying our linux.img.gz, 7za and kernel"
	rm -f "$PAYLOAD_DIR/linux/linux.img" "$PAYLOAD_DIR/linux/zImage_dtb"
	gzip -c "$OUR_LINUX_IMG" > "$PAYLOAD_DIR/linux/linux.img.gz" || die "gzip of $OUR_LINUX_IMG failed"
	cp -f "$OUR_PAYLOAD_7ZA" "$PAYLOAD_DIR/linux/7za"
	log "  linux.img.gz: $(stat -c %s "$PAYLOAD_DIR/linux/linux.img.gz") bytes"

	rm -rf "$FATROOT_LINUX_DIR"
	mkdir -p "$FATROOT_LINUX_DIR"
	cp -f "$OUR_ZIMAGE_DTB" "$FATROOT_LINUX_DIR/zImage_dtb"
	log "  FAT root linux/zImage_dtb: $(stat -c %s "$OUR_ZIMAGE_DTB") bytes (no u-boot.txt)"

	# U-Boot's fpgaload reads menu.rbf from the FAT root only (ADR 0020 §7).
	if [ -f "$PAYLOAD_MENU_RBF" ]; then
		cp -f "$PAYLOAD_MENU_RBF" "$FATROOT_MENU_RBF"
		log "  FAT root menu.rbf: $(stat -c %s "$FATROOT_MENU_RBF") bytes"
	else
		rm -f "$FATROOT_MENU_RBF"
		log "WARNING: $PAYLOAD_MENU_RBF absent -- no HDMI during the install (check-sdcard.sh fails a release)"
	fi
}

build_payload_vfat() {
	log "step 3/5: building the FAT32 payload filesystem"
	mkdir -p "$GENIMAGE_INPUTS"
	local vfat="$GENIMAGE_INPUTS/$VFAT_IMAGE_NAME"
	rm -f "$vfat"
	local -a stage_entries=(mister-payload linux)
	[ -f "$FATROOT_MENU_RBF" ] && stage_entries+=(menu.rbf)

	# Content + 30% + 32 MiB slack, 64 MiB floor, rounded up to whole MiB (p2 stays 1M-aligned).
	local content_kib vfat_kib
	content_kib="$(cd "$STAGE_DIR" && du -sk --apparent-size "${stage_entries[@]}" | awk '{sum += $1} END {print sum + 0}')"
	case "$content_kib" in ''|*[!0-9]*) die "could not measure staged payload size (got '$content_kib')" ;; esac
	vfat_kib=$(( content_kib * 13 / 10 + 32768 ))
	[ "$vfat_kib" -ge 65536 ] || vfat_kib=65536
	vfat_kib=$(( (vfat_kib + 1023) / 1024 * 1024 ))
	log "  staged payload = ${content_kib} KiB; FAT32 image = ${vfat_kib} KiB"

	mkfs.vfat -F 32 -n "$FAT_LABEL" -C "$vfat" "$vfat_kib" >/dev/null || die "mkfs.vfat failed building $vfat"
	( cd "$STAGE_DIR" && MTOOLS_SKIP_CHECK=1 mcopy -s -i "$vfat" "${stage_entries[@]}" :: ) ||
		die "mcopy of the payload into $vfat failed"
}

assemble_hdimage() {
	log "step 4/5: assembling the hdimage (p1 FAT32, p2 0xA2 uboot.img, p3 installer flag)"
	local uboot_src="$PAYLOAD_DIR/linux/uboot.img"
	[ -f "$uboot_src" ] || die "stock uboot.img not staged at $uboot_src (fetch step failed?)"
	cp -f "$uboot_src" "$GENIMAGE_INPUTS/$UBOOT_INPUT_NAME"
	cp -f "$BUILD_DIR/flag.bin" "$GENIMAGE_INPUTS/$FLAG_INPUT_NAME"

	rm -rf "$GENIMAGE_TMP" "$GENIMAGE_OUT"
	mkdir -p "$GENIMAGE_TMP" "$GENIMAGE_ROOT" "$GENIMAGE_OUT"
	"$GENIMAGE_BIN" \
		--rootpath   "$GENIMAGE_ROOT" \
		--tmppath    "$GENIMAGE_TMP" \
		--inputpath  "$GENIMAGE_INPUTS" \
		--outputpath "$GENIMAGE_OUT" \
		--config     "$GENIMAGE_CFG" ||
		die "genimage failed assembling $GENIMAGE_IMAGE_NAME"
	[ -f "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME" ] || die "genimage produced no $GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME"

	# The flag must read back exactly as the cpio's probe will judge it.
	check_flag_entry "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME"
	log "  hdimage: $(stat -c %s "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME") bytes"
}

publish() {
	log "step 5/5: publishing ${FINAL_IMG##*/}(.xz)"
	mkdir -p "$OUTPUT_DIR/images"
	cp -f "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME" "$FINAL_IMG"
	rm -f "$FINAL_IMG.xz"
	xz -T0 --keep -f "$FINAL_IMG" || die "xz of $FINAL_IMG failed"
	log "done:"
	log "  raw : $FINAL_IMG ($(stat -c %s "$FINAL_IMG") bytes)"
	log "  xz  : $FINAL_IMG.xz ($(stat -c %s "$FINAL_IMG.xz") bytes)"
	log "Verify it with:  scripts/check-sdcard.sh $FINAL_IMG"
}

main() {
	log "assembling the SD-card installer image (SDCARD_CORES=$SDCARD_CORES)"
	require_host_tools
	require_prerequisites
	GENIMAGE_BIN="$(resolve_genimage)"
	readonly GENIMAGE_BIN
	log "genimage: $GENIMAGE_BIN"

	stage_payload
	overlay_our_outputs
	build_payload_vfat
	assemble_hdimage
	publish
}

main "$@"
