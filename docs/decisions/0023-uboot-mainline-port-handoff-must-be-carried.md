# ADR 0023 — A mainline U-Boot port is viable, but its QTS handoff must be carried from the MiSTer fork, never taken from upstream (amends ADR 0017)

**Status:** Proposed (2026-07-25) — evidence only. The port go/no-go is a human
decision and is **not** taken here; ADR 0017's sequencing (build the fork from
source first) stands either way. See §4.
**Amends:** ADR 0017 (whose decisions 2–5 stand as written — this ADR revises the
*cost estimate* behind decision 1 and adds a hard constraint that binds any future
port; see §4.1)
**Impact:** `docs/boot-chain.md` (§2 gains a handoff subsection); TASKS P5.1/P5.2
(the parity harness gains a check that is **not** port-specific — it applies to the
fork-from-source build too); PLAN §13 (the "2017.03 under a 2026 toolchain" risk is
joined by a second, sharper one). **No effect on Phases 1–4** and none on the default
release channel, which keeps shipping the stock `uboot.img` byte-identical (P4.4).

## 1. What ADR 0017 got right, and the one input that has changed

ADR 0017 abandoned the mainline port on the grounds that it meant "re-implementations
of everything the fork added … in the single highest-blast-radius component of the
system." That risk framing was and is correct. The **cost** estimate underneath it was
not, in both directions, and both errors are worth recording because they point
opposite ways:

* **The port is smaller than the ADR assumed.** Almost everything ADR 0017 lists as
  needing re-implementation — `u-boot.txt` env-from-FAT, `fpgaload`/`fpgacheck`, the
  warm-reboot mailbox handshake, the pi-top GPIO quirk — is **U-Boot environment
  script text, not code** (`docs/boot-chain.md` §4 quotes all of it verbatim). The
  only genuinely missing C is the `mt` command.
* **One part of the port is *harder* than the ADR assumed, and it is the part nobody
  would have checked.** Mainline has had a DE10-Nano board port for years, which reads
  like the risky DDR/pinmux/PLL work is already done upstream. It is not. Upstream's
  handoff is **Terasic's golden-reference configuration**; MiSTer's is a different one,
  and the difference is load-bearing. §3 proves this from the shipped binary.

## 2. Evidence A — what mainline actually provides

Checked 2026-07-25 against `u-boot/u-boot@master` (`VERSION = 2026`,
`PATCHLEVEL = 07`):

| Piece the port needs | Upstream status |
|---|---|
| Board target | `configs/socfpga_de10_nano_defconfig`, `CONFIG_TARGET_SOCFPGA_TERASIC_DE10_NANO=y` |
| `uboot.img` layout (4×64 KiB SPL + uImage) | `u-boot-with-spl.sfp` target still present, now via `spl/u-boot-splx4.sfp` |
| 64 KiB SPL padding | `CONFIG_SPL_PAD_TO=0x10000` in that defconfig |
| SPL → U-Boot handoff contract | `SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION_TYPE` still `default 0xa2` (`arch/arm/mach-socfpga/Kconfig`) — `docs/boot-chain.md` §2.1's contract is upstream's default, not a fork behaviour |
| `bridge enable` | `U_BOOT_CMD(bridge, …)`, `arch/arm/mach-socfpga/misc.c` — GEN5 socfpga |
| `fpga load`, `env import -t`, `setexpr.l`, `mw`, `load mmc` | standard |
| `mt` (used by `fpgacheck`) | **absent** — no `do_mem_mt` in `cmd/mem.c`. `docs/boot-chain.md` §3.3 remains accurate |
| QTS handoff headers | `board/terasic/de10-nano/qts/*.h` present — **at the same path the fork uses, with different contents.** See §3 |

Buildroot 2026.05.1 (`boot/uboot/`) covers the wiring, including two options the
2017.03 fork can never use:

* `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE` — supplies the **entire** default environment
  from a checked-in text file. **Requires U-Boot ≥ 2018.05.** Under this option the 20
  entries of `docs/boot-chain.md` §3.1 become a reviewable, diffable file instead of a
  patched `include/configs/` header.
* `BR2_TARGET_UBOOT_ALTERA_SOCFPGA_IMAGE_CRC` — runs `mkpimage` for this exact SoC
  family. **Not what we want**, though: it emits a `.crc` file, whereas the MiSTer
  contract needs `u-boot-with-spl.sfp`, which U-Boot's own Makefile already produces.
  The correct wiring is `BR2_TARGET_UBOOT_FORMAT_CUSTOM` +
  `BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME="u-boot-with-spl.sfp"`.

## 3. Evidence B — the handoff is **not** interchangeable

The QTS handoff is not code. It is constant tables that Quartus emits and the SPL
writes to registers verbatim, which makes it directly verifiable in a binary with no
disassembler: generate the expected byte sequence from the source headers and search
for it in the SPL image.

Done against the shipped artifact — `uboot.img`, sha256
`e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64` (the value
`docs/boot-chain.md` §3.2 pins), SPL copy 0 = bytes `0x00000`–`0x0FFFF`:

| Table | MiSTer fork bytes | Mainline bytes |
|---|---|---|
| `sys_mgr_init_table` (pinmux, `const u8[207]`) | **FOUND @ `0x0AAC8`** | **not found** |
| `iocsr_scan_chain0_table` (24 × u32) | **FOUND @ `0x096B8`** | **not found** |
| `iocsr_scan_chain1_table` (54 × u32) | **FOUND @ `0x09718`** | **not found** |
| `iocsr_scan_chain2_table` (30 × u32) | **FOUND @ `0x097F0`** | **not found** |
| `iocsr_scan_chain3_table` (524 × u32) | FOUND @ `0x09868` | FOUND — tables are identical |
| `ac_rom_init` (36 × u32) | FOUND @ `0x090F8` | FOUND — identical |
| `inst_rom_init` (127 × u32) | FOUND @ `0x094BC` | FOUND — identical |

**The shipped SPL provably carries the MiSTer fork's handoff and not upstream's.**

### 3.1 The divergences, itemised

Source-level, `MiSTer-devel/u-boot_MiSTer@8dcc3484` vs `u-boot@master`, after
normalising U-Boot's global `CONFIG_HPS_*` → `CFG_HPS_*` rename (which accounted for
every apparent "missing" define — the two header sets have identical define *counts*:
5, 1, 69 and 158):

| File | Divergence |
|---|---|
| `pinmux_config.h` | 3 of 207 entries: `GENERALIO3` (idx 35), `GENERALIO4` (idx 36), `I2C3USEFPGA` (idx 201) — fork `0`, mainline `1` |
| `iocsr_config.h` | chain0: 12 differing words; chain1: 18; chain2: 2; chain3: identical. IO buffer configuration (drive strength, slew, termination) |
| `pll_config.h` | `CFG_HPS_PERPLLGRP_S2FUSER1CLK_CNT` fork `511` / mainline `19`; `CFG_HPS_SDRPLLGRP_S2FUSER2CLK_CNT` fork `4` / mainline `5`. Both FPGA-facing user clocks |
| `sdram_config.h` | `CFG_HPS_SDR_CTRLCFG_FPGAPORTRST` fork **`0x3FFF`** / mainline **`0x1FF`**; `REG_FILE_INIT_SEQ_SIGNATURE` fork `0x555504a0` / mainline `0x555504a1` |

`FPGAPORTRST` is the one that matters most for this project: it is the f2sdram port
reset/enable mask, and the fork brings **14** bits out of reset where upstream brings
**9**. Cores reaching the HPS DDR3 through those ports are exactly the workload MiSTer
exists to run. `REG_FILE_INIT_SEQ_SIGNATURE` differing is the expected downstream
consequence of the rest, not an independent finding.

