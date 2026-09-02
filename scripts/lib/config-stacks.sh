#!/usr/bin/env bash
#
# scripts/lib/config-stacks.sh — read configs/fragments/stacks.mk and strip
# fragment files. Not directly executable; sourced (same convention as
# scripts/lib/board-expectations.sh) by scripts/check-kernel-defconfig-sync.sh
# and scripts/check-config-fragments.sh. The sourcing script must have set
# ROOT to the repository root first.
#
# stacks.mk is the SINGLE source of truth for which fragments make up which
# Buildroot configuration; the top-level Makefile `include`s it and this file
# parses the same `<STACK>_FRAGMENTS := a b c` lines with sed, so a stack
# can never be defined one way for `make` and another for the checks. Keep
# stacks.mk to that one-line-per-stack shape (docs/buildroot-config.md §1).

# shellcheck disable=SC2034 # read by the sourcing scripts
CONFIG_STACKS_MK="$ROOT/configs/fragments/stacks.mk"
CONFIG_FRAGMENT_DIR="$ROOT/configs/fragments"

# Every `<STACK>` name defined in stacks.mk (DE10NANO, DE10NANO_KERNEL, ...).
config_stack_vars() {
	sed -n 's/^\([A-Z0-9_]*\)_FRAGMENTS[[:space:]]*:=.*$/\1/p' "$CONFIG_STACKS_MK"
}

# $1 = stack var name -> its fragment NAMES, in merge order, one per line.
config_stack_fragments() {
	sed -n "s/^$1_FRAGMENTS[[:space:]]*:=[[:space:]]*//p" "$CONFIG_STACKS_MK" \
		| sed -e 's/[[:space:]]*#.*$//' | tr -s ' \t' '\n' | sed '/^$/d'
}

# $1 = stack var name -> absolute fragment paths, in merge order, one per line.
config_stack_files() {
	local n
	while IFS= read -r n; do
		[ -n "$n" ] || continue
		printf '%s\n' "$CONFIG_FRAGMENT_DIR/$n.fragment"
	done < <(config_stack_fragments "$1")
}

# DE10NANO_KERNEL -> de10nano-kernel: the human-facing stack name.
config_stack_label() {
	printf '%s\n' "$1" | tr 'A-Z_' 'a-z-'
}

# Strip comments/blank lines from a fragment, KEEPING `# BR2_X is not set`
# lines (kconfig reads those as an explicit =n — they are configuration, not
# commentary). Output: only `BR2_...=...` and `# BR2_... is not set` lines,
# trailing same-line comments and whitespace removed. Values are otherwise
# verbatim, so a value containing '=' or '#' inside quotes survives — no
# committed value carries a bare ` #`, which is the one thing this would
# mis-strip.
config_strip_fragment() {
	sed -e 's/^[[:space:]]*# \(BR2_[A-Za-z0-9_]*\) is not set.*$/@@NOTSET@@\1/' \
	    -e 's/^[[:space:]]*#.*$//' \
	    -e 's/[[:space:]]\+#.*$//' \
	    -e 's/[[:space:]]*$//' \
	    -e 's/^@@NOTSET@@\(.*\)$/# \1 is not set/' "$@" \
		| grep -e '^BR2_' -e '^# BR2_' || true
}

# The symbol NAME of a stripped line (either form).
config_line_symbol() {
	case "$1" in
		"# "*" is not set") local s="${1#\# }"; printf '%s\n' "${s% is not set}" ;;
		*) printf '%s\n' "${1%%=*}" ;;
	esac
}
