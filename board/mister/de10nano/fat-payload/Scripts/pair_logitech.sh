#!/bin/bash
# pair_logitech.sh -- pair a Logitech keyboard or mouse to a Unifying receiver.
#
# Part of MiSTer Linux Modernization.
# https://github.com/mcfbytes/Buildroot_MiSTer
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. Distributed WITHOUT ANY WARRANTY; see <https://www.gnu.org/licenses/>.
#
# ---------------------------------------------------------------------------
# THIS FILE IS DELIBERATELY A SHIM. Do not grow it.
# ---------------------------------------------------------------------------
# The real tool is /usr/sbin/mister-pair-logitech, in the read-only rootfs, for
# the same reason check_storage.sh keeps its logic there (ADR 0026): the tool is
# version-locked to something else that ships inside linux.img -- here, the
# ltunify build whose command-line grammar it drives and whose exit-status quirk
# it works around. A Scripts/ copy updated on its own could invoke a flag the
# installed ltunify does not have, and the failure would surface as a confusing
# error in the middle of a pairing window.
#
# So this stays a launcher: stable, and no reason to ever update it.
#
# ---------------------------------------------------------------------------
# HOW IT GETS ONTO A CARD
# ---------------------------------------------------------------------------
# By exactly the same route as the other two Scripts this project ships. They
# are ONE SET and every path treats them as one (ADR 0026):
#
#   * install.sh                        -- onboarding, fetches all three
#   * update_linux_modernization.sh     -- replaces any that went missing
#   * scripts/fetch-sdcard-payload.sh   -- stages all three into sdcard.img
#   * uninstall.sh --remove-script      -- removes all three
#
# ---------------------------------------------------------------------------
# WHY IT PASSES NO ARGUMENTS
# ---------------------------------------------------------------------------
# Because the person running this may have no keyboard -- the one they are
# pairing IS the keyboard, and they reached the Scripts menu with a gamepad. The
# tool's no-argument default is therefore "pair", and it completes without
# asking anything when there is exactly one usable receiver. Everything else it
# can do (list, unpair, info) is for an SSH session, where typing is possible.

set -uo pipefail

TOOL="/usr/sbin/mister-pair-logitech"

if [ ! -x "$TOOL" ]; then
	cat >&2 <<EOF

  This script needs the MiSTer Linux Modernization image.

  $TOOL is not present, which means this MiSTer is
  running a different Linux image (most likely the official one). The pairing
  tool and the ltunify binary it drives both live in that image, so there is
  nothing here for this script to launch.

  See https://github.com/mcfbytes/Buildroot_MiSTer

EOF
	exit 1
fi

exec "$TOOL" "$@"
