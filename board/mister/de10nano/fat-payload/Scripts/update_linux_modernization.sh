#!/bin/bash
# update_linux_modernization.sh -- update this MiSTer's Linux image from the
# mister_linux_modernization database, and keep the card configured so that a
# routine update_all.sh can never put the official image back.
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
# WHY THIS SCRIPT EXISTS
# ---------------------------------------------------------------------------
# Downloader_MiSTer applies AT MOST ONE Linux image per run. When several
# configured databases carry a `linux` entry -- and the official
# distribution_mister always does -- the Downloader takes whichever appears
# first in downloader.ini's database order. Update All pins
# [distribution_mister] to the top of that file, so on any card Update All has
# ever written the official image wins. Ordering is not a defence.
#
# So this project does not compete for that slot:
#
#   1. `update_linux = false` in the [MiSTer] section of
#      /media/fat/downloader.ini turns the Linux update off for every NORMAL
#      run. config['update_linux'] has exactly one read site in the whole
#      Downloader, so false there means no database's `linux` entry is even
#      looked at -- no download, no rsync into /media/fat/linux/, no
#      `updateboot`. Cores, ROMs and MRAs are completely unaffected.
#
#   2. THIS script runs the Downloader against its own PRIVATE ini, which
#      declares one database and nothing else, with UPDATE_LINUX=true and
#      `--run-only`. One candidate, nothing to sort, nothing to race -- on
#      every Downloader build, old or new.
#
# Databases that are recorded in the shared local store but not part of this
# run are carried as "non-current", and their path claims VETO deletion. This
# run therefore cannot remove one byte belonging to distribution_mister or to
# any other database.
#
# ---------------------------------------------------------------------------
# USAGE
# ---------------------------------------------------------------------------
#   update_linux_modernization.sh                 check, and update if needed
#   update_linux_modernization.sh --no-reboot     update, never reboot
#   update_linux_modernization.sh --force         run even if versions match
#   update_linux_modernization.sh --status        report only, change nothing
#   update_linux_modernization.sh --setup-only    repair configuration only
#   update_linux_modernization.sh --restore-stock go back to the official image
#   update_linux_modernization.sh --help
#
# There are no interactive prompts anywhere: a user on a gamepad has no
# keyboard.

set -euo pipefail

readonly DB_ID="mister_linux_modernization"
readonly DB_URL="https://mcfbytes.github.io/Buildroot_MiSTer/db.json"
readonly FAT="/media/fat"
readonly SCRIPTS_DIR="$FAT/Scripts"
readonly BASE_INI="$FAT/downloader.ini"
readonly DL_CFG="$SCRIPTS_DIR/.config/downloader"
# The private ini is generated in /tmp, per run, and never persists.
#
# It can live there because nothing about the Downloader's STATE derives from
# where the ini sits: the log and .last_successful_run are built from
# base_system_path plus the ini's FILENAME STEM, not its directory. The
# directory matters for exactly one thing -- drop-in discovery globs it -- and
# /tmp has no downloader_*.ini in it, which is precisely the property we want.
# (It must NOT be /media/fat for that same reason: an ini there would drag every
# downloader_*.ini on the card into what is meant to be a Linux-only run.)
#
# Consequence worth having: this script leaves NO persistent state of its own
# anywhere. The only durable marks it makes are the one key in the user's
# downloader.ini and the image it installs.
readonly PRIVATE_INI="/tmp/$DB_ID.ini"
readonly OUR_LOG="$DL_CFG/$DB_ID.log"
readonly LOCK_DIR="/tmp/$DB_ID.lock"
readonly LAUNCHER="/tmp/${DB_ID}_dont_download.sh"
readonly LAUNCHER_URL="https://raw.githubusercontent.com/MiSTer-devel/Downloader_MiSTer/main/dont_download.sh"
readonly CACHED_LAUNCHER="$DL_CFG/downloader_latest.zip"
# Touched as the LAST statement of a successful Linux flash. This is the only
# trustworthy success signal: the Downloader's exit code never reflects a failed
# Linux update, because update_linux()'s result is not inspected upstream.
readonly FLASH_FLAG="/tmp/downloader_needs_reboot_after_linux_update"

