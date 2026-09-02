# DE25-Nano implementation path — the mainline-first route to a bootable, reconfigurable board

**Status:** desk analysis, **2026-08-22**, **no hardware touched**. This document synthesises four
investigation legs (open-source DTS survey, the no-carried-patch question, kernel-version choice,
U-Boot build shape), then re-verifies every load-bearing claim against source, and then applies an
adversarial verification pass over both the legs and the synthesis. Where the legs disagreed, §9
records the disagreement and how it was settled; §10 records exactly what was checked, what changed
under challenge, and what nobody has verified. Claims are tagged **[V]** (read from a named source)
/ **[U]** (unverified, with the missing input named).

Cross-refs: [`de25-boot-chain.md`](de25-boot-chain.md) §5, §7, §8.3, §8.5;
[`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §3.1, §4.1, §4.2;
[`de25-patch-portability.md`](de25-patch-portability.md);
[`de25-readiness-ledger.md`](de25-readiness-ledger.md) §5.4;
[`de25-reference-implementation.md`](de25-reference-implementation.md) (salvaged; its §7 verification
record now records which of its claims survived this pass); [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md).

---

## 0. The two findings that change the plan

> **Finding 1 — a 6.18 base costs a whole SoC clock driver.**
> `drivers/clk/socfpga/clk-agilex5.c` **does not exist in 6.18** and lands in **v6.19**, where the
> file is exactly **561 lines** **[V, fetched from `torvalds/linux@v6.19` this pass; `wc -l` = 561;
> matches `intel,agilex5-clkmgr` at `:544`]**. Mainline 6.18.44 ships the `intel,agilex5-clkmgr`
> *binding*, the *clock-ID header*, and the *DT node* — but no driver **[V]**. On a 6.18 base every
> peripheral whose `clocks =` phandle points at `&clkmgr` — `mmc0` and all three `gmac`s included —
> defers forever. A 6.18-based DE25 therefore requires a carried clock-driver backport before it can
> boot from SD at all. No leg caught this; it inverts the kernel recommendation. See §5.

> **Finding 2 — "no carried patch" is true about *binding*, and unproven about *programming*.**
> A DT fallback compatible does bind mainline's stock `stratix10-svc` and `stratix10-soc` drivers on
> Agilex 5, with zero driver patches — that is settled from the OF core and both match tables **[V]**.
> But **binding is not programming.** Terasic's vendor 6.12.11 `stratix10-svc.c` keys *real,
> Agilex-5-specific behaviour* off the `intel,agilex5-svc` string that mainline has never had: it
> attaches the svc device to the SMMU, builds an IOVA carveout, adds
> `AGILEX5_SDM_DMA_ADDR_OFFSET 0x80000000` to every buffer address handed to the SDM, and issues
> `INTEL_SIP_SMC_SDM_REMAPPER_CONFIG` to *bypass the SDM remapper* — and it hard-fails `-ENODEV` if
> the SMMU is absent **[V, fetched and read this pass: `terasic/linux-socfpga@de25-nano-6.12.11-lts:
> drivers/firmware/stratix10-svc.c:59,63-64,3244,3443,3504-3556`]**. Mainline `stratix10-svc.c`
> contains none of it — it hands the SDM raw `gen_pool` physical addresses and knows nothing about
> an IOMMU or a remapper, at 6.18.44 **and** at v7.2 (`grep` for `iommu|REMAPPER|dma_addr_offset` →
> **zero hits** in both) **[V]**. The one time anyone drove a mainline-path reconfiguration on real
> Agilex 5 silicon, it reached `fpga_manager fpga0: writing … to Stratix10 SOC FPGA Manager` and then
> **timed out waiting for `RECONFIG_REQUEST` and wedged the board**
> **[V `de25-reference-implementation.md:115`]**. That is exactly the failure shape the vendor code
> predicts. Confidence in end-to-end reconfiguration via stock mainline drivers is therefore **low**,
> not medium, and §2.6 names the on-hardware test that settles it.

Neither finding changes a decision. Finding 1 changes the kernel pin. Finding 2 changes what we
claim, what confidence we attach, and what the first hardware session must measure.

---

## Sources

All retrieved or read **2026-08-22** unless stated.

- Local kernel tree `output/build/linux-6.18.44` — cited as `linux:path:line`.
- Mainline Linux at tags `v6.18`, `v6.19`, `v7.0`, `v7.1`, `v7.2` and at `master` (post-7.2, → 7.3),
  via `raw.githubusercontent.com/torvalds/linux/<ref>/…` — cited as `mainline@<ref>:path`.
- Read-only reference fork `/mnt/source/de25-linux` (Linux 6.18.38, the friend's working board) —
  cited as `de25-linux:path`. **Read only; never executed, modified, or checked out.**
- `github.com/altera-fpga/linux-socfpga` branch `socfpga-6.18.20-lts` (the org formerly
  `altera-opensource`), and `github.com/terasic/linux-socfpga` branch `de25-nano-6.12.11-lts`.
- Mainline U-Boot at tag `v2026.07`; mainline TF-A at tag `v2.15.0`.
- LKML, both retrieved and read this pass:
  - Khairul Anuar Romli, **“[PATCH v6 1/2] dt-bindings: fpga: stratix10: add support for Agilex5”**,
    `lkml.iu.edu/2511.2/10025.html`, dated **2025-11-18** **[V]**.
  - Khairul Anuar Romli, **“[PATCH v2 2/2] arm64: dts: agilex5: add fpga-region and fpga-mgr nodes”**,
    `lkml.iu.edu/2511.1/07883.html`, dated **2025-11-12** **[V]**. Note the version labels: the
    archive copy of the DTS companion we can reach is the **v2** revision, not v6. An earlier draft
    of this document called both “v6”; corrected. The v6 respin of 2/2 is presumably on lore, which
    was bot-walled this pass — its *content* is **[U]**, its *effect* is verified against tree content
    instead (§2.5).

---

## 1. Decisions taken

These are settled. The rest of this document works inside them and does not re-open them.

| # | Decision | What it forecloses |
|---|---|---|
| 1 | **Core loading uses `fpga_manager` + DT overlay.** | U-Boot-side core loading, RSU slots, QSPI-resident cores — all rejected. |
| 2 | **Scope is "make the hardware available". Main_MiSTer does the loading.** | We ship kernel + DTS plumbing so an fpga-manager and an fpga-region probe and are reachable. We do **not** build a core loader, switching worker, or staging script. |
| 3 | **Two partitions: p1 FAT, p2 everything else.** | Forced by the factory SPL (`CONFIG_SPL_FS_FAT=y`, `SYS_MMCSD_FS_BOOT_PARTITION=1`). Part of the DE25 Buildroot output. |
| 4 | **No shared SD card between DE10 and DE25.** | Explicit non-goal. No cross-board layout compromises. |
| 5 | **Mainline-first, strongly.** | A carried patch requires justification that **no mainline route existed** — not that it was easier. |
| 6 | **Kernel version open in our favour**, up to and including 7.2. | The DE25 is not pinned to the DE10's 6.18. |
| 7 | **Kernel pinned to mainline 7.2 for the DE25** (2026-08-22). | Supersedes decision 6's openness. 6.18 is out; see §5.1. |
| 8 | **We carry the `sdhci-cadence` 40-bit DMA-mask patch** (2026-08-22), as an *upstreamable* carry to be submitted, not a permanent fork. | Accepted as a carried patch under decision 5 because no mainline route exists — see the coupling note below. |
| 9 | **Vendor patches are a last resort** (2026-08-22). A Terasic `stratix10-svc.c` carry is permitted **only if** on-hardware testing proves mainline `svc` cannot program the fabric (§2.6), and only for capability critical to running MiSTer. The same bar applies to any vendor-kernel behaviour: it must buy a real win on something critical, not merely be what the vendor happens to do. | Vendor-tree divergence adopted wholesale; "the vendor does it this way" as a justification. |

Decision 2 carries an honest tension that this document does not paper over: *"hardware available"
still needs some userspace entry point, and mainline provides none.* §7 answers it.

### 1.1 Decisions 7 and 8 fix two *independent* problems — do not conflate them

They are easy to read as one fix and they are not. Dropping either one leaves a board that does
not boot from SD.

| Problem | What fixes it | What does **not** fix it |
|---|---|---|
| `clkmgr` never probes, so every `&clkmgr` consumer (`mmc0`, gmac) defers forever | **The 7.2 pin.** `clk-agilex5.c` exists in 7.2 and matches `"intel,agilex5-clkmgr"` with real `.data` (`drivers/clk/socfpga/clk-agilex5.c:544`, verified in the local 7.2 tree 2026-08-22) **[V]**. 6.18.44 has no such file; its `clk-agilex.c:546` matches only `"intel,agilex-clkmgr"` while the DTS declares `"intel,agilex5-clkmgr"` **[V]** | The sdhci patch. Entirely unrelated code path. |
| `mmc0` DMA faults through the SMMU (mainline takes the 64-bit branch; Terasic's vendor tree caps the controller at 40 bits) | **The carried `sdhci-cadence` patch.** | The 7.2 pin. This is a vendor-vs-mainline driver delta, **not** a 6.18 regression — it travels forward to 6.19 and 7.2 unchanged. Verified: `sdhci-cadence.c` in the local 7.2 tree has no DMA-mask quirk of any kind **[V]** |

**Coupling note for whoever implements decision 8.** `sdhci-cadence.c:656` matches
`{ .compatible = "cdns,sd4hc" }` with **no `.data`** (verified in 7.2) — so a 40-bit mask cannot be
hung off the existing entry. The patch must add a *new* match entry carrying data (the file already
uses `.quirks2` on its per-variant data structs, e.g. `:485`, `:499`), which means **the DTS must
declare that new compatible string first in `mmc0`'s list**. Patch and DTS are coupled; neither
works alone. The 40-bit value itself is a **hypothesis inferred from the vendor quirk and is
untested on hardware** — it is the second item on §2.6's bring-up test list, not an established fix.

---

## 2. The mainline-first question — can we do this with DTS only?

**Headline, stated at the precision the evidence supports:**

- **Binding: yes, DTS-only, zero driver patches, on a 6.19-or-newer base [V].** A two-string
  fallback compatible binds the stock `stratix10-svc`, `stratix10-soc` and `sdhci-cadence` drivers.
  The friend's driver commit `d1878a320` was avoidable and must not be copied.
- **Programming: not established, and one observed on-hardware failure argues against it [V].**
  See §2.6. This is the single largest risk in the DE25 plan and it is a hardware question.
- **The only carried patch a 6.18 base would force is not the fpga-mgr patch at all — it is the
  clock driver [V].** Moving to ≥6.19 removes it (§5).

### 2.1 Why a fallback compatible is sufficient to bind — mechanism, read from source

The drivers we need are pure match-on-string drivers with **no per-compatible data and no branch on
which string matched**:

| Driver | Match table | `.data`? | Branches on matched string? |
|---|---|---|---|
| `stratix10-svc` | `intel,stratix10-svc`, `intel,agilex-svc` | none | no |
| `stratix10-soc` (fpga-mgr) | `intel,stratix10-soc-fpga-mgr`, `intel,agilex-soc-fpga-mgr` | none | no |
| `sdhci-cadence` | three vendor entries with `.data`, then a **bare** `cdns,sd4hc` | none on the bare entry | no |

**[V** at 6.18.44: `linux:drivers/firmware/stratix10-svc.c:1133-1137` (file is 1334 lines),
`linux:drivers/fpga/stratix10-soc.c:448-452`, `linux:drivers/mmc/host/sdhci-cadence.c:643-658`;
`grep` of both stratix10 files for `of_device_get_match_data` / `of_device_is_compatible` /
`match->data` → **no hits**. **[V** at v7.2, both files fetched in full this pass: tables
byte-identical in content, at `mainline@v7.2:drivers/firmware/stratix10-svc.c:1911-1915` (that file
has grown to 2113 lines, mostly FCS command plumbing) and
`mainline@v7.2:drivers/fpga/stratix10-soc.c:448-452`; `grep -c agilex5` → **0** in both.**]**

OF matching walks the node's **entire** `compatible` list. `__of_device_is_compatible()` iterates
every string, and a hit at index *i* returns `score = INT_MAX/2 - (i << 2)`
**[V `linux:drivers/of/base.c:338-356`]**; `__of_match_node()` accepts any `score > 0`, keeping the
highest **[V `linux:drivers/of/base.c:1073-1091`]**. Position therefore affects only *which table
entry wins among several* — never match-versus-no-match. Because neither driver keys behaviour on
the matched entry, **a fallback match is functionally identical to an exact match**. So:

```dts
compatible = "intel,agilex5-soc-fpga-mgr", "intel,agilex-soc-fpga-mgr";
```

binds the **stock, unmodified** `stratix10-soc` driver.

`sdhci-cadence` is the same shape with one extra safeguard worth naming: `sdhci_cdns_probe()` calls
`of_device_get_match_data()` and, on `NULL`, explicitly falls back to `&sdhci_cdns_drv_data`
**[V `linux:drivers/mmc/host/sdhci-cadence.c:561-563`]** — so the bare `cdns,sd4hc` entry's absent
`.data` is a supported, exercised path, not an accident.

**Three hard structural constraints come with this shape.** All three are node *names* or plain
properties, not compatibles, so they are easy to lose when authoring by hand:

1. `s10_init()` does `of_find_node_by_name(NULL, "svc")` and then
   `of_platform_populate(fw_np, s10_of_match, …)` **[V `linux:drivers/fpga/stratix10-soc.c:471-484`]**.
   **The fpga-mgr's parent node must literally be named `svc`.** The child's node name is free.
2. `stratix10_svc_init()` does `of_find_node_by_name(NULL, "firmware")`
   **[V `linux:drivers/firmware/stratix10-svc.c:1307`]**. **The grandparent must literally be named
   `firmware`.**
3. `get_invoke_func()` fails probe with `-ENXIO` unless the svc node carries
   `method = "smc"` or `"hvc"` **[V `linux:drivers/firmware/stratix10-svc.c:865-885`]**.

Mainline's own Agilex 5 shape satisfies all three (`firmware { svc { method = "smc"; … } }`,
`mainline@v7.2:arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi`) **[V]**, as does the friend's
(`de25-linux:…/socfpga_agilex5.dtsi:213-218`) **[V]**. On a 6.18 base, where we would author the
whole subtree, they must be met deliberately.

### 2.2 The independent empirical check — what it proves, and what it does not

The friend's board boots from SD on real DE25 silicon. His `drivers/mmc/host/sdhci-cadence.c` is
**byte-identical to stock 6.18.44** (`diff -q` → identical, re-run this pass) **[V]**, and his
`mmc0` declares `compatible = "intel,agilex5-sd4hc", "cdns,sd4hc"`
**[V `de25-linux:arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi:387`]**. That is the fallback idiom,
matching on the bare `cdns,sd4hc` entry, working on **real Agilex 5 hardware, with an unpatched
mainline driver**.

**The necessary qualifier, added under challenge:** that boot runs with `sdhci.debug_quirks=0x60`
baked into the production `boot.scr.uimg` bootargs, which forces SDHCI into **PIO** instead of ADMA
**[V `de25-reference-implementation.md` §3, commit `716559020`]**. So the empirical check proves
**binding, probe and PIO operation through a fallback compatible on real silicon**. It does **not**
prove the DMA path. §8 Q2 is where that lives, and §5.1 no longer treats it as a settled non-issue.

Note in passing that his board `.dts` sets nine `cdns,phy-use-*` / `cdns,phy-io-mask-*` /
`cdns,phy-sync-method` properties **[V `de25-linux:…/socfpga_agilex5_de25_nano.dts:127-135`]** that
the stock driver's property table **does not parse** — it knows only eleven
`cdns,phy-input-delay-*` / `cdns,phy-dll-delay-*` names **[V `linux:drivers/mmc/host/sdhci-cadence.c:108-118`]**.
Those are **dead devicetree on a mainline driver**; do not transcribe them. Their inertness also
means his working SD path runs on the stock driver's **default** PHY configuration, which is what we
would inherit.

**A correction to an earlier draft of this section:** `altr,smmu_enable_quirk` was described as dead
devicetree on the same footing. That is true **only** of the friend's mainline-based tree
(`grep -rn smmu_enable_quirk /mnt/source/de25-linux/drivers/` → no hits) **[V]**. In Terasic's vendor
tree the property is **live and load-bearing**: `stratix10-svc.c:3508` reads it, and without it the
agilex5-svc probe path returns `-ENODEV` **[V, fetched this pass]**. It is mainline-inert, not
meaningless — and the fact that a vendor driver gates SDM DMA setup on it is evidence for §2.6, not
against it.

### 2.3 What the friend actually carries, counted

Diffing `/mnt/source/de25-linux` (6.18.38) against `linux-6.18.44`, filtering 6.18.38→.44 stable
churn **[V]**:

| Carried change | Size | Avoidable? |
|---|---|---|
| `+{.compatible = "intel,agilex5-soc-fpga-mgr"},` in `s10_of_match` (`de25-linux:drivers/fpga/stratix10-soc.c:451`) | 1 line | **Yes** — declare the fallback in DT instead |
| `+{.compatible = "intel,agilex5-svc"},` in `stratix10_svc_drv_match` (`de25-linux:drivers/firmware/stratix10-svc.c:1134`) | 1 line | **Yes** — same |
| `drivers/clk/socfpga/clk-agilex5.c` + `Makefile:6` | **847 lines** (his vendor backport; the mainline v6.19 file is 561) | **Yes, by moving to ≥6.19** (§5) |
| `drivers/misc/de25_fpga_trigger.c` | 95 lines | **No** — see §7 |

**[V** all four, `wc -l` and `grep` this pass.**]**

He needed the two match-table lines only because his DT declares `intel,agilex5-svc` and
`intel,agilex5-soc-fpga-mgr` **with no fallback string**
**[V `de25-linux:…/socfpga_agilex5.dtsi:215,224`]**. That is a DT authoring choice, not a kernel
constraint. `of-fpga-region.c` and `fpga-mgr.c` are untouched in his tree **[V `diff`]** — he added
no writable attribute; the trigger is the separate module.

### 2.4 What would falsify the "binds and works" reading

1. **An `fpga-mgr` node carrying only the fallback string fails to bind, or `s10_probe()` errors on
   real Agilex 5 silicon.** Low risk — §2.1's mechanism is read from the OF core, and §2.2 shows the
   idiom working on this silicon for a different driver.
2. **The fpga-mgr binds and then cannot program.** **This is no longer hypothetical.** Terasic's
   vendor svc driver does Agilex-5-specific SDM plumbing that mainline lacks entirely (§0 Finding 2),
   Khairul's own changelog rationale for wanting an Agilex 5 compatible is that Agilex 5 "changes how
   reserved memory is mapped and accessed" **[U, rationale text only]** — and the one mainline-path
   attempt on hardware failed at the SDM mailbox **[V]**. See §2.6.
3. **Upstream adds per-compatible `.data` to `s10_of_match` or `stratix10_svc_drv_match`.** The
   moment either table keys behaviour on the string, the fallback becomes correct-but-degraded and
   this section must be re-derived. **Watch those two tables on every kernel bump** — and watch
   specifically for upstream adopting the vendor's remapper/SMMU/DMA-offset behaviour, which is the
   *realised* form of this falsifier sitting in a shipping vendor tree today.

### 2.5 The `dtbs_check` wrinkle — a correction owed

Khairul's v6 binding patch, which restructures the fpga-mgr `compatible` from a flat `enum` into a
`oneOf` blessing the two-string fallback **[V, patch body read at `lkml.iu.edu/2511.2/10025.html`]**,
**has not landed anywhere upstream** — not in v7.2, not at `master`
**[V `mainline@v7.2` and `mainline@master:Documentation/devicetree/bindings/fpga/intel,stratix10-soc-fpga-mgr.yaml`,
both still a plain two-value `enum`]**. Consequently:

| `fpga-mgr` compatible form | Binds stock driver? | `dtbs_check` today | Forward-safe? |
|---|---|---|---|
| `"intel,agilex5-soc-fpga-mgr"` alone | **no** | fails (not in enum) | only after a driver patch |
| `"intel,agilex5-soc-fpga-mgr", "intel,agilex-soc-fpga-mgr"` | **yes** | **warns** (enum, not `items`) | yes — clean once v6 lands |
| `"intel,agilex-soc-fpga-mgr"` alone | **yes** | clean | loses SoC identity if `.data` is ever added |

**Recommendation: use the two-string form and accept a transient `dtbs_check` warning**, tracked as
a known-warning entry that disappears when the v6 binding lands. This **corrects**
[`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2, which states that "writing the two-string
form now is free and forward-compatible" — it is free *at runtime*, but it is **not** schema-clean
today, and that document's own note assumed the binding patch had landed.

### 2.6 The real evidentiary position on "no carried patch", and the test that settles it

State it plainly, because it is the difference between a plan and a hope:

| Question | Status | Evidence |
|---|---|---|
| Does a fallback compatible make `/sys/class/fpga_manager/fpga0` and `/sys/class/fpga_region/region0` appear, with stock drivers? | **Very likely yes** | OF core mechanism [V]; same idiom proven on this silicon for `sdhci-cadence` [V]; friend's board reaches probe with only string additions [V] |
| Does mainline's `stratix10-svc` actually **program an Agilex 5 fabric**? | **Not established. One observed failure.** | Mainline svc hands the SDM raw `gen_pool` physical addresses with no IOMMU mapping and no offset (`linux:drivers/firmware/stratix10-svc.c:277,458,785-807,1007`) [V]. Terasic's vendor svc adds `+0x80000000`, attaches an IOMMU domain, and *disables the SDM remapper* for `intel,agilex5-svc` [V]. Mainline has none of this at 6.18.44 or v7.2 [V]. The single mainline-path attempt on hardware timed out on `RECONFIG_REQUEST` and wedged the board [V] |

**Confidence: high on binding; low on end-to-end reconfiguration through stock mainline drivers.**
The friend's board is **not** evidence that mainline svc can program this fabric — his own working
reconfigurations ran on Terasic's vendor 6.12.11 kernel, which has all of the above.

**The on-hardware test that settles it, and it is cheap:**

1. Boot a DE25 on a ≥6.19 mainline kernel with **no driver patches at all** and a DT carrying
   `firmware { svc { compatible = "intel,agilex-svc"; method = "smc"; memory-region = <&service_reserved>;
   iommus = <&smmu 10>; fpga-mgr { compatible = "intel,agilex5-soc-fpga-mgr","intel,agilex-soc-fpga-mgr"; }; }; }`
   plus a root `fpga-region`.
2. Confirm `fpga0` and `region0` appear and `dmesg` shows `of-fpga-region fpga-region: FPGA Region probed`.
   *(This is the binding half. Expected to pass.)*
3. Apply an overlay with `firmware-name` pointing at a small `.rbf` and watch for either
   `SVC_STATUS_BUFFER_DONE` progress and config-complete, or the `RECONFIG_REQUEST` timeout.
   *(This is the programming half. This is the actual experiment.)*
4. **Run step 3 twice: once with the `smmu` node disabled and once enabled.** The vendor code's
   structure — remapper bypass only when the SMMU is on — makes SMMU state the most likely
   discriminator, and it is a one-line DT change.

**If step 3 fails**, the mainline-first posture on the *svc layer* is refuted for Agilex 5 and we
have a real decision to take: carry a port of the vendor's agilex5 svc behaviour (a substantial
patch, not a one-liner), or drive reconfiguration some other way. Nothing else in this document
depends on that outcome — the clock driver, the SD controller, the DTS node set, U-Boot and the
partition layout are all independent of it. **Do this test first in the D2 hardware session.**

