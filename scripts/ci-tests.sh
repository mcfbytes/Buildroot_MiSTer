#!/usr/bin/env bash
#
# ci-tests.sh — CI-runnable, non-hardware parity test suite (P3.12).
#
# Consolidates, into ONE command:
#   - the existing image-contract scripts (check-zimage-dtb.sh, check-linux-img.sh,
#     check-size-budget.sh) -- called, not reimplemented;
#   - the Makefile's structural initramfs checks (check-initramfs, initramfs-verify);
#   - the full P1.12 QEMU boot test of the initramfs /init (scripts/test-initramfs.sh);
#   - a P2.2/P2.8-style stock-`MiSTer`-binary ABI smoke, run under qemu-user against
#     the built rootfs (the dynamic-link-resolves-clean check and the
#     dies-at-FPGA-access-not-earlier whitelist -- docs/abi-contract.md §2.4/§2.5,
#     A-10/A-22). NOTE: this is a *lightweight* interim of just those two qemu-user
#     gates. The full ABI/loader checklist (docs/abi-contract.md §13.1) now lives in
#     its own deliverable, scripts/check-abi.sh (P2.2), which build.yml runs
#     alongside this suite. The overlap on A-10/A-22 is deliberate: they are the two
#     highest-value checks and cheap enough to assert in both places.
#   - per-service / per-artifact parity checks harvested from each Phase 3 parity
#     doc's "verify-in-build" checklist, asserted against the built
#     output/images/rootfs.tar (the actual shipped artifact) and, where a binary
#     must run, qemu-user against output/target as the sysroot.
#
# Usage: scripts/ci-tests.sh [build-dir]
#   build-dir defaults to "output" (repo-root-relative). Only the image-contract
#   scripts and the Phase-3 artifact checks honor an override -- the Makefile-based
#   initramfs checks and scripts/test-initramfs.sh use Buildroot's own fixed
#   output/ + output-initramfs/ layout (Makefile: OUTPUT_DIR := $(CURDIR)/output,
#   not parameterized) and are SKIPPED with an explicit reason if build-dir differs.
#
# Output: one PASS/FAIL/SKIP line per check (grouped by phase/subsystem), full
# detail from called scripts shown inline, then a summary. SKIP never fails the
# suite; any FAIL does.
#
# The run is long (thousands of lines once the called scripts' own output is in
# there), so the LAST thing printed is a self-contained digest, in this order:
#
#     SKIPPED (n)   -- checks that did NOT run, with why. A skip is not a pass.
#     FAILURES (n)  -- every failure, with its reason. Omitted when there are none.
#     RESULT: PASS|FAIL
#
# So `scripts/ci-tests.sh | tail -n 30` tells you what broke and why, without
# scrolling or grepping -- which is the whole point: the previous version printed
# the failure ONLY at the moment it happened (on stderr, buried mid-run) and the
# end-of-run summary was a flat 46-line PASS/FAIL list, so a `tail` showed the
# counts and named nothing. An intermittent failure was seen but not identifiable.
# Under GitHub Actions each failure is additionally emitted as a ::error::
# annotation, so it shows up in the run UI rather than only in the raw log.
#
# Exit: 0 = every check PASSed or SKIPped. 1 = at least one FAIL. 2 = usage error.
#
# Env overrides (all optional):
#   CI_TESTS_SKIP_QEMU_SYSTEM=1   skip scripts/test-initramfs.sh (the slow one --
#                                 builds/reuses a whole QEMU test kernel and boots
#                                 it 6 times; everything else in this suite is fast)
#   CI_TESTS_LOG=<path>           where to write the machine-readable result list
#                                 (default: <build-dir>/ci-tests-results.txt). Best
#                                 -effort: if the path is not writable the run still
#                                 passes. Upload this as a CI artifact.

set -u
# Deliberately not -e: this script's entire job is "run every check, keep going,
# report the full picture" -- exactly test-initramfs.sh's own stated rationale.

