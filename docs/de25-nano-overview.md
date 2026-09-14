# DE25-Nano — how this is going to work

**Who this is for:** someone technical who has not followed the DE25 work and wants the shape of
it in ten minutes: how the board boots, what we build for it, how far along it is, and what could
still stop it. Every section links to the document that holds the evidence. Status as of
**2026-09-14**: everything below is built and checked at the desk; **nothing has run on a
DE25-Nano yet** — the board is on order.

Tags: **[V]** verified (in a file, a build, a vendor artifact, or on silicon by someone else);
**[U]** unverified, with what would settle it.

---

## 1. The short answer

**Yes: a single SD-card image, written the way the DE10-Nano's is, and the board boots from it.**
The card holds everything we build — bootloader, firmware, kernel, root filesystem. The board's
own flash holds Terasic's factory first-stage loader and is **never written** by anything we ship.
"Burn a card, insert it, power on" is the whole workflow, and the DIP switches stay at their
factory setting **[V, `de25-boot-chain.md` §1]**.

Two things are different from the DE10, and both are fine:

- **The boot partition is FAT32 and the loader finds files by name.** There is no `0xA2` raw
  partition and no `uboot.img`; the factory loader reads `u-boot.itb` off partition 1 like any
  other file **[V]**. The exFAT data partition the DE10 uses is still the target for the *data*
  side of the card, exactly as on the DE10 (§3).
- **The kernel is a 64-bit `Image` plus a separate device tree, booted through a text config
  file**, not the DE10's concatenated `zImage_dtb` **[V, `de25-sdcard.md`]**.

What is *not* yet answered, in one sentence: whether our particular bootloader and firmware pair
boots under Terasic's factory loader on real silicon, and how well the SD controller and the
fabric behave once it does. Section 5 ranks those.

---

## 2. The boot chain, link by link

The DE10-Nano's chain is short: a boot ROM in the SoC scans the card for a raw partition, runs
the small loader it finds there, and that loader configures the FPGA and boots Linux. Everything
lives on the card ([`boot-chain.md`](boot-chain.md)).

The DE25-Nano's Agilex 5 has a different first mover: a hard microcontroller in the chip called the
**Secure Device Manager (SDM)** boots first, and it can only load from the board's QSPI flash or
from a JTAG cable — **not from the SD card** **[V, board wiring and the vendor's own manual,
`de25-boot-chain.md` §8.1]**. So the first two links are board-resident, and the seam between
"the board's" and "ours" is permanent.

