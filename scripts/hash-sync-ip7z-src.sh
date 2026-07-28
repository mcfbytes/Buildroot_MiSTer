#!/usr/bin/env bash
#
# hash-sync-ip7z-src.sh — case 3 of 4 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): refresh the
# bespoke ip7z/7zip release-asset tarball hashes.
#
# RENAMED 2026-07-27 from hash-sync-lzma-sdk.sh, and generalised from one
# package to a TABLE, because a second package now pins the very same upstream
# release asset:
#
#   package/lzma-sdk  -- 8 .c files out of the archive's C/ dir compiled into
#                        liblzma-sdk.so for Main_MiSTer/libchdr
#   package/7zip      -- the CPP/ application, `7zz`, plus the statically
#                        linked /media/fat/linux/7za the Downloader needs
#                        (ADR 0023)
#
# Both resolve to https://github.com/ip7z/7zip/releases/download/<ver>/
# 7z<verdigits>-src.tar.xz. Their renovate.json custom managers share
# depNameTemplate "ip7z/7zip", so Renovate raises ONE PR touching both .mk
# files and this one step refreshes both .hash files. A table (rather than two
# near-identical scripts) is what keeps that true as more consumers of this
# archive appear.
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's "Refresh
# ip7z/7zip release-asset tarball hashes" step invokes this script directly
# (from the .hash-sync-tools checkout of the workflow's own ref -- see that
# step's comment in the .yml); there is no separate inline copy of this
# logic left in the workflow. THIS SCRIPT IS AUTHORITATIVE: fix bugs in this
# case here, not in the .yml.
#
# Extracted so this case is independently testable against a fixture -- see
# "Testing against a fixture" below. This case has NEVER run against a real
# PR (per TASKS.md's "renovate-hash-sync.yml — remaining unproven refresh
# paths" item and docs/renovate.md's "Unverified / what to check on first
# run" section, which name it as one of the three untested cases), which is
# exactly why it gets its own fixture-shaped entry point rather than staying
# folded into a 700-line workflow file.
#
# Bespoke, NOT part of the generic github-packages loop (case 1,
# scripts/hash-sync-github-packages.sh): these tarballs are GitHub release
# ASSETS, not $(call github,...) commit/tag archives, and the filename is
# derived from the version with the dots stripped (<PKG>_SOURCE =
# 7z$(subst .,,<PKG>_VERSION)-src.tar.xz, so 26.02 -> 7z2602-src.tar.xz).
# Trust model is the same as case 1's: upstream publishes no checksums
# anywhere (checked at pin time -- see each .hash file's own header), so a
# locally-computed sha256 of the freshly-fetched asset is the legitimate
# source. Only the FIRST sha256 line (the tarball) is rewritten in each file;
# the DOC/License.txt and DOC/readme.txt provenance lines beneath it are left
# untouched -- if one of those legitimately changed too, the build's own hash
# check fails closed and a human re-derives that line by hand.
#
# The asset is fetched ONCE PER PACKAGE, not once per distinct version. Two
# packages pinned at the same version therefore download the same ~1.5 MB
# twice. That is deliberate: each package's hash is then derived from its own
# fetch (independent verification, no shared-state assumption), and a
# transiently DIVERGENT pin pair -- 7zip already bumped, lzma-sdk not yet, or
# vice versa -- needs no special case to work correctly.
#
# Usage:
#   scripts/hash-sync-ip7z-src.sh [REPO_ROOT]
#   REPO_ROOT defaults to this repo's root. Pass a fixture directory to
#   exercise this case in isolation -- see "Testing against a fixture" below.
#
# Required env:
#   HASH_SYNC_OUTCOMES_FILE   bare filename (production; $RUNNER_TEMP-
#                             prefixed) or an absolute path (standalone/
#                             fixture use) -- see
#                             scripts/lib/hash-sync-common.sh.
#
# Optional env:
#   GITHUB_ENV, RUNNER_TEMP   set automatically by Actions; see
#                             scripts/lib/hash-sync-common.sh for the
#                             standalone-safe fallback behavior of each.
#
# Sets (via hash_sync_set_env), one per table row:
#   LZMA_SDK_HASH_CHANGED=0|1
#   SEVENZIP_HASH_CHANGED=0|1
# Note the second name is NOT "7ZIP_HASH_CHANGED": an environment variable
# cannot begin with a digit, and $GITHUB_ENV would reject it. The Make
# namespace in the .mk file has no such restriction (7ZIP_VERSION is valid and
# has upstream precedent -- package/18xx-ti-utils), so the two spellings
# differ on purpose.
#
# Records ONE row PER PACKAGE to $HASH_SYNC_OUTCOMES_FILE, under the pin names
# "lzma-sdk" and "7zip": refreshed | already-current | skipped | failed.
# APPENDS -- does not truncate; scripts/hash-sync-github-packages.sh (case 1)
# owns creating/truncating the shared outcomes file for the run. Standalone,
# `touch` the file yourself first if case 1 has not run.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- this runs as its own workflow step, and an
# `exit 1` here would skip case 4 entirely. Note the per-package handled paths
# `return 0` to the caller's loop rather than exiting the script, which the
# single-package version did: one package failing to parse or download must
# not silently skip the other one's refresh.
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing fake package/<pkg>/<pkg>.mk files (each just needs a
# <VAR> = <ver> line) and fake package/<pkg>/<pkg>.hash files (a
# "sha256  ...  7z<verdigits>-src.tar.xz" line plus any provenance lines
# beneath it, to confirm those survive untouched). Either let it really
# fetch real ip7z/7zip release assets, or prepend a fake `curl` to $PATH
# that serves a fixture asset:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-ip7z-src.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and each rewritten .hash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

usage() {
	echo "usage: $(basename "$0") [REPO_ROOT]" >&2
	exit 2
}

[ "$#" -le 1 ] || usage

REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
[ -d "$REPO_ROOT" ] || { echo "::error::REPO_ROOT '$REPO_ROOT' is not a directory" >&2; exit 2; }

: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

# One row per package that pins an ip7z/7zip release asset:
#   <package dir, which is also the .mk/.hash basename>|<Make version
#   variable>|<env var to set>
# The pin name recorded in the outcomes file is the package dir name. Add a
# row here when a third package starts consuming this archive; nothing else in
# this script needs touching. Keep renovate.json's custom managers and
# renovate-hash-sync.yml's `paths:` filter in step with any addition -- both
# are explicit allow-lists, and an omission in either is SILENT (the workflow
# simply never fires, leaving a bumped version against a stale hash, which
# then reads like a tampered upstream rather than missing CI wiring).
IP7Z_PACKAGES=(
	"lzma-sdk|LZMA_SDK_VERSION|LZMA_SDK_HASH_CHANGED"
	"7zip|7ZIP_VERSION|SEVENZIP_HASH_CHANGED"
)

# sync_one <outcomes-file> <pkg> <version-var> <env-var>
# Handles exactly one package. Always returns 0 -- the caller's loop must keep
# going regardless of this package's outcome.
sync_one() {
	local outcomes_file="$1" pkg="$2" version_var="$3" env_var="$4"
	local mk="package/$pkg/$pkg.mk"
	local hashfile="package/$pkg/$pkg.hash"

	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping $pkg"
		hash_sync_record "$outcomes_file" "$pkg" skipped "$mk or $hashfile not found in this checkout"
		hash_sync_set_env "$env_var" 0
		return 0
	fi

	# `|| true` for the same reason as case 1's extractions: without it a
	# zero-match grep under `set -euo pipefail` kills the script at the
	# assignment and the handled branch below never executes.
	local version
	version=$(grep -E "^${version_var}[[:space:]]*=" "$mk" | head -1 \
	           | sed -E "s/^${version_var}[[:space:]]*=[[:space:]]*//" || true)
	if [ -z "$version" ]; then
		# Parsing our OWN .mk file -- same class of bug as the github-loop
		# and kernel parse/extract failures, so this is a FAIL (via the
		# recorded outcome), not a warn-and-continue.
		echo "::error::could not parse $version_var from $mk"
		hash_sync_record "$outcomes_file" "$pkg" failed \
			"could not parse $version_var from $mk -- workflow regex bug, not a network issue; build still fails closed on the stale hash"
		hash_sync_set_env "$env_var" 0
		return 0
	fi

	local asset url tmpfile
	asset="7z$(echo "$version" | tr -d .)-src.tar.xz"
	url="https://github.com/ip7z/7zip/releases/download/${version}/${asset}"
	echo "==> $pkg $version: fetching $url"
	tmpfile=$(mktemp)
	if ! curl -fsSL --retry 3 "$url" -o "$tmpfile"; then
		# A download failure against an upstream release asset is a
		# legitimate network blip -- stays warn-and-continue.
		echo "::warning::could not download $url -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$pkg" skipped "could not download $url"
		rm -f "$tmpfile"
		hash_sync_set_env "$env_var" 0
		return 0
	fi
	local newhash
	newhash=$(sha256sum "$tmpfile" | cut -d' ' -f1)
	rm -f "$tmpfile"

	local newline oldline
	newline="sha256  ${newhash}  ${asset}"
	oldline=$(grep -m1 '^sha256' "$hashfile" || true)

	if [ "$oldline" != "$newline" ]; then
		awk -v newline="$newline" '
			BEGIN { done = 0 }
			/^sha256/ && !done { print newline; done = 1; next }
			{ print }
		' "$hashfile" > "$hashfile.tmp"
		mv "$hashfile.tmp" "$hashfile"
		echo "Updated $hashfile:"
		echo "  old: $oldline"
		echo "  new: $newline"
		hash_sync_record "$outcomes_file" "$pkg" refreshed "sha256 updated: $oldline -> $newline"
		hash_sync_set_env "$env_var" 1
	else
		echo "$hashfile already up to date."
		hash_sync_record "$outcomes_file" "$pkg" already-current "sha256 unchanged"
		hash_sync_set_env "$env_var" 0
	fi
	return 0
}

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local row pkg version_var env_var
	for row in "${IP7Z_PACKAGES[@]}"; do
		IFS='|' read -r pkg version_var env_var <<<"$row"
		sync_one "$outcomes_file" "$pkg" "$version_var" "$env_var"
	done
}

main
