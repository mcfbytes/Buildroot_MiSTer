################################################################################
#
# xow-firmware
#
################################################################################

# P3.2 / docs/decisions/0003-xone-firmware.md -- the Xbox Wireless Dongle
# firmware. ACCEPTED maintainer decision (2026-07-13): redistribute it for
# stock parity, sourced fresh from Microsoft's own driver package at BUILD
# TIME, hash-pinned at every step, NEVER committed to git (G6). This is the
# same provenance path the xow/xone projects themselves use (their
# install/firmware.sh scripts do exactly this download-and-extract, from the
# same Windows-Update CDN host) -- we are not inventing a new source, only
# doing the fetch as a proper hash-verified Buildroot package instead of an
# ungated shell script run by hand.
#
# SOURCE: the officially published Microsoft Xbox Wireless Adapter driver
# package (WHQL-signed, distributed via Windows Update's public CDN --
# checked live at pin time: HTTP 200, Content-Type
# application/vnd.ms-cab-compressed). This is the exact .cab
# dlundqvist/xone's own install/firmware.sh downloads for USB PID 0x02fe
# (the common "Xbox Wireless Adapter for Windows" dongle, "S" revision) --
# same URL, same expected extracted-file hash, cross-checked against that
# script's own hardcoded manifest before pinning here.
XOW_FIRMWARE_VERSION = 1cd6a87c-623f-4407-a52d-c31be49e925c_e19f60808bdcbfbd3c3df6be3e71ffc52e43261e
XOW_FIRMWARE_SOURCE = $(XOW_FIRMWARE_VERSION).cab
XOW_FIRMWARE_SITE = http://download.windowsupdate.com/c/msdownload/update/driver/drvs/2017/07

# SECOND dongle firmware -- the OLD external adapter, USB PID 0x02e6 ("Xbox
# One Wireless Adapter", model 1713, the original 2015 unit). The xone driver
# binds FOUR dongle PIDs (transport/dongle.c xone_dongle_id_table[]) and at
# runtime requests a DISTINCT per-PID file, `xone_dongle_<pid>.bin`. The two
# EXTERNAL USB adapters a MiSTer can actually have plugged in are 0x02fe (new,
# above) and 0x02e6 (old, here) -- and they use GENUINELY DIFFERENT firmware
# (different .cab, different size: 70620 vs 70008 bytes, different sha256), so
# 0x02e6 cannot be an alias/symlink of the 0x02fe blob -- it must be fetched
# and installed as its own file. Shipping only 0x02fe would leave every owner
# of the (cheaper, very common on the used market) original adapter with a
# hard "Direct firmware load for xone_dongle_02e6.bin failed with error -2"
# and a dead dongle. This is the exact .cab dlundqvist/xone's own
# install/firmware.sh pulls for PID 0x02e6 (2017/03 driver, member
# FW_ACC_00U.bin, extracted-hash cross-checked against that script's manifest;
# .cab hash computed locally, see xow-firmware.hash). Live at pin time: HTTP
# 200, application/vnd.ms-cab-compressed, 216868 bytes.
#
# The other two PIDs the driver binds -- 0x02f9 (ASUS/Lenovo) and 0x091e
# (Surface Book 2) -- are dongles SOLDERED INTO those laptops' mainboards,
# not USB devices; they physically cannot be attached to a DE10-Nano, so
# their firmware is deliberately NOT shipped (dead weight for hardware that
# cannot exist here). Full scope rationale: docs/decisions/0003-xone-firmware.md.
XOW_FIRMWARE_02E6_CAB = 2ea9591b-f751-442c-80ce-8f4692cdc67b_6b555a3a288153cf04aec6e03cba360afe2fce34.cab
XOW_FIRMWARE_EXTRA_DOWNLOADS = http://download.windowsupdate.com/d/msdownload/update/driver/drvs/2017/03/$(XOW_FIRMWARE_02E6_CAB)

# NOT a FOSS license -- Microsoft's own driver/firmware package, covered by
# Microsoft's Terms of Use (https://www.microsoft.com/en-us/legal/terms-of-use),
# not GPL. No LICENSE_FILES: the .cab carries no license text of its own (it
# is a WHQL driver bundle: a .bin firmware blob, a .sys/.cat/.inf Windows
# driver quad) to point Buildroot's legal-info machinery at. Full analysis:
# docs/decisions/0003-xone-firmware.md.
XOW_FIRMWARE_LICENSE = proprietary (Microsoft driver firmware; Terms of Use, not GPL)

