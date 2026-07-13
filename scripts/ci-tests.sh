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
#     A-10/A-22). NOTE: this is a *lightweight* re-implementation, not the future
#     scripts/check-abi.sh -- no such script exists yet (P2.2's full A-1..A-25 static
#     SONAME checklist in docs/abi-contract.md §13.1 is that task's own deliverable,
#     out of scope here). What's implemented is exactly the two headline checks
#     TASKS.md's own P2.2/P2.8 "Done when" text names.
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
# Exit: 0 = every check PASSed or SKIPped. 1 = at least one FAIL. 2 = usage error.
#
# Env overrides (all optional):
#   CI_TESTS_SKIP_QEMU_SYSTEM=1   skip scripts/test-initramfs.sh (the slow one --
#                                 builds/reuses a whole QEMU test kernel and boots
#                                 it 6 times; everything else in this suite is fast)

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

section() {
	printf '\n=== %s ===\n' "$*"
}

pass() {
	printf 'PASS  %s\n' "$1"
	SUMMARY+=("PASS  $1")
	PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
	printf 'FAIL  %s\n' "$1" >&2
	[ -n "${2:-}" ] && printf '      %s\n' "$2" >&2
	SUMMARY+=("FAIL  $1")
	FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
	printf 'SKIP  %s -- %s\n' "$1" "$2"
	SUMMARY+=("SKIP  $1 -- $2")
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
	if grep -q 'error while loading shared libraries' "$strace_out"; then
		fail "FPGA-access whitelist (P2.8/A-22)" "dynamic linker itself failed -- regression before any real syscall; see $strace_out"
	elif grep -qE 'openat.*"/dev/mem".*=.*-1.*(EACCES|errno=13)' "$strace_out"; then
		devmem_line=$(grep -nE 'openat.*"/dev/mem"' "$strace_out" | head -1 | cut -d: -f1)
		note "reached openat(\"/dev/mem\") at line $devmem_line of the trace (permission denied, as expected -- no FPGA bridge under qemu-user)"
		pass "FPGA-access whitelist (P2.8/A-22): dies at /dev/mem access, not earlier"
	else
		fail "FPGA-access whitelist (P2.8/A-22)" "never reached the expected openat(\"/dev/mem\") -- died earlier (regression) or ran past it; see $strace_out"
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

if [ "$FAIL_COUNT" -gt 0 ]; then
	echo "==== RESULT: FAIL ===="
	exit 1
fi
echo "==== RESULT: PASS ===="
exit 0
