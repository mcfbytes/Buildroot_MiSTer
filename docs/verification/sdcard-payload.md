# `sdcard.img` FAT32 payload-partition inventory (P5.3 / ADR 0020)

This is the **canonical, exact** contents of `p1` — the FAT32 data partition — of the
*shipped* `sdcard.img` / `sdcard-full.img`, as staged by `scripts/mk-sdcard.sh` and
assembled by `board/mister/de10nano/genimage-sdcard.cfg`. `scripts/check-sdcard.sh`
loop-mounts `p1` and diffs its file listing against the fenced block(s) below — treat any
addition, removal, or rename here as a breaking change to that script and to
`scripts/mk-sdcard.sh`'s staging step, and update both together.

This is **not** the final installed card's layout. `p1`'s `mister-payload/*` subtree is
what the installer `/init` (`board/mister/de10nano/installer-overlay/init`) copies onto
the freshly reformatted exFAT partition **with the `mister-payload/` prefix stripped** —
see ADR 0020 §2. `p1`'s own `linux/zImage_dtb` (the installer kernel) never reaches the
installed card at all; it is discarded when the reformat replaces `p1` outright.

Directories are listed with a trailing `/`; everything else is a regular file. Paths are
relative to `p1`'s root.

## 1. Base inventory — always present (`SDCARD_CORES=0`, the default `sdcard.img`)

```
linux/
linux/zImage_dtb
mister-payload/
mister-payload/linux/
mister-payload/linux/linux.img.gz
mister-payload/linux/zImage_dtb
mister-payload/linux/uboot.img
mister-payload/linux/updateboot
mister-payload/linux/MidiLink.INI
mister-payload/linux/ppp_options
mister-payload/linux/u-boot.txt_example
mister-payload/linux/_samba.sh
mister-payload/linux/_user-startup.sh
mister-payload/linux/_wpa_supplicant.conf
mister-payload/linux/gamecontrollerdb/
mister-payload/linux/mt32-rom-data/
mister-payload/linux/soundfonts/
mister-payload/MiSTer
mister-payload/menu.rbf
mister-payload/MiSTer.ini
mister-payload/Scripts/
mister-payload/Scripts/update.sh
mister-payload/Scripts/update_all.sh
mister-payload/Scripts/wifi.sh
```

That is **24 entries** (7 directories, 17 files) for the base inventory. `check-sdcard.sh`
asserts this exact set for any image built with `SDCARD_CORES=0` (or unset).

### 1.1 Provenance of each top-level entry

| Path | Source | Pin |
|---|---|---|
| `linux/zImage_dtb` | Our kernel (`work/Linux-Kernel_MiSTer` build), relinked by `scripts/mk-sdcard.sh` with the installer initramfs (`configs/mister_installer_defconfig` + `board/mister/de10nano/installer-overlay/`) embedded via `MISTER_INITRAMFS_CPIO` | Built, not fetched — same kernel tree as `output/images/zImage_dtb`, different embedded cpio |
| `mister-payload/linux/linux.img.gz` | Our build, `output/images/linux.img`, shipped **gzip-compressed** | Built, not fetched — gzipped so the 512 MiB apparent-size image never has to transit the installer's `mem=511M` RAM tmpfs; the installer stream-decompresses it to `linux/linux.img` on the reformatted exFAT card (ADR 0020 §3) |
| `mister-payload/linux/zImage_dtb` | Our build, `output/images/zImage_dtb` — the **real** boot kernel, distinct from `linux/zImage_dtb` above | Built, not fetched |
| `mister-payload/linux/{uboot.img,updateboot,MidiLink.INI,ppp_options,u-boot.txt_example,_samba.sh,_user-startup.sh,_wpa_supplicant.conf}` and `{gamecontrollerdb,mt32-rom-data,soundfonts}/` (full subtrees) | `files/linux/*` inside the pinned stock archive | `STOCK_RELEASE_URL`/`STOCK_RELEASE_MD5`/`STOCK_RELEASE_SHA256`/`STOCK_RELEASE_SIZE` (`.github/workflows/release.yml`); `uboot.img`/`updateboot` additionally re-verified against `STOCK_UBOOT_SHA256`/`STOCK_UPDATEBOOT_SHA256` per `docs/reference-materials.md` |
| `mister-payload/MiSTer` | `files/MiSTer` inside the same pinned stock archive | Same `STOCK_RELEASE_*` pin as above (member the Downloader itself never extracts — `docs/downloader-contract.md` §5 — but this image is not the Downloader path) |
| `mister-payload/menu.rbf` | `files/menu.rbf` inside the same pinned stock archive | Same `STOCK_RELEASE_*` pin |
| `mister-payload/MiSTer.ini` | `files/MiSTer_example.ini` inside the same pinned stock archive, renamed | Same `STOCK_RELEASE_*` pin |
| `mister-payload/Scripts/update.sh` | `files/Scripts/update.sh` inside the same pinned stock archive | Same `STOCK_RELEASE_*` pin |
| `mister-payload/Scripts/update_all.sh` | `theypsilon/Update_All_MiSTer`, raw file at a pinned commit | Commit + sha256 recorded by `scripts/fetch-sdcard-payload.sh` (see its `renovate.json` entry) |
| `mister-payload/Scripts/wifi.sh` | `MiSTer-devel/Scripts_MiSTer`, `other_authors/wifi.sh` at a pinned commit | Commit + sha256 recorded by `scripts/fetch-sdcard-payload.sh` (see its `renovate.json` entry) |

