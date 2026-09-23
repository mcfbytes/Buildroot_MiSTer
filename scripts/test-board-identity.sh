#!/usr/bin/env bash
#
# Unit test for assert_board(), the board-identity check that install.sh and
# update_linux_modernization.sh run before anything can reach a flash step
# (ADR 0027 Decision 4, docs/downloader-contract.md §13).
#
# Both scripts carry the same block between "--- board identity" markers; this
# asserts the two copies are byte-identical, then runs the block against
# device-tree fixtures under dash (install.sh's POSIX sh) and bash -eu -o
# pipefail (the updater's shell), plus BusyBox sh when it is installed.
#
# Usage: scripts/test-board-identity.sh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"
UPDATER="$ROOT/board/mister/de10nano/fat-payload/Scripts/update_linux_modernization.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok()  { printf 'PASS  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*" >&2; fails=$((fails + 1)); }

extract() { sed -n '/^# --- board identity/,/^# --- end board identity ---$/p' "$1"; }

extract "$INSTALL" >"$WORK/install.blk"
extract "$UPDATER" >"$WORK/updater.blk"
[ -s "$WORK/install.blk" ] || { echo "FATAL: no board-identity block in $INSTALL" >&2; exit 2; }
if cmp -s "$WORK/install.blk" "$WORK/updater.blk"; then
	ok "install.sh and the updater carry the same board-identity block"
else
	bad "board-identity blocks differ between install.sh and the updater"
	diff -u "$WORK/install.blk" "$WORK/updater.blk" >&2 || true
fi

# Each call site must run the check: first statement of preflight() / do_update().
calls() { sed -n "/^$2() {/,/^}/p" "$1" | head -n "$3" | grep -qx $'\tassert_board'; }
if calls "$INSTALL" preflight 5; then ok "install.sh preflight() calls assert_board"
else bad "install.sh preflight() does not call assert_board"; fi
if calls "$UPDATER" do_update 4; then ok "updater do_update() calls assert_board"
else bad "updater do_update() does not call assert_board"; fi

# Fixtures: /proc/device-tree/compatible is NUL-separated and NUL-terminated.
fx() { printf '%b' "$2" >"$WORK/$1"; }
fx de10-ours  'terasic,de10-nano\0altr,socfpga-cyclone5\0altr,socfpga\0'
fx de10-stock 'altr,socfpga-cyclone5\0altr,socfpga\0'
fx de25       'intel,socfpga-agilex5-socdk\0intel,socfpga-agilex5\0'
fx prefix     'altr,socfpga-cyclone5x\0altr,socfpga\0'
fx empty      ''

# run_case <label> <fixture> <pass|die> <shell and its flags...>
run_case() {
	local label=$1 fixture=$2 want=$3; shift 3
	local got rc=0
	# shellcheck disable=SC2016  # expanded by the shell under test
	got=$(MLM_DT_COMPATIBLE="$WORK/$fixture" "$@" -c '
		die() { echo "DIED: $*"; exit 1; }
		. "$0"; assert_board; echo SURVIVED' "$WORK/install.blk" 2>&1) || rc=$?
	case "$want:$rc" in
	pass:0) ok "$label: $fixture accepted" ;;
	die:1)  case "$got" in *"Nothing was changed."*) ok "$label: $fixture refused" ;;
	        *) bad "$label: $fixture refused without the expected message: $got" ;; esac ;;
	*)      bad "$label: $fixture expected $want, rc=$rc: $got" ;;
	esac
}

shells=()
command -v dash >/dev/null 2>&1 && shells+=("dash")
command -v busybox >/dev/null 2>&1 && shells+=("busybox sh")
shells+=("bash -eu -o pipefail")
for sh in "${shells[@]}"; do
	# shellcheck disable=SC2086  # $sh is a command plus its flags
	{
		run_case "$sh" de10-ours  pass $sh
		run_case "$sh" de10-stock pass $sh
		run_case "$sh" de25       die  $sh
		run_case "$sh" prefix     die  $sh
		run_case "$sh" empty      die  $sh
		run_case "$sh" missing    die  $sh
	}
done

if [ "$fails" -ne 0 ]; then
	echo "RESULT: FAIL ($fails)"; exit 1
fi
echo "RESULT: PASS"
