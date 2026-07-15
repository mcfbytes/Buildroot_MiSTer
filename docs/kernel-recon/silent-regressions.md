# Silent-regression triage — the headline list

Generated 2026-07-15 06:06 UTC. Rows where the functionality is NOT covered in our 6.18 build (misclassified / needs-verification / not-evaluated) and failure is silent. Sorted worst-first. All tier-2 verified.

## `45283785a` hid-nintendo: add virtual combo led, don't warn by IMU compensation. — **feature-loss**

- disposition misclassified; coupled: True; interface: /sys/.../leds/<hid-devname>:combo/brightness (LED classdev registered by joycon_leds_create() in the fork commit; name format '%s:combo' with %s = dev_name(&hdev->dev), e.g. '0005:057E:2006.0001:combo')
- effect if absent: Joy-Con L+R combining is completely non-functional (not merely 'auto-detect disabled with manual fallback'). Individual Joy-Cons still work as separate single-stick controllers, but there is no way — automatic or manual — to pair two Joy-Cons into one virtual controller, because Main_MiSTer's ENTIRE pairing handshake (both the write side triggered by a button-combo request, and the read side that recognizes the pair on device rescan) is implemented purely as a read/write of the kernel-side ':combo' LED sysfs node. No alternative/manual pairing UI exists anywhere in Main_MiSTer (grep of menu.cpp/osd.cpp for 'joycon'/'joy-con' returns zero hits; input.cpp sets input[].bind for QUIRK_JOYCON devices at exactly one place, input.cpp:4729-4730, and that code path is unreachable without a valid combo-id readback).
- hardware: Nintendo Joy-Con (L), Nintendo Joy-Con (R)

## `f84543926` dualsense: add player id led control. — **feature-loss**

