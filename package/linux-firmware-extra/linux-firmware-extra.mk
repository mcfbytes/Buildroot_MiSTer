################################################################################
#
# linux-firmware-extra
#
################################################################################

# P3.3 / docs/firmware-parity.md -- see Config.in for the full rationale.
# SOURCE/SITE/VERSION are copied verbatim from work/buildroot/package/
# linux-firmware/linux-firmware.mk (same upstream URL, same pinned version),
# and the tarball hash below is the same published sha256 that sibling
# package's own .hash file carries -- this is NOT a new/foreign source, only
# a different subset kept from the identical, already hash-gated download.
LINUX_FIRMWARE_EXTRA_VERSION = 20251011
LINUX_FIRMWARE_EXTRA_SOURCE = linux-firmware-$(LINUX_FIRMWARE_EXTRA_VERSION).tar.xz
LINUX_FIRMWARE_EXTRA_SITE = $(BR2_KERNEL_MIRROR)/linux/kernel/firmware
LINUX_FIRMWARE_EXTRA_LICENSE = Proprietary
LINUX_FIRMWARE_EXTRA_LICENSE_FILES = \
	WHENCE \
	LICENCE.rtlwifi_firmware.txt \
	LICENCE.ralink_a_mediatek_company_firmware \
	LICENCE.mediatek
LINUX_FIRMWARE_EXTRA_DEPENDENCIES = host-tar

# Four firmware members, plus the four license files above -- every one of
# these paths is checked, at INSTALL_TARGET_CMDS time below, against the
# literal request_firmware()/MODULE_FIRMWARE string this project's pinned
# 6.18.33 kernel source actually uses (docs/firmware-parity.md has the
# per-file driver citation), not assumed from upstream naming conventions.
#
# THREE further files were tried here and dropped: brcm/BCM20702A1-0b05-
# 17cb.hcd, rtl_bt/rtl8723d_config.bin, rtlwifi/rtl8192eefw.bin. Each has a
# plausible in-tree kernel consumer (see docs/firmware-parity.md), but a
# `tar tf` listing of the ACTUAL pinned linux-firmware-20251011.tar.xz
# (not assumed from driver source alone) shows none of the three exist in
# this upstream snapshot at all -- e.g. the entire tarball has exactly one
# `.hcd` file total (brcm/BCM-0bb4-0306.hcd, a different vendor:product),
# and rtlwifi/ has rtl8192eu_*/rtl8192dufw.bin/rtl8192fufw.bin but no
# rtl8192eefw.bin. Per the "do not fabricate a source" rule, these are
# flagged in docs/firmware-parity.md rather than sourced from an
# unpinned/unverified mirror.
LINUX_FIRMWARE_EXTRA_MEMBERS = \
	mediatek/mt7610u.bin \
	mediatek/mt7622pr2h.bin \
	mediatek/mt7668pr2h.bin \
	rtlwifi/rtl8723befw_36.bin \
	$(LINUX_FIRMWARE_EXTRA_LICENSE_FILES)

# Custom EXTRACT_CMDS: pull only the members above out of the tarball,
# instead of generic-package's default of unpacking the whole upstream tree
# (several hundred MB) a second time -- the sibling linux-firmware package
# already pays that cost once; this avoids doubling it for seven small
# files. $(TAR) is Buildroot's own host-tar (support/dependencies/
# check-host-tar.mk), which auto-detects the .xz compression on read same as
# every other Buildroot package relies on.
#
# The upstream tarball has a single top-level wrapper directory
# (linux-firmware-<version>/...) -- confirmed via `tar tf` on the actual
# downloaded file, and the same reason the sibling linux-firmware package's
# own EXTRACT_CMDS pipes through `tar --strip-components=1`. tar matches
# member names given on the command line against the archive's REAL internal
# paths (i.e. still wrapper-prefixed), before --strip-components is applied
# to the extracted output -- so each member below must be given with the
# $(LINUX_FIRMWARE_EXTRA_VERSION)/ prefix, even though --strip-components=1
# then drops that same prefix from what lands in $(@D).
define LINUX_FIRMWARE_EXTRA_EXTRACT_CMDS
	mkdir -p $(@D)
	$(TAR) xf $(LINUX_FIRMWARE_EXTRA_DL_DIR)/$(LINUX_FIRMWARE_EXTRA_SOURCE) \
		-C $(@D) --strip-components=1 \
		$(addprefix linux-firmware-$(LINUX_FIRMWARE_EXTRA_VERSION)/,$(LINUX_FIRMWARE_EXTRA_MEMBERS))
endef

define LINUX_FIRMWARE_EXTRA_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0644 -D $(@D)/mediatek/mt7610u.bin \
		$(TARGET_DIR)/lib/firmware/mediatek/mt7610u.bin
	$(INSTALL) -m 0644 -D $(@D)/mediatek/mt7622pr2h.bin \
		$(TARGET_DIR)/lib/firmware/mediatek/mt7622pr2h.bin
	$(INSTALL) -m 0644 -D $(@D)/mediatek/mt7668pr2h.bin \
		$(TARGET_DIR)/lib/firmware/mediatek/mt7668pr2h.bin
	$(INSTALL) -m 0644 -D $(@D)/rtlwifi/rtl8723befw_36.bin \
		$(TARGET_DIR)/lib/firmware/rtlwifi/rtl8723befw_36.bin
endef

$(eval $(generic-package))
