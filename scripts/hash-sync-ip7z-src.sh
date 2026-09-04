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
# "Testing against a fixture" below.
#
# FIRST REAL RUN: PR #149 (ip7z/7zip 26.02 -> 26.03), 2026-09-04. The tarball
# refresh itself was CORRECT -- both .hash files got the right new sha256 for
# 7z2603-src.tar.xz on the first try, so the regex, the dots-stripped filename
# derivation, the release-asset URL and the two-package table are now proven
# against a real PR rather than reviewed by hand. What the run exposed was the
# LICENSE-FILE gap this script used to leave to a human, described next.
#
# Bespoke, NOT part of the generic github-packages loop (case 1,
# scripts/hash-sync-github-packages.sh): these tarballs are GitHub release
# ASSETS, not $(call github,...) commit/tag archives, and the filename is
# derived from the version with the dots stripped (<PKG>_SOURCE =
# 7z$(subst .,,<PKG>_VERSION)-src.tar.xz, so 26.02 -> 7z2602-src.tar.xz).
# Trust model is the same as case 1's: upstream publishes no checksums
# anywhere (checked at pin time -- see each .hash file's own header), so a
# locally-computed sha256 of the freshly-fetched asset is the legitimate
# source.
#
# LICENSE FILES ARE REFRESHED TOO, as of 2026-09-04. This used to read "only
# the FIRST sha256 line (the tarball) is rewritten; if a DOC/ line legitimately
# changed too, the build fails closed and a human re-derives it by hand." That
# fail-closed is real and correct -- but it fires on `make legal-info`, which
# in this repo runs at the END of a ~80-minute image build, so in practice the
# human learned about it from a RED MASTER rather than from the PR. That is
# what happened on PR #149: 26.03 rewrapped DOC/readme.txt (version banner plus
# three typo fixes, no change of terms), lzma-sdk's legal-info rejected the
# stale hash, and master went red for a bump that was otherwise perfect.
#
# So this script now derives the license-file hashes from the SAME tarball it
# just hashed, exactly as case 7 (scripts/hash-sync-azcopy.sh) has always done
# for azcopy's LICENSE/NOTICE.txt -- see that script's "LICENSE/NOTICE.txt ARE
# REFRESHED TOO" note for the shared rationale. Having already downloaded and
# verified the asset, reading two more files out of it costs nothing.
#
# THIS TRADES A HARD STOP FOR A REVIEWABLE DIFF, WHICH IS THE POINT -- but it
# does mean a silent relicense could now ride in on a green PR, so the trade is
# only honest because of the next paragraph. Do not delete it.
#
# WHEN A LICENSE FILE CHANGES, THE DIFF IS PRINTED. On any license-hash change
# the script re-fetches the PREVIOUS version's asset (recovered from the old
# filename in the .hash line it is about to overwrite) and emits a unified diff
# of the license text into the step log, plus a ::warning:: and a loud outcome
# row. A reviewer then sees "banner + typo fixes" (fine, merge) versus "the
# grant sentence changed" (stop) without having to fetch anything by hand. The
# diff is BEST-EFFORT: if the old asset cannot be fetched or its version cannot
# be parsed, the refresh still happens and a ::notice:: says the diff was
# unavailable. It must never be able to fail the refresh.
#
# Which files these are is read from <PKG>_LICENSE_FILES in the .mk -- the same
# single-source-of-truth rule case 7 follows for azcopy.mk. Nothing is
# hard-coded here, so adding a license file to a .mk needs no edit to this
# script. Note the two packages deliberately list DIFFERENT sets: 7zip pins
# only DOC/License.txt, while lzma-sdk also pins DOC/readme.txt because that is
# where the public-domain grant for the C/ code actually lives (see the license
# comment in lzma-sdk.mk). That asymmetry is exactly why 26.03 broke one
# package's legal-info and not the other's.
#
# A license file listed in the .mk but MISSING FROM THE TARBALL is a `failed`
# outcome and leaves the .hash untouched, mirroring case 7: upstream renaming
# or dropping a license file needs a human to look at <PKG>_LICENSE_FILES
# before the pin can move, and writing a correct tarball hash beside a license
# line nobody re-derived would be worse than refreshing nothing.
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
# containing fake package/<pkg>/<pkg>.mk files (each needs a <VAR> = <ver>
# line and, to exercise the license path, a <PKG>_LICENSE_FILES = ... line)
# and fake package/<pkg>/<pkg>.hash files (a
# "sha256  ...  7z<verdigits>-src.tar.xz" line, a sha256 line per license
# file, plus provenance comments, to confirm those survive untouched).
# Cases worth covering, all reachable with two real versions of the asset:
# an unchanged license file (already-current), a changed one (refreshed +
# the diff), one named in the .mk but absent from the .hash (warning, no
# line added), and one named in the .mk but absent from the tarball
# (`failed`, .hash untouched). Either let it really fetch real ip7z/7zip
# release assets, or prepend a fake `curl` to $PATH that serves a fixture
# asset:
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

