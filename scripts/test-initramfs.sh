#!/usr/bin/env bash
#
# scripts/test-initramfs.sh — CI-runnable QEMU boot test of the initramfs /init
# (TASKS.md P1.12; constraint A7; docs/decisions/0002-initramfs.md §8).
#
# QEMU has no Cyclone V (or Agilex 5) SoC machine model, so this cannot boot
# either board's product kernel. What it CAN do, and what /init actually
# needs proven, is boot the REAL, unmodified stage-1 cpio inside a generic
# `-M virt` kernel, attach a synthetic MBR disk shaped like a real MiSTer SD
# card (a FAT/exFAT data partition containing linux/linux.img), and assert --
# from INSIDE the switched-root system -- every invariant /init is supposed
# to have established. Eight cases:
#
#   fat32      FAT32 card:  exfat probe fails, falls back to vfat (utf8=1)
#   exfat      exFAT card:  mounts on the first try
#   fsck-request  exFAT card carrying linux/.fsck-request: the on-demand repair
#              path (ADR 0026) -- marker deleted before the repair (exactly
#              once), unmount BEFORE fsck.exfat -p (its O_RDWR|O_EXCL cannot
#              open a mounted device), remount with the same sync,dirsync opts
#   symlink    exFAT card:  Samsung-format symlinks work end-to-end on the
#              mainline exfat driver + board patch 0031 (ADR 0019), including
#              the create+unlink cluster-leak regression fsck cannot see
#   label      root=LABEL=MISTERDATA, resolved via BusyBox findfs
#   nonascii   FAT32 card with a non-ASCII long filename -- byte-for-byte
#              round trip through the vfat utf8=1 path (ADR 0010)
#   missing-image   linux/linux.img absent -> rescue shell, never a panic
#   rootwait   root= never appears -> rescue shell after the wait, never a panic
#
# Lifted and productionized from work/p1.10-qemu/run-test.sh (P1.10's own
# throwaway verification harness, ADR 0002 §8: "P1.12 should lift it"). The
# `nonascii` case is new: P1.10 never exercised a non-ASCII filename, and the
# maintainer's own SD card is exFAT with zero non-ASCII filenames across every
# entry on it, so this synthetic test is the only place that regression can
# ever be caught (see the case function below for the full argument).
#
# Usage: scripts/test-initramfs.sh [--board de10nano|de25nano] [--kernel default|rt] [case ...]
#   With no case arguments, runs all eight cases. Exit 0 iff every requested
#   case passed; nonzero otherwise (wired for P4.1's CI job).
#
# TWO BOARDS, ONE /init (ADR 0029 D11, 2026-09-06). The stage-1 /init is
# arch-neutral and is built for both boards from the same fragment stack base
# (package/mister-initramfs, built by each board's own configuration); `--board` picks which built
# cpio to boot and which machine to boot it on:
#
#   de10nano (default)  output/images/mister-initramfs.cpio, armv7, on
#                       `qemu-system-arm -M virt` with a multi_v7_defconfig
#                       kernel at the DE10's pinned version.
#   de25nano            output-de25/images/mister-initramfs.cpio, aarch64, on
#                       `qemu-system-aarch64 -M virt -cpu cortex-a76` with a
#                       kernel built from the DE25's OWN product config
#                       (board/mister/de25nano/linux.config + the shared
#                       board/mister/common/linux-mister.fragment) at the
#                       DE25's pinned version, plus this harness's virtio/
#                       PL011 fragment. There is no arm64 "multi_v7" to lean
#                       on, and the product config is minimal enough to build
#                       in minutes -- so the DE25 leg also proves the product
#                       config's own exfat/vfat/loop/ext4 choices, which the
#                       DE10 leg deliberately does not (its product kernel
#                       cannot run under QEMU at all).
#
# ONE BOARD, TWO KERNEL SERIES (2026-09-11). `--kernel rt` (de10nano only)
# runs the same DE10 leg against the RT kernel's pin (BR2_PACKAGE_LINUX_RT_VERSION,
# 7.2.y) with the RT series' own re-anchored board patch 0031
# (board/mister/de10nano/linux-patches-beta/). 7.x exfat is iomap-based and
# 0031 had to be rewritten for it; the DE25 leg executes that rewrite on
# aarch64, but the DE10-Nano runs it as 32-bit ARM, which nothing else boots
# -- the first field `ln -s` on an RT-booted board Oopsed (page_symlink ->
# NULL write_begin, 2026-09-11, before the rewrite had shipped there). This
# leg is the 32-bit proof; its caches live under work/test-initramfs-rt*.
#
#   Every case, cmdline and assertion is identical between the two legs. The
#   cross compiler for the DE25 leg is the DE25 build's own glibc toolchain
#   (output-de25/host/bin), so `make de25` is the only
#   build prerequisite -- no `make de25` needed.
#
# Prerequisites (all checked explicitly, with an actionable message, before
# anything runs):
#   - `make mister-initramfs` (or `make de25`, with the DE25 stack enabling the extension) already run, so the cpio
#     exists
#   - the matching Buildroot cross toolchain on PATH or under the output dir
#     the board uses (arm-buildroot-linux-gnueabihf-gcc from output/host/bin;
#     aarch64-buildroot-linux-gnu-gcc from output-de25/host/bin)
#   - qemu-system-arm / qemu-system-aarch64, mkfs.vfat, mkfs.exfat, sfdisk,
#     mke2fs, cpio, mtools (mcopy, mmd)
#   - a QEMU-bootable test kernel: reused from a cache
#     (work/test-initramfs[-de25]-kbuild/) if present, else built fresh from
#     the pinned pristine source (dl/linux/linux-<pinned version>.tar.xz, the
#     tarball the Buildroot kernel build already fetched; or
#     work/linux-<pinned version>.tar.xz) and
#     scripts/test-initramfs/qemu-test-kernel.config -- see ensure_qemu_kernel().

set -uo pipefail  # deliberately not -e: run every requested case, then report

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SUPPORT="$HERE/test-initramfs"

# --- Board selection -------------------------------------------------------
# `--board` is consumed here, before any board-dependent path is derived; the
# remaining arguments are case names for main(). TEST_INITRAMFS_BOARD in the
# environment is the same switch for callers that cannot pass arguments
# (ci-tests.sh's per-board legs use the flag).
BOARD="${TEST_INITRAMFS_BOARD:-de10nano}"
# `--kernel` picks which of the board's kernel series the QEMU test kernel is
# built at: `default` (BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE, the shipped
# kernel) or `rt` (BR2_PACKAGE_LINUX_RT_VERSION with the RT series' own patch
# 0031). TEST_INITRAMFS_KERNEL is the environment form.
KERNEL="${TEST_INITRAMFS_KERNEL:-default}"
_args=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--board) shift; BOARD="${1:-}" ;;
		--board=*) BOARD="${1#--board=}" ;;
		--kernel) shift; KERNEL="${1:-}" ;;
		--kernel=*) KERNEL="${1#--kernel=}" ;;
		*) _args+=("$1") ;;
	esac
	shift
done
set -- ${_args[@]+"${_args[@]}"}

