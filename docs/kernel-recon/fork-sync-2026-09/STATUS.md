# Waves 0–2 status — read this first

**Run:** 2026-09-10, remote session, on branch `claude/kernel-6.18-patch-plan-l32pu9`.
**Executed:** Wave 0 (bring-up + enumeration), Wave 1 (12 analysis agents), Wave 2 (4 refutation
agents). **Not executed:** Wave 3 (no patch was authored, no config or doc changed, nothing
regenerated), Wave 4, Wave 5. This file is written for the owner reading on a phone: every
decision you need to make is in §3 with a recommendation and its single strongest reason; the
evidence is in the memos and records linked from each row.

## 0. One-paragraph outcome

Every item in the queue is now dispositioned with evidence, and **no hypothesis in PLAN §2 was
overturned** — but four facts came back different from what the plan assumed, and two of them
change what Wave 3 should do (§2). The stable-drift walk found **nothing that retires or breaks a
carried patch**: 42 collisions, all disjoint or compatible, and both patch series replay clean
at `-F0` (37/37 on 6.18, 40/40 on 7.2). Wave 2 confirmed every disposition, corrected three
citations, and refuted nothing. The two Opus memos both come down on the conservative side:
**keep our cpufreq driver** (option A, with two amendments) and **defer AIC8800** (option D).
One caveat runs through everything: the pinned kernels (6.18.50, 7.2.4) were **unreachable** from
this session, so every vanilla quote is from 6.18.49 / 7.2.3 — one stable release short. See
`env.md` for the one-command re-check that closes that gap.

## 1. Results per item

