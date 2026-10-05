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

# Upstream's common.mk hard-codes -Werror after our CFLAGS; a new GCC warning
# must not break the image build.
define MINIJAIL_REMOVE_WERROR
	$(SED) 's/-Werror //' $(@D)/common.mk
endef
MINIJAIL_POST_PATCH_HOOKS += MINIJAIL_REMOVE_WERROR

# Toolchain via the environment: the Makefile appends to CPPFLAGS (PRELOADPATH),
# which a command-line CPPFLAGS= would discard. Build options: docs/minijail.md.
define MINIJAIL_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) -C $(@D) OUT=$(@D)/ LIBDIR=/usr/lib all
endef

# libminijail.so is not installed: minijail0 and the preload library both link
# the core objects statically, so nothing on the image would load it.
define MINIJAIL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/minijail0 $(TARGET_DIR)/usr/bin/minijail0
	$(INSTALL) -D -m 0755 $(@D)/libminijailpreload.so \
		$(TARGET_DIR)/usr/lib/libminijailpreload.so
endef

$(eval $(generic-package))
