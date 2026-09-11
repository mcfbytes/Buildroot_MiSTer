# Wave 2 refutation — stable drift verdicts and independent build backstop (W2-drift)

Worker: W2-drift (PLAN §5.2). Written 2026-09-10. Read-only against `$S/linux` (gregkh mirror,
`linux-6.18.y` @ `1c732c6b94f0faee1526bd375add2fe10cba2e26`, "Linux 6.18.49" — the 6.18.50 pin is
not reachable this session, see `env.md`) and `$S/linux-7.2` (`linux-7.2.y` @
`58e7295cfecaddec94629160386412e0f2b1e8fe`, "Linux 7.2.3" — 7.2.4 is the real beta pin, not
reachable). No patch or Wave 1 report was modified. All extraction/apply work happened under
`$S/w2work/` (scratch, outside the read-only trees).

## 1. Sampled-row re-derivation

**Sample composition** (17 of 42 rows): every 5th row of the 42-row table (rows 1, 6, 11, 16, 21,
26, 31, 36, 41 — 9 rows), plus the single overlapping-compatible row (row 3: `0015` vs
`268679f50138`), plus rows selected for same-subsystem-behaviour relevance per the assignment's
hints — touch (row 7: `0022`), CSR/LMP (rows 23–25: all three `0036` stable-commit rows), and LED
(rows 37–39: the remaining two `0041` rows and the `0042` row) — 17 rows total, covering 9 of the
13 distinct stable SHAs in the table and 11 of the 20 carried patches that have collision rows.

Every stable commit below was re-fetched independently with `git -C $S/linux show <sha> -- <path>`
and every carried-patch hunk was re-read from the patch file directly (not copied from the Wave 1
reports) before grading.

| Row | Patch | Path | Stable SHA | Wave 1 verdict | My verdict | Agree? |
|---|---|---|---|---|---|---|
| 1 | `0002` | `sound/drivers/dummy.c` | `f20c2c32ec1c` | disjoint | disjoint | yes |
| 3 | `0015` | `drivers/hid/hid-nintendo.c` | `268679f50138` | overlapping-compatible | overlapping-compatible | yes |
| 6 | `0019` | `drivers/hid/hid-logitech-hidpp.c` | `097fcf945d93` | disjoint | disjoint | yes |
| 7 | `0022` | `drivers/hid/hid-playstation.c` | `96dd35f1942c` | disjoint | disjoint | yes |
| 11 | `0031` | `fs/exfat/exfat_fs.h` | `62dde71ca2c8` | disjoint (load-bearing dependent) | disjoint (load-bearing dependent) | yes |
| 16 | `0033` | `drivers/hid/hid-playstation.c` | `96dd35f1942c` | disjoint | disjoint | yes |
| 21 | `0035` | `drivers/hid/hid-nintendo.c` | `268679f50138` | disjoint | disjoint | yes |
| 23 | `0036` | `drivers/bluetooth/btusb.c` | `dc0c462fa838` | disjoint | disjoint | yes |
| 24 | `0036` | `drivers/bluetooth/btusb.c` | `f14d41dbc2fd` | disjoint | disjoint | yes |
| 25 | `0036` | `drivers/bluetooth/btusb.c` | `8881daaafadb` | disjoint | disjoint | yes |
| 26 | `0037` | `drivers/hid/hid-playstation.c` | `96dd35f1942c` | disjoint | disjoint | yes |
| 31 | `0039` | `drivers/hid/hid-nintendo.c` | `268679f50138` | disjoint | disjoint | yes |
| 36 | `0041` | `drivers/hid/hid-nintendo.c` | `5efcd7bbfaae` | disjoint | disjoint | yes |
| 37 | `0041` | `drivers/hid/hid-nintendo.c` | `268679f50138` | disjoint | disjoint | yes |
| 38 | `0041` | `drivers/hid/hid-nintendo.c` | `51cfd1adbe7a` | disjoint | disjoint | yes |
| 39 | `0042` | `drivers/hid/hid-playstation.c` | `96dd35f1942c` | disjoint | disjoint | yes |
| 41 | `0047` | `drivers/bluetooth/btusb.c` | `f14d41dbc2fd` | disjoint | disjoint | yes |

