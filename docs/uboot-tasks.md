# U-Boot — execution tasks

Execution contract for the mainline U-Boot capability artifact. **Design and evidence live
in [`docs/uboot-mainline-port.md`](uboot-mainline-port.md); the decision lives in
[ADR 0024](decisions/0024-mainline-uboot-capability-artifact.md).** This file is only the
ordered work.

Split out of `TASKS.md` deliberately: that file and `PLAN.md` are already large, and the
U-Boot narrative is self-contained. `TASKS.md` P5.1/P5.2 redirect here and carry no
U-Boot detail of their own. **P5.3 (`sdcard.img`) and P5.4 remain in `TASKS.md`** — they
are about the SD image, which keeps embedding the stock blob and is not affected by this
work.

Conventions (model routing, `[HW]`/`[NET]` flags, sizes, standing rules) are inherited
verbatim from [`TASKS.md` §0](../TASKS.md).

---

## The one-line summary

Build mainline U-Boot **2026.04** for the DE10-Nano, configured to behave like stock's
2017.03 fork, as a **build artifact that ships nowhere**. The default channel keeps
shipping the stock `uboot.img` byte-identical. Five deltas are mandatory; three of them are
silent-brick if omitted.

---

## Tasks

- [ ] **U0 — ADR + redirects** — [HAIKU] — Size S — Depends: —
  Land [ADR 0024](decisions/0024-mainline-uboot-capability-artifact.md); annotate ADR 0017
  as superseded-in-part (§Decision 1–3 only; 4 and 5 stand); redirect `PLAN.md` §8 and
  `TASKS.md` P5.1/P5.2 here **without** copying the narrative into them; add both new docs
  to the README documentation map.
  **Done when:** no file in the repo still instructs a reader to build the fork or to add a
  `u-boot/` submodule, and `docs/uboot-mainline-port.md` is reachable from the README.

- [ ] **U1 — [NET] Buildroot skeleton** — [SONNET] — Size M — Depends: U0
  `configs/mister_uboot_defconfig` (Buildroot-config layer) + `make uboot` / `make uboot-clean`
  building into `O=output-uboot`. Model the Makefile target on **`installer`**
  (`Makefile:604-623`), **not** `rt` — `rt`'s `merge_config.sh` step and module-tree staging
  are irrelevant here, since the U-Boot fragment is applied by Buildroot itself and the
  artifact is standalone. Do not forget the `$(UBOOT_DEFCONFIG): ;` empty rule
  (`Makefile:113-115` pattern) that keeps the catch-all target-forwarding rule from
  intercepting it.
  Required Buildroot options, all verified against `work/buildroot` 2026.05.1:
  `BR2_TARGET_UBOOT=y`, `BR2_TARGET_UBOOT_LATEST_VERSION=y` (the **only** choice that
  hash-verifies the tarball — `uboot.mk:41-43` — resolving to 2026.04 per `Config.in:88`),
  `BR2_TARGET_UBOOT_BUILD_SYSTEM_KCONFIG=y`, `BR2_TARGET_UBOOT_USE_DEFCONFIG=y` with
  `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="socfpga_de10_nano"`,
  `BR2_TARGET_UBOOT_FORMAT_CUSTOM=y` + `_CUSTOM_NAME="u-boot-with-spl.sfp"` (no `.sfp`
  entry exists in the format menu, `Config.in:373-551`), `BR2_TARGET_UBOOT_NEEDS_OPENSSL=y`.
  **`BR2_TARGET_UBOOT_ALTERA_SOCFPGA_IMAGE_CRC` must stay OFF** — mainline already wraps the
  SPL with `mkimage -T socfpgaimage` (`scripts/Makefile.xpl:436-441`) and enabling it
  double-wraps via host `mkpimage` (`uboot.mk:561-579`). No custom make target is needed:
  upstream `Kconfig:528` sets `CONFIG_BUILD_TARGET="u-boot-with-spl.sfp"` for gen5 and
  `uboot.mk:66` already calls `all`.
  **Done when:** `make uboot` from a clean tree produces
  `output-uboot/images/u-boot-with-spl.sfp`, and `make uboot-clean` removes `output-uboot/`.

