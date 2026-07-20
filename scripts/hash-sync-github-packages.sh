#!/usr/bin/env bash
#
# hash-sync-github-packages.sh — case 1 of 4 of the Renovate hash-sync
# workflow (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6):
# refresh the tarball sha256 for every github-sourced package pin.
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's "Refresh
# github-sourced package tarball hashes" step invokes this script directly
# (from the .hash-sync-tools checkout of the workflow's own ref -- see that
# step's comment in the .yml); there is no separate inline copy of this
# logic left in the workflow. THIS SCRIPT IS AUTHORITATIVE: fix bugs in this
# case here, not in the .yml.
#
# Extracted so this case is independently testable against a fixture (per
# TASKS.md's "renovate-hash-sync.yml — remaining unproven refresh paths" item
# and docs/renovate.md's "Unverified / what to check on first run" section,
# this is one of three cases that have NEVER run against a real PR; and a
# malformed URL in a DIFFERENT case once let the job report SUCCESS three
# times while leaving a hash stale -- run 29669946883). See "Testing against
# a fixture" below.
#
# Covers the 12 github-sourced packages (package/*/*.mk + their .hash): the
# 11 driver/firmware pins plus libchdr (a userspace shared library --
# Main_MiSTer shared-lib refactor -- but the exact same $(call github,...)
# commit-archive shape). Their own .hash file headers already say the hash
# is "locally computed" -- GitHub publishes no signed manifest for a
# commit/tag archive tarball, so `sha256sum` of a freshly-fetched tarball
# from the ACTUAL pinned owner/repo/ref IS the legitimate, standard-practice
# source for these (see e.g. package/xone/xone.hash's own comment, and
# pkg-download.mk / the Buildroot manual). Automating exactly what a human
# would otherwise type by hand is safe here.
#
# Generic loop, not one call site per package: every one of these .mk files
# follows the identical Buildroot convention
#   <PKG>_VERSION = <commit-sha-or-tag>
#   <PKG>_SITE    = $(call github,<owner>,<repo>,$(<PKG>_VERSION))
# and the resulting downloaded/hashed tarball is always named
# "<package-dir-name>-<VERSION>.tar.gz" by Buildroot's own github helper (NOT
# "<repo-name>-<VERSION>.tar.gz" -- checked against every existing .hash file
# in this tree before writing this loop). Only the FIRST `sha256` line (the
# tarball itself) is ever rewritten; any further lines (LICENSE, individual
# source files hashed for provenance) are left untouched -- if one of those
# legitimately changed too, the build's own hash check will fail closed and a
# human will need to re-derive that specific line by hand.
#
# Usage:
#   scripts/hash-sync-github-packages.sh [REPO_ROOT]
#   REPO_ROOT defaults to this repo's root (the script's own grandparent
#   directory). Pass a fixture directory to exercise this case in isolation
#   -- see "Testing against a fixture" below.
#
# Required env:
#   HASH_SYNC_PACKAGES        space-separated package directory names, e.g.
#                             "rtl8812au xone libchdr". In production this is
#                             the workflow's job-level env: block (single
#                             source of truth shared with the job-summary
#                             step's pin roster -- see that env var's own
#                             comment in the .yml for why it must not drift
#                             into two independently-hardcoded lists).
#   HASH_SYNC_OUTCOMES_FILE   bare filename (production; $RUNNER_TEMP-
#                             prefixed, see scripts/lib/hash-sync-common.sh)
#                             or an absolute path (standalone/fixture use).
#
# Optional env:
#   GITHUB_ENV, RUNNER_TEMP   set automatically by Actions; see
#                             scripts/lib/hash-sync-common.sh for the
#                             standalone-safe fallback behavior of each.
#
# Sets (via hash_sync_set_env -- $GITHUB_ENV in production, stdout
# standalone): PKG_HASH_CHANGED=0|1.
#
# Records to $HASH_SYNC_OUTCOMES_FILE, one row per package in
# $HASH_SYNC_PACKAGES: refreshed | already-current | skipped | failed.
# TRUNCATES/CREATES that file first -- this script is step 1 of 4 in the
# workflow, and the other three append to the same file; see
# HASH_SYNC_OUTCOMES_FILE's own comment in the workflow for why the
# truncation happens here specifically (belt-and-braces: the filename is
# already run-attempt-unique, this does not depend on that).
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing only package/<name>/<name>.mk and package/<name>/<name>.hash
# for one or more fake package names, set HASH_SYNC_PACKAGES to match, and
# either point <name>.mk's $(call github,...) at a real small public repo
# (a genuine network fetch) or prepend a fake `curl` to $PATH that serves a
# fixture tarball instead -- the exact bug this case's own header notes
# (three of four cases never run against a real PR) is precisely the class
# of bug a fake-curl fixture catches cheaply, without any network access:
#
#   HASH_SYNC_PACKAGES=fakepkg \
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-github-packages.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and the rewritten package/fakepkg/fakepkg.hash.

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