---

## 3. Minimal DTS node set

What mainline gives us, by base. `6.18.44` is the local tree; `v7.2` is the current release;
`master` is post-7.2 (→ 7.3, ~Oct 2026 by cadence).

| Node | 6.18.44 | v7.2 | master | What we author |
|---|---|---|---|---|
| `clkmgr` **driver** | **absent** (binding + header + DT node present, **no driver**) | present (since v6.19) | present | nothing on ≥6.19; **carried backport** on 6.18 |
| `/firmware/svc` | absent | present, `compatible = "intel,agilex5-svc"` — **binds nothing** | same | 6.18: whole node. 7.x: **override `compatible` to `"intel,agilex-svc"`** |
| `fpga-mgr` | absent | absent | absent | **author on every base** |
| `fpga-region` | absent | absent | absent | **author on every base** |
| `smmu` (`arm,smmu-v3`) | absent | present, `status = "disabled"` | present, **enabled** | 6.18: whole node. v7.2: `status = "okay"` |
| `mmc0` | **absent** | **absent** | **absent** | **author on every base** — this is the SD-boot gate |
| `gmac0..2` | present, real per-compatible `.data` | present (+`iommus`/`dma-coherent` since v7.0) | present | board-level `status`/`phy-mode`/`phy-handle` only |

