#!/usr/bin/env bash
#
# check-kernel-defconfig-sync.sh — lockstep assertion between the kernel-only
# base defconfig and the main image defconfig (docs/rt-beta-kernel.md §2,
# ADR 0021 as amended 2026-07-18).
#
# configs/mister_kernel_defconfig deliberately COPIES the main defconfig's
# toolchain and kernel stanzas (its header says why). A copy can drift, and the
# failure mode of drift is the quiet kind: a kernel variant built by a
# different toolchain (wrong -mcpu, wrong headers) or from different sources
# than the image its modules are merged into. Nothing at build time compares
# the two files — so this script is that comparison, and it must stay cheap
# enough to run before any cache or build work (it reads two tracked files and
# nothing else).
#
# What it asserts:
#   1. Every BR2_ symbol DEFINED IN BOTH files carries the identical value.
#      Symbols defined in only one file are fine by design (the kernel
#      defconfig has no packages; the main defconfig has no BR2_INIT_NONE).
#   2. Sentinel presence: the kernel defconfig still carries the four symbols
#      no rewrite of it may lose (arch, CPU, headers series, toolchain C++) —
#      the same fail-loud-on-degenerate-input posture as the toolchain
#      fingerprint in .github/actions/buildroot-build/action.yml.
#   3. Family name-set equality: kconfig CHOICE symbols encode their value in
#      the symbol NAME (BR2_KERNEL_HEADERS_6_18 vs _6_19, BR2_cortex_a9 vs
#      _a7), so a headers or CPU bump in one file DROPS the old name and adds a
#      new one — no symbol exists in both files to disagree, and check 1 alone
#      provably passes on exactly the drift this script exists to catch. For
#      each family such a choice lives in, the set of defined symbol names must
#      therefore be identical in both files.
#
# Comments are stripped with the SAME sed idiom as that action's fingerprint
# step (both files are heavily annotated). That stripping also drops
# `# BR2_FOO is not set` lines — NOT because they are comments to kconfig
# (they are not: `conf --defconfig` parses them as an explicit =n, and the
# kernel defconfig's own `# BR2_PACKAGE_BUSYBOX is not set` is LOAD-BEARING
# exactly that way, per its comment there — do not "clean them up") — but
# because a symbol deliberately =n in one file while set in the other is a
# DESIGNED divergence here (the kernel-only config suppresses what the main
# image wants, BusyBox being the live example), so comparing them would make
# this check cry wolf; the sentinel and family-set asserts below are what
# guard against a stanza vanishing or drifting by rename instead. Values are
# split on the FIRST '=' only: several values legitimately contain '=' (the main
# defconfig's ext2 MKFS_OPTIONS).
#
# Where this runs:
#   * .github/actions/buildroot-build — for every variant != main, before any
#     cache restore, so drift dies in seconds instead of 2 hours in.
#   * build.yml's `build` job — as a lint next to lint-kernel-patches.sh, so
#     drift also fails a main-only change that edits the main defconfig
#     without mirroring.
#   * By hand: scripts/check-kernel-defconfig-sync.sh (no arguments).
#     BOARD=<name> (or a single positional <name>) selects which board's
#     EXPECTATION ROW the asserts below use; it does NOT change which two
#     files are compared. The compared pair is fixed to the DE10 defconfigs
#     named above (the file-path axis is deliberately not wired yet —
#     docs/de25-readiness-ledger.md §5.7 risk 3), so BOARD=de25nano today
#     asserts aarch64 expectations against the DE10 pair and fails, as it
#     should: it is a table self-test, not a DE25 lockstep check.
#
# BOARD selects the per-board sentinel/family tables in scripts/lib/
# board-expectations.sh (docs/de25-readiness-ledger.md §5.2) — an optional
# $1 wins over the BOARD env var if both are given. Defaults to
# "de10nano"; none of the call sites above pass either today, so that
# default is the only path any of them exercise, and it is defined to
# reproduce this file's own former literal sentinel/family lists
# byte-for-byte (§5.6) — the table is not a behaviour change for DE10, only
# a second board's row is new. An unrecognized BOARD is a usage error (exit
# 2 below), never a silent fallback to an existing board's row.
#
# Exit: 0 = in lockstep; 1 = drift, a one-sided choice bump, or a missing
# sentinel; 2 = usage/IO error (including an unrecognized BOARD).

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_DEFCONFIG="$ROOT/configs/mister_de10nano_defconfig"
KERNEL_DEFCONFIG="$ROOT/configs/mister_kernel_defconfig"

# shellcheck source=scripts/lib/board-expectations.sh
. "$ROOT/scripts/lib/board-expectations.sh"

# $1 (if given) wins over the BOARD env var; both fall back to "de10nano".
# See this file's header for why the default must stay byte-identical to
# the pre-table literal lists.
BOARD="${1:-${BOARD:-de10nano}}"
# Both tables are checked, not just the first one the script happens to read:
# a board row added to one table and forgotten in the other would otherwise
# surface as a bare `set -u` unbound-variable trace at the later expansion
# instead of a usage error naming the board and the table.
for table in BOARD_ARCH_SENTINELS BOARD_ARCH_FAMILIES; do
	if ! declare -n _tbl="$table" 2>/dev/null || [ -z "${_tbl[$BOARD]+set}" ]; then
		echo "check-kernel-defconfig-sync: FATAL: unknown board '$BOARD' -- scripts/lib/board-expectations.sh's $table has no row for it. Known boards: ${!BOARD_ARCH_SENTINELS[*]}" >&2
		exit 2
	fi
done
unset -n _tbl

