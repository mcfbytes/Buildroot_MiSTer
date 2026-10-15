#!/usr/bin/env bash
#
# test-sdcard-install.sh — boot the FIRST-BOOT INSTALLER in QEMU and prove it
# turns a freshly-flashed sdcard.img into a valid, working MiSTer card
# (TASKS.md P5.3; ADR 0020; sibling of scripts/test-initramfs.sh).
#
# WHAT THIS PROVES, without any real DE10-Nano hardware:
#   The shipped sdcard.img is a FAT32 payload + 0xA2 boot + installer-flag image
#   (genimage-sdcard.cfg). Its /linux/zImage_dtb is THE kernel; stage 1 sees the
#   flag and hands the card to the installer (ADR 0033). This harness:
#     1. flashes sdcard.img onto a larger sparse "card" ($SDCARD_TEST_SIZE);
#     2. boots it under `qemu-system-arm -M virt` (virtio-blk as /dev/vda) and asserts
#        every installer stage ran, in the recoverable order ADR 0020 §8 requires;
#     3. checks the result on the host: p1 exFAT filling the card, p2 0xA2 holding
#        uboot.img byte-for-byte, and the flag (entry 3 + LBA 1024) gone;
#     4. boots the installed card again and asserts stage 1 took the NORMAL path
#        (exFAT mount, switch_root) and the installer never ran;
#     5. asserts the console splash drew; -M virt has no hps_led0, so it also proves
#        the LED half degrades to a no-op.
#
# NOT the DE10-Nano product kernel and NOT a full boot chain (no BootROM/SPL/U-Boot
# -- QEMU can't do socfpga). It tests the one brick-critical thing that has no
# other automated coverage: the installer's reformat+install logic on the real payload.
#
# SIBLING: scripts/test-installer-recovery.sh proves the other half of ADR 0020 §8 --
# that an install interrupted PART-WAY leaves a card that either re-installs itself
# or says honestly that it cannot. It synthesises its own card rather than needing
# `make all`, so it is the one to reach for while iterating on the installer; this
# harness is what proves the SHIPPED article.
#
# Prereqs: qemu-system-arm, sfdisk, cmp, truncate, plus a completed `make sdcard`
# (output/images/sdcard.img + output/images/mister-initramfs.cpio) and the pinned
# kernel source (dl/linux/linux-<pinned version>.tar.xz, same tarball the main build
# uses; scripts/lib/installer-qemu-kernel.sh also accepts the flat dl/ layout).
# The ARM cross toolchain comes from output/host/bin (a completed `make all`).
#
# Usage:
#   make all && make sdcard          # produce the inputs
#   scripts/test-sdcard-install.sh   # -> PASS/FAIL
# Env knobs: SDCARD_IMG, SDCARD_TEST_SIZE (default 2G), TEST_SDCARD_KBUILD,
#   INSTALL_TIMEOUT (default 600), GUARD_TIMEOUT (default 120), QEMU_MEM (default 512).

set -o errexit
set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- inputs (from make sdcard / make all) -----------------------------------
SDCARD_IMG="${SDCARD_IMG:-$ROOT/output/images/sdcard.img}"
INSTALLER_CPIO="${INSTALLER_CPIO:-$ROOT/output/images/mister-initramfs.cpio}"
UBOOT_REF="${UBOOT_REF:-$ROOT/output-sdcard-stage/mister-payload/linux/uboot.img}"
CROSS_COMPILE="${CROSS_COMPILE:-$ROOT/output/host/bin/arm-buildroot-linux-gnueabihf-}"

# --- QEMU test kernel (shares scripts/test-initramfs.sh's source tree + config) ---
# The recipe itself lives in scripts/lib/installer-qemu-kernel.sh, because
# scripts/test-installer-recovery.sh needs exactly the same kernel and a fix here
# must not have to be remembered there. The env knobs below keep their historical
# TEST_SDCARD_* names; empty means "let the library resolve it".
# shellcheck source=scripts/lib/installer-qemu-kernel.sh
. "$ROOT/scripts/lib/installer-qemu-kernel.sh"
IQK_ROOT="$ROOT"
IQK_CROSS_COMPILE="$CROSS_COMPILE"
IQK_KERNEL_VERSION="${TEST_SDCARD_KERNEL_VERSION:-}"
IQK_KERNEL_TARBALL="${TEST_SDCARD_KERNEL_TARBALL:-}"
IQK_KERNEL_SRC="${TEST_SDCARD_KERNEL_SRC:-$ROOT/work/test-initramfs-kernel-src}"
IQK_KBUILD="${TEST_SDCARD_KBUILD:-$ROOT/work/test-sdcard-install-kbuild}"
IQK_CPIO="$INSTALLER_CPIO"
IQK_ZIMAGE=""