**[V** 6.18.44 rows by `grep` over `linux:arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi` (826 lines;
case-insensitive `mmc|sd4hc|sdhci|smmu|iommu` → **zero hits**, re-run this pass; `service_reserved`
svcbuffer at `:23`, `clkmgr` node at `:144-148`, QSPI at `:477`, three stmmac compatibles at
`:491,:603,:715`); clock-ID header at `linux:include/dt-bindings/clock/intel,agilex5-clkmgr.h`; and
**no** file under `linux:drivers/clk/socfpga/` naming agilex5 (`ls`, this pass). v7.2 and master
fetched in full and grepped; `clk-agilex5.c` first appears at tag `v6.19` (commit `2050b57ecda0`,
Ang Tien Sung / Khairul Anuar Romli, Altera; via Dinh Nguyen), **561 lines**, matching
`intel,agilex5-clkmgr` at `:544`.**]**

### 3.1 The nodes, as authored (on a 7.x base)

```dts
/* mainline 7.x ships /firmware/svc with a compatible that binds no driver.
   Override it; keep iommus (a top-level property in the binding, legal for any
   compatible) and add the fpga-mgr child the svc binding already blesses.
   The node NAMES 'firmware' and 'svc' and the 'method' property are all
   load-bearing — see §2.1. */
&{/firmware/svc} {
	compatible = "intel,agilex-svc";        /* [V] binds; schema-clean */
	/* method = "smc" and memory-region inherited from mainline's node */

	fpga_mgr: fpga-mgr {
		compatible = "intel,agilex5-soc-fpga-mgr",
			     "intel,agilex-soc-fpga-mgr";   /* [V] binds on the fallback */
	};
};

/ {
	base_fpga_region: fpga-region {
		compatible = "fpga-region";
		#address-cells = <0x2>;
		#size-cells = <0x2>;
		fpga-mgr = <&fpga_mgr>;
	};
};

&smmu {
	status = "okay";                        /* needed at v7.2; already on at master */
};

/* mmc0 is absent from EVERY mainline base and must be authored in full.
   The sd4hc form binds stock sdhci-cadence through the bare cdns,sd4hc entry.
   Whether it carries iommus/dma-coherent is an open experiment — §8 Q2. */
```

