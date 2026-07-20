#!/usr/bin/env bash
#
# hash-sync-lzma-sdk.sh — case 3 of 4 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): refresh the
# bespoke lzma-sdk release-asset tarball hash.
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's "Refresh
# lzma-sdk release-asset tarball hash" step invokes this script directly
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
# scripts/hash-sync-github-packages.sh): lzma-sdk's tarball is a GitHub
# release ASSET (https://github.com/ip7z/7zip/releases/download/<ver>/...),
# not a $(call github,...) commit/tag archive, and its filename is derived
# from the version with the dots stripped (LZMA_SDK_SOURCE =
# 7z$(subst .,,$(LZMA_SDK_VERSION))-src.tar.xz, so 26.02 -> 7z2602-src.tar.xz).
# Trust model is the same as case 1's: upstream publishes no checksums
# anywhere (checked at pin time -- see package/lzma-sdk/lzma-sdk.hash's own
# header), so a locally-computed sha256 of the freshly-fetched asset is the
# legitimate source. Only the FIRST sha256 line (the tarball) is rewritten;
# the DOC/License.txt and DOC/readme.txt provenance lines beneath it are left
# untouched -- if one of those legitimately changed too, the build's own hash
# check fails closed and a human re-derives that line by hand.
#
# Usage:
#   scripts/hash-sync-lzma-sdk.sh [REPO_ROOT]
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
# Sets (via hash_sync_set_env): LZMA_SDK_HASH_CHANGED=0|1.
#
# Records ONE row (pin name "lzma-sdk") to $HASH_SYNC_OUTCOMES_FILE:
# refreshed | already-current | skipped | failed. APPENDS -- does not
# truncate; scripts/hash-sync-github-packages.sh (case 1) owns
# creating/truncating the shared outcomes file for the run. Standalone,
# `touch` the file yourself first if case 1 has not run.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- this runs as its own workflow step, and an
# `exit 1` here would skip case 4 entirely.
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing a fake package/lzma-sdk/lzma-sdk.mk (just needs a
# LZMA_SDK_VERSION = <ver> line) and a fake package/lzma-sdk/lzma-sdk.hash
# (a "sha256  ...  7z<verdigits>-src.tar.xz" line plus any provenance lines
# beneath it, to confirm those survive untouched). Either let it really
# fetch a real ip7z/7zip release asset, or prepend a fake `curl` to $PATH
# that serves a fixture asset:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-lzma-sdk.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and the rewritten lzma-sdk.hash.

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

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local mk="package/lzma-sdk/lzma-sdk.mk"
	local hashfile="package/lzma-sdk/lzma-sdk.hash"

	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping lzma-sdk"
		hash_sync_record "$outcomes_file" lzma-sdk skipped "$mk or $hashfile not found in this checkout"
		hash_sync_set_env LZMA_SDK_HASH_CHANGED 0
		exit 0
	fi

	# `|| true` for the same reason as case 1's extractions: without it a
	# zero-match grep under `set -euo pipefail` kills the script at the
	# assignment and the handled branch below -- including its `exit 0` that
	# deliberately lets case 4 still run -- never executes.
	local version
	version=$(grep -E '^LZMA_SDK_VERSION[[:space:]]*=' "$mk" | head -1 \
	           | sed -E 's/^LZMA_SDK_VERSION[[:space:]]*=[[:space:]]*//' || true)
	if [ -z "$version" ]; then
		# Parsing our OWN .mk file -- same class of bug as the github-loop
		# and kernel parse/extract failures, so this is a FAIL (via the
		# recorded outcome), not a warn-and-continue. exit 0 (not 1) so case
		# 4 still runs and reports its own pins.
		echo "::error::could not parse LZMA_SDK_VERSION from $mk"
		hash_sync_record "$outcomes_file" lzma-sdk failed \
			"could not parse LZMA_SDK_VERSION from $mk -- workflow regex bug, not a network issue; build still fails closed on the stale hash"
		hash_sync_set_env LZMA_SDK_HASH_CHANGED 0
		exit 0
	fi

	local asset url tmpfile
	asset="7z$(echo "$version" | tr -d .)-src.tar.xz"
	url="https://github.com/ip7z/7zip/releases/download/${version}/${asset}"
	echo "==> lzma-sdk $version: fetching $url"
	tmpfile=$(mktemp)
	if ! curl -fsSL --retry 3 "$url" -o "$tmpfile"; then
		# A download failure against an upstream release asset is a
		# legitimate network blip -- stays warn-and-continue.
		echo "::warning::could not download $url -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" lzma-sdk skipped "could not download $url"
		rm -f "$tmpfile"
		hash_sync_set_env LZMA_SDK_HASH_CHANGED 0
		exit 0
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
		hash_sync_record "$outcomes_file" lzma-sdk refreshed "sha256 updated: $oldline -> $newline"
		hash_sync_set_env LZMA_SDK_HASH_CHANGED 1
	else
		echo "$hashfile already up to date."
		hash_sync_record "$outcomes_file" lzma-sdk already-current "sha256 unchanged"
		hash_sync_set_env LZMA_SDK_HASH_CHANGED 0
	fi
}

main
