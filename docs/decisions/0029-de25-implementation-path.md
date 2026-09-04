# ADR 0029 — DE25-Nano implementation path: the nine decisions that bound wave 1

**Status:** Proposed (2026-09-02) — the nine decisions below were taken by @mcfbytes between
2026-08-19 and 2026-08-22 during D0/D1; this ADR formalises them for acceptance and makes no new one.
**Extends:** [ADR 0027](0027-de25-nano-multi-board-readiness.md). **Supersedes nothing.** Each
decision refines an ADR 0027 disposition point (DP-x) or Decision — mapped in the index table; where
no DP covers one, this ADR says so rather than back-fitting a DP.
**Impact (when acted on):** `configs/mister_de25nano_defconfig`, `board/mister/de25nano/*`,
[`patch-provenance.md`](../patch-provenance.md) (two rows), `scripts/check-kernel-defconfig-sync.sh`.
**No DE10 file changes.**
**Source of record:** [`de25-implementation-path.md`](../de25-implementation-path.md) §1, §1.1 (desk
analysis 2026-08-22, **no hardware touched**), over [`de25-boot-chain.md`](../de25-boot-chain.md) and
[`de25-fpga-reconfig.md`](../de25-fpga-reconfig.md); bare section refs are to the former, whose
**[V]** (read from a named source) / **[U]** (unverified, input named) tags are kept below.
**Related:** [ADR 0016](0016-mainline-first-wifi-drivers.md) (mainline-first precedent), [ADR 0019](0019-exfat-symlinks-carried-patch.md) (carries),
[ADR 0021](0021-rt-kernel-first-class-ci.md) (variant machinery), [ADR 0024](0024-mainline-uboot-capability-artifact.md) (mainline U-Boot).

---

## Context

