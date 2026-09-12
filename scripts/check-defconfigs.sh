#!/usr/bin/env bash
# check-defconfigs.sh -- every configs/mister_*_defconfig loads, is canonical,
# and every profile `select` really lands.
#
# What it asserts, per defconfig (the way upstream Buildroot's own CI checks
# its defconfigs: `make <name>_defconfig` then support/scripts/check-dotconfig.py):
#   (a) LOADS: `make <name>_defconfig` succeeds in a scratch O= dir.
#   (b) EVERY LINE SURVIVES: check-dotconfig.py -- each BR2_ line of the
#       committed defconfig is present verbatim in the resolved .config, so a
#       symbol that kconfig silently dropped (unmet dependency, retired symbol
#       after a Buildroot bump -- the DE25 glibc->uClibc regression of the
#       2026.08 bump was exactly this) FAILS instead of vanishing.
#   (c) CANONICAL: `make savedefconfig` reproduces the committed file's BR2_
#       lines exactly (order aside), so the file is Buildroot's own minimal
#       form and a review diff is the real change. Comment lines are free.
#   (d) PROFILES LAND: for every package/mister-*/Config.in profile the
#       defconfig enables, every `select` in it is `=y` in the resolved
#       config. kconfig ignores a `select` of a `choice` member SILENTLY
#       (the zlib provider was caught this way, ADR 0030 §5.7); this makes
#       that a failure.
#   (e) SHARED REMAINDER: the symbols both boards must agree on (the old
#       `common` layer) carry the same value in every board defconfig.
#
# usage: scripts/check-defconfigs.sh [--keep] [name ...]
#   name  a defconfig basename without the _defconfig suffix (mister_de10nano);
#         default: every configs/mister_*_defconfig.
# Needs the pinned Buildroot tree (make buildroot-unpack); no toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BR_DIR="$ROOT/work/buildroot"
CHECK_DIR="$ROOT/output-config-check"
KEEP=false
rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

only=()
while [ $# -gt 0 ]; do
	case "$1" in
		--keep) KEEP=true ;;
		-h|--help) sed -n '2,30p' "$0"; exit 0 ;;
		*) only+=("$1") ;;
	esac
	shift
done

[ -f "$BR_DIR/Makefile" ] || make -C "$ROOT" --no-print-directory buildroot-unpack
[ -x "$ROOT/work/.hostshim/install" ] && export PATH="$ROOT/work/.hostshim:$PATH"

# Symbols every board defconfig must agree on (the retired `common` layer).
SHARED_SYMBOLS="BR2_TOOLCHAIN_BUILDROOT_CXX BR2_DOWNLOAD_FORCE_CHECK_HASHES BR2_LINUX_KERNEL BR2_LINUX_KERNEL_CUSTOM_VERSION BR2_LINUX_KERNEL_DTS_SUPPORT BR2_REPRODUCIBLE BR2_ROOTFS_MERGED_USR"

names=()
if [ "${#only[@]}" -gt 0 ]; then
	names=("${only[@]}")
else
	for f in "$ROOT"/configs/mister_*_defconfig; do
		n=$(basename "$f" _defconfig); names+=("$n")
	done
fi

br_make() { make -s -C "$BR_DIR" O="$1" BR2_EXTERNAL="$ROOT" BR2_DL_DIR="$ROOT/dl" "${@:2}"; }

