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
# There is no kernel-only stack any more (ADR 0030 Phase C, 2026-09-11): the
# PREEMPT_RT variant is package/linux-rt, a second kernel package built by the
# de10nano IMAGE configuration from the same board/mister/de10nano/linux.config,
# so the "kernel variants build on the image's toolchain/kernel fragments"
# property holds by construction -- there is only one configuration.
#
# `image-common` is the sharing axis between boards: it is in the IMAGE stack
# of every board, so a package both images want is selected once instead of
# mirrored per board.
DE10NANO_FRAGMENTS        := common de10nano image-common de10nano-image
DE25NANO_FRAGMENTS        := common de25nano image-common
#
# There is no stage-1 initramfs stack any more (ADR 0030, 2026-09-11): the
# cpio is package/mister-initramfs, built by the main configuration with the
# main toolchain, and embedded by linux/linux-ext-mister-initramfs.mk.
