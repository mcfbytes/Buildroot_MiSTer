#!/usr/bin/env bash
#
# check-kernel-defconfig-sync.sh — lockstep assertion between the kernel-only
# base configuration and the main image configuration (docs/rt-beta-kernel.md
# §2, ADR 0021 as amended 2026-07-18, docs/buildroot-config.md §1/§4).
#
# HISTORY, because the name predates the layout. Until the fragment split
# (2026-09, docs/buildroot-config.md) configs/mister_kernel_defconfig was a
# hand-mirrored COPY of configs/mister_de10nano_defconfig's toolchain and
# kernel stanzas, and this script compared the two FILES. Both files are gone.
# Today the shipped image and the kernel-only base are two STACKS of
# fragments (configs/fragments/stacks.mk: `common de10nano de10nano-image`
# and `common de10nano kernel-only`) that share the toolchain/kernel
# fragments BY CONSTRUCTION — so the value-drift this script was written for
# can no longer happen by forgetting to mirror an edit. What CAN still happen,
# and what this script now guards, is a toolchain/kernel symbol landing in a
# fragment only ONE stack uses (BR2_KERNEL_HEADERS_6_19=y added to
# de10nano-image.fragment, say): kconfig would accept it, the image and the
# variant kernels would be built by different toolchains, and nothing at build
# time would say so. The comparison is therefore now done over the MERGED
# TEXT of each stack, exactly as it was over the two files, plus one new
# structural assert (0). It stays cheap enough to run before any cache or
# build work: it reads a handful of tracked files and nothing else.
#
# What it asserts, over the merged (comment-stripped) text of the two stacks:
#   0. STRUCTURE: every symbol in a toolchain/kernel family (the BOARD row's
#      arch families + the common families + the kernel/patch families named
#      below) is defined in a fragment BOTH stacks use. That is the
#      "shared by construction" property made checkable.
#   1. Every BR2_ symbol DEFINED IN BOTH stacks carries the identical value.
#      Symbols defined in only one stack are fine by design (the kernel stack
#      has no packages; the image stack has no BR2_INIT_NONE).
#   2. Sentinel presence: the kernel stack still carries the symbols no
#      rewrite of it may lose (arch, CPU, headers series, toolchain C++) —
#      the same fail-loud-on-degenerate-input posture as the toolchain
#      fingerprint in .github/actions/buildroot-build/action.yml.
#   3. Family name-set equality: kconfig CHOICE symbols encode their value in
#      the symbol NAME (BR2_KERNEL_HEADERS_6_18 vs _6_19, BR2_cortex_a9 vs
#      _a7), so a headers or CPU bump on one side DROPS the old name and adds a
#      new one — no symbol exists in both to disagree, and check 1 alone
#      provably passes on exactly that drift. For each family such a choice
#      lives in, the set of defined symbol names must therefore be identical.
#
# Comments are stripped with the SAME sed idiom as that action's fingerprint
# step. That stripping also drops `# BR2_FOO is not set` lines — NOT because
# they are comments to kconfig (they are not: `conf` parses them as an
# explicit =n, and kernel-only.fragment's `# BR2_PACKAGE_BUSYBOX is not set`
# is LOAD-BEARING exactly that way — do not "clean them up") — but because a
# symbol deliberately =n in one stack while set in the other is a DESIGNED
# divergence here (the kernel-only stack suppresses what the image wants,
# BusyBox being the live example), so comparing them would make this check
# cry wolf; the sentinel and family-set asserts guard against a stanza
# vanishing or drifting by rename instead. Values are split on the FIRST '='
# only: several values legitimately contain '=' (the ext2 MKFS_OPTIONS).
#
# The RESOLVED-config half of the same guarantee (that the two stacks still
# agree after olddefconfig, package-driven selects included) lives in
# scripts/check-config-fragments.sh, which needs a Buildroot tree and so runs
# later in CI. This script is the one that runs before any cache restore.
#
# Where this runs:
#   * .github/actions/buildroot-build — for every variant != main, before any
#     cache restore, so drift dies in seconds instead of 2 hours in.
#   * build.yml's `lint-config` job — next to lint-kernel-patches.sh and
#     check-config-fragments.sh.
#   * By hand: scripts/check-kernel-defconfig-sync.sh (no arguments).
#     BOARD=<name> (or a single positional <name>) selects which board's
#     EXPECTATION ROW the asserts below use; it does NOT change which two
#     stacks are compared. The compared pair is fixed to the DE10 stacks
#     named in stacks.mk (there is no DE25 kernel-only stack yet), so
#     BOARD=de25nano today asserts aarch64 expectations against the DE10
#     pair and fails, as it should: it is a table self-test, not a DE25
#     lockstep check.
#
# BOARD selects the per-board sentinel/family tables in scripts/lib/
# board-expectations.sh (docs/de25-readiness-ledger.md §5.2) — an optional
# $1 wins over the BOARD env var if both are given. Defaults to "de10nano";
# none of the call sites above pass either today. An unrecognized BOARD is a
# usage error (exit 2 below), never a silent fallback to an existing row.
#
# Exit: 0 = in lockstep; 1 = drift, a one-sided choice bump, a missing
# sentinel, or a family symbol in a one-stack fragment; 2 = usage/IO error
# (including an unrecognized BOARD).

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/board-expectations.sh
. "$ROOT/scripts/lib/board-expectations.sh"
# shellcheck source=scripts/lib/config-stacks.sh
. "$ROOT/scripts/lib/config-stacks.sh"