MODE="update"
DO_REBOOT=1
FORCE=0

for arg in "$@"; do
	case "$arg" in
		--status)        MODE="status" ;;
		--setup-only)    MODE="setup" ;;
		--restore-stock) MODE="restore" ;;
		--force)         FORCE=1 ;;
		--no-reboot)     DO_REBOOT=0 ;;
		# Usage text comes from the USAGE block above, so the two can never
		# drift apart. Keep the line range in step if that block moves.
		-h|--help)       sed -n '46,52p;54,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,3\}//'; exit 0 ;;
		*) echo "update_linux_modernization.sh: unknown option: $arg" >&2; exit 2 ;;
	esac
done

[ -e "$FAT/linux/no_auto_reboot" ] && DO_REBOOT=0

say() { echo "$*"; }
die() { echo "" >&2; echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Configuration repair
# ---------------------------------------------------------------------------
# Line-oriented on purpose. A configparser round-trip would destroy every
# comment and every section Update All does not manage. Update All itself
# re-emits the [MiSTer] section and unknown sections as RAW TEXT for the same
# reason, which is exactly why a surgical edit survives its rewrites intact.
#
# The value written is always a literal word. The Downloader parses it with a
# strict truth-value grammar that RAISES on anything unrecognised, and that
# exception escapes and makes EVERY Downloader run exit 1 -- so a damaged value
# is repaired rather than left alone.
ensure_kill_switch() {
	local want="${1:-false}"
	python3 - "$BASE_INI" "$want" <<'PYEOF'
import os, re, sys

path, want = sys.argv[1], sys.argv[2]
FALSEY = ('false', 'no', 'n', 'f', 'off', '0')
TRUTHY = ('true', 'yes', 'y', 't', 'on', '1')
accept = FALSEY if want == 'false' else TRUTHY

try:
    with open(path, 'r', encoding='utf-8', errors='surrogateescape') as fh:
        lines = fh.readlines()
    existed = True
except OSError:
    lines, existed = [], False

# A final line with no terminator would otherwise be welded to whatever we
# insert after it -- '[MiSTer]' + 'update_linux = false' on ONE line, which
# configparser reads as a section header and silently drops the setting. Cards
# hand-edited on Windows, or written by a tool that omits the last newline, hit
# this. Normalising here fixes it for both the insert and the prepend path.
if lines and not lines[-1].endswith(('\n', '\r')):
    lines[-1] += '\n'

hdr = re.compile(r'^\s*\[\s*mister\s*\]\s*$', re.I)
any_hdr = re.compile(r'^\s*\[')
# configparser accepts BOTH '=' and ':' as the key/value delimiter, so a card
# carrying `update_linux : true` must be recognised and rewritten. Matching only
# '=' would leave that line in place and append a second `update_linux =` to the
# same section -- a DuplicateOptionError that makes EVERY Downloader run abort,
# including the official one, leaving the user unable to update anything at all.
kv = re.compile(r'^\s*update_linux\s*[=:]\s*(.*?)\s*$', re.I)

start = next((i for i, ln in enumerate(lines) if hdr.match(ln)), None)
if start is None:
    lines = ['[MiSTer]\n', 'update_linux = %s\n' % want, '\n'] + lines
    action = 'created [MiSTer] with update_linux = %s' % want

    # If we are CREATING the file, it must also declare the official database.
    #
    # A databases-less base ini is fine for the Downloader itself -- it auto-adds
    # distribution_mister (config_reader._add_default_database). It is NOT fine
    # for Update All, which seeds its default database set only when
    # downloader.ini does not exist. Writing a [MiSTer]-only file therefore
    # suppresses that seeding while supplying no databases of our own, and an
    # update_all.sh run afterwards can find nothing to install -- we would have
    # cost the user their cores in the act of protecting their kernel.
    #
    # Only distribution_mister, and only when creating from nothing. Adding
    # anything else (jtcores, say) to a card that already had its own
    # configuration would be us making choices for the user; the shipped
    # sdcard.img template is the right place for opinionated defaults.
    if not existed and not any(any_hdr.match(ln) for ln in lines[3:]):
        lines += [
            '\n',
            '[distribution_mister]\n',
            'db_url = https://raw.githubusercontent.com/MiSTer-devel/Distribution_MiSTer/main/db.json.zip\n',
        ]
else:
    end = next((j for j in range(start + 1, len(lines)) if any_hdr.match(lines[j])), len(lines))
    idx = next((j for j in range(start + 1, end) if kv.match(lines[j])), None)
    if idx is None:
        lines.insert(start + 1, 'update_linux = %s\n' % want)
        action = 'added update_linux = %s' % want
    else:
        cur = kv.match(lines[idx]).group(1).split(';')[0].split('#')[0].strip().lower()
        if cur in accept:
            print('unchanged')
            raise SystemExit(0)
        lines[idx] = 'update_linux = %s\n' % want
        action = "changed update_linux from '%s' to %s" % (cur, want)

if not existed:
    action = 'created %s' % path

tmp = path + '.new'
os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
with open(tmp, 'w', encoding='utf-8', errors='surrogateescape') as fh:
    fh.writelines(lines)
os.replace(tmp, path)   # atomic: a power cut cannot leave a half-written ini
print(action)
PYEOF
}

# The private ini is REGENERATED on every run, so it can never go stale.
#
#   update_linux = true   -- this run only; the user's ini is not consulted
#   file_checking         -- MUST be one of the words fastest / balanced /
#                            exhaustive / verify_integrity. The Downloader's own
#                            deprecation message suggests `file_checking = 3`;
#                            that is NOT a valid value and silently degrades to
#                            "balanced", which in steady state is downgraded to
#                            "fastest", which re-enables the unchanged-database
#                            skip. `exhaustive` is what actually keeps our
#                            database from being skipped when db.json has not
#                            changed -- the exact case where a user has been
#                            reverted to stock and wants to be put back. It
#                            costs nothing: our database declares no files.
write_private_ini() {
	cat > "$PRIVATE_INI.new" <<EOF
; Generated by Scripts/update_linux_modernization.sh -- do not edit.
; Regenerated on every run. Deleting it is harmless.
;
; Lives in /tmp on purpose and is regenerated every run. Do NOT copy it into
; /media/fat: drop-in discovery globs the directory the ini lives in, and it
; would then pull in every downloader_*.ini on the card.
[MiSTer]
update_linux = true
file_checking = exhaustive

[$DB_ID]
db_url = $DB_URL
EOF
	mv -f "$PRIVATE_INI.new" "$PRIVATE_INI"
	[ -s "$PRIVATE_INI" ] || die "could not write $PRIVATE_INI"
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------
# /MiSTer.version is exactly 6 ASCII bytes with no newline, and equals the last
# 6 characters of our db.json's linux.version by construction. It is read from
# the ROOT of the running filesystem, not from /media/fat.
installed_version() {
	if [ -f /MiSTer.version ]; then cat /MiSTer.version; else echo "unknown"; fi
}

# Some MiSTers have an empty or expired /etc/ssl/certs, where curl exits 60 on
# every HTTPS request. Scripts/update.sh handles this with an interactive repair
# prompt; we cannot prompt (a gamepad has no keyboard, and this also runs from a
# boot script), so we do the one non-interactive half: retry with the CA bundle
# the card already carries. Detected ONCE, then exported so every later curl in
# this run inherits it.
#
# We deliberately do NOT fall back to --insecure. Everything fetched here is code
# we then execute, and silently dropping TLS verification is not a decision to
# make on a user's behalf without asking.
probe_curl_ssl() {
	[ -n "${CURL_SSL:-}" ] && return 0

	local rc=0
	curl -fsS --max-time 20 -o /dev/null "$DB_URL" 2>/dev/null || rc=$?
	[ "$rc" -eq 0 ] && return 0
	# 60 is specifically "peer certificate cannot be authenticated". Anything
	# else (no route, DNS, 404, timeout) is not ours to interpret here -- let the
	# real request run and report it with its own message.
	[ "$rc" -eq 60 ] || return 0

	if [ -f /etc/ssl/certs/cacert.pem ]; then
		CURL_SSL="--cacert /etc/ssl/certs/cacert.pem"
		export CURL_SSL
		say "Note: using /etc/ssl/certs/cacert.pem (this card's CA certificates look stale)."
	else
		die "TLS certificate verification failed and this card has no /etc/ssl/certs/cacert.pem to fall back on. Run Scripts/update.sh once -- it offers an interactive certificate repair -- then try this again."
	fi
}

published_version() {
	# shellcheck disable=SC2086  # CURL_SSL carries an option PAIR and must split
	curl -fsS --location --max-time 30 --retry 2 ${CURL_SSL:-} "$DB_URL" 2>/dev/null \
		| python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["linux"]["version"][-6:])
except Exception:
    raise SystemExit(1)'
}

kill_switch_state() {
	python3 - "$BASE_INI" <<'PYEOF' 2>/dev/null || echo "unreadable"
import re, sys
try:
    lines = open(sys.argv[1], encoding='utf-8', errors='surrogateescape').readlines()
except OSError:
    print('missing'); raise SystemExit(0)
hdr = re.compile(r'^\s*\[\s*mister\s*\]\s*$', re.I)
any_hdr = re.compile(r'^\s*\[')
# MUST match ensure_kill_switch()'s delimiter set exactly. configparser accepts
# ':' as well as '=', so a card carrying `update_linux : false` is genuinely
# protected -- and reading it with an '='-only pattern would report it as absent,
# i.e. tell a protected user they are NOT protected and invite them to "fix" a
# configuration that was already correct.
kv = re.compile(r'^\s*update_linux\s*[=:]\s*(.*?)\s*$', re.I)
s = next((i for i, l in enumerate(lines) if hdr.match(l)), None)
if s is None:
    print('absent (defaults to enabled)'); raise SystemExit(0)
e = next((j for j in range(s + 1, len(lines)) if any_hdr.match(lines[j])), len(lines))
i = next((j for j in range(s + 1, e) if kv.match(lines[j])), None)
if i is None:
    print('absent (defaults to enabled)'); raise SystemExit(0)
v = kv.match(lines[i]).group(1).split(';')[0].split('#')[0].strip().lower()
print('false' if v in ('false', 'no', 'n', 'f', 'off', '0') else (v or 'empty'))
PYEOF
}

# ---------------------------------------------------------------------------
# Concurrency
# ---------------------------------------------------------------------------
# The local store is a single shared file, written by a non-atomic
# truncate-and-write with no lock anywhere, and dont_download.sh always extracts
# itself to a hardcoded /tmp path. Two Downloaders running at once can therefore
# clobber each other. /tmp/downloader_run_signal is a startup health probe, not
# a mutex, so we make our own. mkdir is atomic everywhere; busybox has no flock.
take_lock() {
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		die "another copy of this script is already running (remove $LOCK_DIR if it is not)"
	fi
	# shellcheck disable=SC2064  # expand LOCK_DIR now, on purpose
	trap "rmdir '$LOCK_DIR' 2>/dev/null || true" EXIT INT TERM

	local p cmd
	for p in /proc/[0-9]*; do
		[ "$p" = "/proc/$$" ] && continue
		[ -r "$p/cmdline" ] || continue
		cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null || true)
		case "$cmd" in
			# update_all.pyz and ua_downloader_dd.pyz are what Update All
			# actually runs -- observed on a real board, and neither matches
			# the dont_download/downloader_* patterns.
			*dont_download*|*downloader_bin*|*downloader_latest*|*update_all.pyz*|*ua_downloader*)
				die "a MiSTer Downloader run is already in progress. Wait for it to finish, then run this again." ;;
		esac
	done
}

