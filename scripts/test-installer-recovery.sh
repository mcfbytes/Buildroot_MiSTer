#!/usr/bin/env bash
#
# test-installer-recovery.sh — prove that an SD-card install INTERRUPTED part-way
# leaves a card that either finishes by itself on the next boot, or says honestly
# that it cannot (ADR 0020 §8; issue #185; sibling of scripts/test-sdcard-install.sh).
#
# WHY THIS EXISTS SEPARATELY FROM test-sdcard-install.sh
# -----------------------------------------------------
# That harness proves the SHIPPED sdcard.img installs correctly when nothing goes
# wrong, and it needs a completed `make all` + `make sdcard` (hours) to do it. The
# property THIS file tests is the opposite one: what the card looks like when the
# user pulls the power half-way through, which is the failure issue #185 is about.
# It does not need the real payload — the installer /init never looks inside those
# files — so it synthesises a card with the shipped SHAPE and miniature contents,
# and runs in minutes off one installer cpio and one QEMU kernel. That is the whole
# reason it is a separate script rather than three more boots bolted onto a harness
# nobody can run on a laptop.
#
# WHAT IT PROVES
# --------------
#   A. Interrupted right after the payload copy-back completed
#      -> the card still has a valid partition table, the bootloader is ALREADY in
#         the 0xA2 partition, and the next boot re-runs the installer unattended
#         and finishes. One extra run, nothing else lost.
#   B. Interrupted mid-copy (mister-payload.part/ on the card)
#      -> the next boot HALTS with the honest "the previous install was
#         INTERRUPTED / re-flash sdcard.img" banner. No reboot loop, no silent
#         panic, and emphatically no reformat of a card it cannot install to.
#   C. Interrupted immediately after the card was made self-recovering
#      -> the bootloader and the installer's own kernel are on the card, and the
#         next boot stops cleanly rather than reformatting with no payload.
#   D. The finished card from (A) still trips the "already provisioned" guard.
#   E. Interrupted after linux/linux.img was expanded
#      -> the card matches every condition the OLD re-run guard used while still
#         booting the installer, so this is the case ADR 0020 §8.4 re-keyed that
#         guard for. The next boot must finish the install, not declare the card
#         installed. (A) cannot cover this: it stops before the expansion.
#   F. Interrupted between sfdisk and mkfs.exfat
#      -> fully recoverable, and worth pinning: sfdisk only rewrites the MBR and
#         the new p1 still starts at LBA 2048, so the shipped FAT32 is still
#         readable under the enlarged entry and the install just runs again.
#
# It also runs a plain, uninterrupted install first (scenario 0), because that is
# the only place the PRISTINE FAT32 first boot is exercised without a `make all`,
# and because the ORDER assertions it makes are the same ones
# scripts/test-sdcard-install.sh makes against the shipped card -- so a marker
# string that drifts fails here, cheaply, instead of in the 3-hour harness.
#
# HOW THE INTERRUPTION IS DONE
# ----------------------------
# The installer honours `mister_installer_stop_after=<tag>` on its kernel command
# line and reboots at that exact point. It does NOT trust that token on its own:
# a user can get arbitrary tokens onto the cmdline through u-boot.txt's $v
# (docs/boot-chain.md §4/§5), and stopping a real install at `recoverable` or
# `payload-partial` would cost that user a re-flash. The hook is gated on
# /.installer-test-hook existing in the INITRAMFS, which no shipped image has and
# no amount of writing to the card can produce. This harness asks
# scripts/lib/installer-qemu-kernel.sh to append that marker as a second cpio
# archive (IQK_EXTRA_INITRAMFS), leaving the installer cpio and /init unchanged.
#
# Scenario 0 below is therefore run against a kernel built WITHOUT the marker,
# with the stop token on its cmdline: if the gate ever regressed to trusting the
# cmdline, that install would stop early instead of completing, and the scenario
# fails. Every later scenario uses the marker kernel.
#
# WHAT IT CANNOT TELL YOU
# -----------------------
# QEMU's -M virt has no BootROM, no SPL and no U-Boot, so "the card would have
# booted the installer again" is modelled, not executed: we hand qemu the same
# -kernel every time. What is actually checked is the two facts a real U-Boot needs
# -- that uboot.img is byte-for-byte in the 0xA2 partition, and that the installer
# found its own linux/zImage_dtb on the card when it re-ran -- plus the end-to-end
# result, that the re-run installs. The remaining link (a real BootROM loading that
# SPL) is P5.4's, on hardware.
#
# Prereqs: qemu-system-arm, sfdisk, mkfs.vfat+mcopy (dosfstools/mtools), cmp,
# truncate, gzip, cpio; the installer cpio (output-installer/images/rootfs.cpio, from
# `make sdcard`, or any Buildroot build of configs/mister_installer_defconfig); an
# ARM cross gcc; and the pinned kernel tarball under dl/.
#
# Usage:
#   scripts/test-installer-recovery.sh          # -> PASS/FAIL
# Env knobs: INSTALLER_CPIO, CROSS_COMPILE, TEST_SDCARD_KBUILD (shared with
#   test-sdcard-install.sh, so running one makes the other cheap),
#   TEST_SDCARD_KERNEL_TARBALL, SDCARD_TEST_SIZE (default 2G),
#   INSTALL_TIMEOUT (default 600), HALT_TIMEOUT (default 120), QEMU_MEM (default 512).

