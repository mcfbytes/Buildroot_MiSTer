# ADR 0024 — The from-source U-Boot is built from **mainline**, not the 2017.03 fork, and exists as a non-shipping capability artifact (supersedes ADR 0017 §Decision 1–3)

**Status:** Accepted (2026-07-28) — decided by @mcfbytes
**Supersedes:** [ADR 0017](0017-uboot-from-mister-fork-full-sd-image.md) §Decision items
**1** (build the fork, not mainline), **2** (the `u-boot/` submodule pin), and **3**
(behavioural parity against the fork as the acceptance test). ADR 0017 §Decision **4**
(the full SD-card image) and §Decision **5** (the default channel ships the stock blob
byte-identical) **stand unchanged** — see §"What does not change".
**Impact:** new files `docs/uboot-mainline-port.md` (the plan), `docs/uboot-tasks.md`
(execution), and — when the plan is executed — `configs/mister_uboot_defconfig`,
`board/mister/de10nano/uboot-mister.fragment`,
`board/mister/de10nano/uboot-mister.env`, `board/mister/de10nano/uboot-patches/*`,
`scripts/check-uboot-parity.sh`, `.github/workflows/uboot.yml`,
`docs/verification/uboot-mainline.md`. `PLAN.md` §8 and `TASKS.md` P5.1/P5.2 are
**redirected, not rewritten** — the U-Boot narrative now lives in its own files.
**Relates to:** [`docs/boot-chain.md`](../boot-chain.md) (the specification being
reproduced), [ADR 0020](0020-sdcard-exfat-reformat-installer.md) (the exFAT data
partition, which turns out to be a hard requirement on the bootloader — see §Decision 4),
[CONTRIBUTING §1/§2](../../CONTRIBUTING.md) (no binaries in git; patch provenance).

## The problem

ADR 0017 chose to build the **MiSTer 2017.03 fork** from source and explicitly abandoned a
mainline port, on the reasoning that a mainline port meant "new code in the single
highest-blast-radius component of the system." That reasoning was sound about the
*shipping* decision. It rested, however, on an **unmeasured estimate** of the port surface:
0017 assumed re-implementing `u-boot.txt` env-from-FAT, `fpgaload`/`fpgacheck`, the
MiSTer-only `mt` command, the warm-reboot mailbox, and the pi-top GPIO quirk — "every one
of those re-implementations is new code."

Two things changed. First, the maintainer's requirement changed: the artifact wanted is a
**modern** bootloader, so that the project has a real path to a new one if it ever needs it
— not a from-source rebuild of a 2017 tree that would inherit nine years of unfixed
upstream. Second, the port surface has now been **measured** rather than estimated
(`docs/uboot-mainline-port.md` §3). It is materially smaller than 0017 assumed, and the
parts that are *not* smaller are not the parts 0017 worried about.

Measured, with mainline 2026.04: `u-boot.txt` env-from-FAT needs no code (`env import -t`
is unchanged, including the unsized-scan behaviour); `fpgaload` needs no code; the
warm-reboot mailbox needs no code; the pi-top `mw` needs no code; `mt` is replaced by
`itest.l *<addr> == <val>`, which was verified **by execution** in a real U-Boot sandbox
across all three warm-reboot dispatch cases — and which also exists in the stock 2017.03
binary, so it can be smoke-tested on hardware under the *current* bootloader before
anything is flashed.

What the measurement found instead were problems a fork build would never have surfaced,
including **two genuine upstream defects** in the very defconfig a naive port starts from.

## Decision

1. **Build mainline U-Boot, pinned at 2026.04, not the fork.** Source comes from
   `BR2_TARGET_UBOOT_LATEST_VERSION=y`, which is the only Buildroot source choice that
   **hash-verifies** the tarball (`work/buildroot/boot/uboot/uboot.mk:41-43`) and which
   resolves to exactly 2026.04 (`Config.in:88`). This satisfies CONTRIBUTING §1 and §3
   without a submodule, a vendored tree, or an override.

   **The pin is deliberate and must not float.** 2026.04 is the last release in which
   defect (b) below is a one-line fix in a known place, and the SPL raw-mode selector is a
   Kconfig `choice` whose default can change with no diff in our files. A U-Boot bump
   re-opens both and must re-assert them against the **resolved `.config`**.

