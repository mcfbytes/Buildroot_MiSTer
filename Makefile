################################################################################
#
# Top-level wrapper for the MISTER BR2_EXTERNAL tree (P1.1, PLAN.md §6).
#
# Buildroot itself is NEVER vendored into this repository (G4/G6, TASKS.md
# standing rule 1 — "No binaries in git. Ever."). This Makefile:
#
#   1. Downloads the pinned upstream Buildroot release tarball into an
#      untracked cache directory (dl/).
#   2. Verifies its SHA-256 against the pinned hash below and aborts loudly
#      on any mismatch — it will NOT unpack an unverified tarball.
#   3. Unpacks it to work/buildroot/ (idempotent: if a Buildroot tree of the
#      pinned version is already present there, the download/verify/unpack
#      step is skipped entirely and no network access is made).
#   4. Forwards every other target (menuconfig, mister_de10nano_defconfig,
#      olddefconfig, savedefconfig, ...) into that Buildroot tree with
#      BR2_EXTERNAL set to this repo, O= pointed at an out-of-tree output
#      directory, and BR2_DL_DIR pointed at the persistent download cache.
#
# work/, dl/, and output/ are all gitignored — see .gitignore.
#
# Reference: /mnt/source/sb-enema/Makefile (working 2026.02.3 pinned-tarball
# wrapper this is modeled on). That reference has no hash verification; this
# Makefile adds it, which is the whole point of P1.1.
#
################################################################################

# --- Buildroot pin ------------------------------------------------------------
# P4.6 wires a Renovate custom regex manager over BUILDROOT_VERSION /
# BUILDROOT_SHA256 in this file (PLAN.md §9), the same way sb-enema's
# renovate.json does for BUILDROOT_VERSION — keep this stanza regex-friendly.
#
# WHERE BUILDROOT_SHA256 COMES FROM — read before changing it.
# The hash below is transcribed from Buildroot's GPG-clearsigned release
# manifest for this exact version:
#
#     https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.gz.sign
#
# which contains a "SHA256: <hash>  buildroot-<version>.tar.gz" line signed by
# the Buildroot maintainer. That signed file is the ONLY source of truth for
# this value.
#
# Do NOT produce this hash by downloading the tarball and running sha256sum on
# it. That is circular — it pins whatever bytes you happened to receive, and
# certifies nothing. A bump (manual or Renovate) MUST take the new hash from
# the .sign file for the new version. `make buildroot-showsig` prints it.
BUILDROOT_VERSION ?= 2026.02.3
BUILDROOT_SHA256   ?= 65528a544f1e07c2f5ec487beca483bd380a6af8351a45f3649a19a0e8b63de2
BUILDROOT_URL       = https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_SIG_URL   = $(BUILDROOT_URL).sign

ROOT_DIR   := $(CURDIR)
WORK_DIR   := $(ROOT_DIR)/work
DL_DIR     := $(ROOT_DIR)/dl
OUTPUT_DIR := $(ROOT_DIR)/output

# --- Stage-1 initramfs output (P1.10 / A1) ------------------------------------
# A SECOND, SEPARATE Buildroot output directory. This is the whole trick of the
# two-stage build (PLAN.md §5, docs/decisions/0002-initramfs.md): stage 1 is a
# different Buildroot *configuration* (static musl BusyBox, cpio) and therefore
# needs a different O=. It must never share $(OUTPUT_DIR) — that would clobber the
# main build's toolchain and target/ with the initramfs's.
#
# It is emphatically NOT BR2_TARGET_ROOTFS_INITRAMFS on the main config: that
# option embeds the whole ~300 MB target rootfs into the kernel (A1).
INITRAMFS_OUTPUT_DIR := $(ROOT_DIR)/output-initramfs
INITRAMFS_CPIO       := $(INITRAMFS_OUTPUT_DIR)/images/rootfs.cpio
INITRAMFS_DEFCONFIG  := $(ROOT_DIR)/configs/mister_initramfs_defconfig
INITRAMFS_INIT       := $(ROOT_DIR)/board/mister/de10nano/initramfs-overlay/init

