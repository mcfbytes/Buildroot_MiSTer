# DE25-Nano (Agilex 5) U-Boot mainline issues — materials for upstream reports

Hardware: Terasic DE25-Nano, Intel Agilex 5 (Cortex-A55/A76), 1 GiB LPDDR4.
Boot chain: factory QSPI SPL (Terasic build of u-boot-socfpga de25-nano-v2025.01)
→ mainline U-Boot v2026.07 `u-boot.itb` from SD FAT → extlinux → Linux 7.x.
Vendor reference: https://github.com/terasic/u-boot-socfpga branch `de25-nano-v2025.01`.
Final state on hardware: 10/10 cold boots, SD at UHS SDR50 4-bit, ~1.5 s from
autoboot to kernel handoff.

---

## 1. ComboPHY is missing from mainline entirely (SD link unstable without it)

The Cadence ComboPHY is the analog frontend of the Agilex 5 SDMMC link. The
Terasic tree carries `drivers/phy/cadence/phy-cadence-combophy.c` (852 lines,
`U_BOOT_DRIVER(combophy_phy_provider)`, compatible `"cdns,combophy"`) and their
`sdhci-cadence` requires `phy-names = "combo-phy"` + `phys = <&combophy0>`.

Mainline v2026.07 has: no driver, no dts node, no call from the SDHCI stack.
Measured on identical hardware and card: factory itb (with ComboPHY
programming) detects the SD card 10/10; mainline without it ~2/5 ("No partition
table"). All of: driver port, dts node, and a `generic_phy_get_by_name()` hook
in `sdhci_cdns_probe` are required.

The driver's SDMMC path does: reset assert/deassert → PHY programming via
HRS04/HRS05 → `sdhci_cdns_detect_card`. Its `cdns,phy-*` dts properties are
small bit fields the vendor tree doesn't even set; they are not the mechanism.

## 2. `sdhci-caps-mask` two-cell property is applied with its halves swapped

`drivers/mmc/sdhci.c:sdhci_setup_cfg()`:

```c
dt_caps_mask = dev_read_u64_default(dev, "sdhci-caps-mask", 0);
caps   = ~lower_32_bits(dt_caps_mask) & sdhci_readl(host, SDHCI_CAPABILITIES);
caps_1 = ~upper_32_bits(dt_caps_mask) & sdhci_readl(host, SDHCI_CAPABILITIES_1);
```

`dev_read_u64()` assembles the two `<caps0 caps1>` cells into a big-endian u64,
putting cell 0 into the HIGH half. `lower_32_bits()` therefore returns the
CAPS1 mask (applied to CAPS0) and `upper_32_bits()` the CAPS0 mask (applied to
CAPS1). Every two-cell `sdhci-caps-mask` in every board dts is applied with the
halves swapped; single-purpose masks mostly "worked" by accident because a
nonzero half masked a bit in the wrong register that happened not to matter.

Found on hardware: with CAPS1 = 0x88000077, no masking of the UHS capability
bits was achievable through the property; the card went into UHS SDR104 tuning
attempts (which fail without 1.8 V), leaving the PHY/DLL state broken and
producing "No partition table" on subsequent reads. Fix used:

```c
u32 arr[2] = {0, 0};
dev_read_u32_array(dev, "sdhci-caps-mask", arr, 2);
dt_caps_mask = ((u64)arr[1] << 32) | arr[0];
```

Note the UHS capability bits this tree tests are `SDHCI_SUPPORT_SDR50 = 0x1`,
`SDHCI_SUPPORT_SDR104 = 0x2`, `SDHCI_SUPPORT_DDR50 = 0x4` (CAPS1 bits 0-2), see
`include/sdhci.h` — masks targeting bits 28-31 (e.g. 0xF0000000) cannot ever
remove UHS modes.

## 3. Any real write into the Agilex 5 rstmgr bank registers kills SPTIMER0

`altr,rst-mgr` bank math: `reg = rstmgr_base + offset + (id/32)*4`. Measured on
DE25-Nano hardware:

- offset 0x14 (bank 0 → 0x14, bank 1 → 0x18): the dw-apb-timer's own
  reset-deassert (SPTIMER0_RESET = id 38) writes 0 to 0x10d11018 bit 6, after
  which the SPTIMER0 registers read all-zero: counter stopped, `get_timer()`
  frozen, `udelay()` returns instantly (counter-invert wrap), every
  `readl_poll_timeout()` never expires. Symptom set: "frozen" autoboot
  countdown, silent hangs in PHY polling loops, dead cyclic scheduler.
- offset 0x10 + a real ComboPHY reset cycle (bank 0 → 0x10): also kills it.
- offset 0x24 (bank 0 → 0x24, bank 1 → 0x28): writes land past the register
  block (MPUMODRST..MISCMODRST occupy 0x10-0x23); everything works. This is
  exactly what both mainline `socfpga_agilex5-u-boot.dtsi` AND the Terasic
  de25-nano-v2025.01 tree ship (`altr,modrst-offset = <0x24>`).
- `reset_manager_gen5.h` (map: MPUMODRST 0x10 … MISCMODRST 0x20) is a
  Cyclone V / Arria V header; its bank addresses do not describe the Agilex 5
  rstmgr as observed. The `altr,rst-mgr-agx5.h` reset indices combined with any
  single base offset do not produce correct register addresses for both bank 0
  and bank 1 on this silicon.

Consequence: on Agilex 5 the reset framework can only be used with an offset
that makes all writes no-ops (0x24). A driver that must really toggle a reset
(e.g. ComboPHY at what the agx5 binding calls PER0MODRST, bit 6) has to poke
the register directly. The likely-hybrid true map (PER0MODRST@0x10,
PER1MODRST@0x14, something timer-gating at 0x18 bit 6) needs Intel
documentation to confirm.

## 4. `sdhci-cadence` (sd6hc) needs per-mode PHY values that no in-tree board ships

On this stack the mainline `sdhci_cdns6_phy_init`/`phy_adj` path (DLL reset
dance + HRS09/10/16/07) is required for card detection (without it: -110 on
voltage select). The built-in table defaults (e.g. emmc_sdr: hrs16=0,
hrs07=0x80000 used for UHS SDR50) break 1.8 V 4-bit reads on the DE25; the
SoCDK sd-hs values (dqs 0x780001, gate 0x81a40040, dq 0x10000001, hrs16=0x101,
hrs07=0xA0001), mirrored onto the `*-emmc-sdr` slots, give a stable UHS SDR50
4-bit link. The factory Terasic tree instead avoids the sd6hc helper entirely
(compatible `cdns,sd4hc`, old-style driver) and programs the PHY from the
ComboPHY driver alone.

## 5. Timer nodes must be enabled for U-Boot proper (already partially known)

`timer0..timer3` are `status = "disabled"` in `socfpga_agilex5.dtsi`; with them
disabled `timer_init()` returns -ENODEV, `udelay` never works, and
`wait_for_bit_le32()` inside `reset_deassert_bulk()` spins forever (boot hangs
silently right after BL31). Needs `status = "okay"` + `bootph-all` in the board
-u-boot.dtsi. Worth a dts default or at least a binding-document note, since
the failure mode (silent hang, no console output) gives no clue.

## 6. UHS without regulators

Terasic's de25 dts ships `sd-uhs-sdr50` with NO vmmc/vqmmc regulators and the
factory itb runs SDR50 10/10 on this board — the 1.8 V switch works without a
regulator driver (SDM/hardware managed). Mainline's `sdhci_set_voltage()`
non-DM path also proceeds without one. The common "UHS requires a vqmmc
regulator" assumption does not hold here; mainline's force-clear of UHS caps
when `!(voltages & MMC_VDD_165_195)` (CAPS0 bit 26 is set on this controller)
did not fire either way in our case, but the regulator requirement in
documentation/comments may deserve a caveat.
