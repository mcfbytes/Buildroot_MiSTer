#!/usr/bin/env bash
#
# hash-sync-kernel.sh — case 2 of 4 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): refresh a pinned
# kernel tarball hash from kernel.org's own signed manifest.
#
# TWO PINS, ONE SCRIPT, ONE SHARED linux.hash (since 2026-08-17). Select with
# the --pin option; the default is `stable`, which is the behavior this script
# had when it took no options at all:
#
#   --pin=stable   the 6.18.y longterm kernel that the SHIPPED image runs.
#                  Version read from configs/mister_de10nano_defconfig.
#   --pin=rt       the RT/beta kernel variant (docs/rt-beta-kernel.md).
#                  Version read from configs/mister_rt.fragment.
#
# WHY `rt` EXISTS NOW, HAVING BEEN FORBIDDEN BEFORE -- read this before
# "restoring" the old prohibition, because the change is deliberate and the old
# comment is still quoted in older commits. The RT pin used to track mainline
# `-rc`, and Buildroot fetches an `-rc` as a cgit-generated snapshot
# (linux-<ver>.tar.GZ) for which kernel.org publishes NO signed manifest. Such
# a hash can only be Trust-On-First-Use from a download a human actually
# inspected, so automating it would have meant inventing trust -- the same
# reason BUILDROOT_SHA256 is still never automated. Linux 7.2 released on
# 2026-08-16, the RT pin moved onto the 7.2 line, and its artifact became an
# ordinary linux-7.2.tar.XZ off the kernel.org mirror -- which IS covered by
# the PGP-signed sha256sums.asc, exactly like the stable pin. Same source, same
# trust level, so the same automation applies.
#
# WHAT DID NOT CHANGE: an `-rc` is still never automated. This script REFUSES
# any extracted version containing `-rc`, records `skipped`, and leaves the
# line alone, so the build fails closed at the kernel download rather than
# blessing a snapshot nobody looked at. That refusal is what makes the `rt`
# case safe even if a human hand-points the fragment back at an `-rc`
# (renovate.json's allowedVersions stops Renovate from doing it on its own).
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
# data line for the selected pin; the header comment blocks are preserved
# verbatim by only ever replacing the matched "sha256" line. Refreshed from
# kernel.org's own PGP-clearsigned sha256sums.asc for the matching vN.x series
# -- the same URL and same trust model docs/renovate.md and the .hash file's
# own header already document as the ONLY legitimate source. This does NOT
# verify the PGP signature (no keyring management here yet) -- it fetches the
# manifest over HTTPS and greps the matching line, which is exactly the same
# trust level as the manual transcription process it replaces, not a
# regression. Verifying the clearsign signature is a worthwhile future
# hardening step, not implemented here (see docs/renovate.md). NOTE that a
# human CAN do better and did on the 7.2 crossing: linux.hash's RT block
# records a real `gpg --verify` of that manifest. This script not doing so is
# a gap in the automation, not a statement that the check is unavailable.
#
# HOW THE TWO PINS STAY OFF EACH OTHER'S LINE, since they share one file: each
# pin's line match is scoped to ITS OWN MAJOR SERIES (linux-<major>....tar.xz).
# 6.18.y matches only linux-6.*, the 7.2 line only linux-7.*. That scoping
# predates the `rt` case -- it was added when the RT pin was still an -rc, to
# stop the stable pin from clobbering a line it did not own -- and it is what
# makes running both pins against one file safe now. If the two pins ever land
# on the SAME major series, both would match both lines; the ambiguity guard
# below catches that and FAILS rather than guessing, which is the correct
# outcome and a loud one.
#
# THIS SCRIPT MUST NEVER TOUCH (loud, on purpose -- see
# scripts/lib/hash-sync-common.sh for the full statement of both permanent
# prohibitions this workflow family observes):
#
#   * ANY `-rc` kernel hash, for either pin -- see the header note above.
#   * BUILDROOT_SHA256 (root Makefile) -- unrelated to this file, but this
#     script does not touch it either; see scripts/lib/hash-sync-common.sh.
#
# Usage:
#   scripts/hash-sync-kernel.sh [--pin=stable|rt] [REPO_ROOT]
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
# Sets (via hash_sync_set_env), ONE PER PIN and deliberately not shared --
# see the CHANGED_VAR note in the body for the push-gate clobber this avoids:
#   --pin=stable   PATCH_HASH_CHANGED=0|1
#   --pin=rt       RT_PATCH_HASH_CHANGED=0|1
# Both are ORed by the .yml's "Commit and push hash refresh" gate. A new pin
# means a new variable AND a new clause in that gate; miss the second half and
# that pin's refresh is computed, written to the working tree, and never
# committed.
#
# Records ONE row per INVOCATION to $HASH_SYNC_OUTCOMES_FILE: refreshed |
# already-current | skipped | failed. The row is named for the pin -- "kernel"
# for --pin=stable, "kernel-rt" for --pin=rt. The stable row keeps its
# historical name deliberately: it is what the workflow's outcome ledger and
# every past run's job summary already call this case, and renaming it would
# silently break nothing while making old runs unreadable. APPENDS -- does not
# truncate; scripts/hash-sync-github-packages.sh (case 1, run first in the
# workflow) owns creating/truncating the shared outcomes file for the run.
# Standalone, `touch` the file yourself first if case 1 has not run.
#
# Because the two pins run as two separate invocations (two workflow steps),
# each gets its own row and its own verdict -- one can be `refreshed` while the
# other is `already-current`, which is the normal case: Renovate raises one PR
# per pin, so the other pin's version has not moved.
#
# Exit: always 0 on a handled path (including a recorded "failed"), same as
# every other case script -- this runs as its own workflow step, and an
# `exit 1` here would skip cases 3 and 4 entirely (the exact hole item J
# closed; see the .yml's own header). A non-zero exit means something this
# script did not anticipate.
#
# Testing against a fixture: point REPO_ROOT at a scratch directory
# containing a fake version file for the pin under test -- configs/
# mister_de10nano_defconfig for `stable`, configs/mister_rt.fragment for `rt`
# (each just needs the one BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="..." line;
# including a SECOND, unanchored-looking copy in a comment is exactly the
# bug-#42 regression test this case wants) -- plus a fake linux.hash carrying
# BOTH pins' lines, which is what exercises the major-series scoping. The
# scoping assertion worth writing is two-directional and cheap: run --pin=rt
# and confirm the 6.18 line is byte-identical afterwards, then run
# --pin=stable and confirm the 7.2 line is. Either let it really fetch
# https://cdn.kernel.org/pub/linux/kernel/vX.x/sha256sums.asc for a real
# published version, or prepend a fake `curl` to $PATH that serves a fixture
# manifest:
#
#   HASH_SYNC_OUTCOMES_FILE=/tmp/out.tsv \
#   PATH="/path/to/fixture/bin:$PATH" \
#   scripts/hash-sync-kernel.sh --pin=rt /path/to/fixture-repo-root
#
# then inspect /tmp/out.tsv and the rewritten linux.hash. The `-rc` refusal is
# the other case worth a fixture, and it needs no network at all: set the
# fragment to 7.3-rc1 and assert the recorded outcome is `skipped` and
# linux.hash is untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

