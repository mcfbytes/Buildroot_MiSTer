#!/usr/bin/env bash
#
# hash-sync-azcopy.sh — case 7 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml, TASKS.md P4.6): refresh
# package/azcopy/azcopy.hash after a Renovate bump of AZCOPY_VERSION.
#
# WHY THIS EXISTS NOW, HAVING BEEN DECLARED IMPOSSIBLE BEFORE -- read this
# before "restoring" the old prohibition, because the change is deliberate and
# the old wording is still quoted in git history. package/azcopy/azcopy.hash,
# package/azcopy/azcopy.mk (point 3 of its header) and renovate.json all used
# to say the hash "CANNOT be auto-refreshed", and azcopy was deliberately
# absent from HASH_SYNC_PACKAGES. That claim was true of the METHOD it was
# aimed at and false as a general statement, and conflating the two is what
# kept this manual for a year:
#
#   * TRUE, permanently: `curl <archive-url> | sha256sum` -- case 1's method
#     -- cannot produce this value. azcopy is a golang-package, so Buildroot
#     sets AZCOPY_DOWNLOAD_POST_PROCESS = go and the file it hashes is the
#     post-`go mod vendor` azcopy-<ver>-go2.tar.gz, not the GitHub archive.
#     Case 1's loop would write a plausible-looking WRONG value. This script
#     must never be folded into that loop.
#
#   * FALSE: that nothing else could do it. The reproduction needs a Go
#     toolchain and a network fetch of every module in go.sum -- which is a
#     CI job description, not an impossibility. This script does exactly what
#     the manual recipe in azcopy.hash does, with the same tools, and it does
#     it by running BUILDROOT'S OWN support/download/go-post-process rather
#     than by reimplementing the repack.
#
# WHAT MAKES THE RESULT TRUSTWORTHY. Three properties, in order of importance:
#
#   1. IT RUNS UPSTREAM'S CODE, NOT A LOOKALIKE. The tarball is produced by
#      work/buildroot/support/download/go-post-process from the pinned
#      Buildroot tree (unpacked here by `make buildroot-unpack`, i.e. verified
#      against BUILDROOT_SHA256 first). Every byte-level detail that makes
#      that tarball reproducible -- POSIX format, sorted file list, the mtime
#      taken from the GitHub archive, --owner=0 --group=0, gzip -6 -n -- comes
#      from support/download/helpers itself. Re-deriving those by hand here
#      would be a second implementation to keep in sync, and the first
#      divergence would be silent.
#   2. THE GO TOOLCHAIN IS THE PINNED ONE. GO_VERSION is read out of that same
#      Buildroot tree (package/go/go.mk) and the official tarball is verified
#      against package/go/go.hash from that tree -- no version is hard-coded
#      here, so a Buildroot bump moves the compiler used here in lockstep with
#      the one the real build uses. `go mod vendor` output is a function of
#      the toolchain as well as of go.mod/go.sum.
#   3. THE MODULES ARE go.sum-VERIFIED. Nothing here disables a checksum. A
#      module that verifies has byte-identical content whichever source served
#      it, which is also what makes the GOPROXY fallback below safe.
#
# It is still NOT a "fetch a signed manifest" case (2 and 6) and not a "hash
# the pinned artifact" case (1, 3, 4). It is a THIRD kind: REBUILD the
# artifact the way the build will, then hash what came out. That is legitimate
# here for the reason the .hash file's header already gives -- the value
# certifies the vendored dependency set as much as the AzCopy sources, and
# there is no URL anywhere that serves it. It is emphatically NOT a licence to
# locally compute a hash for a pin whose upstream publishes a signed manifest;
# that prohibition (scripts/lib/hash-sync-common.sh) is untouched.
#
# GOPROXY: DIRECT FIRST, DECLARED FALLBACK SECOND.
# pkg-golang.mk vendors with GOPROXY=direct. A package may override that (as
# package/azcopy/azcopy.mk temporarily does -- read the block at the end of
# that file for the moved-tag incident behind it), so this script:
#
#   1. always tries GOPROXY=direct first -- the stock behaviour;
#   2. on failure, retries with the GOPROXY= value on the azcopy.mk
#      AZCOPY_DL_ENV line, if there is one. azcopy.mk is the single source of
#      truth; nothing is hard-coded here;
#   3. emits a ::notice:: when direct SUCCEEDS while an override is present,
#      because that means the override has served its purpose and the block in
#      azcopy.mk should be deleted. Acting on that notice is safe: see
#      property 3 above -- both paths yield the same bytes when both work.
#
# If direct fails and there is no override to fall back to, the outcome is
# `skipped`, not `failed`: the bump is then genuinely un-vendorable as
# configured, and the right answer is the fail-closed one (a human reads the
# log and decides), not a hash for a tarball Buildroot cannot reproduce.
#
# LICENSE/NOTICE.txt ARE REFRESHED TOO, which case 1 has no equivalent of.
# azcopy.hash pins three files, and the manual recipe's step 4 was "re-check
# the two license lines by hand" precisely because the download check never
# consults them (only `make legal-info` does) -- so a Microsoft edit to
# LICENSE would sail through a green build. Having already extracted the
# tarball, checking them costs nothing. They are hashed from the tarball this
# script just built, i.e. from the pinned tag's own files.
#
# WHAT THIS SCRIPT MUST NEVER DO:
#
#   * write a hash it did not obtain by running go-post-process to completion.
#     No "the download failed, keep the old value but update the filename" --
#     that is the exact stale-pin state lint.yml's azcopy step exists to
#     catch, and it would convert a red PR into a green one that breaks on
#     master.
#   * disable a checksum to make the vendoring succeed (GOFLAGS=-mod=mod, a
#     doctored go.sum, GONOSUMDB and friends). Changing WHERE bytes are
#     fetched from is not the same as changing WHETHER they are checked; only
#     the former is on the table.
#
# Records ONE row to $HASH_SYNC_OUTCOMES_FILE under the pin name "azcopy":
# refreshed | already-current | skipped | failed. APPENDS -- does not
# truncate; scripts/hash-sync-github-packages.sh (case 1) owns creating the
# shared outcomes file for the run. Standalone, `touch` it yourself first.
#
# Sets (via hash_sync_set_env): AZCOPY_HASH_CHANGED=0|1 -- ORed into the
# .yml's "Commit and push hash refresh" gate, which must also `git add` a path
# covering package/azcopy/azcopy.hash (its `package/*/*.hash` glob does).
#
# Exit: always 0 on a handled path (including a recorded "failed"), like every
# other case script -- this runs as its own workflow step and an `exit 1` here
# would skip the steps after it.
#
# COST: this is by far the most expensive case in the family -- it unpacks
# Buildroot, downloads a ~67 MB Go toolchain and vendors ~1.7 GiB of modules,
# so budget 5-8 minutes rather than case 1's seconds. That is why it is gated
# behind a `paths:` filter on package/azcopy/azcopy.mk alone: it must not run
# on any other pin's bump.
#
# Usage:
#   scripts/hash-sync-azcopy.sh [REPO_ROOT]
#   REPO_ROOT defaults to this repo's root. Unlike the other case scripts,
#   REPO_ROOT must be a REAL checkout of this tree, not a fixture directory:
#   this script runs `make buildroot-unpack` in it to obtain the pinned,
#   hash-verified Buildroot sources it needs. Everything else it writes goes
#   under a scratch directory it removes on exit.
#
# Required env:
#   HASH_SYNC_OUTCOMES_FILE   bare filename (production; $RUNNER_TEMP-
#                             prefixed) or an absolute path (standalone use)
#                             -- see scripts/lib/hash-sync-common.sh.
#
# Optional env:
#   GITHUB_ENV, RUNNER_TEMP   set automatically by Actions; see
#                             scripts/lib/hash-sync-common.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

