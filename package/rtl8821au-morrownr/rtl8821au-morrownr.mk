################################################################################
#
# rtl8821au-morrownr
#
################################################################################

# P3.1 (PLAN.md §4.1 class E) — out-of-tree Realtek RTL8811AU/RTL8821AU USB
# WiFi driver.
#
# NAMED "-morrownr", NOT plain "rtl8821au": Buildroot 2026.05.1 upstream
# already ships its OWN package/rtl8821au (sourced from
# benetti-engineering/rtl8821au, a different fork, built via that fork's own
# in-kernel-Kconfig-style CONFIG_RTL8812AU_8821AU=m integration). A
# same-named package here would collide on both the Kconfig symbol
# (BR2_PACKAGE_RTL8821AU) and the Make variable/target namespace — whichever
# rtl8821au.mk got `include`d last would silently win. Renamed to avoid it,
# following the exact disambiguation convention Buildroot's own upstream
# already uses one row over (package/rtl8812au-aircrack-ng vs. a plain
# rtl8812au namespace) — see PLAN.md/TASKS.md's P3.1 report for the
# collision detail.
#
# Sourced from morrownr's actively-maintained fork, NOT the ~2021 vendor tree
# MiSTer's stock kernel carries. morrownr/8821au-20210708 covers the
# RTL8811AU and RTL8821AU chips specifically (see package/rtl8812au for the
# sibling RTL8812AU repo, and package/rtl8821cu-morrownr for the unrelated
# RTL8821CU).
#
# Commit-pinned, not branch-pinned. The pin below is main HEAD as of this
# writing:
#
#   git log --oneline -1 <=> 3a7cdb5 Merge pull request #206 from
#                                    palyaros02/kernel-7.0-build-fixes
#
# i.e. upstream's own history documents this commit as the kernel-7.0
# build-fix merge, which by construction covers our 6.18.y line.
#
# CONFIG_WIRELESS_EXT — NOT required. This repo shares the same core/os_dep
# driver code as package/rtl8812au (both are morrownr forks of the same
# Realtek "rtw" vendor base) and was verified the same way: reading the
# source shows `#ifdef CONFIG_WIRELESS_EXT` gates only the legacy
# Wireless-Extensions ioctl table (dev->wireless_handlers) and iwconfig
# signal-quality stats in os_dep/linux/{os_intfs,ioctl_linux}.c — never the
# cfg80211/nl80211 path (os_dep/linux/ioctl_cfg80211.c's rtw_cfg80211_ops /
# wiphy_register(), both unconditional). `wpa_supplicant -D nl80211` (what
# MiSTer's wifi.sh uses) only touches the latter. Our kernel does not define
# CONFIG_WIRELESS_EXT (P1.3 hazard — non-prompt, select-only symbol in
# 6.18), so the wext-only code simply compiles out; no wrapper or kernel
# `select` hack is needed.
RTL8821AU_MORROWNR_VERSION = 3a7cdb591b64d99d2670e455bde67c8ab338525b
RTL8821AU_MORROWNR_SITE = $(call github,morrownr,8821au-20210708,$(RTL8821AU_MORROWNR_VERSION))
RTL8821AU_MORROWNR_LICENSE = GPL-2.0
RTL8821AU_MORROWNR_LICENSE_FILES = LICENSE

# Buildroot's kernel-module infra bypasses this driver's own `modules:`
# convenience target (the one that `export CONFIG_RTL8821AU = m` before
# re-invoking kbuild) and calls kbuild directly, so
# `obj-$(CONFIG_RTL8821AU) := $(MODULE_NAME).o` sees an empty
# CONFIG_RTL8821AU and silently builds nothing (MODPOST runs on zero
# objects, no .ko is produced). Reproduce the default explicitly.
RTL8821AU_MORROWNR_MODULE_MAKE_OPTS = CONFIG_RTL8821AU=m

$(eval $(kernel-module))
$(eval $(generic-package))
