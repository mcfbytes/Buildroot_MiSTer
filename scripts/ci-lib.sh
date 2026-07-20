#!/usr/bin/env bash
#
# scripts/ci-lib.sh — small shell helpers shared across the CI pipeline's
# workflow `run:` blocks. Not directly executable; sourced. TASKS.md /
# CI-REFACTOR-MENU.md item G: fold the handful of helpers that build.yml,
# release.yml and .github/actions/kernel-leg/action.yml each carried their
# own copy of, so a fix to one no longer has to be remembered for the
# other copies (same reasoning as the composite actions under
# .github/actions/ and scripts/lib/hash-sync-common.sh for the
# hash-sync-*.sh family).
#
# What was actually duplicated, and is folded in here:
#
#   * sz() — the "<size>B or n/a" formatter every job-summary table
#     (build.yml, release.yml, kernel-leg) used. Defined identically 3x.
#   * The GitHub 2 GiB per-release-asset guard on the legal-info tarball —
#     defined once in release.yml and again, necessarily worded a little
#     differently (see ci_lib_check_release_asset_size below), in
#     kernel-leg's full-legal-info branch.
#   * The legal-info tarball itself, with its sources/host-sources
#     exclusion pattern — build.yml, release.yml, and BOTH branches of
#     kernel-leg's staging step each ran their own `tar -czf`.
#
# WHY THE 2 GiB LIMIT MATTERS — restated here because it needs to survive
# in exactly one place a reader can find from either call site now that
# there is only one copy of the guard's logic: `make legal-info` (and
# `make <variant>-legal-info`) copies every package's upstream source
# TARBALL into legal-info/sources/ and legal-info/host-sources/ — the
# whole target package set, PLUS the BUILD-TIME toolchain's own sources
# (host-gcc, host-binutils, host-glibc, ...). With host-sources/ included,
# the archive measured 2109 MiB. GitHub hard-rejects any single release
# asset at or over 2 GiB, so the first real tag push would have failed at
# the very last step — upload — with a confusing API error instead of a
# clear one raised here. host-sources/ is excluded in every mode for
# exactly this reason (see ci_lib_package_legal_info): it is the
# BUILD-TIME toolchain's own source, never distributed in linux.img or
# zImage_dtb, so it carries no GPL "accompanying source" obligation the
# way legal-info/sources/ does. ci_lib_check_release_asset_size is the
# backstop that turns any future regrowth back past 2 GiB into a loud,
# early CI failure instead of a silent one at the upload API.
#
# SOURCING — must work from BOTH of these call shapes:
#
#   * A workflow `run:` block, or a composite action's `run:` step.
#     Actions runners always start these with CWD = $GITHUB_WORKSPACE (the
#     checked-out repo root) — no step anywhere in this repo overrides
#     working-directory — so a plain, repo-root-relative
#
#         # shellcheck source=scripts/ci-lib.sh
#         source scripts/ci-lib.sh
#
#     is correct and needs no path arithmetic. IMPORTANT for a composite
#     action specifically: unlike the top-level actionlint+shellcheck pass
#     (which shellchecks workflow `run:` blocks with CWD already sitting
#     at repo root), scripts/shellcheck-composite-actions.sh extracts each
#     `run:` body into an unrelated temp directory before shellchecking
#     it, so the literal, repo-root-relative "scripts/ci-lib.sh" the
#     `source=` directive names does not exist relative to THAT temp
#     file's own directory. That script was updated (shellcheck now runs
#     with CWD pinned to the repo root, plus -x) to resolve it the same
#     way it resolves at actual runtime, rather than special-casing this
#     file out or disabling the check — see that script's own header.
#
#   * Another script under scripts/ (e.g. a future extraction of one of
#     the steps below). Those run with an arbitrary CWD (a maintainer's
#     shell, a fixture harness — see scripts/hash-sync-*.sh), so they must
#     resolve this file relative to THEIR OWN location, not CWD:
#
#         SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#         # shellcheck source=scripts/ci-lib.sh
#         . "$SCRIPT_DIR/ci-lib.sh"
#
#     (the same pattern scripts/hash-sync-*.sh already use to reach
#     scripts/lib/hash-sync-common.sh.)
#
# Deliberately does NOT `set -euo pipefail` itself. NOTE this is NOT
# because the job-summary steps run without -e: a workflow `run:` step
# with no `shell:` override is already invoked as `bash --noprofile --norc
# -eo pipefail {0}` by GitHub itself, exactly like a composite action's
# `run:` step (see scripts/shellcheck-composite-actions.sh's header for
# that citation) — so build.yml's and release.yml's job-summary steps and
# kernel-leg's summary step, which each write only `set -u`, are still
# running with -e and pipefail already active; `set -u` adds the
# undefined-variable check on top of that, it does not start from a blank
# slate. (Confirmed directly: `bash -e -c 'set -u; false; echo after'`
# exits 1 without ever printing "after" — `set -u` cannot clear an
# inherited -e.) So the actual posture is uniform -e/pipefail everywhere,
# and the only things that vary by call site are (a) whether -u is spelled
# out (every call site here does turn it on, summary and packaging alike)
# and (b) whether `pipefail` is respelled explicitly (`set -euo pipefail`,
# as kernel-leg's staging step and the legal-info packaging steps in
# build.yml/release.yml do) or left implicit because GitHub's own
# invocation already supplies it (`set -eu`, as the job-summary steps do).
# Sourcing any `set` here would still be the wrong layer regardless of
# which posture is active: it would bake one caller's chosen spelling into
# a file with no business overriding it, which is exactly the kind of
# guard change this refactor must not make. Every function below is
# written to behave correctly under any posture on its own terms (see each
# function's own comment) — in particular ci_lib_sz never itself returns
# non-zero, so a best-effort summary step never aborts because OF it.
#
# NOT folded in here, deliberately: the legal-info EXISTENCE check
# ("[ ! -d ... ] && { ::error::...; exit 1; }", two call sites —
# release.yml and kernel-leg's full-legal-info branch). It is three lines,
# and its two occurrences' messages differ in both the directory named and
# the make target named in the error, so a shared helper would need as
# many parameters as it saved lines. Left inline at both sites.

