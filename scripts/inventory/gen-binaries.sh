#!/usr/bin/env bash
# scripts/inventory/gen-binaries.sh <rootfs-image-or-dir> [extra-elf-binary ...]
#
# Item (b): every ELF binary's DT_NEEDED set, the union of all NEEDED
# across the image (the set P0.7 must map to Buildroot packages), and any
# dangling NEEDED entry (required but not provided anywhere in the image).
#
# Pass the stock `MiSTer` binary (work/extracted/files/MiSTer -- it ships
# in the release archive, outside linux.img) as an extra-elf argument to
# fold it into the union/dangling-dep analysis and get it called out by
# name in the generated doc, per PLAN §3 / P0.5 (it IS the ABI contract).
#
# Evidence method: readelf -h/-d via scripts/inventory/elf_scan.py.
#
# Writes docs/stock-inventory/binaries-needed.md (summary + MiSTer/busybox
# callouts + dangling-dep report), binaries-needed-full.txt (every binary's
# NEEDED set), and binaries-needed-union.txt (deduplicated SONAME list).
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-binaries.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -lt 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir> [extra-elf-binary ...]" >&2
	exit 2
fi

mrl_require python3 readelf

image="$1"
shift
extra=("$@")

root="$(mrl_extract_root "$image")"
outdir="$(mrl_out_dir)"
out_md="$outdir/binaries-needed.md"
out_txt="$outdir/binaries-needed-full.txt"
out_union="$outdir/binaries-needed-union.txt"
tmp_body="$(mktemp)"
MRL_CLEANUP_DIRS+=("$tmp_body")

python3 "$here/build_binaries.py" "$root" "$tmp_body" "$out_txt" "$out_union" "${extra[@]}"

{
	mrl_header "Binaries and their NEEDED sets (item b)" \
		"Evidence method: readelf -h (ELF type) + readelf -d (DT_NEEDED) via scripts/inventory/elf_scan.py, run over every regular ELF file in the rootfs." \
		"Source: $(mrl_source_label "$image")" \
		"Extra ELF files folded in: ${extra[*]:-(none)}"
	cat "$tmp_body"
} >"$out_md"

echo "Wrote $out_md"
echo "Wrote $out_txt"
echo "Wrote $out_union"
