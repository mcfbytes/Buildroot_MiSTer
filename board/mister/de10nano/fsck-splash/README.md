# Boot-time exFAT repair splash artwork

The picture the stage-1 initramfs puts on HDMI while it runs the repair that
`Scripts/check_storage.sh` scheduled (ADR 0026 §6,
`board/mister/common/initramfs-overlay/init`, `fsck_splash_show`). 8-bit Root Kun
inspects the card through a magnifying glass, one eye wide awake.

It is drawn by `itsalive image` exactly as the installer's splash is, so everything
in [`../installer-splash/README.md`](../installer-splash/README.md) about the raw
BGRX8888 format, the overscan rules, `png2raw.py` and the mascot's licence applies
here too. The differences:

| File in the cpio (`/usr/share/mister-fsck/`) | Mode | Source here |
|---|---|---|
| `splash-1280x720.raw.gz` | `itsalive up --mode 720p` (default) | `splash-1280x720.png` |
| `splash-640x480.raw.gz`  | `itsalive up --mode 480p` (`mister_fsck_video=480p` on the kernel command line) | `splash-640x480.png` |

- The frames are rendered by `package/mister-initramfs` (only with
  `BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE=y`, which also copies in `package/itsalive`),
  and `package/mister-initramfs/verify.sh` checks their raw sizes.
- The mascot is `art/root-kun-8bit-32x32.png` (from `art-src/gen.py`); `build.py`
  draws the magnifying glass onto it on the same 32×32 grid, then reuses the installer
  `build.py`'s layout helpers.

## Changing the picture

```sh
python3 board/mister/de10nano/fsck-splash/build.py   # -> splash-1280x720.png, splash-640x480.png
```

Needs ImageMagick 7 (`magick`) and the DejaVu Sans Bold font, like the installer's.
