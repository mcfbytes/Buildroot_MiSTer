################################################################################
#
# munt
#
################################################################################

# P3.8 (MIDI / MT-32 parity). Stock's /usr/sbin/mt32d (P0.3 inventory,
# docs/stock-inventory/binaries-needed-full.txt line 481: linked against only
# libasound/libc/libgcc_s/libm/libpthread/libstdc++ -- notably NO
# libmt32emu.so, i.e. it links libmt32emu statically or the SONAME just isn't
# separately listed by that scan; either way the *behavior* is upstream
# munt's mt32emu_alsadrv "mt32d" console daemon, confirmed by tracing who
# calls it: package/midilink's own upstream source (main.c's start_munt(),
# see midilink.mk) literally does `system("... mt32d ... -f <ROM path> &")`.
# Buildroot 2026.05.1 upstream has no "munt" package (checked:
# work/buildroot/package/munt does not exist), so this authors one.
#
# CHECKED, NOT ASSUMED: mt32emu_alsadrv is a *separate*, plain-Makefile-only
# module that the top-level CMakeLists.txt does not even list as an option
# (only munt_WITH_MT32EMU_SMF2WAV / _QT / _WIN32DRV exist there) -- so it is
# built by hand below, not via cmake-package's own BUILD_CMDS. Its own
# upstream Makefile (mt32emu_alsadrv/Makefile) builds "mt32d" from only
# wav.o + alsadrv.o + src/console.cpp, linked -lmt32emu -lm -lasound
# -lpthread -- NO X11 libs. Only its sibling target "xmt32" (the X-Windows
# GUI, keypad.cpp/lcd.cpp/pixmaps.cpp/xmt32.cpp) needs
# -lX11/-lXt/-lXpm, and this package deliberately never builds it: this is a
# headless embedded image with no X11 stack, and MidiLink's "MUNT" uartmode
# (see midilink.mk) only ever shells out to "mt32d", never "xmt32".
MUNT_VERSION = munt_2_8_2
# Tag munt_2_8_2 resolves to commit 3b05ec276f9e605af86b0eaef7f5eda43477a31f
# (checked at pin time, 2026-07-13, via `gh api repos/munt/munt/git/refs/tags/munt_2_8_2`).
MUNT_SITE = $(call github,munt,munt,$(MUNT_VERSION))
# The library (mt32emu/) and mt32emu_alsadrv/ (mt32d/xmt32) are both
# LGPL-2.1+: mt32emu/COPYING.LESSER.txt is the project-wide LGPL text, and
# mt32emu_alsadrv/src/console.cpp's own file header independently declares
# "GNU Lesser General Public License ... version 2.1 ... or (at your option)
# any later version" (checked, not assumed from the generic COPYING split).
# COPYING.txt (plain GPL-2.0) exists at both levels too and covers the parts
# of the tree this package does NOT build (mt32emu_qt, mt32emu_smf2wav,
# mt32emu_win32drv) -- irrelevant here.
MUNT_LICENSE = LGPL-2.1+
MUNT_LICENSE_FILES = mt32emu/COPYING.LESSER.txt mt32emu_alsadrv/COPYING.LESSER.txt

# Only configure/build the standalone libmt32emu CMake project -- NOT the
# top-level umbrella CMakeLists.txt, which would also try to configure
# mt32emu_qt (needs Qt5/Qt6, entirely unwanted here) and mt32emu_smf2wav
# (a standalone MIDI-to-WAV CLI tool, not part of stock's MIDI path).
MUNT_SUBDIR = mt32emu
MUNT_INSTALL_STAGING = YES
MUNT_DEPENDENCIES = alsa-lib

# doctest (the library's optional unit-test framework) is not a Buildroot
# package; the upstream CMakeLists.txt already degrades gracefully with a
# STATUS message and testing disabled if find_package(doctest) fails, but
# being explicit avoids an unnecessary host find_package probe on every
# build and documents intent.
MUNT_CONF_OPTS = -DBUILD_TESTING=OFF

# mt32emu_alsadrv/src/*.cpp expect "mt32emu/mt32emu.h" on the include path
# (i.e. a parent directory containing an "mt32emu/" subdirectory) -- exactly
# the layout libmt32emu's own CMakeLists.txt installs to
# $(STAGING_DIR)/usr/include/mt32emu/. Compiled and linked here, after
# INSTALL_STAGING/INSTALL_TARGET have both already populated STAGING_DIR and
# TARGET_DIR respectively (standard Buildroot stamp ordering), using the
# same source flags upstream's own mt32emu_alsadrv/Makefile uses for
# "mt32d" (checked against that Makefile directly): CXXFLAGS
# "-Wno-write-strings -Wno-unused-result -Wno-deprecated-declarations",
# LIBS "-lmt32emu -lm -lasound -lpthread" -- swapped here for
# $(TARGET_CXXFLAGS)/$(TARGET_LDFLAGS) so this package picks up the same
# optimization/hardening flags as every other Buildroot-built binary in the
# image, and for the toolchain's own $(TARGET_CXX) rather than a hardcoded
# cross-compiler prefix.
define MUNT_BUILD_MT32D
	$(TARGET_CXX) $(TARGET_CXXFLAGS) -Wno-write-strings -Wno-unused-result -Wno-deprecated-declarations \
		-I$(STAGING_DIR)/usr/include \
		-c $(@D)/mt32emu_alsadrv/src/alsadrv.cpp -o $(@D)/mt32emu_alsadrv/src/alsadrv.o
	$(TARGET_CXX) $(TARGET_CXXFLAGS) -Wno-write-strings -Wno-unused-result -Wno-deprecated-declarations \
		-I$(STAGING_DIR)/usr/include \
		-c $(@D)/mt32emu_alsadrv/src/wav.cpp -o $(@D)/mt32emu_alsadrv/src/wav.o
	$(TARGET_CXX) $(TARGET_CXXFLAGS) $(TARGET_LDFLAGS) -Wno-write-strings -Wno-unused-result -Wno-deprecated-declarations \
		-I$(STAGING_DIR)/usr/include \
		$(@D)/mt32emu_alsadrv/src/console.cpp \
		$(@D)/mt32emu_alsadrv/src/alsadrv.o $(@D)/mt32emu_alsadrv/src/wav.o \
		-L$(STAGING_DIR)/usr/lib -lmt32emu -lasound -lpthread -lm \
		-o $(@D)/mt32emu_alsadrv/src/mt32d
	$(INSTALL) -D -m 0755 $(@D)/mt32emu_alsadrv/src/mt32d $(TARGET_DIR)/usr/sbin/mt32d
endef
MUNT_POST_INSTALL_TARGET_HOOKS += MUNT_BUILD_MT32D

$(eval $(cmake-package))