prog=${0##*/}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

BUILD_DIR_ARG="${1:-output}"
case "$BUILD_DIR_ARG" in
	/*) BUILD_DIR="$BUILD_DIR_ARG" ;;
	*)  BUILD_DIR="$ROOT/$BUILD_DIR_ARG" ;;
esac
IS_DEFAULT_OUTPUT=0
[ "$BUILD_DIR" = "$ROOT/output" ] && IS_DEFAULT_OUTPUT=1

IMAGES="$BUILD_DIR/images"
TARGET="$BUILD_DIR/target"
HOST_SBIN="$BUILD_DIR/host/sbin"
ROOTFS_TAR="$IMAGES/rootfs.tar"
ZIMAGE_DTB="$IMAGES/zImage_dtb"
LINUX_IMG="$IMAGES/linux.img"
# The MAIN kernel's version. Every module/vermagic check below scopes to
# usr/lib/modules/$KVER/ on purpose: since ADR 0021's 2026-07-18 amendment the
# rootfs may also carry kernel-VARIANT trees (e.g. the RT beta's 7.2.0-rc3*,
# merged in via work/extra-modules-overlay), and those are deliberately out of
# scope here — their depmod health is asserted by check-abi.sh A-25 (every
# tree), and their presence in CI by build.yml's merged-kver assert. Do not
# "fix" these checks to glob across all trees; they would then pass on the
# variant tree while the main one regressed.
#
# DERIVED, never hardcoded. This was literally `KVER=6.18.38` until 2026-07-19,
# and it drifted the moment the kernel moved to 6.18.39: every module check
# below started looking in usr/lib/modules/6.18.38/, found nothing, and
# reported six failures that all read like the kernel-module packages had gone
# stale ("a kernel bump needs 'make <pkg>-dirclean'") when in fact the build was
# fine and only this constant was wrong. A hardcoded version here does not fail
# safe -- it fails *misleadingly*, pointing the reader at the wrong subsystem.
#
# Read the MAIN image's defconfig specifically, which is what the scoping note
# above is about: configs/mister_rt.fragment overrides this symbol for the RT
# variant, and configs/mister_kernel_defconfig carries a lockstep copy
# (scripts/check-kernel-defconfig-sync.sh asserts those two agree).
#
# Anchored to ^ and taking the last match on purpose: the defconfig explains
# this symbol in a comment that quotes it verbatim, so an unanchored match
# returns two lines -- the exact bug fixed in the hash-sync workflow (#42).
KVER=$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\([^"]*\)".*$/\1/p' \
	"$ROOT/configs/mister_de10nano_defconfig" | tail -1)
if [ -z "$KVER" ]; then
	echo "FATAL: could not read BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE from" >&2
	echo "       $ROOT/configs/mister_de10nano_defconfig" >&2
	exit 1
fi

# ---------------------------------------------------------------- reporting
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -a SUMMARY=()

# Why these two exist, and not just SUMMARY: a failing run buries its one FAIL
# line among ~45 PASS lines, and the end-of-run summary reprinted the same flat
# list -- so `tail` landed on the counts and showed WHICH checks failed nowhere.
# (That is not hypothetical; it is exactly how an intermittent failure was seen
# but not identified.) These hold the failures and skips, with their reason text,
# so the end of the run can reprint just those. Element format: "name<TAB>reason".
declare -a FAILED=()
declare -a SKIPPED=()

section() {
	printf '\n=== %s ===\n' "$*"
}

pass() {
	printf 'PASS  %s\n' "$1"
	SUMMARY+=("PASS  $1")
	PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
	# stderr, so a failure is still visible when stdout is redirected away --
	# but it is ALSO recorded in FAILED and reprinted to stdout at the end, so
	# that a plain `... | tail` (stdout only) can never miss it.
	printf 'FAIL  %s\n' "$1" >&2
	[ -n "${2:-}" ] && printf '      %s\n' "$2" >&2
	SUMMARY+=("FAIL  $1")
	FAILED+=("$1"$'\t'"${2:-}")
	FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
	printf 'SKIP  %s -- %s\n' "$1" "$2"
	SUMMARY+=("SKIP  $1 -- $2")
	SKIPPED+=("$1"$'\t'"$2")
	SKIP_COUNT=$((SKIP_COUNT + 1))
}

note() { printf '  %s\n' "$*"; }

# Run an external check-*.sh (or similar) command, show its output, then convert
# its exit code to one summary line. Reuses the script's own PASS/FAIL logic --
# does NOT re-derive it.
run_script() {
	local name=$1; shift
	printf -- '--- %s: %s ---\n' "$name" "$*"
	if "$@"; then
		pass "$name"
	else
		fail "$name" "'$*' exited nonzero -- see output above"
	fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# require_present PATH LABEL -- PASS if PATH is in rootfs.tar, else FAIL.
require_present() {
	if tar_has "$1"; then
		pass "$2 present"
	else
		fail "$2 present" "$1 not in rootfs.tar"
	fi
}

# require_absent PATH LABEL [WHY] -- PASS if PATH is NOT in rootfs.tar, else FAIL.
# The mirror of require_present, for the deliberate-exclusion gates: a package
# whose upstream default installs more than we want (ADR 0022's client-only
# nfs-utils being the case in hand) regains the extra binaries silently on any
# option or version bump, and nothing else in the build would complain.
require_absent() {
	if tar_has "$1"; then
		fail "$2 absent" "$1 IS in rootfs.tar${3:+ -- $3}"
	else
		pass "$2 absent"
	fi
}

# not_busybox_symlink PATH LABEL -- PASS if PATH is present in rootfs.tar AND
# is not a symlink into busybox, else FAIL. For the T5 "two packages install
# the same path, BusyBox must not be the one that won" regression guard
# (board/mister/de10nano/busybox.fragment): a collision that quietly resolves
# back to the BusyBox stub -- e.g. a future edit re-enables the applet without
# noticing a real package already owns that path -- is silent at build time
# (last install just wins) and would otherwise only surface as a user running
# a crippled lsof/lsusb/mkdosfs/chvt/openvt at runtime. require_present alone
# does not catch that (both providers satisfy "present"), so this checks what
# provided it.
not_busybox_symlink() {
	local path="$1" label="$2" line
	if ! tar_has "$path"; then
		fail "$label is the real package, not BusyBox" "$path not in rootfs.tar at all"
		return
	fi
	line=$(tar tvf "$ROOTFS_TAR" -- "./$path" 2>/dev/null | head -1)
	case "$line" in
	*'-> '*busybox*)
		fail "$label is the real package, not BusyBox" "still a busybox symlink: $line" ;;
	*)
		pass "$label is the real package, not BusyBox" ;;
	esac
}

# ---------------------------------------------------------------- prereqs
[ -f "$ROOTFS_TAR" ] || { echo "$prog: no $ROOTFS_TAR -- run a build first (or pass the build dir as \$1)." >&2; exit 2; }

TAR_LIST="$(mktemp "${TMPDIR:-/tmp}/ci-tests-tarlist.XXXXXX")"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ci-tests-work.XXXXXX")"
# shellcheck disable=SC2329 # invoked indirectly via `trap cleanup EXIT` below
cleanup() { rm -f "$TAR_LIST"; rm -rf "$WORKDIR"; }
trap cleanup EXIT
tar tf "$ROOTFS_TAR" > "$TAR_LIST"

# tar_has PATH -- PATH without leading "./"; true if that exact entry (file,
# dir, or symlink -- tar tf lists all of them by name regardless of type) is
# in the built rootfs.tar.
tar_has() { grep -qxF "./$1" "$TAR_LIST"; }

# tar_size PATH -- prints the byte size tar recorded for PATH (0 for dirs/symlinks).
tar_size() {
	tar tvf "$ROOTFS_TAR" -- "./$1" 2>/dev/null | awk '{print $3; exit}'
}

QEMU_ARM=""
have qemu-arm && QEMU_ARM=qemu-arm
qemu_target() {
	# Run a target-ARM binary from $TARGET against $TARGET as its own sysroot.
	"$QEMU_ARM" -L "$TARGET" "$@"
}

echo "$prog: build dir = $BUILD_DIR"
echo "$prog: rootfs.tar = $ROOTFS_TAR ($(wc -c <"$ROOTFS_TAR" | tr -d ' ') bytes, $(wc -l <"$TAR_LIST" | tr -d ' ') entries)"
[ -n "$QEMU_ARM" ] && echo "$prog: qemu-arm = $(command -v qemu-arm) ($(qemu-arm --version 2>&1 | head -1))" \
	|| echo "$prog: qemu-arm NOT FOUND -- qemu-user checks will SKIP"

# =============================================================================
section "Image contracts (A3 / A9 / ADR 0015 / size budget)"
# =============================================================================

run_script "check-zimage-dtb.sh"  "$ROOT/scripts/check-zimage-dtb.sh" "$ZIMAGE_DTB"
run_script "check-linux-img.sh"   "$ROOT/scripts/check-linux-img.sh"  "$LINUX_IMG" "$HOST_SBIN"
run_script "check-size-budget.sh" "$ROOT/scripts/check-size-budget.sh" "$LINUX_IMG" "$HOST_SBIN"

# =============================================================================
section "Initramfs (P1.10-P1.12, A7)"
# =============================================================================

if [ "$IS_DEFAULT_OUTPUT" -eq 1 ]; then
	printf -- '--- check-initramfs (Makefile: main kernel .config has CONFIG_BLK_DEV_INITRD / CONFIG_INITRAMFS_SOURCE) ---\n'
	if ( cd "$ROOT" && make --no-print-directory check-initramfs ); then
		pass "check-initramfs (main kernel config)"
	else
		fail "check-initramfs (main kernel config)"
	fi

	printf -- '--- initramfs-verify (Makefile: required BusyBox applets + /init + /dev/console present in the cpio, ash -n parses /init) ---\n'
	if ( cd "$ROOT" && make --no-print-directory initramfs-verify ); then
		pass "initramfs-verify (cpio applet/structure check)"
	else
		fail "initramfs-verify (cpio applet/structure check)"
	fi
else
	skip "check-initramfs (main kernel config)" "Makefile's OUTPUT_DIR is fixed to ./output, not parameterized; build dir here is $BUILD_DIR"
	skip "initramfs-verify (cpio applet/structure check)" "same fixed-OUTPUT_DIR reason"
fi

if [ "${CI_TESTS_SKIP_QEMU_SYSTEM:-0}" = "1" ]; then
	skip "test-initramfs.sh (P1.12 QEMU boot test, 6 cases)" "CI_TESTS_SKIP_QEMU_SYSTEM=1"
elif ! have qemu-system-arm; then
	skip "test-initramfs.sh (P1.12 QEMU boot test, 6 cases)" "qemu-system-arm not found on PATH"
else
	printf -- '--- test-initramfs.sh: fat32 exfat label nonascii missing-image rootwait ---\n'
	printf '  (builds/reuses a QEMU test kernel and boots it 6 times -- can take several minutes)\n'
	if "$ROOT/scripts/test-initramfs.sh"; then
		pass "test-initramfs.sh (P1.12 QEMU boot test, 6 cases)"
	else
		fail "test-initramfs.sh (P1.12 QEMU boot test, 6 cases)" "one or more of the 6 cases failed -- see output above"
	fi
fi

# =============================================================================
section "ABI / stock-binary smoke (P2.2 + P2.8 core checks)"
# =============================================================================
# The stock `MiSTer` binary is a one-off P0.3-era extraction (work/, gitignored --
# not reproduced by a fresh `make all`), so this whole group degrades to SKIP
# when it isn't present, per this script's own design contract: a missing input
# is not a build regression.

STOCK_MISTER=""
for cand in "$ROOT/work/imgroot/tmp/MiSTer" "$ROOT/work/extracted/files/MiSTer"; do
	[ -f "$cand" ] && { STOCK_MISTER="$cand"; break; }
done

if [ -z "$QEMU_ARM" ]; then
	skip "dynamic-link resolution (P2.2/A-10)" "qemu-arm not found on PATH"
	skip "FPGA-access whitelist (P2.8/A-22)" "qemu-arm not found on PATH"
elif [ -z "$STOCK_MISTER" ]; then
	skip "dynamic-link resolution (P2.2/A-10)" "no stock MiSTer binary found (looked at work/imgroot/tmp/MiSTer, work/extracted/files/MiSTer -- a P0.3-era extraction, gitignored, not a build artifact)"
	skip "FPGA-access whitelist (P2.8/A-22)" "same missing stock-binary reason"
else
	MX="$WORKDIR/MiSTer.x"
	cp "$STOCK_MISTER" "$MX"
	chmod +x "$MX"

	printf -- '--- dynamic-link resolution: LD_TRACE_LOADED_OBJECTS against %s ---\n' "$TARGET"
	ldtrace_out="$WORKDIR/ldtrace.out"
	LD_TRACE_LOADED_OBJECTS=1 "$QEMU_ARM" -L "$TARGET" -E LD_TRACE_LOADED_OBJECTS=1 "$MX" >"$ldtrace_out" 2>&1
	ldtrace_rc=$?
	sed 's/^/  /' "$ldtrace_out"
	# NOTE: docs/abi-contract.md §2.4 measured "exactly 15 lines" against the
	# STOCK rootfs (work/imgroot) as a known-good baseline -- not a number to pin
	# against OUR rootfs, whose newer glibc legitimately resolves a different
	# (currently 14-line) set with no `libdl.so.2` line. The actual P2.2
	# assertion is "every name resolves, none 'not found'" -- that's what's
	# checked here.
	if [ "$ldtrace_rc" -eq 0 ] && [ -s "$ldtrace_out" ] && ! grep -qi 'not found' "$ldtrace_out"; then
		pass "dynamic-link resolution (P2.2/A-10): $(wc -l <"$ldtrace_out" | tr -d ' ') libs, none 'not found'"
	else
		fail "dynamic-link resolution (P2.2/A-10)" "rc=$ldtrace_rc, or a 'not found' entry above -- see $ldtrace_out"
	fi

	printf -- '--- FPGA-access whitelist: qemu-arm -strace, expect openat(.../dev/mem) EACCES then SIGSEGV, nothing earlier ---\n'
	strace_out="$WORKDIR/strace.out"
	timeout -k 5 20 "$QEMU_ARM" -L "$TARGET" -strace "$MX" >"$strace_out" 2>&1
	# The entry and the return are matched SEPARATELY, and the return is allowed to
	# be one line late. That is not sloppiness -- qemu-user's -strace is not
	# line-atomic. It emits the syscall entry and its return as two separate
	# writes, so with a threaded guest (the stock MiSTer binary is threaded)
	# another thread's line can land BETWEEN them and split the return off:
	#
	#   openat(AT_FDCWD,"/dev/mem",O_RDWR|...|O_CLOEXEC)852734 futex(...) = 0
	#    = -1 errno=13 (Permission denied)
	#
	# The old single-line regex (entry .* return) therefore missed roughly 1 run in
	# 40 -- measured, not guessed -- and reported it as "never reached /dev/mem",
	# i.e. announced a REGRESSION on what was really trace interleaving. That was
	# the suite's intermittent failure.
	devmem_entry='openat\(.*"/dev/mem"'
	devmem_denied='= *-1 .*(errno=13|EACCES)'
	if grep -q 'error while loading shared libraries' "$strace_out"; then
		fail "FPGA-access whitelist (P2.8/A-22)" "dynamic linker itself failed -- regression before any real syscall; see $strace_out"
	elif ! grep -qE "$devmem_entry" "$strace_out"; then
		fail "FPGA-access whitelist (P2.8/A-22)" "never reached openat(\"/dev/mem\") -- died earlier (regression) or ran past it; see $strace_out"
	elif grep -A1 -E "$devmem_entry" "$strace_out" | grep -qE "$devmem_denied"; then
		devmem_line=$(grep -nE "$devmem_entry" "$strace_out" | head -1 | cut -d: -f1)
		note "reached openat(\"/dev/mem\") at line $devmem_line of the trace (permission denied, as expected -- no FPGA bridge under qemu-user)"
		pass "FPGA-access whitelist (P2.8/A-22): dies at /dev/mem access, not earlier"
	else
		fail "FPGA-access whitelist (P2.8/A-22)" \
			"reached openat(\"/dev/mem\") but its return was not the expected -1 EACCES. If the trace shows it SUCCEEDING, whoever ran this has /dev/mem access (running as root?) and the check's premise no longer holds; see $strace_out"
	fi
fi

# =============================================================================
section "P3.1/P3.3 — Module autoload + vermagic"
# =============================================================================

MODULES_DEP="usr/lib/modules/$KVER/modules.dep"
MODULES_ALIAS="usr/lib/modules/$KVER/modules.alias"

if tar_has "$MODULES_DEP"; then
	dep_lines=$(tar xOf "$ROOTFS_TAR" "./$MODULES_DEP" 2>/dev/null | wc -l | tr -d ' ')
	if [ "$dep_lines" -gt 0 ]; then
		pass "modules.dep non-empty ($dep_lines lines)"
	else
		fail "modules.dep non-empty" "file present but empty -- depmod did not run or found nothing"
	fi
else
	fail "modules.dep non-empty" "$MODULES_DEP not in rootfs.tar"
fi

if tar_has "$MODULES_ALIAS"; then
	alias_lines=$(tar xOf "$ROOTFS_TAR" "./$MODULES_ALIAS" 2>/dev/null | wc -l | tr -d ' ')
	alias_content="$WORKDIR/modules.alias"
	tar xOf "$ROOTFS_TAR" "./$MODULES_ALIAS" 2>/dev/null > "$alias_content"
	if [ "$alias_lines" -gt 0 ]; then
		pass "modules.alias non-empty ($alias_lines lines)"
	else
		fail "modules.alias non-empty" "file present but empty"
	fi

	if grep -qi ' btusb$' "$alias_content"; then
		pass "btusb modalias present in modules.alias"
	else
		fail "btusb modalias present in modules.alias" "no 'alias usb:... btusb' line found"
	fi

	if grep -qiE ' (rtl8187|rtl8192cu|rtl8xxxu|r8188eu|8188eu|rtw88_usb|rtw_8[0-9]{3}[a-z]?u)$' "$alias_content"; then
		pass "Realtek USB WiFi modalias present in modules.alias"
	else
		fail "Realtek USB WiFi modalias present in modules.alias" "no rtl8187/rtl8192cu/rtl8xxxu/r8188eu/rtw88 alias line found"
	fi
else
	fail "modules.alias non-empty" "$MODULES_ALIAS not in rootfs.tar"
	skip "btusb modalias present in modules.alias" "modules.alias missing"
	skip "Realtek USB WiFi modalias present in modules.alias" "modules.alias missing"
fi

# Vermagic: every .ko/.ko.xz under this kernel's modules dir must agree on a
# single "$KVER ... ARMv7" string (mismatched vermagic = module refuses to load).
ko_list="$WORKDIR/ko_list.txt"
grep -E "^\./usr/lib/modules/$KVER/.*\.ko(\.xz)?\$" "$TAR_LIST" > "$ko_list" || true
ko_count=$(wc -l <"$ko_list" | tr -d ' ')
if [ "$ko_count" -eq 0 ]; then
	fail "module vermagic ($KVER, ARMv7)" "no .ko/.ko.xz files found under usr/lib/modules/$KVER"
elif ! have xz; then
	skip "module vermagic ($KVER, ARMv7)" "xz not found on PATH (needed to decompress .ko.xz)"
else
	vermagics="$WORKDIR/vermagics.txt"
	: > "$vermagics"
	while IFS= read -r member; do
		path="${member#./}"
		case "$path" in
		*.ko.xz)
			tar xOf "$ROOTFS_TAR" "./$path" 2>/dev/null | xz -dc 2>/dev/null | strings | grep -m1 '^vermagic=' >> "$vermagics"
			;;
		*.ko)
			tar xOf "$ROOTFS_TAR" "./$path" 2>/dev/null | strings | grep -m1 '^vermagic=' >> "$vermagics"
			;;
		esac
	done < "$ko_list"
	distinct=$(LC_ALL=C sort -u "$vermagics" | wc -l | tr -d ' ')
	bad=$(grep -cvE "^vermagic=$KVER .*ARMv7" "$vermagics" || true)
	if [ "$distinct" -eq 1 ] && [ "$bad" -eq 0 ]; then
		pass "module vermagic ($KVER, ARMv7): consistent across all $ko_count modules -- $(LC_ALL=C sort -u "$vermagics")"
	else
		fail "module vermagic ($KVER, ARMv7)" "$distinct distinct vermagic string(s) across $ko_count modules, $bad not matching '$KVER ... ARMv7':"
		sed 's/^/      /' "$vermagics" | LC_ALL=C sort -u >&2
	fi
fi

# =============================================================================
section "P3.3 — Firmware parity (docs/firmware-parity.md documented present-set)"
# =============================================================================

STOCK_FW_MD="$ROOT/docs/stock-inventory/firmware.md"
PARITY_FW_MD="$ROOT/docs/firmware-parity.md"

if [ ! -f "$STOCK_FW_MD" ] || [ ! -f "$PARITY_FW_MD" ]; then
	skip "firmware present-set (docs/firmware-parity.md)" "doc(s) missing: $STOCK_FW_MD / $PARITY_FW_MD"
else
	all_fw="$WORKDIR/fw_all66.txt"
	missing_fw="$WORKDIR/fw_missing10.txt"
	present_fw="$WORKDIR/fw_present.txt"
	# shellcheck disable=SC2016 # backticks are literal markdown code-span
	# delimiters in docs/stock-inventory/firmware.md, not command substitution.
	grep -E '^\| `[^`]+` \|' "$STOCK_FW_MD" | sed -E 's/^\| `([^`]+)`.*/\1/' | grep -v '/$' | LC_ALL=C sort > "$all_fw"
	awk '/\*\*Missing \([0-9]+\):\*\*/{f=1;next} f&&/^```/{c++;if(c==2)exit;next} f&&c==1{print}' "$PARITY_FW_MD" | LC_ALL=C sort > "$missing_fw"
	comm -23 "$all_fw" "$missing_fw" > "$present_fw"

	all_n=$(wc -l <"$all_fw" | tr -d ' ')
	missing_n=$(wc -l <"$missing_fw" | tr -d ' ')
	present_n=$(wc -l <"$present_fw" | tr -d ' ')
	note "docs say: $all_n stock files total, $missing_n documented as not reproduced (justified omissions), $present_n expected present"

	if [ "$all_n" -eq 0 ] || [ "$present_n" -eq 0 ]; then
		fail "firmware present-set (docs/firmware-parity.md)" "doc parsing produced an empty list -- doc format probably changed; script needs updating, not the build"
	else
		fw_missing_from_tar="$WORKDIR/fw_missing_from_tar.txt"
		: > "$fw_missing_from_tar"
		while IFS= read -r p; do
			tar_has "usr/lib/firmware/$p" || echo "$p" >> "$fw_missing_from_tar"
		done < "$present_fw"
		nmiss=$(wc -l <"$fw_missing_from_tar" | tr -d ' ')
		if [ "$nmiss" -eq 0 ]; then
			pass "firmware present-set: all $present_n documented-present stock files are in rootfs.tar"
		else
			fail "firmware present-set" "$nmiss of $present_n documented-present files are MISSING from rootfs.tar:"
			sed 's/^/      /' "$fw_missing_from_tar" >&2
		fi
	fi
fi

# =============================================================================
section "P3.2 — xone (Xbox One/Series accessory driver)"
# =============================================================================

xone_mods="xone_dongle xone_gip xone_gip_chatpad xone_gip_gamepad xone_gip_headset xone_gip_madcatz_glam xone_gip_madcatz_strat xone_gip_pdp_jaguar xone_wired"
xone_missing=""
for m in $xone_mods; do
	tar_has "usr/lib/modules/$KVER/updates/$m.ko.xz" || xone_missing="$xone_missing $m"
done
if [ -z "$xone_missing" ]; then
	pass "xone: all 9 .ko.xz modules present"
else
	fail "xone: all 9 .ko.xz modules present" "missing:$xone_missing"
fi

# In-kernel USB WiFi (ADR 0016 as updated in v10, docs/wifi-parity.md §6).
#
# This assertion USED to check the opposite thing: that the out-of-tree
# 8812au/8821au .ko.xz were present under updates/. They are deliberately gone
# now -- mainline gained rtw88_8812au / rtw88_8821au (the shared rtw88_88xxa
# core, 6.13), so BR2_PACKAGE_RTL8812AU and BR2_PACKAGE_RTL8821AU_MORROWNR are
# deselected. Asserting the in-kernel replacements is the same protection
# against the same failure: a chip silently losing its driver.
#
# The stale-kmod hazard the old comment described is real and NOT solved by
# moving in-tree -- it just moved too. A kernel version bump rebuilds in-tree
# modules into a NEW lib/modules/<newver>/ while any out-of-tree kernel-module
# PACKAGE (xone and, since v10.2, rtl8852cu-morrownr -- both asserted here)
# stays stamped against the OLD kernel, landing in a stale tree. Because these
# paths are $KVER-scoped, this check fires if the in-tree modules ever fail to
# build for the shipped kernel. Fix when it fires: `make <pkg>-dirclean` for the
# stale package, or `make linux-rebuild all`, then rebuild.
rtwdir="usr/lib/modules/$KVER/kernel/drivers/net/wireless/realtek/rtw88"
# All seven rtw88 USB parts 6.18 offers -- 8814au was migrated in PR #35;
# 8812au/8821au/8723du complete the set in v10.
rtw88_usb_mods="rtw88_8822bu rtw88_8822cu rtw88_8821cu rtw88_8814au rtw88_8723du rtw88_8821au rtw88_8812au"
rtw88_missing=""
for m in $rtw88_usb_mods; do
	tar_has "$rtwdir/$m.ko.xz" || rtw88_missing="$rtw88_missing $m"
done
if [ -z "$rtw88_missing" ]; then
	pass "in-kernel WiFi: all 7 rtw88 USB .ko.xz present (ADR 0016 / v10)"
else
	fail "in-kernel WiFi: all 7 rtw88 USB .ko.xz present (ADR 0016 / v10)" \
		"missing:$rtw88_missing -- a CONFIG_RTW88_*U was dropped, or a kernel bump left the module tree stale (make linux-rebuild all)"
fi

# The REDUNDANT out-of-tree forks must NOT come back: if both an OOT fork and
# the in-kernel driver for the same chip ship, they bind-fight on the same USB
# IDs and which one wins is load-order dependent (ADR 0016's stated reason for
# disabling, not merely not-enabling, them). Assert their absence so a
# well-meaning re-enable of BR2_PACKAGE_RTL8812AU / _RTL8821AU_MORROWNR fails
# loudly here.
#
# NOTE this list is specifically 8812au/8821au, and it is NOT a blanket "no
# out-of-tree WiFi" rule -- v10.2 deliberately ships one such module, 8852cu,
# asserted PRESENT just below. The two assertions do not contradict each other
# because ADR 0016's rule was never "no forks": it is "no fork for a chip
# mainline can already drive". 8812au/8821au have rtw88_8812au/rtw88_8821au;
# RTL8852CU has nothing (rtw89 is PCIe-only for 8852C). Anything added to this
# list must be a chip with an in-kernel USB driver in the shipped kernel.
ootwifi_present=""
for m in 8812au 8821au; do
	tar_has "usr/lib/modules/$KVER/updates/$m.ko.xz" && ootwifi_present="$ootwifi_present $m"
done
if [ -z "$ootwifi_present" ]; then
	pass "redundant out-of-tree WiFi forks absent (8812au/8821au, ADR 0016 / v10)"
else
	fail "redundant out-of-tree WiFi forks absent (8812au/8821au, ADR 0016 / v10)" \
		"present:$ootwifi_present -- would bind-fight the in-kernel rtw88_88xxa drivers on the same USB IDs"
fi

# The ONE permitted out-of-tree WiFi fork must be present: 8852cu.ko
# (package/rtl8852cu-morrownr, BR2_PACKAGE_RTL8852CU_MORROWNR=y), for the
# RTL8852CU/RTL8832CU Wi-Fi 6E USB chips. Mainline 6.18 has the 8852C chip HAL
# in rtw89 but only a PCIe bus file (rtw8852ce.c; no rtw8852cu.c), and
# RTW89_8852CE depends on PCI which this board has not got -- so without this
# module those dongles bind NOTHING. See docs/wifi-parity.md §8 and ADR 0016's
# v10.2 update.
#
# Same shape and same path as the xone assertion above (updates/, .ko.xz),
# because it is the same mechanism: the kernel's scripts/Makefile.modinst
# defaults INSTALL_MOD_DIR to `updates` for M= builds, and Buildroot xz-
# compresses modules. It therefore catches the same two failures -- the package
# silently building no .ko (its `obj-$(CONFIG_RTL8852CU)` needs the
# CONFIG_RTL8852CU=m the .mk passes, and its ccflags need the KSRC= override; if
# either is lost the build "succeeds" with zero objects), and a kernel bump
# leaving the module stamped against the OLD $KVER.
if tar_has "usr/lib/modules/$KVER/updates/8852cu.ko.xz"; then
	pass "out-of-tree WiFi: 8852cu.ko.xz present under updates/ (RTL8852CU, ADR 0016 / v10.2)"
else
	fail "out-of-tree WiFi: 8852cu.ko.xz present under updates/ (RTL8852CU, ADR 0016 / v10.2)" \
		"BR2_PACKAGE_RTL8852CU_MORROWNR dropped, the package built zero objects (CONFIG_RTL8852CU=m / KSRC= lost from MODULE_MAKE_OPTS), or a kernel bump left it stale (make rtl8852cu-morrownr-dirclean; make linux-rebuild all)"
fi

# Broadcom/Cypress FullMAC USB (v10): brcmfmac + its brcmutil helper. New in
# this image -- CONFIG_WLAN_VENDOR_BROADCOM was off entirely before.
brcm_missing=""
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko.xz" \
	|| brcm_missing="$brcm_missing brcmfmac"
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/broadcom/brcm80211/brcmutil/brcmutil.ko.xz" \
	|| brcm_missing="$brcm_missing brcmutil"
if [ -z "$brcm_missing" ]; then
	pass "in-kernel WiFi: brcmfmac + brcmutil .ko.xz present (BCM43xx/CYW43xx USB, v10)"
else
	fail "in-kernel WiFi: brcmfmac + brcmutil .ko.xz present (BCM43xx/CYW43xx USB, v10)" \
		"missing:$brcm_missing -- CONFIG_BRCMFMAC/CONFIG_WLAN_VENDOR_BROADCOM dropped?"
fi

# Firmware for drivers that were being built with NO firmware at all
# (docs/wifi-parity.md §6.2/§6.3, docs/bluetooth-parity.md §9): MT7663U, ath3k,
# and the MediaTek BT half of the MT7921AU/MT7925U combo dongles whose WiFi half
# we already shipped, all probed and then failed at request_firmware(). Assert
# the blobs ship so that regression cannot recur silently.
#   - MT7663U needs BOTH ROM-patch/N9 pairs: the driver picks the N9 to match
#     whichever patch bound, so a half-set breaks a live fallback path.
#   - The QCA pair is the "_usb_" variant specifically -- btusb's QCA path is
#     self-contained (no CONFIG_BT_QCA) and asks for exactly these names.
#   - rtl8761b/bu back the most common cheap USB Bluetooth 5 dongles on sale;
#     they already shipped, and are asserted here so a firmware sub-option
#     reshuffle cannot drop them unnoticed.
fw_missing=""
for f in \
	mediatek/mt7663pr2h.bin mediatek/mt7663_n9_v3.bin \
	mediatek/mt7663pr2h_rebb.bin mediatek/mt7663_n9_rebb.bin \
	ath3k-1.fw \
	brcm/brcmfmac43143.bin brcm/brcmfmac43236b.bin \
	brcm/brcmfmac43242a.bin brcm/brcmfmac43569.bin \
	rtlwifi/rtl8192dufw.bin rsi/rs9113_wlan_qspi.rps rsi/rs9116_wlan.rps \
	mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin \
	mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin \
	mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin \
	qca/rampatch_usb_00000302.bin qca/nvm_usb_00000302.bin \
	brcm/BCM-0bb4-0306.hcd brcm/BCM20702A1-0b05-17cb.hcd \
	rtl_bt/rtl8761b_fw.bin rtl_bt/rtl8761bu_fw.bin
do
	tar_has "usr/lib/firmware/$f" || fw_missing="$fw_missing $f"
done
if [ -z "$fw_missing" ]; then
	pass "WiFi/BT firmware: mt7663/ath3k/brcmfmac/rtl8192du/rsi + MTK-BT/QCA-BT/brcm-hcd/rtl8761b present"
else
	fail "WiFi/BT firmware: mt7663/ath3k/brcmfmac/rtl8192du/rsi + MTK-BT/QCA-BT/brcm-hcd/rtl8761b present" \
		"missing:$fw_missing -- a driver would probe then fail at request_firmware()"
fi

# v10.1 USB WiFi round-out (docs/wifi-parity.md §7). Every one of these had its
# firmware checked above or already shipping; assert the modules themselves.
# ath6k/AR6004 is a DIRECTORY in Buildroot's file list, so the firmware check
# above deliberately does not name a file inside it -- covered here by the
# driver's presence plus the ATHEROS_6004 defconfig symbol.
v101_missing=""
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8192du/rtl8192du.ko.xz" \
	|| v101_missing="$v101_missing rtl8192du"
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/ath/ath6kl/ath6kl_usb.ko.xz" \
	|| v101_missing="$v101_missing ath6kl_usb"
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/rsi/rsi_usb.ko.xz" \
	|| v101_missing="$v101_missing rsi_usb"
if [ -z "$v101_missing" ]; then
	pass "in-kernel WiFi: rtl8192du + ath6kl_usb + rsi_usb .ko.xz present (v10.1)"
else
	fail "in-kernel WiFi: rtl8192du + ath6kl_usb + rsi_usb .ko.xz present (v10.1)" \
		"missing:$v101_missing -- a CONFIG_ symbol was dropped, or the module tree is stale"
fi

# The SDIO bus drivers for the three vendors whose USB driver we build are all
# `default y`/`default m` under CONFIG_MMC=y, so each needs an explicit `is not
# set` in linux.config or olddefconfig silently builds a second bus driver for a
# slot this board does not have. Assert they stayed out of the image -- this is
# the check that catches a linux.config edit dropping those lines.
sdio_present=""
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac-sdio.ko.xz" \
	&& sdio_present="$sdio_present brcmfmac-sdio"
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/ath/ath6kl/ath6kl_sdio.ko.xz" \
	&& sdio_present="$sdio_present ath6kl_sdio"
tar_has "usr/lib/modules/$KVER/kernel/drivers/net/wireless/rsi/rsi_sdio.ko.xz" \
	&& sdio_present="$sdio_present rsi_sdio"
if [ -z "$sdio_present" ]; then
	pass "SDIO WiFi bus drivers absent (no SDIO WiFi slot on DE10-Nano, v10/v10.1)"
else
	fail "SDIO WiFi bus drivers absent (no SDIO WiFi slot on DE10-Nano, v10/v10.1)" \
		"present:$sdio_present -- a '# CONFIG_*_SDIO is not set' line was dropped from linux.config"
fi

xow_size=$(tar_size "usr/lib/firmware/xow_dongle.bin")
if [ "${xow_size:-0}" -eq 70620 ] 2>/dev/null; then
	pass "xow_dongle.bin present, 70620 bytes"
else
	fail "xow_dongle.bin present, 70620 bytes" "got size='${xow_size:-<missing>}'"
fi

xone_02e6_size=$(tar_size "usr/lib/firmware/xone_dongle_02e6.bin")
if [ "${xone_02e6_size:-0}" -eq 70008 ] 2>/dev/null; then
	pass "xone_dongle_02e6.bin present, 70008 bytes"
else
	fail "xone_dongle_02e6.bin present, 70008 bytes" "got size='${xone_02e6_size:-<missing>}'"
fi

# =============================================================================
section "P3.4 — WiFi userland"
# =============================================================================

for spec in "usr/bin/bash:bash" "usr/bin/dialog:dialog" "usr/sbin/iw:iw" "usr/sbin/ip:ip" "usr/sbin/iwconfig:iwconfig"; do
	path="${spec%%:*}"; label="${spec##*:}"
	if tar_has "$path"; then
		pass "$label present ($path)"
	else
		fail "$label present ($path)" "not in rootfs.tar"
	fi
done

if tar_has "usr/sbin/iwlist"; then
	pass "iwlist present (symlink to iwconfig)"
else
	fail "iwlist present (symlink to iwconfig)" "not in rootfs.tar"
fi
if tar_has "usr/sbin/iwgetid"; then
	pass "iwgetid present (symlink to iwconfig)"
else
	fail "iwgetid present (symlink to iwconfig)" "not in rootfs.tar"
fi

# =============================================================================
section "T2 — WiFi hotplug (70-persistent-net.rules, docs/wifi-parity.md §9)"
# =============================================================================
# Closes docs/stock-reconciliation.md §3c's former "top follow-up": a WiFi
# dongle plugged in after boot must come up without a reboot. The rule
# deliberately does NOT match stock's literal text (no NAME="wlan0", RUN+=
# targets %k via an async helper instead of a blocking `ifup -a`) -- see the
# rule file's own header comment and docs/wifi-parity.md §9 for the verified
# reasoning. These checks assert the artifact ships correctly AND that the
# two deliberate divergences have not silently been "corrected" back toward
# stock's text (which would regress two-adapter support -- see §9).

HOTPLUG_RULE="etc/udev/rules.d/70-persistent-net.rules"
HOTPLUG_SCRIPT="etc/wifi-hotplug.sh"

require_present "$HOTPLUG_RULE" "70-persistent-net.rules"
require_present "$HOTPLUG_SCRIPT" "wifi-hotplug.sh"

if tar_has "$HOTPLUG_SCRIPT"; then
	mode=$(tar tvf "$ROOTFS_TAR" -- "./$HOTPLUG_SCRIPT" 2>/dev/null | awk '{print $1; exit}')
	case "$mode" in
	-rwx*|-r-x*) pass "wifi-hotplug.sh executable ($mode)" ;;
	*) fail "wifi-hotplug.sh executable" "mode is '$mode', not executable -- RUN+= execs it directly, udev does not go through a shell" ;;
	esac
