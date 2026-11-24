# DE25-Nano device tree — rationale (D2.3 desk half)

The file this document justifies is
[`board/mister/de25nano/socfpga_agilex5_de25nano.dts`](../board/mister/de25nano/socfpga_agilex5_de25nano.dts),
a **mainline** board device tree for the Terasic DE25-Nano on Linux 7.3.x.

> **Updated 2026-11-17** after the vendor-kernel comparison in
> [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md). Five things changed in the
> board file, and the sections below say where:
>
> 1. `/firmware/svc` is now `compatible = "intel,agilex-svc"` and kernel patch `0102` is gone
>    (§3 "The svc node", [ADR 0034](decisions/0034-de25-fpga-service-path.md)).
> 2. §4's claim that SMMU-off is the one shape in which mainline can program the fabric was
>    wrong as written. With stock TF-A it fails in **every** SMMU mode; the fix is in BL31 (§4.1).
> 3. `dma-coherent` is removed from `mmc0` and deleted on `gmac0` for first boot (§4.5).
> 4. `mmc0` runs default speed only: `cap-sd-highspeed` is gone and the caps mask clears bit 21
>    (§3 `mmc0` rows, [U3]).
> 5. The long comment blocks moved out of the DTS into this document; the file now carries
>    one- and two-line comments only.
>
> The pin is 7.3.4. **Line citations into `linux-7.2.2` in §1–§3 were not re-anchored** and are
> still labelled 7.2.2; anything cited as 7.3.4 was read for this update. The `dtbs_check` and
> structural results in §2 were re-run at 7.3.4 and are restated in §2.6.
>
> **Later on 2026-11-17 the pin moved to 7.4-rc3** and `mmc0` was rewritten for v7.4's SD6HC
> driver (`altr,agilex5-sd6hc`; kernel patch `0101` dropped). §2.7 records that change and its
> checks; every SD4HC statement elsewhere in this document describes the 7.3.4 node.
>
> **2026-11-24:** `mmc0` moved to SD high speed at 50 MHz (§2.8), and the HPS on-chip RAM
> became a `mister_ocram` UIO node (the `/mister` section of §3). U3, U11 and U12 are closed.

The device tree is the highest-risk file on a new board: a wrong value here does not fail the
build, it fails the *board*, and several of the specific mistakes available on this SoC are
silent. This document is the evidence that each node is right, and the record of what was
deliberately **not** copied from the three reference trees that already carry a complete
DE25-Nano DTS.

**Nothing below was written from memory.** Every reference value is quoted from the file named
beside it; every mainline claim is a line citation into `linux-7.2.2` as unpacked from this
repo's own `dl/linux/linux-7.2.2.tar.xz`; every validation result is pasted from a command
transcribed in §1.

