# fpga/de25-base

The DE25-Nano base QSPI image: Terasic's GHRD plus our HDMI boot splash. Design, licensing,
build and bench checks: [docs/de25-base-image.md](../../docs/de25-base-image.md).

- `rtl/`: our HDL (GPL-3.0-or-later). No Terasic HDL lives here; the build merges into the GHRD.
- `sim/run-sim.sh`: the Icarus Verilog testbenches.
- `tools/build-base-image.sh`: the Quartus Prime Pro 25.3.1 build, from a Resource Package zip.
- `tools/gen-logo.py`: regenerates `rtl/de25_splash_logo.hex`.
