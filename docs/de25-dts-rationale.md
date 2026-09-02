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
| `/firmware/svc` `method`, `memory-region`, `iommus` | MAINLINE | **kept, inherited** | Not restated in the board file. `method = "smc"` is required or `get_invoke_func()` fails probe `-ENXIO`; `iommus` is *required by the binding* for the agilex5 string (`intel,stratix10-svc.yaml`'s `allOf`), and is inert as shipped (§4.3). **`memory-region` is dead on mainline** — see [U9]: the driver uses whatever BL31 answers to `FPGA_CONFIG_GET_MEM` (`stratix10-svc.c:865-876`, `:952-960`) and never consults the `service_reserved` `no-map` region. |
| `fpga_mgr` child | TERASIC/ALTERA (single string) | **changed** | Two-string fallback `"intel,agilex5-soc-fpga-mgr", "intel,agilex-soc-fpga-mgr"`. Binds the **stock** driver: `s10_of_match[]` (`drivers/fpga/stratix10-soc.c:448-452`) carries no `.data` and never branches on which entry matched, and OF matching walks the whole list. Costs a transient dtbs_check warning (§2.5 of the implementation path); avoids a carried match-table line forever. |
| `altr,smmu_enable_quirk` on svc / fpga_mgr | TERASIC | **dropped** | Vendor-live, mainline-inert: `grep -rn smmu_enable_quirk` over mainline 7.2.2 → zero hits. It gates SDM DMA setup in *Terasic's* `stratix10-svc.c`; carrying it onto a mainline driver does nothing. Its existence is evidence for implementation-path §2.6, not a property to copy. |
| `interrupts`/`interrupt-parent` on svc | TERASIC | **dropped** | Not in `intel,stratix10-svc.yaml`, not read by mainline's `stratix10-svc.c`. |
| `hwmon` / `temp_volt` child of svc | TERASIC + FRIEND | **dropped** | `compatible = "intel,soc64-hwmon"` exists nowhere in mainline (`drivers/hwmon/`, `Documentation/devicetree/bindings/hwmon/` → zero hits at 7.2.2). The whole `&temp_volt { voltage { … } temperature { … } }` block — 60 lines in both references — binds nothing. Revisit if an SDM hwmon driver lands. |
| `fcs-hal` / `fcs-crypto` children | TERASIC | **dropped** | `intel,agilex5-soc-fcs-hal` likewise absent from mainline. |
| `&smmu` status | all three set `okay` | **changed → `disabled`** | The one design divergence from every reference. Mainline's svc layer hands the SDM **raw physical addresses** and never calls `iommu_map`/`dma_map`, while the inherited `iommus = <&smmu 10>` puts the svc device on a *translated* default domain — so SMMU-on cannot program the fabric on a mainline kernel. Full trace in §4.1. Also MAINLINE 7.2's own default. Every `iommus` property in the tree is kept and goes inert (§4.3), so the SMMU-on leg of the §2.6 test is a one-line change. |
| **`mmc0`** — `compatible` | TERASIC + FRIEND | **kept exactly** | `"intel,agilex5-sd4hc", "cdns,sd4hc"`, vendor string **first**. That order is the `items: [enum, const]` form `0101` adds to `cdns,sdhci.yaml`, and with `0101` the first entry wins and installs the 40-bit DMA mask. ALTERA's `"altr,agilex5-sd6hc","cdns,sd6hc"` is unusable: `cdns,sd6hc` exists nowhere in mainline (implementation path §4.1). A lone `cdns,sd4hc` would still bind — `sdhci_cdns_probe()` falls back to `&sdhci_cdns_drv_data` when `of_device_get_match_data()` returns NULL (`sdhci-cadence.c:561-563`) — but **silently without the mask**, which is the §8 Q2 failure. |
| `mmc0` `reg`, `interrupts` | TERASIC + ALTERA + FRIEND (identical) | **kept** | `0x10808000 0x1000`, `GIC_SPI 96 IRQ_TYPE_LEVEL_HIGH`. |
| `mmc0` node name | — | **changed** | `mmc@10808000`, not the references' `mmc0@10808000`. Generic node name per `mmc-controller.yaml`; the vendor name is not a legal generic-node name and buys nothing. |
| `mmc0` `resets` | TERASIC + FRIEND | **kept** | `<&rst SDMMC_RESET>`. Inert on this board — `sdhci-cadence` takes the reset only under `MMC_CAP_HW_RESET` (eMMC) — but correct hardware description. ALTERA's three-entry list (`COMBOPHY_RESET`, `SDMMC_OCP_RESET`) targets their SD6HC rewrite. |
| `mmc0` `reset-names = "reset"` | TERASIC + FRIEND | **dropped** | Not declared in `cdns,sdhci.yaml` (would trip `unevaluatedProperties`), and the driver looks the reset up with `id = NULL`, i.e. by index. |
| `mmc0` `fifo-depth = <0x800>` | TERASIC + ALTERA + FRIEND | **dropped** | Dead. `grep fifo-depth drivers/mmc/host/sdhci-cadence.c` → zero hits; it is a `dw_mmc` property that travelled here by copy. Same class as the DE10's `speed-mode`/`timeouts` ([`dts-comparison.md`](dts-comparison.md) §4 D3/D4). |
| `mmc0` `#address-cells`/`#size-cells` | all three | **dropped** | The node has no children. Pure `avoid_unnecessary_addr_size` noise. |
| `mmc0` `clocks` + `clock-names` | all three (identical) | **kept, both entries** | `<&clkmgr AGILEX5_L4_MP_CLK>, <&clkmgr AGILEX5_SDMCLK>` / `"biu", "ciu"`. Mainline only ever uses index 0 — `devm_clk_get_enabled(dev, NULL)` (`sdhci-cadence.c:557`) — and on Agilex 5 the second is inert anyway: gate clocks register with `agilex_gateclk_ops` (`clk-gate-s10.c:279`, defined `:117`), which has **no `.enable`/`.disable`**, so `clk_prepare_enable()` is a no-op *and* `clk_disable_unused()` cannot turn `sdmclk` off. Kept because it is the truthful hardware description, it matches all three references including the one that boots, and the binding — not the DT — is what needs widening (§2.4). |
| `mmc0` `iommus` | all three | **kept, inert as shipped** | `&smmu` is disabled, so `of_iommu_xlate()` returns `-ENODEV` and mmc0 DMAs physically. Kept because it is correct hardware description and mandatory the moment `&smmu` is flipped to `okay`. See §4.3. |
| `mmc0` `dma-coherent` | all three | **kept, with [U2] re-opened** | Corroborated by MAINLINE's own `nand` node (`socfpga_agilex5.dtsi:315`). But the vendors assert it under SMMU-**on**, where cacheability comes from the STE/`IOMMU_CACHE` attributes rather than from this property, so their evidence does not transfer to the shipped SMMU-off shape. Must be re-verified by data-integrity test, not inherited. See §4.5. |
| `mmc0` `bus-width = <4>`, `disable-wp` | all three | **kept** | 4-bit microSD, no write-protect switch wired. |
| `mmc0` `cap-sd-highspeed` | TERASIC + ALTERA (FRIEND drops it) | **kept** | Dropping it would be theatre, not caution: `sdhci.c:4572` sets `MMC_CAP_SD_HIGHSPEED` from the capability register's `SDHCI_CAN_DO_HISPD` (bit 21) **regardless of DT**, and our `sdhci-caps-mask` does not clear that bit. `max-frequency` above is the property that actually constrains the bus. If a bench test ever needs genuine default-speed-only, the real lever is widening the caps mask to `<0x00002000 0x0020ff00>`. |
| `mmc0` `no-1-8-v` | TERASIC + FRIEND | **kept** | 3.3V-only signalling. Also the reason we can safely omit ALTERA's `vqmmc-supply` level-shifter regulator (below). |
| `mmc0` `no-sdio` | TERASIC + FRIEND | **kept** | SD card slot only; MiSTer WiFi is USB. |
| `mmc0` `sd-uhs-sdr50` | TERASIC | **dropped** | Contradicts `no-1-8-v` in the same node: every UHS mode needs 1.8V signalling, which `MMC_CAP2_NO_1_8_V` bars. Inert, and confusing to leave in. |
| `mmc0` `sdhci-caps` / `sdhci-caps-mask` | TERASIC (ALTERA has a wider mask) | **kept, TERASIC's values** | **Live on mainline and probably load-bearing.** `__sdhci_read_caps()` (`drivers/mmc/host/sdhci.c:4161-4186`) applies them to `SDHCI_CAPABILITIES{,_1}`; the uint64 is `<caps1 caps>`. `0xc800` in caps bits 15:8 sets the base clock to `0xc8` = 200 MHz, and `sdhci_cdns_ops` has **no `.get_max_clock`**, so a zero base-clock field would fail probe outright with `"Hardware doesn't specify base clock frequency"` / `-ENODEV` (`sdhci.c:4448-4462`). Both vendors set it; treated as load-bearing rather than decorative. The caps1 mask clears bit 13 (`SDHCI_USE_SDR50_TUNING`). ALTERA masks `0x2007`, additionally removing SDR50/SDR104/DDR50 — moot under `no-1-8-v`. |
| `mmc0` 40 × `cdns,phy-*` / `cdns,hrs*` | TERASIC + FRIEND | **dropped** | **Dead devicetree on a mainline driver.** `sdhci-cadence`'s property table knows only eleven `cdns,phy-input-delay-*` / `cdns,phy-dll-delay-*` names (`sdhci-cadence.c:108-119`); not one of the forty is among them. Implementation path §2.2 makes the same call, and notes the consequence: the friend's working SD path already runs on the driver's **default** PHY configuration, which is what we inherit. |
| `mmc0` `vmmc-supply` / `vqmmc-supply` + `sd_emmc_power` / `sd_io_1v8_reg` regulators | ALTERA only | **dropped** | Would mean authoring a `regulator-fixed` and a `regulator-gpio` (on `portb 3`) that no other reference has and no bench test has exercised. Under `no-1-8-v` the level shifter never has to switch, and U-Boot's own SD boot from the same card demonstrates the hardware default is the 3.3V state. Adding an untested GPIO-driven regulator to the SD path is precisely the change that turns a working boot into a non-booting one. Flagged §7 U4. |
| `mmc0` `max-frequency` | FRIEND `25000000` (ALTERA `200000000`; TERASIC none) | **taken from FRIEND** | **First-boot risk control.** Mainline's `sdhci-cadence` programs **none** of the 40 `cdns,phy-*` values the vendor trees carry, so Linux inherits whatever PHY state U-Boot left rather than configuring it. The only boot of this board on a **mainline** sdhci-cadence driver — FRIEND, `socfpga_agilex5_de25_nano.dts:110-126` — reached that state only after dropping high-speed advertisement and capping the clock at 25 MHz, following corrupted SD SCR reads. Start where the one working data point is; lift once a sustained `dd` is clean ([U3]). ALTERA's `200000000` is a no-op ceiling. |
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

**Settled `[V]`, not merely likely.** The DE25 **U-Boot** tree closes it independently of any
Linux DTS: `de25-uboot-socfpga:arch/arm/dts/socfpga_agilex5_de25_nano.dts:11` has
`serial0 = &uart1`, and `...-u-boot.dtsi` sets `stdout-path = "serial0:115200n8"` — and the
friend booted Linux over that console. A board whose bootloader console is uart1 does not have
its Linux console on uart0. Promoted from `[U]` in §7.

### Memory

MAINLINE's `.dtsi` has no memory node, so the board file must supply one.

| Tree | value |
|---|---|
| TERASIC, FRIEND | `memory { reg = <0 0x80000000 0 0x80000000>; }` — 2 GiB, and a node name with no unit address |
| ALTERA, MAINLINE socdk | `memory@80000000 { reg = <0x0 0x80000000 0x0 0x0>; }` — size 0, "we expect the bootloader to fill in the reg" |
| **OURS** | `memory@80000000 { reg = <0x0 0x80000000 0x0 0x40000000>; }` — **1 GiB** |

1 GiB at `0x8000_0000` matches the *UM* and the DE25 **U-Boot** DTS —
`de25-uboot-socfpga:arch/arm/dts/socfpga_agilex5_de25_nano-u-boot.dtsi`, which carries
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
TERASIC and FRIEND's 2 GiB over-claims, ALTERA's and MAINLINE socdk's size 0 boots nothing
without the fixup, and under-claiming degrades gracefully where neither of those does.

**First-boot action: capture U-Boot's `DDR:` lines.** They are the only authority on the real
size, and a `DDR: Warning` there is the signal that any of these DTS constants is wrong.

`de25-reference-implementation.md` asked this of the friend's tree ("Does the DE25-Nano HPS
actually have 2 GiB of DRAM?"). Every DE25 bootloader source says 1 GiB, so his Linux node
over-claims 2× — but "1 GiB" is itself a vendor declaration awaiting the IO96B readout, not a
measurement, and this document should not launder one into the other.

One consequence worth carrying: **all DRAM lives in `0x8000_0000..0xBFFF_FFFF`, entirely inside
32 bits.** That is what makes the SMMU-off escape hatch in §4 safe.

---

## 4. The SMMU / `mmc0` decision (implementation path §8 Q2 and §8 Q1)

**Decision: `&smmu { status = "disabled"; }` for wave 1** — MAINLINE 7.2's own default, and a
deliberate divergence from all three references, which set it `okay`. **`mmc0` keeps both
`iommus = <&smmu 5>` and `dma-coherent`**, and so does every other master in the tree; with the
SMMU off those `iommus` properties are simply inert.

An earlier revision of this document had this the other way round — SMMU on, with SMMU-off
offered as an "escape hatch". **That framing was inverted and is corrected here.** SMMU-on is
not a working configuration on mainline; SMMU-off is the only one that can be.

### 4.1 Why SMMU-on cannot work on a mainline kernel

Traced through `linux-7.2.2` source, not inferred:

| Step | Where | What it does |
|---|---|---|
| 1 | `drivers/firmware/stratix10-svc.c:865-869` | Takes the shared-buffer address straight out of the `INTEL_SIP_SMC_FPGA_CONFIG_GET_MEM` SMC return (`res.a1`/`res.a2`) |
| 2 | `:956` | `devm_memremap()`s that **physical** address |
| 3 | `:1873-1876` | `gen_pool_virt_to_phys()` — the pool hands out **physical** addresses; `:1780` copies one into `pdata->paddr` |
| 4 | `:607` (`COMMAND_RECONFIG_DATA_SUBMIT` → `INTEL_SIP_SMC_FPGA_CONFIG_WRITE`), `:655` (FCS) | Passes that raw physical address to the SDM as SMC argument `a1` |
| 5 | whole file | `grep -c 'iommu_map\|dma_map_single\|dma_alloc'` → **0** |

Meanwhile the svc device inherits `iommus = <&smmu 10>` from the MAINLINE dtsi, and
`arm_smmu_def_domain_type()` (`drivers/iommu/arm/arm-smmu-v3/arm-smmu-v3.c:4294-4304`) returns
`0` for anything that is not a PCI device — so the IOMMU core applies the build default,
`IOMMU_DEFAULT_DMA_STRICT` (`drivers/iommu/Kconfig:100,111`), i.e. a **translated** domain over
a page table nothing has populated. SID 10 therefore gets an S1-translate STE, and the physical
addresses from step 4 are unmapped IOVAs. **The first `RECONFIG_DATA_SUBMIT` faults.**

That SDM traffic genuinely traverses the SMMU is not an assumption — it is precisely what
Terasic's vendor `stratix10-svc.c` compensates for: an IOVA carveout plus explicit `iommu_map()`
calls, a `+0x80000000` address offset, and an `INTEL_SIP_SMC_SDM_REMAPPER_CONFIG` remapper
disable, none of which exists anywhere in mainline at 6.18.44, 7.2 or `master`. Their driver is
the evidence *for* the mechanism, and its absence upstream is the evidence *against* SMMU-on.

This also **sharpens implementation-path §8 Q1** and the one observed on-hardware failure it
records: a `RECONFIG_REQUEST` timeout on the mainline path is exactly what steps 1–5 plus a
translated default domain predict.

### 4.2 SMMU-off is the leg to test first — and it is not proven either

Stated honestly: SMMU-off removes the *identified* fault, it does not establish that mainline
can program this fabric.

- **For**: it is the only shape in which the svc layer's own addressing is self-consistent; it
  is MAINLINE 7.2's shipped default; and the closest supporting data point is the friend's cold
  boot with `iommu.passthrough=1` reaching a login prompt.
- **Against**: Terasic's vendor driver *hard-fails* without the SMMU (its agilex5 probe path
  returns `-ENODEV` absent `altr,smmu_enable_quirk`), and mainline never touches the SDM
  remapper at all. Neither observation transfers cleanly, because the two drivers are doing
  different things, but neither can be waved away.

