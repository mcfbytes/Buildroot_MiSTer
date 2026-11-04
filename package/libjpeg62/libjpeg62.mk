################################################################################
#
# libjpeg62
#
################################################################################

# Same tarball as Buildroot's jpeg-turbo, so it moves with every Buildroot bump.
LIBJPEG62_VERSION = $(JPEG_TURBO_VERSION)
LIBJPEG62_SOURCE = $(JPEG_TURBO_SOURCE)
LIBJPEG62_SITE = $(JPEG_TURBO_SITE)
LIBJPEG62_DL_SUBDIR = jpeg-turbo
LIBJPEG62_LICENSE = $(JPEG_TURBO_LICENSE)
LIBJPEG62_LICENSE_FILES = $(JPEG_TURBO_LICENSE_FILES)
LIBJPEG62_DEPENDENCIES = host-pkgconf

LIBJPEG62_CONF_OPTS = \
	-DWITH_JPEG8=OFF \
	-DWITH_TURBOJPEG=OFF \
	-DWITH_TOOLS=OFF \
	-DWITH_TESTS=OFF \
	-DENABLE_STATIC=OFF \
	-DENABLE_SHARED=ON \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DWITH_SIMD=$(if $(BR2_PACKAGE_JPEG_SIMD_SUPPORT),ON,OFF)

# Only the runtime library: headers and pkg-config would shadow libjpeg.so.8.
define LIBJPEG62_INSTALL_TARGET_CMDS
	cp -a $(LIBJPEG62_BUILDDIR)/libjpeg.so.62* $(TARGET_DIR)/usr/lib/
endef

$(eval $(cmake-package))

# Verify against Buildroot's own jpeg-turbo.hash: no copy here to go stale.
LIBJPEG62_HASH_FILES = $(JPEG_TURBO_HASH_FILES)
