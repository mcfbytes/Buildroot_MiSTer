#!/bin/sh
#
# test-uboot-parity.sh — fixture proof for scripts/check-uboot-parity.sh
# (docs/uboot-tasks.md U4a; docs/uboot-mainline-port.md Sec 6).
#
# WHY THIS EXISTS. check-uboot-parity.sh is a gate that will normally say
# "parity holds", and a gate that only ever passes is indistinguishable from a
# gate that cannot fail. There is no board and, until U2g, no built .sfp
# either, so the only way to show the checker can actually detect the three
# brick-class defects it exists for is to manufacture them. Each fixture below
# is one of those defects, injected into a COPY of the pinned stock uboot.img,
# and each case asserts both the exit status and the specific message — a
# fixture that fails for the wrong reason is not a passing fixture.
#
# Isolation is deliberate. Every mutation that lands inside the U-Boot proper
# payload also invalidates the uImage payload CRC, which would let a checker
# "detect" an environment edit purely by accident. So the environment and
# command-table fixtures RE-STAMP the payload CRC after mutating, and then
# assert that the uImage CRC line still passes — proving the environment and
# command-table checks stand on their own. The re-stamping CRC32 is taken from
# gzip's trailer (a gzip member stores the CRC32 of the uncompressed data),
# which is a completely independent implementation of the same CRC from the one
# the checker computes in awk; the two agreeing on the unmutated blob is itself
# a cross-check of the checker's arithmetic.
#
# The fixtures (all desk work — no build, no board, nothing fetched):
#
#   1. stock-vs-stock          must PASS (exit 0). The .sfp argument may be a
#                              stock uboot.img; parity with itself is trivially
#                              true, and anything the checker gets wrong about
#                              the shipped blob shows up here first.
#   2. env-byte-flipped        one byte of default_environment[] altered, CRC
#                              re-stamped -> exit 1, "environment differs",
#                              entry-by-entry diagnostic printed, uImage CRC
#                              still ok.
#   3. spl-copy-differs        one byte of SPL copy 2's zero padding set ->
#                              exit 1, "SPL copy 2 ... differs from copy 0".
#   4. uimage-crc-wrong        one payload byte flipped, CRC NOT re-stamped ->
#                              exit 1, "uImage payload CRC ... recomputes to".
#   5. cmd-table-broken        the `mt` command record's name pointer zeroed,
#                              CRC re-stamped -> exit 1, commands missing and
#                              `mt` called out by name (plan Sec 3.4).
#   6. ih-ep-bogus             ih_ep set to a value that is neither the fork's
#                              0 nor mainline's CONFIG_TEXT_BASE, header CRC
#                              re-stamped -> exit 1. Proves the ih_ep allowed
#                              diff (plan Sec 3.3) is bounded to those two.
#   7. missing-file            exit 2, not 1: an absent input is an IO error,
#                              not a contract violation.
#   8. truncated-file          exit 2 for the same reason.
#   9. elf-right               the optional third argument: a stub ELF that
#                              declares default_environment at the address
#                              stock's would have must be believed, and its
#                              1,151-byte symbol reconciled with the 1,150-byte
#                              blob (plan Sec 6's constant nit).
#  10. elf-wrong               the same stub linked elsewhere -> exit 1, the
#                              checker says so instead of reading rubbish.
#
# Sections [1]-[6] are fixtures 1-6; [7] holds fixtures 7 and 8, [8] holds 9
# and 10.
#
# Fixtures 2-6 target byte offsets that are properties of the PINNED stock blob
# (sha256 e2d46cf9...62a64), so this script checks that hash before trusting
# them and every offset is guarded at the point of use (e.g. fixture 5 resolves
# the record's name pointer and confirms it reads "mt" before zeroing it).
#
# Deliberately not `set -e`: every case must run and be judged even if an
# earlier one behaves unexpectedly, so one pass shows the whole picture (same
# rationale as scripts/test-ntp-kick.sh, test-timezone.sh, test-uboot-handoff.sh).
#
# Usage: scripts/test-uboot-parity.sh [stock-uboot.img]
# Env:
#   STOCK_UBOOT_IMG  the reference blob, if not given as $1. Default:
#                    <repo-root>/output-sdcard-stage/mister-payload/linux/uboot.img,
#                    where scripts/fetch-sdcard-payload.sh stages it.
#   WORKDIR          where the fixtures are written. Default: a mktemp -d that
#                    is removed on exit. Set it to keep the fixtures and logs.
# Exit: 0 = every case behaved, 1 = a case did not, 2 = setup/IO error.

