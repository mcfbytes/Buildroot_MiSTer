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
#
# The four mediatek/mt7663* files are NOT a stock-parity item (stock ships no
# mt7663 firmware at all): they back CONFIG_MT7663U=m, which this project
# enables beyond stock, and which would otherwise probe and then fail at
# request_firmware(). They are here for the same reason as the rest -- no
# BR2_PACKAGE_LINUX_FIRMWARE_* sub-option installs any mt7663 file (Buildroot's
# MediaTek options stop at MT7601U/MT7610E/MT76X2E/MT7921/MT7925), so the only
# way to ship them from the pinned, hash-verified tarball is here.
LINUX_FIRMWARE_EXTRA_MEMBERS = \
	mediatek/mt7610u.bin \
	mediatek/mt7622pr2h.bin \
	mediatek/mt7663_n9_rebb.bin \
	mediatek/mt7663_n9_v3.bin \
	mediatek/mt7663pr2h.bin \
	mediatek/mt7663pr2h_rebb.bin \
	mediatek/mt7668pr2h.bin \
	rtlwifi/rtl8723befw_36.bin

# Copy the firmware members out of linux-firmware's extracted tree into our own
# $(@D) for INSTALL_TARGET_CMDS below. -D creates the parent directory.
#
# Both command blocks are generated from _MEMBERS with $(foreach ... $(sep)) --
# $(sep) is Buildroot's own newline macro (support/misc/utils.mk), the
# established idiom for emitting one recipe line per list item. Before this the
# same file list was written out three times (_MEMBERS plus both recipes); the
# three agreed, but adding the mt7663 files would have meant editing all three
# in lockstep, and a miss in either recipe fails silently -- a file listed in
# _MEMBERS but never copied, or copied but never installed. Deriving both
# recipes from the single list makes that class of drift impossible.
define LINUX_FIRMWARE_EXTRA_EXTRACT_CMDS
	$(foreach f,$(LINUX_FIRMWARE_EXTRA_MEMBERS), \
		$(INSTALL) -m 0644 -D $(LINUX_FIRMWARE_DIR)/$(f) $(@D)/$(f)$(sep))
endef

define LINUX_FIRMWARE_EXTRA_INSTALL_TARGET_CMDS
	$(foreach f,$(LINUX_FIRMWARE_EXTRA_MEMBERS), \
		$(INSTALL) -m 0644 -D $(@D)/$(f) $(TARGET_DIR)/lib/firmware/$(f)$(sep))
endef

$(eval $(generic-package))