else
	skip "wifi-hotplug.sh executable" "$HOTPLUG_SCRIPT missing (see above)"
fi

# The rule file's mode is asserted exactly, unlike the script's (which only
# has to be executable): udev must be able to READ it, and nothing should ever
# execute it. 644 is also what docs/wifi-parity.md §9 "What ships" promises,
# and an unasserted documented mode is how that promise silently rots.
if tar_has "$HOTPLUG_RULE"; then
	mode=$(tar tvf "$ROOTFS_TAR" -- "./$HOTPLUG_RULE" 2>/dev/null | awk '{print $1; exit}')
	case "$mode" in
	-rw-r--r--) pass "70-persistent-net.rules mode 644 ($mode)" ;;
	*) fail "70-persistent-net.rules mode 644" "mode is '$mode', expected '-rw-r--r--' -- see docs/wifi-parity.md §9" ;;
	esac
else
	skip "70-persistent-net.rules mode 644" "$HOTPLUG_RULE missing (see above)"
fi

if tar_has "$HOTPLUG_RULE"; then
	# Comments stripped before any of the content checks below: the file's own
	# header comment QUOTES stock's original rule verbatim (NAME="wlan0" and
	# all) as part of explaining the divergence, which would otherwise false-
	# positive the very regression guard this section exists to run. Only the
	# active, uncommented directive lines are what actually ships as behavior.
	rule_content="$WORKDIR/70-persistent-net.rules"
	tar xOf "$ROOTFS_TAR" "./$HOTPLUG_RULE" 2>/dev/null | grep -v '^#' > "$rule_content"

	if grep -q 'KERNEL=="wlan\*"' "$rule_content"; then
		pass "70-persistent-net.rules matches KERNEL==\"wlan*\""
	else
		fail "70-persistent-net.rules matches KERNEL==\"wlan*\"" "no such match in the shipped rule"
	fi

	if grep -q 'RUN+="/etc/wifi-hotplug.sh up %k"' "$rule_content" \
		&& grep -q 'RUN+="/etc/wifi-hotplug.sh down %k"' "$rule_content"; then
		pass "70-persistent-net.rules RUN+= dispatches to wifi-hotplug.sh, targeted by %k"
	else
		fail "70-persistent-net.rules RUN+= dispatches to wifi-hotplug.sh, targeted by %k" \
			"expected both 'RUN+=\"/etc/wifi-hotplug.sh up %k\"' and '... down %k' -- see $rule_content"
	fi

	# Regression guard: NAME="wlan0" would break this image's two-adapter
	# support (auto wlan0 AND auto wlan1 in /etc/network/interfaces since
	# P2.3) -- see the rule file's own comment and docs/wifi-parity.md §9,
	# divergence 1, for why this is a deliberate, verified omission, not an
	# oversight to "fix" back toward stock's literal text.
	if grep -q 'NAME="wlan0"' "$rule_content"; then
		fail "70-persistent-net.rules has NOT reintroduced NAME=\"wlan0\"" \
			"found NAME=\"wlan0\" in the shipped rule -- this collapses wlan0/wlan1 to one name and breaks two-adapter support; see docs/wifi-parity.md §9"
	else
		pass "70-persistent-net.rules has NOT reintroduced stock's NAME=\"wlan0\" (two-adapter support preserved)"
	fi
