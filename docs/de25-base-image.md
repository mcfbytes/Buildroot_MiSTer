# DE25-Nano base QSPI image — the GHRD with an HDMI splash

**Status:** first step built and simulated; **never compiled in Quartus (no licence yet), never on a board.**
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

It runs Icarus Verilog (host install, or the `sister-sim:iverilog` image). It checks one full
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
The wrapper makes three changes, all needed **[V 2026-11-25, on this tree's build host]**:

- **`LD_PRELOAD` of the image's own `libudev.so.1`.** Without it, `quartus_syn` aborts with
  `realloc(): invalid pointer` inside `udev_enumerate_scan_devices`. The caller is the FlexLM
  host-ID probe (`cpt_flexlm_get_local_hostid`), so this hits every compile, not just one design.
- **A fixed `--mac-address`** (`QUARTUS_MAC`, default `02:de:25:00:00:01`). The licence is
  bound to a NIC ID, and a container gets a new MAC each run.
- **The caller's uid,** so the outputs are not owned by root.

**The licence.** Without one, synthesis stops with `Error (19286): No license for family
Agilex 5`. Altera issues a no-cost licence for Agilex 5 E-series, which the board's `A5EB013`
is, from its Self-Service Licensing Center. Request it for the NIC ID `02de25000001` (the
default MAC, without colons), or for your own `QUARTUS_MAC`. Pass it as `QUARTUS_LICENSE`; it is
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
