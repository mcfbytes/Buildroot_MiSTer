#!/usr/bin/env python3
"""build_disk_usage.py <rootfs-dir> <out-md>

Item (g): disk usage by top-level directory, plus a second cut by
package-ish grouping under /usr/lib and /usr/share (the two directories
that dominate a typical Buildroot rootfs and where "what should we drop"
(P0.7) / size budgeting (P2.7) actually needs resolution finer than
"/usr is big").

Method: sum `st_size` (apparent file size) of every regular file, walked
in Python -- not `du`, which reports block-allocated size and would vary
with the filesystem's block size / sparseness rather than reflecting the
content Buildroot would actually package. Symlinks contribute ~0 (their
own directory-entry overhead only, not their target's size, which is
already counted once under wherever the real file lives) -- this avoids
double-counting through the extensive /bin,/lib,/sbin -> /usr/* usrmerge
symlinks.
"""
from __future__ import annotations

import sys
from pathlib import Path


def dir_stats(root: Path, top: Path) -> tuple[int, int]:
	"""Return (file_count, total_bytes) for regular files under `top`."""
	count = 0
	total = 0
	for p in top.rglob("*"):
		if p.is_symlink() or not p.is_file():
			continue
		count += 1
		try:
			total += p.stat().st_size
		except OSError:
			pass
	return count, total


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(f"usage: {argv[0]} <rootfs-dir> <out-md>", file=sys.stderr)
		return 2
	root = Path(argv[1]).resolve()
	out_md = Path(argv[2])

	top_entries = sorted(p for p in root.iterdir())
	rows = []
	grand_files = 0
	grand_bytes = 0
	for p in top_entries:
		if p.is_symlink():
			target = p.readlink() if hasattr(p, "readlink") else None
			rows.append((p.name + " (symlink)", 0, 0, str(target) if target else ""))
			continue
		if not p.is_dir():
			try:
				size = p.stat().st_size
			except OSError:
				size = 0
			rows.append((p.name, 1, size, ""))
			grand_files += 1
			grand_bytes += size
			continue
		count, total = dir_stats(root, p)
		rows.append((p.name + "/", count, total, ""))
		grand_files += count
		grand_bytes += total

	md: list[str] = []
	md.append(f"Total regular-file content under the extracted rootfs: **{grand_bytes} bytes** ({grand_bytes / (1024*1024):.1f} MiB) across **{grand_files}** files.\n")
	md.append("(This is *content* size -- apparent `st_size` summed over regular files")
	md.append("only, not on-disk block allocation, and not counting symlinks themselves")
	md.append("-- comparing it to the 375 MiB image / its ext4 metadata+overhead+free-space")
	md.append("is expected to undercount slightly; see docs/verification/stock-release-20250402.md")
	md.append("for the image-level free-space figure.)\n")

	md.append("### By top-level directory\n")
	md.append("| Entry | Files | Bytes | MiB | Note |")
	md.append("|---|---|---|---|---|")
	for name, count, total, note in sorted(rows, key=lambda r: -r[2]):
		mib = total / (1024 * 1024)
		note_s = f"symlink -> `{note}`" if note else ""
		md.append(f"| `/{name}` | {count} | {total} | {mib:.2f} | {note_s} |")
	md.append("")

	# Second cut: package-ish grouping under usr/lib and usr/share, the two
	# directories that dominate (everything else usrmerge-symlinks into
	# these). One row per immediate subdirectory, which in a Buildroot-style
	# rootfs corresponds closely to "one row per package's private dir"
	# (python3.9, samba, gconv, perl5, ...).
	for sub in ("usr/lib", "usr/share", "usr/bin", "usr/sbin"):
		subdir = root / sub
		if not subdir.is_dir():
			continue
		md.append(f"### Package-ish breakdown: `/{sub}/*` (top 25 by size)\n")
		md.append("| Subdirectory | Files | Bytes | MiB |")
		md.append("|---|---|---|---|")
		sub_rows = []
		loose_count = 0
		loose_bytes = 0
		for child in sorted(subdir.iterdir()):
			if child.is_symlink():
				continue
			if child.is_dir():
				count, total = dir_stats(root, child)
				sub_rows.append((child.name + "/", count, total))
			elif child.is_file():
				try:
					loose_bytes += child.stat().st_size
				except OSError:
					pass
				loose_count += 1
		sub_rows.sort(key=lambda r: -r[2])
		for name, count, total in sub_rows[:25]:
			md.append(f"| `{name}` | {count} | {total} | {total / (1024*1024):.2f} |")
		if loose_count:
			md.append(f"| *(loose files directly in `/{sub}`)* | {loose_count} | {loose_bytes} | {loose_bytes / (1024*1024):.2f} |")
		if len(sub_rows) > 25:
			remainder = sub_rows[25:]
			rem_files = sum(r[1] for r in remainder)
			rem_bytes = sum(r[2] for r in remainder)
			md.append(f"| *(remaining {len(remainder)} subdirectories)* | {rem_files} | {rem_bytes} | {rem_bytes / (1024*1024):.2f} |")
		md.append("")

	out_md.write_text("\n".join(md) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
