#!/usr/bin/env bash
#
# check-abi.sh — the ABI / SONAME parity checker (TASKS.md P2.2).
#
# This is the deliverable docs/abi-contract.md §13.1 has always named as the
# thing "scripts/check-abi.sh (P2.2)" is built from. It asserts the ABI/loader
# half of that checklist — the interface the stock `MiSTer` binary demands of
# the rootfs it is dropped into — against a built rootfs:
#
#   * the toolchain declaration (A-1)         — armv7-a + NEON + VFPv3 + EABIhf
#   * the dynamic loader (A-2)                — /lib/ld-linux-armhf.so.3
#   * the twelve DT_NEEDED SONAMEs (A-3)      — present at the same major
#   * the transitive libdl.so.2 (A-4)         — pulled in by imlib2
#   * libbz2.so.**1.0**, not .1 (A-5)         — the one SONAME distros normalise
#   * glibc's GLIBC_2.28 floor (A-6)          — the binary's highest version node
#   * libstdc++ GLIBCXX_3.4.21/CXXABI (A-7)   — the GCC-5.1 C++11 ABI floor
#   * the glibc-2.34 merge trap (A-8, A-9)    — pthread/rt stubs still define
#                                               GLIBC_2.4, and libc.so.6 still
#                                               exports the five merged symbols
#                                               at that version (§1.3 — the
#                                               single highest-value assertion)
#   * /MiSTer.version byte shape (A-11, A-12) — exactly 6 ASCII digits, no \n
#   * firmware + modules.alias (A-24, A-25)   — the module-load ABI floor
#   * the two dynamic gates (A-10, A-22)      — run the ACTUAL stock binary
#                                               under qemu-user against this
#                                               rootfs: every DT_NEEDED resolves,
#                                               and it dies at /dev/mem (not
#                                               earlier). SKIPped, not failed,
#                                               when qemu-arm or the stock binary
#                                               is absent (§2.4/§2.5).
#
# SCOPE — what this deliberately does NOT check. §13.1 also carries the init /
# config-parity rows A-13..A-21, A-23 (asound.conf, the S-script set, fstab,
# inittab, helper binaries, python3). Those belong to P2.3 (init & config
# parity) and P2.4 (read-only-root audit), several have DOCUMENTED, intentional
# divergences from stock's exact strings (e.g. Buildroot names eudev's init
# script S10udevd, not stock's S10udev — see docs/init-parity.md), and
# scripts/ci-tests.sh's Phase-3 section already asserts them against the built
# rootfs. Folding them in here would either duplicate that or hard-fail on an
# intentional, reviewed divergence. This script is the "ABI / SONAME parity
# checker" its name and TASKS P2.2's own text ("verify every SONAME ... exists
# ... at the same major version" + "dynamic-link resolution ... fail on any
# unresolved symbol/library") say it is, no more.
#
# RELATIONSHIP TO ci-tests.sh. Until this script existed, ci-tests.sh carried a
# lightweight interim of the two dynamic gates (A-10/A-22) so CI was not blind
# to them. That interim stays — it is cheap, and ci-tests.sh is the one-command
# parity suite — so A-10/A-22 are asserted in both places. That is intentional
# redundancy on the two highest-value checks, not an oversight.
#
# Usage: scripts/check-abi.sh [rootfs]
#   rootfs may be, in this resolution order:
#     * a Buildroot BUILD dir (has target/)         -> its target/ is the rootfs
#     * an already-extracted rootfs DIRECTORY       -> used as-is
#     * an ext4 IMAGE file (linux.img)              -> extracted read-only via
#                                                      debugfs (no root needed)
#   Defaults to "output" (repo-root-relative) — i.e. the same `output` the CI
#   step passes, whose output/target is the rootfs.
#
# Output: one PASS / FAIL / SKIP line per assertion, then a digest (SKIPPED,
# then FAILURES, then RESULT). Under GitHub Actions each failure is also an
# ::error:: annotation so it names itself in the run UI. A SKIP never fails the
# run; any FAIL does.
#
# Exit: 0 = every assertion PASSed or SKIPped. 1 = at least one FAIL.
#       2 = usage / unresolvable rootfs.
#
# Env overrides (all optional):
#   STOCK_MISTER=<path>   the stock `MiSTer` binary for A-10/A-22 (default: look
#                         at work/imgroot/tmp/MiSTer, work/extracted/files/MiSTer
#                         — a P0.3-era extraction, gitignored, not a build
#                         artifact, so absent in a clean CI checkout -> SKIP).
#   CHECK_ABI_LOG=<path>  where to write the machine-readable result list
#                         (default: <rootfs-parent>/check-abi-results.txt;
#                         best-effort — an unwritable path does not fail the run).

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# common.sh gives us mrl_extract_root (dir passthrough OR debugfs image extract,
# no root, symlink-preserving) and its EXIT-trap cleanup. Sourced, not
# reimplemented — it is the project's blessed image->rootfs helper (P0.3).
# shellcheck source=scripts/inventory/common.sh
. "$ROOT/scripts/inventory/common.sh"

