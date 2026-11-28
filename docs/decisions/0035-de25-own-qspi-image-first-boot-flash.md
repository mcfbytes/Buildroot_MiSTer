# ADR 0035 — DE25-Nano: our own QSPI image, written once by the first boot

**Status:** Proposed (2026-11-25). The owner agreed the direction on 2026-11-25. **Nothing in the
tree writes QSPI yet.** Bench gates B0–B7 (§4) confirm or reverse each part. *2026-11-26:* B0 and
B2 passed on #318's bench, with an HPS-first image built there rather than one of ours (§5), so
D2 is decided.
**Amends:** [ADR 0029](0029-de25-implementation-path.md) **D4**. Posture 1 stays the shipping
state until this ADR's image exists. After that, the rule "nothing we ship writes QSPI" becomes
"exactly one thing writes QSPI: the first-boot installer, once, verified". Also amends
[`de25-nano-tasks.md`](../de25-nano-tasks.md) **D2.9** item 4: the matched pair is written by the
first boot, not over JTAG.
**Source of record:** test T1 on #318 (2026-11-25);
[`de25-boot-chain.md`](../de25-boot-chain.md) §4, §5 and §7;
[`de25-nano-overview.md`](../de25-nano-overview.md) §5.3.

## 1. Context

**T1 closed the posture-1 route to cores.** It was run on #318 on 2026-11-25, against a factory
QSPI whose contents were verified byte for byte against `golden_top_hps.jic`.

- **A full-image RBF is rejected at runtime.** It was built from a default GHRD whose HPS IO hash
  equals the factory one. The SDM answers config status `0xf0040000`, "Bitstream element not
  understood".
- **An HPS-first `core.rbf` is rejected with the same status.** Making the design HPS-first, the
  only way `quartus_pfg` emits a `core.rbf`, changes the HPS IO hash. The SDM requires the
  incoming core to match the running phase-1's hash.
- **CvP is not in the design, and the Terasic System CD produces no `core.rbf`.**

So with Terasic's flash untouched, no artifact loads a core. This is the outcome
[`de25-nano-overview.md`](../de25-nano-overview.md) §5.3 and
[`de25-boot-chain.md`](../de25-boot-chain.md) §7 row 15 anticipated. A second T1 finding binds
every core build: **the HPS IO hash depends on the Quartus version as well as the GHRD revision.**
The same project compiled with 26.3 produced a different hash.

