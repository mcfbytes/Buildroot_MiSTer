#!/usr/bin/env bash
#
# list-kernel-variants.sh — the kernel-variant registry, derived from the
# filesystem instead of hand-maintained in N places (item D, follow-up to
# ADR 0021 as amended 2026-07-18).
#
# WHY THIS EXISTS: build.yml and release.yml each carried their own
# `kernel: [rt]` matrix literal, and both files' headers claimed "adding a
# variant = one matrix entry" — a claim that was already false the moment a
# second workflow needed the same list, since it actually meant editing TWO
# matrix literals plus the fragment. The real registry has always been
# .github/actions/buildroot-build/action.yml's fragment-existence check
# (configs/mister_<name>.fragment): a variant is accepted there iff that file
# exists, no other list consulted. This script is the one place that reads
# that same registry and emits it as JSON, so both workflows' matrices are
# `fromJSON()` of ONE computed list instead of two typed-by-hand ones that can
# drift apart (which is exactly the bug this item exists to close).
#
# CONTRACT: stdout is EXACTLY one line — a JSON array of variant names (e.g.
# ["rt"]) — on success, and nothing else. On failure (including the
# "zero fragments" case below) this exits non-zero with a message on stderr
# and prints NOTHING resembling JSON to stdout, so a caller that forgot to
# check the exit code gets a `fromJSON` parse error instead of a silently
# empty matrix. That distinction matters: an empty `strategy.matrix.kernel`
# is not "no legs, that's fine" to GitHub Actions — a job with zero matrix
# combinations runs zero times and the job itself is reported as a no-op,
# which reads as green. Failing loudly here is what stands between a
# filesystem accident (e.g. every fragment deleted) and a release/CI run that
# silently ships zero kernel variants while looking successful.
#
# EXCLUDED ON PURPOSE: configs/mister_kernel_defconfig (the shared kernel-only
# BASE every variant builds against) and configs/mister_initramfs_defconfig
# (the stage-1 initramfs config). Neither carries a `.fragment` suffix, so the
# glob below already excludes both without any special-casing — the explicit
# denylist further down exists only so that fact survives a future rename
# instead of relying on an accident of extension.
#
# ALSO RESERVED: the variant name "main". Unlike the two defconfigs above,
# a hypothetical configs/mister_main.fragment WOULD match the *.fragment glob
# below -- but .github/actions/buildroot-build/action.yml's `case` matches
# `main)` as its FULL-IMAGE build, not a kernel-only one, so that name reaching
# a matrix would silently run a ~3h20m `make all` inside a kernel leg instead
# of a kernel-only build, only failing much later when the leg's staging step
# looks for output-main/images/zImage_dtb. Checked explicitly below, by name,
# so this can never reach a matrix.
#
# NAME VALIDATION mirrors buildroot-build/action.yml's own variant-name
# whitelist ([a-z0-9_-]) — a name that whitelist would reject must not reach
# a matrix (and from there a shell/path context) via this script either.
#
# Exit: 0 with one JSON line on stdout = the registry, however many entries;
# 1 = a fragment yielded an invalid name, or zero fragments were found (both
# are repo bugs, not valid empty states); 2 = usage/IO error.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -d configs ]; then
	echo "list-kernel-variants: FATAL: configs/ not found under $ROOT" >&2
	exit 2
fi

variants=()
shopt -s nullglob
for f in configs/mister_*.fragment; do
	case "$f" in
	configs/mister_kernel_defconfig | configs/mister_initramfs_defconfig)
		# Unreachable given the *.fragment glob above -- neither defconfig
		# carries that extension -- but kept explicit per the EXCLUDED ON
		# PURPOSE note in the header, so this is documented in code, not
		# just prose.
		continue
		;;
	esac

	name="${f#configs/mister_}"
	name="${name%.fragment}"

	case "$name" in
	main)
		echo "::error::${f} yields the variant name 'main' -- that name is RESERVED by .github/actions/buildroot-build for the full-image build, not a kernel-only variant (see the ALSO RESERVED note in this script's header); rename the fragment" >&2
		exit 1
		;;
	esac

	case "$name" in
	*[!a-z0-9_-]* | '')
		echo "::error::${f} yields an invalid variant name '${name}' -- kernel-variant names must be non-empty [a-z0-9_-] (see the variant validation in .github/actions/buildroot-build/action.yml)" >&2
		exit 1
		;;
	esac

	variants+=("$name")
done
shopt -u nullglob

if [ "${#variants[@]}" -eq 0 ]; then
	echo "::error::no kernel-variant fragments found under configs/ (expected at least configs/mister_rt.fragment, see docs/rt-beta-kernel.md / ADR 0021) -- refusing to emit an empty matrix, which GitHub Actions would run as zero legs and report as a success" >&2
	exit 1
fi

# Sort for a deterministic, reviewable order -- glob order is filesystem-
# dependent, not something a matrix's log output should depend on. mapfile,
# not a bare command-substitution word-split, so a (currently impossible,
# whitelist-enforced) name containing whitespace still round-trips intact --
# same defensive habit lint.yml's own shellcheck step uses. LC_ALL=C so the
# order can't depend on the runner's locale either (same convention as
# scripts/check-abi.sh, scripts/check-linux-img.sh, scripts/ci-tests.sh).
before="${#variants[@]}"
mapfile -t variants < <(printf '%s\n' "${variants[@]}" | LC_ALL=C sort)

# `mapfile < <(... | sort)` does NOT observe a `sort` failure: neither
# `set -e` nor `set -o pipefail` sees inside a process substitution, and
# mapfile itself returns 0 having simply read however many lines `sort`
# managed to emit before dying (e.g. a killed/OOM'd `sort` under TMPDIR
# exhaustion -- build.yml carries an explicit disk-reclaim step, so that is
# not a hypothetical here). That would silently shrink (in the worst case, to
# zero) the already-validated `variants` array AFTER the non-empty check
# above has passed, which is exactly the silently-empty-matrix failure mode
# this script's whole header promises to refuse. Re-check the count is
# unchanged post-sort so a partial/failed sort is caught here, loudly,
# instead of downstream as a mysteriously smaller (or empty) matrix.
if [ "${#variants[@]}" -ne "$before" ]; then
	echo "::error::internal error: sorting ${before} variant name(s) yielded ${#variants[@]} -- 'sort' likely failed inside the process substitution (its exit status is invisible to mapfile/set -e); refusing to emit a matrix that may have silently lost entries" >&2
	exit 1
fi

json="["
for i in "${!variants[@]}"; do
	[ "$i" -gt 0 ] && json+=","
	json+="\"${variants[$i]}\""
done
json+="]"

printf '%s\n' "$json"