else
	skip "70-persistent-net.rules content checks (KERNEL match, RUN+= target, NAME= regression guard)" "$HOTPLUG_RULE missing (see above)"
fi

# =============================================================================
section "T3 — addon.tar §3c closure (helpers, console/UX config, mc)"
# =============================================================================
# docs/stock-reconciliation.md §3c. The seven stock helper scripts are vendored
# BYTE-IDENTICAL from addon.tar (verified against work/imgroot at vendoring
# time); these checks pin presence, mode, and one content marker each -- the
# marker is the line whose absence would mean the file was quietly replaced
# with something other than the stock script (or that a "cleanup" broke the
# documented mechanism).

# -- executable helpers: path, +x, and a stock content marker ----------------
# name:marker  (marker chosen from the script's load-bearing line)
for spec in \
	"usr/bin/vhd_mount:losetup /dev/loop1" \
	"usr/bin/m3u_play:mpg123 -@" \
	"usr/bin/timidity:MC_EXT_SELECTED" \
	"usr/sbin/vmode:/dev/MiSTer_cmd" \
	"usr/sbin/uartmode:midilink MENU QUIET" \
	"usr/sbin/btpair:btctl pair" \
	"usr/sbin/btctl:org.bluez" \
	"etc/jms583-phantom-guard.sh:152d" \
	; do
	f="${spec%%:*}"; marker="${spec#*:}"
	if ! tar_has "$f"; then
		fail "§3c helper $f present+executable+stock-marker" "$f not in rootfs.tar"
		continue
	fi
	mode=$(tar tvf "$ROOTFS_TAR" -- "./$f" 2>/dev/null | awk '{print $1; exit}')
	case "$mode" in
	-rwx*) : ;;
	*) fail "§3c helper $f present+executable+stock-marker" "mode is '$mode', not executable"; continue ;;
	esac
	if tar xOf "$ROOTFS_TAR" "./$f" 2>/dev/null | grep -qF "$marker"; then
		pass "§3c helper $f present+executable+stock-marker"
	else
		fail "§3c helper $f present+executable+stock-marker" "marker '$marker' not found -- file is not the vendored stock script"
	fi
done