set -u

export LC_ALL=C   # byte-wise, like the checker it drives

STOCK_SHA256=e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64
STOCK_SIZE=515141

# Offsets inside the pinned blob. PAY is where the U-Boot proper payload starts
# (0x40000 uImage + 64-byte header); the other two are payload-relative and are
# re-derived in docs/uboot-mainline-port.md Sec 6 / this task's evidence.
PAY=262208        # 0x40040
ENV_OFF=163864    # 0x28018 — default_environment[], 1150 B, 21 entries
MT_REC=211336     # 0x33988 — the `mt` record in the U_BOOT_CMD linker list
                  #           (table at payload 0x33410, 28-byte stride, 51st entry)
SPL_SLOT=65536
UIMG_OFF=262144   # 0x40000

prog=${0##*/}
here=$(cd -- "$(dirname -- "$0")" && pwd) || exit 2
root=$(cd -- "$here/.." && pwd) || exit 2
CHECK=$here/check-uboot-parity.sh

pass=0
fail=0
skip=0

note() { printf '  %s\n' "$*"; }
ok()   { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
bad()  { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
skipped() { skip=$((skip + 1)); printf 'skip %s\n' "$*"; }
die()  { echo "$prog: $*" >&2; exit 2; }

stock=${1:-${STOCK_UBOOT_IMG:-$root/output-sdcard-stage/mister-payload/linux/uboot.img}}
[ -x "$CHECK" ] || die "$CHECK is missing or not executable"
[ -f "$stock" ] || die "stock uboot.img not found at $stock
  pass it as \$1 or \$STOCK_UBOOT_IMG, or stage it with scripts/fetch-sdcard-payload.sh"

got=$(sha256sum "$stock" | cut -d' ' -f1)
[ "$got" = "$STOCK_SHA256" ] ||
	die "$stock is sha256 $got, not the pinned $STOCK_SHA256 — the fixture offsets below are properties of that exact blob"
[ "$(wc -c < "$stock" | tr -d ' ')" -eq "$STOCK_SIZE" ] || die "$stock is not $STOCK_SIZE bytes"

if [ -n "${WORKDIR:-}" ]; then
	mkdir -p "$WORKDIR" || die "cannot create WORKDIR $WORKDIR"
	W=$WORKDIR
	keep=1
else
	W=$(mktemp -d "${TMPDIR:-/tmp}/test-uboot-parity.XXXXXX") || die "mktemp -d failed"
	keep=0
	trap 'rm -rf "$W"' EXIT HUP INT TERM
fi

printf '%s: checker %s\n' "$prog" "$CHECK"
printf '%s: stock   %s (sha256 ok)\n' "$prog" "$stock"
printf '%s: fixtures in %s%s\n\n' "$prog" "$W" "$([ "$keep" -eq 1 ] && echo ' (kept)')"

# --- byte-level fixture surgery ---------------------------------------------

# u32le FILE OFF / u32be FILE OFF -> decimal
u32le() {
	_b=$(od -An -tx1 -j "$2" -N 4 -v "$1" | tr -d ' \n')
	printf '%d' "0x$(echo "$_b" | cut -c7-8)$(echo "$_b" | cut -c5-6)$(echo "$_b" | cut -c3-4)$(echo "$_b" | cut -c1-2)"
}

# putbytes FILE OFF B0 [B1...] — write decimal bytes at OFF, in place
putbytes() {
	_f=$1
	_o=$2
	shift 2
	for _b in "$@"; do
		# shellcheck disable=SC2059  # the octal escape IS the format string:
		# printf '\\ooo' is the POSIX way to emit one arbitrary byte, and
		# printf '%c' would go through the locale (awk's would emit UTF-8).
		printf "\\$(printf '%03o' "$_b")"
	done | dd of="$_f" bs=1 seek="$_o" conv=notrunc 2>/dev/null
}

# put32be FILE OFF VALUE
put32be() {
	putbytes "$1" "$2" \
		$(( ($3 / 16777216) % 256 )) $(( ($3 / 65536) % 256 )) \
		$(( ($3 / 256) % 256 ))      $(( $3 % 256 ))
}

# flipbyte FILE OFF MASK — xor one byte in place
flipbyte() {
	_v=$(od -An -tu1 -j "$2" -N 1 -v "$1" | tr -d ' \n')
	putbytes "$1" "$2" $(( _v ^ $3 ))
}

# crc32 FILE OFF LEN -> lowercase hex, from gzip's trailer (RFC 1952 Sec 2.3.1:
# the last 8 bytes of a member are CRC32 then ISIZE, both little-endian).
crc32() {
	dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | gzip -cn | tail -c 8 |
		od -An -tx1 -v | awk '{printf "%s%s%s%s\n", $4, $3, $2, $1}'
}

# repair_dcrc FILE — re-stamp the uImage payload CRC after mutating the payload
repair_dcrc() {
	_sz=$(od -An -tx1 -j $((UIMG_OFF + 12)) -N 4 -v "$1" | tr -d ' \n')
	_sz=$(printf '%d' "0x$_sz")
	_c=$(crc32 "$1" $((UIMG_OFF + 64)) "$_sz")
	put32be "$1" $((UIMG_OFF + 24)) "$(printf '%d' "0x$_c")"
}

# repair_hcrc FILE — re-stamp the uImage header CRC (computed over the 64-byte
# header with its own ih_hcrc field zeroed), after mutating a header field
repair_hcrc() {
	{
		dd if="$1" bs=1 skip="$UIMG_OFF" count=4 2>/dev/null
		printf '\000\000\000\000'
		dd if="$1" bs=1 skip=$((UIMG_OFF + 8)) count=56 2>/dev/null
	} | gzip -cn | tail -c 8 | od -An -tx1 -v |
		awk '{printf "%s%s%s%s\n", $4, $3, $2, $1}' > "$W/.hcrc"
	put32be "$1" $((UIMG_OFF + 4)) "$(printf '%d' "0x$(cat "$W/.hcrc")")"
}

# --- case plumbing -----------------------------------------------------------

# run NAME ARGS... -> runs the checker, logs to $W/NAME.log, sets $rc
run() {
	_n=$1
	shift
	"$CHECK" "$@" > "$W/$_n.log" 2>&1
	rc=$?
}

want_rc() {   # want_rc NAME WANT
	if [ "$rc" -eq "$2" ]; then
		ok "$1: exit $rc"
	else
		bad "$1: exit $rc, wanted $2"
		sed 's/^/     /' "$W/$1.log"
	fi
}

want_say() {  # want_say NAME TEXT...
	_n=$1
	shift
	if grep -qF -- "$*" "$W/$_n.log"; then
		ok "$_n: says \"$*\""
	else
		bad "$_n: never says \"$*\""
		sed 's/^/     /' "$W/$_n.log"
	fi
}

want_quiet() {  # want_quiet NAME TEXT... — must NOT appear
	_n=$1
	shift
	if grep -qF -- "$*" "$W/$_n.log"; then
		bad "$_n: unexpectedly says \"$*\""
		sed 's/^/     /' "$W/$_n.log"
	else
		ok "$_n: does not say \"$*\""
	fi
}

# --- 1. stock vs stock -------------------------------------------------------
echo "[1] stock-vs-stock: a stock uboot.img is in parity with itself"
run stock-vs-stock "$stock" "$stock"
want_rc stock-vs-stock 0
want_say stock-vs-stock "parity holds"
want_say stock-vs-stock "all 69 stock command names are present"
want_say stock-vs-stock "environment is byte-identical to stock: 1150 bytes, 21 entries"
want_say stock-vs-stock "SPL copy 3 at 0x00030000 is byte-identical to copy 0"
want_say stock-vs-stock "header checksum recomputes: 0x01e0"
want_say stock-vs-stock "SPL payload CRC32 over [0,45816) recomputes: 0x35391b6b"
want_say stock-vs-stock "uImage payload CRC recomputes over all 252933 bytes: 0xce778166"
echo

# --- 2. one environment byte flipped ----------------------------------------
echo "[2] env-byte-flipped: one byte of default_environment[], payload CRC re-stamped"
cp "$stock" "$W/env-flip.img" || die "cp failed"
flipbyte "$W/env-flip.img" $((PAY + ENV_OFF + 9)) 1     # "console" -> "bonsole"
repair_dcrc "$W/env-flip.img"
run env-flip "$W/env-flip.img" "$stock"
want_rc env-flip 1
want_say env-flip "environment differs from stock"
want_say env-flip "entry-by-entry diagnostic"
want_say env-flip "+bootargs=bonsole=ttyS0,115200"
want_say env-flip "uImage payload CRC recomputes"   # the re-stamp worked: isolated
want_say env-flip "CONTRACT VIOLATED"
echo

# --- 3. one SPL copy differs -------------------------------------------------
echo "[3] spl-copy-differs: one byte of copy 2's zero padding"
cp "$stock" "$W/spl2.img" || die "cp failed"
putbytes "$W/spl2.img" $((2 * SPL_SLOT + 49152)) 255
run spl2 "$W/spl2.img" "$stock"
want_rc spl2 1
want_say spl2 "SPL copy 2 at 0x00020000 differs from copy 0"
want_say spl2 "SPL copy 1 at 0x00010000 is byte-identical to copy 0"
want_say spl2 "SPL payload CRC32 over [0,45816) recomputes"   # copy 0 untouched
echo

# --- 4. the uImage payload CRC is wrong -------------------------------------
echo "[4] uimage-crc-wrong: one payload byte flipped, CRC left stale"
cp "$stock" "$W/dcrc.img" || die "cp failed"
flipbyte "$W/dcrc.img" $((PAY + 4096)) 255
run dcrc "$W/dcrc.img" "$stock"
want_rc dcrc 1
want_say dcrc "the payload was edited after mkimage"
want_say dcrc "environment is byte-identical to stock"   # env untouched: isolated
echo

# --- 5. a command disappears from the table ---------------------------------
echo "[5] cmd-table-broken: the \`mt\` record's name pointer zeroed, CRC re-stamped"
cp "$stock" "$W/nomt.img" || die "cp failed"
namep=$(u32le "$W/nomt.img" $((PAY + MT_REC)))
nameoff=$((PAY + namep - 16777280))          # 16777280 = 0x01000040 = ih_load
if [ "$namep" -lt 16777280 ] || [ "$nameoff" -ge "$STOCK_SIZE" ]; then
	bad "cmd-table-broken: the record at payload 0x$(printf '%x' "$MT_REC") holds no in-range name pointer"
elif [ "$(dd if="$W/nomt.img" bs=1 skip="$nameoff" count=2 2>/dev/null)" != "mt" ]; then
	bad "cmd-table-broken: the record at payload 0x$(printf '%x' "$MT_REC") is not \`mt\` — blob layout changed"
else
	note "record at payload 0x$(printf '%x' "$MT_REC") -> name 0x$(printf '%x' "$namep") = \"mt\", zeroing the pointer"
	putbytes "$W/nomt.img" $((PAY + MT_REC)) 0 0 0 0
	repair_dcrc "$W/nomt.img"
	run nomt "$W/nomt.img" "$stock"
	want_rc nomt 1
	want_say nomt "commands are missing"
	want_say nomt "\`mt\` is missing"
	want_say nomt "uImage payload CRC recomputes"          # re-stamp worked
	want_say nomt "environment is byte-identical to stock" # env untouched
fi
echo

# --- 6. ih_ep is neither the fork's 0 nor mainline's CONFIG_TEXT_BASE -------
echo "[6] ih-ep-bogus: ih_ep outside the two allowed values, header CRC re-stamped"
cp "$stock" "$W/ihep.img" || die "cp failed"
put32be "$W/ihep.img" $((UIMG_OFF + 20)) 291    # 0x00000123
repair_hcrc "$W/ihep.img"
run ihep "$W/ihep.img" "$stock"
want_rc ihep 1
want_say ihep "ih_ep = 0x00000123: neither 0 (fork)"
want_say ihep "uImage header CRC recomputes"    # re-stamp worked: isolated
echo

# --- 7/8. IO errors are exit 2, not exit 1 ----------------------------------
echo "[7] missing-file and truncated-file are usage/IO errors"
run missing "$W/does-not-exist.sfp" "$stock"
want_rc missing 2
want_say missing "no such file"
want_quiet missing "CONTRACT VIOLATED"

dd if="$stock" of="$W/short.img" bs=1 count=1024 2>/dev/null
run short "$W/short.img" "$stock"
want_rc short 2
want_say short "too small"
echo

# --- 8. the optional u-boot ELF argument (fixtures 9 and 10) ----------------
# U2g will pass the built ELF as $3 so default_environment[] is located by
# symbol instead of by scan. There is no U-Boot ELF on disk yet, so the case is
# made from a two-line assembly stub that declares the symbol at the address
# stock's would have (ih_load 0x01000040 + the 0x28018 payload offset) — `nm -S`
# is all the checker reads from it, so the stub is a faithful stand-in.
echo "[8] the optional u-boot ELF argument (nm -S default_environment)"
if command -v as >/dev/null 2>&1 && command -v ld >/dev/null 2>&1; then
	cat > "$W/fakeenv.s" <<-ASM
		.section .env, "a"
		.globl default_environment
		.type default_environment, %object
		.size default_environment, 1151
	default_environment:
		.space 1151
	ASM
	printf 'SECTIONS { . = 0x01028058; .env : { *(.env) } }\n' > "$W/right.ld"
	printf 'SECTIONS { . = 0x02000000; .env : { *(.env) } }\n' > "$W/wrong.ld"
	if as -o "$W/fakeenv.o" "$W/fakeenv.s" 2>"$W/as.log" &&
	   ld -T "$W/right.ld" -o "$W/right.elf" "$W/fakeenv.o" 2>>"$W/as.log" &&
	   ld -T "$W/wrong.ld" -o "$W/wrong.elf" "$W/fakeenv.o" 2>>"$W/as.log"; then
		run elf-right "$stock" "$stock" "$W/right.elf"
		want_rc elf-right 0
		want_say elf-right "default_environment at 0x01028058 size 1151 -> payload offset 0x00028018"
		want_say elf-right "the ELF symbol is 1151 B and the blob is 1150 B"

		run elf-wrong "$stock" "$stock" "$W/wrong.elf"
		want_rc elf-wrong 1
		want_say elf-wrong "the ELF puts default_environment outside the uImage payload"
	else
		skipped "elf-arg: as/ld could not build the stub ($(tr '\n' ' ' < "$W/as.log"))"
	fi
else
	skipped "elf-arg: no as/ld on this host"
fi
echo

printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || echo "$prog: the checker did not behave as specified" >&2
[ "$fail" -eq 0 ]
