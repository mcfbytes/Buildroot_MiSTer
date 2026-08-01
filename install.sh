#!/bin/sh
# install.sh -- convert an ordinary MiSTer installation to the MiSTer Linux
# Modernization image, in one command, from the MiSTer itself.
#
#   curl -fsSL https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/install.sh | bash
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
# WHAT IT DOES
# ---------------------------------------------------------------------------
# 1. Checks it is running on a MiSTer with a writable /media/fat.
# 2. Backs up the handful of small files in /media/fat/linux/ that a Linux
#    update overwrites (see BACKUP_FILES below) into /media/fat/linux/.mlm-backup/.
# 3. Installs Scripts/update_linux_modernization.sh onto the card.
# 4. Runs it, which sets the `update_linux = false` kill switch, fetches this
#    project's image through the stock on-device Downloader, and reboots.
#
# Everything it does is reversible: `Scripts/update_linux_modernization.sh
# --restore-stock` hands the Linux image back to the official database.
#
# Options (pipe them through with `| bash -s -- <option>`):
#   --dry-run   print exactly what would happen and change nothing
#   --yes       skip the 10-second countdown
#   --no-reboot install and update, but leave rebooting to you
#
# Environment:
#   MLM_REF          git ref to install from (default: master)
#   MLM_UPDATER_URL  override where the updater script is fetched from
#
# ---------------------------------------------------------------------------
# ON `curl | bash`
# ---------------------------------------------------------------------------
# You are piping a remote script into a shell as root. That deserves a moment's
# thought, so: this is the same trust model MiSTer's own Scripts/update.sh uses
# (it downloads dont_download.sh from raw.githubusercontent.com and executes it),
# and the anchor is HTTPS to GitHub. If you would rather read first, that is the
# better habit -- drop the pipe:
#
#   curl -fsSL https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/install.sh -o mlm.sh
#   less mlm.sh
#   sh mlm.sh
#
# This script does NOT pin a hash of the updater it downloads. Both come from the
# same repository over the same TLS connection, so a pinned hash would add no
# real assurance while guaranteeing this file goes stale on the next change to
# the updater. Said plainly rather than implied.

set -eu

MLM_REF="${MLM_REF:-master}"
RAW_BASE="https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/${MLM_REF}"
# Overridable so a fork can point this at its own copy, and so the install path
# can be exercised end to end (curl understands file:// too) without pushing.
UPDATER_URL="${MLM_UPDATER_URL:-${RAW_BASE}/board/mister/de10nano/fat-payload/Scripts/update_linux_modernization.sh}"
DB_URL="https://mcfbytes.github.io/Buildroot_MiSTer/db.json"

FAT="/media/fat"
SCRIPTS_DIR="$FAT/Scripts"
UPDATER="$SCRIPTS_DIR/update_linux_modernization.sh"
BACKUP_DIR="$FAT/linux/.mlm-backup"

# Small files in /media/fat/linux/ that the Linux update's rsync replaces. All
# of these are shipped inside every Linux image, official and ours alike, so
# they are replaced by ANY update -- this is not something this project does to
# you. They are backed up anyway because they are tiny and occasionally edited.
# linux.img / zImage_dtb / 7za are deliberately NOT here: they are the payload,
# and copying 600 MB onto an exFAT card mounted `sync` to "back up" the thing
# being replaced would be slow and pointless.
BACKUP_FILES="MidiLink.INI ppp_options u-boot.txt_example _samba.sh _user-startup.sh _wpa_supplicant.conf updateboot uboot.img"

DRY_RUN=0
ASSUME_YES=0
REBOOT_ARG=""

for arg in "$@"; do
	case "$arg" in
		--dry-run)   DRY_RUN=1 ;;
		--yes|-y)    ASSUME_YES=1 ;;
		--no-reboot) REBOOT_ARG="--no-reboot" ;;
		-h|--help)
			echo "usage: install.sh [--dry-run] [--yes] [--no-reboot]"
			echo "  piped:  curl -fsSL <url> | bash -s -- --dry-run"
			exit 0
			;;
		*)
			echo "install.sh: unknown option: $arg" >&2
			exit 2
			;;
	esac
done

