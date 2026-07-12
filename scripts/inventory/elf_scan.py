#!/usr/bin/env python3
"""elf_scan.py <rootfs-dir> [extra-file ...] — walk a rootfs tree (plus any
extra standalone files given on the command line, e.g. the stock `MiSTer`
binary which ships outside linux.img) and emit one JSON object per line
(JSONL, sorted by path) describing every ELF *regular file* found:

  {"path": "usr/bin/curl", "class": "binary", "elf_type": "EXEC",
   "soname": null, "needed": ["libc.so.6", ...], "interp": "/lib/ld-linux-armhf.so.3"}

`class` is one of:
  - "binary"       -- readelf reports "Executable file" (covers both plain
                       ET_EXEC and PIE ET_DYN -- GNU readelf's own Type:
                       string already distinguishes a PIE executable from a
                       plain shared object, which is what this script relies
                       on instead of a fragile guess based on path/name).
  - "library"      -- ET_DYN, "Shared object file" -- has a DT_SONAME tag,
                       i.e. it's loadable by SONAME via the dynamic linker's
                       NEEDED mechanism.
  - "plugin"       -- ET_DYN, "Shared object file", but NO DT_SONAME -- a
                       dlopen()'d module (gconv, PAM, NSS, xtables, Python
                       C extensions, samba VFS modules, ...), loaded by
                       full path, not by the dynamic linker's NEEDED
                       resolution. Still worth recording (P0.7 sizing) but
                       it is not part of the ABI-contract SONAME surface.
  - "other"        -- ELF but neither of the above (e.g. relocatable .o,
                       core dump) -- rare/unexpected in a rootfs, flagged
                       for a human to look at.

Evidence method: `readelf -h` (for Type:) and `readelf -d` (for SONAME/
NEEDED/program interpreter) from GNU binutils -- see the header note in
each generated doc for the exact invocation. This script only orchestrates
readelf and structures its output; it does not parse ELF itself.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SKIP_TOP_DIRS = {"proc", "sys", "dev", "run"}


def is_elf(path: Path) -> bool:
	try:
		with open(path, "rb") as f:
			return f.read(4) == b"\x7fELF"
	except OSError:
		return False


def readelf_h(path: Path) -> str | None:
	try:
		out = subprocess.run(
			["readelf", "-h", str(path)], capture_output=True, text=True, check=True
		).stdout
	except (subprocess.CalledProcessError, OSError):
		return None
	for line in out.splitlines():
		line = line.strip()
		if line.startswith("Type:"):
			return line.split(":", 1)[1].strip()
	return None


def readelf_d(path: Path) -> tuple[str | None, list[str]]:
	soname = None
	needed: list[str] = []
	try:
		out = subprocess.run(
			["readelf", "-d", str(path)], capture_output=True, text=True, check=True
		).stdout
	except (subprocess.CalledProcessError, OSError):
		return soname, needed
	for line in out.splitlines():
		if "(SONAME)" in line and "[" in line:
			soname = line.split("[", 1)[1].rsplit("]", 1)[0]
		elif "(NEEDED)" in line and "[" in line:
			needed.append(line.split("[", 1)[1].rsplit("]", 1)[0])
	return soname, needed


def readelf_interp(path: Path) -> str | None:
	try:
		out = subprocess.run(
			["readelf", "-p", ".interp", str(path)], capture_output=True, text=True
		).stdout
	except OSError:
		return None
	for line in out.splitlines():
		line = line.strip()
		if line.startswith("[") and "]" in line:
			# format: "  [     0]  /lib/ld-linux-armhf.so.3"
			val = line.split("]", 1)[1].strip()
			if val:
				return val
	return None


def classify(elf_type_line: str | None, soname: str | None) -> str:
	if elf_type_line is None:
		return "other"
	if "Executable file" in elf_type_line:
		return "binary"
	if "Shared object file" in elf_type_line:
		return "library" if soname else "plugin"
	return "other"


def scan_one(path: Path, rel: str) -> dict:
	elf_type = readelf_h(path)
	soname, needed = readelf_d(path)
	interp = readelf_interp(path) if elf_type and "Executable file" in elf_type else None
	return {
		"path": rel,
		"class": classify(elf_type, soname),
		"elf_type": elf_type,
		"soname": soname,
		"needed": sorted(needed),
		"interp": interp,
	}


def iter_rootfs_elfs(root: Path):
	for p in sorted(root.rglob("*")):
		try:
			if p.is_symlink() or not p.is_file():
				continue
		except OSError:
			continue
		rel_parts = p.relative_to(root).parts
		if rel_parts and rel_parts[0] in SKIP_TOP_DIRS:
			continue
		if not is_elf(p):
			continue
		yield p, str(p.relative_to(root))


def main(argv: list[str]) -> int:
	if len(argv) < 2:
		print(f"usage: {argv[0]} <rootfs-dir> [extra-file ...]", file=sys.stderr)
		return 2
	root = Path(argv[1])
	if not root.is_dir():
		print(f"error: '{root}' is not a directory", file=sys.stderr)
		return 1
	extra = [Path(p) for p in argv[2:]]

	records = []
	for p, rel in iter_rootfs_elfs(root):
		records.append(scan_one(p, rel))
	for p in extra:
		if not p.is_file():
			print(f"error: extra file '{p}' not found", file=sys.stderr)
			return 1
		if not is_elf(p):
			print(f"error: extra file '{p}' is not an ELF file", file=sys.stderr)
			return 1
		records.append(scan_one(p, f"EXTRA:{p}"))

	records.sort(key=lambda r: r["path"])
	for r in records:
		print(json.dumps(r, sort_keys=True))
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
