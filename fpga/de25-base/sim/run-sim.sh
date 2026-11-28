#!/bin/sh
# Runs the de25-base testbenches under Icarus Verilog: the host's iverilog, or a container image
# that has it, named by DE25_SIM_IMAGE.
# shellcheck disable=SC2015 # ok/FAIL pairs: ok and echo never fail
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$here/.out"                # compiled testbenches, per checkout
if command -v iverilog >/dev/null 2>&1; then run() { sh -c "$1"; }
elif [ -n "${DE25_SIM_IMAGE:-}" ]; then
	run() { docker run --rm -u "$(id -u):$(id -g)" -v "$here/..:/w" -w /w/sim "$DE25_SIM_IMAGE" sh -c "$1"; }
else echo "${0##*/}: no iverilog on PATH, and DE25_SIM_IMAGE is unset" >&2; exit 2; fi
cd "$here"
exp_lit=$(python3 -I -c "import sys; print(64 * sum(bin(int(l, 16)).count('1') for l in open(sys.argv[1])))" ../rtl/de25_splash_logo.hex)
fail=0
out=$(run "iverilog -g2012 -o .out/tb_video.vvp tb_video.v ../rtl/de25_vtiming.v ../rtl/de25_splash.v && vvp -n .out/tb_video.vvp")
echo "$out"
echo "$out" | grep -q "de=2073600 hs_edges=1125 vs_cycles=11000 lit=$exp_lit bar=8192 blank_nonzero=0" &&
	echo "ok   video: 1080p60 timing, $exp_lit lit logo pixels, 8192 bar pixels, black blanking" ||
	{ echo "FAIL video (expected lit=$exp_lit)"; fail=1; }
out=$(run "iverilog -g2012 -o .out/tb_adv.vvp tb_adv7513.v ../rtl/de25_adv7513_init.v && vvp -n .out/tb_adv.vvp")
echo "$out"
echo "$out" | grep -q "starts=43 writes=43 framing_errors=0 nack=0" &&
	echo "ok   adv7513: 43 register writes to 0x39, all ACKed, no framing errors" ||
	{ echo "FAIL adv7513"; fail=1; }
rtl="../rtl/de25_fb_regs.v ../rtl/de25_fb_reader.v ../rtl/de25_vtiming.v"
out=$(run "iverilog -g2012 -o .out/tb_fb.vvp tb_fb.v $rtl && vvp -n .out/tb_fb.vvp")
echo "$out"
echo "$out" | grep -q "tb_fb: 0 failure(s)" &&
	echo "ok   framebuffer: five modes every pixel, invalid settings black, underrun and read error flagged, AXI rules" ||
	{ echo "FAIL framebuffer"; fail=1; }
out=$(run "iverilog -g2012 -o .out/tb_hdmi.vvp tb_hdmi.v ../rtl/de25_hdmi.v $rtl ../rtl/de25_splash.v ../rtl/de25_adv7513_init.v && cd ../rtl && vvp -n ../sim/.out/tb_hdmi.vvp")
echo "$out"
echo "$out" | grep -q "splash: de=2073600 sync_mismatch=0 splash_mismatch=0" &&
	echo "$out" | grep -q "fb: de=2073600 sync_mismatch=0 border_nonblack=0 image_mismatch=0" &&
	echo "ok   top level: splash cycle-exact when disabled; framebuffer with a black border when enabled" ||
	{ echo "FAIL top level"; fail=1; }
exit "$fail"
