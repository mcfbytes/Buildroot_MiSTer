# Verification of stock release `release_20260907` — what moved, and what it means for us

Date: 2026-09-10. Companion to [`stock-release-20250402.md`](stock-release-20250402.md),
which is now the **previous** stock release. Everything below was measured on the shipped
artifacts (both stock archives, both stock `linux.img`s, the upstream build inputs, the
upstream kernel branch) and on **our** latest shipping release, `v2026.09.04-beta`
(`linux.img` sha256 `817f71cb…cb47`, `release_20260904.7z`, `zImage_dtb` 6.18.49).
Raw lists every count below can be re-derived from are in
[`stock-reconciliation-20260907/`](stock-reconciliation-20260907/).

## TL;DR

**No — stock did not "just bump kernel modules and keep the OS the same".** It did the
opposite of what the last five years suggested it ever would:

1. **The kernel moved from 5.15.1 to 6.18.38** (`MiSTer-v6.18` branch, a squash-import of
   pristine `v6.18.38` plus ~60 rebased MiSTer commits). `zImage_dtb` grew 7.38 → 8.56 MB,
   `modules.tar.gz` 25 → 45.5 MB.
2. **The userland did NOT move.** Same Buildroot 2021.02.4 payload: glibc 2.31, BusyBox
   1.33.1, OpenSSL **1.1.1k**, OpenSSH 8.6p1, Python 3.9, wpa_supplicant 2.9, dhcpcd 9.4.0,
   eudev 3.2.9, p7zip 16.02, ProFTPD 1.3.6e, vim 8.2. The rootfs tarball was **rebuilt**
   (2026-07-22 build stamps) but not upgraded: outside Python's `.pyc` cache, 38 files
   changed bytes — 33 ELF binaries (none changed version), the two `perlbug`/`perlthanks`
   stubs (a build date), `/MiSTer.version`, `/etc/shadow` (new salt; the hash still
   verifies as `1` under `openssl passwd -5`), and **one script that really changed:
   `usr/sbin/uartmode`** (§4.2). Two behavioural additions came through `addon.tar`:
   that `uartmode` rewrite and a new 13th init script, `S39usb-coldplug`
   ([`stock-userland-added.txt`](stock-reconciliation-20260907/stock-userland-added.txt)).
   Same `/etc/inittab`, `fstab`, `profile`, `dhcpcd.conf`. Same four SSH host keys as
   every stock image since 2016.
3. **Stock converged on our Wi-Fi/Bluetooth model.** All six out-of-tree Realtek forks are
   gone; in their place mainline `rtw88` (8723DU/8812AU/8814AU/8821CU/8822BU/8822CU),
   `rtw89` (8851BU/8852BU), `mt7921u`/`mt7925u`, `rtl8192du`, `ath6kl_usb`, `carl9170`,
   `btmtk`. 52 → 89 modules, 66 → 91 firmware files on the rootfs (64 → 89 in
   `firmware.tar.gz`; §3.2 explains the bases). Two of the additions are drivers we
   deliberately left off (`ath10k_usb`, `ar5523`) — see §5. One removal has **no**
   replacement in the shipped kernel: the `8821au` fork is gone and `RTW88_8821AU` was
   only enabled the day after the cut (§2.6).
4. **The archive format changed.** `release_20260907.7z` is committed to SD-Installer as
   **two split volumes** (`.7z.001` + `.7z.002`, 117,936,766 bytes joined). The Downloader
   cannot consume a split archive, so `Distribution_MiSTer` grew a joiner that mirrors one
   flat `linux_release_20260907.7z` on its `all_releases` GitHub release — **and then the
   `linux` entry was commented out of the official db.json** (2026-09-10 21:45 +0200). As
   of this writing stock devices are **not being offered** the new image via the Downloader.
5. **Our contract inputs are unaffected in substance**: `uboot.img` and `updateboot` are
   **byte-identical** to the 20250402 ones we pin, so `STOCK_UBOOT_*` / `STOCK_UPDATEBOOT_*`
   stay valid. The only payload file that changed is `MidiLink.INI` (+NES/GBMIDI/X68000
   sections), which we currently ship in its **2020** form.
6. **Our kernel parity is ahead, not behind**: every post-rebase stock fix is either already
   carried (`fb_ops` mmap fix, Mercusys BT ID, `CONFIG_TUN`, `RTW88_8821AU`) or arrived
   upstream **after** the 20260907 kernel was cut (cpufreq port, xpad 8BitDo bypass, exfat
   read-ahead, Classic2USB/RetroZord FF, AIC8800). Three small firmware gaps on our side
   are real and listed in §4.2.
7. **Stock's rebase silently dropped drivers it had in 5.15** (§2.6): the shipped 6.18.38
   kernel has **no `hid-playstation`** (DualShock 4 / DualSense) and **no `hid-logitech` /
   `hid-logitech-hidpp` / `hid-logitech-dj`** (Unifying receivers, K400 Fn fix), because
   both now depend on `LEDS_CLASS_MULTICOLOR`, which stock leaves unset — and the fork's
   own 230 lines of patches to those two drivers are compiled out. Also gone: the
   cpufreq driver (port landed two days after the cut), the iptables `filter` table, and
   **every driver for RTL8811AU/8821AU dongles** (fork removed, in-kernel replacement not
   yet enabled — an Archer T2U Nano that worked on 20250402 has no Wi-Fi on 20260907).
   Our image has all of them.

---

## 1. Artifact identity