usage() {
	echo "usage: $(basename "$0") [--pin=stable|rt] [REPO_ROOT]" >&2
	exit 2
}

PIN=stable
while [ "$#" -gt 0 ]; do
	case "$1" in
		--pin=*) PIN="${1#--pin=}"; shift ;;
		--pin)   PIN="${2:-}"; shift 2 || usage ;;
		-*)      usage ;;
		*)       break ;;
	esac
done

[ "$#" -le 1 ] || usage

# Per-pin configuration, resolved ONCE here so the body below reads the same
# for both pins and no later branch has to re-ask "which pin am I?".
#
#   VERSION_FILE  where the pinned version is read from
#   OUTCOME_PIN   the row name in the outcomes ledger
#   CHANGED_VAR   the env var the workflow's push gate ORs together
#
# CHANGED_VAR MUST DIFFER PER PIN, and this is not cosmetic. hash_sync_set_env
# appends to $GITHUB_ENV, where the LAST write to a key wins. Both pins run as
# separate steps in one job, so a shared name would let the second invocation
# overwrite the first's verdict: stable refreshes (1), rt is already-current
# (0), the gate reads 0, and the push step is skipped -- the stable hash sits
# refreshed in the working tree and is never committed. Green run, stale
# branch, no diagnostic. The stable pin KEEPS the historical PATCH_HASH_CHANGED
# name so the existing gate expression and every past run stay meaningful; the
# rt pin gets its own, which the .yml's gate must OR in (it does).
case "$PIN" in
	stable)
		VERSION_FILE="configs/mister_de10nano_defconfig"
		OUTCOME_PIN="kernel"
		CHANGED_VAR="PATCH_HASH_CHANGED"
		;;
	rt)
		VERSION_FILE="configs/mister_rt.fragment"
		OUTCOME_PIN="kernel-rt"
		CHANGED_VAR="RT_PATCH_HASH_CHANGED"
		;;
	*)
		echo "::error::unknown --pin '$PIN' (expected 'stable' or 'rt')" >&2
		usage
		;;
