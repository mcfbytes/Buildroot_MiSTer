# Kernel patch provenance & triage (P0.4)

Every change in `MiSTer-devel/Linux-Kernel_MiSTer` (branch `MiSTer-v5.15`,
HEAD `f0fb626acadd07f0718934826b143b6e4c9ce81c`, 2026-07-08) classified per `PLAN.md` §4.1,
with upstream status verified against **real Linux 6.18.38 source** (not from memory), and a
disposition for each.

This is the map that `P1.4`–`P1.9` consume. Every row is independently verifiable from the
cited commit SHA, `file:line`, or upstream commit.

**Status:** complete. All 109 fork commits accounted for; content diff reconciles exactly.

---

## 1. Method — how the baseline was established

### 1.1 The problem with the task as originally written

`TASKS.md` P0.4 says "enumerate every commit not in upstream `v5.15.1`", implying
`git log v5.15.1..HEAD`. **That command cannot work.** The fork is *not* a git-ancestry fork
of `torvalds/linux`:

* `git -C work/Linux-Kernel_MiSTer tag -l` → **zero tags**. There is no `v5.15.1` ref.
* The root commit `e12ed6c19` ("v5.13.12", no parents) is a **single squashed import** of the
  entire 5.13.12 source tree (72,216 files).
* "Version bump" commits (`137491a75` v5.14, `b6f2ca1c4` v5.14.5, `aba1ef4c1` v5.15.1) replace
  the tree wholesale. There is no shared commit graph with mainline, so no `merge-base` exists.

Commit ancestry is therefore only good for **provenance** (who/when/why). It cannot be trusted
for **completeness**. Completeness requires a *content* diff against a genuine upstream tree.

### 1.2 Baseline: a pristine, hash-verified v5.15.1

```sh
curl -o work/linux-5.15.1.tar.xz https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.15.1.tar.xz
curl -o work/sha256sums-5.15.1.asc https://cdn.kernel.org/pub/linux/kernel/v5.x/sha256sums.asc
sha256sum work/linux-5.15.1.tar.xz
# 32fdcd33c8ac571b9a7a297f33860f6171327961f2a2ea6bd54bf82275b614c8
# -- matches kernel.org's signed sha256sums.asc entry for linux-5.15.1.tar.xz  ✓
tar xf work/linux-5.15.1.tar.xz -C work/
```

Both trees were then reduced to `path → (mode, git blob SHA)` listings and compared. Blob SHA
equality is exact content equality:

```sh
# pristine side
cd work/linux-5.15.1 && git init -q . && git add -Af . && git ls-files -s   # 73,614 files
# fork side
git -C work/Linux-Kernel_MiSTer ls-tree -r aba1ef4c1    # 73,603 files
git -C work/Linux-Kernel_MiSTer ls-tree -r HEAD         # 77,061 files
```

### 1.3 Load-bearing finding: `aba1ef4c1` lands a PRISTINE v5.15.1 tree

Comparing `aba1ef4c1`'s tree against pristine v5.15.1:

| Result | Count |
|---|---|
| Files with **differing content or mode** | **0** |
| Files **added** by MiSTer at/before the bump | **0** |
| Files **missing** from the fork | 11 |

**Zero content differences and zero added files.** The version-bump commit lands an unmodified
upstream tree. **Therefore the 109 commits after `aba1ef4c1` are the complete MiSTer delta** —
nothing is hidden inside the squashed import.

The 11 missing files are an artefact of MiSTer's original import, not a MiSTer change:

```
Documentation/devicetree/bindings/.yamllint      tools/testing/selftests/arm64/tags/.gitignore
fs/ext4/.kunitconfig                             tools/testing/selftests/arm64/tags/Makefile
fs/fat/.kunitconfig                              tools/testing/selftests/arm64/tags/run_tags_test.sh
lib/kunit/.kunitconfig                           tools/testing/selftests/arm64/tags/tags_test.c
tools/perf/include/perf/perf_dlfilter.h          tools/testing/selftests/bpf/test_progs.c
                                                 tools/testing/selftests/tc-testing/plugins/__init__.py
```

Evidence they are import noise, not deletions: they are **absent from the root commit
`e12ed6c19`** and **never touched by any commit** (`git log --all -- <path>` → empty). None is
`.gitignore`d (`git check-ignore` → no match on any of them). All 11 are KUnit configs, lint
configs, userspace `perf`, or selftests — **none is compiled into a kernel image**. Zero impact.

### 1.4 The authoritative delta: HEAD tree vs pristine v5.15.1

| | Count |
|---|---|
| **Added** | 3,485 files (3,428 = vendored Realtek WiFi trees, class E) |
| **Removed** | 38 files (11 import artefacts + 15 `scripts/gdb/linux/*.py` + 12 mainline `fs/exfat/*`) |
| **Modified** | 48 files |

Excluding the vendored WiFi trees, the entire MiSTer delta is **57 added + 38 removed +
48 modified = 143 files.** That is the real size of the problem.

### 1.5 Reconciliation (content diff ⟷ commit list) — exact

Cross-checked in both directions:

* **In the content diff but touched by no commit:** exactly the 11 import artefacts (§1.3). ✓
* **Touched by a commit but not in the final diff:** 149 files — 148 under
  `drivers/net/wireless/realtek/` (added by `33ff5146a`, later replaced by the morrownr
  backport `3740d5b88`) and `fs/exfat/exfat_config.h` (added by `df35bdb27`, removed by
  `7f7148c1f`). All transient-by-construction. ✓

No unexplained residue in either direction.

### 1.6 Upstream verification

```sh
git clone --single-branch --branch linux-6.18.y \
  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git work/linux-stable
git -C work/linux-stable describe --tags   # v6.18.38
```

Every "drop — upstream" claim below was checked by grepping the **actual 6.18.38 source** for
the specific VID/PID, symbol, or code path — and, where merged, the introducing commit was
recovered with `git log -S<string> --reverse -- <path>`. Device IDs were checked **one by one**:
a driver existing upstream does not mean MiSTer's IDs are in it. (This caught the NSO Famicom
and Elite 2 paddle gaps — see §3.)

> **Methodology note / trap for reviewers.** An early sweep here used a buggy shell helper that
> passed the grep pattern twice, so `grep` exited 2 on a nonexistent file and every probe
> reported "ABSENT". It produced confident false negatives for `BTN_GRIPL`, `ABS_PROFILE`, the
> 8BitDo Ultimate, and the Xbox Elite 2 — all of which *are* upstream. Every "ABSENT" below was
> re-derived with a corrected helper that prints the matching line. If you re-run this triage,
> print your matches; do not trust a bare boolean.

### 1.7 Correction to the plan's commit count

`PLAN.md` §4.1 and §14 say the fork carries **"~60 commits"**. The real number is **109**
commits after the last version bump (113 total including the four squashed imports). The
delta is larger than the plan assumes, though the *carried* set is smaller than 109 — see the
histogram. **Recommendation for P0.9: change "~60" to "109" in PLAN.md §4.1, §12 and §14.**

### 1.8 Class histogram (all 109 commits)

| Class | Commits | Disposition |
|---|---|---|
| **A** — MiSTer core (fb / audio / cpufreq) | 4 | carry → `0001`–`0003` |
| **A** — DTS + `socfpga.dtsi` | 13 | carry → `0004` |
| **A** — `MiSTer_defconfig` | 11 | **not a patch** — input to P1.3 |
| **B** — `loop=` root patch | 1 | **delete** — replaced by initramfs (§5) |
| **C** — HID, now upstream | 22 | **drop** (each cites a mainline commit) |
| **D** — HID/input, still out-of-tree | 30 | carry → `0010`+ |
| **D** — xone | 7 | **re-source** as `package/xone` (medusalix) |
| **E** — Realtek USB WiFi | 9 | **re-source** as `package/rtl*` (morrownr) |
| **F** — misc quirks | 5 | 1 drop, 1 no-op, 3 carry |
| **G** — exfat replacement *(new class — not in PLAN §4.1)* | 6 | **decision required** — see §5 |
| noise | 1 | dismissed |
| **Total** | **109** | |

---

## 2. New findings that are NOT in PLAN.md

Four things this triage found that the plan does not model. Two are high-severity.

### N1 — The fork REPLACES mainline exfat with the out-of-tree Samsung driver, which supports **symlinks** and **FAT12/16/32** (HIGH)

`8b6b8c2f5` "Remove original exFAT driver" deletes all 12 mainline `fs/exfat/*.c|h` files;
`df35bdb27` "Add exFAT with symlinks support" drops in the old Samsung/`exfat-nofuse` driver
(`exfat_core.c`, `exfat_super.c`, `exfat_oal.c`, …). Proof it is the out-of-tree driver and not
mainline's: the **stock kernel config** carries its Kconfig symbols, which mainline has never
had —

```
CONFIG_EXFAT_DISCARD=y            CONFIG_EXFAT_DELAYED_SYNC=y
CONFIG_EXFAT_DEFAULT_CODEPAGE=437 CONFIG_EXFAT_DEFAULT_IOCHARSET="utf8"
```
(`docs/stock-inventory/stock-linux.config`; mainline 5.15/6.18 `fs/exfat/Kconfig` has only
`EXFAT_FS` and `EXFAT_DEFAULT_IOCHARSET`.)

Three consequences, all user-visible:

1. **Symlinks on `/media/fat` work today and will not on mainline exfat/vfat.**
   `fs/exfat/exfat_super.c:676` `exfat_symlink()`, `:1088` `.symlink`, `:1111`
   `exfat_symlink_inode_operations`. Mainline exfat has **no symlink support at all**
   (`grep symlink linux-6.18.38/fs/exfat/*.c` → empty); nor does vfat.
   Symlinks are stored in the **FAT `ATTR_SYSTEM` (0x04) attribute bit** — deliberately, so
   Windows preserves them on copy (commit `99a2c80d0`: *"use ATTR_SYSTEM as symlink flag to
   preserve links while copying on Windows or other OS"*, `fs/exfat/exfat_api.h:65`). Because
   it is a generic FAT directory-entry attribute, **symlinks work on FAT32 and exFAT alike**.
   **Main_MiSTer consumes them:** `Main_MiSTer/file_io.cpp:1592` —
   `// Handle (possible) symbolic link type in the directory entry` — `stat()`s `DT_LNK`
   entries and resolves them to `DT_REG`/`DT_DIR`. Added Jan 2019 by Sorgelig
   (`Main_MiSTer` commit `325f6b6` "Improved handling of symbolic links"). Community setups
   that symlink `games/` folders onto USB/network storage depend on this.

2. **The `exfat` driver also mounts FAT12/16/32** (`fs/exfat/exfat_core.c:30` —
   *"PROJECT : exFAT & FAT12/16/32 File System"*). This is why the class-B kernel patch can
   hardcode `init_mount(..., "exfat", ...)` for a FAT32 SD card (§4).

3. **Filename encoding differs.** Stock mounts *both* FAT32 and exFAT through this driver with
   `iocharset=utf8` (`EXFAT_DEFAULT_IOCHARSET`). Mainline vfat defaults to
   `CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"` (also stock's value — but stock's vfat driver is
   never used for `/media/fat`). If P1.10 mounts FAT32 with mainline `vfat` and default
   options, **non-ASCII filenames will be decoded differently** (mojibake in the file browser,
   broken paths). P1.10 must mount vfat with `-o iocharset=utf8` (and/or set
   `CONFIG_FAT_DEFAULT_UTF8=y`).

**Disposition: decision required at P0.9.** Options:
* **(a) Accept the regression** — use mainline exfat + vfat, lose symlinks on `/media/fat`,
  fix encoding with mount options. Cheap. Silently breaks an existing user-visible feature.
* **(b) Carry the out-of-tree driver** — forward-port a 2012-era Samsung driver
  (`user_namespace`→`mnt_idmap`, folio-based `address_space_operations`, `iov_iter` churn) to
  6.18. Large, ongoing maintenance burden; exactly the kind of hot-file patch §5 exists to
  eliminate.
* **(c) Add symlink support to mainline exfat** as a small carried patch, using the same
  `ATTR_SYSTEM` encoding, so on-disk links stay compatible. Smallest patch that preserves the
  ABI. Plausibly upstreamable.

This is the largest single unknown left in the plan and it is not currently budgeted anywhere.

### N2 — PLAN §13 mis-describes the `altspi`/spidev hazard (mechanism, not severity)

§13 says *"There is no `altspi` driver anywhere in MiSTer's kernel — `spidev` is binding it as
a catch-all."* **That is not what happens.** MiSTer explicitly patched spidev's match table:

```c
/* work/Linux-Kernel_MiSTer/drivers/spi/spidev.c:699 — added by commit 246984fce */
    { .compatible = "micron,spi-authenta" },
+   { .compatible = "altspi" },
```

So `altspi` is an out-of-tree **one-line kernel patch**, not a catch-all bind. The *hazard is
still real and still fatal* — 6.18's spidev binds **only** compatibles listed in
`spidev_dt_ids[]` (`linux-6.18.38/drivers/spi/spidev.c:720`), so an unlisted `altspi` node
simply never probes: no `/dev/spidev1.0`, and `brightness.cpp` silently loses I/O-board
brightness control. But the fix framing changes: we already own both sides.
* **Preferred:** change the DTS `compatible` to one 6.18's spidev already accepts (zero kernel
  patches). Note 6.18's entries carry `.data = &spidev_of_check`; an entry without `.data` is
  fine (`spidev_probe()` skips the check when `device_get_match_data()` returns NULL).
* **Fallback:** re-carry the one-liner as `0005-…`.
Because we ship our own DTB, changing the compatible breaks nothing. **P1.8 should prefer the
DTS route.** (Plan text should be corrected at P0.9.)

### N3 — `/media/fat` is mounted `sync,dirsync` by the kernel, and nothing else remounts it (MEDIUM)

The class-B patch mounts the data partition with
`MS_DIRSYNC | MS_SYNCHRONOUS | MS_NOATIME | MS_NODIRATIME` (§4). The stock `/etc/fstab` has
**no `/media/fat` entry at all** (verified: `work/imgroot/etc/fstab`), so those flags are the
only ones it ever has. The §5 `/init` sketch mounts it with default (async) options.
**P1.10 must mount `/media/fat` `-o sync,dirsync,noatime,nodiratime` for parity**, or accept a
deliberate, documented change — writes to saves/configs would no longer be flushed
immediately, which changes power-off-corruption behaviour on a device users switch off at the
wall. This is a behavioural contract, not a performance tunable.

### N4 — MiSTer's ALSA card is a *patched `snd-dummy`*, and the real audio ABI is `/dev/MrAudio` (MEDIUM)

`TASKS.md` P1.5 says *"Card/device name exposed to userland must match stock (Main_MiSTer opens
it by name)"*. **Main_MiSTer does not open ALSA at all** (no `snd_pcm`/`asound` references in
the source). The actual contract is two-part:

1. `sound/drivers/dummy.c` is **patched** (commit `333d49b95`): `fake_buffer` flipped `1`→`0`
   and a `model_MiSTer` (S16_LE, 48 kHz, 2ch, 32 KiB buffer) force-selected as the default
   model. The card keeps snd-dummy's stock names — `card->driver`/`shortname` = `"Dummy"`,
   `longname` = `"Dummy 1"` (`dummy.c:1095-1097`, unmodified).
2. `sound/drivers/MiSTer-audio-spi.c` creates the char device **`/dev/MrAudio`** and DMAs PCM
   to the FPGA over SPI.

They are glued by **`/etc/asound.conf`** (`work/imgroot/etc/asound.conf`), which is the real
ABI:

```
pcm.!default { type plug; slave.pcm { type rate; slave {
  format S16_LE; rate 48000;
  pcm { type file; file "/dev/MrAudio"; format "raw"; slave.pcm { type hw; card 0 } } } } }
```

