# Q4 decision memo — cpufreq: keep `0003`, adopt the fork's port, or hybrid?

**For:** the owner, reading without a terminal.
**Item:** fork commit `59bcae8ebc53933bc4729af25ae5cd94ade1f756`, branch `MiSTer-v6.18`,
"Port MiSTer CPUFreq to Linux 6.18 with opt-in turbo (#85)", Kasper Olesen, 2026-09-08.
Unsquashed as `refs/pr/85`: `3f8cc62c34` (the port), `60e0d56bdd` (OCRAM tail reservation +
allocator range check), `d49875d491` (`CONFIG_ARM_SOCFPGA_CPUFREQ=m` in `MiSTer_defconfig`).
**Ground:** vanilla = **6.18.49** (release commit `1c732c6b94f0`, `linux-6.18.y`). The image pins
6.18.50; no 6.18.50 tree was reachable from this session (`fork-sync-2026-09/env.md`, "The gap").
Nothing below depends on a hunk that moved between .49 and .50, but it is unverified.

---

## 0. The three findings that should decide this

1. **Option C's premise is false.** The plan assumed the fork's driver changes the
   `scaling_max_freq`-only contract for community overclock scripts. It does not: **both**
   drivers set `.set_boost = cpufreq_boost_set_sw` with `.boost_enabled = false` and flag the
   1000/1200 rows `CPUFREQ_BOOST_FREQ`. The sysfs behaviour is **identical**, including the
   `boost` file, which **does exist** on our current build. See §4 — and note that
   `docs/abi-contract.md:1670` says the opposite and is **stale**.
2. **Our `0003` does two of the fork author's three suspected hang causes** (DDR execution
   through the PLL-bypass window; a single-step VCO jump; no `OUTRESETALL`) — it does **not**
   gate FPGA-facing clocks. But it is also the code that **stock shipped for four years** and
   that **reached 1.2 GHz on our own DE10-Nano on 6.18.33** (`docs/testlogs/p1-first-boot.md:118`).
   See §3.
3. **Their build is clean on our tree.** Their diff applies to 6.18.49 with `patch -p1 -F0`
   with zero fuzz, configures `=y` against our `linux.config`, and compiles `W=1` with **zero
   warnings** (§7). Adoption is not blocked by mechanics; it is blocked by evidence.

**Recommendation: A** (keep `0003`; record Q4 as a deliberate divergence), **plus two amendments**
that are independent of A/B/C: fix the stale `abi-contract.md` row (§4) and carry the OCRAM tail
reservation into `0004` (§6). Track **B** as a bench-gated follow-up. Reasoning in §8.

---

## 1. What OUR patch does

