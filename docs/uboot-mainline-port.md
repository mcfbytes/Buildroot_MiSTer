# Plan — a modern mainline U-Boot for the DE10-Nano, built from source as a capability artifact

**Status:** proposed (2026-07-28). **Supersedes in part:** [ADR 0017](decisions/0017-uboot-from-mister-fork-full-sd-image.md)
§Decision-1 (which chose the 2017.03 fork and rejected the mainline port).
**Requires a new ADR:** 0024 (0023 is the highest in `docs/decisions/`).
**Specification being reproduced:** [`docs/boot-chain.md`](boot-chain.md) — cited by section
throughout; nothing from it is restated here.

---

## 1. What this is, and what it is not

Build **mainline U-Boot 2026.04** for the MiSTer, configured to behave as close to
identically to the stock 2017.03 fork as the evidence allows, as a **build artifact only**.

**Not changing, and gated so it stays that way:**

* The default release channel keeps shipping the **stock `uboot.img` byte-identical**
  (515,141 B, sha256 `e2d46cf9…62ba64`), fetched by hash. ADR 0017 §Decision-5 stands.
* `sdcard.img` keeps embedding that same stock blob. `scripts/mk-sdcard.sh` and
  `scripts/check-sdcard.sh` are untouched.
* `configs/fragments/de10nano-image.fragment` gains **no** `BR2_TARGET_UBOOT*` line.
* **No artifact this plan produces may ever be named `uboot.img`.** `updateboot` `dd`s
  `/media/fat/linux/uboot.img` over the `0xA2` partition on every Linux update with no
  version check, no hash check and no opt-out (boot-chain §5). The build output is
  `u-boot-with-spl.sfp` and is published, if at all, under a name that cannot collide.
* Nothing here touches hardware until §8's gate is passed.

**What changes versus ADR 0017:** 0017 rejected mainline because it meant "new code in the
one component whose failure mode is a bricked board." That objection was correct about the
*shipping* decision and is preserved above. It was wrong about the *cost*: the port surface
is now measured, not estimated, and it is five deltas, four of which are configuration.

---

## 2. Verdict

**A mainline port is feasible and the build already exists.** U-Boot 2026.04 and 2026.07
both compile clean for `socfpga_de10_nano_defconfig` with this repo's own Buildroot gcc
14.4 cross toolchain, producing a `u-boot-with-spl.sfp` whose on-disk structure matches
boot-chain §2 exactly — four byte-identical 64 KiB SPL copies, a valid Altera `AS01` header
at `+0x40`, a legacy uImage (not a FIT) at `0x40000`, load `0x01000040`, total closing the
file exactly. No binman, no ITB, no toolchain work.

**But a naive `socfpga_de10_nano_defconfig` build would not boot a MiSTer card, and two of
the reasons are upstream defects.** Five deltas must be carried. Three are silent-brick if
omitted. All five are now demonstrated fixes, not proposals.

---

## 3. What the research established

Two workflows, 18 agents, with adversarial verification that re-ran the decisive steps
independently. Where a verifier corrected a finding, the verifier's figure is used.
Scratch trees are under `/mnt/source/uboot-mainline/` (outside the repo, gitignored by
being outside it).

### 3.1 The five must-carry deltas

