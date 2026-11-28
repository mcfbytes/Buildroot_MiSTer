# DE25-Nano — where it stands and how it works

**Who this is for:** someone technical who has not followed the DE25 work and wants its shape in
ten minutes. Every section links to the document that holds the evidence.
**Status as of 2026-11-28.** This page is the one place that carries the current state; the
other DE25 documents describe one subject each, and several are history (§7).

Tags: **[V]** verified (the column or the text says where); **[U]** unverified, with what would
settle it.

---

## 1. The goal

The owner's words: "for a user to be able to flash an SD-card and boot MiSTer as they currently
do with DE10-Nano without having to mess with JTAG or anything else." Near term: a basic UI, and
loading cores from userspace. The decision record is
[ADR 0036](decisions/0036-de25-scope-and-base-generations.md) (Proposed).

**Today** the tree builds a bare developer OS for the board: boot firmware, kernel, the DE10's
userspace, a card that installs itself. It boots on a tester's board. It carries no MiSTer
binaries, shows no picture on a factory board, and writes nothing to the board's flash. No
`de25-*` pre-release has been published yet.

## 2. The model in six facts

1. **The chip boots from its QSPI flash, never from the SD card.** A small processor in the
   chip, the SDM, starts first and can read only the flash or a JTAG cable **[V, board wiring]**.
2. **The flash holds a phase-1; cores are files.** The phase-1 sets up the processor, its pins
   and its DDR, and carries the first-stage loader (SPL). Every fabric design is a separate
   `core.rbf`.
