#!/bin/sh
#
# check-uboot-handoff.sh — the handoff-equality gate for the DE10-Nano's
# mainline U-Boot port (docs/uboot-mainline-port.md Sec 3.2a, Sec 6;
# docs/uboot-tasks.md U4b).
#
# WHY THIS EXISTS. Sec 3.2a's binary evidence pins the SHIPPED stock SPL to
# the fork's QTS handoff headers by packing each of the seven handoff tables
# (pinmux, four IOCSR scan chains, two DDR sequencer ROMs) out of
# `qts/*.h` and finding the exact byte string inside SPL copy 0. The same
# check run against a build we control catches the one failure mode a
# cold-boot smoke test cannot: the build silently picking up the wrong
# `qts/*.h` tree (e.g. a rebase that reverts the carried headers, or a stray
# `-I` that shadows them with mainline's own). That failure mode looks
# EXACTLY like success — the build is green, the image is the right size,
# nothing about the build log says anything is wrong — right up until DDR
# calibration or the HPS-FPGA bridges misbehave on real silicon.
#
# WHAT THIS DOES NOT DO. Per Sec 3.2a: this proves each table's bytes are
# PRESENT in each image's SPL copy 0, at whatever offset the compiler put it
# — offsets are code layout and MUST NOT be compared between the two images,
# only reported. It does not touch the QTS scalar #defines (FPGAPORTRST, the
# PLL counts): those compile to instruction immediates and are not
# greppable — Sec 3.2a is explicit about that limit.
#
# HOW. The packing and byte-string search is done by a small python3 helper,
# scripts/lib/qts-tables.py (sanctioned style exception — see that file's own
# header for why: Buildroot already requires host python3, so this adds no
# dependency). This script is the POSIX sh front end: it validates arguments,
# runs that helper once, and turns its machine-readable report into this
# repo's usual ok()/bad() house style (scripts/check-zimage-dtb.sh).
#
# Usage: scripts/check-uboot-handoff.sh <qts-dir> <image-a> <image-b>
#
#   <qts-dir>   directory containing the qts/*.h headers to check (e.g. the
#               carried fork headers, copied out of the patched tree).
#   <image-a>,
#   <image-b>   two U-Boot images whose SPL copy 0 must both contain every
#               table packed from <qts-dir> — typically a freshly built
#               `u-boot-with-spl.sfp` and the reference stock `uboot.img`.
#               A fixture run may legitimately pass the SAME file twice (no
#               built .sfp exists yet, or to prove the harness itself works).
#
# Exit: 0 = every table found in SPL copy 0 of both images, 1 = at least one
#       table is missing from at least one image (named below) — a real
#       assertion failure, 2 = usage/IO/parse error.

set -eu

prog=${0##*/}
scriptdir=$(cd -- "$(dirname -- "$0")" && pwd)
helper="$scriptdir/lib/qts-tables.py"

usage() {
	echo "usage: $prog <qts-dir> <image-a> <image-b>" >&2
	exit 2
}

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; }

[ $# -eq 3 ] || usage
qts_dir=$1
image_a=$2
image_b=$3

[ -d "$qts_dir" ] || { echo "$prog: no such directory: $qts_dir" >&2; exit 2; }
[ -f "$image_a" ] || { echo "$prog: no such file: $image_a" >&2; exit 2; }
[ -f "$image_b" ] || { echo "$prog: no such file: $image_b" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "$prog: python3 not found on PATH" >&2; exit 2; }
[ -f "$helper" ] || { echo "$prog: helper missing: $helper" >&2; exit 2; }

printf '%s: qts-dir=%s\n' "$prog" "$qts_dir"
printf '%s: image-a=%s\n' "$prog" "$image_a"
printf '%s: image-b=%s\n' "$prog" "$image_b"

tmpout=$(mktemp) || { echo "$prog: mktemp failed" >&2; exit 2; }
trap 'rm -f "$tmpout"' EXIT

helper_rc=0
python3 "$helper" "$qts_dir" "$image_a" "$image_b" >"$tmpout" 2>&1 || helper_rc=$?

if [ "$helper_rc" -eq 2 ]; then
	echo "$prog: qts-tables.py usage/IO/parse error:" >&2
	sed 's/^/  /' "$tmpout" >&2
	exit 2
fi

if [ "$helper_rc" -ne 0 ] && [ "$helper_rc" -ne 1 ]; then
	echo "$prog: qts-tables.py exited $helper_rc unexpectedly:" >&2
	sed 's/^/  /' "$tmpout" >&2
	exit 2
fi

missing=0
found=0
while IFS='	' read -r table image status offset nbytes nwords; do
	case $table in
	SUMMARY) continue ;;
	esac
	case $status in
	FOUND)
		found=$((found + 1))
		ok "$table @ $offset in $image ($nbytes bytes, $nwords elements)"
		;;
	MISSING)
		missing=$((missing + 1))
		bad "$table NOT FOUND in $image ($nbytes bytes, $nwords elements packed)"
		;;
	*)
		echo "$prog: unrecognised report line from qts-tables.py: $table $image $status" >&2
		exit 2
		;;
	esac
done <"$tmpout"

note "$found found, $missing missing (7 tables x 2 images = 14 checks expected)"

if [ "$missing" -eq 0 ]; then
	echo "$prog: all seven handoff tables present in SPL copy 0 of both images"
	exit 0
else
	echo "$prog: HANDOFF MISMATCH — $missing table/image pair(s) missing, named above" >&2
	exit 1
fi