| # | Delta | Why it is required | Fix | Risk |
|---|---|---|---|---|
| 1 | SPL raw-mode selector | Mainline dropped `ARCH_SOCFPGA`'s unconditional `select SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION`; the methods are now a Kconfig `choice` and the DE10-Nano defconfig picks none, falling through to **absolute LBA `0x400`**. The built SPL ignores the MBR — `mmc_load_image_raw_partition` is not even linked in. Breaks the type-`0xA2` contract of boot-chain §2.1. | `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y` (one defconfig line; deselects `USE_SECTOR`, and the `SECTOR` symbol disappears outright, so the feared double-count to `+0x400` is unreachable) | **brick** |
| 2 | Dead `+0x200` hook (**upstream bug**) | With #1 applied, `raw_sect` is 0 and the SPL would load from the *start* of the `0xA2` partition — i.e. SPL copy 0. The hook that supplies `+0x200`, `board_spl_mmc_get_uboot_raw_sector()` (`arch/arm/mach-socfpga/board.c:216-221`, added 2025-12-11 by `1cf1b504f4`), is **dead code**: commit `62f7a94602` (2026-02-13) renamed `TARGET_SOCFPGA_*` → `ARCH_SOCFPGA_*` and missed this one guard at `board.c:214-215`. Those two lines are the only remaining references to the old symbols in the whole tree. Still broken at v2026.10-rc1 and `origin/main` (`134ad3c3c0`, 2026-07-27). Also silently affects Arria10. | One-line guard fix. Verified by rebuild: `nm` shows the override compiled and linked (absent before). Load path then matches boot-chain §2.1 exactly. **Upstreamable.** | **brick** |
| 3 | exFAT | Stock's U-Boot **reads exFAT** — the fork replaced the FAT driver with ChaN FatFs (`fs/fat/ffconf.h:212 #define _FS_EXFAT 1`; the literal `EXFAT` string is in the shipped binary). Mainline's `fs/fat/fat.c:68-95` rejects anything that is not `FAT`/`FAT32`. Given ADR 0020 reformats the data partition to exFAT, a mainline U-Boot without this cannot load `zImage_dtb`. Mainline *has* `CONFIG_FS_EXFAT`, but it **fails to link on 32-bit ARM**: `undefined reference to __aeabi_ldivmod` at `fs/exfat/time.c:129,147-149`. No 32-bit board in tree enables it, so nobody has hit it. | `CONFIG_FS_EXFAT=y` + a `do_div()` patch. A working fix was written and built green independently. **Upstreamable.** | **brick** |
| 4 | QTS handoff data | MiSTer deliberately replaced Terasic's Quartus handoff with its own (`dadd1c8978`, Sorgelig, 2017-04-01, *"Use SPL config from DE10 FB project"*). Detail in §3.2. | Carry the fork's four `board/terasic/de10-nano/qts/*.h` with `s/CONFIG_HPS_/CFG_HPS_/` | high |
| 5 | The entire environment | The built default env has 43 entries and **not one MiSTer variable** — no `bootcmd`, no `bootargs` (both `USE_*` symbols off in the defconfig). Mainline's `distro_bootcmd` is present but inert, and its `mmc_boot` **collides** with stock's variable of the same name. The board would sit at the prompt. | `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE=y` + `CONFIG_ENV_DEFAULT_ENV_TEXT_FILE=…` (`env/Kconfig:771`/`:781` in 2026.04) — verified to reproduce a stock-shaped blob byte-for-byte in a built binary | **brick** |

### 3.2 The QTS handoff: much safer than ADR 0017 assumed, but not empty

Independently derived twice (once by me, once by a verifier with its own parser), on
`board/terasic/de10-nano/qts/`, fork `8dcc3484` vs mainline v2026.07, normalizing only the
`CONFIG_HPS_` → `CFG_HPS_` rename:

**Identical — every value that would kill DDR bring-up:** all 157 `sdram_config.h` defines
but two; every DDR3 timing and geometry (`MEMTYPE=2`, `MEMBL=8`, `TCL=7`, `TCWL=7`,
`TFAW=15`, `TRFC=120`, `TRCD=6`, `TREFI=3120`, `TRP=6`, `TWR=6`, `TRAS=14`, `TRC=20`,
`ROWBITS=15`, `COLBITS=10`, `BANKBITS=3`, `DEVWIDTH=8`, `IFWIDTH=32`, ODT, PHY control);
both sequencer ROMs (`ac_rom_init` 36 words, `inst_rom_init` 127 words) at **zero**
differing words; **`iocsr_scan_chain3_table` — the DDR3 HPS I/O bank — 0 of 524 words
differ**; all four `SCANCHAIN*_LENGTH`; every DDR clock in `pll_config.h`.

**Divergent — all in the HPS↔FPGA interface:**

