################################################################################
#
# rcheevos
#
################################################################################

# RetroAchievements' own client library: achievement/leaderboard evaluation
# against emulated memory (rcheevos), the RetroAchievements web API request
# and response marshalling (rapi), game identification hashing (rhash), and
# rc_client, the high-level state machine upstream recommends integrating
# against. Built here as a target SHARED library, librcheevos.
#
# Upstream Buildroot has NO rcheevos package -- checked against the ACTUAL
# pinned tree (2026.08; Makefile's BUILDROOT_VERSION and work/buildroot's own
# BR2_VERSION), whose package/ has no rcheevos entry and no BR2_PACKAGE_
# RCHEEVOS symbol, so this authors one. No RCHEEVOS_ Make namespace collision
# either.
#
# NO CONSUMER SHIPS TODAY, and that is not an oversight worth hiding: neither
# Main_MiSTer nor this tree references rcheevos yet (git grep -i rcheevos over
# both is empty). So unlike package/libchdr and package/lzma-sdk -- the other
# two members of the "Main_MiSTer shared libraries" menu, which exist to
# REPLACE code Main already vendors -- this package adds a NEW capability
# rather than unvendoring an existing one. It is enabled in the defconfig
# anyway (273 KiB as shipped -- 279,580 bytes stripped in rootfs.tar; the
# 330 KiB staging copy is the unstripped one) so the
# .so and its headers are simply present for a consumer to link, the same way
# a distro ships a library ahead of its dependents.

# TAG PIN, and the leading "v" is kept IN the version string rather than
# reconstructed as "v$(RCHEEVOS_VERSION)" in the SITE line. Same reason as
# package/dualsensectl and package/munt: scripts/hash-sync-github-packages.sh's
# generic loop takes the literal RHS of the first *_VERSION line and uses it
# BOTH as the archive ref and as the "<pkgdir>-<version>.tar.gz" filename it
# rewrites in the .hash. Splitting the "v" off would make it fetch
# .../archive/12.5.0.tar.gz -- a 404, there is no bare "12.5.0" ref -- and
# write a filename Buildroot never asks for.
#
# A TAG, not a branch-head commit (the shape package/libchdr needs): upstream
# tags every release, and at v12.5.0 (2026-09-13) the tag, origin/master and
# origin/develop are all the same commit, 1433173220a7eaede6a9ed7a18e94117be
# 1821e0. Upstream's own README says to integrate against master, "which
# corresponds to the last official release", not develop.
RCHEEVOS_VERSION = v12.5.0
RCHEEVOS_SITE = $(call github,RetroAchievements,rcheevos,$(RCHEEVOS_VERSION))

# The bare version, for the SONAME, the .pc Version field and the installed
# filename -- none of which want a "v". Derived from RCHEEVOS_VERSION rather
# than written out a second time, so a Renovate bump that rewrites the pin
# above cannot leave a stale literal behind.
RCHEEVOS_SOVERSION = $(patsubst v%,%,$(RCHEEVOS_VERSION))