for f in "$MAIN_DEFCONFIG" "$KERNEL_DEFCONFIG"; do
	[ -f "$f" ] || { echo "check-kernel-defconfig-sync: FATAL: missing $f" >&2; exit 2; }
done

# Strip comments/blank lines, keep only BR2_ symbol assignments. Same idiom as
# the toolchain-fingerprint step (action.yml): a '#' that begins a line or
# follows whitespace starts a comment; no legitimate value carries a bare '#'.
strip_config() {
	sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]\+#.*$//' -e 's/[[:space:]]*$//' "$1" \
		| grep '^BR2_' || true
}

main_stripped=$(strip_config "$MAIN_DEFCONFIG")
kernel_stripped=$(strip_config "$KERNEL_DEFCONFIG")

# --- 2. Sentinels first: a degenerate kernel defconfig must not pass ---------
# (an empty or mis-stripped file would trivially satisfy the "no symbol
# disagrees" check below — same reasoning as the fingerprint's BR2_arm assert).
# Merge order is BOARD's arch row first, then the common row — this
# reproduces, for BOARD=de10nano, the exact former literal list in the same
# order (scripts/lib/board-expectations.sh, §5.3).
rc=0
# shellcheck disable=SC2086 # word splitting over the merged symbol list is intended
for must in ${BOARD_ARCH_SENTINELS[$BOARD]} $BOARD_COMMON_SENTINELS; do
	if ! printf '%s\n' "$kernel_stripped" | grep -q "^${must}"; then
		echo "FAIL: sentinel '${must}' is absent from configs/mister_kernel_defconfig --" >&2
		echo "      the kernel-only toolchain stanza has been lost or renamed; see that" >&2
		echo "      file's LOCKSTEP header." >&2
		rc=1
	fi
done

# --- 1. Value comparison over the symbols both files define ------------------
# awk keyed on the symbol name (text before the FIRST '='), values compared
# verbatim. Output: one "SYMBOL | main-value | kernel-value" line per mismatch.
mismatches=$(awk '
	BEGIN { FS = "" }
	{
		eq = index($0, "=")
		if (eq == 0) next
		sym = substr($0, 1, eq - 1)
		val = substr($0, eq + 1)
		if (NR == FNR) { main[sym] = val; next }
		if ((sym in main) && main[sym] != val)
			printf "%s\n  main:   %s=%s\n  kernel: %s=%s\n", sym, sym, main[sym], sym, val
	}
' <(printf '%s\n' "$main_stripped") <(printf '%s\n' "$kernel_stripped"))

if [ -n "$mismatches" ]; then
	echo "FAIL: configs/mister_kernel_defconfig has drifted from configs/mister_de10nano_defconfig." >&2
	echo "Every BR2_ symbol defined in BOTH files must carry the identical value:" >&2
	printf '%s\n' "$mismatches" >&2
	echo "" >&2
	echo "Mirror the main defconfig's value into the kernel defconfig (or vice versa —" >&2
	echo "whichever change was intended) in the same commit. See the LOCKSTEP header in" >&2
	echo "configs/mister_kernel_defconfig." >&2
	rc=1
fi

# --- 3. Family name-set comparison: choice symbols drift by RENAME, not value -
# The comparison above is blind to a kconfig CHOICE bump (header §3): switch the
# main defconfig to BR2_KERNEL_HEADERS_6_19=y or BR2_cortex_a7=y and the old
# name simply stops being defined in both files — zero shared symbols disagree,
# and both scenarios were demonstrated to sail through check 1 alone. So for
# each family a choice lives in, assert the SET of defined symbol names matches
# exactly. The designed one-sided symbols (BR2_INIT_NONE, packages, rootfs
# types) share none of these prefixes, so they stay exempt. Both-sides-empty
# degenerates to equal sets — that hole is what the presence sentinels above
# close.
# Same merge order as the sentinels above: BOARD's arch row first, then the
# common row (scripts/lib/board-expectations.sh, §5.3).
# shellcheck disable=SC2086 # word splitting over the merged symbol list is intended
for family in ${BOARD_ARCH_FAMILIES[$BOARD]} $BOARD_COMMON_FAMILIES; do
	main_names=$(printf '%s\n' "$main_stripped" | sed -n "s/^\(${family}[A-Za-z0-9_]*\)=.*/\1/p" | sort)
	kernel_names=$(printf '%s\n' "$kernel_stripped" | sed -n "s/^\(${family}[A-Za-z0-9_]*\)=.*/\1/p" | sort)
	if [ "$main_names" != "$kernel_names" ]; then
		echo "FAIL: the ${family}* symbol-name sets differ between the two defconfigs." >&2
		echo "A choice symbol carries its value in its NAME, so a bump/rename on one side" >&2
		echo "is invisible to the shared-value comparison — mirror it in the same commit:" >&2
		echo "  main:   $(printf '%s' "${main_names:-<none>}" | tr '\n' ' ')" >&2
		echo "  kernel: $(printf '%s' "${kernel_names:-<none>}" | tr '\n' ' ')" >&2
		rc=1
	fi
done

shared=$(awk '
	BEGIN { FS = "" }
	{
		eq = index($0, "=")
		if (eq == 0) next
		sym = substr($0, 1, eq - 1)
		if (NR == FNR) { main[sym] = 1; next }
		if (sym in main) n++
	}
	END { print n + 0 }
' <(printf '%s\n' "$main_stripped") <(printf '%s\n' "$kernel_stripped"))

if [ "$rc" -eq 0 ]; then
	echo "check-kernel-defconfig-sync: OK — $shared shared BR2_ symbol(s) agree, all sentinels present, choice-family name sets match."
fi
exit "$rc"
