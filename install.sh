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
# 3. Installs this project's Scripts onto the card:
#    update_linux_modernization.sh (updates the image from now on),
#    check_storage.sh (checks the exFAT data partition for damage, ADR 0026) and
#    mount_smb.sh (mounts a NAS share; nothing distributes Scripts_MiSTer's
#    cifs_mount.sh, so this is how an SMB mount works out of the box --
#    docs/cifs-mount-fscache-probe.md).
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
#   MLM_REF                git ref to install from (default: master)
#   MLM_UPDATER_URL        override where the updater script is fetched from
#   MLM_CHECK_STORAGE_URL  override where check_storage.sh is fetched from
#   MLM_MOUNT_SMB_URL      override where mount_smb.sh is fetched from
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
# Same override shape as UPDATER_URL, for the same two reasons (forks, and
# exercising the install path end to end against a file:// URL).
CHECK_STORAGE_URL="${MLM_CHECK_STORAGE_URL:-${RAW_BASE}/board/mister/de10nano/fat-payload/Scripts/check_storage.sh}"
# Same override shape again, same two reasons.
MOUNT_SMB_URL="${MLM_MOUNT_SMB_URL:-${RAW_BASE}/board/mister/de10nano/fat-payload/Scripts/mount_smb.sh}"
DB_URL="https://mcfbytes.github.io/Buildroot_MiSTer/db.json"

FAT="/media/fat"
SCRIPTS_DIR="$FAT/Scripts"
UPDATER="$SCRIPTS_DIR/update_linux_modernization.sh"
CHECK_STORAGE="$SCRIPTS_DIR/check_storage.sh"
MOUNT_SMB="$SCRIPTS_DIR/mount_smb.sh"
BACKUP_DIR="$FAT/linux/.mlm-backup"

# These three are ONE SET, and every path that touches them treats them as one:
# install.sh installs all three, `update_linux_modernization.sh --setup-only`
# replaces any that went missing, `uninstall.sh --remove-script` removes all
# three, and scripts/fetch-sdcard-payload.sh stages all three into sdcard.img.
# Scripts this project ships must not arrive by two different mechanisms
# (ADR 0026).

