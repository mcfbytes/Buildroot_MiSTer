# DE25-Nano kernel patch series — what is here and why

**Base:** mainline Linux **7.2.3**, aarch64 (Agilex 5). See
[`docs/de25-implementation-path.md`](../../../../docs/de25-implementation-path.md) §5 for the
version pin.

**Shape.** This directory follows the same house pattern as
[`board/mister/de10nano/linux-patches-beta/`](../../de10nano/linux-patches-beta/): every patch
shared with the DE10 is a **relative symlink** into the DE10 series, so there is exactly one copy
of each shared patch in the tree and a fix to it lands on both boards at once. Only genuinely
DE25-specific patches are real files here.

**Numbering.** The shared series keeps its DE10 4-digit prefixes (`0010`–`0042`) so
`support/scripts/apply-patches.sh` applies it in the same order on both boards. DE25-local
patches start at **`0101`**, leaving `0043`–`0099` free for anything the DE10 series adds later
without renumbering.

**Where each symlink points.** Most shared patches are byte-identical between
`linux-patches/` (the shipped 6.18 series) and `linux-patches-beta/` (the 7.x series), so they
link to the canonical file in `linux-patches/`. **Four** — `0015`, `0030`, `0031`, `0037` — have a
**7.x-re-anchored** copy in `linux-patches-beta/`, and those link to the beta copy, because this
board is on 7.2.x. (`0031` rejoined that list on 2026-09-06 for a real 7.x API delta, not a
re-anchor — see its row below; this intro said "three" until the Wave-4 audit of 2026-09-11
caught the omission. `0001` is the fifth divergent pair; it is DE10-only and excluded either way.)

That choice is not cosmetic — the shipped 6.18-anchored copies **hard-fail** on 7.2.x at
Buildroot's `patch -F0`: `0015` 3/5 hunks FAILED, `0030` 1/1 FAILED, `0037` 4/6 FAILED. If you
ever "simplify" these three to point at `linux-patches/`, the build breaks immediately. `0031` is
worse than a build break and is why it is on this list at all: its shared 6.18 form **applies and
compiles** on 7.x and then Oopses on the first `ln -s` (row 25 below).

---

## Audit mapping — all 40 rows of `docs/de25-patch-portability.md` §2, plus two later additions

Source of the verdicts: [`docs/de25-patch-portability.md`](../../../../docs/de25-patch-portability.md)
(D0.3, desk audit 2026-08-21). "Series" is that document's second verdict.