| Value | Fork | Mainline | Meaning |
|---|---|---|---|
| `CFG_HPS_SDR_CTRLCFG_FPGAPORTRST` | `0x3FFF` | `0x1FF` | releases 14 vs 9 FPGA→SDRAM port resets. Lives in `sdram_config.h` and is written to the SDRAM controller by the SPL (`drivers/ddr/altera/sdram_gen5.c:466`), so "the divergence is entirely non-DDR" is **wrong** — but it is a controller register, not a timing. Accepting mainline's value leaves five fabric ports in reset; MiSTer cores could lose SDRAM access. |
| `REG_FILE_INIT_SEQ_SIGNATURE` | `0x555504a0` | `0x555504a1` | Quartus generator stamp |
| `PERPLLGRP_S2FUSER1CLK_CNT` | 511 | 19 | HPS→FPGA user clock 1 |
| `SDRPLLGRP_S2FUSER2CLK_CNT` | 4 | 5 | HPS→FPGA user clock 2 |
| `pinmux_config.h` | — | — | 3 substantive bits: `GENERALIO3`, `GENERALIO4` (fork 0 / mainline 1, from `f7d1761b89` "Switch i2c to gpio mode for smbus compatibility"), `I2C3USEFPGA` |
| `iocsr` chains 0/1/2 | — | — | 32 of 108 words (chain0 12/24, chain1 18/54, chain2 2/30) |

Two provenance notes that matter. **Mainline's DE10-Nano QTS headers have had no value
change since `6bd041f00d` (2017-04-18)** — every later touch is SPDX, the `CFG_` rename, or
whitespace. Carrying the fork's headers therefore forfeits no upstream fix stream and will
not fight future churn. And the fork and mainline **imported the board independently**
(fork `c7ed0834ac` 2017-03-27; mainline `6bd041f00d` 2017-04-18) — v2017.03 has no
DE10-Nano at all.

### 3.3 Three further divergences, none previously documented

* **uImage entry point.** Mainline sets `ih_ep = CONFIG_TEXT_BASE` (`0x01000040`) via
  `CONFIG_SYS_UBOOT_START`; the fork leaves it `0`. Worse, the two SPLs read *different
  fields*: the fork's uses `ih_load` (`common/spl/spl.c:110`), mainline's uses `ih_ep`
  (`common/spl/spl_legacy.c:57`). Each build is self-consistent, but **a mainline SPL and a
  stock `uboot.img` are not interchangeable** — mixing them jumps to `0x0`. This constrains
  partial-flash and recovery procedures.
* **`CONFIG_ENV_OFFSET` is `0x4400` in mainline vs `512` in the fork** (`ENV_SIZE` `0x2000`
  vs `4096`). `updateboot` zeroes only sector 1 (boot-chain §5), so on mainline a saved
  environment would **survive** where stock guarantees it never does — quietly voiding
  Consequence (b) and the "effective env is always defaults + `u-boot.txt`" invariant.
* **`bridge enable` semantics changed.** Present in mainline (`arch/arm/mach-socfpga/misc.c:197-229`)
  but not equivalent to the fork's (`misc.c:437-464`), and this is on the **cold-boot** path
  since `fpgaload` runs it every boot. Separately, the fork's `arch_early_init_r` re-enables
  bridges when the FPGA is already in user mode (`d6010efe50`, Sorgelig, 2017-03-27);
  mainline's `misc_gen5.c:188-214` calls only `socfpga_bridges_reset(1)`. **A cold-boot
  smoke test cannot catch this** — it is the warm-reboot core-handoff path.

### 3.4 `mt` — solved, and testable on stock hardware first

Stock's `fpgacheck` uses `mt`, a MiSTer-only command (boot-chain §3.3). The replacement is
**`itest.l *<addr> == <val>`** — verified *by execution*, not inference: a verifier built a
real U-Boot 2026.04 sandbox binary and ran the rewritten `fpgacheck` through all three
warm-reboot dispatch cases of boot-chain §6.1, confirming the exit-status sense matches
(`do_itest` returns `!value`; hush takes THEN iff `rcode==0`, matching the fork's
`memcmp(...) ? 1 : 0`).

Two traps found along the way:

* **`setexpr` + `test -eq` is a silent trap** and must not be used: `env_set_hex` writes
  bare lowercase hex, `test -eq` parses base-0, so the comparison is false forever and every
  warm reboot silently takes the cold path.
