################################################################################
#
# bcm20702-firmware
#
################################################################################

# P3.14 -- the Broadcom BCM20702 Bluetooth adapter's patch-RAM firmware
# (brcm/BCM20702A1-0b05-17cb.hcd), which btbcm uploads to BCM20702-based USB
# BT dongles after power-up (the very common ASUS USB-BT400, model 0b05:17cb,
# and compatible generics; kernel CONFIG_BT_HCIBTUSB_BCM=y). Without it those
# dongles enumerate but never come up. Stock ships this exact file
# (docs/stock-inventory/firmware.md, 35000 bytes); it is NOT in mainline
# linux-firmware, so P3.3 left it as a flagged gap (docs/firmware-parity.md).
#
# REDISTRIBUTION: this is Broadcom's proprietary BT firmware. It is handled the
# SAME way as xow_dongle.bin -- maintainer-approved (2026-07-13), redistributed
# for stock parity by a hash-pinned BUILD-TIME fetch, NEVER committed to git
# (G6). See docs/decisions/0003-xone-firmware.md for the full posture; this is
# the same class of decision (vendor firmware, redistributed by fetching from a
# public source rather than vendoring a blob). Upstream here is
# winterheart/broadcom-bt-firmware, the well-known community repo that extracts
# these .hcd blobs from Broadcom's own published Windows drivers -- same
# provenance shape as xow/xone. Its BCM20702A1-0b05-17cb.hcd is byte-size
# identical to stock's (35000 bytes); both the release tarball and the
# extracted .hcd are sha256-pinned (see .hash + the inline check below).
#
# WHY A COMMIT, NOT A TAG (changed 2026-07-19): upstream stopped tagging. The
# newest tag, v12.0.1.1105_p4, is from 2022-10-10, while master is still active
# (three firmware commits on 2026-07-08). Worse, the tag scheme actively
# misleads automation: the "_pN" suffix is a patch level ON TOP of the base
# version, so v12.0.1.1105_p4 is NEWER than v12.0.1.1105 -- but under Renovate's
# `loose` versioning the bare tag sorts higher, and it kept proposing
# v12.0.1.1105 (2020-05-02) as an "upgrade", i.e. a 2.5-year DOWNGRADE.
# Tracking master's HEAD by commit removes the ordering question entirely and
# matches how this repo pins its 9 other untagged upstreams.
#
# The blast radius is deliberately tiny: this package installs exactly ONE file
# and the inline sha256sum below fails the build CLOSED if that file ever
# changes. At the moment of the switch the .hcd was byte-identical at
# v12.0.1.1105_p4 and at master, so the change is a provable no-op for the
# image -- it only unblocks future firmware updates.
BCM20702_FIRMWARE_VERSION = efa06da04e7cd88825121dc6d7b318c805356e0e
BCM20702_FIRMWARE_SITE = $(call github,winterheart,broadcom-bt-firmware,$(BCM20702_FIRMWARE_VERSION))

# Broadcom's proprietary BT firmware, redistributed -- NOT GPL. No LICENSE_FILES:
# the firmware blob carries no license text of its own to point Buildroot's
# legal-info machinery at (same situation as package/xow-firmware).
BCM20702_FIRMWARE_LICENSE = PROPRIETARY (Broadcom BT firmware; redistributed via winterheart/broadcom-bt-firmware)

# The release tarball carries MANY dongles' .hcd files; we install ONLY the one
# stock shipped (0b05:17cb) for strict parity. The extracted blob's sha256 is
# asserted inline right before install -- Buildroot's .hash file verifies only
# the DOWNLOADED tarball, not a file we then derive from it, so this is the
# second, inner hash gate on the firmware itself.
define BCM20702_FIRMWARE_INSTALL_TARGET_CMDS
	@echo "02204ae0958e7af3ffa6193713f5b3847d4ad37b9b9b5064b56cd96f2fdd18d1  $(@D)/brcm/BCM20702A1-0b05-17cb.hcd" | sha256sum -c -
	$(INSTALL) -m 0644 -D $(@D)/brcm/BCM20702A1-0b05-17cb.hcd \
		$(TARGET_DIR)/lib/firmware/brcm/BCM20702A1-0b05-17cb.hcd
endef

$(eval $(generic-package))
