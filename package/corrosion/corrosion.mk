################################################################################
#
# corrosion
#
################################################################################

# Host-only CMake modules for building Rust crates from CMake; slint's C++ API
# needs them and otherwise git-clones them at configure time (docs/slint.md).
CORROSION_VERSION = v0.6.1
CORROSION_SITE = $(call github,corrosion-rs,corrosion,$(CORROSION_VERSION))
CORROSION_LICENSE = MIT
CORROSION_LICENSE_FILES = LICENSE
HOST_CORROSION_CONF_OPTS = -DCORROSION_INSTALL_ONLY=ON

$(eval $(host-cmake-package))
