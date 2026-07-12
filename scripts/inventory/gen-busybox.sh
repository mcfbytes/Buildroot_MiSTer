#!/usr/bin/env bash
# scripts/inventory/gen-busybox.sh <rootfs-image-or-dir>
#
# Item (e): BusyBox version and applet list.
#
# Evidence method: run the actual stock `busybox` binary under `qemu-arm`
# user-mode emulation (with -L pointed at the rootfs so its dynamic
# dependencies, e.g. libpam, resolve) rather than guessing from a build
# config -- this is the same binary that runs on the real target.
#
# Writes docs/stock-inventory/busybox-applets.md.
#
# shellcheck disable=SC2016,SC1091,SC2034
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-busybox.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -ne 1 ]; then
	echo "usage: $0 <rootfs-image-or-dir>" >&2
	exit 2
fi

mrl_require qemu-arm

root="$(mrl_extract_root "$1")"

busybox_rel=""
busybox_bin=""
for cand in bin/busybox usr/bin/busybox; do
	if [ -f "$root/$cand" ]; then
		busybox_rel="$cand"
		busybox_bin="$root/$cand"
		break
	fi
done
if [ -z "$busybox_bin" ]; then
	echo "error: no busybox binary found under bin/ or usr/bin/ in '$1'" >&2
	exit 1
fi

# NOTE: `| head -1` on a still-writing producer causes SIGPIPE once head
# closes the pipe after its first line; under `set -o pipefail` that makes
# the whole pipeline's exit status nonzero, which would abort the script
# (even inside a command substitution assignment) without the trailing
# `|| true` -- the captured text itself is unaffected either way.
version_line="$(qemu-arm -L "$root" "$busybox_bin" 2>&1 | head -1)" || true
applets="$(qemu-arm -L "$root" "$busybox_bin" --list 2>/dev/null | LC_ALL=C sort)"
applet_count="$(printf '%s\n' "$applets" | grep -c .)"

outdir="$(mrl_out_dir)"
out_md="$outdir/busybox-applets.md"

{
	mrl_header "BusyBox applets (item e)" \
		"Evidence method: qemu-arm -L <rootfs> <busybox> [--list], executing the actual stock binary under user-mode ARM emulation (not a guess from a build config)." \
		"Source: $(mrl_source_label "$1")" \
		"Binary: /$busybox_rel (within the rootfs)"
	printf 'Version banner: `%s`\n\n' "$version_line"
	printf 'Applet count (`busybox --list`): **%s**\n\n' "$applet_count"
	printf '```\n%s\n```\n' "$applets"
} >"$out_md"

echo "Wrote $out_md"