# btctl must actually RUN on this image: it needs dbus-python + PyGObject
# (BR2_PACKAGE_DBUS_PYTHON / BR2_PACKAGE_PYTHON_GOBJECT -- the same bindings
# stock ships for its python3.9). Presence in the tar first, then a real
# import + a compile of the shipped script under qemu.
#
# MATCH .pyc, NOT .py. This defconfig sets BR2_PACKAGE_PYTHON3_PYC_ONLY=y, so
# target-finalize BYTE-COMPILES every module and DELETES the .py source --
# `site-packages/dbus/__init__.py` does not exist on this target and never
# will, while `__init__.pyc` does. An earlier revision asserted the .py and
# failed against a perfectly good build, with a message blaming a missing
# BR2_PACKAGE_* symbol that was in fact set. Both spellings are accepted below
# so the check keeps working if PYC_ONLY is ever turned off.
for sitepkg in "dbus:dbus-python" "gi:PyGObject (gi)"; do
	sitepkg_dir=${sitepkg%%:*}
	sitepkg_label=${sitepkg#*:}
	if grep -qE "^\./usr/lib/python3\.[0-9]+/site-packages/$sitepkg_dir/__init__\.pyc?$" "$TAR_LIST"; then
		pass "$sitepkg_label in site-packages (btctl runtime)"
	else
		fail "$sitepkg_label in site-packages (btctl runtime)" \
			"no site-packages/$sitepkg_dir/__init__.py[c] in rootfs.tar -- package not installed at all (note PYC_ONLY means .pyc is the expected spelling)"
	fi
done
if [ -z "$QEMU_ARM" ]; then
	skip "btctl imports + compiles (dbus, dbus.mainloop.glib, GLib)" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/python3" ] || [ ! -f "$TARGET/usr/sbin/btctl" ]; then
	skip "btctl imports + compiles (dbus, dbus.mainloop.glib, GLib)" "target python3 or usr/sbin/btctl not present in output/target"
else
	btctl_out="$WORKDIR/btctl-imports.out"
	# cfile= is MANDATORY here, not tidiness. py_compile.compile() with no
	# cfile writes to importlib.util.cache_from_source(file) -- for an
	# extension-less script that is
	# $TARGET/usr/sbin/__pycache__/btctlcpython-314.pyc (no dot: rpartition
	# ('.') finds none, so the stem and the cache tag concatenate). qemu_target
	# is `qemu-arm -L $TARGET ...`; -L only redirects the ELF loader, so the
	# path argument is a plain HOST path and that write really lands in
	# output/target. Buildroot never wipes output/target between builds, so the
	# next `make all` would tar a host-generated .pyc into rootfs.tar -- an
	# unasserted binary in the image (G6), and dead weight besides (btctl is
	# executed as a script, its __pycache__ is never consulted). A verification
	# script must not mutate the tree it verifies: send it to $WORKDIR, which
	# cleanup() rm -rf's on EXIT.
	if qemu_target "$TARGET/usr/bin/python3" -c \
		"import dbus, dbus.service, dbus.mainloop.glib; from gi.repository import GLib; import py_compile; py_compile.compile('$TARGET/usr/sbin/btctl', cfile='$WORKDIR/btctl.pyc', doraise=True)" \
		>"$btctl_out" 2>&1; then
		pass "btctl imports + compiles under target python (via qemu-arm)"
	else
		fail "btctl imports + compiles under target python" "$(tail -3 "$btctl_out" | tr '\n' ' ')"
	fi
fi
# No host-generated bytecode anywhere in the image. This is a real leak path,
# not paranoia: .gitignore:9 hides __pycache__/ from `git status`, but the
# rootfs overlay is copied by rsync, not by git -- SYSTEM_RSYNC
# (work/buildroot/system/system.mk:64-68) passes only RSYNC_VCS_EXCLUSIONS
# (work/buildroot/Makefile:642-644: .svn/.git/.hg/.bzr/CVS) plus --exclude
# .empty --exclude '*~'. __pycache__ is on neither list, so a stray py_compile
# run inside board/.../rootfs-overlay/ (or, before the cfile= fix above, inside
# output/target/) ships an invisible, unreviewed binary blob to the target. Both
# routes were live and both are now closed; this asserts they stay closed.
# Scoped to /usr/sbin is NOT enough -- match anywhere except python's own
# /usr/lib/python3.N tree, which legitimately ships precompiled bytecode
# (BR2_PACKAGE_PYTHON3_PYC_ONLY / _PY_PYC, work/buildroot/package/python3/
# Config.in:32,35). Today that tree holds the ONLY __pycache__ in the image
# (site-packages/libmount/), verified against output/images/rootfs.tar.
stray_pyc=$(grep -E '/__pycache__/' "$TAR_LIST" | grep -vE '^\./usr/lib/python3\.[0-9]+/' || true)
if [ -z "$stray_pyc" ]; then
	pass "no stray __pycache__ outside python3's stdlib"
else
	fail "no stray __pycache__ outside python3's stdlib" "host bytecode in image: $(echo "$stray_pyc" | tr '\n' ' ')"
fi

# -- fluidsynth path difference, resolved both ways --------------------------
# Stock has /usr/sbin/fluidsynth (real ELF); the fluidsynth package installs
# /usr/bin/fluidsynth. No shipped caller uses the absolute stock path
# (midilink: PATH `fluidsynth`; timidity wrapper: PATH; uartmode: killall by
# name; Main_MiSTer: no fluidsynth reference at all -- all verified), but
# third-party user scripts may hardcode stock's path, so a compat symlink
# closes the difference outright.
require_present "usr/bin/fluidsynth" "fluidsynth binary (package path)"
if tar_has "usr/sbin/fluidsynth"; then
	fs_link=$(tar tvf "$ROOTFS_TAR" -- "./usr/sbin/fluidsynth" 2>/dev/null | awk '{print $NF; exit}')
	if [ "$fs_link" = "/usr/bin/fluidsynth" ]; then
		pass "usr/sbin/fluidsynth compat symlink -> /usr/bin/fluidsynth (stock path resolves)"
	else
		fail "usr/sbin/fluidsynth compat symlink" "points at '$fs_link', expected /usr/bin/fluidsynth"
	fi
else
	fail "usr/sbin/fluidsynth compat symlink" "not in rootfs.tar -- stock's absolute path would dangle"
fi

# -- console/audio config ----------------------------------------------------
# asound.conf routes the ALSA default pcm into /dev/MrAudio (the in-kernel
# MiSTer SPI audio ring, CONFIG_SND_MISTER_AUDIO=y creates the device node --
# sound/drivers/MiSTer-audio-spi.c) so mpg123/aplay/fluidsynth are audible
# through the core's HDMI/analog output.
#
# NOT because hw:0 is missing -- hw:0 exists and MUST exist. MiSTer-audio-spi
# is a chardev SPI driver, not an ALSA driver (no card, no PCM), so the only
# ALSA card on this board is the patched snd-dummy: CONFIG_SND_DUMMY=y
# (board/mister/de10nano/linux.config:391, built in, enable[0]=1 at
# sound/drivers/dummy.c:51) registers it as card 0, and asound.conf's own
# innermost slave is literally `type hw; card 0` -- the `type file` plugin
# DUPLICATES the stream, so card 0 must accept S16_LE/48000/2ch or the whole
# default pcm fails to open (docs/abi-contract.md sec 8.2(a), 8.2(c)).
# The real failure mode WITHOUT this file: ALSA's default resolves to that
# dummy card, snd-dummy discards the samples and the system is silently mute
# (docs/phase0-review.md:128, "omit it and the system is silent").
if tar_has "etc/asound.conf" && tar xOf "$ROOTFS_TAR" ./etc/asound.conf 2>/dev/null | grep -qF '/dev/MrAudio'; then
	pass "etc/asound.conf present, targets /dev/MrAudio"
else
	fail "etc/asound.conf present, targets /dev/MrAudio" "missing, or no /dev/MrAudio route"
fi
# kbd.map blanks VC keycodes 88/113/114/115 (F12/Mute/Vol-/Vol+) -- the keys
# Main_MiSTer consumes via evdev; loading it stops the framebuffer console
# double-acting on them. Loaded by the guarded inittab line iff kbd's loadkeys
# ships (T5); the map itself is stock-identical and harmless alone.
if tar_has "etc/kbd.map" && tar xOf "$ROOTFS_TAR" ./etc/kbd.map 2>/dev/null | grep -qF 'keycode 88 ='; then
	pass "etc/kbd.map present, blanks keycode 88 (F12)"
else
	fail "etc/kbd.map present, blanks keycode 88 (F12)" "missing, or not the stock map"
fi
if tar xOf "$ROOTFS_TAR" ./etc/inittab 2>/dev/null | grep -qF '/usr/bin/loadkeys /etc/kbd.map'; then
	pass "inittab loads kbd.map (guarded loadkeys line)"
else
	fail "inittab loads kbd.map (guarded loadkeys line)" "no loadkeys line in etc/inittab"
fi

# -- JMS583 phantom-LUN guard ------------------------------------------------
JMS_RULE="etc/udev/rules.d/60-jms583-phantom.rules"
if tar_has "$JMS_RULE" && tar xOf "$ROOTFS_TAR" "./$JMS_RULE" 2>/dev/null \
	| grep -qF 'ATTRS{idVendor}=="152d", ATTRS{idProduct}=="0583"'; then
	pass "60-jms583-phantom.rules present, matches JMS583 (152d:0583)"
else
	fail "60-jms583-phantom.rules present, matches JMS583 (152d:0583)" "missing or wrong match"
fi

# -- vhd_mount's mount point -------------------------------------------------
# vhd_mount mounts /dev/loop1p1 on /media/rootfs; "/" is read-only at runtime,
# so the directory must ship in the image (same .gitkeep idiom as /media/fat).
if grep -qE '^\./media/rootfs/$' "$TAR_LIST"; then
	pass "/media/rootfs mount point ships in the image"
else
	fail "/media/rootfs mount point ships in the image" "vhd_mount has nowhere to mount on the read-only root"
fi

# -- mc (file manager + the MiSTer launcher wiring) --------------------------
require_present "usr/bin/mc" "mc binary"
require_present "usr/bin/memtool" "memtool (pengutronix, stock's usr/bin/memtool)"
# addon.tar's argv[0]/alias symlinks (memtool.c:475 dispatches on basename;
# `play` is what mc's stock sound.sh execs for au/voc/snd). Targets must not
# dangle: memtool from the package above, aplay from alsa-utils.
for spec in "usr/bin/md:memtool" "usr/bin/mw:memtool" "usr/bin/play:aplay"; do
	f="${spec%%:*}"; want="${spec#*:}"
	if ! tar_has "$f"; then
		fail "$f symlink -> $want" "not in rootfs.tar"
		continue
	fi
	got=$(tar tvf "$ROOTFS_TAR" -- "./$f" 2>/dev/null | awk '{print $NF; exit}')
	if [ "$got" = "$want" ]; then
		pass "$f symlink -> $want"
	else
		fail "$f symlink -> $want" "points at '$got'"
	fi
done
require_present "usr/share/mc/skins/MiSTer.ini" "mc MiSTer skin"
if tar_has "root/.config/mc/ini" && tar xOf "$ROOTFS_TAR" ./root/.config/mc/ini 2>/dev/null | grep -qx 'skin=MiSTer'; then
	pass "root mc config selects the MiSTer skin"
else
	fail "root mc config selects the MiSTer skin" "root/.config/mc/ini missing or no skin=MiSTer line"
fi
if tar_has "etc/mc/mc.ext.ini"; then
	mcext="$WORKDIR/mc.ext.ini"
	tar xOf "$ROOTFS_TAR" ./etc/mc/mc.ext.ini > "$mcext" 2>/dev/null
	mc_missing=""
	grep -qx '\[mc.ext.ini\]' "$mcext" || mc_missing="$mc_missing [mc.ext.ini]-version-group"
	grep -qx 'Open=echo load_core %d/%p >/dev/MiSTer_cmd' "$mcext" || mc_missing="$mc_missing rbf-load_core"
	grep -qx 'Open=vhd_mount %d/%p' "$mcext" || mc_missing="$mc_missing vhd_mount"
	grep -qx 'Open=m3u_play %f' "$mcext" || mc_missing="$mc_missing m3u_play"
	grep -qx 'Open=aplay %s' "$mcext" || mc_missing="$mc_missing wav-aplay"
	if [ -z "$mc_missing" ]; then
		pass "mc.ext.ini: version group + all 4 MiSTer handlers (rbf/vhd/m3u/wav)"
	else
		fail "mc.ext.ini: version group + all 4 MiSTer handlers" "missing:$mc_missing"
	fi
else
	fail "mc.ext.ini: version group + all 4 MiSTer handlers" "etc/mc/mc.ext.ini not in rootfs.tar"
fi
# [core] must carry BOTH patterns. Stock ADDED `extensions=rbf` to upstream's
# group; it did NOT trade away the Unix-coredump `regexp` (stock's own copy,
# work/imgroot/etc/mc/filehighlight.ini:22-25, has all three keys). mc appends
# `regexp` and `extensions` as two independent filters on one group
# (mc-4.8.33 lib/filehighlight/ini-file-read.c:251,:256), so both coexist.
# Asserting the regexp too pins the file to exactly two deltas vs the 4.8.33
# package default ([core] +rbf, [media] +vgm;vgz) -- an earlier draft silently
# dropped it, which was a third, undocumented divergence from stock.
if ! tar_has "etc/mc/filehighlight.ini"; then
	fail "filehighlight.ini: .rbf cores + upstream coredump regexp" "etc/mc/filehighlight.ini not in rootfs.tar"
else
	fh="$WORKDIR/filehighlight.ini"
	tar xOf "$ROOTFS_TAR" ./etc/mc/filehighlight.ini > "$fh" 2>/dev/null
	fh_missing=""
	grep -qE '^[[:space:]]*extensions=rbf$'          "$fh" || fh_missing="$fh_missing rbf-extensions"
	grep -qF 'regexp=^core\\.*\\d*$'                 "$fh" || fh_missing="$fh_missing coredump-regexp"
	if [ -z "$fh_missing" ]; then
		pass "filehighlight.ini: .rbf cores + upstream coredump regexp"
	else
		fail "filehighlight.ini: .rbf cores + upstream coredump regexp" "missing:$fh_missing"
	fi
fi

# -- var/lib/bluetooth (stock's addon 'placeholder' file, closed structurally)
# Stock kept the dir alive in its tar with a placeholder file; here bluez
# 5.79's own install ships the directory (Makefile.am:36, install -dm700) and
# /usr/bin/bluetoothd mounts the persistent ext4 image over it (S45bluetooth).
# mkdir -p on the read-only root would fail, so the dir MUST be in the image.
if grep -qE '^\./var/lib/bluetooth/$' "$TAR_LIST"; then
	pass "/var/lib/bluetooth ships in the image (BT persistence mount point)"
else
	fail "/var/lib/bluetooth ships in the image" "bluetoothd's mount point is missing on a read-only root"
fi

# =============================================================================
section "T5 — utility binaries closing the stock gap (docs/package-manifest.md §4c)"
# =============================================================================
# Highest-value binaries from each of the three T5 groups, plus regression
# guards for the BusyBox-applet collisions T5 found and fixed (board/mister/
# de10nano/busybox.fragment): a collision that "resolves" back to the BusyBox
# stub -- e.g. because a future edit re-enables the applet without noticing
# the real package already owns that path -- would be silent at build time
# (last install just wins) and only show up as a user running a crippled
# lsof/lsusb/mkdosfs/chvt/openvt at runtime. Presence alone does not catch
# that, so these checks additionally assert the shipped entry is NOT a
# busybox symlink where a real package is supposed to own the path.

# -- Group 1: BusyBox applets stock ships as GNU coreutils --------------------
# `stat`/`timeout` matter most (task's own words) -- ordinary shell scripts
# use both, and a MiSTer script that works on stock previously failed
# outright on this image. Presence AND their sub-feature-gated flags (found
# pinned off in the base busybox.config -- board/mister/de10nano/
# busybox.fragment's own T5 comment) are both checked, since presence alone
# would not have caught a crippled `stat` with no `-c` support.
require_present "usr/bin/stat" "stat"
require_present "usr/bin/timeout" "timeout"
if [ -z "$QEMU_ARM" ]; then
	skip "stat -c (FEATURE_STAT_FORMAT) works" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/stat" ]; then
	skip "stat -c (FEATURE_STAT_FORMAT) works" "$TARGET/usr/bin/stat not present in output/target"
elif qemu_target "$TARGET/usr/bin/stat" -c '%s' "$TARGET/usr/bin/stat" >/dev/null 2>&1; then
	pass "stat -c (FEATURE_STAT_FORMAT) works"
else
	fail "stat -c (FEATURE_STAT_FORMAT) works" "stat -c '%s' failed -- FEATURE_STAT_FORMAT may not be compiled in"
fi
for spec in "usr/bin/tac:tac" "usr/bin/shuf:shuf" "usr/bin/comm:comm" "usr/bin/split:split" "usr/bin/expand:expand" "usr/bin/groups:groups" "usr/bin/nc:nc"; do
	path="${spec%%:*}"; label="${spec##*:}"
	require_present "$path" "$label"
done
# Stock ships TWO names for netcat -- usr/bin/netcat (a real GNU Netcat 0.7.1
# ELF) and usr/bin/nc -> netcat beside it. BusyBox provides the second name
# only through its own separate alias applet (CONFIG_NETCAT, default n
# upstream: networking/nc.c:17-21), so this guards the easy-to-lose half of
# that pair -- CONFIG_NC=y alone satisfies the `nc` check above while leaving
# `netcat` a command-not-found. Substitution, not reproduction: our provider is
# BusyBox's nc, not GNU Netcat -- see board/mister/de10nano/busybox.fragment.
require_present "usr/bin/netcat" "netcat (BusyBox CONFIG_NETCAT alias -- stock's second name for the same command)"

# -- Group 2: wpa_supplicant CLI sub-options -----------------------------------
# Highest value-per-byte item in T5 and squarely WiFi work (P3.4/docs/wifi-
# parity.md territory) -- both are sub-options of the wpa_supplicant package
# already built for this image, not a new package.
require_present "usr/sbin/wpa_cli" "wpa_cli"
require_present "usr/sbin/wpa_passphrase" "wpa_passphrase"

# -- Group 3: the highest-value packages, one binary each ---------------------
# On a games console, joystick calibration/force-feedback tooling
# (linuxconsoletools) is arguably the single most valuable item in the whole
# T5 pass; 7-Zip is the highest-priority archival tool (MiSTer release
# archives are .7z -- without this, on-device extraction was impossible);
# dosfstools/exfatprogs are what a USB stick actually gets reformatted with.
require_present "usr/bin/jstest" "jstest (linuxconsoletools joystick calibration)"
require_present "usr/bin/fftest" "fftest (linuxconsoletools force-feedback test)"
require_present "usr/sbin/fsck.vfat" "fsck.vfat (dosfstools compat symlink)"
require_present "usr/sbin/mkfs.vfat" "mkfs.vfat (dosfstools compat symlink)"
require_present "usr/sbin/fatlabel" "fatlabel (dosfstools)"
require_present "usr/sbin/mkfs.exfat" "mkfs.exfat (exfatprogs)"
require_present "usr/sbin/fsck.exfat" "fsck.exfat (exfatprogs)"
# 7z support: upstream 7-Zip (package/7zip), NOT p7zip -- ADR 0023. Three
# things get asserted because three different mistakes are possible here.
require_present "usr/bin/7zz" "7zz (7-Zip 26.02, upstream -- replaced p7zip)"
# (1) BOTH aliases must resolve to 7zz, and each must be a SYMLINK. `7za` is
# the name a decade of community scripts reach for (every MiSTer that has ever
# updated has a /media/fat/linux/7za). `7zr` is subtler and matters more: it is
# the ONLY 7-Zip name stock's rootfs provides, so it is what a script written
# against stock calls. A broken alias is invisible until one of them runs.
#
# Requiring a symlink is what makes this double as the p7zip-regression guard.
# Buildroot never un-installs, so a target tree built before the swap keeps
# p7zip's REAL usr/bin/7zr ELF, and the image would then ship two different 7z
# implementations of two different vintages -- silent, because both "work". A
# bare presence check cannot tell those apart; "is a symlink to 7zz" can.
for sevenzip_alias in 7za 7zr; do
	if ! tar_has "usr/bin/$sevenzip_alias"; then
		fail "usr/bin/$sevenzip_alias alias -> 7zz present" "usr/bin/$sevenzip_alias not in rootfs.tar"
		continue
	fi
	sevenzip_entry=$(tar tvf "$ROOTFS_TAR" -- "./usr/bin/$sevenzip_alias" 2>/dev/null | head -1)
	sevenzip_link=${sevenzip_entry##*-> }
	case "$sevenzip_entry" in
	*'-> '*)
		if [ "$sevenzip_link" = "7zz" ]; then
			pass "usr/bin/$sevenzip_alias is a symlink -> 7zz"
		else
			fail "usr/bin/$sevenzip_alias symlink -> 7zz" "points at '$sevenzip_link', expected 7zz"
		fi ;;
	*)
		fail "usr/bin/$sevenzip_alias is a symlink -> 7zz" \
			"it is a REAL FILE, not a symlink -- almost certainly p7zip's own binary left behind by a pre-ADR-0023 target tree; run 'make p7zip-dirclean' and delete it ($sevenzip_entry)" ;;
	esac
done

# -- The payload 7za: output/images/7za, NOT a rootfs file --------------------
# This is the one that ends up at /media/fat/linux/7za on the persistent exFAT
# partition, via release.yml's files/linux/ payload and mk-sdcard.sh's
# mister-payload/linux/. Its absence silently restores the old behaviour --
# the Downloader fetching p7zip 16.02 (2016) off the internet -- so it is
# checked here rather than only in the release job.
if [ ! -f "$IMAGES/7za" ]; then
	fail "output/images/7za present (payload 7-Zip for /media/fat/linux/7za)" \
		"$IMAGES/7za missing -- package/7zip's INSTALL_IMAGES step did not run"
