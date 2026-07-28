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

# DOWNLOAD SITE: Fedora's lookaside cache, deliberately NOT the upstream
# project site (https://www.cabextract.org.uk) this tarball originates from.
#
# WHY: www.cabextract.org.uk is a small self-hosted site that is repeatedly
# unreachable from GitHub-hosted runners -- `make all` died there in CI runs
# 30175094935 (2026-07-25) and 30312448080 (2026-07-27), both times with
# "Connection timed out" on EVERY resolved IPv4 (the A records rotate between
# runs, so this is the host/route refusing us, not one dead server). It
# resolves and serves fine from other networks, which is exactly what makes it
# a landmine: it fails only in CI, ~2.5h into a build.
#
# It is INTERMITTENT, not a standing block -- run 30183462152 (2026-07-26, in
# between the two failures) fetched it from upstream in 0.6s. So "I just tried
# the old URL and it worked" is not evidence this can be reverted; it is the
# same coin landing the other way. Roughly two failures in three runs over
# 2026-07-25..27 is the actual observed rate.
#
# WHY THAT BREAKS THE BUILD OUTRIGHT rather than falling back: Buildroot tries
# BR2_PRIMARY_SITE, then _SITE, then BR2_BACKUP_SITE (sources.buildroot.net) --
# see work/buildroot/package/pkg-download.mk's DOWNLOAD_URIS. The backup mirror
# only carries tarballs for packages that exist in UPSTREAM Buildroot.
# cabextract is a package of OURS (upstream has only libmspack, same author,
# same site), so sources.buildroot.net/cabextract/ is a guaranteed 404 -- it
# cannot ever cover this package, and the fetch had exactly one real source.
# Confirmed in both failure logs: upstream timeout, then two 404s, then Error 1.
#
# That no-backup property is true of every package/ directory of ours, not just
# this one -- but the rest are hosted somewhere that can absorb it (GitHub for
# the driver/firmware packages, Microsoft's Windows Update CDN for
# xow-firmware). cabextract was the only one whose single source was a small
# self-hosted origin, which is why it is the only one that needed moving.
#
# WHY FEDORA'S LOOKASIDE: it is content-addressed and never pruned (unlike a
# Debian pool entry, which disappears once no suite references the version),
# it is CDN-fronted, and it keeps the ORIGINAL upstream filename -- so
# CABEXTRACT_SOURCE and the sha256 in cabextract.hash are unchanged by this
# move. Verified byte-identical to the upstream tarball: both sides hash to
# the b5546db1... sha256 already pinned in cabextract.hash, downloaded from
# each host and compared before this switch was made.
#
# Serving the source from a mirror does not weaken provenance: integrity here
# rests on the hash pin, not on the transport or the hostname. A mirror handing
# us different bytes fails the build at check-hash. (Same reasoning already
# written down for the plain-HTTP Microsoft .cab fetch in
# package/xow-firmware/xow-firmware.mk.)
#
# BUMPING THE VERSION: the lookaside path embeds the tarball's SHA512, so
# CABEXTRACT_SHA512 below must be updated IN LOCKSTEP with CABEXTRACT_VERSION
# or the download 404s. It is deliberately also listed in cabextract.hash, so
# Buildroot re-verifies it after download and a half-done bump fails closed
# instead of silently fetching the old release. Fedora publishes the value at
# https://src.fedoraproject.org/rpms/cabextract/raw/rawhide/f/sources.
# This pin is manual by design (docs/renovate.md) -- Renovate does not track it.
CABEXTRACT_SHA512 = 416bdc5a889c3986b2a5d6ecb8526a69f2d85c34f4856da43951271ff4f31013e4197c56ea5f6b05061b511b980d5a65cb34b9b859d3013c1dbcbb89d43114f9
CABEXTRACT_SITE = https://src.fedoraproject.org/repo/pkgs/cabextract/$(CABEXTRACT_SOURCE)/sha512/$(CABEXTRACT_SHA512)

CABEXTRACT_LICENSE = GPL-3.0+
CABEXTRACT_LICENSE_FILES = COPYING

$(eval $(host-autotools-package))
