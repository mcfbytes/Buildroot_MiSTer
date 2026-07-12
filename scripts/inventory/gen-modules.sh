#!/usr/bin/env bash
# scripts/inventory/gen-modules.sh <rootfs-image-or-dir>
#
# Item (h): the 52 `.ko.xz` modules with dependencies (parsed from
# modules.dep), grouped by driver family (mac80211 stack, mt76*, rt2x00*,
# rtlwifi, rtl8xxxu, out-of-tree Realtek, Bluetooth USB, xone), mapped to a
# P0.4 class/disposition and owning Phase 3 task, plus the modules.alias
# count and the udev-autoload mechanism (P3.3).
#
# Writes docs/stock-inventory/modules.md.
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-modules.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -ne 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir>" >&2
	exit 2
fi

mrl_require python3

root="$(mrl_extract_root "$1")"
outdir="$(mrl_out_dir)"
out_md="$outdir/modules.md"
tmp_body="$(mktemp)"
MRL_CLEANUP_DIRS+=("$tmp_body")

python3 "$here/build_modules.py" "$root" "$tmp_body"

{
	mrl_header "Kernel modules (item h)" \
		"Evidence method: parse modules.dep/modules.alias/modules.builtin directly from usr/lib/modules/<version>/ on the extracted rootfs tree." \
		"Source: $(mrl_source_label "$1")"
	cat "$tmp_body"
} >"$out_md"

echo "Wrote $out_md"
