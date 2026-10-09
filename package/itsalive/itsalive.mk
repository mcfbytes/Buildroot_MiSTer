################################################################################
#
# itsalive
#
################################################################################

# ItsAlive_MiSTer: bring up HDMI + /dev/fb0 on a MiSTer with no Main_MiSTer
# running. Ships in the SD-card installer initramfs (configs/
# mister_installer_defconfig) to draw the first-boot "installing, do not power
# off" splash -- ADR 0020 section 9, issue #185 -- and, built by the DE10
# configuration, into the stage-1 cpio for the boot-time exFAT repair's splash
# (ADR 0026 section 6; not into the rootfs). Upstream Buildroot 2026.08 has
# no such package (checked: nothing under work/buildroot/package/its*).
#
# THE FIRST CARGO PACKAGE IN THIS TREE. Three things worth knowing:
#
#   1. host-rustc is pulled in automatically by $(cargo-package) and resolves
#      to host-rust-bin: a ~200 MB prebuilt toolchain download plus a ~30 MB
#      rust-std for the target triple, no compile. The triple Buildroot derives
#      for the installer (armv7 + EABIHF + musl) is armv7-unknown-linux-
#      musleabihf, a Tier-2 platform whose std tarball package/rust-bin/
#      rust-bin.hash already pins.
#
#   2. THE BINARY IS STATIC. rustc's *-linux-musl targets default to
#      `+crt-static`, so under the installer's musl toolchain cargo links a
#      fully static executable on its own; on the main glibc toolchain
#      ITSALIVE_CARGO_ENV below asks for it (2026-10-08). The
#      crate's own .cargo/config.toml also asks for rust-lld and +crt-static so
#      that upstream's CI can cross-link with nothing installed; Buildroot's
#      cargo infrastructure hands cargo its linker and rustflags through
#      CARGO_TARGET_<TRIPLE>_LINKER / _RUSTFLAGS environment variables, which
#      cargo ranks ABOVE a config file, so the two do not fight: Buildroot's
#      arm-buildroot-linux-musleabihf-gcc does the link. Verified on the first
#      build: `file` reports "statically linked" (package/itsalive/itsalive.hash
#      header records the measurement).
#
#   3. THE .hash LINE IS NOT THE HASH OF THE GITHUB TARBALL. $(cargo-package)
#      sets ITSALIVE_DOWNLOAD_POST_PROCESS = cargo, so what lands in dl/ -- and
#      what is checked -- is the post-`cargo vendor` itsalive-<sha>-cargo6.tar.gz
#      repacked by Buildroot's own support/download/helpers. Same situation as
#      azcopy's -go2 tarball; read package/itsalive/itsalive.hash before touching
#      the value, and NEVER add this package to renovate-hash-sync.yml's
#      HASH_SYNC_PACKAGES (case 1's curl-and-hash loop would write a
#      plausible-looking wrong value).
#
# Pinned to a commit on master, not a tag: the project cuts no releases, and
# renovate.json's git-refs manager for it tracks master's HEAD exactly like the
# out-of-tree driver pins. The pinned commit is the one the 2026-09-21 rig
# session verified on a DE10-Nano (ItsAlive_MiSTer docs/testlogs/).
ITSALIVE_VERSION = 797378a7d06f9e1175151a18b98e64d17aa79a77
ITSALIVE_SITE = $(call github,mcfbytes,ItsAlive_MiSTer,$(ITSALIVE_VERSION))
ITSALIVE_LICENSE = GPL-3.0+
ITSALIVE_LICENSE_FILES = LICENSE

# Static on glibc too (on musl it already is): the main configuration's
# stage-1 initramfs has no libc. Replaces pkg-cargo.mk's ARM RUSTFLAGS, so
# its one flag is repeated here; the later assignment wins.
ITSALIVE_CARGO_ENV = \
	CARGO_TARGET_$(call UPPERCASE,$(RUSTC_TARGET_NAME))_RUSTFLAGS="-Clink-arg=-Wl,--allow-multiple-definition -Ctarget-feature=+crt-static"

ITSALIVE_BIN = $(ITSALIVE_DIR)/target/$(RUSTC_TARGET_NAME)/$(if $(BR2_ENABLE_DEBUG),debug,release)/itsalive

# Built for the stage-1 cpio only, which copies ITSALIVE_BIN.
ifeq ($(BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE),y)
ITSALIVE_INSTALL_TARGET = NO
endif

$(eval $(cargo-package))
