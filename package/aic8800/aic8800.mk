################################################################################
#
# aic8800
#
################################################################################

# Out-of-tree AICSemi AIC8800-family Wi-Fi 6 (802.11ax) + Bluetooth USB driver
# and its firmware. Two modules -- aic_load_fw (stage 1: claims the ROM
# bootloader device, downloads the image, the device re-enumerates) and
# aic8800_fdrv (stage 2: the cfg80211 fullmac driver) -- plus ~6.6 MiB of
# firmware blobs, which this package installs because the driver is INERT
# without them.
#
# WHY THIS IS ADMISSIBLE UNDER ADR 0016. The rule is "use the in-kernel driver
# for every chip mainline can drive; keep an out-of-tree fork ONLY where
# mainline still has no USB driver". Mainline has no aic8800 driver AT ALL --
# no chip HAL, no bus file, no staging entry, no MAINTAINERS line -- verified
# by case-insensitive grep for aic8800 / aicwf / AICSemi / RivieraWaves / rwnx
# over drivers/, net/ and MAINTAINERS in three trees (6.18.49, 7.2.3,
# v7.3-rc2): zero files in all three. This is the second package in the tree
# to meet that bar, alongside rtl8852cu-morrownr.
#
# NO BIND CONFLICTS. The two modules claim 46 unique VID:PIDs between them
# (41 from aic8800_fdrv's table with CONFIG_USB_BT=y, 11 from aic_load_fw's
# bootstrap table, 6 shared). All 46 were checked one-by-one against
# drivers/net/wireless/, drivers/bluetooth/, drivers/usb/ and drivers/net/usb/
# in 6.18: overlaps=0. Two near misses worth knowing about, neither live:
# rtw88's rtl8812au.c claims 2604:0012, one PID below the Tenda block here;
# rtw89's rtl8851bu.c and btusb.c both claim 3625:010b against our 3625:0110.
#
# ---------------------------------------------------------------------------
# PROVENANCE -- why radxa-pkg and not stock's own copy
# ---------------------------------------------------------------------------
#
# MiSTer stock (MiSTer-devel/Linux-Kernel_MiSTer, MiSTer-v6.18 commit
# c129b0fac34ad5d613bbec3f59d6036775e41c83, "Add AIC8800 WiFi/BT driver.")
# VENDORED this driver into its kernel tree as 142 files / 82,330 insertions.
# We cannot follow it there: ADR 0016 and PLAN 2.9 both forbid carrying an
# 82k-line in-tree patch in board/mister/de10nano/linux-patches/, because it
# would make scripts/export-kernel-tree.sh's per-patch replay and
# scripts/lint-kernel-patches.sh meaningless for that entry. It has to be a
# Buildroot kernel-module package, which means it has to come from somewhere
# fetchable as a tarball -- and stock's copy lives inside a multi-GB kernel
# repository with no standalone artifact.
#
# radxa-pkg/aic8800 packages the SAME AICSemi SDK snapshot. This was verified,
# not assumed, against the generated version header both trees carry:
#
#   stock c129b0fac3   RWNX_VERS_REV "1a4b0054d2M (master)"
#                      RWNX_VERS_MOD "6.4.3.0"
#                      RELEASE_DATE  "2026_0123_5f7be68d"
#   radxa-pkg 516e3b08 RWNX_VERS_REV "1a4b0054d2M (master)"
#                      RWNX_VERS_MOD "6.4.3.0"
#                      RELEASE_DATE  "2026_0123_5f7be68d"   <- identical
#
# and radxa's own release tags spell the same stamp out: the newest is
# `5.0+git20260123.5f7be68d-8`. The file inventories match too: 111/110 files
# in aic8800_fdrv and 24/23 in aic_load_fw, the only difference being the
# .gitignore stock added when vendoring. So the chip coverage this package
# ships is the chip coverage stock ships -- including the newer 8800D80N /
# 8800D80X2 / 8800DLN variants, which the other public mirrors of this driver
# (goecho/aic8800_linux_drvier and friends) predate and do not carry.
#
# The two trees are NOT byte-identical, and the differences run in both
# directions and are understood: stock's copy is adapted for IN-TREE kbuild
# (EXTRA_CFLAGS -> ccflags-y, CONFIG_AIC8800_WLAN_SUPPORT commented out
# because the kernel Kconfig supplies it), while radxa's keeps the vendor's
# out-of-tree scaffolding -- which is the shape Buildroot's kernel-module
# infrastructure wants -- and carries extra hardening stock has not taken,
# e.g. the USB disconnect-callback synchronisation in aicwf_usb.c.
#
# radxa-pkg ALSO ships the firmware, which stock does not, and which is the
# whole reason this package can exist at all. As of the pin date stock had
# shipped no firmware in any release (Linux_Image_creator_MiSTer's newest
# commit, d4e3f51ec "Release 20260907.", PRE-DATES the driver commit) and
# linux-firmware carries no AIC blobs in either our pinned 20260410 tree or
# upstream main. See docs/wifi-parity.md section 10.
#
# ---------------------------------------------------------------------------
# LICENCE -- stated plainly, because it is not clean
# ---------------------------------------------------------------------------
#
# debian/copyright is the most authoritative statement that exists for this
# code and it says: src/* is GPL-2, the Debian packaging is GPL-3+. The driver
# sources agree at the module level (two MODULE_LICENSE("GPL") declarations),
# but many individual vendor files carry a bare copyright line with no grant,
# and a couple are Apache-2.0 inside an otherwise-GPL tree. There is no
# upstream AICSemi repository to point at: every public copy, radxa's included,
# is a re-published SDK drop.
#
# The firmware blobs are ordinary redistributed vendor binaries with no licence
# text of their own -- the same posture this tree already takes for
# xow_dongle.bin (ADR 0003) and BCM20702A1-0b05-17cb.hcd
# (package/bcm20702-firmware). LICENSE_FILES points at debian/copyright rather
# than the repo's top-level LICENSE, because the top-level file is the GPL-3
# text covering radxa's packaging and would misdescribe the driver.
#
# This ambiguity was the reason the driver was DEFERRED on first analysis
# (owner decision D2, docs/kernel-recon/fork-sync-2026-09/memo-Q9-aic8800.md).
# It was reversed by the owner in full knowledge of it: stock is clearly
# heading for shipping the chip, and resellers bundle these dongles. The
# ambiguity is recorded here rather than resolved, because it cannot be
# resolved from outside AICSemi.

