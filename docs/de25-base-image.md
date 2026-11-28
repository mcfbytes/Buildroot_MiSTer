# DE25-Nano base QSPI image — the GHRD with an HDMI splash

**Status:** first step built and simulated. Quartus compiles for this device with the licence; **the base image itself has never been compiled or run on a board.**
This is the image [ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md) D1 calls
"our own QSPI image", in its first and smallest form: Terasic's factory design with a picture.
Sources: `fpga/de25-base/`.

## 1. What it is

Terasic's GHRD (`Demonstration/SoC_FPGA/GHRD` in the DE25-Nano Resource Package) is the design
in every board's factory QSPI. It configures the HPS, its DDR and the bridges, but its top level
declares the HDMI pins and drives none of them, so a factory board's HDMI is dark. The ADV7513's
control I2C is on FPGA pins only (*UM* §3.6, Table 3-7), so Linux cannot reach it either.

The base image is that GHRD plus one block, `de25_hdmi_splash`:

| Module | Does |
|---|---|
| `de25_vtiming` | CEA-861 1920×1080p60 timing (VIC 16) at 148.5 MHz, positive syncs |
| `de25_splash` | a 128×32 1-bit logo (`tools/gen-logo.py`) scaled 8× and centred, a bar under it, a dark background |
| `de25_adv7513_init` | an open-drain I2C master that writes 43 ADV7513 registers once, 200 ms after reset |
| `de25_hdmi_splash` | the wrapper the GHRD top instantiates |

The register table follows Main_MiSTer's `video.cpp` init for RGB 4:4:4 input and HDMI output,
with two changes: `0x17 = 0x02`, because our syncs are already positive, and `0xD6 = 0xC0`
(HPD always high), so the init needs no hot-plug wait.

The image is **HPS-first** (`HPS_INITIALIZATION "HPS FIRST"`); the factory GHRD is FPGA-first.
Only an HPS-first phase-1 accepts a core at runtime. An FPGA-first design yields only full
images, which the SDM refuses after boot (`0xf0040000`), so it could never load a MiSTer core.
Under the factory image the HPS IO hash is the factory's, so no core of ours matches it either.
#318 proved the HPS-first pair on the bench (ADR 0035 B2): it loaded 32 cores, including after
10 warm reboots, with no SError.

The build therefore writes a **pair** with one HPS IO hash, and refuses to finish if the two
hashes differ:

- **`de25_base.jic`**, the QSPI image: the SDM firmware, the phase-1 (I/O and HPS
  configuration, about 830 KiB on the bench build) and the SPL. It holds no fabric logic.
