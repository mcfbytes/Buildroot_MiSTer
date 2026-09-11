# Silent-regression triage — the headline list

Generated 2026-09-11 03:36 UTC. Rows where the functionality is NOT covered in our 6.18 build (misclassified / needs-verification / not-evaluated) and failure is silent. Sorted worst-first. All tier-2 verified.

## `c129b0fac` Add AIC8800 WiFi/BT driver. — **feature-loss**

- disposition not-evaluated; coupled: False; interface: None
- effect if absent: A USB dongle built on the AICSemi AIC8800 family (AIC8800 / 8801 / 8800DC / 8800DW / 8800DE / 8800D80 / 8800D80X2 / 8800D80N / 8800DLN / 8800M80 and the Tenda- and TP-Link-branded variants of them) binds no driver at all on our image: mainline 6.18/7.2/7.3-rc has no aic8800 driver over any bus, so there is no fallback. No wlanN appears, no hci for the BT half. Nothing logs an error beyond the usual 'no driver' -- the dongle simply does nothing. NOTE the symmetric fact: on the STOCK image, where the driver IS built (MiSTer_defconfig CONFIG_AIC8800_WLAN_SUPPORT=m + CONFIG_AIC_LOADFW_SUPPORT=m), the dongle also does nothing today, because Release 20260907's firmware.tar.gz ships 0 of the ~60 firmware blobs the driver filp_open()s from /lib/firmware (104 entries, zero aic/fmacfw/fw_patch/fw_adid/8800 matches; sha256 8a6ab6730e5a4b0ee978cae98a15fd8505e5605074cd34018adac0ac43359f78). So absence costs nothing that stock currently delivers.
- hardware: Tenda U2 (2604:0014), Tenda U11 (2604:001f), Tenda U11 Pro (2604:0020), Tenda (2604:0013) -- commodity Wi-Fi 6 USB dongles, Tenda TX1U Nano (3625:0110), TP-Link (2357:014e) and Mercury (2357:014b) AIC8800-based dongles, AICSemi reference/OEM AIC8800 family under VIDs a69c and 368b (chips AIC8800, 8801, 8800DC, 8800DW, 8800DE, 8800D40/D41, 8800D80/D81, 8800D80X2/D81X2/D89X2, 8800D80N/D40N/DLN/DWN, 8800M80 customer variants, 8800FC customer variants)

**Total: 1 candidates** (of which 1 feature-loss).

## Protected (carried) silent-failure items

These WOULD regress silently if their patch were ever dropped — they are carried today:

