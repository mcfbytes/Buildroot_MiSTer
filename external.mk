################################################################################
#
# external.mk for the MISTER BR2_EXTERNAL tree
#
# Pulls in every package .mk under package/*/*.mk. P3.1 added the six Realtek
# Wi-Fi kernel-module packages (rtl8188eu, rtl8188fu, rtl8812au, rtl8821au,
# rtl8821cu, rtl88x2bu); P3.2 will add xone the same way (see PLAN.md §6,
# TASKS.md class E). This is the standard Buildroot br2-external idiom, so new
# packages need no change here — just add package/<name>/<name>.mk.
#
################################################################################

include $(sort $(wildcard $(BR2_EXTERNAL_MISTER_PATH)/package/*/*.mk))

################################################################################
#
# P1.10 — stage-2 half of the two-stage initramfs build (A1, PLAN.md §5,
# docs/decisions/0002-initramfs.md).
#
# Stage 1 (configs/mister_initramfs_defconfig, driven by the top-level Makefile's
# `initramfs` target) produces output-initramfs/images/rootfs.cpio. This block is
# what makes the MAIN build's kernel swallow it: it injects CONFIG_INITRAMFS_SOURCE
# into the kernel .config at kconfig-fixup time, which is the same mechanism
# Buildroot itself uses for BR2_TARGET_ROOTFS_INITRAMFS (linux/linux.mk:412-419) —
# we just point it at a different, much smaller cpio.
#
# WHY HERE AND NOT IN THE DEFCONFIG. The obvious alternative is
# BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES in configs/mister_de10nano_defconfig. Do
# not: package/pkg-kconfig.mk:19-20 makes `make linux-update-defconfig` and
# `make linux-savedefconfig` HARD-FAIL ("Unable to perform when fragment files are
# set") as soon as any fragment is configured — and those are precisely the commands
# P1.3 uses to regenerate board/mister/de10nano/linux.config. Doing it here keeps
# that workflow intact and keeps an absolute build path out of a committed defconfig.
#
# Ordering is safe: Buildroot's Makefile includes linux/linux.mk (line 553) before
# $(BR2_EXTERNAL_MKS) (line 564), and LINUX_KCONFIG_FIXUP_CMDS is expanded lazily
# inside the .stamp_kconfig_fixup_done recipe, so appending to it here works.
# $(sep) is Buildroot's newline (support/misc/utils.mk:103) — a bare `+=` would
# splice our first command onto the tail of linux.mk's last one.
#
################################################################################

ifeq ($(BR2_LINUX_KERNEL),y)

# Overridable so CI can build the two stages in separate workspaces.
MISTER_INITRAMFS_CPIO ?= $(BR2_EXTERNAL_MISTER_PATH)/output-initramfs/images/rootfs.cpio

define MISTER_LINUX_INITRAMFS_FIXUP
	@if [ ! -f "$(MISTER_INITRAMFS_CPIO)" ]; then \
		echo "*** MISTER: stage-1 initramfs cpio not found:"; \
		echo "***   $(MISTER_INITRAMFS_CPIO)"; \
		echo "*** The kernel cannot be built without it — U-Boot never loads an"; \
		echo "*** initrd (A3), so the cpio must be INSIDE the zImage. Build it with:"; \
		echo "***   make initramfs"; \
		echo "*** (the top-level 'make all' does this for you)."; \
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

# CONFIG_INITRAMFS_COMPRESSION_* is set explicitly rather than left to kconfig. The
# choice in usr/Kconfig carries NO `default`, so it silently resolves to its first
# visible entry — today that happens to be GZIP, but "whatever is listed first
# upstream" is not something a boot path should depend on. We ship an UNCOMPRESSED
# cpio (BR2_TARGET_ROOTFS_CPIO_NONE in stage 1) and let the kernel gzip it here:
# compressing it twice would be pointless, and gzip beats leaving it raw for the
# LZ4-compressed zImage to squeeze (LZ4 optimises for decode speed, not ratio).
LINUX_KCONFIG_FIXUP_CMDS += $(sep)$(MISTER_LINUX_INITRAMFS_FIXUP)

endif # BR2_LINUX_KERNEL