* `itest` **also exists in the stock 2017.03 binary** (its help text is in
  `work/uboot-proper.bin`). The rewritten `fpgacheck` is therefore **bidirectionally
  compatible** — it can be smoke-tested on real hardware under the *stock* bootloader,
  before any mainline image is flashed. That is a free de-risking step and §8 uses it.

### 3.5 Size and headroom

| | Stock | Mainline 2026.04 |
|---|---|---|
| `u-boot-with-spl.sfp` | 515,141 B | 795,776 B (2026.07: 797,648 B) |
| SPL (`spl/u-boot-spl.bin`) | 45,820 B incl. CRC | 57,006 B against a 62,752 B limit — **5,746 B headroom (90.8 % used)** |

Mainline enforces `SPL_SIZE_CHECK` at build time. 2017.03 does **not**: workflow 1 proved
`tools/socfpgaimage.c:218-225` guards with no else branch, so an oversized SPL prints
"Not a sane SOCFPGA preloader", **exits 0**, and writes a header with a truncated
`length_u32` (`build_header()` takes a `uint16_t`). Choosing mainline removes that
silent-corruption window outright.

Headroom is recoverable: dropping the unused SPL SPI/QSPI stack (`SPL_SPI`,
`SPL_SPI_FLASH_SUPPORT`, `SPL_DM_SPI`, `SPL_SPI_LOAD`) takes it from 12.6 % to **30.4 %**,
restoring stock's margin. Dropping `EFI_LOADER`/`NET`/`USB` shrinks U-Boot proper from
533 KB toward stock's 253 KB and removes the `gnutls` host dependency.

The `0xA2` partition is 4 MiB in our own `genimage-sdcard.cfg:132-135`, so 795,776 B fits
with room. **It is unknown what size mr-fusion and the Windows SD installer create** — see
§9; `updateboot` `dd`s with no size check.

### 3.6 Buildroot wiring is pure configuration

Measured against `work/buildroot` (2026.05.1), not recalled:

* `BR2_TARGET_UBOOT_LATEST_VERSION=y` is the **only** choice for which Buildroot
  hash-verifies the tarball (`uboot.mk:41-43` adds `BR_NO_CHECK_HASH_FOR` for every
  `CUSTOM_*`). It resolves to **2026.04** (`Config.in:88`), whose sha256
  `ac7c04b8…f2fd` was confirmed byte-identical to `boot/uboot/uboot.hash`. This matches the
  repo's hash-pinning convention for free.
* No `.sfp` format exists in the menu (`Config.in:373-551`) → `BR2_TARGET_UBOOT_FORMAT_CUSTOM`
  + `_CUSTOM_NAME="u-boot-with-spl.sfp"`. **No custom make target is needed**: upstream
  `Kconfig:528` sets `CONFIG_BUILD_TARGET="u-boot-with-spl.sfp"` for gen5 and folds it into
  `INPUTS-y`, and `uboot.mk:66` already calls `all`.
* **`BR2_TARGET_UBOOT_ALTERA_SOCFPGA_IMAGE_CRC` must stay off** — a socfpga-shaped trap.
  Mainline already wraps the SPL with `mkimage -T socfpgaimage`
  (`scripts/Makefile.xpl:436-441`); enabling it double-wraps via host `mkpimage`
  (`uboot.mk:561-579`).
* `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES` exists (`Config.in:140-145`, `uboot.mk:401`) and
  applies via `merge_config.sh -m` + `olddefconfig` (`pkg-kconfig.mk:191-199`) — **the same
  mechanism `make rt` uses**, and therefore **the same hazard**: dropped symbols only warn.
  The `rt` recipe's `PREEMPT_RT` guard (`Makefile:504-521`) is the precedent for the
  resolved-`.config` assertion this build needs.