# ---------------------------------------------------------------------------
# Result bookkeeping (mirrors scripts/ci-tests.sh so the two read alike).
# ---------------------------------------------------------------------------
PASS_N=0
FAIL_N=0
SKIP_N=0
FAILURES=()
SKIPPED=()
# Parallel arrays (emoji, text), one entry per check, in run order -- the raw
# material for the GitHub Actions job-summary table written at the end.
SUMMARY_EMOJI=()
SUMMARY_TEXT=()

# In GitHub Actions, surface each failure as an annotation too.
_annotate_error() {
	[ -n "${GITHUB_ACTIONS:-}" ] || return 0
	printf '::error title=check-abi (P2.2)::%s: %s\n' "$1" "$2"
}

_row() { SUMMARY_EMOJI+=("$1"); SUMMARY_TEXT+=("$2"); }

section() { printf '\n=== %s ===\n' "$1"; }
pass()    { PASS_N=$((PASS_N + 1)); _row "✅" "$1"; printf '  PASS  %s\n' "$1"; }
note()    { printf '        (%s)\n' "$1"; }
skip()    {
	SKIP_N=$((SKIP_N + 1))
	SKIPPED+=("$1 -- $2")
	_row "⚪" "$1 — $2"
	printf '  SKIP  %s -- %s\n' "$1" "$2"
}
fail() {
	FAIL_N=$((FAIL_N + 1))
	FAILURES+=("$1 -- $2")
	_row "❌" "$1 — $2"
	printf '  FAIL  %s -- %s\n' "$1" "$2"
	_annotate_error "$1" "$2"
}

# ---------------------------------------------------------------------------
# Resolve the rootfs.
# ---------------------------------------------------------------------------
INPUT="${1:-output}"
if [ "$#" -gt 1 ]; then
	echo "usage: $0 [rootfs-build-dir | rootfs-dir | image]" >&2
	exit 2
fi

if [ -d "$INPUT" ] && [ -d "$INPUT/target" ]; then
	# A Buildroot build dir: the rootfs tree is target/.
	ROOTFS="$INPUT/target"
elif [ -d "$INPUT" ]; then
	ROOTFS="$INPUT"
elif [ -f "$INPUT" ]; then
	# An ext4 image — extract read-only (registers its own EXIT cleanup).
	ROOTFS="$(mrl_extract_root "$INPUT")" || {
		echo "::error::could not extract a rootfs from image '$INPUT'" >&2
		exit 2
	}
else
	echo "::error::'$INPUT' is not a build dir, a rootfs dir, or an image file" >&2
	exit 2
fi

if [ ! -e "$ROOTFS/usr/lib" ] && [ ! -e "$ROOTFS/lib" ]; then
	echo "::error::'$ROOTFS' has neither usr/lib nor lib -- does not look like a rootfs" >&2
	exit 2
fi

echo "check-abi: rootfs = $ROOTFS"

CHECK_ABI_LOG="${CHECK_ABI_LOG:-$(dirname "$ROOTFS")/check-abi-results.txt}"

