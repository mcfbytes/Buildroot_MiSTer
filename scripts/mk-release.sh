#!/usr/bin/env bash
# mk-release.sh -- turn a finished `make` into a verified release asset set.
#
# usage: scripts/mk-release.sh [<output-dir>] [<dist-dir>]      (defaults: output, dist)
#
# release.yml's build job is this script plus the sdcard image. It is a plain
# sequence, and every step is one you can run at a terminal:
#
#   1. read /MiSTer.version out of the built linux.img and check the contract
#      (6 ASCII digits, no newline, equal to $MISTER_VERSION when that is set);
#      RELEASE_DATE = 20<that>, written to <dist>/RELEASE_DATE for the caller
#   2. stage the image assets: linux.img, zImage_dtb, zImage_dtb-rt,
#      buildroot.config, linux.config, linux-rt.config, legal-info.tar.gz
#   3. fetch, verify and extract the pinned STOCK release archive
#      (scripts/verify-stock-payload.sh; the STOCK_* pins come from the
#      environment -- release.yml's env block, or your shell)
#   4. assemble files/linux/ = stock's tree with OUR linux.img, zImage_dtb and
#      7za dropped in, and pack release_<date>.7z the way the Downloader expects
#   5. prove the archive round-trips under the pinned ARM 7za (qemu-arm) and
#      that its member list matches the assembled tree
#   6. SHA256SUMS over everything above
#
# Needs on the host: 7z (p7zip-full), qemu-arm, debugfs (e2fsprogs), curl.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out=${1:-$ROOT/output}
dist=${2:-$ROOT/dist}
work=$ROOT/release-work
# shellcheck source=scripts/ci-lib.sh
source "$ROOT/scripts/ci-lib.sh"
say() { printf '\n==> mk-release: %s\n' "$*"; }
die() { echo "mk-release: FATAL: $*" >&2; exit 1; }

for t in 7z qemu-arm debugfs curl; do command -v "$t" >/dev/null 2>&1 || die "'$t' not found in PATH"; done
for f in images/linux.img images/zImage_dtb images/zImage_dtb-rt images/linux-rt.config images/7za .config; do
	[ -f "$out/$f" ] || die "$out/$f is missing -- run 'make' first (zImage_dtb-rt / linux-rt.config come from package/linux-rt)"
done
[ -d "$out/legal-info" ] || die "$out/legal-info is missing -- run 'make legal-info' first"

# --- 1. /MiSTer.version --------------------------------------------------------
say "reading /MiSTer.version from $out/images/linux.img"
rm -rf "$work"; mkdir -p "$work/ver" "$dist"
debugfs -R "rdump /MiSTer.version $work/ver" "$out/images/linux.img" >/dev/null 2>"$work/debugfs.log" || true
verfile="$work/ver/MiSTer.version"
[ -f "$verfile" ] || { sed 's/^/    /' "$work/debugfs.log" >&2; die "debugfs could not extract /MiSTer.version"; }
[ "$(wc -c < "$verfile")" -eq 6 ] || die "/MiSTer.version is $(wc -c < "$verfile") bytes, expected exactly 6 (docs/downloader-contract.md §3)"
[ "$(tail -c1 "$verfile" | od -An -tx1 | tr -d ' ')" != "0a" ] || die "/MiSTer.version ends in a newline -- that breaks the Downloader's version-equality check"
yymmdd=$(cat "$verfile")
case "$yymmdd" in [0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) die "/MiSTer.version '$yymmdd' is not 6 ASCII digits" ;; esac
if [ -n "${MISTER_VERSION:-}" ] && [ "$yymmdd" != "$MISTER_VERSION" ]; then
	die "built /MiSTer.version '$yymmdd' != requested MISTER_VERSION '$MISTER_VERSION' -- post-build.sh did not honor the override"
fi
release_date="20$yymmdd"
echo "$release_date" > "$dist/RELEASE_DATE"
echo "    /MiSTer.version=$yymmdd -> RELEASE_DATE=$release_date"

# --- 2. image assets --------------------------------------------------------------
say "staging image assets into $dist"
cp -f "$out/images/linux.img" "$out/images/zImage_dtb" "$out/images/zImage_dtb-rt" "$out/images/linux-rt.config" "$dist/"
cp -f "$out/.config" "$dist/buildroot.config"
trees=("$out"/build/linux-[0-9]*/)
[ "${#trees[@]}" -eq 1 ] && [ -d "${trees[0]}" ] || die "expected exactly one kernel tree at $out/build/linux-[0-9]*/, found ${#trees[@]} (a stale sibling from a version bump?)"
cp -f "${trees[0]}.config" "$dist/linux.config"
ci_lib_package_legal_info "$out" "$dist/legal-info.tar.gz" patches-only
ci_lib_check_release_asset_size "$dist/legal-info.tar.gz" legal-info.tar.gz \
	". The package set has outgrown a single source bundle -- split it (e.g. sources/ as its own asset)."

# --- 3. the stock archive ---------------------------------------------------------
say "fetching + verifying the pinned stock release"
vsp="$ROOT/scripts/verify-stock-payload.sh"
"$vsp" fetch-stock "$work/stock_release.7z"
"$vsp" verify-stock "$work/stock_release.7z"
"$vsp" extract-stock "$work/stock_release.7z" "$work/stock-extract"
"$vsp" verify-uboot "$work/stock-extract"

# --- 4. assemble + pack ------------------------------------------------------------
say "assembling files/linux and packing release_$release_date.7z"
mkdir -p "$work/release-stage"
cp -a "$work/stock-extract/files" "$work/release-stage/files"
cp -f "$out/images/linux.img" "$out/images/zImage_dtb" "$out/images/7za" "$work/release-stage/files/linux/"
find "$work/release-stage/files/linux" -maxdepth 1 -printf '    %f\n' | sort
# Plain solid LZMA2, no BCJ2: the on-device 7za (2016) cannot read BCJ2 streams.
( cd "$work/release-stage" && 7z a -mx=9 -m0=lzma2 -mf=off -ms=on "$dist/release_$release_date.7z" files/ >/dev/null )
echo "    wrote $dist/release_$release_date.7z ($(wc -c < "$dist/release_$release_date.7z") bytes)"

# --- 5. round trip under the pinned ARM 7za ----------------------------------------
say "round-tripping the archive under the pinned ARM 7za (qemu-arm)"
"$vsp" fetch-7za "$work/7za"
"$vsp" roundtrip "$dist/release_$release_date.7z" "$work/7za" "$work/downloader-extract" "$out/target"
"$vsp" verify-uboot "$work/downloader-extract" --hash-only
"$vsp" verify-layout "$dist/release_$release_date.7z" "$work/release-stage"

# --- 6. SHA256SUMS -------------------------------------------------------------------
say "SHA256SUMS"
( cd "$dist" && sha256sum "release_$release_date.7z" linux.img zImage_dtb zImage_dtb-rt buildroot.config linux.config linux-rt.config legal-info.tar.gz > SHA256SUMS && cat SHA256SUMS )
# The stock archive stays for scripts/mk-sdcard.sh, which reuses it through
# fetch-sdcard-payload.sh's cache instead of downloading it again.
say "done: $dist ready; stock archive kept at $work/stock_release.7z for mk-sdcard.sh"
