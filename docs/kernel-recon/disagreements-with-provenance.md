# Disagreements with docs/patch-provenance.md

Generated 2026-07-15 06:48 UTC. Every record where independent re-derivation contradicts the prior doc — each was a candidate `60e08955f`-class error; all are tier-2 verified.

## `60e08955f` dualsense: give mute button and led to system.

- disposition: **misclassified** | severity cosmetic | silent
- doc ref: patch-provenance.md:337
- notes: MISCLASSIFIED in patch-provenance.md:337 (verbatim): '| `f84543926`, `0d60c3482`, `60e08955f`, `b76b4bc6a` | DualSense player LEDs / lightbar / mute / player-6 | **`8c0ab553b072`** *HID: playstation: expose DualSense player LEDs through LED class* (2021-09-08); **`8e5198a12d64`** *...add initial DualSense lightbar support* (2021-02-16) | 6.18 `hid-playstation.c:217` `update_player_leds`, `:155` lightbar flag. MiSTer's were pre-upstream backports. verify controller LED behaviour on HW (P3.13)'. Both cited vanilla SHAs verified to exist in /mnt/source/linux and are ancestors of v6.18.38 (`git me…

## `45283785a` hid-nintendo: add virtual combo led, don't warn by IMU compensation.

- disposition: **carried** | severity feature-loss | silent
- doc ref: patch-provenance.md:334
- notes: MISCLASSIFIED. patch-provenance.md:334 GROUPS four commits (`c4ec5cb40`, `9bdab534b`, `60821059c`, `45283785a`) into one Class-C 'drop — now upstream' row citing a single upstream SHA, `2af16c1f846b` ('HID: nintendo: add nintendo switch controller driver', 2021-09-11, v5.16), as the citation for all four. That upstream commit only introduced the BASE hid-nintendo driver (matches c4ec5cb40 and neighbors); it predates 45283785a by about a month in the fork's own history and never touched LED code beyond the stock player/home LEDs. Re-derived independently: `git log -S'combo' -- drivers/hid/hid-n…

## `60821059c` hid-nintendo: don't fail if home led is not present.

- disposition: **carried** | severity feature-loss | loud
- doc ref: patch-provenance.md:334
- notes: VERIFIED. Fork diff (drivers/hid/hid-nintendo.c, joycon_leds_create()) confirmed by `git show 60821059c`: both `return ret;` statements are commented out — (1) after `devm_led_classdev_register()` fails ('Failed registering home led'), (2) after `joycon_home_led_brightness_set()` fails ('Failed to set home LED dflt; ret=%d'). Both error paths become non-fatal in the fork.

Vanilla 6.18.38 history (all three SHAs confirmed via `git log`/`git show`/`git merge-base --is-ancestor` in /mnt/source/linux, checked out at tag v6.18.38):
- `2af16c1f846b` (2021-09-11, Daniel J. Ogorchock) is simply the o…

## `8908e0fe1` Fix module compile for Fanatec driver (#25)

- disposition: **carried** | severity feature-loss | loud
- doc ref: patch-provenance.md line 360
- notes: Build system fix for Fanatec wheel driver (HID). Changes Makefile to use composite module pattern: obj-$(CONFIG_HID_FTEC) += hid-fanatec.o with hid-fanatec-$(CONFIG_HID_FTEC) += hid-ftec.o hid-ftecff.o. This replaces the original incorrect pattern that listed both object files directly. Patch 0012-hid-fanatec.patch incorporates this fix in its Makefile hunk (lines 76-77), explicitly folding commits e82a5928, 8908e0fe, and ed8f8e6ce together. ESCALATION NOTE: patch-provenance.md groups this commit with e82a5928 and ed8f8e6ce in a single row (line 360), violating the one-commit-per-row contract;…

## `b76b4bc6a` dualsense: leds config for player 6.

- disposition: **carried** | severity cosmetic | silent
- doc ref: patch-provenance.md:337
- notes: SONNET ESCALATION VERIFICATION — every claim re-derived from scratch:

1. FORK DIFF (`git show b76b4bc6a` in /mnt/source/Linux-Kernel_MiSTer, +5/-4, drivers/hid/hid-playstation.c only): grows `static const int player_ids[6]` to `player_ids[7]`, appending `BIT(4) | BIT(0)` as the new index-6 pattern; changes the clamp `if(player_id > 5) player_id = 0;` to `if(player_id > 6) player_id = 0;`; and raises `ds->led.max_brightness` from 5 to 6 in ds_leds_create(). Indices 0-5 (off + players 1-5) are untouched byte-for-byte — this commit purely appends a 7th table entry and widens two bounds checks. C…

## `f84543926` dualsense: add player id led control.

- disposition: **carried** | severity feature-loss | silent
- doc ref: patch-provenance.md:337
- notes: SONNET ESCALATION VERIFICATION -- every link re-derived from scratch, all confirmed:

1. FORK (f84543926, `git show` in /mnt/source/Linux-Kernel_MiSTer): replaces the IDA-based `ps_device_set_player_id()`/`player_id` field with a single `struct led_classdev ds->led`, name `devm_kasprintf(dev, GFP_KERNEL, "%s:player_id", dev_name(dev))` where dev=&hdev->dev (the HID device, e.g. '0003:054C:0CE6.0001:player_id'), max_brightness=5, brightness_set_blocking=dualsense_player_led_brightness_set -> dualsense_set_player_leds(ds, brightness) (clamped >5 -> 0), registered in ds_leds_create() called from …

## `0d60c3482` dualsense: add lightbar color control.

- disposition: **dropped-upstream** | severity cosmetic | silent
- doc ref: patch-provenance.md:337
- notes: PROVENANCE DOC IS WRONG for this row. Verbatim, patch-provenance.md:337: '| `f84543926`, `0d60c3482`, `60e08955f`, `b76b4bc6a` | DualSense player LEDs / lightbar / mute / player-6 | **`8c0ab553b072`** *HID: playstation: expose DualSense player LEDs through LED class* (2021-09-08); **`8e5198a12d64`** *…add initial DualSense lightbar support* (2021-02-16) | 6.18 `hid-playstation.c:217` `update_player_leds`, `:155` lightbar flag. MiSTer's were pre-upstream backports. ⚠ verify controller LED behaviour on HW (P3.13) |'. Two errors: (1) it GROUPS four textually-and-functionally distinct fork commits…

## `9bdab534b` hid-nintendo: use default calibration if empty calibration is loaded.

- disposition: **dropped-upstream** | severity cosmetic | silent
- doc ref: patch-provenance.md line 334 (GROUPED ROW: c4ec5cb40, 9bdab534b, 60821059c, 45283785a)
- notes: CRITICAL ESCALATION ISSUE (from prior pass, still valid as context): This commit is listed in patch-provenance.md line 334 as part of a GROUPED ROW (4 commits: c4ec5cb40, 9bdab534b, 60821059c, 45283785a) labeled 'Switch Pro/Joy-Con backport + fixes' citing upstream commit 2af16c1f846b ('HID: nintendo: add nintendo switch controller driver', 2021-09-11, v5.16) -- that citation only covers the BASE driver addition, not this specific empty-calibration fix; the doc's specific claim for this sub-commit is imprecise. Re-derived independently: this fork commit predates the upstream driver's initial m…

## `af27afc4c` Update xpad driver (#63)

- disposition: **dropped-upstream** | severity none | silent
- doc ref: patch-provenance.md line 365 groups commits af27afc4c, f3c75eb02, a2242dd85, c035c21c0 as 'xpad deltas' carried in 0017-xpad-mister-deltas.patch, but the patch file header explicitly states 'NOT ported: af27afc4c' — this is a misclassification
- notes: This commit represents a wholesale resync of the fork's xpad.c driver with a version that incorporates upstream changes from 2022–2024. Vanilla 6.18.38 already includes all the substantive features this commit brings: (1) Event code constants: BTN_GRIPL/GRIPR/GRIPL2/GRIPR2 (0x224–0x227, verified at input-event-codes.h:605-608, exact match) for Xbox Elite paddle buttons; (2) ABS_PROFILE (0x21, input-event-codes.h:893) for profile selector (Xbox Adaptive Controller); (3) MAP_SHARE_BUTTON/MAP_PADDLES/MAP_PROFILE_BUTTON (xpad.c:83-85, exact match) and packet type detection (PKT_XBE1/XBE2_FW_OLD/FW…

## `b00a72159` Add support for NSO Mega Drive Controller (#50)

