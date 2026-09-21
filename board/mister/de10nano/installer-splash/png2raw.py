#!/usr/bin/env python3
"""png2raw.py IN.png OUT.raw.gz -- one PNG to a gzipped raw BGRX8888 frame.

The SD-card installer's HDMI splash (ADR 0020 §9) is blitted by `itsalive
image`, which takes raw pixels in MiSTer_fb's byte order -- B, G, R, then a
padding byte -- and neither decodes nor scales. The frames are composed as
PNGs (build.py, checked in); this turns one into what the tool eats, at
build time, from installer-post-build.sh. It exists so that no derived
binary has to live in git next to its source.

Deliberately dependency-free: the standard library only (zlib, struct,
gzip), so it runs on any host Buildroot itself runs on, with nothing to
apt-get. That costs a PNG decoder of ~40 lines, which is why it accepts only
what build.py emits: 8-bit RGB (colour type 2) or RGBA (6), non-interlaced.
Anything else is a loud error, not a guess. Alpha is dropped, not blended:
the frames are fully opaque (the X byte is ignored by the frame reader
anyway), and build.py's output is checked for that below.

Output is reproducible run to run: gzip level 9, mtime 0, no name in the
header. The RAW frame is byte-identical to `magick IN.png -depth 8 bgra:-`,
which is how the frames were first produced and checked (2026-09-21); the
gzip stream around it is zlib's, not GNU gzip's, so the .gz itself differs
from `gzip -9n`'s by a few dozen bytes. Only the raw bytes reach the screen.
"""
import gzip
import struct
import sys
import zlib


def die(msg):
    sys.exit(f"png2raw.py: ERROR: {msg}")


def decode_png(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        die("not a PNG")
    pos, idat, hdr = 8, [], None
    while pos + 8 <= len(data):
        (n,) = struct.unpack(">I", data[pos:pos + 4])
        typ, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if typ == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat.append(body)
        elif typ == b"IEND":
            break
    if hdr is None:
        die("no IHDR")
    w, h, depth, ctype, _, _, interlace = hdr
    if depth != 8 or ctype not in (2, 6) or interlace != 0:
        die(f"unsupported PNG (bit depth {depth}, colour type {ctype}, "
            f"interlace {interlace}); only 8-bit RGB/RGBA non-interlaced")
    bpp = 4 if ctype == 6 else 3
    stride = w * bpp
    raw = zlib.decompress(b"".join(idat))
    if len(raw) != h * (stride + 1):
        die("IDAT length does not match the header")
    out, prev, p = bytearray(), bytearray(stride), 0
    for _ in range(h):
        ft, line = raw[p], bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if ft == 1:      # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:    # Average
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + (a + prev[i]) // 2) & 255
        elif ft == 4:    # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        elif ft != 0:
            die(f"bad filter type {ft}")
        out += line
        prev = line
    return w, h, bpp, bytes(out)


def to_bgrx(w, h, bpp, px):
    if bpp == 4 and set(px[3::4]) != {255}:
        die("frame is not fully opaque; build.py is meant to emit opaque frames")
    n = w * h
    frame = bytearray(n * 4)
    frame[0::4] = px[2::bpp]      # B
    frame[1::4] = px[1::bpp]      # G
    frame[2::4] = px[0::bpp]      # R
    frame[3::4] = b"\xff" * n     # X: what magick's bgra: wrote for opaque input
    return bytes(frame)


def main(argv):
    if len(argv) != 3:
        die("usage: png2raw.py IN.png OUT.raw.gz")
    with open(argv[1], "rb") as f:
        w, h, bpp, px = decode_png(f.read())
    frame = to_bgrx(w, h, bpp, px)
    with open(argv[2], "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f,
                           compresslevel=9, mtime=0) as gz:
            gz.write(frame)
    print(f"png2raw.py: {argv[1]} -> {argv[2]} ({w}x{h}, {len(frame)} raw bytes)")


if __name__ == "__main__":
    main(sys.argv)