ADR 0027 committed the project to a *posture* — same repo, staged phases, guarded couplings — and
deliberately took no technical position on how a DE25 boots or reconfigures. It predates all of D0.
Phases D0/D1 then completed (2026-08-21/22, [`de25-nano-tasks.md`](../de25-nano-tasks.md) "Execution
status") and the owner took nine decisions against their findings, which live only as a table in a
desk-analysis document. They foreclose options the task list still calls open, and two are the
difference between a board that boots from SD and one that does not.

Two D0 findings frame the set, neither known when ADR 0027 was accepted. **`clk-agilex5.c` does not
exist in 6.18** — it lands in v6.19 **[V §0 Finding 1, §5.1]**, so on a 6.18 base every `&clkmgr`
consumer, `mmc0` included, defers forever. And **binding the mainline FPGA-manager stack is settled;
*programming* the fabric through it is not** **[V §0 Finding 2, §2.6]**: Terasic's vendor `svc` does
Agilex-5-specific SDM plumbing (IOMMU attach, IOVA carveout, `+0x80000000` offset, remapper bypass)
that mainline lacks at 6.18.44 *and* v7.2, and the one mainline-path attempt on silicon timed out on
`RECONFIG_REQUEST` and wedged the board. Confidence: **low**.

## Decision

Accept the nine decisions below as the bounding constraints for DE25 wave 1.

| # | Decision | Source | ADR 0027 anchor |
|---|---|---|---|
| D1 | Core loading = `fpga_manager` + DT overlay | §1 row 1 | refines **DP-9** |
| D2 | Scope is "make the hardware available"; Main_MiSTer loads | §1 row 2 | **DP-1**, 0027 **Decision 6** |
| D3 | Two partitions (p1 FAT, p2 the rest); no card shared with a DE10 | §1 rows 3–4 | **DP-3**, **DP-1** |
| D4 | Posture 1: nothing we ship writes the factory QSPI | §6 pre; boot-chain §4, §10 | **is** DP-1's posture call |
| D5 | Mainline-first: a carry needs "no mainline route existed" | §1 row 5 | **DP-1** |
| D6 | Kernel pinned to **mainline 7.2**, not 6.18 | §1 rows 6–7, §5 | *no DP* — nearest DP-5/DP-9 |
| D7 | Carry the `sdhci-cadence` 40-bit DMA-mask patch, upstreamably | §1 row 8, §1.1 | *no DP* — instance of D5 |
| D8 | Fix mainline's unbindable Agilex 5 svc node **upstream** | §3.1 note | **DP-9** |
| D9 | A vendor `svc` carry is a hardware-gated escape hatch | §1 row 9, §2.6 | **DP-9**, **DP-1** |
| D10 | The SMMU ships **disabled**; DMA isolation is a non-goal (DE10 parity) | [`de25-dts-rationale.md`](../de25-dts-rationale.md) §4 | **DP-9**, **DP-1** |
| D11 | Card layout **target** is the DE10-style two-stage layout; the plain-ext4 card stays until hardware | [`de25-sdcard.md`](../de25-sdcard.md) | **DP-3** |
| D12 | The DE25 mirrors the DE10's `linux-firmware` selection; seccomp stays off as on the DE10 | [`de25-kernel-config.md`](../de25-kernel-config.md) §7.1 | **DP-1**, 0027 **Decision 6** |

### D1 — Core loading goes through `fpga_manager` + a DT overlay

**Decision.** Fabric reconfiguration is driven by the kernel FPGA-manager/FPGA-region stack with a DT
overlay carrying `firmware-name`; U-Boot-side core loading, RSU slots and QSPI-resident cores are out.

- **Evidence.** The overlay notifier is the *only* mainline trigger — `firmware-name` is read solely
  inside `of_fpga_region_parse_ov()`, so a base-tree `fpga-region` programs nothing at boot **[V §7
  option (c)]**; DP-9's premise was confirmed by D0.2 **[V]**; RSU is out on sizing (a 256 MB
  reference layout against this board's 16 MB) **[V boot-chain §8.4]**.
- **Consequences.** The RT beta's UIO doorbell patches (0043–0045) are not ported (DP-9). The kernel
  needs `CONFIG_FPGA_BRIDGE=y` *and* `CONFIG_OF_OVERLAY=y`, which `OF_FPGA_REGION` does **not**
  select — without it the notifier is a stub and reconfiguration silently never fires **[V §3.1]**.
- **Re-open if.** The §2.6 test fails (→ D9). Scope limit: D1 forecloses U-Boot as the *core-switching*
  mechanism, not whether a boot-time phase-2 `core.rbf` ships at all — boot-chain §7 row 15 **[U]**.

### D2 — Scope is "make the hardware available"; Main_MiSTer does the loading

**Decision.** We ship kernel + DTS plumbing so an fpga-manager and an fpga-region probe and are
reachable from userspace, plus a minimal trigger; no core loader, switching worker or staging script.

- **Evidence.** Mainline exposes no writable attribute anywhere — `fpga_mgr_attrs[]` is three
  `DEVICE_ATTR_RO` entries, `fpga_region` one, `OF_CONFIGFS` does not exist **[V §7]**. So "available"
  needs some non-mainline code: a ~95-line out-of-tree GPL misc driver calling `of_overlay_fdt_apply()`.
- **Consequences.** Wave-1 releases carry no MiSTer binaries (0027 Decision 6 — a bare developer OS).
  Overlay choice, `.rbf` staging, switch sequencing and quiescing the fabric client are Main_MiSTer's.
  That module is the only carried item that fully satisfies D5 — the tension §7 names, not one hidden.
- **Re-open if.** Mainline gains a writable fpga-manager attribute or an overlay loader (delete the
  module); or an upstream framework port states a different contract — the upstream owner's call.

### D3 — Two partitions (p1 FAT, p2 the rest), and no card shared with a DE10

**Decision.** The DE25 SD card is two partitions — p1 FAT holding what the factory SPL must find, p2
everything else — and a card that works in both boards is an explicit non-goal.

- **Evidence.** The factory SPL loads `u-boot.itb` **by name from a FAT filesystem** on partition 1
  (`CONFIG_SPL_FS_FAT=y`, `SYS_MMCSD_FS_BOOT_PARTITION` default 1), and there is **no 0xA2 analogue**
  **[V boot-chain §2 step 4 and close]**.
- **Consequences.** No cross-board layout compromises; `boot-chain.md` §2's partition-order lore does
  not transfer. DP-3 (A/B slots) stays tabled on the owner's "pull the card" rationale.
- **Re-open if.** Nothing plausible for p1. p2's filesystem and kernel-on-p1-vs-p2 are **not** decided
  here — §6.3 is explicit that D3 "fixes the partition count and p1's FAT type only".

### D4 — Posture 1: nothing we ship writes the factory QSPI

**Decision.** We pin to the factory QSPI image (SDM firmware + phase-1 bitstream + embedded U-Boot
SPL) and never write it; we build `u-boot.itb` only, and our whole interface to the board's boot
firmware is one FIT file, by name, on the FAT partition.

- **Evidence.** The analogue of the DE10 "stock `uboot.img`, byte-identical" posture, **chosen
  fail-closed, not forced by impossibility** (boot-chain §9.2 corrected "close to forced"); its
  sharpest sub-risk, SPL FIT-signature enforcement, tests **negative** on the published SPL **[V
  boot-chain §4 posture 1, §7 row 6]**. The strongest guard is a defconfig line, not a habit: on a
  failed FAT env load `env_ubi_load()` calls `ubi_part()` unconditionally, and a UBI attach on a blank
  MTD **writes a layout volume into QSPI on the load path, with no `saveenv` anywhere** **[V,
  code-traced, §6.2 — promotes ledger row 12 from [U]]**.
- **Consequences.** Our U-Boot fragment carries `# CONFIG_ENV_IS_IN_UBI is not set` with the comment
  that survives editing (§6.2); our DTS omits the QSPI node or enables it read-only (boot-chain §7 row
  10); any `fw_env.config` names only the FAT `uboot.env` (row 11). Posture 2 is **bench-only** and
  never an update-channel artifact; Terasic's DDR/pinmux handoff lives inside the bitstream and is not
  ours to change **[V boot-chain §8.6]**.
- **Re-open if.** A sub-16 MB power-loss-safe RSU layout is ever *proven* (boot-chain §8.4 residual) —
  posture 2/3 becomes shippable and this must re-open rather than be treated as settled; or if D2.2
  finds the factory SPL rejects our FIT (§8.3 blocker 1 **[U]**).

### D5 — Mainline-first, strongly

**Decision.** A carried patch requires justification that **no mainline route existed** — not that it
was easier, and not that the vendor does it that way.

- **Evidence.** The route exists and is cheap: a two-string fallback compatible binds the stock
  `stratix10-svc`, `stratix10-soc` and `sdhci-cadence` drivers with zero driver patches — OF matching
  walks the whole `compatible` list and no table keys behaviour on the matched entry **[V §2.1, from
  `drivers/of/base.c:338-356` and all three tables]**.
- **Consequences.** Altera's `mmc0` (`altr,agilex5-sd6hc`/`cdns,sd6hc`) must **not** be copied —
  `cdns,sd6hc` exists nowhere in mainline; take Altera's board `.dts` as the wiring reference and
  `mmc0` in the SD4HC form **[V §4.1]**, and read vendor trees for *behaviour*, not just nodes **[V
  §4.2]**. Three node *names* are load-bearing: `svc`, its parent `firmware`, and `method = "smc"`.
- **Re-open if.** Never as a blanket rule; re-applied per item. D7, D8 and D9 are its instances.

### D6 — The kernel is pinned to mainline 7.2, not 6.18

**Decision.** The DE25 pins to mainline **7.2**, the line this repo already builds for the DE10 RT
beta (superseding the earlier, weaker "kernel version open in our favour up to and including 7.2").

- **Evidence.** The 6.18 case collapses on its own terms **[V §5.1]**: `clk-agilex5.c` lands in v6.19,
  so a 6.18 DE25 carries a whole SoC clock driver (847 vendor lines on the reference board) for what
  mainline provides one release later — the carry D5 forbids. Cost is bounded: all 40 of our patches
  applied to **Linux 7.2 final** at `-F0`, zero fuzz **[V rt-beta-kernel.md:222]** — ARM32, so
  aarch64 is **[U]** (Q8).
- **Consequences.** The DE25 inherits the RT beta's treadmill (7.2 is not LTS): `rt-clean`, TOFU-hash
  re-verification, per-version boot proof. Sharing that line keeps the repo at **two** kernel lines
  and lets one bump serve both. No version fixes reconfiguration: `grep iommu|REMAPPER|dma_addr_offset`
  in `stratix10-svc.c` is **zero hits** at 6.18.44 and v7.2 **[V]**.
- **Re-open if** (§5.3, verbatim): kernel.org designates a 7.x release longterm — pin that one; or 7.3
  ships with the `smmu` node already enabled *and* any Agilex 5 `mmc0` node.

### D7 — Carry the `sdhci-cadence` 40-bit DMA-mask patch, as an upstreamable carry

**Decision.** We carry a `sdhci-cadence` patch capping this controller's DMA mask at 40 bits, as an
*upstreamable* carry to be submitted, not a permanent fork — accepted under D5 because no mainline
route exists.

- **Evidence.** Terasic's driver gives `intel,agilex5-sd4hc` a match entry carrying
  `SDHCI_QUIRK2_40_BIT_DMA_MASK`, a quirk absent from mainline at 6.18.44, v7.2 and `master`, so
  mainline takes the `DMA_BIT_MASK(64)` branch on a controller the vendor caps; under SMMU translation
  an IOVA above the wired bits truncates — an `F_TRANSLATION` fault **[V §5.1, §8 Q2]**. **The 40-bit
  value is a hypothesis inferred from the vendor quirk, untested on hardware [U]** (§2.6 item 2).
- **Consequences.** Patch and DTS are **coupled**: `sdhci-cadence.c:656` matches `cdns,sd4hc` with no
  `.data`, so the patch adds a *new* match entry carrying data and the DTS must declare that new
  string first in `mmc0`'s list **[V §1.1]** — neither half works alone.
- **Re-open if.** §8 Q2's five-leg boot test shows no fault, or that `iommus`/`dma-coherent` presence
  is the real discriminator — then the patch is dropped.

#### D6 and D7 fix two *independent* problems — do not conflate them

They read as one fix and are not. Dropping the 7.2 pin leaves a board that does not boot from SD
(§1.1). Dropping the sdhci patch does **not** break the *shipped* wave-1 boot path: with the SMMU
disabled there are no IOVAs to truncate and all DRAM sits below 4 GiB
([`de25-dts-rationale.md`](../de25-dts-rationale.md) §4.4) — 0101 is what makes the future SMMU-on
test leg survivable, and it is carried now so that leg is a one-line DTS change.

| Problem | What fixes it | What does **not** fix it |
|---|---|---|
| `clkmgr` never probes, so every `&clkmgr` consumer (`mmc0`, gmac) defers forever | **The 7.2 pin.** `clk-agilex5.c` exists in 7.2 and matches `"intel,agilex5-clkmgr"` with real `.data` (`drivers/clk/socfpga/clk-agilex5.c:544`) **[V]**; 6.18.44 has no such file **[V]** | The sdhci patch. Entirely unrelated code path. |
| `mmc0` DMA faults through the SMMU (mainline takes the 64-bit branch; the vendor caps the controller at 40 bits) — **reachable only with the SMMU enabled**, which wave 1 does not ship | **The carried `sdhci-cadence` patch.** | The 7.2 pin. A vendor-vs-mainline driver delta, **not** a 6.18 regression — it travels forward to 6.19 and 7.2 unchanged **[V]** |

D8's one-liner is a *third* independent thing: it fixes fpga-mgr/svc **binding**, touches neither DMA
nor clocks, and is carried locally (0102) pending an owner decision on upstream submission.

### D8 — Fix mainline's unbindable Agilex 5 svc node upstream, one match-table line

**Decision.** Mainline ships an Agilex 5 `/firmware/svc` node whose `compatible` matches no driver on
any released kernel through v7.2 or `master`. We **carry the one-line match-table fix locally**
(`board/mister/de25nano/linux-patches/0102`) and keep mainline's own `intel,agilex5-svc` compatible
in the DTS, so the device tree does not misdescribe the SoC; overriding the compatible to
`intel,agilex-svc` is retained only as the documented fallback if 0102 is ever dropped. Whether and
when 0102 is submitted upstream is an owner decision (see "Decisions deliberately left open").

- **Evidence.** `stratix10_svc_drv_match` has never contained `intel,agilex5-svc` (`grep -c agilex5` →
  0 at v7.2 and `master`) **[V §3, §3.1]**. The override is schema-clean — `intel,agilex-svc` is in
  the binding's `enum` and `iommus` is top-level, so `iommus = <&smmu 10>` stays legal, while the
  two-string form fails `dtbs_check` **[V §3.1]**. Keeping the agilex5 string (with 0102) also
  satisfies the binding's `allOf`, which *requires* `iommus` for that string, without a workaround.
- **Consequences.** The fpga-mgr *child* differs: use the two-string fallback and accept a transient
  `dtbs_check` **warning** until the v6 binding lands — **correcting** [`de25-fpga-reconfig.md`](../de25-fpga-reconfig.md)
  §4.2's "free and forward-compatible" claim, true at runtime but not schema-clean **[V §2.5]**.
  Whether dropping the agilex5 string while keeping `iommus` is *functionally* equivalent is **[U]** (Q3).
- **Re-open if.** Upstream adds per-compatible `.data` to `s10_of_match` or `stratix10_svc_drv_match`
  — D5's "a fallback is free" argument then stops holding and §2.1 must be re-derived. **Watch both
  tables on every kernel bump** (§8 Q10).

### D9 — A vendor `stratix10-svc` carry is a hardware-gated escape hatch, not a plan

**Decision.** Carrying Terasic's `stratix10-svc.c` behaviour is permitted **only if** on-hardware
testing proves mainline `svc` cannot program the fabric, and only for capability critical to running
MiSTer — and the same bar applies to any vendor-kernel behaviour: it must buy a real win on something
critical, not merely be what the vendor happens to do.

- **Evidence.** The gate is §2.6's four-step test: boot the 7.2 kernel with **no behavioural svc
  patches** — 0102 (match-table only) stays applied, because without it the shipped DTS's
  `intel,agilex5-svc` node binds nothing and the test would stop at a binding failure that says
  nothing about mainline's programming path — confirm `fpga0`/`region0` probe (the binding half,
  expected to pass), then apply an overlay with `firmware-name` and watch for
  `SVC_STATUS_BUFFER_DONE` or the `RECONFIG_REQUEST` timeout. **SMMU disabled first** (the shipped
  shape); the SMMU-enabled leg is predicted to fail by source (mainline svc passes physical
  addresses, [`de25-dts-rationale.md`](../de25-dts-rationale.md) §4.1) and is run second only to
  confirm that prediction **[V §2.6, corrected]**.