# The two stacks compared. Fixed on purpose (see the header); the fragment
# lists themselves come from stacks.mk, never from here.
MAIN_STACK=DE10NANO
KERNEL_STACK=DE10NANO_KERNEL

# Families whose symbols must live in a fragment shared by both stacks, on
# top of the BOARD arch row and the common row from board-expectations.sh:
# the kernel stanza and the patch/hash registry. BR2_LINUX_KERNEL covers
# every BR2_LINUX_KERNEL_* symbol (version, patch dir, config file, image
# format, DTS) — any one of them differing between the image and a variant
# kernel is exactly the "built from different sources" failure ADR 0021
# describes.
SHARED_ONLY_FAMILIES="BR2_LINUX_KERNEL BR2_GLOBAL_PATCH_DIR"

# $1 (if given) wins over the BOARD env var; both fall back to "de10nano".
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

[ -f "$CONFIG_STACKS_MK" ] || { echo "check-kernel-defconfig-sync: FATAL: missing $CONFIG_STACKS_MK" >&2; exit 2; }

mapfile -t main_files < <(config_stack_files "$MAIN_STACK")
mapfile -t kernel_files < <(config_stack_files "$KERNEL_STACK")
if [ "${#main_files[@]}" -eq 0 ] || [ "${#kernel_files[@]}" -eq 0 ]; then
	echo "check-kernel-defconfig-sync: FATAL: ${MAIN_STACK}_FRAGMENTS or ${KERNEL_STACK}_FRAGMENTS is empty/missing in configs/fragments/stacks.mk" >&2
	exit 2
fi
for f in "${main_files[@]}" "${kernel_files[@]}"; do
	[ -f "$f" ] || { echo "check-kernel-defconfig-sync: FATAL: missing $f (named in configs/fragments/stacks.mk)" >&2; exit 2; }
done

# Strip comments/blank lines, keep only BR2_ symbol assignments. Same idiom as
# the toolchain-fingerprint step (action.yml): a '#' that begins a line or
# follows whitespace starts a comment; no legitimate value carries a bare '#'.
strip_config() {
	sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]\+#.*$//' -e 's/[[:space:]]*$//' "$@" \
		| grep '^BR2_' || true
}

main_stripped=$(strip_config "${main_files[@]}")
kernel_stripped=$(strip_config "${kernel_files[@]}")

rc=0

# --- 0. Structure: family symbols only in fragments BOTH stacks use ---------
# Shared = present in both lists (by path). A family symbol found in any
# other fragment is a toolchain/kernel decision one stack would not see.
shared_files=()
for f in "${main_files[@]}"; do
	for g in "${kernel_files[@]}"; do
		[ "$f" = "$g" ] && shared_files+=("$f")
	done
done
if [ "${#shared_files[@]}" -eq 0 ]; then
	echo "FAIL: the $(config_stack_label "$MAIN_STACK") and $(config_stack_label "$KERNEL_STACK") stacks share no fragment at all --" >&2
	echo "      the kernel-only base can no longer be in lockstep with the image by construction." >&2
	rc=1
