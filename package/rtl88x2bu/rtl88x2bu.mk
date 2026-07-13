################################################################################
#
# rtl88x2bu
#
################################################################################

# P3.1 (PLAN.md §4.1 class E) — out-of-tree Realtek RTL8812BU/RTL8822BU USB
# WiFi driver.
#
# Sourced from morrownr's actively-maintained fork, NOT the ~2021 vendor tree
# MiSTer's stock kernel carries.
#
# Commit-pinned, not branch-pinned. The pin below is main HEAD as of this
# writing:
#
#   git log --oneline -1 <=> fecac34 Merge pull request #264 from
#                                    Summer0Glow/fix-kernel-6.18-compatibility
#
# i.e. upstream's own history documents this commit as the Linux 6.18
# compatibility fix merge — a direct, named assertion of compatibility with
# our exact kernel line.
#
# CONFIG_WIRELESS_EXT — NOT required. This repo shares the same core/os_dep
# driver code as package/rtl8812au, package/rtl8821au and package/rtl8821cu
# (all morrownr forks of the same Realtek "rtw" vendor base) and was
# verified the same way: `#ifdef CONFIG_WIRELESS_EXT` gates only the legacy
# Wireless-Extensions ioctl table (dev->wireless_handlers) and iwconfig
# signal-quality stats in os_dep/linux/{os_intfs,ioctl_linux}.c — never the
# cfg80211/nl80211 path (os_dep/linux/ioctl_cfg80211.c's rtw_cfg80211_ops /
# wiphy_register(), both unconditional). `wpa_supplicant -D nl80211` (what
# MiSTer's wifi.sh uses) only touches the latter. Our kernel does not define
# CONFIG_WIRELESS_EXT (P1.3 hazard — non-prompt, select-only symbol in
# 6.18), so the wext-only code simply compiles out; no wrapper or kernel
# `select` hack is needed.
RTL88X2BU_VERSION = fecac340fb117eb979f4bb6d28e29730384c382b
RTL88X2BU_SITE = $(call github,morrownr,88x2bu-20210702,$(RTL88X2BU_VERSION))
RTL88X2BU_LICENSE = GPL-2.0
RTL88X2BU_LICENSE_FILES = LICENSE

# Buildroot's kernel-module infra bypasses this driver's own `modules:`
# convenience target (the one that exports the chip CONFIG_ variable before
# re-invoking kbuild) and calls kbuild directly, so
# `obj-$(CONFIG_RTL8822BU) := $(MODULE_NAME).o` sees an empty
# CONFIG_RTL8822BU and silently builds nothing (MODPOST runs on zero
# objects, no .ko is produced). Reproduce the default explicitly. (Yes,
# RTL8822BU, not RTL88X2BU -- that is the Makefile's own internal variable
# name for this chip pair, unrelated to the package/repo name.)
RTL88X2BU_MODULE_MAKE_OPTS = CONFIG_RTL8822BU=m

$(eval $(kernel-module))
$(eval $(generic-package))