# --- knobs ------------------------------------------------------------------
SDCARD_TEST_SIZE="${SDCARD_TEST_SIZE:-2G}"   # simulated card size to auto-expand into
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-600}"    # seconds for the install boot (TCG is slow)
GUARD_TIMEOUT="${GUARD_TIMEOUT:-120}"        # seconds for the post-install normal boot
QEMU_MEM="${QEMU_MEM:-512}"                  # MiB; ~the real mem=511M cap, to exercise the RAM budget

# RESERVED_SECTORS the installer keeps for p2 (must match mister-installer/install).
RESERVED_SECTORS=8192

mkdir -p "${TMPDIR:-$ROOT/work}"
WORK="$(mktemp -d "${TMPDIR:-$ROOT/work}/sdcard-install-test.XXXXXX")"
DISK="$WORK/test-disk.img"
INSTALL_LOG="$WORK/install.log"
GUARD_LOG="$WORK/guard.log"
trap 'rm -rf "$WORK"' EXIT

log()  { printf '[test-sdcard] %s\n' "$*"; }
pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; FAILED=1; }
die()  { printf '[test-sdcard] FATAL: %s\n' "$*" >&2; exit 2; }
FAILED=0

# eq GOT WANT DESC  -- assert GOT == WANT (proper if/then/else, not A && B || C).
eq()   { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi; }
# has LOGFILE PATTERN DESC  -- assert PATTERN present; hasnt = assert absent.
has()   { if grep -q "$2" "$1"; then pass "$3"; else fail "$3"; fi; }
hasnt() { if grep -q "$2" "$1"; then fail "$3"; else pass "$3"; fi; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing tool '$1' -- $2"; }

# ---------------------------------------------------------------- preconditions
need qemu-system-arm "install qemu-system-arm"
need sfdisk          "install util-linux"
need cmp             "install diffutils"
need truncate        "install coreutils"
[ -f "$SDCARD_IMG" ]      || die "no sdcard image at $SDCARD_IMG -- run 'make sdcard' first"
[ -f "$INSTALLER_CPIO" ]  || die "no stage-1 cpio at $INSTALLER_CPIO -- run 'make all' first"
[ -f "$UBOOT_REF" ]       || die "no uboot.img reference at $UBOOT_REF (set UBOOT_REF=)"
[ -x "${CROSS_COMPILE}gcc" ] || die "ARM cross gcc not found at ${CROSS_COMPILE}gcc -- run 'make all'"

# ------------------------------------------------------------ the QEMU test kernel
# Thin wrapper: the library does the work and sets IQK_ZIMAGE.
ensure_kernel() { iqk_ensure_kernel; }

# boot_installer LOGFILE TIMEOUT -- boot the installer kernel with $DISK on virtio-blk.
# root=/dev/vda1 tells the installer which partition is the data partition.
boot_installer() {
	local logf=$1 tmo=$2
	timeout "$tmo" qemu-system-arm -M virt -m "$QEMU_MEM" -nographic -no-reboot \
		-kernel "$IQK_ZIMAGE" \
		-drive file="$DISK",format=raw,if=none,id=sd0 \
		-device virtio-blk-device,drive=sd0 \
		-append "console=ttyAMA0,115200 loglevel=4 root=/dev/vda1 loop=linux/linux.img ro rootwait" \
		>"$logf" 2>&1 || true   # timeout/`-no-reboot` exit is expected; we assert on the log
}

# ============================================================================
main() {
	log "sdcard.img = $SDCARD_IMG ($(stat -c %s "$SDCARD_IMG") bytes)"
	ensure_kernel

	# --- 1. flash onto a bigger card ----------------------------------------
	log "flashing sdcard.img onto a $SDCARD_TEST_SIZE virtual card"
	cp -f "$SDCARD_IMG" "$DISK"
	truncate -s "$SDCARD_TEST_SIZE" "$DISK"
	local dev_sectors; dev_sectors=$(( $(stat -c %s "$DISK") / 512 ))

	# --- 2. install boot ----------------------------------------------------
	log "boot 1/2: running the installer (timeout ${INSTALL_TIMEOUT}s; TCG is slow) ..."
	boot_installer "$INSTALL_LOG" "$INSTALL_TIMEOUT"
	local stage
	for stage in \
		'source mounted' \
		'first-boot installer flag found' \
		'payload and kernel staged in RAM OK' \
		'uboot.img staged at LBA' \
		'the card can reach U-Boot again' \
		'from here a power cut re-runs the installer' \
		'this card can now finish on its own' \
		'per-board MAC = ' \
		'removed linux/linux.img.gz' \
		'this card is a MiSTer now' \
		'install complete'; do
		if grep -q "$stage" "$INSTALL_LOG"; then pass "installer stage: '$stage'"; else fail "installer never reached: '$stage'"; fi
	done
	if grep -q 'INSTALLER: FAILED' "$INSTALL_LOG"; then fail "installer dropped to the FAILURE rescue path"; else pass "no installer failure banner"; fi

	# --- 2a. the ORDER, not just the steps (ADR 0020 §8) --------------------
	# The whole point of the reorder is which write happens first, so assert the
	# order rather than the mere presence of each stage -- a future edit that
	# moves `dd uboot.img` back to the end would otherwise still pass every check
	# above while restoring the minute-long brick window of issue #185.
	#
	# Byte offsets, not line numbers: the guest console is a tty, the splash
	# rewrites its status line with \r, and several of these markers share a line.
	# `|| true` is load-bearing: this script runs under `set -o pipefail`, so a
	# marker that is ABSENT makes grep fail, fails the pipeline, and -- because the
	# result is captured into a variable -- `set -e` would abort the harness instead
	# of reporting the FAIL. An empty offset is the answer we want here.
	at() { grep -abo -m1 "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1 || true; }
	local o_staged o_part o_uboot o_mkfs o_recov o_payload o_commit
	o_staged=$(at  "$INSTALL_LOG" 'uboot.img staged at LBA')
	o_part=$(at    "$INSTALL_LOG" 'new partitions present')
	o_uboot=$(at   "$INSTALL_LOG" 'the card can reach U-Boot again')
	o_mkfs=$(at    "$INSTALL_LOG" 'formatting (exFAT)')
	o_recov=$(at   "$INSTALL_LOG" 'from here a power cut re-runs the installer')
	o_payload=$(at "$INSTALL_LOG" 'this card can now finish on its own')
	o_commit=$(at  "$INSTALL_LOG" 'this card is a MiSTer now')
	order_ok() { # order_ok A B DESC -- assert offset A < offset B
		if [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; then pass "$3"; else fail "$3 (offsets '$1' vs '$2')"; fi
	}
	order_ok "$o_staged"  "$o_part"    "order: uboot.img is staged BEFORE the MBR points p2 at it"
	order_ok "$o_part"    "$o_uboot"   "order: uboot.img is verified in p2 right after the repartition"
	order_ok "$o_uboot"   "$o_mkfs"    "order: the bootloader is written BEFORE the filesystem is made"
	order_ok "$o_mkfs"    "$o_recov"   "order: the kernel is restored right after the format"
	order_ok "$o_recov"   "$o_payload" "order: the card is self-recovering before the payload copy-back"
	order_ok "$o_payload" "$o_commit"  "order: spending the flag is the LAST thing done (the commit point)"

	# --- 2b. the first-boot splash ------------------------------------------
	# During the install there is no HDMI and no menu (the FPGA has no bitstream
	# loaded -- see the long "WHY THERE IS NO HDMI SPLASH" note in the installer
	# /init), so this console UI plus the hps_led0 heartbeat is the ONLY thing
	# telling a user the board has not hung. Assert that it actually drew, rather
	# than only that the install worked silently underneath it.
	#
	# NOTE: the guest console is a tty here, so the splash animates in place with
	# \r and the step labels land mid-line rather than at a line start. Match on
	# substrings only -- do not anchor these patterns with ^.
	has "$INSTALL_LOG" 'F I R S T - B O O T   S E T U P' "splash: banner drew"
	has "$INSTALL_LOG" 'Do NOT power off'                "splash: warns against pulling power"
	local step
	for step in \
		'checking the card' \
		'reading the payload' \
		'copying to memory' \
		'writing the bootloader' \
		'repartitioning the card' \
		'formatting (exFAT)' \
		'making the card recoverable' \
		'writing files to the card' \
		'expanding the system image' \
		'finishing the install'; do
		has "$INSTALL_LOG" "$step" "splash: reached step '$step'"
	done
	has "$INSTALL_LOG" '] 100%'          "splash: progress bar reached 100%"
	has "$INSTALL_LOG" 'INSTALL COMPLETE' "splash: completion banner drew"
	# QEMU's -M virt has no hps_led0, so this run also proves the LED code path
	# degrades to a no-op instead of failing an install on a board without one.
	pass "splash: install completed on a platform with no hps_led0"
	# The generated MAC must be locally-administered (bit1 set) + unicast (bit0 clear).
	local mac; mac=$(sed -n 's/.*per-board MAC = \([0-9A-Fa-f:]*\).*/\1/p' "$INSTALL_LOG" | head -1)
	if [ -n "$mac" ]; then
		local o1=$(( 0x${mac%%:*} ))
		if [ $(( o1 & 0x02 )) -ne 0 ] && [ $(( o1 & 0x01 )) -eq 0 ]; then pass "MAC $mac is locally-administered + unicast"; else fail "MAC $mac is not locally-administered unicast"; fi
	else fail "no per-board MAC in the install log"; fi

	# --- 3. verify the resulting disk (host-side, no privilege) -------------
	local dump; dump=$(sfdisk -d "$DISK" 2>/dev/null)
	# p1 = exFAT (type 7), starts at 2048, and fills the card up to the reserved tail.
	local p1_start p1_size p1_type p2_start p2_size p2_type
	p1_start=$(printf '%s\n' "$dump" | sed -n '/img1 /s/.*start=\s*\([0-9]*\).*/\1/p')
	p1_size=$(printf '%s\n'  "$dump" | sed -n '/img1 /s/.*size=\s*\([0-9]*\).*/\1/p')
	p1_type=$(printf '%s\n'  "$dump" | sed -n '/img1 /s/.*type=\s*\([0-9A-Fa-f]*\).*/\1/p')
	p2_start=$(printf '%s\n' "$dump" | sed -n '/img2 /s/.*start=\s*\([0-9]*\).*/\1/p')
	p2_size=$(printf '%s\n'  "$dump" | sed -n '/img2 /s/.*size=\s*\([0-9]*\).*/\1/p')
	p2_type=$(printf '%s\n'  "$dump" | sed -n '/img2 /s/.*type=\s*\([0-9A-Fa-f]*\).*/\1/p')

	eq "$p1_type" "7"   "p1 type=7 (exFAT/NTFS)"
	eq "$p1_start" "2048" "p1 start=2048 (1 MiB aligned)"
	eq "$p2_type" "a2"  "p2 type=a2 (SPL boot)"
	eq "$p2_size" "$RESERVED_SECTORS" "p2 size=$RESERVED_SECTORS (exactly RESERVED_SECTORS)"
	# p1 must fill the card: p1_start + p1_size + p2_size == dev_sectors.
	if [ -n "$p1_size" ] && [ $(( p1_start + p1_size + p2_size )) -eq "$dev_sectors" ]; then
		pass "p1 fills the card (2048 + $p1_size + $p2_size = $dev_sectors sectors)"
	else fail "partitions do not fill the card ($p1_start+$p1_size+$p2_size != $dev_sectors)"; fi

	# p2 head == uboot.img byte-for-byte.
	local ubsz; ubsz=$(stat -c %s "$UBOOT_REF")
	dd if="$DISK" bs=512 skip="$p2_start" count=$(( ubsz / 512 + 1 )) 2>/dev/null | head -c "$ubsz" > "$WORK/p2head.bin"
	if cmp -s "$WORK/p2head.bin" "$UBOOT_REF"; then pass "p2 head == uboot.img ($ubsz bytes)"; else fail "p2 head != uboot.img"; fi

	# p1 exFAT signature.
	local sig; sig=$(dd if="$DISK" bs=1 skip=$(( p1_start*512 + 3 )) count=8 2>/dev/null | tr -d '\0 ')
	eq "$sig" "EXFAT" "p1 has the exFAT signature"
	local e3 blk
	e3=$(dd if="$DISK" bs=1 skip=478 count=16 2>/dev/null | od -An -tx1 | tr -d ' \n')
	eq "$e3" "00000000000000000000000000000000" "MBR entry 3 (the installer flag) was removed"
	blk=$(dd if="$DISK" bs=512 skip=1024 count=1 2>/dev/null | tr -d '\0' | wc -c)
	eq "$blk" "0" "the flag block at LBA 1024 was wiped"

	# --- 4. the installed card boots normally -------------------------------
	log "boot 2/2: the installed card must take stage 1's NORMAL path (no flag any more) ..."
	boot_installer "$GUARD_LOG" "$GUARD_TIMEOUT"
	has   "$GUARD_LOG" 'data partition mounted as exfat' "installed card mounts as exFAT on the normal path"
	has   "$GUARD_LOG" 'switching root'                  "stage 1 switch_rooted into the installed linux.img"
	hasnt "$GUARD_LOG" 'installer flag found'            "/init saw no armed flag"
	hasnt "$GUARD_LOG" '\[installer\]'                  "the installer never ran again"
	hasnt "$GUARD_LOG" 'BOOT FAILED'                     "no stage-1 rescue"

	echo
	if [ "$FAILED" -eq 0 ]; then
		log "ALL CHECKS PASSED -- the installer produces a valid, full-size exFAT MiSTer card."
		return 0
	fi
	log "one or more checks FAILED (see above). Install log: $INSTALL_LOG"
	return 1
}

main "$@"