PIN=azcopy
ENV_VAR=AZCOPY_HASH_CHANGED

usage() {
	echo "usage: $(basename "$0") [REPO_ROOT]" >&2
	exit 2
}

[ "$#" -le 1 ] || usage

REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
[ -d "$REPO_ROOT" ] || { echo "::error::REPO_ROOT '$REPO_ROOT' is not a directory" >&2; exit 2; }

: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

SCRATCH=""
# `return 0` is load-bearing, not decorative: bash propagates a non-zero status
# out of an EXIT trap, so the bare `[ -n "$SCRATCH" ] && rm -rf ...` this
# started as made the script exit 1 on every path that never allocated a
# scratch dir -- including the cheap already-current one, which is the path
# almost every run takes. That would have failed the step (and, via the
# workflow's push gate, suppressed other cases' refreshes) while reporting a
# perfectly good outcome. Caught by running it; keep the explicit return.
cleanup() {
	if [ -n "$SCRATCH" ]; then
		rm -rf "$SCRATCH"
	fi
	return 0
}
trap cleanup EXIT

# vendor_with GOPROXY_VALUE OUT_FILE GO_ROOT BUILDROOT_DIR BASE_NAME
#   Runs Buildroot's own go-post-process over OUT_FILE (which must already
#   hold the GitHub archive) with the given GOPROXY, in a throwaway cwd --
#   go-post-process unpacks and repacks relative to its working directory,
#   exactly as dl-wrapper's `cd "${tmpd}"` arranges on a real build.
#   Returns go-post-process's own exit status.
vendor_with() {
	local goproxy="$1" out="$2" goroot="$3" br="$4" base_name="$5"
	local wd
	wd="$(mktemp -d "$SCRATCH/vendor.XXXXXX")"
	(
		cd "$wd"
		# `env -i` so nothing from the runner's environment (a GOFLAGS, a
		# GOPRIVATE, a preinstalled Go earlier in PATH) can change what
		# `go mod vendor` produces. The variables set here are exactly
		# pkg-golang.mk's DL_ENV -- HOST_GO_COMMON_ENV (package/go/go.mk)
		# with GOPROXY overridden -- plus the TAR that package/pkg-download.mk
		# passes and support/download/helpers uses for the repack.
		env -i \
			HOME="$SCRATCH/home" \
			PATH="$goroot/bin:/usr/local/bin:/usr/bin:/bin" \
			TAR=tar \
			GO111MODULE=on \
			GOFLAGS=-mod=vendor \
			GOROOT="$goroot" \
			GOPATH="$SCRATCH/gopath" \
			GOCACHE="$SCRATCH/gocache" \
			GOMODCACHE="$SCRATCH/gopath/pkg/mod" \
			GOPROXY="$goproxy" \
			GOTOOLCHAIN=local \
			GOBIN= \
			"$br/support/download/go-post-process" -o "$out" -n "$base_name"
	)
}

