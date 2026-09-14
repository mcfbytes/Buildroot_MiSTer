# U-Boot — desk plan and execution tasks, both boards

Execution contract for the from-source bootloaders. **Design and evidence live in
[`docs/uboot-mainline-port.md`](uboot-mainline-port.md) (DE10-Nano) and
[`docs/de25-uboot.md`](de25-uboot.md) (DE25-Nano); the decisions live in
[ADR 0024](decisions/0024-mainline-uboot-capability-artifact.md) and
[ADR 0029](decisions/0029-de25-implementation-path.md).** This file is only the ordered work.

Split out of `TASKS.md` deliberately: that file and `PLAN.md` are already large, and the
U-Boot narrative is self-contained. `TASKS.md` P5.1/P5.2 redirect here and carry no
U-Boot detail of their own. **P5.3 (`sdcard.img`) and P5.4 remain in `TASKS.md`** — they
are about the SD image, which keeps embedding the stock blob and is not affected by this
work. The DE25's card and kernel tracks stay in `docs/de25-nano-tasks.md`.

---

## The one-line summary

Build mainline U-Boot **2026.07** for the DE10-Nano so that it behaves **like stock's 2017.03
fork in every way the evidence can check**, as a build artifact that ships nowhere; finish the
DE25-Nano's `u-boot.itb` desk work; and do **all of it without a board.**

## The owner's direction (2026-09-14)

* **The DE10-Nano will very likely never ship a custom U-Boot.** Stock's works. The target is
  a from-source bootloader that is *as close as possible to what stock does*, kept buildable
  "just in case" and so that the whole image — bootloader included — exists from source.
* **Where the plan had a choice, mirror stock.** That decided the warm-reboot bridge behaviour
  (carry the fork's C change), the QTS scalars (carry the fork's values), and `mt` (carry the
  command, so the environment is byte-identical). `docs/uboot-mainline-port.md` §3.4, §4, §9.
* **No hardware session is planned for either board.** The DE10 hardware gate (U6) is deferred
  indefinitely, not waived; the DE25 board is on order with no date. Every task below is desk
  work with a desk-checkable acceptance test. Nothing below is allowed to say "verified on
  hardware".

## Conventions

Inherited verbatim from [`TASKS.md` §0](../TASKS.md): **[HAIKU]** mechanical work,
**[SONNET]** implementation, **[OPUS]** analysis and hard debugging; escalate one tier after two
failed acceptance runs; **[NET]** needs downloads; sizes S (< half day), M (a day-ish), L
(multi-day). Two additions used by the DE25 waves and here:

* **[FABLE]** — adversarial review only. Reads the artifact and the claims, tries to break
  them, never edits. Used where a wrong result would look like success on a board.
* **Fan-out** — tasks in the same wave share no inputs and run concurrently. A wave's
  integration task runs alone. Wave A is 13 agents; with the wave-B/C tails the whole plan
  is under the session's 15-agent workflow guideline if wave B waits for wave A.

Every patch carries a full CONTRIBUTING §2 provenance header, modelled on
`board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch`. Every claim a
task records is tagged **[V]** (observed in this build or read from source, with the path)
or **[U]** (unverified, missing input named) — the `docs/de25-uboot.md` discipline.

**Reference material already on disk** (outside the repo; do not commit any of it):
`work/U-Boot_MiSTer` = the fork at `8dcc3484`; `work/uboot-proper.bin` = stock's U-Boot proper
(252,933 B); the stock `uboot.img` is fetched by hash through
`scripts/fetch-sdcard-payload.sh` (`STOCK_UBOOT_SHA256`); `dl/uboot/u-boot-2026.07.tar.bz2` =
the pinned tarball; `/mnt/source/uboot-mainline/verify-qts/qtsdiff.py` = the QTS header
parser/differ; `/mnt/source/uboot-mainline/env-layout-parity/mister.env.txt` = a stock-env
text file that already built byte-identical; `/mnt/source/uboot-research/parity-check/*.py`
= Python reference implementations of the structural checks (SPL header, uImage, env scan,
command table). The Python is reference, not deliverable: repo scripts are POSIX `sh`
(`scripts/check-zimage-dtb.sh` house style), with one sanctioned exception named in U4b.