esac

REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
[ -d "$REPO_ROOT" ] || { echo "::error::REPO_ROOT '$REPO_ROOT' is not a directory" >&2; exit 2; }

: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local defconfig="$VERSION_FILE"
	local linuxhash="board/mister/de10nano/patches/linux/linux.hash"

	if [ ! -f "$defconfig" ] || [ ! -f "$linuxhash" ]; then
		echo "::warning::$defconfig or $linuxhash not found in this checkout -- skipping $OUTCOME_PIN"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "$defconfig or $linuxhash not found in this checkout"
		hash_sync_set_env "$CHANGED_VAR" 0
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
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed \
			"could not extract BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE from $defconfig"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	# REFUSE `-rc`, FOR EITHER PIN. This is the one permanent prohibition this
	# script enforces at runtime rather than by scoping, and it must come
	# BEFORE the format check below -- otherwise an -rc would be reported as
	# "malformed", i.e. as a bug in this script, when it is in fact a
	# well-formed version this script is deliberately declining to handle.
	#
	# kernel.org publishes NO signed manifest for an -rc: sha256sums.asc covers
	# releases only, and Buildroot fetches an -rc as a cgit-generated snapshot
	# (linux-<ver>.tar.GZ from git.kernel.org/torvalds/t, linux/linux.mk:35),
	# not as a mirror tarball. There is therefore nothing to transcribe FROM,
	# and the only honest way to produce that hash is for a human to inspect a
	# local download and pin it Trust-On-First-Use -- see linux.hash's own
	# header for the procedure. Automating it would mean computing a sha256 of
	# whatever arrived and calling that provenance, which is circular and is
	# exactly what this workflow family refuses to do for BUILDROOT_SHA256 too.
	#
	# `skipped`, not `failed`: an -rc pin is a legitimate state of the tree
	# (the RT variant lived there for months), not a defect. The consequence is
	# that linux.hash keeps whatever line it has, so the build fails CLOSED at
	# the kernel download until a human writes the value -- loud, safe, and the
	# same failure mode this pin had before any of it was automated.
	if [[ "$kver" == *-rc* ]]; then
		echo "==> $OUTCOME_PIN $kver: -rc pin, refusing to automate (kernel.org signs no manifest for a cgit snapshot)"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped \
			"'$kver' is an -rc: kernel.org signs no manifest for a cgit snapshot, so this hash must be hand-written TOFU per linux.hash's header"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	# A malformed version is a bug in THIS script, not a transient network
	# problem, so fail loudly rather than falling through to the warn-and-skip
	# path below. bash's =~ anchors against the whole string, so this also
	# rejects a multi-line $kver if the grep above ever regresses.
	#
	# TWO COMPONENTS IS VALID and is not an oversight to "fix": kernel.org
	# publishes a .0 release as linux-7.2.tar.xz, never linux-7.2.0.tar.xz, so
	# the RT pin legitimately reads "7.2" while the kernel it builds calls
	# itself 7.2.0. Everything downstream here is built from $kver verbatim, so
	# the filename this script looks for stays the one that actually exists.
	if ! [[ "$kver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
		echo "::error::extracted kernel version is not a plain version string: '${kver}'" >&2
		# Same reasoning as the empty-$kver branch above: fail the run via
		# the recorded outcome, but exit 0 so later cases still execute and
		# get their own pins reported. Same push suppression applies too.
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed \
			"extracted kernel version is not a plain version string: '${kver}'"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	local series manifest_url
	series="v$(echo "$kver" | cut -d. -f1).x"
	manifest_url="https://cdn.kernel.org/pub/linux/kernel/${series}/sha256sums.asc"
	echo "==> $OUTCOME_PIN $kver: fetching $manifest_url"

	# An upstream fetch failure is a legitimate network blip against
	# kernel.org, not a bug in this script -- stays warn-and-continue.
	local manifest
	manifest=$(curl -fsSL --retry 3 "$manifest_url") || {
		echo "::warning::could not fetch $manifest_url -- leaving $linuxhash untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "could not fetch $manifest_url"
		hash_sync_set_env "$CHANGED_VAR" 0
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
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" skipped "no entry for linux-${kver}.tar.xz in $manifest_url"
		hash_sync_set_env "$CHANGED_VAR" 0
		exit 0
	fi

	local newhash newline
	newhash=$(echo "$matchline" | awk '{print $1}')
	newline="sha256  ${newhash}  linux-${kver}.tar.xz"

	# Match THIS pin's release-tarball line SPECIFICALLY, never "the first
	# sha256 line": linux.hash carries BOTH pins' entries, and a first-line
	# match would clobber whichever happened to be on top.
	#
	# Scope the match to THIS pin's major series (linux-<major>....tar.xz). An
	# extension-only match (linux-*.tar.xz) is not enough, and the reason has
	# now actually happened rather than being hypothetical: it was sufficient
	# only while the RT pin was an -rc, because Buildroot fetches an -rc as a
	# cgit snapshot (.tar.GZ) which no .tar.xz pattern can match. On 2026-08-17
	# that pin reached a stable release and its line became linux-7.2.tar.xz --
	# precisely the collision this scoping was written in advance to survive,
	# and the reason both pins can now be automated against one shared file.
	# Verified back then: with the RT line first, a 6.18 bump OVERWROTE it and
	# left the stale 6.18 line intact, producing two 6.18 entries and no RT
	# entry at all. The major-scoped match keeps the two pins on their own
	# lines regardless of order.
	#
	# Confirm before "simplifying" this pattern: it must match BOTH shapes the
	# two pins produce -- three-component linux-6.18.44.tar.xz and
	# two-component linux-7.2.tar.xz. It does; [0-9] takes the first digit and
	# [0-9.]* takes the (possibly empty) rest, so a .0 release published under
	# a two-component name is not a special case here.
	#
	# The remaining prohibition is the -rc refusal above, which is enforced
	# before this point is ever reached, for either pin.
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
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" failed \
			"$linuxhash has $nmatch lines matching the ${major}.x release pattern -- refusing to guess"
		hash_sync_set_env "$CHANGED_VAR" 0
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
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" refreshed "sha256 updated: $oldline -> $newline"
		hash_sync_set_env "$CHANGED_VAR" 1
	else
		echo "$linuxhash already up to date."
		hash_sync_record "$outcomes_file" "$OUTCOME_PIN" already-current "sha256 unchanged"
		hash_sync_set_env "$CHANGED_VAR" 0
	fi
}

main
