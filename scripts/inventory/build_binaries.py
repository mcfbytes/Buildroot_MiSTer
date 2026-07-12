#!/usr/bin/env python3
"""build_binaries.py <rootfs-dir> <out-md> <out-txt> <out-union-txt> [extra-elf ...]

Item (b): every ELF executable and its DT_NEEDED list, the union of all
NEEDED across the image (what P0.7 must map to Buildroot packages), and any
NEEDED SONAME that is NOT present anywhere in the image (a dangling
dependency -- would be a hard-fail finding).

`extra-elf` files (e.g. the stock `MiSTer` binary, which ships in the
release archive's `files/MiSTer`, outside `linux.img` itself) are included
in the binaries list/union but obviously can't be "found missing/present in
the image" for anything beyond the rootfs's own library set -- they're
resolved against the *rootfs*'s libraries, which is exactly the ABI
question P0.5 cares about.
"""
from __future__ import annotations

import os
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Objects the dynamic linker resolves without a corresponding on-disk
# SONAME-bearing regular file: the kernel-provided vDSO (never a real
# file) and the dynamic linker itself (present, but its own DT_SONAME is
# usually absent/irrelevant -- it's found by the ELF interpreter path, not
# NEEDED resolution).
KNOWN_NON_FILE_NEEDED = {"linux-vdso.so.1"}


def run_elf_scan(root: Path, extra: list[Path]) -> list[dict]:
	cmd = [sys.executable, str(HERE / "elf_scan.py"), str(root)] + [str(p) for p in extra]
	out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
	return [json.loads(line) for line in out.splitlines() if line.strip()]


def main(argv: list[str]) -> int:
	if len(argv) < 5:
		print(f"usage: {argv[0]} <rootfs-dir> <out-md> <out-txt> <out-union-txt> [extra-elf ...]", file=sys.stderr)
		return 2
	root = Path(argv[1]).resolve()
	out_md = Path(argv[2])
	out_txt = Path(argv[3])
	out_union = Path(argv[4])
	extra = [Path(p) for p in argv[5:]]

	records = run_elf_scan(root, extra)
	binaries = [r for r in records if r["class"] == "binary"]
	all_sonames = {r["soname"] for r in records if r["soname"]}
	# The runtime loader resolves a NEEDED entry either via the SONAME->
	# file symlink/cache convention *or*, absent that, by directly opening
	# a same-named regular file in its search path -- several bundled
	# libraries here (e.g. libadplug.so, libbinio.so) have no DT_SONAME at
	# all but are still found this way because their own filename already
	# matches what's NEEDED. So "present in the image" must check real
	# file basenames too, not just DT_SONAME tags, or every SONAME-less
	# library looks like a false-positive dangling dependency.
	all_basenames = {Path(r["path"]).name for r in records}
	# ld-linux is resolved via the ELF interpreter field, not a NEEDED
	# SONAME lookup, but list it as "present" if the file exists so it
	# doesn't spuriously show up as dangling if something odd NEEDs it.
	interp_names = {Path(r["interp"]).name for r in records if r.get("interp")}

	union_needed: set[str] = set()
	for r in records:
		union_needed.update(r["needed"])

	known_present = all_sonames | all_basenames | interp_names | KNOWN_NON_FILE_NEEDED
	dangling = sorted(n for n in union_needed if n not in known_present)

	# --- full per-binary list ---
	lines = ["# path\telf_type\tinterp\tneeded (comma-separated)"]
	for r in sorted(binaries, key=lambda r: r["path"]):
		lines.append(
			f"{r['path']}\t{r['elf_type']}\t{r['interp'] or '-'}\t{','.join(r['needed']) or '-'}"
		)
	out_txt.write_text("\n".join(lines) + "\n")

	out_union.write_text("\n".join(sorted(union_needed)) + "\n")

	mister = next((r for r in records if r["path"].endswith("MiSTer") and r["path"].startswith("EXTRA:")), None)
	busybox = next((r for r in binaries if r["path"] in ("bin/busybox", "usr/bin/busybox")), None)

	pie_count = sum(1 for r in binaries if "Position-Independent" in (r["elf_type"] or ""))
	exec_count = len(binaries) - pie_count

	md = []
	md.append(f"Total ELF binaries in the rootfs (`readelf -h` Type contains \"Executable file\"): **{len(binaries)}**")
	md.append(f"- Plain `ET_EXEC` (non-PIE): **{exec_count}**")
	md.append(f"- `ET_DYN` PIE executables: **{pie_count}**\n")
	md.append(f"Union of all `DT_NEEDED` SONAMEs across every ELF object in the image (binaries")
	md.append(f"*and* libraries/plugins -- a library can NEED another library) -- **the set")
	md.append(f"P0.7 must map to Buildroot packages**: **{len(union_needed)}** distinct SONAMEs.")
	md.append("See `binaries-needed-union.txt` for the full sorted list.\n")

	md.append("(A NEEDED entry counts as \"present\" if either some file's `DT_SONAME` matches it,")
	md.append("or a regular file with that exact basename exists anywhere in the image -- the")
	md.append("runtime loader falls back to a plain filename search when there's no SONAME/")
	md.append("ldconfig-cache hit, which is how several SONAME-less bundled libs here, e.g.")
	md.append("`libadplug.so`, `libbinio.so`, are legitimately resolved despite carrying no")
	md.append("`DT_SONAME` tag of their own.)\n")

	if dangling:
		md.append(f"### ⚠ Dangling NEEDED entries: {len(dangling)}\n")
		md.append("Required by something in the image but matched by **neither** a `DT_SONAME`")
		md.append("**nor** any same-named file anywhere in the image (and not the vDSO/interpreter)")
		md.append("-- these binaries/libraries cannot actually resolve their dependency and will")
		md.append("fail to load at runtime as shipped:\n")
		for d in dangling:
			needers = sorted(r["path"] for r in records if d in r["needed"])
			md.append(f"- `{d}` -- needed by: " + ", ".join(f"`{n}`" for n in needers))
		md.append("")
	else:
		md.append("### Dangling NEEDED entries: **none**\n")
		md.append("Every `DT_NEEDED` SONAME found anywhere in the image resolves to a real file")
		md.append("elsewhere in the image (by SONAME or by plain filename), or is the vDSO / ELF")
		md.append("interpreter.\n")

	if mister:
		md.append("### The stock `MiSTer` binary (THE ABI contract, PLAN §3 / P0.5)\n")
		# Name the record we actually matched, not argv[5]: with several
		# extra-elf arguments the MiSTer record need not be the first one, and
		# reading argv[5] would then attribute the ABI contract to the wrong
		# file. Basename only -- these docs are diffed across images and must
		# not carry the invoking host's directory layout.
		md.append(f"- Source: `{os.path.basename(mister['path'].removeprefix('EXTRA:'))}`")
		md.append(f"- ELF type: {mister['elf_type']}")
		md.append(f"- Interpreter: `{mister['interp']}`")
		md.append(f"- `DT_NEEDED` ({len(mister['needed'])}): " + ", ".join(f"`{n}`" for n in mister["needed"]))
		md.append("")

	if busybox:
		md.append("### `busybox` (init, all S-scripts, most of `/bin`)\n")
		md.append(f"- Path: `{busybox['path']}`")
		md.append(f"- ELF type: {busybox['elf_type']}")
		md.append(f"- `DT_NEEDED` ({len(busybox['needed'])}): " + ", ".join(f"`{n}`" for n in busybox["needed"]))
		md.append("")

	out_md.write_text("\n".join(md) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
