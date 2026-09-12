#!/bin/sh
# Structural checks on the assembled stage-1 tree and its cpio, run by
# package/mister-initramfs before the cpio is handed to the kernel.
#
# Every one of these is a real, shipped failure mode (ADR 0002 §8a): kconfig
# silently drops unknown BusyBox symbols, so a misspelled CONFIG_ turns into a
# cpio that looks healthy and an /init that dies on its first `[`. Check the
# artifact, not the intent.
#
# usage: verify.sh <root-dir> <cpio> [qemu-user binary]
set -eu

root=$1
cpio_file=$2
qemu=${3:-}
rc=0

fail() { echo "mister-initramfs: FATAL: $*" >&2; rc=1; }

# Applets /init invokes. A missing one is a brick: /init dies before the
# rescue shell can even be reached.
for a in sh mount umount losetup switch_root cttyhack setsid sleep mkdir cat ls \
	dmesg tail findfs printf echo test rm sync; do
	found=0
	for d in bin sbin usr/bin usr/sbin; do
		[ -e "$root/$d/$a" ] && { found=1; break; }
	done
	[ $found -eq 1 ] || fail "/init needs '$a' but it is not in the tree. Check its CONFIG_ symbol really exists in this BusyBox version (kconfig silently discards unknown symbols) -- board/mister/common/initramfs-busybox.config"
done

# ADR 0026: fsck.exfat present; the other exfatprogs tools absent (a card
# reformatter must not be one typo away from the boot path).
[ -x "$root/usr/sbin/fsck.exfat" ] || fail "/usr/sbin/fsck.exfat is missing or not executable (mister-initramfs-exfatprogs did not build it?)"
for b in dump.exfat exfat2img exfatlabel mkfs.exfat tune.exfat; do
	for d in sbin usr/sbin bin usr/bin; do
		[ -e "$root/$d/$b" ] && fail "$d/$b is in the tree and must not be (ADR 0026)"
	done
done

[ -f "$root/init" ] && [ -x "$root/init" ] || fail "/init is not a regular executable file (the overlay did not apply?)"

# The shipped ash must be able to PARSE /init. shellcheck checks the language;
# this checks the interpreter we ship (e.g. FEATURE_SH_MATH for $((...))).
if [ -n "$qemu" ] && command -v "$qemu" >/dev/null 2>&1; then
	"$qemu" "$root/bin/busybox" ash -n "$root/init" || fail "the BusyBox ash we just built cannot parse /init"
else
	echo "mister-initramfs: WARN: ${qemu:-qemu-user} not available; skipping the ash -n parse check of /init" >&2
fi

# The cpio must carry /dev/console (c 5 1): without it /init has no stdio and
# the rescue shell is unreachable.
if [ -f "$cpio_file" ]; then
	cpio -t --quiet < "$cpio_file" | grep -qx 'dev/console' || fail "dev/console is not in the cpio (fakeroot mknod step failed?)"
	cpio -t --quiet < "$cpio_file" | grep -qx 'init' || fail "init is not in the cpio"
else
	fail "cpio $cpio_file was not produced"
fi

[ $rc -eq 0 ] && echo "mister-initramfs: verify OK ($(cpio -t --quiet < "$cpio_file" | grep -c .) entries, $(stat -c %s "$cpio_file") bytes)"
exit $rc
