#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds the DE25-Nano base QSPI image: Terasic's GHRD with our HDMI splash merged in
# (docs/de25-base-image.md). Run inside a Quartus Prime Pro container; nothing here writes a board.
#
# usage: build-base-image.sh RESOURCE_PACKAGE.zip OUT_DIR
# env:   SPL_HEX     SPL to embed (default: the GHRD's own u-boot-spl-dtb.hex from the package)
#        QUARTUS_VER the pinned Quartus version (default 25.3.1); a mismatch is fatal
set -eu

prog=${0##*/}
die() { echo "$prog: FATAL: $*" >&2; exit 1; }
say() { echo "$prog: $*"; }

[ $# -eq 2 ] || die "usage: $prog RESOURCE_PACKAGE.zip OUT_DIR"
rp=$1; out=$2
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${QUARTUS_VER:=25.3.1}"
[ -f "$rp" ] || die "no resource package at $rp"
for t in quartus_sh quartus_pfg unzip sha256sum; do command -v "$t" >/dev/null || die "$t not on PATH"; done
quartus_sh --version | grep -q "Version $QUARTUS_VER" ||
	die "Quartus is not $QUARTUS_VER -- the HPS IO hash depends on the version, so cores and this image must share one"

mkdir -p "$out"; out=$(CDPATH='' cd -- "$out" && pwd)
work="$out/work"; rm -rf "$work"; mkdir -p "$work"

say "unpacking $(basename "$rp") (sha256 $(sha256sum "$rp" | cut -c1-16)...)"
unzip -q "$rp" -d "$work/rp"
ghrd=$(find "$work/rp" -type d -path '*Demonstration/SoC_FPGA/GHRD' | head -n1)
pll=$(find "$work/rp" -type f -path '*Demonstration/FPGA/HDMI_TX/*' -name AV_PLL.ip | head -n1)
[ -n "$ghrd" ] || die "no Demonstration/SoC_FPGA/GHRD in the package"
[ -n "$pll" ] || die "no HDMI_TX AV_PLL.ip in the package (the 148.5 MHz pixel PLL)"

proj="$work/ghrd"
cp -a "$ghrd" "$proj"
mkdir -p "$proj/de25_base"
cp -a "$pll" "$proj/de25_base/"
[ -d "${pll%.ip}" ] && cp -a "${pll%.ip}" "$proj/de25_base/"
cp "$here"/rtl/*.v "$here"/rtl/de25_splash_logo.hex "$proj/de25_base/"

qpf=$(find "$proj" -maxdepth 1 -name '*.qpf' | head -n1)
[ -n "$qpf" ] || die "no .qpf in the GHRD"
rev=$(basename "$qpf" .qpf)
top="$proj/$rev.v"; qsf="$proj/$rev.qsf"
[ -f "$top" ] && [ -f "$qsf" ] || die "expected $rev.v and $rev.qsf beside $rev.qpf"

# The merge is checked, not assumed: every name it relies on must already be in Terasic's top.
for n in CLOCK0_50 CLOCK2_50 system_reset_n HDMI_TX_CLK HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS HDMI_TX_D HDMI_I2C_SCL HDMI_I2C_SDA; do
	grep -q "\\b$n\\b" "$top" || die "$rev.v has no '$n' -- the package is not the GHRD this recipe was written for"
done
grep -Eq 'assign[[:space:]]+HDMI_TX_' "$top" && die "$rev.v already drives HDMI_TX_* -- refusing to double-drive"
# HPS-first: only an HPS-first phase-1 accepts cores at runtime (ADR 0035 D2; #318 T1/T3).
sed -i '/HPS_INITIALIZATION/d' "$qsf"
echo 'set_global_assignment -name HPS_INITIALIZATION "HPS FIRST"' >> "$qsf"

say "merging the HDMI splash into $rev.v"
python3 -I - "$top" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
i = s.rindex("endmodule")
s = s[:i] + """
// ---- de25-base: HDMI boot splash (Buildroot_MiSTer fpga/de25-base) ----
wire de25_pclk;
AV_PLL u_de25_pll (.refclk(CLOCK0_50), .rst(~system_reset_n), .outclk_0(de25_pclk));
de25_hdmi_splash u_de25_splash (
	.clk50(CLOCK2_50), .pclk(de25_pclk), .rst_n(system_reset_n),
	.HDMI_TX_CLK(HDMI_TX_CLK), .HDMI_TX_DE(HDMI_TX_DE), .HDMI_TX_HS(HDMI_TX_HS),
	.HDMI_TX_VS(HDMI_TX_VS), .HDMI_TX_D(HDMI_TX_D),
	.HDMI_I2C_SCL(HDMI_I2C_SCL), .HDMI_I2C_SDA(HDMI_I2C_SDA),
	.init_done(), .init_nack()
);
""" + s[i:]
open(p, "w").write(s)
PYEOF
{
	echo "set_global_assignment -name IP_FILE de25_base/AV_PLL.ip"
	for f in de25_vtiming de25_splash de25_adv7513_init de25_hdmi_splash; do
		echo "set_global_assignment -name VERILOG_FILE de25_base/$f.v"
	done
	echo "set_global_assignment -name SEARCH_PATH de25_base"
} >> "$qsf"

say "compiling (quartus_sh --flow compile $rev)"
( cd "$proj" && quartus_sh --flow compile "$rev" ) > "$out/compile.log" 2>&1 ||
	die "compile failed -- see $out/compile.log"

spl=${SPL_HEX:-$(find "$proj" -path '*software/u-boot/spl/u-boot-spl-dtb.hex' | head -n1)}
[ -n "$spl" ] && [ -f "$spl" ] || die "no SPL hex (set SPL_HEX, or the package's GHRD lacks software/u-boot/spl)"
sof="$proj/output_files/$rev.sof"
say "embedding the SPL ($spl)"
quartus_pfg -c "$sof" "$out/de25_base_hps.sof" -o hps_path="$spl" > "$out/pfg-sof.log" 2>&1 ||
	die "SPL merge failed -- see $out/pfg-sof.log"
say "writing the QSPI image (phase-1) and the splash core"
quartus_pfg -c "$out/de25_base_hps.sof" "$out/de25_base.jic" -o hps=1 \
	-o device=MT25QU128 -o flash_loader=A5EB013BB23B -o mode=ASX4 > "$out/pfg-jic.log" 2>&1 ||
	die "jic generation failed -- see $out/pfg-jic.log"
quartus_pfg -c "$out/de25_base_hps.sof" "$out/de25_base.rbf" -o hps=1 > "$out/pfg-rbf.log" 2>&1 ||
	die "rbf generation failed -- see $out/pfg-rbf.log"
[ -f "$out/de25_base.core.rbf" ] || die "pfg wrote no de25_base.core.rbf -- see $out/pfg-rbf.log"
for f in de25_base.jic de25_base.core.rbf; do
	quartus_pfg -i "$out/$f" > "$out/$f.info" 2>&1 || true
done

# The pair is only usable if both halves carry the same HPS IO hash (T1, #318).
h1=$(grep -i 'HPS IO hash' "$out/de25_base.jic.info" | head -n1)
h2=$(grep -i 'HPS IO hash' "$out/de25_base.core.rbf.info" | head -n1)
[ -n "$h1" ] && [ "$h1" = "$h2" ] || die "HPS IO hash differs or is missing (jic: '$h1', core: '$h2')"

( cd "$out" && sha256sum de25_base.jic de25_base.core.rbf de25_base_hps.sof > SHA256SUMS )
say "done: $out/de25_base.jic + de25_base.core.rbf ($h1)"
cat "$out/SHA256SUMS"
