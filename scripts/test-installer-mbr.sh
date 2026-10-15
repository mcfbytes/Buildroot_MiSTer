#!/usr/bin/env bash
# test-installer-mbr.sh -- the installer's shell MBR writer must produce the SAME 512 bytes
# as sfdisk for the same layout, run on the BusyBox ash we ship. docs/installer-init.md#partition-layout
#
# Usage: scripts/test-installer-mbr.sh [path/to/install] [path/to/busybox]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${1:-}"; INSTALL="${INSTALL:-$ROOT/board/mister/de10nano/installer-overlay/usr/libexec/mister-installer/install}"
BUSYBOX="${2:-$ROOT/output/build/mister-initramfs/root/bin/busybox}"
mkdir -p "${TMPDIR:-$ROOT/work}"
WORK="$(mktemp -d "${TMPDIR:-$ROOT/work}/installer-mbr-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

log()  { printf '[test-mbr] %s\n' "$*"; }
die()  { printf '[test-mbr] FATAL: %s\n' "$*" >&2; exit 2; }
FAILED=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; FAILED=1; }

command -v sfdisk >/dev/null || die "needs sfdisk (util-linux) as the reference"
[ -x "$BUSYBOX" ] || die "no BusyBox at $BUSYBOX -- run 'make mister-initramfs' first"
# The shipped (ARM) BusyBox runs under qemu-arm; a host BusyBox (CI's lint job) runs as is.
RUN=()
if file -b "$BUSYBOX" | grep -q 'ARM'; then
	command -v qemu-arm >/dev/null || die "needs qemu-arm (qemu-user) to run the shipped BusyBox"
	RUN=(qemu-arm)
fi

sed -n '/^# >>> MBR SECTION BEGIN/,/^# >>> MBR SECTION END/p' "$INSTALL" > "$WORK/mbr.sh"
grep -q '^mbr_build()' "$WORK/mbr.sh" || die "no MBR SECTION (with mbr_build) in $INSTALL"
FLAG_CONF="$ROOT/board/mister/common/initramfs-overlay/usr/lib/mister/install-flag.conf"
# shellcheck source=board/mister/common/initramfs-overlay/usr/lib/mister/install-flag.conf
. "$FLAG_CONF"
P1=2048; P2SZ=8192; ID=0x12345678
# Entry 3 as genimage writes it for genimage-sdcard.cfg's flag partition (sfdisk will not put
# a partition in the pre-p1 gap): type 0xda, LBA 1024 (CHS 0/16/17), 1024 sectors.
FLAG_ENTRY='\x00\x10\x11\x00\xda\x20\x20\x00\x00\x04\x00\x00\x00\x04\x00\x00'

# check NAME SECTORS -- one card size, both ways, byte-compared.
check() {
	local name=$1 sectors=$2 data p2
	data=$(( sectors - P1 - P2SZ )); p2=$(( sectors - P2SZ ))
	truncate -s 0 "$WORK/ours.img" "$WORK/ref.img"
	truncate -s $(( sectors * 512 )) "$WORK/ours.img" "$WORK/ref.img"

	# shellcheck disable=SC2016  # the script runs inside BusyBox sh, not here
	"${RUN[@]}" "$BUSYBOX" sh -c '
		set -eu; . "$1"; img=$2
		id="$(oct 0x78)$(oct 0x56)$(oct 0x34)$(oct 0x12)"
		dd if="$img" of="$img.old" bs=512 count=1 2>/dev/null
		mbr_build "$img.new" "$img.old" "$id" \
			"$(mbr_entry 7 "$3" "$4")" "$(mbr_entry 0xa2 "$5" "$6")" \
			"$(mbr_entry "$9" "$7" "$8")" "$MBR_EMPTY_ENTRY"
		dd if="$img.new" of="$img" bs=512 count=1 conv=notrunc 2>/dev/null
	' sh "$WORK/mbr.sh" "$WORK/ours.img" "$P1" "$data" "$p2" "$P2SZ" "$FLAG_LBA" "$FLAG_SECTORS" "$FLAG_TYPE" ||
		{ fail "$name: the shipped ash could not build the MBR"; return; }

	sfdisk --quiet --no-reread --no-tell-kernel "$WORK/ref.img" >/dev/null 2>&1 <<-EOF || { fail "$name: sfdisk refused the layout"; return; }
	label: dos
	label-id: $ID
	start=$P1, size=$data, type=7
	start=$p2, size=$P2SZ, type=a2
	EOF
	# shellcheck disable=SC2059  # the format IS the 16 bytes
	printf "$FLAG_ENTRY" | dd of="$WORK/ref.img" bs=1 seek=478 conv=notrunc status=none

	if cmp -s <(head -c 512 "$WORK/ours.img") <(head -c 512 "$WORK/ref.img"); then
		pass "$name ($sectors sectors): byte-identical to sfdisk"
	else
		fail "$name ($sectors sectors): differs from sfdisk"
		cmp -l <(head -c 512 "$WORK/ours.img") <(head -c 512 "$WORK/ref.img") | head -8 >&2 || true
	fi
}

log "MBR writer from $INSTALL, run under $BUSYBOX"
check "8 MiB (test image)"    16384
check "2 GiB card"            4194304
check "64 GB card"            124735488
check "256 GB card"           500170752
check "1.5 TiB (past 2^31)"   3221225472
check "MBR limit (2^32-1)"    4294967295
if [ "$FAILED" = 0 ]; then log "PASS"; else log "FAIL"; exit 1; fi
