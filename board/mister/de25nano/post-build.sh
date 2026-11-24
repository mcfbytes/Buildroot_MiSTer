#!/bin/sh
# Runs after the DE10's post-build.sh: every generic-uio node in the DE25 DTS must have
# a /dev/mister rule, in the shared 65-mister-uio.rules or in this board's overlay's
# 65-mister-uio-de25.rules (docs/dts-mister-fpga-interface.md §7).
set -eu
board_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
rules_dir="$1/etc/udev/rules.d"
dts="$board_dir/socfpga_agilex5_de25nano.dts"

missing=""
names=$(sed -n 's/.*linux,uio-name = "\([a-z0-9_]*\)";.*/\1/p' "$dts")
# A missing file reads as empty, so every name it should have carried is reported.
rules=$(cat "$rules_dir/65-mister-uio.rules" "$rules_dir/65-mister-uio-de25.rules" 2>/dev/null || true)
for n in $names; do
	printf '%s\n' "$rules" | grep -q "ATTR{name}==\"$n\"," || missing="$missing $n"
done
if [ -n "$missing" ]; then
	echo "post-build.sh(de25nano): FATAL: no /dev/mister rule for:$missing" >&2
	exit 1
fi
echo "post-build.sh(de25nano): all $(echo "$names" | wc -l) DTS UIO nodes have a /dev/mister rule"