say()  { echo "$*"; }
die()  { echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
rule() { echo "=================================================================="; }

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
preflight() {
	[ -d "$FAT" ] ||
		die "$FAT does not exist. This script is meant to be run ON a MiSTer, over SSH or from a terminal, not on your PC."

	command -v curl >/dev/null 2>&1 || die "curl not found."
	command -v python3 >/dev/null 2>&1 ||
		die "python3 not found. The MiSTer Downloader requires it, so a MiSTer that can update at all has it -- this system looks unusual."

	# The rootfs is read-only by design; /media/fat is the writable half.
	if ! touch "$FAT/.mlm-write-test" 2>/dev/null; then
		die "$FAT is not writable. Try: mount -o remount,rw $FAT"
	fi
	rm -f "$FAT/.mlm-write-test"

	# The Linux update needs room for an ~80 MB archive plus a 512 MiB image
	# extracted beside the one you are running. Checked here so the answer
	# arrives before the download, not after it.
	free_kb=$(df -k "$FAT" 2>/dev/null | awk 'NR==2 {print $4}') || free_kb=""
	case "$free_kb" in
		''|*[!0-9]*) : ;;
		*)
			if [ "$free_kb" -lt 716800 ]; then
				die "not enough free space on $FAT: $((free_kb / 1024)) MiB free, about 700 MiB needed. Free some space and try again."
			fi
			;;
	esac
}

installed_version() {
	if [ -f /MiSTer.version ]; then cat /MiSTer.version; else echo "unknown"; fi
}

published_version() {
	curl -fsSL --max-time 30 --retry 2 "$DB_URL" 2>/dev/null | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["linux"]["version"][-6:])
except Exception:
    raise SystemExit(1)' 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# The plan, stated before anything is touched
# ---------------------------------------------------------------------------
show_plan() {
	inst=$(installed_version)
	pub=$(published_version)

	rule
	say " MiSTer Linux Modernization -- installer"
	say " https://github.com/mcfbytes/Buildroot_MiSTer"
	rule
	say ""
	say "  Currently installed : $inst"
	if [ -n "$pub" ]; then
		say "  Will install        : $pub"
	else
		say "  Will install        : (could not reach the update channel -- check the network)"
	fi
	say "  Installing from     : $MLM_REF"
	say ""
	say "WHAT CHANGES"
	say ""
	say "  /media/fat/linux/linux.img      the root filesystem  <- replaced"
	say "  /media/fat/linux/zImage_dtb     the kernel           <- replaced"
	say "  /media/fat/linux/uboot.img      bootloader           <- replaced (byte-identical to stock)"
	say "  /media/fat/linux/MidiLink.INI, ppp_options, u-boot.txt_example,"
	say "  _samba.sh, _user-startup.sh, _wpa_supplicant.conf, updateboot"
	say "                                                       <- replaced (backed up first)"
	say "  /media/fat/linux/mt32-rom-data/, soundfonts/         <- our copies replace same-named"
	say "                                                          files; anything extra you added stays"
	say "  /media/fat/downloader.ini       ONE key changed: [MiSTer] update_linux = false."
	say "                                  Your comments, sections and databases are left alone."
	say "                                  Created (with the official database) only if absent."
	say "  /media/fat/Scripts/update_linux_modernization.sh      <- installed"
	say ""
	say "  The saved U-Boot environment (first 512 bytes of the card) is wiped by"
	say "  'updateboot'. That happens on EVERY Linux update, official ones included."
	say ""
	say "  SSH host keys change: this image generates keys per device instead of"
	say "  shipping one set to everybody, so expect a one-time host-key warning."
	say ""
	say "WHAT IS LEFT ALONE"
	say ""
	say "  /media/fat/MiSTer.ini and every other core .ini      <- NOT touched"
	say "  games/, ROMs, saves, states, config/, cores, _Arcade <- NOT touched"
	say "  /media/fat/linux/gamecontrollerdb/                   <- explicitly excluded"
	say "  /media/fat/linux/u-boot.txt                          <- yours (holds this card's MAC)"
	say "  /media/fat/linux/wpa_supplicant.conf                 <- your real Wi-Fi config;"
	say "                                                          only the _template is replaced"
	say "  /media/fat/linux/user-startup.sh, samba.sh           <- same: only the _templates ship"
	say "  hostname, hosts, interfaces, resolv.conf,"
	say "  dhcpcd.conf, fstab (in /media/fat/linux/)            <- copied into the new image"
	say ""
	say "  Your cores keep updating normally afterwards. update_all.sh and"
	say "  Scripts/update.sh simply stop touching the Linux image, in either"
	say "  direction -- that is what stops the official image overwriting this one."
	say ""
	say "TO UNDO, AT ANY TIME"
	say ""
	say "  Scripts/update_linux_modernization.sh --restore-stock"
	say "  then run your normal update. Full procedure: docs/user/rollback.md"
	say ""
	rule
}