* `BR2_TARGET_UBOOT_PATCH` (`Config.in:103-113`, `uboot.mk:342-354`) picks up
  `board/mister/de10nano/uboot-patches/` on the ordinary extract/patch flow, honours a
  `series` file, applies at fuzz zero. (Note: `UBOOT_OVERRIDE_SRCDIR` would have **skipped
  patching entirely** — `pkg-generic.mk:945` — which is why the tarball source, not ADR
  0017's submodule-override scheme, is the right shape here.)
* Host deps, measured: `openssl` yes; `gnutls` only because `CONFIG_TOOLS_MKEFICAPSULE=y`
  pulls it in (a host-only tool that cannot touch target images — disable it in the fragment
  rather than adding `host-gnutls`); `dtc`/`python3`/`pylibfdt`/`binman` **not needed** for
  gen5.

---

## 4. Design

**Source.** Mainline U-Boot **2026.04** via `BR2_TARGET_UBOOT_LATEST_VERSION=y` — hash-verified
by Buildroot, no submodule, no vendored tree, standing rule 1 satisfied trivially.
**Pin deliberately, do not float:** 2026.04 is the last release where §3.1 delta #2 is a
one-line fix in a *known* place. A U-Boot bump must re-verify deltas #1 and #2 against the
resolved `.config`, because #1 is a Kconfig `choice` whose default can flip with no diff in
our files.

**Layering**, mirroring the RT kernel's two-layer model exactly:

| Layer | File | Contents |
|---|---|---|
| Buildroot config | `configs/mister_uboot_defconfig` | `BR2_TARGET_UBOOT*`, toolchain, no rootfs |
| U-Boot config | `board/mister/de10nano/uboot-mister.fragment` | the `CONFIG_*` deltas of §3.1/§3.3 |
| Environment | `board/mister/de10nano/uboot-mister.env` | stock's env as text, `itest`-rewritten `fpgacheck` |
| Patches | `board/mister/de10nano/uboot-patches/` | the two upstream fixes + the QTS headers |

**Output artifact:** `output-uboot/images/u-boot-with-spl.sfp`. Never `uboot.img` (§1).

**Patches carried** — each needs a CONTRIBUTING.md provenance header, using
`board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch` as the template:

1. `0001-arm-socfpga-fix-dead-raw-sector-hook-guard.patch` — the `TARGET_`→`ARCH_` guard
   (§3.1 #2). **Upstream this.**
2. `0002-fs-exfat-fix-64-bit-division-on-32-bit-arm.patch` — `do_div()` in `fs/exfat/time.c`
   (§3.1 #3). **Upstream this.**
3. `0003-board-terasic-de10-nano-mister-qts-handoff.patch` — the four QTS headers (§3.2).
   Never upstreamable; MiSTer is a different FPGA design on the same board.
4. Warm-reboot bridge behaviour (§3.3) — **carrier undecided**, see §9.

Note that patches 1–3 are *behaviour* changes, not build fixes. ADR 0017 restricted
`uboot-patches/` to build fixes only; that restriction was written for a fork build where
any behaviour delta would be a regression against a proven binary. It does not survive
contact with a mainline port and ADR 0024 must say so explicitly.

---

## 5. Implementation steps

Mapped onto existing task IDs — this **amends** P5.1/P5.2 rather than renumbering.

**Step 0 — record the decision.** Write `docs/decisions/0024-mainline-uboot-capability-artifact.md`
in 0017's format. It records: mainline replaces the fork *for this artifact only*; the
default channel is untouched; `uboot-patches/` may now carry behaviour changes with
provenance; the three of 0017's objections that survive (blast radius, unproven-on-hardware,
`mt`/`fpgaload`/mailbox behaviour needing reproduction). Amend PLAN §8 and TASKS P5.1/P5.2
to point at this plan. *Done when:* ADR merged, `0017` annotated (not rewritten — it stays
the record of why the fork was once the cheaper path).

**Step 1 — Buildroot skeleton (amends P5.1).** `configs/mister_uboot_defconfig` +
`make uboot` / `make uboot-clean` into `O=output-uboot`, modelled on `installer`
(`Makefile:604-623`), **not** `rt` (whose merge_config and module-staging dance is
irrelevant here). *Done when:* `make uboot` produces `output-uboot/images/u-boot-with-spl.sfp`
from a clean tree.

**Step 2 — the five deltas (amends P5.1).** Fragment + env file + the three patches of §4.
*Done when:* the resolved `.config` assertion in the recipe passes for
`SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y`, `SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION_TYPE=0xa2`,
`SYS_MMCSD_RAW_MODE_U_BOOT_USE_SECTOR` **not** set, `FS_EXFAT=y`, `ENV_OFFSET=0x200`,
`TEXT_BASE=0x01000040`, `SPL_PAD_TO=0x10000` — and `nm` proves
`board_spl_mmc_get_uboot_raw_sector` is linked into the SPL.

**Step 3 — parity check (amends P5.2).** `scripts/check-uboot-parity.sh`, §6. *Done when:*
it passes against the built artifact and its allowed-delta list is complete, with
`docs/verification/uboot-mainline.md` recording every diff and its explanation.

**Step 4 — CI.** `.github/workflows/uboot.yml`, `workflow_dispatch` primary + `pull_request`
scoped by `paths:` to the five U-Boot inputs. Manual-first per the budget posture stated in
`reproducibility.yml:26-32`; path scoping per `lint.yml:26-36`. It is **not** a kernel
variant and must not join `build.yml`'s matrix.

**Step 5 — hardware (P5.4, gated).** §8.

---

## 6. Verification

`scripts/check-uboot-parity.sh`, in the house style of `check-zimage-dtb.sh` (POSIX `sh`,
`set -eu`, header citing boot-chain sections, `Usage:`, `Exit: 0/1/2`, `note()/ok()/bad()`).

**Structural assertions** (hard failures): four byte-identical 64 KiB SPL copies; Altera
header at `+0x40` (validation `0x31305341`, `length_u32`, checksum); legacy uImage magic at
`0x40000` with recomputed header and payload CRCs; `load=0x01000040`; total size closes the
file exactly; SPL size against `tools/spl_size_limit`; `0xA2`-partition-type path present in
the SPL (assert on the resolved `.config` **and** on `nm`, not on the defconfig).

**Environment parity.** Extract the raw `default_environment[]` symbol (locate with
`nm -S u-boot`, read `u-boot.bin` at `addr - CONFIG_TEXT_BASE`) — **not**
`u-boot-initial-env`, which is sorted and can be stale. Compare **entry by entry**, not with
`cmp`: the two `itest` rewrites add 9 bytes each, so the blob is 1,168 B where stock's is
1,150 B. A plain `cmp` is achievable only by emitting literal `mt` text that mainline cannot
execute — that trade is rejected.

**Allowed diffs** (enumerate, explain individually, or fail): version string and build
timestamp; uImage `ih_ep` `0x01000040` vs `0x00000000` (§3.3 — with the mixing hazard
documented); the two `fpgacheck` entries rewritten `mt`→`itest`; total size; code layout.

**Forbidden diffs:** any other environment entry differing in name, value or order; a
missing command from stock's 69-entry table; any layout/offset change; a load-address
change; any SPL header field change; `USE_SECTOR` reappearing.

Reconcile one doc nit while here: boot-chain §3.1 says the env blob is "20 entries, 1,149
bytes"; direct extraction gives **21 entries, 1,150 bytes** (`0x28018–0x28495` inclusive is
`0x47E` = 1,150; the ELF symbol is 1,151). Byte-identity was never in doubt — the constant
is.

---

## 7. Explicitly out of scope

* Shipping this to users, in any channel, in any release, under any flag (ADR 0017 §Decision-5).
* Porting the *fork* to a modern toolchain. Worth recording that it does work — the 2017.03
  tree builds clean under gcc 14.4 with **zero patches**, and its env blob, appended DTB and
  69-command table are **byte-identical** to the shipped 2025 binary — which also settles
  boot-chain §10's open question: **`MiSTer_defconfig` is what built the stock blob**
  (`socfpga_de10_nano_defconfig` does not even compile at `8dcc3484`). That remains the
  fallback if mainline stalls.
* Byte-identical reproduction of the stock blob (boot-chain §3.2; doubly moot for mainline).
* The full SD-card image (P5.3) and mr-fusion payload parity — unaffected.

---

## 8. Risks, recovery, and the gate

**"Brick" here always means "the SD card is wrong", never "the board is dead."** Verified:
the DE10-Nano has no HPS-attached flash (`nand@ff900000` and `spi@ff705000` are
`status = "disabled"` in `work/stock.dts:742-770`; the EPCS128 is FPGA-AS-only), and nothing
in `arch/arm/mach-socfpga/` programs fuses. **Recovery is: put the card in another machine
and rewrite it.**

**Failure taxonomy** (deterministic from `arch/arm/mach-socfpga/spl.c:81-176`; first possible
serial output is `preloader_console_init()` at `:157`):

| Symptom | Cause |
|---|---|
| No serial output at all | failure at/before pinmux, bad socfpga header/CRC, or wrong partition type |
| SPL banner + named DDR error | calibration — i.e. the QTS handoff |
| SPL banner then silence | U-Boot proper not loaded (deltas #1/#2), or the `ih_ep`/`ih_load` mismatch of §3.3 |
| U-Boot prompt, no boot | environment (delta #5) |
| Boots, but cores misbehave | `FPGAPORTRST` / s2f clocks / pinmux (§3.2) — **the dangerous one, it looks like success** |
| Cold boot fine, warm reboot dead | the `bridge enable` divergence (§3.3) — **invisible to a cold-boot smoke test** |

**The gate, in order.** Nothing is flashed until all of it is done:

1. Steps 1–4 green in CI, `docs/verification/uboot-mainline.md` complete.
2. **Measure the real card's `0xA2` partition size** (`sfdisk -l /dev/mmcblk0` on the test
   MiSTer at `192.168.0.161`) and confirm it exceeds the built image.
3. **Free de-risking step:** smoke-test the `itest`-rewritten `fpgacheck` on hardware under
   the **stock** bootloader via `u-boot.txt` (§3.4 — the primitive exists in both). This
   validates the single largest env rewrite with zero brick exposure.
4. A **second SD card** known-good and a written, *drilled* recovery procedure — recovery
   performed once from an actually-bricked state before any first-class use.
5. Serial console attached for the first boot. Test matrix: cold boot to menu; `u-boot.txt`
   override honoured; **warm-reboot core handoff** (load a core → Main_MiSTer warm-reboots →
   fabric still live); an `updateboot` flash + env-wipe cycle leaving the board bootable.

---

## 9. Open questions

1. **Nothing has been run on a DE10-Nano.** Every claim above is source-level or
   build-artifact-level. "It boots" is a per-build claim, exactly like the RT kernel pin.
2. **The warm-reboot bridge fix (§3.3): carried C patch (`d6010efe50`) or `bridge enable` in
   `fpgacheck`'s middle branch?** The env route keeps the delta out of C but was assessed as
   *not equivalent*. Decide explicitly and write it down — a cold-boot test cannot catch this.
3. **Does the `GENERALIO3`/`GENERALIO4` pinmux difference actually break anything?** And is
   `FPGAPORTRST=0x3FFF` genuinely required, or merely what MiSTer's Quartus project emitted?
   Both are unverified on hardware and must not be reported either way.
4. **What size `0xA2` partition do mr-fusion and the Windows SD installer create?** Ours is
   4 MiB; the in-the-wild value is unknown and `updateboot` `dd`s with no size check.
5. **Does mainline's exFAT driver handle the variant `mkfs.exfat -L MiSTer_Data` produces**
   (ADR 0020 §2), including `ATTR_SYSTEM` handling?
6. **Does `bootz` on a raw self-decompressing zImage consult `CONFIG_SYS_BOOTM_LEN`?** It
   dropped from 64 MiB (fork) to 8 MiB (mainline); `zImage_dtb` is ~7 MB and growing toward
   the 16 MB budget of boot-chain §7.3. Set it to `0x4000000` and move on, but confirm.
7. **Will upstream take the two fixes?** Both are real mainline bugs. Landing them removes
   two carried patches from the highest-blast-radius component.
8. **Renovate:** with `LATEST_VERSION=y` there is no version string to track — does the pin
   ride the Buildroot bump, or does it need its own manager plus a "re-verify deltas #1/#2"
   gate?
