# Wave 4 — audit of the 2026-09 fork-sync increment

Audited 2026-09-11 against commits `53a9a7c` (Waves 0–2), `b502662` (Wave 3) and `f7b59f5`
(export) on `claude/kernel-6.18-patch-plan-l32pu9`. Grounding trees are the ones `env.md`
names: fork `MiSTer-v6.18` @ `c129b0fac` (+ `refs/pr/88`, `/91`, `/92`), vanilla
`linux-6.18.y` @ `1c732c6b94f0` ("Linux 6.18.49"), `linux-7.2.y` @ `58e7295cfeca` ("Linux
7.2.3"), `torvalds/linux` @ `50d05c7c76c9` (7.3-rc2), `Main_MiSTer` @ `6cda9cc546c4`,
`Linux_Image_creator_MiSTer` @ `d4e3f51`.

Everything below was re-derived in this session. Where a claim could not be checked from
the trees available, the verdict is **UNVERIFIABLE**, not "assumed correct".

**Totals: 112 claims checked — 80 CONFIRMED, 28 CORRECTED, 2 UNVERIFIABLE**, plus one measured
baseline row and one section added. Several corrections are the same underlying error restated in
a second document — notably the stale patch-series counts (five places) and the RTL8710BU/RTL8188FU
coverage claim (two places).

---

## 1. `carried` records vs. their patches and the fork diff

| # | Item | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|---|
| 1.1 | Q8 `41c45f378` | record names `0048-hid-google-stadiaff-classic2usb-retrozord.patch` | CONFIRMED | file exists; record `carried_patch` matches | — |
| 1.2 | Q8 | `carried_mode: clean-apply` truthful | CONFIRMED | `git -C fork show 41c45f378` vs the patch's hunk: identical `@@`, identical two added lines, identical index line `6b38d2421d..9aaa07ca39` | — |
| 1.3 | Q8 | patch Provenance cites record + fork SHA | CONFIRMED | header names `41c45f378e8f433b56c4da9b80edcdfd67fcebfb` and `records/41c45f378…json` | — |
| 1.4 | Q8 | no accidental extra edits | CONFIRMED | diff of the patch's hunk against the fork commit is empty | — |
| 1.5 | Q8 | Main_MiSTer citations `input.cpp:52-53`, `:4176-4177`, `:5102`, `:5349`, `:5496` | CONFIRMED | all five re-read at `Main_MiSTer` `6cda9cc5`; predicate, `make_unique` pair, NeGcon, Guncon and UNIQ sites all present at those lines | — |
| 1.6 | Q8 | "0048 was unused in all three series" | CONFIRMED | `linux-patches/` ended at `0047`; beta `series` ended at `0046`; de25 highest shared was `0042` | — |
| 1.7 | Q10 `a14b5e8e1` | record names `0049-…-skip-baudrate.patch` | CONFIRMED | file exists; matches | — |
| 1.8 | Q10 | `carried_mode: re-implemented` truthful | CORRECTED (nuance) | the added/removed **lines** are identical to `refs/pr/92`; only the `@@` anchors were regenerated against our eight-patch `hid-nintendo` stack, and the raw PR diff applies at `-F0` with offsets only. "re-implemented" overstates it | record notes now state exactly what was regenerated and that the lines are identical; the field is left at `re-implemented` since the shipped hunks were regenerated, not copied |
| 1.9 | Q10 | patch Provenance cites record, PR #92 head, and "UNMERGED" | CONFIRMED | header block quotes the full head SHA and `refs/pull/92/head`; PR #92 is not an ancestor of `c129b0fac` | — |
| 1.10 | Q10 | no semantic drift vs the PR | CONFIRMED | hunk-by-hunk compare against `git show refs/pr/92`: same helper, same reorder, same guard | — |
| 1.11 | Q10 | "MiSTer-devel … sometimes a modified hunk — see the Q6/Q8 precedents, where #88 and #91's merged commits differ from their PR heads" | **CORRECTED** | `git patch-id --stable` is IDENTICAL head↔merge for both: #88 `6a080ee6d7bb…`, #91 `347bc8291a32…`. The commits differ in SHA/author/message only; **no** hunk change has been observed | reworded in the `0049` header, the record notes, and `fork-sync.conf` to say what was measured |
| 1.12 | Q6 `9854075c8` | record names `0050-exfat-dir-readahead-plug.patch`, mode `clean-apply` | CONFIRMED | patch hunks identical to `git show 9854075c8` (both hunks, same added lines) | — |
| 1.13 | Q6 | `0050` header's patch-id claim for PR #88 | CONFIRMED | recomputed: both `97887b3413` and `9854075c8` are `6a080ee6d7bbbdfe57b54713fd5d17828fc49565` | — |
| 1.14 | Q6 | "fails at `-F0` on v7.2.3, 2 of 2 hunks" | CONFIRMED | `0050` is absent from the beta `series` and from de25; the 42-entry beta series replays clean without it (below) | — |
| 1.15 | Q5 `7c75b1b46` | record names `0017-xpad-mister-deltas.patch`, delta 5 present | CONFIRMED | `0017` hunk 2 adds the `skip_8bitdo_init` `module_param` block; the `xpad_start_input()` guard matches the fork's three added conditions verbatim | — |
| 1.16 | Q5 | delta 5 semantically equals fork `7c75b1b46`, no extra edits | CONFIRMED | the only content difference between the pre- and post-Wave-3 `0017` is delta 5's two insertions | — |
| 1.17 | Q5 | `carried_mode: re-implemented` truthful | CONFIRMED | `0017` is a curated multi-delta patch regenerated pristine→patched at 6.18.49; `@@` headers all shifted | — |
| 1.18 | Q5 | record notes say "NOT YET AUTHORED … does not itself modify 0017" | **CORRECTED** | the patch *was* authored in Wave 3; the Wave-1 notes were never updated when `carried_mode` flipped from `planned` | notes opening rewritten to state it was authored 2026-09-11 |
| 1.19 | Q3 `ea2212221` | record names `0001-fbdev-add-MiSTer_fb-driver.patch`, mode `re-implemented` | CONFIRMED | ours is a whole-driver patch, not a carry of the fork's 5-line diff | — |
| 1.20 | Q3 | `0001` now uses `__FB_DEFAULT_SYSMEM_OPS_RDWR` + `select FB_SYSMEM_FOPS`, mmap unchanged | CONFIRMED | shared patch lines 184 / 372; the fork's `ea2212221` sets `.fb_read = fb_sys_read`, `.fb_write = fb_sys_write`, `.fb_mmap = fb_io_mmap` and selects both symbols — same choice | — |
| 1.21 | Q3 | the beta copy is in lockstep | CONFIRMED | diff of the two patches' `+`/`-` lines shows exactly one difference, the documented `<linux/fbcon.h>` → `"core/fbcon.h"` include delta | — |
| 1.22 | Q3 | `0001` diffstat (Kconfig 12, Makefile 1, `MiSTer_fb.c` 430; 443 insertions) | CONFIRMED | recounted from the hunks: 12 + 1 + 430 = 443, and each `@@` count matches its body exactly | — |
| 1.23 | Q3 | record's `recommendation` says "advisory only — no patch file was edited" | **CORRECTED** | D4 was taken and both `0001` copies were edited | `recommendation` now records that it was actioned |
| 1.24 | Q3 | Main_MiSTer never `read`/`write`/`mmap`s `/dev/fb0` | CONFIRMED | the only `/dev/fb0` reference in `Main_MiSTer` is `video.cpp:3773`, opened solely for `ioctl(FBIO_WAITFORVSYNC)` | — |
| 1.25 | Q4 partial | `0004`'s OCRAM node vs fork `60e0d56bdd` | **CORRECTED** | every property is byte-identical (`#address-cells`/`#size-cells`/`ranges`, `flags-sram@f000 { reg = <0xf000 0x1000>; }`), but we add a 10-line comment the fork **deliberately** omits ("No source comments are added" — `60e0d56bdd`'s own message). The header claimed "node text matches the fork's" / "carried verbatim" | `0004`'s header now says properties are verbatim and names the added comment as ours |
| 1.26 | Q4 partial | `0004`'s new diffstat (202 insertions, 7 deletions) | CONFIRMED | recounted from the hunks — and it also **fixes** the previous file's wrong `213/14` | — |
| 1.27 | Q4 partial | "the `terasic,de10-nano` compatible is not carried; vanilla already has it" | CONFIRMED | `socfpga_cyclone5_de10nano.dts:15` at 6.18.49 carries the exact three-string `compatible` | — |
| 1.28 | Q4 partial | `socfpga.dtsi:785-788` `ocram: sram@ffff0000`; Main_MiSTer flags in DDR at `0x1FFFF000` | CONFIRMED | dtsi lines exact; `fpga_io.cpp:397`, `:595`, `user_io.cpp:1336`, `:1370` all `shmem_map(0x1FFFF000, 0x1000)`; `SOCFPGA_OCRAM_ADDRESS` is defined at `fpga_base_addr_ac5.h:44` and referenced nowhere else in the tree | — |
| 1.29 | all | the 6.18 series still applies | CONFIRMED | `patch -p1 -F0` replay of all 40 patches into a pristine 6.18.49 extract: **40/40, zero fuzz, zero rejects** (re-run after every header edit in this audit) | — |
| 1.30 | all | the beta series still applies at 7.2.3 | CONFIRMED | `patch -p1 -F0` replay of the 42 `series` entries into a pristine v7.2.3 extract: **42/42, zero fuzz, zero rejects** | — |
| 1.31 | all | patch lint | CONFIRMED | `scripts/lint-kernel-patches.sh` → PASS, 41 patches across 2 series | — |

