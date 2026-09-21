# SD-card installer splash artwork

The picture the first-boot installer puts on HDMI while it reformats the card
(ADR 0020 §9, `board/mister/de10nano/installer-overlay/init`, "THE HDMI SPLASH").
Drawn by `itsalive image` (package/itsalive), which blits raw pixels and neither
decodes nor scales, so the artwork goes into the cpio **rendered per video mode**
as gzipped raw BGRX8888 frames. Those frames are **not committed**: they are pure
derivations of the PNGs here, and `../installer-post-build.sh` produces them at
build time with `png2raw.py` (below).

| File in the cpio (`/usr/share/mister-installer/`) | Mode | Raw size | Source here |
|---|---|---|---|
| `splash-1280x720.raw.gz` | `itsalive up --mode 720p` (default) | 1280 × 720 × 4 = 3 686 400 B | `splash-1280x720.png` |
| `splash-640x480.raw.gz`  | `itsalive up --mode 480p` (`mister_installer_video=480p`) | 640 × 480 × 4 = 1 228 800 B | `splash-640x480.png` |

Both compress to under 20 KB, which is why the cpio carries both rather than
choosing at build time.

## What is in this directory

- `build.py` — composes the two PNGs from `kun32.png` and text, on a 320-cell
  pixel-art grid blown up with nearest-neighbour scaling so both sizes share one
  layout and stay crisp. Needs ImageMagick 7 (`magick`) and the DejaVu Sans Bold
  font. Keeps everything load-bearing inside the middle 90 % (overscan-safe).
- `kun32.png` — the 32×32 full-colour 8-bit MiSTer Kun sprite, rendered from
  `upstream/8-bit_mister_kun_fullcolor_32x32.svg`.
- `splash-1280x720.png`, `splash-640x480.png` — the composed frames. These ARE the
  source of the shipped picture (there is no vector form of the composition, only
  of the mascot), so they are committed; a reviewer sees what ships without
  running anything.
- `png2raw.py` — the build-time converter: 8-bit RGB/RGBA non-interlaced PNG →
  gzipped raw BGRX8888, Python standard library only. Its raw output is
  byte-identical to the ImageMagick pipeline below (checked 2026-09-21; the gzip
  wrapper differs, zlib vs GNU gzip, and does not matter). `installer-post-build.sh`
  runs it and asserts each frame's raw byte count.
- `upstream/` — the MiSTer Kun sources and their licence, verbatim from
  [baxysquare/mister_kun](https://github.com/baxysquare/mister_kun) (the 8-bit
  SVG/PNG variants, `LICENSE`, `README.md`).

## Changing the picture

```sh
cd board/mister/de10nano/installer-splash
python3 build.py                                   # -> splash-1280x720.png, splash-640x480.png
# what the build will ship, for a look before committing:
python3 png2raw.py splash-1280x720.png /tmp/x.raw.gz && zcat /tmp/x.raw.gz | wc -c   # 3686400
```

Keep `build.py`'s output 8-bit RGBA, non-interlaced and fully opaque, which is what
`png2raw.py` accepts (anything else fails the installer build loudly rather than
guessing). The equivalent ImageMagick pipeline, if you want to cross-check the
converter, is `magick splash-$s.png -depth 8 bgra:- | gzip -9n`: `bgra:` is
ImageMagick's name for the byte order MiSTer_fb wants (B, G, R, then a padding
byte the frame reader ignores), and `-n` keeps gzip reproducible.

## Licence

- The MiSTer Kun mascot was created by GitHub user **HeWhoisRed** for the MiSTer
  FPGA project as "a gift to the MiSTer community", to be used and remixed as
  people wish, with attribution appreciated -- see `upstream/LICENSE`. The 8-bit
  sprite is baxysquare's remaster under the same terms. This directory and the
  shipped frames credit both here and in `README.md` ("License layering").
- `build.py` and the composition are part of this repository (GPLv3, like every
  other script here). The artwork's terms are the mascot's, not GPLv3.