# find_lib <soname> -> prints the resolved real file path (following symlinks),
# or nothing. Searches usr/lib then lib (on a merged rootfs lib -> usr/lib, so
# either resolves the same file; on a split one both are searched).
find_lib() {
	local soname="$1" d f
	for d in usr/lib lib; do
		f="$ROOTFS/$d/$soname"
		if [ -e "$f" ]; then
			readlink -f "$f"
			return 0
		fi
	done
	return 1
}

# readelf -V of a resolved library, empty if the file is missing.
lib_verdefs() {
	local f
	f="$(find_lib "$1")" || return 1
	readelf -V "$f" 2>/dev/null
}

# =============================================================================
section "Toolchain & loader (A-1, A-2)"
# =============================================================================

# A-1 — the toolchain's own ABI declaration, read off a real target ELF. The
# stock binary is armv7-a/VFPv3/NEON/EABIhf (§1.1); a rootfs built for anything
# it cannot execute (e.g. vfpv4, or softfloat) is caught here rather than at
# first instruction on hardware. busybox is the guaranteed-present probe.
A1_ELF=""
for cand in usr/bin/busybox bin/busybox usr/bin/MiSTer bin/sh; do
	if [ -e "$ROOTFS/$cand" ]; then A1_ELF="$ROOTFS/$cand"; break; fi
done
if [ -z "$A1_ELF" ]; then
	# A rootfs with no busybox/sh/MiSTer is broken, not "nothing to check" --
	# SKIP here would let a malformed/empty rootfs pass the toolchain-ABI gate
	# silently. Fail instead.
	fail "A-1 toolchain is armv7-a + NEON + VFPv3 + EABIhf" "no probe ELF (busybox/sh/MiSTer) found in rootfs -- rootfs is empty or malformed"
else
	a1_attr="$(readelf -A "$A1_ELF" 2>/dev/null)"
	a1_missing=""
	while IFS='|' read -r label pattern; do
		printf '%s' "$a1_attr" | grep -qE "$pattern" || a1_missing="$a1_missing $label"
	done <<-'EOF'
		v7|Tag_CPU_arch:[[:space:]]*v7
		VFPv3|Tag_FP_arch:[[:space:]]*VFPv3
		NEONv1|Tag_Advanced_SIMD_arch:[[:space:]]*NEONv1
		VFP-args|Tag_ABI_VFP_args:[[:space:]]*VFP registers
	EOF
	if [ -z "$a1_missing" ]; then
		pass "A-1 toolchain is armv7-a + NEON + VFPv3 + EABIhf (probe: ${A1_ELF#"$ROOTFS/"})"
	else
		fail "A-1 toolchain ABI" "missing/mismatched attribute(s):$a1_missing on ${A1_ELF#"$ROOTFS/"} -- rootfs may be built for a CPU/FP config the stock binary cannot run on"
	fi
fi

# A-2 — the dynamic loader the stock binary names in .interp. A softfloat or
# arm-linux-gnueabi toolchain installs ld-linux.so.3 instead and execve fails
# with ENOENT before a single instruction of MiSTer runs (§1.1 T5).
if [ -e "$ROOTFS/lib/ld-linux-armhf.so.3" ] || [ -e "$ROOTFS/usr/lib/ld-linux-armhf.so.3" ]; then
	pass "A-2 dynamic loader /lib/ld-linux-armhf.so.3 present"
else
	fail "A-2 dynamic loader" "/lib/ld-linux-armhf.so.3 absent -- the stock binary's .interp will not resolve (execve ENOENT)"
fi

# =============================================================================
section "SONAME set (A-3, A-4, A-5)"
# =============================================================================