XOW_FIRMWARE_DEPENDENCIES = host-cabextract

# Not a tar/zip Buildroot's default $(INFLATE$(suffix ...)) extractor
# understands (there is no INFLATE.cab) -- override, same pattern
# work/buildroot/package/doom-wad/doom-wad.mk uses to pull one named member
# out of a foreign archive format instead of unpacking the whole thing.
# Both .cabs carry a member literally named FW_ACC_00U.bin (different bytes),
# so they MUST extract into separate subdirs or the second clobbers the first.
# Each extracted blob's hash is checked inline right after extraction --
# Buildroot's .hash-file machinery verifies only the DOWNLOADED .cabs (the
# SOURCE + EXTRA_DOWNLOADS, covered in xow-firmware.hash), never a file we then
# derive from one, so this is the second, inner hash gate on the firmware
# itself (both the outer .cab and the inner firmware are pinned, not just one).
define XOW_FIRMWARE_EXTRACT_CMDS
	$(HOST_DIR)/bin/cabextract -d $(@D)/02fe $(XOW_FIRMWARE_DL_DIR)/$(XOW_FIRMWARE_SOURCE)
	@echo "48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66  $(@D)/02fe/FW_ACC_00U.bin" | sha256sum -c -
	$(HOST_DIR)/bin/cabextract -d $(@D)/02e6 $(XOW_FIRMWARE_DL_DIR)/$(XOW_FIRMWARE_02E6_CAB)
	@echo "080ce4091e53a4ef3e5fe29939f51fd91f46d6a88be6d67eb6e99a5723b3a223  $(@D)/02e6/FW_ACC_00U.bin" | sha256sum -c -
endef

# FW_ACC_00U.bin is the extracted member's name inside Microsoft's cab (one
# of four files in it: the .bin firmware, a .sys driver, a .cat signature
# catalog, and an .inf install script -- we want only the firmware). Its
# hash is checked explicitly above, right after extraction (Buildroot's own
# .hash-file machinery only verifies the DOWNLOADED .cab, not a file we then
# derive from it -- xow-firmware.hash covers the .cab; the sha256sum -c line
# above covers the extracted member, so both the outer download and the
# inner firmware blob are hash-gated, not just one of the two).
#
# Three names installed, covering both EXTERNAL dongles the driver binds:
#
#  1. xow_dongle.bin -- stock's literal filename (docs/stock-inventory/
#     firmware.md), for byte-for-byte parity. This is the 0x02fe blob (70620
#     bytes), matching stock's documented size exactly.
#
#  2. xone_dongle_02fe.bin -- what the xone fork (dlundqvist,
#     package/xone/xone.mk) requests via request_firmware() at runtime for a
#     0x02fe-PID (new) dongle (transport/dongle.c:
#     `sprintf(fwname, "xone_dongle_%04x.bin", fw_product)`). Stock's older
#     fork (medusalix) hardcoded the single "xow_dongle.bin" name; dlundqvist
#     moved to a per-PID scheme. Identical bytes to #1, so a symlink (not a
#     copy) -- no reason to duplicate the blob.
#
#  3. xone_dongle_02e6.bin -- the 0x02e6 (old) dongle's firmware. A DISTINCT
#     70008-byte blob (different .cab, different sha256), so a REAL FILE, not
#     an alias of #1 -- symlinking it to xow_dongle.bin would load the wrong
#     firmware onto the old adapter. Without this file, an owner of the
#     original Xbox One Wireless Adapter gets "Direct firmware load for
#     xone_dongle_02e6.bin failed with error -2" and a dead dongle.
define XOW_FIRMWARE_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0644 -D $(@D)/02fe/FW_ACC_00U.bin \
		$(TARGET_DIR)/lib/firmware/xow_dongle.bin
	ln -sf xow_dongle.bin $(TARGET_DIR)/lib/firmware/xone_dongle_02fe.bin
	$(INSTALL) -m 0644 -D $(@D)/02e6/FW_ACC_00U.bin \
		$(TARGET_DIR)/lib/firmware/xone_dongle_02e6.bin
endef

$(eval $(generic-package))
