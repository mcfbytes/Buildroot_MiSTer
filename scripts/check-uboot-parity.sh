#!/bin/sh
#
# check-uboot-parity.sh — assert that a from-source U-Boot for the DE10-Nano is
# interchangeable with the stock 2017.03 fork blob (plan §6).
#
# WHY THIS EXISTS. The DE10-Nano's bootloader is the one part of the image that
# cannot be tested by booting it: a wrong SPL header, a short SPL copy or a
# changed environment does not fail a build, it bricks a card that can only be
# recovered with a second reader. The owner's target for the mainline build is
# "as close as possible to what stock does" (docs/uboot-tasks.md), so parity
# with the shipped blob IS the specification, and this script is how that
# specification is checked without a board.
#
# WHAT IT CHECKS, and where each rule comes from:
#
#   Structural (docs/uboot-mainline-port.md §6, boot-chain §2)
#     * four byte-identical 64 KiB SPL copies at 0x00000/0x10000/0x20000/0x30000
#       — the BootROM tries each in turn, so they are a redundancy contract, not
#       a layout accident;
#     * the Altera/socfpga SPL header at +0x40: validation word 0x31305341,
#       length_u32, and the header checksum recomputed exactly as
#       `sfp_hdr_checksum` computes it (u-boot 2026.07 tools/socfpgaimage.c:121,
#       whose `while (--len)` at :126 sums only the first 9 of the 12 header
#       bytes — reproduce the tool, not the intent), plus the payload CRC32 that
#       `pbl_crc32` (tools/pbl_crc32.c:42) stores at the end of the payload;
#     * a legacy uImage at 0x40000 whose header CRC and payload CRC recompute,
#       whose ih_load is 0x01000040, and whose payload closes the file exactly;
#     * SPL payload size against the 64 KiB slot (and against $SPL_SIZE_LIMIT /
#       u-boot:tools/spl_size_limit when the caller has one — plan §3.5: 2017.03
#       does NOT enforce it and silently truncates length_u32 instead).
#
#   Environment (plan §6, boot-chain §3.1)
#     The default_environment[] blob must be BYTE-IDENTICAL to stock's — 21
#     entries, 1,150 B, malformed entry 15 and all. With the fork's `mt` command
#     carried (plan §3.4, decided 2026-09-14) there is no allowed delta left, so
#     this is a plain cmp; the entry-by-entry diff is printed only as the
#     diagnostic when the cmp fails. Stock's blob lives at offset 0x28018 of the
#     U-Boot-proper payload (i.e. 0x68058 in the .img); the built blob is located
#     from the ELF (`nm -S u-boot` -> addr - ih_load) when one is passed, and by
#     scanning for the blob otherwise. Note that u-boot-initial-env is NOT used:
#     it is sorted and can be stale.
#
#   Command table (plan §6, boot-chain §3.3)
#     Every one of stock's 69 command names must exist in the built binary
#     (`mt` included); extra mainline commands are allowed and listed. Both
#     tables are recovered the same way: the longest run of `struct cmd_tbl`
#     records that validate as a linker list (U_BOOT_CMD; the records are
#     emitted sorted by name into .u_boot_list_2_cmd_2_*). The third word of the
#     record is `int repeatable` in the fork and the `cmd_rep` function pointer
#     in mainline, so both spellings are accepted — see recname() below. This is
#     the check that a `git bisect`-sized Kconfig slip silently breaks.
#
#   Allowed diffs, named in the output rather than ignored (plan §6): version
#   string and build timestamp, uImage ih_ep 0x01000040 vs 0, total size, code
#   layout and table offsets. Forbidden: any environment byte, a missing stock
#   command, a layout/offset change of the SPL copies or the uImage, a load
#   address change, any SPL header field change.
#
# NOT CHECKED HERE: the QTS handoff tables (§3.2a) — that is
# scripts/check-uboot-handoff.sh, which needs the carried qts/*.h as a third
# input. This script and that one are the two halves of plan §6.
#
# All the binary arithmetic is done in awk with no bitwise builtins — POSIX awk
# has none — fed from `od`. That keeps the script POSIX sh with no host
# dependency beyond coreutils and awk; the only optional tool is `nm`, and only
# for the third argument. Verified to give identical results under gawk, mawk,
# the one-true awk (nawk) and this image's own BusyBox awk (via qemu-arm).
#
# Usage: scripts/check-uboot-parity.sh <built.sfp> <stock-uboot.img> [u-boot-elf]
#   <built.sfp>       the image under test (u-boot-with-spl.sfp, or a uboot.img)
#   <stock-uboot.img> the reference blob (scripts/fetch-sdcard-payload.sh fetches
#                     it by hash as STOCK_UBOOT_SHA256)
#   [u-boot-elf]      optional: the built u-boot ELF, used to locate
#                     default_environment[] exactly instead of by scan
# Env:
#   NM               nm to use for the ELF (default: nm)
#   SPL_SIZE_LIMIT   byte limit for the SPL payload, e.g. the output of the
#                    U-Boot tree's tools/spl_size_limit (default: unset, only
#                    the 64 KiB slot is enforced)
# Exit:  0 = parity holds, 1 = a contract violation, 2 = usage/IO error.

