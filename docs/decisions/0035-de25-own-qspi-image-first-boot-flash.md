# ADR 0035 — DE25-Nano: our own QSPI image, written once by the first boot

**Status:** Proposed (2026-11-25). The owner agreed the direction on 2026-11-25. **Nothing in the
tree writes QSPI yet.** Bench gates B0–B7 (§4) confirm or reverse each part. *2026-11-26:* B0 and
B2 passed on #318's bench, with an HPS-first image built there rather than one of ours (§5), so
D2 is decided. *2026-11-28:* the owner confirmed self-flash as the user path
([ADR 0036](0036-de25-scope-and-base-generations.md) D4). An independent review amended D3 to D6,
added gates B2b and B8, and extended B3 and B4; each change is dated below.
**Amends:** [ADR 0029](0029-de25-implementation-path.md) **D4**. Posture 1 stays the shipping
state until this ADR's image exists. After that, the rule "nothing we ship writes QSPI" becomes
"exactly one thing writes QSPI: the first-boot installer, once, verified". Also amends
[`de25-nano-tasks.md`](../de25-nano-tasks.md) **D2.9** item 4: the matched pair is written by the
first boot, not over JTAG.
**Source of record:** test T1 on #318 (2026-11-25);
[`de25-boot-chain.md`](../de25-boot-chain.md) §4, §5 and §7;
the overview's §5.3 as it then stood, now in [`de25-history.md`](../de25-history.md).

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
the overview's §5.3 (now in [`de25-history.md`](../de25-history.md)) and
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
(USB-C) and the free Quartus Programmer
([`de25-boot-chain.md`](../de25-boot-chain.md) §1, §6). No extra hardware is needed. Whether MSEL
must move to `111` for the flash is **[U]**: Terasic's guide names no switch change, Altera's guides
ask for it on one kit and not on another, and #318's two flashes did not record it. The owner's
bench settles it ([`user/de25-recovery.md`](../user/de25-recovery.md)).

**A self-built SPL is accepted.** The public DE25 port boots its own exFAT-aware SPL, merged into
its own `.jic`, and its unsigned local bitstreams load **[V there]**. On these boards neither the
SPL nor the bitstream needs a vendor signature.

## 2. Decision

**D1 — We ship our own QSPI image.** It holds SDM firmware, a phase-1 bitstream and an SPL. It and
every core are built from **one pinned Quartus version and one pinned base design**, so their HPS
IO hashes match. A core built against any other pin is refused before it is loaded (D2.9 item 2).
*2026-11-28:* the pin has a name, a **base generation**, and a candidate
([ADR 0036](0036-de25-scope-and-base-generations.md) D3).

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
([`de25-sdcard.md`](../de25-sdcard.md) §1). *2026-11-28:* step 2 comes **before the first public
`.jic`**, not after it. A published `.jic` carries an SPL binary, and the GPL asks its publisher
for the complete source. Our own SPL is built by Buildroot, whose `legal-info` provides that; a
vendor's prebuilt SPL would leave us to reconstruct someone else's build.

**D4 — The first boot writes the image, once, in a short window.** *(Amended 2026-11-28; the
owner's decision that this is the user path is ADR 0036 D4.)*

- **The user is told first.** The release notes, the card's `README.txt` and
  [`user/de25-first-boot.md`](../user/de25-first-boot.md) say before the first boot: this card
  rewrites the board's flash once, the board then no longer boots cards that expect the factory
  flash, how long it takes, not to unplug it, and what the JTAG recovery is.
- **Only a board and a flash it recognises.** The installer writes only if the JTAG ID, the
  flash's JEDEC ID and the current flash contents are on a known list (the factory images, and
  our own older ones). Anything else is left alone, and the user is pointed at the JTAG guide.
- **Before the exFAT expand.** The write runs at the very start of the first-boot install.
- **The first write is made with the SDM owning the flash.** The factory image reports "QSPI
  ownership after HPS bring up: SDM" (§5), so the handover of gate B3 is needed for this write
  whatever our own image later sets.
