# Stable-drift verdicts — batch A (patches 0001–0004, 0010–0020)

Wave 1, `W1-drift-verdicts` (batch A of the fan-out over `stable-drift-6.18.39-49.md`).

## Grounding

- **Vanilla 6.18, upper bound**: `1c732c6b94f0faee1526bd375add2fe10cba2e26` = release commit
  "Linux 6.18.49" on `linux-6.18.y` (gregkh/linux mirror, `$S/linux`). This is **not** 6.18.50,
  the pin: the mirror lags one release and kernel.org is unreachable from this session
  (`env.md`, "The gap"). Every verdict and every `-F0` dry-run below is against 6.18.49, not
  .50. The 6.18.49→6.18.50 delta remains an open gap to be walked separately per `env.md`'s
  recipe once a tree with the `v6.18.50` tag is reachable.
- **Vanilla 6.18, lower bound**: `v6.18.39` = `f89c296854b755a66657065c35b05406fc18264d`
  (resolved via `v6.18.39^{commit}` — the annotated-tag trap `env.md` warns about; the bare
  `git rev-parse v6.18.39` on this mirror returns the tag object `e871c68dfd325de0…`, not the
  commit).
- **Input**: `docs/kernel-recon/fork-sync-2026-09/stable-drift-6.18.39-49.md` (Wave 0,
  `drift.py`), whole-file path intersection — a row exists whenever a stable commit touched
  *any* line of a file a carried patch also touches, not necessarily the same hunk. Determining
  actual hunk-region overlap is this document's job.
- **Range covered**: every carried patch numbered 0001–0004 and 0010–0020 in
  `board/mister/de10nano/linux-patches/` (15 files; 0005–0009 do not exist in the series).
  No patch was modified to produce this record.

---

## 1. Collision verdicts

Six collision rows fall in this range (all from `0002`, `0015`, `0017`, `0019` — the other
eleven patches in range have zero path collisions per the Wave 0 table).