case "$BOARD" in
de10nano)
	CPIO="$ROOT/output/images/mister-initramfs.cpio"
	CPIO_MAKE_TARGET="mister-initramfs"
	KARCH=arm
	CROSS_COMPILE="${CROSS_COMPILE:-arm-buildroot-linux-gnueabihf-}"
	TOOLCHAIN_BIN="$ROOT/output/host/bin"
	QEMU_SYSTEM=qemu-system-arm
	QEMU_MACHINE=(-M virt)
	KERNEL_IMAGE_TARGET=zImage
	KERNEL_IMAGE_REL=arch/arm/boot/zImage
	# The generic ARM kernel: multi_v7_defconfig + this harness's fragment.
	KERNEL_BASE_DEFCONFIG=multi_v7_defconfig
	KERNEL_BASE_FILES=()
	PIN_FRAGMENT="$ROOT/configs/mister_de10nano_defconfig"
	PIN_SYMBOL=BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE
	EXFAT_SYMLINK_PATCH="$ROOT/board/mister/de10nano/linux-patches/0031-exfat-samsung-symlinks.patch"
	CACHE_TAG=""
	;;
de25nano)
	CPIO="$ROOT/output-de25/images/mister-initramfs.cpio"
	CPIO_MAKE_TARGET="de25   # with BR2_LINUX_KERNEL_EXT_MISTER_INITRAMFS=y in the DE25 stack (ADR 0029 D11)"
	KARCH=arm64
	CROSS_COMPILE="${CROSS_COMPILE:-aarch64-buildroot-linux-gnu-}"
	TOOLCHAIN_BIN="$ROOT/output-de25/host/bin"
	QEMU_SYSTEM=qemu-system-aarch64
	# `-M virt` has no default CPU on aarch64; cortex-a76 is the DE25's big
	# core and what the stage-1 toolchain tunes for (BR2_cortex_a76_a55 --
	# an armv8.2 target whose LSE atomics a cortex-a53 model would SIGILL on).
	QEMU_MACHINE=(-M virt -cpu cortex-a76)
	KERNEL_IMAGE_TARGET=Image
	KERNEL_IMAGE_REL=arch/arm64/boot/Image
	# The DE25's own product kernel config as the base (see the header).
	KERNEL_BASE_DEFCONFIG=""
	KERNEL_BASE_FILES=("$ROOT/board/mister/de25nano/linux.config"
	                   "$ROOT/board/mister/common/linux-mister.fragment")
	PIN_FRAGMENT="$ROOT/configs/mister_de25nano_defconfig"
	PIN_SYMBOL=BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE
	# Resolved through the DE25's own patch dir, which links to the 7.x
	# re-anchored copy in linux-patches-beta/ (since 2026-09-06 -- this
	# very case found the shared 6.18 form Oopsing on 7.x, ADR 0002 §8b).
	EXFAT_SYMLINK_PATCH="$ROOT/board/mister/de25nano/linux-patches/0031-exfat-samsung-symlinks.patch"
	CACHE_TAG="-de25"
	;;
*)
	printf 'test-initramfs.sh: FATAL: unknown --board %s (known: de10nano, de25nano)\n' "'$BOARD'" >&2
	exit 2
	;;
esac

case "$BOARD/$KERNEL" in
*/default)
	;;
de10nano/rt)
	# The RT series: its pin, its own 7.x-anchored 0031, its own caches (a
	# 7.2.y source tree and O= build must never share work/ with the 6.18
	# ones -- ensure_qemu_kernel() reuses whatever it finds there).
	PIN_SYMBOL=BR2_PACKAGE_LINUX_RT_VERSION
	EXFAT_SYMLINK_PATCH="$ROOT/board/mister/de10nano/linux-patches-beta/0031-exfat-samsung-symlinks.patch"
	CACHE_TAG="-rt"
	;;
*)
	printf 'test-initramfs.sh: FATAL: unknown --kernel %s for --board %s (known: default; rt on de10nano)\n' "'$KERNEL'" "$BOARD" >&2
	exit 2
	;;
esac

INIT_SRC="$ROOT/board/mister/common/initramfs-overlay/init"
MARKER_C="$SUPPORT/marker-init.c"
TEST_SYMLINK_C="$SUPPORT/test-symlink.c"
KERNEL_FRAGMENT="$SUPPORT/qemu-test-kernel.config"

export PATH="$TOOLCHAIN_BIN:$PATH"
export MTOOLS_SKIP_CHECK=1

# Cache locations. Overridable so CI can point these at a persistent cache
# across runs (a full kernel build is the expensive part of this script by a
# wide margin) or a scratch dir for a fully clean run. The DE25 leg's caches
# carry a -de25 tag so the two boards' kernel trees never share a directory.
WORK="${TEST_INITRAMFS_WORK:-$ROOT/work/test-initramfs$CACHE_TAG}"
KBUILD="${TEST_INITRAMFS_KBUILD:-$ROOT/work/test-initramfs$CACHE_TAG-kbuild}"
KERNEL_SRC="${TEST_INITRAMFS_KERNEL_SRC:-$ROOT/work/test-initramfs$CACHE_TAG-kernel-src}"
# Derived from the board's fragment, NOT hardcoded: board patch 0031 (applied
# below) tracks the pinned kernel's APIs and will not compile against an older
# one -- 6.18.40 gave exfat_remove_entries() a 4th arg, so a stale pin here
# fails the QEMU kernel build with a confusing "too few arguments". Reading the
# pin keeps this test kernel on the same version the image ships, which is what
# this script's header already claims it does.
KERNEL_VERSION="${TEST_INITRAMFS_KERNEL_VERSION:-$(sed -n "s/^$PIN_SYMBOL=\"\(.*\)\"\$/\1/p" "$PIN_FRAGMENT")}"
# Inline, not die() -- that is defined further down, and this block runs before
# it. Under `set -uo pipefail` (no -e) an undefined-function call would print
# "command not found" and CARRY ON, which is exactly the silent failure this
# guard exists to prevent.
[ -n "$KERNEL_VERSION" ] || {
	printf 'test-initramfs.sh: FATAL: %s\n' \
		"could not read $PIN_SYMBOL from ${PIN_FRAGMENT#"$ROOT"/}" >&2
	exit 2
}
# The pristine source tarball. Buildroot's own kernel build fetches it into
# dl/linux/ (BR2_DL_DIR), so that is where it is on any tree that has built
# the board's image; work/ is the older convention and stays as the fallback
# for a tarball dropped there by hand.
if [ -z "${TEST_INITRAMFS_KERNEL_TARBALL:-}" ]; then
	if [ -f "$ROOT/dl/linux/linux-$KERNEL_VERSION.tar.xz" ]; then
		KERNEL_TARBALL="$ROOT/dl/linux/linux-$KERNEL_VERSION.tar.xz"
	else
		KERNEL_TARBALL="$ROOT/work/linux-$KERNEL_VERSION.tar.xz"
	fi
else
	KERNEL_TARBALL="$TEST_INITRAMFS_KERNEL_TARBALL"
fi
QEMU_KERNEL="$KBUILD/$KERNEL_IMAGE_REL"

BUILD="$WORK/run"
MARKER_INIT="$WORK/marker-init"
MARKER_INIT_NONASCII="$WORK/marker-init-nonascii"
TEST_SYMLINK_BIN="$WORK/test-symlink"

