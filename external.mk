################################################################################
#
# external.mk for the MISTER BR2_EXTERNAL tree
#
# Pulls in every package .mk under package/*/*.mk. P3.1 added the Realtek
# Wi-Fi kernel-module packages; v9 narrowed the SELECTED set (defconfig) to the
# three 802.11ac chips with no mainline USB driver -- rtl8812au, rtl8814au-morrownr
# and rtl8821au-morrownr -- and moved 8188eu/8188fu/8821cu/8822bu onto in-kernel
# drivers (rtl8xxxu/rtw88; the now-deselected packages stay in the tree as a
# selectable fallback). P3.2 added xone (Xbox One/Series accessory driver) the
# same way (see PLAN.md §6, TASKS.md class D/E). This is the standard Buildroot
# br2-external idiom, so new packages need no change here — just add
# package/<name>/<name>.mk.
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

# WHY THE ARCH TEST — added with the DE25-Nano target (D2.1).
#
# BR2_LINUX_KERNEL=y alone was the right condition while every output directory
# in this tree built for the same armv7 board. It no longer is:
# configs/mister_de25nano_defconfig builds an AARCH64 kernel for a different
# board (Agilex 5), in output-de25/, and this hook keys on the *symbol*, not on
# which defconfig or which O= is in play — so without a second test it would
# fire there too and try to embed $(MISTER_INITRAMFS_CPIO) into that kernel.
#
# Two things would go wrong, one loudly and one not:
#   1. LOUDLY, and only by luck: the fixup hard-fails if the cpio is absent, so
#      a DE25 build in a tree that had never run `make initramfs` would die with
#      an error message telling the developer to build a stage-1 initramfs their
#      board does not have and does not want.
#   2. QUIETLY, which is the real hazard: in a tree that HAS run `make
#      initramfs` (i.e. any tree that has built the DE10 image — so, every
#      developer's, and CI's), the cpio exists and the fixup succeeds. The
#      aarch64 kernel then ships an armv7 BusyBox as its initramfs, boots, runs
#      /init, and fails at the first exec with a message about the *binary*
#      rather than about the build. A green build that produces that is worse
#      than no build.
#
# THE TEST IS ON THE ARCHITECTURE, not on a board name or a defconfig name, and
# that is the point: the thing that makes this hook wrong for the DE25 is not
# "it is the DE25", it is that the cpio is armv7 userspace. Every output dir
# this hook is *meant* for -- the main DE10 image, configs/mister_kernel_defconfig
# and the rt variant built on it -- is BR2_arm=y, and every one of them wants the
# cpio. So `BR2_arm` names the actual precondition and needs no maintenance when
# a fourth armv7 variant or a second aarch64 board appears.
#
# Considered and rejected: a BR2_EXTERNAL Config.in symbol (e.g. a
# "BR2_PACKAGE_MISTER_EMBED_STAGE1_INITRAMFS" bool) would be more explicit, but
# it would have to be added to configs/mister_de10nano_defconfig AND
# configs/mister_kernel_defconfig to keep them building — editing both files
# that scripts/check-kernel-defconfig-sync.sh locks in lockstep, and changing
# the DE10's toolchain-fingerprint cache key, for zero behavioural difference.
# Revisit if a third board ever needs a stage-1 cpio of its own architecture.
ifeq ($(BR2_LINUX_KERNEL)$(BR2_arm),yy)

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

endif # BR2_LINUX_KERNEL && BR2_arm
