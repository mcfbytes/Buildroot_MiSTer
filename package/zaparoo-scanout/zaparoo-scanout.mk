################################################################################
#
# zaparoo-scanout
#
################################################################################

# Commit pin on the Zaparoo Menu core fork; the module is one subdirectory of it.
# See docs/zaparoo-scanout.md.
ZAPAROO_SCANOUT_VERSION = a1fdb653c0a5a6b74fadfa552f07d4fc1ed875e4
ZAPAROO_SCANOUT_SITE = $(call github,ZaparooProject,Menu_MiSTer,$(ZAPAROO_SCANOUT_VERSION))
ZAPAROO_SCANOUT_LICENSE = GPL-3.0+
ZAPAROO_SCANOUT_LICENSE_FILES = kernel/scanout-slots/zaparoo_scanout_uapi.h
ZAPAROO_SCANOUT_MODULE_SUBDIRS = kernel/scanout-slots

$(eval $(kernel-module))
$(eval $(generic-package))
