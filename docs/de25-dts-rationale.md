# DE25-Nano device tree — rationale (D2.3 desk half)

The file this document justifies is
[`board/mister/de25nano/socfpga_agilex5_de25nano.dts`](../board/mister/de25nano/socfpga_agilex5_de25nano.dts),
a **mainline** board device tree for the Terasic DE25-Nano on Linux 7.2.x.

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
| **FRIEND** | `/mnt/source/de25-linux` (6.18.38 + vendor backports) — `socfpga_agilex5_de25_nano.dts` (262 lines) + its 1016-line `.dtsi`. TERASIC plus MiSTer-specific additions. The only tree with an *observed SD boot on real DE25 silicon*. |

`OURS` = `MAINLINE` + the board file in this repo. No SoC `.dtsi` is patched: everything is
authored in the board file, by reference (`&label`) or by path (`&{/firmware/svc}`).

---

## 1. Method (reproducible)

Nothing here needs a cross compiler — DTB generation and schema checking are host-only.

```sh
# 0. A private, writable copy of the pinned kernel.  Do NOT use output-rt/build/linux-7.2.1;
#    that is a live DE10 build tree.
mkdir -p /mnt/source/de25-work/t3
tar -xf dl/linux/linux-7.2.2.tar.xz -C /mnt/source/de25-work/t3/
cd /mnt/source/de25-work/t3/linux-7.2.2

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
source /mnt/source/de25-work/venv/bin/activate        # dtschema 2026.6
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
have introduced (`ethernet-phy@0 { reg = <1>; }` — present in TERASIC, ALTERA **and** FRIEND)
was fixed before it was committed; see §5 D3.

### 2.2 `dtbs_check`

**Against stock 7.2.2 (no carried patches): 9 warnings.**
**Against 7.2.2 + `0101` + `0102` — the tree we actually ship: 7 warnings.**

| # | Warning (abridged; verbatim text in §2.3) | Node | Class | Disposition |
|---|---|---|---|---|
| 1 | `fpga-mgr:compatible:0: 'intel,agilex5-soc-fpga-mgr' is not one of [...]` (via `intel,stratix10-svc.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Expected per implementation-path §2.5 |
| 2 | `fpga-mgr:compatible: [...] is too long` (via `intel,stratix10-svc.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Same |
| 3 | `compatible:0: 'intel,agilex5-soc-fpga-mgr' is not one of [...]` (via `intel,stratix10-soc-fpga-mgr.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Same |
| 4 | `compatible: [...] is too long` (via `intel,stratix10-soc-fpga-mgr.yaml`) | `/firmware/svc/fpga-mgr` | **(a)** | Same |
| 5 | `failed to match any schema with compatible: ['intel,agilex5-soc-fpga-mgr', 'intel,agilex-soc-fpga-mgr']` | `/firmware/svc/fpga-mgr` | **(a)** | Summary line for 1–4 |
| 6 | `mmc@10808000: clocks: [[7, 40], [7, 78]] is too long` | `/soc@0/mmc@10808000` | **(c′)** | Ours, deliberate — binding gap, fix identified and verified (§2.4) |
| 7 | `mmc@10808000: Unevaluated properties are not allowed ('clock-names', 'dma-coherent', 'iommus' were unexpected)` | `/soc@0/mmc@10808000` | **(c′)** | Same |
| 8 | `mmc@10808000: compatible:0: 'intel,agilex5-sd4hc' is not one of [...]` | `/soc@0/mmc@10808000` | **(a)** | **Gone with `0101`** — its binding hunk adds the string |
| 9 | `failed to match any schema with compatible: ['intel,agilex5-sd4hc', 'cdns,sd4hc']` | `/soc@0/mmc@10808000` | **(a)** | Summary line for 8; **gone with `0101`** |

Counts, stock 7.2.2: **(a) 7 · (b) 0 · (c) 0 · (c′) 2**.
Counts, 7.2.2 + `0101` + `0102` (shipped): **(a) 5 · (b) 0 · (c) 0 · (c′) 2**.

Class key, per the task's definitions:

- **(a)** *expected*: the DT form is the forward-correct one; the *binding* has not caught up.
- **(b)** *inherited from the mainline dtsi*: **none**. Verified by running the same command on
  the stock in-tree board — `make ARCH=arm64 CHECK_DTBS=y intel/socfpga_agilex5_socdk.dtb`
  emits **zero** warnings on 7.2.2. Every warning above is attributable to a node we authored.
- **(c)** *ours to fix*: **none remain**. Two were found and fixed during authoring, before the
  file was written out — the `ethernet-phy@0`/`reg = <1>` mismatch (§5 D3) and the `hps0` LED
  child node name, which `leds-gpio.yaml`'s child pattern `(^led-[0-9a-f]$|led)` rejects
  outright under its `additionalProperties: false` (§5 D2).
- **(c′)** is a class the task did not name and this file needs: *ours, deliberate, and fixable
  only in a binding we already carry a patch to*. See §2.4 — the fix is verified, it is four
  short blocks in a file `0101` already edits, and it is not this file's to make.

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
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: mmc@10808000 (intel,agilex5-sd4hc): clocks: [[7, 40], [7, 78]] is too long
	from schema $id: http://devicetree.org/schemas/mmc/cdns,sdhci.yaml
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: mmc@10808000 (intel,agilex5-sd4hc): Unevaluated properties are not allowed ('clock-names', 'dma-coherent', 'iommus' were unexpected)
	from schema $id: http://devicetree.org/schemas/mmc/cdns,sdhci.yaml
```

Stock 7.2.2 additionally emits, and `0101` removes:

```
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: mmc@10808000 (intel,agilex5-sd4hc): compatible:0: 'intel,agilex5-sd4hc' is not one of ['amd,pensando-elba-sd4hc', 'microchip,mpfs-sd4hc', 'microchip,pic64gx-sd4hc', 'mobileye,eyeq-sd4hc', 'socionext,uniphier-sd4hc']
	from schema $id: http://devicetree.org/schemas/mmc/cdns,sdhci.yaml
arch/arm64/boot/dts/intel/socfpga_agilex5_de25nano.dtb: /soc@0/mmc@10808000: failed to match any schema with compatible: ['intel,agilex5-sd4hc', 'cdns,sd4hc']
```

### 2.4 Both residual classes are *binding* gaps, and both fixes are verified

This was tested, not asserted. Two throwaway edits were applied to the schema files in the
scratch tree and then reverted.

**(a) — the fpga-mgr warnings.** Restructuring `intel,stratix10-soc-fpga-mgr.yaml`'s
`compatible` from a flat two-value `enum` into the `oneOf`/`items` shape that Khairul's v6
binding patch proposes (implementation path §2.5) clears **all five**. That patch has not
landed at 7.2 or at `master`, which is exactly why §2.5 recommends accepting the warning
rather than dropping the SoC-specific string.

**(c′) — the mmc0 warnings.** Adding the following to `cdns,sdhci.yaml`'s `properties:` clears
**both**, leaving `socfpga_agilex5_de25nano.dtb` **completely dtbs_check-clean**:

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

**This belongs in `linux-patches/0101`, whose binding hunk already edits this exact file**
(it adds `intel,agilex5-sd4hc` to the vendor enum three lines above). It is not a DTS change
and is therefore out of this file's scope — flagged for whoever owns `0101`. Precedent for each
line: `clocks`/`clock-names` because the Agilex 5 integration genuinely wires two clocks (§3,
mmc0 row); `iommus: maxItems: 1` because `dwc2.yaml:93` declares exactly that for the same
reason on the same SoC; `dma-coherent: true` because nine existing `mmc/*.yaml` bindings already
do (`arasan,sdhci.yaml:127`, `fsl,esdhc.yaml:78`, `sdhci-am654.yaml:53`, …).

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

**Coverage audit — every enabled DMA master carries an `iommus` phandle**, which matters
because the SMMU is enabled (§4):

| enabled master | `iommus` | status |
|---|---|---|
| `/soc@0/ethernet@10810000` | `<&smmu 1>` | okay |
| `/soc@0/mmc@10808000` | `<&smmu 5>` | okay |
| `/soc@0/usb@10b00000` | `<&smmu 6>` | okay |
| `/soc@0/dma-bus@10db0000/dma-controller@0` | `<&smmu 8>` | (no status = enabled) |
| `/soc@0/dma-bus@10db0000/dma-controller@10000` | `<&smmu 9>` | (no status = enabled) |
| `/firmware/svc` | `<&smmu 10>` | (no status = enabled) |

Node statuses, read back out of the blob with `fdtget`: `serial@10c02100` okay,
`serial@10c02000` disabled, `ethernet@10810000` okay, `usb@10b00000` okay, `i2c@10c02900` okay,
`gpio@10c03300` okay, `gpio@10c03200` disabled, `iommu@16000000` okay, `mmc@10808000` okay,
`spi@108d2000` (qspi) disabled, `watchdog@10d00200`…`watchdog@10d00600` okay,
`nand-controller@10b80000` disabled.

---

## 3. Node-by-node

`—` = absent from that tree. "MAINLINE" means `socfpga_agilex5.dtsi` at 7.2.2 unless a board
file is named.

| Node / property | Source | Verdict | Why |
|---|---|---|---|
| `#include "socfpga_agilex5.dtsi"` | all three | **kept** | The board file patches no SoC `.dtsi`. Everything is a reference or a path override. |
| `model` | — | **changed** | `"Terasic DE25-Nano"`. All three references say `"SoCFPGA Agilex5 Terasic DE25-Nano"`; ours is the board name, which is what `/proc/device-tree/model` should read. |
| root `compatible` | all three | **kept** (`intel,socfpga-agilex5-socdk`, `intel,socfpga-agilex5`) | Factually wrong — this is not an SoCDK — but `Documentation/devicetree/bindings/arm/altera.yaml:109-117` is a **closed five-value enum** for Agilex 5 boards, so `terasic,de25-nano` would fail dtbs_check for zero gain: arm64 has no `DT_MACHINE_START` table, so nothing matches on it. Board identity lives in `model`. The honest fix is a one-line upstream `altera.yaml` patch; see §7 U6. |
| `aliases/serial0 = &uart1` | TERASIC + ALTERA + FRIEND | **kept** | See "Console UART" below. |
| `aliases/ethernet0 = &gmac0` | TERASIC + ALTERA + FRIEND | **kept** | **Load-bearing.** U-Boot's `fdt_fixup_ethernet()` walks `/aliases` for `ethernetN` and writes `$ethaddr` into the node it names. Without it the MAC is never injected — the identical DE10 lesson, [`dts-comparison.md`](dts-comparison.md) §3.3. |
| `aliases/i2c1 = &i2c1` | ALTERA only | **kept** | Pins the one enabled adapter to `/dev/i2c-1` instead of dynamic numbering. The DE10's A14 ([`dts-comparison.md`](dts-comparison.md) §2) is the standing lesson that i²C adapter numbering is worth making deterministic. Either way it lands inside `0..2`. |
| `chosen/stdout-path` | all three | **kept** | `"serial0:115200n8"`. |
| `chosen/bootargs` | TERASIC + FRIEND | **dropped** | Self-contradictory *and* dead. Their string sets `console=`/`earlycon=` to `0x10c02000` (= **uart0**) while their own `stdout-path` resolves to uart1, and U-Boot's `fdt_chosen()` overwrites `/chosen/bootargs` from `$bootargs` regardless. ALTERA's 2025 in-house file already dropped it. |
| `leds { compatible = "gpio-leds" }` | all three | **kept** | |
| LED child node name | ALTERA (`led-0`) | **changed** from TERASIC/FRIEND (`hps0`) | `leds-gpio.yaml`'s child pattern is `(^led-[0-9a-f]$|led)`; `hps0` matches neither, so the node is rejected by that binding's `additionalProperties: false`. Provably a no-op: the class-device name comes from `label`, so `/sys/class/leds/hps_led0` is unchanged — same ABI as the DE10. |
| `label = "hps_led0"`, `gpios = <&portb 17 GPIO_ACTIVE_LOW>` | all three | **kept** | Identical in all three. |
| `linux,default-trigger = "mmc0"` | — (DE10 stock has it) | **not added** | Out of wave-1 scope (bare developer OS, no MiSTer binaries). One line to add later; the trigger resolves because the mmc core registers a simple trigger named after `dev_name(&host->class_dev)`. |
| `memory@80000000` | — in MAINLINE dtsi | **authored** | See "Memory" below. |
| `base_fpga_region: fpga-region` | TERASIC + ALTERA `.dtsi`; absent from MAINLINE at every base | **authored** | Implementation path §3.1. `compatible = "fpga-region"`, `#address-cells`/`#size-cells` = 2, `fpga-mgr = <&fpga_mgr>`. `fpga-region.yaml` requires exactly `compatible` + `fpga-mgr`; both present. |
| `fpga-bridges`, any bridge node | — | **deliberately absent** | The Cyclone V `fpga_bridge0..3` shape has no Agilex analogue and must not be transliterated ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2). |
| `config-complete-timeout-us` | — | **deliberately absent** | It belongs on the per-core **overlay**, not the base region ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.3). `of-fpga-region.c` reads it from the overlay's target node. |
| `/firmware/svc` `compatible` | MAINLINE | **kept unchanged** (`intel,agilex5-svc`) | See "The svc node" below. Earlier drafts of implementation-path §3.1 called for overriding this to `intel,agilex-svc`; that is now the *fallback*, not the plan. |
| `/firmware/svc` `method`, `memory-region`, `iommus` | MAINLINE | **kept, inherited** | Not restated in the board file. `method = "smc"` is required or `get_invoke_func()` fails probe `-ENXIO`; `iommus` is *required by the binding* for the agilex5 string (`intel,stratix10-svc.yaml`'s `allOf`). |
| `fpga_mgr` child | TERASIC/ALTERA (single string) | **changed** | Two-string fallback `"intel,agilex5-soc-fpga-mgr", "intel,agilex-soc-fpga-mgr"`. Binds the **stock** driver: `s10_of_match[]` (`drivers/fpga/stratix10-soc.c:448-452`) carries no `.data` and never branches on which entry matched, and OF matching walks the whole list. Costs a transient dtbs_check warning (§2.5 of the implementation path); avoids a carried match-table line forever. |
| `altr,smmu_enable_quirk` on svc / fpga_mgr | TERASIC | **dropped** | Vendor-live, mainline-inert: `grep -rn smmu_enable_quirk` over mainline 7.2.2 → zero hits. It gates SDM DMA setup in *Terasic's* `stratix10-svc.c`; carrying it onto a mainline driver does nothing. Its existence is evidence for implementation-path §2.6, not a property to copy. |
| `interrupts`/`interrupt-parent` on svc | TERASIC | **dropped** | Not in `intel,stratix10-svc.yaml`, not read by mainline's `stratix10-svc.c`. |
| `hwmon` / `temp_volt` child of svc | TERASIC + FRIEND | **dropped** | `compatible = "intel,soc64-hwmon"` exists nowhere in mainline (`drivers/hwmon/`, `Documentation/devicetree/bindings/hwmon/` → zero hits at 7.2.2). The whole `&temp_volt { voltage { … } temperature { … } }` block — 60 lines in both references — binds nothing. Revisit if an SDM hwmon driver lands. |
| `fcs-hal` / `fcs-crypto` children | TERASIC | **dropped** | `intel,agilex5-soc-fcs-hal` likewise absent from mainline. |
| `&smmu { status = "okay" }` | all three | **kept** | Implementation path §3.1. Disabled at MAINLINE 7.2, enabled at `master`. See §4 for why this choice propagates into mmc0. |
| **`mmc0`** — `compatible` | TERASIC + FRIEND | **kept exactly** | `"intel,agilex5-sd4hc", "cdns,sd4hc"`, vendor string **first**. That order is the `items: [enum, const]` form `0101` adds to `cdns,sdhci.yaml`, and with `0101` the first entry wins and installs the 40-bit DMA mask. ALTERA's `"altr,agilex5-sd6hc","cdns,sd6hc"` is unusable: `cdns,sd6hc` exists nowhere in mainline (implementation path §4.1). A lone `cdns,sd4hc` would still bind — `sdhci_cdns_probe()` falls back to `&sdhci_cdns_drv_data` when `of_device_get_match_data()` returns NULL (`sdhci-cadence.c:561-563`) — but **silently without the mask**, which is the §8 Q2 failure. |
| `mmc0` `reg`, `interrupts` | TERASIC + ALTERA + FRIEND (identical) | **kept** | `0x10808000 0x1000`, `GIC_SPI 96 IRQ_TYPE_LEVEL_HIGH`. |
| `mmc0` node name | — | **changed** | `mmc@10808000`, not the references' `mmc0@10808000`. Generic node name per `mmc-controller.yaml`; the vendor name is not a legal generic-node name and buys nothing. |
| `mmc0` `resets` | TERASIC + FRIEND | **kept** | `<&rst SDMMC_RESET>`. Inert on this board — `sdhci-cadence` takes the reset only under `MMC_CAP_HW_RESET` (eMMC) — but correct hardware description. ALTERA's three-entry list (`COMBOPHY_RESET`, `SDMMC_OCP_RESET`) targets their SD6HC rewrite. |
| `mmc0` `reset-names = "reset"` | TERASIC + FRIEND | **dropped** | Not declared in `cdns,sdhci.yaml` (would trip `unevaluatedProperties`), and the driver looks the reset up with `id = NULL`, i.e. by index. |
| `mmc0` `fifo-depth = <0x800>` | TERASIC + ALTERA + FRIEND | **dropped** | Dead. `grep fifo-depth drivers/mmc/host/sdhci-cadence.c` → zero hits; it is a `dw_mmc` property that travelled here by copy. Same class as the DE10's `speed-mode`/`timeouts` ([`dts-comparison.md`](dts-comparison.md) §4 D3/D4). |
| `mmc0` `#address-cells`/`#size-cells` | all three | **dropped** | The node has no children. Pure `avoid_unnecessary_addr_size` noise. |
| `mmc0` `clocks` + `clock-names` | all three (identical) | **kept, both entries** | `<&clkmgr AGILEX5_L4_MP_CLK>, <&clkmgr AGILEX5_SDMCLK>` / `"biu", "ciu"`. Mainline only ever uses index 0 — `devm_clk_get_enabled(dev, NULL)` (`sdhci-cadence.c:557`) — and on Agilex 5 the second is inert anyway: gate clocks register with `agilex_gateclk_ops` (`clk-gate-s10.c:279`, defined `:117`), which has **no `.enable`/`.disable`**, so `clk_prepare_enable()` is a no-op *and* `clk_disable_unused()` cannot turn `sdmclk` off. Kept because it is the truthful hardware description, it matches all three references including the one that boots, and the binding — not the DT — is what needs widening (§2.4). |
| `mmc0` `iommus`, `dma-coherent` | all three | **kept** | The §8 Q2 decision. See §4. |
| `mmc0` `bus-width = <4>`, `disable-wp` | all three | **kept** | 4-bit microSD, no write-protect switch wired. |
| `mmc0` `cap-sd-highspeed` | TERASIC + ALTERA | **kept** | |
| `mmc0` `no-1-8-v` | TERASIC + FRIEND | **kept** | 3.3V-only signalling. Also the reason we can safely omit ALTERA's `vqmmc-supply` level-shifter regulator (below). |
| `mmc0` `no-sdio` | TERASIC + FRIEND | **kept** | SD card slot only; MiSTer WiFi is USB. |
| `mmc0` `sd-uhs-sdr50` | TERASIC | **dropped** | Contradicts `no-1-8-v` in the same node: every UHS mode needs 1.8V signalling, which `MMC_CAP2_NO_1_8_V` bars. Inert, and confusing to leave in. |
| `mmc0` `sdhci-caps` / `sdhci-caps-mask` | TERASIC (ALTERA has a wider mask) | **kept, TERASIC's values** | **Live on mainline and probably load-bearing.** `__sdhci_read_caps()` (`drivers/mmc/host/sdhci.c:4161-4186`) applies them to `SDHCI_CAPABILITIES{,_1}`; the uint64 is `<caps1 caps>`. `0xc800` in caps bits 15:8 sets the base clock to `0xc8` = 200 MHz, and `sdhci_cdns_ops` has **no `.get_max_clock`**, so a zero base-clock field would fail probe outright with `"Hardware doesn't specify base clock frequency"` / `-ENODEV` (`sdhci.c:4448-4462`). Both vendors set it; treated as load-bearing rather than decorative. The caps1 mask clears bit 13 (`SDHCI_USE_SDR50_TUNING`). ALTERA masks `0x2007`, additionally removing SDR50/SDR104/DDR50 — moot under `no-1-8-v`. |
| `mmc0` 40 × `cdns,phy-*` / `cdns,hrs*` | TERASIC + FRIEND | **dropped** | **Dead devicetree on a mainline driver.** `sdhci-cadence`'s property table knows only eleven `cdns,phy-input-delay-*` / `cdns,phy-dll-delay-*` names (`sdhci-cadence.c:108-119`); not one of the forty is among them. Implementation path §2.2 makes the same call, and notes the consequence: the friend's working SD path already runs on the driver's **default** PHY configuration, which is what we inherit. |
| `mmc0` `vmmc-supply` / `vqmmc-supply` + `sd_emmc_power` / `sd_io_1v8_reg` regulators | ALTERA only | **dropped** | Would mean authoring a `regulator-fixed` and a `regulator-gpio` (on `portb 3`) that no other reference has and no bench test has exercised. Under `no-1-8-v` the level shifter never has to switch, and U-Boot's own SD boot from the same card demonstrates the hardware default is the 3.3V state. Adding an untested GPIO-driven regulator to the SD path is precisely the change that turns a working boot into a non-booting one. Flagged §7 U4. |
| `mmc0` `max-frequency` | ALTERA `200000000`; FRIEND `25000000` | **dropped (neither)** | TERASIC ships none. ALTERA's is a no-op ceiling. FRIEND's 25 MHz is a real cap with a board-instance-specific rationale ("corrupted SD SCR data during post-JTAG Linux boots") that should not be generalised. Named in §7 U3 as the first thing to try if SD is flaky. |
| `&gmac0` `status`, `phy-mode`, `phy-handle`, `max-frame-size` | all three (identical) | **kept** | `phy-mode = "rgmii"`, **not** `"rgmii-id"`: ALTERA's file states the TX/RX delays are on the PCB, so asking the PHY for internal delay too would double it — the same trap as the DE10's `gmac1` ([`dts-comparison.md`](dts-comparison.md) §3.2). |
| `&gmac0` `mdio0` node name | all three **and MAINLINE's own socdk** (`socfpga_agilex5_socdk.dts:51`) | **kept** | Does not match `mdio.yaml`'s `$nodename` pattern, but it is what the in-tree board uses, so the shape is upstream's, not ours — and dtbs_check does not in fact flag it. Cosmetic at runtime: `stmmac_of_get_mdio()` (`stmmac_platform.c:295-318`) finds the node by scanning children for `compatible = "snps,dwmac-mdio"`, never by name. |
| `ethernet-phy@0 { reg = <1>; }` | all three | **changed → `ethernet-phy@1`** | A unit-address/`reg` mismatch that dtc reports under `-Wunit_address_vs_reg`. PHY address **1** is the real value (all three agree on `reg`); only the unit address was wrong. Provably a no-op — `of_mdiobus_register()` addresses the PHY from `reg`. See §5 D3. |
| `&gmac1`, `&gmac2` | — | **left disabled** | One RJ45 on this board; MAINLINE's default is disabled. |
| `&gpio1 { status = "okay" }` | all three | **kept** | Provides `portb`, which `led-0` uses. `gpio0` stays disabled (all three). |
| `&i2c1 { status = "okay" }` | all three | **kept** | The only i²C bus enabled ⇒ exactly one adapter, pinned to 1 by the alias. |
| `&uart1 { status = "okay" }` | all three | **kept** | Console. `uart0` left disabled (MAINLINE default) — see "Console UART". |
| `&usb0 { status = "okay"; disable-over-current }` | all three | **kept** | `disable-over-current` is live (`Documentation/devicetree/bindings/usb/dwc2.yaml:89`). No `dr_mode`: none of the three sets one, so dwc2 reads the OTG capability out of the hardware. Flagged §7 U5. |
| `&watchdog0..4 { status = "okay" }` | all three | **kept, all five** | Deliberate parity with a safety argument: `dw_wdt` sets `WDOG_HW_RUNNING` when it finds the watchdog already started by firmware, and the watchdog core then pets it until userspace opens the device. A watchdog started by the SPL whose node is **disabled** in Linux is never petted and resets the board. Enabling costs a `/dev/watchdogN`; not enabling could cost a boot. |
| `disable-over-current` on `&watchdog4` | TERASIC → ALTERA → FRIEND | **dropped** | A copy-paste of the `usb0` property onto a watchdog. Meaningless to `snps,dw-wdt`, absent from its binding, propagated unchanged through all three trees. |
| `&osc1 { clock-frequency = <25000000> }` | all three | **kept** | MAINLINE declares `osc1` as a `fixed-clock` with `clock-frequency = <0>` (`socfpga_agilex5.dtsi:139-143`); it is the root of the peripheral clock tree, so leaving it at 0 gives a zero rate everywhere downstream. Exactly the `osc1` question [`dts-comparison.md`](dts-comparison.md) §4.1 asked for the DE10 — and here, unlike there, the answer is that it *does* need setting. |
| `&qspi` + `flash@0` + partitions | ALTERA only | **dropped** | Not in the §3.1 node set; TERASIC and FRIEND both leave QSPI disabled. Enabling it exposes the **factory boot image** to `/dev/mtd` writes, and the QSPI contents are the board's un-recoverable-without-Quartus state ([`de25-boot-chain.md`](de25-boot-chain.md) §7 rows 14/15). Nothing in wave 1 needs it. |
| `mister_fb`, `ascal_scratch`, `x86ram`, `mister_fb_mem` reserved regions | FRIEND only | **dropped** | ADR 0027 scopes wave 1 to a bare developer OS with **no MiSTer binaries**. These describe a fabric/Main_MiSTer memory map that does not exist yet, and `de25-reference-implementation.md` already flags the friend's 2 GiB assumption underneath `x86ram@b0000000` as unverified. |
| `&i2c1`'s vendor `status` whitespace, `&mmc` label | — | n/a | We define our own label `mmc0`; the references' `&mmc` label lives in a `.dtsi` we do not patch. |

### The svc node — a dependency, stated plainly

We keep MAINLINE's `compatible = "intel,agilex5-svc"` exactly as the `.dtsi` ships it, with its
inherited `iommus = <&smmu 10>` (which the binding's `allOf` **requires** for that string), and
add only the `fpga_mgr` child.

That string is in `intel,stratix10-svc.yaml`'s enum but has **never** been in
`stratix10_svc_drv_match[]` — not at 6.18.44, not at 7.2.2, not at `master`. On a stock kernel
the node is therefore **inert**: `stratix10_svc_init()`'s `of_platform_populate()` skips it, no
service device is created, and the `fpga_mgr` child has nothing to attach to. Because it is a
lone compatible with no fallback string, the OF core cannot rescue it either.

**This DTS therefore depends on `linux-patches/0102`**, which adds the one match-table line (or
on the equivalent landing upstream — it is a one-line upstream fix and worth sending).

**Fallback if `0102` is ever dropped:** re-add the override that earlier drafts of
implementation-path §3.1 called for —

```dts
&{/firmware/svc} {
	compatible = "intel,agilex-svc";	/* in the match table AND in the enum */
	...
};
```

— which binds the stock driver and is schema-clean. Mainline branches on neither string
(implementation path §8 Q3), so the two are equivalent *against mainline*; they stop being
equivalent the moment anyone ports the vendor's agilex5-specific svc behaviour, which is why
keeping the SoC-accurate string plus a one-line patch is the better shape.

### Console UART — a documented deviation

The task brief said "uart0 status okay (console)". **The file enables `uart1` instead**, and
leaves `uart0` at MAINLINE's disabled default. The evidence:

- TERASIC, ALTERA and FRIEND *all three* set `aliases { serial0 = &uart1; }` and
  `&uart1 { status = "okay"; }`, and none of them enables uart0.
- MAINLINE's `socfpga_agilex5_socdk.dts` uses uart0 — but that is a **different board**; HPS
  UART pinmux is board wiring, not SoC wiring.
- The one apparent counter-evidence is TERASIC's/FRIEND's `bootargs` naming `0x10c02000`
  (uart0). It is self-contradictory with their own `stdout-path` in the same node, and ALTERA's
  2025 in-house rewrite **deleted the bootargs string entirely** while keeping
  `serial0 = &uart1` — the strongest single signal that the bootargs were stale SoCDK residue.
- UART addresses are identical across MAINLINE, TERASIC and FRIEND (`uart0` = `serial@10c02000`,
  `uart1` = `serial@10c02100`), so this is a pure wiring question, not an addressing one.

If first boot is silent, the one-line fallback is to enable `&uart0` as well and move
`serial0`; both would then exist and the correct one can be chosen from the U-Boot `console=`
argument. Tagged §7 U1 until a serial console is actually observed.

### Memory

MAINLINE's `.dtsi` has no memory node, so the board file must supply one.

| Tree | value |
|---|---|
| TERASIC, FRIEND | `memory { reg = <0 0x80000000 0 0x80000000>; }` — 2 GiB, and a node name with no unit address |
| ALTERA, MAINLINE socdk | `memory@80000000 { reg = <0x0 0x80000000 0x0 0x0>; }` — size 0, "we expect the bootloader to fill in the reg" |
| **OURS** | `memory@80000000 { reg = <0x0 0x80000000 0x0 0x40000000>; }` — **1 GiB** |

1 GiB at `0x8000_0000` is what the **factory SPL DTB** reports and what the *UM* specifies for
the HPS — [`de25-boot-chain.md`](de25-boot-chain.md) §3, `[V SPL-dtb]`. The references'
2 GiB over-claims by 2× on a 1 GiB board; size 0 is a hard dependency on
`fdt_fixup_memory_banks()` running. U-Boot rewrites this either way, so stating the measured
size costs nothing and degrades gracefully in the one case where the other two do not.

`de25-reference-implementation.md` already asked this question of the friend's tree ("Does the
DE25-Nano HPS actually have 2 GiB of DRAM?"). **It does not** — and this is the answer to that
open item, sourced from the factory SPL rather than from a vendor DTS.

One consequence worth carrying: **all DRAM lives in `0x8000_0000..0xBFFF_FFFF`, entirely inside
32 bits.** That is what makes the SMMU-off escape hatch in §4 safe.

---

## 4. The SMMU / `mmc0` decision (implementation path §8 Q2)

**Decision: `&smmu { status = "okay" }`, and `mmc0` keeps both `iommus = <&smmu 5>` and
`dma-coherent`.** Full parity with all three references. The §8 Q2 DMA-width risk is answered on
the *driver* side by `linux-patches/0101`, not by unwiring the SMMU.

**Why not drop `iommus`.** Under an *enabled* SMMUv3, a master that is not described does not
bypass — it **aborts**. `arm_smmu_init_initial_stes()` fills every stream-table entry with
`arm_smmu_make_abort_ste()`
(`drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3.c:1925-1934`, called from `:1955` for two-level
tables and `:4489` for linear ones), and an unallocated L1 descriptor faults too. So dropping
`iommus` from `mmc0` while `&smmu` is `okay` would trade a **possible** `F_TRANSLATION` for a
**certain** abort — no SD at all. The two properties are not independent knobs; `&smmu`'s status
decides, and `iommus` must then agree with it.

**Why `dma-coherent` stays.** Corroborated inside MAINLINE itself: the sibling `nand` controller
on this same SoC carries `dma-coherent` in `socfpga_agilex5.dtsi:315`, which is upstream's own
statement that Agilex 5 HPS peripheral masters are coherent. All three vendor trees agree on
`mmc0`. (The conservative direction — omitting it, so Linux does cache maintenance on a device
that may not need it — is always *safe*, only slower; it is named as a fallback in §7 U2 rather
than taken, because the mainline `nand` precedent is stronger than the absence of a bench test.)

**How the §8 Q2 failure is actually addressed.** Mainline takes `DMA_BIT_MASK(64)` where the
Agilex 5 SD4HC drives only 40 address bits; under SMMU translation the IOVA allocator works
top-down, so the first mapping lands above bit 39, the controller truncates it, and
`arm-smmu-v3` reports an "input address caused fault" with nothing mmc-shaped in the log. That
is a **vendor-vs-mainline driver delta**, so it does not go away on a newer kernel — which is
exactly why `linux-patches/0101` exists and why our `compatible` puts `intel,agilex5-sd4hc`
first. Without `0101` the node still binds through the bare `cdns,sd4hc` entry and behaves as
today (i.e. exposed to the fault, workaround-able from the command line with the friend's
`sdhci.debug_quirks=0x60` PIO forcing); with `0101` the mask is right and ADMA works.

**The escape hatch, for §2.6 step 4 of the implementation path** — which asks for the
programming test to be run once with the SMMU off and once on:

```dts
&smmu { status = "disabled"; };
```

is a **one-line change with no other edits**, and it is safe here. `of_iommu_xlate()` returns
`-ENODEV` when the IOMMU node is unavailable (`drivers/iommu/of_iommu.c:28-29`), and
`of_iommu_configure()` treats `-ENODEV` as "this device has no IOMMU", not as an error — so
*every* `iommus` property in the tree goes inert at once and every master DMAs physically. All
DRAM is below 4 GiB (§3, Memory), so a 40-bit-wired controller cannot truncate anything. This is
also the configuration MAINLINE 7.2 ships by default.

**What would falsify this.** If SD fails on first boot with `arm-smmu-v3` translation faults
*even with `0101` applied*, the next step is the escape hatch above, not further DT surgery on
`mmc0`. If SD then works, §8 Q2's leg 5 is confirmed and the question becomes whether the SMMU
is needed at all for the svc/fpga path (§8 Q1's step 4).

---

## 5. Deliberate divergences from the reference files

Every difference a node-by-node diff against TERASIC/ALTERA/FRIEND turns up, accounted for.
D1–D6 are changes of *form*; the content drops are in §3.

| # | Divergence | Why |
|---|---|---|
| D1 | `mmc0@10808000` → **`mmc@10808000`** | Generic node name (`mmc-controller.yaml`). The device is named from the translated `reg`, not the node name, so `10808000.mmc` either way. |
| D2 | LED child `hps0` → **`led-0`** (ALTERA's form) | `leds-gpio.yaml` child pattern `(^led-[0-9a-f]$|led)`; `hps0` is rejected under `additionalProperties: false`. ABI unchanged: `/sys/class/leds/hps_led0` comes from `label`. |
| D3 | `ethernet-phy@0 { reg = <1>; }` → **`ethernet-phy@1 { reg = <1>; }`** | Silences `-Wunit_address_vs_reg`, which is the one dtc warning a verbatim transcription would have added. Provably a no-op: `of_mdiobus_register()` addresses PHYs from `reg`. All three references carry the mismatch. |
| D4 | `memory { … }` → **`memory@80000000 { … }`**, and 2 GiB → **1 GiB** | Unit address for dtc; size from the factory SPL DTB (§3, Memory). `memory@80000000` is still found by both consumers — Linux scans `device_type = "memory"`, and U-Boot's `fdt_fixup_memory_banks()` uses libfdt's `fdt_subnode_offset()`, whose name comparison accepts a trailing `@unit-address`. |
| D5 | `model` `"SoCFPGA Agilex5 Terasic DE25-Nano"` → **`"Terasic DE25-Nano"`** | Cosmetic; the board's name rather than a compilation of SoC and board. |
| D6 | `&watchdog4` loses `disable-over-current` | A watchdog has no over-current line. Copy-paste from `usb0`, propagated through all three trees. |

---

## 6. What this document does **not** prove

- **That the board boots.** Nothing here has run on silicon. This is a desk validation: the DTB
  compiles clean, validates against the bindings modulo two known binding gaps, and its
  load-bearing node names and phandles resolve. Every runtime claim is a citation into driver
  source, not an observation.
- **That the fabric can be programmed.** Implementation path §8 Q1 is untouched by this file and
  remains **low confidence**; the `fpga-region`/`fpga_mgr` nodes here are the *binding* half of
  §2.6's four-step test, which is expected to pass, not the *programming* half, which is the
  actual experiment.
- **That `mmc0` DMAs correctly.** §4 argues the shape is right and names the fallback; §8 Q2
  stays open until the five-leg boot matrix is run.
- **PHY link.** `phy-mode = "rgmii"` with the delays on the PCB is ALTERA's claim, taken on
  their authority and cross-checked against the other two references. Not measured.

---

## 7. Open `[U]` — what could not be settled without hardware

| # | Question | Why it matters | How it is settled |
|---|---|---|---|
| **U1** | Is the console really `uart1`? | If it is `uart0`, first boot is silent with no other symptom. Three-way reference agreement says uart1; the task brief said uart0 (see "Console UART"). | First serial connection. One-line fix either way; enabling both is the belt-and-braces option. |
| **U2** | Is the SDMMC master really cache-coherent? | `dma-coherent` on a non-coherent master is silent data corruption. Justified from `socfpga_agilex5.dtsi:315`'s `nand` precedent + three vendor trees, not from a bench test. | First SD read/write of real data. If the rootfs is corrupt, delete `dma-coherent` (always safe — costs throughput only) before touching anything else. |
| **U3** | Does SD need a clock cap? | FRIEND caps at 25 MHz for "corrupted SD SCR data during post-JTAG Linux boots"; TERASIC and ALTERA do not cap. We ship no cap. | If SD enumeration is flaky, add `max-frequency = <25000000>` — one line, and the reference has a written rationale for it. |
| **U4** | Does the SD I/O rail need ALTERA's `regulator-gpio` on `portb 3`? | ALTERA wires `vqmmc-supply` to a 1.8V/3.3V level shifter; we rely on `no-1-8-v` plus the boot-default state. | Only matters if UHS is ever wanted. Until then the shifter never switches. |
| **U5** | `dr_mode` for `usb0` | Unset in all three references, so dwc2 reads OTG capability from the hardware. A MiSTer image wants host mode. | Observe `/sys/class/udc` and whether hubs enumerate; add `dr_mode = "host"` if OTG guesses wrong. |
| **U6** | Should the root compatible say `terasic,de25-nano`? | Currently claims to be an SoCDK. Nothing on arm64 reads it, but it is wrong. | A one-line upstream patch to `Documentation/devicetree/bindings/arm/altera.yaml`, then a one-line DTS change. Cheap, and squarely within the "send fixes upstream" decision. |
| **U7** | Does `sdhci-caps`' 200 MHz base clock match the silicon? | If the capability register already reports a *different* non-zero base, we are overriding a correct value with a vendor constant and every derived card clock is off. | `cat /sys/kernel/debug/mmc0/ios` on first boot, and compare `dmesg`'s reported max clock with the caps register read before the override. |
| **U8** | Do the two residual binding gaps get fixed upstream? | Until then this DTB is never fully dtbs_check-clean, and a CI gate would have to allow-list 7 warnings. | Watch Khairul's v6 fpga-mgr binding series (implementation path §8 Q4); and land §2.4's `cdns,sdhci.yaml` addition into `linux-patches/0101`. Re-check both on every kernel bump. |

---

## 8. Corrections owed to sibling documents

| Document | Claim | Correction |
|---|---|---|
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 | The authored node set overrides `/firmware/svc`'s compatible to `"intel,agilex-svc"` | Superseded. We keep MAINLINE's `"intel,agilex5-svc"` and carry `linux-patches/0102` (a one-line match-table addition) instead. The override is retained as the documented fallback. Rationale: the vendor treats the agilex5 string as semantic, so a kernel that will one day want that distinction should not have the DT lie about the SoC. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §2.5 | The two-string fpga-mgr form "warns" under `dtbs_check` | Confirmed and quantified: **five** warning lines, from **two** schemas (`intel,stratix10-svc.yaml` validating the child in place, and `intel,stratix10-soc-fpga-mgr.yaml` validating it standalone), plus the "failed to match any schema" summary. Simulating Khairul's v6 `oneOf`/`items` shape clears all five (§2.4). |
| [`de25-reference-implementation.md`](de25-reference-implementation.md) (open question, line ~664) | "Does the DE25-Nano HPS actually have 2 GiB of DRAM? His memory node hard-codes `reg = <0 0x80000000 0 0x80000000>`…" | **Answered: no, 1 GiB.** The factory SPL DTB reads `reg = <0x0 0x80000000 0x0 0x40000000>` ([`de25-boot-chain.md`](de25-boot-chain.md) §3, `[V SPL-dtb]`), matching the *UM*. The friend's node over-claims 2×, and his `x86ram@b0000000 + 0x10000000` would indeed sit past the top of RAM. Our node states 1 GiB. |
| [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2 | The svc node needs `compatible = "intel,agilex-svc"` authored on top of the in-tree dtsi | Only true on a 6.18 base, where the whole subtree is authored. On 7.x the subtree already exists and is inherited; the only additions are the `fpga_mgr` child and the root `fpga-region`. That section's own `[U]` note about the missing `smmu` node is resolved on 7.2: the node exists, `status = "disabled"`, and the board file turns it on. |
