#!/usr/bin/env bash
#
# check-kernel-fragment-noop.sh — prove that the shared MiSTer kernel fragment
# changes NOTHING on the board whose kernel config it was extracted from.
#
# WHY THIS EXISTS
# ---------------
# board/mister/common/linux-mister.fragment is the arch-neutral MiSTer driver
# and feature set: input/HID, Bluetooth, Wi-Fi, USB, sound, filesystems,
# netfilter, LEDs. It was extracted from the DE10-Nano's kernel config and is
# consumed today by the DE25-Nano, which layers it on top of its own minimal
# arm64 base (board/mister/de25nano/linux.config).
#
# The whole value of that arrangement rests on ONE claim: every line in the
# fragment is byte-identical to the corresponding line in the DE10's resolved
# kernel config. That is what makes "both boards have the same driver support"
# checkable, and it is what will let the DE10 adopt the fragment later with a
# provable zero-delta instead of a leap of faith.
#
# A claim that is only asserted in a comment decays. This script is the claim,
# executed. It is designed to be run against a *configured kernel build tree*,
# so it belongs AFTER a kernel build, not in a lint job (see docs/ci.md notes
# in docs/de25-kernel-config.md §10).
#
# HOW IT WORKS — and why it runs kconfig twice
# --------------------------------------------
# Naively one would merge the fragment onto the tree's .config, resolve, and
# diff against the tree's .config. That has a false-positive: resolving a config
# outside Buildroot's environment cannot reproduce toolchain-derived string
# symbols exactly (CONFIG_CC_VERSION_TEXT comes from `$(CC) --version` run
# through kconfig's $(shell,...) and comes back empty here). So instead:
#
#   CONTROL : tree/.config                    -> olddefconfig -> control/.config
#   TEST    : tree/.config + fragment (merge) -> olddefconfig -> test/.config
#
# Both runs use exactly the same kconfig binary, srctree, ARCH and compiler, so
# every environment-derived difference cancels. The fragment is a no-op if and
# only if control/.config and test/.config are byte-identical.
#
# It also fails on any merge_config.sh "is redefined by fragment" line. Note the
# gotcha those lines carry: merge_config resolves a symbol's new value with
# `grep -w CONFIG_<SYM> <fragment>`, which matches PROSE as well as settings, so
# a comment in the fragment that names a symbol the fragment also sets produces
# a FALSE redefinition warning. Rule 5 in the fragment's header forbids that;
# this check is what enforces it.
#
# USAGE
#   scripts/check-kernel-fragment-noop.sh [--tree DIR] [--fragment FILE] [--keep]
#
# With no arguments it binds to THE kernel tree under output/build/linux-[0-9]*
# — the same "never the first glob match" discipline the Makefile's `rt` recipe
# uses: `linux-[0-9]*` so linux-firmware-*/linux-headers-*/linux-pam-* cannot
# match, zero trees is fatal, and MORE than one tree is fatal too, because a
# stale sibling left by a kernel bump sorts first often enough that picking one
# blindly would validate the wrong kernel and false-pass.
#
# Exit codes: 0 = fragment is a no-op. 1 = drift, or the check could not run.
#
set -euo pipefail

PROG=${0##*/}
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

TREE=""
FRAGMENT="$REPO_ROOT/board/mister/common/linux-mister.fragment"
KEEP=0

die() { printf '%s: FATAL: %s\n' "$PROG" "$1" >&2; exit 1; }

usage() {
	cat >&2 <<-EOF
	usage: $PROG [--tree DIR] [--fragment FILE] [--keep]

	  --tree DIR      configured kernel build tree to check against.
	                  Default: the unique output/build/linux-[0-9]*/ .
	  --fragment FILE kernel config fragment to prove is a no-op.
	                  Default: board/mister/common/linux-mister.fragment
	  --keep          keep the scratch directory (prints its path).
	EOF
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
	--tree)     [ $# -ge 2 ] || usage; TREE=$2; shift 2 ;;
	--fragment) [ $# -ge 2 ] || usage; FRAGMENT=$2; shift 2 ;;
	--keep)     KEEP=1; shift ;;
	-h|--help)  usage ;;
	*)          printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2; usage ;;
	esac