- **Consequences.** **Run this test first in the D2 hardware session**; nothing else depends on it
  (clock driver, SD controller, DTS node set, U-Boot, partition layout are independent). If it fails,
  mainline-first is refuted *on the svc layer only* and the real choice graduates to its own ADR, with
  a sizing diff and a TF-A `plat/intel/soc/agilex5` read — unread here **[U]** (§8 Q1/Q5).
- **Re-open if.** The test passes — the hatch closes and D5 holds unqualified on the svc layer.

### D10 — The SMMU ships disabled; DMA isolation is a non-goal

**Decision (owner, 2026-09-02).** The board device tree leaves the Agilex 5 `arm,smmu-v3` at
`status = "disabled"`, every `iommus` reference stays in the tree but is inert, and this is the
intended configuration, not a wave-1 expedient. DMA isolation for peripherals and for the fabric
is **not a goal** of this image: the DE10-Nano's Cyclone V has no SMMU, so a core in the fabric
can already DMA anywhere in RAM on stock, and this is parity with that, not a regression. The
security value an IOMMU carries on a laptop or server does not apply to a games console whose
fabric is loaded by its owner.

- **Evidence.** Mainline `stratix10-svc` takes the SDM buffer from the `GET_MEM` SMC, keeps
  **physical** addresses in its gen_pool and hands them to the SDM raw (no `iommu_map`/`dma_map`
  anywhere in the file), while the dtsi's `iommus = <&smmu 10>` attaches the svc device to a
  translated default domain. With the SMMU on, mainline can bind the FPGA manager but the SDM's
  first read faults: **SMMU-on cannot program the fabric on a mainline kernel** — traced at 7.2.2
  and matching the one failed attempt seen on real silicon **[V, rationale §4.1]**. Terasic's
  vendor driver makes SMMU-on work with an IOVA carveout, `iommu_map()` and an SDM remapper
  bypass; mainline has none of that. SMMU-off makes the driver's assumption true.