`ac_rom_init` / `inst_rom_init` being byte-identical is a genuinely useful separate
signal: the DDR calibration **sequencer microcode** has not diverged between the two
trees, only the data fed to it.

### 3.2 What this evidence does *not* establish

Stated plainly, because the strength of §3 makes it easy to over-read:

* **Scalar `#define`s are not directly proven from the binary.** The PLL counts and
  SDRAM `ctrlcfg` fields are compiled into instruction immediates and computed values,
  not greppable tables. They rest on the source-level diff plus the fact that the blob
  is now *doubly* pinned to the fork source: `docs/boot-chain.md` §3.1's env-blob
  fingerprint, and now these tables.
* **Identical inputs to different code is still a risk.** This proves what the tables
  contain, not that a 2026 SPL consuming them behaves as a 2017.03 SPL did. The gen5
  DDR calibration path has had nine years of upstream change. The risk is far narrower
  than "unknown DDR configuration" — it is not zero.
* **Nothing here is hardware-verified.** No board has booted a from-source SPL of
  either vintage. `docs/boot-chain.md` §6.3's warm-reboot-mailbox assumption (DRAM at
  `0x1FFFF000` surviving the reset window, and the SPL not scribbling on it) remains
  source-asserted, and a modern SPL with a different stack/relocation layout is
  precisely the kind of change that could break it **silently** — cores would still
  boot; "reboot into a different core" would quietly regress to always-menu.

## 4. Decision

1. **ADR 0017's decision 1 is amended from "the mainline port is abandoned" to "the
   mainline port is not the first step, and is no longer ruled out."** Its risk
   argument stands; its cost estimate is superseded by §2 and §3.

2. **Hard constraint on any future port — the load-bearing clause of this ADR.** A
   mainline-based build **MUST** carry MiSTer's four `board/terasic/de10-nano/qts/*.h`
   (~26 KB) and **MUST NOT** use upstream's DE10-Nano handoff, with or without local
   edits. Upstream and MiSTer occupy the *same path* with *different contents*, so this
   is a silent-adoption hazard, not a merge conflict: a port that simply builds
   `socfpga_de10_nano_defconfig` inherits Terasic's f2sdram port mask and FPGA user
   clocks and will still appear to boot.

3. **Add a handoff-equality gate to P5.2, applicable to *both* candidate trees.**
   Rebuild the SPL, extract the tables of §3, and assert byte-equality against the
   stock SPL's. This needs no hardware and no board, and it catches the entire class of
   "the build silently picked up the wrong handoff" — the failure mode most likely to
   brick a board — before anything is flashed. Roughly 60 lines
   (`scripts/check-uboot-handoff.sh`); §6 records the method so it survives this ADR.
   This is **not** port-specific: it is a correctness check on the fork-from-source
   build of P5.1 too, where it also serves as the first real proof that the build
   reproduces the shipped configuration.

4. **Sequencing is unchanged from ADR 0017: P5.1/P5.2 first.** Build the fork from
   source, establish the Buildroot wiring and the behavioural-parity harness against a
   tree already known to match the shipped blob. Only then consider re-pointing the
   source at mainline and re-running the same harness. The harness is the reusable
   asset; building it against a known-good tree means a red result means "the port is
   wrong", not "the harness is wrong".

5. **Three named traps any port must handle**, recorded here so they are not
   rediscovered:
   * **`CONFIG_ENV_IS_NOWHERE`, not `ENV_IS_IN_MMC`.** Mainline's defconfig sets
     `CONFIG_ENV_IS_IN_MMC=y` with `CONFIG_ENV_OFFSET=0x4400`. `updateboot` only wipes
     sector 1 (`docs/boot-chain.md` §5, Consequence (b)), so a mainline build would
     **silently gain a persistent saved environment**, breaking the documented
     invariant that the effective environment is always `defaults + u-boot.txt`.
   * **`mt`.** Carry the ~25-line command rather than rewriting `fpgacheck` with
     `setexpr`+`test`, so the environment text stays directly diffable against the
     stock blob's — which is what makes §3-style verification cheap.
   * **The default environment belongs in a text file**, via
     `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE`, not a patched header.

