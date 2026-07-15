# Old-branch sweep — commits with no MiSTer-v5.15 equivalent

Generated 2026-07-15 04:27 UTC by `phase0.py` (plan §3.5). Matching: patch-id, then normalized
subject. **Residue commits get Phase 1 analysis as the appendix work list.**

## MiSTer-v5.14 — 61 branch-only commits, 55 matched, 6 residue

### Residue (appendix work list)

- `c70a3fc27` 2021-08-31 Add rtl8821au, rtl88x2bu, rtl8821cu WiFi drivers.
- `0d8641a2b` 2021-08-30 Add rtl8188eu, rtl8188fu WiFi drivers.
- `c3c1a0ec9` 2021-08-31 dwc2: remove original driver.
- `a95855a70` 2021-08-31 dwc2: port from socfpga-v4.19.
- `bbeff2c30` 2021-09-10 Enable Logitech D-Input drivers.
- `346cbf62b` 2021-09-17 defconfig: update.

<details><summary>Matched commits</summary>

- `2b1e3cff3` → `aa8afe109` (patch-id) Add de10-nano DT.
- `4a2d3f061` → `e40563ae1` (patch-id) Support for i2c rtc m41t81.
- `c5c910e43` → `2548c2978` (patch-id) Support for i2c rtc mcp794xx.
- `435489599` → `71c583074` (patch-id) Disable RTC error messages.
- `3fc6e862e` → `3d95de58f` (subject) Support for init loop device.
- `fb6a73527` → `077c2c317` (patch-id) Disable USB overcurrent signaling.
- `2cb5b8e0f` → `6c2d53934` (patch-id) Use 100kHz for i2c-1 for better compatibility with devices.
- `24edd52ad` → `246984fce` (patch-id) Enable SPI on LTC. Use HPS LED for SD card activity.
- `b795ddc23` → `1337de1fd` (patch-id) Switch to i2c-gpio driver for smbus compatibility.
- `456ab291f` → `333d49b95` (patch-id) Implement MiSTer audio driver.
- `e38a8ab18` → `c4d12c768` (patch-id) Enable UART1.
- `72247f550` → `7d2df2d2d` (patch-id) Disable DMA on UART0/1. DMA is broken on Designware UARTs.
- `1f16a1d3d` → `7436e2d6e` (patch-id) mt7601u possible fix?
- `7df8dfc07` → `fc8f3c2c6` (patch-id) Logitech K400r: disable Fn swap.
- `5d249d0fd` → `70e391b81` (patch-id) HID: map key Europe 1(0x32) to F24 code (for Keyrah).
- `8713e1492` → `52a56ae3d` (patch-id) mousedev: disable touch to click on DualShock4 and DualSense.
- `80f8a293c` → `1412bd707` (patch-id) hid-sony: fix divide by 0 exception.
- `b430600b6` → `f84543926` (patch-id) dualsense: add player id led control.
- `cbffa7fa6` → `0d60c3482` (patch-id) dualsense: add lightbar color control.
- `7560f40a7` → `60e08955f` (patch-id) dualsense: give mute button and led to system.
- `a732e41d3` → `b76b4bc6a` (patch-id) dualsense: leds config for player 6.
- `96d2d3ef2` → `c4ec5cb40` (patch-id) Support for Nintendo Switch controller (pro, nes, snes, joycon)
- `c6552dbff` → `9bdab534b` (patch-id) hid-nintendo: use default calibration if empty calibration is loaded.
- `488c75e13` → `60821059c` (patch-id) hid-nintendo: don't fail if home led is not present.
- `f45d4b074` → `45283785a` (patch-id) hid-nintendo: add virtual combo led, don't warn by IMU compensation.
- `3bce1814a` → `0d7778d1f` (patch-id) wiimote: set uniq field.
- `d9c5e788e` → `47dc53a22` (patch-id) wiimote: fix the buttons codes.
- `b3bc22ec8` → `15968bc26` (patch-id) wiimote: fix analog ranges.
- `fbedb7f3d` → `2ac0aa1e8` (patch-id) input: support for mouseX and mice in EVIOCGRAB mode.
- `88f324cf5` → `817ace70b` (patch-id) Remove XBox One Wireless Adapter USB IDs from mt76 driver to allow 'xow' driver compatibility.
- `d4f3bd5a6` → `f0982bf2c` (patch-id) usbhid: apply jspoll for gamepad usage as well.
- `b12438bac` → `f3c75eb02` (patch-id) XInput polling rate param + Qanba Obsidian XInput mode support
- `26cb0ac14` → `b2a04cbfd` (patch-id) vt: reduce from 63 to 9 ttys.
- `722e03aa8` → `d1002ecd4` (patch-id) Implement MiSTer frame buffer device.
- `e26fa487d` → `b62efee23` (patch-id) hps_led: enable brightness change notification.
- `9788649c0` → `c5066763c` (patch-id) Enable i2c2 device.
- `fbb9903b4` → `b02a4a011` (subject) btusb: support for more CSR clones.
- `60e10ce84` → `6827e7644` (patch-id) Support for RTC PCF8563
- `4c03c9bbd` → `071d9092e` (patch-id) dts: fix warnings.
- `5d680c5bb` → `f52690120` (patch-id) dts: enable bridges.
- `18f89a5b1` → `8b6b8c2f5` (patch-id) Remove original exFAT driver.
- `089b705ad` → `df35bdb27` (patch-id) Add exFAT with symlinks support.
- `682979464` → `2d39e76d1` (patch-id) mmc: don't activate LED on status command.
- `523b02e4e` → `552f9f197` (patch-id) hci_conn: prevent call with NULL pointer.
- `4d85eea69` → `e2c082ef9` (patch-id) usb-storage: blacklist Realtek WiFi driver CD-ROM.
- `38ff362a5` → `215e6e662` (subject) Add defconfig.
- `01450528b` → `9a8cb6a93` (patch-id) hid-microsoft: support for XBox Series X/S controller.
- `80f1520f2` → `e155f6a2f` (patch-id) hid-nintendo: support for Switch NES and SNES controllers.
- `39e14593a` → `fc09a292a` (patch-id) rtl8821cu: workaround for bad efuse in EDUP EP-AC1661.
- `2661f047a` → `5bdbf2f7e` (patch-id) hid: add quirk for ControllaBLE.
- `8295b48d0` → `a10f4246f` (patch-id) btusb: add Edimax BT-8500 vid/pid for FW loading.
- `2ed2ea78e` → `858322ce6` (patch-id) exfat: fix memory mapped file ops.
- `e8268e01a` → `5220d6686` (patch-id) exfat: cleanup from kernel version conditions.
- `40bd83017` → `7f7148c1f` (patch-id) exfat: remove exfat_config.h messing kernel config.
- `51b8f693c` → `99a2c80d0` (patch-id) exfat: use ATTR_SYSTEM as symlink flag to preserve links while copying on Windows or other OS.

