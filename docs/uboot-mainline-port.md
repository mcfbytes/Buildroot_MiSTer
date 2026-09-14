# Plan — a modern mainline U-Boot for the DE10-Nano, built from source as a capability artifact

**Status:** proposed (2026-07-28). **Supersedes in part:** [ADR 0017](decisions/0017-uboot-from-mister-fork-full-sd-image.md)
§Decision-1 (which chose the 2017.03 fork and rejected the mainline port).
**Requires a new ADR:** 0024 (0023 is the highest in `docs/decisions/`).
**Specification being reproduced:** [`docs/boot-chain.md`](boot-chain.md) — cited by section
throughout; nothing from it is restated here.

> **Revision 2026-09-14.** Three things changed since this plan was written, none of them
> the verdict. (1) **The pin is 2026.07, not 2026.04:** Buildroot 2026.08 (the repo's pin)
> bundles U-Boot 2026.07 with its own hash line, so `BR2_TARGET_UBOOT_LATEST_VERSION=y` now
> resolves there — the same tarball the DE25-Nano already builds. Deltas #1–#4 were re-checked
> in the 2026.07 tarball on 2026-09-14: the missing raw-mode line, the dead `TARGET_SOCFPGA_GEN5`
> guard (`board.c:214-215`), the 64-bit `/` and `%` in `fs/exfat/time.c:129,147-148`, and
> `FPGAPORTRST=0x1FF` are all still there. (2) **The owner decided the open questions by one
> rule — mirror stock** (§9, items 2 and 3, and the `mt` question in §3.4): the warm-reboot
> bridge behaviour is carried as the fork's C change, the fork's QTS values are carried
> unmodified, and `mt` is carried as a command so the environment text is byte-identical to
> stock's. (3) **§3.2a and §6 fold in the never-merged ADR 0023 draft** (branch
> `docs/adr-0023-uboot-mainline-handoff`, commit `491c0d9`, 2026-07-25; its number was reused by
> the 7-Zip ADR and the branch was deleted on 2026-09-14): the binary-level proof that the
> shipped SPL carries the fork's handoff, and the no-hardware handoff-equality gate that proof
> makes possible. Execution: [`docs/uboot-tasks.md`](uboot-tasks.md).

---

## 1. What this is, and what it is not

Build **mainline U-Boot 2026.07** (2026.04 when first written; see the revision note) for the MiSTer, configured to behave as close to
identically to the stock 2017.03 fork as the evidence allows, as a **build artifact only**.

**Not changing, and gated so it stays that way:**

* The default release channel keeps shipping the **stock `uboot.img` byte-identical**
  (515,141 B, sha256 `e2d46cf9…62ba64`), fetched by hash. ADR 0017 §Decision-5 stands.
* `sdcard.img` keeps embedding that same stock blob. `scripts/mk-sdcard.sh` and
  `scripts/check-sdcard.sh` are untouched.
* `configs/mister_de10nano_defconfig` gains **no** `BR2_TARGET_UBOOT*` line.
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

### 3.2a The shipped SPL provably carries the fork's handoff — binary evidence

*Folded in from the ADR 0023 draft (2026-07-25); reproduced there against the pinned stock
`uboot.img`, sha256 `e2d46cf9…62a64`, SPL copy 0 = bytes `0x00000`–`0x0FFFF`.*

§3.2 is a source-level diff. It leaves one inference open: that the stock binary was built
from the fork's headers rather than from something else at the same path. The handoff is
constant tables the SPL writes to registers verbatim, so that inference is directly
checkable with no disassembler — pack each `qts/*.h` initialiser and search the SPL bytes:

| Table | Fork bytes | Mainline bytes |
|---|---|---|
| `sys_mgr_init_table` (pinmux, `const u8[207]`) | **found @ `0x0AAC8`** | not found |
| `iocsr_scan_chain0_table` (24 × u32) | **found @ `0x096B8`** | not found |
| `iocsr_scan_chain1_table` (54 × u32) | **found @ `0x09718`** | not found |
| `iocsr_scan_chain2_table` (30 × u32) | **found @ `0x097F0`** | not found |
| `iocsr_scan_chain3_table` (524 × u32) | found @ `0x09868` | found — identical tables |
| `ac_rom_init` (36 × u32) | found @ `0x090F8` | found — identical |
| `inst_rom_init` (127 × u32) | found @ `0x094BC` | found — identical |

Method, so this stays checkable: parse the `{…}` initialisers out of each header; pack the
`iocsr_scan_chain*_table`, `ac_rom_init` and `inst_rom_init` arrays as **little-endian u32**;
pack `sys_mgr_init_table` as **raw bytes** (it is `const u8[]` — packing it as u32 is why it
appears absent on a naive first pass); search SPL copy 0 for each byte string. Normalise
`CONFIG_HPS_*` → `CFG_HPS_*` before comparing define *names* across the two trees.

What this does and does not establish, stated plainly:

* It **proves** the four divergent tables in the shipped SPL are the fork's, which pins the
  blob to the fork source a second, independent way (the first is boot-chain §3.1's env-blob
  fingerprint). It also proves the DDR sequencer microcode has not diverged — only the data
  fed to it.
