#!/usr/bin/env bash
#
# test-sdcard-install-de25.sh — run the DE25-Nano first-boot installer in QEMU on the
# built sdcard-de25.img and check the card it leaves (docs/de25-sdcard.md §3).
#
# Boots `qemu-system-aarch64 -M virt` with the test kernel scripts/test-initramfs.sh
# builds around THIS build's mister-initramfs.cpio, the card as a virtio disk:
#   1. a fresh card with a pre-seeded wpa_supplicant.conf, power cut mid-install;
#   2. the next boot resumes and finishes; the host then checks the MBR, that p1 is
#      byte-identical to the shipped image's, the flag is gone and the exFAT is clean;
#   3. a normal boot: stage 1 mounts the exFAT p2, loop-mounts linux.img, switch_roots;
#   4. a shell boot that compares linux.img with p1's payload and reads the pre-seed.
# Not the board's kernel, SD controller or U-Boot: the installer's logic, on the real payload.
#
# Prereqs: `make de25`, then `scripts/test-initramfs.sh --board de25nano` (builds the
# QEMU kernel this uses); qemu-system-aarch64, sfdisk, mcopy, fsck.exfat, cmp.
# Env: DE25_SDCARD_IMG, DE25_TEST_CARD_SIZE (default 2G), DE25_INSTALL_TIMEOUT (default 900).
# shellcheck disable=SC2015  # ok() and bad() always succeed, so A && ok || bad is an if/else
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IMG="${DE25_SDCARD_IMG:-$ROOT/output-de25/images/sdcard-de25.img}"
CPIO="$ROOT/output-de25/images/mister-initramfs.cpio"
FLAG_BIN="$ROOT/output-de25/images/mister-install-flag.bin"
KERNEL="${TEST_INITRAMFS_KBUILD:-$ROOT/work/test-initramfs-de25-kbuild}/arch/arm64/boot/Image"
CARD_SIZE="${DE25_TEST_CARD_SIZE:-2G}"
INSTALL_TIMEOUT="${DE25_INSTALL_TIMEOUT:-900}"
WORK="$ROOT/work/test-sdcard-install-de25"
CMDLINE="console=ttyAMA0,115200 root=/dev/vda2 loop=linux/linux.img ro rootwait"

