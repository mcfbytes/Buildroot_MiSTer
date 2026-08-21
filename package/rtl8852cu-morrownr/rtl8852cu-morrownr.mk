################################################################################
#
# rtl8852cu-morrownr
#
################################################################################

# Out-of-tree Realtek RTL8852CU / RTL8832CU (Wi-Fi 6E, 2x2, 2.4/5/6 GHz USB)
# driver from morrownr's fork of the Realtek "phl" vendor tree.
#
# THIS PACKAGE DELIBERATELY REVERSES THE "ZERO OUT-OF-TREE WIFI DRIVERS" STATE
# the v10 image reached (docs/decisions/0016-mainline-first-wifi-drivers.md,
# defconfig "P3.1/v9" block). It is not a relapse: ADR 0016's rule was never
# "no forks", it was "use the in-kernel driver for every chip mainline can
# drive; keep a fork ONLY where mainline still has no USB driver". v10 emptied
# the exception list because mainline had caught up on 8812au/8821au/8814au.
# RTL8852CU is a chip mainline has NOT caught up on, so the same unchanged rule
# re-populates the list with exactly one entry. Maintainer decision, 2026-07-27.
#
# WHY MAINLINE CANNOT DRIVE IT -- verified against the pinned kernel tree, not
# assumed. rtw89 DOES have the RTL8852C chip HAL (RTW89_8852C, the shared
# rtw8852c.c / rtw8852c_rfk.c / rtw8852c_table.c), but the only BUS file built
# on top of it is the PCIe one:
#
#   output/build/linux-6.18.40/drivers/net/wireless/realtek/rtw89/
#     rtw8852c.c  rtw8852c_rfk.c  rtw8852c_table.c   <- chip HAL, present
#     rtw8852ce.c                                    <- PCIe bus file, present
#     (no rtw8852cu.c)                               <- USB bus file, ABSENT
#
# and its Kconfig offers only the PCIe variant:
#
#   drivers/net/wireless/realtek/rtw89/Kconfig:113-122
#     config RTW89_8852CE
#       tristate "Realtek 8852CE PCI wireless network (Wi-Fi 6E) adapter"
#       depends on PCI
#
# For contrast the same directory DOES ship rtw8851bu.c and rtw8852bu.c (the
# RTW89_8851BU / RTW89_8852BU USB parts this image already builds), so the gap
# is specific to 8852C rather than rtw89 lacking USB support in general. This
# board has no PCIe (CONFIG_PCI is unset), so RTW89_8852CE is unreachable even
# if it were enabled -- an RTL8852CU dongle currently gets NO driver at all.
# That is the single remaining USB WiFi coverage gap the v10.1 audit found
# (docs/wifi-parity.md section 7).
#
# Commit-pinned, not branch-pinned:
#
#   git ls-remote https://github.com/morrownr/rtl8852cu-20251113
#     1530c38e5b1be6d1e96a31cf4f3602a9c23f2465  HEAD
#     1530c38e5b1be6d1e96a31cf4f3602a9c23f2465  refs/heads/main
#
# i.e. HEAD and main resolved to the same commit at pin time (2026-07-27).
# Upstream's README.md:74-75 states its own supported range as "Kernels: 5.15 -
# 6.14 (Realtek)" / "Kernels: 6.15 - 7.1 (community support)", so our 6.18.40 is
# inside the community-supported band -- NOT inside Realtek's own tested band.
# That is a weaker upstream assurance than package/rtl8812au had (whose pinned
# commit message literally read "support from kernels 6.17-7.0"); treat a build
# break on a kernel bump as expected maintenance, not a surprise.
# README.md:66 lists "armv6l, armv7l (arm)" as a compatible architecture.
#
# Named "-morrownr" for the uniform naming scheme across the morrownr driver
# set. There is no collision to avoid here: Buildroot 2026.05.1 upstream ships
# no rtl8852cu package (checked work/buildroot/package/rtl* -- rtl8188eu,
# rtl8189es, rtl8189fs, rtl8192eu, rtl8723bu, rtl8723ds, rtl8723ds-bt,
# rtl8812au-aircrack-ng, rtl8821au, rtl8821cu, rtl8822cs, rtl_433 and nothing
# else), so the suffix is purely cosmetic, exactly as for rtl8814au-morrownr.
#
# CONFIG_WIRELESS_EXT -- NOT required. Re-verified against THIS source rather
# than inherited from the sibling packages, because this is a DIFFERENT code
# base: 8812au/8814au/8821au are the old Realtek "rtw" tree, this is the newer
# "phl" tree (phl/hal_g6/...), so the sibling analysis could not just be copied.
# The conclusion happens to match, but one detail is new and is why this
# paragraph is longer than the siblings':
#
#   - os_dep/linux/os_intfs.c:447  `#ifdef CONFIG_WIRELESS_EXT` ->
#     pnetdev->wireless_handlers = &rtw_handlers_def  (the legacy WEXT ioctl
#     table registration)
#   - include/rtw_ioctl.h:34  `#if defined(PLATFORM_LINUX) &&
#     defined(CONFIG_WIRELESS_EXT)` -> the extern for that table
#   - os_dep/linux/ioctl_linux.c:7709 and :8173 -> the iw_handler_def /
#     iwpriv command tables and the iwconfig signal-quality stats
#   Those four sites are the ONLY CONFIG_WIRELESS_EXT uses in the whole tree,
#   and all four are iwconfig/iwlist/iwpriv-only. The cfg80211/nl80211 path is
#   separate and is what `wpa_supplicant -D nl80211` (MiSTer's wifi.sh) uses.
#
#   NEW, not present in the sibling forks: include/osdep_service_linux.h:88-90
#   contains a SELF-DEFINE fallback --
#       #ifdef CONFIG_NET_RADIO
#       #define CONFIG_WIRELESS_EXT
#       #endif
#   -- so, unlike the siblings, this driver can switch the WEXT code on without
#   the kernel's own symbol. That fallback is dead: CONFIG_NET_RADIO was a
#   pre-2.6.17 kernel symbol and does not exist in 6.18.40 (grep over the pinned
#   tree's net/ and include/ returns zero files). Recorded because it is exactly
#   the kind of thing that would quietly invalidate the copied analysis.
#
#   Our kernel resolves CONFIG_WEXT_CORE=y, CONFIG_WEXT_PROC=y and
#   CONFIG_CFG80211_WEXT=y but leaves CONFIG_WIRELESS_EXT unset
#   (output/build/linux-6.18.40/.config:1153-1164; the generated
#   include/generated/autoconf.h contains zero occurrences of it). It is a
#   non-prompt, select-only bool -- net/wireless/Kconfig:2-3 -- which is the
#   P1.3 hazard. So the WEXT-only code above simply compiles out; no wrapper and
#   no kernel `select` hack is needed.
RTL8852CU_MORROWNR_VERSION = c9b43801805db0b39f7b9e0da11f8841a95a069c
RTL8852CU_MORROWNR_SITE = $(call github,morrownr,rtl8852cu-20251113,$(RTL8852CU_MORROWNR_VERSION))
RTL8852CU_MORROWNR_LICENSE = GPL-2.0
RTL8852CU_MORROWNR_LICENSE_FILES = LICENSE

