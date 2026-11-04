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
# A shim, like pair_logitech.sh: the tool is /usr/sbin/mister-sinden-lightgun. Not put
# on cards by default: only images built with BR2_PACKAGE_SINDEN_LIGHTGUN have the tool.

set -uo pipefail

TOOL="/usr/sbin/mister-sinden-lightgun"

if [ ! -x "$TOOL" ]; then
	cat >&2 <<EOF

  This script needs a MiSTer Linux Modernization image built with
  Sinden Lightgun support.

  $TOOL is not present. The standard image does not
  include it (the driver runtime, mono, is large and untested with a gun), and
  the official image never has. An image built with BR2_PACKAGE_SINDEN_LIGHTGUN
  carries the runtime and the hotplug rule this script launches.

  See https://github.com/mcfbytes/Buildroot_MiSTer/blob/master/docs/sinden-lightgun.md

EOF
	exit 1
fi

exec "$TOOL" install
