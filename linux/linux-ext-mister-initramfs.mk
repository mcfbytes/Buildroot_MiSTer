################################################################################
#
# Linux kernel extension: MiSTer stage-1 initramfs (ADR 0002)
#
################################################################################

# Included by linux/linux.mk BEFORE it evaluates the kernel package (that is
# what a linux-ext-*.mk is for), so package/mister-initramfs becomes a real
# dependency of the kernel: LINUX_PATCH_DEPENDENCIES += mister-initramfs is
# derived from LINUX_EXTENSIONS by linux.mk itself. external.mk cannot do
# that -- it is included after the kernel's prerequisites are expanded.
#
# The fixup below is what makes CONFIG_INITRAMFS_SOURCE point at the cpio. It
# runs at kernel kconfig-fixup time, after board/mister/<board>/linux.config
# is loaded, and it is deliberately NOT in that committed linux.config: an
# absolute build path has no place in a defconfig, and setting the symbol via
# a kernel-config fragment would break `make linux-update-defconfig`
# (pkg-kconfig.mk refuses to save a config assembled from fragments).
#
# Compression: the kernel's usr/Kconfig initramfs-compression choice has NO
# default, so it is pinned to gzip explicitly (with the matching CONFIG_RD_).
# The cpio itself is uncompressed; compressing twice would be pointless.

LINUX_EXTENSIONS += mister-initramfs

ifeq ($(BR2_LINUX_KERNEL_EXT_MISTER_INITRAMFS),y)

# LINUX_EXTENSIONS only orders the kernel's PATCH stage after the extension's
# PATCH stage (linux.mk derives LINUX_PATCH_DEPENDENCIES from it -- enough for
# xenomai, whose prepare-kernel needs sources, not a build). The cpio has to be
# BUILT and installed before the kernel's kconfig fixup runs, so the package is
# a full dependency as well. This file is included before linux.mk evaluates
# the kernel package, which is the only place this line can take effect.
LINUX_DEPENDENCIES += mister-initramfs

# Overridable on the make command line: scripts/mk-sdcard.sh relinks the
# kernel around the installer's cpio with MISTER_INITRAMFS_CPIO=<file>.
MISTER_INITRAMFS_CPIO ?= $(BINARIES_DIR)/mister-initramfs.cpio

# Nothing to do at kernel-patch time; the hook must exist because linux.mk
# registers <EXT>_PREPARE_KERNEL for every enabled extension.
define MISTER_INITRAMFS_PREPARE_KERNEL
endef

define MISTER_INITRAMFS_LINUX_KCONFIG_FIXUP
	@if [ ! -f "$(MISTER_INITRAMFS_CPIO)" ]; then \
		echo "*** MISTER: stage-1 initramfs cpio not found: $(MISTER_INITRAMFS_CPIO)"; \
		echo "*** The kernel cannot boot without it (U-Boot never loads an initrd, A3)."; \
		echo "*** Is BR2_PACKAGE_MISTER_INITRAMFS built? (make mister-initramfs)"; \
		exit 1; \
	fi
	@$(call MESSAGE,"Embedding stage-1 initramfs: $(MISTER_INITRAMFS_CPIO)")
	$(call KCONFIG_ENABLE_OPT,CONFIG_BLK_DEV_INITRD)
	$(call KCONFIG_SET_OPT,CONFIG_INITRAMFS_SOURCE,"$(MISTER_INITRAMFS_CPIO)")
	$(call KCONFIG_SET_OPT,CONFIG_INITRAMFS_ROOT_UID,0)
	$(call KCONFIG_SET_OPT,CONFIG_INITRAMFS_ROOT_GID,0)
	$(call KCONFIG_ENABLE_OPT,CONFIG_RD_GZIP)
	$(call KCONFIG_ENABLE_OPT,CONFIG_INITRAMFS_COMPRESSION_GZIP)
endef
LINUX_KCONFIG_FIXUP_CMDS += $(sep)$(MISTER_INITRAMFS_LINUX_KCONFIG_FIXUP)

endif
