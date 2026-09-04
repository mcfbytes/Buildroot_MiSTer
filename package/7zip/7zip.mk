################################################################################
#
# 7zip
#
################################################################################

# Igor Pavlov's 7-Zip, the UPSTREAM project, built as the console application
# `7zz` -- not p7zip. Two artifacts come out of one build:
#
#   1. $(TARGET_DIR)/usr/bin/7zz  -- dynamically linked, the general-purpose
#      on-device archiver (plus a `7za` compat alias; see the install cmds).
#   2. $(BINARIES_DIR)/7za        -- STATICALLY linked, shipped onto the
#      exFAT data partition as /media/fat/linux/7za. This is the one that
#      matters: the MiSTer Downloader hardcodes that path and DOWNLOADS a
#      10-year-old binary from the internet if the file is absent. See
#      ADR 0023 and docs/downloader-contract.md §4 for the whole mechanism;
#      the short version is in the INSTALL_IMAGES comment below.
#
# NOT package/p7zip (which this replaces in the defconfig): p7zip is a
# third-party Unix port, upstream-dead since 16.02 (2016) and carried on only
# by the p7zip-project fork Buildroot packages at 17.06 (2022). 7-Zip itself
# has had native Linux support since 21.01 (2021), so the port is no longer
# the only way to get 7z on Linux and there is no reason to prefer a stale
# fork of a subset. Format coverage is a superset either way.
#
# SAME UPSTREAM TARBALL AS package/lzma-sdk -- deliberately, and they are
# INDEPENDENTLY versioned. lzma-sdk compiles 8 .c files out of this same
# archive's C/ directory into liblzma-sdk.so for Main_MiSTer/libchdr; this
# package compiles the CPP/ application out of it. Two packages, one upstream
# release, so the two _VERSION values will normally track together and
# Renovate raises a PR per package. They are NOT wired to a shared variable:
# Buildroot's one-version-per-package rule keeps each package's hash file
# meaningful on its own, and nothing breaks if they transiently differ (they
# build disjoint artifacts with no shared ABI). If you bump one, bump the
# other in the same PR unless you have a reason not to. Note the LICENSE
# differs between the two for real reasons -- see the license comment below.
7ZIP_VERSION = 26.03
# 7z$(subst .,,26.02) = 7z2602-src.tar.xz -- the versioning scheme 7-zip.org
# itself uses for source drops. The GitHub ip7z/7zip release page is the
# project's own release channel (7-zip.org's download page links there); it
# publishes NO checksums (no checksum assets, none in the release body, none
# on 7-zip.org -- re-checked at pin time, 2026-07-27), hence the
# locally-computed hash in 7zip.hash and the defconfig's
# BR2_DOWNLOAD_FORCE_CHECK_HASHES=y actually guarding it.
7ZIP_SOURCE = 7z$(subst .,,$(7ZIP_VERSION))-src.tar.xz
7ZIP_SITE = https://github.com/ip7z/7zip/releases/download/$(7ZIP_VERSION)
# The archive is FLAT: Asm/ C/ CPP/ DOC/ sit at the top level with no
# version-named container directory, so the default tar --strip-components=1
# would eat C/ itself. Same value and same reason as package/lzma-sdk.
7ZIP_STRIP_COMPONENTS = 0

# License chain read out of DOC/License.txt in the pinned 26.02 tree, per its
# own per-path enumeration (CHECKED, not assumed):
#   - CPP/7zip/Compress/Rar*        LGPL-2.1+ with unRAR license restriction
#   - CPP/7zip/Compress/LzfseDecoder.cpp, C/ZstdDec.c   BSD-3-Clause
#   - C/Xxh64.c                    BSD-2-Clause
#   - everything else              LGPL-2.1+ (or public domain where a file
#                                  says so itself)
# The unRAR restriction is IN SCOPE here and is the one real difference from
# package/lzma-sdk, whose LICENSE is "Public Domain": lzma-sdk compiles only
# public-domain C/ files and never touches CPP/, so License.txt's LGPL/unRAR
# terms scope nothing it ships. This package DOES compile the Rar decoders
# (Rar1Decoder/Rar2Decoder/Rar3Decoder/Rar3Vm/Rar5Decoder/RarCodecsRegister/
# RarHandler/Rar5Handler/Rar20Crypto/Rar5Aes/RarAes all appear in the link
# line), so the restriction travels with the image. Its substance is a
# no-reverse-engineering-of-RAR clause, not a no-redistribution clause;
# upstream Buildroot ships package/p7zip under the identical license string
# without setting REDISTRIBUTE = NO, and neither does this.
7ZIP_LICENSE = LGPL-2.1+ with unRAR restriction, BSD-3-Clause, BSD-2-Clause
7ZIP_LICENSE_FILES = DOC/License.txt
7ZIP_CPE_ID_VENDOR = 7-zip
7ZIP_CPE_ID_PRODUCT = 7-zip