fail=0
log()  { printf '[de25-install] %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }
die()  { printf 'test-sdcard-install-de25.sh: FATAL: %s\n' "$*" >&2; exit 2; }
need() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (no '$2' in ${1#"$ROOT"/})"; }
lacks() { grep -qF -- "$2" "$1" && bad "$3 ('$2' in ${1#"$ROOT"/})" || ok "$3"; }

for t in qemu-system-aarch64 sfdisk mcopy fsck.exfat cmp timeout; do
	command -v "$t" >/dev/null 2>&1 || die "'$t' not found"
done
[ -f "$IMG" ] || die "no $IMG -- run 'make de25'"
[ -f "$FLAG_BIN" ] || die "no $FLAG_BIN -- run 'make de25'"
[ -f "$KERNEL" ] || die "no QEMU kernel at $KERNEL -- run 'scripts/test-initramfs.sh --board de25nano'"
[ "$KERNEL" -nt "$CPIO" ] ||
	die "$KERNEL is older than $CPIO, so it embeds a stale stage 1 -- re-run scripts/test-initramfs.sh --board de25nano"

rm -rf "$WORK"; mkdir -p "$WORK"
CARD="$WORK/card.img"

# part N FIELD -- start/size/type of MBR entry N of $1, from sfdisk -d.
part() {
	sfdisk -d "$1" 2>/dev/null | grep -E "^[^ ]+$2 *:" | sed -n "s/.*$3= *\([^, ]*\).*/\1/p"
}
qemu() {  # qemu LOG [extra qemu args...] -- boots $CARD; output to LOG
	local logf=$1; shift
	timeout -k 10 "$INSTALL_TIMEOUT" qemu-system-aarch64 -M virt -cpu cortex-a76 -m 1024 \
		-nographic -no-reboot -kernel "$KERNEL" \
		-drive file="$CARD",format=raw,if=none,id=sd0 -device virtio-blk-device,drive=sd0 \
		"$@" > "$logf" 2>&1 || true
}

log "card: $CARD_SIZE sparse, with ${IMG#"$ROOT"/} at its start"
truncate -s "$CARD_SIZE" "$CARD"
dd if="$IMG" of="$CARD" bs=4M conv=notrunc,sparse status=none
p1_start=$(part "$CARD" 1 start); p1_size=$(part "$CARD" 1 size)
p2_start=$(part "$CARD" 2 start)
card_sectors=$(( $(stat -c %s "$CARD") / 512 ))
printf 'ssid="mister-test"\n' > "$WORK/wpa_supplicant.conf"
MTOOLS_SKIP_CHECK=1 mcopy -i "$CARD@@$((p2_start * 512))" "$WORK/wpa_supplicant.conf" ::wpa_supplicant.conf
ok "pre-seeded wpa_supplicant.conf onto the setup volume"

# --- 1. fresh install, power cut while linux.img expands ---------------------------
log "boot 1: fresh install, cut power during the expand"
L1="$WORK/boot1.log"
( timeout -k 10 "$INSTALL_TIMEOUT" qemu-system-aarch64 -M virt -cpu cortex-a76 -m 1024 \
	-nographic -no-reboot -kernel "$KERNEL" \
	-drive file="$CARD",format=raw,if=none,id=sd0 -device virtio-blk-device,drive=sd0 \
	-append "$CMDLINE" > "$L1" 2>&1 || true ) &
qpid=$!
for _ in $(seq 1 "$INSTALL_TIMEOUT"); do
	grep -q 'expanding linux.img' "$L1" 2>/dev/null && break
	kill -0 "$qpid" 2>/dev/null || break
	sleep 1
done
sleep 2
pkill -KILL -f "file=$CARD," 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
need "$L1" 'first-boot installer flag found' "boot 1: stage 1 handed the armed card to the installer"
need "$L1" 'card state: fresh' "boot 1: the installer saw a fresh card"
need "$L1" 'pre-seed: captured wpa_supplicant.conf' "boot 1: the pre-seed was captured"
need "$L1" 'to the end of the card' "boot 1: p2 was grown to the card"
need "$L1" 'expanding linux.img' "boot 1: reached the expand (then the power was cut)"
lacks "$L1" 'installer flag spent' "boot 1: the cut came before the commit point"
[ "$(part "$CARD" 3 type)" = da ] && dd if="$CARD" bs=512 skip=1024 count=1 status=none | cmp -s - "$FLAG_BIN" &&
	ok "after the cut the flag is still armed" || bad "after the cut the flag is not armed"

# --- 2. the next boot resumes and finishes ------------------------------------------
log "boot 2: resume"
L2="$WORK/boot2.log"
qemu "$L2" -append "$CMDLINE"
need "$L2" 'card state: resume' "boot 2: the interrupted install was recognised"
need "$L2" 'installer flag spent' "boot 2: the install reached the commit point"
need "$L2" 'rebooting into MiSTer' "boot 2: the installer rebooted"
lacks "$L2" 'INSTALLER: FAILED' "boot 2: no installer failure banner"

[ "$(part "$CARD" 1 type)" = 1c ] && [ "$(part "$CARD" 1 start)" = "$p1_start" ] &&
	[ "$(part "$CARD" 1 size)" = "$p1_size" ] && sfdisk -d "$CARD" | grep -E '^[^ ]+1 *:' | grep -q bootable &&
	ok "entry 1 is unchanged (0x1c, bootable, same start and size)" || bad "entry 1 changed"
[ "$(part "$CARD" 2 type)" = 7 ] && [ "$(part "$CARD" 2 start)" = "$p2_start" ] &&
	[ "$(part "$CARD" 2 size)" = $((card_sectors - p2_start)) ] &&
	ok "entry 2 is 0x07 from LBA $p2_start to the end of the card" ||
	bad "entry 2 is $(part "$CARD" 2 type)/$(part "$CARD" 2 start)/$(part "$CARD" 2 size)"
[ -z "$(part "$CARD" 3 type)" ] && ok "entry 3 (the flag) is gone" || bad "entry 3 is still in the MBR"
dd if="$CARD" bs=512 skip=1024 count=1 status=none | cmp -s - <(head -c 512 /dev/zero) &&
	ok "the flag sector is spent" || bad "the flag sector is not zero"
cmp -s <(dd if="$IMG" bs=512 skip="$p1_start" count="$p1_size" status=none) \
	<(dd if="$CARD" bs=512 skip="$p1_start" count="$p1_size" status=none) &&
	ok "p1 is byte-identical to the shipped image's (the installer never wrote it)" ||
	bad "p1 differs from the shipped image's"
dd if="$CARD" of="$WORK/p2.img" bs=4M iflag=skip_bytes skip=$((p2_start * 512)) conv=sparse status=none
fsck.exfat -n "$WORK/p2.img" > "$WORK/fsck.log" 2>&1 && ok "p2 is a clean exFAT (fsck.exfat -n)" ||
	{ bad "fsck.exfat -n on p2 failed"; sed 's/^/    /' "$WORK/fsck.log" >&2; }
grep -q 'MiSTer_Data' <(blkid -p -o value -s LABEL "$WORK/p2.img" 2>/dev/null) &&
	ok "p2 is labelled MiSTer_Data" || bad "p2 is not labelled MiSTer_Data"
rm -f "$WORK/p2.img"

# --- 3. a normal boot ----------------------------------------------------------------
log "boot 3: normal boot"
L3="$WORK/boot3.log"
( qemu "$L3" -append "$CMDLINE" ) &
qpid=$!
for _ in $(seq 1 120); do grep -q 'switching root' "$L3" 2>/dev/null && break; sleep 1; done
sleep 1
pkill -KILL -f "file=$CARD," 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
lacks "$L3" '[installer]' "boot 3: the installer did not run"
need "$L3" 'data partition mounted as exfat' "boot 3: stage 1 mounted p2 as exFAT"
need "$L3" '/media/fat = /dev/vda2 (exfat)' "boot 3: /media/fat is p2"
need "$L3" 'switching root' "boot 3: stage 1 loop-mounted linux.img and switched root"

# --- 4. look inside ------------------------------------------------------------------
log "boot 4: inspect p2 from a stage-1 shell"
L4="$WORK/boot4.log"
# stdin is a FIFO held open: EOF on the console would end ash, and PID 1 with it.
fifo="$WORK/console.fifo"; mkfifo "$fifo"
qemu-system-aarch64 -M virt -cpu cortex-a76 -m 1024 -nographic -no-reboot -kernel "$KERNEL" \
	-drive file="$CARD",format=raw,if=none,id=sd0 -device virtio-blk-device,drive=sd0 \
	-append "console=ttyAMA0,115200 rdinit=/bin/sh" < "$fifo" > "$L4" 2>&1 &
qpid=$!
exec {fifo_fd}>"$fifo"
for _ in $(seq 1 60); do grep -q 'BusyBox.*built-in shell' "$L4" 2>/dev/null && break; sleep 1; done
sleep 1
# shellcheck disable=SC2016  # guest script text: the guest expands it
printf '%s\n' \
	'mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev' \
	'i=0; while [ ! -b /dev/vda2 ] && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done' \
	'mkdir -p /m1 /m2; mount -t vfat -o ro /dev/vda1 /m1; mount -t exfat -o ro /dev/vda2 /m2' \
	'zcat /m1/mister-payload/linux/linux.img.gz | cmp - /m2/linux/linux.img && echo CHECK-IMG-SAME' \
	'cat /m2/linux/wpa_supplicant.conf' \
	'[ -e /m2/linux/.mister-install-in-progress ] || echo CHECK-NO-TOKEN' \
	'[ -e /m2/linux/.mister-preseed ] || echo CHECK-NO-PRESEED-DIR' \
	'[ -e /m2/linux/linux.img.gz ] || echo CHECK-NO-GZ' \
	'echo CHECK-DONE' >&"$fifo_fd"
for _ in $(seq 1 300); do grep -q '^CHECK-DONE' "$L4" 2>/dev/null && break; sleep 1; done
printf 'reboot -f\n' >&"$fifo_fd"
sleep 2
exec {fifo_fd}>&-
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true
need "$L4" 'CHECK-IMG-SAME' "linux/linux.img on p2 equals the payload on p1 (= rootfs.ext4, per check-sdcard-de25.sh)"
need "$L4" 'ssid="mister-test"' "the pre-seeded wpa_supplicant.conf landed in linux/"
need "$L4" 'CHECK-NO-TOKEN' "the in-progress token is gone"
need "$L4" 'CHECK-NO-PRESEED-DIR' "the pre-seed staging dir is gone"
need "$L4" 'CHECK-NO-GZ' "no linux.img.gz was left on p2"

if [ "$fail" -eq 0 ]; then
	log "PASS (logs in ${WORK#"$ROOT"/})"
else
	log "FAIL (logs in ${WORK#"$ROOT"/})"
fi
exit "$fail"
