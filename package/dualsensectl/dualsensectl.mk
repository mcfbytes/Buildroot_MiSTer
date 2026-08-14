################################################################################
#
# dualsensectl
#
################################################################################

# Operator CLI for the PlayStation 5 DualSense, talking to the pad directly
# over /dev/hidraw* through hidapi's hidraw backend. Upstream Buildroot
# 2026.05.1 has no dualsensectl package (checked: work/buildroot/package/
# dualsensectl does not exist), so this authors one.
#
# WHY IT IS HERE, AND WHAT IT IS NOT FOR. It covers the DualSense features
# hid-playstation exposes NO interface for -- adaptive trigger effects,
# speaker/headphone routing, output volume, rumble/trigger attenuation,
# microphone mode and volume, player/mic LED dimming, BT power-off, firmware
# info. It does NOT displace the DualSense kernel patches (0033 player_id
# LED, 0037 mic-mute -> BTN_Z, 0042 stock lightbar LED names): those satisfy
# Main_MiSTer's *sysfs LED class device* and *input event* ABIs, neither of
# which a userspace hidraw client can provide. docs/dualsense-tooling.md has
# the full analysis; the short version is that Main_MiSTer's get_led_path()
# (work/Main_MiSTer/input.cpp:2642) builds the LED path from the pad's own
# sysfs devpath, so an LED classdev must be a child of the HID device, and
# the mic-mute button is consumed in-kernel by vanilla with no event for any
# userspace process to see. This package is purely additive.
#
# NO AUTOMATIC INVOCATION. Nothing on this image runs dualsensectl -- no init
# script, no udev rule. That is deliberate: it and hid-playstation both write
# DS_OUTPUT reports to the same pad, and fields they both own (the lightbar
# above all, which Main_MiSTer drives through the :red/:green/:blue classdevs
# 0042 registers) are last-writer-wins. An operator running `dualsensectl
# trigger both weapon ...` from a shell is a deliberate act; a udev rule
# firing it behind Main_MiSTer's back would be a race nobody asked for.
#
# NO UDEV PERMISSION RULE EITHER, unlike upstream's README suggestion. That
# rule (MODE="0660", TAG+="uaccess") exists to hand desktop seat users access
# to the hidraw node. This image has exactly one account -- root, with an
# empty password (BR2_TARGET_GENERIC_ROOT_PASSWD="") and no BR2_ROOTFS_USERS
# table -- and root already opens the default 0600 root:root hidraw node.
# Shipping the rule would be cargo cult: logind/elogind is not installed, so
# TAG+="uaccess" would be inert, and MODE="0660" would only widen permissions
# for a group nothing on the image is a member of.

# TAG PIN, not a commit: upstream tags releases (v0.1..v0.7) and v0.7
# (2025-02-08) is the newest. The leading "v" is kept IN the version string
# rather than reconstructed as "v$(DUALSENSECTL_VERSION)" in the SITE line,
# because scripts/hash-sync-github-packages.sh's generic loop takes the
# literal RHS of the first *_VERSION line and uses it BOTH as the archive ref
# and as the "<pkgdir>-<version>.tar.gz" filename it rewrites in the .hash.
# Splitting the "v" off would make it fetch .../archive/0.7.tar.gz (a 404 --
# there is no bare "0.7" ref) and write a filename Buildroot never asks for.
# Same reason package/munt carries its full "munt_2_7_2" tag verbatim.
DUALSENSECTL_VERSION = v0.7
DUALSENSECTL_SITE = $(call github,nowrep,dualsensectl,$(DUALSENSECTL_VERSION))

# The sources carry "SPDX-License-Identifier: GPL-2.0-or-later" at the top of
# both main.c and crc32.h -- checked by reading them, not inferred from
# meson.build, whose looser `license: 'GPLv2'` field would have read as plain
# GPL-2.0. LICENSE is the GPLv2 text. Buildroot spells "or later" as the "+"
# suffix (395 upstream .mk files use GPL-2.0+; exactly one uses the SPDX long
# form), so this follows the house majority.
DUALSENSECTL_LICENSE = GPL-2.0+
DUALSENSECTL_LICENSE_FILES = LICENSE

# meson.build's dependency() calls, one for one:
#   libudev       -> udev (the virtual provider; eudev on this image)
#   dbus-1        -> dbus, used ONLY by `power-off`, which asks BlueZ over the
#                    system bus to Disconnect the pad (main.c:422-491). Both
#                    dbus and libusb (hidapi's other leg) were already in the
#                    defconfig before this package, so the only genuinely new
#                    libraries on the image are hidapi and libgudev.
#   hidapi-hidraw -> hidapi. Buildroot's hidapi builds BOTH backends on Linux
#                    and installs hidapi-hidraw.pc alongside hidapi-libusb.pc;
#                    the hidraw one is what is wanted here, since the libusb
#                    backend cannot see a Bluetooth-connected pad at all.
# host-pkgconf because meson resolves all three through pkg-config.
DUALSENSECTL_DEPENDENCIES = host-pkgconf hidapi dbus udev

# Upstream also ships bash/zsh completions under completion/, but its
# meson.build does not install them and this package does not add them by
# hand: BR2_PACKAGE_BASH_COMPLETION is not enabled on this image, so they
# would be dead files in the rootfs.
$(eval $(meson-package))
