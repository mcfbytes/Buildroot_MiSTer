# MiSTer Buildroot external -- thin wrapper. Everything past `make <name>_defconfig`
# is plain Buildroot: `make`, `make menuconfig`, `make linux-menuconfig`,
# `make legal-info`, `make <pkg>-rebuild`, ... are forwarded unchanged, with
# BR2_EXTERNAL set to this tree and O= pointing at the output directory. The
# only thing this wrapper adds is that the pinned Buildroot release is fetched
# and hash-verified for you into work/buildroot (Buildroot is never vendored).
#
#   make mister_de10nano_defconfig && make                 # the DE10-Nano image
#   make O=output-de25 mister_de25nano_defconfig && make O=output-de25   # the DE25-Nano
#   make linux-menuconfig  |  make linux-rt-menuconfig  |  make help
#
# ONE DEPARTURE FROM A PLAIN BUILDROOT DEFCONFIG, for newcomers: the shared
# package sets are Kconfig PROFILES (package/mister-userspace, -firmware,
# -drivers) that the defconfig enables with one line each, so two boards
# share a userspace without drifting apart. "Why is package X in my image?"
# -> package/mister-userspace/Config.in. See docs/buildroot-config.md.
#
# Documentation: README.md "Building it yourself"; docs/decisions/0030.

# --- Buildroot pin ----------------------------------------------------------
# Renovate bumps BUILDROOT_VERSION; BUILDROOT_SHA256 is transcribed from the
# GPG-clearsigned release manifest (`make buildroot-showsig`) by
# scripts/hash-sync-buildroot.sh -- never from a downloaded tarball. Keep both
# lines exactly this shape: four scripts and renovate.json parse them.
BUILDROOT_VERSION  ?= 2026.08
BUILDROOT_SHA256   ?= d678e810abf877d04513e03ca2c99f992dd49118b9c2e18d6e25f5f58fa8c5cd

ROOT_DIR   := $(CURDIR)
O          ?= $(ROOT_DIR)/output
export BR2_DL_DIR ?= $(ROOT_DIR)/dl
BR_DIR     := $(ROOT_DIR)/work/buildroot
BR_STAMP   := $(BR_DIR)/.mister-br2-stamp-$(BUILDROOT_VERSION)
HOSTSHIM   := $(ROOT_DIR)/work/.hostshim
BR_MAKE     = PATH="$(HOSTSHIM):$$PATH" $(MAKE) -C $(BR_DIR) O=$(O) BR2_EXTERNAL=$(ROOT_DIR)

.PHONY: all help hostshim buildroot-unpack buildroot-verify buildroot-showsig
.PHONY: de25 sdcard clean distclean

all: $(BR_STAMP) hostshim
	@test -f $(O)/.config || { \
		echo "FATAL: $(O)/.config does not exist -- configure first:" >&2; \
		echo "         make mister_de10nano_defconfig          # DE10-Nano image" >&2; \
		echo "         make O=output-de25 mister_de25nano_defconfig   # DE25-Nano" >&2; exit 1; }
	$(BR_MAKE) all

# The pinned tree: fetched + SHA-256-verified + unpacked once per version (the
# stamp carries the version, so a bump is a new target and re-fetches).
$(BR_STAMP):
	scripts/fetch-buildroot.sh $(BUILDROOT_VERSION) $(BUILDROOT_SHA256) $(BR2_DL_DIR) $(BR_DIR)
	@touch $@
buildroot-unpack: $(BR_STAMP)
buildroot-verify:
	scripts/fetch-buildroot.sh --verify-only $(BUILDROOT_VERSION) $(BUILDROOT_SHA256) $(BR2_DL_DIR)
buildroot-showsig:
	scripts/fetch-buildroot.sh --showsig $(BUILDROOT_VERSION)

# GNU `install` shim for hosts whose install is uutils (no-op elsewhere).
hostshim:
	@scripts/hostshim.sh $(HOSTSHIM)

# The DE25-Nano builds in its own output tree; this is `make O=output-de25`.
de25: $(BR_STAMP) hostshim
	$(MAKE) O=$(ROOT_DIR)/output-de25 all

# SD-card installer image (ADR 0020): a shell orchestrator, run after `make all`.
sdcard: hostshim
	SDCARD_CORES=$(SDCARD_CORES) $(ROOT_DIR)/scripts/mk-sdcard.sh

# Buildroot's own meanings: clean keeps .config, distclean removes the tree.
# dl/ is a shared download cache and survives both; `git clean -xfd` takes it.
clean: $(BR_STAMP)
	@for o in $(O) $(ROOT_DIR)/output-de25 $(ROOT_DIR)/output-installer; do \
		[ -f $$o/.config ] && $(MAKE) -C $(BR_DIR) O=$$o BR2_EXTERNAL=$(ROOT_DIR) clean; done; true
	rm -rf $(ROOT_DIR)/output-installer-kernel $(ROOT_DIR)/output-sdcard-stage $(ROOT_DIR)/output-sdcard-build $(ROOT_DIR)/output-config-check
distclean:
	rm -rf $(O) $(ROOT_DIR)/output-de25 $(ROOT_DIR)/output-installer $(ROOT_DIR)/output-installer-kernel \
	       $(ROOT_DIR)/output-sdcard-stage $(ROOT_DIR)/output-sdcard-build $(ROOT_DIR)/output-config-check

help: $(BR_STAMP) hostshim
	@echo "MiSTer Buildroot external (Buildroot $(BUILDROOT_VERSION), BR2_EXTERNAL=$(ROOT_DIR), O=$(O))"
	@echo "  make mister_de10nano_defconfig && make                 the DE10-Nano image (output/)"
	@echo "  make O=output-de25 mister_de25nano_defconfig && make O=output-de25   the DE25-Nano (or: make de25)"
	@echo "  make sdcard                                             installer card image, after make all"
	@echo "  make buildroot-unpack | buildroot-verify | buildroot-showsig"
	@echo "Everything else is Buildroot's own (below), forwarded with O= and BR2_EXTERNAL set."
	@echo ""
	@$(BR_MAKE) help

# GNU make would otherwise try to remake this file through the catch-all.
Makefile: ;

# Every other goal is Buildroot's: menuconfig, linux-menuconfig, savedefconfig,
# legal-info, external-deps, <pkg>-rebuild, list-defconfigs, ...
%: $(BR_STAMP) hostshim
	$(BR_MAKE) $@
