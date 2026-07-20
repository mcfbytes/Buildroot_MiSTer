################################################################################
#
# rtl8188eu-aircrack-ng
#
################################################################################

# P3.1 (PLAN.md §4.1 class E) — out-of-tree Realtek RTL8188EU USB WiFi
# driver.
#
# NAMED "-aircrack-ng", NOT plain "rtl8188eu": Buildroot 2026.05.1 upstream
# already ships its OWN package/rtl8188eu (sourced from
# benetti-engineering/rtl8188eu, a different fork, built via that fork's own
# in-kernel-Kconfig-style CONFIG_RTL8188EU=m integration). A same-named
# package here would collide on both the Kconfig symbol
# (BR2_PACKAGE_RTL8188EU, declared by two different Config.in "config"
# stanzas) and the Make variable/target namespace (two different
# rtl8188eu.mk defining RTL8188EU_VERSION/_SITE/... — whichever gets
# `include`d last silently wins, an undefined-behaviour landmine). Renamed
# to avoid it, following the exact disambiguation convention Buildroot's
# own upstream already uses one row over (package/rtl8812au-aircrack-ng vs.
# a plain rtl8812au namespace) — see PLAN.md/TASKS.md's P3.1 report for the
# collision detail.
#
# DEVIATION FROM morrownr, DOCUMENTED PER THE TASK'S OWN ALLOWANCE: morrownr
# does not carry an RTL8188EU repo (checked morrownr's full repository list
# on GitHub — 7612u, 8812au-20210820, 8814au, 8821au-20210708,
# 8821cu-20210916, 88x2bu-20210702, Monitor_Mode, USB-WiFi, mt76,
# rtl8852bu-20250826, rtl8852cu-20251113, rtw89 — no 8188e of any kind).
# Sourced instead from aircrack-ng/rtl8188eus, the most actively maintained
# fork of the original Realtek RTL8188EU vendor driver (last push at pin
# time: 2025-02-03; the `master`/`v5.7.6.1` branches are stale since 2020).
#
# ⚠ BUILD RISK, STATED PLAINLY: as of the pinned commit, aircrack-ng/rtl8188eus
# has an OPEN, UNMERGED pull request (#319, "v5.3.9: Linux 6.19 + clang
# compatibility fixes, cfg80211 API updates...") whose own description says
# it is needed for the driver to build/run on modern kernels. Issue #317
# ("Added support for kernel 6.14.x") is also open/unmerged. This means the
# pinned commit's build-against-6.18 status is NOT independently asserted by
# upstream the way the morrownr packages' pins are — it was proven
# empirically by this project's own build. See the P3.1 build report for the
# actual result on this kernel tree.
#
# CONFIG_WIRELESS_EXT — NOT required, verified by reading the source (same
# analysis as the other packages; this driver shares the same core/os_dep
# ancestry — the whole RTL8188EU/8812AU/8821AU/8821CU/88x2BU family
# descends from one Realtek "rtw" vendor codebase). The only code gated by
# `#ifdef CONFIG_WIRELESS_EXT` is the legacy Wireless-Extensions ioctl
# table (os_dep/linux/os_intfs.c: dev->wireless_handlers) and iwconfig
# signal-quality stats (os_dep/linux/ioctl_linux.c) — never the
# cfg80211/nl80211 path (os_dep/linux/ioctl_cfg80211.c's rtw_cfg80211_ops /
# wiphy_register(), unconditional). `wpa_supplicant -D nl80211` (what
# MiSTer's wifi.sh uses) only touches the latter. Our kernel does not define
# CONFIG_WIRELESS_EXT (P1.3 hazard — non-prompt, select-only symbol in
# 6.18), so the wext-only code simply compiles out; no wrapper or kernel
# `select` hack is needed.
RTL8188EU_AIRCRACK_NG_VERSION = af3bf004458f76b7aec33e9ba552cd382ed1f5c3
RTL8188EU_AIRCRACK_NG_SITE = $(call github,aircrack-ng,rtl8188eus,$(RTL8188EU_AIRCRACK_NG_VERSION))
RTL8188EU_AIRCRACK_NG_LICENSE = GPL-2.0
# Upstream ships NO top-level LICENSE/COPYING file (checked). Every source
# file carries the same Realtek GPL-2.0 boilerplate header; core/rtw_cmd.c
# is used here as a stable, always-present representative.
RTL8188EU_AIRCRACK_NG_LICENSE_FILES = core/rtw_cmd.c

# Buildroot's kernel-module infra bypasses this driver's own `modules:`
# convenience target (the one that `export CONFIG_RTL8188EU = m` before
# re-invoking kbuild) and calls kbuild directly, so
# `obj-$(CONFIG_RTL8188EU) := $(MODULE_NAME).o` sees an empty
# CONFIG_RTL8188EU and silently builds nothing (MODPOST runs on zero
# objects, no .ko is produced). Reproduce the default explicitly.
RTL8188EU_AIRCRACK_NG_MODULE_MAKE_OPTS = CONFIG_RTL8188EU=m

$(eval $(kernel-module))
$(eval $(generic-package))