# Guest boot budget. Every case here either reaches switch_root or a rescue
# shell within a couple of seconds of real 6.18 kernel + qemu virt boot time;
# 30s is generous headroom, not a tuned minimum. `-k 10` guarantees qemu is
# actually gone even if it ignores SIGTERM (observed in sandboxed CI runners).
# The aarch64 leg boots a 7.2 product-config kernel under TCG on a single
# emulated cortex-a76; measured 2026-09-06 it reaches switch_root in well under
# 10 s on a loaded 32-core host, so the same budget holds for both boards.
BOOT_TIMEOUT=30
BOOT_TIMEOUT_KILL=10

FAILED=0
RAN=0
declare -a SUMMARY=()

# populate_in_guest (below) backgrounds a qemu process and holds a FIFO open
# while it waits for the guest to reach a shell prompt. Track both here so a
# script error, Ctrl-C, or an early `die` never leaves an orphaned qemu (or a
# FIFO a later run would block writing into) behind -- the EXIT trap below is
# the only path that always runs.
declare -a CLEANUP_PIDS=()
declare -a CLEANUP_FILES=()

cleanup() {
	local p f
	for p in ${CLEANUP_PIDS[@]+"${CLEANUP_PIDS[@]}"}; do
		kill -9 "$p" >/dev/null 2>&1 || true
	done
	for f in ${CLEANUP_FILES[@]+"${CLEANUP_FILES[@]}"}; do
		rm -f "$f"
	done
}
trap cleanup EXIT

# ---------------------------------------------------------------- reporting
log()  { printf '==> %s\n' "$*" >&2; }
die()  { printf 'test-initramfs.sh: FATAL: %s\n' "$*" >&2; exit 2; }

pass_case() {
	SUMMARY+=("PASS  $1")
	printf 'PASS  %s\n' "$1"
}

fail_case() {
	SUMMARY+=("FAIL  $1")
	printf 'FAIL  %s\n' "$1" >&2
	printf '      %s\n' "$2" >&2
	FAILED=1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH ($2)"
}

# ---------------------------------------------------------------- prereqs
check_prereqs() {
	need "$QEMU_SYSTEM"        "install $QEMU_SYSTEM"
	need mkfs.vfat             "install dosfstools"
	need mkfs.exfat            "install exfatprogs (or exfat-utils)"
	need fsck.exfat            "install exfatprogs (or exfat-utils)"
	need sfdisk                "install util-linux"
	need mke2fs                "install e2fsprogs"
	need cpio                  "install cpio"
	need patch                 "install patch"
	need "${CROSS_COMPILE}gcc" "expected the Buildroot cross toolchain on PATH (${TOOLCHAIN_BIN#"$ROOT"/}); run 'make $CPIO_MAKE_TARGET' first, or set CROSS_COMPILE"
	need mcopy                 "install mtools"
	need mmd                   "install mtools"

	[ -f "$CPIO" ] || die "no $CPIO -- run 'make $CPIO_MAKE_TARGET' first."
	[ -f "$INIT_SRC" ] || die "missing $INIT_SRC"
	[ -f "$MARKER_C" ] || die "missing $MARKER_C"
	[ -f "$TEST_SYMLINK_C" ] || die "missing $TEST_SYMLINK_C"
	[ -f "$KERNEL_FRAGMENT" ] || die "missing $KERNEL_FRAGMENT"
	[ -f "$EXFAT_SYMLINK_PATCH" ] || die "missing $EXFAT_SYMLINK_PATCH"
	local f
	for f in ${KERNEL_BASE_FILES[@]+"${KERNEL_BASE_FILES[@]}"}; do
		[ -f "$f" ] || die "missing $f"
	done
}

# ---------------------------------------------------------- the QEMU test kernel
# For the DE10 leg: NOT the product kernel (board/mister/de10nano/linux.config)
# -- see scripts/test-initramfs/qemu-test-kernel.config's header. For the DE25
# leg: the product config IS the base (see the file header for why). Either
# way it is built out-of-tree (O=) against a pristine source tree at the
# board's pinned kernel version so incremental rebuilds (e.g. after /init
# changes -- see the re-point below) are cheap.
ensure_qemu_kernel() {
	if [ ! -f "$KBUILD/Makefile" ]; then
		log "no cached QEMU test kernel at $KBUILD -- building from scratch"
		[ -f "$KERNEL_TARBALL" ] || die \
			"$KERNEL_TARBALL missing; cannot bootstrap the QEMU test kernel." \
			"Fetch the pinned kernel source tarball (same one the board's Buildroot" \
			"kernel build already uses -- dl/linux/) to that path, or point" \
			"TEST_INITRAMFS_KERNEL_TARBALL at it."
		mkdir -p "$KERNEL_SRC"
		log "extracting $KERNEL_TARBALL"
		tar -C "$KERNEL_SRC" --strip-components=1 -xf "$KERNEL_TARBALL"
		mkdir -p "$KBUILD"
		if [ -n "$KERNEL_BASE_DEFCONFIG" ]; then
			log "configuring: $KERNEL_BASE_DEFCONFIG + $KERNEL_FRAGMENT"
			make -C "$KERNEL_SRC" O="$KBUILD" ARCH=$KARCH CROSS_COMPILE="$CROSS_COMPILE" \
				"$KERNEL_BASE_DEFCONFIG"
		else
			# A minimal product config as the base: seed .config with it and
			# let merge_config.sh layer the rest on. The seed is the first
			# base file; the others are merged like the harness fragment.
			log "configuring: ${KERNEL_BASE_FILES[*]#"$ROOT"/} + $KERNEL_FRAGMENT"
			cp "${KERNEL_BASE_FILES[0]}" "$KBUILD/.config"
		fi
		# merge_config.sh finishes with a BARE `make ... alldefconfig` in the
		# CURRENT directory -- it has no -C. Run from this repo's root (the
		# normal way to invoke this script) that `make` hits the wrapper
		# Makefile, which forwards `alldefconfig` to Buildroot, which fails
		# ("Can't read seed configuration"), and merge_config.sh exits before
		# writing the merged .config. Every fragment symbol the base defconfig
		# already had looks fine; every one it lacked (CONFIG_EXFAT_FS,
		# CONFIG_FAT_DEFAULT_UTF8) is silently missing, and the three exFAT
		# cases fail with "mount: No such device" for a reason that looks
		# nothing like this. So: cd into the kernel tree, give its make the
		# ARCH it needs, and refuse to continue if the merge fails. The
		# fragment-survival check after olddefconfig below is the backstop.
		(cd "$KERNEL_SRC" && ARCH=$KARCH CROSS_COMPILE="$CROSS_COMPILE" \
			scripts/kconfig/merge_config.sh -O "$KBUILD" \
				"$KBUILD/.config" \
				${KERNEL_BASE_FILES[@]+"${KERNEL_BASE_FILES[@]:1}"} \
				"$KERNEL_FRAGMENT" >&2) \
			|| die "merge_config.sh failed for $KERNEL_FRAGMENT"
	elif [ ! -d "$KERNEL_SRC" ]; then
		die "$KBUILD exists but its source tree $KERNEL_SRC does not." \
			"Remove $KBUILD (or set TEST_INITRAMFS_KBUILD to a fresh path) and re-run."
	fi

	# The product kernel carries fs/exfat symlink support as board patch 0031
	# (ADR 0019), and the `symlink` case asserts exactly that behaviour, so
	# the QEMU test kernel source must carry the same patch. Idempotent (the
	# marker macro only exists once the patch is in), and applied to a cached
	# source tree too, so caches created before this patch existed upgrade in
	# place -- the O= build's dependency tracking then rebuilds fs/exfat only.
	if ! grep -q EXFAT_ATTR_SYMLINK "$KERNEL_SRC/fs/exfat/exfat_raw.h"; then
		log "applying $(basename "$EXFAT_SYMLINK_PATCH") to $KERNEL_SRC"
		patch -p1 -s -d "$KERNEL_SRC" < "$EXFAT_SYMLINK_PATCH" \
			|| die "board patch 0031 failed to apply to the QEMU test kernel source"
	fi

	# Always re-point CONFIG_INITRAMFS_SOURCE at the CURRENT cpio and rebuild:
	# cheap if /init did not change (the kernel's own dependency tracking skips
	# straight to nothing-to-do), silently testing a STALE /init if skipped.
	"$KERNEL_SRC/scripts/config" --file "$KBUILD/.config" \
		--set-str CONFIG_INITRAMFS_SOURCE "$CPIO"
	make -C "$KERNEL_SRC" O="$KBUILD" ARCH=$KARCH CROSS_COMPILE="$CROSS_COMPILE" \
		olddefconfig >&2

	# Every `CONFIG_X=y` the fragment asks for must be in the resolved config,
	# on a fresh bootstrap AND on a cached $KBUILD (a cache made by a run whose
	# merge silently failed -- see above -- keeps its broken .config forever,
	# because the merge only happens on bootstrap). Fail with the fix spelled
	# out rather than let the exFAT cases fail on a symptom.
	missing=""
	while IFS= read -r sym; do
		grep -qx "$sym" "$KBUILD/.config" || missing="$missing $sym"
	done <<-EOF
	$(grep -E '^CONFIG_[A-Z0-9_]+=y$' "$KERNEL_FRAGMENT")
	EOF
	[ -z "$missing" ] || die \
		"QEMU test kernel .config lacks fragment symbol(s):$missing" \
		"(from $KERNEL_FRAGMENT). If $KBUILD is a cache from before the" \
		"merge_config.sh cwd fix, remove it (rm -rf $KBUILD) and re-run to" \
		"bootstrap a correct one."

	log "building QEMU test kernel $KERNEL_IMAGE_TARGET (embedding $(basename "$CPIO"))"
	make -C "$KERNEL_SRC" O="$KBUILD" ARCH=$KARCH CROSS_COMPILE="$CROSS_COMPILE" \
		-j"$(nproc)" "$KERNEL_IMAGE_TARGET" >&2

	[ -f "$QEMU_KERNEL" ] || die "kernel build finished but produced no $QEMU_KERNEL"
}

