#!/usr/bin/env bash
#
# scripts/lib/installer-qemu-kernel.sh — build the ARM zImage that boots the SD-card
# installer initramfs under `qemu-system-arm -M virt`. Not directly executable;
# sourced. Same reasoning as scripts/ci-lib.sh and scripts/lib/hash-sync-common.sh:
# two harnesses need this recipe and a fix to one should not have to be remembered
# for the other.
#
# The callers:
#   scripts/test-sdcard-install.sh   — the shipped sdcard.img, end to end
#   scripts/test-installer-recovery.sh — the interrupt/recover matrix (ADR 0020 §8)
#
# WHAT IS LOAD-BEARING IN HERE, and why each line resists being "simplified":
#
#   * The kernel version is READ FROM configs/mister_de10nano_defconfig, never
#     hardcoded. Board patch 0031 (exFAT symlinks) tracks the pinned kernel's
#     internal APIs — 6.18.40 gave exfat_remove_entries() a fourth argument — so a
#     stale pin here fails the build with a confusing "too few arguments".
#   * `-m` on merge_config.sh means MERGE ONLY. Without it, merge_config.sh runs a
#     bare `make alldefconfig` whose `make` resolves to this repo's ROOT wrapper
#     Makefile, which forwards to Buildroot and dies "Can't read seed
#     configuration". We reconcile with an explicit `make -C … olddefconfig`.
#   * O= MUST be absolute. A relative O= is resolved against $KERNEL_SRC and
#     silently builds into a nested directory.
#   * The cached initramfs object is deleted before every build: the kernel's own
#     dependency tracking can miss a same-path cpio CONTENT change, which would
#     silently embed a stale /init — exactly the thing these harnesses exist to
#     test.
#
# Inputs (set by the caller before calling iqk_ensure_kernel):
#   IQK_ROOT            repo root
#   IQK_CROSS_COMPILE   ARM cross-toolchain prefix
#   IQK_KERNEL_VERSION  optional; read from the board defconfig when empty
#   IQK_KERNEL_TARBALL  optional; resolved under dl/ when empty
#   IQK_KERNEL_SRC      extracted+patched source tree (shared between harnesses)
#   IQK_KBUILD          out-of-tree build dir (per harness: they differ in the cpio)
#   IQK_CPIO            the installer initramfs to embed
# Output:
#   IQK_ZIMAGE          the built zImage, on success

iqk_log() { printf '[qemu-kernel] %s\n' "$*" >&2; }
iqk_die() { printf '[qemu-kernel] FATAL: %s\n' "$*" >&2; exit 2; }

# The pinned kernel version, from the board defconfig. See the header.
iqk_kernel_version() {
	local v
	v="$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\(.*\)"$/\1/p' \
		"$IQK_ROOT/configs/mister_de10nano_defconfig")"
	[ -n "$v" ] || iqk_die "could not read BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE from configs/mister_de10nano_defconfig"
	printf '%s' "$v"
}

# Locate the kernel tarball. Buildroot shards dl/ by package (dl/linux/linux-X.tar.xz)
# but older trees and manual downloads leave it flat in dl/, so try both rather than
# making the caller know which layout its checkout happens to have.
iqk_kernel_tarball() {
	local ver=$1 c
	for c in "$IQK_ROOT/dl/linux/linux-$ver.tar.xz" "$IQK_ROOT/dl/linux-$ver.tar.xz"; do
		if [ -f "$c" ]; then printf '%s' "$c"; return 0; fi
	done
	# Report the sharded path: that is where a `make all` actually puts it.
	printf '%s' "$IQK_ROOT/dl/linux/linux-$ver.tar.xz"
}

