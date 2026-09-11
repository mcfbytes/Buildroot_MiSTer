# Stable drift verdicts, batch B — patches 0022–0042, 0047

Worker: W1-drift-verdicts (batch B). Written 2026-09-10.

## Grounding

- Vanilla tree: `$S/linux`, gregkh/linux mirror, `linux-6.18.y` checked out at
  **`1c732c6b94f0faee1526bd375add2fe10cba2e26`** ("Linux 6.18.49"). The mirror lags one
  release behind the 6.18.50 pin (`env.md`); **6.18.50 is not covered by this batch** — the
  6.18.49→6.18.50 delta must be walked separately once a tree carrying the `v6.18.50` tag is
  reachable. Every verdict and every `-F0` result below is against 6.18.49, not 6.18.50.
- Drift range walked: `v6.18.39` (`f89c296854b7`) .. `1c732c6b94f0` (6.18.49), per
  `stable-drift-6.18.39-49.md` (Wave 0, `drift.py`).
- Carried series: `board/mister/de10nano/linux-patches/`. No patch was modified by this
  worker; all `patch -p1 -F0` runs below are against temp copies of extracted 6.18.49 files
  only, under `<scratchpad>/work-drift-B/tree/`.
- Scope: every collision row in `stable-drift-6.18.39-49.md` whose Patch column is 0022
  through 0047 inclusive, i.e. `0022`–`0042` and `0047` (`0043`–`0046` are beta-only, out of
  scope). 22 patches in range; 16 of them have collision rows (36 rows total); 6 have zero
  collisions (`0025`, `0026`, `0027`, `0028`, `0029`, `0030`).
- 7.x axis: not applicable to this batch — none of PLAN §3 step 3's five explicit rows
  assigned to this batch touch the beta/DE25 series, and no collision row here is beta-local.

## 1. Collision verdicts

All 36 collision rows in scope are graded **disjoint**: the stable hunk and the carried
patch's hunk touch different functions/regions of the shared file, confirmed both by reading
the quoted hunks below and by the `-F0` chained dry-run (§3), which applied every hunk of
every patch in range cleanly (no `FAILED`, no fuzz; two patches show a pure line-offset with
identical context, discussed inline).

### 1.1 `drivers/hid/hid-nintendo.c` — 0032, 0034, 0035, 0038, 0039, 0040, 0041 vs. three stable commits

Three stable commits touch `hid-nintendo.c` in range, none of them in the regions any of
these seven carried patches touch:

| Stable commit | Date | Subject | Region touched (6.18.49 line #s) |
|---|---|---|---|
| `5efcd7bbfaae` | 2026-07-30 | stop device IO before `hid_hw_stop` on probe failure | `nintendo_hid_probe()` error labels, lines 2687–2728 (`err_close`→`err_io_stop`, adds `hid_device_io_stop()`) |
| `268679f50138` | 2026-07-30 | register input device after capabilities are set | `joycon_input_create()`, lines 2122–2181 (moves `input_register_device()` from right after `input_set_drvdata()` near the top of the function to just before `return 0;` at the end) |
| `51cfd1adbe7a` | 2026-07-15 | fix OOB read in `joycon_ctlr_read_handler()` | `joycon_ctlr_read_handler()`, lines 2557–2568 (`size >= 12` → `size >= sizeof(struct joycon_input_report)`) |

Quoted stable hunk (`268679f50138`, the one closest in proximity to a carried patch):

```
@@ -2138,10 +2138,6 @@ static int joycon_input_create(struct joycon_ctlr *ctlr)
-	ret = input_register_device(ctlr->input);
-	if (ret)
-		return ret;
-
 	if (joycon_type_is_right_joycon(ctlr)) {
...
@@ -2181,6 +2177,10 @@
 	if (joycon_has_rumble(ctlr))
 		joycon_config_rumble(ctlr);
+
+	ret = input_register_device(ctlr->input);
+	if (ret)
+		return ret;
```

Carried-patch regions, verified against the current (post-stable-fix) 6.18.49 tree:

| Patch | Touches | Current line (6.18.49, chained) | Verdict |
|---|---|---|---|
| `0032` | `struct joycon_ctlr` field + `joycon_parse_imu_report()` (~1487) + `joycon_leds_create()`/`home_led:` label (~2331) | none overlap 2122–2181, 2557–2568, 2687–2728 | disjoint |
| `0034` | `nescon_button_mappings[]` / `famicom_r_button_mappings[]` (~436–460) | same | disjoint |
| `0035` | `joycon_leds_create()`, `home_led:` registration error path (~2395–2400) | inside `joycon_leds_create()`, a different function from all three stable hunks | disjoint |
| `0038` | `joycon_input_create()`, **top of the function**, immediately before `ctlr->input = devm_input_allocate_device(&hdev->dev);` (0038's own hunk: `@@ -2164,6 +2164,26 @@ static int joycon_input_create(...)`) | Confirmed: in the live 6.18.49 tree this insertion point is lines 2126–2127, i.e. *before* `input_set_drvdata()` at line 2136 — `268679f50138`'s nearest touched line is 2138 (11 lines below 0038's insertion point, no shared context line) | disjoint (same function, non-overlapping region — see re-anchor note below) |
| `0039` | `gencon_button_mappings[]` / `n64con_button_mappings[]` (~480–530) | none overlap | disjoint |
| `0040` | `joycon_imu_input_create()`, `imu_name` assignment (line 2075, function ends at 2118) — an entirely separate function from `joycon_input_create()` at 2122 | none overlap | disjoint |
| `0041` | `joycon_leds_create()`, LED-name `devm_kasprintf()` calls (~2355–2420) | inside `joycon_leds_create()`, unrelated to any of the three stable hunks | disjoint |

Re-anchor note for `0038` only (nearest of the seven): `268679f50138` restructured
`joycon_input_create()` by moving `input_register_device()` from top to bottom, but did not
touch the very first lines of the function (`hdev = ctlr->hdev;` /
`ctlr->input = devm_input_allocate_device(&hdev->dev);`), which is exactly where `0038`
inserts its PID-normalisation block. A re-anchor would need nothing beyond what already
applies: `0038`'s three lines of context (`hdev = ctlr->hdev;` / blank / the
`devm_input_allocate_device` call) are byte-identical pre- and post-`268679f50138`. Confirmed
by the `-F0` run (§3): `0038` applies with **zero offset, zero fuzz**.

### 1.2 `drivers/hid/hid-playstation.c` — 0022, 0033, 0037, 0042 vs. `96dd35f1942c`

`96dd35f1942c` ("validate `num_touch_reports` in DualShock 4 reports", 2026-03-23) touches
only `dualshock4_parse_report()`:

```
@@ -2377,6 +2377,12 @@ static int dualshock4_parse_report(...)
+		if (usb->num_touch_reports > ARRAY_SIZE(usb->touch_reports)) {
+			hid_err(hdev, "DualShock4 USB input report has invalid num_touch_reports=%d\n", ...);
+			return -EINVAL;
+		}
...
+		if (bt->num_touch_reports > ARRAY_SIZE(bt->touch_reports)) {
+			hid_err(hdev, "DualShock4 BT input report has invalid num_touch_reports=%d\n", ...);
+			return -EINVAL;
+		}
```

Current 6.18.49 function map (`grep -n '^static' drivers/hid/hid-playstation.c`):
`ps_led_register()` 826, `dualsense_parse_report()` 1427, `dualsense_set_player_leds()` 1693,
`dualsense_create()` 1716, `dualshock4_get_mac_address()` 2117,
`dualshock4_parse_report()` 2358 (the stable commit's target).

| Patch | Touches | Verdict |
|---|---|---|
| `0022` | `dualshock4_get_mac_address()`, line 2117 — **240 lines above** `dualshock4_parse_report()` at 2358 | disjoint |
| `0033` | `dualsense_set_player_leds()`/`dualsense_create()`, lines 1693–1900 | disjoint |
| `0037` | `dualsense_parse_report()` (1427) + `dualsense_create()` (1716) — DualSense mic/BTN_Z, not DualShock 4 | disjoint |
| `0042` | `ps_led_register()` (826) + `dualsense_create()` (1716) — DualSense lightbar/DualShock 4 hid-sony-compat naming branch, not `dualshock4_parse_report()`'s touch-report parsing | disjoint |

All four confirmed clean at `-F0` (§3): zero offset, zero fuzz.

### 1.3 `drivers/hid/hid-wiimote-modules.c` — 0023 vs. `adf0eb748d21`

`adf0eb748d21` ("Fix table layout and whitespace errors", 2026-03-26) is whitespace-only, in
`wiimod_turntable_in_ext()`'s ASCII-art comment and `wiimod_turntable_probe()`'s opening
declaration line and closing `input_set_abs_params()` calls:

```
@@ -2557,7 +2557,7 @@ static int wiimod_turntable_probe(...)
- 	int ret, i;
+	int ret, i;
...
@@ -2594,9 +2594,9 @@
 	input_set_abs_params(wdata->extension.input,
-			     ABS_HAT2X, 0, 31, 1, 1);	
+			     ABS_HAT2X, 0, 31, 1, 1);
```

`0023`'s hunk in the same function inserts a field assignment mid-body:

```
@@ -2567,6 +2567,7 @@ static int wiimod_turntable_probe(...)
 	wdata->extension.input->open = wiimod_turntable_open;
 	wdata->extension.input->close = wiimod_turntable_close;
 	wdata->extension.input->dev.parent = &wdata->hdev->dev;
+	wdata->extension.input->uniq = wdata->hdev->uniq;
 	wdata->extension.input->id.bustype = wdata->hdev->bus;
```

Confirmed against the live 6.18.49 tree: the function's opening (`int ret, i;`, line 2560) and
closing (`input_set_abs_params(..., ABS_HAT3X, ...)` through `input_register_device()`, lines
~2594–2599) are the only lines `adf0eb748d21` touches; `0023`'s insertion point
(`wdata->extension.input->dev.parent = ...`, line ~2569) sits in the untouched middle of the
same function, with none of its three context lines carrying trailing whitespace. Disjoint.
Confirmed clean at `-F0`.

### 1.4 `drivers/hid/hid-input.c` — 0024 vs. `02a88f8308ae`

`02a88f8308ae` ("fix battery reporting for Bluetooth Magic Trackpad USB-C", 2026-07-06) adds
one row to `hid_battery_quirks[]` (line ~374–380):

```
@@ -374,6 +374,9 @@ static const struct hid_device_id hid_battery_quirks[] = {
+	{ HID_BLUETOOTH_DEVICE(BT_VENDOR_ID_APPLE,
+		USB_DEVICE_ID_APPLE_MAGICTRACKPAD2_USBC),
+	  HID_BATTERY_QUIRK_AVOID_QUERY },
```

`0024` edits the unrelated `hid_keyboard[256]` scancode table (USB keycode 0x32: 43 → 194,
the Keyrah Europe-1 remap), a different table entirely (`hid-input.c`'s battery-quirk table
vs. its USB-HID-to-Linux-keycode table). Disjoint. Confirmed clean at `-F0` (zero offset,
zero fuzz).

### 1.5 `fs/exfat/{dir.c,exfat_fs.h,namei.c}` — 0031 vs. `62dde71ca2c8`

This is the one row worth flagging beyond a plain "disjoint" tag. `62dde71ca2c8` ("preserve
benign secondary entries during rename and move", 2026-07-16) is the **exact commit `0031`'s
own header documents adapting to**:

> "1. 6.18.40 API adaptation. The stable series backported upstream's benign-secondary-entry
> preservation rework, which gave `exfat_remove_entries()` a 4th arg (`bool free_benign`). The
> symlink error-path call passes `true`, matching upstream's own unlink/rmdir idiom... NOTE:
> on the stable side this patch now requires >= 6.18.40; it will not compile against 6.18.39
> or earlier."

Stable's hunk changes the function **signatures**:

```
--- a/fs/exfat/exfat_fs.h
 void exfat_init_ext_entry(struct exfat_entry_set_cache *es, int num_entries,
-		struct exfat_uni_name *p_uniname);
+		struct exfat_uni_name *p_uniname,
+		struct exfat_entry_set_cache *old_es, int num_extra);
 void exfat_remove_entries(struct inode *inode, struct exfat_entry_set_cache *es,
-		int order);
+		int order, bool free_benign);
```

and their **definitions** in `dir.c` (lines 481–560 in the current tree), plus every
**call site** in `namei.c` (`exfat_add_entry()` line 509, `exfat_unlink()` line 820,
`exfat_rmdir()` line 981, `exfat_rename_file()`/`exfat_move_file()` lines 1043–1200,
`__exfat_rename()` line 1251).

`0031`'s own hunks never touch `exfat_init_ext_entry()`'s or `exfat_remove_entries()`'s
*definitions* (its `dir.c` hunks are at lines 268 `get_new:`/`dir_emit` and 396–410
`exfat_set_entry_type()`, both well clear of stable's 481–560 region) — it only *calls*
`exfat_remove_entries(inode, &es, ES_IDX_FILE, true);` inside its new `exfat_symlink()`
error path, with the 4-arg form stable's signature requires. Its `namei.c` insertion in
`exfat_add_entry()` (`if (type == TYPE_FILE || type == TYPE_SYMLINK) {`, line 519) sits 10
lines below stable's `exfat_init_ext_entry(&es, num_entries, &uniname, NULL, 0);` call at
line 509 — same function, no shared context line, confirmed by the two unmodified context
lines `0031` carries above its edit (`info->entry = dentry;` / `info->flags = ...` /
`info->type = type;`), which match the live tree exactly.

**Verdict: disjoint at the hunk-line level, but load-bearing dependent** — `0031` does not
merely tolerate `62dde71ca2c8`, it requires it (own header: "will not compile against 6.18.39
or earlier"). No re-anchor work is needed; it was already done in the patch itself before this
worker ran. Confirmed at `-F0`: applies with two pure-offset hunks and zero fuzz —
`exfat_fs.h` hunk #3 at offset 1 line, `namei.c` hunk #3 at offset 49 lines (both from
unrelated upstream churn elsewhere in those files across v6.18.39..49, not from
`62dde71ca2c8` itself). This is **not** a `superseded` case: `62dde71ca2c8` fixes an existing
exFAT bug and adds no symlink capability of any kind; `0031`'s entire raison d'être (Samsung-
format symlinks) remains 100% absent from vanilla.

### 1.6 `drivers/bluetooth/btusb.c` — 0036, 0047 vs. three stable commits

| Stable commit | Date | Subject | Region touched |
|---|---|---|---|
| `dc0c462fa838` | 2026-05-30 | Add TP-Link UB600 for Realtek 8761BUV | `quirks_table[]`, adds `{ USB_DEVICE(0x37ad, 0x0600), ...}` after the `0x2b89:0x6275` row, near the *end* of the "Additional Realtek 8761BUV" block (now lines 803–806, right before the `/* Additional Realtek 8821AE ... */` comment at line 808) |
| `f14d41dbc2fd` | 2026-07-27 | Fix short read errors in `btusb_qca_send_vendor_req()` | `btusb_qca_send_vendor_req()` and its three callers, lines ~3345–3625 |
| `8881daaafadb` | 2026-07-20 | validate Realtek vendor event length | `btusb_recv_event_realtek()`, lines ~2716–2720 |

`0036` touches `btusb_setup_csr()` (line 2443–2475 in the current tree), an entirely
different function from all three. Confirmed: `git log --oneline v6.18.39..v6.18.49 --
drivers/bluetooth/btusb.c` returns exactly these three commits, and none of them is
`btusb_setup_csr` or its `is_fake` chain. Disjoint. `0x2512` does not appear anywhere in the
6.18.49 file (`grep -n 0x2512` → empty). `-F0`: applies with hunk #1 at offset 4 lines (from
`dc0c462fa838`'s 2-line quirks-table addition earlier in the file plus minor unrelated
upstream churn), zero fuzz.

`0047` inserts `{ USB_DEVICE(0x2c4e, 0x0115), ...}` at the **start** of the "Additional
Realtek 8761BUV" comment block (its own hunk: `@@ -786,6 +786,8 @@`, right after the section
comment, before the `0x2357:0x0604` row) — 17 lines above where `dc0c462fa838` inserted its
own row at the *end* of that same block. Same table, non-overlapping rows, no shared context
line. Disjoint. Confirmed clean at `-F0`, zero offset, zero fuzz.

## 2. `-F0` dry-run table (all 22 patches in range)

Method: extracted `drivers/hid/hid-nintendo.c`, `drivers/hid/hid-playstation.c`,
`drivers/bluetooth/btusb.c`, `drivers/hid/hid-wiimote-{core,modules}.c`,
`drivers/hid/hid-input.c`, `drivers/hid/usbhid/hid-core.c`, `drivers/input/{input,mousedev}.c`,
`include/linux/input.h`, `drivers/net/wireless/mediatek/mt76/mt76x2/usb.c`,
`drivers/usb/dwc2/hcd_intr.c`, `drivers/leds/leds-gpio.c`,
`drivers/i2c/busses/i2c-designware-master.c`, and the six `fs/exfat/*.c/.h` files verbatim
from `$S/linux` at 6.18.49, into `<scratchpad>/work-drift-B/tree/`. For files touched by more
than one patch in the series (`hid-nintendo.c`, `hid-playstation.c`, `btusb.c`), patches were
applied **in series order** (`0015` first as the one out-of-range prerequisite for `0034`'s
Famicom-table dependency, then `0022..0047` as listed) — each patch was `--dry-run`'d at its
position in the chain, then applied for real (`patch -p1 -F0`, no dry-run) before testing the
next, so later patches see the file state they actually build on in a real
`scripts/export-kernel-tree.sh` replay.

| Patch | File(s) | Result |
|---|---|---|
| `0022` | hid-playstation.c | clean (all hunks, 0 offset, 0 fuzz) |
| `0023` | hid-wiimote-core.c, hid-wiimote-modules.c | clean |
| `0024` | hid-input.c | clean |
| `0025` | usbhid/hid-core.c | clean |
| `0026` | input.c, mousedev.c, linux/input.h | clean |
| `0027` | mt76x2/usb.c | clean |
| `0028` | dwc2/hcd_intr.c | clean |
| `0029` | leds-gpio.c | clean |
| `0030` | i2c-designware-master.c | clean |
| `0031` | exfat dir.c, exfat_fs.h, exfat_raw.h, file.c, inode.c, namei.c | clean, with offsets: exfat_fs.h hunk #3 offset 1 line; namei.c hunk #3 offset 49 lines; zero fuzz throughout |
| `0032` | hid-nintendo.c | clean |
| `0033` | hid-playstation.c | clean |
| `0034` | hid-nintendo.c | clean |
| `0035` | hid-nintendo.c | clean |
| `0036` | btusb.c | clean, hunk #1 offset 4 lines, zero fuzz |
| `0037` | hid-playstation.c | clean |
| `0038` | hid-nintendo.c | clean |
| `0039` | hid-nintendo.c | clean |
| `0040` | hid-nintendo.c | clean |
| `0041` | hid-nintendo.c | clean |
| `0042` | hid-playstation.c | clean |
| `0047` | btusb.c | clean |

**Zero `FAILED` hunks, zero fuzzed hunks, across all 22 patches in range.** The two offsets
(`0031`, `0036`) are pure line-number shifts with unchanged context — not evidence of drift
into the patches' own regions, confirmed by §1's line-by-line analysis.

## 3. PLAN §3 step 3 explicit findings (this batch's five: 0027, 0028, 0030, 0036, 0047)

**0027 — mt76x2u Xbox adapter IDs.** `grep -n '045e, 0x02e6\|045e, 0x02fe' drivers/net/wireless/mediatek/mt76/mt76x2/usb.c` at 6.18.49:

```
26:	{ USB_DEVICE(0x045e, 0x02e6) },	/* XBox One Wireless Adapter */
27:	{ USB_DEVICE(0x045e, 0x02fe) },	/* XBox One Wireless Adapter */
```

Both IDs are still present in vanilla 6.18.49's `mt76x2u_device_table[]`, byte-identical to
6.18.38/v6.18.39. `git log --oneline v6.18.39..v6.18.49 --
drivers/net/wireless/mediatek/mt76/mt76x2/usb.c` returns **no commits**. The removal `0027`
performs is still needed — mt76 would otherwise still win the driver-matching race against
`xone` for the Xbox One Wireless Adapter. Not superseded, not affected.

**0028 — dwc2 unaligned IN split.** `git log --oneline v6.18.39..v6.18.49 --
drivers/usb/dwc2/` returns **zero commits** — the entire `dwc2` directory is untouched across
the whole drift range. `dwc2_hc_xfercomp_intr()`/`dwc2_xfercomp_isoc_split_in()` in the
current tree are structurally identical to what `0028`'s own provenance note describes for
6.18.38 (confirmed live: `chan->align_buf` copy still confined to
`dwc2_xfercomp_isoc_split_in()`, `dwc2_hc_xfercomp_intr()` at line 958 has no `align_buf`
handling of its own). Patch fully unaffected; applies at zero offset (§2).

**0030 — i2c-designware dev_err quieting.** `git log --oneline v6.18.39..v6.18.49 --
drivers/i2c/busses/i2c-designware-master.c` returns **zero commits**. Current `i2c_dw_xfer()`
call site (line 855–858):

```
	ret = i2c_dw_wait_transfer(dev);
	if (ret) {
		dev_err(dev->dev, "controller timed out\n");
```

Still `dev_err`, unchanged from 6.18.38. `0030`'s downgrade to `dev_dbg` remains needed and
unabsorbed.

**0036 — btusb CSR 0x2512.** Three stable commits touch `btusb.c` in range (§1.6); none
touches `btusb_setup_csr()` or extends its `is_fake` range checks — `dc0c462fa838` only adds
a `quirks_table[]` row, `f14d41dbc2fd` only rewrites `btusb_qca_send_vendor_req()`,
`8881daaafadb` only bounds-checks `btusb_recv_event_realtek()`. `grep -n 0x2512
drivers/bluetooth/btusb.c` at 6.18.49 → **no match**. The CSR clone detection `0036` adds is
still absent from vanilla and unaffected by anything in this drift range.

**0047 — btusb Mercusys 2c4e:0115.** `grep -n 0x2c4e drivers/bluetooth/btusb.c` at 6.18.49:

```
534:	{ USB_DEVICE(0x2c4e, 0x0128), .driver_info = BTUSB_REALTEK |
```

Only `0x2c4e:0x0128` is present; **`0x2c4e:0x0115` is absent**, confirming `0047` remains
needed on the 6.18.y-pinned de10 series. Neighbouring rows (lines 525–536) are the "Realtek
8851BU"/generic-8761BUV block:

```
	{ USB_DEVICE(0x3625, 0x010b), .driver_info = BTUSB_REALTEK | BTUSB_WIDEBAND_SPEECH },
	{ USB_DEVICE(0x2001, 0x332a), .driver_info = BTUSB_REALTEK | BTUSB_WIDEBAND_SPEECH },
	{ USB_DEVICE(0x7392, 0xe611), .driver_info = BTUSB_REALTEK | BTUSB_WIDEBAND_SPEECH },
	{ USB_DEVICE(0x2c4e, 0x0128), .driver_info = BTUSB_REALTEK | BTUSB_WIDEBAND_SPEECH },
```

Per the patch's own retire-trigger, checked by tag: `git show v7.2.3:drivers/bluetooth/btusb.c
| grep -n 2c4e` (both via the gregkh mirror's `v7.2.3` tag and independently via the
`$S/linux-7.2` tree, HEAD = "Linux 7.2.3", `58e7295cfecadd`):

```
535:	{ USB_DEVICE(0x2c4e, 0x0128), .driver_info = BTUSB_REALTEK |
830:	{ USB_DEVICE(0x2c4e, 0x0115), .driver_info = BTUSB_REALTEK |
```

`2c4e:0115` **is** in-tree at v7.2.3 (as `0047`'s own header states — it is a plain backport
of a mainline commit that landed for the 7.2 line). This confirms both halves of the patch's
own logic: (a) still needed on 6.18.y — confirmed above; (b) correctly excluded from the beta
series (7.2.x already has it in-tree, and the patch header records a measured `-F0` FAIL
there). No action needed this increment; the retire condition (`pin leaves 6.18.y`) has not
fired.

## 4. Superseded / conflicting section

**Empty.** No collision row in this batch (0022–0042, 0047) graded `superseded` or
`conflicting`. No row met the `dropped-upstream` evidence bar (same-behaviour confirmation of
a stable commit implementing what a carried patch does) — every stable commit examined fixes
an unrelated bug, adds an unrelated device ID, or reworks unrelated internal plumbing in a
file a carried patch happens to also touch.

## 5. Conclusion

None of the 22 patches in this batch (`0022`–`0042`, `0047`) retire this increment. All 36
collision rows in range are disjoint from their carried patch's hunk region, confirmed both
by reading the actual current 6.18.49 source (function-by-function line mapping, §1) and by
a chained `patch -p1 -F0 --dry-run`/apply replay of the full in-range series against
extracted 6.18.49 files, which produced zero `FAILED` hunks and zero fuzz across all 22
patches — only two harmless line-offset hunks (`0031`, `0036`), both with unchanged context.
One patch, `0031` (exfat Samsung symlinks), is worth carrying forward as a standing note
rather than an action: it is not merely compatible with stable commit `62dde71ca2c8` but
*depends* on it (the patch's own header already documents the 6.18.40 API adaptation, and its
"requires >= 6.18.40" constraint is satisfied by both the 6.18.49 grounding here and the
6.18.50 pin). No patch in this batch needs re-anchoring: `0038` is the closest thing to a
near-miss (same function as a stable relocation, `268679f50138`) and applies at zero offset
because its insertion point predates everything the stable commit touches. The five PLAN §3
explicit rows assigned to this batch (`0027`, `0028`, `0030`, `0036`, `0047`) all confirm
their patches remain necessary and unaffected by the 6.18.39→6.18.49 walk; `0047`'s
retire-trigger condition is independently reconfirmed false (2c4e:0115 absent from 6.18.49,
present at v7.2.3, exactly as the patch predicts). The open item is unchanged from `env.md`:
this batch, like the rest of Wave 1's drift verdicts, is grounded on 6.18.49 and the
6.18.49→6.18.50 delta still needs to be walked once a tree carrying the `v6.18.50` tag is
reachable.
