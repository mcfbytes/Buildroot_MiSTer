# Tree-diff backstop, 2026-09 increment — post-Wave-3 behavioural audit

**Method:** PLAN.md §5.2 Wave 3 tail / `fork-sync-2026-07.md` §3(b) ("every byte of
divergence, not every commit"). Run 2026-09-11 in this session against
`$S/fork-6.18` (`MiSTer-v6.18` @ `c129b0fac34ad5d613bbec3f59d6036775e41c83`, base
`d9ac12a691ead295c8bc6438754767b94c0f26a2` = `v6.18.38`). This is the same backstop that
found the silent NSO-Genesis regression in July; it is run here against the fork's HEAD
**after** this repo's own Wave 3 landed `0048`–`0050`, the `0017` delta-5 fold, the `0004`
OCRAM reservation and the `0001` fb_sys_* alignment, to answer "what remains, and is it
all dispositioned".

## 0. Result in one paragraph

**Yes, with one exception.** Of 58 files with any byte-level difference between our
patched 6.18.38 tree and the fork's HEAD (excluding AIC8800, xone, configs,
Documentation and the fork's standalone DTS, per the method), 53 are comment/brace-style/
patch-decomposition variance with **zero** behavioural effect, 4 clusters are genuinely
behavioural and **all four are already dispositioned** by existing records or docs, and
**one** file (`drivers/video/fbdev/MiSTer_fb.c`) has a small, previously unexamined
behavioural difference — not a regression in what we ship, but a latent robustness bug in
the fork's own driver that no record currently names. See §5 Finding F1. The separate DTS
node-by-node comparison (§4) found nothing new: every divergence is already covered by
`docs/dts-comparison.md`, re-verified here against the current fork HEAD rather than the
5.15-era stock DTB that document was built from.

---

## 1. Method — exact commands run

```bash
S=/tmp/claude-0/.../scratchpad          # session scratchpad, see WAVE3-PREAMBLE.md
mkdir -p $S/wave4-treediff/{his-base,his,ours-on-6.18.38}
cd $S/wave4-treediff

# Step 1: pristine 6.18.38 (fork's own spine point) and the fork's current HEAD.
git -C $S/fork-6.18 archive d9ac12a691ead295c8bc6438754767b94c0f26a2 | tar -x -C his-base
git -C $S/fork-6.18 archive c129b0fac34ad5d613bbec3f59d6036775e41c83 | tar -x -C his

# Step 2: our full 6.18 series onto a second copy of the same pristine base.
cp -a his-base/. ours-on-6.18.38/
for p in board/mister/de10nano/linux-patches/*.patch; do   # 40 files, numeric order
    ( cd ours-on-6.18.38 && patch -p1 -F0 < "$p" )          # see §2 for the fallback ladder
done
find ours-on-6.18.38 -name '*.orig' -delete                # GNU patch 2.7.6's own backup
find ours-on-6.18.38 -name '*.rej'  -delete                # heuristic; none had .rej content

# Step 3: the excluded diff.
diff -ruN \
  -x aic8800 -x xone -x configs -x Documentation \
  -x socfpga_cyclone5_de10_nano.dts \
  ours-on-6.18.38 his > full-diff-raw.txt

# Step 4: the DTS file the method says to compare separately (§4) — read directly,
# no dtc/decompile step (git sources are already text; "decompile-free" per the brief).
```

`-x <name>` excludes by basename at any depth, so `-x configs` also caught
`arch/arm/configs/` (the only `configs/` directory either tree touches) and `-x xone`
caught all 20 `drivers/hid/xone/**` files. Verified by diffing the file list with and
without the narrower exclusion set (`comm -23`) — the only files it removed beyond the
87→58 file count were the two DTS forms, the defconfig, and exactly the 20 xone files, so
nothing else was silently dropped. `scripts/dtc/include-prefixes/arm/intel/socfpga/*`
appeared as 3 apparent extra diffs; these are **not separate files** — that path is a
`120000` symlink to `../../../arch/arm/boot/dts` in both trees (`git ls-tree` confirmed),
and `diff -r` follows matching directory symlinks, so these are the *same* three DTS/DTSI
diffs counted twice. Deduplicated: **55 distinct files** differ, grouped below as 58 diff
sections.

---

## 2. Apply log (step 2) — the full 40-patch 6.18 series onto pristine 6.18.38

Every patch was tried at `patch -p1 -F0` first (real apply, not dry-run); none needed a
fallback to `-F1`/`-F2`/`-F3` and none failed. This includes `0050-exfat-dir-readahead-plug.patch`,
which the preamble flagged as a possible `-F1`/failure risk on 6.18.38 (it was authored/
re-anchored against 6.18.49) — it applied clean with 1 offset hunk.

| # | Patch | Result |
|---|---|---|
| 0001-fbdev-add-MiSTer_fb-driver.patch | -F0 clean, 0 offset hunks |
| 0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch | -F0 clean, 0 offset hunks |
| 0003-cpufreq-cyclone5-de10nano-overclock.patch | -F0 clean, 0 offset hunks |
| 0004-dts-de10nano-MiSTer.patch | -F0 clean, 0 offset hunks |
| 0010-hid-guncon2.patch | -F0 clean, 0 offset hunks |
| 0011-hid-guncon3.patch | -F0 clean, 0 offset hunks |
| 0012-hid-fanatec.patch | -F0 clean, 0 offset hunks |
| 0013-hid-flydigi-vader.patch | -F0 clean, 0 offset hunks |
| 0014-hid-gamecube-adapter.patch | -F0 clean, 0 offset hunks |
| 0015-hid-nintendo-nso-famicom.patch | -F0 clean, 0 offset hunks |
| 0016-hid-microsoft-elite2-paddles.patch | -F0 clean, 0 offset hunks |
| 0017-xpad-mister-deltas.patch | -F0 clean, **15 offset hunks** (largest offset run in the series; no fuzz) |
| 0018-hid-controllable-quirk.patch | -F0 clean, 0 offset hunks |
| 0019-hidpp-k400-fn-inversion.patch | -F0 clean, 0 offset hunks |
| 0020-mmc-no-led-on-send-status.patch | -F0 clean, 0 offset hunks |
| 0022-hid-playstation-ds4-mac-fix.patch | -F0 clean, 0 offset hunks |
| 0023-hid-wiimote-fixes.patch | -F0 clean, 0 offset hunks |
| 0024-hid-input-keyrah-europe1.patch | -F0 clean, 0 offset hunks |
| 0025-usbhid-jspoll-gamepad.patch | -F0 clean, 0 offset hunks |
| 0026-input-mousedev-eviocgrab.patch | -F0 clean, 0 offset hunks |
| 0027-mt76x2u-release-xbox-adapter-ids.patch | -F0 clean, 0 offset hunks |
| 0028-dwc2-fix-unaligned-in-split.patch | -F0 clean, 0 offset hunks |
| 0029-leds-gpio-brightness-hw-changed.patch | -F0 clean, 0 offset hunks |
| 0030-i2c-designware-quiet-timeout.patch | -F0 clean, 0 offset hunks |
| 0031-exfat-samsung-symlinks.patch | -F0 clean, 0 offset hunks |
| 0032-hid-nintendo-joycon-combo-led.patch | -F0 clean, 0 offset hunks |
| 0033-hid-playstation-dualsense-player-id-led.patch | -F0 clean, 0 offset hunks |
| 0034-hid-nintendo-nes-famicom-stock-ab-mapping.patch | -F0 clean, 0 offset hunks |
| 0035-hid-nintendo-home-led-nonfatal.patch | -F0 clean, 0 offset hunks |
| 0036-btusb-csr-clone-lmp-subver-2512.patch | -F0 clean, 0 offset hunks |
| 0037-hid-playstation-dualsense-mute-btn-z.patch | -F0 clean, 0 offset hunks |
| 0038-hid-nintendo-nso-genesis-bt-pid.patch | -F0 clean, 0 offset hunks |
| 0039-hid-nintendo-nso-n64-genesis-stock-button-mapping.patch | -F0 clean, 0 offset hunks |
| 0040-hid-nintendo-imu-name-suffix.patch | -F0 clean, 0 offset hunks |
| 0041-hid-nintendo-stock-led-classdev-names.patch | -F0 clean, 0 offset hunks |
| 0042-hid-playstation-stock-lightbar-led-names.patch | -F0 clean, 0 offset hunks |
| 0047-btusb-mercusys-ma530-2c4e-0115.patch | -F0 clean, 1 offset hunk |
| 0048-hid-google-stadiaff-classic2usb-retrozord.patch | -F0 clean, 0 offset hunks |
| 0049-hid-nintendo-8bitdo-adapter-skip-baudrate.patch | -F0 clean, 0 offset hunks |
| 0050-exfat-dir-readahead-plug.patch | -F0 clean, **1 offset hunk** (preamble flagged this as a possible -F1/fail risk on 6.18.38 — it was not needed) |

**40/40 applied, 0 failures, 0 fuzz.** A stray artifact: GNU patch 2.7.6 wrote `.orig`
backups for exactly the three files touched by more than one patch each with any offset
(`fs/exfat/dir.c`, `drivers/bluetooth/btusb.c`, `drivers/input/joystick/xpad.c`) — this is
patch's own "backup on non-exact match" heuristic, not a content problem; spot-checked
(`blk_start_plug`, `skip_8bitdo_init`, the `0x2512` check all present and correct) and the
`.orig`/`.rej` files were deleted before diffing so they do not appear in §3/§4.

---

## 3. Classified hunk table — 58 diff sections (55 distinct files)

**(a) = comment/style/decomposition only, or independently-organized code with verified
identical behaviour. (b) = genuinely behavioural, already dispositioned unless marked
FINDING.**

| File | Class | What differs | Disposition |
|---|---|---|---|
| `arch/arm/boot/dts/intel/socfpga/Makefile` | (a) | adds `socfpga_cyclone5_de10_nano.dtb` build target (his own DTS filename) | DTS packaging, `kernel-export.md` §1.2 row 3 |
| `arch/arm/boot/dts/intel/socfpga/socfpga.dtsi` | (a) | `i2c1 clock-frequency=<100000>` present in his, absent in ours | `fork-sync-2026-07.md` §3 — `i2c1` is `disabled`, property never read |
| `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts` (vanilla-named) | (a) structural | his leaves this file vanilla; all MiSTer content lives in his separate underscore file instead | DTS packaging, `kernel-export.md` §1.2 row 3 — **see §4, this is NOT the file that ships** |
| `arch/arm/configs/MiSTer_defconfig` | excluded | per method | — |
| `drivers/block/loop.c` | (a) | ours exports `loop_max_part()`/keeps `loop_set_backing_fd()`; his dropped both | `fork-sync-2026-07.md` §3 "ours-only… nothing to sync" |
| `drivers/bluetooth/btusb.c` | (a) | his adds a `bt_dev_err()` diagnostic dump we don't have | `fork-sync-2026-07.md` §3 "non-substantive" |
| `drivers/clk/socfpga/{Makefile,clk-mister-cpu.c,clk-mister-ocram.{S,h},clk-periph.c,clk-pll.c,clk.h}` | (b) | fork's CCF-integrated OCRAM-resident cpufreq clock provider (#85) | **Q4, dropped-deliberate**, record `59bcae8eb…`, `memo-Q4-cpufreq.md`, owner decision **D1 = A** (keep `0003`) |
| `drivers/cpufreq/{Kconfig.arm,Makefile,socfpga-cpufreq.c}` | (b) | same — fork's driver is `=m`, boost-gated, different Kconfig help text | same as above; boost-sysfs contract difference already corrected in `docs/abi-contract.md` (STATUS §2.2) |
| `drivers/hid/Kconfig`, `drivers/hid/Makefile` | (a) structural | `source "drivers/hid/xone/Kconfig"` / `obj-$(CONFIG_JOYSTICK_XONE) += xone/` — his vendors xone in-tree, we ship it as `package/xone` | `kernel-export.md` §1.2 row 6, ADR 0016 |
| `drivers/hid/hid-ftec.c`, `hid-ftec.h`, `hid-ftecff.c`, `hid-guncon2.c`, `hid-guncon3.c` | (a) | two independent forward-ports of the same third-party vendor drivers (gotzl hid-fanatecff, guncon2/3 projects); brace style (K&R vs Allman), `printk`/`pr_*`, tabs vs spaces, minor error-handling variance (ours adds `kzalloc`-NULL guards his lacks; ours declares `ftecff_send_cmd`/`ftecff_update_slot` prototypes in the header, avoiding `-Wmissing-prototypes`, his does not) | Same bucket as `fork-sync-2026-07.md` §3's general finding ("two independent ports… differing comment wording, brace style, decomposition"), now confirmed to extend to these four files too; no user-visible behaviour difference — same USB IDs, same protocol math, same DEVICE_ATTR set |
| `drivers/hid/hid-nintendo.c` | (b) | NSO Genesis BT PID, N64/Genesis stock button maps, IMU name suffix, stock LED classdev names, home-LED non-fatal | **0038–0042**, records `b00a72159…` (0038+0039), `45283785a…` (0032+0040), `60821059c…` (0035+0041) — all `carried` |
| `drivers/hid/hid-nintendo.c` — famicom d-pad | (a), **was (b), now converged** | fork-sync-2026-07 recorded "we call `joycon_report_dpad`/`joycon_config_dpad` for famicom, upstream's 6.18 does not" — **stale**: at `c129b0fac`, his `joycon_type_is_any_nescon()` now folds in `joycon_type_is_left_famicom()` (his own comment: "FAMIL (left) is wired into `joycon_type_is_any_nescon()`"), so both trees call the d-pad helpers for famicom controllers today. No behaviour delta remains; flagging only so §4.3 of PLAN.md is not read as still-current on this one sub-item |
| `drivers/hid/hid-playstation.c` | (b) | DualSense player-ID LED (`led_classdev` vs the removed IDA scheme), lightbar RGB LED naming, BTN_Z scope | **0033/0042**, record `f84543926…`; BTN_Z — `fork-sync-2026-07.md` §3, record `60e08955f…` (origin of `0037`) — ours scopes `BTN_Z` to DualSense only (matches stock 5.15); his declares it in the shared table so DualShock4 gets it too (his diverges from stock, not us) |
| `drivers/hid/hid-logitech-hidpp.c` | (a) | `k400_enable_fn`→`k400_enable_Fn`, `fn_feature_index`→`feature_index` — renames only | `0019`, same semantics |
| `drivers/hid/hid-microsoft.c` | (a) | brace-only, zero real-content hunks | `0016`, no-op |
| `drivers/hid/hid-vader4.c` | (a) | brace style only | `0013`, no-op |
| `drivers/hid/hid-gamecube-adapter.c` | (a) | comment style (`/* */` vs `//`, identical values 45/215); `cancel_work_sync` loop extracted to a shared helper called from two sites in his vs. inlined twice in ours — same net effect | `0014`, no-op |
| `drivers/hid/hid-pl.c`, `drivers/hid/usbhid/hid-core.c` | (a) | trailing-whitespace-only (identical token text after `-w`) | `0018`/`0025`, no-op |
| `drivers/i2c/busses/i2c-designware-master.c` | (a) | our explanatory comment removed; `dev_dbg()` call itself byte-identical | `0030`, PLAN §3 explicit row |
| `drivers/input/joystick/xpad.c` | (a) | brace/printk style; `int`→`unsigned int interval`; his adds a redundant `if (xpad->flydigi_irq_in)` guard before a `->pipe=` assignment that an earlier `if (!xpad->flydigi_irq_in) goto/return` already makes unreachable-NULL in both trees; ours documents and fixes a real `strstr(udev->product…)` NULL-deref his lacks (Wave-5 candidate, not a delta needing action here) | `0017` + Q5 fold, record `7c75b1b46…` |
| `drivers/input/mousedev.c`, `drivers/input/input.c`, `include/linux/input.h` | (a) structural | two independently-organized implementations of the same EVIOCGRAB-under-grab fix: ours adds `struct input_handler.ignore_grab` (core-level bypass) + per-client grab in mousedev; his exempts mousedev from the core grab check directly and reaches the same per-client grab via `mousedev_do_ioctl`/`_ioctl`/`_ioctl_compat`. Same end behaviour: `/dev/input/mouseX` and `/dev/input/mice` keep working under an evdev `EVIOCGRAB`, and mousedev has its own independent per-client grab either way | `0026`, record `2ac0aa1e8…` |
| `drivers/leds/leds-gpio.c` | (a) | comment removed only | `0029`, PLAN §3 explicit row |
| `drivers/mmc/core/core.c` | (a) | comment removed only; `led_trigger_event()` call byte-identical | `0020`, PLAN §3 explicit row |
| `drivers/net/wireless/mediatek/mt76/mt76x2/usb.c` | (a) | comment removed only | `0027`, no-op |
| `drivers/net/wireless/{Kconfig,Makefile}` | (b) | `source drivers/net/wireless/aic8800/Kconfig` / `obj-$(CONFIG_AIC8800) += aic8800/` | **Q9, not-evaluated/deferred**, `memo-Q9-aic8800.md`, owner decision **D2 = defer**; the driver tree itself is excluded from this diff per method |
| `drivers/spi/spidev.c` | (b) | his `spidev_of_check`/`{ .compatible = "altspi" }` entry | record `246984fce…`, `carried`-for-the-fork/dropped-for-us — our DTS targets `rohm,dh2228fv`, which mainline spidev already accepts |
| `drivers/usb/dwc2/hcd_intr.c` | (a) | comment removed only | `0028`, PLAN §3 explicit row |
| `drivers/video/fbdev/Kconfig` | (a) | his drops `depends on OF` from `FB_MISTER` — inert, the DE10-Nano SoC always has `OF` set (device-tree platform) | — |
| `drivers/video/fbdev/MiSTer_fb.c` | (a) + **(b) FINDING** | fb_ops now aligned (D4, Wave 3) — (a); `info->flags = 0` explicit-vs-implicit-zero — (a); **probe error-check idiom mismatch — see §5 F1** | (a) parts: record `ea2212221…`; F1 part: **no existing record** |
| `fs/exfat/{namei.c,exfat_fs.h,file.c,inode.c,dir.c,exfat_raw.h}` | (b) | independently-reimplemented Samsung-style symlink support on mainline-based exfat: ours keeps a dedicated `TYPE_SYMLINK` + `exfat_symlink_inode_operations`; his folds symlink-ness into `TYPE_FILE` + an `attr`-bit helper `exfat_attr_is_symlink()` + generic `page_symlink_inode_operations`, and adds an `exfat_cleanup_symlink()` helper. **On-disk format verified identical**: both define `EXFAT_ATTR_SYMLINK = EXFAT_ATTR_SYSTEM` and `EXFAT_ATTR_SYMLINK_OLD = 0x0040` and both treat either bit as marking a symlink on read, so cards are interchangeable either direction | `docs/patch-provenance.md` N1, ADR 0019, record `df35bdb27…` (origin of `0031`) |
| `include/uapi/linux/vt.h` | (b) | his `MAX_NR_CONSOLES 63→9` | record `b2a04cbfd…`, `dropped-deliberate` — Main_MiSTer never references the constant, vanilla's 63 is zero-risk |
| `init/do_mounts.c` | (b) structural | his `loop=` boot parameter (root_mountflags gains `MS_NOATIME\|MS_NODIRATIME`, plus `m_open`/`loop_setup`) — this is how every *other* stock MiSTer boots | **Fully dispositioned by design, not a gap**: `board/mister/de10nano/linux-patches-upstream/0100-init-support-for-init-loop-device.patch` (exported-tree-only, origin `3d95de58f…`, record `3d95de58f0334ffba30f7b81d88fbf5f2378f255.json`, `carried-upstream-only`); our image boots via a real initramfs `/init` instead (`linux-patches-upstream/README.md`, `linux-patches-upstream/not-in-image`) |
| `sound/drivers/{MiSTer-audio-spi.c,dummy.c,Kconfig}` | (a) | comment removal, `dev_t major` vs `int major` (both -1 sentinel, same width in practice on this arch), `IS_ERR()` vs `== NULL` idiom swaps that are each correctly paired with their own allocator's contract | `0002`, no-op |
| `scripts/dtc/include-prefixes/arm/intel/socfpga/{Makefile,socfpga.dtsi,socfpga_cyclone5_de10nano.dts}` | dedup | symlink-reached duplicates of the three `arch/arm/boot/dts/…` entries above (`scripts/dtc/include-prefixes/arm` is a `120000` symlink in both trees) | same as the entries above |

**Excluded from this table entirely, per method:** `drivers/net/wireless/aic8800/**` (143
files), `drivers/hid/xone/**` (20 files), `arch/arm/configs/MiSTer_defconfig`,
`Documentation/**` (none differed anyway), `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts`
(compared separately, §4).

**Tally: 53 sections (a), 5 sections/clusters (b)** — cpufreq/clk (7 files, one decision),
hid-nintendo.c, hid-playstation.c, spidev.c+vt.h (paired stock-vs-fork DTS items),
exfat symlink cluster, AIC8800 Kconfig/Makefile, init/do_mounts.c. All dispositioned
**except MiSTer_fb.c's F1**, detailed in §5.

---

## 4. The DTS structural comparison (separate, decompile-free, node-by-node)

Per the method, `his`'s **actual shipped** DTS — `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts`
(underscore; `kernel-export.md` §1.2 row 3: "the shipped 20260907 DTB is that file") — was
read directly and compared node-by-node against our patched
`arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts` (no underscore, the file
our `0004` patches). The vanilla-named file in his tree (§3 above) is **not** what stock
boots and was not used for this comparison.

| Node/property | Ours | His (shipped) | Verdict |
|---|---|---|---|
| `model` | `"Terasic DE10-Nano"` | `"Terasic DE10-nano"` | cosmetic string only; `docs/dts-comparison.md` D13 |
| `compatible` | `"terasic,de10-nano","altr,socfpga-cyclone5","altr,socfpga"` | identical | match |
| `memory` | `memory@0 { reg=<0 0x40000000>; }` | `memory { name="memory"; reg=<0 0x40000000>; }` | same 1 GiB region; unit-address/legacy-`name` cosmetics only |
| `aliases.ethernet0` | `&gmac1` | `&gmac1` | match (load-bearing for U-Boot's MAC injection — identical) |
| `regulator_3_3v` | full node | identical | match |
| `leds.hps0` | `gpios=<&portb 24 GPIO_ACTIVE_HIGH>` | `gpios=<&portb 24 0>` | `GPIO_ACTIVE_HIGH` **is** `0` — identical after macro expansion |
| `i2c_gpio` + 3 RTC children | `rtc@51/68/6f`, vendor-prefixed compatibles (`nxp,pcf8563` etc.) | `rtc_at_51/68/6F`, bare compatibles (`pcf8563` etc.) | **Verified functionally identical**: `i2c_device_match()` (`drivers/i2c/i2c-core-base.c`) tries `of_match_table` first, then falls back to `i2c_match_id()` against `client->name`, which `of_i2c_get_board_info()` sets from the compatible string with any vendor prefix stripped at the first comma — a bare, comma-less compatible like his becomes `client->name` verbatim and matches the driver's legacy (non-OF) `i2c_device_id` table directly. Confirmed against `rtc-pcf8563.c`, `rtc-m41t80.c`, `rtc-ds1307.c`: all three list the bare name in `i2c_device_id` and the vendor-prefixed form in `of_device_id`. `docs/dts-comparison.md` D2 |
| `MiSTer_fb` node | `MiSTer_fb@22000000 { …; interrupts=<0 40 IRQ_TYPE_EDGE_RISING>; }` | `MiSTer_fb { …; interrupts=<0 40 1>; }` | `IRQ_TYPE_EDGE_RISING` is `1` — identical; node name is cosmetic (driver matches on `compatible`, not name, per our own comment) |
| `&gmac1` | `phy-mode="rgmii"`, full skew set (txd0-3=0, rxd0-3=420, txen=0, txc=1860, rxdv=420, rxc=1680), `max-frame-size=3800` | identical values | match — **note**: the *other* (vanilla-named, non-shipping) file in his tree has different, incomplete skew values; that file is not what boots (§3) |
| `&gpio0/1/2` | `status="okay"` | identical | match |
| `&i2c0` | `clock-frequency=<100000>`; `accelerometer@53` `interrupts=<3 IRQ_TYPE_LEVEL_HIGH>` + `interrupt-names="INT1"` | `speed-mode=<0>`; `adxl345@53` `interrupts=<3 2>` (no `interrupt-names`) | `docs/dts-comparison.md` D3 (`speed-mode` is a dead property, zero driver reads it, clock comes from `clock-frequency`) and D7 (the accelerometer node is inert on both — `CONFIG_ADXL345`/`CONFIG_IIO` unset in `linux.config`, no driver binds, and this is an i²c *client* node so it cannot affect the adapter itself) |
| `&i2c2` | `clock-frequency=<100000>` | `clock-frequency=<100000>`, `speed-mode=<0>` | same D3 reasoning — dead property |
| `&spi0`/`spiusb@0` | `status="okay"`, `MiSTer,spi-audio`, 10 MHz | `timeouts=<3>` (his) — `docs/dts-comparison.md` D4, zero driver reads `"timeouts"` | match |
| `&spi1`/spidev child | `spidev@0`, `"rohm,dh2228fv"` | `spibri@0`, `"altspi"` | `docs/dts-comparison.md` D15, record `246984fce…` |
| `&mmc0` | `vmmc-supply`, `vqmmc-supply`, `status="okay"` | identical | match |
| `&uart0`/`&uart1` | `/delete-property/ dmas`, `/delete-property/ dma-names` | identical | match; `clock-frequency=<100000000>` is a documented no-op (D14, `dw8250_probe()` overwrites it from the `clocks` phandle either way) |
| `&usb1` | `dr_mode="host"`, `disable-over-current`, `status="okay"` | identical | match |
| `&fpga_bridge{0,1,2}` | `status="okay"` | identical | match |
| `&ocram` / `flags-sram@f000` | `reg=<0xf000 0x1000>` (carried into `0004` by Wave 3, STATUS §2.3) | `reg=<0xf000 0x1000>` | match |

**No DTS-level finding.** Every divergence is a cosmetic string/macro-expansion identity,
a dead property, or an already-dispositioned deliberate difference (`altspi`). The
`docs/dts-comparison.md` document itself is dated (measured against the 5.15-era stock
DTB, per its own banner and PLAN §9.1/§9.2) but every specific value it cites for these
nodes was independently re-confirmed here against the current fork HEAD's actual shipped
source, so its conclusions transfer forward without needing a re-run for this set of nodes.

---

## 5. Findings

### F1 — `MiSTer_fb.c` probe: stock's error-check idiom doesn't match its own allocator (new, undispositioned)

**Not a delta in what we ship** — our code is correct. It is a latent bug in the fork's
(and therefore stock's) driver that no existing record examines, because record
`ea2212221…` (Q3) scoped its analysis to the `fb_ops` read/write/mmap selection only (a
5-line commit) and explicitly quoted *our own* `memremap()` call as the shared baseline
without checking whether his independently-forward-ported driver still calls the same
allocator the same way.

Both trees call the identical allocator:
```c
fbdev->fb_base = memremap(fbdev->fb_res->start, resource_size(fbdev->fb_res), MEMREMAP_WT);
```
Ours then checks it correctly for `memremap()`'s actual contract (`memremap()` returns
`NULL` on failure — `include/linux/io.h:158`, plain `void *`, not `void __iomem *`, no
`ERR_PTR` anywhere in its implementation):
```c
if (!fbdev->fb_base) { dev_err(&pdev->dev, "memremap fb failed\n"); return -ENOMEM; }
```
His checks it with the wrong idiom, and the error message names a function that is not
actually being called:
```c
if (IS_ERR(fbdev->fb_base)) { dev_err(&pdev->dev, "devm_ioremap_resource fb failed\n"); return PTR_ERR(fbdev->fb_base); }
```
`IS_ERR(NULL)` is `false` (`IS_ERR` only recognizes the small negative range `[-4095,-1]`
encoded as a pointer; `NULL` is `0`, outside that range) and `PTR_ERR(NULL)` is `0`. So on
an actual `memremap()` failure, his `probe()` would **not** detect it, would return `0`
(success) from a failed probe, and `fbdev->fb_base` would be left `NULL` for the driver's
later dereferences (`info->pseudo_palette = fbdev->fb_base`, `fbdev->info.screen_base =
fbdev->fb_base+4096`, the `memset()` at close) — a `NULL`-pointer read/write instead of a
clean probe failure with a correct log line.

**Severity: low in practice.** The DE10-Nano's FPGA framebuffer window is a fixed
reserved-memory region asserted by the DTB; `memremap()` failing there at all would be
exceptional (OOM of the low-memory mapping space, or a misconfigured `reg`), so this is a
dead-in-normal-operation error path, not a live regression. It looks like a leftover from
an abandoned refactor toward `devm_ioremap_resource()` (the error string is exactly that
function's own log message) that changed the check and the message but not the actual
call.

**Disposition proposed here:** no action needed on our side (we are already correct and
match `memremap()`'s real contract — closer to correct behaviour than his own tree, not
just closer to any particular stock generation). Candidate for a two-line Wave 5 PR to the
fork (`if (!fbdev->fb_base)` + fix the log string) — trivial, low-risk, good-faith. No
record currently names this; recommend a short addendum to record `ea2212221…`'s `notes`
(scope correction: "this record's equivalence analysis covers only the `fb_ops` hunk; the
`fb_base` allocation/error-check code is unchanged by commit `ea2212221` and was not
compared to his's independently-forward-ported version — see tree-diff-2026-09.md F1")
rather than a new record, since there is no origin commit on `MiSTer-v6.18` this delta
traces to (it predates the whole 2026-09 queue).

**No other findings.** Every other behavioural cluster in §3 and every DTS divergence in
§4 already has a citable disposition.

---

## 6. Wave 5 input — features our kernel has that his branch lacks

| Feature | Our patch(es) | Files/functions | Restores stock 5.15? | Main_MiSTer coupling | Re-anchor effort onto `c129b0fac` |
|---|---|---|---|---|---|
| NSO Genesis BT PID | `0038` | `hid-nintendo.c`, `USB_DEVICE_ID_NINTENDO_GENCON`/`hdev->product` match | **Yes** — restores stock 5.15 (record `b00a72159…`) | High — Main_MiSTer's controller-detection path keys on this | Low: single self-contained hunk, no dependency on other missing patches |
| N64/Genesis stock button mapping | `0039` | `hid-nintendo.c` `gencon_button_mappings[]`, `n64con_button_mappings[]` | **Yes** — matches stock's wire-to-evdev table, not mainline's remap (record `b00a72159…`) | High — gamecontrollerdb `bN` ordinals and `.map` files assume stock's codes | Low-medium: two static tables, straightforward to re-anchor, but must be re-verified against whatever his port's tables look like at merge time (his currently uses mainline's remap) |
| IMU name suffix | `0040` | `hid-nintendo.c`, `"%s IMU"` vs `"%s (IMU)"` | Yes (record `45283785a…`) | Low-medium — cosmetic sysfs/libevdev name string | Trivial |
| Stock LED classdev names | `0041` | `hid-nintendo.c` home/combo LED naming | Yes (record `60821059c…`) | Medium — LED sysfs paths some community scripts reference | Trivial |
| Stock lightbar LED names | `0042` | `hid-playstation.c` DualSense lightbar `led_classdev` names | Yes (record `f84543926…`) | Medium — same class | Trivial |
| `BTN_Z` scoped to DualSense only | `0037` | `hid-playstation.c` `ps_gamepad_buttons[]`/`ps_gamepad_create()` callers | Yes — stock 5.15 has exactly one caller (DualSense); his's shared-table form also gives DualShock4 `BTN_Z`, which stock never did | Low | Trivial — one-line scope change, already isolated in his's code as a single shared-vs-split table decision |
| Home-LED registration failure non-fatal | `0035` | `hid-nintendo.c` `joycon_leds_create()` | Yes (record `60821059c…`) | Low | Trivial |
| DS4 3rd-party clone pairing-info non-fatal | `0022` | `hid-playstation.c` DualShock4 probe | Yes (predates this increment) | Medium — cheap DS4 clones over wire | Already present in his in equivalent form (`hid_err`+`ret=0`, same MiSTer-authored comment carried forward) — **not actually a gap**, listed for completeness only |
| `MiSTer_fb.c` probe error-check correctness | n/a (baseline `0001`) | `drivers/video/fbdev/MiSTer_fb.c` `probe()` | N/A — not a stock-5.15 restoration, a bug-fix-quality improvement (F1) | None (kernel-internal robustness only) | Trivial — 2-line fix, good-faith upstream PR |
| exFAT Samsung-symlink on-disk compatibility notes | `0031` (already carried both directions) | `fs/exfat/*` | On-disk format parity, not a missing feature — both trees support symlinks; listed only because the *internal* implementations differ enough that a future exfat refactor on either side should re-check bit-compatibility (see §3 table) | Low (filesystem-transparent) | N/A — not a gap, a maintenance note |

**Strong cases** (restore documented stock-5.15 behaviour, Main_MiSTer-coupled):
`0038`, `0039`, `0037`. **Weaker/cosmetic cases**: `0040`, `0041`, `0042` (naming only, no
functional difference, but community scripts/LED paths may depend on the names). **Not
really gaps**: DS4 pairing-info fix (his already has it) and the exfat/`0022` rows, kept
in the table for completeness per the task's request but should not be read as open work.

## 7. Reverse table — features his branch has that ours lacks

| Feature | His commit/code | Dispositioned? | Disposition |
|---|---|---|---|
| CCF-integrated, OCRAM-resident cpufreq driver with `stop_machine` PLL retune | `59bcae8eb` (#85) | **Yes** | Q4, `memo-Q4-cpufreq.md`, owner decision D1 = A (keep `0003`); OCRAM `flags-sram` reservation carried into `0004` regardless (STATUS §2.3) |
| AIC8800 Wi-Fi/BT vendored driver | `c129b0fac` | **Yes** | Q9, `memo-Q9-aic8800.md`, owner decision D2 = defer (no redistributable firmware source identified, no SPDX headers) |
| `loop=` boot parameter + `MS_NOATIME\|MS_NODIRATIME` | `3d95de58f` (`init/do_mounts.c`) | **Yes** | `board/mister/de10nano/linux-patches-upstream/0100-init-support-for-init-loop-device.patch`, record `3d95de58f…`, `carried-upstream-only` — deliberately not in our image (initramfs `/init` instead) |
| xpad `skip_8bitdo_init` opt-in bypass | `7c75b1b46` (Q5) | **Yes — we carry it too** | folded into `0017` delta 5, record `7c75b1b46…` — not actually a gap |
| PR #92 8BitDo adapter fix (hid-nintendo) | `a14b5e8e1c` | **Yes — we carry it too** | `0049`, record `a14b5e8e1c…` — not actually a gap |
| exFAT dir read-ahead plug | `9854075c8` (#88) | **Yes — we carry it too** | `0050`, record `9854075c8…` — not actually a gap |
| Stadia-FF Classic2USB/RetroZord IDs | `41c45f378` (#91) | **Yes — we carry it too** | `0048`, record `41c45f378…` — not actually a gap |
| `BTN_Z` on DualShock4 (in addition to DualSense) | shared-table form in `hid-playstation.c` | **Yes** | `fork-sync-2026-07.md` §3 — this is *his* divergence from stock 5.15, not a gap in ours; ours matches stock |
| `spidev` `altspi` compatible | `drivers/spi/spidev.c` | **Yes** | record `246984fce…`, dropped-deliberate — our DTS uses `rohm,dh2228fv` instead, which needs no driver patch |
| `vt.h` `MAX_NR_CONSOLES` 63→9 | `include/uapi/linux/vt.h` | **Yes** | record `b2a04cbfd…`, dropped-deliberate |
| NSO right-Famicom d-pad support | `hid-nintendo.c`, `joycon_type_is_any_nescon()` now includes famicom | **Yes, and stale in the other direction** | Not a current gap at all — see the "famicom d-pad" row in §3: his caught up to ours independently between July and this run; both trees behave the same today |
| Fanatec/Guncon driver error-handling verbosity variance (occasional missing `kzalloc` NULL guard) | `hid-ftecff.c` | **Yes** | §3 table row — non-behavioural (both drivers work; ours is marginally more defensive), not a functional gap |
| `MiSTer_fb.c` probe error-check bug | `drivers/video/fbdev/MiSTer_fb.c` | **No — this is backwards**: it is a bug *in his tree*, not a feature ours lacks | See F1 — ours is already correct; nothing to adopt |

**Every row in this table is dispositioned.** Zero findings from this direction.

---

## 8. Counts

- Diff sections reviewed: **58** (55 distinct files after de-duplicating the
  `scripts/dtc/include-prefixes` symlink echoes).
- **(a) comment/style/decomposition-only or verified-equivalent: 53 sections.**
- **(b) genuinely behavioural: 5 sections/clusters, all pre-existing and dispositioned**
  (cpufreq/clk ×7 files as one decision, hid-nintendo.c, hid-playstation.c, spidev.c+vt.h,
  exfat cluster ×6 files, AIC8800 Kconfig/Makefile, init/do_mounts.c).
- **Undispositioned findings: 1 — F1 (`drivers/video/fbdev/MiSTer_fb.c` probe
  error-check idiom)**, low severity, no action required on our side, Wave 5 candidate.
- DTS node-by-node comparison (§4): **0 findings**, everything already covered by
  `docs/dts-comparison.md` and re-verified here against the current fork HEAD.


## Correction (Wave 5, 2026-09-11)

The Wave 5 candidate row for `0038` (NSO Genesis BT PID) is withdrawn: `hid-nintendo.c` at
`c129b0fac` already contains the identical `hdev->product` normalization (grep re-verified while
porting; see `upstream-candidates/01-hid-nintendo-nso-genesis-bt-pid.NOTE.md`). The behavioural
cluster for that file therefore reduces to `0039`–`0041`. Everything else in this report stands.