## 2. `dropped-*` / `not-evaluated` records vs. the evidence standard

| # | Item | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|---|
| 2.1 | Q1 `aec7dc3aa` | `dropped-deliberate`, duplicate of `5fcfae369`, `CONFIG_TUN=y` already ours | CONFIRMED | record quotes the resolved config line and names the duplicate record; `linux.config` carries `CONFIG_TUN=y` | — |
| 2.2 | Q2 `33a0521fd` | `dropped-deliberate`, `CONFIG_RTW88_8821AU=m` since v10 | CONFIRMED | quoted in the record with a `linux.config` line reference; Wave-2 `w2-covered.md` re-derived it | — |
| 2.3 | Q7 `e6f377e7d` | `dropped-deliberate`, wholly derived from Q2/Q3/Q4 | CONFIRMED | the three defconfig lines are the `select`-implied consequences; record names the superseding records | — |
| 2.4 | Q4 `59bcae8eb` | notes reflect owner decision D1=A and point at the memo | PARTLY — **CORRECTED** | the notes *do* carry an "OWNER DECISION D1=A (2026-09-11), RECORD CLOSED" paragraph and name `memo-Q4-cpufreq.md`, but they still **opened** with "DISPOSITION IS DELIBERATELY 'needs-verification'", contradicting the record's own `disposition: dropped-deliberate` | opening rewritten to state the closed disposition and that the body is the unchanged Wave-1/2 analysis |
| 2.5 | Q4 | the DTS half is tracked as a partial carry rather than by flipping `carried_patch` | CONFIRMED | `dependencies.superseded_by` carries an explicit "partial carry: DTS flags-sram node → `0004`" entry plus the two origin records for `0003` | — |
| 2.6 | Q9 `c129b0fac` | notes reflect D2=defer and point at the memo | PARTLY — **CORRECTED** | the closing paragraph does exactly that, but the notes **opened** with "Disposition is needs-verification, NOT not-evaluated" — a direct self-contradiction with `disposition: not-evaluated` | opening rewritten |
| 2.7 | Q9 | evidence standard: real SHAs, quoted lines | CONFIRMED | 46 USB IDs checked one by one with file:line citations, `rwnx_version_gen.h` snapshot stamp quoted, mainline absence quoted at three trees, ARM compile + modpost result stated | — |
| 2.8 | Q9 | "stock's `firmware.tar.gz` ships zero of the ~60 blobs" | CONFIRMED | `tar tzf firmware.tar.gz` at `d4e3f51`: 89 files, none matching `fmacfw_*`/`fw_patch_*`/`fw_adid_*` | — |
| 2.9 | Q4/Q9 | "fork issue #84 / PR #85 / PR #92 discussion unreadable" | UNVERIFIABLE (as stated) | GitHub API/HTML is blocked from this session too; the records already say a human must paste the threads. Not a defect — the limitation is declared where it bites | — |