- **Written in an order that keeps the exposed window short.** Everything new goes into the
  blank part of the flash first and is verified there; the region the SDM starts from is
  rewritten last. The HPS-first phase-1 measured about 828 KiB on the bench (§5); the layout
  that makes this order possible, and the window it leaves, are gate B4.
- **Read back and verify before any reset.** The SDM reads QSPI only when it starts, so the
  running system is unaffected until then. A mismatch is rewritten without rebooting.
- **Resumable.** If the flash already holds the image, the write is skipped. A reset before the
  verify re-runs it.
- **Signalled where it can be.** During the window the HPS LED (`hps_led0`, HPS GPIO, independent of
  the fabric) blinks a distinct pattern, and the serial console prints the warning. HDMI is dark:
  the factory fabric cannot drive it (§1).
- **The picture comes after the new image is running, and a reboot may not be enough.** A warm
  reboot does not make the SDM start again: #318 saw the fabric survive one (§5), and Altera
  describes an HPS cold reset as reloading only the first-stage loader **[S, sibling families]**.
  So after the write the old firmware and the factory phase-1 may still be running, and the
  boot core would be refused until a power cycle. Gate B8 finds out. Until it passes, the plan
  is that the installer asks for a power cycle (LED pattern, serial), and ItsAlive covers the
  rest of the install on HDMI after it.
- **Proven by cutting the power.** Before the first release that writes the flash: a power-cut
  campaign on the owner's board, each cut recovered by the documented JTAG procedure.

**D5 — The user can always find the recovery.** *(Amended 2026-11-28.)* The card's visible
volume carries a short guide, the URL of
[`user/de25-recovery.md`](../user/de25-recovery.md) and the SHA-256 of each `.jic`. The `.jic`
files themselves are release assets (ours) or Terasic's own download (the factory one), not
files on the card: p1 is hidden from Windows, p2 is 16 MiB until the install has run, and a
`.jic` is 16 MiB ([`de25-sdcard.md`](../de25-sdcard.md) §1). Flashing from a PC stays the
documented recovery, and the bench tool.

**D6 — RSU for later updates, if it fits.** *(Amended 2026-11-28.)* RSU does **not** protect the
first write. The factory flash is a standard layout, not an RSU one (§5, B5), and turning it
into an RSU layout means rewriting the region the SDM starts from; no fallback exists while
that happens. What RSU buys is every write after that: a cut mid-update then boots the other
slot instead of needing a PC. It is also how a second base generation could live beside the
first ([`de25-quartus.md`](../de25-quartus.md) §7). Gate B5.

## 3. Consequences

- **The QSPI becomes a versioned artifact,** with its own version, release notes and support
  question ("which `.jic` is on this board?"). The phase-1/core pairing check of D2.9 item 2 is
  mandatory, not optional.
- **The installer gains a flash writer and its tests.** Like the DE10 installer, it needs a
  power-cut harness, here around the QSPI window.
- **ItsAlive on the factory design is not pursued,** because the board offers no route to the
  ADV7513 without our fabric (§1). ItsAlive's DE25 path stands as written, for after the flash.
- **Nothing we ship touches fuses or keys.** No installer, tool or script sends a fuse, key or
  owner-root-key command to the SDM, and no image is signed or encrypted. A partly written flash
  is recoverable over JTAG; a programmed fuse is not, and a locked board would also add duties
  under the GPL-3 our HDL carries.
- **ADR 0029 D4's guards stay** until D4 here is implemented: the UBI-env line, and a DTS with no
  writable QSPI node. Implementing D4 replaces the DTS guard with one named writer, so the
  UBI-env guard still applies.

## 4. Bench gates (in order)