**Test order for implementation-path §2.6 step 4: SMMU-off first, SMMU-on second.** §2.6
currently presents the two legs as symmetric; they are not, and the ordering matters because a
SMMU-on failure carries no information (it is predicted) while an SMMU-off failure is real news.

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

### 4.4 What this does to §8 Q2 (the `mmc0` DMA width)

With the SMMU off, the §8 Q2 failure mode **cannot occur**: the mechanism is the IOVA allocator
handing out an address above bit 39 that a 40-bit-wired controller truncates, and with no
translation there are no IOVAs. Every DRAM address on this board is inside
`0x8000_0000..0xBFFF_FFFF` (§3, Memory), i.e. well inside 32 bits.

`linux-patches/0101` is still correct and still wanted — it is what makes the SMMU-on leg
survivable, and it is what makes the two-string compatible schema-clean — it is simply not
load-bearing in the shipped configuration.

### 4.5 `dma-coherent` — kept, with a caveat that is new

Kept, corroborated inside MAINLINE itself: the sibling `nand` controller on this same SoC
carries `dma-coherent` in `socfpga_agilex5.dtsi:315`.

**The caveat the SMMU flip introduces:** all three vendor trees assert `dma-coherent` on `mmc0`
with the SMMU **on**, where the cacheability of an access is determined by the STE / `IOMMU_CACHE`
attributes rather than by the master's own `dma-coherent` property. Their evidence therefore does
**not** transfer unchanged to the SMMU-off shape, and the mainline `nand` precedent — which is
about the SoC's interconnect rather than about translation — is now doing more of the work than
it was. The friend's `SETUP.md:139-142` is a live warning in the same area: with
`iommu.passthrough=1`, SDHCI ADMA "can corrupt early SD init" after a JTAG full-SOF load, which
is an SMMU-off ADMA integrity failure whatever its root cause.