**Agreement: 17/17 (100%). No verdict refuted.**

### Evidence detail

**Row 1 — `0002` vs `f20c2c32ec1c`.** Stable inserts a 6-line card-index bounds check
immediately before `err = snd_devm_card_new(...)` at old line 1017 in `snd_dummy_probe()`:
```
+	if (dev < 0 || dev >= SNDRV_CARDS) {
+		dev_warn(&devptr->dev, "Invalid card index %d, using default 0\n", dev);
+		dev = 0;
+	}
```
`0002`'s hunk anchors 6 lines later (`@@ -1023,6 +1056,10 @@`), on `return err;` /
`dummy = card->private_data;` context, to add `dummy->model = m = &model_MiSTer;`. Different
function region, no line intersection, and downstream of stable's insertion — confirmed at `-F0`
in §2 (offset +6, no fuzz, exactly stable's 6-line delta). **disjoint.**

**Row 3 — `0015` vs `268679f50138`.** Stable moves `input_register_device(ctlr->input)` from the
top of `joycon_input_create()` (removes 4 lines at old 2138–2141) to just before `return 0;` (adds
4 lines after old ~2177). `0015`'s hunk (`@@ -2157,9 +2193,13 @@`) sits in the untouched middle of
the same function — its own three lines of context read:
```
 		joycon_config_right_stick(ctlr->input);
 		joycon_config_dpad(ctlr->input);
 		joycon_config_buttons(ctlr->input, procon_button_mappings);
-	} else if (joycon_type_is_any_nescon(ctlr)) {
+	} else if (joycon_type_is_any_nescon(ctlr) ||
+		   joycon_type_is_left_famicom(ctlr)) {
```
— the if/else-if type-dispatch chain, strictly between stable's removal point (2141) and
insertion point (2177). No shared line. Confirmed at `-F0`: applies at offset −4, zero fuzz — the
exact size of stable's 4-line move. **overlapping-compatible**, matching Wave 1 exactly.

**Row 6 — `0019` vs `097fcf945d93`.** Stable deletes one stale kernel-doc line (`@dev:` member
doc) from `struct hidpp_scroll_counter` at old line 164 — comment-only, no code. `0019`'s four
hunks anchor at old lines 3337, 3361, 3380, 4559 (`m560_input_mapping`, a new
`k400_disable_tap_to_click()`, `k400_connect()`, `hidpp_devices[]`) — all >3000 lines downstream,
functional K400 code unrelated to the struct doc. `-F0`: uniform offset −1, zero fuzz. **disjoint.**

**Row 7/16/26/39 — `0022`/`0033`/`0037`/`0042` vs `96dd35f1942c`.** Stable adds two
`num_touch_reports` bounds checks inside `dualshock4_parse_report()` (old lines 2377–2404, quoted
in full in `stable-drift-verdicts-B.md` §1.2 and independently re-pulled here — identical).
Function map of the current 6.18.49 tree (`grep -n '^static' drivers/hid/hid-playstation.c`):
`ps_led_register` 826, `dualsense_parse_report` 1427, `dualsense_set_player_leds` 1693,
`dualsense_create` 1716, `dualshock4_get_mac_address` 2117, `dualshock4_parse_report` 2358 —
stable's target. Carried-patch hunk anchors (own patch files, pre-chain old-line headers):
`0022` at 2128/2149 (`dualshock4_get_mac_address`, 200+ lines above), `0033` at 216/1210/1690/1847
(`dualsense_*`, DualSense not DualShock4), `0037` at 211/1404/1457/1699/1775/1839 (`dualsense_*`),
`0042` at 171/198/835/1650/1823 (`ps_led_register`/`dualsense_create`). None reach
`dualshock4_parse_report`'s 2358–2404 region. **All four disjoint**, confirmed at `-F0` (zero
offset, zero fuzz for all four in §2).

