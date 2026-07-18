#!/usr/bin/env bash
#
# mk-sdcard.sh — assemble the shipped, dd/Etcher-writable SD-card installer image
# (`sdcard.img` / `sdcard-full.img`; TASKS.md P5.3, PLAN.md §8, ADR 0017, ADR 0020).
#
# This is the ORCHESTRATOR that ties the individually-authored sdcard-image pieces
# together into one release artifact. It runs AFTER a completed `make all` (it needs
# the real kernel + rootfs this repo builds) and produces
# `output/images/sdcard.img.xz` (or `output/images/sdcard-full.img.xz` when
# SDCARD_CORES=1), plus the raw `.img` beside it so `scripts/check-sdcard.sh` can
# verify the result without a second decompress.
#
# It is DELIBERATELY a shell orchestrator, not a Makefile target: there is no
# `installer`/`sdcard` target in the top-level Makefile yet (a separate task owns
# that), so this script drives Buildroot directly the same way the Makefile's
# BR_MAKE/BR_MAKE_RT recipes do — same `work/buildroot` tree, same BR2_EXTERNAL,
# same shared `dl/` cache, same host-`install` shim on PATH.
#
# ---------------------------------------------------------------------------
# The seven steps (fixed interface — TASKS.md P5.3 "scripts/mk-sdcard.sh")
# ---------------------------------------------------------------------------
#  1. Build the INSTALLER initramfs cpio from configs/mister_installer_defconfig
#     into output-installer/ (mirrors how the Makefile builds output-initramfs/
#     and output-rt/: a separate Buildroot O= with its own static-musl config).
#     Product: output-installer/images/rootfs.cpio.
#
#  2. Relink OUR kernel with that cpio embedded to produce the INSTALLER
#     zImage_dtb, then RESTORE output/ so output/images/zImage_dtb (the real,
#     Downloader-shipped kernel) is left exactly as `make all` produced it. This
#     REUSES the completed main build in output/: a `linux-reconfigure all` that
#     re-embeds step 1's cpio (via external.mk's MISTER_INITRAMFS_CPIO override) and
#     re-links only the kernel on the ALREADY-BUILT toolchain (~15 min) -- NOT a
#     fresh from-scratch build in a new O= (that would rebuild the whole internal
#     glibc toolchain + rootfs, ~3 h, and blow the CI job's wall-clock cap; see
#     .github/workflows/release.yml). Buildroot's own BR2_ROOTFS_POST_IMAGE_SCRIPT
#     (board/mister/de10nano/post-image.sh) assembles zImage_dtb during that `all`.
#     We snapshot the real zImage_dtb + gzip the real linux.img BEFORE the relink,
#     and re-run the relink with the DEFAULT (stage-1) cpio afterward, so output/
#     ends unchanged and step 4 ships our real artifacts regardless of output/'s
#     transient state. Product: output-installer-kernel/installer-zImage_dtb (a plain
#     holding file -- this dir is no longer a Buildroot O=, just scratch storage).
#
#  3. Fetch + verify + stage the external payload via
#     scripts/fetch-sdcard-payload.sh (SDCARD_CORES passed through). Product:
#     <stage>/mister-payload/ (see docs/verification/sdcard-payload.md).
#
#  4. Overlay OUR build outputs: replace the stock linux.img the fetch left in
#     <stage>/mister-payload/linux/ with OUR linux.img GZIPPED (linux/linux.img.gz --
#     the installer stream-decompresses it onto the card so the 512 MiB image never
#     transits the mem=511M RAM; ADR 0020 §3 / installer-overlay/init), overwrite
#     zImage_dtb with our real one, and lay the INSTALLER zImage_dtb (step 2) at the
#     FAT root's own linux/ dir. This reproduces sdcard-payload.md §1 exactly.
#
#  5. Build the FAT32 payload filesystem (mkfs.vfat + mcopy -s of the staged
#     tree), sized to content + generous slack. genimage's own
#     vfat-from-directory type is deliberately NOT used (PLAN §8 / the
#     genimage-sdcard.cfg header explain why) — we hand it a prebuilt image.
#
#  6. Run genimage with board/mister/de10nano/genimage-sdcard.cfg to assemble the
#     hdimage (MBR + 0xA2 uboot partition + the FAT32 payload partition). Prefers
#     output/host/bin/genimage, falls back to a PATH genimage.
#
#  7. xz -T0 the result to output/images/sdcard.img.xz (or sdcard-full.img.xz).
#
# ---------------------------------------------------------------------------
# Host build dependencies (NOT in the shipped rootfs — PLAN §"Host tooling")
# ---------------------------------------------------------------------------
# genimage, mtools (mcopy), dosfstools (mkfs.vfat), xz-utils, gzip, plus the usual
# make/coreutils (cmp included). These are build-HOST tools that never enter the
# image, so they live on PATH (CI installs them via extra-apt-packages), NOT in the
# main defconfig. This script fails loudly and by name if any is missing.
#
# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
#   make all                       # prerequisite: the real kernel + rootfs
#   scripts/mk-sdcard.sh           # -> output/images/sdcard.img(.xz)
#   SDCARD_CORES=1 scripts/mk-sdcard.sh   # -> output/images/sdcard-full.img(.xz)
#
# Exit: 0 = success; non-zero + a message on stderr on any failure. Every
# Buildroot invocation and every external tool is checked; a missing tool or a
# missing prerequisite (`make all` not run yet) is a clear, actionable error, not
# a deep-in-the-recipe crash.