- **Consequences.** Disabling the SMMU is what gives D1 (fpga-manager + overlay on mainline) its
  chance, so D10 is a precondition of D1, not a trade against it. The D7 patch is not
  load-bearing on the shipped path (all DRAM is below 4 GiB). The runtime equivalent for a test
  card is the kernel argument `iommu.passthrough=1` in `extlinux.conf` — the SMMU cannot be
  toggled from userspace after boot, but the hardware session can compare both shapes by editing
  a text file on the FAT partition. **SMMU-off is unproven, not disproven** (rationale U10):
  Terasic's driver refuses to run on Agilex 5 without the SMMU and always disables the SDM
  remapper, which mainline never touches; the §2.6 fabric test runs SMMU-off **first** and is
  what settles it.
- **Re-open if.** Upstream `stratix10-svc` gains IOMMU-aware buffer handling (then SMMU-on
  becomes a free choice and this decision is revisited on its merits, still with isolation as a
  non-goal by default); or the SMMU-off fabric test fails on hardware and the vendor remapper
  behaviour turns out to be required — that is D9's escape hatch, evaluated then.

### D11 — Card layout: the DE10-style two-stage layout is the target; plain ext4 until hardware

**Decision (owner, 2026-09-03).** The DE25 card will use the DE10's model: p1 FAT holding the
boot files, p2 an exFAT data partition (the `/media/fat` equivalent) holding `linux/linux.img`,
loop-mounted as the root by the embedded initramfs. Until a board is in hand the shipped card
keeps the interim shape (p2 = the ext4 root written directly, `root=/dev/mmcblk0p2`), because it
isolates the factory-SPL, DTS and SD-controller questions the first boot has to answer.

