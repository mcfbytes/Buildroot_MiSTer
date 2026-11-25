#!/usr/bin/env bash
# QEMU test of the DE25 ext4 card's first-boot grow (S00growroot, docs/de25-sdcard.md §1).
# Boot 1 grows p2 and its ext4 to a 2G card; boot 2 must change nothing.
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IMG="${DE25_SDCARD_EXT4_IMG:-$ROOT/output-de25/images/sdcard-de25-ext4.img}"
KERNEL="${TEST_INITRAMFS_KBUILD:-$ROOT/work/test-initramfs-de25-kbuild}/arch/arm64/boot/Image"
CARD_SIZE="${DE25_TEST_CARD_SIZE:-2G}"
BOOT_TIMEOUT="${DE25_BOOT_TIMEOUT:-300}"
WORK="$ROOT/work/test-sdcard-ext4-de25"
CMDLINE="console=ttyAMA0,115200 root=/dev/vda2 rw rootwait"

fail=0
log()  { printf '[de25-ext4] %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }
die()  { printf 'test-sdcard-ext4-de25.sh: FATAL: %s\n' "$*" >&2; exit 2; }

for t in qemu-system-aarch64 sfdisk dumpe2fs e2fsck timeout; do
	command -v "$t" >/dev/null 2>&1 || die "'$t' not found"
done
[ -f "$IMG" ] || die "no $IMG -- run 'make de25'"
[ -f "$KERNEL" ] || die "no QEMU kernel at $KERNEL -- run 'scripts/test-initramfs.sh --board de25nano'"

rm -rf "$WORK"; mkdir -p "$WORK"
CARD="$WORK/card.img"
part() { sfdisk -d "$1" 2>/dev/null | grep -E "^[^ ]+$2 *:" | sed -n "s/.*$3= *\([^, ]*\).*/\1/p"; }

# boot LOG -- boots $CARD until S00growroot has run (or the timeout), then cuts power.
boot() {
	local logf=$1
	timeout -k 10 "$BOOT_TIMEOUT" qemu-system-aarch64 -M virt -cpu cortex-a76 -m 1024 \
		-nographic -no-reboot -kernel "$KERNEL" \
		-drive file="$CARD",format=raw,if=none,id=sd0 -device virtio-blk-device,drive=sd0 \
		-append "$CMDLINE" > "$logf" 2>&1 &
	local qpid=$! n=0
	while kill -0 "$qpid" 2>/dev/null; do
		if grep -qE 'growroot: (done|.*failed)|Starting syslogd|S01syslogd' "$logf"; then
			sleep 3; sync; break
		fi
		n=$((n + 1)); [ "$n" -lt "$BOOT_TIMEOUT" ] || break
		sleep 1
	done
	kill "$qpid" 2>/dev/null || true; wait "$qpid" 2>/dev/null || true
}

log "card: $CARD_SIZE sparse, with ${IMG#"$ROOT"/} at its start"
truncate -s "$CARD_SIZE" "$CARD"
dd if="$IMG" of="$CARD" bs=4M conv=notrunc,sparse status=none
card_sectors=$(( $(stat -c %s "$CARD") / 512 ))
p1_before=$(sfdisk -d "$CARD" | grep -E '^[^ ]+1 *:')

log "boot 1: first boot grows the root"
boot "$WORK/boot1.log"
grep -q 'growroot: growing partition 2' "$WORK/boot1.log" && ok "boot 1: the partition grow ran" || bad "boot 1: no partition grow in the log"
grep -q 'growroot: growing the ext4' "$WORK/boot1.log" && ok "boot 1: the filesystem grow ran" || bad "boot 1: no filesystem grow in the log"
grep -q 'growroot: done' "$WORK/boot1.log" && ok "boot 1: growroot reported done" || bad "boot 1: growroot did not report done"
grep -q 'growroot:.*failed' "$WORK/boot1.log" && bad "boot 1: growroot reported a failure" || ok "boot 1: no growroot failure"

p2_start=$(part "$CARD" 2 start); p2_size=$(part "$CARD" 2 size)
[ $(( p2_start + p2_size )) -eq "$card_sectors" ] && ok "entry 2 ends at the end of the card" ||
	bad "entry 2 ends at $(( p2_start + p2_size )), the card has $card_sectors sectors"
[ "$(sfdisk -d "$CARD" | grep -E '^[^ ]+1 *:')" = "$p1_before" ] && ok "entry 1 is unchanged" || bad "entry 1 changed"

dd if="$CARD" of="$WORK/p2.ext4" bs=512 skip="$p2_start" count="$p2_size" status=none
e2fsck -fy "$WORK/p2.ext4" > "$WORK/e2fsck.log" 2>&1 && ok "p2 is fsck-clean after the power cut" || {
	rc=$?; [ "$rc" -le 1 ] && ok "p2 is clean after journal replay (e2fsck exit $rc)" || bad "e2fsck exit $rc on p2"; }
blocks=$(dumpe2fs -h "$WORK/p2.ext4" 2>/dev/null | sed -n 's/^Block count:[[:space:]]*//p')
bsize=$(dumpe2fs -h "$WORK/p2.ext4" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')
slack=$(( p2_size * 512 - blocks * bsize ))
[ "$slack" -le 1048576 ] && ok "the ext4 fills p2 (slack $slack bytes)" || bad "the ext4 leaves $slack bytes of p2 unused"
rm -f "$WORK/p2.ext4"

log "boot 2: nothing left to grow"
boot "$WORK/boot2.log"
grep -q 'growroot: growing' "$WORK/boot2.log" && bad "boot 2: growroot grew again" || ok "boot 2: growroot did nothing"
grep -q 'S01syslogd\|syslogd' "$WORK/boot2.log" && ok "boot 2: userland reached the init scripts" ||
	bad "boot 2: userland never reached the init scripts (see ${WORK#"$ROOT"/}/boot2.log)"

[ "$fail" -eq 0 ] && log "PASS (logs in ${WORK#"$ROOT"/})" || log "FAIL (logs in ${WORK#"$ROOT"/})"
exit "$fail"
