# DTS comparison — stock vs mainline vs ours (P1.7)

The device tree is the highest-risk file in Phase 1: a wrong value here does not fail the
build, it fails the *board*, and one specific mistake (**A14**) kills HDMI with no error
message at all. This document is the evidence that `0004-dts-de10nano-MiSTer.patch` is
correct, node by node, value by value.

Three trees are compared:

| Column | What it is |
|---|---|
| **STOCK** | `docs/stock-inventory/stock.dts` — decompiled from the **appended DTB of the running stock MiSTer kernel** (`work/stock.dtb`). Ground truth for "what the board actually runs today". Not the fork's source; the artifact. |
| **MAINLINE** | `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts` in pristine **linux-6.18.38** (introduced by `144616a80889`, v6.14) + the `socfpga_cyclone5.dtsi` / `socfpga.dtsi` it includes. |
| **OURS** | MAINLINE + `board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch`. |

**Nothing below was written from memory.** Every STOCK value is quoted from `stock.dts`;
every MAINLINE value from the 6.18.38 tree; every OURS value from the **decompiled built
DTB**, not from the source we wrote.

---

## 1. Method (reproducible)

```sh
export PATH=$PWD/output/host/bin:$PATH
cd work/k-dts                                     # pristine linux-6.18.38
cp ../../board/mister/de10nano/linux.config .config
make ARCH=arm CROSS_COMPILE=arm-buildroot-linux-gnueabihf- olddefconfig

# baseline: dtc warnings from the UNPATCHED mainline board DTS
make ARCH=arm CROSS_COMPILE=arm-buildroot-linux-gnueabihf- \
     intel/socfpga/socfpga_cyclone5_de10nano.dtb          # and again with W=1

git apply -p1 ../../board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch
make ARCH=arm CROSS_COMPILE=arm-buildroot-linux-gnueabihf- dtbs

# the real test: decompile what we BUILT and compare it with what stock RUNS
dtc -I dtb -O dts -s -o ours.dts   arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dtb
dtc -I dtb -O dts -s -o stock.dts  ../stock.dtb
# ... then a phandle-resolving structural diff of the two (phandle *numbers* differ
#     between the two blobs and are pure noise; the nodes they point at are what matter)
```

### `dtc` warnings — baseline vs after

| | default `DTC_FLAGS` (what `make dtbs` uses) | `W=1` |
|---|---|---|
| MAINLINE (unpatched) | **0** | 5 |
| OURS | **0** | 5 |
| **new warnings introduced** | **0** | **0** |

The five `W=1` warnings are `simple_bus_reg` complaints about
`/soc/base_fpga_region`, `/soc/stmmac-axi-config`, `/soc/eccmgr`, `/soc/sdramedac` and
`/soc/usbphy` — all of them in the **shared** `socfpga.dtsi`, all of them present in the
unpatched baseline, none of them ours. The two warnings our first draft *did* introduce
(`unit_address_vs_reg` on `MiSTer_fb` and on the three `rtc_at_*` nodes — the same
warnings `stock.dtb` itself produces when decompiled) were fixed by giving those nodes
unit addresses; see §4.

---

## 2. A14 — proof of the i²C adapter numbering

> **A14.** Main_MiSTer never scans past `/dev/i2c-2` (`Main:smbus.cpp:214`,
> `if (force_bus > 2) { … return -1; }`). It finds the ADV7513 HDMI transmitter by probing
> address `0x39` on each of `/dev/i2c-0..2` (`Main:video.cpp:1448`). A **fourth** i²C
> adapter, or a renumbering, can put the transmitter on `/dev/i2c-3`, where Main_MiSTer
> **refuses to look** — no error, no picture.

The proof has four parts. It does **not** depend on knowing which physical bus the ADV7513
is wired to (Phase 0 could not determine that from the schematics — open question **Q-E**);
it does not need to.

### 2.1 Only two drivers in our config can create an i²C adapter

From the **resolved** `.config` (`make olddefconfig` over `board/mister/de10nano/linux.config`):

