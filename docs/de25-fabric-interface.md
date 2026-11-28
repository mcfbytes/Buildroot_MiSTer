# DE25-Nano: the fabric interface for a host program

**What this is.** Everything a MiSTer-style host program (a Main, a test tool) needs to load
cores into the DE25-Nano's fabric and talk to them, in one place. It states what is measured,
what is planned and what is still open, and links to the detailed records instead of repeating
them. **Status 2026-11-27.**

**Evidence tags:** **[V]** verified on DE25 hardware (#318's bench unless noted); **[S]**
verified in simulation or by building; **[P]** planned, not built; **[U]** unknown.

## 1. The model in one paragraph

Agilex 5 boots from its QSPI flash, never from the SD card. The flash holds an **HPS-first
phase-1**: the I/O and processor setup plus the SPL, and no fabric logic. Every fabric design
is a separate **`core.rbf`**, and the SDM accepts one only if it carries the **same HPS IO
hash** as the phase-1. That hash depends on the base design **and the Quartus version**. At
power-on the fabric is empty. U-Boot loads a boot core, and Linux replaces it with any other
core at runtime, as often as needed. A warm reboot keeps whatever core is loaded; a power cycle
clears it. Records: [ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md) §5,
[`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §12.

## 2. Which cores load

| Phase-1 in the flash | What loads at runtime |
|---|---|
| Terasic's factory image (FPGA-first, every board as shipped) | **nothing**: a full image is refused (`0xf0040000`), and no HPS-first core matches its hash **[V]** |
| An HPS-first image (ours, or Altera's public `ghrd.hps.jic`) | any `core.rbf` compiled against the **same** base design and Quartus version **[V]** |

So every core a host program offers must be built against one pinned base. A core built
against another base is refused by the SDM. A host program should check the pairing before
asking (§4), so the user sees "built for a different base image", not a bare SDM status.

## 3. Loading a core from Linux

The image ships `de25-fpga-load`, a small kernel module **[S: built, not yet run on a board]**:

```
modprobe de25-fpga-load                                # not autoloaded
cp menu.core.rbf /lib/firmware/                        # bare file names only, no '/'
echo menu.core.rbf > /sys/class/misc/de25-fpga-load/load
cat /sys/class/fpga_manager/fpga0/state                # "operating" after success
```

- **The write is synchronous.** It returns when the SDM reports done, with the load's error if
  any: `-EINVAL` for a bad name, `-EBUSY` while another load runs, `-ENODEV` without an FPGA
  manager, and the FPGA manager's code for an SDM refusal. It waits up to 30 s.
- **dmesg** gets one line per load: `<name>: loaded in N ms`, or `load failed (err)`.
- **Time:** about 2.1 s for a 1.58 MB core, start to "operating", through the same kernel path
  **[V: the bench's equivalent module]**.
- **Root only.** Source: `package/de25-fpga-load/src/de25-fpga-load.c`.

## 4. Rules around a load

| Rule | Why | Tag |
|---|---|---|
| **Never touch a bridge window while the fabric is empty or being loaded.** That includes every `/dev/mister/*` map into the LW or H2F windows | a read of an unconfigured fabric is a fatal asynchronous SError | [V on the public DE25 port; standing rule] |
| **Stop all HPS→fabric traffic before a load, and stop the fabric's own DDR masters before a load or a reboot.** For the base design's framebuffer: write `CTRL` 0, wait for `STATUS` bit 2 (idle). Do not rely on reconfiguration to stop a master | a load turns the F2SDRAM bridge off with no drain, and a warm reboot keeps the fabric running while the HPS resets DDR; a burst abandoned mid-flight may hang the HPS until a power cycle | [P: never tried with a master active; the full quiesce contract is open, D2.11] |
| **After a failed or refused load, treat the bridges as off** until a later load succeeds | the secure firmware re-enables the bridges only after a successful load; a bridge access before then is an SError | [S: from the firmware source] |
| **Settle after a load before the first bridge access** | the public DE25 port needed about 3 s before and 5 s after; our bench saw no failure with a plain settle, and the figures for our image are not measured | [U for our image] |
| **Check the HPS IO hash before loading** | a mismatched core is refused by the SDM with a cryptic status | [P: D2.9 item 2, D2.11] |
| **After a warm reboot, expect `S2F/LWS2F bridge enable: Timeout hdskack` from BL31 on each load** until the next power cycle | every load after a warm reset reconfigures a running fabric; every such load still reached "operating" in 32 bench loads | [V], to be explained |
| **One writer.** Only one program loads cores and owns the bridges at a time | two writers on the same registers corrupt each other | standing rule |

## 5. Address map (HPS side)

| Window | Base | Size | Linux | Notes |
|---|---|---|---|---|
| LW bridge (LWH2F) | `0x2000_0000` | 2 MiB described | `/dev/mister/lw-bridge` | the fabric's register space; Altera's baseline puts its peripherals here **[V: the bench's reads]** |
| H2F bridge | `0x4000_0000` | 1 GiB described | `/dev/mister/h2f-bridge` | the windows above 4 GiB are not described |
| HPS DDR | `0x8000_0000` | 1 GiB | Linux below `mem=479M` | the reserved tiles above it: [`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7 |
| Framebuffer | `0xA000_0000` (image at `+0x1000`) | 32 MiB tile | `/dev/fb0` (`MiSTer_fb`) | §6 |
| Fabric DDR aperture | `0xA000_0000` | 512 MiB | `/dev/mister/ddr-aperture` | core DDRAM; a core's DE10 address plus `0x8000_0000` |
| OCRAM | `0x0` | 508 KiB | `/dev/mister/ocram` | boot stages only; nothing at runtime |

The full node list, UIO names and mapping rules are in
[`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §5 and §7. Agilex 5 has no
Cyclone V-style GPO/GPI registers in the HPS FPGA manager. A DE25 base design must provide
them as fabric registers behind the LW bridge **[P: not designed]**.

## 6. Video

The base design's `de25_hdmi` block drives HDMI at 1080p60. It shows a boot splash until
software enables the framebuffer, then scans out `/dev/fb0`'s memory, scaled by a whole factor
and centred **[S]**. Its register map, the `MiSTer_fb` mode it must agree with, and the timing
are in [`de25-base-image.md`](de25-base-image.md) §6. Where the register block sits on the LW
bridge is fixed when it is wired into the base design **[P]**. The HDMI transmitter is reachable
only through the fabric, so nothing can show a picture before a core with this block is loaded.

## 7. Flash ownership and updates

| Phase-1 | QSPI after boot | Consequence |
|---|---|---|
| Terasic factory | SDM-owned | Linux can reach the flash only through the SDM's `QSPI_OPEN`/`QSPI_CLOSE` handover |
| Altera's baseline (and ours, if built from it) | HPS-owned (`QSPI_OWNERSHIP HPS`) | Linux can drive the flash with mainline `cadence-quadspi`, as Altera's U-Boot sets up |

A host program should never write the flash. The first-boot installer is the one planned writer
([ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md) D4).

## 8. Open items a host program depends on

| Item | Where it is tracked |
|---|---|
| The quiesce and settle contract around a load | D2.11 in [`de25-nano-tasks.md`](de25-nano-tasks.md) |
| The HPS-IO-hash pairing check (reading a core's hash, and the running phase-1's) | D2.9 item 2, D2.11 |
| GPO/GPI registers (the Cyclone V HPS-to-fabric control words) on Agilex 5 | not designed |
| The video register block's LW offset, and a vsync interrupt line | [`de25-base-image.md`](de25-base-image.md) §6–§7 |
| The `hdskack` messages after a warm reset | ADR 0035 §5 |
