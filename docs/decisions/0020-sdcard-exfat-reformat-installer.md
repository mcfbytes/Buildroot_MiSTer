# ADR 0020 — SD-card auto-resize is an mr-fusion-style exFAT reformat installer, not a static FAT32 partition (amends ADR 0017)

**Status:** Accepted (2026-07-17) — decided by @mcfbytes
**Amends:** ADR 0017 §Decision item 4 (which stands otherwise — see §4)
**Impact:** PLAN §8/§9 (Phase 5 `sdcard.img` deliverable); TASKS P5.3 (payload/mechanism
narrative superseded, "done when" criteria stand); new files
`configs/mister_installer_defconfig`, `board/mister/de10nano/installer-overlay/`,
`board/mister/de10nano/genimage-sdcard.cfg`, `scripts/fetch-sdcard-payload.sh`,
`scripts/mk-sdcard.sh`, `scripts/check-sdcard.sh`, `docs/verification/sdcard-payload.md`.

## 1. What ADR 0017 under-specified

ADR 0017 §Decision item 4 committed to a full SD-card image with a two-partition MBR —
`p1` = FAT32 data partition, `p2` = type `0xA2` boot partition — and described `p1`'s
*contents* (mr-fusion parity + `update_all.sh`) in detail. It did not address the
requirement PLAN.md's own opening line for the feature states: the image must
**auto-expand to fill any SD/USB medium the way mr-fusion does**. A card is shipped small
(so the compressed release asset stays small and the write is fast); the installed card
must use the *whole* device, whatever size the user's card happens to be.

ADR 0017's static `p1 = FAT32` layout has no mechanism to do that. This ADR supplies one.

### 1.1 Why "grow the filesystem" does not work

The obvious fix — ship a small FAT32 `p1`, then grow it in place on first boot, the way a
cloud-image `cloud-init` grows `p1` with `growpart` + `resize2fs` — does not apply here,
for a reason specific to this project:

* **MiSTer's data partition is exFAT, not FAT32 or ext4.** ADR 0010/0019 already commit
  this project to exFAT as the primary on-card filesystem (arcade-organizer symlinks,
  files above the FAT32 4 GiB limit, parity with every mr-fusion'd card in the wild).
* **Linux cannot grow exFAT in place.** There is no `resize.exfat`; `exfatprogs` ships
  `mkfs.exfat`/`fsck.exfat`/`dump.exfat` and nothing that extends a live filesystem's
  extent.
* A FAT32-only shipped image (grow-in-place candidate) would need to convert to exFAT
  *anyway* to reach parity with the rest of the project's exFAT decisions — at which point
  "reformat" is no longer avoidable, so there is no cheaper path left to try.

**Mr-fusion's own source confirms this is not a novel problem.** Mr-fusion does not grow a
filesystem either — it ships a throwaway installer OS whose first-boot job is to
**reformat** the card to the user's actual size
(`mr-fusion/builder/scripts/S99install-MiSTer.sh` + `entrypoint.sh`, upstream
[MiSTer-devel/mr-fusion](https://github.com/MiSTer-devel/mr-fusion)). This project adopts
the same mechanism rather than inventing an alternative, per the standing principle of
reusing a proven reference implementation over writing new code in a boot-path component.

## 2. Decision

1. **Replace ADR 0017's static `p1 = FAT32 data partition` with a throwaway installer OS
   that reformats the card to exFAT on first boot.** The shipped `sdcard.img` MBR keeps
   ADR 0017's `p2 = 0xA2` boot partition (`uboot.img` raw at its start, boot-chain §2.1)
   unchanged, but `p1` now holds an **installer kernel** (`linux/zImage_dtb` = our kernel
   relinked with a dedicated installer initramfs, `MISTER_INITRAMFS_CPIO`-style) plus the
   entire real payload staged under `mister-payload/` (not the final card contents
   directly), with `mister-payload/linux/linux.img` shipped **gzip-compressed** as
   `linux.img.gz` so it fits the installer's RAM budget (§3). The installer card ships
   **no `linux/u-boot.txt`** — an earlier draft put a `mem=` override there, but the stock
   `uboot.img` never reads it (§3).

2. **First boot reformats in RAM, then reboots into the real system.** The installer
   `/init`:
   - copies `mister-payload/*` off the shipped FAT32 partition into tmpfs (RAM) in full,
     before touching any partition table — the source data must survive the
     repartition it is about to trigger. `linux.img` travels as the small
     `linux.img.gz` (§3), so the RAM copy is on the order of ~150 MB, not ~700 MB;
   - reads the whole device's sector count from `/sys/block/<dev>/size` and `sfdisk`s a
     new table sized to the *actual* medium: `p2` keeps its reserved `0xA2` region
     (mirroring mr-fusion's ~8192-sector reservation), `p1` becomes exFAT type `0x07`
     sized to fill the remainder;
   - `mkfs.exfat -L MiSTer_Data` on the new `p1`, mounts it **`-t exfat` directly** — no
     FUSE, unlike mr-fusion's `mount.exfat-fuse`, because this project's kernel already
     carries in-kernel read-write exfat (ADR 0010) plus the symlink patch (ADR 0019);
   - copies the RAM-held payload back onto the fresh exFAT partition, then
     stream-`zcat`s `linux/linux.img.gz` to `linux/linux.img` **directly onto that
     partition** and removes the `.gz` — so the full 512 MiB image is written to disk,
     never staged in RAM (§3). This is where the **real** `linux/zImage_dtb` +
     `linux/linux.img` replace the installer's own boot kernel — see §2.1 for why that
     single fact is the primary re-run guard;
   - merges any optional user pre-seed the shipped FAT32 partition already had
     (`wpa_supplicant.conf`, `samba.sh`, `Scripts/*`, `config/`), mirroring mr-fusion's
     step 5;
   - generates a random **locally-administered** MAC (first octet: local-admin bit set,
     multicast bit clear) and writes `ethaddr=…` into a fresh `linux/u-boot.txt` **on the
     freshly-formatted exFAT partition** (the installed card's only `linux/u-boot.txt`) —
     so no installed board ever carries forward the compiled-in shared fallback
     `02:03:04:05:06:07` (boot-chain §3.1 entry 14);
   - `dd`s `uboot.img` onto the (unchanged-geometry) `0xA2` partition, `sync`s, reboots.

   Every step follows the defensive idiom already established by
   `board/mister/de10nano/initramfs-overlay/init`: on any fatal error, print a clear
   banner and drop to a rescue shell rather than panicking silently — a half-reformatted
   card must be diagnosable, not a second brick added on top of the first-boot problem
   this feature exists to solve. PID 1 never exits.

### 2.1 Re-run safety is structural, not a flag

Because the reformat **replaces** the FAT32 installer partition's `linux/zImage_dtb` with
a fresh exFAT partition holding the real `linux/zImage_dtb`, the installer kernel simply
does not exist anywhere on an installed card — U-Boot's `mmcload` finds the real kernel on
the next boot and the installer init never runs again. The explicit guard (skip if `p1` is
already exFAT, labelled `MiSTer_Data`, and contains `linux/linux.img`) is
belt-and-suspenders on top of that structural fact, not the primary defense — worth
recording because a future change to the reformat step must not silently remove the thing
that makes re-runs actually safe.

## 3. The RAM-transit constraint, and the finding that resolves it

Every byte of the payload passes through tmpfs twice (once out, once back) before landing
on the reformatted card, and the installer boots on the **stock, unmodified `uboot.img`**,
whose compiled-in environment caps Linux-visible RAM at `mem=511M`. `docs/boot-chain.md` §4
shows why that cap is effectively fixed: `mmcboot` builds the kernel command line with
`setenv bootargs … mem=511M memmap=513M$511M …` as a **literal string** — it never
interpolates a `mem=` environment variable — and the top ~513 MiB (the warm-reboot mailbox
region, §6.4) is deliberately walled off besides.

**An earlier draft of this ADR proposed lifting the cap with a `p1` `linux/u-boot.txt`
whose `mmcboot` override changed `mem=511M` to `mem=1024M`, "reclaiming" the full 1 GiB for
the RAM-transit. That does not work and has been dropped:** the stock binary never reads a
bare `mem=` env var (the string is literal), `scripts/mk-sdcard.sh` only ever wrote the
inert bare-`mem` form, and genuinely lifting the cap would mean rebuilding U-Boot (P5.1),
explicitly out of scope here (§4). The installer therefore has — and must live within —
~511 MiB, on the plain stock environment, with **no shipped `u-boot.txt`** (U-Boot's
`scrtest` `if test -e` guard makes the file's absence safe, boot-chain §4).

The single payload item that blows a 511 MiB budget is **`linux.img`**: a 512 MiB
*apparent-size* ext4 image (`BR2_TARGET_ROOTFS_EXT2_SIZE=512M`). It is sparse (~190 MB
actually used) on our ext filesystem, but FAT32 has no sparse support, so the shipped copy —
and any RAM copy — is the full 512 MiB, by itself larger than the whole `mem=511M` address
space. No amount of RAM tuning fixes that; it is impossible by construction.

**Resolution: ship `linux.img` gzip-compressed, and never transit it through RAM at full
size.** `scripts/mk-sdcard.sh` stores it as `mister-payload/linux/linux.img.gz` (~80 MiB —
the mostly-zero image compresses hard). The installer copies that small `.gz` through the
RAM tmpfs like any other file and then, only *after* the copy-back, streams
`zcat linux/linux.img.gz > linux/linux.img` **directly onto the freshly-formatted exFAT
partition** and deletes the `.gz`. The 512 MiB expansion is written to **disk**, never held
in RAM. This needs one addition to the installer BusyBox
(`board/mister/de10nano/installer-busybox.config`): `CONFIG_GUNZIP`/`CONFIG_ZCAT` (the
kernel's own `CONFIG_RD_GZIP` in `external.mk` is unrelated — it decompresses the
*initramfs*, not `linux.img`). It works on the **plain stock `mem=511M`**, with no U-Boot
change and no `u-boot.txt`.

With the RAM-transit budget correctly understood as **~511 MiB** and `linux.img` removed
from it, this bounds what the shipped payload may contain:

* **Base payload (mr-fusion parity + `update_all.sh`)** — the P0.6 `files/linux/`
  auxiliary payload, `MiSTer` + `menu.rbf` + `MiSTer.ini`, and the `Scripts/` set — is,
  once `linux.img` is the ~80 MiB `.gz`, on the order of ~150 MiB as it sits in RAM (the
  `.gz` plus the installer kernel, `menu.rbf`, `MiSTer`, soundfonts, scripts). Fits
  comfortably under ~511 MiB with margin for the kernel + initramfs + working buffers.
* **`SDCARD_CORES=1` (the `_Console` set from `MiSTer-devel/Distribution_MiSTer`)** adds
  on the order of 150–200 MiB (~40–60 `.rbf` files at ~1.5–3 MiB each; cores compress
  poorly and are shipped uncompressed, so they *do* transit RAM). Base + `_Console`
  together are ~300–350 MiB in RAM, still under ~511 MiB — so **both the default and the
  `SDCARD_CORES=1` variant use the exact same installer and both auto-resize.** There is no
  "cores are too big to RAM-transit" fallback design to maintain.
* **Safety valve, not a design fork.** The installer still measures free RAM against the
  staged payload size before copying and, if a larger core set would not fit, skips the
  cores with a loud console message and installs the base payload anyway — a degraded,
  diagnosable outcome rather than an OOM mid-reformat. The baked core set is size-capped
  (`scripts/check-sdcard.sh`, ~600 MiB on the `_Console` subtree) to keep this valve
  theoretical rather than something the median `SDCARD_CORES=1` build trips; because the
  installer now *always* runs at the stock `mem=511M`, this valve is the sole runtime
  defense against an oversized future core set and must never be removed.
* Cores were always "ideal, not required": `update_all.sh` is on every installed card
  (base payload) and a first run brings the system fully current regardless of what a
  particular `sdcard.img` snapshot baked in.

## 4. What still stands from ADR 0017

Everything in ADR 0017 **except** the literal `p1 = FAT32 data partition` shape is
unchanged:

* **U-Boot stays the stock blob by default** (ADR 0017 §Decision items 3/5). This ADR does
  not touch that — the installer `dd`s the same hash-pinned `uboot.img` fetched by
  `scripts/fetch-sdcard-payload.sh` (reusing `release.yml`'s existing
  `STOCK_UBOOT_SHA256`/`STOCK_UBOOT_SIZE` verification, not a parallel fetch mechanism). No
  byte of the pinned binary is patched, built, or replaced, and — unlike an earlier draft
  (§3) — no companion `u-boot.txt` env override is shipped on the installer card either:
  the installer runs on the stock environment exactly as it comes. The from-source P5.1
  U-Boot build remains an explicit future opt-in, gated behind its own hardware matrix,
  exactly as before.
* **`sdcard.img.xz` is a separate release asset**, never folded into `release_*.7z`, never
  referenced by `db.json` (ADR 0017 §Decision item 4, restated by this ADR's §2 design and
  unchanged).
* **The 0xA2 boot-partition contract is untouched** — same partition type, same "SPL raw at
  its start" mechanism (boot-chain §2.1), same reason a wrong partition type bricks the
  board. The installer's `sfdisk` step re-creates this partition at the *same offset and
  size* it shipped with; only `p1`'s type/size is rewritten.
* **The default/shipped release channel (Downloader `release_*.7z`, `linux.img`,
  `zImage_dtb`, `configs/mister_de10nano_defconfig`) is completely untouched.** This
  feature adds a wholly separate asset and a wholly separate Buildroot output directory
  (`output-installer/`, mirroring `output-rt/`); nothing here changes what any existing
  build target produces.

`SDCARD_CORES` is new (not present in ADR 0017 at all): a build-time flag,
`SDCARD_CORES=0` (default) → `sdcard.img` (minimal, truest mr-fusion parity), `1` →
`sdcard-full.img` (base + `_Console`, §3). Both are opt-in-tag-controlled release outputs;
the cores variant is `workflow_dispatch`-gated in CI, not part of the default tagged
release build.

## 5. Alternatives considered

- **FAT32 grow-in-place (`fatresize`/manual FAT extension).** Rejected: still leaves the
  card FAT32, which regresses ADR 0010/0019's exFAT decisions (symlinks, 4 GiB file
  limit) for every SD-installed board — the reformat is strictly better *and* is the only
  path that reaches exFAT at all, so there is nothing grow-in-place would have saved.
- **Ship the full-size image pre-formatted for the largest supported card, pad with
  zeros.** Rejected: the compressed asset would still be enormous for anyone with a
  smaller card (the image is the size of the *card*, not the payload, before compression
  helps only with the zero-fill, not the copy time), and `SDCARD_CORES=1` would make this
  strictly worse. It also does not solve "user's card is *larger* than what we shipped
  for" at all — mr-fusion parity requires using the actual medium size.
- **A separate, fixed-size, non-resizing image just for `SDCARD_CORES=1`.** Considered and
  dropped once §3's RAM-transit arithmetic — with `linux.img` shipped gzipped and expanded
  to disk rather than RAM — showed base + `_Console` fits under the stock ~511 MiB ceiling
  — a second mechanism would have been unbudgeted complexity for a case that does not
  actually arise at the current core-set size.
- **FUSE `mount.exfat-fuse` (matching mr-fusion's own installer exactly).** Rejected as
  unnecessary: mr-fusion needed FUSE because its installer kernel predates or omits
  in-kernel exfat; this project's kernel already has ADR 0010's in-kernel exfat (rw) plus
  ADR 0019's carried symlink patch, so `mount -t exfat` on the installer is strictly
  simpler and drops a dependency mr-fusion could not avoid.

## Consequences

- A fourth Buildroot output directory, `output-installer/`, joins `output/`,
  `output-rt/`, `output-initramfs/` (Makefile wiring mirrors the existing `rt`/`initramfs`
  target pattern exactly — variables, `.PHONY`, help text, `clean`/`distclean` coverage).
- The installer is its own small static-musl rootfs
  (`configs/mister_installer_defconfig`, based on `configs/mister_initramfs_defconfig`)
  with `exfatprogs` and `util-linux` (`sfdisk`) added as target packages — the only new
  target-side runtime dependency this feature introduces, and it never ships in the
  Downloader-delivered `linux.img`.
- `docs/verification/sdcard-payload.md` (companion to this ADR) becomes the canonical,
  machine-checked inventory of the shipped FAT32 partition's contents;
  `scripts/check-sdcard.sh` diffs a loop-mounted image against it in CI, so drift between
  what `scripts/mk-sdcard.sh` actually stages and what this ADR describes fails a build
  rather than shipping silently.
- The installer-logic reformat path (sfdisk → mkfs.exfat → copy-back → MAC-gen) is
  testable against a scratch loopback disk image on a CI runner with no hardware, because
  none of it depends on the DE10-Nano SoC — only on `losetup`/`sfdisk`/`exfatprogs`
  existing on the runner. Real on-hardware boot (unique MAC survives reboot, `update_all`
  completes) stays P5.4, human-gated, exactly as ADR 0017 already scoped it.
- This ADR does not change any risk already recorded against the stock-blob U-Boot path
  in ADR 0017; it adds one new risk of its own — a botched `sfdisk`/`mkfs.exfat` sequence
  on first boot is now the single point where an install can go wrong on an otherwise-good
  card. The defensive-init requirement in §2 (banner + rescue shell, never a silent panic)
  is this ADR's mitigation, not a separate task.
- `scripts/mk-sdcard.sh` ships `mister-payload/linux/linux.img` **gzip-compressed** as
  `linux.img.gz` (§3); the installer stream-decompresses it onto the reformatted card. It
  does **not** ship a `p1` `linux/u-boot.txt` — only two `u-boot.txt`-shaped files exist in
  this design: the fetched `mister-payload/linux/u-boot.txt_example` (mr-fusion parity) and
  the installer-*generated* `linux/u-boot.txt` (per-board MAC) the reformat step writes onto
  the final exFAT card. `docs/verification/sdcard-payload.md` §1 is the canonical `p1`
  inventory and lists neither a `p1` `u-boot.txt` nor an uncompressed `linux.img`.
