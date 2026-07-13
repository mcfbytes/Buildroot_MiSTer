################################################################################
#
# cabextract (host-only)
#
################################################################################

# Build-time-only host tool (P3.2, docs/decisions/0003-xone-firmware.md):
# extracts a single file out of the Microsoft driver .cab that
# package/xow-firmware sources the Xbox Wireless Dongle firmware from.
# HOST-ONLY on purpose -- nothing on the target ever runs cabextract, it is
# a build step, same role host-cpio/host-m4/etc. already play in a plain
# Buildroot tree. No Config.in, and no target-package eval below: not a
# user-selectable option, pulled in automatically via
# XOW_FIRMWARE_DEPENDENCIES = host-cabextract (same idiom as
# work/buildroot/package/autoconf/autoconf.mk's HOST_AUTOCONF_DEPENDENCIES =
# host-m4 host-libtool -- neither has a Config.in of its own either).
#
# NAMING: the package directory is "cabextract" (bare, no "host-" prefix) --
# host-autotools-package derives BOTH the plain metadata-variable prefix
# (CABEXTRACT_*, used below) AND the "host-cabextract" make-target name from
# the *directory* name (pkgname = package/pkg-utils.mk's
# $(lastword $(subst /, ,$(pkgdir)))), then prepends "host-" itself. A
# directory literally named "host-cabextract" would have produced a
# "host-host-cabextract" target instead -- caught by actually running
# `make xow-firmware` and hitting "No rule to make target 'host-cabextract'"
# before this comment was written.
#
# Same upstream author/site as Buildroot's own package/libmspack (both
# cabextract.org.uk, Stuart Caie) -- NOT linked against that package's
# libmspack, though: this release tarball bundles its own copy of mspack
# (./mspack/*.c) and builds self-contained (checked: `./configure && make`
# needs nothing beyond a C toolchain, confirmed by an out-of-tree build
# before writing this package).
CABEXTRACT_VERSION = 1.11
CABEXTRACT_SOURCE = cabextract-$(CABEXTRACT_VERSION).tar.gz
CABEXTRACT_SITE = https://www.cabextract.org.uk
CABEXTRACT_LICENSE = GPL-3.0+
CABEXTRACT_LICENSE_FILES = COPYING

$(eval $(host-autotools-package))