set -o errexit
set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INSTALLER_CPIO="${INSTALLER_CPIO:-$ROOT/output-installer/images/rootfs.cpio}"
CROSS_COMPILE="${CROSS_COMPILE:-$ROOT/output/host/bin/arm-buildroot-linux-gnueabihf-}"

# The QEMU kernel recipe is shared with test-sdcard-install.sh on purpose -- same
# cpio, same kernel, so whichever you run first pays for both.
# shellcheck source=scripts/lib/installer-qemu-kernel.sh
. "$ROOT/scripts/lib/installer-qemu-kernel.sh"
IQK_ROOT="$ROOT"
IQK_CROSS_COMPILE="$CROSS_COMPILE"
IQK_KERNEL_VERSION="${TEST_SDCARD_KERNEL_VERSION:-}"
IQK_KERNEL_TARBALL="${TEST_SDCARD_KERNEL_TARBALL:-}"
IQK_KERNEL_SRC="${TEST_SDCARD_KERNEL_SRC:-$ROOT/work/test-initramfs-kernel-src}"
IQK_KBUILD="${TEST_SDCARD_KBUILD:-$ROOT/work/test-sdcard-install-kbuild}"
IQK_CPIO="$INSTALLER_CPIO"
IQK_EXTRA_INITRAMFS=""   # set per-kernel in main(); see HOW THE INTERRUPTION IS DONE
IQK_ZIMAGE=""

SDCARD_TEST_SIZE="${SDCARD_TEST_SIZE:-2G}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-600}"
HALT_TIMEOUT="${HALT_TIMEOUT:-120}"     # backstop only; boot() stops on its marker (see boot())
QEMU_MEM="${QEMU_MEM:-512}"

# Must match board/mister/de10nano/installer-overlay/init and genimage-sdcard.cfg.
RESERVED_SECTORS=8192
P1_START_SECTORS=2048
# The synthesised card's own FAT32 payload partition. Big enough that mkfs.vfat
# will make a FAT32 (not FAT16) filesystem, small enough to build in a second.
SYNTH_P1_MIB=128
# The fake system image: gzipped on the card exactly as the real one is, and
# expanded onto the reformatted partition by the installer. 64 MiB of zeros
# compresses to ~64 KiB, so this costs nothing and still exercises the zcat path.
SYNTH_LINUX_IMG_MIB=64

# Default the scratch dir under work/, next to the kbuild tree, NOT under /tmp:
# the card below is a 2 GB sparse file and /tmp is a tmpfs on plenty of machines
# (it is on the maintainer's), so a run would be charged to RAM and shared with
# whatever else is using it. TMPDIR still overrides, for anyone who wants that.
WORK_BASE="${TMPDIR:-$ROOT/work}"
mkdir -p "$WORK_BASE" || { printf '[test-recovery] FATAL: cannot create %s\n' "$WORK_BASE" >&2; exit 2; }
WORK="$(mktemp -d "$WORK_BASE/installer-recovery-test.XXXXXX")"
CARD="$WORK/synth-sdcard.img"
DISK="$WORK/test-disk.img"
trap 'rm -rf "$WORK"' EXIT