SCRATCH=""
# `return 0` is load-bearing, not decorative -- bash propagates a non-zero
# status out of an EXIT trap, so a bare `[ -n "$SCRATCH" ] && rm -rf ...` would
# make the script exit 1 on any path that never allocated a scratch dir. Same
# trap, same footgun, same fix as scripts/hash-sync-azcopy.sh; see the longer
# note in that file for the incident that found it.
cleanup() {
	if [ -n "$SCRATCH" ]; then
		rm -rf "$SCRATCH"
	fi
	return 0
}
trap cleanup EXIT

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

	local asset url wd tmpfile
	asset="7z$(echo "$version" | tr -d .)-src.tar.xz"
	url="https://github.com/ip7z/7zip/releases/download/${version}/${asset}"
	echo "==> $pkg $version: fetching $url"
	wd="$(mktemp -d "$SCRATCH/$pkg.XXXXXX")"
	tmpfile="$wd/$asset"
	if ! curl -fsSL --retry 3 "$url" -o "$tmpfile"; then
		# A download failure against an upstream release asset is a
		# legitimate network blip -- stays warn-and-continue.
		echo "::warning::could not download $url -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$pkg" skipped "could not download $url"
		hash_sync_set_env "$env_var" 0
		return 0
	fi
	local newhash
	newhash=$(sha256sum "$tmpfile" | cut -d' ' -f1)

	# The tarball line still carries the OLD asset name at this point, so it
	# is matched by its "-src.tar.xz" suffix rather than by name -- the same
	# reason case 7 matches azcopy's by "-go2.tar.gz".
	local newline oldline old_asset
	newline="sha256  ${newhash}  ${asset}"
	oldline=$(awk '$1 == "sha256" && $3 ~ /-src\.tar\.xz$/ { print; exit }' "$hashfile" || true)
	old_asset=$(printf '%s\n' "$oldline" | awk '{ print $3 }')

	# --- license files ---------------------------------------------------
	# <PKG>_LICENSE_FILES in the .mk is the single source of truth for which
	# files these are; see this script's header. The archive is FLAT
	# (<PKG>_STRIP_COMPONENTS = 0), so each entry is also its exact member
	# path inside the tarball and its exact filename column in the .hash --
	# no path translation needed anywhere in here.
	local lic_var="${version_var%_VERSION}_LICENSE_FILES"
	local license_files
	license_files=$(grep -E "^${lic_var}[[:space:]]*=" "$mk" | head -1 \
	                 | sed -E "s/^${lic_var}[[:space:]]*=[[:space:]]*//" || true)

	local licmap="$wd/licmap.tsv" lic_changed=""
	: > "$licmap"
	if [ -z "$license_files" ]; then
		# Not fatal: the tarball hash is still correct and useful. But say
		# so loudly -- a .mk that stopped matching this grep (a continued
		# line, a rename) would otherwise silently revert this case to its
		# pre-2026-09-04 behavior and put the legal-info break back.
		echo "::warning::could not parse $lic_var from $mk -- refreshing the tarball hash only; any changed license file will fail closed in legal-info as it did before PR #149"
	else
		local lf lf_hash old_lf_line
		for lf in $license_files; do
			if ! tar -C "$wd" -xJf "$tmpfile" "$lf" 2>/dev/null; then
				echo "::error::$pkg $version's tarball does not contain $lf, which $lic_var names"
				hash_sync_record "$outcomes_file" "$pkg" failed \
					"$lf missing from $asset -- upstream renamed or dropped a license file; $lic_var in $mk needs a human before this pin can move"
				hash_sync_set_env "$env_var" 0
				return 0
			fi
			lf_hash=$(sha256sum "$wd/$lf" | cut -d' ' -f1)
			old_lf_line=$(awk -v f="$lf" '$1 == "sha256" && $3 == f { print; exit }' "$hashfile" || true)
			if [ -z "$old_lf_line" ]; then
				# Deliberately NOT auto-added: giving a license file its
				# first recorded hash is a trust decision, not a refresh.
				echo "::warning::$lic_var names $lf but $hashfile has no sha256 line for it -- add one by hand if it should be pinned"
				continue
			fi
			printf '%s\t%s\n' "$lf" "$lf_hash" >> "$licmap"
			if [ "$(printf '%s\n' "$old_lf_line" | awk '{ print $2 }')" != "$lf_hash" ]; then
				lic_changed="${lic_changed}${lic_changed:+ }$lf"
			fi
		done
	fi

	# Rewrite matched BY FILENAME so the provenance comments -- which are most
	# of both these files -- survive verbatim.
	awk -v tarline="$newline" -v mapfile="$licmap" '
		BEGIN {
			while ((getline line < mapfile) > 0) {
				split(line, a, "\t"); h[a[1]] = a[2]
			}
		}
		$1 == "sha256" && $3 ~ /-src\.tar\.xz$/ { print tarline; next }
		$1 == "sha256" && ($3 in h) { print "sha256  " h[$3] "  " $3; next }
		{ print }
	' "$hashfile" > "$hashfile.tmp"

	if cmp -s "$hashfile" "$hashfile.tmp"; then
		rm -f "$hashfile.tmp"
		echo "$hashfile already up to date."
		hash_sync_record "$outcomes_file" "$pkg" already-current "tarball and license-file sha256s unchanged"
		hash_sync_set_env "$env_var" 0
		return 0
	fi
	mv "$hashfile.tmp" "$hashfile"
	echo "Updated $hashfile:"
	echo "  old: $oldline"
	echo "  new: $newline"

	local reason="sha256 updated: $oldline -> $newline"
	if [ -n "$lic_changed" ]; then
		# The loud path. See "WHEN A LICENSE FILE CHANGES" in the header:
		# auto-refreshing these is only defensible because the reviewer is
		# handed the actual textual diff here.
		echo "::warning::$pkg: license file(s) CHANGED across this bump: $lic_changed -- read the diff below and confirm the terms did not change before merging"
		reason="$reason; LICENSE FILE(S) CHANGED, REVIEW THE DIFF IN THE STEP LOG: $lic_changed"
		diff_license_files "$wd" "$old_asset" "$lic_changed"
	fi
	hash_sync_record "$outcomes_file" "$pkg" refreshed "$reason"
	hash_sync_set_env "$env_var" 1
	return 0
}