# NO FIRMWARE PACKAGE IS NEEDED for this driver, and that is worth stating
# because the mainline rtw89 driver next door DOES need one
# (BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW89 -> rtw89/*.bin, already enabled for
# RTL8851BU/RTL8852BU). This vendor tree links its firmware in as a C array
# instead: Makefile:96 sets `CONFIG_FILE_FWIMG = n`, include/autoconf.h:128
# defines LOAD_FW_HEADER_FROM_DRIVER, and the image itself is
# phl/hal_g6/mac/fw_ax/rtl8852c/hal8852c_fw.c -- a single 13.7 MB generated .c
# file. Consequence to expect: the resulting 8852cu.ko is LARGE (the extracted
# source tree is ~67 MB, ~15 MB of it firmware arrays). The on-image size has
# NOT been measured -- see docs/wifi-parity.md section 8.
#
# TWO kbuild quirks, both required. Buildroot's kernel-module infra calls kbuild
# directly (package/pkg-kernel-module.mk:71-81: `$(MAKE) -C $(LINUX_DIR)
# $(LINUX_MAKE_FLAGS) $(..._MODULE_MAKE_OPTS) PWD=... M=... modules`), which
# means every assumption this Makefile makes about being invoked through its own
# `modules:` target is void.
#
# (1) CONFIG_RTL8852CU=m -- the same trap as the seven OTHER Realtek
#     kernel-module packages here, every one of which carries the identical
#     `<PKG>_MODULE_MAKE_OPTS = CONFIG_<CHIP>=m` line (grep MODULE_MAKE_OPTS
#     over package/*/*.mk: rtl8812au, rtl8814au-morrownr, rtl8821au-morrownr,
#     rtl8821cu-morrownr, rtl8188fu, rtl8188eu-aircrack-ng, rtl88x2bu). The one
#     kernel-module package that does NOT need the shim is package/xone, whose
#     Kbuild declares `obj-m :=` unconditionally -- its own header records that
#     as checked, not assumed.
#     Makefile:936-937 is `obj-$(CONFIG_RTL8852CU) := $(MODULE_NAME).o`, and the
#     only thing that ever sets that variable is Makefile:957,
#     `export CONFIG_RTL8852CU = m`, which sits in the `else` branch of
#     `ifneq ($(KERNELRELEASE),)` -- i.e. the branch taken ONLY when the driver's
#     own top-level `modules:` target runs, which Buildroot never invokes. Left
#     empty, `obj-` is a variable kbuild never scans: MODPOST runs on zero
#     objects, the package "succeeds", and no .ko exists. Reproduce it here.
#
# (2) KSRC=$(LINUX_DIR) -- NEW, and specific to this newer "phl" code base; the
#     five sibling morrownr forks do not need it because upstream already
#     converted them to write `ccflags-y` directly. Checked by extracting
#     Makefile line 1 from all five cached tarballs, not extrapolated from one:
#
#       dl/rtl8812au/            ccflags-y += $(USER_ccflags-y)
#       dl/rtl8814au-morrownr/   ccflags-y += $(USER_ccflags-y)
#       dl/rtl8821au-morrownr/   ccflags-y += $(USER_EXTRA_CFLAGS)
#       dl/rtl8821cu-morrownr/   ccflags-y += $(USER_EXTRA_CFLAGS)
#       dl/rtl88x2bu/            ccflags-y += $(USER_EXTRA_CFLAGS)
#       dl/rtl8852cu-morrownr/   EXTRA_CFLAGS += $(USER_EXTRA_CFLAGS)   <- ours
#
#     (Five, not seven: the other two MODULE_MAKE_OPTS packages listed under (1)
#     are not morrownr forks -- rtl8188fu is kelebek333's and rtl8188eu is
#     aircrack-ng's. rtl8188eu-aircrack-ng's Makefile line 1 is in fact still
#     `EXTRA_CFLAGS += $(USER_EXTRA_CFLAGS) -fno-pie`, i.e. unconverted like
#     ours -- but it is deselected in the defconfig, so it is not a live
#     counter-example to anything this image builds.)
#
#     This tree, by contrast, still builds its entire flag set in
#     EXTRA_CFLAGS, and EXTRA_CFLAGS NO LONGER EXISTS in 6.18 kbuild -- grep for
#     it over output/build/linux-6.18.40/scripts/ and the top-level Makefile
#     returns zero hits. The driver knows this and translates, at
#     Makefile:927-934:
#
#         KER_MINOR_15 := $(shell cd $(KSRC); echo `make kernelversion | \
#                                 cut -d. -f2` \>= 15 | bc -l)
#         ifeq ($(KER_MAJOR_7), 1)
#         ccflags-y := $(EXTRA_CFLAGS)
#         else ifeq ($(KER_MAJOR_6), 1)
#         ifeq ($(KER_MINOR_15), 1)
#         ccflags-y := $(EXTRA_CFLAGS)
#         endif
#         endif
#
#     but KER_MAJOR_6/KER_MAJOR_7 (Makefile:333-334) are probed by shelling out
#     to `$(MAKE) -s -C $(KSRC) kernelversion`, and KSRC is set by
#     platform/autodetect.mk:18 to `/lib/modules/$(shell uname -r)/build` -- the
#     BUILD HOST's running kernel. In a cross build that path is wrong, and on a
#     CI container or this workstation it does not exist at all. The probe's
#     `2>/dev/null` swallows the failure, `bc` then gets `echo >= 6` and errors
#     out with an empty result (verified by running the exact fragment), so
#     KER_MAJOR_6 != 1, the translation is skipped, and EVERY EXTRA_CFLAGS entry
#     is silently dropped -- including `-I$(src)/include` (Makefile:63) and
#     `-DCONFIG_RTL8852C` (phl/hal_g6/rtl8852c/rtl8852c.mk:1), i.e. both the
#     include path and the define that selects the chip. Pointing KSRC at the
#     kernel Buildroot is actually building fixes the probe at the source.
#     autodetect.mk uses `:=`, but a make COMMAND-LINE assignment overrides any
#     makefile assignment, and pkg-kernel-module.mk:77 places MODULE_MAKE_OPTS on
#     the command line -- so this reaches every included .mk, not just the top
#     Makefile.
#
#     Two alternatives were considered and rejected:
#       - Patching the Makefile to set ccflags-y unconditionally. It works, but
#         it is a patch against a 1069-line vendor Makefile that upstream
#         rewrites freely, i.e. re-work on every pin bump, for no benefit over
#         one variable.
#       - Setting CONFIG_PLATFORM_AUTODETECT=n to stop autodetect.mk clobbering
#         KSRC. Strictly worse: that same file is also the ONLY place that adds
#         -DCONFIG_IOCTL_CFG80211, -DCONFIG_LITTLE_ENDIAN and
#         -DCONFIG_REGD_SRC_FROM_OS (platform/autodetect.mk:2-7), so turning it
#         off would take the whole cfg80211/nl80211 path out with it.
#
#     Cosmetic, not fixed: the KER_MINOR_15 probe at Makefile:927 calls plain
#     `make` without resetting MAKEFLAGS the way lines 333-335 do, so under a
#     parallel build it prints "warning: jobserver unavailable: using -j1" to
#     stderr. Verified that the value it consumes on stdout is still correct.
#
# Kept on ONE line on purpose, unwrapped: scripts/export-kernel-tree.sh lifts this
# recipe out of the .mk with `sed -n "s/^${upper}_MODULE_MAKE_OPTS = //p"`, which
# reads a single line and would capture a bare backslash from a `\`-continued
# assignment. That script also rewrites the $(LINUX_DIR) below into the exported
# tree's own $KDIR -- see its EXPORTED_LINUX_DIR note.
RTL8852CU_MORROWNR_MODULE_MAKE_OPTS = CONFIG_RTL8852CU=m KSRC=$(LINUX_DIR)