6. **Not decided here:** whether to do the port at all. That remains a human go/no-go,
   and nothing in Phases 1–4 depends on it.

### 4.1 Relationship to ADR 0017's other decisions

Decisions 2 (submodule pin at `8dcc3484`), 3 (behavioural parity, not byte identity),
4 (the full SD-card image) and 5 (default channel untouched; from-source build opt-in
behind a flag) are **unaffected**. Decision 3 in particular is reinforced: §3 is a
concrete, automatable instance of exactly the behavioural-parity validation it asks
for.

## 5. Alternatives considered

* **Leave ADR 0017 alone and record nothing.** Rejected: the handoff divergence is a
  live hazard for anyone who reads "mainline has a DE10-Nano board port" and concludes
  the hard part is done. That inference is natural, wrong, and would be discovered on
  hardware.
* **Reverse ADR 0017 outright and adopt the mainline port now.** Rejected: the evidence
  narrows the port's risk, it does not eliminate it (§3.2), and none of it is
  hardware-verified. Reversing a decision on the strength of a static analysis, in the
  component where a mistake needs a card reader to undo, would be exactly the mistake
  ADR 0017 was written to prevent.
* **Regenerate the handoff from the MiSTer Quartus project rather than carrying the
  fork's headers.** Rejected for now: `arch/arm/mach-socfpga/qts-filter.sh` can do it,
  but it introduces a Quartus dependency into the build for output we can copy and then
  *verify against the shipped binary* — the copy is the more checkable path. This
  becomes necessary only if the MiSTer FPGA project's HPS configuration ever changes,
  which would invalidate the carried headers.

## 6. Reproducing the evidence

Method, so this ADR is checkable without re-deriving it:

1. Take SPL copy 0: the first `0x10000` bytes of `uboot.img` (`docs/boot-chain.md` §2 —
   all four copies are byte-identical).
2. Parse the `{…}` initialisers out of each `qts/*.h`. Pack `iocsr_scan_chain*_table`,
   `ac_rom_init` and `inst_rom_init` as **little-endian u32**; `sys_mgr_init_table` is
   `const u8[]` and packs as **raw bytes** (packing it as u32 is why it appears absent
   in a naive first pass).
3. Search the SPL for each byte string. Normalise `CONFIG_HPS_*` → `CFG_HPS_*` before
   comparing define names across the two trees, or the rename swamps the real diff.

Sources: `MiSTer-devel/u-boot_MiSTer@8dcc3484aac6f07314538e82530d446083085e12`,
`u-boot/u-boot@master` (2026-07, `VERSION = 2026 / PATCHLEVEL = 07`), and the pinned
stock `uboot.img` fetched by hash per `scripts/fetch-sdcard-payload.sh`.

## 7. Consequences

- Any P5 work — fork or mainline — inherits the handoff gate of §4 decision 3. It is
  cheap and should land with P5.1, not wait for a port that may never happen.
- `docs/boot-chain.md` §2 should gain a subsection recording that the handoff tables
  are extractable and where they sit in the SPL; that document's §3.3 note that `mt` is
  not upstream is re-confirmed as of 2026-07 and needs no change.
- PLAN §13 gains a risk: **"a mainline port silently adopts Terasic's handoff."**
  Mitigated by §4 decisions 2 (the constraint) and 3 (the gate), not by review
  discipline.
- If the port is ever taken, `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE` becomes available and
  the environment stops being carried as a source patch. That is a real maintainability
  gain and is the strongest non-security argument for the port.
- ADR 0017's header is annotated to point here, following the ADR 0010 → 0019
  precedent.