So [U2] is **re-opened in the shipped shape**: the integrity check must be run with the SMMU off,
not inherited from the vendors' SMMU-on configuration. If reads come back corrupt, **delete
`dma-coherent` first** — treating a coherent master as non-coherent is always correct and merely
slower; the converse silently corrupts.


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
| D7 | `&smmu` `okay` → **`disabled`** | The one *design* divergence, not a form one. Mainline's svc layer cannot work under a translated domain (§4.1). Also MAINLINE 7.2's own default. All `iommus` properties retained so the reverse is one line. |
| D8 | `mmc0` gains **`max-frequency = <25000000>`** | FRIEND's value. The only mainline-driver boot of this board needed it; mainline programs none of the PHY timing the vendors declare (§3, `max-frequency` row). Lift once [U3] clears. |

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
- **That `mmc0` DMAs correctly.** §4.4/§4.5 argue the shape is right and name the fallbacks;
  [U2] (coherency, in the SMMU-off shape) and [U3] (clock cap) both stay open. §8 Q2's own
  failure mode is out of reach in the shipped configuration, which is a change of exposure, not
  a proof of correctness.
- **That SMMU-off *works*.** §4.1 rules SMMU-on out from source. It does not follow that
  SMMU-off succeeds — Terasic's vendor driver hard-fails without the SMMU, and mainline never
  touches the SDM remapper. [U10] is the live question and §2.6 step 4 is the test.