Read alongside [`de25-implementation-path.md`](de25-implementation-path.md) §2–§4 and §8, and
[`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.

---

## 0. The four trees

| Column | What it is |
|---|---|
| **MAINLINE** | `linux-7.2.2` — `arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi` (951 lines) and the in-tree board file `socfpga_agilex5_socdk.dts`. The base we `#include` and the baseline we compare warnings against. |
| **TERASIC** | `github.com/terasic/linux-socfpga` @ `de25-nano-6.12.11-lts` — `socfpga_agilex5_de25_nano.dts` (207 lines) + its 1255-line `.dtsi`. The board vendor's own BSP; the SD4HC form. |
| **ALTERA** | `github.com/altera-fpga/linux-socfpga` @ `socfpga-6.18.20-lts` (default branch, `d8e46bd82a1e`) — `socfpga_agilex5_de25_nano.dts` (206 lines) + its `.dtsi`. Altera's in-house cleanup of Terasic's file; newest, and the best *wiring* reference (§4 of the implementation path). Its `mmc0` is **not** usable — see §3. |
| **PORT** | A third-party DE25-Nano Linux port (6.18.38 + vendor backports), consulted read-only; not public — `socfpga_agilex5_de25_nano.dts` (262 lines) + its 1016-line `.dtsi`. TERASIC plus MiSTer-specific additions. The only tree with an *observed SD boot on real DE25 silicon*. |

`OURS` = `MAINLINE` + the board file in this repo. No SoC `.dtsi` is patched: everything is
authored in the board file, by reference (`&label`) or by path (`&{/firmware/svc}`).

---

## 1. Method (reproducible)

Nothing here needs a cross compiler — DTB generation and schema checking are host-only.

```sh
# 0. A private, writable copy of the pinned kernel.  Do NOT use output/build/linux-rt-<version>;
#    that is a live DE10 build tree.
mkdir -p /mnt/source/dts-check-work/t3
tar -xf dl/linux/linux-7.2.2.tar.xz -C /mnt/source/dts-check-work/t3/
cd /mnt/source/dts-check-work/t3/linux-7.2.2

# 1. Drop the board file in and register it.
cp /mnt/source/Buildroot_MiSTer/board/mister/de25nano/socfpga_agilex5_de25nano.dts \
   arch/arm64/boot/dts/intel/
sed -i 's#\t\t\t\tsocfpga_agilex5_socdk.dtb \\#\t\t\t\tsocfpga_agilex5_de25nano.dtb \\\n&#' \
   arch/arm64/boot/dts/intel/Makefile

# 2. Kconfig only needs HOSTCC, so allnoconfig works with no aarch64 toolchain present.
make ARCH=arm64 HOSTCC=gcc allnoconfig

# 3. dtc.  Note the target path is relative to arch/arm64/boot/dts.
make ARCH=arm64 HOSTCC=gcc          intel/socfpga_agilex5_de25nano.dtb   # default DTC_FLAGS
make ARCH=arm64 HOSTCC=gcc W=1      intel/socfpga_agilex5_de25nano.dtb
make ARCH=arm64 HOSTCC=gcc W=2      intel/socfpga_agilex5_de25nano.dtb
# ... and the same three against the in-tree baseline:
make ARCH=arm64 HOSTCC=gcc W=2      intel/socfpga_agilex5_socdk.dtb

# 4. dtbs_check.  Run it BOTH ways.  The carried patches change the *bindings*, so the
#    result is meaningless unless you say which tree you measured.
source /mnt/source/dts-check-work/venv/bin/activate        # dtschema 2026.6
rm -f arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb \
      Documentation/devicetree/bindings/processed-schema.json
make ARCH=arm64 HOSTCC=gcc CHECK_DTBS=y intel/socfpga_agilex5_de25nano.dtb   # stock 7.2.2

for p in 0101-mmc-sdhci-cadence-agilex5-40-bit-dma-mask \
         0102-firmware-stratix10-svc-match-agilex5-svc; do
  patch -p1 < /mnt/source/Buildroot_MiSTer/board/mister/de25nano/linux-patches/$p.patch
done
rm -f arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb \
      Documentation/devicetree/bindings/processed-schema.json
make ARCH=arm64 HOSTCC=gcc CHECK_DTBS=y intel/socfpga_agilex5_de25nano.dtb   # what we ship

# 5. Structural check: decompile what was BUILT and verify the load-bearing node names and
#    that the fpga-mgr phandle resolves.
dtc -I dtb -O dts -o de25nano.decompiled.dts \
    arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb
```

*(The listing above is the 7.2.2 run and names `0102`, which no longer exists. The 2026-11-17
re-run in §2.6 applied the whole DE25 series with `patch -F0` and built the same target.)*

`make ARCH=arm64 defconfig` is **not** usable here (no aarch64 compiler on the host), and is not
needed: `allnoconfig` satisfies kbuild, and the `%.dtb` rule does not depend on `CC`.

---

## 2. Results

### 2.1 `dtc`

| | default `DTC_FLAGS` (what `make dtbs` uses) | `W=1` | `W=2` |
|---|---|---|---|
| MAINLINE baseline (`socfpga_agilex5_socdk.dtb`, unpatched) | **0** | **0** | 6 |
| **OURS** (`socfpga_agilex5_de25nano.dtb`) | **0** | **0** | 6 |
| **new warnings introduced** | **0** | **0** | **0** |

The six `W=2` warnings are all `property_name_chars_strict` on `snps,wr_osr_lmt` /
`snps,rd_osr_lmt` in the three `stmmac-axi-config` nodes of the **shared**
`socfpga_agilex5.dtsi` (`:583,:584,:696,:697,:809,:810`). They are present in the unpatched
baseline, they are upstream's, none of them is ours. Verbatim:

```
arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi:583.5-28: Warning (property_name_chars_strict):
  /soc@0/ethernet@10810000/stmmac-axi-config:snps,wr_osr_lmt: Character '_' not recommended in property name
[... five more, identical shape, at :584 :696 :697 :809 :810]
```

The `unit_address_vs_reg` warning that a naive transcription of the reference files *would*
have introduced (`ethernet-phy@0 { reg = <1>; }` — present in TERASIC, ALTERA **and** PORT)
was fixed before it was committed; see §5 D3.

### 2.2 `dtbs_check`

**Against stock 7.2.2 (no carried patches): 9 warnings.**
**Against 7.2.2 + `0101` + `0102` — the tree we actually ship: 5 warnings.**

| # | Warning (abridged; verbatim text in §2.3) | Node | Class | Disposition |
|---|---|---|---|---|
| 1 | `fpga-mgr:compatible:0: 'intel,agilex5-soc-fpga-mgr' is not one of [...]` (via `intel,stratix10-svc.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Expected per implementation-path §2.5 |
| 2 | `fpga-mgr:compatible: [...] is too long` (via `intel,stratix10-svc.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Same |
| 3 | `compatible:0: 'intel,agilex5-soc-fpga-mgr' is not one of [...]` (via `intel,stratix10-soc-fpga-mgr.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Same |
| 4 | `compatible: [...] is too long` (via `intel,stratix10-soc-fpga-mgr.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Same |
| 5 | `failed to match any schema with compatible: ['intel,agilex5-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr']` | `/firmware/svc/fpga-mgr` | **(a)** | Summary line for 1–4 |
| 6 | `mmc@10808000: compatible:0: 'intel,agilex5-sd4hc' is not one of [...]` | `/soc@0/mmc@10808000` | **(a)** | **Gone with `0101`** |
| 7 | `failed to match any schema with compatible: ['intel,agilex5-sd4hc', 'cdns,sd4hc']` | `/soc@0/mmc@10808000` | **(a)** | Summary line for 6; **gone with `0101`** |
| 8 | `mmc@10808000: clocks: [[7, 40], [7, 78]] is too long` | `/soc@0/mmc@10808000` | **(a)** | **Gone with `0101`** — its binding hunk now widens `clocks` |
| 9 | `mmc@10808000: Unevaluated properties are not allowed ('clock-names', 'dma-coherent', 'iommus' were unexpected)` | `/soc@0/mmc@10808000` | **(a)** | **Gone with `0101`** — it now declares all three |

Counts, stock 7.2.2: **(a) 9 · (b) 0 · (c) 0**.
Counts, 7.2.2 + `0101` + `0102` (shipped): **(a) 5 · (b) 0 · (c) 0**.

Class key, per the task's definitions:

- **(a)** *expected*: the DT form is the forward-correct one; the *binding* has not caught up.
  All five residual warnings are the single known issue from implementation-path §2.5 — the
  two-string `fpga-mgr` compatible against a binding that is still a flat `enum`, reported once
  by each of the two schemas that validate that node and once as a summary.
- **(b)** *inherited from the mainline dtsi*: **none**. Verified by running the same command on
  the stock in-tree board — `make ARCH=arm64 CHECK_DTBS=y intel/socfpga_agilex5_socdk.dtb`
  emits **zero** warnings on 7.2.2. Every warning above is attributable to a node we authored.
- **(c)** *ours to fix*: **none remain**. Four were found and fixed during authoring, before the
  file was written out — the `ethernet-phy@0`/`reg = <1>` mismatch (§5 D3), the `hps0` LED child
  node name, which `leds-gpio.yaml`'s child pattern `(^led-[0-9a-f]$|led)` rejects outright
  under its `additionalProperties: false` (§5 D2), the `mmc0@` node name (§5 D1) and the
  `reset-names`/`fifo-depth` properties `cdns,sdhci.yaml` does not declare (§3).

An earlier revision of this document classified the four `mmc0` warnings as a separate class
"(c′)" — *ours, deliberate, fixable only in a binding we already carry a patch to*. That class
is now **empty**: `linux-patches/0101`'s binding hunk carries the `clocks`/`clock-names`/
`iommus`/`dma-coherent` additions described in §2.4, so all four are gone from the shipped
tree. The classification is kept in the record because it is the shape this kind of finding
takes, and because §2.4's argument is what justified the DT keeping those properties.

### 2.3 Verbatim output (7.2.2 + `0101` + `0102`)

```
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: svc (intel,agilex5-svc): fpga-mgr:compatible:0: 'intel,agilex5-soc-fpga-mgr' is not one of ['intel,stratix10-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr']
	from schema $id: http://devicetree.org/schemas/firmware/intel,stratix10-svc.yaml
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: svc (intel,agilex5-svc): fpga-mgr:compatible: ['intel,agilex5-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr'] is too long
	from schema $id: http://devicetree.org/schemas/firmware/intel,stratix10-svc.yaml
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: fpga-mgr (intel,agilex5-soc-fpga-mgr): compatible:0: 'intel,agilex5-soc-fpga-mgr' is not one of ['intel,stratix10-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr']
	from schema $id: http://devicetree.org/schemas/fpga/intel,stratix10-soc-fpga-mgr.yaml
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: fpga-mgr (intel,agilex5-soc-fpga-mgr): compatible: ['intel,agilex5-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr'] is too long
	from schema $id: http://devicetree.org/schemas/fpga/intel,stratix10-soc-fpga-mgr.yaml
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: /firmware/svc/fpga-mgr: failed to match any schema with compatible: ['intel,agilex5-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr']
```

Stock 7.2.2 additionally emits, and `0101` removes all four:

```
... mmc@10808000 (intel,agilex5-sd4hc): compatible:0: 'intel,agilex5-sd4hc' is not one of ['amd,pensando-elba-sd4hc', ...]
... /soc@0/mmc@10808000: failed to match any schema with compatible: ['intel,agilex5-sd4hc', 'cdns,sd4hc']
... mmc@10808000 (intel,agilex5-sd4hc): clocks: [[7, 40], [7, 78]] is too long
... mmc@10808000 (intel,agilex5-sd4hc): Unevaluated properties are not allowed ('clock-names', 'dma-coherent', 'iommus' were unexpected)
```

### 2.4 Both remaining and removed warnings are *binding* gaps, and both fixes are verified

This was tested, not asserted.

**The four `mmc0` warnings — fixed, in tree.** `cdns,sdhci.yaml` declared `clocks: maxItems: 1`
and no `clock-names`/`iommus`/`dma-coherent`, under `unevaluatedProperties: false`. The
additions now carried by `linux-patches/0101` (whose binding hunk already edits that file to add
`intel,agilex5-sd4hc` to the vendor enum) are:

```yaml
  clocks:
    minItems: 1
    maxItems: 2

  clock-names:
    minItems: 1
    items:
      - const: biu
      - const: ciu

  iommus:
    maxItems: 1

  dma-coherent: true
```

Precedent for each: `clocks`/`clock-names` because the Agilex 5 integration genuinely wires two
clocks (§3, mmc0 row); `iommus: maxItems: 1` because `dwc2.yaml:93` declares exactly that for
the same reason on the same SoC; `dma-coherent: true` because nine existing `mmc/*.yaml`
bindings already do (`arasan,sdhci.yaml:127`, `fsl,esdhc.yaml:78`, `sdhci-am654.yaml:53`, …).
**Verified**: with `0101` applied, `mmc@10808000` produces zero warnings.

**The five `fpga-mgr` warnings — not fixable here.** Restructuring
`intel,stratix10-soc-fpga-mgr.yaml`'s `compatible` from a flat two-value `enum` into the
`oneOf`/`items` shape that Khairul's v6 binding patch proposes (implementation path §2.5) clears
**all five** — confirmed by applying that shape to the scratch tree and re-running, then
reverting. That patch has not landed at 7.2 or at `master`, which is exactly why §2.5
recommends accepting the warning rather than dropping the SoC-specific string. We do not carry a
local binding patch for it because, unlike the `mmc0` case, there is a live upstream series we
would be duplicating and then have to un-carry.


### 2.5 Structural check on the built blob

`dtc -I dtb -O dts` of what was actually built:

```
	firmware {
		svc {
			compatible = "intel,agilex5-svc";
			method = "smc";
			memory-region = <0x03>;
			iommus = <0x04 0x0a>;
			fpga-mgr {
				compatible = "intel,agilex5-soc-fpga-mgr", "intel,agilex-soc-fpga-mgr";
				phandle = <0x17>;
			};
		};
	};
...
	fpga-region {
		compatible = "fpga-region";
		#address-cells = <0x02>;
		#size-cells = <0x02>;
		fpga-mgr = <0x17>;
	};
```

Phandles resolved out of the blob:

| phandle | resolves to |
|---|---|
| `0x17` | `/firmware/svc/fpga-mgr` ✔ — `fpga-region`'s `fpga-mgr` points at the manager |
| `0x04` | `/soc@0/iommu@16000000` (smmu) |
| `0x03` | `/reserved-memory/svcbuffer@0` (`service_reserved`) |
| `0x06` | `/soc@0/rstmgr@10d11000` |
| `0x07` | `/soc@0/clock-controller@10d10000` (clkmgr) |
| `0x16` | `/soc@0/gpio@10c03300/gpio-controller@0` (`portb`) |

Confirmed: the node is literally named **`svc`**, under a node literally named **`firmware`**,
with `method = "smc"` — the three constraints `s10_init()`
(`drivers/fpga/stratix10-soc.c:471`), `stratix10_svc_init()`
(`drivers/firmware/stratix10-svc.c:2086`) and `get_invoke_func()` impose, none of which is
expressed as a compatible and all of which are easy to lose when authoring by hand.

**Coverage audit — every enabled DMA master still carries an `iommus` phandle**, even though
`&smmu` is disabled and they are all inert as shipped. This is what makes the SMMU-on leg of
implementation-path §2.6 step 4 a genuine one-line change (§4.3):

| enabled master | `iommus` (as built) | status |
|---|---|---|
| `/soc@0/ethernet@10810000` | `<&smmu 1>` | okay |
| `/soc@0/mmc@10808000` | `<&smmu 5>` | okay |
| `/soc@0/usb@10b00000` | `<&smmu 6>` | okay |
| `/soc@0/dma-bus@10db0000/dma-controller@0` | `<&smmu 8>` | (no status = enabled) |
| `/soc@0/dma-bus@10db0000/dma-controller@10000` | `<&smmu 9>` | (no status = enabled) |
| `/firmware/svc` | `<&smmu 10>` | (no status = enabled) |
| `/soc@0/iommu@16000000` (the SMMU itself) | — | **disabled** |

All six `iommus` phandles resolve to `0x04` = `/soc@0/iommu@16000000`, confirmed with `fdtget`
against the built blob.

Node statuses, read back out of the blob with `fdtget`: `serial@10c02100` okay,
`serial@10c02000` disabled, `ethernet@10810000` okay, `usb@10b00000` okay, `i2c@10c02900` okay,
`gpio@10c03300` okay, `gpio@10c03200` disabled, **`iommu@16000000` disabled**, `mmc@10808000`
okay (with `max-frequency = <0x17d7840>` = 25 000 000), `spi@108d2000` (qspi) disabled,
`watchdog@10d00200`…`watchdog@10d00600` okay, `nand-controller@10b80000` disabled.

### 2.6 Re-run at 7.3.4 (2026-11-17)

Run on a pristine `linux-7.3.4` with the DE25 patch series applied (39 patches, `0102` no longer
among them), dtschema 2026.9, before and after the 2026-11-17 board-file change.

- **`dtc`** with the kernel's `W=1` check set: **0 warnings** before and after.
- **`dtbs_check`**: the same **5** `fpga-mgr` two-string warnings before and after. The only
  textual difference is that two of them now name the parent as `svc (intel,agilex-svc)`. No
  warning concerns the `svc` node's own properties, and none concerns `mmc@10808000`.
- **Decompiled blob, before against after** — the whole difference:

```
 svc {
-        compatible = "intel,agilex5-svc";
+        compatible = "intel,agilex-svc";
 ethernet@10810000 {
-        dma-coherent;
 mmc@10808000 {
-        cap-sd-highspeed;
-        dma-coherent;
-        sdhci-caps-mask = <0x2000 0xff00>;
+        sdhci-caps-mask = <0x2000 0x20ff00>;
```

Every `iommus` phandle in the §2.5 coverage table is still present. The listing at the top of
§2.5 is the 7.2.2 blob and shows the old svc compatible.

### 2.7 `mmc0` rewritten for SD6HC at 7.4-rc3 (2026-11-17)

v7.4 adds `Documentation/devicetree/bindings/mmc/cdns,sd6hc.yaml` and an
`altr,agilex5-sd6hc` match in `drivers/mmc/host/sdhci-cadence-core.c` (driver data: 40-bit DMA
mask, `SDHCI_QUIRK_CAP_CLOCK_BASE_BROKEN` with the base clock taken from `ciu`, ACMD12/ACMD23
quirks, and an init hook that asserts and releases all three resets together). The node now
follows the binding exactly, and matches Altera's own 6.18 dtsi node for the same block:

```
 mmc@10808000 {
-        compatible = "intel,agilex5-sd4hc", "cdns,sd4hc";
-        resets = <&rst SDMMC_RESET>;
-        clocks = <&clkmgr AGILEX5_L4_MP_CLK>, <&clkmgr AGILEX5_SDMCLK>;
-        clock-names = "biu", "ciu";
+        compatible = "altr,agilex5-sd6hc", "cdns,sd6hc";
+        resets = <&rst SDMMC_RESET>, <&rst COMBOPHY_RESET>, <&rst SDMMC_OCP_RESET>;
+        reset-names = "sdhc-reset", "combophy", "sdmmc-ocp";
+        clocks = <&clkmgr AGILEX5_SDMCLK>, <&clkmgr AGILEX5_L4_MP_CLK>;
+        clock-names = "ciu", "biu";
```

Unchanged on purpose: no `dma-coherent` (§4.5), default speed at 25 MHz with `no-1-8-v` and the
caps mask clearing bit 21 ([U3]). The `sdhci-caps` base-clock override is now inert (the quirk
ignores the capability's base-clock field) and is kept as harmless. None of the binding's
`cdns,iocell-*`/`cdns,delay-element-ps` properties is set, so the driver's defaults apply
**[U — first bench test]**. The probe-time reset means Linux no longer depends on U-Boot's PHY
state, which retires the "inherited PHY" risk of §3 for this pin.

Checks: compiled with the 7.4-rc3 tree's own `dtc` with default checks plus
`avoid_unnecessary_addr_size`, `alias_paths`, `unique_unit_address` and `unit_address_vs_reg`:
**0 warnings**, and byte-identical to the DTB `make de25` built. Then, by the §1 method on a
pristine `linux-7.4-rc3` (no DE25 patch touches a binding any more, so stock = shipped):
`W=1` 0 warnings; `W=2` only the six `snps,*_osr_lmt` property-name warnings from mainline's
own dtsi, the same six the in-tree SoCDK board shows; **`dtbs_check` (dtschema 2026.9): the same
5 `fpga-mgr` two-string warnings as at 7.3.4 (§2.6) and nothing else** — none for `svc` or
`mmc@10808000`, which validates cleanly against `cdns,sd6hc.yaml`. Not run on hardware.

### 2.8 `mmc0` at SD high speed, 50 MHz (2026-11-24)

```
-        max-frequency = <25000000>;
+        max-frequency = <50000000>;
+        cap-sd-highspeed;
-        sdhci-caps-mask = <0x00002000 0x0020ff00>;
+        sdhci-caps-mask = <0x00002000 0x0000ff00>;
```

**Why the stages no longer have to match.** v7.4's `sdhci-cadence-phy-v6.c` computes the PHY
and `HRS` timings from the card clock period. `sdhci_cdns6_set_clock()` and
`sdhci_cdns6_set_uhs_signaling()` call `sdhci_cdns6_phy_reconfigure()`, which rewrites the PHY
registers and `HRS07`/`09`/`10`/`16` whenever the clock or timing changes. None of it is read
from DT. The #318 tester's T0 capture showed that the SDHCI soft reset at probe zeroes
`HRS07`/`10`/`16` anyway. So Linux never runs on U-Boot's values, and it can pick its own mode.

**Evidence [V on hardware, #318].** On 7.4-rc4 after a UHS SDR50 U-Boot, a full 32 GB
`dd if=/dev/mmcblk0` read had no errors and a clean `dmesg`:
- 12.0 MB/s at default speed, 25 MHz (the old node);
- 23.5 MB/s with the same change on the tester's tree, and 23.6 MB/s on master `c197eff`.

**Not done.** UHS stays off under Linux. `no-1-8-v` stays, and there is no `vqmmc-supply` for
ALTERA's level shifter (U4). Caps1 bit 13 (use tuning for SDR50) stays masked. The `sdhci-caps`
base-clock override is still inert.

---

## 3. Node-by-node

`—` = absent from that tree. "MAINLINE" means `socfpga_agilex5.dtsi` at 7.2.2 unless a board
file is named.

| Node / property | Source | Verdict | Why |
|---|---|---|---|
| `#include "socfpga_agilex5.dtsi"` | all three | **kept** | The board file patches no SoC `.dtsi`. Everything is a reference or a path override. |
| `model` | — | **changed** | `"Terasic DE25-Nano"`. All three references say `"SoCFPGA Agilex5 Terasic DE25-Nano"`; ours is the board name, which is what `/proc/device-tree/model` should read. |
| root `compatible` | all three | **kept** (`intel,socfpga-agilex5-socdk`, `intel,socfpga-agilex5`) | Factually wrong — this is not an SoCDK — but `Documentation/devicetree/bindings/arm/altera.yaml:109-117` is a **closed five-value enum** for Agilex 5 boards, so `terasic,de25-nano` would fail dtbs_check for zero gain: arm64 has no `DT_MACHINE_START` table, so nothing matches on it. Board identity lives in `model`. The honest fix is a one-line upstream `altera.yaml` patch; see §7 U6. |
| `aliases/serial0 = &uart1` | TERASIC + ALTERA + PORT | **kept** | See "Console UART" below. |
| `aliases/ethernet0 = &gmac0` | TERASIC + ALTERA + PORT | **kept** | **Load-bearing.** U-Boot's `fdt_fixup_ethernet()` walks `/aliases` for `ethernetN` and writes `$ethaddr` into the node it names. Without it the MAC is never injected — the identical DE10 lesson, [`dts-comparison.md`](dts-comparison.md) §3.3. |
| `aliases/i2c1 = &i2c1` | ALTERA only | **kept** | Pins the one enabled adapter to `/dev/i2c-1` instead of dynamic numbering. The DE10's A14 ([`dts-comparison.md`](dts-comparison.md) §2) is the standing lesson that i²C adapter numbering is worth making deterministic. Either way it lands inside `0..2`. |
| `chosen/stdout-path` | all three | **kept** | `"serial0:115200n8"`. |
| `chosen/bootargs` | TERASIC + PORT | **dropped** | Self-contradictory *and* dead. Their string sets `console=`/`earlycon=` to `0x10c02000` (= **uart0**) while their own `stdout-path` resolves to uart1, and U-Boot's `fdt_chosen()` overwrites `/chosen/bootargs` from `$bootargs` regardless. ALTERA's 2025 in-house file already dropped it. |
| `leds { compatible = "gpio-leds" }` | all three | **kept** | |
| LED child node name | ALTERA (`led-0`) | **changed** from TERASIC/PORT (`hps0`) | `leds-gpio.yaml`'s child pattern is `(^led-[0-9a-f]$|led)`; `hps0` matches neither, so the node is rejected by that binding's `additionalProperties: false`. Provably a no-op: the class-device name comes from `label`, so `/sys/class/leds/hps_led0` is unchanged — same ABI as the DE10. |
| `label = "hps_led0"`, `gpios = <&portb 17 GPIO_ACTIVE_LOW>` | all three | **kept** | Identical in all three. |
| `linux,default-trigger = "mmc0"` | — (DE10 stock has it) | **not added** | Out of wave-1 scope (bare developer OS, no MiSTer binaries). One line to add later; the trigger resolves because the mmc core registers a simple trigger named after `dev_name(&host->class_dev)`. |
| `memory@80000000` | — in MAINLINE dtsi | **authored** | See "Memory" below. |
| `base_fpga_region: fpga-region` | TERASIC + ALTERA `.dtsi`; absent from MAINLINE at every base | **authored** | Implementation path §3.1. `compatible = "fpga-region"`, `#address-cells`/`#size-cells` = 2, `fpga-mgr = <&fpga_mgr>`. `fpga-region.yaml` requires exactly `compatible` + `fpga-mgr`; both present. |
| `fpga-bridges`, any bridge node | — | **deliberately absent** | The Cyclone V `fpga_bridge0..3` shape has no Agilex analogue and must not be transliterated ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2). |
| `config-complete-timeout-us` | — | **deliberately absent** | It belongs on the per-core **overlay**, not the base region ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.3). `of-fpga-region.c` reads it from the overlay's target node. |
| `/firmware/svc` `compatible` | — | **overridden** to `intel,agilex-svc` (2026-11-17) | See "The svc node" below. Until 2026-11-17 the file kept mainline's `intel,agilex5-svc` and carried `linux-patches/0102` to make it bind. |
| `/firmware/svc` `method`, `memory-region`, `iommus` | MAINLINE | **kept, inherited** | Not restated in the board file. `method = "smc"` is required or `get_invoke_func()` fails probe `-ENXIO`. `iommus` is required by the binding only for the agilex5 string; it stays legal under `intel,agilex-svc` and is inert as shipped (§4.3). **`memory-region` is not read by the driver** — it uses whatever BL31 answers to `FPGA_CONFIG_GET_MEM` (7.3.4 `stratix10-svc.c:919-923,1010`). [U9] is now closed from source: BL31 answers `0x80400000`, inside `service_reserved`. |
| `fpga_mgr` child | TERASIC/ALTERA (single string) | **changed** | Two-string fallback `"intel,agilex5-soc-fpga-mgr", "intel,agilex-soc-fpga-mgr"`. Binds the **stock** driver: `s10_of_match[]` (`drivers/fpga/stratix10-soc.c:448-452`) carries no `.data` and never branches on which entry matched, and OF matching walks the whole list. Costs a transient dtbs_check warning (§2.5 of the implementation path); avoids a carried match-table line forever. |
| `altr,smmu_enable_quirk` on svc / fpga_mgr | TERASIC | **dropped** | Vendor-live, mainline-inert: `grep -rn smmu_enable_quirk` over mainline 7.2.2 → zero hits. It gates SDM DMA setup in *Terasic's* `stratix10-svc.c`; carrying it onto a mainline driver does nothing. Its existence is evidence for implementation-path §2.6, not a property to copy. |
| `interrupts`/`interrupt-parent` on svc | TERASIC | **dropped** | Not in `intel,stratix10-svc.yaml`, not read by mainline's `stratix10-svc.c`. |
| `hwmon` / `temp_volt` child of svc | TERASIC + PORT | **dropped** | `compatible = "intel,soc64-hwmon"` exists nowhere in mainline, so the whole `&temp_volt { … }` block binds nothing. **Corrected 2026-11-17:** mainline does have an SDM hwmon driver, `socfpga-hwmon`. It needs no DT node — the svc driver creates its device — and it picks its channel table from the svc compatible (7.3.4 `drivers/hwmon/socfpga-hwmon.c:444-447`). Under `intel,agilex-svc` that would be the Agilex 7 table, so `CONFIG_SENSORS_ALTERA_SOCFPGA_HWMON` stays off ([`de25-kernel-config.md`](de25-kernel-config.md) §5.1). |
| `fcs-hal` / `fcs-crypto` children | TERASIC | **dropped** | `intel,agilex5-soc-fcs-hal` likewise absent from mainline. |
| `&smmu` status | all three set `okay` | **changed → `disabled`** | The one design divergence from every reference, **and from mainline 7.3.4**, whose dtsi enables the node (`socfpga_agilex5.dtsi:379-388` has no `status`; the 7.2 dtsi had it disabled). Owner decision ADR 0029 D10, kept by ADR 0034. The reasoning is in §4, corrected 2026-11-17. Every `iommus` property in the tree is kept and goes inert (§4.3), so the SMMU-on fallback is a small change. |
| **`mmc0`** — `compatible` | TERASIC + PORT | **kept exactly** | `"intel,agilex5-sd4hc", "cdns,sd4hc"`, vendor string **first**. That order is the `items: [enum, const]` form `0101` adds to `cdns,sdhci.yaml`, and with `0101` the first entry wins and installs the 40-bit DMA mask. **The block is in fact a Cadence SD6HC** — U-Boot, Altera 6.18 and Linux v7.4 all bind it as `altr,agilex5-sd6hc` / `cdns,sd6hc`. Mainline 7.3.4 has no SD6HC code at all, so this compatible is a deliberate shim onto the SD4HC driver, which works only because that driver never touches the PHY here (see the `cdns,phy-*` row). A lone `cdns,sd4hc` would still bind — `sdhci_cdns_probe()` falls back to `&sdhci_cdns_drv_data` when `of_device_get_match_data()` returns NULL — but without the mask and with four `dtbs_check` warnings. At the 7.4 pin the node is rewritten for the real driver ([`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §6.3). |
| `mmc0` `reg`, `interrupts` | TERASIC + ALTERA + PORT (identical) | **kept** | `0x10808000 0x1000`, `GIC_SPI 96 IRQ_TYPE_LEVEL_HIGH`. |
| `mmc0` node name | — | **changed** | `mmc@10808000`, not the references' `mmc0@10808000`. Generic node name per `mmc-controller.yaml`; the vendor name is not a legal generic-node name and buys nothing. |
| `mmc0` `resets` | TERASIC + PORT | **kept** | `<&rst SDMMC_RESET>`. Inert on this board — `sdhci-cadence` takes the reset only under `MMC_CAP_HW_RESET` (eMMC) — but correct hardware description. ALTERA's three-entry list (`COMBOPHY_RESET`, `SDMMC_OCP_RESET`) targets their SD6HC rewrite. |
| `mmc0` `reset-names = "reset"` | TERASIC + PORT | **dropped** | Not declared in `cdns,sdhci.yaml` (would trip `unevaluatedProperties`), and the driver looks the reset up with `id = NULL`, i.e. by index. |
| `mmc0` `fifo-depth = <0x800>` | TERASIC + ALTERA + PORT | **dropped** | Dead. `grep fifo-depth drivers/mmc/host/sdhci-cadence.c` → zero hits; it is a `dw_mmc` property that travelled here by copy. Same class as the DE10's `speed-mode`/`timeouts` ([`dts-comparison.md`](dts-comparison.md) §4 D3/D4). |
| `mmc0` `#address-cells`/`#size-cells` | all three | **dropped** | The node has no children. Pure `avoid_unnecessary_addr_size` noise. |
| `mmc0` `clocks` + `clock-names` | all three (identical) | **kept, both entries** | `<&clkmgr AGILEX5_L4_MP_CLK>, <&clkmgr AGILEX5_SDMCLK>` / `"biu", "ciu"`. Mainline only ever uses index 0 — `devm_clk_get_enabled(dev, NULL)` (`sdhci-cadence.c:557`) — and on Agilex 5 the second is inert anyway: gate clocks register with `agilex_gateclk_ops` (`clk-gate-s10.c:279`, defined `:117`), which has **no `.enable`/`.disable`**, so `clk_prepare_enable()` is a no-op *and* `clk_disable_unused()` cannot turn `sdmclk` off. Kept because it is the truthful hardware description, it matches all three references including the one that boots, and the binding — not the DT — is what needs widening (§2.4). |
| `mmc0` `iommus` | all three | **kept, inert as shipped** | `&smmu` is disabled, so `of_iommu_xlate()` returns `-ENODEV` and mmc0 DMAs physically. Kept because it is correct hardware description and mandatory the moment `&smmu` is flipped to `okay`. See §4.3. |
| `mmc0` `dma-coherent` | all three | **removed (2026-11-17)** | First boot treats the SD controller as non-coherent. See §4.5. |
| `mmc0` `bus-width = <4>`, `disable-wp` | all three | **kept** | 4-bit microSD, no write-protect switch wired. |
| `mmc0` `cap-sd-highspeed` | TERASIC + ALTERA (PORT drops it) | **removed (2026-11-17), restored 2026-11-24 (§2.8)** | High speed is enabled from **two** independent places: `mmc_of_parse()` sets `MMC_CAP_SD_HIGHSPEED` from this property (7.3.4 `drivers/mmc/core/host.c:350`), and `sdhci.c:4572` sets it from capability bit 21. The earlier text here named only the second and kept the property as harmless; with the bit masked, the property alone would still enable high speed. Both are now off, so the card stays at default speed — the mode U-Boot leaves the PHY in ([U3], [U12]). |
| `mmc0` `no-1-8-v` | TERASIC + PORT | **kept** | 3.3V-only signalling. Also the reason we can safely omit ALTERA's `vqmmc-supply` level-shifter regulator (below). |
| `mmc0` `no-sdio` | TERASIC + PORT | **kept** | SD card slot only; MiSTer WiFi is USB. |
| `mmc0` `sd-uhs-sdr50` | TERASIC | **dropped** | Contradicts `no-1-8-v` in the same node: every UHS mode needs 1.8V signalling, which `MMC_CAP2_NO_1_8_V` bars. Inert, and confusing to leave in. |
| `mmc0` `sdhci-caps` / `sdhci-caps-mask` | TERASIC (ALTERA has a wider mask) | **kept; mask widened (2026-11-17)** | **Live on mainline and probably load-bearing.** `__sdhci_read_caps()` (7.3.4 `drivers/mmc/host/sdhci.c:4161-4174`) applies them to `SDHCI_CAPABILITIES{,_1}`; the uint64 is `<caps1 caps>`. `0xc800` in caps bits 15:8 sets the base clock to `0xc8` = 200 MHz, and `sdhci_cdns_ops` has **no `.get_max_clock`**, so a zero base-clock field would fail probe with `"Hardware doesn't specify base clock frequency"`. The caps1 mask clears bit 13 (`SDHCI_USE_SDR50_TUNING`), TERASIC's value. The caps mask is now `0x0020ff00`: TERASIC's `0xff00` plus bit 21 (`SDHCI_CAN_DO_HISPD`), which is ours. ALTERA masks `0x2007` in caps1, additionally removing SDR50/SDR104/DDR50 — moot under `no-1-8-v`. |
| `mmc0` 40 × `cdns,phy-*` / `cdns,hrs*` | TERASIC + PORT | **dropped — and must stay dropped** | `sdhci-cadence`'s property table knows only eleven `cdns,phy-input-delay-*` / `cdns,phy-dll-delay-*` names (`sdhci-cadence.c:108-119`); not one of the forty is among them, so they would be dead. The eleven it does know must not be added either: they would make the SD4HC driver run its own PHY write handshake against an SD6HC block. With none present the driver leaves the PHY alone, and Linux runs on the state U-Boot programmed ([U12]). |
| `mmc0` `vmmc-supply` / `vqmmc-supply` + `sd_emmc_power` / `sd_io_1v8_reg` regulators | ALTERA only | **dropped** | Would mean authoring a `regulator-fixed` and a `regulator-gpio` (on `portb 3`) that no other reference has and no bench test has exercised. Under `no-1-8-v` the level shifter never has to switch, and U-Boot's own SD boot from the same card demonstrates the hardware default is the 3.3V state. Adding an untested GPIO-driven regulator to the SD path is precisely the change that turns a working boot into a non-booting one. Flagged §7 U4. |
| `mmc0` `max-frequency` | PORT `25000000` (ALTERA `200000000`; TERASIC none) | **`25000000`** | **First-boot risk control.** Mainline 7.3.4 programs none of the SD6HC PHY, so Linux inherits whatever PHY state U-Boot left. Our U-Boot runs default speed at 25 MHz with the default-speed PHY values ([`de25-uboot.md`](de25-uboot.md) §5.1), so Linux is held to the same mode and clock. The PORT reached a working SD only at this cap, per the earlier record. Lift in step with U-Boot ([U3]). ALTERA's `200000000` is a no-op ceiling. |
| `&gmac0` `status`, `phy-mode`, `phy-handle`, `max-frame-size` | all three (identical) | **kept** | `phy-mode = "rgmii"`, **not** `"rgmii-id"`: ALTERA's file states the TX/RX delays are on the PCB, so asking the PHY for internal delay too would double it — the same trap as the DE10's `gmac1` ([`dts-comparison.md`](dts-comparison.md) §3.2). |
| `&gmac0` `dma-coherent` | MAINLINE dtsi (`socfpga_agilex5.dtsi:611`) | **deleted (2026-11-17)** | `/delete-property/ dma-coherent;` in the board file. Same first-boot rule as `mmc0`: §4.5. `usb0` has no `dma-coherent` in mainline, so after this change no enabled DMA master claims coherency. |
| `&gmac0` `mdio0` node name | all three **and MAINLINE's own socdk** (`socfpga_agilex5_socdk.dts:51`) | **kept** | Does not match `mdio.yaml`'s `$nodename` pattern, but it is what the in-tree board uses, so the shape is upstream's, not ours — and dtbs_check does not in fact flag it. Cosmetic at runtime: `stmmac_of_get_mdio()` (`stmmac_platform.c:295-318`) finds the node by scanning children for `compatible = "snps,dwmac-mdio"`, never by name. |
| `ethernet-phy@0 { reg = <1>; }` | all three | **changed → `ethernet-phy@1`** | A unit-address/`reg` mismatch that dtc reports under `-Wunit_address_vs_reg`. PHY address **1** is the real value (all three agree on `reg`); only the unit address was wrong. Provably a no-op — `of_mdiobus_register()` addresses the PHY from `reg`. See §5 D3. |
| `&gmac1`, `&gmac2` | — | **left disabled** | One RJ45 on this board; MAINLINE's default is disabled. |
| `&gpio1 { status = "okay" }` | all three | **kept** | Provides `portb`, which `led-0` uses. `gpio0` stays disabled (all three). |
| `&i2c1 { status = "okay" }` | all three | **kept** | The only i²C bus enabled ⇒ exactly one adapter, pinned to 1 by the alias. |
| `&uart1 { status = "okay" }` | all three | **kept** | Console. `uart0` left disabled (MAINLINE default) — see "Console UART". |
| `&usb0 { status = "okay"; disable-over-current }` | all three | **kept** | `disable-over-current` is live (`Documentation/devicetree/bindings/usb/dwc2.yaml:89`). No `dr_mode`: none of the three sets one, so dwc2 reads the OTG capability out of the hardware. Flagged §7 U5. |
| `&watchdog0..4 { status = "okay" }` | all three | **kept, all five** | Deliberate parity with a safety argument: `dw_wdt` sets `WDOG_HW_RUNNING` when it finds the watchdog already started by firmware, and the watchdog core then pets it until userspace opens the device. A watchdog started by the SPL whose node is **disabled** in Linux is never petted and resets the board. Enabling costs a `/dev/watchdogN`; not enabling could cost a boot. |
| `disable-over-current` on `&watchdog4` | TERASIC → ALTERA → PORT | **dropped** | A copy-paste of the `usb0` property onto a watchdog. Meaningless to `snps,dw-wdt`, absent from its binding, propagated unchanged through all three trees. |
| `&osc1 { clock-frequency = <25000000> }` | all three | **kept** | MAINLINE declares `osc1` as a `fixed-clock` with `clock-frequency = <0>` (`socfpga_agilex5.dtsi:139-143`); it is the root of the peripheral clock tree, so leaving it at 0 gives a zero rate everywhere downstream. Exactly the `osc1` question [`dts-comparison.md`](dts-comparison.md) §4.1 asked for the DE10 — and here, unlike there, the answer is that it *does* need setting. |
| `&qspi` + `flash@0` + partitions | ALTERA only | **dropped** | Not in the §3.1 node set; TERASIC and PORT both leave QSPI disabled. Enabling it exposes the **factory boot image** to `/dev/mtd` writes, and the QSPI contents are the board's un-recoverable-without-Quartus state ([`de25-boot-chain.md`](de25-boot-chain.md) §7 rows 14/15). Nothing in wave 1 needs it. |
| `mister_fb`, `ascal_scratch`, `x86ram`, `mister_fb_mem` reserved regions | PORT only | **same addresses, our names (2026-11-24)** | Not copied. The DTS carries the DE10's tile and UIO names at PORT's addresses: scaler scratch `0x9E00_0000` +32 MiB, fb `0xA000_0000` +32 MiB with the `MiSTer_fb` node over its first 8 MiB, the core window `0xB000_0000` +256 MiB. See "The video layout" below and [`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7. |
| `&i2c1`'s vendor `status` whitespace, `&mmc` label | — | n/a | We define our own label `mmc0`; the references' `&mmc` label lives in a `.dtsi` we do not patch. |

### The MiSTer `/mister` group, the f2h lines and the HPS key (2026-11-17)

The last `/ { }` block adds the MiSTer HPS<->FPGA interface with the DE10's node and UIO names,
so the shared udev rule builds the same `/dev/mister/*`; addresses, the SPI `17 + N` evidence and
the SError hazard are in [`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7, not
repeated here. Beside it, `gpio-keys` declares `hps_key0` on HPS GPIO40 (`portb` 16, beside the
LED on 17), which the public port wires to the board's HPS key; `GPIO_ACTIVE_LOW` is assumed from
the LED and is **[U]**. The G-sensor behind HPS GPIO34's I2C enable is not described (part
unidentified). Checks on the extended tree: `dtc` with the §1 warning set, 0 warnings;
`dt-validate` (dtschema 2026.9) adds only `generic-uio` noise — 67 `linux,uio-name` "not of type"
lines and one unknown-vendor `mister,map-writecombine`, because `generic-uio` has no binding (the
DE10's `0072` draws the same) — beside the §2.7 `fpga-mgr` five; `gpio-keys` and
`reserved-memory` validate clean.

**The on-chip RAM (2026-11-24).** Agilex 5's OCRAM is 512 KiB at physical `0x0`
(`socfpga_agilex5.dtsi` `ocram: sram@0`, `mmio-sram`). `/mister/ocram@0` exposes
`0x00000..0x7efff` as `mister_ocram`, which is `/dev/mister/ocram` through the existing rule.
Two `reg`-only children of `&ocram`, `mister-ocram@0` and `handoff-sram@7f000`, leave the
kernel's sram pool empty. The page left out is the SPL handoff block (`SOC64_HANDOFF_BASE` =
`0x7f000` on Agilex 5). The interface doc, `dts-mister-fpga-interface.md` §7, has the
boot-stage usage and the hazards.

### The video layout — PORT's addresses, so PORT's bitstreams and Main run here (2026-11-24)

**Goal: compatibility.** PORT's fabric and its Main_MiSTer build must run on this image
unchanged, and greenfield's DE25 row follows the same map. The addresses are facts read from
PORT's fabric top, its Main and its board DTS; nothing was copied. The full table is in
[`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7. In short:

- **Scaler scratch, `mister-scaler@9e000000`, 32 MiB.** PORT's ascal has `RAMSIZE` = 32 MiB and
  adds the base the HPS writes into the fbcfg mailbox (LW `0x2001_0200`) to every access. PORT's
  Main reads that word to find the scaler. 32 MiB from `0x9E00_0000` ends at `0xA000_0000`, so the
  scratch covers the old `ddr-low`/handoff addresses; those two moved down by 32 MiB, to
  `0x9DF0_0000` and `0x9DFF_F000`, and `mem=` went from `511M` to `479M` to stay below them.
- **Framebuffer, `mister-fb@a0000000`, 32 MiB.** PORT's Main sets `FB_ADDR = 0xA000_0000` and maps
  three 1080p 8888 buffers there. A root node `mister-fb@a0000000` (`compatible = "MiSTer_fb"`)
  covers buffer 0 only, 8 MiB, as the DE10's stock node does, so `/dev/fb0`'s `smem_start` is
  `0xA000_1000`, the address PORT's Main hands the scaler for buffer 0. No `interrupts`: PORT has
  no vsync line, and a declared line that never fires would make every `FBIO_WAITFORVSYNC` wait
  the full 50 ms timeout instead of whatever the fabric gives. `f2h_irq[0]` stays free for it.
- **Core DDRAM, `mister-core@b0000000`, 256 MiB.** PORT's fabric relocates a core's DE10 address
  `0x3xxx_xxxx` by setting bit 31, so its window is `0xB000_0000`–`0xBFFF_FFFF`, the DE10's own
  `0x3000_0000` window plus `0x8000_0000`. `mister-core@a2000000` (224 MiB) fills the rest of the
  aperture; PORT gives those bytes to Linux, we keep them reserved so the 512 MiB aperture stays
  whole.

Every window PORT's Main maps through `/dev/mem` is above `mem=` and `no-map`, which is what
`CONFIG_STRICT_DEVMEM=y` needs. Two things PORT does at boot that this image does not do yet:

1. **Program the scaler base.** PORT's `mister-fb` service waits for its MENU fabric, then writes
   `0x9E00_0000` to the fbcfg word. Until something writes it, ascal is gated and PORT's Main falls
   back to the Cyclone V scaler constant. On this image the step is manual (the `devmem` lines in
   `de25-sdcard.md`); a boot service needs a DE25-only overlay, because the DE25 takes the DE10's.
2. **Load `stratix10_rsu`** for its core switching. Not a layout question; not done here.

### The svc node — described as `intel,agilex-svc`

**Changed 2026-11-17 ([ADR 0034](decisions/0034-de25-fpga-service-path.md)).** The board file
overrides one property of the inherited node and adds the `fpga_mgr` child:

```dts
&{/firmware/svc} {
	compatible = "intel,agilex-svc";
	fpga_mgr: fpga-mgr { … };
};
```

`method`, `memory-region` and `iommus = <&smmu 10>` are inherited unchanged.

**What it replaced.** Until this change the file kept mainline's `intel,agilex5-svc` and carried
`linux-patches/0102`, a one-line match-table addition, because that string is in the binding's
enum but was in no driver's match table at 7.3.4 or earlier. The override was the documented
fallback. It is now the plan, for three reasons:

1. **The string selects behaviour, and we need the Agilex behaviour.** Our BL31 (with TF-A patch
   `0002`) serves the physical-address SMC contract (§4.1). From Linux v7.4,
   `intel,agilex5-svc` means something else: probe fails `-ENODEV` unless an IOMMU domain is
   attached, and buffers are IOVAs. With `&smmu` disabled that string would stop probing.
   `intel,agilex-svc` keeps the physical path on every kernel version.
2. **`0102` was wrong about the protocol.** Its message said Agilex 5 speaks the Agilex SMC
   protocol unchanged. BL31's Agilex 5 code handles addresses differently
   ([`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §3.2).
3. **One fewer kernel patch.** On 7.3.4 the match table carries no driver data, so the stock
   driver runs identical code for either string.

**What it costs.** One node names the wrong SoC family. `socfpga-hwmon` would therefore select
the Agilex 7 channel table, so that driver is kept off. On 7.4 and later the node also gets a
PSCI notifier that offlines secondary CPUs on a warm reboot only.

**Schema.** `intel,agilex-svc` is in the binding's enum; `iommus` is required only for the
agilex5 string and stays legal here (7.3.4 `intel,stratix10-svc.yaml:34-37,70-79`). No new
`dtbs_check` warning (§2.6).

**Three structural constraints** ride on this subtree and are all satisfied by mainline's node
shape, which we inherit: the node must literally be named `svc` (7.3.4 `stratix10-soc.c:474`),
its parent must literally be named `firmware` (7.3.4 `stratix10-svc.c:2201`), and `method` must
be present or probe fails.

**The `fpga_mgr` child keeps its two-string form**, `"intel,agilex5-soc-fpga-mgr",
"intel,agilex-soc-fpga-mgr"`. The stock driver binds through the second string (7.3.4
`stratix10-soc.c:451-454`; unchanged at v7.4-rc1). It still costs the five `dtbs_check` warnings
of §2.2.

### Console UART — a documented deviation

The task brief said "uart0 status okay (console)". **The file enables `uart1` instead**, and
leaves `uart0` at MAINLINE's disabled default. The evidence:

- TERASIC, ALTERA and PORT *all three* set `aliases { serial0 = &uart1; }` and
  `&uart1 { status = "okay"; }`, and none of them enables uart0.
- MAINLINE's `socfpga_agilex5_socdk.dts` uses uart0 — but that is a **different board**; HPS
  UART pinmux is board wiring, not SoC wiring.
- The one apparent counter-evidence is TERASIC's/PORT's `bootargs` naming `0x10c02000`
  (uart0). It is self-contradictory with their own `stdout-path` in the same node, and ALTERA's
  2025 in-house rewrite **deleted the bootargs string entirely** while keeping
  `serial0 = &uart1` — the strongest single signal that the bootargs were stale SoCDK residue.
- UART addresses are identical across MAINLINE, TERASIC and PORT (`uart0` = `serial@10c02000`,
  `uart1` = `serial@10c02100`), so this is a pure wiring question, not an addressing one.

**Settled `[V]`, not merely likely.** The DE25 **U-Boot** tree closes it independently of any
Linux DTS: Terasic's public branch (`github.com/terasic/u-boot-socfpga` @ `de25-nano-v2025.01`,
`arch/arm/dts/socfpga_agilex5_de25_nano.dts:11`) has `serial0 = &uart1`, and `...-u-boot.dtsi`
sets `stdout-path = "serial0:115200n8"` — and the PORT booted Linux over that console. A board
whose bootloader console is uart1 does not have its Linux console on uart0. Promoted from `[U]`
in §7.

### Memory

MAINLINE's `.dtsi` has no memory node, so the board file must supply one.

| Tree | value |
|---|---|
| TERASIC, PORT | `memory { reg = <0 0x80000000 0 0x80000000>; }` — 2 GiB, and a node name with no unit address |
| ALTERA, MAINLINE socdk | `memory@80000000 { reg = <0x0 0x80000000 0x0 0x0>; }` — size 0, "we expect the bootloader to fill in the reg" |
| **OURS** | `memory@80000000 { reg = <0x0 0x80000000 0x0 0x40000000>; }` — **1 GiB** |

1 GiB at `0x8000_0000` matches the *UM* and the DE25 **U-Boot** DTS — Terasic's public branch
(`github.com/terasic/u-boot-socfpga` @ `de25-nano-v2025.01`,
`arch/arm/dts/socfpga_agilex5_de25_nano-u-boot.dtsi`), which carries
`memory { /* 1GB */ reg = <0 0x80000000 0 0x40000000>; }`.

**Be precise about what that is.** It is a *declared constant in a bootloader device tree*, not
a measurement, and [`de25-boot-chain.md`](de25-boot-chain.md) §3's `[V SPL-dtb]` tag overstates
it — a correction owed, recorded in §8. The real size is discovered at runtime by the IO96B
controller: `drivers/ddr/altera/sdram_agilex5.c` computes `hw_size` from
`io96b_ctrl->overall_size`, **caps** the DT-declared size at it, and prints
`DDR: Warning: DRAM size from device tree (...) exceeds the actual hardware capacity(...)` on
mismatch. U-Boot then rewrites Linux's node wholesale from `bi_dram` —
`arch/arm/lib/bootm-fdt.c` → `fdt_fixup_memory_banks()`, under `CONFIG_ARCH_FIXUP_FDT_MEMORY`
(default `y`).

So the value here only matters if that fixup does not run. It is still the right value to state:
TERASIC and PORT's 2 GiB over-claims, ALTERA's and MAINLINE socdk's size 0 boots nothing
without the fixup, and under-claiming degrades gracefully where neither of those does.

**First-boot action: capture U-Boot's `DDR:` lines.** They are the only authority on the real
size, and a `DDR: Warning` there is the signal that any of these DTS constants is wrong.

`de25-reference-implementation.md` asked this of the PORT tree ("Does the DE25-Nano HPS
actually have 2 GiB of DRAM?"). Every DE25 bootloader source says 1 GiB, so the port's Linux node
over-claims 2× — but "1 GiB" is itself a vendor declaration awaiting the IO96B readout, not a
measurement, and this document should not launder one into the other.

One consequence worth carrying: **all DRAM lives in `0x8000_0000..0xBFFF_FFFF`, entirely inside
32 bits.** That is what makes the SMMU-off escape hatch in §4 safe.

---

## 4. The SMMU / `mmc0` decision (implementation path §8 Q2 and §8 Q1)

> **Status: owner decision, ADR 0029 D10 (2026-09-02), kept by
> [ADR 0034](decisions/0034-de25-fpga-service-path.md) (2026-11-17).** The SMMU ships disabled.
> DMA isolation is a non-goal for this image (the DE10's Cyclone V has no SMMU, so this is
> parity, not a regression). D10's re-open condition — upstream `svc` growing IOMMU-aware buffer
> handling — **is met from Linux v7.4**, so the decision is re-examined at that pin move.

**Decision: `&smmu { status = "disabled"; }`.** This diverges from all three references and from
mainline 7.3.4, whose dtsi enables the node. Every `iommus` property in the tree is kept and is
inert.

**Corrected 2026-11-17.** This section used to argue that SMMU-on cannot work on mainline and
that SMMU-off is the only shape that can. The first half still holds at 7.3.4. The second half
was wrong as written: **with stock TF-A v2.15.0, mainline cannot program the fabric in any SMMU
mode**, because of two address-handling mismatches in BL31. By the same reading,
`iommu.passthrough=1` would not help either. This is read from source and has not been run on a
board. §4.1 has the corrected account.

### 4.1 What actually blocks the mainline path, and what was done

Full trace with line citations: [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §3.
In short, at 7.3.4:

| Step | Kernel | BL31 v2.15.0 on Agilex 5 |
|---|---|---|
| 1 | Asks for a buffer window with `FPGA_CONFIG_GET_MEM` and builds a pool of **physical** addresses over it (`stratix10-svc.c:919-923,1010`) | Answers `0x80400000`, ending at `0x82000000` |
| 2 | Submits each buffer's physical address with `FPGA_CONFIG_WRITE` (`:626-629`) | **Rejects** every address below `BL31_LIMIT` = `0x82000000` — the whole window it advertised |
| 3 | Gets no callback for a rejected data submit (`:833-851`); the FPGA manager times out after 5 s | — |
| 4 | Looks completed addresses up by exact match (`:321-332`) | Returns each address with `0x80000000` **subtracted** |
| 5 | No buffer is ever unlocked; over 2 MiB the write loop spins (`stratix10-soc.c:256,296-297`) | — |

Steps 2 and 4 are firmware behaviour and do not depend on the SMMU. They are why the vendor
driver adds `0x80000000` to an IOVA: the sum clears BL31's range check, and BL31's subtraction
hands the IOVA back.

**With the SMMU on there is a further problem at 7.3.4**, the one this section originally
described: the service device inherits `iommus = <&smmu 10>`, gets a translated default domain
over an empty page table, and the physical addresses it submits are unmapped IOVAs. That part
of the earlier analysis stands. From v7.4 the upstream driver handles it for the
`intel,agilex5-svc` string.

**What was done.** TF-A patch `0002` makes BL31 accept the advertised window and return the
caller's own address ([`de25-uboot.md`](de25-uboot.md) §8). The service node is described as
`intel,agilex-svc` so the kernel keeps using that physical contract (§3, "The svc node").

**The observed `RECONFIG_REQUEST` timeout is not explained by this.** That failure
(implementation path §2.6) happens before any data submit. It was seen on a 6.18-class driver
whose request timeout was 300 ms; 7.3.4 waits 5000 ms (`stratix10-svc-client.h:71`).

### 4.2 Is the SMMU needed by the hardware? Probably not; unproven

- **For SMMU-off:** BL31 has a mode that does not involve the SMMU. Unless a caller asks for
  bypass, it programs the SDM address remapper with the DDR base and gives the SDM an address
  relative to it. U-Boot's `fpga load` uses exactly that path with a raw DDR address, and never
  enables the SMMU. An earlier port recorded successful U-Boot loads on this board; a later
  note from the same source says a U-Boot load wedged the SDM
  ([`de25-boot-chain.md`](de25-boot-chain.md) §7b F1).
- **Against:** the vendor kernel refuses to run without the SMMU, and so does v7.4's driver for
  the agilex5 string. Both are policy in a driver, not a statement about the hardware. What is
  genuinely unknown is the silicon revision, the state of the revision-A workaround bit, and
  whether the SMMU's reset state passes or aborts untranslated traffic ([U11]).

**Test order.** Register reads and `fpga load` at the U-Boot prompt first, then Linux. See
[`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §8, which replaces the SMMU-off /
SMMU-on ordering this section used to give.

### 4.3 Why every `iommus` property stays anyway

With `&smmu` disabled, `of_iommu_xlate()` returns `-ENODEV` for the unavailable IOMMU node
(`drivers/iommu/of_iommu.c:28-29`) and `of_iommu_configure()` treats `-ENODEV` as "this device
has no IOMMU", not as an error. Every `iommus` phandle in the tree therefore goes inert at once,
with no per-node edits, and every master DMAs physically.

Deleting them would be actively wrong, because the SMMU-on leg of the test must be a **one-line
change**: `arm_smmu_init_initial_stes()` fills *every* stream-table entry with
`arm_smmu_make_abort_ste()` (`arm-smmu-v3.c:1925-1934`, called from `:1955` for two-level tables
and `:4489` for linear ones), so under an enabled SMMU a master with no `iommus` property does
not bypass — it **aborts**. The tree as shipped is correct for both configurations; only
`&smmu`'s `status` selects between them.

*(2026-11-17: true for every peripheral. For FPGA programming the SMMU-on shape needs two more
things: the service node back on `intel,agilex5-svc`, and a kernel whose service driver maps
its buffers — v7.4 or a backport. See
[`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §6.3 and §8, test T5.)*

### 4.4 What this does to §8 Q2 (the `mmc0` DMA width)

With the SMMU off, the §8 Q2 failure mode **cannot occur**: the mechanism is the IOVA allocator
handing out an address above bit 39 that a 40-bit-wired controller truncates, and with no
translation there are no IOVAs. Every DRAM address on this board is inside
`0x8000_0000..0xBFFF_FFFF` (§3, Memory), i.e. well inside 32 bits.

`linux-patches/0101` is still correct and still wanted — it is what makes the SMMU-on leg
survivable, and it is what makes the two-string compatible schema-clean — it is simply not
load-bearing in the shipped configuration.

### 4.5 `dma-coherent` — removed for first boot

**Changed 2026-11-17.** `mmc0` no longer has `dma-coherent`, and `&gmac0` deletes the property
it inherits from mainline's dtsi. Until this change both were kept, with [U2] open.

- **The asymmetry decides it.** `dma-coherent` on a master that is not coherent corrupts data
  silently. Leaving it off a master that is coherent is always correct and only slower, because
  the kernel then does the cache maintenance itself.
- **Nobody has measured the shape we ship.** Mainline and all three vendor trees assert the
  property with the SMMU **on**. We run with it off.
- **The only DE25 evidence for an untranslated shape is non-coherent.** The public vendor-kernel
  port (`github.com/ahmadexp/MiSTer-DE25-Nano`) runs `gmac0` and the SD controller with no
  translation and with `dma-coherent` deleted. U-Boot also treats its DMA as non-coherent. The
  earlier port's setup notes recorded SD ADMA corruption under `iommu.passthrough=1` after a
  JTAG load, which is a failure in exactly this area.

A first boot that corrupts the root filesystem is the hardest failure to diagnose, so the first
boot does not take the risk. Restoring the property on each master is an A/B measurement after
a clean first boot ([U2]), not a default.

`usb0` has no `dma-coherent` in mainline, so nothing changes there.


## 5. Deliberate divergences from the reference files

Every difference a node-by-node diff against TERASIC/ALTERA/PORT turns up, accounted for.
D1–D6 are changes of *form*; the content drops are in §3.

| # | Divergence | Why |
|---|---|---|
| D1 | `mmc0@10808000` → **`mmc@10808000`** | Generic node name (`mmc-controller.yaml`). The device is named from the translated `reg`, not the node name, so `10808000.mmc` either way. |
| D2 | LED child `hps0` → **`led-0`** (ALTERA's form) | `leds-gpio.yaml` child pattern `(^led-[0-9a-f]$|led)`; `hps0` is rejected under `additionalProperties: false`. ABI unchanged: `/sys/class/leds/hps_led0` comes from `label`. |
| D3 | `ethernet-phy@0 { reg = <1>; }` → **`ethernet-phy@1 { reg = <1>; }`** | Silences `-Wunit_address_vs_reg`, which is the one dtc warning a verbatim transcription would have added. Provably a no-op: `of_mdiobus_register()` addresses PHYs from `reg`. All three references carry the mismatch. |
| D4 | `memory { … }` → **`memory@80000000 { … }`**, and 2 GiB → **1 GiB** | Unit address for dtc; size from the factory SPL DTB (§3, Memory). `memory@80000000` is still found by both consumers — Linux scans `device_type = "memory"`, and U-Boot's `fdt_fixup_memory_banks()` uses libfdt's `fdt_subnode_offset()`, whose name comparison accepts a trailing `@unit-address`. |
| D5 | `model` `"SoCFPGA Agilex5 Terasic DE25-Nano"` → **`"Terasic DE25-Nano"`** | Cosmetic; the board's name rather than a compilation of SoC and board. |
| D6 | `&watchdog4` loses `disable-over-current` | A watchdog has no over-current line. Copy-paste from `usb0`, propagated through all three trees. |
| D7 | `&smmu` `okay` → **`disabled`** | The one *design* divergence, not a form one, and a divergence from mainline 7.3.4's dtsi as well as from the references (§4). All `iommus` properties retained so the reverse is a small change. |
| D8 | `mmc0` gains **`max-frequency = <25000000>`** | Mainline programs none of the SD6HC PHY, so Linux runs the mode and clock U-Boot ended in (§3, `max-frequency` row). Lift once [U3] clears, in both stages together. |
| D9 | `/firmware/svc` `compatible` → **`intel,agilex-svc`** (2026-11-17) | Selects the physical-address SMC path our patched BL31 serves, on every kernel version; replaces kernel patch `0102` (§3, "The svc node"). |
| D10 | `mmc0` and `gmac0` lose **`dma-coherent`** (2026-11-17) | Unmeasured with the SMMU off; non-coherent is always correct (§4.5). |
| D11 | `mmc0` loses **`cap-sd-highspeed`**, and its caps mask gains bit 21 (2026-11-17) | Default speed only, matching U-Boot, because Linux cannot reprogram the PHY for another mode (§3). |

---

## 6. What this document does **not** prove

- **That the board boots.** Nothing here has run on silicon. This is a desk validation: the DTB
  compiles clean, validates against the bindings modulo two known binding gaps, and its
  load-bearing node names and phandles resolve. Every runtime claim is a citation into driver
  source, not an observation.
- **That the fabric can be programmed.** The `fpga-region`/`fpga_mgr` nodes here are the
  *binding* half. The *programming* half was blocked in BL31 and is now patched there (§4.1);
  that patch is verified by build and by a host harness only. Hardware tests T1 and T3 in
  [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §8 are the experiment.
- **That `mmc0` works at all on 7.3.4.** Linux inherits the SD6HC PHY state from U-Boot and
  resets the SDHCI block at probe. Whether that reset clears the PHY state is unknown ([U12]).
  If it does, this kernel cannot use the card slot without the SD6HC driver.
- **That `mmc0` DMAs correctly.** §4.5 takes the safe side on coherency; [U2] and [U3] record
  what is given up. §8 Q2's failure mode is out of reach with the SMMU off, which is a change of
  exposure, not a proof of correctness.
- **That SMMU-off *works*.** §4.2 gives the reasons to expect it. [U10] and [U11] are the live
  questions.
- **PHY link.** `phy-mode = "rgmii"` with the delays on the PCB is ALTERA's claim, taken on
  their authority and cross-checked against the other two references. Not measured.

---

## 7. Open `[U]` — what could not be settled without hardware

| # | Question | Why it matters | How it is settled |
|---|---|---|---|
| ~~U1~~ | ~~Is the console really `uart1`?~~ | — | **Closed `[V]`.** The DE25 U-Boot tree sets `serial0 = &uart1` and `stdout-path = "serial0:…"` (Terasic's public branch, `github.com/terasic/u-boot-socfpga` @ `de25-nano-v2025.01`, `arch/arm/dts/socfpga_agilex5_de25_nano.dts:11`, `...-u-boot.dtsi`), and the PORT booted Linux on that console. Not to be re-litigated. |
| **U2** | Are the SDMMC and gmac0 masters cache-coherent **with the SMMU off**? | `dma-coherent` on a non-coherent master is silent data corruption. The vendors' evidence is all SMMU-**on**. The PORT's setup guide — the reference DE25 tree's, not the public port's, which has no such file — records ADMA corrupting early SD init under `iommu.passthrough=1` ([`de25-reference-implementation.md`](de25-reference-implementation.md), the "SD host needed capping at 25 MHz" finding). | **Shipped non-coherent since 2026-11-17** (§4.5), so first boot does not depend on the answer. To restore the property: a sustained `dd` round trip with checksum on SD, and a multi-GiB checksummed transfer on Ethernet, each run with and without it. |
| ~~U3~~ | **Closed 2026-11-24 (§2.8):** Linux runs SD high speed at 50 MHz; U-Boot runs UHS SDR50. Can default speed and the 25 MHz cap be lifted? | Shipped at default speed, 25 MHz, in **both** U-Boot and Linux. Mainline 7.3.4 programs none of the SD6HC PHY, so Linux must run the mode U-Boot ended in; U-Boot programs different PHY values per mode. | After a clean sustained `dd` at default speed, climb one step at a time and **change both stages together**: (1) high-speed timing at 25 MHz — drop the bit-21 mask in both device trees and re-add `cap-sd-highspeed` to Linux; (2) 50 MHz in both. Watch for `unrecognised SCR structure version` / `-EINVAL` at init, the symptom the port hit. The real fix is the SD6HC driver at the 7.4 pin. **2026-11-23:** U-Boot alone now ends in UHS SDR50 ([`de25-uboot.md`](de25-uboot.md) §5.1, #318). The tester's 7.4-rc3 kernel, running this DTS unchanged, mounted its root filesystem after that U-Boot, so with the 7.4 driver the two stages no longer have to match. The Linux side of this row is still open. |
| **U4** | Does the SD I/O rail need ALTERA's `regulator-gpio` on `portb 3`? | ALTERA wires `vqmmc-supply` to a 1.8V/3.3V level shifter; we rely on `no-1-8-v` plus the boot-default state. | Only matters if UHS is ever wanted. Until then the shifter never switches. |
| **U5** | `dr_mode` for `usb0` | Unset in all three references, so dwc2 reads OTG capability from the hardware. A MiSTer image wants host mode. | Observe `/sys/class/udc` and whether hubs enumerate; add `dr_mode = "host"` if OTG guesses wrong. |
| **U6** | Should the root compatible say `terasic,de25-nano`? | Currently claims to be an SoCDK. Nothing on arm64 reads it, but it is wrong. | A one-line upstream patch to `Documentation/devicetree/bindings/arm/altera.yaml`, then a one-line DTS change. |
| **U7** | Does `sdhci-caps`' 200 MHz base clock match the silicon? | If the capability register already reports a *different* non-zero base, we override a correct value with a vendor constant and every derived card clock is off — including the 25 MHz cap, which would really be 12.5 MHz if the true base were 100 MHz. | `cat /sys/kernel/debug/mmc0/ios` on first boot; compare `dmesg`'s reported max clock against a raw read of `SDHCI_CAPABILITIES` before the override. |
| **U8** | Do the residual `fpga-mgr` binding warnings get fixed upstream? | Until then this DTB carries 5 warnings and a CI gate would have to allow-list them. | Watch Khairul's v6 fpga-mgr binding series (implementation path §8 Q4). The `mmc0` half is already closed by `0101`. Re-check on every kernel bump. |
| ~~U9~~ | ~~Does BL31 hand back the svc buffer we think it does?~~ **Closed from source 2026-11-17:** TF-A v2.15.0 answers `0x80400000` with length `0x1C00000` (`plat/intel/soc/agilex5/include/socfpga_plat_def.h:43-44`, `plat/intel/soc/common/socfpga_sip_svc.c:1962-1966`), which lies inside `service_reserved` (`0x80000000 + 0x2000000`, `no-map`). The debug-print check below is still worth one look on first boot. Original row follows. | `memory-region = <&service_reserved>` is **dead on mainline**: `stratix10-svc.c:865-876` takes the address from the `FPGA_CONFIG_GET_MEM` SMC and `:952-960` `memremap`s *that*, never consulting the `no-map` reserved region. If our `u-boot.itb`'s BL31 answers with a region other than `0x8000_0000 + 32 MiB`, the driver memremaps **live kernel RAM** and the SDM writes into it. | `dyndbg='file stratix10-svc.c +p'` on the kernel command line, then compare the driver's `"SM software provides paddr"` / `"reserved memory ... paddr"` debug line against `/proc/device-tree/reserved-memory/svcbuffer@0/reg`. Do this **before** the first reconfiguration attempt. |
| **U10** | Can mainline's svc program the fabric, SMMU off, through the patched BL31? | §4.1–§4.2. With stock BL31 it could not, in any SMMU mode; the patch is verified by build and harness only. | Tests T1 (U-Boot `fpga load`) and T3 (Linux load) in [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §8. |
| ~~U11~~ | **Closed 2026-11-24 by T0 (#318):** rev-B silicon, `POR_1` bit 1 clear, remap registers 0, SMMU off with `GBPA.ABORT` = 0. Silicon revision, the revision-A workaround bit, the SDM remap registers, and the SMMU's reset state | They decide whether BL31 programs the remapper and whether untranslated SDM and peripheral traffic passes an SMMU that Linux never enables. If `BOOT_SCRATCH_POR_1` bit 1 is set or `GBPA` resets to abort, the SMMU-on fallback becomes the primary path. | Test T0: `md.l` of `0x10D12210`, `0x10D1225C`, `0x10D12280`/`284`, `0x16000020`, `0x16000044` at the U-Boot prompt. |
| ~~U12~~ | **Closed 2026-11-24 by T0 (#318):** yes, the reset zeroes `HRS07`/`10`/`16`, and 7.4's driver reprograms them (§2.8). Does Linux's SDHCI reset at probe clear the SD6HC `HRS` and PHY registers U-Boot programmed? | If it does, 7.3.4 cannot use the SD card and the SD6HC driver is a first-boot requirement. No source says; the SD4HC precedent suggests the registers survive. | Test T0: dump `HRS`/PHY, write `0x01` to `0x1080822f`, dump again — at the U-Boot prompt, no Linux needed. |


## 8. Corrections owed to sibling documents

| Document | Claim | Correction |
|---|---|---|
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 | The authored node set overrides `/firmware/svc`'s compatible to `"intel,agilex-svc"` | Superseded. We keep MAINLINE's `"intel,agilex5-svc"` and carry `linux-patches/0102` (a one-line match-table addition) instead. The override is retained as the documented fallback. Rationale: the vendor treats the agilex5 string as semantic, so a kernel that will one day want that distinction should not have the DT lie about the SoC. **Reversed again 2026-11-17:** §3.1's override is what ships after all, and `0102` is dropped (see the row added below). |
| [`de25-implementation-path.md`](de25-implementation-path.md) §2.5 | The two-string fpga-mgr form "warns" under `dtbs_check` | Confirmed and quantified: **five** warning lines, from **two** schemas (`intel,stratix10-svc.yaml` validating the child in place, and `intel,stratix10-soc-fpga-mgr.yaml` validating it standalone), plus the "failed to match any schema" summary. Simulating Khairul's v6 `oneOf`/`items` shape clears all five (§2.4). |
| [`de25-reference-implementation.md`](de25-reference-implementation.md) (open question, line ~664) | "Does the DE25-Nano HPS actually have 2 GiB of DRAM? The port's memory node hard-codes `reg = <0 0x80000000 0 0x80000000>`…" | **Answered as far as any desk source can: every DE25 bootloader source says 1 GiB.** The port's Linux node over-claims 2×. Its `x86ram@b0000000 + 0x10000000` ends at `0xC000_0000`, exactly the top of 1 GiB, so it fits; it is the DE10 core window relocated, and our `mister-core@b0000000` reserves the same bytes. Our node states 1 GiB — but see the row below: "1 GiB" is a vendor *declaration*, not a measurement. |
| [`de25-boot-chain.md`](de25-boot-chain.md) §3 | "the factory SPL DTB's memory node reads `reg = <0x0 0x80000000 0x0 0x40000000>` = 1 GiB at 0x8000_0000 **[V SPL-dtb]**" | **The `[V]` overstates it.** That is a *constant in Terasic's U-Boot device tree* (Terasic's public branch, `github.com/terasic/u-boot-socfpga` @ `de25-nano-v2025.01`, `arch/arm/dts/socfpga_agilex5_de25_nano-u-boot.dtsi`, commented `/* 1GB */`), not a readout. The authoritative size comes from the IO96B controller at runtime: `drivers/ddr/altera/sdram_agilex5.c` derives `hw_size` from `io96b_ctrl->overall_size`, caps the DT value at it, and prints `DDR: Warning …` on mismatch. Downgrade to `[V, vendor DTS constant] / [U, hardware]` and capture U-Boot's `DDR:` lines on first boot. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 and §2.6 step 4 | `&smmu { status = "okay"; }` is part of the authored node set, and the two SMMU legs of the programming test are symmetric | **Both corrected.** Mainline's `stratix10-svc` hands the SDM raw physical addresses with no `iommu_map`/`dma_map` anywhere, while the inherited `iommus = <&smmu 10>` puts the svc device on a *translated* default domain — so **SMMU-on cannot program the fabric on a mainline kernel** (§4.1, traced at 7.2.2). Wave 1 ships `status = "disabled"`. The two legs are therefore **not** symmetric: SMMU-off must be run **first**, because a SMMU-on failure is predicted by source and carries no information. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §8 Q2 | The `mmc0` DMA-width question is the leading first-boot risk | Still real, but **not reachable in the shipped configuration**: with the SMMU off there are no IOVAs to truncate and all DRAM is below 4 GiB (§4.4). `linux-patches/0101` remains correct and wanted — it is what makes the SMMU-on leg survivable — but it is not load-bearing for first boot. The *actual* leading first-boot SD risk is PHY timing, which mainline does not program at all; hence the 25 MHz cap ([U3]). |
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 | `memory-region = <&service_reserved>` is part of the svc contract | **It is inert on mainline.** `stratix10-svc.c:865-876` takes the buffer from the `FPGA_CONFIG_GET_MEM` SMC and `:952-960` `memremap`s that; the `no-map` reserved region is never consulted. Whether BL31 actually answers with `service_reserved`'s range is a **hardware check that must precede the first reconfiguration attempt** — [U9]. |
| [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2 | The svc node needs `compatible = "intel,agilex-svc"` authored on top of the in-tree dtsi | Only true on a 6.18 base, where the whole subtree is authored. On 7.x the subtree already exists and is inherited; the only additions are the `fpga_mgr` child and the root `fpga-region`. That section's own `[U]` note about the missing `smmu` node is resolved on 7.2: the node exists with `status = "disabled"`, and the board file deliberately leaves it disabled for wave 1 (§4.1); the SMMU-on form is kept only as the labelled alternative for the second test leg. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §2.6, §8 Q1; ADR 0029 D9/D10 *(added 2026-11-17)* | SMMU-off is the only configuration in which mainline `svc` can program the fabric; `iommu.passthrough=1` is the runtime equivalent | **Incomplete.** With stock TF-A v2.15.0 it fails in every SMMU mode: BL31 rejects the buffer window it advertises and returns rebased completion addresses (§4.1). Fixed in BL31 by TF-A patch `0002`; the four-step test is replaced by T0–T5 in [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md) §8. |
| This document, earlier revisions *(added 2026-11-17)* | The disabled SMMU is "MAINLINE 7.2's own default" | True of the 7.2 dtsi only. At 7.3.4 the node is enabled (`socfpga_agilex5.dtsi:379-388`), so ours is a divergence from mainline. |
| This document and [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 *(added 2026-11-17)* | Keep `intel,agilex5-svc` and carry `0102`; the override is only a fallback | **Reversed** by [ADR 0034](decisions/0034-de25-fpga-service-path.md): the override ships and `0102` is dropped (§3, "The svc node"). |
| This document §3, earlier revisions *(added 2026-11-17)* | `hwmon`: revisit if an SDM hwmon driver lands; `cap-sd-highspeed`: the caps mask is the only lever | Mainline has `socfpga-hwmon` (kept off, wrong channel table under our svc compatible). High speed has two independent enables, the DT property and capability bit 21; both are now off. |
| [`de25-uboot.md`](de25-uboot.md) §5.1 *(added 2026-11-17)* | Leaving `cap-sd-highspeed` out keeps U-Boot at default speed | U-Boot's SDHCI core enables high speed from capability bit 21 regardless of DT (`drivers/mmc/sdhci.c:977-978`). The U-Boot DTS now masks that bit. |
