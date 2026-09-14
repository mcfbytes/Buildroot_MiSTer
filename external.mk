################################################################################
#
# external.mk for the MISTER BR2_EXTERNAL tree
#
# Pulls in every package .mk under package/*/*.mk. P3.1 added the Realtek
# Wi-Fi kernel-module packages; v9 narrowed the SELECTED set (defconfig) to the
# three 802.11ac chips with no mainline USB driver -- rtl8812au, rtl8814au-morrownr
# and rtl8821au-morrownr -- and moved 8188eu/8188fu/8821cu/8822bu onto in-kernel
# drivers (rtl8xxxu/rtw88; the now-deselected packages stay in the tree as a
# selectable fallback). P3.2 added xone (Xbox One/Series accessory driver) the
# same way (see PLAN.md §6, TASKS.md class D/E). This is the standard Buildroot
# br2-external idiom, so new packages need no change here — just add
# package/<name>/<name>.mk.
#
################################################################################

include $(sort $(wildcard $(BR2_EXTERNAL_MISTER_PATH)/package/*/*.mk))

# The stage-1 initramfs is embedded by linux/linux-ext-mister-initramfs.mk
# (a Buildroot "linux extension", included by linux/linux.mk before the
# kernel package is evaluated -- the only hook early enough to make the
# kernel DEPEND on package/mister-initramfs). It used to live here as a
# LINUX_KCONFIG_FIXUP_CMDS append against a cpio from a second Buildroot
# tree; ADR 0030 moved both the cpio and the fixup into the main build.


################################################################################
#
# dhcpcd: pin the hook set so it cannot depend on the BUILD HOST.
#
# dhcpcd's own ./configure decides which dhcpcd-hooks to install by probing the
# machine it runs on -- `which ntpd`, `which chronyd`,
# /usr/lib/systemd/systemd-timesyncd, `which ypbind` -- unless it is handed the
# list explicitly (configure: `if ! $HOOKSET` around the probes; HOOKSET is
# only set by --with-hooks). Buildroot's package/dhcpcd/dhcpcd.mk passes no
# --with-hooks, so the TARGET image inherited the host's daemons: a GitHub
# runner (ntpd/chronyd on PATH) shipped 50-ntp.conf, a developer box with
# systemd-timesyncd and no ntpd shipped 50-timesyncd.conf instead -- and the
# build was green either way. Found 2026-09-02 by diffing a CI image against a
# local one (docs/init-parity.md, dhcpcd row).
#
# This appends to the package's own CONFIG_OPTS -- legal because Buildroot
# includes BR2_EXTERNAL .mk files after package/*/*.mk (work/buildroot/
# Makefile: package includes first, then $(BR2_EXTERNAL_MKS)) and the
# DHCPCD_CONFIGURE_CMDS `define` expands $(DHCPCD_CONFIG_OPTS) when the recipe
# RUNS, not when the .mk is parsed. No Buildroot patch, no dhcpcd patch.
#
# The values reproduce the canonical (CI-built) image exactly: the base hooks
# 01-test/20-resolv.conf/30-hostname are unconditional in hooks/Makefile;
# `ntp.conf` selects 50-ntp.conf (we ship classic ntpd, BR2_PACKAGE_NTP, so
# DHCP-offered NTP servers land in /etc/ntp.conf as on stock); `yp.conf` keeps
# the 50-yp.conf EXAMPLE hook under /usr/share/dhcpcd/hooks, which CI also
# shipped. Names are hook stems: configure's find_hook() matches
# [0-9][0-9]-<stem>[.conf], so "ntp.conf" is right and "50-ntp.conf" silently
# matches nothing (verified against dhcpcd 10.2.4's configure).
# scripts/check-linux-img.sh asserts the resulting hook set, fail-closed.
#
################################################################################
ifeq ($(BR2_PACKAGE_DHCPCD),y)
DHCPCD_CONFIG_OPTS += --with-hooks=ntp.conf --with-eghooks=yp.conf
endif

################################################################################
#
# U-Boot / DE25-Nano: the QSPI-write audit as a build assertion.
#
# docs/de25-uboot.md section 7 is a hand-audited table of every U-Boot Kconfig
# symbol, command and default-environment string that could reach the DE25's
# QSPI flash (SDM firmware + the phase-1 HPS bitstream + the factory SPL --
# no power-loss-safe update path on this board, so a write there is
# brick-class with JTAG-only recovery). docs/de25-boot-chain.md section 5's
# final bullet and its section 9.3 open-concern row both record, as of
# 2026-08-21, that "no release writes QSPI" is "a policy, enforced by prose
# only" -- no CI check pins a DE25 U-Boot config to the audited state. This
# hook is that check, moved from prose into the build (docs/uboot-tasks.md
# DU2): a wrong fragment request, a wrong resolved .config, or a QSPI-write
# command string reaching u-boot.itb, fails `make uboot-rebuild` outright,
# naming both docs.
#
# Same mechanism as the dhcpcd block above: BR2_EXTERNAL_MKS is included by
# Buildroot's own Makefile AFTER every package/*.mk (work/buildroot/Makefile:
# package includes first, then $(BR2_EXTERNAL_MKS)), so UBOOT_POST_BUILD_HOOKS
# already carries its Buildroot-default value here, and appending to it is
# legal. The hook body is $(call)ed from $(BUILD_DIR)/%/.stamp_built's own
# recipe (package/pkg-generic.mk), where $(@D) is the package's build
# directory ($(BUILD_DIR)/uboot-<version>) -- no Buildroot patch, no U-Boot
# patch.
#
# Guarded on the DE25 U-Boot board defconfig specifically, not merely
# "aarch64": the repo's other board-distinguishing idiom is by architecture
# (package/mister-initramfs/mister-initramfs.mk:35, BR2_arm vs BR2_aarch64),
# but BR2_TARGET_UBOOT_BOARD_DEFCONFIG says directly "this is the DE25 U-Boot
# build", which is the fact this hook actually depends on. It is therefore
# inert on the DE10 tree, where that symbol is "socfpga_de10_nano": `make
# O=output printvars VARS='UBOOT_%_HOOKS MISTER_UBOOT_%'` on the DE10 tree
# prints neither UBOOT_POST_BUILD_HOOKS nor any MISTER_UBOOT_* variable, so
# the hook is never appended there [V, evaluated 2026-09-14; the DE10 tree was
# not rebuilt].
#
# THREE THINGS ARE AUDITED, and the first exists because of a trap:
#
#   1. The FRAGMENT (board/mister/de25nano/uboot.fragment). A fragment line
#      asking for one of these symbols does NOT necessarily show up in the
#      resolved .config: ENV_IS_IN_UBI `depends on MTD_UBI` and `depends on
#      CMD_UBI` (u-boot env/Kconfig), both off here, so kconfig SILENTLY DROPS
#      the request -- merge_config.sh prints an "override" warning and the
#      resolved .config gains no line at all. de25-uboot.md section 7 says
#      exactly this ("strictly stronger than 'not set' -- there is no line to
#      flip"), which is good news for safety and bad news for a checker that
#      only reads the resolved config: the request would pass unnoticed today
#      and become live the moment some other change satisfied its
#      dependencies. A fragment that asks to re-open a brick-class hazard is a
#      defect whether or not kconfig happened to grant it, so it fails here.
#
#   2. The RESOLVED .config ($(@D)/.config) -- section 7's table proper,
#      including CONFIG_ENV_IS_IN_FAT=y, the one permitted env location.
#
#   3. The built u-boot.itb, by `strings`: the default environment is compiled
#      in as text, and section 7's sharpest finding (the stock `bootcmd_qspi`,
#      `"ubi detach; sf probe && ... saveenv && ubi part root"`) is a QSPI
#      write living in a STRING, not in a symbol. One documented exception is
#      allowed and is pinned by its exact head -- see the comment on
#      QSPI_ENV_EXEMPT below.
#
################################################################################
ifeq ($(call qstrip,$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG)),socfpga_agilex5)

# Section 7's symbol table, as one extended-regex alternation. Anchored with
# "^CONFIG_" and followed by "=" at the use site, so CONFIG_MTD matches
# CONFIG_MTD= and CONFIG_MTD_UBI= (its own alternative) but never
# CONFIG_SPL_MTD= or CONFIG_BLOBLIST_SIZE=.
MISTER_DE25_QSPI_SYMS = ENV_IS_IN_UBI|ENV_IS_IN_SPI_FLASH|ENV_IS_IN_NAND|ENV_IS_IN_MMC|CADENCE_QSPI|DM_SPI_FLASH|SPI_FLASH[A-Z_]*|CMD_SF[A-Z_]*|CMD_MTD[A-Z_]*|CMD_UBI[A-Z_]*|CMD_NAND|MTD|DM_MTD|MTD_UBI|MTD_RAW_NAND|HANDOFF|BLOBLIST

# Command strings that must not appear in the built FIT, plus the erase/write
# verbs that would make one of them dangerous. Section 7 names the first three.
MISTER_DE25_QSPI_STRS = sf probe|sf erase|sf write|sf update|ubi part|ubi create|mtdparts|mtd erase|mtd write|nand erase|nand write

# The ONE permitted `sf probe` occurrence, pinned by the head of its line.
#
# DEVIATION FROM docs/uboot-tasks.md DU2, stated plainly: DU2 asks for a
# u-boot.itb "free of `sf probe`". The good build is not, and cannot be
# without a U-Boot patch: include/configs/socfpga_soc64_common.h defines the
# default-env variable `linux_qspi_enable` unconditionally (unlike
# bootcmd_qspi, which is gated on CONFIG_CMD_SF and is genuinely absent here
# [V, checked]), so the string is compiled into every socfpga_soc64 build. Its
# CALLER is gated: board_prep_linux() (arch/arm/mach-socfpga/board.c:194-197)
# runs it under `if (use_fit && IS_ENABLED(CONFIG_CADENCE_QSPI))`, and
# CADENCE_QSPI is one of the symbols check 2 above has already proven absent
# -- so this hook only ever reaches the strings check with that gate proven
# closed in the same run. That is section 7's own "inert, and it is the
# Kconfig gate that makes it so" row, re-derived per build instead of
# asserted once in prose.
#
# The exemption is deliberately the narrowest that lets the good build pass:
# ONE occurrence, on a line starting with this exact text. Any second
# occurrence, any `sf probe` elsewhere, and any edit to the head of this
# variable (a bump that rewrites it, or someone splicing a write into the
# front of it) fails the build and forces a re-audit. Closing the deviation
# properly means guarding linux_qspi_enable under CONFIG_CADENCE_QSPI in the
# carried section-8 U-Boot patch -- upstreamable, out of DU2's scope, noted
# for DU5-prep.
MISTER_DE25_QSPI_ENV_EXEMPT = linux_qspi_enable=if sf probe; then echo Enabling QSPI at Linux DTB

define MISTER_UBOOT_DE25_QSPI_AUDIT
	@set -eu; \
	cfg='$(@D)/.config'; \
	itb='$(@D)/u-boot.itb'; \
	frags='$(UBOOT_KCONFIG_FRAGMENT_FILES)'; \
	syms='$(MISTER_DE25_QSPI_SYMS)'; \
	strs='$(MISTER_DE25_QSPI_STRS)'; \
	exempt='$(MISTER_DE25_QSPI_ENV_EXEMPT)'; \
	doc1='docs/de25-uboot.md section 7'; \
	doc2='docs/de25-boot-chain.md section 5'; \
	for f in $$frags; do \
		[ -f "$$f" ] || continue; \
		hits=$$(grep -E "^[[:space:]]*CONFIG_($$syms)=" "$$f" || true); \
		[ -n "$$hits" ] || continue; \
		echo "MiSTer QSPI-write audit FAILED ($$doc1, $$doc2): $$f asks to enable a symbol this board must never carry --" >&2; \
		echo "$$hits" | sed 's/^/  /' >&2; \
		echo "  A fragment request is a defect even when kconfig drops it for unmet dependencies" >&2; \
		echo "  (ENV_IS_IN_UBI depends on MTD_UBI and CMD_UBI, both off here), because the resolved" >&2; \
		echo "  .config would then look clean while the file still asks to re-open a brick-class" >&2; \
		echo "  hazard. See $$doc1 and $$doc2." >&2; \
		exit 1; \
	done; \
	if [ ! -f "$$cfg" ]; then \
		echo "MiSTer QSPI-write audit: $$cfg not found -- cannot check against $$doc1 / $$doc2" >&2; \
		exit 1; \
	fi; \
	hits=$$(grep -E "^CONFIG_($$syms)=" "$$cfg" || true); \
	if [ -n "$$hits" ]; then \
		echo "MiSTer QSPI-write audit FAILED ($$doc1, $$doc2): the following symbols must be absent or unset in the resolved config --" >&2; \
		echo "$$hits" | sed 's/^/  /' >&2; \
		exit 1; \
	fi; \
	if ! grep -q '^CONFIG_ENV_IS_IN_FAT=y$$' "$$cfg"; then \
		echo "MiSTer QSPI-write audit FAILED ($$doc1, $$doc2): CONFIG_ENV_IS_IN_FAT=y is required -- FAT on the SD card is the only environment location this board may use" >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$$itb" ]; then \
		echo "MiSTer QSPI-write audit: $$itb not found -- cannot check for embedded QSPI-write strings ($$doc1)" >&2; \
		exit 1; \
	fi; \
	hits=$$(strings "$$itb" | grep -E "$$strs" | sed '/^$$/d' || true); \
	bad=$$(printf '%s\n' "$$hits" | sed '/^$$/d' | grep -v -F -e "$$exempt" || true); \
	nallowed=$$(printf '%s\n' "$$hits" | sed '/^$$/d' | grep -c -F -e "$$exempt" || true); \
	nverbs=$$(printf '%s\n' "$$hits" | sed '/^$$/d' | grep -F -e "$$exempt" | grep -oE "$$strs" | grep -c . || true); \
	if [ -n "$$bad" ] || [ "$$nallowed" -gt 1 ] || [ "$$nverbs" -gt 1 ]; then \
		echo "MiSTer QSPI-write audit FAILED ($$doc1, $$doc2): u-boot.itb carries a QSPI command string that is not the one documented, gate-closed exception --" >&2; \
		printf '%s\n' "$$hits" | sed '/^$$/d;s/^/  /' | cut -c1-120 >&2; \
		echo "  The only permitted occurrence is ONE line, carrying ONE of these verbs, beginning:" >&2; \
		echo "    $$exempt" >&2; \
		echo "  ($$doc1's linux_qspi_enable row: inert only because CADENCE_QSPI is compiled out," >&2; \
		echo "  which this hook has just re-proved against the resolved .config.)" >&2; \
		exit 1; \
	fi; \
	echo "MiSTer QSPI-write audit ($$doc1, $$doc2): PASS -- fragment, resolved .config and u-boot.itb all clean"
endef

UBOOT_POST_BUILD_HOOKS += MISTER_UBOOT_DE25_QSPI_AUDIT

endif # BR2_TARGET_UBOOT_BOARD_DEFCONFIG = socfpga_agilex5 (DE25-Nano)
