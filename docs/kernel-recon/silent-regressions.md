# Silent-regression triage — the headline list

Generated 2026-07-15 06:48 UTC. Rows where the functionality is NOT covered in our 6.18 build (misclassified / needs-verification / not-evaluated) and failure is silent. Sorted worst-first. All tier-2 verified.

## `60e08955f` dualsense: give mute button and led to system. — **cosmetic**

- disposition misclassified; coupled: False; interface: BTN_Z evdev key event (gamepad range) + led_classdev sysfs node named "<hdev>:mute"; NEITHER has a dedicated Main_MiSTer consumer
- effect if absent: No functional change for any current MiSTer user (see userspace_coupling — no shipped consumer exists either way). At the kernel-capability level: the DualSense mute button no longer surfaces as a distinguishable BTN_Z evdev event (it becomes fully invisible to userspace, same as vanilla), and the mute LED is no longer exposed as a writable /sys/class/leds/*:mute node. Both remain latent/opt-in capabilities that nothing in Main_MiSTer currently reads or writes.
- hardware: Sony DualSense (PS5 controller)

**Total: 1 candidates** (of which 0 feature-loss).

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
- `45283785a` hid-nintendo: add virtual combo led, don't warn by IMU compe → 0032-hid-nintendo-joycon-combo-led.patch
- `47dc53a22` wiimote: fix the buttons codes. → 0023-hid-wiimote-fixes.patch
- `484f68172` input: Add support for the NSO Famicom controllers (no mic f → 0015-hid-nintendo-nso-famicom.patch
- `52a56ae3d` mousedev: disable touch to click on DualShock4 and DualSense → 0026-input-mousedev-eviocgrab.patch
- `5bdbf2f7e` hid: add quirk for ControllaBLE. → 0018-hid-controllable-quirk.patch
- `6827e7644` Support for RTC PCF8563 → 0004-dts-de10nano-MiSTer.patch
- `70e391b81` HID: map key Europe 1(0x32) to F24 code (for Keyrah). → 0024-hid-input-keyrah-europe1.patch
- `77862a67f` Add support for official gamecube-adapter (#48) → 0014-hid-gamecube-adapter.patch
- `7d2df2d2d` Disable DMA on UART0/1. DMA is broken on Designware UARTs. → 0004-dts-de10nano-MiSTer.patch
- `8179ac736` Add driver for Namco Guncon 3 (#20) → 0011-hid-guncon3.patch
- `817ace70b` Remove XBox One Wireless Adapter USB IDs from mt76 driver to → 0027-mt76x2u-release-xbox-adapter-ids.patch
- `9b9aebfac` hid-guncon3: fix warnings. → 0011-hid-guncon3.patch
- `a2242dd85` xpad: exclude GIP-capable controllers. → 0017-xpad-mister-deltas.patch
- `aa8afe109` Add de10-nano DT. → 0004-dts-de10nano-MiSTer.patch
- `b02a4a011` btusb: support for more CSR clones. → 0036-btusb-csr-clone-lmp-subver-2512.patch
- `b1b168eb6` input: add HID driver to fix Flydigi Vader 4 Pro mapping in  → 0013-hid-flydigi-vader.patch
- `b62efee23` hps_led: enable brightness change notification. → 0029-leds-gpio-brightness-hw-changed.patch
- `b745ce6d9` fix Logitech K400 Plus FN problem (#15) → 0019-hidpp-k400-fn-inversion.patch
- `c035c21c0` xpad: support for extra buttons on Flydigi Vader 3/4/5 Pro i → 0017-xpad-mister-deltas.patch
- `c5066763c` Enable i2c2 device. → 0004-dts-de10nano-MiSTer.patch
- `c784a6856` hid-microsoft: support for XBox Elite 2 paddles. → 0016-hid-microsoft-elite2-paddles.patch
- `d1002ecd4` Implement MiSTer frame buffer device. → 0001-fbdev-add-MiSTer_fb-driver.patch
- `d7adb20b4` Fix for unaligned IN data. (#57) → 0028-dwc2-fix-unaligned-in-split.patch
- `e40563ae1` Support for i2c rtc m41t81. → 0004-dts-de10nano-MiSTer.patch
- `e503d193c` Add driver for Namco GunCon 2 → 0010-hid-guncon2.patch
- `e6df8e30e` Improve clock transition stability and get OSC1 freq from DT → 0003-cpufreq-cyclone5-de10nano-overclock.patch
- `e82a59280` Add Fanatec wheel driver (#24) → 0012-hid-fanatec.patch
- `f0982bf2c` usbhid: apply jspoll for gamepad usage as well. → 0025-usbhid-jspoll-gamepad.patch
- `f3c75eb02` XInput polling rate param + Qanba Obsidian XInput mode suppo → 0017-xpad-mister-deltas.patch
- `f84543926` dualsense: add player id led control. → 0033-hid-playstation-dualsense-player-id-led.patch
- `fc8f3c2c6` Logitech K400r: disable Fn swap. → 0019-hidpp-k400-fn-inversion.patch