# A-3 — every DT_NEEDED SONAME of the stock binary (§2.2), present AND with a
# matching DT_SONAME on the real file. Matching the SONAME string is the
# same-major check: the major lives in the SONAME (.so.6, .so.1.0, .so.16).
SONAMES_12="libc.so.6 libm.so.6 libpthread.so.0 librt.so.1 libstdc++.so.6 libgcc_s.so.1 libz.so.1 libbz2.so.1.0 libpng16.so.16 libfreetype.so.6 libImlib2.so.1 libbluetooth.so.3"
a3_bad=""
for so in $SONAMES_12; do
	f="$(find_lib "$so")" || { a3_bad="$a3_bad $so(absent)"; continue; }
	# The realname's own DT_SONAME must be exactly this SONAME. grep -F, not
	# -E: SONAMEs carry regex metacharacters (libstdc++.so.6, the dots) that
	# an -E pattern would mis-parse into a spurious mismatch.
	if ! readelf -d "$f" 2>/dev/null | grep -qF "soname: [$so]"; then
		got="$(readelf -d "$f" 2>/dev/null | grep -oiE 'soname: \[[^]]+\]' | head -1)"
		a3_bad="$a3_bad $so(DT_SONAME=${got:-none})"
	fi
done
if [ -z "$a3_bad" ]; then
	pass "A-3 all 12 DT_NEEDED SONAMEs present with matching DT_SONAME"
else
	fail "A-3 SONAME set" "problem(s):$a3_bad -- a missing SONAME or a major bump breaks 'cannot open shared object file' (§2.2)"
fi

# A-4 — libdl.so.2 is not in the binary's own DT_NEEDED; it is pulled in
# transitively by libImlib2.so.1 (§2.3). Also a glibc-2.34 merge stub.
if find_lib libdl.so.2 >/dev/null; then
	pass "A-4 transitive libdl.so.2 present (imlib2 dependency)"
else
	fail "A-4 libdl.so.2" "absent -- libImlib2.so.1's own DT_NEEDED will not resolve (§2.3)"
fi

# A-5 — the SONAME is libbz2.so.**1.0**, not the usual libbz2.so.1. Some distro
# packagings normalise it; if ours did, the stock binary's DT_NEEDED on
# libbz2.so.1.0 would not resolve (§2.2 watch list).
if find_lib libbz2.so.1.0 >/dev/null; then
	pass "A-5 libbz2.so.1.0 present (the .1.0 SONAME, not libbz2.so.1)"
else
	fail "A-5 libbz2.so.1.0" "absent -- bzip2 must ship the libbz2.so.1.0 SONAME the stock binary names, not a normalised libbz2.so.1 (§2.2)"
fi

# =============================================================================
section "glibc / libstdc++ version floors (A-6, A-7)"
# =============================================================================

# A-6 — the binary's highest glibc version node is GLIBC_2.28 (fcntl64, §1.2).
# Distinguish "libc.so.6 absent" from "present but too old" so the failure names
# the real problem (a missing file otherwise reads as an old glibc).
if ! find_lib libc.so.6 >/dev/null; then
	fail "A-6 GLIBC_2.28" "libc.so.6 not found in rootfs -- cannot check the GLIBC_2.28 floor"
elif lib_verdefs libc.so.6 | grep -q 'Name: GLIBC_2.28'; then
	pass "A-6 libc.so.6 provides version node GLIBC_2.28"
else
	fail "A-6 GLIBC_2.28" "libc.so.6 does not provide GLIBC_2.28 -- a glibc older than 2.28 fails fcntl64@GLIBC_2.28 at startup (§1.2)"
fi

# A-7 — libstdc++ must carry the GCC-5.1 C++11 ABI: GLIBCXX_3.4.21 and
# CXXABI_1.3.9 (§1.2 T8). As with A-6, name a missing library distinctly from
# an old one.
if ! find_lib libstdc++.so.6 >/dev/null; then
	fail "A-7 libstdc++ C++11 ABI" "libstdc++.so.6 not found in rootfs -- cannot check the GCC-5.1 C++11 ABI floor"
else
	a7v="$(lib_verdefs libstdc++.so.6)"
	a7_miss=""
	printf '%s' "$a7v" | grep -q 'Name: GLIBCXX_3.4.21' || a7_miss="$a7_miss GLIBCXX_3.4.21"
	printf '%s' "$a7v" | grep -q 'Name: CXXABI_1.3.9'   || a7_miss="$a7_miss CXXABI_1.3.9"
	if [ -z "$a7_miss" ]; then
		pass "A-7 libstdc++.so.6 provides GLIBCXX_3.4.21 and CXXABI_1.3.9"
	else
		fail "A-7 libstdc++ C++11 ABI" "missing:$a7_miss -- libstdc++ older than GCC 5.1 (§1.2 T8)"
	fi
