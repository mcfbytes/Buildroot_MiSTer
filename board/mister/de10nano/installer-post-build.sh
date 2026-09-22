#!/bin/sh
#
# installer-post-build.sh <target-dir> [args...]
#
# Runs after the INSTALLER target filesystem is assembled, before the cpio is
# generated (BR2_ROOTFS_POST_BUILD_SCRIPT in configs/mister_installer_defconfig).
# Reproducible: no timestamps, no randomness. The sibling for the DE10-Nano
# image is post-build.sh; nothing there applies to a throwaway cpio with no
# /etc/shadow and no /MiSTer.version, which is why this is a separate file
# rather than a branch in that one.
#
# WHY THIS EXISTS — the HDMI splash frames.
# /init's splash section (ADR 0020 §9) feeds `itsalive image` a gzipped raw
# BGRX8888 frame per video mode from /usr/share/mister-installer/. Those frames
# are pure derivations of the PNGs in board/mister/de10nano/installer-splash/,
# so they are produced HERE at build time rather than committed next to their
# source: two fewer binaries in git, and a change to a PNG cannot ship with a
# stale frame. The converter is pure Python 3 (which Buildroot already needs on
# the host), so this adds no host dependency.
#
# Hard-checked, not merely hoped: the raw byte count must be exactly
# width x height x 4 for each mode, or `itsalive image` refuses the frame at
# run time -- a failure the unit test cannot see and a user would only meet as
# "the screen came up blank". Better to fail the build.
#
# AND WHY IT TRIMS UTIL-LINUX -- the black screen before the splash.
# /init needs util-linux for sfdisk, and Buildroot has no finer knob than
# BR2_PACKAGE_UTIL_LINUX_BINARIES, which is `--enable-all-programs`: ~60 static
# binaries (lsns, lscpu, swapon, ...) and ~10 MB of this cpio's ~13 MB. Every
# byte of it sits between power-on and the picture twice over -- U-Boot reads
# it off the card inside zImage_dtb, then the kernel inflates it before /init
# can run -- and nothing in the installer ever executes it. Measured on a
# DE10-Nano (2026-09-22): gunzipping the cpio took 1.0 s of CPU as built and
# 0.27 s trimmed (6.7 MB -> 1.7 MB gzipped). So every util-linux file NOT in
# UTIL_LINUX_KEEP goes. The keep list is exactly the util-linux programs /init
# runs; several shadow a BusyBox applet of the same name, so dropping one would
# silently swap implementations under /init rather than fail. A kept name that
# is missing fails the build.
UTIL_LINUX_KEEP="sfdisk blkid blockdev findfs hexdump dmesg setsid"

set -e

TARGET_DIR="${1:?installer-post-build.sh: target dir argument missing}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Written by Buildroot just before the post-build scripts run: one
# "package,./path" line per file each package installed into TARGET_DIR.
FILE_LIST="${BUILD_DIR:?installer-post-build.sh: BUILD_DIR not set (run from Buildroot)}/packages-file-list.txt"
SPLASH_SRC="$HERE/installer-splash"
SPLASH_DST="$TARGET_DIR/usr/share/mister-installer"

mkdir -p "$SPLASH_DST"
# size  expected-raw-bytes (w*h*4)
for spec in "1280x720 3686400" "640x480 1228800"; do
	# shellcheck disable=SC2086  # the split into two words is the point
	set -- $spec
	size="$1"; want="$2"
	png="$SPLASH_SRC/splash-$size.png"
	out="$SPLASH_DST/splash-$size.raw.gz"
	[ -f "$png" ] || { echo "installer-post-build.sh: ERROR: $png not found" >&2; exit 1; }
	python3 "$SPLASH_SRC/png2raw.py" "$png" "$out"
	got="$(gzip -dc "$out" | wc -c | tr -d ' ')"
	if [ "$got" != "$want" ]; then
		echo "installer-post-build.sh: ERROR: $out decompresses to $got bytes, want $want (${size} x 4)" >&2
		exit 1
	fi
	chmod 0644 "$out"
done
echo "installer-post-build.sh: rendered the HDMI splash frames into /usr/share/mister-installer"

[ -f "$FILE_LIST" ] || { echo "installer-post-build.sh: ERROR: $FILE_LIST not found" >&2; exit 1; }
trimmed=0
while IFS=, read -r pkg path; do
	[ "$pkg" = util-linux ] || continue
	case " $UTIL_LINUX_KEEP " in *" ${path##*/} "*) continue ;; esac
	f="$TARGET_DIR/${path#./}"
	if [ -e "$f" ] || [ -L "$f" ]; then rm -f "$f"; trimmed=$((trimmed + 1)); fi
done < "$FILE_LIST"
for p in $UTIL_LINUX_KEEP; do
	for d in bin sbin usr/bin usr/sbin; do
		[ -f "$TARGET_DIR/$d/$p" ] && continue 2
	done
	echo "installer-post-build.sh: ERROR: util-linux $p not in the target -- /init runs it" >&2
	exit 1
done
echo "installer-post-build.sh: removed $trimmed util-linux file(s) /init never runs; kept: $UTIL_LINUX_KEEP"
