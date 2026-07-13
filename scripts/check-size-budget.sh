#!/bin/bash

# check-size-budget.sh — Validate that linux.img has ≥15% free space
#
# Usage:
#   ./scripts/check-size-budget.sh <path-to-linux.img>
#   ./scripts/check-size-budget.sh output/images/linux.img
#
# Exit codes:
#   0 — Image is within budget (≥15% free)
#   1 — Image exceeds budget (<15% free)
#   2 — Usage error or missing dependencies

set -o pipefail

# Configuration
THRESHOLD_PERCENT=15

# Main logic
main() {
    local img_path="$1"

    # Validate input
    if [[ -z "$img_path" ]]; then
        echo "Error: Missing argument" >&2
        echo "Usage: $(basename "$0") <path-to-linux.img>" >&2
        return 2
    fi

    # Check if file exists and is readable
    if [[ ! -f "$img_path" ]]; then
        echo "Error: Image file not found: $img_path" >&2
        return 2
    fi

    if [[ ! -r "$img_path" ]]; then
        echo "Error: Image file is not readable: $img_path" >&2
        return 2
    fi

    # Check if dumpe2fs is available
    if ! command -v dumpe2fs &> /dev/null; then
        echo "Error: dumpe2fs not found in PATH" >&2
        echo "Install with: sudo apt-get install e2fsprogs" >&2
        return 2
    fi

    # Extract filesystem metadata
    local dumpe2fs_output
    if ! dumpe2fs_output=$(dumpe2fs -h "$img_path" 2>&1); then
        echo "Error: dumpe2fs failed on $img_path" >&2
        echo "$dumpe2fs_output" >&2
        return 2
    fi

    # Parse key fields
    local block_size block_count free_blocks
    block_size=$(echo "$dumpe2fs_output" | grep "^Block size:" | awk '{print $3}')
    block_count=$(echo "$dumpe2fs_output" | grep "^Block count:" | awk '{print $3}')
    free_blocks=$(echo "$dumpe2fs_output" | grep "^Free blocks:" | awk '{print $3}')

    # Validate parsed values
    if [[ -z "$block_size" || -z "$block_count" || -z "$free_blocks" ]]; then
        echo "Error: Could not parse filesystem metadata" >&2
        echo "Dumpe2fs output:" >&2
        echo "$dumpe2fs_output" >&2
        return 2
    fi

    # Calculate sizes (arithmetic, careful with large numbers)
    local total_blocks free_percent
    total_blocks=$block_count
    # Use bc for floating-point percent calculation to avoid integer truncation
    if ! command -v bc &> /dev/null; then
        # Fallback: integer arithmetic (will round down, acceptable for threshold check)
        free_percent=$((free_blocks * 100 / total_blocks))
    else
        free_percent=$(echo "scale=1; $free_blocks * 100 / $total_blocks" | bc)
    fi

    # Calculate sizes in MiB for reporting
    local total_mib free_mib used_mib
    total_mib=$((block_count * block_size / 1024 / 1024))
    free_mib=$((free_blocks * block_size / 1024 / 1024))
    used_mib=$((total_mib - free_mib))

    # Report
    printf "Image: %s\n" "$img_path"
    printf "Total: %d MiB (%d blocks × %d bytes)\n" "$total_mib" "$block_count" "$block_size"
    printf "Used:  %d MiB\n" "$used_mib"
    printf "Free:  %d MiB\n" "$free_mib"
    printf "Free:  %s%%\n" "$free_percent"

    # Check against threshold
    if (( $(echo "$free_percent < $THRESHOLD_PERCENT" | bc -l 2>/dev/null || echo "$((free_percent < THRESHOLD_PERCENT))") )); then
        printf "\n❌ FAIL: Only %.0f%% free, need ≥%d%%\n" "$free_percent" "$THRESHOLD_PERCENT" >&2
        return 1
    else
        printf "\n✅ PASS: %.0f%% free (≥%d%% required)\n" "$free_percent" "$THRESHOLD_PERCENT"
        return 0
    fi
}

main "$@"
