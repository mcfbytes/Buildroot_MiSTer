#!/bin/sh
# uninstall.sh -- hand the Linux image back to the official MiSTer database.
#
#   curl -fsSL https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/uninstall.sh | sh
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
# WHAT UNINSTALLING ACTUALLY IS
# ---------------------------------------------------------------------------
# One line in one file. Opting in set `update_linux = false` in the [MiSTer]
# section of /media/fat/downloader.ini, which stops EVERY normal Downloader run
# from applying ANY Linux image -- that is the whole mechanism that kept the
# official image from replacing this one. Setting it back to `true` re-arms the
# official database, and the next `update_all.sh` or `Scripts/update.sh` run
# installs the stock image over this one.
#
# Nothing re-applies the setting behind you. This project installs no boot
# scripts, no daemons and no state files; the updater is the only thing that
# ever writes that key, and it only runs when you run it. So there is no marker
# to clear and nothing to fight.
#
# It then INSTALLS the official image, rather than leaving that to your next
# normal update. That is deliberate, and it is the difference between this
# working and appearing to work.
#
# The Downloader skips a database whose content has not changed since the last
# run -- can_skip_db() in db_utils.py returns true whenever file_checking is
# FASTEST, which is the steady-state default -- and a SKIPPED database's `linux`
# entry is never even looked at. So "flip the key, then run update_all.sh" can
# silently do nothing at all on a card that updated recently, leaving you on this
# image believing you had reverted. Observed on real hardware, which is why this
# script does the revert itself: its own ini, file_checking = exhaustive so
# nothing is skipped, and --run-only distribution_mister so only the official
# database is consulted.
#
# --no-flash restores the old behaviour (flip the setting and stop) if you would
# rather run the update yourself.
#
# It is also not the only way. If you still have the updater on the card,
# `Scripts/update_linux_modernization.sh --restore-stock` does exactly the same
# thing without needing the network -- and this script prefers it when present,
# so there is one implementation of the edit rather than two.
#
# Options:
#   --remove-script    also delete this project's Scripts entries
#                      (update_linux_modernization.sh, check_storage.sh and
#                      pair_logitech.sh)
#   --restore-backups  put the files in linux/.mlm-backup/ back (see below)
#   --yes              skip the 10-second countdown
#
# ---------------------------------------------------------------------------
# ABOUT THE BACKUPS, AND WHEN TO RESTORE THEM
# ---------------------------------------------------------------------------
# install.sh copies the small files a Linux update replaces -- MidiLink.INI,
# ppp_options, the `_`-prefixed templates, updateboot, uboot.img -- into
# /media/fat/linux/.mlm-backup/ before anything touches them. The updater
# additionally saves your original downloader.ini there as downloader.ini.orig,
# once, before its first edit.
#
# TIMING MATTERS. Those files live in /media/fat/linux/, which EVERY Linux update
# rsyncs over -- including the official one you are about to install. Restoring
# them now would just have them overwritten again minutes later. So:
#
#     1. run this script            (re-arms the official image)
#     2. run your normal update     (installs it, reboots)
#     3. uninstall.sh --restore-backups   <-- only now
#
# downloader.ini.orig is deliberately NOT restored automatically, even with
# --restore-backups. It is a snapshot from before you opted in, and Update All
# and you have very likely added databases to that file since; putting the old
# copy back would silently drop them. The path is printed so you can diff it and
# decide.

set -eu

FAT="/media/fat"
BASE_INI="$FAT/downloader.ini"
UPDATER="$FAT/Scripts/update_linux_modernization.sh"
CHECK_STORAGE="$FAT/Scripts/check_storage.sh"
PAIR_LOGITECH="$FAT/Scripts/pair_logitech.sh"
PRIVATE_INI="/tmp/mister_linux_modernization.ini"
BACKUP_DIR="$FAT/linux/.mlm-backup"
BASE_INI_BACKUP="$BACKUP_DIR/downloader.ini.orig"
STOCK_DB_ID="distribution_mister"
STOCK_DB_URL="https://raw.githubusercontent.com/MiSTer-devel/Distribution_MiSTer/main/db.json.zip"
REVERT_INI="/tmp/mlm_revert.ini"
LAUNCHER="/tmp/mlm_revert_dont_download.sh"
LAUNCHER_URL="https://raw.githubusercontent.com/MiSTer-devel/Downloader_MiSTer/main/dont_download.sh"
FLASH_FLAG="/tmp/downloader_needs_reboot_after_linux_update"