fi

# =============================================================================
section "The glibc-2.34 merge trap (A-8, A-9) -- highest-value assertion (§1.3)"
# =============================================================================

# A-8 — since glibc 2.34 libpthread/librt are version-placeholder stubs. They
# must still EXIST as files AND still define the version node the binary's
# verneed names (GLIBC_2.4, the ARM baseline), or the loader hard-fails.
a8_bad=""
for so in libpthread.so.0 librt.so.1; do
	v="$(lib_verdefs "$so")" || { a8_bad="$a8_bad $so(absent)"; continue; }
	printf '%s' "$v" | grep -q 'Name: GLIBC_2.4' || a8_bad="$a8_bad $so(no GLIBC_2.4 node)"
done
if [ -z "$a8_bad" ]; then
	pass "A-8 libpthread.so.0 and librt.so.1 exist and define version node GLIBC_2.4"
else
	fail "A-8 pthread/rt stubs" "problem(s):$a8_bad -- the loader verifies verneed against the NAMED file's verdef; a stripped stub breaks 'version GLIBC_2.4 not found' (§1.3)"
fi

# A-9 — and libc.so.6 must export the five merged symbols as compat symbols at
# @GLIBC_2.4, so the loader resolves them from global scope (§1.3). Each named
# explicitly rather than counted, so a missing one is named.
A9_SYMS="pthread_create pthread_join pthread_attr_setaffinity_np shm_open shm_unlink"
a9_dyn="$(find_lib libc.so.6 >/dev/null && readelf -W --dyn-syms "$(find_lib libc.so.6)" 2>/dev/null)"
a9_miss=""
for sym in $A9_SYMS; do
	printf '%s' "$a9_dyn" | grep -qE "[[:space:]]${sym}@+GLIBC_2\.4( |$)" || a9_miss="$a9_miss $sym"
done
if [ -z "$a9_miss" ]; then
	pass "A-9 libc.so.6 exports all 5 merged symbols at @GLIBC_2.4"
else
	fail "A-9 merged symbols" "libc.so.6 missing @GLIBC_2.4 export(s):$a9_miss -- built without the compat stubs; derive the list for any binary with scripts/abi/needed-symbols.py (§1.3)"
fi

# =============================================================================
section "/MiSTer.version byte shape (A-11, A-12)"
# =============================================================================

# A-11/A-12 — the Downloader compares /MiSTer.version with a bare f.read() and
# NO .strip(): exactly 6 bytes, all ASCII digits, and crucially no trailing
# newline, or the box re-flashes on every Downloader run forever (§10.1, P2.6).
VERFILE="$ROOTFS/MiSTer.version"
if [ ! -f "$VERFILE" ]; then
	fail "A-11 /MiSTer.version present" "$VERFILE absent -- post-build.sh must write it at the rootfs root (P2.6)"
else
	nbytes="$(wc -c < "$VERFILE")"
	if [ "$nbytes" -eq 6 ]; then
		pass "A-11 /MiSTer.version is exactly 6 bytes"
	else
		fail "A-11 /MiSTer.version size" "$nbytes bytes, expected exactly 6 (§13.1 A-11)"
	fi
	# Byte-level: six digits 0x30-0x39, last byte not 0x0a. od, not $(cat) --
	# a command substitution would swallow the very newline this guards.
	hexbytes="$(od -An -tx1 "$VERFILE" | tr -d ' \n')"
	if printf '%s' "$hexbytes" | grep -qE '^(3[0-9]){6}$'; then
		pass "A-12 /MiSTer.version is six ASCII digits, no trailing newline"
	else
		last2="${hexbytes: -2}"
		reason="bytes=$hexbytes"
		[ "$last2" = "0a" ] && reason="$reason -- ends in a newline, which permanently breaks the Downloader's version-equality check (§10.1)"
		fail "A-12 /MiSTer.version byte shape" "$reason"
	fi