set -o errexit
set -o nounset
set -o pipefail

# --- Locate the repo root ---------------------------------------------------
# Assigned then marked readonly separately (readonly X="$(cmd)" masks cmd's exit
# status — shellcheck SC2155), matching scripts/fetch-sdcard-payload.sh.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# --- Buildroot plumbing (mirror the top-level Makefile's BR_MAKE) -----------
readonly BR_DIR="$REPO_ROOT/work/buildroot"
readonly DL_DIR="$REPO_ROOT/dl"
readonly HOSTSHIM_DIR="$REPO_ROOT/work/.hostshim"   # Makefile HOSTSHIM_DIR

# --- The output directories this script reads or writes ---------------------
# output/                     : the MAIN build. Read for our real linux.img +
#                               zImage_dtb; ALSO transiently used for the step-2
#                               kernel relink (reconfigured with the installer cpio,
#                               then restored -- see build_installer_kernel).
# output-installer/           : the installer initramfs cpio (step 1; fixed interface)
# output-installer-kernel/    : scratch HOLDING dir (NOT a Buildroot O= any more): the
#                               captured installer zImage_dtb + the pre-relink snapshots
#                               of our real zImage_dtb / gzipped linux.img.
readonly OUTPUT_DIR="$REPO_ROOT/output"
readonly INSTALLER_OUTPUT_DIR="$REPO_ROOT/output-installer"
readonly INSTALLER_KERNEL_OUTPUT_DIR="$REPO_ROOT/output-installer-kernel"

readonly INSTALLER_CPIO="$INSTALLER_OUTPUT_DIR/images/rootfs.cpio"
# The installer kernel captured out of output/ after the relink, plus the pre-relink
# snapshots of our real outputs (so step 4 never depends on output/'s transient state).
readonly INSTALLER_ZIMAGE_DTB="$INSTALLER_KERNEL_OUTPUT_DIR/installer-zImage_dtb"
readonly SAVED_REAL_ZIMAGE_DTB="$INSTALLER_KERNEL_OUTPUT_DIR/real-zImage_dtb"
readonly SAVED_REAL_LINUX_IMG_GZ="$INSTALLER_KERNEL_OUTPUT_DIR/real-linux.img.gz"

readonly INSTALLER_DEFCONFIG="mister_installer_defconfig"
readonly INSTALLER_DEFCONFIG_FILE="$REPO_ROOT/configs/$INSTALLER_DEFCONFIG"
readonly INSTALLER_OVERLAY_INIT="$REPO_ROOT/board/mister/de10nano/installer-overlay/init"

# --- Our real, Downloader-shipped build outputs (inputs to this script) -----
readonly OUR_LINUX_IMG="$OUTPUT_DIR/images/linux.img"
readonly OUR_ZIMAGE_DTB="$OUTPUT_DIR/images/zImage_dtb"

