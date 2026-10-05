################################################################################
#
# minijail
#
################################################################################

MINIJAIL_VERSION = linux-v2026.05.18
MINIJAIL_SITE = $(call github,google,minijail,$(MINIJAIL_VERSION))
MINIJAIL_LICENSE = BSD-3-Clause
MINIJAIL_LICENSE_FILES = LICENSE
MINIJAIL_DEPENDENCIES = libcap
MINIJAIL_INSTALL_STAGING = YES

# Toolchain via the environment: the Makefile appends to CPPFLAGS (PRELOADPATH),
# which a command-line CPPFLAGS= would discard. Build options: docs/minijail.md.
define MINIJAIL_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(TARGET_CONFIGURE_OPTS) $(MAKE) -C $(@D) \
		OUT=$(@D)/ LIBDIR=/usr/lib all
endef

define MINIJAIL_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libminijail.h $(STAGING_DIR)/usr/include/libminijail.h
	$(INSTALL) -D -m 0755 $(@D)/libminijail.so $(STAGING_DIR)/usr/lib/libminijail.so
endef

define MINIJAIL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/minijail0 $(TARGET_DIR)/usr/bin/minijail0
	$(INSTALL) -D -m 0755 $(@D)/libminijail.so $(TARGET_DIR)/usr/lib/libminijail.so
	$(INSTALL) -D -m 0755 $(@D)/libminijailpreload.so \
		$(TARGET_DIR)/usr/lib/libminijailpreload.so
endef

$(eval $(generic-package))
