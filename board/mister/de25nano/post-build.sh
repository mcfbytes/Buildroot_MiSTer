#!/bin/sh
# Runs after the DE10's post-build.sh: every generic-uio node in the DE25 DTS must have
# a /dev/mister rule in the shared 65-mister-uio.rules (docs/dts-mister-fpga-interface.md §7).
set -eu
board_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
rules="$1/etc/udev/rules.d/65-mister-uio.rules"
dts="$board_dir/socfpga_agilex5_de25nano.dts"

missing=""
names=$(sed -n 's/.*linux,uio-name = "\([a-z0-9_]*\)";.*/\1/p' "$dts")
for n in $names; do
	grep -q "ATTR{name}==\"$n\"," "$rules" || missing="$missing $n"
done
if [ -n "$missing" ]; then
	echo "post-build.sh(de25nano): FATAL: no /dev/mister rule for:$missing" >&2
	exit 1
fi
echo "post-build.sh(de25nano): all $(echo "$names" | wc -l) DTS UIO nodes have a /dev/mister rule"
