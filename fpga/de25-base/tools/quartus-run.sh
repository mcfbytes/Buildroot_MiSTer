#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs a command in Altera's pinned Quartus Pro container (docs/de25-quartus.md §4).
#
# usage: quartus-run.sh COMMAND [ARGS...]   (the current directory is mounted at /w)
# env:   QUARTUS_LICENSE  licence file(s) on the host, colon-separated (required for a compile)
#        QUARTUS_MAC      the NIC ID your own licence was issued for (required with a licence)
#        QUARTUS_IMAGE    override the pinned image
set -eu

: "${QUARTUS_IMAGE:=alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}"
: "${QUARTUS_MAC:=}"
[ $# -ge 1 ] || { echo "usage: ${0##*/} COMMAND [ARGS...]" >&2; exit 2; }
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# Each licence file is mounted at /opt/license-N.dat and listed in LM_LICENSE_FILE.
mounts= ; lmf= ; n=0
if [ -n "${QUARTUS_LICENSE:-}" ]; then
	old_ifs=$IFS; IFS=:
	for f in $QUARTUS_LICENSE; do
		[ -f "$f" ] || { echo "${0##*/}: no licence at $f" >&2; exit 1; }
		f=$(CDPATH='' cd -- "$(dirname -- "$f")" && pwd)/$(basename -- "$f")
		case $f in *[[:space:]]*) echo "${0##*/}: licence path has a space: $f" >&2; exit 1;; esac
		n=$((n + 1))
		mounts="$mounts -v $f:/opt/license-$n.dat:ro"
		lmf="${lmf:+$lmf:}/opt/license-$n.dat"
	done
	IFS=$old_ifs
	# No shared default: a FIXED licence is per user and per NIC (docs/de25-quartus.md §3).
	[ -n "$QUARTUS_MAC" ] || { echo "${0##*/}: set QUARTUS_MAC to your licence's NIC ID" >&2; exit 1; }
fi

# The image's libudev aborts in FlexLM's host-ID probe; mount a stub over it (built once, here).
stub="$PWD/.quartus-run/libudev-stub.so"
if [ ! -f "$stub" ] || [ "$here/udev-stub.c" -nt "$stub" ]; then
	mkdir -p "${stub%/*}"
	${CC:-cc} -shared -fPIC -O2 -Wl,-soname,libudev.so.1 -o "$stub" "$here/udev-stub.c"
fi

# shellcheck disable=SC2086 # $mounts is split on purpose; its paths have no spaces
exec docker run --rm -i ${QUARTUS_MAC:+--mac-address "$QUARTUS_MAC"} --user "$(id -u):$(id -g)" -e HOME=/tmp \
	-v "$PWD:/w" -w /w -v "$stub:/usr/lib/x86_64-linux-gnu/libudev.so.1.7.8:ro" \
	$mounts ${lmf:+-e LM_LICENSE_FILE=$lmf} \
	"$QUARTUS_IMAGE" "$@"