# LICENSE is the standard MIT text ("Copyright (c) 2018 RetroAchievements.org",
# the permission grant, the "above copyright notice" condition, the all-caps
# disclaimer) -- checked by reading the file, not inferred from the README.
#
# BUT MIT ALONE IS WRONG, and an earlier revision of this file said it. There
# is no deps/ or third_party/ directory, so the tree LOOKS like it is all
# upstream's own code, and it very nearly is -- but two of the files this
# package compiles into the shipped .so are vendored third-party
# implementations carrying their own grants, both found by reading their
# headers rather than by trusting the layout:
#
#   src/rhash/md5.c + md5.h  L. Peter Deutsch / Aladdin Enterprises, 1999-2002.
#                            The notice is the ZLIB LICENSE word for word (the
#                            three numbered restrictions: origin must not be
#                            misrepresented, altered versions plainly marked,
#                            notice may not be removed). Upstream Buildroot
#                            spells this exact file's licence "Zlib (md5)" in
#                            package/rtty -- same lpd md5, same call.
#   src/rhash/aes.c + aes.h  kokke/tiny-AES-c at f06ac37, "with unused code
#                            excised", released under the Unlicense.
#
# Both are genuinely SHIPPED, not merely present: md5 is called from 12 files
# across rhash, rapi and the runtime, and aes from hash_encrypted.c. So they
# are named here rather than silently subsumed under the project's MIT --
# exactly the call package/libchdr makes for its bundled dr_flac.
#
# LICENSE_FILES LISTS THE TWO HEADERS, NOT THE TWO .c FILES, on purpose. The
# full grant appears in both members of each pair, so either would serve as
# the legal text; the headers are simply the more stable half, and these are
# hash-checked at every build. Measured over upstream's whole history:
# md5.h has ONE commit (2020-01-04) and aes.h ONE (2024-01-16), against two
# and one for the .c files. This is the package/lzma-sdk reasoning applied to
# a lower-churn file: if the operative grant is not in LICENSE_FILES, then
# `make legal-info` emits a LICENSE claiming MIT while the image carries
# zlib- and Unlicense-covered object code whose grants travel nowhere. That
# these hashes will also trip on an unrelated upstream edit is the cost of
# the tripwire working at all -- and at one commit each in eight years, it is
# a cost this package is unlikely to ever pay.
RCHEEVOS_LICENSE = MIT, Zlib (md5), Unlicense (tiny-AES-c)
RCHEEVOS_LICENSE_FILES = LICENSE src/rhash/md5.h src/rhash/aes.h

# Staging install: a consumer compiles against <rc_client.h> et al. and links
# -lrcheevos from the sysroot, so headers + .so must land in staging, not just
# the target.
RCHEEVOS_INSTALL_STAGING = YES

# NO DEPENDENCIES, deliberately stated rather than left blank. Verified by
# collecting every system #include across src/ and include/: the only ones
# that survive the platform #ifdefs on this target are libc headers plus
# <math.h> and <pthread.h>. In particular there is NO zlib (rhash's
# hash_zip.c walks the zip central directory, it never inflates), NO openssl
# or nettle (md5 and aes are compiled in from src/rhash/), and NO Lua --
# upstream removed the Lua evaluator entirely; the "unused_L" parameters
# still in rc_evaluate_trigger() and friends are vestigial ABI, not a
# dependency. The remaining non-libc includes (<libretro.h>, <ogcsys.h>,
# <3ds/synchronization.h>, <windows.h>) belong to platforms this build is
# not, or to the one source file excluded below.
#
# pthread is NOT optional on Linux: rc_compat.h's platform ladder falls
# through to the plain-POSIX #else branch (#include <pthread.h>, typedef
# pthread_mutex_t rc_mutex_t), so rc_mutex_* is always the pthread
# implementation here. Hence the Config.in "depends on
# BR2_TOOLCHAIN_HAS_THREADS" and the -pthread below.

