#!/usr/bin/env bash
#
# scripts/lib/board-expectations.sh — per-board expected-symbol tables for
# the arch/toolchain guards in scripts/check-kernel-defconfig-sync.sh and
# .github/actions/buildroot-build/action.yml. Not directly executable;
# sourced, same convention as scripts/lib/hash-sync-common.sh and
# scripts/ci-lib.sh (see either file's own header for the sourcing shape:
# a repo-root-relative `source scripts/lib/board-expectations.sh` from a
# workflow/composite-action `run:` block, or
# `. "$SCRIPT_DIR/lib/board-expectations.sh"` from another script under
# scripts/, resolved off ${BASH_SOURCE[0]}, not CWD).
#
# docs/de25-readiness-ledger.md §5.2 is this file's spec; §5.3-§5.4 explain
# each row, §5.7 the fail-closed properties both consumers must preserve.
#
# Adding a board means adding a row to EVERY array below — there is
# deliberately no fallback row and no wildcard match. An inference from an
# existing row (e.g. "this board is also aarch64, so reuse that row") is
# exactly the failure this design forbids: a missing row must be a loud
# error, never a silent, possibly-wrong inherited guess. See §5.2's "Why an
# explicit BOARD string key, not something derived".
#
# Both consumers key on an explicit BOARD string (env var or argument),
# defaulting to "de10nano" — NOT derived from a defconfig filename stem
# (that conflates the board axis with the variant axis
# .github/actions/buildroot-build/action.yml already has) and NOT derived
# by reading BR2_arm vs BR2_aarch64 back out of a defconfig and picking a
# generic row (that would let a future board silently inherit an existing
# one). Each row is an affirmative, reviewed claim.
#
# shellcheck disable=SC2034 # every name below (BOARD_COMMON_SENTINELS,
#   BOARD_COMMON_FAMILIES, BOARD_ARCH_SENTINELS, BOARD_ARCH_FAMILIES,
#   BOARD_FINGERPRINT_SENTINELS) is read by the sourcing consumers
#   (scripts/check-kernel-defconfig-sync.sh, .github/actions/
#   buildroot-build/action.yml), not by this file itself, so shellcheck's
#   single-file analysis can't see the use.

# Arch-independent sentinels/families every board shares (KERNEL_HEADERS is a
# choice under package/linux-headers, TOOLCHAIN_BUILDROOT_CXX is under
# package/gcc — neither varies by board, so neither is duplicated per row).
BOARD_COMMON_SENTINELS="BR2_KERNEL_HEADERS BR2_TOOLCHAIN_BUILDROOT_CXX"
BOARD_COMMON_FAMILIES="BR2_KERNEL_HEADERS BR2_TOOLCHAIN_BUILDROOT_"

# Sentinel symbols check-kernel-defconfig-sync.sh's `for must in ...` assert
# requires present in configs/mister_kernel_defconfig (its :83, pre-change).
# Merge order for a consumer is ARCH ROW FIRST, then BOARD_COMMON_SENTINELS —
# see that script for why the order matters (byte-identity with today's
# literal list, so docs/de25-readiness-ledger.md §5.6's migration check is
# meaningful).
declare -A BOARD_ARCH_SENTINELS=(
	[de10nano]="BR2_arm BR2_cortex_a9"
	# [U] — confirm against configs/mister_de25nano_defconfig when it lands.
	# BR2_aarch64 is the live arch choice (docs/de25-readiness-ledger.md
	# §5.4); BR2_cortex_a76_a55 is D2.1's CPU pick, not yet verified against
	# a real defconfig.
	[de25nano]="BR2_aarch64 BR2_cortex_a76_a55"
)

# Family PREFIXES for the `for family in ...` symbol-name-set assert (its
# :129, pre-change) — see that script's header §3 for why a kconfig CHOICE
# needs a name-set comparison, not a value comparison. Same arch-row-first,
# then BOARD_COMMON_FAMILIES merge order as the sentinels above.
declare -A BOARD_ARCH_FAMILIES=(
	[de10nano]="BR2_arm BR2_ARM_ BR2_cortex"
	# [U] — confirm against configs/mister_de25nano_defconfig when it lands.
	# BR2_ARM_ is carried over unchanged (docs/de25-readiness-ledger.md
	# §5.4): both 32- and 64-bit cores share the BR2_cortex_* namespace, and
	# an aarch64 defconfig populating no BR2_ARM_* symbol is a legitimate
	# empty-set match, not a failure.
	[de25nano]="BR2_aarch64 BR2_ARM_ BR2_cortex"
)

# Toolchain-fingerprint sentinel PATTERNS for
# .github/actions/buildroot-build/action.yml's `for must in ...` assert (its
# :190-195, pre-change) — grep -q patterns against the stripped fingerprint,
# not plain symbol names (hence the leading '^').
declare -A BOARD_FINGERPRINT_SENTINELS=(
	[de10nano]="^BR2_arm ^BR2_cortex"
	# [U] — confirm against configs/mister_de25nano_defconfig when it lands.
	[de25nano]="^BR2_aarch64 ^BR2_cortex"
)