- **`de25_base.core.rbf`**, the GHRD plus the splash. Something has to load it at boot, before
  Linux: U-Boot (`fpga load`) or the SPL. The `.jic` alone leaves the fabric empty at power-on,
  even with a core in QSPI (#318, 2026-11-27); a warm reboot keeps whatever was loaded. That choice is part of D3. The logo then shows from
  about U-Boot time, not from reset, and Linux later replaces it with the Menu core.

## 2. What it is for

1. **The flash window** of ADR 0035 D4. After the first boot writes this image and reboots, every
   later boot shows the logo as soon as the boot core is loaded.
2. **A known-good fabric to fall back to.** It is the factory design plus a block that only
   drives otherwise-unused pins, so it changes nothing the HPS depends on.
3. **The base the MiSTer framework grows from.** Next steps, not built:
   - a framebuffer reader on the F2SDRAM port, reading HPS DDR at a reserved address;
   - an `fbcfg` mailbox behind the LW bridge, compatible with what ItsAlive's DE25 path expects
     (the MAGIC check and the scaler base write), so `itsalive` can draw installer progress
     unchanged;
   - the Menu core, loaded at runtime over the same phase-1 (#318 T3 did it through
     `fpga_mgr_load()`; our loader is `de25-fpga-reconfig.md` §3.2's open choice).

## 3. Licensing: why the repo holds no Terasic HDL

Terasic's HDL headers (the GHRD top, and the HDMI_TX demo's VPG and I2C files) permit use on
Terasic boards and prohibit duplication or modification otherwise. So `fpga/de25-base/` carries
only our own files, GPL-3.0-or-later. The build takes the GHRD project and the demo's
`AV_PLL.ip` (the 148.5 MHz pixel PLL) from the user's own copy of the Resource Package and merges
our block in at build time. A built `.jic` is a separate question: it contains Terasic's
compiled design and Altera's SDM firmware, and gate B7 must answer it before any `.jic` is
published.

## 4. Building it

Simulation (no Quartus needed):

```
fpga/de25-base/sim/run-sim.sh
```

It runs Icarus Verilog: the host's `iverilog`, or a container image that has it, named by
`DE25_SIM_IMAGE`. It checks one full
frame: 2,073,600 active pixels, 1125 lines, a 5-line vsync, exactly the logo's lit-pixel count,
and black blanking. It also checks the init against an I2C slave model: 43 writes to 0x39, all
acknowledged, no framing errors. **Both pass.**

The image (Quartus Prime Pro, **pinned 25.3.1**):

```
QUARTUS_LICENSE=<licence .dat> fpga/de25-base/tools/quartus-run.sh \
    /w/fpga/de25-base/tools/build-base-image.sh <Resource Package .zip> <out dir>
```

Run it from the repo root: `tools/quartus-run.sh` mounts the current directory at `/w`. The script:

1. unpacks the package and copies the GHRD project and `AV_PLL.ip`;
2. checks that the GHRD top has every name the merge relies on and drives no `HDMI_TX_*` pin;
3. inserts the PLL and `de25_hdmi_splash` before `endmodule` and adds our files to the `.qsf`;
4. runs `quartus_sh --flow compile`, then `quartus_pfg -c … -o hps_path=<SPL hex>` (the GHRD's
   own SPL by default; `SPL_HEX` for ours, ADR 0035 D3), then the `.jic` with `-o hps=1` and
   Terasic's own options (`device=MT25QU128`, `flash_loader=A5EB013BB23B`, `mode=ASX4`), and the
   `.core.rbf` with `-o hps=1`;
5. compares the HPS IO hash that `quartus_pfg -i` reports for both halves, then prints it and the
   SHA-256s.

**The container.** The DE10's Quartus container (`theypsilon/quartus-lite-c5:17.0.2`) cannot
build this: Agilex 5 needs Quartus Prime **Pro**. `tools/quartus-run.sh` runs Altera's own image,
`alterafpga/quartus-pro:25.3.1-patch1.02-agilex5` (Docker Hub, 17.5 GB). It is 25.3.1 Build 100
with patch 1.02, the patch Altera requires on every 25.3.1 install, and only Agilex 5 devices.
The wrapper makes four changes, all needed **[V 2026-11-25, on this tree's build host]**:

- **A stub `libudev.so.1` mounted over the image's** (`tools/udev-stub.c`, built on first use
  into `.quartus-run/`). Without it, `quartus_syn` aborts with `realloc(): invalid pointer` in
  `udev_enumerate_scan_devices`. The caller is FlexLM's host-ID probe (`sys_cpt`, which
  `dlopen`s libudev), so every compile hits it. Preloading the real library only moves the crash:
  it passes while there is no licence and aborts again once a licence makes FlexLM probe more
  host-ID types. The stub's `udev_new()` returns NULL, the probe skips its device scan, and the
  MAC-based licence still matches. A full compile of a test design for `A5EB013BB23BE4SR1`
  passes this way **[V 2026-11-27]**.
- **A fixed `--mac-address`** (`QUARTUS_MAC`, default `02:de:25:00:00:01`). The licence is
  bound to a NIC ID, and a container gets a new MAC each run.