else
	# STATIC is a requirement, not an optimization: this binary outlives the
	# rootfs that installed it (u-boot.txt _vN rollback, a rollback to a stock
	# image on glibc ~2.32, or a stock user's Downloader run after having once
	# installed our release). Dynamically linked, it dies at exec with
	# GLIBC_2.xx-not-found and the Linux update fails at its first `7za t`.
	# Checked structurally (no INTERP segment, no NEEDED entries) rather than
	# by parsing `file`, which words this differently across versions.
	payload_interp=$(readelf -l "$IMAGES/7za" 2>/dev/null | grep -c INTERP || true)
	payload_needed=$(readelf -d "$IMAGES/7za" 2>/dev/null | grep -c NEEDED || true)
	payload_arch=$(readelf -h "$IMAGES/7za" 2>/dev/null | awk -F: '/Machine:/{print $2}' | tr -d ' ')
	if [ "$payload_interp" = "0" ] && [ "$payload_needed" = "0" ]; then
		pass "output/images/7za is statically linked (survives a rootfs rollback)"
	else
		fail "output/images/7za is statically linked" \
			"INTERP segments=$payload_interp, NEEDED entries=$payload_needed (both must be 0)"
	fi
	if [ "$payload_arch" = "ARM" ]; then
		pass "output/images/7za is a target-ARM ELF (Machine: ARM)"
	else
		fail "output/images/7za is a target-ARM ELF" "Machine reads '$payload_arch', expected ARM"
	fi

	# The behavioural contract, run against the real artifact: the EXACT command
	# pair linux_updater.py issues -- `7za t <archive>` then
	# `7za x -y <archive> files/linux/* -o<dir>`. The wildcard is the subtle
	# part: the on-device shell leaves `files/linux/*` unexpanded (no such dir
	# in its cwd) and passes it through literally, so 7-Zip's OWN pattern
	# matching decides what comes out. A regression there would extract the
	# whole archive -- including files/MiSTer, which the Downloader must never
	# overwrite -- and no exit code would reveal it. Self-round-trip, so no
	# host 7z is needed; cross-version compat against the pinned 2016 binary is
	# release.yml's qemu-arm step (docs/downloader-contract.md §4).
	if [ -z "$QEMU_ARM" ]; then
		skip "payload 7za runs the Downloader's t + x command pair" "qemu-arm not found on PATH"
	else
		sevenzip_work="$WORKDIR/7za-roundtrip"
		mkdir -p "$sevenzip_work/stage/files/linux" "$sevenzip_work/out"
		echo payload > "$sevenzip_work/stage/files/linux/linux.img"
		echo payload > "$sevenzip_work/stage/files/linux/zImage_dtb"
		echo decoy   > "$sevenzip_work/stage/files/MiSTer"
		# Read the whole banner block, not one line: 7-Zip's first stdout line
		# is EMPTY (the version is on line 2), and p7zip's giveaway "p7zip
		# Version ..." line is its line 2 -- so any single-line read is wrong
		# for one of the two. Both binaries print this to stdout, not stderr.
		sevenzip_banner=$("$QEMU_ARM" "$IMAGES/7za" 2>/dev/null | head -4)
		sevenzip_ver=$(printf '%s\n' "$sevenzip_banner" | grep -m1 -- '7-Zip')
		case "$sevenzip_banner" in
		*p7zip*)
			fail "payload 7za is upstream 7-Zip, not p7zip" "reports: ${sevenzip_ver:-$sevenzip_banner}" ;;
		*"7-Zip"*)
			pass "payload 7za self-reports upstream 7-Zip ($sevenzip_ver)" ;;
		*)
			fail "payload 7za self-reports upstream 7-Zip" "unrecognised banner: ${sevenzip_banner:-<no output>}" ;;
		esac
		if ( cd "$sevenzip_work/stage" && "$QEMU_ARM" "$IMAGES/7za" a -mx=1 -m0=lzma2 -ms=on ../t.7z files/ ) >/dev/null 2>&1 \
			&& "$QEMU_ARM" "$IMAGES/7za" t "$sevenzip_work/t.7z" >/dev/null 2>&1 \
			&& "$QEMU_ARM" "$IMAGES/7za" x -y "$sevenzip_work/t.7z" 'files/linux/*' -o"$sevenzip_work/out" >/dev/null 2>&1
		then
			sevenzip_got=$(cd "$sevenzip_work/out" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ')
			if [ "$sevenzip_got" = "files/linux/linux.img files/linux/zImage_dtb " ]; then
				pass "payload 7za: t + x -y 'files/linux/*' extracts exactly files/linux/ (files/MiSTer untouched)"
			else
				fail "payload 7za: x -y 'files/linux/*' extracts ONLY files/linux/" \
					"got: ${sevenzip_got:-<nothing>}"
			fi
		else
			fail "payload 7za runs the Downloader's a/t/x command sequence" "one of a, t or x exited nonzero under qemu-arm"
		fi
	fi
fi
# ntfsprogs SPLITS across bindir and sbindir, and not the way the package name
# suggests -- get this backwards and the gate fails deterministically on the
# first real build (it did, in review, before this was corrected).
# ntfsprogs/Makefile.am:17 `bin_PROGRAMS = ntfsfix ntfsinfo ntfscluster ntfsls
# ntfscat ntfscmp` -> /usr/bin, while :18's `sbin_PROGRAMS = mkntfs ntfslabel
# ntfsundelete ntfsresize ntfsclone ntfscp` -> /usr/sbin, plus the
# install-exec-hook at :166-169 symlinking mkfs.ntfs -> mkntfs there.
# ntfs-3g.mk passes no --exec-prefix override (unlike dosfstools.mk:13), so
# bindir really is /usr/bin. Stock lands identically: work/imgroot has
# usr/bin/ntfsfix and usr/sbin/{mkntfs,mkfs.ntfs}, and no usr/sbin/ntfsfix.
require_present "usr/sbin/mkfs.ntfs" "mkfs.ntfs (ntfs-3g NTFSPROGS -- found missing despite BR2_PACKAGE_NTFS_3G already being on, see defconfig)"
require_present "usr/bin/ntfsfix" "ntfsfix (ntfs-3g NTFSPROGS -- /usr/bin, not /usr/sbin; see the path-split note above)"
require_present "usr/bin/dtc" "dtc (BR2_PACKAGE_DTC_PROGRAMS -- library-only before T5)"
require_present "usr/bin/loadkeys" "loadkeys (kbd -- what makes the guarded inittab line + T3's etc/kbd.map actually load)"
require_present "usr/bin/setfont" "setfont (kbd)"
require_present "usr/bin/htop" "htop"
require_present "usr/bin/tmux" "tmux"

# -- Regression guards: the BusyBox-applet collisions T5 found and fixed ------
not_busybox_symlink "usr/bin/lsof" "lsof"
not_busybox_symlink "usr/bin/lsusb" "lsusb"
not_busybox_symlink "usr/sbin/mkdosfs" "mkdosfs (dosfstools compat symlink)"
not_busybox_symlink "usr/bin/chvt" "chvt (kbd)"
not_busybox_symlink "usr/bin/openvt" "openvt (kbd)"
not_busybox_symlink "usr/bin/deallocvt" "deallocvt (kbd)"
not_busybox_symlink "usr/bin/setkeycodes" "setkeycodes (kbd)"

# =============================================================================
section "P3.5 — Bluetooth parity"
# =============================================================================

if tar_has "etc/bluetooth/main.conf"; then
	main_conf="$WORKDIR/main.conf"
	tar xOf "$ROOTFS_TAR" ./etc/bluetooth/main.conf > "$main_conf" 2>/dev/null
	bt_missing=""
	grep -qE '^Name[[:space:]]*=[[:space:]]*MiSTer[[:space:]]*$'                       "$main_conf" || bt_missing="$bt_missing Name=MiSTer"
	grep -qE '^FastConnectable[[:space:]]*=[[:space:]]*true[[:space:]]*$'               "$main_conf" || bt_missing="$bt_missing FastConnectable=true"
	grep -qE '^Privacy[[:space:]]*=[[:space:]]*off[[:space:]]*$'                        "$main_conf" || bt_missing="$bt_missing Privacy=off"
	grep -qE '^JustWorksRepairing[[:space:]]*=[[:space:]]*always[[:space:]]*$'          "$main_conf" || bt_missing="$bt_missing JustWorksRepairing=always"
	grep -qE '^AutoEnable[[:space:]]*=[[:space:]]*true[[:space:]]*$'                    "$main_conf" || bt_missing="$bt_missing AutoEnable=true"
	if [ -z "$bt_missing" ]; then
		pass "bluetooth main.conf: all 5 stock settings present"
	else
		fail "bluetooth main.conf: all 5 stock settings present" "missing/mismatched:$bt_missing"
	fi
else
	fail "bluetooth main.conf: all 5 stock settings present" "etc/bluetooth/main.conf not in rootfs.tar"
fi

# input.conf -- the HID half. Both settings are asserted with their VALUES, not
# merely "the file exists": each is also BlueZ's compiled-in default for one of
# the two, so a silently-empty or reverted file would otherwise look identical
# to a correct one on the ClassicBondedOnly side and be invisible here.
if tar_has "etc/bluetooth/input.conf"; then
	input_conf="$WORKDIR/input.conf"
	tar xOf "$ROOTFS_TAR" ./etc/bluetooth/input.conf > "$input_conf" 2>/dev/null

	# Kernel HIDP, not uhid: stock parity, keeps bluetoothd out of the
	# per-report data path, and repairs Main_MiSTer's bt_auto_disconnect
	# (input.cpp:4156 matches "bluetooth" in the sysfs path, which uhid's
	# /sys/devices/virtual/misc/uhid/... never contains).
	if grep -qE '^UserspaceHID[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$input_conf"; then
		pass "bluetooth input.conf: UserspaceHID=false (kernel HIDP)"
	else
		fail "bluetooth input.conf: UserspaceHID=false (kernel HIDP)" \
			"not set; BlueZ 5.79 defaults to uhid, which is the opposite of stock"
	fi

	# The security-relevant one. DS3/SIXAXIS support comes from the
	# CablePairing backport in board/mister/de10nano/patches/bluez5_utils/,
	# NOT from disabling this -- flipping it false would drop the encryption
	# requirement for every BR/EDR HID device (CVE-2023-45866).
	if grep -qE '^ClassicBondedOnly[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$input_conf"; then
		pass "bluetooth input.conf: ClassicBondedOnly=true (CVE-2023-45866 mitigation intact)"
	else
		fail "bluetooth input.conf: ClassicBondedOnly=true (CVE-2023-45866 mitigation intact)" \
			"not set to true -- if this was flipped to fix DS3 pairing, the supported route is the CablePairing series in board/mister/de10nano/patches/bluez5_utils/, which fixes it WITHOUT weakening every other BR/EDR HID device"
	fi
else
	fail "bluetooth input.conf present" "etc/bluetooth/input.conf not in rootfs.tar"
fi

# The CablePairing patch series actually reached the source tree. Asserted
# against the PATCHED BUILD TREE rather than the rootfs, because none of it is
# visible in a shipped file: bluetoothd's behaviour changes, its name and size
# do not. Without this, the series silently ceasing to apply (a Buildroot bump,
# a bad rebase, a deleted directory) would produce a perfectly green build in
# which a DS3 simply cannot connect over Bluetooth -- the exact regression this
# whole change exists to fix.
#
# CHOOSE THE MARKER CAREFULLY -- the obvious one is wrong. An earlier revision
# of this check grepped for BT_IO_SEC_LOW, which is VACUOUS: that string is
# already present in pristine 5.79 (profiles/input/server.c:274), and is in
# fact the very line patch 0004 replaces. The check passed identically whether
# the series had applied or not -- inverted, if anything, since it matches most
# reliably on an UNPATCHED tree.
#
# server_set_cable_pairing is introduced only by patch 0004 and appears nowhere
# in pristine 5.79 (verified against the unpatched tarball, along with
# get_necessary_sec_level, device_is_cable_pairing and
# btd_adapter_has_cable_pairing_devices -- any of the four would do).
#
# THE FAILURE THIS GUARDS IS LIVE, not hypothetical: Buildroot never revisits
# .stamp_patched, so adding patches to an ALREADY-BUILT tree is a silent no-op.
# An incremental `make all` over an output/ that predates this branch ships a
# bluetoothd with no CablePairing support and no DS3 -- looking, in every
# shipped file, exactly like a correct build. Use `make bluez5_utils-dirclean`
# after changing anything in board/mister/de10nano/patches/bluez5_utils/.
#
# Same glob-into-an-array idiom as the CONFIG_NFSD gate below -- but note a
# stale sibling build dir from a version bump is REAL here (Buildroot never
# removes the old one), so the newest directory is chosen rather than demanding
# exactly one.
bluez_dirs=()
for _d in "$BUILD_DIR"/build/bluez5_utils-[0-9]*; do
	[ -d "$_d" ] && bluez_dirs+=("$_d")
done
if [ "${#bluez_dirs[@]}" -eq 0 ]; then
	skip "bluez CablePairing series applied (DS3 over Bluetooth)" \
		"no $BUILD_DIR/build/bluez5_utils-[0-9]* directory found"
else
	# Newest by version sort, so a leftover tree from a previous pin does not
	# decide the verdict.
	bluez_newest=$(printf '%s\n' "${bluez_dirs[@]}" | sort -V | tail -1)
	if grep -q 'server_set_cable_pairing' "$bluez_newest/profiles/input/server.c" 2>/dev/null; then
		pass "bluez CablePairing series applied in $(basename "$bluez_newest") (DS3 over Bluetooth)"
	else
		fail "bluez CablePairing series applied (DS3 over Bluetooth)" \
			"server_set_cable_pairing absent from $bluez_newest/profiles/input/server.c -- board/mister/de10nano/patches/bluez5_utils/ did not apply (a stale .stamp_patched will do this silently; try 'make bluez5_utils-dirclean'), so a DS3 cannot connect"
	fi
fi

# The kernel side of UserspaceHID=false, read from the RESOLVED .config: without
# CONFIG_BT_HIDP the setting would strand BR/EDR HID entirely (bluetoothd would
# have no kernel HIDP to hand its L2CAP sockets to). linux.config is a minimal
# defconfig, so its silence on the symbol proves nothing -- same reasoning as the
# CONFIG_NFSD gate in the netfs section.
#
# Same glob-into-an-array idiom as the CONFIG_NFSD gate below, and for the same
# stated reason: an unmatched glob expands to the literal pattern, so anything
# other than exactly one match is a stale-tree condition worth reporting rather
# than globbing past.
bt_kconfigs=()
for _c in "$BUILD_DIR"/build/linux-[0-9]*/.config; do
	[ -f "$_c" ] && bt_kconfigs+=("$_c")
done
if [ "${#bt_kconfigs[@]}" -ne 1 ]; then
	skip "CONFIG_BT_HIDP enabled (required by input.conf's UserspaceHID=false)" \
		"expected exactly one $BUILD_DIR/build/linux-[0-9]*/.config, found ${#bt_kconfigs[@]}"
elif grep -qE '^CONFIG_BT_HIDP=[ym]$' "${bt_kconfigs[0]}"; then
	pass "CONFIG_BT_HIDP enabled (required by input.conf's UserspaceHID=false)"
else
	fail "CONFIG_BT_HIDP enabled (required by input.conf's UserspaceHID=false)" \
		"not set in ${bt_kconfigs[0]} -- kernel HIDP is unavailable, so UserspaceHID=false would strand BR/EDR HID entirely"
fi

# =============================================================================
section "P3.6 — Samba parity"
# =============================================================================

for spec in "usr/sbin/smbd:smbd" "usr/sbin/nmbd:nmbd"; do
	require_present "${spec%%:*}" "${spec##*:}"
done

if tar_has "etc/fstab"; then
	fstab="$WORKDIR/fstab"
	tar xOf "$ROOTFS_TAR" ./etc/fstab > "$fstab" 2>/dev/null
	if grep -qE '^tmpfs[[:space:]]+/var/cache/samba[[:space:]]+tmpfs' "$fstab"; then
		pass "/var/cache/samba tmpfs in fstab"
	else
		fail "/var/cache/samba tmpfs in fstab" "no matching fstab line"
	fi
else
	fail "/var/cache/samba tmpfs in fstab" "etc/fstab not in rootfs.tar"
fi

if [ -z "$QEMU_ARM" ]; then
	skip "testparm -s parses smb.conf clean" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/testparm" ] || [ ! -f "$TARGET/etc/samba/smb.conf" ]; then
	skip "testparm -s parses smb.conf clean" "output/target/usr/bin/testparm or /etc/samba/smb.conf not present (build target tree incomplete) -- config file presence still checked above"
else
	tp_out="$WORKDIR/testparm.out"
	qemu_target "$TARGET/usr/bin/testparm" -s "$TARGET/etc/samba/smb.conf" >"$tp_out" 2>&1
	sed 's/^/  /' "$tp_out"
	# testparm exits nonzero here purely because /var/lib/samba, /var/cache/samba,
	# etc. don't pre-exist as real directories in the static build tree -- they're
	# tmpfs mounts created at boot (S91smb, fstab), same pattern as every other
	# read-only-root writable-state path in this project (ADR 0011). Confirmed by
	# hand: pointing testparm's lock/state/cache/pid dirs at real tmp dirs makes
	# the SAME config parse with rc=0. So "parses clean" here means the actual
	# syntax-parse signal ("Loaded services file OK."), not the process exit code.
	if grep -q 'Loaded services file OK' "$tp_out" && ! grep -qi 'Unknown parameter\|syntax error' "$tp_out"; then
		pass "testparm -s parses smb.conf clean (via qemu-arm)"
	else
		fail "testparm -s parses smb.conf clean" "no 'Loaded services file OK' (or a syntax error) in output above"
	fi
fi

# =============================================================================
section "P3.7 — SSH & FTP parity"
# =============================================================================

if grep -qxF './etc/init.d/S50proftpd' "$TAR_LIST"; then
	mode=$(tar tvf "$ROOTFS_TAR" -- ./etc/init.d/S50proftpd 2>/dev/null | awk '{print $1; exit}')
	case "$mode" in
	-rwx*|-r-x*) pass "S50proftpd present and executable ($mode)" ;;
	*) fail "S50proftpd present and executable" "mode is '$mode', not executable" ;;
	esac
