################################################################################
#
# xone
#
################################################################################

# P3.2 (PLAN.md §4.1 class D/E) — out-of-tree GIP (Game Input Protocol) driver
# for Xbox One / Xbox Series X|S accessories: wired controllers/headsets/
# chatpad/guitars, plus the Xbox Wireless Dongle. Stock's 5.15 fork vendors
# this wholesale (docs/patch-provenance.md §3.5, 7 commits, 19 files under
# drivers/hid/xone/). Re-sourced here as a Buildroot kernel-module package
# instead, per G4 (do not vendor).
#
# FORK CHOICE, CHECKED AT PIN TIME (2026-07-13), NOT ASSUMED:
#
#   medusalix/xone (the original project, and what stock's fork vendored) --
#   `pushed_at` 2025-12-21, and its own README now says in bold: "The original
#   project is in maintenance mode, please refer to [dlundqvist/xone] for
#   updates and issues." Its commit history backs that up: one real commit
#   ("Fix compatibility with latest kernel") after a 19-MONTH gap (2024-04-25
#   -> 2025-12-21), then nothing.
#
#   dlundqvist/xone (fork) -- `pushed_at` 2026-03-24, 397 commits, continuous
#   PR-driven development through March 2026 (merges from multiple external
#   contributors, not just the fork owner). This is the README's own named
#   successor, not an unsanctioned fork. Picked per this task's own guidance
#   to prefer the actively-maintained fork when the original has gone stale.
#
# DEVIATION FROM STOCK WORTH FLAGGING: dlundqvist renamed every module from
# stock's hyphenated scheme (xone-dongle, xone-gip, xone-gip-gamepad, ...) to
# underscores (xone_dongle, xone_gip, xone_gip_gamepad, ...) and moved from a
# single shared "xow_dongle.bin" firmware file to per-USB-PID files
# ("xone_dongle_<pid>.bin"). Neither changes driver *function* -- module
# names don't participate in udev/modalias autoload matching (that's by
# device ID, unaffected), and the firmware split is upstream's own fix for
# using the wrong radio calibration on multi-PID dongle hardware. Flagged
# here because docs/stock-inventory/modules.md's 7-module stock list and
# docs/stock-inventory/firmware.md's "xow_dongle.bin" entry both predate this
# rename and will not string-match the built module/firmware names -- expected,
# not a bug. See docs/decisions/0003-xone-firmware.md for the firmware side.
#
# LOCAL DELTAS FROM MISTER'S OLD (medusalix-based) VENDORED COPY: checked, all
# FOUR turned out to be unnecessary as separate patches -- rumble handling,
# Elite Series 2 paddle support (a `PaddleCapability` enum with distinct
# PADDLE_ELITE/PADDLE_ELITE2_4X/PADDLE_ELITE2_510 cases, more granular than a
# simple backport), per-PID firmware naming, and a sysfs `pairing` attribute
# are ALL already native features of dlundqvist/xone -- this fork's own
# community independently grew equivalent functionality. Full citation:
# docs/patch-provenance.md §3.5.
XONE_VERSION = f2aa9fe01103d7600553b505b298ff0bd47ff280
XONE_SITE = $(call github,dlundqvist,xone,$(XONE_VERSION))
XONE_LICENSE = GPL-2.0+
# Top-level LICENSE is the FSF's standard GPLv2 text; every source file's own
# SPDX-License-Identifier reads "GPL-2.0-or-later" (checked: dongle.c, wired.c,
# mt76.c, bus.c, protocol.c, auth.c, crypto.c, common.c, all driver/*.c), hence
# the Buildroot "+" (GPL-2.0-or-later) rather than a bare "GPL-2.0". The driver
# itself is unambiguously GPL -- it was only the wireless-dongle FIRMWARE (not
# shipped by this package; see package/xow-firmware/ instead) that had an open
# redistribution question, decided in docs/decisions/0003-xone-firmware.md
# (Status: Accepted).
XONE_LICENSE_FILES = LICENSE

# Unlike the P3.1 Realtek drivers, this one does NOT need an explicit
# <PKG>_MODULE_MAKE_OPTS shim. Checked, not assumed: this source tree's Kbuild
# (which kbuild's own out-of-tree module logic prefers over the sibling
# Makefile when both exist at the module root -- and both do here) declares
# `obj-m := xone_gip.o xone_wired.o xone_dongle.o ...` UNCONDITIONALLY, never
# gated behind `obj-$(CONFIG_XONE)`. Buildroot's kernel-module infra calling
# `make -C $(LINUX_DIR) M=$(@D) modules` therefore builds all nine .ko as-is;
# there is no CONFIG_ symbol for the P3.1 gotcha to silently swallow. The
# top-level Makefile's own `default:`/`install:` targets (which DO reference
# $$PWD and a `modules:`-shaped convenience wrapper) are bypassed entirely,
# same as every other package here -- but since Kbuild itself needs no such
# wrapper, bypassing it is harmless.

$(eval $(kernel-module))
$(eval $(generic-package))
