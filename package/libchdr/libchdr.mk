################################################################################
#
# libchdr
#
################################################################################

# MAME's CHD (Compressed Hunks of Data) read library, extracted and maintained
# standalone by rtissera. Main_MiSTer's cores support consumes it for CD-image
# formats (PSX/MegaCD/Saturn/Neo Geo CD/etc. .chd files). Buildroot 2026.02.3
# upstream has no libchdr package (checked: work/buildroot/package/libchdr does
# not exist), so this authors one. Built as a shared library against the
# SYSTEM zlib, zstd and lzma-sdk (the last a BR2_EXTERNAL sibling package)
# rather than upstream's vendored deps/ copies of all three -- upstream itself
# provides WITH_SYSTEM_ZLIB/WITH_SYSTEM_ZSTD "for distros" (its CHANGELOG.md
# 0.3.0 notes); the missing WITH_SYSTEM_LZMA third leg is added by this
# package's patch 0001, with 0002/0003 switching the sources to the system
# <LzmaDec.h> (see each patch's header for the full story).
#
# ONE DEP STAYS BUNDLED, DELIBERATELY: the header-only dr_flac decoder
# (include/dr_libs/dr_flac.h) is compiled into the library by src/
# libchdr_flac.c. No shared-lib alternative exists to unbundle to (dr_libs is
# header-only by design, no distro ships it as a .so), and libchdr_flac.c
# pokes drflac internals directly (DRFLAC_CACHE_L2_LINES_REMAINING on the
# decoder's private bitstream state, src/libchdr_flac.c:169 -- its own comment
# reads "ugh... there's no function to obtain bytes used in drflac"), so it
# could not be swapped for libFLAC either without rewriting the codec. Covered
# in LIBCHDR_LICENSE below.

# COMMIT PIN, NOT THE TAG -- the only release tag, v0.3.0, predates commit
# 23d3ddd ("cmake: fallback to pkgconfig if the zstd cmake config is
# missing"), which added cmake/Findzstd.cmake with a pkg-config fallback.
# Without it, WITH_SYSTEM_ZSTD does a bare find_package(zstd REQUIRED)
# expecting zstd's CMake config package -- which Buildroot's zstd package
# (Makefile-installed, ships only libzstd.pc, no *.cmake) does not provide,
# so configure FAILS at the tag. The pin (upstream master HEAD at pin time,
# 2026-07-17; commit date 2026-06-20) also carries the
# chd_read_header_core_file_callbacks fix (798a4f7, file size populated
# before reading the header). Version/ABI are unchanged from the tag: CMake
# project() still says 0.3.0, so this still produces libchdr.so.0.3 with
# SONAME libchdr.so.0 (verified by host-building the pinned+patched source
# at pin time).
LIBCHDR_VERSION = 04a177ee3cea055d93da2d5839d3413168837c6f
LIBCHDR_SITE = $(call github,rtissera,libchdr,$(LIBCHDR_VERSION))
# LICENSE.txt is the standard BSD 3-clause text ("Copyright Romain
# Tisserand", the three numbered conditions, the all-caps disclaimer --
# checked by reading the file, not assumed from the README). The bundled
# dr_flac (see the header comment above) is dual-licensed "Choice of public
# domain or MIT-0" per its own line 2 and the ALTERNATIVE 1 (Public Domain,
# www.unlicense.org) / ALTERNATIVE 2 (MIT No Attribution) statements at the
# end of the header -- and since it IS compiled into the shipped .so, it is
# named in LIBCHDR_LICENSE rather than silently subsumed. dr_flac offers no
# separate license file to add to LIBCHDR_LICENSE_FILES (the statements live
# at the bottom of dr_flac.h itself).
LIBCHDR_LICENSE = BSD-3-Clause, Unlicense/MIT-0 (bundled dr_flac)
LIBCHDR_LICENSE_FILES = LICENSE.txt

# Staging install: Main_MiSTer compiles against <libchdr/chd.h> and links
# -lchdr from the sysroot, so headers + .so must land in staging, not just
# the target.
LIBCHDR_INSTALL_STAGING = YES
# host-pkgconf is NOT listed: pkg-cmake.mk's inner-cmake-package appends it
# to every cmake package's dependencies unconditionally (checked,
# work/buildroot/package/pkg-cmake.mk line 175), and patch 0001's
# pkg_check_modules(lzma-sdk) probe is the only pkg-config user here.
LIBCHDR_DEPENDENCIES = zlib zstd lzma-sdk

# -DBUILD_SHARED_LIBS=ON is NOT passed here -- pkg-cmake.mk already passes
# it for every target cmake package whenever BR2_STATIC_LIBS is unset
# (checked, work/buildroot/package/pkg-cmake.mk line 120; this defconfig is
# shared-libs), and repeating infra-provided options is against upstream
# convention. INSTALL_STATIC_LIBS=OFF keeps the intermediate chdr-static
# archive (and the vendored-codec .a files it would drag along) out of
# staging -- only the shared library and headers install. The three
# WITH_SYSTEM_* switches unbundle zlib/zstd (upstream's own options) and
# lzma (our patch 0001; probes the sibling lzma-sdk package's lzma-sdk.pc).
# The shared lib links with upstream's own -Wl,--no-undefined plus a
# version script (src/link.T: "global: chd_*; local: *"), so a missing
# system dep fails loudly at link time and nothing but chd_* is exported.
LIBCHDR_CONF_OPTS = \
	-DWITH_SYSTEM_ZLIB=ON \
	-DWITH_SYSTEM_ZSTD=ON \
	-DWITH_SYSTEM_LZMA=ON \
	-DINSTALL_STATIC_LIBS=OFF

$(eval $(cmake-package))
