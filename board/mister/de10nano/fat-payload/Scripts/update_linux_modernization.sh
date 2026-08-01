#!/bin/bash
# update_linux_modernization.sh -- update THIS project's Linux image (linux.img +
# zImage_dtb) from the mister_linux_modernization db.json, without ever letting the
# official distribution_mister Linux image overwrite it.
#
# Part of https://github.com/mcfbytes/Buildroot_MiSTer
#
# ---------------------------------------------------------------------------
# WHY THIS SCRIPT EXISTS
# ---------------------------------------------------------------------------
# Downloader_MiSTer applies AT MOST ONE Linux update per run. When more than one
# configured database carries a `linux` entry -- and the official
# `distribution_mister` always does -- it picks whichever database's document
# finished downloading and parsing FIRST. That is a genuine race between worker
# threads, not a priority you can configure. Relying on winning it (by keeping our
# db.json small) works most of the time and fails silently the rest of the time,
# reverting the user to the stock image on a routine `update_all.sh` run.
#
# So we do not race. Instead:
#
#   1. `update_linux = false` in the [MiSTer] section of /media/fat/downloader.ini
#      switches the Linux update OFF for every NORMAL Downloader run. Cores, ROMs,
#      MRAs, Jotego -- everything else -- keep updating exactly as before. The
#      official Linux image can no longer be applied, so it can no longer clobber
#      ours. There is nothing left to race.
#
#      Verified safe against Update All: Update_All_MiSTer preserves the [MiSTer]
#      section VERBATIM when it rewrites downloader.ini (ini_repository.py, IniAst
#      `mister_section` is re-emitted as raw text), and it only ever sets the
#      UPDATE_LINUX env var to 'false', never to 'true' (downloader_service.py
#      `_prepare_env`). It cannot turn our setting back on.
#
#   2. This script re-enables the Linux update for ONE run, for ONE database, by
#      setting UPDATE_LINUX=true (the env var is applied AFTER the ini is parsed,
#      so it overrides it -- config_reader.py `read_rest_env_and_config_file`) and
#      passing `--run-only mister_linux_modernization` so no other database is even
#      considered. Deterministic: no race, no ambiguity.
#
# `--run-only` does NOT delete anything belonging to the databases it skips. File
# removal only happens through Downloader's explicit uninstall command
# (DatabaseConfigRemover is reachable only from uninstall_service.py), and the local
# store is loaded whole and saved whole, so the skipped databases' records survive
# untouched.
#
# ---------------------------------------------------------------------------
# USAGE
# ---------------------------------------------------------------------------
#   update_linux_modernization.sh              update, reboot when one is needed
#   update_linux_modernization.sh --no-reboot  update, never reboot (print instead)
#   update_linux_modernization.sh --setup-only configure the card, do not update
#   update_linux_modernization.sh --status     show current configuration + version
#
# Safe to re-run. Safe to run before opting in -- it configures the card itself.
# To undo everything, see docs/user/rollback.md.

set -euo pipefail

readonly DB_ID="mister_linux_modernization"
readonly DB_URL="https://mcfbytes.github.io/Buildroot_MiSTer/db.json"

readonly FAT="/media/fat"
readonly BASE_INI="${FAT}/downloader.ini"
readonly DROP_IN_INI="${FAT}/downloader_${DB_ID}.ini"
readonly LAUNCHER_URL="https://raw.githubusercontent.com/MiSTer-devel/Downloader_MiSTer/main/dont_download.sh"
readonly LAUNCHER_PATH="/tmp/dont_download_${DB_ID}.sh"

MODE="update"
ALLOW_REBOOT_VALUE="1"

for arg in "$@"; do
	case "$arg" in
		--no-reboot)  ALLOW_REBOOT_VALUE="0" ;;
		--setup-only) MODE="setup" ;;
		--status)     MODE="status" ;;
		-h|--help)
			sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
			exit 0
			;;
		*)
			echo "unknown option: $arg" >&2
			echo "usage: $(basename "${BASH_SOURCE[0]}") [--no-reboot] [--setup-only] [--status]" >&2
			exit 2
			;;
	esac
done

say() { echo "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_python() {
	command -v python3 >/dev/null 2>&1 ||
		die "python3 not found. Downloader_MiSTer itself requires it, so a MiSTer that can update at all has it -- this system looks unusual."
}

