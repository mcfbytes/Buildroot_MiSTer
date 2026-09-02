# DE25-Nano kernel patch portability — all 40 patches, two verdicts each

**Status:** **desk audit, 2026-08-21. No hardware. Nothing built, nothing rebased, no file
moved.** This is task **D0.3** of [`de25-nano-tasks.md`](de25-nano-tasks.md) §D0.3, produced as
a **draft**: the series-layout proposal in §3 is a proposal, and the *portable* verdicts that
touch `arch/`, a DTS, or a Kconfig (§8) are queued for an independent spot-verification pass
that has **not** yet run. Every load-bearing claim is tagged **[V]** (a file was opened and the
relevant lines read — the patch, the provenance record, or `output/build/linux-6.18.44`) or
**[U]** (not settled by reading, with the thing that would settle it named). A **[V]** here is a
*source-reading* claim only: **nothing in this document has been compiled for aarch64 and
nothing has been run on Agilex 5 silicon.**

**Cross-refs:** [`de25-nano-plan.md`](de25-nano-plan.md) §5 (the ~28/~8 estimate this
reconciles against) and §6 DP-9/DP-10 · [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md)
· [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §7–§8 (D0.2 — authoritative on
reconfiguration and on what DP-9 does and does not settle) ·
[`de25-boot-chain.md`](de25-boot-chain.md) (D0.1) · [`patch-provenance.md`](patch-provenance.md)
· [`kernel-recon/`](kernel-recon/) · [`abi-contract.md`](abi-contract.md) §4.3 (the framebuffer
and vsync userspace contract) · [`rt-beta-kernel.md`](rt-beta-kernel.md) §9 (the beta-local
observability patches).

**Sources read this pass.** All 40 unique patch files under
`board/mister/de10nano/linux-patches/` (36) and `board/mister/de10nano/linux-patches-beta/`
(40 + a `series` file); `docs/patch-provenance.md`; `docs/kernel-recon/`; the local kernel tree
`output/build/linux-6.18.44` (cited as `linux:path:line`), including
`arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi`, `socfpga_agilex5_socdk.dts` and
`socfpga_agilex.dtsi` for the Agilex-side comparison.

> **Four facts shaped this document.**
>
> 1. **The owner's prior survived, cleanly and on evidence.** All **25** patches under
>    `drivers/hid`, `drivers/input` and `drivers/hid/usbhid` are portable as-is to arm64 and
>    belong in a **shared** series. Every one was opened; the specific arch-coupling classes
>    (32-bit time/ioctl, unaligned access, endianness, DMA/coherency, `__u32`-vs-pointer struct
>    layout, absent HW blocks) were looked for by name and **none was found** (§5). **[V]**
> 2. **But the prior's *complement* is understated, and that is where the money is.** The prior
>    names fb / vsync / f2h_irq as the worry set. The single hardest arm64 break found is in
>    **none of them**: `0002` (MiSTer audio SPI) **does not compile on aarch64** — it passes
>    `unsigned int *` where `dma_alloc_coherent()` wants `dma_addr_t *`, and `dma_addr_t` is
>    `u64` on every 64-bit arch **[V `linux:kernel/dma/Kconfig:35`,
>    `linux:include/linux/types.h:157-161`]**. Anyone porting on the prior alone hits it at the
>    first aarch64 compile.
> 3. **One break compiles clean and fails silently — the dangerous class.** `0001`'s
>    `memremap(…, MEMREMAP_WT)` yields **Normal non-cacheable** on arm
>    (`linux:arch/arm/include/asm/io.h:390`, `ioremap_wt == ioremap_wc`) and **Device-nGnRE** on
>    arm64 (`linux:include/asm-generic/io.h:1166-1167` → `linux:arch/arm64/include/asm/io.h:284`)
>    **[V]**. The patch's own header justifies its direct-dereference drawing ops with *"memremap
>    (MEMREMAP_WT) returns a normal-memory mapping"* — **true on arm, false on arm64**. Generalise
>    the lesson: *any patch whose **correctness argument** cites an arm32 memory-attribute
>    encoding needs the argument re-derived on arm64, even when the code is unchanged.*
> 4. **No patch is dropped and none is superseded.** Zero of 40. The 0037/BTN_Z trap class —
>    dropping something that looks cosmetic but shifts an index userspace depends on — is
>    therefore **not engaged anywhere in this audit**, and no drop-justifying provenance cite is
>    owed. The one verdict that *resembles* a drop (0043/0044/0045 not going to DE25) is DP-9's
>    already-taken decision, recorded here with the capability each provides so the
>    Agilex-native replacement can be **checked** rather than assumed equivalent.

---

## 1. How to read this

Every patch gets **two** verdicts, and they answer different questions.

**Verdict 1 — portability.** *Would this patch build and behave correctly on arm64/Agilex 5?*
One of `portable-as-is` (applies and works unchanged), `portable-with-rework` (the mechanism is
sound; named, bounded changes are required first), `board-specific` (encodes Cyclone V
addresses, interrupt numbers, register maps or gateware contracts — a reimplementation, not a
rebase), or `superseded-upstream` (the change already landed in 6.18; **no patch earned this
verdict**).

**Verdict 2 — target series.** *Which patch directory should it live in once the tree builds two
boards?* One of `shared` (applied to both), `de10-only`, `de25-only` (none yet), or `drop`
(none).

**The second column is the one that serves the owner's goal.** Portability alone would let you
put all 33 portable patches in one pile and call it reuse; it would also let you conclude that
`0043` "does not port" and quietly delete a patch that ships, today, on the DE10 RT beta. The
two verdicts are independent in both directions:

- A patch can be **portable and still DE10-only** — `0045` (UIO write-combining) is generic,
  arch-independent kernel code that would build and work on arm64, but per DP-9 it has nothing
  to attach to on the DE25 until a GHRD exists, so it stays in the DE10 beta series.
- A patch can be **board-flavoured in its rationale and still shared** — `0030` (quiet the
  DesignWare I2C timeout) exists because the DE10's optional RTC add-on is usually absent, but
  the file it edits is the generic Synopsys driver that Agilex 5's HPS I2C also uses, so it
  belongs in the shared series.

**`de10-only` never means "delete".** Where this document says a patch is not ported to the
DE25, the patch stays live and unmodified where it is. Two triage verdicts of `drop` (`0043`,
`0044`) were **overturned to `de10-only`** for exactly this reason during the deep-dive pass.

**Depth is uneven, and the document says so.** Eight patches got a full deep dive (`0001`,
`0002`, `0003`, `0004`, `0043`, `0044`, `0045`, `0046`) plus a cross-cutting mechanism pass; the
other 32 got a single-pass triage read. **Where a deep dive contradicted triage, the deep dive
wins and the table flags it (⚠).** That flag is the signal for how much to trust the
un-deep-dived rows: on the four patches where a second, more careful pass was applied to
*non-obvious* code, it found something triage had missed **three times out of four** — a
build-breaking `NO_IRQ` (`0001`), a build-breaking `dma_addr_t` (`0002`), and an arm64-absent
`CONFIG_CMDLINE_EXTEND` (`0043`). The rows that are pure device-ID tables, evdev keymaps and
log-severity changes are cheap to be right about; the rows involving memory attributes, DMA and
DT bindings are not.

**Provenance cites.** House rule: a `drop` or `superseded` verdict *must* cite the provenance
record. No verdict here is either, so a cite is carried only where a leg actually took one; `—`
means no per-patch provenance row was needed for this verdict, not that none exists. Four
patches have a **[V] negative** provenance finding worth recording: `0043`, `0044`, `0045` and
`0046` have **no entry at all** in `patch-provenance.md` (grep for `ramoops`, `doorbell`,
`writecombine`, `uio` returns nothing relevant), yet each patch header cites *"Disposition
'carry' (docs/patch-provenance.md 3.1)"* — and §3.1 (`patch-provenance.md:330-346`) is the
Class A table covering `0001`–`0004` only. Those headers cite a row that was never written.
That is a documentation defect to close, not a disposition problem: all four are locally
authored with no fork ancestry, so there is no upstream disposition to reconcile.

---

## 2. The table — all 40

Risk is a reading-effort signal, not a verdict: 🟢 green = mechanism obviously arch-neutral;
🟡 amber = a named, bounded change or decision is required; 🔴 red = board-specific by
construction. ⚠ marks a row where the deep dive overturned or materially corrected triage.

| # | Patch | Subsystem | Risk | Portability | Series | Rationale (one line) | Provenance |
|---|---|---|---|---|---|---|---|
| 1 | `0001-fbdev-add-MiSTer_fb-driver` ⚠ | fbdev | 🔴 | board-specific | de10-only | Driver is inseparable from a DE10 fabric frame-reader at `0x22000000` + GIC SPI 40; **and** it uses arm-only `NO_IRQ` (won't compile on arm64) and relies on `MEMREMAP_WT` being Normal memory (it is Device on arm64) — both missed by triage. | `patch-provenance.md:334`, `:558-640`, `:1173`, `:1507` |
| 2 | `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model` ⚠ | sound | 🟡 | portable-with-rework | shared (gated) | Chrdev+SPI driver is subsystem-generic, but **breaks the aarch64 build**: `&MrBufferInfo.addr` (`unsigned int`) passed as `dma_addr_t *`. Fix must not widen the 16-byte FPGA wire descriptor. `dummy.c` half is arch-neutral and mandatory on DE10. | `patch-provenance.md:335`, `:634-760`, `:280-306` (N4), `:1174` |
| 3 | `0003-cpufreq-cyclone5-de10nano-overclock` | cpufreq | 🔴 | board-specific | de10-only | Pokes Cyclone V gen5 clock-manager MMIO at fixed offsets via `altr,clk-mgr`; Agilex 5 has a different clkmgr (`intel,agilex5-clkmgr`) **with no in-tree driver at all** in 6.18.44 — nothing to port *to*. | `patch-provenance.md:336`, `:757-880`, `:1175`, `:1511` (B6) |
| 4 | `0004-dts-de10nano-MiSTer` | dts | 🔴 | board-specific | de10-only | The DE10 board DTS itself: gen5 FPGA bridges, KSZ9031 PCB skews, `MiSTer_fb@22000000`, DE10 header pinout. DE25 needs a from-scratch arm64 DTS. | `patch-provenance.md:337`, `:930-975`, `:1176` |
| 5 | `0010-hid-guncon2` | hid | 🟢 | portable-as-is | shared | Raw `usb_driver` for a Namco lightgun using generic USB/input APIs; fixed 6-byte report is a peripheral protocol detail, not an arch assumption. | — |
| 6 | `0011-hid-guncon3` | hid | 🟢 | portable-as-is | shared | Standalone USB interrupt-URB HID driver; `usb_maxpacket()`/`strscpy()` already match 6.18 API. USB-generic, works over any host controller incl. Agilex 5's dwc2. | — |
| 7 | `0012-hid-fanatec` | hid | 🟢 | portable-as-is | shared | ~1745 lines of USB HID force-feedback (hrtimer, spinlocks, jiffies, sysfs); no MMIO, DMA, endianness or pointer-size ABI exposure anywhere. | — |
| 8 | `0013-hid-flydigi-vader` | hid | 🟢 | portable-as-is | shared | New Bluetooth HID remap driver using only `hid_parse`/`hid_hw_start`/`input_report_key`; `BTN_GRIP*` are arch-independent UAPI constants. | — |
| 9 | `0014-hid-gamecube-adapter` | hid | 🟢 | portable-as-is | shared | Generic USB-HID driver over `u8` buffers with RCU + `work_struct` hot-plug; uses modern `hid_is_usb()`. Not upstream, so not superseded. | — |
| 10 | `0015-hid-nintendo-nso-famicom` | hid | 🟢 | portable-as-is | shared | Two enum values, two type helpers, two dispatch arms, one button table in `hid-nintendo.c`. Beta copy differs by **context re-anchoring only**; functional hunks byte-identical. | — |
| 11 | `0016-hid-microsoft-elite2-paddles` | hid | 🟢 | portable-as-is | shared | HID usage-mapping quirk decoding an 8-bit paddle bitmask; no arch, pointer-size or DMA assumption. | — |
| 12 | `0017-xpad-mister-deltas` | joystick | 🟢 | portable-as-is | shared | `cpoll` param, GIP exclusion, Qanba/Flydigi table entries; endianness handled correctly via `le16_to_cpup()` for the raw-mode axes. | — |
| 13 | `0018-hid-controllable-quirk` | hid | 🟢 | portable-as-is | shared | Two device-ID table rows routing a BT VID:PID through the existing PANTHERLORD driver. No code at all beyond table data. | — |
| 14 | `0019-hidpp-k400-fn-inversion` | hid | 🟢 | portable-as-is | shared | HID++ feature-protocol logic plus one ID-table row; all payloads are single bytes. | — |
| 15 | `0020-mmc-no-led-on-send-status` | mmc | 🟢 | portable-as-is | shared | One conditional in core `mmc_start_request()`, gating the LED trigger on `MMC_SEND_STATUS`. Core-layer, host-driver-agnostic; the DE10 `hps_led0` framing is a consequence, not a dependency. | — |
| 16 | `0022-hid-playstation-ds4-mac-fix` | hid | 🟢 | portable-as-is | shared | Turns a hard probe failure into warn-and-continue in `dualshock4_get_mac_address()`. Pure error-handling policy. | — |
| 17 | `0023-hid-wiimote-fixes` | hid | 🟢 | portable-as-is | shared | Sets `input_dev->uniq` across ~11 extension probes, remaps a keymap to `BTN_*`, corrects two ABS ranges. Bluetooth HID input mapping only. | — |
| 18 | `0024-hid-input-keyrah-europe1` | hid | 🟢 | portable-as-is | shared | A **single byte** changed in the `hid_keyboard[256]` scancode table. Architecture-agnostic by construction. | — |
| 19 | `0025-usbhid-jspoll-gamepad` | hid | 🟢 | portable-as-is | shared | One `case HID_GD_GAMEPAD:` fallthrough in `usbhid_start()`'s polling-interval switch. | — |
| 20 | `0026-input-mousedev-eviocgrab` | input | 🟢 | portable-as-is | shared | New `->ignore_grab` flag + `EVIOCGRAB` on mousedev. **`EVIOCGRAB`'s argument is a bool, not a pointer**, so there is no `compat_ptr()`/32-vs-64 ioctl hazard; the patch header states it was written with other arches in mind. | — |
| 21 | `0027-mt76x2u-release-xbox-adapter-ids` | net (mt76) | 🟢 | portable-as-is | shared | Deletes two `USB_DEVICE()` rows so `xone` can claim the device. Driver-match priority policy; a USB ID table has no CPU architecture. | — |
| 22 | `0028-dwc2-fix-unaligned-in-split` | usb | 🟢 | portable-as-is | shared | Moves an `align_buf` copy-back into the shared split-completion path — a **real general dwc2 bug**, not a MiSTer quirk. Agilex 5 declares `snps,dwc2` too, so it applies there identically. | — |
| 23 | `0029-leds-gpio-brightness-hw-changed` | leds | 🟢 | portable-as-is | shared | Generic `leds-gpio` + LED-class change. Shared as *code*; it only *does* anything on a board whose DTS wires an activity LED (DE10: `hps_led0` from `0004`). | `patch-provenance.md:429`, `:1198` |
| 24 | `0030-i2c-designware-quiet-timeout` | i2c | 🟢 | portable-as-is | shared | One `dev_err`→`dev_dbg` in the generic Synopsys DW I2C master, which Agilex 5's HPS I2C also uses. Beta copy differs by re-anchoring only; the changed line is byte-identical. | — |
| 25 | `0031-exfat-samsung-symlinks` | exfat | 🟢 | portable-as-is | shared | Filesystem-format code; the attribute-bit overload is a 16-bit DOS value handled by existing helpers. `inode_nohighmem()` is a generic VFS call, a no-op without HIGHMEM (normal on arm64). | — |
| 26 | `0032-hid-nintendo-joycon-combo-led` | hid | 🟢 | portable-as-is | shared | Registers a virtual `led_classdev` used as a userspace pairing mailbox; downgrades two warns to debug. | — |
| 27 | `0033-hid-playstation-dualsense-player-id-led` | hid | 🟢 | portable-as-is | shared | Replaces five auto-lit player LEDs with one writable `player_id_led` that Main_MiSTer drives. LED-class/HID only. | — |
| 28 | `0034-hid-nintendo-nes-famicom-stock-ab-mapping` | hid | 🟢 | portable-as-is | shared | Swaps two rows in two static button-mapping tables to restore stock's A/B order. Same userspace consumes it on both boards. | — |
| 29 | `0035-hid-nintendo-home-led-nonfatal` | hid | 🟢 | portable-as-is | shared | Makes home-LED `devm_led_classdev_register()` failure non-fatal at probe. Only **partially** fixed upstream — the registration path is still fatal in 6.18, so **carry, not superseded**. | `patch-provenance.md:363` |
| 30 | `0036-btusb-csr-clone-lmp-subver-2512` | bluetooth | 🟢 | portable-as-is | shared | One `else if` comparing `le16_to_cpu(rp->lmp_subver)` against a clone signature. USB-attached, host-controller-agnostic. | — |
| 31 | `0037-hid-playstation-dualsense-mute-btn-z` | hid | 🟢 | portable-as-is | shared | **Functional, not cosmetic.** `BTN_Z` (0x135) sits between `BTN_WEST` and `BTN_TL` and shifts every higher `EV_KEY` ordinal, so the shipped `gamecontrollerdb` `platform:MiSTer` rows depend on it. The RT beta drops it; that is a **known divergence, not a precedent**. Beta copy differs by hunk offsets only. | `patch-provenance.md:370`, `:1222`, `:1537` |
| 32 | `0038-hid-nintendo-nso-genesis-bt-pid` | hid | 🟢 | portable-as-is | shared | 20-line `hdev->product` rewrite keyed off a controller-reported type byte, before `devm_input_allocate_device()`. | — |
| 33 | `0039-hid-nintendo-nso-n64-genesis-stock-button-mapping` | hid | 🟢 | portable-as-is | shared | Reassigns evdev codes in two static mapping tables to stock's order. Not bench-verified against real pads — a testing gap, **not** a portability risk. | — |
| 34 | `0040-hid-nintendo-imu-name-suffix` | hid | 🟢 | portable-as-is | shared | One format-string token (`"%s (IMU)"` → `"%s IMU"`) restoring the substring Main_MiSTer filters on. | — |
| 35 | `0041-hid-nintendo-stock-led-classdev-names` | hid | 🟢 | portable-as-is | shared | `devm_kasprintf()` format change restoring stock's flat LED names so Main_MiSTer's hardcoded `fopen()` paths resolve. | — |
| 36 | `0042-hid-playstation-stock-lightbar-led-names` | hid | 🟢 | portable-as-is | shared | Adds stock-compatible R/G/B LED classdevs alongside mainline's multicolor device, using an explicit back-pointer+index instead of `container_of()`. LED-class/HID only. | — |
| 37 | `0043-dts-uio-doorbells` ⚠ | dts (uio) | 🔴 | board-specific | de10-only *(beta)* | Eight interrupt-only `generic-uio` nodes on Cyclone V GIC SPI 48–55 (`f2h_irq8..15`). Triage said `drop`; **overturned — it ships on DE10.** Deep dive added: **`CONFIG_CMDLINE_EXTEND` does not exist on arm64**, so the DE10 binding recipe has no arm64 counterpart. Not ported to DE25 per DP-9. | **none exists** (see §1); `de25-nano-plan.md:211-218`; `de25-fpga-reconfig.md` §8 |
| 38 | `0044-dts-uio-fpga-regions` ⚠ | dts (uio) | 🔴 | board-specific | de10-only *(beta)* | Two reg-bearing UIO nodes: the 2 MiB lwhps2fpga window at `0xff200000` (never write-combined) and the 512 MiB f2sdram DDR aperture at `0x20000000` (WC-capable). Triage said `drop`; **overturned.** Depends on the `mem=511M` bootarg. Not ported per DP-9. | **none exists**; `de25-nano-plan.md:213-219` |
| 39 | `0045-uio-writecombine` | uio | 🟡 | **portable-as-is** | de10-only *(beta)* | Generic `UIO_MEM_PHYS_WC` memtype — **arch-independent, and the Normal-NC vs Device-nGnRnE distinction it exploits is identical on arm64** (`linux:arch/arm64/include/asm/pgtable.h:789-792`). Not ported *because it has nothing to attach to until a GHRD exists*, not because it fails. **D0.2 §8 states plainly that DP-9 does not settle this patch's question.** Splitting the generic half to shared/upstream is an open owner decision (§7). | **none exists**; `de25-fpga-reconfig.md` §8 |
| 40 | `0046-dts-ramoops` | dts | 🔴 | board-specific | de10-only *(beta)* | 1 MiB `ramoops` carve-out at `0x1FE00000` — every number derives from `mem=511M`, MiSTer's fixed mailbox at `0x1FFFF000`, and ARM32's lowmem/HIGHMEM model. The **capability** (crash forensics for a silent hang) is board-agnostic and arguably worth more on DE25; the **address** is not portable. The four `CONFIG_PSTORE_*` symbols are a genuine shared-fragment candidate. | **none exists**; `rt-beta-kernel.md` §9, §9.1, `:74`, `:730-732`, `:228` |

**Totals.** 33 `portable-as-is` · 1 `portable-with-rework` · 6 `board-specific` · **0
`superseded`** · **0 `drop`**. Series: **33 shared** · **7 de10-only** · 0 de25-only.

**Series membership and the four divergent copies.** 36 patches are in both directories; 4
(`0043`–`0046`) are beta-only. Of the 36, **32 are byte-identical between the two series** —
including `0002`, `0003` and `0004`, verified by `cmp`/`diff` **[V]**. Four differ, and **none
of the differences changes a verdict** **[V]**:

| Patch | What differs between the shipped and beta copies | Verdict impact |
|---|---|---|
| `0001` | `#include <linux/fbcon.h>` → `#include "core/fbcon.h"` (7.x moved `fbcon_update_vcs()`'s declaration into the fbdev core), plus a 7-line note asking that the two be kept in lockstep. | None. Kernel-version churn, not arch coupling. **Both copies carry the identical `NO_IRQ` and `MEMREMAP_WT` problems.** |
| `0015` | Context re-anchoring around `JOYCON_CTLR_TYPE_LIC_PRO = 0x06`, which the 7.x tree already carries. Functional hunks byte-identical. | None. |
| `0030` | Context re-anchoring (`i2c_dw_init_master()` → 7.x's renamed `i2c_dw_init()`) and a shifted line number. The changed line is byte-identical. | None. |
| `0037` | Hunk-header offsets only, re-anchored around 7.x's added DualSense-Edge paddle block. Added lines byte-identical. | None — but note the beta *series file* **drops `0037` entirely**, which is the known divergence recorded in row 31, not a licence to do the same on DE25. |

---

## 3. Series layout — the proposal

**This is a proposal. No files were moved and no `series` file was written.** It is the concrete
answer to the owner's question: *how do we get one tree building two boards while reusing as
much as possible?*

### 3.1 The shape

```
board/mister/
  common/
    linux-patches/            <- SHARED: 33 patches, applied to BOTH boards
  de10nano/
    linux-patches/            <- DE10-only: 0001 0002-audio-node? 0003 0004     (4)
    linux-patches-beta/       <- DE10 RT beta delta: 0043 0044 0045 0046        (4)
    linux.config / linux-rt.fragment
  de25nano/
    linux-patches/            <- DE25-only: empty today                          (0)
    linux.config
```

**The shared series holds 33 of 40 patches — 82.5%.** That is the reuse figure, and it is real:
every one of those 33 was opened and judged arch-neutral on its own text, not assumed neutral
because it lives under `drivers/hid`.

**The DE10-only series holds 7.** Four in the stock series (`0001`, `0003`, `0004`, and — see
below — the board half of `0002`), four beta-local (`0043`–`0046`). Every one encodes a Cyclone
V physical address, GIC SPI number, clock-manager register offset, or gateware contract.

**The DE25-only series is empty today, by design.** ADR 0027 scopes the initial DE25 image to a
bare developer OS with **no MiSTer binaries**. The DE25 will eventually need its own board DTS
(the analogue of `0004`), and probably its own `ramoops` node (the analogue of `0046`, whose
capability is *more* valuable on a board whose reconfiguration path has a reported
hang-on-second-load); neither is written and neither should be written speculatively.

### 3.2 Two decisions the layout forces, neither of which this document takes

**(a) `0002` is one file doing two jobs.** Its `MiSTer-audio-spi.c` half is bound to a
`MiSTer,spi-audio` DT node and a MiSTer gateware wire protocol → DE10-only in substance. Its
`sound/drivers/dummy.c` half is arch-neutral ALSA core → a shared candidate. But the patch
header warns in as many words that *the two halves ship together*: `asound.conf` pins format and
rate but **not** channel count, which is negotiated against `hw:0`, so pinning snd-dummy to 2ch
is the only thing stopping a mono client teeing mono frames into a driver that reads them as
4-byte stereo. Omit the `dummy.c` hunks on DE10 and you get a perfectly healthy `/dev/MrAudio`
and **wrong or silent audio** (`patch-provenance.md:280-306`, N4) **[V]**.

Two viable options. **Option 1 (recommended, lowest risk):** keep `0002` whole in the *shared*
series and let the DE25 defconfig simply not set `CONFIG_SND_MISTER_AUDIO` /
`CONFIG_SND_DUMMY`. The driver half is inert without a DT node; the `dummy.c` half is **not**
inert — it changes snd-dummy's global defaults on any board that builds `CONFIG_SND_DUMMY` — so
the defconfig gate is doing real work, not decoration. **Option 2:** split into a shared
`dummy.c` patch and a DE10-only `MiSTer-audio-spi` patch. Safe for DE10 only if both stay
applied there. **Owner call required** — and it should be taken with the knowledge that `0002`
does not currently compile for aarch64 at all (§4.4), so under Option 1 the aarch64 build must
either carry the type fix or not build the file.

**(b) `0045` may be worth splitting for upstream, not just for reuse.** Its `uio.c`,
`uio_driver.h` and `uio-howto.rst` hunks are generic, arch-independent kernel code written — by
its own header — to upstreamable standards; only the `mister,map-writecombine` property parse in
`uio_pdrv_genirq.c` is board-flavoured, and even that is only a name. `de25-fpga-reconfig.md` §8
states explicitly that **DP-9 does not settle 0045's question and should not be cited as having
done so**. Splitting the generic half to the shared series (or upstream) costs nothing on DE10
and would leave the DE25 with the memory-attribute escape hatch already in place if it ever
needs one — which, given §4.1's finding that a naively ported `MiSTer_fb` lands on Device memory
on arm64, is not hypothetical.

### 3.3 What the layout does **not** solve

The shared series is 33 patches of *device support*. It contains nothing that makes the two
boards behave alike where it matters — video, audio, fabric signalling — because those five
mechanisms are exactly where the boards differ. **That is not a failure of the split; it is the
correct answer to the question, and §4 is the part of this document that carries the weight.**

---

## 4. The fabric-facing mechanisms

Five mechanisms account for all 7 DE10-only patches and for every hard finding in this audit.
For each: what the DE10 does, what the Agilex path looks like, and — the part that matters —
**the capability stated so that a replacement can be *checked* rather than assumed equivalent.**

Per DP-9, the DE25 adopts Agilex-native DTS/fpga-region idioms instead of the carried UIO
patches. **That decision is not re-litigated here.** What is recorded is what each carried patch
*provides*, in testable form, because "fpga-region replaces it" is a claim about reconfiguration
and several of these capabilities are about **runtime signalling and apertures**, which
`of-fpga-region.c` has nothing to say about (`de25-fpga-reconfig.md` §8, Claim B **refuted**
**[V]**).

### 4.1 Framebuffer — `0001`, `0004`, (`0044`)

**DE10.** Two *independent* paths sharing one patch, and conflating them would produce a DE25
port that looks right and is not. **(a) Pixels:** Main_MiSTer never mmaps `/dev/fb0` — its only
mmap is on `/dev/mem`, at raw physical `FB_ADDR = 0x22000000`, for `1920*1080*4*3` =
24,883,200 B of triple buffer (`abi-contract.md:416`, `:528-533`, `:542-555`) **[V]**.
**(b) fbdev:** `0004` declares `MiSTer_fb@22000000` with `reg = <0x22000000 0x800000>` — 8 MiB,
**buffer 0 only**, deliberately not the full 24.9 MB, and it **must not be "fixed" upward**
(`abi-contract.md:553-555`) **[V]**. `/dev/fb0` exists to serve `FBIO_WAITFORVSYNC` and to let
fbcon paint; nothing else consumes it. The window sits above the `mem=511M` cap, so it has no
`struct page`s and no cacheable linear alias, and the fabric reads it over f2sdram without
snooping the A9 caches.

**Agilex path — three blockers, two invisible to a green DE10 build.**

1. **Hard compile break [V].** `MiSTer_fb.c:303,324,325` reference `NO_IRQ`, defined **only** in
   `linux:arch/arm/include/asm/irq.h:22`. No arm64 and no asm-generic definition exists. (Aside,
   true on both arches: `irq_of_parse_and_map()` returns `0` on failure, never `NO_IRQ`, so the
   guard is dead code and `free_irq()` can be called on a never-requested IRQ.)
2. **Hard semantic break that compiles clean [V].** `MEMREMAP_WT` → `ioremap_wt()`
   (`linux:kernel/iomem.c:113-114`). arm: `ioremap_wt == ioremap_wc` = Normal-NC
   (`linux:arch/arm/include/asm/io.h:390`). arm64: no `ioremap_wt`, so
   `linux:include/asm-generic/io.h:1166-1167` aliases it to plain `ioremap()` =
   `PROT_DEVICE_nGnRE` (`linux:arch/arm64/include/asm/io.h:284`). Consequence: `mode_set()`'s
   full-window `memset()` and the `sys_fillrect`/`sys_copyarea`/`sys_imageblit` direct
   dereferences become memcpy/memset over **Device** memory, where arm64 forbids unaligned
   access and can fault — and the mapping falls to the throughput floor `0045` exists to lift.
   The fix is `MEMREMAP_WC` (→ `ioremap_wc` → `PROT_NORMAL_NC`), which reproduces arm's
   attribute exactly.
3. **Addresses and DT shape [V].** Agilex 5 DRAM base is `0x80000000`
   (`socfpga_agilex5_socdk.dts:32-35`), so `0x22000000` is not DRAM on that SoC. Root
   `#address-cells`/`#size-cells` are `<2>`/`<2>` (`socfpga_agilex5.dtsi:15-16`) against Cyclone
   V's `<1>`/`<1>`, so the 2-cell `reg` is not even syntactically valid there. Cosmetic but
   real: `fb_probe()` prints `(unsigned)fix.smem_start` with `%x`, truncating a 64-bit address.

Where the DE25 window goes is **[U]** — `de25-fpga-reconfig.md` §7.3 already tabulates the four
requirements (LPDDR4A as the HPS-shared bank per DE25 UM §3.7.4; a `/reserved-memory` `no-map`
node; a per-frame fabric IRQ; a coherency discipline) and marks the address pending the GHRD.
DP-10 (tabled) may make this a DRM/KMS question instead, which would change the userspace ABI.

> **Capability to preserve — framebuffer.**
> 1. **Pixel round trip.** Write a known 32-bit pattern at offset 0 through whatever userspace
>    mapping replaces `/dev/mem@0x22001000`; it must (a) appear on HDMI and (b) read back
>    byte-identical **through a second, independently created mapping**. The second mapping is
>    the point: a silent copy-on-write failure passes a read-back through the *same* mapping.
> 2. **Attribute, not just function.** The pixel window must map **Normal non-cacheable, never
>    Device**. Test by `memset()`ing the whole window and checking (a) no alignment fault and
>    (b) fill bandwidth in the DE10's order. Falling to ~100 MB/s write / ~54 MB/s read is the
>    exact signature of a Device mapping — the floor `0045` measured on Cyclone V.
> 3. **The custom ABI, byte for byte.** `echo "8888 1 <w> <h> <w*4>" > /sys/module/MiSTer_fb/parameters/mode`
>    — a plain shell redirect, so it must remain a real writable sysfs attribute, not an ioctl —
>    must succeed, leave `width`/`height`/`stride`/`format`/`rb` reading back exactly those
>    values, increment `res_count` by exactly 1, and have zeroed the window. Formats `8888`
>    (default), `565`, `1555`, `8` (pseudocolor, 256-entry palette) must all exist, each with the
>    `rb` red/blue swap. Main_MiSTer writes this with `fprintf` **and** with
>    `system("echo …")` (`video.cpp:3548`, `:4390`).
> 4. **Node size.** The fbdev region covers buffer 0 only (≥ 8,298,496 B; 8 MiB is correct) while
>    userspace maps 3×. A DE25 DTS that "helpfully" sizes it to the full triple buffer is a
>    regression.
> 5. **fbcon paints.** With no Main_MiSTer running, kernel console output is visible, and stays
>    visible after a mode write. This is what breaks first if the mapping story is wrong, and it
>    fails silently — as a blank terminal, not an error.
>
> **Note for a DRM/KMS replacement (DP-10):** it satisfies *neither* half automatically. `simplefb`
> has no vsync-interrupt concept and cannot serve `FBIO_WAITFORVSYNC` (**[U, inferred]**,
> `de25-fpga-reconfig.md` §7.3), and the pixel path is not an fbdev consumer at all.

### 4.2 Vsync — `0001`, `0004`, (`0043`)

**DE10.** The fabric's `HDMI_TX_VS` pulse drives `f2h_irq0` → Cyclone V GIC **SPI 40**, declared
as `interrupts = <0 40 IRQ_TYPE_EDGE_RISING>` — edge, because it is a true pulse with no cause
register to read back. `irq_handler()` bumps `frame_count` and `wake_up_interruptible(&vs_wait)`;
`fb_wait_for_vsync()` snapshots the count and waits with a 50 ms timeout. The ABI is
`FBIO_WAITFORVSYNC = _IOW('F', 0x20, __u32)` = `0x40044620` — mainline UAPI, **byte-identical on
aarch64 because the argument is a fixed-width `__u32`** (`abi-contract.md:583-607`) **[V]**.
`*arg != 0` → `-ENODEV`; any other cmd → `-ENOTTY`; no vsync in 50 ms → `-ETIMEDOUT`.

**The contract is stronger than "the wake arrives."** Main_MiSTer opens `/dev/fb0`, waits once,
then **times** a second wait with `getus()` (`video.cpp:3856-3868`) — it measures the
inter-vsync interval. Lose the IRQ entirely and every call returns `-ETIMEDOUT` after 50 ms,
which is a hard **20 fps cap on the menu with no error message anywhere**
(`abi-contract.md:612-614`) **[V]**.

**Agilex path.** The *syntax* ports free: Agilex 5's `intc` is `arm,gic-v3` with
`#interrupt-cells = <3>` and `GIC_SPI == 0` in cell 0 (`socfpga_agilex5.dtsi:69-84`) **[V]**, and
the ioctl number is arch-independent. **The number 40 does not port.** Cyclone V routes its 64
f2h lines onto SPI 40–103; Agilex 5's f2h SPI base is **[U]** — `socfpga_agilex5.dtsi` declares
no f2h lines at all, and its in-tree SPI indices are HPS peripherals. Settled by the Agilex 5
HPS TRM's f2h interrupt table (which `de25-fpga-reconfig.md` §7.2 records as returning **HTTP
403** to every fetch on 2026-08-21 and **never read**) plus the DE25 GHRD.

A latent race worth fixing *while* porting **[V code / U impact]**: `frame_count` is a plain
`u32` incremented from IRQ context and read from process context with no `READ_ONCE`, atomic, or
explicit barrier. `wake_up_interruptible()` carries the barrier that makes it converge in
practice on two Cortex-A9s; 2×A76 + 2×A55 is not a reason to assume the DE10's luck transfers.
Relatedly, the DE10's IRQ-affinity arrangement (GIC puts SPIs on CPU0; Main_MiSTer pins *itself*
to CPU1) must be **re-derived** on a big.LITTLE part — copying it is meaningless when CPU1 is an
A55 and CPU2/3 are A76s.

> **Capability to preserve — vsync.**
> 1. `ioctl(fb, FBIO_WAITFORVSYNC, &zero)` returns 0, never `-ETIMEDOUT`, sustained under load.
>    This is the existing DE10 gate (`abi-contract.md` H-2) and it is **necessary but not
>    sufficient**.
> 2. The interval between two consecutive successful calls equals the core's frame period
>    (~16.7 ms at 60 Hz) within a few hundred microseconds, with jitter no worse than the DE10's.
>    **The DE10 baseline has never been measured** — only "returns 0" was ever gated. Measure
>    DE10 first or the comparison is vacuous.
> 3. Error semantics unchanged: `*arg != 0` → `-ENODEV`; other cmd → `-ENOTTY`; 50 ms timeout.
> 4. `/sys/module/MiSTer_fb/parameters/frame_count` advances monotonically at the frame rate —
>    this is how you distinguish "the IRQ fires" from "the wait happens to return".
> 5. **The vsync line must be exclusively kernel-owned.** `uio_pdrv_genirq` cannot share an IRQ
>    at all — its probe fails with *"interrupt configuration error"* when `IRQF_SHARED` is set
>    (`linux:drivers/uio/uio_pdrv_genirq.c:146`) **[V]** — so a UIO node on the vsync line would
>    permanently and silently deny it to the framebuffer.
> 6. Trigger type must match the signal: **edge for a pulse, level for a cause-register-backed
>    line.** Backwards loses events with no diagnostic.

### 4.3 f2h_irq and the FPGA bridges — `0004`, `0001`, (`0043`, `0044`)

**DE10.** Cyclone V routes 64 FPGA-to-HPS lines onto GIC SPI 40–103. The allocation this repo
fixes, and which is the model for whatever the DE25 does:

| GIC SPI (DT cell) | f2h line | Owner | Trigger |
|---|---|---|---|
| 40 | `f2h_irq0` | `MiSTer_fb` — HDMI_TX_VS. Kernel-owned, **not** in the doorbell pool | edge-rising |
| 41 | `f2h_irq1` | `video_sync`, driven by stock gateware (`sys_top.v:573`), **measured 60.17 Hz over 42 s**. Deliberately unclaimed | — |
| 42–47 | `f2h_irq2..7` | Platform reserve (audio ring watermark, CEC). No nodes | — |
| 48–55 | `f2h_irq8..15` | `0043` UIO doorbell pool, `mister_doorbell1..8` | level-high |
| 56–103 | `f2h_irq16..63` | Reserved, no nodes | — |

**The second interrupt cell is the SPI *index*, not the GIC INTID** (INTID = cell + 32). `0043`'s
header flags "correcting" this by subtracting 32 as a **silent brick** — it lands on HPS
peripheral interrupts. `0004` additionally enables `&fpga_bridge0/1/2` (lwhps2fpga, hps2fpga,
fpga2hps); fpga2sdram stays off.

**Agilex path — the structural difference, not just different numbers.** Cyclone V exposes four
address-bearing bridge nodes with in-tree drivers (`linux:drivers/fpga/altera-hps2fpga.c:118-122`).
`socfpga_agilex5.dtsi` has **none** — no bridge node, no `fpga-mgr`, no `fpga-region`, no
`firmware`/`svc` node; grepping the whole file for `fpga` returns only the SoC and stmmac
compatibles **[V]**. For contrast, `socfpga_agilex.dtsi` (Agilex 7) has all three at `:63-80`
**[V]**. And `grep -rn agilex5 drivers/fpga/` returns **nothing** **[V]**. So
`&fpga_bridge0..2 { status = "okay"; }` has no counterpart: on Agilex the bridges are SDM/ATF-owned
and invisible to Linux, and enabling the F2H path is a firmware/U-Boot action, not a DTS one
(`de25-fpga-reconfig.md` §7.1) **[V]**.

**And the F2H path specifically is the one under suspicion**: `de25-fpga-reconfig.md` §1 item 2
records a dated on-Agilex-5-silicon report of the system hanging when the fabric is configured a
**second** time, with the LWH2F bridge implicated and a `bridge enable 0x3b` workaround that
skips F2H **[U, search-corroborated]**. That report is U-Boot-context and not dispositive, but it
means the f2h path should be the **first** thing exercised on DE25, not the last.

> **Capability to preserve — f2h_irq.** *The test shape matters as much as the result.*
> 1. A fabric-raised interrupt wakes a blocked userspace thread. Reproduce `0043`'s measurement
>    discipline: arm a consumer on **every** declared line, run ≥ 42 s, and read the **per-line**
>    event counter. `0043`'s own header records the trap — the first run was read as "eight lines
>    green" because eight probe processes exited 0, when in fact one line was seeing 60 Hz and
>    seven were seeing nothing. **Process exit codes are not evidence.**
> 2. Every line the GHRD says is driven shows its expected rate; every line it says is undriven
>    shows **exactly zero** events *and* a zero initial latched count.
> 3. **No coalescing** on a cause-register-backed line: raise two events before acking the first,
>    count two. This is why `0043` uses level-high, and why `uio_pdrv_genirq` sets
>    `IRQ_DISABLE_UNLAZY` for level IRQs (`linux:drivers/uio/uio_pdrv_genirq.c:185`) **[V]**.
> 4. **Exclusivity acknowledged.** The line the framebuffer uses must have no UIO node and must
>    not be claimable by one; verify the failure is loud.
> 5. Wake-to-userspace latency measured on DE25 **and** compared against a DE10 measurement —
>    which does not exist yet and must be taken as the control.
> 6. Reconfiguration-side behaviour (does f2h still work after a *second* overlay apply?) is
>    `de25-fpga-reconfig.md` §6.3's runnable D2.5 plan. Don't duplicate it; **do** run it before
>    trusting any of the above.

### 4.4 Audio — `0002`, `0004`

**DE10.** Not an ALSA driver, and two halves that must ship together.
**Half 1:** `sound/drivers/MiSTer-audio-spi.c`, an SPI driver on DT `compatible = "MiSTer,spi-audio"`
(HPS SPIM0, mode 3, 10 MHz), which `dma_alloc_coherent()`s a 512 KiB ring (~2.6 s of audio),
exposes `/dev/MrAudio`, truncates writes to whole 4-byte S16_LE **stereo** frames, and then
`spi_write()`s a **16-byte descriptor** `{addr, len, ptr, reserved}` of four `u32`. **The audio
never crosses SPI**: `addr` is the *physical* DMA address of the ring, and the fabric slave is an
**AXI master into HPS DRAM** that reads that ring itself. **Half 2:** `sound/drivers/dummy.c`
gains a `model_MiSTer` (S16_LE / 48000 / **2 ch**) and `fake_buffer` defaults to 0.
`/etc/asound.conf` routes `plug → rate → file("/dev/MrAudio") → hw:0` and the `file` plugin
**tees**; asound.conf pins format and rate but **not** channel count, which is negotiated against
`hw:0`.

**Agilex path — this is the patch that breaks the owner's prior, and it is in none of the three
categories the prior names.**

- **Hard compile break [V].** `dma_alloc_coherent(&g_spi->dev, BUFFER_LEN, &MrBufferInfo.addr,
  GFP_KERNEL)` passes `unsigned int *` where the prototype wants `dma_addr_t *`. `dma_addr_t` is
  `u64` whenever `CONFIG_ARCH_DMA_ADDR_T_64BIT` (`linux:include/linux/types.h:157-161`), which is
  `def_bool 64BIT || PHYS_ADDR_T_64BIT` (`linux:kernel/dma/Kconfig:35`) — unconditionally `y` on
  arm64. `-Wincompatible-pointer-types` is an error by default in the GCC generation this tree
  uses. The patch's own forward-port note states the dead premise outright: *"ARM_LPAE is off on
  Cyclone V, so `dev_t` and `dma_addr_t` are both u32."*
- **And fixing the C type is not fixing the bug [V].** `Info_t` is **wire format** to the fabric.
  aarch64-LE preserves the byte order, so the *format* survives — but 32 bits cannot express an
  address above 4 GiB, and Agilex 5 DRAM starts at `0x80000000`. Either constrain the ring below
  4 GiB (`dma_set_coherent_mask(DMA_BIT_MASK(32))` already asks, and becomes a *real* constraint
  on arm64 rather than the no-op it is on Cyclone V) **or widen the descriptor — which is a
  gateware change, not a kernel one.** Widening the C type alone truncates silently. *This is the
  general shape of the DE25 port: several "kernel" problems are actually gateware contracts.*
- **Coherency is not free [U].** On Cyclone V the fabric reads the ring over f2sdram without
  snooping the A9 caches, and `dma_alloc_coherent()`'s Normal-NC mapping makes that safe.
  `de25-fpga-reconfig.md` §7.2 records that Agilex 5's CCU makes F2H/F2SDRAM coherency **opt-in
  per transaction** via an AXUSER signal the fabric master drives — making "the fabric can read
  the coherent ring" a gateware-design obligation, not a SoC guarantee. That §7.2 is explicitly
  **[U]**: TRM 814346/813752 returned HTTP 403 and was never read; it is search-snippet paraphrase.
- **What ports free [V].** The SPI controller is the *identical* `snps,dw-apb-ssi` on both
  (`socfpga_agilex5.dtsi:326-341`, spi0@`0x10da4000`, GIC_SPI 99). Whether SPIM0's pins reach
  fabric on the DE25 board is **[U]** — needs the schematic/UM pin tables. One Agilex-side
  difference to watch: Agilex 5's spi0 declares `dmas`/`dma-names` where Cyclone V's does not, so
  the dw-spi core installs `can_dma`; the 4- and 16-byte transfers *should* stay PIO because
  `dw_spi_can_dma()` returns false for `len <= fifo_len`, which keeps `device_open()`'s **stack**
  `int rptr` safe under `VMAP_STACK` — but that holds only if the runtime-probed FIFO is ≥ 16
  bytes **[U until read from a real DE25 boot log]**.

> **Capability to preserve — audio.**
> 1. `/dev/MrAudio` with the same identity: dynamic major, chrdev region `MrAudio_proc`, class
>    `MrAudio_sys`, node `MrAudio`.
> 2. Write semantics: length truncated to a multiple of 4; `0` or `> 512 KiB` → `-EFAULT`; the
>    ring wraps at 512 KiB; ≥ ~2.6 s of buffering.
> 3. **The mono test — the whole point of the `dummy.c` half.** Card 0 must advertise exactly 2
>    channels, and a **mono** client must still tee **stereo** into `/dev/MrAudio`. A system that
>    passes the stereo test and fails the mono test **looks healthy and is broken**. Card 0's
>    names must stay snd-dummy's stock strings (`Dummy` / `Dummy 1`) — ABI A11/A12.
> 4. End to end with the verbatim `asound.conf` chain: audible, non-glitching, correct-*pitch*
>    audio. Wrong rate or channel count shows up as pitch/speed error, not silence.
> 5. **The descriptor contract**, the thing most likely to be silently wrong on arm64: the
>    physical ring address the driver prints must be the address the fabric actually reads, and
>    must be **below 4 GiB** while the descriptor field is 32 bits. **Assert this in the driver
>    rather than trusting the allocator.**
> 6. Honest diagnostics: with SPI down, `read()` must report a failure string, not a fabricated
>    length larger than the ring (the B4 bug, fixed in this forward-port —
>    `patch-provenance.md:1509`). Regressing it makes the one diagnostic you read when SPI breaks
>    itself wrong.

### 4.5 Doorbells, apertures and the crash record — `0043`, `0044`, `0045`, `0046`

All four are beta-local; none ships in the stock series. Recorded as capability, per DP-9.

| Patch | What it provides |
|---|---|
| `0043` | A **named, blocking wait on an FPGA-raised interrupt** — eight interrupt-only `generic-uio` nodes, level-typed so a second event raised before ack is not coalesced away, replacing a cause-register spin over the LW bridge. The node **name** is the ABI (`/sys/class/uio/uioN/name`, derived via `%pfwP`), never the minor — adding any UIO node renumbers every later minor. |
| `0044` | **Named, size-bounded mmap** of the two FPGA windows replacing raw `/dev/mem`, so a mapping bug is an `mmap` failure rather than a write into arbitrary physical memory. Carries two hardware rules: **H-1** (a read of an *undecoded* LW offset **hard-hangs the HPS** — no bus fault, no exception, no panic, not one console byte, power-cycle only; confirmed 3× on silicon, once with a capturing serial console; writes presumed equally lethal, never tested) and **MAP_SHARED-always** (UIO has no `VM_SHARED` check anywhere in `drivers/uio/uio.c`, so `MAP_PRIVATE` silently COWs and every store goes to anonymous RAM the FPGA never sees — while a read-back through the same mapping still passes). |
| `0045` | Lifts a **page-attribute throughput floor** measured on Cyclone V at ~100 MB/s write / ~54 MB/s read (23.3 µs for a 2352-byte sector) — a property of the page attribute, not of the bridge. |
| `0046` | A **crash record that survives a warm reset**. Stated honestly by the patch itself: for an H-1-class hang there is **no kmsg dump** — the kernel never reaches its die path, so the dmesg records stay empty for exactly the failure that motivated the node. What survives is the **console** area (printk path) and the **pmsg** area (`/dev/pmsg0` breadcrumbs), which converts a silent brick into a *named offset*. |

**Agilex path.** DP-9 stands and is not re-litigated; `de25-fpga-reconfig.md` is authoritative.
Three things to carry forward. **(i)** D0.2 **splits** DP-9 and the split must not be lost: Claim
A (fpga-region is the proper — indeed *sole* — reconfiguration architecture on Agilex 5) is
**CONFIRMED [V]**; Claim B (fpga-region stands *"in place of"* 0043–0045) is **REFUTED [V]** —
`of-fpga-region.c:353-379` fires only on overlay apply/remove and has nothing to say about how a
*running* core signals the HPS or how the HPS reaches its registers and shared memory. **The
runtime signalling + aperture + coherency contract is open and needs its own DP** (§7).
**(ii)** `0043`/`0044` are literally unportable and would be even if fpga-region did not exist.
**(iii)** `0046`'s *address* is Cyclone-V-only, but its *capability* is board-agnostic and
arguably more valuable on DE25 — and on Agilex 5 the arithmetic must be re-derived from scratch:
DRAM starts at `0x80000000`, the first 32 MiB is already reserved by `svcbuffer@0`
(`socfpga_agilex5.dtsi:23-27`, `no-map`) **[V]**, arm64 has **no HIGHMEM** at all so the
lowmem-hole placement argument *ceases to exist* rather than changing its numbers **[V]**, and
there is no `mem=` cap in the DE25 boot story.

> **Capability to preserve — doorbells and apertures.**
> 1. **Blocking wake:** a consumer blocked on a doorbell fd is woken by a fabric event; the
>    per-line counter increments exactly once per event; two events raised before the first ack
>    yield two counted events.
> 2. **Named bounded mapping:** the *name* is the stable handle and survives adding other nodes
>    (which renumber every later minor); the exported size equals the DT size; an mmap past it
>    **fails** rather than reaching adjacent physical memory. This is the whole point of replacing
>    `/dev/mem`, and the one property trivially lost by "just use `/dev/mem` again on aarch64".
> 3. **Attribute discipline:** the register window maps Device/strongly-ordered and **never**
>    write-combining — on arm64 restate the argument as *Normal-NC is speculatively readable*, so
>    a WC mapping of a window where undecoded reads hang the board could hang it off a
>    **mispredicted path**, with no program access at any bad offset. The bulk aperture maps
>    Normal-NC and must materially beat the Device floor; measure write and read bandwidth the way
>    they were measured on DE10 (~100 / ~54 MB/s is the *failure signature*, not the target).
> 4. **MAP_SHARED:** a `MAP_PRIVATE` mapping must be rejected, or proven not to silently COW.
>    Today it silently COWs on both arches and passes a same-mapping read-back self-test. Make it
>    an actual test, not a comment.
> 5. **Never-probe (H-1):** the rule that *mapping* the register window is safe but *touching* an
>    undecoded offset is lethal must be re-established on DE25 hardware, not assumed to carry. It
>    covers reads **and** writes; only reads were ever measured.
> 6. **Crash record:** after `echo c > /proc/sysrq-trigger` **and** after a watchdog-induced warm
>    reset, `mount -t pstore pstore /sys/fs/pstore` yields `console-ramoops-0` and
>    `pmsg-ramoops-0` containing pre-hang text. Preserve the honest limits in the docs as well as
>    the code: for a hang that never reaches the die path the dmesg records are empty **by
>    design**, and DRAM survives a warm reset, not a power cycle — which is the argument for a
>    watchdog that can turn a hang into a warm reset. Agilex 5 exposes five `snps,dw-wdt`
>    instances for it (`socfpga_agilex5.dtsi:431-470`, all `disabled`) **[V]**.

---

## 5. The hypothesis — did the owner's prior survive?

**The prior.** *"The majority of patches should convert just fine as they're mostly input
related. The ones we need to worry about are the MiSTer / DE10-Nano specific ones for vsync,
framebuffer, and f2h_irq. I would bet money the USB/HID input patches (majority) will be OK on
DE25-Nano."*

**Verdict: SURVIVED on its own terms — 25 of 25 — and it is the *complement* that needs
amending.**

### 5.1 What was actually checked

The instruction was to hunt for input/HID patches that are secretly arch- or platform-coupled.
Every one of the 25 patches under `drivers/hid`, `drivers/input` and `drivers/hid/usbhid` was
opened and its hunks read, and these specific coupling classes were looked for **by name**:

| Coupling class hunted | Found in any HID/input patch? |
|---|---|
| 32-bit `time_t` / `timeval` in a struct or ioctl | **No.** No HID/input patch touches a time-bearing struct. |
| ioctl argument that is a **pointer** (needs `compat_ptr()`/`->compat_ioctl`) | **No.** The only ioctl added anywhere in the 25 is `EVIOCGRAB` in `0026`, whose argument is a **bool, not a pointer** — and the patch header records that its `CONFIG_COMPAT` wiring was *"kept correct for other arches"*, i.e. it was written with non-ARM32 targets in mind. **[V]** |
| Unaligned access / direct dereference of a mapped aperture | **No.** No HID/input patch maps anything; all use `copy_from_user`/`hid_hw_*`/URB buffers. |
| Endianness in an on-wire structure | **No — and where it mattered it was already correct.** `0017` uses `le16_to_cpup()` for the Flydigi raw-mode stick axes; `0036` uses `le16_to_cpu()` on `lmp_subver`. **[V]** |
| DMA / coherency assumptions | **No.** `0011` and `0017` use `usb_alloc_coherent()`, which is the USB core's own API and arch-neutral; none allocates a DMA buffer whose *address* is exposed to anything. |
| `__u32` vs pointer-size struct layout (a pointer stuffed into a fixed-width field) | **No — in the HID/input set.** But see §5.3: this exact hazard **was** found, twice, outside it. |
| A HW block Agilex 5 lacks or has a different version of | **No.** The one hardware-adjacent patch in the set, `0028` (dwc2), targets an IP Agilex 5 **also has** (`snps,dwc2`, `socfpga_agilex5.dtsi:419`), and the bug it fixes is generic host-controller logic that the patch header itself recommends upstreaming. |
| Upstream supersession (patch no longer needed on 6.18) | **No.** Checked case by case against `output/build/linux-6.18.44`. The closest call is `0035`, where provenance records a **partial** upstream fix — the *set*-failure path landed upstream, the *registration*-failure path this patch addresses is still fatal — so it is **carry, not superseded** (`patch-provenance.md:363`) **[V]**. |

**A tested hypothesis that survives is a real result, and this one did.** It is worth being
explicit about *why* it held rather than treating it as luck: the HID/input patches are
overwhelmingly (a) device-ID table rows, (b) evdev keycode/axis table data, (c) LED-classdev and
sysfs naming, (d) probe-failure tolerance, and (e) self-contained USB drivers built on the USB
core's own DMA-safe APIs. None of those five categories has an architectural surface. That is a
structural reason, not an anecdote, and it is why the prior was a good bet.

### 5.2 One caveat that is not a counter-example

`0037` (DualSense mic-mute as `BTN_Z`) is portable in the arch sense and shared in the series
sense — but it is the project's known trap for a *different* reason: `BTN_Z` (0x135) sits between
`BTN_WEST` and `BTN_TL`, so it shifts every higher `EV_KEY` ordinal and therefore every
`gamecontrollerdb` `bN` index. The RT beta series drops it. **That is a known divergence, not a
precedent.** It must be in the shared series on both boards, because the same Main_MiSTer
userspace reads the same database on both. The same reasoning applies to `0034`, `0039`, `0040`,
`0041` and `0042`: they *look* cosmetic (table swaps, format strings) and are **userspace ABI**.
An arch audit that filed them as "trivially portable, low value" would be right about the arch
and wrong about the stakes.

### 5.3 The counter-examples — where the prior is wrong

They are all **outside** the HID/input set, and two of the three are **outside the vsync /
framebuffer / f2h_irq set the prior names**:

1. **`0002` — MiSTer audio SPI. The single hardest arm64 break in the whole audit, and the prior
   does not name audio at all.** It does not compile for aarch64: an `unsigned int` struct member
   is passed where `dma_addr_t *` is required. **[V]** And the type fix alone is wrong — the
   member is FPGA wire format, so the real question is a gateware one (§4.4).
2. **`0001` — MiSTer_fb.** The prior *does* name the framebuffer, so this is a confirmation, not
   a counter-example — except in one respect: the prior's framing is "board-specific hardware, so
   we'll rewrite it", whereas the two findings here are **generic arm-vs-arm64 defects that would
   bite any port of this code even to a board with identical hardware**: arm-only `NO_IRQ`, and a
   `MEMREMAP_WT` correctness argument that is false on arm64. **[V]**
3. **`0043` — the doorbell DTS.** Board-specific as expected, but the deep dive found an arch
   coupling triage missed that lives at the **Kconfig** level, not in any data structure:
   `CONFIG_CMDLINE_EXTEND` **does not exist on arm64** (defined in arm, riscv, powerpc, sh,
   loongarch and `usr/Kconfig` only — `linux:arch/arm64/Kconfig` offers `CMDLINE`,
   `CMDLINE_FROM_BOOTLOADER`, `CMDLINE_FORCE`) **[V]**. So the DE10's `generic-uio` binding recipe
   has no arm64 counterpart; a DE25 would need U-Boot bootargs / DT `/chosen`, or
   `UIO_PDRV_GENIRQ` as a module with a `modprobe of_id=`. `CMDLINE_FORCE` is **not** an
   acceptable substitute — it discards the bootloader's `root=`/`console=`.

**Bottom line for whoever ports.** The prior is a good *triage* heuristic and a bad *stopping
rule*. The right generalisation is: **the risk is not in the subsystem, it is in whether the
patch's correctness argument mentions an address, a memory attribute, a DMA address, or a fixed
width.** Grep the 40 patch *headers* for `LPAE`, `dma_addr_t`, `memremap`, `NO_IRQ`,
`pgprot_`, `strongly-ordered`, `mem=` and `CMDLINE` before grepping the code; every finding in
this audit would have surfaced.

---

## 6. Reconciliation against the plan's "~28 portable / ~8 board"

`de25-nano-plan.md:135-136` estimates *"Kernel patches — input/HID (~28) … port as-is"* and
*"Kernel patches — board (~8: MiSTer_fb, audio SPI, DTS, overclock…)"*.

**Measured: 33 shared / 7 DE10-only, over a union of 40.** The estimate was close, and every
delta is explainable.

| Delta | Explanation |
|---|---|
| **Denominator: 36 → 40.** | The plan's row is written against the 36-patch shipped series (its own text says "all 36+40 patch-by-patch", so it anticipated the union). The union adds `0043`–`0046`, all beta-local; **three of the four are board-specific**, which is why the board count grew rather than the portable count. |
| **"~28 input/HID" → 33 shared.** | The plan's 28 counts the *input/HID class*. The strict HID/input/usbhid count is **25**. The shared series is larger — 33 — because it also holds **8 non-HID portable patches** the row's label does not cover: `0020` (mmc core), `0026` (input core + mousedev — arguably in-class), `0027` (mt76 ID table), `0028` (dwc2), `0029` (leds-gpio), `0030` (i2c-designware), `0031` (exfat), `0036` (btusb), plus `0002` at portable-with-rework. **Net: the plan under-counted reuse.** |
| **"~8 board" → 6 board-specific (7 DE10-only).** | Two reclassifications. **(a)** `0002` (audio SPI) is named in the plan's board list but is judged **portable-with-rework, shared**: its driver code is subsystem-generic C, and only the DT binding and the gateware wire contract are board-coupled — so it belongs in the shared series behind a defconfig gate, not in a board series. **(b)** `0045` is **de10-only by DP-9, not by portability** — the patch itself is generic arch-independent kernel code. Counting the plan's way (audio as board), the figure is 7 against an estimate of ~8: **within one.** |
| **"port as-is" for the whole input/HID row.** | **Confirmed for all 25 [V]** — no rework required on any of them. |
| **The plan's "meaningless until L0; do not port speculatively" for the board row.** | **Confirmed and reinforced.** §4 additionally establishes that mainline 6.18.44 does not yet supply the Agilex-5 idioms a port would build on: no `fpga-mgr`, no `fpga-region`, no bridge nodes, **no MMC/SD node at all**, and **no driver for `intel,agilex5-clkmgr`** (binding and dt-bindings header only) **[V]**. That is a fact D0.2/D1 must confront rather than assume. |
| **Superseded-upstream: 0.** | The plan does not predict a count. None was found; the nearest call (`0035`) is *partially* landed and remains a carry (`patch-provenance.md:363`). |

**Net assessment: the plan's estimate holds.** It under-stated reuse slightly (33 vs 28) and
over-stated the board burden slightly (6–7 vs 8). No structural surprise. The surprises are all
in §4 and §5.3, and none of them changes a *count*.

---

## 7. Open questions — what reading could not settle

| # | Question | Tag | What settles it | Blocks |
|---|---|---|---|---|
| 1 | What GIC SPI range carries `f2h_irq` on Agilex 5, and how many lines? `socfpga_agilex5.dtsi` declares none. | [U] | Agilex 5 HPS TRM f2h interrupt map — `de25-fpga-reconfig.md` §7.2 records TRM 814346/813752 returning **HTTP 403** on 2026-08-21, never read — **plus** the DE25 GHRD's `f2h_irq` wiring. | Any vsync node, any doorbell node (§4.2, §4.3) |
| 2 | Where does the HPS-visible, fabric-writable DRAM window live on Agilex 5, and how big? | [U] | The DE25 GHRD. `de25-fpga-reconfig.md` §7.3 identifies LPDDR4A as the candidate bank (DE25 UM §3.7.4) and marks the address pending. | Framebuffer node, `ramoops` placement, any shared aperture |
| 3 | Is HPS↔fabric coherency automatic on Agilex 5, or **opt-in per transaction** via an AXUSER signal the fabric master drives? | [U] | The TRM (403, never read) or a hardware experiment on the GHRD. `de25-fpga-reconfig.md` §7.2 says opt-in, **from search snippets only**. | Whether a ported `MiSTer_fb` window and the MrAudio ring need explicit cache maintenance — a **gateware** constraint |
| 4 | Does SPIM0 reach FPGA fabric pins on the DE25 board at all? | [U] | DE25 schematic / UM pin tables. | Whether the MiSTer audio topology has any DE25 analogue (§4.4) |
| 5 | Is Agilex 5's SDM served by the existing `intel,agilex-svc` / `intel,agilex-soc-fpga-mgr` drivers, or does it need new compatibles? No agilex5 DTS in 6.18.44 instantiates either, and `drivers/fpga` contains no `agilex5` string **[V]**. | [U] | A newer kernel, the Altera GSRD tree, or the A5-series upstream patches `de25-fpga-reconfig.md` §3.1 tracks. | DP-9's *execution* — the native idiom has no in-tree starting point at this kernel level |
| 6 | Where does the DE25's `intel,agilex5-clkmgr` driver come from? Binding + dt-bindings header exist; **no driver does** **[V]**. | [U] | D0.2/D1 — vendor tree, later mainline, or ATF/SCMI-managed with no Linux clkmgr driver. | Any Agilex 5 clock/DVFS question (§ row 3 of the table) |
| 7 | Does the H-1 failure class (undecoded fabric read wedging the CPU silently) reproduce on Agilex 5, or does the NoC/firewall terminate it as a bus error/SError? | [U] | Hardware. If Agilex 5 aborts cleanly, the console/pmsg areas drop from "only forensic channel" to "convenience". | The never-probe rule, and how much `0046`'s capability is worth on DE25 |
| 8 | Is `0002`'s 16-byte descriptor widened to carry a 64-bit ring address, or is the ring constrained below 4 GiB? | **Owner decision** | Must be taken **before** the driver is ported; a kernel-only fix truncates silently. | §4.4 |
| 9 | Does DE25 need `/dev/fb0` at all, or does an aarch64 Main_MiSTer HAL replace the vsync ioctl with a doorbell `read()`? (DP-10 is tabled and may make this DRM/KMS.) | **Owner decision**, gated on L0 | Determines whether `0001` is forward-ported or retired — and therefore whether the `NO_IRQ` / `MEMREMAP_WT` fixes are worth making. | §4.1, §4.2 |
| 10 | Split `0045` so the generic UIO memtype goes shared/upstream, keeping only the property parse board-local? | **Owner decision** | Its own header says the generic half is upstreamable. `de25-fpga-reconfig.md` §8 states DP-9 does **not** settle this. | §3.2(b) |
| 11 | Split `0002` into a shared `dummy.c` patch and a DE10-only audio-spi patch, or keep it whole behind a defconfig gate? | **Owner decision** | The halves ship together on DE10; splitting is safe there only if both stay applied. | §3.2(a) |
| 12 | **Blocking follow-up inherited from D0.2.** `de25-fpga-reconfig.md` §8 records that `de25-nano-plan.md` §6's DP-9 bullet still reads *"in place of the carried UIO doorbell patches"*, which D0.2's own analysis **refutes**, and that a **new DP** must be opened for the runtime HPS↔FPGA signalling / aperture / coherency contract. **That edit has not been made.** | **Action item** | An edit to `de25-nano-plan.md` §6 plus a new DP. | Until it lands, plan §6 reads as having settled a problem D0.2 explicitly found unsettled. |
| 13 | **Measurement debt — blocks every DE25 comparison in §4.** Three DE10 baselines the capability tests compare against **do not exist**: vsync inter-frame interval and jitter (only *"returns 0"* was ever gated, `abi-contract.md` H-2), wake-to-userspace doorbell latency, and core-switch duration (`de25-fpga-reconfig.md` §1 calls the "a few seconds" figure [U], unmeasured). | [U] | **Take them on DE10 first.** No hardware needed beyond the board already in use. | Otherwise every "no worse than the DE10" test in §4 is vacuous. |

---

## 8. Verification obligation — the spot-check list

Per the D0.3 brief, every **portable** verdict that touches `arch/`, a DTS, or a Kconfig gets an
independent spot-verification pass. Enumerating the diffs by target path **[V]**, six patches
qualify strictly:

| Patch | Verdict | Path that triggers the check | What the check should target |
|---|---|---|---|
| `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model` | portable-with-rework | `sound/drivers/Kconfig` | **The `dma_addr_t` finding.** Confirm the call site and that `-Wincompatible-pointer-types` is an error, not a warning, in this tree's toolchain. Confirm the proposed fix does **not** widen `Info_t`. |
| `0010-hid-guncon2` | portable-as-is | `drivers/hid/Kconfig` | New-symbol placement and `depends on` chain; that nothing in the added driver assumes 32-bit. |
| `0011-hid-guncon3` | portable-as-is | `drivers/hid/Kconfig` | Same, plus the `usb_maxpacket()` 2-arg form against 6.18. |
| `0012-hid-fanatec` | portable-as-is | `drivers/hid/Kconfig` | Largest patch in the shared series (~1745 lines); confirm no `unsigned long`-width or jiffies-arithmetic assumption slipped past triage. |
| `0013-hid-flydigi-vader` | portable-as-is | `drivers/hid/Kconfig` | Symbol placement; report-parsing widths. |
| `0014-hid-gamecube-adapter` | portable-as-is | `drivers/hid/Kconfig` | Symbol placement; the RCU/`work_struct` hot-plug path. |

**Plus one added by judgment, not by the rule** — `0045-uio-writecombine` touches none of those
paths (`drivers/uio/*.c`, `include/linux/uio_driver.h`, `Documentation/`), but it carries a
**portable-as-is** verdict that rests entirely on an **arch memory-attribute claim**
(`pgprot_writecombine` = `MT_NORMAL_NC` vs `pgprot_noncached` = `MT_DEVICE_nGnRnE` on arm64), and
it is the same claim class that produced the `MEMREMAP_WT` finding in `0001`. It should be
spot-checked with the six.

No `board-specific` verdict needs spot-verification for portability — but `0043`'s
`CMDLINE_EXTEND` finding and `0001`'s `NO_IRQ` / `MEMREMAP_WT` findings are the audit's most
load-bearing negative results and are cheap to re-confirm (three greps, all cited inline in §4
and §5.3).

---

## 9. Method, and what this pass did not do

**Did not:** run git, commit, build, run `make`, touch CI, move a file, write a `series` file, or
rebase anything. **Did:** open all 40 patch files; grep `patch-provenance.md` per patch rather
than reading it end to end; read the relevant `kernel-recon/` records; and check every
Agilex-side and arm64-side claim against `output/build/linux-6.18.44`.

**Where the depth is uneven, §2 flags it (⚠) and §1 says how to read the flag.** Eight patches
got a deep dive plus a cross-cutting mechanism pass; 32 got a single triage read. Three of the
eight deep dives overturned or materially corrected their triage verdict — all three on
memory-attribute, DMA or Kconfig grounds, none on subsystem grounds. **The un-deep-dived rows are
device-ID tables, evdev keymaps, format strings and log-severity changes; the confidence in them
is high and the reason is structural, not statistical (§5.1).**

**One caution about the `[V]` tags in this document.** They mean *a file was opened and the cited
lines read* — by this pass for every claim in §4 and §5.3 and for the arch findings, and by the
triage/deep-dive legs for the per-patch rows in §2, whose sources are cited inline. **No `[V]`
here means "built", "booted" or "measured".** Every one of the §4 capability tests is written to
be run on hardware that this audit never touched, and several of them compare against a DE10
baseline that has never been taken (§7 row 13).
