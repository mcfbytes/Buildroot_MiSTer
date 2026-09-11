################################################################################
#
# mister-initramfs-busybox
#
################################################################################

# The stage-1 initramfs's BusyBox: a SECOND BusyBox in this build, configured
# from board/mister/common/initramfs-busybox.config (a deliberately tiny
# applet set -- exactly what /init calls), linked -static against the main
# toolchain's glibc, and installed into its own build directory only
# (_install/). Nothing here reaches the rootfs; package/mister-initramfs turns
# the result into the cpio the kernel embeds. ADR 0002 as amended by ADR 0030:
# stage 1 used to be a separate musl Buildroot configuration because
# BR2_STATIC_LIBS is not offered with glibc -- a limit of a Buildroot
# *configuration*, not of a package that passes -static itself. Measured
# cost: 942,660 B static-glibc vs 263,308 B static-musl, against a 16 MiB
# zImage_dtb budget with ~7 MB of headroom (docs/boot-chain.md §7.3).
#
# Same tarball as Buildroot's own busybox package; _DL_SUBDIR makes the
# download land in dl/busybox/ so it is fetched once. Upstream's patch set for
# busybox is applied too (POST_PATCH hook), so this BusyBox carries the same
# fixes and CVE backports as the rootfs one.
#
# It is a kconfig-package, so `make mister-initramfs-busybox-menuconfig` edits
# the stage-1 BusyBox config and `make mister-initramfs-busybox-update-config`
# saves it back to board/mister/common/initramfs-busybox.config.

MISTER_INITRAMFS_BUSYBOX_VERSION = 1.38.0
MISTER_INITRAMFS_BUSYBOX_SOURCE = busybox-$(MISTER_INITRAMFS_BUSYBOX_VERSION).tar.bz2
MISTER_INITRAMFS_BUSYBOX_SITE = https://www.busybox.net/downloads
MISTER_INITRAMFS_BUSYBOX_DL_SUBDIR = busybox
MISTER_INITRAMFS_BUSYBOX_LICENSE = GPL-2.0, bzip2-1.0.6
MISTER_INITRAMFS_BUSYBOX_LICENSE_FILES = LICENSE archival/libarchive/bz/LICENSE
MISTER_INITRAMFS_BUSYBOX_CPE_ID_VENDOR = busybox
MISTER_INITRAMFS_BUSYBOX_INSTALL_TARGET = NO
MISTER_INITRAMFS_BUSYBOX_INSTALL_STAGING = NO

MISTER_INITRAMFS_BUSYBOX_KCONFIG_FILE = $(BR2_EXTERNAL_MISTER_PATH)/board/mister/common/initramfs-busybox.config
MISTER_INITRAMFS_BUSYBOX_KCONFIG_EDITORS = menuconfig
MISTER_INITRAMFS_BUSYBOX_KCONFIG_OPTS = $(MISTER_INITRAMFS_BUSYBOX_MAKE_OPTS)

MISTER_INITRAMFS_BUSYBOX_MAKE_ENV = \
	$(TARGET_MAKE_ENV) \
	CFLAGS="$(TARGET_CFLAGS)"
ifeq ($(BR2_REPRODUCIBLE),y)
MISTER_INITRAMFS_BUSYBOX_MAKE_ENV += KCONFIG_NOTIMESTAMP=1
endif

# CONFIG_PREFIX on the command line overrides the .config's "./_install";
# BusyBox strips the final binary itself (no SKIP_STRIP: this binary never
# passes through Buildroot's target-finalize strip).
MISTER_INITRAMFS_BUSYBOX_MAKE_OPTS = \
	AR="$(TARGET_AR)" \
	NM="$(TARGET_NM)" \
	RANLIB="$(TARGET_RANLIB)" \
	CC="$(TARGET_CC)" \
	ARCH=$(NORMALIZED_ARCH) \
	EXTRA_LDFLAGS="$(TARGET_LDFLAGS)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	CONFIG_PREFIX="$(@D)/_install"

# Static is the point; pin it whatever the committed config says.
define MISTER_INITRAMFS_BUSYBOX_KCONFIG_FIXUP_CMDS
	$(call KCONFIG_ENABLE_OPT,CONFIG_STATIC)
endef

define MISTER_INITRAMFS_BUSYBOX_APPLY_UPSTREAM_PATCHES
	$(APPLY_PATCHES) $(@D) $(TOPDIR)/package/busybox \*.patch
endef
MISTER_INITRAMFS_BUSYBOX_POST_PATCH_HOOKS += MISTER_INITRAMFS_BUSYBOX_APPLY_UPSTREAM_PATCHES

define MISTER_INITRAMFS_BUSYBOX_BUILD_CMDS
	$(MISTER_INITRAMFS_BUSYBOX_MAKE_ENV) $(MAKE) $(MISTER_INITRAMFS_BUSYBOX_MAKE_OPTS) -C $(@D)
	rm -rf $(@D)/_install
	$(MISTER_INITRAMFS_BUSYBOX_MAKE_ENV) $(MAKE) $(MISTER_INITRAMFS_BUSYBOX_MAKE_OPTS) -C $(@D) install
endef

$(eval $(kconfig-package))
