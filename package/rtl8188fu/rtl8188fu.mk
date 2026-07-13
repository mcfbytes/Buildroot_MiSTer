################################################################################
#
# rtl8188fu
#
################################################################################

# P3.1 (PLAN.md §4.1 class E) — out-of-tree Realtek RTL8188FU USB WiFi
# driver.
#
# DEVIATION FROM morrownr, DOCUMENTED PER THE TASK'S OWN ALLOWANCE: morrownr
# does not carry an RTL8188FU repo (checked morrownr's full repository list
# on GitHub — see package/rtl8188eu/rtl8188eu.mk for the list; no 8188F of
# any kind). Sourced instead from kelebek333/rtl8188fu, described upstream
# as "RTL8188FU driver for Linux 4.15.x ~ 7.0.x" and, at pin time, the most
# recently and actively maintained RTL8188FU fork on GitHub (pushed within
# the last two months, versus multi-year-stale alternatives such as
# libc0607/rtl8188fu-20230217 and i2som/RTL8188FU).
#
# Commit-pinned, not branch-pinned. The pin below is master HEAD as of this
# writing:
#
#   git log --oneline -1 <=> c8c9570 minor addition for linux 6.13
#
# CONFIG_WIRELESS_EXT — NOT required, verified by reading the source (same
# analysis as the other five packages; this driver shares the same
# core/os_dep ancestry as the whole RTL8188EU/8812AU/8821AU/8821CU/88x2BU
# family, all descending from one Realtek "rtw" vendor codebase). The only
# code gated by `#ifdef CONFIG_WIRELESS_EXT` is the legacy
# Wireless-Extensions ioctl table (os_dep/linux/os_intfs.c:
# dev->wireless_handlers) and iwconfig signal-quality stats
# (os_dep/linux/ioctl_linux.c) — never the cfg80211/nl80211 path
# (os_dep/linux/ioctl_cfg80211.c's rtw_cfg80211_ops / wiphy_register(),
# unconditional). `wpa_supplicant -D nl80211` (what MiSTer's wifi.sh uses)
# only touches the latter. Our kernel does not define CONFIG_WIRELESS_EXT
# (P1.3 hazard — non-prompt, select-only symbol in 6.18), so the wext-only
# code simply compiles out; no wrapper or kernel `select` hack is needed.
RTL8188FU_VERSION = c8c95708b3756c67139c456a2a6576c1e6491d82
RTL8188FU_SITE = $(call github,kelebek333,rtl8188fu,$(RTL8188FU_VERSION))
RTL8188FU_LICENSE = GPL-2.0
RTL8188FU_LICENSE_FILES = LICENSE

# Buildroot's kernel-module infra bypasses this driver's own `modules:`
# convenience target (the one that `export CONFIG_RTL8188FU = m` before
# re-invoking kbuild) and calls kbuild directly, so
# `obj-$(CONFIG_RTL8188FU) := rtl8188fu.o` sees an empty CONFIG_RTL8188FU
# and silently builds nothing (MODPOST runs on zero objects, no .ko is
# produced). Reproduce the default explicitly.
RTL8188FU_MODULE_MAKE_OPTS = CONFIG_RTL8188FU=m

$(eval $(kernel-module))
$(eval $(generic-package))