declare -A BOARD_VALUES
for name in "${names[@]}"; do
	defconfig="$ROOT/configs/${name}_defconfig"
	[ -f "$defconfig" ] || { fail "$name: $defconfig does not exist"; continue; }
	odir="$CHECK_DIR/$name"; rm -rf "$odir"; mkdir -p "$odir"
	echo "==> $name"
	# (a)
	if ! br_make "$odir" "${name}_defconfig" >"$odir/load.log" 2>&1; then
		fail "$name: 'make ${name}_defconfig' failed -- see ${odir#"$ROOT"/}/load.log"; continue
	fi
	# (b)
	if ! python3 "$BR_DIR/support/scripts/check-dotconfig.py" "$odir/.config" "$defconfig" >"$odir/dotconfig.log" 2>&1; then
		fail "$name: a defconfig line did not survive into the resolved .config (kconfig dropped it silently -- unmet dependency, or a symbol retired by a Buildroot bump):"; sed 's/^/      /' "$odir/dotconfig.log" >&2
	else
		echo "    every defconfig line survives in the resolved .config ($(grep -c -E '^(BR2_[A-Za-z0-9_]+=|# BR2_[A-Za-z0-9_]+ is not set$)' "$defconfig") lines)"
	fi
	# (c)
	if br_make "$odir" savedefconfig BR2_DEFCONFIG="$odir/saved.defconfig" >"$odir/save.log" 2>&1; then
		if ! diff <(grep -E '^(BR2_[A-Za-z0-9_]+=|# BR2_[A-Za-z0-9_]+ is not set$)' "$defconfig" | sort) <(grep -E '^(BR2_[A-Za-z0-9_]+=|# BR2_[A-Za-z0-9_]+ is not set$)' "$odir/saved.defconfig" | sort) >"$odir/canonical.diff"; then
			fail "$name: not canonical -- 'make savedefconfig' differs from the committed file (< committed, > canonical). Replace the file's BR2_ lines with the canonical set:"; sed 's/^/      /' "$odir/canonical.diff" >&2
		else
			echo "    canonical (savedefconfig reproduces it)"
		fi
	else
		fail "$name: savedefconfig failed -- see ${odir#"$ROOT"/}/save.log"
	fi
	# (d)
	for cfgin in "$ROOT"/package/mister-*/Config.in; do
		sym=$(sed -n 's/^config \(BR2_PACKAGE_MISTER_[A-Z_]*\)$/\1/p' "$cfgin" | head -1)
		[ -n "$sym" ] || continue
		grep -qx "$sym=y" "$odir/.config" || continue
		missing=""
		while IFS= read -r sel; do
			grep -qx "$sel=y" "$odir/.config" || missing="$missing $sel"
		done < <(sed -n 's/^[[:space:]]*select \(BR2_[A-Za-z0-9_]*\)[[:space:]]*$/\1/p' "$cfgin")
		if [ -n "$missing" ]; then
			fail "$name: profile $sym is enabled but these selects did not land:$missing -- a select of a kconfig 'choice' member is ignored silently (move the line into the defconfig), or the package's own dependencies are unmet on this board (${cfgin#"$ROOT"/})"
		else
			echo "    profile $sym: every select landed ($(grep -c '^[[:space:]]*select ' "$cfgin"))"
		fi
	done
	# collect for (e)
	for s in $SHARED_SYMBOLS; do
		v=$(grep -E "^$s=|^# $s is not set" "$odir/.config" | head -1 || true)
		BOARD_VALUES["$name:$s"]="$v"
	done
done

# (e)
first=""
for name in "${names[@]}"; do
	[ -f "$ROOT/configs/${name}_defconfig" ] || continue
	case "$name" in mister_installer) continue ;; esac   # the installer cpio is not a board image
	if [ -z "$first" ]; then first="$name"; continue; fi
	for s in $SHARED_SYMBOLS; do
		if [ "${BOARD_VALUES[$first:$s]:-}" != "${BOARD_VALUES[$name:$s]:-}" ]; then
			fail "shared remainder: $s differs between $first ('${BOARD_VALUES[$first:$s]:-unset}') and $name ('${BOARD_VALUES[$name:$s]:-unset}') -- both boards must agree on it (docs/buildroot-config.md)"
		fi
	done
done
[ -n "$first" ] && echo "==> shared remainder: $(echo "$SHARED_SYMBOLS" | wc -w) symbols agree across the board defconfigs"

if [ "$rc" -eq 0 ]; then
	[ "$KEEP" = true ] || rm -rf "$CHECK_DIR"
	echo "check-defconfigs: OK -- ${#names[@]} defconfig(s) load, are canonical, and every profile select lands"
else
	echo "check-defconfigs: FAILED -- resolved configs left under ${CHECK_DIR#"$ROOT"/}/ for inspection" >&2
fi
exit "$rc"