- **PHY link.** `phy-mode = "rgmii"` with the delays on the PCB is ALTERA's claim, taken on
  their authority and cross-checked against the other two references. Not measured.

---

## 7. Open `[U]` — what could not be settled without hardware

| # | Question | Why it matters | How it is settled |
|---|---|---|---|
| ~~U1~~ | ~~Is the console really `uart1`?~~ | — | **Closed `[V]`.** The DE25 U-Boot tree sets `serial0 = &uart1` and `stdout-path = "serial0:…"` (`de25-uboot-socfpga:.../socfpga_agilex5_de25_nano.dts:11`, `...-u-boot.dtsi`), and the friend booted Linux on that console. Not to be re-litigated. |
| **U2** | Is the SDMMC master really cache-coherent **with the SMMU off**? | `dma-coherent` on a non-coherent master is silent data corruption. The vendors' evidence is all SMMU-**on**, where cacheability comes from the STE/`IOMMU_CACHE` attributes, not this property — so it does not transfer to the shipped shape (§4.5). The friend's `SETUP.md:139-142` records ADMA corrupting early SD init under `iommu.passthrough=1`. | Sustained `dd` read/write + checksum in the **shipped SMMU-off** configuration. If corrupt, delete `dma-coherent` first — the non-coherent treatment is always correct, merely slower. |
| **U3** | Can the 25 MHz clock cap be lifted? | Shipped capped, following the only mainline-driver boot of this board. Mainline programs none of the 40 vendor `cdns,phy-*` values, so PHY state is whatever U-Boot left. | Once a sustained `dd` read/write is clean at 25 MHz, raise in steps (or delete `max-frequency`) and re-run. Watch for `unrecognised SCR structure version` / `-EINVAL` at init, which is the symptom the friend hit. |
| **U4** | Does the SD I/O rail need ALTERA's `regulator-gpio` on `portb 3`? | ALTERA wires `vqmmc-supply` to a 1.8V/3.3V level shifter; we rely on `no-1-8-v` plus the boot-default state. | Only matters if UHS is ever wanted. Until then the shifter never switches. |
| **U5** | `dr_mode` for `usb0` | Unset in all three references, so dwc2 reads OTG capability from the hardware. A MiSTer image wants host mode. | Observe `/sys/class/udc` and whether hubs enumerate; add `dr_mode = "host"` if OTG guesses wrong. |
| **U6** | Should the root compatible say `terasic,de25-nano`? | Currently claims to be an SoCDK. Nothing on arm64 reads it, but it is wrong. | A one-line upstream patch to `Documentation/devicetree/bindings/arm/altera.yaml`, then a one-line DTS change. |
| **U7** | Does `sdhci-caps`' 200 MHz base clock match the silicon? | If the capability register already reports a *different* non-zero base, we override a correct value with a vendor constant and every derived card clock is off — including the 25 MHz cap, which would really be 12.5 MHz if the true base were 100 MHz. | `cat /sys/kernel/debug/mmc0/ios` on first boot; compare `dmesg`'s reported max clock against a raw read of `SDHCI_CAPABILITIES` before the override. |
| **U8** | Do the residual `fpga-mgr` binding warnings get fixed upstream? | Until then this DTB carries 5 warnings and a CI gate would have to allow-list them. | Watch Khairul's v6 fpga-mgr binding series (implementation path §8 Q4). The `mmc0` half is already closed by `0101`. Re-check on every kernel bump. |
| **U9** | **Does BL31 hand back the svc buffer we think it does?** | `memory-region = <&service_reserved>` is **dead on mainline**: `stratix10-svc.c:865-876` takes the address from the `FPGA_CONFIG_GET_MEM` SMC and `:952-960` `memremap`s *that*, never consulting the `no-map` reserved region. If our `u-boot.itb`'s BL31 answers with a region other than `0x8000_0000 + 32 MiB`, the driver memremaps **live kernel RAM** and the SDM writes into it. | `dyndbg='file stratix10-svc.c +p'` on the kernel command line, then compare the driver's `"SM software provides paddr"` / `"reserved memory ... paddr"` debug line against `/proc/device-tree/reserved-memory/svcbuffer@0/reg`. Do this **before** the first reconfiguration attempt. |
| **U10** | Can mainline's svc program the fabric at all, SMMU off? | §4.2. SMMU-on is ruled out by source; SMMU-off is unproven in both directions. | Implementation path §2.6 step 4, **run SMMU-off first**. A SMMU-on failure carries no information; a SMMU-off failure is real news. |


