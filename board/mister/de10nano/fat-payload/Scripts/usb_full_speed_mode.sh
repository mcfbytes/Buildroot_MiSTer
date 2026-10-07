#!/bin/bash
# usb_full_speed_mode.sh -- turn USB full-speed mode (dwc2.fs_ddma) on or off.
#
# Part of MiSTer Linux Modernization.
# https://github.com/mcfbytes/Buildroot_MiSTer
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. Distributed WITHOUT ANY WARRANTY; see <https://www.gnu.org/licenses/>.
#
# A launcher, like check_storage.sh: the tool ships in the rootfs with the kernel
# option it drives (ADR 0026, docs/dwc2-usb-irq.md).

set -uo pipefail

TOOL="/usr/sbin/mister-usb-full-speed"

if [ ! -x "$TOOL" ]; then
	cat >&2 <<EOF

  This script needs the MiSTer Linux Modernization image.

  $TOOL is not present, which means this MiSTer is
  running a different Linux image (most likely the official one). Full-speed
  mode is a kernel option of that image, so there is nothing here to switch.

  See https://github.com/mcfbytes/Buildroot_MiSTer

EOF
	exit 1
fi

exec "$TOOL" "$@"