# ci_lib_sz FILE
#   Prints FILE's size as a human "<N><unit>B" string (numfmt --to=iec-i),
#   or "n/a" if FILE does not exist. Never fails — the `||` branch always
#   supplies a successful `echo` — so it is safe to call under `set -e`
#   from a context whose whole point is a best-effort summary that must
#   not abort over one missing file.
ci_lib_sz() {
	[ -f "$1" ] && numfmt --to=iec-i --suffix=B "$(stat -c %s "$1")" || echo "n/a"
}

# ci_lib_package_legal_info OUTPUT_DIR DEST_TARBALL MODE
#   Archives OUTPUT_DIR/legal-info (Buildroot's `make legal-info` /
#   `make <variant>-legal-info` SBOM output) into DEST_TARBALL. MODE is
#   one of:
#
#     full            Excludes only legal-info/host-sources — ships
#                      legal-info/sources/, the GPL "accompanying source"
#                      for every package actually distributed. Used where
#                      the artifact really does convey the image
#                      (release.yml; kernel-leg's full-legal-info branch).
#     manifest-only    Excludes BOTH legal-info/sources and
#                      legal-info/host-sources. A CI push distributes
#                      nothing, so there is no obligation to carry the GPL
#                      source tarballs — what remains is the part that is
#                      actually an SBOM and actually gets read:
#                      manifest.csv, the license texts, buildroot.config,
#                      and the source hashes. Used by build.yml and
#                      kernel-leg's non-full branch.
#
#   host-sources/ is excluded in EITHER mode, always — see this file's own
#   header for why (the BUILD-TIME-toolchain-vs-shipped-binary distinction
#   and the 2109 MiB measurement).
#
#   Does NOT check that OUTPUT_DIR/legal-info exists first — the two
#   callers that need that guard (release.yml, kernel-leg's
#   full-legal-info branch) do it themselves immediately before calling
#   this, because their ::error:: wording differs (see this file's header
#   on why that stayed inline rather than becoming a third helper).
#   Relies on the caller's own `set -e` / `set -eu` / `set -euo pipefail`
#   to stop the step if `tar` itself fails, or if MODE is invalid.
ci_lib_package_legal_info() {
	local output_dir="$1" dest_tarball="$2" mode="$3"
	case "$mode" in
	full)
		tar -czf "$dest_tarball" --exclude='legal-info/host-sources' -C "$output_dir" legal-info
		;;
	manifest-only)
		tar -czf "$dest_tarball" --exclude='legal-info/sources' --exclude='legal-info/host-sources' -C "$output_dir" legal-info
		;;
	*)
		echo "::error::ci_lib_package_legal_info: MODE must be 'full' or 'manifest-only', got '$mode'" >&2
		return 1
		;;
	esac
}

# ci_lib_check_release_asset_size FILE DISPLAY_NAME SPLIT_ADVICE
#   Enforces GitHub's 2 GiB per-release-asset ceiling on FILE (see this
#   file's header for why that number, and why it is checked at all).
#
#   Always prints "<DISPLAY_NAME>: <N> bytes (<M> MiB)". If FILE is at or
#   over the limit, ALSO prints, to stderr:
#
#     ::error::<DISPLAY_NAME> is <M> MiB, at or over GitHub's 2 GiB
#     per-release-asset limit<SPLIT_ADVICE>
#
#   and returns 1. SPLIT_ADVICE is deliberately a caller-supplied, opaque
#   suffix (own leading punctuation included) rather than a fixed string
#   here, because release.yml's and kernel-leg's actual advice genuinely
#   differ — one names the sources-as-separate-asset option, the other
#   points back at this shared guard's main-step sibling — and this keeps
#   each call site's exact original wording rather than forcing them to
#   converge on a new, third message.
#
#   Returns (does not itself `exit`) on violation: every call site already
#   runs under `set -e` / `set -eu` / `set -euo pipefail`, so a plain call
#   without `|| exit 1` still aborts the step — this stays exit-free so it
#   composes and is testable outside that context too.
ci_lib_check_release_asset_size() {
	local file="$1" display_name="$2" split_advice="$3"
	local limit=$((2 * 1024 * 1024 * 1024))
	local size
	size=$(stat -c %s "$file")
	echo "${display_name}: ${size} bytes ($((size / 1024 / 1024)) MiB)"
	if [ "$size" -ge "$limit" ]; then
		echo "::error::${display_name} is $((size / 1024 / 1024)) MiB, at or over GitHub's 2 GiB per-release-asset limit${split_advice}" >&2
		return 1
	fi
}
