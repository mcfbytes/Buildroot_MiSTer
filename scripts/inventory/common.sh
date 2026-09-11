#!/usr/bin/env bash
# scripts/inventory/common.sh — shared helpers for the stock-inventory
# generator scripts (P0.3). Not directly executable; sourced by gen-*.sh.
#
# Design goals (see docs/stock-inventory/README.md for the full contract):
#   - every gen-*.sh takes a rootfs *ext4 image* OR an already-extracted root
#     directory as its argument, so the same script works against the stock
#     image today and any Buildroot-built image later (P2/P3 parity checks).
#   - output is deterministic: sorted with LC_ALL=C, no timestamps, no
#     absolute host paths, no ownership bits (debugfs rdump extraction does
#     not preserve original uid/gid when run unprivileged — see
#     docs/reference-materials.md section 3).
#   - nothing requires root.

export LC_ALL=C

MRL_CLEANUP_DIRS=()

# Every scratch path this process creates lives under one per-process root.
#
# It is keyed on `$$` rather than tracked in an array because `mrl_extract_root`
# has to *print* the path it created, so callers invoke it as
# `root="$(mrl_extract_root "$img")"` — a command substitution, i.e. a subshell.
# An `MRL_CLEANUP_DIRS+=(...)` inside that subshell appends to the subshell's
# copy of the array and is lost when it exits, so the parent's EXIT trap would
# find an empty array and delete nothing. (That bug leaked one ~300 MB
# extraction per generator run.) `$$` is the *invoking* shell's PID and stays
# identical inside command substitutions — `$BASHPID` does not — so a path
# derived from it is reachable from both sides of the subshell boundary.
MRL_TMPROOT="${TMPDIR:-/tmp}/mister-inventory.$$"

mrl_cleanup() {
	# IMPORTANT: this runs as an EXIT trap under `set -e` (every gen-*.sh
	# sets -euo pipefail). If the *last* command this function runs has a
	# nonzero exit status, bash silently replaces the script's real exit
	# code with that status -- e.g. an intended `exit 0` becomes 1. Two
	# defenses: guard the loop with an explicit length check (avoids the
	# "${arr[@]:-}" empty-array-under-nounset gotcha, which otherwise
	# iterates once with an empty string and trips `[ -n "" ]` = false),
	# and end with an explicit `return 0` no matter what happened above.
	if [ "${#MRL_CLEANUP_DIRS[@]}" -gt 0 ]; then
		local d
		for d in "${MRL_CLEANUP_DIRS[@]}"; do
			# `if`-guarded, not `&&`-chained: under `set -e`, a bare
			# `[ -d "$d" ] && rm ...` statement whose test is false
			# would itself trigger errexit right here (it's not
			# exempted the way an if-condition is), aborting the trap
			# mid-loop and -- see the comment above this function --
			# clobbering the script's real exit status.
			if [ -d "$d" ]; then
				rm -rf "$d"
			fi
		done
	fi
	if [ -d "$MRL_TMPROOT" ]; then
		rm -rf "$MRL_TMPROOT"
	fi
	return 0
}
trap mrl_cleanup EXIT

# mrl_require <tool> [tool...] — fail loudly if a required tool is missing.
mrl_require() {
	local missing=()
	local t
	for t in "$@"; do
		command -v "$t" >/dev/null 2>&1 || missing+=("$t")
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		echo "error: required tool(s) not found in PATH: ${missing[*]}" >&2
		exit 1
	fi
}

# mrl_extract_root <image-or-dir>
#   Prints (on stdout) a directory holding the rootfs contents.
#     - If given a directory, prints it unchanged (fast path for a
#       pre-extracted tree such as work/imgroot; not cleaned up).
#     - If given a regular file, treats it as an ext4 image and extracts it
#       read-only via `debugfs -R "rdump / <tmpdir>"` (preserves symlinks as
#       real symlinks, requires no root — verified docs/reference-materials.md
#       section 3). The temp dir is registered for cleanup at process exit.
mrl_extract_root() {
	local input="$1"
	if [ -d "$input" ]; then
		printf '%s\n' "$input"
		return 0
	fi
	if [ ! -f "$input" ]; then
		echo "error: '$input' is neither a directory nor a regular file" >&2
		return 1
	fi
	mrl_require debugfs

	local tmpdir
	mkdir -p "$MRL_TMPROOT"
	tmpdir="$(mktemp -d "${MRL_TMPROOT}/root.XXXXXX")"
	# Inside $MRL_TMPROOT, not beside it: a sibling path would outlive the
	# cleanup of $tmpdir and leak too.
	local log="${tmpdir}/../rdump.$$.log"

	# debugfs rdump prints a one-line version banner ("debugfs 1.47.2
	# (...)") plus benign "Operation not permitted while changing
	# ownership of ..." lines when run unprivileged (it tries to chown
	# extracted files to the image's original uid/gid, which requires
	# root) -- neither is an extraction failure. A real failure is any
	# other line, or a nonzero exit combined with an empty tree.
	if ! debugfs -R "rdump / ${tmpdir}" "$input" >"$log" 2>&1; then
		echo "error: debugfs rdump failed on '$input'; see $log" >&2
		return 1
	fi
	if grep -qvE 'Operation not permitted while changing ownership|^debugfs [0-9]' "$log"; then
		echo "error: debugfs rdump reported unexpected output on '$input':" >&2
		grep -vE 'Operation not permitted while changing ownership|^debugfs [0-9]' "$log" >&2
		return 1
	fi
	if [ -z "$(find "$tmpdir" -mindepth 1 -print -quit)" ]; then
		echo "error: rdump of '$input' produced an empty tree" >&2
		return 1
	fi
	rm -f "$log"
	# No MRL_CLEANUP_DIRS registration here: this function runs inside a
	# command substitution, so an append would not survive into the caller.
	# $tmpdir is under $MRL_TMPROOT, which the EXIT trap removes wholesale.
	printf '%s\n' "$tmpdir"
}