- disposition: **dropped-upstream** | severity feature-loss | silent
- doc ref: patch-provenance.md line 335 (GROUPED row: `e155f6a2f`, `2799f8b94`, `b00a72159`)
- notes: ESCALATION REQUIRED — GROUPED ROW in provenance.md: This commit is grouped with `e155f6a2f` (NSO NES/SNES) and `2799f8b94` (NSO N64), but must be analyzed independently (instructions §3). **Disposition analysis**: Fork commit (2023-09-04) precedes upstream 94f18bb19945 (2023-12-04). Vanilla 6.18.38 already includes NSO Genesis/Mega Drive support via 94f18bb19945, using `JOYCON_CTLR_TYPE_GEN (0x0D)` and `USB_DEVICE_ID_NINTENDO_GENCON (0x201e)` -- confirmed at hid-nintendo.c:322 and hid-ids.h:1067. **Key difference (equivalence=partial)**: Fork adds a product-ID forcing workaround (`git show b00…

## `0d8641a2b` Add rtl8188eu, rtl8188fu WiFi drivers.

- disposition: **dropped-deliberate** | severity none | None
- doc ref: patch-provenance.md line 389 (Class E table: plan is 'package/rtl8188eu, rtl8188fu, ... Do not vendor' -- that plan is itself superseded a second time in our actual defconfig, where both packages are sourced but left disabled in favor of mainline CONFIG_RTL8XXXU=m; the provenance doc predates and does not mention that later decision)
- notes: CORRECTED (Sonnet escalation, orchestrator-flagged internal contradiction). The prior version of this record was self-contradictory: its notes asserted 'ZERO in-kernel coverage ... adapter transparently unavailable ... regression vs stock' while its own dependencies.superseded_by simultaneously named package/rtl8188eu-aircrack-ng and package/rtl8188fu as the coverage. Both halves were wrong. Re-derived from the live checkouts: (1) configs/mister_de10nano_defconfig:568-569 explicitly disables BOTH packages ('# BR2_PACKAGE_RTL8188EU_AIRCRACK_NG is not set' / '# BR2_PACKAGE_RTL8188FU is not set')…

## `2548c2978` Support for i2c rtc mcp794xx.

- disposition: **dropped-deliberate** | severity feature-loss | silent
- doc ref: patch-provenance.md line ~4, grouped with 13 commits in single row
- notes: PROVENANCE DOC DISAGREEMENT: This commit is listed in patch-provenance.md as part of a GROUPED row with 12 other commits (aa8afe109..077c2c317), violating the grounding contract's requirement to analyze commits independently. This analysis treats it as a single commit.

FUNCTIONAL ASSESSMENT: This commit adds two RTC devices (&i2c1 rtc_at_68 and rtc_at_6F) using bare compatible strings ('m41t81' and 'mcp7941x', without vendor prefixes). Vanilla 6.18.38 supports these chips via rtc-m41t80.c and rtc-ds1307.c drivers. The bare compatible strings work via a fallback mechanism in of_i2c_register_de…

## `bbeff2c30` Enable Logitech D-Input drivers.

- disposition: **dropped-deliberate** | severity feature-loss | silent
- doc ref: NOT LISTED (old-branch-residue.md line 14)
- notes: CRITICAL: This commit is ONLY on MiSTer-v5.14 branch, NOT on MiSTer-v5.15 (stock). However, the same kconfig options (CONFIG_LOGITECH_FF=y and CONFIG_LOGIRUMBLEPAD2_FF=y) ARE enabled in v5.15's defconfig via commit 215e6e662 'Add defconfig' (2021-11-08). This represents a deliberate re-implementation: Sorgelig chose not to cherry-pick this v5.14 commit to v5.15, but instead replicated the functionality when creating the v5.15 defconfig. The commit is NOT listed in patch-provenance.md (which lists 11 defconfig commits at line 312, but not bbeff2c30). Both CONFIG_LOGITECH_FF and CONFIG_LOGIRUMBL…

## `115b1d1ae` Fix for edimax EW-7822ULC BUG #769  (#47)

- disposition: **dropped-obsolete** | severity none | silent
- doc ref: patch-provenance.md line 389 (Class E table row for 115b1d1ae): the doc's actual disposition for this row is 're-source' -> package/rtl8812au, rtl8821au, rtl8821cu, rtl88x2bu (P3.1), with an open action item: 'Verify the two local device fixes are present upstream or re-apply as package patches.' It does NOT say 'carried'. The first-pass record's disposition='carried' + agrees_with_provenance_doc=true both misread this row; this task performs the verification the doc's action item asked for.
- notes: CORRECTED from first-pass 'carried'. 'carried' has a precise meaning in this schema: shipped as a 00xx patch file in board/mister/de10nano/linux-patches/. There is no such patch (grep of the 25 files in linux-patches/ confirms no realtek-wifi entry), and there could not sensibly be one: our build does not vendor the fork's rtl8812au/rtl8821au/rtl8821cu/rtl88x2bu source trees at all. It re-sources RTL8812AU/RTL8821AU/RTL8814AU from independently-pinned, newer morrownr forks (package/rtl8812au, rtl8821au-morrownr, rtl8814au-morrownr) that already build cleanly against 6.18 and already lack the s…

## `38a039bab` rtl8821au: disable warnings.

- disposition: **dropped-obsolete** | severity cosmetic | silent
- doc ref: 3.6 Class E — Realtek USB WiFi (groups rtl8821au vendors/resyncs but does not list this commit)
- notes: rtl8821au was vendored in the Linux-Kernel_MiSTer fork but is NOT present in vanilla 6.18.38. It has been extracted to an out-of-tree Buildroot package (rtl8821au-morrownr, sourced from morrownr's actively-maintained fork) in P3.1. The warning suppressions (-Wno-cast-function-type, -Wno-enum-conversion) added here are already present in the current morrownr upstream Makefile (verified via git clone of morrownr/8821au-20210708 at HEAD). This commit is a follow-up compiler-flag fix applied during the kernel fork's active development but is not carried as a separate patch since the driver is no l…


**Total: 15 disagreements.**