# ---------------------------------------------------------------- marker-init
# Compiled statically (no shared libs available in the tiny ext4 image it
# ships in) for the guest's architecture, since it runs there, not on the host.
build_marker_inits() {
	log "compiling marker-init (+ nonascii variant) with ${CROSS_COMPILE}gcc"
	"${CROSS_COMPILE}gcc" -O2 -static -Wall -Wextra -o "$MARKER_INIT" "$MARKER_C" \
		|| die "marker-init compile failed"
	"${CROSS_COMPILE}gcc" -O2 -static -Wall -Wextra -DCHECK_NONASCII \
		-o "$MARKER_INIT_NONASCII" "$MARKER_C" \
		|| die "marker-init-nonascii compile failed"
	log "compiling test-symlink (guest-side exfat symlink assertions)"
	"${CROSS_COMPILE}gcc" -O2 -static -Wall -Wextra \
		-o "$TEST_SYMLINK_BIN" "$TEST_SYMLINK_C" \
		|| die "test-symlink compile failed"
}

# ---------------------------------------------------------------- disk builders
# The ext4 image that /init's `loop=` mounts -- i.e. the tiny stand-in for the
# real linux/linux.img, whose /sbin/init is one of the two marker-init builds.
build_ext4_image() {
	local out=$1 init_bin=$2 rootdir=$3
	mkdir -p "$rootdir"/sbin "$rootdir"/dev "$rootdir"/proc "$rootdir"/sys \
		"$rootdir"/media/fat
	cp "$init_bin" "$rootdir/sbin/init"
	# mke2fs -d populates from a directory with no root and no loop mount needed.
	mke2fs -q -t ext4 -L rootfs -d "$rootdir" "$out" 16M
}

# MBR-wrap a single partition image so root=/dev/vda1 is a real partition
# under qemu's virtio-blk, exactly like a real MiSTer SD card.
wrap_mbr() {
	local partimg=$1 diskimg=$2 ptype=$3
	truncate -s 100M "$diskimg"
	printf 'label: dos\nstart=2048, size=196608, type=%s, bootable\n' "$ptype" \
		| sfdisk -q "$diskimg" >/dev/null
	dd if="$partimg" of="$diskimg" bs=512 seek=2048 conv=notrunc status=none
}

# ---------------------------------------------------------------- qemu runner
# `timeout -k` is load-bearing, not decoration: a plain `timeout N` only
# SIGTERMs at N and then waits indefinitely for the child to actually exit,
# which qemu does not always do promptly under -nographic in a sandboxed
# runner (observed directly while developing this script). `-k` forces a
# SIGKILL grace period so this function always returns.
boot_qemu() {
	local diskimg=$1 cmdline=$2 logfile=$3
	shift 3
	timeout -k "$BOOT_TIMEOUT_KILL" "$BOOT_TIMEOUT" \
		"$QEMU_SYSTEM" "${QEMU_MACHINE[@]}" -m 512 -nographic -no-reboot \
		-kernel "$QEMU_KERNEL" \
		-drive file="$diskimg",format=raw,if=none,id=sd0 \
		-device virtio-blk-device,drive=sd0 \
		"$@" \
		-append "$cmdline" \
		< /dev/null > "$logfile" 2>&1
	# Exit status is deliberately not inspected here: qemu's own exit code
	# under `-nographic -no-reboot` after a guest-initiated poweroff, versus a
	# `timeout`-forced kill, is not a reliable pass/fail signal by itself --
	# every case function asserts the CONSOLE LOG content instead, which is
	# what actually distinguishes "booted and asserted" from "sat at a rescue
	# shell until the timeout fired" (both must be reachable, deliberately).
}