# ---------------------------------------------------------------------------
# Config: make the card's configuration correct, idempotently.
#
# Both edits are surgical on purpose. downloader.ini is the USER's file: it may
# carry their own databases, comments and formatting, and Update All also writes
# to it. We never rewrite it wholesale (configparser would drop every comment) --
# we touch exactly the one key we care about and leave every other byte alone.
# ---------------------------------------------------------------------------

ensure_base_ini() {
	need_python
	python3 - "$BASE_INI" <<'PY'
import os, re, sys

path = sys.argv[1]
text = ''
if os.path.isfile(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        text = fh.read()

lines = text.splitlines(keepends=True)

def is_header(line):
    return re.match(r'\s*\[([^\]]+)\]', line)

# Locate the [MiSTer] section and, inside it, an existing update_linux key.
mister_start = None
mister_end = len(lines)
for idx, line in enumerate(lines):
    m = is_header(line)
    if not m:
        continue
    if m.group(1).strip().lower() == 'mister':
        mister_start = idx
        for j in range(idx + 1, len(lines)):
            if is_header(lines[j]):
                mister_end = j
                break
        break

WANT = 'update_linux = false\n'

if mister_start is None:
    # No [MiSTer] section at all. Prepend one; a base ini with no database
    # sections still gets distribution_mister added automatically by the
    # Downloader (config_reader.py _add_default_database), so this does NOT
    # stop cores from updating.
    block = '[MiSTer]\n' + WANT + '\n'
    text = block + text
    action = 'created [MiSTer] section with update_linux = false'
else:
    key_idx = None
    for j in range(mister_start + 1, mister_end):
        if re.match(r'\s*update_linux\s*=', lines[j], re.I):
            key_idx = j
            break
    if key_idx is None:
        lines.insert(mister_start + 1, WANT)
        text = ''.join(lines)
        action = 'added update_linux = false to the existing [MiSTer] section'
    else:
        current = lines[key_idx].split('=', 1)[1].strip().lower()
        if current == 'false':
            action = 'already correct'
        else:
            lines[key_idx] = WANT
            text = ''.join(lines)
            action = 'changed update_linux from %r to false' % current

if action != 'already correct':
    tmp = path + '.new'
    with open(tmp, 'w', encoding='utf-8') as fh:
        fh.write(text)
    os.replace(tmp, path)

print(action)
PY
}

ensure_drop_in_ini() {
	local want
	want="[${DB_ID}]
db_url = ${DB_URL}
"
	# Compare through "$(...)" on BOTH sides: command substitution strips
	# trailing newlines, so comparing a captured file against a variable that
	# still has its trailing newline never matches and would rewrite this file
	# on every single run. /media/fat is exFAT mounted `sync`, so a pointless
	# rewrite is a real (if small) cost, and reporting "written" every time
	# hides whether anything actually changed.
	if [ -f "$DROP_IN_INI" ] && [ "$(cat "$DROP_IN_INI")" = "$(printf '%s' "$want")" ]; then
		echo "already correct"
		return 0
	fi
	printf '%s' "$want" > "$DROP_IN_INI.new"
	mv -f "$DROP_IN_INI.new" "$DROP_IN_INI"
	echo "written"
}

# ---------------------------------------------------------------------------
# Download the official Downloader launcher.
#
# Mirrors Scripts/update.sh's CURL_SSL handling: some MiSTers have an expired or
# empty /etc/ssl/certs, and curl exits 60 there. We retry once with the bundled
# cacert.pem if one exists. We deliberately do NOT offer update.sh's interactive
# "run insecurely?" fallback -- this script can run unattended, and silently
# dropping TLS verification to fetch code we then execute is not a tradeoff to
# make on the user's behalf.
# ---------------------------------------------------------------------------

fetch_launcher() {
	local rc=0
	rm -f "$LAUNCHER_PATH"

	curl ${CURL_SSL:-} --fail --location --silent --show-error \
		--retry 3 --retry-connrefused \
		-o "$LAUNCHER_PATH" "$LAUNCHER_URL" || rc=$?

	if [ "$rc" -eq 60 ] && [ -f /etc/ssl/certs/cacert.pem ]; then
		say "  certificate verification failed, retrying with /etc/ssl/certs/cacert.pem"
		rc=0
		CURL_SSL="--cacert /etc/ssl/certs/cacert.pem"
		export CURL_SSL
		curl ${CURL_SSL} --fail --location --silent --show-error \
			--retry 3 --retry-connrefused \
			-o "$LAUNCHER_PATH" "$LAUNCHER_URL" || rc=$?
	fi

	if [ "$rc" -ne 0 ]; then
		case "$rc" in
			60) die "could not verify the TLS certificate while downloading the Downloader launcher. Run Scripts/update.sh once -- it has an interactive certificate repair option -- then try again." ;;
			*)  die "could not download the Downloader launcher (curl exit $rc). Check the network connection and try again." ;;
		esac
	fi

	chmod +x "$LAUNCHER_PATH"
}

