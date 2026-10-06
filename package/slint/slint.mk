################################################################################
#
# slint
#
################################################################################

# The C++ API (libslint_cpp.so + CMake package), software renderer only, plus the
# carried 0001-0003 (fontconfig dlopen, ARGB8888 target, scene clock). docs/slint.md.
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
SLINT_DEPENDENCIES = host-rustc host-corrosion host-slint

# PKG_CARGO_ENV's own ARM rustflag, plus the board's CPU so rustc tunes like GCC does.
SLINT_RUSTFLAGS = \
	$(if $(filter arm,$(NORMALIZED_ARCH)),-Clink-arg=-Wl$(comma)--allow-multiple-definition) \
	$(if $(BR2_GCC_TARGET_CPU),-Ctarget-cpu=$(call qstrip,$(BR2_GCC_TARGET_CPU))) \
	$(if $(BR2_ARM_CPU_HAS_NEON),-Ctarget-feature=+neon)

# Corrosion runs cargo at configure (metadata) and build time, so both get the env.
SLINT_CARGO_ENV = \
	$(PKG_CARGO_ENV) \
	CARGO_NET_OFFLINE=true \
	PKG_CONFIG_ALLOW_CROSS=1 \
	CARGO_TARGET_$(call UPPERCASE,$(RUSTC_TARGET_NAME))_RUSTFLAGS="$(strip $(SLINT_RUSTFLAGS))"
SLINT_CONF_ENV = $(SLINT_CARGO_ENV)
SLINT_MAKE_ENV = $(SLINT_CARGO_ENV)

# FETCHCONTENT_FULLY_DISCONNECTED: never let CMake fetch Corrosion off the network.
SLINT_CONF_OPTS = \
	-DCorrosion_DIR=$(HOST_DIR)/lib/cmake/Corrosion \
	-DFETCHCONTENT_FULLY_DISCONNECTED=ON \
	-DRust_COMPILER=$(HOST_DIR)/bin/rustc \
	-DRust_CARGO=$(HOST_DIR)/bin/cargo \
	-DRust_CARGO_TARGET=$(RUSTC_TARGET_NAME) \
	-DSLINT_COMPILER=$(HOST_DIR)/bin/slint-compiler \
	-DSLINT_LIBRARY_CARGO_FLAGS=--locked \
	-DSLINT_BUILD_TESTING=OFF \
	-DSLINT_BUILD_EXAMPLES=OFF \
	-DSLINT_FEATURE_BACKEND_WINIT=OFF \
	-DSLINT_FEATURE_RENDERER_FEMTOVG=OFF \
	-DSLINT_FEATURE_RENDERER_SKIA=OFF \
	-DSLINT_FEATURE_RENDERER_SOFTWARE=ON \
	-DSLINT_FEATURE_EXPERIMENTAL=OFF \
	-DSLINT_FEATURE_BACKEND_QT=OFF \
	-DSLINT_FEATURE_BACKEND_LINUXKMS_LIBSEAT=OFF \
	-DSLINT_FEATURE_LIVE_PREVIEW=OFF \
	-DSLINT_FEATURE_ACCESSIBILITY=OFF \
	-DSLINT_FEATURE_SYSTEM_TRAY=OFF \
	-DSLINT_FEATURE_GETTEXT=OFF \
	-DSLINT_FEATURE_TESTING=OFF

# Off by default: the intended caller is its own Platform rendering into its own buffer.
ifeq ($(BR2_PACKAGE_SLINT_LINUXKMS),y)
SLINT_CONF_OPTS += -DSLINT_FEATURE_BACKEND_LINUXKMS=ON
else
SLINT_CONF_OPTS += -DSLINT_FEATURE_BACKEND_LINUXKMS=OFF
endif

ifeq ($(BR2_PACKAGE_SLINT_LINUXKMS_LIBINPUT),y)
SLINT_DEPENDENCIES += libinput libxkbcommon libudev
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
