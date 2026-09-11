# Fork-sync increment 2026-09 — plan: reconcile against the shipped stock 6.18 kernel

**Status:** Waves 0–5 executed 2026-09-10/11 (see [`STATUS.md`](STATUS.md) §7–§8). Wave 5 output is
prepared, not sent. Written
2026-09-10 on branch `claude/kernel-6.18-patch-plan-l32pu9`. Every fact in §1 was measured in this session from
the live upstream repositories and the stock release artifacts; every disposition in §2 is a
**hypothesis** for the Wave 1 workers to test, in the sense `MISTER-KERNEL-PATCH-RECON.md` §0
gives that word.

**What changed.** On 2026-09-07 stock MiSTer shipped its first 6.18 kernel
(`Linux_Image_creator_MiSTer` "Release 20260907", kernel `6.18.38-MiSTer`). Within four days
users found regressions in it and the fork (`MiSTer-devel/Linux-Kernel_MiSTer`, branch
`MiSTer-v6.18`) took eight commits and one still-open PR to address them. None of that is
reconciled here yet: `docs/kernel-recon/fork-sync.conf` records `MiSTer-v6.18` as reconciled
through `6332499e7` (2026-08-24), and the fork's HEAD is now `c129b0fac` (2026-09-11).

**Why this increment is different from the previous two.** Until now `MiSTer-v5.15` was the
source of truth for *what stock has* and `MiSTer-v6.18` was evidence about a port in progress
(`fork-sync-2026-07.md` §1, "Baseline note"). That inverts as of 20260907: **`MiSTer-v6.18` is
now what every stock MiSTer runs**, and `MiSTer-v5.15` is frozen history (HEAD `5fcfae369`,
unchanged since 2026-07-24, still equal to our sync point). Two consequences run through
this whole plan:

1. A fork commit on `MiSTer-v6.18` is now a **stock-parity** question, not a port question.
   The "dispositioned ≠ closed" lesson of the last increment (`fork-sync.conf`, "READ THIS
   BEFORE TRUSTING THE [ok]") applies with full force.
2. For the first time we can measure **stock 6.18 regressions our image does not have** —
   and there are several (§4.3). They matter for two reasons: they are the answer to "why
   would anyone run this image", and they are the material for PRs back to the fork.

---

## 0. TL;DR

| | |
|---|---|
| **Queue** | 8 new commits on `MiSTer-v6.18` past `6332499e7` (one is a cherry-pick already dispositioned), **1 open PR** (#92), 3 closed-unmerged PR heads that are duplicates of merged commits. `MiSTer-v5.15`: nothing new. No new fork branches. Full list §1.3. |
| **Stock release facts** | 20260907 = `MiSTer-v6.18` @ **`aec7dc3aa`** exactly (IKCONFIG-extracted config is byte-identical to that commit's `MiSTer_defconfig`; measured §1.2). Everything after it is a post-release fix. |
| **Already covered by us** | fb `mmap` fix (#83) — our `0001` fixed this in July; `CONFIG_RTW88_8821AU=m` (#81) — already in `linux.config`; `CONFIG_TUN` (the cherry-pick) — already carried. To be *verified*, not assumed (§2). |
| **Carry candidates** | Stadia-FF device IDs for Classic2USB/RetroZord (#91, Main_MiSTer-coupled); exFAT dir read-ahead plug (#88); xpad `skip_8bitdo_init` param; **PR #92** (8BitDo adapter makes hid-nintendo reset-loop — "gamepad unusable", hardware-verified by its author); the OCRAM `flags-sram` DTS reservation buried inside the cpufreq commit. |
| **Two real decisions** | (a) **cpufreq**: the fork replaced the driver we carry as `0003` with a new CCF-integrated, OCRAM-resident, opt-in-boost implementation (#85). Keep ours, adopt theirs, or hybrid — §2.4. (b) **AIC8800**: a 70 k-line vendored USB Wi-Fi/BT driver landed in-tree upstream with no firmware shipped yet and no SPDX headers. Package it, defer it, or decline — §2.9. |
| **Retire candidates** | None retire outright this increment. `0047` retires by rule when the pin leaves 6.18.y. `0003` is *replaced*, not retired, if decision (a) goes upstream's way. The 6.18.39→6.18.50 stable-drift check (§3) is the only thing that could retire a patch, and it has never been run past .39. |
| **Fan-out** | 5 waves, **~27 agent runs** (+8 conditional): 6 Haiku, 18 Sonnet, 2 Opus, 1 Opus/orchestrator audit. Cost table §5.4. Roughly a day of wall-clock with Waves 1–3 parallelised. |
| **Blocking owner decisions** | The two above, plus "carry an unmerged PR (#92) now?" — §7. Everything else proceeds on stated defaults. |

---

## 1. What is new upstream — measured

### 1.1 The stock release

`MiSTer-devel/Linux_Image_creator_MiSTer` commit `d4e3f51ec7fdd18116562d38bace9ef7dffe0f38`
("Release 20260907.", Sorgelig, 2026-09-07) replaced every binary in that repo:

| Artifact | Old → new size | sha256 (new) |
|---|---|---|
| `zImage_dtb` | 7,380,857 → 8,564,005 | `0bec449e365e757d14711bead76c5b1805d2b613a39e633fe7dc9f08e5687e73` |
| `modules.tar.gz` | 24,992,422 → 45,546,423 | `9a866063e095f3527d20d69638e37ad011cafce979fad7edc94a5bdbab2a6c2a` |
| `firmware.tar.gz` | 1,691,298 → 6,018,350 | `8a6ab6730e5a4b0ee978cae98a15fd8505e5605074cd34018adac0ac43359f78` |
| `rootfs.tar.bz2` | 82,617,954 → 82,661,550 | (not inventoried here — rootfs parity is `docs/stock-reconciliation.md`'s job and is out of scope for a *kernel* increment; flagged in §8) |
| `addon.tar` | unchanged | — |

Extracted in this session with the repo's own tooling
(`scripts/inventory/kernel_extract.py`, no network, ~10 s) and committed as text under
`evidence/`:

- `evidence/stock-20260907-linux.config` — the IKCONFIG `.config` of the shipped kernel
  (4,659 lines). **This is the new stock baseline for the config axis**, superseding
  `docs/stock-inventory/20250402/stock-linux.config` (5.15) for every future parity question.
- `evidence/stock-20260907-modules.txt` — `modules.tar.gz` contents: **89 modules** under
  `lib/modules/6.18.38-MiSTer/`. Notable: `xpad`, `hid-vader4`, the full `xone-*` set, the
  entire mainline `rtw88`/`rtw89`/`mt76`/`ath` USB set. Notable by absence: **no
  `rtw88_8821au.ko`**, **no cpufreq driver of any kind**, no `aic8800*`.
- `evidence/stock-20260907-firmware.txt` — `firmware.tar.gz` contents, 89 files. Now
  includes `rtw88/rtw8821a_fw.bin`, `rtw89/*`, `mediatek/mt7925/*`, `ath10k/QCA9377`.
  **No AIC8800 firmware.**

Stock's 5.15-era `stock-mods.txt` had 52 out-of-tree-heavy modules (`8188eu`, `8812au`,
`8821au`, `8821cu`, `88x2bu`, …). All of those are gone from stock 6.18; stock has
independently arrived at the mainline-first posture ADR 0016 chose in July.

### 1.2 Which fork commit stock was built from — settled

The shipped `.config` was diffed against `arch/arm/configs/MiSTer_defconfig` at every
candidate commit on `MiSTer-v6.18`:

| Fork commit | `diff` lines vs shipped config |
|---|---:|
| `6332499e7` (our sync point) | 2 |
| **`aec7dc3aa`** (TUN cherry-pick, 2026-07-24 author date, applied after `6332499e7`) | **0** |
| `33a0521fd` (#81, RTW88_8821AU) | 2 |
| `ea2212221` (#83, fb ops) | 2 |
| `59bcae8eb` (#85, cpufreq) | 3 |
| `e6f377e7d` (defconfig update) | 6 |
| `c129b0fac` (AIC8800, HEAD) | 9 |

**Stock 20260907 is `MiSTer-v6.18` @ `aec7dc3aa`, kernel 6.18.38.** Everything from
`33a0521fd` onward post-dates the release and was prompted by it. Corroborated by the module
list: no `rtw88_8821au.ko` (the #81 fix is not in the release) and the shipped config still
has `# CONFIG_RTW88_8821AU is not set` (line 1682).

Two direct consequences for stock users, both of which our image already handles (§2.2,
§2.3): on stock 20260907, `mmap(/dev/fb0)` returns `-ENODEV` (Console Mode / SDL 1.2 fbcon
cannot start — #83's own description) and Archer T2U Nano-class 8811AU/8821AU dongles have
no driver at all (#81).

### 1.3 The queue — `MiSTer-v6.18` since `6332499e7`

`evidence/fork-commits-since-6332499e7.tsv`, oldest first (author dates; `aec7dc3aa` was
*committed* after `6332499e7` despite its July author date):

| # | SHA | Date | Author | Subject | Files | ± |
|---|---|---|---|---|---|---|
| Q1 | `aec7dc3aa` | 2026-07-24 | Nigel Shearman | config: enable CONFIG_TUN for tap device support (#76) | `MiSTer_defconfig` | +1/−1 |
| Q2 | `33a0521fd` | 2026-09-08 | Julian Seitz / RenderBr | config: enable CONFIG_RTW88_8821AU for Realtek 8821AU/8811AU USB adapters (#81) | `MiSTer_defconfig` | +1/−1 |
| Q3 | `ea2212221` | 2026-09-08 | Takiiiiiiii | fbdev: MiSTer_fb: declare explicit fb_ops for read/write/mmap (#83) | `fbdev/Kconfig`, `MiSTer_fb.c` | +5 |
| Q4 | `59bcae8eb` | 2026-09-08 | Kasper Olesen | Port MiSTer CPUFreq to Linux 6.18 with opt-in turbo (#85) | 12 files: `clk/socfpga/clk-mister-cpu.c` (+343), `clk-mister-ocram.S` (+194), `clk-mister-ocram.h`, `clk-periph.c`, `clk-pll.c`, `clk.h`, `cpufreq/socfpga-cpufreq.c` (+111), `Kconfig.arm`, `Makefile`s, DTS `socfpga_cyclone5_de10_nano.dts` (+11/−1), defconfig | +697/−5 |
| Q5 | `7c75b1b46` | 2026-09-08 | Kasper Olesen | Input: xpad - add opt-in 8BitDo initialization bypass | `xpad.c` | +9/−1 |
| Q6 | `9854075c8` | 2026-09-09 | Sorgelig (re-authored from PR #88, Giancarlo Erra) | exfat: speed-up dir read-ahead. | `fs/exfat/dir.c` | +4 |
| Q7 | `e6f377e7d` | 2026-09-09 | Sorgelig | Update defconfig. | `MiSTer_defconfig` | +3 |
| Q8 | `41c45f378` | 2026-09-09 | Porkchop Express (misteraddons) | Adapt Classic2USB and RetroZord HID force feedback support (#91) | `hid-google-stadiaff.c` | +2 |
| Q9 | `c129b0fac` | 2026-09-11 | Sorgelig | Add AIC8800 WiFi/BT driver. | 143 files, `drivers/net/wireless/aic8800/**` + wireless `Kconfig`/`Makefile` + defconfig | ≈ +70,000 |

Plus, from `evidence/fork-refs-2026-09-10.txt` (PR refs are fetchable over git even though
the GitHub API is not reachable from this environment — §5.1):

| PR | State (from refs) | Head | Relation to the queue |
|---|---|---|---|
| **#92** | **open** (has a `refs/pull/92/merge`) | `a14b5e8e1c` — Michał Kopeć, 2026-09-10, *HID: nintendo: skip baudrate setup for 8BitDo adapters*, `hid-nintendo.c` +20/−12 | **Q10 — not merged, in the queue anyway** (§2.10) |
| #81, #83, #91 | merged | as above | = Q2, Q3, Q8 |
| #85 | merged (squashed) | `d49875d491`, a 3-commit series: *cpufreq: port…*, *ARM: socfpga: reserve OCRAM tail for MiSTer persistent flags*, *ARM: configs: build MiSTer CPUFreq as an opt-in module* | = Q4. The unsquashed form is the better review input — it separates the DTS reservation from the driver. |
| #86 | closed, not merged | `ca8459023d` | duplicate of Q5 (same diff, "for testing" in the subject) |
| #88 | closed, not merged | `97887b3413` | duplicate of Q6 (same 4-line diff; Sorgelig re-committed it under his own subject) |
| #90 | closed, not merged | `02ed6e7200` | duplicate of #91/Q8 |

Referenced but **unreadable from here**: fork issue #84 (the 8BitDo reconnect regression Q5
investigates). See §5.1 for the access constraint and the human step it implies.

### 1.4 Our side, as it stands

| | |
|---|---|
| Pinned kernel | **6.18.50** (`configs/fragments/de10nano.fragment:30`, hash in `board/mister/de10nano/patches/linux/linux.hash:39`). Stock is on 6.18.38. |
| Recon grounding | `commits.jsonl` `_meta.vanilla_target` = **v6.18.39**. The `_meta` note from 2026-08-24 says the .40–.45 re-check across the 125 records "has not been done". It is now .40–.50 and still has not. §3. |
| Carried series | `board/mister/de10nano/linux-patches/` — 37 files (`0001`–`0004`, `0010`–`0020`, `0022`–`0042`, `0047`). Beta (7.2.4) series: 36 shared + `0043`–`0046`. DE25 (7.2.3) series: `0010`–`0042` shared + `0101`, `0102`. Any new shared patch has **three** series to land in. |
| Records | 126 in `docs/kernel-recon/records/`, 126/126 tier-2 verified, `reduce.py` invariants 0 problems as of 2026-08-24. |
| Fork branches | Still exactly five (`MiSTer-v5.13.12`, `MiSTer-v5.14`, `MiSTer-v5.15`, `MiSTer-v6.18`, `origin`). The §8.3 branch-inventory gap from the last increment is closed *for this pass* by `evidence/fork-refs-2026-09-10.txt`; it is still not automated. |

---

## 2. Preliminary dispositions — hypotheses for Wave 1

One row per queue item. "Hypothesis" is what the orchestrator expects the worker to find;
the worker's job is to refute it with source evidence. Grounding tree for every claim below
is **v6.18.50** (the pin), not the 6.18.38 stock builds on — the worker-instructions
"Which vanilla version" rule.

### 2.1 Q1 `aec7dc3aa` — CONFIG_TUN cherry-pick — **duplicate, no action** — Haiku

Byte-identical hunk to `5fcfae369` on `MiSTer-v5.15`, which has record
`records/5fcfae36975b217f6ab82b501065f3b13173ae15.json` and is acted on
(`linux.config:175`, `CONFIG_TUN=y`). Record it as `dropped-deliberate` with
`dependencies.duplicate_of = ["5fcfae369…"]`, capability supplied by `linux.config`. Worker
must still confirm `CONFIG_TUN=y` survives `olddefconfig` on v6.18.50 (the NFS_V3 trap).

### 2.2 Q2 `33a0521fd` — CONFIG_RTW88_8821AU — **already provided; verify** — Haiku → Sonnet spot-check

`board/mister/de10nano/linux.config:623` has had `CONFIG_RTW88_8821AU=m` since the v10 Wi-Fi
expansion (`docs/wifi-parity.md` §6.4, ADR 0016). Hypothesis `dropped-deliberate` (capability
provided), exactly the `CONFIG_MACVLAN`/`CONFIG_TUN` precedent. Worker checks: (1) resolved
config on v6.18.50 still yields `RTW88_8821AU=m` **and** the auto-selected `RTW88_8821A=m` /
`RTW88_88XXA=m` core (Q7 adds `RTW88_8821A=m` explicitly — confirm we get it by `select`);
(2) `rtw88/rtw8821a_fw.bin` is in our image (`BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88` glob);
(3) the commit's motivating device, TP-Link Archer T2U Nano `2357:011e`, is in v6.18.50's
`rtw8821au.c` ID table. Note for §4.3: stock 20260907 users have no driver for this chip;
ours have had one since July.

### 2.3 Q3 `ea2212221` — MiSTer_fb explicit fb_ops — **already fixed in `0001`; verify equivalence and decide alignment** — Sonnet

Our `0001-fbdev-add-MiSTer_fb-driver.patch` forward-port note (1) identified the same
v6.8 commit `8813e86f6d82` in July and resolved it with `__FB_DEFAULT_IOMEM_OPS_RDWR` +
`__FB_DEFAULT_IOMEM_OPS_MMAP` and `select FB_IOMEM_FOPS` (patch lines 82–135). Upstream's
fix, two months later, uses `fb_sys_read`/`fb_sys_write` + `fb_io_mmap` and selects **both**
`FB_SYSMEM_FOPS` and `FB_IOMEM_FOPS`. Same bug, same `mmap` path, different read/write
helpers. Hypothesis: `carried`, `carried_mode: re-implemented`, `carried_patch: 0001`,
`equivalence: equivalent` for mmap and **`partial` for read/write** pending the worker's
answer to one concrete question: for a `memremap()`'d reserved-RAM window on ARM, do
`fb_io_read` (uses `memcpy_fromio`/`__iomem` accessors) and `fb_sys_read` (plain `memcpy`)
behave identically for `read(2)`/`write(2)` on `/dev/fb0`? `0001`'s header argues *iomem*
is the correct variant ("this window is FPGA memory above the…"); upstream argues *sysmem* is
("valid kernel mapping"). Both work in practice; the worker decides whether to align to
upstream's choice to shrink the export diff against `MiSTer-v6.18`, or keep ours and record
why. Whichever wins, the record must quote both hunks. Not a behaviour change for
Main_MiSTer (it `mmap`s; it does not `read`).

### 2.4 Q4 `59bcae8eb` — the cpufreq port (#85) — **decision required; Opus**

This is the one item that is not a small carry. Facts:

- **Stock 6.18 shipped with no cpufreq driver at all** (§1.1: no `ARM_SOCFPGA_CPUFREQ` in
  the shipped config, no module). Sorgelig did not port the 5.15 overclock driver; #85 is a
  community re-implementation that restores it, and stock 20260907 users currently have no
  overclock. We have had one since July: `0003-cpufreq-cyclone5-de10nano-overclock.patch`
  (Michael Huang's driver, forward-ported, `CONFIG_ARM_SOCFPGA_CPUFREQ=y`, 1000/1200 MHz
  rows flagged `CPUFREQ_BOOST_FREQ`).
- **The two implementations differ in kind**, not just in code. Ours reprograms the clock
  manager directly from the cpufreq driver, behind the CCF's back (its header says so and
  explains why cpufreq-dt cannot be used). Upstream's is split into a **clock provider**
  (`drivers/clk/socfpga/clk-mister-cpu.c`, hooks into `clk-periph.c`/`clk-pll.c` so sibling
  counters are compensated and the TWD timers get rate-change notifications) plus a thin
  cpufreq driver, and it runs the PLL retune **from a reserved OCRAM page under
  `stop_machine`** with bounded polling, incremental VCO steps, `OUTRESETALL`, and rollback —
  because its first attempt "hung on the 800 → 1000 MHz transition" executing from DDR while
  gating FPGA-facing clocks. **Whether our `0003` has that hang is an open question**: the
  origin commit `e6df8e30e` ("Improve clock transition stability") was the 5.15 fork's own
  answer to instability, and we have no hardware evidence either way at 1000/1200 on 6.18.
- **Config policy conflict.** Upstream builds it `=m` ("opt-in module", so a default boot
  never loads it). Our standing rule is `=y` for MiSTer-critical drivers because module
  autoload is unreliable when the module directory name does not match `uname -r`
  (`fork-sync-2026-07.md` §2). If we adopt theirs we must decide `=y` vs `=m` + explicit
  `modprobe` in init.
- **ABI.** Both expose standard cpufreq sysfs. `docs/abi-contract.md:1670` records for
  `0003` that there is **no** `…/cpufreq/boost` file and community scripts overclock via
  `scaling_max_freq`. Upstream's commit says "6.18 creates available/boost frequency
  attributes in the core" and boost is off by default — so on upstream's driver
  `scaling_max_freq` alone may not reach 1200 MHz until `boost` is written. That is a
  **behaviour change for the community overclock scripts**, in either direction, and must
  be stated in the record and in `abi-contract.md`.
- **Two side-changes ride inside the commit and are separable** (the PR #85 3-commit form
  separates them): (i) DTS: `compatible` gains `"terasic,de10-nano"` at the front — worker
  checks whether vanilla v6.18.50 `socfpga_cyclone5_de10nano.dts` already has it (our `0004`
  patches the vanilla file, upstream keeps its own copy); (ii) DTS: an `&ocram` child
  `flags-sram@f000 { reg = <0xf000 0x1000>; }` reserving the last 4 KiB of OCRAM from
  `gen_pool` because **Main_MiSTer keeps persistent flags there across core loads and
  reboots**. That reservation is a **stock-parity/robustness item independent of the
  cpufreq decision** — today nothing stops a future in-kernel `sram` allocation from landing
  on MiSTer's flag page. Hypothesis: carry (ii) into `0004` regardless; carry (i) only if
  vanilla lacks it.
- Upstream's own validation caveats are in the commit message and are honest: "Long-duration
  1200 MHz stability remains under test", "MiSTer Pi and SuperStation hardware have not been
  tested", an unexplained "OSD movement was reported during scripts".

**Options for the owner (§7):**

| Option | What it means | Risk |
|---|---|---|
| A. Keep `0003`, record Q4 `dropped-deliberate` (different implementation of a capability we carry), carry only the DTS reservation | Least work; our export diverges further from upstream's tree in `drivers/clk` and `drivers/cpufreq` | If the DDR-execution hang is real on our driver too, we ship it; we have no evidence either way |
| B. Adopt upstream's port, retire `0003`, carry Q4 as `0003` v2 (`=y`) + DTS hunks into `0004` | Export matches upstream; benefits from their OCRAM/`stop_machine` design; boost semantics change for scripts | New 700-line driver we did not write; their own "unresolved" list; needs [HW] at all four operating points |
| C. Hybrid: adopt upstream's clock provider + driver but keep boost enabled-by-default to preserve the `scaling_max_freq`-only script contract | Best of both if it works | Deviates from upstream's opt-in intent; still needs [HW] |

Recommended default if the owner does not answer: **A now, B as a tracked follow-up gated
on hardware time** — because A is zero-risk to the shipped image and B cannot be validated
without a DE10-Nano on the bench. The Opus worker's deliverable is the comparison that lets
the owner choose with evidence rather than this table (§5.2, W1-Q4).

### 2.5 Q5 `7c75b1b46` — xpad `skip_8bitdo_init` — **carry, default-off** — Sonnet

Nine lines: a `bool` module parameter, default `false`, that skips the Xbox-360 vendor init
request for USB `2dc8:3106` only. Zero behaviour change unless a user opts in; exists so
stock users can A/B the reconnect failure in fork issue #84. Our `0017-xpad-mister-deltas`
already owns `xpad.c`'s MiSTer deltas and already declares the `cpoll` parameter at the same
spot the new one is inserted, so the hunk anchors on our own context. Hypothesis: `carried`,
folded into `0017` as delta 5 (with a header note that it is an experimental switch, not a
quirk — the commit's own words), applied to all three series. Worker also checks whether
v6.18.50's `xpad_start_input()` still has the `XTYPE_XBOX360` init block in the same shape
(the fork is on 6.18.38; stable may have moved it).

### 2.6 Q6 `9854075c8` (= PR #88) — exFAT directory read-ahead plug — **carry, likely as a mainline-attributed backport** — Sonnet

Four lines: wrap the `sb_breadahead()` loop in `exfat_dir_readahead()` with
`blk_start_plug`/`blk_finish_plug`, "matching the allocation-bitmap implementation". A
throughput fix for large directories — the MiSTer file browser over big game folders is
exactly the workload. Two checks decide the form: (1) **is it in mainline?** grep
`fs/exfat/dir.c` at `v7.3-rc*` (and `git log -S'blk_start_plug' -- fs/exfat/`) — if mainline
has it, this is the `0047` pattern: carry as a backport with mainline authorship, and add
"absent from 6.18.y because no `Cc: stable`" evidence by tag; if not, carry as fork code with
Giancarlo Erra's authorship (the PR head `97887b3413` carries his `Signed-off-by`; the merged
commit does not — the record should cite both SHAs); (2) **the 7.x series**: `0031` already
needed a re-anchored beta copy because 7.x exFAT is iomap-based — the worker must check
whether `exfat_dir_readahead()` still exists in 7.2.4/7.2.3 in this shape, and whether the
plug is already there. It touches `fs/exfat/dir.c`, which `0031` also touches — verify the
hunks are in different regions (the last increment found `0031` vs a stable `dir.c` fix were
disjoint; same check).

### 2.7 Q7 `e6f377e7d` — defconfig update (+3) — **config axis, fully derived from Q2/Q3/Q4** — Haiku

`CONFIG_ARM_SOCFPGA_CPUFREQ=m` (→ Q4 decision), `CONFIG_RTW88_8821A=m` (→ Q2, auto-selected),
`CONFIG_FB_SYSMEM_FOPS=y` + `CONFIG_FB_IOMEM_FOPS=y` (→ Q3). No independent content;
record it `dropped-deliberate` with `superseded_by` pointing at the three records. The
`AIC8800*` lines come from Q9, not this commit.

### 2.8 Q8 `41c45f378` (#91) — Stadia-FF IDs for Classic2USB / RetroZord — **carry as new shared patch** — Haiku draft, Sonnet verify

Two `hid_device_id` rows in `hid-google-stadiaff.c` (`16d0:1460` Classic2USB / Reflex Adapt,
`1209:595a` RetroZord) matched with `HID_GROUP_GENERIC`, so the Stadia rumble driver claims
those adapters and their force feedback works. **Main_MiSTer already special-cases exactly
these two IDs** (the VID/PID predicate at `input.cpp:52-53`, `input.cpp:4176-4177`
`make_unique()`, plus NeGcon/Guncon paths at `:5101` and `:5348`) — the userspace coupling
is direct, which under §7.2 of the recon spec makes this "must not drop silently".
`CONFIG_HID_GOOGLE_STADIA_FF=y` is already in our `linux.config:410`, so the two lines are
the whole gap. Checks: mainline status at `v7.3-rc*` (if upstreamed, `0047` pattern);
`hid-google-stadiaff` binding must not rename the input device — Main_MiSTer matches on
`name`/`uniq` strings like `RZordPsWheel`, and a driver takeover that changed the reported
name would break those paths (the driver calls `hid_hw_start(HID_CONNECT_DEFAULT)`, so it
should not, but quote it). New number: **`0048`**, in all three series.

### 2.9 Q9 `c129b0fac` — AIC8800 Wi-Fi/BT driver — **decision required; do not carry in-tree; Opus review + Sonnet packaging if approved**

Facts from the tree (not from the commit message, which is one line):

- 143 files, ≈70 k lines, `drivers/net/wireless/aic8800/{aic8800_fdrv,aic_load_fw,aic_zlp_quirk}`.
  RivieraWaves/AICSemi vendor driver (`Copyright (C) RivieraWaves 2012-2019` headers,
  `MODULE_LICENSE("GPL")` in the three module entry points, **no SPDX tags**). Kconfig:
  `AIC8800_WLAN_SUPPORT` `depends on USB && CFG80211`; defconfig sets `AIC8800=y`,
  `AIC8800_WLAN_SUPPORT=m`, `AIC_LOADFW_SUPPORT=m`. USB ID table covers the AIC8800 family
  plus Tenda U2/U11/U11 Pro dongles (`aicwf_usb.c:2641-2668`).
- It needs firmware loaded from `/lib/firmware` by `aic_load_fw` (`FW_NAME "fw.bin"` plus
  per-chip files). **The stock release does not ship any** — the commit post-dates it —
  and no fork or LIC commit adds it yet. A driver without firmware is inert.
- It includes a `wext` shim (`aicwf_wext_linux.c`); our kernel does not enable `CFG80211_WEXT`
  (select-only symbol, the same hazard every `rtl*` package note records).
- Mainline has no `aic8800` driver in 6.18. Worker must verify against `v7.3-rc*` too — a
  mainline driver appearing later would flip this to "wait for mainline".

Policy: ADR 0016 permits an out-of-tree driver only for a chip mainline cannot drive
(precedent: `package/rtl8852cu-morrownr`). AIC8800 qualifies on that criterion, **but** the
carry form matters: a 70 k-line patch in `linux-patches/` is unreviewable and would make
`scripts/export-kernel-tree.sh`'s per-patch replay and `lint-kernel-patches.sh` meaningless
for that entry. The only acceptable forms are a **Buildroot kernel-module package** (source
pinned by commit hash to an upstream repo — candidates: whatever the fork vendored from, to
be identified from the file headers/`rwnx_version_gen.h`; the Radxa and goecho `aic8800`
trees are the usual public sources — with a `linux-firmware-extra`-style firmware package
alongside), or **declining for now**. Inputs the owner needs before choosing (§7): does any
known MiSTer-community dongle use AIC8800 (the Tenda U2/U11 IDs suggest yes — cheap AX
dongles); is the firmware redistributable and from where; does the driver build against
6.18.50 *and* 7.2.x for 32-bit ARM (the `rtl8852cu` `__aeabi_uldivmod` lesson — compile
before deciding). Default if unanswered: **defer**, record `not-evaluated` with the evidence
above and a tracked follow-up; do not let the increment's `fork-sync.conf` advance be
blocked by it (a `not-evaluated` record *is* a disposition under the schema, as long as it
says why).

### 2.10 Q10 PR #92 `a14b5e8e1c` (open) — hid-nintendo: skip baudrate setup for 8BitDo adapters — **carry now, track the PR** — Sonnet

The 8BitDo USB Wireless Adapter in Switch mode presents as a genuine Pro Controller
(`057e:2009`, same strings), does not implement `JC_USB_CMD_BAUDRATE_3M`, and reset-loops
when sent it: 17 re-enumerations, 13× `-EPROTO`, HID device left bound to nothing, "gamepad
unusable" — a controlled A/B on a DE10-Nano running 6.18.38, by the author. The fix moves
`joycon_read_info()` ahead of the USB baudrate/handshake block and skips that block when the
returned MAC carries 8BitDo's `E4:17:D8` OUI. Main_MiSTer has 8BitDo-adapter-specific paths
(`input.cpp:5852`, `:6130`) and hard-codes `057e_2009` (`:4733`), so this hardware is in
active community use. Hypothesis: **carry as `0049`** without waiting for the merge — the
failure mode is total for that adapter, the change is 32 lines in a driver we already patch
heavily (`0015`, `0032`, `0034`, `0035`, `0038`–`0041`), and the conflict risk is ours to
absorb whether we carry it now or later. Record keyed on the PR head SHA with
`source_branch: "refs/pull/92/head"` and a `notes` line saying it is unmerged; when it
merges, add the merged SHA to `duplicate_of` and re-check the hunk against the merged form.
Worker checks: the reorder does not change behaviour for controllers whose `read_info`
times out (the PR text discusses this); `0035` (home-LED non-fatal) and `0041` (LED names)
touch nearby probe code — apply order and context must be measured at `-F0`.

---

## 3. Version-drift re-grounding: v6.18.39 → v6.18.50

Deliberately its own axis, because it is the only mechanism by which a carried patch can
*retire* and it has been skipped twice (`_meta` note, 2026-08-24). Method, per
`fork-sync-2026-07.md` §5, mechanised:

1. Haiku (W1-drift-list): `git log --name-only v6.18.39..v6.18.50` intersected with the set
   of paths touched by every file in `linux-patches/` (and `linux-patches-beta/`'s four
   locals, against 7.2.2→7.2.4 for the RT line; DE25's two locals, 7.2.3, unchanged pin —
   skip). Output: `stable-drift-6.18.39-50.md`, one row per (patch, stable commit) collision
   with the stable subject and `--stat`.
2. Sonnet (W1-drift-verdicts, batched ~10 collisions per agent): for each collision, quote
   the stable hunk and the carried hunk and grade `disjoint` / `overlapping-compatible` /
   `superseded` / `conflicting`. **`superseded` is the retire signal** and needs the full
   `dropped-upstream` evidence standard (file:line + quote + same-behaviour confirmation).
3. The four patches the provenance doc names as "a `.y` bump could invalidate" get a row
   even with zero path collisions, stating that explicitly: `0028` (dwc2 unaligned IN
   split), `0027` (mt76x2u Xbox adapter IDs), `0020` (MMC `SEND_STATUS` LED), `0030`
   (i2c-designware timeout `dev_err`). Add `0036` (btusb CSR) and `0047` (btusb Mercusys —
   check by tag that `2c4e:0115` is still absent at v6.18.50; if a stable maintainer picked
   it up, `0047` fails at `-F0` and the build would already be red, but say so).
4. Outcome feeds `commits.jsonl` `_meta.vanilla_target: v6.18.50` (commit SHA via
   `rev-parse v6.18.50^{commit}` — annotated-tag trap) and a paragraph in the increment
   write-up. `reduce.py` reads the version from `_meta`, so `reconciliation.md` follows.

The build is the backstop for *loud* absorption (`-F0` fails on an absorbed hunk); this axis
exists for the *silent* case — a stable fix that changes the behaviour our hunk sits next to.

---

## 4. Patches to retire, patches to add, and where we are ahead

### 4.1 Retire candidates (patches we carry)

| Patch | Verdict this increment | Trigger to retire |
|---|---|---|
| `0047-btusb-mercusys-ma530-2c4e-0115` | keep | Pin leaves 6.18.y (already documented in the patch and the beta `series` header). §3 step 3 re-checks .50. |
| `0003-cpufreq-cyclone5-de10nano-overclock` | keep under option A; **replaced** under B/C | Owner decision §2.4 + [HW] validation |
| `0027`, `0028`, `0020`, `0030`, `0036` | keep unless §3 finds `superseded` | Stable-drift verdict |
| everything else | keep | — no signal from this queue; upstream's port carries the same content (the last increment's tree-diff found both trees hold the same behavioural set) |

No patch retires on today's evidence. That is the honest answer; the §3 run is what could
change it.

### 4.2 New patches / changes for parity (worth including)

| Item | Form | Series | Tier | Worth it because |
|---|---|---|---|---|
| Stadia-FF IDs (Q8) | `0048` | de10, beta, de25 | Haiku+Sonnet | Main_MiSTer-coupled hardware; two lines |
| PR #92 8BitDo adapter (Q10) | `0049` | de10, beta, de25 | Sonnet | "gamepad unusable" class, hardware-verified upstream |
| exFAT plug (Q6) | `0050` (or backport form) | de10, beta*, de25* | Sonnet | file-browser throughput on the workload MiSTer actually has; *7.x form to be measured |
| xpad `skip_8bitdo_init` (Q5) | fold into `0017` | de10, beta, de25 | Sonnet | default-off diagnostic; keeps our xpad in step with stock's for the #84 investigation |
| OCRAM `flags-sram@f000` reservation (from Q4) | fold into `0004` | de10 only (board DTS) | Sonnet | protects Main_MiSTer's persistent-flag page from in-kernel `sram` allocations — independent of cpufreq |
| `"terasic,de10-nano"` compatible (from Q4) | fold into `0004` **only if vanilla lacks it** | de10 | Haiku check | export-tree alignment; may be a no-op |
| fb ops alignment (Q3) | edit `0001` **only if the worker recommends** | de10, beta (beta has its own re-anchored `0001` copy) | Sonnet | shrinks export diff; not a fix |
| cpufreq v2 (Q4, option B/C) | replace `0003`, extend `0004` | de10, beta | Opus + [HW] | see §2.4 |
| AIC8800 (Q9) | `package/aic8800` + firmware package, **not** a patch | n/a | Opus review, Sonnet package | see §2.9; default defer |

Not worth including: nothing in the queue is dismissible on content — the only "decline"
candidates are Q9 (on cost/firmware grounds, not merit) and the `=m` half of Q7 (policy).

### 4.3 Where our image is ahead of stock 6.18 (20260907) — for the record and for upstream PRs

Measured against the shipped config/module list, not inferred:

| Stock 20260907 state | Ours | Fixed upstream since? |
|---|---|---|
| `mmap(/dev/fb0)` → `-ENODEV`; Console Mode broken | fixed in `0001` (2026-07) | yes, #83 (Q3) |
| No driver for RTL8811AU/8821AU dongles | `rtw88_8821au` since v10 | yes, #81 (Q2) |
| No cpufreq/overclock at all | `0003` | yes, #85 (Q4), different design |
| NSO Genesis BT PID, N64/Genesis button maps, IMU name suffix, LED classdev names, DS lightbar names | `0038`–`0042` | **no** — upstream's port still lacks them (last increment's tree-diff) |
| NES/Famicom A/B mapping, Joy-Con combo LED, DualSense player-ID LED, home-LED non-fatal, CSR `0x2512` clones, DualSense `BTN_Z` | `0032`–`0037` (some are in upstream's port in a different form — see `fork-sync-2026-07.md` §3) | partially |
| Mercusys `2c4e:0115` | `0047` | yes (`6332499e7`) |
| 8BitDo adapter reset loop (Q10) | not yet — this increment | PR #92 open |

The `0038`–`0042` row is the material for **Wave 5** (optional): PRs to the fork carrying
what stock 6.18 users are missing, rendered from our export so authorship and provenance
travel with them. It is the most useful thing this repo can hand upstream right now and it
costs one Sonnet run per PR to prepare.

---

## 5. Execution — waves, agents, tiers, cost

### 5.1 Environment facts every worker prompt must state

- **No `/mnt/source`.** The previous campaigns assumed pre-cloned trees there. In this
  environment workers clone into the session scratchpad. Disk: ~24 GB free, enough for one
  shallow stable clone (~1.5 GB checked out) plus the fork and mainline at depth 1.
- **GitHub API and HTML are unreachable** (the proxy returns 403 / a scope error for
  `api.github.com` and `github.com/*/pulls` on repositories not attached to the session);
  **git over HTTPS works** for public repos, including `refs/pull/N/head` and
  `refs/pull/N/merge`. So: PR *diffs and commit messages* are available; PR *discussions*
  and *issues* (e.g. fork issue #84) are not. Where a disposition would depend on discussion
  content, the record says `needs-verification` and names what to paste. The human
  attaching the fork with `add_repo … access:"push"` may lift this; it was not tried here
  because a cross-owner attach is expected to be refused.
- **Shallow-fetch trap, hit in this session:** `git fetch --depth N origin refs/pull/N/head`
  into an existing shallow clone re-grafts the *main branch's* history at the PR's ancestors
  — `git log 6332499e7..HEAD` silently dropped from 9 commits to 4 afterwards. Fetch PR refs
  **without** `--depth`, or re-run `git fetch --depth 400 origin MiSTer-v6.18` after. Wave 0
  asserts the queue length before anything else runs.
- Grounding trees and how to get them (Wave 0 does it once; workers reuse the paths):

  ```bash
  S=<scratchpad>
  git clone --branch MiSTer-v6.18 --depth 400 https://github.com/MiSTer-devel/Linux-Kernel_MiSTer $S/fork
  git -C $S/fork fetch origin refs/pull/92/head:refs/pr/92 refs/pull/85/head:refs/pr/85   # no --depth
  git clone --branch v6.18.50 --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git $S/linux
  git -C $S/linux fetch --shallow-exclude=v6.18.39 origin linux-6.18.y   # history for the §3 drift walk
  git -C $S/linux fetch --depth 1 origin tag v6.18.39 tag v7.2 tag v7.2.4   # mainline-status and RT checks
  git clone --depth 1 https://github.com/torvalds/linux $S/mainline          # "is it upstream yet" (v7.3-rc*)
  git clone --depth 120 https://github.com/MiSTer-devel/Main_MiSTer $S/main   # userspace coupling
  git clone --depth 5 https://github.com/MiSTer-devel/Linux_Image_creator_MiSTer $S/lic   # stock artifacts (binaries are plain blobs, ~140 MB)
  ```

  If a git.kernel.org clone is slow through the proxy, `github.com/gregkh/linux` mirrors
  `linux-6.18.y`; tags are identical.

### 5.2 Wave plan

Tiers use the current model line-up (`TASKS.md` §0's routing table predates Opus 5):
**Haiku 4.5** (`claude-haiku-4-5-20251001`) mechanical; **Sonnet 5** (`claude-sonnet-5`)
verification and implementation; **Opus 5** (`claude-opus-5`) for the two items that need
kernel-design judgement; the orchestrator (this session's model, or Opus) audits. The
2026-07-15 orchestration ran tier-2 on Sonnet only by user directive ("no Fable/Opus
workers"); this plan proposes exactly two Opus runs and says why for each — downgrade them to
Sonnet if that directive still stands, at the cost of a weaker cpufreq comparison.

**Wave 0 — Bring-up and enumeration (deterministic; 1 Haiku, or a script). Serial, ~30 min.**

| ID | Agent | Task | Output |
|---|---|---|---|
| W0-env | Haiku | Run the §5.1 clones; assert `git log 6332499e7..MiSTer-v6.18 | wc -l == 9`; assert the shipped-config diff vs `aec7dc3aa` is 0 lines (re-derives §1.2); re-extract stock config/DTB with `scripts/inventory/kernel_extract.py` and `diff` against `evidence/` (must be identical) | `queue.jsonl` (Q1–Q10 with files/±/change_type/tier, PR-head SHAs), `env.md` (paths, SHAs, tag→commit map incl. `v6.18.50^{commit}`) |
| W0-drift | Haiku | §3 step 1 path intersection | `stable-drift-6.18.39-50.md` (collision rows, no verdicts) |

**Wave 1 — Per-item analysis (fan-out; 13 agents; fully parallel, ~2–4 h wall-clock).**
One record per queue item, schema per `worker-instructions.md` (adapted: paths from
`env.md`, grounding v6.18.50, `source_branch` set, `source_ref` for the PR). Each prompt
includes the §2 hypothesis **and the instruction to refute it**.

| ID | Item | Tier | Why this tier | Key acceptance |
|---|---|---|---|---|
| W1-Q1 | TUN cherry-pick | Haiku | duplicate lookup + one `olddefconfig` | `duplicate_of` set; resolved-config line quoted |
| W1-Q2 | RTW88_8821AU | Haiku | config-grep + firmware presence | three §2.2 checks each quoted |
| W1-Q7 | defconfig update | Haiku | derived record | `superseded_by` → Q2/Q3/Q4 records |
| W1-Q8 | Stadia IDs | Haiku (record) → **Sonnet** (mainline status + name-stability check) | two-line diff, but a userspace-coupling claim needs a quoted `hid_hw_start` path | Main_MiSTer `input.cpp` lines quoted; `v7.3-rc` grep result quoted |
| W1-Q3 | fb ops | Sonnet | equivalence argument over `fb_io_*` vs `fb_sys_*` on `memremap` memory | both hunks quoted; explicit recommendation align/keep with reason |
| W1-Q5 | xpad param | Sonnet | fold into `0017` requires re-reading our curated `xpad.c` deltas | dry-run `-F0` of the folded `0017` on v6.18.50 **and** v7.2.4 |
| W1-Q6 | exFAT plug | Sonnet | mainline-status decides the patch form; 7.x exFAT shape check | `git log -S` result quoted from `$S/mainline`; 7.2.4 `exfat_dir_readahead` quoted or "absent" |
| W1-Q10 | PR #92 | Sonnet | 32-line reorder in a driver we patch eight times | `-F0` apply order proven with `0035`/`0041` present; behaviour on `read_info` timeout stated |
| W1-Q4 | cpufreq port | **Opus** | design comparison across `drivers/clk` + `drivers/cpufreq` + DTS; the deliverable is the §2.4 decision memo with evidence | memo answering: does `0003` execute the retune from DDR while gating FPGA clocks (yes/no, quoted); vanilla `compatible` at v6.18.50; boost-sysfs contract under each option; `=y` feasibility of upstream's module; [HW] test matrix |
| W1-Q9 | AIC8800 | **Opus** | license/provenance sweep over 143 vendored files, mainline check at `v7.3-rc`, identify the vendored source tree, *attempt a cross-compile* against 6.18.50 for ARM (`__aeabi_uldivmod`-class failures surface only by compiling) | record `not-evaluated` or `carry-as-package` with: origin repo+commit, license findings, firmware file list and source, build result, USB-ID overlap check against `drivers/net/wireless/` and `drivers/bluetooth/` at v6.18.50 (the ADR 0016 bind-conflict test) |
| W1-drift-verdicts ×2 | §3 step 2, batched | Sonnet | quote-and-grade, ~10 collisions per agent | every row graded; any `superseded` carries `dropped-upstream`-grade evidence |

**Wave 2 — Refutation pass (4 Sonnet; parallel, ~1 h).** Independent agents instructed to
*refute* the load-bearing claims, per `fork-sync-2026-07.md` §7's method:

| ID | Claim under attack |
|---|---|
| W2-covered | "Q2 and Q3 are already covered by `linux.config` / `0001`" — the class of claim that produced the NSO-Genesis miss |
| W2-mainline | every "not in mainline" / "in mainline" statement from W1 (Q6, Q8, Q9, `0047` at .50) — re-derived from `$S/mainline` and `$S/linux` by a second agent |
| W2-coupling | every `userspace_coupling.coupled=true` citation (Q8, Q10) — re-grep Main_MiSTer at its current HEAD |
| W2-drift | 20 % sample of the drift verdicts plus **every** `superseded` |

Any refuted claim sends the item back to its W1 tier with the refutation attached.

**Wave 3 — Implementation (parallel by item; 7 Sonnet + 0–1 Opus; ~2–3 h).**

| ID | Tier | Work | Validation before commit |
|---|---|---|---|
| W3-0048 | Sonnet | author `0048` (Q8) with provenance header; symlink into beta and de25 series; `series` file entry | `scripts/lint-kernel-patches.sh`; `-F0` dry-run on pristine 6.18.50, 7.2.4, 7.2.3 |
| W3-0049 | Sonnet | author `0049` (Q10) | same + apply-order proof with the hid-nintendo stack |
| W3-0050 | Sonnet | author `0050` (Q6) in the form W1-Q6 decided; 7.x re-anchor or omission with tag evidence | same |
| W3-0017 | Sonnet | fold Q5 into `0017`, header delta 5 | same, both kernels |
| W3-0004 | Sonnet | OCRAM reservation (+ compatible if needed) into `0004`; `dtc` compile of the resulting DTS | `scripts/check-zimage-dtb.sh` on a kernel-only build |
| W3-config-docs | Sonnet | records for Q1/Q2/Q7; `linux.config` untouched unless a W1 record says otherwise; `docs/patch-provenance.md` §11 rows; `docs/kernel-config-deltas.md` banner (stock baseline is now the 6.18 config in `evidence/`); `docs/abi-contract.md` if cpufreq changes; `docs/wifi-parity.md` AIC8800 paragraph; `fork-sync.conf` advance (only after every Q has a record); `commits.jsonl` `_meta.increments` entry + `vanilla_target`; `python3 docs/kernel-recon/reduce.py` → 0 problems | `reduce.py` exit 0; `scripts/check-fork-sync.sh` would report reconciled (needs `gh`; state the manual equivalent) |
| W3-docs-refresh | Sonnet | the §9 documentation refresh: re-measure every README stock claim that the 20260907 release changed, regenerate `docs/stock-inventory/` from the 6.18 image with per-file release labels, re-run `docs/stock-reconciliation.md` / `firmware-parity.md` / `bluetooth-parity.md` / `wifi-parity.md` module-and-firmware sections against `evidence/`, re-run `kernel-config-deltas.md` §4 against the 6.18 stock config | every changed number cites the evidence file or the command that produced it; no stock cell left as an unlabelled 5.15 measurement |
| W3-cpufreq | Opus, **only if option B/C chosen** | port upstream's provider+driver as `0003` v2; `=y`; ABI doc | kernel-only build for de10 and rt; [HW] handoff list |
| W3-aic8800 | Sonnet, **only if approved** | `package/aic8800` kernel-module package + firmware package, Renovate manager, hash file | `make` of the package; bind-conflict grep |

Then one **full kernel build per variant** (the de10 kernel-only stack and `make rt`), the
`check-kernel-fragment-noop.sh` / `check-config-fragments.sh` / `check-kernel-defconfig-sync.sh`
trio, and — the backstop that found `0038` last time — **`scripts/export-kernel-tree.sh`
followed by `git diff` of the export against `$S/fork` at `c129b0fac`**, excluding
`drivers/net/wireless/aic8800/**`. Every remaining behavioural delta must already have a
record; a new one is a finding.

**Wave 4 — Audit (1 Opus or the orchestrator; serial, ~1 h).** Re-verify every `carried`
record's hunk-to-patch mapping, every `dropped-*` record's evidence, the §3 verdicts, and the
export diff. Write `docs/kernel-recon/fork-sync-2026-09.md` in the shape of the July one:
findings table first, then the increment, then "found here, deliberately not actioned here"
(cpufreq option B, AIC8800, the rootfs-side release delta — §8). Update
`orchestration-state.md` and this file's status line.

**Wave 5 — Optional upstream contributions (Sonnet, one per PR).** Render `0038`–`0042`
(and `0034` if upstream's port still swaps NES A/B) from the export as PRs against
`MiSTer-v6.18`, each with the record's evidence in the PR body. Needs the human to open the
PRs (no API from here); the agent prepares branch + body.

### 5.3 Ordering and dependencies

```
W0-env ──┬── W1-Q1 … W1-Q10 (parallel) ──┬── W2 (parallel) ──► W3 (parallel by item) ──► builds + export diff ──► W4 ──► W5
         └── W0-drift ── W1-drift-verdicts ┘
```

Owner decisions (§7) are needed **before W3-cpufreq / W3-aic8800 only**; every other W3 item
proceeds on the §2 defaults. If the decisions have not arrived by the end of W2, W3 runs
without those two and W4 records them as open.

### 5.4 Cost and sizing (estimates, not measurements)

| Wave | Agents | Tier | Est. tokens / agent | Est. total |
|---|---:|---|---|---|
| W0 | 2 | Haiku | 50–150 k | 0.3 M |
| W1 mechanical | 4 (Q1, Q2, Q7, Q8-record) | Haiku | 100–200 k | 0.6 M |
| W1 verification | 5 (Q3, Q5, Q6, Q10, Q8-verify) + 2 drift | Sonnet | 300–600 k | 3.5 M |
| W1 design | 2 (Q4, Q9) | Opus | 1–2 M | 3 M |
| W2 | 4 | Sonnet | 200–400 k | 1.2 M |
| W3 | 7 (+2 conditional) | Sonnet (Opus ×1 cond.) | 300–800 k | 3.5–6.5 M |
| W4 | 1 | Opus / orchestrator | 1–1.5 M | 1.5 M |
| W5 | 0–6 | Sonnet | 200 k | 0–1.2 M |
| **Total** | **~27 (+8 cond.)** | | | **≈ 13.5–17.5 M tokens** |

The July campaign spent 103 Haiku workers + Sonnet tier-2 on 123 records; this increment is
an order of magnitude smaller in records but heavier per record (two design items, three
kernels to apply to, a full stable-drift walk). The Opus spend is concentrated where a wrong
answer costs hardware hangs (Q4) or a 70 k-line supply-chain decision (Q9).

### 5.5 Worker prompt template (Wave 1)

```
You are reconciling ONE item from MiSTer-devel/Linux-Kernel_MiSTer (branch MiSTer-v6.18,
or the PR ref named below) against the kernel this repo ships, v6.18.50. Analyze ONLY this
item. Do not group it with any other.

ITEM: <sha or refs/pr/N>  <subject>
ORCHESTRATOR HYPOTHESIS (test it; refute it if the source disagrees):
<one paragraph from docs/kernel-recon/fork-sync-2026-09/PLAN.md §2.x>

Trees (read-only; from env.md): fork=$S/fork  linux=$S/linux (checked out v6.18.50; tags
v6.18.39, v7.2, v7.2.4 fetched)  mainline=$S/mainline (v7.3-rc)  main=$S/main (Main_MiSTer)
Repo: this checkout — carried series board/mister/de10nano/linux-patches{,-beta,-upstream}/,
board/mister/de25nano/linux-patches/, board/mister/de10nano/linux.config, the shipped stock
config docs/kernel-recon/fork-sync-2026-09/evidence/stock-20260907-linux.config, and
docs/kernel-recon/worker-instructions.md (schema + grounding contract — mandatory).

RULES (worker-instructions.md, restated): no upstream claim without file:line + quoted hunk
+ same-behaviour confirmation; never write a SHA you did not obtain from a git command you
ran; search by symbol, never by old path; "already provided by our config/patch" is a claim
that needs the resolved config line or the carried hunk QUOTED; a partial equivalence is a
carry candidate, not a closed question. For anything that depends on PR discussion or an
issue thread you cannot read, set needs-verification and name what a human should paste.

OUTPUT: exactly one file, docs/kernel-recon/records/<full-sha>.json, schema per
worker-instructions.md with "source_branch" ("MiSTer-v6.18" or "refs/pull/92/head") and, for
carried items, the patch number this plan assigns. Nothing else on disk.
```

---

## 6. Definition of done for this increment

- Every Q1–Q10 has exactly one record; `reduce.py` reports 0 problems; `fork-sync.conf`
  `MiSTer-v6.18` line advanced to `c129b0fac` **with** a comment naming the records, and a
  separate note that PR #92 is carried ahead of merge.
- `_meta.vanilla_target` = v6.18.50 and the §3 drift walk is in the increment write-up, with
  its verdict table.
- New/changed patches (`0048`, `0049`, `0050`, `0017`, `0004`, possibly `0001`) apply at `-F0`
  on pristine 6.18.50, 7.2.4 and 7.2.3 (or are omitted from a 7.x series with tag-level
  evidence in the `series` header, per the beta `series` rule), pass
  `lint-kernel-patches.sh`, and the de10 + rt kernel builds are green.
- The export-vs-fork tree diff has zero undispositioned behavioural deltas outside
  `aic8800/`.
- `docs/kernel-recon/fork-sync-2026-09.md` exists in the July shape; `patch-provenance.md`
  §11, `kernel-config-deltas.md`, `abi-contract.md` (if cpufreq changed), `wifi-parity.md`
  (AIC8800 paragraph) updated in the same PR as the patches; the §9 documentation refresh
  is done, so no document still presents a 5.15 stock measurement as current without
  saying so.
- The two owner decisions are either executed or recorded as open with the Opus memos
  attached.
- Hardware-gated items are listed for the human with exact test steps: cpufreq at
  400/800/1000/1200 under either option, an 8BitDo adapter in Switch mode, a
  Classic2USB/RetroZord rumble check, an Archer T2U Nano association.

---

## 7. Decisions needed from the owner

| # | Decision | Default if unanswered | Blocks |
|---|---|---|---|
| D1 | cpufreq: keep `0003` (A), adopt upstream's port (B), or hybrid (C) — §2.4 | A now, B tracked | W3-cpufreq only |
| D2 | AIC8800: package it, defer, or decline — §2.9 | defer, `not-evaluated` record with evidence | W3-aic8800 only |
| D3 | Carry PR #92 before it merges — §2.10 | yes | W3-0049 |
| D4 | Align `0001`'s read/write helpers to upstream's `fb_sys_*` if W1-Q3 finds them equivalent — §2.3 | follow the worker's recommendation | W3 edit of `0001` |
| D5 | Run the two Opus workers, or hold to the July "Sonnet only" directive | run them (two agents, reasons in §5.2) | W1-Q4, W1-Q9 quality |
| D6 | Wave 5 upstream PRs for `0038`–`0042` | prepare branches, human opens PRs | nothing in this increment |

---

## 8. Out of scope here, but surfaced

- **Rootfs-side delta of Release 20260907.** `rootfs.tar.bz2` and `firmware.tar.gz` changed
  too (new firmware: `rtw89/*`, `mediatek/mt7925/*`, `ath10k/QCA9377/*`,
  `rtlwifi/rtl8192dufw.bin`, …). `docs/stock-reconciliation.md` and `docs/firmware-parity.md`
  are measured against the 2026-07-17 LIC commit and need a re-run against `d4e3f51`. One
  Sonnet task, separate PR; the module and firmware lists in `evidence/` are its input.
- **`docs/stock-inventory/`** still describes the 5.15 image. The 6.18 config in `evidence/`
  should eventually move there via `gen-kernel-config-dts.sh` with the README updated to say
  which stock release each file came from.
- **`check-fork-sync.sh` still cannot see new branches** (`fork-sync-2026-07.md` §8.3) and
  cannot see open PRs at all. Fetching `refs/pull/*/merge` (only open PRs have one) is a
  no-API way to list them; worth a five-line addition, tracked, not done here.
- **Stock has moved to 6.18.38 and will presumably sit there** the way 5.15 sat on 5.15.1.
  Our `.y` tracking is now a concrete, describable advantage (12 stable releases ahead as of
  this writing) — a README/version-delta sentence, not a kernel task.

---

## 9. Documentation: the 5.15-era recon is labelled, and what the increment must refresh

Stock's move to 6.18 makes every "stock" claim in this repo a dated one. This section
records what was **done now** (in the commit that added this plan) and what is **left for
the increment** (`W3-docs-refresh`).

### 9.1 Labelled now — the 5.15 reconciliation stays in place, marked as such

Archiving by moving files was rejected: `phase0.py`, `reduce.py`, `worker-instructions.md`,
`fork-sync-2026-07.md`, `scripts/export-kernel-tree.sh`, `docs/de25-readiness-ledger.md`
and the README all cite the spec and the records by path, and `fork-sync.conf`'s whole
mechanism keys on `records/<sha>.json` staying where it is. The records are also still the
live evidence base — every new increment adds to them. So the artifacts stay put and each
now says, at the top, which stock kernel it was measured against:

| File | What was added |
|---|---|
| `MISTER-KERNEL-PATCH-RECON.md` | **ARCHIVED** banner: executed 2026-07 against `MiSTer-v5.15` @ `f0fb626ac`; not the live process; points here |
| `docs/patch-provenance.md` | "Stock baseline of this document: the 5.15 kernel" banner; stock-parity is now measured against `MiSTer-v6.18` + the shipped 6.18 config |
| `docs/kernel-recon/worker-instructions.md` | "Which fork branch" note (work items come from `MiSTer-v6.18`; `MiSTer-v5.15` frozen at `5fcfae369`); Resources table now lists both stock configs |
| `docs/kernel-recon/fork-sync.conf` | "WHY BOTH BRANCHES" rewritten: the inversion, the `aec7dc3aa` identity of Release 20260907, the pending queue. Pointers **not** moved — nothing is dispositioned yet |
| `docs/kernel-recon/reduce.py` → `reconciliation.md` | Branch legend now says `v5.15` = stock until 2026-09-07, `v6.18` = stock since Release 20260907. (`reduce.py` also gained a one-line fix so it parses on Python 3.11 — an em-dash escape inside an f-string expression was a `SyntaxError` there; outputs regenerated, content unchanged apart from the legend and timestamp) |
| `docs/stock-inventory/README.md` | Banner: inventory is of release 20250402 (5.15); kernel-side 6.18 files are in `evidence/`; rootfs-side re-run pending |
| `docs/kernel-config-deltas.md` | Stock-baseline note: "stock config" means 5.15; §4 audit to be re-run against the 6.18 config |
| `docs/stock-reconciliation.md` | Banner: measured against LIC `8aba321` (5.15); what Release 20260907 replaced; re-run pending |
| `README.md` | One-paragraph version, the two **Kernel** rows, §1 "The kernel", and the Wi-Fi hardware table intro updated to the 6.18 facts that are measured; a "Stock moved on 2026-09-07" note under the comparison table says every other stock cell is still the 20250402 measurement |

### 9.2 Left for the increment (`W3-docs-refresh`, Sonnet)

Everything below still presents a 5.15-era stock measurement. Each is now labelled as such
(§9.1) or is a plan/task document where the history is the point; none is wrong, all are
dated. In priority order:

| Document | What to re-measure against | Notes |
|---|---|---|
| `README.md` — every non-kernel row of "Stock vs. this image", the Bluetooth/Wi-Fi/controller hardware tables, "What this improves" §3–§6, "the honest list" | Release 20260907's `rootfs.tar.bz2`, `firmware.tar.gz`, `modules.tar.gz` (`evidence/` has the last two as lists) | Buildroot/glibc/OpenSSL/OpenSSH/Samba/Python versions in stock's new rootfs are unknown until it is inventoried — do not guess them |
| `docs/stock-inventory/` (all files) | 20260907 image via `scripts/inventory/run-all.sh` | Keep the 20250402 files, renamed with a release suffix, or move them to a `20250402/` subdirectory; README must name the release per file |
| `docs/stock-reconciliation.md`, `docs/verification/stock-reconciliation/*.txt` | LIC `d4e3f51` | `stock-mods.txt`/`stock-fw.txt` are superseded by the `evidence/` lists; `addon.tar` is unchanged so §3 stands |
| `docs/firmware-parity.md`, `docs/bluetooth-parity.md`, `docs/wifi-parity.md` | `evidence/stock-20260907-firmware.txt`, `-modules.txt` | The "stock ships no `ath3k-1.fw`" class of claims may have flipped — 89 firmware files now vs 69 |
| `docs/kernel-config-deltas.md` §4, §7 | `evidence/stock-20260907-linux.config` resolved on v6.18.50 | This is the config-axis half of the increment proper (W1-Q2/Q7) |
| `docs/version-delta.md`, `docs/package-manifest.md` | new stock rootfs | Only after the inventory; SONAME table may move |
| `docs/abi-contract.md`, `docs/boot-chain.md` | `MiSTer-v6.18` @ `aec7dc3aa` source | Citations are to `MiSTer-v5.15` line numbers. The *contract* is unchanged unless stock's 6.18 kernel changed an ABI surface — the fb `mmap` regression (§1.2) is exactly such a change and should be recorded as "stock 6.18 breaks its own contract here; fixed by #83" |
| `docs/reference-materials.md` | add the 20260907 artifacts with hashes (§1.1 has them) | `work/` manifest discipline: URL, commit, hash, reproduce command |
| `PLAN.md`, `TASKS.md`, `docs/phase0-review.md`, ADRs 0010/0016 | — | Historical; add a one-line "stock was 5.15 when this was written" note at the top of `PLAN.md` and `TASKS.md` only |