---

## Owner decisions needed before kickoff

Answer in one line each; silence takes the recommendation.

1. **Where does the DE10 U-Boot build live?** *(plan §9 item 9)*
   **Recommended: in `configs/mister_de10nano_defconfig`**, so there is one image, one CI
   build, and the artifact is built on every PR and cannot rot. Cost: ~2 minutes per CI build
   (host-openssl + U-Boot; the tarball rides the `dl/` cache). It amends ADR 0024's "gains no
   `BR2_TARGET_UBOOT*` line" bullet, which was written to keep the artifact out of the
   *release*, and `mk-release.sh` stages named files only, so nothing changes in what ships.
   Alternative: its own defconfig + `O=output-uboot` + a manual `workflow_dispatch` lane — a
   second toolchain build and a new Makefile target ADR 0030 just removed the like of.
2. **DE25: drop the custom U-Boot pin?** Buildroot 2026.08 bundles the same 2026.07 with a
   hash line, so `BR2_TARGET_UBOOT_CUSTOM_VERSION` + `patches/uboot/uboot.hash` are redundant.
   **Recommended: switch to `LATEST_VERSION=y`** so both boards share one pin that rides the
   Buildroot bump, guarded by DU2's resolved-config check (the reason the custom pin was chosen
   — "fail closed on a bump" — is then served by the check, not the pin). Alternative: keep the
   deliberate pin and its hash file. TF-A stays custom either way (Buildroot's latest is v2.12).
3. **`mt` carried, not rewritten** — decided by the mirror-stock rule; this is the veto point.
4. **Outbound mail.** U7 and DU5 *prepare* upstream submissions; nothing is sent to the U-Boot
   list without an explicit go.
5. **`docs/de25-uboot.md` §13 items 1–6** — DU4 lists a recommendation per item.

---

## DE10-Nano — the U-series

### Wave A — fan out (13 agents, no inter-dependencies)

- [x] **U0 — ADR + redirects** — DONE (ADR 0024 landed 2026-07-28; amended 2026-09-14 with the
  version drift, the mirror-stock decisions and the ADR 0023 fold-in).

- [ ] **U1 — Buildroot wiring** — [SONNET] — Size M — Depends: owner decision 1
  Assuming decision 1's recommendation: add to `configs/mister_de10nano_defconfig`
  `BR2_TARGET_UBOOT=y`, `BR2_TARGET_UBOOT_BUILD_SYSTEM_KCONFIG=y`,
  `BR2_TARGET_UBOOT_LATEST_VERSION=y` (2026.07 under Buildroot 2026.08 — the only source choice
  Buildroot hash-verifies), `BR2_TARGET_UBOOT_USE_DEFCONFIG=y`,
  `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="socfpga_de10_nano"`,
  `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES=".../board/mister/de10nano/uboot.fragment"`,
  `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE=".../board/mister/de10nano/uboot.env"` (Buildroot sets
  `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE` + the absolute path — `uboot.mk:414-422`),
  `BR2_TARGET_UBOOT_NEEDS_OPENSSL=y`, `BR2_TARGET_UBOOT_FORMAT_CUSTOM=y` +
  `_CUSTOM_NAME="u-boot-with-spl.sfp"`; **leave `BR2_TARGET_UBOOT_SPL` and
  `BR2_TARGET_UBOOT_ALTERA_SOCFPGA_IMAGE_CRC` unset** (the latter double-wraps the SPL —
  plan §3.6). Patches come from `BR2_GLOBAL_PATCH_DIR/uboot/`, already
  `board/mister/de10nano/patches/`, exactly like `patches/linux/`; retire the empty
  `board/mister/de10nano/uboot-patches/.gitkeep` and its four references (`PLAN.md:548,734,971`,
  `board/mister/de10nano/linux-rt.fragment:49`, `docs/init-parity.md:134`). Ship a **stub**
  `uboot.fragment` (header comment only, in the `de25nano/uboot.fragment` style, including its
  merge_config comment-line editing rule) and a **stub** `uboot.env` (stock's `bootcmd` line
  only) so the build is green before wave B fills them. Keep the defconfig canonical
  (`make savedefconfig`, then `scripts/check-defconfigs.sh` — every line must survive into
  the resolved `.config`). Extend `scripts/ci-tests.sh`: assert
  `images/u-boot-with-spl.sfp` exists, assert **no `images/uboot.img`** and no `.sfp` in the
  release stage (`mk-release.sh` stages named files; assert it anyway — plan §1's naming rule).
  If decision 1 goes the other way: the same lines in `configs/mister_de10nano_uboot_defconfig`
  with the DE10 toolchain block and no rootfs, plus a `uboot` target in the Makefile modelled
  on `de25`.
  **Done when:** `make` from a configured tree emits `images/u-boot-with-spl.sfp`; `ci-tests.sh`
  passes; `check-defconfigs.sh` green; CI build time delta recorded in the PR.

- [ ] **U2a — Patches 0001/0002, the two upstream fixes** — [SONNET] — Size S — Depends: —
  `0001-arm-socfpga-fix-dead-raw-sector-hook-guard.patch`: `arch/arm/mach-socfpga/board.c:214-215`
  `CONFIG_TARGET_SOCFPGA_{ARRIA10,GEN5}` → `CONFIG_ARCH_SOCFPGA_{ARRIA10,GEN5}` (fallout of
  `62f7a94602`). `0002-fs-exfat-fix-64-bit-division-on-32-bit-arm.patch`: `fs/exfat/time.c:129,147-148`
  via `do_div()`/`div_u64`-style helpers so `CONFIG_FS_EXFAT` links on 32-bit ARM. Build-test
  both **outside Buildroot** against `dl/uboot/u-boot-2026.07.tar.bz2` with the repo's cross
  toolchain (`output/host/bin/arm-buildroot-linux-gnueabihf-*`) and `socfpga_de10_nano_defconfig`
  + `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y` + `CONFIG_FS_EXFAT=y`. Provenance
  headers cite the upstream commits and say "to be submitted upstream (U7)".
  **Done when:** both apply at `-F0`; `nm spl/u-boot-spl` shows `board_spl_mmc_get_uboot_raw_sector`
  **[V]** (absent without 0001); the `FS_EXFAT` build links **[V]**.

- [ ] **U2b — Patch 0003, the fork's QTS handoff** — [SONNET] — Size S — Depends: —
  `0003-board-terasic-de10-nano-mister-qts-handoff.patch`: the four `board/terasic/de10-nano/qts/*.h`
  from `work/U-Boot_MiSTer@8dcc3484`, `s/CONFIG_HPS_/CFG_HPS_/`, **values unmodified** (decided:
  `FPGAPORTRST=0x3FFF`, both s2f clock counts, the three pinmux bits, the 32 IOCSR words).
  Verify with `/mnt/source/uboot-mainline/verify-qts/qtsdiff.py`: patched tree vs fork = **zero**
  differences after the rename; patched tree vs pristine 2026.07 = exactly plan §3.2's list.
  Provenance: fork `dadd1c8978` ("Use SPL config from DE10 FB project") and plan §3.2/§3.2a.
  **Done when:** the two `qtsdiff.py` runs say exactly that **[V]**, recorded in the patch header.

- [ ] **U2c — Patch 0004, the fork's `mt`** — [SONNET] — Size S — Depends: —
  `0004-cmd-mem-add-mt-memory-test-against-value.patch`: port `do_mem_mt` + its `U_BOOT_CMD`
  from `work/U-Boot_MiSTer/cmd/mem.c:158-180,1259-1263` (`cmd_tbl_t` → `struct cmd_tbl`,
  `simple_strtoul` → `hextoul`); find the introducing fork commit with `git log -S do_mem_mt`
  for the header. Test **by execution** in a U-Boot sandbox build (`make sandbox_defconfig`,
  host gcc — plan §3.4 did this for `itest`): `mw.l`, then `mt.l` equal and unequal, and prove
  the hush exit-status sense with `if mt.l …; then echo T; else echo F; fi` for both cases —
  this is the whole `fpgacheck` contract (boot-chain §6.1).
  **Done when:** the sandbox transcript is in the patch header **[V]**; the command table gains
  `mt` with stock's help string.

- [ ] **U2d — Patch 0005, the warm-reboot bridge behaviour** — [OPUS] — Size M — Depends: —
  The fork's `d6010efe50` (Sorgelig, 2017-03-27) adds one line, `socfpga_bridges_reset(0);`, at
  the end of `arch_early_init_r` in the 2017.03 `misc.c`. Mainline's `misc_gen5.c:185-210`
  `arch_early_init_r` ends in `socfpga_bridges_reset(1)`. The line does not port; the
  **behaviour** must. Read the fork's `socfpga_bridges_reset(int)` body (`misc.c:437-464` in the
  fork — its FPGA-user-mode test and which bridges and `l3regs` remap bits it releases) and
  mainline's `do_bridge_reset()` / `socfpga_bridges_reset()` in `misc_gen5.c`, and write the
  smallest patch that gives mainline the fork's post-reset state when the fabric is already
  configured. Write the equivalence argument **into the patch header and plan §3.3**, including
  what it does at cold boot (fabric unconfigured) — it must be a no-op there. Hardware cannot
  check this; the argument is the deliverable.
  **Done when:** the patch builds; `objdump -d u-boot` shows `arch_early_init_r` reaching the
  release path **[V]**; the argument survives U9.

- [ ] **U2e — The fragment** — [SONNET] — Size M — Depends: —
  `board/mister/de10nano/uboot.fragment`, headed like the DE25's (which layer is which; the
  merge_config comment-line rule). Every line a delta on `socfpga_de10_nano_defconfig`, each with
  its plan §3.1/§3.3 citation: `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y`;
  `CONFIG_FS_EXFAT=y`; **environment mirrors stock** — `CONFIG_ENV_IS_IN_MMC=y`,
  `CONFIG_ENV_OFFSET=0x200`, `CONFIG_ENV_SIZE=0x1000` (so `updateboot`'s sector-1 wipe keeps
  the "effective env = defaults + `u-boot.txt`" invariant, boot-chain §5 Consequence (b));
  `CONFIG_BOOTDELAY=0`, `CONFIG_AUTOBOOT_KEYED=y`, `CONFIG_AUTOBOOT_STOP_STR="\e"`;
  `CONFIG_SYS_BOOTM_LEN=0x4000000`; `CONFIG_TEXT_BASE=0x01000040`; `# CONFIG_TOOLS_MKEFICAPSULE
  is not set` (drops the `gnutls` host dep); the unused SPL SPI/QSPI stack off (`SPL_SPI`,
  `SPL_SPI_FLASH_SUPPORT`, `SPL_DM_SPI`, `SPL_SPI_LOAD` — SPL headroom 12.6 % → 30.4 %, plan
  §3.5). Do **not** strip mainline's extra commands to chase stock's 69: the parity check
  tolerates extras, and every removal is a chance to drop something stock's env calls. Resolve
  it with `merge_config.sh` + `olddefconfig` against the pristine tarball and diff the resolved
  `.config` against the defconfig's resolution: every fragment symbol must survive.
  **Done when:** the resolved `.config` carries every symbol U3 will assert **[V]**; the
  merge report shows zero dropped symbols.

