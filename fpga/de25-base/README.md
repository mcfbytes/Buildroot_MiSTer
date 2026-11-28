# fpga/de25-base

The DE25-Nano base QSPI image: our HDMI block, and the first build recipe (Terasic's GHRD plus a
boot splash). The base is moving to Altera's baseline design. Design, licensing, build and bench
checks: [docs/de25-base-image.md](../../docs/de25-base-image.md). Quartus, the licences and the
version freeze: [docs/de25-quartus.md](../../docs/de25-quartus.md).

- `rtl/`: our HDL (GPL-3.0-or-later). No Terasic HDL lives here; the build merges into the GHRD.
- `sim/run-sim.sh`: the Icarus Verilog testbenches.
- `tools/build-base-image.sh`: the first recipe, a Quartus Prime Pro 25.3.1 build from a Resource Package zip.
- `tools/quartus-run.sh`: runs a command in a Quartus Pro container (`QUARTUS_IMAGE`).
- `tools/quartus-image.sh`: builds the Quartus Pro 26.3 container from Altera's installers.
- `tools/gen-logo.py`: regenerates `rtl/de25_splash_logo.hex`.