* It **does not** prove the scalar `#define`s (the PLL counts, `FPGAPORTRST`): those compile
  to instruction immediates and are not greppable. They rest on the source diff plus the
  double pin above.
* It **does not** prove that a 2026 SPL consuming the same tables behaves as the 2017.03 SPL
  did. The gen5 calibration path has nine years of upstream change; the risk is far narrower
  than "unknown DDR configuration", not zero. Hardware only.

The payoff is §6's **handoff-equality gate**: the same search run against *our* built SPL
catches the whole class of "the build silently picked up the wrong `qts/*.h`" — the failure
mode most likely to look like success on a board — with no hardware at all. That is the one
delta of §3.1 whose omission a cold-boot smoke test could not catch.

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

> **Decided 2026-09-14 (mirror stock; amends ADR 0024 §Decision 5):** carry the fork's `mt`
> command instead of rewriting `fpgacheck`. It is 23 lines of C in `cmd/mem.c` (fork
> `8dcc3484`, `do_mem_mt` + one `U_BOOT_CMD`; port is `cmd_tbl_t` → `struct cmd_tbl`), it
> never leaves the tree, and with it the environment text is **byte-identical to stock's**
> (21 entries, 1,150 B), so §6's environment check becomes a plain `cmp` instead of an
> allowed-delta list. The `itest` rewrite below stays documented for two reasons: it is the
> fallback if `mt` ever fails to port, and it is the free stock-hardware smoke test in §8.

Stock's `fpgacheck` uses `mt`, a MiSTer-only command (boot-chain §3.3). The alternative is
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
  `CUSTOM_*`). Under Buildroot 2026.05.1 it resolved to 2026.04 (sha256 `ac7c04b8…f2fd`,
  confirmed byte-identical to `boot/uboot/uboot.hash`); under the repo's current Buildroot
  2026.08 it resolves to **2026.07** (`Config.in:88`, sha256 `78e8bfc3…243e` — the same line
  `board/mister/de25nano/patches/uboot/uboot.hash` carries, GPG-verified against the release
  signature). This matches the repo's hash-pinning convention for free.
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
  mechanism `make linux-rt` uses**, and therefore **the same hazard**: dropped symbols only warn.
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

**Source.** Mainline U-Boot **2026.07** via `BR2_TARGET_UBOOT_LATEST_VERSION=y` — hash-verified
by Buildroot, no submodule, no vendored tree, standing rule 1 satisfied trivially, and the
same tarball the DE25-Nano builds.
**The pin rides the Buildroot bump, and every bump re-opens deltas #1 and #2:** #1 is a
Kconfig `choice` whose default can flip with no diff in our files, and #2 is a carried patch
against a known line. That is why the resolved-`.config` assertion and the handoff gate of
§6 run in the build recipe, not in a checklist: a Buildroot bump that moves U-Boot fails the
build loudly instead of shipping a silently different bootloader.

**Layering**, mirroring the DE25-Nano's U-Boot wiring (post-ADR 0030 layout; the original
table named a separate `configs/mister_uboot_defconfig` + `output-uboot/`, which predates the
committed-defconfig layout — see `docs/uboot-tasks.md` U1 for the placement decision):

| Layer | File | Contents |
|---|---|---|
| Buildroot config | `BR2_TARGET_UBOOT*` lines in the DE10 defconfig (U1 decides which one) | source pin, board defconfig, fragment, env file, `FORMAT_CUSTOM` name |
| U-Boot config | `board/mister/de10nano/uboot.fragment` | the `CONFIG_*` deltas of §3.1/§3.3, headed like `board/mister/de25nano/uboot.fragment` |
| Environment | `board/mister/de10nano/uboot.env` | stock's 21 entries as text, byte-identical (via `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE`) |
| Patches | `board/mister/de10nano/patches/uboot/` | via `BR2_GLOBAL_PATCH_DIR`, exactly as the kernel's `patches/linux/` — the two upstream fixes, the QTS headers, `mt`, the bridge behaviour |

**Output artifact:** `images/u-boot-with-spl.sfp`. Never `uboot.img` (§1).

**Patches carried** — each needs a CONTRIBUTING.md provenance header, using
`board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch` as the template:

1. `0001-arm-socfpga-fix-dead-raw-sector-hook-guard.patch` — the `TARGET_`→`ARCH_` guard
   (§3.1 #2). **Upstream this.**
2. `0002-fs-exfat-fix-64-bit-division-on-32-bit-arm.patch` — `do_div()` in `fs/exfat/time.c`
   (§3.1 #3). **Upstream this.**
3. `0003-board-terasic-de10-nano-mister-qts-handoff.patch` — the four QTS headers (§3.2),
   **the fork's values unmodified** (`FPGAPORTRST=0x3FFF`, both s2f clock counts, the three
   pinmux bits, all 32 IOCSR words — decided 2026-09-14, mirror stock). Never upstreamable;
   MiSTer is a different FPGA design on the same board. Gated by §6's handoff check.
4. `0004-cmd-mem-add-mt-memory-test-against-value.patch` — the fork's `mt` (§3.4). Provenance:
   fork commit that introduced `do_mem_mt` (find it with `git log -S do_mem_mt` in
   `work/U-Boot_MiSTer`).
5. `0005-arm-socfpga-gen5-release-bridges-after-reset-if-fpga-in-user-mode.patch` — the fork's
   `d6010efe50` (Sorgelig, 2017-03-27, one line: `socfpga_bridges_reset(0)` at the end of
   `arch_early_init_r`) re-expressed against mainline's `misc_gen5.c:185-210`, whose
   `arch_early_init_r` ends in `socfpga_bridges_reset(1)`. **Decided 2026-09-14: carried as C,
   mirror stock** — the env-script route was assessed as not equivalent (§3.3). The porting
   agent must diff the fork's `socfpga_bridges_reset(0)` body (its user-mode test and which
   bridges it releases) against mainline's `do_bridge_reset(1, mask)` and carry the *behaviour*,
   not the line.

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
`u-boot-initial-env`, which is sorted and can be stale. With `mt` carried (§3.4, decided
2026-09-14) the blob must be **byte-identical to stock's** (21 entries, 1,150 B): a plain
`cmp` against the blob extracted from the stock `uboot.img` at `0x28018`, and an entry-by-entry
report only as the diagnostic when `cmp` fails. *(Original design, kept for the fallback: with
the `itest` rewrite the blob is 1,168 B and the comparison is entry-by-entry against an
allowed-delta list of exactly the two `fpgacheck` entries.)*

**Handoff equality** (folded in from the ADR 0023 draft, §3.2a): extract SPL copy 0 from the
built `.sfp` and from the stock `uboot.img`; pack the seven tables of §3.2a from the carried
`qts/*.h` and assert every one is found in **both** SPLs. The offsets may differ (code layout);
presence and byte-equality may not. This needs no hardware and catches the one silent-brick
delta a cold-boot test cannot. The stock blob is fetched by hash the way `release.yml` already
does (`scripts/fetch-sdcard-payload.sh`, `STOCK_UBOOT_SHA256`).

**Command table.** Every one of stock's 69 commands present (boot-chain §3.3's list, `mt`
included); extra mainline commands are allowed and listed.

**Allowed diffs** (enumerate, explain individually, or fail): version string and build
timestamp; uImage `ih_ep` `0x01000040` vs `0x00000000` (§3.3 — with the mixing hazard
documented); total size; code layout; table offsets inside the SPL.

**Forbidden diffs:** any environment byte; a missing command from stock's 69-entry table;
any handoff table absent from or differing in the built SPL; any layout/offset change of
the four SPL copies or the uImage; a load-address change; any SPL header field change;
`USE_SECTOR` reappearing.

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
2. ~~**The warm-reboot bridge fix (§3.3): carried C patch (`d6010efe50`) or `bridge enable` in
   `fpgacheck`'s middle branch?**~~ **Decided 2026-09-14 by the owner: carried C patch, mirror
   stock** (§4 patch 5). The env route was assessed as not equivalent, and a cold-boot test
   cannot catch getting this wrong.
3. ~~**Does the `GENERALIO3`/`GENERALIO4` pinmux difference actually break anything?** And is
   `FPGAPORTRST=0x3FFF` genuinely required?~~ **Decided 2026-09-14 by the owner: carry the
   fork's values unmodified, mirror stock** (§4 patch 3). Whether either is *required* stays
   unverified and must not be reported either way; it no longer affects execution.
4. **What size `0xA2` partition do mr-fusion and the Windows SD installer create?** Ours is
   4 MiB; the in-the-wild value is unknown and `updateboot` `dd`s with no size check.
5. **Does mainline's exFAT driver handle the variant `mkfs.exfat -L MiSTer_Data` produces**
   (ADR 0020 §2), including `ATTR_SYSTEM` handling?
6. **Does `bootz` on a raw self-decompressing zImage consult `CONFIG_SYS_BOOTM_LEN`?** It
   dropped from 64 MiB (fork) to 8 MiB (mainline); `zImage_dtb` is ~7 MB and growing toward
   the 16 MB budget of boot-chain §7.3. Set it to `0x4000000` and move on, but confirm.
7. **Will upstream take the two fixes?** Both are real mainline bugs. Landing them removes
   two carried patches from the highest-blast-radius component.
8. ~~**Renovate:** with `LATEST_VERSION=y` there is no version string to track — does the pin
   ride the Buildroot bump, or does it need its own manager plus a "re-verify deltas #1/#2"
   gate?~~ **Answered 2026-09-14:** it rides the Buildroot bump (2026.08 already moved it to
   2026.07), and the "re-verify" gate is the U3 resolved-`.config` assertion plus the §6
   handoff check, both of which run inside the build. No separate manager.
9. **Should the DE10 U-Boot build live in the shipping `mister_de10nano_defconfig`** (one image,
   one CI build, the artifact built on every PR so it cannot rot; amends ADR 0024's "gains no
   `BR2_TARGET_UBOOT*` line") **or in its own defconfig and output tree** (isolated, manual CI
   lane, a second toolchain build)? Owner decision; `docs/uboot-tasks.md` U1 recommends the
   former.
