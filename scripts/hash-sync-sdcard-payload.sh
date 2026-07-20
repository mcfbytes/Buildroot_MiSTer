#!/usr/bin/env bash
#
# hash-sync-sdcard-payload.sh — case 4 of 4 of the Renovate hash-sync
# workflow (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6):
# refresh the sd-card payload single-file pins IN scripts/fetch-sdcard-
# payload.sh (this script edits that one; it is not a fork of it).
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's "Refresh
# sdcard payload script hashes (update_all.sh, wifi.sh)" step invokes this
# script directly (from the .hash-sync-tools checkout of the workflow's own
# ref -- see that step's comment in the .yml); there is no separate inline
# copy of this logic left in the workflow. THIS SCRIPT IS AUTHORITATIVE: fix
# bugs in this case here, not in the .yml.
#
# Extracted so this case is independently testable against a fixture -- see
# "Testing against a fixture" below. This case has NEVER run against a real
# PR (per TASKS.md's "renovate-hash-sync.yml — remaining unproven refresh
# paths" item and docs/renovate.md's "Unverified / what to check on first
# run" section, which name it as one of the three untested cases).
#
# scripts/fetch-sdcard-payload.sh pins two individual scripts by commit AND
# by sha256+size: update_all.sh (theypsilon/Update_All_MiSTer) and wifi.sh
# (MiSTer-devel/Scripts_MiSTer). renovate.json's git-refs managers bump the
# PINNED_*_COMMIT (which the raw URL interpolates); the sha256+size then need
# recomputing from the file at the new commit -- the same "fetch the real
# artifact and sha256sum it" practice as case 1 (the github-packages loop).
# The _Console cores commit (PINNED_CORES_COMMIT) has no companion hash and
# is deliberately not handled here -- see scripts/fetch-sdcard-payload.sh's
# own header for why (cores churn too fast for a stable per-file hash to be
# worth maintaining; it is traceability-pinned by commit only).
#
# Usage:
#   scripts/hash-sync-sdcard-payload.sh [REPO_ROOT]
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
# Sets (via hash_sync_set_env): PAYLOAD_HASH_CHANGED=0|1.
#
# Records TWO rows (pin names "PINNED_UPDATE_ALL" and "PINNED_WIFI_SH") to
# $HASH_SYNC_OUTCOMES_FILE: refreshed | already-current | skipped | failed.
# APPENDS -- does not truncate; scripts/hash-sync-github-packages.sh (case 1)
# owns creating/truncating the shared outcomes file for the run. Standalone,
# `touch` the file yourself first if case 1 has not run.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- this is the last of the four cases, but the
# convention is kept for the same reason as the others: a workflow step
# failing here would still abort the "Check for a recorded workflow bug
# before pushing anything" / job-summary steps that come after it.
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing a fake scripts/fetch-sdcard-payload.sh with just the four
# `readonly PINNED_{UPDATE_ALL,WIFI_SH}_{COMMIT,SHA256,SIZE}=...` lines this
# script parses/rewrites. Either let it really fetch
# https://raw.githubusercontent.com/<repo>/<commit>/<path>, or prepend a fake
# `curl` to $PATH that serves fixture file contents for both pins:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-sdcard-payload.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and the rewritten fetch-sdcard-payload.sh.

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

	local file="scripts/fetch-sdcard-payload.sh"
	local changed=0

	if [ ! -f "$file" ]; then
		# The whole script is missing, so the loop below never runs --
		# record BOTH pins explicitly here rather than letting them silently
		# vanish from the job summary.
		echo "::warning::$file not found in this checkout -- skipping PINNED_UPDATE_ALL and PINNED_WIFI_SH"
		hash_sync_record "$outcomes_file" PINNED_UPDATE_ALL skipped "$file not found in this checkout"
		hash_sync_record "$outcomes_file" PINNED_WIFI_SH skipped "$file not found in this checkout"
		hash_sync_set_env PAYLOAD_HASH_CHANGED 0
		exit 0
	fi

	# The pin table: one row per single-file pin this case owns. A plain
	# array now that this lives in a real script file rather than embedded
	# in YAML (the original's "no heredoc, YAML-indent-safe" workaround is
	# moot here) -- still parsed the same way (`set -- $pin`) so the
	# prefix/repo/path split behaves identically.
	local pins=(
		"PINNED_UPDATE_ALL theypsilon/Update_All_MiSTer update_all.sh"
		"PINNED_WIFI_SH MiSTer-devel/Scripts_MiSTer other_authors/wifi.sh"
	)

	local pin prefix repo path commit url tmpfile newhash newsize oldhash oldsize
	for pin in "${pins[@]}"; do
		# shellcheck disable=SC2086
		set -- $pin
		prefix=$1; repo=$2; path=$3

		# `|| true` for the same reason as cases 1 and 3: without it a
		# zero-match grep under `set -euo pipefail` kills the script at the
		# assignment, so the handled branch below -- and its `continue`,
		# which exists precisely so the OTHER pin still gets refreshed --
		# would be unreachable.
		commit=$(grep -E "^readonly ${prefix}_COMMIT=" "$file" | head -1 | sed -E 's/.*="([0-9a-f]{40})".*/\1/' || true)
		if [ -z "$commit" ]; then
			# Parsing our OWN script's ${prefix}_COMMIT line is the same
			# class of bug as the .mk parse failures in cases 1 and 3 (a
			# regex against a file this repo controls, not an upstream
			# condition) -- FAIL via the recorded outcome rather than
			# warn-and-continue. Still `continue`, not exiting the script,
			# so the OTHER pin in this same loop still gets
			# refreshed/reported.
			echo "::error::could not read ${prefix}_COMMIT from $file"
			hash_sync_record "$outcomes_file" "$prefix" failed \
				"could not read ${prefix}_COMMIT from $file -- workflow regex bug, not a network issue; build still fails closed on the stale hash"
			continue
		fi
		url="https://raw.githubusercontent.com/${repo}/${commit}/${path}"
		echo "==> ${prefix}: fetching $url"
		tmpfile=$(mktemp)
		if ! curl -fsSL --retry 3 "$url" -o "$tmpfile"; then
			# A download failure against an upstream raw-file URL is a
			# legitimate network blip -- stays warn-and-continue.
			echo "::warning::could not download $url -- skipping, build will fail closed on a stale hash instead"
			hash_sync_record "$outcomes_file" "$prefix" skipped "could not download $url"
			rm -f "$tmpfile"
			continue
		fi
		newhash=$(sha256sum "$tmpfile" | cut -d' ' -f1)
		newsize=$(stat -c %s "$tmpfile")
		rm -f "$tmpfile"
		oldhash=$(grep -E "^readonly ${prefix}_SHA256=" "$file" | head -1 | sed -E 's/.*="([0-9a-f]+)".*/\1/')
		oldsize=$(grep -E "^readonly ${prefix}_SIZE=" "$file" | head -1 | sed -E 's/.*="([0-9]+)".*/\1/')
		if [ "$oldhash" != "$newhash" ] || [ "$oldsize" != "$newsize" ]; then
			# Exact-string sed replacement on the LITERAL prefix (not awk -v
			# with a regex, and not a variable substitution inside the
			# pattern beyond the anchored prefix group): `\1` here is a sed
			# backreference to that anchored group, kept intact by using
			# single-quoted-around-variable `-E "s|...|\\1\"...\"|"` rather
			# than building the replacement text through `awk -v`, which
			# would eat backslash escapes (see the kernel case's own note on
			# exactly that trap).
			sed -i -E "s|^(readonly ${prefix}_SHA256=)\"[0-9a-f]+\"|\\1\"${newhash}\"|" "$file"
			sed -i -E "s|^(readonly ${prefix}_SIZE=)\"[0-9]+\"|\\1\"${newsize}\"|" "$file"
			echo "Updated ${prefix}: sha256 ${oldhash} -> ${newhash}; size ${oldsize} -> ${newsize}"
			hash_sync_record "$outcomes_file" "$prefix" refreshed "sha256 ${oldhash} -> ${newhash}; size ${oldsize} -> ${newsize}"
			changed=1
		else
			echo "${prefix} already up to date."
			hash_sync_record "$outcomes_file" "$prefix" already-current "sha256/size unchanged"
		fi
	done

	hash_sync_set_env PAYLOAD_HASH_CHANGED "$changed"
}

main
