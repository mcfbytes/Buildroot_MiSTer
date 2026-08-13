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

################################################################################
#
# bluez5_utils VERSION OVERRIDE — DS3/SIXAXIS over Bluetooth, and HID fixes
#
# Buildroot 2026.05.1 pins bluez5_utils 5.79 (package/bluez5_utils/
# bluez5_utils.mk:8). This image needs newer, for three reasons, in descending
# order of importance:
#
#   1. DS3/SIXAXIS OVER BLUETOOTH. 5.79 cannot connect a PS3 pad at all: the
#      pad does not do canonical bonding with encryption, and BlueZ's
#      ClassicBondedOnly=true default rejects it before the (already enabled)
#      sixaxis plugin matters. The fix is upstream's four-commit CablePairing
#      series, first released in 5.83 — the input server listens at
#      BT_IO_SEC_LOW and re-raises to BT_IO_SEC_MEDIUM for everything EXCEPT a
#      device carrying the new CablePairing property. So the DS3 connects and
#      every other BR/EDR HID device keeps encryption enforced. The usual
#      retro-distro fix, ClassicBondedOnly=false, would instead drop that
#      requirement for ALL BR/EDR HID and re-expose CVE-2023-45866; upstream
#      closed bluez#688 with this series precisely to avoid that.
#   2. bluez#1710, "input/device: Fix off by one report descriptor size error"
#      (in 5.87). A HID report-descriptor sizing bug — squarely in the path
#      every Bluetooth controller on this image takes.
#   3. Four more releases of ordinary BR/EDR and HID fixes.
#
# WHY AN OVERRIDE AND NOT A PATCH SERIES. This started as backported patches
# under board/mister/de10nano/patches/bluez5_utils/. That approach shipped a
# latent build break: the CablePairing series is FOUR commits, the first cut
# carried three, and the result applied cleanly with `patch` while leaving
# profiles/input/manager.c calling a btd_adapter_has_cable_pairing_devices()
# that nothing defined — an unconditional compile failure under gcc 14.4's
# -Wimplicit-function-declaration. "The series applies" and "the series
# builds" are different claims. A coherent upstream release cannot have that
# class of defect, so the patches were dropped in favour of this.
#
# WHAT WAS CHECKED BEFORE MAKING THIS SWITCH (not assumed):
#   - The override propagates. BLUEZ5_UTILS_{VERSION,SOURCE,DIR} are lazy `=`
#     assignments, so reassigning VERSION here re-derives the tarball name and
#     build dir. Verified with `make printvars`.
#   - The hash travels with it. BR2_DOWNLOAD_FORCE_CHECK_HASHES=y, so a
#     missing hash entry fails the build CLOSED rather than silently fetching
#     an unverified tarball. The companion hash lives at
#     board/mister/de10nano/patches/bluez5_utils/bluez5_utils.hash —
#     pkg-patch-hash-dirs (package/pkg-utils.mk:164) searches
#     $(BR2_GLOBAL_PATCH_DIR)/<pkg>/ for hashes as well as patches, the same
#     mechanism board/mister/de10nano/patches/linux/linux.hash already uses.
#   - No dependency coupling breaks. `ell` is only pulled in by
#     --enable-mesh, which this image does not enable.
#   - Configure-option drift is benign. 5.87 REMOVED the `health` and `sap`
#     AC_ARG_ENABLE options that bluez5_utils.mk still passes as
#     --disable-health/--disable-sap. autotools warns on an unrecognised
#     option rather than failing, and since we wanted both OFF and they are
#     now gone entirely, the effective build is unchanged. Noted because it IS
#     a divergence from Buildroot's tested combination; it is the same class
#     as the --disable-asan/lsan/ubsan/pie flags the .mk already passes, which
#     no bluez in this range defines either.
#
# NOT VERIFIED HERE: that a DS3 actually pairs and connects on real hardware.
# That is the claim of the change and it needs a pad. See
# docs/bluetooth-parity.md §10.
#
################################################################################

ifeq ($(BR2_PACKAGE_BLUEZ5_UTILS),y)

MISTER_BLUEZ5_UTILS_VERSION = 5.87

# This file is parsed AFTER package/*/*.mk (Buildroot's Makefile:550 vs :564),
# so BLUEZ5_UTILS_VERSION still holds Buildroot's OWN pin at this point. Compare
# the two and fail LOUDLY the moment upstream Buildroot catches up.
#
# This guard is the whole reason a version override is safe to carry. Without
# it, a Buildroot bump to a release shipping bluez >= 5.87 would leave this
# line silently pinning the tree BACKWARD to an older bluez than Buildroot
# itself ships — a downgrade nobody would see in a diff, and exactly the
# failure mode an override invites. Renovate keeps this pin moving forward on
# its own (see renovate.json); the guard covers the other axis.
MISTER_BLUEZ5_NEWEST := $(shell printf '%s\n%s\n' \
	'$(BLUEZ5_UTILS_VERSION)' '$(MISTER_BLUEZ5_UTILS_VERSION)' | sort -V | tail -1)

ifeq ($(BLUEZ5_UTILS_VERSION),$(MISTER_BLUEZ5_UTILS_VERSION))
$(error MISTER: Buildroot now pins bluez5_utils $(BLUEZ5_UTILS_VERSION) itself, \
	which equals this tree's override. Delete the bluez5_utils block at the end \
	of external.mk, delete board/mister/de10nano/patches/bluez5_utils/bluez5_utils.hash, \
	drop the nowrep-style manager for it from renovate.json, and update \
	docs/bluetooth-parity.md §10)
else ifeq ($(MISTER_BLUEZ5_NEWEST),$(BLUEZ5_UTILS_VERSION))
$(error MISTER: Buildroot now pins bluez5_utils $(BLUEZ5_UTILS_VERSION), which is \
	NEWER than this tree's override of $(MISTER_BLUEZ5_UTILS_VERSION). Keeping the \
	override would DOWNGRADE bluez. Delete the bluez5_utils block at the end of \
	external.mk and its companion hash file, then re-verify DS3 support against \
	the newer version — see docs/bluetooth-parity.md §10)
endif

BLUEZ5_UTILS_VERSION = $(MISTER_BLUEZ5_UTILS_VERSION)

endif # BR2_PACKAGE_BLUEZ5_UTILS
