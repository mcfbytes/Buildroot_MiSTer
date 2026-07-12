#!/usr/bin/env python3
"""build_shared_libs.py <rootfs-dir> <out-md> <out-txt>

Item (a): every shared library, its SONAME, the real file it resolves to,
and its symlink chain.

Runs elf_scan.py (readelf -h/-d under the hood) over the whole tree, keeps
ET_DYN "Shared object file" entries (both SONAME-bearing real libraries and
SONAME-less dlopen plugins), then separately walks every symlink in the
tree to build the "logical name -> real file" chains P0.7/P2.2 need (the
SONAME is the ABI-relevant name, not whatever the regular file happens to
be called).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run_elf_scan(root: Path) -> list[dict]:
	out = subprocess.run(
		[sys.executable, str(HERE / "elf_scan.py"), str(root)],
		capture_output=True, text=True, check=True,
	).stdout
	return [json.loads(line) for line in out.splitlines() if line.strip()]


def symlink_chain(root: Path, link: Path) -> list[str] | None:
	"""Follow a symlink one hop at a time (lexical normalization only --
	does NOT use Path.resolve(), which would silently jump straight to the
	final target instead of recording each intermediate hop), returning
	the chain of root-relative path strings from the symlink itself to the
	final real file, or None if it's broken / escapes the tree / loops."""
	rel0 = str(link.relative_to(root))
	chain = [rel0]
	current_rel = rel0
	seen = set()
	for _ in range(40):  # generous bound against a pathological loop
		current = root / current_rel
		if not current.is_symlink():
			break
		if current_rel in seen:
			return None
		seen.add(current_rel)
		target = os.readlink(current)
		if os.path.isabs(target):
			nxt = os.path.normpath(target.lstrip("/"))
		else:
			nxt = os.path.normpath(os.path.join(os.path.dirname(current_rel), target))
		if nxt.startswith(".."):
			return None  # escapes the extracted tree
		chain.append(nxt)
		current_rel = nxt
	current = root / current_rel
	if current.is_symlink():
		return None  # too many hops, treat as unresolved rather than guess
	if not current.exists():
		return None
	return chain


def main(argv: list[str]) -> int:
	if len(argv) != 4:
		print(f"usage: {argv[0]} <rootfs-dir> <out-md> <out-txt>", file=sys.stderr)
		return 2
	root = Path(argv[1]).resolve()
	out_md = Path(argv[2])
	out_txt = Path(argv[3])

	records = run_elf_scan(root)
	libs = [r for r in records if r["class"] in ("library", "plugin")]

	# Build symlink chains for every symlink in the tree whose ultimate
	# target is one of the shared objects we found.
	real_paths = {r["path"] for r in libs}
	chains: dict[str, list[str]] = {}
	for p in sorted(root.rglob("*")):
		if not p.is_symlink():
			continue
		rel_parts = p.relative_to(root).parts
		if rel_parts and rel_parts[0] in ("proc", "sys", "dev", "run"):
			continue
		chain = symlink_chain(root, p)
		if chain is None:
			continue
		final_rel = chain[-1]
		if final_rel in real_paths:
			chains[chain[0]] = chain

	bash_builtin_sonames = sorted(
		r["soname"] for r in libs
		if r["path"].startswith("usr/lib/bash/") and r["soname"]
	)

	# --- full flat list (deterministic, sorted) ---
	lines = ["# path\tclass\tsoname\telf_type"]
	for r in sorted(libs, key=lambda r: r["path"]):
		lines.append(f"{r['path']}\t{r['class']}\t{r['soname'] or '-'}\t{r['elf_type']}")
	lines.append("")
	lines.append("# symlink chains (symlink -> ... -> real file), sorted by symlink path")
	for link in sorted(chains):
		lines.append(f"{link} -> " + " -> ".join(chains[link][1:]))
	out_txt.write_text("\n".join(lines) + "\n")

	sonamed = [r for r in libs if r["soname"] and r["path"] not in [
		x["path"] for x in libs if x["path"].startswith("usr/lib/bash/")
	]]
	real_libs = [r for r in libs if r["soname"] and not r["path"].startswith("usr/lib/bash/")]
	plugins = [r for r in libs if not r["soname"]]

	md = []
	md.append(f"Total ELF shared objects (`readelf -h` Type contains \"Shared object file\"): **{len(libs)}**\n")
	md.append(f"- With a `DT_SONAME` tag: **{len(sonamed) + len(bash_builtin_sonames)}**")
	md.append(f"  - True ABI libraries (resolvable via `DT_NEEDED`, excluding bash builtins): **{len(real_libs)}**")
	md.append(f"  - `/usr/lib/bash/*` loadable builtins (technically carry a `DT_SONAME` matching their own name, e.g. `soname=basename`, but are loaded via bash's `enable -f`, never via `DT_NEEDED` resolution -- not part of the ABI-contract SONAME surface): **{len(bash_builtin_sonames)}**")
	md.append(f"- Without a `DT_SONAME` (dlopen'd plugins: glibc gconv, PAM, NSS, iptables/xtables extensions, Python C extensions, Perl XS modules, slang modules, pppd plugins, ...): **{len(plugins)}**\n")
	md.append(f"Symlinks resolving to one of the above (SONAME symlink chains, e.g. `libc.so.6 -> libc-2.31.so`): **{len(chains)}**\n")

	top_dirs: dict[str, int] = {}
	for r in plugins:
		d = "/".join(Path(r["path"]).parts[:3])
		top_dirs[d] = top_dirs.get(d, 0) + 1
	md.append("### Plugin/dlopen `.so` breakdown by directory (no SONAME, not DT_NEEDED-resolved)\n")
	md.append("| Directory | Count |")
	md.append("|---|---|")
	for d, n in sorted(top_dirs.items(), key=lambda kv: (-kv[1], kv[0])):
		md.append(f"| `{d}` | {n} |")
	md.append("")

	md.append("### True ABI libraries (SONAME -> real file), sorted by SONAME\n")
	md.append("See `shared-libraries-full.txt` for the complete sorted list with symlink")
	md.append("chains; the table below is the same data with one row per SONAME for")
	md.append("quick lookup (P0.5/P0.7 consume the SONAME, not the filename).\n")
	md.append("| SONAME | Real file |")
	md.append("|---|---|")
	for r in sorted(real_libs, key=lambda r: (r["soname"] or "", r["path"])):
		md.append(f"| `{r['soname']}` | `{r['path']}` |")

	out_md.write_text("\n".join(md) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