# mrl_source_label <input>
#   A stable, host-independent name for the rootfs source, for doc headers.
#   These files are diffed across images, so the header must not carry an
#   absolute host path or a mktemp-random component. Callers may be handed an
#   extraction directory rather than the original image (run-all.sh extracts
#   once and shares the tree), so the true source name is passed down out of
#   band in MRL_SOURCE_LABEL; fall back to the basename of whatever we got.
mrl_source_label() {
	printf '%s\n' "${MRL_SOURCE_LABEL:-$(basename "$1")}"
}

# mrl_header <title> <evidence-line...>
#   Emits a standard markdown header: title, generation notice, and one
#   line per evidence/method string passed in. No timestamps (deterministic
#   output — these files are diffed across images).
mrl_header() {
	local title="$1"
	shift
	printf '# %s\n\n' "$title"
	# shellcheck disable=SC2016 # single quotes intentional: %s is a printf
	# format spec, not a shell expansion; the backtick is literal markdown.
	printf '> Generated by `%s` (P0.3). Do not hand-edit — re-run the script.\n' \
		"${MRL_SCRIPT_NAME:-scripts/inventory/<script>.sh}"
	printf '>\n'
	local line
	for line in "$@"; do
		printf '> %s\n' "$line"
	done
	printf '\n'
}

# mrl_out_dir — resolve the stock-inventory output directory, regardless of
# the caller's cwd. Requires this file to live at
# <repo>/scripts/inventory/common.sh.
#
# The 2026-09 split turned docs/stock-inventory/ from a single directory into
# one per release (docs/stock-inventory/<release>/), so the fixed top-level
# path this function used to return is stale for every gen-*.sh and for
# run-all.sh. Two env vars, checked in order, pick where a run writes/reads:
#   - MRL_OUT_DIR   explicit override -- any directory, created if missing.
#   - MRL_RELEASE   write into docs/stock-inventory/<MRL_RELEASE>/ (created
#                    if missing), e.g. MRL_RELEASE=20260907.
#
# NEITHER SET IS A HARD ERROR, deliberately. This used to fall back to the
# legacy top-level docs/stock-inventory/, "kept so a caller that never heard of
# the split still works" -- but after the split there is no such caller for it
# to serve, and the fallback actively broke the two things it was meant to
# protect:
#
#   1. run-all.sh sets NEITHER variable, so the unqualified recipe in
#      docs/stock-inventory/README.md scattered eight regenerated documents
#      back into the top level, next to the per-release directories rather
#      than inside one. mkdir -p made that silent.
#   2. Step (f) then failed outright anyway: gen-kernel-config-dts.sh's
#      compare_one() now returns 1 when the committed file is absent, and
#      stock-linux.config / stock.dts no longer exist at the top level, so
#      run_step marked it FAILED and run-all.sh exited 1.
#
# A caller that does not say which release it is generating has not been
# helped by guessing; it has been handed a wrong answer or a confusing
# failure. Saying so costs one line and names the fix.
mrl_out_dir() {
	local here repo_root dir inv known d
	here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	repo_root="$(cd "$here/../.." && pwd)"
	if [ -n "${MRL_OUT_DIR:-}" ]; then
		dir="$MRL_OUT_DIR"
	elif [ -n "${MRL_RELEASE:-}" ]; then
		dir="$repo_root/docs/stock-inventory/$MRL_RELEASE"
	else
		# Glob rather than `ls` (SC2012; CI runs shellcheck at default
		# severity, which includes info-level findings).
		inv="$repo_root/docs/stock-inventory"
		known=""
		for d in "$inv"/[0-9]*/; do
			[ -d "$d" ] || continue
			d="${d%/}"
			known="$known ${d##*/}"
		done
		printf '%s\n' \
			"error: neither MRL_RELEASE nor MRL_OUT_DIR is set, so there is no" \
			"       output directory to write to. docs/stock-inventory/ is one" \
			"       directory per release since the 2026-09 split; pick one:" \
			"" \
			"         MRL_RELEASE=<release> $0 ..." \
			"         MRL_OUT_DIR=<dir>     $0 ..." \
			"" \
			"       Existing releases:${known:- (none found)}" >&2
		return 1
	fi
	mkdir -p "$dir"
	printf '%s\n' "$(cd "$dir" && pwd)"
}
