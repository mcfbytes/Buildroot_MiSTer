#!/usr/bin/env bash
#
# hash-sync-buildroot.sh — case 6 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): refresh the
# pinned Buildroot tarball hash (BUILDROOT_SHA256 in the root Makefile) from
# Buildroot's own GPG-clearsigned release manifest.
#
# WHY THIS EXISTS NOW, HAVING BEEN FORBIDDEN BEFORE -- read this before
# "restoring" the old prohibition, because the change is deliberate and the
# old wording ("BUILDROOT_SHA256 is NEVER automated") is still quoted in older
# commits and in this family's own scripts. The prohibition was always about
# the SOURCE of the value, not about who does the transcription: a
# locally-computed sha256sum of the downloaded tarball is circular (it pins
# whatever bytes happened to arrive and certifies nothing), and THAT remains
# permanently forbidden -- this script never hashes a tarball. But upstream
# publishes a GPG-clearsigned manifest for every release:
#
#     https://buildroot.org/downloads/buildroot-<ver>.tar.gz.sign
#
# containing a "SHA256: <hash>  buildroot-<ver>.tar.gz" line, and the manual
# process this script replaces was ALWAYS "run `make buildroot-showsig` and
# transcribe that line by hand" (the root Makefile's own header). Fetching the
# same signed manifest over HTTPS and transcribing the same line is the same
# trust level as the human doing it -- the exact narrowing case 2
# (scripts/hash-sync-kernel.sh) went through on 2026-08-17 when the RT pin
# left the -rc series and its hash became transcribable from kernel.org's
# signed sha256sums.asc. Same reasoning, same source kind, same automation.
# NARROWED 2026-08-24; see docs/ci.md#renovate-hash-sync-not-automated.
#
# Like case 2, this does NOT verify the PGP signature (no keyring management
# in this workflow family yet) -- it fetches the clearsigned manifest over
# HTTPS and greps the SHA256 line, which is exactly the trust level of the
# manual transcription it replaces, not a regression. Verifying the clearsign
# signature (upstream's release manager publishes the key) is a worthwhile
# future hardening step for BOTH manifest-transcribing cases, not implemented
# here. A human CAN do better on a bump that warrants it: `gpg --verify` the
# .sign file locally, as linux.hash's RT block records was done for the 7.2
# crossing.
#
# WHAT THIS SCRIPT MUST NEVER DO (the surviving half of the old prohibition;
# see scripts/lib/hash-sync-common.sh for the family-wide statement):
#
#   * compute BUILDROOT_SHA256 from a downloaded tarball. There is no code
#     path here that downloads the tarball at all -- keep it that way. If the
#     .sign manifest cannot be fetched or parsed, the correct outcome is
#     `skipped` (build fails closed on the stale hash) or `failed` (a parse
#     bug against a file this repo controls), never a locally-derived value.
#
# Rewrites ONLY the hash value on the Makefile's BUILDROOT_SHA256 line,
# preserving that line's own spacing verbatim (the stanza is column-aligned
# and Renovate-watched -- see the Makefile's "keep this stanza regex-friendly"
# note). Both pin lines are matched whitespace-tolerantly
# (BUILDROOT_VERSION[[:space:]]*?=), the same tolerance renovate.json's
# matchString has -- a single-space match here already broke CI once when the
# stanza was aligned (run 32698708260).
#
# Parse idiom note: shapes are asserted IN the grep match and the value is
# re-extracted with grep -oE, per the case-5 parse note in
# docs/ci.md#renovate-hash-sync-cores-pin -- never the
# `sed -E 's/.*pattern.*/\1/'` idiom, which prints its input UNCHANGED on a
# non-match and lets a malformed line escape as a bogus value.
#
# Usage:
#   scripts/hash-sync-buildroot.sh [REPO_ROOT]
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
# Sets (via hash_sync_set_env): BUILDROOT_HASH_CHANGED=0|1 -- ORed into the
# .yml's "Commit and push hash refresh" gate, which must also `git add`
# Makefile. A new pin means a new variable AND a new clause in that gate AND
# its file in the `git add` list; miss any of the three and the refresh is
# computed, written to the working tree, and never committed (green run,
# stale branch, no diagnostic -- the exact CHANGED_VAR clobber trap
# scripts/hash-sync-kernel.sh documents).
#
# Records ONE row, pin name "buildroot", to $HASH_SYNC_OUTCOMES_FILE:
# refreshed | already-current | skipped | failed. APPENDS -- does not
# truncate; scripts/hash-sync-github-packages.sh (case 1, run first in the
# workflow) owns creating/truncating the shared outcomes file for the run.
# Standalone, `touch` the file yourself first if case 1 has not run.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- this runs as its own workflow step, and an
# `exit 1` here would skip later cases entirely (the exact hole item J
# closed; see the .yml's own header). A non-zero exit means something this
# script did not anticipate.
#
# Testing against a fixture: point REPO_ROOT at a scratch directory holding a
# Makefile with the two pin lines (BUILDROOT_VERSION / BUILDROOT_SHA256 --
# aligned or not; both spacings must work) and either let it really fetch the
# .sign for a published version, or prepend a fake `curl` to $PATH serving a
# fixture manifest:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-buildroot.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and the rewritten Makefile. Assertions worth
# keeping: a stale hash refreshes to the manifest's value with every OTHER
# byte of the Makefile identical; a current hash records already-current and
# touches nothing; a Makefile with no BUILDROOT_SHA256 line records failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