done

[ -f "$FRAGMENT" ] || die "fragment does not exist: $FRAGMENT"
# Canonicalise now: merge_config.sh runs after a `cd` into the scratch dir,
# where a relative --fragment path would no longer resolve.
FRAGMENT=$(readlink -f "$FRAGMENT")

# --- bind to THE kernel tree, fail closed on zero or many --------------------
if [ -z "$TREE" ]; then
	# shellcheck disable=SC2207  # paths here are Buildroot-generated, no spaces
	trees=($(ls -d "$REPO_ROOT"/output/build/linux-[0-9]*/ 2>/dev/null || true))
	if [ ${#trees[@]} -eq 0 ]; then
		printf '%s: FATAL: no kernel tree under %s\n' \
			"$PROG" "$REPO_ROOT/output/build/linux-[0-9]*/" >&2
		printf '        This check needs a CONFIGURED kernel tree; it cannot run on a\n' >&2
		printf '        clean checkout. Build the DE10 image first (make all), or pass\n' >&2
		printf '        --tree DIR.\n' >&2
		exit 1
	elif [ ${#trees[@]} -gt 1 ]; then
		printf '%s: FATAL: %d kernel trees under %s/output/build/ -- cannot tell which\n' \
			"$PROG" "${#trees[@]}" "$REPO_ROOT" >&2
		printf '        one is current:\n' >&2
		printf '          %s\n' "${trees[@]}" >&2
		printf '        A stale sibling appears when the kernel version is bumped without\n' >&2
		printf '        discarding the old tree; validating its .config would prove the\n' >&2
		printf '        fragment against the WRONG kernel. Remove the stale tree, or pass\n' >&2
		printf '        --tree DIR explicitly.\n' >&2
		exit 1
	fi
	TREE=${trees[0]}
fi
TREE=${TREE%/}
[ -d "$TREE" ] || die "not a directory: $TREE"
# Absolute, because both kconfig runs below execute with cwd inside the scratch
# directory -- a relative --tree would silently resolve to nothing there.
TREE=$(cd -- "$TREE" && pwd)

CONF="$TREE/scripts/kconfig/conf"
MERGE="$TREE/scripts/kconfig/merge_config.sh"
BASE_CONFIG="$TREE/.config"

[ -f "$BASE_CONFIG" ]  || die "$TREE has no .config -- the tree is not configured."
[ -x "$CONF" ]         || die "$CONF is missing or not executable -- the tree was never built."
[ -x "$MERGE" ]        || die "$MERGE is missing."

# --- derive ARCH and version from the .config's generated header -------------
# e.g. "# Linux/arm 6.18.48 Kernel Configuration"
header=$(sed -n 's|^# Linux/\([a-z0-9_]*\) \([^ ]*\) Kernel Configuration$|\1 \2|p' \
	"$BASE_CONFIG" | head -n1)
[ -n "$header" ] || die "cannot read the arch/version header from $BASE_CONFIG"
ARCH=${header% *}
KERNELVERSION=${header#* }

# --- find the cross compiler the tree was built with, if we can --------------
# Only used so that toolchain-derived symbols resolve the same way in BOTH
# runs; since the two runs are compared to each other, a fallback is harmless.
CC_BIN=${CC:-}
LD_BIN=${LD:-}
if [ -z "$CC_BIN" ]; then
	host_bin=$(cd -- "$TREE/../.." 2>/dev/null && pwd)/host/bin
	for candidate in "$host_bin"/*-linux-*-gcc; do
		[ -x "$candidate" ] || continue
		CC_BIN=$candidate
		LD_BIN=${candidate%-gcc}-ld
		break
	done
fi
[ -n "$CC_BIN" ] || CC_BIN=gcc
[ -n "$LD_BIN" ] || LD_BIN=ld

WORK=$(mktemp -d -t kfragnoop.XXXXXXXX)
# shellcheck disable=SC2329  # invoked indirectly, by the EXIT trap below
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/control" "$WORK/test"

export ARCH SRCARCH="$ARCH" KERNELVERSION
# srctree is how kconfig's `conf` finds the top-level Kconfig (and every
# `source`d file) when run from a directory other than the kernel tree:
# zconf_fopen() retries a relative path under $srctree. That is why the two
# olddefconfig runs below can `cd` into scratch dirs that contain only a
# .config and still name a bare "Kconfig".
export srctree="$TREE"
export CC="$CC_BIN" LD="$LD_BIN"
export HOSTCC=${HOSTCC:-gcc} HOSTCXX=${HOSTCXX:-g++}

printf '%s: tree      %s\n' "$PROG" "$TREE"
printf '%s: arch      %s (kernel %s)\n' "$PROG" "$ARCH" "$KERNELVERSION"
printf '%s: fragment  %s\n' "$PROG" "$FRAGMENT"
printf '\n'

# --- CONTROL: resolve the tree's own config, untouched -----------------------
cp -- "$BASE_CONFIG" "$WORK/control/.config"
( cd "$WORK/control" && "$CONF" --olddefconfig Kconfig ) > "$WORK/control.log" 2>&1 \
	|| { cat "$WORK/control.log" >&2; die "control olddefconfig failed"; }

# --- TEST: same config with the fragment merged in ---------------------------
cp -- "$BASE_CONFIG" "$WORK/test/base.config"
printf '===== merge_config.sh -m =====\n'
( cd "$WORK/test" && "$MERGE" -m -O "$WORK/test" base.config "$FRAGMENT" ) \
	> "$WORK/merge.log" 2>&1 || { cat "$WORK/merge.log" >&2; die "merge_config.sh failed"; }
cat "$WORK/merge.log"
printf '===== end merge_config.sh =====\n\n'

( cd "$WORK/test" && "$CONF" --olddefconfig Kconfig ) > "$WORK/test.log" 2>&1 \
	|| { cat "$WORK/test.log" >&2; die "test olddefconfig failed"; }

status=0

if grep -q 'is redefined by fragment' "$WORK/merge.log"; then
	printf '%s: FAIL: merge_config.sh reported a REDEFINITION.\n' "$PROG" >&2
	grep -n 'is redefined by fragment' "$WORK/merge.log" >&2
	printf '        Either the fragment genuinely disagrees with %s,\n' "$BASE_CONFIG" >&2
	printf '        or a COMMENT in the fragment names a symbol the fragment also sets\n' >&2
	printf '        (merge_config greps prose too -- rule 5 in the fragment header).\n' >&2
	status=1
fi

if ! diff -u "$WORK/control/.config" "$WORK/test/.config" > "$WORK/drift.diff"; then
	printf '%s: FAIL: the fragment CHANGES the resolved config of this tree.\n' "$PROG" >&2
	printf '        Every line of %s must be\n' "$FRAGMENT" >&2
	printf '        byte-identical to the corresponding line in this board resolved\n' >&2
	printf '        config, or the two boards no longer share one driver set.\n' >&2
	printf '        --- control (tree as built) vs test (tree + fragment) ---\n' >&2
	cat "$WORK/drift.diff" >&2
	status=1
fi

if [ "$status" -eq 0 ]; then
	printf '%s: PASS: fragment is a no-op on %s\n' "$PROG" "$TREE"
	printf '%s:       zero redefinitions, resolved config identical.\n' "$PROG"
fi

if [ "$KEEP" -eq 1 ]; then
	printf '%s: scratch kept at %s\n' "$PROG" "$WORK"
fi

exit "$status"
