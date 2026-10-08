#!/bin/bash
# password_login.sh -- turn root password login over SSH and FTP on or off.
#
# Part of MiSTer Linux Modernization.
# https://github.com/mcfbytes/Buildroot_MiSTer
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. Distributed WITHOUT ANY WARRANTY; see <https://www.gnu.org/licenses/>.
#
# A launcher, like check_storage.sh: the tool lives in the rootfs (ADR 0031,
# docs/ssh-ftp-parity.md §1.4).

set -uo pipefail

TOOL="/usr/sbin/mister-password-login"

if [ ! -x "$TOOL" ]; then
	cat >&2 <<EOF

  This script needs the MiSTer Linux Modernization image.

  $TOOL is not present, which means this MiSTer is
  running a different Linux image (most likely the official one). The tool
  ships inside that image, so there is nothing here to run.

  See https://github.com/mcfbytes/Buildroot_MiSTer

EOF
	exit 1
fi

exec "$TOOL" "$@"
