# Reference materials (P0.2)

In-tree copy of `work/manifest.txt`. `work/` is gitignored (standing rule 1: no
binaries in git, ever), so the *provenance* of everything in it lives here instead —
source URLs, commit SHAs, hashes, and the exact command that produced each derived
artifact. If `work/` is deleted, this file is enough to rebuild it. Regenerate the
binary materials by following the "How to reproduce" line of each entry.

---

# work/ manifest — P0.2 Acquire reference materials

Generated: 2026-07-12 (session date), branch `phase0-recon`.

IMPORTANT: `work/` is listed in `.gitignore` (`work/` line) and is NEVER committed.
Nothing below is tracked by git. This file exists so that anyone can reconstruct
the entire contents of `work/` from source, without relying on the binary
artifacts themselves being checked in anywhere. Re-running the commands in the
"How to reproduce" line for each entry should reproduce a byte-identical (or,
for git clones, ref-identical) copy.

Tool versions used to produce this manifest (recorded for reproducibility):
  7z 26.00 (x64), git 2.53.0, debugfs 1.47.2 (e2fsprogs), curl.

--------------------------------------------------------------------------------
## 1. Downloaded release archive

### work/release_20250402.7z
- Source repo:      MiSTer-devel/SD-Installer-Win64_MiSTer (branch: master)
- File is committed directly in the repo (no GitHub Releases exist on this repo;
  `SD-Installer-Win64_MiSTer` ships binaries as tracked git blobs).
- Path in repo:      release_20250402.7z
- Git blob SHA:      c4822002f25751dc8875b8925fee89ab1397b694
- Introduced by commit: b8531c7848526d9a8227841923cc4a493cb6e631 ("Release 20250402.", 2025-04-02T12:29:24Z)
- Commit-pinned URL (verified HTTP 200 on 2026-07-11):
  https://raw.githubusercontent.com/MiSTer-devel/SD-Installer-Win64_MiSTer/b8531c7848526d9a8227841923cc4a493cb6e631/release_20250402.7z
- Size:   93,727,644 bytes
- MD5:    8dc3acae7d758a80a363fbd7ad31d95d   (matches the db.json `linux` entry byte-exact per docs/verification/stock-release-20250402.md)
- SHA-256: 5d087d9c501b2bc50aaf918146e7bf30e5981c08268d5a0e67a3233a4da642ba
- How acquired: this file was already present in `work/` before this task ran
  (pre-seeded per `docs/verification/stock-release-20250402.md`); re-downloaded
  hash was NOT re-fetched over the network in this session — the commit-pinned
  URL above was independently confirmed to resolve (HTTP 200) and to be the
  correct git blob for this exact filename/size in the source repo.
- How to reproduce: `curl -LO <commit-pinned URL above>` and verify MD5/SHA-256 above.

--------------------------------------------------------------------------------
## 2. Extracted release contents

### work/extracted/
- Derived from: `work/release_20250402.7z`
- How produced: `7z x work/release_20250402.7z -o work/extracted`
- Contents (top level): `files/linux/{linux.img, zImage_dtb, uboot.img, updateboot,
  MidiLink.INI, ppp_options, u-boot.txt_example, _samba.sh, _user-startup.sh,
  _wpa_supplicant.conf, gamecontrollerdb/, mt32-rom-data/, soundfonts/}`,
  `files/{MiSTer, menu.rbf, MiSTer_example.ini, Scripts/update.sh}`,
  and a Windows `.exe` SD-card-writer GUI (`MiSTer SD Card Utility.exe`, unused by us).
- The Downloader (`Downloader_MiSTer`) only ever extracts `files/linux/*` from an
  archive of this shape — see `docs/downloader-contract.md` (P0.6) /
  `docs/verification/stock-release-20250402.md`.

Individual file hashes of the pieces later tasks touch directly:

| File | Size | SHA-256 |
|---|---|---|
| files/linux/linux.img | 393,216,000 | 4acd6edaaeca7474b1f1be5e40dc0fb6828950dd6f8a033b4bcd8f26f8201a70 |
| files/linux/zImage_dtb | 7,380,857 | a6c7b1be0da9ba24a91bc1816737915d6a6cfba27c6c3025caded95167dc8dae |
| files/linux/uboot.img | 515,141 | e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64 |
| files/linux/updateboot | 407 | 6ff2d50a080e26d7173b61c52083e9cc42ca658db0c5031b4da1c45c74a562f2 |

How to reproduce: `7z x work/release_20250402.7z -o work/extracted` (no mount needed;
7z reads the ext4 `linux.img` as a container directly, per PLAN's note and confirmed
in `docs/verification/stock-release-20250402.md`).