fi
is_shared() { local s; for s in "${shared_files[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
# shellcheck disable=SC2086 # word splitting over the merged family list is intended
for f in "${main_files[@]}" "${kernel_files[@]}"; do
	is_shared "$f" && continue
	for family in ${BOARD_ARCH_FAMILIES[$BOARD]} $BOARD_COMMON_FAMILIES $SHARED_ONLY_FAMILIES; do
		hits=$(strip_config "$f" | sed -n "s/^\(${family}[A-Za-z0-9_]*\)=.*/\1/p")
		[ -n "$hits" ] || continue
		echo "FAIL: ${f#"$ROOT"/} defines toolchain/kernel symbol(s) $(printf '%s' "$hits" | tr '\n' ' ')" >&2
		echo "      but only ONE of the two stacks uses that fragment. Such symbols belong in a" >&2
		echo "      fragment both configs/fragments/stacks.mk stacks list (common or de10nano)," >&2
		echo "      or the image and the variant kernels are built from different settings." >&2
		rc=1
	done
done

# --- 2. Sentinels: a degenerate kernel stack must not pass ------------------
# (an empty or mis-stripped stack would trivially satisfy the "no symbol
# disagrees" check below — same reasoning as the fingerprint's BR2_arm assert).
# Merge order is BOARD's arch row first, then the common row — this
# reproduces, for BOARD=de10nano, the exact former literal list in the same
# order (scripts/lib/board-expectations.sh, §5.3).
# shellcheck disable=SC2086 # word splitting over the merged symbol list is intended
for must in ${BOARD_ARCH_SENTINELS[$BOARD]} $BOARD_COMMON_SENTINELS; do
	if ! printf '%s\n' "$kernel_stripped" | grep -q "^${must}"; then
		echo "FAIL: sentinel '${must}' is absent from the $(config_stack_label "$KERNEL_STACK") stack --" >&2
		echo "      the kernel-only toolchain stanza has been lost or renamed; see" >&2
		echo "      configs/fragments/de10nano.fragment and docs/buildroot-config.md §3." >&2
		rc=1
	fi
done

# --- 1. Value comparison over the symbols both stacks define ---------------
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
	echo "FAIL: the $(config_stack_label "$KERNEL_STACK") stack disagrees with the $(config_stack_label "$MAIN_STACK") stack." >&2
	echo "Every BR2_ symbol defined in BOTH stacks must carry the identical value:" >&2
	printf '%s\n' "$mismatches" >&2
	echo "" >&2
	echo "A symbol both stacks need belongs in a SHARED fragment (common or de10nano), defined" >&2
	echo "once -- see configs/fragments/stacks.mk and docs/buildroot-config.md §1." >&2
	rc=1
fi

# --- 3. Family name-set comparison: choice symbols drift by RENAME, not value -
# The comparison above is blind to a kconfig CHOICE bump (header §3): switch the
# image stack to BR2_KERNEL_HEADERS_6_19=y or BR2_cortex_a7=y and the old
# name simply stops being defined in both — zero shared symbols disagree,
# and both scenarios were demonstrated to sail through check 1 alone. So for
# each family a choice lives in, assert the SET of defined symbol names matches
# exactly. The designed one-sided symbols (BR2_INIT_NONE, packages, rootfs
# types) share none of these prefixes, so they stay exempt. Both-sides-empty
# degenerates to equal sets — that hole is what the presence sentinels above
# close.
# shellcheck disable=SC2086 # word splitting over the merged symbol list is intended
for family in ${BOARD_ARCH_FAMILIES[$BOARD]} $BOARD_COMMON_FAMILIES; do
	main_names=$(printf '%s\n' "$main_stripped" | sed -n "s/^\(${family}[A-Za-z0-9_]*\)=.*/\1/p" | sort)
	kernel_names=$(printf '%s\n' "$kernel_stripped" | sed -n "s/^\(${family}[A-Za-z0-9_]*\)=.*/\1/p" | sort)
	if [ "$main_names" != "$kernel_names" ]; then
		echo "FAIL: the ${family}* symbol-name sets differ between the two stacks." >&2
		echo "A choice symbol carries its value in its NAME, so a bump/rename on one side" >&2
		echo "is invisible to the shared-value comparison — define it once, in a shared fragment:" >&2
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
	echo "check-kernel-defconfig-sync: OK — $(config_stack_label "$MAIN_STACK") and $(config_stack_label "$KERNEL_STACK") stacks share ${#shared_files[@]} fragment(s); $shared shared BR2_ symbol(s) agree, all sentinels present, choice-family name sets match, every toolchain/kernel family symbol lives in a shared fragment."
fi
exit "$rc"
