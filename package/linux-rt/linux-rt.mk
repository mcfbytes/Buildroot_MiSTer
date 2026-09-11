################################################################################
#
# linux-rt -- the PREEMPT_RT kernel variant, built beside the main kernel
#
################################################################################

# ADR 0030 Phase C (amends ADR 0021). Until 2026-09 this kernel was a separate
# kernel-only Buildroot tree (output-rt/) whose module tree the wrapper
# Makefile copied into an overlay for the next `make all` to fold into
# linux.img, with stamps to remove stale trees because Buildroot's overlay
# rsync never deletes. As a package of the main configuration all of that
# disappears: modules_install lands in TARGET_DIR directly, depmod runs in a
# target-finalize hook like the main kernel's, and one `make` produces both
# kernels and the one image. Precedent: boot/barebox's barebox-aux (same
# source, second config, one tree).
#
# Everything kernel-generic is REUSED from linux/linux.mk rather than copied:
# LINUX_MAKE_ENV / LINUX_MAKE_FLAGS (ARCH, CROSS_COMPILE, KCFLAGS,
# INSTALL_MOD_PATH, reproducible KBUILD_* under BR2_REPRODUCIBLE),
# LINUX_KCONFIG_FIXUP_CMDS (every BR2_-driven kernel fixup, the
# PACKAGES_LINUX_CONFIG_FIXUPS every kmod/lvm2-style package contributes, and
# the stage-1 cpio fixup linux/linux-ext-mister-initramfs.mk appends to it),
# LINUX_DTBS / LINUX_IMAGE_NAME / LINUX_TARGET_NAME. The kconfig-package
# infrastructure's KCONFIG_* helpers act on THIS package's .config at recipe
# time (PKG=LINUX_RT), so the shared fixup body needs no adaptation.

LINUX_RT_VERSION = $(call qstrip,$(BR2_PACKAGE_LINUX_RT_VERSION))
LINUX_RT_SOURCE = linux-$(LINUX_RT_VERSION).tar.xz
LINUX_RT_SITE = $(call qstrip,$(BR2_KERNEL_MIRROR))/linux/kernel/v$(firstword $(subst ., ,$(LINUX_RT_VERSION))).x
LINUX_RT_DL_SUBDIR = linux
LINUX_RT_LICENSE = GPL-2.0 WITH Linux-syscall-note
LINUX_RT_LICENSE_FILES = COPYING
LINUX_RT_CPE_ID_VENDOR = linux
LINUX_RT_CPE_ID_PRODUCT = linux_kernel
LINUX_RT_INSTALL_IMAGES = YES

# The same host tools the main kernel needs (kmod for depmod, compressors,
# firmware for CONFIG_EXTRA_FIRMWARE, ...), plus the cpio it embeds.
LINUX_RT_DEPENDENCIES = $(LINUX_DEPENDENCIES) mister-initramfs
LINUX_RT_KCONFIG_DEPENDENCIES = $(LINUX_KCONFIG_DEPENDENCIES)

LINUX_RT_MAKE_ENV = $(LINUX_MAKE_ENV)
LINUX_RT_MAKE_FLAGS = $(LINUX_MAKE_FLAGS)
LINUX_RT_ARCH_PATH = $(@D)/arch/$(KERNEL_ARCH)

# Base config = the main kernel's; the RT delta rides on top as a fragment.
LINUX_RT_KCONFIG_FILE = $(call qstrip,$(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))
LINUX_RT_KCONFIG_FRAGMENT_FILES = $(call qstrip,$(BR2_PACKAGE_LINUX_RT_CONFIG_FRAGMENT_FILES))
LINUX_RT_KCONFIG_EDITORS = menuconfig nconfig
LINUX_RT_KCONFIG_OPTS = $(LINUX_KCONFIG_OPTS)
LINUX_RT_KCONFIG_FIXUP_CMDS = $(LINUX_KCONFIG_FIXUP_CMDS)

LINUX_RT_VERSION_PROBED = `MAKEFLAGS='$(filter-out w,$(MAKEFLAGS))' $(BR2_MAKE) $(LINUX_RT_MAKE_FLAGS) -C $(LINUX_RT_DIR) --no-print-directory -s kernelrelease 2>/dev/null`

