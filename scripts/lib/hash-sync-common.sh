#!/usr/bin/env bash
# scripts/lib/hash-sync-common.sh — shared plumbing for the renovate-hash-sync
# case scripts (scripts/hash-sync-*.sh). Not directly executable; sourced by
# each of them. TASKS.md P4.6; extracted from .github/workflows/
# renovate-hash-sync.yml so each of that workflow's four hash-refresh cases
# is its own testable script instead of one 700-line embedded-shell workflow
# file (see that workflow's own header for the run-29669946883 incident that
# motivated testability in the first place).
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's four
# hash-refresh steps invoke scripts/hash-sync-{github-packages,kernel,
# lzma-sdk,sdcard-payload}.sh directly (each from the .hash-sync-tools
# checkout of the workflow's own ref), and every one of those scripts sources
# this file -- there is no separate inline copy of the per-pin outcome-ledger
# logic left in the workflow YAML. (The push-gate and job-summary steps still
# live in the .yml itself, since they only READ the outcomes file these
# scripts write, via the same $RUNNER_TEMP/$HASH_SYNC_OUTCOMES_FILE path --
# see hash_sync_resolve_outcomes_file below.) THIS FILE IS AUTHORITATIVE for
# the shared outcome-ledger plumbing: fix bugs here, not in the .yml.
#
# What lives here, and why it is shared rather than copy-pasted four times:
#
#   * The per-pin outcome ledger (hash_sync_record). Every case script must
#     record refreshed/already-current/skipped/failed for each pin it owns,
#     to the SAME TSV file, in the SAME "<pin>\t<outcome>\t<reason>" shape --
#     the workflow's job-summary/gate steps (still in the .yml; not part of
#     this extraction) parse that file expecting exactly this format. One
#     implementation here means the four case scripts cannot drift apart on
#     it.
#   * Outcomes-file path resolution (hash_sync_resolve_outcomes_file). In the
#     workflow, $HASH_SYNC_OUTCOMES_FILE is a bare filename (a job-level env:
#     block cannot reach $RUNNER_TEMP -- see that env var's own comment in
#     the workflow) and every step prefixes it with $RUNNER_TEMP itself. On
#     the actual runner $RUNNER_TEMP is always set, so this reproduces that
#     behavior exactly. Standalone/fixture invocation (this extraction's
#     whole point) has no $RUNNER_TEMP, so this also accepts an
#     already-absolute path and falls back to $TMPDIR/tmp -- see the
#     function's own comment.
#   * The $GITHUB_ENV shim (hash_sync_set_env). The workflow's *_CHANGED
#     flags are consumed by the "Commit and push" step's `if:` condition via
#     $GITHUB_ENV. Outside Actions that variable is unset, and appending to
#     an unset/empty path is an "ambiguous redirect" error -- this shim keeps
#     every case script runnable standalone against a fixture without
#     changing what happens on the real runner (where $GITHUB_ENV is always
#     set).
#
# What does NOT live here, on purpose: nothing about WHICH pins exist or
# HOW each is fetched/parsed -- that is each case script's own business, and
# each one's header carries its own case-specific rationale (including the
# load-bearing shell subtleties: the anchored-grep-plus-tail--1 kernel-version
# extraction, the `|| true` needed under `set -euo pipefail`, the
# major-series-scoped linux.hash match, and the exact-string awk replacement).
# This file only carries the bookkeeping every case script needs identically.
#
# This workflow's two permanent, cross-cutting prohibitions -- restated here
# because this is the one file every case script sources, so this is where a
# future fifth case script is most likely to be reviewed against them:
#
#   * BUILDROOT_SHA256 (root Makefile) is NEVER refreshed by any script in
#     this family. That value is only legitimate when transcribed BY A HUMAN
#     from Buildroot's GPG-signed release manifest
#     (https://buildroot.org/downloads/buildroot-<ver>.tar.gz.sign) --
#     a locally-computed sha256sum of the downloaded tarball is explicitly
#     forbidden there (it would certify nothing and could bless a
#     tampered/truncated tarball). See the root Makefile's own header and
#     docs/renovate.md.
#   * configs/mister_rt.fragment's TOFU-pinned mainline `-rc` kernel hash is
#     NEVER refreshed by any script in this family either. kernel.org signs
#     no manifest for an `-rc` cgit snapshot, so that pin's hash is
#     Trust-On-First-Use and can ONLY be re-derived by hand, per the RT
#     hash file's own documented procedure. scripts/hash-sync-kernel.sh
#     (case 2) refreshes the STABLE longterm kernel pin in the same
#     linux.hash file and is deliberately scoped (by major series) to never
#     touch this line -- see that script's own header and inline comments.

set -euo pipefail

# hash_sync_resolve_outcomes_file NAME_OR_PATH
#   Prints the full path to use for the outcomes TSV, to stdout.
#
#   - An already-absolute path (a maintainer testing standalone, or a fixture
#     harness) is used as-is.
#   - A bare filename (the production/workflow case -- see this file's own
#     header above) is prefixed with $RUNNER_TEMP, falling back to $TMPDIR
#     then /tmp so this is also safe to call with $RUNNER_TEMP unset, i.e.
#     outside Actions.
hash_sync_resolve_outcomes_file() {
	local name_or_path="$1"
	case "$name_or_path" in
		/*) printf '%s\n' "$name_or_path" ;;
		*) printf '%s/%s\n' "${RUNNER_TEMP:-${TMPDIR:-/tmp}}" "$name_or_path" ;;
	esac
}

# hash_sync_record OUTCOMES_FILE PIN OUTCOME REASON
#   Appends one "<pin>\t<outcome>\t<reason>" row. OUTCOME is one of
#   refreshed | already-current | skipped | failed -- the same four values
#   the workflow's job-summary step has always tabulated; this extraction
#   does not add, remove, or rename any of them (item J is not being
#   re-litigated here).
hash_sync_record() {
	local outcomes_file="$1" pin="$2" outcome="$3" reason="$4"
	printf '%s\t%s\t%s\n' "$pin" "$outcome" "$reason" >> "$outcomes_file"
}

# hash_sync_set_env NAME VALUE
#   Appends NAME=VALUE to $GITHUB_ENV, exactly like every step in the
#   original workflow did directly. When $GITHUB_ENV is unset (standalone/
#   fixture invocation, i.e. not running as an Actions step) this prints the
#   assignment to stdout instead of erroring on an ambiguous redirect --
#   production behavior on the actual runner (where $GITHUB_ENV is always
#   set) is unchanged.
hash_sync_set_env() {
	local name="$1" value="$2"
	if [ -n "${GITHUB_ENV:-}" ]; then
		printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
	else
		printf '%s=%s\n' "$name" "$value"
	fi
}
