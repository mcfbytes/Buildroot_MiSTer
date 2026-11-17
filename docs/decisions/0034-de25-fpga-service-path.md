# ADR 0034 — DE25-Nano FPGA service path: fix the firmware, keep the kernel vanilla

**Status:** Proposed (2026-11-17). The changes are in the tree; **none has run on a DE25-Nano**.
The decision is confirmed or reversed by tests T1 and T3 in
[`de25-vendor-kernel-delta.md`](../de25-vendor-kernel-delta.md) §8.
**Amends:** [ADR 0029](0029-de25-implementation-path.md) **D8** (reversed: the service node is
described as `intel,agilex-svc` and kernel patch `0102` is dropped) and **D9** (its open TF-A
read is done, and its test is replaced). **Keeps** ADR 0029 **D10** (SMMU disabled), and records
that D10's own re-open condition is met from Linux v7.4.
**Source of record:** [`de25-vendor-kernel-delta.md`](../de25-vendor-kernel-delta.md), a desk
comparison of Terasic's and Altera's kernels with mainline 7.3.4 and v7.4-rc1, TF-A v2.15.0 and
U-Boot 2026.07. Its evidence tags are kept below.
**Impact:** `board/mister/de25nano/` only — the board DTS, the U-Boot DTS, `linux.config`,
`linux-patches/`, and `patches/arm-trusted-firmware/`. **No DE10 file changes.**

## 1. Context

ADR 0029 left one question open and said so: can mainline's `stratix10-svc` program the Agilex 5
fabric at all? D9 named a hardware test and noted that TF-A's Agilex 5 platform code had not been
read. D10 disabled the SMMU on the argument that mainline hands the SDM physical addresses, so
SMMU-off is the only shape in which it could work.

Reading TF-A v2.15.0 against the 7.3.4 driver changes that picture
([`de25-vendor-kernel-delta.md`](../de25-vendor-kernel-delta.md) §3):

- BL31 advertises a buffer window through `FPGA_CONFIG_GET_MEM` and then rejects every address
  in it. The kernel's first data submit is refused **[V]**.
- BL31 returns completion addresses with `0x80000000` subtracted. The kernel cannot match them
  to its buffers, and the FPGA manager spins **[V]**.

So with stock firmware the mainline path fails in every SMMU configuration, not only with the
SMMU on. D10's reasoning was incomplete, and D9's test would have failed for a reason that says
nothing about the SMMU.

Two more facts bear on the choice:

- Linux v7.4 gives `intel,agilex5-svc` driver data that **requires** an attached IOMMU domain
  and fails probe without one **[V]**. ADR 0029 D8 kept that string with the SMMU disabled.
  Those two decisions cannot both hold on 7.4.
- U-Boot's `fpga load` sends the same SMCs with a raw DDR address and never sets up the SMMU
  **[V]**. That is the vendor's standard boot-time load, which suggests the hardware does not
  need the SMMU for this **[I]**.

## 2. Decision

1. **Fix the address contract in BL31.** Carry TF-A patch `0002`: accept the advertised window
   in `FPGA_CONFIG_WRITE`, and return the caller's own address from `COMPLETED_WRITE` unless a
   caller requested remapper bypass. The exception keeps vendor kernels and v7.4's
   `intel,agilex5-svc` path working against the same BL31.
2. **Describe the service node as `intel,agilex-svc`.** That string selects the physical-address
   path on every kernel version, which is the contract the patched BL31 serves.
3. **Drop kernel patch `0102`.** With item 2 it is dead code. Its premise — that Agilex 5 speaks
   the Agilex SMC protocol unchanged — is contradicted by BL31, and upstream gave the string
   different semantics.
4. **Keep the SMMU disabled** (ADR 0029 D10 stands) for the 7.3 line.
5. **Keep the SMMU-on shape as the named fallback**, taken only if hardware shows the SDM cannot
   reach DDR without it. On 7.4 that shape needs no kernel patch.

The result is that no DE25-specific kernel patch is needed for any wave-1 function. Patch
`0101` stays as an optional carry.

## 3. Why this and not the alternatives

| Alternative | Why not |
|---|---|
| Fix it in the kernel: a pool above `0x82000000` and add `DRAM_BASE` on claim | A carried patch to a file upstream is actively changing. BL31 is ours to build and already carries one patch |
| Backport v7.4's Agilex 5 service change and turn the SMMU on | Reverses D10 before any hardware evidence asks for it, and imports the SMMU command-queue stall that the public vendor-kernel port reports after a full fabric load |
| Keep `intel,agilex5-svc` and `0102` until the pin moves | Works on 7.3.4, then stops probing at 7.4 with the SMMU off. It also keeps a patch whose commit message is wrong |
| Wait for hardware and change nothing | The mainline path is known from source not to work. The first bench session would be spent rediscovering that |

## 4. Consequences

- **The device tree names the wrong SoC family on one node.** ADR 0029 D8 wanted to avoid
  exactly that. It is accepted here because the string is what selects driver behaviour, and
  the behaviour we need is the Agilex one.
- **`socfpga-hwmon` stays off.** Under `intel,agilex-svc` it would use the Agilex 7 channel
  table. `linux.config` says so explicitly.
- **On 7.4 the node gains a PSCI notifier** that offlines secondary CPUs on a warm reboot. It
  acts only with `reboot=warm` **[V]**.
- **BL31 carries a second local patch.** It is an upstream candidate; whether to send it is the
  owner's decision.
- **A loader is still needed.** Mainline has no userspace trigger. A draft external module is in
  [`de25-vendor-kernel-delta.md`](../de25-vendor-kernel-delta.md) Appendix A; it is not in the
  tree.

## 5. What confirms or reverses this

| Result | Effect |
|---|---|
| T1 passes (U-Boot `fpga load`, SMMU untouched) and T3 passes (Linux load through the patched BL31) | Accept. D10 is confirmed on hardware |
| T1 passes, T3 fails | The decision stands; the fault is in our patch, module or the driver. Debug |
| T1 fails, or T0 finds the revision-A workaround bit set, or the SMMU resets to abort | Reverse items 2 and 4: enable the SMMU and use `intel,agilex5-svc`. Take it with the 7.4 pin rather than a backport if timing allows. Item 1 stays; it is harmless to that shape |

## 6. Re-examine at the 7.4 pin move

ADR 0029 D8 and D10 both said to re-open when upstream gave the match table per-compatible
meaning or made the service driver IOMMU-aware. Both happened in v7.4. The pin move is therefore
a decision point, not a routine bump. [`de25-vendor-kernel-delta.md`](../de25-vendor-kernel-delta.md)
§6.3 lists what changes, including the SD controller, which gets a real driver there.

## 7. Not decided here

- Whether TF-A patch `0002` or the kernel robustness findings are sent upstream.
- The loader's interface, and when it lands.
- Whether `STRICT_DEVMEM` stays on for the DE25. It is on today by arm64's default. It is off
  on the DE10 by arm32's default, with no config line, and Main_MiSTer relies on that.