**Notes that are load-bearing, not stylistic.**

- The svc override to the gen1 string is schema-clean: `intel,agilex-svc` is in the binding's
  `enum`, and `iommus` is declared as a plain top-level property, so keeping `iommus = <&smmu 10>`
  is legal **[V `mainline@v7.2:Documentation/devicetree/bindings/firmware/intel,stratix10-svc.yaml`
  — `enum` includes all three strings, `iommus: maxItems: 1` top-level, `additionalProperties: false`,
  and an `allOf` that *requires* `iommus` when the compatible contains `intel,agilex5-svc`]**. The
  two-string form `"intel,agilex5-svc","intel,agilex-svc"` would bind but **fails** `dtbs_check`,
  because the svc binding is a plain `enum`, not the `items` form. **Whether dropping the agilex5
  string while keeping `iommus` is functionally equivalent is [U]** — and §0 Finding 2 sharpens why
  it may not be: the vendor driver treats the agilex5 string as the switch that turns on IOMMU
  attach, IOVA carveout and remapper bypass. Mainline does none of that under *either* string, so
  the override is safe *relative to mainline* — but if we ever port vendor behaviour, the string
  becomes semantic. See §8 Q3.
- **Mainline 7.x has a real bug here worth a one-line patch upstream:** it ships an Agilex 5 svc DT
  node whose compatible matches no driver on any released kernel through v7.2 or at `master` **[V]**.
  The fix is one match-table line. Sending it to `linux-fpga` is cheap, is squarely within decision 5,
  and would remove our override entirely.
