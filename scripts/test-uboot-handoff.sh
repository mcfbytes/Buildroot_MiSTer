#!/bin/sh
#
# test-uboot-handoff.sh — fixture proof for scripts/check-uboot-handoff.sh
# (docs/uboot-tasks.md U4b; docs/uboot-mainline-port.md Sec 3.2a, Sec 6).
#
# Two fixtures, both run against the pinned stock `uboot.img`
# (sha256 e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64,
# fetched elsewhere by scripts/fetch-sdcard-payload.sh's STOCK_UBOOT_SHA256 --
# this script does not fetch it itself, see STOCK_UBOOT_IMG below):
#
#   1. PASS -- the carried fork's `qts/*.h` (work/U-Boot_MiSTer, commit
#      8dcc3484) must find all seven handoff tables in the stock blob's SPL
#      copy 0, at exactly the offsets plan Sec 3.2a lists. This is the
#      positive proof that the stock binary was built from these headers.
#
#   2. FAIL -- pristine mainline 2026.07's OWN `qts/*.h` (extracted fresh
#      from the pinned dl/uboot/u-boot-2026.07.tar.bz2 tarball, never the
#      carried/patched copy) must NOT find four of the seven tables --
#      `sys_mgr_init_table` and IOCSR chains 0-2, the values MiSTer
#      deliberately replaced (plan Sec 3.2) -- while still finding the other
#      three (chain3, ac_rom_init, inst_rom_init: proven never to have
#      diverged). This negative run is the whole point of the gate: it
#      proves check-uboot-handoff.sh can actually detect the wrong headers
#      landing in a build, not just rubber-stamp whatever tree it is given
#      -- the one failure mode a cold-boot smoke test cannot catch (plan
#      Sec 3.2a's payoff paragraph). Its transcript is printed verbatim,
#      delimited, for docs/verification/uboot-mainline.md to quote later.
#
# Neither fixture builds anything or touches a board (plan Sec 7, Sec 8).
#
# Deliberately not `set -e`: both fixtures must run and be judged even if
# one behaves unexpectedly, so the report shows the whole picture in one
# pass (same rationale as scripts/test-ntp-kick.sh and scripts/
# test-timezone.sh).
#
# Environment overrides (all optional; defaults match this repo/session):
#   FORK_QTS_DIR     directory holding the carried fork's qts/*.h.
#                    Default: work/U-Boot_MiSTer/board/terasic/de10-nano/qts
#                    (the read-only fork checkout at commit 8dcc3484).
#   UBOOT_TARBALL    the pinned mainline U-Boot source tarball -- used ONLY
#                    to extract ITS OWN qts/*.h for fixture 2, never built.
#                    Default: dl/uboot/u-boot-2026.07.tar.bz2
#   STOCK_UBOOT_IMG  the reference stock uboot.img both fixtures run
#                    against (sha256 e2d46cf9...62a64 expected; not
#                    reverified here -- that is fetch-sdcard-payload.sh's
#                    job, this script only reads whatever path it is given).
#                    Default: /mnt/source/uboot-wave-a/stock/mister-payload/linux/uboot.img
#
# Usage: scripts/test-uboot-handoff.sh
# Exit: 0 = both fixtures behaved exactly as documented above, 1 = a fixture
#       behaved unexpectedly (each such case named on stderr as a FAIL
#       line), 2 = usage/IO/setup error -- a fixture input is missing or the
#       tarball has no de10-nano qts/*.h members. A setup error is a
#       repo/environment problem, not a finding about the check script.

set -u

prog=${0##*/}
scriptdir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -- "$scriptdir/.." && pwd)
check="$scriptdir/check-uboot-handoff.sh"

: "${FORK_QTS_DIR:=$repo_root/work/U-Boot_MiSTer/board/terasic/de10-nano/qts}"
: "${UBOOT_TARBALL:=$repo_root/dl/uboot/u-boot-2026.07.tar.bz2}"
: "${STOCK_UBOOT_IMG:=/mnt/source/uboot-wave-a/stock/mister-payload/linux/uboot.img}"

fail=0

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }

[ -x "$check" ]          || { echo "$prog: missing or not executable: $check" >&2; exit 2; }
[ -d "$FORK_QTS_DIR" ]   || { echo "$prog: FORK_QTS_DIR not found: $FORK_QTS_DIR" >&2; exit 2; }
[ -f "$UBOOT_TARBALL" ]  || { echo "$prog: UBOOT_TARBALL not found: $UBOOT_TARBALL" >&2; exit 2; }
[ -f "$STOCK_UBOOT_IMG" ] || { echo "$prog: STOCK_UBOOT_IMG not found: $STOCK_UBOOT_IMG" >&2; exit 2; }

