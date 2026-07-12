#!/usr/bin/env python3
"""normalize-dts.py <input.dts> <output> — normalize a dtc-decompiled DTS
text file for content-equivalence comparison (used by
gen-kernel-config-dts.sh to tell "a real property/node changed" apart from
"this dtc build renders whitespace/number literals differently than the one
that produced the committed docs/stock-inventory/stock.dts").

dtc's *tree content* is what P1.3/P1.7 actually depend on; its text
pretty-printing is not part of any contract. Known cosmetic variance across
dtc releases that this script neutralizes:
  - a "// version: N" / "// last_comp_version: N" / "// boot_cpuid_phys: N"
    header banner (present in some releases, absent in others)
  - 4-space vs tab indentation, and blank lines between nodes
  - hex literal padding/case (0x01 vs 0x1) and runs of internal whitespace
  - the /memreserve/ line's two address/size fields, written as bare
    decimal (e.g. "0") in some releases and as 0x-prefixed hex in others
    for the same numeric value
This is intentionally narrow: it does NOT reorder nodes/properties, so a
genuine structural difference still shows up as a diff.
"""
from __future__ import annotations

import re
import sys

HEX_RE = re.compile(r'0[xX][0-9a-fA-F]+')


def norm_hex(s: str) -> str:
	return HEX_RE.sub(lambda m: '0x' + (m.group(0)[2:].lower().lstrip('0') or '0'), s)


def normalize(path: str) -> list[str]:
	out = []
	with open(path) as f:
		for line in f:
			if line.startswith("// "):
				continue
			s = " ".join(line.split())  # collapse all internal whitespace runs
			if not s:
				continue
			m = re.match(r'^/memreserve/ (\S+) (\S+);$', s)
			if m:
				addr = int(m.group(1), 0)
				size = int(m.group(2), 0)
				s = f'/memreserve/ 0x{addr:x} 0x{size:x};'
			else:
				s = norm_hex(s)
			out.append(s)
	return out


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(f"usage: {argv[0]} <input.dts> <output>", file=sys.stderr)
		return 2
	lines = normalize(argv[1])
	with open(argv[2], "w") as f:
		f.write("\n".join(lines) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