```
CONFIG_I2C_DESIGNWARE_CORE=y
CONFIG_I2C_DESIGNWARE_PLATFORM=y     <- creates adapters (the 4 HPS I2C controllers)
CONFIG_I2C_GPIO=y                    <- creates adapters (bit-banged)
CONFIG_I2C_BOARDINFO=y  CONFIG_I2C_CHARDEV=y  CONFIG_I2C_SMBUS=y  CONFIG_I2C_ALGOBIT=y
CONFIG_I2C_HID=y                     <- CLIENT driver. Registers no adapter.
```

That is the complete list of `CONFIG_I2C_*` symbols set to `y`/`m`. No `I2C_MUX`, no
DRM/DDC bus, no USB-I²C bridge. Identical adapter-creating set to stock
(`docs/stock-inventory/stock-linux.config:1889,1891`). `I2C_HID` is new in 6.18 relative
to stock, and P1.3 already established it is a *client* driver — it binds to devices **on**
an i²C bus and never calls `i2c_add_adapter()`.

> ⚠ Note for reviewers: `board/mister/de10nano/linux.config` lists only
> `CONFIG_I2C_DESIGNWARE_CORE=y`, not `…_PLATFORM=y`. That is **not** a bug, but it is a
> load-bearing implicit default: in 6.18 `I2C_DESIGNWARE_CORE` has a prompt and
> `I2C_DESIGNWARE_PLATFORM` is `default I2C_DESIGNWARE_CORE`
> (`drivers/i2c/busses/Kconfig:564,584-588`), so `olddefconfig` turns PLATFORM on. Verified
> in the resolved `.config` above. If a future Kconfig refactor breaks that default, **every
> HPS i²C bus disappears and HDMI dies** — the exact A14 failure, from the config side.
> Worth an explicit `CONFIG_I2C_DESIGNWARE_PLATFORM=y` in the config file.

### 2.2 Our DTB enables exactly three adapters — the same three as stock

Enumerated from the **built DTB**, not from the source:

| # | node | compatible | STOCK | OURS |
|---|---|---|---|---|
| | `/soc/i2c@ffc04000` (HPS I2C0) | `snps,designware-i2c` | **okay** | **okay** |
| | `/soc/i2c@ffc05000` (HPS I2C1) | `snps,designware-i2c` | `disabled` | `disabled` |
| | `/soc/i2c@ffc06000` (HPS I2C2) | `snps,designware-i2c` | **okay** | **okay** |
| | `/soc/i2c@ffc07000` (HPS I2C3) | `snps,designware-i2c` | `disabled` | `disabled` |
| | `/i2c_gpio` (portb 22 = SDA, 23 = SCL) | `i2c-gpio` | **okay** | **okay** |
| | **total enabled adapters** | | **3** | **3** |

