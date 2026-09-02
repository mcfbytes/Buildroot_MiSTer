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
# NOT ENABLED BY DEFAULT. configs/fragments/de10nano-image.fragment leaves
# BR2_PACKAGE_AZCOPY unset on size grounds alone: 39.1 MiB installed would make
# this the second-largest package in the image after samba4, for a tool most
# owners will never run. The package is complete and tested; it is one
# uncommented line away.
#
# IT IS STILL SHIPPED, just not in the image: release.yml's `build-azcopy` job
# builds it on every tag and attaches azcopy-<version>-armv7.xz to the release.
# That build passes CGO_ENABLED=0 via AZCOPY_GO_ENV on the make command line --
# deliberately NOT set in this file, because static is a property of the
# DOWNLOAD (which outlives the rootfs that installed it and must survive a
# rollback to an older or stock image), not of an in-image azcopy, which should
# keep cgo and glibc's NSS resolver. See docs/ci.md#azcopy-release-asset.
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
#      work/buildroot/package/go/Config.in.host). Measured, so nobody has to
#      fear it: the five bootstrap stages take 3.0 min and host-go-src another
#      1.2 min, and azcopy itself compiles in 12 s. Wall clock is not the
#      problem; DISK is -- the module cache measured 1.7 GiB. It is left at
#      the from-source default rather than switched to host-go-bin (which
#      downloads a pre-built toolchain tarball), because "build the compiler
#      from source" is the posture the rest of this tree already takes.
#   2. The tarball this package hashes is NOT the GitHub archive. Buildroot's
#      golang infrastructure sets <PKG>_DOWNLOAD_POST_PROCESS = go, which runs
#      `go mod vendor` and repacks -- see azcopy.hash for the whole story and
#      the exact command to regenerate the hash on a version bump.
#   3. Consequently scripts/hash-sync-github-packages.sh CANNOT cover this
#      package and azcopy is deliberately absent from HASH_SYNC_PACKAGES in
#      .github/workflows/renovate-hash-sync.yml -- that loop's method is
#      `curl <archive-url> | sha256sum`, which here would hash the
#      PRE-vendoring archive and write a confidently wrong value. That
#      exclusion is permanent.
#
#      What is NOT permanent, and changed on 2026-08-28: the hash is now
#      refreshed automatically anyway, by a case of its own --
#      scripts/hash-sync-azcopy.sh (case 7), which REBUILDS the -go2 tarball
#      using Buildroot's own support/download/go-post-process and Buildroot's
#      own pinned Go, then hashes the result. package/azcopy/azcopy.mk is
#      therefore IN that workflow's `paths:` filter while staying out of
#      HASH_SYNC_PACKAGES; the two allow-lists disagree for this one package
#      on purpose. Older commits (and this file's own header before that date)
#      still say the hash "CANNOT be auto-refreshed" -- read that as "cannot
#      be curl'd", which remains true.
#
#      The manual recipe in azcopy.hash is not retired: it is still the local
#      procedure, and the fallback whenever case 7 records a skip. The bump PR
#      still fails closed on a stale hash either way -- lint.yml's "azcopy
#      version/hash pin consistency" step is what makes that true.

# PLAIN VERSION, "v" RECONSTRUCTED IN THE SITE LINE -- deliberately NOT the
# package/dualsensectl and package/munt convention of keeping the tag's "v" or
# full tag text inside <PKG>_VERSION. That convention exists solely to keep
# scripts/hash-sync-github-packages.sh's generic loop working (it uses the
# literal *_VERSION string as both the archive ref and the .hash filename
# stem). This package is not in that loop and never can be (point 3 above), so
# the constraint does not apply and the plain upstream version number -- which
# is what `azcopy --version` prints, and what AzcopyVersion in common/version.go
# hardcodes -- is the more useful thing to have in the variable.
AZCOPY_VERSION = 10.32.8
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
#                       (common/version.go: `const AzcopyVersion = "10.32.8"`),
#                       so the binary self-reports correctly with no link-time
#                       help. Verified by running the built ARMv7 binary:
#                       `azcopy --version` -> "azcopy version 10.32.7"
#                       (verified at the 10.32.7 pin; the constant tracks the
#                       tag, so 10.32.8 self-reports 10.32.8).
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

