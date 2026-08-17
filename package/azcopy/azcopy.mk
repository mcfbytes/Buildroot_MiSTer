################################################################################
#
# azcopy
#
################################################################################

# Microsoft's AzCopy: the command-line client for Azure Blob / Azure Files /
# Azure Data Lake Storage. Upstream Buildroot 2026.05.1 has no azcopy package
# (checked: work/buildroot/package/azcopy does not exist; the only "az*"
# package in the pinned tree is azure-iot-sdk-c), so this authors one.
#
# WHAT IT IS FOR HERE. Off-device backup of the exFAT data partition -- saves,
# screenshots, config, and the handful of small files under /media/fat/linux
# that a Linux update overwrites -- to Azure Storage, over the network the
# board already has, without an intervening PC. `azcopy sync` is the operative
# subcommand: it is incremental and restartable, which matters a great deal
# over a 100 Mbit link driven by a 800 MHz dual-core Cortex-A9.
#
# NOT ENABLED BY DEFAULT. configs/mister_de10nano_defconfig leaves
# BR2_PACKAGE_AZCOPY unset on size grounds alone: 39.1 MiB installed would make
# this the second-largest package in the image after samba4, for a tool most
# owners will never run. It is published as a standalone download instead. The
# package is complete and tested; it is one uncommented line away.
#
# READ docs/azcopy.md BEFORE TOUCHING THIS PACKAGE. It carries the size
# accounting (including why a file-transfer CLI is 39 MiB -- Google Cloud
# Storage support alone measures +26.4 MB against an empty Go binary), the
# ARMv7 support analysis, and the record of it running on real hardware
# against a real storage account -- which matters, because Microsoft does not
# build or test AzCopy for 32-bit ARM at all.
#
# THIS IS THE FIRST GO PACKAGE IN THE IMAGE. Three consequences worth knowing
# before the first build surprises you:
#
#   1. It drags in host-go, which Buildroot builds FROM SOURCE by default on
#      an x86_64 host (BR2_PACKAGE_HOST_GO_SRC is the default when
#      BR2_PACKAGE_HOST_GO_BOOTSTRAP_STAGE5_ARCH_SUPPORTS, see
#      work/buildroot/package/go/Config.in.host). That is a real, one-off
#      addition to cold CI wall-clock. It is left at the default rather than
#      switched to host-go-bin: go-bin downloads a pre-built toolchain
#      tarball, and "build the compiler from source" is the posture the rest
#      of this tree already takes.
#   2. The tarball this package hashes is NOT the GitHub archive. Buildroot's
#      golang infrastructure sets <PKG>_DOWNLOAD_POST_PROCESS = go, which runs
#      `go mod vendor` and repacks -- see azcopy.hash for the whole story and
#      the exact command to regenerate the hash on a version bump.
#   3. Consequently scripts/hash-sync-github-packages.sh CANNOT cover this
#      package and azcopy is deliberately absent from HASH_SYNC_PACKAGES in
#      .github/workflows/renovate-hash-sync.yml. Renovate still proposes the
#      version bump (renovate.json has a custom manager for the line below);
#      the bump PR then fails closed on the stale hash until a human runs the
#      regeneration recipe. Same fail-closed posture as the RT kernel pin.

# PLAIN VERSION, "v" RECONSTRUCTED IN THE SITE LINE -- deliberately NOT the
# package/dualsensectl and package/munt convention of keeping the tag's "v" or
# full tag text inside <PKG>_VERSION. That convention exists solely to keep
# scripts/hash-sync-github-packages.sh's generic loop working (it uses the
# literal *_VERSION string as both the archive ref and the .hash filename
# stem). This package is not in that loop and never can be (point 3 above), so
# the constraint does not apply and the plain upstream version number -- which
# is what `azcopy --version` prints, and what AzcopyVersion in common/version.go
# hardcodes -- is the more useful thing to have in the variable.
AZCOPY_VERSION = 10.32.7
AZCOPY_SITE = $(call github,Azure,azure-storage-azcopy,v$(AZCOPY_VERSION))

# MIT, per the LICENSE file at the repo root -- read, not inferred; its first
# three lines are "The MIT License (MIT)" / blank / "Copyright (c) 2017
# Microsoft <wastore@microsoft.com>" (the copyright sign is the U+00A9
# character in the file, spelled out here to keep this .mk ASCII).
# NOTICE.txt is listed
# alongside it because it is where Microsoft enumerates the third-party
# licenses of everything AzCopy links in (MIT, Apache-2.0 and BSD-2/3-Clause
# among them); the golang infrastructure additionally appends ", vendored
# dependencies licenses probably not listed" to <PKG>_LICENSE on its own
# (pkg-golang.mk), which is accurate and left alone.
AZCOPY_LICENSE = MIT
AZCOPY_LICENSE_FILES = LICENSE NOTICE.txt