set -eu

# Byte-wise, locale-independent: `sort`/`comm` must agree on collation and no
# text comparison here is linguistic (same reason as scripts/check-abi.sh:78).
export LC_ALL=C

SPL_COPIES=4
SPL_SLOT=65536          # 0x10000 — one BootROM SPL slot
UIMG_OFF=262144         # 0x40000 — where the legacy uImage starts
UIMG_HDR=64             # sizeof(image_header_t)
SPL_HDR_OFF=64          # 0x40 — struct socfpga_header inside the SPL
SPL_VALIDATION=31305341 # 'A' 'S' '0' '1' little-endian
UIMG_MAGIC=27051956     # IH_MAGIC, big-endian
TEXT_BASE=16777280      # 0x01000040 — ih_load, and the U-Boot proper link base
STOCK_ENV_OFF=163864    # 0x28018 in the U-Boot proper payload (plan §6)
STOCK_ENV_LEN=1150      # 21 entries incl. the terminating NUL (plan §6)

prog=${0##*/}
fail=0

usage() {
	echo "usage: $prog <built.sfp> <stock-uboot.img> [u-boot-elf]" >&2
	exit 2
}

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }
die()  { echo "$prog: $*" >&2; exit 2; }

hx()   { printf '0x%08x' "$1"; }

# rdbytes FILE OFFSET LEN -> the bytes as decimal, one field per byte
rdbytes() { od -An -tu1 -v -j "$2" -N "$3" "$1"; }