## 8. Corrections owed to sibling documents

| Document | Claim | Correction |
|---|---|---|
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 | The authored node set overrides `/firmware/svc`'s compatible to `"intel,agilex-svc"` | Superseded. We keep MAINLINE's `"intel,agilex5-svc"` and carry `linux-patches/0102` (a one-line match-table addition) instead. The override is retained as the documented fallback. Rationale: the vendor treats the agilex5 string as semantic, so a kernel that will one day want that distinction should not have the DT lie about the SoC. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §2.5 | The two-string fpga-mgr form "warns" under `dtbs_check` | Confirmed and quantified: **five** warning lines, from **two** schemas (`intel,stratix10-svc.yaml` validating the child in place, and `intel,stratix10-soc-fpga-mgr.yaml` validating it standalone), plus the "failed to match any schema" summary. Simulating Khairul's v6 `oneOf`/`items` shape clears all five (§2.4). |
| [`de25-reference-implementation.md`](de25-reference-implementation.md) (open question, line ~664) | "Does the DE25-Nano HPS actually have 2 GiB of DRAM? His memory node hard-codes `reg = <0 0x80000000 0 0x80000000>`…" | **Answered as far as any desk source can: every DE25 bootloader source says 1 GiB.** His Linux node over-claims 2×, and his `x86ram@b0000000 + 0x10000000` would sit past the top of RAM. Our node states 1 GiB — but see the row below: "1 GiB" is a vendor *declaration*, not a measurement. |
| [`de25-boot-chain.md`](de25-boot-chain.md) §3 | "the factory SPL DTB's memory node reads `reg = <0x0 0x80000000 0x0 0x40000000>` = 1 GiB at 0x8000_0000 **[V SPL-dtb]**" | **The `[V]` overstates it.** That is a *constant in Terasic's U-Boot device tree* (`de25-uboot-socfpga:arch/arm/dts/socfpga_agilex5_de25_nano-u-boot.dtsi`, commented `/* 1GB */`), not a readout. The authoritative size comes from the IO96B controller at runtime: `drivers/ddr/altera/sdram_agilex5.c` derives `hw_size` from `io96b_ctrl->overall_size`, caps the DT value at it, and prints `DDR: Warning …` on mismatch. Downgrade to `[V, vendor DTS constant] / [U, hardware]` and capture U-Boot's `DDR:` lines on first boot. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 and §2.6 step 4 | `&smmu { status = "okay"; }` is part of the authored node set, and the two SMMU legs of the programming test are symmetric | **Both corrected.** Mainline's `stratix10-svc` hands the SDM raw physical addresses with no `iommu_map`/`dma_map` anywhere, while the inherited `iommus = <&smmu 10>` puts the svc device on a *translated* default domain — so **SMMU-on cannot program the fabric on a mainline kernel** (§4.1, traced at 7.2.2). Wave 1 ships `status = "disabled"`. The two legs are therefore **not** symmetric: SMMU-off must be run **first**, because a SMMU-on failure is predicted by source and carries no information. |
| [`de25-implementation-path.md`](de25-implementation-path.md) §8 Q2 | The `mmc0` DMA-width question is the leading first-boot risk | Still real, but **not reachable in the shipped configuration**: with the SMMU off there are no IOVAs to truncate and all DRAM is below 4 GiB (§4.4). `linux-patches/0101` remains correct and wanted — it is what makes the SMMU-on leg survivable — but it is not load-bearing for first boot. The *actual* leading first-boot SD risk is PHY timing, which mainline does not program at all; hence the 25 MHz cap ([U3]). |
| [`de25-implementation-path.md`](de25-implementation-path.md) §3.1 | `memory-region = <&service_reserved>` is part of the svc contract | **It is inert on mainline.** `stratix10-svc.c:865-876` takes the buffer from the `FPGA_CONFIG_GET_MEM` SMC and `:952-960` `memremap`s that; the `no-map` reserved region is never consulted. Whether BL31 actually answers with `service_reserved`'s range is a **hardware check that must precede the first reconfiguration attempt** — [U9]. |
| [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §4.2 | The svc node needs `compatible = "intel,agilex-svc"` authored on top of the in-tree dtsi | Only true on a 6.18 base, where the whole subtree is authored. On 7.x the subtree already exists and is inherited; the only additions are the `fpga_mgr` child and the root `fpga-region`. That section's own `[U]` note about the missing `smmu` node is resolved on 7.2: the node exists, `status = "disabled"`, and the board file turns it on. |