- `077c2c317` Disable USB overcurrent signaling. → 0004-dts-de10nano-MiSTer.patch
- `0d7778d1f` wiimote: set uniq field. → 0023-hid-wiimote-fixes.patch
- `1337de1fd` Switch to i2c-gpio driver for smbus compatibility. → 0004-dts-de10nano-MiSTer.patch
- `15968bc26` wiimote: fix analog ranges. → 0023-hid-wiimote-fixes.patch
- `246984fce` Enable SPI on LTC. Use HPS LED for SD card activity. → 0004-dts-de10nano-MiSTer.patch
- `2ac0aa1e8` input: support for mouseX and mice in EVIOCGRAB mode. → 0026-input-mousedev-eviocgrab.patch
- `333d49b95` Implement MiSTer audio driver. → 0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch
- `3d72b9db7` Add cpufreq/overclock driver (#34) → 0003-cpufreq-cyclone5-de10nano-overclock.patch
- `41c45f378` Adapt Classic2USB and RetroZord HID force feedback support … → 0048-hid-google-stadiaff-classic2usb-retrozord.patch
- `45283785a` hid-nintendo: add virtual combo led, don't warn by IMU comp… → 0032-hid-nintendo-joycon-combo-led.patch, 0040-hid-nintendo-imu-name-suffix.patch
- `47dc53a22` wiimote: fix the buttons codes. → 0023-hid-wiimote-fixes.patch
- `484f68172` input: Add support for the NSO Famicom controllers (no mic … → 0015-hid-nintendo-nso-famicom.patch
- `52a56ae3d` mousedev: disable touch to click on DualShock4 and DualSens… → 0026-input-mousedev-eviocgrab.patch
- `5bdbf2f7e` hid: add quirk for ControllaBLE. → 0018-hid-controllable-quirk.patch
- `6332499e7` Bluetooth: btusb: add Mercusys 2c4e:0115 support (#78) → 0047-btusb-mercusys-ma530-2c4e-0115.patch
- `6827e7644` Support for RTC PCF8563 → 0004-dts-de10nano-MiSTer.patch
- `70e391b81` HID: map key Europe 1(0x32) to F24 code (for Keyrah). → 0024-hid-input-keyrah-europe1.patch
- `77862a67f` Add support for official gamecube-adapter (#48) → 0014-hid-gamecube-adapter.patch
- `7d2df2d2d` Disable DMA on UART0/1. DMA is broken on Designware UARTs. → 0004-dts-de10nano-MiSTer.patch
- `8179ac736` Add driver for Namco Guncon 3 (#20) → 0011-hid-guncon3.patch
- `817ace70b` Remove XBox One Wireless Adapter USB IDs from mt76 driver t… → 0027-mt76x2u-release-xbox-adapter-ids.patch
- `9b9aebfac` hid-guncon3: fix warnings. → 0011-hid-guncon3.patch
- `a2242dd85` xpad: exclude GIP-capable controllers. → 0017-xpad-mister-deltas.patch
- `aa8afe109` Add de10-nano DT. → 0004-dts-de10nano-MiSTer.patch
- `b00a72159` Add support for NSO Mega Drive Controller (#50) → 0038-hid-nintendo-nso-genesis-bt-pid.patch, 0039-hid-nintendo-nso-n64-genesis-stock-button-mapping.patch
- `b02a4a011` btusb: support for more CSR clones. → 0036-btusb-csr-clone-lmp-subver-2512.patch
- `b1b168eb6` input: add HID driver to fix Flydigi Vader 4 Pro mapping in… → 0013-hid-flydigi-vader.patch
- `b62efee23` hps_led: enable brightness change notification. → 0029-leds-gpio-brightness-hw-changed.patch
- `b745ce6d9` fix Logitech K400 Plus FN problem (#15) → 0019-hidpp-k400-fn-inversion.patch
- `c035c21c0` xpad: support for extra buttons on Flydigi Vader 3/4/5 Pro … → 0017-xpad-mister-deltas.patch
- `c5066763c` Enable i2c2 device. → 0004-dts-de10nano-MiSTer.patch
- `c784a6856` hid-microsoft: support for XBox Elite 2 paddles. → 0016-hid-microsoft-elite2-paddles.patch
- `d1002ecd4` Implement MiSTer frame buffer device. → 0001-fbdev-add-MiSTer_fb-driver.patch
- `d7adb20b4` Fix for unaligned IN data. (#57) → 0028-dwc2-fix-unaligned-in-split.patch
- `e40563ae1` Support for i2c rtc m41t81. → 0004-dts-de10nano-MiSTer.patch
- `e503d193c` Add driver for Namco GunCon 2 → 0010-hid-guncon2.patch
- `e6df8e30e` Improve clock transition stability and get OSC1 freq from D… → 0003-cpufreq-cyclone5-de10nano-overclock.patch
- `e82a59280` Add Fanatec wheel driver (#24) → 0012-hid-fanatec.patch
- `f0982bf2c` usbhid: apply jspoll for gamepad usage as well. → 0025-usbhid-jspoll-gamepad.patch
- `f3c75eb02` XInput polling rate param + Qanba Obsidian XInput mode supp… → 0017-xpad-mister-deltas.patch
- `f84543926` dualsense: add player id led control. → 0033-hid-playstation-dualsense-player-id-led.patch, 0042-hid-playstation-stock-lightbar-led-names.patch
- `fc8f3c2c6` Logitech K400r: disable Fn swap. → 0019-hidpp-k400-fn-inversion.patch
