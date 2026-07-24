################################################################################
#
# linux-firmware-extra
#
################################################################################

# P3.3 / docs/firmware-parity.md -- see Config.in for the full rationale.
#
# Installs the handful of firmware files that stock MiSTer ships, and that this
# project's pinned kernel actually request_firmware()s, but that NO
# BR2_PACKAGE_LINUX_FIRMWARE_* sub-option installs (the four MEMBERS below).
#
# It does NOT fetch or unpack a tarball of its own. It takes the files straight
# out of the linux-firmware package's OWN already-extracted tree
# ($(LINUX_FIRMWARE_DIR)) -- the identical upstream snapshot, downloaded +
# hash-verified + extracted exactly ONCE by that package. This package used to
# fetch its own full ~600 MiB linux-firmware tarball at a SEPARATELY pinned
# version, which:
#   (a) DRIFTED -- it sat at 20251011 while the real linux-firmware package
#       moved to 20260410 (a fork-sync of upstream Buildroot bumps
#       linux-firmware automatically; this package is on renovate-hash-sync's
#       "NEVER automated" list and nothing re-pinned it), so the four files
#       shipped a ~6-month-older snapshot than every other firmware file, and
#   (b) DOUBLED the download + dl/ footprint for content that is a strict
#       subset of what linux-firmware already fetched.
# Reading from $(LINUX_FIRMWARE_DIR) makes version parity STRUCTURAL (there is
# no second version to keep in sync) and removes the duplicate fetch/extract.
# `depends on BR2_PACKAGE_LINUX_FIRMWARE` (Config.in) guarantees that tree
# exists whenever this package is enabled -- it also means this package no
# longer builds in the kernel-only variants (mister_kernel_defconfig does not
# enable linux-firmware), where its files landed in a target/ that is thrown
# away and only cost a wasted ~557 MiB fetch.

# LEGAL-INFO: this package has no _SOURCE of its own, so Buildroot's legal-info
# treats it as "part of Buildroot" and skips it entirely -- no manifest row, no
# license collection (pkg-generic.mk guards the whole license/manifest block on
# a non-empty _SOURCE). That is correct here: the four files ARE linux-firmware
# files, and linux-firmware -- a hard dependency, always built when this package
# is -- already records them under its own SBOM entry. Its
# LINUX_FIRMWARE_LICENSE_FILES lists WHENCE + LICENCE.mediatek +
# LICENCE.ralink_a_mediatek_company_firmware + LICENCE.rtlwifi_firmware.txt,
# exactly the licenses our four files fall under, so the attribution is complete
# via linux-firmware rather than duplicated here.
LINUX_FIRMWARE_EXTRA_LICENSE = Proprietary

# Reported version tracks linux-firmware's -- used only for the build-dir name,
# NOT for a download (there is none). No separate pin, so no separate drift.
# (`=`, not `:=`: deferred so the forward reference to LINUX_FIRMWARE_VERSION
# resolves after all package .mk files are parsed.)
LINUX_FIRMWARE_EXTRA_VERSION = $(LINUX_FIRMWARE_VERSION)
# No source of our own: an empty _SOURCE means pkg-generic.mk builds an empty
# _MAIN_DOWNLOAD (it is guarded on _SOURCE being non-empty), so nothing is
# downloaded. Set explicitly (`=`) so the infra's `?=` default cannot fill it.
LINUX_FIRMWARE_EXTRA_SOURCE =

# Our .stamp_extracted must run AFTER linux-firmware is built, so that
# $(LINUX_FIRMWARE_DIR) is populated when EXTRACT_CMDS copies out of it.
# pkg-generic.mk gates .stamp_extracted on _EXTRACT_DEPENDENCIES specifically
# (regular _DEPENDENCIES gates only -configure, which is too late for a copy we
# do at extract time).
LINUX_FIRMWARE_EXTRA_EXTRACT_DEPENDENCIES = linux-firmware

# Every path here is checked against the literal request_firmware()/
# MODULE_FIRMWARE string this project's pinned kernel uses (docs/firmware-
# parity.md has the per-file driver citation), and confirmed present in the
# linux-firmware tree (verified against the extracted 20260410 tree, not
# assumed from upstream naming). THREE further candidates were tried and
# dropped -- see Config.in and docs/firmware-parity.md.
LINUX_FIRMWARE_EXTRA_MEMBERS = \
	mediatek/mt7610u.bin \
	mediatek/mt7622pr2h.bin \
	mediatek/mt7668pr2h.bin \
	rtlwifi/rtl8723befw_36.bin

# Copy the four firmware members out of linux-firmware's extracted tree into
# our own $(@D) for INSTALL_TARGET_CMDS below. -D creates the parent directory.
define LINUX_FIRMWARE_EXTRA_EXTRACT_CMDS
	$(INSTALL) -m 0644 -D $(LINUX_FIRMWARE_DIR)/mediatek/mt7610u.bin $(@D)/mediatek/mt7610u.bin
	$(INSTALL) -m 0644 -D $(LINUX_FIRMWARE_DIR)/mediatek/mt7622pr2h.bin $(@D)/mediatek/mt7622pr2h.bin
	$(INSTALL) -m 0644 -D $(LINUX_FIRMWARE_DIR)/mediatek/mt7668pr2h.bin $(@D)/mediatek/mt7668pr2h.bin
	$(INSTALL) -m 0644 -D $(LINUX_FIRMWARE_DIR)/rtlwifi/rtl8723befw_36.bin $(@D)/rtlwifi/rtl8723befw_36.bin
endef

define LINUX_FIRMWARE_EXTRA_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0644 -D $(@D)/mediatek/mt7610u.bin $(TARGET_DIR)/lib/firmware/mediatek/mt7610u.bin
	$(INSTALL) -m 0644 -D $(@D)/mediatek/mt7622pr2h.bin $(TARGET_DIR)/lib/firmware/mediatek/mt7622pr2h.bin
	$(INSTALL) -m 0644 -D $(@D)/mediatek/mt7668pr2h.bin $(TARGET_DIR)/lib/firmware/mediatek/mt7668pr2h.bin
	$(INSTALL) -m 0644 -D $(@D)/rtlwifi/rtl8723befw_36.bin $(TARGET_DIR)/lib/firmware/rtlwifi/rtl8723befw_36.bin
endef

$(eval $(generic-package))
