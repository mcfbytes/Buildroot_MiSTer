################################################################################
#
# ltunify
#
################################################################################

# Pair, unpair and inspect devices on a Logitech Unifying receiver, over
# /dev/hidraw* with no library dependencies at all. Upstream Buildroot 2026.05.1
# has no ltunify package (checked: work/buildroot/package/ltunify does not
# exist), so this authors one.
#
# WHY THIS AND NOT SOLAAR. Solaar is the actively-maintained tool and covers
# more hardware (Unifying, Bolt, Lightspeed), but its ONLY console_scripts entry
# point is "solaar = solaar.gtk:main", and solaar/gtk.py imports solaar.ui at
# module level, which does gi.require_version("Gtk", "3.0"). Running `solaar
# pair` therefore drags in the whole GTK3 stack -- on an image with zero X11/GTK
# packages and no display server. It would also mean authoring two more missing
# packages (python-dbus, python-hid-parser, neither in Buildroot 2026.05.1) plus
# a carried patch to defer the GUI import. ltunify is two C files and -lrt.
# docs/logitech-pairing.md has the full comparison, including what ltunify
# CANNOT do.
#
# WHAT IT CANNOT DO, stated here because the limits are the reason a wrapper
# exists at all (rootfs-overlay/usr/sbin/mister-pair-logitech):
#
#   * LIGHTSPEED / POWERPLAY (c539/c53a/c53f/c543) and 27 MHz (c51b) receivers
#     bind as "logitech-djreceiver" identically to Unifying ones, so they pass
#     ltunify's driver-name test in open_hidraw() (ltunify.c:1158) and then fail
#     at the register write, or time out.
#   * BOLT RECEIVERS (046d:c548) fail the OTHER way. On this kernel Bolt is not
#     in hid-logitech-dj's device table at all -- hid-multitouch claims it -- so
#     ltunify's driver-name test rejects it and reports "No Logitech Unifying
#     Receiver device found" at somebody looking straight at the dongle. The
#     wrapper classifies by USB product ID independently of driver so it can say
#     what is actually plugged in.
#   * "Assume that the first match is the receiver" (ltunify.c:1188) -- with two
#     receivers plugged in, which is EXACTLY the re-pair case, it silently picks
#     whichever hidraw node globbed first. The wrapper groups nodes by physical
#     USB device and makes the choice explicit through ltunify's own -d escape
#     hatch. Grouping matters on its own: a Nano receiver owns TWO hidraw nodes
#     (logi_dj_probe's -ENODEV guard for HID++-less interfaces is
#     recvr_type_dj-only), so a per-node view shows one dongle as two.
#
# UPSTREAM IS FROZEN. Last commit 2020-06-14. That is a known and accepted
# property of this pin, not an oversight: the HID++ 1.0 pairing registers it
# writes are a fixed protocol on hardware Logitech stopped changing, and the
# tool either works on a given receiver or is refused by the wrapper.

# COMMIT PIN, not the v0.3 tag, and the difference is exactly one commit.
# b68dc9af is v0.3 (872a781, 2020-06-14) plus "ltunify: fix harmless compiler
# warning", which checks fscanf()'s return value when reading bInterfaceNumber
# during Nano-receiver c534 detection. Functionally that commit changes nothing
# (iface was already initialised to -1 on the failure path) -- it is taken for
# the build log. Verified, not assumed: cross-compiling the v0.3 tree with the
# exact flags TARGET_CONFIGURE_OPTS passes here
# (-O2 -g0 -D_FORTIFY_SOURCE=1, gcc 14.4 / glibc 2.43) emits
#
#   ltunify.c:1217:49: warning: ignoring return value of 'fscanf' declared
#   with attribute 'warn_unused_result' [-Wunused-result]
#
# while the pinned commit compiles silently. Pinning the tag would therefore put
# a warning in every build of this image forever. Same posture as
# package/libchdr, which also pins a branch head over a stale tag.
#
# It is also, literally, the last thing upstream ever said: master HEAD has not
# moved since 2020-06-14T20:59:19Z. There is no "newer tag vs newer branch"
# tension to manage here of the kind a live repo would have.
LTUNIFY_VERSION = b68dc9af6db53de231d5ac71f9b6ba2ff3057a68
LTUNIFY_SITE = $(call github,Lekensteyn,ltunify,$(LTUNIFY_VERSION))

# GPL-3.0+ from the file header of ltunify.c ("either version 3 of the License,
# or (at your option) any later version") -- read, not inferred. There is NO
# LICENSE/COPYING file in the tarball (checked against the pinned archive), so
# _LICENSE_FILES names the source file that carries the notice. That is the
# standard Buildroot fallback for a project shipping no separate licence text.
#
# hidpp20.c carries no header of its own; it is #include'd into ltunify.c
# (ltunify.c:516) rather than compiled separately, so it is one translation unit
# with the file that does carry the notice, by the same author.
#
# GPLv3 is not a new licensing posture for this image -- bash (BR2_PACKAGE_BASH,
# already =y) is GPL-3.0+ too.
LTUNIFY_LICENSE = GPL-3.0+
LTUNIFY_LICENSE_FILES = ltunify.c