# u32le/u32be/u16le/u8 FILE OFFSET -> decimal value of the integer at OFFSET
u32le() {
	_b=$(od -An -tx1 -j "$2" -N 4 -v "$1" | tr -d ' \n')
	[ ${#_b} -eq 8 ] || die "short read of 4 bytes at offset $2 of $1"
	printf '%d' "0x$(echo "$_b" | cut -c7-8)$(echo "$_b" | cut -c5-6)$(echo "$_b" | cut -c3-4)$(echo "$_b" | cut -c1-2)"
}
u32be() {
	_b=$(od -An -tx1 -j "$2" -N 4 -v "$1" | tr -d ' \n')
	[ ${#_b} -eq 8 ] || die "short read of 4 bytes at offset $2 of $1"
	printf '%d' "0x$_b"
}
u16le() {
	_b=$(od -An -tx1 -j "$2" -N 2 -v "$1" | tr -d ' \n')
	[ ${#_b} -eq 4 ] || die "short read of 2 bytes at offset $2 of $1"
	printf '%d' "0x$(echo "$_b" | cut -c3-4)$(echo "$_b" | cut -c1-2)"
}
u8() {
	_b=$(od -An -tx1 -j "$2" -N 1 -v "$1" | tr -d ' \n')
	[ ${#_b} -eq 2 ] || die "short read of 1 byte at offset $2 of $1"
	printf '%d' "0x$_b"
}

# --- CRC32, two flavours, in portable awk ------------------------------------
# MODE=zlib : the reflected CRC32 of include/u-boot/crc.h, used by mkimage for
#             the uImage header and payload CRCs.
# MODE=pbl  : tools/pbl_crc32.c:42-57 — poly 0x04c11db7, MSB-first, seeded
#             0xffffffff and complemented on the way out, used by
#             tools/socfpgaimage.c for the SPL payload.
# Both are table-driven and use an explicit xor table, because POSIX awk has no
# bitwise operators (gawk/mawk/busybox awk all agree on plain arithmetic).
# shellcheck disable=SC2016  # this is an awk program, not shell: $f/$1 are awk's
CRC_AWK='
function xor32(a, b,   r, m, i) {
	r = 0; m = 1
	for (i = 0; i < 4; i++) {
		r += X8[(a % 256) * 256 + (b % 256)] * m
		a = int(a / 256); b = int(b / 256); m *= 256
	}
	return r
}
BEGIN {
	for (i = 0; i < 16; i++) for (j = 0; j < 16; j++) {
		v = 0; p = 1; a = i; b = j
		for (k = 0; k < 4; k++) {
			if ((a % 2) != (b % 2)) v += p
			a = int(a / 2); b = int(b / 2); p *= 2
		}
		X4[i * 16 + j] = v
	}
	for (i = 0; i < 256; i++) for (j = 0; j < 256; j++)
		X8[i * 256 + j] = X4[int(i / 16) * 16 + int(j / 16)] * 16 + X4[(i % 16) * 16 + (j % 16)]
	if (MODE == "zlib")
		for (i = 0; i < 256; i++) {
			c = i
			for (k = 0; k < 8; k++)
				if (c % 2) c = xor32(3988292384, int(c / 2)); else c = int(c / 2)
			T[i] = c
		}
	else
		for (i = 0; i < 256; i++) {
			m = i * 16777216
			for (k = 0; k < 8; k++)
				if (m >= 2147483648) m = xor32((m * 2) % 4294967296, 79764919)
				else m = (m * 2) % 4294967296
			T[i] = m
		}
	crc = 4294967295
	n = 0
}
{
	for (f = 1; f <= NF; f++) {
		b = $f + 0
		if (MODE == "zlib") crc = xor32(T[X8[(crc % 256) * 256 + b]], int(crc / 256))
		else crc = xor32((crc * 256) % 4294967296, T[X8[int(crc / 16777216) * 256 + b]])
		n++
	}
}
# Print in two 16-bit halves: a CRC >= 2^31 through one %x saturates to
# 0x7fffffff in busybox awk (its printf casts to int).
END { v = 4294967295 - crc; printf "%04x%04x %d\n", int(v / 65536), v % 65536, n }
'

# crc32 FILE OFFSET LEN -> "hexcrc bytecount" (reflected/zlib flavour)
crc32() { rdbytes "$1" "$2" "$3" | awk -v MODE=zlib "$CRC_AWK"; }
# pblcrc FILE OFFSET LEN -> "hexcrc bytecount" (socfpga SPL flavour)
pblcrc() { rdbytes "$1" "$2" "$3" | awk -v MODE=pbl "$CRC_AWK"; }

# --- The U-Boot proper payload: environment blob and command table -----------
# Fed the payload bytes as decimal (od -tu1), with BASE = the link address of
# byte 0 (ih_load).
#
# MODE=env reads default_environment[] from HINT (the ELF-derived payload
# offset) when there is one, and otherwise finds it: anchor on the first of
# "bootcmd=" / "bootargs=" / "baudrate=" that starts immediately after a NUL --
# the NUL matters, or mainline's "distro_bootcmd=" masquerades as the anchor and
# the blob is read from its middle -- then walk back over whole printable
# NUL-terminated entries and forward to the empty entry that terminates the
# blob. The walk-back can still overshoot into neighbouring .rodata strings, so
# the anchored result is reported alongside the ELF one, never instead of it.
#
# MODE=cmd recovers the U_BOOT_CMD linker list: the longest run of struct
# cmd_tbl records that validate, trying the three plausible ARM32 strides
# (CONFIG_SYS_LONGHELP and CONFIG_AUTO_COMPLETE each add a word).
# shellcheck disable=SC2016  # ditto: an awk program quoted whole
PAY_AWK='
function w32(o) { return b[o] + b[o+1] * 256 + b[o+2] * 65536 + b[o+3] * 16777216 }
function inrange(p) { return (p >= BASE && p < BASE + n) }
function cstr(ptr, max,   o, s, c, l) {
	if (ptr == 0) return ""
	o = ptr - BASE
	if (o < 0 || o >= n) return BAD
	s = ""; l = 0
	while (l < max) {
		c = b[o + l]
		if (c == 0) return s
		if (c < 32 || c > 126) return BAD
		s = s sprintf("%c", c); l++
	}
	return BAD
}
# One U_BOOT_CMD record. The third word is `int repeatable` in the 2017.03 fork
# (0 or 1) and the `cmd_rep` FUNCTION POINTER in mainline, which replaced it
# (u-boot:include/command.h) — accept either, or neither table is found.
function recname(o, stride,   np, cp, ma, rp, up, j, nm) {
	if (o < 0 || o + stride > n) return ""
	np = w32(o)
	if (!inrange(np)) return ""
	cp = w32(o + 12)
	if (!inrange(cp)) return ""
	ma = w32(o + 4)
	if (ma < 1 || ma > 255) return ""
	rp = w32(o + 8)
	if (rp > 1 && !inrange(rp)) return ""
	for (j = 16; j < stride; j += 4) {
		up = w32(o + j)
		if (up != 0 && !inrange(up)) return ""
	}
	nm = cstr(np, 16)
	if (nm == "" || nm == BAD || nm ~ /[ \t]/) return ""
	up = w32(o + 16)
	if (up != 0 && cstr(up, 512) == BAD) return ""
	return nm
}
# Walk the NUL-separated entries from S to the empty entry that terminates the
# blob. Returns the blob length (entries plus that terminator), or 0 with EERR
# set. ECNT gets the entry count; with EMIT, each entry is printed.
function walkfwd(s, emit,   p, e, i, t, cnt, term) {
	cnt = 0; p = s; term = 0
	while (p < n) {
		e = p
		while (e < n && b[e] != 0) e++
		if (e >= n) break
		if (e == p) { term = 1; break }
		t = ""
		for (i = p; i < e; i++) {
			if (b[i] < 32 || b[i] > 126) { t = BAD; break }
			t = t sprintf("%c", b[i])
		}
		if (t == BAD) { EERR = "a non-printable byte at payload offset " i; return 0 }
		if (emit) printf "ENTRY %d %d %s\n", cnt, p, t
		cnt++
		p = e + 1
	}
	if (!term) { EERR = "the blob at payload offset " s " has no NUL-NUL terminator"; return 0 }
	ECNT = cnt
	return p + 1 - s
}
# Find the blob without an ELF: anchor on a well-known entry that must start
# right after a NUL (so "distro_bootcmd=" cannot masquerade as "bootcmd="),
# then walk back over whole printable entries. AHITS gets the match count.
function anchor(   o, i, k, np, pat, m, cand, ok, p, c) {
	split("bootcmd= bootargs= baudrate=", pat, " ")
	for (k = 1; k <= 3; k++) {
		np = length(pat[k]); m = -1; AHITS = 0
		for (o = 1; o + np <= n; o++) {
			if (b[o-1] != 0 || b[o] != ORD[substr(pat[k], 1, 1)]) continue
			ok = 1
			for (i = 1; i < np; i++)
				if (b[o+i] != ORD[substr(pat[k], i+1, 1)]) { ok = 0; break }
			if (!ok) continue
			AHITS++
			if (m < 0) m = o
		}
		if (m >= 0) { AWHAT = pat[k]; break }
	}
	if (m < 0) return -1
	while (m > 0) {
		if (b[m-1] != 0) break
		p = m - 2
		while (p >= 0 && b[p] != 0) p--
		if (p < 0) break
		c = cstr(BASE + p + 1, m - p - 1)
		if (c == "" || c == BAD) break
		m = p + 1
	}
	return m
}
{ for (f = 1; f <= NF; f++) b[n++] = $f + 0 }
END {
	BAD = sprintf("%c", 1)
	for (i = 32; i < 127; i++) ORD[sprintf("%c", i)] = i
	if (MODE == "env") {
		a = anchor()
		if (a >= 0) {
			alen = walkfwd(a, 0)
			if (alen > 0) printf "ENVA %d %d %d %s %d\n", a, alen, ECNT, AWHAT, AHITS
		}
		s = (HINT >= 0) ? HINT : a
		if (s < 0) { print "ENVERR no bootcmd=/bootargs=/baudrate= entry to anchor on"; exit 0 }
		blen = walkfwd(s, 1)
		if (blen == 0) { print "ENVERR " EERR; exit 0 }
		printf "ENV %d %d %d\n", s, blen, ECNT
		exit 0
	}
	# MODE == cmd
	best = 0; bs = 0; bstride = 0
	for (si = 0; si < 3; si++) {
		stride = 24 + si * 4
		for (o = 0; o + stride <= n; o += 4) {
			if (recname(o, stride) == "") continue
			run = 1; s = o
			for (p = o - stride; p >= 0; p -= stride) {
				if (recname(p, stride) == "") break
				run++; s = p
			}
			for (p = o + stride; p + stride <= n; p += stride) {
				if (recname(p, stride) == "") break
				run++
			}
			if (run > best) { best = run; bs = s; bstride = stride }
		}
	}
	if (best < 2) { print "CMDERR no command table found"; exit 0 }
	printf "TABLE %d %d %d\n", best, bs, bstride
	for (i = 0; i < best; i++) printf "NAME %s\n", recname(bs + i * bstride, bstride)
}
'

# payscan FILE PAYLOAD_OFF PAYLOAD_LEN BASE MODE [ENV_HINT]
# ENV_HINT is the payload offset of default_environment[] when the ELF gave us
# one; -1 means "find it yourself".
payscan() {
	rdbytes "$1" "$2" "$3" |
		awk -v BASE="$4" -v MODE="$5" -v HINT="${6:--1}" "$PAY_AWK"
}

# ---------------------------------------------------------------------------
[ $# -eq 2 ] || [ $# -eq 3 ] || usage
built=$1
stock=$2
elf=${3:-}

for f in "$built" "$stock" ${elf:+"$elf"}; do
	[ -f "$f" ] || die "no such file: $f"
	[ -r "$f" ] || die "not readable: $f"
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-uboot-parity.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

bsize=$(wc -c < "$built" | tr -d ' ')
ssize=$(wc -c < "$stock" | tr -d ' ')
printf '%s: built  %s (%s bytes)\n' "$prog" "$built" "$bsize"
printf '%s: stock  %s (%s bytes)\n' "$prog" "$stock" "$ssize"
if [ -n "$elf" ]; then printf '%s: elf    %s\n' "$prog" "$elf"; fi

min=$((UIMG_OFF + UIMG_HDR))
[ "$bsize" -gt "$min" ] || die "$built is $bsize bytes, too small to hold an SPL region and a uImage"
[ "$ssize" -gt "$min" ] || die "$stock is $ssize bytes, too small to be the stock uboot.img"

# --- 1. The legacy uImage at 0x40000 ----------------------------------------
echo
echo "[1] legacy uImage header at $(hx $UIMG_OFF)"

smagic=$(u32be "$stock" "$UIMG_OFF")
[ "$(printf '%08x' "$smagic")" = "$UIMG_MAGIC" ] ||
	die "reference $stock has no uImage magic at $(hx $UIMG_OFF) — wrong file?"
sload=$(u32be "$stock" $((UIMG_OFF + 16)))
ssz=$(u32be "$stock" $((UIMG_OFF + 12)))
note "stock: ih_size=$ssz ih_load=$(hx "$sload") ih_ep=$(hx "$(u32be "$stock" $((UIMG_OFF + 20)))")"

bmagic=$(u32be "$built" "$UIMG_OFF")
if [ "$(printf '%08x' "$bmagic")" = "$UIMG_MAGIC" ]; then
	ok "uImage magic 0x$UIMG_MAGIC present at $(hx $UIMG_OFF)"
else
	bad "no uImage magic at $(hx $UIMG_OFF) (found $(hx "$bmagic")) — the SPL region is the wrong size"
	echo "$prog: CONTRACT VIOLATED" >&2
	exit 1
fi

bhcrc=$(u32be "$built" $((UIMG_OFF + 4)))
btime=$(u32be "$built" $((UIMG_OFF + 8)))
bsz=$(u32be "$built" $((UIMG_OFF + 12)))
bload=$(u32be "$built" $((UIMG_OFF + 16)))
bep=$(u32be "$built" $((UIMG_OFF + 20)))
bdcrc=$(u32be "$built" $((UIMG_OFF + 24)))
bos=$(u8 "$built" $((UIMG_OFF + 28)))
barch=$(u8 "$built" $((UIMG_OFF + 29)))
btype=$(u8 "$built" $((UIMG_OFF + 30)))
bcomp=$(u8 "$built" $((UIMG_OFF + 31)))
bname=$(dd if="$built" bs=1 skip=$((UIMG_OFF + 32)) count=32 2>/dev/null | tr -d '\0')
note "ih_name      = \"$bname\""
note "ih_time      = $btime (allowed diff: build timestamp)"
note "ih_size      = $bsz  ih_load = $(hx "$bload")  ih_ep = $(hx "$bep")"
note "os/arch/type/comp = $bos/$barch/$btype/$bcomp (want 17/2/5/0 = U-Boot/ARM/firmware/none)"

if [ "$bos" -eq 17 ] && [ "$barch" -eq 2 ] && [ "$btype" -eq 5 ] && [ "$bcomp" -eq 0 ]; then
	ok "uImage os/arch/type/comp match stock's IH_OS_U_BOOT/IH_ARCH_ARM/IH_TYPE_FIRMWARE/IH_COMP_NONE"
else
	bad "uImage os/arch/type/comp = $bos/$barch/$btype/$bcomp, stock is 17/2/5/0"
fi

if [ "$bload" -eq "$TEXT_BASE" ]; then
	ok "ih_load = $(hx "$bload") — the SPL of the fork jumps to ih_load (common/spl/spl.c:110)"
else
	bad "ih_load = $(hx "$bload"), must be $(hx $TEXT_BASE): stock's SPL would jump into the wrong address"
fi

if [ "$bep" -eq 0 ] || [ "$bep" -eq "$TEXT_BASE" ]; then
	ok "ih_ep = $(hx "$bep") (allowed diff: mainline sets CONFIG_TEXT_BASE, the fork leaves 0 — plan §3.3)"
	[ "$bep" -eq 0 ] || note "mixing warning: a stock SPL reads ih_load, a mainline SPL reads ih_ep (common/spl/spl_legacy.c:57) — do not pair an SPL and a uImage from different builds"
else
	bad "ih_ep = $(hx "$bep"): neither 0 (fork) nor $(hx $TEXT_BASE) (mainline) — a mainline SPL would jump there"
fi

if [ $((UIMG_OFF + UIMG_HDR + bsz)) -eq "$bsize" ]; then
	ok "total size closes the file: $(hx $UIMG_OFF) + $UIMG_HDR + $bsz = $bsize"
else
	bad "ih_size $bsz does not close the file: $(hx $UIMG_OFF) + $UIMG_HDR + $bsz = $((UIMG_OFF + UIMG_HDR + bsz)), file is $bsize"
fi

# header CRC: the 64-byte header with its own ih_hcrc field zeroed
hcrc=$({
	dd if="$built" bs=1 skip="$UIMG_OFF" count=4 2>/dev/null
	printf '\000\000\000\000'
	dd if="$built" bs=1 skip=$((UIMG_OFF + 8)) count=56 2>/dev/null
} | od -An -tu1 -v | awk -v MODE=zlib "$CRC_AWK" | cut -d' ' -f1)
if [ "$hcrc" = "$(printf '%08x' "$bhcrc")" ]; then
	ok "uImage header CRC recomputes: 0x$hcrc"
else
	bad "uImage header CRC is $(hx "$bhcrc") but recomputes to 0x$hcrc"
fi

# payload CRC
crcres=$(crc32 "$built" $((UIMG_OFF + UIMG_HDR)) "$bsz")
dcrc=${crcres%% *}
dread=${crcres##* }
if [ "$dread" -ne "$bsz" ]; then
	bad "uImage payload is short: read $dread of $bsz bytes"
elif [ "$dcrc" = "$(printf '%08x' "$bdcrc")" ]; then
	ok "uImage payload CRC recomputes over all $bsz bytes: 0x$dcrc"
else
	bad "uImage payload CRC is $(hx "$bdcrc") but recomputes to 0x$dcrc — the payload was edited after mkimage"
fi

# --- 2. The four SPL copies --------------------------------------------------
echo
echo "[2] SPL region: $SPL_COPIES copies of $SPL_SLOT bytes"

dd if="$built" bs="$SPL_SLOT" skip=0 count=1 of="$tmp/spl0.bin" 2>/dev/null
i=1
while [ "$i" -lt "$SPL_COPIES" ]; do
	dd if="$built" bs="$SPL_SLOT" skip="$i" count=1 of="$tmp/spl$i.bin" 2>/dev/null
	if cmp -s "$tmp/spl0.bin" "$tmp/spl$i.bin"; then
		ok "SPL copy $i at $(hx $((i * SPL_SLOT))) is byte-identical to copy 0"
	else
		bad "SPL copy $i at $(hx $((i * SPL_SLOT))) differs from copy 0 — the BootROM fallback copies are not interchangeable"
		cmp "$tmp/spl0.bin" "$tmp/spl$i.bin" 2>&1 | sed 's/^/     /' >&2 || true
	fi
	i=$((i + 1))
done

# --- 3. The socfpga SPL header ----------------------------------------------
echo
echo "[3] socfpga SPL header at +$(hx $SPL_HDR_OFF) of copy 0"

val=$(u32le "$built" "$SPL_HDR_OFF")
ver=$(u8 "$built" $((SPL_HDR_OFF + 4)))
flags=$(u8 "$built" $((SPL_HDR_OFF + 5)))
lenu32=$(u16le "$built" $((SPL_HDR_OFF + 6)))
zero=$(u16le "$built" $((SPL_HDR_OFF + 8)))
cks=$(u16le "$built" $((SPL_HDR_OFF + 10)))
splen=$((lenu32 * 4))
note "validation=$(hx "$val") version=$ver flags=$flags length_u32=$lenu32 ($splen bytes) zero=$zero checksum=0x$(printf '%04x' "$cks")"

if [ "$(printf '%08x' "$val")" = "$SPL_VALIDATION" ]; then
	ok "validation word 0x$SPL_VALIDATION present — the BootROM will accept this SPL"
else
	bad "validation word is $(hx "$val"), must be 0x$SPL_VALIDATION ('A''S''0''1')"
fi
if [ "$ver" -eq 0 ] && [ "$flags" -eq 0 ] && [ "$zero" -eq 0 ]; then
	ok "SPL header version/flags/zero are stock's 0/0/0"
else
	bad "SPL header version/flags/zero = $ver/$flags/$zero, stock is 0/0/0"
fi

# tools/socfpgaimage.c:63-72 — sums header bytes 0..8 only (the while(--len)
# pre-decrement drops the last byte of the 10 it means to read).
calc=$(rdbytes "$built" "$SPL_HDR_OFF" 9 | awk '{for(i=1;i<=NF;i++)s+=$i}END{printf "%04x\n", s % 65536}')
if [ "$calc" = "$(printf '%04x' "$cks")" ]; then
	ok "header checksum recomputes: 0x$calc (socfpgaimage.c off-by-one reproduced)"
else
	bad "header checksum is 0x$(printf '%04x' "$cks") but recomputes to 0x$calc"
fi

if [ "$splen" -ge $((SPL_HDR_OFF + 12)) ] && [ "$splen" -le "$SPL_SLOT" ]; then
	ok "SPL payload length $splen bytes is inside the $SPL_SLOT-byte slot (headroom $((SPL_SLOT - splen)) bytes, $((splen * 100 / SPL_SLOT))% used)"
	crcoff=$((splen - 4))
	stored=$(u32le "$built" "$crcoff")
	crcres=$(pblcrc "$built" 0 "$crcoff")
	got=${crcres%% *}
	gread=${crcres##* }
	if [ "$gread" -ne "$crcoff" ]; then
		bad "SPL payload is short: read $gread of $crcoff bytes"
	elif [ "$got" = "$(printf '%08x' "$stored")" ]; then
		ok "SPL payload CRC32 over [0,$crcoff) recomputes: 0x$got (stored at +$(hx $crcoff))"
	else
		bad "SPL payload CRC32 is $(hx "$stored") but recomputes to 0x$got — copy 0 is corrupt"
	fi
	if rdbytes "$built" "$splen" $((SPL_SLOT - splen)) | awk '{for(i=1;i<=NF;i++)if($i!=0){exit 1}}'; then
		ok "the rest of copy 0 ($((SPL_SLOT - splen)) bytes) is zero padding"
	else
		bad "copy 0 has non-zero bytes after the payload end ($(hx $splen)) — mkimage padding changed"
	fi
else
	bad "SPL length_u32 says $splen bytes, outside [$((SPL_HDR_OFF + 12)), $SPL_SLOT] — 2017.03's mkimage truncates length_u32 silently (plan §3.5), so treat this as corruption"
fi

if [ -n "${SPL_SIZE_LIMIT:-}" ]; then
	if [ "$splen" -le "$SPL_SIZE_LIMIT" ]; then
		ok "SPL payload $splen <= SPL_SIZE_LIMIT $SPL_SIZE_LIMIT (headroom $((SPL_SIZE_LIMIT - splen)) bytes)"
	else
		bad "SPL payload $splen > SPL_SIZE_LIMIT $SPL_SIZE_LIMIT — mainline's SPL_SIZE_CHECK would have failed this build"
	fi
else
	note "SPL_SIZE_LIMIT unset: only the $SPL_SLOT-byte slot was enforced. Pass the U-Boot tree's \`tools/spl_size_limit\` output to check the link-time limit too (plan §3.5: stock's 45,820 B, mainline 57,006 B of 62,752 B)."
fi

# --- 4. Environment parity ---------------------------------------------------
echo
echo "[4] default_environment[] parity"

spay=$((UIMG_OFF + UIMG_HDR))
bpay=$((UIMG_OFF + UIMG_HDR))

payscan "$stock" "$spay" "$ssz" "$sload" env > "$tmp/stock.env.txt" || die "env scan of $stock failed"
if grep -q '^ENVERR' "$tmp/stock.env.txt"; then
	die "$(sed -n 's/^ENVERR //p' "$tmp/stock.env.txt") in the reference $stock"
fi
sed -n 's/^ENVWARN /     warning: /p' "$tmp/stock.env.txt"
sread=$(awk '$1=="ENV"{print $2}' "$tmp/stock.env.txt")
slen=$(awk '$1=="ENV"{print $3}' "$tmp/stock.env.txt")
scnt=$(awk '$1=="ENV"{print $4}' "$tmp/stock.env.txt")
note "stock env: payload offset $(hx "$sread"), $slen bytes, $scnt entries (file offset $(hx $((spay + sread))))"
if [ "$sread" -eq "$STOCK_ENV_OFF" ] && [ "$slen" -eq "$STOCK_ENV_LEN" ]; then
	ok "stock env is where plan §6 says it is: $(hx $STOCK_ENV_OFF), $STOCK_ENV_LEN bytes"
else
	note "reference note: stock env is at $(hx "$sread")/$slen B, plan §6 records $(hx $STOCK_ENV_OFF)/$STOCK_ENV_LEN B — the reference blob is not the one the plan measured"
fi

bread=""
esize=""
if [ -n "$elf" ]; then
	nmbin=${NM:-nm}
	if nmline=$("$nmbin" -S "$elf" 2>/dev/null | awk '$4=="default_environment"{print $1" "$2; found=1} END{exit !found}'); then
		eaddr=$((0x$(echo "$nmline" | cut -d' ' -f1)))
		esize=$((0x$(echo "$nmline" | cut -d' ' -f2)))
		bread=$((eaddr - bload))
		if [ "$bread" -lt 0 ] || [ $((bread + esize)) -gt "$bsz" ]; then
			bad "the ELF puts default_environment outside the uImage payload — $(hx "$eaddr") size $esize is not inside [$(hx "$bload"), +$bsz) — wrong ELF for this image?"
			bread=""
			esize=""
		else
			note "$nmbin -S: default_environment at $(hx "$eaddr") size $esize -> payload offset $(hx "$bread")"
		fi
	else
		note "$nmbin -S found no default_environment in $elf (stripped, or a different link) — falling back to the scan"
	fi
fi

payscan "$built" "$bpay" "$bsz" "$bload" env "${bread:--1}" > "$tmp/built.env.txt" || die "env scan of $built failed"
if grep -q '^ENVERR' "$tmp/built.env.txt"; then
	bad "$(sed -n 's/^ENVERR //p' "$tmp/built.env.txt") in $built — no environment blob to compare"
else
	boff=$(awk '$1=="ENV"{print $2}' "$tmp/built.env.txt")
	blen=$(awk '$1=="ENV"{print $3}' "$tmp/built.env.txt")
	bcnt=$(awk '$1=="ENV"{print $4}' "$tmp/built.env.txt")
	note "built env: payload offset $(hx "$boff"), $blen bytes, $bcnt entries (file offset $(hx $((bpay + boff))))"
	if [ -n "$bread" ]; then
		note "located from the ELF symbol; the scan is only a cross-check"
	fi
	aoff=$(awk '$1=="ENVA"{print $2}' "$tmp/built.env.txt")
	if [ -n "$aoff" ]; then
		note "scan: $(awk '$1=="ENVA"{printf "anchored on \"%s\" (%d match(es) in the payload), blob at 0x%08x, %d bytes, %d entries", $5, $6, $2, $3, $4}' "$tmp/built.env.txt")"
		if [ "$aoff" -ne "$boff" ]; then
			note "the scan and the ELF disagree ($(hx "$aoff") vs $(hx "$boff")) — the ELF wins; a scan-only run of this image would compare the wrong bytes"
		fi
	elif [ -z "$bread" ]; then
		note "scan: no usable anchor beyond the blob it found"
	fi
	if [ -n "$esize" ] && [ "$esize" -ne "$blen" ]; then
		note "the ELF symbol is $esize B and the blob is $blen B — the symbol also covers the string literal's own trailing NUL and any alignment padding after the NUL-NUL terminator (plan §6: stock is 1,150 B of a 1,151 B symbol)"
	fi

	dd if="$stock" bs=1 skip=$((spay + sread)) count="$slen" of="$tmp/stock.env.bin" 2>/dev/null
	dd if="$built" bs=1 skip=$((bpay + boff)) count="$blen" of="$tmp/built.env.bin" 2>/dev/null
	if [ "$blen" -ne "$slen" ]; then
		bad "environment is $blen bytes, stock's is $slen bytes ($bcnt entries vs $scnt)"
	fi
	if cmp -s "$tmp/stock.env.bin" "$tmp/built.env.bin"; then
		ok "environment is byte-identical to stock: $slen bytes, $scnt entries (\`mt\` carried, plan §3.4 — no allowed delta)"
	else
		bad "environment differs from stock's — every byte of default_environment[] is a forbidden diff (plan §6)"
		cmp "$tmp/stock.env.bin" "$tmp/built.env.bin" 2>&1 | sed 's/^/     /' >&2 || true
		echo "     entry-by-entry diagnostic (-stock +built):" >&2
		sed -n 's/^ENTRY [0-9]* [0-9]* //p' "$tmp/stock.env.txt" > "$tmp/stock.entries"
		sed -n 's/^ENTRY [0-9]* [0-9]* //p' "$tmp/built.env.txt" > "$tmp/built.entries"
		diff -u "$tmp/stock.entries" "$tmp/built.entries" 2>&1 | sed 's/^/     /' >&2 || true
	fi
fi

# --- 5. Command table --------------------------------------------------------
echo
echo "[5] command table"

payscan "$stock" "$spay" "$ssz" "$sload" cmd > "$tmp/stock.cmd.txt" || die "command scan of $stock failed"
if grep -q '^CMDERR' "$tmp/stock.cmd.txt"; then
	die "no command table found in the reference $stock"
fi
payscan "$built" "$bpay" "$bsz" "$bload" cmd > "$tmp/built.cmd.txt" || die "command scan of $built failed"

sed -n 's/^NAME //p' "$tmp/stock.cmd.txt" | sort -u > "$tmp/stock.names"
snames=$(wc -l < "$tmp/stock.names" | tr -d ' ')
note "stock: $(awk '$1=="TABLE"{print $2}' "$tmp/stock.cmd.txt") entries at payload offset $(hx "$(awk '$1=="TABLE"{print $3}' "$tmp/stock.cmd.txt")"), stride $(awk '$1=="TABLE"{print $4}' "$tmp/stock.cmd.txt") (allowed diff: offset and stride)"

if grep -q '^CMDERR' "$tmp/built.cmd.txt"; then
	bad "no command table found in $built"
else
	sed -n 's/^NAME //p' "$tmp/built.cmd.txt" | sort -u > "$tmp/built.names"
	bnames=$(wc -l < "$tmp/built.names" | tr -d ' ')
	note "built: $(awk '$1=="TABLE"{print $2}' "$tmp/built.cmd.txt") entries at payload offset $(hx "$(awk '$1=="TABLE"{print $3}' "$tmp/built.cmd.txt")"), stride $(awk '$1=="TABLE"{print $4}' "$tmp/built.cmd.txt")"
	comm -23 "$tmp/stock.names" "$tmp/built.names" > "$tmp/missing"
	comm -13 "$tmp/stock.names" "$tmp/built.names" > "$tmp/extra"
	if [ -s "$tmp/missing" ]; then
		bad "$(wc -l < "$tmp/missing" | tr -d ' ') of stock's $snames commands are missing: $(tr '\n' ' ' < "$tmp/missing")"
	else
		ok "all $snames stock command names are present ($bnames total in the build)"
	fi
	if grep -qx 'mt' "$tmp/built.names"; then
		ok "\`mt\` is present — stock's fpgacheck runs unmodified (plan §3.4)"
	else
		bad "\`mt\` is missing: stock's fpgacheck would fail on every boot (plan §3.4)"
	fi
	if [ -s "$tmp/extra" ]; then
		note "extra commands, allowed: $(tr '\n' ' ' < "$tmp/extra")"
	else
		note "no extra commands beyond stock's $snames"
	fi
fi

# --- 6. Verdict --------------------------------------------------------------
echo
echo "[6] allowed diffs (plan §6): version string and build timestamp; uImage"
echo "    ih_ep $(hx $TEXT_BASE) vs 0x00000000; total image size; code layout and"
echo "    table offsets inside the SPL; extra commands. Everything else above is"
echo "    a hard contract."

if [ "$fail" -eq 0 ]; then
	echo "$prog: parity holds"
else
	echo "$prog: CONTRACT VIOLATED" >&2
fi
exit "$fail"