backup_files() {
	mkdir -p "$BACKUP_DIR" 2>/dev/null || {
		say "  (could not create $BACKUP_DIR -- continuing without a backup)"
		return 0
	}
	n=0
	for f in $BACKUP_FILES; do
		if [ -f "$FAT/linux/$f" ] && [ ! -f "$BACKUP_DIR/$f" ]; then
			cp -p "$FAT/linux/$f" "$BACKUP_DIR/$f" 2>/dev/null && n=$((n + 1))
		fi
	done
	if [ "$n" -gt 0 ]; then
		say "  Backed up $n file(s) to $BACKUP_DIR"
	else
		say "  Nothing new to back up (already done, or nothing present)"
	fi
}

install_updater() {
	mkdir -p "$SCRIPTS_DIR" || die "could not create $SCRIPTS_DIR"

	tmp="/tmp/update_linux_modernization.sh.$$"
	rm -f "$tmp"

	# Capture curl's status directly. Writing this as `if ! curl ...; then rc=$?`
	# records the status of the NEGATED condition -- which is 0 -- and the error
	# message then cheerfully reports "curl exit 0" on every failure, sending
	# whoever is debugging it down the wrong path.
	rc=0
	curl -fsSL --max-time 60 --retry 3 --retry-connrefused -o "$tmp" "$UPDATER_URL" || rc=$?

	if [ "$rc" -ne 0 ]; then
		rm -f "$tmp"
		if [ "$rc" -eq 60 ] && [ -f /etc/ssl/certs/cacert.pem ]; then
			say "  Certificate check failed; retrying with this card's cacert.pem"
			curl -fsSL --cacert /etc/ssl/certs/cacert.pem --max-time 60 --retry 3 \
				-o "$tmp" "$UPDATER_URL" ||
				die "could not download the updater script."
		elif [ "$rc" -eq 60 ]; then
			die "TLS certificate verification failed and this card has no /etc/ssl/certs/cacert.pem. Run Scripts/update.sh once -- it offers an interactive certificate repair -- then try again."
		else
			die "could not download the updater script (curl exit $rc). Check the network and try again."
		fi
	fi

	# Cheap sanity checks: a captive portal or an error page must not end up
	# installed as an executable and then run as root.
	[ -s "$tmp" ] || { rm -f "$tmp"; die "the downloaded updater is empty."; }
	head -n 1 "$tmp" | grep -q '^#!' ||
		{ rm -f "$tmp"; die "the downloaded updater does not start with a shebang -- got a captive portal or an error page, not a script."; }
	grep -q 'mister_linux_modernization' "$tmp" ||
		{ rm -f "$tmp"; die "the downloaded updater does not look like the right script."; }

	mv -f "$tmp" "$UPDATER" || die "could not install $UPDATER"
	chmod 0755 "$UPDATER" || die "could not make $UPDATER executable"
	say "  Installed $UPDATER"
}

# ---------------------------------------------------------------------------
main() {
	preflight
	show_plan

	if [ "$DRY_RUN" -eq 1 ]; then
		say ""
		say "--dry-run: nothing was changed."
		exit 0
	fi

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
	say "Backing up the small files a Linux update replaces..."
	backup_files

	say ""
	say "Downloading the updater..."
	install_updater

	say ""
	say "Handing over to the updater. Do NOT power off until it finishes."
	rule
	say ""

	# exec so the updater owns the terminal, the exit status and the reboot.
	# shellcheck disable=SC2086  # REBOOT_ARG is one optional word, or empty
	exec "$UPDATER" $REBOOT_ARG
}

main
