#!/usr/bin/env bash
# scripts/inventory/run-all.sh <rootfs-image-or-dir> [zImage_dtb] [MiSTer-binary]
#
# Regenerates the entire docs/stock-inventory/ tree in one command (P0.3
# "Done when" criterion). See README.md in this directory for the full
# per-item breakdown; this is just the runner.
#
# Arguments:
#   1. rootfs-image-or-dir (required) -- an ext4 image file (e.g.
#      work/extracted/files/linux/linux.img) or an already-extracted root
#      directory (e.g. work/imgroot). Every gen-*.sh script that inspects
#      the rootfs (items a, b, c, d, e, g, h) takes this same argument.
#   2. zImage_dtb (optional) -- feeds item (f), the kernel config + DTS
#      regeneration. Skipped with a warning if omitted.
#   3. MiSTer-binary (optional) -- the stock `MiSTer` binary (ships outside
#      linux.img, in the release archive's files/MiSTer). Folded into item
#      (b)'s NEEDED union/dangling-dep analysis and called out by name if
#      given; item (b) still runs without it.
#
# Nothing here requires root. Exits nonzero if any generator reports a
# real problem (e.g. a genuine kernel-config/DTS content diff, or a
# dangling NEEDED dependency) -- see each generator's own exit-code
# contract in its header comment.
set -uo pipefail  # deliberately not -e: run every generator, then report

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
	echo "usage: $0 <rootfs-image-or-dir> [zImage_dtb] [MiSTer-binary]" >&2
	exit 2
fi
image="$1"
zimage_dtb="${2:-}"
mister_binary="${3:-}"

# Extract the image ONCE and hand every generator the resulting directory.
# Each gen-*.sh accepts either an image or an already-extracted root, so
# passing "$image" through to all seven would re-run the same ~300 MB
# debugfs rdump seven times over.
# shellcheck source=scripts/inventory/common.sh
. "$here/common.sh"
root="$(mrl_extract_root "$image")"

# The generators would otherwise header themselves with $root -- a mktemp path
# that changes every run, which is exactly the nondeterminism these diffable
# docs must not have. Name the real source instead.
export MRL_SOURCE_LABEL="${MRL_SOURCE_LABEL:-$(basename "$image")}"

declare -A RESULTS

run_step() {
	local name="$1"
	shift
	echo "=== $name ==="
	if "$@"; then
		RESULTS["$name"]="ok"
	else
		RESULTS["$name"]="FAILED (exit $?)"
	fi
	echo
}

run_step "a: shared libraries"   "$here/gen-shared-libs.sh"   "$root"
run_step "b: binaries + NEEDED"  "$here/gen-binaries.sh"      "$root" ${mister_binary:+"$mister_binary"}
run_step "c: /etc configs"       "$here/gen-etc-configs.sh"   "$root"
run_step "d: firmware"           "$here/gen-firmware.sh"      "$root"
run_step "e: busybox applets"    "$here/gen-busybox.sh"       "$root"
if [ -n "$zimage_dtb" ]; then
	run_step "f: kernel config + DTS" "$here/gen-kernel-config-dts.sh" "$zimage_dtb"
else
	echo "=== f: kernel config + DTS ==="
	echo "SKIPPED -- no zImage_dtb argument given"
	echo
	RESULTS["f: kernel config + DTS"]="skipped"
fi
run_step "g: disk usage"         "$here/gen-disk-usage.sh"    "$root"
run_step "h: modules"            "$here/gen-modules.sh"       "$root"

echo "=== Summary ==="
status=0
for name in "a: shared libraries" "b: binaries + NEEDED" "c: /etc configs" \
	"d: firmware" "e: busybox applets" "f: kernel config + DTS" \
	"g: disk usage" "h: modules"; do
	result="${RESULTS[$name]:-(not run)}"
	printf '%-28s %s\n' "$name" "$result"
	case "$result" in
		FAILED*) status=1 ;;
	esac
done

exit "$status"
