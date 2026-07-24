# Fork-sync increment — 2026-07-24

The first *incremental* run of the reconciliation. The original pass
(`MISTER-KERNEL-PATCH-RECON.md`) reconciled 108 fork commits in one campaign; this document
covers what has landed on `MiSTer-devel/Linux-Kernel_MiSTer` since, using the same
methodology at a scale that fits the input.

**Outcome: one config change to our build (`CONFIG_TUN=y`), one prose-only disposition
retrofitted with evidence, and both `fork-sync.conf` pointers advanced.** The adversarial
pass (§7) additionally surfaced two items that are *not* part of this sync but should not be
lost: a known-open NSO Genesis limitation upstream has now fixed, and a duplicate device-ID
entry in our own patch `0017`. Both are recorded in §8 as follow-ups.

---

## 1. What was new

`scripts/check-fork-sync.sh` against the sync points recorded in `fork-sync.conf`
(`MiSTer-v5.15 @ 794e6f002`, `MiSTer-v6.18 @ d9ac12a691`):

| Branch | New commits | Nature |
|---|---:|---|
| `MiSTer-v5.15` | **1** | `5fcfae369` — `config: enable CONFIG_TUN for tap device support (#76)` |
| `MiSTer-v6.18` | **57** | Sorgelig's own forward-port of the MiSTer series onto `v6.18.38` |

