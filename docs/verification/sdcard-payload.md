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
menu.rbf
mister-payload/
mister-payload/linux/
mister-payload/linux/linux.img.gz
mister-payload/linux/zImage_dtb
mister-payload/linux/7za
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
mister-payload/downloader.ini
mister-payload/Scripts/
mister-payload/Scripts/check_storage.sh
mister-payload/Scripts/mount_smb.sh
mister-payload/Scripts/update.sh
mister-payload/Scripts/update_all.sh
mister-payload/Scripts/update_linux_modernization.sh
mister-payload/Scripts/wifi.sh
```

That is **30 entries** (7 directories, 23 files) for the base inventory. `check-sdcard.sh`
asserts this exact set for any image built with `SDCARD_CORES=0` (or unset).

> **Changed 2026-08-01** — `menu.rbf` **added at the FAT root** (ADR 0020 §7). This is a
> second copy of `mister-payload/menu.rbf`, and the duplication is deliberate: the stock
> U-Boot's `fpgaload` reads `$core` (compiled-in `menu.rbf`) from the partition **root**,
> not from the payload subtree, so without a root copy the FPGA was never configured
> during the install and HDMI showed "no signal" for its whole duration. It cannot be
> given another name — `mmcload` runs `fpgacheck` *before* `scrtest`, so a `core=` in
> `linux/u-boot.txt` is imported only after the core has already been loaded.

> **Changed 2026-08-01** — two entries **added**, both of them this project's own
> update-channel configuration, staged by `stage_update_channel()` in
> `scripts/fetch-sdcard-payload.sh`:
>
> * `mister-payload/downloader.ini` — carries `[MiSTer] update_linux = false`,
>   which stops every normal Downloader run from applying *any* Linux image, and
>   reproduces Update All's own default database set so a freshly flashed card
>   still gets exactly the cores a stock card would. (Update All only seeds those
>   defaults when `downloader.ini` does **not** exist, so shipping the file
>   suppresses the seeding — reproducing the set is what keeps parity, and it
>   also makes Update All treat the file as already canonical and never rewrite
>   it.)
> * `mister-payload/Scripts/update_linux_modernization.sh` — the one Scripts-menu
>   entry that updates this project's Linux image.
>
> Together they make a freshly flashed card hold on to this project's Linux image
> across routine `update_all.sh` runs while still updating cores normally, with
> no user action at all. See ADR 0025, `docs/user/onboarding.md`, and the header
> comment above `stage_update_channel()`.
>
> Deliberately **not** in this inventory: a drop-in
> `downloader_mister_linux_modernization.ini`. A drop-in database registration can
> never outrank `[distribution_mister]` (base-ini sections precede drop-ins, and
> Update All pins the official database first), so it would buy no protection while
> putting our database into every core update. Nothing else is staged either — the
> updater keeps no state on the card. It may not be added here in any case:
> `check-sdcard.sh` diffs this block against the built image in **both** directions.

> **Changed 2026-08-17** — one entry **added**, taking the base inventory from 29 to 30:
> `mister-payload/Scripts/mount_smb.sh`
> ([docs/cifs-mount-fscache-probe.md](../cifs-mount-fscache-probe.md)), also staged by
> `stage_update_channel()`.
>
> It mounts a NAS share over SMB/CIFS. It ships because the community script for this job,
> `Scripts_MiSTer/cifs_mount.sh`, **cannot run on this image at all**: before doing any work
> it requires `fscache.ko` to be listed in `/lib/modules/$(uname -r)/modules.builtin`, and
> Linux 6.8 merged `fs/fscache/` into `fs/netfs/`, making `CONFIG_FSCACHE` a `bool` rather
> than a module target — so no kernel ≥ 6.8 records that name at all. It
> reports "The current Kernel doesn't support CIFS (SAMBA)" on a kernel whose CIFS is
> complete and working. Nothing in the image is missing; the probe is looking for the wrong
> thing. Ours asks `/proc/filesystems` instead, which is correct whether `cifs` is built in
> or modular, on any kernel version.
>
> Unlike `check_storage.sh` this is **not** a shim — it is self-contained on the card, and
> configured by `Scripts/mount_smb.ini` beside it (an existing `cifs_mount.ini` is read as a
> fallback, so migrating costs nothing). Its behaviour is gated by
> `scripts/test-mount-smb.sh`.
>
> It lands by the same one route as the other two, which are now a set of three.

> **Changed 2026-08-13** — one entry **added**, taking the base inventory from 28 to 29:
> `mister-payload/Scripts/check_storage.sh` ([ADR 0026](../decisions/0026-user-driven-exfat-fsck.md)),
> also staged by `stage_update_channel()`.
>
> It checks the exFAT data partition for damage and, if it finds any, offers to repair it on
> the next boot. exFAT has no journal and this box is never cleanly unmounted, so a power cut
> in the wrong millisecond can leave lost clusters that nothing ever cleans up. The repair
> itself lives in the initramfs — it is the only place it *can* live, since the rootfs is a
> file on the partition being repaired — and is never automatic.
>
> The staged file is a **shim**: the tool is `/usr/sbin/mister-fsck-exfat`, in the read-only
> rootfs, because a repair tool stored on the partition it repairs is unavailable in exactly
> the case it exists for, and because its other end is in the initramfs and the two must
> ship together. So this entry is stable and has no reason to change again.
>
> It lands by exactly the same route as `update_linux_modernization.sh` — the two are one
> set: `install.sh` installs both, `uninstall.sh --remove-script` removes both,
> `stage_update_channel()` stages both here, and `update_linux_modernization.sh` replaces
> either if it later goes missing (which is how users who onboarded before this feature
> existed get the menu entry).

> **Changed 2026-07-27** — two edits that happen to cancel out in the count.
> `mister-payload/linux/7za` was **added** (ADR 0023) and
> `mister-payload/linux/zImage_dtb-rt` was **removed** (ADR 0021, amended
> again). The RT beta kernel is a developer artifact and stays a manual
> download from the GitHub Release; shipping an unvalidated real-time kernel on
> every user's card bought nothing, since nothing on the card referenced it and
> `u-boot.txt` never selected it. Its **module trees still ride inside
> `linux.img.gz`**, so the download-and-drop-in workflow still works against a
> card built from this image.

### 1.1 Provenance of each top-level entry

| Path | Source | Pin |
|---|---|---|
| `linux/zImage_dtb` | Our kernel (`work/Linux-Kernel_MiSTer` build), relinked by `scripts/mk-sdcard.sh` with the installer initramfs (`configs/mister_installer_defconfig` + `board/mister/de10nano/installer-overlay/`) embedded via `MISTER_INITRAMFS_CPIO` | Built, not fetched — same kernel tree as `output/images/zImage_dtb`, different embedded cpio |
| `menu.rbf` (FAT **root**) | A byte-identical copy of `mister-payload/menu.rbf`, placed by `scripts/mk-sdcard.sh` step 4c | Not a second download and **not committed to this repo** — it is the stock file the payload fetch already staged, so it inherits the same `STOCK_RELEASE_*` pin and needs no Renovate manager of its own. This is U-Boot's `$core`: `fpgaload` reads it from the partition **root**, so without this copy the FPGA is left unconfigured for the entire install (ADR 0020 §7) |
| `mister-payload/linux/linux.img.gz` | Our build, `output/images/linux.img`, shipped **gzip-compressed** | Built, not fetched — gzipped so the 512 MiB apparent-size image never has to transit the installer's `mem=511M` RAM tmpfs; the installer stream-decompresses it to `linux/linux.img` on the reformatted exFAT card (ADR 0020 §3) |
| `mister-payload/linux/zImage_dtb` | Our build, `output/images/zImage_dtb` — the **real** boot kernel, distinct from `linux/zImage_dtb` above | Built, not fetched |
| `mister-payload/linux/7za` | Our build, `output/images/7za` — 7-Zip 26.02 built by `package/7zip`, **statically linked** | Built, not fetched. Lands at `/media/fat/linux/7za`, the path the Downloader hardcodes (`constants.py` `FILE_7z_util`) and otherwise fills by downloading p7zip **16.02, 2016-05-21** from `SD-Installer-Win64_MiSTer/raw/master/7za.gz`. Seeding it here means a card flashed from `sdcard.img` never performs that fetch at all. Static because this file lives on the persistent exFAT partition and outlives the rootfs that placed it — see ADR 0023 and `docs/downloader-contract.md` §4 |
| `mister-payload/linux/{uboot.img,updateboot,MidiLink.INI,ppp_options,u-boot.txt_example,_samba.sh,_user-startup.sh,_wpa_supplicant.conf}` and `{gamecontrollerdb,mt32-rom-data,soundfonts}/` (full subtrees) | `files/linux/*` inside the pinned stock archive | `STOCK_RELEASE_URL`/`STOCK_RELEASE_MD5`/`STOCK_RELEASE_SHA256`/`STOCK_RELEASE_SIZE` (`.github/workflows/release.yml`); `uboot.img`/`updateboot` additionally re-verified against `STOCK_UBOOT_SHA256`/`STOCK_UPDATEBOOT_SHA256` per `docs/reference-materials.md` |
| `mister-payload/MiSTer` | `files/MiSTer` inside the same pinned stock archive | Same `STOCK_RELEASE_*` pin as above (member the Downloader itself never extracts — `docs/downloader-contract.md` §5 — but this image is not the Downloader path) |
| `mister-payload/menu.rbf` | `files/menu.rbf` inside the same pinned stock archive | Same `STOCK_RELEASE_*` pin |
| `mister-payload/MiSTer.ini` | `files/MiSTer_example.ini` inside the same pinned stock archive, renamed | Same `STOCK_RELEASE_*` pin |
| `mister-payload/Scripts/update.sh` | `files/Scripts/update.sh` inside the same pinned stock archive | Same `STOCK_RELEASE_*` pin |
| `mister-payload/Scripts/update_all.sh` | `theypsilon/Update_All_MiSTer`, raw file at a pinned commit | Commit + sha256 recorded by `scripts/fetch-sdcard-payload.sh` (see its `renovate.json` entry) |
| `mister-payload/Scripts/wifi.sh` | `MiSTer-devel/Scripts_MiSTer`, `other_authors/wifi.sh` at a pinned commit | Commit + sha256 recorded by `scripts/fetch-sdcard-payload.sh` (see its `renovate.json` entry) |
| `mister-payload/downloader.ini` | **Ours**, `board/mister/de10nano/fat-payload/downloader.ini` | In-tree, not fetched. Sets `[MiSTer] update_linux = false` so no normal Downloader run can apply *any* Linux image — which is what stops the official `distribution_mister` entry from overwriting ours. Also declares the core databases explicitly — `distribution_mister` (canonical URL from the Downloader's own `constants.py`), `jtcores` and `update_all_mister` — because shipping the file suppresses Update All's own default seeding. `distribution_mister` **must** be explicit here: `_add_default_database` only auto-adds it when the base ini declares *no* databases, and this file declares some. Deliberately comment-free beyond a two-line header pointing at the docs; the explanation lives in `docs/user/onboarding.md`, since tooling rewrites this file and comments on database sections do not survive |
| `mister-payload/Scripts/update_linux_modernization.sh` | **Ours**, `board/mister/de10nano/fat-payload/Scripts/update_linux_modernization.sh` | In-tree, not fetched. The only thing that updates *our* Linux image. Runs the Downloader against its **own private ini**, generated at runtime under `Scripts/.config/mister_linux_modernization/` — in a directory of its own, because drop-in discovery globs the directory the resolved ini sits in, so an ini in `/media/fat` would pull the user's whole database list into a Linux-only run. One database, `update_linux = true`, plus `--run-only` as a fail-closed assertion. It does **not** install or depend on a drop-in database ini, and keeps no state on the card: the private ini is generated in `/tmp` per run. Separately, it repairs `[MiSTer] update_linux = false` in the user's `downloader.ini` on every run |

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

Because that check only runs against a built `sdcard-full.img` — and only `release.yml`'s
opt-in `SDCARD_CORES=1` leg ever builds one — the snapshot commit itself is validated much
earlier, when Renovate bumps it: `renovate-hash-sync.yml`'s cores-pin step
(`scripts/hash-sync-cores-pin.sh`) resolves the `_Console` listing at the newly-pinned commit
and fails the PR closed if it does not resolve, holds no `*.rbf`, or already busts the same
`$EXPECT_CORES_MAX_BYTES` cap this section describes. See
[`docs/ci.md#renovate-hash-sync-cores-pin`](../ci.md#renovate-hash-sync-cores-pin).

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