- **Evidence.** The initramfs two-stage design carries no architecture-specific line (README,
  "The initramfs that deleted a kernel patch"); mainline U-Boot reads FAT and exFAT
  (implementation-path §6.3); the factory SPL reads FAT on partition 1 only (boot-chain §8), which
  fixes p1's role either way. The rewritten in-kernel `loop=` patch also compile-verifies on
  aarch64, so both routes stay open, but the initramfs is the plan.
- **Consequences.** A new aarch64 stage-1 initramfs stack and its QEMU test path are owed before
  the switch; `genimage-sdcard.cfg`, `extlinux.conf`'s kernel arguments and the card checker
  change together. The DE25 inherits the DE10's `linux.img` update flow and downloader contract
  unchanged. This closes §8 Q7 of the implementation path.
- **Re-open if.** The first hardware boot shows U-Boot cannot read the FAT boot files reliably,
  or Main_MiSTer's DE25 port needs a layout the loop root cannot provide.

### D12 — Firmware parity with the DE10; seccomp stays off

**Decision (owner, 2026-09-03).** The DE25 image ships the DE10's `linux-firmware` selection
(the 29 `BR2_PACKAGE_LINUX_FIRMWARE_*` choices plus `linux-firmware-extra`), so a dongle that
works on a DE10 works on a DE25. The mechanism is a shared `image-common` fragment included by
both boards' image stacks and never by the kernel-only stack (rule 4 of
[`buildroot-config.md`](../buildroot-config.md) §10). `CONFIG_SECCOMP` stays off, exactly as on
the DE10; the obligation that travels with it — `BR2_PACKAGE_OPENSSH_SANDBOX` must be off when
openssh joins the image — is accepted, not argued.