- [ ] **U2f — The environment file** — [SONNET] — Size S — Depends: —
  `board/mister/de10nano/uboot.env`: stock's 21 entries, verbatim, in U-Boot's `.env` text
  format, with `mt` kept (U2c). Start from
  `/mnt/source/uboot-mainline/env-layout-parity/mister.env.txt` (it already built
  byte-identical once); the reference text is boot-chain §3.1/§4. **The acceptance test is a
  byte compare**: run the file through U-Boot's own `scripts/env2string.awk` flow (a sandbox or
  the 2026.07 tree's `include/generated/env.txt` rule) and `cmp` the resulting
  `default_environment[]` bytes against the blob at `0x28018` of the stock `uboot.img`
  (1,150 B, 21 entries — plan §6's corrected constant; **including the malformed entry-15
  fingerprint** of boot-chain §3.1, which the text format must reproduce exactly). Record in the
  file header that `CONFIG_ENV_SIZE=0x1000` (U2e) bounds it.
  **Done when:** `cmp` is silent **[V]**.

- [ ] **U4a — `scripts/check-uboot-parity.sh`** — [OPUS] — Size M — Depends: —
  House style of `scripts/check-zimage-dtb.sh`: POSIX `sh`, `set -eu`, header naming the
  contract and citing boot-chain sections, `Usage: check-uboot-parity.sh <built.sfp> <stock-uboot.img>`,
  `Exit: 0 = pass, 1 = contract violation, 2 = usage/IO error`, `note()`/`ok()`/`bad()`. Structural
  (hard fail): four byte-identical 64 KiB SPL copies; Altera header at `+0x40` (validation
  `0x31305341`, `length_u32`, checksum); legacy uImage magic at `0x40000` with recomputed header
  and payload CRCs; `load=0x01000040`; total size closes the file; SPL size against
  `tools/spl_size_limit`. Environment: locate `default_environment[]` in the built binary
  (`nm -S u-boot` → `addr - CONFIG_TEXT_BASE` into `u-boot.bin`) and in stock's (`0x28018`),
  **`cmp` them**; on mismatch print the entry-by-entry diff as the diagnostic. Command table:
  every stock command name present (extract both tables the way
  `/mnt/source/uboot-research/parity-check/cmdtbl.py` does), extras listed. Allowed diffs
  (version string, build timestamp, `ih_ep` `0x01000040` vs `0`, total size, code layout) are
  named in the output. **Self-test fixtures, as a `scripts/test-uboot-checks.sh` in the `scripts/test-*.sh`
  style:** stock-vs-stock must pass (the `.sfp` argument may be a stock `uboot.img`),
  and a mutated copy (one env byte flipped; one SPL copy differing; uImage CRC wrong) must fail
  with the right message. Runs today against the stock blob alone; U2g points it at the build.
  **Done when:** fixtures pass/fail as listed **[V]**; shellcheck clean.