else
	fail "S50proftpd present and executable" "etc/init.d/S50proftpd not in rootfs.tar"
fi

require_present "etc/init.d/S50sshd" "S50sshd"

# =============================================================================
section "P3.8 — MIDI / MT-32 parity"
# =============================================================================

for spec in "usr/sbin/mt32d:mt32d" "usr/sbin/midilink:midilink" "usr/sbin/mlinkutil:mlinkutil"; do
	require_present "${spec%%:*}" "${spec##*:}"
done

if grep -qE '^\./usr/lib/libmt32emu\.so' "$TAR_LIST"; then
	pass "libmt32emu.so* present ($(grep -cE '^\./usr/lib/libmt32emu\.so' "$TAR_LIST") files)"
else
	fail "libmt32emu.so* present" "no usr/lib/libmt32emu.so* entries in rootfs.tar"
fi

alsa_midi_missing=""
for t in amidi aconnect aplaymidi arecordmidi aseqdump aseqnet; do
	tar_has "usr/bin/$t" || alsa_midi_missing="$alsa_midi_missing $t"
done
if [ -z "$alsa_midi_missing" ]; then
	pass "ALSA MIDI tools present (amidi aconnect aplaymidi arecordmidi aseqdump aseqnet)"
else
	fail "ALSA MIDI tools present" "missing:$alsa_midi_missing"
fi

# =============================================================================
section "Main_MiSTer shared libraries"
# =============================================================================
# The five libraries backing the Main_MiSTer shared-lib refactor (no task ID
# -- referenced by name): Main stops vendoring lib/{zstd,miniz,lzma,libchdr}
# and links these instead. zstd + minizip (classic) + minizip-ng come from
# upstream Buildroot (defconfig), lzma-sdk + libchdr from this tree's
# package/. See docs/main-shared-libs.md.
#
# minizip and minizip-ng are ALTERNATIVES, not a pair: Main links the classic
# libminizip.so.1 (zip.h/unzip.h API) today, while minizip-ng is staged for a
# future native mz_zip.h port. Both are asserted because both are shipped --
# and libminizip.so.1's absence is exactly the failure this section exists to
# catch ("MiSTer: error while loading shared libraries: libminizip.so.1").
#
# Version parts are WILDCARDED on purpose -- liblzma-sdk's SONAME is the FULL
# SDK version by policy (every bump is a loud ABI event, see
# package/lzma-sdk/lzma-sdk.mk), so a Renovate bump changes the filename
# itself. An exact-version assertion here would go stale and turn CI red on a
# legitimate bump -- exactly the PR #35 failure mode (commit 1341c93: the
# 8814au parity check outlived the in-kernel migration and every master build
# went red until the stale assertion was fixed).
for spec in \
	"libzstd\.so\.1:libzstd.so.1* (zstd)" \
	"libminizip\.so\.1:libminizip.so.1* (minizip, classic)" \
	"libminizip-ng\.so\.4:libminizip-ng.so.4* (minizip-ng)" \
	"liblzma-sdk\.so\.:liblzma-sdk.so.* (lzma-sdk)" \
	"libchdr\.so\.0:libchdr.so.0* (libchdr)"; do
	lib_re="^\\./usr/lib/${spec%%:*}"
	lib_name="${spec#*:}"
	if grep -qE "$lib_re" "$TAR_LIST"; then
		pass "$lib_name present ($(grep -cE "$lib_re" "$TAR_LIST") files)"
	else
		fail "$lib_name present" "no matching usr/lib entries in rootfs.tar (grep -E '$lib_re')"
	fi
done

# =============================================================================
section "P3.9 — Python & Downloader ABI gate"
# =============================================================================

PY_MODS="ssl,zlib,bz2,lzma,curses,readline,pyexpat"
if [ -z "$QEMU_ARM" ]; then
	skip "python3 imports ($PY_MODS)" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/python3" ]; then
	skip "python3 imports ($PY_MODS)" "$TARGET/usr/bin/python3 not present or not executable"
else
	py_out="$WORKDIR/python-imports.out"
	if qemu_target "$TARGET/usr/bin/python3" -c "import $PY_MODS" >"$py_out" 2>&1; then
		pass "python3 imports ($PY_MODS) all succeed (via qemu-arm)"
	else
		fail "python3 imports ($PY_MODS)" "$(cat "$py_out")"
	fi
fi

# =============================================================================
section "Wide-char ncurses (BR2_PACKAGE_NCURSES_WCHAR)"
# =============================================================================
# The ABI contract (docs/package-manifest.md, ncurses row) requires the SONAME
# libncursesw.so.6 -- the WIDE build. Plain BR2_PACKAGE_NCURSES ships the narrow
# libncurses.so.6 instead, which is invisible to a "does it link" check (the whole
# stack is then self-consistently narrow) yet:
#   - breaks any libncursesw.so.6-linked ARM binary dropped on the device -- 35
#     stock binaries DT_NEEDED that exact SONAME; and
#   - strips the wide-char curses API from Python -- the window.get_wch() method
#     and its module-level companion _curses.unget_wch -- both compiled in only
#     against ncursesw. A TUI reading the UP arrow via window.get_wch() then fails
#     and falls back to echoing ^[[A instead of navigating.
# Assert the artifact: the wide SONAME is shipped, the narrow one is not, and the
# wide API is actually present.

require_present "usr/lib/libncursesw.so.6" "libncursesw.so.6 (wide, ABI-contract SONAME)"

if tar_has "usr/lib/libncurses.so.6"; then
	fail "narrow libncurses.so.6 NOT shipped (wide-only, stock parity)" \
		"libncurses.so.6 is present -- BR2_PACKAGE_NCURSES_WCHAR is off, or something re-introduced the narrow lib. Stock ships only libncursesw.so.6."
else
	pass "narrow libncurses.so.6 absent (wide-only build, stock parity)"
fi

# Functional proof, not just a filename. The discriminator is the MODULE-LEVEL
# _curses.unget_wch: it is compiled in only when _curses is built against the wide
# lib, so it is present on ncursesw and absent on narrow ncurses (verified both
# ways on this tree). Note we do NOT test get_wch here even though get_wch() is the
# call a TUI actually uses to read the UP arrow: get_wch is a *window method*, not
# a module attribute, so probing it needs a live initscr()'d terminal, which does
# not exist under qemu-user. unget_wch is its module-level companion from the same
# --enable-widec build and is the reliable, tty-free signal for the same thing.
if [ -z "$QEMU_ARM" ]; then
	skip "python3 curses wide-char API (unget_wch)" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/python3" ]; then
	skip "python3 curses wide-char API (unget_wch)" "$TARGET/usr/bin/python3 not present"
else
	wch_out="$WORKDIR/curses-wch.out"
	if qemu_target "$TARGET/usr/bin/python3" -c \
		'import _curses; assert hasattr(_curses, "unget_wch"), "_curses has no unget_wch -> built against NARROW ncurses; window.get_wch() (arrow-key read) will not work"' \
		>"$wch_out" 2>&1; then
		pass "python3 _curses is wide-char (unget_wch present -> get_wch key reads work)"
	else
		fail "python3 _curses is wide-char (unget_wch present)" \
			"$(cat "$wch_out") -- is BR2_PACKAGE_NCURSES_WCHAR=y?"
	fi
fi

# =============================================================================
section "Locale data (BR2_GENERATE_LOCALE)"
# =============================================================================
# BR2_ENABLE_LOCALE=y only compiles locale *support* into glibc. Generating the
# locale *data* is a separate knob (BR2_GENERATE_LOCALE), and it defaulted to
# "". An image built that way has NO /usr/lib/locale at all, which is invisible
# in every other check here -- nothing fails to link, no SONAME is missing, the
# rootfs looks perfectly healthy. It only bites at runtime, because our own
# rootfs-overlay /etc/profile exports LC_ALL=en_US.UTF-8: every login shell
# printed "setlocale: LC_ALL: cannot change locale (en_US.UTF-8)", and
# update_all.sh died outright on setlocale(LC_CTYPE, "") ->
#     locale.Error: unsupported locale setting
# before doing any work. Stock's /usr/lib/locale is a single ~2.9 MB
# locale-archive (docs/stock-inventory/disk-usage.md); so is ours.
#
# Assert the artifact, not the intent -- same rule as initramfs-verify.

require_present "usr/lib/locale/locale-archive" "glibc locale-archive"

# The locale /etc/profile actually asks for must be IN that archive. A present
# but wrong-locale archive would sail past the check above.
PROFILE="$ROOT/board/mister/de10nano/rootfs-overlay/etc/profile"
PROFILE_LOCALE="$(sed -n 's/^export LC_ALL=//p' "$PROFILE" | head -1)"
if [ -z "$PROFILE_LOCALE" ]; then
	skip "profile locale is generated" "no 'export LC_ALL=' in $PROFILE"
elif [ -z "$QEMU_ARM" ]; then
	skip "profile locale ($PROFILE_LOCALE) is generated" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/python3" ]; then
	skip "profile locale ($PROFILE_LOCALE) is generated" "$TARGET/usr/bin/python3 not present"
else
	# Reproduce update_all.sh's exact failing call (update_all/main.py:16) against
	# the rootfs we just built, with the same LC_ALL /etc/profile will export.
	loc_out="$WORKDIR/locale-setlocale.out"
	# `env`, not a "LC_ALL=x qemu_target ..." prefix: a var prefix on a shell
	# *function* lands in this script's own environment, and the host bash then
	# warns "setlocale: LC_ALL: cannot change locale" if the HOST lacks the
	# locale -- noise whose text is identical to the very bug this checks for.
	if env LC_ALL="$PROFILE_LOCALE" "$QEMU_ARM" -L "$TARGET" "$TARGET/usr/bin/python3" -c \
		'import locale; locale.setlocale(locale.LC_CTYPE, "")' >"$loc_out" 2>&1; then
		pass "setlocale(LC_CTYPE, \"\") under LC_ALL=$PROFILE_LOCALE (the update_all.sh call)"
	else
		fail "setlocale(LC_CTYPE, \"\") under LC_ALL=$PROFILE_LOCALE (the update_all.sh call)" \
			"$(cat "$loc_out") -- is BR2_GENERATE_LOCALE set, and does it include $PROFILE_LOCALE?"
	fi
fi

# =============================================================================
section "Timezone (tzdata + persistent /etc/localtime + first-boot autodetect)"
# =============================================================================
# Two independent things, both of which were missing and each of which alone
# breaks the timezone:
#
#   1. tzdata itself. We shipped no /usr/share/zoneinfo at all, so no TZ= value
#      could resolve. (BR2_TARGET_TZ_INFO was simply never enabled.)
#   2. The persistence mechanism. Stock makes /etc/localtime a symlink to
#      /media/fat/linux/timezone -- a file on the FAT *data* partition. That is
#      the whole trick: the rootfs is reflashed wholesale on every update, so a
#      timezone stored anywhere inside it is lost. Buildroot's own
#      BR2_TARGET_LOCALTIME instead points /etc/localtime at
#      ../usr/share/zoneinfo/Etc/UTC, which is IN the rootfs and therefore does
#      NOT persist -- so getting (1) right while leaving Buildroot's default
#      symlink in place would still be broken, just less obviously.
#
# Hence: assert the symlink TARGET, not merely that /etc/localtime exists.

STOCK_LOCALTIME_TARGET="/media/fat/linux/timezone"

# NB: assert the *posix/* path. Top-level zoneinfo/Etc is a SYMLINK to posix/Etc
# (tzdata.mk relinks every top-level zone that way, and stock has the identical
# shape), so "usr/share/zoneinfo/Etc/UTC" resolves on a live filesystem but is
# never a tar *entry* -- tar stores the symlink, not the path through it.
require_present "usr/share/zoneinfo/posix/Etc/UTC" "tzdata (usr/share/zoneinfo)"

lt_line="$(tar tvf "$ROOTFS_TAR" 2>/dev/null | grep -E '(^|[[:space:]])\./etc/localtime( |$|[[:space:]]*->)')"
lt_target="${lt_line##*-> }"
if [ -z "$lt_line" ]; then
	fail "/etc/localtime -> $STOCK_LOCALTIME_TARGET" "no ./etc/localtime entry in rootfs.tar"
elif [ "$lt_target" = "$STOCK_LOCALTIME_TARGET" ]; then
	pass "/etc/localtime -> $STOCK_LOCALTIME_TARGET (persists across reflash, stock parity)"
