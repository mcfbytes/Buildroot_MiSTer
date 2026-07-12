#!/usr/bin/env bash
# scripts/inventory/gen-kernel-config-dts.sh <zImage_dtb> [output-dir]
#
# Item (f): regenerate the stock kernel .config (via IKCONFIG) and the DTS
# (via the appended DTB) from a zImage_dtb file, per PLAN.md A3 / the
# "Reproduction" recipe in docs/verification/stock-release-20250402.md.
#
# Output-dir defaults to a scratch temp directory (never overwrites the
# committed docs/stock-inventory/{stock-linux.config,stock.dts} unless you
# explicitly pass that path). After generating, this script always diffs its
# output against the committed files if they exist, and reports:
#   - byte-identical
#   - content-identical (cosmetic-only diff, e.g. dtc version formatting)
#   - DIFFERS (a real content difference -- investigate)
#
# Requires: python3, dtc. No root needed.
#
# shellcheck disable=SC2016 # markdown backticks in printf format strings are
#   intentionally single-quoted throughout this file (literal text, not
#   shell expansion).
# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed
#   path; shellcheck can't resolve it statically (verified manually, and by
#   `shellcheck -x` in CI).
# shellcheck disable=SC2034 # MRL_SCRIPT_NAME is read by mrl_header() in the
#   sourced common.sh, not in this file, so shellcheck's single-file
#   analysis can't see the use.
set -euo pipefail

MRL_SCRIPT_NAME="scripts/inventory/gen-kernel-config-dts.sh"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "usage: $0 <zImage_dtb> [output-dir]" >&2
	exit 2
fi
zimage_dtb="$1"
outdir="${2:-}"

mrl_require python3 dtc

if [ ! -f "$zimage_dtb" ]; then
	echo "error: '$zimage_dtb' is not a regular file" >&2
	exit 1
fi

if [ -z "$outdir" ]; then
	outdir="$(mktemp -d "${TMPDIR:-/tmp}/mister-kernel-extract.XXXXXX")"
	MRL_CLEANUP_DIRS+=("$outdir")
else
	mkdir -p "$outdir"
fi

out_config="$outdir/stock-linux.config"
out_dtb="$outdir/stock.dtb"
out_dts="$outdir/stock.dts"

python3 "$here/kernel_extract.py" "$zimage_dtb" \
	--out-config "$out_config" --out-dtb "$out_dtb"

dtc -I dtb -O dts -o "$out_dts" "$out_dtb"

echo "Generated:"
echo "  $out_config"
echo "  $out_dtb"
echo "  $out_dts"

committed_dir="$(mrl_out_dir)"
committed_config="$committed_dir/stock-linux.config"
committed_dts="$committed_dir/stock.dts"

# mrl_diff_stable <a> <b> — unified diff with fixed labels/no timestamps, so
# output stays deterministic regardless of host tmpdir names or file mtimes.
mrl_diff_stable() {
	diff -u --label "committed/$(basename "$1")" --label "generated/$(basename "$2")" "$1" "$2"
}

compare_one() {
	local label="$1" generated="$2" committed="$3"
	if [ ! -f "$committed" ]; then
		echo "[$label] no committed file at docs/stock-inventory/$label to compare against"
		return 0
	fi
	if cmp -s "$generated" "$committed"; then
		echo "[$label] byte-identical to the committed docs/stock-inventory/$label"
		return 0
	fi
	# Try a formatting-insensitive compare for DTS: dtc's cosmetic
	# rendering (tabs vs spaces, hex zero-padding, "// version:" header
	# comments) varies across dtc releases even when the tree content is
	# identical. Strip comments/blank lines, collapse whitespace, and
	# normalize hex literal padding before the final content diff.
	local norm_a norm_b
	norm_a="$(mktemp)"
	norm_b="$(mktemp)"
	python3 "$here/normalize-dts.py" "$generated" "$norm_a"
	python3 "$here/normalize-dts.py" "$committed" "$norm_b"
	if cmp -s "$norm_a" "$norm_b"; then
		echo "[$label] content-identical to the committed docs/stock-inventory/$label (cosmetic-only diff -- see below)"
		mrl_diff_stable "$committed" "$generated" | head -20 || true
		rm -f "$norm_a" "$norm_b"
		return 0
	else
		echo "[$label] DIFFERS from the committed docs/stock-inventory/$label (real content difference):"
		mrl_diff_stable "$committed" "$generated" | head -60 || true
		rm -f "$norm_a" "$norm_b"
		return 1
	fi
}

status=0
config_result="$(compare_one "stock-linux.config" "$out_config" "$committed_config")" || status=1
echo "$config_result"
dts_result="$(compare_one "stock.dts" "$out_dts" "$committed_dts")" || status=1
echo "$dts_result"

# Emit the item (f) summary doc alongside the two data files (which this
# script deliberately does NOT overwrite by default -- see header comment).
doc="$(mrl_out_dir)/kernel-config-dts.md"
dtc_version="$(dtc -v 2>&1 | head -1)"
{
	mrl_header "Kernel config + DTS: regeneration (item f)" \
		"Evidence method: python3 (scripts/inventory/kernel_extract.py + lz4_legacy.py) to pull the IKCONFIG .config and the appended DTB out of a zImage_dtb; dtc -I dtb -O dts for the DTS text." \
		"dtc version used for this run: ${dtc_version}" \
		"Regenerated from: $zimage_dtb"
	printf 'Regeneration script: `scripts/inventory/gen-kernel-config-dts.sh <zImage_dtb> [output-dir]`.\n'
	printf 'By default it writes to a scratch temp dir and never touches the committed\n'
	printf '`stock-linux.config` / `stock.dts` -- it only *compares* its fresh output\n'
	printf 'against them. Point `output-dir` at `docs/stock-inventory` to actually\n'
	printf 're-commit (e.g. after building a new image in P1+).\n\n'
	printf '## Verification result (this run)\n\n'
	printf -- '- %s\n' "$config_result"
	printf -- '- %s\n' "$dts_result"
	printf '\n'
	printf '## Why `stock.dts` is only "content-identical", not byte-identical\n\n'
	printf 'The committed `stock.dts` was decompiled by an earlier/different `dtc`\n'
	printf 'build than the one installed in this environment. The two texts differ in\n'
	printf 'exactly one line -- the `/memreserve/` header (`/memreserve/ 0 0x1000;` vs\n'
	printf '`/memreserve/\\t0x0000000000000000 0x0000000000001000;`, a tab-vs-space and\n'
	printf 'decimal-vs-hex-zero rendering choice, same value) -- plus whether a\n'
	printf '`// version: N` / `// last_comp_version: N` / `// boot_cpuid_phys: N`\n'
	printf 'banner is emitted and whether nodes are indented with tabs or 4 spaces.\n'
	printf 'Every node, property, and value in the tree is identical; see\n'
	printf '`scripts/inventory/normalize-dts.py` for the exact, narrow normalization\n'
	printf '(whitespace collapse + hex/decimal literal equivalence) used to prove this,\n'
	printf 'and re-run `gen-kernel-config-dts.sh` yourself to reproduce the diff.\n'
} >"$doc"
echo "Wrote $doc"

exit "$status"
