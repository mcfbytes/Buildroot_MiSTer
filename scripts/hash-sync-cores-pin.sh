#!/usr/bin/env bash
#
# hash-sync-cores-pin.sh — case 5 of 5 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): VALIDATE the
# _Console cores snapshot pin (PINNED_CORES_COMMIT) in
# scripts/fetch-sdcard-payload.sh.
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's "Validate the
# _Console cores snapshot pin" step invokes this script directly (from the
# .hash-sync-tools checkout of the workflow's own ref -- see that step's
# comment in the .yml). THIS SCRIPT IS AUTHORITATIVE: fix bugs in this case
# here, not in the .yml.
#
# WHY THIS CASE IS DIFFERENT FROM THE OTHER FOUR
# Cases 1-4 REWRITE a companion sha256 that Renovate cannot compute. This one
# rewrites nothing: PINNED_CORES_COMMIT is a commit-only pin by design (cores
# churn too fast for a stable per-file hash to be worth maintaining -- see
# scripts/fetch-sdcard-payload.sh's own header and docs/renovate.md), so
# there is no companion value to keep in lockstep and nothing here ever edits
# a file.
#
# What there IS, and why this case exists at all: PINNED_CORES_COMMIT is read
# in exactly ONE place -- fetch_cores() in scripts/fetch-sdcard-payload.sh --
# which runs only under SDCARD_CORES=1, i.e. only in release.yml's OPT-IN
# sdcard-full.img.xz leg. No PR build ever resolves it. So an automatic
# Renovate bump to a commit that does not resolve, or whose _Console listing
# is unusable, would sail through every check on the PR and first surface
# when someone cuts a release with cores enabled. This script closes that
# hole with a single Contents API call -- no core downloads, no build -- and
# asserts exactly the four things fetch_cores() would later depend on:
#
#   1. the pinned commit resolves and the _Console path exists at it
#      (a Renovate-written SHA is not guaranteed to survive an upstream
#      force-push/GC by the time a release is cut);
#   2. the listing contains at least one *.rbf -- the same condition
#      fetch_cores() itself dies on ("API shape changed or the pin is
#      stale"), checked here instead of 3 hours into a release build;
#   3. every *.rbf the name filter selects is a regular file. A dir,
#      symlink or submodule named "*.rbf" is selected by fetch_cores()'s
#      name-only filter but has a null download_url, so its `curl -o` would
#      fail the release build. See the jq call for why this is asked as a
#      SEPARATE question rather than narrowed into the selection;
#   4. the API-reported total of those *.rbf files is within
#      $EXPECT_CORES_MAX_BYTES -- the SAME ~600 MiB cap
#      scripts/check-sdcard.sh enforces on the staged tree
#      (docs/verification/sdcard-payload.md §2 / ADR 0020 §3). Catching an
#      over-cap upstream here costs one API call; catching it in
#      check-sdcard.sh costs a full release build first.
#
# Usage:
#   scripts/hash-sync-cores-pin.sh [REPO_ROOT]
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
#   GITHUB_TOKEN              sent as a bearer token, exactly as
#                             fetch_cores() does. STRONGLY WANTED in CI: the
#                             unauthenticated GitHub API limit is 60/hr PER
#                             IP, shared across every job on that runner, so
#                             without it this check degrades to a 403 ->
#                             "skipped" and validates nothing.
#   EXPECT_CORES_MAX_BYTES    cap for check 3; default 629145600 (~600 MiB),
#                             the same default and the same variable name
#                             scripts/check-sdcard.sh uses, so overriding the
#                             cap in one place does not silently leave the
#                             other on the old value.
#   GITHUB_ENV, RUNNER_TEMP   set automatically by Actions; see
#                             scripts/lib/hash-sync-common.sh for the
#                             standalone-safe fallback behavior of each.
#
# Sets (via hash_sync_set_env): CORES_PIN_CHANGED=0, ALWAYS. This case never
# edits a file, so it must never contribute to the workflow's commit/push
# `if:` condition. It is set at all only so the flag exists alongside the
# other four cases' *_CHANGED flags rather than being an unset special case.
#
# Records ONE row (pin name "PINNED_CORES") to $HASH_SYNC_OUTCOMES_FILE:
#   already-current  the pin resolves and all three checks pass. ("Validated"
#                    is not in the ledger's four-value vocabulary and this is
#                    not the place to widen it -- see
#                    scripts/lib/hash-sync-common.sh's hash_sync_record. The
#                    pin is, literally, current.)
#   failed           the pin itself is unusable (404/422 at that commit, zero
#                    *.rbf, over the cap, or our own parse of
#                    fetch-sdcard-payload.sh broke). Suppresses the
#                    workflow's push step and fails the job -- correct here:
#                    unlike a stale companion hash, NOTHING downstream fails
#                    closed on a bad cores pin until a release is cut.
#   skipped          transport/rate-limit/5xx -- an upstream condition, not a
#                    verdict on the pin. Warn-and-continue, same as every
#                    other case's network path.
# APPENDS -- does not truncate; scripts/hash-sync-github-packages.sh (case 1)
# owns creating/truncating the shared outcomes file for the run. Standalone,
# `touch` the file yourself first if case 1 has not run.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- a nonzero exit here would abort the "Check for a
# recorded workflow bug before pushing anything" / job-summary steps that
# come after it, which are the very steps that act on a recorded "failed".
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing a fake scripts/fetch-sdcard-payload.sh with just the
# `readonly PINNED_CORES_COMMIT="..."` line this script parses. To exercise
# the failure paths without an upstream, prepend a fake `curl` to $PATH that
# emits a chosen body and http_code:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-cores-pin.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv. Every branch below (200-ok, 200-zero-rbf,
# 200-non-file-rbf, 200-over-cap, 200-unparseable, 404, 403/000, missing
# file, unparseable pin line) was exercised that way before this script was
# wired in.

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

