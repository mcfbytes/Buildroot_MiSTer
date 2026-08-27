################################################################################
#
# libchdr
#
################################################################################

# MAME's CHD (Compressed Hunks of Data) read library, extracted and maintained
# standalone by rtissera. Main_MiSTer's cores support consumes it for CD-image
# formats (PSX/MegaCD/Saturn/Neo Geo CD/etc. .chd files). Buildroot 2026.05.1
# upstream has no libchdr package (checked: work/buildroot/package/libchdr does
# not exist), so this authors one. Built as a shared library against the
# SYSTEM zlib, zstd and lzma-sdk (the last a BR2_EXTERNAL sibling package)
# rather than upstream's vendored deps/ copies of all three -- upstream itself
# provides WITH_SYSTEM_ZLIB/WITH_SYSTEM_ZSTD "for distros" (its CHANGELOG.md
# 0.3.0 notes); the missing WITH_SYSTEM_LZMA third leg is added by this
# package's patch 0001, with 0002/0003 switching the sources to the system
# <LzmaDec.h> (see each patch's header for the full story).
#
# FORMER PATCH 0004 (codec_lzma inverted dictionary clamp) WAS DROPPED
# 2026-08-24, exactly as its own instruction said to ("Drop 0004 when
# upstream carries the fix"): upstream fixed the inverted MIN/MAX in
# lzma_compute_aligned_dictionary_size()'s reduceSize clamp in commit
# fa364205 ("Fix LZMA dict-size bug...", merged via upstream PR #169), which
# this pin carries. Upstream's version spells the clamp
# MIN(dictSize, MAX(reduceSize, kReduceMin)) with a comment memorializing
# the old bug, and switched the assumed encoder level 9 -> 6 (matching
# MAME's chdman) in the same commit -- invisible with a correct clamp, as
# the dropped patch's own header predicted. The bug's full story (64 MiB
# dictionary where 24,576 bytes is correct, ~128 MB of unswappable RAM for
# an mlockall() consumer with two handles) lives in that patch's header;
# recover it from git history at this file's 2026-08-24 change if it is
# ever needed again.
#
# PATCH 0005 is a performance change, not a correctness one. crc16 is
# byte-at-a-time and runs on EVERY hunk read (VERIFY_BLOCK_CRC defaults to 1),
# which for a CD image is a 19,584-byte pass per hunk on top of the codec.
# Slicing-by-4 folds four bytes per iteration from three derived tables; same
# polynomial, same result, 1.5 kB more .rodata, plain C so every target gains.
# Measured on the DE10-Nano: 299.6 -> 127.0 us per hunk (2.36x), and end to end
# through chd_read() the audio hunks of a Sonic CD .chd go p50 2,212 -> 1,894 us
# and p90 2,698 -> 2,176 us. Verified byte-exact: all 31,984 hunks decode with 0
# failures and an unchanged FNV-1a over every decoded byte. Rebased 2026-08-24
# onto this pin's crc16_update() split (upstream's CHDR_LOWRAM_MAP work made
# the CRC continuable; the slicing loop is initial-value-agnostic so it drops
# in unchanged -- see the patch's rebase note). Drop 0005 when upstream
# carries it. The gap in the numbering is deliberate, not an error: 0004 was
# dropped as upstreamed (above) and renaming this file would orphan its
# history and every reference to it.
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
# so configure FAILS at the tag. The pin (upstream master HEAD at bump time;
# Renovate PR #115, 2026-08-24, previously 6cde534 of 2026-07-17) carries
# everything the old pin did (798a4f7's chd_read_header_core_file_callbacks
# fix included) plus, notably: the dictionary-clamp fix that used to be this
# package's patch 0004 (see above), a vendored LZMA SDK bump 25.01 -> 26.02
# -- now the SAME version as the system lzma-sdk package this build links
# instead of it -- a vendored miniz bump (also unused here; system zlib),
# and new CHDR_WANT_TESTS / CHDR_LOWRAM_MAP options, both left at their
# defaults (tests build a non-installed benchmark, exactly what the old pin
# built unconditionally; LOWRAM_MAP=OFF is the old pin's behavior).
# Version/ABI are unchanged from the tag: CMake
# project() still says 0.3.0, so this still produces libchdr.so.0.3 with
# SONAME libchdr.so.0 (re-verified at the 2026-08-24 bump by cross-building
# the pinned+patched source and reading the .so's SONAME).
LIBCHDR_VERSION = 970a0ce060c0aa1012b1eebba1433c9a9e8ac8b9
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