| # | Link | Lives in | Who builds it | What it does | Status |
|---|---|---|---|---|---|
| 1 | **SDM firmware** | QSPI flash | Terasic (factory) | Boots the SoC, reads the flash | [V] never ours |
| 2 | **Phase-1 bitstream + first-stage loader (SPL)** | QSPI flash | Terasic (factory) | Configures the FPGA fabric with Terasic's reference design, sets up HPS pins and DDR (the *handoff* data is inside this bitstream), then runs U-Boot SPL | [V] never ours; the SPL is U-Boot 2025.01 built from Terasic's public branch (why we keep it: see below) |
| 3 | **SPL reads the card** | — | — | Finds `u-boot.itb` by name on partition 1 (FAT) and verifies its crc32 hashes | [V] by reference: Terasic's own shipped FIT is unsigned crc32 with our exact layout, so the factory loader demonstrably accepts that shape (§5.1) |
| 4 | **`u-boot.itb`** — a container holding **TF-A BL31** (the EL3 secure firmware) + **U-Boot proper** + our board device tree | card, p1 | **us** (mainline U-Boot 2026.07 + TF-A v2.15.0, through Buildroot) | BL31 runs first and stays resident as the SoC's secure monitor; U-Boot proper then takes over | built, structure verified with `dumpimage` [V]; boots under the factory SPL **[U — needs the board]** |
| 5 | **U-Boot boots Linux** | card, p1 | us | Reads `extlinux/extlinux.conf`, loads `Image` + `socfpga_agilex5_de25nano.dtb`, boots | built [V]; SD timing on this board **[U]** |
| 6 | **Linux** | card, p2 | us (kernel 7.2 series, arm64, 92 modules, MiSTer's shared userspace profile) | Mounts the root filesystem, brings up console, network, USB | built; boots under QEMU [V]; on the board **[U]** |
| 7 | **Fabric reconfiguration at runtime** | — | us (kernel + DTS) + later the MiSTer framework | Linux hands a bitstream to BL31 over an SMC call and the SDM rewrites the fabric (§6) | mechanism [V]; not yet exercised by us **[U]** |

Detail: [`de25-boot-chain.md`](de25-boot-chain.md) §2 is this table with the evidence per step;
[`de25-uboot.md`](de25-uboot.md) is link 4 in depth; [`de25-sdcard.md`](de25-sdcard.md) is the card.

**Why the first-stage loader stays Terasic's 2025.01 when everything else is current.** It is
not a choice between old and new U-Boot: the SPL lives *inside the phase-1 bitstream in the
board's flash*, and the only ways to put a different one there are a JTAG cable and a PC. Our
build does compile a modern (2026.07) SPL, and nothing of it is shipped, because using it would
mean reflashing every board once at install time — the "posture 2" bench operation, which
another port of this board did take. Until there is a reason to (§5.3 may supply one), the
factory SPL is the part of the chain we deliberately do not own, and the modern U-Boot *proper*
it hands off to is ours.

**What "never written" costs and buys.** Because links 1–2 are Terasic's, we inherit their DDR
and pin configuration and their loader's policy, and we control exactly one interface: a FIT
named `u-boot.itb` on a FAT partition. That is a thin contract, which is both the good news and
the whole risk **[V, `de25-boot-chain.md` §4]**. It also means there is no field-update path for
the flash and none is needed: recovery from a bad *card* is writing a new card; recovery from a
bad *flash* (which nothing we ship can cause) is a PC with Quartus and the on-board USB-Blaster
**[V, vendor guide]**. The build enforces the rule mechanically: the DE25 U-Boot build fails if
any flash-writing driver, command, or environment location is compiled in
(`external.mk`, `MISTER_UBOOT_DE25_QSPI_AUDIT`) **[V]**.

---

## 3. The card

Today's card (interim, chosen so the first boot has the fewest moving parts) **[V, `de25-sdcard.md`]**:

| Partition | Type | Holds |
|---|---|---|
| p1, 256 MiB | FAT32 `DE25BOOT` | `u-boot.itb`, `Image`, the `.dtb`, `extlinux/extlinux.conf` |
| p2 | ext4 | the Buildroot root filesystem, written directly |

Target card (decided, [ADR 0029](decisions/0029-de25-implementation-path.md) D11): p1 stays FAT
with the boot files; **p2 becomes the exFAT data partition, the `/media/fat` equivalent, holding
`linux/linux.img`**, loop-mounted as root by the same two-stage initramfs the DE10 uses. That
initramfs already builds for aarch64 and passes its QEMU tests (`scripts/test-initramfs.sh
--board de25nano`) **[V]**. The switch is deliberately deferred until a board has answered the
loader, DTS, and SD-controller questions with the simpler card.

`make de25` builds the whole thing into `output-de25/images/sdcard-de25.img`, and a fail-closed
checker rejects any image that looks like DE10 layout lore transplanted (a `0xA2` partition, a
`uboot.img`) **[V]**.

---

## 4. Where things stand

| Piece | State |
|---|---|
| Toolchain, kernel, DTS, root filesystem, card image | build green from one defconfig; the DTS is documented node by node against Terasic's, Altera's, and mainline's trees ([`de25-dts-rationale.md`](de25-dts-rationale.md)) |
| U-Boot + TF-A | built from mainline, pinned by Buildroot; FIT layout matches the factory loader's contract; every flash-writing path compiled out and asserted at build time ([`de25-uboot.md`](de25-uboot.md)) |
| BL31 console | moved to the header UART (a one-line carried patch, matching what Terasic ships), so secure-firmware messages and crashes are visible at bring-up instead of going to an unwired port |
| Reproducibility | the FIT and BL31 are byte-identical across three clean builds on this machine [V]; the only difference against the incremental tree was the toolchain's git-describe banner |
| Stage-1 initramfs (two-stage card) | built for aarch64, QEMU-tested [V] |
| Hardware | none yet; first-boot serial checklist written ([`de25-sdcard.md`](de25-sdcard.md) §6, [`de25-uboot.md`](de25-uboot.md) §11) |

The pre-hardware task list and its history are [`de25-nano-tasks.md`](de25-nano-tasks.md); the
bootloader desk plan is [`uboot-tasks.md`](uboot-tasks.md) (DU-series).

---

## 5. Blockers and unknowns, ranked

### 5.1 Closed at the desk

- **"Will the factory loader reject our unsigned FIT?"** — No. Its config verifies hashes only,
  its device tree carries no signing key, and Terasic's own shipped `u-boot.itb` (extracted from
  the factory SD image) is crc32-only with no signature and the same three-image layout and load
  addresses as ours **[V, `de25-uboot.md` §12]**. This was the sharpest brick-adjacent risk on the
  list ([`de25-boot-chain.md`](de25-boot-chain.md) §7 row 6) and it is now a structural match.
