#!/usr/bin/env python3
"""lz4_legacy.py — pure-Python decompressor for the Linux kernel's "legacy"
LZ4 frame format (magic 0x184C2102), used by CONFIG_KERNEL_LZ4 zImage/vmlinux
payloads.

Why this exists: `scripts/extract-ikconfig` (in the kernel tree) shells out
to an `lz4` CLI binary for this format (`lz4 -d -l`). This environment does
not have an `lz4` CLI or a `python3-lz4` module installed (only the runtime
shared library, which isn't invocable from the shell) — see
docs/stock-inventory/kernel-config-dts.md for the evidence. The legacy frame
format is simple enough to reimplement directly, with no dependency beyond
the standard library, so gen-kernel-config-dts.sh remains runnable anywhere
python3 is.

Format (see https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md,
"skippable/legacy" variant used by arch/*/boot/compressed and
scripts/extract-ikconfig):
  magic (4 bytes LE) = 0x184C2102
  then repeated blocks until EOF:
    block_size (4 bytes LE)
    block_size bytes of raw LZ4 block data (no per-block checksum/header)
  (a block_size of 0, or one that doesn't fit in the remaining input, ends
  the stream — matches the reference decoder's behavior of stopping at the
  first truncated/invalid block rather than erroring, since the compressed
  vmlinux is itself only a prefix of the file that also contains other
  content such as the appended device tree blob).
"""
from __future__ import annotations

import struct
import sys

LEGACY_MAGIC = bytes([0x02, 0x21, 0x4C, 0x18])
_MAX_BLOCK = 8 * 1024 * 1024  # kernel's legacy encoder never exceeds 8 MiB


def find_legacy_magic(data: bytes, start: int = 0) -> int:
	"""Return the byte offset of the legacy LZ4 magic in `data`, or -1."""
	return data.find(LEGACY_MAGIC, start)


def decompress_block(block: bytes) -> bytes:
	"""Decompress one raw LZ4 block (the block-format, not the frame
	format): sequences of [token][literal-len ext][literals][offset]
	[match-len ext], as specified at
	https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
	"""
	out = bytearray()
	i = 0
	n = len(block)
	while i < n:
		token = block[i]
		i += 1
		lit_len = token >> 4
		if lit_len == 15:
			while True:
				b = block[i]
				i += 1
				lit_len += b
				if b != 0xFF:
					break
		out += block[i:i + lit_len]
		i += lit_len
		if i >= n:
			break  # last sequence in the block has no offset/match
		offset = block[i] | (block[i + 1] << 8)
		i += 2
		match_len = token & 0x0F
		if match_len == 15:
			while True:
				b = block[i]
				i += 1
				match_len += b
				if b != 0xFF:
					break
		match_len += 4
		start = len(out) - offset
		# Overlapping copy (offset can be smaller than match_len) — must
		# copy byte-by-byte, not via a bulk slice.
		for k in range(match_len):
			out.append(out[start + k])
	return bytes(out)


def decompress_legacy_stream(data: bytes) -> bytes:
	"""Decompress a full legacy-framed LZ4 stream (data[0:4] must be the
	magic). Returns the concatenated decompressed payload."""
	if data[:4] != LEGACY_MAGIC:
		raise ValueError("input does not start with the legacy LZ4 magic")
	i = 4
	n = len(data)
	out = bytearray()
	while i + 4 <= n:
		block_size = struct.unpack_from("<I", data, i)[0]
		i += 4
		if block_size == 0 or block_size > _MAX_BLOCK or i + block_size > n:
			break
		out += decompress_block(data[i:i + block_size])
		i += block_size
	return bytes(out)


def decompress_from(data: bytes) -> bytes:
	"""Locate the legacy magic anywhere in `data` and decompress from
	there. Convenience wrapper for callers holding a whole zImage that has
	a small self-extracting ARM stub prepended to the compressed
	payload."""
	idx = find_legacy_magic(data)
	if idx < 0:
		raise ValueError("legacy LZ4 magic not found in input")
	return decompress_legacy_stream(data[idx:])


def _main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(f"usage: {argv[0]} <input> <output>", file=sys.stderr)
		return 2
	with open(argv[1], "rb") as f:
		data = f.read()
	out = decompress_from(data)
	with open(argv[2], "wb") as f:
		f.write(out)
	print(f"decompressed {len(out)} bytes to {argv[2]}", file=sys.stderr)
	return 0


if __name__ == "__main__":
	raise SystemExit(_main(sys.argv))
