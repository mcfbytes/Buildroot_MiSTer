################################################################################
#
# mister-initramfs
#
################################################################################

# Assembles the stage-1 initramfs cpio (ADR 0002, as amended by ADR 0030)
# from two sibling packages built with the main toolchain -- a static BusyBox
# (mister-initramfs-busybox) and a static fsck.exfat
# (mister-initramfs-exfatprogs) -- plus board/mister/common/initramfs-overlay,
# whose /init is the whole point. The result goes to images/ only; nothing is
# installed into the rootfs. linux/linux-ext-mister-initramfs.mk embeds it.
#
# Root ownership and the /dev/console node need fakeroot, exactly as
# fs/common.mk does for the real rootfs images. With BR2_REPRODUCIBLE the
# mtimes are pinned to SOURCE_DATE_EPOCH and host-cpio's --reproducible is
# used, for the same reason fs/cpio does: the cpio is inside zImage_dtb, so
# a non-reproducible cpio makes the kernel non-reproducible.

MISTER_INITRAMFS_DEPENDENCIES = \
	mister-initramfs-busybox \
	mister-initramfs-exfatprogs \
	host-fakeroot
MISTER_INITRAMFS_INSTALL_TARGET = NO
MISTER_INITRAMFS_INSTALL_IMAGES = YES

ifeq ($(BR2_REPRODUCIBLE),y)
MISTER_INITRAMFS_DEPENDENCIES += host-cpio
MISTER_INITRAMFS_CPIO_OPTS = --reproducible
endif

MISTER_INITRAMFS_OVERLAY = $(BR2_EXTERNAL_MISTER_PATH)/board/mister/common/initramfs-overlay
MISTER_INITRAMFS_ROOT = $(@D)/root
MISTER_INITRAMFS_IMAGE = $(@D)/mister-initramfs.cpio
MISTER_INITRAMFS_QEMU = $(if $(BR2_arm),qemu-arm,$(if $(BR2_aarch64),qemu-aarch64,))