2. **Drop the `u-boot/` submodule.** ADR 0017 §Decision 2's rationale (pin the exact commit
   the shipped blob was built from) is specific to reproducing the fork. It does not apply
   to a mainline build, and `UBOOT_OVERRIDE_SRCDIR` — the wiring 0017 specified — would
   have **silently skipped the patch step entirely** (`package/pkg-generic.mk:945`),
   disabling the `uboot-patches/` mechanism 0017 itself relied on. The ordinary
   tarball-plus-`BR2_TARGET_UBOOT_PATCH` flow (`boot/uboot/Config.in:103-113`,
   `uboot.mk:342-354`) is used instead.

3. **`board/mister/de10nano/uboot-patches/` may carry behaviour changes**, not just build
   fixes. ADR 0017 §Decision 3 restricted it to "build fixes only, never behaviour changes."
   That restriction was correct for a fork build, where the binary being reproduced was
   already proven and any behaviour delta would be a regression. It cannot survive a
   mainline port, whose entire purpose is to re-introduce MiSTer's behaviour into a tree
   that does not have it. Every patch still carries a full CONTRIBUTING §2 provenance
   header, and every one is enumerated in `docs/uboot-mainline-port.md` §4.

4. **Five deltas are mandatory; three are silent-brick if omitted.** Detail and evidence in
   `docs/uboot-mainline-port.md` §3.1. In summary:

   a. **SPL raw-mode selector.** Mainline dropped `ARCH_SOCFPGA`'s unconditional
      `select SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION`; `configs/socfpga_de10_nano_defconfig`
      sets no raw-mode line at all and falls through to **absolute LBA `0x400`**, ignoring
      the MBR and breaking the type-`0xA2` contract of boot-chain §2.1. Its sibling
      `socfpga_de0_nano_soc_defconfig:31` sets it correctly; this is a one-line omission.

   b. **A dead `+0x200` hook — upstream defect.** `board_spl_mmc_get_uboot_raw_sector()`
      (`arch/arm/mach-socfpga/board.c:216-221`) is guarded on `CONFIG_TARGET_SOCFPGA_GEN5`,
      but commit `62f7a94602` (2026-02-13) renamed the symbol to `ARCH_SOCFPGA_GEN5` and
      missed this guard. Confirmed still broken on `origin/main`. Without it, (a) alone
      loads from the *start* of the `0xA2` partition — SPL copy 0 — not U-Boot proper.
      Also silently affects Arria10. **To be sent upstream.**

   c. **exFAT — upstream defect.** Stock's U-Boot *reads exFAT* (the fork replaced the FAT
      driver with ChaN FatFs); mainline's `fs/fat/fat.c:68-95` rejects it. Since ADR 0020
      makes the data partition exFAT, a mainline U-Boot without this **cannot load
      `zImage_dtb` on our own SD image**. Mainline has `CONFIG_FS_EXFAT` but it does not
      link on 32-bit ARM (`__aeabi_ldivmod`, `fs/exfat/time.c:129,147-149`) — no 32-bit
      board in tree enables it. **To be sent upstream.**

   d. **The QTS handoff data.** MiSTer deliberately replaced Terasic's Quartus handoff with
      its own (`dadd1c8978`, 2017-04-01). Every DDR3 timing, geometry, ODT, PHY value, both
      sequencer ROMs and the DDR3 I/O scan chain (524/524 words) are **identical** to
      mainline's — the divergence is confined to the HPS↔FPGA interface (`FPGAPORTRST`
      `0x3FFF` vs `0x1FF`, two s2f clock dividers, three pinmux bits, 32 IOCSR words).
      Carried as board files; never upstreamable, because MiSTer is a different FPGA design
      on the same board.

   e. **The environment.** A stock-shaped default environment via
      `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE` (`env/Kconfig:771`). The built default env has
      43 entries and not one MiSTer variable — no `bootcmd`, no `bootargs` — and mainline's
      distro `mmc_boot` *collides* with stock's variable of the same name.