# NO AZCOPY_CPE_ID_VENDOR / _PRODUCT, and their absence is a finding rather than
# an omission. `cpe:2.3:a:microsoft:azcopy` LOOKS like the obvious value and does
# not exist: the NVD CPE dictionary was queried at pin time (2026-08-17) for
# `cpe:2.3:a:microsoft:azcopy`, for `cpe:2.3:a:microsoft:azure_storage`, and for
# the bare keyword "azcopy", and all three return zero products. Setting a
# plausible-looking CPE that matches no dictionary entry is worse than setting
# none: it would make `make pkg-stats` and any downstream SBOM consumer report a
# confident identifier that silently matches no CVE feed. Buildroot's default
# (`cpe:2.3:a:azcopy_project:azcopy`) is at least honestly wrong. Revisit if NVD
# ever assigns one -- AzCopy vulnerabilities have historically been published
# under the Azure SDK/Storage advisories rather than a product CPE of its own.

# The Go module path carries a /v10 major-version suffix (go.mod line 1:
# "module github.com/Azure/azure-storage-azcopy/v10"). pkg-golang.mk infers
# <PKG>_GOMOD from the SITE URL, which would give it without the suffix and
# make `go build <gomod>/.` fail to resolve. Same override, same reason, as
# upstream's package/gocryptfs (/v2).
AZCOPY_GOMOD = github.com/Azure/azure-storage-azcopy/v10

# NOT SET, on purpose:
#
#   AZCOPY_LDFLAGS   -- there is no -X version stamp to inject. AzCopy carries
#                       its version as a plain source constant
#                       (common/version.go: `const AzcopyVersion = "10.32.7"`),
#                       so the binary self-reports correctly with no link-time
#                       help. Verified by running the built ARMv7 binary:
#                       `azcopy --version` -> "azcopy version 10.32.7".
#   AZCOPY_TAGS      -- upstream's own release pipeline builds the Linux
#                       binaries with no build tags; there is no "minimal" or
#                       "no cloud X" tag to trim with. (The *_se_* release
#                       assets are a separate Microsoft-internal build, not a
#                       tag on this tree.)
#   AZCOPY_BUILD_TARGETS -- the main package is at the module root (main.go),
#                       which is pkg-golang.mk's default of ".". That default
#                       is also what names the binary `azcopy` rather than
#                       `azure-storage-azcopy`, via <PKG>_BIN_NAME defaulting
#                       to the package directory name.
#
# CGO is left wherever the toolchain lands it. HOST_GO_TARGET_ENV sets
# CGO_ENABLED=1 whenever BR2_PACKAGE_HOST_GO_TARGET_CGO_LINKING_SUPPORTS is
# set, which it is for this glibc/NPTL/shared-libs config, so the binary comes
# out dynamically linked against libc.so.6 and libresolv.so.2 -- both already
# in the image (output/target/lib/libresolv.so.2 exists; it is part of glibc,
# not a new dependency). The package also builds and runs correctly with
# CGO_ENABLED=0, so nothing here depends on that choice; the difference
# measured on the stripped ARMv7 binary was 62,636 bytes (41,007,016 with cgo
# vs 40,944,380 without), and the cgo build is the one that gets glibc's NSS
# resolver rather than Go's pure-Go one.

# /etc/profile.d/azcopy.sh -- environment defaults this board needs. Read that
# file; its comments are the authority. The short version is that AzCopy's own
# defaults put job-plan files and logs on a rootfs that gets reflashed wholesale
# and sizes its buffer cache at 1 GiB on a board with 511 MiB of RAM.
#
# INSTALLED BY THE PACKAGE, not by board/mister/de10nano/rootfs-overlay/. An
# overlay file has no view of BR2_PACKAGE_AZCOPY and would ship into every
# image, including the ones that (today, by default) have no azcopy binary at
# all. Installing it here ties it to the package that needs it, which is what
# the pkg-golang default INSTALL_TARGET_CMDS is extended for rather than
# replaced -- the binary install below is a copy of pkg-golang.mk's own, since
# defining <PKG>_INSTALL_TARGET_CMDS suppresses the default entirely.
define AZCOPY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/azcopy $(TARGET_DIR)/usr/bin/azcopy
	$(INSTALL) -D -m 0644 $(AZCOPY_PKGDIR)/azcopy-profile.sh \
		$(TARGET_DIR)/etc/profile.d/azcopy.sh
endef

$(eval $(golang-package))