--------------------------------------------------------------------------------
## 3. Full stock rootfs — work/imgroot/ (fixed in this task)

**Status before this task:** `work/imgroot/` held only a partial extraction
(MiSTer.version, /etc/fstab, /etc/init.d/*, /etc/inittab — 16 files, 1 symlink).
This did NOT satisfy P0.3/P0.5/P0.7, which need the full tree (`/usr/lib`,
`/usr/bin`, `/usr/sbin`, `/lib/firmware`, `/usr/lib/modules`) with SONAME symlink
chains intact.

**Fix applied:** the old partial tree was removed and replaced with a full
extraction using `debugfs rdump`, which (unlike some `7z` builds elsewhere) is
guaranteed to preserve symlinks as real filesystem symlinks and requires no
mount/root privileges:

```
debugfs -R "rdump / work/imgroot" work/extracted/files/linux/linux.img
```

- **Symlink check:** `find work/imgroot -type l | wc -l` → **767** real symlinks,
  confirmed correctly preserved (spot-checked `bin -> usr/bin`,
  `usr/lib/libc.so.6 -> libc-2.31.so`, `usr/lib/libcap.so -> libcap.so.2 ->
  libcap.so.2.48`, etc. — full SONAME symlink chains intact).
- **7z symlink behavior — spot-checked for the record:** a side-by-side test
  (`7z x linux.img -o<scratch> bin` and `... usr/lib/libc.so.6 usr/lib/modules`)
  showed that **this environment's 7z (26.00 x64) also preserves symlinks
  correctly** — both methods work here. `debugfs rdump` was used anyway because
  the task calls it the safer/guaranteed choice, and it also avoids any
  ownership/permission ambiguity 7z might introduce. Note: `debugfs rdump`
  prints many benign `Operation not permitted while changing ownership of ...`
  lines when run unprivileged (it tries to `chown` extracted files to their
  original in-image UID/GID, which requires root) — **all file *content* was
  written successfully**; these are ownership-restore warnings only, not data
  loss. Verified: zero non-ownership errors in the rdump log
  (`/tmp/.../scratchpad/debugfs-rdump.log`, sanitized of the chown lines,
  is empty). Full extracted-tree owner/group in `work/imgroot` is therefore the
  invoking user (mcf:mcf), not the image's original ownership — irrelevant for
  read-only inventory/inspection use (P0.3/P0.5/P0.7) but worth knowing if any
  later step cares about original uid/gid bits.
- **Verification checks (all pass):**
  - `work/imgroot/usr/lib/libc-2.31.so` exists (930,536 bytes) ✓
  - `work/imgroot/usr/lib/modules/5.15.1-MiSTer/` present with **52** `.ko.xz` ✓
  - `work/imgroot/usr/lib/firmware/` present with **66** files recursively
    (verification doc's prose figure of "72 files" is in the same ballpark;
    reconciling the exact count is P0.3's job — this task only confirms the
    directory is fully populated and browsable, which it is).
  - `work/imgroot/usr/bin` populated: 466 regular files + 235 symlinks
  - `work/imgroot/usr/sbin` populated: 145 regular files + 93 symlinks
  - `work/imgroot/bin/busybox` present (756,744 bytes)
- **Totals:** 10,830 regular files, 926 directories, 767 symlinks, 298 MiB total
  (consistent with the 375 MiB image at ~86% used per the verification doc's
  13.6% free-space figure — ext4 overhead accounts for the difference).

How to reproduce: `debugfs -R "rdump / work/imgroot" work/extracted/files/linux/linux.img`
(run as any user; ignore `Operation not permitted while changing ownership` lines).

--------------------------------------------------------------------------------
## 4. Derived boot-chain / kernel-config artifacts (pre-seeded, hashes recorded here)

These were produced during plan verification (`docs/verification/stock-release-20250402.md`,
"Reproduction" section) before this task ran. Recorded here for completeness/manifest
integrity, not re-derived in this session.

| File | Size | SHA-256 | Derivation |
|---|---|---|---|
| work/stock-linux.config | 113,239 | 02634008f20ac1e2e125be2702b212d41e72c34a318ebcaa854c0bee6a65eb5c | LZ4-decompress the zImage payload inside `zImage_dtb`, locate the `IKCFG_ST`/`IKCFG_ED` gzip block embedded by `CONFIG_IKCONFIG`, gunzip it → 4,246-line kernel `.config` |
| work/stock.dtb | 20,017 | 1e9655be4a7eb48d87030467810d77277b645d5fcb1c0118d0650caa2a074d1a | Carved from `zImage_dtb` at the zImage's declared-size offset (`loadaddr + *(loadaddr+0x2C)` = byte 7,360,840); DTB `totalsize` field (20,017) reaches exactly EOF, confirming a clean `cat zImage dtb` concatenation |
| work/stock.dts | 35,181 | d7b7c070f86fc2709e5bada85818a56766b481815cb6858c77bc3f1910119a18 | `dtc -I dtb -O dts work/stock.dtb` |
| work/uboot-proper.bin | 252,933 | c580b99ad1c5d256b75f6d33994583964d6ceb8c091037b470b55f1c0dccbdc2 | The U-Boot-proper uImage carved out of `uboot.img` at offset 256 KiB (0x40000), after the four 64 KiB SPL copies; embedded env recovered via `strings` on this blob at offset 0x40040 (see boot-chain section of the verification doc) |

--------------------------------------------------------------------------------
## 5. Git clones (new in this task)

All four cloned with full working trees (no `--depth`, except none were shallowed at
all — see per-repo notes). Commit SHAs below are exactly what `git -C <dir> rev-parse
HEAD` returned at clone time in this session (2026-07-11/12).

### work/Linux-Kernel_MiSTer
- URL:     https://github.com/MiSTer-devel/Linux-Kernel_MiSTer
- Branch:  **MiSTer-v5.15**  (confirmed correct: matches the shipped kernel banner
  "Linux version 5.15.1-MiSTer"; the repo also has `MiSTer-v5.13.12`, `MiSTer-v5.14`,
  and `origin` branches, which are older/unrelated)
- Clone command: `git clone --single-branch --branch MiSTer-v5.15 <url> work/Linux-Kernel_MiSTer`
  (full history fetched — no `--depth`; `--single-branch` only avoided fetching the
  other three branches' refs)
- HEAD commit: `f0fb626acadd07f0718934826b143b6e4c9ce81c` ("defconfig: enable macvlan
  support (#71)", 2026-07-08)
- `git rev-parse --is-shallow-repository` → **false** (genuinely full history, not shallow)
- Total commits reachable from HEAD: **113**
- Size on disk: 1.6 GiB (includes full `.git`)
- **Important structural finding for P0.4:** this repository is **not** a
  git-ancestry fork of torvalds/linux. `git tag -l` returns **zero tags** — there
  is no real `v5.15.1` git tag/ref, only commits whose *message* happens to say
  "v5.15.1" etc. The root commit (`e12ed6c19`, message "v5.13.12", no parents) is
  a **single squashed import of the entire 5.13.12 kernel.org source tree**
  (72,216 files, ~30.95M insertions, verified via `git show --stat`). Subsequent
  squash-style "version bump" commits (`v5.14`, `v5.14.5`, `v5.15.1` — the last
  being commit `aba1ef4c1`) replace the tree wholesale for each stock kernel.org
  point release MiSTer-devel rebased onto, and MiSTer's own patches are
  interleaved before/after those version-bump commits.
  - Commits after the last version-bump commit (`aba1ef4c1`, message "v5.15.1")
    to HEAD: **109 commits** (`git log --oneline aba1ef4c1..HEAD | wc -l`).
  - `git diff --stat aba1ef4c1..HEAD` shows 3,560 files changed / ~3.3M insertions
    — this huge number is **not** a red flag; it's dominated by two commits that
    vendor entire out-of-tree Realtek WiFi driver trees wholesale (class E per
    §4.1): `33ff5146a` ("Add rtl8821au/rtl8812au, rtl88x2bu, rtl8821cu, rtl8188eu,
    rtl8188fu WiFi drivers.", 2.56M insertions/2,548 files) and `3740d5b88`
    ("Backport rtl8812au rtl8821au rtl8821cu drivers from morrownr — issue #39
    (#40)", 942K insertions/1,687 files). The actual MiSTer-specific driver
    patches (fbdev, audio-spi, DTS, HID quirks, xone, exFAT) are individually
    small (tens to low-thousands of lines each) — see the shortstat table
    gathered during this task's spot check.
  - **Consequence for P0.4:** `git log v5.15.1..HEAD` as literally written in the
    task text will **not** work (no such tag). Use the SHA `aba1ef4c1` directly
    as the base, e.g. `git log aba1ef4c1..HEAD` (gives the 109 MiSTer-devel
    commits). But note `aba1ef4c1`'s **tree content**, not its git ancestry, is
    what should be diffed against a genuinely-fetched upstream `v5.15.1` tag
    from a real linux.git mirror (there is no shared commit graph to compute a
    true `git merge-base` against torvalds/linux — a content diff, or a
    `linux-5.15.y` stable-branch merge-base search as the task's fallback
    suggests, is the only valid approach). This repo has no upstream remote
    configured and no linux.org history at all beyond the squashed snapshots.
  - Confirmed present: `drivers/video/fbdev/MiSTer_fb.c`,
    `sound/drivers/MiSTer-audio-spi.c` (both added by commits inside the 109,
    "Implement MiSTer frame buffer device." and "Implement MiSTer audio driver.").
  - Confirmed Makefile version at HEAD: `VERSION = 5 PATCHLEVEL = 15 SUBLEVEL = 1`
    (matches banner).
- How to reproduce: `git clone --single-branch --branch MiSTer-v5.15 https://github.com/MiSTer-devel/Linux-Kernel_MiSTer work/Linux-Kernel_MiSTer`

### work/Main_MiSTer
- URL:     https://github.com/MiSTer-devel/Main_MiSTer
- Branch:  master
- Clone command: `git clone <url> work/Main_MiSTer` (full clone, default branch)
- HEAD commit: `14052d21612df6136992190c0d5d4cbccbd816a9` (2026-07-12 03:08:55 +0800)
- Size on disk: 127 MiB
- Confirmed present: `fpga_io.h`/`fpga_io.cpp`, `brightness.h`/`brightness.cpp`.
- `/dev/fb0` ioctl user identified: `video.cpp` — opens `/dev/fb0` and calls
  `ioctl(fb, FBIO_WAITFORVSYNC, &zero)` (lines ~3859, 3867); also drives the
  `MiSTer_fb` kernel module via its sysfs parameter file
  `/sys/module/MiSTer_fb/parameters/mode` (not an ioctl, but the same driver's
  control surface — relevant to P0.5's ABI contract).
- How to reproduce: `git clone https://github.com/MiSTer-devel/Main_MiSTer work/Main_MiSTer`

### work/Downloader_MiSTer
- URL:     https://github.com/MiSTer-devel/Downloader_MiSTer
- Branch:  main
- Clone command: `git clone <url> work/Downloader_MiSTer` (full clone, default branch)
- HEAD commit: `915315668b9460b0fcdfc728be8254fe698c479f` (2026-07-08 00:32:32 +0000)
- Size on disk: 15 MiB
- Confirmed present: `src/downloader/linux_updater.py`, `src/downloader/constants.py`
  (both feed P0.6's already-drafted `docs/downloader-contract.md`).
- How to reproduce: `git clone https://github.com/MiSTer-devel/Downloader_MiSTer work/Downloader_MiSTer`

### work/U-Boot_MiSTer
- URL:     https://github.com/MiSTer-devel/U-Boot_MiSTer
- Branch:  MiSTer
- Clone command: `git clone <url> work/U-Boot_MiSTer` (full clone, default branch
  is `MiSTer`)
- HEAD commit: `8dcc3484aac6f07314538e82530d446083085e12` (2021-11-12 23:23:26 +0800)
- Size on disk: 222 MiB
- Confirmed present (de10-nano board/env sources):
  `board/terasic/de10-nano/`, `configs/socfpga_de10_nano_defconfig`,
  `include/configs/socfpga_de10_nano.h`, `arch/arm/dts/socfpga_cyclone5_de10_nano.dts`.
- How to reproduce: `git clone https://github.com/MiSTer-devel/U-Boot_MiSTer work/U-Boot_MiSTer`

--------------------------------------------------------------------------------
## 6. Reproduction summary (full work/ rebuild from scratch)

```sh
mkdir -p work
curl -Lo work/release_20250402.7z \
  https://raw.githubusercontent.com/MiSTer-devel/SD-Installer-Win64_MiSTer/b8531c7848526d9a8227841923cc4a493cb6e631/release_20250402.7z
# verify: md5sum work/release_20250402.7z  ->  8dc3acae7d758a80a363fbd7ad31d95d

7z x work/release_20250402.7z -o work/extracted
debugfs -R "rdump / work/imgroot" work/extracted/files/linux/linux.img

git clone --single-branch --branch MiSTer-v5.15 https://github.com/MiSTer-devel/Linux-Kernel_MiSTer work/Linux-Kernel_MiSTer
git clone https://github.com/MiSTer-devel/Main_MiSTer                                            work/Main_MiSTer
git clone https://github.com/MiSTer-devel/Downloader_MiSTer                                       work/Downloader_MiSTer
git clone https://github.com/MiSTer-devel/U-Boot_MiSTer                                            work/U-Boot_MiSTer

# work/stock-linux.config, work/stock.dtb, work/stock.dts, work/uboot-proper.bin:
# see section 4 above for exact derivation steps (LZ4/IKCONFIG extraction, DTB
# carving at the zImage-declared offset, dtc decompile, uImage carving).
```