BR_TARBALL := $(DL_DIR)/buildroot-$(BUILDROOT_VERSION).tar.gz
BR_DIR     := $(WORK_DIR)/buildroot
# Two properties this path must have, both learned the hard way:
#
#  1. INSIDE $(BR_DIR), not a $(WORK_DIR) sibling. Make only reruns a file
#     target's recipe when the target is missing or stale, so a stamp that
#     outlives $(BR_DIR) (someone rm -rf's or mv's the tree away) would keep
#     asserting "already present" forever. Living inside ties the stamp's
#     lifetime to the tree it attests to.
#
#  2. VERSION-QUALIFIED. The $(BR_STAMP) rule has no prerequisites, so its
#     recipe runs exactly once per distinct stamp filename, ever. With a
#     constant name, bumping BUILDROOT_VERSION left the old stamp in place and
#     Make said "Nothing to be done" — silently building against the OLD
#     Buildroot tree and never even checking the new hash. That is precisely
#     what P4.6's Renovate bump does, so it would have shipped broken.
#     Putting the version in the filename makes a bump a different target,
#     which is missing, which forces the re-fetch.
BR_STAMP   := $(BR_DIR)/.mister-br2-stamp-$(BUILDROOT_VERSION)

# --- Host `install` must be GNU install ---------------------------------------
# Buildroot REFUSES to build if /usr/bin/install is uutils coreutils 0.8.0 —
# see work/buildroot/support/dependencies/dependencies.sh:193-200, which pins
# that exact version and links the upstream bug:
#     https://github.com/uutils/coreutils/issues/12166
# Debian/Ubuntu's `coreutils-from-uutils` package installs exactly that as the
# default `install`, and ships GNU's as `gnuinstall`.
#
# Buildroot's own advice is `update-alternatives --install ... gnuinstall 100`,
# which needs root and mutates the developer's system. We do NOT do that. We
# instead build a tiny shim directory containing a single `install` symlink to
# whatever GNU install we can find, and prepend it to PATH for Buildroot only.
# That is self-contained, needs no root, is identical for every developer and
# for CI, and touches nothing outside this repo. It is a no-op on a host whose
# `install` is already GNU.
#
# [P1.10] The shim lives under work/, NOT under $(OUTPUT_DIR). It is a property of
# the *host*, not of any one Buildroot output, and since P1.10 there are two output
# directories that both need it. Keeping it in output/ would mean rebuilding it per
# output dir and losing it to a `make clean` of the main build.
HOSTSHIM_DIR := $(WORK_DIR)/.hostshim
GNU_INSTALL  := $(shell if install --version 2>/dev/null | grep -q 'GNU coreutils'; then \
                            command -v install; \
                        else \
                            command -v gnuinstall 2>/dev/null; \
                        fi)

.PHONY: hostshim
hostshim:
	@if install --version 2>/dev/null | grep -q 'GNU coreutils'; then \
		exit 0; \
	fi; \
	if [ -z "$(GNU_INSTALL)" ]; then \
		echo "FATAL: your 'install' is not GNU coreutils:" >&2; \
		install --version 2>&1 | head -1 | sed 's/^/    /' >&2; \
		echo "" >&2; \
		echo "Buildroot refuses to build with it (dependencies.sh:193; upstream bug" >&2; \
		echo "https://github.com/uutils/coreutils/issues/12166), and no GNU 'install'" >&2; \
		echo "was found to substitute. Install GNU coreutils, e.g.:" >&2; \
		echo "    sudo apt-get install gnu-coreutils   # provides /usr/bin/gnuinstall" >&2; \
		exit 1; \
	fi; \
	mkdir -p $(HOSTSHIM_DIR); \
	ln -sf $(GNU_INSTALL) $(HOSTSHIM_DIR)/install; \
	echo "==> host 'install' is not GNU; shimming $(GNU_INSTALL) into PATH for Buildroot"

