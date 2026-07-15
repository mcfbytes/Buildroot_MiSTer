# Tree-diff attribution — fork f0fb626ac vs vanilla v5.15.1

Generated 2026-07-15 04:27 UTC by `phase0.py`. Content comparison via `git ls-tree -r` blob
hashes (content-addressed, valid across repos). Every differing path must be
attributable to ≥1 enumerated delta commit — see plan §3.3.

| Class | Paths |
|---|---|
| added | 3485 |
| modified | 48 |
| deleted | 38 |
| unattributed, gitignored-at-import (benign, see below) | 11 |
| **unattributed, unexplained (must be 0)** | **0** |
| touched-but-reverted (informational) | 149 |

## Gitignored-at-import deletions (benign)

Absent from the fork because git skipped them (kernel's own `.gitignore`)
when the source tarball was `git add`ed. None are part of the kernel build.

- `Documentation/devicetree/bindings/.yamllint` — rule `.gitignore:13:.*`
- `fs/ext4/.kunitconfig` — rule `.gitignore:13:.*`
- `fs/fat/.kunitconfig` — rule `.gitignore:13:.*`
- `lib/kunit/.kunitconfig` — rule `.gitignore:13:.*`
- `tools/perf/include/perf/perf_dlfilter.h` — rule `tools/perf/.gitignore:6:perf`
- `tools/testing/selftests/arm64/tags/.gitignore` — rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/Makefile` — rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/run_tags_test.sh` — rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/tags_test.c` — rule `.gitignore:116:tags`
- `tools/testing/selftests/bpf/test_progs.c` — rule `tools/testing/selftests/bpf/.gitignore:12:/test_progs*`
- `tools/testing/selftests/tc-testing/plugins/__init__.py` — rule `tools/testing/selftests/tc-testing/.gitignore:4:plugins/`

## Attribution table

Out-of-tree directories are collapsed to `dir/**`.

| Path | St | Commits (oldest→newest) |
|---|---|---|
| `Documentation/devicetree/bindings/.yamllint` | D | *(gitignored-at-import)* |
| `arch/arm/boot/dts/Makefile` | M | aa8afe109 |
| `arch/arm/boot/dts/socfpga.dtsi` | M | 6c2d53934 |
| `arch/arm/boot/dts/socfpga_cyclone5_de10_nano.dts` | A | aa8afe109 e40563ae1 2548c2978 077c2c317 246984fce 1337de1fd 333d49b95 c4d12c768 7d2df2d2d d1002ecd4 c5066763c 6827e7644 071d9092e f52690120 |
| `arch/arm/configs/MiSTer_defconfig` | A | 215e6e662 e503d193c 8179ac736 4ddd8ec3d 7828d722e e82a59280 0d7b4fc7e d788e7ab9 3d72b9db7 3740d5b88 ae9313e22 5391b8171 1a1f208fa 316288a3d 77862a67f 9521b003c 9f59d13d5 97a398176 f0fb626ac |
| `drivers/block/loop.c` | M | 3d95de58f |
| `drivers/bluetooth/btusb.c` | M | b02a4a011 a10f4246f 3fb48dc16 |
| `drivers/cpufreq/Kconfig.arm` | M | 3d72b9db7 |
| `drivers/cpufreq/Makefile` | M | 3d72b9db7 |
| `drivers/cpufreq/socfpga-cpufreq.c` | A | 3d72b9db7 e6df8e30e |
| `drivers/hid/Kconfig` | M | c4ec5cb40 e503d193c 8179ac736 4ddd8ec3d e82a59280 77862a67f 9521b003c b1b168eb6 |
| `drivers/hid/Makefile` | M | c4ec5cb40 e503d193c 8179ac736 4ddd8ec3d e82a59280 8908e0fe1 77862a67f 9521b003c b1b168eb6 |
| `drivers/hid/hid-ftec.c` | A | e82a59280 |
| `drivers/hid/hid-ftec.h` | A | e82a59280 |
| `drivers/hid/hid-ftecff.c` | A | e82a59280 ed8f8e6ce |
| `drivers/hid/hid-gamecube-adapter.c` | A | 77862a67f |
| `drivers/hid/hid-google-stadiaff.c` | A | 9521b003c |
| `drivers/hid/hid-guncon2.c` | A | e503d193c |
| `drivers/hid/hid-guncon3.c` | A | 8179ac736 9b9aebfac |
| `drivers/hid/hid-ids.h` | M | c4ec5cb40 9a8cb6a93 e503d193c 8179ac736 adbaaea91 77862a67f 2799f8b94 b00a72159 9521b003c 43c52e9ef |
| `drivers/hid/hid-input.c` | M | 70e391b81 |
| `drivers/hid/hid-lg.c` | M | 43c52e9ef |
| `drivers/hid/hid-lg4ff.c` | M | 8a100f2ed 43c52e9ef |
| `drivers/hid/hid-logitech-hidpp.c` | M | fc8f3c2c6 b745ce6d9 |
| `drivers/hid/hid-microsoft.c` | M | 9a8cb6a93 adbaaea91 c784a6856 |
| `drivers/hid/hid-nintendo.c` | A | c4ec5cb40 9bdab534b 60821059c 45283785a e155f6a2f 2799f8b94 b00a72159 f9c64d8cd 484f68172 |
| `drivers/hid/hid-pl.c` | M | 5bdbf2f7e |
| `drivers/hid/hid-playstation.c` | M | f84543926 0d60c3482 60e08955f b76b4bc6a |
| `drivers/hid/hid-quirks.c` | M | 5bdbf2f7e |
| `drivers/hid/hid-sony.c` | M | 1412bd707 5c410e935 |
| `drivers/hid/hid-vader4.c` | A | b1b168eb6 |
| `drivers/hid/hid-wiimote-core.c` | M | 0d7778d1f |
| `drivers/hid/hid-wiimote-modules.c` | M | 0d7778d1f 47dc53a22 15968bc26 |
| `drivers/hid/usbhid/hid-core.c` | M | f0982bf2c |
| `drivers/hid/xone/**` | A | 4ddd8ec3d 5a7965488 c708f2222 e2eb39e6f 8270e78f4 d776ddb4e d5beb5aa6 |
| `drivers/i2c/busses/i2c-designware-master.c` | M | 71c583074 |
| `drivers/input/input.c` | M | 2ac0aa1e8 |
| `drivers/input/joydev.c` | M | c4ec5cb40 |
| `drivers/input/joystick/xpad.c` | M | f3c75eb02 409f81077 6eec2a515 af27afc4c a2242dd85 c035c21c0 |
| `drivers/input/mousedev.c` | M | 52a56ae3d 2ac0aa1e8 |
| `drivers/leds/leds-gpio.c` | M | b62efee23 |
| `drivers/mmc/core/core.c` | M | 2d39e76d1 |
| `drivers/net/wireless/mediatek/mt76/mt76x2/usb.c` | M | 817ace70b |
| `drivers/net/wireless/mediatek/mt7601u/phy.c` | M | 7436e2d6e |
| `drivers/net/wireless/realtek/Kconfig` | M | 33ff5146a 3740d5b88 |
| `drivers/net/wireless/realtek/Makefile` | M | 33ff5146a 3740d5b88 |
| `drivers/net/wireless/realtek/rtl8188eu/**` | A | 33ff5146a |
| `drivers/net/wireless/realtek/rtl8188fu/**` | A | 33ff5146a |
| `drivers/net/wireless/realtek/rtl8812au/**` | A | 3740d5b88 2371fb1aa 43fbb63ae 993b82e31 115b1d1ae |
| `drivers/net/wireless/realtek/rtl8821au/**` | A | 33ff5146a 3740d5b88 2371fb1aa 43fbb63ae 993b82e31 115b1d1ae |
| `drivers/net/wireless/realtek/rtl8821cu/**` | A | 33ff5146a fc09a292a 3740d5b88 2371fb1aa 43fbb63ae 993b82e31 115b1d1ae |
| `drivers/net/wireless/realtek/rtl88x2bu/**` | A | 33ff5146a 143ce187e 43fbb63ae 993b82e31 115b1d1ae |
| `drivers/rtc/rtc-m41t80.c` | M | 71c583074 |
| `drivers/spi/spidev.c` | M | 246984fce |
| `drivers/usb/dwc2/core.c` | M | 077c2c317 |
| `drivers/usb/dwc2/hcd_intr.c` | M | d7adb20b4 |
| `drivers/usb/storage/usual-tables.c` | M | e2c082ef9 |
| `drivers/video/fbdev/Kconfig` | M | d1002ecd4 |
| `drivers/video/fbdev/Makefile` | M | d1002ecd4 |
| `drivers/video/fbdev/MiSTer_fb.c` | A | d1002ecd4 |
| `fs/exfat/Kconfig` | M | 8b6b8c2f5 df35bdb27 |
| `fs/exfat/Makefile` | M | 8b6b8c2f5 df35bdb27 |
| `fs/exfat/balloc.c` | D | 8b6b8c2f5 |
| `fs/exfat/cache.c` | D | 8b6b8c2f5 |
| `fs/exfat/dir.c` | D | 8b6b8c2f5 |
| `fs/exfat/exfat_api.c` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_api.h` | A | df35bdb27 7f7148c1f 99a2c80d0 |
| `fs/exfat/exfat_bitmap.c` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_bitmap.h` | A | df35bdb27 |
| `fs/exfat/exfat_blkdev.c` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_blkdev.h` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_cache.c` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_cache.h` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_core.c` | A | df35bdb27 5220d6686 7f7148c1f |
| `fs/exfat/exfat_core.h` | A | df35bdb27 5220d6686 7f7148c1f |
| `fs/exfat/exfat_data.c` | A | df35bdb27 5220d6686 7f7148c1f |
| `fs/exfat/exfat_data.h` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_fs.h` | D | 8b6b8c2f5 |
| `fs/exfat/exfat_nls.c` | A | df35bdb27 5220d6686 7f7148c1f |
| `fs/exfat/exfat_nls.h` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_oal.c` | A | df35bdb27 5220d6686 7f7148c1f |
| `fs/exfat/exfat_oal.h` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_raw.h` | D | 8b6b8c2f5 |
| `fs/exfat/exfat_super.c` | A | df35bdb27 858322ce6 5220d6686 7f7148c1f 99a2c80d0 |
| `fs/exfat/exfat_super.h` | A | df35bdb27 5220d6686 7f7148c1f 99a2c80d0 |
| `fs/exfat/exfat_upcase.c` | A | df35bdb27 7f7148c1f |
| `fs/exfat/exfat_version.h` | A | df35bdb27 |
| `fs/exfat/fatent.c` | D | 8b6b8c2f5 |
| `fs/exfat/file.c` | D | 8b6b8c2f5 |
| `fs/exfat/inode.c` | D | 8b6b8c2f5 |
| `fs/exfat/misc.c` | D | 8b6b8c2f5 |
| `fs/exfat/namei.c` | D | 8b6b8c2f5 |
| `fs/exfat/nls.c` | D | 8b6b8c2f5 |
| `fs/exfat/super.c` | D | 8b6b8c2f5 |
| `fs/ext4/.kunitconfig` | D | *(gitignored-at-import)* |
| `fs/fat/.kunitconfig` | D | *(gitignored-at-import)* |
| `include/uapi/linux/input-event-codes.h` | M | af27afc4c |
| `include/uapi/linux/vt.h` | M | b2a04cbfd |
| `init/do_mounts.c` | M | 3d95de58f |
| `lib/kunit/.kunitconfig` | D | *(gitignored-at-import)* |
| `net/bluetooth/hci_conn.c` | M | 552f9f197 |
| `scripts/gdb/linux/__init__.py` | D | a547c18d0 |
| `scripts/gdb/linux/clk.py` | D | a547c18d0 |
| `scripts/gdb/linux/config.py` | D | a547c18d0 |
| `scripts/gdb/linux/cpus.py` | D | a547c18d0 |
| `scripts/gdb/linux/device.py` | D | a547c18d0 |
| `scripts/gdb/linux/dmesg.py` | D | a547c18d0 |
| `scripts/gdb/linux/genpd.py` | D | a547c18d0 |
| `scripts/gdb/linux/lists.py` | D | a547c18d0 |
| `scripts/gdb/linux/modules.py` | D | a547c18d0 |
| `scripts/gdb/linux/proc.py` | D | a547c18d0 |
| `scripts/gdb/linux/rbtree.py` | D | a547c18d0 |
| `scripts/gdb/linux/symbols.py` | D | a547c18d0 |
| `scripts/gdb/linux/tasks.py` | D | a547c18d0 |
| `scripts/gdb/linux/timerlist.py` | D | a547c18d0 |
| `scripts/gdb/linux/utils.py` | D | a547c18d0 |
| `sound/drivers/Kconfig` | M | 333d49b95 |
| `sound/drivers/Makefile` | M | 333d49b95 |
| `sound/drivers/MiSTer-audio-spi.c` | A | 333d49b95 |
| `sound/drivers/dummy.c` | M | 333d49b95 |
| `tools/perf/include/perf/perf_dlfilter.h` | D | *(gitignored-at-import)* |
| `tools/testing/selftests/arm64/tags/.gitignore` | D | *(gitignored-at-import)* |
| `tools/testing/selftests/arm64/tags/Makefile` | D | *(gitignored-at-import)* |
| `tools/testing/selftests/arm64/tags/run_tags_test.sh` | D | *(gitignored-at-import)* |
| `tools/testing/selftests/arm64/tags/tags_test.c` | D | *(gitignored-at-import)* |
| `tools/testing/selftests/bpf/test_progs.c` | D | *(gitignored-at-import)* |
| `tools/testing/selftests/tc-testing/plugins/__init__.py` | D | *(gitignored-at-import)* |

## Touched but reverted to vanilla content (informational)

- `drivers/net/wireless/realtek/rtl8821au/core/rtw_ioctl_rtl.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/core/rtw_mp_ioctl.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8188c2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8188c2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8192d2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8192d2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8192e1Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8192e1Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8192e2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8192e2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723a1Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723a1Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723a2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723a2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723b1Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723b1Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723b2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8723b2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8812a1Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8812a1Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8812a2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8812a2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8821a1Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8821a1Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8821a2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8821a2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8821aCsr2Ant.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtc8821aCsr2Ant.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/HalBtcOutSrc.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC-BTCoexist/Mp_Precomp.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/HalPhyRf.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/HalPhyRf.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/Mp_Precomp.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/PhyDM_Adaptivity.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/PhyDM_Adaptivity.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_ACS.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_ACS.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_AntDect.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_AntDect.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_AntDiv.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_AntDiv.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_CfoTracking.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_CfoTracking.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_DIG.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_DIG.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_DynamicBBPowerSaving.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_DynamicBBPowerSaving.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_DynamicTxPower.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_DynamicTxPower.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_EdcaTurboCheck.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_EdcaTurboCheck.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_HWConfig.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_HWConfig.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_NoiseMonitor.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_NoiseMonitor.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_PathDiv.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_PathDiv.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_PowerTracking.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_PowerTracking.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_RXHP.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_RXHP.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_RaInfo.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_RaInfo.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_RegDefine11AC.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_RegDefine11N.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_debug.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_debug.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_interface.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_interface.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_pre_define.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_precomp.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_reg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/phydm_types.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_BB.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_BB.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_FW.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_FW.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_MAC.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_MAC.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_RF.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalHWImg8812A_RF.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalPhyRf_8812A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/HalPhyRf_8812A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/Mp_Precomp.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/phydm_RTL8812A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/phydm_RTL8812A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/phydm_RegConfig8812A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8812a/phydm_RegConfig8812A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_BB.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_BB.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_FW.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_FW.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_MAC.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_MAC.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_RF.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalHWImg8821A_RF.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalPhyRf_8821A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/HalPhyRf_8821A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/Mp_Precomp.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/PhyDM_IQK_8821A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/PhyDM_IQK_8821A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/phydm_RTL8821A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/phydm_RTL8821A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/phydm_RegConfig8821A.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/OUTSRC/rtl8821a/phydm_RegConfig8821A.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/hal/rtl8812a/rtl8812a_mp.c` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/Hal8192CPhyCfg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/Hal8192CPhyReg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/Hal8192DPhyCfg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/Hal8192DPhyReg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/Hal8723APhyCfg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/Hal8723APhyReg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/mp_custom_oid.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_cmd.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_dm.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_event.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_hal.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_led.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_recv.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_rf.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_spec.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_sreset.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192c_xmit.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_cmd.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_dm.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_hal.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_led.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_recv.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_rf.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_spec.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8192d_xmit.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_cmd.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_dm.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_hal.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_led.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_pg.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_recv.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_rf.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_spec.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_sreset.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtl8723a_xmit.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtw_ioctl_rtl.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtw_mp_ioctl.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821au/include/rtw_wifi_regd.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl8821cu/include/rtw_wifi_regd.h` — 33ff5146a 3740d5b88
- `drivers/net/wireless/realtek/rtl88x2bu/platform/platform_rockchips_sdio.c` — 33ff5146a 143ce187e
- `fs/exfat/exfat_config.h` — df35bdb27 7f7148c1f
