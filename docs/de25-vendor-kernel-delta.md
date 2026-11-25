# DE25-Nano: the vendor kernel versus mainline, and how to stay on a vanilla kernel

**Status: desk study, 2026-11-17. Nothing in this document has run on a DE25-Nano.** No board has
booted our image yet. Every hardware statement below is either read from source or reported by
someone else's vendor-kernel port, and is tagged as such.

This document compares the kernel Terasic ships for the DE25-Nano with mainline Linux, and
records what the comparison changes in this repo. It is the consolidated reference; the older
DE25 documents link here where a finding settles or reverses something they say.

**The short version.**

- A vanilla 7.3.4 kernel needs **no DE25-specific kernel patch** to boot, mount the SD card and
  bring up Ethernet and USB. The one DE25-local patch we still carry (`0101`) is optional.
- The one real blocker was **FPGA programming, and it is in firmware, not in the kernel**. With
  stock TF-A v2.15.0, mainline's `stratix10-svc` cannot program the Agilex 5 fabric in any SMMU
  configuration: BL31 rejects the buffer it advertises, and it returns completion addresses the
  kernel cannot match (§3). We now fix that in BL31, which we already build and patch (§4.1).
- The SMMU is **probably not required by the hardware** to program the fabric, but that is
  unproven. One bench session at the U-Boot prompt settles it, with no Linux and no patch (§8).
- Linux **v7.4 changes the picture**: it gains Altera's own Agilex 5 service path (SMMU
  required) and the SD6HC driver. §6.3 says what that means for the next pin move.

Related: [`de25-dts-rationale.md`](de25-dts-rationale.md) §4,
[`de25-fpga-reconfig.md`](de25-fpga-reconfig.md),
[`de25-implementation-path.md`](de25-implementation-path.md) §2.6 and §7,
[`de25-kernel-config.md`](de25-kernel-config.md), [`de25-uboot.md`](de25-uboot.md) §8,
[ADR 0034](decisions/0034-de25-fpga-service-path.md).

---

## 1. What was compared, and how to read the evidence

| Name here | Tree |
|---|---|
| `terasic/` | `github.com/terasic/linux-socfpga`, branch `de25-nano-6.12.11-lts` @ `d7d192a9ddd9` — the kernel Terasic ships for this board |
| `altera612/` | `github.com/altera-fpga/linux-socfpga`, `socfpga-6.12.11-lts` — Terasic's base |
| `altera618/` | `github.com/altera-fpga/linux-socfpga`, `socfpga-6.18.37-lts` — newest Altera downstream |
| `v6.12.11/`, `v6.18.37/` | mainline stable, the bases of the two vendor trees |
| `v7.3.4/` | mainline stable — **our pin** (`dl/linux/linux-7.3.4.tar.xz`) |
| `v7.4-rc1/` | mainline, individual files fetched read-only on 2026-11-17 |
| `TF-A/` | Trusted Firmware-A v2.15.0, our pin (`dl/arm-trusted-firmware/`); line numbers are the unpatched file |
| `U-Boot/` | U-Boot 2026.07, our pin |
| `pubport/` | `github.com/ahmadexp/MiSTer-DE25-Nano` @ `4b2aef2` (public, GPLv3) |

Terasic's tree differs from Altera's 6.12.11 tree in four files only: the board DTS, the DTS
Makefile, a config file, and a diagnostic change to `drivers/edac/altera_edac.c`. The comparison
that matters is therefore Altera downstream against mainline.

**Evidence tags.**

- **[V]** — read from the named source for this document, by its author.
- **[S]** — found by one study pass and confirmed by a second, but not re-read for this document.
- **[I]** — an inference from [V]/[S] facts. The reasoning is given.
- **[U]** — unsettled until it is measured on a board.
- **vendor-kernel evidence** — an observation from someone running Terasic's or Altera's kernel.
  It says what the hardware can do. It does not say what mainline does.

`pubport/` runs Terasic's 6.12.11 kernel with five patches of its own. Everything cited from it
is vendor-kernel evidence. It is a different source from "the PORT" that the older DE25
documents cite; those citations were not re-read for this study and stand as those documents
recorded them.

---

## 2. What differs, subsystem by subsystem

