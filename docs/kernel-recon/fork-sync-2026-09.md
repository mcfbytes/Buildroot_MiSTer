# Fork-sync increment — 2026-09-11

The third incremental run of the reconciliation, and the first that follows a **stock release**
rather than the fork's own development. On 2026-09-07 stock MiSTer shipped its first 6.18
kernel (`Linux_Image_creator_MiSTer` "Release 20260907", `MiSTer-v6.18` @ `aec7dc3aa`, kernel
`6.18.38-MiSTer`) — which inverts the baseline this whole reconciliation project has used since
its first campaign: `MiSTer-v6.18` is now what every stock MiSTer runs, and `MiSTer-v5.15` is
frozen history. Within four days of that release, users found regressions in it and the fork
took eight commits and one still-open PR to address them; this document reconciles those nine
items against this repo's own 6.18 build.

**Outcome: four items carried as new/changed patches, four dropped as already covered, one
driver-replacement deliberately declined with a tracked bench-gated follow-up, and one 82,000-line
out-of-tree driver deferred pending two answerable external facts.**

| # | Finding | Kind | Action |
|---|---|---|---|
| 1 | Stock 20260907 shipped with **no cpufreq driver at all** and **no driver for RTL8811AU/8821AU dongles** — regressions vs. this image, which has had both since July | stock is behind us, not the reverse | none needed; recorded for the record (§2, §4.3) |
| 2 | Our `docs/abi-contract.md` and `docs/patch-provenance.md` described the cpufreq `boost` sysfs file as non-existent | **our own docs were stale**, and user-visible today | corrected in both docs + a new FAQ entry (§3) |
| 3 | A 2026-07-24 ledger defect — four carried patches (`0039`-`0042`) unreachable from any record's `carried_patch` — found by `reduce.py`'s own orphan invariant | pre-existing process gap, unrelated to this queue | fixed: `reduce.py` now reads a `carried_patches` (plural) list; four origin records updated (§5) |
| 4 | An open PR (#92) carried ahead of its own merge, for the first time in this project | new pattern, deliberate (owner decision D3) | carried as `0049`, keyed on the PR head SHA with an explicit re-key procedure for when it merges (§2) |
| 5 | A community re-implementation of the overclock driver (`59bcae8eb`, #85) — better-engineered, unvalidated on our image | decision required | **kept `0003`** (owner decision D1=A); DTS OCRAM hygiene hunk still carried; option B tracked bench-gated (§2) |
| 6 | A 70k-line vendored Wi-Fi/BT driver (`c129b0fac`, AIC8800) with no firmware and no license file | decision required | **deferred** (owner decision D2); compiles clean, zero USB-ID conflicts, but inert without ~60 firmware blobs stock does not ship either (§2) |

---

## 1. What was new

`fork-sync.conf`'s `MiSTer-v6.18` pointer stood at `6332499e7` (2026-08-24). Between then and
2026-09-11 the branch gained:

| Item | SHA | Date | Author | Subject |
|---|---|---|---|---|
| Q1 | `aec7dc3aa` | 2026-07-24 | Nigel Shearman | config: enable CONFIG_TUN for tap device support (#76) |
| Q2 | `33a0521fd` | 2026-09-08 | Julian Seitz | config: enable CONFIG_RTW88_8821AU for Realtek 8821AU/8811AU USB adapters (#81) |
| Q3 | `ea2212221` | 2026-09-08 | Takiiiiiiii | fbdev: MiSTer_fb: declare explicit fb_ops for read/write/mmap (#83) |
| Q4 | `59bcae8eb` | 2026-09-08 | Kasper Olesen | Port MiSTer CPUFreq to Linux 6.18 with opt-in turbo (#85) |
| Q5 | `7c75b1b46` | 2026-09-08 | Kasper Olesen | Input: xpad - add opt-in 8BitDo initialization bypass |
| Q6 | `9854075c8` | 2026-09-09 | Sorgelig (re-committed; PR #88 by Giancarlo Erra) | exfat: speed-up dir read-ahead. |
| Q7 | `e6f377e7d` | 2026-09-09 | Sorgelig | Update defconfig. |
| Q8 | `41c45f378` | 2026-09-09 | Porkchop Express | Adapt Classic2USB and RetroZord HID force feedback support (#91) |
| Q9 | `c129b0fac` | 2026-09-11 | Sorgelig | Add AIC8800 WiFi/BT driver. |
| Q10 | PR #92 head `a14b5e8e1` | 2026-09-10 | Michał Kopeć | HID: nintendo: skip baudrate setup for 8BitDo adapters (**open**, not merged) |

Plus three closed-unmerged PR heads (#86, #88, #90) that duplicate Q5/Q6/Q8 respectively —
tracked in `fork-sync-2026-09/PLAN.md` §1.3, not separately dispositioned.

`MiSTer-v5.15` gained nothing (still frozen at `5fcfae369`). No new fork branches.

**Why this queue is different in kind from the last two increments.** Until Release 20260907,
`MiSTer-v5.15` was the source of truth for *what stock has* and `MiSTer-v6.18` commits were
evidence about a port in progress. That inverted on 2026-09-07: stock now runs `MiSTer-v6.18`
directly (the shipped IKCONFIG config is byte-identical to `MiSTer_defconfig` at `aec7dc3aa`,
measured in Wave 0), so a commit on this branch is now a stock-parity question, not a port
question — the "dispositioned ≠ closed" lesson `fork-sync.conf` already carries applies with
full force. It also means, for the first time, this project can measure stock 6.18 regressions
**this image does not have**: no cpufreq driver at all, and no RTL8811AU/8821AU driver, on
stock's Release 20260907 (§1 item in the table above; full facts in `PLAN.md` §1.1-§1.2 and
§4.3).

---

## 2. Per-item outcome

**Q1 `aec7dc3aa` (CONFIG_TUN) — `dropped-deliberate`, duplicate.** Byte-identical hunk to the
already-dispositioned `5fcfae369` on `MiSTer-v5.15`; `CONFIG_TUN=y` has been in `linux.config`
since that record landed (previous increment). Confirmed to survive `olddefconfig` on 6.18.49.

**Q2 `33a0521fd` (CONFIG_RTW88_8821AU) — `dropped-deliberate`, already provided.**
`linux.config:623` has had `CONFIG_RTW88_8821AU=m` since the v10 Wi-Fi expansion (`docs/wifi-
parity.md` §6.4, ADR 0016) — four months before the fork's own defconfig caught up. Resolved
config yields the auto-selected `RTW88_8821A=m`/`RTW88_88XXA=m` core; firmware ships via
`BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88`; the motivating device (TP-Link Archer T2U Nano,
`2357:011e`) is in 6.18.49's `rtw8821au.c` ID table. **Stock 20260907 users have no driver for
this chip; ours has had one since July.**

**Q3 `ea2212221` (fbdev explicit fb_ops) — `carried`, re-implemented in `0001`, aligned.**
Same v6.8 regression (`8813e86f6d82`, fbdev's default file-I/O implementations removed) that
`0001`'s July forward-port already fixed via `__FB_DEFAULT_IOMEM_OPS_RDWR`/`_MMAP` +
`select FB_IOMEM_FOPS`. Upstream's fix uses `fb_sys_read`/`fb_sys_write` + `fb_io_mmap` and
selects both `FB_SYSMEM_FOPS` and `FB_IOMEM_FOPS`. Proven behaviourally identical on ARM
(`mmiocpy` *is* `memcpy`, `arch/arm/lib/memcpy.S:56-66` — both paths execute the same machine
code on this target) and Main_MiSTer never calls `read(2)`/`write(2)` on `/dev/fb0` (only
`ioctl(FBIO_WAITFORVSYNC)`, `video.cpp:3773-3789`), so this was a zero-risk export-diff-shrinking
choice, not a bug fix — owner decision D4: aligned. `mmap` stays on `fb_io_mmap` unchanged (6.18
has no sysmem mmap helper at all).

**Q4 `59bcae8eb` (cpufreq port, #85) — `dropped-deliberate`, owner decision D1=A.** The one item
that is not a small carry — full comparison in `memo-Q4-cpufreq.md`. Facts: stock 20260907
shipped with **no cpufreq driver at all**; this image has had one (`0003`, forward-ported from
Michael Huang's 5.15 driver) since July. The fork's port is a genuine engineering improvement —
a real CCF clock provider, an OCRAM-resident PLL retune under `stop_machine` with `OUTRESETALL`,
12.5%-per-step VCO ramping, bounded polling, rollback, and CCF rate-change notification so the
A9 TWD local timer stays correct through a frequency change (`0003` never calls the CCF, so the
TWD clockevent rate silently goes stale) — over `0003`'s direct-register-poke design, which
reproduces two of the three causes the fork author names for the port's *own* first-attempt
hang (DDR execution through the PLL-bypass window; a single-step VCO jump) plus a fourth latent
defect (`wait_for_fsm()`'s mask/bit-number bug, already documented, B6). **The decision came down
to one fact that killed the tie-breaker the plan expected**: the boost/`scaling_max_freq` sysfs
contract the two drivers expose is **byte-identical** (both set `.set_boost =
cpufreq_boost_set_sw` with `.boost_enabled = false`) — so adopting the fork's driver buys no
user-visible improvement, only unvalidated code, on the one patch that can hang a board
mid-transition. **Kept `0003`.** The DTS OCRAM `flags-sram@f000` tail reservation from the same
commit *is* carried into `0004` regardless, as zero-cost allocation hygiene (the fork's stated
rationale — persistent flags live there — does not verify against Main_MiSTer, which keeps them
in DDR at `0x1FFFF000`, but the reservation costs nothing and becomes load-bearing if option B is
ever adopted). Option B is **tracked, not abandoned** — see §6.

**Q5 `7c75b1b46` (xpad `skip_8bitdo_init`) — `carried`, folded into `0017` as delta 5.** A
default-**off** module parameter skipping the Xbox-360 vendor-init request for USB `2dc8:3106`
only — an experimental A/B switch (the commit's own words) for the reconnect-failure regression
tracked in fork issue #84, not a permanent quirk. Zero behaviour change unless a user opts in.
`0017` already owns `xpad.c`'s MiSTer deltas and already declares a module parameter at the
insertion point the fork's hunk anchors on, so the fold applies at `-F0` with offsets only on
both 6.18.49 and 7.2.3.

**Q6 `9854075c8` (exFAT dir read-ahead plug, = PR #88) — `carried` as `0050`, 6.18-only, fork
authorship.** Wraps `exfat_dir_readahead()`'s `sb_breadahead()` loop in a block plug, matching
the existing allocation-bitmap precedent already in this kernel (`fs/exfat/balloc.c`) —
throughput fix for large directories, exactly the MiSTer file-browser workload. Mainline does
**not** have this exact hunk to attribute a backport to: v7.3-rc2 refactored directory
read-ahead into a shared `exfat_blk_readahead()` helper (mainline's own generalization of the
same allocation-bitmap precedent) that replaced `exfat_dir_readahead()` entirely, and 7.2.3
already carries that refactor — so the fork's 4-line hunk **fails at `-F0`** against 7.2.3 (`2
out of 2 hunks FAILED`, reproduced), meaning the RT/DE25 kernels already have the behaviour under
a different shape. `0050` is carried as fork code, for the 6.18 series only, with PR #88's
original author Giancarlo Erra's `Signed-off-by` preserved (Sorgelig's re-commit onto
`MiSTer-v6.18` dropped both his authorship and his commit body).

**Q7 `e6f377e7d` (defconfig update) — `dropped-deliberate`, fully derived.** Three lines, each
the config-side consequence of Q2 (`RTW88_8821A=m`, auto-selected) or Q3
(`FB_SYSMEM_FOPS=y`/`FB_IOMEM_FOPS=y`, `select`-implied). No independent content.

**Q8 `41c45f378` (Stadia-FF IDs, #91) — `carried` as `0048`, Main_MiSTer-coupled.** Two
`hid_device_id` rows so the Stadia rumble driver claims the Classic2USB/Reflex Adapt
(`16d0:1460`) and RetroZord (`1209:595a`) adapters — `CONFIG_HID_GOOGLE_STADIA_FF=y` is already
in `linux.config:410`, so the two lines are the entire gap. Main_MiSTer already special-cases
exactly these two IDs six times (`input.cpp:52-53`, `:4176-4177`, plus NeGcon/Guncon paths at
`:5101-5103`/`:5348-5350`/`:5495-5506`), so this is "must not drop silently" territory under the
recon spec. Verified the driver's `hid_hw_start(HID_CONNECT_DEFAULT & ~HID_CONNECT_FF)` call
never touches device name/uniq strings, so none of Main_MiSTer's string matches are affected by
which driver binds. Applies clean at `-F0` on both 6.18.49 and 7.2.3 (the file is byte-identical
across both trees).

**Q9 `c129b0fac` (AIC8800 Wi-Fi/BT driver) — `not-evaluated`, owner decision D2=defer.** 142
files, 82,330 insertions — a RivieraWaves/AICSemi vendor "rwnx" fullmac driver re-badged for the
AIC8800 chip family, needed for the Tenda U2/U11/U11 Pro and TX1U Nano AX dongles among others.
Full sweep in `memo-Q9-aic8800.md`. The technical objection is gone: both kernel modules compile
**and modpost clean** for 32-bit ARM (the `rtl8852cu`-class `__aeabi_uldivmod` 64-bit-division
trap does not recur — the driver only needs `__aeabi_idiv`/`__aeabi_uidiv`, both exported by
`armksyms.c`), and the ADR 0016 USB-ID bind-conflict test passes with zero overlaps against
anything this repo already carries. The supply-chain objection is decisive: the driver reads
~60 firmware blobs from `/lib/firmware` via `filp_open()` (not `request_firmware()`), and
stock's own Release 20260907 `firmware.tar.gz` ships **zero** of them — no firmware commit
exists anywhere in the fork's history yet. The 139-file vendored source tree also carries **no
LICENSE file, no README**, and SPDX tags on exactly one of 139 files (a third-party quirk
module); 85 files have a bare copyright line and no license grant at all, two are Apache-2.0
(GPL-2.0-incompatible, though not compiled into the shipped `.ko`). Both blockers — identifying
the upstream vendor repo (the exact snapshot is stamped in `rwnx_version_gen.h`:
`RWNX_VERS_REV "1a4b0054d2M (master)"`, SDK `"6.4.3.0"`, `RELEASE_DATE "2026_0123_5f7be68d"`) and
its firmware distribution — are answerable without hardware, which is why this is a defer, not a
decline. ADR 0016 already permits an out-of-tree driver here (same "mainline cannot drive this
chip" ground `rtl8852cu-morrownr` was accepted on) but **only** as a Buildroot kernel-module
package — an 82k-line patch in `linux-patches/` would make `scripts/export-kernel-tree.sh`'s
per-patch replay and `lint-kernel-patches.sh` meaningless for that entry, so in-tree carry is off
the table regardless of outcome.

**Q10 PR #92 head `a14b5e8e1` (hid-nintendo 8BitDo adapter fix) — `carried` as `0049`, unmerged,
owner decision D3=carry now.** The 8BitDo USB Wireless Adapter in Switch mode presents as a
genuine `057e:2009` Pro Controller and reset-loops (17 re-enumerations, 13× `-EPROTO`,
hardware-verified A/B by the PR author on a DE10-Nano running 6.18.38) when hid-nintendo sends
it `JC_USB_CMD_BAUDRATE_3M`, which the adapter does not implement. The fix moves
`joycon_read_info()` ahead of the baudrate/handshake block and skips that block for controllers
whose reported MAC carries 8BitDo's `E4:17:D8` OUI. "Gamepad unusable" class failure, 32 lines,
Main_MiSTer hard-codes `057e_2009` (`input.cpp:4733-4734`) so this hardware is in active
community use. Carried **ahead of the PR's own merge** — the first time this project has done
so — because the failure mode is total for that adapter and the conflict-absorption cost is
ours whether carried now or later; applies clean at `-F0` on top of all eight patches this repo
already carries on `hid-nintendo.c`, on both 6.18.49 and 7.2.3. Record is keyed on the PR head
SHA (`source_branch: refs/pull/92/head`), **not** a merge commit, with an explicit re-key
procedure written into both the record's own notes and `fork-sync.conf`'s comment block for when
#92 merges.

---

## 3. Our own docs were stale on the boost ABI — found by this increment, fixed here

`docs/abi-contract.md:1670` and `docs/patch-provenance.md` (the "P1.6 correction" box) both
asserted, in the present tense, that `/sys/devices/system/cpu/cpufreq/boost` does not exist and
that `0003`'s overclock mechanism is `scaling_max_freq` alone. **That was true of `0003` before
PR #24** (the fix for a field hard-hang where the board auto-overclocked to 1.2 GHz on every
boot) — which added `.set_boost = cpufreq_boost_set_sw`/`.boost_enabled = false` to the driver.
The shipped `0003` has carried that hunk since PR #24 landed, months before this increment, and
both docs kept describing the pre-PR#24 state. Consequence, verified against 6.18.49's core
`cpufreq.c` (quoted in full in `memo-Q4-cpufreq.md` §4): the `boost` file **exists** (default
`0`), and `echo 1200000 > scaling_max_freq` alone **clamps to `800000`** until `echo 1 >
.../cpufreq/boost` is written. This is user-visible today, on the shipped image, independent of
the Q4 A/B/C decision — and it is **byte-identical** between `0003` and the fork's alternative
driver, which is what killed option C (memo §4, §8). Both docs are corrected in this increment
(`patch-provenance.md` §5 and §11, `abi-contract.md`'s cpufreq row) and a new FAQ entry
(`docs/user/faq.md`) tells script authors the one extra line they need.

---

## 4. Where this image is ahead of stock 6.18 — for the record

Measured against the shipped Release 20260907 config/module list, not inferred (`PLAN.md` §4.3):

| Stock 20260907 state | Ours | Fixed upstream since? |
|---|---|---|
| `mmap(/dev/fb0)` → `-ENODEV`; Console Mode broken | fixed in `0001` (2026-07) | yes, #83 (Q3) |
| No driver for RTL8811AU/8821AU dongles | `rtw88_8821au` since v10 | yes, #81 (Q2) |
| No cpufreq/overclock at all | `0003` | yes, #85 (Q4), different design — kept ours |
| NSO Genesis BT PID, N64/Genesis button maps, IMU name suffix, LED classdev names, DS lightbar names | `0038`-`0042` | **no** — upstream's port still lacks them |
| 8BitDo USB Wireless Adapter reset loop | fixed this increment, `0049` | PR #92, still open |

The `0038`-`0042` row remains the material for an optional Wave 5 (upstream PRs carrying what
stock 6.18 users are missing) — not actioned in this increment.

---

## 5. Ledger fix — the `0039`-`0042` orphans, found by `reduce.py`'s own invariant

`reduce.py`'s orphan-carried-patch check reported `0039`, `0040`, `0041`, `0042` as unreachable
from any record's `carried_patch` — a pre-existing defect from 2026-07-24, unrelated to this
increment's queue, surfaced only because this pass re-ran the invariant. Root cause: the schema
holds one `carried_patch` per record, but several origin commits produced **two** carried
patches from one diff (e.g. one commit's hunk split into both the NSO-Genesis BT-PID fix and the
N64/Genesis button-mapping fix). Two of the four origin commits were straightforward
(`b00a72159` → `0038`+`0039`; `60821059c` → `0035`+`0041`, both already had records). The other
two (`0040`'s cited origin `a6b7e3666` and `0042`'s cited origin `f123647ef`, per
`patch-provenance.md` §11's table) turned out to have **no record file at all under those short
SHAs** — tracing them found they are the `MiSTer-v6.18`-branch re-ports (byte-identical subject
lines) of two already-recorded `MiSTer-v5.15` commits, `45283785a` and `f84543926`
respectively (the same subject-twinning `fork-sync.conf`'s 2026-07-24 note already documents for
57 other commits). Fixed minimally: `reduce.py` now also reads an optional `carried_patches`
(plural) list per record for both the orphan check and the patch-mapping table, and the four
origin records (`b00a72159`, `45283785a`, `60821059c`, `f84543926`) were given that field. Zero
orphans remain (verified by re-deriving the mapping logic against the live `records/` directory
without running `reduce.py`'s full regeneration, per this session's remit).

---

## 6. Follow-ups — found here, deliberately not actioned here

### 6.1 Option B (adopt the fork's cpufreq port) — bench-gated, not abandoned

Per `memo-Q4-cpufreq.md` §8, re-open the Q4 decision (A → B) the moment any of: (1) a
reproducible hang or corruption on `0003` itself at 1000 or 1200 MHz on real 6.18 hardware — the
single largest evidence hole today is that **zero 1000 MHz data points exist on either
implementation**; (2) evidence the July field hard-hang (`docs/debug-tooling.md:5-30`, fixed by
PR #24) was the PLL *transition* itself rather than sustained 1.2 GHz operation; (3) a measured
TWD timer defect under `0003` at the 400 MHz operating point (`0003` never calls the CCF, so
`smp_twd`'s clk-notifier-driven rate correction never fires — a real, narrow defect the fork's
design fixes for free); or (4) a decision to converge this repo's `drivers/clk`+`drivers/cpufreq`
export with the fork's tree. None of the four hold as of this increment. Nothing flips this to
option C — its premise (that the two drivers differ on the boost/`scaling_max_freq` contract) is
refuted (§3), and C would re-create the PR #24 auto-overclock bug.

### 6.2 AIC8800 — deferred, re-open trigger is two cheap checks

Per `memo-Q9-aic8800.md` §8, re-open the moment either (a) stock's `firmware.tar.gz` gains
`fmacfw_*`/`fw_patch_*`/`fw_adid_*` entries, or (b) the upstream vendor repo is identified (grep
any candidate tree for `1a4b0054d2M` or `2026_0123_5f7be68d` in `rwnx_version_gen.h`) and that
repo carries both a LICENSE file and the firmware. Both checks are one `tar tzf` and one `git
grep`; neither needs hardware. If ever approved, the only admissible carry form is a Buildroot
kernel-module package (two ordered `M=` passes with `KBUILD_EXTRA_SYMBOLS`, since
`aic8800_fdrv` imports nine symbols from `aic_load_fw` — `pkg-kernel-module.mk`'s single `M=`
assumption does not fit as-is) plus a separate firmware package.

### 6.3 Rootfs-side release delta — not this increment's scope

Release 20260907 also replaced `rootfs.tar.bz2` (82,617,954 → 82,661,550 bytes), which
`PLAN.md` §1.1 explicitly flagged as out of scope for a *kernel* increment — that re-inventory
belongs to `docs/stock-reconciliation.md` and is the concurrent Wave 3 documentation-refresh
task's responsibility (`fork-sync-2026-09/PLAN.md` §5.2, `W3-docs-refresh`), not this one. If
that task reports the rootfs-side re-inventory incomplete when it lands, it remains an open
follow-up independent of everything in this document; this increment did not re-run it and does
not claim to have.

### 6.4 The 6.18.50/7.2.4 pin gap — still open, restated

Every vanilla-6.18 quote behind every disposition and memo in this increment is against the
**6.18.49 release commit** (`1c732c6b94f0faee1526bd375add2fe10cba2e26`, `linux-6.18.y`), not the
**v6.18.50** tag `configs/fragments/de10nano.fragment` actually pins — v6.18.50 was unreachable
from the authoring session (`fork-sync-2026-09/env.md`: the gregkh GitHub mirror lags one stable
release behind kernel.org, which the session's proxy blocks outright). Likewise every 7.x quote
is against **7.2.3**, not the **7.2.4** the RT/beta series pins. `commits.jsonl`'s
`_meta.vanilla_target` records this honestly (`"6.18.49 (release commit; v6.18.50 tag
unreachable when this increment ran)"`) rather than silently advancing to `6.18.50`. The `-F0`
apply in CI against the real 6.18.50/7.2.4 tarballs is the loud backstop for any of the ten items
above; the silent half — a `.49→.50`/`.3→.4` stable commit quietly moving a hunk one of these
ten sits on — is closed by re-running the drift walk `env.md` documents (one `git log` per
series) the next time a tree carrying those tags is reachable. Nothing in this increment's own
evidence turns on a single point release between `.49` and `.50` (the previous increment's
`v6.18.39→6.18.49` drift walk found 42 collisions across 37 patches, all disjoint or
overlapping-compatible, zero superseded/conflicting — `stable-drift-6.18.39-49.md`), but per the
grounding contract that is stated, not assumed, for the `.50` gap specifically.