</details>

## MiSTer-v5.13.12 — 52 branch-only commits, 43 matched, 9 residue

### Residue (appendix work list)

- `a6165424f` 2020-02-14 xinmotek fix (#11)
- `2efa211a2` 2021-08-19 btrtl: add RTL8761B ROMs to list.
- `40120d090` 2021-08-24 drivers: bluetooth: backport some drivers from upstream.
- `3d587b6a3` 2021-08-24 Add rtl8821au, rtl88x2bu, rtl8821cu WiFi drivers. — *also on MiSTer-v5.14 (re-applied there, dropped at v5.15)*
- `ffbb77e46` 2021-08-25 Replace exFAT with version supporting symlinks.
- `bdedb82d2` 2021-08-29 Add rtl8188eu, rtl8188fu WiFi drivers. — *also on MiSTer-v5.14 (re-applied there, dropped at v5.15)*
- `ec75e65f8` 2021-08-29 Revert "xinmotek fix (#11)"
- `109599db7` 2021-08-30 Update rtl8188eu driver.
- `38a039bab` 2021-08-30 rtl8821au: disable warnings.

<details><summary>Matched commits</summary>

- `d601df634` → `aa8afe109` (patch-id) Add de10-nano DT.
- `f7782e6e8` → `e40563ae1` (patch-id) Support for i2c rtc m41t81.
- `59db70c6b` → `2548c2978` (patch-id) Support for i2c rtc mcp794xx.
- `b3fc43b83` → `71c583074` (patch-id) Disable RTC error messages.
- `728599a6f` → `3d95de58f` (subject) Support for init loop device.
- `6b8423c18` → `077c2c317` (patch-id) Disable USB overcurrent signaling.
- `3444398bf` → `6c2d53934` (patch-id) Use 100kHz for i2c-1 for better compatibility with devices.
- `61c16bbbb` → `246984fce` (patch-id) Enable SPI on LTC. Use HPS LED for SD card activity.
- `02c4801a6` → `1337de1fd` (patch-id) Switch to i2c-gpio driver for smbus compatibility.
- `92f904b7f` → `333d49b95` (patch-id) Implement MiSTer audio driver.
- `08267dce0` → `c4d12c768` (patch-id) Enable UART1.
- `a6e947b1c` → `7d2df2d2d` (patch-id) Disable DMA on UART0/1. DMA is broken on Designware UARTs.
- `15e7a0cc3` → `7436e2d6e` (patch-id) mt7601u possible fix?
- `2bfa41bbf` → `fc8f3c2c6` (patch-id) Logitech K400r: disable Fn swap.
- `9051a2241` → `70e391b81` (patch-id) HID: map key Europe 1(0x32) to F24 code (for Keyrah).
- `78a297384` → `52a56ae3d` (patch-id) mousedev: disable touch to click on DualShock4 and DualSense.
- `50b80148e` → `1412bd707` (patch-id) hid-sony: fix divide by 0 exception.
- `4243cdf84` → `f84543926` (patch-id) dualsense: add player id led control.
- `125cdbd23` → `0d60c3482` (patch-id) dualsense: add lightbar color control.
- `774ae18f3` → `60e08955f` (patch-id) dualsense: give mute button and led to system.
- `4ea8b3c6c` → `b76b4bc6a` (patch-id) dualsense: leds config for player 6.
- `bd16e72cf` → `c4ec5cb40` (patch-id) Support for Nintendo Switch controller (pro, nes, snes, joycon)
- `ec3c791c3` → `9bdab534b` (patch-id) hid-nintendo: use default calibration if empty calibration is loaded.
- `1a2c716a7` → `60821059c` (patch-id) hid-nintendo: don't fail if home led is not present.
- `630062aa6` → `45283785a` (patch-id) hid-nintendo: add virtual combo led, don't warn by IMU compensation.
- `11638be32` → `0d7778d1f` (patch-id) wiimote: set uniq field.
- `7e846262d` → `47dc53a22` (patch-id) wiimote: fix the buttons codes.
- `218796716` → `15968bc26` (patch-id) wiimote: fix analog ranges.
- `4874442e9` → `2ac0aa1e8` (patch-id) input: support for mouseX and mice in EVIOCGRAB mode.
- `4adb15a12` → `817ace70b` (patch-id) Remove XBox One Wireless Adapter USB IDs from mt76 driver to allow 'xow' driver compatibility.
- `e8ba6be24` → `f0982bf2c` (patch-id) usbhid: apply jspoll for gamepad usage as well.
- `446efee36` → `f3c75eb02` (patch-id) XInput polling rate param + Qanba Obsidian XInput mode support
- `95c4d0718` → `b2a04cbfd` (patch-id) vt: reduce from 63 to 9 ttys.
- `7ee3c4c41` → `d1002ecd4` (patch-id) Implement MiSTer frame buffer device.
- `763bf8e77` → `b62efee23` (patch-id) hps_led: enable brightness change notification.
- `3b0f6eb17` → `c5066763c` (patch-id) Enable i2c2 device.
- `49986f077` → `b02a4a011` (subject) btusb: support for more CSR clones.
- `58abce53c` → `6827e7644` (patch-id) Support for RTC PCF8563
- `483555193` → `071d9092e` (patch-id) dts: fix warnings.
- `675d67e25` → `f52690120` (patch-id) dts: enable bridges.
- `fb750ebdd` → `215e6e662` (subject) Add defconfig.
- `0f8c59fb7` → `2d39e76d1` (patch-id) mmc: don't activate LED on status command.
- `2fd8d2b56` → `1a1f208fa` (subject) Update defconfig.

</details>
