################################################################################
#
# sinden-lightgun
#
################################################################################

# Glue only, no download: Sinden's driver is fetched on the device.
SINDEN_LIGHTGUN_VERSION = 1
SINDEN_LIGHTGUN_SOURCE =
SINDEN_LIGHTGUN_LICENSE = GPL-3.0
SINDEN_LIGHTGUN_DEPENDENCIES = mono sdl sdl_image libjpeg62

define SINDEN_LIGHTGUN_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(SINDEN_LIGHTGUN_PKGDIR)/mister-sinden-lightgun \
		$(TARGET_DIR)/usr/sbin/mister-sinden-lightgun
	$(INSTALL) -D -m 0644 $(SINDEN_LIGHTGUN_PKGDIR)/61-sinden-lightgun.rules \
		$(TARGET_DIR)/etc/udev/rules.d/61-sinden-lightgun.rules
endef

# Mono ships ~200 MB; keep the runtime and LightgunMono.exe's closure, in the GAC
# where mono resolves it. Breaks other mono users, hence the option.
SINDEN_LIGHTGUN_MONO_ASSEMBLIES = mscorlib System System.Core System.Configuration \
	System.Xml System.Security System.Numerics Mono.Security

define SINDEN_LIGHTGUN_TRIM_MONO
	find $(TARGET_DIR)/usr/lib/mono -mindepth 1 -maxdepth 1 ! -name 4.5 ! -name gac -exec rm -rf {} +
	find $(TARGET_DIR)/usr/lib/mono/gac -mindepth 1 -maxdepth 1 \
		$(foreach a,$(SINDEN_LIGHTGUN_MONO_ASSEMBLIES),! -name $(a)) -exec rm -rf {} +
	find $(TARGET_DIR)/usr/lib/mono/4.5 -mindepth 1 \
		$(foreach a,$(SINDEN_LIGHTGUN_MONO_ASSEMBLIES),! -name $(a).dll) -exec rm -rf {} +
	cd $(TARGET_DIR)/usr/bin && rm -f mono-boehm mono-configuration-crypto \
		mono-find-provides mono-find-requires mono-gdb.py mono-heapviz \
		mono-package-runtime mono-service mono-service2 mono-sgen-gdb.py \
		mono-test-install monodis monodocer monodocs2html monodocs2slashdoc monop monop2
	rm -f $(TARGET_DIR)/usr/lib/libmonoboehm-2.0.so* \
		$(TARGET_DIR)/usr/lib/libmonosgen-2.0.so* $(TARGET_DIR)/usr/lib/libmono-2.0.so*
	rm -rf $(TARGET_DIR)/etc/mono/2.0 $(TARGET_DIR)/etc/mono/4.0 \
		$(TARGET_DIR)/etc/mono/browscap.ini $(TARGET_DIR)/etc/mono/mconfig
	find $(TARGET_DIR)/etc/mono/4.5 -mindepth 1 ! -name machine.config -exec rm -rf {} +
endef
ifeq ($(BR2_PACKAGE_SINDEN_LIGHTGUN_TRIM_MONO),y)
SINDEN_LIGHTGUN_TARGET_FINALIZE_HOOKS += SINDEN_LIGHTGUN_TRIM_MONO
endif

$(eval $(generic-package))
