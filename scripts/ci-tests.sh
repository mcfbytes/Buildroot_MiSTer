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
KVER=6.18.38

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

# ---------------------------------------------------------------- prereqs
[ -f "$ROOTFS_TAR" ] || { echo "$prog: no $ROOTFS_TAR -- run a build first (or pass the build dir as \$1)." >&2; exit 2; }

TAR_LIST="$(mktemp "${TMPDIR:-/tmp}/ci-tests-tarlist.XXXXXX")"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/ci-tests-work.XXXXXX")"
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

# Out-of-tree WiFi drivers (ADR 0016): the three 802.11ac Realtek chips mainline
# still cannot drive. These are kernel-module PACKAGES, and Buildroot STAMPS
# those -- a kernel *version* bump (e.g. 6.18.33 -> 6.18.38) rebuilds the in-tree
# modules but silently leaves these built against the OLD kernel, so they land in
# a stale lib/modules/<old>/ tree and vanish from the shipped one. That really
# happened (local 6.18.38 build) and the xone check above is the only reason it
# was caught -- these three had no assertion at all and would have gone missing
# silently, taking every RTL8812AU/8814AU/8821AU adapter with them. Hence this.
# Fix when it fires: `make <pkg>-dirclean` for each, then rebuild.
ootwifi_mods="8812au 8814au 8821au"
ootwifi_missing=""
for m in $ootwifi_mods; do
	tar_has "usr/lib/modules/$KVER/updates/$m.ko.xz" || ootwifi_missing="$ootwifi_missing $m"
done
if [ -z "$ootwifi_missing" ]; then
	pass "out-of-tree WiFi: 8812au + 8814au + 8821au .ko.xz present (ADR 0016)"
else
	fail "out-of-tree WiFi: 8812au + 8814au + 8821au .ko.xz present (ADR 0016)" \
		"missing:$ootwifi_missing -- kernel-module packages are stamped; a kernel bump needs 'make <pkg>-dirclean' + rebuild"
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
section "Timezone parity (tzdata + persistent /etc/localtime)"
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

# =============================================================================
section "P3.10 — Network filesystem client parity"
# =============================================================================

require_present "usr/sbin/mount.cifs" "mount.cifs"

if tar_has "usr/sbin/mount.nfs" || tar_has "sbin/mount.nfs"; then
	fail "mount.nfs ABSENT (parity)" "mount.nfs IS present in rootfs.tar -- P3.10 dropped NFS client parity, this is a regression"
else
	pass "mount.nfs ABSENT (parity, P3.10 dropped NFS client)"
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