- [ ] **U4b — `scripts/check-uboot-handoff.sh`** — [SONNET] — Size M — Depends: —
  The plan §3.2a/§6 handoff-equality gate. Inputs: the carried `qts/*.h` (from the patch or the
  patched tree), the built `.sfp`, the stock `uboot.img`. Pack the seven tables (u32 LE for the
  `iocsr_scan_chain*`, `ac_rom_init`, `inst_rom_init` arrays; **raw bytes** for
  `sys_mgr_init_table`) and assert each is found in SPL copy 0 of **both** images; offsets are
  reported, not compared. **Sanctioned style exception:** the packing is done by a small
  `python3` helper (`scripts/lib/qts-tables.py`, parser lifted from `qtsdiff.py`) called from
  the POSIX `sh` wrapper — Buildroot already requires host `python3`, so it adds no dependency;
  say so in the header. Fixtures: stock `uboot.img` must pass with the fork's headers (expected
  offsets are plan §3.2a's table) and **fail** with pristine mainline's headers — that failing
  run is the whole point, keep its transcript in `docs/verification/uboot-mainline.md`.
  **Done when:** both fixture runs behave **[V]**; shellcheck clean.

- [ ] **U8 — Docs debt** — [HAIKU] — Size S — Depends: —
  boot-chain §3.1's "20 entries, 1,149 bytes" → **21 entries, 1,150 bytes** (plan §6; the ELF
  symbol is 1,151); README phase-5 row (`README.md:167`) and the documentation-map rows
  (`README.md:1022-1023`) say "2026.07, in progress, ships nowhere"; `PLAN.md` §8 / `TASKS.md`
  P5.1-P5.2 pointers checked. No narrative copied anywhere.
  **Done when:** `git grep "2026.04"` finds only historical measurements in the plan.