The 57 are the headline surprise, and they are not 57 new decisions. Between 2026-07-21 and
07-23 Sorgelig independently forward-ported the whole MiSTer series onto vanilla `v6.18.38`,
rooted at the *same* base commit `d9ac12a691` our export (PR #75) replays onto — developed in
parallel with it, not derived from it. Every one of those commits is a re-port of content
already dispositioned from the `MiSTer-v5.15` branch (§3).

**Baseline note.** Stock ships `5.15.1`; `MiSTer-v5.15` is therefore the source of truth for
*what stock has*, and it is the branch this reconciliation is measured against. `MiSTer-v6.18`
is the destination of the forward-port effort we are contributing to, so it is tracked, but a
commit appearing there is evidence about the port, not about stock.

---

## 2. `CONFIG_TUN` — the one real action

`5fcfae369` (Nigel Shearman, PR #76) flips a single line in stock's defconfig:

```diff
-# CONFIG_TUN is not set
+CONFIG_TUN=y
```

Why it matters, in the commit author's own framing: a WiFi *station* cannot emit frames
bearing a second source MAC. `CONFIG_MACVLAN` — which we already carry
(`linux.config:168`, added in the previous increment) — therefore cannot give an emulated NIC
such as the Amiga A2065 its own address over wireless the way it can on wired `eth0`.
Routing through a tap device is the only way out there. Wired users were already served;
WiFi users were not.

Disposition: **`dropped-deliberate`** with the functionality supplied via
`dependencies.superseded_by`, following the `CONFIG_MACVLAN` record (`f0fb626ac`) exactly.
Per `worker-instructions.md`, `carried` is reserved for commits with a named `00xx-*.patch`;
our kernel config lives in `board/mister/de10nano/linux.config`, not in an
`arch/arm/configs` defconfig, so a one-symbol stock defconfig change is mirrored as a config
line rather than a patch file. The fork's *hunk* is dropped; the *capability* is provided.

### Verified, not assumed

`linux.config` is a **minimal** defconfig — a written symbol is not necessarily a resolved
one (see `docs/kernel-recon/` sibling notes and the `NFS_V3` trap). So the symbol was
resolved against the real tree:

```bash
S=$(mktemp -d); cp board/mister/de10nano/linux.config $S/.config
make -C /mnt/source/linux O=$S ARCH=arm olddefconfig      # /mnt/source/linux @ v6.18.39
```

* `CONFIG_TUN=y` survives at resolved line 1416.
* `CONFIG_INET=y` (861) satisfies `depends on`; `CONFIG_CRC32=y` (4290) satisfies `select`.
* Resolving the pre-change file and diffing the two outputs yields **exactly one changed
  line** — no side effects, nothing else flipped on.
* `CONFIG_TAP` stays off deliberately: it backs `macvtap`/`ipvtap`, whereas `/dev/net/tun`
  already yields both `tunX` and `tapX`. `CONFIG_TUN_VNET_CROSS_LE` stays at default `n`, as
  the fork commit left it.

`=y` not `=m` matches both the fork's reasoning and our `MACVLAN` precedent: the module
directory name does not match `uname -r` on MiSTer, so module autoload is unreliable.

### We are ahead of the fork's own 6.18 branch here

This landed on `MiSTer-v5.15` on **2026-07-24**, one day *after* Sorgelig committed the
`MiSTer-v6.18` defconfig (`e8f065dbf8`, 2026-07-23) — which still reads
`# CONFIG_TUN is not set` at its line 1383. Stock's 5.15 line is the source of truth, so we
follow it; the fork's 6.18 branch simply has not picked this up yet. **Worth raising with
Sorgelig as part of the forward-port effort (PR #75).**

### Follow-up: the export tree needs regenerating

`scripts/export-kernel-tree.sh` derives `arch/arm/configs/MiSTer_defconfig` from
`linux.config`, so our export picks this up automatically — *but only when it is next run*.
Until then `fork/MiSTer-v6.18:arch/arm/configs/MiSTer_defconfig` still has `CONFIG_MACVLAN=y`
and no `CONFIG_TUN` line at all. **Regenerate and re-push the export before PR #75 is
updated.** That is a fork-repo action, deliberately out of scope for this PR.

This is not only a defconfig refresh. `fork/MiSTer-v6.18`'s `Makefile` still reads
`SUBLEVEL = 38` while `configs/mister_de10nano_defconfig:130` pins **6.18.39**, so
regeneration also rebases the series onto a new v6.18.39 base commit and produces a
`mister-6.18.39` tag. Left alone, PR #75 offers upstream a tree one stable release behind the
kernel our image actually builds.

---

## 3. The 57 `MiSTer-v6.18` commits — why none is new work

Two independent checks, because subject matching alone is weak evidence.

**(a) Subject-set comparison.** Of 57 subjects, exactly three lack a byte-identical twin on
`MiSTer-v5.15`, and all three are renames of commits we already hold records for:

| `MiSTer-v6.18` subject | Already dispositioned as |
|---|---|
| `exfat: support for symlinks.` | v5.15 `Add exFAT with symlinks support.` + `exfat: use ATTR_SYSTEM as symlink flag…` — we carry `0031-exfat-samsung-symlinks.patch` |
| `fix for 3rd party DS4 failing to connect by wire.` | v5.15 `hid-sony: fix for 3rd party DS4 failing to connect by wire.` — `0022-hid-playstation-ds4-mac-fix.patch` |
| `Add MiSTer_defconfig` | v5.15 `Add defconfig.` lineage — handled on the config axis |

**(b) Tree-diff backstop (§3.3 of the plan — "every byte of divergence", not "every
commit").** Both 6.18 branches share base `d9ac12a691`, so they diff directly:

```bash
git diff fork/MiSTer-v6.18 origin/MiSTer-v6.18        # '+' = upstream has, we lack
```

Excluding the vendored out-of-tree drivers — `drivers/net/wireless/realtek/rtl88*` and
`drivers/hid/xone`, which we ship as Buildroot packages rather than in-tree — the result is
two independent ports of the same features: differing comment wording, brace style, and patch
decomposition. Three deltas are genuinely behavioural, and **all three are already
dispositioned**:

| Delta | Disposition |
|---|---|
| `drivers/spi/spidev.c` — `{ .compatible = "altspi" }` | Record `246984fce`: dropped. Our DTS `0004` retargets the node to `rohm,dh2228fv`, which vanilla `spidev` already accepts; `grep` of Main_MiSTer finds zero references to `altspi` (only to `/dev/spidev1.0`). |
| `include/uapi/linux/vt.h` — `MAX_NR_CONSOLES 63 → 9` | Record `b2a04cbfd`: dropped. Main_MiSTer only ever activates VT 1 and VT 2 and never references the constant; keeping vanilla's 63 is the zero-risk choice. |
| `drivers/hid/hid-nintendo.c:2175-2177` — NSO Genesis `hdev->product` `0x2017` → `USB_DEVICE_ID_NINTENDO_GENCON` | Record `b00a72159`: `dropped-upstream`, **but flagged a present-day KNOWN LIMITATION with a carry recommendation**. Upstream has now implemented it; we have not. Dispositioned ≠ closed — see §8.1. |

Two further *structural* differences, neither behavioural for our image, named so a later pass
does not rediscover them as gaps:

* **DTS packaging.** Upstream keeps the fork's DTS as a separate file
  `socfpga_cyclone5_de10_nano.dts` (+205 lines, plus its own `Makefile` `dtb-` entry) and
  leaves vanilla's `socfpga_cyclone5_de10nano.dts` byte-identical; our `0004` patches the
  vanilla file instead. The two trees therefore emit **differently named DTBs** — relevant to
  anything keyed on the DTB filename.
* **`socfpga.dtsi` `i2c1 clock-frequency = <100000>`** — present upstream, dropped by us.
  Inert *because* `socfpga.dtsi:689` marks `i2c1` `status = "disabled"` and no board DTS
  re-enables it; if the node were ever enabled this would stop being inert.

Notable in the other direction — ours-only, upstream dropped them, nothing to sync:
`drivers/cpufreq/socfpga-cpufreq.c` plus its `Kconfig.arm`/`Makefile` entries (our overclock
patch `0003`), `include/linux/loop.h`, and the `loop_set_backing_fd()` export in
`drivers/block/loop.c`.

Two further divergences where **upstream's port, not ours, drifts from stock** — recorded so
a later pass does not "fix" them backwards:

* **`BTN_Z` scope.** Upstream declares `BTN_Z` in the *shared* `ps_gamepad_buttons[]` table
  (`hid-playstation.c:568`), consumed by `ps_gamepad_create()` which upstream calls from
  both `dualsense_create()` and `dualshock4_create()` — so their DualShock 4 also gains
  `BTN_Z`. We scope it to DualSense via `input_set_capability()`. Stock v5.15 is on **our**
  side: its table is DualSense-only (`ps_gamepad_create()` has exactly one caller there).
  Patch `0037`'s forward-port note states this and was verified accurate.
* **NSO right-Famicom d-pad.** We call `joycon_report_dpad()`/`joycon_config_dpad()`;
  upstream's 6.18 does not. Stock v5.15 sets up the hat for every NSO controller
  unconditionally, and vanilla has no Famicom support at all — so again ours matches stock.

Non-substantive upstream-only additions, listed so they are not later mistaken for gaps: a
`bt_dev_err()` diagnostic dump in `btusb_setup_csr()`; `hid_dbg_ratelimited()` where we use
`hid_dbg()`; and Joy-Con combo-LED registration ordered *after* the home LED (we register it
before, so a home-LED failure cannot skip it).

---

## 4. Retrofit — `794e6f002` had no record

`fork-sync.conf` was advanced past `794e6f002` ("New driver for RTL8821CU") on 2026-07-16
with the reasoning stated **only in that file's comment**. That is precisely the
"seen, not reconciled" failure the file's own `UPDATING` note warns against, so this pass
went back and supplied the evidence as
`records/794e6f002d0f655c504733c126a01f8c1f0bc1d4.json`.

Disposition **`dropped-upstream`**, `superseded-better`. The commit bulk-vendors a newer
`rtw88` tree onto a 5.15 base to obtain 8821CU support that mainline then lacked; vanilla
`v6.18.39` carries it natively at `drivers/net/wireless/realtek/rtw88/Kconfig:195`. The
decisive evidence is that the fork's vendored tree uses the *same upstream symbol names*, so
its defconfig hunk compares directly against our resolved config:

| Symbol set by `794e6f002` | Our resolved config |
|---|---|
| `RTW88=m`, `RTW88_CORE=m`, `RTW88_USB=m`, `RTW88_8821C=m`, `RTW88_8821CU=m`, `RTW88_LEDS=y` | all present (lines 1688, 1689, 1690, 1693, 1703, 1709) |
| `RTW88_DEBUG=y`, `RTW88_DEBUGFS=y` | **deliberately off** — developer instrumentation; adds log noise and debugfs surface to a shipping image, no effect on whether a dongle associates |

`BR2_PACKAGE_RTL8821CU_MORROWNR` stays absent from our defconfig: with in-tree
`rtw88_8821cu` enabled, an out-of-tree driver for the same chip would race it for the same
USB IDs.

---

## 5. Version drift — grounding moved to v6.18.39

The original recon was grounded on `v6.18.38`. `configs/mister_de10nano_defconfig:130` now
pins **6.18.39**, so every check in this increment was run against a clean `v6.18.39`
checkout — commit `f89c296854b755a66657065c35b05406fc18264d` — and `commits.jsonl`'s `_meta`
was updated to match. (Note for future increments: `v6.18.39` is an *annotated* tag, so
`git rev-parse v6.18.39` yields the tag object `e871c68d…`, not the commit. `_meta` records
commit SHAs, as it did for 6.18.38; use `git rev-parse v6.18.39^{commit}`.)

`reduce.py` now reads the version from `_meta` instead of a hardcoded literal, so
`reconciliation.md` cannot silently claim the wrong base on the next pin bump.

### Impact check on the existing dispositions — the risk a version bump actually carries

Moving the grounding is not free: a stable bump can land a fix that supersedes or conflicts
with a carried patch, and nothing would announce it. Checked explicitly:
`v6.18.38..v6.18.39` is 496 commits over 474 files. Intersected against every path our
carried series touches, **exactly two collide**:

| File | Stable change | Our patch | Verdict |
|---|---|---|---|
| `drivers/bluetooth/btusb.c` | Mercusys `2c4e:0128` ID, `#else` OOB-wake stubs, probe-unwind UAF fixes | `0036` CSR-clone `lmp_subver 0x2512` detection | textually disjoint, unrelated intent |
| `fs/exfat/dir.c` | `exfat_find_dir_entry()` uniname bounds hardening | `0031` Samsung symlinks | different hunk region |

Neither supersedes a carried patch. Confirmed at the build level rather than by reading:
`output/build/linux-6.18.39/` carries both `.stamp_patched` and `.stamp_built`, and the
patched content is verifiably present in the tree (`fs/exfat/namei.c` symlink handling,
`btusb.c` `0x2512`). `worker-instructions.md` has been amended so future workers ground on the
version we actually ship.

---

## 6. Regeneration

`docs/kernel-recon/` is **generated from `records/*.json`** — `reconciliation.{jsonl,md}`,
`disagreements-with-provenance.md`, `silent-regressions.md` and `device-support.md` all come
out of `reduce.py`, which also enforces the §5 invariants. After adding the two records:

```
records: 125  problems: 0
dispositions: {carried: 50, carried-upstream-only: 1, dropped-upstream: 22,
               dropped-deliberate: 44, dropped-obsolete: 8}
```

Zero invariant violations: no orphan carried patches, no missing records, no
evidence-free `dropped-upstream` rows.

Hand-maintained in that directory (i.e. *not* regenerated, and the things that go stale
silently): `fork-sync.conf`, `commits.jsonl`, `worker-instructions.md`, `phase0-report.md`,
`pilot-report.md`, `orchestration-state.md`, `old-branch-residue.md`,
`tree-diff-attribution.md`, and this file.

---

## 7. Verification pass

The three load-bearing claims were re-checked by independent agents instructed to *refute*
them, grounded on the live trees (`ESCALATE` criteria per `worker-instructions.md` §Final):

| Claim | Verdict |
|---|---|
| `CONFIG_TUN=y` achieves stock parity, no missing companion symbol, no side effects | **CONFIRMED** |
| `794e6f002` is fully covered by mainline `rtw88_8821cu` (incl. USB VID:PID equivalence) | **CONFIRMED** |
| The 57 `MiSTer-v6.18` commits introduce no functionality new to our export | **PARTIALLY REFUTED** — see §8 |

**`CONFIG_TUN` — confirmed.** The suspected defect (that the commit says "tap" but we did not
enable `CONFIG_TAP`) was chased specifically and refuted: `CONFIG_TAP` at
`drivers/net/Kconfig:420` is a promptless `tristate` *selected by* drivers implementing the
tap userspace interface (macvtap/ipvtap); `/dev/net/tun` alone already yields both `tunX` and
`tapX`. Whole-neighbourhood comparison against stock's defconfig `:1296-1313` matches on every
value. Main_MiSTer coupling re-checked: `git grep -nE 'net/tun|TUNSETIFF|IFF_TAP|IFF_TUN'`
→ zero hits, as is `dev/net` and `if_tun`.

**`794e6f002` — confirmed, and the deferred crux is closed.** Both USB ID tables were
extracted and compared: **15 IDs each, sets identical**, differing only in ordering. No
dongle regresses. Two prose overstatements in the record were corrected in the process (the
vendored snapshot does define `RTW88_8821AE`/`RTW88_8812AE` which vanilla lacks — but those
are PCIe parts and our resolved config has `# CONFIG_PCI is not set` at line 1181, so they
are unreachable on a DE10-Nano).

**xone — closed in our favour.** Our pin (`package/xone/xone.mk:50`, `dlundqvist/xone`
`f2aa9fe0…`) is **newer than and a strict superset of** upstream's vendored copy. All three
of Sorgelig's xone deltas (`861a469229` paddles, `fc87de1c04` per-PID firmware, `e000b73074`
pairing sysfs) are already native features of our pin, which additionally exposes
`active_clients`/`poweroff` sysfs attributes and a firmware requester with fallback. USB
device-ID tables are identical. **No action needed.**

Three defects in this increment's own records were found and fixed: an overstated Main_MiSTer
grep claim, an empty `device_ids` list, and a `_meta.vanilla_commit` that held the *annotated
tag object* rather than the commit.

---

## 8. Follow-ups — found here, deliberately not actioned here

Neither of these is stock parity, so neither is in scope for the increment that closes this
sync. Both are real and should not be lost.

### 8.1 NSO Genesis/Mega Drive product normalization — a known-open item upstream has now fixed

Upstream's 6.18 port carries a hunk our export does not
(`origin/MiSTer-v6.18:drivers/hid/hid-nintendo.c:2175-2177`):

```c
if (hdev->product == USB_DEVICE_ID_NINTENDO_SNESCON &&
    ctlr->ctlr_type == JOYCON_CTLR_TYPE_GEN)
	hdev->product = USB_DEVICE_ID_NINTENDO_GENCON;
```

Over Bluetooth an NSO Genesis pad presents PID `0x2017` (SNES), so Main_MiSTer's
`gamecontroller_db.cpp:544/554` GUID lookup selects the **SNES** row and the pad is
mismapped. Record `b00a72159` already dispositions the originating commit `dropped-upstream`
**but flags exactly this as a present-day KNOWN LIMITATION with an explicit carry
recommendation** — so this is a known-*open* item, not new work, and the "nothing new on
v6.18" framing must not be read as closing it.

Note **stock v5.15 does not have this fix either** — upstream authored it during their 6.18
forward-port. Carrying it is therefore an improvement over stock, not stock parity, which is
why it is a follow-up rather than part of this sync.

### 8.2 Duplicate Qanba device ID in our patch `0017`

`board/mister/de10nano/linux-patches/0017-xpad-mister-deltas.patch:186` inserts
`XPAD_XBOX360_VENDOR(0x2c22)` at the head of `xpad_table[]`, but vanilla v6.18.39 already
carries it in sorted position (`drivers/input/joystick/xpad.c:585`). Our built tree therefore
has it **twice** — verified at `output/build/linux-6.18.39/drivers/input/joystick/xpad.c:563`
and `:617`. Functionally harmless (first match wins), but wrong, and doubly awkward because
the patch header at line 43 asserts this entry "is the only piece of it this patch still
needs to add itself" — false against 6.18 — while lines 72-75 criticise the fork for
inserting an entry out of order at the top of the table, which is precisely what the hunk
does. Fix: drop the hunk, and correct the header claim so delta 2 adds only the
`xpad_device[]` row.

### 8.3 `check-fork-sync.sh` cannot see a branch that is not already listed

The script iterates only the branches named in `fork-sync.conf`, so a **new** fork branch
produces no drift signal — it is invisible until a human notices. That is not hypothetical:
`MiSTer-v6.18` was created 2026-07-16 and entered the file only because someone spotted it.
`origin/MiSTer-v5.14`, `origin/MiSTer-v5.13.12` and `origin/origin` are likewise unlisted
(verified frozen since 2021, so no drift today, and covered by the 15 old-branch residue
records). One `gh api repos/$FORK/branches` call comparing the live branch inventory against
the conf's keys would close the hole — the same "make it a fact rather than a memory" move
this file was built on.