main() {
	cd "$REPO_ROOT"

	local outcomes_file
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local mk="package/azcopy/azcopy.mk"
	local hashfile="package/azcopy/azcopy.hash"

	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping azcopy"
		hash_sync_record "$outcomes_file" "$PIN" skipped "$mk or $hashfile not found in this checkout"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	# `|| true` for the same reason as every other case script's extractions:
	# a zero-match grep under `set -euo pipefail` would kill the script at the
	# assignment and the handled branch below would never run.
	local version
	version=$(grep -E '^AZCOPY_VERSION[[:space:]]*=' "$mk" | head -1 \
	           | sed -E 's/^AZCOPY_VERSION[[:space:]]*=[[:space:]]*//' | tr -d '[:space:]' || true)
	if [ -z "$version" ]; then
		# Parsing our OWN .mk -- a workflow bug, not a network issue.
		echo "::error::could not parse AZCOPY_VERSION from $mk"
		hash_sync_record "$outcomes_file" "$PIN" failed \
			"could not parse AZCOPY_VERSION from $mk -- workflow regex bug, not a network issue; build still fails closed on the stale hash"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	local base_name="azcopy-${version}"
	local asset="${base_name}-go2.tar.gz"

	# Nothing to do if the hash file already pins this version's tarball. The
	# expensive work below is skipped entirely on a re-run, which matters
	# because this workflow is idempotent by design (it recomputes on every
	# `synchronize` event). Note this is the same consistency relation
	# lint.yml's "azcopy version/hash pin consistency" step gates on, so an
	# already-current outcome here means that step is green too.
	local oldline
	oldline=$(grep -m1 '^sha256' "$hashfile" || true)
	if [ "${oldline##*  }" = "$asset" ]; then
		echo "$hashfile already pins $asset -- nothing to do."
		hash_sync_record "$outcomes_file" "$PIN" already-current "already pins $asset"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	SCRATCH="$(mktemp -d)"
	mkdir -p "$SCRATCH/home"

	# The pinned, BUILDROOT_SHA256-verified Buildroot tree: the source of
	# go-post-process, of helpers, and of both Go pins read below. Not a
	# convenience -- see property 1 in the header.
	echo "==> unpacking the pinned Buildroot tree (for support/download/go-post-process)"
	if ! make buildroot-unpack; then
		echo "::warning::make buildroot-unpack failed -- cannot reach go-post-process, leaving $hashfile untouched"
		hash_sync_record "$outcomes_file" "$PIN" skipped "make buildroot-unpack failed -- could not obtain the pinned Buildroot tree"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi
	local br="$REPO_ROOT/work/buildroot"

	local go_version
	go_version=$(grep -E '^GO_VERSION[[:space:]]*=' "$br/package/go/go.mk" | head -1 \
	              | sed -E 's/^GO_VERSION[[:space:]]*=[[:space:]]*//' | tr -d '[:space:]' || true)
	if [ -z "$go_version" ]; then
		echo "::error::could not parse GO_VERSION from the pinned Buildroot tree ($br/package/go/go.mk)"
		hash_sync_record "$outcomes_file" "$PIN" failed \
			"could not parse GO_VERSION from $br/package/go/go.mk -- upstream renamed the variable, or the tree is not where this script expects"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	# The sha256 Buildroot itself pins for this toolchain tarball, taken from
	# the same tree -- so the compiler is verified against upstream's own
	# recorded value, never against one this script invented.
	local go_tarball="go${go_version}.linux-amd64.tar.gz"
	local go_sha
	go_sha=$(awk -v f="$go_tarball" '$1 == "sha256" && $3 == f { print $2 }' "$br/package/go/go.hash" || true)
	if [ -z "$go_sha" ]; then
		echo "::error::no sha256 for $go_tarball in $br/package/go/go.hash"
		hash_sync_record "$outcomes_file" "$PIN" failed \
			"no sha256 for $go_tarball in the pinned Buildroot tree's package/go/go.hash"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	echo "==> fetching Go $go_version (pinned by the Buildroot tree, verified against its go.hash)"
	if ! curl -fsSL --retry 3 "https://go.dev/dl/${go_tarball}" -o "$SCRATCH/$go_tarball"; then
		echo "::warning::could not download $go_tarball -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$PIN" skipped "could not download $go_tarball"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi
	if ! echo "${go_sha}  $SCRATCH/$go_tarball" | sha256sum -c - >/dev/null; then
		# A checksum mismatch on the compiler is never "a blip". Fail loudly.
		echo "::error::$go_tarball does not match the sha256 Buildroot pins for it"
		hash_sync_record "$outcomes_file" "$PIN" failed \
			"$go_tarball sha256 mismatch against the pinned Buildroot tree's package/go/go.hash -- refusing to vendor with an unverified toolchain"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi
	tar -C "$SCRATCH" -xzf "$SCRATCH/$go_tarball"
	local goroot="$SCRATCH/go"

	# The URL Buildroot itself would fetch: AZCOPY_SITE is
	# $(call github,Azure,azure-storage-azcopy,v$(AZCOPY_VERSION)) and the
	# wget backend appends "/<filename>" to it (support/download/wget).
	# GitHub ignores the trailing filename and serves the ref's archive.
	local url="https://github.com/Azure/azure-storage-azcopy/archive/v${version}/${asset}"
	echo "==> fetching $url"
	local out="$SCRATCH/output"
	if ! curl -fsSL --retry 3 "$url" -o "$out"; then
		echo "::warning::could not download $url -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$PIN" skipped "could not download $url"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	# The package's own GOPROXY override, if it has one. Read from azcopy.mk
	# so that file stays the single source of truth -- see this script's
	# header, and the block at the end of azcopy.mk.
	local override
	override=$(grep -E '^AZCOPY_DL_ENV[[:space:]]*\+=[[:space:]]*GOPROXY=' "$mk" | head -1 \
	            | sed -E 's/^AZCOPY_DL_ENV[[:space:]]*\+=[[:space:]]*GOPROXY=//' | tr -d '[:space:]' || true)

	local used_proxy=direct
	echo "==> vendoring with GOPROXY=direct (pkg-golang.mk's stock setting)"
	if vendor_with direct "$out" "$goroot" "$br" "$base_name"; then
		if [ -n "$override" ]; then
			echo "::notice::GOPROXY=direct vendored azcopy $version successfully, but package/azcopy/azcopy.mk still carries an AZCOPY_DL_ENV GOPROXY override ($override). That override is now obsolete -- delete its block from azcopy.mk. (Safe: a go.sum-verified module is byte-identical whichever source served it, so this hash is what either path produces.)"
		fi
	elif [ -n "$override" ]; then
		echo "==> GOPROXY=direct failed; retrying with azcopy.mk's declared override GOPROXY=$override"
		# Re-fetch: a failed post-process leaves $out unpacked-and-abandoned
		# rather than untouched, and the retry needs the pristine archive.
		if ! curl -fsSL --retry 3 "$url" -o "$out"; then
			echo "::warning::could not re-download $url for the GOPROXY retry -- leaving $hashfile untouched"
			hash_sync_record "$outcomes_file" "$PIN" skipped "could not re-download $url for the GOPROXY retry"
			hash_sync_set_env "$ENV_VAR" 0
			return 0
		fi
		if ! vendor_with "$override" "$out" "$goroot" "$br" "$base_name"; then
			echo "::warning::vendoring azcopy $version failed with GOPROXY=direct AND with azcopy.mk's override ($override) -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
			hash_sync_record "$outcomes_file" "$PIN" skipped \
				"go mod vendor failed under both GOPROXY=direct and the azcopy.mk override ($override) -- read the step log; this bump may not be vendorable as configured"
			hash_sync_set_env "$ENV_VAR" 0
			return 0
		fi
		used_proxy="$override"
	else
		echo "::warning::vendoring azcopy $version failed with GOPROXY=direct and azcopy.mk declares no override -- leaving $hashfile untouched, build will fail closed on a stale hash instead"
		hash_sync_record "$outcomes_file" "$PIN" skipped \
			"go mod vendor failed under GOPROXY=direct and azcopy.mk declares no AZCOPY_DL_ENV GOPROXY override -- read the step log"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi

	local newhash
	newhash=$(sha256sum "$out" | cut -d' ' -f1)
	echo "==> $asset: $newhash ($(stat -c '%s' "$out") bytes, vendored via GOPROXY=$used_proxy)"

	# The two license files, from the tarball just built -- the manual
	# recipe's step 4. See the header for why the download check can never
	# catch a change to these.
	local xdir="$SCRATCH/x"
	mkdir -p "$xdir"
	# Guarded rather than left to `set -e`: if a future AzCopy release renames
	# or drops one of these, an unguarded tar would abort the script with no
	# outcome row at all -- the shape of the run-29669946883 failure this
	# family's outcome ledger exists to make impossible. The tarball hash is
	# already correct at this point, but writing it while silently leaving a
	# stale license line would be worse than refreshing nothing, because
	# AZCOPY_LICENSE_FILES would then name files whose recorded hashes nobody
	# re-derived. Fail, and let the human look.
	if ! tar -C "$xdir" -xzf "$out" "$base_name/LICENSE" "$base_name/NOTICE.txt" 2>/dev/null; then
		echo "::error::azcopy $version's tarball does not contain both LICENSE and NOTICE.txt at its root"
		hash_sync_record "$outcomes_file" "$PIN" failed \
			"LICENSE and/or NOTICE.txt missing from azcopy-$version -- upstream renamed or dropped a license file; AZCOPY_LICENSE_FILES in azcopy.mk needs a human before this pin can move"
		hash_sync_set_env "$ENV_VAR" 0
		return 0
	fi
	local license_hash notice_hash
	license_hash=$(sha256sum "$xdir/$base_name/LICENSE" | cut -d' ' -f1)
	notice_hash=$(sha256sum "$xdir/$base_name/NOTICE.txt" | cut -d' ' -f1)

	# Rewrite the three sha256 lines in place, matched by the FILENAME on each
	# line rather than by position, so the file's long provenance comments --
	# which is most of it -- survive verbatim. The tarball line is matched by
	# its "-go2.tar.gz" suffix (the version in it is the OLD one at this
	# point, so it cannot be matched by name).
	local newline="sha256  ${newhash}  ${asset}"
	awk -v tarline="$newline" \
	    -v lic="sha256  ${license_hash}  LICENSE" \
	    -v not="sha256  ${notice_hash}  NOTICE.txt" '
		$1 == "sha256" && $3 ~ /-go2\.tar\.gz$/ { print tarline; next }
		$1 == "sha256" && $3 == "LICENSE"       { print lic; next }
		$1 == "sha256" && $3 == "NOTICE.txt"    { print not; next }
		{ print }
	' "$hashfile" > "$hashfile.tmp"
	mv "$hashfile.tmp" "$hashfile"

	echo "Updated $hashfile:"
	echo "  old: $oldline"
	echo "  new: $newline"
	hash_sync_record "$outcomes_file" "$PIN" refreshed \
		"sha256 updated (vendored via GOPROXY=$used_proxy): $oldline -> $newline"
	hash_sync_set_env "$ENV_VAR" 1
	return 0
}

main