| Area | Vendor (Terasic 6.12 / Altera 6.18) | Mainline 7.3.4 | Does it matter for the DE25? |
|---|---|---|---|
| **svc: Agilex 5 path** | Probe fails `-ENODEV` unless an IOMMU is present and the node has `altr,smmu_enable_quirk`. Buffers are IOVAs from a carveout below `0x20000000`, mapped with `iommu_map()`; `0x80000000` is added before the SMC; BL31 is asked to bypass the SDM remapper (`terasic/drivers/firmware/stratix10-svc.c:59-64,3244,3366,3507-3556`) **[V]** | None of it. Pool of physical addresses from `FPGA_CONFIG_GET_MEM`; the match table has no `intel,agilex5-svc` (`v7.3.4/drivers/firmware/stratix10-svc.c:919-923,2002-2006`) **[V]** | **Yes. This is the deciding difference** — §3 |
| **svc/fpga-mgr timeouts** | 5000 / 5000 ms for request / buffer | The same in 7.3.4 (`v7.3.4/include/linux/firmware/intel/stratix10-svc-client.h:71-72`). 6.18.37 still had 300 / 720 ms (`v6.18.37/…:68-69`) **[V]** | Yes — it removes the "300 ms `RECONFIG_REQUEST` timeout" risk the older documents record |
| **fpga-mgr driver** | Agilex 5 compatible, per-chunk DMA mapping, firmware-version probe, an authenticate-only flag, a fixed completion timeout **[S]** | Stock driver; binds through our two-string fallback. The completion timeout comes from the caller (`v7.3.4/drivers/fpga/stratix10-soc.c:359`) **[V]** | Only the timeout: whoever calls `fpga_mgr_load()` must set `config_complete_timeout_us`, or completion fails at once |
| **Userspace FPGA trigger** | `CONFIG_OF_CONFIGFS=y` in Terasic's config (`terasic/de25-nano.config:2246`) **[V]** | No `OF_CONFIGFS`, no `FPGA_MGR_DEBUG_FS`, no `drivers/of/configfs.c`; the fpga-mgr sysfs attributes are read-only (`v7.3.4/drivers/fpga/fpga-mgr.c:655-657`) **[V]** | Yes — a loader needs an out-of-tree module, not a kernel patch (§4.3) |
| **SMMU driver** | No change to `drivers/iommu` **[S]** | — | No |
| **SMMU DT node** | Disabled in the dtsi, enabled by the board file **[S]** | **Enabled by default** — the node has no `status` (`v7.3.4/arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi:379-388`) **[V]** | Yes — our `status = "disabled"` is a divergence from mainline 7.3.4, not its default |
| **SD/MMC** | 6.12: a combophy writer inside `sdhci-cadence.c`, `intel,agilex5-sd4hc`, a 40-bit DMA quirk. 6.18: a separate SD6HC driver **[S]** | No `mmc` node in the dtsi, no SD6HC code, no Agilex 5 match — no file under `drivers/`, `Documentation/` or `arch/` contains `sd6hc` **[V]** | Yes — we author the node, and Linux inherits whatever PHY state U-Boot left (§5.1) |
| **Ethernet glue** | DT-driven XGMAC features, per-channel interrupts, RX watchdog off **[S]** | Its own Agilex 5 setup (`v7.3.4/drivers/net/ethernet/stmicro/stmmac/dwmac-socfpga.c:569,668-676`) **[V]**; one combined interrupt, RX watchdog on **[S]** | Should work from source. The interrupt mode differs from what the vendor exercised; watch for stalls at first boot |
| **USB** | dwc2 unchanged; a dwc3 glue for the USB 3.1 port **[S]** | dwc2 the same; no dwc3 glue | No — only `usb0` (dwc2) is enabled by any DE25 device tree |
| **Clocks** | 6.12: an older driver. Altera 6.18 adopted mainline's **[S]** | `clk-agilex5.c`, same clock IDs | No patch. Gate clocks have no enable operation in either, so the gate state U-Boot leaves is final **[S]** |
| **hwmon** | `soc64-hwmon`, a DT child of the svc node | `socfpga-hwmon`, created by the svc driver with no DT node; it picks its channel table from the svc compatible and knows only Stratix 10 and Agilex 7 (`v7.3.4/drivers/hwmon/socfpga-hwmon.c:444-447`) **[V]** | Optional, and **off**: see §4.2 |
| **RSU** | Built as a module in Terasic's config | Present; the device is created by the svc probe, not by a DT node (`v7.3.4/drivers/firmware/stratix10-svc.c:2099`) **[V]** | Kept `=n`. Kconfig is the only gate |
| **FCS, socfpga-config, EDAC, QSFP, TSE, soft-IP** | About seventy extra service commands, and a sysfs front end that can send QSPI-write and fuse-counter commands to the SDM **[S]** | Absent | Not needed. Several are liabilities for a board whose QSPI we never write |
| **GIC ITS DMA32 quirk, AXI-DMAC 40-bit** | Vendor properties **[S]** | Moot (all DRAM is below 4 GiB) / done with `dma-ranges` | No |

The vendor delta is large — hundreds of files against either mainline base — but almost all of it
is IP this board does not use.

### What mainline 7.3.4 already covers

- Clocks, resets, GIC, timers, caches, PMU, `uart1`, `i2c1`, `gpio1`, the watchdogs, `usb0`.
- `gmac0` as an XGMAC, with the Marvell and Micrel PHY drivers from the shared fragment.
- The SMMUv3 node and every stream ID.
- The service layer, RSU, the SDM hwmon driver, and the FPGA manager, region and overlay core.
- The longer service timeouts.

Missing from mainline and supplied by our board DTS: the `mmc0` node, the `fpga-mgr` child and
the `fpga-region`.

---

## 3. The FPGA service path

This is the part of the comparison that decides anything. The claim, stated once: **with
unpatched TF-A v2.15.0, mainline 7.3.4 cannot program the Agilex 5 fabric from Linux, whether
the SMMU is on, off or in passthrough.** It is read from source on both sides. It has not been
observed on hardware.

### 3.1 What the kernel does

1. At probe the service driver asks BL31 for a buffer window with
   `INTEL_SIP_SMC_FPGA_CONFIG_GET_MEM` and builds a pool over the address it gets back
   (`v7.3.4/drivers/firmware/stratix10-svc.c:919-923,1010`) **[V]**.
2. The FPGA manager takes four 512 KiB buffers from that pool
   (`v7.3.4/drivers/fpga/stratix10-soc.c:19-20,213-223`) **[V]**.
3. Each buffer is submitted with `INTEL_SIP_SMC_FPGA_CONFIG_WRITE`, with the buffer's
   **physical address** as argument 1 (`stratix10-svc.c:626-629`) **[V]**.
4. Finished buffers come back through `FPGA_CONFIG_COMPLETED_WRITE`. The driver looks each
   returned address up in its own list and gets the buffer back only on an exact match
   (`stratix10-svc.c:321-332,364-368`) **[V]**.

### 3.2 What BL31 does with it on Agilex 5

**Mismatch 1 — BL31 rejects the window it advertises.**

- `GET_MEM` returns base `0x80400000` and an end of `0x82000000`
  (`TF-A/plat/intel/soc/agilex5/include/socfpga_plat_def.h:43-44`,
  `TF-A/plat/intel/soc/common/socfpga_sip_svc.c:1962-1966`) **[V]**.
- `intel_fpga_config_write()` first calls `is_address_in_ddr_range()`, which returns false for
  any address below `BL31_LIMIT`, and `BL31_LIMIT` is `0x82000000`
  (`socfpga_sip_svc.c:321,337-340`; `socfpga_plat_def.h:150`) **[V]**.
- So every buffer in the advertised window returns `INTEL_SIP_SMC_STATUS_REJECTED`.
- The kernel's rejected branch calls back only for FCS commands
  (`stratix10-svc.c:833-851`) **[V]**. The FPGA manager hears nothing, waits 5 s and returns
  `-ETIMEDOUT` (`stratix10-soc.c:320`). By then `FPGA_CONFIG_START` has already put the SDM
  into reconfiguration.
- This is specific to Agilex 5. On Agilex 7 the window is `0x400000..0x2000000` and
  `BL31_LIMIT` is `0x81000`, so the two agree
  (`TF-A/plat/intel/soc/agilex/include/socfpga_plat_def.h:30-31,99`) **[V]**.

