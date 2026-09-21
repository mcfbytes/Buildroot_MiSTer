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

set -e

TARGET_DIR="${1:?installer-post-build.sh: target dir argument missing}"
HERE="$(cd "$(dirname "$0")" && pwd)"
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