# A second boot, with interactive stdin, used ONLY to populate an exFAT
# partition (mtools cannot write exFAT -- "non DOS media" -- and this harness
# has no root to loop-mount with either). Boots the REAL initramfs with
# rdinit=/bin/sh, which hands us a BusyBox ash directly instead of running
# /init, then drives it over the console.
#
# This does NOT just pipe a fixed block of commands at qemu's stdin after a
# guessed delay. An earlier version did exactly that, on the reasoning that
# piped input arriving before the guest's UART and ash are ready gets dropped
# or interleaved into the kernel's own boot log -- true, but a FIXED delay
# (however generous) is still a guess about how long boot takes, and this
# harness has been directly observed to boot anywhere from under a second to
# well past 20s depending on host load. A guessed delay is either flaky
# (too short, sometimes) or slow (too long, always). So instead: hold the
# guest's stdin open on a FIFO, watch the console log for the actual ash
# sign-on banner, and only THEN write commands -- synchronized to a real
# event in the guest, not a clock on the host.
#
# Three more pitfalls, all found by actually running this (not by inspection)
# and all load-bearing, not stylistic:
#
#  1. With TWO virtio-blk drives attached (only true in this function -- every
#     other boot in this script uses one), device naming is NOT command-line
#     order: measured directly, the disk given SECOND on the qemu command line
#     (here, imgfile) enumerates as /dev/vda, and the one given FIRST (diskimg)
#     enumerates as /dev/vdb. This is the opposite of the natural assumption
#     and is NOT relied upon below -- the command list detects which of
#     /dev/vda1 / /dev/vdb1 actually exists (only the MBR-partitioned disk
#     has one; the raw ext4 imgfile does not) and sets $DATADEV/$IMGDEV from
#     that, rather than assuming either device name.
#
#  2. Neither candidate device is guaranteed to exist the instant ash starts
#     reading commands -- the kernel is still enumerating virtio devices. A
#     command that reads one too early fails with "Can't lookup blockdev". So
#     the command list always starts with a bounded wait for a partition node
#     to appear, rather than trusting any fixed delay to be long enough.
#
#  3. The guest's console ECHOES BACK THE LITERAL COMMAND TEXT it read,
#     whether or not the command actually ran -- so if a caller marks success
#     with `cmd && echo SOME-MARKER`, the string SOME-MARKER appears in the
#     log the moment the line is echoed, BEFORE `cmd` even runs, regardless of
#     whether `cmd` then fails. A plain `grep -q SOME-MARKER` is therefore a
#     false positive by construction and WILL NOT catch a failed command
#     (found exactly this way: a failed exfat mount still "passed" a
#     `grep -q GUEST-EXFAT-RW-MOUNT-OK` check because that string is also
#     substring-present in the echoed input line). Callers must mark success
#     with the ACTUAL EXIT STATUS, e.g. `cmd; echo MARKER-RC=$?`: the echoed
#     input line then contains the literal, unexpanded text `MARKER-RC=$?`
#     (no `$` expansion happens until the shell actually executes the line),
#     which is textually distinct from a real "MARKER-RC=0" in the output.
#
# Callers' commands may reference $DATADEV (the MBR disk's data partition)
# and $IMGDEV (the raw imgfile's whole-disk device) -- both set by the time
# any caller command runs. There is no grep, awk or sed in this BusyBox
# config (allnoconfig-derived, board/mister/common/initramfs-busybox.config
# -- confirmed missing directly, not assumed), so the detection below is
# plain `test`/`case` only.
populate_in_guest() {
	local diskimg=$1 imgfile=$2 logfile=$3
	shift 3
	local fifo qemu_pid waited

	fifo="$WORK/populate-$$.fifo"
	rm -f "$fifo"
	mkfifo "$fifo"
	CLEANUP_FILES+=("$fifo")

	: > "$logfile"
	# Opening a FIFO for read and for write are each a BLOCKING syscall until
	# the other end is also open (POSIX fifo(7)) -- so qemu (the reader, via
	# `< "$fifo"`) has to be started FIRST, in the background, where its open()
	# blocks harmlessly in a child process. Only THEN can the parent's own
	# `exec {fd}>` (the writer) rendezvous with it. Getting this order backwards
	# deadlocks the whole script on the very first `exec` -- found exactly this
	# way: it hung with wchan=wait_for_partner and no qemu process ever existed.
	"$QEMU_SYSTEM" "${QEMU_MACHINE[@]}" -m 512 -nographic -no-reboot \
		-kernel "$QEMU_KERNEL" \
		-drive file="$diskimg",format=raw,if=none,id=sd0 \
		-device virtio-blk-device,drive=sd0 \
		-drive file="$imgfile",format=raw,if=none,id=img0 \
		-device virtio-blk-device,drive=img0 \
		-append "console=ttyAMA0,115200 loglevel=4 rdinit=/bin/sh" \
		< "$fifo" > "$logfile" 2>&1 &
	qemu_pid=$!
	CLEANUP_PIDS+=("$qemu_pid")

	# Held open for the guest's whole session once connected: the fifo's write
	# end must not see EOF between commands, or qemu delivers that as EOF on
	# the guest's stdin and ash exits (pid 1 exiting is a kernel panic).
	# `exec {fd}>` picks an unused descriptor and keeps it open past this call.
	exec {fifo_fd}>"$fifo"

	waited=0
	until grep -q 'BusyBox.*built-in shell' "$logfile" 2>/dev/null; do
		if ! kill -0 "$qemu_pid" 2>/dev/null; then
			log "populate_in_guest: qemu exited before reaching a shell prompt"
			break
		fi
		waited=$((waited + 1))
		if [ "$waited" -ge "$BOOT_TIMEOUT" ]; then
			log "populate_in_guest: timed out waiting for the ash prompt"
			break
		fi
		sleep 1
	done
	sleep 1  # ash prints the banner fractionally before its first read(2)

	{
		# shellcheck disable=SC2016 # deliberate: this is GUEST ash script text
		# fed over the console, not host expansion -- $i/$DATADEV/$? etc. must
		# survive quoted so THE GUEST expands them, not this host script.
		printf '%s\n' \
			'mount -t proc proc /proc' \
			'mount -t devtmpfs devtmpfs /dev' \
			'mkdir -p /mnt/fat' \
			'i=0; while [ ! -b /dev/vda1 ] && [ ! -b /dev/vdb1 ] && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done' \
			'if [ -b /dev/vda1 ]; then DATADEV=/dev/vda1; IMGDEV=/dev/vdb; elif [ -b /dev/vdb1 ]; then DATADEV=/dev/vdb1; IMGDEV=/dev/vda; else DATADEV=; IMGDEV=; fi' \
			'echo "GUEST-DATADEV=$DATADEV GUEST-IMGDEV=$IMGDEV"' \
			"$@" \
			'sync'
	} >&"$fifo_fd"

	# No poweroff applet is enabled in this BusyBox config (see
	# initramfs-busybox.config), so the guest has no way to end its own
	# session -- wait for our commands to have plausibly finished, then tear
	# down unconditionally. `sync` is deliberately the last command above:
	# ash reads and echoes ("# sync", an EXACT line, nothing appended) one
	# command at a time and -- consistently, in every log captured while
	# developing this function -- only after the PRECEDING command has
	# already produced its real output, so this line appearing is a good
	# enough "everything before it already ran" signal without needing a
	# dedicated done-marker command (which would face the same echo-vs-
	# execution ambiguity pitfall 2 above describes).
	waited=0
	until grep -qx '# sync' "$logfile" 2>/dev/null; do
		waited=$((waited + 1))
		[ "$waited" -ge "$BOOT_TIMEOUT" ] && break
		kill -0 "$qemu_pid" 2>/dev/null || break
		sleep 1
	done
	sleep 1  # let a just-echoed `sync` actually complete before teardown

	exec {fifo_fd}>&-
	kill -9 "$qemu_pid" >/dev/null 2>&1 || true
	wait "$qemu_pid" 2>/dev/null || true
	rm -f "$fifo"
}

