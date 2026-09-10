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
#
# `image-common` is the second sharing axis, at right angles to the first: it
# is in the IMAGE stack of every board and in the kernel-only stack of NONE,
# so a package both images want is selected once instead of mirrored per
# board — and the kernel-only base keeps its no-packages shape (§10 rule 4:
# `common` is in the kernel-only stack's fingerprint text, `image-common` is
# not). Merge order within a stack is free here: no symbol may be defined
# twice in one stack (scripts/check-config-fragments.sh (a)), so the board
# layer and the shared image layer never race.
DE10NANO_FRAGMENTS        := common de10nano image-common de10nano-image
DE10NANO_KERNEL_FRAGMENTS := common de10nano kernel-only
DE25NANO_FRAGMENTS        := common de25nano image-common
#
# The stage-1 initramfs stacks. `initramfs-common` is the third sharing axis:
# it is in NO image stack and NO kernel-only stack — a stage-1 stack builds a
# static musl BusyBox cpio and no kernel (it deliberately does not include
# `common`, which carries BR2_LINUX_KERNEL=y). Per board, only the arch/ABI +
# headers-series lines differ, and scripts/check-config-fragments.sh (f)
# asserts each initramfs-<board> fragment agrees symbol-for-symbol with that
# board's <board>.fragment. Output dirs: output-initramfs/ (DE10, embedded in
# every DE10 kernel) and output-initramfs-de25/ (DE25, built and QEMU-proven,
# not yet embedded — ADR 0029 D11).
INITRAMFS_DE10NANO_FRAGMENTS := initramfs-common initramfs-de10nano
INITRAMFS_DE25NANO_FRAGMENTS := initramfs-common initramfs-de25nano