- disposition misclassified; coupled: True; interface: LED class device `<hid-device-id>:player_id` brightness (0-5). The fork's naming -- devm_kasprintf(dev, "%s:player_id", dev_name(dev)) with dev=&hdev->dev -- exactly matches how Main_MiSTer's get_led_path() constructs its base path (truncates the input device's sysfs path at '/input/', appends '/leds/<hid-device-id>'), i.e. this commit and Main_MiSTer were co-designed around the same naming convention.
- effect if absent: On vanilla 6.18.38, DualSense (054c:0ce6) exposes five separate LED classdevs named `<gamepad-input-dev>:white:player-N` (N=1-5), keyed off the gamepad's INPUT device name, instead of the fork's single `<hid-device-id>:player_id` brightness classdev (0-5) keyed off the HID device. Main_MiSTer/input.cpp:2702 writes only `<led_path>:player_id/brightness` (led_path derived from the HID device id, matching the fork's naming exactly); that open fails with ENOENT on vanilla, so update_num_hw() silently falls into its pre-existing DualShock4 branch (input.cpp:2709-2726) and paints the lightbar's :red/:green/:blue sub-LEDs with the DS4 color_code[] per-player palette instead of the intended blue/green player_id-brightness cue. Simultaneously, vanilla's own driver auto-lights the 5-LED row once at connect via dualsense_set_player_leds(ds) (hid-playstation.c:1865) using an IDA connection-order id -- not a MiSTer-assigned player slot -- and nothing in Main_MiSTer ever touches those 5 LEDs afterward, so the row shows a static, assignment-independent pattern for the life of the connection. Net effect: player identity is still visually conveyed (lightbar color, same mechanism used for plain DualShock4), but the specific PS5-style white player-LED indicator the fork commit and Main_MiSTer were co-designed around is wrong/stale and unreachable from userspace.
- hardware: DualSense (PlayStation 5 controller)

## `b02a4a011` btusb: support for more CSR clones. — **feature-loss**

- disposition needs-verification; coupled: False; interface: None
- effect if absent: A CSR-vendor-ID (0a12) fake dongle that self-reports manufacturer=10, hci_rev==lmp_subver (both 0x2512), and an lmp_subver of 0x2512 is NOT flagged is_fake by any vanilla 6.18.38 branch: it passes the manufacturer/hci_rev-consistency check (because it self-reports consistently), and 0x2512 (9490 decimal) exceeds every ranged check's upper bound, including the top BT4.0 tier <= 0x22bb (8891 decimal) -- so it falls through all six is_fake branches untouched. Result: none of the six CSR-clone quirks (HCI_QUIRK_BROKEN_STORED_LINK_KEY, HCI_QUIRK_BROKEN_ERR_DATA_REPORTING, HCI_QUIRK_BROKEN_FILTER_CLEAR_ALL, HCI_QUIRK_NO_SUSPEND_NOTIFIER, HCI_QUIRK_BROKEN_READ_VOICE_SETTING, HCI_QUIRK_BROKEN_READ_PAGE_SCAN_TYPE) and none of the reset/discovery quirk-clears are applied, AND the Barrot-8041a02 pm_runtime force-suspend/wake bulk-RX workaround is never triggered for this device -- it is treated as a genuine, well-behaved CSR controller. If the real chip is in fact a broken clone, this manifests as controller lockups, broken link-key storage, or a Bluetooth adapter that never receives bulk-RX data (keyboard/mouse HID-over-BT) until manually suspended -- exactly the class of bug upstream is still separately patching for the neighboring bcdDevice=0x8891/0a12:0001 dongle family as late as commit 2c1dda2acc41 (2024-10-16, 'Fix regression with fake CSR controllers 0a12:0001', bug report literally shows bcdDevice=88.91 i.e. 0x8891).
- hardware: CSR-vendor-ID (0a12) fake/clone Bluetooth dongles self-reporting lmp_subver 0x2512

## `fc09a292a` rtl8821cu: workaround for bad efuse in EDUP EP-AC1661. — **feature-loss**

- disposition needs-verification; coupled: False; interface: None
- effect if absent: EFUSE-corrupted rtl8821c-family adapters (map byte at offset 0xCA reads 0xFF/unprogrammed) get efuse->rfe_option = 0xFF & 0x1f = 0x1F in mainline rtw88, which matches none of the explicit switch cases in rtw8821c_read_efuse() (0x2/0x4/0x7/0xa/0xc/0xf) so hal->rfe_btg stays false, get_cck_rx_pwr() falls into the 'else' LNA gain table branch, and rtw8821c_coex_cfg_rfe_type()'s switch on rfe_module_type=0x1F hits whatever its default case is (not individually enumerated here) instead of the correct antenna/RFE-module case. Net effect: silently wrong RX LNA gain table selection and wrong BT-coexistence antenna/RFE-module configuration — degraded RX sensitivity and/or wrong BT-coex antenna switching, NOT a bind/probe failure and NOT boot-critical. The device still binds (its USB ID is in the mainline table) and should still associate to WiFi; the regression is silent RF/coex misconfiguration, not non-functionality.
- hardware: EDUP EP-AC1661 (named in the fork commit message as the motivating device with a known-bad EFUSE batch)

## `97a398176` update config. — **feature-loss**

- disposition not-evaluated; coupled: True; interface: BTN_Z remap for wired/RF XInput-mode Vader controllers (generic BTN_* passthrough for the Bluetooth D-Input HID_VADER4 path)
- effect if absent: CONFIG_HID_VADER4=m enables Flydigi Vader 4 Pro D-Input mode support; CONFIG_JOYSTICK_XPAD=m changes Xbox controller support from built-in to module
- hardware: Flydigi Vader 4 Pro (0xd7d7:0x0041 over Bluetooth), Xbox controllers (various VID:PIDs)

## `f0fb626ac` defconfig: enable macvlan support (#71) — **feature-loss**

- disposition not-evaluated; coupled: True; interface: socket/ioctl (SIOCADDRT, netlink RTM_* messages via libnl); Docker and container runtimes call ip link add type macvlan or use netlink directly
- effect if absent: No MACVLAN virtual network interface support; container networking tools like Docker cannot create multiple virtual MACs on a single interface; network namespace isolation via macvlan is unavailable.
- hardware: —

## `60e08955f` dualsense: give mute button and led to system. — **cosmetic**

- disposition misclassified; coupled: False; interface: BTN_Z evdev key event (gamepad range) + led_classdev sysfs node named "<hdev>:mute"; NEITHER has a dedicated Main_MiSTer consumer
- effect if absent: No functional change for any current MiSTer user (see userspace_coupling — no shipped consumer exists either way). At the kernel-capability level: the DualSense mute button no longer surfaces as a distinguishable BTN_Z evdev event (it becomes fully invisible to userspace, same as vanilla), and the mute LED is no longer exposed as a writable /sys/class/leds/*:mute node. Both remain latent/opt-in capabilities that nothing in Main_MiSTer currently reads or writes.
- hardware: Sony DualSense (PS5 controller)

## `b76b4bc6a` dualsense: leds config for player 6. — **cosmetic**

- disposition misclassified; coupled: False; interface: LED class device `<hid-device-id>:player_id` brightness (fork extends valid range from 0-5 to 0-6 by growing player_ids[] from 6 to 7 elements and raising the clamp from `player_id > 5` to `player_id > 6` / max_brightness from 5 to 6). Kernel-side change only; Main_MiSTer not updated to use player 6.
- effect if absent: Kernel-capability-only: the DualSense LED classdev's 6-element player_ids[] table (index 6 = BIT(4)|BIT(0)) and max_brightness=6 boundary check would not exist, so writing 6 to the `:player_id` LED would be rejected/clamped rather than lighting a 6th-player pattern. Zero user-visible effect today: Main_MiSTer/input.cpp:2702 hardcodes `set_led(led_path, ":player_id", (num > 5) ? 0 : num)`, so it never writes 6 to this LED regardless of whether the kernel would accept it — the earlier num>7 clamp at input.cpp:2695 only bounds the DS4 color_code[] fallback path, not this write. No MiSTer user can reach player slot 6 on a DualSense today, with or without this commit.
- hardware: Sony DualSense (PS5 controller)

## `71c583074` Disable RTC error messages. — **cosmetic**

- disposition needs-verification; coupled: False; interface: None
- effect if absent: Spurious dev_err messages logged to kernel ring buffer on boot when optional RTC add-on board not fitted; no functional impact on boards with RTC hardware present
- hardware: DE10-Nano without optional RTC add-on

**Total: 9 candidates** (of which 6 feature-loss).

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
- `fc8f3c2c6` Logitech K400r: disable Fn swap. → 0019-hidpp-k400-fn-inversion.patch