- [ ] **U7-prep — Upstream submissions, drafted** — [SONNET] — Size S — Depends: U2a
  Two `git format-patch` mails with cover text in U-Boot list style (`scripts/get_maintainer.pl`
  for the socfpga custodian Cc), one per fix, ready in `docs/verification/uboot-upstream/` or
  a PR comment. **Not sent** — owner decision 4. After a send, the carried patches' provenance
  headers gain the list URL.
  **Done when:** the two mails exist and `checkpatch.pl` is clean.

### Wave B — integrate (one agent), then verify (three in parallel)

- [ ] **U2g — Integration build** — [SONNET] — Size M — Depends: U1, U2a–U2f
  Drop the five patches into `board/mister/de10nano/patches/uboot/` (with a `series` file if
  ordering matters), replace the stubs with the real fragment and env, `make uboot-dirclean
  uboot-rebuild`. Record: applies at `-F0`; `nm` shows the hook; `spl/u-boot-spl.bin` size
  and headroom (plan §3.5); `u-boot-with-spl.sfp` size; the resolved `.config`'s values for
  every U3 symbol. Start `docs/verification/uboot-mainline.md` (house style of
  `docs/verification/sdcard-payload.md`): every allowed diff enumerated and explained, both
  U4 scripts' transcripts, the U4b negative run.
  **Done when:** `check-uboot-parity.sh` and `check-uboot-handoff.sh` pass against the build
  and the stock blob **[V]**; the verification doc exists.

