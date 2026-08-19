# DE25-Nano boot chain — QSPI, SD, and the user experience

**Status:** desk-research first pass, 2026-08-19 — no hardware touched. This is a
*partial* result of task D0.1 ([`de25-nano-tasks.md`](de25-nano-tasks.md)); §8 lists
what remains, and every load-bearing claim here must still survive D0.1's adversarial
verify and D2.2's on-hardware test before any flash-path code trusts it. Claims are
tagged **[V]** (verified against a named source) / **[U]** (unverified). Cross-refs:
[`de25-nano-plan.md`](de25-nano-plan.md) §4.1,
[ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md), and — for the DE10
baseline this is contrasted against — [`boot-chain.md`](boot-chain.md).

**Sources** (retrieved 2026-08-19):
- Terasic **DE25-Nano User Manual**, rev. 2025-09-05 (51 pp., via DigiKey mirror
  `mm.digikey.com/...P0804.pdf`) — cited below as *UM* §/page.
- Altera **Agilex 5 E-series GHRD Linux boot examples**, rel-25.1
  (`altera-fpga.github.io/rel-25.1/.../ug-linux-boot-agx5e-premium/`) — cited as *GHRD*.
- Intel **Agilex 5 SoC FPGA Boot Overview** (doc 813762) and **Agilex SoC Boot /
  Configuration User Guides** (cdrdv2 667140, 704696) — cited as *Intel-boot* /
  *Intel-cfg*.
- RocketBoards **Building Bootloader for Agilex 5**.

---

## 1. The headline answer

**Routine use never writes QSPI [V].** The QSPI ships factory-programmed (*UM* §3.1),
and in the HPS-first flow everything a user or a release touches — U-Boot proper, ATF
BL31, the fabric bitstream, kernel, rootfs — lives on the SD card (*GHRD*). Burning a
fresh SD card and inserting it is the whole workflow; the DIP switches stay at factory
default. New-card UX therefore matches the DE10.

What the DE10 never had is a **seam**: the first two boot-chain links (SDM firmware +
FSBL) live in QSPI, board-resident, while everything after lives on the card and
changes per release. §4–§5 are about managing that seam; it is a *project-side*
decision made once, not a user-facing per-card or per-release event.

## 2. Boot chain, link by link

1. **Power-on → SDM** (Secure Device Manager — hard microcontroller, boots first)
   **[V Intel-boot]**. MSEL[2:0] selects the configuration source (§3).
2. **SDM loads from QSPI** (AS-Fast, the board default): its own firmware plus the
   *phase-1* "HPS-first" bitstream — HPS pin/DDR configuration only, with the **FSBL
   embedded** (U-Boot SPL or ATF BL2) **[V GHRD, Intel-boot]**. SDM configures HPS
   SDRAM pins, places the FSBL in OCRAM, releases the HPS **[V Intel-boot]**.
3. **FSBL initializes DDR, reads the SD card**: loads `u-boot.itb` — a FIT carrying
   ATF **BL31** + U-Boot proper + DTB — from the FAT partition **[V GHRD]**. From here
   the chain is card-resident.
4. **U-Boot loads the phase-2 fabric bitstream** (`core.rbf`, `fpga load`) and the
   kernel from the same FAT partition; boots Linux from the rootfs partition
   **[V GHRD]**. (A U-Boot-less "ATF-to-Linux" variant exists in *GHRD*; noted, not
   pursued.)
5. **Linux reconfigures the fabric at runtime** via the SDM mailbox — the
   `stratix10-soc` FPGA manager + DT overlays (the eventual core-switching path;
   latency dossier is task D0.2) **[V driver exists / U latency]**.

**No 0xA2 analogue [V].** The DE10's raw-partition-scanned-by-BootROM mechanism does
not exist here; the FSBL finds `u-boot.itb` **by name on the FAT partition** (*GHRD*).
The partition-order lore in [`boot-chain.md`](boot-chain.md) §2 does not transfer.

## 3. What lives where

| Artifact | Location | Owner / change cadence |
|---|---|---|
| SDM firmware | QSPI | Altera toolchain version; effectively never (posture §4) |
| Phase-1 HPS bitstream (pin/DDR handoff) | QSPI | board vendor design; effectively never |
| FSBL (U-Boot SPL / ATF BL2) | QSPI (embedded in phase-1 image) | same |
| `u-boot.itb` (ATF BL31 + U-Boot + DTB) | SD, FAT partition | **ours, per release** |
| Phase-2 fabric bitstream (`core.rbf`) | SD, FAT | ours / eventually per-core |
| Kernel (`Image`/FIT), DTB | SD, FAT | ours, per release |
| Rootfs | SD | ours, per release |

Board facts (*UM* p.9, §3.8.4): 128 Mbit (16 MB) QSPI, ASx4; **USB-Blaster III
on-board** (USB-C); 1 GB LPDDR4 on HPS "shared with FPGA"; microSD socket wired to the
**HPS**, described as "not only … external storage for the HPS but also … an
alternative boot option" — one ambiguous sentence, see §8-Q1.

## 4. MSEL and the "is QSPI writing required?" decision

*UM* Table 3-2 documents exactly **two** configuration schemes **[V]**:

| MSEL[2:0] | Scheme | Meaning |
|---|---|---|
| `001` | AS Fast | FPGA configured from QSPI Flash (**factory default**, pre-programmed) |
| `111` | JTAG | configure via on-board USB-Blaster III |

No SD/MMC scheme is documented for this board, although Agilex 5 silicon has an SD/MMC
active-configuration controller (*Intel-cfg*) — §8-Q1.

Three postures for the QSPI-resident links, one to be chosen (this graduates with the
DP-1 ADR at D2.7; the recommendation below is not yet a decision):