log()  { printf '[test-recovery] %s\n' "$*"; }
pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; FAILED=1; }
die()  { printf '[test-recovery] FATAL: %s\n' "$*" >&2; exit 2; }
FAILED=0

eq()    { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi; }
has()   { if grep -q "$2" "$1"; then pass "$3"; else fail "$3"; fi; }
hasnt() { if grep -q "$2" "$1"; then fail "$3"; else pass "$3"; fi; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing tool '$1' -- $2"; }

# ---------------------------------------------------------------- preconditions
need qemu-system-arm "install qemu-system-arm"
need sfdisk          "install util-linux"
need mkfs.vfat       "install dosfstools"
need mcopy           "install mtools"
need cmp             "install diffutils"
need truncate        "install coreutils"
need gzip            "install gzip"
need cpio            "install cpio (the test-hook marker archive)"
[ -f "$INSTALLER_CPIO" ] || die "no installer cpio at $INSTALLER_CPIO -- build configs/mister_installer_defconfig, or set INSTALLER_CPIO="
[ -x "${CROSS_COMPILE}gcc" ] || die "ARM cross gcc not found at ${CROSS_COMPILE}gcc (set CROSS_COMPILE=)"

# ===========================================================================
#  A synthetic card with the SHIPPED SHAPE and miniature contents
# ===========================================================================
# Shape, not contents, is what the installer reacts to: it globs the payload's
# top-level entries, requires linux/{linux.img.gz,zImage_dtb,uboot.img} inside it,
# and reads linux/zImage_dtb + menu.rbf from the FAT ROOT (the two files that make
# an interrupted card recoverable). Everything here mirrors
# docs/verification/sdcard-payload.md §1 in structure, at ~1/1000th the size.
#
# Two collisions are deliberately reproduced because the commit phase has to
# survive them: menu.rbf exists BOTH at the root and inside the payload, and the
# payload has a linux/ directory that must merge with the one the installer
# already created for its own kernel.
STAGE="$WORK/fatroot"
UBOOT_REF="$WORK/uboot.img"
INSTALLER_KERNEL_REF="$WORK/installer-zImage_dtb"

blob() { # blob PATH SIZE_KIB MARKER -- deterministic, distinguishable filler
	local path=$1 kib=$2 marker=$3
	mkdir -p "${path%/*}"
	{
		printf '%s\n' "$marker"
		head -c $(( kib * 1024 - ${#marker} - 1 )) /dev/zero | tr '\0' "${marker:0:1}"
	} > "$path"
}

build_synth_card() {
	log "synthesising a card with the shipped layout (p1 FAT32 ${SYNTH_P1_MIB}M, p2 0xA2 4M)"
	local p="$STAGE/mister-payload"
	mkdir -p "$STAGE/linux" "$p/linux/soundfonts" "$p/Scripts"

	# --- p1 root: what the installer boots from and recovers with ------------
	blob "$INSTALLER_KERNEL_REF" 2048 "INSTALLER-KERNEL"
	cp "$INSTALLER_KERNEL_REF" "$STAGE/linux/zImage_dtb"
	blob "$STAGE/menu.rbf" 512 "MENU-RBF"

	# --- the payload ---------------------------------------------------------
	# The REAL kernel: must differ from the installer's, since the commit point is
	# precisely the moment one replaces the other.
	blob "$p/linux/zImage_dtb" 2048 "REAL-KERNEL"
	blob "$UBOOT_REF" 503 "UBOOT-IMG"
	cp "$UBOOT_REF" "$p/linux/uboot.img"
	head -c $(( SYNTH_LINUX_IMG_MIB * 1024 * 1024 )) /dev/zero > "$WORK/linux.img"
	gzip -1 -c "$WORK/linux.img" > "$p/linux/linux.img.gz"
	rm -f "$WORK/linux.img"
	blob "$p/linux/7za" 64 "SEVENZIP"
	printf 'ethaddr=02:03:04:05:06:07\n' > "$p/linux/u-boot.txt_example"
	blob "$p/linux/soundfonts/test.sf2" 32 "SOUNDFONT"
	cp "$STAGE/menu.rbf" "$p/menu.rbf"          # the root/payload collision
	blob "$p/MiSTer" 256 "MISTER-BIN"
	printf '[MiSTer]\n' > "$p/MiSTer.ini"
	printf '[MiSTer]\nupdate_linux = false\n' > "$p/downloader.ini"
	printf '#!/bin/sh\nexit 0\n' > "$p/Scripts/update_all.sh"

	# --- assemble: FAT32 image, then the MBR around it -----------------------
	local p1_bytes=$(( SYNTH_P1_MIB * 1024 * 1024 ))
	local p1_sectors=$(( p1_bytes / 512 ))
	local total_sectors=$(( P1_START_SECTORS + p1_sectors + RESERVED_SECTORS ))
	truncate -s "$p1_bytes" "$WORK/p1.vfat"
	mkfs.vfat -F 32 -n MISTER "$WORK/p1.vfat" >/dev/null
	mcopy -s -i "$WORK/p1.vfat" "$STAGE/linux" "$STAGE/menu.rbf" "$STAGE/mister-payload" ::/

	truncate -s $(( total_sectors * 512 )) "$CARD"
	sfdisk --quiet "$CARD" >/dev/null <<-EOF
	label: dos
	start=${P1_START_SECTORS}, size=${p1_sectors}, type=c
	start=$(( P1_START_SECTORS + p1_sectors )), size=${RESERVED_SECTORS}, type=a2
	EOF
	dd if="$WORK/p1.vfat" of="$CARD" bs=512 seek="$P1_START_SECTORS" conv=notrunc status=none
	dd if="$UBOOT_REF" of="$CARD" bs=512 seek=$(( P1_START_SECTORS + p1_sectors )) conv=notrunc status=none
	rm -f "$WORK/p1.vfat"
	log "synthetic card: $(stat -c %s "$CARD") bytes"
}

flash_fresh_card() {
	cp -f "$CARD" "$DISK"
	truncate -s "$SDCARD_TEST_SIZE" "$DISK"
}

# boot LOGFILE TIMEOUT [EXTRA_CMDLINE] [STOP_REGEX]
#
# `-no-reboot` makes qemu exit when the guest reboots, which ends every boot that
# RUNS to completion by itself. The boots that matter most here do not reboot:
# every terminal path in the installer respawns a console shell forever (PID 1
# must never exit), so those runs would sit until the timeout expired. Waiting out
# three 2-minute timeouts to observe a banner that printed in twenty seconds makes
# the harness too slow to use while editing /init, so a STOP_REGEX ends the boot
# as soon as the state under test is on the console. The timeout stays as the
# backstop for "the marker never appeared".
boot() {
	local logf=$1 tmo=$2 extra=${3:-} stop=${4:-} qpid waited=0
	: > "$logf"
	qemu-system-arm -M virt -m "$QEMU_MEM" -nographic -no-reboot \
		-kernel "$IQK_ZIMAGE" \
		-drive file="$DISK",format=raw,if=none,id=sd0 \
		-device virtio-blk-device,drive=sd0 \
		-append "console=ttyAMA0,115200 loglevel=4 root=/dev/vda1 $extra" \
		>"$logf" 2>&1 &
	qpid=$!
	while kill -0 "$qpid" 2>/dev/null; do
		if [ -n "$stop" ] && grep -qE "$stop" "$logf" 2>/dev/null; then
			# One more second so the rest of the banner lands in the log before
			# we pull the machine out from under it.
			sleep 1
			kill "$qpid" 2>/dev/null || true
			break
		fi
		if [ "$waited" -ge "$tmo" ]; then
			kill -9 "$qpid" 2>/dev/null || true
			break
		fi
		sleep 1
		waited=$(( waited + 1 ))
	done
	wait "$qpid" 2>/dev/null || true
}

# ---------------------------------------------------------------- host checks
# assert_bootloader_present DESC -- the 0xA2 partition holds uboot.img verbatim.
# This is the claim the whole reorder rests on: after sfdisk the card must be able
# to reach U-Boot again within seconds, not only at the end of the install.
assert_bootloader_present() {
	local dump p2_start ubsz
	dump=$(sfdisk -d "$DISK" 2>/dev/null)
	p2_start=$(printf '%s\n' "$dump" | sed -n '/img2 /s/.*start=[[:space:]]*\([0-9]*\).*/\1/p')
	if [ -z "$p2_start" ]; then fail "$1 (no second partition in the table)"; return; fi
	ubsz=$(stat -c %s "$UBOOT_REF")
	dd if="$DISK" bs=512 skip="$p2_start" count=$(( ubsz / 512 + 1 )) 2>/dev/null |
		head -c "$ubsz" > "$WORK/p2head.bin"
	if cmp -s "$WORK/p2head.bin" "$UBOOT_REF"; then pass "$1"; else fail "$1 (0xA2 head != uboot.img)"; fi
}

assert_exfat_p1() {
	local dump p1_start p1_type sig
	dump=$(sfdisk -d "$DISK" 2>/dev/null)
	p1_start=$(printf '%s\n' "$dump" | sed -n '/img1 /s/.*start=[[:space:]]*\([0-9]*\).*/\1/p')
	p1_type=$(printf '%s\n'  "$dump" | sed -n '/img1 /s/.*type=[[:space:]]*\([0-9A-Fa-f]*\).*/\1/p')
	eq "$p1_type" "7" "$1: p1 is type 7 (exFAT)"
	sig=$(dd if="$DISK" bs=1 skip=$(( p1_start * 512 + 3 )) count=8 2>/dev/null | tr -d '\0 ')
	eq "$sig" "EXFAT" "$1: p1 carries the exFAT signature"
}

# order_ok A B DESC -- assert byte offset A comes before byte offset B.
# Byte offsets, not line numbers: the guest console is a tty, the splash rewrites
# its status line with \r, and several markers share a line.
# `|| true` is load-bearing: under `set -o pipefail` an ABSENT marker makes grep
# fail, which fails the pipeline, which -- captured into a variable -- would abort
# the whole harness under `set -e` instead of reporting the FAIL. An empty offset
# is exactly the answer order_ok wants.
at() { grep -abo -m1 "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1 || true; }
order_ok() {
	if [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; then pass "$3"; else fail "$3 (offsets '$1' vs '$2')"; fi
}

# ===========================================================================
scenario_clean_install() {
	log "--- 0. a clean install on a pristine (FAT32) card ----------------------"
	flash_fresh_card
	local dev_sectors; dev_sectors=$(( $(stat -c %s "$DISK") / 512 ))
	# The stop token IS on this cmdline, and this kernel has NO marker file. A
	# user really can get that token onto a real board's cmdline through
	# u-boot.txt's $v, so "the installer ignores it" has to be a test, not a
	# claim: if the gate regressed to trusting the cmdline, the install below
	# would stop at payload-copied instead of finishing.
	boot "$WORK/z1.log" "$INSTALL_TIMEOUT" "mister_installer_stop_after=payload-copied"
	has   "$WORK/z1.log" 'this is not a test image' "0: the cmdline hook was refused (no initramfs marker)"
	hasnt "$WORK/z1.log" 'TEST-STOP'                "0: and it did not stop"
	has   "$WORK/z1.log" 'source mounted (vfat)'  "0: the shipped FAT32 partition mounted as vfat"
	has   "$WORK/z1.log" 'INSTALL COMPLETE'       "0: the install finished"
	hasnt "$WORK/z1.log" 'INSTALLER: FAILED'      "0: no failure banner"
	hasnt "$WORK/z1.log" 'not found'              "0: no missing-applet noise on the console"
	has   "$WORK/z1.log" 'removed linux/linux.img.gz'  "0: the compressed image was deleted, not truncated"
	has   "$WORK/z1.log" "removed mister-payload/ from" "0: the staged payload dir was cleaned up"

	# The ORDER is the point of the change, so assert it rather than the mere
	# presence of each step. These are the same markers scripts/test-sdcard-install.sh
	# greps for against the shipped card; keep the two in step.
	local o_part o_uboot o_mkfs o_recov o_payload o_commit
	o_part=$(at    "$WORK/z1.log" 'new partitions present')
	o_uboot=$(at   "$WORK/z1.log" 'the card can reach U-Boot again')
	o_mkfs=$(at    "$WORK/z1.log" 'formatting (exFAT)')
	o_recov=$(at   "$WORK/z1.log" 'from here a power cut re-runs the installer')
	o_payload=$(at "$WORK/z1.log" 'this card can now finish on its own')
	o_commit=$(at  "$WORK/z1.log" 'this card is a MiSTer now')
	order_ok "$o_part"    "$o_uboot"   "0: uboot.img lands right after the repartition, not at the end"
	order_ok "$o_uboot"   "$o_mkfs"    "0: the bootloader is written BEFORE the filesystem is made"
	order_ok "$o_mkfs"    "$o_recov"   "0: the installer kernel is restored right after the format"
	order_ok "$o_recov"   "$o_payload" "0: the card is self-recovering before the payload copy-back"
	order_ok "$o_payload" "$o_commit"  "0: the real kernel is the LAST thing installed (the commit point)"

	# And the finished geometry, host-side.
	local dump p1_start p1_size p2_size p2_type
	dump=$(sfdisk -d "$DISK" 2>/dev/null)
	p1_start=$(printf '%s\n' "$dump" | sed -n '/img1 /s/.*start=[[:space:]]*\([0-9]*\).*/\1/p')
	p1_size=$(printf '%s\n'  "$dump" | sed -n '/img1 /s/.*size=[[:space:]]*\([0-9]*\).*/\1/p')
	p2_size=$(printf '%s\n'  "$dump" | sed -n '/img2 /s/.*size=[[:space:]]*\([0-9]*\).*/\1/p')
	p2_type=$(printf '%s\n'  "$dump" | sed -n '/img2 /s/.*type=[[:space:]]*\([0-9A-Fa-f]*\).*/\1/p')
	eq "$p1_start" "$P1_START_SECTORS" "0: p1 starts at LBA $P1_START_SECTORS"
	eq "$p2_type"  "a2"                "0: p2 is type a2 (SPL boot)"
	eq "$p2_size"  "$RESERVED_SECTORS" "0: p2 is exactly RESERVED_SECTORS"
	if [ -n "$p1_size" ] && [ $(( p1_start + p1_size + p2_size )) -eq "$dev_sectors" ]; then
		pass "0: p1 auto-expanded to fill the card"
	else
		fail "0: partitions do not fill the card ($p1_start+$p1_size+$p2_size != $dev_sectors)"
	fi
	assert_exfat_p1 "0"
	assert_bootloader_present "0: the finished card has uboot.img in its 0xA2 partition"
}

scenario_interrupted_after_payload() {
	log "--- A. interrupted right after the payload copy-back -------------------"
	flash_fresh_card
	boot "$WORK/a1.log" "$INSTALL_TIMEOUT" "mister_installer_stop_after=payload-copied"
	has   "$WORK/a1.log" 'TEST-STOP after "payload-copied"' "A: the run stopped where we asked it to"
	hasnt "$WORK/a1.log" 'INSTALL COMPLETE'                 "A: the interrupted run did NOT finish"
	hasnt "$WORK/a1.log" 'INSTALLER: FAILED'                "A: the interrupted run did not fail either"
	# The two facts a real U-Boot would need at this instant.
	assert_bootloader_present "A: uboot.img is ALREADY in the 0xA2 partition at the interrupt"
	assert_exfat_p1 "A"

	log "    re-booting the interrupted card (it must finish on its own) ..."
	boot "$WORK/a2.log" "$INSTALL_TIMEOUT"
	# It found ITS OWN kernel on the card -- i.e. a real board would have booted
	# the installer here rather than nothing.
	has   "$WORK/a2.log" 'installer kernel staged in RAM'   "A: the card still carried the installer kernel"
	hasnt "$WORK/a2.log" 'no linux/zImage_dtb at the card root' "A: no missing-installer-kernel warning"
	hasnt "$WORK/a2.log" 'already provisioned'              "A: the provisioned guard did NOT misfire"
	hasnt "$WORK/a2.log" 'was INTERRUPTED'                  "A: not mistaken for a partial copy"
	hasnt "$WORK/a2.log" 'INSTALLER: FAILED'                "A: no failure banner on the recovery run"
	has   "$WORK/a2.log" 'this card is a MiSTer now'        "A: the recovery run reached the commit point"
	has   "$WORK/a2.log" 'INSTALL COMPLETE'                 "A: the recovery run finished, unattended"
	has   "$WORK/a2.log" 'per-board MAC = '                 "A: the recovery run still wrote a per-board MAC"
	assert_bootloader_present "A: the finished card has uboot.img in its 0xA2 partition"

	log "--- D. the finished card still trips the provisioned guard -------------"
	boot "$WORK/d1.log" "$HALT_TIMEOUT" "" 'already provisioned'
	has   "$WORK/d1.log" 'already provisioned'  "D: re-run guard tripped on the finished card"
	hasnt "$WORK/d1.log" 'INSTALLER: FAILED'    "D: the benign halt did not print the FAILED banner"
	hasnt "$WORK/d1.log" 'INSTALL COMPLETE'     "D: the benign halt did not claim an install"
}

scenario_interrupted_after_expand() {
	log "--- E. interrupted after linux.img was expanded ------------------------"
	# THE case the re-keyed guard exists for (ADR 0020 §8.4). At this point the
	# card is exFAT, labelled MiSTer_Data, and HAS linux/linux.img -- all three
	# conditions the OLD guard used -- while its linux/zImage_dtb is still the
	# installer's and a complete payload is sitting right there. The old guard
	# would have called this card "installed" and halted on it. Scenario A cannot
	# catch that: it stops BEFORE the zcat, so no linux.img exists and the old
	# guard would not have fired either.
	flash_fresh_card
	boot "$WORK/e1.log" "$INSTALL_TIMEOUT" "mister_installer_stop_after=expanded"
	has   "$WORK/e1.log" 'TEST-STOP after "expanded"' "E: the run stopped after the expansion"
	hasnt "$WORK/e1.log" 'INSTALL COMPLETE'           "E: the interrupted run did NOT finish"

	log "    re-booting (the old guard would have called this card installed) ..."
	boot "$WORK/e2.log" "$INSTALL_TIMEOUT"
	hasnt "$WORK/e2.log" 'already provisioned' "E: the re-keyed guard did NOT misfire on a mid-commit card"
	hasnt "$WORK/e2.log" 'INSTALLER: FAILED'   "E: no failure banner"
	has   "$WORK/e2.log" 'INSTALL COMPLETE'    "E: it finished the install instead"
}

scenario_interrupted_after_bootloader() {
	log "--- F. interrupted between sfdisk and mkfs.exfat -----------------------"
	# Worth its own scenario because the answer is better than it looks. sfdisk
	# only rewrites the MBR, and the new p1 still starts at LBA 2048, so the
	# SHIPPED FAT32 filesystem -- installer kernel, payload and all -- is still
	# sitting there, readable under the enlarged partition entry. An interrupt
	# here is therefore FULLY recoverable, which is why the header puts the hard
	# window at mkfs.exfat and not at sfdisk.
	flash_fresh_card
	boot "$WORK/f1.log" "$INSTALL_TIMEOUT" "mister_installer_stop_after=bootloader"
	has   "$WORK/f1.log" 'TEST-STOP after "bootloader"' "F: the run stopped after the bootloader write"
	hasnt "$WORK/f1.log" 'formatting (exFAT)'           "F: it stopped BEFORE mkfs.exfat"
	assert_bootloader_present "F: uboot.img is in the new 0xA2 partition already"

	log "    re-booting the repartitioned-but-unformatted card ..."
	boot "$WORK/f2.log" "$INSTALL_TIMEOUT"
	has   "$WORK/f2.log" 'source mounted (vfat)' "F: the shipped FAT32 survived the repartition"
	hasnt "$WORK/f2.log" 'INSTALLER: FAILED'     "F: no failure banner"
	has   "$WORK/f2.log" 'INSTALL COMPLETE'      "F: the install simply ran again and finished"
}

scenario_interrupted_mid_copy() {
	log "--- B. interrupted mid copy-back ---------------------------------------"
	flash_fresh_card
	boot "$WORK/b1.log" "$INSTALL_TIMEOUT" "mister_installer_stop_after=payload-partial"
	has   "$WORK/b1.log" 'TEST-STOP after "payload-partial"' "B: the run stopped mid-copy"
	hasnt "$WORK/b1.log" 'this card can now finish on its own' "B: the payload dir was never renamed"
	assert_bootloader_present "B: uboot.img is in the 0xA2 partition even here"

	log "    re-booting the mid-copy card (it must halt honestly) ..."
	boot "$WORK/b2.log" "$HALT_TIMEOUT" "" 'Dropping to a console shell'
	has   "$WORK/b2.log" 'was INTERRUPTED'         "B: the honest interrupted-install banner drew"
	has   "$WORK/b2.log" 'mister-payload.part'     "B: the banner names the partial directory"
	has   "$WORK/b2.log" 're-flash sdcard.img'     "B: the banner gives the recovery instruction"
	hasnt "$WORK/b2.log" 'INSTALL COMPLETE'        "B: it did not claim to have installed anything"
	hasnt "$WORK/b2.log" 'already provisioned'     "B: it did not call a half-copied card installed"
	hasnt "$WORK/b2.log" 'repartitioning the card' "B: it did NOT reformat a card it cannot install to"
}

scenario_interrupted_at_recoverable() {
	log "--- C. interrupted the instant the card became recoverable -------------"
	flash_fresh_card
	boot "$WORK/c1.log" "$INSTALL_TIMEOUT" "mister_installer_stop_after=recoverable"
	has "$WORK/c1.log" 'TEST-STOP after "recoverable"' "C: the run stopped just after the kernel restore"
	has "$WORK/c1.log" 'from here a power cut re-runs the installer' "C: the installer kernel was written first"
	assert_bootloader_present "C: uboot.img was already written at that point"
	assert_exfat_p1 "C"

	log "    re-booting (no payload on the card: it must stop, not reformat) ..."
	boot "$WORK/c2.log" "$HALT_TIMEOUT" "" 'Dropping to a rescue shell'
	has   "$WORK/c2.log" 'INSTALLER: FAILED'        "C: it reported the card as not installable"
	has   "$WORK/c2.log" 'interrupted before the payload was copied' "C: with the accurate reason"
	hasnt "$WORK/c2.log" 'repartitioning the card'  "C: it did NOT reformat with no payload"
	hasnt "$WORK/c2.log" 'INSTALL COMPLETE'         "C: it did not claim an install"
}

# ============================================================================
main() {
	# Kernel 1: NO test-hook marker. Scenario 0 runs on this one, which is what
	# makes its "the cmdline alone does nothing" assertion mean anything.
	IQK_EXTRA_INITRAMFS=""
	iqk_ensure_kernel
	build_synth_card
	scenario_clean_install

	# Kernel 2: same installer cpio with /.installer-test-hook appended as a
	# second archive, so stop_after() will act. Rebuilding is ~a minute and it is
	# the price of the hook not being reachable from a real card.
	log "rebuilding the test kernel WITH the /.installer-test-hook marker ..."
	mkdir -p "$WORK/hook" && : > "$WORK/hook/.installer-test-hook"
	IQK_EXTRA_INITRAMFS="$WORK/hook"
	iqk_ensure_kernel

	scenario_interrupted_after_payload
	scenario_interrupted_after_expand
	scenario_interrupted_after_bootloader
	scenario_interrupted_mid_copy
	scenario_interrupted_at_recoverable

	echo
	if [ "$FAILED" -eq 0 ]; then
		log "ALL CHECKS PASSED -- an interrupted install either finishes itself or says why it cannot."
		return 0
	fi
	log "one or more checks FAILED (see above). Logs: $WORK"
	trap - EXIT
	return 1
}

main "$@"