fi

# =============================================================================
section "Module-load ABI floor (A-24, A-25)"
# =============================================================================

# A-24 — the stock firmware floor is 66 regular files; newer modules only add.
FW_DIR=""
for d in usr/lib/firmware lib/firmware; do
	[ -d "$ROOTFS/$d" ] && { FW_DIR="$ROOTFS/$d"; break; }
done
if [ -z "$FW_DIR" ]; then
	fail "A-24 firmware present" "no usr/lib/firmware directory in rootfs"
else
	fwn="$(find "$FW_DIR" -type f | wc -l)"
	if [ "$fwn" -ge 66 ]; then
		pass "A-24 firmware: $fwn files (>= stock floor of 66)"
	else
		fail "A-24 firmware count" "$fwn files, below the stock floor of 66 (§13.1 A-24)"
	fi
fi

# A-25 — depmod must have regenerated modules.alias at image build, or udev
# cannot autoload a driver by modalias.
MODROOT=""
for d in usr/lib/modules lib/modules; do
	[ -d "$ROOTFS/$d" ] && { MODROOT="$ROOTFS/$d"; break; }
done
if [ -z "$MODROOT" ]; then
	fail "A-25 modules.alias present" "no usr/lib/modules directory in rootfs"
else
	# The single kernel-version subdirectory.
	KVER="$(find "$MODROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
	if [ -n "$KVER" ] && [ -s "$MODROOT/$KVER/modules.alias" ]; then
		pass "A-25 modules.alias regenerated by depmod (kernel $KVER)"
	else
		fail "A-25 modules.alias" "missing or empty under $MODROOT/${KVER:-<no kver dir>}/ -- depmod did not run at image build (§13.1 A-25)"
	fi
fi

# =============================================================================
section "Dynamic gates: the stock binary under qemu-user (A-10, A-22)"
# =============================================================================
# These run the ACTUAL stock `MiSTer` binary against THIS rootfs. The binary is
# a one-off P0.3-era extraction (work/, gitignored -- not produced by `make
# all`), so both gates degrade to SKIP when it, or qemu-arm, is absent: a
# missing test input is not a build regression. Same contract as ci-tests.sh.

QEMU_ARM="$(command -v qemu-arm || command -v qemu-arm-static || true)"
STOCK_MISTER="${STOCK_MISTER:-}"
if [ -z "$STOCK_MISTER" ]; then
	for cand in "$ROOT/work/imgroot/tmp/MiSTer" "$ROOT/work/extracted/files/MiSTer"; do
		[ -f "$cand" ] && { STOCK_MISTER="$cand"; break; }
	done
fi

if [ -z "$QEMU_ARM" ]; then
	skip "A-10 dynamic-link resolution" "qemu-arm not found on PATH"
	skip "A-22 FPGA-access whitelist"  "qemu-arm not found on PATH"
elif [ -z "$STOCK_MISTER" ] || [ ! -f "$STOCK_MISTER" ]; then
	skip "A-10 dynamic-link resolution" "no stock MiSTer binary (looked at work/imgroot/tmp/MiSTer, work/extracted/files/MiSTer; a gitignored P0.3 extraction, not a build artifact). Set STOCK_MISTER to override."
	skip "A-22 FPGA-access whitelist"  "same missing stock-binary reason"