5. **Acceptance is structural parity plus an enumerated diff list, not byte identity and
   not a plain `cmp` of the environment.** ADR 0017 §Decision 3 expected the default-env
   blob to match stock's byte for byte. That is unachievable here and the trade is
   rejected: the two `itest` rewrites make the blob 1,168 B where stock's is 1,150 B, and
   the only way to make `cmp` pass would be to emit literal `mt` text that mainline cannot
   execute. `scripts/check-uboot-parity.sh` therefore compares **entry by entry** against an
   explicit allowed-delta list (`docs/uboot-mainline-port.md` §6).

6. **This artifact ships nowhere, and the gate is hardware plus a drilled recovery.**
   No release channel, no `release_*.7z`, no db.json, no `sdcard.img` default, no opt-in
   flag for users. It is a CI artifact until `docs/uboot-tasks.md` U6 is complete —
   which requires a measured `0xA2` partition size on a real card, a second known-good SD
   card, a recovery performed once from an actually-bricked state, and a test matrix that
   includes **warm-reboot core handoff** (a cold-boot smoke test cannot catch the
   `bridge enable` divergence).

## What does not change

* **The default release channel still ships the stock `uboot.img` byte-identical**
  (515,141 B, sha256 `e2d46cf9…62ba64`), fetched by hash. ADR 0017 §Decision 5 stands.
* **`sdcard.img` still embeds that same stock blob.** ADR 0017 §Decision 4 and ADR 0020
  stand; `scripts/mk-sdcard.sh` and `scripts/check-sdcard.sh` are untouched.
* `configs/mister_de10nano_defconfig` gains no `BR2_TARGET_UBOOT*` line.
* **No artifact produced by this work may be named `uboot.img`.** `updateboot` `dd`s
  `/media/fat/linux/uboot.img` over the `0xA2` partition on every Linux update with no
  version check, no hash check and no opt-out (boot-chain §5).

## Alternatives considered

- **Build the 2017.03 fork from source (ADR 0017's decision).** Still viable, and now
  *proven* viable: the fork compiles clean under gcc 14.4 with **zero patches**, and its
  env blob, appended DTB and 69-command table come out **byte-identical** to the shipped
  2025 binary. (That also settles boot-chain §10's open question: `MiSTer_defconfig` is what
  built the stock blob; `socfpga_de10_nano_defconfig` does not compile at `8dcc3484`.)
  Rejected as the primary path because it delivers a 2017 bootloader — the thing the
  maintainer explicitly does not want — and forgoes nine years of upstream fixes forever.
  **Retained as the documented fallback** if the mainline path stalls on hardware.
- **Mainline with no carried patches, accepting mainline's QTS data.** Rejected. It leaves
  five FPGA→SDRAM ports held in reset and the s2f clocks wrong; the failure mode is a board
  that *appears* to boot while cores misbehave, which is the worst kind.
- **Reproducing stock's env byte-for-byte by emitting literal `mt` text.** Rejected; see
  §Decision 5.
- **Floating the U-Boot version with Buildroot's default.** Rejected; see §Decision 1.

## Consequences

- ADR 0017 is annotated as superseded-in-part. It remains the record of why the fork was
  once the cheaper path, and its §Decision 4/5 are still live.
- `PLAN.md` §8 and `TASKS.md` P5.1/P5.2 are redirected to `docs/uboot-mainline-port.md` and
  `docs/uboot-tasks.md`. Those two files are already large; the U-Boot narrative is not
  added to them.
- The project takes on **two upstream patches it should try to shed** (§Decision 4b, 4c).
  Both are real mainline bugs; landing them removes carried patches from the
  highest-blast-radius component.
- A U-Boot version bump is no longer routine: it re-opens §Decision 4a/4b and requires
  re-asserting the resolved `.config`. `docs/uboot-tasks.md` U4 makes that a CI assertion
  rather than a convention.
- Choosing mainline removes a silent-corruption window that the fork has and cannot lose:
  2017.03's `tools/socfpgaimage.c:218-225` accepts an oversized SPL, prints "Not a sane
  SOCFPGA preloader", **exits 0**, and writes a truncated `length_u32`. Mainline enforces
  `SPL_SIZE_CHECK` at build time.
- Nothing in this ADR has been run on a DE10-Nano. Every claim is source-level or
  build-artifact-level. "It boots" remains a per-build claim, exactly like the RT kernel pin.