1. **Pin to factory QSPI; never write it** — *recommended for v1*; the exact analogue
   of the DE10 "stock `uboot.img`, byte-identical" posture. Our SD payload must be
   loadable by Terasic's shipped FSBL: their SPL must find and boot our mainline
   `u-boot.itb`. The name+location contract is the stable interface **[V GHRD]**;
   whether their specific SPL build honors it for our FIT is **[U → D2.2 first test]**.
   If it works: pure DE10 UX forever; we record the factory QSPI version we tested
   against (§5).
2. **Ship our own QSPI image** (SDM fw + phase-1 + our FSBL): full control of the
   SPL/DDR handoff, at the cost of a **one-time QSPI flash per board** at onboarding —
   a real gotcha the DE10 never had. If ever forced here, updates go through **RSU**
   (§6), never raw writes.
3. **Hybrid**: start at 1; fall back to 2 only if the factory FSBL proves
   incompatible, shipping the QSPI update RSU-protected as a documented one-time step.

## 5. The version-skew seam (the one gotcha to engineer away)

QSPI side: SDM firmware + FSBL + DDR/pinmux handoff (board-resident, ~static). SD
side: everything else (ours, per release). Failure mode: a release whose `u-boot.itb`
the resident FSBL cannot load — the DE25 equivalent of the DE10's zImage_dtb contract
break, except the user cannot see or fix it by re-imaging the card *if* the mismatch
is QSPI-side. Release discipline that keeps this impossible:

- Every DE25 release records **which factory QSPI version(s) it is tested against**
  (Terasic System CD revision; QSPI image hash once we can dump it — D2.2).
- The FSBL→`u-boot.itb` interface (FAT partition number, filename, FIT format) is
  treated as a frozen contract; changes to any of it are release-blocking findings.
- No release ever writes QSPI as a side effect. If a QSPI update is ever shipped
  (posture 2/3), it is a separate, explicit, RSU-protected artifact with its own
  documentation — the `updateboot` analogue **must not** be a cargo-culted raw `dd`:
  the DE10 habit (whole-disk `dd` + env wipe,
  [`downloader-contract.md`](downloader-contract.md) §8) is board-fatal here.

## 6. QSPI update safety and the unbrick path

- **RSU (Remote System Update)** is Altera's power-loss-safe QSPI update framework:
  a factory fallback image plus application image slots; the SDM falls back
  automatically on a corrupt/interrupted image **[V Intel docs / U fit-in-16MB — §8-Q4]**.
  Any future QSPI-writing flow uses RSU or does not exist. (This is the concrete form
  of the DP-3 caveat recorded in [`de25-nano-plan.md`](de25-nano-plan.md) §6: the
  *boot-firmware* layer has no pull-the-card recovery, unlike the rootfs.)
- **The board is effectively unbrickable [V UM §3.2]:** the USB-Blaster III is
  on-board — worst case is MSEL→`111` (JTAG) + Quartus Programmer on a PC over USB-C
  to reflash QSPI, then MSEL back to `001`. Annoying (needs a PC + Quartus install),
  not fatal, and needs no external programmer hardware.

## 7. What would brick or strand the board (fail-closed inventory, desk-research level)

| # | Action | Consequence | Guard |
|---|---|---|---|
| 1 | Raw/partial QSPI overwrite (non-RSU), interrupted | No SDM config → no boot from AS; recover only via JTAG+PC | §5 rule: no release writes QSPI; RSU-only if ever |
| 2 | Shipping `u-boot.itb` the resident FSBL can't parse | Board strands at FSBL; user re-images card in vain if told "it's the card" | frozen FSBL contract + per-release factory-QSPI test matrix (§5) |
| 3 | Porting DE10 `updateboot` semantics (raw `dd`, env wipe at fixed sectors) | Writes garbage at Agilex-meaningless offsets; worst case hits QSPI-adjacent state | board-identity assertion before any flash step (ADR 0027 §Decision 4) |
| 4 | MSEL switched away from `001` by a user following DE10-era lore | No boot until switched back | docs: "switches stay at default" is the only user-facing rule |

## 8. Open questions (the remainder of D0.1)

- **Q1 — SDM boot from SD/MMC on *this board*.** Silicon has an SD/MMC configuration
  controller (*Intel-cfg*) and *UM* §3.8.4 calls the microSD "an alternative boot
  option", yet Table 3-2 offers no SD scheme and the socket wires to the HPS. If an
  undocumented MSEL combination let the SDM fetch phase-1 + FSBL from the card, the
  QSPI seam vanishes entirely (everything-on-card, full DE10 parity). **Ask Terasic /
  test on hardware.** [U]
- **Q2 — Factory QSPI contents.** Which FSBL (U-Boot SPL vs ATF BL2), which
  SDM-firmware/Quartus version, dumpable hash, and whether Terasic's System CD ships
  the QSPI image for re-flash. [U]
- **Q3 — FSBL→`u-boot.itb` contract verification.** Does the factory SPL boot a
  mainline-built FIT (BL31 + U-Boot 2026.x + DTB)? First test of D2.2. [U]
- **Q4 — RSU layout in 16 MB.** Factory + how many app images fit, given Agilex 5
  phase-1 image sizes. [U]
- **Q5 — U-Boot environment location** (QSPI via SDM? FAT file? nowhere/default-env)
  and the warm-reboot / core-preload story ([`boot-chain.md`](boot-chain.md) §6
  analogue). [U]
- **Q6 — DDR handoff coupling.** How much of the DDR init lives QSPI-side (phase-1
  handoff) vs in our `u-boot.itb`, i.e. how tightly posture-1 pins us to Terasic's
  DDR configuration. [U]