| Patch | Path | Stable sha | Verdict | Evidence summary |
|---|---|---|---|---|
| `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model.patch` | `sound/drivers/dummy.c` | `f20c2c32ec1c` | **disjoint** | Stable inserts a 6-line card-index bounds check (`if (dev < 0 \|\| dev >= SNDRV_CARDS) …`) immediately **before** `err = snd_devm_card_new(...)` at old line 1017 in `snd_dummy_probe()`. Our hunk (`@@ -1023,6 +1056,10 @@`) anchors 6 lines later, on the 3 context lines `return err;` / `dummy = card->private_data;` / `dummy->card = card;`, to insert `dummy->model = m = &model_MiSTer;`. Different intent (defensive OOB-index guard vs. MiSTer default-model selection), no line-level intersection — the stable hunk sits entirely above our hunk's context window. Confirmed by build backstop: hunk applies at **offset +6, no fuzz** (§2). |
| `0015-hid-nintendo-nso-famicom.patch` | `drivers/hid/hid-nintendo.c` | `5efcd7bbfaae` | **disjoint** | Stable's whole diff is inside `nintendo_hid_probe()`'s error path (`err_close:`/`err_io_stop:` labels, old lines 2692–2730), fixing a use-after-free by calling `hid_device_io_stop()` before `hid_hw_close()`. None of our 5 hunks (old-file anchors 316, 443, 723, 1711, 2157) touch `nintendo_hid_probe()` or its error labels — they touch the ctlr-type enum, a new button-mapping table, two new `joycon_type_is_*_famicom()` inline helpers, `joycon_parse_report()`, and `joycon_input_create()`. Different function, unrelated intent (UAF fix vs. Famicom controller-type support). |
| `0015-hid-nintendo-nso-famicom.patch` | `drivers/hid/hid-nintendo.c` | `268679f50138` | **overlapping-compatible** | Stable moves `input_register_device(ctlr->input)` from the top of `joycon_input_create()` (removes 4 lines at old 2138–2141) to the bottom (adds 4 lines after old line ~2181, before `return 0;`). Our hunk (`@@ -2157,9 +2193,13 @@ static int joycon_input_create`) sits textually **inside that same function**, between stable's removal point and its insertion point — in the untouched if/else-if type-dispatch chain, where we add a `joycon_type_is_left_famicom()`/`joycon_type_is_right_famicom()` branch. Same region (one function), no line-level intersection, both edits are independent of each other's control flow (moving a registration call vs. adding a dispatch branch). Coexistence is not hypothetical: the `-F0` dry run applied our hunk cleanly at **offset −4, no fuzz** (§2) — the exact offset stable's 4-line move up top predicts. A manual re-anchor (were one desired) would only need to bump the hunk's second `@@` line number by −4; no context lines change. |
| `0015-hid-nintendo-nso-famicom.patch` | `drivers/hid/hid-nintendo.c` | `51cfd1adbe7a` | **disjoint** | Stable's diff is entirely inside `joycon_ctlr_read_handler()` (old lines 2559–2570), widening a length guard from `size >= 12` to `size >= sizeof(struct joycon_input_report)` to fix an OOB read on spoofed IMU reports. None of our 5 hunks touch `joycon_ctlr_read_handler()`. Different function, unrelated intent (a security bounds-check fix vs. controller-type support). |
| `0017-xpad-mister-deltas.patch` | `drivers/input/joystick/xpad.c` | `455dbb5bdd81` | **disjoint** | Stable adds two one-line device-table rows: `{ 0x3507, 0x000b, "ZENAIM LEVERLESS", …}` in the `xpad_device[]` table at old line ~429 (alphabetically between the Nacon `0x3285` and GameSir `0x3537` rows) and `XPAD_XBOX360_VENDOR(0x3507)` in `xpad_table[]` at old line ~592. Our `0017` has one hunk ending its context just before that point (`@@ -404,6 +416,8 @@`, up to the `0x2dc8` 8BitDo rows) and the next hunk starting after it (`@@ -434,6 +448,7 @@`, from `0x3651` CRKD on); stable's ZENAIM row lands in the untouched gap between them. The `xpad_table[]` edit at old 592 is nowhere near any of our 18 hunks at all. Different intent (new controller VID/PID vs. MiSTer-specific feature/quirk deltas), no line intersection. Downstream hunks in our patch pick up a cumulative **+1/+2 line offset, no fuzz** (§2) — exactly consistent with one 1-line insertion before hunk #5 and combined with our own later insertions. |
| `0019-hidpp-k400-fn-inversion.patch` | `drivers/hid/hid-logitech-hidpp.c` | `097fcf945d93` | **disjoint** | Stable removes one stale kernel-doc line (`* @dev: the input device for which events should be reported.`) from the `struct hidpp_scroll_counter` doc comment at old line 164 — a comment-only cleanup, no code change. Our 4 hunks are all far downstream (old-file anchors 3337, 3361, 3380, 4559), inside `m560_input_mapping()`, a new `k400_disable_tap_to_click()` function, `k400_connect()`, and the `hidpp_devices[]` ID table — all functional K400 FN-key-inversion code, nowhere near the struct doc comment. Different region entirely, unrelated intent. All 4 hunks apply at a uniform **offset −1, no fuzz** (§2), exactly the 1-line deletion propagating downstream. |

No row in this batch reached `superseded` or `conflicting` grade — see §3.

---

## 2. `-F0` dry-run backstop — all 15 patches in range

Method: for every patch, extracted every file named in its `+++ b/<path>` lines from
`$S/linux` at `1c732c6b94f0` (6.18.49) into a scratch tree preserving paths (new-file targets,
i.e. `--- /dev/null`, are simply absent — patch creates them), then ran
`patch -p1 -F0 --dry-run < <patch>` from that tree.