So: **ALSA card 0 must exist and accept S16_LE/48000/2ch** (satisfied by the patched
snd-dummy), and **`/dev/MrAudio` must exist and accept raw S16_LE 48 kHz stereo writes.**
`CONFIG_SND_DUMMY=y` and `CONFIG_SND_MISTER_AUDIO=y` are both required (verified in stock
config and in HEAD's `MiSTer_defconfig`). **`0002-…` must therefore contain the `dummy.c` patch
as well as the new driver** — porting only `MiSTer-audio-spi.c` yields a silent system.

### N5 — Two carried patches are dead weight (minor, but free wins)

* `drivers/usb/dwc2/core.c` (from `077c2c317`) is a **no-op**. It removes the
  `if (hsotg->params.oc_disable)` guard — but the same commit also adds
  `disable-over-current` to the `&usb1` DTS node, and dwc2 parses that property
  unconditionally (`5.15.1 drivers/usb/dwc2/params.c:468`; still present in
  `6.18.38 drivers/usb/dwc2/params.c:60`). `oc_disable` is therefore already `true` and the
  guard was always taken. **Drop the C patch; keep the DTS property.** **DROPPED (P1.9,
  confirmed) — TASKS.md P1.9 explicit ruling.** Owned by `0004-dts-de10nano-MiSTer.patch`
  (P1.7): that patch must carry only the `disable-over-current` DTS hunk from `077c2c317`,
  not its `drivers/usb/dwc2/core.c` hunk.
* `include/uapi/linux/vt.h` `MAX_NR_CONSOLES 63 → 9` (`b2a04cbfd`) is a UAPI header edit for a
  few KB of memory. **DROPPED (P1.9, confirmed)** — see §3.7 F-3.

---

## 3. Summary table

Legend — **Disposition:** `carry` = becomes a `linux-patches/` file · `drop` = 6.18 supersedes ·
`re-source` = Buildroot `kernel-module` package from upstream project · `delete` = removed by
design · `config` = feeds P1.3, not a patch.

### 3.1 Class A — MiSTer core (carry)

| Commit(s) | Subject | Files | Origin | Upstream in 6.18 | Disposition | Target |
|---|---|---|---|---|---|---|
| `d1002ecd4` | Implement MiSTer frame buffer device | `drivers/video/fbdev/MiSTer_fb.c` (+Kconfig/Makefile/DTS) | Sorgelig | no (MiSTer-specific) | carry — **landed (P1.4)** | `0001-fbdev-add-MiSTer_fb-driver.patch` ✅ |
| `333d49b95` | Implement MiSTer audio driver | `sound/drivers/MiSTer-audio-spi.c`, **`sound/drivers/dummy.c`** (+Kconfig/Makefile/DTS) | Sorgelig | no | carry — **landed (P1.5)** | `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch` ✅ |
| `3d72b9db7`, `e6df8e30e` | Add cpufreq/overclock driver; improve clock transition | `drivers/cpufreq/socfpga-cpufreq.c`, `Kconfig.arm`, `Makefile` | **Michael Huang** (PRs #34/#35) | no (`grep socfpga drivers/cpufreq/` → none) | carry | `0003-cpufreq-cyclone5-de10nano-overclock.patch` |
| `aa8afe109`, `e40563ae1`, `2548c2978`, `6827e7644`, `6c2d53934`, `246984fce`, `1337de1fd`, `c4d12c768`, `7d2df2d2d`, `c5066763c`, `071d9092e`, `f52690120`, `077c2c317` | de10-nano DTS + RTCs + i2c-gpio + uart1 + i2c2 + bridges + usb1 | `arch/arm/boot/dts/socfpga_cyclone5_de10_nano.dts`, `socfpga.dtsi`, `dts/Makefile` | Sorgelig; `6827e7644` **antoniovillena** | mainline has a *minimal* de10nano DTS (`144616a80889`, 2025-02-03, v6.14) — insufficient (§4.1a) | carry — **landed (P1.7)**; the `socfpga.dtsi` hunk **not** carried | `0004-dts-de10nano-MiSTer.patch` ✅ |
| `246984fce` (spidev hunk) | Enable SPI on LTC | `drivers/spi/spidev.c` — `{ .compatible = "altspi" }` | Sorgelig | no | **DROPPED (P1.7)** — DTS retargeted to `rohm,dh2228fv`, which 6.18's `spidev_dt_ids[]` already accepts (N2) | *(none — `0005` slot intentionally empty)* |
| `215e6e662`, `7828d722e`, `d788e7ab9`, `0d7b4fc7e`, `5391b8171`, `1a1f208fa`, `ae9313e22`, `316288a3d`, `97a398176`, `f0fb626ac`, `9f59d13d5` | defconfig (11 commits) | `arch/arm/configs/MiSTer_defconfig` | Sorgelig; `ae9313e22` **Bas v.d. Wiel**; `316288a3d` **Larry**; `f0fb626ac` **Nigel Shearman**; `0d7b4fc7e` **fjmartinez2k**; `9f59d13d5` **Fabio DL** | n/a | **config** — feeds P1.3 | *(none)* |

> **P1.3 note.** `docs/stock-inventory/stock-linux.config` (IKCONFIG, release 20250402) is
> **15 months older than fork HEAD**. It lacks `CONFIG_HID_VADER4=m` and `CONFIG_MACVLAN=y`,
> which HEAD's `MiSTer_defconfig` has. P1.3 must reconcile *both* sources.
> Symbols the carried patches introduce: `FB_MISTER`, `SND_MISTER_AUDIO` (+`SND_DUMMY`),
> `ARM_SOCFPGA_CPUFREQ`, `SPI_SPIDEV`, `HID_GUNCON2/3`, `HID_FTEC`, `HID_VADER4`,
> `HID_GAMECUBE_ADAPTER(_FF)`, `JOYSTICK_XONE`, `RTL8188EU/8188FU/8812AU/8821AU/8821CU/8822BU`.
> (`HID_GOOGLE_STADIA_FF` and `HID_NINTENDO` now come from mainline.)

### 3.2 Class B — `loop=` root patch (delete)

| Commit | Subject | Files | Origin | Upstream | Disposition |
|---|---|---|---|---|---|
| `3d95de58f` | Support for init loop device | `init/do_mounts.c` (+101/−4), `drivers/block/loop.c` (+7) | Sorgelig | no — and `mount_block_root()`/`init_mount()` were **removed** from `init/do_mounts.c` in the 6.x rewrite | **delete** — replaced by initramfs (§5). Full analysis: §4 |

### 3.3 Class C — HID/BT/storage, now upstream (drop — 22 commits)

Every row verified against 6.18.38 source; upstream commit recovered with `git log -S`.

| Commit(s) | Subject | Upstream in 6.18 — citation | Evidence |
|---|---|---|---|
| `c4ec5cb40`, `9bdab534b`, `60821059c`, `45283785a` | Switch Pro/Joy-Con backport + fixes | **`2af16c1f846b`** *HID: nintendo: add nintendo switch controller driver* (2021-09-11, v5.16) | `drivers/hid/hid-nintendo.c` present |
| `e155f6a2f`, `2799f8b94`, `b00a72159` | NSO NES/SNES, N64, Mega Drive | **`94f18bb19945`** *HID: nintendo: add support for nso controllers* (2023-12-04) | 6.18 `hid-ids.h:1066-1068`: `SNESCON 0x2017`, `GENCON 0x201e`, `N64CON 0x2019`. **Device-ID table is identical to the fork's.** |
| `f9c64d8cd` | hid-nintendo: fix possible division by 0 | **`6eb04ca8c52e`** *HID: nintendo: Prevent divide-by-zero on code* (2023-12-05) | 6.18 `hid-nintendo.c:1196,1201` — same `imu_cal_*_divisor[i] == 0` guards |
| `f84543926`, `0d60c3482`, `60e08955f`, `b76b4bc6a` | DualSense player LEDs / lightbar / mute / player-6 | **`8c0ab553b072`** *HID: playstation: expose DualSense player LEDs through LED class* (2021-09-08); **`8e5198a12d64`** *…add initial DualSense lightbar support* (2021-02-16) | 6.18 `hid-playstation.c:217` `update_player_leds`, `:155` lightbar flag. MiSTer's were pre-upstream backports. ⚠ verify controller LED behaviour on HW (P3.13) |
| `9a8cb6a93` | hid-microsoft: Xbox Series X/S | **`f5554725f304`** *HID: microsoft: Add rumble support to latest xbox controllers* (2023-04-25) | 6.18 `hid-microsoft.c:454` binds `MODEL_1914` (=0x0b13) |
| `adbaaea91` | hid-microsoft: XOne Elite 2 ID | same as above | 6.18 `hid-microsoft.c:458` binds `MODEL_1797_BLE` (=0x0b22) |
| `409f81077` | xpad: Elite 2 ID | **`e23c69e33248`** *Input: xpad - add support for XBOX One Elite paddles* (2022-08-18) | 6.18 `xpad.c:166` `{ 0x045e, 0x0b00, …, MAP_PADDLES, XTYPE_XBOXONE }` |
| `6eec2a515` | xpad: 8BitDo Ultimate ID | **`21617de3b464`** *Input: xpad - add 8BitDo Pro 2 Wired Controller support* (2023-01-27) | 6.18 `xpad.c:409-410` `0x2dc8,0x3106` / `0x3109` |
| `9521b003c` | Google Stadia controller + rumble | **`24175157b852`** *HID: hid-google-stadiaff: add support for Stadia force feedback* (2023-07-16) | 6.18 `hid-google-stadiaff.c:144` binds `USB_DEVICE_ID_GOOGLE_STADIA` (0x9400) — exact ID match |
| `3fb48dc16` | btusb: TP-Link UB500 | **`4fd6d4907961`** *Bluetooth: btusb: Add support for TP-Link UB500 Adapter* (2021-09-30, v5.16) | 6.18 `btusb.c:787` `USB_DEVICE(0x2357, 0x0604)` |
| `a10f4246f` | btusb: Edimax BT-8500 | **`c7577014b74c`** *Bluetooth: btusb: Add RTL8761BUV device (Edimax BT-8500)* (2022-08-26) | 6.18 `btusb.c:797` `USB_DEVICE(0x7392, 0xc611)` |
| `e2c082ef9` | usb-storage: blacklist Realtek WiFi CD-ROM | **`a3dc32c635ba`** *USB: storage: Ignore driver CD mode for Realtek multi-mode Wi-Fi dongles* (2025-08-14) | 6.18 `unusual_devs.h:1509` `UNUSUAL_DEV(0x0bda, 0x1a2b, 0x0000, 0xffff, …, US_FL_IGNORE_DEVICE)` — same effect, **wider** bcdDevice range than MiSTer's `0x0000-0x9999` |
| `552f9f197` | hci_conn: prevent call with NULL pointer | **restructured** — the patched function `create_le_conn_complete()` no longer lives in `net/bluetooth/hci_conn.c`; it moved to `net/bluetooth/hci_sync.c:6942` with a different signature (`(hdev, void *data, int err)`), and `hci_connect_le_scan_cleanup()` now takes `(conn, status)` | patch site gone; NULL path structurally absent |
| `b02a4a011` | btusb: support for more CSR clones | **superseded** — 6.18 `btusb.c:2472-2530` carries a far more evolved fake-CSR detector (`bcdDevice` list `0x0100/0x0134/0x1915/0x2520/0x7558/0x8891`, ranged `lmp_subver`/`hci_ver` tests) | ⚠ **6.18 does not explicitly handle `lmp_subver == 0x2512`** (MiSTer's addition), and 0x2512 falls outside 6.18's `<= 0x22bb` range test. A specific fake-CSR dongle model may regress. **Flag for P3.13 hardware test.** |
| `71c583074` *(m41t80 half)* | Disable RTC error messages | **`c7622a4e44d9`** *rtc: m41t80: reduce verbosity* (2025-05-26) | 6.18 `rtc-m41t80.c:215` `dev_dbg(&client->dev, "Unable to read date\n")` — identical. *(The `i2c-designware` half is NOT upstream — see F-5.)* |
| — | *(uapi, folded in above)* `include/uapi/linux/input-event-codes.h` | **`97c01e65ef4c`** *Input: Add and document BTN_GRIP** (2025-07-27); **`1260cd04a601`** *Input: add ABS_PROFILE to uapi and documentation* (2022-09-28) | 6.18 `input-event-codes.h:605-608` `BTN_GRIPL 0x224 / BTN_GRIPR 0x225 / BTN_GRIPL2 0x226 / BTN_GRIPR2 0x227` and `:893` `ABS_PROFILE 0x21` — **byte-identical numbering to MiSTer's.** No UAPI conflict; drop the header patch entirely. |
| — | *(folded in)* `drivers/input/joydev.c` Nintendo `ACCEL_DEV` | **`4ff5b10840a8`** *HID: nintendo: add IMU support* (2021-09-11) | 6.18 `joydev.c:760-765` defines the same Nintendo VID/PIDs in the accelerometer blacklist |

### 3.4 Class D — HID/input, still out-of-tree (carry — 30 commits)

All confirmed **absent** from 6.18.38.

| Commit(s) | Subject | Files | Origin / upstream project | Target file |
|---|---|---|---|---|
| `e503d193c` | Namco GunCon 2 | `drivers/hid/hid-guncon2.c` | **Nolan Nicholson** | `0010-hid-guncon2.patch` |
| `8179ac736`, `9b9aebfac` | Namco GunCon 3 (+warning fix) | `drivers/hid/hid-guncon3.c` | **Nolan Nicholson** (PR #20) | `0011-hid-guncon3.patch` |
| `e82a59280`, `8908e0fe1`, `ed8f8e6ce` | Fanatec wheels (+build/warning fixes) | `drivers/hid/hid-ftec.{c,h}`, `hid-ftecff.c` | **Michael Huang** (PRs #24/#25); upstream project: `gotzl/hid-fanatecff` | `0012-hid-fanatec.patch` |
| `b1b168eb6` | Flydigi Vader 4 Pro, BT D-Input remap | `drivers/hid/hid-vader4.c` | Sorgelig | `0013-hid-flydigi-vader.patch` |
| `77862a67f` | Official Nintendo GameCube adapter (057e:0337) | `drivers/hid/hid-gamecube-adapter.c` | **James McCarthy** (PR #48) | **`0014-hid-gamecube-adapter.patch`** *(new — not in PLAN §6)* |
| `484f68172` | **NSO Famicom controllers** | `drivers/hid/hid-nintendo.c` | **Aurora** (PR #62) | **`0015-hid-nintendo-nso-famicom.patch`** ✅ **landed (P1.9-esc)** — re-implemented, not rebased (§9) |
| `c784a6856` | hid-microsoft: Xbox Elite 2 paddles | `drivers/hid/hid-microsoft.c` | Sorgelig | **`0016-hid-microsoft-elite2-paddles.patch`** *(new)* |
| `af27afc4c`, `f3c75eb02`, `a2242dd85`, `c035c21c0` | xpad deltas | `drivers/input/joystick/xpad.c` | **zakk4223** (PR #63), **eniva**, Sorgelig | **`0017-xpad-mister-deltas.patch`** *(new)* |
| `5bdbf2f7e` | ControllaBLE quirk (1209:FACA) | `drivers/hid/hid-quirks.c`, `hid-pl.c` | Sorgelig | `0018-hid-controllable-quirk.patch` |
| `fc8f3c2c6`, `b745ce6d9` | Logitech K400r / K400 Plus: disable Fn swap | `drivers/hid/hid-logitech-hidpp.c` | Sorgelig; **HGD73** (PR #15) | `0019-hidpp-k400-fn-inversion.patch` |
| `8a100f2ed`, `43c52e9ef` | Logitech G923 wheels + 32-bit rumble/FF fix | `drivers/hid/hid-lg.c`, `hid-lg4ff.c`, `hid-ids.h` | **atrac17** (PR #32), **zakk4223** (PR #54) | ❌ **NOT CARRIED (P1.9-esc)** — reclassified: the fork's file is a vendored copy of the out-of-tree **berarma/new-lg4ff** rewrite; there is no `0021` (§9) |
| `1412bd707`, `5c410e935` | hid-sony: div-by-0; 3rd-party DS4 wired connect | `drivers/hid/hid-sony.c` | Sorgelig | `0022-hid-sony-fixes.patch` |
| `0d7778d1f`, `47dc53a22`, `15968bc26` | wiimote: `uniq`, button codes, analog ranges | `drivers/hid/hid-wiimote-{core,modules}.c` | Sorgelig | `0023-hid-wiimote-fixes.patch` |
| `70e391b81` | Map HID Europe-1 (0x32) → `KEY_F24` (**Keyrah**) | `drivers/hid/hid-input.c` (1 line) | Sorgelig | `0024-hid-input-keyrah-europe1.patch` |
| `f0982bf2c` | usbhid: apply `jspoll` to gamepads too | `drivers/hid/usbhid/hid-core.c` | Sorgelig | `0025-usbhid-jspoll-gamepad.patch` |
| `2ac0aa1e8`, `52a56ae3d` | **core input:** mouseX/mice under `EVIOCGRAB`; disable touch-to-click on DS4/DualSense | `drivers/input/input.c`, `drivers/input/mousedev.c`, `include/linux/input.h` | Sorgelig | **`0026-input-mousedev-eviocgrab.patch`** ✅ **landed (P1.9-esc)** — see §9 |
| `817ace70b` | Remove Xbox One Wireless Adapter IDs from mt76 (so xone can bind) | `drivers/net/wireless/mediatek/mt76/mt76x2/usb.c` | **sofakng** | `0027-mt76x2u-release-xbox-adapter-ids.patch` — **still required:** 6.18 `mt76x2/usb.c:26-27` still claims `045e:02e6` and `045e:02fe` |
| `d7adb20b4` | **dwc2: fix unaligned IN data** | `drivers/usb/dwc2/hcd_intr.c` | **Martin Donlon** (PR #57, 2025-01-13) | `0028-dwc2-fix-unaligned-in-split.patch` — **not upstream:** 6.18 `hcd_intr.c:922-928` still has the old unconditional `memcpy(..., len)` in `dwc2_xfercomp_isoc_split_in()`. **Genuine bug fix — should be submitted upstream.** |

### 3.5 Class D/E — xone (re-source, 7 commits)

| Commits | Subject | Origin | Disposition |
|---|---|---|---|
| `4ddd8ec3d`, `5a7965488`, `c708f2222`, `e2eb39e6f`, `8270e78f4`, `d776ddb4e`, `d5beb5aa6` | Add/refresh xone (Xbox wireless adapter, GIP) — 19 files, `drivers/hid/xone/**`, `CONFIG_JOYSTICK_XONE=m` | vendored from **`medusalix/xone`** (MIT/GPL); MiSTer-local additions: rumble fix, Elite-2 paddles backport, per-PID firmware, sysfs software pairing | **re-source** → `package/xone` (A5: already `=m` in stock — 7 `.ko.xz` shipped). MiSTer's 4 local deltas (2026-04) must be carried as package patches. Firmware redistribution decision: P3.2 / `docs/decisions/0003-xone-firmware.md`. **Not upstream** (`grep -rl gip_driver drivers/` in 6.18 → nothing) |

### 3.6 Class E — Realtek USB WiFi (re-source, 9 commits)

Vendored wholesale: **3,428 files**. Triaged as whole trees, not line-by-line.

| Commits | Subject | Origin | Disposition |
|---|---|---|---|
| `33ff5146a` (2,548 files / 2.56M+), `3740d5b88` (1,687 files / 942K+), `2371fb1aa`, `143ce187e`, `4e98a68d1` (merge), `43fbb63ae`, `993b82e31`, `115b1d1ae`, `fc09a292a` | Vendor + resync rtl8188eu, rtl8188fu, rtl8812au, rtl8821au, rtl8821cu, rtl88x2bu | **morrownr** (explicitly: `3740d5b88` = *"Backport … from morrownr"*, **gkrzystek**, PR #40); local fixes: EDUP EP-AC1661 efuse (`fc09a292a`), Edimax EW-7822ULC (`115b1d1ae`) | **re-source** → `package/rtl8188eu`, `rtl8188fu`, `rtl8812au`, `rtl8821au`, `rtl8821cu`, `rtl88x2bu` (P3.1), commit-pinned + hash-verified. **Do not vendor.** Kconfig symbols: `RTL8188EU`, `RTL8188FU`, `RTL8812AU`, `RTL8821AU`, `RTL8821CU`, **`RTL8822BU`** (note: the 88x2bu symbol is `RTL8822BU`, not `RTL88X2BU`) — all `=m`; 6 `.ko.xz` shipped. Verify the two local device fixes are present upstream or re-apply as package patches. |

### 3.7 Class F — misc quirks

| # | Commit | Subject | File | Upstream in 6.18 | Disposition |
|---|---|---|---|---|---|
| F-1 | `2d39e76d1` | mmc: don't activate LED on status command | `drivers/mmc/core/core.c` (1 line) | **no** (`grep MMC_SEND_STATUS drivers/mmc/core/core.c` → none) | **carry** → `0020-mmc-no-led-on-send-status.patch` |
| F-2 | `b62efee23` | hps_led: brightness-change notification | `drivers/leds/leds-gpio.c` (+9) | **no** | **CARRIED (P1.9)** → `0029-leds-gpio-brightness-hw-changed.patch`. Consumer confirmed: Main_MiSTer polls `brightness_hw_changed` to drive the on-screen disk-activity LED (TASKS.md P1.9 explicit ruling — **do not drop**). Applies clean to 6.18.38, builds warning-free at `W=1`. |
| F-3 | `b2a04cbfd` | vt: reduce 63 → 9 ttys | `include/uapi/linux/vt.h` (`MAX_NR_CONSOLES`) | **no** (it is a local reduction) | **DROPPED (P1.9, confirmed).** TASKS.md P1.9 explicit ruling: a UAPI header edit for a few KB, only 3 consoles used. Not carried; no `00xx` file. |
| F-4 | `7436e2d6e` | mt7601u "possible fix?" — comments out DPD calibration | `drivers/net/wireless/mediatek/mt7601u/phy.c` | **no** — 6.18 `mt7601u/phy.c:592` still calls `mt76 01u_mcu_calibrate(dev, MCU_CAL_DPD, …)` | **DROPPED (P1.9, confirmed).** Author **bbond007**; commit message is literally *"mt7601u possible fix?"*; the diff comments out a calibration call and leaves stray `/* remove this for testing--> spark2k06 */` markers. Unprincipled, and not in P1.9's task scope. Not carried; re-add only if a real mt7601u regression appears at P3.13. |
| F-5 | `71c583074` *(i2c half)* | Disable RTC error messages | `drivers/i2c/busses/i2c-designware-master.c` (`dev_err`→`dev_dbg` on "controller timed out") | **no** — 6.18 `i2c-designware-master.c:857` still `dev_err` | **carry** → `0030-i2c-designware-quiet-timeout.patch`. Cosmetic: silences boot spam when no RTC add-on board is fitted. *(The m41t80 half of this commit **is** upstream — see class C.)* |

### 3.8 Class G — exfat replacement (NEW class; decision required)

| Commits | Subject | Files | Origin | Upstream | Disposition |
|---|---|---|---|---|---|
| `8b6b8c2f5`, `df35bdb27`, `858322ce6`, `5220d6686`, `7f7148c1f`, `99a2c80d0` | Remove mainline exFAT; add out-of-tree exFAT **with symlink support**; cleanups | −12 mainline `fs/exfat/*`, +20 files (`exfat_core.c`, `exfat_super.c`, …), `Kconfig`, `Makefile` | Samsung / `exfat-nofuse` lineage, re-integrated by Sorgelig | mainline exfat exists but has **no symlinks** and **no FAT12/16/32** | **DECISION REQUIRED — see N1.** Not currently in PLAN §4.1's taxonomy. |

### 3.9 Noise

| Commit | Subject | Disposition |
|---|---|---|
| `a547c18d0` | "remove unused files." — deletes `scripts/gdb/linux/*.py` (15 files, −2,156) | **dismiss.** Deletes upstream kernel GDB helper scripts. No functional effect on the built kernel. Do not carry. |

---

## 4. Class B analysis — `init/do_mounts.c` (P1.10 depends on this)

Commit `3d95de58f` "Support for init loop device", Sorgelig, 2021-11-08. Two files.

### 4.1 The actual diff

`drivers/block/loop.c` — exports `max_part` so `do_mounts.c` can compute the loop8 minor:

```c
+int loop_max_part(void)
+{
+	return max_part;
+}
+EXPORT_SYMBOL(loop_max_part);
```

`init/do_mounts.c` — the substance:

```c
-int root_mountflags = MS_RDONLY | MS_SILENT;
+int root_mountflags = MS_RDONLY | MS_SILENT | MS_NOATIME | MS_NODIRATIME;

+static char * __initdata loop_name = 0;
+static int __init set_loop_name(char *str) { loop_name = str; return 1; }
+__setup("loop=", set_loop_name);
...
+static int __init m_open(const char *filename, int flags, int mode)   /* filp_open + fd_install */
+static int __init loop_setup(const char *file, const char *device)    /* ioctl(LOOP_SET_FD) */
+extern int loop_max_part(void);

 void __init mount_root(void)
 {
 	int err = create_dev("/dev/root", ROOT_DEV);
+	if (loop_name)
+	{
+		char lname[32];
+		err = init_mkdir("/root2", 0777);
+		if (err) pr_emerg("Failed mkdir /root2: %d\n", err);
+
+		err = init_mount("/dev/root", "/root2", "exfat",
+		                 MS_DIRSYNC | MS_SYNCHRONOUS | MS_NOATIME | MS_NODIRATIME, "");
+		if (err) pr_emerg("Failed to mount /dev/root as VFAT or exFAT: %d\n", err);
+
+		err = create_dev("/dev/loop8", MKDEV(7, (loop_max_part()+1)*8));
+		if (err < 0) pr_emerg("Failed to create /dev/loop8: %d\n", err);
+
+		sprintf(lname, "/root2/%s", loop_name);
+		err = loop_setup(lname, "/dev/loop8");
+		if (err) pr_emerg("Failed to loop_setup: %d\n", err);
+
+		mount_block_root("/dev/loop8", root_mountflags);
+		err = init_mount("/root2", "/root/media/fat", "", MS_BIND, "");
+		if (err) pr_emerg("Failed to bind-mount ... to /root/media/fat : %d\n", err);
+	}
+	else
+	{
+		mount_block_root("/dev/root", root_mountflags);
+	}
 }
```

### 4.2 Behaviour, step by step — and whether §5's `/init` covers it

| # | Stock kernel behaviour | Covered by the §5 `/init` sketch? |
|---|---|---|
| 1 | Parse `loop=` from cmdline (`__setup`) | ✅ yes — `/init` parses `loop=` from `/proc/cmdline` (A2) |
| 2 | `root=` → `/dev/root` via the standard `ROOT_DEV` path; `rootwait` handled by core | ✅ yes — A2 requires parsing `root=` and a `rootwait` retry loop |
| 3 | `mkdir /root2`, mount the data partition there | ✅ yes — `/mnt/fat` |
| 4 | Mount it with fstype **`"exfat"` only** — works for FAT32 *because MiSTer's exfat driver also handles FAT12/16/32* (N1) | ⚠ **partially.** The sketch tries `vfat` then `exfat`, which mounts both — **but via two different mainline drivers.** See §4.3. |
| 5 | Mount flags **`MS_DIRSYNC \| MS_SYNCHRONOUS \| MS_NOATIME \| MS_NODIRATIME`** | ❌ **NOT covered.** The sketch uses default (async) options. **N3 — must add `-o sync,dirsync,noatime,nodiratime`.** |
| 6 | `create_dev("/dev/loop8", MKDEV(7, (max_part+1)*8))` — with `loop.max_part=8` on the cmdline, `part_shift = fls(8) = 4`, `max_part` becomes 15, so the minor is `16*8 = 128` = loop index 8 << 4. Needed because `CONFIG_BLK_DEV_LOOP_MIN_COUNT=8` only pre-creates **loop0–loop7**. | ⚠ **needs care.** BusyBox `losetup /dev/loop8` will fail if the node does not exist. Use `losetup -f` (via `/dev/loop-control`), or `mknod` the node explicitly. **Nothing in userland depends on the root being `loop8` specifically** (verified: no `loop8` reference in `work/imgroot/etc`, `/usr/bin`, `/usr/sbin`, or Main_MiSTer), so `losetup -f` is safe. |
| 7 | `loop_setup()` = `ioctl(LOOP_SET_FD)`; **backing file opened `O_RDWR`**, but the loop device is then mounted with `MS_RDONLY` (from `root_mountflags` + cmdline `ro`) | ✅ yes — `losetup -r` (read-only) + `mount -o ro`. Ours is *stricter*, which is fine and arguably better. |
| 8 | `mount_block_root("/dev/loop8", root_mountflags)` → root = the ext4 in `linux.img`, `ro,noatime,nodiratime` | ✅ yes — `mount -o ro /dev/loopN /newroot` (**add `noatime,nodiratime` for exactness**; moot on a ro mount, but free) |
| 9 | **`init_mount("/root2", "/root/media/fat", "", MS_BIND, "")`** — a **bind** mount, not a move. The data partition therefore stays mounted at `/root2` *as well*. | ⚠ **differs.** The sketch uses `mount --move`. Functionally equivalent for everything that reads `/media/fat`; the only observable difference is one fewer entry in `/proc/mounts`. **Nothing parses `/proc/mounts`** (verified: no `getmntent`/`/proc/mounts`/`mtab` in Main_MiSTer). `mount --move` is cleaner. ✅ acceptable. |
| 10 | **Error paths: every failure just `pr_emerg`s and continues**, ending in a kernel panic ("VFS: Unable to mount root fs"). No recovery. | ✅ **strictly improved** — A2 mandates a diagnostic banner and a serial rescue shell. |
| 11 | `/root2` semantics: an intermediate mountpoint in the initramfs/rootfs, hidden after the switch to `/root`. Not a userland-visible path. | ✅ n/a — no userland reference to `/root2` (verified). |

### 4.3 The one gap that is not a mount option: **symlinks and codepage** (N1)

Step 4 is where §5's plan is *incomplete*, not wrong. Stock mounts the FAT32 **or** exFAT data
partition through **one** driver — MiSTer's out-of-tree exfat — which gives it:

* **symlink support on both FAT32 and exFAT** (used by Main_MiSTer, `file_io.cpp:1592`), and
* **`iocharset=utf8`** filename decoding on both.

The `mount -t vfat || mount -t exfat` fallback routes FAT32 to mainline **vfat** (no symlinks,
`iso8859-1` default) and exFAT to mainline **exfat** (no symlinks). So:

* **Mount options fix the encoding** (`-o iocharset=utf8`) — cheap, do it.
* **Nothing at the initramfs level restores symlinks.** That requires the N1 decision.

**Verdict:** the initramfs replacement covers **100 % of the `loop=` patch's own logic**, and
improves on its error handling. It does **not** cover the *filesystem-driver* substitution that
the class-B patch silently depends on. Deleting `init/do_mounts.c` is correct and safe;
**deleting the exfat driver is a separate decision (N1) that P1.10 must not assume away.**

**Action for P1.10:** mount with
`-o ro,sync,dirsync,noatime,nodiratime,iocharset=utf8` (vfat) /
`-o ro,sync,dirsync,noatime,nodiratime,iocharset=utf8` (exfat) — noting that `/media/fat` is
mounted **rw** in stock (only the *root* is `ro`), so drop `ro` for the data partition.

---

## 5. Carried patches — one subsection each

### `0001-fbdev-add-MiSTer_fb-driver.patch` — **P1.4** (class A)

**Origin:** `d1002ecd4` "Implement MiSTer frame buffer device.", Sorgelig, 2021-08-20.
**Files:** `drivers/video/fbdev/MiSTer_fb.c` (new, ~394 lines), `drivers/video/fbdev/Kconfig`
(`config FB_MISTER`), `drivers/video/fbdev/Makefile`, and the `MiSTer_fb` DTS node (in `0004`).

**What it does.** A platform driver bound to DT `compatible = "MiSTer_fb"` at
`reg = <0x22000000 0x800000>`, IRQ 40 — the FPGA's frame-reader window. `memremap(...,
MEMREMAP_WT)`s that region and registers it as `/dev/fb0`. The first 4096 bytes are a header;
`screen_base = fb_base + 4096` (`MiSTer_fb.c:265-266`).

**ABI surface — flag loudly for P0.5:**

* **`/dev/fb0`** — standard fbdev node.
* **`FBIO_WAITFORVSYNC` ioctl** (`MiSTer_fb.c:111-133`). **This is a *standard mainline* ioctl,
  not a custom number:** `_IOW('F', 0x20, __u32)` — and it is **identical in 5.15 and 6.18**
  (`linux-5.15.1/include/uapi/linux/fb.h:37` ≡ `linux-6.18.38/include/uapi/linux/fb.h:38`).
  Consumer: `Main_MiSTer/video.cpp` ~L3859/3867 `ioctl(fb, FBIO_WAITFORVSYNC, &zero)`.
  **Good news: the ioctl ABI cannot drift.** Any non-`FBIO_WAITFORVSYNC` cmd returns `-ENOTTY`;
  a non-zero `arg` value returns `-ENODEV`.
* **`/sys/module/MiSTer_fb/parameters/mode`** (`module_param_cb`, mode **0664**, RW) — the real
  custom ABI. Format is a 5-field string `"%u %u %u %u %u"` = `format rb width height stride`
  (`mode_set()`/`mode_get()`, `MiSTer_fb.c:341-370`). Writing it wipes the framebuffer,
  reconfigures `fb_info`, and bumps `res_count`. Main_MiSTer drives this directly.
* **Read-only params** (0444): `width`, `height`, `stride`, `format`, `rb`, `frame_count`,
  `res_count` under `/sys/module/MiSTer_fb/parameters/`.

**Forward-port hazards on 6.18 — as *predicted*, then as *found***

> **P1.4 is done.** The patch is
> `board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch`
> (3 files, +426: `drivers/video/fbdev/MiSTer_fb.c` new, `Kconfig`, `Makefile`).
> **Disposition: carry — landed.** The patch's own header is the authoritative write-up;
> what follows is the score-card against the predictions made here in Phase 0, because
> **two of the six were wrong** and the wrongness is instructive.

| # | Predicted here | Reality on 6.18.38 |
|---|---|---|
| 1 | `static struct fb_ops ops` **"must become `const`"** | ❌ **Wrong — not a hazard at all.** `fb_info.fbops` has been `const struct fb_ops *` since **v5.6** (`bf9e25ec1287`), i.e. *already in 5.15*. Assigning a non-`const` object to a pointer-to-`const` is legal C; the 5.15 code compiles unchanged. Constified anyway, as hardening. |
| 2 | `info->flags = FBINFO_FLAG_DEFAULT;` **will not compile** | ✅ **Right.** Removed in **v6.6** by `0444fa357c16`. Assignment deleted. The macro was `0` and `fb_info` sits in a `devm_kzalloc()`'d struct, so this is a no-op, not a behaviour change. |
| 3 | `FBINFO_MISC_USEREVENT` / `fb_notifier_call_chain` — already commented out; `fbcon_update_vcs` survives | ✅ **Right.** No work. |
| 4 | Kconfig: prefer `select FB_SYSMEM_HELPERS` | ❌ **Wrong recommendation** — see 5. `FB_SYSMEM_HELPERS` drags in `FB_SYSMEM_FOPS` (`fb_sys_read`/`fb_sys_write`) **and still leaves the driver with no `mmap`**, because 6.18 has **no sysmem mmap helper** (only `__FB_DEFAULT_SYSMEM_OPS_{RDWR,DRAW}`). Shipped instead: `select FB_SYS_{FILLRECT,COPYAREA,IMAGEBLIT}` (all three still exist) **+ `FB_IOMEM_FOPS`**, plus `depends on OF`. |
| 5 | ⚠ "the single most likely place P1.4 breaks" — sysmem vs iomem fops | ✅ **Right that it was the crux; the resolution is `IOMEM`.** The fallback died in **v6.8**, `8813e86f6d82` ("fbdev: Remove default file-I/O implementations") — a driver with no `.fb_mmap` now takes a `WARN` and `-ENODEV` in `fb_mmap()`. Shipped `__FB_DEFAULT_IOMEM_OPS_RDWR` + `__FB_DEFAULT_IOMEM_OPS_MMAP` (`fb_io_read`/`fb_io_write`/`fb_io_mmap`), which is **exactly what the pre-6.8 core fallback did** — `vm_iomap_memory()` on the physical `fix.smem_start`. It *has* to be iomem: the window is FPGA memory above the `mem=511M` line and **has no `struct page`s**, so a sysmem/`vm_insert_page` mmap could not work. The **drawing** ops stay on `sys_fillrect`/`sys_copyarea`/`sys_imageblit` as in 5.15 — `memremap(MEMREMAP_WT)` returns a normal-memory mapping, so direct dereference is correct there. **Note the premise stated here ("Main_MiSTer maps the framebuffer") is itself false** — see `docs/abi-contract.md` §4.1; only **fbcon** consumes these fops. |
| 6 | No aperture / `remove_conflicting_framebuffers` concern | ✅ **Right.** Platform device, no PCI VGA conflict. Untouched. |

**Two hazards this section did *not* predict**, both found by building:

7. **`platform_driver::remove()` returns `void`** since **v6.11** (`0edb555a65d1`). `fb_remove()`
   changed `int` → `void`; it only ever returned `0`. *(This one bites every carried platform
   driver — **P1.5** and **P1.6** will hit it too.)*
8. **`-Wmissing-prototypes` is on in the default build** since **v6.8** (`0fcb70851fbf`). The
   5.15 file's non-`static` `void fb_set()` is the **only** warning it still emits on 6.18;
   made `static` (it is file-local and was never meant to be a vmlinux-global symbol).

Also fixed, on the error path only, ABI untouched: `memremap()` returns **NULL** on failure, not
an `ERR_PTR`. The 5.15 code tested `IS_ERR()` — false for NULL — so a failed mapping fell
through to `screen_base = 0x1000` and oopsed on the first fbcon draw. Now tests for NULL and
returns `-ENOMEM`.

**Config:** `CONFIG_FB_MISTER=y` was added to `board/mister/de10nano/linux.config` by this task,
as `docs/kernel-config-deltas.md` §4.1 deferred it (kconfig would have discarded the symbol
before the driver existed). `savedefconfig` round-trips with that one line as the only delta.
`CONFIG_FB_DEVICE=y` — the 6.x symbol that creates `/dev/fb0` — must not drift off.

**Verified:** applies clean to pristine 6.18.38 (`git apply --check` and `patch --dry-run`, both
exit 0); full `zImage` builds with **zero compiler diagnostics** at `W=1`
(arm-buildroot-linux-gnueabihf-gcc 14.3.0); `FBIO_WAITFORVSYNC` = `_IOW('F', 0x20, __u32)` =
**`0x40044620`** evaluated from *both* trees' own headers — identical, and identical on the ARM
target (`movw r1,#0x4620` / `movt r1,#0x4004`); all eight module params present with stock's
names and permissions (`mode` 0664 RW; the seven others 0444 RO), `KBUILD_MODNAME` still
`MiSTer_fb` so the sysfs path is unchanged. **Not verified (needs hardware, → P1.13):** that
IRQ 40 actually fires and `FBIO_WAITFORVSYNC` returns 0 rather than `-ETIMEDOUT`, and that fbcon
paints.

---

### `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch` — **P1.5** (class A) ✅ **LANDED**

**Origin:** `333d49b95` "Implement MiSTer audio driver.", Sorgelig, 2021-08-20 (5 files).
**Files:** `sound/drivers/MiSTer-audio-spi.c` (new), **`sound/drivers/dummy.c` (patched)**,
`sound/drivers/Kconfig` (`config SND_MISTER_AUDIO`), `sound/drivers/Makefile`, DTS (`0004`).

**⚠ Read N4 first — the plan and TASKS.md both mis-state this driver's ABI.**

**What it does — two halves that must ship together:**

1. **`MiSTer-audio-spi.c`**: platform/SPI driver on DT `compatible = "MiSTer,spi-audio"`.
   Allocates a 512 KiB coherent DMA ring (`dma_alloc_coherent`, ~2.6 s of audio), registers a
   char device **`/dev/MrAudio`** (`alloc_chrdev_region` + `class_create` + `device_create` +
   `cdev_add`, `DRIVER_NAME "MrAudio"`), and on `write()` copies PCM into the ring and
   `spi_write()`s the `MrBufferInfo` descriptor (`{addr, ptr, len}`) to the FPGA.
2. **`dummy.c`**: `fake_buffer` `1 → 0` and a `model_MiSTer` (S16_LE / 48000 / 2ch /
   32 KiB) **force-selected** as the default snd-dummy model
   (`dummy->model = m = &model_MiSTer;`). This provides ALSA **card 0**.

**ABI surface — flag loudly for P0.5:**

* **`/dev/MrAudio`** — char device, dynamic major, accepts **raw S16_LE 48 kHz stereo** writes.
* **ALSA card 0** with snd-dummy's *unmodified* names: `card->driver` = `"Dummy"`,
  `shortname` = `"Dummy"`, `longname` = `"Dummy 1"` (`dummy.c:1095-1097`).
* The binding between them is **`/etc/asound.conf`** (rootfs, not kernel): `pcm.!default` is a
  `plug → rate(48000,S16_LE) → file("/dev/MrAudio") → hw:0` chain. **P2.3 must ship this file
  verbatim.**
* `CONFIG_SND_MISTER_AUDIO=y` **and** `CONFIG_SND_DUMMY=y` are both required (stock config +
  HEAD `MiSTer_defconfig`).
* Main_MiSTer itself does **not** open ALSA. Consumers are MidiLink / fluidsynth / mt32 and any
  userland audio program using the default PCM.

**The 5.15 → 6.18 API churn actually hit (P1.5 outcome).** Predictions 2–4 above held:
snd-dummy's structure is intact, `dma_alloc_coherent` is unchanged, and there is no ALSA PCM
churn because this is a chrdev, not an ALSA driver. Prediction 3's "CMA sizing must be
preserved" is void — there is no CMA to size (A12 / abi-contract §8.2: `CONFIG_DMA_CMA` is
*not set*; the 512 KiB comes from the page allocator).

| # | Churn | Fix |
|---|---|---|
| 1 | `class_create()` lost its `struct module *` arg in **v6.4-rc1** (`1aaba11da9aa`) | `class_create(DRIVER_NAME "_sys")` |
| 2 | `struct spi_driver::remove` became `void` in **v5.18-rc1** (`a0386bba7093`, Uwe Kleine-König) | `static void device_remove(...)` |
| 3 | `class_create()`/`device_create()` return `ERR_PTR()`, never `NULL` — 5.15's `== NULL` tests were **dead code**, so a failed `device_create()` was treated as success | `IS_ERR()` on both; success path bit-for-bit unchanged |
| 4 | `major` was an `int` holding a `dev_t` | now `dev_t`. `ARM_LPAE` is off on Cyclone V ⇒ `dev_t` and `dma_addr_t` are both `u32`; every printk format and printed value is unchanged |

Also: `Kconfig` gained `depends on SPI` (it cannot link without it) and tab indentation;
`model_MiSTer` is now `const` like every other model in `dummy.c` (verified in `.rodata`
alongside `model_emu10k1`/`model_ca0106`). `CONFIG_SND_MISTER_AUDIO` and its `default n` are
unchanged. Everything that is ABI — `DRIVER_NAME "MrAudio"`, the `MrAudio_proc` chrdev region,
the `MrAudio_sys` class, the dynamic major, the 512 KiB ring, the 4-byte write alignment, the
`> BUFFER_LEN ⇒ -EFAULT`, the `Info_t` descriptor, the `read()` status string — is verbatim.

Note the two hazards P1.4 hit do **not** apply here: this is an **SPI** driver, not a platform
driver (so `platform_driver::remove`'s v6.11 `void` change is irrelevant), and every function in
the file is already `static` (so v6.8's default `-Wmissing-prototypes` is satisfied).

**Verified (build-time, actually executed):**

* `git apply --check -p1` against a freshly-extracted pristine v6.18.38 → **clean**; `patch -p1
  --dry-run` likewise (Buildroot applies with `patch(1)`, not git).
* Full `vmlinux` build of the patched pristine tree with the board `linux.config`:
  **zero warnings, zero errors** — and also zero at `W=1`.
* Booted the resulting kernel under `qemu-system-arm -M virt` with a busybox initramfs:
  `/proc/asound/cards` → **card 0 = `Dummy - Dummy / Dummy 1`** (names unmodified, as A12
  requires); `/sys/module/snd_dummy/parameters/fake_buffer` → **`N`** (the patched default).
* Drove card 0's playback PCM through the raw `SNDRV_PCM_IOCTL_HW_PARAMS` ABI — exactly what
  libasound's `type hw` plugin does underneath. **S16_LE / 48000 / 2ch is ACCEPTED.** As a
  differential, four triples that an *unpatched* snd-dummy would accept (`U8`, `44100`, mono,
  and a 64 KiB buffer) are all **rejected with `EINVAL`** — proving `model_MiSTer` is genuinely
  force-selected rather than merely present.

#### ⚠ Correction to A12 / N4: *why* the `dummy.c` hunks are load-bearing

A12 and N4 both say card 0 "must accept S16_LE/48000/2ch — otherwise the whole default PCM
fails to open and nothing plays". **That reasoning is wrong, even though the conclusion (ship
the hunks) is right.** An *unpatched* snd-dummy advertises `USE_FORMATS = U8 | S16_LE`,
`USE_RATE = CONTINUOUS 5500..48000`, `channels 1..2` — a **superset**. It would accept
S16_LE/48000/2ch quite happily, and the default PCM would open fine without any `dummy.c`
patch at all. So "otherwise nothing plays" does not follow.

What the hunks actually buy is **pinning**, and the reason is subtle. Read `asound.conf` again:
its `type rate` slave pins `format S16_LE` and `rate 48000` — and **says nothing about the
channel count**. Channels are negotiated against `hw:0`. With stock snd-dummy's `channels 1..2`,
a **mono** client negotiates 1ch all the way down, and the `type file` plugin tees **mono**
S16_LE/48000 into `/dev/MrAudio` — which `MiSTer-audio-spi.c` hands to the FPGA as 4-byte
*stereo* frames (`userBufLen & ~3`). `model_MiSTer`'s `channels_min = channels_max = 2` forces
the top-level `plug` to convert everything to stereo, so `/dev/MrAudio` always sees exactly
S16_LE/48000/2ch. That is the load-bearing effect, and the mono-`EINVAL` above demonstrates it.

**`fake_buffer = 0` is carried for stock parity, and its necessity is UNPROVEN.** A12 says it is
needed "so the dummy card presents a real (if discarded) ring buffer, which the `type file`
chain needs". I could not confirm that: booting the same kernel with `snd_dummy.fake_buffer=1`
on the cmdline produced an **identical** hw_params result (the contract triple still accepted,
the same four still rejected). Mechanically, `fake_buffer=1` selects `dummy_pcm_ops_no_buf`,
whose `.copy` discards and whose `.page` returns one shared page for every offset — which may
well be fine for a pure sink. **We ship 0 because stock ships 0**, which is the right call
regardless; but nobody has demonstrated that 1 breaks anything. If A12's claim matters to
anyone, it needs a real `speaker-test` on hardware to settle. Not a blocker either way.

**NOT verified — needs hardware (route to P1.13):**

* **`/dev/MrAudio` never appears in emulation**, because the driver only probes when an SPI
  device matches `compatible = "MiSTer,spi-audio"` — and that DT node is **P1.7's**
  (`0004-dts-de10nano-MiSTer.patch`), deliberately not carried here. Until P1.7 lands, the
  chrdev half of this patch is compiled but never exercised. P1.13 must assert `ls -l
  /dev/MrAudio` → `crw------- root root` (dynamic major, minor 0) and check `dmesg` for
  `MrAudio Audio buffer '/dev/MrAudio' created.`
* The **0600 root:root** mode is by construction, not measurement: the driver sets no `devnode`
  callback, so `devtmpfs_create_node()` applies its `req.mode == 0 ⇒ 0600` default
  (`drivers/base/devtmpfs.c`, **identical in 5.15 and 6.18**), and **no udev rule in the stock
  rootfs matches `SUBSYSTEM=="MrAudio_sys"`** (checked all of `lib/udev/rules.d/`; stock's
  `/dev` is empty of static nodes). So ours is the same as stock's — but neither has been
  *observed*.
* That the FPGA actually plays what is written to the ring (`spi_write()` of `Info_t`), and that
  the 512 KiB order-7 `dma_alloc_coherent()` succeeds at probe time on a 511 MiB machine.
* **End-to-end `/etc/asound.conf`**: `alsa-lib` is not in the Buildroot output yet (P3.8), so
  the full `plug → rate → file → hw:0` chain has not been opened by libasound. Only its
  `slave.pcm { type hw; card 0 }` leg is proved (above). **P1.13/P2.3 must run
  `speaker-test -c2 -r48000 -fS16_LE` and confirm both that it plays and that `/dev/MrAudio`
  receives bytes.**

---

### `0003-cpufreq-cyclone5-de10nano-overclock.patch` — **P1.6** (class A) ✅ **CARRIED**

> **Filename note:** shipped as `0003-cpufreq-cyclone5-de10nano-overclock.patch` (the earlier
> plan text said `0003-cpufreq-cyclone5-overclock.patch`).

**Origin:** `3d72b9db7` "Add cpufreq/overclock driver (#34)" + `e6df8e30e` "Improve clock
transition stability and get OSC1 freq from DT (#35)" — **Michael Huang**, 2022-10.
**Files:** `drivers/cpufreq/socfpga-cpufreq.c` (new, ~325 lines), `drivers/cpufreq/Kconfig.arm`
(`config ARM_SOCFPGA_CPUFREQ`, `depends on CPU_FREQ && CLK_INTEL_SOCFPGA32`),
`drivers/cpufreq/Makefile`.

**What it does.** A standard `cpufreq_driver` (`.name = "socfpga"`) that reprograms the Cyclone V
main PLL VCO. Frequency table (`socfpga-cpufreq.c:99`):

| Frequency | Flag |
|---|---|
| 1,200,000 kHz | `CPUFREQ_BOOST_FREQ` (overclock) |
| 1,000,000 kHz | `CPUFREQ_BOOST_FREQ` (overclock) |
| 800,000 kHz | — (stock max) |
| 400,000 kHz | — |

`.boost_enabled = false` by default; OC is opt-in. It finds the clock manager via
`of_find_compatible_node(NULL, NULL, "altr,clk-mgr")` and reads OSC1 from DT.

**ABI surface:** the **standard cpufreq sysfs** under
`/sys/devices/system/cpu/cpu[01]/cpufreq/`. Main_MiSTer does **not** touch cpufreq (verified — no
`cpufreq`/`scaling_` references); the consumers are community overclock scripts on `/media/fat`.
Stock governor: `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` with
performance/powersave/userspace/ondemand/conservative/schedutil all built in (P1.3 must match).

> ⚠ **[P1.6 correction] There is NO `/sys/devices/system/cpu/cpufreq/boost` file — not on 6.18,
> and *not on stock 5.15 either*.** The claim above (and in `abi-contract.md` §7.3, which cited
> this file) was wrong. `create_boost_sysfs_file()` is gated on `cpufreq_boost_supported()` ==
> `(cpufreq_driver->set_boost != NULL)`. This driver **never sets `->set_boost`**, never calls
> `cpufreq_enable_boost_support()`, and the fork **does not patch `drivers/cpufreq/cpufreq.c`**
> (`git show --stat 3d72b9db7` touches only `MiSTer_defconfig`, `Kconfig.arm`, `Makefile`,
> `socfpga-cpufreq.c`). So no boost file was ever created. `.boost_enabled = false` is inert.
>
> **The actual overclock mechanism is `scaling_max_freq`.** `socfpga_cpu_init()` sets
> `policy->cpuinfo.max_freq = 1200000`, and `cpufreq_frequency_table_cpuinfo()` deliberately
> honours a driver-supplied ceiling above the table max — *"If the driver has set its own
> cpuinfo.max_freq above max_freq, leave it as is."* (`drivers/cpufreq/freq_table.c`, **identical
> in 5.15 and 6.18**). The `CPUFREQ_BOOST_FREQ` rows are skipped when computing the table max, so
> without that assignment the board would cap at 800 MHz. **That one line IS the overclock
> feature.** Anyone "cleaning up" the redundant-looking `cpuinfo.max_freq` assignment silently
> removes overclocking.

**The 5.15 → 6.18 API churn actually hit (P1.6 outcome). The "low hazard / near-clean rebase"
prediction above was wrong: two of the four items are hard build failures, and the worst one is a
*silent runtime* failure that compiles fine.** Verbatim compiler output from building the
unmodified fork driver against pristine 6.18.38:

```
socfpga-cpufreq.c:135:1: warning: 'inline' is not at beginning of declaration [-Wold-style-declaration]
socfpga-cpufreq.c:143:16: error: too many arguments to function 'cpufreq_frequency_table_verify'
socfpga-cpufreq.c:274:26: error: initialization of 'void (*)(struct cpufreq_policy *)' from
                                 incompatible pointer type 'int (*)(struct cpufreq_policy *)'
                                 [-Wincompatible-pointer-types]
```

| # | Churn | Fix |
|---|---|---|
| 1 | `cpufreq_frequency_table_verify()` **lost its `table` argument** — now `(struct cpufreq_policy_data *)` only, reading `policy->freq_table` itself. (§5's "unchanged" was wrong.) | one-arg call |
| 2 | `struct cpufreq_driver::exit()` **returns `void`, not `int`** (`include/linux/cpufreq.h:406`). (§5's ".exit signature unchanged" was wrong.) | `static void socfpga_cpu_exit(...)` |
| 3 | `void inline wait_for_fsm(void)` is `-Wold-style-declaration`, and being non-`static` also trips v6.8's default `-Wmissing-prototypes` | `static void`; `socfpga_cpufreq_clk_mgr_base_addr` made `static` too |
| 4 | **🔥 `scaling_available_frequencies` must be dropped from `->attr`.** Since 6.x `cpufreq_add_dev_interface()` creates it itself for any policy with a `freq_table`. Leaving it in `->attr` makes the core's *second* `sysfs_create_file()` return `-EEXIST`, which **aborts policy creation** — the driver compiles, links, and then simply never registers. **This is invisible at build time.** | `->attr` keeps **only** `cpufreq_freq_attr_scaling_boost_freqs` |

Item 4's asymmetry is the subtle part: the core creates `scaling_boost_frequencies` **only** when
`cpufreq_boost_supported()` (i.e. `->set_boost` non-NULL), which this driver leaves NULL. So that
one *must stay* in `->attr` or the file disappears; and `scaling_available_frequencies` *must go*
or the driver dies. Confirmed correct against `struct cpufreq_driver` in 6.18: `struct freq_attr
**attr` (`:411`) and `bool boost_enabled` (`:416`) do still exist.

**Resulting sysfs — bit-for-bit identical to stock 5.15:**

| Path | Value |
|---|---|
| `…/cpu[01]/cpufreq/scaling_driver` | `socfpga` |
| `…/cpu[01]/cpufreq/scaling_governor` | default `performance` |
| `…/cpu[01]/cpufreq/cpuinfo_min_freq` | `400000` |
| `…/cpu[01]/cpufreq/cpuinfo_max_freq` | `1200000` ← **the OC ceiling** |
| `…/cpu[01]/cpufreq/scaling_max_freq` | writable, clamped to `cpuinfo_max_freq` ← **the OC switch** |
| `…/cpu[01]/cpufreq/scaling_available_frequencies` | `800000 400000` (core-created) |
| `…/cpu[01]/cpufreq/scaling_boost_frequencies` | `1200000 1000000` (`->attr`-created) |
| `…/cpu[01]/cpufreq/scaling_cur_freq`, `cpuinfo_cur_freq` | present (`->get` is set) |
| `/sys/devices/system/cpu/cpufreq/boost` | **does not exist** (and never did) |

**Config:** `CONFIG_ARM_SOCFPGA_CPUFREQ=y` added to `board/mister/de10nano/linux.config` by this
task — P1.3 could not have added it, because the symbol does not exist in vanilla 6.18. Stock
parity confirmed: `work/stock-linux.config:500` has it `=y`, and the stock image's
`usr/lib/modules/5.15.1-MiSTer/modules.builtin:233` lists
`kernel/drivers/cpufreq/socfpga-cpufreq.ko` as **built-in**.

#### ⚠ P1.6 → P1.7 hand-off: the DTS **must** set `osc1`'s rate

The driver reads `/clkmgr@ffd04000/clocks/osc1/clock-frequency` and computes every VCO frequency
from it. **Mainline does not provide it and neither does U-Boot:**

* mainline `socfpga.dtsi` declares `osc1` as a bare `compatible = "fixed-clock"` with **no**
  `clock-frequency`, and **no** mainline Cyclone V board DTS overrides it (checked
  `socfpga_cyclone5_{de10nano,socdk,de0_nano_soc,sockit}.dts` — zero `&osc1` overrides);
* the MiSTer U-Boot has **no** socfpga FDT fixup — no `ft_board_setup`, no
  `CONFIG_OF_BOARD_SETUP`, no `fdt_setprop`/`do_fixup` anywhere under `arch/arm/mach-socfpga/`,
  `board/altera/`, `board/terasic/`;
* but the **stock DTB does carry it**: `work/stock.dts:107-112` → `clock-frequency = <0x17d7840>`
  = **25,000,000**. (Consistent with the driver's own comments: *"25 MHz * (95 + 1) = 2400 MHz"*.)

⇒ ~~**`0004-dts-de10nano-MiSTer.patch` (P1.7) must add `&osc1 { clock-frequency = <25000000>; };`**~~

**[P1.7, 2026-07-12 — RETRACTED. No DTS change is needed; `0004` adds nothing for `osc1`.]**
`osc1` *is* the root of the entire gen5 clock tree, and it *does* carry the 25 MHz rate — but it
already does so, in **both** trees, via the SoC-family include rather than the board file:

| | file | line | value |
|---|---|---|---|
| fork (5.15) | `arch/arm/boot/dts/socfpga_cyclone5.dtsi` | 15-17 | `osc1 { clock-frequency = <25000000>; }` |
| mainline 6.18.38 | `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5.dtsi` | 13-18 | `osc1 { clock-frequency = <25000000>; }` |

Both board DTSes `#include` that file. The search that produced this open item looked at
`socfpga.dtsi` (where `osc1` is declared **rateless**, 6.18 line 124) and at the board `.dts`,
and missed the `socfpga_cyclone5.dtsi` layer in between. **This also closes the "open item"
below** — nothing is injected by the MiSTer release build; the property was in the fork's DTS
sources all along.

**Verified against the artifacts, not the sources:** `dtc -I dtb -O dts` on `work/stock.dtb` and
on the DTB built from `0004` both yield
`osc1 { #clock-cells = <0x00>; clock-frequency = <0x17d7840>; compatible = "fixed-clock"; }`
— `0x17d7840` = 25,000,000, byte-identical. See `docs/dts-comparison.md` §4.1.

**Why not `cpufreq-dt` + OPP tables?** (the honest upstream check — the preferred outcome would
have been to *drop* this patch)

**It cannot work, because the mainline gen5 socfpga clock driver is read-only:**

* **No `.set_rate` op exists anywhere in it.** `grep -n set_rate drivers/clk/socfpga/{clk,clk-gate,clk-pll,clk-periph}.c` → **no matches**. `clk_pll_ops` and `periclk_ops` are `{ .recalc_rate }` only; `gateclk_ops` adds only `.determine_rate`/`.get_parent`/`.set_parent`. `clk_set_rate()` on the MPU clock therefore **cannot change the frequency** — which is exactly what `cpufreq-dt` needs. `socfpga_clk_determine_rate()` even ignores the requested rate and returns `best_parent_rate / div`, i.e. the *current* rate.
* The `cpu@0`/`cpu@1` nodes in `socfpga.dtsi` have **no `clocks` property**, so `cpufreq-dt`'s `clk_get(cpu_dev)` would fail `-ENOENT` regardless.
* Nothing named `altr`/`socfpga` appears in `cpufreq-dt-platdev.c`'s allowlist.
* Structurally, an OPP row ("one clock + one regulator") **cannot express this transition**: four clocks derived from one VCO (`mpuclk`, `mainclk`, `dbgatclk`, `cfgs2fuser0clk`) must be reprogrammed as a single order-dependent sequence — bypass the main PLL, then apply dividers and VCO in an order that depends on whether the target VCO is above or below the current one — while holding `mainclk`/`dbgatclk` at 400 MHz and `cfgs2fuser0clk` at 100 MHz.

Supporting `cpufreq-dt` would mean **adding `.set_rate`/`.determine_rate` to a clock driver shared
by every Cyclone V board** — a far larger, riskier change than carrying a self-contained
out-of-tree driver, and untestable without hardware. **Verdict: carry the patch.** There is no
mainline commit that supersedes it; mainline has no socfpga cpufreq driver at all
(`grep -rin 'socfpga\|altera\|altr' drivers/cpufreq/` in 6.18.38 → **no matches**).

#### Known latent bug — **deliberately preserved, not fixed**

`wait_for_fsm()` calls `wait_on_bit(word, bit, mode)` with an `__iomem` pointer and passes
`CLKMGR_STAT_BUSY` — a **mask** (`BIT(0)` == 1) — where a **bit number** is expected. It therefore
polls **bit 1** of `CLKMGR_STAT`, not bit 0 (BUSY). `wait_on_bit()` also does a plain `test_bit()`
on MMIO rather than `readl()`, and if the bit were ever observed set it would sleep
`TASK_UNINTERRUPTIBLE` on a wait queue **that no hardware can ever wake**. In practice it returns
immediately and PLL settling is covered by register-write latency — which is why the stock kernel
works. Fixing it changes PLL transition timing, which **cannot be validated without a DE10-Nano on
the bench**; a forward-port is the wrong place to smuggle in an untested change to clock
sequencing. Carried verbatim, flagged for hardware bring-up (P1.13).

**Verified (build-time, actually executed):**

* `git apply --check -v` against a freshly-extracted pristine v6.18.38 → **clean** (exit 0);
  `patch -p1 --dry-run` (Buildroot's applier) likewise → **clean** (exit 0).
* From pristine: apply → `olddefconfig` (symbol survives) → `make W=1
  drivers/cpufreq/socfpga-cpufreq.o` → **zero warnings, zero errors**.
* Full `zImage` build of the patched tree with the board `linux.config`: **zero warnings, zero
  errors**; driver confirmed linked in — `nm vmlinux` shows
  `__initcall__kmod_socfpga_cpufreq__213_380_socfpga_cpufreq_init6`, `socfpga_cpufreq_driver`,
  `socfpga_target_index`, `socfpga_get`.

**Not verified (needs hardware):** that the PLL actually retimes and the board is stable at
1.0/1.2 GHz; the `wait_for_fsm()` bit above. No DE10-Nano was available.

---

### `0004-dts-de10nano-MiSTer.patch` — **P1.7** (class A, 13 commits)

**Origin:** `aa8afe109` (base DTS) + 12 follow-ups. **Files:**
`arch/arm/boot/dts/socfpga_cyclone5_de10_nano.dts` (fork) → to be re-based on mainline's
`arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts` (present in 6.18; introduced by
**`144616a80889`** *ARM: dts: socfpga: Add basic support for Terrasic's de10-nano*, 2025-02-03),
plus **one hunk in `arch/arm/boot/dts/socfpga.dtsi`**.

**Everything the fork's DTS adds** (full node list — diff against mainline node-by-node in
`docs/dts-comparison.md`, do **not** work from memory):

| Node | Content |
|---|---|
| `chosen` | `bootargs = "earlyprintk"`, `stdout-path = "serial0:115200n8"` |
| `memory` | `reg = <0x0 0x40000000>` (1 GB; cmdline `mem=511M` overrides) |
| `regulator_3_3v` | `regulator-fixed`, 3.3 V |
| `leds` | `gpio-leds`, `hps0` → label **`hps_led0`**, `gpios = <&portb 24 0>`, `linux,default-trigger = "mmc0"` |
| `i2c_gpio` | `i2c-gpio` bus on `&portb 22/23` (open-drain), `delay-us = <2>`; children `pcf8563@0x51`, `m41t81@0x68`, `mcp7941x@0x6F` (RTC add-on board) |
| `MiSTer_fb` | `compatible = "MiSTer_fb"`, `reg = <0x22000000 0x800000>`, `interrupts = <0 40 1>`, `interrupt-parent = <&intc>` |
| `&gmac1` | `status=okay`, `phy-mode = "rgmii"`, all 12 `*-skew-ps` values, **`max-frame-size = <3800>`** |
| `&gpio0/1/2` | enabled |
| `&i2c0` | `speed-mode = <0>`, `adxl345@53` |
| `&i2c2` | enabled, `clock-frequency = <100000>`, `speed-mode = <0>` |
| `&spi0` | `timeouts = <3>`; child `spiusb@0` → `compatible = "MiSTer,spi-audio"`, 10 MHz, `spi-cpha`, `spi-cpol` |
| `&spi1` | `timeouts = <3>`; child `spibri@0` → `compatible = "altspi"`, 25 MHz → `/dev/spidev1.0` (**§13 / N2**) |
| `&mmc0` | `vmmc-supply`/`vqmmc-supply` = `&regulator_3_3v` |
| `&uart0`, `&uart1` | enabled, **`/delete-property/ dmas` + `dma-names`** (DW UART DMA is broken) |
| `&usb1` | **`disable-over-current`**, `dr_mode = "host"` |
| `&fpga_bridge0/1/2` | enabled |
| **`socfpga.dtsi`** | `i2c1`: `clock-frequency = <100000>` — ⚠ **a change to the shared SoC dtsi, not the board DTS.** Decide at P1.7 whether to move it into the board file (preferred — keeps the patch off a shared file) or carry the dtsi hunk. |

**Hazards:** mainline's DTS lives at a different path (`intel/socfpga/…de10nano.dts`, no
underscore) and includes `socfpga_cyclone5.dtsi`; node names/labels are stable. `dtc` in 6.18 is
stricter — expect new warnings on the unit-address-less nodes (`MiSTer_fb`, `i2c_gpio`,
`leds`) and on `rtc_at_51`-style names without `@reg`. `071d9092e` already did one round of
warning-fixing on 5.15; expect another.

#### ✅ DONE — P1.7, 2026-07-12 (Michael C. Ferguson)

Shipped as `board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch`.
**Re-authored** on top of mainline's board DTS, not replayed. Full node-by-node evidence:
**`docs/dts-comparison.md`**. Resolutions to the open questions above:

* **The `socfpga.dtsi` hunk is NOT carried.** `i2c1` is `disabled` on this board in stock
  *and* in ours, so its `clock-frequency` is never read (probe never runs). Dropping it keeps
  patch `0004` off a file shared by every socfpga board — the option P0.4 marked "preferred".
* **`dtc`: zero new warnings**, at default `DTC_FLAGS` *and* at `W=1` (baseline: 0 / 5 —
  the 5 are pre-existing `simple_bus_reg` complaints in the shared `socfpga.dtsi`). The
  predicted `unit_address_vs_reg` warnings were real; fixed by giving `MiSTer_fb` and the
  three RTC nodes unit addresses (`MiSTer_fb@22000000`, `rtc@51/68/6f`). Both renames are
  provable no-ops — drivers match on `compatible`, and `of_device_make_bus_id()` builds the
  platform-device name from the translated `reg` + `%pOFn` (unit address stripped),
  `drivers/of/device.c:298-305`.
* **Dead properties dropped:** `speed-mode` (i2c0/i2c2) and `timeouts` (spi0/spi1) — a
  whole-tree `grep` of 6.18 for either string in `*.c`/`*.h` returns **zero hits**. Bus speed
  is unchanged (100 kHz on both i²C buses, as stock).
* **`aliases { ethernet0 = &gmac1; }` is load-bearing** and is carried: U-Boot's
  `fdt_fixup_ethernet()` (`common/fdt_support.c:470`, called from `image_setup_libfdt()`
  `common/image-fdt.c:497`) uses it to inject `$ethaddr`. Mainline's dtsi does not have it.
* **A14 (the HDMI killer) is proven**, not assumed: exactly **three** i²C adapters
  (`i2c0`, `i2c2`, `i2c_gpio` — byte-identically stock's), **no `i2c` aliases**, so
  `i2c_add_adapter()` takes the dynamic path and `idr_alloc()`s from
  `__i2c_first_dynamic_bus_num == 0` ⇒ the only possible numbers are **{0, 1, 2}**. No
  adapter can be numbered ≥ 3. Full argument, including probe order and the
  `I2C_DESIGNWARE_PLATFORM` config dependency, in `docs/dts-comparison.md` §2.
* **`osc1` needs no hunk.** `socfpga.dtsi:124` declares it rateless, but
  `socfpga_cyclone5.dtsi:13-18` — which the board DTS includes — sets
  `clock-frequency = <25000000>`. The built DTB is byte-identical to stock here (`0x17d7840`).

---

### `0005-spidev-accept-altspi-compatible.patch` — **P1.8** (class A, §13 / N2)

**Origin:** `246984fce` "Enable SPI on LTC. Use HPS LED for SD card activity.", Sorgelig,
2018-02-06. **File:** `drivers/spi/spidev.c` — one line added to `spidev_dt_ids[]`.

**Consumer:** `Main_MiSTer/brightness.cpp` opens **`/dev/spidev1.0`** (I/O-board brightness).

**The hazard, precisely.** 6.18's spidev binds **only** compatibles in `spidev_dt_ids[]`
(`6.18 drivers/spi/spidev.c:720`). An `altspi` node not listed there **never probes** →
`/dev/spidev1.0` never appears → brightness control silently dies. (`spidev_of_check()` at
`:711` is a *different* guard — it only rejects the literal string `"spidev"` in DT.)

**Preferred fix (P1.8):** change the DTS `compatible` to one 6.18 already accepts and drop this
patch entirely. We ship our own DTB, so nothing breaks. **Fallback:** re-add the one-liner; note
6.18's entries carry `.data = &spidev_of_check`, and an entry *without* `.data` is safe because
`spidev_probe()` (`:763`) only invokes the callback when `device_get_match_data()` is non-NULL.

**Assert in P1.13's boot log:** `/dev/spidev1.0` exists.

#### ❌ DROPPED — resolved by P1.7, 2026-07-12. This patch does not exist and never will.

The "preferred fix" was taken. `0004-…`'s `spi1` child uses
**`compatible = "rohm,dh2228fv"`**, which is already in 6.18's `spidev_dt_ids[]` *and*
`spidev_spi_ids[]`, so spidev probes it with a stock kernel and no `drivers/spi/spidev.c`
hunk is needed. Rationale for that particular string (it is the de-facto mainline
"userspace-driven SPI slave" placeholder; `spidev_of_check()` only rejects the literal
`"spidev"`; the real device is an add-on **hub** — brightness/lid,
`Main_MiSTer/brightness.cpp` — which no in-table compatible describes anyway) is in
`docs/dts-comparison.md` §5, together with the proof that the node still lands on **SPI bus
1, CS 0 ⇒ `/dev/spidev1.0`** (no `spi` aliases ⇒ `spi_register_controller()` numbers
controllers dynamically in probe order, exactly as on stock).

**§6's patch list therefore has no `0005`.** The numbering gap is intentional — do not
renumber `0010`+ to close it.

---

### `0010`–`0030` — classes D & F ✅ **P1.9 LANDED (partial — see escalations)**

Per-patch detail is in the §3.4 and §3.7 tables (origin, files, upstream evidence, target
filename). Owner: **P1.9** ([SONNET]). Done 2026-07-12 by Michael C. Ferguson, working tree
`work/k-hid/` (pristine 6.18.38). 15 of 18 planned patches carried; 3 escalated. Full kernel
build (`zImage` + `modules`) with the final `board/mister/de10nano/linux.config` (which now
also carries the new `CONFIG_HID_GUNCON2/3`, `CONFIG_HID_FTEC`,
`CONFIG_HID_GAMECUBE_ADAPTER(_FF)`, `CONFIG_HID_VADER4=m` lines this task's drivers need):
**zero warnings, zero errors.** All 18 landed patches verified with `git apply --check`
against a pristine 6.18.38 tree, both individually and as the full ordered series.

**Carried (18 files, `board/mister/de10nano/linux-patches/`):**
`0010-hid-guncon2.patch`, `0011-hid-guncon3.patch`, `0012-hid-fanatec.patch`,
`0013-hid-flydigi-vader.patch`, `0014-hid-gamecube-adapter.patch`,
`0016-hid-microsoft-elite2-paddles.patch`, `0017-xpad-mister-deltas.patch`,
`0018-hid-controllable-quirk.patch`, `0019-hidpp-k400-fn-inversion.patch`,
`0020-mmc-no-led-on-send-status.patch`, `0022-hid-playstation-ds4-mac-fix.patch`,
`0023-hid-wiimote-fixes.patch`, `0024-hid-input-keyrah-europe1.patch`,
`0025-usbhid-jspoll-gamepad.patch`, `0027-mt76x2u-release-xbox-adapter-ids.patch`,
`0028-dwc2-fix-unaligned-in-split.patch`, `0029-leds-gpio-brightness-hw-changed.patch`,
`0030-i2c-designware-quiet-timeout.patch`. Every file carries a full provenance header
(origin commit(s)/URL, author, upstream status, forward-port notes, `Signed-off-by`).

**New findings during the port (P0.4 re-verification, per task instructions):**

* **`1412bd707` (hid-sony div-by-0, folded into old `0022`) is superseded upstream**, not by a
  byte-identical fix but a *better* one: `hid-playstation.c`'s DualSense/DualShock4 calibration
  setup now sanity-checks every `sens_denom` for zero at calibration-parse time (init-time
  guard with a safe fallback) instead of the fork's per-report-parse ternary. Dropped.
* **`5c410e935` (hid-sony 3rd-party DS4 wired-connect fix) is NOT superseded, but its target
  moved.** DualShock4 handling was split out of `hid-sony.c` into the new upstream
  `hid-playstation.c` (`dualshock4_get_mac_address()`), which has the identical
  hard-fail-on-read-error bug in its new home. Re-targeted; carried as
  `0022-hid-playstation-ds4-mac-fix.patch` (renamed from the planned
  `0022-hid-sony-fixes.patch`).
* **Class C's three explicitly-named "carry" items in the P1.9 task text are all confirmed
  still upstream-superseded** (re-verified directly against `work/k-hid`, not re-derived from
  this document): usb-storage Realtek CD-ROM blacklist (`unusual_devs.h:1509`, exact IDs
  `0x0bda,0x1a2b`), btusb TP-Link UB500 (`btusb.c:787`, `0x2357,0x0604`), btusb Edimax BT-8500
  (`btusb.c:797`, `0x7392,0xc611`). Not carried, no `00xx` file — matches §3.3's original
  triage exactly.
* **`hid-microsoft`'s device-table macro was renamed upstream**:
  `USB_DEVICE_ID_MS_XBOX_ELITE2_CONTROLLER` (fork, 5.15) →
  `USB_DEVICE_ID_MS_XBOX_CONTROLLER_MODEL_1797_BLE` (6.18) — same numeric ID (`0x0b22`).
  `0016` retargets to the new name.
* **Two API removals hit twice each, not predicted by P0.4:** `usb_maxpacket()` dropped its
  3rd (direction) argument (hit in `0011`); `hrtimer_init()` + assigning `->function` was
  replaced by a single `hrtimer_setup()` call, v6.12 (hit in `0012`, matching what P1.4
  independently found for a *different* API,
  `platform_driver::remove()` returning `void` — the general pattern of "helper signature
  simplified by folding two calls into one" recurs across subsystems in this kernel gap).
  `hid_is_using_ll_driver(hdev, &usb_hid_driver)` was removed entirely (`usb_hid_driver` became
  file-static once the USB-specific `hid_is_usb()` helper landed, v5.2) — hit in `0014`.
  `hidpp_root_get_feature()` dropped its `feature_type` output parameter, and `k400_connect()`
  dropped its `bool connected` parameter — both hit in `0019`.
* **A latent bug found and fixed while porting `0019`:** the fork's own K400-Fn-inversion patch
  reused `k400->feature_index` (already claimed by `k400_disable_tap_to_click()`'s HID++
  feature cache) for the unrelated Fn-inversion feature lookup too. Whichever call ran second
  would see a stale non-zero index and skip its own lookup, sending its `SetFeature` command at
  the wrong feature index. Given a dedicated `fn_feature_index` field instead of sharing.

**Escalated to [OPUS] — not ported, left as `.c` in the fork only.**
**➡ ALL THREE NOW RESOLVED — see §9 for the [OPUS] dispositions** (`0026` and `0015` landed;
`0021` deliberately not carried). P1.9's escalation reasoning below is preserved as written,
including the parts §9 corrects (`0021`'s "orphaned `G920` ID" claim is **wrong** — see §9.3).

* **`0026-input-mousedev-eviocgrab.patch`** — out of scope for P1.9 by design (TASKS.md P1.9
  explicit ruling: not a HID quirk, a core input-subsystem patch). Not attempted here. See
  original analysis below (unchanged from P0.4).
* **`0015-hid-nintendo-nso-famicom.patch`** (`484f68172`, NSO Famicom controllers) — **new
  finding: upstream `hid-nintendo.c` was substantially reorganized** since the fork's 5.15
  base (2,564 → 2,853 lines). The fork's patch is written against a macro-based type-detection
  idiom (`#define jc_type_is_nescon(ctlr) (...)`, `jc_type_is_joycon`, `jc_type_is_nso`,
  `jc_has_rumble`); 6.18 replaced every one of those macros with `static inline bool
  joycon_type_is_*()` helper functions with different names and different combining logic
  (e.g. `joycon_type_is_any_nescon()` merges what were separate left/right macros), and the
  `jc_type_is_nso`/`jc_has_rumble` macros have no direct successor — their logic is now spread
  across the refactored helpers. Porting Famicom support (`JOYCON_CTLR_TYPE_FAMIL/FAMIR`, new
  `jc_type_is_famircon`-equivalent, button-input-array wiring, mic-capability exclusion per the
  commit's "no mic for Famicom R" note) correctly requires understanding this new scheme
  end-to-end, not a mechanical port. **Flagged for [OPUS] per the P1.9 escalation rule**
  ("stop on that one... rather than forcing it").
* **`0021-hid-lg4ff-g923.patch`** (`8a100f2ed` + `43c52e9ef`, G923 wheels + 32-bit rumble/FF
  fix) — **new finding: depends entirely on an out-of-tree architecture that never landed
  upstream.** The fork's `8a100f2ed` is itself a ~2,000-line wholesale rewrite of
  `hid-lg4ff.c` (1,500 → 2,378+ lines) pulling in Bernat Arlandis's well-known out-of-tree
  memless-FF-timer "new-lg4ff" project (hrtimer-driven slot scheduler, mirroring the same
  pattern as `0012`'s Fanatec driver). **6.18's `hid-lg4ff.c` is still the pre-2019 old-style
  driver** (1,500 lines, no `hrtimer`, no `LG4FF_VERSION`) — the rewrite was never merged
  upstream. Confirmed `USB_DEVICE_ID_LOGITECH_G920_WHEEL` (already in `hid-ids.h`) is an
  **orphaned ID**: not referenced anywhere in `hid-lg4ff.c` or `hid-lg.c`, meaning even G920
  wheel support is not actually wired up in mainline today, let alone G923. Adding just the
  `hid-lg.c` device-table entries (the smaller, separable half of `43c52e9ef`) without a
  matching `lg4ff_devices[]` entry would make `lg4ff_init()` hard-fail
  (`hid_err(...); error = -1;`) on probe — the wheel wouldn't even come up as a plain gamepad.
  A correct, minimal port requires hand-authoring a `lg4ff_devices[]` entry (effects/range/
  mode-switch tables) against the *old* architecture from protocol knowledge, not a diff
  replay. Given force feedback on a physical steering wheel is safety/feel-sensitive and the
  actual fix (the 32-bit rumble bug) is inseparable from the rewritten architecture, **flagged
  for [OPUS]** rather than shipping a half-working wheel driver.

**Carried against the provenance doc's own suggestion — reviewed and overturned:**

* **`0028-dwc2-fix-unaligned-in-split.patch`** was flagged above (original analysis, preserved
  below for the record) for **[OPUS]** escalation on the theory that "a real bug fix, not a
  quirk" needed more careful handling. Hands-on inspection during P1.9 found
  `dwc2_hc_xfercomp_intr()` / `dwc2_xfercomp_isoc_split_in()` structurally **unchanged** since
  5.15 (same `dwc2_get_actual_xfer_length()` helper, same call sites, same context) — no
  upstream reorganization to navigate. Carried as a normal mechanical port instead of
  escalating; see the P1.9 report for the full reasoning. *(Original P0.4 analysis, for
  the record: "a real dwc2 bug fix, not a quirk. Moves the `align_buf` bounce-buffer `memcpy`
  out of `dwc2_xfercomp_isoc_split_in()` and gates it on `chan->align_buf && chan->ep_is_in &&
  qtd->complete_split`, using `dwc2_get_actual_xfer_length()` instead of `len`. 6.18 still has
  the old code (`hcd_intr.c:922-928`). Recommend submitting upstream — it benefits every dwc2
  user, and upstreaming it removes a carried patch permanently." That upstream-submission
  recommendation still stands independently of this fork.)*
* **`0017-xpad-mister-deltas.patch`** was flagged above for possible escalation
  ("do not port the [wholesale-sync] commit; port the MiSTer-specific deltas... the delta is
  genuinely small"). Confirmed small and non-restructured on inspection — all four target
  functions/tables (`xpad_device[]`, `xpad_probe()`, `xpad_init_output()`,
  `xpad360_process_packet()`, `xpad_init_input()`, `xpad_disconnect()`) are structurally
  unchanged from the fork's 5.15 base. Carried in full, including the ~230-line Flydigi V2
  raw-mode client for the Vader 5 Pro. **HW verification pending (flag for P3.13):** the
  Flydigi V2 protocol implementation and the GIP-exclusion/xone hand-off are ported faithfully
  but not bench-tested against real hardware here.

---

## 6. Mapping onto PLAN §6's `linux-patches/` filenames

§6 lists 10 files. The verified triage needs **more**, because §6's class D/F list is
incomplete. Proposed final set (P1.9 confirms):

| §6 planned | Status |
|---|---|
| `0001-fbdev-add-MiSTer_fb-driver.patch` | ✅ **landed (P1.4)** — as planned. Applies clean to 6.18.38, builds warning-free at `W=1`. Also carries `CONFIG_FB_MISTER=y` into `linux.config`. See §5. |
| `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch` | ✅ **landed (P1.5)** — renamed from `0002-sound-add-MiSTer-audio-spi.patch` because it **does** carry the `dummy.c` hunks (N4), and the name should say so. Applies clean to 6.18.38, builds warning-free at `W=1`. Also carries `CONFIG_SND_MISTER_AUDIO=y` into `linux.config`. See §5. |
| `0003-cpufreq-cyclone5-de10nano-overclock.patch` | ✅ carried (P1.6). Renamed from `0003-cpufreq-cyclone5-overclock.patch`. `cpufreq-dt`/OPP **cannot** replace it (gen5 clk driver has no `.set_rate`). Two hard API breaks + one silent `-EEXIST` sysfs trap fixed. ~~Requires P1.7 to add `&osc1 { clock-frequency = <25000000>; }`.~~ **[P1.7: no DTS change needed — claim retracted.]** P1.6 read only `socfpga.dtsi:124` (where `osc1` is declared rateless); **`socfpga_cyclone5.dtsi:13-18`**, which the board DTS `#include`s, already sets `clock-frequency = <25000000>`. Verified in the **built DTB**: `osc1 { clock-frequency = <0x17d7840>; }` — byte-identical to `stock.dtb`. Stock's DTS also has **no** OPP/`operating-points` nodes anywhere, consistent with carrying the driver. |
| `0004-dts-de10nano-MiSTer.patch` | ✅ **landed (P1.7)** — re-authored on mainline's board DTS. **Zero new `dtc` warnings** (default *and* `W=1`); built DTB decompiled and diffed node-by-node against `stock.dtb`. The `socfpga.dtsi` i2c1 hunk is **not carried** (i2c1 is `disabled`; the property is never read) — patch stays off the shared SoC file. **A14 proven**: exactly 3 i²C adapters, no `i2c` aliases ⇒ numbers can only be {0,1,2}. See `docs/dts-comparison.md`. |
| `0005-spidev-accept-altspi-compatible.patch` | ❌ **DROPPED — eliminated by P1.7.** The DTS uses `compatible = "rohm,dh2228fv"`, already in 6.18's `spidev_dt_ids[]`, so no kernel hunk is needed. Node still lands on bus 1 CS 0 ⇒ `/dev/spidev1.0`. The `0005` slot stays empty — **do not renumber**. See §5 and `docs/dts-comparison.md` §5. |
| `0010-hid-guncon2.patch` | ✅ **landed (P1.9)** — as planned. Applies clean to 6.18.38, builds warning-free at `W=1`. |
| `0011-hid-guncon3.patch` | ✅ **landed (P1.9)** — `usb_maxpacket()` 3-arg→2-arg forward-port fix (see §5 below). |
| `0012-hid-fanatec.patch` | ✅ **landed (P1.9)** — `hrtimer_init()`→`hrtimer_setup()` forward-port fix (see §5). |
| `0013-hid-flydigi-vader.patch` | ✅ **landed (P1.9)** — unmodified (the `hid-vader4.c` BT driver; the *xpad* Vader work is `0017`) |
| `0020-usb-storage-blacklist-realtek-cdrom.patch` | ❌ **DELETE — upstream, confirmed (P1.9)** (`a3dc32c635ba`; re-verified directly against `work/k-hid`: `unusual_devs.h:1509`) |
| `0014-hid-gamecube-adapter.patch` | ✅ **landed (P1.9)** — Nintendo WUP-028 (057e:0337). `hid_is_using_ll_driver()`→`hid_is_usb()` forward-port fix. |
| `0015-hid-nintendo-nso-famicom.patch` | ✅ **landed (P1.9-esc, [OPUS])** — re-implemented against 6.18's typed-helper + `joycon_ctlr_button_mapping` scheme; the 5.15 diff applies in no form. Builds warning-free at `W=1`. See §9. |
| `0016-hid-microsoft-elite2-paddles.patch` | ✅ **landed (P1.9)** — Elite 2 paddles over BT. Device-table macro renamed upstream (`USB_DEVICE_ID_MS_XBOX_ELITE2_CONTROLLER`→`..._MODEL_1797_BLE`, same ID). |
| `0017-xpad-mister-deltas.patch` | ✅ **landed (P1.9)** — cpoll, GIP exclusions, Vader 3/4/5 Pro (incl. the full Flydigi V2 raw-mode client), Qanba. Confirmed non-restructured on inspection; carried in full rather than escalated. HW verification pending, flag for P3.13. |
| `0018-hid-controllable-quirk.patch` | ✅ **landed (P1.9)** — 1209:FACA, unmodified. |
| `0019-hidpp-k400-fn-inversion.patch` | ✅ **landed (P1.9)** — K400r / K400 Plus. `hidpp_root_get_feature()`/`k400_connect()` signature forward-port fixes; also fixed a latent feature-index cache-sharing bug in the fork's own patch (see §5). |
| `0020-mmc-no-led-on-send-status.patch` | ✅ **landed (P1.9)** — *(number freed by the deletion above)*, unmodified. |
| `0021-hid-lg4ff-g923.patch` | ❌ **NOT CARRIED — deliberate (P1.9-esc, [OPUS]).** No `00xx` file. The G923 *Xbox* variant is already fully supported upstream by `hid-logitech-hidpp`; the G923 *PlayStation* variant would need ~120 lines of never-executed, hardware-untestable FF-wheel plumbing whose failure mode is a wheel with **no driver at all**. Narrow, documented regression accepted. Full reasoning + a complete recipe for whoever has the hardware: §9. |
| `0022-hid-playstation-ds4-mac-fix.patch` | ✅ **landed (P1.9)**, renamed from `0022-hid-sony-fixes.patch`. DS4 support (incl. MAC-address retrieval) moved from `hid-sony.c` to the new upstream `hid-playstation.c`; div-by-0 half dropped (already superseded upstream by init-time `sens_denom` guards); 3rd-party-wired-DS4 half re-targeted to `dualshock4_get_mac_address()`. |
| `0023-hid-wiimote-fixes.patch` | ✅ **landed (P1.9)** — uniq, buttons, analog. Also extended the uniq fix to `wiimod_turntable_probe()` (a module added upstream after the fork's 5.15 base). |
| `0024-hid-input-keyrah-europe1.patch` | ✅ **landed (P1.9)** — Europe-1 → `KEY_F24`, byte-identical. |
| `0025-usbhid-jspoll-gamepad.patch` | ✅ **landed (P1.9)** — jspoll for gamepads, unmodified (dropped 3 unconditional debug `pr_info()`s). |
| `0026-input-mousedev-eviocgrab.patch` | ✅ **landed (P1.9-esc, [OPUS])** — the one that mattered: without it a USB mouse dies the instant a core launches. `input_pass_values()` rewritten against 6.18's `->handle_events()` + `scoped_guard(rcu)`; the name-prefix hack replaced by an explicit `input_handler->ignore_grab` opt-in. Builds warning-free at `W=1`. See §9. |
| `0027-mt76x2u-release-xbox-adapter-ids.patch` | ✅ **landed (P1.9)** — let xone bind 045e:02e6/02fe, unmodified. |
| `0028-dwc2-fix-unaligned-in-split.patch` | ✅ **landed (P1.9)** — carried, not escalated. See §5 for why this overturns the earlier `[OPUS]`/"submit upstream" recommendation; upstream submission is still separately worth doing. |
| `0029-leds-gpio-brightness-hw-changed.patch` | ✅ **landed (P1.9)** — consumer confirmed (Main_MiSTer polls it for the disk-activity LED), kept per explicit Phase 0 ruling. |
| `0030-i2c-designware-quiet-timeout.patch` | ✅ **landed (P1.9)** — cosmetic, forward-ported to the new `i2c_dw_wait_transfer()` call site. |
| *(pending N1 decision)* `00xx-exfat-*` | **class G — see N1** |

**Dropped relative to §6/§4.1:** the `loop=` patch (class B, by design), 22 class-C commits +
1 more found by P1.9 (`1412bd707` div-by-0, superseded by init-time guards in
`hid-playstation.c`), the `dwc2/core.c` no-op (N5, **confirmed dropped P1.9** — owned by
`0004-dts-de10nano-MiSTer.patch`/P1.7, which must carry only the DTS half of `077c2c317`),
`vt.h` (F-3, **confirmed dropped P1.9**), and `mt7601u` (F-4, **confirmed dropped P1.9**).

---

## 7. Open questions / risks for the P0.9 review gate

| # | Question | Severity | Owner |
|---|---|---|---|
| **Q1** | **exfat (N1): (a) accept losing symlinks on `/media/fat`, (b) forward-port the out-of-tree driver, or (c) add `ATTR_SYSTEM` symlink support to mainline exfat?** Main_MiSTer actively resolves symlinks (`file_io.cpp:1592`). Nothing in the plan budgets this. | **HIGH** | P0.9 → P1.3/P1.10 |
| **Q2** | Does anything in the community actually *use* symlinks on `/media/fat`? If a survey says no, Q1 collapses to (a) + a release note. **Needs a human/community answer — I cannot determine it from the repos.** | **HIGH** | human |
| **Q3** | `/media/fat` mount options (N3): replicate `sync,dirsync`, or deliberately switch to async and document the power-off-corruption trade-off? | MEDIUM | P1.10 |
| **Q4** | FAT32 `iocharset`: stock is effectively `utf8`; mainline vfat defaults to `iso8859-1`. Set `-o iocharset=utf8` (and/or `CONFIG_FAT_DEFAULT_UTF8=y`)? | MEDIUM | P1.3/P1.10 |
| **Q5** | btusb CSR clones (`b02a4a011`): 6.18's detector is a superset but does **not** cover `lmp_subver == 0x2512`. Do we drop and risk one fake-dongle model, or carry a 1-line addition? | MEDIUM | P3.13 (HW) |
| **Q6** | ~~`leds-gpio` `brightness_hw_changed` (F-2): no consumer found in Main_MiSTer. Confirm at P0.5, then drop if truly unused.~~ **DECIDED (P1.9):** consumer confirmed (Main_MiSTer polls it for the disk-activity LED per TASKS.md P1.9's explicit ruling) — kept, carried as `0029-leds-gpio-brightness-hw-changed.patch`. | LOW | ~~P0.5~~ done |
| **Q7** | ~~`mt7601u` DPD hack (F-4) and `vt.h` (F-3): recommend dropping both. Confirm.~~ **DECIDED (P1.9):** both confirmed dropped per TASKS.md P1.9's explicit ruling (`vt.h`) and P1.9's own judgment, out of task scope (`mt7601u`, F-4's "unprincipled" assessment stands). | LOW | ~~P0.9~~ done |
| **Q8** | `socfpga.dtsi` `i2c1 clock-frequency` hunk: move into the board DTS instead of patching the shared SoC dtsi? | LOW | P1.7 |
| **Q9** | DualSense (4 class-C commits): upstream `hid-playstation` has all the features, but MiSTer's LED/mute *semantics* may differ. Verify controller behaviour on hardware. | LOW | P3.13 |
| **Q10** | Stock config is 15 months older than fork HEAD (missing `HID_VADER4`, `MACVLAN`). P1.3 must reconcile `stock-linux.config` **and** HEAD's `MiSTer_defconfig`. | LOW | P1.3 |

### Proposed additions to PLAN.md's A1–A9 index (for P0.9)

* **A10 — `/media/fat` is a kernel-mounted, `sync,dirsync,noatime,nodiratime`, UTF-8, *symlink-capable*
  filesystem.** Stock mounts FAT32 **and** exFAT through a single out-of-tree exfat driver that
  supports symlinks (`ATTR_SYSTEM` bit) and defaults to `iocharset=utf8`; nothing in
  `/etc/fstab` re-mounts it. Mainline exfat/vfat provide **neither** symlinks nor UTF-8 by
  default. Any replacement must reproduce mount flags, codepage **and** decide the symlink
  question. [N1, N3, §4] → P1.3, P1.10
* **A11 — The audio ABI is `/dev/MrAudio` + a patched `snd-dummy` glued by `/etc/asound.conf`.**
  Not a conventional ALSA driver. `CONFIG_SND_DUMMY=y` is mandatory; the `dummy.c` patch ships
  with `0002-…`; `/etc/asound.conf` ships in the rootfs overlay. [N4] → P1.5, P2.3
* **A12 — Main_MiSTer relies on mousedev receiving events while evdev is `EVIOCGRAB`-ed.**
  A core `drivers/input/input.c` + `mousedev.c` patch, not a HID quirk. [§6 `0026`] → P1.9
  **SATISFIED (P1.9-esc, [OPUS]): `0026-input-mousedev-eviocgrab.patch`.** A12 is sharper than
  it reads, and §9.1 states it exactly: Main_MiSTer's *primary* mouse data path is the ImPS/2
  packet stream from `/dev/input/mouseN`, and it `EVIOCGRAB`s that same mouse's **evdev** node
  whenever a core is running or the OSD is up. Without the patch the grab starves mousedev and
  **the mouse dies in every core.** Not a nicety — the difference between a working mouse and
  no mouse, for every user who owns one.

---

## 8. Reproducing this triage

`scripts/triage/regen-triage.sh` regenerates every number in §1 from scratch (downloads the
pristine tarball, verifies its hash, builds the blob-hash listings, and prints the added /
removed / modified counts plus the reconciliation). Text output only; nothing is committed.

Reference trees used (all under gitignored `work/`, see `docs/reference-materials.md`):

| Tree | Ref | Purpose |
|---|---|---|
| `work/linux-5.15.1/` | tarball, SHA-256 `32fdcd33…14c8` (kernel.org signed sums) | pristine baseline |
| `work/Linux-Kernel_MiSTer/` | `MiSTer-v5.15` @ `f0fb626ac` | the fork |
| `work/linux-stable/` | `linux-6.18.y` @ **v6.18.38** (`e46dc0adfe39`) | upstream verification |

---

## 9. P1.9's three [OPUS] escalations — resolved

Owner: **P1.9-escalation** ([OPUS]). Done 2026-07-12 by Michael C. Ferguson, working tree
`work/k-esc/` (pristine 6.18.38). P1.9 ([SONNET]) correctly refused to force these three and
escalated per TASKS.md §0's escalation rule. Outcome: **two carried, one deliberately not.**

Verification for all of it: the full ordered series (**23 patches**, `0001`–`0030`) applies
clean to a pristine 6.18.38 with `git apply --check`, and a full
`make ARCH=arm CROSS_COMPILE=arm-buildroot-linux-gnueabihf- zImage modules` with
`board/mister/de10nano/linux.config` produces **zero warnings and zero errors** (`zImage`
8,623,256 bytes + 42 modules). `input.o`, `mousedev.o`, `hid-nintendo.o` also rebuilt clean at
`W=1`. **No `linux.config` changes were needed** — see §9.4.

### 9.1 `0026-input-mousedev-eviocgrab.patch` — CARRIED. The one that mattered.

**This is not a peripheral quirk. On an unpatched 6.18, a USB mouse works in the file browser
and goes dead the moment you launch a core — for every user.** The mechanism, established by
reading Main_MiSTer rather than assuming:

* Main_MiSTer opens **both** node families for the same physical mouse: `/dev/input/eventN`
  *and* `/dev/input/mouseN` (`input.cpp:5177` — `readdir()` matching `"event*"` **and**
  `"mouse*"`).
* Its **primary** mouse data path is mousedev, not evdev: it writes the ImPS/2 magic sequence
  to the mouse node to enable the scroll wheel (`input.cpp:5237`) and then parses raw 4-byte
  PS/2 packets from it (`input.cpp:6144`). The evdev node is used for identification and for
  everything that is not the pointer.
* Whenever a core is running or the OSD is visible it `EVIOCGRAB`s **every** fd in its pool —
  which includes the evdev node of the very mouse whose mousedev node it is reading
  (`input.cpp:6463` `input_switch()`, `:5528` on hotplug).
* And `input_pass_values()` (`drivers/input/input.c:111`) short-circuits on `dev->grab`: a
  grabbed device delivers to the grabbing handle **and to nobody else**. `input_grab_device()`
  has exactly one caller in the tree — evdev. So the grab starves mousedev, and the pointer
  dies exactly when the user starts using the machine.

**What the patch changes, semantically — three things:**

1. **`include/linux/input.h` + `drivers/input/input.c`.** A new opt-in flag on
   `struct input_handler`, **`->ignore_grab`**. When a grab is in force, `input_pass_values()`
   delivers to the grabbing handle as before, and *then* makes a second pass over the device's
   open handles, delivering the same batch to any handler that set the flag. mousedev sets it;
   nothing else does. Deliberately narrow: exempt handlers see the batch **after** the grabbing
   handle (an evdev grab still wins; a filter that ate an event still hides it); their return
   value is **discarded** (an observer may not shorten the batch the autorepeat pass below
   uses); and with no grab in force **nothing changes at all** — the flag is read only on the
   `dev->grab` path.
   *Deviation from the fork, deliberate:* the original matches `strncmp(handle->name, "mouse", 5)`
   inside the input core. That works only because mousedev happens to name its handles
   `mouse%d`, it couples the core to a naming convention, and it puts a `strncmp()` in the event
   hot path. The flag says the same thing exactly (mousedev is the only handler with handles
   named `mouse*`), says it in the handler that wants the exemption, and costs a byte and a
   predictable branch. Note `struct input_handler` **already has** an unrelated
   `->passive_observer`; hence the different name.
2. **`drivers/input/mousedev.c` — `EVIOCGRAB` on mousedev itself.** mousedev has no
   `->unlocked_ioctl` in mainline, so Main_MiSTer's `EVIOCGRAB` on a mouse node returns
   `-ENOTTY` (it ignores the error) and the node is not actually exclusive. This gives mousedev
   evdev's grab semantics at the mousedev-*client* level: `EVIOCGRAB,1` → this client becomes
   the sole recipient of that mousedev's packets, `-EBUSY` if another client holds it;
   `EVIOCGRAB,0` → release, `-EINVAL` if not the holder; dropped automatically on `close()`, so
   a crashed client cannot wedge the node. The grab is **per-mousedev, not global**: grabbing
   `/dev/input/mouse0` does not silence `/dev/input/mice`, because `mousedev_event()` feeds the
   mixdev through a separate `mousedev_notify_readers()` call. Unknown ioctls return
   **`-ENOTTY`** (the original returned `-EINVAL`, a gratuitous ABI change for anything that
   probes the node).
3. **`drivers/input/mousedev.c` — tap-to-click suppression for DS4/DualSense.** mousedev
   synthesises a left-click when a touch is released within `tap_time`. A DualShock 4 /
   DualSense touchpad is used on MiSTer as a plain pointing device (Main_MiSTer `QUIRK_DS4TOUCH`
   reads it through that same mouse node), where the synthetic click is a misfire: lift a finger,
   get a spurious button-1. Suppressed for the four Sony IDs via a per-device `dis_t2c` flag.
   **Known gap, carried deliberately:** the DualSense **Edge (054c:0df2)** is not in the list
   because it is not in the original either (the Edge postdates it). An Edge used as a
   touchpad-mouse will still tap-to-click. Adding it is a one-line table change, but it is a
   behaviour change relative to stock MiSTer, not a forward-port. → **P3.13.**

**Forward-port work (5.15 → 6.18): the `input.c` hunk does not apply in any form.**
`input_to_handler()` no longer exists — `d469647bafd9` ("Input: simplify event handling logic",
Torokhov, 2024-07-03, v6.11) replaced it with a per-handle `->handle_events()` method bound at
registration by `input_handle_setup_event_handler()`; `071b24b54d2d` (v6.12) fixed where that
binding happens; and `21d8dd0daf4c` ("Input: use guard notation in input core", v6.14) turned
the RCU read section into a `scoped_guard(rcu)` block, so the grab fast path now exits with
`break`, not `rcu_read_unlock()` + return. Both hunks were rewritten against that structure.
`mousedev.c` itself is structurally unchanged since 5.15, so those hunks are near-mechanical —
but the ioctl, the `-ENOTTY` default, and the RCU annotations were rewritten to evdev's idiom
(`rcu_dereference_protected()` with an explicit `lockdep_is_held()`, not a bare `__rcu`
dereference).

**Not verifiable without hardware:** that a real mouse's pointer survives an `EVIOCGRAB` in a
running core, and that DS4/DualSense touchpads no longer emit phantom clicks. → **P3.13.**

### 9.2 `0015-hid-nintendo-nso-famicom.patch` — CARRIED. A re-implementation, not a rebase.

The NSO Famicom pair reports the **Joy-Con (R) product ID (057e:2007)** over Bluetooth, so it
already matches the driver's device table; what it does not report is a *controller type* the
driver knows — the device-info subcommand returns **0x07** (controller I) and **0x08**
(controller II). Every type helper in 6.18's `hid-nintendo.c` returns false for those, and
`joycon_read_info()` (`:2455`) stores the byte without validating it. Net effect on an
unmodified 6.18: **the pads probe successfully, create an input device, and register no buttons
and no axes at all** — a silent, dead gamepad, nothing in `dmesg`. This adds the two types and
wires them into the two dispatch chains.

P1.9 was right that this is not a diff replay. `94f18bb19945` ("HID: nintendo: add support for
nso controllers", Ryan McClelland, 2023-12-04) rewrote the driver's detection scheme, and
**every hunk of the original is obsolete:**

| Original (5.15 idiom) | 6.18 | Disposition of the hunk |
|---|---|---|
| `#define jc_type_is_nescon(ctlr)` — macros ANDing product ID with `ctlr_type` | tiered `static inline bool joycon_{device,type}_is_*()` helpers (`:658-767`); **type helpers test `ctlr_type` alone** — the product ID is deliberately no longer consulted, because NSO pads lie about it | rewritten: added `joycon_type_is_left_famicom()` / `joycon_type_is_right_famicom()` |
| `jc_type_is_joycon` taught to exclude Famicom (else a Famicom, reporting the Joy-Con (R) PID, is misdetected as a Joy-Con) | `joycon_type_is_any_joycon()` is type-based, already false for 0x07/0x08 | **dropped — not needed** |
| `jc_type_is_nso` roll-up gating a shared reporting block | no such helper; each type has its own arm in `joycon_parse_report()` / `joycon_input_create()` | **dropped**, replaced by two new arms |
| `jc_has_rumble` — a **negative** list (all except nescon/snescon/mdcon), had to learn about Famicom or the pads get a rumble device they do not have | `joycon_has_rumble()` / `_has_imu()` / `_has_joysticks()` are **positive** lists | **dropped — a new type is excluded from all three by construction.** This is the load-bearing insight: the negative→positive flip means new NSO types need *no* capability-helper edits at all |
| `famircon_button_inputs[]` — a flat array of `BTN_*` codes; the bit→code mapping open-coded in a long if/else | `struct joycon_ctlr_button_mapping` tables of `{code, bit}` pairs consumed by `joycon_config_buttons()` / `joycon_report_buttons()` | rewritten: authored `famicom_r_button_mappings[]` against the new structure, `JC_BTN_*` bits taken from the shared NSO decode block the original relied on (unchanged since 5.15) |

Controller I reuses `nescon_button_mappings` verbatim (it *is* a NES pad in a different shell).
Controller II gets its own four-entry table — A, B, and the two rail buttons — because it
physically has **no SELECT and no START** (on a real Famicom those live on controller I); in
their place it has a microphone and volume slider, which neither the original nor this port
exposes (the original's subject says so: *"no mic for Famicom R"*). Without an entry, the bit is
simply never reported, rather than a phantom SELECT/START being fabricated.

**Behaviour note, A/B — read this before filing a bug.** The original reports "A" as `BTN_EAST`
and "B" as `BTN_SOUTH` for all NSO controllers. Upstream 6.18 maps NES-family pads
**positionally** instead — "A" → `BTN_SOUTH`, "B" → `BTN_EAST` (`nescon_button_mappings`; cf.
the explicit *"mapped positionally, rather than by label"* comment on `gencon_button_mappings`).
This port follows **upstream's** convention, because Famicom controller I shares
`nescon_button_mappings` and the two pads of one set must not disagree with each other.
Consequence: **A and B are swapped relative to stock MiSTer** — but they are already swapped for
the NSO NES, SNES, N64 and Genesis pads too, which is a pre-existing consequence of taking
upstream's `hid-nintendo` instead of the fork's (§3.3, class C), not something this patch
introduces. Users re-map in the OSD.

**Not verifiable without hardware:** no NSO Famicom pair here. The type bytes, the button set,
and the absence of SELECT/START on controller II are taken from the original commit, whose
author has the hardware. → **P3.13.**

### 9.3 `0021-hid-lg4ff-g923.patch` — **NOT CARRIED.** Deliberate. No `00xx` file.

TASKS.md's standing bar for this one is *"a broken force-feedback wheel driver is worse than an
absent one"*. It is not carried, and the reasoning is below in full, because "we skipped it" is
not an acceptable answer on its own.

**First, two corrections to P1.9's analysis** (which was directionally right and wrong on the
facts):

* **`USB_DEVICE_ID_LOGITECH_G920_WHEEL` is NOT an orphaned ID.** P1.9 grepped only
  `hid-lg4ff.c` and `hid-lg.c`. It is referenced by **`hid-logitech-hidpp.c:4666`**
  (`HIDPP_QUIRK_CLASS_G920`, FF via HID++ feature page `0x8123`). More importantly, 6.18's
  `hid-ids.h:905` **already carries `USB_DEVICE_ID_LOGITECH_G923_XBOX_WHEEL` (0xc26e)** and
  `hid-logitech-hidpp.c:4669` binds it. **The G923 Xbox/PC variant is already fully supported
  upstream, force feedback included** — and `CONFIG_HID_LOGITECH_HIDPP` is `=y` in our build
  (selected by `CONFIG_HID_LOGITECH_DJ`). There is nothing to do for it.
* **The "32-bit rumble/FF fix" fixes a bug that does not exist in 6.18.** The actual diff of
  `43c52e9ef` is `parameters[i].k1 = div_s64((long long)parameters[i].k1 * gain, 0xffff)` — a
  64-bit division in *gain-scaling code that exists only in the out-of-tree rewrite*. 6.18's
  `hid-lg4ff.c` has no `parameters`, no `k1`/`k2`, no gain scaling, no `div_s64`, no `hrtimer`
  (`grep -c` → 0 for all of them): FF scaling is done by `input_ff_memless` in the input core.
  So this is not a fix we are declining to carry — **there is nothing to fix.**

**What the fork's patch actually is.** `8a100f2ed` (+1,425/−540) replaces `hid-lg4ff.c`
wholesale with a vendored copy of **berarma/new-lg4ff**, an out-of-tree hrtimer-driven
memless-FF-slot-scheduler rewrite that **never landed upstream**. 6.18 is still the pre-2019
driver. Carrying the fork's patch means carrying that entire third-party driver as a kernel
patch — for *all* Logitech wheels, replacing well-maintained mainline code.

**Why the "scoped subset" TASKS.md hypothesised does not work.** The suggestion was to lift just
the G923 device ID + wheel table onto 6.18's existing architecture. That subset is genuinely
*correct* — and practically **useless**, which is a finding, not an excuse:

* The G923 **PlayStation/PC** edition boots in PS mode as **046d:c267** and stays there. The
  classic-mode PID **046d:c266** — the one that behaves like a G29 and the only one a wheel
  table entry would help — is **only ever reached by sending the wheel a vendor mode-switch
  command** (report ID `0x30`, payload `f8 09 07 01 01 00 00`; identically documented as the
  `usb_modeswitch -v 046d -p c267 -M 30f8090701010000` recipe the community used before drivers
  did it). A `lg4ff_devices[]` row for c266 alone is dead code on real hardware.
* Making it useful therefore requires the whole multimode/mode-switch path
  (`LG4FF_MODE_G923{,_PS}` bits, `lg4ff_alternate_modes[]`, `lg4ff_multimode_wheels[]`,
  `lg4ff_g923_ident_info` = `{modes, mask 0xff00, result 0x3800, real c266}`,
  `lg4ff_mode_switch_30_g923`, plus `lg4ff_send_cmd_with_id()` / `lg4ff_switch_from_ps_mode()`
  and a hook in `lg4ff_handle_multimode_wheel()`) — ~120 lines, hand-authored against the old
  architecture, which is exactly the work P1.9 flagged.

**And that path has a failure mode strictly worse than doing nothing.** `hid_generic_match()`
(`drivers/hid/hid-generic.c`) returns **false** if any other driver's `id_table` claims the
device. So the moment `c267` is added to `lg_devices[]`, hid-generic will not touch the wheel —
and if `lg4ff_init()` then hard-fails (`"this module does not know how to handle it"`,
`error = -1`, `hid-lg.c` `lg_probe()` → `goto err_stop`), the wheel ends up with **no driver
bound at all: no axes, no buttons, nothing.** In the reference implementation that hard-fail is
gated on an untestable magic `bcdDevice` value (`(bcdDevice & 0xff00) == 0x3800`). Today a G923
PS at least enumerates under hid-generic as a working joystick. **Shipping this could take that
away.** The hardening that removes the hazard (switch unconditionally on PID `c267`; restore the
mutated `report->id`; always return `LG4FF_MMODE_SWITCHED` so a failed switch degrades to
"joystick, no FF") is code that **has never run anywhere, on any wheel** — and the thing it
would be steering is a 2.5 Nm motor in someone's hands. That is not a standard this port is
willing to defend, and TASKS.md says so in as many words.

**So: what does a G923 owner actually get?**

| Variant | On stock MiSTer (5.15 + fork rewrite) | On this kernel (6.18, no `0021`) |
|---|---|---|
| **G923 Xbox/PC** (046d:c26d/**c26e**) | not handled by the fork's `lg4ff` either (HID++ device) | ✅ **fully supported, FF included** — upstream `hid-logitech-hidpp`. No change, no work. |
| **G923 PlayStation/PC** (046d:**c267** → c266) | FF, 900° range, auto-switch out of PS mode | ⚠️ **binds `hid-generic`: steering, pedals and buttons all work as a plain joystick. No force feedback. No range control.** This is the regression, and it is the whole of it. |
| **G29, G27, G25, DFP, DFGT, Momo, DF-EX, Wingman** | the out-of-tree rewrite | ✅ mainline `hid-lg4ff` — FF, range and mode-switching, all of it, from the maintained in-tree driver rather than a vendored fork. Arguably a **reliability gain.** |

**Recipe for whoever has the hardware** (this is 90% of the work, pre-verified — all magic
numbers cross-checked against **two** independent public sources, berarma/new-lg4ff master and
the `usb_modeswitch` recipe above, which agree byte-for-byte):

1. `hid-ids.h`: `USB_DEVICE_ID_LOGITECH_G923_WHEEL 0xc266`, `..._G923_PS_WHEEL 0xc267`
   (`..._G923_XBOX_WHEEL 0xc26e` is **already there**).
2. `hid-lg.c`: `lg_devices[]` rows for c266 + c267 with `LG_FF4`; c266/c267 in `lg_probe()`'s
   "interface 0 only" check; c266 in `lg_input_mapped()`'s wheel list.
3. `hid-lg4ff.c`: `lg4ff_devices[]` row
   `{c266, lg4ff_wheel_effects, 40, 900, lg4ff_set_range_g25}` — *identical to the G29's row;
   the struct is unchanged in 6.18* — plus the multimode/alternate-mode/ident/mode-switch
   entries listed above.
4. **Handle the hard-fail.** Do not let a `c267` device reach the `lg4ff_devices[]` lookup.
5. Test on the wheel. Then send it upstream: mainline has no G923-PS support at all, and this
   would be the first.

### 9.4 Kernel config

**No `board/mister/de10nano/linux.config` changes were required by any of the three.**
`CONFIG_INPUT_MOUSEDEV=y` and `CONFIG_HID_NINTENDO=y` are already present. `linux.config` is a
`savedefconfig`-style file, so symbols that are `select`ed or take their Kconfig default are
correctly absent from it — verified against the generated `.config` that
`CONFIG_HID_LOGITECH_HIDPP=y` (selected by `CONFIG_HID_LOGITECH_DJ`) and `CONFIG_LOGIWHEELS_FF=y`
(`default LOGITECH_FF`), so `hid-logitech-hidpp.o` and `hid-lg4ff.o` **are** built. That matters
for §9.3: the upstream G923-Xbox and G29-family wheel support is compiled in, not merely
available.

---

## 10. Latent bugs in the **stock** MiSTer kernel that this image fixes

These are **not** forward-porting regressions. Every one is present verbatim in the
5.15 fork and therefore in **every MiSTer image shipped to date**. They surfaced only
because forward-porting forces you to read code that has otherwise been copied
forward untouched since 2021.

They are listed here because they are **user-visible behavioural differences between
the stock 5.15 image and ours**, and belong in the release notes (P4.8/P4.9) as much
as in this triage.

| # | Patch | Bug in stock | Effect on a stock MiSTer | Status |
|---|---|---|---|---|
| **B1** | `0014-hid-gamecube-adapter` | **Use-after-free on unplug.** Teardown cancels only `adpt->work_rumble`; the four per-port `ctrl->work_connect` items are never cancelled, then `kfree(adpt)` runs. `work_connect` is embedded in `adpt->ctrls[]` and its handler `container_of()`s back and dereferences `ctrl->adpt->hdev` — and can even `input_register_device()` against the freed adapter. Same defect on the probe error path. | Plugging a controller into the GameCube adapter while the adapter itself is being unplugged can corrupt kernel memory. Silent; may present as an unrelated later crash. | **FIXED** (PR #2 review) |
| **B2** | `0001-fbdev-add-MiSTer_fb` | **`memremap()` returns `NULL` on failure, not an `ERR_PTR`** — the code tests `IS_ERR()`, which is *false* for NULL. A failed mapping therefore falls straight through with `screen_base` unset. | Oops on the first fbcon draw if the framebuffer window ever fails to map. Unreachable with a correct DT node, which is why it has never been seen. | **FIXED** (P1.4) |
| **B3** | `0002-sound-add-MiSTer-audio-spi` | **`class_create()`/`device_create()` return `ERR_PTR`, never `NULL`** — the `== NULL` checks are dead code, so a *failed* `device_create()` was treated as success. | Driver would continue as if `/dev/MrAudio` existed when it did not. | **FIXED** (P1.5) |
| **B4** | `0002-sound-add-MiSTer-audio-spi` | **Bogus diagnostics on SPI failure.** `device_open()` computes the ring `len` even when `spi_read()` failed: `rptr` stays `-1`, `-1 >> 8` is still `-1`, and the `(unsigned int)` cast makes it compare as `0xffffffff`, so the wraparound branch is *always* taken → `len = ptr + buffer_len + 1`, a length larger than the whole ring. | The status string you read to diagnose a broken SPI link is itself wrong — precisely when you need it. No memory-safety issue (`msg[]` is 1024 B; nothing in userland parses it). | **FIXED** (PR #2 review) |
| **B5** | `0019-hidpp-k400-fn-inversion` | The fork's own patch **reuses `SetFeature` at the wrong feature index** (shares a feature-index cache it should not). | Wrong HID++ feature written on a Logitech K400. | **FIXED** (P1.9) |
| **B6** | `0003-cpufreq-cyclone5-de10nano` | **`wait_for_fsm()` passes a *mask* where a *bit number* is expected.** `wait_on_bit(word, bit, mode)` is given `CLKMGR_STAT_BUSY` (`BIT(0)` == 1), so it polls **bit 1**, not bit 0. It also does a plain `test_bit()` on `__iomem` rather than `readl()`, and would sleep on a wait queue no hardware can wake if the bit were ever seen set. | Harmless *today* only because the call returns immediately. | **NOT FIXED — carried verbatim, deliberately.** Correcting it changes PLL transition timing, which cannot be validated without a bench. A forward-port is the wrong place to smuggle that in. **Tracked for P1.13 hardware bring-up.** |

### Why B6 is not fixed

The other five are fixes whose correctness can be established by reading the code.
B6 is not: making `wait_for_fsm()` actually *wait* changes the timing of a live PLL
reprogramming sequence on silicon we have not yet booted. Shipping an untested change
to clock sequencing — inside a patch whose stated job is "carry this forward" — is
exactly the kind of quiet scope creep that makes a forward-port unreviewable. It is
recorded, not hidden, and P1.13 has it on the checklist.

### Provenance note

B1 and B4 were **found by automated static review on PR #2**, not by the porting
agents. Both were confirmed against the 5.15 source before being fixed. This is worth
recording as evidence for the review discipline itself: the ports were already
building warning-free and passing every acceptance check when these were caught.