# ltunify.c includes <execinfo.h> unconditionally (ltunify.c:320) even though it
# never calls backtrace() -- a debugging leftover. glibc provides the header, so
# this image needs nothing extra; the `select BR2_PACKAGE_LIBEXECINFO if
# !BR2_TOOLCHAIN_USES_GLIBC` in Config.in covers a non-glibc toolchain the same
# way upstream's package/hddtemp and package/libest do.
#
# The DEPENDENCIES line below is the other half of that select and is not
# optional: a select only turns the symbol on, it does not order the builds, so
# without it Buildroot may compile ltunify before libexecinfo has installed
# execinfo.h into staging -- an intermittent "execinfo.h: No such file or
# directory" rather than an honest failure. Every in-tree user of this select
# pairs it the same way (package/hddtemp, package/libest).
#
# What is NOT added is -lexecinfo at link time, which is where this differs from
# hddtemp.mk. Verified rather than assumed: `grep backtrace *.c` over the pinned
# tree returns nothing, so only the header is ever needed, and linking the
# library would add a DT_NEEDED for symbols the binary does not reference.
#
# Both lines are inert on this image -- it is glibc, so the select never fires.
ifeq ($(BR2_PACKAGE_LIBEXECINFO),y)
LTUNIFY_DEPENDENCIES += libexecinfo
endif

# A plain Makefile with no configure step -- generic-package, and only the
# `ltunify` target.
#
# NOT `all`. That would also build read-dev-usbmon, a usbmon-capture debugging
# tool that reads /dev/usbmonX (CONFIG_USB_MON, not enabled on this image) and
# whose helper hidraw.c upstream's own README describes as "currently unusable,
# it does not process data correctly". Nothing would ever run it.
#
# TARGET_CONFIGURE_OPTS is what makes the cross-build work: the Makefile writes
# `CFLAGS ?= -g -O2 ...`, and a command-line assignment overrides a `?=`, so
# TARGET_CFLAGS wins. -lrt is already in upstream's own recipe.
#
# PACKAGE_VERSION MUST BE PASSED, and this is the one non-obvious thing in this
# file. Upstream's Makefile reads:
#
#     PACKAGE_VERSION ?= $(shell git describe --dirty 2>/dev/null | sed s/^v//)
#     ifeq (PACKAGE_VERSION, "")
#             LTUNIFY_DEFINES :=
#     else
#             LTUNIFY_DEFINES := -DPACKAGE_VERSION=\"$(PACKAGE_VERSION)\"
#     endif
#
# That ifeq compares the literal string "PACKAGE_VERSION" against "" and is
# therefore ALWAYS false, so -DPACKAGE_VERSION is always defined. Building from
# an archive tarball (no .git) leaves the shell substitution empty, so the
# define lands as -DPACKAGE_VERSION="" -- which pre-empts ltunify.c's own
# `#ifndef PACKAGE_VERSION / #define PACKAGE_VERSION "0.3"` fallback (line 37)
# and makes `ltunify --version` print an empty version string. Passing the pin
# explicitly is what keeps that output meaningful.
#
# The value is $(LTUNIFY_VERSION) itself, i.e. the full commit SHA, rather than
# a hand-written "0.3-1-gb68dc9a". A literal cannot drift out of step with the
# pin when Renovate rewrites the version line, and the SHA is the single most
# useful thing to have in a bug report anyway.
define LTUNIFY_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(TARGET_CONFIGURE_OPTS) \
		PACKAGE_VERSION="$(LTUNIFY_VERSION)" ltunify
endef

# Hand-written rather than `$(MAKE) install`, for two reasons:
#
#   1. Upstream's `install` target depends on `install-udevrule`, and this image
#      does not want that rule. It exists to hand DESKTOP SEAT USERS access to
#      the receiver's hidraw node: TAG+="uaccess" needs logind/elogind, which is
#      not installed, and the MODE="0660", GROUP="plugdev" line is commented out
#      upstream anyway. This image has exactly one account -- root, which already
#      opens the default 0600 root:root node. Shipping it would be cargo cult.
#      (Same call, same reasoning, as package/dualsensectl.)
#
#   2. That rule's device list is a hardcoded four-PID allowlist
#      (c52b/c532/c52f/c534), so it would go stale silently rather than usefully.
define LTUNIFY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ltunify $(TARGET_DIR)/usr/bin/ltunify
endef

$(eval $(generic-package))