3. **A core loads only over a matching phase-1.** The SDM compares an HPS IO hash. It depends on
   the base design **and the Quartus version** **[V, #318]**. So every core is built against one
   named base, a *base generation* ([`de25-quartus.md`](de25-quartus.md) §5).
4. **Terasic's factory flash cannot take cores at all.** It is "FPGA-first": a full image is
   refused at runtime, and no core of ours matches its hash **[V, #318 T1]**. HDMI is dark under
   it, because the HDMI chip is wired to FPGA pins only.
5. **So the flash must be rewritten once.** With an "HPS-first" phase-1 in the flash, cores load
   from U-Boot and from Linux, repeatedly and across warm reboots **[V, #318]**. The plan is that the card's
   first boot writes it ([ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md));
   a PC with a USB cable is the recovery, not the install
   ([`user/de25-recovery.md`](user/de25-recovery.md)).
6. **An HPS-first board powers on with an empty fabric.** U-Boot must load a boot core for
   there to be a picture. A warm reboot keeps whatever core was loaded; a power cycle clears it
   **[V, #318]**.

What a host program needs to load and talk to a core is one page:
[`de25-fabric-interface.md`](de25-fabric-interface.md).

## 3. The boot chain

| # | Link | Lives in | Today | Target |
|---|---|---|---|---|
| 1 | SDM firmware | flash | Terasic's factory image | ours, from the base generation's Quartus build |
| 2 | Phase-1 and SPL | flash | Terasic's, FPGA-first; SPL is their U-Boot 2025.01 | HPS-first; the SPL built here from mainline |
| 3 | `u-boot.itb` (TF-A BL31 + U-Boot + DTB) | card, hidden FAT p1 | ours; loaded by name by the factory SPL **[V, #318]** | the same file |
| 4 | Boot core | card, p1 | none | loaded by U-Boot, with a hash check; a failed load still boots Linux |
| 5 | Linux | card | `Image` + DTB on p1; the root is `linux/linux.img` on the exFAT p2, as on the DE10 **[V, #318]** | the same |
| 6 | Cores at runtime | card, exFAT | `de25-fpga-load` is packaged, not yet run | a host program picks a core; the loader loads it |

Detail: [`de25-boot-chain.md`](de25-boot-chain.md) §0, [`de25-uboot.md`](de25-uboot.md),
[`de25-sdcard.md`](de25-sdcard.md).

## 4. Where things stand

**Tester's board** = one remote DE25-Nano, issue #318. **Owner's board** = on order.

| Piece | Desk / QEMU | Tester's board | Owner's board |
|---|---|---|---|
| TF-A and U-Boot under the factory SPL | built, FIT checked | **boots, 10/10 cold boots** | — |
| Kernel, DTS, SD at high speed, OCRAM node | built | **boots to a login; full-card read clean** | — |
| Two-stage card and first-boot installer | QEMU, with a power cut | **installs and reboots once (ADR 0035 B0 a–c)** | Windows view (d) owed |
| Core load over an HPS-first flash | — | **once from U-Boot; from Linux 20 in a row, and one after each of 10 warm reboots** — with the tester's own Quartus 25.1.1 pair and a bench module | — |
| TF-A patch `0002` (the FPGA service path, [ADR 0034](decisions/0034-de25-fpga-service-path.md)) | host harness | implied by the Linux loads; the tester's confirmation is owed | — |
| `de25-fpga-load` (our loader) | builds | not run | — |
| Base generation 1 (candidate): Altera's baseline on Quartus 26.3 | **hash test 1 passes [V 2026-11-28]**; test 2 not run | — | — |
| HDMI block `de25_hdmi` (splash, framebuffer) | simulated | not run | — |
| U-Boot loads a boot core | not written | (one manual `fpga load` worked) | — |
| First-boot flash write | not written; nothing in the tree writes QSPI | — | — |
| RTL pipeline; core template; Menu core; a basic UI | not started | — | — |
| User documentation | drafted 2026-11-28, times unmeasured | — | — |

**What the hardware results do not yet show.** Every core loaded so far was split from the
*same compile* as its phase-1. That a separately compiled core keeps the hash is hash test 2,
and it decides whether cores can be built independently
([`de25-quartus.md`](de25-quartus.md) §5).

## 5. Gates and open work

The bench gates for the flash image, in [ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md) §4–§5:

| Gate | Question | State |
|---|---|---|
| B0 | the two-stage card boots on the factory flash | **pass** (a–c); (d) owed |
| B1 | fuse status | not read |
| B2 | cores load over an HPS-first image; warm reboots | **pass** |
| B2b | the hash holds across separate compiles | test 1 **pass**; test 2 not run |
| B3 | Linux writes the flash while the SDM owns it | desk only; three accounts to reconcile |
| B4 | write time, write order, the exposed window | not run |
| B5 | an RSU layout fits and builds | fits by size; not built |
| B6 | our own SPL in the image | not run; due before the first public `.jic` |
| B7 | redistribution terms of a `.jic` | open |
| B8 | what a reboot does after the flash is rewritten | not run |

Not on that list, and on the path to the goal: the RTL pipeline (D2.13), a core template and a
Menu core (D2.14), a basic UI (D2.15), the loader's interface and the quiesce contract (D2.11),
the video contract between the base design and its users (ADR 0036 §5). Tasks, the critical
path and the bench order: [`de25-nano-tasks.md`](de25-nano-tasks.md).

**Known anomalies, recorded, not explained:** after a forced warm reset, every core load prints
`S2F/LWS2F bridge enable: Timeout hdskack` until a power cycle, and still succeeds
(ADR 0035 §5).

## 6. Two boards

| Board | Role |
|---|---|
| The owner's | everything destructive or visual: recovery drills first, then every flash-write experiment, the power-cut campaign, HDMI, the boot core, the first loader runs |
| The tester's (#318) | the second unit and the Quartus 25.1.1 reference; restored to factory, the "fresh user" for a release-candidate card and the user docs |

## 7. Map of the documents

**Read in this order.**

| # | Document | Read it for |
|---|---|---|
| 1 | this page | the state and the shape |
| 2 | [`de25-quartus.md`](de25-quartus.md) | which Quartus, the two licences, the version freeze, what a core build must do |
| 3 | [`de25-fabric-interface.md`](de25-fabric-interface.md) | what a host program needs: loading, rules around a load, the address map |
| 4 | [ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md), [ADR 0036](decisions/0036-de25-scope-and-base-generations.md) | the flash image and its gates; the scope and the base generations |
| 5 | [`de25-base-image.md`](de25-base-image.md) | the base design: the HDMI block, its registers, the build |
| 6 | [`de25-boot-chain.md`](de25-boot-chain.md) | the chain link by link, and what would brick or strand a board |
| 7 | [`de25-sdcard.md`](de25-sdcard.md), [`de25-uboot.md`](de25-uboot.md) | the card and its installer; the bootloader build |
| 8 | [`de25-nano-tasks.md`](de25-nano-tasks.md) | live tasks, the critical path, the bench order |

**For users:** [`user/de25-first-boot.md`](user/de25-first-boot.md),
[`user/de25-recovery.md`](user/de25-recovery.md).

**Reference, as needed.**

| Document | Read it for |
|---|---|
| [`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7 | the `/dev/mister` nodes and the full memory map |
| [`de25-dts-rationale.md`](de25-dts-rationale.md) | every device-tree node and why |
| [`de25-kernel-config.md`](de25-kernel-config.md) | the kernel configuration |
| [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) | the reconfiguration path through the kernel; §12 is what was measured |
| [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) | vendor kernels against mainline; the test order T0–T5 and its results |
| [`de25-memory-layout-proposal.md`](de25-memory-layout-proposal.md) | a proposal for the HPS-DDR layout |
| [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md), [ADR 0029](decisions/0029-de25-implementation-path.md), [ADR 0034](decisions/0034-de25-fpga-service-path.md) | the earlier decisions, each with its amendments |

**History.** Correct for their dates, superseded in places, kept because other documents cite
them.

| Document | What it was |
|---|---|
| [`de25-history.md`](de25-history.md) | Phases D0 and D1, Waves 1 to 6, the DU7 boot-path record |
| [`de25-nano-plan.md`](de25-nano-plan.md) | the 2026-08 readiness plan: the board, the layer model, the decision points |
| [`de25-implementation-path.md`](de25-implementation-path.md) | the desk analysis behind ADR 0029 |
| [`de25-reference-implementation.md`](de25-reference-implementation.md) | what a third-party port's sources showed |
| [`de25-patch-portability.md`](de25-patch-portability.md) | the audit of the DE10 patch series |
| [`de25-readiness-ledger.md`](de25-readiness-ledger.md) | where the DE10's assumptions were baked into scripts and CI |