`gamecontrollerdb/`, `mt32-rom-data/`, `soundfonts/` are copied wholesale from the stock
archive; `check-sdcard.sh` asserts each directory exists and is non-empty rather than
enumerating every file inside — their contents are already covered by the
`STOCK_RELEASE_SHA256` archive-level hash gate, so a second per-file enumeration here
would only duplicate that guarantee, not add one.

## 2. `SDCARD_CORES=1` addendum (`sdcard-full.img`)

Adds exactly one subtree on top of the base inventory in §1 — nothing in §1 is removed or
altered:

```
mister-payload/_Console/
mister-payload/_Console/*.rbf
```

The exact member list under `_Console/` is **not** hash-pinned (per ADR 0020 §2/PLAN.md
§"Cores" — the user waived caching for this opt-in set): it is whatever
`scripts/fetch-sdcard-payload.sh` fetches from `MiSTer-devel/Distribution_MiSTer` at the
snapshot commit it records in its own output/log for traceability. `check-sdcard.sh`
therefore checks this addendum by **pattern** (directory exists, every entry inside
matches `*.rbf`, total staged core-payload size is under the ≲600 MiB cap from ADR 0020
§3) rather than by an exact file-for-file diff — unlike §1, which is asserted exactly.

## 3. What `check-sdcard.sh` actually asserts

1. `sfdisk -d sdcard.img` shows **partition 1** (the `mmcblk0p1`-equivalent slot U-Boot's
   hardcoded `mmc_boot=1` unconditionally reads, boot-chain §4) as **FAT32 (`0x0c`)** — this
   is the load-bearing invariant; if the partitions are swapped, U-Boot's `mmcload` can
   never find `/linux/zImage_dtb` and the board fails to boot before the installer's own
   rescue-shell defenses can run — and **partition 2** as `0xA2` at the expected offset/size
   (ADR 0020 §4 — the `0xA2` region and its offset are unchanged from ADR 0017's original
   layout).
2. `cmp` of the `0xA2` partition's head (first 515,141 bytes) against the pinned
   `uboot.img` (`STOCK_UBOOT_SHA256`) — byte-identical.
3. Loop-mount the FAT32 partition; `find`-list it, sort, and diff against §1's fenced
   block exactly (both directions — no extra entries, no missing ones); for
   `SDCARD_CORES=1` builds, additionally apply §2's pattern check.
4. Nonzero exit on any mismatch — this script runs in CI and gates the release publish
   step in `.github/workflows/release.yml`.

This document is the single source of truth §3 diffs against; if `scripts/mk-sdcard.sh`'s
staging step changes what lands on `p1`, update this file in the same change.