# `7zz` is the "Alone2" bundle -- the full console application. Its makefile
# lives in the bundle dir and includes its siblings by RELATIVE path
# (../../cmpl_gcc.mak -> CPP/7zip/cmpl_gcc.mak), so the build must run with
# that directory as cwd; hence -C plus a relative -f, exactly as upstream's
# own README instructs.
7ZIP_ALONE2_DIR = CPP/7zip/Bundles/Alone2
# Object/output subdir. C/var_gcc.mak already defaults this to b/g; passing it
# explicitly makes the install commands below immune to an upstream default
# change (which would otherwise fail as a confusing "no such file" at install
# time, long after a green build).
7ZIP_O = b/g

# 7-Zip does not use autotools/CMake -- it ships hand-written GNU makefiles
# with a documented set of override variables. Each one passed here, and why:
#
#   CC / CXX            The cross compilers. C/var_gcc.mak derives these from
#                       $(CROSS_COMPILE); overriding the results directly is
#                       simpler and matches what TARGET_CC/TARGET_CXX already
#                       resolve to (Buildroot's wrapper binaries, which inject
#                       the -march/-mfpu/-mfloat-abi tuple, plus this config's
#                       BR2_SSP_STRONG -fstack-protector-strong and
#                       BR2_RELRO_FULL -fPIE/-pie -- so those land WITHOUT
#                       being named here; do not re-add them).
#   CFLAGS_BASE2  /     The documented pre-injection slots in
#   CXXFLAGS_BASE2      C/7zip_gcc_c.mak and CPP/7zip/7zip_gcc.mak
#                       ("$(CFLAGS_BASE2) $(CFLAGS_BASE)"). Buildroot's flags
#                       land BEFORE upstream's own -O2, so on a conflict
#                       upstream wins -- which is a non-issue under this
#                       defconfig (BR2_OPTIMIZE_2=y, so both say -O2) but is
#                       worth knowing before switching to BR2_OPTIMIZE_S and
#                       expecting -Os to take effect. It would not.
#   LDFLAGS             Upstream sets this to "-DNDEBUG" (a no-op at link);
#                       preserved verbatim so overriding it adds rather than
#                       replaces. TARGET_LDFLAGS is empty under this
#                       defconfig, so this currently changes nothing, and is
#                       here so a future BR2_TARGET_LDFLAGS is not silently
#                       dropped.
#   CFLAGS_WARN_WALL    Upstream ships "-Wall -Werror -Wextra". -Werror is
#                       correct for upstream's own CI and WRONG for a
#                       distribution build: a Buildroot toolchain bump
#                       (gcc 14 -> 15) turns any newly-introduced warning
#                       into a hard failure in a package nobody touched. The
#                       two useful flags are kept and only -Werror dropped;
#                       upstream's much larger CFLAGS_WARN list
#                       (CPP/7zip/warn_gcc.mak) is left entirely alone, so
#                       warnings still print, they just no longer fail.
#   COMPL_STATIC = 1    Adds $(PROGPATH_STATIC) -- i.e. `7zzs` -- to the
#                       default goal, linked with -static from the same
#                       objects. This is upstream's own supported switch, not
#                       a hack. Both binaries are built in one pass; see
#                       INSTALL_IMAGES below for why we need the static one.
#
# NOT passed, on purpose: USE_ASM. The only ARM32 assembly in the tree is
# Asm/arm/7zCrcOpt.asm, which is MASM syntax for the Windows assembler and
# will not go through GNU as; the accelerated AES/SHA paths are aarch64/x64
# only. Plain C is simply correct on this ARMv7 Cortex-A9, not a compromise
# (same finding as package/lzma-sdk's no-assembly note).
define 7ZIP_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/$(7ZIP_ALONE2_DIR) \
		-f ../../cmpl_gcc.mak \
		O=$(7ZIP_O) \
		CC="$(TARGET_CC)" \
		CXX="$(TARGET_CXX)" \
		CFLAGS_BASE2="$(TARGET_CFLAGS)" \
		CXXFLAGS_BASE2="$(TARGET_CXXFLAGS)" \
		LDFLAGS="-DNDEBUG $(TARGET_LDFLAGS)" \
		CFLAGS_WARN_WALL="-Wall -Wextra" \
		COMPL_STATIC=1