**Mismatch 2 — the completion address does not come back as it went in.**

- On Agilex 5, `intel_smmu_hps_remapper_init()` subtracts `DRAM_BASE` (`0x80000000`) from the
  buffer address in every case. The subtracted value is what is stored, and what
  `COMPLETED_WRITE` later returns (`socfpga_sip_svc.c:154,343,793-806`) **[V]**.
- The kernel submitted `P` and gets `P - 0x80000000`. The lookup returns NULL, and the FPGA
  manager's unlock helper ignores NULL (`stratix10-soc.c:124`) **[V]**.
- No buffer is ever unlocked. Once all four are in use, `s10_send_buf()` returns `-ENOBUFS` and
  the write loop retries immediately, with no wait (`stratix10-soc.c:256,296-297`) **[V]**. For
  any image over 2 MiB that is a busy loop in the kernel.

**The two must be fixed together.** Fixing only the first — for example by moving the buffer above
`0x82000000` — turns a clean timeout into a hang.

The vendor's `+0x80000000` satisfies both at once. An IOVA near the top of the carveout, plus
`0x80000000`, clears the range check, and BL31's subtraction hands back exactly the IOVA the
driver stored.

**A separate BL31 defect, recorded because it is on the same path.**
`intel_fpga_config_start()` calls `intel_smmu_hps_remapper_init(0U)`
(`socfpga_sip_svc.c:258`) **[V]**. The argument is a pointer, so the function reads and rewrites
the 64-bit word at physical address 0, which is the start of on-chip RAM and is mapped
read-write in BL31 (`TF-A/plat/intel/soc/agilex5/bl31_plat_setup.c:198`) **[V]**. In our build
the compiler emits the access as written **[V, disassembly of `bl31.dump`]**. It is harmless as
far as we can tell, and the vendor's v2.12.0 has the same line **[S]**. We do not patch it.

### 3.3 The remapper, the silicon revision and the SMMU

BL31 has a mode that does not involve the SMMU at all.

- At every `FPGA_CONFIG_START` and `FPGA_CONFIG_WRITE`, if bit 1 of `BOOT_SCRATCH_POR_1` is clear
  and no caller has asked for bypass, BL31 writes `DRAM_BASE` into the two
  `SDM_BE_*ADDR_REMAP` system-manager registers and gives the SDM `address - DRAM_BASE`
  (`socfpga_sip_svc.c:793-806`) **[V]**.
- U-Boot names that scratch bit `ALT_SYSMGR_SCRATCH_REG_POR_1_REVA_WORKAROUND_MASK`
  (`U-Boot/arch/arm/mach-socfpga/include/mach/system_manager_soc64.h:50`) and no code in U-Boot
  2026.07 reads or writes it **[V]**. BL31 only reads it. So the name says it is a revision-A
  workaround flag, and nothing we build sets it. Whether it is set on this board is unknown
  **[U]**; T0 reads it (§8). If it is, something that runs before our U-Boot set it, and on this
  board that could be the factory SPL, which is Terasic's **[I]**.
- Mainline v7.4 states the constraint the remapper exists for: the SDM can address 29 bits, and
  an IOVA is kept below `0x20000000` for that reason
  (`v7.4-rc1/drivers/firmware/stratix10-svc.c:74-89`) **[V]**.
- `pubport/` reports that Quartus resolves the board's part number to `MAIN_SM4` /
  `MAIN_SM4_REVB` (`pubport/mister-de25/README.md:76-78`) **[V, their statement]**.

**Inference [I].** On revision-B silicon the SDM reaches the first 512 MiB of DDR without the
SMMU, through the remapper, in BL31's default mode. Whether the SDM's bus traffic then passes an
SMMU that Linux never enabled depends on the reset value of the SMMU's `GBPA` register, which no
source we could read documents **[U]**.

**The bypass SMC is gated the same way in both TF-A versions.** Terasic's v2.12.0 gates
`INTEL_SIP_SMC_FCS_SDM_REMAPPER_CONFIG` on constants named `A5F0`/`A5F4`; ours gates on
`A5C0`/`A5C4`. The values are the same — `0xC000` and `0x4000C000` under the mask `0xF000F000` —
so both take the same branch on the same chip (`TF-A/…/agilex5_system_manager.h:197-210`, and the
same header on `github.com/terasic/arm-trusted-firmware` `de25-nano-v2.12.0`, lines 191-201)
**[V]**. On a chip outside that pair the SMC does nothing and still returns success, in both.

### 3.4 U-Boot's `fpga load` uses the same SMCs

Under TF-A, U-Boot's SDM driver sends `FPGA_CONFIG_START`, then `FPGA_CONFIG_WRITE` with the
caller's **raw DDR address**, and counts non-zero completions
(`U-Boot/drivers/fpga/intel_sdm_mb.c:682-685,704-712,735-747`) **[V]**. It never asks for
remapper bypass, and neither U-Boot nor BL31 touches the SMMU's control registers **[S]**.

That is the same thing Linux would be doing with the SMMU off, once the two mismatches are
fixed. It makes `fpga load` at the U-Boot prompt the cheapest test of whether the hardware path
works (§8, T1). Two reports exist from this board, both on another party's bootloader and both
unverified by us:

- an earlier arrangement loaded more than eight cores this way and printed
  `FPGA reconfiguration OK!` ([`de25-reference-implementation.md`](de25-reference-implementation.md),
  "signed bitstream" finding);
- a later one says `fpga load` wedged the SDM and the launcher was retired
  ([`de25-boot-chain.md`](de25-boot-chain.md) §7b F1).

The first is the best existing evidence that the SDM can read DDR with nobody having set up the
SMMU. The second is a reason to expect that a failed attempt needs a power cycle.

### 3.5 Where upstream went

Linux v7.4-rc1 carries Altera's Agilex 5 service support **[V, `v7.4-rc1/drivers/firmware/stratix10-svc.c`]**:

- the match table gains `intel,agilex5-svc`, and each entry now has driver data (`:2327-2332`);
- for `intel,agilex5-svc`, probe **fails with `-ENODEV` when no IOMMU domain is attached**
  (`:2385-2392`), then asks BL31 for remapper bypass, allocates with `dma_alloc_coherent()` under
  a 29-bit mask, adds `0x80000000` before each SMC and adds it back when a buffer is claimed
  (`:74-89,449-457,2394-2398,2430`);
