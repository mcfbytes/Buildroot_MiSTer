# Reconciliation — one row per fork commit

Generated 2026-07-15 15:13 UTC by `reduce.py` from 123 records (108 MiSTer-v5.15 + 15 old-branch residue). Tier-2 verified: 123/123.

## How to read this table

Each row is one commit from the MiSTer kernel fork (`MiSTer-devel/Linux-Kernel_MiSTer`),
reconciled against our vanilla-6.18.38-based build. The full evidence for a row lives in
`records/<full-sha>.json`.

- **SHA** — the fork commit (short). **Branch** — where the commit lives: `v5.15` is the
  branch stock MiSTer actually shipped; `v5.14`/`v5.13.12` are older branches whose
  unique commits never reached stock (analyzed so nothing is lost *between* MiSTer's own
  branches either).
- **Disposition** — what happened to the commit's functionality in this build:
  - `carried` — kept, as the patch named in the next column (applied to the pristine
    kernel.org tree at build time);
  - `dropped-upstream` — the same functionality is already in mainline 6.18 (the record
    cites the upstream commit and quotes the matching code);
  - `dropped-deliberate` — intentionally not carried, with the replacement named (a
    maintained out-of-tree package, a mainline driver, or a documented decision);
  - `dropped-obsolete` — the code it changed no longer exists in any form we ship
    (e.g. fixes to a vendored driver that was replaced wholesale).
- **Carried patch** — the `board/mister/de10nano/linux-patches/00xx-*.patch` file that
  carries it (`—` when not carried).
- **Impact today** — **read this column first.** It is what a user of *this build*
  actually experiences: `none (carried)` — the feature is present via our patch;
  `none (in mainline)` — 6.18 already has it; `none (replaced)` — a named package/driver
  provides it. Only rows marked **limitation** describe a real present-day difference,
  and each one is listed explicitly below the legend.
- **Drop-risk** — a *hypothetical* used during triage: the worst effect **if this
  functionality had been left out with no replacement**, and whether that absence would
  be `loud` (build/boot error) or `silent` (quietly missing — the class this audit
  hunts). **A row reading `feature-loss/silent` next to an Impact-today of `none` is not
  a problem in the build** — it records why the row demanded scrutiny during the audit,
  and that scrutiny is complete. Severity ladder: `boot-critical` > `feature-loss` >
  `cosmetic` > `none`.
- **Coupled** — `Y` when MiSTer userspace (Main_MiSTer) directly depends on the kernel
  interface involved (input event codes, sysfs nodes, /dev nodes, ioctls); these must
  never be dropped silently. The record cites the exact `file:line`.
