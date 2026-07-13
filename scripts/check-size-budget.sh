#!/bin/bash

# check-size-budget.sh — Validate that linux.img has >= 15% free space (P2.7).
#
# Usage:
#   ./scripts/check-size-budget.sh <path-to-linux.img> [host-sbin-dir]
#   ./scripts/check-size-budget.sh output/images/linux.img
#
# Exit codes:
#   0 — Image is within budget (>= 15% free)
#   1 — Image exceeds budget (< 15% free)
#   2 — Usage error or missing dependencies

set -o pipefail

THRESHOLD_PERCENT=15

# Locate dumpe2fs. CI runners often do NOT have e2fsprogs installed
# system-wide, but the Buildroot build always produces one under host/sbin next
# to the image. Prefer an explicit host-sbin arg, then the host/sbin sibling of
# the image dir, then PATH -- the same "use the build's own tools" convention as
# scripts/check-linux-img.sh.
find_dumpe2fs() {
	local img_path="$1" host_sbin="$2" cand
	for cand in \
		"${host_sbin:+$host_sbin/dumpe2fs}" \
		"$(dirname "$img_path")/../host/sbin/dumpe2fs" \
		"$(command -v dumpe2fs 2>/dev/null)"; do
		[ -n "$cand" ] && [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
	done
	return 1
}

main() {
	local img_path="$1" host_sbin="$2"

	if [[ -z "$img_path" ]]; then
		echo "Error: Missing argument" >&2
		echo "Usage: $(basename "$0") <path-to-linux.img> [host-sbin-dir]" >&2
		return 2
	fi
	if [[ ! -f "$img_path" ]]; then
		echo "Error: Image file not found: $img_path" >&2
		return 2
	fi
	if [[ ! -r "$img_path" ]]; then
		echo "Error: Image file is not readable: $img_path" >&2
		return 2
	fi

	local dumpe2fs
	if ! dumpe2fs=$(find_dumpe2fs "$img_path" "$host_sbin"); then
		echo "Error: dumpe2fs not found (checked host-sbin arg, the image's" >&2
		echo "  ../host/sbin sibling, and PATH). Install e2fsprogs, or pass the" >&2
		echo "  Buildroot host/sbin dir as the second argument." >&2
		return 2
	fi

	local dumpe2fs_output
	if ! dumpe2fs_output=$("$dumpe2fs" -h "$img_path" 2>&1); then
		echo "Error: dumpe2fs failed on $img_path" >&2
		echo "$dumpe2fs_output" >&2
		return 2
	fi

	local block_size block_count free_blocks
	block_size=$(echo "$dumpe2fs_output"  | awk '/^Block size:/{print $3; exit}')
	block_count=$(echo "$dumpe2fs_output" | awk '/^Block count:/{print $3; exit}')
	free_blocks=$(echo "$dumpe2fs_output" | awk '/^Free blocks:/{print $3; exit}')

	if [[ ! "$block_size" =~ ^[0-9]+$ || ! "$block_count" =~ ^[0-9]+$ || ! "$free_blocks" =~ ^[0-9]+$ ]]; then
		echo "Error: Could not parse filesystem metadata" >&2
		echo "Dumpe2fs output:" >&2
		echo "$dumpe2fs_output" >&2
		return 2
	fi

	# Integer arithmetic only -- no bc dependency (which CI may lack). Percent is
	# shown to one decimal via *1000; the PASS/FAIL test avoids division entirely
	# (free/total >= T%  <=>  free*100 >= T*total), so there is no rounding error
	# at the threshold boundary.
	local free_pct_x10 free_mib total_mib used_mib
	free_pct_x10=$(( free_blocks * 1000 / block_count ))
	total_mib=$(( block_count * block_size / 1024 / 1024 ))
	free_mib=$((  free_blocks * block_size / 1024 / 1024 ))
	used_mib=$((  total_mib - free_mib ))

	printf 'Image: %s\n' "$img_path"
	printf 'Total: %d MiB (%d blocks x %d bytes)\n' "$total_mib" "$block_count" "$block_size"
	printf 'Used:  %d MiB\n' "$used_mib"
	printf 'Free:  %d MiB\n' "$free_mib"
	printf 'Free:  %d.%d%%\n' "$(( free_pct_x10 / 10 ))" "$(( free_pct_x10 % 10 ))"

	if (( free_blocks * 100 < THRESHOLD_PERCENT * block_count )); then
		printf '\nFAIL: only %d.%d%% free, need >= %d%%\n' \
			"$(( free_pct_x10 / 10 ))" "$(( free_pct_x10 % 10 ))" "$THRESHOLD_PERCENT" >&2
		return 1
	fi
	printf '\nPASS: %d.%d%% free (>= %d%% required)\n' \
		"$(( free_pct_x10 / 10 ))" "$(( free_pct_x10 % 10 ))" "$THRESHOLD_PERCENT"
	return 0
}

main "$@"