## 3. The ledger

| # | Item | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|---|
| 3.1 | `commits.jsonl` | ten new rows match the fork | CONFIRMED | every row's `author`, `author_email`, `date`, `subject`, `added`, `removed` recomputed from `git show --numstat` in the fork — **10/10 exact**, including `c129b0fac`'s 82,330/0 over 142 files | — |
| 3.2 | `commits.jsonl` | `_meta.increments[2]` from `6332499e7` to `c129b0fac`, 10 `added_shas` | CONFIRMED | `git rev-list --count 6332499e7..c129b0fac` = **9**, plus the PR head = 10 | — |
| 3.3 | `commits.jsonl` | `vanilla_target` honest at 6.18.49 | CONFIRMED | `"6.18.49 (release commit; v6.18.50 tag unreachable when this increment ran)"`, `vanilla_commit` `1c732c6b94f0…` — matches `env.md` and was not silently advanced | — |
| 3.4 | `fork-sync.conf` | pointer advanced to `c129b0fac` with a per-item disposition table | CONFIRMED | all ten Q rows present and each matches its record's `disposition` | — |
| 3.5 | `fork-sync.conf` | PR #92 carried ahead of merge, with re-key procedure | CONFIRMED | stated in the `PR#92` row, in the record, and in the patch header, consistently | — |
| 3.6 | `fork-sync.conf` | grounding caveat | CONFIRMED | states 6.18.49 not v6.18.50, names `env.md`, names CI's `-F0` as the loud backstop | — |
| 3.7 | `fork-sync.conf` | "the queue past the pointer below (8 commits + open PR #92) is planned, **not yet dispositioned**" | **CORRECTED** | the queue is 9 commits (measured), and it is dispositioned — the pointer was advanced in the same commit | paragraph rewritten |
| 3.8 | `carried_patches` | `b00a72159` → `0038`+`0039` | CONFIRMED | §11 attributes both to `b00a72159`; both patch headers name it as Origin | — |
| 3.9 | `carried_patches` | `60821059c` → `0035`+`0041` | CONFIRMED against §11 | §11: "`0041` … (same origin commit as `0035`)". Note `0041`'s own header names "stock `hid-nintendo.c`" rather than that commit's diff | — |
| 3.10 | `carried_patches` | `45283785a` → `0032`+`0040` | CONFIRMED against §11 | §11 attributes `0040` to `a6b7e3666`; `a6b7e36668f60fee…` exists on `MiSTer-v6.18` and its own message says "Original commit `45283785a7ace…` on branch MiSTer-v5.15", so the record now carrying it is the right one, and Wave 3 added that `duplicate_of` link | — |
| 3.11 | `carried_patches` | `f84543926` → `0033`+`0042` | CONFIRMED against §11 | §11 attributes `0042` to `f123647ef`; `f123647ef78978…` exists on `MiSTer-v6.18` with the same subject as `f84543926`, and the record now declares it in `duplicate_of` | — |
| 3.12 | `carried_patches` | the mechanism's description ("patches split out of one origin commit's diff") | **CORRECTED** (doc only) | literally true only for `b00a72159`. `a6b7e3666`'s diff contains the combo-LED + `hid_dbg_ratelimited` change and **not** the `" IMU"` suffix (`0040`); `f123647ef`'s diff replaces the player-LED IDA machinery and **does not** create the `:red`/`:green`/`:blue` lightbar names (`0042`); `60821059c` only comments out two `return ret;`. Those three patches restore a *stock ABI string*, attributed per §11 to the nearest fork commit | precision note added to `fork-sync-2026-09.md` §5. `reduce.py`'s comment is code and was left alone |
| 3.13 | ledger outputs | regenerate cleanly | CONFIRMED | `python3 docs/kernel-recon/reduce.py` → **136 records, problems: 0**; re-run after every edit in this audit | outputs regenerated |