- **Doc✓** — whether the original `docs/patch-provenance.md` triage agreed with this
  independently re-derived result (`N` rows are the errors this exercise found; all are
  corrected in that doc's §11).
- **T2** — `✓` means the record survived a second, independent verification pass
  (a stronger reviewer re-derived every claim from the actual source trees; 123/123 rows
  have this).
- **Why / replacement** — the short answer to "where did it go?": the mainline commit that
  provides it (`dropped-upstream`), or what replaces it (`→ package/...`, a mainline driver,
  an ADR/decision). `see record` means the reason is narrative — read the JSON record.

### Why rows are `dropped-deliberate`

Nothing was dropped by accident: every `dropped-deliberate` record names its replacement or
the decision behind it. The recurring patterns, so the table reads at a glance:

1. **Vendored driver trees → maintained sources.** The fork carried multi-megabyte copies of
   out-of-tree drivers (realtek wifi families, xone). We ship the same functionality from
   commit-pinned, hash-verified Buildroot packages or — preferred when it works on the real
   hardware — the mainline in-kernel drivers (`rtw88`, `rtl8xxxu`). Fixes the fork made to
   its vendored copies are verified present in whichever source we actually build.
2. **Fork mechanisms replaced by this build's architecture.** The `loop=` boot parameter
   hack is replaced by a real initramfs; the fork's `MiSTer_defconfig` commits are absorbed
   into `board/mister/de10nano/linux.config` (verified symbol-by-symbol against the resolved
   build config).
3. **Shared-file hygiene.** Hunks in files shared by every socfpga board (`socfpga.dtsi`)
   were dropped when provably inert on this board, keeping patches off shared files.
4. **Rejected on the merits.** Experimental or debug leftovers (the `mt7601u` calibration
   disable marked "possible fix?", the vt 63→9 console tweak, deleted gdb helper scripts)
   — each with the reasoning recorded.
5. **Risk-based.** The out-of-tree new-lg4ff rewrite was not carried: mainline `hid-lg4ff`
   covers every wheel Main_MiSTer actually drives, and the rewrite carries an untestable
   hard-fail hazard. Known limitation: the G923 *PlayStation* variant loses force feedback.

### Present-day limitations — the complete list

Of 123 rows, **3** describe a real difference a user could notice on this build today; everything else is fully covered. They are:

- `b00a72159` Add support for NSO Mega Drive Controller (#50) — see its record for the decision and affected hardware.
- `43c52e9ef` Update lg4ff to latest version. Fix broken 32bit rumble/ff (#54) — see its record for the decision and affected hardware.
- `fc09a292a` rtl8821cu: workaround for bad efuse in EDUP EP-AC1661. — see its record for the decision and affected hardware.

## The table

| SHA | Branch | Disposition | Carried patch | Why / replacement | Impact today | Drop-risk | Coupled | Doc✓ | T2 | Subject |
|---|---|---|---|---|---|---|---|---|---|---|
| `071d9092e` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | cosmetic/silent | — | Y | ✓ | dts: fix warnings. |
| `077c2c317` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Disable USB overcurrent signaling. |
| `0d7778d1f` | v5.15 | **carried** | 0023-hid-wiimote-fixes.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | wiimote: set uniq field. |
| `1337de1fd` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Switch to i2c-gpio driver for smbus compatibility. |
| `15968bc26` | v5.15 | **carried** | 0023-hid-wiimote-fixes.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | wiimote: fix analog ranges. |
| `246984fce` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Enable SPI on LTC. Use HPS LED for SD card activity. |
| `2ac0aa1e8` | v5.15 | **carried** | 0026-input-mousedev-eviocgrab.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | input: support for mouseX and mice in EVIOCGRAB mode. |
| `2d39e76d1` | v5.15 | **carried** | 0020-mmc-no-led-on-send-status.patch | — | none (carried) | cosmetic/silent | Y | Y | ✓ | mmc: don't activate LED on status command. |
| `333d49b95` | v5.15 | **carried** | 0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Implement MiSTer audio driver. |
| `3d72b9db7` | v5.15 | **carried** | 0003-cpufreq-cyclone5-de10nano-overclock.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Add cpufreq/overclock driver (#34) |
| `45283785a` | v5.15 | **carried** | 0032-hid-nintendo-joycon-combo-led.patch | — | none (carried) | feature-loss/silent | Y | N | ✓ | hid-nintendo: add virtual combo led, don't warn by IMU comp… |
| `47dc53a22` | v5.15 | **carried** | 0023-hid-wiimote-fixes.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | wiimote: fix the buttons codes. |
| `484f68172` | v5.15 | **carried** | 0015-hid-nintendo-nso-famicom.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | input: Add support for the NSO Famicom controllers (no mic … |
| `52a56ae3d` | v5.15 | **carried** | 0026-input-mousedev-eviocgrab.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | mousedev: disable touch to click on DualShock4 and DualSens… |
| `5bdbf2f7e` | v5.15 | **carried** | 0018-hid-controllable-quirk.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | hid: add quirk for ControllaBLE. |
| `5c410e935` | v5.15 | **carried** | 0022-hid-playstation-ds4-mac-fix.patch | — | none (carried) | feature-loss/loud | — | Y | ✓ | hid-sony: fix for 3rd party DS4 failing to connect by wire. |
| `60821059c` | v5.15 | **carried** | 0035-hid-nintendo-home-led-nonfatal.patch | — | none (carried) | feature-loss/loud | Y | N | ✓ | hid-nintendo: don't fail if home led is not present. |
| `60e08955f` | v5.15 | **carried** | 0037-hid-playstation-dualsense-mute-btn-z.patch | — | none (carried) | cosmetic/silent | — | N | ✓ | dualsense: give mute button and led to system. |
| `6827e7644` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Support for RTC PCF8563 |
| `70e391b81` | v5.15 | **carried** | 0024-hid-input-keyrah-europe1.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | HID: map key Europe 1(0x32) to F24 code (for Keyrah). |
| `71c583074` | v5.15 | **carried** | 0030-i2c-designware-quiet-timeout.patch | — | none (carried) | cosmetic/silent | — | Y | ✓ | Disable RTC error messages. |
| `77862a67f` | v5.15 | **carried** | 0014-hid-gamecube-adapter.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Add support for official gamecube-adapter (#48) |
| `7d2df2d2d` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Disable DMA on UART0/1. DMA is broken on Designware UARTs. |
| `8179ac736` | v5.15 | **carried** | 0011-hid-guncon3.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Add driver for Namco Guncon 3 (#20) |
| `817ace70b` | v5.15 | **carried** | 0027-mt76x2u-release-xbox-adapter-ids.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Remove XBox One Wireless Adapter USB IDs from mt76 driver t… |
| `8908e0fe1` | v5.15 | **carried** | 0012-hid-fanatec.patch | — | none (carried) | feature-loss/loud | — | N | ✓ | Fix module compile for Fanatec driver (#25) |
| `9b9aebfac` | v5.15 | **carried** | 0011-hid-guncon3.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | hid-guncon3: fix warnings. |
| `a2242dd85` | v5.15 | **carried** | 0017-xpad-mister-deltas.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | xpad: exclude GIP-capable controllers. |
| `aa8afe109` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | boot-critical/silent | Y | Y | ✓ | Add de10-nano DT. |
| `b02a4a011` | v5.15 | **carried** | 0036-btusb-csr-clone-lmp-subver-2512.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | btusb: support for more CSR clones. |
| `b1b168eb6` | v5.15 | **carried** | 0013-hid-flydigi-vader.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | input: add HID driver to fix Flydigi Vader 4 Pro mapping in… |
| `b62efee23` | v5.15 | **carried** | 0029-leds-gpio-brightness-hw-changed.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | hps_led: enable brightness change notification. |
| `b745ce6d9` | v5.15 | **carried** | 0019-hidpp-k400-fn-inversion.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | fix Logitech K400 Plus FN problem (#15) |
| `b76b4bc6a` | v5.15 | **carried** | 0033-hid-playstation-dualsense-player-id-led.patch | — | none (carried) | cosmetic/silent | — | N | ✓ | dualsense: leds config for player 6. |
| `c035c21c0` | v5.15 | **carried** | 0017-xpad-mister-deltas.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | xpad: support for extra buttons on Flydigi Vader 3/4/5 Pro … |
| `c4d12c768` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | none/silent | Y | Y | ✓ | Enable UART1. |
| `c5066763c` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Enable i2c2 device. |
| `c784a6856` | v5.15 | **carried** | 0016-hid-microsoft-elite2-paddles.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | hid-microsoft: support for XBox Elite 2 paddles. |
| `d1002ecd4` | v5.15 | **carried** | 0001-fbdev-add-MiSTer_fb-driver.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Implement MiSTer frame buffer device. |
| `d7adb20b4` | v5.15 | **carried** | 0028-dwc2-fix-unaligned-in-split.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Fix for unaligned IN data. (#57) |
| `e40563ae1` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Support for i2c rtc m41t81. |
| `e503d193c` | v5.15 | **carried** | 0010-hid-guncon2.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Add driver for Namco GunCon 2 |
| `e6df8e30e` | v5.15 | **carried** | 0003-cpufreq-cyclone5-de10nano-overclock.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | Improve clock transition stability and get OSC1 freq from D… |
| `e82a59280` | v5.15 | **carried** | 0012-hid-fanatec.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Add Fanatec wheel driver (#24) |
| `ed8f8e6ce` | v5.15 | **carried** | 0012-hid-fanatec.patch | — | none (carried) | cosmetic/silent | — | Y | ✓ | Fix warning. |
| `f0982bf2c` | v5.15 | **carried** | 0025-usbhid-jspoll-gamepad.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | usbhid: apply jspoll for gamepad usage as well. |
| `f3c75eb02` | v5.15 | **carried** | 0017-xpad-mister-deltas.patch | — | none (carried) | feature-loss/silent | — | Y | ✓ | XInput polling rate param + Qanba Obsidian XInput mode supp… |
| `f52690120` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | — | none (carried) | cosmetic/silent | — | Y | ✓ | dts: enable bridges. |
| `f84543926` | v5.15 | **carried** | 0033-hid-playstation-dualsense-player-id-led.patch | — | none (carried) | feature-loss/silent | Y | N | ✓ | dualsense: add player id led control. |
| `fc8f3c2c6` | v5.15 | **carried** | 0019-hidpp-k400-fn-inversion.patch | — | none (carried) | feature-loss/silent | Y | Y | ✓ | Logitech K400r: disable Fn swap. |
| `0d60c3482` | v5.15 | **dropped-upstream** | — | in mainline: `fc97b4d6a1a6`; → fc97b4d6a1a6 (HID: playstation: expose DualSense… | none (in mainline) | cosmetic/silent | — | N | ✓ | dualsense: add lightbar color control. |
| `1412bd707` | v5.15 | **dropped-upstream** | — | in mainline: `74cb485f68eb`; → 74cb485f68eb (upstream HID: playstation: sanity … | none (in mainline) | boot-critical/loud | — | Y | ✓ | hid-sony: fix divide by 0 exception. |
| `2799f8b94` | v5.15 | **dropped-upstream** | — | in mainline: `94f18bb19945`; → 94f18bb19945 (HID: nintendo: add support for nso… | none (in mainline) | feature-loss/silent | — | Y | ✓ | add support for NSO N64 controller (#49) |
| `2efa211a2` | v5.13.12 | **dropped-upstream** | — | in mainline: `bb23f07cb639`; → bb23f07cb | none (in mainline) | cosmetic/silent | — | ? | ✓ | btrtl: add RTL8761B ROMs to list. |
| `3fb48dc16` | v5.15 | **dropped-upstream** | — | in mainline: `4fd6d4907961` | none (in mainline) | feature-loss/silent | — | Y | ✓ | Add support for TP-Link UB500 Adapter (#33) |
| `40120d090` | v5.15 | **dropped-upstream** | — | in mainline: `27f4d1f214ae` | none (in mainline) | feature-loss/silent | — | ? | ✓ | drivers: bluetooth: backport some drivers from upstream. |
| `552f9f197` | v5.15 | **dropped-upstream** | — | in mainline: `f7cbce60a38a`; → f7cbce60a38a (Bluetooth: hci_sync: Fix UAF on cr…; 881559af5f5c (Bluetooth: hci_sync: Attempt to de… | none (in mainline) | boot-critical/loud | — | Y | ✓ | hci_conn: prevent call with NULL pointer. |
| `6eec2a515` | v5.15 | **dropped-upstream** | — | in mainline: `21617de3b464` | none (in mainline) | feature-loss/silent | — | Y | ✓ | xpad: Add 8BitDo Ultimate Controller ID (#36) |
| `9521b003c` | v5.15 | **dropped-upstream** | — | in mainline: `24175157b852`; → 24175157b852 (upstream HID: hid-google-stadiaff:… | none (in mainline) | feature-loss/silent | Y | Y | ✓ | Add support for Google Stadia controller w/ rumble (#52) |
| `9a8cb6a93` | v5.15 | **dropped-upstream** | — | in mainline: `f5554725f304`; → f5554725f | none (in mainline) | feature-loss/silent | — | Y | ✓ | hid-microsoft: support for XBox Series X/S controller. |
| `9bdab534b` | v5.15 | **dropped-upstream** | — | in mainline: `50503e360eeb`; → 50503e360eeb | none (in mainline) | cosmetic/silent | Y | N | ✓ | hid-nintendo: use default calibration if empty calibration … |
| `a10f4246f` | v5.15 | **dropped-upstream** | — | in mainline: `c7577014b74c` | none (in mainline) | feature-loss/silent | — | Y | ✓ | btusb: add Edimax BT-8500 vid/pid for FW loading. |
| `a6165424f` | v5.13.12 | **dropped-upstream** | — | in mainline: `c62f7cd8ed06`; → c62f7cd8ed06 | none (in mainline) | none/silent | — | ? | ✓ | xinmotek fix (#11) |
| `adbaaea91` | v5.15 | **dropped-upstream** | — | in mainline: `f5554725f304` | none (in mainline) | feature-loss/silent | — | Y | ✓ | hid-microsoft: add XOne Elite 2 ID. |
| `af27afc4c` | v5.15 | **dropped-upstream** | — | in mainline: `e23c69e33248`; → vanilla-6.18.38-xpad.c (commits e23c69e33248 and… | none (in mainline) | none/silent | — | N | ✓ | Update xpad driver (#63) |
| `b00a72159` | v5.15 | **dropped-upstream** | — | in mainline: `94f18bb19945`; → 94f18bb19945 (vanilla, 2023-12-04, 'HID: nintend… | **limitation — see record** | feature-loss/silent | Y | N | ✓ | Add support for NSO Mega Drive Controller (#50) |
| `c4ec5cb40` | v5.15 | **dropped-upstream** | — | in mainline: `2af16c1f846b`; → 2af16c1f846b (v5.16, basic driver); 294a828759d0 (v5.16, charging grip); … | none (in mainline) | feature-loss/silent | Y | Y | ✓ | Support for Nintendo Switch controller (pro, nes, snes, joy… |
| `e155f6a2f` | v5.15 | **dropped-upstream** | 0034-hid-nintendo-nes-famicom-stock-ab-mapping.patch | in mainline: `94f18bb19945`; → 94f18bb19 | none (in mainline) | feature-loss/silent | Y | Y | ✓ | hid-nintendo: support for Switch NES and SNES controllers. |
| `e2c082ef9` | v5.15 | **dropped-upstream** | — | in mainline: `a3dc32c635ba`; → a3dc32c635bae0ae569f489e00de0e8f015bfc25 (vanill… | none (in mainline) | feature-loss/silent | — | Y | ✓ | usb-storage: blacklist Realtek WiFi driver CD-ROM. |
| `ec75e65f8` | v5.13.12 | **dropped-upstream** | — | in mainline: `c62f7cd8ed06`; → c62f7cd8ed06 | none (in mainline) | none/silent | — | ? | ✓ | Revert "xinmotek fix (#11)" |
| `f9c64d8cd` | v5.15 | **dropped-upstream** | — | in mainline: `6eb04ca8c52e` | none (in mainline) | boot-critical/loud | — | Y | ✓ | drivers: hid-nintendo: fix possible division by 0. |
| `0d7b4fc7e` | v5.15 | **dropped-deliberate** | — | → board/mister/de10nano/linux.config (CONFIG_PANTH… | none (replaced) | feature-loss/silent | Y | Y | ✓ | Enable CONFIG_PANTHERLORD_FF (#27) |
| `0d8641a2b` | v5.14 | **dropped-deliberate** | — | → CONFIG_RTL8XXXU=m (mainline in-kernel driver, bo…; 33ff5146a (MiSTer-v5.15 fork commit, combined re…; … | none (replaced) | none/None | — | N | ✓ | Add rtl8188eu, rtl8188fu WiFi drivers. |
| `143ce187e` | v5.15 | **dropped-deliberate** | — | → CONFIG_RTW88_8822BU=m (mainline kernel); BR2_PACKAGE_RTL88X2BU (available but disabled in… | none (replaced) | feature-loss/silent | — | Y | ✓ | Sync rtl88x2bu with upstream |
| `1a1f208fa` | v5.15 | **dropped-deliberate** | — | → board/mister/de10nano/linux.config (6.18.38 succ… | none (replaced) | none/silent | — | Y | ✓ | Update defconfig. |
| `215e6e662` | v5.15 | **dropped-deliberate** | — | → board/mister/de10nano/linux.config (6.18.38 succ… | none (replaced) | none/silent | — | Y | ✓ | Add defconfig. |
| `2548c2978` | v5.15 | **dropped-deliberate** | — | → 0004-dts-de10nano-MiSTer.patch | none (replaced) | feature-loss/silent | — | N | ✓ | Support for i2c rtc mcp794xx. |
| `316288a3d` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | — | Y | ✓ | Enable NFS4 driver |
| `33ff5146a` | v5.15 | **dropped-deliberate** | — | → 3740d5b88 (in-fork: 'Backport rtl8812au rtl8821a…; package/rtl8812au (BR2_PACKAGE_RTL8812AU=y) -- R…; … | none (replaced) | none/silent | — | Y | ✓ | Add rtl8821au/rtl8812au, rtl88x2bu, rtl8821cu, rtl8188eu, r… |
| `346cbf62b` | v5.14 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | — | ? | ✓ | defconfig: update. |
| `3740d5b88` | v5.15 | **dropped-deliberate** | — | → BR2_PACKAGE_RTL8812AU (out-of-tree, morrownr for…; BR2_PACKAGE_RTL8821AU_MORROWNR (out-of-tree, mor…; … | none (replaced) | none/silent | — | Y | ✓ | Backport  rtl8812au  rtl8821au  rtl8821cu drivers from morr… |
| `3d587b6a3` | v5.13.12 | **dropped-deliberate** | — | → 33ff5146a7248ef86e15bb3b78f1f7516f86ee4f (v5.15 …; mainline rtw88 drivers (RTL8821C, RTL8822B); … | none (replaced) | none/silent | — | ? | ✓ | Add rtl8821au, rtl88x2bu, rtl8821cu WiFi drivers. |
| `3d95de58f` | v5.15 | **dropped-deliberate** | — | → initramfs /init boot flow with loop= parameter p… | none (replaced) | feature-loss/silent | — | Y | ✓ | Support for init loop device. |
| `409f81077` | v5.15 | **dropped-deliberate** | — | → e23c69e3324892f7420686b3aaa0403df6cf152c — Input…; package/xone (BR2_PACKAGE_XONE=y) — the driver t… | none (replaced) | none/silent | Y | Y | ✓ | xpad: add Elite 2 ID. |
| `43c52e9ef` | v5.15 | **dropped-deliberate** | — | → hid-logitech-hidpp (for G923 Xbox, 046d:c26e) — … | **limitation — see record** | feature-loss/silent | — | Y | ✓ | Update lg4ff to latest version. Fix broken 32bit rumble/ff … |
| `43fbb63ae` | v5.15 | **dropped-deliberate** | — | → package/rtl8812au (BR2_PACKAGE_RTL8812AU=y); package/rtl8821au-morrownr (BR2_PACKAGE_RTL8821A…; … | none (replaced) | none/silent | — | Y | ✓ | wireless: realtek: fix makefiles. |
| `4ddd8ec3d` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | — | Y | ✓ | Add xone (XBox wireless adapter) driver. |
| `5391b8171` | v5.15 | **dropped-deliberate** | — | → board/mister/de10nano/linux.config (NFS_FS=y exp… | none (replaced) | none/silent | — | Y | ✓ | Update defconfig. |
| `5a7965488` | v5.15 | **dropped-deliberate** | — | → package/xone (dlundqvist/xone fork, commit f2aa9… | none (replaced) | feature-loss/silent | Y | Y | ✓ | xone: fixed rumble. |
| `6c2d53934` | v5.15 | **dropped-deliberate** | — | see record | none | none/silent | — | Y | ✓ | Use 100kHz for i2c-1 for better compatibility with devices. |
| `7436e2d6e` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | — | Y | ✓ | mt7601u possible fix? |
| `7828d722e` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | cosmetic/silent | — | ? | ✓ | defconfig: compile 80211 as a module. |
| `7f7148c1f` | v5.15 | **dropped-deliberate** | — | → 0031-exfat-samsung-symlinks.patch | none (replaced) | none/silent | — | Y | ✓ | exfat: remove exfat_config.h messing kernel config. |
| `8270e78f4` | v5.15 | **dropped-deliberate** | — | → package/xone (dlundqvist/xone fork, commit f2aa9… | none (replaced) | feature-loss/silent | — | Y | ✓ | xone: backport the paddles from fork. |
| `858322ce6` | v5.15 | **dropped-deliberate** | — | → vanilla-exfat-6.18 | none (replaced) | none/silent | — | Y | ✓ | exfat: fix memory mapped file ops. |
| `8a100f2ed` | v5.15 | **dropped-deliberate** | — | → vanilla 6.18.38 drivers/hid/hid-lg4ff.c (in-tree…; hid-logitech-hidpp.c for the unrelated G923 Xbox… | none (replaced) | none/silent | Y | Y | ✓ | Update hid-lg4ff.c for Logitech Wheel Support (#32) |
| `8b6b8c2f5` | v5.15 | **dropped-deliberate** | — | → 0031-exfat-samsung-symlinks.patch | none (replaced) | none/silent | — | Y | ✓ | Remove original exFAT driver. |
| `97a398176` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | Y | Y | ✓ | update config. |
| `993b82e31` | v5.15 | **dropped-deliberate** | — | → package/rtl8812au (morrownr/8812au-20210820 @ 8c…; package/rtl8821au-morrownr (morrownr/8821au-2021…; … | none (replaced) | none/silent | — | Y | ✓ | Update realtek drivers from upstream (#44) |
| `99a2c80d0` | v5.15 | **dropped-deliberate** | — | → 0031-exfat-samsung-symlinks.patch | none (replaced) | feature-loss/silent | Y | Y | ✓ | exfat: use ATTR_SYSTEM as symlink flag to preserve links wh… |
| `9f59d13d5` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | Y | Y | ✓ | Enable force feedback on PS adapter (#56) |
| `a547c18d0` | v5.15 | **dropped-deliberate** | — | see record | none | none/silent | — | Y | ✓ | remove unused files. |
| `ae9313e22` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | — | Y | ✓ | Enable the NFS filesystem in the kernel. (#45) |
| `b2a04cbfd` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | cosmetic/silent | Y | Y | ✓ | vt: reduce from 63 to 9 ttys. |
| `bbeff2c30` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | Y | N | ✓ | Enable Logitech D-Input drivers. |
| `bdedb82d2` | v5.13.12 | **dropped-deliberate** | — | → CONFIG_RTL8XXXU=m (mainline rtl8xxxu, in-kernel)…; 33ff5146a (in-fork: 2021-11-08, combines rtl8188… | none (replaced) | feature-loss/silent | — | ? | ✓ | Add rtl8188eu, rtl8188fu WiFi drivers. |
| `c3c1a0ec9` | v5.14 | **dropped-deliberate** | — | → a95855a70 (socfpga-4.19 dwc2 port — v5.14 only, … | none (replaced) | boot-critical/loud | — | Y | ✓ | dwc2: remove original driver. |
| `c708f2222` | v5.15 | **dropped-deliberate** | — | → package/xone (dlundqvist/xone commit f2aa9fe0110… | none (replaced) | feature-loss/silent | — | Y | ✓ | xone: update to latest. |
| `c70a3fc27` | v5.14 | **dropped-deliberate** | — | → 33ff5146a (in-fork, v5.15: 'Add rtl8821au/rtl881…; 3740d5b88 (in-fork: 'Backport rtl8812au rtl8821a…; … | none (replaced) | none/silent | — | ? | ✓ | Add rtl8821au, rtl88x2bu, rtl8821cu WiFi drivers. |
| `d5beb5aa6` | v5.15 | **dropped-deliberate** | — | → package/xone (dlundqvist fork f2aa9fe01...) | none (replaced) | feature-loss/silent | — | Y | ✓ | xone: sysfs for software pairing. |
| `d776ddb4e` | v5.15 | **dropped-deliberate** | — | → package/xone (dlundqvist/xone fork, commit f2aa9… | none (replaced) | feature-loss/loud | — | Y | ✓ | xone: use firmware according to PID. |
| `d788e7ab9` | v5.15 | **dropped-deliberate** | — | → board/mister/de10nano/linux.config (CONFIG_LOGIG… | none (replaced) | feature-loss/silent | — | Y | ✓ | Update defconfig (enable logitech wheels). |
| `e2eb39e6f` | v5.15 | **dropped-deliberate** | — | → BR2_PACKAGE_XONE (dlundqvist/xone@f2aa9fe01103d7… | none (replaced) | feature-loss/silent | — | Y | ✓ | xone: update driver. |
| `f0fb626ac` | v5.15 | **dropped-deliberate** | — | see record | none (decided; see record) | feature-loss/silent | Y | Y | ✓ | defconfig: enable macvlan support (#71) |
| `fc09a292a` | v5.15 | **dropped-deliberate** | — | see record | **limitation — see record** | feature-loss/silent | — | ? | ✓ | rtl8821cu: workaround for bad efuse in EDUP EP-AC1661. |
| `109599db7` | v5.13.12 | **dropped-obsolete** | — | → CONFIG_RTL8XXXU=m (mainline in-kernel driver, bo…; package/rtl8188eu-aircrack-ng -- present in tree… | none (replaced) | none/silent | — | Y | ✓ | Update rtl8188eu driver. |
| `115b1d1ae` | v5.15 | **dropped-obsolete** | — | → vanilla rtw88_8822bu (drivers/net/wireless/realt…; package/rtl8812au (BR2_PACKAGE_RTL8812AU=y, morr… | none (replaced) | none/silent | — | N | ✓ | Fix for edimax EW-7822ULC BUG #769  (#47) |
| `2371fb1aa` | v5.15 | **dropped-obsolete** | — | → package/rtl8812au (BR2_PACKAGE_RTL8812AU=y; morr…; package/rtl8821au-morrownr (BR2_PACKAGE_RTL8821A…; … | none (replaced) | feature-loss/silent | — | Y | ✓ | Sync rtl8821au with upstream |
| `38a039bab` | v5.13.12 | **dropped-obsolete** | — | → rtl8821au-morrownr (out-of-tree BR2 package, com… | none (replaced) | cosmetic/silent | — | N | ✓ | rtl8821au: disable warnings. |
| `5220d6686` | v5.15 | **dropped-obsolete** | — | → Carried patch 0031-exfat-samsung-symlinks.patch … | none (replaced) | none/silent | — | Y | ✓ | exfat: cleanup from kernel version conditions. |
| `a95855a70` | v5.14 | **dropped-obsolete** | — | → d7adb20b4ca595838289406c083fff78f004a8c3 — unali… | none (replaced) | feature-loss/silent | — | ? | ✓ | dwc2: port from socfpga-v4.19. |
| `df35bdb27` | v5.15 | **dropped-obsolete** | — | → vanilla 6.18 fs/exfat (partial: filesystem funct…; 0031-exfat-samsung-symlinks.patch (capability-on… | none (replaced) | feature-loss/silent | Y | Y | ✓ | Add exFAT with symlinks support. |
| `ffbb77e46` | v5.13.12 | **dropped-obsolete** | — | → 8b6b8c2f5 (Remove original exFAT driver, v5.15); df35bdb27 (Add exFAT with symlinks support, v5.1…; … | none (replaced) | feature-loss/silent | Y | ? | ✓ | Replace exFAT with version supporting symlinks. |