# BIND-CONFLICT CHECK (ADR 0016's stated reason for DISABLING, not merely
# not-enabling, a redundant fork). Result: NO conflict with any in-kernel driver
# this image builds -- but the margin is thinner than it looks, so read on
# before touching the chip switches.
#
# This is a MULTI-CHIP tree. Makefile:70-76 carries switches for RTL8852B,
# 8852BP, 8852BT, 8851B, 8852C, 8852D and 8842A, and upstream ships only
# `CONFIG_RTL8852C = y` (Makefile:74) with every other one `= n`. The USB ID
# table in os_dep/linux/usb_intf.c:143-202 is #ifdef-partitioned per chip, so the
# module that actually gets built claims ONLY the nine RTL8852C IDs:
#
#   0bda:c85a  0bda:c832  0bda:c85d      (Realtek reference)
#   0db0:991d  MSI AXE5400
#   2c4e:0127  Mercusys MA86XH
#   3574:6251  Sihai Lianzong
#   35b2:0502  TP-Link Archer TXE70UH
#   35bc:0101  TP-Link Archer TX50UH V1
#   35bc:0102  TP-Link Archer TXE70UH(EU) V1
#
# All nine were grepped against drivers/net/wireless/ and drivers/bluetooth/ in
# the pinned 6.18.40 tree: zero matches. The near-misses are close enough to be
# worth writing down -- rtw89_8852bu claims 35bc:0100 and 35bc:0108 (ours are
# 35bc:0101/0102) and btusb claims 2c4e:0128 (ours is 2c4e:0127).
#
# (Upstream's own supported-device-IDs file lists only eight of the nine -- it
# omits 2c4e:0127, which usb_intf.c:184 does carry. The source is authoritative;
# the doc lags.)
#
# DO NOT flip another CONFIG_RTL88xx switch on in this Makefile. The blocks that
# are compiled out are precisely the ones that WOULD collide: the 8852B block
# lists 0bda:b832/b83a/b852/b85a/a85b, every one of which is in mainline's
# rtw8852bu.c; the 8851B block lists 0bda:b851 (mainline rtw8851bu.c) and
# 3574:6211 (mainline mt76/mt7921/usb.c). Enabling either would recreate exactly
# the load-order-dependent bind fight ADR 0016 exists to prevent.
#
# Module name is 8852cu (Makefile:433-442 picks MODULE_NAME per IC_NAME +
# HCI_NAME; CONFIG_RTL8852C=y with CONFIG_USB_HCI=y -> 8852cu). It installs to
# usr/lib/modules/$(KVER)/updates/8852cu.ko(.xz) -- the kernel's
# scripts/Makefile.modinst:48 defaults INSTALL_MOD_DIR to `updates` for M=
# builds -- which is where scripts/ci-tests.sh asserts it.
$(eval $(kernel-module))
$(eval $(generic-package))