else
	fail "/etc/localtime -> $STOCK_LOCALTIME_TARGET" \
		"it points at '$lt_target' instead. If that is ../usr/share/zoneinfo/..., the rootfs-overlay symlink was lost and Buildroot's BR2_TARGET_LOCALTIME default won -- the timezone will NOT survive a reflash."
fi

# tzdata is only useful if a TZ= value actually resolves against it. Prove it
# with a zone that has a non-UTC offset and DST, so a stub/empty zoneinfo can't
# accidentally pass.
if [ -z "$QEMU_ARM" ]; then
	skip "TZ=America/New_York resolves against shipped zoneinfo" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/usr/bin/python3" ]; then
	skip "TZ=America/New_York resolves against shipped zoneinfo" "$TARGET/usr/bin/python3 not present"
else
	tz_out="$WORKDIR/tz-resolve.out"
	if env TZ=America/New_York "$QEMU_ARM" -L "$TARGET" "$TARGET/usr/bin/python3" -c \
		'import time; assert time.tzname == ("EST","EDT"), time.tzname; print(time.tzname)' \
		>"$tz_out" 2>&1; then
		pass "TZ=America/New_York resolves against shipped zoneinfo -> $(cat "$tz_out")"
	else
		fail "TZ=America/New_York resolves against shipped zoneinfo" \
			"$(cat "$tz_out") -- is BR2_TARGET_TZ_INFO=y?"
	fi
fi

# --- first-boot autodetection (ADR 0025) -------------------------------------
# The two checks above prove a timezone CAN be set and CAN persist. Neither says
# anything about a fresh card, where /media/fat/linux/timezone does not exist yet
# and glibc silently falls back to UTC. The dhcpcd hook is what fills it in, the
# first time the box gets an address. Assert the hook AND dhcpcd's runner, since
# a hook nothing sources is inert.
# NB /lib is a usr-merge symlink, so tar records these only under ./usr/lib/.
require_present "usr/lib/dhcpcd/dhcpcd-hooks/90-timezone" "dhcpcd 90-timezone hook (ADR 0025)"
require_present "usr/lib/dhcpcd/dhcpcd-run-hooks" "dhcpcd hook runner (sources 90-timezone)"

# curl is what the hook queries the geo-IP provider with, and the reason this
# feature needed no new package. If it ever drops out of the package set the hook
# degrades to a silent no-op, which is exactly the kind of quiet loss this suite
# exists to catch.
require_present "usr/bin/curl" "curl CLI (the hook's only runtime dependency)"

# The behaviour itself -- validation of the network-supplied zone name, the
# once-and-only-once contract, and the two properties it has purely by virtue of
# being SOURCED into dhcpcd's shell (leaks nothing, never exits its caller) -- is
# asserted by its own sandboxed harness, which needs no build and no network.
printf -- '--- test-timezone.sh: timezone hook behaviour (16 cases) ---\n'
if "$ROOT/scripts/test-timezone.sh"; then
	pass "test-timezone.sh (timezone hook behaviour, 16 cases)"
else
	fail "test-timezone.sh (timezone hook behaviour, 16 cases)" \
		"one or more cases failed -- see output above"
fi

# ...and again under the shell that will ACTUALLY run it on the box. The host's
# /bin/sh (dash, on the CI runner) is a good POSIX proxy for BusyBox ash, but it
# is not the same interpreter, and this is a boot-path script: a construct dash
# accepts and ash does not would fail on hardware and nowhere else.
if [ -z "$QEMU_ARM" ]; then
	skip "test-timezone.sh under the target's own BusyBox ash" "qemu-arm not found on PATH"
elif [ ! -x "$TARGET/bin/busybox" ]; then
	skip "test-timezone.sh under the target's own BusyBox ash" "$TARGET/bin/busybox not present"
else
	printf -- '--- test-timezone.sh: same cases, target BusyBox ash under qemu-arm ---\n'
	if TZ_TEST_SH="$QEMU_ARM -L $TARGET $TARGET/bin/busybox sh" \
		"$ROOT/scripts/test-timezone.sh"; then
		pass "test-timezone.sh under the target's own BusyBox ash"
	else
		fail "test-timezone.sh under the target's own BusyBox ash" \
			"passes on the host shell but not on BusyBox ash -- see output above"
	fi
fi

# =============================================================================
section "P3.10 — Network filesystem client parity (NFS half per ADR 0022)"
# =============================================================================
# NB on paths: /sbin is a usr-merge symlink to usr/sbin, so tar records these
# helpers ONLY under ./usr/sbin/ -- never assert the ./sbin/ spelling, it can
# never match.

require_present "usr/sbin/mount.cifs" "mount.cifs"

# ADR 0022 REVERSED P3.10's original call. This check used to assert the exact
# opposite -- "mount.nfs ABSENT (parity, P3.10 dropped NFS client)" -- which was
# right while we shipped no NFS userland, and became the reason PR #59's build
# failed: the defconfig gained BR2_PACKAGE_NFS_UTILS=y and the gate dutifully
# reported the intended feature as a regression. Parity is a floor, not a
# ceiling (docs/netfs-parity.md); mount.nfs is now beyond-parity on purpose, so
# the assertion is inverted rather than deleted.
require_present "usr/sbin/mount.nfs"   "mount.nfs (ADR 0022, beyond parity)"
require_present "usr/sbin/mount.nfs4"  "mount.nfs4"
require_present "usr/sbin/umount.nfs"  "umount.nfs"
require_present "usr/sbin/umount.nfs4" "umount.nfs4"

# The half of ADR 0022 that is easy to lose. BR2_PACKAGE_NFS_UTILS_RPC_NFSD is
# `default y` upstream, so "client-only" survives exactly as long as our
# explicit `# ... is not set` does. Turning it back on would install these, add
# an S60nfs init script, select rpcbind -- and fire NFS_UTILS_LINUX_CONFIG_FIXUPS,
# whose KCONFIG_ENABLE_OPT flips the in-kernel NFS *server* on underneath our
# deliberate `# CONFIG_NFSD is not set`. A games console does not export
# filesystems; assert both sides of that, userland here and kernel below.
require_absent "usr/sbin/rpc.nfsd"   "rpc.nfsd (NFS server)"       "BR2_PACKAGE_NFS_UTILS_RPC_NFSD went back to its default y?"
require_absent "usr/sbin/rpc.mountd" "rpc.mountd (NFS server)"     "BR2_PACKAGE_NFS_UTILS_RPC_NFSD went back to its default y?"
require_absent "usr/sbin/exportfs"   "exportfs (NFS server)"       "BR2_PACKAGE_NFS_UTILS_RPC_NFSD went back to its default y?"
require_absent "etc/init.d/S60nfs"   "S60nfs init script"          "the NFS server init script is installed by BR2_PACKAGE_NFS_UTILS_RPC_NFSD"
require_absent "usr/sbin/rpcbind"    "rpcbind (portmapper)"        "BR2_PACKAGE_RPCBIND is selected by the NFS server; NFSv4 needs no portmapper"

# NB deliberately NOT asserted absent: rpc.statd, rpc.idmapd, nfsdcld*. All three
# are installed by a client-only nfs-utils and are inert with nothing starting
# them (ADR 0022 "Accepted limitations"). Their presence is not a server.

# The kernel side of the same invariant, read from the RESOLVED .config rather
# than the defconfig: CONFIG_NFSD's absence from board/mister/de10nano/linux.config proves
# nothing on its own (that file is a minimal defconfig -- an absent symbol may
# still be `default y`), and the flip we are guarding against comes from a
# Buildroot package's LINUX_CONFIG_FIXUPS, which edits the resolved .config and
# would never show up in ours.
# Filtered through -f rather than taken straight from the glob: an unmatched
# glob expands to the literal pattern, so a bare array would report "found 1"
# for "found none" -- the same fail-misleadingly shape as the hardcoded $KVER
# above. The linux-[0-9]* spelling (release.yml uses it too) excludes the
# linux-headers-*/linux-firmware-* siblings; more than one match means a stale
# tree from a version bump, which is a real thing to notice, not to glob past.
kconfigs=()
for _c in "$BUILD_DIR"/build/linux-[0-9]*/.config; do
	[ -f "$_c" ] && kconfigs+=("$_c")
done
if [ "${#kconfigs[@]}" -ne 1 ]; then
	skip "CONFIG_NFSD stays unset in the built kernel" \
		"expected exactly one $BUILD_DIR/build/linux-[0-9]*/.config, found ${#kconfigs[@]}"
elif grep -q '^CONFIG_NFSD=' "${kconfigs[0]}"; then
	fail "CONFIG_NFSD stays unset in the built kernel" \
		"$(grep '^CONFIG_NFSD=' "${kconfigs[0]}" | head -1) in ${kconfigs[0]} -- something (NFS_UTILS_LINUX_CONFIG_FIXUPS?) turned the in-kernel NFS server on"
else
	pass "CONFIG_NFSD stays unset in the built kernel (client-only, ADR 0022)"
fi

# =============================================================================
section "P3.11 — RTC parity"
# =============================================================================

if grep -qE '^\./etc/init\.d/S05' "$TAR_LIST"; then
	fail "no S05rtc init script (kernel-only RTC parity)" "found: $(grep -E '^\./etc/init\.d/S05' "$TAR_LIST" | tr '\n' ' ')"
else
	pass "no S05* init script (kernel-only RTC parity, P3.11)"
fi

# =============================================================================
section "DualSense tooling (dualsensectl) + the gconv modules it drags in"
# =============================================================================

# The CLI itself and hidapi's hidraw backend -- the libusb backend cannot see a
# Bluetooth-connected pad, so asserting "some hidapi .so shipped" would not be
# the same assertion. See docs/dualsense-tooling.md.
require_present "usr/bin/dualsensectl" "dualsensectl CLI"

if grep -qE '^\./usr/lib/libhidapi-hidraw\.so' "$TAR_LIST"; then
	pass "libhidapi-hidraw.so* present ($(grep -cE '^\./usr/lib/libhidapi-hidraw\.so' "$TAR_LIST") files)"
else
	fail "libhidapi-hidraw.so* present" "no usr/lib/libhidapi-hidraw.so* entries in rootfs.tar"
fi

# glibc's gconv charset modules. NOT decorative, and not really about
# dualsensectl: docs/package-manifest.md §1 has them in stock's own SONAME
# inventory and names gconv/ in its "Not recommended to drop (tempting by size,
# but load-bearing)" list -- "needed for any non-ASCII filename over SMB". They
# were nonetheless absent from the target for this project's whole life (glibc
# built them into the sysroot; nothing installed them), and they arrived only
# as a transitive select of hidapi
# (BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_COPY, with an empty _LIST meaning "all").
#
# That provenance is exactly why this is asserted here rather than trusted:
# turning BR2_PACKAGE_DUALSENSECTL back off would silently take SMB non-ASCII
# filename support with it, and nothing else in the build would say a word.
# The threshold is deliberately loose -- the point is "the directory is
# populated", not a specific module count that a glibc bump would churn.
gconv_count=$(grep -cE '^\./usr/lib/gconv/.*\.so$' "$TAR_LIST" || true)
if [ "$gconv_count" -ge 100 ]; then
	pass "glibc gconv charset modules present ($gconv_count .so files)"
else
	fail "glibc gconv charset modules present" \
		"found $gconv_count usr/lib/gconv/*.so in rootfs.tar (expected >=100); did BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_COPY get turned off, or GCONV_LIBS_LIST pinned to a subset?"
fi

# =============================================================================
section "Summary"
# =============================================================================

echo ""
printf '%s\n' "${SUMMARY[@]}"
echo ""
printf '%s: %d passed, %d failed, %d skipped (%d total)\n' \
	"$prog" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

# The full transcript above is long and the interesting part is at the top of it.
# Everything from here down is the digest: skips, then failures, then the verdict
# -- newest-reader-first, so `tail -n 30` answers "what broke and why" on its own.

# A SKIP is NOT a pass: the check did not run. Easy to miss in a green-looking
# wall of text (a missing qemu-arm silently skips the locale, timezone, ABI and
# Python gates), so name them rather than leaving them as a bare count.
if [ "$SKIP_COUNT" -gt 0 ]; then
	echo ""
	printf -- '---- SKIPPED (%d) -- these checks did NOT run ----\n' "$SKIP_COUNT"
	for _e in "${SKIPPED[@]}"; do
		printf '  SKIP  %s\n' "${_e%%$'\t'*}"
		printf '%s\n' "${_e#*$'\t'}" | sed 's/^/          /'
	done
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
	echo ""
	printf -- '==== FAILURES (%d) ====\n' "$FAIL_COUNT"
	for _e in "${FAILED[@]}"; do
		_name="${_e%%$'\t'*}"
		_why="${_e#*$'\t'}"
		printf '  FAIL  %s\n' "$_name"
		# sed, not printf: a reason is often multi-line (a Python traceback, a
		# diff). printf would indent only the first line and let the rest ragged
		# out of the block, which is precisely when you most want it readable.
		[ -n "$_why" ] && printf '%s\n' "$_why" | sed 's/^/          /'
		# Surface each failure in the PR's Files-changed / run UI, not just in a
		# 3000-line log nobody opens. %0A is how a GitHub annotation carries a
		# newline; a raw one would truncate the message at the first line.
		if [ -n "${GITHUB_ACTIONS:-}" ]; then
			printf '::error title=ci-tests: %s::%s\n' "$_name" "${_why//$'\n'/%0A}"
		fi
	done
fi

# Machine-readable, and the thing to upload as a CI artifact / paste into a bug.
# Never fatal: a read-only or missing build dir must not turn a green run red.
CI_TESTS_LOG="${CI_TESTS_LOG:-$BUILD_DIR/ci-tests-results.txt}"
if { : > "$CI_TESTS_LOG"; } 2>/dev/null; then
	{
		printf '# %s -- %s\n' "$prog" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf '# build-dir: %s\n' "$BUILD_DIR"
		printf '%s\n' "${SUMMARY[@]}"
		printf '# %d passed, %d failed, %d skipped (%d total)\n' \
			"$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" \
			"$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
	} > "$CI_TESTS_LOG"
	echo ""
	printf 'results written to %s\n' "$CI_TESTS_LOG"
fi

echo ""
if [ "$FAIL_COUNT" -gt 0 ]; then
	echo "==== RESULT: FAIL ===="
	exit 1
fi
echo "==== RESULT: PASS ===="
exit 0