- `intel,agilex-svc` and `intel,stratix10-svc` keep the physical-address path, and gain a reboot
  notifier that takes the secondary CPUs offline through PSCI on a **warm** reboot only
  (`:144-155,2307-2319,2440-2448`).

So upstream chose the vendor's design, SMMU included, for the Agilex 5 string. The physical
path survives under the other two strings.

---

## 4. What this repo does about it

### 4.1 Fix the address contract in BL31 (TF-A patch `0002`)

[`board/mister/de25nano/patches/arm-trusted-firmware/0002-plat-intel-agilex5-fpga-config-address-contract.patch`](../board/mister/de25nano/patches/arm-trusted-firmware/0002-plat-intel-agilex5-fpga-config-address-contract.patch)
changes one file, `plat/intel/soc/common/socfpga_sip_svc.c`, for Agilex 5 only:

1. `intel_fpga_config_write()` also accepts a buffer that lies wholly inside the `GET_MEM`
   window. `is_address_in_ddr_range()` is not widened, so no other SMC gains access below
   `BL31_LIMIT`, and `0x80000000..0x803fffff` — BL31 itself — stays rejected.
2. `FPGA_CONFIG_COMPLETED_WRITE` returns the address the caller submitted.

The second change is conditional, to keep the other kind of caller working. Altera's kernels
and v7.4's `intel,agilex5-svc` path submit `IOVA + 0x80000000` and expect the bare IOVA back,
and both announce themselves by requesting remapper bypass at probe. The patch records that
request — whether or not the JTAG-ID gate honours it — and returns today's value to those
callers. U-Boot only counts completions and is unaffected.

Two things a bypass caller could notice, both read from the patch **[V]**:

- The first change applies to every caller. A bypass caller's submission is `IOVA + 0x80000000`,
  so an IOVA in `0x400000..0x1ffffff` lands inside the window. Stock BL31 rejected those; the
  patched one accepts them. They are valid IOVAs for such a caller, whose space runs to
  `0x20000000` (`terasic/drivers/firmware/stratix10-svc.c:59-62`,
  `v7.4-rc1/drivers/firmware/stratix10-svc.c:74-89`), so this removes a rejection and adds no
  new failure.
- The record of a bypass request is never cleared. A later call with the bypass argument at 0
  leaves it set until reset. Stock BL31's own `g_remapper_bypass` behaves the same way
  (`socfpga_sip_svc.c:808-819`).

**Why firmware and not the kernel.** We already build and patch BL31. The kernel-side
equivalent — a buffer pool above `0x82000000` plus adding `DRAM_BASE` on claim — is a carried
kernel patch in a file upstream is actively changing.

**Verification [V].**

| Check | Result |
|---|---|
| `apply-patches.sh` on a fresh v2.15.0 tarball, `0001` then `0002` | both apply, no fuzz |
| `make PLAT=agilex5 … bl31` and `make PLAT=agilex … bl31` (aarch64 gcc 15.2) | both build, no warnings |
| `__BL31_END__` in `bl31.map` | `0x800178c0`, unchanged — about 1.9 MiB below U-Boot at `0x80200000` |
| Host harness: the patched functions, verbatim, against register stubs | all cases pass |

Harness cases: `0x80400000` and `0x81f80000 + 0x80000` accepted; `0x803ff000`, `0x80000000`,
`0x80200000`, a buffer crossing `0x82000000` from below, and an overflowing size rejected;
`0x82000000` and above behave as before; with no bypass request a submitted address comes back
unchanged while the SDM is given `address - 0x80000000` and the remap registers hold
`0x80000000`; after a bypass request the rebased address comes back, on a part inside the JTAG
gate and on one outside it.

**Not verified [U].** Any behaviour on hardware. The patch is an upstream candidate for TF-A; it
has not been sent anywhere.

The linker does not protect the gap between BL31 and U-Boot: `BL31_LIMIT` is 32 MiB above the
base, so a much larger BL31 would link cleanly and overlap U-Boot. Nothing in this repo checks
`__BL31_END__` today.

### 4.2 Describe the service node as `intel,agilex-svc`, and drop kernel patch `0102`

The board DTS now sets

```dts
&{/firmware/svc} {
	compatible = "intel,agilex-svc";
};
```

and `linux-patches/0102` (a bare `intel,agilex5-svc` match entry) is deleted.

- On 7.3.4 the two are identical in behaviour: the match table has no driver data, so the stock
  driver binds and runs the same code either way. One fewer kernel patch.
- On 7.4 and later they are not. `intel,agilex5-svc` means "SMMU required" there, and our DTS
  disables the SMMU, so the old shape would stop probing. `intel,agilex-svc` keeps the
  physical-address path that our patched BL31 serves. `0102` would not have applied there anyway.
- `0102`'s commit message said the Agilex 5 SDM speaks the same SMC protocol as Agilex. §3.2
  shows it does not.
- The binding allows it: the compatible is a one-of-three enum and `iommus` is required only for
  the Agilex 5 string (`v7.3.4/Documentation/devicetree/bindings/firmware/intel,stratix10-svc.yaml:34-37,70-79`)
  **[V]**. `dtbs_check` reports the same five `fpga-mgr` warnings before and after, and nothing
  new **[V]**.

**What it costs.** The device tree now names the wrong SoC family on one node. Two consequences
follow, and both are handled:

- `socfpga-hwmon` would select the **Agilex 7** channel table for this compatible, at 7.3.4 and
  at 7.4. So the hwmon driver stays off, with an explicit line in `linux.config`.
- On 7.4 and later the node gets the warm-reboot PSCI notifier. It acts only when the kernel is
  booted with `reboot=warm`; Altera's commit says Agilex 5 does not need it **[S]**.

This is a stopgap for the SMMU-off shape. It is revisited at the 7.4 pin move (§6.3).

### 4.3 A load trigger, drafted but not landed

Mainline has no way for userspace to start a load (§2). The smallest thing that works is an
external module that calls the exported FPGA manager API directly:

1. find the manager node and take a reference with `of_fpga_mgr_get()`;
2. `fpga_mgr_lock()`, which returns `-EBUSY` if a load is in progress;
3. `fpga_mgr_load()` with a firmware name and `config_complete_timeout_us` set to 30 s;
4. unlock, and release everything.

