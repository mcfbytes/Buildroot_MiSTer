################################################################################
#
# midilink
#
################################################################################

# P3.8 (MIDI / MT-32 parity). This is the actual ALSA-sequencer client stock
# runs to expose USB MIDI adapters (and MUNT/FluidSynth softsynth ports) to
# the Minimig/ao486/etc. cores -- traced from stock's /usr/sbin/midilink +
# /usr/sbin/mlinkutil (P0.3 inventory, docs/stock-inventory/
# binaries-needed-full.txt lines 470/480) to their upstream source. See
# docs/midi-mt32-parity.md for the full trace (docs/package-manifest.md's
# P0.7-era note that MIDI/MT-32 is "driven directly by the MiSTer binary,
# not a daemon" predates this and undersells it -- flagged there, not
# corrected here, since package-manifest.md is out of this task's lane).
#
# FORK CHOICE, CHECKED AT PIN TIME (2026-07-13), NOT ASSUMED: MiSTer-devel/
# MidiLink_MiSTer (the official org repo) vs. bbond007/MiSTer_MidiLink (a
# community fork carrying its own bundled mt32d/ cross-build scaffold).
# Picked the official repo: no evidence surfaced that its midilink/
# mlinkutil source has meaningfully diverged from bbond007's copy (both
# describe themselves identically), and this project builds mt32d from
# munt's own upstream source anyway (package/munt), so bbond007's bundled
# mt32d build scaffolding is not a draw. Neither repo publishes release
# tags -- pin is an exact commit, same as package/xone's precedent for an
# untagged upstream.
MIDILINK_VERSION = d6b337383d10dc5048b22eb5d27baf61826f6bb1
# HEAD of MiSTer-devel/MidiLink_MiSTer's master branch at pin time
# (`gh api repos/MiSTer-devel/MidiLink_MiSTer/commits/master`), dated
# 2026-06-08, "Disable DELAYSYSEX for X68000 (#18)".
MIDILINK_SITE = $(call github,MiSTer-devel,MidiLink_MiSTer,$(MIDILINK_VERSION))
MIDILINK_LICENSE = GPL-3.0+
MIDILINK_LICENSE_FILES = LICENSE
MIDILINK_DEPENDENCIES = alsa-lib

# Upstream's own Makefile (checked, not assumed) is:
#   CCFLAGS=-Ialsa/include -Lalsa/lib -Ofast -mcpu=cortex-a9 -mtune=cortex-a9 \
#           -mfpu=neon -mfloat-abi=hard -ftree-vectorize -funsafe-math-optimizations
#   LDFLAGS=-lasound -lm -pthread
#   $(CC) $(CCFLAGS) $(LDFLAGS) main.c modem.c serial.c serial2.c misc.c \
#         udpsock.c tcpsock.c alsa.c ini.c directory.c modem_snd.c -o midilink
#   $(CC) $(CCFLAGS) mlinkutil.c misc.c serial2.c tcpsock.c -o mlinkutil
#
# Deliberately NOT reproduced verbatim:
#   - "-Ialsa/include -Lalsa/lib" pull in this repo's own vendored,
#     prebuilt-for-a-specific-old-cross-toolchain ALSA headers/static libs
#     (checked: alsa/include, alsa/lib exist in the tree). G4 says do not
#     vendor -- built here against THIS system's alsa-lib (staged the
#     normal Buildroot way) instead; alsa.c's API usage is pure
#     snd_seq_*() (checked: grepped every snd_(seq|rawmidi|pcm|mixer)_
#     symbol in alsa.c, all are snd_seq_*), matching
#     BR2_PACKAGE_ALSA_LIB_SEQ selected in Config.in.
#   - "-Ofast ... -funsafe-math-optimizations -mcpu=cortex-a9 ..." hardcode
#     both an aggressive fast-math optimization level AND a specific CPU
#     tune that happens to match the DE10-Nano's Cortex-A9 today but
#     shouldn't be duplicated ad hoc per-package -- $(TARGET_CFLAGS)
#     already carries the board's real -mcpu/-mfpu/-mfloat-abi (from the
#     toolchain's own BR2_GCC_TARGET_* config) plus this build's chosen
#     -O level, consistently with every other package in the image.
define MIDILINK_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/main.c $(@D)/modem.c $(@D)/serial.c $(@D)/serial2.c $(@D)/misc.c \
		$(@D)/udpsock.c $(@D)/tcpsock.c $(@D)/alsa.c $(@D)/ini.c $(@D)/directory.c \
		$(@D)/modem_snd.c \
		-lasound -lm -pthread \
		-o $(@D)/midilink
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/mlinkutil.c $(@D)/misc.c $(@D)/serial2.c $(@D)/tcpsock.c \
		-lasound -lm -pthread \
		-o $(@D)/mlinkutil
endef

# Paths match stock exactly (P0.3 inventory: usr/sbin/midilink,
# usr/sbin/mlinkutil), not Buildroot's more common usr/bin -- MidiLink.INI
# and MiSTer's own menu/core-launch scripts, if they invoke either by
# absolute path rather than bare name + $PATH, expect /usr/sbin.
define MIDILINK_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/midilink $(TARGET_DIR)/usr/sbin/midilink
	$(INSTALL) -D -m 0755 $(@D)/mlinkutil $(TARGET_DIR)/usr/sbin/mlinkutil
endef

$(eval $(generic-package))