# ---------------------------------------------------------------- assertions
# A successful boot: switch_root worked and every marker-init assertion
# passed. Deliberately checks for the ABSENCE of any FAIL marker too, not just
# the PRESENCE of RESULT=PASS -- a partially-populated log (qemu killed mid
# boot) must not read as a pass just because it never got far enough to fail.
assert_booted_clean() {
	local logfile=$1 what=$2
	if ! grep -q 'MARKER: RESULT=PASS' "$logfile"; then
		fail_case "$what" "no MARKER: RESULT=PASS in $logfile"
		return 1
	fi
	if grep -q 'MARKER:.*FAIL' "$logfile"; then
		fail_case "$what" "a marker assertion FAILed -- see $logfile"
		return 1
	fi
	return 0
}

# A correctly-handled failure: reaches the rescue shell with the expected
# diagnostic, and CRITICALLY never panics and never claims success. A2/A7's
# entire point is "rescue shell, not panic" -- so this checks both directions.
assert_rescue() {
	local logfile=$1 what=$2 expect_msg=$3
	if grep -qF "$expect_msg" "$logfile"; then
		: # expected message present
	else
		fail_case "$what" "expected rescue message not found: '$expect_msg' (see $logfile)"
		return 1
	fi
	if ! grep -q 'Dropping to a rescue shell on the console' "$logfile"; then
		fail_case "$what" "rescue banner missing -- did not reach the rescue shell"
		return 1
	fi
	if grep -qi 'Kernel panic' "$logfile"; then
		fail_case "$what" "kernel panic in log -- A2/A7 requires a rescue shell, never a panic"
		return 1
	fi
	if grep -q 'MARKER: RESULT=' "$logfile"; then
		fail_case "$what" "switch_root ran (MARKER: RESULT= present) -- this case should have failed BEFORE switch_root"
		return 1
	fi
	return 0
}

# =========================================================================
# Cases
# =========================================================================

# --- fat32: exfat probe fails, falls back to vfat (utf8=1), switch_root ---
case_fat32() {
	local name=fat32 b="$BUILD/fat32"
	rm -rf "$b"; mkdir -p "$b/rootdir"
	build_ext4_image "$b/linux.img" "$MARKER_INIT" "$b/rootdir"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.vfat -F 32 -n MISTERDATA "$part" >/dev/null
	mmd -i "$part" ::/linux
	mcopy -i "$part" "$b/linux.img" ::/linux/linux.img

	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 0c   # 0c = FAT32 LBA

	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=/dev/vda1 loop=linux/linux.img ro rootwait"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	assert_booted_clean "$log" "$name" || return
	grep -q 'data partition mounted as vfat' "$log" || {
		fail_case "$name" "did not take the vfat fallback path (expected exfat probe to fail first)"
		return
	}
	pass_case "$name (FAT32: exfat probe fails -> vfat utf8=1 fallback -> switch_root)"
}

# --- exfat: mounts on the first try, switch_root ---
case_exfat() {
	local name=exfat b="$BUILD/exfat"
	rm -rf "$b"; mkdir -p "$b/rootdir"
	build_ext4_image "$b/linux.img" "$MARKER_INIT" "$b/rootdir"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.exfat -n MISTERDATA "$part" >/dev/null

	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 07   # 07 = exFAT/NTFS

	# mtools cannot write exFAT and we are not root, so populate the card from
	# INSIDE qemu instead, using the very kernel+initramfs under test. This
	# also independently proves mainline exfat mounts read-write on this
	# kernel (A15) -- not just read-only, which would be a much easier bug to
	# hide.
	# $DATADEV/$IMGDEV, not a hardcoded /dev/vda1 -- see populate_in_guest's own
	# header (pitfall 1) for why device NAMING is not command-line order with
	# two virtio-blk drives attached. RC-based markers, not `cmd && echo
	# MARKER` -- see the same header (pitfall 3) for why the latter is a
	# false-positive-by-construction on this console.
	local poplog="$b/populate.log"
	# shellcheck disable=SC2016 # deliberate: GUEST ash script text again --
	# $DATADEV/$IMGDEV/$? must reach the guest unexpanded by this host shell.
	populate_in_guest "$disk" "$b/linux.img" "$poplog" \
		'mount -t exfat -o rw "$DATADEV" /mnt/fat; echo "GUEST-EXFAT-RW-MOUNT-RC=$?"' \
		'mkdir -p /mnt/fat/linux' \
		'cat "$IMGDEV" > /mnt/fat/linux/linux.img; echo "GUEST-COPY-RC=$?"' \
		'umount /mnt/fat; echo "GUEST-UMOUNT-RC=$?"'
	grep -qE 'GUEST-DATADEV=/dev/vd[ab]1' "$poplog" || { fail_case "$name" "populate: neither /dev/vda1 nor /dev/vdb1 ever appeared (see $poplog)"; return; }
	grep -q 'GUEST-EXFAT-RW-MOUNT-RC=0' "$poplog"   || { fail_case "$name" "populate: exfat rw mount failed (see $poplog)"; return; }
	grep -q 'GUEST-COPY-RC=0' "$poplog"             || { fail_case "$name" "populate: linux.img copy failed (see $poplog)"; return; }

	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=/dev/vda1 loop=linux/linux.img ro rootwait"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	assert_booted_clean "$log" "$name" || return
	grep -q 'data partition mounted as exfat' "$log" || {
		fail_case "$name" "did not mount as exfat on the first try"
		return
	}
	pass_case "$name (exFAT: mounts on the first try -> switch_root)"
}