else
	# MRL_TMPROOT is created lazily by mrl_extract_root; on the dir fast-path
	# (a rootfs dir, not an image) that never ran, so ensure it exists. It is
	# still cleaned wholesale by common.sh's EXIT trap.
	mkdir -p "$MRL_TMPROOT"
	WORKDIR="$(mktemp -d "${MRL_TMPROOT}/check-abi.XXXXXX")"
	MRL_CLEANUP_DIRS+=("$WORKDIR")
	MX="$WORKDIR/MiSTer.x"
	cp "$STOCK_MISTER" "$MX"
	chmod +x "$MX"

	# A-10 — every DT_NEEDED (plus the transitive libdl and the vDSO/loader)
	# resolves against THIS rootfs. The env-var trace form is the one that
	# works under qemu-user (invoking the loader directly segfaults -- §13.1
	# A-10 note). The pinned "15 lines" in §2.4 was measured against the STOCK
	# rootfs; our newer glibc legitimately resolves a different count (libdl is
	# merged), so the assertion is "nonzero exit is impossible and no line says
	# 'not found'", not a line count.
	ldtrace_out="$WORKDIR/ldtrace.out"
	LD_TRACE_LOADED_OBJECTS=1 "$QEMU_ARM" -L "$ROOTFS" -E LD_TRACE_LOADED_OBJECTS=1 "$MX" >"$ldtrace_out" 2>&1
	ldtrace_rc=$?
	sed 's/^/        /' "$ldtrace_out"
	if [ "$ldtrace_rc" -eq 0 ] && [ -s "$ldtrace_out" ] && ! grep -qi 'not found' "$ldtrace_out"; then
		pass "A-10 dynamic-link resolution: $(grep -c '=>' "$ldtrace_out") libs resolved, none 'not found'"
	else
		fail "A-10 dynamic-link resolution" "rc=$ldtrace_rc, or a 'not found' entry above -- a DT_NEEDED of the stock binary does not resolve against this rootfs (§2.4)"
	fi

	# A-22 — run to first hardware access. The stock binary must reach
	# openat("/dev/mem") = -1 EACCES and then SIGSEGV at 0x00706014 (§2.5).
	# Anything earlier (linker failure, missing lib, glibc symbol) is a hard
	# regression.
	#
	# The PRIMARY success signal is that SIGSEGV address, not the EACCES return.
	# Why: qemu-user's -strace is not line-atomic on a threaded guest (the stock
	# binary is threaded), so a syscall's return line can be split an arbitrary
	# number of lines away from its entry by another thread's output -- which is
	# what made ci-tests.sh's grep-adjacency approach intermittently miss the
	# EACCES and cry regression. The SIGSEGV line, by contrast, is a single
	# atomic line AND a precise fingerprint: 0x00706014 is exactly what
	# MAP_ADDR(0xFF706014) computes to when /dev/mem gave map_base==NULL, i.e.
	# it is reached ONLY on the denied-/dev/mem path (§2.5). If /dev/mem had
	# actually opened (e.g. run as root with real access) map_base != NULL and
	# the fault, if any, would be elsewhere -- so the fingerprint also
	# distinguishes the "premise no longer holds" case cleanly.
	strace_out="$WORKDIR/strace.out"
	timeout -k 5 20 "$QEMU_ARM" -L "$ROOTFS" -strace "$MX" >"$strace_out" 2>&1
	devmem_entry='openat\(.*"/dev/mem"'
	devmem_denied='= *-1 .*(errno=13|EACCES)'
	fpga_fault='SIGSEGV.*si_addr=0x0*706014'
	if grep -q 'error while loading shared libraries' "$strace_out"; then
		fail "A-22 FPGA-access whitelist" "dynamic linker itself failed -- regression before any real syscall; see $strace_out"
	elif grep -qi 'not found' "$strace_out"; then
		fail "A-22 FPGA-access whitelist" "a shared library was 'not found' -- regression before /dev/mem; see $strace_out"
	elif ! grep -qE "$devmem_entry" "$strace_out"; then
		fail "A-22 FPGA-access whitelist" "never reached openat(\"/dev/mem\") -- died earlier (regression) or ran past it; see $strace_out"
	elif grep -qE "$fpga_fault" "$strace_out"; then
		note "reached openat(\"/dev/mem\") and faulted at the §2.5 fingerprint SIGSEGV @ 0x00706014 (FPGA GPI read of 0xFF706014 with a NULL map_base) -- the denied-/dev/mem path, exactly as expected under qemu-user"
		pass "A-22 FPGA-access whitelist: dies at the FPGA-register fault, not earlier"
	elif grep -A1 -E "$devmem_entry" "$strace_out" | grep -qE "$devmem_denied"; then
		# Fallback: EACCES observed inline, but no fingerprint (e.g. the segv
		# was swallowed by the timeout). Still proves the denied-/dev/mem path.
		note "reached openat(\"/dev/mem\") = -1 EACCES, as expected (no FPGA bridge under qemu-user)"
		pass "A-22 FPGA-access whitelist: dies at /dev/mem access, not earlier"
	else
		fail "A-22 FPGA-access whitelist" "reached openat(\"/dev/mem\") but saw neither an EACCES return nor the §2.5 fault fingerprint. If /dev/mem SUCCEEDED, whoever ran this has /dev/mem access (root?) and the check's premise no longer holds; see $strace_out"
	fi
