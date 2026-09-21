#!/usr/bin/env python3
"""Build the MiSTer first-install splash screen.

Composed on a 320-cell-wide pixel-art grid, then blown up with
nearest-neighbour scaling, so both outputs share one layout and stay crisp
as flat 32bpp with no scaling on the target.

  1280x720 -> 320x180 cells, scale 4
   640x480 -> 320x240 cells, scale 2

Overscan: nothing load-bearing outside the middle 90%, i.e. cells
x in [16,304) for both sizes, y in [9,171) at 720p and [12,228) at 480p.
"""
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
KUN = os.path.join(HERE, "kun32.png")

BG     = "#16162e"
PINK   = "#e98db8"
WHITE  = "#f0efef"
DIM    = "#7a7aa8"
BLACK  = "#010101"
YELLOW = "#ffd400"

FONT_B = "DejaVu-Sans-Bold"
W = 320


def run(cmd):
    subprocess.run(cmd, check=True)


def sz(p):
    o = subprocess.run(["magick", "identify", "-format", "%w %h", p],
                       capture_output=True, text=True, check=True).stdout
    return tuple(int(v) for v in o.split())


def label(path, text, w, h, fill, gravity="center", interline=1):
    run(["magick", "-background", "none", "-fill", fill, "-font", FONT_B,
         "-interline-spacing", str(interline),
         "-size", f"{w}x{h}", "-gravity", gravity, f"label:{text}",
         "-trim", "+repage", f"PNG32:{path}"])
    return path


def hazard(x0, y0, x1, y1, period=14, sw=7):
    h = y1 - y0
    ops = [f"fill {YELLOW}", f"rectangle {x0},{y0} {x1-1},{y1-1}", f"fill {BLACK}"]
    i = x0 - h - period
    while i < x1 + period:
        pts = [(i, y1), (i + sw, y1), (i + sw + h, y0), (i + h, y0)]
        pts = [(max(x0, min(x1, px)), py) for px, py in pts]
        ops.append("polygon " + " ".join(f"{px},{py}" for px, py in pts))
        i += period
    return ops


def build(scale, ch, out):
    tmp = os.path.join(HERE, f"_t{scale}")
    os.makedirs(tmp, exist_ok=True)
    t = lambda n: os.path.join(tmp, n)

    safe_top = round(ch * 0.05)
    safe_bot = ch - safe_top - 4

    # ---- text bitmaps first, so the layout can be driven by real ink -----
    warn = label(t("warn.png"), "DO NOT POWER OFF", 272, 44, BLACK)
    ww, wh = sz(warn)
    calm = label(t("calm.png"),
                 "It reboots itself when it is done.  Give it about a minute.",
                 280, 11, BLACK)
    cw, chh = sz(calm)

    # ---- bottom: warning bar, packed up from the safe bottom edge --------
    calm_y = safe_bot - chh
    warn_y = calm_y - 7 - wh
    bar_top = warn_y - 8
    lip_top = bar_top - 4

    # ---- top strip -------------------------------------------------------
    strip_y = safe_top + 1
    strip_h = 11

    # ---- middle: cat on the left, text stack on the right ---------------
    cat_px = 3 if ch < 210 else 4
    cat_s = 32 * cat_px
    cat_x = 18
    cat_y = lip_top - 4 - cat_s

    col_x = cat_x + cat_s + 12
    col_w = 302 - col_x

    head_h, sub_h = 26, 12
    gap1, gap2 = 4, 9
    bub_h = min(52 if ch < 210 else 72, cat_s - head_h - sub_h - gap1 - gap2)
    stack_h = head_h + gap1 + sub_h + gap2 + bub_h
    stack_y = cat_y + (cat_s - stack_h) // 2
    head_y = stack_y
    sub_y = head_y + head_h + gap1
    bub_y = sub_y + sub_h + gap2

    # ---- background ------------------------------------------------------
    draw = hazard(0, 0, W, 7)
    draw += [f"fill {BLACK}", f"rectangle 0,{lip_top} {W-1},{ch-1}"]
    draw += [f"fill {YELLOW}", f"rectangle 0,{bar_top} {W-1},{ch-1}"]
    base = t("base.png")
    run(["magick", "-size", f"{W}x{ch}", f"xc:{BG}", "-antialias",
         "-draw", " ".join(draw), f"PNG32:{base}"])

    # ---- speech bubble ---------------------------------------------------
    bub = t("bub.png")
    run(["magick", "-size", f"{col_w}x{bub_h}", "xc:none", "-antialias",
         "-draw", f"fill {BLACK} rectangle 0,0 {col_w-1},{bub_h-1} "
                  f"fill {WHITE} rectangle 2,2 {col_w-3},{bub_h-3}",
         f"PNG32:{bub}"])
    tw, th = 10, 16
    tail = t("tail.png")
    run(["magick", "-size", f"{tw}x{th}", "xc:none", "-antialias",
         "-draw", f"fill {BLACK} polygon {tw},0 {tw},{th} 0,{th//2} "
                  f"fill {WHITE} polygon {tw},3 {tw},{th-3} 4,{th//2}",
         f"PNG32:{tail}"])

    head = label(t("head.png"), "INSTALLING...", col_w, head_h, PINK, "west")
    sub = label(t("sub.png"), "Reformatting your SD card.", col_w, sub_h, WHITE, "west")
    bubt = label(t("bubt.png"), "Touch that switch\nand we start over.",
                 col_w - 18, bub_h - 14, BLACK, "center", interline=3)
    slug = label(t("slug.png"), "FIRST-TIME SETUP", 120, strip_h, DIM, "west")
    cred = label(t("cred.png"), "MiSTer Kun by HeWhoisRed", 150, strip_h - 1, DIM, "east")

    cat = t("cat.png")
    run(["magick", KUN, "-scale", f"{cat_s}x{cat_s}", f"PNG32:{cat}"])

    parts = [(cat, cat_x, cat_y)]
    _, sgh = sz(slug)
    parts.append((slug, 18, strip_y + (strip_h - sgh) // 2))
    crw, crh = sz(cred)
    parts.append((cred, 302 - crw, strip_y + (strip_h - crh) // 2))
    _, hh = sz(head)
    parts.append((head, col_x, head_y + (head_h - hh) // 2))
    _, sh = sz(sub)
    parts.append((sub, col_x, sub_y + (sub_h - sh) // 2))
    parts.append((bub, col_x, bub_y))
    parts.append((tail, col_x - tw + 2, bub_y + bub_h // 2 - th // 2))
    bw, bh = sz(bubt)
    parts.append((bubt, col_x + (col_w - bw) // 2, bub_y + (bub_h - bh) // 2))
    parts.append((warn, (W - ww) // 2, warn_y))
    parts.append((calm, (W - cw) // 2, calm_y))

    cmd = ["magick", base]
    for p, x, y in parts:
        cmd += ["(", p, ")", "-geometry", f"+{x}+{y}", "-composite"]
    cmd += ["-scale", f"{scale*100}%", "-alpha", "remove", "-alpha", "off",
            "-depth", "8", f"PNG32:{out}"]
    run(cmd)
    print(f"{os.path.basename(out)}: {W}x{ch} cells x{scale} | cat {cat_s} @y{cat_y} "
          f"| warn {ww}x{wh} @y{warn_y} | bar {bar_top}..{ch} | "
          f"safe y {safe_top}..{safe_bot}, lowest ink {calm_y + chh}")


if __name__ == "__main__":
    build(4, 180, os.path.join(HERE, "splash-1280x720.png"))
    build(2, 240, os.path.join(HERE, "splash-640x480.png"))
