#!/usr/bin/env bash
#
# test-sdcard-install.sh — boot the FIRST-BOOT INSTALLER in QEMU and prove it
# turns a freshly-flashed sdcard.img into a valid, working MiSTer card
# (TASKS.md P5.3; ADR 0020; sibling of scripts/test-initramfs.sh).
#
# WHAT THIS PROVES, without any real DE10-Nano hardware:
#   The shipped sdcard.img (board/mister/de10nano/genimage-sdcard.cfg) is a small
#   FAT32-payload + 0xA2-boot image. Its /linux/zImage_dtb is the INSTALLER kernel
#   (our 6.18 kernel relinked with board/mister/de10nano/installer-overlay/init as
#   its initramfs). On first boot that /init reformats the whole card to a
#   full-size exFAT "MiSTer_Data" partition, installs the real payload, writes a
#   per-board MAC, dd's uboot.img to the new 0xA2 partition, and reboots. This
#   harness exercises that end to end:
#
#     1. Flash the shipped sdcard.img onto a LARGER "card" (a sparse image
#        truncated up to $SDCARD_TEST_SIZE) so there is room to auto-expand into.
#     2. Boot the installer kernel under `qemu-system-arm -M virt`, the card on
#        virtio-blk as /dev/vda (exactly scripts/test-initramfs.sh's approach; QEMU
#        has no Cyclone V model). Assert the installer ran every stage and rebooted.
#     3. Verify the RESULT on the host (no privilege needed): partition table
#        (p1 exFAT filling the card, p2 0xA2 == RESERVED_SECTORS at the tail), the
#        0xA2 head is byte-for-byte uboot.img, and p1 carries the exFAT signature.
#     4. Boot the installer AGAIN against the installed card and assert its re-run
#        guard trips ("already provisioned") -- which is only possible if p1 is
#        exFAT, labelled MiSTer_Data, AND contains linux/linux.img (so the payload
#        landed and linux.img.gz expanded). Also asserts the benign-halt path does
#        NOT print the "INSTALLER: FAILED" banner.
#
# NOT the DE10-Nano product kernel and NOT a full boot chain (no BootROM/SPL/U-Boot
# -- QEMU can't do socfpga). It tests the one new, brick-critical thing that has no
# other automated coverage: the installer /init's reformat+install logic.
#
# Prereqs: qemu-system-arm, sfdisk, cmp, truncate, plus a completed `make sdcard`
# (output/images/sdcard.img + output-installer/images/rootfs.cpio) and the pinned
# linux-6.18.38 source (dl/linux-6.18.38.tar.xz, same tarball the main build uses).
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
INSTALLER_CPIO="${INSTALLER_CPIO:-$ROOT/output-installer/images/rootfs.cpio}"
UBOOT_REF="${UBOOT_REF:-$ROOT/output-sdcard-stage/mister-payload/linux/uboot.img}"
CROSS_COMPILE="${CROSS_COMPILE:-$ROOT/output/host/bin/arm-buildroot-linux-gnueabihf-}"

# --- QEMU test kernel (shares scripts/test-initramfs.sh's source tree + config) ---
KERNEL_TARBALL="${TEST_SDCARD_KERNEL_TARBALL:-$ROOT/dl/linux-6.18.38.tar.xz}"
KERNEL_SRC="${TEST_SDCARD_KERNEL_SRC:-$ROOT/work/test-initramfs-kernel-src}"
KBUILD="${TEST_SDCARD_KBUILD:-$ROOT/work/test-sdcard-install-kbuild}"
KERNEL_FRAGMENT="$ROOT/scripts/test-initramfs/qemu-test-kernel.config"
EXFAT_SYMLINK_PATCH="$ROOT/board/mister/de10nano/linux-patches/0031-exfat-samsung-symlinks.patch"
QEMU_ZIMAGE="$KBUILD/arch/arm/boot/zImage"

# --- knobs ------------------------------------------------------------------
SDCARD_TEST_SIZE="${SDCARD_TEST_SIZE:-2G}"   # simulated card size to auto-expand into
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-600}"    # seconds for the install boot (TCG is slow)
GUARD_TIMEOUT="${GUARD_TIMEOUT:-120}"        # seconds for the re-run-guard boot (halts to a shell)
QEMU_MEM="${QEMU_MEM:-512}"                  # MiB; ~the real mem=511M cap, to exercise the RAM budget

# RESERVED_SECTORS the installer keeps for p2 (must match installer-overlay/init).
RESERVED_SECTORS=8192

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sdcard-install-test.XXXXXX")"
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
[ -f "$INSTALLER_CPIO" ]  || die "no installer cpio at $INSTALLER_CPIO -- run 'make sdcard' first"
[ -f "$UBOOT_REF" ]       || die "no uboot.img reference at $UBOOT_REF (set UBOOT_REF=)"
[ -x "${CROSS_COMPILE}gcc" ] || die "ARM cross gcc not found at ${CROSS_COMPILE}gcc -- run 'make all'"

