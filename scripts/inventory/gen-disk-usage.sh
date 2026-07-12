#!/usr/bin/env bash
# scripts/inventory/gen-disk-usage.sh <rootfs-image-or-dir>
#
# Item (g): disk usage by top-level directory, plus a package-ish second
# cut under /usr/lib, /usr/share, /usr/bin, /usr/sbin (feeds P2.7's size
# budget and P0.7's "what should we drop").
#
# Writes docs/stock-inventory/disk-usage.md.
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-disk-usage.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -ne 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir>" >&2
	exit 2
fi

mrl_require python3

root="$(mrl_extract_root "$1")"
outdir="$(mrl_out_dir)"
out_md="$outdir/disk-usage.md"
tmp_body="$(mktemp)"
MRL_CLEANUP_DIRS+=("$tmp_body")

python3 "$here/build_disk_usage.py" "$root" "$tmp_body"

{
	mrl_header "Disk usage by top-level directory (item g)" \
		"Evidence method: Python os.walk/stat summing regular-file st_size (apparent content size, not block-allocated du(1) size) on the extracted rootfs tree." \
		"Source: $(mrl_source_label "$1")"
	cat "$tmp_body"
} >"$out_md"

echo "Wrote $out_md"