# The Linux update needs room for the ~80 MB release .7z AND the tree it
# extracts (a 512 MiB non-sparse linux.img plus the rest of files/linux/) to
# exist at the same time as the live linux.img. linux_updater.py performs NO
# free-space check of its own on this path -- LinuxFreeSpaceReservation only
# covers a database's `files`, and ours declares none -- so `7za x` simply fails
# partway and the Downloader reports the failure without changing its exit code.
# Catch it here, where we can say something useful, instead of after an 80 MB
# download.
preflight_space() {
	# A leftover staging tree means a previous run died between extract and
	# flash; linux_updater.py never cleans it up on the user-files failure path.
	# It can be several hundred MB, and it is pure garbage -- removing it may by
	# itself free the space this run needs.
	if [ -d "$FAT/linux.update" ]; then
		say "Removing a stale $FAT/linux.update left by an earlier interrupted update"
		rm -rf "$FAT/linux.update" 2>/dev/null || true
	fi
	rm -f "$FAT/linux.7z" 2>/dev/null || true

	local need_kb=716800   # 700 MiB
	local free_kb
	free_kb=$(df -k "$FAT" 2>/dev/null | awk 'NR==2 {print $4}') || free_kb=""
	case "$free_kb" in
		''|*[!0-9]*) return 0 ;;   # unreadable: do not block on a guess
	esac

	if [ "$free_kb" -lt "$need_kb" ]; then
		die "not enough free space on $FAT: $((free_kb / 1024)) MiB available, about $((need_kb / 1024)) MiB needed.
       The update downloads an ~80 MB archive and extracts a 512 MiB filesystem
       image beside the one you are running, so it needs room for both at once.
       Free some space and run this again. Nothing has been changed."
	fi
}