- [ ] **U2 — The five deltas** — [OPUS] — Size L — Depends: U1
  Author the U-Boot-config layer `board/mister/de10nano/uboot-mister.fragment` (wired via
  `BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES`, `Config.in:140-145`), the environment
  `board/mister/de10nano/uboot-mister.env`, and the patches in
  `board/mister/de10nano/uboot-patches/` (picked up by `BR2_TARGET_UBOOT_PATCH`,
  `Config.in:103-113` / `uboot.mk:342-354`; honours a `series` file, applies at fuzz zero).
  Head the fragment with the same "which layer is which" note `configs/mister_rt.fragment:19-21`
  uses for the kernel. Every patch carries a full CONTRIBUTING §2 provenance header — use
  `board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch` as the
  template. Per ADR 0024 §Decision 3, behaviour changes **are** permitted here; each must be
  enumerated in `docs/uboot-mainline-port.md` §4.
  The five deltas, with full evidence in `docs/uboot-mainline-port.md` §3.1:
  (a) `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y`;
  (b) the dead-hook guard fix at `arch/arm/mach-socfpga/board.c:214`;
  (c) `CONFIG_FS_EXFAT=y` + the `do_div()` fix in `fs/exfat/time.c`;
  (d) the fork's four `board/terasic/de10-nano/qts/*.h` with `s/CONFIG_HPS_/CFG_HPS_/`;
  (e) the environment, via `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE` (`env/Kconfig:771`).
  Also apply the stock-parity config deltas: `CONFIG_ENV_OFFSET=0x200` /
  `CONFIG_ENV_SIZE=0x1000` (so `updateboot`'s sector-1 wipe keeps working — boot-chain §5
  Consequence (b)), `CONFIG_BOOTDELAY=0`, `CONFIG_AUTOBOOT_KEYED=y`,
  `CONFIG_AUTOBOOT_STOP_STR="\e"`, `CONFIG_SYS_BOOTM_LEN=0x4000000`,
  `CONFIG_TEXT_BASE=0x01000040`. Disable `CONFIG_TOOLS_MKEFICAPSULE` (host-only tool; it is
  the sole reason a `gnutls` host dependency appears) and drop the unused SPL SPI/QSPI stack
  (`SPL_SPI`, `SPL_SPI_FLASH_SUPPORT`, `SPL_DM_SPI`, `SPL_SPI_LOAD`), which takes SPL
  headroom from 12.6 % to 30.4 % under the hard 64 KiB BootROM ceiling.
  Use `itest.l *<addr> == <val>` for the `fpgacheck` rewrite. **Do not use `setexpr` +
  `test -eq`** — `env_set_hex` writes bare lowercase hex and `test -eq` parses base-0, so
  the comparison is false forever and every warm reboot silently takes the cold path.
  **Done when:** the resolved `.config` assertion of U3 passes and `nm` proves
  `board_spl_mmc_get_uboot_raw_sector` is linked into the SPL.

- [ ] **U3 — Resolved-`.config` assertion in the build recipe** — [SONNET] — Size S — Depends: U2
  Assert on the **resolved `.config`**, never the defconfig or the fragment: the SPL
  raw-mode selector is a Kconfig `choice` whose default can flip on a U-Boot bump with no
  diff in our files, and `merge_config.sh` only *warns* when a fragment symbol is dropped
  while `olddefconfig` silently discards symbols whose dependencies fail. This is the exact
  hazard the `rt` recipe already guards against — model the check on `Makefile:504-521`,
  including its single-tree uniqueness guard.
  Assert at minimum: `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y`,
  `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION_TYPE=0xa2`,
  `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_SECTOR` **not** set, `CONFIG_FS_EXFAT=y`,
  `CONFIG_ENV_OFFSET=0x200`, `CONFIG_TEXT_BASE=0x01000040`, `CONFIG_SPL_PAD_TO=0x10000`,
  `CONFIG_ARCH_SOCFPGA_GEN5=y`.
  **Done when:** deleting any one delta from the fragment makes `make uboot` fail loudly,
  with a message that names the delta and cites its `docs/uboot-mainline-port.md` §3.1 row.

- [ ] **U4 — `scripts/check-uboot-parity.sh`** — [OPUS] — Size M — Depends: U3
  House style of `scripts/check-zimage-dtb.sh`: POSIX `sh`, `set -eu`, a header naming the
  contract and citing boot-chain sections, `Usage:`, `Exit: 0 = pass, 1 = contract
  violation, 2 = usage/IO error`, `note()`/`ok()`/`bad()`. Takes the `.sfp` path as an
  argument. Full check list in `docs/uboot-mainline-port.md` §6.
  Structural (hard fail): four byte-identical 64 KiB SPL copies; Altera header at `+0x40`
  (validation `0x31305341`, `length_u32`, checksum); legacy uImage magic at `0x40000` with
  recomputed header and payload CRCs; `load=0x01000040`; total size closes the file exactly;
  SPL size against `tools/spl_size_limit`.
  Environment: extract the raw `default_environment[]` symbol (`nm -S u-boot`, read
  `u-boot.bin` at `addr - CONFIG_TEXT_BASE`) — **not** `u-boot-initial-env`, which is sorted
  and can be stale. Compare **entry by entry** against stock's 21 entries; a plain `cmp` is
  impossible and that trade is rejected (ADR 0024 §Decision 5).
  While here, reconcile a `boot-chain.md` §3.1 nit: it records the env blob as "20 entries,
  1,149 bytes"; direct extraction gives **21 entries, 1,150 bytes** (`0x28018–0x28495`
  inclusive is `0x47E`; the ELF symbol is 1,151). Byte-identity was never in doubt — the
  constant is.
  **Done when:** it passes against the U2 artifact, every allowed diff is enumerated with a
  per-item explanation in `docs/verification/uboot-mainline.md`, and an unexplained delta
  fails the run.

