#!/bin/sh
# Installed by MiSTer Linux Modernization -- https://github.com/mcfbytes/Buildroot_MiSTer
#
# Safe to delete, and safe to replace with your own: this file is only ever
# created when it does not already exist, and nothing rewrites it afterwards.
#
# WHY IT IS HERE
# --------------
# /etc/init.d/S99user runs this file, and that init script is byte-identical in
# this project's Linux image and in the official one. This file lives on the FAT
# data partition, which survives a root filesystem replacement, and the official
# Linux update copies only `_user-startup.sh` (with the underscore) and runs
# without --delete -- so this file is never removed or overwritten by it.
#
# That makes it the one place we can still run code after this project's image
# has been replaced by the official one. All it does is notice that, and say so.
# It never installs or flashes anything.
#
# NOT staged onto the shipped sdcard.img: /etc/init.d/S05mlm deploys it
# create-if-absent on first boot, so a user who already has their own
# user-startup.sh keeps it.

[ "$1" = "start" ] || exit 0

MLM_STATE=/media/fat/Scripts/.config/mister_linux_modernization/state
MLM_DIR=/media/fat/Scripts/.config/mister_linux_modernization

[ -r "$MLM_STATE" ] || exit 0

MLM_VERSION=
# shellcheck source=/dev/null
. "$MLM_STATE" 2>/dev/null || exit 0
[ -n "$MLM_VERSION" ] || exit 0

CURRENT=unknown
[ -r /MiSTer.version ] && CURRENT=$(cat /MiSTer.version)

if [ "$CURRENT" != "$MLM_VERSION" ] && [ ! -e "$MLM_DIR/deliberate-rollback" ]; then
	printf '\n'
	printf '****************************************************************\n'
	printf '*  MiSTer Linux Modernization: THIS CARD WAS REVERTED.\n'
	printf '*\n'
	printf '*  Running Linux image : %s\n' "$CURRENT"
	printf '*  Expected            : %s\n' "$MLM_VERSION"
	printf '*\n'
	printf '*  Something replaced this Linux image -- almost always the\n'
	printf '*  official one, applied by a routine core update.\n'
	printf '*\n'
	printf '*  To put it back:  Scripts > update_linux_modernization\n'
	printf '****************************************************************\n'
	printf '\n'
	mkdir -p "$MLM_DIR" 2>/dev/null
	{
		echo "when=$(date -u 2>/dev/null)"
		echo "running=$CURRENT"
		echo "expected=$MLM_VERSION"
	} > "$MLM_DIR/REVERTED" 2>/dev/null
fi

# If a user script was set aside when this file was installed, chain to it.
[ -x "$MLM_DIR/user-startup-chain.sh" ] && "$MLM_DIR/user-startup-chain.sh" "$@"
exit 0