fetch_launcher() {
	rm -f "$LAUNCHER" "$LAUNCHER.partial"
	# shellcheck disable=SC2086  # CURL_SSL carries an option PAIR and must split
	if curl -fL --max-time 120 --retry 3 --retry-connrefused ${CURL_SSL:-} \
			-o "$LAUNCHER.partial" "$LAUNCHER_URL" 2>/dev/null; then
		mv -f "$LAUNCHER.partial" "$LAUNCHER"
	elif [ -s "$CACHED_LAUNCHER" ]; then
		say "Could not reach GitHub; using the cached Downloader already on this card."
		cp -f "$CACHED_LAUNCHER" "$LAUNCHER"
	else
		rm -f "$LAUNCHER.partial"
		die "could not download the MiSTer Downloader, and no cached copy exists. Check the network and try again."
	fi
	chmod +x "$LAUNCHER"
	[ -s "$LAUNCHER" ] || die "the downloaded Downloader is empty"
}

# ---------------------------------------------------------------------------
# The Downloader run
# ---------------------------------------------------------------------------
run_downloader() {
	local only_db="$1" allow_reboot="$2" rc=0

	# Scrub every inherited variable that would change WHERE the store lives or
	# WHICH databases take part. These matter because this script may be started
	# from another updater's process tree. Proxy and TLS settings are kept on
	# purpose so proxied networks and certificate repair keep working.
	unset DEFAULT_BASE_PATH FORCED_BASE_PATH PC_LAUNCHER \
	      EXTRA_DROP_IN_DATABASE_FILES DEFAULT_DB_ID DEFAULT_DB_URL \
	      DOWNLOADER_LAUNCHER_PATH LOGFILE DEBUG SKIP_FREE_SPACE_CHECKS \
	      FAIL_ON_FILE_ERROR ROTATE_LOGS LOGLEVEL COMMIT DOWNLOADER_OUTPUT \
	      MISTER_ENVIRONMENT 2>/dev/null || true

	# DOWNLOADER_INI_PATH is taken verbatim and outranks the launcher-derived
	# path. Its filename stem also names our log and our .last_successful_run
	# marker, which is why the private ini is NOT called downloader.ini: that
	# would rotate away the user's own downloader.log and its five backups.
	export DOWNLOADER_INI_PATH="$PRIVATE_INI"
	# Strictly the word `true`; the Downloader compares against that exact
	# string, so 1 / yes / on all mean FALSE.
	export UPDATE_LINUX="true"
	# Only 0, 1 and 2 are legal; anything else -- including an empty string --
	# is a traceback. 0 = never: the Downloader prints its recommendation and we
	# stay in control of the screen and of the reboot.
	export ALLOW_REBOOT="$allow_reboot"
	export PYTHONUTF8=1

	# --run-only is the fail-CLOSED assertion, not just a filter. If the private
	# ini were ever missing or empty, the Downloader would auto-add
	# distribution_mister (it does that whenever the base ini declares no
	# databases) and this run would install the STOCK image. With --run-only, an
	# unconfigured id is rejected with exit code 10 long before the Linux update
	# is reached.
	"$LAUNCHER" --run-only "$only_db" || rc=$?
	return "$rc"
}
do_status() {
	local inst pub ks
	inst=$(installed_version)
	ks=$(kill_switch_state)
	echo "MiSTer Linux Modernization -- status"
	echo ""
	echo "  Installed Linux image : $inst"
	echo "  Kernel                : $(uname -r)"
	if pub=$(published_version); then
		echo "  Latest published      : $pub"
		if [ "$inst" = "$pub" ]; then
			echo "                          (up to date)"
		else
			echo "                          (an update is available)"
		fi
	else
		echo "  Latest published      : could not check (no network?)"
	fi
	echo ""
	if [ "$ks" = "false" ]; then
		echo "  Official Linux updates: DISABLED   <- this image is protected"
	else
		echo "  Official Linux updates: $ks"
		echo "                          <- NOT PROTECTED. A routine update_all.sh"
		echo "                             run could replace this Linux image."
		echo "                             Fix it with:  $0 --setup-only"
	fi
	echo "  downloader.ini        : $BASE_INI"
	echo "  Update channel        : $DB_URL"
	echo "  Last run log          : $OUR_LOG"
	echo ""
}

