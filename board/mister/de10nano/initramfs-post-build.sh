#!/bin/sh
#
# initramfs-post-build.sh <target-dir> [args...]
#
# Stage-1 (initramfs) post-build hook. Runs after the cpio's target tree is
# assembled and before the cpio is generated (BR2_ROOTFS_POST_BUILD_SCRIPT in
# configs/mister_initramfs_defconfig). Reproducible: no timestamps, no
# randomness, no network -- it only deletes files (A9).
#
# WHY THIS EXISTS -- exfatprogs ships six binaries and /init calls one.
#
# BR2_PACKAGE_EXFATPROGS has no per-binary sub-options (its Config.in offers
# nothing but `depends on BR2_USE_WCHAR`), unlike dosfstools, whose .mk wraps
# each of FATLABEL/FSCK_FAT/MKFS_FAT in its own install guard. So the only way
# to take fsck.exfat without the other five is to delete them afterwards.
#
# This is not housekeeping. Every byte in this tree is a byte of zImage: the
# cpio is embedded via CONFIG_INITRAMFS_SOURCE and shares the 16 MiB U-Boot load
# budget that scripts/check-zimage-dtb.sh enforces. The five unused binaries are
# static musl ARM executables of 87-104 KB each once stripped -- 476,876 bytes
# measured on this toolchain, more than the entire rest of the cpio put together
# -- to ship five tools that nothing in stage 1 can invoke. (fsck.exfat, the one
# we keep, is 116,564; the whole cpio is 422,400 with it in.) Stage 1 has no
# shell user: it runs /init
# and switch_roots. mkfs.exfat in particular has no business being one `sh`
# typo away from the boot path of a device whose data partition is the thing it
# would reformat. (The full set does ship in the ROOTFS, where a user with a
# shell can reach it -- BR2_PACKAGE_EXFATPROGS in mister_de10nano_defconfig.)
#
# KEEP THIS LIST IN STEP with what the initramfs /init actually invokes. The
# Makefile's `initramfs-verify` target asserts both directions against the built
# cpio -- fsck.exfat present, the deleted five absent -- so a drift here fails
# the build rather than silently shipping a bigger zImage or, worse, silently
# removing something /init needs.

set -e

TARGET_DIR="${1:?initramfs-post-build.sh: target dir argument missing}"

# Everything exfatprogs installs EXCEPT fsck.exfat. Named individually rather
# than globbed so that a new binary in a future exfatprogs release is NOT
# silently deleted -- it shows up as unexpected cpio content in
# `initramfs-verify` and gets a deliberate decision.
for tool in dump.exfat exfat2img exfatlabel mkfs.exfat tune.exfat; do
	rm -f "${TARGET_DIR}/usr/sbin/${tool}" "${TARGET_DIR}/sbin/${tool}"
done

# fsck.exfat is the whole point of pulling the package in; if it is missing the
# repair path would be a silent no-op on every boot that requested it.
[ -x "${TARGET_DIR}/usr/sbin/fsck.exfat" ] || [ -x "${TARGET_DIR}/sbin/fsck.exfat" ] || {
	echo "FATAL: initramfs-post-build.sh: fsck.exfat is not in the target tree." >&2
	echo "       BR2_PACKAGE_EXFATPROGS is set in configs/mister_initramfs_defconfig;" >&2
	echo "       did the package move its install path? See ADR 0026." >&2
	exit 1
}
