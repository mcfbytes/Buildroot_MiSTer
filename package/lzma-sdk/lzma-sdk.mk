################################################################################
#
# lzma-sdk
#
################################################################################

# Igor Pavlov's LZMA SDK (the reference LZMA implementation shipped inside
# the 7-Zip source tree), compiled as a target SHARED library, liblzma-sdk.
# Consumers: Main_MiSTer (which vendors this exact C code as lib/lzma/) and
# libchdr (whose CHD v5 LZMA codec is written against this SDK's API). This
# is NOT xz-utils' liblzma.so.5 -- entirely different API (LzmaDec_*/
# LzmaEnc_*/LzmaCompress vs lzma_stream_*); xz is packaged separately by
# upstream Buildroot as package/xz.
#
# NAME COLLISION TRAP -- this package MUST be "lzma-sdk", NOT "lzma".
# Upstream Buildroot 2026.05.1 ships package/lzma (checked: it is host-ONLY
# lzma-utils 4.32.7, $(eval $(host-autotools-package)) with no target
# variant), which squats the unprefixed LZMA_ Make namespace. pkg-generic's
# host-package inheritance derives HOST_LZMA_SOURCE / HOST_LZMA_SITE from
# the unprefixed LZMA_SOURCE / LZMA_SITE with DEFERRED (=) assignments, so a
# same-named external target package would silently clobber them -- while
# HOST_LZMA_DL_VERSION is assigned IMMEDIATELY (:=) and stays 4.32.7. The
# result is a corrupt hybrid (host-lzma trying to download OUR tarball under
# lzma-utils' version bookkeeping), not a clean "duplicate package" error.
# The Kconfig side never warns either: BR2_PACKAGE_LZMA does not exist
# upstream (host packages have no prompt), so only the Make namespace
# collides -- silently. Precedent for suffixing our way out of an upstream
# squat: package/rtl8188eu-aircrack-ng (see its Config.in).
LZMA_SDK_VERSION = 26.02
# 7z$(subst .,,26.02) = 7z2602-src.tar.xz -- the same versioning scheme
# 7-zip.org itself uses for source drops. The GitHub ip7z/7zip release page
# is the project's own release channel (7-zip.org's download page links
# there); it publishes NO checksums (no checksum assets, none in the release
# body, none on 7-zip.org -- checked at pin time, 2026-07-17), hence the
# locally-computed hash in lzma-sdk.hash and the defconfig's
# BR2_DOWNLOAD_FORCE_CHECK_HASHES=y actually guarding it.
LZMA_SDK_SOURCE = 7z$(subst .,,$(LZMA_SDK_VERSION))-src.tar.xz
LZMA_SDK_SITE = \
	https://github.com/ip7z/7zip/releases/download/$(LZMA_SDK_VERSION)
# The archive is FLAT: Asm/ C/ CPP/ DOC/ sit at the top level with no
# version-named container directory, so the default tar --strip-components=1
# would eat C/ itself. Precedent: upstream package/lzma-alone sets the same
# for its equally flat lzma922.tar.bz2 from the same author.
LZMA_SDK_STRIP_COMPONENTS = 0
# License chain, verified per-file at pin time (2026-07-17), CHECKED, NOT
# ASSUMED: DOC/readme.txt line 43 states "LZMA SDK is written and placed in
# the public domain by Igor Pavlov."; every .c this package compiles and
# every .h it installs carries "Igor Pavlov : Public domain" in its opening
# comment (all 21 files checked individually against the extracted 26.02
# tree). DOC/License.txt's LGPL and unRAR-restriction terms apply only to
# CPP/ code (the 7-Zip application proper, Rar codecs) that this package
# never compiles or ships; it is listed in LICENSE_FILES anyway so the legal
# text that scopes those exclusions travels with the image's legal-info.
# Precedent: upstream package/lzma-alone uses "Public Domain" for this same
# SDK's C code.
LZMA_SDK_LICENSE = Public Domain
LZMA_SDK_LICENSE_FILES = DOC/License.txt DOC/readme.txt
LZMA_SDK_INSTALL_STAGING = YES