# --- fsck-request: the on-demand exFAT repair path (ADR 0026) ---
#
# The riskiest thing in that ADR is an ORDERING claim: /init can only repair the
# data partition by unmounting it first, because fsck.exfat's repair mode opens
# O_RDWR|O_EXCL and a mounted filesystem holds an exclusive bdev claim
# (fs/super.c:1617) even when mounted read-only. Get that wrong and the repair
# silently fails on every real card -- with the partition already unmounted.
# This case is the only place that ordering is executed rather than reasoned
# about, on the real cpio, against a real exFAT volume.
#
# It also pins the three properties the design leans on:
#   * exactly-once -- the marker must be GONE afterwards, asserted from inside
#     the switched-root system by marker-init (a repair that re-arms itself is
#     indistinguishable from a brick);
#   * the remount uses the SAME options -- marker-init's existing A13
#     sync+dirsync+noatime assertion runs against the post-fsck mount, which is
#     precisely why /init factors the mount into mount_data_partition();
#   * the outcome is recorded in .fsck-result for the user-facing tool to report.
case_fsck_request() {
	local name=fsck-request b="$BUILD/fsck-request"
	rm -rf "$b"; mkdir -p "$b/rootdir"
	build_ext4_image "$b/linux.img" "$MARKER_INIT" "$b/rootdir"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.exfat -n MISTERDATA "$part" >/dev/null

	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 07   # 07 = exFAT/NTFS

	# Same in-guest population as case_exfat (mtools cannot write exFAT and we
	# are not root), plus the request marker itself. The marker's CONTENT is
	# never read by /init -- it only tests for the file -- so any bytes do.
	local poplog="$b/populate.log"
	# shellcheck disable=SC2016 # deliberate: GUEST ash script text -- $DATADEV/
	# $IMGDEV/$? must reach the guest unexpanded by this host shell.
	populate_in_guest "$disk" "$b/linux.img" "$poplog" \
		'mount -t exfat -o rw "$DATADEV" /mnt/fat; echo "GUEST-EXFAT-RW-MOUNT-RC=$?"' \
		'mkdir -p /mnt/fat/linux' \
		'cat "$IMGDEV" > /mnt/fat/linux/linux.img; echo "GUEST-COPY-RC=$?"' \
		'echo test-request > /mnt/fat/linux/.fsck-request; echo "GUEST-MARKER-RC=$?"' \
		'umount /mnt/fat; echo "GUEST-UMOUNT-RC=$?"'
	grep -qE 'GUEST-DATADEV=/dev/vd[ab]1' "$poplog" || { fail_case "$name" "populate: neither /dev/vda1 nor /dev/vdb1 ever appeared (see $poplog)"; return; }
	grep -q 'GUEST-EXFAT-RW-MOUNT-RC=0' "$poplog"   || { fail_case "$name" "populate: exfat rw mount failed (see $poplog)"; return; }
	grep -q 'GUEST-COPY-RC=0' "$poplog"             || { fail_case "$name" "populate: linux.img copy failed (see $poplog)"; return; }
	grep -q 'GUEST-MARKER-RC=0' "$poplog"           || { fail_case "$name" "populate: could not write the .fsck-request marker (see $poplog)"; return; }

	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=/dev/vda1 loop=linux/linux.img ro rootwait"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	# Covers "the marker is gone" too: that assertion lives in marker-init and
	# so is part of RESULT=PASS.
	assert_booted_clean "$log" "$name" || return

	grep -q 'fsck: repair requested' "$log" || {
		fail_case "$name" "/init never noticed the .fsck-request marker"
		return
	}
	# THE ordering assertion. If the unmount had not happened first, fsck.exfat
	# would have failed to open the device and /init would report a nonzero exit
	# here instead of a clean-or-repaired verdict.
	grep -qE 'fsck: (clean: no errors found|repaired: errors were found and corrected)' "$log" || {
		fail_case "$name" "fsck.exfat did not complete cleanly -- the unmount-before-repair ordering is the usual cause (see $log)"
		return
	}
	grep -q 'fsck: data partition remounted as exfat' "$log" || {
		fail_case "$name" "the data partition was not remounted after fsck"
		return
	}
	# The recorded outcome, read back from the filesystem by marker-init (the
	# host cannot see inside an exFAT image) and echoed to the console. This is
	# the only artifact Scripts/check_storage.sh ever reports, so a redirect that
	# silently failed on the remounted volume must not pass. "INTERRUPTED" is
	# /init's pre-repair placeholder -- seeing it here means the verdict write
	# after the remount did not land.
	grep -qE 'MARKER: FSCK-RESULT=(clean|repaired)' "$log" || {
		fail_case "$name" "no usable .fsck-result recorded on the card -- got: $(grep -o 'MARKER: FSCK-RESULT=.*' "$log" || echo '(nothing)')"
		return
	}
	pass_case "$name (exFAT: marker -> delete -> umount -> fsck.exfat -p -> remount -> switch_root)"
}

# --- symlink: Samsung-format symlinks on exFAT (board patch 0031, ADR 0019) ---
#
# Asserts, from inside the guest, on the same kernel the other cases boot:
# symlink create (relative/absolute/dangling/EEXIST), readlink, lstat ->
# S_IFLNK, open-through-link content, getdents d_type=DT_LNK, unlink (link
# dies, target survives) -- hot, and again cold after a umount/remount --
# plus the create+unlink cluster-leak regression as a statvfs free-space
# round-trip, which fsck.exfat (1.3.2) provably does NOT catch (verified by
# leaking a cluster on an unfixed kernel: fsck stays silent). The assertions
# live in scripts/test-initramfs/test-symlink.c and ride into the guest on a
# host-written vfat tool image, because mtools cannot write exFAT -- the
# same reason case_exfat populates in-guest.
case_symlink() {
	local name=symlink b="$BUILD/symlink"
	rm -rf "$b"; mkdir -p "$b"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.exfat -n MISTERDATA "$part" >/dev/null
	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 07   # 07 = exFAT/NTFS

	# The second drive carries the test binary instead of a linux.img: a
	# whole-disk vfat image (which host mcopy CAN write), so
	# populate_in_guest's $DATADEV/$IMGDEV detection works unchanged -- only
	# the MBR-wrapped disk has a partition node.
	local tool="$b/tool.img"
	truncate -s 16M "$tool"
	mkfs.vfat -n TOOLS "$tool" >/dev/null
	mcopy -i "$tool" "$TEST_SYMLINK_BIN" ::/test-symlink

	local poplog="$b/populate.log"
	# shellcheck disable=SC2016 # GUEST ash text: $DATADEV/$IMGDEV/$? must
	# reach the guest unexpanded (see populate_in_guest's header).
	populate_in_guest "$disk" "$tool" "$poplog" \
		'mkdir -p /mnt/tool' \
		'mount -t vfat "$IMGDEV" /mnt/tool; echo "GUEST-TOOL-MOUNT-RC=$?"' \
		'mount -t exfat -o rw,sync,dirsync "$DATADEV" /mnt/fat; echo "GUEST-EXFAT-MOUNT-RC=$?"' \
		'/mnt/tool/test-symlink /mnt/fat create; echo "GUEST-SYMLINK-CREATE-RC=$?"' \
		'umount /mnt/fat; echo "GUEST-UMOUNT1-RC=$?"' \
		'mount -t exfat -o rw "$DATADEV" /mnt/fat; echo "GUEST-REMOUNT-RC=$?"' \
		'/mnt/tool/test-symlink /mnt/fat verify; echo "GUEST-SYMLINK-VERIFY-RC=$?"' \
		'umount /mnt/fat; echo "GUEST-UMOUNT2-RC=$?"'

	local m
	for m in TOOL-MOUNT EXFAT-MOUNT SYMLINK-CREATE UMOUNT1 REMOUNT \
			SYMLINK-VERIFY UMOUNT2; do
		grep -q "GUEST-$m-RC=0" "$poplog" || {
			fail_case "$name" "GUEST-$m-RC=0 not found (see $poplog)"
			return
		}
	done
	# Belt and braces: RC=0 already implies no assertion fired (test-symlink
	# exits 1 on the first failure), but a FAIL: line names the exact broken
	# assertion in the failure report, so check for it explicitly too.
	if grep -q 'FAIL:' "$poplog"; then
		fail_case "$name" "a test-symlink assertion failed (see $poplog)"
		return
	fi

	# Host-side: the driver's writes must leave a checksum-valid filesystem.
	# This does NOT catch cluster leaks (fsck.exfat 1.3.2 ignores orphaned
	# bitmap bits -- the statvfs check above is the leak tripwire); it
	# catches dentry-set/checksum corruption instead.
	dd if="$disk" of="$b/part1.after" bs=512 skip=2048 count=196608 status=none
	if ! fsck.exfat -n "$b/part1.after" >"$b/fsck.log" 2>&1; then
		fail_case "$name" "fsck.exfat found problems after symlink I/O (see $b/fsck.log)"
		return
	fi

	pass_case "$name (exFAT Samsung-format symlinks: hot+cold round-trip, DT_LNK, unlink leak tripwire, fsck-clean -- ADR 0019)"
}