REMOVE_SCRIPT=0
ASSUME_YES=0
RESTORE_BACKUPS=0
NO_FLASH=0

for arg in "$@"; do
	case "$arg" in
		--remove-script)   REMOVE_SCRIPT=1 ;;
		--no-flash)        NO_FLASH=1 ;;
		--restore-backups) RESTORE_BACKUPS=1 ;;
		--yes|-y)        ASSUME_YES=1 ;;
		-h|--help)
			echo "usage: uninstall.sh [--remove-script] [--restore-backups] [--no-flash] [--yes]"
			echo "  --no-flash          only flip the setting; do not install the"
			echo "                      official image now"
			echo "  --restore-backups   put linux/.mlm-backup/ files back; run this"
			echo "                      AFTER the official image has been installed"
			exit 0
			;;
		*) echo "uninstall.sh: unknown option: $arg" >&2; exit 2 ;;
	esac
done

say()  { echo "$*"; }
die()  { echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
rule() { echo "=================================================================="; }

rule
say " MiSTer Linux Modernization -- uninstall"
rule
say ""
say "  This re-arms the official Linux image. It changes ONE key:"
say ""
say "      $BASE_INI   ->   [MiSTer] update_linux = true"
say ""
say "  Nothing is flashed now. On your next normal update -- update_all.sh or"
say "  Scripts/update.sh -- the official image installs over this one, and the"
say "  MiSTer reboots into it."
say ""
say "  Your cores, ROMs, saves, config and MiSTer.ini are not touched."
if [ "$REMOVE_SCRIPT" -eq 1 ]; then
	say "  --remove-script: $UPDATER,"
	say "                   $CHECK_STORAGE and"
	say "                   $PAIR_LOGITECH will also be deleted."
fi
say ""
rule

if [ "$ASSUME_YES" -eq 0 ]; then
	say ""
	say "Starting in 10 seconds. Press Ctrl-C now to abort."
	i=10
	while [ "$i" -gt 0 ]; do
		printf '\r  %2d ' "$i"
		sleep 1
		i=$((i - 1))
	done
	printf '\r      \n'
fi
say ""

[ -d "$FAT" ] || die "$FAT does not exist. Run this ON the MiSTer, not on your PC."

if [ -x "$UPDATER" ]; then
	# One implementation of the edit, not two.
	say "Using the installed updater's --restore-stock..."
	"$UPDATER" --restore-stock
else
	say "Updater not on the card; editing $BASE_INI directly."
	[ -f "$BASE_INI" ] ||
		die "$BASE_INI does not exist, so nothing ever disabled Linux updates here. There is nothing to undo."
	command -v python3 >/dev/null 2>&1 ||
		die "python3 not found, and it is needed to edit the ini safely. Set [MiSTer] update_linux = true in $BASE_INI by hand instead."

	python3 - "$BASE_INI" <<'PYEOF' || die "could not update the ini. Is /media/fat writable?"
import os, re, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='surrogateescape') as fh:
    lines = fh.readlines()
if lines and not lines[-1].endswith(('\n', '\r')):
    lines[-1] += '\n'

hdr = re.compile(r'^\s*\[\s*mister\s*\]\s*$', re.I)
any_hdr = re.compile(r'^\s*\[')
# '=' and ':' are both valid configparser delimiters.
kv = re.compile(r'^\s*update_linux\s*[=:]\s*(.*?)\s*$', re.I)

s = next((i for i, l in enumerate(lines) if hdr.match(l)), None)
if s is None:
    print('no [MiSTer] section -- nothing was disabling Linux updates')
    raise SystemExit(0)
e = next((j for j in range(s + 1, len(lines)) if any_hdr.match(lines[j])), len(lines))
i = next((j for j in range(s + 1, e) if kv.match(lines[j])), None)
if i is None:
    print('no update_linux key -- nothing was disabling Linux updates')
    raise SystemExit(0)

cur = kv.match(lines[i]).group(1).split(';')[0].split('#')[0].strip().lower()
if cur in ('true', 'yes', 'y', 't', 'on', '1'):
    print('already true -- official Linux updates were already enabled')
    raise SystemExit(0)

lines[i] = 'update_linux = true\n'
tmp = path + '.new'
with open(tmp, 'w', encoding='utf-8', errors='surrogateescape') as fh:
    fh.writelines(lines)
os.replace(tmp, path)
print("changed update_linux from '%s' to true" % cur)
PYEOF
fi