# --- Staging + assembly scratch --------------------------------------------
# STAGE_DIR is the SAME default fetch-sdcard-payload.sh uses, so a warm
# .fetch-cache/ (the 93 MiB stock archive) survives across runs. The FAT root we
# hand to mkfs.vfat is exactly {mister-payload/, linux/} inside it — the fetch
# script's own .fetch-cache/.fetch-work siblings are excluded by copying only
# those two dirs into the image (never a blanket `mcopy -s .`).
STAGE_DIR="${STAGE_DIR:-$REPO_ROOT/output-sdcard-stage}"
readonly STAGE_DIR
readonly PAYLOAD_DIR="$STAGE_DIR/mister-payload"     # fetch-sdcard-payload.sh's product
readonly FATROOT_LINUX_DIR="$STAGE_DIR/linux"        # FAT root's linux/ (installer kernel only; no u-boot.txt)

# genimage's three working directories + the config it consumes.
readonly BUILD_DIR="$REPO_ROOT/output-sdcard-build"
readonly GENIMAGE_INPUTS="$BUILD_DIR/inputs"         # holds uboot.img + sdcard-payload.vfat
readonly GENIMAGE_TMP="$BUILD_DIR/genimage.tmp"      # genimage insists this be empty
readonly GENIMAGE_ROOT="$BUILD_DIR/empty-root"       # --rootpath (required, unused for hdimage)
readonly GENIMAGE_OUT="$BUILD_DIR/out"               # genimage writes sdcard.img here
readonly GENIMAGE_CFG="$REPO_ROOT/board/mister/de10nano/genimage-sdcard.cfg"

# The two input filenames genimage-sdcard.cfg hard-codes (keep in sync with it).
readonly VFAT_IMAGE_NAME="sdcard-payload.vfat"
readonly UBOOT_INPUT_NAME="uboot.img"
readonly GENIMAGE_IMAGE_NAME="sdcard.img"            # `image sdcard.img { ... }` in the cfg

# --- SDCARD_CORES: opt-in "full" variant (adds _Console cores, renames output) ---
SDCARD_CORES="${SDCARD_CORES:-0}"
readonly SDCARD_CORES
if [ "$SDCARD_CORES" = "1" ]; then
	readonly FINAL_IMG="$OUTPUT_DIR/images/sdcard-full.img"
else
	readonly FINAL_IMG="$OUTPUT_DIR/images/sdcard.img"
fi

# --- FAT32 payload label (cosmetic; nothing boots by it) --------------------
# U-Boot loads by partition NUMBER, not label (boot-chain §4), and the installer
# /init resolves the data partition from root= on the cmdline, so this label is
# purely cosmetic. Kept distinct from the final card's exFAT "MiSTer_Data" so the
# two are never confused when inspecting a card. FAT labels are <=11 chars, upper.
readonly FAT_LABEL="MISTER"

# NOTE: the installer card ships NO linux/u-boot.txt. An earlier design wrote one
# with a `mem=1024M` override to hand the installer more RAM, but the stock uboot.img
# hardcodes `mem=511M memmap=513M$511M` as a literal string in `mmcboot` and never
# interpolates a `mem=` env var (docs/boot-chain.md §4), so that override was inert --
# the installer always booted at mem=511M. The RAM ceiling is instead respected by
# shipping linux.img GZIPPED and stream-decompressing it onto the card (step 4 / the
# installer /init), so nothing needs the missing headroom. U-Boot's `scrtest` guards
# the load with `if test -e .../linux/u-boot.txt`, so the file's ABSENCE is safe.

