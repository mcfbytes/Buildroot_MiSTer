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

# Buildroot invocation shared by every forwarded target. BR2_EXTERNAL is passed
# explicitly here rather than exported: a command-line assignment overrides the
# environment anyway, so an export would just be a redundant second source of
# truth that can drift out of sync with this one.
BR_MAKE = $(MAKE) -C $(BR_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(ROOT_DIR) BR2_DL_DIR=$(DL_DIR)

# Bare `make` must NOT be `all`. The P1.1 defconfig deliberately sets no arch or
# toolchain, so Buildroot would fall back to its own defaults (BR2_i386 +
# internal toolchain) and a reflexive `make` would spend an hour compiling an
# x86 toolchain and rootfs that nothing in this project wants. P1.2 gives the
# defconfig real content; until then, and arguably after, `help` is the right
# thing to get for free.
.DEFAULT_GOAL := help

.PHONY: all help buildroot-fetch buildroot-verify buildroot-unpack buildroot-showsig require-tools

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

# `make` with no target builds the full image, same as bare Buildroot.
all: $(BR_STAMP)
	$(BR_MAKE) all

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
	@echo "  make all                        - build the full image"
	@echo ""
	@echo "Pinned Buildroot: $(BUILDROOT_VERSION) (BR2_EXTERNAL=$(ROOT_DIR))"
	@echo "Any other target is forwarded verbatim into Buildroot's own Makefile."

br-help: $(BR_STAMP)
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
%: $(BR_STAMP)
	$(BR_MAKE) $@