- [ ] **U5 — CI** — [SONNET] — Size S — Depends: U4
  New `.github/workflows/uboot.yml`. **`workflow_dispatch` is the primary trigger**, plus
  `pull_request` scoped by `paths:` to the five U-Boot inputs. Cite `reproducibility.yml:26-32`
  in the header for the manual-first posture and `lint.yml:26-36` for the path scoping, and
  state the budget reasoning explicitly — Actions minutes are a real constraint here. This
  is **not** a kernel variant: it must not join `build.yml`'s matrix (which is derived from
  `configs/mister_*.fragment` by `scripts/list-kernel-variants.sh`) and must not drag in the
  kernel gate.
  **Done when:** a manual run builds the artifact and runs `check-uboot-parity.sh`; a PR
  touching only kernel files does not trigger it.

- [ ] **U6 — [HW] Hardware matrix and recovery drill** — human + [OPUS] — Size L — Depends: U5
  **Gate. Nothing is flashed until every item below is done, in order.**
  1. U1–U5 green; `docs/verification/uboot-mainline.md` complete.
  2. **Measure the real card's `0xA2` partition size** (`sfdisk -l /dev/mmcblk0` on the test
     MiSTer at `192.168.0.161`) and confirm it exceeds the built image. `updateboot` `dd`s
     with no size check, and our own `genimage-sdcard.cfg:132-135` value (4 MiB) says
     nothing about what mr-fusion or the Windows SD installer create.
  3. **Free de-risking step:** smoke-test the `itest`-rewritten `fpgacheck` on hardware under
     the **stock** bootloader via `u-boot.txt`. `itest` exists in the stock 2017.03 binary,
     so the single largest environment rewrite can be validated with zero brick exposure.
  4. A second SD card known-good, plus a written recovery procedure **executed once from an
     actually-bricked state**. Recovery is always "rewrite the card from another machine":
     the DE10-Nano has no HPS-attached flash (`nand@ff900000` / `spi@ff705000` are
     `status = "disabled"` in `work/stock.dts:742-770`) and nothing programs fuses, so
     "brick" here never means a dead board.
  5. Serial console attached for the first boot.
  Matrix: cold boot to menu; `u-boot.txt` override honoured; **warm-reboot core handoff**
  (load a core → Main_MiSTer warm-reboots → fabric still live); an `updateboot` flash +
  env-wipe cycle leaving the board bootable.
  **Done when:** the matrix and a successful real recovery drill are logged in
  `docs/testlogs/uboot-mainline.md`.

- [ ] **U7 — [NET] Send the two upstream fixes** — [SONNET] — Size S — Depends: U2
  Both are genuine mainline bugs and landing them removes carried patches from the
  highest-blast-radius component in the system.
  (a) `arch/arm/mach-socfpga/board.c:214` — `CONFIG_TARGET_SOCFPGA_GEN5` →
  `CONFIG_ARCH_SOCFPGA_GEN5` (and the Arria10 sibling), fallout from the rename in
  `62f7a94602`. Also fixes in-tree Arria10.
  (b) `fs/exfat/time.c:129,147-149` — 64-bit division via `do_div()` so `CONFIG_FS_EXFAT`
  links on 32-bit ARM. No 32-bit board in tree enables it, which is why nobody has hit it.
  **Done when:** both are posted to the U-Boot list with the socfpga custodian on Cc, and
  the carried patches in `uboot-patches/` cite the submission in their provenance headers.

---

## Open questions

Tracked in `docs/uboot-mainline-port.md` §9. The two that most affect execution order:

1. **The warm-reboot bridge fix** — carried C patch (`d6010efe50`) or `bridge enable` in
   `fpgacheck`'s middle branch? The env route keeps the delta out of C but was assessed as
   *not* equivalent. **Decide before U2 and write the reasoning down**; a cold-boot test
   cannot catch getting this wrong.
2. **Is `FPGAPORTRST=0x3FFF` genuinely required**, or merely what MiSTer's Quartus project
   emitted? Unverified on hardware, and must not be asserted either way. Same for the
   `GENERALIO3`/`GENERALIO4` pinmux difference.

---

## Status

Nothing below U0 has been started. **Nothing in this plan has been run on a DE10-Nano** —
every claim in the design doc is source-level or build-artifact-level. "It boots" is a
per-build claim, exactly like the RT kernel pin.