# --- small helpers ----------------------------------------------------------
log() { printf 'mk-sdcard: %s\n' "$*"; }
err() { printf 'mk-sdcard: ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

# ===========================================================================
# Preconditions: tools + prerequisite build outputs
# ===========================================================================

require_host_tools() {
	# Buildroot invocations + the coreutils this script leans on.
	local missing=""
	local t
	# gzip: step 2 pre-gzips our real linux.img into the payload (linux/linux.img.gz)
	# so the 512 MiB image never has to transit the installer's mem=511M RAM tmpfs.
	# cmp: step 2 asserts the captured installer kernel differs from the real one.
	for t in make du awk sha256sum stat gzip cmp; do
		command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
	done

	# The image-assembly tools (the ones a fresh runner most often lacks). Named
	# with their providing package so the error is directly actionable, mirroring
	# PLAN §"Host tooling".
	command -v mkfs.vfat >/dev/null 2>&1 || missing="$missing mkfs.vfat(dosfstools)"
	command -v mcopy     >/dev/null 2>&1 || missing="$missing mcopy(mtools)"
	command -v xz        >/dev/null 2>&1 || missing="$missing xz(xz-utils)"

	if [ -n "$missing" ]; then
		err "missing required host tool(s):$missing"
		err "install them first, e.g. on Debian/Ubuntu:"
		err "    sudo apt-get install genimage mtools dosfstools xz-utils p7zip-full jq"
		err "(genimage/mtools/dosfstools/xz-utils are build-HOST tools; they never"
		err " enter the shipped rootfs — see PLAN §\"Host tooling\".)"
		exit 1
	fi
}

# Resolve the genimage binary: prefer the one Buildroot may have built into
# output/host/bin (BR2_PACKAGE_HOST_GENIMAGE), else a PATH genimage.
resolve_genimage() {
	if [ -x "$OUTPUT_DIR/host/bin/genimage" ]; then
		printf '%s' "$OUTPUT_DIR/host/bin/genimage"
		return 0
	fi
	if command -v genimage >/dev/null 2>&1; then
		command -v genimage
		return 0
	fi
	err "genimage not found (neither $OUTPUT_DIR/host/bin/genimage nor on PATH)"
	err "install it, e.g.: sudo apt-get install genimage"
	exit 1
}

require_prerequisites() {
	# The Buildroot tree the Makefile unpacks/verifies. We do not fetch it here —
	# that is the Makefile's job; a `make all` (this script's prerequisite) has
	# already done it.
	[ -f "$BR_DIR/Makefile" ] || die "Buildroot tree not found at $BR_DIR — run 'make all' first (it fetches/unpacks Buildroot)"

	# Our real build outputs (step 4 overlays these). Their absence means the
	# main build has not run — this script cannot and must not fabricate them.
	[ -f "$OUR_LINUX_IMG" ] || die "missing $OUR_LINUX_IMG — run 'make all' before 'make sdcard'"
	[ -f "$OUR_ZIMAGE_DTB" ] || die "missing $OUR_ZIMAGE_DTB — run 'make all' before 'make sdcard'"

	# The installer pieces authored by the sibling tasks.
	[ -f "$INSTALLER_DEFCONFIG_FILE" ] || die "missing installer defconfig: $INSTALLER_DEFCONFIG_FILE"
	[ -x "$INSTALLER_OVERLAY_INIT" ] || die "missing/non-executable installer init: $INSTALLER_OVERLAY_INIT"
	[ -f "$GENIMAGE_CFG" ] || die "missing genimage config: $GENIMAGE_CFG"
	[ -x "$REPO_ROOT/scripts/fetch-sdcard-payload.sh" ] || die "missing/non-executable scripts/fetch-sdcard-payload.sh"
}

# br_make O_DIR EXTRA_VARS... -- one forwarded Buildroot invocation, shaped exactly
# like the Makefile's BR_MAKE (same tree, BR2_EXTERNAL, shared dl/ cache) with the
# host-`install` GNU shim prepended to PATH when it exists (it is created by the
# Makefile's `hostshim` target only on hosts whose `install` is not GNU; on a GNU
# host the directory never exists and this prefix is inert — same contract the
# Makefile documents).
br_make() {
	local o_dir="$1"; shift
	local shim_path="$PATH"
	[ -d "$HOSTSHIM_DIR" ] && shim_path="$HOSTSHIM_DIR:$PATH"
	PATH="$shim_path" \
		make -C "$BR_DIR" \
			O="$o_dir" \
			BR2_EXTERNAL="$REPO_ROOT" \
			BR2_DL_DIR="$DL_DIR" \
			"$@"
}

# ===========================================================================
# Step 1 — the installer initramfs cpio (output-installer/)
# ===========================================================================
build_installer_cpio() {
	log "step 1/7: building the installer initramfs cpio ($INSTALLER_DEFCONFIG -> output-installer/)"
	mkdir -p "$INSTALLER_OUTPUT_DIR"

	# Load the installer config into its own output dir (idempotent: reloading a
	# defconfig is cheap), then build. BR2_TARGET_ROOTFS_CPIO=y in that config
	# makes `all` emit images/rootfs.cpio.
	br_make "$INSTALLER_OUTPUT_DIR" "$INSTALLER_DEFCONFIG"
	br_make "$INSTALLER_OUTPUT_DIR" all

	[ -f "$INSTALLER_CPIO" ] ||
		die "installer build finished but produced no $INSTALLER_CPIO"
	log "installer cpio: $(stat -c %s "$INSTALLER_CPIO") bytes ($INSTALLER_CPIO)"
}

# ===========================================================================
# Snapshot our real outputs BEFORE the in-place relink (step 2) touches output/
# ===========================================================================
# Step 2 reconfigures + re-links the kernel IN output/, which transiently overwrites
# output/images/zImage_dtb. Snapshot the real artifacts first -- and gzip linux.img
# now, in the exact form it ships -- so step 4 always overlays OUR real build, never
# a half-relinked output/. gzip because linux.img ships GZIPPED on the card (the
# installer stream-decompresses it so the 512 MiB image never transits its mem=511M
# RAM; ADR 0020 §3 / board/mister/de10nano/installer-overlay/init).
snapshot_real_outputs() {
	log "snapshotting our real zImage_dtb + gzipping linux.img (before the in-place relink)"
	mkdir -p "$INSTALLER_KERNEL_OUTPUT_DIR"
	cp -f "$OUR_ZIMAGE_DTB" "$SAVED_REAL_ZIMAGE_DTB"
	# -c to stdout so the source (a hardlink of the sparse rootfs.ext2) is untouched.
	gzip -c "$OUR_LINUX_IMG" > "$SAVED_REAL_LINUX_IMG_GZ" ||
		die "gzip of $OUR_LINUX_IMG failed"
	log "  real zImage_dtb: $(stat -c %s "$SAVED_REAL_ZIMAGE_DTB") bytes"
	log "  linux.img.gz:    $(stat -c %s "$SAVED_REAL_LINUX_IMG_GZ") bytes (from a $(stat -c %s "$OUR_LINUX_IMG")-byte linux.img)"
}

# ===========================================================================
# Step 2 — relink OUR kernel with the installer cpio, REUSING output/
# ===========================================================================
# We must NOT do a fresh from-scratch Buildroot build here: a new empty O= would
# rebuild the whole internal glibc toolchain + rootfs (~3 h), and stacked on the main
# build in the same CI job that overruns GitHub's hard ~6 h wall-clock cap so the
# release never publishes (.github/workflows/release.yml). Instead we REUSE the
# completed main build in output/ -- its toolchain and kernel objects are already
# built -- and just RE-LINK the kernel with a different embedded initramfs (~15 min).
#
# The catch: relinking in output/ transiently overwrites output/images/zImage_dtb
# with the installer kernel. We handle that by (a) snapshotting our real outputs
# BEFORE the relink (snapshot_real_outputs, from main) so step 4 is immune to
# output/'s transient state, and (b) relinking a SECOND time with the DEFAULT cpio
# afterward so output/ is left exactly as `make all` produced it (a standalone
# `make sdcard`, or a later `make all`, then sees no difference). In CI the real
# release assets are already staged into dist/ before this runs, so even a failure
# mid-relink cannot corrupt the shipped Downloader assets.
build_installer_kernel() {
	log "step 2/7: relinking OUR kernel with the installer cpio (in-place in output/, then restoring)"
	mkdir -p "$INSTALLER_KERNEL_OUTPUT_DIR"

	local cpio_override="MISTER_INITRAMFS_CPIO=$INSTALLER_CPIO"

	# SAFETY NET for the shared output/ dir. The relink below transiently overwrites
	# output/images/zImage_dtb with the INSTALLER kernel; the restore afterward puts
	# the real one back. If ANYTHING in between fails (a br_make error, the capture
	# check, a cp) under `set -e`, the script would exit leaving output/ -- a build
	# dir other targets read -- holding the installer kernel. Arm an EXIT trap that
	# restores the shipped artifact from the pre-relink snapshot on any early exit,
	# and disarm it once the normal restore has run. (The kernel build tree under
	# output/build/linux-*/ still references the installer cpio after such a failure,
	# but the next `make all` self-corrects via external.mk's default MISTER_INITRAMFS_CPIO;
	# what must never be left wrong is the shipped output/images/zImage_dtb, and this
	# guarantees that.) Snapshot exists: snapshot_real_outputs ran before this.
	_restore_output_zimage() {
		[ -f "$SAVED_REAL_ZIMAGE_DTB" ] || return 0
		if cp -f "$SAVED_REAL_ZIMAGE_DTB" "$OUR_ZIMAGE_DTB" 2>/dev/null; then
			err "output/images/zImage_dtb restored from the pre-relink snapshot after a failure mid-relink"
		fi
	}
	trap '_restore_output_zimage' EXIT

	# Re-embed the installer cpio and re-link. `linux-reconfigure` re-runs the kernel
	# kconfig-fixup (external.mk sets CONFIG_INITRAMFS_SOURCE=$INSTALLER_CPIO) then
	# rebuilds + reinstalls the kernel; the trailing `all` re-runs post-image.sh
	# (BR2_ROOTFS_POST_IMAGE_SCRIPT) to reassemble output/images/zImage_dtb -- now the
	# INSTALLER kernel. Everything else in output/ is already built, so `all` is fast.
	log "  relinking with the installer cpio ..."
	br_make "$OUTPUT_DIR" "$cpio_override" linux-reconfigure all

	# Capture the installer zImage_dtb out of output/ before we restore it.
	[ -f "$OUR_ZIMAGE_DTB" ] ||
		die "installer relink finished but produced no $OUR_ZIMAGE_DTB"
	cp -f "$OUR_ZIMAGE_DTB" "$INSTALLER_ZIMAGE_DTB"

	# Restore output/ to the real kernel: reconfigure back to the DEFAULT (stage-1)
	# cpio -- external.mk's MISTER_INITRAMFS_CPIO default is output-initramfs/'s cpio,
	# which the main build already produced -- and reassemble. Then, belt-and-
	# suspenders, drop our pre-relink snapshot back over output/images/zImage_dtb.
	log "  restoring output/ to the real kernel ..."
	br_make "$OUTPUT_DIR" linux-reconfigure all
	cp -f "$SAVED_REAL_ZIMAGE_DTB" "$OUR_ZIMAGE_DTB"

	# output/ is back to the real kernel -- disarm the safety net. Any failure in the
	# sanity checks below no longer risks a dirty output/ (it is already restored).
	trap - EXIT

	# The captured installer kernel must NOT be the real one -- a wiring mistake here
	# would ship the throwaway installer kernel to Downloader users. It MUST differ in
	# content too (a bigger embedded initramfs), or the cpio was not swapped in.
	if [ "$INSTALLER_ZIMAGE_DTB" -ef "$OUR_ZIMAGE_DTB" ]; then
		die "installer zImage_dtb resolves to the SAME file as the real one ($OUR_ZIMAGE_DTB) — refusing"
	fi
	if cmp -s "$INSTALLER_ZIMAGE_DTB" "$OUR_ZIMAGE_DTB"; then
		die "installer zImage_dtb is byte-identical to the real one — the installer cpio was not embedded (relink failed)"
	fi
	log "installer zImage_dtb: $(stat -c %s "$INSTALLER_ZIMAGE_DTB") bytes ($INSTALLER_ZIMAGE_DTB)"
}

# ===========================================================================
# Step 3 — fetch + verify + stage the external payload
# ===========================================================================
stage_payload() {
	log "step 3/7: fetching + staging the external payload (SDCARD_CORES=$SDCARD_CORES)"
	# Export both into the child's environment: STAGE_DIR so it uses the same dir
	# (and warm .fetch-cache/) — also passed as $1, which wins either way — and
	# SDCARD_CORES so the fetch stages (or prunes) _Console. `export` on an
	# already-readonly var only sets the export attribute; the value is unchanged.
	export STAGE_DIR SDCARD_CORES
	"$REPO_ROOT/scripts/fetch-sdcard-payload.sh" "$STAGE_DIR"

	[ -d "$PAYLOAD_DIR/linux" ] ||
		die "fetch-sdcard-payload.sh did not produce $PAYLOAD_DIR/linux — cannot continue"
}

# ===========================================================================
# Step 4 — overlay OUR outputs + build the FAT root's linux/ dir
# ===========================================================================
overlay_our_outputs() {
	log "step 4/7: overlaying our linux.img.gz + zImage_dtb and the installer kernel"

	# 4a. Replace the STOCK linux.img/zImage_dtb the fetch left under
	#     mister-payload/linux/ with OUR real build (snapshotted before the step-2
	#     relink). These are the REAL boot kernel/rootfs the installer lays onto the
	#     reformatted exFAT card. linux.img ships GZIPPED (linux/linux.img.gz): the
	#     installer stream-decompresses it onto the card, so the 512 MiB image never
	#     transits its mem=511M RAM (ADR 0020 §3 / installer-overlay/init). Drop the
	#     stock uncompressed linux.img the fetch copied in -- we ship only the .gz.
	rm -f "$PAYLOAD_DIR/linux/linux.img"
	cp -f "$SAVED_REAL_LINUX_IMG_GZ" "$PAYLOAD_DIR/linux/linux.img.gz"
	cp -f "$SAVED_REAL_ZIMAGE_DTB" "$PAYLOAD_DIR/linux/zImage_dtb"

	# 4b. The FAT root's own linux/ dir holds ONLY the installer kernel
	#     (sdcard-payload.md §1: linux/, linux/zImage_dtb — nothing else). No
	#     linux/u-boot.txt: an env override there would be inert against the stock
	#     uboot.img (it hardcodes mem=511M and never reads a `mem=` var -- boot-chain
	#     §4), and U-Boot's scrtest `if test -e` guard makes the file's absence safe.
	#     Rebuild the dir from scratch each run so a stale file can never survive.
	rm -rf "$FATROOT_LINUX_DIR"
	mkdir -p "$FATROOT_LINUX_DIR"
	cp -f "$INSTALLER_ZIMAGE_DTB" "$FATROOT_LINUX_DIR/zImage_dtb"

	log "FAT root linux/: installer zImage_dtb (no u-boot.txt -- see 4b)"
}

# ===========================================================================
# Step 5 — build the FAT32 payload filesystem
# ===========================================================================
build_payload_vfat() {
	log "step 5/7: building the FAT32 payload filesystem"
	mkdir -p "$GENIMAGE_INPUTS"
	local vfat="$GENIMAGE_INPUTS/$VFAT_IMAGE_NAME"
	rm -f "$vfat"

	# Size = content (measured from the two dirs that actually go into the image,
	# NOT the whole STAGE_DIR which also holds .fetch-cache/.fetch-work) + 30%
	# slack for FAT tables / directory entries / cluster rounding, with a 64 MiB
	# floor (comfortably above FAT32's ~33 MiB minimum). Since linux.img now ships
	# GZIPPED (linux/linux.img.gz, ~80 MiB), the base payload is on the order of
	# ~150-200 MiB rather than the ~700 MiB the raw 512 MiB linux.img used to force.
	#
	# --apparent-size is kept as belt-and-suspenders: none of the staged files are
	# sparse today (the .gz is dense, the stock members are plain files, and mcopy
	# writes file CONTENTS into FAT32, which has no sparse support), so it equals
	# `du`'s allocated figure here -- but were any sparse file ever added under
	# mister-payload/, apparent size is what mcopy would actually write, and sizing
	# from allocated blocks would under-build the vfat and ENOSPC in mcopy.
	local content_kib
	content_kib="$(cd "$STAGE_DIR" && du -sk --apparent-size mister-payload linux | awk '{sum += $1} END {print sum + 0}')"
	case "$content_kib" in
		''|*[!0-9]*) die "could not measure staged payload size (got '$content_kib')" ;;
	esac
	local vfat_kib=$(( content_kib * 13 / 10 + 32768 ))
	local floor_kib=$(( 64 * 1024 ))
	[ "$vfat_kib" -ge "$floor_kib" ] || vfat_kib="$floor_kib"
	log "staged payload = ${content_kib} KiB; FAT32 image = ${vfat_kib} KiB"

	# mkfs.vfat -C creates the image file itself; its size argument is a count of
	# 1024-byte blocks (dosfstools BLOCK_SIZE), i.e. the KiB figure above. -F 32
	# forces FAT32 (the type genimage-sdcard.cfg declares, partition-type 0x0c).
	mkfs.vfat -F 32 -n "$FAT_LABEL" -C "$vfat" "$vfat_kib" >/dev/null ||
		die "mkfs.vfat failed building $vfat"

	# Copy ONLY the two payload dirs into the image root (never the fetch cache).
	# MTOOLS_SKIP_CHECK=1 stops mtools rejecting our freshly-made FS over cosmetic
	# geometry nits (same flag check-sdcard.sh uses to read it back). -s = recurse.
	(
		cd "$STAGE_DIR"
		MTOOLS_SKIP_CHECK=1 mcopy -s -i "$vfat" mister-payload linux ::
	) || die "mcopy of the payload into $vfat failed"

	log "FAT32 payload image: $(stat -c %s "$vfat") bytes ($vfat)"
}

