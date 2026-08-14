#!/bin/bash
# check_storage.sh -- check the MiSTer data partition (exFAT) for damage, and
# offer to repair it on the next boot if anything turns up.
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
# The real tool is /usr/sbin/mister-fsck-exfat, in the read-only rootfs, for two
# reasons that a copy living here on the FAT card would break (ADR 0026):
#
#   1. It is the tool you reach for when THIS partition is damaged. Anything
#      stored here is unavailable in exactly the case it is needed.
#
#   2. It hands a request to the initramfs, which performs the actual repair
#      during boot. Both ends ship inside one linux.img and therefore cannot
#      drift. A Scripts/ copy updated on its own could write a request that the
#      running initramfs does not act on -- silently doing nothing on a box the
#      user was just told is about to repair itself.
#
# So this stays a launcher: stable, and no reason to ever update it.
#
# ---------------------------------------------------------------------------
# HOW IT GETS ONTO A CARD
# ---------------------------------------------------------------------------
# By exactly the same route as Scripts/update_linux_modernization.sh, which is
# the point -- two Scripts this project ships should not arrive by two different
# mechanisms:
#
#   * install.sh                        -- onboarding, fetches both
#   * update_linux_modernization.sh     -- replaces either if it went missing
#   * scripts/fetch-sdcard-payload.sh   -- stages both into sdcard.img
#   * uninstall.sh --remove-script      -- removes both
#
# An earlier revision had an /etc/init.d script copy this out of the rootfs on
# boot. It worked, but it invented a rootfs-to-exFAT sync convention that
# nothing else in MiSTer follows, and generalizing it to cover both Scripts
# would have been a false generalization: the updater is image-independent and
# manages its own updates, while this file is a version-locked launcher that
# never needs updating. Same destination, one mechanism, no new convention.

set -uo pipefail

TOOL="/usr/sbin/mister-fsck-exfat"

if [ ! -x "$TOOL" ]; then
	cat >&2 <<EOF

  This script needs the MiSTer Linux Modernization image.

  $TOOL is not present, which means this MiSTer is running
  a different Linux image (most likely the official one). The repair half of
  this feature lives in that image's initramfs, so there is nothing here for
  this script to drive.

  See https://github.com/mcfbytes/Buildroot_MiSTer

EOF
	exit 1
fi

exec "$TOOL" "$@"
