################################################################################
#
# mister-initramfs-exfatprogs
#
################################################################################

# A SECOND exfatprogs in this build: the same tarball Buildroot's own
# exfatprogs package builds (shared through _DL_SUBDIR, so it is downloaded
# once), linked -static against the main toolchain's glibc so that ONE binary,
# fsck.exfat, can live inside the stage-1 initramfs with no shared libc next
# to it. Nothing is installed to the rootfs; package/mister-initramfs copies
# fsck.exfat out of this package's build directory. ADR 0026 is the reason
# fsck.exfat is in stage 1 at all, and the reason mkfs/tune/label/dump are
# deliberately NOT copied: a card reformatter must never sit one typo away
# from the boot path.

MISTER_INITRAMFS_EXFATPROGS_VERSION = 1.2.9
MISTER_INITRAMFS_EXFATPROGS_SOURCE = exfatprogs-$(MISTER_INITRAMFS_EXFATPROGS_VERSION).tar.xz
MISTER_INITRAMFS_EXFATPROGS_SITE = https://github.com/exfatprogs/exfatprogs/releases/download/$(MISTER_INITRAMFS_EXFATPROGS_VERSION)
MISTER_INITRAMFS_EXFATPROGS_DL_SUBDIR = exfatprogs
MISTER_INITRAMFS_EXFATPROGS_LICENSE = GPL-2.0+
MISTER_INITRAMFS_EXFATPROGS_LICENSE_FILES = COPYING
MISTER_INITRAMFS_EXFATPROGS_CPE_ID_VENDOR = namjaejeon
MISTER_INITRAMFS_EXFATPROGS_INSTALL_TARGET = NO
MISTER_INITRAMFS_EXFATPROGS_INSTALL_STAGING = NO

MISTER_INITRAMFS_EXFATPROGS_CONF_ENV = LDFLAGS="$(TARGET_LDFLAGS) -static"

$(eval $(autotools-package))