# The SDK-shaped problem again (see package/lzma-sdk): upstream ships NO
# build system this package can drive. The tree has no CMakeLists.txt and no
# top-level Makefile -- only test/Makefile, which builds the MinGW/x86 unit
# test binary and hard-errors on any ARCH it cannot detect, and Package.swift,
# which is for SwiftPM consumers. So this is a generic-package with a single
# direct $(TARGET_CC) invocation, exactly like package/lzma-sdk (further
# precedents: package/mongoose compiles with direct $(TARGET_CC);
# package/sunxi-cedarx links -shared -Wl,-soname the same way).
#
# THE SOURCE LIST IS A WILDCARD MINUS THREE FILES, not a hand-written
# enumeration, so an upstream release that adds a .c to one of the four
# directories below is picked up by the next Renovate bump instead of being
# silently dropped. If such a file ever needs a define or a header this build
# does not pass, -Wl,--no-undefined below turns that into a LOUD build failure
# on the bump PR -- which is the intended outcome, not a regression.
#
# THE LIMIT OF THAT, stated rather than left to be discovered: the four
# patterns are not recursive, so a brand-new SUBDIRECTORY (an upstream
# "src/rnet/", say) would be skipped, and silently unless something already
# compiled references it. $(wildcard) was still preferred over a recursive
# $(shell find ...) because find's output order is filesystem-dependent while
# $(wildcard) globs sorted -- and link order feeds straight into
# reproducibility.yml. Upstream's four-directory layout has been stable for
# the whole 10.x-12.x range this pin has lived in; if that changes, add the
# pattern here.
#
# The three exclusions, each checked in the v12.5.0 tree rather than copied
# from Package.swift's exclude list:
#
#   rc_libretro.c             #include <libretro.h>, which only the libretro
#                             frontends provide (upstream's own test/ dir
#                             ships a private copy to compile it). It is
#                             frontend glue for RetroArch/RALibretro -- core
#                             option parsing, memory-map validation -- with
#                             nothing a MiSTer consumer would call.
#   rc_client_external.c      Entire body is inside #ifdef RC_CLIENT_SUPPORTS_
#                             EXTERNAL; without that define the file compiles
#                             to an empty translation unit. That define opts
#                             into the versioned rc_client_external ABI used
#                             to talk to a SEPARATE rcheevos implementation
#                             (see src/rc_client_external_versions.h), which
#                             is the opposite of what shipping this .so does.
#   rc_client_raintegration.c Entire body is inside #ifdef RC_CLIENT_SUPPORTS_
#                             RAINTEGRATION (the #endif is the last line of
#                             the file); RAIntegration is the Windows-only
#                             achievement-development DLL, and its public
#                             header #undefs the feature outright on
#                             !defined(_WIN32).
#
# The matching header, rc_client_raintegration.h, IS still installed below:
# it self-disables on non-Windows at line 4, leaving only type definitions and
# no function declarations, so it cannot promise an entry point this .so does
# not carry.
RCHEEVOS_SKIP_SRCS = \
	rc_libretro.c \
	rc_client_external.c \
	rc_client_raintegration.c