**Row 11 — `0031` vs `62dde71ca2c8`.** Stable changes `exfat_init_ext_entry()`/
`exfat_remove_entries()` **signatures** in `exfat_fs.h` (adds two params each) at old lines
496–504. `0031`'s three `exfat_fs.h` hunks anchor at old lines 60, 372, 526 — none touch the
496–504 declaration block. But `0031`'s own header documents that it *requires* this exact stable
commit ("will not compile against 6.18.39 or earlier") for its 4-arg `exfat_remove_entries()`
call. Consistent independent check: the hunk at old 526 (`@@ -526,6 +530,7 @@`) lands 4 lines
below the *un-patched* 522 that a naive line count would predict, i.e. it already accounts for
stable's net +1-line signature growth (496–504 is 9 lines old → 10 lines new) — exactly the
`+1`-line offset `-F0` reports for this hunk in §2. **disjoint at the hunk level, load-bearing
dependent** — same grade and same reasoning as Wave 1's batch B §1.5.

**Row 21/31 — `0035`/`0039` vs `268679f50138`.** `0035`'s one hunk (`@@ -2395,8 +2395,13 @@
home_led:`) is inside `joycon_leds_create()`, well past `joycon_input_create()`'s 2122–2181 range
stable touches. `0039`'s one hunk (`@@ -480,32 +480,49 @@ snescon_button_mappings[]`) is 1600+
lines upstream of it. **Both disjoint.**

**Row 23–25 — `0036` vs three `btusb.c` commits.** `0036`'s single hunk
(`@@ -2522,6 +2522,13 @@`) inserts an `else if (lmp_subver == 0x2512)` branch inside
`btusb_setup_csr()`. Independently confirmed the function boundaries in the live 6.18.49 tree:
`btusb_setup_csr` starts at line 2443, `btusb_recv_event_realtek` at 2719,
`btusb_qca_send_vendor_req` at 3347 — `0036`'s insertion at 2522 sits inside `btusb_setup_csr`
itself (right after the `bcdDevice == 0x0134` clone check, before `if (is_fake) {`), nowhere near
`quirks_table[]` (`dc0c462fa838`, ~802), `btusb_recv_event_realtek` (`8881daaafadb`, 2719), or
`btusb_qca_send_vendor_req` (`f14d41dbc2fd`, 3345+). **All three disjoint.**

**Row 36–38 — `0041` vs three `hid-nintendo.c` commits.** `0041`'s two hunks
(`@@ -2355,10 +2355,13 @@` / `@@ -2417,10 +2420,20 @@`, both `static int joycon_leds_create`)
are entirely inside `joycon_leds_create()` — a different function from
`nintendo_hid_probe()`'s error path (`5efcd7bbfaae`, 2687–2728), `joycon_input_create()`
(`268679f50138`, 2122–2181), and `joycon_ctlr_read_handler()` (`51cfd1adbe7a`, 2557–2568), and
`joycon_leds_create` sits between `joycon_ctlr_read_handler` and `joycon_input_create` in file
order without overlapping either. **All three disjoint.**

**Row 41 — `0047` vs `f14d41dbc2fd`.** `0047`'s one hunk (`@@ -786,6 +786,8 @@`) inserts a
`{ USB_DEVICE(0x2c4e, 0x0115), ... }` row at the *start* of the "Additional Realtek 8761BUV"
block in `quirks_table[]`; `f14d41dbc2fd` rewrites `btusb_qca_send_vendor_req()` at old
3345–3625, a different table/function entirely. **disjoint.**

No sampled row disagreed with Wave 1. No `superseded` or `conflicting` grade was found or should
have been assigned to any sampled row — every stable commit examined fixes an unrelated bug, adds
an unrelated device ID, or touches unrelated internal plumbing in a file the carried patch happens
to share, never the behaviour the carried patch itself changes.

## 2. Independent `-F0` apply backstop

### 2.1 6.18 series (37 patches) against 6.18.49

Method: `grep -h '^+++ b/' board/mister/de10nano/linux-patches/*.patch | sed 's|^+++ b/||' | sort -u`
→ 47 unique paths; 10 are new files a patch creates (`drivers/cpufreq/socfpga-cpufreq.c`,
`drivers/hid/hid-ftec.{c,h}`, `hid-ftecff.c`, `hid-gamecube-adapter.c`, `hid-guncon2.c`,
`hid-guncon3.c`, `hid-vader4.c`, `drivers/video/fbdev/MiSTer_fb.c`,
`sound/drivers/MiSTer-audio-spi.c`) and correctly do not exist yet at `1c732c6b94f0` (6.18.49) —
confirmed with `git cat-file -e HEAD:<path>` per path, not assumed. The remaining 37 pre-existing
paths were extracted with `git -C $S/linux archive HEAD <paths> | tar -x -C <tmp>` into a fresh
scratch tree, then all 37 patches were applied **for real** (not `--dry-run`), in filename order,
with `patch -p1 -F0 --no-backup-if-mismatch`.

**Result: 37/37 applied, exit 0 every time, zero fuzz, zero FAILED anywhere in the log**
(`grep -ci "fuzz\|FAILED\|reject" apply610.log` → 0).

| Patch | Result at `-F0` (real apply, chained) |
|---|---|
| `0001`–`0001` fbdev | clean |
| `0002` sound dummy | Hunk #3 offset **+6** (matches `f20c2c32ec1c`, row 1) |
| `0003` cpufreq overclock | clean |
| `0004` dts de10nano | clean |
| `0010` guncon2 | clean |
| `0011` guncon3 | clean (no offsets — series order resolves the isolated-run failure Wave 1 batch A flagged) |
| `0012` fanatec | clean |
| `0013` flydigi vader | clean, no offset |
| `0014` gamecube adapter | clean, no offsets |
| `0015` nintendo famicom | Hunk #5 offset **−4** (matches `268679f50138`, row 3) |
| `0016` microsoft elite2 | clean |
| `0017` xpad deltas | Hunks #5–#18 offset **+1 to +2** (matches `455dbb5bdd81`) |
| `0018` controllable quirk | clean |
| `0019` hidpp k400 | Hunks #1–#4 offset **−1** (matches `097fcf945d93`, row 6) |
| `0020` mmc no-led | clean |
| `0022`–`0030` (9 patches) | all clean, zero offset |
| `0031` exfat symlinks | Hunk #3 (`exfat_fs.h`) offset **+1**; hunk #3 (`namei.c`) offset **+49**; zero fuzz (matches `62dde71ca2c8`, row 11) |
| `0032`–`0035` | all clean |
| `0036` btusb CSR | Hunk #1 offset **+4** |
| `0037`–`0042` | all clean |
| `0047` btusb Mercusys | clean |

Every offset traces to a collision row already graded above (§1) or in the Wave 1 reports; no
patch produced fuzz or a failure at any point in the real, ordered, cumulative apply. **This
independently confirms Wave 1's build-backstop claim** — including that `0011`/`0014`'s
isolated-dry-run failures reported in `stable-drift-verdicts-A.md` are purely a series-ordering
artifact: applied for real in sequence here, both are clean with no offset.

### 2.2 Beta series (40 patches, per `series`) against v7.2.3

`board/mister/de10nano/linux-patches-beta/series` lists 40 entries (36 symlinks into
`linux-patches/` + `0015`/`0030`/`0031`/`0037` as real re-anchored copies + `0001` as a real
re-anchored copy + `0043`–`0046` beta-local originals), explicitly excluding `0047` with a
documented reason (mainline backport already in-tree at 7.2). Confirmed by counting: 40 lines
after stripping comments, exactly matching the series file's own "36 shared + 4 beta-local = 40"
claim.

Paths: `grep -h '^+++ b/' <each series file>` → 51 unique paths; 10 are new files (same set as
§2.1 plus none extra — confirmed with the same `cat-file -e` check against `v7.2.3`'s
`58e7295cfecaddec94629160386412e0f2b1e8fe`), 41 pre-existing paths extracted with
`git -C $S/linux-7.2 archive HEAD <paths> | tar -x -C <tmp2>`, then all 40 series patches applied
for real, in series order, `patch -p1 -F0 --no-backup-if-mismatch`, following the symlinks.

**Result: 40/40 applied, exit 0 every time, zero fuzz, zero FAILED anywhere in the log**
(`grep -ci "fuzz\|FAILED\|reject\|can't find\|No file to patch" apply72.log` → 0). Offsets are
larger than the 6.18 run (expected — 7.2.3 is much further from the original patch baselines) but
uniformly clean:

| Patch | Notable offsets (clean, zero fuzz) |
|---|---|
| `0002` | +6 |
| `0003` | −5, −3 |
| `0010`/`0011`/`0014` | −6, +37 (each) |
| `0012` | −6 |
| `0013` | −6, +2 |
| `0015` (7.x re-anchored copy) | −4 |
| `0017` | −31 to −34 across all 18 hunks |
| `0018` | −4, +1 |
| `0019` | +11 to +51 |
| `0020` (7.x re-anchored copy) | +1 |
| `0022` | +31 |
| `0025` | +1 |
| `0028` | +2 |
| `0029` | −1 |
| `0031` (7.x re-anchored copy) | clean, zero offset |
| `0032`–`0042` (hid-nintendo/playstation LED/mapping set) | +9 to +31 |
| `0036` | +68 |
| `0037` (7.x re-anchored copy) | clean, zero offset |
| `0043`–`0046` (beta-local) | clean, zero offset |
| all others (`0001`, `0004`, `0016`, `0023`, `0024`, `0026`, `0027`, `0030`, `0038`–`0041`) | clean, mostly zero or small offset |

As a targeted extra check, `0047` (the deliberately-excluded patch) was run against the same
`tree72` state with `patch -p1 -F0 --dry-run`: it **fails**, byte-for-byte reproducing the series
file's own claim —
```
checking file drivers/bluetooth/btusb.c
Hunk #1 FAILED at 786.
1 out of 1 hunk FAILED
```
confirming the series comment's stated reason (0x2c4e:0x0115 already present in the 7.2 line) is
not merely asserted but independently reproducible.

**Version-gap note**: the real beta pin is **7.2.4**; **7.2.3** is what this session can reach
(mirror lag, `env.md`). This apply run is grounded on 7.2.3, one release short of the pin, same
caveat as the rest of this increment's 7.x work — the 7.2.3→7.2.4 delta is not covered here.

## 3. Enumeration sanity check

Three carried patches with **zero** collision rows (from Wave 0's "Patches with zero path
collisions" list, none previously spot-checked by Wave 1's explicit-row list which covered
`0020`/`0027`/`0028`/`0030`/`0036`/`0047`):

```
$ git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/hid/hid-microsoft.c
(empty)
$ git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/hid/usbhid/hid-core.c
(empty)
$ git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/input/input.c drivers/input/mousedev.c include/linux/input.h
(empty)
```

All three return empty — **confirms** `drift.py`'s zero-collision finding for `0016`
(hid-microsoft elite2 paddles), `0025` (usbhid jspoll), and `0026` (mousedev eviocgrab) rather
than contradicting it. No evidence the enumeration missed rows for these three paths.

## 4. Conclusion

- **Sampled-row re-derivation: 17/17 agree with Wave 1 (100%).** 16 disjoint, 1
  overlapping-compatible (`0015` vs `268679f50138`) — no refutation. Every stable commit's diff
  and every carried-patch hunk was independently re-pulled and re-read (not copied from the Wave 1
  markdown), and the region/function-level reasoning matches Wave 1's in every case, including the
  one non-trivial row (`0031`/`exfat_fs.h`, disjoint-but-load-bearing-dependent) and the one
  overlapping-compatible row.
- **6.18 series -F0 replay: 37/37 clean, zero fuzz, zero failures**, real (non-dry-run) apply
  against extracted 6.18.49 sources in filename order — confirms Wave 1's build-backstop claim
  exactly, offsets included.
- **Beta series -F0 replay: 40/40 clean, zero fuzz, zero failures**, real apply against extracted
  v7.2.3 sources in `series`-file order — new data point (Wave 1's drift-verdict batches did not
  include a beta-series `-F0` table; this worker added one). `0047`'s deliberate exclusion is
  independently reproduced as a hunk failure against the same tree, matching the series file's own
  claim word for word.
- **Enumeration check: 3/3 zero-collision patches confirmed genuinely zero** — no evidence
  `drift.py` missed rows for `0016`, `0025`, or `0026`.
- **Nothing in this refutation pass changes Wave 1's headline numbers**: 41 disjoint / 1
  overlapping-compatible / 0 superseded / 0 conflicting stands, and the clean `-F0` series replay
  claim stands for both the 6.18 and (newly confirmed here) the beta series. The open items are
  unchanged from `env.md`: 6.18.49→6.18.50 and 7.2.3→7.2.4 remain unwalked deltas pending a
  reachable tree with those tags.
