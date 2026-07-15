# Reconciliation — one row per fork commit

Generated 2026-07-15 13:37 UTC by `reduce.py` from 123 records (108 MiSTer-v5.15 + 15 old-branch residue). Tier-2 verified: 123/123.

| SHA | Branch | Disposition | Carried patch | Severity | Fail | Coupled | Doc✓ | T2 | Subject |
|---|---|---|---|---|---|---|---|---|---|
| `071d9092e` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | cosmetic | silent | — | Y | ✓ | dts: fix warnings. |
| `077c2c317` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | — | Y | ✓ | Disable USB overcurrent signaling. |
| `0d7778d1f` | v5.15 | **carried** | 0023-hid-wiimote-fixes.patch | feature-loss | silent | Y | Y | ✓ | wiimote: set uniq field. |
| `1337de1fd` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | — | Y | ✓ | Switch to i2c-gpio driver for smbus compatibility. |
| `15968bc26` | v5.15 | **carried** | 0023-hid-wiimote-fixes.patch | feature-loss | silent | Y | Y | ✓ | wiimote: fix analog ranges. |
| `246984fce` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | Y | Y | ✓ | Enable SPI on LTC. Use HPS LED for SD card activity. |
| `2ac0aa1e8` | v5.15 | **carried** | 0026-input-mousedev-eviocgrab.patch | feature-loss | silent | Y | Y | ✓ | input: support for mouseX and mice in EVIOCGRAB mode. |
| `2d39e76d1` | v5.15 | **carried** | 0020-mmc-no-led-on-send-status.patch | cosmetic | silent | Y | Y | ✓ | mmc: don't activate LED on status command. |
| `333d49b95` | v5.15 | **carried** | 0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch | feature-loss | silent | Y | Y | ✓ | Implement MiSTer audio driver. |
| `3d72b9db7` | v5.15 | **carried** | 0003-cpufreq-cyclone5-de10nano-overclock.patch | feature-loss | silent | — | Y | ✓ | Add cpufreq/overclock driver (#34) |
| `45283785a` | v5.15 | **carried** | 0032-hid-nintendo-joycon-combo-led.patch | feature-loss | silent | Y | N | ✓ | hid-nintendo: add virtual combo led, don't warn by IMU compe |
| `47dc53a22` | v5.15 | **carried** | 0023-hid-wiimote-fixes.patch | feature-loss | silent | Y | Y | ✓ | wiimote: fix the buttons codes. |
| `484f68172` | v5.15 | **carried** | 0015-hid-nintendo-nso-famicom.patch | feature-loss | silent | — | Y | ✓ | input: Add support for the NSO Famicom controllers (no mic f |
| `52a56ae3d` | v5.15 | **carried** | 0026-input-mousedev-eviocgrab.patch | feature-loss | silent | Y | Y | ✓ | mousedev: disable touch to click on DualShock4 and DualSense |
| `5bdbf2f7e` | v5.15 | **carried** | 0018-hid-controllable-quirk.patch | feature-loss | silent | Y | Y | ✓ | hid: add quirk for ControllaBLE. |
| `5c410e935` | v5.15 | **carried** | 0022-hid-playstation-ds4-mac-fix.patch | feature-loss | loud | — | Y | ✓ | hid-sony: fix for 3rd party DS4 failing to connect by wire. |
| `60821059c` | v5.15 | **carried** | 0035-hid-nintendo-home-led-nonfatal.patch | feature-loss | loud | Y | N | ✓ | hid-nintendo: don't fail if home led is not present. |
| `60e08955f` | v5.15 | **carried** | 0037-hid-playstation-dualsense-mute-btn-z.patch | cosmetic | silent | — | N | ✓ | dualsense: give mute button and led to system. |
| `6827e7644` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | — | Y | ✓ | Support for RTC PCF8563 |
| `70e391b81` | v5.15 | **carried** | 0024-hid-input-keyrah-europe1.patch | feature-loss | silent | Y | Y | ✓ | HID: map key Europe 1(0x32) to F24 code (for Keyrah). |
| `71c583074` | v5.15 | **carried** | 0030-i2c-designware-quiet-timeout.patch | cosmetic | silent | — | Y | ✓ | Disable RTC error messages. |
| `77862a67f` | v5.15 | **carried** | 0014-hid-gamecube-adapter.patch | feature-loss | silent | — | Y | ✓ | Add support for official gamecube-adapter (#48) |
| `7d2df2d2d` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | — | Y | ✓ | Disable DMA on UART0/1. DMA is broken on Designware UARTs. |
| `8179ac736` | v5.15 | **carried** | 0011-hid-guncon3.patch | feature-loss | silent | Y | Y | ✓ | Add driver for Namco Guncon 3 (#20) |
| `817ace70b` | v5.15 | **carried** | 0027-mt76x2u-release-xbox-adapter-ids.patch | feature-loss | silent | Y | Y | ✓ | Remove XBox One Wireless Adapter USB IDs from mt76 driver to |
| `8908e0fe1` | v5.15 | **carried** | 0012-hid-fanatec.patch | feature-loss | loud | — | N | ✓ | Fix module compile for Fanatec driver (#25) |
| `9b9aebfac` | v5.15 | **carried** | 0011-hid-guncon3.patch | feature-loss | silent | Y | Y | ✓ | hid-guncon3: fix warnings. |
| `a2242dd85` | v5.15 | **carried** | 0017-xpad-mister-deltas.patch | feature-loss | silent | — | Y | ✓ | xpad: exclude GIP-capable controllers. |
| `aa8afe109` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | boot-critical | silent | Y | Y | ✓ | Add de10-nano DT. |
| `b02a4a011` | v5.15 | **carried** | 0036-btusb-csr-clone-lmp-subver-2512.patch | feature-loss | silent | — | Y | ✓ | btusb: support for more CSR clones. |
| `b1b168eb6` | v5.15 | **carried** | 0013-hid-flydigi-vader.patch | feature-loss | silent | — | Y | ✓ | input: add HID driver to fix Flydigi Vader 4 Pro mapping in  |
| `b62efee23` | v5.15 | **carried** | 0029-leds-gpio-brightness-hw-changed.patch | feature-loss | silent | Y | Y | ✓ | hps_led: enable brightness change notification. |
| `b745ce6d9` | v5.15 | **carried** | 0019-hidpp-k400-fn-inversion.patch | feature-loss | silent | Y | Y | ✓ | fix Logitech K400 Plus FN problem (#15) |
| `b76b4bc6a` | v5.15 | **carried** | 0033-hid-playstation-dualsense-player-id-led.patch | cosmetic | silent | — | N | ✓ | dualsense: leds config for player 6. |
| `c035c21c0` | v5.15 | **carried** | 0017-xpad-mister-deltas.patch | feature-loss | silent | Y | Y | ✓ | xpad: support for extra buttons on Flydigi Vader 3/4/5 Pro i |
| `c4d12c768` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | none | silent | Y | Y | ✓ | Enable UART1. |
| `c5066763c` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | Y | Y | ✓ | Enable i2c2 device. |
| `c784a6856` | v5.15 | **carried** | 0016-hid-microsoft-elite2-paddles.patch | feature-loss | silent | — | Y | ✓ | hid-microsoft: support for XBox Elite 2 paddles. |
| `d1002ecd4` | v5.15 | **carried** | 0001-fbdev-add-MiSTer_fb-driver.patch | feature-loss | silent | Y | Y | ✓ | Implement MiSTer frame buffer device. |
| `d7adb20b4` | v5.15 | **carried** | 0028-dwc2-fix-unaligned-in-split.patch | feature-loss | silent | Y | Y | ✓ | Fix for unaligned IN data. (#57) |
| `e40563ae1` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | feature-loss | silent | — | Y | ✓ | Support for i2c rtc m41t81. |
| `e503d193c` | v5.15 | **carried** | 0010-hid-guncon2.patch | feature-loss | silent | Y | Y | ✓ | Add driver for Namco GunCon 2 |
| `e6df8e30e` | v5.15 | **carried** | 0003-cpufreq-cyclone5-de10nano-overclock.patch | feature-loss | silent | — | Y | ✓ | Improve clock transition stability and get OSC1 freq from DT |
| `e82a59280` | v5.15 | **carried** | 0012-hid-fanatec.patch | feature-loss | silent | Y | Y | ✓ | Add Fanatec wheel driver (#24) |
| `ed8f8e6ce` | v5.15 | **carried** | 0012-hid-fanatec.patch | cosmetic | silent | — | Y | ✓ | Fix warning. |
| `f0982bf2c` | v5.15 | **carried** | 0025-usbhid-jspoll-gamepad.patch | feature-loss | silent | — | Y | ✓ | usbhid: apply jspoll for gamepad usage as well. |
| `f3c75eb02` | v5.15 | **carried** | 0017-xpad-mister-deltas.patch | feature-loss | silent | — | Y | ✓ | XInput polling rate param + Qanba Obsidian XInput mode suppo |
| `f52690120` | v5.15 | **carried** | 0004-dts-de10nano-MiSTer.patch | cosmetic | silent | — | Y | ✓ | dts: enable bridges. |
| `f84543926` | v5.15 | **carried** | 0033-hid-playstation-dualsense-player-id-led.patch | feature-loss | silent | Y | N | ✓ | dualsense: add player id led control. |
| `fc8f3c2c6` | v5.15 | **carried** | 0019-hidpp-k400-fn-inversion.patch | feature-loss | silent | Y | Y | ✓ | Logitech K400r: disable Fn swap. |
| `0d60c3482` | v5.15 | **dropped-upstream** | — | cosmetic | silent | — | N | ✓ | dualsense: add lightbar color control. |
| `1412bd707` | v5.15 | **dropped-upstream** | — | boot-critical | loud | — | Y | ✓ | hid-sony: fix divide by 0 exception. |
| `2799f8b94` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | add support for NSO N64 controller (#49) |
| `2efa211a2` | v5.13.12 | **dropped-upstream** | — | cosmetic | silent | — | ? | ✓ | btrtl: add RTL8761B ROMs to list. |
| `3fb48dc16` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | Add support for TP-Link UB500 Adapter (#33) |
| `40120d090` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | ? | ✓ | drivers: bluetooth: backport some drivers from upstream. |
| `552f9f197` | v5.15 | **dropped-upstream** | — | boot-critical | loud | — | Y | ✓ | hci_conn: prevent call with NULL pointer. |
| `6eec2a515` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | xpad: Add 8BitDo Ultimate Controller ID (#36) |
| `9521b003c` | v5.15 | **dropped-upstream** | — | feature-loss | silent | Y | Y | ✓ | Add support for Google Stadia controller w/ rumble (#52) |
| `9a8cb6a93` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | hid-microsoft: support for XBox Series X/S controller. |
| `9bdab534b` | v5.15 | **dropped-upstream** | — | cosmetic | silent | Y | N | ✓ | hid-nintendo: use default calibration if empty calibration i |
| `a10f4246f` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | btusb: add Edimax BT-8500 vid/pid for FW loading. |
| `a6165424f` | v5.13.12 | **dropped-upstream** | — | none | silent | — | ? | ✓ | xinmotek fix (#11) |
| `adbaaea91` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | hid-microsoft: add XOne Elite 2 ID. |
| `af27afc4c` | v5.15 | **dropped-upstream** | — | none | silent | — | N | ✓ | Update xpad driver (#63) |
| `b00a72159` | v5.15 | **dropped-upstream** | — | feature-loss | silent | Y | N | ✓ | Add support for NSO Mega Drive Controller (#50) |
| `c4ec5cb40` | v5.15 | **dropped-upstream** | — | feature-loss | silent | Y | Y | ✓ | Support for Nintendo Switch controller (pro, nes, snes, joyc |
| `e155f6a2f` | v5.15 | **dropped-upstream** | 0034-hid-nintendo-nes-famicom-stock-ab-mapping.patch | feature-loss | silent | Y | Y | ✓ | hid-nintendo: support for Switch NES and SNES controllers. |
| `e2c082ef9` | v5.15 | **dropped-upstream** | — | feature-loss | silent | — | Y | ✓ | usb-storage: blacklist Realtek WiFi driver CD-ROM. |
| `ec75e65f8` | v5.13.12 | **dropped-upstream** | — | none | silent | — | ? | ✓ | Revert "xinmotek fix (#11)" |
| `f9c64d8cd` | v5.15 | **dropped-upstream** | — | boot-critical | loud | — | Y | ✓ | drivers: hid-nintendo: fix possible division by 0. |
| `0d7b4fc7e` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | Y | ✓ | Enable CONFIG_PANTHERLORD_FF (#27) |
| `0d8641a2b` | v5.14 | **dropped-deliberate** | — | none | None | — | N | ✓ | Add rtl8188eu, rtl8188fu WiFi drivers. |
| `143ce187e` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Sync rtl88x2bu with upstream |
| `1a1f208fa` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Update defconfig. |
| `215e6e662` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Add defconfig. |
| `2548c2978` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | N | ✓ | Support for i2c rtc mcp794xx. |
| `316288a3d` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Enable NFS4 driver |
| `33ff5146a` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Add rtl8821au/rtl8812au, rtl88x2bu, rtl8821cu, rtl8188eu, rt |
| `346cbf62b` | v5.14 | **dropped-deliberate** | — | feature-loss | silent | — | ? | ✓ | defconfig: update. |
| `3740d5b88` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Backport  rtl8812au  rtl8821au  rtl8821cu drivers from morro |
| `3d587b6a3` | v5.13.12 | **dropped-deliberate** | — | none | silent | — | ? | ✓ | Add rtl8821au, rtl88x2bu, rtl8821cu WiFi drivers. |
| `3d95de58f` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Support for init loop device. |
| `409f81077` | v5.15 | **dropped-deliberate** | — | none | silent | Y | Y | ✓ | xpad: add Elite 2 ID. |
| `43c52e9ef` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Update lg4ff to latest version. Fix broken 32bit rumble/ff ( |
| `43fbb63ae` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | wireless: realtek: fix makefiles. |
| `4ddd8ec3d` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Add xone (XBox wireless adapter) driver. |
| `5391b8171` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Update defconfig. |
| `5a7965488` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | Y | ✓ | xone: fixed rumble. |
| `6c2d53934` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Use 100kHz for i2c-1 for better compatibility with devices. |
| `7436e2d6e` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | mt7601u possible fix? |
| `7828d722e` | v5.15 | **dropped-deliberate** | — | cosmetic | silent | — | ? | ✓ | defconfig: compile 80211 as a module. |
| `7f7148c1f` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | exfat: remove exfat_config.h messing kernel config. |
| `8270e78f4` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | xone: backport the paddles from fork. |
| `858322ce6` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | exfat: fix memory mapped file ops. |
| `8a100f2ed` | v5.15 | **dropped-deliberate** | — | none | silent | Y | Y | ✓ | Update hid-lg4ff.c for Logitech Wheel Support (#32) |
| `8b6b8c2f5` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Remove original exFAT driver. |
| `97a398176` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | Y | ✓ | update config. |
| `993b82e31` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | Update realtek drivers from upstream (#44) |
| `99a2c80d0` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | Y | ✓ | exfat: use ATTR_SYSTEM as symlink flag to preserve links whi |
| `9f59d13d5` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | Y | ✓ | Enable force feedback on PS adapter (#56) |
| `a547c18d0` | v5.15 | **dropped-deliberate** | — | none | silent | — | Y | ✓ | remove unused files. |
| `ae9313e22` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Enable the NFS filesystem in the kernel. (#45) |
| `b2a04cbfd` | v5.15 | **dropped-deliberate** | — | cosmetic | silent | Y | Y | ✓ | vt: reduce from 63 to 9 ttys. |
| `bbeff2c30` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | N | ✓ | Enable Logitech D-Input drivers. |
| `bdedb82d2` | v5.13.12 | **dropped-deliberate** | — | feature-loss | silent | — | ? | ✓ | Add rtl8188eu, rtl8188fu WiFi drivers. |
| `c3c1a0ec9` | v5.14 | **dropped-deliberate** | — | boot-critical | loud | — | Y | ✓ | dwc2: remove original driver. |
| `c708f2222` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | xone: update to latest. |
| `c70a3fc27` | v5.14 | **dropped-deliberate** | — | none | silent | — | ? | ✓ | Add rtl8821au, rtl88x2bu, rtl8821cu WiFi drivers. |
| `d5beb5aa6` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | xone: sysfs for software pairing. |
| `d776ddb4e` | v5.15 | **dropped-deliberate** | — | feature-loss | loud | — | Y | ✓ | xone: use firmware according to PID. |
| `d788e7ab9` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | Update defconfig (enable logitech wheels). |
| `e2eb39e6f` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | Y | ✓ | xone: update driver. |
| `f0fb626ac` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | Y | Y | ✓ | defconfig: enable macvlan support (#71) |
| `fc09a292a` | v5.15 | **dropped-deliberate** | — | feature-loss | silent | — | ? | ✓ | rtl8821cu: workaround for bad efuse in EDUP EP-AC1661. |
| `109599db7` | v5.13.12 | **dropped-obsolete** | — | none | silent | — | Y | ✓ | Update rtl8188eu driver. |
| `115b1d1ae` | v5.15 | **dropped-obsolete** | — | none | silent | — | N | ✓ | Fix for edimax EW-7822ULC BUG #769  (#47) |
| `2371fb1aa` | v5.15 | **dropped-obsolete** | — | feature-loss | silent | — | Y | ✓ | Sync rtl8821au with upstream |
| `38a039bab` | v5.13.12 | **dropped-obsolete** | — | cosmetic | silent | — | N | ✓ | rtl8821au: disable warnings. |
| `5220d6686` | v5.15 | **dropped-obsolete** | — | none | silent | — | Y | ✓ | exfat: cleanup from kernel version conditions. |
| `a95855a70` | v5.14 | **dropped-obsolete** | — | feature-loss | silent | — | ? | ✓ | dwc2: port from socfpga-v4.19. |
| `df35bdb27` | v5.15 | **dropped-obsolete** | — | feature-loss | silent | Y | Y | ✓ | Add exFAT with symlinks support. |
| `ffbb77e46` | v5.13.12 | **dropped-obsolete** | — | feature-loss | silent | Y | ? | ✓ | Replace exFAT with version supporting symlinks. |