# -DRC_SHARED + -fvisibility=hidden IS THE POINT OF THIS PACKAGE, and the two
# must be passed together. include/rc_export.h defines RC_EXPORT as
# __attribute__((visibility("default"))) under RC_SHARED precisely so a shared
# build can hide everything else; passing RC_SHARED without -fvisibility=hidden
# marks the public API default in a build where everything is already default,
# i.e. does nothing. Measured on this toolchain at v12.5.0, with patch 0001
# applied: 264 exported symbols with the pair, 477 without. (255 with the
# pair but without patch 0001 -- the nine it restores are exactly the
# difference.)
#
# The 213 symbols that difference suppresses are not cosmetic. Among them are
# md5_init, md5_append and md5_finish -- the RSA-derived md5 API whose names
# Main_MiSTer's own vendored lib/md5 also defines -- plus AES_init_ctx,
# AES_CTR_xcrypt_buffer and four more AES_* entry points, and a global
# literally named "g_host". ELF symbol interposition is first-definition-wins
# across the whole link, so exporting those from a library loaded into the
# same process as its own md5 implementation is a silent wrong-function bind,
# not a link error. This is the same property package/libchdr gets from
# upstream's version script (src/link.T, "global: chd_*; local: *") and which
# its Config.in calls out; rcheevos has no version script, so visibility is
# how it is obtained here.
#
# Patch 0001 is what makes the pair safe to use: rc_util.h is the only public
# header upstream left un-annotated, so without it the nine rc_buffer_*/
# rc_djb2/rc_format_md5 entry points it declares would be hidden and the
# installed headers would promise an API the .so does not export. See that
# patch's own header; it is written to be upstreamable and should be dropped
# if upstream takes it.
#
# -DRC_CLIENT_SUPPORTS_HASH enables rhash inside rc_client -- the
# rc_client_begin_identify_and_load_game() path, i.e. "given a file, work out
# which game this is". It GATES PUBLIC HEADER DECLARATIONS, not just
# implementation (include/rc_client.h lines 265 and 333), so it must also be
# in the .pc's Cflags or a consumer's rc_client.h would hide functions the .so
# exports. It is in both; rcheevos.pc carries it deliberately.
#
# _LARGEFILE64_SOURCE IS REQUIRED HERE BUT IS DELIBERATELY NOT PASSED. It
# selects the fseeko64/ftello64 branch of rhash's filereader
# (src/rhash/hash.c:187,198); the #else branch is plain fseek/ftell, whose
# long offset is 32 bits on this ARM target and would cap disc images at
# 2 GiB. Buildroot already supplies it -- package/Makefile.in line 202 adds
# "-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64" to
# TARGET_CPPFLAGS unconditionally (no BR2_ guard), and TARGET_CFLAGS begins
# with TARGET_CPPFLAGS -- so repeating it would be exactly the
# infra-provided-option duplication package/libchdr's .mk refuses for
# -DBUILD_SHARED_LIBS. Verified effective rather than assumed, twice: the
# defines appear on the compile line above, and the built .so imports
# fseeko64@GLIBC_2.4 / ftello64@GLIBC_2.4. It is ABI-neutral for consumers
# (no off_t appears in any installed header), so unlike
# RC_CLIENT_SUPPORTS_HASH it also has no business in the .pc.
#
# -pthread is belt-and-braces. On this glibc it is a no-op for linking --
# 2.34 merged libpthread into libc, and the .so's pthread_mutex* imports
# resolve from libc alone -- but it is the portable spelling and costs
# nothing. -lm is NOT optional: rc_typed_value_modulus() calls fmod(), and
# -Wl,--no-undefined caught its absence as a hard link error while this
# package was being written, which is exactly what that flag is for.
#
# SONAME POLICY -- THE FULL VERSION (librcheevos.so.12.5.0), matching
# package/lzma-sdk's deliberate loud-ABI-event policy, and here it is backed
# by upstream's own history rather than by analogy. rcheevos publishes no ABI
# guarantee, and its public headers are full of caller-allocated structs
# (rc_runtime_t is declared complete in rc_runtime.h and initialised in place
# by rc_runtime_init(); rc_api_*_response_t likewise). Three separate PATCH
# releases changed those layouts:
#
#   v10.7.1  added "char owns_self;" to the public rc_runtime_t -- a field
#            still present at v12.5.0 as uint8_t owns_self.
#   v10.3.3  inserted "const char* display_name;" into the MIDDLE of
#            rc_api_login_response_t, shifting every field after it.
#   v6.0.1   redefined RC_ALIGNMENT from 8 to sizeof(void*), which on a
#            32-bit target like this one changes padding library-wide.
#
# (Minor releases do it too -- v12.4.0 added avatar_last_updated to
# rc_client_user_t -- so a major.minor SONAME would not have caught the three
# above either. Derived by diffing include/ across all 55 tags, not sampled.)
#
# A stale consumer meeting a changed layout is memory corruption, not an
# error, and on this image that is the EXPECTED failure mode rather than a
# theoretical one: the Main_MiSTer binary lives on the persistent /media/fat
# partition and SURVIVES rootfs reflashes, so linux.img and the binary that
# links this library are routinely out of sync. Making the full version the
# SONAME turns every bump into a clean refuse-to-load. The cost is honest and
# accepted: a pure-bugfix patch release also forces a consumer rebuild.
define RCHEEVOS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -fPIC -fvisibility=hidden \
		-DRC_SHARED -DRC_CLIENT_SUPPORTS_HASH \
		-I$(@D)/include -I$(@D)/src \
		$(filter-out $(addprefix $(@D)/src/,$(RCHEEVOS_SKIP_SRCS)), \
			$(wildcard $(@D)/src/*.c $(@D)/src/rcheevos/*.c \
				$(@D)/src/rapi/*.c $(@D)/src/rhash/*.c)) \
		-shared -Wl,-soname,librcheevos.so.$(RCHEEVOS_SOVERSION) \
		-Wl,--no-undefined $(TARGET_LDFLAGS) -pthread -lm \
		-o $(@D)/librcheevos.so.$(RCHEEVOS_SOVERSION)
endef

# Headers go in a NAMESPACED /usr/include/rcheevos/ dir. rc_*.h is a
# distinctive enough prefix that flat /usr/include would probably survive, but
# rc_hash.h, rc_error.h and rc_util.h are exactly the names another project
# would also pick, and both existing members of this menu already namespace
# (include/libchdr/, include/lzma-sdk/). Safe because every intra-header
# include is same-directory quoted ("rc_export.h", "rc_runtime.h", ... --
# checked across all 15 installed headers), so they resolve inside the
# namespaced dir with no path edits. rcheevos.pc's Cflags points -I at the
# subdirectory itself, so a consumer writes #include <rc_client.h> exactly as
# upstream's wiki does; libchdr.pc does the same.
#
# INSTALLED WITH A WILDCARD, for the same reason the source list is one: a
# release that adds a public header should not need this line edited.
# module.modulemap is excluded by the *.h glob rather than by name -- it is
# SwiftPM metadata pointing at include/rcheevos.h and means nothing to a C
# consumer.
#
# src/rc_version.h IS INSTALLED TOO, named explicitly because it is the one
# public header upstream did not put in include/. It declares rc_version()
# and rc_version_string() -- both RC_EXPORT-annotated, both compiled in from
# src/rc_version.c, and so both genuinely exported by this .so. Leaving the
# header behind would export two entry points no consumer could declare;
# caught exactly that way, by a consumer smoke test failing with "implicit
# declaration of function 'rc_version_string'". It is safe to install: it is
# self-contained (#include "rc_export.h" + <stdint.h>, both resolving inside
# the namespaced dir) and its RCHEEVOS_VERSION_* macros are what a consumer
# needs for a compile-time version check -- which matters more here than
# usual, given the full-version SONAME policy above.
#
# It is the ONLY such header: src/ carries exactly two RC_EXPORT-annotated
# headers (checked mechanically, not sampled), and the other is
# src/rc_libretro.h, whose implementation this package deliberately does not
# compile -- so installing that one WOULD promise entry points the .so lacks.
# Not installed, correctly.
#
# The unversioned librcheevos.so dev symlink is STAGING-ONLY -- the target
# gets just the versioned file, whose filename IS the SONAME the runtime
# linker looks up. Same deliberate choice, and same note, as package/lzma-sdk:
# this is stricter than Buildroot's infra-installed packages (cmake/autotools
# targets keep their unversioned .so on the target, since target-finalize
# prunes headers/.pc/.a but not symlinks), and nothing links at runtime
# through the unversioned name, so omitting it there loses nothing.
#
# rcheevos.pc is shipped in this package dir and installed with the Version
# line substituted from RCHEEVOS_SOVERSION, so the .mk stays the single source
# of truth for the version (pc-in-package-dir precedents: package/lzma-sdk
# ships lzma-sdk.pc, upstream package/libmad ships mad.pc).
define RCHEEVOS_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/librcheevos.so.$(RCHEEVOS_SOVERSION) \
		$(STAGING_DIR)/usr/lib/librcheevos.so.$(RCHEEVOS_SOVERSION)
	ln -sf librcheevos.so.$(RCHEEVOS_SOVERSION) \
		$(STAGING_DIR)/usr/lib/librcheevos.so
	mkdir -p $(STAGING_DIR)/usr/include/rcheevos
	$(INSTALL) -m 0644 $(wildcard $(@D)/include/*.h) $(@D)/src/rc_version.h \
		$(STAGING_DIR)/usr/include/rcheevos
	$(INSTALL) -D -m 0644 $(RCHEEVOS_PKGDIR)/rcheevos.pc \
		$(STAGING_DIR)/usr/lib/pkgconfig/rcheevos.pc
	$(SED) 's/@RCHEEVOS_VERSION@/$(RCHEEVOS_SOVERSION)/' \
		$(STAGING_DIR)/usr/lib/pkgconfig/rcheevos.pc
endef

define RCHEEVOS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/librcheevos.so.$(RCHEEVOS_SOVERSION) \
		$(TARGET_DIR)/usr/lib/librcheevos.so.$(RCHEEVOS_SOVERSION)
endef

$(eval $(generic-package))
