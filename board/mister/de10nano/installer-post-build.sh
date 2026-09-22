#!/bin/sh

# installer-post-build.sh <target-dir> [args...] -- runs after the INSTALLER
# rootfs is assembled, before the cpio is built. Rationale: docs/installer-build.md.

# Kept util-linux programs -- everything else of --enable-all-programs is cut
# from the cpio below. Rationale + measurements: docs/installer-build.md.
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