**Nothing can show a picture before our fabric is in.** The ADV7513's control I2C is wired to FPGA
pins only, on a bus separate from the HPS's (*UM* §3.6, Table 3-7). Terasic ships HDMI as separate
fabric-only demos, such as `…/FPGA/HDMI_ASx4/` in the Resource Package. The factory design is
believed to leave HDMI dark **[I; #318 to confirm]**. ItsAlive's DE25 path expects a
MiSTer-framework fabric (the mailbox and `fbcfg` MAGICs behind the LW bridge), so it refuses on the
factory design with exit 15.

**Recovery from a bad flash is a PC step, not a dead board.** It needs the on-board USB-Blaster III
(USB-C), the free Quartus Programmer, and MSEL set to `111` and back
([`de25-boot-chain.md`](../de25-boot-chain.md) §1, §6). No extra hardware is needed.

**A self-built SPL is accepted.** The public DE25 port boots its own exFAT-aware SPL, merged into
its own `.jic`, and its unsigned local bitstreams load **[V there]**. On these boards neither the
SPL nor the bitstream needs a vendor signature.

## 2. Decision

**D1 — We ship our own QSPI image.** It holds SDM firmware, a phase-1 bitstream and an SPL. It and
every core are built from **one pinned Quartus version and one pinned base design**, so their HPS
IO hashes match. A core built against any other pin is refused before it is loaded (D2.9 item 2).

**D2 — The image is HPS-first** *(decided 2026-11-26 by B2)*. The QSPI holds the phase-1 (I/O
and HPS configuration) and the SPL, and no fabric logic. Every fabric design, including the
boot-time one, is a `core.rbf` with the phase-1's HPS IO hash. The alternative cannot run cores:

- **FPGA-first** (a full design configured at every reset, as the factory image is): `quartus_pfg`
  emits only full images for it, and the SDM refuses a full image after boot (`0xf0040000`). Such
  a base could never load a MiSTer core at runtime.
- **HPS-first** passed B2. The bench loaded 32 cores without a fatal result, 10 of them after warm
  reboots. The public port's warm-reboot SError, the reason it retired HPS-first
  ([`de25-reference-implementation.md`](../de25-reference-implementation.md)), did not
  reproduce.

The boot-time core (the base image's splash, [`de25-base-image.md`](../de25-base-image.md)) is
loaded by U-Boot or by the SPL; which one is D3's choice. An HPS-first image configures no
fabric by itself, even at power-on (§5), so that load step is always needed. Linux then
replaces the boot-time core with the Menu.

**D3 — The SPL becomes ours, in two steps.** The first image carries the GHRD's own SPL, to prove
the image shape. Our mainline U-Boot SPL, which the tree already compiles and never ships
(`board/mister/de25nano/uboot.fragment`), replaces it in a separate bench flash (B6). An SPL that
reads exFAT is not needed: the card keeps its FAT boot partition
([`de25-sdcard.md`](../de25-sdcard.md) §1).

**D4 — The first boot writes the image, once, in a short window.**

- **Before the exFAT expand.** The write runs at the very start of the first-boot install, while
  the user is still watching.
- **Only the sectors the image occupies.** The HPS-first phase-1 measured about 828 KiB on the
  bench (§5); with the SDM firmware and the SPL the written span is a few MiB, not the 16 MiB a
  `.jic` file pads to. B4 measures the window.
- **Read back and verify before the reboot.** The SDM reads QSPI only at reset, so the running
  system is unaffected until then. A mismatch is rewritten without rebooting.
- **Resumable.** If the flash already holds the image, the write is skipped. A reset before the
  verify re-runs it.
- **Signalled where it can be.** During the window the HPS LED (`hps_led0`, HPS GPIO, independent of
  the fabric) blinks a distinct pattern, and the serial console prints the warning. The README and
  the release notes say beforehand: the first boot takes N minutes, so do not unplug it.
- **The picture comes after the flash.** The installer reboots into our fabric, and ItsAlive covers
  the rest of the install on HDMI.

**D5 — The card carries its own recovery.** The FAT partition holds our `.jic`, the factory `.jic`
where its licence allows (B7), and a one-page JTAG recovery guide. Flashing from a PC stays the
documented alternative to D4.

**D6 — RSU if it fits.** If a power-loss-safe RSU layout with the factory image as fallback fits
the 16 MB flash (boot-chain §8.4), D4 writes the application slot instead. A cut mid-write then
boots the factory image instead of needing a PC.

## 3. Consequences

- **The QSPI becomes a versioned artifact,** with its own version, release notes and support
  question ("which `.jic` is on this board?"). The phase-1/core pairing check of D2.9 item 2 is
  mandatory, not optional.
- **The installer gains a flash writer and its tests.** Like the DE10 installer, it needs a
  power-cut harness, here around the QSPI window.
- **ItsAlive on the factory design is not pursued,** because the board offers no route to the
  ADV7513 without our fabric (§1). ItsAlive's DE25 path stands as written, for after the flash.
- **ADR 0029 D4's guards stay** until D4 here is implemented: the UBI-env line, and a DTS with no
  writable QSPI node. Implementing D4 replaces the DTS guard with one named writer, so the
  UBI-env guard still applies.

## 4. Bench gates (in order)

| # | Gate | Decides |
|---|---|---|
| B0 | The two-stage card (hidden `0x1c` p1, first-boot install) boots on the **factory** QSPI. This runs before any reflash, because after one the bench no longer runs the factory SPL | Posture-1 card layout; ADR 0029 D4's last check |
| B1 | The secure-boot fuse status (owner root key hash) | That an unsigned image is accepted on this board |
| B2 | #318's posture-2 plan: an HPS-first image with the GHRD SPL; `u-boot.itb` still loads; T1 at the U-Boot prompt; T3 from Linux (one load, then twenty, then a truncated RBF); plus about 10 warm reboots, each followed by an LW-bridge read, with a settle after each load | D1, D2 |
| B3 | Linux writes QSPI on our kernel. The SDM does not stream flash data: `QSPI_OPEN` (mailbox command 50) hands the Cadence QSPI controller to the HPS, Linux drives the flash with the mainline `cadence-quadspi` driver, and `QSPI_CLOSE` (51) hands it back (§5). That needs a small carried client of `stratix10-svc`, under ADR 0029's vendor-patch bar, plus the controller node and `CONFIG_SPI_CADENCE_QUADSPI`, enabled only together with that client. Measure the write time too | Whether D4 is possible at all, and how long its window is |
| B4 | The time to erase, write and verify the phase-1 sectors | The size of D4's window |
| B5 | Whether an RSU layout with a factory fallback fits 16 MB | D6 |
| B6 | Our mainline SPL in the image | D3 step 2 |
| B7 | The redistribution terms for a built `.jic`: Altera's SDM firmware, and Terasic's compiled GHRD, whose HDL headers forbid duplication outside Terasic boards. The repo therefore carries only our own HDL ([`de25-base-image.md`](../de25-base-image.md) §3) | What D5 may ship, and what a release may attach |

If B3 fails, D4 falls back to a one-time PC flash over JTAG, as the public port does, and D5's
guide becomes the install step instead of the recovery step.

## 5. Bench results

*#318, 2026-11-26.* The tester's own builds: Quartus 25.1.1 Build 125, Terasic System CD GHRD, the
GHRD's own SPL. Logs are on the bench, not in this repo.

| Gate | Result |
|---|---|
| B0 | **Pass (a)–(c).** On the untouched factory QSPI, master `20025ad`'s card boots. The factory SPL (`2025.01-gd0f8813fd6bf`) loads `u-boot.itb` from the hidden `0x1c` p1 as is. The installer runs and reboots exactly once. The second boot has `/media/fat` = the exFAT `MiSTer_Data`. (d), the Windows view, is not run: there is no Windows host on the bench |
| — | **The factory image is FPGA-first** (`HPS configuration order: HPS_AFTER_INIT_DONE`; `pfg -o hps=1` refuses it). The HDMI is dark under it: the monitor sees the hot-plug signal but no picture |
| B2 | **Pass.** An HPS-first pair from one `.sof`: phase-1 `hps.rbf` 847,872 B, `core.rbf` 1,581,056 B, the same HPS IO hash in both (`EA2C2695…`). Three clean default builds reproduced the factory hashes, so 25.1.1 Build 125 is deterministic on that bench. **T1:** `fpga load` at the U-Boot prompt says "FPGA reconfiguration OK!", the first runtime core load on a DE25. **T3:** a bench-only module calling `fpga_mgr_load()` loaded 20 cores in a row in one session, then one after each of 10 warm reboots, with every LW-bridge read stable and no SError |
| B2 note | After a `reboot -f`, every later load prints `S2F/LWS2F bridge enable: Timeout hdskack` (from BL31). It persists through later warm resets and clears only on a power cycle. Every such load still reached "operating" with working bridges. Record it; do not paper over it |
| B3 | **Desk result.** Reading the flash from Linux works as `QSPI_OPEN` → `cadence-quadspi` → `QSPI_CLOSE` (as U-Boot's `mailbox_s10.c` does). Never enable the controller without the handover: the SDM and the HPS must not both drive the flash. The factory image sets "QSPI ownership after HPS bring up: SDM", so the handover is required, not optional |
| D2 note | **An HPS-first image configures no fabric at power-on** *(2026-11-27, corrects the 2026-11-26 report)*. A cold boot leaves the fabric empty, LEDs dark, even with a core in QSPI; only an explicit `fpga load` (U-Boot or Linux) configures it. **A warm reboot keeps the loaded fabric**, and a power cycle clears it. That is also the `hdskack` latch's mechanism: every load after a warm reset reconfigures a live fabric |
| B5 | **Fits by size** *(2026-11-27)*. The factory image ends at `0x3450a1`, about 3.3 MiB of 16 MiB, and everything above is `0xFF`. Its layout is four 420 KiB firmware sections (CMF 1–4 at `0x0`/`0x40000`/`0x80000`/`0xC0000`, Altera-signed, "Support firmware upgrade: TRUE (Max 4)", not identical copies) plus a 1.3 MiB configuration payload at `0x200000`. That leaves about 12.7 MiB for an application slot. Not yet shown: that `quartus_pfg` builds an RSU layout from a factory `.sof` we rebuild (whose hashes match the factory's, per B2) plus our HPS-first image, and that the SPL handles it (B6) |

**The runtime loader is still open.** Mainline has no sysfs trigger for `fpga_mgr_load()`.
The bench module is option (b) of [`de25-fpga-reconfig.md`](../de25-fpga-reconfig.md) §3.2, and is
a bench artifact, not our loader.