# --- label: root=LABEL=... resolved via BusyBox findfs ---
case_label() {
	local name=label b="$BUILD/label"
	rm -rf "$b"; mkdir -p "$b/rootdir"
	build_ext4_image "$b/linux.img" "$MARKER_INIT" "$b/rootdir"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.vfat -F 32 -n MISTERDATA "$part" >/dev/null
	mmd -i "$part" ::/linux
	mcopy -i "$part" "$b/linux.img" ::/linux/linux.img

	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 0c

	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=LABEL=MISTERDATA loop=linux/linux.img ro rootwait"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	assert_booted_clean "$log" "$name" || return
	grep -q 'root device /dev/vda1 ready' "$log" || {
		fail_case "$name" "LABEL=MISTERDATA did not resolve to /dev/vda1 via findfs"
		return
	}
	pass_case "$name (root=LABEL=MISTERDATA resolved via findfs -> switch_root)"
}

# --- nonascii: a non-ASCII FAT32 long filename survives vfat utf8=1 ---
#
# THE CASE THIS SCRIPT EXISTS TO ADD (see the file header). Populated with the
# HOST's own mtools -- unlike exFAT, mtools writes vfat long filenames just
# fine (verified separately: `mcopy` auto-detects the C.UTF-8 locale and emits
# a proper Unicode LFN entry) -- so there is no need for the in-guest populate
# trick here; the interesting part is entirely on the read side, in the real
# kernel's vfat driver.
#
# The exact filename and content are compiled into marker-init-nonascii
# (scripts/test-initramfs/marker-init.c); this function must create EXACTLY
# that name/content or the assertion is void by construction.
NONASCII_NAME=$'Pok\xc3\xa9mon_\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e_\xe2\x98\x85.txt'
NONASCII_CONTENT='MARKER-NONASCII-OK'

case_nonascii() {
	local name=nonascii b="$BUILD/nonascii"
	rm -rf "$b"; mkdir -p "$b/rootdir"
	build_ext4_image "$b/linux.img" "$MARKER_INIT_NONASCII" "$b/rootdir"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.vfat -F 32 -n MISTERDATA "$part" >/dev/null
	mmd -i "$part" ::/linux
	mcopy -i "$part" "$b/linux.img" ::/linux/linux.img

	printf '%s' "$NONASCII_CONTENT" > "$b/nonascii-src.txt"
	mcopy -i "$part" "$b/nonascii-src.txt" "::/$NONASCII_NAME" || {
		fail_case "$name" "host mcopy could not write the non-ASCII filename onto the FAT32 image"
		return
	}

	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 0c

	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=/dev/vda1 loop=linux/linux.img ro rootwait"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	assert_booted_clean "$log" "$name" || return
	grep -q 'data partition mounted as vfat' "$log" || {
		fail_case "$name" "did not take the vfat utf8=1 fallback path"
		return
	}
	grep -q 'MARKER: non-ASCII vfat filename opens by its exact UTF-8 bytes .*PASS' "$log" || {
		fail_case "$name" "non-ASCII filename did NOT survive the vfat utf8=1 mount byte-for-byte (mojibake regression -- see $log)"
		return
	}
	grep -q 'MARKER: non-ASCII file content round-trips byte-for-byte .*PASS' "$log" || {
		fail_case "$name" "non-ASCII file content did not round-trip (see $log)"
		return
	}
	pass_case "$name (non-ASCII FAT32 long filename round-trips byte-for-byte through vfat utf8=1, ADR 0010)"
}

# --- missing-image: loop= names a file that is not there -> rescue, no panic ---
case_missing_image() {
	local name=missing-image b="$BUILD/missing-image"
	rm -rf "$b"; mkdir -p "$b"

	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.vfat -F 32 -n MISTERDATA "$part" >/dev/null
	# Deliberately no linux/linux.img on the card at all.

	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 0c

	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=/dev/vda1 loop=linux/linux.img ro rootwait"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	assert_rescue "$log" "$name" "loop image 'linux/linux.img' not found on /dev/vda1" || return
	pass_case "$name (missing linux/linux.img -> rescue shell, never a panic)"
}

# --- rootwait: root= never appears -> retry loop -> rescue after N s, no panic ---
case_rootwait() {
	local name=rootwait b="$BUILD/rootwait"
	rm -rf "$b"; mkdir -p "$b"

	# No disk content matters here -- /dev/sdz9 never exists under qemu virt,
	# so /init's resolve_root() retry loop is guaranteed to exhaust rootwait=N.
	local part="$b/part1.img"
	truncate -s 96M "$part"
	mkfs.vfat -F 32 -n MISTERDATA "$part" >/dev/null
	local disk="$b/sd.img"
	wrap_mbr "$part" "$disk" 0c

	local wait_s=3
	local cmdline="console=ttyAMA0,115200 loglevel=4 loop.max_part=8 mem=511M root=/dev/sdz9 loop=linux/linux.img ro rootwait=${wait_s}"
	local log="$b/console.log"
	boot_qemu "$disk" "$cmdline" "$log"

	assert_rescue "$log" "$name" "root device '/dev/sdz9' did not appear after ${wait_s}s" || return
	pass_case "$name (root= never appears -> ${wait_s}s retry loop -> rescue shell, never a panic)"
}

# =========================================================================
# Driver
# =========================================================================

ALL_CASES=(fat32 exfat fsck-request symlink label nonascii missing-image rootwait)

run_case() {
	case "$1" in
	fat32)          case_fat32 ;;
	exfat)          case_exfat ;;
	fsck-request)   case_fsck_request ;;
	symlink)        case_symlink ;;
	label)          case_label ;;
	nonascii)       case_nonascii ;;
	missing-image)  case_missing_image ;;
	rootwait)       case_rootwait ;;
	*) die "unknown case '$1' (known: ${ALL_CASES[*]})" ;;
	esac
	RAN=$((RAN + 1))
}

main() {
	local -a requested=("$@")
	[ ${#requested[@]} -eq 0 ] && requested=("${ALL_CASES[@]}")

	check_prereqs
	mkdir -p "$WORK" "$BUILD"
	ensure_qemu_kernel
	build_marker_inits

	log "board: $BOARD ($KARCH, $QEMU_SYSTEM ${QEMU_MACHINE[*]}, kernel $KERNEL_VERSION [$KERNEL series, $(basename "$(dirname "$EXFAT_SYMLINK_PATCH")")/0031], cpio ${CPIO#"$ROOT"/})"
	log "running ${#requested[@]} case(s): ${requested[*]}"
	echo ""
	local c
	for c in "${requested[@]}"; do
		run_case "$c"
	done

	echo ""
	echo "==== scripts/test-initramfs.sh summary ($BOARD, $RAN case(s)) ===="
	printf '%s\n' "${SUMMARY[@]}"
	if [ "$FAILED" -ne 0 ]; then
		echo "==== RESULT: FAIL ===="
		exit 1
	fi
	echo "==== RESULT: PASS ===="
}

main "$@"