Same three buses, same registers, same GPIO pins (`gpios = <&portb 22 6>, <&portb 23 6>`,
byte-identical to stock, `6` = `GPIO_ACTIVE_HIGH | GPIO_OPEN_DRAIN`). The i²C *clients* we
changed (the accelerometer's node name, the three RTC compatibles, the spidev compatible)
are clients — they create no adapters.

### 2.3 Three adapters, numbered dynamically from zero, can only be {0, 1, 2}

* Neither STOCK nor OURS has any `i2c` **alias**. (`/aliases` in both:
  `serial0`, `serial1`, `timer0..3`, `ethernet0` — no `i2cN`.) So `i2c_add_adapter()` takes
  the *dynamic* path, not `__i2c_add_numbered_adapter()`:

  ```c
  /* 6.18 drivers/i2c/i2c-core-base.c:1657-1677 */
  int i2c_add_adapter(struct i2c_adapter *adapter) {
          id = of_alias_get_id(dev->of_node, "i2c");
          if (id >= 0) { adapter->nr = id; return __i2c_add_numbered_adapter(adapter); }
          id = idr_alloc(&i2c_adapter_idr, NULL, __i2c_first_dynamic_bus_num, 0, GFP_KERNEL);
          adapter->nr = id;
  ```

* `__i2c_first_dynamic_bus_num` is **0** on this board. It is a plain global
  (`drivers/i2c/i2c-boardinfo.c:25`, BSS ⇒ 0) and there are exactly two things that can
  raise it, neither of which fires here:
  1. `i2c_init()` → `of_alias_get_highest_id("i2c")` (`i2c-core-base.c:2093-2097`) — no i²C
     aliases exist, returns `-ENODEV`.
  2. `i2c_register_board_info()` (`i2c-boardinfo.c:58`) — never called on a DT-only ARM boot.

* ⇒ `idr_alloc(..., 0, 0, ...)` hands out **0, 1, 2** to the three adapters, in whatever
  order they register. **There is no fourth adapter and no adapter can be numbered ≥ 3.**
  Whichever of the three physical buses the ADV7513 hangs on — and it hangs on one of them,
  because these are byte-identically the buses stock enables and HDMI works on stock —
  Main_MiSTer's `0..2` scan reaches it. **A14 holds.**

### 2.4 …and the order is stock's order too (belt and braces)

A14 only needs "≤ 3 adapters". But the *assignment* is also identical to stock:

* Both `i2c-designware-platdrv` and `i2c-gpio` register at **`subsys_initcall`** — in 6.18
  (`i2c-designware-platdrv.c:400`, `i2c-gpio.c:497`) **and in the stock 5.15 fork**
  (`…platdrv.c:427`, `i2c-gpio.c:513`). Same level ⇒ ties are broken by link order, and
  `drivers/i2c/busses/Makefile` puts `i2c-designware-platform.o` before `i2c-gpio.o` in
  both trees (6.18: lines 57/68; fork: lines 55/64).
* All DT platform devices already exist by then (`of_platform_default_populate` runs at
  `arch_initcall_sync`), so DesignWare probes its two devices first, in DT order —
  `0xffc04000` then `0xffc06000` — taking **i2c-0** and **i2c-1**.
* `i2c-gpio` additionally *cannot* win the race: it needs GPIO descriptors from
  `gpio-dwapb`, which is a `module_platform_driver` (`gpio-dwapb.c:862` ⇒ `device_initcall`,
  **after** `subsys_initcall`). Its first probe therefore returns `-EPROBE_DEFER` and it is
  retried on the deferred-probe pass. It gets **i2c-2**.

⇒ `i2c-0` = HPS I2C0, `i2c-1` = HPS I2C2, `i2c-2` = the bit-banged RTC bus. Same as stock.

### 2.5 What is still NOT proven without hardware

The chain above proves *reachability* (three adapters, numbered 0–2). It does **not** prove
the ADV7513 answers — that requires the board. **P1.13 must assert, in the boot log:**

* `ls /dev/i2c-*` → exactly `i2c-0 i2c-1 i2c-2`, and **no `/dev/i2c-3`**;
* Main_MiSTer prints `Opened /dev/i2c-N for device 0x39` (`smbus.cpp:260`) and **not**
  `ADV7513 not found on i2c bus! HDMI won't be available!` (`video.cpp:1451`).

---

## 3. Node-by-node comparison

`—` = node/property absent. Values are as they appear in the **built/decompiled DTBs**.

### 3.1 Nodes MiSTer needs that mainline does not enable

| Node | STOCK | MAINLINE | OURS | Notes |
|---|---|---|---|---|
| `&usb1` (`usb@ffb40000`) | okay, `dr_mode="host"`, `disable-over-current` | `disabled` | **identical to stock** | The only USB port on the board. |
| `&usb0` | `disabled` | `disabled` | `disabled` | Not wired out. |
| `&fpga_bridge0` (lwhps2fpga) | okay | `disabled` | **okay** | |
| `&fpga_bridge1` (hps2fpga) | okay | `disabled` | **okay** | |
| `&fpga_bridge2` (fpga2hps) | okay | `disabled` | **okay** | |
| `&fpga_bridge3` (fpga2sdram) | `disabled` | `disabled` | `disabled` | Stock leaves it off; so do we. |
| `&spi0` | okay | `disabled` | **okay** | |
| `&spi0/spiusb@0` | `MiSTer,spi-audio`, 10 MHz, `spi-cpha`, `spi-cpol` | — | **identical** (`spi-max-frequency = <0x989680>`) | Consumed by patch `0002`. SPI bus 0. |
| `&spi1` | okay | `disabled` | **okay** | |
| `&spi1/spidev@0` | `spibri@0`, `compatible="altspi"`, 25 MHz | — | `spidev@0`, `compatible="rohm,dh2228fv"`, 25 MHz | **See §5 (P1.8).** |
| `&i2c2` | okay, `clock-frequency=<100000>` | `disabled` | **okay, `clock-frequency=<100000>`** | Adapter #3 of 3. |
| `&uart1` | okay | okay (implicitly — no `status` in the dtsi) | okay | Enabled in all three; the change is the DMA deletion below. |
| `&uart0`/`&uart1` `dmas`/`dma-names` | **absent** | present (`<&pdma 28/29>`, `<&pdma 30/31>`) | **deleted** | `/delete-property/`. Verified: the pristine DTB has 2 `dmas` properties, ours has **0**. DW UART DMA is unreliable on this SoC; stock deletes them too. |
| `MiSTer_fb` | `reg=<0x22000000 0x800000>`, `interrupt-parent=<&intc>`, `interrupts=<0 40 1>` | — | **identical values**, node renamed `MiSTer_fb@22000000` | See §4. IRQ 40 = GIC SPI 40 = FPGA→HPS `f2h_irq0`. Consumed by patch `0001`. |
| `i2c_gpio` | `i2c-gpio`, `gpios=<&portb 22 6>,<&portb 23 6>`, `i2c-gpio,delay-us=<2>` | — | **byte-identical** | SDA = portb 22, SCL = portb 23 (index order; `i2c-gpio.c:381,389`). |
| `i2c_gpio` children | `rtc_at_51` `"pcf8563"`, `rtc_at_68` `"m41t81"`, `rtc_at_6F` `"mcp7941x"` | — | `rtc@51` `"nxp,pcf8563"`, `rtc@68` `"st,m41t81"`, `rtc@6f` `"microchip,mcp7941x"` | See §4. |
| `leds/hps0` | `gpio-leds`, `label="hps_led0"`, `gpios=<&portb 24 0>`, `linux,default-trigger="mmc0"` | — | **byte-identical** | **ABI**: the class-device name comes from `label` ⇒ `/sys/class/leds/hps_led0`, which Main_MiSTer polls (`brightness_hw_changed`, patch `0029`). The `mmc0` trigger is registered by mainline's mmc core (`drivers/mmc/core/host.c:656`, `led_trigger_register_simple(dev_name(&host->class_dev))`), so it resolves. |
| `regulator_3_3v` | `regulator-fixed`, "3.3V", 3300000/3300000 | — | **byte-identical** (node name `3-3-v-regulator` kept) | |
| `&mmc0` `vmmc-supply`/`vqmmc-supply` | `<&regulator_3_3v>` both | — | **identical** | |
| `&gmac1` | okay, `phy-mode="rgmii"`, 12 × `*-skew-ps`, `max-frame-size=<3800>` | okay, `phy-mode="rgmii-id"`, only 6 skews | **stock's values, exactly** | See §3.2. |
| `aliases/ethernet0` | `= &gmac1` | — | **`= &gmac1`** | **Load-bearing** — see §3.3. |
| `&gpio0/1/2` | okay | okay | okay | Already enabled by mainline. |
| `&i2c0` | okay + accelerometer | okay + accelerometer | okay + accelerometer | Adapter #1 of 3. |
| `chosen/bootargs` | `"earlyprintk"` | — | `"earlyprintk"` | Inert: U-Boot's `fdt_chosen()` overwrites it from `$bootargs` (`docs/boot-chain.md` §4.2). Carried for parity. |
| `cpus` OPP / `operating-points` | **none** | none | none | For **P1.6**: stock's DTS carries **no** OPP/cpufreq nodes at all — `cpu@0`/`cpu@1` have only `compatible`/`device_type`/`reg`/`next-level-cache`. Consistent with P1.6 carrying the `socfpga-cpufreq` driver rather than switching to `cpufreq-dt`. |

### 3.2 `&gmac1` — every skew value, checked

| Property | STOCK | MAINLINE | OURS |
|---|---|---|---|
| `phy-mode` | `"rgmii"` | `"rgmii-id"` | **`"rgmii"`** |
| `txd0/1/2/3-skew-ps` | `0` ×4 | — | **`0` ×4** |
| `rxd0/1/2/3-skew-ps` | `420` ×4 (`0x1a4`) | `420` ×4 | **`420` ×4** |
| `txen-skew-ps` | `0` | `0` | **`0`** |
| `txc-skew-ps` | `1860` (`0x744`) | — | **`1860`** |
| `rxdv-skew-ps` | `420` | `420` | **`420`** |
| `rxc-skew-ps` | `1680` (`0x690`) | — | **`1680`** |
| `max-frame-size` | `3800` (`0xed8`) | — | **`3800`** |

Why stock's values and not mainline's: mainline asks the KSZ9031 for its *internal* delay
(`rgmii-id`) and leaves the clock skews at chip default; stock uses `rgmii` and dials the
delay in explicitly with `txc-skew-ps`/`rxc-skew-ps`. These are **not** interchangeable —
applying mainline's `rgmii-id` on top of stock's skews would double the delay. We take
stock's pair wholesale because that is the combination the hardware is known to link at.

There is no `mdio`/`phy` child node in either tree; the skews still reach the PHY because
`ksz9031_config_init()` walks *up* the device parents until it finds an `of_node`
(`drivers/net/phy/micrel.c`) — which is the MAC node these properties live on.

### 3.3 `aliases/ethernet0` — do not drop this

Mainline's `socfpga.dtsi` has no `ethernet0` alias; stock's DTB does. It is **not**
cosmetic. U-Boot boots us with an explicit FDT pointer (`bootz $loadaddr - $fdt_addr`,
`docs/boot-chain.md` §4.1), so it runs `image_setup_libfdt()`
(`work/U-Boot_MiSTer/common/image-fdt.c:497`) → **`fdt_fixup_ethernet()`**
(`common/fdt_support.c:470`), which walks `/aliases`, looks for `ethernetN`, and writes
`$ethaddr` into the node it points at. Without the alias the MAC address is never injected.

---

## 4. Deliberate divergences from stock (and why each is safe)

Every difference the decompiled-DTB diff turns up, accounted for.

| # | Divergence | Why |
|---|---|---|
| D1 | `MiSTer_fb` → **`MiSTer_fb@22000000`** | Silences dtc's `unit_address_vs_reg` (a node with `reg` must have a unit address) — the one warning our patch would otherwise add at `W=1`; `stock.dtb` produces it too. **Provably a no-op**: the driver matches on `compatible` (`MiSTer_fb.c:380`, `.of_match_table`), and the platform device is named from the *translated reg* plus `%pOFn`, which strips the unit address — `of_device_make_bus_id()`, `drivers/of/device.c:298-305` — so the device is `22000000.MiSTer_fb` either way. Main_MiSTer touches the driver only via `/sys/module/MiSTer_fb/parameters/mode` (`video.cpp:3548`), never via the DT path. |
| D2 | `rtc_at_51/68/6F` → **`rtc@51/68/6f`**, and `"pcf8563"`/`"m41t81"`/`"mcp7941x"` → **`"nxp,pcf8563"`/`"st,m41t81"`/`"microchip,mcp7941x"`** | Same `unit_address_vs_reg` fix, plus the vendored compatibles are the *primary* match path. All three are in 6.18's OF match tables — `rtc-pcf8563.c:569`, `rtc-m41t80.c:103`, `rtc-ds1307.c:1142`. Stock's bare strings only matched via the i²C core's vendor-prefix-stripping fallback (`i2c_of_match_device_sysfs()`); the vendored form matches directly. i²C client node names are cosmetic — the sysfs name is `bus-addr` (`0-0051`), never the DT node name. |
| D3 | `speed-mode = <0>` **dropped** from `i2c0` and `i2c2` | **Dead property.** `grep -rn '"speed-mode"' --include=*.c --include=*.h` over the whole 6.18 tree → **zero hits**. No driver has ever read it. Bus speed comes from `clock-frequency`, and both buses are at the same 100 kHz as stock: stock's `i2c0` has *no* `clock-frequency` and gets i2c-designware's 100 kHz default; ours states `100000` explicitly. `i2c2` is `100000` in both. |
| D4 | `timeouts = <3>` **dropped** from `spi0` and `spi1` | Same: `grep -rn '"timeouts"'` over 6.18 → **zero hits**. Not in any binding, not read by `spi-dw`. Cargo cult. |
| D5 | `status = "okay"` dropped from the `spi0`/`spi1` **child** nodes | An absent `status` *is* "okay" (`of_device_is_available()`); stock states it redundantly. |
| D6 | `i2c1` (`ffc05000`) `clock-frequency = <100000>` **not carried** | Stock has it only because the fork patched the **shared** `socfpga.dtsi`, which affects every socfpga board. `i2c1` is **`disabled`** in stock and in ours, so `i2c_designware_probe()` never runs and the property is never read. Not carrying it keeps patch `0004` off a shared SoC file, as P0.4 recommended. |
| D7 | Accelerometer: `adxl345@53` → `accelerometer@53`; `interrupts = <3 2>` (EDGE_FALLING) → `<3 IRQ_TYPE_LEVEL_HIGH>` (`4`); `+ interrupt-names = "INT1"` | We keep **mainline's** node as-is. `CONFIG_ADXL345`/`CONFIG_IIO` are **not set** (`board/mister/de10nano/linux.config` — zero `IIO` symbols), so no driver binds and the node is inert for MiSTer. It is an i²C *client*: it creates no adapter and cannot affect A14. |
| D8 | `+ /soc/bus@ff200000` (`simple-bus`, `reg = <0xff200000 0x200000>`) | Mainline's FPGA-overlay attach point. Empty, no children ⇒ no driver binds, nothing is reserved. Main_MiSTer reaches the FPGA registers by `mmap`ing `/dev/mem` at `0xff200000` regardless. Kept as free future capability. |
| D9 | `+ /soc/stmmac-axi-config` and `snps,axi-config` on both `ethernet@` nodes | Mainline's upstream AXI burst settings for this SoC (`snps,wr_osr_lmt`/`rd_osr_lmt = 15`, `snps,blen`). Absent from stock ⇒ stmmac used its defaults. Every other in-tree socfpga board ships this. Accepted as an upstream improvement; if gigabit throughput regresses, this is the first thing to bisect. |
| D10 | `memory` → `memory@0`; `intc@fffed000` → `interrupt-controller@fffed000`; `dwmmc0@ff704000` → `mmc@ff704000`; `nand@` → `nand-controller@`; `l3regs@0xff800000` → `l3regs@ff800000`; `serial0@/serial1@` → `serial@` | Pure mainline node **renames** (6.18 fixed the malformed `@0x…` unit address and adopted the generic names). No functional content changed; all phandle references were verified to resolve to the same targets. `memory@0` is still found by both consumers: Linux scans `device_type = "memory"`, and U-Boot's `fdt_fixup_memory_banks()` uses libfdt's `fdt_subnode_offset()`, whose name comparison explicitly accepts a trailing `@unit-address` (`fdt_nodename_eq_()`). |
| D11 | `/soc/amba/pdma@ffe01000`: `#dma-channels`/`#dma-requests` gone | Mainline removed them upstream; `pl330` reads the counts from the hardware. |
| D12 | `sdmmc_clk`'s `clk-phase = <0 135>` → `mmc0`'s `clk-phase-sd-hs = <0>, <135>` | Mainline moved the SD high-speed clock phase from the clock node to the mmc node. **Same values** (`0x87` = 135). |
| D13 | root `compatible` gains `"terasic,de10-nano"`; `model` "DE10-nano" → "DE10-Nano" | Mainline's. The machine match (`altr,socfpga`) is unchanged and still present. |
| D14 | `uart0` gains `clock-frequency = <100000000>` | Mainline's. A no-op: `dw8250_probe()` reads it first, then overwrites `uartclk` with `clk_get_rate(&l4_sp_clk)` when a `clocks` phandle is present — which it is. Same 100 MHz either way. |
| D15 | spidev compatible `"altspi"` → `"rohm,dh2228fv"` | §5. |

### 4.1 `osc1` — checked, no action needed

P1.6 reported that mainline declares `osc1` (the root of the whole gen5 clock tree) as a
bare `fixed-clock` with no rate, and asked for `&osc1 { clock-frequency = <25000000>; }`.
**That is already the case and needs no patch.** `socfpga.dtsi:124` declares `osc1` without
a rate, but **`socfpga_cyclone5.dtsi:13-18`** — which our board DTS `#include`s — sets
`clock-frequency = <25000000>` on it. Confirmed in the **built DTB**, which is
byte-identical to stock here:

```
osc1 { #clock-cells = <0x00>; clock-frequency = <0x17d7840>; compatible = "fixed-clock"; };
   # 0x17d7840 = 25,000,000 — identical in stock.dtb and in ours.dtb
```

---

## 5. `/dev/spidev1.0` without a kernel patch (P1.8)

Stock's `spi1` child is `compatible = "altspi"`. That is not a mainline binding: it works on
stock only because the fork added the string to `spidev_dt_ids[]` (`drivers/spi/spidev.c`,
fork commit `246984fce`) — the patch planned as `0005-spidev-accept-altspi-compatible.patch`.
6.18's spidev binds **only** compatibles in that table, so an `altspi` node on a stock 6.18
would never probe and `/dev/spidev1.0` would silently not appear.

Since we author the DTS, we change the *DTS* instead of the kernel:

**Chosen compatible: `rohm,dh2228fv`** — because
1. it is already in 6.18's `spidev_dt_ids[]` (and `spidev_spi_ids[]`), so no kernel patch;
2. it is the de-facto mainline placeholder for "this SPI slave is driven from userspace";
3. `spidev_of_check()` — the `.data` callback on every entry — only rejects the literal
   string `"spidev"` appearing in a node's `compatible`, so it passes;
4. it names no MiSTer hardware, and the alternatives are no more honest: the device on this
   bus is an add-on hub (brightness / lid, `Main_MiSTer/brightness.cpp`), **not** MiSTer's
   own I/O board, and no in-table compatible describes it.

⇒ **patch `0005` is dropped, not carried.**

The device node is still bus 1, CS 0. SPI controller bus numbers are assigned exactly like
i²C: no `spi` aliases exist, `spi-dw-mmio` leaves `bus_num = pdev->id = -1` for DT devices,
so `spi_register_controller()` allocates dynamically in probe order — `spi@fff00000` → bus 0
(the audio link), `spi@fff01000` → bus 1. spidev then names the char device
`spidev%d.%d` from `controller->bus_num` and the chip select ⇒ **`/dev/spidev1.0`**, which is
what `brightness.cpp` opens. Same as stock.

**P1.13 must assert `/dev/spidev1.0` exists** and that the boot log carries no
`spidev … without a matching compatible` complaint.

---

## 6. What this document does NOT prove

Honesty about the limits of a bench-only verification:

1. **That the ADV7513 answers.** §2 proves it is *reachable* (three adapters, numbered 0–2,
   on the same physical buses as stock). Only hardware proves it *responds*. → **P1.13**.
2. **That gigabit ethernet links.** The skews are copied from stock exactly, but D9
   (`snps,axi-config`) is a real behavioural difference from stock. → P1.13 / P3.x.
3. **That the RTC add-on board is detected.** Vendored compatibles match 6.18's OF tables
   (D2), but no one here has the add-on board. → **P3.11 (RTC parity)**.
4. **That the FPGA bridges + `MiSTer_fb` produce a picture.** The DT values are stock's; the
   drivers arrive from patches `0001`/`0002`. → P1.13.
5. **`clk-phase-sd-hs` (D12) on real SD cards.** Values are identical to stock's, but the
   plumbing that consumes them changed between 5.15 and 6.18.