: "${HASH_SYNC_PACKAGES:?HASH_SYNC_PACKAGES must be set (space-separated package dir names)}"
: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"
	: > "$outcomes_file"

	local changed=0
	local pkg mk hashfile version owner repo url tmpfile newhash newname newline oldline
	# shellcheck disable=SC2086
	for pkg in $HASH_SYNC_PACKAGES; do
		mk="package/$pkg/$pkg.mk"
		hashfile="package/$pkg/$pkg.hash"
		if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
			# Previously a bare `continue` with no warning at all -- a totally
			# silent skip. These pins are named explicitly in
			# HASH_SYNC_PACKAGES BECAUSE their .mk/.hash are supposed to
			# always exist, so this is not a legitimate "nothing to do here"
			# case; it is either repo damage or HASH_SYNC_PACKAGES going
			# stale. Surfaced (not failed) because it is not a parse/extract
			# bug in THIS script -- there is nothing here to parse.
			echo "::warning::$mk or $hashfile not found in this checkout -- skipping $pkg"
			hash_sync_record "$outcomes_file" "$pkg" skipped "$mk or $hashfile not found in this checkout"
			continue
		fi

		# `|| true` on each extraction, and it is load-bearing: under
		# `set -euo pipefail` a zero-match grep exits 1, pipefail makes the
		# whole pipeline return 1, that becomes the assignment's status, and
		# `set -e` kills the function (and the script) right here -- before
		# the `[ -z ... ]` branch below can run. The handled path would be
		# dead code and the "remaining pins still get a chance to run"
		# promise in that branch's comment would be a lie: an unparseable
		# .mk for package #1 would take out packages 2-N with it -- and,
		# because a non-zero exit fails this workflow step, cases 2-4 (the
		# kernel, lzma-sdk, and sdcard-payload scripts) and the push guard
		# along with them -- reported as "not-run" rather than as the parse
		# bug it actually was. With `|| true` the empty string reaches the
		# guard and the recorded `failed` outcome is what fails the job, in
		# the workflow's summary step, after everything else has had its
		# turn.
		version=$(grep -E '^[A-Z0-9_]+_VERSION[[:space:]]*=' "$mk" | head -1 \
		           | sed -E 's/^[A-Z0-9_]+_VERSION[[:space:]]*=[[:space:]]*//' || true)
		owner=$(grep -E '_SITE[[:space:]]*=[[:space:]]*\$\(call github,' "$mk" | head -1 \
		         | sed -E 's/.*\$\(call github,([^,]+),([^,]+),.*/\1/' || true)
		repo=$(grep -E '_SITE[[:space:]]*=[[:space:]]*\$\(call github,' "$mk" | head -1 \
		        | sed -E 's/.*\$\(call github,([^,]+),([^,]+),.*/\2/' || true)

		if [ -z "$version" ] || [ -z "$owner" ] || [ -z "$repo" ]; then
			# A parse/extract failure against a .mk file THIS repo controls
			# (not a network condition) is a bug in this script's own
			# regexes, not a transient upstream hiccup -- so this is a FAIL,
			# not a warn-and-continue. Recorded as "failed" (not "skipped")
			# so the workflow's job-summary step fails the job; still
			# `continue` rather than exiting the script, so the remaining
			# pins in this loop still get a chance to run and be reported on.
			echo "::error::could not parse $mk (version='$version' owner='$owner' repo='$repo')"
			hash_sync_record "$outcomes_file" "$pkg" failed \
				"could not parse VERSION/SITE out of $mk -- workflow regex bug, not a network issue; build still fails closed on the stale hash"
			continue
		fi

		url="https://github.com/$owner/$repo/archive/$version.tar.gz"
		echo "==> $pkg: fetching $url"
		tmpfile=$(mktemp)
		if ! curl -fsSL --retry 3 "$url" -o "$tmpfile"; then
			# A download failure against an upstream URL IS a legitimate
			# network blip -- one package's mirror hiccup should not fail
			# the other pins' refreshes, so this stays warn-and-continue.
			echo "::warning::could not download $url for $pkg -- skipping, build will fail closed on a stale hash instead"
			hash_sync_record "$outcomes_file" "$pkg" skipped "could not download $url"
			rm -f "$tmpfile"
			continue
		fi
		newhash=$(sha256sum "$tmpfile" | cut -d' ' -f1)
		rm -f "$tmpfile"

		newname="${pkg}-${version}.tar.gz"
		newline="sha256  ${newhash}  ${newname}"
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
			changed=1
		else
			echo "$hashfile already up to date."
			hash_sync_record "$outcomes_file" "$pkg" already-current "sha256 unchanged"
		fi
	done

	hash_sync_set_env PKG_HASH_CHANGED "$changed"
}

main
