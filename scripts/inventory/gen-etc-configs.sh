#!/usr/bin/env bash
# scripts/inventory/gen-etc-configs.sh <rootfs-image-or-dir>
#
# Item (c): /etc configs verbatim-listed (init scripts, inittab, fstab,
# smb.conf, wpa_supplicant, sshd_config, ...), the A8 six-destination
# regular-file check, and the default-credential posture (reported
# factually, without embedding password hashes or private SSH host keys
# into this repo -- see the doc body for why).
#
# Writes docs/stock-inventory/etc-configs.md and
# docs/stock-inventory/etc-init-scripts-full.txt.
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-etc-configs.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -ne 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir>" >&2
	exit 2
fi

mrl_require python3

root="$(mrl_extract_root "$1")"
outdir="$(mrl_out_dir)"
out_md="$outdir/etc-configs.md"
out_init_txt="$outdir/etc-init-scripts-full.txt"
tmp_body="$(mktemp)"
MRL_CLEANUP_DIRS+=("$tmp_body")

python3 "$here/build_etc_configs.py" "$root" "$tmp_body" "$out_init_txt"

{
	mrl_header "/etc configuration inventory (item c)" \
		"Evidence method: direct file reads + os.path.islink()/isfile() on the extracted rootfs tree (symlinks preserved -- see docs/reference-materials.md section 3)." \
		"Source: $(mrl_source_label "$1")"
	cat "$tmp_body"
} >"$out_md"

echo "Wrote $out_md"
echo "Wrote $out_init_txt"