| # | Gate | Decides |
|---|---|---|
| B0 | The two-stage card (hidden `0x1c` p1, first-boot install) boots on the **factory** QSPI. This runs before any reflash, because after one the bench no longer runs the factory SPL | Posture-1 card layout; ADR 0029 D4's last check |
| B1 | The secure-boot fuse status (owner root key hash) | That an unsigned image is accepted on this board |
| B2 | #318's posture-2 plan: an HPS-first image with the GHRD SPL; `u-boot.itb` still loads; T1 at the U-Boot prompt; T3 from Linux (one load, then twenty, then a truncated RBF); plus about 10 warm reboots, each followed by an LW-bridge read, with a settle after each load | D1, D2 |
| B2b | *(added 2026-11-28)* The HPS IO hash holds across separate compiles: (1) the unmodified base reproduces the published hash; (2) the base plus `de25_hdmi`, and a design with clearly different fabric, keep it and load over one phase-1 | D1's premise that cores can be built independently ([ADR 0036](0036-de25-scope-and-base-generations.md) D3) |
| B3 | Linux writes QSPI on our kernel. The SDM does not stream flash data: `QSPI_OPEN` (mailbox command 50) hands the Cadence QSPI controller to the HPS, Linux drives the flash with the mainline `cadence-quadspi` driver, and `QSPI_CLOSE` (51) hands it back (§5). That needs a small carried client of `stratix10-svc`, under ADR 0029's vendor-patch bar, plus the controller node and `CONFIG_SPI_CADENCE_QUADSPI`, enabled only together with that client. Measure the write time too. *2026-11-28:* three accounts of the handover disagree and B3 must reconcile them: this row names `QSPI_OPEN` and `QSPI_CLOSE`; #318's trace adds `QSPI_DIRECT` (59); [`de25-reference-implementation.md`](../de25-reference-implementation.md) §3 records the direct controller path hanging and a chip-select re-assert before every write. An alternative to the carried client, to weigh: U-Boot does the handover for the installer boot only and enables the controller node for Linux, as Altera's environment does (`linux_qspi_enable`); no kernel carry, but U-Boot's QSPI audit is relaxed for that boot | Whether D4 is possible at all, and how long its window is |
| B4 | The time to erase, write and verify the phase-1 sectors. *2026-11-28:* and the write order: the standard and RSU layouts from `quartus_pfg`'s map files, which regions can be written into blank flash first, and the measured window in which a cut needs JTAG. Timing runs first on scratch data in the blank region above the image, which touches no boot data | The size of D4's window |
| B5 | Whether an RSU layout fits 16 MB and builds, with two slots | D6: later updates, and a second base generation |
| B6 | Our mainline SPL in the image. *2026-11-28:* before the first public `.jic` (D3); re-run B0's checks against it | D3 step 2 |
| B7 | The redistribution terms for a built `.jic`: Altera's SDM firmware, and Terasic's compiled GHRD, whose HDL headers forbid duplication outside Terasic boards. The repo therefore carries only our own HDL ([`de25-base-image.md`](../de25-base-image.md) §3) | What D5 may ship, and what a release may attach |
| B8 | *(added 2026-11-28)* The reset after the write. On the factory image, rewrite the flash, then `reboot`: which firmware, phase-1 and SPL run afterwards, and does the boot core load? Then the same after a power cycle | Whether D4 ends in a reboot or asks the user for a power cycle |

If B3 fails, D4 falls back to a one-time PC flash over JTAG, as the public port does, and D5's
guide becomes the install step instead of the recovery step. That is the only case in which
users are asked to use JTAG to install (ADR 0036 D4).

## 5. Bench results

*#318, 2026-11-26.* The tester's own builds: Quartus 25.1.1 Build 125, Terasic System CD GHRD, the
GHRD's own SPL. Logs are on the bench, not in this repo.