fi

# ---------------------------------------------------------------------------
# Digest — SKIPPED first (a skip is not a pass), then FAILURES, then RESULT.
# Mirrors ci-tests.sh so `check-abi.sh output | tail` names what broke.
# ---------------------------------------------------------------------------
{
	printf 'check-abi (P2.2) result -- rootfs %s\n' "$ROOTFS"
	printf 'PASS=%d FAIL=%d SKIP=%d\n' "$PASS_N" "$FAIL_N" "$SKIP_N"
	if [ "${#SKIPPED[@]}" -gt 0 ]; then
		printf 'SKIPPED:\n'; printf '  %s\n' "${SKIPPED[@]}"
	fi
	if [ "${#FAILURES[@]}" -gt 0 ]; then
		printf 'FAILURES:\n'; printf '  %s\n' "${FAILURES[@]}"
	fi
} > "$CHECK_ABI_LOG" 2>/dev/null || true

# GitHub Actions job-summary section: a one-line verdict plus a collapsible
# per-check table. Written to $GITHUB_STEP_SUMMARY so it renders on the run's
# Summary page in whatever workflow invoked this script (build.yml, release.yml).
# Best-effort: never let a summary-write problem change the run's exit status.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	if [ "$FAIL_N" -gt 0 ]; then
		abi_verdict="❌ **FAIL**"
	elif [ "$SKIP_N" -gt 0 ]; then
		abi_verdict="✅ **PASS** (with skips)"
	else
		abi_verdict="✅ **PASS**"
	fi
	{
		printf '### 🔗 ABI / SONAME parity (P2.2)\n\n'
		# shellcheck disable=SC2016  # printf format: the backtick is literal
		# markdown and %s are positional args, not shell expansions.
		printf '%s — %d passed, %d failed, %d skipped · rootfs `%s`\n\n' \
			"$abi_verdict" "$PASS_N" "$FAIL_N" "$SKIP_N" "${ROOTFS#"$ROOT/"}"
		printf '<details><summary>Per-check results (docs/abi-contract.md §13.1)</summary>\n\n'
		printf '| | Check |\n|:--:|---|\n'
		_i=0
		while [ "$_i" -lt "${#SUMMARY_TEXT[@]}" ]; do
			# Escape pipes so a reason string never breaks the table.
			_t="${SUMMARY_TEXT[$_i]//|/\\|}"
			printf '| %s | %s |\n' "${SUMMARY_EMOJI[$_i]}" "$_t"
			_i=$((_i + 1))
		done
		printf '\n</details>\n\n'
	} >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

printf '\n========================================================\n'
if [ "$SKIP_N" -gt 0 ]; then
	printf 'SKIPPED (%d):\n' "$SKIP_N"
	printf '  - %s\n' "${SKIPPED[@]}"
fi
if [ "$FAIL_N" -gt 0 ]; then
	printf 'FAILURES (%d):\n' "$FAIL_N"
	printf '  - %s\n' "${FAILURES[@]}"
fi
printf 'PASS=%d FAIL=%d SKIP=%d\n' "$PASS_N" "$FAIL_N" "$SKIP_N"
if [ "$FAIL_N" -gt 0 ]; then
	printf 'RESULT: FAIL\n'
	exit 1
fi
printf 'RESULT: PASS\n'
exit 0
