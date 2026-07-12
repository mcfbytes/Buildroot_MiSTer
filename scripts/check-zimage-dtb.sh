#!/bin/sh
#
# check-zimage-dtb.sh — assert the U-Boot <-> kernel contract for `zImage_dtb` (A3).
#
# Stock MiSTer U-Boot boots the kernel with:
#
#     load mmc 0:$mmc_boot $loadaddr $bootimage        # loads the WHOLE zImage_dtb
#     setexpr.l fdt_addr $loadaddr + 0x2C              # fdt_addr = &zImage[0x2C]
#     setexpr.l fdt_addr *$fdt_addr + $loadaddr        # fdt_addr = loadaddr + *(loadaddr+0x2C)
#     bootz $loadaddr - $fdt_addr
#
# (work/U-Boot_MiSTer @ 8dcc3484, include/configs/socfpga_de10_nano.h:54-60)
#
# So the DTB MUST begin at exactly the byte offset stored in the zImage header's
# declared-size field at +0x2C — which a plain `cat zImage dtb` guarantees, and
# which nothing else does. This script proves it for a built artifact.
#
# It also enforces the load-region budget: U-Boot loads the kernel blob at
# loadaddr=0x01000000 and stages FPGA bitstreams at fpgadata=0x02000000, so the
# blob must stay strictly under 16 MiB.
#
# Usage: scripts/check-zimage-dtb.sh <zImage_dtb>
# Exit:  0 = all assertions pass, 1 = a contract violation, 2 = usage/IO error.

set -eu

ZIMAGE_MAGIC=016f2818   # arch/arm/boot/compressed/head.S, at zImage +0x24 (LE)
DTB_MAGIC=d00dfeed      # FDT header magic (big-endian)
LOADADDR=16777216       # 0x01000000 — U-Boot $loadaddr
FPGADATA=33554432       # 0x02000000 — U-Boot $fpgadata (first byte we must not reach)
BUDGET=$((FPGADATA - LOADADDR))

prog=${0##*/}
fail=0

usage() {
	echo "usage: $prog <zImage_dtb>" >&2
	exit 2
}

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }

# hex32le FILE OFFSET -> decimal value of the little-endian u32 at OFFSET
hex32le() {
	_b=$(od -An -tx1 -j "$2" -N 4 -v "$1" | tr -d ' \n')
	[ ${#_b} -eq 8 ] || { echo "$prog: short read at offset $2 of $1" >&2; exit 2; }
	# bytes are b0 b1 b2 b3 (little-endian) -> 0xb3b2b1b0
	printf '%d' "0x$(echo "$_b" | cut -c7-8)$(echo "$_b" | cut -c5-6)$(echo "$_b" | cut -c3-4)$(echo "$_b" | cut -c1-2)"
}

# hex32be FILE OFFSET -> decimal value of the big-endian u32 at OFFSET
hex32be() {
	_b=$(od -An -tx1 -j "$2" -N 4 -v "$1" | tr -d ' \n')
	[ ${#_b} -eq 8 ] || { echo "$prog: short read at offset $2 of $1" >&2; exit 2; }
	printf '%d' "0x$_b"
}

[ $# -eq 1 ] || usage
img=$1
[ -f "$img" ] || { echo "$prog: no such file: $img" >&2; exit 2; }

size=$(wc -c < "$img" | tr -d ' ')
printf '%s: %s (%s bytes)\n' "$prog" "$img" "$size"
[ "$size" -gt 64 ] || { echo "$prog: file too small to be a zImage" >&2; exit 2; }

# --- 1. It really is an ARM zImage ------------------------------------------
magic=$(hex32le "$img" 36)                       # 36 = 0x24
if [ "$(printf '%08x' "$magic")" = "$ZIMAGE_MAGIC" ]; then
	ok "zImage magic 0x$ZIMAGE_MAGIC present at +0x24"
else
	bad "zImage magic at +0x24 is 0x$(printf '%08x' "$magic"), expected 0x$ZIMAGE_MAGIC"
	exit 1
fi

# --- 2. The declared end == where the DTB must start -------------------------
zstart=$(hex32le "$img" 40)                      # 40 = 0x28, zimage_start
zend=$(hex32le "$img" 44)                        # 44 = 0x2C, zimage_end  <-- U-Boot reads THIS
note "zImage declared start (+0x28) = $zstart"
note "zImage declared end   (+0x2C) = $zend   <- U-Boot's fdt_addr offset"
note "U-Boot computes fdt_addr = 0x$(printf '%08x' "$LOADADDR") + 0x$(printf '%08x' "$zend") = 0x$(printf '%08x' $((LOADADDR + zend)))"

if [ "$zend" -le 0 ] || [ "$zend" -ge "$size" ]; then
	bad "declared end ($zend) is outside the file (size $size) — nothing was appended?"
	exit 1
fi

# --- 3. A DTB starts exactly there -------------------------------------------
dmag=$(hex32be "$img" "$zend")
if [ "$(printf '%08x' "$dmag")" = "$DTB_MAGIC" ]; then
	ok "DTB magic 0x$DTB_MAGIC sits exactly at the declared end ($zend)"
else
	bad "no DTB magic at offset $zend (found 0x$(printf '%08x' "$dmag")) — zImage and DTB are misaligned"
	bad "the artifact must be produced by a plain 'cat zImage dtb', with no padding"
	exit 1
fi

# --- 4. The DTB is the last thing in the file --------------------------------
dsize=$(hex32be "$img" $((zend + 4)))            # FDT totalsize
note "DTB totalsize = $dsize"
if [ $((zend + dsize)) -eq "$size" ]; then
	ok "DTB totalsize reaches exactly EOF ($zend + $dsize = $size)"
else
	bad "DTB does not end at EOF: $zend + $dsize = $((zend + dsize)), file is $size bytes"
fi

# --- 5. Load-region budget ---------------------------------------------------
if [ "$size" -lt "$BUDGET" ]; then
	ok "size $size < 16 MiB budget (headroom $((BUDGET - size)) bytes, top addr 0x$(printf '%08x' $((LOADADDR + size))))"
else
	bad "size $size >= budget $BUDGET: the blob would overrun \$fpgadata (0x$(printf '%08x' "$FPGADATA"))"
fi

if [ "$fail" -eq 0 ]; then
	echo "$prog: all assertions passed"
else
	echo "$prog: CONTRACT VIOLATED" >&2
fi
exit "$fail"
