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
  guard was always taken. **Drop the C patch; keep the DTS property.**
* `include/uapi/linux/vt.h` `MAX_NR_CONSOLES 63 → 9` (`b2a04cbfd`) is a UAPI header edit for a
  few KB of memory. **Recommend dropping** (see §6, F-3).

---

## 3. Summary table

Legend — **Disposition:** `carry` = becomes a `linux-patches/` file · `drop` = 6.18 supersedes ·
`re-source` = Buildroot `kernel-module` package from upstream project · `delete` = removed by
design · `config` = feeds P1.3, not a patch.

### 3.1 Class A — MiSTer core (carry)

| Commit(s) | Subject | Files | Origin | Upstream in 6.18 | Disposition | Target |
|---|---|---|---|---|---|---|
| `d1002ecd4` | Implement MiSTer frame buffer device | `drivers/video/fbdev/MiSTer_fb.c` (+Kconfig/Makefile/DTS) | Sorgelig | no (MiSTer-specific) | carry | `0001-fbdev-add-MiSTer_fb-driver.patch` |
| `333d49b95` | Implement MiSTer audio driver | `sound/drivers/MiSTer-audio-spi.c`, **`sound/drivers/dummy.c`** (+Kconfig/Makefile/DTS) | Sorgelig | no | carry | `0002-sound-add-MiSTer-audio-spi.patch` |
| `3d72b9db7`, `e6df8e30e` | Add cpufreq/overclock driver; improve clock transition | `drivers/cpufreq/socfpga-cpufreq.c`, `Kconfig.arm`, `Makefile` | **Michael Huang** (PRs #34/#35) | no (`grep socfpga drivers/cpufreq/` → none) | carry | `0003-cpufreq-cyclone5-overclock.patch` |
| `aa8afe109`, `e40563ae1`, `2548c2978`, `6827e7644`, `6c2d53934`, `246984fce`, `1337de1fd`, `c4d12c768`, `7d2df2d2d`, `c5066763c`, `071d9092e`, `f52690120`, `077c2c317` | de10-nano DTS + RTCs + i2c-gpio + uart1 + i2c2 + bridges + usb1 | `arch/arm/boot/dts/socfpga_cyclone5_de10_nano.dts`, `socfpga.dtsi`, `dts/Makefile` | Sorgelig; `6827e7644` **antoniovillena** | mainline has a *minimal* de10nano DTS (`144616a80889`, 2025-02-03, v6.14) — insufficient (§4.1a) | carry | `0004-dts-de10nano-MiSTer.patch` |
| `246984fce` (spidev hunk) | Enable SPI on LTC | `drivers/spi/spidev.c` — `{ .compatible = "altspi" }` | Sorgelig | no | carry **or** retarget DTS (N2) | `0005-spidev-accept-altspi-compatible.patch` |
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
| `484f68172` | **NSO Famicom controllers** | `drivers/hid/hid-nintendo.c` | **Aurora** (PR #62) | **`0015-hid-nintendo-nso-famicom.patch`** *(new)* |
| `c784a6856` | hid-microsoft: Xbox Elite 2 paddles | `drivers/hid/hid-microsoft.c` | Sorgelig | **`0016-hid-microsoft-elite2-paddles.patch`** *(new)* |
| `af27afc4c`, `f3c75eb02`, `a2242dd85`, `c035c21c0` | xpad deltas | `drivers/input/joystick/xpad.c` | **zakk4223** (PR #63), **eniva**, Sorgelig | **`0017-xpad-mister-deltas.patch`** *(new)* |
| `5bdbf2f7e` | ControllaBLE quirk (1209:FACA) | `drivers/hid/hid-quirks.c`, `hid-pl.c` | Sorgelig | `0018-hid-controllable-quirk.patch` |
| `fc8f3c2c6`, `b745ce6d9` | Logitech K400r / K400 Plus: disable Fn swap | `drivers/hid/hid-logitech-hidpp.c` | Sorgelig; **HGD73** (PR #15) | `0019-hidpp-k400-fn-inversion.patch` |
| `8a100f2ed`, `43c52e9ef` | Logitech G923 wheels + 32-bit rumble/FF fix | `drivers/hid/hid-lg.c`, `hid-lg4ff.c`, `hid-ids.h` | **atrac17** (PR #32), **zakk4223** (PR #54) | `0021-hid-lg4ff-g923.patch` |
| `1412bd707`, `5c410e935` | hid-sony: div-by-0; 3rd-party DS4 wired connect | `drivers/hid/hid-sony.c` | Sorgelig | `0022-hid-sony-fixes.patch` |
| `0d7778d1f`, `47dc53a22`, `15968bc26` | wiimote: `uniq`, button codes, analog ranges | `drivers/hid/hid-wiimote-{core,modules}.c` | Sorgelig | `0023-hid-wiimote-fixes.patch` |
| `70e391b81` | Map HID Europe-1 (0x32) → `KEY_F24` (**Keyrah**) | `drivers/hid/hid-input.c` (1 line) | Sorgelig | `0024-hid-input-keyrah-europe1.patch` |
| `f0982bf2c` | usbhid: apply `jspoll` to gamepads too | `drivers/hid/usbhid/hid-core.c` | Sorgelig | `0025-usbhid-jspoll-gamepad.patch` |
| `2ac0aa1e8`, `52a56ae3d` | **core input:** mouseX/mice under `EVIOCGRAB`; disable touch-to-click on DS4/DualSense | `drivers/input/input.c`, `drivers/input/mousedev.c` | Sorgelig | **`0026-input-mousedev-eviocgrab.patch`** *(new — see §6 D-14)* |
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
| F-2 | `b62efee23` | hps_led: brightness-change notification | `drivers/leds/leds-gpio.c` (+6) | **no** | **carry** → `0029-leds-gpio-brightness-hw-changed.patch`. ⚠ consumer not identified in Main_MiSTer — confirm at P0.5 whether anything reads `/sys/class/leds/hps_led0/brightness_hw_changed`; if nothing does, drop. |
| F-3 | `b2a04cbfd` | vt: reduce 63 → 9 ttys | `include/uapi/linux/vt.h` (`MAX_NR_CONSOLES`) | **no** (it is a local reduction) | **recommend drop** — a UAPI header edit for a few KB. Zero functional need; keeps our patch set smaller. Decide at P0.9. |
| F-4 | `7436e2d6e` | mt7601u "possible fix?" — comments out DPD calibration | `drivers/net/wireless/mediatek/mt7601u/phy.c` | **no** — 6.18 `mt7601u/phy.c:592` still calls `mt76 01u_mcu_calibrate(dev, MCU_CAL_DPD, …)` | **carry with prejudice.** Author **bbond007**; commit message is literally *"mt7601u possible fix?"*; the diff comments out a calibration call and leaves stray `/* remove this for testing--> spark2k06 */` markers. Unprincipled. **Recommend: drop, and re-add only if a real mt7601u regression appears at P3.13.** |
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

**Forward-port hazards on 6.18 (specific):**

1. `static struct fb_ops ops` → **must become `static const struct fb_ops ops`**:
   `struct fb_info.fbops` is `const struct fb_ops *` (`6.18 include/linux/fb.h:497`).
2. **`info->flags = FBINFO_FLAG_DEFAULT;` (`MiSTer_fb.c:239`) will not compile** —
   `FBINFO_FLAG_DEFAULT` / `FBINFO_DEFAULT` were **removed** in the 6.x fbdev flag cleanup
   (absent from `6.18 include/linux/fb.h`). Delete the assignment.
3. `FBINFO_MISC_USEREVENT` + `fb_notifier_call_chain(FB_EVENT_MODE_CHANGE_ALL, …)` also gone —
   **already inside a `/* … */` block** in the 5.15 source (`MiSTer_fb.c:328-335`), so no work.
   `fbcon_update_vcs(info, true)` (the live call) **still exists**: `6.18
   include/linux/fbcon.h:28`. ✓
4. **Kconfig:** `select FB_SYS_FILLRECT / FB_SYS_COPYAREA / FB_SYS_IMAGEBLIT` still resolve in
   6.18 (`drivers/video/fbdev/core/Kconfig:61,…`), and `sys_fillrect`/`sys_copyarea`/
   `sys_imageblit` are still declared (`6.18 include/linux/fb.h:578-580`). Prefer the modern
   `select FB_SYSMEM_HELPERS` (6.18 `Kconfig:164`), which pulls all three.
5. ⚠ **Mixed sysmem/iomem idiom.** The driver `memremap()`s MMIO but uses the **sys_\*
   (system-memory)** accel helpers, and supplies no `.fb_read`/`.fb_write`/`.fb_mmap`. In 6.18
   these fops are no longer implicit — drivers declare them via `FB_DEFAULT_SYSMEM_OPS` /
   `__FB_DEFAULT_SYSMEM_OPS_RDWR` (or the `IOMEM` variants). **P1.4 must decide sysmem vs iomem
   fops explicitly and verify `mmap()` of `/dev/fb0` still works** — Main_MiSTer maps the
   framebuffer. This is the single most likely place P1.4 breaks.
6. No aperture/`remove_conflicting_framebuffers` concern (platform device, no PCI VGA conflict).

---

### `0002-sound-add-MiSTer-audio-spi.patch` — **P1.5** (class A)

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

**Forward-port hazards on 6.18 (specific):**

1. **`class_create(THIS_MODULE, DRIVER_NAME "_sys")` will not compile.** 6.18's signature is
   `struct class *class_create(const char *name)` — one argument
   (`6.18 include/linux/device/class.h:226`; the `owner` arg was dropped in 6.4). Must become
   `class_create(DRIVER_NAME "_sys")`.
2. snd-dummy's structure is intact in 6.18 — `struct dummy_model` (`sound/drivers/dummy.c:109`),
   `dummy_models[]`, `static bool fake_buffer = 1` (`:61`), `const struct dummy_model *model`
   (`:128`). The three MiSTer hunks should rebase with minimal churn. ✓
3. `dma_alloc_coherent`/`dma_free_coherent` unchanged. CMA sizing must be preserved.
4. Standard ALSA PCM API churn is **not** a factor here — MiSTer-audio-spi is *not* an ALSA
   driver at all (it's a chrdev). The only ALSA surface is snd-dummy, which upstream maintains.
   This substantially **de-risks** P1.5 versus the plan's assumption.

---

### `0003-cpufreq-cyclone5-overclock.patch` — **P1.6** (class A)

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

**ABI surface:** the **standard cpufreq sysfs** —
`/sys/devices/system/cpu/cpu*/cpufreq/{scaling_governor,scaling_max_freq,scaling_available_frequencies,…}`
plus **`/sys/devices/system/cpu/cpufreq/boost`** (the OC switch). Main_MiSTer does **not** touch
cpufreq (verified — no `cpufreq`/`scaling_` references); the consumers are community overclock
scripts on `/media/fat`. Stock governor: `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` with
performance/powersave/userspace/ondemand/conservative/schedutil all built in (P1.3 must match).

**Forward-port hazards on 6.18: low — better than the plan assumes.**
`struct cpufreq_driver` in 6.18 **still has** `struct freq_attr **attr` (`include/linux/cpufreq.h:413`),
`bool boost_enabled` (`:416`) and `int (*set_boost)(...)` (`:417`) — the fields this driver uses.
`.verify`/`.target_index`/`.get`/`.init`/`.exit` signatures are unchanged;
`cpufreq_frequency_table_verify(struct cpufreq_policy_data *)` is unchanged. Expect near-clean
rebase. Watch: `CLK_INTEL_SOCFPGA32` symbol name, and `wait_on_bit()`'s `void *` cast.

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

---

### `0010`–`0030` — classes D & F

Per-patch detail is in the §3.4 and §3.7 tables (origin, files, upstream evidence, target
filename). Owner: **P1.9** ([SONNET], escalate to [OPUS] per the notes below).

**Escalate to [OPUS]:**

* **`0026-input-mousedev-eviocgrab.patch`** (`2ac0aa1e8`, `52a56ae3d`) — **not a HID quirk; a
  core input-subsystem patch.** It rewrites `mousedev_notify_readers()` into a per-client
  `mousedev_notify_reader()` and adds a hook in `drivers/input/input.c`'s value-dispatch loop so
  that handles whose name starts with `"mouse"` still receive events **while another client holds
  `EVIOCGRAB`**. **This is load-bearing:** Main_MiSTer both grabs evdev devices exclusively
  (`Main_MiSTer/input.cpp:4828, 5528, 5631` → `ioctl(fd, EVIOCGRAB, …)`) **and** reads mousedev
  (`input.cpp:5240-5241` writes the IMPS/2 `0xf3 200 0xf3 100 0xf3 80` sequence to a mouse fd).
  Without the patch, grabbing starves `/dev/input/mice` and the menu mouse dies.
  `input_pass_values()`/`input_to_handler()` internals have churned since 5.15 — budget real
  time. **PLAN.md §4.1's class D ("HID") does not describe this; it should.**
* **`0017-xpad-mister-deltas.patch`** (`af27afc4c` + 3) — `af27afc4c` is a **wholesale sync to a
  much newer upstream xpad**, so most of its content is already in 6.18. Do **not** port the
  commit; port the **MiSTer-specific deltas on top of 6.18's xpad**:
  1. `cpoll` module param (XInput polling interval) — `f3c75eb02`;
  2. **GIP-capable controllers commented out of `xpad_device[]`** (`045e:02d1/02dd/02e3/02ea/0b00/0b12`)
     so **xone** claims them instead — `a2242dd85`. *This is a deliberate divergence from
     upstream and must be preserved or xpad and xone will fight over the same devices.*
  3. `MAP_VADER4`/`MAP_VADER5` + Flydigi Vader 3/4/5 Pro extra buttons — `c035c21c0`;
  4. Qanba Obsidian XInput mode — `f3c75eb02`.
  Note 6.18 already has `MAP_PADDLES`, `MAP_SHARE_BUTTON`, `MAP_PROFILE_BUTTON`, the paddle
  report path via `BTN_GRIPL/R/L2/R2` (`xpad.c:494-498, 1088-1098`), Flydigi **Apex 5**, and
  `XPAD_XBOX360_VENDOR(0x2c22)` for Qanba — so the delta is genuinely small.
* **`0028-dwc2-fix-unaligned-in-split.patch`** (`d7adb20b4`, **Martin Donlon**) — a real dwc2
  bug fix, not a quirk. Moves the `align_buf` bounce-buffer `memcpy` out of
  `dwc2_xfercomp_isoc_split_in()` and gates it on `chan->align_buf && chan->ep_is_in &&
  qtd->complete_split`, using `dwc2_get_actual_xfer_length()` instead of `len`. **6.18 still has
  the old code** (`hcd_intr.c:922-928`). **Recommend submitting upstream** — it benefits every
  dwc2 user, and upstreaming it removes a carried patch permanently.

---

## 6. Mapping onto PLAN §6's `linux-patches/` filenames

§6 lists 10 files. The verified triage needs **more**, because §6's class D/F list is
incomplete. Proposed final set (P1.9 confirms):

| §6 planned | Status |
|---|---|
| `0001-fbdev-add-MiSTer_fb-driver.patch` | ✅ as planned |
| `0002-sound-add-MiSTer-audio-spi.patch` | ✅ **but must also carry the `dummy.c` hunks** (N4) |
| `0003-cpufreq-cyclone5-overclock.patch` | ✅ as planned |
| `0004-dts-de10nano-MiSTer.patch` | ✅ as planned (+ decide the `socfpga.dtsi` i2c1 hunk) |
| `0005-spidev-accept-altspi-compatible.patch` | ⚠ **prefer to eliminate** by retargeting the DTS compatible (N2) |
| `0010-hid-guncon2.patch` | ✅ |
| `0011-hid-guncon3.patch` | ✅ |
| `0012-hid-fanatec.patch` | ✅ |
| `0013-hid-flydigi-vader.patch` | ✅ (the `hid-vader4.c` BT driver; the *xpad* Vader work is `0017`) |
| `0020-usb-storage-blacklist-realtek-cdrom.patch` | ❌ **DELETE — upstream** (`a3dc32c635ba`) |
| **new** `0014-hid-gamecube-adapter.patch` | Nintendo WUP-028 (057e:0337) |
| **new** `0015-hid-nintendo-nso-famicom.patch` | NSO Famicom (`FAMIL`/`FAMIR` ctlr types) |
| **new** `0016-hid-microsoft-elite2-paddles.patch` | Elite 2 paddles over BT |
| **new** `0017-xpad-mister-deltas.patch` | cpoll, GIP exclusions, Vader 3/4/5, Qanba |
| **new** `0018-hid-controllable-quirk.patch` | 1209:FACA |
| **new** `0019-hidpp-k400-fn-inversion.patch` | K400r / K400 Plus |
| **new** `0020-mmc-no-led-on-send-status.patch` | *(number freed by the deletion above)* |
| **new** `0021-hid-lg4ff-g923.patch` | G923 wheels + 32-bit FF fix |
| **new** `0022-hid-sony-fixes.patch` | div-by-0, 3rd-party DS4 wired |
| **new** `0023-hid-wiimote-fixes.patch` | uniq, buttons, analog |
| **new** `0024-hid-input-keyrah-europe1.patch` | Europe-1 → `KEY_F24` |
| **new** `0025-usbhid-jspoll-gamepad.patch` | jspoll for gamepads |
| **new** `0026-input-mousedev-eviocgrab.patch` | **[OPUS]** core input |
| **new** `0027-mt76x2u-release-xbox-adapter-ids.patch` | let xone bind 045e:02e6/02fe |
| **new** `0028-dwc2-fix-unaligned-in-split.patch` | **[OPUS]**; submit upstream |
| **new** `0029-leds-gpio-brightness-hw-changed.patch` | pending consumer check (F-2) |
| **new** `0030-i2c-designware-quiet-timeout.patch` | cosmetic |
| *(pending N1 decision)* `00xx-exfat-*` | **class G — see N1** |

**Dropped relative to §6/§4.1:** the `loop=` patch (class B, by design), 22 class-C commits,
the `dwc2/core.c` no-op (N5), `vt.h` (F-3, recommended), and `mt7601u` (F-4, recommended).

---

## 7. Open questions / risks for the P0.9 review gate

| # | Question | Severity | Owner |
|---|---|---|---|
| **Q1** | **exfat (N1): (a) accept losing symlinks on `/media/fat`, (b) forward-port the out-of-tree driver, or (c) add `ATTR_SYSTEM` symlink support to mainline exfat?** Main_MiSTer actively resolves symlinks (`file_io.cpp:1592`). Nothing in the plan budgets this. | **HIGH** | P0.9 → P1.3/P1.10 |
| **Q2** | Does anything in the community actually *use* symlinks on `/media/fat`? If a survey says no, Q1 collapses to (a) + a release note. **Needs a human/community answer — I cannot determine it from the repos.** | **HIGH** | human |
| **Q3** | `/media/fat` mount options (N3): replicate `sync,dirsync`, or deliberately switch to async and document the power-off-corruption trade-off? | MEDIUM | P1.10 |
| **Q4** | FAT32 `iocharset`: stock is effectively `utf8`; mainline vfat defaults to `iso8859-1`. Set `-o iocharset=utf8` (and/or `CONFIG_FAT_DEFAULT_UTF8=y`)? | MEDIUM | P1.3/P1.10 |
| **Q5** | btusb CSR clones (`b02a4a011`): 6.18's detector is a superset but does **not** cover `lmp_subver == 0x2512`. Do we drop and risk one fake-dongle model, or carry a 1-line addition? | MEDIUM | P3.13 (HW) |
| **Q6** | `leds-gpio` `brightness_hw_changed` (F-2): no consumer found in Main_MiSTer. Confirm at P0.5, then drop if truly unused. | LOW | P0.5 |
| **Q7** | `mt7601u` DPD hack (F-4) and `vt.h` (F-3): recommend dropping both. Confirm. | LOW | P0.9 |
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
