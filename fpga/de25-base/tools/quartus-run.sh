#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs a command in Altera's pinned Quartus Pro container (docs/de25-base-image.md §4).
#
# usage: quartus-run.sh COMMAND [ARGS...]   (the current directory is mounted at /w)
# env:   QUARTUS_LICENSE  licence file on the host (required for a compile)
#        QUARTUS_MAC      the MAC that licence was issued for (default 02:de:25:00:00:01)
#        QUARTUS_IMAGE    override the pinned image
set -eu

: "${QUARTUS_IMAGE:=alterafpga/quartus-pro:25.3.1-patch1.02-agilex5}"
: "${QUARTUS_MAC:=02:de:25:00:00:01}"
[ $# -ge 1 ] || { echo "usage: ${0##*/} COMMAND [ARGS...]" >&2; exit 2; }
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

lic=
if [ -n "${QUARTUS_LICENSE:-}" ]; then
	[ -f "$QUARTUS_LICENSE" ] || { echo "${0##*/}: no licence at $QUARTUS_LICENSE" >&2; exit 1; }
	lic=$(CDPATH='' cd -- "$(dirname -- "$QUARTUS_LICENSE")" && pwd)/$(basename -- "$QUARTUS_LICENSE")
fi

# The image's libudev aborts in FlexLM's host-ID probe; mount a stub over it (built once, here).
stub="$PWD/.quartus-run/libudev-stub.so"
if [ ! -f "$stub" ] || [ "$here/udev-stub.c" -nt "$stub" ]; then
	mkdir -p "${stub%/*}"
	${CC:-cc} -shared -fPIC -O2 -Wl,-soname,libudev.so.1 -o "$stub" "$here/udev-stub.c"
fi

exec docker run --rm -i --mac-address "$QUARTUS_MAC" --user "$(id -u):$(id -g)" -e HOME=/tmp \
	-v "$PWD:/w" -w /w -v "$stub:/usr/lib/x86_64-linux-gnu/libudev.so.1.7.8:ro" \
	${lic:+-v "$lic:/opt/license.dat:ro" -e LM_LICENSE_FILE=/opt/license.dat} \
	"$QUARTUS_IMAGE" "$@"
