# ADR 0035 — DE25-Nano: our own QSPI image, written once by the first boot

**Status:** Proposed (2026-11-25). The owner agreed the direction on 2026-11-25. **No QSPI image
exists yet, and nothing in the tree writes QSPI.** Bench gates B0–B7 (§4) confirm or reverse each
part.
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

**D2 — The image's fabric posture is open.** Two shapes are possible:

- **HPS-first:** the fabric stays empty until Linux loads the Menu core.
- **A full design configured at every reset**, with the Menu in it.

The public port retired HPS-first after a fatal SError on the first fabric read after warm reboots
([`de25-reference-implementation.md`](../de25-reference-implementation.md)). Gate B2 decides.

**D3 — The SPL becomes ours, in two steps.** The first image carries the GHRD's own SPL, to prove
the image shape. Our mainline U-Boot SPL, which the tree already compiles and never ships
(`board/mister/de25nano/uboot.fragment`), replaces it in a separate bench flash (B6). An SPL that
reads exFAT is not needed: the card keeps its FAT boot partition
([`de25-sdcard.md`](../de25-sdcard.md) §1).

**D4 — The first boot writes the image, once, in a short window.**

- **Before the exFAT expand.** The write runs at the very start of the first-boot install, while
  the user is still watching.
- **Only the sectors the image occupies.** The phase-1 payload measured about 2.9 MiB, so the window
  should be seconds to tens of seconds (B4 measures it).
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
| B3 | Linux writes QSPI through the SDM mailbox on our kernel | Whether D4 is possible at all |
| B4 | The time to erase, write and verify the phase-1 sectors | The size of D4's window |
| B5 | Whether an RSU layout with a factory fallback fits 16 MB | D6 |
| B6 | Our mainline SPL in the image | D3 step 2 |
| B7 | The redistribution terms for the SDM firmware inside a `.jic` | What D5 may ship |

If B3 fails, D4 falls back to a one-time PC flash over JTAG, as the public port does, and D5's
guide becomes the install step instead of the recovery step.