- **Where the environment lives.** On the FAT partition only; the flash-resident fallback that
  mainline compiles in by default is removed and asserted absent **[V]**.
- **Console UART, memory node, SD controller node, SMMU posture** — all resolved by
  cross-checking three vendor trees ([`de25-dts-rationale.md`](de25-dts-rationale.md)).

### 5.2 Open, needs the board (in the order the first boot will hit them)

1. **The version pairing.** Terasic ships U-Boot 2025.01 + TF-A 2.12; we ship 2026.07 + v2.15.0
   under Terasic's 2025.01 SPL. Nobody has run that combination. The SPL→BL31→U-Boot interfaces
   are stable and generic, but this is the one thing only a serial log can confirm **[U]**.
2. **SD controller timing.** We run the controller at default speed with Intel dev-kit PHY
   values; Terasic's own board support uses the same PHY values (and enables faster modes). If
   `Retrieving file: /Image` stalls, this is the first knob ([`de25-uboot.md`](de25-uboot.md) §5.1) **[U]**.
3. **DRAM size.** Declared as 1 GiB in our device tree rather than read from the loader's
   handoff, on purpose; the loader's `DDR:` lines on the console settle it **[U]**.
4. **The MAC address.** The HPS MAC is not fused and is random on every boot; first-boot
   provisioning (as the DE10 does through `u-boot.txt`) is needed before networking is
   deterministic. Learned from another DE25-Nano port **[V there, U here]**.

### 5.3 Open, and project-shaping: programming the fabric from Linux

**Yes, the fabric can be programmed from the HPS — but not the way the DE10 does it, and the
MiSTer framework will need a new back end for it.** On the DE10, Main_MiSTer writes a
memory-mapped FPGA manager directly. On Agilex 5 there is no such device: Linux hands the
bitstream to BL31 with an SMC call, the SDM rewrites the fabric, and the only userspace entry
point is applying a device-tree overlay against an FPGA region **[V, `de25-fpga-reconfig.md`]**.
The mainline kernel has the drivers but no Agilex 5 device-tree nodes for them; ours adds them
**[V]**.

What is known from another DE25-Nano port that runs this path on real hardware:

- **Unsigned, locally compiled bitstreams are accepted** by the factory SDM: bitstream
  authentication is not enforced on shipped boards **[V there]**. This removes the scenario where
  community cores would need a signing infrastructure.
- **A full reconfiguration takes about 3 s of SDM time, roughly 8 s end to end**, and repeated
  switching works only with settle windows before and after — discovered the hard way
  **[V there, U for us]**. MiSTer switches cores dozens of times a session, so this is the number
  to beat and the behaviour to harden ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §6).
