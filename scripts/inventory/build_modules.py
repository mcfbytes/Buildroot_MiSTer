#!/usr/bin/env python3
"""build_modules.py <rootfs-dir> <out-md>

Item (h): the 52 `.ko.xz` modules with their dependencies (parsed from
`modules.dep`), grouped by driver family, mapped to a P0.4 disposition
class (D/E, PLAN.md §4.1) and an owning Phase 3 task, plus the
`modules.alias` count/mechanism (udev-driven autoload, P3.3).
"""
from __future__ import annotations

import sys
from pathlib import Path

MODULES_SUBDIR = "usr/lib/modules"

# name -> (group, P0.4 class, owning task, one-line note)
GROUPS: dict[str, tuple[str, str, str, str]] = {
	# mac80211 stack (core cfg80211/mac80211 infrastructure everything else needs)
	"cfg80211": ("mac80211 stack (core)", "in-tree, upstream", "P3.1/P3.3", "wireless config API core; every WiFi driver below needs it"),
	"mac80211": ("mac80211 stack (core)", "in-tree, upstream", "P3.1/P3.3", "software MAC layer used by most non-vendor-specific drivers"),
	"lib80211": ("mac80211 stack (core)", "in-tree, upstream", "P3.1/P3.3", "shared WEP/TKIP/CCMP crypto helpers (legacy, used by libertas et al)"),
	# mt76 family
	"mt76": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MediaTek mt76 core driver"),
	"mt76-usb": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "mt76 USB transport"),
	"mt76-connac-lib": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "shared lib for mt7663/mt7615-class chips"),
	"mt7601u": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT7601U USB dongle"),
	"mt7615-common": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT7615-class shared code"),
	"mt7663-usb-sdio-common": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT7663 USB/SDIO shared code"),
	"mt7663u": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT7663U USB dongle"),
	"mt76x0-common": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT76x0-class shared code"),
	"mt76x02-lib": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT76x02-class shared lib"),
	"mt76x02-usb": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT76x02-class USB transport"),
	"mt76x0u": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT76x0U USB dongle"),
	"mt76x2-common": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT76x2-class shared code"),
	"mt76x2u": ("mt76* (MediaTek)", "in-tree, upstream", "P3.1/P3.3", "MT76x2U USB dongle"),
	# rt2x00 / Ralink family
	"rt2x00lib": ("rt2x00* (Ralink)", "in-tree, upstream", "P3.1/P3.3", "rt2x00 core library"),
	"rt2x00usb": ("rt2x00* (Ralink)", "in-tree, upstream", "P3.1/P3.3", "rt2x00 USB transport"),
	"rt2800lib": ("rt2x00* (Ralink)", "in-tree, upstream", "P3.1/P3.3", "rt2800-class shared lib"),
	"rt2800usb": ("rt2x00* (Ralink)", "in-tree, upstream", "P3.1/P3.3", "rt2800 USB dongles"),
	"rt2500usb": ("rt2x00* (Ralink)", "in-tree, upstream", "P3.1/P3.3", "rt2500 USB dongles (legacy)"),
	"rt73usb": ("rt2x00* (Ralink)", "in-tree, upstream", "P3.1/P3.3", "rt73 USB dongles (legacy)"),
	# rtlwifi (in-tree Realtek) + rtl8xxxu
	"rtlwifi": ("rtlwifi (in-tree Realtek)", "in-tree, upstream", "P3.1/P3.3", "rtlwifi core"),
	"rtl8192c-common": ("rtlwifi (in-tree Realtek)", "in-tree, upstream", "P3.1/P3.3", "RTL8192C-class shared code"),
	"rtl8192cu": ("rtlwifi (in-tree Realtek)", "in-tree, upstream", "P3.1/P3.3", "RTL8192CU USB dongle"),
	"rtl_usb": ("rtlwifi (in-tree Realtek)", "in-tree, upstream", "P3.1/P3.3", "rtlwifi USB transport"),
	"rtl8187": ("rtlwifi (in-tree Realtek)", "in-tree, upstream", "P3.1/P3.3", "RTL8187 USB dongle (older rtl_usb-independent driver)"),
	"rtl8xxxu": ("rtl8xxxu (in-tree Realtek, alt. driver)", "in-tree, upstream", "P3.1/P3.3", "newer single-module Realtek USB driver (alternative to rtlwifi for some chips)"),
	# Out-of-tree Realtek set (class E, morrownr re-source, PLAN.md §4.1)
	"8188eu": ("Out-of-tree Realtek (class E)", "class E -- re-source from morrownr, do not vendor", "P3.1", "RTL8188EU"),
	"rtl8188fu": ("Out-of-tree Realtek (class E)", "class E -- re-source from morrownr, do not vendor", "P3.1", "RTL8188FU"),
	"8812au": ("Out-of-tree Realtek (class E)", "class E -- re-source from morrownr, do not vendor", "P3.1", "RTL8812AU"),
	"8821au": ("Out-of-tree Realtek (class E)", "class E -- re-source from morrownr, do not vendor", "P3.1", "RTL8821AU"),
	"8821cu": ("Out-of-tree Realtek (class E)", "class E -- re-source from morrownr, do not vendor", "P3.1", "RTL8821CU"),
	"88x2bu": ("Out-of-tree Realtek (class E)", "class E -- re-source from morrownr, do not vendor", "P3.1", "RTL88x2BU"),
	# Marvell (in-tree, not called out explicitly in the task list but present)
	"libertas": ("Marvell (in-tree, upstream)", "in-tree, upstream", "P3.1/P3.3", "Marvell Libertas core"),
	"libertas_tf": ("Marvell (in-tree, upstream)", "in-tree, upstream", "P3.1/P3.3", "Libertas \"thinfirm\" variant"),
	"libertas_tf_usb": ("Marvell (in-tree, upstream)", "in-tree, upstream", "P3.1/P3.3", "Libertas thinfirm USB transport"),
	"mwifiex": ("Marvell (in-tree, upstream)", "in-tree, upstream", "P3.1/P3.3", "Marvell mwifiex core"),
	"mwifiex_usb": ("Marvell (in-tree, upstream)", "in-tree, upstream", "P3.1/P3.3", "mwifiex USB transport"),
	"usb8xxx": ("Marvell (in-tree, upstream)", "in-tree, upstream", "P3.1/P3.3", "Marvell USB8xxx firmware loader helper"),
	# Bluetooth USB
	"btusb": ("Bluetooth USB", "in-tree, upstream", "P3.3/P3.5", "generic USB Bluetooth HCI driver"),
	"btintel": ("Bluetooth USB", "in-tree, upstream", "P3.3/P3.5", "Intel BT firmware/quirk helper"),
	"btbcm": ("Bluetooth USB", "in-tree, upstream", "P3.3/P3.5", "Broadcom BT firmware/quirk helper"),
	"btrtl": ("Bluetooth USB", "in-tree, upstream", "P3.3/P3.5", "Realtek BT firmware/quirk helper"),
	"ath3k": ("Bluetooth USB", "in-tree, upstream", "P3.3/P3.5", "Atheros AR3011/AR3012 BT firmware loader"),
	# xone (class D, PLAN.md §4.1)
	"xone-dongle": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "Xbox wireless dongle transport"),
	"xone-gip-bus": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "GIP (Game Input Protocol) virtual bus"),
	"xone-gip-chatpad": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "GIP chatpad accessory"),
	"xone-gip-common": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "GIP shared code"),
	"xone-gip-gamepad": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "GIP gamepad input"),
	"xone-gip-headset": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "GIP headset audio"),
	"xone-wired": ("xone (Xbox wireless)", "class D -- carry / package (P3.2)", "P3.2", "wired Xbox One controller transport"),
}