rm -f "$PRIVATE_INI"

if [ "$NO_FLASH" -eq 0 ]; then
	command -v curl >/dev/null 2>&1 || die "curl not found."
	say ""
	say "Installing the official Linux image..."

	cat > "$REVERT_INI" <<EOF
; Generated by uninstall.sh -- regenerated every run, safe to delete.
; file_checking = exhaustive is load-bearing: at the default (fastest) the
; Downloader skips a database whose content has not changed, and a skipped
; database's linux entry is never considered -- so the revert would silently
; not happen.
[MiSTer]
update_linux = true
file_checking = exhaustive

[$STOCK_DB_ID]
db_url = $STOCK_DB_URL
EOF

	rm -f "$LAUNCHER"
	# shellcheck disable=SC2086  # CURL_SSL is an option PAIR and must word-split
	curl -fsSL --max-time 120 --retry 3 ${CURL_SSL:-} -o "$LAUNCHER" "$LAUNCHER_URL" ||
		die "could not download the MiSTer Downloader. Check the network, or re-run with --no-flash and update by hand."
	chmod +x "$LAUNCHER"
	rm -f "$FLASH_FLAG"

	rc=0
	DOWNLOADER_INI_PATH="$REVERT_INI" UPDATE_LINUX="true" ALLOW_REBOOT="0" \
		"$LAUNCHER" --run-only "$STOCK_DB_ID" || rc=$?
	rm -f "$LAUNCHER"

	if [ "$rc" -ne 0 ]; then
		die "the Downloader exited with code $rc. Nothing is half-applied -- the image is swapped in only as the last step of a successful update, so you are still on the current one."
	fi
	if [ ! -e "$FLASH_FLAG" ]; then
		die "the Downloader reported no error but installed no image. You are still on the current one. Check /media/fat/Scripts/.config/downloader/mlm_revert.log"
	fi
	say ""
	say "Official Linux image installed."
fi

if [ "$RESTORE_BACKUPS" -eq 1 ]; then
	say ""
	if [ -d "$BACKUP_DIR" ]; then
		n=0
		for f in "$BACKUP_DIR"/*; do
			[ -f "$f" ] || continue
			base=$(basename "$f")
			# Never auto-restore the ini snapshot -- see the header.
			[ "$base" = "downloader.ini.orig" ] && continue
			cp -p "$f" "$FAT/linux/$base" 2>/dev/null && n=$((n + 1))
		done
		say "Restored $n file(s) from $BACKUP_DIR into $FAT/linux/"
		if [ -f "$BASE_INI_BACKUP" ]; then
			say "Your pre-opt-in downloader.ini is at $BASE_INI_BACKUP"
			say "  (not restored automatically -- you have probably added databases since;"
			say "   diff it against the live file and merge by hand if you want it back)"
		fi
	else
		say "No backups found at $BACKUP_DIR -- nothing to restore."
	fi
fi

# All of this project's Scripts, together -- install.sh installs them as one
# set, so --remove-script takes them as one too (ADR 0026). check_storage.sh and
# pair_logitech.sh are only launchers for rootfs tools that are about to be
# replaced by the stock image anyway, so leaving them behind would just be menu
# entries that print "this needs the MiSTer Linux Modernization image".
if [ "$REMOVE_SCRIPT" -eq 1 ]; then
	for _f in "$UPDATER" "$CHECK_STORAGE" "$PAIR_LOGITECH"; do
		[ -e "$_f" ] || continue
		rm -f "$_f" && say "Removed $_f"
	done
fi

say ""
rule
if [ "$NO_FLASH" -eq 1 ]; then
	say " Setting flipped, nothing installed (--no-flash)."
	say ""
	say " To finish, run a normal update -- but note it may SKIP the official"
	say " database if its content has not changed since your last update, in"
	say " which case nothing happens. Re-run this script without --no-flash to"
	say " have it install the official image directly instead."
else
	say " Done. The official Linux image is installed."
	say ""
	say " REBOOT to start running it -- nothing is running from it until you do."
fi
say ""
say " Re-running install.sh puts this project's image back."
if [ "$RESTORE_BACKUPS" -eq 0 ] && [ -d "$BACKUP_DIR" ]; then
	say ""
	say " Customised MidiLink.INI, ppp_options or similar? Backups are in"
	say " $BACKUP_DIR. Restore them AFTER the official"
	say " image is installed -- it rewrites linux/ too -- with:"
	say ""
	say "     uninstall.sh --restore-backups"
fi
rule
