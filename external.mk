################################################################################
#
# external.mk for the MISTER BR2_EXTERNAL tree
#
# Pulls in every package .mk under package/*/*.mk. P3.1 added the Realtek
# Wi-Fi kernel-module packages; v9 narrowed the SELECTED set (defconfig) to the
# three 802.11ac chips with no mainline USB driver -- rtl8812au, rtl8814au-morrownr
# and rtl8821au-morrownr -- and moved 8188eu/8188fu/8821cu/8822bu onto in-kernel
# drivers (rtl8xxxu/rtw88; the now-deselected packages stay in the tree as a
# selectable fallback). P3.2 added xone (Xbox One/Series accessory driver) the
# same way (see PLAN.md §6, TASKS.md class D/E). This is the standard Buildroot
# br2-external idiom, so new packages need no change here — just add
# package/<name>/<name>.mk.
#
################################################################################

include $(sort $(wildcard $(BR2_EXTERNAL_MISTER_PATH)/package/*/*.mk))

# The stage-1 initramfs is embedded by linux/linux-ext-mister-initramfs.mk
# (a Buildroot "linux extension", included by linux/linux.mk before the
# kernel package is evaluated -- the only hook early enough to make the
# kernel DEPEND on package/mister-initramfs). It used to live here as a
# LINUX_KCONFIG_FIXUP_CMDS append against a cpio from a second Buildroot
# tree; ADR 0030 moved both the cpio and the fixup into the main build.


################################################################################
#
# dhcpcd: pin the hook set so it cannot depend on the BUILD HOST.
#
# dhcpcd's own ./configure decides which dhcpcd-hooks to install by probing the
# machine it runs on -- `which ntpd`, `which chronyd`,
# /usr/lib/systemd/systemd-timesyncd, `which ypbind` -- unless it is handed the
# list explicitly (configure: `if ! $HOOKSET` around the probes; HOOKSET is
# only set by --with-hooks). Buildroot's package/dhcpcd/dhcpcd.mk passes no
# --with-hooks, so the TARGET image inherited the host's daemons: a GitHub
# runner (ntpd/chronyd on PATH) shipped 50-ntp.conf, a developer box with
# systemd-timesyncd and no ntpd shipped 50-timesyncd.conf instead -- and the
# build was green either way. Found 2026-09-02 by diffing a CI image against a
# local one (docs/init-parity.md, dhcpcd row).
#
# This appends to the package's own CONFIG_OPTS -- legal because Buildroot
# includes BR2_EXTERNAL .mk files after package/*/*.mk (work/buildroot/
# Makefile: package includes first, then $(BR2_EXTERNAL_MKS)) and the
# DHCPCD_CONFIGURE_CMDS `define` expands $(DHCPCD_CONFIG_OPTS) when the recipe
# RUNS, not when the .mk is parsed. No Buildroot patch, no dhcpcd patch.
#
# The values reproduce the canonical (CI-built) image exactly: the base hooks
# 01-test/20-resolv.conf/30-hostname are unconditional in hooks/Makefile;
# `ntp.conf` selects 50-ntp.conf (we ship classic ntpd, BR2_PACKAGE_NTP, so
# DHCP-offered NTP servers land in /etc/ntp.conf as on stock); `yp.conf` keeps
# the 50-yp.conf EXAMPLE hook under /usr/share/dhcpcd/hooks, which CI also
# shipped. Names are hook stems: configure's find_hook() matches
# [0-9][0-9]-<stem>[.conf], so "ntp.conf" is right and "50-ntp.conf" silently
# matches nothing (verified against dhcpcd 10.2.4's configure).
# scripts/check-linux-img.sh asserts the resulting hook set, fail-closed.
#
################################################################################
ifeq ($(BR2_PACKAGE_DHCPCD),y)
DHCPCD_CONFIG_OPTS += --with-hooks=ntp.conf --with-eghooks=yp.conf
endif
