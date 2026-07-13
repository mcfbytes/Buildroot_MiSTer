################################################################################
#
# rtl8821cu-morrownr
#
################################################################################

# P3.1 (PLAN.md §4.1 class E) — out-of-tree Realtek RTL8811CU/RTL8821CU
# (and RTL8821CUH/RTL8731AU) USB WiFi driver.
#
# NAMED "-morrownr", NOT plain "rtl8821cu": Buildroot 2026.02.3 upstream
# already ships its OWN package/rtl8821cu — which, notably, is ALSO sourced
# from morrownr/8821cu-20210916, and (as of this writing) at the exact same
# commit this package independently pinned (7f63a9d), which is a useful
# independent confirmation that this is the right pin. It differs from ours
# in build-flag details (CONFIG_PLATFORM_AUTODETECT=n, explicit
# USER_EXTRA_CFLAGS, a modprobe.d install hook) and — critically — its
# version is Buildroot-release-cadence-pinned, not controlled by this
# project, so relying on it would mean losing our own pin control across a
# future `BUILDROOT_VERSION` bump (this project's whole reproducibility
# posture, A9, depends on OUR pins, not on whatever Buildroot's next release
# happens to carry). Kept as our own package, renamed to avoid the Kconfig
# symbol (BR2_PACKAGE_RTL8821CU) and Make-namespace collision, following the
# exact disambiguation convention Buildroot's own upstream already uses one
# row over (package/rtl8812au-aircrack-ng vs. a plain rtl8812au namespace).
#
# Commit-pinned, not branch-pinned. The pin below is main HEAD as of this
# writing:
#
#   git log --oneline -1 <=> 7f63a9d Merge pull request #195 from
#                                    Benetti-Engineering/fix/linux-6.18
#
# i.e. upstream's own history documents this commit as the Linux 6.18 build
# fix merge — a direct, named assertion of compatibility with our exact
# kernel line.
#
# CONFIG_WIRELESS_EXT — NOT required. This repo shares the same core/os_dep
# driver code as package/rtl8812au and package/rtl8821au-morrownr (all three
# are morrownr forks of the same Realtek "rtw" vendor base) and was
# verified the same way: `#ifdef CONFIG_WIRELESS_EXT` gates only the legacy
# Wireless-Extensions ioctl table (dev->wireless_handlers) and iwconfig
# signal-quality stats in os_dep/linux/{os_intfs,ioctl_linux}.c — never the
# cfg80211/nl80211 path (os_dep/linux/ioctl_cfg80211.c's rtw_cfg80211_ops /
# wiphy_register(), both unconditional). `wpa_supplicant -D nl80211` (what
# MiSTer's wifi.sh uses) only touches the latter. Our kernel does not define
# CONFIG_WIRELESS_EXT (P1.3 hazard — non-prompt, select-only symbol in
# 6.18), so the wext-only code simply compiles out; no wrapper or kernel
# `select` hack is needed.
RTL8821CU_MORROWNR_VERSION = 7f63a9da2e8ed83403f6f920e9b1628a37b38ef4
RTL8821CU_MORROWNR_SITE = $(call github,morrownr,8821cu-20210916,$(RTL8821CU_MORROWNR_VERSION))
RTL8821CU_MORROWNR_LICENSE = GPL-2.0
RTL8821CU_MORROWNR_LICENSE_FILES = LICENSE

# Unlike the other five packages in this family, this driver's Makefile
# defaults to building as a module with no extra flags needed: its gating
# is `ifeq ($(CONFIG_RTL8821CU),y) / obj-y := ... / else / obj-m := ...`,
# i.e. obj-m is the fallback taken when CONFIG_RTL8821CU is unset (which it
# is, under Buildroot's kernel-module infra -- see the sibling packages'
# comments for why that variable is normally unset here). Verified by an
# actual build (P3.1 build report). CONFIG_RTL8821CU=m is set explicitly
# below anyway, purely for self-documentation/robustness against upstream
# changing the default -- it is a no-op today, matching what mainline
# Buildroot's own package/rtl8821cu.mk does for the identical source.
RTL8821CU_MORROWNR_MODULE_MAKE_OPTS = CONFIG_RTL8821CU=m

$(eval $(kernel-module))
$(eval $(generic-package))