- [ ] **U3 — Resolved-`.config` assertion inside the build** — [SONNET] — Size S — Depends: U2g
  Not a checklist: an `UBOOT_POST_BUILD_HOOKS` append from `external.mk` (the same trick that
  fixed dhcpcd's `CONF_OPTS`) that greps `$(@D)/.config` and fails the build naming the delta
  and its plan §3.1 row. Assert at minimum
  `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y`,
  `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION_TYPE=0xa2`,
  `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_SECTOR` **unset**, `CONFIG_FS_EXFAT=y`,
  `CONFIG_ENV_IS_IN_MMC=y`, `CONFIG_ENV_OFFSET=0x200`, `CONFIG_ENV_SIZE=0x1000`,
  `CONFIG_TEXT_BASE=0x01000040`, `CONFIG_SPL_PAD_TO=0x10000`, `CONFIG_ARCH_SOCFPGA_GEN5=y`,
  `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE=y`, `CONFIG_CMD_MEMORY=y`. Same hook runs
  `nm` for `board_spl_mmc_get_uboot_raw_sector`. Guard it on the DE10 defconfig (the DE25 has
  its own, DU2). This is what makes the Buildroot-bump-moves-U-Boot case fail loudly.
  **Done when:** deleting any one fragment line makes `make uboot-rebuild` fail with a message
  naming it **[V]** (do it for three of them and record the output).

- [ ] **U5 — CI** — [SONNET] — Size S — Depends: U2g
  With decision 1's recommendation there is **no new workflow**: the build already runs U-Boot,
  `verify-image` already runs `ci-tests.sh`. Add to `ci-tests.sh` a "U-Boot" section that runs
  both U4 scripts against `images/u-boot-with-spl.sfp` and the stock blob fetched by hash
  (`fetch-sdcard-payload.sh`'s path, `dl/`-cached; if the owner wants `ci-tests.sh` to stay
  offline, put the two runs in `release.yml` next to `check-sdcard.sh`, which already has the
  blob). Extend `scripts/lint-kernel-patches.sh` (the `lint-config` job) to `patches/uboot/`. If decision 1 went the
  other way: a `workflow_dispatch`-first `uboot.yml`, `pull_request` scoped by `paths:` to the
  U-Boot inputs (`reproducibility.yml:26-32` posture, `lint.yml:26-36` scoping), never in the
  kernel gate.
  **Done when:** a PR touching only U-Boot inputs runs the checks; the Actions-minutes delta is
  in the PR description.

- [ ] **U9 — Adversarial review** — [FABLE] — Size M — Depends: U2g (runs alongside U3/U5)
  Reads, does not edit. Against plan §8's failure taxonomy, patch by patch and symbol by symbol:
  can the built `.sfp` present as a boot on a board while being wrong? Specifically: the U2d
  bridge argument at cold boot and at warm reboot; whether the env `cmp` could pass while the
  *effective* env differs (`CONFIG_ENV_*` defaults, `env import` behaviour, `hush` version
  differences since 2017); whether anything in the SPL could touch `0x1FFFF000`–`0x1FFFFFFF`
  (the mailbox, boot-chain §6.3) before U-Boot proper; whether the `ih_ep`/`ih_load` mixing
  hazard (plan §3.3) is documented where a future flasher would read it. Findings go to
  `docs/verification/uboot-mainline.md` as a section; each is fixed or recorded [U] with the
  missing input named.
  **Done when:** no finding is left unlabelled.

### Deferred — not in this plan

- [ ] **U6 — [HW] Hardware matrix and recovery drill** — deferred indefinitely (owner,
  2026-09-14). The text of the gate stands unchanged in plan §8 for the day stock's `uboot.img`
  "turns into a pumpkin": measured `0xA2` partition size; the `itest` fallback smoke-tested under
  stock via `u-boot.txt`; second card + drilled recovery; serial console; cold boot, `u-boot.txt`
  override, **warm-reboot core handoff**, an `updateboot` cycle. Until then, nothing this plan
  builds is flashed, published, or named `uboot.img`.
- [ ] **U7 — send** — on the owner's go only.

---

## DE25-Nano — the DU-series (desk half of D2.2/D2.4)

Everything `docs/de25-uboot.md` §12 tags **[U]** needs the board and stays [U]. What follows is
the rest.

### Wave A — fan out (runs with the DE10's wave A)

- [ ] **DU1 — One U-Boot pin for both boards** — [HAIKU] — Size S — Depends: owner decision 2
  If recommended: in `configs/mister_de25nano_defconfig` replace
  `BR2_TARGET_UBOOT_CUSTOM_VERSION=y` + `_VALUE="2026.07"` with `BR2_TARGET_UBOOT_LATEST_VERSION=y`;
  `git rm board/mister/de25nano/patches/uboot/uboot.hash` (its header's reason — "Buildroot's
  hash file has no line for our tarball" — is no longer true; say so in the commit); keep the
  defconfig canonical (`make O=output-de25 savedefconfig`, `scripts/check-defconfigs.sh`). TF-A keeps its custom pin and hash. **Prove nothing moved:** `make O=output-de25
  uboot-dirclean uboot-rebuild` before and after, `sha256sum images/u-boot.itb` identical
  (`BR2_REPRODUCIBLE=y`, per-tree identity is [V] in `de25-uboot.md` §5b).
  **Done when:** the two hashes match **[V]**; `check-defconfigs.sh` green; `de25-uboot.md` §2's
  version table updated.

- [ ] **DU2 — The QSPI-write audit as a build assertion** — [SONNET] — Size S — Depends: —
  `de25-uboot.md` §13 item 7 and `de25-boot-chain.md` §5's final bullet: the rule exists only
  as sentences. Encode §7's table as an `UBOOT_POST_BUILD_HOOKS` append in `external.mk`
  guarded on the DE25 defconfig: every §7 symbol **absent or unset** in the resolved `.config`
  (`ENV_IS_IN_UBI`, `ENV_IS_IN_SPI_FLASH`, `ENV_IS_IN_NAND`, `ENV_IS_IN_MMC`, `CADENCE_QSPI`,
  `DM_SPI_FLASH`, `SPI_FLASH*`, `CMD_SF*`, `CMD_MTD*`, `CMD_UBI*`, `CMD_NAND`, `MTD`, `DM_MTD`,
  `MTD_UBI`, `MTD_RAW_NAND`, `HANDOFF`, `BLOBLIST`), `ENV_IS_IN_FAT=y`, and `strings u-boot.itb`
  free of `sf probe`, `ubi part`, `mtdparts`. Plus the Linux side of `de25-boot-chain.md` §7
  row 11 in `ci-tests.sh`'s DE25 section: no `fw_env.config` in the DE25 rootfs names an MTD
  device. Cite the two docs in the hook's error text.
  **Done when:** re-adding `CONFIG_ENV_IS_IN_UBI=y` to the fragment fails the build naming
  `de25-uboot.md` §7 **[V]**; `de25-boot-chain.md` §5's final bullet and its §9.3 open-concern row flip to
  [V] with the commit cited.

- [ ] **DU3 — FIT reproducibility across clean trees** — [SONNET] — Size S — Depends: DU1
  `de25-uboot.md` §5b tags cross-tree identity [U]. Two clean `O=` trees on one commit, same
  toolchain, `sha256sum` of `u-boot.itb` and `bl31.bin`; if they differ, `dumpimage -l` and
  `diffoscope`-style section comparison to name the source (build path, timestamp,
  `SOURCE_DATE_EPOCH`). Local only — do not add a DE25 leg to `reproducibility.yml` (Actions
  budget); record the method so the D2.8 release lane can repeat it.
  **Done when:** §5b's [U] becomes [V] or a named cause.

- [ ] **DU4 — §13 decisions dispositioned** — [HAIKU] — Size S — Depends: owner decision 5
  Recommendations, one per `de25-uboot.md` §13 item: (1) keep the carried mtdids/mtdparts
  guard patch — one line, inert argument not needed; (2) `HANDOFF` off + declared 1 GiB as
  shipped; (3) `&mmc` at 25 MHz as shipped; (4) no seeded `uboot.env`; (5) keep `FS_EXFAT=y`
  (ADR 0029 D11 made the DE10-style two-stage layout the target, and its data partition is
  exFAT); (6) stay on `DISTRO_DEFAULTS` until first boot, but add a one-line note naming
  `BOOTSTD_DEFAULTS` as the migration target in the fragment; (7) = DU2. Write each disposition
  into §13 with the date; nothing else changes.
  **Done when:** §13 has a disposition line per item.

- [ ] **DU5-prep — Upstream the mtdids guard** — [SONNET] — Size S — Depends: —
  `0001-configs-socfpga_soc64-guard-mtdids-mtdparts-env.patch` (`de25-uboot.md` §8 calls it
  upstreamable, not submitted). Same shape as U7-prep: a list-ready mail, `checkpatch.pl`
  clean, **not sent** without the owner's go.
  **Done when:** the mail exists.

- [ ] **DU6 — TF-A tag signature** — [SONNET] [NET] — Size S — Depends: —
  §12 says the v2.15.0 tag's signing key was on no reachable keyserver. Try the
  trustedfirmware.org release announcement / the project's published key file / a WKD lookup;
  if found, verify the tag and record the fingerprint in
  `board/mister/de25nano/patches/arm-trusted-firmware/arm-trusted-firmware.hash`'s header the
  way `uboot.hash` did; if not, record **where** it was looked for and that the hash is TOFU.
  **Done when:** the hash file header says one or the other with the evidence.

### Wave B

- [ ] **DU7 — Boot-path re-review** — [FABLE] — Size S — Depends: DU1, DU2 (may run as part of U9)
  The wave-2 `fable` boot-path pass was against the custom-pin build. Re-run its checklist
  (`de25-nano-tasks.md` "What the boot-path fable pass established") against the DU1 artifact:
  no QSPI command or driver in U-Boot proper, unsigned-crc32 FIT at the factory SPL's addresses,
  nothing persistent written. Add: does DU2's hook actually fire on the DE25 tree and not the
  DE10's?
  **Done when:** the pass is logged in `de25-nano-tasks.md` under a wave-4 heading.

---

## Dependency graph

```
owner decisions 1, 2, 5 ──┐
                          ▼
Wave A (parallel): U1 U2a U2b U2c U2d U2e U2f U4a U4b U8 U7-prep │ DU1 DU2 DU4 DU5-prep DU6
                          │                                        │
                          ▼                                        ▼
Wave B:            U2g (integration, alone)                 DU3 (after DU1)
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
             U3          U5          U9 [FABLE]  ──  DU7 [FABLE]
                                      │
                             (owner go) U7 send / DU5 send
Deferred:  U6 [HW]
```

Wave A: 16 agents if every task is its own agent; U8, DU4 and DU5-prep are small enough to
share one Haiku/Sonnet, bringing it to 13. Waves B and C are 1 + 3 + 1. No agent needs a board,
a serial cable, or network beyond the pinned tarball and the hash-fetched stock blob.

---

## Status

**2026-09-14:** plan written; nothing below U0 started. Both boards' U-Boot work is desk-only by
the owner's direction, and "it boots" remains a per-build claim that only hardware can make.
