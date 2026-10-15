#!/usr/bin/env python3
"""Build the boot-time exFAT repair splash screen (ADR 0026).

Same grid, palette, helpers and overscan rules as ../installer-splash/build.py,
whose layout this mirrors; the mascot is 8-bit Root Kun (art/), inspecting the
card through a magnifying glass.

  1280x720 -> 320x180 cells, scale 4
   640x480 -> 320x240 cells, scale 2
"""
import importlib.util
import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
KUN = os.path.join(REPO, "art", "root-kun-8bit-32x32.png")

_spec = importlib.util.spec_from_file_location(
    "installer_splash", os.path.join(HERE, "..", "installer-splash", "build.py"))
I = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(I)
run, sz, label, hazard = I.run, I.sz, I.label, I.hazard
BG, PINK, WHITE, DIM, BLACK, YELLOW, W = I.BG, I.PINK, I.WHITE, I.DIM, I.BLACK, I.YELLOW, I.W

STEEL = "#9aa3ad"
LENS = "#bfe6ff"
WOOD = "#8a5a36"


def inspector(out):
    """Root Kun with a magnifying glass over one eye, drawn on his own 32x32 grid."""
    cx, cy = 21, 15
    draw = [
        # handle first, so the rim sits on top of its end
        f"stroke {BLACK} stroke-width 4 line {cx + 4},{cy + 4} {cx + 9},{cy + 9}",
        f"stroke {WOOD} stroke-width 2 line {cx + 5},{cy + 5} {cx + 9},{cy + 9}",
        "stroke none",
        f"fill {BLACK} circle {cx},{cy} {cx + 6},{cy}",
        f"fill {STEEL} circle {cx},{cy} {cx + 5},{cy}",
        f"fill {LENS} circle {cx},{cy} {cx + 4},{cy}",
        # the magnified eye: wide awake, unlike the other one
        f"fill {WHITE} circle {cx},{cy} {cx + 3},{cy}",
        f"fill {BLACK} rectangle {cx - 1},{cy - 1} {cx + 1},{cy + 1}",
        f"fill {WHITE} point {cx - 1},{cy - 1}",
        f"fill {WHITE} point {cx - 3},{cy - 3}",
    ]
    run(["magick", KUN, "+antialias", "-draw", " ".join(draw), f"PNG32:{out}"])
    return out


def build(scale, ch, out):
    tmp = tempfile.mkdtemp(prefix="fsck-splash-")
    t = lambda n: os.path.join(tmp, n)

    safe_top = round(ch * 0.05)
    safe_bot = ch - safe_top - 4

    warn = label(t("warn.png"), "DO NOT POWER OFF", 272, 44, BLACK)
    ww, wh = sz(warn)
    calm = label(t("calm.png"),
                 "Big cards take a few minutes.  MiSTer starts by itself when it is done.",
                 280, 11, BLACK)
    cw, chh = sz(calm)

    calm_y = safe_bot - chh
    warn_y = calm_y - 7 - wh
    bar_top = warn_y - 8
    lip_top = bar_top - 4

    strip_y = safe_top + 1
    strip_h = 11

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

    draw = hazard(0, 0, W, 7)
    draw += [f"fill {BLACK}", f"rectangle 0,{lip_top} {W-1},{ch-1}"]
    draw += [f"fill {YELLOW}", f"rectangle 0,{bar_top} {W-1},{ch-1}"]
    base = t("base.png")
    run(["magick", "-size", f"{W}x{ch}", f"xc:{BG}", "-antialias",
         "-draw", " ".join(draw), f"PNG32:{base}"])

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

    head = label(t("head.png"), "INSPECTING...", col_w, head_h, PINK, "west")
    sub = label(t("sub.png"), "Checking and repairing your SD card.", col_w, sub_h, WHITE, "west")
    bubt = label(t("bubt.png"), "I'm counting every cluster.\nDon't make me lose count.",
                 col_w - 18, bub_h - 14, BLACK, "center", interline=3)
    slug = label(t("slug.png"), "SD CARD CHECK-UP", 120, strip_h, DIM, "west")
    cred = label(t("cred.png"), "MiSTer Kun by HeWhoisRed", 150, strip_h - 1, DIM, "east")

    cat = t("cat.png")
    run(["magick", inspector(t("kun.png")), "-scale", f"{cat_s}x{cat_s}", f"PNG32:{cat}"])

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
    shutil.rmtree(tmp)
    print(f"{os.path.basename(out)}: {W}x{ch} cells x{scale} | cat {cat_s} @y{cat_y} "
          f"| safe y {safe_top}..{safe_bot}, lowest ink {calm_y + chh}")


if __name__ == "__main__":
    build(4, 180, os.path.join(HERE, "splash-1280x720.png"))
    build(2, 240, os.path.join(HERE, "splash-640x480.png"))