AIC8800_VERSION = 516e3b087763d80c44f5e3b6d2dd63e0d925c91d
AIC8800_SITE = $(call github,radxa-pkg,aic8800,$(AIC8800_VERSION))
AIC8800_LICENSE = GPL-2.0 (driver, per debian/copyright + MODULE_LICENSE), PROPRIETARY (AICSemi firmware blobs, redistributed)
AIC8800_LICENSE_FILES = debian/copyright

# Only the USB tree is built. The tarball also carries PCIE/ and SDIO/ driver
# trees for the same chips; this board has no PCIe (CONFIG_PCI is unset) and
# the SDIO part is a soldered-down module, not a dongle, so neither is
# reachable here.
#
# ONE kbuild pass over the PARENT directory builds BOTH modules: its Makefile
# is `obj-m += aic_load_fw/` + `obj-m += aic8800_fdrv/`, so modpost sees them
# together and resolves aic8800_fdrv's references to the ten symbols
# aic_load_fw exports (get_fw_path, get_testmode, get_hardware_info, ...) in
# that single run. Do NOT split this into two M= passes chasing an ordering
# problem -- there isn't one, and splitting it would create the
# KBUILD_EXTRA_SYMBOLS dance that the single pass avoids.
AIC8800_MODULE_SUBDIRS = src/USB/driver_fw/drivers/aic8800