# Same default and same variable name as scripts/check-sdcard.sh -- see this
# script's header for why they are deliberately spelled identically.
: "${EXPECT_CORES_MAX_BYTES:=629145600}"

readonly CORES_REPO="MiSTer-devel/Distribution_MiSTer"
readonly CORES_PATH="_Console"

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	# This case edits nothing; see the header. Set first, so every early
	# `exit 0` below still leaves the flag defined for the workflow's
	# commit/push `if:` condition.
	hash_sync_set_env CORES_PIN_CHANGED 0

	local file="scripts/fetch-sdcard-payload.sh"

	if [ ! -f "$file" ]; then
		# Same reasoning as case 4's missing-file branch: record the pin
		# explicitly rather than letting it silently vanish from the job
		# summary (the workflow's gate turns an unrecorded pin into
		# "not-run" and fails, but a named reason is more useful).
		echo "::warning::$file not found in this checkout -- skipping PINNED_CORES"
		hash_sync_record "$outcomes_file" PINNED_CORES skipped "$file not found in this checkout"
		exit 0
	fi

	# `|| true` for the same reason as cases 1, 3 and 4: a zero-match grep
	# under `set -euo pipefail` would kill the script at the assignment,
	# making the handled branch below unreachable.
	#
	# The 40-hex shape is asserted in the MATCH (and re-extracted with
	# `grep -oE`), NOT left to a trailing `sed -E 's/.*="([0-9a-f]{40})".*/\1/'`
	# as the sibling cases do. That idiom has a trap: sed prints its input
	# UNCHANGED when the pattern does not match, so a present-but-malformed
	# pin line yields the whole line rather than the empty string the
	# `-z` guard below is looking for -- the parse bug then escapes as a
	# bogus commit and gets misreported downstream (here it would surface as
	# a 404 "pinned commit gone", blaming upstream for our own bad regex).
	# Verified against a fixture whose line reads
	# `readonly PINNED_CORES_COMMIT=$SOMEVAR`.
	local commit
	commit=$(grep -E '^readonly PINNED_CORES_COMMIT="[0-9a-f]{40}"' "$file" | head -1 | grep -oE '[0-9a-f]{40}' || true)
	if [ -z "$commit" ]; then
		# Parsing our OWN script's pin line -- a regex bug against a file
		# this repo controls, not an upstream condition. FAIL, same as the
		# equivalent branch in case 4.
		echo "::error::could not read PINNED_CORES_COMMIT from $file"
		hash_sync_record "$outcomes_file" PINNED_CORES failed \
			"could not read PINNED_CORES_COMMIT from $file -- workflow regex bug, not a network issue"
		exit 0
	fi

	local url="https://api.github.com/repos/${CORES_REPO}/contents/${CORES_PATH}?ref=${commit}"
	echo "==> PINNED_CORES: resolving $url"

	local -a auth_args=()
	if [ -n "${GITHUB_TOKEN:-}" ]; then
		auth_args=(-H "Authorization: Bearer $GITHUB_TOKEN")
	else
		# Not fatal, but say so loudly: unauthenticated this check is one
		# 403 away from validating nothing at all.
		echo "::warning::GITHUB_TOKEN is not set -- the GitHub API call below is unauthenticated (60/hr per runner IP) and may degrade to a 'skipped' outcome"
	fi

	local body http
	body=$(mktemp)
	# No `-f`: a 404 must reach the classifier below as a VERDICT ON THE PIN,
	# not as a generic curl failure indistinguishable from a timeout. --retry
	# covers transport blips only; it does not retry a 4xx.
	http=$(curl -sSL --retry 3 --retry-connrefused \
		-H "Accept: application/vnd.github+json" \
		"${auth_args[@]}" \
		-w '%{http_code}' \
		-o "$body" \
		"$url" 2>/dev/null || echo "000")

	case "$http" in
		200) ;;
		404|422)
			# The pin does not resolve. Not a network condition -- this is
			# precisely the bad-bump case this script exists to catch.
			echo "::error::PINNED_CORES: HTTP $http for $url -- the pinned commit or the ${CORES_PATH} path does not resolve"
			hash_sync_record "$outcomes_file" PINNED_CORES failed \
				"HTTP $http resolving ${CORES_PATH} at ${CORES_REPO}@${commit} -- pinned commit gone (force-push/GC) or path renamed; release.yml's SDCARD_CORES=1 leg would fail on this"
			rm -f "$body"
			exit 0
			;;
		*)
			# 000 (transport), 403 (rate limit), 5xx, anything else: an
			# upstream condition, so warn-and-continue like every other
			# case's network path.
			echo "::warning::PINNED_CORES: HTTP $http for $url -- skipping validation this run"
			hash_sync_record "$outcomes_file" PINNED_CORES skipped \
				"HTTP $http resolving ${CORES_PATH} at ${CORES_REPO}@${commit} (transport, rate limit, or upstream 5xx) -- pin NOT validated this run"
			rm -f "$body"
			exit 0
			;;
	esac

	# jq is present on GitHub's ubuntu runners and is already a hard
	# requirement of fetch_cores() itself (`need_cmd jq`). Treat its absence
	# as a workflow bug rather than silently degrading to a grep.
	if ! command -v jq >/dev/null 2>&1; then
		echo "::error::PINNED_CORES: jq not found -- cannot parse the ${CORES_PATH} listing"
		hash_sync_record "$outcomes_file" PINNED_CORES failed \
			"jq not found on the runner -- scripts/fetch-sdcard-payload.sh needs it too (need_cmd jq)"
		rm -f "$body"
		exit 0
	fi

	# One jq pass for all three numbers.
	#
	# The selection is `select(.name | endswith(".rbf"))` and NOTHING ELSE --
	# character-for-character what fetch_cores() applies, deliberately, so
	# the count and total below describe exactly the set that would be
	# staged (not the whole directory, which also holds a handful of .mgl
	# launcher stubs this payload does not take). A gate whose filter is
	# merely SIMILAR to the one it predicts is not a gate; it can pass while
	# the release fails. If fetch_cores()'s filter ever changes, change this
	# one in the same commit.
	#
	# An earlier revision of this script narrowed the selection with
	# `.type == "file"`, which looked harmless and was not: it silently
	# diverged from the set fetch_cores() stages. The `type` question is
	# real, so it is asked SEPARATELY rather than folded into the selection
	# -- `nonfile` counts selected entries that are not regular files (a
	# dir/symlink/submodule named "*.rbf"). Those have a null download_url,
	# so fetch_cores()'s `curl -o` would fail the release build on them;
	# reporting the count lets this gate FAIL for that reason explicitly,
	# instead of quietly not counting them.
	local counts n total nonfile
	if ! counts=$(jq -r '[.[] | select(.name | endswith(".rbf"))]
	                     | "\(length) \([.[].size] | add // 0) \([.[] | select(.type != "file")] | length)"' \
	                     "$body" 2>/dev/null); then
		echo "::error::PINNED_CORES: could not parse the ${CORES_PATH} listing as a JSON array of entries"
		hash_sync_record "$outcomes_file" PINNED_CORES failed \
			"HTTP 200 but the ${CORES_PATH} listing did not parse as a contents array -- GitHub API shape changed; fetch_cores()'s jq would break the same way"
		rm -f "$body"
		exit 0
	fi
	rm -f "$body"
	# shellcheck disable=SC2086
	set -- $counts
	n=$1; total=$2; nonfile=$3

	if [ "$nonfile" -gt 0 ]; then
		# Selected by name, but not a regular file -> download_url is null,
		# and fetch_cores() would die on the curl. Caught here instead.
		echo "::error::PINNED_CORES: $nonfile entry(ies) named '*.rbf' under ${CORES_PATH} are not regular files"
		hash_sync_record "$outcomes_file" PINNED_CORES failed \
			"$nonfile of $n '*.rbf' entries at ${CORES_REPO}@${commit} are not type=file (dir/symlink/submodule) -- their download_url is null and fetch_cores() would fail the release build on them"
		exit 0
	fi

	if [ "$n" -eq 0 ]; then
		# The same condition fetch_cores() dies on, caught ~3 hours earlier.
		echo "::error::PINNED_CORES: zero .rbf files under ${CORES_PATH} at $commit"
		hash_sync_record "$outcomes_file" PINNED_CORES failed \
			"${CORES_PATH} at ${CORES_REPO}@${commit} lists zero .rbf files -- API shape changed or the pin is stale (fetch_cores() dies on exactly this)"
		exit 0
	fi

	if [ "$total" -gt "$EXPECT_CORES_MAX_BYTES" ]; then
		echo "::error::PINNED_CORES: ${CORES_PATH} totals $total bytes, over EXPECT_CORES_MAX_BYTES ($EXPECT_CORES_MAX_BYTES)"
		hash_sync_record "$outcomes_file" PINNED_CORES failed \
			"$n .rbf totalling $total bytes EXCEEDS \$EXPECT_CORES_MAX_BYTES ($EXPECT_CORES_MAX_BYTES, ~600 MiB -- docs/verification/sdcard-payload.md §2 / ADR 0020 §3); check-sdcard.sh would reject the built sdcard-full.img"
		exit 0
	fi

	echo "PINNED_CORES ok: $n .rbf, $((total / 1024 / 1024)) MiB at ${CORES_REPO}@${commit} (cap $((EXPECT_CORES_MAX_BYTES / 1024 / 1024)) MiB)"
	hash_sync_record "$outcomes_file" PINNED_CORES already-current \
		"commit-only pin, nothing to refresh; validated: $n .rbf totalling $((total / 1024 / 1024)) MiB at ${CORES_REPO}@${commit}, within the $((EXPECT_CORES_MAX_BYTES / 1024 / 1024)) MiB cap"
}

main
