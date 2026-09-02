# DE25-Nano reference implementation — analysis of a working third-party board

**Status: COMPLETE, closed out 2026-08-22.** *(Was: SALVAGED PARTIAL, 2026-08-21.)*

This document was produced by a 9-agent ultracode run that was cut off by an account spend limit
after 4 of 9 agents completed. What survived was the raw output of four research legs, preserved
here rather than lost.

**The two gaps are now closed, by a separate run on 2026-08-22:**

1. **The missing Leg 4 (U-Boot deltas) has been done** — its findings are folded in as
   [§7](#7-leg-4-u-boot--filled-in-2026-08-22) below. The QSPI **posture** half of that leg's brief
   is **moot**: the owner has since settled the card layout (two partitions, p1 FAT, factory SPL
   untouched, no QSPI writes from Linux), so there is no posture-1-vs-posture-2 decision left to
   analyse. Leg 4's *technical* half — what we build, what the FIT must contain, and the one
   defconfig line that keeps a QSPI write structurally impossible — is what §7 records.
2. **The adversarial verification pass has run**, over the claims this document's successor leans
   on. [§8](#8-verification-record-2026-08-22) records exactly which claims were independently
   checked, which survived, and which failed. **The document as a whole has still not been refuted
   claim-by-claim** — §8 covers the load-bearing subset, not all of it. Anything not named in §8
   still carries the original single-agent standard, which is weaker than
   [`de25-boot-chain.md`](de25-boot-chain.md), [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) or
   [`de25-patch-portability.md`](de25-patch-portability.md).

**Never ran, and no longer will:** the synthesis pass and the neutrality audit that was to strip
smuggled recommendations. Where a leg's wording drifts toward advocacy, that is why. The synthesis
this document was to feed now lives in
[`de25-implementation-path.md`](de25-implementation-path.md), which supersedes it as the
decision-bearing document; this file remains the **record of what the reference repos contain**.

**Nothing here is adopted.** The owner's standing instruction governs: this is reference material,
and every divergence from our plan is his decision, not a recommendation. Where a leg's wording
drifts toward advocacy, that is an artifact of the missing neutrality pass.

**Sources.** Two read-only reference repos, supplied by the owner 2026-08-21:
`/mnt/source/de25-linux` (kernel; `881d4404a`, tag `v2026.07.27-v618-kernel-port-f9-fb-fix-5`)
and `/mnt/source/de25-uboot-socfpga` (U-Boot **2025.01**, branch `de25-mister-exfat-boot`,
tag `v2026.07.13-uboot-hf-launcher`). Neither was executed, modified, or checked out.
Comparison baseline is our `output/build/linux-6.18.44`.

**What he achieved, stated fairly:** a DE25-Nano booting Linux to the MiSTer MENU, with
`fpga_manager` and `fpga_region` probing on real hardware — further than any other work we know
of. His own `SETUP.md` §9 records that core switching is **not** wired up on his current card
layout, and the intended fast path is explicitly marked not end-to-end tested.

---

## 1. The two symptoms — why cores were limited and slow

The owner heard second-hand that only a certain number of cores could be loaded "into firmware"
and that loading was very slow, and suspected misconfiguration. Both are real, both are explained
by code in the reference repos, and **neither is a property of Agilex 5 SDM reconfiguration.**
Both come from the U-Boot/QSPI core-loading route — the route this project has already excluded.

### (a) "Only a certain number of cores into firmware"

"Firmware" was literal: **QSPI**. His first working core-switch tier put each core into the SDM's
configuration flash as an RSU application image and rebooted into it. Three independent caps
stacked up:

1. **The slot map exhausts the 16 MiB device.** Hard-coded in three places — MiSTer's binary
   carries the constants `0x00600000`, `0x00900000`, `0x00D00000` **[V]**; `de25_stage_core.sh:11-15`
   documents them as P1 = MENU 3 MB (never staged), P2 = 4 MB, P3 = 3 MB, merged 2026-07-07 into a
   single 7 MB staging slot "so >4 MB cores fit" **[V]**. P2 base `0x900000` + `0x700000` lands
   exactly on `0x1000000` = 16 MiB **[V arithmetic]**. So: **MENU plus two — later one — cores
   resident in firmware.** Every other core needed a full erase/write/verify.
2. **A ~2 MiB ceiling on the Linux live path.** Not folklore: mainline `stratix10-soc.c:19-20`
   allocates `NUM_SVC_BUFS 4 × SVC_BUF_SIZE SZ_512K` = exactly **2 MiB in flight**, and
   `s10_ops_write()` cannot proceed past that without `SVC_STATUS_BUFFER_DONE` callbacks recycling
   buffers **[V]**. His note attributes the stall to his own BL31 modification
   (`FPGA_CONFIG_BUFFER_SIZE=16`) killing the reply that drives recycling **[U — the ATF source is
   in neither repo]**. With 5 of his 8 cores under 2 MB and 3 over, "only some cores load" is
   literally what a user would have seen **[V]**.
3. **Only eight cores have ever been rebuilt for A5EB013** (`CORES.manifest`) — cores are
   device-specific and must be recompiled **[V]**.

> **This one matters for us.** Cap 2 is *mainline* code, and our own cores will be 1.92–3.65 MB —
> straddling that 2 MiB in-flight window. Buffer recycling working correctly is therefore a
> load-bearing assumption for any Linux-side core loading we build, and belongs in D2.5's
> measurement plan rather than being assumed.

### (b) "Very slow to load cores"

Every path he actually shipped is dominated by something that is not reconfiguration:

| Path | Dominant cost | Evidence |
|---|---|---|
| RSU / QSPI rewrite | `de25_fcs_stage_core.py` pushes the `.rpd` through the FCS→SDM mailbox in **4096-byte writes with a 0.05 s settle each**, re-asserting chip-select per write, then reads the slot back for an md5 verify in 4 KiB calls. For a 3.35 MB core that is **≥817 round-trips and ≥41 s of `sleep()` alone** before mailbox cost — then a reboot. His own script calls it "the ~minutes-long FCS rewrite". | `:65-70,95-107`; `de25_stage_core.sh:72` **[V]** |
| U-Boot launcher | No QSPI write, but a **warm reboot** — MiSTer's OSD string is `"Loading core... (board reboots ~30s)"`; his hook comments say ~35 s. On this SoC every reset is a full SDM configuration cycle with no warm/cold distinction. | **[V]** |
| Kernel `fpga_manager` + DT overlay (the intended fast path) | "~8 s total", "NES 3,325,952 B live-switches in ~3 s" | comment **[V]**, but see below |

**The fast path is the one he never proved.** Commit `881d4404a` (2026-08-01) records that the
script wrote to `/sys/kernel/config/device-tree/overlays/fullcore` — a configfs path that does not
exist in his mainline-based 6.18 tree — and states the replacement (the ~95-line misc driver over
`of_overlay_fdt_apply()`, `30d9c99a8`) **"has NOT yet been end-to-end tested"** **[V]**. MiSTer's
Tier A/B binaries still target the same dead configfs paths **[V strings]**.

### Verdict for our D0.2 conclusion

His experience **neither confirms nor undermines** our low-to-moderate-confidence finding that
core switching is UX-viable. He has never measured Agilex 5 reconfiguration on a working Linux
overlay path. What he measured is QSPI rewriting (minutes) and reboots (~30–35 s).

One genuinely intrinsic floor does appear, from two independent code paths: U-Boot's SDM driver
sleeps `udelay(1000000)` before its first `RECONFIG_STATUS` poll and then polls at 1 s intervals
**[V]**, mirroring the kernel service layer's `msleep(1000)` that our `de25-fpga-reconfig.md` §6.1
row 7 already flagged. **Expect a ~1 s quantization floor per full reconfiguration on this
silicon.**

---

## 2. What his work settles for us

Our five open unknowns, as answered by two independent legs. Where the legs differ in emphasis,
both readings are given — there was no synthesis pass to reconcile them.


### From LEG 1 — Device tree (de25-linux @ 881d4404a, tag v2026.07.27-v618-kernel-port-f9-fb-fix-5-g881d4404a) vs mainline linux-6.18.44

**[V] U1 — Do mainline's intel,agilex-svc / intel,agilex-soc-fpga-mgr compatibles bind on Agilex 5?**

No. Mainline 6.18.44's match tables contain only stratix10 and agilex (gen1) strings, and the Agilex 5 DTS declares intel,agilex5-svc / intel,agilex5-soc-fpga-mgr. Two one-line of_device_id additions fix it, and BOTH are required (svc is built-in and matches at __init, so the mgr cannot be created until svc binds). Separately, mainline 6.18.44's socfpga_agilex5.dtsi instantiates no svc/fpga-mgr/fpga-region node at all, so the DTS content must be supplied too. He reports fpga0/region0 binding on real hardware after the patch.

*Source:* `linux-6.18.44 drivers/firmware/stratix10-svc.c:1133-1137, drivers/fpga/stratix10-soc.c:448-452; /mnt/source/de25-linux commit d1878a320; /mnt/source/de25-linux/.../socfpga_agilex5.dtsi:213-243`

**[V] U2 — Is there a usable DT-overlay path for reconfiguration?**

Yes, but only via of_overlay_fdt_apply() from kernel code. The configfs device-tree path (/sys/kernel/config/device-tree/overlays/) does not exist upstream and never worked on his kernel — his switch script had been failing structurally on it for its whole history. Mainline fpga_manager sysfs is read-only (no writable firmware attribute), so he wrote a 95-line misc driver whose one write-only sysfs attribute re-applies a static .dtbo naming firmware-name=core.rbf under /fpga-region. The mechanism is HW-proven to reach the real reconfigure path; the one test attempt then failed at the SDM mailbox ('timeout waiting for RECONFIG_REQUEST') and wedged the board. This directly answers our fpga-reconfig §11 row 6 (carry OF_CONFIGFS vs write a board driver vs U-Boot-preload): OF_CONFIGFS is not an option, and he chose 'write a board driver'.

*Source:* `/mnt/source/de25-linux commits 30d9c99a8 and 881d4404a; drivers/misc/de25_fpga_trigger.c; analysis/full_config/de25_full_core.dtso`

**[U] U3 — Does the factory FSBL boot a mainline-built u-boot.itb?**

Not answered, and this leg found no evidence either way. He flashes his own exFAT-aware SPL in QSPI (posture 2), so the factory-FSBL path is never exercised in his tree. Nothing in the kernel repo bears on it. Treat as still open.

*Source:* `absence of evidence in /mnt/source/de25-linux (kernel repo only); his SETUP.md §3 boot chain`

**[U] U4 — Is bitstream authentication (VAB) enforced out of the box?**

Not settled by the DTS, but two adjacent facts: his dtsi instantiates the full Intel FCS subtree (fcs-hal 'intel,agilex5-soc-fcs-hal', fcs-crypto, fcs-config) and his overlay ships plain unsigned .rbf/.rpd payloads which the SDM accepts, with the only rejection documented being a wrong-recipe RSU magic (0xa9129446 vs the expected 0x95482962), not a signature failure. That is consistent with VAB not being enforced on this board, but it is inference, not a read of a fuse or a config bit.

*Source:* `/mnt/source/de25-linux/.../socfpga_agilex5.dtsi:232-253; board_overlay/usr/local/bin/de25_stage_core.sh:42-58`

**[V] U5 — Real reconfiguration latency**

His numbers, from source comments rather than a log I read: a 3,325,952-byte NES core live-switches in ~3 s of config time, ~8 s end-to-end including a mandatory 3 s pre-quiesce settle and a mandatory 5 s post-config settle; the reboot fallback path is ~35 s. Both settle delays are HW-forced, not padding: trimming the pre-quiesce to 1 s reproducibly wedged the board on the NEXT switch, and any LWH2F access inside the post-config window hangs a CPU on the AXI bus with no timeout (RCU stall, warm reset comes back dark). So ~8 s, of which ~5 s is unavoidable dead time, is the honest UX figure for his design.

*Source:* `/mnt/source/de25-linux/board_overlay/usr/local/bin/de25_live_switch_core.sh:7-12, 81-93, 123-132; de25_launch_core.sh:8-18`

**[V] Our fpga-reconfig §11 row 14 — Does the Agilex 5 svc node need iommus = <&smmu 10>?**

His does, and it also carries altr,smmu_enable_quirk on both the svc node and the fpga-mgr child. He supplies the smmu node himself (mainline 6.18.44 has none) and enables it from the board DTS. He did not test the no-iommus form, so 'needs' is not proven — but the working configuration is known.

*Source:* `/mnt/source/de25-linux/.../socfpga_agilex5.dtsi:213-226, 461-471; socfpga_agilex5_de25_nano.dts:182-184`

**[V] DP-10's residual question (is the display pipeline HPS-reachable?)**

Corroborated as no. His DTS has no display, DRM, HDMI or I2C-transmitter node whatsoever; Linux's only display device is MiSTer_fb writing a DRAM region the fabric scaler reads. He also enables exactly one HPS I2C bus with no children, which means the DE10's ADV7513-on-/dev/i2c-0..2 discovery contract cannot work on this board.

*Source:* `full read of /mnt/source/de25-linux/.../socfpga_agilex5_de25_nano.dts; /mnt/source/Buildroot_MiSTer/docs/de25-fpga-reconfig.md:696-727`


### From Leg 2 — Kernel Deltas

**[V] U1 — Do intel,agilex-svc/soc-fpga-mgr compatibles bind on Agilex 5?**

No — mainline's stratix10-svc.c/stratix10-soc.c need an added 'intel,agilex5-svc'/'intel,agilex5-soc-fpga-mgr' of_device_id entry each (his commit message: this gap exists in current mainline too). His DTS already declares those compatibles and a fpga-region node inherited unmodified from his kernel base — but our own linux-6.18.44 baseline lacks those same DTS nodes entirely, an unresolved discrepancy between two nominally-mainline-descended point releases.

*Source:* `de25-linux commit d1878a320; both repos' socfpga_agilex5.dtsi`

**[V] U2 — Is there a usable DT-overlay reconfig path?**

Yes, mechanism confirmed on real hardware: apply a DT overlay with a firmware-name property via of_overlay_fdt_apply(); of-fpga-region.c's own notifier drives the real reconfigure. The RPi-style OF-configfs path some earlier code assumed was never upstream and always failed. Reliability under real SDM mailbox timing is NOT yet demonstrated — one live test hit a 300ms RECONFIG_REQUEST timeout and wedged the board.

*Source:* `de25-linux commits 30d9c99a8, 881d4404a`

**[U] U3 — Does the factory FSBL boot a mainline-built u-boot.itb?**

Not established — he replaced the SPL with his own exFAT-aware build and there is no evidence in SETUP.md or the repo that the stock factory FSBL was ever tested against any other u-boot.itb.

*Source:* `/mnt/source/de25-linux/SETUP.md (absence of any such test)`

**[V] U4 — Is VAB (bitstream authentication) enforced out of the box?**

No — CONFIG_SPL_FIT_SIGNATURE=y is set (FIT image signing) but CONFIG_SOCFPGA_SECURE_VAB_AUTH is not set anywhere in the defconfig, board header, or board directory.

*Source:* `/mnt/source/de25-uboot-socfpga/configs/socfpga_agilex5_de25_nano_defconfig and related files (grep, both symbols)`

**[V] U5 — Real reconfiguration latency.**

No clean success-path number obtained. Working path (reboot) measured at ~35s. Fast path (live DT-overlay) targets ~8s but is unverified end-to-end; the one real hardware attempt at it hit the hardcoded 300ms SDM RECONFIG_REQUEST timeout and wedged the board on resume — empirical (if limited, n=1, unhardened-driver) evidence that the timeout-tightness risk our own D0.2 dossier already flagged on paper is real on Agilex 5 silicon.

*Source:* `de25-linux commit 30d9c99a8; board_overlay/usr/local/bin/de25_live_switch_core.sh, de25_launch_core.sh`


### From Leg 3 — the two symptoms ("only a certain number of cores into firmware", "very slow to load cores"), mechanism-level explanation from the reference repos

**[V] U1 — Do mainline's 'intel,agilex-svc' / 'intel,agilex-soc-fpga-mgr' compatibles bind on Agilex 5?**

Not as shipped, for two independent reasons, and he fixed both. (i) DT: mainline 6.18.44's socfpga_agilex5.dtsi instantiates no svc, fpga-mgr or fpga-region node at all — only the svcbuffer reserved-memory. He authored all three: a firmware/svc node with compatible 'intel,agilex5-svc' (method smc, memory-region svcbuffer, iommus <&smmu 10>, altr,smmu_enable_quirk, GIC_SPI 0), a child fpga-mgr 'intel,agilex5-soc-fpga-mgr', and a top-level fpga-region with fpga-mgr = <&fpga_mgr>. (ii) Drivers: neither stratix10-svc.c nor stratix10-soc.c matches an agilex5 string in 6.18.44 — his two-line patch adds one entry to each match table. His commit message records that both were required together: fixing only the fpga-mgr left the mailbox failing with "couldn't get service channel (fpga)", because the SVC node binds at __init before its children can be created. HW-confirmed on the board: /sys/class/fpga_manager/fpga0 and /sys/class/fpga_region/region0 exist and 'of-fpga-region fpga-region: FPGA Region probed' appears in dmesg — his words, 'the first time this has worked on this board'. Both match tables have no per-compatible .data, so the third entry is functionally free. NOTE: this is the fix an already-posted Altera series does upstream with 'intel,agilex-soc-fpga-mgr' as the declared DT fallback (our §3.1) — he did not use the fallback route, he added the strings.

*Source:* `/mnt/source/de25-linux commit d1878a320; arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi:213-244 (added in bf8e5c9c6); diff vs /mnt/source/Buildroot_MiSTer/output/build/linux-6.18.44/drivers/{firmware/stratix10-svc.c,fpga/stratix10-soc.c} and .../dts/intel/socfpga_agilex5.dtsi`

**[V] U2 — Is there a usable DT-overlay path for reconfiguration?**

Yes, and our §3.2 option table is now settled empirically rather than by inference. Option (a) is real and is what the vendor ships: Terasic's stock DE25 kernel config (6.12.11) has CONFIG_OF_CONFIGFS=y — so the /sys/kernel/config/device-tree/overlays/ workflow every Altera document describes works verbatim on the vendor kernel, and its provenance as a vendor carry is no longer [U]. Option (b) is real and now has a working reference implementation: his drivers/misc/de25_fpga_trigger.c, ~95 lines, request_firmware()s a static .dtbo and calls the mainline exported of_overlay_fdt_apply(); of-fpga-region's overlay notifier then calls fpga_region_program_fpga(). HW-tested to the point of 'fpga_manager fpga0: writing de25_live_switch_current.rbf to Stratix10 SOC FPGA Manager' in dmesg. Two caveats: his design re-applies a STATIC overlay naming a FIXED firmware path and stages the chosen core to that path first (avoiding rebuilding a DTB per switch), and his end-to-end integration is still untested. His confirmation that mainline fpga_manager class devices expose no writable 'firmware' attribute — only RO name/state/status — matches our §2.6 'there is no second door'.

*Source:* `/mnt/source/de25-linux/analysis/smc_bridge/board_kernel.config:2246; commits 30d9c99a8 and 881d4404a`

**[U] U3 — Does the factory FSBL boot a mainline-built u-boot.itb?**

NOT ANSWERED, and he is structurally unable to answer it: he replaced the SPL (his exFAT-aware SPL is inside his own .jic) precisely because the factory one cannot read exFAT. What his repo does settle is the baseline: the u-boot.itb he pulled off the board identifies as '2025.01-gd0f8813fd6bf' with vendor=terasic — Terasic shipped a build of this very tree at the 'add support for de25-nano' commit, confirming U-Boot 2025.01 + a board commit that is public. His own build carries the identical version string, so he never moved off 2025.01 either. Two facts sharpen our Q3: his defconfig sets CONFIG_SPL_FIT_SIGNATURE=y (as mainline's agilex5 defconfig does) yet he loads locally built, unsigned FITs — consistent with our finding that the factory SPL's control DTB requires no keys; and the SPL FIT load address contract is visible (CONFIG_SPL_LOAD_FIT_ADDRESS=0x82000000, CONFIG_SYS_SPI_U_BOOT_OFFS=0x04000000).

*Source:* `/mnt/source/de25-uboot-socfpga/configs/socfpga_agilex5_de25_nano_defconfig; strings of /mnt/source/de25-linux/analysis/uboot_board_orig_pulled.itb; SETUP.md §3`

**[V] U4 — Is bitstream authentication (VAB) enforced on this board out of the box?**

Strong practical evidence that it is NOT — but not from a stock board. He loads locally built, unsigned .uboot.rbf files into the fabric both from U-Boot ('fpga load' + 'FPGA reconfiguration OK!') and from Linux via the fpga_manager, across at least eight cores, with no signing step anywhere in the repos; grep for VAB/QKY/efuse/authentication over his scripts, docs and configs returns nothing relevant. His defconfig does not set CONFIG_SOCFPGA_SECURE_VAB_AUTH (upstream keeps that in a separate socfpga_agilex5_vab_defconfig). The caveat is real and unremovable: he flashed his own .jic over the factory QSPI, so this is evidence about HIS device state, not proof about a factory-fresh DE25. It does establish that the A5EB013 silicon in front of him is not efuse-locked, which is the half of the question that would have been fatal.

*Source:* `/mnt/source/de25-uboot-socfpga/configs/socfpga_agilex5_{de25_nano,vab}_defconfig; grep over /mnt/source/de25-linux; SETUP.md §3`

**[U] U5 — Real reconfiguration latency.**

STILL UNMEASURED on a working Linux overlay path, and this leg cannot close it. The only in-repo numbers are comment/commit prose from the 6.12.11-era configfs path — '~3 s config' for a 3,325,952 B NES core, '16-18 s' for an a2600<->NES round trip, '~8 s' claimed live-switch total — and the referenced backing artifacts (analysis/SUB10S_ATF_KERNEL_DIVERGENCE.md, the memory/*.md notes, com9_*_throttle_validate.log) are NOT in the shared repo, so none is verifiable here. What IS new and verifiable are three real inputs to our §6.2 arithmetic: (1) actual MiSTer-scale Agilex 5 bitstream sizes for the A5EB013 die — 1.92 MB (menu) to 3.65 MB — which lands at the top of our 1-4 MB guess; (2) a second, independent ~1 s poll quantization, in U-Boot's intel_sdm_mb.c, matching the kernel service layer's msleep(1000) (our §6.1 row 7); (3) hard evidence that reconfiguration cost is NOT the dominant term in a perceived switch — his own design spends >=3 s quiescing and 5 s settling around it, both for HW-proven safety reasons.

*Source:* `/mnt/source/de25-linux/board_overlay/media/fat/cores/CORES.manifest; de25_live_switch_core.sh:7-12,74-92,120-131; /mnt/source/de25-uboot-socfpga/drivers/fpga/intel_sdm_mb.c:20-21,1060-1070`


### From Leg 5 — platform gotchas, secure-boot, and the two symptoms (plus U1–U5 resolution)

**[V] U1 -- Do mainline's intel,agilex-svc / intel,agilex-soc-fpga-mgr compatibles bind on Agilex 5?**

No, not as-is on this kernel generation: neither string matched an agilex5-specific DTS compatible in his tree, and mainline 6.18.44 has no svc/fpga-mgr/fpga-region node in socfpga_agilex5.dtsi at all (confirms D0.2 §3.1's absence finding). His fix -- adding explicit intel,agilex5-svc / intel,agilex5-soc-fpga-mgr match-table entries -- is a small, zero-risk kernel patch, and is HW-confirmed to bind and probe. This independently corroborates Altera's own upstream A5-series patch, which adds the identical fpga-mgr string.

*Source:* `de25-linux commit d1878a320`

**[V] U2 -- Is there a usable DT-overlay path for reconfiguration?**

Yes, and it is the only usable path -- but the /sys/kernel/config/device-tree/overlays/ configfs workflow every vendor doc describes never existed in his kernel (confirmed against kernel.org: no CONFIG_OF_CONFIGFS subsystem upstream), matching D0.2 §3.2 exactly. He built a small (~90-line) misc-device driver calling the exported of_overlay_fdt_apply() directly, HW-confirmed to reach the real fpga_manager write path via of-fpga-region.c's own notifier.

*Source:* `de25-linux commits 30d9c99a8, 881d4404a`

**[U] U3 -- Does the factory FSBL boot a mainline-built u-boot.itb?**

Untested. He replaced Terasic's factory SPL with his own exFAT-aware SPL before the board was ever brought up in this repo's recorded history; no commit or doc anywhere in his tree exercises the unmodified factory FSBL against any FIT image, mainline-built or otherwise. This remains a genuinely open question for our posture-1 plan.

*Source:* `de25-uboot-socfpga commit history d0f8813fd6->096da9d4bb->38eff87fc0; absence confirmed by full log review`

**[V] U4 -- Is bitstream authentication (VAB) enforced on this board out of the box?**

No, on his specific unit: his defconfig never sets CONFIG_SOCFPGA_SECURE_VAB_AUTH (confirmed against the Kconfig, which shows that symbol lives only in separate *_vab_defconfig files), and his board repeatedly boots a self-built, unsigned .jic via JTAG all the way to a running MiSTer MENU -- the strongest practical evidence available that VAB is unprovisioned on this board class. This is single-unit evidence, not a guarantee about every DE25-Nano's eFuse state.

*Source:* `de25-uboot-socfpga configs/ + arch/arm/mach-socfpga/Kconfig:27; de25-linux SETUP.md §3 and full working-boot history`

**[V] U5 -- Real reconfiguration latency**

One real number now exists, single-source and self-reported: a 3.3MB core's SDM reconfiguration window is ~3s (post-BUF4-fix), and the full quiesce->overlay->settle->service-restart worker completes in ~8s regardless of core size, with a documented a2600<->NES round trip of 16-18s. This lands inside D0.2 §6.2's estimated range and is the first hardware corroboration of it, but it is not independently reproduced and the pre-fix pathology (an SDM/ATF buffer-reclaim bug, not a fundamental SoC limit) shows how easily a latency measurement can be dominated by a project-specific bug rather than the platform.

*Source:* `de25-linux board_overlay/usr/local/bin/de25_live_switch_core.sh header + commit 7fb52ac3f`


---

## 3. Platform gotchas we inherit regardless of design choices

These are properties of the SoC and the board, not of his design decisions, so our port meets them
whichever posture we choose.


### Mainline 6.18's Agilex 5 DTSI has no SD/MMC controller node and no SMMU node. A board DTS that references &mmc or &smmu is a dtc compile error; without an mmc node the board cannot boot from SD at all.

- **Evidence:** grep -i 'mmc|sd4hc|smmu|iommu' over /mnt/source/Buildroot_MiSTer/output/build/linux-6.18.44/arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi returns nothing; the same nodes appear as + hunks in his fork at :384 and :461
- **His fix:** Back-ported mmc0@10808000 ('intel,agilex5-sd4hc','cdns,sd4hc', iommus=<&smmu 5>, dma-coherent) and smmu: iommu@16000000 ('arm,smmu-v3') from Terasic's 6.12.11-LTS tree into the dtsi (bf8e5c9c6).
- **Applies to us:** Unavoidably. Any DE25 port we do needs these nodes from somewhere. The only open choice is which file they live in and whether we try to upstream them.

### Mainline 6.18's own gmac0 node for Agilex 5 does not work on real DE25 hardware — ethernet never probes.

- **Evidence:** /mnt/source/de25-linux commit e57c54c74: -EIO 'Cannot register the MDIO bus', preceded by 'Version ID not available' / 'No HW DMA feature register supported' on every boot
- **His fix:** Replaced the mainline node (compatible altr,socfpga-stmmac-agilex5, one macirq, reset-names stmmaceth/ahb) with Terasic's full node: altr,socfpga-stmmac-a10-s10 + 17 per-queue IRQ vectors, snps,multi-irq-en, snps,pblx8, altr,smtg-hub, iommus=<&smmu 1>, dma-coherent, and reset-names stmmaceth/stmmaceth-ocp. He identifies the concrete mechanism: dwmac-socfpga.c acquires the OCP reset exclusively by the name 'stmmaceth-ocp', which mainline's 'ahb' naming never satisfies.
- **Applies to us:** Yes, verbatim — this is a property of mainline's DTS vs this silicon, independent of any design choice of ours. It also means mainline's Agilex 5 ethernet support is untested on hardware and we should not trust other mainline Agilex 5 nodes by default.

### With the SMMU enabled, any DMA-capable peripheral missing an iommus stream ID faults on every transfer.

- **Evidence:** /mnt/source/de25-linux commit 36f39d30d: usb0 without iommus=<&smmu 6> produced AHB ERROR on every dwc2 channel; lsusb showed only root hubs
- **His fix:** Added iommus = <&smmu 6> to usb0. Stream IDs in use in his tree: gmac0=1, mmc0=5, usb0=6, svc=10.
- **Applies to us:** Yes, if we enable the SMMU. The failure mode is a device that enumerates nothing rather than a probe error, so it is easy to misdiagnose as a USB or PHY problem.

### mmc0 DMA through the SMMU F_TRANSLATION-faults on 6.18 but not on 6.12, with a byte-identical devicetree. ~~It is a kernel regression, not a DT gap.~~ — **the FAULT is confirmed; the "kernel regression" ATTRIBUTION is CORRECTED, 2026-08-22**

> **Correction (2026-08-22).** The **fault is real and well-evidenced** — commit `716559020`'s
> retract-of-a-retraction stands, verified [V]. What does **not** hold is calling it a *kernel-version
> regression*. The "working 6.12" baseline is **Terasic's vendor tree**, not mainline, and its
> `sdhci-cadence.c` gives `intel,agilex5-sd4hc` a dedicated match entry carrying
> **`SDHCI_QUIRK2_40_BIT_DMA_MASK`** (`terasic/linux-socfpga@de25-nano-6.12.11-lts:
> drivers/mmc/host/sdhci-cadence.c:783-786,952-953`) **[V, fetched 2026-08-22]**. That quirk **exists
> nowhere in mainline** — zero hits in `drivers/mmc/` and `include/` at 6.18.44, and zero in
> `sdhci.h` at v7.2 and `master` **[V]**. His 6.18 tree binds the bare `cdns,sd4hc` entry with a
> byte-identical-to-mainline driver **[V `diff -q`]**, so mainline's
> `sdhci_set_dma_mask()` takes the 64-bit branch (`DMA_BIT_MASK(64)`, `sdhci.c:4117-4123`) **[V]** on
> a controller the vendor deliberately caps at 40 bits. Under SMMU translation, top-down IOVA
> allocation above the controller's wired address bits truncates — exactly an `F_TRANSLATION`
> "input address caused fault". **The DT was byte-identical; the DRIVERS were not.** Mainline 6.12
> was never tested and could not have been (no Agilex 5 clk driver in mainline before v6.19).
>
> **Consequence for us, and it is the opposite of what this section originally implied:** the fault
> does **not** disappear on 6.19 or 7.2. It travels with mainline `sdhci-cadence` + SMMU on every
> version. It is therefore **not** an argument for a newer kernel, and it has a cheap
> mainline-first remedy to test: a one-entry upstream `sdhci-cadence` patch adding
> `intel,agilex5-sd4hc` with a 40-bit mask. See
> [`de25-implementation-path.md`](de25-implementation-path.md) §5.1 and §8 Q2.

- **Evidence:** /mnt/source/de25-linux commit 716559020: the earlier 'false alarm / warm-reboot artifact' conclusion is retracted; the 'clean' retest had sdhci.debug_quirks=0x60 silently inherited from a JTAG-recovery script, which forces PIO and never exercised the faulting path. A genuine power-cycle through the unmodified production boot script reproduced it decisively.
- **His fix:** sdhci.debug_quirks=0x60 baked into the production boot.scr.uimg — forces SDHCI into PIO instead of ADMA. Root cause deliberately not bisected.
- **Applies to us:** Yes, and on **every** mainline kernel version, not just 6.18 (see the correction box). The mitigation costs the entire SD DMA path. This is also a methodology warning we should adopt: do not test SMMU-adjacent behaviour on this board via a warm reboot, and audit your own test harness's default bootargs before declaring a fault gone. A third methodology lesson, added by the 2026-08-22 pass: **a "byte-identical devicetree" isolates nothing when the two kernels are a vendor tree and a mainline tree** — diff the drivers before attributing a fault to a version.

### Touching the LWH2F window too soon after config-complete hangs a CPU on the AXI bus with no bus timeout — RCU stall, and a warm reset from that state brings the board back DARK (power-cycle only).

- **Evidence:** /mnt/source/de25-linux/board_overlay/usr/local/bin/de25_live_switch_core.sh:123-132, described as 'HW-proven 2026-07-13, the hard way'
- **His fix:** Mandatory 5 s settle after config-complete before any fabric access, and a mandatory 3 s settle before starting a new reconfigure (trimming that to 1 s reproducibly wedged the next switch). Both are dead time in every core switch.
- **Applies to us:** Yes if we do live reconfiguration on this SoC. It sets a hard floor of several seconds on switch latency that no software optimisation removes, and it means any 'is the fabric up?' probe must be gated, not speculative.

### On an unconfigured fabric, a raw MMIO read of the fabric sysid is a FATAL async SError — a kernel panic, not a recoverable probe failure.

- **Evidence:** /mnt/source/de25-linux/board_overlay/usr/local/bin/de25_fabric_ready.py (HPS-First guard comment, 'HW-proven on the first Stage-1 HPS-First boot')
- **His fix:** A guard script that refuses the MMIO probe unless a U-Boot-supplied de25_core= breadcrumb names a configured core, or fpga0/state reads 'operating' after a kernel-driven config. Note his finding that fpga0/state reads 'unknown' for a U-Boot-configured fabric, so it cannot be used as a universal signal.
- **Applies to us:** Yes. Any Main_MiSTer aarch64 HAL that probes the fabric the way DE10's does will panic the kernel on an unconfigured board. This is a hard constraint on how L0's HAL discovers the fabric.

### The configfs device-tree overlay path does not exist in upstream Linux and never will as things stand.

- **Evidence:** /mnt/source/de25-linux commits 881d4404a and 30d9c99a8: 'confirmed against kernel.org: the RPi-style drivers/of/configfs.c subsystem this assumed was never upstream'; his defconfig even carries an inert CONFIG_OF_CONFIGFS=y line for a symbol that does not exist
- **His fix:** Wrote a misc driver that calls of_overlay_fdt_apply() from kernel context.
- **Applies to us:** Yes — it removes one of the three options our fpga-reconfig §11 row 6 was going to cost out. Also a caution: an inert CONFIG_ symbol in a defconfig produces no warning and no behaviour.

### With CONFIG_STRICT_DEVMEM=y, ordinary System RAM cannot be mmap'd via /dev/mem; only no-map reserved regions can.

- **Evidence:** /mnt/source/de25-linux commit 9454a984d; arch/arm64/configs/de25_defconfig:12312
- **His fix:** A no-map reserved-memory node over the AO486 0xB0000000 window. He notes the failure was silent and cost several investigation sessions — Main released the x86 CPU over a never-staged BIOS and the core triple-faulted.
- **Applies to us:** Yes, for any Main_MiSTer shared-memory window, if we keep STRICT_DEVMEM. Note our DE10 config sets '# CONFIG_STRICT_DEVMEM is not set' (board/mister MiSTer_defconfig), so this is a divergence we would inherit only if the DE25 config turns it on.

### ~~drivers/input/mousedev.c is missing #include <linux/compat.h>~~ — **REFUTED by the main session, 2026-08-21**

> **This claim is wrong and is retained only as a worked example of why this document's
> missing adversarial pass matters.** Checked directly: `output/build/linux-6.18.44/drivers/input/mousedev.c`
> has no `#include <linux/compat.h>` and needs none — there is **no `compat_ptr()` call**. The only
> occurrence of that token is inside a comment at `:891-893` explaining why translation is
> *unnecessary*: "EVIOCGRAB's argument is a truth value, not a pointer, so the compat entry point
> needs no `compat_ptr()` translation." Our own patch `0026-input-mousedev-eviocgrab.patch:461-464`
> adds exactly that construct, deliberately. The agent appears to have pattern-matched the word
> `compat_ptr` in prose. **There is no build error on arm64.**
>
> What *is* true and worth keeping: our patch's own note (`:85`) records that `CONFIG_COMPAT` is
> off on 32-bit ARM, so this `.compat_ioctl` path has **never been exercised** on the DE10. On
> aarch64 with `CONFIG_COMPAT=y` it becomes live for the first time. The patch author already
> reasoned about the safety (truth value, not pointer), so this is a review item, not a defect.

- **Evidence:** de25-linux commit 9a3e73919; CONFIG_COMPAT=y confirmed in his defconfig
- **His fix:** One-line #include <linux/compat.h> add.
- **Applies to us:** Any aarch64 DE25 defconfig of ours that sets CONFIG_COMPAT=y (likely, for any 32-bit compat needs) will hit the identical implicit-declaration build error and need the identical one-line fix — trivial but must not be missed.

### stratix10-svc.c / stratix10-soc.c of_device_id tables lack 'intel,agilex5-svc' / 'intel,agilex5-soc-fpga-mgr' entries — a genuine mainline gap for this SoC family, not board-specific.

- **Evidence:** de25-linux commit d1878a320, explicitly stated to reproduce on current mainline too
- **His fix:** Add one compatible-string line to each driver's match table (zero functional risk, no .data/branching on the tables).
- **Applies to us:** Any DE25 board work using mainline-flavored kernel sources needs this same two-line fix before /sys/class/fpga_manager or /sys/class/fpga_region will bind at all.

### There is no writable userspace attribute on fpga_manager class devices in current mainline, and the RPi-style OF-configfs overlay subsystem was never upstreamed — any design assuming a configfs-triggered reconfigure path will fail structurally, not intermittently.

- **Evidence:** de25-linux commits 30d9c99a8, 881d4404a, explicit statement 'confirmed against kernel.org'
- **His fix:** A custom misc-device kernel module applying a static prebuilt DT overlay via of_overlay_fdt_apply(), relying on of-fpga-region.c's own notifier.
- **Applies to us:** Any of our own reconfigure design must go through the DT-overlay + fpga-region-notifier path (or write our own trigger like his), not a configfs write.

### Agilex 5 Rev A silicon requires a runtime-detected, non-optional Intel-upstream FPGA-reconfig workaround (register-gated, not a defconfig symbol), dated 2023 and explicitly scoped to Rev A only.

- **Evidence:** de25-uboot-socfpga commit 2030244a1e, confirmed ancestor of his branch
- **His fix:** Already inherited automatically via mainline U-Boot; no action needed beyond using a U-Boot new enough to carry it.
- **Applies to us:** If our target boards are Rev A Agilex 5 silicon (needs confirming against our own board's stepping), we inherit this same requirement for free from any modern U-Boot — but must confirm our chosen U-Boot baseline actually includes it.

### The SDM reconfigure mailbox protocol has a hardcoded, tight 300ms RECONFIG_REQUEST timeout and a 4×512KiB buffer pool with a 720ms per-buffer reclaim timeout — both drivers our and his kernels share verbatim.

- **Evidence:** stratix10-svc-client.h:68-69 in both repos; matches docs/de25-fpga-reconfig.md's own independent desk-research figures
- **His fix:** None yet — his one live test hit this timeout and wedged the board; the fix path (retry/backoff/hardened quiesce) is explicitly not yet built.
- **Applies to us:** Confirms our D0.2 dossier's latency-risk flag was well-founded rather than overcautious; any of our own live-reconfigure implementation needs to budget for this timeout being real and tight on actual hardware, not just in the datasheet.

### Mainline 6.18.x cannot reconfigure an Agilex 5 fabric at all until BOTH a DT node set and a driver match-table entry are added — and adding only one of them fails in a way that looks like a driver bug.

- **Evidence:** mainline socfpga_agilex5.dtsi has no svc/fpga-mgr/fpga-region node (only svcbuffer@0); stratix10-svc.c and stratix10-soc.c match only stratix10-*/agilex-*. His commit records that patching only the fpga-mgr left modprobe succeeding while the mailbox still failed with "couldn't get service channel (fpga)", because the SVC node binds at __init before its children can be created.
- **His fix:** Two one-line match-table additions (intel,agilex5-svc, intel,agilex5-soc-fpga-mgr) plus authoring firmware/svc + fpga-mgr + fpga-region nodes in the SoC dtsi. Note his svc node needs memory-region=<&service_reserved>, iommus=<&smmu 10> and altr,smmu_enable_quirk on this SMMU-enabled SoC.
- **Applies to us:** Directly and unavoidably — this is our D0.2 §3.1/§4.2 work item, now with a working reference. The upstream Altera series uses 'intel,agilex-soc-fpga-mgr' as a DT fallback instead; either route works, but the fallback route avoids carrying driver patches. Our decision, not his.

### Reconfiguration on this SoC quantizes to ~1 s regardless of bitstream size, from two independent code paths.

- **Evidence:** U-Boot's intel_sdm_mb.c does udelay(RECONFIG_STATUS_INTERVAL_DELAY_US = 1000000) after sending the bitstream, before its FIRST RECONFIG_STATUS poll, then polls at 1 s intervals (60 s ceiling, 100-retry inner loop at 20 ms). The kernel service layer independently polls with msleep(1000) (our §6.1 row 7).
- **His fix:** None — accepted. It is why even a ~3 s claimed 'live' config is nowhere near the raw fabric-write time.
- **Applies to us:** Yes. Our §6.2 estimate of '~10 ms to ~1 s' should treat ~1 s as the practical floor, not the optimistic tail. It is still small next to a reboot.

### An MMIO read of an unconfigured or half-configured fabric is a FATAL async SError on Agilex 5 — a kernel panic, not a failed probe — and there is no AXI bus timeout, so a poke during the post-config settle window hangs a CPU (RCU stall) and a warm reset from that state brings the board back DARK (power-cycle or JTAG only).

- **Evidence:** de25_fabric_ready.py's header ('on Agilex 5 the sysid read below is then a fatal async SError (kernel panic, not a recoverable failed probe; HW-proven)'); de25_live_switch_core.sh's settle comment ('the first LWH2F poke during that window ... hangs the CPU on the AXI bus — no timeout on Agilex → RCU stall, and a warm reset from that state leaves the board DARK'); MiSTer's own 'FULL-config WEDGE ... JTAG recovery needed' strings.
- **His fix:** A hard guard before Main is ever started (a de25_core= bootargs breadcrumb from U-Boot, an HPS_FIRST_MODE marker, and a fpga_manager state check), a 5 s settle after config-complete before any fabric access, and a policy of NEVER warm-rebooting out of a suspected wedge.
- **Applies to us:** Yes, and it is a design constraint on Main_MiSTer's DE25 port, not just on scripts: anything that probes the fabric must be gated on a positive fabric-configured signal. Note also his HW-proven finding that fpga0/state reads 'unknown' (a false negative) for a fabric configured by U-Boot rather than by the kernel driver — so fpga0/state alone is not a usable guard.

### A hard-kill of the fabric client followed immediately by a reconfigure poisons the SDM service layer; the quiesce delay before a reconfigure is load-bearing and cannot be tuned down.

- **Evidence:** de25_live_switch_core.sh's F8 note: HW-tested 2026-07-16, trimming the 3 s quiesce to 1 s made the very NEXT switch fail with 'timeout waiting for svc layer buffers', and the following service restart hung a CPU on the AXI bus (RCU stall), wedging the board silently — JTAG-recoverable only. His reading is that the sleep also lets the prior reconfigure's svc buffer pool fully reclaim.
- **His fix:** Left at 3 s quiesce + 5 s settle, with an explicit DO-NOT-REDUCE comment.
- **Applies to us:** Yes, if we do runtime switching. This is ~8 s of pure sequencing per switch on top of any reconfiguration cost, and it is the real answer to 'how fast can a core switch be' — far more than the SDM write. It should be measured in D2.5 as its own term.

### MiSTer-scale Agilex 5 bitstreams for the A5EB013 die are 1.9-3.6 MB, i.e. they straddle the kernel's 2 MiB in-flight buffer pool (4 x 512 KiB).

- **Evidence:** CORES.manifest sizes (menu 1,929,216 ... ao486 3,645,440); mainline stratix10-soc.c NUM_SVC_BUFS=4, SVC_BUF_SIZE=SZ_512K.
- **His fix:** None needed once the buffer-recycling replies work; his wall was self-inflicted via an ATF mod.
- **Applies to us:** As a sizing input, yes — it fills in the missing input to our §6.2 arithmetic and confirms our 1-4 MB guess. As a wall, only if we ever modify ATF's FPGA config buffer handling. It also means any bitstream transfer necessarily makes at least 4-8 buffer round trips, so BUFFER_DONE callback health is on the critical path for every switch.

### The SDM owns the QSPI; the HPS cannot drive the Cadence QSPI controller directly (that path hangs). All HPS-side flash access goes through the FCS mailbox, in tiny chunks, with a chip-select re-assert required before EVERY write.

- **Evidence:** de25_fcs_qspi.py header ('The HPS cannot touch it through the cadence controller (that path hangs)'); de25_fcs_stage_core.py:56-70 ('the SDM deselects the QSPI chip after every write cycle, so each consecutive write MUST re-assert cs(0) first -- else the 2nd write returns SDM status 4 and WEDGES the async channel (needs JTAG/power-cycle recovery)'); qspi_read max 4096 bytes per call.
- **His fix:** 4 KiB write chunks with cs-per-write and a 50 ms settle; cancel checks only BETWEEN operations, never mid-op.
- **Applies to us:** Only if we ever write QSPI from Linux — which our posture 1 says we never do. It is decisive evidence FOR posture 1: any QSPI-write-based update mechanism on this board is minutes-long, wedge-prone, and JTAG-recoverable at best. It also means our Q4 RSU sizing question has a companion: even if RSU fits, writing it is this.

### The SD host needed capping at 25 MHz (default speed, no UHS/SDR50) for stability; SCR-corruption and ADMA issues appear around JTAG-adjacent boots.

- **Evidence:** His board DTS caps &mmc max-frequency at 25000000 with an explicit stability rationale; SETUP.md §9 additionally requires sdhci.debug_quirks=0x60 and forbids iommu.passthrough=1 for post-JTAG full-SOF boots or SDHCI ADMA corrupts early SD init.
- **His fix:** DTS clock cap plus documented cmdline requirements for the JTAG development flow.
- **Applies to us:** Probably — it is a board/PHY-level finding, and the cdns,phy-* tuning block in his DTS is inherited from Terasic. If we hit SD instability, this is the first knob, and it costs bitstream read bandwidth (a 3.5 MB core at 4-bit/25 MHz is bounded near 12.5 MB/s theoretical).

### Every reset on this SoC is a full SDM reconfiguration cycle, and software cannot distinguish a deliberate reboot from a power-cycle: RSTMGR_SOC64_STATUS reads 'Reset state: Cold' for both, and ATF's handler for software reboot is literally mailbox_reset_cold().

- **Evidence:** boot.scr.uimg's 2026-07-20 note, stated as validated against his own com9_coldboot_throttle_validate.log vs com9_warmreboot_throttle_validate.log (both logs absent from the shared repo, so the validation itself is [U]).
- **His fix:** A one-shot marker file written by the single legitimate reboot path and consumed by boot.scr on read, so any unplanned reset defaults to MENU.
- **Applies to us:** Yes for our Q5 (warm reboot, parked) and for any boot-time state machine we build. It also means a reboot can never be cheap on this board: it is a full SDM configuration cycle every time.

### Partial reconfiguration is not a free speed win: PR personas must come from one base compile, and loading a persona that does not match wedges the SDM.

- **Evidence:** MiSTer binary strings 'fpga_load_rbf: SDM WEDGE on %s (persona not from base compile?) - JTAG recovery needed' and 'fpga_load_rbf: restoring PR base before partial'; analysis/pr_partial/de25_pr_partial.dtso documents that the earlier FULL-config overlay HUNG the HPS in 'Experiment 2' and that partial-fpga-config is 'the make-or-break difference'; the PR partial bitstream in that experiment was 344 KB vs multi-MB full cores.
- **His fix:** He kept a de25base.core.rbf and restored it before a partial swap, then abandoned the tier in favour of full config once HPS-first compilation made full reconfiguration survivable.
- **Applies to us:** Relevant if anyone proposes PR as the MiSTer core-switch mechanism: it would make every core a persona of one frozen base compile — an FPGA-project-level constraint, not a software one — in exchange for a ~10x smaller bitstream.

### Every DMA-capable peripheral needs an explicit iommus= stream-ID property once an smmu node is enabled on Agilex 5 -- omitting it on even one master (he missed usb0) silently AHB-faults every DMA transfer on that device with no obvious error pointing at the DT.

- **Evidence:** de25-linux commits 36f39d30d/c917db658: usb0 was missing iommus=<&smmu 6> after being ported from a different upstream base than the vendor tree it was checked against; fixed with one line, HW-validated.
- **His fix:** Add the correct iommus=<&smmu N> property with the vendor tree's stream ID for every boot-relevant DMA master.
- **Applies to us:** Mainline 6.18.44's socfpga_agilex5.dtsi ships neither an smmu node nor any iommus= properties at all (verified directly). Whoever authors our DE25 board DTS (D0.3/D2) must add the smmu node and correctly stream-ID every master ourselves, sourced from a vendor tree or Altera's newer DTS series, and audit every DMA-capable node individually -- this is not a one-time fix, it's a class of omission to check for on every node we add.

### mmc0/SDHCI on Agilex 5 faults arm-smmu-v3 F_TRANSLATION on a genuine cold boot with an SMMU node enabled and a v6.18-generation kernel, even with a devicetree byte-identical to a working 6.12.11 baseline -- ~~a real kernel-version regression~~ **[CORRECTED 2026-08-22: a vendor-vs-mainline DRIVER delta, not a version regression — see the correction box in §3 above; the leading root cause is a 64-bit vs 40-bit DMA mask under SMMU translation, and it travels forward to 6.19/7.2]**, not a DT authoring mistake, root cause unresolved.

- **Evidence:** de25-linux commits 314a0be6c (initial false-negative) and 716559020 (retraction + reproduction via a genuine physical power-cycle through the unmodified production boot chain).
- **His fix:** sdhci.debug_quirks=0x60 on the kernel command line, forcing SDHCI/mmc0 into PIO instead of ADMA, sidestepping the DMA-through-IOMMU path entirely. Baked into the default production boot.scr.uimg bootargs, not a JTAG-only special case.
- **Applies to us:** Our kernel baseline is also 6.18.x mainline. If we enable an SMMU node for Agilex 5 (which D0.2 flagged as an open question -- §3.1 note 2, whether the svc node even needs iommus=<&smmu 10>), we should expect to hit the identical mmc0/ADMA fault the moment SD/MMC is DT-enabled alongside SMMU, and plan for the PIO-quirk mitigation (with its throughput cost) rather than treating it as a DT-authoring bug to debug from scratch. **[CORRECTED 2026-08-22:** there is no "upstream fix" coming, because there is no upstream regression — the delta is vendor-driver-vs-mainline-driver (a 40-bit vs 64-bit DMA mask) and it is present on 6.19 and 7.2 too. The mainline-first remedy to test is a one-entry `sdhci-cadence` patch adding `intel,agilex5-sd4hc` with a 40-bit mask.**]**

### Reconfiguring the fabric and then touching it (an LWH2F/fabric-side register poke) too soon after config-complete hangs the CPU on the AXI bus with no timeout -- an RCU stall that leaves the board completely dark, JTAG-recoverable only, not warm-reset-recoverable.

- **Evidence:** de25-linux board_overlay/usr/local/bin/de25_live_switch_core.sh: HW-tested trimming the post-quiesce sleep from 3s to 1s reproduced this exact failure mode; a hard-kill of MiSTer followed by immediate reconfig was separately found to poison the SDM service layer.
- **His fix:** A generous, empirically-tuned settle window: 3s before starting reconfiguration (to let the prior fabric session's buffer pool fully reclaim) and 5s after config-complete before any fabric-side access (to let the new core's internal resets/PLLs lock).
- **Applies to us:** This directly bears on D0.2 §11 row 4 (does the region accept repeated overlay apply/remove cycles cleanly). His answer is 'yes, but only with settle windows this project had to discover by bricking the board twice' -- our own D2.5 hardware-measurement plan should budget for exactly this discovery rather than assuming a bare of_overlay_fdt_apply()/remove() pair is safe back-to-back, and any MiSTer-style core-switch UI on this board needs a mandatory settle floor baked into the framework, not left to a user-triggerable spam-switch.

### The SDM mailbox layer exhibits an apparent request-budget/throttling behavior across reconfiguration attempts that is broader than any single driver bug -- a raw overlay-trigger write timed out waiting for RECONFIG_REQUEST even after the buffer-size (BUF4) bug that had caused the '>2MB wall' was already fixed.

- **Evidence:** de25-linux commit 30d9c99a8 message, explicitly describing this as 'the same class of pre-existing mailbox/budget issue already documented elsewhere in this project.' The referenced memory files documenting that broader pattern are not present in this repo snapshot -- root cause is [U] to us.
- **His fix:** Not fixed at the point this repo snapshot ends; the live-switch worker treats an unresponsive trigger write as fatal (30s deadline, then park rather than reboot) rather than retrying.
- **Applies to us:** We should not assume the mainline stratix10-soc.c/stratix10-svc.c stack is bug-free on Agilex 5 just because the compatible-string gap (U1) is a known, fixable issue. There appears to be at least one more class of SDM-mailbox fragility on this platform that neither his fixes nor our D0.2 desk research have fully characterized; D2.5's hardware-measurement plan should treat 'the mailbox occasionally times out for reasons unrelated to buffer size' as an open risk to budget time against, not a solved problem.

---

## 4. Decisions for the owner

Every point below is a place his approach diverges from our documented plan. **These are not
recommendations.** The neutrality audit that was to strip advocacy from this section never ran, so
read any evaluative wording with that in mind.


### DTSI provenance — fork mainline's socfpga_agilex5.dtsi vs override from the board DTS

- **His approach:** Forked mainline's socfpga_agilex5.dtsi and back-ported vendor nodes into it, including a wholesale replacement of the mainline gmac0 node. Board DTS is Terasic's file verbatim.
- **Our plan:** Parity-with-stock methodology: author our own board DTS on top of mainline's, using &label overrides, and keep patches off shared .dtsi files (the DE10 patch explicitly refuses to carry a socfpga.dtsi hunk for exactly this reason).
- **What forced his choice:** Forced for three of the nodes: mmc0, smmu and the firmware/svc subtree do not exist in mainline 6.18 at all, and the board DTS references &mmc, &smmu and &temp_volt by label, so their absence is a dtc compile error, not a silent gap (bf8e5c9c6 says so explicitly). The gmac0 replacement was forced by a real probe failure (e57c54c74) and he states it is a whole-node structural difference — split IRQs, reset-names, iommus — not expressible as a board-level override.
- **Cost of his way:** A forked shared .dtsi that every socfpga board in the tree inherits; every kernel bump is a merge against upstream's own evolving Agilex 5 DTSI, and upstream has already been seen to independently re-add a conflicting gmac0 revision.
- **Cost of our way:** Not available for mmc0/smmu/svc — there is nothing to override. A mainline-only DTS for this board does not boot from SD. We would have to add those nodes somewhere; the only parity-preserving choice is which file, and whether we upstream them.
- **Our doc:** docs/de25-nano-plan.md §4.1; docs/dts-comparison.md; board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch (Forward-port note refusing the shared-dtsi hunk)

### Reconfiguration trigger — custom in-tree misc driver

- **His approach:** drivers/misc/de25_fpga_trigger.c: a new 95-line misc driver with one write-only sysfs attribute that re-applies a static .dtbo via of_overlay_fdt_apply(), plus a new Kconfig symbol CONFIG_DE25_FPGA_TRIGGER.
- **Our plan:** Not decided — our fpga-reconfig §11 row 6 lists three costed options (carry OF_CONFIGFS, write a board driver, U-Boot-preload only) and defers the choice to D2.
- **What forced his choice:** Forced: mainline exposes no userspace path to fpga_mgr_load(); of-fpga-region only programs on OF_OVERLAY_PRE_APPLY; and the configfs overlay path he had assumed (RPi-style drivers/of/configfs.c) was never upstream, so his script's core step had never once worked.
- **Cost of his way:** A permanently carried out-of-tree kernel patch adding a board-specific driver + Kconfig symbol, with no upstreaming story. The trigger has no quiesce sequencing of its own, so driving it directly is documented by its own author as unsafe.
- **Cost of our way:** U-Boot-preload-only means every core switch is a reboot (~35 s on his measurements), which is the UX premise our D0.2 called into question. OF_CONFIGFS is now known not to be a real option.
- **Our doc:** docs/de25-fpga-reconfig.md §11 row 6; §8 Claim A

### Runtime HPS↔fabric access — raw /dev/mem instead of UIO

- **His approach:** CONFIG_UIO is not set. Every fabric register access (sysid probe, ascal fbcfg base) is an mmap of /dev/mem at fixed physical addresses from Python scripts run by systemd units.
- **Our plan:** DP-9 (as narrowed by D0.2 §8) leaves the runtime signaling/aperture contract explicitly undecided and flags the /dev/mem practice as the thing patches 0044/0045 exist to replace.
- **What forced his choice:** No forcing reason found in the commits; it appears to be the path of least resistance carried forward from bring-up scripting. He has not needed an aperture binding because Main's fabric access is not yet performance-bound on his setup.
- **Cost of his way:** No named/size-bounded apertures, no write-combining, no page-attribute control, and STRICT_DEVMEM had to be worked around with a no-map reserved region for AO486's 256 MB window. Also no protection against Main touching a half-configured region — a documented board-wedge hazard.
- **Cost of our way:** Re-deriving 0043/0044/0045 for Agilex 5 is real work gated on a GHRD that defines the topology, which does not exist yet.
- **Our doc:** docs/de25-fpga-reconfig.md §8 (Claim B refuted), §11 rows 10 and 11

### Vsync interrupt / FBIO_WAITFORVSYNC

- **His approach:** No interrupts property on the fb node; MiSTer_fb.c patched so an absent IRQ is legal and the ioctl simply becomes unavailable.
- **Our plan:** Our D0.2 §7.3 names 'a per-frame interrupt from fabric to HPS' as one of four requirements for a MiSTer-style framebuffer and calls it 'the doorbell problem again'.
- **What forced his choice:** No f2h IRQ is wired in his golden_top/GHRD, and the mainline Agilex 5 DTSI has no bridge or f2h interrupt-cell scheme to name one. He worked around the driver's arm32 NO_IRQ check rather than wire an interrupt.
- **Cost of his way:** FBIO_WAITFORVSYNC is silently unavailable — an ABI Main_MiSTer uses on DE10. Any tearing/pacing behavior that depends on it is gone with no error.
- **Cost of our way:** Requires the GHRD to expose an f2h interrupt and a documented Agilex 5 SPI number for it. Not resolvable from Linux alone.
- **Our doc:** docs/de25-fpga-reconfig.md §7.3 (table row 3); board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch:195-201

### Audio

- **His approach:** MiSTer-audio-spi driver ported and built as a module, but no DT node, so it never probes. No spi0/spidev nodes either.
- **Our plan:** Our DE10 DTS wires spi0 → 'MiSTer,spi-audio' @10 MHz and spi1 → spidev for brightness/add-on control, as stock-parity ABI.
- **What forced his choice:** Not stated in any commit. Most likely simply not reached yet — his SETUP.md scope is reaching the MENU. I could not find a forcing reason.
- **Cost of his way:** No audio path through the documented MiSTer mechanism; whatever audio exists is fabric/HDMI-side only. /dev/spidev1.0 (Main's brightness.cpp) does not exist.
- **Cost of our way:** Requires knowing which Agilex 5 SPI controller the GHRD wires to the audio link, which is a GHRD question.
- **Our doc:** board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch (spi0/spi1 sections); docs/dts-comparison.md

### SD performance posture

- **His approach:** max-frequency = <25000000>, no-1-8-v, sd-uhs-sdr50 and the sdhci-caps/sdhci-caps-mask overrides removed; plus sdhci.debug_quirks=0x60 (PIO, no ADMA) baked into the production boot script.
- **Our plan:** Parity with stock DE10 means SD performance is not deliberately crippled; nothing in our docs contemplates a PIO-mode root filesystem.
- **What forced his choice:** Both forced by real faults: corrupted SCR reads on post-JTAG boots (b3cc7d53f) and an SMMU F_TRANSLATION fault on mmc0 DMA that he established is a 6.12→6.18 kernel regression with a byte-identical devicetree (716559020). Root cause not bisected, deferred by explicit choice.
- **Cost of his way:** Default-speed 25 MHz 4-bit AND PIO for every block read on a Cortex-A55. This is a large, permanent, whole-system I/O penalty that touches every core load, every ROM load and the loop-mounted rootfs. It is the strongest DTS-level candidate for symptom (b) that is independent of reconfiguration cost.
- **Cost of our way:** Bisecting the 6.12→6.18 mmc0/SMMU regression, or shipping with the SMMU off / iommu.passthrough, each of which has its own consequences (his SETUP.md §9 warns iommu.passthrough=1 corrupts early SD init after a JTAG load).
- **Our doc:** docs/de25-boot-chain.md §4 (posture); docs/de25-nano-plan.md §4.1

### Core payload location — QSPI RSU slots vs SD files

- **His approach:** Original design staged core bitstreams into QSPI RSU application slots: P1 3 MB fixed MENU hub, plus (originally) a 4 MB P2 and a 3 MB P3, merged 2026-07-07 into one 7 MB staging slot so >4 MB cores would fit. The current design reads .uboot.rbf from the exFAT card instead.
- **Our plan:** Our posture-1 v1 recommendation never writes QSPI at all; cores live on the FAT partition, as on DE10.
- **What forced his choice:** He flashes his own QSPI image anyway (his SPL is exFAT-aware), so the RSU slot mechanism was available and gave a reboot-based switch that worked before the kernel fpga_manager path did.
- **Cost of his way:** A hard, small ceiling on how many core images the firmware can hold — one MENU plus effectively one staged core — and a per-core QSPI write cycle. This is the most literal match for the owner's second-hand symptom (a), 'only being able to load a certain number of cores into firmware'.
- **Cost of our way:** None on this axis; the SD-file model has no such ceiling. But it depends on a working live-switch or a reboot-with-fpga-load path.
- **Our doc:** docs/de25-boot-chain.md §4 (posture 1 vs 2)

### Core-switch mechanism actually in production use

- **His approach:** A full warm reboot (~35s) per core switch, with U-Boot re-running `fpga load` at boot per a persisted core_select.txt. His in-kernel live DT-overlay reconfigure path (~8s target) exists as of Aug 1, 2026 but is not yet reliable — it can time out at the SDM mailbox and wedge the board, and its safety net (park the board rather than reboot on a stuck-mid-config SDM) is deliberate but user-visible.
- **Our plan:** Our D0.2 dossier's DP-9 concluded core-switching is 'UX-viable at low-to-moderate confidence', implicitly assuming a fast (non-reboot) in-kernel reconfigure path is achievable, with latency still an open unknown (U5) pending measurement.
- **What forced his choice:** The reboot fallback is what actually works reliably today; the live path is new (committed same day as the failed HW test) and explicitly documented by him as not yet safe for routine use ('the raw trigger has no quiesce/settle sequencing of its own... unsafe for routine use').
- **Cost of his way:** 35s per core switch if the live path is disabled/unreliable — materially worse UX than instant Cyclone-V-style core swap, and a documented failure mode (board wedge, JTAG-only recovery) on the fast path as currently implemented.
- **Cost of our way:** Building and hardening the same live DT-overlay + SDM-mailbox mechanism ourselves, with no guarantee it clears the same 300ms RECONFIG_REQUEST timeout more reliably than his first attempt did — this is real engineering work, not a known-solved problem, and his result is the first empirical Agilex-5-hardware data point either project has.
- **Our doc:** docs/de25-fpga-reconfig.md §8 (DP-9 verdict), §6 (latency, U5 marked open)

### Bitstream authentication (VAB)

- **His approach:** VAB is not enabled — only FIT image signing (CONFIG_SPL_FIT_SIGNATURE=y). Anyone who can write the SD card/QSPI can boot arbitrary code.
- **Our plan:** Not yet decided by our project (U4 was an open unknown, not yet dispositioned in policy).
- **What forced his choice:** No evidence of an explicit security requirement in his project; consistent with a developer-focused, JTAG-recoverable bring-up posture rather than a hardened consumer deployment.
- **Cost of his way:** No bitstream-tampering protection; acceptable for a dev board, not necessarily for a shipped image.
- **Cost of our way:** Enabling VAB would require CONFIG_SOCFPGA_SECURE_VAB_AUTH plus a real key/fusing workflow, a project we have not scoped and he has not attempted either.
- **Our doc:** docs/de25-boot-chain.md (U4 listed as open unknown)

### Non-stock ATF/BL31 buffer-size modification

- **His approach:** His comments describe carrying a custom BL31 change ('FPGA_CONFIG_BUFFER_SIZE=16' mod, later a 'BUF4' fix) affecting the SDM reconfigure buffer-reclaim BUSY-reply path — a modification to Arm Trusted Firmware itself, not to U-Boot or the kernel.
- **Our plan:** Our plan is to use a modern/current U-Boot as a reference and has not scoped any ATF/BL31-level customization at all.
- **What forced his choice:** Presumably to work around an observed >2MB live-reconfigure failure — but I could not verify this in code (the ATF source is not among the repos we have access to), so I cannot confirm whether it is a real fix, a misdiagnosis, or unnecessary against a stock/current ATF.
- **Cost of his way:** An unverifiable, out-of-band firmware customization layered under U-Boot that neither of us can currently audit.
- **Cost of our way:** If we adopt current/stock ATF without this change, we do not know whether we would hit the same >2MB wall he describes — unresolved, not established either way.
- **Our doc:** docs/de25-nano-plan.md §4.1 (modern U-Boot direction)

### QSPI posture — he writes the SDM configuration flash; our v1 recommendation is never to write it

- **His approach:** Flashes a custom .jic over the factory QSPI via JTAG (golden_top_menu_exfat_spl_ro_bootcmd_20260704.jic), carrying his own exFAT-aware SPL, his own bootcmd, and his own fabric image. This is our posture 2. An earlier variant was HPS-First (Phase-1 .hps.jic, fabric left unconfigured for U-Boot to fill), and an even earlier one carried a full RSU application-slot layout (rsu_initial_v2).
- **Our plan:** Posture 1: pin factory QSPI byte-untouched, boot our own u-boot.itb from Terasic's factory SPL, treat the FSBL->u-boot.itb name+location contract as the only interface we own.
- **What forced his choice:** Forced, and the forcing reason is legible: he chose a single-partition exFAT card with the rootfs as a loop-mounted /linux/rootfs.ext4, and the factory SPL cannot read exFAT. His two DE25 U-Boot commits are exactly 'Add SPL exFAT boot support for DE25' (a new common/spl/spl_exfat.c plus an imported libexfat) and 'Make DE25 exFAT boot read-only and script-first'. An exFAT SPL cannot live on the SD card it must read, so it has to go into QSPI.
- **Cost of his way:** Every board needs a bench JTAG flash before it boots, with Quartus Pro on a PC. The QSPI becomes a per-board version-skew surface (his SETUP.md §10 troubleshooting is 'you flashed the wrong .jic'). It cost him at least one hard brick (2026-07-12: a stale RSU fallback armed reboot_image over a Phase-1 image, SDM booted garbage, JTAG reflash). And it makes the SPL/bootcmd our-code, not vendor-code, forever.
- **Cost of our way:** We inherit whatever the factory SPL can read — realistically FAT — so the single-exFAT-card layout and the loop-root design are off the table for us, and the version-skew seam our de25-boot-chain.md §5 identifies stays. We also cannot fix an SPL bug without moving to posture 2/3.
- **Our doc:** docs/de25-boot-chain.md §4 (postures 1/2/3) and §5 (version-skew seam); docs/de25-nano-plan.md §4.1; DP-1

### Card layout — one exFAT partition with a loop-mounted ext4 rootfs vs our FAT + rootfs model

- **His approach:** Single active MBR partition, exFAT, spanning the card; boot files at the root; rootfs is /linux/rootfs.ext4 (3.5 GiB) loop-mounted as /dev/loop8 with the outer exFAT bind-mounted at /media/fat. Kernel-side init/do_mounts carries a custom mount_mister_loop_root path.
- **Our plan:** DE10-style separation: a FAT boot partition read by the bootloader plus a rootfs the kernel mounts directly; persistent state on the FAT partition.
- **What forced his choice:** Stated in SETUP.md §1: it supersedes an earlier FAT32-p1 + ext4-p2 layout so the whole card is one user-visible exFAT volume (the MiSTer /media/fat experience) with no small boot partition to manage. It is what forced the exFAT SPL, hence the QSPI flash.
- **Cost of his way:** An exFAT SPL, a QSPI flash per board, a kernel patch to init/do_mounts, an ext4-in-a-file rootfs that cannot be grown or fsck'd normally, and a documented Windows failure mode copying the 3.5 GiB image (ERROR 1006 on some readers). He also hit live ext4-in-loop rootfs corruption during a failed boot incident.
- **Cost of our way:** Two partitions the user can see, and a FAT-side/rootfs-side split for persistent state — exactly the DE10 model our persistent-state rule already assumes.
- **Our doc:** docs/de25-boot-chain.md §3 ('What lives where'); docs/de25-nano-plan.md §4.1

### U-Boot base version

- **His approach:** U-Boot 2025.01, the Terasic/Altera socfpga vendor fork (Makefile VERSION=2025 PATCHLEVEL=01), with his exFAT work applied on top. He never rebased.
- **Our plan:** Modern/current upstream U-Boot, per the owner's standing instruction.
- **What forced his choice:** He started from the board's own factory u-boot.itb (which identifies as 2025.01-gd0f8813fd6bf, i.e. a build of this tree at Terasic's board commit) and needed the vendor DDR/SDM/handoff code that is only in that fork. Rebasing was never the goal; booting was.
- **Cost of his way:** His SPL exFAT series is against a 2025.01 vendor fork; nothing of it is upstreamable as-is and it does not transplant to current U-Boot without work. He also inherits the fork's Agilex 5 quirks with no upstream fix path.
- **Cost of our way:** We must establish that current upstream U-Boot has enough Agilex 5 support for this board, and carry the Terasic board DTS/defconfig ourselves. His repo shows the board support commit is small and self-contained (8 files) — that is encouraging, not proof.
- **Our doc:** docs/uboot-mainline-port.md / docs/uboot-tasks.md; owner's standing instruction

### Core storage model — cores in QSPI 'firmware' slots vs cores as files on the card

- **His approach:** Three successive models: (Tier C/RSU) stage a core's .rpd into a QSPI RSU application slot via the FCS mailbox and reboot the SDM into it; (Tier C/launcher) leave cores on the card as .uboot.rbf and warm-reboot so U-Boot fpga-loads the selection named in /core_select.txt; (live) kernel fpga_manager overlay, no reboot. He moved forward through all three; the RSU tier is now explicitly defused.
- **Our plan:** Cores are ordinary files on the card, loaded at runtime through the kernel fpga_manager + DT overlay; QSPI is never written.
- **What forced his choice:** The forcing reason is legible from the tier ordering: the RSU path was the first thing that worked, because it needs no working overlay loader and no kernel fpga_manager binding — the SDM does the configuration at reset. He only reached the fpga_manager path after fixing the agilex5 compatibles on 2026-08-01.
- **Cost of his way:** This IS symptom (a) and half of symptom (b): a hard cap of MENU + two (then one) cores resident in firmware, minutes to re-stage, a reboot per switch, and a brick class where a mis-armed reboot_image points the SDM at a slot that no longer holds a valid image.
- **Cost of our way:** We depend entirely on the overlay path working, repeatedly, which our §6.1 row 4a and §3.2 flag as the unexercised risk — with no fallback tier if it does not.
- **Our doc:** docs/de25-fpga-reconfig.md §2, §3.2 option (c); docs/de25-nano-plan.md DP-9

### Overlay loader choice

- **His approach:** Currently option (b): a custom ~95-line misc driver (de25_fpga_trigger) over of_overlay_fdt_apply(), applying a STATIC pre-built .dtbo that names a FIXED firmware path, with the chosen core copied to that path first. Previously he relied on option (a), the vendor kernel's CONFIG_OF_CONFIGFS, without knowing it was vendor-only.
- **Our plan:** Undecided between (a) carry OF_CONFIGFS, (b) our own small driver, (c) U-Boot preload only; (c) is sufficient for the L1 developer OS.
- **What forced his choice:** Not a design preference — a forced discovery. His scripts assumed configfs because every Altera document describes it; when he moved from the stock 6.12.11 kernel (CONFIG_OF_CONFIGFS=y) to his mainline-based 6.18 port, the path silently vanished and his core-write step failed structurally.
- **Cost of his way:** ~95 lines and a UAPI he owns forever, plus a static-overlay design that cannot vary anything per switch except the file contents at a fixed path. In exchange: no out-of-tree Kconfig carry and no dependence on an unmerged 2014 series.
- **Cost of our way:** Option (a) matches every vendor recipe verbatim but carries a patch unmerged since 2014; option (c) means no runtime core switching at all.
- **Our doc:** docs/de25-fpga-reconfig.md §3.2 (option table a/b/c)

### Fabric-at-boot posture — HPS-First (fabric unconfigured until something loads a core) vs golden/MENU-in-QSPI

- **His approach:** Tried HPS-First (Phase-1 .hps.jic; U-Boot fpga-loads the selected core before booting Linux) and RETIRED it in favour of a golden .jic that configures a MENU fabric from QSPI at every reset. Guards were needed either way: a de25_core= bootargs breadcrumb, an /media/fat/HPS_FIRST_MODE marker, and a fabric-ready probe, because on Agilex 5 an MMIO read of an unconfigured fabric is a fatal async SError (kernel panic), not a failed probe.
- **Our plan:** Not yet decided; our de25-boot-chain.md assumes the factory QSPI configures the fabric and our fpga-reconfig doc assumes Linux reconfigures it afterwards.
- **What forced his choice:** HPS-First produced a reproducible fatal async SError on the first fabric read ~26 s into every warm-reboot boot, board unreachable, JTAG recovery required — he explicitly tested and REFUTED the leading hypothesis (a redundant double `bridge enable`) and still could not fix it. Retiring the posture was the fix.
- **Cost of his way:** A cold boot always lands on the MENU fabric, matching DE10's menu.rbf-at-every-boot guarantee, at the cost of putting a fabric image in QSPI (posture 2 again).
- **Cost of our way:** If we stay on the factory QSPI we inherit whatever fabric Terasic's golden image configures, and our first fabric access from Linux must be guarded the same way — an unguarded probe is a panic, not an error.
- **Our doc:** docs/de25-boot-chain.md §2, §7; docs/de25-fpga-reconfig.md §7

### Warm reboot as a core-switch mechanism, and the cold/warm indistinguishability it forces

- **His approach:** The reboot tier writes /core_select.txt and reboots; because U-Boot cannot tell a deliberate reboot from a power-cycle (RSTMGR_SOC64_STATUS reads 'Reset state: Cold' for both, and ATF's own handler for every software reboot is mailbox_reset_cold()), he added a one-shot /core_switch_pending.txt marker that boot.scr consumes on read, so any unplanned reset falls back to MENU.
- **Our plan:** No reboot-based switching contemplated; our Q5 parks warm-reboot behaviour as [U].
- **What forced his choice:** Forced by the SoC: he validated the indistinguishability against his own cold-boot and warm-reboot serial logs. Without the marker, a core that hangs at boot is retried forever.
- **Cost of his way:** An extra file-based state machine spanning Linux and U-Boot, and a boot that must be orchestrated by exactly one code path to be honoured.
- **Cost of our way:** None directly — but Q5 should record that a warm reboot on this SoC is a full SDM reconfiguration cycle and is not distinguishable in software from a cold boot.
- **Our doc:** docs/de25-boot-chain.md §8.5 (Q5, warm reboot parked)

### Kernel base

- **His approach:** A mainline-derived 6.18.38 tree with the DE25 board port and the MiSTer kernel series merged in, plus a de25_defconfig. The board's shipped rootfs still carries modules for the Terasic 6.12.11 vendor kernel, and his autostart script insmods loose .ko files by absolute path because they are not depmod-wired.
- **Our plan:** Buildroot-built mainline 6.18.44 with our patch series, one coherent module tree.
- **What forced his choice:** He is running Terasic's STOCK rootfs (extracted from de25_nano_revA_sdcard_console_v1.1.img p2) with an overlay dropped on top, so the userspace and the kernel come from different worlds and the seams are patched by hand.
- **Cost of his way:** Hand-installed modules, an insmod-by-path loop in a service, and a documented class of silent failure when the module tree and the running kernel disagree — the same trap our own memory notes call out for kernel bumps.
- **Cost of our way:** We build the rootfs, so this class does not arise; but we also do not get Terasic's vendor userspace for free.
- **Our doc:** docs/de25-nano-plan.md; ADR 0027 (bare developer OS scope)

### QSPI-resident boot posture

- **His approach:** He flashes his own custom .jic (a Terasic golden_top GHRD rebuild with a custom exFAT-aware, read-only, script-first SPL) over JTAG, rather than the factory-shipped image. His SPL sources boot.scr.uimg from an exFAT partition instead of the DE10-style FAT32/0xA2 split.
- **Our plan:** Posture 1 (v1 recommendation, not yet decided): pin factory QSPI byte-untouched, never write it, and prove our own u-boot.itb loads under Terasic's unmodified factory SPL.
- **What forced his choice:** His stated reason (SETUP.md §1/§3) is that the persistent exFAT + single-partition loop-root boot flow needed an exFAT-aware SPL, which the factory SPL is not; an earlier all-core U-Boot fpga-load launcher approach wedged the SDM and was retired, motivating a rebuilt, more conservative SPL.
- **Cost of his way:** He owns SDM firmware + FSBL + DDR/pinmux handoff for every board onboarded (a bench JTAG operation per unit); factory-FSBL compatibility with any mainline artifact (U3) is now untested and unknown for his design.
- **Cost of our way:** Posture 1 constrains the SD-side boot flow to whatever partition scheme the factory SPL can read (its SPL_FS_LOAD_PAYLOAD_NAME/FS_BOOT_PARTITION contract), and is untested against a mainline-built u-boot.itb until D2.2's first hardware pass.
- **Our doc:** docs/de25-boot-chain.md §4 (three postures) and §8.3 (Q3, parked)

### Core-switch mechanism and QSPI role

- **His approach:** Runtime core switching is a two-tier system: a fast, no-reboot Linux-kernel overlay path (de25_fpga_trigger -> of_overlay_fdt_apply -> stratix10-soc.c) as the default, falling back to a warm-reboot U-Boot fpga-load path; an earlier QSPI-resident RSU multi-slot staging scheme for baking cores into flash was tried and partly retired after a board-wedging failure.
- **Our plan:** DP-9 (decided in direction): DTS/fpga-region overlay configuration is the sole native reconfiguration architecture on Agilex 5, adopted in place of the DE10's carried UIO doorbell patches. Our plan does not touch QSPI for core switching at all (per de25-boot-chain.md §5's 'no release writes QSPI' rule).
- **What forced his choice:** QSPI staging was his path to give any-size cores a boot-time selection mechanism before the Linux overlay driver existed and worked; it was abandoned once the overlay-based live-switch matured, not because QSPI residency was ever the intended long-term design.
- **Cost of his way:** He hit two board-wedging failures along the way (the retired all-core fpga-load launcher, and the 2026-07-12 stale-.rpd/reboot_image wedge) before landing on the Linux-overlay-based approach our DP-9 already independently arrived at from source-code reading alone.
- **Cost of our way:** None yet paid -- D0.2's overlay-only conclusion is confirmed as correct by his hardware trail, at the cost of two wedges he already absorbed and we have not.
- **Our doc:** docs/de25-fpga-reconfig.md §8 (DP-9 verdict), docs/de25-nano-plan.md §6 DP-9

### HPS Ethernet MAC address

- **His approach:** A single fixed MAC (CE:24:6F:BD:E3:59) baked into a NetworkManager cloned-mac-address profile shipped inside the released rootfs image -- identical on every board flashed from that image.
- **Our plan:** No DE25-specific mechanism designed yet; the DE10 precedent (ADR-adjacent, installer-overlay/init) generates one random locally-administered MAC per physical card at flash time and injects it via U-Boot's fdt_fixup_ethernet()/aliases mechanism, giving each card a distinct address; the project's stated philosophy (ADR 0015, per-device SSH host keys) explicitly rejects shipping identical per-device identifiers.
- **What forced his choice:** His stated reason (comment in the .nmconnection file) is purely pragmatic: get a deterministic DHCP lease for a single development board without touching U-Boot env/QSPI at all, given the HPS has no fused MAC and CONFIG_NET_RANDOM_ETHADDR randomizes it every cold boot.
- **Cost of his way:** Every board flashed from his released rootfs image collides on the same MAC and the same DHCP lease if two are ever on the same network -- fine for one dev unit, not viable as a multi-user distribution default.
- **Cost of our way:** Requires either reusing the DE10's flash-time random-MAC-into-u-boot.txt mechanism (needs a persisted env location on the exFAT/loop-root layout, which is a different boot flow than DE10's) or a first-boot systemd/udev generator writing a per-device NetworkManager profile -- undesigned, not yet costed.
- **Our doc:** board/mister/de10nano/installer-overlay/init:856-885; memory: ssh-host-keys-shared-across-all-misters (ADR 0015 philosophy)

---

## 5. Open questions this pass did not close

- Does the DE25-Nano HPS actually have 2 GiB of DRAM? His memory node hard-codes reg = <0 0x80000000 0 0x80000000> despite a comment saying the bootloader fills it in, while our plan §4.1 records 1 GB LPDDR4 for the HPS from the User Manual. If it is 1 GiB, x86ram@b0000000+0x10000000 sits exactly at the top of RAM and the declared size is wrong — worth checking against a booted /proc/meminfo or the U-Boot log before we copy any of this map.
- Is his claim that the FDT reserved-memory scanner silently drops the LAST child node true on 6.18? He designs around it (x86ram deliberately not last) but cites only a document in a parent repo I do not have. If false, it is harmless superstition; if true, it is a mainline bug we should know about.
- Which of the four SMMU stream IDs (gmac0=1, mmc0=5, usb0=6, svc=10) are architectural for Agilex 5 and which are Terasic-GHRD-specific? He inherited all four from the vendor BSP without a citation to an Intel document.
- Does the svc node actually require iommus=<&smmu 10> and altr,smmu_enable_quirk, or are they cargo from the vendor tree? He never tested the form without them, and mainline gen1 socfpga_agilex.dtsi has no such properties on its svc node.
- Is the ~3 s / 3.3 MB reconfiguration figure real? It appears only as a source comment citing analysis/SUB10S_ATF_KERNEL_DIVERGENCE.md and a COM9 serial log, neither of which is present in this repo. The single documented HW attempt at the kernel fpga_manager path FAILED with 'timeout waiting for RECONFIG_REQUEST', so the ~3 s number most plausibly comes from the U-Boot fpga-load path, not the Linux path. Someone should establish which path it measures before D0.2's UX conclusion is revisited on it.
- Does the >2 MB live-load wall really disappear with a stock (unmodified) BL31, or only with his BUF4 build? He attributes the wall to his own FPGA_CONFIG_BUFFER_SIZE=16 modification, which would mean a stock ATF never had the problem — but that is his diagnosis of his own bug, and it is the load-bearing claim for symptom (a) being self-inflicted rather than intrinsic.
- How does Main_MiSTer find the HDMI transmitter on DE25? On DE10 it probes 0x39 across /dev/i2c-0..2 (video.cpp:1448) and refuses to scan past bus 2. His DTS enables exactly one HPS I2C adapter with no children, and the ADV7513 control I2C is on FPGA pins. Either his aarch64 Main fork removed that probe or the transmitter is configured entirely from the fabric — neither is established here.
- Where did the audio path go? MiSTer-audio-spi is ported and built as a module but has no DT node. Is HDMI audio driven entirely from the fabric on this board, making the SPI audio link unnecessary, or is audio simply not implemented yet?
- Whether the ascal-scratch/framebuffer split at 0x9e000000 / 0xa0000000 is forced by hardware or is a consequence of his particular golden_top's fbcfg wiring. If it is a design choice, our port need not inherit the 64 MiB of reservations.
- Does 'a certain number of cores' refer to the 8-core roster limit (CORES.manifest) or the (claimed-fixed, unverifiable) >2MB BL31 buffer wall, or both? Ambiguous, not disambiguated by any source available to us.
- Is the claimed 'NES live-switches in ~3s' result (script header, referencing an analysis file not present in either repo we have access to) still valid, given the same-day 30d9c99a8 commit shows a fresh standalone HW test of the reconfigure mechanism failing? Could not resolve.
- Does the 'FPGA_CONFIG_BUFFER_SIZE'/'BUF4 BL31' fix he describes actually exist and do what the comments claim? The ATF/arm-trusted-firmware source is not among the repos we were given — unverifiable from here.
- Why does our own linux-6.18.44 baseline lack the agilex5-svc/soc-fpga-mgr/fpga-region DT nodes that his 6.18.38-based tree (a numerically earlier stable point release) already has? Worth checking directly against a plain kernel.org 6.18.44 tarball rather than assuming either tree's provenance.
- Was the factory Terasic FSBL ever tested against a non-custom (mainline-built) u-boot.itb? No evidence either way in the materials available.
- What is the real Rev A vs Rev B silicon stepping of the DE25-Nano boards our project would target, given the Intel Rev-A-only U-Boot workaround (2030244a1e) is conditional on that?
- His record is internally contradictory about whether a no-reboot core switch was EVER achieved. 7fb52ac3f (2026-07-13) claims 'HW-proven a2600<->NES round trip in 16-18s' via the configfs overlay; 881d4404a (2026-08-01) says that same write 'had ALWAYS failed here, structurally, since before this file's own history begins'. The reconciliation the dates support is that the July tests ran on Terasic's stock 6.12.11 kernel (CONFIG_OF_CONFIGFS=y [V]) and the August finding is about his mainline 6.18 port, which first booted on hardware 2026-07-24 [V]. Worth asking him directly — because if the 16-18 s round trip is real, it is the single most valuable data point in existence for our D0.2 §6, and if it is not, nobody has yet switched a core on Agilex 5 without a reboot.
- Which symptom did the owner's friend actually report, and from which era? '~35 s reboot per switch' (launcher tier, 2026-07-13 onward), 'minutes per switch' (RSU/FCS staging tier, before that), and 'only small cores load' (the 2 MiB svc-buffer wall) are three different experiences of three different designs. The second-hand phrasing 'a certain number of cores into firmware' matches the RSU tier specifically.
- The backing artifacts for every timing claim are absent from the shared repos: analysis/SUB10S_ATF_KERNEL_DIVERGENCE.md, the whole memory/*.md set referenced by name in a dozen script comments, com9_coldboot_throttle_validate.log / com9_warmreboot_throttle_validate.log, and analysis/boot-hf-launcher-production.cmd. If he can share the COM9 serial logs and the SUB10S analysis, that is the only path to closing U5 without our own hardware.
- Exactly what his BL31 'FPGA_CONFIG_BUFFER_SIZE=16' modification changed, and whether stock ATF (2.12.0 per Terasic's build record, or 2.14) has the same behaviour. The kernel-side 2 MiB geometry is [V] mainline; the ATF side is his prose only, and neither reference repo contains ATF source. If the BUSY/BUFFER_DONE contract is fragile in stock ATF too, the 2 MiB wall becomes OUR problem and not just his.
- Is the DE25's QSPI actually 16 MiB or 256 MiB? The Terasic U-Boot DTS says mt25qu02g (256 MiB) but the node is verbatim SoCDK boilerplate; his RSU layout terminates exactly at 16 MiB. This bears directly on our Q4 ('Does RSU fit in 16 MB?') — if the part is really 2 Gbit, that question changes shape entirely. Settle it against the DE25 UM/schematic or an on-board `sf probe`, not against a copied DTS node.
- Whether Terasic's FACTORY QSPI (as opposed to his replacement .jic) enforces bitstream authentication. His unsigned-RBF success is on a board whose QSPI he overwrote; U4 is answered for the silicon but not strictly for the factory configuration.
- Whether the fpga-region overlay path survives DOZENS of apply/remove cycles — our §3.2's 'no mainline user at all' concern. His design deliberately re-applies a STATIC overlay via of_overlay_remove() + of_overlay_fdt_apply() each time, which is exactly that pattern, but he has not run it end-to-end even once.
- Whether the golden/MENU-in-QSPI posture he settled on is compatible with our posture 1 at all: does Terasic's FACTORY .jic configure a fabric that a MiSTer MENU can run on, or does reaching the MENU inherently require replacing the QSPI fabric image? If the latter, posture 1 is only viable for the L1 developer OS and DP-1 must be re-opened for the MiSTer image. Nothing in either repo answers this — he never ran on the factory .jic.
- What exactly is the 'throttle'/'budget depleted' mailbox issue referenced in commit 30d9c99a8? The memory files it cites are not in this repo snapshot (they live in an external monorepo we were not given), so its root cause, frequency, and whether it is deterministic or transient remain unknown to us.
- Does Terasic's factory-shipped (unmodified) SPL/FSBL accept a mainline-built u-boot.itb at all (U3)? Neither this task nor his repo has ever tested it -- he replaced the SPL before first boot. This is the single biggest open item for our posture-1 plan and is not answerable from either reference repo; it needs a real board running the untouched factory .jic.
- Is his board's permissive VAB state (U4) representative of the DE25-Nano product line generally, or could Terasic ship (or a customer provision) units with VAB fused? His evidence is single-unit and structural (an unsigned .jic boots), not a statement about eFuse policy across the SKU.
- Does the mmc0/SMMU F_TRANSLATION regression (6.12->6.18 window) have a known upstream fix, a tracked kernel bug, or a narrower root cause than 'somewhere in arm-smmu-v3 or DMA-mapping'? He explicitly deferred bisection; this is worth a targeted search before our own D0.3/D2 work reaches the same wall.
- What is the actual current state of end-to-end live core switching as of his latest commits (881d4404a, 2026-08-01)? SETUP.md (dated 2026-07-04) says core switching is not wired up; later commits show it working in principle (mechanism HW-confirmed) but the most recent standalone test of the new trigger driver hit a mailbox timeout. Whether a full menu-driven live switch has been demonstrated end-to-end with all fixes (agilex5 compatibles + de25_fpga_trigger + BUF4 BL31) applied together is not established from what's in this repo.
- Does his DP-1-relevant Terasic stock image (de25_nano_revA_sdcard_console_v1.1.img) represent a genuine board-support reference analogous to what DE10's stock-shadowing model needs, or is it materially different in kind (a generic Linux console BSP vs. a running MiSTer install)? This bears on whether DP-1's premise needs revisiting and by how much -- flagged, not resolved, per the task's standing instruction not to decide DP-1 here.

---

## 6. What still needs doing

1. ~~**Re-run the killed legs**~~ — **DONE / MOOT, 2026-08-22.** Leg 4's U-Boot half was re-run and
   is folded in as [§7](#7-leg-4-u-boot--filled-in-2026-08-22). Its posture half is **moot**: the
   owner settled the card layout and the QSPI posture (two partitions, p1 FAT, factory SPL
   untouched, Linux never writes QSPI), so there is no posture-1-vs-posture-2 call left to make.
2. **Adversarial verification.** **PARTIAL, 2026-08-22** — see
   [§8](#8-verification-record-2026-08-22). The load-bearing platform claims the successor document
   leans on were independently checked; most held, two failed and are corrected in place. **The
   brick-adjacent and flash-path claims (FCS/QSPI staging, the SError/LWH2F wedge, the RSU slot map)
   were NOT re-checked** and still do not meet the bar.
3. **The posture-1 gate remains open (D0.1 Q3).** Nobody has booted a mainline-built `u-boot.itb`
   from Terasic's *factory* SPL — his repo is structurally unable to answer it, since he replaced
   the SPL. The best indirect evidence: his own defconfig sets `CONFIG_SPL_FIT_SIGNATURE=y` and he
   loads locally built **unsigned** FITs successfully, which is the same U-Boot code path and is
   consistent with a control DTB that requires no keys **[V]**.


---

## 7. Leg 4 (U-Boot) — filled in 2026-08-22

The leg that never ran. Its brief had two halves. **The posture half is moot**: the owner has since
settled the QSPI posture and the card layout — two partitions (p1 FAT, p2 everything else), the
factory SPL in QSPI untouched, and Linux never writing QSPI — so there is no posture-1-vs-posture-2
cost analysis to write. What follows is the technical half, and it is recorded here as reference
material in the same spirit as the rest of this document. The decision-bearing write-up, with the
build fragment, lives in [`de25-implementation-path.md`](de25-implementation-path.md) §6.

**Note on evidence standard.** These findings were produced by a single leg on 2026-08-22 and are
**mostly not adversarially verified** — the exceptions are the four items explicitly marked
"re-verified" below, which were fetched from `u-boot/u-boot@v2026.07` and read during the
verification pass. Everything else here carries this document's usual single-agent standard.

**What his tree is, for comparison [V].** U-Boot **2025.01**, branch `de25-mister-exfat-boot`. The
`u-boot.itb` he pulled off the factory board identifies as `2025.01-gd0f8813fd6bf` with
`vendor=terasic` — Terasic shipped a build of this very tree at its "add support for de25-nano"
commit, and his own build carries the identical version string, so he never moved off 2025.01. His
defconfig sets `CONFIG_SPL_FIT_SIGNATURE=y` (as mainline's agilex5 defconfig does) yet he loads
locally built **unsigned** FITs successfully; the SPL FIT load contract is visible as
`CONFIG_SPL_LOAD_FIT_ADDRESS=0x82000000`, `CONFIG_SYS_SPI_U_BOOT_OFFS=0x04000000`.

**1. There is no DE25-Nano in mainline U-Boot [V].** `board/terasic/*` at `v2026.07` has
de0-nano-soc, de1-soc, de10-nano, de10-standard and sockit — no de25 — and no `configs/*de25*`
exists anywhere in the 40,995-path tree. We carry the board fragment ourselves; there is nothing to
select. Mainline's generic `socfpga_agilex5_defconfig` is the starting point.

**2. `u-boot.itb` comes from binman, not the legacy Makefile rule [V].** The legacy `u-boot.itb:`
rule is gated on `U_BOOT_ITS`, set only under the deprecated `SPL_FIT_GENERATOR`. `ARCH_SOCFPGA_AGILEX5`
`select`s `BINMAN if SPL_ATF`, and the defconfig sets `CONFIG_SPL_ATF=y` *(re-verified: line 54 of
`socfpga_agilex5_defconfig@v2026.07`)*, so `make all` runs binman against
`arch/arm/dts/socfpga_soc64_fit-u-boot.dtsi`. The resulting FIT carries: `uboot` =
`u-boot-nodtb.bin` (standalone, arm64, load `0x80200000`); `atf` = `bl31.bin`
(`os=arm-trusted-firmware`, load = entry = `0x80000000`); `fdt-0` = `u-boot.dtb`; and one config
node `board-0` marked `default`, signed only with a `crc32` integrity stamp — no keys. That last
detail is consistent with this document's §2 U3/U4 finding that the factory SPL's control DTB
requires no signing keys.

**3. Board-ID matching cannot lock us out [V].** `board_fit_config_name_match()` *is* compiled in
for SOC64 (`arch/arm/mach-socfpga/board.c:148-158`) and matches each config node's **`description`**
— not its node name — against `"board_%u"` from `socfpga_get_board_id()`. `fit_find_config_node()`
falls back to `/configurations/default` when nothing matches. A single-config FIT therefore boots
correctly regardless of what board ID the SPL reports. This closes a residual that the original
posture-1 analysis had left open.

**4. The env configuration is a latent QSPI-write hazard, and the guard is a defconfig line, not
discipline [V, re-verified].** Mainline's `socfpga_agilex5_defconfig@v2026.07` sets **both**
`CONFIG_ENV_IS_IN_FAT=y` (`:72`) and **`CONFIG_ENV_IS_IN_UBI=y`** (`:73`), with
`ENV_FAT_DEVICE_AND_PART="0:1"` (`:74`), `ENV_UBI_PART="root"` (`:75`), `ENV_UBI_VOLUME="env"`
(`:76`) *(all four lines re-verified by fetching the defconfig)*. The hazard is **not** `saveenv` —
it is `env_load()`. `env_ubi_load()` calls `ubi_part()` **unconditionally** at
`env/ubi.c:128` whenever the FAT load fails *(re-verified: `env/ubi.c@v2026.07` fetched and read;
`ubi_part()` at `:128` inside `env_ubi_load()` at `:107`)*. Against a **fully erased** MTD partition
`ubi_attach()` *succeeds* (`ai->is_empty = 1`), and `ubi_read_volume_table()` then calls
`create_empty_lvol()` → `create_vtbl()`, **writing a fresh UBI layout volume into QSPI**. So: a
missing or corrupt FAT env plus a blank `root` MTD writes QSPI on the first boot, with no user
action. **The guard is `# CONFIG_ENV_IS_IN_UBI is not set` in our fragment.** Nothing in
`ARCH_SOCFPGA_AGILEX5`/`ARCH_SOCFPGA_SOC64` selects it — it is a plain defconfig choice. This
promotes [`de25-readiness-ledger.md`](de25-readiness-ledger.md) row 12 from **[U]** to
**[V, code-traced]**.

**5. `CONFIG_SPL` looks droppable [U].** Nothing forces it on: `ARCH_SOCFPGA_AGILEX5` selects
`BINMAN if SPL_ATF`, `CLK`, `FPGA_INTEL_SDM_MAILBOX`, `SPL_CLK if SPL`, and `ARCH_SOCFPGA_SOC64`,
and none of the binman FIT images references anything under `spl/`. So `# CONFIG_SPL is not set`
should genuinely eliminate SPL compilation while still emitting `u-boot.itb`. **Reasoned from the
Kconfig graph, not build-tested** — first thing to check at first build.

**6. The exFAT blocker has expired [V].** Mainline U-Boot has real exFAT — `fs/exfat/`,
`CONFIG_FS_EXFAT` ("read/write support") — added by commit `b86a651b64` on **2025-03-17**, i.e.
*after* his 2025.01 base. That is exactly why he had to hand-roll `libexfat` and a custom
exFAT-aware SPL, and it is why that whole workstream is **not** something we inherit: on current
mainline the equivalent is one defconfig line. Note the stock defconfig enables `SPL_FS_FAT` (`:22`)
but not `FS_FAT`/`CMD_FAT`/`FS_EXFAT` for U-Boot proper *(re-verified)*. This removes a capability
gap; it does not by itself decide p2's filesystem.

**7. Version pairing, and the honest caveat [V for versions, U for the pairing].** Mainline
**v2026.07** is current stable (v2026.10 is at -rc2, due 2026-10-05), and mainline **TF-A v2.15.0**
does carry `plat/intel/soc/agilex5/`. **That pairing is unblessed and untested by anyone we know
of** — Terasic and Altera document only vendor forks (`u-boot-socfpga socfpga_v2023.10` +
`arm-trusted-firmware socfpga_v2.10.0`), and he stayed on 2025.01 throughout. Whether a stock
v2.15.0 BL31 boots this board, and whether it handles >2 MB reconfiguration without his
`FPGA_CONFIG_BUFFER_SIZE` modification, is open.

**What Leg 4 does *not* answer.** It does not close U3 — nobody has booted a mainline-built
`u-boot.itb` from Terasic's **factory** SPL, and no amount of source reading can. That remains the
single biggest open item for posture 1 and needs a real board on an untouched factory `.jic`.

---

## 8. Verification record (2026-08-22)

A separate run put this document's load-bearing platform claims through the adversarial pass that
the original run never got to. **Scope: the subset that the successor document
[`de25-implementation-path.md`](de25-implementation-path.md) leans on.** Claims not listed here were
not re-checked and still carry the original single-agent standard.

### Independently verified — claims that HELD

| Claim (where it lives here) | Outcome | How it was checked |
|---|---|---|
| Mainline 6.18.44's `socfpga_agilex5.dtsi` has **no** `mmc0`, `smmu`, `svc`, `fpga-mgr` or `fpga-region` node (§2 U1, §3) | **VERIFIED** | Case-insensitive `grep` for `mmc\|sd4hc\|sdhci\|smmu\|iommu` over the 826-line file → **zero hits**; only `service_reserved` svcbuffer at `:23`, `clkmgr` at `:144-148`, QSPI at `:477`, three stmmac compatibles at `:491,:603,:715` |
| Neither `stratix10-svc.c` nor `stratix10-soc.c` matches an agilex5 string in 6.18.44, and both tables carry **no `.data`** (§2 U1, §3) | **VERIFIED** | Tables read at `stratix10-svc.c:1133-1137` and `stratix10-soc.c:448-452`; `grep` for `of_device_get_match_data`/`of_device_is_compatible`/`match->data` in both files → zero hits. Also re-verified at **v7.2** (`:1911-1915` and `:448-452`) and at `master` — still no agilex5 string |
| His fix is exactly two one-line match-table additions (§2 U1, §3) | **VERIFIED** | `de25-linux:drivers/fpga/stratix10-soc.c:451`, `drivers/firmware/stratix10-svc.c:1134` |
| The fault that stopped his one Linux-path reconfiguration attempt: mailbox timeout, board wedged (§2 U2/U5, §3) | **VERIFIED** | Re-read here at `:115`; consistent across Legs 1/2/3/5 |
| `stratix10-soc.c` allocates `NUM_SVC_BUFS 4 × SVC_BUF_SIZE SZ_512K` = 2 MiB in flight (§1a cap 2, §3) | **VERIFIED** | `stratix10-soc.c:19-20`, allocation loop at `:215-216` |
| `fpga_manager` class devices expose **no** writable attribute; `fpga_region` exposes only RO `compat_id`; `OF_CONFIGFS` is not in mainline (§2 U2, §3) | **VERIFIED** | `fpga-mgr.c:655-664` (three `DEVICE_ATTR_RO`, and `fpga_mgr_attrs[]` holds exactly those); `fpga-region.c:175`; `drivers/of/Kconfig` has only `OF_OVERLAY:105` and `OF_OVERLAY_KUNIT_TEST:116`; no `drivers/of/configfs.c` |
| Reconfiguration quantizes to ~1 s from two independent code paths (§1b, §3) | **VERIFIED** | `de25-uboot-socfpga:drivers/fpga/intel_sdm_mb.c:20-21` (60 s timeout, 1 s interval, `udelay(1 s)` before the first poll); kernel `stratix10-svc.c:295` `msleep(1000)`, 30 s ceiling. Caveat kept: the kernel sleep fires only if the first poll is not already complete, so "~1 s practical floor" is the right framing — which is what this document already said |
| The mmc0/SMMU `F_TRANSLATION` fault itself is real, not a warm-reboot artifact (§3) | **VERIFIED** | Commit `716559020`'s retract-of-a-retraction; the "clean" disproof boot had `sdhci.debug_quirks=0x60` silently baked in by a JTAG-recovery script default |
| MiSTer-scale A5EB013 bitstreams are 1.9–3.6 MB (§1a cap 3, §3) | **VERIFIED** | `board_overlay/media/fat/cores/CORES.manifest`: menu 1,929,216 … ao486 3,645,440. Minor discrepancy noted: the NES figure quoted in prose (3,325,952) vs the manifest's 3,346,432 — different build cutover, immaterial to the >2 MiB arithmetic |
| The friend's SD path runs an **unmodified** mainline `sdhci-cadence` (§3) | **VERIFIED** | `diff -q` against `linux-6.18.44` → identical. Qualifier added by the pass: it runs with `sdhci.debug_quirks=0x60` (PIO), so it proves binding and PIO, **not** the DMA path |

### Independently verified — claims that FAILED and are CORRECTED

| Claim | Outcome | Correction |
|---|---|---|
| "mmc0 DMA F_TRANSLATION-faults on 6.18 but not 6.12 with a byte-identical DT — **a kernel-version regression**" (§3, twice) | **FAILED — attribution wrong; fault real** | Corrected in place at both sites. The 6.12 baseline is Terasic's **vendor** tree, whose `sdhci-cadence` gives `intel,agilex5-sd4hc` a `SDHCI_QUIRK2_40_BIT_DMA_MASK` that exists nowhere in mainline; his 6.18 tree binds bare `cdns,sd4hc` and gets a 64-bit mask. Vendor-vs-mainline **driver** delta, not a version regression — and it therefore **travels forward to 6.19 and 7.2** |
| "Both match tables have no per-compatible `.data`, so the third entry is **functionally free**" (§2 Leg 3 U1, §3) | **HOLDS for mainline; MISLEADING as a general claim** | True of mainline at 6.18.44, v7.2 and `master` [V]. But Terasic's **vendor** `stratix10-svc.c` keys real behaviour off `of_device_is_compatible(node, "intel,agilex5-svc")` at `:3507`: IOMMU attach + IOVA carveout, `AGILEX5_SDM_DMA_ADDR_OFFSET 0x80000000` added to every buffer address sent to the SDM (`:59,:3244`), an `INTEL_SIP_SMC_SDM_REMAPPER_CONFIG` remapper bypass (`:3550-3551`), and a hard `-ENODEV` if the SMMU is absent. So the "per-compatible behaviour appears" falsifier is not hypothetical — it already exists downstream, and it is the concrete mechanism behind the mailbox timeout his one Linux-path attempt hit |
| ~~`drivers/input/mousedev.c` is missing `#include <linux/compat.h>`~~ | **FAILED, refuted 2026-08-21** | Already annotated in place in §3. Left exactly as it was, as the worked example of why this pass mattered |

### What the pass concluded about this document as a whole

- **No contamination found.** The known-false mousedev claim did not spread. Every claim the
  successor document leans on was re-checked; the two that failed did so for
  **evidence-characterisation** reasons — attributing a fault to the wrong variable, and
  generalising a mainline property to vendor trees — **not fabrication**. The document's `[V]`/`[U]`
  tagging proved broadly honest under spot-check.
- **One framing this document got right and the successor initially got wrong:** that end-to-end
  Linux reconfiguration has **never** succeeded on a mainline-driver path on this silicon. This
  document says so plainly at `:115` and in §5. A draft of the successor briefly described the
  trigger module as "running on real hardware"; that was corrected against this text.

### Not re-checked, and still at the original standard

Everything in §1 (the RSU slot map, the FCS staging arithmetic, the ~35 s launcher figure), the
brick-adjacent claims in §3 (SError on unconfigured fabric, the LWH2F post-config wedge, the quiesce
window, the QSPI-via-FCS constraint, the SD 25 MHz cap), the whole of §4 (decisions for the owner),
all of §5's open questions, and §7's Leg-4 findings apart from the four items marked "re-verified"
there. The timing numbers in particular remain unverifiable from here: their backing artifacts
(`analysis/SUB10S_ATF_KERNEL_DIVERGENCE.md`, the `memory/*.md` set, the COM9 serial logs) are absent
from the shared repos, as §5 already records.