# Both sub-Makefiles already self-select as modules, but pass these anyway:
# command-line variables beat the in-file `:=` and propagate to the sub-makes
# kbuild spawns, so the selection cannot drift if a version bump changes the
# vendor default.
AIC8800_MODULE_MAKE_OPTS = \
	CONFIG_AIC_LOADFW_SUPPORT=m \
	CONFIG_AIC8800_WLAN_SUPPORT=m

# ---------------------------------------------------------------------------
# VENDOR PATCH SERIES
# ---------------------------------------------------------------------------
#
# radxa-pkg ships the RAW AICSemi SDK under src/ and applies its own quilt
# series at build time from debian/patches/. That series is LOAD-BEARING, not
# cosmetic: it is where every kernel-API compatibility fix lives
# (fix-linux-6.13 through 6.17, 6.19, 7.1, 7.2), and the 2026-01 SDK snapshot
# does NOT compile against a modern cfg80211 without them. Every one is
# LINUX_VERSION_CODE-guarded, so applying the whole set is correct on any
# kernel; note the series jumps 6.17 -> 6.19, i.e. our 6.18 needs nothing of
# its own. The series also carries real bug fixes (USB suspend/reboot hang, a
# missing vmalloc.h, an SDIO fall-through) and the debug-log-level reduction.
#
# WE SKIP EXACTLY FOUR, and only these four: the *-firmware-path patches, which
# relocate firmware into Debian's /lib/firmware/aic8800_fw/{USB,SDIO,PCIE}/
# layout. We keep the VENDOR DEFAULT, /lib/firmware/<chip-variant>/, because
# that is the path stock's in-kernel copy uses and matching stock is the point.
# AIC8800_CHECK_FW_PATH below asserts that outcome after patching, so if a
# future bump moves the relocation into a differently-named patch the build
# fails loudly instead of silently installing firmware where nothing looks.
#
# WHY THE CRLF NORMALISATION COMES FIRST: four vendor files under aic_load_fw/
# ship CRLF line endings while every radxa patch is LF, and plain `patch`
# rejects those hunks -- silently leaving aic_load_fw at the vendor's
# LOGERROR|LOGINFO|LOGDEBUG|LOGTRACE debug level, which floods dmesg on every
# hotplug. `patch -l` does not rescue it. Normalising the tree to LF first
# makes all 23 non-skipped patches apply with zero fuzz.
#
# This runs as a POST_EXTRACT hook so it lands BEFORE Buildroot's own patch
# step, which keeps any patch we ever add under package/aic8800/ layered on
# top of upstream's series rather than fighting it.

AIC8800_SKIP_PATCHES = \
	fix-usb-firmware-path.patch \
	fix-sdio-firmware-path.patch \
	fix-pcie-firmware-path.patch \
	fix-sdio-per-chip-firmware-path.patch

# Written to fail LOUDLY, which took two rewrites to get right -- the obvious
# shapes for this loop all fail silently:
#
#   * `set -e` first, so a failed cd or a rejected hunk aborts instead of
#     letting the rest of the recipe carry on against an unpatched tree. The
#     first draft chained `cd $(@D) && find ... && applied=0; while ...`, where
#     the `;` before `applied=0` ends the && list: a failed cd skipped the find
#     but still ran the loop, which then read no series file, iterated zero
#     times and echoed a cheerful "applied=0 skipped=0" before exiting 0.
#   * NO `[ -z "$$p" ] && continue` guard. Under `set -e` that is a trap, not a
#     no-op: when $$p is non-empty the test fails, and a failing test that is
#     the whole AND-OR list aborts the shell. Both the empty-line and the
#     not-a-patch cases go through `case` instead, which always returns 0.
#   * The line filter is `*.patch`, not a `#`-comment check. `#` inside a
#     define is a question about GNU Make's comment handling that this does not
#     need to answer -- and radxa's series file has no comments anyway.
#   * `test $$applied -gt 0` at the end. A series file that moved or emptied
#     would otherwise patch nothing and report success, and the build would
#     fail much later with the confusing cfg80211 get_txpower error instead of
#     here with the real reason.
define AIC8800_APPLY_VENDOR_PATCHES
	set -e; \
	cd $(@D); \
	find src -type f \( -name '*.c' -o -name '*.h' -o -name 'Makefile' \) \
		-exec sed -i 's/\r$$//' {} + ; \
	applied=0; skipped=0; \
	while read -r p; do \
		case "$$p" in \
			*.patch) ;; \
			*) continue ;; \
		esac; \
		case " $(AIC8800_SKIP_PATCHES) " in \
			*" $$p "*) skipped=$$((skipped + 1)); continue ;; \
		esac; \
		echo "aic8800: applying $$p"; \
		patch -p1 --batch --forward -s -i "debian/patches/$$p"; \
		applied=$$((applied + 1)); \
	done < debian/patches/series; \
	echo "aic8800: vendor series applied=$$applied skipped=$$skipped"; \
	test "$$applied" -gt 0
