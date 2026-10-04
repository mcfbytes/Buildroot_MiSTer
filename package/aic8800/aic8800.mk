################################################################################
#
# aic8800
#
################################################################################

# AICSemi AIC8800 Wi-Fi 6 + BT USB driver and firmware, from the tree stock
# vendored (MiSTer-v6.18 c129b0fac3). Provenance + licence: docs/wifi-parity.md §10.1.
AIC8800_VERSION = b72eea956451d6a351292cd6cd46b44b48e65b8d
AIC8800_SITE = $(call github,shenmintao,aic8800d80,$(AIC8800_VERSION))
# Upstream publishes no licence file; the only grant is MODULE_LICENSE("GPL").
AIC8800_LICENSE = GPL-2.0 (driver, per MODULE_LICENSE; no licence file published), PROPRIETARY (AICSemi firmware blobs, redistributed)

# One kbuild pass over the parent dir, so modpost resolves aic_load_fw's exports
# for aic8800_fdrv. aic_zlp_quirk needs CONFIG_KPROBES (off here and in stock).
AIC8800_MODULE_SUBDIRS = drivers/aic8800
AIC8800_MODULE_MAKE_OPTS = \
	CONFIG_AIC_LOADFW_SUPPORT=m \
	CONFIG_AIC8800_WLAN_SUPPORT=m \
	CONFIG_AIC_ZLP_QUIRK=n

# The driver filp_open()s /lib/firmware/<variant>/ itself (no request_firmware()),
# so a moved base path would leave every installed blob unreachable.
define AIC8800_CHECK_FW_PATH
	grep -Fq 'aic_default_fw_path = "/lib/firmware";' \
		$(@D)/drivers/aic8800/aic_load_fw/aicbluetooth.c || \
		{ echo "aic8800: FATAL: default firmware path is no longer /lib/firmware" >&2; exit 1; }
endef
AIC8800_POST_PATCH_HOOKS += AIC8800_CHECK_FW_PATH

# Per-chip subdirectories, never flat: the chip is picked at runtime from the USB ID.
AIC8800_FW_VARIANTS = \
	aic8800 \
	aic8800D80 \
	aic8800D80N \
	aic8800D80X2 \
	aic8800DC \
	aic8800DLN

define AIC8800_INSTALL_TARGET_CMDS
	for v in $(AIC8800_FW_VARIANTS); do \
		$(INSTALL) -d $(TARGET_DIR)/lib/firmware/$$v ; \
		$(INSTALL) -m 0644 $(@D)/fw/$$v/* \
			$(TARGET_DIR)/lib/firmware/$$v/ || exit 1 ; \
	done
endef

$(eval $(kernel-module))
$(eval $(generic-package))