# Small files in /media/fat/linux/ that the Linux update's rsync replaces.
#
# Every one of these is genuinely in scope, checked rather than assumed: stock's
# files/linux/ is {linux.img, zImage_dtb, uboot.img, updateboot, MidiLink.INI,
# ppp_options, u-boot.txt_example, _samba.sh, _user-startup.sh,
# _wpa_supplicant.conf, gamecontrollerdb/, mt32-rom-data/, soundfonts/}
# (docs/verification/stock-release-20250402.md), and our release archive is that
# same tree with linux.img/zImage_dtb overlaid and 7za added (release.yml,
# "Assemble release tree"). The flash-phase rsync copies all of it. So these are
# replaced by ANY Linux update, official or ours -- not something this project
# does to you.
#
# Not listed, deliberately:
#   gamecontrollerdb/  -- the rsync excludes it outright, so it is never touched.
#   mt32-rom-data/, soundfonts/  -- rsynced, but directories, and potentially
#       large. Without --delete, anything you ADDED survives; only a shipped file
#       you edited in place would be overwritten. Copying them here could mean
#       hundreds of MB on a sync-mounted exFAT card, which is not a trade worth
#       making for that case.
#   linux.img, zImage_dtb, 7za  -- the payload itself.
#
# In practice rsync's size+mtime quick check skips an untouched file entirely, so
# the ones that actually get rewritten are the ones somebody customised -- which
# is exactly what this backup is for.
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

	# This script is POSIX sh, but the updater it hands off to is #!/bin/bash --
	# so check for bash HERE rather than letting the exec fail at the very end
	# with an unhelpful "not found". Stock ships /usr/bin/bash (it is what
	# Scripts/wifi.sh runs under), so this should never fire; it exists so that
	# when it does, the message names the actual problem.
	command -v bash >/dev/null 2>&1 ||
		die "bash not found. The updater this installs runs under bash, and every MiSTer image ships it -- this system looks unusual."

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

       2. Run \`Scripts/update.sh\` once and accept its certificate repair. It
          works, and it is what MiSTer has always done. Two things worth knowing
          before you pick it: the bundle is fetched with verification DISABLED
          (its sha256 comes from the same unverified connection, so it catches a
          truncated download, not an attacker), and it is installed into
          /etc/ssl/certs -- where a tampered bundle would be persistent, silent,
          and trusted by every program on the box from then on. It also deletes
          the existing certificates BEFORE downloading the new ones, so if that
          download fails you are left with none at all.

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
	say "  /media/fat/linux/linux.img    the root filesystem   <- replaced"
	say "  /media/fat/linux/zImage_dtb   the kernel            <- replaced"
	say "  /media/fat/linux/7za          7-Zip 26.02 replaces the 2016 p7zip"
	say "  /media/fat/downloader.ini     ONE key: [MiSTer] update_linux = false"
	say "                                (your original is saved to linux/.mlm-backup/)"
	say "  /media/fat/Scripts/update_linux_modernization.sh   <- installed"
	say "  /media/fat/Scripts/check_storage.sh                <- installed"
	say "  /media/fat/Scripts/mount_smb.sh                    <- installed"
	say ""
	say "  That is the whole of it. Our release archive IS the stock archive with"
	say "  those first three files swapped in, so everything else under linux/ --"
	say "  MidiLink.INI, ppp_options, uboot.img, updateboot, the _templates,"
	say "  mt32-rom-data/, soundfonts/ -- is rewritten with BYTE-IDENTICAL content."
	say "  A no-op unless you had customised one, and the small ones are copied to"
	say "  linux/.mlm-backup/ first in case you had."
	say ""
	say "  Two side effects worth knowing, both of which any Linux update causes:"
	say "  the saved U-Boot environment (first 512 bytes of the card) is wiped by"
	say "  updateboot, and SSH host keys change -- this image generates them per"
	say "  device instead of shipping one set to everybody, so expect a one-time"
	say "  host-key warning."
	say ""
	say "  AFTERWARDS, routine updates stop touching /media/fat/linux/ at all:"
	say "  update_linux = false means no Linux update runs unless you run the"
	say "  updater. These files become more stable than they are on stock, where"
	say "  every official Linux update rewrites them."
	say ""
	say "WHAT IS LEFT ALONE"
	say ""
	say "  MiSTer.ini and every core .ini, games/, ROMs, saves, states, config/,"
	say "  cores, _Arcade/                                     <- NOT touched"
	say "  linux/gamecontrollerdb/                             <- rsync-excluded"
	say "  your live u-boot.txt (this card MAC), wpa_supplicant.conf,"
	say "  user-startup.sh, samba.sh   -- only the _templates ship, so yours stay"
	say "  linux/{hostname,hosts,interfaces,resolv.conf,dhcpcd.conf,fstab}"
	say "                              -- copied INTO the new image before it goes live"
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

# Fetch one Scripts/ entry and install it. Was install_updater(); generalized so
# every script this project ships arrives by exactly this path (ADR 0026).
install_one_script() {
	url="$1"; dest="$2"; marker="$3"
	name="${dest##*/}"

	tmp="/tmp/${name}.$$"
	rm -f "$tmp"

	# Capture curl's status directly. Writing this as `if ! curl ...; then rc=$?`
	# records the status of the NEGATED condition -- which is 0 -- and the error
	# message then cheerfully reports "curl exit 0" on every failure, sending
	# whoever is debugging it down the wrong path.
	rc=0
	# shellcheck disable=SC2086  # CURL_SSL is an option PAIR and must word-split
	curl -fsSL --max-time 60 --retry 3 --retry-connrefused ${CURL_SSL:-} -o "$tmp" "$url" || rc=$?

	if [ "$rc" -ne 0 ]; then
		rm -f "$tmp"
		if [ "$rc" -eq 60 ] && [ -f /etc/ssl/certs/cacert.pem ]; then
			say "  Certificate check failed; retrying with this card's cacert.pem"
			curl -fsSL --cacert /etc/ssl/certs/cacert.pem --max-time 60 --retry 3 \
				-o "$tmp" "$url" ||
				die "could not download $name."
		elif [ "$rc" -eq 60 ]; then
			die "TLS certificate verification failed and this card has no /etc/ssl/certs/cacert.pem. Run Scripts/update.sh once -- it offers an interactive certificate repair -- then try again."
		else
			die "could not download $name (curl exit $rc). Check the network and try again."
		fi
	fi

	# Cheap sanity checks: a captive portal or an error page must not end up
	# installed as an executable and then run as root.
	[ -s "$tmp" ] || { rm -f "$tmp"; die "the downloaded $name is empty."; }
	head -n 1 "$tmp" | grep -q '^#!' ||
		{ rm -f "$tmp"; die "the downloaded $name does not start with a shebang -- got a captive portal or an error page, not a script."; }
	grep -q "$marker" "$tmp" ||
		{ rm -f "$tmp"; die "the downloaded $name does not look like the right script."; }

	mv -f "$tmp" "$dest" || die "could not install $dest"
	chmod 0755 "$dest" || die "could not make $dest executable"
	say "  Installed $dest"
}

# THE list of Scripts/ entries this project installs. Adding one is a line here.
#
# Deliberately straight-line calls rather than a loop over a list variable: a
# `... | while read` loop runs in a SUBSHELL, where install_one_script's die()
# exits only that subshell and the install would carry on past a failure it had
# already reported. Three calls do not need a parser.
install_scripts() {
	mkdir -p "$SCRIPTS_DIR" || die "could not create $SCRIPTS_DIR"
	install_one_script "$UPDATER_URL"       "$UPDATER"       'mister_linux_modernization'
	install_one_script "$CHECK_STORAGE_URL" "$CHECK_STORAGE" 'mister-fsck-exfat'
	install_one_script "$MOUNT_SMB_URL"     "$MOUNT_SMB"     'kernel_supports_cifs'
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
	say "Downloading this project's Scripts..."
	install_scripts

	say ""
	say "Handing over to the updater. Do NOT power off until it finishes."
	rule
	say ""

	# exec so the updater owns the terminal, the exit status and the reboot.
	# shellcheck disable=SC2086  # REBOOT_ARG is one optional word, or empty
	exec "$UPDATER" $REBOOT_ARG
}

main