endef
AIC8800_POST_EXTRACT_HOOKS += AIC8800_APPLY_VENDOR_PATCHES

# Assert the firmware path the driver will actually build with. This is the
# single most breakable assumption in the package: the driver does NOT use
# request_firmware() (CONFIG_USE_FW_REQUEST is n in both module Makefiles), so
# none of /lib/firmware's normal search behaviour applies -- it filp_open()s a
# path it concatenates itself from this string plus a per-chip subdirectory.
# If this string ever moves, the firmware installed below becomes unreachable
# and the driver fails at probe with nothing but a `firmware path = ...` line
# in dmesg to explain it.
define AIC8800_CHECK_FW_PATH
	grep -q 'aic_default_fw_path = "/lib/firmware";' \
		$(@D)/src/USB/driver_fw/drivers/aic8800/aic_load_fw/aicbluetooth.c || \
		{ echo "aic8800: FATAL: default firmware path is no longer /lib/firmware --" \
		       "the installed blobs would be unreachable. Re-check" \
		       "AIC8800_SKIP_PATCHES against debian/patches/series." >&2; exit 1; }
endef
AIC8800_POST_PATCH_HOOKS += AIC8800_CHECK_FW_PATH

# ---------------------------------------------------------------------------
# FIRMWARE
# ---------------------------------------------------------------------------
#
# Installed into per-chip subdirectories of /lib/firmware because that is
# where the driver looks: aic_load_fw/aicbluetooth.c:320-337 builds
# "<aic_default_fw_path>/<variant>/<name>" switched on usb_dev->chipid, and
# aic8800_fdrv takes the bare path from get_fw_path() and strcat()s the same
# suffix per variant (aicwf_compat_8800d80.c:43 "/aic8800D80",
# rwnx_platform.c:1672 "/aic8800DC", :1811 "/aic8800D80N", :1841
# "/aic8800DLN", aicwf_compat_8800d80x2.c:44 "/aic8800D80X2"). Installing
# these flat into /lib/firmware/ -- which is what every other firmware in this
# image does, and the obvious thing to do -- yields a driver that still fails.
#
# All six variants ship: 6.6 MiB over 84 files. Trimming to the two or three
# variants today's retail dongles use would save ~4 MiB, but the whole point
# of the package is that a user buys an unidentified cheap AX stick and it
# works, and the chipid switch is made at runtime from the USB ID.
AIC8800_FW_VARIANTS = \
	aic8800 \
	aic8800D80 \
	aic8800D80N \
	aic8800D80X2 \
	aic8800DC \
	aic8800DLN

define AIC8800_INSTALL_TARGET_CMDS
	for v in $(AIC8800_FW_VARIANTS); do \
		$(INSTALL) -d $(TARGET_DIR)/lib/firmware/$$v ; \
		$(INSTALL) -m 0644 $(@D)/src/USB/driver_fw/fw/$$v/* \
			$(TARGET_DIR)/lib/firmware/$$v/ || exit 1 ; \
	done
endef

$(eval $(kernel-module))
$(eval $(generic-package))
