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
#   --dry-run       print exactly what would happen and change nothing
#   --yes           skip the 10-second countdown
#   --no-reboot     install and update, but leave rebooting to you
#   --bootstrap-ca  ONLY if this card's CA certificates are too old to verify
#                   anything: fetch a CA bundle over an UNVERIFIED connection and
#                   use it for this run only. Read the warning it prints.
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
BOOTSTRAP_CA=0
REBOOT_ARG=""
CA_BUNDLE_URL="https://curl.se/ca/cacert.pem"
CA_BUNDLE_TMP="/tmp/mlm-cacert.pem"

for arg in "$@"; do
	case "$arg" in
		--dry-run)   DRY_RUN=1 ;;
		--bootstrap-ca) BOOTSTRAP_CA=1 ;;
		--yes|-y)    ASSUME_YES=1 ;;
		--no-reboot) REBOOT_ARG="--no-reboot" ;;
		-h|--help)
			echo "usage: install.sh [--dry-run] [--yes] [--no-reboot] [--bootstrap-ca]"
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

	# curl, specifically -- not wget. The wget on a MiSTer is the BusyBox applet,
	# built with no TLS support at all: it answers every https:// URL with
	# "not an http or ftp url" and exits 1. Verified on hardware. Stock ships a
	# real /usr/bin/curl (linked against libcurl/libssl), and MiSTer's own
	# Scripts/update.sh uses curl exclusively for the same reason.
	command -v curl >/dev/null 2>&1 ||
		die "curl not found. It ships with every MiSTer image -- this system looks unusual. (BusyBox wget is not an alternative here: it has no HTTPS support.)"
	command -v python3 >/dev/null 2>&1 ||
		die "python3 not found. The MiSTer Downloader requires it, so a MiSTer that can update at all has it -- this system looks unusual."

	# Probe TLS before anything else, so a card with a stale certificate store
	# gets a straight answer instead of discovering it three steps later as
	# "could not reach the update channel". curl exit 60 is specifically
	# "peer certificate cannot be authenticated"; MiSTer images have shipped
	# expired CA bundles before, which is why Scripts/update.sh carries an
	# interactive repair for exactly this.
	tls_rc=0
	curl -fsS --max-time 20 -o /dev/null "$DB_URL" 2>/dev/null || tls_rc=$?
	if [ "$tls_rc" -eq 60 ]; then
		# Try the card's own bundle first -- but VERIFY it actually helps before
		# accepting it. On an old card that file is often exactly what expired,
		# and silently adopting it would just move the same failure downstream.
		if [ -f /etc/ssl/certs/cacert.pem ] &&
		   curl -fsS --cacert /etc/ssl/certs/cacert.pem --max-time 20 -o /dev/null "$DB_URL" 2>/dev/null; then
			CURL_SSL="--cacert /etc/ssl/certs/cacert.pem"
			export CURL_SSL
			say "Note: this card's default CA path failed; using /etc/ssl/certs/cacert.pem instead."
			say ""
		elif [ "$BOOTSTRAP_CA" -eq 1 ]; then
			bootstrap_ca
		else
			die "TLS certificate verification failed, and this card has no
       /etc/ssl/certs/cacert.pem to fall back on. Its CA certificates are too
       old to verify anything -- a root filesystem frozen years ago carries a
       trust store frozen years ago.

       Nothing on this card can currently make a trustworthy HTTPS connection,
       so there is no way to fix this over the network from the card without
       some leap of faith. Your options, safest first:

       1. DO IT FROM A MACHINE WITH WORKING TLS. Download the installer there,
          check it, and copy it to the card (over SMB, scp, or by putting the SD
          card in that machine):

            curl -fsSL $RAW_BASE/install.sh -o mlm.sh
            sha256sum mlm.sh        # compare against the repo on github.com
            # copy mlm.sh to /media/fat/Scripts/ then, on the MiSTer:
            sh /media/fat/Scripts/mlm.sh --bootstrap-ca

       2. Run \`Scripts/update.sh\` once and accept its certificate repair. Note
          what that actually does: fetches a CA bundle with verification DISABLED
          and installs it into /etc/ssl/certs. It works, and it is what MiSTer
          has always done -- but a tampered bundle there is persistent and
          silent, and would be trusted by every program on the box from then on.

       3. Re-run this installer with --bootstrap-ca. Same unverified fetch, but
          used for THIS RUN ONLY and never written to the system trust store, so
          the exposure ends when the run does.

       This is, for what it is worth, a fairly complete argument for why this
       project exists."
		fi
	fi

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

# Fetch a CA bundle over an UNVERIFIED connection and use it for this run only.
#
# There is no clever way around the leap of faith: a card whose trust store has
# expired cannot verify anything, including whatever would repair it. What we CAN
# control is the blast radius, and that is the whole design of this function.
#
# We deliberately do NOT do what Scripts/update.sh does -- fetch the bundle
# insecurely and install it into /etc/ssl/certs. That is the worse of the two
# available risks: a CA injected into the system trust store is trusted by every
# program on the box, for every connection, from then on, and it looks completely
# clean afterwards. Getting a tampered script instead is a one-shot compromise of
# a box whose root password is `1` and whose rootfs is about to be replaced
# wholesale anyway.
#
# So: bundle to /tmp, used for this run, gone at reboot. The system trust store
# is not touched, and the rootfs is not remounted rw.
#
# You should only need this ONCE. The image being installed ships a current CA
# bundle and refreshes it every release, so once this run finishes the card's
# certificates are fixed properly and permanently -- which is rather the point.
bootstrap_ca() {
	say ""
	rule
	say " WARNING -- UNVERIFIED DOWNLOAD"
	rule
	say ""
	say "  This card's CA certificates cannot verify anything, so the CA bundle"
	say "  itself has to be fetched with verification turned off:"
	say ""
	say "    $CA_BUNDLE_URL"
	say ""
	say "  If someone is intercepting this connection they can hand you their own"
	say "  bundle, and everything this run then 'verifies' would be verified"
	say "  against them. On a trusted home network that is a remote risk; on a"
	say "  public or shared one it is not."
	say ""
	say "  Limiting the damage: the bundle goes to $CA_BUNDLE_TMP and is used for"
	say "  THIS RUN ONLY. Nothing is written to /etc/ssl/certs, so no attacker CA"
	say "  can outlive this run. (Scripts/update.sh's repair does write to the"
	say "  system trust store, which is why this does not reuse it.)"
	say ""
	say "  If you would rather not: Ctrl-C, and fetch the installer from a machine"
	say "  whose TLS works, then copy it to the card."
	say ""
	rule

	if [ "$ASSUME_YES" -eq 0 ]; then
		say ""
		say "  Continuing in 10 seconds. Ctrl-C to stop."
		i=10
		while [ "$i" -gt 0 ]; do
			printf '\r  %2d ' "$i"
			sleep 1
			i=$((i - 1))
		done
		printf '\r      \n'
	fi

	rm -f "$CA_BUNDLE_TMP"
	curl -fsSL --insecure --max-time 60 --retry 2 -o "$CA_BUNDLE_TMP" "$CA_BUNDLE_URL" ||
		die "could not download the CA bundle from $CA_BUNDLE_URL."
	[ -s "$CA_BUNDLE_TMP" ] || die "the downloaded CA bundle is empty."
	grep -q 'BEGIN CERTIFICATE' "$CA_BUNDLE_TMP" ||
		die "the downloaded CA bundle does not contain any certificates -- got a captive portal or an error page."

	CURL_SSL="--cacert $CA_BUNDLE_TMP"
	export CURL_SSL

	# Prove it actually helps before continuing, rather than failing later with a
	# confusing message.
	# shellcheck disable=SC2086  # CURL_SSL is an option PAIR and must word-split
	curl -fsS $CURL_SSL --max-time 20 -o /dev/null "$DB_URL" ||
		die "even with the fetched CA bundle, $DB_URL could not be verified. Something else is wrong -- check the date/time on this MiSTer (a badly wrong clock invalidates every certificate)."

	say ""
	say "  CA bundle fetched and working, for this run only."
	say ""
	# Deliberately NOT removed here: CURL_SSL is exported and inherited across
	# the exec into the updater, which has its own downloads to make and would
	# otherwise hit the same wall. /tmp is a tmpfs, so the bundle is gone at the
	# reboot this install ends with -- which is the lifetime we want.
}

installed_version() {
	if [ -f /MiSTer.version ]; then cat /MiSTer.version; else echo "unknown"; fi
}

published_version() {
	# shellcheck disable=SC2086  # CURL_SSL is an option PAIR and must word-split
	curl -fsSL --max-time 30 --retry 2 ${CURL_SSL:-} "$DB_URL" 2>/dev/null | python3 -c 'import json,sys
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
	# shellcheck disable=SC2086  # CURL_SSL is an option PAIR and must word-split
	curl -fsSL --max-time 60 --retry 3 --retry-connrefused ${CURL_SSL:-} -o "$tmp" "$UPDATER_URL" || rc=$?

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