- No `fpga-bridges` property and **no bridge nodes at all**. The Cyclone V shape has no Agilex
  analogue and must not be transliterated — see [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2.
- `CONFIG_FPGA_BRIDGE=y` is still required, because `FPGA_REGION depends on FPGA_BRIDGE` and
  `OF_FPGA_REGION depends on OF && FPGA_REGION` **[V `linux:drivers/fpga/Kconfig:145-158`]**, even
  though no bridge driver is used. And `CONFIG_OF_OVERLAY` is **not** selected by `OF_FPGA_REGION` —
  with it off, the notifier registration is a stub and reconfiguration silently never fires. That
  trap is already documented at [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.1 and belongs in
  the per-board sentinel set in `scripts/check-kernel-defconfig-sync.sh`.

---

## 4. Prior art — a complete DE25-Nano DTS already exists, twice

**Do not author the board file from scratch.** Two open-source trees carry a full
`socfpga_agilex5_de25_nano.dts`, and the more current one is vendor-authored:

| Tree | Branch / HEAD | Kernel | What it carries |
|---|---|---|---|
| `github.com/terasic/linux-socfpga` | `de25-nano-6.12.11-lts`, `d7d192a9dd`, 2025-06-27 | 6.12.11 | 207-line board `.dts` + 1255-line `.dtsi`; `mmc0` = `"intel,agilex5-sd4hc","cdns,sd4hc"`, `smmu`, `svc`/`fpga_mgr`/`fpga-region` all wired |
| **`github.com/altera-fpga/linux-socfpga`** (formerly `altera-opensource`) | **`socfpga-6.18.20-lts`** (default branch), pushed 2026-08-11 | 6.18.20 | 206-line board `.dts` + 1274-line `.dtsi`; upstream-style cleanup of Terasic's file; `svc`/`fpga_mgr`/`fpga-region` at `:82-96,:188-193`; `smmu` enabled from the board file |

**[V** both files fetched in full; Altera dtsi `firmware/svc` at `:82-96` with `fpga_mgr` child at
`:92-95`, root `fpga-region` at `:188-193`, `mmc0` at `:356-362`.**]**

That Altera itself has taken the DE25-Nano board file in-house — on its **current default branch**,
pushed eleven days before this retrieval — is the most useful thing this survey found. It makes the
following unnecessary: authoring the board `.dts` from first principles; guessing pinmux, PHY
wiring, regulator GPIOs, QSPI partition layout, or the `temp_volt` hwmon channel map; and treating
the friend's back-port as the only reference. It is a **better primary reference** than the friend's
tree: newer, closer to our base, and traceable to a named vendor org.

### 4.1 But it is not drop-in, and the reason matters

Altera's 6.18.20-lts `mmc0` declares `compatible = "altr,agilex5-sd6hc", "cdns,sd6hc"` **[V
`socfpga-6.18.20-lts:…/socfpga_agilex5.dtsi:356`]**, with a `COMBOPHY_RESET` stage and no static
PHY timing properties — it targets their **out-of-tree SD6HC driver rewrite** (dynamic timing
calculation replacing static DT params, by Tanmay Kathpalia, Altera; visible in the sibling
`comet-a13-6.18.2-lts` branch's commit log, state `pending` **[V, commit messages only]**).

**`cdns,sd6hc` does not exist anywhere in mainline** — not in 6.18.44, not at v7.2, not at `master`
**[V `grep` of `drivers/mmc/` and `Documentation/devicetree/bindings/mmc/` on all three]**. Copying
Altera's `mmc0` verbatim therefore **buys a carried driver patch** and violates decision 5. The
older SD4HC form, which Terasic and the friend both use and which the friend's board demonstrably
boots on with an unpatched driver (§2.2), does not.

**Rule for harvesting: take Altera's board `.dts` as the wiring reference — pinmux, PHY, regulators,
QSPI partitions, hwmon channels — and take `mmc0` in the SD4HC form.** Reconcile every node against
what mainline's driver actually matches before adopting it. The prior art tells us *what the board
looks like*; it does not tell us *what our kernel binds*. §4.2 is the same lesson applied to the
svc node.

### 4.2 Read the vendor trees for *behaviour*, not just for nodes

The survey's second-most useful output is negative: the vendor trees carry **driver** behaviour that
their DTS silently depends on. Terasic's `stratix10-svc.c` is 3733 lines to mainline's 1334, and the
delta includes the entire Agilex 5 SDM DMA story (§0 Finding 2) **[V]**; its `sdhci-cadence.c` gives
`intel,agilex5-sd4hc` a dedicated `.data` carrying `SDHCI_QUIRK2_40_BIT_DMA_MASK`, a quirk that
**does not exist anywhere in mainline** **[V, §5.1]**. A DTS harvested from a vendor tree and dropped
onto a mainline kernel is therefore not a like-for-like transplant, and the differences are invisible
at build time. Every node we adopt gets checked against *the driver mainline will actually bind*.

Also flagged, not pursued: `Thejayman77/retroDE*` (an apparently independent MiSTer-core-on-DE25
porting effort) and `GM-Benji/agilex5-linux-amp` **[U, not inspected]**. MiSTeX has **no** Agilex 5
support — GitHub code search for `agilex5` in `MiSTeX-devel/MiSTeX-hardware` returns zero hits **[V]**.

---

## 5. Kernel version — recommend mainline 7.2; minimum acceptable base is 6.19

**Recommendation: pin the DE25 to mainline 7.2, the line this repo already builds for the DE10 RT
beta. Do not base the DE25 on 6.18.** Confidence: **high** on the mechanism driving the choice,
**medium** on the operational cost, which is a treadmill question rather than a technical one.

### 5.1 Why 6.18 fails on its own terms

The 6.18 case rested on three supports. Two collapse and the third has been re-characterised:

1. **"6.18 is the only LTS."** True — 6.18 was designated longterm, supported into Dec 2028 **[V]**;
   6.19/7.0/7.1/7.2 are ordinary stable lines. But this is an argument about *bump cadence*, not
   capability, and it is outweighed by (3).
2. **"The mmc0/SMMU regression argues for a newer kernel."** **Re-characterised, and it now argues
   for nothing.** An earlier reading called the fault a 6.12→6.18 *kernel-version regression* on a
   byte-identical DT. That is **not established, and the evidence points elsewhere.** The "working
   6.12" baseline is **Terasic's vendor tree**, whose `sdhci-cadence.c` gives `intel,agilex5-sd4hc`
   a dedicated match entry carrying **`SDHCI_QUIRK2_40_BIT_DMA_MASK`**
   **[V `terasic/linux-socfpga@de25-nano-6.12.11-lts:drivers/mmc/host/sdhci-cadence.c:783-786,952-953`,
   fetched this pass]**. That quirk **exists nowhere in mainline** — `grep '40_BIT_DMA_MASK'` over
   `drivers/mmc/` and `include/` at 6.18.44 → zero hits; over `sdhci.h` at v7.2 and `master` → zero
   hits **[V]**. Mainline's `sdhci_set_dma_mask()` therefore takes the 64-bit branch
   (`dma_set_mask_and_coherent(dev, DMA_BIT_MASK(64))`, `linux:drivers/mmc/host/sdhci.c:4117-4123`)
   **[V]** on a controller the vendor deliberately caps at 40 bits. Under SMMU translation with
   top-down IOVA allocation, an IOVA above the controller's wired address bits truncates — which is
   precisely an `F_TRANSLATION` "input address caused fault". **The DT was byte-identical; the
   drivers were not.** Mainline 6.12 was never tested and could not have been (no Agilex 5 clk driver
   in mainline before v6.19). **Consequence: this is a vendor-vs-mainline delta, not a version
   regression, so it does NOT disappear on 6.19 or 7.2 — it travels with mainline `sdhci-cadence` +
   SMMU on every version [V].** It is now an open hardware question with a named leading hypothesis
   and a cheap upstreamable fix (§8 Q2), not a version-selection input in either direction. Note
   separately that mainline has never shipped an Agilex 5 `mmc0` node on any version 6.18 → `master`
   **[V]**, so `iommus` and `dma-coherent` are knobs we control.
3. **"A 6.18 DE25 carries no driver patches."** **False, and this is decisive.** `clk-agilex5.c`
   lands in **v6.19** and is absent from 6.18 **[V]**. Mainline 6.18.44 has the
   `intel,agilex5-clkmgr` binding, the clock-ID header, and the DT node at `:144-148` — and no driver
   at all; the *only* `agilex5` compatible string in the whole of 6.18.44's `drivers/` is stmmac's
   **[V, `grep -rl` this pass]**. Every consumer of `&clkmgr` — `mmc0` included — would defer
   forever. The friend confirms this by construction: he backported an 847-line vendor
   `clk-agilex5.c` into his 6.18.38 tree and wired it into `drivers/clk/socfpga/Makefile:6` **[V]**.

Support 3 is decisive under decision 5. Basing on 6.18 means carrying a whole SoC clock driver when
a mainline route plainly exists one release later. That is exactly the carried patch decision 5
tells us to justify — and there is no justification available.

### 5.2 What each base actually costs

| Base | Carried driver code | DTS work | Line status |
|---|---|---|---|
| 6.18.44 | **clkmgr backport** (561 lines mainline / 847 lines vendor) | author `svc` + `smmu` + `fpga-mgr` + `fpga-region` + `mmc0` | LTS → Dec 2028 |
| 6.19 | **none** | author `fpga-mgr` + `fpga-region` + `mmc0`; override `svc` compatible; enable `smmu` | EOL |
| **7.2** | **none** | same as 6.19 | stable, short tail |
| master → 7.3 | none | same, minus `smmu` enable | unreleased |

Moving from 6.18 to ≥6.19 removes a driver backport and two authored nodes. Moving from 6.19 to 7.2
gains `iommus`/`dma-coherent` on the ethernet nodes (landed by v7.0 **[V]**) and puts us on the line
the repo already builds. Note the correction to one leg's reading: at **tag v7.2** the `smmu` node
still carries `status = "disabled"` (`:379-389`); only at `master` is it enabled (`:379-388`) **[V,
both fetched]**. Two legs disagreed here because one read `master` and called it 7.2. Either way we
set `status = "okay"` from the board file, as Altera's own board file does.

**No version of mainline fixes anything on the reconfiguration question (§2.6).** `stratix10-svc.c`
grows from 1334 lines at 6.18.44 to 2113 at v7.2, but the growth is FCS command plumbing; a `grep`
for `iommu|REMAPPER|dma_addr_offset` at v7.2 returns **zero hits**, exactly as at 6.18.44 **[V]**.
Choosing 7.2 buys the clock driver and the ethernet `iommus`; it does not buy Agilex 5 SDM support.

### 5.3 Cost of a different kernel from the DE10

Small, and already paid. `de25-patch-portability.md` triages our 40-patch series against 6.18.44:
**33/40 (82.5%) portable-as-is**, all subsystem-generic (HID/USB/mmc-core/i2c/exfat/leds), none
6.18-coupled **[V `de25-patch-portability.md:124-166`]**. `rt-beta-kernel.md` records a **completed
build measurement**: the full 40-entry series applies to **Linux 7.2 final** at Buildroot's `-F0`
with **40/40 applying and zero hunks taking fuzz**, verified 2026-08-17 **[V `rt-beta-kernel.md:222`]**.
That is on the DE10 ARM32 tree, so transfer to aarch64 is **[U]** — but the touched files are
architecture-generic C, so confidence is high. ADR 0021's per-variant machinery (shared
`linux.config` + version fragment + symlinked series) is proven end-to-end on that same 7.2 line, so
a DE25 pin at 7.2 is a **new instance of an existing pattern**, not new engineering.

The real cost is the **bump treadmill**: 7.2 is not LTS, so the DE25 inherits the RT beta's
discipline (`rt-clean`, TOFU-hash re-verification, boot re-proved per version) indefinitely. Pinning
the DE25 to the same 7.x line the RT beta already tracks keeps that at **two** kernel lines in the
repo rather than three, and lets one bump serve both.

**Re-open this if:** kernel.org designates a 7.x release longterm (pin that one instead); or 7.3
ships with the `smmu` already enabled *and* any Agilex 5 `mmc0` node, which would be the first
upstream test case for the SD/SMMU question either way.

---

## 6. U-Boot

**We build `u-boot.itb` only.** The factory SPL in QSPI is untouched — that is the posture-1
contract fixed in [`de25-boot-chain.md`](de25-boot-chain.md) §2, §8.3.

**Version: mainline v2026.07** (current stable; v2026.10 is at -rc2, due 2026-10-05) **[V]**, paired
with **mainline TF-A v2.15.0**, which does carry `plat/intel/soc/agilex5/` **[V]**. Flag plainly:
**this pairing is unblessed and untested by us [U]**. Terasic and Altera document only vendor forks
(`u-boot-socfpga socfpga_v2023.10` + `arm-trusted-firmware socfpga_v2.10.0`). There is **no**
Terasic DE25-Nano board anywhere in mainline U-Boot — `board/terasic/*` has de0-nano-soc, de1-soc,
de10-nano, de10-standard, sockit and no de25 entry, and no `configs/*de25*` exists in the full
40,995-path v2026.07 tree **[V]**. We carry the board fragment ourselves; there is nothing to select.

### 6.1 The FIT contract we must hit

`u-boot.itb` is produced by **binman**, not the legacy `u-boot.itb:` Makefile rule (which is gated
on `U_BOOT_ITS`, set only under the deprecated `SPL_FIT_GENERATOR`, unused here — `Makefile:1785`).
`ARCH_SOCFPGA_AGILEX5` `select`s `BINMAN if SPL_ATF` (`arch/arm/mach-socfpga/Kconfig:72-78`) and the
defconfig sets `SPL_ATF=y` (**[V]** re-verified this pass: `socfpga_agilex5_defconfig:54`
`CONFIG_SPL_ATF=y`), so `make all` runs `.binman_stamp` (`Makefile:1393,1399`) against
`arch/arm/dts/socfpga_soc64_fit-u-boot.dtsi` **[V]**:

| FIT element | Content |
|---|---|
| image `uboot` | `u-boot-nodtb.bin`, `type=standalone`, `arch=arm64`, `load = 0x80200000` (= `CONFIG_TEXT_BASE`) |
| image `atf` | `bl31.bin`, `type=firmware`, `os=arm-trusted-firmware`, `load = entry = 0x80000000` |
| image `fdt-0` | `u-boot.dtb`, description `"socfpga_socdk"` → rename per board |
| config `board-0` | `default`; `firmware="atf" loadables="uboot" fdt="fdt-0"`; `signature { algo = "crc32"; … }` — an integrity stamp, no keys, consistent with the factory SPL accepting unsigned FITs |

**Residual closed:** `board_fit_config_name_match()` *is* compiled in for SOC64
(`arch/arm/mach-socfpga/board.c:148-158`) and matches each config node's **`description`** — not its
node name — formatted `"board_%u"` from `socfpga_get_board_id()` (`:114-146`), and
`fit_find_config_node()` (`boot/common_fit.c`) falls back to `/configurations/default` when nothing
matches **[V]**. A single-config FIT therefore boots correctly **regardless of board ID**.

**Build shape.** Nothing forces `CONFIG_SPL` on — `ARCH_SOCFPGA_AGILEX5` selects `BINMAN if SPL_ATF`,
`CLK`, `FPGA_INTEL_SDM_MAILBOX`, `SPL_CLK if SPL`, and `ARCH_SOCFPGA_SOC64` **[V]** — and none of the
binman FIT images references anything under `spl/`. So our fragment can carry
`# CONFIG_SPL is not set`, genuinely eliminating SPL compilation. **[U] that this builds clean**;
it is reasoned from the Kconfig graph, not build-tested, and is the first thing to check at first build.

### 6.2 The env configuration that makes a QSPI write structurally impossible

This is stronger than "never call `saveenv`", and it upgrades ledger row 12 from **[U]** to
**[V, code-traced]**. Re-verified against `v2026.07` sources this pass.

The stock `socfpga_agilex5_defconfig` sets **both** `CONFIG_ENV_IS_IN_FAT=y` (`:72`) and
**`CONFIG_ENV_IS_IN_UBI=y`** (`:73`), with `ENV_FAT_DEVICE_AND_PART="0:1"` (`:74`),
`ENV_UBI_PART="root"` (`:75`), `ENV_UBI_VOLUME="env"` (`:76`) **[V, fetched at v2026.07]**. FAT is
tried before UBI in `env_locations[]`, and `env_save()` targets whatever `env_load()` last succeeded
from (`gd->env_load_prio`, `env/env.c:33-73`) **[V]** — so with a valid `uboot.env` on FAT, `saveenv`
never reaches UBI.

**But the hazard is on the load path, with no save involved.** `env_ubi_load()` (`env/ubi.c:107`)
calls `ubi_part()` **unconditionally** at **`env/ubi.c:128`** whenever the FAT load fails
**[V, file fetched at v2026.07 and read this pass]**. That runs `ubi_dev_scan()` → `ubi_init()` →
`ubi_attach_mtd_dev()` → `ubi_attach()`; against a **fully erased** MTD partition this **succeeds**
(`ai->is_empty = 1`, "empty MTD device detected", `drivers/mtd/ubi/attach.c:1100-1126`), whereupon
`ubi_read_volume_table()` calls `create_empty_lvol()` → `create_vtbl()` (`vtbl.c:299,495,780,808-809`)
and **writes a fresh UBI layout volume into QSPI** **[V]**.

> **Missing or corrupt FAT env + a blank `root` MTD ⇒ QSPI is written on the very first
> `env_load()`, with zero user action and no `saveenv` anywhere.**

**The guard must therefore be `# CONFIG_ENV_IS_IN_UBI is not set` in our board fragment.** Nothing
in `ARCH_SOCFPGA_AGILEX5`/`ARCH_SOCFPGA_SOC64` `select`s it — it is a plain defconfig choice **[V]**.
Recommended fragment, with a comment that survives future editing:

```
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
# CONFIG_ENV_IS_IN_UBI is not set    # env_ubi_load() -> ubi_part() -> UBI attach ->
                                     # create_vtbl() writes a layout volume into a blank
                                     # QSPI partition on LOAD, not just on save. The write
                                     # is in the UBI attach path, not in env/ubi.c itself —
                                     # grepping env/ubi.c for a write finds nothing. See §6.2.
# CONFIG_SPL is not set              # factory SPL is untouched; we ship u-boot.itb only
```

### 6.3 exFAT — a blocker that has expired

Mainline U-Boot now has real exFAT: `fs/exfat/`, `CONFIG_FS_EXFAT` ("read/write support",
`imply CMD_FS_GENERIC if CMDLINE`), added by commit `b86a651b64` on **2025-03-17** — *after* the
reference board's U-Boot 2025.01 base **[V]**. That is precisely why the friend had to hand-roll
`libexfat` and a custom exFAT-aware SPL; on current mainline the equivalent is one defconfig line.
Note the stock defconfig enables `SPL_FS_FAT` (`:22`) but **not** `FS_FAT`/`CMD_FAT`/`FS_EXFAT` for
U-Boot proper **[V, re-checked this pass]** — we set what we need either way.

This removes a capability gap; it does **not** decide p2's filesystem. **Decision 3 fixes the
partition count and p1's FAT type only — p2's filesystem is still an open owner decision [U].**
Kernel-on-p1 sidesteps the question entirely and matches the SPL contract's spirit; kernel-on-p2 is
now viable if p2 ends up exFAT. The 4 GiB FAT32 per-file cap is irrelevant to a kernel `Image`.

---

## 7. The residual scope question — the minimal kernel-side trigger

Decision 2 says we make the hardware available and Main_MiSTer does the loading. The honest problem
is that **mainline provides no userspace entry point at all**, so "available" is not achievable with
zero non-mainline code. This section states the options and their costs. It does **not** design a
loader.

**What mainline exposes [V, all re-read this pass]:** `fpga_manager` class devices carry `name`,
`state`, `status` — all `DEVICE_ATTR_RO`, and `fpga_mgr_attrs[]` holds exactly those three
(`linux:drivers/fpga/fpga-mgr.c:655-664`). `fpga_region` carries only `compat_id`, also RO
(`linux:drivers/fpga/fpga-region.c:175`). There is no writable attribute anywhere. `OF_CONFIGFS`
**does not exist in mainline** — `linux:drivers/of/Kconfig` has only `OF_OVERLAY:105` and
`OF_OVERLAY_KUNIT_TEST:116`, and there is no `drivers/of/configfs.c`. Altera's vendor 6.12-lts tree
does carry it — i.e. the friend's original path was the vendor path.

**The only mainline trigger is an OF overlay carrying `firmware-name`**, caught by of-fpga-region's
overlay notifier, registered at module init (`linux:drivers/fpga/of-fpga-region.c:340,455`).

| Option | Mainline surface | Cost | Verdict |
|---|---|---|---|
| (a) Small out-of-tree module calling `of_overlay_fdt_apply()` | **adds one file, modifies none** | ~95 lines; GPL-only symbol; must track OF API drift | **Recommended** |
| (b) Carry `OF_CONFIGFS` | permanently forks `drivers/of` | repeatedly rejected upstream; conflicts on every rebase | Rejected |
| (c) Static base-DT `fpga-region` with `firmware-name` | zero code | **does not work — see below** | **Closed [V]** |

**(c) is settled closed.** `firmware-name` is read **only** inside `of_fpga_region_parse_ov()`
(`linux:drivers/fpga/of-fpga-region.c:232`, plus the child-region rejection helper at `:162`), and
that function is reached **only** from the overlay notifier. `of_fpga_region_probe()` (`:396`) never
reads it **[V, function read in full]**. A base-tree `firmware-name` programs nothing at boot. This
closes Leg B's open unknown about a zero-out-of-tree-code path: **there isn't one.**

**(a) is the recommendation.** `of_overlay_fdt_apply()` and `of_overlay_remove()` are
`EXPORT_SYMBOL_GPL` (`linux:drivers/of/overlay.c:1090,1272`) **[V]**, so a small GPL module can drive
reconfiguration without patching any mainline file. The friend's `de25_fpga_trigger.c` is 95 lines
doing exactly this — `request_firmware()` → `of_overlay_fdt_apply()` → `DEVICE_ATTR_WO(trigger)` on a
misc device **[V `de25-linux:drivers/misc/de25_fpga_trigger.c`, 95 lines by `wc -l`]**.

**What that module's hardware history actually shows — corrected.** An earlier draft said "it is
running on real hardware." That overstates it. On real silicon the module **reached the fpga-mgr
write path** — `dmesg` shows `fpga_manager fpga0: writing de25_live_switch_current.rbf to Stratix10
SOC FPGA Manager` — and the **single** reconfiguration attempt then **timed out waiting for
`RECONFIG_REQUEST` and wedged the board** **[V `de25-reference-implementation.md:115`, §5]**. So the
module is an existence proof that *the trigger shape works* — a userspace write does reach
`fpga_region_program_fpga()` through the overlay notifier — and it is **not** evidence that
programming succeeds. Those are two different claims and §2.6 owns the second.

**The honest tension, stated plainly.** Option (a) is still non-mainline code. Decision 5 cannot be
fully satisfied for the trigger, because **no mainline route exists** — which is precisely the
justification decision 5 asks for, and (as of this pass) the only one of our carried items that has
it. What (a) buys over (b) is rebase safety: a new file never conflicts, and it does not relitigate
a rejected upstream design. Scope discipline holds: the module's entire job is to accept "apply this
overlay" and hand it to `of_overlay_fdt_apply()`. Choosing the overlay, staging the `.rbf`,
sequencing switches, and quiescing the fabric client are **Main_MiSTer's**, per decision 2.

**Answer to the residual question, in one sentence:** *the minimal kernel-side trigger is a small
out-of-tree GPL misc driver exposing one write-only attribute that calls `of_overlay_fdt_apply()` on
a `firmware-name`-bearing overlay — roughly 100 lines, adding one file and modifying none, because
mainline exposes no writable fpga-manager attribute, has no configfs overlay loader, and ignores
`firmware-name` outside the overlay-notifier path.*

---

## 8. Open [U] — what is unsettled and what settles each

| # | Open question | Why it matters | How it is settled |
|---|---|---|---|
| 1 | **Can mainline's `stratix10-svc` actually program an Agilex 5 fabric?** | The headline risk. A fallback-matched fpga-mgr probes cleanly and then fails to program — the worst failure mode, and it has been **observed once on real silicon** [V]. Terasic's vendor svc does IOMMU attach, an IOVA carveout, a `+0x80000000` SDM address offset and an `INTEL_SIP_SMC_SDM_REMAPPER_CONFIG` remapper bypass under `intel,agilex5-svc`; mainline passes raw `gen_pool` physical addresses and has none of it at 6.18.44 **or v7.2** [V]. | **§2.6's four-step hardware test — do it first.** In parallel, read TF-A `plat/intel/soc/agilex5` SIP handlers against `include/linux/firmware/intel/stratix10-smc.h`, and diff Terasic's `stratix10-svc.c` against mainline's to size a port if step 3 fails. Confidence today: **low**. |
| 2 | Does an authored `mmc0` fault `arm-smmu-v3` `F_TRANSLATION` on a 7.x base, and is the cause a DMA-mask width? | **Leading hypothesis, newly evidenced:** mainline takes `DMA_BIT_MASK(64)` (`sdhci.c:4117-4123`) where Terasic's vendor driver caps this controller at 40 bits via `SDHCI_QUIRK2_40_BIT_DMA_MASK` — a quirk absent from mainline at 6.18.44, v7.2 and `master` [V]. Under SMMU translation, top-down IOVA allocation above the controller's wired address bits truncates → "input address caused fault". This is a **vendor-vs-mainline driver delta, so it does not go away on a newer kernel.** | Boot **five** ways: `iommus` present/absent × `dma-coherent` present/absent, **plus** a fifth leg capping mmc0's addressing (`dma-ranges` / `bus_dma_limit` in DT, or a locally applied 40-bit mask) with the SMMU on. Watch dmesg for `F_TRANSLATION`; measure `dd`/`hdparm` to separate working ADMA from forced PIO. **If the fifth leg fixes it, the mainline-first remedy is a one-entry `sdhci-cadence` upstream patch** (`intel,agilex5-sd4hc` + a 40-bit mask), which removes the PIO throughput cost for everyone. No public evidence exists either way **[V, searched: zero agilex5-specific hits; no smmu/iommu commit in the last 100 on `socfpga-6.18.20-lts`]**. |
| 3 | Is overriding svc's compatible to `intel,agilex-svc` while keeping `iommus = <&smmu 10>` functionally equivalent? | Safe against **mainline**, which branches on neither string [V]. Not safe as a general assumption: the binding's `allOf` *requires* `iommus` for the agilex5 string, and the vendor driver makes that string the switch for IOMMU attach + remapper bypass, hard-failing `-ENODEV` without it [V]. | Confirm `iommus` is honoured by the generic `of_dma_configure()` path independent of the matched compatible (`drivers/of/device.c`, `drivers/iommu/of_iommu.c`), then verify on-device that svc buffers in `service_reserved` are SDM-reachable. Folded into Q1's test. |
| 4 | Has Khairul's fpga-mgr series landed anywhere we would ship? | The binding is absent from v7.2 **and** `master`, nine months after the v6 posting (2025-11-18) — long enough to suspect it stalled. Until it lands, our two-string form warns under `dtbs_check` (§2.5). | Fetch the lore thread for a maintainer "Applied" from Xu Yilun or Dinh Nguyen; grep linux-next's `socfpga_agilex5.dtsi` for `fpga-region`. Re-check on every kernel bump. |
| 5 | Does mainline TF-A v2.15.0's Agilex 5 BL31 boot this board, and does it handle >2 MB reconfiguration? | The reference board needed non-stock ATF buffer-size fixes. Stock ATF is untested here, and it is the other half of Q1's SMC contract. | D2.2 hardware pass: build stock v2.15.0 `bl31.bin`, package into `u-boot.itb`, boot under the factory SPL; separately exercise the >2 MB fabric-reconfigure path. |
| 6 | Does `# CONFIG_SPL is not set` build clean and still emit `u-boot.itb`? | Reasoned from the Kconfig graph only. | A desk build of v2026.07 + our fragment; check for `u-boot.itb` and no fatal errors. |
| 7 | Which filesystem for p2, and therefore does the kernel live on p1 or p2? | Decision 3 fixes partition count and p1 only. U-Boot can now read either **[V]**, so this is a project decision, not a capability gap. | Owner decision, informed by the DE10 two-partition precedent and what else p2 must hold. |
| 8 | Do our 33 portable-as-is patches apply cleanly on **aarch64** at 7.2? | Verified at 7.2 on ARM32 with 40/40 and zero fuzz; the touched files are arch-generic C, so transfer is likely but unproven. | First DE25 Buildroot build with the shared series symlinked at a 7.2 pin. |
| 9 | Are `Thejayman77/retroDE*` and `GM-Benji/agilex5-linux-amp` relevant parallel efforts? | Possible prior art for MiSTer cores on this SoC. | One short follow-up leg: inspect for board DTS or fpga-manager plumbing. |
| 10 | Does upstream ever adopt the vendor's Agilex 5 svc behaviour? | If it does, `stratix10_svc_drv_match` gains per-compatible meaning and §2.1's "fallback is free" argument stops holding. This is falsifier (3) in its realised form. | Diff both match tables and `grep` for `iommu|REMAPPER|dma_addr_offset` in `stratix10-svc.c` on **every** kernel bump. Add to the bump checklist. |

---

## 9. Where the legs disagreed, and corrections owed

**Resolved disagreements.**

1. **"No driver patch needed" vs "Altera's own tree carries the match entries."** Both observations
   are true and they do not conflict *for binding*. Altera and the friend chose *exact* compatible
   strings in their DT, which forces the match-table additions; the fallback route was simply not
   taken. The OF core makes a fallback binding-equivalent **[V]**, and we author our own DT, so the
   choice is ours. The salvaged doc's claim is **upheld in substance for binding**, with two
   corrections: the upstream *binding* patch has not landed (so the two-string form warns under
   `dtbs_check`), and **binding was never the whole question** — §2.6.
2. **`smmu` status at v7.2.** One leg read `master` and labelled it 7.2. At **tag v7.2** the node has
   `status = "disabled"` (`:379-389`); at `master` it is enabled (`:379-388`) **[V, both fetched]**.
   Immaterial to the plan — we set `status = "okay"` from the board file either way — but it slightly
   shrinks the "7.x gives it free" claim.
3. **Kernel choice.** One leg recommended 6.18 LTS on the grounds that no newer kernel offered
   anything concrete. That analysis did not check `drivers/clk/socfpga/`. With `clk-agilex5.c`
   landing in v6.19, 6.18 costs a carried driver and the recommendation inverts (§5).

**Corrections owed to sibling documents.**

| Document | Claim | Correction |
|---|---|---|
| `de25-fpga-reconfig.md` §4.2 | "Writing the two-string form now is free and forward-compatible" | Free at **runtime**; **not** schema-clean — the binding is still a plain `enum` at `master`, so `dtbs_check` warns until Khairul's v6 lands (§2.5). |
| `de25-reference-implementation.md` (line ~349) | "Mainline 6.18.x cannot reconfigure an Agilex 5 fabric until BOTH a DT node set and a driver match-table entry are added" | The driver half is **avoidable for binding** via a DT fallback compatible **[V]**. What 6.18 *does* unavoidably need is the **clkmgr driver**, which that document does not mention. And "can reconfigure" is not established for mainline drivers at any version (§2.6). |
| `de25-reference-implementation.md` §3 (mmc0/SMMU) | "a real kernel-version regression, not a DT gap" | **Not established.** The 6.12 baseline is Terasic's **vendor** tree, whose `sdhci-cadence` carries a 40-bit DMA-mask quirk that exists nowhere in mainline **[V]**. Vendor-vs-mainline driver delta; mainline 6.12 never tested. The fault therefore travels forward to 6.19/7.2, and 6.18 is not implicated as a version. Recorded in that document's own verification record. |
| `de25-readiness-ledger.md` row 12 | U-Boot env→QSPI write, mechanism **[U]** | Promote to **[V, code-traced]**: the *load* path alone writes a UBI layout volume to a blank QSPI partition; the guard is `# CONFIG_ENV_IS_IN_UBI is not set`, not "don't call `saveenv`" (§6.2). |
| `de25-patch-portability.md` (patch 3 rationale) | "Agilex 5 has a different clkmgr with no in-tree driver at all in 6.18.44" | Correct, and **understated** — it is a boot blocker for the whole board on 6.18, not just context for a cpufreq patch. Landed upstream in v6.19. |

**Corrections applied to this document's own earlier draft**, listed so the change is auditable:

- §2.2 no longer presents the friend's SD boot as unqualified evidence — it runs in PIO.
- §2.2 no longer calls `altr,smmu_enable_quirk` dead devicetree without qualification; it is
  mainline-inert but vendor-live.
- §7 no longer says the trigger module "is running on real hardware"; its one attempt failed.
- §5.1 support 2 rewritten from "the regression does not materialise" to "the regression was
  mis-attributed, and the real delta travels forward".
- §2.4/§8 Q1 confidence on end-to-end reconfiguration lowered from **medium** to **low**, with the
  vendor-driver evidence attached.
- The lkml version label for the DTS companion corrected from v6 to v2 (the binding half is v6).
- Line-number citations corrected: friend's `mmc0` compatible is at `socfpga_agilex5.dtsi:387`;
  6.18.44 `sdhci-cadence` match table at `:643-658`; `of_iommu`/OF base score function at
  `base.c:338-356`.
- §8 gained Q10 (watch upstream for adopted vendor svc behaviour).

**Corrections proposed and rejected**, with the reason:

| Proposed | Rejected because |
|---|---|
| "The v7.2 citation `stratix10-svc.c:1911-1915` is a wrong line number; the table sits near `:1133`." | **The citation is correct.** `:1133` is the **6.18.44** location, in a 1334-line file. The **v7.2** file has grown to 2113 lines (FCS command plumbing) and the table genuinely sits at `:1911-1915` **[V, `mainline@v7.2:drivers/firmware/stratix10-svc.c` fetched and grepped this pass]**. Both citations retained, each labelled with its base. |
| "`clk-agilex5.c … 561 lines` is unconfirmed; the commit adds 736 lines across 7 files." | **The file is exactly 561 lines** **[V, `torvalds/linux@v6.19` fetched, `wc -l` = 561]**. The 736-line figure is the whole commit including Kconfig/Makefile/header churn — a different measure of a different thing. Kept 561 for the file, and now name the friend's 847-line vendor backport alongside it so the three numbers cannot be confused again. |

**Never challenged by any leg**, and worth flagging as such: that `s10_init()`'s
`of_find_node_by_name(NULL, "svc")` makes the parent node **name** load-bearing, that
`stratix10_svc_init()` does the same for `firmware`, and that a missing `method` property fails
probe outright (§2.1); and that Altera's SD6HC `mmc0` is unusable on mainline (§4.1).

---

## 10. Verification record

**What ran this pass (2026-08-22).** Two adversarial verification lenses over the draft and its
source legs — one on the headline binding claim, one spot-checking the salvaged
`de25-reference-implementation.md` — followed by a re-verification of every correction against
primary source before it was applied. Nothing was accepted on a verifier's say-so alone.

**Read directly from local source** (`output/build/linux-6.18.44`, read-only):
`drivers/firmware/stratix10-svc.c` (match table, `of_find_node_by_name`, `get_invoke_func`,
`gen_pool`/`paddr` handling), `drivers/fpga/stratix10-soc.c` (match table, `s10_init`,
`NUM_SVC_BUFS`), `drivers/fpga/of-fpga-region.c` (`firmware-name` read sites, probe, notifier),
`drivers/fpga/fpga-mgr.c` and `fpga-region.c` (sysfs attribute groups), `drivers/of/base.c`
(match scoring), `drivers/of/overlay.c` (exports), `drivers/of/Kconfig`, `drivers/fpga/Kconfig`,
`drivers/mmc/host/sdhci-cadence.c` (match table, probe `.data` fallback, PHY property table),
`drivers/mmc/host/sdhci.c` (`sdhci_set_dma_mask`), `arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi`,
`drivers/clk/socfpga/` (directory listing), and a tree-wide `grep -rl agilex5 drivers/`.

**Read read-only from `/mnt/source/de25-linux`:** `drivers/clk/socfpga/clk-agilex5.c` (847 lines),
`drivers/misc/de25_fpga_trigger.c` (95 lines), both patched match tables, `socfpga_agilex5.dtsi`
(svc/fpga-mgr/mmc0 compatibles), `diff -q` of `sdhci-cadence.c` against ours (identical), and a
`grep` for `smmu_enable_quirk` consumers (none).

**Fetched and read this pass:** `torvalds/linux@v6.19:drivers/clk/socfpga/clk-agilex5.c`;
`torvalds/linux@v7.2` and `@master` copies of `stratix10-svc.c`, `stratix10-soc.c`,
`drivers/mmc/host/sdhci.h`, `drivers/mmc/host/sdhci-cadence.c`;
`terasic/linux-socfpga@de25-nano-6.12.11-lts:drivers/mmc/host/sdhci-cadence.c` and
`drivers/firmware/stratix10-svc.c`; `u-boot/u-boot@v2026.07:env/ubi.c` and
`configs/socfpga_agilex5_defconfig`; both LKML archive pages.

**What changed under challenge.** Six substantive changes, all listed in §9 under "corrections
applied to this document's own earlier draft". The two most consequential: the mmc0/SMMU fault is
re-characterised from a kernel-version regression (which a newer kernel would escape) to a
vendor-vs-mainline driver delta (which it will not); and confidence in end-to-end reconfiguration
through stock mainline drivers is lowered to **low**, with §2.6 added to state the position honestly
and name the hardware test.

**What remains contested.** Nothing, materially — both rejected corrections (§9) were settled by
going back to the primary source, and the record of why is kept above so the question does not
reopen on memory.

**What was NOT verified this pass, and must not be read as verified.**

1. **The whole of §6 beyond the four spot-checks named there.** The U-Boot leg's binman/FIT contract,
   `board_fit_config_name_match()` tracing, `Makefile` line citations, the TF-A v2.15.0 Agilex 5
   claim, and the exFAT commit `b86a651b64` were **not** re-read this pass. Re-verified: the
   `socfpga_agilex5_defconfig` env/SPL/FS lines, and `env/ubi.c`'s unconditional `ubi_part()`. The
   rest carries its original leg's evidence standard.
2. **Khairul's v6 2/2 DTS patch body.** Only the v2 revision is reachable on the archive we can read;
   lore was bot-walled. Its *effect* is verified against tree content instead.
3. **TF-A `plat/intel/soc/agilex5` source.** Nobody in this project has read it. Q1 and Q5 both
   depend on it.
4. **Altera's `socfpga-6.18.20-lts` and Terasic's `de25-nano-6.12.11-lts` board `.dts` files
   node-by-node.** They were fetched and structurally surveyed (§4), not audited. §4.2's rule exists
   because of that.
5. **Anything on hardware.** No DE25 board was touched. Every claim about what happens at runtime on
   Agilex 5 silicon in this document is either inherited from the reference implementation's record
   or is a prediction. §2.6 exists to convert the most important prediction into a measurement.
