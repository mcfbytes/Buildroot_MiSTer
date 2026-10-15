#!/bin/sh
# Structural checks on the assembled stage-1 tree and its cpio, run by
# package/mister-initramfs before the cpio is handed to the kernel.
#
# Every one of these is a real, shipped failure mode (ADR 0002 §8a): kconfig
# silently drops unknown BusyBox symbols, so a misspelled CONFIG_ turns into a
# cpio that looks healthy and an /init that dies on its first `[`. Check the
# artifact, not the intent.
#
# usage: verify.sh <root-dir> <cpio> [qemu-user binary] [itsalive|-] [installer]
set -eu

root=$1
cpio_file=$2
qemu=${3:-}
splash=${4:-}
installer=${5:-}
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

# ADR 0026/0033: fsck.exfat present; no other exfatprogs tool on any PATH dir (the
# installer's mkfs.exfat lives in /usr/libexec/mister-installer, checked below).
[ -x "$root/usr/sbin/fsck.exfat" ] || fail "/usr/sbin/fsck.exfat is missing or not executable (mister-initramfs-exfatprogs did not build it?)"
for b in dump.exfat exfat2img exfatlabel mkfs.exfat tune.exfat; do
	for d in sbin usr/sbin bin usr/bin; do
		[ -e "$root/$d/$b" ] && fail "$d/$b is in the tree and must not be (ADR 0026)"
	done
done

# The repair's HDMI splash (BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE). /init survives
# any of these missing, so they are checked here or never.
if [ "$splash" = itsalive ]; then
	[ -x "$root/usr/bin/itsalive" ] || fail "/usr/bin/itsalive is missing or not executable"
	file -b "$root/usr/bin/itsalive" | grep -q 'statically linked' ||
		fail "/usr/bin/itsalive is not statically linked: $(file -b "$root/usr/bin/itsalive")"
	for a in zcat timeout; do
		[ -e "$root/bin/$a" ] || [ -e "$root/usr/bin/$a" ] ||
			fail "the splash needs '$a' but it is not in the tree -- board/mister/common/initramfs-busybox.config"
	done
	for spec in 1280x720:3686400 640x480:1228800; do
		f="$root/usr/share/mister-fsck/splash-${spec%%:*}.raw.gz"
		got=$(gzip -dc "$f" 2>/dev/null | wc -c | tr -d ' ')
		[ "$got" = "${spec#*:}" ] || fail "$f decompresses to ${got:-nothing} bytes, want ${spec#*:}"
	done
fi

# The installer flag probe, its one definition and its magic block, on every board (ADR 0033).
[ -x "$root/usr/lib/mister/install-flag" ] || fail "/usr/lib/mister/install-flag is missing or not executable"
[ -f "$root/usr/lib/mister/install-flag.conf" ] || fail "/usr/lib/mister/install-flag.conf is missing"
flag="$root/usr/lib/mister/install-flag.bin"
[ "$(stat -c %s "$flag" 2>/dev/null)" = 512 ] || fail "$flag is not exactly 512 bytes"
head -c 33 "$flag" 2>/dev/null | grep -q '^MiSTer first-boot installer flag' || fail "$flag does not start with the flag magic"
for a in hexdump dd cmp; do
	[ -e "$root/bin/$a" ] || [ -e "$root/usr/bin/$a" ] ||
		fail "install-flag needs '$a' but it is not in the tree -- board/mister/common/initramfs-busybox.config"
done

# The first-boot installer (BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER): everything it runs.
inst="$root/usr/libexec/mister-installer"
if [ "$installer" = installer ]; then
	[ -f "$inst/install" ] || fail "$inst/install is missing"
	[ -x "$inst/mkfs.exfat" ] || fail "$inst/mkfs.exfat is missing or not executable"
	file -b "$inst/mkfs.exfat" | grep -q 'statically linked' ||
		fail "$inst/mkfs.exfat is not statically linked"
	for a in dd cmp wc hexdump blockdev blkid cp mv du cut rm sync zcat timeout reboot \
		mkdir mount umount cat sleep setsid cttyhack dmesg tail; do
		[ -e "$root/bin/$a" ] || [ -e "$root/sbin/$a" ] || [ -e "$root/usr/bin/$a" ] ||
			[ -e "$root/usr/sbin/$a" ] || fail "the installer needs '$a' but it is not in the tree"
	done
	if [ "$splash" = itsalive ]; then
		for spec in 1280x720:3686400 640x480:1228800; do
			f="$root/usr/share/mister-installer/splash-${spec%%:*}.raw.gz"
			got=$(gzip -dc "$f" 2>/dev/null | wc -c | tr -d ' ')
			[ "$got" = "${spec#*:}" ] || fail "$f decompresses to ${got:-nothing} bytes, want ${spec#*:}"
		done
	fi
else
	[ ! -e "$inst" ] || fail "$inst is in the tree without BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER"
fi
# One definition of the flag: no script that sources install-flag.conf may set FLAG_* itself.
for f in "$root/usr/lib/mister/install-flag" "$inst/install"; do
	[ -f "$f" ] || continue
	# shellcheck disable=SC2016  # a literal $FLAG_CONF in the script is what we look for
	grep -Eq '^[[:space:]]*\. "?(/usr/lib/mister/install-flag\.conf|\$FLAG_CONF)"?' "$f" ||
		fail "$f does not source install-flag.conf"
	! grep -Eq '^[[:space:]]*FLAG_(SLOT|LBA|SECTORS|TYPE|REF)=' "$f" || fail "$f redefines a FLAG_* value"
done

[ -f "$root/init" ] && [ -x "$root/init" ] || fail "/init is not a regular executable file (the overlay did not apply?)"

# The shipped ash must be able to PARSE /init. shellcheck checks the language;
# this checks the interpreter we ship (e.g. FEATURE_SH_MATH for $((...))).
if [ -n "$qemu" ] && command -v "$qemu" >/dev/null 2>&1; then
	for f in init usr/lib/mister/install-flag usr/lib/mister/install-flag.conf usr/libexec/mister-installer/install; do
		[ -f "$root/$f" ] || continue
		"$qemu" "$root/bin/busybox" ash -n "$root/$f" || fail "the BusyBox ash we just built cannot parse /$f"
	done
	# The installer's sector maths needs FEATURE_SH_MATH_64: a 2 TB card is past 2^31 sectors.
	# shellcheck disable=SC2016  # expanded by the shipped ash, not this one
	[ "$("$qemu" "$root/bin/busybox" ash -c 'echo $(( 4294967295 >> 24 ))' 2>/dev/null)" = 255 ] ||
		fail "the BusyBox ash we just built has 32-bit arithmetic (CONFIG_FEATURE_SH_MATH_64)"
	"$qemu" "$root/bin/busybox" ash -c '[ 4294967296 -gt 4294967295 ]' 2>/dev/null ||
		fail "the BusyBox [ we just built compares in 32 bits (CONFIG_FEATURE_TEST_64)"
else
	echo "mister-initramfs: WARN: ${qemu:-qemu-user} not available; skipping the ash -n parse checks" >&2
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
