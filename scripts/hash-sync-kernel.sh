#!/usr/bin/env bash
#
# hash-sync-kernel.sh — case 2 of 4 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): refresh the
# STABLE longterm kernel tarball hash from kernel.org's own signed manifest.
#
# STATUS: WIRED IN. .github/workflows/renovate-hash-sync.yml's "Refresh
# kernel tarball hash from kernel.org's signed manifest" step invokes this
# script directly (from the .hash-sync-tools checkout of the workflow's own
# ref -- see that step's comment in the .yml); there is no separate inline
# copy of this logic left in the workflow. THIS SCRIPT IS AUTHORITATIVE: fix
# bugs in this case here, not in the .yml.
#
# Extracted so this case is independently testable against a fixture. This
# is the case whose PR #41 run (kernel 6.18.38 -> 6.18.39) surfaced the two
# bugs the workflow's own header used to understate: an unanchored defconfig
# grep that built a URL containing a newline (bug #42), and the fact that a
# fetch failure here was only a ::warning:: -- so the job reported SUCCESS
# three times while silently leaving linux.hash stale (run 29669946883).
# Both traps are preserved verbatim below, with the same comments, because
# they are exactly the kind of regression a fixture-based test for this case
# would need to catch (see "Testing against a fixture" below).
#
# Only touches board/mister/de10nano/patches/linux/linux.hash's own sha256
# data line; the header comment block above it is preserved verbatim by only
# ever replacing the matched "sha256" line. Refreshed from kernel.org's own
# PGP-clearsigned sha256sums.asc for the matching v6.x series -- the same URL
# and same trust model docs/renovate.md and the .hash file's own header
# already document as the ONLY legitimate source. This does NOT verify the
# PGP signature (no keyring management here yet) -- it fetches the manifest
# over HTTPS and greps the matching line, which is exactly the same trust
# level as the manual transcription process it replaces, not a regression.
# Verifying the clearsign signature is a worthwhile future hardening step,
# not implemented here (see docs/renovate.md).
#
# THIS SCRIPT MUST NEVER TOUCH (loud, on purpose -- see
# scripts/lib/hash-sync-common.sh for the full statement of both permanent
# prohibitions this workflow family observes):
#
#   * configs/mister_rt.fragment's TOFU-pinned mainline `-rc` kernel hash.
#     linux.hash also carries that RT beta pin's entry; kernel.org signs no
#     manifest for an `-rc` cgit snapshot, so that hash can ONLY be
#     re-derived by hand, per the RT hash file's own documented TOFU
#     procedure. This script's match is deliberately scoped to the STABLE
#     pin's major series specifically so it can never clobber that line --
#     see the "major=" comment below for the incident that made this
#     necessary.
#   * BUILDROOT_SHA256 (root Makefile) -- unrelated to this file, but this
#     script does not touch it either; see scripts/lib/hash-sync-common.sh.
#
# Usage:
#   scripts/hash-sync-kernel.sh [REPO_ROOT]
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
# Sets (via hash_sync_set_env): PATCH_HASH_CHANGED=0|1.
#
# Records ONE row (pin name "kernel") to $HASH_SYNC_OUTCOMES_FILE:
# refreshed | already-current | skipped | failed. APPENDS -- does not
# truncate; scripts/hash-sync-github-packages.sh (case 1, run first in the
# workflow) owns creating/truncating the shared outcomes file for the run.
# Standalone, `touch` the file yourself first if case 1 has not run.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- this runs as its own workflow step, and an
# `exit 1` here would skip cases 3 and 4 entirely (the exact hole item J
# closed; see the .yml's own header). A non-zero exit means something this
# script did not anticipate.
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing a fake configs/mister_de10nano_defconfig (just needs the one
# BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="..." line -- including a SECOND,
# unanchored-looking copy in a comment is exactly the bug-#42 regression
# test this case wants) and a fake linux.hash (with, ideally, both a
# same-major "sha256  ...  linux-X.Y.tar.xz" line AND an RT-style foreign
# entry, to exercise the major-series scoping). Either let it really fetch
# https://cdn.kernel.org/pub/linux/kernel/vX.x/sha256sums.asc for a real
# published version, or prepend a fake `curl` to $PATH that serves a fixture
# manifest:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-kernel.sh /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and the rewritten linux.hash.

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

	local defconfig="configs/mister_de10nano_defconfig"
	local linuxhash="board/mister/de10nano/patches/linux/linux.hash"

	if [ ! -f "$defconfig" ] || [ ! -f "$linuxhash" ]; then
		echo "::warning::$defconfig or $linuxhash not found in this checkout -- skipping kernel"
		hash_sync_record "$outcomes_file" kernel skipped "$defconfig or $linuxhash not found in this checkout"
		hash_sync_set_env PATCH_HASH_CHANGED 0
		exit 0
	fi

	# ANCHOR THIS GREP. The defconfig explains the setting in a comment that
	# quotes it verbatim ("... free-form string BR2_LINUX_KERNEL_CUSTOM_VERSION_
	# VALUE=\"<version>\", which Kconfig ..."), so an unanchored match returns
	# TWO lines. That made $kver a two-line string, `cut` then ran per-line, and
	# the series came out as "v6\n6.x" -- producing a URL with an embedded
	# newline that curl rejected outright ("Malformed input to a URL function").
	# Because a fetch failure is only a warning here, the run went green while
	# silently leaving linux.hash stale (bug #42). Anchoring plus tail -1 keeps
	# it to the real setting; scripts/export-kernel-tree.sh reads the same file
	# the same way.
	#
	# The `|| true` is load-bearing under `set -euo pipefail`: with no match,
	# grep exits 1, pipefail propagates that to the command substitution, and
	# because this is a plain assignment `set -e` aborts right here -- so the
	# explicit empty-check below would never run and the failure would be
	# silent. Swallowing the status lets that check emit its diagnostic instead.
	local kver
	kver=$(grep -oE '^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="[^"]+"' "$defconfig" \
	        | sed -E 's/.*"([^"]+)"/\1/' | tail -1 || true)
	if [ -z "$kver" ]; then
		echo "::error::could not extract BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE from $defconfig" >&2
		# A parse/extract failure against a file THIS repo controls is a bug
		# in this script's own regex, not a transient upstream condition --
		# record it as "failed" (not "skipped") so the workflow's job-summary
		# step fails the run, but exit 0 (not 1) so cases 3 and 4 still run
		# and get their own pins reported on instead of being skipped
		# outright by a halted job. The workflow's "Check for a recorded
		# workflow bug before pushing anything" step reads this same
		# recorded "failed" and suppresses the push job-wide.
		hash_sync_record "$outcomes_file" kernel failed \
			"could not extract BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE from $defconfig"
		hash_sync_set_env PATCH_HASH_CHANGED 0
		exit 0
	fi

	# A malformed version is a bug in THIS script, not a transient network
	# problem, so fail loudly rather than falling through to the warn-and-skip
	# path below. bash's =~ anchors against the whole string, so this also
	# rejects a multi-line $kver if the grep above ever regresses.
	if ! [[ "$kver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
		echo "::error::extracted kernel version is not a plain version string: '${kver}'" >&2
		# Same reasoning as the empty-$kver branch above: fail the run via
		# the recorded outcome, but exit 0 so later cases still execute and
		# get their own pins reported. Same push suppression applies too.
		hash_sync_record "$outcomes_file" kernel failed \
			"extracted kernel version is not a plain version string: '${kver}'"
		hash_sync_set_env PATCH_HASH_CHANGED 0
		exit 0
	fi

	local series manifest_url
	series="v$(echo "$kver" | cut -d. -f1).x"
	manifest_url="https://cdn.kernel.org/pub/linux/kernel/${series}/sha256sums.asc"
	echo "==> kernel $kver: fetching $manifest_url"

	# An upstream fetch failure is a legitimate network blip against
	# kernel.org, not a bug in this script -- stays warn-and-continue.
	local manifest
	manifest=$(curl -fsSL --retry 3 "$manifest_url") || {
		echo "::warning::could not fetch $manifest_url -- leaving $linuxhash untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" kernel skipped "could not fetch $manifest_url"
		hash_sync_set_env PATCH_HASH_CHANGED 0
		exit 0
	}

	# kernel.org's manifest lines look like:
	#   <sha256hash>  linux-6.18.38.tar.xz
	local matchline
	matchline=$(echo "$manifest" | grep -E "  linux-${kver//./\\.}\.tar\.xz\$" | head -1 || true)
	if [ -z "$matchline" ]; then
		# No entry for this exact version is an external/upstream condition
		# (the release tarball may simply not be published to kernel.org
		# yet), not evidence this script mis-parsed anything -- $kver already
		# passed the strict version-format check above. Stays
		# warn-and-continue.
		echo "::warning::no entry for linux-${kver}.tar.xz in $manifest_url -- leaving $linuxhash untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" kernel skipped "no entry for linux-${kver}.tar.xz in $manifest_url"
		hash_sync_set_env PATCH_HASH_CHANGED 0
		exit 0
	fi

	local newhash newline
	newhash=$(echo "$matchline" | awk '{print $1}')
	newline="sha256  ${newhash}  linux-${kver}.tar.xz"

	# Match the RELEASE tarball line SPECIFICALLY, never "the first sha256
	# line": linux.hash also carries entries this script must NOT manage --
	# notably the RT beta's kernel (configs/mister_rt.fragment). A
	# first-line match would clobber whichever entry happened to be on top.
	#
	# Scope the match to THIS pin's major series (linux-<major>.*.tar.xz). An
	# extension-only match (linux-*.tar.xz) is not enough: it is sufficient
	# only while the RT pin is an -rc, because Buildroot fetches -rc as a
	# cgit snapshot (.tar.gz). The moment that pin reaches a stable mainline
	# release it becomes linux-7.2.tar.xz -- which the old pattern also
	# matched. Verified: with the RT line first, a 6.18 bump OVERWROTE it and
	# left the stale 6.18 line intact, producing two 6.18 entries and no RT
	# entry at all. The major-scoped match keeps the two pins on their own
	# lines regardless of order.
	#
	# An RT kernel bump still always needs its hash refreshed BY HAND, per
	# the hash file's documented TOFU procedure -- this script never touches
	# that line either way.
	local major release_re
	major="${kver%%.*}"
	release_re="^sha256  .*  linux-${major}\.[0-9][0-9.]*\.tar\.xz\$"

	# If two lines somehow match, do not guess which one this pin owns.
	local nmatch
	nmatch=$(grep -c -E "$release_re" "$linuxhash" || true)
	if [ "${nmatch:-0}" -gt 1 ]; then
		echo "::error::$linuxhash has $nmatch lines matching the ${major}.x release pattern -- refusing to guess which one belongs to this pin." >&2
		grep -n -E "$release_re" "$linuxhash" >&2 || true
		# An ambiguous $linuxhash (or an over-broad release_re) is this
		# script's own problem to resolve, not an upstream condition -- FAIL
		# via the recorded outcome, same reasoning as the two $kver branches
		# above. exit 0 so cases 3 and 4 still run. Same push suppression
		# applies too.
		hash_sync_record "$outcomes_file" kernel failed \
			"$linuxhash has $nmatch lines matching the ${major}.x release pattern -- refusing to guess"
		hash_sync_set_env PATCH_HASH_CHANGED 0
		exit 0
	fi

	local oldline
	oldline=$(grep -m1 -E "$release_re" "$linuxhash" || true)

	if [ "$oldline" != "$newline" ]; then
		# Replace by EXACT string match on the line we found, not by
		# re-deriving a regex inside awk -- passing a regex through `awk -v`
		# would have its backslash escapes eaten, silently turning `\.` into
		# "any character".
		awk -v oldline="$oldline" -v newline="$newline" '
			BEGIN { done = 0 }
			$0 == oldline && !done { print newline; done = 1; next }
			{ print }
		' "$linuxhash" > "$linuxhash.tmp"
		mv "$linuxhash.tmp" "$linuxhash"
		echo "Updated $linuxhash:"
		echo "  old: $oldline"
		echo "  new: $newline"
		hash_sync_record "$outcomes_file" kernel refreshed "sha256 updated: $oldline -> $newline"
		hash_sync_set_env PATCH_HASH_CHANGED 1
	else
		echo "$linuxhash already up to date."
		hash_sync_record "$outcomes_file" kernel already-current "sha256 unchanged"
		hash_sync_set_env PATCH_HASH_CHANGED 0
	fi
}

main
