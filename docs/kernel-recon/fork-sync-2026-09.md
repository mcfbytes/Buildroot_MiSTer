# Fork-sync increment — 2026-09-11

The third incremental run of the reconciliation, and the first that follows a **stock release**
rather than the fork's own development. On 2026-09-07 stock MiSTer shipped its first 6.18
kernel (`Linux_Image_creator_MiSTer` "Release 20260907", `MiSTer-v6.18` @ `aec7dc3aa`, kernel
`6.18.38-MiSTer`) — which inverts the baseline this whole reconciliation project has used since
its first campaign: `MiSTer-v6.18` is now what every stock MiSTer runs, and `MiSTer-v5.15` is
frozen history. Within four days of that release, users found regressions in it and the fork
took **nine** commits and one still-open PR to address them; this document reconciles those **ten**
items against this repo's own 6.18 build.

**Outcome: five items carried as new/changed patches (Q3, Q5, Q6, Q8, Q10), three dropped as
already covered (Q1, Q2, Q7), one driver-replacement deliberately declined with a tracked
bench-gated follow-up (Q4), and one 82,000-line out-of-tree driver deferred pending two answerable
external facts (Q9).**

| # | Finding | Kind | Action |
|---|---|---|---|
| 1 | Stock 20260907 shipped with **no cpufreq driver at all** and **no driver for RTL8811AU/8821AU dongles** — regressions vs. this image, which has had both since July | stock is behind us, not the reverse | none needed; recorded for the record (§2, §4.3) |
| 2 | Our `docs/abi-contract.md` and `docs/patch-provenance.md` described the cpufreq `boost` sysfs file as non-existent | **our own docs were stale**, and user-visible today | corrected in both docs + a new FAQ entry (§3) |
| 3 | A 2026-07-24 ledger defect — four carried patches (`0039`-`0042`) unreachable from any record's `carried_patch` — found by `reduce.py`'s own orphan invariant | pre-existing process gap, unrelated to this queue | fixed: `reduce.py` now reads a `carried_patches` (plural) list; four origin records updated (§5) |
| 4 | An open PR (#92) carried ahead of its own merge, for the first time in this project | new pattern, deliberate (owner decision D3) | carried as `0049`, keyed on the PR head SHA with an explicit re-key procedure for when it merges (§2) |
| 5 | A community re-implementation of the overclock driver (`59bcae8eb`, #85) — better-engineered, unvalidated on our image | decision required | **kept `0003`** (owner decision D1=A); DTS OCRAM hygiene hunk still carried; option B tracked bench-gated (§2) |
| 6 | An 82k-line vendored Wi-Fi/BT driver (`c129b0fac`, AIC8800 — 142 files, 82,330 insertions) with no firmware and no license file | decision required | **deferred** (owner decision D2); compiles clean, zero USB-ID conflicts, but inert without ~60 firmware blobs stock does not ship either (§2). **Reversed 2026-09-10:** packaged as `package/aic8800` with firmware (§6.2) |

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

**Q9 `c129b0fac` (AIC8800 Wi-Fi/BT driver) — `not-evaluated`, owner decision D2=defer.**
*(Overtaken 2026-09-10: D2 reversed, record now `carried-as-package` → `package/aic8800`; §6.2.)* 142
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
| NSO Genesis BT PID, N64/Genesis button maps, IMU name suffix, LED classdev names, DS lightbar names | `0038`-`0042` | **no** at the time — upstream's port still lacked them. *Update 2026-09-12:* `0038` he already had; `0039` merged as #95; `0040`/`0041` **closed** as #96/#97 in favour of Main_MiSTer #1307/#1308 and retired from our series; `0042` unsent |
| 8BitDo USB Wireless Adapter reset loop | fixed this increment, `0049` | PR #92, still open |

The `0038`-`0042` row remains the material for an optional Wave 5 (upstream PRs carrying what
stock 6.18 users are missing) — not actioned in this increment. (Actioned 2026-09-12; see
`fork-sync-2026-09/STATUS.md` D6 for the outcome.)

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
orphans remain: `python3 docs/kernel-recon/reduce.py` reports **136 records, problems: 0**, and its
regenerated outputs (`reconciliation.{md,jsonl}`, `device-support.md`, `silent-regressions.md`,
`disagreements-with-provenance.md`) are committed alongside. **Precision note (Wave-4 audit,
2026-09-11):** `carried_patches` is described above and in `reduce.py`'s comment as "patches split
out of one origin commit's diff", which is literally true only for `b00a72159` → `0038`+`0039`.
For `0040`, `0041` and `0042` the second patch restores a *stock ABI string* (`" IMU"` suffix,
`player1..4`/`home` LED classdev names, `:red`/`:green`/`:blue` lightbar names) that no single fork
commit's diff produced — each is attributed to the commit `patch-provenance.md` §11's table names
as its origin, which is the authority used here, not to a hunk of that commit. The mapping matches
§11 row for row; the mechanism's name overstates how tight the link is.

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

> **Overtaken 2026-09-10:** the owner reversed D2 after Wave 3 (this repo's #163, merged into this
> branch). `package/aic8800` builds both modules with the two ordered `M=` passes this section
> asked for and ships all six firmware variants from `radxa-pkg/aic8800` — the same SDK snapshot
> stock vendored (`2026_0123_5f7be68d`), which also answers trigger (b). Trigger (a) has still
> not fired: stock ships neither the module nor the blobs. The licence question was accepted, not
> resolved; there is no hardware test. `memo-Q9-aic8800.md` §9–§10 and `docs/wifi-parity.md`
> §10.1 record the reversal; the ledger record is `carried-as-package`. The paragraph below is
> kept as written.

Per `memo-Q9-aic8800.md` §8, re-open the moment either (a) stock's `firmware.tar.gz` gains
`fmacfw_*`/`fw_patch_*`/`fw_adid_*` entries, or (b) the upstream vendor repo is identified (grep
any candidate tree for `1a4b0054d2M` or `2026_0123_5f7be68d` in `rwnx_version_gen.h`) and that
repo carries both a LICENSE file and the firmware. Both checks are one `tar tzf` and one `git
grep`; neither needs hardware. If ever approved, the only admissible carry form is a Buildroot
kernel-module package (two ordered `M=` passes with `KBUILD_EXTRA_SYMBOLS`, since
`aic8800_fdrv` imports nine symbols from `aic_load_fw` — `pkg-kernel-module.mk`'s single `M=`
assumption does not fit as-is) plus a separate firmware package.

### 6.3 Rootfs-side release delta — not this increment's scope

> **Overtaken 2026-09-11:** the parallel workstream's PRs #157–#160 (stock release verification, the rtl8xxxu firmware, the release pin, and the vendored `uartmode`/`S39usb-coldplug`) landed on master the same day and are merged into this branch; the rootfs-side gaps this section anticipates are closed there (`docs/verification/stock-release-20260907.md`, `docs/stock-reconciliation.md` §3d).

Release 20260907 also replaced `rootfs.tar.bz2` (82,617,954 → 82,661,550 bytes), which
`PLAN.md` §1.1 explicitly flagged as out of scope for a *kernel* increment — that re-inventory
belongs to `docs/stock-reconciliation.md` and is the concurrent Wave 3 documentation-refresh
task's responsibility (`fork-sync-2026-09/PLAN.md` §5.2, `W3-docs-refresh`), not this one. If
that task reports the rootfs-side re-inventory incomplete when it lands, it remains an open
follow-up independent of everything in this document; this increment did not re-run it and does
not claim to have.

**Update (Wave-4 audit, 2026-09-11):** that task did land, in the same commit as this document
(`docs/stock-inventory/20260907/`, `docs/stock-reconciliation.md` §0). It found the userland
outside kernel/modules/firmware byte-for-byte unchanged — and **one thing PLAN.md §1.1 got
wrong**: `addon.tar` is *not* unchanged against the `8aba321` baseline this repo's §3 audit was
built from. Same size, different sha256; a **new** `etc/init.d/S39usb-coldplug`, and a **changed**
`usr/sbin/uartmode` (new `fuser -k` kill path, a `169.254.*` filter in PPP IP detection, PPP
exit-status handling, and a new mode `"6"` launching `/media/fat/snid`). Our vendored copy has not
picked either up. That is a live follow-up owned by `docs/stock-reconciliation.md` §0.3, not by
this kernel increment, and it is recorded here so it is not lost between the two.

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

---

## 7. Audit (Wave 4)

Audited 2026-09-11 by an independent pass over `53a9a7c` (Waves 0–2), `b502662` (Wave 3) and
`f7b59f5` (export), re-deriving every claim from the same trees `env.md` names. Full table, with
the evidence for each row: [`fork-sync-2026-09/audit-findings.md`](fork-sync-2026-09/audit-findings.md)
— **112 claims checked, 80 confirmed, 28 corrected, 2 unverifiable.**

**Nothing contradicted a disposition.** Every one of the ten `disposition` values survives
independent re-derivation, and every carried patch's hunks are the fork's own change with no
accidental extra edit:

- `0048` is byte-identical to `41c45f378`'s diff; `0050` to `9854075c8`'s; `0049`'s added and
  removed lines are identical to `refs/pull/92/head`'s with only the `@@` anchors regenerated;
  `0017` delta 5 reproduces `7c75b1b46`'s two hunks exactly; `0001`'s `fb_ops` now matches
  `ea2212221`'s choice; `0004`'s new node reproduces every property of `60e0d56bdd`'s `&ocram`
  override.
- All 40 patches in `linux-patches/` replay into a pristine 6.18.49 tree at `patch -p1 -F0`:
  **40/40, zero fuzz, zero rejects**. All 42 `linux-patches-beta/series` entries replay into a
  pristine v7.2.3 tree the same way: **42/42**. `scripts/lint-kernel-patches.sh` passes.
- All ten `commits.jsonl` rows were recomputed from the fork with `git show --numstat`: author,
  email, date, subject, insertions and deletions match **exactly**, ten for ten.
- `docs/kernel-config-deltas.md` §11's headline numbers were reproduced end to end from its own
  stated command: **1,229 / 1,289 / 27 / 87**, and the 27-symbol stock-only list matches its four
  classes name for name.
- The boost-ABI correction is right: 6.18.49's `cpufreq.c:2845-2847` gates the `boost` file purely
  on `->set_boost`, which `0003` sets — so the file exists and `scaling_max_freq` clamps to
  800000 until boost is written, exactly as `abi-contract.md`, `patch-provenance.md` §11 and
  `docs/user/faq.md` now say.

### 7.1 Corrections made by this audit

**Records** (the recurring pattern: Wave 3 flipped `disposition`/`carried_mode` but left Wave-1
prose that described the older state):

1. `records/59bcae8eb….json` (Q4) opened "DISPOSITION IS DELIBERATELY `needs-verification`" while
   the field said `dropped-deliberate`. Opening rewritten; the body is untouched Wave-1/2 analysis
   and now says so.
2. `records/c129b0fac….json` (Q9) opened "Disposition is needs-verification, **NOT** not-evaluated"
   while the field said `not-evaluated` — a direct self-contradiction. Opening rewritten.
3. `records/7c75b1b46….json` (Q5) opened "CARRY, PLANNED, **NOT YET AUTHORED** … it does not itself
   modify `0017`". It was authored in Wave 3. Rewritten.
4. `records/ea2212221….json` (Q3)'s `recommendation` ended "advisory only — no patch file was
   edited". D4 was taken and both `0001` copies were edited. Rewritten.
5. `records/a14b5e8e1….json` (Q10) said `carried_mode='planned'` inside notes whose field reads
   `re-implemented`, and cited "#88 and #91's merged commits differ from their PR heads" as
   evidence that a merge may carry a modified hunk. Measured: `git patch-id --stable` is
   **identical** head↔merge for both (`6a080ee6d7bb…`, `347bc8291a32…`) — they differ in SHA,
   author and message only. Both corrected, here and in `0049`'s header and `fork-sync.conf`.

**Patch headers** (headers only — no diff hunk was touched):

6. `0004`'s "carried here verbatim (node text matches the fork's)" was not true: every *property*
   is verbatim, but we add a 10-line comment the fork deliberately omits ("No source comments are
   added" — `60e0d56bdd`'s own message). Both the prose block and the `Forward-port:` note now say
   which half is verbatim and which is ours.
7. `0049`'s "WHEN #92 MERGES" step (2) now states the measured patch-id result instead of implying
   a modified hunk is the expected case.

**Ledger:**

8. `fork-sync.conf`'s branch-description paragraph still read "the queue past the pointer below
   (**8 commits** + open PR #92) is planned, **not yet dispositioned**". It is 9 commits (measured
   `git rev-list --count`), and it is dispositioned — the pointer was advanced in the same commit.
9. `carried_patches` is described as "patches split out of one origin commit's diff". True for
   `b00a72159` → `0038`+`0039`; **not** literally true for `0040`, `0041`, `0042`, which restore a
   stock ABI string that no single fork commit's diff produced. §5 above now says so. The mapping
   itself matches `patch-provenance.md` §11 row for row and is unchanged.

**Shipped docs** — the two that are wrong about the product, not about process:

10. **`README.md`'s hardware table said stock 6.18 has "no driver for RTL8710BU or RTL8188FU".**
    False: 6.18's `rtl8xxxu` links `8188f.o` and `8710b.o` unconditionally and binds both outside
    the `RTL8XXXU_UNTESTED` guard (`core.c:8060-8062`, `:8108-8112`); `rtl8xxxu.ko` is in stock's
    module list and `rtlwifi/rtl8188fufw.bin` + `rtl8710bufw_{SMIC,UMC}.bin` are in its firmware
    list. The same false premise justified a "no consumer" disposition in
    `docs/stock-reconciliation.md` §0.1 — **we build `CONFIG_RTL8XXXU=m` too**, so that row is now
    an untriaged firmware gap on our side, not a justified absence.
11. **`README.md` credited stock 6.18 with "newly covering" RTL8814AU, RTL8822CU and RTL8723DU.**
    The modules ship; `rtw88/rtw8814a_fw.bin`, `rtw8822c_fw.bin` and `rtw8723d_fw.bin` do not —
    the same `request_firmware()` failure shape README already flags for `mt7663u`.

**Counts** (all re-measured, not inferred):

12. `README.md` "37 patch files" and "all 37 patches apply cleanly" → **40**.
13. `README.md`'s delta paragraph: "126 reconciled commits (… 1 on `MiSTer-v6.18`)" → **136
    records** (110 + 10 + 1 PR head + 15 residue, per `reduce.py`); "36 carried patch files … a
    37th file `0047`" → 40 files, with `0048`/`0049`/`0050` named; and the sentence saying the
    6.18 queue "are queued, with a per-item plan" now says it was executed.
14. `docs/buildroot-config.md` still said the beta series "drops exactly ONE shared patch" and has
    "all 40 entries (the other 36 shared + four beta-local)" → **two** omissions, **42 entries**,
    38 shared, with the 42/42 `-F0` measurement.
15. `linux-patches-beta/series` said five shared entries are real re-anchored files and then
    "these **four** needed …" → five, named. Its "`make rt` is green on the whole 40" is now
    scoped to the date it was measured, since the list is 42 and `make rt` has not been re-run.
16. `de25nano/linux-patches/README.md` said "**Three** — `0015`, `0030`, `0037` — have a
    7.x-re-anchored copy" while its own row 25 says `0031` links to the beta copy too → four, and
    `0001` is the fifth divergent pair. Its `0047` row's "this board is on 7.2.2" is annotated
    against the README's own 7.2.3 pin.
17. `docs/kernel-export.md` §1.2 row 2's "53 of **62** commits are his" → 53 of **67** at the
    baseline that row itself declares (`c129b0fac`); no point on the branch gives 62.
18. `docs/firmware-parity.md` attributed "91 files" to
    `evidence/stock-20260907-firmware.txt`, which lists **89**. Both numbers are right for their
    own method (89 = `firmware.tar.gz`; 91 = the installed tree, i.e. those 89 plus
    `regulatory.db`/`.p7s` from `rootfs.tar.bz2`); the header now says which is which.
19. This document: "eight commits … those nine items" → nine and ten; the outcome line's "four
    carried, four dropped" → **five** carried (Q3, Q5, Q6, Q8, Q10) and **three** dropped as
    already covered (Q1, Q2, Q7); finding 6's "70k-line" → 82k (142 files, 82,330 insertions);
    §5's "verified … without running `reduce.py`'s full regeneration" → it *was* run and its
    outputs are committed (136 records, problems: 0); §6.3 now carries the `addon.tar` finding the
    rootfs-side task actually produced.

`python3 docs/kernel-recon/reduce.py` was re-run after every record edit above: **136 records,
problems: 0.**

20. **A Wave-3 artifact was left uncommitted.**
    `fork-sync-2026-09/tree-diff-2026-09.md` — the export/tree-diff backstop PLAN.md §5.2 puts at
    the tail of Wave 3, the same check that found the silent NSO-Genesis regression in July — is
    **untracked** in the working tree and is not in `b502662`. It should be committed with the
    increment. Its result was re-verified here and holds: of 55 distinct files differing between
    our patched 6.18.38 tree and `MiSTer-v6.18` @ `c129b0fac` (excluding AIC8800, xone, configs,
    Documentation and the fork's own DTS), every behavioural cluster is already dispositioned
    except its finding **F1** — the fork's `MiSTer_fb.c` `probe()` checks `memremap()` with
    `IS_ERR()`/`PTR_ERR()` and logs `devm_ioremap_resource`, a function it does not call
    (`c129b0fac:drivers/video/fbdev/MiSTer_fb.c:261-265`). Since `memremap()` returns `NULL` and is
    declared `void *` (`include/linux/io.h:158`), a failed mapping there would be reported as a
    *successful* probe with `fb_base == NULL`. **Nothing to fix on our side** — `0001`'s header
    item 7 already carries both halves of the correct check, and the shipped patch tests
    `if (!fbdev->fb_base)`. Confirmed independently in this audit, and the scope-correction
    addendum F1 recommends is now appended to `records/ea2212221….json`'s notes (that record
    analysed only the five-line `fb_ops` hunk, not the rest of the file). Candidate two-line Wave-5
    PR to the fork.

### 7.2 What this audit could not verify

- **`scripts/check-export-tree.sh`'s dry-run result** (`f7b59f5`: "PASS, 19 checks, 88,335 files
  identical, both DTBs identical, two exports with identical inputs give identical SHAs").
  Re-running it needs a full kernel build and the 6.18.50 tarball, which is unreachable here for
  the same reason Wave 0 recorded. Nothing found contradicts it; it is simply not re-measured.
- **Anything behind a GitHub PR or issue thread** — fork issue #84, PR #75's review, PR #85's
  review, PR #92's comments. Blocked from this session exactly as from Waves 0–3. Every claim that
  depends on one already says so and names what a human must paste; the audit adds no confidence
  to those, in either direction.
- The §3 stable-drift verdicts were **not** re-graded row by row. They are corroborated
  indirectly — a missed `superseded`/`conflicting` verdict is what a failed `-F0` replay looks
  like, and both series replay clean — and Wave 2 sampled 17 of the 42 independently.