# diff_license_files WORKDIR OLD_ASSET "FILE [FILE...]"
#   Best-effort: fetches the PREVIOUS release asset and prints a unified diff
#   of each changed license file into the step log. Every failure path here is
#   a notice and a `return 0` -- this is a review aid bolted onto an already-
#   completed refresh, and it must never be able to fail one.
diff_license_files() {
	local wd="$1" old_asset="$2" files="$3"
	local old_version old_url old_dir lf

	# 7z2602-src.tar.xz -> 26.02, inverting the .mk's
	# 7z$(subst .,,$(<PKG>_VERSION))-src.tar.xz. Anything not matching that
	# exact shape skips the diff, never the refresh.
	old_version=$(printf '%s\n' "$old_asset" \
		| sed -nE 's/^7z([0-9]{2})([0-9]{2})-src\.tar\.xz$/\1.\2/p')
	if [ -z "$old_version" ]; then
		echo "::notice::could not derive the previous version from '$old_asset' -- skipping the license diff; compare by hand"
		return 0
	fi

	old_dir="$wd/old"
	mkdir -p "$old_dir"
	old_url="https://github.com/ip7z/7zip/releases/download/${old_version}/${old_asset}"
	echo "--- fetching $old_version to diff its license text against ---"
	if ! curl -fsSL --retry 3 "$old_url" -o "$old_dir/$old_asset"; then
		echo "::notice::could not download $old_url -- skipping the license diff; compare by hand"
		return 0
	fi
	for lf in $files; do
		if ! tar -C "$old_dir" -xJf "$old_dir/$old_asset" "$lf" 2>/dev/null; then
			echo "::notice::$lf is not present in $old_version -- newly added license file, nothing to diff"
			continue
		fi
		echo "===== diff $lf : $old_version -> current ====="
		# `|| true`: diff exits 1 when files differ, which they do by
		# construction here, and pipefail would otherwise kill the script.
		diff -u "$old_dir/$lf" "$wd/$lf" | head -80 || true
		echo "===== end diff $lf ====="
	done
	return 0
}

main() {
	cd "$REPO_ROOT"

	SCRATCH="$(mktemp -d)"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local row pkg version_var env_var
	for row in "${IP7Z_PACKAGES[@]}"; do
		IFS='|' read -r pkg version_var env_var <<<"$row"
		sync_one "$outcomes_file" "$pkg" "$version_var" "$env_var"
	done
}

main
