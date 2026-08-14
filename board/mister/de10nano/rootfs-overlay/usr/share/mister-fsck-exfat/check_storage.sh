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
# THIS FILE IS THE ONE COPY. It lives in the rootfs and is deployed to
# /media/fat/Scripts/check_storage.sh from two places, both of which read it
# from right here so the two can never drift:
#
#   * /etc/init.d/S94storagecheck -- installs it on boot if the card does not
#     already have it, which is how EXISTING users get the Scripts-menu entry
#     when they update the Linux image.
#   * scripts/fetch-sdcard-payload.sh -- stages it into sdcard.img's payload,
#     so a freshly flashed card has the entry before its first boot finishes.

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