# Optional: the repair's HDMI splash (package/itsalive, built static).
# The frames are rendered from the committed PNGs at build time, as the
# installer's are; /init shows nothing if either half is missing.
ifeq ($(BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE),y)
MISTER_INITRAMFS_DEPENDENCIES += itsalive
MISTER_INITRAMFS_SPLASH_SRC = $(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/fsck-splash
define MISTER_INITRAMFS_INSTALL_ITSALIVE
	$(INSTALL) -m 0755 -D $(ITSALIVE_BIN) \
		$(MISTER_INITRAMFS_ROOT)/usr/bin/itsalive
	$(TARGET_CROSS)strip $(MISTER_INITRAMFS_ROOT)/usr/bin/itsalive
	mkdir -p $(MISTER_INITRAMFS_ROOT)/usr/share/mister-fsck
	for s in 1280x720 640x480; do \
		python3 $(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/installer-splash/png2raw.py \
			$(MISTER_INITRAMFS_SPLASH_SRC)/splash-$$s.png \
			$(MISTER_INITRAMFS_ROOT)/usr/share/mister-fsck/splash-$$s.raw.gz || exit 1; \
	done
endef
endif

# Board layers over the common overlay, in order, as BR2_ROOTFS_OVERLAY is for the rootfs.
# The installer's subtree in them ships only with BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER.
MISTER_INITRAMFS_BOARD_OVERLAYS = $(call qstrip,$(BR2_PACKAGE_MISTER_INITRAMFS_BOARD_OVERLAY))
MISTER_INITRAMFS_BOARD_OVERLAY_EXCLUDES = \
	$(if $(BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER),,--exclude=/usr/libexec/mister-installer/)
define MISTER_INITRAMFS_INSTALL_BOARD_OVERLAYS
	$(foreach d,$(MISTER_INITRAMFS_BOARD_OVERLAYS), \
		test -d $(d) || { echo "mister-initramfs: board overlay $(d) does not exist" >&2; exit 1; }$(sep) \
		rsync -a $(RSYNC_VCS_EXCLUSIONS) $(MISTER_INITRAMFS_BOARD_OVERLAY_EXCLUDES) \
			$(d)/ $(MISTER_INITRAMFS_ROOT)/$(sep))
endef

# Optional: the first-boot installer (ADR 0033). mkfs.exfat lives OFF the PATH, beside
# the only script that may run it; its splash frames come only with itsalive.
ifeq ($(BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER),y)
MISTER_INITRAMFS_INSTALLER_SPLASH = $(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/installer-splash
define MISTER_INITRAMFS_INSTALL_INSTALLER
	$(INSTALL) -m 0755 -D $(MISTER_INITRAMFS_EXFATPROGS_DIR)/mkfs/mkfs.exfat \
		$(MISTER_INITRAMFS_ROOT)/usr/libexec/mister-installer/mkfs.exfat
	$(TARGET_CROSS)strip $(MISTER_INITRAMFS_ROOT)/usr/libexec/mister-installer/mkfs.exfat
	$(if $(BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE),$(MISTER_INITRAMFS_INSTALL_INSTALLER_SPLASH))
endef
define MISTER_INITRAMFS_INSTALL_INSTALLER_SPLASH
	mkdir -p $(MISTER_INITRAMFS_ROOT)/usr/share/mister-installer
	for s in 1280x720 640x480; do \
		python3 $(MISTER_INITRAMFS_INSTALLER_SPLASH)/png2raw.py \
			$(MISTER_INITRAMFS_INSTALLER_SPLASH)/splash-$$s.png \
			$(MISTER_INITRAMFS_ROOT)/usr/share/mister-installer/splash-$$s.raw.gz || exit 1; \
	done
endef
endif

# The installer flag's magic block (docs/installer-init.md#the-flag): every board's /init
# compares LBA 1024 against this, and mk-sdcard.sh writes the same file onto sdcard.img.
MISTER_INITRAMFS_FLAG_MAGIC = MiSTer first-boot installer flag v1 db4ad7b4-a222-4b41-9a8b-17d92131ada0
MISTER_INITRAMFS_FLAG = $(@D)/mister-install-flag.bin

# /init does its own `mkdir -p /proc /sys /dev /mnt/fat /newroot`; the
# directories are created here anyway so the tree is complete without it.
define MISTER_INITRAMFS_BUILD_CMDS
	rm -rf $(MISTER_INITRAMFS_ROOT) $(MISTER_INITRAMFS_IMAGE)
	mkdir -p $(MISTER_INITRAMFS_ROOT)/dev $(MISTER_INITRAMFS_ROOT)/proc \
		$(MISTER_INITRAMFS_ROOT)/sys $(MISTER_INITRAMFS_ROOT)/mnt/fat \
		$(MISTER_INITRAMFS_ROOT)/newroot $(MISTER_INITRAMFS_ROOT)/tmp \
		$(MISTER_INITRAMFS_ROOT)/etc $(MISTER_INITRAMFS_ROOT)/usr/sbin
	cp -a $(MISTER_INITRAMFS_BUSYBOX_DIR)/_install/. $(MISTER_INITRAMFS_ROOT)/
	rm -f $(MISTER_INITRAMFS_ROOT)/linuxrc
	$(INSTALL) -m 0755 $(MISTER_INITRAMFS_EXFATPROGS_DIR)/fsck/fsck.exfat \
		$(MISTER_INITRAMFS_ROOT)/usr/sbin/fsck.exfat
	$(TARGET_CROSS)strip $(MISTER_INITRAMFS_ROOT)/usr/sbin/fsck.exfat
	$(MISTER_INITRAMFS_INSTALL_ITSALIVE)
	cp -a $(MISTER_INITRAMFS_OVERLAY)/. $(MISTER_INITRAMFS_ROOT)/
	$(MISTER_INITRAMFS_INSTALL_BOARD_OVERLAYS)
	printf '%s\n' '$(MISTER_INITRAMFS_FLAG_MAGIC)' > $(MISTER_INITRAMFS_FLAG)
	truncate -s 512 $(MISTER_INITRAMFS_FLAG)
	$(INSTALL) -m 0644 -D $(MISTER_INITRAMFS_FLAG) $(MISTER_INITRAMFS_ROOT)/usr/lib/mister/install-flag.bin
	$(MISTER_INITRAMFS_INSTALL_INSTALLER)
	echo '#!/bin/sh' > $(@D)/fakeroot.sh
	echo 'set -e' >> $(@D)/fakeroot.sh
	echo 'chown -h -R 0:0 $(MISTER_INITRAMFS_ROOT)' >> $(@D)/fakeroot.sh
	echo 'mknod -m 0622 $(MISTER_INITRAMFS_ROOT)/dev/console c 5 1' >> $(@D)/fakeroot.sh
	$(if $(BR2_REPRODUCIBLE),echo 'find $(MISTER_INITRAMFS_ROOT) -print0 | xargs -0 -r touch -hd @$(SOURCE_DATE_EPOCH)' >> $(@D)/fakeroot.sh)
	echo 'cd $(MISTER_INITRAMFS_ROOT) && find . | LC_ALL=C sort | cpio $(MISTER_INITRAMFS_CPIO_OPTS) --quiet -o -H newc > $(MISTER_INITRAMFS_IMAGE)' >> $(@D)/fakeroot.sh
	chmod +x $(@D)/fakeroot.sh
	PATH=$(BR_PATH) FAKEROOTDONTTRYCHOWN=1 $(HOST_DIR)/bin/fakeroot -- $(@D)/fakeroot.sh
	PATH=$(BR_PATH) $(BR2_EXTERNAL_MISTER_PATH)/package/mister-initramfs/verify.sh \
		$(MISTER_INITRAMFS_ROOT) $(MISTER_INITRAMFS_IMAGE) $(MISTER_INITRAMFS_QEMU) \
		$(if $(BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE),itsalive,-) \
		$(if $(BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER),installer)
endef

define MISTER_INITRAMFS_INSTALL_IMAGES_CMDS
	$(INSTALL) -m 0644 -D $(MISTER_INITRAMFS_IMAGE) $(BINARIES_DIR)/mister-initramfs.cpio
	$(INSTALL) -m 0644 -D $(MISTER_INITRAMFS_FLAG) $(BINARIES_DIR)/mister-install-flag.bin
endef

$(eval $(generic-package))
