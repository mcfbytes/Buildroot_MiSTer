#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes rtl/de25_splash_logo.hex: a 128x32 1-bit bitmap, one row per line, MSB = leftmost."""
import os

W, H = 128, 32
FONT = {  # 5x7, rows top to bottom, bit 4 = leftmost column
    "M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
    "i": [0x04, 0x00, 0x0C, 0x04, 0x04, 0x04, 0x0E],
    "S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
    "T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
    "e": [0x00, 0x00, 0x0E, 0x11, 0x1F, 0x10, 0x0E],
    "r": [0x00, 0x00, 0x16, 0x19, 0x10, 0x10, 0x10],
    "D": [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
    "E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
    "2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
    "5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
}

bmp = [[0] * W for _ in range(H)]


def text(s, scale, y0):
    width = len(s) * 6 * scale - scale
    x0 = (W - width) // 2
    for n, ch in enumerate(s):
        for r, bits in enumerate(FONT[ch]):
            for c in range(5):
                if bits & (0x10 >> c):
                    for dy in range(scale):
                        for dx in range(scale):
                            bmp[y0 + r * scale + dy][x0 + (n * 6 + c) * scale + dx] = 1


text("MiSTer", 3, 0)
text("DE25", 1, 24)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rtl", "de25_splash_logo.hex")
with open(out, "w") as f:
    for row in bmp:
        f.write("%032x\n" % int("".join(map(str, row)), 2))