**Two of the fifteen fail in isolation — this is a series-ordering artifact, not stable drift.**
`0011-hid-guncon3.patch` and `0014-hid-gamecube-adapter.patch` edit `drivers/hid/Kconfig` and
`drivers/hid/Makefile` at anchors that assume the *preceding* carried patches in the series
(0010, 0012, 0013 for 0011; 0010–0013 for 0014) have already inserted their own `config
HID_…`/`obj-$(CONFIG_…)` lines — the real series is applied strictly in order by
`scripts/export-kernel-tree.sh` and the build, never as isolated single-file patches against a
pristine tree. To confirm this is not a drift signal, the full 0001→0020 sequence was also
applied **cumulatively, in order, non-dry-run**, against the same 6.18.49 sources
(`patch -p1 -F0` for real, each patch building on the previous patch's output): **every one of
the 15 patches applied cleanly, offsets only, zero fuzz, zero failures.** That sequential run is
the one that matches how the series is actually consumed.

| Patch | Isolated `-F0 --dry-run` vs 6.18.49 | Sequential (0001→0020, real apply) |
|---|---|---|
| `0001-fbdev-add-MiSTer_fb-driver.patch` | clean | clean |
| `0002-sound-add-…-dummy-MiSTer-model.patch` | Hunk #3 (`sound/drivers/dummy.c`) offset **+6**; rest clean | Hunk #3 offset +6; rest clean |
| `0003-cpufreq-cyclone5-de10nano-overclock.patch` | clean (0 collisions row) | clean |
| `0004-dts-de10nano-MiSTer.patch` | clean (0 collisions row) | clean |
| `0010-hid-guncon2.patch` | clean (0 collisions row) | clean |
| `0011-hid-guncon3.patch` | **FAIL** — Kconfig hunk #1 (anchor at 424), Makefile hunk #1 (anchor at 57), hid-ids.h hunk #1 (anchor at 1058) — all series-ordering, see above; `hid-guncon3.c` itself (the new file) applies clean | clean, no offsets |
| `0012-hid-fanatec.patch` | clean (0 collisions row) | clean |
| `0013-hid-flydigi-vader.patch` | Makefile hunk #1 offset **−4** (series-ordering: anchors past 0010–0012's insertions) | clean, no offset |
| `0014-hid-gamecube-adapter.patch` | **FAIL** — Kconfig hunk #1 (anchor 416), Makefile hunk #1 (anchor 55) — series-ordering; hid-ids.h hunk #1 succeeded at offset −4 (series-ordering, not a fail) | clean, no offsets |
| `0015-hid-nintendo-nso-famicom.patch` | Hunk #5 (`joycon_input_create`) offset **−4** — real drift, from stable `268679f50138`'s 4-line move (§1) | Hunk #5 offset −4 (same — this one is real drift, present even sequentially since nothing upstream of it in the series touches `hid-nintendo.c`) |
| `0016-hid-microsoft-elite2-paddles.patch` | clean (0 collisions row) | clean |
| `0017-xpad-mister-deltas.patch` | Hunks #5–#18 offset **+1 to +2** — real drift, from stable `455dbb5bdd81`'s two 1-line VID/PID insertions (§1) | same offsets (nothing upstream in the series touches `xpad.c`) |
| `0018-hid-controllable-quirk.patch` | clean (0 collisions row) | clean |
| `0019-hidpp-k400-fn-inversion.patch` | Hunks #1–#4 offset **−1** — real drift, from stable `097fcf945d93`'s 1-line doc-comment deletion (§1) | same offset |
| `0020-mmc-no-led-on-send-status.patch` | clean (0 collisions row; confirmed independently, §3) | clean |

**Zero fuzz, zero failures anywhere once series order is respected.** The only patches whose
offsets trace to a *collision* row are `0002`, `0015`, `0017`, `0019` — exactly the four patches
with collision rows in §1, and the offset magnitudes/directions match each stable commit's
line-count delta exactly (verified against each quoted hunk above). `0011`/`0013`/`0014`'s
isolated-run numbers are an artifact of testing single files out of series order, not evidence
of anything upstream.

---

## 3. Superseded / conflicting section

**Empty.** No row in this batch graded `superseded` or `conflicting`.

### PLAN §3 step 3 explicit check: `0020-mmc-no-led-on-send-status.patch`

Required even at zero path collisions. Two checks:

1. `git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/mmc/core/` returns exactly **one**
   commit:
   ```
   8d94498cc mmc: block: fix RPMB device unregister ordering
   ```
   `git show --stat 8d94498cc` confirms it touches only `drivers/mmc/core/block.c` (RPMB
   child/parent device unregister ordering, 1 insertion / 2 deletions) — unrelated to
   `core.c` or to LED handling. This corroborates Wave 0's 0-collision finding for `0020`
   rather than contradicting it.

2. Direct grep of the 6.18.49 tree for the behaviour itself. `drivers/mmc/core/core.c` at
   6.18.49, `mmc_start_request()`:
   ```c
   	if (host->uhs2_sd_tran)
   		mmc_uhs2_prepare_cmd(host, mrq);

   	led_trigger_event(host->led, LED_FULL);
   	__mmc_start_request(host, mrq);

   	return 0;
   }
   EXPORT_SYMBOL(mmc_start_request);
   ```
   (`core.c:356-364`). The `led_trigger_event(host->led, LED_FULL)` call is **unconditional** —
   no `MMC_SEND_STATUS` (or any other opcode) check guards it, byte-identical in shape to what
   `0020`'s header describes finding at the 5.15→6.18.38 forward-port. A tree-wide grep for
   `MMC_SEND_STATUS` across `drivers/mmc/` (10 hits: `mmc_ops.c`, `mmc.c`, `mmc_test.c`×3,
   `sdhci-uhs2.c`, `renesas_sdhi_core.c`, `dw_mmc.c`, `mmc_spi.c` comment) shows none of them are
   anywhere near LED/trigger code — `dw_mmc.c:267`'s `cmd->opcode != MMC_SEND_STATUS` guards a
   DMA/PIO choice, not the activity LED, and no `drivers/mmc/core/host.c` or `core.c` LED
   function references the opcode at all. **Mainline has not adopted the behaviour `0020`
   carries; the LED still flashes on every `MMC_SEND_STATUS` poll on 6.18.49.** `0020` is not
   superseded and remains necessary.

---

## 4. Conclusion

None of the six collisions in patches 0001–0004/0010–0020 are `superseded` or `conflicting`.
Four are cleanly `disjoint` (different functions/regions, unrelated intent: `0002` vs a
card-index bounds check, two of `0015`'s three collisions vs a UAF fix and an OOB-read fix,
`0017` vs a new controller VID/PID row, `0019` vs a stale kernel-doc line). One is
`overlapping-compatible` (`0015` vs `268679f50138`'s `input_register_device()` relocation
inside `joycon_input_create()` — same function, no line intersection, proven to coexist at a
clean −4-line offset). The explicit `0020` check (PLAN §3 step 3) confirms mainline still
flashes the activity LED unconditionally on `MMC_SEND_STATUS` at 6.18.49, so `0020` is not
superseded either. **No patch in this batch (0001–0004, 0010–0020) can retire.** Nothing
strictly *needs* re-anchoring for correctness — `patch -F0` already resolves every real-drift
offset automatically with zero fuzz and zero failures, confirmed both in isolation and in the
actual series-application order — but if the series is ever hand-rebased against a newer
vanilla tree, four hunks have known, quoted offsets to carry forward: `0002` hunk #3 (+6),
`0015` hunk #5 (−4), `0017` hunks #5–#18 (+1/+2, cumulative with our own insertions), and
`0019` hunks #1–#4 (−1). The two apparent isolated-run failures (`0011`, `0014`) are a testing
artifact of breaking series order, not a drift finding, and are moot once the patches are
applied in their real 0001→0020 sequence, which was verified clean end-to-end against 6.18.49.
This batch's evidence does not by itself close the "no patch retires" question for the whole
series — batch B (patches beyond 0020) and the `0028`/`0027`/`0030`/`0036`/`0047` explicit
rows are out of this batch's scope per the task assignment.
