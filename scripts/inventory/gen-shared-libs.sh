#!/usr/bin/env bash
# scripts/inventory/gen-shared-libs.sh <rootfs-image-or-dir>
#
# Item (a): every shared library with its SONAME, the real file it
# resolves to, and its symlink chain (e.g. `libc.so.6 -> libc-2.31.so`).
# The SONAME is the ABI-relevant name P0.5/P0.7/P2.2 consume, not the
# on-disk filename.
#
# Evidence method: `readelf -h` (ELF type) and `readelf -d` (SONAME) via
# scripts/inventory/elf_scan.py, over every regular ELF file in the tree.
#
# Writes docs/stock-inventory/shared-libraries.md (summary) and
# docs/stock-inventory/shared-libraries-full.txt (full sorted list +
# symlink chains).
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-shared-libs.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -ne 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir>" >&2
	exit 2
fi

mrl_require python3 readelf

root="$(mrl_extract_root "$1")"
outdir="$(mrl_out_dir)"
out_md="$outdir/shared-libraries.md"
out_txt="$outdir/shared-libraries-full.txt"
tmp_body="$(mktemp)"
MRL_CLEANUP_DIRS+=("$tmp_body")

python3 "$here/build_shared_libs.py" "$root" "$tmp_body" "$out_txt"

{
	mrl_header "Shared libraries (item a)" \
		"Evidence method: readelf -h (ELF type) + readelf -d (DT_SONAME) via scripts/inventory/elf_scan.py, run over every regular ELF file in the rootfs." \
		"Source: $(mrl_source_label "$1")"
	cat "$tmp_body"
} >"$out_md"

echo "Wrote $out_md"
echo "Wrote $out_txt"