# The SDK ships no library build system for Unix -- its makefiles build the
# 7-Zip executables out of CPP/. So this is a generic-package with a single
# direct $(TARGET_CC) invocation (precedents: package/mongoose compiles with
# direct $(TARGET_CC); package/sunxi-cedarx links -shared -Wl,-soname the
# same way). The 8 .c files are exactly Main_MiSTer's vendored lib/lzma set.
#
# -DZ7_ST is CRITICAL, empirically proven during recon: -D_7ZIP_ST alone is
# NOT enough on SDK >= 23.01. The _7ZIP_ST -> Z7_ST compat shim at the
# bottom of C/7zTypes.h is commented out in 26.02 (lines 593-599 of the
# extracted file, wrapped in /* */), so without -DZ7_ST, LzmaEnc.c includes
# LzFindMt.h and the link dies with undefined MatchFinderMt_* references.
# -D_7ZIP_ST is kept belt-and-braces for any straggler that still checks the
# old spelling. Under Z7_ST no Threads.c is needed (single-threaded match
# finder only -- fine: Main_MiSTer's vendored copy builds the same way).
# No assembly: the SDK's LzmaDecOpt fast path is aarch64/x64-only, so plain
# C is simply correct on this ARM32 Cortex-A9, not a compromise.
#
# -Wl,--no-undefined turns any silently-missing symbol into a hard link
# error at build time instead of a dlopen/exec-time surprise on the device.
#
# SONAME POLICY -- full version (liblzma-sdk.so.26.02), deliberately NOT a
# stable .so.1: upstream gives no ABI guarantees between SDK releases, and
# the API is caller-allocated-struct based (CLzmaDec etc. are embedded by
# value in consumer structs), so a struct-layout change recompiles into
# silent memory corruption if an old binary meets a new library. Making the
# full version the SONAME turns every SDK bump into a LOUD ABI event: a
# consumer built against 26.02 refuses to start against 26.03 with a clean
# linker error. That matters specifically here because the Main_MiSTer
# binary lives on the persistent /media/fat partition and SURVIVES rootfs
# reflashes (see docs: persistent state lives on /media/fat) -- a stale
# binary meeting a freshly-flashed rootfs is the expected failure mode, not
# a theoretical one.
define LZMA_SDK_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -fPIC -DZ7_ST -D_7ZIP_ST \
		$(@D)/C/Alloc.c $(@D)/C/CpuArch.c $(@D)/C/Delta.c \
		$(@D)/C/LzFind.c $(@D)/C/LzmaDec.c $(@D)/C/LzmaEnc.c \
		$(@D)/C/LzmaLib.c $(@D)/C/Sort.c \
		-shared -Wl,-soname,liblzma-sdk.so.$(LZMA_SDK_VERSION) \
		-Wl,--no-undefined $(TARGET_LDFLAGS) \
		-o $(@D)/liblzma-sdk.so.$(LZMA_SDK_VERSION)
endef

# Headers go in a NAMESPACED /usr/include/lzma-sdk/ dir -- names like
# 7zTypes.h and Sort.h are far too generic to drop into /usr/include
# directly. Safe because the SDK's intra-header includes are same-directory
# quoted ("7zTypes.h", "Compiler.h" -- the only two, checked across all 13
# headers), so they resolve inside the namespaced dir with no path edits.
# The 13-header set is Main_MiSTer's vendored lib/lzma set: Bra.h and
# LzHash.h are not strictly needed to CALL the library but are kept for
# parity with that vendored tree so Main_MiSTer's includes port over 1:1.
# The installed headers are Z7_ST-INSENSITIVE (verified: the define only
# changes what the SDK's own .c files compile, not any installed struct
# layout or prototype), so the .pc needs no Cflags defines.
#
# The unversioned liblzma-sdk.so dev symlink is STAGING-ONLY -- a choice
# these hand-written install commands make deliberately (the manual's rule
# for INSTALL_TARGET_CMDS: install only what the target needs at runtime).
# The target gets just the versioned file, whose filename IS the SONAME the
# runtime linker looks up. Note this is stricter than Buildroot's
# infra-installed packages (cmake/autotools targets keep their unversioned
# .so symlinks on the target -- target-finalize prunes headers/.pc/.a, not
# symlinks); nothing links at runtime through the unversioned name, so
# omitting it here loses nothing.
#
# lzma-sdk.pc is shipped in this package dir and installed with the Version
# line substituted from LZMA_SDK_VERSION, so the .mk stays the single source
# of truth for the version (pc-in-package-dir precedents: package/libmad
# ships mad.pc, package/stb ships stb.pc).
define LZMA_SDK_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/liblzma-sdk.so.$(LZMA_SDK_VERSION) \
		$(STAGING_DIR)/usr/lib/liblzma-sdk.so.$(LZMA_SDK_VERSION)
	ln -sf liblzma-sdk.so.$(LZMA_SDK_VERSION) \
		$(STAGING_DIR)/usr/lib/liblzma-sdk.so
	mkdir -p $(STAGING_DIR)/usr/include/lzma-sdk
	$(INSTALL) -m 0644 \
		$(@D)/C/7zTypes.h $(@D)/C/Alloc.h $(@D)/C/Bra.h \
		$(@D)/C/Compiler.h $(@D)/C/CpuArch.h $(@D)/C/Delta.h \
		$(@D)/C/LzFind.h $(@D)/C/LzHash.h $(@D)/C/LzmaDec.h \
		$(@D)/C/LzmaEnc.h $(@D)/C/LzmaLib.h $(@D)/C/Precomp.h \
		$(@D)/C/Sort.h \
		$(STAGING_DIR)/usr/include/lzma-sdk
	$(INSTALL) -D -m 0644 $(LZMA_SDK_PKGDIR)/lzma-sdk.pc \
		$(STAGING_DIR)/usr/lib/pkgconfig/lzma-sdk.pc
	$(SED) 's/@LZMA_SDK_VERSION@/$(LZMA_SDK_VERSION)/' \
		$(STAGING_DIR)/usr/lib/pkgconfig/lzma-sdk.pc
endef

define LZMA_SDK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/liblzma-sdk.so.$(LZMA_SDK_VERSION) \
		$(TARGET_DIR)/usr/lib/liblzma-sdk.so.$(LZMA_SDK_VERSION)
endef

$(eval $(generic-package))