OUTCOME_PIN="buildroot"
CHANGED_VAR="BUILDROOT_HASH_CHANGED"

REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
[ -d "$REPO_ROOT" ] || { echo "::error::REPO_ROOT '$REPO_ROOT' is not a directory" >&2; exit 2; }

: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local makefile="Makefile"

	if [ ! -f "$makefile" ]; then
		echo "::warning::$makefile not found in this checkout -- skipping $OUTCOME_PIN"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "$makefile not found in this checkout"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	# Buildroot versions are YYYY.MM[.N][-rcN]; assert that shape in the match
	# itself (see the parse-idiom note in the header). `?=` is a literal in
	# basic-vs-extended regex terms only for the `?` -- inside ERE, `\?` is the
	# literal question mark. The trailing [[:space:]]*$ tolerates trailing
	# whitespace on the line without letting it into the value.
	#
	# The `|| true`s are load-bearing under `set -euo pipefail`: with no match,
	# grep exits 1, and a plain-assignment substitution failure aborts the
	# script before the empty-check below can emit its diagnostic (the same
	# trap scripts/hash-sync-kernel.sh documents).
	local ver
	ver=$(grep -E '^BUILDROOT_VERSION[[:space:]]*\?=[[:space:]]*[0-9]{4}\.[0-9]{2}(\.[0-9]+)?(-rc[0-9]+)?[[:space:]]*$' "$makefile" \
	        | head -1 | grep -oE '[0-9]{4}\.[0-9]{2}(\.[0-9]+)?(-rc[0-9]+)?' | head -1 || true)
	if [ -z "$ver" ]; then
		echo "::error::could not extract BUILDROOT_VERSION from $makefile" >&2
		# A parse/extract failure against a file THIS repo controls is a bug
		# in this script's own regex, not a transient upstream condition --
		# record "failed" (not "skipped") so the job-summary step fails the
		# run, but exit 0 so later cases still run and report their own pins.
		# The workflow's push-suppression step reads this same recorded
		# "failed" and suppresses the push job-wide.
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed \
			"could not extract BUILDROOT_VERSION from $makefile"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	local sign_url
	sign_url="https://buildroot.org/downloads/buildroot-${ver}.tar.gz.sign"
	echo "==> $OUTCOME_PIN $ver: fetching $sign_url"

	# An upstream fetch failure is a legitimate network blip against
	# buildroot.org, not a bug in this script -- warn-and-continue; the build
	# fails closed at `make buildroot-verify` on the stale hash instead.
	local manifest
	manifest=$(curl -fsSL --retry 3 "$sign_url") || {
		echo "::warning::could not fetch $sign_url -- leaving $makefile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "could not fetch $sign_url"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	}

	# The clearsigned manifest's line looks like:
	#   SHA256: <64 hex>  buildroot-2026.05.2.tar.gz
	# Match the EXACT pinned version's filename, hex shape asserted in the
	# match. The filename check is not decoration: the manifest also carries a
	# SHA1 line and (in principle) could list more than one file.
	local ver_re matchline newhash
	ver_re=${ver//./\\.}
	matchline=$(printf '%s\n' "$manifest" \
	        | grep -E "^SHA256: [0-9a-f]{64}  buildroot-${ver_re}\.tar\.gz\$" | head -1 || true)
	if [ -z "$matchline" ]; then
		# A manifest that fetched but does not carry the expected line is an
		# upstream condition (or a not-yet-published version), not evidence
		# this script mis-parsed anything -- $ver already passed the strict
		# format check above. Stays warn-and-continue.
		echo "::warning::no 'SHA256: ...  buildroot-${ver}.tar.gz' line in $sign_url -- leaving $makefile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "no SHA256 line for buildroot-${ver}.tar.gz in $sign_url"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi
	newhash=$(printf '%s\n' "$matchline" | grep -oE '[0-9a-f]{64}' | head -1)

	# If two BUILDROOT_SHA256 lines somehow exist, do not guess which one is
	# the pin (same ambiguity posture as case 2's linux.hash guard).
	local hashline_re nmatch
	hashline_re='^BUILDROOT_SHA256[[:space:]]*\?='
	nmatch=$(grep -c -E "$hashline_re" "$makefile" || true)
	if [ "${nmatch:-0}" -ne 1 ]; then
		echo "::error::$makefile has $nmatch lines matching BUILDROOT_SHA256 ?= -- refusing to guess which one is the pin." >&2
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed \
			"$makefile has $nmatch BUILDROOT_SHA256 lines (expected exactly 1) -- refusing to guess"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	local oldline oldhash
	oldline=$(grep -m1 -E "$hashline_re" "$makefile")
	oldhash=$(printf '%s\n' "$oldline" | grep -oE '[0-9a-f]{64}' | head -1 || true)
	if [ -z "$oldhash" ]; then
		echo "::error::$makefile's BUILDROOT_SHA256 line carries no 64-hex value: '$oldline'" >&2
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed \
			"BUILDROOT_SHA256 line carries no 64-hex value: '$oldline'"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	if [ "$oldhash" != "$newhash" ]; then
		# Substitute ONLY the hash inside the line we already hold, so the
		# stanza's column alignment survives byte-for-byte; then replace by
		# EXACT string match on the whole line, not by re-deriving a regex
		# inside awk -- passing a regex through `awk -v` would have its
		# backslash escapes eaten (a 64-hex string has none, but the idiom is
		# kept identical to case 2's for a reason).
		local newline
		newline=${oldline/"$oldhash"/"$newhash"}
		awk -v oldline="$oldline" -v newline="$newline" '
			BEGIN { done = 0 }
			$0 == oldline && !done { print newline; done = 1; next }
			{ print }
		' "$makefile" > "$makefile.tmp"
		mv "$makefile.tmp" "$makefile"
		echo "Updated $makefile:"
		echo "  old: $oldline"
		echo "  new: $newline"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" refreshed "BUILDROOT_SHA256 updated for $ver: $oldhash -> $newhash (from $sign_url)"
		hash_sync_set_env "$CHANGED_VAR" 1
	else
		echo "$makefile BUILDROOT_SHA256 already up to date for $ver."
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" already-current "BUILDROOT_SHA256 unchanged for $ver"
		hash_sync_set_env "$CHANGED_VAR" 0
	fi
}

main