endef

# The target gets the DYNAMIC 7zz: the rootfs already carries the glibc and
# libstdc++ it needs, so there is nothing to gain from the static one here and
# ~0.65 MiB of rootfs to lose.
#
# `7za` is a COMPAT ALIAS, not a second binary. Every MiSTer that has ever run
# an update has a /media/fat/linux/7za, so "7za" is the name a decade of
# community scripts reach for; `7zz` is the name upstream uses and what a user
# who knows modern 7-Zip will type. Both resolve to the same 26.02 binary.
# Safe to alias because 7-Zip does NOT dispatch on argv[0] -- checked, there is
# no basename/argv[0] inspection in CPP/7zip/UI/Console/Main.cpp; the
# 7zz/7za/7zr distinction in p7zip and in upstream's own bundles is which
# codecs got COMPILED IN (separate Bundles/ targets), not a runtime mode. So
# the alias is genuinely the full archiver, never a crippled one.
#
# `7zr` is aliased TOO, and for a stronger reason than 7za. An earlier revision
# of this file refused it, arguing that in real 7-Zip "7zr" names the REDUCED
# 7z-only build (Bundles/Alone7z) so pointing it at the full binary is
# misleading. That objection is real but inverted in practice, and it lost to
# one checked fact: `usr/bin/7zr` is the ONLY 7-Zip-family binary stock's rootfs
# contains (verified against work/imgroot -- no 7z, no 7za, and it is itself
# p7zip 16.02). So `7zr` is the only such name a third-party MiSTer script
# written against stock can possibly call, and dropping it would be a silent
# parity regression for a zero-byte symlink. "Misleading" here can only ever
# mean "more capable than the name promises", never less -- exactly the
# argument made for 7za just above, applied consistently.
define 7ZIP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(7ZIP_ALONE2_DIR)/$(7ZIP_O)/7zz \
		$(TARGET_DIR)/usr/bin/7zz
	ln -sf 7zz $(TARGET_DIR)/usr/bin/7za
	ln -sf 7zz $(TARGET_DIR)/usr/bin/7zr
endef

# THE POINT OF THIS PACKAGE. $(BINARIES_DIR)/7za is not a rootfs file at all
# -- it is a payload artifact, a sibling of output/images/{linux.img,
# zImage_dtb}, consumed by the two things that write the exFAT data partition:
#
#   .github/workflows/release.yml  -> release-stage/files/linux/7za, which the
#                                     Downloader's own rsync lands at
#                                     /media/fat/linux/7za on every update
#   scripts/mk-sdcard.sh           -> mister-payload/linux/7za, so a card
#                                     flashed from sdcard.img has it from
#                                     first boot and never fetches at all
#
# It is named `7za` here, already, so both consumers stay dumb copies with no
# rename step to get wrong.
#
# STATIC IS A REQUIREMENT, NOT AN OPTIMIZATION. This binary lives on the
# PERSISTENT partition (see docs: persistent state lives on /media/fat) and
# therefore OUTLIVES the rootfs that installed it. Three ways a dynamic build
# would meet a glibc it was not linked against:
#   - a u-boot.txt _vN rollback to an older linux.img of ours,
#   - a rollback all the way to a STOCK image (glibc ~2.32 vs our 2.43),
#   - a stock user running stock's Downloader after having once installed our
#     release, which is exactly when a working updater matters most.
# In every one of those, a dynamic 7za dies at exec with a GLIBC_2.xx-not-found
# and the Linux update fails at its first `7za t`. Static removes the failure
# mode entirely. (Note stock's own pinned binary IS dynamic and has gotten
# away with it only because stock's userland barely moves -- see
# scripts/verify-stock-payload.sh's sysroot comment. We do not get that luxury
# and should not want it.)
#
# Cost accepted: ~2.9 MiB on the data partition and ~1 MiB inside
# release_*.7z, versus the 465 KiB gzipped p7zip 16.02 it displaces. Bought
# with it: no network fetch during an update at all, and a decade of upstream
# fixes. Not stripped here -- upstream's own link line already passes -s.
7ZIP_INSTALL_IMAGES = YES
define 7ZIP_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(7ZIP_ALONE2_DIR)/$(7ZIP_O)/7zzs \
		$(BINARIES_DIR)/7za
endef

$(eval $(generic-package))