# --- TEMPORARY: vendor through the module proxy (upstream moved a tag) --------
#
# ADDED 2026-08-28, for the 10.32.7 -> 10.32.8 bump. DELETE THIS BLOCK the
# moment it stops being needed -- scripts/hash-sync-azcopy.sh tells you when,
# loudly and on every bump PR (see "HOW THIS BLOCK GETS REMOVED" below). It is
# a deviation from stock Buildroot behaviour and must not outlive its cause.
#
# WHAT BROKE. pkg-golang.mk vendors with GOPROXY=direct, i.e. `go mod vendor`
# fetches every module straight from its origin VCS. AzCopy 10.32.8's go.sum
# names github.com/googleapis/enterprise-certificate-proxy v0.3.21, and that
# project MOVED the v0.3.21 git tag after publishing it:
#
#   proxy.golang.org / go.sum record it at 82da9ba (2026-08-11, "chore: Bump
#   version from v0.3.20 to v0.3.21"); the tag in the repository now points at
#   3afb37a (2026-08-14), two bugfix commits later.
#
# A tag is mutable; a published module version is not. So a direct fetch gets
# bytes that can never satisfy go.sum, and the vendoring dies:
#
#   verifying github.com/googleapis/enterprise-certificate-proxy@v0.3.21:
#   checksum mismatch
#       downloaded: h1:EwROawv3cMS8uI2hnx2pwAosDYo3UJQ9RygfjgZeYcE=
#       go.sum:     h1:OFdQ3tnCX/zaQ0Cedur3D3z7kI6HiLX9g3TiAN4/DFU=
#
# That is `make azcopy` failing at DOWNLOAD, on any cold dl/ cache -- including
# release.yml's build-azcopy job, which builds this package on every tag.
#
# WHY THIS IS NOT A WEAKENING, and why a patch cannot fix it instead. Every
# module is still verified against AzCopy's own go.sum, which is itself
# checkable against the sum.golang.org transparency log; nothing here disables
# a check. All this changes is WHERE the bytes are fetched from, and the proxy
# is the immutable, log-attested copy of exactly the bytes go.sum names -- the
# git tag is the mutable one. (A package/azcopy/*.patch correcting the go.sum
# line could not work at all: `go mod vendor` runs inside the DOWNLOAD step,
# in support/download/go-post-process, and the tarball is hashed before
# Buildroot ever extracts it to output/build and applies patches. There is no
# hook in between. It would also mean trusting the moved tag over the attested
# bytes, which is the wrong direction.)
#
# WHY AZCOPY_DL_ENV AND NOT AZCOPY_GO_ENV. Both would override pkg-golang.mk's
# GOPROXY=direct, but AZCOPY_GO_ENV is a MAKE VARIABLE that release.yml sets on
# the command line (`make azcopy AZCOPY_GO_ENV=CGO_ENABLED=0`, see
# docs/ci.md#azcopy-release-asset) -- and a command-line assignment REPLACES
# the makefile's value outright, which would silently drop this override in the
# one job that most needs it. AZCOPY_DL_ENV is download-only and nothing
# overrides it. It must be appended AFTER $(eval $(golang-package)) above:
# pkg-golang.mk does its own `AZCOPY_DL_ENV += ... GOPROXY=direct ...` inside
# that eval, and DL_ENV is emitted as a shell command prefix, where the LAST
# assignment of a variable wins.
#
# HOW THIS BLOCK GETS REMOVED. scripts/hash-sync-azcopy.sh (renovate-hash-sync
# case 7) always attempts GOPROXY=direct FIRST and only falls back to the value
# on the line below. When direct succeeds it emits a ::notice:: saying this
# block is obsolete. That is safe to act on: a module that verifies against
# go.sum has byte-identical content whichever source served it, so the two
# paths produce the same vendor tree and the same -go2 tarball hash. In
# practice this will clear itself when AzCopy ships a release whose go.sum no
# longer names enterprise-certificate-proxy v0.3.21.
AZCOPY_DL_ENV += GOPROXY=https://proxy.golang.org,direct