# ------------------------------------------------------------ the QEMU test kernel
# Same recipe as scripts/test-initramfs.sh's ensure_qemu_kernel, but embedding the
# INSTALLER cpio. Built out-of-tree in its OWN $KBUILD so it never fights the
# test-initramfs harness's CONFIG_INITRAMFS_SOURCE. O= MUST be absolute (a relative
# O= is resolved against $KERNEL_SRC, silently building into a nested dir).
ensure_kernel() {
	case "$KBUILD" in /*) : ;; *) die "TEST_SDCARD_KBUILD must be an absolute path" ;; esac
	if [ ! -f "$KBUILD/.config" ]; then
		[ -d "$KERNEL_SRC/scripts/kconfig" ] || {
			[ -f "$KERNEL_TARBALL" ] || die "kernel source missing: neither $KERNEL_SRC nor $KERNEL_TARBALL"
			log "extracting $KERNEL_TARBALL -> $KERNEL_SRC"
			mkdir -p "$KERNEL_SRC"
			tar -C "$KERNEL_SRC" --strip-components=1 -xf "$KERNEL_TARBALL"
		}
		# fs/exfat symlink support (ADR 0019, board patch 0031) -- idempotent.
		if [ -f "$EXFAT_SYMLINK_PATCH" ] && ! grep -q EXFAT_ATTR_SYMLINK "$KERNEL_SRC/fs/exfat/exfat_raw.h" 2>/dev/null; then
			log "applying $(basename "$EXFAT_SYMLINK_PATCH")"
			patch -p1 -s -d "$KERNEL_SRC" < "$EXFAT_SYMLINK_PATCH" || die "board patch 0031 failed to apply"
		fi
		mkdir -p "$KBUILD"
		log "configuring: multi_v7_defconfig + qemu-test-kernel.config"
		make -C "$KERNEL_SRC" O="$KBUILD" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" multi_v7_defconfig >&2
		# `-m` = MERGE ONLY. Without it, merge_config.sh runs a bare `make alldefconfig`
		# (no -C) whose `make` resolves to this repo's ROOT wrapper Makefile (which
		# forwards to Buildroot and dies "Can't read seed configuration"). We reconcile
		# ourselves below with `make -C "$KERNEL_SRC" ... olddefconfig` (proper -C + ARCH).
		"$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$KBUILD" "$KBUILD/.config" "$KERNEL_FRAGMENT" >&2
	fi
	# Point at the installer cpio and (re)build. Nuke the cached initramfs object so a
	# changed /init is never silently embedded stale (the kernel's own dep tracking
	# can miss a same-path cpio-content change).
	"$KERNEL_SRC/scripts/config" --file "$KBUILD/.config" --set-str CONFIG_INITRAMFS_SOURCE "$INSTALLER_CPIO"
	make -C "$KERNEL_SRC" O="$KBUILD" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" olddefconfig >&2
	rm -f "$KBUILD"/usr/initramfs_data.cpio* "$KBUILD/arch/arm/boot/zImage"
	log "building QEMU test kernel (embedding the installer initramfs)"
	make -C "$KERNEL_SRC" O="$KBUILD" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" zImage >&2
	[ -f "$QEMU_ZIMAGE" ] || die "kernel build produced no $QEMU_ZIMAGE"
}

# boot_installer LOGFILE TIMEOUT -- boot the installer kernel with $DISK on virtio-blk.
# root=/dev/vda1 tells the installer which partition is the data partition.
boot_installer() {
	local logf=$1 tmo=$2
	timeout "$tmo" qemu-system-arm -M virt -m "$QEMU_MEM" -nographic -no-reboot \
		-kernel "$QEMU_ZIMAGE" \
		-drive file="$DISK",format=raw,if=none,id=sd0 \
		-device virtio-blk-device,drive=sd0 \
		-append "console=ttyAMA0,115200 loglevel=4 root=/dev/vda1" \
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
		'payload staged in RAM OK' \
		'payload written to' \
		'per-board MAC = ' \
		'uboot.img written to' \
		'install complete'; do
		if grep -q "$stage" "$INSTALL_LOG"; then pass "installer stage: '$stage'"; else fail "installer never reached: '$stage'"; fi
	done
	if grep -q 'INSTALLER: FAILED' "$INSTALL_LOG"; then fail "installer dropped to the FAILURE rescue path"; else pass "no installer failure banner"; fi
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

	# --- 4. re-run guard against the installed card -------------------------
	log "boot 2/2: re-running the installer against the installed card (guard must trip) ..."
	boot_installer "$GUARD_LOG" "$GUARD_TIMEOUT"
	has   "$GUARD_LOG" 'source mounted (exfat)' "installed card re-mounts as exFAT"
	has   "$GUARD_LOG" 'already provisioned'    "re-run guard tripped (exFAT MiSTer_Data + linux/linux.img present)"
	hasnt "$GUARD_LOG" 'INSTALLER: FAILED'      "benign halt did not print the FAILED banner"

	echo
	if [ "$FAILED" -eq 0 ]; then
		log "ALL CHECKS PASSED -- the installer produces a valid, full-size exFAT MiSTer card."
		return 0
	fi
	log "one or more checks FAILED (see above). Install log: $INSTALL_LOG"
	return 1
}

main "$@"
