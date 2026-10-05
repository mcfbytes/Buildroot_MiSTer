#!/bin/bash
# sinden_lightgun.sh -- download Sinden's Lightgun driver and enable it.
#
# Part of MiSTer Linux Modernization.
# https://github.com/mcfbytes/Buildroot_MiSTer
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. Distributed WITHOUT ANY WARRANTY; see <https://www.gnu.org/licenses/>.
#
# A shim, like pair_logitech.sh: the tool is /usr/sbin/mister-sinden-lightgun,
# versioned with the mono runtime and udev rule it drives. See docs/sinden-lightgun.md.

set -uo pipefail

TOOL="/usr/sbin/mister-sinden-lightgun"

if [ ! -x "$TOOL" ]; then
	cat >&2 <<EOF

  This script needs the MiSTer Linux Modernization image.

  $TOOL is not present, which means this MiSTer is
  running a different Linux image (most likely the official one). The driver
  runtime (mono, SDL 1.2, libjpeg62) and the hotplug rule live in that image,
  so there is nothing here for this script to launch.

  See https://github.com/mcfbytes/Buildroot_MiSTer

EOF
	exit 1
fi

exec "$TOOL" install