| Item | `release_20250402` (pinned) | `release_20260907` (new) |
|---|---|---|
| SD-Installer commit | `b8531c78…` | `76fd6f4ced6350b0ad56a7013b41526f47e3a2fb` ("Release 20260907.", 2026-09-08 04:12 +0800) |
| Archive | single `release_20250402.7z`, 93,727,644 B, MD5 `8dc3acae…` | **split**: `release_20260907.7z.001` (83,886,080 B, MD5 `a939a2b229fc7156f5d697aee4821f65`, sha256 `0fd3708b…4d3e`) + `release_20260907.7z.002` (34,050,686 B, MD5 `06b9770e5247864e3a7ee5001fc38c5a`, sha256 `662a3225…5fa6`) |
| Joined archive (`cat .001 .002`) | n/a | 117,936,766 B, MD5 **`8cd4edca838fdc226390e3fb04f3ca79`**, sha256 `e5bea8413adc249f420e08a48e5cdab9b8c5da04bf52d81dc5261f0f350adf66`; `7z t` passes |
| Official mirror of the joined file | n/a | `https://github.com/MiSTer-devel/Distribution_MiSTer/releases/download/all_releases/linux_release_20260907.7z` — fetched, **byte-identical** to our own join |
| Archive method | `LZMA2:26 LZMA:20 BCJ2`, solid, 2 blocks | identical |
| `linux.img` | 393,216,000 B, 13.6 % free | 393,216,000 B (same 375 MiB), **6.3 % free** (24.6 MB) — the 6.18 module set ate 29 MB |
| ext4 | label `rootfs`, UUID `50ef310c…` | label `rootfs`, **new UUID** `7f78d538-13e3-4c8d-af95-292bf007d4a3`, same feature set |
| `/MiSTer.version` | `250402` | `260907` |
| `zImage_dtb` | 7,380,857 B (zImage 7,360,840 + DTB 20,017) | 8,564,005 B (zImage 8,543,776 + DTB 20,229); still plain concatenation, LZ4 payload, `IKCONFIG` embedded |
| `uboot.img` | sha256 `e2d46cf9…62a64`, 515,141 B | **identical** |
| `updateboot` | sha256 `6ff2d50a…562f2`, 407 B | **identical** |
| Upstream build inputs | `Linux_Image_creator_MiSTer` `13c512d` | `d4e3f51ec7fdd18116562d38bace9ef7dffe0f38` ("Release 20260907.", 2026-09-07) |

`Linux_Image_creator_MiSTer` commits since 20250402, all of which this release folds in:
`d947f5f` XBOX dongle firmwares (2026-04-09) · `24ecf64` JMS583 reboot fix (2026-07-02) ·
`c1ee265` rtl8821c firmware (2026-07-15) · `8aba321` WPA3 on RTL8821CU (2026-07-17, the
commit [`docs/stock-reconciliation.md`](../stock-reconciliation.md) was reconciled against) ·
`d4e3f51` the release itself (new `rootfs.tar.bz2`, `modules.tar.gz`, `firmware.tar.gz`,
`zImage_dtb`; `create_img.sh` **unchanged**).

## 2. The kernel: 5.15.1 → 6.18.38-MiSTer

Banner: `Linux version 6.18.38-MiSTer (saar@Gryphon) (arm-none-linux-gnueabihf-gcc 10.2.1
20201103 …)` — same 2020 Arm toolchain as before. `CONFIG_LOCALVERSION=""`; the `-MiSTer`
suffix comes from the branch, and `/lib/modules/6.18.38-MiSTer` now **matches `uname -r`**
(the mismatch the `CONFIG_TUN` commit complained about is gone).

### 2.1 Branch shape

`MiSTer-devel/Linux-Kernel_MiSTer` HEAD is now branch **`MiSTer-v6.18`**
(`c129b0fac34ad5d613bbec3f59d6036775e41c83`). Its history is a chain of squash-imports
(`v5.13.12 → v5.14 → v5.14.5 → v5.15.1 → v6.18.38`, commit `d9ac12a6`) with **~60 MiSTer
commits rebased on top** (all committed 2026-07-23 by Sorgelig's rebase; seven of them are
authored by contributors — Martin Donlon, Aurora, James McCarthy, Alexey Melnikov, Michael
Huang and Nolan Nicholson (2) — per
[`stock-kernel-commits.txt`](stock-reconciliation-20260907/stock-kernel-commits.txt),
which is the authorship the patch-provenance record must carry). So there is still no
`merge-base` with mainline, but `git diff v6.18.38 MiSTer-v6.18` is now a clean, small
delta: the squash-import tree equals `v6.18.38` except for a deleted
`Documentation/.renames.txt`. Full commit list:
[`stock-kernel-commits.txt`](stock-reconciliation-20260907/stock-kernel-commits.txt).

### 2.2 Which commit the shipped kernel is

The embedded `.config` is **identical** (0 differing lines) to `arch/arm/configs/
MiSTer_defconfig` at **`aec7dc3a`** (2026-08-30, "enable CONFIG_TUN") and differs from the
commit before it. So the 20260907 kernel contains everything up to and including
`aec7dc3a`, and **does not** contain:

| Landed after the cut | Date | Effect on stock 20260907 | Our status (v2026.09.04-beta, 6.18.49) |
|---|---|---|---|
| `33a0521f` enable `RTW88_8821AU` | 09-08 | RTL8811AU/8821AU (e.g. Archer T2U Nano) **have no driver** in this stock release | `rtw88_8821au` built since ADR 0016 ✔ |
| `ea221222` MiSTer_fb explicit `fb_ops` (#83) | 09-08 | **`mmap(/dev/fb0)` returns -ENODEV** on 6.8+ without it — Console Mode / SDL-fbcon users are broken on stock 20260907 | Our `0001` patch already carries `__FB_DEFAULT_IOMEM_OPS_RDWR/MMAP` + `select FB_IOMEM_FOPS` (stock chose `fb_sys_read/write` + `fb_io_mmap`; both restore mmap) ✔ |
| `59bcae8e` cpufreq port with opt-in turbo (#85) | 09-09 | `CONFIG_ARM_SOCFPGA_CPUFREQ` is **absent** from the shipped config — stock 20260907 has **no cpufreq driver** at all (5.15 stock had one) | `ARM_SOCFPGA_CPUFREQ=y` via our `0003` patch ✔ — but stock's new implementation (OCRAM-resident PLL retune, `boost` API, 1000/1200 MHz opt-in) is a different design worth reading before our next cpufreq touch |
| `7c75b1b4` xpad `skip_8bitdo_init` (2dc8:3106) | 09-09 | not present | not carried; experimental A/B switch, default off — no action |
| `9854075c` exfat dir read-ahead | 09-09 | not present | not carried (4 lines in `fs/exfat/dir.c`) — candidate for `0031`'s neighbourhood |
| `41c45f37` Classic2USB (16d0:1460) / RetroZord (1209:595a) in `hid-google-stadiaff` | 09-09 | not present | not carried — 2-line device-table add, trivial to carry |
| `e6f377e7` defconfig: `RTW88_8821A=m`, `FB_SYSMEM_FOPS=y`, `FB_IOMEM_FOPS=y` | 09-09 | not present | equivalent ✔ |
| `c129b0fa` **AIC8800 Wi-Fi/BT vendor driver** (~100 k lines, `drivers/net/wireless/aic8800/`) | 09-11 | not present | not carried; out-of-tree vendor blob-driver of exactly the class ADR 0016 avoids. Flag for a future ADR: "AIC8800 — decline unless mainline grows one" |
| `6332499e` btusb Mercusys 2c4e:0115 | 08-24 | **present** | our `0047` ✔ |
| `aec7dc3a` `CONFIG_TUN=y` | 08-30 | **present** | ours `=y` ✔ |

### 2.3 What the rebase kept, dropped, and re-shaped (vs. our carried series)

`git diff --stat v6.18.38 MiSTer-v6.18` (excluding aic8800) touches 90 files. Mapped
against `board/mister/de10nano/linux-patches/`:

- **Carried by us, also in stock 6.18** (same functionality): MiSTer_fb (`0001`), MiSTer
  audio SPI + snd-dummy model (`0002`), cpufreq (`0003`, stock's landed later), DE10-Nano
  DTS (`0004`), GunCon2/3 (`0010/0011`), Fanatec (`0012`), Vader (`0013`), GameCube
  adapter (`0014`), NSO Famicom (`0015`), Elite 2 paddles (`0016`), xpad deltas (`0017`),
  ControllaBLE quirk (`0018`), K400 Fn (`0019`), mmc LED (`0020`), DS4 wire fix (`0022`),
  wiimote (`0023`), Keyrah Europe-1 (`0024`), usbhid jspoll (`0025`), mousedev/EVIOCGRAB
  (`0026`), mt76x2u Xbox IDs (`0027`), dwc2 unaligned IN (`0028`), leds-gpio (`0029`),
  i2c-designware (`0030`), exfat symlinks (`0031`), joy-con LED / DualSense player-ID /
  mute-`BTN_Z` / NSO Genesis (`0032`–`0042`), CSR clones (`0036`). Stock's "Support for
  init loop device" (`do_mounts.c`) has a counterpart in `linux-patches-upstream/0100`,
  but that directory is **not** applied to this image (README: replaced by the
  initramfs); it exists only for the exported upstream tree.
- **In stock 6.18, deliberately not in ours** (unchanged dispositions from
  `docs/patch-provenance.md`): `vt.h MAX_NR_CONSOLES 63→9`; `spidev` `altspi` compatible
  (we retarget the DTS to `rohm,dh2228fv`); `drivers/block/loop.c` `loop_max_part()` export
  (only needed by stock's in-kernel `do_mounts.c` loop hack); in-tree `xone`
  (`CONFIG_JOYSTICK_XONE=m`, medusalix lineage with Sorgelig's "firmware by PID", "sysfs
  software pairing" and "paddles backport" commits) — we ship `dlundqvist/xone` as a
  package, see [`stock-reconciliation.md` §2b](../stock-reconciliation.md).
- **Stock dropped in its own rebase**: the 5.15-era RTC/i2c/UART DTS tweaks are now
  expressed in the new `socfpga_cyclone5_de10_nano.dts` (215 lines) rather than as driver
  patches; nothing in `drivers/rtc/` is touched any more.

### 2.4 Device tree

Stock 20250402 → 20260907 DTB: the 6.18 `socfpga.dtsi` modernisation only (node renames
`serial0@` → `serial@`, `intc@` → `interrupt-controller@`, `dwmmc0@` → `mmc@`, new
`stmmac-axi-config`, `clk-phase-sd-hs`, `intel,socfpga-qspi` compatible, dropped
`#dma-channels`). Stock 20260907 → ours: 54 changed lines (28 added, 26 removed), all already documented in
[`docs/dts-comparison.md`](../dts-comparison.md) — `terasic,de10-nano` compatible, the
`altspi` → `rohm,dh2228fv` retarget, proper `nxp,`/`st,`/`microchip,` RTC compatibles,
`accelerometer@53` with `INT1`, `bus@ff200000` for the UIO regions, `MiSTer_fb@22000000`.
Diff: [`dts-stock-vs-ours.diff`](stock-reconciliation-20260907/dts-stock-vs-ours.diff).

### 2.5 Kernel config delta, stock 6.18.38 vs ours 6.18.49

3,661 stock symbols vs 3,793 ours; **188 differ**, of which 6 are toolchain version
strings. No `y`↔`m` flips at all.

**On in stock, off in ours (7 symbols)** —
[`kconfig-on-in-stock-off-in-ours.txt`](stock-reconciliation-20260907/kconfig-on-in-stock-off-in-ours.txt):
`AR5523=m`, `ATH10K=m` (+`_CE`, `_LEDS`), `ATH10K_USB=m`, `BT_HCIBFUSB=m`,
`JOYSTICK_XONE=m`. See §5.

**On in ours, off in stock (78 symbols)** —
[`kconfig-on-in-ours-off-in-stock.txt`](stock-reconciliation-20260907/kconfig-on-in-ours-off-in-stock.txt):
the things this project adds on purpose — `ARM_SOCFPGA_CPUFREQ`, `BRCMFMAC(_USB)`, `RSI_91X`/
`RSI_USB`/`BT_HCIRSI`, `ATH9K_HTC`, `RTW88_8821A(U)`, `NTFS3_FS`, `BLK_DEV_INITRD` + every
`RD_*`/`DECOMPRESS_*` (our initramfs), `BLK_DEV_DM`/`MD`, `IP_NF_*` legacy iptables,
`HID_LOGITECH`/`HID_LOGITECH_DJ`/`HID_LOGITECH_HIDPP`/`HID_PLAYSTATION` + their `*_FF`
(**absent** from stock's config entirely — see §2.6), `LEDS_CLASS_MULTICOLOR`,
`HID_STEELSERIES`, `HID_BETOP_FF`/`HID_BIGBEN_FF`/`HID_MEGAWORLD_FF`,
`LOCKUP_DETECTOR`/`SOFTLOCKUP_DETECTOR`/`WQ_WATCHDOG`, `PANIC_ON_OOPS`, `COREDUMP`/
`ELF_CORE`, `STACKPROTECTOR_PER_TASK`, `FAT_DEFAULT_UTF8`, `FB_IOMEM_FOPS`. Stock 6.18
also stays `PREEMPT_NONE`, `HZ=1000`, `VMSPLIT_3G`, `KERNEL_LZ4`, `MODULE_COMPRESS_XZ`,
`CIFS=y`, `NFS_FS=y`, `EXFAT_FS=y`, no NTFS —
[`docs/kernel-config-deltas.md`](../kernel-config-deltas.md) was written against the 5.15
config and should be re-based on `config-stock-20260907` (the `IKCONFIG` extract; regenerate
with `scripts/extract-ikconfig` from any 6.18 tree).

`xpad` went from built-in (`=y` in 5.15) to `=m`; `hid-vader4` is new (`=m`, we build it too).

### 2.6 What stock lost in its own rebase (5.15.1 config → 6.18.38 config)

Symbols that were `y`/`m` in stock's 5.15.1 `IKCONFIG` and are **`n` or absent** in its
6.18.38 one, ignoring pure renames (`CRYPTO_*_ARM`, `UNIX_SCM`, `FB_CMDLINE`,
`CRYPTO_GF128MUL`) and five of the six vendor forks, which were replaced on purpose by an
in-kernel driver that *is* built — the sixth is the last row of this table:

| Lost | Mechanism | User-visible effect on stock 20260907 | Ours |
|---|---|---|---|
| `HID_PLAYSTATION=y`, `PLAYSTATION_FF=y` | 6.18's `config HID_PLAYSTATION` has `depends on LEDS_CLASS_MULTICOLOR`; stock's defconfig (still at HEAD `c129b0fa`) has `# CONFIG_LEDS_CLASS_MULTICOLOR is not set`, so the symbol is **invisible** — no `=y`, no "is not set", nothing to notice in a diff | DualShock 4 and DualSense bind to `hid-generic`: no rumble, no lightbar, no player-ID LED, no mic-mute `BTN_Z`, no touchpad-as-mouse suppression. Every one of the fork's own `hid-playstation.c` patches (186 changed lines, four rebased commits: player-id LED, mute button/LED, player-6 LEDs, DS4 wired fix) is **dead code** | `HID_PLAYSTATION=y`, `PLAYSTATION_FF=y`, `LEDS_CLASS_MULTICOLOR=y`; patches `0022`, `0033`, `0037`, `0042` live |
| `HID_LOGITECH=y`, `HID_LOGITECH_DJ=y`, `HID_LOGITECH_HIDPP=y`, `LOGITECH_FF=y` | same: `config HID_LOGITECH` gained `depends on LEDS_CLASS_MULTICOLOR` | Unifying/Bolt receivers lose per-device enumeration (`hid-logitech-dj`), HID++ features and the fork's own "fix Logitech K400 Plus FN problem" (44 changed lines in `hid-logitech-hidpp.c`) are compiled out; Logitech wheels lose FF | all `=y`; `0019` live; see [`logitech-pairing.md`](../logitech-pairing.md) |
| `ARM_SOCFPGA_CPUFREQ=y` | port to 6.18 landed 2026-09-09, two days after the cut (§2.2) | no cpufreq driver: no `/sys/devices/system/cpu/cpufreq/`, CPU stays at U-Boot's 800 MHz; harmless unless something scripted `cpufreq-set` | `=y` (`0003`) |
| `IP_NF_FILTER=y`, `IP_NF_TARGET_REJECT=y` | dropped in the defconfig regeneration (`NETFILTER`, `IP_NF_IPTABLES` kept) | `iptables -t filter` (the default table) fails with "table does not exist"; stock ships the `iptables` binaries but no init script uses them, so only user scripts notice | `IP_NF_FILTER=y`, `IP_NF_TARGET_REJECT=y`, `IP_NF_MANGLE=m` |
| `EXFAT_DISCARD=y`, `EXFAT_DELAYED_SYNC=y` | options of the 5.15 fork's older exFAT driver; mainline exFAT has neither | none that is measurable from here | n/a (same mainline driver) |
| `RTL8821AU=m` (the `8821au` vendor fork) | removed with the other five forks, but its in-kernel replacement `RTW88_8821AU` was only enabled in `33a0521f` on 2026-09-08, **after** the cut (§2.2); the shipped config has `RTW88_8812AU=m` and no `8821A` symbol | **RTL8811AU/RTL8821AU dongles (e.g. TP-Link Archer T2U Nano, 2357:011e) have no driver at all** on stock 20260907 — a regression from 20250402, where the fork drove them. The other five chips are covered (`rtl8xxxu`, `rtw88_8812au/8821cu/8822bu`) | `rtw88_8821au` built since ADR 0016 ✔ |

The first two rows are the ones that matter: they are exactly the "silent regression"
class `MISTER-KERNEL-PATCH-RECON.md` §0 was written to catch on **our** side, and upstream
has now walked into it on theirs. Verified two ways: the symbols are absent from the
shipped `IKCONFIG`, and no `hid-playstation*.ko`/`hid-logitech*.ko` exists in the shipped
`modules.tar.gz` (they are not modules in stock's config either — they are simply not built).

## 3. Modules and firmware

### 3.1 Modules: 52 → 89

Removed (8): `8188eu 8812au 8821au 8821cu 88x2bu rtl8188fu` (the six vendor forks),
`lib80211` (only the forks needed it), `xone-gip-common` (folded into `xone-gip-bus`).
Added (45): full mainline `rtw88` USB set (`8723du 8812au 8814au 8821cu 8822bu 8822cu`
+ `88xxa`/`core`/`usb`), `rtw89` (`8851bu 8852bu`), `mt7921u`/`mt7925u` (+`mt792x-*`),
`rtl8192du`, `ath10k_usb`, `ath6kl_usb`, `ar5523`, `carl9170`, `btmtk`, `bfusb`, `xpad`,
`hid-vader4`, and three xone GIP accessory modules (`madcatz_glam`, `madcatz_strat`,
`pdp_jaguar`) that the medusalix tree lacked.
Notable: stock still ships `etc/modprobe.d/rtw88-prefer.conf` (`blacklist 8821cu`) even
though there is no `8821cu.ko` left to blacklist.

Against ours (191 module files across 6.18.49 + 7.2.3 RT): 76 of the 89 stock names match
verbatim; the 13 that don't are the 9 hyphen-named `xone-*` (ours are `xone_*`, same
drivers plus more), `ar5523`, `ath10k_core`, `ath10k_usb`, `bfusb` (§5).

### 3.2 Firmware: 66 → 91 files (89 in `firmware.tar.gz`)

**Counting basis, because three numbers circulate for the old release.** Everything in
this section counts regular files on the assembled rootfs, which is `firmware.tar.gz`
plus the two `regulatory.db`/`regulatory.db.p7s` files `rootfs.tar.bz2` itself carries:
20250402 = 64 (tarball) + 2 = **66**; 20260907 = 89 + 2 = **91**. The `69` in
[`docs/stock-reconciliation.md`](../stock-reconciliation.md) is the tarball at creator commit
`8aba321` (2026-07, three xone dongle blobs and two rtl8821c updates after the 20250402
cut, never shipped in an image); the `72` in the 20250402 verification doc counts
directories. The raw lists here are rootfs-basis on both sides.

Added since 20250402 (25):
[`stock-fw-added-since-20250402.txt`](stock-reconciliation-20260907/stock-fw-added-since-20250402.txt)
— `rtw88/{rtw8812a,rtw8821a,rtw8821c,rtw8822b}_fw.bin`, `rtw89/{rtw8851b,rtw8852b,
rtw8852b_fw-1}`, `mediatek/{WIFI_MT7961_patch_mcu_1_2_hdr,WIFI_RAM_CODE_MT7961_1}`,
`mediatek/mt7925/*` (2), `ath10k/QCA9377/hw1.0/{board-2,firmware-6}`,
`ath6k/AR6004/hw1.3/{bdata,fw-3}`, `rtlwifi/{rtl8188fufw,rtl8192dufw,rtl8192fufw,
rtl8710bufw_SMIC,rtl8710bufw_UMC,rtl8723bu_bt}`, `xone_dongle_{02e6,02f9,02fe,091e}`.
Nothing was removed. Stock still has **no** `mediatek/mt7663*`, no `ath3k-1.fw`/`ar3k/`,
no `qca/`, no MT7961 **Bluetooth** patch, and its `brcm/` is still the single
`BCM20702A1-0b05-17cb.hcd` (no `brcmfmac` Wi-Fi blobs). (An earlier draft of this
sentence also listed `rtl_bt/rtl8761b*` and "no `brcm/`" — wrong on both counts: stock has
shipped `rtl_bt/rtl8761bu_{fw,config}.bin` and that one `.hcd` since 20250402, as the
raw list shows and as README l.99 / `bluetooth-parity.md` already say.) So every
"stock has no X" row in [`bluetooth-parity.md` §9](../bluetooth-parity.md) and
[`wifi-parity.md` §6](../wifi-parity.md) still holds, except that stock's *Wi-Fi* driver
coverage is now roughly ours minus Broadcom/Redpine/ath9k_htc and minus the BT halves.

## 4. Parity against our v2026.09.04-beta image

### 4.1 Where stock caught up (no action, but the comparison prose is stale)

- Mainline-first Wi-Fi: stock now makes the same choice ADR 0016 made, for five of the
  six chips (the sixth, RTL8811AU/8821AU, is a regression until stock's next build picks
  up `RTW88_8821AU` — §2.6), and additionally ships `rtw89`/`mt7925u` Wi-Fi 6/6E and
  `rtl8192du`.
- Kernel on an LTS line. (Whether stock will take `6.18.y` stable updates is unknown; it
  cut at `.38` while `.50` was current, and the 5.15 branch never took one.)
- `xpad` as a module, `hid-vader4`, `btmtk`, `CONFIG_TUN`.
- The JMS583 phantom-LUN guard and `rtw88-prefer.conf` (already reconciled in
  `stock-reconciliation.md` §3 from the 8aba321 addon).

### 4.2 Gaps on OUR side (real, small, actionable)

| Stock 20260907 has | We have | Why it matters | Fix |
|---|---|---|---|
| `rtlwifi/rtl8710bufw_SMIC.bin`, `rtl8710bufw_UMC.bin` | driver `rtl8xxxu` with `RTL8XXXU_UNTESTED=y` (8710B support is in `8710b.c`), **no firmware** | README's hardware table claims RTL8710BU is driven by our in-kernel `rtl8xxxu`; without these two blobs `rtl8xxxu_load_firmware()` fails and the dongle is dead | add both to `package/linux-firmware-extra`'s file list |
| `rtlwifi/rtl8192fufw.bin` | same — `8192f.c` requests it, blob absent | RTL8192FU dongles bind and then fail at `request_firmware()` | add |
| `rtlwifi/rtl8723bu_bt.bin` | we ship `rtl8723bu_nic.bin` but not the `_bt` variant | **Correction (2026-09-10):** `8723b.c:489` names the `_bt` file only when `priv->enable_bluetooth` is set, and that flag is declared and read but **never written** anywhere in `rtl8xxxu`, in v6.18.38 and in stock's `MiSTer-v6.18` alike. The branch is unreachable; the driver always loads `rtl8723bu_nic.bin`. Stock's file is a byte-identical duplicate of `rtl8723bs_bt.bin`, which we ship, and nothing can request it | **decline** (documented omission, #158) |
| `ath10k/QCA9377/hw1.0/*` | no `ath10k` | deliberate (wifi-parity §7: upstream calls `ATH10K_USB` "will not fully work") | keep off; note stock now ships it |
| `xone_dongle_02f9.bin`, `_091e.bin` | `02e6`, `02fe` only | ADR 0003: those two PIDs are laptop-internal dongles | keep |
| `RTL8192E/*`, `mediatek/mt7662u*`, `rt2870_sw_ch_offload.bin`, `rtl_bt/rtl8192e{e,u}_fw.bin`, `rtlwifi/rtl8723defw.bin` | absent | all justified in `stock-reconciliation.md` §1 | keep |
| `S39usb-coldplug` (`udevadm trigger --subsystem-match=usb --action=add` + `settle` after `S30dbus`; the new 13th init script) | vendored **byte-identical** (#160) | A second USB replay after the one `S10udevd` already does. Stock gives no rationale. A first draft of this row declined it as a double-fire hazard for our USB `RUN+=` rules; that was wrong — `--subsystem-match=usb` re-emits only for devices whose own subsystem is `usb`, and none of our `RUN+=` rules match that (`scsi_device`, `net`, `block`). It re-runs only udev's idempotent kmod load and costs one empty-queue `settle` | **done** (#160) |
| `usr/sbin/uartmode` rewritten (2375 → 2975 B; `fuser -k` on `/dev/ttyS1` instead of `killall` by name, `169.254.*` filtered from the PPP IP detection, `pppd` fatal exit codes end the respawn loop, new mode 6 respawning `/media/fat/snid`) | the `8aba321` copy | The one non-ELF file whose content changed in this release; an earlier draft of §1 bucketed it with the rebuilt binaries. Main invokes `uartmode <n>` from the OSD, so every stock user with the new Main gets the new modes | re-vendored byte-identical (#160) |
| `MidiLink.INI` with `[NES]`, `[GBMIDI]`, `[X68000]` sections | 2020 file from the 20250402 pin | our `release_YYYYMMDD.7z` and `sdcard.img` `rsync` the **old** file over `/media/fat/linux/MidiLink.INI` on every update — a stock user who updates to us **loses** the three new sections (MidiLink needs them for those cores) | bump the stock pin (§6) or vendor the file |

Full list: [`stock-fw-absent-in-ours.txt`](stock-reconciliation-20260907/stock-fw-absent-in-ours.txt).

### 4.3 Where we remain ahead (unchanged by this release)

Everything in the README's "Stock vs. this image" table that is about the **userland**
still holds and is now *more* stark: stock rebuilt a 2021 Buildroot tree around a 2026
kernel, so it ships OpenSSL 1.1.1k (EOL 2023-09-11) next to Linux 6.18. Also unchanged:
identical SSH host keys, no timezone detection, p7zip 16.02 as `7zr` **and** as the
network-fetched `7za`, 375 MiB image now at 6.3 % free, no NTFS, no Broadcom/Redpine/
ath9k_htc, no BT firmware for MT7961/QCA/ath3k, no RT kernel, no SBOM, no
reproducibility, no published rootfs recipe.

## 5. Stock modules we do not build — decision check

| Module | Upstream's own words | Our disposition |
|---|---|---|
| `ath10k_usb` | Kconfig: "experimental … will not fully work" | Off ([`wifi-parity.md` §7](../wifi-parity.md)). Stock building it means QCA9377 USB sticks now **bind and fail** on stock rather than not bind. No reason to follow. |
| `ar5523` | AR5523, 2004-era 802.11a/b/g | Off — one of the four 2000s-era parts wifi-parity §7 declines. Zero WPA3 relevance. No reason to follow. |
| `bfusb` | AVM BlueFRITZ! USB (2001), needs `bfubase.frm` — **stock does not ship that firmware either**, so the module is inert | Off. Not a gap. |
| `xone` (in-tree, `JOYSTICK_XONE`) | medusalix lineage + Sorgelig's PID-firmware/pairing/paddles commits | We ship `dlundqvist/xone` `f2aa9fe` as a package. **To check**: does dlundqvist carry the "sysfs software pairing" knob stock exposes? If Main_MiSTer starts using it, that is a userspace-coupling item. |

## 6. Downloader / release-pipeline impact

### 6.1 What upstream did about the split archive

`Distribution_MiSTer` `.github/db_operator.py` (`53ccdce`, 2026-09-07 "Introducing
multi-part support in linux releases files"): `get_linux_latest_release()` now accepts
`release_YYYYMMDD.7z(.NNN)?`, sorts and validates the volume sequence, and
`fetch_linux_release()` **concatenates the volumes**, runs `7z t`, uploads the result as
`linux_<name>.7z` to the repo's `all_releases` GitHub release, and publishes **that** mirror
URL in `db.json["linux"]` (with `hash`/`size` of the joined file). The
`Downloader_MiSTer` `LinuxUpdater` itself is **unchanged** (HEAD `5d07713`, 2026-08-07;
`linux_updater.py` last touched 2026-07-20) — still one `url`, one `hash`, one `size`,
one `7za t` + `7za x … files/linux/*`.

**Current state (2026-09-10 20:28 UTC db.json)**: `linux` is **`null`**. The workflow's
`transformer.apply_linux_update()` call is commented out (`113d36e` on 09-07 before the
joiner landed, re-enabled with it, and commented out **again** in `6916c7e` at 21:45 +0200
on 09-10). The mirror asset `linux_release_20260907.7z` **does exist** and is byte-identical
to our own join, so the plumbing works; the entry was pulled deliberately. Whether that is
a hold on 20260907 (e.g. the `/dev/fb0` mmap regression in §2.2, or the 6.3 % free
space) or just a workflow hiccup is not knowable from the repos. Watch
`Distribution_MiSTer` for the next `db_operator.py` change.

Consequence for our multi-db contract ([`downloader-contract.md` §9](../downloader-contract.md)):
while stock's entry is null, **our db is the only `linux` provider** on any device that
has us configured — the "first wins" race is moot. When stock's entry returns it will carry
`version: "260907"`, which is **greater than nothing but compares by inequality only**, so
the ordering rules in §9 apply exactly as written; nothing changes for us.

### 6.2 Our pin (`release.yml` `STOCK_*`, `verify-stock-payload.sh`, `fetch-sdcard-payload.sh`)

Nothing breaks today: the pinned 20250402 URL, MD5, sha256, size still verify (re-checked
this session: `8dc3acae…`, `5d087d9c…`, 93,727,644). `uboot.img`/`updateboot` hashes are
unchanged in 20260907, so the belt-and-braces `STOCK_UBOOT_*`/`STOCK_UPDATEBOOT_*` checks
would pass against either release.

If/when the pin is bumped to 20260907, three things need touching, because every script
assumes **one URL → one file**:

1. `STOCK_RELEASE_URL` becomes two URLs (or the Distribution mirror URL, which is a single
   file but is a *release asset on a branch-free tag*, not a commit-pinned raw blob — a
   different trust story from the one `docs/ci.md#stock-payload-sourcing` documents).
   Recommended: pin the **two raw volume URLs at commit `76fd6f4c…`**, verify each part's
   size/MD5/sha256, `cat` them, then verify the joined file's size/MD5/sha256
   (117,936,766 / `8cd4edca…` / `e5bea841…`) and only then `7z t`. The joined file is what
   the field `7za` sees; `7z` itself also accepts the `.001` directly, but joining first
   keeps `verify-stock`'s "hash before extract" ordering exact.
2. `fetch-sdcard-payload.sh` gains the same two-part fetch, and its cache-hit check
   (`size` + MD5 + sha256 of one file) becomes a check on the joined file.
3. `renovate.md`'s "frozen compatibility pin — never bump" paragraph needs rewording: the
   pin **is** frozen for `uboot.img` (still true, byte-identical) but the auxiliary payload
   (`MidiLink.INI`) does move, so it is a *deliberate, occasional* bump, not a never.

What a bump would change in our shipped `files/linux/`: **only `MidiLink.INI`**
([diff](stock-reconciliation-20260907/MidiLink.INI-20250402-to-20260907.diff)). What it
would change in `sdcard.img`'s payload: `files/MiSTer` (2025-03-05 build → 2026-09-07,
"Release 20260907"), `files/menu.rbf` (2024-10-30 → 2026-09-07), `files/MiSTer_example.ini`
(2024-03-25 → 2026-08-07, now LF not CRLF; adds `hdmi_cec_*`, `vrr_mode` moved, `hdmi_off`,
`spd_quirk`, `xbe2_shift`, `keyboard_as_joystick`, `autofire_*`, `lookahead`,
`video_off_logo`, `sanity_check`, `direct_video=2`; `composite_sync` default flips `0→1`;
`font=` commented out — [diff](stock-reconciliation-20260907/MiSTer_example.ini-20250402-to-20260907.diff)).
`Scripts/update.sh` and the `.exe` are unchanged.

## 7. Documentation that this release makes stale

Ordered by how wrong the reader is left.

| Doc | Claim | Now |
|---|---|---|
| `README.md` §"Stock vs. this image" (rows Kernel, Kernel delta, Wi-Fi chipset coverage, Bluetooth firmware, Image size) and intro ¶ (l.67-68), l.126 "**stock does not move**", l.302, l.405-407 | stock = 5.15.1, six vendor forks, no Wi-Fi 6/6E, 13.6 % free, fixed forever | 6.18.38; mainline `rtw88`/`rtw89`/`mt7925u`; Wi-Fi 6/6E present; 6.3 % free; stock moved. The *userland* rows stay true. "Kernel delta: 110 commits … no per-commit disposition" → now ~60 rebased commits on a clean `v6.18.38` import, diffable (§2.1) |
| `README.md` hardware table l.442 | "No driver at all for RTL8710BU, RTL8814AU, RTL8822CU, RTL8723DU" on stock | stock 20260907 has `rtw88_8814au`/`8822cu`/`8723du` and `rtl8xxxu` **with** the 8710B firmware. Ours lacks the 8710B/8192F firmware (§4.2) — the row's "in-kernel `rtl8xxxu`" claim for RTL8710BU is currently hollow on **our** side |
| `docs/stock-reconciliation.md` | source of truth = creator commit `8aba321`, 69 fw / 52 mods / kernel 5.15.1; §2a "we ship zero out-of-tree modules for the six chips **stock's fork covers**" | re-run against `d4e3f51` (89 fw / 89 mods / 6.18.38); §2a's corroboration paragraph inverts — stock no longer has a fork to blacklist, yet still ships the blacklist file |
| `docs/version-delta.md` | "Linux kernel: stock 5.15.1, never merged a single 5.15.y" | true of 5.15; stock is now 6.18.38 (cut 12 stable releases behind `.50`). Userland rows unchanged and verified again here |
| `docs/kernel-config-deltas.md` | compares against the 5.15 stock config | re-base on the 6.18.38 `IKCONFIG` (§2.5); the two-way symbol lists are in `stock-reconciliation-20260907/` |
| `docs/patch-provenance.md`, `MISTER-KERNEL-PATCH-RECON.md`, `docs/kernel-recon/*` | fork pinned at `MiSTer-v5.15` `f0fb626a…` | the fork now has its own 6.18 rebase — a *second* independent disposition of every 5.15 commit, by upstream. Its keep/drop set should be diffed against ours (§2.3 is the first pass; every carried patch has a stock counterpart, and stock's extra "loop_max_part export" / `vt.h` / `altspi` are our known deliberate drops) |
| `docs/downloader-contract.md` §11.1 | "actual, currently-live `Distribution_MiSTer` `linux` entry" = the 20250402 raw URL | entry is null; when it returns it will be the Distribution `all_releases` mirror URL with the joined file's hash (§6.1). §4 "no split volumes" advice for **our** archive stays correct |
| `docs/downloader-contract.md` §4, `docs/ci.md#stock-payload-sourcing`, `docs/renovate.md` (l.199-210), `docs/reference-materials.md`, `PLAN.md` §10 | single-file stock archive at a raw commit URL | the newest stock archive is split (§1, §6.2) |
| `docs/verification/sdcard-payload.md` | payload provenance = 20250402 `MiSTer`/`menu.rbf`/`MiSTer_example.ini` | unchanged until the pin bumps; add the "these three are 18 months stale on a fresh card" note, or bump |
| `docs/wifi-parity.md` §6-§7, `docs/bluetooth-parity.md` §9, ADR 0016 | "stock has no rtw88 module", "stock's kernel branch (`MiSTer-v5.15`)…" | stock now ships the full rtw88/rtw89 USB set; the BT-firmware gaps remain. ADR 0016 gains a "stock adopted the same policy in 20260907" postscript |
| `docs/verification/stock-release-20250402.md` | "(the stock side, fixed forever)" | historical; add a header pointing here |
| `docs/midi-mt32-parity.md` / `package/midilink` | `MidiLink.INI` is stock's | stock's file gained three core sections we do not ship (§4.2) |
| `.github/ISSUE_TEMPLATE/bug_report.yml` l.114 | "Was working fine on stock release_20250402" | mention 20260907 as the current stock |

## 8. Follow-ups, smallest first

1. **Firmware** — **done, PR #158.** `rtlwifi/rtl8710bufw_SMIC.bin`, `rtl8710bufw_UMC.bin`
   and `rtl8192fufw.bin` added to `package/linux-firmware-extra` (all three are `File:`
   entries in the pinned linux-firmware WHENCE). `rtl8723bu_bt.bin` is **declined**: its
   only consumer sits behind a flag the driver never sets (§4.2 row), and upstream never
   shipped the name anyway. `docs/stock-inventory/firmware.md` regenerated from this
   image (91 files); `docs/firmware-parity.md`'s CI-parsed *Missing* block is now 14 →
   **77 of 91 present**.
2. **Kernel** (handled in the separate kernel-reconciliation session): carry `41c45f37`
   (Classic2USB/RetroZord FF, 2 lines) and `9854075c` (exfat read-ahead, 4 lines) as
   `0048`/`0049`; read `59bcae8e` before the next cpufreq change.
3. **Stock pin bump to 20260907** — **done, PR #159.** `STOCK_RELEASE_URL` is now a
   two-URL list that `fetch-stock` and `fetch-sdcard-payload.sh` join; the MD5/SHA-256/size
   pins are the joined file's. Run end to end against the new pins: join, hashes, `7z t`,
   `uboot.img`/`updateboot` identity, the new `MidiLink.INI`, and the sdcard payload
   (now carrying the 20260907 `MiSTer`/`menu.rbf`/`MiSTer_example.ini`). The qemu-arm `7za`
   round-trip against **our** archive still runs in `release.yml` as before.
4. **Docs** per §7 — userland side **done** across #158 (firmware), #159 (pin: `ci.md`,
   `renovate.md`, `downloader-contract.md` §11.1, `reference-materials.md`, README's
   "stock does not move", the bug template) and #160 (the `uartmode` rewrite and
   `S39usb-coldplug` vendored byte-identical, with the dispositions in `init-parity.md`
   and `stock-reconciliation.md` §3d; README image-size row). The
   kernel-side rows of §7 (`version-delta.md` kernel line, `kernel-config-deltas.md`,
   `patch-provenance.md`, the kernel-recon set, `wifi-parity.md` §6-7's driver claims,
   ADR 0016's postscript, `stock-reconciliation.md` §2) are the kernel session's.
5. **Watch**: `Distribution_MiSTer` `db_operator.py` for the `linux` entry's return, and
   `Linux-Kernel_MiSTer` for whether `MiSTer-v6.18` ever takes a `6.18.y` bump (it would be
   the first stable update stock has ever taken).
6. **Hardware check** (cannot be done here): on a stock 20260907 card, `/dev/fb0` mmap
   (§2.2), a DualSense, a Logitech Unifying receiver and an RTL8811AU/8821AU dongle
   (§2.6) — four regressions we can expect support threads about, and for all four the
   answer is "this image has never had the problem" (`0001`, `HID_PLAYSTATION`/
   `HID_LOGITECH` with `LEDS_CLASS_MULTICOLOR=y`, `rtw88_8821au`).
7. **Upstream courtesy**: the §2.6 finding is a one-line fix in `MiSTer_defconfig`
   (`CONFIG_LEDS_CLASS_MULTICOLOR=y`, then re-`olddefconfig`). Worth an issue on
   `Linux-Kernel_MiSTer` with this document as evidence; it also protects the users who
   will never run our image.