File: `board/mister/de10nano/linux-patches/0003-cpufreq-cyclone5-de10nano-overclock.patch`
(566 lines; Michael Huang's 5.15 driver, forward-ported; squash of fork `3d72b9db7` + `e6df8e30e`).

**Where the PLL retune executes: from DDR.** There is no OCRAM anywhere in the patch. Every
occurrence count is zero:

```
$ grep -c OCRAM   0003-...patch   -> 0
$ grep -c ocram   0003-...patch   -> 0
```

The transition is an ordinary module function in kernel text (DDR):

```
0003-...patch:418   +static int socfpga_target_index(struct cpufreq_policy *policy,
0003-...patch:419   +	unsigned int index)
0003-...patch:427   +	mutex_lock(&socfpga_cpufreq_mutex);
0003-...patch:429   +	current_vco_clock_hz = get_vco_clock_hz();
0003-...patch:433   +	if (target_vco_clock_hz == current_vco_clock_hz) {
0003-...patch:434   +		set_dividers(clock_data);
0003-...patch:435   +	} else if (target_vco_clock_hz > current_vco_clock_hz) {
0003-...patch:436   +		set_dividers(clock_data);
0003-...patch:437   +		set_vco_freq(clock_data);
0003-...patch:438   +	} else if (target_vco_clock_hz < current_vco_clock_hz) {
0003-...patch:439   +		set_vco_freq(clock_data);
0003-...patch:440   +		set_dividers(clock_data);
0003-...patch:441   +	}
0003-...patch:443   +	mutex_unlock(&socfpga_cpufreq_mutex);
0003-...patch:445   +	return 0;
```

**Does it bypass the main PLL while executing from DDR? Yes.** Both halves bracket their writes
with main-PLL bypass:

```
0003-...patch:376   +static inline void set_dividers(const struct socfpga_clock_data *clock_data)
0003-...patch:378   +	// Put main PLL into bypass
0003-...patch:379   +	writel(CLKMGR_BYPASS_MAINPLL, socfpga_cpufreq_clk_mgr_base_addr +
0003-...patch:380   +		CLKMGR_GEN5_BYPASS);
0003-...patch:381   +	wait_for_fsm();
0003-...patch:384   +	writel(clock_data->alteragrp_mpuclk,   ... + ALTR_MPUCLK);
0003-...patch:392   +	writel(clock_data->mainpll_cfgs2fuser0clk, ... + MAINPLL_CFGS2FUSER0CLK);
0003-...patch:397   +	// Put main PLL out of bypass
0003-...patch:398   +	writel(0, socfpga_cpufreq_clk_mgr_base_addr + CLKMGR_GEN5_BYPASS);
0003-...patch:399   +	wait_for_fsm();
```

```
0003-...patch:402   +static inline void set_vco_freq(const struct socfpga_clock_data *clock_data)
0003-...patch:405   +	writel(CLKMGR_BYPASS_MAINPLL, ... + CLKMGR_GEN5_BYPASS);
0003-...patch:407   +	wait_for_fsm();
0003-...patch:409   +	// Set VCO register
0003-...patch:410   +	writel(calculate_vco_reg(clock_data->vco_numer, clock_data->vco_denom),
0003-...patch:411   +		socfpga_cpufreq_clk_mgr_base_addr + MAINPLL_VCO);
0003-...patch:413   +	// Put main PLL out of bypass
0003-...patch:414   +	writel(0, ... + CLKMGR_GEN5_BYPASS);
0003-...patch:415   +	wait_for_fsm();
```

The bypass window is survivable from DDR because the SDRAM controller runs off the *SDRAM* PLL,
not the main PLL; in bypass the L3/L4 interconnect falls back to osc1 (25 MHz) and code keeps
running, slowly. That is by design in the 5.15 original — the bypass bracketing in
`set_dividers()` is exactly what fork commit `e6df8e30e` ("Improve clock transition stability")
*added* in 2022.

**Does it gate FPGA-facing clocks? No.** The only clock-manager offsets it defines are:

```
0003-...patch:212   +#define CLKMGR_GEN5_BYPASS     0x04
0003-...patch:213   +#define CLKMGR_STAT            0x14
0003-...patch:214   +#define MAINPLL_VCO            0x40
0003-...patch:215   +#define MAINPLL_MPUCLK         0x48
0003-...patch:216   +#define MAINPLL_CFGS2FUSER0CLK 0x5c
0003-...patch:217   +#define ALTR_MPUCLK            0xe0
```

`0x60` (main-PLL group enable) and `0xa0` (peripheral-PLL group enable) appear **nowhere**
(`grep -c 0x60` → 0, `grep -c 0xa0` → 0). It rewrites the C5 divider at `0x5c` **without** gating
C5 first, which the Cyclone V TRM (as quoted in the fork author's own notes, `59bcae8eb` commit
message: *"C0-C2 are hardware-managed. C3-C5 require software gating"*) says you should not do.

**`OUTRESETALL`? No.** `grep -c OUTRESETALL` → 0, `grep -c outreset` → 0. The VCO write is a
read-modify-write masked to numerator+denominator only, so the reset bits are preserved untouched:

```
0003-...patch:230   +#define MAINPLL_VCO_MASK 0x003ffff8      /* numer[15:3] + denom[21:16] only */
0003-...patch:311   +	vco_reg = readl(... + MAINPLL_VCO);
0003-...patch:312   +	return (vco_reg & ~MAINPLL_VCO_MASK) | (((denom << VCO_DENOM_OFFSET) |
0003-...patch:313   +		(numer << VCO_NUMER_OFFSET)) & MAINPLL_VCO_MASK);
```

**VCO stepping? One jump.** `set_vco_freq()` writes the final numerator in a single `writel`
(line 410 above). 800 → 1000 MHz is numer 63 → 79 (VCO 1600 → 2000 MHz, **+25 %**); 800 → 1200 is
63 → 95 (**+50 %**), in one write.

**Interrupts / the other CPU? Neither.** The only synchronisation is `mutex_lock()`
(`0003-...patch:427`). `grep -c stop_machine` → 0, `grep -c local_irq` → 0. CPU1 keeps executing
DDR-resident kernel code with interrupts on, through the bypass window and the frequency change.

**Timers after the MPU clock changes.** Two mechanisms, only one of which our driver gets:

* `loops_per_jiffy` / `udelay` — **correct in both drivers**, because both use `->target_index`,
  so the cpufreq core emits `CPUFREQ_POSTCHANGE` and ARM rescales:
  `$S/linux/arch/arm/kernel/smp.c:794` `static int cpufreq_callback(...)`,
  `:820` `loops_per_jiffy = cpufreq_scale(global_l_p_j_ref, ...)`, registered at `:836-841`.
* The **A9 TWD per-CPU clockevent** — **stale under `0003`**. Its rate comes from the CCF:
  `$S/linux/arch/arm/boot/dts/intel/socfpga/socfpga.dtsi:861-866`
  `timer@fffec600 { compatible = "arm,cortex-a9-twd-timer"; clocks = <&mpu_periph_clk>; }`, and
  `mpu_periph_clk` is `mpuclk / 4` (`socfpga.dtsi:286-291`, `fixed-divider = <4>`). `smp_twd`
  only learns of a change through a **clk notifier**:
  `$S/linux/arch/arm/kernel/smp_twd.c:110` `static int twd_rate_change(...)`,
  `:118` `if (flags == POST_RATE_CHANGE) on_each_cpu(twd_update_frequency, ...)`,
  `:131-138` `twd_clk_init() { ... clk_notifier_register(twd_clk, &twd_clk_nb); }`.
  `0003` never calls the CCF (`grep -c clk_notifier` → 0; it pokes `clk_mgr` registers directly),
  so **no notification is ever sent** and `twd_timer_rate` keeps its boot value. Consequence: at
  1200 MHz the TWD really runs at 300 MHz while the kernel believes 200 MHz → local-timer
  interrupts fire ~1.5× early (wasted wakeups, self-correcting because timekeeping comes from the
  `timer1` dw-apb clocksource — `docs/testlogs/p1-first-boot-dmesg.txt:36`
  `clocksource: Switched to clocksource timer1`). At the **400 MHz** row the error runs the other
  way: TWD 100 MHz believed to be 200 MHz → every local-timer deadline expires **2× late**. That
  is a real (if narrow — nothing selects 400 under the `performance` default governor) defect that
  the fork's design fixes for free. *Not confirmed on hardware:* the July dmesg carries no TWD
  banner (`smp_twd` is silent on success), so confirm with
  `cat /sys/devices/system/clockevents/clockevent0/current_device` on the bench.

Also carried deliberately: `wait_for_fsm()` passes a **mask** where `wait_on_bit()` wants a **bit
number**, so it polls bit 1 of `CLKMGR_STAT` instead of bit 0 and returns immediately —
`0003-...patch:335-339`, documented at `:132-142` and `docs/patch-provenance.md:1522`. In effect
**all four `wait_for_fsm()` calls above are no-ops** and PLL settling is covered only by
register-write latency.

---

## 2. What THEIR port does

Five pieces (all quotes are from the blobs at `59bcae8eb`):

**(a) A real CCF clock provider for `mpuclk`.** `drivers/clk/socfpga/clk-mister-cpu.c` (343 lines)
implements `.recalc_rate/.round_rate/.set_rate`:

```
clk-mister-cpu.c:318   const struct clk_ops socfpga_mister_cpu_ops = {
clk-mister-cpu.c:319   	.recalc_rate = mister_cpu_recalc_rate,
clk-mister-cpu.c:320   	.round_rate = mister_cpu_round_rate,
clk-mister-cpu.c:321   	.set_rate = mister_cpu_set_rate,
clk-mister-cpu.c:322   };
```

installed by hijacking the ops of the `reg = <0x48>` periph-clock node:

```
clk-periph.c hunk:  -	init.ops = ops;
                    +	init.ops = socfpga_mister_cpu_clock(node) ? &socfpga_mister_cpu_ops : ops;
                    -	init.flags = 0;
                    +	init.flags = IS_ENABLED(CONFIG_ARM_SOCFPGA_CPUFREQ) ?
                    +		     CLK_GET_RATE_NOCACHE : 0;
clk-pll.c hunk:     -	init.flags = 0;
                    +	init.flags = IS_ENABLED(CONFIG_ARM_SOCFPGA_CPUFREQ) ?
                    +		     CLK_GET_RATE_NOCACHE : 0;
```

Board and clock-plan gating:

```
clk-mister-cpu.c:324   bool __init socfpga_mister_cpu_clock(struct device_node *node)
clk-mister-cpu.c:329   	if (!IS_ENABLED(CONFIG_ARM_SOCFPGA_CPUFREQ) ||
clk-mister-cpu.c:330   	    !of_machine_is_compatible("terasic,de10-nano") ||
clk-mister-cpu.c:331   	    of_property_read_u32(node, "reg", &reg) || reg != CM_MPU)
clk-mister-cpu.c:332   		return false;
clk-mister-cpu.c:334   	np = of_find_node_by_name(NULL, "osc1");
clk-mister-cpu.c:339   	if (reg || rate != 25000000)
clk-mister-cpu.c:340   		return false;
```

Because CCF owns the transaction, `clk_set_rate()` fires `PRE/POST_RATE_CHANGE` down the subtree,
so `smp_twd`'s notifier (§1) runs and the TWD stays correct — this is what the commit message
means by *"Notify dependent clocks, including the local TWD timers."*

**(b) A hardware-plan sanity check before every transition** (`mister_check_plan()`,
`clk-mister-cpu.c:164-188`): refuses if a fault is latched, if the PLL is already bypassed or in
safe mode, if the main PLL is not locked, if any `OUTRESET` bit is set, if the denominator is
non-zero, if L4 is not sourced from the peripheral PLL, or if the current register set does not
exactly match one of the four known rows. It also refuses to retune while a flash controller is
sourced from the PLL being changed:

```
clk-mister-cpu.c:140   static int mister_flash_gates(u32 *gates)
clk-mister-cpu.c:146   	if (FIELD_GET(GENMASK(1, 0), src) == 1) {
clk-mister-cpu.c:147   		if (mister_device_enabled("altr,socfpga-dw-mshc"))
clk-mister-cpu.c:148   			return -EBUSY;
```

*(Note for us: MiSTer boots from SD via `altr,socfpga-dw-mshc`. Whether `CM_PER_SRC` selects the
main PLL for SDMMC on a MiSTer DTB decides whether this returns `-EBUSY` and disables 1000/1200
outright. Unverified — bench item.)*

**(c) The retune runs from a reserved OCRAM page under `stop_machine`.**

```
clk-mister-cpu.c:195   static int __init mister_setup_ocram(void)
clk-mister-cpu.c:209   	np = of_find_compatible_node(NULL, NULL, "mmio-sram");
clk-mister-cpu.c:220   	allocation = gen_pool_alloc_algo(pool, PAGE_SIZE,
clk-mister-cpu.c:221   					 gen_pool_first_fit_align, &align);
clk-mister-cpu.c:225   	if (physical < MISTER_OCRAM_BASE ||
clk-mister-cpu.c:226   	    physical > MISTER_OCRAM_FLAGS - PAGE_SIZE) {
clk-mister-cpu.c:227   		gen_pool_free(pool, allocation, PAGE_SIZE);
clk-mister-cpu.c:229   		return -ERANGE;
clk-mister-cpu.c:231   	mapping = __arm_ioremap_exec(physical, PAGE_SIZE, false);
clk-mister-cpu.c:236   	mister_ocram_fn = (void *)fncpy(mapping, &socfpga_mister_ocram,
clk-mister-cpu.c:245   late_initcall(mister_setup_ocram);
```

```
clk-mister-cpu.c:307   	ret = stop_machine(mister_transition, &tr, NULL);
clk-mister-cpu.c:308   	if (ret)
clk-mister-cpu.c:309   		pr_err("MiSTer CPU clock transition failed: %d%s\n", ret,
clk-mister-cpu.c:310   		       mister_clock_fault ? "; clock state uncertain, reboot required" : "");
```

The 400↔800 case never leaves C (same VCO, divider only):

```
clk-mister-cpu.c:257   	if (FIELD_GET(CM_VCO_NUMER, cm_read(CM_VCO)) == r->numer) {
clk-mister-cpu.c:258   		cm_update(CM_MPU, CM_COUNTER, r->mpu_ext);
clk-mister-cpu.c:261   			cm_write(CM_MPU, old_mpu);           /* rollback */
```

**(d) The OCRAM assembly** (`clk-mister-ocram.S`, 194 lines, position-independent, no literal
pools, no DDR access in the gated window). The three things the author says his first attempt got
wrong are all addressed there:

*Gating* (C5 and the flash gates are switched off before bypass, restored at the end):
```
clk-mister-ocram.S:47    	bic r2, r6, #0x300        @ clear CM_MAIN_EN bits 8,9 (C5 gates)
clk-mister-ocram.S:48    	str r2, [r0, #0x60]
clk-mister-ocram.S:50    	bic r2, r7, r2            @ clear the computed flash gates
clk-mister-ocram.S:51    	str r2, [r0, #0xa0]
clk-mister-ocram.S:124  .Lrestore_gates:
clk-mister-ocram.S:125   	str r7, [r0, #0xa0]
clk-mister-ocram.S:126   	str r6, [r0, #0x60]
```

*`OUTRESETALL`* (bit 24 of the VCO register, set then cleared before leaving bypass):
```
clk-mister-ocram.S:148  .Lreset_outputs:
clk-mister-ocram.S:150   	ldr r2, [r0, #0x40]
clk-mister-ocram.S:151   	orr r3, r2, #0x1000000
clk-mister-ocram.S:152   	str r3, [r0, #0x40]
clk-mister-ocram.S:154   	str r2, [r0, #0x40]
```

*Incremental VCO steps* (numerator moves ±8 at a time — "at stock N=63, steps of eight change VCO
by at most 12.5 %" — with a settling delay and a bounded LOCK poll after each step):
```
clk-mister-ocram.S:158  .Lramp:
clk-mister-ocram.S:161   	cmp r8, r9
clk-mister-ocram.S:163   	addlo r8, r8, #8
clk-mister-ocram.S:164   	subhi r8, r8, #8
clk-mister-ocram.S:168   	str r2, [r0, #0x40]
clk-mister-ocram.S:170   	movw r3, #2048            @ settle
clk-mister-ocram.S:176   	movw r3, #4096            @ bounded LOCK poll on CM_INTER bit 6
clk-mister-ocram.S:179   	tst r2, #64
clk-mister-ocram.S:183   	mvn r2, #109              @ -ETIMEDOUT
```

*Bounded polling* everywhere — `.Lwait_idle` (`:134-146`) is a 4096-iteration register-read loop,
never a CPU-frequency-calibrated delay; the C side uses
`readl_poll_timeout_atomic(..., 1, CM_TIMEOUT_US)` (`clk-mister-cpu.c:89-90`, `CM_TIMEOUT_US 1000`).

*Rollback* (`:77-103`) restores the old counters and ramps the VCO back; if that fails,
`.Lsafe_bypass` (`:105-114`) leaves the PLL bypassed and returns `-EIO`.

**(e) A thin cpufreq driver** (`drivers/cpufreq/socfpga-cpufreq.c`, 111 lines) that does nothing
but `clk_set_rate()` and verify:

```
socfpga-cpufreq.c:17   static int socfpga_target_index(struct cpufreq_policy *policy, unsigned int index)
socfpga-cpufreq.c:22   	if (rate > 800000000 &&
socfpga-cpufreq.c:23   	    (!cpufreq_boost_enabled() || !policy->boost_enabled))
socfpga-cpufreq.c:24   		return -EINVAL;
socfpga-cpufreq.c:26   	ret = clk_set_rate(policy->clk, rate);
socfpga-cpufreq.c:30   	return clk_get_rate(policy->clk) == rate ? 0 : -EIO;
socfpga-cpufreq.c:44   static struct cpufreq_driver socfpga_driver = {
socfpga-cpufreq.c:51   	.set_boost = cpufreq_boost_set_sw,
socfpga-cpufreq.c:52   	.boost_enabled = false,
```

### Risky or unfinished, in their own words and in the code

| # | Item | Evidence |
|---|---|---|
| R1 | **Long-duration 1200 MHz stability still under test** | commit msg: *"Long-duration 1200 MHz stability remains under test."* |
| R2 | **MiSTer Pi / SuperStation untested** | commit msg: *"MiSTer Pi and SuperStation hardware have not been tested."* |
| R3 | **"OSD movement was reported during scripts" — unexplained** | commit msg: *"Unresolved: OSD movement was reported during scripts. No input injection was performed; a parallel evdev observer is inconclusive under EVIOCGRAB."* An unexplained input-path artefact is exactly the class of bug MiSTer users report as "the menu moved by itself". No mechanism identified here either. |
| R4 | **The corrected boost-off assertion was never rerun** | commit msg: *"The boost-off harness was corrected to check scaling_max_freq instead of cpuinfo_max_freq, but that corrected assertion has not been rerun."* i.e. the one automated check of the exact ABI property §4 turns on is **unvalidated**. |
| R5 | **A hard-hang path by design** | `clk-mister-ocram.S:116-122` `.Lhalt: ... 1: b 1b` — an infinite loop **inside `stop_machine`**, both CPUs frozen, "keep executing in OCRAM for watchdog recovery". We build `CONFIG_DW_WATCHDOG=y` (`board/mister/de10nano/linux.config:375`) but **Main_MiSTer never opens a watchdog** (`grep -ri watchdog $S/main/*.cpp *.h` → no matches), so in practice this is a dead board until power-cycle. |
| R6 | **Latched permanent failure** | `clk-mister-cpu.c:67` `static bool mister_clock_fault;` set at `:263` and `:270`; once latched, `mister_check_plan()` returns `-EIO` forever (`:169-172`) — cpufreq is dead until reboot. |
| R7 | **The clk-side change is not opt-in** | `clk-periph.c`/`clk-pll.c` gate on `IS_ENABLED(CONFIG_ARM_SOCFPGA_CPUFREQ)`, which is true for `=m` too. Building the cpufreq driver as a module you never load still replaces the `mpuclk` ops and sets `CLK_GET_RATE_NOCACHE` on **every** socfpga gen5 pll/periph clock. |
| R8 | **Instruction-level validation was emulation, not silicon** | commit msg: *"actual ARM instruction emulation covering all ten PLL-changing pairs and six injected failure cases"* — the failure paths (R5/R6) have never run on hardware. |
| R9 | **`-EBUSY` if SD is on the main PLL** | `clk-mister-cpu.c:146-149` (see (b)). MiSTer always has an active `dw-mshc`; whether `CM_PER_SRC[1:0] == 1` on a MiSTer board is unverified here. If it is, 1000/1200 never work at all. |

---

## 3. The hang question: does OUR `0003` do any of the three things?

Their claim (`59bcae8eb` commit message): *"The first experimental turbo implementation hung on the
800 -> 1000 MHz transition. It executed from DDR while gating FPGA-facing clocks, omitted
OUTRESETALL and changed the VCO by 25% in one step."*

| Suspected cause | Does `0003` do it? | Evidence |
|---|---|---|
| **Executes from DDR through the PLL-bypass window** | **YES** | `0003-...patch:418-446` is plain kernel text; `grep -c OCRAM` → 0. Bypass asserted at `:379-381` and `:405-407`, released at `:398-399` / `:414-415`. |
| **…while gating FPGA-facing clocks** | **NO** | The patch never writes `0x60` (main-PLL enable) or `0xa0` (periph enable): `grep -c 0x60` → 0, `grep -c 0xa0` → 0; the full offset list is `0003-...patch:212-219`. It changes the C5 divider (`0x5c`, line 392) *ungated*, which is the opposite mistake. |
| **Omits `OUTRESETALL`** | **YES** | `grep -c OUTRESETALL` → 0. `calculate_vco_reg()` masks to `0x003ffff8` (`:220`, `:311-313`), so the reset bits are read back and rewritten unchanged — never asserted. |
| **Changes the VCO by 25 % in one step** | **YES, and worse** | `set_vco_freq()` is a single `writel` of the final numerator (`:410-411`). 800→1000 is numer 63→79 = VCO 1600→2000 MHz (**+25 %**, exactly their case); 800→1200 is 63→95 (**+50 %**). |

So `0003` reproduces **two of the three** (DDR execution, single-step VCO), plus a fourth thing
their revision fixes (`0003`'s bounded-wait is a **no-op** — the `wait_for_fsm()` mask/bit bug,
`:335-339`, `docs/patch-provenance.md:1522`), and avoids the gating one.

### The 5.15 history of "Improve clock transition stability"

`docs/kernel-recon/records/3d72b9db7650bc27b0c4a9931adfb144e3b2850b.json` — `"disposition":
"carried"`, the original driver (#34). `docs/kernel-recon/records/e6df8e30e7b6f7153042520087d1a24c42c28552.json`
— #35, `"carried"`, `"carried_mode": "re-implemented"`. What #35 actually changed (verified by
`git -C fork-6.18 show e6df8e30e`) is **exactly the bypass bracketing in `set_dividers()`**:

```
+        // Put main PLL into bypass
+        writel(CLKMGR_BYPASS_MAINPLL, socfpga_cpufreq_clk_mgr_base_addr +
+                CLKMGR_GEN5_BYPASS);
+        wait_for_fsm();
...
+        // Put main PLL out of bypass
+        writel(0, socfpga_cpufreq_clk_mgr_base_addr + CLKMGR_GEN5_BYPASS);
+        wait_for_fsm();
```

plus reading osc1 from DT. So the 5.15 fork's own answer to instability was *bypass bracketing*,
not OCRAM residency — and that answer shipped in every stock MiSTer image from 2022 until
2026-09-07 (`docs/stock-inventory/20250402/stock-linux.config:500` `CONFIG_ARM_SOCFPGA_CPUFREQ=y`).

### Do we have evidence `0003` works at 1000/1200 on 6.18 hardware?

**Yes, once, at 1200 — and it was an accident.** `docs/testlogs/p1-first-boot.md` (DE10-Nano, real
silicon, 2026-07-12, kernel 6.18.33):

* `:39` — *"| 11 | **P1.6** cpufreq overclock ABI | **PASS** | `cpuinfo_max_freq = 1200000` while
  `scaling_available_frequencies = 800000 400000` … **No `boost` file**"*
* `:117-119` — *"B6, the deliberately unfixed `wait_for_fsm()` bit/mask bug in `socfpga-cpufreq` —
  **the CPU is running at 1.2 GHz, so the PLL path evidently works**, but that bug is latent by
  construction and this boot does not exercise it."*
* `:41` — *"| 17 | **Clean dmesg** | **PASS** | **Zero** errors, warnings, oops, BUG, or call traces"*

That boot predates PR #24: the board was **auto**-overclocking, i.e. the `performance` governor
drove an 800 → 1200 MHz transition (numer 63 → 95, +50 % VCO, one step, from DDR, no
`OUTRESETALL`) during boot, and it completed, repeatedly, across boots.

**But that same behaviour also produced a field hard-hang.** `docs/debug-tooling.md:5-30`:
*"the board was **auto-overclocking itself to 1.2 GHz on boot** … a board that died with no serial
output and needed a power cycle"* — root-caused to the unrequested overclock and fixed in PR #24
(`3fb7f81`, merged `83ae09a`) by adding `->set_boost` and an 800 MHz default;
*"The board is stable and serial console is clean."* **The diagnosis attributed the hang to
*running* at 1.2 GHz on a passively-cooled board, not to the transition** — but nothing in our
records isolates the two, and a transition hang is not excluded by the evidence.

**What we do NOT have:** any hardware test of `0003` *after* PR #24, i.e. of the deliberate path
`echo 1 > .../cpufreq/boost` → `scaling_max_freq` → 1000 or 1200. The full doc sweep
(`grep -rn "1200\|overclock\|cpufreq" docs/*.md README.md docs/testlogs/*.md`) returns exactly
four substantive hits: `docs/testlogs/p1-first-boot.md:39` and `:118` (above),
`docs/debug-tooling.md:13` and `README.md:575` (the auto-OC bug story), and
`docs/patch-provenance.md:1522` (the B6 latent bug, *"NOT FIXED — carried verbatim, deliberately …
Tracked for P1.13 hardware bring-up"*). **1000 MHz has never been observed at all**, on either
implementation, on our image.

---

## 4. Sysfs / ABI contract — the finding that kills option C

`docs/abi-contract.md:1670` currently says:

> *"cpufreq/overclock sysfs (community scripts) — OC is via **`scaling_max_freq`** up to
> `cpuinfo_max_freq` = `1200000`; there is **no** `…/cpu/cpufreq/boost` file (see the P1.6
> correction in `patch-provenance.md` §5)"*

**That row is stale.** It describes `0003` *before* PR #24. The patch we ship today ends with:

```
0003-...patch:502   +	.set_boost     = cpufreq_boost_set_sw,
0003-...patch:503   +	.boost_enabled = false,
```

and the 6.18 core creates the boost files purely from `->set_boost` being non-NULL:

```
$S/linux/drivers/cpufreq/cpufreq.c:2845  static bool cpufreq_boost_supported(void)
                                   :2847  	return cpufreq_driver->set_boost;
                                   :2943  	if (cpufreq_boost_supported()) {
                                   :2944  		ret = create_boost_sysfs_file();
                                   :2850  static int create_boost_sysfs_file(void)
                                   :2854  	ret = sysfs_create_file(cpufreq_global_kobject, &boost.attr);
```
```
$S/linux/drivers/cpufreq/cpufreq.c:1073  		if (cpufreq_boost_supported()) {
                                   :1075  				&cpufreq_freq_attr_scaling_boost_freqs.attr);
                                   :1107  	if (cpufreq_boost_supported()) {
                                   :1108  		ret = sysfs_create_file(&policy->kobj, &local_boost.attr);
```

So **with OUR driver today**: `/sys/devices/system/cpu/cpufreq/boost` **exists** (default `0` —
`show_boost` prints `cpufreq_driver->boost_enabled`, `cpufreq.c:564-567`), a per-policy
`/sys/devices/system/cpu/cpu[01]/cpufreq/boost` exists (`local_boost`, `cpufreq.c:634`), and
`scaling_boost_frequencies` is core-created.

**Can `scaling_max_freq` alone reach 1 200 000 without writing `boost`? No — on either driver.**
The chain, all in 6.18.49:

```
cpufreq.c:746-762   store_one(scaling_max_freq, max)  ->  freq_qos_update_request(policy->max_freq_req, val)
cpufreq.c:2638-2648 new_data.max = freq_qos_read_value(..., FREQ_QOS_MAX);
                    ret = cpufreq_driver->verify(&new_data);
freq_table.c:67-76  int cpufreq_frequency_table_verify(struct cpufreq_policy_data *policy)
                    	cpufreq_verify_within_cpu_limits(policy);
cpufreq.h:497-501   cpufreq_verify_within_cpu_limits() -> cpufreq_verify_within_limits(policy,
                    	policy->cpuinfo.min_freq, policy->cpuinfo.max_freq)
cpufreq.h:492       	policy->max = clamp(policy->max, min, max);
```

and `cpuinfo.max_freq` is derived from the table **with boost rows skipped while boost is off**:

```
freq_table.c:38-59  cpufreq_for_each_valid_entry_idx(pos, table, i) {
                    	if ((!cpufreq_boost_enabled() || !policy->boost_enabled)
                    	    && (pos->flags & CPUFREQ_BOOST_FREQ))
                    		continue;
                    	...
                    	if (policy->cpuinfo.max_freq < max_freq)
                    		policy->max = policy->cpuinfo.max_freq = max_freq;
```

Writing `1 > boost` calls `cpufreq_boost_trigger_state` → `policy_set_boost` →
`cpufreq_boost_set_sw`, which recomputes `cpuinfo` **and immediately raises the running ceiling**:

```
cpufreq.c:2783-2801 int cpufreq_boost_set_sw(struct cpufreq_policy *policy, int state)
                    	ret = cpufreq_frequency_table_cpuinfo(policy);
                    	ret = freq_qos_update_request(policy->max_freq_req, policy->max);
```

Both drivers flag the same rows (`0003-...patch:297-298` `SOCFPGA_CPUFREQ_ROW(1200000,
CPUFREQ_BOOST_FREQ)` / `(1000000, CPUFREQ_BOOST_FREQ)`; `socfpga-cpufreq.c:12-13`
`{ .frequency = 1000000, .flags = CPUFREQ_BOOST_FREQ }, { .frequency = 1200000, .flags =
CPUFREQ_BOOST_FREQ }`), so the observable contract is **byte-for-byte the same**:

| | our `0003` (today) | their driver | stock 5.15 |
|---|---|---|---|
| `/sys/devices/system/cpu/cpufreq/boost` | exists, `0` | exists, `0` | **absent** |
| `cpuinfo_max_freq` before writing boost | `800000` | `800000` | `1200000` |
| `echo 1200000 > scaling_max_freq` alone | clamped to `800000` | clamped to `800000` | reaches 1.2 GHz |
| after `echo 1 > …/cpufreq/boost` | ceiling 1 200 000, and with the `performance` governor the CPU **jumps straight to 1.2 GHz** | same | n/a |
| extra guard | none (table-driven only) | also `-EINVAL` in `->target_index` if boost off (`socfpga-cpufreq.c:22-24`) | n/a |

**Precisely stated:** the behaviour change for community overclock scripts that write only
`scaling_max_freq` **already happened**, in *our* PR #24, on *our* image, in July. It is not a
consequence of adopting the fork's port. Adopting theirs changes **nothing** on this axis, and
option **C** ("keep boost enabled by default to preserve the `scaling_max_freq`-only contract")
would be a *new* divergence from *our own* shipped behaviour, not a preservation of it.

**Action regardless of A/B/C:** rewrite `docs/abi-contract.md:1670` (and the "P1.6 correction" at
`docs/patch-provenance.md:798-804` and `:851-853`, which assert *"no boost file was ever created …
`.boost_enabled = false` is inert"*) to match the shipped patch. A script author reading the
contract today is told the opposite of the truth.

---

## 5. Config policy: can their driver be `=y`?

**Yes.** Measured, not argued:

* Their Kconfig adds one dependency we did not have before —
  `depends on CPU_FREQ && CLK_INTEL_SOCFPGA32 && SRAM` (`drivers/cpufreq/Kconfig.arm` hunk) —
  and we already set `CONFIG_SRAM=y` (`board/mister/de10nano/linux.config:157`;
  resolved `.config:1325` after `olddefconfig`).
* Appending `CONFIG_ARM_SOCFPGA_CPUFREQ=y` to our config and running `olddefconfig` against a tree
  with their Kconfig **keeps it `=y`** (`<tmp>/.config:520 CONFIG_ARM_SOCFPGA_CPUFREQ=y`), and the
  objects build (§7).
* No `request_module`, no `MODULE_DEVICE_TABLE`, no modprobe assumption anywhere in either new
  file (`grep -c request_module` → 0). `module_init()` becomes a `device_initcall` when built in.
* **Init ordering is safe.** The clock provider is registered by `CLK_OF_DECLARE` during
  `of_clk_init()` (long before any initcall), so the cpufreq driver at `device_initcall` (level 6)
  finds `mpuclk` (`socfpga-cpufreq.c:65-76`). The OCRAM page is set up at `late_initcall`
  (`clk-mister-cpu.c:245`), i.e. **after** the built-in cpufreq driver registers — that is fine,
  because registration needs no OCRAM and the boot-time governor target (800 MHz, or 400→800 which
  is same-VCO) takes the divider-only path (`clk-mister-cpu.c:257-266`). Only a later, user-driven
  1000/1200 transition needs OCRAM, and by then `late_initcall` has run.
* **One piece must NOT be a module and already isn't**: `clk-mister-cpu.c` calls
  `__arm_ioremap_exec()` (`:231`), which has **no `EXPORT_SYMBOL`** in 6.18.49
  (`$S/linux/arch/arm/mm/ioremap.c:421` — definition only). It is built into `vmlinux` via
  `obj-$(CONFIG_CLK_INTEL_SOCFPGA32)` and `CLK_INTEL_SOCFPGA32` is a `bool`
  (`$S/linux/drivers/clk/socfpga/Kconfig:11-13`), so this is not a problem — but it does mean the
  `=m`/`=y` knob only ever covers the 111-line cpufreq shim.
* Every symbol the cpufreq shim uses is exported (`cpufreq_register_driver`,
  `cpufreq_generic_frequency_table_verify`, `cpufreq_generic_get`, `cpufreq_boost_set_sw`,
  `cpufreq_boost_enabled`, `of_clk_get_from_provider`, `of_machine_compatible_match`,
  `clk_{set,get,round}_rate` — all `EXPORT_SYMBOL[_GPL]`), so `=m` also links. Our `=y` rule costs
  nothing here.

**Conclusion:** if we adopt, take it `=y` and drop their `=m` defconfig commit (`d49875d491`) —
our standing rule (`fork-sync-2026-07.md` §2) applies unmodified and nothing in their code resists
it.

---

## 6. The two DTS side-changes

### (i) `compatible = "terasic,de10-nano", …` — **nothing to carry**

Vanilla 6.18.49 already has it:

```
$S/linux/arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts:14   	model = "Terasic DE10-Nano";
$S/linux/arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts:15   	compatible = "terasic,de10-nano", "altr,socfpga-cyclone5", "altr,socfpga";
```

Our `0004-dts-de10nano-MiSTer.patch:108` carries that exact line as **unchanged context**. Their
hunk exists only because the fork keeps its own copy of the file
(`socfpga_cyclone5_de10_nano.dts`, note the extra underscore) which lacked it. Their code matches
on this string in two places — `clk-mister-cpu.c:330`
`!of_machine_is_compatible("terasic,de10-nano")` and `socfpga-cpufreq.c:62`
`if (!of_machine_is_compatible("terasic,de10-nano")) return -ENODEV;` — so **our DTB already
satisfies their matcher**, and this hunk is a no-op for us. *(Aside: their driver therefore does
nothing on a stock image built from a fork DTB older than this commit.)*

### (ii) The OCRAM tail reservation — carry it, but for a corrected reason

Their hunk (against their DTS; ours would go in `0004`):

```
+&ocram {
+	#address-cells = <1>;
+	#size-cells = <1>;
+	ranges = <0 0xffff0000 0x10000>;
+
+	flags-sram@f000 {
+		reg = <0xf000 0x1000>;
+	};
+};
```

**What we carry today:** nothing. `grep -rln "ocram\|flags-sram" board/mister/de10nano/linux-patches/`
returns **no files**; `0004-dts-de10nano-MiSTer.patch` has no `&ocram` node
(its override list is `&gmac1 &gpio0 &i2c0 &i2c2 &mmc0 &spi0 &spi1 &uart0 &uart1 &usb1
&fpga_bridge0/1/2` — patch lines 205-330).

**Vanilla's node** (`$S/linux/arch/arm/boot/dts/intel/socfpga/socfpga.dtsi:785-788`):

```
		ocram: sram@ffff0000 {
			compatible = "mmio-sram";
			reg = <0xffff0000 0x10000>;
		};
```

**The mechanism is real.** In `$S/linux/drivers/misc/sram.c`, a child with only `reg` (no
`export`, `pool`, or `protect-exec`) is a *reserved block* that is simply skipped when the parent
pool is populated:

```
sram.c:199-221   	for_each_available_child_of_node(np, child) { ... list_add_tail(&block->list, &reserve_list);
sram.c:223-225   		block->export = of_property_read_bool(child, "export");
                 		block->pool   = of_property_read_bool(child, "pool");
                 		block->protect_exec = of_property_read_bool(child, "protect-exec");
sram.c:291-292   		if ((block->export || block->pool || block->protect_exec) && block->size) {   /* not us */
sram.c:301-303   		if (block->start == cur_start) { cur_start = block->start + block->size; continue; }
sram.c:314-321   		if (sram->pool) { ... gen_pool_add_virt(sram->pool, ... cur_size); }
```

**But their stated rationale does not verify against Main_MiSTer.** Their message says *"MiSTer
uses flags at the end of OCRAM across core loads and reboots."* At Main_MiSTer
`6cda9cc546c4b32e256a19931128b82586253812` the persistent-flags page is **DDR at physical
`0x1FFFF000`**, i.e. the last 4 KiB below the `mem=511M` boundary — not OCRAM:

```
$S/main/fpga_io.cpp:397     	void* buf = shmem_map(0x1FFFF000, 0x1000);      /* make_env(): core name */
$S/main/fpga_io.cpp:595-600 	void* buf = shmem_map(0x1FFFF000, 0x1000);      /* reboot(): */
                            	flg += 0xF08/4;  *flg = cold ? 0 : 0xBEEFB001;
$S/main/user_io.cpp:1336    	void* buf = shmem_map(0x1FFFF000, 0x1000);      /* sdram_sz(), offset 0xF00 */
$S/main/user_io.cpp:1370    	void* buf = shmem_map(0x1FFFF000, 0x1000);      /* altcfg(),  offset 0xF04 */
```

`SOCFPGA_OCRAM_ADDRESS 0xffff0000` is **defined and never used**
(`$S/main/fpga_base_addr_ac5.h:44`; it is the only occurrence of the symbol in the tree).

**So: carry it anyway, but as hygiene, not as a Main_MiSTer requirement.** It costs 10 DTS lines
and zero runtime; it makes the OCRAM allocation deterministic for *any* future in-kernel `sram`
consumer; and today nothing else allocates from that pool on our image
(`arch/arm/mach-socfpga/pm.c:50-57` is the only other gen_pool user and we build
`# CONFIG_SUSPEND is not set`, `linux.config:46`). If we adopt option B it becomes
**load-bearing**, because their allocator rejects any page outside `0xffff0000-0xffffefff`
(`clk-mister-cpu.c:225-230`) and disables PLL retuning if it lands wrong. Exact text to add to
`0004-dts-de10nano-MiSTer.patch` (appended after the `&fpga_bridge2` block, matching their node
verbatim so the two trees stay diffable):

```dts
&ocram {
	#address-cells = <1>;
	#size-cells = <1>;
	ranges = <0 0xffff0000 0x10000>;

	/*
	 * Reserve the last 4 KiB of OCRAM from the mmio-sram gen_pool.  A child
	 * with only "reg" (no export/pool/protect-exec) is excluded from the
	 * parent pool by drivers/misc/sram.c without creating a subpool or
	 * clearing the memory.  Upstream MiSTer added this for persistent flags;
	 * at Main_MiSTer 6cda9cc54 those flags actually live in DDR at
	 * 0x1FFFF000 (fpga_io.cpp:397/595, user_io.cpp:1336/1370), so for us this
	 * is allocation hygiene, and a hard requirement only if we ever adopt the
	 * OCRAM-resident PLL retune (fork 59bcae8eb).
	 */
	flags-sram@f000 {
		reg = <0xf000 0x1000>;
	};
};
```

---

## 7. Build check — done, and it passes

All work in a private tmp tree; no shared tree was modified and no `make` ran inside `$S/linux`
(everything used `O=<tmp>`), per the worker preamble.

**(a) Patch application against 6.18.49.** Copied the six existing files their diff touches out of
`$S/linux` and ran the code half of the diff (`git show 59bcae8eb -- drivers/clk/socfpga
drivers/cpufreq`):

```
$ patch -p1 -F0 --dry-run < code.diff
checking file drivers/clk/socfpga/Makefile
checking file drivers/clk/socfpga/clk-mister-cpu.c
checking file drivers/clk/socfpga/clk-mister-ocram.S
checking file drivers/clk/socfpga/clk-mister-ocram.h
checking file drivers/clk/socfpga/clk-periph.c
checking file drivers/clk/socfpga/clk-pll.c
checking file drivers/clk/socfpga/clk.h
checking file drivers/cpufreq/Kconfig.arm
checking file drivers/cpufreq/Makefile
checking file drivers/cpufreq/socfpga-cpufreq.c
```

**Zero fuzz, zero rejects, zero offsets** at `-F0`. (The two DTS hunks and the `MiSTer_defconfig`
hunk are fork-only paths and were excluded — see §6.)

**(b) Compile.** Extracted a private copy of the 6.18.49 source (`git archive HEAD | tar -x`),
applied the same diff in it, copied `board/mister/de10nano/linux.config` to a separate `O=` dir,
appended `CONFIG_ARM_SOCFPGA_CPUFREQ=y`, then:

```
make -C <src> O=<obj> ARCH=arm LLVM=1 olddefconfig     -> rc=0, CONFIG_ARM_SOCFPGA_CPUFREQ=y kept
make -C <src> O=<obj> ARCH=arm LLVM=1 -j4 prepare      -> rc=0
make -C <src> O=<obj> ARCH=arm LLVM=1 W=1 drivers/clk/socfpga/ drivers/cpufreq/
  CC      drivers/clk/socfpga/clk-pll.o
  CC      drivers/clk/socfpga/clk-periph.o
  CC      drivers/clk/socfpga/clk-mister-cpu.o
  AS      drivers/clk/socfpga/clk-mister-ocram.o
  AR      drivers/clk/socfpga/built-in.a
  CC      drivers/cpufreq/socfpga-cpufreq.o
  AR      drivers/cpufreq/built-in.a
```

**Result: builds clean, `W=1`, zero warnings**, ARM/clang, against 6.18.49 + our MiSTer config,
built-in (`=y`). The modified `clk-pll.o`/`clk-periph.o` also rebuild clean.

A separate out-of-tree `M=` build of the same three objects also compiled clean (`CC`/`AS`/`LD` all
succeeded, no diagnostics); its `modpost` stage failed only because an `M=` build has no
`vmlinux Module.symvers` to resolve against — that is an artefact of the harness, not of their
code, and it incidentally re-confirms that `clk-mister-cpu.c` cannot be a module
(`__arm_ioremap_exec` unresolved; §5).

**Not built:** a full `zImage`/`dtbs`, and nothing was run on hardware.

---

## 8. Recommendation

| | **A — keep `0003`** | **B — adopt theirs `=y`, retire `0003`** | **C — theirs, but boost on by default** |
|---|---|---|---|
| **Work** | ~0. Record Q4 as a deliberate divergence. Two independent chores: fix `abi-contract.md:1670` (§4) and add the `&ocram` node to `0004` (§6). | Replace `0003` with a ~700-line, 4-file patch touching **shared** `drivers/clk/socfpga` code (`clk-periph.c`, `clk-pll.c`, `clk.h`, `Makefile`) + `0004` DTS hunk + config move. Rewrite the `0003` header and the ABI docs. Retire `0003`. | B's work, **plus** a deliberate deviation from upstream (`.boost_enabled = true`) that must be re-explained on every future rebase. |
| **Risk** | Ships a driver that does 2 of 3 suspected hang causes and whose four `wait_for_fsm()` guards are no-ops; TWD clockevent rate goes stale on every transition (§1). No 1000 MHz evidence at all; one 1200 MHz success and one unexplained field hard-hang in the same era. | Engineering is clearly better (OCRAM + `stop_machine` + `OUTRESETALL` + 12.5 % VCO steps + bounded polls + rollback + CCF/TWD notification). But: 700 lines we did not write, R1–R9 in §2 — including a **deliberate infinite-loop hang path** with no watchdog behind it (R5), a **latched permanent failure** (R6), a possible `-EBUSY`-forever if SD is main-PLL-sourced (R9), and an **unexplained OSD artefact** (R3). The clk-side hijack is not opt-in (R7). | All of B's risk, **and it re-introduces the exact defect we fixed in PR #24**: with `boost_enabled = true` at registration, `cpufreq_online()` calls `policy_set_boost(policy, cpufreq_boost_enabled())` on every new policy (`cpufreq.c:1632-1634`), which recomputes `cpuinfo.max_freq` to 1 200 000 and pushes it into `policy->max` (`cpufreq_boost_set_sw`, `cpufreq.c:2789-2797`; `freq_table.c:41-59`) — so with the `performance` default governor the board **auto-overclocks to 1.2 GHz on boot** again. |
| **What changes for users / scripts** | **Nothing.** | **Nothing** — the sysfs contract is identical (§4). Only `scaling_driver` stays `"socfpga"` and `dmesg` gains `MiSTer CPU:` lines. | The `scaling_max_freq`-only script "works" again — by shipping an unrequested overclock. |
| **Hardware test required before shipping** | Only if we want to *close* the open question (recommended, not blocking). | **Mandatory, all four points.** | Same, plus a thermal soak. |

**Hardware test script (identical for A-validation and B-acceptance).** On a DE10-Nano with serial
console attached and `dmesg -w` running in a second shell:

```sh
C=/sys/devices/system/cpu/cpu0/cpufreq
cat $C/scaling_driver $C/scaling_governor            # expect: socfpga, performance
cat $C/cpuinfo_min_freq $C/cpuinfo_max_freq          # expect: 400000  800000   (boost off)
cat $C/scaling_available_frequencies                 # expect: 800000 400000
cat $C/scaling_boost_frequencies                     # expect: 1200000 1000000
cat /sys/devices/system/cpu/cpufreq/boost            # expect: 0        <-- if "No such file", §4 is wrong
echo 1200000 > $C/scaling_max_freq; cat $C/scaling_max_freq   # expect: 800000 (clamped) — the §4 claim
cat /sys/devices/system/clockevents/clockevent0/current_device # expect: twd  (see §1)

echo userspace > $C/scaling_governor                 # take the governor out of the loop
for f in 400000 800000 400000 800000; do
  echo $f > $C/scaling_setspeed; sleep 2
  echo -n "set $f -> "; cat $C/scaling_cur_freq $C/cpuinfo_cur_freq
  date; grep -c . /proc/interrupts >/dev/null        # timers alive?
done

echo 1 > /sys/devices/system/cpu/cpufreq/boost       # opt in
cat $C/cpuinfo_max_freq                              # expect: 1200000
for f in 1000000 800000 1000000 1200000 800000 1200000 400000 1200000; do
  echo $f > $C/scaling_setspeed; sleep 3
  echo -n "set $f -> "; cat $C/cpuinfo_cur_freq
  ( time sleep 1 ) 2>&1 | grep real                  # timer sanity: must print ~1.0s at EVERY step
  dd if=/dev/urandom bs=1M count=64 2>/dev/null | sha256sum   # CPU+DDR under load
done
echo 0 > /sys/devices/system/cpu/cpufreq/boost; cat $C/scaling_max_freq  # expect: 800000
```

**Watch for:** (1) the board dying with no serial output at the moment of a transition — that is
the hang question, and it is the only thing that separates A from B; (2) `( time sleep 1 )`
reporting anything other than ~1.0 s — that is the stale-TWD defect of §1 and it should appear
under `0003` at 400 MHz (≈2 s) and not under theirs; (3) any `MiSTer CPU:` `pr_err` (option B);
(4) the OSD moving on its own while the loop runs (their R3); (5) a 30-minute soak at 1200 with
`sha256sum` in a loop before believing anything. Repeat the whole thing after a cold boot and
after a core load.

### Recommendation: **A**, with the two independent amendments, and **B tracked as bench-gated**

**The single strongest reason:** the only *user-visible* thing option B or C could buy us — the
boost/`scaling_max_freq` semantics — **is already identical between the two drivers** (§4). What
remains for B is engineering quality (OCRAM residency, `OUTRESETALL`, VCO ramping, TWD
notification), all of it real, none of it validated on our image, in exchange for retiring the
only cpufreq code that has **ever been observed running on a MiSTer at 1.2 GHz** — including on
our own board on 6.18 (`docs/testlogs/p1-first-boot.md:118`). Swapping proven-in-the-field code
for better-designed-but-unproven code, with no bench, on the one patch that can brick a board
mid-transition, is the wrong trade *today*; it becomes the right trade the moment someone has the
board on the desk.

**What would flip this to B:**

1. **A reproducible hang or corruption on `0003` at 1000 or 1200 MHz on 6.18 hardware** (the test
   above, step "boost on"). We have zero 1000 MHz data points; that is the single largest hole.
2. **Evidence that the July field hard-hang was the *transition*, not sustained 1.2 GHz** — e.g.
   a serial capture showing the death at the moment of the frequency write. `docs/debug-tooling.md:12-22`
   attributes it to the unrequested overclock but does not isolate the two.
3. **A measured timer defect** — `( time sleep 1 )` reporting ~2 s at 400 MHz under `0003` — if we
   decide the 400 MHz row must work correctly.
4. **A decision to converge our `drivers/clk` + `drivers/cpufreq` export with the fork's tree**
   (e.g. because we intend to send patches upstream to the fork), which makes divergence itself
   the cost.

**What would flip it to C: nothing.** C's premise is refuted (§4) and its implementation
re-creates the auto-overclock bug of PR #24. It should be struck from the option list.

**Also do, regardless of the decision:**

* Fix `docs/abi-contract.md:1670` and `docs/patch-provenance.md:798-804` / `:851-853` — they
  currently tell script authors the opposite of what the shipped kernel does (§4).
* Add the `&ocram` `flags-sram@f000` reservation to `0004` (§6), with the corrected rationale.
* Do **not** carry the `terasic,de10-nano` compatible hunk — vanilla 6.18.49 already has it (§6i).
* If B is ever taken: take it `=y` (§5) and drop their `d49875d491` `=m` defconfig commit.