iqk_ensure_kernel() {
	local fragment patch
	fragment="$IQK_ROOT/scripts/test-initramfs/qemu-test-kernel.config"
	patch="$IQK_ROOT/board/mister/de10nano/linux-patches/0031-exfat-samsung-symlinks.patch"

	[ -n "${IQK_ROOT:-}" ]  || iqk_die "IQK_ROOT is not set"
	[ -n "${IQK_KBUILD:-}" ] || iqk_die "IQK_KBUILD is not set"
	[ -n "${IQK_CPIO:-}" ]  || iqk_die "IQK_CPIO is not set"
	[ -f "$IQK_CPIO" ]      || iqk_die "no installer cpio at $IQK_CPIO"
	[ -x "${IQK_CROSS_COMPILE}gcc" ] || iqk_die "ARM cross gcc not found at ${IQK_CROSS_COMPILE}gcc"
	[ -f "$fragment" ] || iqk_die "missing kernel fragment $fragment"
	case "$IQK_KBUILD" in /*) : ;; *) iqk_die "IQK_KBUILD must be an absolute path" ;; esac

	[ -n "${IQK_KERNEL_VERSION:-}" ] || IQK_KERNEL_VERSION="$(iqk_kernel_version)"
	[ -n "${IQK_KERNEL_TARBALL:-}" ] || IQK_KERNEL_TARBALL="$(iqk_kernel_tarball "$IQK_KERNEL_VERSION")"
	[ -n "${IQK_KERNEL_SRC:-}" ]     || IQK_KERNEL_SRC="$IQK_ROOT/work/test-initramfs-kernel-src"

	if [ ! -f "$IQK_KBUILD/.config" ]; then
		if [ ! -d "$IQK_KERNEL_SRC/scripts/kconfig" ]; then
			[ -f "$IQK_KERNEL_TARBALL" ] ||
				iqk_die "kernel source missing: neither $IQK_KERNEL_SRC nor $IQK_KERNEL_TARBALL"
			iqk_log "extracting $IQK_KERNEL_TARBALL -> $IQK_KERNEL_SRC"
			mkdir -p "$IQK_KERNEL_SRC"
			tar -C "$IQK_KERNEL_SRC" --strip-components=1 -xf "$IQK_KERNEL_TARBALL"
		fi
		# fs/exfat symlink support (ADR 0019, board patch 0031) -- idempotent.
		if [ -f "$patch" ] && ! grep -q EXFAT_ATTR_SYMLINK "$IQK_KERNEL_SRC/fs/exfat/exfat_raw.h" 2>/dev/null; then
			iqk_log "applying $(basename "$patch")"
			patch -p1 -s -d "$IQK_KERNEL_SRC" < "$patch" || iqk_die "board patch 0031 failed to apply"
		fi
		mkdir -p "$IQK_KBUILD"
		iqk_log "configuring: multi_v7_defconfig + qemu-test-kernel.config"
		make -C "$IQK_KERNEL_SRC" O="$IQK_KBUILD" ARCH=arm \
			CROSS_COMPILE="$IQK_CROSS_COMPILE" multi_v7_defconfig >&2
		"$IQK_KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$IQK_KBUILD" \
			"$IQK_KBUILD/.config" "$fragment" >&2
	fi

	"$IQK_KERNEL_SRC/scripts/config" --file "$IQK_KBUILD/.config" \
		--set-str CONFIG_INITRAMFS_SOURCE "$IQK_CPIO"
	make -C "$IQK_KERNEL_SRC" O="$IQK_KBUILD" ARCH=arm \
		CROSS_COMPILE="$IQK_CROSS_COMPILE" olddefconfig >&2
	rm -f "$IQK_KBUILD"/usr/initramfs_data.cpio* "$IQK_KBUILD/arch/arm/boot/zImage"
	iqk_log "building QEMU test kernel (embedding $IQK_CPIO)"
	make -C "$IQK_KERNEL_SRC" O="$IQK_KBUILD" ARCH=arm \
		CROSS_COMPILE="$IQK_CROSS_COMPILE" -j"$(nproc)" zImage >&2

	IQK_ZIMAGE="$IQK_KBUILD/arch/arm/boot/zImage"
	[ -f "$IQK_ZIMAGE" ] || iqk_die "kernel build produced no $IQK_ZIMAGE"
}
