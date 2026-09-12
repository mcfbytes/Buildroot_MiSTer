# Verification of stock release `release_20260912` — a Main_MiSTer bump, and why we pinned it

Date: 2026-09-12. Companion to [`stock-release-20260907.md`](stock-release-20260907.md), which
remains the full analysis of stock's 6.18 era; this release changes almost nothing that document
measured, so this note records only the pin move and what actually differs.

## Why the pin moved

Linux-Kernel_MiSTer PRs #96/#97 (the Switch controller `" IMU"` suffix and the 5.15
`player1..4`/`home` LED names) were closed in favour of the Main_MiSTer-side fix,
Main_MiSTer #1307/#1308, merged 2026-09-12 and first shipped in **Release 20260912**. The
same PR that retires our kernel patches `0040`/`0041` therefore moves the stock payload pin, so a
tag-built `sdcard.img` never pairs a kernel emitting mainline names with a `files/MiSTer` that
only matches the old ones. (A first-boot `update_all.sh`/`update.sh` would fix that on its own;
the pin move keeps the shipped state consistent regardless.)

## 1. Artifact identity

| Item | `release_20260907` (previous pin) | `release_20260912` (pinned now) |
|---|---|---|
| SD-Installer commit | `76fd6f4ced6350b0ad56a7013b41526f47e3a2fb` | `cd80db9c0ab64ba38be95071a090a80c367d63cf` ("Release 20260912.", Sorgelig, 2026-09-12 13:01 UTC) |
| Volumes | `.001` 83,886,080 B + `.002` 34,050,686 B | `.001` 83,886,080 B (blob `1b6bd927…`, MD5 `2552d0d8…`) + `.002` 42,660,398 B (blob `85c72489…`, MD5 `70cc944b…`) |
| Joined archive | 117,936,766 B, MD5 `8cd4edca…`, sha256 `e5bea841…` | **126,546,478 B**, MD5 **`7cec2206e2a1133aa307c541219aa08f`**, sha256 `35fcbaca57cd2471b1d353f3dd4bae7c7e67256f8c5c8b2d6d5cbcc78269a7ea` |
| `Distribution_MiSTer` mirror (`linux_release_<date>.7z`) | exists, byte-identical | **none yet** on 2026-09-12; live db.json still `"linux": null` |
| Members | 24 | 24, same layout |
| `linux.img` | 393,216,000 B, modules `6.18.38-MiSTer`, `/MiSTer.version` `260907` | 393,216,000 B, modules still `6.18.38-MiSTer`, `/MiSTer.version` **`260912`** |
| `zImage_dtb` | 8,564,005 B | **8,626,429 B** — rebuilt from `MiSTer-v6.18` after PRs #93 (`LEDS_CLASS_MULTICOLOR`), #94 (`IP_NF_FILTER`), #95 (NSO N64/Genesis maps), #98 (`MiSTer_fb` `memremap()` check); the image-creator also took "Add missing firmwares" (`b02ec9a1f`) and "Add AIC8800 firmware" (`7843c7036`) |
| `files/MiSTer` | 1,162,128 B (CRC `2AD33899`) | **1,166,224 B** (CRC `20A80ACB`) — `strings` shows `(IMU)`, `:green:player-1`, `:blue:player-5` |
| `uboot.img` | sha256 `e2d46cf9…62a64`, 515,141 B | **identical** |
| `updateboot` | sha256 `6ff2d50a…562f2`, 407 B | **identical** |
| Upstream build inputs | `Linux_Image_creator_MiSTer` `d4e3f51` | `9d9ff03ad` ("Release 20260912.", 2026-09-12 12:55 UTC) |

## 2. What moved — exactly three members

`7z l -slt` on both joined archives, compared by path/size/CRC: **only** `files/MiSTer`,
`files/linux/linux.img` and `files/linux/zImage_dtb` differ. The 21 other members
(`MidiLink.INI`, `_samba.sh`, `_user-startup.sh`, `_wpa_supplicant.conf`, `gamecontrollerdb`,
`mt32-rom-data`, `ppp_options`, `soundfonts`, `u-boot.txt_example`, `uboot.img`, `updateboot`,
`menu.rbf`, `MiSTer_example.ini`, `Scripts/update.sh`, the `.exe`, …) are byte-identical.

Consequences for us:

- **Shipped payload:** `linux.img` and `zImage_dtb` are ours, never stock's, so the only shipped
  file this bump changes is `files/MiSTer` on `sdcard.img` (via `scripts/fetch-sdcard-payload.sh`).
  `files/linux/` as we ship it is unchanged.
- **Boot contract:** `uboot.img`/`updateboot` unchanged for the third release running, so the
  `STOCK_UBOOT_*`/`STOCK_UPDATEBOOT_*` pins hold ([`downloader-contract.md`](../downloader-contract.md) §8/§12).
- **Kernel-side parity docs** (`stock-release-20260907.md` §2–§5, `docs/kernel-recon/fork-sync-2026-09/`)
  are not invalidated: the module set is still `6.18.38-MiSTer`; the rebuilt `zImage_dtb` folds in
  the four merged PRs above, which our series already carries or does not need
  (`0039` = #95; #98's fix is in our `0001`; #93/#94 are config we already set).
  The next fork-sync increment picks up the branch head (`912aa5608`, "hid-playstation: fix
  warning.") in the normal way.

## 3. Verification run (2026-09-12, local)

With the new `STOCK_*` values exported exactly as `release.yml` now carries them:

```
scripts/verify-stock-payload.sh fetch-stock    → 2 volumes joined
scripts/verify-stock-payload.sh verify-stock   → size/MD5/SHA-256/internal-CRC all match
scripts/verify-stock-payload.sh extract-stock  → 13 files, files/linux/*
scripts/verify-stock-payload.sh verify-uboot   → uboot.img and updateboot byte-identical to stock
```

The joined volumes were also hashed independently before the script ran (same MD5/SHA-256), and
the previous pin's volumes were re-fetched and re-verified against the old values (117,936,766 B,
`8cd4edca…`) to make the member diff above a like-for-like comparison.

## 4. Places the pin lives (all moved together)

`.github/workflows/release.yml` (`STOCK_RELEASE_URL/MD5/SHA256/SIZE`, the source of truth),
`scripts/fetch-sdcard-payload.sh` (its `:=` defaults), `scripts/verify-stock-payload.sh` (the
example block in its header), `docs/ci.md` (stock-payload sourcing), `docs/reference-materials.md`
§1, `docs/renovate.md` (the "deliberately not managed" paragraph) and
`docs/downloader-contract.md` §11.1's dated note.