def parse_modules_dep(path: Path) -> dict[str, list[str]]:
	deps: dict[str, list[str]] = {}
	for line in path.read_text().splitlines():
		if not line.strip():
			continue
		lhs, _, rhs = line.partition(":")
		mod = lhs.strip()
		rhs_deps = [d for d in rhs.strip().split() if d]
		deps[mod] = rhs_deps
	return deps


def modname(ko_path: str) -> str:
	return Path(ko_path).name.removesuffix(".ko.xz")


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(f"usage: {argv[0]} <rootfs-dir> <out-md>", file=sys.stderr)
		return 2
	root = Path(argv[1]).resolve()
	out_md = Path(argv[2])

	modules_root = root / MODULES_SUBDIR
	kdirs = [p for p in modules_root.iterdir() if p.is_dir()] if modules_root.is_dir() else []
	if len(kdirs) != 1:
		print(f"error: expected exactly one kernel-version dir under {modules_root}, found {len(kdirs)}", file=sys.stderr)
		return 1
	kdir = kdirs[0]
	kernel_version = kdir.name

	dep_file = kdir / "modules.dep"
	if not dep_file.is_file():
		print(f"error: {dep_file} not found", file=sys.stderr)
		return 1
	deps = parse_modules_dep(dep_file)

	ko_files = sorted(kdir.rglob("*.ko.xz"))
	alias_file = kdir / "modules.alias"
	alias_count = 0
	if alias_file.is_file():
		alias_count = sum(
			1 for line in alias_file.read_text().splitlines()
			if line.strip() and not line.startswith("#")
		)
	builtin_file = kdir / "modules.builtin"
	builtin_count = len(builtin_file.read_text().splitlines()) if builtin_file.is_file() else 0

	md: list[str] = []
	md.append(f"Kernel version directory: `{MODULES_SUBDIR}/{kernel_version}/`\n")
	md.append(f"`.ko.xz` module count: **{len(ko_files)}**")
	md.append(f" (per A5/PLAN §3/§4.1: stock ships 52 -- {'matches' if len(ko_files) == 52 else 'DIFFERS from the documented 52'}).\n")
	md.append(f"`modules.dep` entries: **{len(deps)}**; built-in (non-module) drivers listed in `modules.builtin`: **{builtin_count}**.\n")

	md.append("### `modules.alias` and the udev autoload mechanism (P3.3)\n")
	md.append(f"`modules.alias` non-comment lines: **{alias_count}**. Mechanism: `depmod` (run")
	md.append("at image build time) generates `modules.alias` from every module's")
	md.append("`MODULE_DEVICE_TABLE` info (`alias <bus-match-pattern> <module-name>`).")
	md.append("**eudev** (stock's hotplug daemon, `S10udev`) matches each hotplugged")
	md.append("device's kernel-generated `MODALIAS` uevent variable against this table")
	md.append("and invokes `modprobe`, which resolves the match through")
	md.append("`modules.alias`/`modules.dep` to load the right `.ko.xz` (and its")
	md.append("dependencies, in the order `modules.dep` specifies) -- no static")
	md.append("device-to-module list is maintained anywhere; it's entirely table-driven")
	md.append("from what's actually plugged in. P3.3 must reproduce this exact chain")
	md.append("(`depmod` at image build + eudev + `modprobe`), not a custom udev-rules")
	md.append("hardcoded module list.\n")

	# --- grouped table ---
	grouped: dict[str, list[str]] = {}
	unclassified = []
	for ko in ko_files:
		name = modname(str(ko))
		info = GROUPS.get(name)
		if info is None:
			unclassified.append(name)
			continue
		grouped.setdefault(info[0], []).append(name)

	md.append("### Grouped by driver family\n")
	md.append("| Group | Count | P0.4 class / disposition | Phase 3 task |")
	md.append("|---|---|---|---|")
	group_order = []
	seen_groups = set()
	for name in GROUPS:
		g = GROUPS[name][0]
		if g not in seen_groups:
			seen_groups.add(g)
			group_order.append(g)
	for g in group_order:
		members = grouped.get(g, [])
		if not members:
			continue
		# class/task are the same for every member of a group by construction
		sample = next(v for k, v in GROUPS.items() if v[0] == g)
		md.append(f"| {g} | {len(members)} | {sample[1]} | {sample[2]} |")
	if unclassified:
		md.append(f"| *(unclassified -- new module since this script was written)* | {len(unclassified)} | - | - |")
	md.append("")

	# --- full per-module table with deps ---
	md.append("### Full module list with dependencies (sorted)\n")
	md.append("| Module | Group | Dependencies |")
	md.append("|---|---|---|")
	for ko in ko_files:
		name = modname(str(ko))
		rel = str(ko.relative_to(kdir))
		group = GROUPS.get(name, ("(unclassified)",))[0]
		dep_list = deps.get(rel, [])
		dep_names = ", ".join(f"`{modname(d)}`" for d in dep_list) if dep_list else "*(none)*"
		md.append(f"| `{name}` | {group} | {dep_names} |")
	md.append("")

	if unclassified:
		md.append(f"### ⚠ Unclassified modules: {', '.join(unclassified)}\n")
		md.append("Present in the image but not in this script's GROUPS table -- likely")
		md.append("means the stock module set changed since this inventory was written;")
		md.append("update `scripts/inventory/build_modules.py`'s `GROUPS` dict.\n")

	out_md.write_text("\n".join(md) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
