################################################################################
#
# rtl8814au-morrownr
#
################################################################################

# Out-of-tree Realtek RTL8814AU (4x4 802.11ac USB) driver from morrownr's
# actively-maintained fork. RTL8814AU has NO mainline USB driver in 6.18
# (rtl8xxxu is 802.11n only; neither rtw88 nor rtw89 cover it), so an
# out-of-tree driver is the only option -- matching the sibling package/rtl8812au
# and package/rtl8821au-morrownr choices. All three are morrownr forks of the
# same Realtek "rtw" vendor base, together covering the 11ac Realtek USB chips
# mainline still omits (8812au / 8811au+8821au / 8814au). The other Realtek USB
# chips MiSTer's stock kernel drove out-of-tree -- 8188eu/8188fu (rtl8xxxu),
# 8821cu (rtw88_8821cu), 8822bu (rtw88_8822bu) -- are now handled by in-kernel
# drivers, so only these three 11ac forks remain.
#
# Named "-morrownr" for a uniform naming scheme across the morrownr driver set.
# Unlike rtl8821au-morrownr there is no name collision to avoid here (Buildroot
# upstream ships no rtl8814au package), so the suffix is purely cosmetic.
#
# Commit-pinned, not branch-pinned: b1866ce is morrownr/8814au main HEAD at pin
# time.
#
# CONFIG_WIRELESS_EXT -- NOT required, same analysis as the sibling packages.
# Reading the source shows the `#ifdef CONFIG_WIRELESS_EXT` blocks gate only the
# legacy Wireless-Extensions ioctl table (dev->wireless_handlers) and iwconfig
# signal-quality stats in os_dep/linux/{os_intfs,ioctl_linux}.c -- never the
# cfg80211/nl80211 path (os_dep/linux/ioctl_cfg80211.c, unconditional). MiSTer's
# wifi.sh drives it via `wpa_supplicant -D nl80211`, which only touches the
# latter. Our kernel leaves CONFIG_WIRELESS_EXT unset (P1.3 hazard -- non-prompt,
# select-only symbol in 6.18), so the wext-only code compiles out cleanly; no
# wrapper or kernel `select` hack is needed.
RTL8814AU_MORROWNR_VERSION = b1866ce2b857a8dfe2e147e19eb8eca0a842ce18
RTL8814AU_MORROWNR_SITE = $(call github,morrownr,8814au,$(RTL8814AU_MORROWNR_VERSION))
RTL8814AU_MORROWNR_LICENSE = GPL-2.0
RTL8814AU_MORROWNR_LICENSE_FILES = LICENSE

# Buildroot's kernel-module infra calls kbuild directly, bypassing the driver's
# own `modules:` convenience target (the one that would `export CONFIG_RTL8814AU
# = m` before re-invoking kbuild), so `obj-$(CONFIG_RTL8814AU) := $(MODULE_NAME).o`
# sees an empty CONFIG_RTL8814AU and silently builds nothing (MODPOST on zero
# objects, no .ko). Reproduce the default explicitly.
RTL8814AU_MORROWNR_MODULE_MAKE_OPTS = CONFIG_RTL8814AU=m

$(eval $(kernel-module))
$(eval $(generic-package))
