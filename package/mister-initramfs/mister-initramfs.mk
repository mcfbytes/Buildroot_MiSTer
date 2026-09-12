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
	cp -a $(MISTER_INITRAMFS_OVERLAY)/. $(MISTER_INITRAMFS_ROOT)/
	echo '#!/bin/sh' > $(@D)/fakeroot.sh
	echo 'set -e' >> $(@D)/fakeroot.sh
	echo 'chown -h -R 0:0 $(MISTER_INITRAMFS_ROOT)' >> $(@D)/fakeroot.sh
	echo 'mknod -m 0622 $(MISTER_INITRAMFS_ROOT)/dev/console c 5 1' >> $(@D)/fakeroot.sh
	$(if $(BR2_REPRODUCIBLE),echo 'find $(MISTER_INITRAMFS_ROOT) -print0 | xargs -0 -r touch -hd @$(SOURCE_DATE_EPOCH)' >> $(@D)/fakeroot.sh)
	echo 'cd $(MISTER_INITRAMFS_ROOT) && find . | LC_ALL=C sort | cpio $(MISTER_INITRAMFS_CPIO_OPTS) --quiet -o -H newc > $(MISTER_INITRAMFS_IMAGE)' >> $(@D)/fakeroot.sh
	chmod +x $(@D)/fakeroot.sh
	PATH=$(BR_PATH) FAKEROOTDONTTRYCHOWN=1 $(HOST_DIR)/bin/fakeroot -- $(@D)/fakeroot.sh
	PATH=$(BR_PATH) $(BR2_EXTERNAL_MISTER_PATH)/package/mister-initramfs/verify.sh \
		$(MISTER_INITRAMFS_ROOT) $(MISTER_INITRAMFS_IMAGE) $(MISTER_INITRAMFS_QEMU)
endef

define MISTER_INITRAMFS_INSTALL_IMAGES_CMDS
	$(INSTALL) -m 0644 -D $(MISTER_INITRAMFS_IMAGE) $(BINARIES_DIR)/mister-initramfs.cpio
endef

$(eval $(generic-package))
