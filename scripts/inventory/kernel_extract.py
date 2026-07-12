#!/usr/bin/env python3
"""kernel_extract.py — extract the embedded IKCONFIG .config and the
appended device-tree blob out of a `zImage_dtb` file (a stock-MiSTer-style
plain concatenation of an ARM zImage + a DTB, per PLAN.md A3).

Used by gen-kernel-config-dts.sh (P0.3 item f). No third-party dependencies;
LZ4 legacy-frame decompression is provided by lz4_legacy.py in this
directory (see that file for why we don't just shell out to `lz4`).

Method (matches the "Reproduction" recipe in
docs/verification/stock-release-20250402.md, made concrete/scriptable):
  1. The ARM zImage self-relocating header has a 4-byte magic 0x016F2818 at
     offset 0x24, and a little-endian 32-bit "end" field at offset 0x2C.
     When (as here) the header's "start" field (offset 0x28) is 0, "end" is
     directly the zImage's own size in bytes — i.e. the offset one past its
     last byte. That is exactly where U-Boot computes the appended DTB
     address from (`fdt_addr = loadaddr + *(loadaddr+0x2C)`), so it is also
     where the DTB begins in a `cat zImage dtb` file. We verify this by
     checking the standard DTB magic (0xd00dfeed) at that offset.
  2. The zImage payload (self-extracting stub + compressed kernel) is
     scanned for the LZ4 "legacy frame" magic (0x184C2102); the kernel's
     CONFIG_KERNEL_LZ4 zImage build embeds the compressed vmlinux this way.
     Decompressing from there yields the raw vmlinux image.
  3. CONFIG_IKCONFIG embeds the running .config as a gzip stream wrapped in
     literal `IKCFG_ST` / `IKCFG_ED` markers inside vmlinux. We find
     `IKCFG_ST`, skip the 8-byte marker, and gzip-decompress from there
     (tolerating trailing non-gzip bytes, the same way scripts/extract-ikconfig's
     `zcat` tolerates a "trailing garbage" warning).
"""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lz4_legacy  # noqa: E402

ZIMAGE_HDR_MAGIC_OFFSET = 0x24
ZIMAGE_HDR_MAGIC = 0x016F2818
ZIMAGE_HDR_START_OFFSET = 0x28
ZIMAGE_HDR_END_OFFSET = 0x2C
DTB_MAGIC = 0xD00DFEED
IKCFG_MARKER = b"IKCFG_ST"


def find_dtb_offset(data: bytes) -> int:
	magic = struct.unpack_from("<I", data, ZIMAGE_HDR_MAGIC_OFFSET)[0]
	if magic != ZIMAGE_HDR_MAGIC:
		raise ValueError(
			f"zImage header magic mismatch at offset "
			f"{ZIMAGE_HDR_MAGIC_OFFSET:#x}: got {magic:#010x}, "
			f"expected {ZIMAGE_HDR_MAGIC:#010x}"
		)
	start = struct.unpack_from("<I", data, ZIMAGE_HDR_START_OFFSET)[0]
	end = struct.unpack_from("<I", data, ZIMAGE_HDR_END_OFFSET)[0]
	if start != 0:
		raise ValueError(
			f"zImage header 'start' field at {ZIMAGE_HDR_START_OFFSET:#x} "
			f"is {start:#x}, expected 0 (assumption behind treating 'end' "
			f"as an absolute file offset would need revisiting)"
		)
	dtb_magic = struct.unpack_from(">I", data, end)[0]
	if dtb_magic != DTB_MAGIC:
		raise ValueError(
			f"no DTB magic at computed offset {end} (0x{end:x}); got "
			f"{dtb_magic:#010x}, expected {DTB_MAGIC:#010x}. The "
			f"zImage_dtb file may not be a plain zImage+dtb concatenation."
		)
	return end


def extract_dtb(data: bytes, dtb_offset: int) -> bytes:
	dtb = data[dtb_offset:]
	totalsize = struct.unpack_from(">I", dtb, 4)[0]
	if totalsize != len(dtb):
		raise ValueError(
			f"DTB totalsize field ({totalsize}) does not reach exactly "
			f"EOF (dtb is {len(dtb)} bytes) -- unexpected trailing data "
			f"after the DTB, or this isn't a clean `cat zImage dtb`"
		)
	return dtb


def extract_ikconfig(vmlinux: bytes) -> bytes:
	st = vmlinux.find(IKCFG_MARKER)
	if st < 0:
		raise ValueError(
			"IKCFG_ST marker not found -- kernel was not built with "
			"CONFIG_IKCONFIG, or the vmlinux wasn't decompressed correctly"
		)
	start = st + len(IKCFG_MARKER)
	d = zlib.decompressobj(16 + zlib.MAX_WBITS)  # 16+ = expect gzip header
	out = d.decompress(vmlinux[start:])
	out += d.flush()
	if not out.startswith(b"#") :
		raise ValueError(
			"decompressed IKCONFIG block does not look like a kernel "
			".config (does not start with '#')"
		)
	return out


def extract_vmlinux(zimage_payload: bytes) -> bytes:
	idx = lz4_legacy.find_legacy_magic(zimage_payload)
	if idx < 0:
		raise ValueError(
			"LZ4 legacy-frame magic not found in the zImage payload -- "
			"this script only handles CONFIG_KERNEL_LZ4 zImages "
			"(stock is LZ4; a differently-compressed future image needs "
			"an extra branch here, e.g. gzip/xz -- see try_decompress in "
			"scripts/extract-ikconfig in any kernel tree for the full "
			"list of magics to support)"
		)
	return lz4_legacy.decompress_legacy_stream(zimage_payload[idx:])


def main(argv: list[str]) -> int:
	ap = argparse.ArgumentParser(description=__doc__)
	ap.add_argument("zimage_dtb", help="path to a zImage_dtb (or plain zImage) file")
	ap.add_argument("--out-config", required=True, help="output path for the extracted .config")
	ap.add_argument("--out-dtb", required=True, help="output path for the carved-out .dtb")
	args = ap.parse_args(argv[1:])

	data = Path(args.zimage_dtb).read_bytes()
	if len(data) < 0x30:
		print("error: input file too small to be a zImage", file=sys.stderr)
		return 1

	try:
		dtb_offset = find_dtb_offset(data)
	except ValueError as e:
		print(f"error: {e}", file=sys.stderr)
		return 1
	print(f"zImage declared size / DTB offset: {dtb_offset} (0x{dtb_offset:x})", file=sys.stderr)

	try:
		dtb = extract_dtb(data, dtb_offset)
	except ValueError as e:
		print(f"error: {e}", file=sys.stderr)
		return 1
	Path(args.out_dtb).write_bytes(dtb)
	print(f"wrote {len(dtb)}-byte DTB to {args.out_dtb}", file=sys.stderr)

	zimage_payload = data[:dtb_offset]
	try:
		vmlinux = extract_vmlinux(zimage_payload)
	except ValueError as e:
		print(f"error: {e}", file=sys.stderr)
		return 1
	print(f"decompressed vmlinux: {len(vmlinux)} bytes", file=sys.stderr)

	try:
		config = extract_ikconfig(vmlinux)
	except ValueError as e:
		print(f"error: {e}", file=sys.stderr)
		return 1
	Path(args.out_config).write_bytes(config)
	print(f"wrote {len(config)}-byte kernel .config to {args.out_config}", file=sys.stderr)

	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