## 4. Wave-3 documentation claims, spot-checked against the evidence

| # | Doc | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|---|
| 4.1 | README comparison table | Buildroot 2021.02.4 / glibc 2.31 / OpenSSL 1.1.1k / OpenSSH 8.6p1 / Samba 4.14.6 / Python 3.9.6 unchanged by 20260907 | CONFIRMED | `docs/stock-inventory/20260907/` regenerated from the release's own `rootfs.tar.bz2` + overlay; every version matches the 20250402 set | — |
| 4.2 | README | "507 true-ABI shared libraries", unchanged | CONFIRMED | both `shared-libraries.md` files report **507** | — |
| 4.3 | README | `rootfs.tar.bz2` 82,617,954 → 82,661,550 bytes | CONFIRMED | blob sizes at LIC `13c512d` and `d4e3f51` | — |
| 4.4 | README | installed tree 267.2 MiB → 294.4 MiB apparent | CONFIRMED | `disk-usage.md`: 280,215,940 B / 10,830 files → 308,723,439 B / 10,896 files | — |
| 4.5 | README | "89 modules, up from 52" | CONFIRMED | `evidence/stock-20260907-modules.txt` has 89 `.ko.xz`; 52 is the 20250402 figure | — |
| 4.6 | README | "firmware set (91 files, up from 66)" | CONFIRMED | 89 in `firmware.tar.gz` + `regulatory.db`/`.p7s` from `rootfs.tar.bz2` = 91 installed regular files, matching `20260907/firmware.md`; 66 is the 20250402 installed count | — |
| 4.7 | `docs/firmware-parity.md` | "`evidence/stock-20260907-firmware.txt` (91 files)" | **CORRECTED** | that file has **89** lines; 91 is the *installed* count from a different method | header now states 89, explains where 91 comes from, and the "re-checked against the 91-file list" line now says 89-path |
| 4.8 | README hardware table | `rtw88_8821au.ko` absent from stock 20260907 | CONFIRMED | not in the module list — while `rtw88/rtw8821a_fw.bin` *is* in the firmware list | — |
| 4.9 | README hardware table | `rtw88_8812au/8814au/8821c/8821cu/8822bu/8822cu/8723du` all present | CONFIRMED | all seven in `stock-20260907-modules.txt` | — |
| 4.10 | README hardware table | "newly covers RTL8814AU, RTL8822CU, RTL8723DU" | **CORRECTED** | modules ship, firmware does not: `rtw88/rtw8814a_fw.bin`, `rtw8822c_fw.bin`, `rtw8723d_fw.bin` are all absent from stock's set, though each driver declares them (`rtw8814a.c:2183/2266`, `rtw8822c.c:5440`, `rtw8723d.c:2203`). Same failure shape README itself flags for `mt7663u` | row now says "builds" and names the three missing blobs |
| 4.11 | README hardware table | "still no driver for RTL8710BU or RTL8188FU" | **CORRECTED** | false. 6.18's `rtl8xxxu` links `8188f.o` and `8710b.o` unconditionally (`rtl8xxxu/Makefile`) and binds them **outside** the `RTL8XXXU_UNTESTED` guard (`core.c:8060-8062`, `:8108-8112`); `rtl8xxxu.ko` is in stock's module list and `rtlwifi/rtl8188fufw.bin` + `rtl8710bufw_{SMIC,UMC}.bin` are in its firmware list | row rewritten with the file:line and firmware evidence |
| 4.12 | README hardware table | `rtw89_8851b(u)`/`8852b(u)`/`8852b_common` present, with `rtw89/rtw8851b_fw.bin` and `rtw8852b_fw.bin` | CONFIRMED | all in the module and firmware lists | — |
| 4.13 | README hardware table | no `brcmfmac`/`brcmutil`, no `rsi`/`rsi_usb`, no `ath9k_htc`; `ath6kl_core`/`ath6kl_usb`/`carl9170`/`rtl8192du` present | CONFIRMED | grepped one by one against `stock-20260907-modules.txt` | — |
| 4.14 | README hardware table | `mt7663u` ships with no `mt7663*` firmware; `mt7921u`/`mt7925u` ship **with** their `WIFI_*` blobs | CONFIRMED | `mt7663` has zero matches in the firmware list; all four MT7961/MT7925 `WIFI_*` blobs are present | — |
| 4.15 | README hardware table | new `brcm/BCM20702A1-0b05-17cb.hcd`; still no `ath3k-1.fw`/`ar3k/*.dfu`; no `BT_`-prefixed MediaTek blob | CONFIRMED | all four greps against the firmware list | — |
| 4.16 | README | stock now ships `ath10k_core`/`ath10k_usb` + `ath10k/QCA9377/hw1.0/{board-2.bin,firmware-6.bin}` | CONFIRMED | present in both lists | — |
| 4.17 | `docs/stock-reconciliation.md` §0 | source-of-truth table (LIC commits, sha256s, 89 firmware files, 89 `.ko.xz`, `addon.tar` 2,611,200 B) | CONFIRMED | `tar tzf`/`ls -l` on the `d4e3f51` artifacts | — |
| 4.18 | `docs/stock-reconciliation.md` §0.1 | `rtl8710bufw_{SMIC,UMC}.bin` "no consumer — no driver in this image binds RTL8710B at all" | **CORRECTED** | we build `CONFIG_RTL8XXXU=m`, which links `8710b.o` and binds `0bda:b711`/`0bda:2005`. We ship the driver without its firmware | row re-graded "untriaged — genuine gap candidate" with the evidence; the neighbouring `rtl8192fufw.bin` row got the same caveat |
| 4.19 | `docs/stock-reconciliation.md` §0.3 | `addon.tar` changed: new `S39usb-coldplug`, changed `uartmode` | CONFIRMED | same 2,611,200-byte size, different sha256, and the two named files | surfaced into `fork-sync-2026-09.md` §6.3, which had left it hanging as "if that task reports …" |
| 4.20 | `docs/kernel-config-deltas.md` §11 | "1,229 symbols `=y`/`=m` in stock, 1,289 in ours; 27 stock-only, 87 ours-only" | CONFIRMED | reproduced end to end: `cp linux.config → O/.config; make -C linux O= ARCH=arm LLVM=1 olddefconfig`, then `comm` — **1229 / 1289 / 27 / 87 exactly**, and the 27-symbol list matches the doc's four classes (9+11+1+6) name for name | — |
| 4.21 | `docs/kernel-config-deltas.md` §11 | ours-only class counts sum to 87 | CONFIRMED | 19+21+5+2+19+13+8 = 87 | — |
| 4.22 | `docs/kernel-config-deltas.md` §11 | `JOYSTICK_XONE` absent from vanilla Kconfig | CONFIRMED | `grep -rn 'config JOYSTICK_XONE'` over 6.18.49 → no match | — |
| 4.23 | `docs/patch-provenance.md` §11 + `abi-contract.md` cpufreq row + `docs/user/faq.md` | the `boost` file exists and `scaling_max_freq` alone clamps to 800000 | CONFIRMED | `0003` sets `.set_boost = cpufreq_boost_set_sw` (`:502`), `.boost_enabled = false` (`:503`), flags 1000/1200 `CPUFREQ_BOOST_FREQ` (`:297-298`); 6.18.49 `cpufreq.c:2845-2847` gates the file purely on `->set_boost`, `:2943-2944` creates it, `:1107-1108` the per-policy one, `freq_table.c:41-43` skips boost rows when off. The old text was right only for the pre-PR#24 driver | — |
| 4.24 | `docs/patch-provenance.md` §11 | the fork's driver has the identical boost contract | CONFIRMED | `59bcae8eb:drivers/cpufreq/socfpga-cpufreq.c` — same `CPUFREQ_BOOST_FREQ` rows, same `.set_boost`/`.boost_enabled = false` | — |
| 4.25 | `docs/patch-provenance.md` §11 | the `freq_table.c` "leave it as is" quote is still present in 6.18 | CONFIRMED | `freq_table.c:54-59` verbatim | — |
| 4.26 | `docs/kernel-export.md` §1.2 row 1 | `v6.18.38` = `d9ac12a691`, parent `aba1ef4c1` = `v5.15.1` | CONFIRMED | `git log -1 --format='%H %P %s'` on both | — |
| 4.27 | `docs/kernel-export.md` §1.2 row 2 | "53 of 62 commits are his" | **CORRECTED** | measured at the stated baseline `c129b0fac`: **67** commits since `d9ac12a691`, 53 by Sorgelig. No point on the branch gives 62 | row now reads 53 of 67 and lists the other contributors by count |
| 4.28 | `docs/kernel-export.md` §1.2 row 3 | his own `socfpga_cyclone5_de10_nano.dts` exists; the 20260907 DTB's `compatible` is the pre-#85 pair | CONFIRMED | both DTS files present at `c129b0fac`; `20260907/stock.dts:8` = `"altr,socfpga-cyclone5\0altr,socfpga"` | — |
| 4.29 | `docs/kernel-export.md` §1.2 row 4 | `lib/modules/6.18.38-MiSTer/` with `CONFIG_LOCALVERSION=""` | CONFIRMED | `tar tzf modules.tar.gz \| head` and `stock-20260907-linux.config:32` | — |
| 4.30 | `docs/kernel-export.md` §1.2 row 6 | fork vendors `drivers/hid/xone` and, since 2026-09-11, `drivers/net/wireless/aic8800` | CONFIRMED | `git ls-tree c129b0fac` | — |
| 4.31 | `docs/kernel-export.md` §1.2 row 8 | `create_img.sh` untars `modules.tar.gz` with `--strip-components=2` into `/lib` | CONFIRMED | `create_img.sh:30`, `:34`, `:41` | — |
| 4.32 | `docs/kernel-export.md` | `check-export-tree.sh` dry-run "PASS, 19 checks, 88,335 files identical" | UNVERIFIABLE | the script builds a kernel and needs the 6.18.50 tarball; not re-run in this audit. Reported as unverified, not assumed | — |
| 4.33 | write-up §4 | stock 20260907 has **no cpufreq driver at all** | CONFIRMED | `stock-20260907-linux.config` has `CPU_FREQ=y` + governors but no `ARM_SOCFPGA_CPUFREQ`, no `CPUFREQ_DT` (`:503` explicitly not set); ours has `ARM_SOCFPGA_CPUFREQ=y` | — |
| 4.34 | write-up §4 | stock 20260907 `mmap(/dev/fb0)` is broken | CONFIRMED | `CONFIG_FB_MISTER=y` with **neither** `FB_IOMEM_FOPS` nor `FB_SYSMEM_FOPS` anywhere in the shipped config | — |

