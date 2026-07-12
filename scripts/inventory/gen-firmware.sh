#!/usr/bin/env bash
# scripts/inventory/gen-firmware.sh <rootfs-image-or-dir>
#
# Item (d): full /usr/lib/firmware file list with sizes, grouped by vendor
# dir, and the corrected file count (PLAN.md/TASKS.md say "72 firmware
# files"; that figure counts directories -- see the generated doc for the
# reconciliation, which is now the authoritative count).
#
# Writes docs/stock-inventory/firmware.md.
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-firmware.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -ne 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir>" >&2
	exit 2
fi

mrl_require python3

root="$(mrl_extract_root "$1")"
outdir="$(mrl_out_dir)"
out_md="$outdir/firmware.md"
tmp_body="$(mktemp)"
MRL_CLEANUP_DIRS+=("$tmp_body")

python3 "$here/build_firmware.py" "$root" "$tmp_body"

{
	mrl_header "Firmware inventory: /usr/lib/firmware (item d)" \
		"Evidence method: find -type f / -type d on the extracted rootfs tree, cross-checked with debugfs -R \"ls -l /usr/lib/firmware\" on the raw image." \
		"Source: $(mrl_source_label "$1")"
	cat "$tmp_body"
} >"$out_md"

echo "Wrote $out_md"