| Audit # | Patch | Audit verdict / series | Here? | Reason |
|---|---|---|---|---|
| 1 | `0001-fbdev-add-MiSTer_fb-driver` | board-specific / de10-only | **excluded** | DE10 fabric frame-reader at `0x22000000` + GIC SPI 40; also arm-only `NO_IRQ` and a `MEMREMAP_WT` correctness argument that is false on arm64 (audit §4.1). |
| 2 | `0002-sound-add-MiSTer-audio-spi-and-snd-dummy-MiSTer-model` | portable-**with-rework** / shared (gated) | **excluded** | The only non-`portable-as-is` row in the shared set. It does **not compile on aarch64** (`&MrBufferInfo.addr`, an `unsigned int *`, passed where `dma_alloc_coherent()` wants `dma_addr_t *`), and the audit shows the C fix alone is wrong — the field is a 32-bit FPGA **wire** descriptor and Agilex 5 DRAM starts at `0x80000000` (§4.4). Audit §7 Q8 makes "widen the descriptor or constrain the ring below 4 GiB" an **open owner decision**, and ADR 0027 scopes the first DE25 image to a bare developer OS with no MiSTer binaries, so nothing here consumes `/dev/MrAudio`. **Re-add once Q8 is decided and the type/descriptor fix exists** — at that point it is a shared patch behind a defconfig gate, per audit §3.2(a) Option 1. |
| 3 | `0003-cpufreq-cyclone5-de10nano-overclock` | board-specific / de10-only | **excluded** | Cyclone V gen5 clock-manager MMIO at fixed offsets; Agilex 5 has a different clkmgr. |
| 4 | `0004-dts-de10nano-MiSTer` | board-specific / de10-only | **excluded** | The DE10 board DTS. The DE25 gets its own arm64 DTS (separate work item). |
| 5 | `0010-hid-guncon2` | portable-as-is / shared | **included** | Raw `usb_driver` on generic USB/input APIs. |
| 6 | `0011-hid-guncon3` | portable-as-is / shared | **included** | Standalone USB interrupt-URB HID driver; USB-generic. |
| 7 | `0012-hid-fanatec` | portable-as-is / shared | **included** | USB HID force-feedback; no MMIO/DMA/endianness/pointer-size exposure. |
| 8 | `0013-hid-flydigi-vader` | portable-as-is / shared | **included** | Bluetooth HID remap driver; `BTN_GRIP*` are arch-independent UAPI. |
| 9 | `0014-hid-gamecube-adapter` | portable-as-is / shared | **included** | Generic USB-HID driver over `u8` buffers. |
| 10 | `0015-hid-nintendo-nso-famicom` | portable-as-is / shared | **included (beta copy)** | Two enums, two helpers, two dispatch arms, one button table. The beta copy is re-anchored for 7.x; functional hunks are byte-identical. |
| 11 | `0016-hid-microsoft-elite2-paddles` | portable-as-is / shared | **included** | HID usage mapping of an 8-bit paddle bitmask. |
| 12 | `0017-xpad-mister-deltas` | portable-as-is / shared | **included** | Endianness already handled via `le16_to_cpup()`. |
| 13 | `0018-hid-controllable-quirk` | portable-as-is / shared | **included** | Two device-ID table rows. |
| 14 | `0019-hidpp-k400-fn-inversion` | portable-as-is / shared | **included** | HID++ feature logic; single-byte payloads. |
| 15 | `0020-mmc-no-led-on-send-status` | portable-as-is / shared | **included** | One conditional in core `mmc_start_request()`; host-driver-agnostic. |
| 16 | `0022-hid-playstation-ds4-mac-fix` | portable-as-is / shared | **included** | Probe error-handling policy only. |
| 17 | `0023-hid-wiimote-fixes` | portable-as-is / shared | **included** | Bluetooth HID input mapping only. |
| 18 | `0024-hid-input-keyrah-europe1` | portable-as-is / shared | **included** | One byte in the `hid_keyboard[256]` scancode table. |
| 19 | `0025-usbhid-jspoll-gamepad` | portable-as-is / shared | **included** | One `case` in `usbhid_start()`'s polling switch. |
| 20 | `0026-input-mousedev-eviocgrab` | portable-as-is / shared | **included** | `EVIOCGRAB`'s argument is a bool, not a pointer — no `compat_ptr()` 32-vs-64 hazard. |
| 21 | `0027-mt76x2u-release-xbox-adapter-ids` | portable-as-is / shared | **included** | Deletes two `USB_DEVICE()` rows; a USB ID table has no architecture. |
| 22 | `0028-dwc2-fix-unaligned-in-split` | portable-as-is / shared | **included** | Real generic dwc2 bug; Agilex 5 also declares `snps,dwc2`. |
| 23 | `0029-leds-gpio-brightness-hw-changed` | portable-as-is / shared | **included** | Generic `leds-gpio`/LED-class change; inert until a DTS wires an activity LED. |
| 24 | `0030-i2c-designware-quiet-timeout` | portable-as-is / shared | **included (beta copy)** | Generic Synopsys DW I2C, which Agilex 5's HPS I2C also uses. Beta copy is re-anchored on 7.x's renamed `i2c_dw_init()`; the changed line is byte-identical. |
| 25 | `0031-exfat-samsung-symlinks` | portable-as-is / shared | **included (beta copy)** | Filesystem-format code; `inode_nohighmem()` is a no-op without HIGHMEM (normal on arm64). **Links to the 7.x re-anchored beta copy since 2026-09-06**, the day `scripts/test-initramfs.sh --board de25nano` (the first thing ever to run this patch on a 7.x kernel) found the shared 6.18 form Oopses on symlink CREATION: `page_symlink()` calls `a_ops->write_begin`, and 7.x exFAT is iomap-based with neither `write_begin` nor `write_end`. It applied at `-F0` and compiled, which is why the triage above missed it. The beta copy replaces `page_symlink()` with a buffer-head target writer (see its bracketed note); the aarch64 `symlink` case passes on it — hot+cold, `DT_LNK`, the cluster-leak tripwire, fsck-clean (ADR 0002 §8b). |
| 26 | `0032-hid-nintendo-joycon-combo-led` | portable-as-is / shared | **included** | Virtual `led_classdev` as a userspace mailbox. |
| 27 | `0033-hid-playstation-dualsense-player-id-led` | portable-as-is / shared | **included** | LED-class/HID only. |
| 28 | `0034-hid-nintendo-nes-famicom-stock-ab-mapping` | portable-as-is / shared | **included** | Userspace ABI (stock A/B order), not cosmetic — audit §5.2. |
| 29 | `0035-hid-nintendo-home-led-nonfatal` | portable-as-is / shared | **included** | Only *partially* fixed upstream; the registration path is still fatal. Carry. |
| 30 | `0036-btusb-csr-clone-lmp-subver-2512` | portable-as-is / shared | **included** | One `else if` on `le16_to_cpu(rp->lmp_subver)`. |
| 31 | `0037-hid-playstation-dualsense-mute-btn-z` | portable-as-is / shared | **included (beta copy)** | **Functional, not cosmetic**: `BTN_Z` (0x135, between `BTN_WEST` and `BTN_TL`) shifts every higher `EV_KEY` ordinal, so the shipped `gamecontrollerdb` `platform:MiSTer` rows depend on it — and on DualShock 4 *not* having it. Beta copy's added/removed lines are byte-identical to the 6.18 one; only context differs (7.x's DualSense Edge paddle blocks). **Realigned 2026-09-21** to the shape upstream merged in `0b2ffdd1d` (PR #107): the capability is now declared by a `bool has_mute_button` parameter inside `ps_gamepad_create()`, i.e. *before* `input_register_device()`, which the previous form missed — `joydev_connect()` snapshots `dev->keybit` at handler attach, so `/dev/input/jsN` on a DualSense was 13 buttons instead of stock's 14. No `bN` index moves on any pad. |
| 32 | `0038-hid-nintendo-nso-genesis-bt-pid` | portable-as-is / shared | **included** | `hdev->product` rewrite before `devm_input_allocate_device()`. |
| 33 | `0039-hid-nintendo-nso-n64-genesis-stock-button-mapping` | portable-as-is / shared | **included** | Static mapping-table reassignment (userspace ABI). |
| 34 | `0040-hid-nintendo-imu-name-suffix` | portable-as-is / shared | **retired 2026-09-12** | Was: one format-string token Main_MiSTer filters on. Upstream closed our kernel PR (Linux-Kernel_MiSTer #96) in favour of the userspace fix, Main_MiSTer #1307 (Release 20260912 onward), so the patch was deleted from the shared series and this link with it. |
| 35 | `0041-hid-nintendo-stock-led-classdev-names` | portable-as-is / shared | **retired 2026-09-12** | Was: `devm_kasprintf()` format restoring stock LED names. Same outcome as `0040`: Linux-Kernel_MiSTer #97 closed, Main_MiSTer #1308 falls back to the mainline `:green:player-N`/`:blue:player-5` names. |
| 36 | `0042-hid-playstation-stock-lightbar-led-names` | portable-as-is / shared | **included** | LED-class/HID only. |
| 37 | `0043-dts-uio-doorbells` | board-specific / de10-only *(beta)* | **excluded** | Eight `generic-uio` nodes on Cyclone V GIC SPI 48–55; DP-9 adopts Agilex-native idioms instead. `CONFIG_CMDLINE_EXTEND` does not exist on arm64. |
| 38 | `0044-dts-uio-fpga-regions` | board-specific / de10-only *(beta)* | **excluded** | Cyclone V lwhps2fpga/f2sdram apertures; depends on the `mem=511M` bootarg. |
| 39 | `0045-uio-writecombine` | **portable-as-is** / de10-only *(beta)* | **excluded** | Generic and arch-independent, and it would *work* on arm64 — but per DP-9 it has nothing to attach to until a DE25 GHRD exists. Audit §3.2(b)/§7 Q10 keeps "split the generic half to shared/upstream" open as an owner decision; if that is taken, this becomes a candidate for this directory. |
| 40 | `0046-dts-ramoops` | board-specific / de10-only *(beta)* | **excluded** | Every number derives from `mem=511M`, MiSTer's `0x1FFFF000` mailbox and ARM32's HIGHMEM model. The *capability* is worth more on DE25, but the arithmetic must be re-derived (DRAM at `0x80000000`, `svcbuffer@0` already reserved, no HIGHMEM on arm64). |
| — | `0047-btusb-mercusys-ma530-2c4e-0115` | *post-audit (added 2026-09-02)* | **excluded**, then **retired 2026-09-21** (deleted from the DE10 series once `linux-6.18.53` took the same commit as stable backport `0f7f58ea6299`) | Not in the audit; it is a **backport of a mainline commit that is already in v7.2**. Its own header says "DELETE THIS PATCH the moment the kernel pin leaves 6.18.y for 7.2 or newer — at that point the ID is in-tree and re-adding it would collide." This board is on 7.2.3 (7.2.2 when this row was written), so the ID is already present. (It is likewise absent from `linux-patches-beta/series`.) |
| — | `0021` | — | n/a | No such patch; the DE10 series has never had one. |
| — | `0048-hid-google-stadiaff-classic2usb-retrozord` | *post-audit (added 2026-09-11)* | **included** | Not in the audit; two `hid_device_id` rows (Classic2USB `16d0:1460`, RetroZord `1209:595a`) in `drivers/hid/hid-google-stadiaff.c`, matched with `HID_GROUP_GENERIC` — a USB ID table has no architecture. Main_MiSTer-coupled (`input.cpp:52-53`, `:4176-4177`, `:5102`, `:5349`, `:5496`), so it must not drop silently. Applies clean at `-F0` on 7.2.3 (offset 0). |
| — | `0049-hid-nintendo-8bitdo-adapter-skip-baudrate` | *post-audit (added 2026-09-11)* | **included** | Not in the audit; carried from open PR #92 ahead of merge (owner decision D3) — reorders `joycon_init()`'s USB handshake/baudrate block after `joycon_read_info()` and skips it for 8BitDo-adapter MACs (`E4:17:D8` OUI). USB-generic HID probe-path logic, no architecture exposure. Applies clean at `-F0` on 7.2.3 (offsets only, zero fuzz) after this board's own `0015`/`0032`/`0034`/`0035`/`0038`/`0039` hid-nintendo stack (`0040`/`0041` were in that stack until their 2026-09-12 retirement; the remaining seven re-verified at `-F0` on v7.2.5, zero fuzz). |
| — | `0050-exfat-dir-readahead-plug` | *post-audit (added 2026-09-11)* | **excluded** — 7.2.3 already carries mainline's plugged read-ahead (`fs/exfat/fatent.c` `exfat_blk_readahead`); the 6.18 hunk fails at `-F0` there | A 4-line `blk_start_plug`/`blk_finish_plug` wrap of `exfat_dir_readahead()`'s `sb_breadahead()` loop — but that function does not exist on 7.x at all. `git show v7.2.3:fs/exfat/dir.c` has no `exfat_dir_readahead` and no `blk_start_plug`; the equivalent batching already lives in `exfat_get_dentry()` + `exfat_blk_readahead()` (`fs/exfat/fatent.c:159-183`). Measured: `patch -p1 -F0 --dry-run` against pristine v7.2.3 `fs/exfat/dir.c` reports "Hunk #1 FAILED at 6. Hunk #2 FAILED at 682. 2 out of 2 hunks FAILED". 6.18-series-only per this board's own `linux-patches-beta/series` exclusion (same reasoning, mirror image of `0047`); retires from `linux-patches/` outright when the 6.18.y pin leaves 6.18.y. |
| — | `0051-perf-revert-no-slang-al-addr-stub-mismatch` | *post-audit (added 2026-09-14)* | **excluded** — 7.2.x was never broken; applying the revert there would break it | Reverts stable commit `e97bd4417010` ("perf annotate: Fix build with NO_SLANG=1"), which 6.18.52 cherry-picked without the commit it repairs, `ad83f3b7155db28e` ("perf c2c annotate: Start from the contention line"; the `cd3466cd2639783d` in its `Fixes:` line is a different commit that never touches `hist.h`), leaving `tools/perf/util/hist.h`'s two no-slang inline stubs with a `u64 al_addr` parameter no caller, definition or other declaration in the 6.18.52 tree has. 7.2.x took the prerequisite, so both sides of its `#ifdef HAVE_SLANG_SUPPORT` agree at the `al_addr` arity (v7.2.6 `hist.h:722`/`:725` and `:754`/`:762`) and the revert would strip a parameter its callers pass. Measured: `patch -p1 -F0 --dry-run` against pristine v7.2.6 `tools/perf/util/hist.h` reports "Hunk #1 FAILED at 700. Hunk #2 succeeded at 741 (offset 2 lines). 1 out of 2 hunks FAILED", exit 1 — `patch` stops the build at patch time, which is the desired fail-closed shape. Moot for this board twice over: `configs/mister_de25nano_defconfig` does not select `BR2_PACKAGE_MISTER_USERSPACE`, so nothing here builds `perf` at all. Retires when 6.18.y repairs itself or the DE10 pin leaves 6.18.y. |
| — | `0052-mmc-dw-mmc-socfpga-max-data-timeout` | *post-audit (added 2026-09-21)* | **excluded** — wrong SD controller for this board | Installs a `set_data_timeout` hook on `socfpga_drv_data`, which is reached only through `{ .compatible = "altr,socfpga-dw-mshc", .data = &socfpga_drv_data, }` (`drivers/mmc/host/dw_mmc-pltfm.c:105` on 6.18.52, `:95` on 7.2.6). The Agilex 5 SD controller is a **Cadence SDHCI** part, not a DesignWare one — see `0101` in the table below and `docs/de25-dts-rationale.md` §2.4 — so that compatible never matches here. Moot twice over: `board/mister/de25nano/linux.config` has **no `CONFIG_MMC_DW` at all** (its MMC block is `CONFIG_MMC_SDHCI`/`_PLTFM`/`_CADENCE=y`, lines 178-180), so `dw_mmc-pltfm.c` is not compiled for this board. It is in `linux-patches-beta/series` because the DE10 runs the same Cyclone V controller on 7.x. |
| — | `0053-exfat-dir-count-readahead-one-page` | *post-audit (added 2026-09-21)* | **excluded** — 7.x has no `exfat_dir_readahead()` to bound, same as `0050` | Gives the internal exFAT dentry reader a `max_ra_bytes` argument and uses `PAGE_SIZE` in `exfat_count_dir_entries()` (fork commit `ae4cafc03`, PR #106). 7.2.6 replaced that whole path with `exfat_blk_readahead()` in `fs/exfat/fatent.c:159-185`, called inline from `exfat_get_dentry()` (`dir.c:645-658`). Measured: `patch -p1 -F0 --dry-run` against pristine v7.2.6 reports "Hunk #1 FAILED at 656. Hunk #2 FAILED at 690. Hunk #3 FAILED at 707. Hunk #4 succeeded at 664 (offset -52 lines). Hunk #5 succeeded at 1196 (offset -67 lines). 3 out of 5 hunks FAILED", exit 1. **This one partially applies** — unlike `0047`/`0050`/`0051` a forced apply would leave `exfat_get_dentry()` recursing into itself and calling a nonexistent `exfat_get_dentry_ra()`; `-F0` stops the build first. Note that 7.x is **not already fixed** here, merely differently shaped: 7.2.6 still reads ahead `min(sect_per_clus, EXFAT_BLK_RA_SIZE(sb))` on the same count path, so the amplification exists on this board too. A 7.x fix would be original code with no fork commit behind it; recorded as open in `docs/kernel-recon/fork-sync-2026-09-21.md` §5 rather than invented. Retires with `0050`. |
| — | `0054-dwc2-ddma-keep-frame-list-while-periodic-qhs-remain` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Descriptor-DMA frame-list fix. Symlink it together with `0059` if `fs_ddma` is qualified on this board. |
| — | `0055-dwc2-ddma-frame-list-unmap-direction` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Same as `0054`. |
| — | `0056-dwc2-read-hfnum-for-current-frame` | *post-audit (added 2026-09-26, #205)* | **included** | `dwc2_schedule_periodic()` compares against a cached frame number that can be stale in process context; reachable in buffer DMA, which is this board's mode. Generic dwc2 logic. |
| — | `0057-dwc2-ddma-no-sof-unmask-for-periodic-qhs` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Same as `0054`. |
| — | `0058-dwc2-host-single-irq-action` | *post-audit (added 2026-09-26, #205)* | **excluded** — held for hardware qualification | Changes how the IRQ is requested (one action instead of two). The win is on PREEMPT_RT (one IRQ-thread wake per interrupt); this board's kernel is `PREEMPT_LAZY`. Revisit with the DE25 RT kernel and on hardware. |
| — | `0059-dwc2-fs-ddma-param` | *post-audit (added 2026-09-26, #205)* | **excluded** — held for hardware qualification | The `fs_ddma` opt-in. Needs this board's dwc2 core revision and USB topology (is there an on-board hub?) before it means anything. Bring `0054`/`0055`/`0057`/`0063`–`0066` with it. |
| — | `0060-dwc2-host-keep-periodic-qh-cadence` | *post-audit (added 2026-09-26, #205)* | **included** | A 1 kHz full-speed interrupt endpoint was polled every 2 ms in buffer DMA; generic scheduler fix. |
| — | `0061-dwc2-host-debugfs-hcd-stats` | *post-audit (added 2026-09-26, #205)* | **included** | Debugfs counters only, no behaviour change. Included so hardware qualification can measure this board's SOF and split load with the same counters as the DE10. |
| — | `0062-dwc2-host-sof-holdoff-in-hardirq` | *post-audit (added 2026-09-26, #205)* | **excluded** — held for hardware qualification | Needs `0058`, and like it mainly helps PREEMPT_RT. |
| — | `0063-dwc2-ddma-desc-list-bidirectional` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Same as `0054`. |
| — | `0064-dwc2-ddma-giveback-on-dequeue-halt` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Same as `0054`. |
| — | `0065-dwc2-ddma-halt-before-freeing-desc-list` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Same as `0054`. |
| — | `0066-dwc2-ddma-keep-xfercompl-unmasked` | *post-audit (added 2026-09-26, #205)* | **excluded** — descriptor DMA is off on this board: dwc2 only enables it through `0059`, which is held for hardware qualification, so this code never runs | Same as `0054`. |

### DE25-local patches (not in the audit — new work)

| # | Patch | Why |
|---|---|---|
| 101 | `0101-mmc-sdhci-cadence-agilex5-40-bit-dma-mask` | Gives `intel,agilex5-sd4hc` its own `of_device_id` entry whose driver data installs a 40-bit DMA mask via the existing `sdhci_ops->set_dma_mask` hook. Addresses `docs/de25-implementation-path.md` §8 Q2 (the leading hypothesis for the mmc0/`arm-smmu-v3` `F_TRANSLATION` fault): mainline takes `DMA_BIT_MASK(64)` where the controller drives only 40 address bits. Its binding hunk also completes `Documentation/devicetree/bindings/mmc/cdns,sdhci.yaml` for this integration — the new compatible string, `clocks` widened to 2 with `clock-names` (`biu`, `ciu`), and `iommus`/`dma-coherent` declared — which is what makes the DE25 `mmc0` node dtbs_check-clean (`docs/de25-dts-rationale.md` §2.4). Upstreamable as-is; carried locally pending submission. |
| 102 | `0102-firmware-stratix10-svc-match-agilex5-svc` | One-line match-table addition so mainline's `intel,agilex5-svc` DT node (shipped in `socfpga_agilex5.dtsi`, listed in the binding, matched by no driver) actually binds. `docs/de25-implementation-path.md` §3.1 bullet 2. Removes the need for a DTS-side compatible override. Upstreamable as-is; carried locally pending submission. |

### Counts

| | |
|---|---|
| Audit rows | 40 |
| Included from the audit | **30** (32 `portable-as-is` + `shared` rows, minus the two retired on 2026-09-12 — `0040`, `0041`) |
| Excluded from the audit | **8** — 7 `de10-only` (`0001` `0003` `0004` `0043` `0044` `0045` `0046`) + `0002` (`portable-with-rework`, deferred) |
| Post-audit patches considered | 6 (`0047` excluded — already upstream at 7.2, and retired 2026-09-21 when 6.18.53 took it too; `0048`, `0049` included — 2026-09-11; `0050` excluded — 7.2.3 already carries mainline's own plugged read-ahead, 2026-09-11; `0051` excluded — a revert of a 6.18.y-only backport defect 7.x never had, 2026-09-14; `0052` excluded — DesignWare MMC hook, this board is Cadence SDHCI, 2026-09-21; `0053` excluded — 7.x has no `exfat_dir_readahead()` to bound, 2026-09-21) |
| dwc2 series `0054`–`0066` (#205) | 13 considered, **3** included (`0056`, `0060`, `0061`); 10 held: the descriptor-DMA set and `0058`/`0059`/`0062` wait for hardware qualification (`docs/dwc2-usb-irq.md`) |
| DE25-local patches | **2** (`0101`, `0102`) |
| **Total applied here** | **37** |

## Note for the DE25 DTS

`0101` adds `intel,agilex5-sd4hc` to the **vendor `enum` inside the `items:` list** in
`cdns,sdhci.yaml`, which is the two-element form:

```dts
compatible = "intel,agilex5-sd4hc", "cdns,sd4hc";
```

**The order is load-bearing for `dtbs_check`** — the vendor string first, `cdns,sd4hc` second, and
both present. A single-string `compatible = "intel,agilex5-sd4hc"` would bind the driver but fail
the schema; `compatible = "cdns,sd4hc"` alone stays schema-clean but binds the generic entry and
therefore **does not get the 40-bit mask**.

The same binding hunk also declares the four properties the Agilex 5 `mmc0` node needs and the
schema previously lacked, so the node may carry all of them and stay clean:

- `clocks` — now `minItems: 1, maxItems: 2`, and `clock-names` accepts `biu`, `ciu` in that order;
- `iommus` — `maxItems: 1` (same form as `usb/dwc2.yaml` for another Agilex 5 peripheral);
- `dma-coherent` — `true` (as nine other `mmc/*.yaml` bindings already declare).

Nothing here is made mandatory, so the in-tree `cdns,sd4hc` boards are unaffected — verified:
`uniphier-ld20-ref.dtb` and `elba-asic.dtb` both build `CHECK_DTBS=y`-clean with the patch applied.

`0102` means the DTS does **not** need to override `/firmware/svc`'s compatible to
`"intel,agilex-svc"`; mainline's `"intel,agilex5-svc"` now binds directly, and the binding's
`allOf` requirement that `iommus` be present for that string continues to hold.

## Verification

Both DE25-local patches were generated with `git format-patch` against a pristine
`linux-7.2.2` tree and re-checked with `git apply --check`. The whole directory applies with
Buildroot's own applier at its `patch -F0` (zero-fuzz) setting:

```
work/buildroot/support/scripts/apply-patches.sh <fresh linux-7.2.x> \
    board/mister/de25nano/linux-patches
```

34/34 applied, zero hunks taking fuzz, zero rejects, exit 0. `scripts/lint-kernel-patches.sh`
accepts this directory as an argument and passes.

RE-VERIFIED AT 7.2.3 (2026-09-02), when Renovate's rt bump moved the shared `linux.hash` and the
DE25 pin followed (`docs/buildroot-config.md` §6.4). `make de25` after a `linux-dirclean` on a
freshly downloaded, hash-verified `linux-7.2.3.tar.xz`: **34/34 applied, 0 hunks with fuzz, 0
rejects**, 79 hunks relocated by line OFFSET only — which `patch -F0` permits (`-F` caps *fuzz*,
i.e. context mismatch, not displacement). Note what this does and does not prove: the series still
applies and the kernel still builds; nothing here has been run on hardware at 7.2.3.

`dtbs_check` on `socfpga_agilex5_de25nano.dtb` at 7.2.2 + `0101` + `0102` (the measurement was
taken at 7.2.2 and has not been re-run at 7.2.3) leaves **5** warnings,
all of them the expected `fpga-mgr` two-string ones from `docs/de25-dts-rationale.md` §2.2 rows
1–5; both `mmc@10808000` warnings are gone. `make dt_binding_check
DT_SCHEMA_FILES=Documentation/devicetree/bindings/mmc/cdns,sdhci.yaml` is clean
(CHKDT / LINT / STYLE / example DTC all pass).

RE-VERIFIED AT 7.2.3 (2026-09-11), fork-sync increment 2026-09 Wave 3, after adding `0048` and
`0049` (both post-audit, symlinks into `../../de10nano/linux-patches/`) and considering and
excluding `0050` (see its row above). `patch -p1 -F0` replay of the full 36-entry directory
against a pristine `linux-7.2.3` extract: **36/36 applied, 0 hunks with fuzz, 0 rejects** — `0048`
at offset 0, `0049` at offsets only (20/21/21 lines across its three hunks, matching the offsets
measured for the beta series' own hid-nintendo stack) — plus a separate dry-run confirming `0050`
FAILS both hunks against the same pristine tree, exactly as its excluded row states.
`scripts/lint-kernel-patches.sh` accepts the directory and passes with `0048`/`0049` included.

RE-VERIFIED AT 7.2.7 (2026-09-26), after adding the dwc2 patches `0056`, `0060` and `0061`
(symlinks into `../../de10nano/linux-patches/`). `apply-patches.sh` on a pristine `linux-7.2.7`
extract: **37/37 applied, 0 hunks with fuzz, 0 rejects**. `drivers/usb/dwc2/` builds with W=1 for
arm64 against this board's `linux.config` plus `common/linux-mister.fragment`; the only warning is
the pre-existing `remotewakeup` kerneldoc one in `core_intr.c`. `scripts/lint-kernel-patches.sh`
passes. Not run on hardware.
