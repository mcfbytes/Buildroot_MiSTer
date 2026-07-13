################################################################################
#
# rtl8812au
#
################################################################################

# P3.1 (PLAN.md §4.1 class E) — out-of-tree Realtek RTL8812AU USB WiFi driver.
#
# Sourced from morrownr's actively-maintained fork, NOT the ~2021 vendor tree
# MiSTer's stock kernel carries (that copy predates 6.x kbuild API churn and
# does not build against 6.18 — see PLAN.md's risk register, class E).
# morrownr/8812au-20210820 is the correct repo for the RTL8812AU chip itself;
# morrownr splits the RTL881x/882x family across several repos (see
# package/rtl8821au for RTL8811AU/RTL8821AU, package/rtl8821cu for RTL8821CU).
#
# Commit-pinned, not branch-pinned. The pin below is main HEAD as of this
# writing, chosen deliberately: its own (merge) commit message is literally
# "support from kernels 6.17-7.0", i.e. upstream itself asserts this exact
# commit builds against our 6.18.y line.
#
#   git log --oneline -1 <=> 8cac6f4 support from kernels 6.17-7.0
#
# CONFIG_WIRELESS_EXT — NOT required, verified by reading the source (not
# assumed). The only code gated by `#ifdef CONFIG_WIRELESS_EXT` is:
#   - os_dep/linux/os_intfs.c: `pnetdev->wireless_handlers = &rtw_handlers_def`
#     (registers the legacy Wireless-Extensions ioctl table)
#   - os_dep/linux/ioctl_linux.c: rtw_get_wireless_stats() (iwconfig signal
#     quality) and the associated iw_handler_def/iwpriv command table
# All of that is for `iwconfig`/`iwlist`/`iwpriv` only. The driver's
# cfg80211/nl80211 path — `rtw_cfg80211_ops` and `wiphy_register()` in
# os_dep/linux/ioctl_cfg80211.c — is registered UNCONDITIONALLY, with no
# CONFIG_WIRELESS_EXT guard anywhere near it. `wpa_supplicant -D nl80211`
# (what MiSTer's wifi.sh invokes) talks to the kernel exclusively through
# that cfg80211/nl80211 path, so it is unaffected either way.
# Our kernel does not define CONFIG_WIRELESS_EXT (P1.3 hazard: it is a
# non-prompt, select-only symbol in 6.18 — see TASKS.md P1.3/P3.1). That just
# means the wext-only code above compiles out. No wrapper, no kernel `select`
# hack, no defconfig line is needed for this driver to work under nl80211.
RTL8812AU_VERSION = 8cac6f43316a56cc89cc8cb532cd6c6ae14c4805
RTL8812AU_SITE = $(call github,morrownr,8812au-20210820,$(RTL8812AU_VERSION))
RTL8812AU_LICENSE = GPL-2.0
RTL8812AU_LICENSE_FILES = LICENSE

# Buildroot's kernel-module infra invokes the KERNEL's own
# `-C $(LINUX_DIR) M=<srcdir> modules` directly, bypassing this driver's own
# `modules:` convenience target entirely -- and it is that bypassed target
# (see the Makefile's `else` branch, only taken when $(KERNELRELEASE) is
# NOT set) which normally does `export CONFIG_RTL8812AU = m` before
# re-invoking kbuild. Skip that and `obj-$(CONFIG_RTL8812AU) := $(MODULE_NAME).o`
# resolves with CONFIG_RTL8812AU empty -> `obj-` (a no-op variable kbuild
# never scans) -> a module that "builds" (MODPOST on zero objects) but
# produces no .ko. Reproduce the default explicitly as a command-line
# override instead, which is what mainline Buildroot's own
# package/rtl8821cu.mk/rtl8188eu.mk/rtl8821au.mk do for the same reason.
RTL8812AU_MODULE_MAKE_OPTS = CONFIG_RTL8812AU=m

$(eval $(kernel-module))
$(eval $(generic-package))
