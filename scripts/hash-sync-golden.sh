#!/usr/bin/env bash
#
# hash-sync-golden.sh — renovate-hash-sync case 8: on a Buildroot bump,
# record the new version's golden config hashes
# (configs/fragments/golden.sha256) so the bump PR is complete on its own.
#
# WHY. scripts/check-config-fragments.sh (d) pins the sha256 of every fragment
# stack's normalised resolved .config per BUILDROOT_VERSION. A Buildroot bump
# changes Kconfig defaults, so it is EXPECTED to move every hash; the check
# therefore treats "no line for this Buildroot version" as a ::warning, not a
# failure, so the automated bump PR still gets its build. This case is what
# turns that warning back into a recorded line: it runs the check's own
# --update-golden against the freshly bumped tree and the workflow commits the
# result alongside the BUILDROOT_SHA256 transcription case 6 just made.
#
# WHAT IT RUNS, AND FROM WHERE. Unlike the other cases this one deliberately
# executes the TARGET BRANCH's scripts/check-config-fragments.sh (through the
# target branch's Makefile: `make buildroot-unpack` fetches + hash-verifies the
# NEW tarball using the hash case 6 wrote), not a copy from .hash-sync-tools:
# the golden file's format and normalisation rules are defined by the check
# script in the same tree, and a golden written by a different version of the
# rules would be wrong by construction. A branch that predates the fragment
# split has no such script and is skipped.
#
# WHEN IT WRITES. Only when golden.sha256 has NO line at all for the tree's
# BUILDROOT_VERSION (a bump). If lines exist, any mismatch is real drift and
# is lint-config's to fail on -- this case must never bless it, so it records
# `skipped` and leaves the file alone. A kernel bump does not move the golden
# (the kernel version symbols are excluded from the normalisation), so on the
# weekly kernel PRs this case is a no-op.
#
# Cost: one 10 MB tarball download plus Buildroot's kconfig `conf` build and
# one olddefconfig per stack -- no toolchain, no package, no compile.
#
# Exit: always 0 on a handled path, same as every other case (see
# hash-sync-kernel.sh's header for why); a non-zero exit is a bug here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

OUTCOME_PIN="golden"
CHANGED_VAR="GOLDEN_CHANGED"

REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
[ -d "$REPO_ROOT" ] || { echo "::error::REPO_ROOT '$REPO_ROOT' is not a directory" >&2; exit 2; }

: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local check="scripts/check-config-fragments.sh"
	local golden="configs/fragments/golden.sha256"
	if [ ! -x "$check" ] || [ ! -f "$golden" ]; then
		echo "::notice::$check or $golden not in this checkout (pre-fragment-split branch) -- skipping $OUTCOME_PIN"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "$check or $golden not in this checkout"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	local ver
	ver=$(sed -n -e 's/[[:space:]]*$//' -e 's/^BUILDROOT_VERSION[[:space:]]*?=[[:space:]]*//p' Makefile | head -1)
	if [ -z "$ver" ]; then
		echo "::error::could not extract BUILDROOT_VERSION from Makefile" >&2
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed "could not extract BUILDROOT_VERSION from Makefile"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	if awk -v v="$ver" '$1 == v { found = 1 } END { exit !found }' "$golden"; then
		echo "==> $OUTCOME_PIN: $golden already records Buildroot $ver -- nothing to add (drift, if any, is lint-config's to report, never this case's to bless)"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" already "golden already recorded for Buildroot $ver"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	echo "==> $OUTCOME_PIN: no golden lines for Buildroot $ver -- regenerating"
	# buildroot-unpack fetches and hash-verifies the NEW tarball with the
	# BUILDROOT_SHA256 case 6 just transcribed; if that failed or was skipped,
	# this fails closed too and the PR stays red at the same place.
	if ! make --no-print-directory buildroot-unpack; then
		echo "::warning::make buildroot-unpack failed for Buildroot $ver -- leaving $golden untouched (lint-config will warn, not fail)"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "make buildroot-unpack failed for Buildroot $ver"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi
	if ! "$check" --update-golden; then
		# --update-golden still runs (a)-(c); a failure there is a real
		# fragment problem the PR must fix, not something to paper over.
		echo "::warning::$check --update-golden reported failures -- $golden NOT committed; see the check's output"
		git checkout -- "$golden" 2>/dev/null || true
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "$check failed under Buildroot $ver"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	if git diff --quiet -- "$golden"; then
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" already "golden unchanged"
		hash_sync_set_env "$CHANGED_VAR" 0
	else
		echo "Updated $golden:"
		git --no-pager diff -- "$golden"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" refreshed "recorded golden hashes for Buildroot $ver"
		hash_sync_set_env "$CHANGED_VAR" 1
	fi
}

main "$@"