do_restore_stock() {
	take_lock
	echo "This hands the Linux image back to the official MiSTer database."
	echo ""
	local r
	r=$(ensure_kill_switch true) || die "could not update $BASE_INI"
	echo "  downloader.ini: $r"
	rm -f "$PRIVATE_INI"
	echo ""
	echo "That is the whole revert. Nothing re-applies the setting behind you:"
	echo "this script is the only thing that ever writes it, and it only runs when"
	echo "you run it."
	echo ""
	echo "Now run a normal update -- Scripts > update_all.sh, or Scripts >"
	echo "update.sh -- and the official Linux image will install over this one."
	echo ""
	echo "To come back later: run this script again."
	echo ""
}

do_update() {
	local inst pub r rc=0 expected=0 allow_reboot=0

	take_lock

	say "MiSTer Linux Modernization -- Linux image update"
	say ""

	# Keep the card's configuration correct even on a plain update run, so a
	# user who only ever runs this script still stays protected.
	r=$(ensure_kill_switch false) || die "could not update $BASE_INI"
	[ "$r" = "unchanged" ] || say "Repaired downloader.ini: $r"

	if [ "$MODE" = "setup" ]; then
		write_private_ini
		say ""
		say "Configuration is in place. Nothing was downloaded."
		return 0
	fi

	inst=$(installed_version)
	say "  Installed : $inst"

	probe_curl_ssl
	if pub=$(published_version); then
		say "  Available : $pub"
	else
		die "could not read the update channel at $DB_URL. Check the network and try again."
	fi
	say ""

	if [ "$inst" = "$pub" ] && [ "$FORCE" -eq 0 ]; then
		# Nothing to do -- and, importantly, the shared local store is not
		# touched at all in this case.
		say "Already up to date. Nothing to do."
		return 0
	fi

	if [ "$inst" = "$pub" ]; then
		# --force reaches the Downloader, but the Downloader applies its OWN
		# version comparison (`/MiSTer.version` against the last 6 characters of
		# the db entry) and will skip the flash for exactly the same reason we
		# nearly did. So a flash is NOT expected here, and demanding one would
		# make every --force run on an up-to-date box end in the alarming
		# "UPDATE DID NOT HAPPEN" banner and a non-zero exit. --force is for
		# re-running the machinery (after a reverted card, or to check the
		# channel end to end), not an override of the Downloader's own check.
		expected=0
		say "Versions match, but --force was given. Running anyway."
		say "(The Downloader compares versions itself, so it may still decide"
		say " there is nothing to install. That is not an error.)"
	else
		expected=1
		say "Updating the Linux image: $inst -> $pub"
	fi
	say ""
	say "  Do NOT turn off the MiSTer, and do not cancel this script,"
	say "  until it says it has finished."
	say ""

	preflight_space
	write_private_ini
	fetch_launcher

	# The flag is a /tmp file that an earlier run in this same boot may have left
	# behind. Clear it so that it describes only OUR run.
	rm -f "$FLASH_FLAG"

	set +e
	run_downloader "$DB_ID" "$allow_reboot"
	rc=$?
	set -e
	rm -f "$LAUNCHER"

	echo ""
	if [ "$rc" -ne 0 ]; then
		echo "=============================================================="
		echo " The Downloader exited with code $rc."
		echo ""
		echo " Nothing is left half-applied: the Linux image is swapped in"
		echo " only as the very last step of a successful update, so the"
		echo " system you are running now is untouched and still bootable."
		echo ""
		echo " Log: $OUR_LOG"
		echo "=============================================================="
		exit "$rc"
	fi

	if [ "$expected" -eq 1 ] && [ ! -e "$FLASH_FLAG" ]; then
		echo "=============================================================="
		echo " UPDATE DID NOT HAPPEN"
		echo ""
		echo " The Downloader finished without reporting an error, but no new"
		echo " Linux image was installed. The system you are running now is"
		echo " untouched."
		echo ""
		echo " Log: $OUR_LOG"
		echo "=============================================================="
		exit 1
	fi

	if [ ! -e "$FLASH_FLAG" ]; then
		# Only reachable with expected=0, i.e. --force on an up-to-date box:
		# the Downloader ran and decided, correctly, that there was nothing to
		# install. Say so plainly rather than claiming an update.
		echo "The Downloader found nothing to install. Already on $inst."
		echo ""
		return 0
	fi

	echo "=============================================================="
	echo " Linux image updated: $inst -> $pub"
	echo "=============================================================="
	echo ""

	if [ "$DO_REBOOT" -eq 0 ]; then
		echo "A REBOOT IS REQUIRED for the new image to take effect."
		echo "Reboot from the OSD menu when you are ready."
		echo ""
		return 0
	fi

	local i
	echo "Rebooting in 10 seconds. Do not turn off the MiSTer."
	for i in 10 9 8 7 6 5 4 3 2 1; do
		printf '\r  %2d ' "$i"
		sleep 1
	done
	printf '\r      \n'
	sync; sync
	reboot
}

case "$MODE" in
	status)  do_status ;;
	restore) do_restore_stock ;;
	*)       do_update ;;
esac