| Q | Item | Disposition | Planned action (Wave 3) | Wave 2 | Record / report |
|---|---|---|---|---|---|
| Q1 | `aec7dc3aa` TUN cherry-pick | dropped-deliberate (duplicate of `5fcfae369`; `CONFIG_TUN=y` already ours) | none | confirmed; stale path citation corrected; **Main_MiSTer now really does use `/dev/net/tun`** (A2065 Ethernet, landed 2026-07-26) — the July record's "zero hits" is out of date | `records/aec7dc3aa….json` |
| Q2 | `33a0521fd` RTW88_8821AU | dropped-deliberate (`CONFIG_RTW88_8821AU=m` since v10; 8821A/88XXA auto-selected; firmware shipped; Archer T2U Nano ID present) | none | confirmed by independent re-resolve | `records/33a0521fd….json` |
| Q3 | `ea2212221` fb ops (#83) | **carried**, re-implemented in `0001` | optional: align `0001` (and the beta copy) to `fb_sys_read/write` + `select FB_SYSMEM_FOPS` — recommended, zero risk (D4) | confirmed; one line-number citation fixed; the two read paths are proven byte-identical on ARM (`mmiocpy` *is* `memcpy` in `arch/arm/lib/memcpy.S`) | `records/ea2212221….json` |
| Q4 | `59bcae8eb` cpufreq port (#85) | needs-verification **by design** — owner decision D1 | see §3 | n/a (memo) | `memo-Q4-cpufreq.md`, `records/59bcae8eb….json` |
| Q5 | `7c75b1b46` xpad `skip_8bitdo_init` | **carried** → fold into `0017` as delta 5 | author the hunk in `0017`; applies at `-F0` on both 6.18.49 and 7.2.3 (offsets only) | confirmed; a wrong 6.18.49 line citation fixed | `records/7c75b1b46….json` |
| Q6 | `9854075c8` exFAT read-ahead plug (#88) | **carried** → `0050`, **fork code with Giancarlo Erra's authorship** (not a mainline backport) | author `0050` for the **6.18 series only** — see §2.1 | confirmed incl. the 7.x failure reproduction | `records/9854075c8….json` |
| Q7 | `e6f377e7d` defconfig update | dropped-deliberate (derived from Q2/Q3) | none | confirmed | `records/e6f377e7d….json` |
| Q8 | `41c45f378` Stadia-FF IDs (#91) | **carried** → `0048`, Main_MiSTer-coupled (six `input.cpp` sites) | author `0048` in all three series; applies clean at `-F0` on 6.18.49 and 7.2.3 | confirmed, all six citations exact | `records/41c45f378….json` |
| Q9 | `c129b0fac` AIC8800 driver | needs-verification **by design** — owner decision D2 | see §3 | n/a (memo) | `memo-Q9-aic8800.md`, `records/c129b0fac….json` |
| Q10 | PR #92 `a14b5e8e1` hid-nintendo 8BitDo adapter | **carried** → `0049`, unmerged, Main_MiSTer-coupled | author `0049` in all three series; applies clean at `-F0` on top of our eight hid-nintendo patches, on 6.18.49 and 7.2.3 | confirmed | `records/a14b5e8e1….json` |
| drift | v6.18.39 → 6.18.49, 42 collision rows, 37 patches | 41 disjoint, 1 overlapping-compatible, **0 superseded, 0 conflicting**; PLAN §3 explicit rows (0020/0027/0028/0030/0036/0047) all "still needed" | none; advance `_meta.vanilla_target` only to the 6.18.49 release commit, not .50 (env.md) | 17/17 sampled verdicts agree; both series replayed clean independently | `stable-drift-6.18.39-49.md`, `stable-drift-verdicts-{A,B}.md`, `w2-drift.md` |

Wave 2 reports: `w2-covered.md`, `w2-mainline.md`, `w2-coupling.md`, `w2-drift.md`. Three
records carry a `wave2_corrections` array documenting exactly what was changed and why.

## 2. What came back different from the plan

### 2.1 Q6 cannot go into the 7.x series — and does not need to
Mainline refactored directory read-ahead into a shared `exfat_blk_readahead()` helper (with the
plug) and `v7.2.3` already has that shape, so the fork's 4-line hunk **fails** against 7.2.3
(`2 out of 2 hunks FAILED`, reproduced twice). The RT and DE25 kernels therefore already have
the behaviour; `0050` is a **6.18-only** patch, omitted from `linux-patches-beta/series` and the
DE25 directory with that tag-level evidence in the `series` header — exactly the one admissible
reason the `series` rules allow. It is also not a mainline SHA to backport (no single mainline
commit is "this hunk"), so it is carried as fork code with the PR #88 author's `Signed-off-by`.

### 2.2 The boost sysfs contract — our docs are wrong, and it is user-visible today
Both cpufreq drivers (ours `0003` and the fork's) set `.set_boost = cpufreq_boost_set_sw` with
boost off and flag the 1000/1200 rows `CPUFREQ_BOOST_FREQ`. Consequence on **our shipped
kernel**: `/sys/devices/system/cpu/cpufreq/boost` **exists**, and `echo 1200000 >
scaling_max_freq` alone **clamps to 800000** until `echo 1 > …/cpufreq/boost` is written
(`memo-Q4-cpufreq.md` §4, core code quoted). `docs/abi-contract.md:1670` and
`docs/patch-provenance.md:798-804` say the opposite. This is (a) a doc fix regardless of D1,
(b) a note for `docs/user/` — community overclock scripts written for stock 5.15 need the extra
line — and (c) worth a 30-second hardware confirmation when you are back. It also kills option
C: its premise was that the two drivers differ here; they do not.

### 2.3 Nothing to carry from the fork's `compatible` change; carry the OCRAM reservation as hygiene
Vanilla 6.18.49 already has `"terasic,de10-nano"` in `socfpga_cyclone5_de10nano.dts:15`. The
`&ocram { flags-sram@f000 … }` reservation is real (the `sram` driver skips reserved children
when populating its pool) but the fork's rationale is wrong: Main_MiSTer's persistent flags live
in **DDR at `0x1FFFF000`** (`fpga_io.cpp:397,595`, `user_io.cpp:1336,1370`), not OCRAM;
`SOCFPGA_OCRAM_ADDRESS` is defined and never used. Carry the ten DTS lines into `0004` anyway
(zero cost, deterministic OCRAM allocation for any future consumer, and load-bearing if D1 ever
goes to B) — exact node text in memo §6.

### 2.4 Two small refutations of the plan's own text
PLAN §2.8 paraphrased the Stadia driver's start call as bare `HID_CONNECT_DEFAULT`; it is
`HID_CONNECT_DEFAULT & ~HID_CONNECT_FF` (no effect on the conclusion). PLAN §2.9 said our kernel
does not enable `CFG80211_WEXT`; it does (`linux.config:145`, a prompted symbol) — the
select-only symbol the vendor Makefiles key on is `WIRELESS_EXT`, so the AIC8800 wext shim still
compiles out, which the build confirmed.

### 2.5 A pre-existing ledger defect, found by running the invariant checker
`reduce.py` reports `ORPHAN carried patches: 0039, 0040, 0041, 0042` — those four patches
(added 2026-07-24) are named in `docs/patch-provenance.md` §11 but **no record's `carried_patch`
names them** (the schema has one `carried_patch` per record and their origin commits already
point at `0038`/`0032`/`0035`/`0042`'s siblings). This predates this increment and is a Wave 3
item: either allow a list in `carried_patch` or add the four to the originating records'
`notes` and teach `reduce.py` to read a `carried_patches` list. The regenerated ledger outputs
were deliberately **not** committed by this run — the ten new records would show planned
patches as carried before they exist.

## 3. Decisions for the owner

| # | Decision | Recommendation (from the memo) | Strongest reason | Default applied if you say nothing |
|---|---|---|---|---|
| D1 | cpufreq: keep `0003` (A) / adopt the fork's port (B) / hybrid (C) | **A**, plus two amendments independent of the choice: fix the boost-ABI docs (§2.2) and add the OCRAM reservation to `0004` (§2.3). Track B as bench-gated. **Strike C** (premise refuted). | Our `0003` does two of the fork author's three suspected hang causes (DDR execution through PLL bypass; single-step VCO jump, +50 % at 1200) — but it is the code stock shipped for four years and the only cpufreq code ever observed at 1.2 GHz on our own board (`docs/testlogs/p1-first-boot.md:118`). The fork's port applies and compiles `W=1`-clean on our tree, `=y` is viable, but it has **zero** validation on our image and its author lists open issues. Swapping proven-in-the-field for better-designed-but-unproven, with no bench, on the one patch that can hang a board mid-transition, is the wrong trade today. | A |
| D2 | AIC8800: package (P) / defer (D) / decline (X) | **D — defer.** | It compiles clean for 32-bit ARM (both `.ko`s link; the `rtl8852cu` `__aeabi_uldivmod` trap does not recur) and has zero USB-ID conflicts — but it is **inert without ~60 firmware blobs** that no source we can verify supplies (stock's 20260907 firmware tarball has none; the driver opens `/lib/firmware/…` with `filp_open`, not `request_firmware`), and the vendor tree ships **no license text**: 85 files with a bare copyright line and no grant, 51 with nothing, 2 Apache-2.0 (`aic_br_ext.{c,h}`), 1 SPDX tag (a third-party kprobes quirk that is dead code under our config anyway). Both blockers are answerable without hardware by identifying the upstream repo (the exact snapshot is stamped: `rwnx v6.4.3.0 - 1a4b0054d2M`, SDK `2026_0123_5f7be68d` — grep candidates in memo §1.2) and its firmware distribution. Packaging note for later: the two modules must be built in order with `KBUILD_EXTRA_SYMBOLS` (fdrv imports nine symbols from `aic_load_fw`), which Buildroot's single-`M=` kernel-module infrastructure cannot express as-is; measured cost ≈207 KB `.ko.xz`. | D |
| D3 | Carry the open PR #92 now | **Yes.** | "Gamepad unusable" class, hardware-verified A/B by its author on a DE10-Nano at 6.18.38, 32 lines, applies clean on top of our whole hid-nintendo stack on both kernels; Main_MiSTer hard-codes `057e_2009`. | yes |
| D4 | Align `0001` to upstream's `fb_sys_read/write` | **Yes** (also the beta copy). | Proven identical machine code on ARM; Main_MiSTer only ioctls `/dev/fb0`; shrinks the export diff. | follow the memo: yes |
| D5 | Run the two Opus workers | moot — they ran (≈0.50 M tokens total) | — | — |
| D6 | Wave 5 upstream PRs for `0038`–`0042` | unchanged: optional | — | prepare branches only when asked |

## 4. Hardware-gated items (for when you are at the board)

1. **Boost contract check** (30 s): `cat /sys/devices/system/cpu/cpufreq/boost`; `echo 1200000 >
   …/cpu0/cpufreq/scaling_max_freq` then `cat scaling_max_freq` (expect 800000 clamp); `echo 1 >
   …/cpufreq/boost` and repeat (expect 1200000). Confirms §2.2 on real hardware.
2. **`0003` at 1000 MHz** — the single largest evidence hole in D1: we have one accidental
   800→1200 data point and none at 1000. Memo §8 has the step list and what to watch.
3. 8BitDo USB Wireless Adapter in Switch mode (`057e:2009`) after `0049` lands.
4. Classic2USB / RetroZord rumble after `0048` lands.
5. Archer T2U Nano association on our image (Q2 says it should already work).

## 5. Grounding caveat, stated once more

The gregkh GitHub mirror lags one release (has `v6.18.49` and `v7.2.3`; `linux-6.18.y` head *is*
6.18.49) and every kernel.org host is blocked by the session proxy. All vanilla quotes are
therefore from **6.18.49 / 7.2.3**, not the pinned **6.18.50 / 7.2.4**. Records say so in
`verification`/`notes`. The `-F0` build against the real 6.18.50 tarball in CI is the loud
backstop; the silent half is one command per line in `env.md` once a tree with the tags is
reachable. `_meta.vanilla_target` must not be advanced past the 6.18.49 release commit until then.

## 6. Cost of Waves 0–2 (measured from agent reports)

| Wave | Agents | Tokens (sum of subagent reports) |
|---|---:|---:|
| 1 — Haiku (Q1, Q2, Q7) | 3 | ≈0.21 M |
| 1 — Sonnet (Q3, Q5, Q6, Q8, Q10, drift A, drift B) | 7 | ≈0.87 M |
| 1 — Opus (Q4, Q9) | 2 | ≈0.50 M (each ran ~20 min incl. a kernel `prepare` and an ARM build) |
| 2 — Sonnet (covered, mainline, coupling, drift) | 4 | ≈0.63 M |
| **Total** | **16** | **≈2.3 M** — well under the plan's 5–8 M estimate for these waves |
