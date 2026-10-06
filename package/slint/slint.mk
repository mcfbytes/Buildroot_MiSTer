################################################################################
#
# slint
#
################################################################################

# The C++ API (libslint_cpp.so + CMake package) for the software renderer on the
# LinuxKMS backend, which falls back to /dev/fb0 without DRM. See docs/slint.md.
SLINT_VERSION = 1.18.1
SLINT_SITE = $(call github,slint-ui,slint,v$(SLINT_VERSION))
SLINT_LICENSE = GPL-3.0 or LicenseRef-Slint-Royalty-free-2.0 or LicenseRef-Slint-Software-3.0
SLINT_LICENSE_FILES = \
	LICENSE.md \
	LICENSES/GPL-3.0-only.txt \
	LICENSES/LicenseRef-Slint-Royalty-free-2.0.md \
	LICENSES/LicenseRef-Slint-Software-3.0.md
SLINT_INSTALL_STAGING = YES

# cmake-package, but vendored like a cargo-package (the .hash names -cargo6).
SLINT_DOWNLOAD_POST_PROCESS = cargo
SLINT_DOWNLOAD_DEPENDENCIES = host-rustc
SLINT_DL_ENV = CARGO_HOME=$(BR_CARGO_HOME)
SLINT_DEPENDENCIES = host-rustc host-corrosion host-slint fontconfig

# Corrosion runs cargo at build time, so the cargo environment goes on MAKE_ENV.
SLINT_MAKE_ENV = \
	$(PKG_CARGO_ENV) \
	CARGO_NET_OFFLINE=true \
	PKG_CONFIG_ALLOW_CROSS=1

SLINT_CONF_OPTS = \
	-DCorrosion_DIR=$(HOST_DIR)/lib/cmake/Corrosion \
	-DRust_COMPILER=$(HOST_DIR)/bin/rustc \
	-DRust_CARGO=$(HOST_DIR)/bin/cargo \
	-DRust_CARGO_TARGET=$(RUSTC_TARGET_NAME) \
	-DSLINT_COMPILER=$(HOST_DIR)/bin/slint-compiler \
	-DSLINT_BUILD_TESTING=OFF \
	-DSLINT_BUILD_EXAMPLES=OFF \
	-DSLINT_FEATURE_BACKEND_WINIT=OFF \
	-DSLINT_FEATURE_RENDERER_FEMTOVG=OFF \
	-DSLINT_FEATURE_RENDERER_SKIA=OFF \
	-DSLINT_FEATURE_RENDERER_SOFTWARE=ON \
	-DSLINT_FEATURE_BACKEND_LINUXKMS=ON \
	-DSLINT_FEATURE_BACKEND_LINUXKMS_LIBSEAT=OFF \
	-DSLINT_FEATURE_ACCESSIBILITY=OFF \
	-DSLINT_FEATURE_SYSTEM_TRAY=OFF \
	-DSLINT_FEATURE_TESTING=OFF

ifeq ($(BR2_PACKAGE_SLINT_LIBINPUT),y)
SLINT_DEPENDENCIES += libinput libxkbcommon udev
SLINT_CONF_OPTS += -DSLINT_FEATURE_BACKEND_LINUXKMS_LIBINPUT=ON
else
SLINT_CONF_OPTS += -DSLINT_FEATURE_BACKEND_LINUXKMS_LIBINPUT=OFF
endif

ifeq ($(BR2_PACKAGE_SLINT_INTERPRETER),y)
SLINT_CONF_OPTS += -DSLINT_FEATURE_INTERPRETER=ON
else
SLINT_CONF_OPTS += -DSLINT_FEATURE_INTERPRETER=OFF
endif

# host-slint is slint-compiler only: .slint -> C++ for packages that link Slint.
HOST_SLINT_COMPILER_FEATURES = \
	cpp renderer-software image-default-formats bundle-translations fontconfig-dlopen

define HOST_SLINT_BUILD_CMDS
	cd $(@D) && \
	$(HOST_MAKE_ENV) $(HOST_CONFIGURE_OPTS) $(HOST_PKG_CARGO_ENV) \
		cargo build --offline --release --locked -p slint-compiler \
			--no-default-features --features "$(HOST_SLINT_COMPILER_FEATURES)"
endef

define HOST_SLINT_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/target/release/slint-compiler \
		$(HOST_DIR)/bin/slint-compiler
endef

$(eval $(cmake-package))
$(eval $(host-cargo-package))