- **The caller's uid,** so the outputs are not owned by root.
- **`HOME=/tmp`,** because that uid has no home directory in the image, and Quartus writes
  its settings under `$HOME`.

The stub makes udev report no devices, so the wrapper is for compiling only. `quartus_pgm`
through it would find no USB-Blaster.

**The licence.** Without one, synthesis stops with `Error (19286): No license for family
Agilex 5`. Altera issues a no-cost licence for Agilex 5 E-series, which the board's `A5EB013`
is, from its Self-Service Licensing Center. Request **SW-AGILEX-5E**, type FIXED, for the
NIC ID `02de25000001` (the default MAC, without colons), or for your own `QUARTUS_MAC`. It
carries the feature `quartus_agilex5e` and lasts a year. Pass it as `QUARTUS_LICENSE`; it is
never committed.

**Why 25.3.1 and not the factory's 25.1.1:** we do not need to match the factory's HPS IO hash,
because we replace the factory image. What matters is that the image and every core share one
Quartus version (T1, #318), and Altera's container images start at 25.3. The bench's 25.1.1
Build 125 compiles were deterministic: three clean builds printed the same hashes. So 25.1.1 is
not ruled out; it is just not packaged. Two clean compiles must print the same hash on our pin
too.

## 5. Bench checks it needs (ADR 0035 B2)

- The logo appears once the boot core is loaded, and stays until Linux loads the Menu core.
- The ADV7513 ACKs, which shows the I2C pins and pull-ups. A NACK leaves `init_nack` set, which
  is visible in SignalTap.
- Pixel clock phase: `HDMI_TX_CLK` is the inverted pixel clock. If the picture sparkles, adjust
  `0xBA` (the input clock delay) before touching the logic.
- `HDMI_TX_CLK`'s I/O standard: the GHRD `.qsf` sets "1.1-V", while *UM* Table 3-13 lists the
  HDMI pins at 3.3 V. Check the compile's pin report against the schematic.
- Linux and our `u-boot.itb` boot exactly as on the factory image (T2's checks).

## 6. The framebuffer (`de25_fb_reader`, `de25_fb_regs`, `de25_hdmi`)

**Status 2026-11-27:** written and simulated; not yet wired into a base design (that needs the
26.3 toolchain, §7) and never run on a board.

`de25_hdmi` is the one block a base design instantiates. It drives the ADV7513 at 1080p60 and
shows one of two sources:

- **the splash** (§1), from reset until software enables the framebuffer;
- **a linear framebuffer in HPS DDR**, read over the F2SDRAM port (AXI4, 256-bit), scaled by
  the largest whole factor up to 4× that fits 1920×1080, centred, with a black border.

| Port | Clock | What it is |
|---|---|---|
| `s_*` | `clk` (the LW bridge's) | Avalon-MM slave, 16 × 32-bit words with byte enables, fixed read latency 1, no wait states: declare it so in Platform Designer |
| `m_ar*`, `m_r*` | `clk` (the F2SDRAM port's) | AXI4 read master: 256 B bursts (`arlen` 7, `arsize` 5, INCR), ID 0, `arcache` `0011`. No write channels: the base design ties them off |
| `HDMI_*` | `pclk`, 148.5 MHz | the board pins (*UM* Table 3-13, §7) |
| I2C init | `clk` | `CLK_HZ` sets the 100 kHz divider and the 200 ms power-on wait |
| `rst_n`, `pll_locked` | any | reset, synchronised inside to each clock; the pixel side also waits for the PLL to lock |

`rtl/de25_hdmi.sdc` cuts the timing paths of the block's clock crossings; the base design adds
it after its own clock constraints.

### 6.1 Register map (word offsets from the block's base on the LW bridge)

| Word | Name | Access | Reset | Meaning |
|---|---|---|---|---|
| 0 | `MAGIC` | RO | `0xDE25FB5A` | identifies the block |
| 1 | `VERSION` | RO | `3` | 2: byte enables, `STATUS` bits 1, 7, 8; 3: bits 2 and 3 |
| 2 | `CTRL` | RW | `0` | bit 0: show the framebuffer (else the splash) |
| 3 | `BASE_LO` | RW | `0xA0001000` | framebuffer address bits 31:8; bits 7:0 read as 0 (256-byte aligned) |
| 4 | `BASE_HI` | RW | `0` | address bits 39:32 |
| 5 | `WIDTH` | RW | `640` | pixels, 1–1920 |
| 6 | `HEIGHT` | RW | `480` | lines, 1–1080 |
| 7 | `STRIDE` | RW | `2560` | bytes per line; bits 7:0 read as 0. Must be ≥ `WIDTH`×4 |
| 9 | `STATUS` | RO, W1C bits 1:0 | | 31:16 frame count; 8 ADV7513 init NACKed; 7 ADV7513 init done; 6:4 scale in use; 3 settings accepted (the reader is fetching); 2 idle (off at the last frame boundary and no fetch running); 1 sticky read error (a response other than OKAY); 0 sticky underrun. Write 1 to clear a sticky bit; a new event in the same cycle wins |

The reset values are `MiSTer_fb`'s own defaults: image at its region's `+0x1000`, 640×480,
XRGB8888 (byte 0 blue, byte 2 red), stride rounded up to 256 B. So the driver's default mode
shows correctly once `CTRL` is set. Another mode is two writes that must agree:
`/sys/module/MiSTer_fb/parameters/mode` (`format rb width height stride`) and these registers.
It shows XRGB8888 only. An invalid setting shows black, not garbage: a zero size, a size over
1080p, a stride under `WIDTH`×4, or a region (`BASE` to `BASE` + `HEIGHT`×`STRIDE` + 256) that
leaves HPS DDR (`0x8000_0000`–`0xBFFF_FFFF`; the reader's `WIN_LO`/`WIN_HI` parameters). The
reader cannot write; this bound keeps it from reading anything but DDR. With `CTRL` set, the
framebuffer owns the screen whether or not its settings are accepted, so a rejected setting is
black, never the splash; `STATUS` bit 3 tells the two apart.

**Rules for software.**

- **Change a mode with `CTRL` 0.** The settings are several writes, and a frame boundary between
  two of them would show one frame of a half-written mode. Write `CTRL` 0, then the settings,
  then `CTRL` 1.
- **Stop the reader before a core load or a reboot.** With `CTRL` 1 the reader is a live master
  on the F2SDRAM port, reading every line. A load reconfigures the fabric and turns that port's
  bridge off with no drain, and a warm reboot keeps the fabric running while the HPS resets DDR
  and the bridges. Neither has been tried with a master active, and an abandoned burst may hang
  the HPS until a power cycle. Write `CTRL` 0 and wait for `STATUS` bit 2 (idle), at most two
  frames (34 ms), then load or reboot.

### 6.2 How it works

- **Settings change only at a frame boundary.** At each vsync the pixel side asks, and the
  system side snapshots the registers, works out the scale and the offsets, and answers. The
  pixel side takes the copy once the answer arrives. `CTRL` takes effect the same way, so the
  switch between splash and framebuffer happens in vertical blanking, never mid-frame.
- **Two lines ahead.** At the hsync after line *y*, the pixel side asks for line *y*+2's source
  row, into the half of the two-line, 256-bit buffer that line *y* has just freed. Each fetch
  therefore has a full line, 14.8 µs, before it is shown; a 1920-pixel row is 240 beats, about
  2.4 µs at 100 MHz without stalls. A request that arrives while the previous fetch still runs
  is dropped, not restarted (the AR channel stays stable and the fetch stays coherent): its
  line shows stale pixels, and the sticky underrun bit is set. Every late line is flagged.
- **No 4 KiB crossings.** Rows start on 256-byte boundaries (the base and the stride are
  256-byte aligned) and every burst is 256 B, so no burst crosses a 4 KiB boundary. The last
  burst of a row may read up to 252 B past the row's last pixel; those beats are dropped. The
  framebuffer region must therefore stay readable for 256 B past each row.
- **Latency.** The framebuffer path is three pixel clocks behind the timing generator; the
  splash is delayed to match, so switching sources never moves the syncs.

### 6.3 Simulation

`sim/run-sim.sh` runs four testbenches. Both framebuffer ones pass on every pixel of a full
frame:

| Testbench | Checks |
|---|---|
| `tb_video` | the timing and the splash (§1) |
| `tb_adv7513` | the I2C init |
| `tb_fb` | `MAGIC`/`VERSION`; every output pixel of 640×480 at 2×, 1280×720 at 1×, 1920×1080 at 1× with 50% AXI stalls, 333×200 at 4× (a partial last burst), 600×300 at 3× from another base; the pixel count and `STATUS` scale each time; black for a short stride and for a region outside DDR; a forced 35 µs stall sets the underrun bit, and the next frame is exact again; an injected `SLVERR` sets the read-error bit. On every AR: payload stable while waiting, 8 × 32 B INCR, 256-byte aligned |
| `tb_hdmi` | the top level: with `CTRL` 0, output identical to a second instance of the splash, cycle for cycle (this checks the mux and pipeline; `tb_video` checks the splash itself); with `CTRL` 1, the border black and the image exact |

The AXI model stalls `arready` and `rvalid` at random and answers in order; it does not model
reordering (the reader uses one ID). Every read is also checked to lie inside HPS DDR, none may
be issued while settings are rejected or after `CTRL` 0, and a byte write must change only its
byte. Not simulated: a reset or PLL unlock mid-fetch, `CTRL` toggled while the top level is
compared, the clear-versus-event race in `STATUS` (the logic gives the event priority), and the
I2C table's register values and real 100 kHz timing (`tb_adv7513` runs a scaled clock).

## 7. Retargeting onto Altera's DE25-Nano baseline (planned)

Altera publishes a reference design for this board: `terasic-de25-nano-devkit/baseline-a55`
in `altera-fpga/agilex5-ed-hps-baseline`, tag `QPDS26.3_REL_BASELINE_PR`, under an MIT-style
licence whose main condition is use on Altera devices. Its prebuilt files are on
`releases.rocketboards.org` (`2026.10/gsrd/agilex5_terasic_de25_nano_gsrd.baseline-a55/`). It
suits us better than Terasic's GHRD (§3):

- **Already HPS-first.** `HPS_INITIALIZATION "HPS FIRST"`, so its pair is the shape ADR 0035 D2
  needs. The published `ghrd.hps.jic` and `ghrd.core.rbf` share HPS IO hash `DF9589F2…`
  (`quartus_pfg -i`, 2026-11-27).
- **`QSPI_OWNERSHIP HPS`.** After boot the HPS owns the flash controller, so Linux can drive the
  flash with the mainline `cadence-quadspi` driver, with no SDM handover. Altera's U-Boot
  environment enables `spi@108d2000` for Linux in exactly this case (`linux_qspi_enable`).
  That simplifies ADR 0035 B3.
- **The boot core is loaded by U-Boot**, from a FIT image that carries the kernel, the DTB and
  the core.
- **An F2SDRAM adapter is already present** (AXI4, 256-bit, 40-bit address), driven by a Nios V
  test master. Ours replaces it.
- **The LW bridge** reaches the fabric peripherals at `0x2000_0000`.

What it lacks: HDMI. The top level has no HDMI ports. *UM* Table 3-13 lists them (the manual
says 3.3 V for all; see the first integration rule below): `HDMI_TX_D0..D23` = `AV19 AT11 BE11 AV14 AT19 AT14 AV16 AV11 BH11 BE14 BE19 BH14 BV6
BJ23 BV4 BU23 BH16 DA1 BH19 CP2 CM1 DA2 CP1 CU2`, `HDMI_TX_CLK` `DJ24`, `DE` `CJ2`, `HS`
`BR11`, `VS` `BR14`, `INT` `CF2`, and the I2C pair `BT1`/`BW2` (Table 3-7). The 148.5 MHz pixel
clock comes from an IOPLL we generate off the design's 100 MHz reference (`pll_refclk_100`,
`V16`).

**What the integration must get right** (from the second RTL review, 2026-11-28):

- **Pins from Terasic's `.qsf`, by script, not from the manual.** Take each `HDMI_*` location and
  I/O standard from Terasic's own project and cross-check them with their HDMI demo's. The
  manual's "3.3 V" is very likely wrong for `HDMI_TX_CLK` (`DJ24`): its neighbours in Altera's
  `.qsf` are all 1.1 V, and §5 records Terasic's `.qsf` setting it to 1.1 V. `HDMI_TX_INT`
  (`CF2`) is an input (the ADV7513 drives it open-drain). The build fails on a pin without a
  location (`PROMOTE_WARNING_TO_ERROR 12677`) and on failed timing (`332148`), and it checks the
  fitter's `.pin` report against the `.qsf` before writing any image.
- **Behind Altera's F2SDRAM adapter.** Our AXI master replaces the Nios V test master, not the
  adapter: the adapter sets the sideband the hard port expects (`ARCACHE`, `ARPROT`, `ARUSER`,
  QoS). Tie off the write channels (`AWVALID`/`WVALID` 0, `BREADY` 1). The adapter declares one
  outstanding read; if Platform Designer serialises the bursts, a 1080p row is 30 round trips in
  14.8 µs. Check `STATUS` bit 0 after ten seconds at 1920×1080, and raise the adapter's read
  capability if it underruns.
- **The block's reset includes the HPS reset,** so a warm reboot stops the reader, and the
  warm-reset handshake (looped straight back in Altera's top) waits for `STATUS` bit 2 where
  practical.
- **The pixel clock.** An IOPLL from the 100 MHz reference to 148.5 MHz; check the achieved
  frequency in the IP report (an integer PLL may only get close). Forward `HDMI_TX_CLK` from a
  DDIO output or a 180° PLL output rather than the LUT inversion in `de25_hdmi.v`, put the data
  registers in the I/O cells, and give the ADV7513's setup and hold as output delays.
- **The LW offset** of the register block, and an `f2h` interrupt line for vsync (Altera's
  top wires `f2h_irq0` to the push buttons; the DTS reserves it for the framebuffer).

**It needs Quartus 26.3.** The `.ip` files are saved by 26.3, and older versions do not open
newer IP. The base image's Quartus pin therefore moves from 25.3.1 to 26.3 when this lands.

Altera has published no 26.3 container (the newest Agilex 5 one is `26.1.1-agilex5`).
`tools/quartus-image.sh <dir>` builds one from Altera's four installer files, downloaded while
signed in: `QuartusProSetup-26.3.0.114-linux.run`, `QuartusProSetup-part2-26.3.0.114.qdz`,
`agilex_common-26.3.0.114.qdz` and `agilex5-26.3.0.114.qdz` (16 GB). It checks their SHA-1s
against `tools/quartus-26.3.0.114.sha1` (Altera's published values), installs Quartus with
Agilex 5 only into a container laid out like Altera's images, and tags it
`de25/quartus-pro:26.3.0.114-agilex5` (55 GB on disk). Running it accepts Altera's EULA.
**[V 2026-11-28: built; `quartus_sh --version` reports 26.3.0 Build 114.]**

**First check after the toolchain is in:** compile the design unmodified and compare its HPS IO
hash with the published `DF9589F2…`. A match means our build reproduces Altera's, and cores we
compile will also load over the public `ghrd.hps.jic`.