# The RT proof. merge_config.sh only WARNS when a fragment symbol is dropped
# and olddefconfig silently discards symbols whose dependencies fail, so
# without this a plain 7.2 kernel would ship labeled zImage_dtb-rt. Checked
# before the (long) compile so a wrong config fails in seconds.
define LINUX_RT_ASSERT_PREEMPT_RT
	@grep -qx 'CONFIG_PREEMPT_RT=y' $(@D)/.config || { \
		echo "*** linux-rt: the configured kernel is NOT RT: CONFIG_PREEMPT_RT=y is absent from $(@D)/.config."; \
		echo "*** Two config layers are in play: board/mister/de10nano/linux-rt.fragment (kernel"; \
		echo "*** config, where CONFIG_PREEMPT_RT lives) and BR2_PACKAGE_LINUX_RT_* (Buildroot config)."; \
		echo "*** Check the fragment against this kernel version's Kconfig (docs/rt-beta-kernel.md §1)."; \
		exit 1; }
endef
LINUX_RT_POST_CONFIGURE_HOOKS += LINUX_RT_ASSERT_PREEMPT_RT

define LINUX_RT_BUILD_CMDS
	$(call KCONFIG_DISABLE_OPT,CONFIG_GCC_PLUGINS)
	$(LINUX_RT_MAKE_ENV) $(BR2_MAKE) $(LINUX_RT_MAKE_FLAGS) -C $(@D) all
	$(LINUX_RT_MAKE_ENV) $(BR2_MAKE) $(LINUX_RT_MAKE_FLAGS) -C $(@D) $(LINUX_TARGET_NAME)
	$(LINUX_RT_MAKE_ENV) $(BR2_MAKE) $(LINUX_RT_MAKE_FLAGS) -C $(@D) $(LINUX_DTBS)
endef

# zImage_dtb-rt is zImage + DTB concatenated, exactly as
# board/mister/de10nano/post-image.sh assembles the main kernel's zImage_dtb,
# and it gets the same budget/DTB-at-EOF check. linux-rt.config is what the
# release publishes next to it.
define LINUX_RT_INSTALL_IMAGES_CMDS
	cat $(LINUX_RT_ARCH_PATH)/boot/$(LINUX_IMAGE_NAME) \
		$(addprefix $(LINUX_RT_ARCH_PATH)/boot/dts/,$(LINUX_DTBS)) \
		> $(BINARIES_DIR)/zImage_dtb-rt
	$(BR2_EXTERNAL_MISTER_PATH)/scripts/check-zimage-dtb.sh $(BINARIES_DIR)/zImage_dtb-rt
	$(INSTALL) -m 0644 $(@D)/.config $(BINARIES_DIR)/linux-rt.config
endef

# LINUX_RT_VERSION_PROBED shells out to `make kernelrelease`; each recipe
# below evaluates it ONCE into a shell variable rather than inlining it per use.
define LINUX_RT_INSTALL_TARGET_CMDS
	@if grep -q "CONFIG_MODULES=y" $(@D)/.config; then \
		kver=$(LINUX_RT_VERSION_PROBED); \
		$(LINUX_RT_MAKE_ENV) $(BR2_MAKE1) $(LINUX_RT_MAKE_FLAGS) -C $(@D) modules_install; \
		rm -f $(TARGET_DIR)/lib/modules/$$kver/build ; \
		rm -f $(TARGET_DIR)/lib/modules/$$kver/source ; \
	fi
endef

# linux.mk's own LINUX_RUN_DEPMOD only depmods the main kernel's version, so
# this tree gets its own -- and a non-empty modules.alias is asserted, because
# a tree without one cannot autoload a single driver on the device.
define LINUX_RT_RUN_DEPMOD
	@kver=$(LINUX_RT_VERSION_PROBED); \
	if test -d $(TARGET_DIR)/lib/modules/$$kver \
		&& grep -q "CONFIG_MODULES=y" $(LINUX_RT_DIR)/.config; then \
		$(HOST_DIR)/sbin/depmod -a -b $(TARGET_DIR) $$kver; \
		test -s $(TARGET_DIR)/lib/modules/$$kver/modules.alias || { \
			echo "*** linux-rt: $(TARGET_DIR)/lib/modules/$$kver/modules.alias is missing or empty -- depmod did not run; this tree cannot autoload modules on device"; exit 1; }; \
		echo ">>> linux-rt $$kver: module tree depmod'd in $(TARGET_DIR)/lib/modules/$$kver"; \
	fi
endef
LINUX_RT_TARGET_FINALIZE_HOOKS += LINUX_RT_RUN_DEPMOD

$(eval $(kconfig-package))
