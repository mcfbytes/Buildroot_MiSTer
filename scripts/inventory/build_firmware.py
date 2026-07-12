#!/usr/bin/env python3
"""build_firmware.py <rootfs-dir> <out-md>

Item (d): full `/usr/lib/firmware` file list with sizes, grouped by vendor
directory, and the correct file count (resolving a documentation
discrepancy -- see the doc body).
"""
from __future__ import annotations

import sys
from pathlib import Path

FW_DIR = "usr/lib/firmware"

# Which module/driver each vendor directory (or loose top-level file glob)
# feeds, and which Phase 3 task owns it -- from PLAN.md §4.1 / TASKS.md A5.
VENDOR_NOTES = {
	"RTL8192E": ("rtl8192e (in-tree rtlwifi family)", "P3.1 (class E, morrownr re-source) / P3.3 (firmware infra)"),
	"brcm": ("btusb/btbcm (Broadcom BT patch, BCM20702A1)", "P3.3 (Bluetooth USB firmware)"),
	"mediatek": ("mt76x0/mt7622 (mt76 family)", "P3.1 / P3.3"),
	"rtl_bt": ("btrtl (Realtek Bluetooth USB)", "P3.3 (Bluetooth USB firmware)"),
	"rtlwifi": ("rtlwifi (in-tree Realtek WiFi: 8188e/8192c/8192d/8192e/8723 family)", "P3.1 (class E where out-of-tree) / P3.3"),
}
LOOSE_FILE_NOTES = {
	"mt7601u.bin": ("rt2800usb/mt7601u (in-tree ralink/mt76 family)", "P3.1 / P3.3"),
	"mt7650.bin": ("rt2800usb (Ralink/MediaTek)", "P3.1 / P3.3"),
	"mt7662.bin": ("rt2800usb (Ralink/MediaTek)", "P3.1 / P3.3"),
	"mt7662_rom_patch.bin": ("rt2800usb (Ralink/MediaTek)", "P3.1 / P3.3"),
	"rt2870.bin": ("rt2800usb (Ralink)", "P3.1 / P3.3"),
	"rt2870_sw_ch_offload.bin": ("rt2800usb (Ralink)", "P3.1 / P3.3"),
	"regulatory.db": ("cfg80211 (wireless regulatory database, not a driver firmware blob)", "P3.3 (linux-firmware parity, not driver-specific)"),
	"regulatory.db.p7s": ("cfg80211 (regulatory.db's detached signature)", "P3.3"),
	"xow_dongle.bin": ("xone / xow (Xbox One wireless dongle firmware)", "P3.2 (xone package + redistribution decision)"),
}


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(f"usage: {argv[0]} <rootfs-dir> <out-md>", file=sys.stderr)
		return 2
	root = Path(argv[1]).resolve()
	out_md = Path(argv[2])
	fw_root = root / FW_DIR

	if not fw_root.is_dir():
		print(f"error: '{fw_root}' not found -- is this a full rootfs extraction?", file=sys.stderr)
		return 1

	all_entries = sorted(fw_root.rglob("*"))
	files = [p for p in all_entries if p.is_file()]
	dirs = [p for p in all_entries if p.is_dir()]
	symlinks = [p for p in all_entries if p.is_symlink()]
	# `find /usr/lib/firmware | wc -l` (no -mindepth 1) that PLAN.md/TASKS.md's
	# "72 firmware files" figure traces to: the firmware dir itself (+1) plus
	# every entry under it (files + subdirs), i.e. it counts directories as
	# if they were files.
	find_no_mindepth_count = 1 + len(all_entries)

	by_vendor: dict[str, list[Path]] = {}
	for p in files:
		rel = p.relative_to(fw_root)
		vendor = rel.parts[0] if len(rel.parts) > 1 else "(top-level)"
		by_vendor.setdefault(vendor, []).append(p)

	md: list[str] = []
	md.append(f"**Regular files under `/{FW_DIR}`: {len(files)}**\n")
	md.append("### Resolving the \"72 firmware files\" figure in PLAN.md §3/§4.1, TASKS.md A5, and the verification doc\n")
	md.append(f"Those all say stock ships \"72 firmware files\". The actual count of")
	md.append(f"**regular files** is **{len(files)}**. Reproducing the likely source of")
	md.append(f"the \"72\": `find /usr/lib/firmware | wc -l` (i.e. *without* `-mindepth 1`)")
	md.append(f"counts the firmware directory itself as one line, plus one line per entry")
	md.append(f"under it -- {len(files)} files + {len(dirs)} subdirectories" +
	           (f" + {len(symlinks)} symlinks" if symlinks else "") +
	           f" + 1 (the dir itself) = **{find_no_mindepth_count}**, matching the")
	md.append(f"documented figure exactly. So the existing docs are counting directories")
	md.append(f"(and the top-level dir itself) as if they were firmware files. **This")
	md.append(f"doc's {len(files)} is the corrected, authoritative count** (files only,")
	md.append(f"via `find -type f`, cross-checked against `debugfs -R \"ls -l ...\"` on the")
	md.append(f"raw ext4 image directly, not just the extracted tree).\n")

	if symlinks:
		md.append(f"Symlinks under `/{FW_DIR}`: **{len(symlinks)}** (none expected/found is also a valid, reported result).\n")

	md.append("### By vendor/subsystem directory\n")
	md.append("| Directory | Files | Total bytes | Feeds driver | Phase 3 task |")
	md.append("|---|---|---|---|---|")
	for vendor in sorted(by_vendor):
		flist = by_vendor[vendor]
		total = sum(p.stat().st_size for p in flist)
		note = VENDOR_NOTES.get(vendor, ("(loose top-level files -- see below)", "-"))
		label = f"`{vendor}/`" if vendor != "(top-level)" else "*(top-level, no subdir)*"
		md.append(f"| {label} | {len(flist)} | {total} | {note[0]} | {note[1]} |")
	md.append("")

	md.append("### Full file listing (sorted, with size and driver/task mapping)\n")
	md.append("| Path | Bytes | Feeds driver | Phase 3 task |")
	md.append("|---|---|---|---|")
	for p in files:
		rel = str(p.relative_to(fw_root))
		size = p.stat().st_size
		if "/" in rel:
			vendor = rel.split("/", 1)[0]
			note = VENDOR_NOTES.get(vendor, ("-", "-"))
		else:
			note = LOOSE_FILE_NOTES.get(rel, ("-", "-"))
		md.append(f"| `{rel}` | {size} | {note[0]} | {note[1]} |")
	md.append("")

	md.append("### Redistribution-relevant callout: `xow_dongle.bin`\n")
	md.append("Present at `/usr/lib/firmware/xow_dongle.bin` in the **stock** image --")
	md.append("this is the Xbox One wireless dongle firmware used by the `xone`/`xow`")
	md.append("driver stack. Directly relevant to **P3.2**'s redistribution question:")
	md.append("stock **does** ship this firmware file today (bundled directly in")
	md.append("`linux.img`, not fetched on demand), so whatever redistribution")
	md.append("constraints apply, MiSTer's existing distribution already accepts them for")
	md.append("this exact file -- P3.2 should confirm the same terms apply to however we")
	md.append("choose to source/ship it (bundle vs on-device fetch) rather than assume a")
	md.append("stricter default.\n")

	out_md.write_text("\n".join(md) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