show_status() {
	say "Configuration"
	say "  ${BASE_INI}"
	if [ -f "$BASE_INI" ]; then
		if grep -qiE '^\s*update_linux\s*=\s*false' "$BASE_INI"; then
			say "    update_linux = false   [OK] the official Linux image cannot overwrite ours"
		else
			say "    update_linux is NOT false   [!] run this script without --status to fix"
		fi
	else
		say "    missing   [!] run this script without --status to create it"
	fi

	say "  ${DROP_IN_INI}"
	if [ -f "$DROP_IN_INI" ]; then
		say "    present   [OK] $(grep -i '^\s*db_url' "$DROP_IN_INI" | head -1 | sed 's/^\s*//')"
	else
		say "    missing   [!] run this script without --status to create it"
	fi

	say ""
	say "Installed version"
	if [ -f /MiSTer.version ]; then
		say "  /MiSTer.version = $(cat /MiSTer.version)"
	else
		say "  /MiSTer.version is missing"
	fi
	say "  kernel          = $(uname -r)"
}

main() {
	say "=============================================================="
	say " MiSTer Linux Modernization -- update"
	say " https://github.com/mcfbytes/Buildroot_MiSTer"
	say "=============================================================="
	say ""

	if [ "$MODE" = "status" ]; then
		show_status
		exit 0
	fi

	say "Checking configuration..."
	say "  downloader.ini : $(ensure_base_ini)"
	say "  database       : $(ensure_drop_in_ini)"
	say ""
	say "  Normal updates (update_all.sh, Scripts/update.sh) will now leave the"
	say "  Linux image alone entirely -- cores and everything else still update."
	say "  This script is what updates the Linux image."
	say ""

	if [ "$MODE" = "setup" ]; then
		say "--setup-only given: configuration is done, not updating."
		exit 0
	fi

	say "Downloading the MiSTer Downloader..."
	fetch_launcher
	say ""

	# UPDATE_LINUX=true re-enables the Linux update that downloader.ini switched
	# off, for this run only. DOWNLOADER_INI_PATH points at the user's REAL ini so
	# the local store stays consistent with every normal run. --run-only means this
	# is the only database considered, so nothing can race us and nothing else is
	# touched.
	local rc=0
	DOWNLOADER_INI_PATH="$BASE_INI" \
	DOWNLOADER_LAUNCHER_PATH="$LAUNCHER_PATH" \
	UPDATE_LINUX="true" \
	ALLOW_REBOOT="$ALLOW_REBOOT_VALUE" \
	CURL_SSL="${CURL_SSL:-}" \
		"$LAUNCHER_PATH" --run-only "$DB_ID" || rc=$?

	rm -f "$LAUNCHER_PATH"

	say ""
	if [ "$rc" -ne 0 ]; then
		say "=============================================================="
		say " The Downloader exited with code $rc."
		say ""
		say " Nothing is left half-applied: the Linux image is only swapped in"
		say " as the very last step of a successful update. Your current system"
		say " is untouched and still bootable."
		say ""
		say " The log is at ${FAT}/Scripts/.config/downloader/downloader.log"
		say "=============================================================="
		exit "$rc"
	fi

	if [ -f /tmp/downloader_needs_reboot_after_linux_update ] && [ "$ALLOW_REBOOT_VALUE" = "0" ]; then
		say "=============================================================="
		say " A new Linux image was installed. REBOOT to start running it."
		say " Nothing is running from it until you do."
		say "=============================================================="
	else
		say "Done."
	fi
}

main