workdir=$(mktemp -d) || { echo "$prog: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$workdir"' EXIT

echo "$prog: extracting pristine mainline qts/*.h from $UBOOT_TARBALL"
members=$(tar -tjf "$UBOOT_TARBALL" | grep -E '/board/terasic/de10-nano/qts/[^/]+\.h$')
if [ -z "$members" ]; then
	echo "$prog: no board/terasic/de10-nano/qts/*.h members in $UBOOT_TARBALL" >&2
	exit 2
fi
printf '%s\n' "$members" | tar -xjf "$UBOOT_TARBALL" -C "$workdir" -T -
pristine_qts_dir=$(find "$workdir" -type d -name qts | head -n1)
[ -n "$pristine_qts_dir" ] || { echo "$prog: extraction did not produce a qts/ directory" >&2; exit 2; }
note "fork qts dir:     $FORK_QTS_DIR"
note "pristine qts dir: $pristine_qts_dir"
note "stock uboot.img:  $STOCK_UBOOT_IMG"

# --- Fixture 1: fork headers must PASS, at plan Sec 3.2a's exact offsets ---
echo
echo "$prog: === fixture 1 (PASS expected): fork qts/*.h vs stock uboot.img ==="
rc1=0
out1=$("$check" "$FORK_QTS_DIR" "$STOCK_UBOOT_IMG" "$STOCK_UBOOT_IMG" 2>&1) || rc1=$?
printf '%s\n' "$out1"
echo "$prog: fixture 1 exit=$rc1"

if [ "$rc1" -eq 0 ]; then
	ok "fixture 1 exited 0 (PASS), as expected"
else
	bad "fixture 1 exited $rc1, expected 0 -- the fork's own headers must pass against the stock blob built from them"
fi

for pair in \
	'sys_mgr_init_table:0x0aac8' \
	'iocsr_scan_chain0_table:0x096b8' \
	'iocsr_scan_chain1_table:0x09718' \
	'iocsr_scan_chain2_table:0x097f0' \
	'iocsr_scan_chain3_table:0x09868' \
	'ac_rom_init:0x090f8' \
	'inst_rom_init:0x094bc'
do
	table=${pair%%:*}
	offset=${pair#*:}
	case $out1 in
	*"$table @ $offset in"*) ok "fixture 1: $table @ $offset matches plan Sec 3.2a" ;;
	*) bad "fixture 1: $table not reported at $offset (plan Sec 3.2a)" ;;
	esac
done

# --- Fixture 2: pristine mainline headers must FAIL, naming 4 tables ---
echo
echo "$prog: === fixture 2 (FAIL expected): pristine mainline qts/*.h vs stock uboot.img ==="
rc2=0
out2=$("$check" "$pristine_qts_dir" "$STOCK_UBOOT_IMG" "$STOCK_UBOOT_IMG" 2>&1) || rc2=$?
echo "$prog: ---- BEGIN fixture 2 transcript (verbatim; for docs/verification/uboot-mainline.md) ----"
printf '%s\n' "$out2"
echo "$prog: ---- END fixture 2 transcript ----"
echo "$prog: fixture 2 exit=$rc2"

if [ "$rc2" -eq 1 ]; then
	ok "fixture 2 exited 1 (FAIL), as expected -- pristine mainline headers must NOT pass"
else
	bad "fixture 2 exited $rc2, expected 1"
fi

for table in sys_mgr_init_table iocsr_scan_chain0_table iocsr_scan_chain1_table iocsr_scan_chain2_table; do
	case $out2 in
	*"$table NOT FOUND in"*) ok "fixture 2: $table correctly reported NOT FOUND (diverged, plan Sec 3.2)" ;;
	*) bad "fixture 2: $table was not reported as missing (expected absent from the stock blob)" ;;
	esac
done

for table in iocsr_scan_chain3_table ac_rom_init inst_rom_init; do
	case $out2 in
	*"$table @"*) ok "fixture 2: $table still found (never diverged, plan Sec 3.2)" ;;
	*) bad "fixture 2: $table unexpectedly not found (it never diverged, plan Sec 3.2)" ;;
	esac
done

echo
if [ "$fail" -eq 0 ]; then
	echo "$prog: both fixtures behaved as documented"
	exit 0
else
	echo "$prog: TEST FAILURE -- see FAIL lines above" >&2
	exit 1
fi