- **Evidence.** The shared kernel fragment (`board/mister/common/linux-mister.fragment`) already
  builds every Wi-Fi/Bluetooth driver the DE10 has; without the blobs they bind and fail at
  `request_firmware()` ([`de25-kernel-config.md`](../de25-kernel-config.md) §7.1). Cost measured
  on the DE10: ~52 MB installed.
- **Consequences.** This is the first shared *package* content between the boards and the
  natural home for more as the DE25 grows out of the bare developer OS (ADR 0027 Decision 6 is
  refined, not reversed: still no MiSTer binaries). The DE25 rootfs size follows the measurement.
- **Re-open if.** The DE25 ever ships a Wi-Fi/Bluetooth driver set that differs from the DE10's.

## Decisions deliberately left open

None of these is decided here. Each is named so it is not mistaken for settled.

1. ~~**p2's filesystem, and therefore whether the kernel lives on p1 or p2**~~ **Decided 2026-09-03 — D11** (two-stage target, plain ext4 interim). Original text kept for the record: (§8 Q7, §6.3). D3 fixes the
   partition count and p1's FAT type only; mainline U-Boot now reads exFAT (`CONFIG_FS_EXFAT`) **[V]**,
   so this is a project decision, not a capability gap.
2. **Whether the DE10 and DE25 defconfigs are refactored into a shared base + per-board fragments.**
   The owner's goal is maximal reuse, and the readiness ledger finds most machinery board-agnostic.
   Wave 1 nevertheless introduces `configs/mister_de25nano_defconfig` **standalone, on purpose**:
   refactoring the DE10 defconfig while bringing up an unbooted board couples two risks and puts DE10
   regressions on the DE25's critical path. **Interim, not the end state** — the shared-base refactor
   is a future ADR, taken once a DE25 has booted and the overlap is measured rather than predicted.
   *Addendum 2026-09-02:* the owner took the refactor early, on the condition that the DE10 build be
   provably unchanged: all three defconfigs became fragment stacks under `configs/fragments/`
   (`docs/buildroot-config.md`; the measured overlap is the seven-symbol `common.fragment`, §10
   there — the DE25 stack shares nothing else with the DE10 and still carries no DE10 package).
   The DE10's resolved `.config`, `savedefconfig` and CI cache keys were shown byte-identical
   before the monoliths were deleted (§11 there). Not an ADR of its own: no decision recorded
   here changed.