# Buildroot invocation shared by every forwarded target. BR2_EXTERNAL is passed
# explicitly here rather than exported: a command-line assignment overrides the
# environment anyway, so an export would just be a redundant second source of
# truth that can drift out of sync with this one.
#
# $(HOSTSHIM_DIR) goes FIRST in PATH so the GNU `install` shim (see above) wins
# over a uutils one. On a host with GNU install the directory is never created
# and this prefix is inert.
BR_MAKE = PATH="$(HOSTSHIM_DIR):$$PATH" \
          $(MAKE) -C $(BR_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(ROOT_DIR) BR2_DL_DIR=$(DL_DIR)

# The same, aimed at the stage-1 output directory. Same Buildroot tree, same
# BR2_EXTERNAL, same download cache — only O= and the defconfig differ.
BR_MAKE_INITRAMFS = PATH="$(HOSTSHIM_DIR):$$PATH" \
          $(MAKE) -C $(BR_DIR) O=$(INITRAMFS_OUTPUT_DIR) BR2_EXTERNAL=$(ROOT_DIR) BR2_DL_DIR=$(DL_DIR)

# Bare `make` must NOT be `all`. The P1.1 defconfig deliberately sets no arch or
# toolchain, so Buildroot would fall back to its own defaults (BR2_i386 +
# internal toolchain) and a reflexive `make` would spend an hour compiling an
# x86 toolchain and rootfs that nothing in this project wants. P1.2 gives the
# defconfig real content; until then, and arguably after, `help` is the right
# thing to get for free.
.DEFAULT_GOAL := help

.PHONY: all help buildroot-fetch buildroot-verify buildroot-unpack buildroot-showsig require-tools
.PHONY: initramfs initramfs-clean initramfs-menuconfig initramfs-busybox-menuconfig check-initramfs
.PHONY: zimage-dtb

# GNU Make always checks whether its own makefiles need remaking, using
# whatever rule matches their name -- including the catch-all `%:` pattern
# rule below. Without this explicit no-op rule, EVERY invocation (and, worse,
# every recursive $(MAKE) call inside the $(BR_STAMP) recipe below) would
# match "Makefile" against `%: $(BR_STAMP)` and try to rebuild $(BR_STAMP)
# again before doing anything else -- which recurses without end the moment
# $(BR_STAMP)'s own recipe invokes $(MAKE) (it does, for buildroot-verify).
# An explicit rule always wins over a pattern rule for the same target name,
# so this simple line is what breaks that cycle.
Makefile: ;

# [P1.10] Exactly the same landmine, one step further out. $(INITRAMFS_DEFCONFIG) is
# a prerequisite of $(INITRAMFS_OUTPUT_DIR)/.config below. It is an existing file with
# no rule of its own, so the catch-all `%: $(BR_STAMP) hostshim` pattern rule matched
# it and make dutifully "remade" it — by forwarding a target literally named
# `/…/configs/mister_initramfs_defconfig` into Buildroot **with O=$(OUTPUT_DIR)**,
# i.e. loading the stage-1 config into the MAIN build's output directory. Caught with
# `make -n initramfs`. An explicit empty rule beats a pattern rule.
$(INITRAMFS_DEFCONFIG): ;

# `make` with no target builds the full image, same as bare Buildroot.
#
# TWO-STAGE (P1.10 / A1). `initramfs` is a hard prerequisite, not a convenience:
# U-Boot passes `-` for the initrd argument of `bootz` and never loads one (A3), so
# the cpio has to be INSIDE the zImage. external.mk points the kernel's
# CONFIG_INITRAMFS_SOURCE at $(INITRAMFS_CPIO) and refuses to configure the kernel
# if that file is not there — so stage 1 must have run first. Ordering it here is
# what makes a bare `make all` do the right thing.
all: initramfs $(BR_STAMP) hostshim
	$(BR_MAKE) all
	@$(MAKE) --no-print-directory check-initramfs

# --- Stage 1: the initramfs cpio ----------------------------------------------
# Phony on purpose. Buildroot is the incremental build system here; re-entering it
# is cheap when nothing changed, and it is the only thing that knows that editing
# board/mister/de10nano/initramfs-overlay/init or initramfs-busybox.config means
# the cpio must be regenerated.
initramfs: $(INITRAMFS_OUTPUT_DIR)/.config hostshim
	$(BR_MAKE_INITRAMFS) all
	@test -f $(INITRAMFS_CPIO) || { \
		echo "FATAL: stage 1 finished but produced no $(INITRAMFS_CPIO)" >&2; exit 1; }
	@$(MAKE) --no-print-directory initramfs-verify
	@echo ""
	@echo "==> stage-1 initramfs: $$(stat -c %s $(INITRAMFS_CPIO)) bytes  ($(INITRAMFS_CPIO))"
	@echo ""

# Every command /init actually invokes, asserted against the cpio we just built.
#
# This exists because of a bug that shipped silently and was only caught by booting:
# `CONFIG_ASH_BUILTIN_TEST` is the pre-1.22 spelling of BusyBox's ash `test`/`[`
# builtin (1.37 calls it `CONFIG_ASH_TEST`). kconfig does not warn about unknown
# symbols in an input .config — `olddefconfig` just DROPS them. So the config asked
# for `[`, BusyBox silently built without it, the cpio looked perfectly healthy, and
# /init died on its first `[ -n "$$root_arg" ]` with "line 98: [: not found" — while
# still printing a rescue banner that claimed the command line had no root=.
#
# A wrong applet name is a brick. Check the artifact, not the intent.
INITRAMFS_REQUIRED_APPLETS := sh mount umount losetup switch_root cttyhack setsid \
                              sleep mkdir cat ls dmesg tail findfs printf echo test
.PHONY: initramfs-verify
initramfs-verify:
	@rc=0; \
	applets=$$(cpio -t --quiet < $(INITRAMFS_CPIO)); \
	for a in $(INITRAMFS_REQUIRED_APPLETS); do \
		echo "$$applets" | grep -qE "^(bin|sbin|usr/bin|usr/sbin)/$$a$$" || { \
			echo "FATAL: /init needs '$$a' but it is not in the cpio." >&2; \
			echo "       Check its CONFIG_ symbol really exists in this BusyBox version —" >&2; \
			echo "       kconfig silently discards unknown symbols. See the header of" >&2; \
			echo "       board/mister/de10nano/initramfs-busybox.config." >&2; \
			rc=1; }; \
	done; \
	echo "$$applets" | grep -qx 'init' || { \
		echo "FATAL: /init is not in the cpio (the overlay did not apply)." >&2; rc=1; }; \
	echo "$$applets" | grep -qx 'dev/console' || { \
		echo "FATAL: /dev/console is not in the cpio — /init would have no stdio and the" >&2; \
		echo "       rescue shell would be unreachable. Is device creation set to STATIC?" >&2; rc=1; }; \
	if command -v qemu-arm >/dev/null 2>&1; then \
		qemu-arm $(INITRAMFS_OUTPUT_DIR)/target/bin/busybox ash -n $(INITRAMFS_INIT) || { \
			echo "FATAL: the BusyBox ash we just built cannot even PARSE /init." >&2; \
			echo "       Usually a shell FEATURE that allnoconfig left off (e.g." >&2; \
			echo "       CONFIG_FEATURE_SH_MATH for \$$((arith))). shellcheck cannot see this:" >&2; \
			echo "       it checks the language, this checks the interpreter we ship." >&2; rc=1; }; \
	else \
		echo "WARN: qemu-arm not installed; skipping the ash -n parse check of /init." >&2; \
	fi; \
	[ $$rc -eq 0 ] && echo "==> initramfs-verify OK: $(words $(INITRAMFS_REQUIRED_APPLETS)) applets + /init + /dev/console + ash parses /init"; \
	exit $$rc

$(INITRAMFS_OUTPUT_DIR)/.config: $(INITRAMFS_DEFCONFIG) | $(BR_STAMP)
	@mkdir -p $(INITRAMFS_OUTPUT_DIR)
	$(BR_MAKE_INITRAMFS) mister_initramfs_defconfig

initramfs-clean:
	rm -rf $(INITRAMFS_OUTPUT_DIR)

# Escape hatches for iterating on stage 1 without hand-editing the checked-in
# configs. Both write to output-initramfs/; remember to fold the result back into
# configs/mister_initramfs_defconfig (`savedefconfig`) or into
# board/mister/de10nano/initramfs-busybox.config by hand.
initramfs-menuconfig: $(INITRAMFS_OUTPUT_DIR)/.config hostshim
	$(BR_MAKE_INITRAMFS) menuconfig

initramfs-busybox-menuconfig: $(INITRAMFS_OUTPUT_DIR)/.config hostshim
	$(BR_MAKE_INITRAMFS) busybox-menuconfig

# --- The assertion that stops a silent brick ----------------------------------
# docs/boot-chain.md §8, I1 and I2. The failure this guards against is not loud: a
# kernel built with CONFIG_INITRAMFS_SOURCE="" boots perfectly, runs the kernel's
# own default_cpio_list rootfs, finds no /init, calls prepare_namespace(), tries to
# mount root=/dev/mmcblk0p1 (a FAT partition) as a root filesystem, and panics —
# with a message that points at the disk, not at the build. Fail at build time
# instead. Also run standalone: `make check-initramfs`.
check-initramfs:
	@cfg=$$(ls -d $(OUTPUT_DIR)/build/linux-*/ 2>/dev/null | head -1)".config"; \
	if [ ! -f "$$cfg" ]; then \
		echo "==> check-initramfs: no kernel build in $(OUTPUT_DIR) yet — nothing to check."; \
		echo "    (P1.3 owns turning BR2_LINUX_KERNEL on in the main defconfig.)"; \
		exit 0; \
	fi; \
	rc=0; \
	grep -qx 'CONFIG_BLK_DEV_INITRD=y' "$$cfg" || { \
		echo "FAIL (I1): CONFIG_BLK_DEV_INITRD is not y in $$cfg" >&2; rc=1; }; \
	grep -q '^CONFIG_INITRAMFS_SOURCE=".\+"' "$$cfg" || { \
		echo "FAIL (I2): CONFIG_INITRAMFS_SOURCE is empty in $$cfg — the kernel has NO" >&2; \
		echo "           initramfs. It will panic on a FAT root at boot." >&2; rc=1; }; \
	[ $$rc -eq 0 ] && echo "==> check-initramfs OK: $$(grep '^CONFIG_INITRAMFS_SOURCE=' $$cfg)"; \
	exit $$rc

# --- zImage_dtb (P1.11 / A3) ----------------------------------------------------
# The REAL hook is BR2_ROOTFS_POST_IMAGE_SCRIPT in configs/mister_de10nano_defconfig
# (board/mister/de10nano/post-image.sh), which Buildroot runs automatically at the
# end of every `$(BR_MAKE) all` and which already fails the build on a contract
# violation -- so `make all` needs no extra step here, unlike check-initramfs above
# (nothing else asserts THAT one).
#
# This target exists for standalone use: iterating on post-image.sh / linux.config
# without a full `make all`, or (until P1.3's Buildroot-level kernel wiring lands)
# pointing it at any pre-built zImage+DTB pair via ZIMAGE_DTB_BINARIES_DIR=, e.g. a
# scratch dir populated from a raw kbuild tree such as work/k-final:
#   make zimage-dtb ZIMAGE_DTB_BINARIES_DIR=/path/to/scratch/images
# (post-image.sh also searches BINARIES_DIR/../build/.../arch/arm/boot/ if the
# image is not directly in BINARIES_DIR -- see its own header.)
ZIMAGE_DTB_BINARIES_DIR ?= $(OUTPUT_DIR)/images
zimage-dtb:
	@mkdir -p $(ZIMAGE_DTB_BINARIES_DIR)
	$(ROOT_DIR)/board/mister/de10nano/post-image.sh $(ZIMAGE_DTB_BINARIES_DIR)

# Deliberately does NOT depend on $(BR_STAMP): `make help` on a fresh clone (or
# with no network) must print something useful rather than trying to fetch a
# tarball first. Buildroot's own target list is behind `make br-help`, which
# does need the tree.
help:
	@echo "MiSTer BR2_EXTERNAL wrapper (TASKS.md P1.1)"
	@echo ""
	@echo "  make mister_de10nano_defconfig  - load configs/mister_de10nano_defconfig"
	@echo "  make menuconfig                 - interactive Buildroot config"
	@echo "  make linux-menuconfig           - interactive kernel config"
	@echo "  make savedefconfig              - save current config back to a defconfig"
	@echo "  make olddefconfig               - non-interactively resolve config to defaults"
	@echo "  make list-defconfigs            - list built-in and external defconfigs"
	@echo "  make buildroot-verify           - download (if needed) + SHA-256-verify the"
	@echo "                                    pinned Buildroot tarball, without unpacking"
	@echo "  make buildroot-showsig          - print upstream's GPG-signed release manifest"
	@echo "                                    (the ONLY valid source for BUILDROOT_SHA256)"
	@echo "  make br-help                    - Buildroot's own target list"
	@echo "  make all                        - build the full image (runs 'initramfs' first)"
	@echo ""
	@echo "Two-stage initramfs (P1.10):"
	@echo "  make initramfs                  - build ONLY the stage-1 cpio and print its size"
	@echo "  make initramfs-menuconfig       - Buildroot menuconfig for the stage-1 config"
	@echo "  make initramfs-busybox-menuconfig - BusyBox menuconfig for the stage-1 BusyBox"
	@echo "  make initramfs-clean            - rm -rf output-initramfs/"
	@echo "  make check-initramfs            - assert the built kernel really embeds the cpio"
	@echo ""
	@echo "zImage_dtb assembly (P1.11):"
	@echo "  make zimage-dtb                 - cat zImage+DTB and run scripts/check-zimage-dtb.sh"
	@echo "                                    (runs automatically at the end of 'make all' via"
	@echo "                                    BR2_ROOTFS_POST_IMAGE_SCRIPT; override the source"
	@echo "                                    dir with ZIMAGE_DTB_BINARIES_DIR=)"
	@echo ""
	@echo "Pinned Buildroot: $(BUILDROOT_VERSION) (BR2_EXTERNAL=$(ROOT_DIR))"
	@echo "Any other target is forwarded verbatim into Buildroot's own Makefile."

br-help: $(BR_STAMP) hostshim
	$(BR_MAKE) help

# Print upstream's clearsigned release manifest, which carries the authoritative
# SHA256 line. Use this — not `sha256sum` of a tarball you just downloaded —
# whenever BUILDROOT_VERSION is bumped.
buildroot-showsig:
	@echo "==> $(BUILDROOT_SIG_URL)"
	@curl -fsSL $(BUILDROOT_SIG_URL) || { \
		echo "FATAL: could not fetch the release signature." >&2; exit 1; }

# Fail fast and by name, the way scripts/inventory/common.sh's mrl_require does,
# rather than dying deep inside a recipe with "curl: command not found".
require-tools:
	@for t in curl tar sha256sum; do \
		command -v $$t >/dev/null 2>&1 || { \
			echo "FATAL: required tool '$$t' not found in PATH." >&2; exit 1; }; \
	done

# --- Download, verify, unpack Buildroot ---------------------------------------

# Plain file-based rule: only fetches if $(BR_TARBALL) isn't already on disk.
# Download to .tmp and rename only on success, so an interrupted transfer can
# never leave a truncated tarball parked at the real path.
$(BR_TARBALL): | require-tools
	@mkdir -p $(DL_DIR)
	@echo "==> Downloading Buildroot $(BUILDROOT_VERSION) from $(BUILDROOT_URL)"
	@curl -fSL --retry 3 -o $@.tmp $(BUILDROOT_URL)
	@mv $@.tmp $@

# Downloads (if needed) and checks the tarball against the pinned hash.
# Standalone and directly invokable so the verification path can be exercised
# (and its failure mode demonstrated) without touching work/buildroot.
buildroot-fetch: $(BR_TARBALL)

buildroot-verify: $(BR_TARBALL)
	@echo "==> Verifying SHA-256 of $(BR_TARBALL)"
	@echo "$(BUILDROOT_SHA256)  $(BR_TARBALL)" | sha256sum -c - >/dev/null 2>&1 || { \
		echo "" >&2; \
		echo "FATAL: SHA-256 mismatch for $(BR_TARBALL)" >&2; \
		echo "  expected: $(BUILDROOT_SHA256)" >&2; \
		echo "  actual:   $$(sha256sum $(BR_TARBALL) | cut -d' ' -f1)" >&2; \
		echo "" >&2; \
		echo "Refusing to unpack a Buildroot tarball that does not match the pinned hash." >&2; \
		echo "" >&2; \
		echo "The cached tarball is corrupt, truncated, or not what upstream published." >&2; \
		echo "To recover, DELETE IT and let it re-download:" >&2; \
		echo "    rm -f $(BR_TARBALL) && make buildroot-verify" >&2; \
		echo "" >&2; \
		echo "Do NOT 'fix' this by pasting the actual hash above into BUILDROOT_SHA256." >&2; \
		echo "That defeats the entire check and would bless a bad tarball. A new hash is" >&2; \
		echo "legitimate ONLY when it comes from upstream's GPG-signed release manifest:" >&2; \
		echo "    make buildroot-showsig BUILDROOT_VERSION=<new-version>" >&2; \
		exit 1; \
	}
	@echo "==> SHA-256 OK ($(BUILDROOT_SHA256))"

# The stamp is the idempotency gate: if work/buildroot/ already holds the
# pinned version (e.g. pre-seeded, as it is in this repo today) this never
# touches the network. Otherwise it downloads, verifies, and unpacks.
$(BR_STAMP):
	@mkdir -p $(WORK_DIR)
	@set -e; \
	if [ -f $(BR_DIR)/Makefile ] && grep -qx 'export BR2_VERSION := $(BUILDROOT_VERSION)' $(BR_DIR)/Makefile 2>/dev/null; then \
		echo "==> Buildroot $(BUILDROOT_VERSION) already present at $(BR_DIR); skipping download/unpack"; \
	else \
		$(MAKE) --no-print-directory buildroot-verify; \
		echo "==> Unpacking Buildroot $(BUILDROOT_VERSION) to $(BR_DIR)"; \
		rm -rf $(BR_DIR); \
		mkdir -p $(BR_DIR); \
		tar -C $(BR_DIR) --strip-components=1 -xf $(BR_TARBALL); \
	fi
	@touch $@

buildroot-unpack: $(BR_STAMP)

# --- Forward everything else into Buildroot ------------------------------------
# make menuconfig, make linux-menuconfig, make savedefconfig, make
# mister_de10nano_defconfig (Buildroot's own %_defconfig rule finds it under
# this tree's configs/, since BR2_EXTERNAL is set above), etc.
%: $(BR_STAMP) hostshim
	$(BR_MAKE) $@
