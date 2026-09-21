################################################################################
#
# itsalive
#
################################################################################

# ItsAlive_MiSTer: bring up HDMI + /dev/fb0 on a MiSTer with no Main_MiSTer
# running. Ships in the SD-card installer initramfs (configs/
# mister_installer_defconfig) to draw the first-boot "installing, do not power
# off" splash -- ADR 0020 section 9, issue #185. Upstream Buildroot 2026.08 has
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
#   2. THE BINARY IS STATIC WITHOUT ANY FLAG FROM THIS FILE. rustc's
#      *-linux-musl targets default to `+crt-static`, so under the installer's
#      musl toolchain cargo links a fully static executable on its own. The
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
ITSALIVE_VERSION = ac13a064672e0408f2ad1055d64f60ec726deffb
ITSALIVE_SITE = $(call github,mcfbytes,ItsAlive_MiSTer,$(ITSALIVE_VERSION))
ITSALIVE_LICENSE = GPL-3.0+
ITSALIVE_LICENSE_FILES = LICENSE

$(eval $(cargo-package))
