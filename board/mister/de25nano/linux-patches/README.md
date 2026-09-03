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
link to the canonical file in `linux-patches/`. Three — `0015`, `0030`, `0037` — have a
**7.x-re-anchored** copy in `linux-patches-beta/`, and those link to the beta copy, because this
board is on 7.2.x. (`0001` is the fourth divergent pair; it is DE10-only and excluded either way.)

That choice is not cosmetic — the shipped 6.18-anchored copies **hard-fail** on 7.2.x at
Buildroot's `patch -F0`: `0015` 3/5 hunks FAILED, `0030` 1/1 FAILED, `0037` 4/6 FAILED. If you
ever "simplify" these three to point at `linux-patches/`, the build breaks immediately.

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
| 25 | `0031-exfat-samsung-symlinks` | portable-as-is / shared | **included** | Filesystem-format code; `inode_nohighmem()` is a no-op without HIGHMEM (normal on arm64). |
| 26 | `0032-hid-nintendo-joycon-combo-led` | portable-as-is / shared | **included** | Virtual `led_classdev` as a userspace mailbox. |
| 27 | `0033-hid-playstation-dualsense-player-id-led` | portable-as-is / shared | **included** | LED-class/HID only. |
| 28 | `0034-hid-nintendo-nes-famicom-stock-ab-mapping` | portable-as-is / shared | **included** | Userspace ABI (stock A/B order), not cosmetic — audit §5.2. |
| 29 | `0035-hid-nintendo-home-led-nonfatal` | portable-as-is / shared | **included** | Only *partially* fixed upstream; the registration path is still fatal. Carry. |
| 30 | `0036-btusb-csr-clone-lmp-subver-2512` | portable-as-is / shared | **included** | One `else if` on `le16_to_cpu(rp->lmp_subver)`. |
| 31 | `0037-hid-playstation-dualsense-mute-btn-z` | portable-as-is / shared | **included (beta copy)** | **Functional, not cosmetic**: `BTN_Z` shifts every higher `EV_KEY` ordinal, so the shipped `gamecontrollerdb` `platform:MiSTer` rows depend on it. Beta copy differs by hunk offsets only. |
| 32 | `0038-hid-nintendo-nso-genesis-bt-pid` | portable-as-is / shared | **included** | `hdev->product` rewrite before `devm_input_allocate_device()`. |
| 33 | `0039-hid-nintendo-nso-n64-genesis-stock-button-mapping` | portable-as-is / shared | **included** | Static mapping-table reassignment (userspace ABI). |
| 34 | `0040-hid-nintendo-imu-name-suffix` | portable-as-is / shared | **included** | One format-string token Main_MiSTer filters on. |
| 35 | `0041-hid-nintendo-stock-led-classdev-names` | portable-as-is / shared | **included** | `devm_kasprintf()` format restoring stock LED names. |
| 36 | `0042-hid-playstation-stock-lightbar-led-names` | portable-as-is / shared | **included** | LED-class/HID only. |
| 37 | `0043-dts-uio-doorbells` | board-specific / de10-only *(beta)* | **excluded** | Eight `generic-uio` nodes on Cyclone V GIC SPI 48–55; DP-9 adopts Agilex-native idioms instead. `CONFIG_CMDLINE_EXTEND` does not exist on arm64. |
| 38 | `0044-dts-uio-fpga-regions` | board-specific / de10-only *(beta)* | **excluded** | Cyclone V lwhps2fpga/f2sdram apertures; depends on the `mem=511M` bootarg. |
| 39 | `0045-uio-writecombine` | **portable-as-is** / de10-only *(beta)* | **excluded** | Generic and arch-independent, and it would *work* on arm64 — but per DP-9 it has nothing to attach to until a DE25 GHRD exists. Audit §3.2(b)/§7 Q10 keeps "split the generic half to shared/upstream" open as an owner decision; if that is taken, this becomes a candidate for this directory. |
| 40 | `0046-dts-ramoops` | board-specific / de10-only *(beta)* | **excluded** | Every number derives from `mem=511M`, MiSTer's `0x1FFFF000` mailbox and ARM32's HIGHMEM model. The *capability* is worth more on DE25, but the arithmetic must be re-derived (DRAM at `0x80000000`, `svcbuffer@0` already reserved, no HIGHMEM on arm64). |
| — | `0047-btusb-mercusys-ma530-2c4e-0115` | *post-audit (added 2026-09-02)* | **excluded** | Not in the audit; it is a **backport of a mainline commit that is already in v7.2**. Its own header says "DELETE THIS PATCH the moment the kernel pin leaves 6.18.y for 7.2 or newer — at that point the ID is in-tree and re-adding it would collide." This board is on 7.2.2, so the ID is already present. (It is likewise absent from `linux-patches-beta/series`.) |
| — | `0021` | — | n/a | No such patch; the DE10 series has never had one. |

### DE25-local patches (not in the audit — new work)

| # | Patch | Why |
|---|---|---|
| 101 | `0101-mmc-sdhci-cadence-agilex5-40-bit-dma-mask` | Gives `intel,agilex5-sd4hc` its own `of_device_id` entry whose driver data installs a 40-bit DMA mask via the existing `sdhci_ops->set_dma_mask` hook. Addresses `docs/de25-implementation-path.md` §8 Q2 (the leading hypothesis for the mmc0/`arm-smmu-v3` `F_TRANSLATION` fault): mainline takes `DMA_BIT_MASK(64)` where the controller drives only 40 address bits. Its binding hunk also completes `Documentation/devicetree/bindings/mmc/cdns,sdhci.yaml` for this integration — the new compatible string, `clocks` widened to 2 with `clock-names` (`biu`, `ciu`), and `iommus`/`dma-coherent` declared — which is what makes the DE25 `mmc0` node dtbs_check-clean (`docs/de25-dts-rationale.md` §2.4). Upstreamable as-is; carried locally pending submission. |
| 102 | `0102-firmware-stratix10-svc-match-agilex5-svc` | One-line match-table addition so mainline's `intel,agilex5-svc` DT node (shipped in `socfpga_agilex5.dtsi`, listed in the binding, matched by no driver) actually binds. `docs/de25-implementation-path.md` §3.1 bullet 2. Removes the need for a DTS-side compatible override. Upstreamable as-is; carried locally pending submission. |

### Counts

| | |
|---|---|
| Audit rows | 40 |
| Included from the audit | **32** (all 32 `portable-as-is` + `shared` rows) |
| Excluded from the audit | **8** — 7 `de10-only` (`0001` `0003` `0004` `0043` `0044` `0045` `0046`) + `0002` (`portable-with-rework`, deferred) |
| Post-audit patches considered | 1 (`0047`, excluded — already upstream at 7.2) |
| DE25-local patches | **2** (`0101`, `0102`) |
| **Total applied here** | **34** |

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