3. **The U-Boot / TF-A version pairing.** Mainline U-Boot **v2026.07** + TF-A **v2.15.0** is the
   recommendation, but the pairing is **unblessed and untested by us [U]** — the vendors document only
   forks and no DE25-Nano board exists in mainline U-Boot, so we carry the fragment ourselves **[V
   §6]**. Settled by D2.2 (§8 Q5) and a desk build (§8 Q6, `# CONFIG_SPL is not set`).
4. **Whether either patch is submitted upstream.** D7 and D8 are both *intended* as upstream
   contributions, and that intent is part of their justification. **Owner approval is required before
   any mailing-list post** — nothing goes to `linux-fpga`, `linux-mmc` or any list without it.

Still tabled from ADR 0027 and untouched here: DP-2, DP-3, DP-6, DP-7, DP-8, DP-10. Also open:
boot-chain §7 row 15 — whether a phase-2 `core.rbf` from our own Quartus compilation may be paired
with the factory phase-1 **[U]**.

## Relationship to the DE10 build

**The invariant: nothing here changes DE10 behaviour.** Every decision is scoped to a board that does
not yet build in this repo. The DE10 keeps its 6.18 pin, its `zImage_dtb` concatenation contract, its
0xA2 layout, its stock-`uboot.img` byte-identity and its release namespace; D6's 7.2 pin reuses the
*RT variant's* existing line and does not move the DE10 stable pin.

**The parity-with-stock methodology is unchanged.** DE10 work continues to shadow a stock image and be
judged against it ([`abi-contract.md`](../abi-contract.md), [`stock-reconciliation.md`](../stock-reconciliation.md),
the parity dossiers). It does not transfer and is not weakened: per DP-1 there **is no stock to
shadow** on the DE25 — whatever ships first *is* the reference — which is why the DE25 gets D5 where
the DE10 gets bug-for-bug fidelity. Two standards, each correct for its board.

## Alternatives rejected

**Amend ADR 0027 in place.** 0027 deliberately took no technical position; amending it would blur what
was known on 2026-08-19 against what D0 found. A separate dated ADR keeps that auditable.

**Wait for hardware before recording any of it.** The decisions are already taken and already
foreclosing options in the task list. Recording them does not make them verified — each says its [U].

**Record only the hardware-independent ones** (D3, D5, D6, D8) — which drops exactly the four carrying
the most risk. An ADR that records only the safe calls is not a decision record.

## Consequences

- Nothing builds or ships on acceptance. The first code this authorises is a DE25 defconfig and board
  directory that no CI lane runs per-PR (ADR 0027 Decision 5).
- Four obligations land on whoever opens D2: run §2.6's test **first**; add the
  `OF_OVERLAY`/`FPGA_BRIDGE` sentinels to the per-board defconfig check; add the two match-table
  watches to the kernel-bump checklist (§8 Q10); and write `# CONFIG_ENV_IS_IN_UBI is not set` into
  the U-Boot fragment before any board is powered with our FIT on the card.
- Two `patch-provenance.md` rows are owed (D7's carry, D8's upstream fix) before either lands, and
  boot-chain §10's request that "the DP-1 ADR must record posture 1 as chosen fail-closed, with a
  proven sub-16 MB RSU layout as its explicit revisit trigger" is discharged by D4.
- If the §2.6 test fails, D9 opens a successor ADR; D1–D8 stand regardless of its outcome.