- **Do not load cores from U-Boot.** `fpga load` from the bootloader wedged the SDM on that
  port and was retired; load from Linux **[V there]**.
- **A fabric-unconfigured ("HPS-first") flash image is fragile**: it produced a fatal bus error
  on warm reboots there. A flash image that configures a full design at every reset was stable.
  Our posture keeps Terasic's factory (fully configured) image in flash, which is the stable
  shape **[V there]**.

What is still unknown for *our* model specifically:

- **Whether a core compiled by us can be loaded against Terasic's factory phase-1 bitstream.**
  Altera's doctrine for split configuration is that both halves come from the same compilation.
  If that holds, MiSTer-style core switching on an untouched factory flash is not possible, and
  the realistic model becomes what that other port converged on: a **one-time, bench flash of a
  MiSTer "golden" image** (menu core plus HPS handoff) over JTAG at install time — a PC step users
  do once, never an update-channel operation — after which cores switch from Linux
  ([`de25-boot-chain.md`](de25-boot-chain.md) §7 row 15, §4 posture 2) **[U]**.
- **HPS↔FPGA memory sharing.** The DE10's shared framebuffer rides bridges Linux can see and
  control; Agilex 5 exposes no bridge devices to Linux at all, and the aperture semantics for a
  MiSTer-style frame buffer are documented weakly ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §7) **[U]**.
- **Everything above the OS.** Main_MiSTer on aarch64 (or 32-bit under compat), its core-loading
  back end, the fabric-side `sys/` framework, the HDMI and SDRAM IP — none of that exists for
  this board, none of it is this repo's to build, and it gates "MiSTer parity" entirely
  ([`de25-nano-plan.md`](de25-nano-plan.md) §2, layers L0–L2). What this repo delivers first is
  the **bare developer OS** ([ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md)):
  the card, the boot chain, a kernel with the reconfiguration path wired, serial, network — the
  platform someone would port the framework onto.

---

## 6. What the first board session looks like

1. Write today's card, attach the serial cable, watch for the SPL's `DDR:` lines (link 2), then
   the `U-Boot 2026.07` banner (link 4 is proven the moment it prints), then extlinux loading
   `Image` (link 5), then a login prompt (link 6). Checklist: [`de25-sdcard.md`](de25-sdcard.md) §6.
2. If the kernel load stalls, lift the SD controller from default to high speed
   ([`de25-uboot.md`](de25-uboot.md) §5.1).
3. Switch the card to the two-stage exFAT layout (§3).
4. Apply a device-tree overlay carrying a bitstream and time it — the first fabric
   reconfiguration from our Linux, and the measurement the core-switching question needs
   ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §11).
5. Only then decide the golden-image question (§5.3), with numbers.

---

## 7. Map of the detailed documents

| Document | Read it for |
|---|---|
| [`de25-boot-chain.md`](de25-boot-chain.md) | the chain link by link, the flash-writing rules, the brick/strand inventory, the resolved questions |
| [`de25-uboot.md`](de25-uboot.md) | the bootloader build, the FIT contract, the flash audit, first-boot serial expectations |
| [`de25-sdcard.md`](de25-sdcard.md) | card layout, building and writing it, first-boot checklist |
| [`de25-dts-rationale.md`](de25-dts-rationale.md) | every device-tree node and why |
| [`de25-kernel-config.md`](de25-kernel-config.md) | the kernel configuration and its diet |
| [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) | how the fabric is reprogrammed on Agilex 5, latency, the open questions |
| [`de25-implementation-path.md`](de25-implementation-path.md) | the decisions behind the current shape |
| [`de25-reference-implementation.md`](de25-reference-implementation.md) | what was learned from another port's working board |
| [`de25-nano-plan.md`](de25-nano-plan.md) / [`de25-nano-tasks.md`](de25-nano-tasks.md) | the readiness plan and the task history |
| [`de25-readiness-ledger.md`](de25-readiness-ledger.md) | every place the DE10's assumptions are baked into scripts and CI |
| [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md), [ADR 0029](decisions/0029-de25-implementation-path.md) | the governing decisions |
