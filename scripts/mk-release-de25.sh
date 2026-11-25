#!/usr/bin/env bash
# mk-release-de25.sh -- turn a finished `make de25` + `make O=output-de25 legal-info`
# into the DE25-Nano pre-release asset set (ADR 0027 D6; docs/ci.md#de25-manual-lane).
#
# usage: scripts/mk-release-de25.sh [<output-dir>] [<dist-dir>]   (defaults: output-de25, dist-de25)
#
#   1. check /MiSTer.version in rootfs.ext4 (6 digits, no newline, = $MISTER_VERSION if set)
#   2. sdcard-de25.img and sdcard-de25-ext4.img -> .img.xz, integrity-tested
#   3. loose FAT-partition files: u-boot.itb, Image, the board DTB, bl31.bin
#   4. buildroot.config, linux.config, legal-info.tar.gz (patches-only, as DE10)
#   5. SHA256SUMS over everything above
#
# Needs on the host: xz, debugfs (e2fsprogs), sha256sum, tar.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
abspath() { case $1 in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$PWD/$1" ;; esac; }
out=$(abspath "${1:-$ROOT/output-de25}")
dist=$(abspath "${2:-$ROOT/dist-de25}")
# shellcheck source=scripts/ci-lib.sh
source "$ROOT/scripts/ci-lib.sh"
say() { printf '\n==> mk-release-de25: %s\n' "$*"; }
die() { echo "mk-release-de25: FATAL: $*" >&2; exit 1; }

# The names post-image.sh assembles the card from; it is their one author.
dtb=socfpga_agilex5_de25nano.dtb
boot_files=(u-boot.itb Image "$dtb" bl31.bin)

for t in xz debugfs sha256sum tar; do command -v "$t" >/dev/null 2>&1 || die "'$t' not found in PATH"; done
for f in images/sdcard-de25.img images/sdcard-de25-ext4.img images/rootfs.ext4 "${boot_files[@]/#/images/}" .config; do
	[ -f "$out/$f" ] || die "$out/$f is missing -- run 'make de25' first"
done
[ -d "$out/legal-info" ] || die "$out/legal-info is missing -- run 'make O=output-de25 legal-info' first"
grep -qx 'BR2_aarch64=y' "$out/.config" || die "$out/.config is not an aarch64 (DE25-Nano) configuration"

# --- 1. /MiSTer.version ----------------------------------------------------------
say "reading /MiSTer.version from $out/images/rootfs.ext4"
mkdir -p "$dist"
work=$(mktemp -d "$dist/.work.XXXXXX")
trap 'rm -rf "$work"' EXIT
debugfs -R "rdump /MiSTer.version $work" "$out/images/rootfs.ext4" >/dev/null 2>"$work/debugfs.log" || true
verfile="$work/MiSTer.version"
[ -f "$verfile" ] || { sed 's/^/    /' "$work/debugfs.log" >&2; die "debugfs could not extract /MiSTer.version"; }
[ "$(wc -c < "$verfile")" -eq 6 ] || die "/MiSTer.version is $(wc -c < "$verfile") bytes, expected exactly 6"
yymmdd=$(cat "$verfile")
case "$yymmdd" in [0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "/MiSTer.version '$yymmdd' is not 6 ASCII digits" ;; esac
if [ -n "${MISTER_VERSION:-}" ] && [ "$yymmdd" != "$MISTER_VERSION" ]; then
	die "built /MiSTer.version '$yymmdd' != requested MISTER_VERSION '$MISTER_VERSION'"
fi
echo "    /MiSTer.version=$yymmdd"

# --- 2. the card image -------------------------------------------------------------
for card in sdcard-de25.img sdcard-de25-ext4.img; do
	say "compressing $card"
	rm -f "$dist/$card.xz"
	xz -T0 -9 -c "$out/images/$card" > "$work/$card.xz"
	xz -t "$work/$card.xz"
	mv "$work/$card.xz" "$dist/$card.xz"
	ci_lib_check_release_asset_size "$dist/$card.xz" "$card.xz" "."
done

# --- 3. loose boot files -------------------------------------------------------------
say "staging the FAT-partition boot files"
for f in "${boot_files[@]}"; do cp -f "$out/images/$f" "$dist/$f"; done

# --- 4. configs + legal-info -----------------------------------------------------------
say "staging configs and legal-info"
cp -f "$out/.config" "$dist/buildroot.config"
trees=("$out"/build/linux-[0-9]*/)
[ "${#trees[@]}" -eq 1 ] && [ -d "${trees[0]}" ] || die "expected exactly one kernel tree at $out/build/linux-[0-9]*/, found ${#trees[@]}"
cp -f "${trees[0]}.config" "$dist/linux.config"
ci_lib_package_legal_info "$out" "$dist/legal-info.tar.gz" patches-only
ci_lib_check_release_asset_size "$dist/legal-info.tar.gz" legal-info.tar.gz "."

# --- 5. SHA256SUMS ----------------------------------------------------------------------
say "SHA256SUMS"
( cd "$dist" && sha256sum sdcard-de25.img.xz sdcard-de25-ext4.img.xz "${boot_files[@]}" buildroot.config linux.config legal-info.tar.gz > SHA256SUMS && cat SHA256SUMS )
say "done: $dist ready"