| Gate | Result |
|---|---|
| B0 | **Pass (a)–(c).** On the untouched factory QSPI, master `20025ad`'s card boots. The factory SPL (`2025.01-gd0f8813fd6bf`) loads `u-boot.itb` from the hidden `0x1c` p1 as is. The installer runs and reboots exactly once. The second boot has `/media/fat` = the exFAT `MiSTer_Data`. (d), the Windows view, is not run: there is no Windows host on the bench |
| — | **The factory image is FPGA-first** (`HPS configuration order: HPS_AFTER_INIT_DONE`; `pfg -o hps=1` refuses it). The HDMI is dark under it: the monitor sees the hot-plug signal but no picture |
| B2 | **Pass.** An HPS-first pair from one `.sof`: phase-1 `hps.rbf` 847,872 B, `core.rbf` 1,581,056 B, the same HPS IO hash in both (`EA2C2695…`). Three clean default builds reproduced the factory hashes, so 25.1.1 Build 125 is deterministic on that bench. **T1:** `fpga load` at the U-Boot prompt says "FPGA reconfiguration OK!", the first runtime core load on a DE25. **T3:** a bench-only module calling `fpga_mgr_load()` loaded 20 cores in a row in one session, then one after each of 10 warm reboots, with every LW-bridge read stable and no SError |
| B2 note | After a `reboot -f`, every later load prints `S2F/LWS2F bridge enable: Timeout hdskack` (from BL31). It persists through later warm resets and clears only on a power cycle. Every such load still reached "operating" with working bridges. Record it; do not paper over it |
| B2b | **Test 1 passes** *(2026-11-28, our build host)*. Altera's baseline at tag `QPDS26.3_REL_BASELINE_PR`, unmodified, compiled with Quartus 26.3.0 Build 114, gives HPS IO hash `DF9589F2…` and IO hash `9E82C9A1…`, identical to Altera's published `ghrd.core.rbf` ([`de25-quartus.md`](../de25-quartus.md) §5). **Test 2 is not run** |
| B3 | **Desk result.** Reading the flash from Linux works as `QSPI_OPEN` → `cadence-quadspi` → `QSPI_CLOSE` (as U-Boot's `mailbox_s10.c` does). Never enable the controller without the handover: the SDM and the HPS must not both drive the flash. The factory image sets "QSPI ownership after HPS bring up: SDM", so the handover is required, not optional |
| D2 note | **An HPS-first image configures no fabric at power-on** *(2026-11-27, corrects the 2026-11-26 report)*. A cold boot leaves the fabric empty, LEDs dark, even with a core in QSPI; only an explicit `fpga load` (U-Boot or Linux) configures it. **A warm reboot keeps the loaded fabric**, and a power cycle clears it. That is also the `hdskack` latch's mechanism: every load after a warm reset reconfigures a live fabric |
| B5 | **Fits by size** *(2026-11-27)*. The factory image ends at `0x3450a1`, about 3.3 MiB of 16 MiB, and everything above is `0xFF`. Its layout is four 420 KiB firmware sections (CMF 1–4, Altera-signed, "Support firmware upgrade: TRUE (Max 4)", not identical copies) at byte offsets `0x0`/`0x80000`/`0x100000`/`0x180000`, plus a 1.3 MiB configuration payload at `0x200000`. (`quartus_pfg -i` prints the four sections at `0x0`/`0x40000`/`0x80000`/`0xC0000`; those are its own section offsets, not byte addresses in the flash.) That leaves about 12.7 MiB. It is a standard layout, not an RSU one, so RSU cannot protect the write that replaces it (D6). Not yet shown: that `quartus_pfg` builds an RSU layout from a factory `.sof` we rebuild (whose hashes match the factory's, per B2) plus our HPS-first image, and that the SPL handles it (B6) |

**The runtime loader is still open.** Mainline has no sysfs trigger for `fpga_mgr_load()`.
The bench module is option (b) of [`de25-fpga-reconfig.md`](../de25-fpga-reconfig.md) §3.2, and is
a bench artifact, not our loader. *2026-11-27:* ours is packaged as `package/de25-fpga-load`; it
has not run on a board ([`de25-nano-tasks.md`](../de25-nano-tasks.md) D2.11).
