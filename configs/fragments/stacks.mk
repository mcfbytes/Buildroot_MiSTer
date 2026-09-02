# configs/fragments/stacks.mk — the ONE place that says which fragments make
# up which Buildroot configuration. Included by the top-level Makefile and
# parsed (as plain `NAME := words` lines) by scripts/check-config-fragments.sh
# and scripts/check-kernel-defconfig-sync.sh. Keep it to that shape: one
# `<STACK>_FRAGMENTS := <name> <name> ...` line per stack, names without the
# `.fragment` suffix, in merge order (later fragments layer on earlier ones).
#
# See docs/buildroot-config.md §1 for the mechanism and §10 for why each
# symbol lives where it does.
#
# The de10nano and de10nano-kernel stacks share `common` and `de10nano` BY
# CONSTRUCTION — that is what keeps the kernel-only base (used by `make rt`
# and every CI kernel leg) in lockstep with the shipped image without a
# mirrored copy. scripts/check-kernel-defconfig-sync.sh asserts this.
DE10NANO_FRAGMENTS        := common de10nano de10nano-image
DE10NANO_KERNEL_FRAGMENTS := common de10nano kernel-only
DE25NANO_FRAGMENTS        := common de25nano