# ===========================================================================
# Step 6 — assemble the hdimage with genimage
# ===========================================================================
assemble_hdimage() {
	log "step 6/7: assembling the SD-card hdimage with genimage"
	# Resolved (and existence-checked) up front in main so a missing genimage fails
	# in the preflight, not after the two multi-hour Buildroot builds.
	local genimage="$GENIMAGE_BIN"

	# genimage's second input: the stock uboot.img, written RAW to the 0xA2
	# partition. We use the SAME copy the fetch already verified byte-for-byte
	# against STOCK_UBOOT_SHA256 (mister-payload/linux/uboot.img) — no second
	# download, and it is provably the pinned blob.
	local uboot_src="$PAYLOAD_DIR/linux/uboot.img"
	[ -f "$uboot_src" ] || die "stock uboot.img not staged at $uboot_src (fetch step failed?)"
	cp -f "$uboot_src" "$GENIMAGE_INPUTS/$UBOOT_INPUT_NAME"

	# genimage requires an EMPTY tmppath and a rootpath (unused for a pure
	# hdimage-of-prebuilt-images, but the flag is mandatory). Recreate both clean.
	rm -rf "$GENIMAGE_TMP" "$GENIMAGE_OUT"
	mkdir -p "$GENIMAGE_TMP" "$GENIMAGE_ROOT" "$GENIMAGE_OUT"

	"$genimage" \
		--rootpath   "$GENIMAGE_ROOT" \
		--tmppath    "$GENIMAGE_TMP" \
		--inputpath  "$GENIMAGE_INPUTS" \
		--outputpath "$GENIMAGE_OUT" \
		--config     "$GENIMAGE_CFG" ||
		die "genimage failed assembling $GENIMAGE_IMAGE_NAME"

	[ -f "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME" ] ||
		die "genimage reported success but produced no $GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME"
	log "hdimage: $(stat -c %s "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME") bytes"
}

