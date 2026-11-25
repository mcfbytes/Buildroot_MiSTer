# DE25-Nano base QSPI image — the GHRD with an HDMI splash

**Status:** first step built and simulated; **never compiled in Quartus, never on a board.**
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

The image is **FPGA-first** (`HPS_INITIALIZATION "AFTER INIT_DONE"`, as the factory GHRD is). The
SDM configures the whole fabric before the HPS starts, so the splash is on the screen from
reset, before the SPL prints a line. The build refuses an HPS-first project.

## 2. What it is for

1. **The flash window** of ADR 0035 D4. After the first boot writes this image and reboots, every
   later boot shows the logo at power-on.
2. **A known-good fabric to fall back to.** It is the factory design plus a block that only
   drives otherwise-unused pins, so it changes nothing the HPS depends on.
3. **The base the MiSTer framework grows from.** Next steps, not built:
   - a framebuffer reader on the F2SDRAM port, reading HPS DDR at a reserved address;
   - an `fbcfg` mailbox behind the LW bridge, compatible with what ItsAlive's DE25 path expects
     (the MAGIC check and the scaler base write), so `itsalive` can draw installer progress
     unchanged;
   - the Menu core, once B2 says how cores load over an FPGA-first base.

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

It runs Icarus Verilog (host install, or the `sister-sim:iverilog` image). It checks one full
frame: 2,073,600 active pixels, 1125 lines, a 5-line vsync, exactly the logo's lit-pixel count,
and black blanking. It also checks the init against an I2C slave model: 43 writes to 0x39, all
acknowledged, no framing errors. **Both pass.**

The image (Quartus Prime Pro, **pinned 25.3.1**):

```
fpga/de25-base/tools/build-base-image.sh <DE25-Nano Resource Package .zip> <out dir>
```

Inside a Quartus Pro container (`tools/Dockerfile.quartus-pro`, an untested sketch built from
Altera's installer and Agilex 5 device file). The script:

1. unpacks the package and copies the GHRD project and `AV_PLL.ip`;
2. checks that the GHRD top has every name the merge relies on and drives no `HDMI_TX_*` pin;
3. inserts the PLL and `de25_hdmi_splash` before `endmodule` and adds our files to the `.qsf`;
4. runs `quartus_sh --flow compile`, then `quartus_pfg -c … -o hps_path=<SPL hex>` (the GHRD's
   own SPL by default; `SPL_HEX` for ours, ADR 0035 D3), then the `.jic` with Terasic's own
   options (`device=MT25QU128`, `flash_loader=A5EB013BB23B`, `mode=ASX4`);
5. prints `quartus_pfg -i` (the HPS IO hash) and the SHA-256s.

The DE10's Quartus container (`theypsilon/quartus-lite-c5:17.0.2`) cannot build this. Agilex 5
needs Quartus Prime **Pro**, and some Agilex 5 devices also need a licence file (passed in as
`LM_LICENSE_FILE`). Which applies to this device is B1/B7 desk work.

**Why 25.3.1 and not the factory's 25.1.1:** we do not need to match the factory's HPS IO hash,
because we replace the factory image. What matters is that the image and every core share one
Quartus version (T1, #318). B2 adds a reproducibility check: two clean compiles of the same
project must print the same hash.

## 5. Bench checks it needs (ADR 0035 B2)

- The logo appears at power-on, before the SPL's first line, and stays through Linux.
- The ADV7513 ACKs, which shows the I2C pins and pull-ups. A NACK leaves `init_nack` set, which
  is visible in SignalTap.
- Pixel clock phase: `HDMI_TX_CLK` is the inverted pixel clock. If the picture sparkles, adjust
  `0xBA` (the input clock delay) before touching the logic.
- `HDMI_TX_CLK`'s I/O standard: the GHRD `.qsf` sets "1.1-V", while *UM* Table 3-13 lists the
  HDMI pins at 3.3 V. Check the compile's pin report against the schematic.
- Linux and our `u-boot.itb` boot exactly as on the factory image (T2's checks).