This replaces the overlay-applying module that
[`de25-implementation-path.md`](de25-implementation-path.md) §7 recommended. It does not touch
the live device tree, and it does not depend on the overlay notifier. Loading an overlay to
describe the fabric's devices is then a separate step that Main_MiSTer may or may not want.

An 89-line draft is in Appendix A. It compiles against 7.3.4 headers with the resolved DE25
config and passes `checkpatch.pl --strict` **[V]**. **It is not in the tree as a package**: it
has not been linked against a built kernel, loaded, or run, and the rule here is that code lands
only when it builds through Buildroot. It is needed before test T3 and not before.

---

## 5. The first-boot shape

Three smaller findings changed the board files. Each one trades speed for a first boot whose
failures are easier to read.

### 5.1 SD: Linux inherits the PHY state, so both stages must agree on the mode

> **Superseded at the 7.4 pin (2026-11-24).** v7.4's SD6HC driver computes and rewrites the PHY
> and `HRS` timings on every clock or timing change, and T0 (#318) showed that the SDHCI reset
> at probe zeroes `HRS07`/`10`/`16`. So Linux inherits nothing, and the stages now run different
> modes: U-Boot UHS SDR50, Linux SD high speed at 50 MHz (`de25-dts-rationale.md` §2.8). The text
> below describes 7.3.4.

- The SD controller is a Cadence **SD6HC**. Mainline 7.3.4 has no SD6HC code, so our node binds
  the SD4HC driver through a local compatible. That driver never writes the SD6HC PHY: its only
  PHY code handles eleven SD4HC properties our node does not have **[S]**. Whatever U-Boot left
  in the PHY and `HRS` registers is all Linux ever has.
- **Never add `cdns,phy-*` properties to the Linux node.** They would make the SD4HC driver run
  its own PHY handshake against an SD6HC block **[S/I]**.
- U-Boot programs different PHY values for default speed and high speed
  (`board/mister/de25nano/uboot-dts/socfpga_agilex5_de25nano-u-boot.dtsi`). So Linux must run the
  mode U-Boot ended in.
- Our U-Boot DTS meant to stay at default speed by leaving out `cap-sd-highspeed`. That does not
  work: U-Boot's SDHCI core enables high speed from the capability register on its own
  (`U-Boot/drivers/mmc/sdhci.c:977-978`) **[V]**. The Linux side had the mirror-image problem:
  `cap-sd-highspeed` in DT and capability bit 21 each enable high speed independently
  (`v7.3.4/drivers/mmc/core/host.c:350`, `v7.3.4/drivers/mmc/host/sdhci.c:4572`) **[V]**.

**What changed.** Both device trees now mask capability bit 21 with `sdhci-caps-mask`, and the
Linux node no longer has `cap-sd-highspeed`. U-Boot and Linux both run default speed at 25 MHz,
on the default-speed PHY values, whatever the capability register says.

**Still open [U].** Linux issues a software reset of the SDHCI block at probe
(`v7.3.4/drivers/mmc/host/sdhci.c`, `sdhci_init()` → `SDHCI_RESET_ALL`). If that reset also
clears the SD6HC `HRS` and PHY registers, a 7.3.4 kernel cannot use the card at all and the
SD6HC driver becomes a first-boot requirement. No source says either way. The SD4HC precedent
suggests the registers survive; Terasic's driver sidesteps the question by reprogramming the PHY
itself. T0 settles it without Linux (§8).

### 5.2 DMA: non-coherent until measured

`dma-coherent` is gone from `mmc0`, and `gmac0` now has `/delete-property/ dma-coherent`.

- A wrong `dma-coherent` corrupts data silently. Treating a coherent master as non-coherent is
  always correct and only slower.
- Mainline asserts it for these masters with the SMMU on. We run with it off, and nobody has
  measured that shape.
- `pubport/` runs `gmac0` and the SD controller exactly this way — no translation, no
  `dma-coherent` — on the vendor kernel
  (`pubport/mister-de25/kernel/patches/0003-arm64-dts-intel-de25-isolate-sdm-smmu-stream.patch`)
  **[V, vendor-kernel evidence]**. U-Boot treats DMA the same way.

Restoring the property is test T4, an A/B measurement, not a default.

### 5.3 Ethernet PHY: unknown part, so a temporary driver set

No tree names the PHY part fitted to this board. `linux.config` now builds the Realtek, Qualcomm
AR803x, TI DP83867, Microsemi and Vitesse drivers in addition to the shared fragment's Marvell
and Micrel. The five added ones, with Micrel, are the gigabit copper PHY drivers Terasic's
config builds in (`terasic/de25-nano.config:3046-3076`); Marvell and Broadcom are modules there
(`:3025`, `:3039`) **[V]**. With a matching driver, `phy-mode = "rgmii"` is
applied to the PHY as the vendor kernel applies it; with only the generic driver the PHY keeps
its strap defaults.

Prune to the fitted part once it is read: `cat /sys/bus/mdio_bus/devices/*/phy_id` under Linux.
Our U-Boot has no Ethernet node, so it cannot be read at the U-Boot prompt.

### 5.4 Config hygiene

- The `# CONFIG_MEDIA_SUPPORT is not set` line is gone from the DE25 base. The shared fragment
  sets it `=m`, the fragment wins, and the pair produced a `merge_config.sh` redefinition
  warning.
- `CONFIG_STRICT_DEVMEM=y` is now written down. It was already the resolved value, by arm64's
  default. `IO_STRICT_DEVMEM` stays off, so reading device registers through `/dev/mem` works,
  which the bench steps in §8 rely on. Reading System RAM through `/dev/mem` does not. The DE10
  turns `STRICT_DEVMEM` off for Main_MiSTer; the DE25 image ships no MiSTer binaries, so this is
  left for the Main_MiSTer port to decide.
- The RSU comment no longer claims a missing DT node keeps RSU out. No such node exists.

---

## 6. The carried set

### 6.1 What is carried, ranked by how much depends on it

| # | Item | Where | Status |
|---|---|---|---|
| 1 | BL31 FPGA-config address contract | TF-A patch `0002` | **Required** for FPGA programming from Linux. Landed; hardware-unproven |
| 2 | `intel,agilex-svc` on the service node | board DTS | Landed. Replaces kernel patch `0102` |
| 3 | FPGA load trigger | external module, Appendix A | Drafted, not landed. Needed for T3 |
| 4 | Non-coherent `mmc0` and `gmac0` | board DTS | Landed, first-boot posture |
| 5 | Default-speed SD in both stages | board DTS, U-Boot DTS | Landed, first-boot posture |
| 6 | Temporary PHY driver set | DE25 `linux.config` | Landed; prune after the PHY ID is read |
| 7 | 40-bit SDHCI DMA mask | kernel patch `0101` | **Optional.** Inert with the SMMU off. Kept for an SMMU-on leg and for its binding hunk, which keeps `dtbs_check` clean on `mmc0` |

**No DE25-specific kernel patch is load-bearing.** The shared HID, dwc2 and filesystem series is
unaffected by any of this; see
[`board/mister/de25nano/linux-patches/README.md`](../board/mister/de25nano/linux-patches/README.md).

### 6.2 What is deliberately not carried

| Vendor item | Why not |
|---|---|
| The svc SMMU carveout, `+0x80000000` and remapper bypass | Upstream has its own version in 7.4. We fix the firmware instead |
| `OF_CONFIGFS` | Never upstream. Forks `drivers/of` permanently |
| `FPGA_MGR_DEBUG_FS` | Vendor-only; the module in §4.3 does the job with exported API |
| Terasic's combophy writer in `sdhci-cadence.c` | Superseded by the SD6HC driver in 7.4 |
| FCS, `socfpga-config` and their roughly seventy service commands | Not needed; they include QSPI-write and fuse commands |
| Agilex 5 EDAC, dwc3 glue, QSFP, TSE, soft-IP drivers | Hardware this board does not use |
| Per-channel stmmac interrupts, the page-pool TX quirk | Performance work for the vendor's SMMU-on shape |
| The public port's SMMU-bypass and `/dev/mem` patches | Specific to its vendor-kernel setup |

### 6.3 What changes when the pin moves to 7.4

> **Done for shape (b), 2026-11-17:** the DE25 pin is now 7.4-rc3 (local-only, no CI artifact).
> The SD node uses `altr,agilex5-sd6hc` and `0101` is gone; the svc node stays
> `intel,agilex-svc` with the SMMU off, so the (a)/(b) choice below is still open for hardware.
> Details: [`de25-kernel-config.md`](de25-kernel-config.md) 2026-11-17 note,
> [`de25-dts-rationale.md`](de25-dts-rationale.md) §2.7.

Verified at v7.4-rc1 **[V]**; whether the dtsi `mmc` node lands in 7.5 is **[S]**.

| Area | 7.3.4 (now) | 7.4 |
|---|---|---|
| svc, SMMU off | `intel,agilex-svc` + TF-A `0002` | The same shape keeps working; the node gains the warm-reboot notifier |
| svc, SMMU on | Not possible without a backport | `intel,agilex5-svc` works **as upstream intends**, with no kernel patch. TF-A `0002` is compatible with it by design (§4.1) |
| hwmon | Wrong table under `intel,agilex-svc` | Correct Agilex 5 table, but only under `intel,agilex5-svc` (`v7.4-rc1/drivers/hwmon/socfpga-hwmon.c:464-469`) |
| SD | SD4HC shim + inherited PHY state | `altr,agilex5-sd6hc` in `sdhci-cadence-core.c`, with its own PHY code and the 40-bit mask (`:584-594,805-806`). `0101` goes; our node is rewritten (two-string compatible, `ciu`/`biu` clock order, three named resets). The dtsi still has no `mmc` node at v7.4-rc1 |
| fpga-mgr | Two-string fallback | Unchanged; the match table is the same |

So at 7.4 there is a real choice, and hardware should make it:

- **(a) Upstream's shape:** SMMU on, `intel,agilex5-svc`, `altr,agilex5-sd6hc`. Zero DE25 kernel
  patches and correct hwmon. It reverses ADR 0029 D10. The risk is the SMMU command-queue stall
  that `pubport/` reports after a full fabric load when peripherals are translated — seen on the
  vendor kernel, untested on mainline.
- **(b) Today's shape:** SMMU off, `intel,agilex-svc`, patched BL31. Nothing new to carry, but the
  service node stays mis-described and hwmon stays off.

If T1 and T3 pass, (b) is proven and (a) becomes an experiment worth one bench session. If they
fail, (a) is the fallback and the 7.4 pin move is how to get it without a backport.

---

## 7. Upstream-submission candidates

**Nothing here has been posted, and nothing will be without the owner's approval.**

1. **TF-A:** Agilex 5 `FPGA_CONFIG_WRITE` rejects the `GET_MEM` window and returns a rebased
   completion address (patch `0002`).
2. **TF-A:** `intel_fpga_config_start()` passes `0U` as a pointer and rewrites address 0.
3. **Kernel:** `stratix10-svc` gives no callback for a rejected data submit, and `stratix10-soc`
   spins on `-ENOBUFS`. Both turn a firmware refusal into a 5 s stall or a hang.
4. **Kernel DT:** a `terasic,de25-nano` board compatible in `altera.yaml`, and
   `capacity-dmips-mhz` / `cpu-map` for the A76 + A55 mix, which no tree has **[S]**.
5. **Kernel:** per-queue interrupts for `dwmac-socfpga` (optional).

No longer candidates: `0101` (superseded by the SD6HC series) and `0102` (contradicted by
upstream's semantics for the string).

---

## 8. Hardware test order

| # | Test | Needs | Decides |
|---|---|---|---|
| **T0** | Register capture at the U-Boot prompt (list below) | serial console only | Silicon revision; whether BL31 will program the remapper; whether SMMU bypass is the reset state; what SD mode and PHY state U-Boot leaves; whether a controller reset wipes it |
| **T1** | `fatload` a phase-2 RBF, then `fpga load 0 <addr> <size>`; re-read the remap registers | our firmware, a matching RBF (see below), no Linux | **Whether the SDM can program the fabric with the SMMU untouched** |
| **T2** | Linux first boot as shipped: root mount; 1 GiB `dd` out and back with `sha256sum`; PHY driver and ID; `iperf3` both ways; USB hub, HID and storage; watchdogs; `clk_summary` | the image | Whether the inherited SD state survives Linux; Ethernet and USB on mainline glue |
| **T3** | Linux FPGA load with the §4.3 module, SMMU off, `dyndbg='file stratix10-svc.c +p'`: one load, then twenty in a row, then a truncated RBF | the module landed | The vanilla-kernel FPGA path, end to end |
| **T4** | A/B: `dma-coherent` restored on SD and on Ethernet; then the SD ladder — high-speed timing at 25 MHz, then 50 MHz, in both stages together | T2 clean | Whether to restore `dma-coherent` and lift the speed cap |
| **T5** | SMMU on — only if T1 or T3 fails | a 7.4 kernel, or a backport of its svc change | The fallback |

**T0, what to capture.**

```
md.l 0x10D12210 1      # BOOT_SCRATCH_COLD_4: JTAG ID. Masked with 0xF000F000:
                       #   0x0000C000 = SM4, 0x4000C000 = SM4 rev B
md.l 0x10D1225C 1      # BOOT_SCRATCH_POR_1: bit 1 set = rev A workaround, remapper not programmed
md.l 0x10D12280 2      # SDM_BE_AWADDR_REMAP, SDM_BE_ARADDR_REMAP
md.l 0x16000000 1      # SMMU IDR0
md.l 0x16000020 2      # SMMU CR0, CR0ACK: bit 0 = SMMUEN
md.l 0x16000044 1      # SMMU GBPA: bit 20 = ABORT
mmc rescan; mmc info   # expect "Bus Speed: 25000000" and a legacy / default-speed mode
md.l 0x10808000 0x12   # SD6HC HRS00..HRS17; HRS07 @+0x1C, HRS09 @+0x24, HRS10 @+0x28, HRS16 @+0x40
md.l 0x10808240 2      # SDHCI capabilities: bit 21 = high speed, bits 15:8 = base clock in MHz
```

The PHY registers are indirect: write the register number to `0x10808010`, read the value at
`0x10808014`, for `0x2000`, `0x2004`, `0x2008`, `0x200C` and `0x2010`.

Then the reset question from §5.1. Write the reset Linux will write, and compare:

```
mw.b 0x1080822f 0x01   # SDHCI software reset, all — what sdhci_init() issues
```

**T0 result (2026-11-24, #318):** rev-B silicon, `POR_1` bit 1 clear, remap registers 0, SMMU
off with `GBPA` 0. The reset zeroed `HRS07`/`10`/`16` and `HRS04`-`06`, and cleared `HRS09`
bit 19. Linux 7.4 reprograms all of them (§5.1 note).

Repeat the `HRS` and PHY reads. Unchanged means Linux inherits the state. Reset values mean
7.3.4 cannot run this card slot, and the SD6HC driver is needed before first boot. The card is
unusable in U-Boot after this write until `mmc rescan`.

**T1, details.**

- Load the RBF at an address from `0x82000000` up, with its end below `0xA0000000`. Below
  `0x82000000` BL31 rejects it; above `0xA0000000` it is outside the SDM's 29-bit window after
  the remapper **[I]**. U-Boot's default load address, `0x82000000`, is fine.
- **It needs an RBF that matches the phase-1 image in QSPI.** None is archived here. Our own
  documents also disagree on whether the factory QSPI image is HPS-first at all
  ([`de25-boot-chain.md`](de25-boot-chain.md) §2 says it is; §7b F2 calls it fully configured).
  `quartus_pfg -i golden_top_hps.jic` prints an "HPS IO hash" for an HPS-first image, which
  settles that and gives the hash a phase-2 file must match. `pubport/` avoids the question by
  flashing its own HPS-first image, which is a QSPI write and outside what this project ships.
- A failed load may leave the SDM needing a power cycle (§3.4).
- Pass: `FPGA reconfiguration OK!`, the remap registers read `0x80000000` afterwards, and the
  SMMU's `CR0` is still 0.

**T1 result (2026-11-25, #318):** not runnable on the factory flash. A full-image RBF and an
HPS-first `core.rbf` both fail with config status `0xf0040000`. The second fails because its HPS IO
hash differs from the factory phase-1's. T1 and T3 move to our own QSPI image
([ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md) gate B2).

**Reading the results.**

| Outcome | Meaning | Next |
|---|---|---|
| T1 passes | The SDM reaches DDR with the SMMU off. The hardware path is fine | T2, then T3 |
| T1 passes, T3 fails | The fault is ours: the BL31 patch, the module, or the kernel driver | `dyndbg` on the service driver. If the BL31 patch is at fault, the kernel-side equivalent is the alternative (§4.1) |
| T1 fails, or `POR_1` bit 1 is set, or `GBPA` has ABORT set | The SMMU is needed on this silicon | T5: enable `&smmu`, use `intel,agilex5-svc` on 7.4, keep `0101` or move to SD6HC, restore mainline's `dma-coherent` |
| T5 works but the command-queue stall appears | The public port's finding holds on mainline too | Translate only the SDM stream and bypass the rest. On mainline that needs a small carried patch or a per-device default-domain change **[I, untested]** |

---

## 9. Two questions, answered directly

**Is the SMMU required to program the fabric?**

- By the vendor kernel: yes, by construction. Its probe fails without it.
- By mainline 7.4's driver for `intel,agilex5-svc`: yes, by policy.
- By the hardware: **probably not on this board, unproven.** BL31 has a non-SMMU mode built on
  the revision-B remapper, U-Boot's `fpga load` uses it, and the die is reported as SM4
  revision B. T0 and T1 settle it.
- By mainline 7.3.4 as shipped: the question did not arise, because the BL31 address contract
  broke it in every mode.

**Does enforcement of signed bitstreams depend on the SMMU path?** No.

- The SDM authenticates the bytes it receives. Linux and BL31 only tell it where to read.
- Mainline's reconfiguration request carries one flag, for partial reconfiguration. No tree has
  a "skip authentication" flag. The vendor's extra flag is an authenticate-only dry run
  (`v7.3.4/include/linux/firmware/intel/stratix10-svc-client.h:61-64`,
  `terasic/…/stratix10-svc-client.h:60-68`, `terasic/drivers/fpga/stratix10-soc.c:226-233`) **[V]**.
- The SMMU or the remapper decides only whether the SDM reads the right bytes. A wrong mapping
  gives a failed configuration, not an unauthenticated one **[I]**.
- Whether enforcement is on at all is a fuse and key-provisioning property of each device.
  Port reports say unsigned cores load on shipped boards
  ([`de25-boot-chain.md`](de25-boot-chain.md) §7b F5).
- With our config, no in-tree code can send fuse-writing or QSPI-writing SDM commands. Terasic's
  shipped kernel exposes both to root through `socfpga-config` **[S]**. What remains is an
  out-of-tree module calling the SMC directly, which root can always do.

---

## 10. What is not verified

- Nothing was booted. The BL31 patch, the device-tree changes and the kernel config are
  untested on hardware.
- No kernel was built for this change. The config was resolved with `olddefconfig`; the DTB was
  compiled and schema-checked; the patch series was applied to a pristine 7.3.4 tree.
- The BL31 and module compile checks used the host's aarch64 gcc 15.2, not the Buildroot
  toolchain.
- The reset values of `GBPA` and of the remap registers, and the remapper's exact behaviour, are
  not documented in anything we could read.
- The [S] rows of §2 were not re-read for this document.
- The Ethernet PHY part, the silicon revision, and whether the factory QSPI image is HPS-first
  are all unknown.

---

## Appendix A. Draft load-trigger module

Not in the tree as a package; see §4.3. Writing a firmware name to
`/sys/class/misc/de25-fpga-load/load` (root only) loads that file as a full bitstream.

```c
// SPDX-License-Identifier: GPL-2.0-only
/* de25-fpga-load - load a full FPGA image by firmware name through fpga-mgr. */
#include <linux/fpga/fpga-mgr.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/time64.h>

/* stratix10-soc waits this long for the SDM to report completion; 0 fails at once. */
#define DE25_FPGA_COMPLETE_TIMEOUT_US	(30 * USEC_PER_SEC)

static const char * const de25_fpga_mgr_compat = "intel,agilex5-soc-fpga-mgr";

static ssize_t load_store(struct device *dev, struct device_attribute *attr,
			  const char *buf, size_t count)
{
	struct fpga_image_info *info;
	struct fpga_manager *mgr;
	struct device_node *np;
	char *copy, *name;
	int ret;

	copy = kstrndup(buf, count, GFP_KERNEL);
	if (!copy)
		return -ENOMEM;
	name = strim(copy);
	if (!*name || strchr(name, '/')) {
		ret = -EINVAL;
		goto out_copy;
	}

	np = of_find_compatible_node(NULL, NULL, de25_fpga_mgr_compat);
	if (!np) {
		ret = -ENODEV;
		goto out_copy;
	}
	mgr = of_fpga_mgr_get(np);
	of_node_put(np);
	if (IS_ERR(mgr)) {
		ret = PTR_ERR(mgr);
		goto out_copy;
	}

	info = fpga_image_info_alloc(dev);
	if (!info) {
		ret = -ENOMEM;
		goto out_mgr;
	}
	info->firmware_name = devm_kstrdup(dev, name, GFP_KERNEL);
	if (!info->firmware_name) {
		ret = -ENOMEM;
		goto out_info;
	}
	/* Full reconfiguration: no FPGA_MGR_PARTIAL_RECONFIG in info->flags. */
	info->config_complete_timeout_us = DE25_FPGA_COMPLETE_TIMEOUT_US;

	ret = fpga_mgr_lock(mgr);
	if (ret)
		goto out_info;
	ret = fpga_mgr_load(mgr, info);
	fpga_mgr_unlock(mgr);

out_info:
	fpga_image_info_free(info);
out_mgr:
	fpga_mgr_put(mgr);
out_copy:
	kfree(copy);
	return ret ? ret : count;
}
static DEVICE_ATTR_WO(load);

static struct attribute *de25_fpga_load_attrs[] = {
	&dev_attr_load.attr,
	NULL
};
ATTRIBUTE_GROUPS(de25_fpga_load);

static struct miscdevice de25_fpga_load_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "de25-fpga-load",
	.groups = de25_fpga_load_groups,
};
module_misc_device(de25_fpga_load_misc);

MODULE_DESCRIPTION("DE25-Nano full-bitstream load trigger");
MODULE_LICENSE("GPL");
```

Every symbol it imports is exported by 7.3.4 (`v7.3.4/drivers/fpga/fpga-mgr.c:125,145,584,729,740,763,773`)
**[V]**. Before it lands it needs a decision on where the interface lives (a misc device is the
smallest choice, not necessarily the right one for Main_MiSTer) and a quiesce step for whatever
is using the fabric.

## Appendix B. Verification record

Run on 2026-11-17 in a scratch directory; none of it writes to the repo.

| What | How | Result |
|---|---|---|
| Kernel patch series | `work/buildroot/support/scripts/apply-patches.sh` on pristine `linux-7.3.4` | 39 of 39 applied, no fuzz, no rejects |
| Patch headers | `scripts/lint-kernel-patches.sh board/mister/de25nano/linux-patches board/mister/de25nano/patches/arm-trusted-firmware` | pass, 41 patches |
| Defconfigs | `scripts/check-defconfigs.sh` | OK |
| Board DTB | `cpp` + `dtc` with the kernel's `W=1` checks, before and after | 0 warnings both times; the decompiled diff is the svc compatible, the two `dma-coherent` removals, `cap-sd-highspeed`, and the caps mask — nothing else |
| `dtbs_check` | kbuild `CHECK_DTBS=y` on 7.3.4 + the series, dtschema 2026.9 | the same 5 `fpga-mgr` two-string warnings before and after |
| U-Boot DTB | `cpp` + `dtc` against the 2026.07 tree with the resolved DE25 config | compiles; the only difference is the new `sdhci-caps-mask` |
| Kernel config | `merge_config.sh -m` + `olddefconfig`, arm64, before and after | all 494 requested symbols survive; the resolved difference is the five PHY drivers and their helper; the `MEDIA_SUPPORT` redefinition warning is gone |
| TF-A | see §4.1 | applies, builds, harness passes |
| Draft module | `modules_prepare`, then `make M=… W=1`; `checkpatch.pl --strict` | compiles with no compiler warning; 0 errors, 0 warnings, 0 checks |