# ===========================================================================
# Step 7 — publish: raw .img + xz -T0 next to it in output/images/
# ===========================================================================
publish() {
	log "step 7/7: publishing $([ "$SDCARD_CORES" = 1 ] && echo sdcard-full.img || echo sdcard.img)(.xz)"
	mkdir -p "$OUTPUT_DIR/images"

	# Keep the RAW image beside the .xz: scripts/check-sdcard.sh verifies the raw
	# hdimage (partition table, uboot head, FAT inventory) and release.yml runs it
	# before publishing — no second decompress needed. `xz --keep` leaves the raw
	# in place; `-T0` uses all cores; `-f` overwrites a stale .xz from a prior run.
	cp -f "$GENIMAGE_OUT/$GENIMAGE_IMAGE_NAME" "$FINAL_IMG"
	rm -f "$FINAL_IMG.xz"
	xz -T0 --keep -f "$FINAL_IMG" || die "xz of $FINAL_IMG failed"

	[ -f "$FINAL_IMG.xz" ] || die "xz reported success but produced no $FINAL_IMG.xz"
	log "done:"
	log "  raw : $FINAL_IMG ($(stat -c %s "$FINAL_IMG") bytes)"
	log "  xz  : $FINAL_IMG.xz ($(stat -c %s "$FINAL_IMG.xz") bytes)"
	log ""
	log "Verify it with:  scripts/check-sdcard.sh $FINAL_IMG"
}

# ===========================================================================
# main
# ===========================================================================
main() {
	log "assembling the SD-card installer image (SDCARD_CORES=$SDCARD_CORES)"
	require_host_tools
	require_prerequisites

	# Fail-fast preflight: resolve genimage NOW (it exits with a clear message if
	# absent) so a runner lacking it stops in seconds rather than after step 1's
	# installer-initramfs build and step 2's kernel relink. resolve_genimage is the
	# sibling of the mkfs.vfat/mcopy/xz checks in require_host_tools but needs the
	# output/host/bin fallback, so it lives here where OUTPUT_DIR is meaningful.
	# assemble_hdimage reuses this resolved path.
	GENIMAGE_BIN="$(resolve_genimage)"
	readonly GENIMAGE_BIN
	log "genimage: $GENIMAGE_BIN"

	snapshot_real_outputs      # 0: capture real zImage_dtb + gzip linux.img (pre-relink)
	build_installer_cpio       # 1
	build_installer_kernel     # 2 (in-place relink in output/, then restore)
	stage_payload              # 3
	overlay_our_outputs        # 4
	build_payload_vfat         # 5
	assemble_hdimage           # 6
	publish                    # 7
}

main "$@"