## 5. Series-count consistency

| # | Where | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|---|
| 5.1 | measured | `linux-patches/` file count | — | **40** `.patch` files | baseline for everything below |
| 5.2 | `linux-patches-beta/series` header | "38 of the 40 shared + 4 beta-local — 42 entries" | CONFIRMED | 42 non-comment lines; replayed 42/42 at `-F0` on v7.2.3 | — |
| 5.3 | `linux-patches-beta/series` header | "five … are REAL FILES re-anchored for 7.x … **these four** needed …" | **CORRECTED** | five real shared-patch files (`0001`, `0015`, `0030`, `0031`, `0037`) — the "four" predates `0031` rejoining on 2026-09-06 | now "these five", with the names |
| 5.4 | `linux-patches-beta/series` header | "`make rt` is green on the whole 40" | **CORRECTED** | true of 2026-08-17's 40-entry list; the list is 42 now and `make rt` has not been re-run on it | reworded to say what was measured when |
| 5.5 | `README.md:90` | "**37 patch files**" | **CORRECTED** | 40 | → 40 |
| 5.6 | `README.md:157` | "all 37 patches apply cleanly" | **CORRECTED** | 40, re-measured 40/40 at `-F0` this audit | → 40, with the measurement |
| 5.7 | `README.md` delta paragraph | "126 reconciled commits (… 1 on `MiSTer-v6.18` …) down to **36 carried patch files**"; "A 37th file, `0047`"; "the eight commits and one open PR … are queued" | **CORRECTED** | `reduce.py` reports 136 records (110 + 10 + 1 PR head + 15 residue); 40 files; the queue is 9 commits + 1 PR and is executed, not queued | paragraph rewritten, naming `0048`/`0049`/`0050` and pointing at the executed write-up |
| 5.8 | `docs/buildroot-config.md` | "drops exactly ONE shared patch … all 40 entries (the other 36 shared + four beta-local)" | **CORRECTED** | two omissions (`0047`, `0050`); 42 entries, 38 shared | paragraph rewritten with the 42/42 measurement |
| 5.9 | `docs/rt-beta-kernel.md` §1/§2/§5 | 42 entries, 38 of 40, five real beta copies | CONFIRMED | already correct — this doc was updated properly in Wave 3 | — |
| 5.10 | `de25nano/linux-patches/README.md` | "**Three** — `0015`, `0030`, `0037` — have a 7.x-re-anchored copy … `0001` is the fourth divergent pair" | **CORRECTED** | four (`0031` links to the beta copy too, as this README's own row 25 says); `0001` is the fifth | intro rewritten; the hard-fail sentence now separates `0031`'s different (runtime-Oops) reason |
| 5.11 | `de25nano/…/README.md` | counts: 40 audit rows, 32 included, 8 excluded, 2 DE25-local, 36 total | CONFIRMED | directory holds exactly 36 patches (32 shared symlinks + `0048` + `0049` + `0101` + `0102`) | — |
| 5.12 | `de25nano/…/README.md` | "This board is on 7.2.2" (in the `0047` row) | **CORRECTED** | the README's own header pins 7.2.3 | annotated "7.2.3 (7.2.2 when this row was written)" |
| 5.13 | `PLAN.md` §1 inventory ("37 files … 36 shared") | — | CONFIRMED as history | PLAN §1 is explicitly the 2026-09-10 pre-increment measurement and its status line already says Waves 0–3 executed. Left as the as-planned snapshot | — |

## 6. Write-up (`docs/kernel-recon/fork-sync-2026-09.md`)

| # | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|
| 6.1 | Findings table comes first, before the increment narrative | CONFIRMED | table is at the top, before §1 | — |
| 6.2 | "the fork took **eight** commits and one still-open PR … those **nine** items" | **CORRECTED** | `git rev-list --count 6332499e7..c129b0fac` = 9; with the PR head, ten items — and the document's own §1 table lists ten | → nine commits, ten items |
| 6.3 | "Outcome: **four** items carried …, **four** dropped as already covered …" | **CORRECTED** | five carried (Q3, Q5, Q6, Q8, Q10) and three dropped-as-covered (Q1, Q2, Q7) per the records; Q4 is the declined one, Q9 the deferred one | recounted, with the Q-numbers named |
| 6.4 | Finding 6: "A **70k-line** vendored Wi-Fi/BT driver" | **CORRECTED** | 82,330 insertions over 142 files — as the same document's outcome line and §2 already say | → 82k, with the file/line counts |
| 6.5 | §5: "Zero orphans remain (verified … **without running `reduce.py`'s full regeneration**, per this session's remit)" | **CORRECTED** | Wave 3 *did* run it — `reconciliation.{md,jsonl}`, `device-support.md`, `silent-regressions.md` and `disagreements-with-provenance.md` are all regenerated in `b502662` | replaced with the actual `136 records, problems: 0` result |
| 6.6 | §6.3: rootfs re-inventory "is the concurrent task's responsibility … if that task reports it incomplete when it lands" | **CORRECTED** | it landed in the same commit, and it produced a real finding (`addon.tar` changed) that §6 did not carry | update paragraph added naming `S39usb-coldplug` and `uartmode` |
| 6.7 | Every per-item outcome in §2 matches its record's `disposition`/`carried_patch` | CONFIRMED | checked Q1–Q10 one by one against `records/` | — |
| 6.8 | §6.4's grounding restatement matches `env.md` and `commits.jsonl` | CONFIRMED | same SHAs, same caveat, same re-check command | — |
| 6.9 | "§ Audit (Wave 4)" section present | ADDED | — | appended, listing every correction and every unverifiable claim |

## 7. Unverifiable

1. **`check-export-tree.sh`'s dry-run result** ("PASS, 19 checks, 88,335 files identical, both
   DTBs identical, two exports with identical inputs give identical SHAs", `f7b59f5`). Re-running
   it needs a full kernel build and the 6.18.50 tarball, neither available here. Not contradicted
   by anything found — simply not re-measured.
2. **Anything behind GitHub PR/issue discussion** — fork issue #84's body, PR #85's review thread,
   PR #75's review thread, PR #92's comments. The API and web UI are blocked from this session
   exactly as they were from Waves 0–3. Every place that depends on them already says so and names
   what a human must paste; that is the correct handling, and the audit adds no confidence to it.

## 8. One uncommitted Wave-3 artifact, and its finding

`docs/kernel-recon/fork-sync-2026-09/tree-diff-2026-09.md` (337 lines) is **untracked** in the
working tree — it is the export/tree-diff backstop PLAN.md §5.2 puts at the tail of Wave 3, and it
was never added to `b502662`. It should be committed with the rest of the increment; it is the
same backstop that found the silent NSO-Genesis regression in July, and its result belongs in the
record.

Its own headline is re-verified here and holds: of 55 distinct files differing between our patched
6.18.38 tree and `MiSTer-v6.18` @ `c129b0fac` (excluding AIC8800, xone, configs, Documentation and
the fork's standalone DTS), everything behavioural is already dispositioned **except** its finding
F1, which this audit re-derived independently and confirms:

| # | Item | Claim | Verdict | Evidence | Fix applied |
|---|---|---|---|---|---|
| 8.1 | tree-diff F1 | the fork's `MiSTer_fb.c` `probe()` checks `memremap()` with `IS_ERR()`/`PTR_ERR()` and logs a function it does not call | CONFIRMED | `c129b0fac:drivers/video/fbdev/MiSTer_fb.c:261-265` reads exactly that; `memremap()` is declared `void *memremap(...)` at `include/linux/io.h:158` and returns `NULL` on failure, so `IS_ERR(NULL)` is false and `PTR_ERR(NULL)` is 0 — a failed mapping would be reported as a successful probe with `fb_base == NULL` | — |
| 8.2 | tree-diff F1 | "not a delta in what we ship — our code is correct" | CONFIRMED | `0001`'s header item 7 ("Two error-path fixes") already documents both halves of the fix, and the shipped patch tests `if (!fbdev->fb_base) … return -ENOMEM;` | — |
| 8.3 | record `ea2212221…` | its equivalence analysis covers the whole file | **CORRECTED** | it scopes to the five-line `fb_ops` hunk only, as tree-diff F1 says; the rest of `MiSTer_fb.c` was never compared against the fork's independently forward-ported copy | the scope-correction addendum tree-diff F1 recommends is now appended to the record's `notes`, with the file:line evidence |

## 9. Not re-audited

The §3 stable-drift verdicts (`stable-drift-verdicts-{A,B}.md`, 42 collision rows) were not
re-graded row by row. They were corroborated indirectly and strongly: the full 40-patch 6.18
series replays into a pristine 6.18.49 tree at `-F0` with zero fuzz and zero rejects, and the
42-entry beta series does the same on v7.2.3 — which is the failure mode a missed `superseded`
or `conflicting` verdict would produce. Wave 2's own `w2-drift.md` sampled 17 of them
independently and agreed with all 17.
