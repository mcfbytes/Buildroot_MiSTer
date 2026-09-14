# Mainline U-Boot 2026.07 for the DE10-Nano — integration build, measured

This is the evidence file for the from-source DE10-Nano bootloader: **what was built, what
differs from the stock 2017.03 fork blob, why each difference is allowed, and what no desk
check can settle.** The design lives in
[`docs/uboot-mainline-port.md`](../uboot-mainline-port.md), the decision in
[ADR 0024](../decisions/0024-mainline-uboot-capability-artifact.md), the boot contract it
has to honour in [`docs/boot-chain.md`](../boot-chain.md). This file records the run.

**This artifact ships nowhere.** It is built by the ordinary `make` of
`configs/mister_de10nano_defconfig` into `output/images/u-boot-with-spl.sfp`, it is never
named `uboot.img`, and `scripts/mk-release.sh` stages named files only — the release keeps
embedding the stock blob (`docs/verification/sdcard-payload.md` §3 item 2). The point of
building it is that the whole image exists from source and cannot rot, and the point of
this file is that the claim "it behaves like stock" is checkable without a board.

Every statement below is tagged **[V]** (observed in the run recorded here, with the
command) or **[U]** (unverified, with the missing input named). Nothing here was observed
on hardware: **there has been no hardware session, and none is planned** — the DE10 gate
(task U6) is deferred, not waived. See §8.

---

## 1. What was built

| Input | Value |
|---|---|
| U-Boot | **2026.07**, via `BR2_TARGET_UBOOT_LATEST_VERSION` under Buildroot 2026.08 — the only source choice Buildroot hash-verifies (plan §3.6) |
| tarball | `dl/uboot/u-boot-2026.07.tar.bz2`, sha256 `78e8bfc382fe388f9b55aa1daf8c563522a037779b5d4c349d1415e381f1243e` (verified by Buildroot at extract time, build log) |
| board defconfig | `configs/socfpga_de10_nano_defconfig` (upstream's, unmodified) |
| fragment | `board/mister/de10nano/uboot.fragment`, sha256 `8ae7b43d549d856fabf398fbf981ac96e5cb8ac521e18222a41e1274557accd0` |
| environment text | `board/mister/de10nano/uboot.env`, sha256 `65da6ec5309c5a104aa108ed26232ed12f34fb60e62a0e8e56c6d6ba095ae6a8` |
| patches | `board/mister/de10nano/patches/uboot/000{1..5}-*.patch` (§2) |
| Buildroot | 2026.08 (`Makefile:BUILDROOT_VERSION`) |
| toolchain | `arm-buildroot-linux-gnueabihf-gcc` 15.3.0 (Buildroot-built, `output/host/bin/`) |
| reference blob | stock `uboot.img`, 515,141 B, sha256 `e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64` |

Build command, from a tree configured with `make mister_de10nano_defconfig`:

```
make BR2_JLEVEL=12 uboot-dirclean uboot          # exit 0
```

Artifacts **[V]**:

| File | Size | sha256 |
|---|---|---|
| `output/images/u-boot-with-spl.sfp` | 816,000 B | `287201ee714d351abd19f7c827a405f8c7e0f796fdaf33ccb71d518039455e46` |
| `output/build/uboot-2026.07/spl/u-boot-spl.bin` | 46,386 B | `ae00baa6fba3822e8035a7e510a6e38ba24babc9b7a6f8fa16b164136d2cbcd4` |
| `output/images/u-boot.bin` (U-Boot proper) | 553,792 B | `c9052ca30afa5942569e719689120a796b0f90a725e8b2a1adb431d15ea5abeb` |

**Those hashes are stable.** `BR2_REPRODUCIBLE=y` is set for this board, so the build
carries a fixed `SOURCE_DATE_EPOCH`: the uImage `ih_time` is `1788535000` = 2026-09-04
15:16:40 UTC, not this run's wall clock. That is Buildroot's own `BR2_VERSION_EPOCH`
(`work/buildroot/Makefile:97`, used at `:540` because the pinned tree is an unpacked
release tarball and not a git checkout — in a git checkout the commit date would win
instead, which is still deterministic but a different number). Two independent
`uboot-dirclean uboot` runs produced byte-identical `.sfp` files **[V]** (`cmp` silent).
That is worth stating because an earlier out-of-Buildroot scratch build of the same source
did *not* fix the epoch and its `.sfp` hash was therefore not an identity; inside Buildroot
it is.

### The temporary `gnutls` line is gone

Wave A's wiring had to add `BR2_TARGET_UBOOT_NEEDS_GNUTLS=y` to
`configs/mister_de10nano_defconfig`, because the pristine board defconfig resolves
`CONFIG_TOOLS_MKEFICAPSULE=y` (it is `default y if EFI_LOADER`) and `tools/mkeficapsule.c`
hard-requires `gnutls/gnutls.h`. The fragment's `# CONFIG_TOOLS_MKEFICAPSULE is not set`
(§7 of the fragment) removes the pull-in, so the line was deleted here and the claim was
proved the only way that settles it — **a `uboot-dirclean` rebuild with the line removed,
which exits 0 and mentions gnutls nowhere** (`grep -ci gnutls build-final.log` → `0`) **[V]**.
CI therefore does not pay for the `host-gnutls`/nettle/p11-kit/libtasn1/libunistring chain.

Be precise about what that rebuild proves. `output/` is not a clean tree: wave A's build
had already installed `host-gnutls` (`output/build/host-gnutls-3.8.13/`,
`output/host/lib/libgnutls.so`), and `uboot-dirclean` does not remove them, so a rebuild
here cannot *observe* that nothing latent would still need them. The claim rests instead on
gates that are deterministic in the tree: `output/.config` has
`# BR2_TARGET_UBOOT_NEEDS_GNUTLS is not set` (the only thing that adds `host-gnutls` to
`UBOOT_DEPENDENCIES`, `boot/uboot/uboot.mk`); the resolved U-Boot `.config` has
`# CONFIG_TOOLS_MKEFICAPSULE is not set`, and `tools/Makefile`'s
`hostprogs-always-$(CONFIG_TOOLS_MKEFICAPSULE) += mkeficapsule` is the only consumer of
`gnutls`, so `tools/mkeficapsule` is absent from the build tree; and the build log has zero
`gnutls`/`lgnutls` hits. The first from-scratch observation is CI's (task U5), which
starts from no `output/` at all.

`configs/mister_de10nano_defconfig` is canonical after the change: `make savedefconfig`
reproduces its `BR2_` lines exactly, and `scripts/check-defconfigs.sh` is green for all
three defconfigs **[V]** (§6).

---

## 2. The five carried patches

They live in `board/mister/de10nano/patches/uboot/` and are picked up by
`BR2_GLOBAL_PATCH_DIR` exactly like `patches/linux/`. **No `series` file is needed:**
Buildroot applies `*.patch` in sorted order and no two of these touch the same file, so the
numeric order *is* the applied order.

| # | Patch | Touches | Class |
|---|---|---|---|
| 0001 | `arm-socfpga-fix-dead-raw-sector-hook-guard` | `arch/arm/mach-socfpga/board.c` | upstream bug fix (plan §3.1 delta 2) |
| 0002 | `fs-exfat-fix-64-bit-division-on-32-bit-arm` | `fs/exfat/time.c` | upstream bug fix (delta 3) |
| 0003 | `board-terasic-de10-nano-mister-qts-handoff` | `board/terasic/de10-nano/qts/{iocsr,pinmux,pll,sdram}_config.h` | carried fork data (delta 4) |
| 0004 | `cmd-mem-add-mt-memory-test-against-value` | `cmd/mem.c` | carried fork command (plan §3.4) |
| 0005 | `arm-socfpga-gen5-release-bridges-after-reset-if-fpga-in-user-mode` | `arch/arm/mach-socfpga/misc_gen5.c` | carried fork behaviour (plan §3.3) |

sha256, as committed:

```
3ef5b26b6b916e459318d709998f99c059544317019a2f840f4e8ef0f7a673d1  0001-arm-socfpga-fix-dead-raw-sector-hook-guard.patch
5f9be8eabb0f77aa3cf3ccc8624f798ac8ba69beebee7c8f475f59c36bd58bb8  0002-fs-exfat-fix-64-bit-division-on-32-bit-arm.patch
96a54b3d6223a3f883101eba1f9202b9ca19cbb395e0ecd38942fa1bd5aae535  0003-board-terasic-de10-nano-mister-qts-handoff.patch
01e0de68875c02180bb4af13f4703ce150432267b86d7738b379b2e9104497a8  0004-cmd-mem-add-mt-memory-test-against-value.patch
7118f4c0bc69572a6ebb13d13785c0467aff9e155c80754ed3ec9b2f4dc756c2  0005-arm-socfpga-gen5-release-bridges-after-reset-if-fpga-in-user-mode.patch
```

### All five apply, at zero fuzz — the build's own transcript **[V]**

Buildroot's `support/scripts/apply-patches.sh` runs `patch -p1 -F0 -g0 --no-backup-if-mismatch -t -N`,
so a hunk that needed fuzz or an offset would be *rejected*, not accepted quietly, and any
`Hunk #n succeeded at … (offset …)` line would appear here. None does:

```
>>> uboot 2026.07 Patching

Applying 0001-arm-socfpga-fix-dead-raw-sector-hook-guard.patch using patch:
patching file arch/arm/mach-socfpga/board.c

Applying 0002-fs-exfat-fix-64-bit-division-on-32-bit-arm.patch using patch:
patching file fs/exfat/time.c

Applying 0003-board-terasic-de10-nano-mister-qts-handoff.patch using patch:
patching file board/terasic/de10-nano/qts/iocsr_config.h
patching file board/terasic/de10-nano/qts/pinmux_config.h
patching file board/terasic/de10-nano/qts/pll_config.h
patching file board/terasic/de10-nano/qts/sdram_config.h

Applying 0004-cmd-mem-add-mt-memory-test-against-value.patch using patch:
patching file cmd/mem.c

Applying 0005-arm-socfpga-gen5-release-bridges-after-reset-if-fpga-in-user-mode.patch using patch:
patching file arch/arm/mach-socfpga/misc_gen5.c
```

`scripts/lint-kernel-patches.sh board/mister/de10nano/patches/uboot` is also green — all
five are `git am`-able, i.e. their mail headers parse, which the `patch -p1` path never
exercises **[V]**:

```
=== board/mister/de10nano/patches/uboot
ok   0001-arm-socfpga-fix-dead-raw-sector-hook-guard.patch Michael C. Ferguson <michael.christopher.ferguson@gmail.com>
ok   0002-fs-exfat-fix-64-bit-division-on-32-bit-arm.patch Michael C. Ferguson <michael.christopher.ferguson@gmail.com>
ok   0003-board-terasic-de10-nano-mister-qts-handoff.patch Sorgelig <pour.garbage@gmail.com>
ok   0004-cmd-mem-add-mt-memory-test-against-value.patch  Sorgelig <pour.garbage@gmail.com>
ok   0005-arm-socfpga-gen5-release-bridges-after-reset-if-fpga-in-user-mode.patch Sorgelig <pour.garbage@gmail.com>

RESULT: PASS — all 5 patches in 1 series are `git am`-able.
```

### Each patch's effect, observed in the built binaries **[V]**

* **0001 — the `+0x200` hook is linked and strong.**

  ```
  $ arm-buildroot-linux-gnueabihf-nm output/build/uboot-2026.07/spl/u-boot-spl | grep raw_sector
  ffff0154 T board_spl_mmc_get_uboot_raw_sector
  ffff1682 W spl_mmc_get_uboot_raw_sector
  ```

  Note the second line. Mainline's fallback is a **three-hop** weak chain
  (`spl_mmc_get_uboot_raw_sector` → `board_spl_mmc_get_uboot_raw_sector` →
  `arch_spl_mmc_get_uboot_raw_sector`, `common/spl/spl_mmc.c:322/:316/:310`), so a `W`
  symbol whose name contains `raw_sector` is present with *or without* this patch. **An
  assertion must match `T board_spl_mmc_get_uboot_raw_sector` exactly** — a bare grep for
  `raw_sector` passes on a broken build. This is the note U3's hook has to honour.

* **0002 — exFAT links and is in the image.** `CONFIG_FS_EXFAT=y` builds and links (the
  whole build is exit 0, which it could not be with the unresolved `__aeabi_ldivmod`), and
  `strings output/images/u-boot.bin` carries `EXFAT`, `exfat` and
  `unsupported exFAT version: %hhu.%hhu`.

* **0003 — the fork's handoff tables are in our SPL.** §5, the handoff-equality gate.

* **0004 — `mt` exists with stock's help string.** `nm` shows `0100eb34 t do_mem_mt`, the
  parity check finds `mt` in the built command table (§4 block 5), and the built binary
  carries the string `memory test against value`, which is byte-for-byte what the stock
  blob carries.

* **0005 — `arch_early_init_r()` reaches the release path.** Disassembly of the built
  U-Boot proper shows both calls, the pristine one and the added one:

  ```
  100278a:  2001        movs  r0, #1
  100278c:  f000 f8d8   bl    1002940 <socfpga_bridges_reset>
   …
  100279a:  2000        movs  r0, #0
  100279c:  f000 f8d0   bl    1002940 <socfpga_bridges_reset>
  ```

  The second is the patch: `socfpga_bridges_reset(0)` as the last statement of
  `arch_early_init_r`, which is the fork's warm-reboot behaviour. The equivalence argument
  is in the patch header and in plan §3.3; **what it does on a board is [U]** (§8).

---

## 3. The resolved `.config` — every symbol U3 will assert

Read out of `output/build/uboot-2026.07/.config` *after* the fragment merge and
`olddefconfig`, which is the only file that tells the truth (the fragment is a request; the
board defconfig, the Kconfig defaults and Buildroot's own fixups all get a say). Plan §5
step 2's list, plus the four the task adds **[V]**:

```
CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE=y
CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION_TYPE=0xa2
# CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_SECTOR is not set
CONFIG_FS_EXFAT=y
CONFIG_ENV_IS_IN_MMC=y
CONFIG_ENV_OFFSET=0x200
CONFIG_ENV_SIZE=0x1000
CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE=y
CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="…/board/mister/de10nano/uboot.env"
CONFIG_TEXT_BASE=0x01000040
CONFIG_SPL_PAD_TO=0x10000
CONFIG_ARCH_SOCFPGA_GEN5=y
CONFIG_CMD_MEMORY=y
```

and the rest of the fragment's deltas, for completeness:

```
CONFIG_BOOTDELAY=0
CONFIG_AUTOBOOT_KEYED=y
CONFIG_AUTOBOOT_STOP_STR="\e"
CONFIG_SYS_BOOTM_LEN=0x4000000
# CONFIG_TOOLS_MKEFICAPSULE is not set
# CONFIG_SPL_SPI is not set
# CONFIG_SPL_DM_SPI is not set
CONFIG_CMD_UNZIP=y
CONFIG_LOOPW=y
CONFIG_CMD_MEMINFO=y
```

**Four symbols are ABSENT from the resolved `.config` rather than set to `n`**, and an
assertion that string-matches `# CONFIG_X is not set` on any of them fails on a correct
build:

| Symbol | Why it vanishes |
|---|---|
| `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR` | `depends on …USE_SECTOR` (`common/spl/Kconfig:581`) — this is what plan §3.1 means by "the SECTOR symbol disappears outright", and it is what makes a double-count to `+0x400` unreachable |
| `CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_DATA_PART_OFFSET` | same dependency (`:598`) |
| `CONFIG_SPL_SPI_FLASH_SUPPORT` | `depends on SPL_SPI` (`:1539`) |
| `CONFIG_SPL_SPI_LOAD` | inside `if SPL_SPI_FLASH_SUPPORT` (`:1548-1579`, symbol at `:1573`) |

`CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE` deserves a note of its own: it is **not** in the
fragment and cannot be. Buildroot writes it, and the absolute path beside it, from
`BR2_TARGET_UBOOT_DEFAULT_ENV_FILE` in `UBOOT_KCONFIG_FIXUP_CMDS` — *after* the fragments
are merged and *before* `olddefconfig`. Resolving the fragment on its own leaves it `is not
set`; only the real Buildroot build produces the `=y` above. Any check of that symbol must
therefore run inside the build, not against the fragment.

### The merge dropped nothing

`merge_config.sh` reports a "Value of … is redefined" block per changed symbol and would
report a dropped one; fifteen blocks appeared, one per directive that actually changes
something — twelve for the fragment as staged by U2e plus three for §4b's block 10 — with
no other diagnostics (`grep -c 'is redefined by fragment'` on the final build's log → `15`;
the first build, before block 10, showed `12`). The three deliberate restatements
(`ENV_IS_IN_MMC`, `TEXT_BASE`, `CMD_MEMORY`) produce no block precisely because they already
resolve to the written value — which is the drift alarm they exist to be. `olddefconfig`
emitted exactly one warning, the intended one:

```
.config:2141:warning: override: SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE changes choice state
```

---

## 4. `scripts/check-uboot-parity.sh` — the structural, environment and command-table gate

```
$ SPL_SIZE_LIMIT=$(output/build/uboot-2026.07/tools/spl_size_limit) \
  scripts/check-uboot-parity.sh \
      output/images/u-boot-with-spl.sfp \
      <stock>/uboot.img \
      output/build/uboot-2026.07/u-boot
```

Exit **0** **[V]**. Full transcript:

```
check-uboot-parity.sh: built  output/images/u-boot-with-spl.sfp (816000 bytes)
check-uboot-parity.sh: stock  .../uboot.img (515141 bytes)
check-uboot-parity.sh: elf    output/build/uboot-2026.07/u-boot

[1] legacy uImage header at 0x00040000
  stock: ih_size=252933 ih_load=0x01000040 ih_ep=0x00000000
ok   uImage magic 0x27051956 present at 0x00040000
  ih_name      = "U-Boot 2026.07 for de10-nano boa"
  ih_time      = 1788535000 (allowed diff: build timestamp)
  ih_size      = 553792  ih_load = 0x01000040  ih_ep = 0x01000040
  os/arch/type/comp = 17/2/5/0 (want 17/2/5/0 = U-Boot/ARM/firmware/none)
ok   uImage os/arch/type/comp match stock's IH_OS_U_BOOT/IH_ARCH_ARM/IH_TYPE_FIRMWARE/IH_COMP_NONE
ok   ih_load = 0x01000040 — the SPL of the fork jumps to ih_load (common/spl/spl.c:110)
ok   ih_ep = 0x01000040 (allowed diff: mainline sets CONFIG_TEXT_BASE, the fork leaves 0 — plan §3.3)
  mixing warning: a stock SPL reads ih_load, a mainline SPL reads ih_ep (common/spl/spl_legacy.c:57) — do not pair an SPL and a uImage from different builds
ok   total size closes the file: 0x00040000 + 64 + 553792 = 816000
ok   uImage header CRC recomputes: 0xbfe8e684
ok   uImage payload CRC recomputes over all 553792 bytes: 0x20beac5d

[2] SPL region: 4 copies of 65536 bytes
ok   SPL copy 1 at 0x00010000 is byte-identical to copy 0
ok   SPL copy 2 at 0x00020000 is byte-identical to copy 0
ok   SPL copy 3 at 0x00030000 is byte-identical to copy 0

[3] socfpga SPL header at +0x00000040 of copy 0
  validation=0x31305341 version=0 flags=0 length_u32=11600 (46400 bytes) zero=0 checksum=0x0172
ok   validation word 0x31305341 present — the BootROM will accept this SPL
ok   SPL header version/flags/zero are stock's 0/0/0
ok   header checksum recomputes: 0x0172 (socfpgaimage.c off-by-one reproduced)
ok   SPL payload length 46400 bytes is inside the 65536-byte slot (headroom 19136 bytes, 70% used)
ok   SPL payload CRC32 over [0,46396) recomputes: 0x54fe73cf (stored at +0x0000b53c)
ok   the rest of copy 0 (19136 bytes) is zero padding
ok   SPL payload 46400 <= SPL_SIZE_LIMIT 62752 (headroom 16352 bytes)

[4] default_environment[] parity
  stock env: payload offset 0x00028018, 1150 bytes, 21 entries (file offset 0x00068058)
ok   stock env is where plan §6 says it is: 0x00028018, 1150 bytes
  nm -S: default_environment at 0x0106cb70 size 1150 -> payload offset 0x0006cb30
  built env: payload offset 0x0006cb30, 1150 bytes, 21 entries (file offset 0x000acb70)
  located from the ELF symbol; the scan is only a cross-check
  scan: anchored on "bootcmd=" (1 match(es) in the payload), blob at 0x0006cac9, 1253 bytes, 31 entries
  the scan and the ELF disagree (0x0006cac9 vs 0x0006cb30) — the ELF wins; a scan-only run of this image would compare the wrong bytes
ok   environment is byte-identical to stock: 1150 bytes, 21 entries (`mt` carried, plan §3.4 — no allowed delta)

[5] command table
  stock: 69 entries at payload offset 0x00033410, stride 28 (allowed diff: offset and stride)
  built: 112 entries at payload offset 0x00070f6c, stride 28
ok   all 69 stock command names are present (112 total in the build)
ok   `mt` is present — stock's fpgacheck runs unmodified (plan §3.4)
  extra commands, allowed: [ bind blkcache bootefi bootelf bootflow bootp bootvx chpart dfu dhcp eficonfig ext2load ext2ls fatmkdir fatrm fatwrite fstypes gpio i2c iminfo imxtract ln mdio mii mkdir mtdparts mv net panic part ping pxe random rm sf sspi sysboot tftpboot ums unbind usb usbboot

[6] allowed diffs (plan §6): version string and build timestamp; uImage
    ih_ep 0x01000040 vs 0x00000000; total image size; code layout and
    table offsets inside the SPL; extra commands. Everything else above is
    a hard contract.
check-uboot-parity.sh: parity holds
```

### 4a. The environment, proved a second way

The script locates the built blob from the ELF symbol; here is the same claim made
independently, straight out of the two files with `dd` **[V]**:

```
$ dd if=<stock>/uboot.img      bs=1 skip=$((0x68058)) count=1150 of=stock.env.bin
$ dd if=output/images/u-boot-with-spl.sfp bs=1 skip=$((0xACB70)) count=1150 of=built.env.bin
$ cmp stock.env.bin built.env.bin            # silent
$ sha256sum stock.env.bin built.env.bin
f8c20f3e07669b258adc20d47f68a3ec6b5c21c81cabb2971f999364cd0fef54  stock.env.bin
f8c20f3e07669b258adc20d47f68a3ec6b5c21c81cabb2971f999364cd0fef54  built.env.bin
$ tr '\0' '\n' < built.env.bin | grep -c .
21
```

**1,150 bytes, 21 entries, byte-identical** — including the malformed entry 15
(`bootm $loadaddr - $fdt_addr`, no `=`), which is the fingerprint boot-chain §3.1 traces
into `himport_r()`'s "no `=` before the NUL" branch. Because `mt` is carried (plan §3.4)
there is no allowed environment delta at all: the comparison is a plain `cmp`, not a
delta list.

Two offsets worth pinning down, because both plan §6 and `docs/uboot-tasks.md` write them
loosely as "`0x28018` of the stock `uboot.img`": `0x28018` is the offset **into U-Boot
proper**. In `uboot.img` the same bytes are at **`0x68058`** — `0x28018` plus the image's
prefix of four 64 KiB SPL copies (`0x40000`) and the 64-byte legacy uImage header. The
check script has this right (its header says so explicitly); the plan and task text are the
ones that need the wording fixed. **[U] for task U8** — it is not in this task's file scope.

### 4b. Four stock commands mainline did not have

The first parity run against a real build failed:

```
FAIL 4 of stock's 69 commands are missing: gzwrite loopw meminfo unzip
```

Plan §6 lists "a missing command from stock's 69-entry table" among the **forbidden**
diffs (extras are allowed, absences are not), so this was closed rather than excused.
All four commands exist in mainline v2026.07 and were simply off in the board defconfig;
`CONFIG_CMD_UNZIP=y` (which builds `cmd/unzip.o`, carrying **both** `unzip` and `gzwrite`
— there is no separate `GZWRITE` symbol in this tree), `CONFIG_LOOPW=y` and
`CONFIG_CMD_MEMINFO=y` were added to the fragment as block 10, with the reasoning in the
fragment itself. All three live in `cmd/`, i.e. in U-Boot proper, so the SPL payload is
unchanged by them (46,400 B before and after) and the `.sfp` grew by 2,576 B.

This is a genuine change of scope relative to task U2e, which was told not to *strip*
mainline's extras and quite reasonably did not anticipate mainline being *short*. Nothing
in stock's environment calls any of the four; the reason to carry them is parity with the
shipped table, which is this port's specification.

---

## 5. `scripts/check-uboot-handoff.sh` — the QTS handoff-equality gate

This is the check for the one silent-brick delta a cold-boot smoke test could not catch:
the build picking up mainline's `qts/*.h` instead of the carried fork ones (plan §3.2a).
It packs the seven handoff tables out of the headers **in the patched build tree** and
asserts each byte string is present in SPL copy 0 of both images. Offsets are reported,
never compared — they are code layout.

```
$ scripts/check-uboot-handoff.sh \
      output/build/uboot-2026.07/board/terasic/de10-nano/qts \
      output/images/u-boot-with-spl.sfp \
      <stock>/uboot.img
```

Exit **0** **[V]**:

```
check-uboot-handoff.sh: qts-dir=output/build/uboot-2026.07/board/terasic/de10-nano/qts
check-uboot-handoff.sh: image-a=output/images/u-boot-with-spl.sfp
check-uboot-handoff.sh: image-b=.../uboot.img
ok   sys_mgr_init_table @ 0x0a63c in output/images/u-boot-with-spl.sfp (207 bytes, 207 elements)
ok   sys_mgr_init_table @ 0x0aac8 in .../uboot.img (207 bytes, 207 elements)
ok   iocsr_scan_chain0_table @ 0x091a4 in output/images/u-boot-with-spl.sfp (96 bytes, 24 elements)
ok   iocsr_scan_chain0_table @ 0x096b8 in .../uboot.img (96 bytes, 24 elements)
ok   iocsr_scan_chain1_table @ 0x09204 in output/images/u-boot-with-spl.sfp (216 bytes, 54 elements)
ok   iocsr_scan_chain1_table @ 0x09718 in .../uboot.img (216 bytes, 54 elements)
ok   iocsr_scan_chain2_table @ 0x092dc in output/images/u-boot-with-spl.sfp (120 bytes, 30 elements)
ok   iocsr_scan_chain2_table @ 0x097f0 in .../uboot.img (120 bytes, 30 elements)
ok   iocsr_scan_chain3_table @ 0x09354 in output/images/u-boot-with-spl.sfp (2096 bytes, 524 elements)
ok   iocsr_scan_chain3_table @ 0x09868 in .../uboot.img (2096 bytes, 524 elements)
ok   ac_rom_init @ 0x08d70 in output/images/u-boot-with-spl.sfp (144 bytes, 36 elements)
ok   ac_rom_init @ 0x090f8 in .../uboot.img (144 bytes, 36 elements)
ok   inst_rom_init @ 0x08fa8 in output/images/u-boot-with-spl.sfp (508 bytes, 127 elements)
ok   inst_rom_init @ 0x094bc in .../uboot.img (508 bytes, 127 elements)
  14 found, 0 missing (7 tables x 2 images = 14 checks expected)
check-uboot-handoff.sh: all seven handoff tables present in SPL copy 0 of both images
```

Every stock-side offset reproduces plan §3.2a's table exactly. The built-side offsets
differ, as they must — nine years of code layout.

### 5a. The negative run — why this gate is not vacuous

A check that passes on everything proves nothing, so `scripts/test-uboot-handoff.sh` runs
the same gate with **pristine mainline's** `qts/*.h` (extracted fresh from the pinned
tarball at run time) against the same stock blob, and requires it to **fail**. It does,
naming exactly the four tables plan §3.2 says diverged and still finding the three that
never did **[V]** (the `qts-dir=` line names a `mktemp` directory and therefore varies
between runs; everything else is deterministic):

```
check-uboot-handoff.sh: qts-dir=<tmp>/u-boot-2026.07/board/terasic/de10-nano/qts
check-uboot-handoff.sh: image-a=.../uboot.img
check-uboot-handoff.sh: image-b=.../uboot.img
FAIL sys_mgr_init_table NOT FOUND in .../uboot.img (207 bytes, 207 elements packed)
FAIL sys_mgr_init_table NOT FOUND in .../uboot.img (207 bytes, 207 elements packed)
FAIL iocsr_scan_chain0_table NOT FOUND in .../uboot.img (96 bytes, 24 elements packed)
FAIL iocsr_scan_chain0_table NOT FOUND in .../uboot.img (96 bytes, 24 elements packed)
FAIL iocsr_scan_chain1_table NOT FOUND in .../uboot.img (216 bytes, 54 elements packed)
FAIL iocsr_scan_chain1_table NOT FOUND in .../uboot.img (216 bytes, 54 elements packed)
FAIL iocsr_scan_chain2_table NOT FOUND in .../uboot.img (120 bytes, 30 elements packed)
FAIL iocsr_scan_chain2_table NOT FOUND in .../uboot.img (120 bytes, 30 elements packed)
ok   iocsr_scan_chain3_table @ 0x09868 in .../uboot.img (2096 bytes, 524 elements)
ok   iocsr_scan_chain3_table @ 0x09868 in .../uboot.img (2096 bytes, 524 elements)
ok   ac_rom_init @ 0x090f8 in .../uboot.img (144 bytes, 36 elements)
ok   ac_rom_init @ 0x090f8 in .../uboot.img (144 bytes, 36 elements)
ok   inst_rom_init @ 0x094bc in .../uboot.img (508 bytes, 127 elements)
ok   inst_rom_init @ 0x094bc in .../uboot.img (508 bytes, 127 elements)
  6 found, 8 missing (7 tables x 2 images = 14 checks expected)
check-uboot-handoff.sh: HANDOFF MISMATCH — 8 table/image pair(s) missing, named above
```

`test-uboot-handoff.sh` itself exits 0 — both fixtures behaved as documented, the positive
one finding all seven at plan §3.2a's offsets **[V]**.

**What this gate cannot see**, restated from the script's own header so the gap is on the
record: the QTS **scalar** `#define`s — `CFG_HPS_SDR_CTRLCFG_FPGAPORTRST`, the two s2f PLL
counts, `REG_FILE_INIT_SEQ_SIGNATURE` — compile to instruction immediates and are not
greppable. They rest on the source diff of plan §3.2 plus `qtsdiff.py`'s two runs recorded
in patch 0003's header **[V by source, U by binary]**.

---

## 6. SPL size and headroom

| | Bytes |
|---|---|
| `spl/u-boot-spl.bin` | **46,386** |
| SPL payload as the socfpga header counts it (`length_u32` × 4) | 46,400 |
| 64 KiB SPL slot | 65,536 |
| `tools/spl_size_limit` (the link-time limit `SPL_SIZE_CHECK` enforces) | 62,752 |
| free in the slot | **19,136 (29.2 %)** |
| free against the link limit | **16,352 (26.1 %)** |

Plan §3.5's target was "12.6 % → 30.4 % of the 64 KiB slot" after dropping the unused SPL
SPI/QSPI stack, measured on 2026.04. This build lands at **29.2 %** on the same metric: the
direction and the magnitude both reproduce, the last point is a 2026.07-vs-2026.04
difference, not a regression. Stock's own SPL is 45,820 B, i.e. 30.1 % slot-free, so the
margin is now within a point of stock's **[V]**.

Two things this buys, both of them plan §3.5's argument:

* Mainline enforces `SPL_SIZE_CHECK` at **build** time. The 2017.03 fork does not:
  `tools/socfpgaimage.c:218-225` guards with no `else`, so an oversized SPL prints
  "Not a sane SOCFPGA preloader", **exits 0**, and writes a header with a `length_u32`
  truncated through a `uint16_t`. Choosing mainline closes that silent-corruption window.
* The `0xA2` partition is 4 MiB in our own `board/mister/de10nano/genimage-sdcard.cfg`, so
  the 816,000 B `.sfp` fits with room. What size **mr-fusion and the Windows SD installer**
  create is still open (plan §9), and `updateboot` `dd`s with no size check **[U]**.

---

## 7. Every allowed diff, enumerated and explained

Plan §6 names these; each is present in this build and each is here on purpose.

| # | Diff | Stock | Built | Why it is allowed |
|---|---|---|---|---|
| 1 | Version string | `U-Boot 2017.03+ (Apr 02 2025 - 20:16:03 +0800)` | `U-Boot 2026.07 (Sep 04 2026 - 15:16:40 +0000)` | The whole point of the port. Nothing in the boot path parses it. |
| 2 | uImage `ih_time` | 2025-04-02 | `1788535000` | Build timestamp, fixed by `BR2_REPRODUCIBLE`'s `SOURCE_DATE_EPOCH` rather than the wall clock — so it is stable, not merely tolerated. |
| 3 | uImage `ih_ep` | `0x00000000` | `0x01000040` | Mainline sets it from `CONFIG_SYS_UBOOT_START`; the fork leaves it 0. **Each build is self-consistent, but the two SPLs read different fields** — the fork's uses `ih_load` (`common/spl/spl.c:110`), mainline's uses `ih_ep` (`common/spl/spl_legacy.c:57`). See the hazard below. |
| 4 | Total size | 515,141 B | 816,000 B | Nine years of U-Boot, and mainline's `EFI_LOADER`/`NET`/`USB` still on. Fits the 4 MiB `0xA2` partition with room (§6). |
| 5 | `ih_size` / U-Boot proper | 252,933 B | 553,792 B | Same reason. |
| 6 | Code layout, table offsets in the SPL | — | — | Presence and byte-equality are the contract (§5); position is not. |
| 7 | Command table offset and stride | `0x33410` | `0x70f6c` | Same. Stride is 28 in both, incidentally. |
| 8 | 43 extra commands | — | listed in §4 block 5 | Plan §6 allows extras explicitly; **removing** them is the risk, since stock's environment might call one. |

**Forbidden, and none of them occurred [V]:** any environment byte; a missing command from
stock's 69; any handoff table absent from or differing in the built SPL; any layout change
of the four SPL copies or the uImage; a load-address change; any SPL header field change;
`USE_SECTOR` reappearing.

### The `ih_ep`/`ih_load` mixing hazard — read this before flashing anything partially

Diff 3 is not cosmetic and it is the one that can brick a card with two individually
correct files. **A stock SPL paired with our `uboot.img`-shaped payload, or our SPL paired
with stock's, jumps to the wrong address** — stock's SPL reads `ih_load` (which we set
correctly, so that direction survives), but *our* SPL reads `ih_ep`, which stock leaves
`0x00000000`. Our SPL + stock's U-Boot proper therefore branches to `0x0`.

The rule is: **the `.sfp` is atomic.** Never flash part of one build over part of another.
`updateboot` already writes the whole blob, and `scripts/mk-sdcard.sh` writes the whole
stock `uboot.img`, so nothing in this repo does the dangerous thing today — but a recovery
procedure invented under pressure with a card reader might, and this is where it is
written down. The parity script prints the same warning on every run.

---

## 8. What only hardware can show

Nothing in this file was observed on a board, and nothing in it can be. These are the
claims the desk cannot settle **[U]** — the DE10 hardware gate (task U6) is deferred
indefinitely, not waived, and the list below is its agenda.

1. **That it boots at all.** The SPL is structurally valid and the BootROM's acceptance
   criteria (validation word, checksum, length) are checked byte-for-byte — but "the
   BootROM accepts this header" is not "DDR calibrates". Which leads to:
2. **That a 2026 gen5 SPL consuming the fork's 2017 handoff data calibrates this board's
   DDR3.** §5 proves the *data* our SPL carries is the data stock's SPL carries; the
   sequencer *code* consuming it has nine years of upstream change. Plan §3.2a is explicit
   that this narrows the risk rather than removing it.
3. **The scalar handoff values.** `FPGAPORTRST=0x3FFF` releases 14 FPGA→SDRAM port resets
   where mainline's `0x1FF` releases 9; the two s2f user-clock counts differ. These are not
   greppable in a binary (§5), so only a running core that uses SDRAM through the fabric
   exercises them.
4. **Patch 0005's three boot claims** (plan §3.3): that a fabric-preserving warm reset
   actually reaches `arch_early_init_r` with the FPGA reporting user mode; that a core
   stays reachable from Linux across it; and that cold boot still loads `menu.rbf`
   unchanged. The equivalence argument is source-level and is the deliverable; the
   behaviour is not observable here. `objdump` proving the call is emitted (§2) is a much
   weaker claim than "the warm-reboot path works".
5. **`mt`'s runtime exit-status sense inside `fpgacheck`.** The command is present with
   stock's help string and stock's environment calls it unmodified, and the sandbox
   transcript in patch 0004's header exercises the hush `if` both ways — but not on this
   silicon against the real `0x1FFFF000` mailbox (boot-chain §6.1/§6.3).
6. **exFAT reads.** `CONFIG_FS_EXFAT` links and the driver is in the image; that
   `load mmc 0:1 … /linux/zImage_dtb` succeeds off a real exFAT partition formatted by our
   installer is untested.
7. **`CONFIG_SYS_BOOTM_LEN` and `bootz`.** Plan §9 Q6 — whether `bootz` on a raw
   self-decompressing zImage consults the symbol at all — is **still open**. The fragment
   sets stock's 64 MiB, which can only widen a bound, and says in its own text that it does
   not close the question.
8. **Whether anything in the SPL touches `0x1FFFF000`–`0x1FFFFFFF`** (the warm-reboot
   mailbox, boot-chain §6.3) before U-Boot proper reads it. Not checked here; on task U9's
   list.

Until those are answered, the honest status of this artifact is exactly what ADR 0024 says:
**a buildable, checkable capability that ships nowhere.**

---

## 9. Integration notes and open advisory items

Findings the wave-A verifiers raised against files integrated here. The factual ones were
fixed in place during integration; the rest are recorded so they are not lost.

**Fixed here [V]:**

* `uboot.fragment` — an 81-column line rewrapped; the two `merge_config.sh` copies'
  differences stated completely (they also differ in a rewrap of the usage text);
  `common/spl/Kconfig:587` quoted in full (`default 0x200 if ARCH_SOCFPGA_GEN5 || ARCH_AT91`).
* `uboot.env` — the `filechk_defaultenv.h` sed described exactly (`s/\\\x0\s*//g` also
  swallows whitespace after the backslash-NUL).
* Patch 0001 — the weak fallback is a **three**-hop chain, not two, and the header now says
  so and spells out the consequence for U3's assertion (§2).
* Patch 0002 — U-Boot does not "link no libgcc division routine": it carries
  `__aeabi_uldivmod` in `arch/arm/lib` and lacks the **signed** `__aeabi_ldivmod`, which is
  what a signed `time_t` pulls in. Corrected in both the commit message and the in-code
  comment (line count preserved, so the hunk header is unchanged).
* Patch 0003 — the checkpatch totals in the `[V]` bracket were not reproducible from the
  deliverable; restated as the reproducible 3E/7W/0C → 3E/3W/0C, with the substantive claim
  (four "Misplaced SPDX" warnings before, zero after) unchanged.
* Patch 0004 — the fork's remote is `MiSTer-devel/U-Boot_MiSTer`, not
  `MiSTer-devel/Buildroot-MiSTer`.
* Patch 0005 — `[PATCH 5/5]` → `[PATCH]`, matching its four siblings and surviving a
  reorder; `fpgamgr_test_fpga_ready()`'s **function body** is character-identical, the
  files are not; the `--follow` commit count corrected to 33/71.
* Patches 0003 and 0005 — the diff bodies used bare `--- a/`/`+++ b/` framing with no
  `diff --git`/`index` lines, unlike 0001/0002/0004. Framed uniformly now; the `index`
  blob ids were produced by `git apply --index` + `git diff --cached` of each patch on the
  pristine 2026.07 files, not typed in. Applies identically (the rebuild below is the proof).
* Patch 0004 — line 1 read `From 0000000000000000000000000000000000000000`; now carries the
  fork's origin commit `c0ed23f52e203d704c0b149408f2cc0b1bb48939` like the 0003/0005
  siblings (`git -C work/U-Boot_MiSTer cat-file -t` → `commit`).
* Patches 0001 and 0002 — `docs/uboot-tasks.md` (U2a) wants the header to say the literal
  "to be submitted upstream (U7)"; the phrase now appears in both `Upstream status:`
  fields, still followed by the "drafted by U7-prep, NOT sent, owner decision 4" sentence
  and the note that U7 is "send, on the owner's go only".
* `uboot.env` — its `Disposition:` field said it was paired with the *fragment's*
  `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE=y`; the fragment deliberately does not contain that
  symbol (§3). Reworded to say Buildroot's `UBOOT_KCONFIG_FIXUP_CMDS` writes it from
  `BR2_TARGET_UBOOT_DEFAULT_ENV_FILE` and the fragment owns only the storage side. Comment
  lines only — the built blob is unchanged (§4a).

**Open [U]:**

* **`Signed-off-by: Sorgelig` on patches 0003/0004/0005.** The fork commits they carry have
  no sign-off (`git log -1 --format=%B dadd1c8978` is a single line), so the trailer attests
  a DCO the author never gave. The repo's existing fork-origin kernel patches are
  inconsistent about this (`linux-patches/0001` and `0018` add it, `0002` does not). This is
  a repo-wide template question, not a defect of any one patch — **owner's call**; left as
  staged rather than decided unilaterally here.
* **`0x28018` vs `0x68058`.** Plan §6 and `docs/uboot-tasks.md` describe the stock
  environment blob's offset as "of the stock `uboot.img`"; it is the offset into U-Boot
  proper (§4a). For task U8; both files are outside this task's scope.
* **Plan §3.1 row 1 says the unselected raw-mode default lands at absolute LBA `0x400`.**
  In the pinned v2026.07 tree it is `0x200` (`common/spl/Kconfig:587`, and the baseline
  `.config`). The nature of the delta is unchanged; the number is wrong. For task U9 or
  whoever owns the plan.
* **Plan §3.1 row 3 cites `fs/fat/fat.c:68-95`** for the FAT-type rejection; in v2026.07 it
  is `:223-226`. Same class.
* **Plan §3.1 row 2 cites `origin/main` at `134ad3c3c0`**; that object does not exist in the
  local mirror, whose head is `5c215cb75c` ("Prepare v2026.10-rc1", 2026-07-27) and still
  carries the dead guard. The patch header cites `5c215cb75c` correctly.
* **Patch 0004's checkpatch findings** (4 errors / 3 warnings / 1 check under `--strict`)
  are carried verbatim from the fork's 2017 C and are documented as deliberately kept. The
  patch is never mailed, so this is a note rather than a debt.
* **`scripts/test-uboot-parity.sh`'s `repair_dcrc` fixture helper** re-stamps the uImage
  payload CRC but not the header CRC, so two of its fixtures also emit a header-CRC failure
  they do not assert on. Exit codes and asserted messages are unaffected. Owner of the
  fixture script (task U4a/U5).
* **`uboot.env` carries no `Signed-off-by` footer.** It has CONTRIBUTING §2's four content
  fields (Origin / Author-copyright / Upstream status / Disposition), but §2 is written for
  kernel patches and this is an environment text file, so whether such files need a
  sign-off line is the owner's call, not decided here.
* **"the ELF symbol is 1,151 bytes"** (`docs/uboot-tasks.md`, plan §6) does not hold on the
  `CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE` path: `nm -S` gives `0x47e` = 1,150, because
  `xxd -i` emits a byte-list initialiser with no implicit string terminator. 1,151 is what
  the `CONFIG_EXTRA_ENV_SETTINGS` string-literal path (stock, and the 2026.04-era scratch
  builds) yields. The 1,150-byte comparison in §4/§4a is the right one; the two docs are
  outside this task's scope → U8.
* **`docs/init-parity.md:134`** cites `patches/uboot/.gitkeep` as an example of the marker
  convention. The directory now exists and holds real patches, so the example should cite
  `linux-patches/.gitkeep` instead. For task U8.
* **`scripts/ci-tests.sh` has no DE10 U-Boot section yet** — it asserts nothing about
  `images/u-boot-with-spl.sfp` existing, about `images/uboot.img` **not** existing, or about
  the release stage carrying no `.sfp`. That is task U5's deliverable; recorded here so the
  gap is visible in the meantime.

---

## 10. Reproducing this

From the repository root, as in §1 — the repo `Makefile`'s catch-all rule
(`%: $(BR_STAMP) hostshim`) forwards every Buildroot goal with `work/.hostshim` on `PATH`,
which is what keeps Buildroot 2026.x's `install` calls away from the uutils `install`
(`make -C output …` directly skips that shim):

```
make mister_de10nano_defconfig
make BR2_JLEVEL=12 uboot-dirclean uboot

# plan §6, both halves
SPL_SIZE_LIMIT=$(output/build/uboot-2026.07/tools/spl_size_limit) \
  scripts/check-uboot-parity.sh \
      output/images/u-boot-with-spl.sfp <stock>/uboot.img output/build/uboot-2026.07/u-boot
scripts/check-uboot-handoff.sh \
      output/build/uboot-2026.07/board/terasic/de10-nano/qts \
      output/images/u-boot-with-spl.sfp <stock>/uboot.img

# the gates' own fixtures, including §5a's negative run
STOCK_UBOOT_IMG=<stock>/uboot.img scripts/test-uboot-handoff.sh
scripts/test-uboot-parity.sh <stock>/uboot.img
```

`<stock>/uboot.img` is the hash-pinned blob `scripts/fetch-sdcard-payload.sh` fetches
(`STOCK_UBOOT_SHA256`), sha256 `e2d46cf9…62a64`.

If a Buildroot bump moves `BR2_TARGET_UBOOT_LATEST_VERSION` off 2026.07, expect the patches
to need refreshing and **expect this file's hashes to change**; the two check scripts, not
the hashes, are what has to stay green.

---

## 11. U9 — adversarial review of the integrated artifact (2026-09-14)

Task U9 (`docs/uboot-tasks.md`): read and test the integrated build against plan §8's
failure taxonomy — *can the built `.sfp` present as a boot on a board while being wrong?* —
and leave no finding unlabelled. Inputs: the carried patches, the fragment and environment,
`output/images/u-boot-with-spl.sfp` and `output/build/uboot-2026.07/` (ELF, `.config`,
`spl/`), the stock blob (`e2d46cf9…62a64`), the fork at `work/U-Boot_MiSTer` (`8dcc3484`,
read only), the mainline mirror at `/mnt/source/uboot-mainline/mainline-board-support/u-boot.git`,
and task U2c's sandbox binary (`/mnt/source/uboot-wave-a/U2c/u-boot-2026.07/u-boot`, v2026.07
+ patch 0004, `CONFIG_HUSH_OLD_PARSER=y` — the same parser the DE10 `.config` resolves).
Scratch: `/mnt/source/uboot-wave-a/U9/`. Every claim is **[V]** (observed, where stated) or
**[U]** (unverified, missing input named); nothing here was observed on a board.

**Two findings changed the artifact or the record; everything else held.** One fix was
applied (patch 0006, §11.2) and the tree rebuilt, so **§1's hashes and §2's five-patch table
predate this section** — the current values are in §11.2. Summary:

| # | Attack | Result |
|---|---|---|
| 11.1 | (a) the bridge argument, cold and warm | holds; one caller the census missed, inert; one ordering delta in `bridge enable`, inert **[V by source]** |
| 11.2 | (b) effective env ≠ compiled env | **FOUND and FIXED**: no `CFG_SYS_BOOTMAPSZ`, DTB relocated above `mem=511M` → patch 0006 |
| 11.3 | (b) hush / `env import` / storage | hold, **by execution** in the 2026.07 sandbox |
| 11.4 | (b) watchdog | **FOUND, [U]**: stock hands Linux a running 30 s watchdog, this build hands it a stopped one — not trivial, recorded for the owner |
| 11.5 | (c) SPL and the mailbox | nothing CPU-side touches `0x1FFFF000–0x1FFFFFFF` **[V by source + link map]**; DDR retention across the reset stays hardware-only, as on stock |
| 11.6 | (d) the `ih_ep`/`ih_load` hazard | documented in the plan, this file and the parity script; **absent from `docs/boot-chain.md`, `README.md`, `mk-sdcard.sh`, `check-sdcard.sh`** → [U] for U8/owner |
| 11.7 | (e) the QTS handoff | gate rerun, exit 0; **the scalars are now proven by binary** — the two structs that carry them (`sdram_config`, `cm_default_cfg`) and `io_config` are byte-identical in stock's SPL; `misc_config` and `rw_mgr_config` hold the same values in a different layout (corrected 2026-09-14, see 11.7) |
| 11.8 | (f) `mt` exit-status sense | identical instruction sequence in stock's binary and ours |
| 11.9 | (g) SPL size | 46,386 B against 62,752 B, check wiring confirmed; the BootROM's own limit is [U] |

### 11.1 The bridge argument (patch 0005), cold boot and warm reboot

**Disassembly of the built `arch_early_init_r` [V]** (`objdump -d --disassemble=arch_early_init_r
output/build/uboot-2026.07/u-boot`, unchanged by patch 0006):

```
01002760 <arch_early_init_r>:
 1002760:	b538      	push	{r3, r4, r5, lr}
 1002766:	f7ff fda9 	bl	10022bc <socfpga_get_sysmgr_addr>
 100276a:	2400      	movs	r4, #0
 100276c:	4b0d      	ldr	r3, [pc, #52]	@ 0xae9efebc
 100276e:	4d0e      	ldr	r5, [pc, #56]	@ 0x01073060 = iswgrp_handoff[]
 1002770:	f8c0 30e0 	str.w	r3, [r0, #224]	@ warmramgrp_enable
 1002774:	f7ff fda2 	bl	10022bc <socfpga_get_sysmgr_addr>
 1002778:	3080      	adds	r0, #128	@ +0x80 = iswgrp_handoff regs
 100277a:	5903      	ldr	r3, [r0, r4]
 1002780:	3404      	adds	r4, #4
 1002782:	2c20      	cmp	r4, #32                @ 8 words cached
 1002784:	f845 3b04 	str.w	r3, [r5], #4
 1002788:	d1f4      	bne.n	1002774
 100278a:	2001      	movs	r0, #1
 100278c:	f000 f8d8 	bl	1002940 <socfpga_bridges_reset>   @ (1)
 1002790:	f7ff ffae 	bl	10026f0 <socfpga_sdram_remap_zero>
 1002796:	f7ff fd4f 	bl	1002238 <socfpga_fpga_add>
 100279a:	2000      	movs	r0, #0
 100279c:	f000 f8d0 	bl	1002940 <socfpga_bridges_reset>   @ (0) -- patch 0005
 10027a0:	2000      	movs	r0, #0
 10027a2:	bd38      	pop	{r3, r4, r5, pc}
```

The order is the fork's (`misc.c:356-404`): cache the eight handoff words, `reset(1)`,
remap, register the FPGA, `reset(0)`, return.

**Register end states, both trees, walked from source [V].** Read from the fork's
`spl.c`/`misc.c`/`reset_manager.c` and mainline's `spl_gen5.c`/`misc_gen5.c`/
`reset_manager_gen5.c` in the build tree. `brg` = rstmgr `brgmodrst` (+0x1c), `remap` = L3
`0xff800000`, `h[n]` = sysmgr `iswgrp_handoff[n]` (+0x80+4n).

| Point | Stock (fork) | This build (mainline + 0005) |
|---|---|---|
| SPL, early | `reset(1)`: `brg=0xffffffff` | `remap_zero`; `reset(1)`: `brg=7, remap=1` |
| SPL, after pinmux | **`reset(0)`** (`spl.c` "De-assert reset for peripherals and bridges based on handoff"): `h[0]=0, h[1]=0x19`; then the ready test — cold: return; warm: `brg=0, remap=0x19` | `socfpga_bridges_set_handoff_regs(true,true,true)`: `h[0]=7, h[1]=1` |
| SPL, SDRAM init | `h[3]=fpgaport_rst=0x3FFF`, `h[4]=rows` (`sdram.c:440-450`) | same (`sdram_gen5.c:461-472`) |
| SPL, end | `reset(1)`: `brg=0xffffffff` (remap untouched) | — |
| proper, `arch_early_init_r` | cache `h[0..7]` = `0, 0x19, …`; `reset(1)`; `remap=1`; `reset(0)`: cold → return, warm → `brg=0, remap=0x19` | cache `h[0..7]` = `7, 1, …`; `reset(1)`; `remap=1`; `reset(0)`: rewrites `h[0]=0, h[1]=0x19`, then cold → return, warm → `brg=0, remap=0x19` |
| `bridge enable` (cold path, `fpgaload`) | `fpgaintf_module=h[2]`; `apply_static_cfg`; `fpgaport_rst=h[3]`; `brg=cache[0]=0`; `remap=cache[1]=0x19` | `do_bridge_reset(1, ~0)`: `set_handoff_regs(false,false,false)` → `h[0]=0, h[1]=0x19`, **re-reads both into the cache**; `fpgaintf_module=h[2]`; `if (h[3]) { fpgaport_rst=h[3]; apply_static_cfg }`; `brg=0`; `remap=0x19` |

Both paths end with `brg=0`, `remap=0x19`, `fpgaport_rst=0x3FFF`, `fpgaintf_module` from the
pinmux — at cold boot after `fpgaload`, and at a warm reboot in the middle `fpgacheck` branch
where `fpgaload` never runs. Three things the U2d argument did not say, all checked here:

* **The fork's `socfpga_bridges_reset(0)` has a second caller, in the SPL** (`spl.c`, the
  "De-assert reset for peripherals and bridges" block, before `preloader_console_init`). The
  patch header's census ("no caller at all in a pristine v2026.07") is about mainline and is
  correct; the fork calls it twice. Consequences: on stock the SPL leaves `h[0]=0, h[1]=0x19`,
  on this build the SPL leaves `h[0]=7, h[1]=1`, so U-Boot proper's **cached** copies differ
  between the trees. Inert: the only consumer of the cached `[0]`/`[1]` on stock's env path is
  `do_bridge_reset(1, …)`, which reloads them (`misc_gen5.c:265-269`) after rewriting the
  registers; patch 0005's own `reset(0)` rewrites the registers too. The fork's SPL-time
  "FPGA not ready" `printf` at cold boot runs before `preloader_console_init` and is dropped;
  U-Boot proper's message is printed at the same point in both trees.
* **`bridge enable` orders `apply_static_cfg` differently**: the fork applies, then writes
  `fpgaport_rst`; mainline writes, then applies (and only `if (h[3])`). Inert here because
  `fpgaport_rst` already holds `0x3FFF` from the SPL's `sdram_write_verify` in both trees and
  `h[3] = 0x3FFF ≠ 0`; `bridge enable` rewrites the value the register already has, so the
  apply order cannot change the outcome. This closes the "`bridge enable` semantics changed"
  half of plan §3.3 that the 2026-09-14 revision left open — **for stock's environment** (mask
  `~0`); a `bridge enable <mask>` with a partial mask is mainline-only behaviour nothing here
  calls.
* **`h[2]` (`fpgaintf_module`) is populated identically**: `populate_sysmgr_fpgaintf_module()`
  is the same function line for line modulo accessor style (fork `system_manager.c:22-53`,
  mainline `system_manager_gen5.c:16-57`).
* **Linux reads exactly one handoff word**: `drivers/fpga/altera-fpga2sdram.c:116`
  (`SYSMGR_ISWGRP_HANDOFF3`, `0x8C`) in `output/build/linux-6.18.51`. That is `h[3]`, which
  both SPLs write from `cfg->fpgaport_rst` and which patch 0005 never touches. Nothing in
  `arch/arm/mach-socfpga` or the bridge drivers reads `h[0]`/`h[1]`.

**Still [U] (hardware):** that a Main_MiSTer cold reset (`rstmgr.ctrl = 1`, boot-chain §6.3)
reaches `arch_early_init_r` with `fpgamgr_test_fpga_ready()` true; that a core stays
reachable across it; that cold boot loads `menu.rbf`. Unchanged from §8 item 4.

### 11.2 Finding, FIXED — the DTB was relocated above `mem=511M` (patch 0006)

**The attack.** The environment `cmp` proves 1,150 bytes; it cannot see a `CONFIG_`/`CFG_`
symbol that changes what those bytes *do*. Walking stock's board headers
(`work/U-Boot_MiSTer/include/configs/socfpga_de10_nano.h`, `socfpga_common.h`) define by define
against the resolved `.config` and mainline's two headers found one boot-path define with no
mainline counterpart: **`CONFIG_SYS_BOOTMAPSZ (64 * 1024 * 1024)`** (`socfpga_common.h:18`
in the fork; `:22` at upstream `v2017.03`).

**What it does.** `bootz` relocates the flattened device tree before the jump
(`arch/arm/lib/bootm.c:158-164 boot_prep_linux` → `boot/image-board.c:929 image_setup_linux`
→ `boot/image-fdt.c boot_relocate_fdt`). With no `fdt_high` in the environment (stock has
none) the target is the highest free 4 KiB-aligned block below
`env_get_bootm_mapsize() + env_get_bootm_low()` (`image-fdt.c:221-247`, `LMB_MEM_ALLOC_MAX`).
`env_get_bootm_mapsize()` (`image-board.c:151-163`) returns `bootm_mapsize` if set, else
`CFG_SYS_BOOTMAPSZ` if defined, else `env_get_bootm_size()` = `bootm_size` if set, else
`gd->ram_size` capped at `gd->ram_top` — **1 GiB on this board** (no `board_get_usable_ram_top`
in `mach-socfpga` or `board/terasic/de10-nano`). The LMB's only reservation up there is
U-Boot's own (`lib/lmb.c:535-543`, `[start_addr_sp - CONFIG_STACK_SIZE, ram_top)`), so the DTB
would land immediately below U-Boot's stack, at roughly `0x3Bxxxxxx`: above the `mem=511M`
line, inside the half of DDR MiSTer cores own (boot-chain §6.4), and ~60 MiB from where every
stock boot has placed it (just under 64 MiB, `0x03FFxxxx`, via the fork's identical
`boot_relocate_fdt` + `getenv_bootm_mapsize()` at `common/image.c:512-526`).

**Why mainline lost it, and why the env cannot carry the replacement [V]**: mirror commit
`faea9e7a78` (Simon Goldschmidt, 2019-01-09, "arm: socfpga: remove CONFIG_SYS_BOOTMAPSZ")
deleted the define *and relied on* a new `bootm_size=0xa000000` entry in `socfpga_common.h`'s
default environment (`include/configs/socfpga_common.h:150` in v2026.07). This build replaces
that default environment wholesale with stock's 21 entries — byte-identical by owner decision —
so the entry is gone and the bound silently falls to the whole DRAM. **This is a behaviour the
environment-parity check is structurally unable to see.**

**Would it boot anyway?** Probably: the 6.18 kernel maps the DTB through the fixed FDT fixmap
(`arch/arm/kernel/head.S:304`, `arch/arm/mm/mmu.c:1385-1388`) and reserves it by physical
address (`arch/arm/kernel/setup.c:1108`), so a blob outside `mem=` is still parsed. But the
blob would then sit in fabric-owned DDR for the life of the system, and "mirror stock wherever
there is a choice" decides it. **[U]:** kernel behaviour with the DTB at either address was
not observed (no board; `test-initramfs.sh` boots the kernel without U-Boot).

**The fix.** `board/mister/de10nano/patches/uboot/0006-configs-socfpga-de10-nano-bound-the-linux-boot-map-at-64-mib.patch`
— ten lines added to `include/configs/socfpga_de10_nano.h`, one of them
`#define CFG_SYS_BOOTMAPSZ (64 * 1024 * 1024)`. The board header is the layer upstream itself
uses for the symbol (some 65 board headers under `include/configs/` in v2026.07 still define
it — 67 files counting `km/`); the value is stock's;
no environment byte changes. Full provenance header in the patch (origin `5095ee088d`, 2014;
removal `faea9e7a78`, 2019; disposition: carry, mirror stock; never upstream).

Applied and rebuilt here **[V]**:

```
$ patch -p1 -F0 -g0 --no-backup-if-mismatch -t -N --dry-run < 0006-*.patch   # pristine tarball header
checking file include/configs/socfpga_de10_nano.h
$ patch -p1 -F0 -g0 --no-backup-if-mismatch -t -N < 0006-*.patch             # output/build/uboot-2026.07
patching file include/configs/socfpga_de10_nano.h
$ scripts/lint-kernel-patches.sh board/mister/de10nano/patches/uboot
ok   0006-configs-socfpga-de10-nano-bound-the-linux-boot-map-at-64-mib.patch Michael C. Ferguson <michael.christopher.ferguson@gmail.com>
RESULT: PASS — all 6 patches in 1 series are `git am`-able.
$ timeout 590 make BR2_JLEVEL=12 uboot-rebuild      # exit 0
```

The flags are the ones Buildroot's `support/scripts/apply-patches.sh` uses, and the dry run
is against the header extracted from the pinned tarball, so the patch applies at fuzz zero on
the path Buildroot will take. **[U]:** a `make uboot-dirclean uboot` through Buildroot's own
extract/patch step was *not* run here (the tree was shared with U3/U5 at the time); the next
clean build is the observation.

`env_get_bootm_mapsize()` in the built ELF, before and after **[V]**:

```
before (u-boot sha256 8004117d…, .sfp 287201ee…):
 100494c:	b508      	push	{r3, lr}
 100494e:	4806      	ldr	r0, [pc, #24]	@ "bootm_mapsize"
 1004950:	f02c f848 	bl	10309e4 <env_get>
 1004954:	b918      	cbnz	r0, 100495e
 1004956:	e8bd 4008 	ldmia.w	sp!, {r3, lr}
 100495a:	f7ff bfd1 	b.w	1004900 <env_get_bootm_size>       <- whole-DRAM fallback
after:
 1004900:	b508      	push	{r3, lr}
 1004902:	4806      	ldr	r0, [pc, #24]	@ "bootm_mapsize"
 1004904:	f02c f848 	bl	1030998 <env_get>
 1004908:	b120      	cbz	r0, 1004914
 …
 1004914:	f04f 6080 	mov.w	r0, #67108864	@ 0x4000000          <- 64 MiB
```

A normalised whole-binary disassembly diff (addresses, PC-relative literals and raw opcode
bytes stripped; `/mnt/source/uboot-wave-a/U9/dis.diff`, 73 lines) shows exactly: that
function's body, the now-unreferenced `env_get_bootm_size()` dropped by the linker, three
size/offset literals that shifted by its 88 bytes, and one 8-byte alignment change. Nothing
else in U-Boot proper moved. `spl/u-boot-spl.bin` is **byte-identical** to the pre-patch
build (`cmp` silent; sha256 `ae00baa6…`).

Artifacts after patch 0006 **[V]** — these supersede §1's table:

| File | Size | sha256 |
|---|---|---|
| `output/images/u-boot-with-spl.sfp` | 815,896 B | `4bf59acf9fea2114b6c5186ef82e8386d7a20e62c3e0fd904b5fb573a9a15f97` |
| `output/images/u-boot.bin` | 553,688 B | `ce860693fa254b6e782d67d7ec803e674d8bc0342b5a6d458c14146f960ddc4b` |
| `output/build/uboot-2026.07/spl/u-boot-spl.bin` | 46,386 B | `ae00baa6fba3822e8035a7e510a6e38ba24babc9b7a6f8fa16b164136d2cbcd4` (unchanged) |

Both gates rerun against the rebuilt artifact, exit **0** and **0** **[V]**
(`/mnt/source/uboot-wave-a/U9/parity-after.txt`, `handoff-after.txt`):

```
  ih_size      = 553688  ih_load = 0x01000040  ih_ep = 0x01000040
ok   total size closes the file: 0x00040000 + 64 + 553688 = 815896
ok   uImage header CRC recomputes: 0x4e7469eb
ok   uImage payload CRC recomputes over all 553688 bytes: 0x7ed6e687
ok   SPL payload 46400 <= SPL_SIZE_LIMIT 62752 (headroom 16352 bytes)
ok   environment is byte-identical to stock: 1150 bytes, 21 entries (`mt` carried, plan §3.4 — no allowed delta)
ok   all 69 stock command names are present (112 total in the build)
check-uboot-parity.sh: parity holds
  14 found, 0 missing (7 tables x 2 images = 14 checks expected)
check-uboot-handoff.sh: all seven handoff tables present in SPL copy 0 of both images
```

The rebuild log also shows task U3's `UBOOT_POST_BUILD_HOOKS` audit (landed in `external.mk`
while this review ran) passing on the patched tree — informational, not relied on:
`MiSTer DE10 U-Boot resolved-.config audit (docs/uboot-mainline-port.md): PASS`.

### 11.3 The effective environment — everything else held, by execution

* **The compiled blob is the file and nothing else [V].** `include/env_default.h` wraps its
  entire compiled-in list — `bootargs`/`bootcmd`/…, `CONFIG_ENV_VARS_UBOOT_CONFIG`'s
  `arch=`/`cpu=`/`board=`/`vendor=`/`soc=`, `CFG_EXTRA_ENV_SETTINGS` (mainline's `bootm_size`
  lives there) — in `#ifndef CONFIG_ENV_USE_DEFAULT_ENV_TEXT_FILE`; the `#else` is only
  `#include "generated/defaultenv_autogenerated.h"`. `CONFIG_ENV_VARS_UBOOT_CONFIG=y` in the
  resolved `.config` therefore contributes nothing, which `nm -S` = 1,150 confirms. The one
  runtime-only extra is `fdtcontroladdr` (`common/board_r.c:458`); no stock variable has that
  name.
* **Storage mirrors stock exactly [V]** (`.config`): `ENV_IS_IN_MMC=y`, `ENV_OFFSET=0x200`,
  `ENV_SIZE=0x1000`, `ENV_MMC_DEVICE_INDEX=0`, `ENV_MMC_EMMC_HW_PARTITION=0`,
  `# ENV_MMC_USE_SW_PARTITION / ENV_MMC_USE_DT / ENV_REDUNDANT / ENV_OFFSET_RELATIVE_END /
  ENV_IS_NOWHERE … is not set`. No device-tree, partition-name or redundant-copy lookup can
  move it: the CRC is at card bytes 512–515 and `updateboot`'s `dd … seek=1 count=1` still
  destroys it (boot-chain §5 Consequence (b)).
* **hush: the same parser, the same `$` rule [V by source and execution].** Both trees run
  the old hush (`CONFIG_HUSH_OLD_PARSER=y`; `# CONFIG_HUSH_MODERN_PARSER is not set`), and in
  both the `isdigit` arm of `handle_dollar` is `#ifndef __U_BOOT__` (mainline
  `common/cli_hush.c:2848-2849`, fork `:2858-2859`), so `$5` is a literal `$` — which is what
  keeps `memmap=513M$511M` intact. Executed in the sandbox:

  ```
  => setenv mmcboot "setenv bootargs console=ttyS0,115200 \$v loop.max_part=8 mem=511M memmap=513M\$511M root=\$mmcroot loop=linux/linux.img ro rootwait;echo rc=would-bootz"; run mmcboot; printenv bootargs
  rc=would-bootz
  bootargs=console=ttyS0,115200 $v loop.max_part=8 mem=511M memmap=513M$511M root=$mmcroot loop=linux/linux.img ro rootwait
  ```

  (the sandbox has no `v`/`mmcroot` set in that run, hence the literal `$v`; on the board
  they expand as on stock.)
* **The 1,150 bytes import cleanly, malformed entry included [V by execution].** The exact
  stock blob (`work/uboot-proper.bin` @ `0x28018`) was written into sandbox memory word by
  word and imported in binary (NUL-separated) form, which is how `env_set_default()` consumes
  `default_environment[]`:

  ```
  => <288 x mw.l>; env import -d -b 0x200000 0x47e; echo rc=$?; printenv
  rc=0
  baudrate=115200
  bootargs=console=ttyS0,115200 $v loop.max_part=8 mem=511M memmap=513M$511M
  bootcmd=mw 0xff709004 0x800; run mmcload; run mmcboot
  … (19 variables, the two loadaddr= entries collapsed to one) …
  => printenv 'bootm $loadaddr - $fdt_addr'
  ## Error: "bootm $loadaddr - $fdt_addr" not defined
  ```

  Entry 15 is silently dropped by `himport_r`'s no-`=` branch, exactly as boot-chain §3.1
  traces for 2017.03.
* **`fpgacheck`'s three-way dispatch, by execution [V]** (mailbox mocked at `0x100000`/
  `0x100f08`, `fpgaload` stubbed to an echo; transcript `/mnt/source/uboot-wave-a/U9/sandbox.txt`):

  ```
  [warm flag + staged env]  ## Info: input data size = 23 = 0x17 / DISPATCH-fpgaload / core=menu.rbf foo=bar / both magics cleared (mt … 0 → rc=0)
  [warm flag, no staged env] core=zzz (untouched), no fpgaload, flag cleared
  [no warm flag]             DISPATCH-fpgaload, core=zzz, staged magic left in place
  ```

  `env import -t <addr>` with no size scans for `'\n'` then `'\0'` bounded by
  `MAX_ENV_SIZE` in both trees (mainline `cmd/nvedit.c:836-846`, fork `:1049-1066`,
  character-identical loop), so Main_MiSTer's `memset(…, 0, 0xF00)` terminator (boot-chain
  §6.3) works the same.
* **Autoboot [V by source]:** `bootcmd` is read from the environment (`common/autoboot.c:484`);
  `CONFIG_BOOTSTD=y` without `BOOTSTD_BOOTCOMMAND` never substitutes its own. Keyed stop:
  the empty `AUTOBOOT_DELAY_STR` cannot match (`:297`, `len > 0` guard). Cosmetic delta: the
  Kconfig default `AUTOBOOT_PROMPT="Autoboot in %d seconds\n"` is printed once per boot.
* **`mt` argument parsing [V]:** `cmd_get_data_size("mt", 4)` returns 4 with no suffix
  (`common/command.c:469-491`), `hextoul` accepts `0x…`; the command-table entry is
  `maxargs=3, repeatable=1` in both binaries.
* **Malloc arena:** `SYS_MALLOC_LEN=0x4000000` and `SYS_MALLOC_CLEAR_ON_INIT=y` in both
  (fork `Kconfig:108-110` defaults it on), so both zero the same 64 MiB at the top of DDR
  every boot — identical footprint, no new trample of fabric memory.

### 11.4 Finding, [U] — the watchdog stock hands to Linux

Stock defines `CONFIG_HW_WATCHDOG` (`socfpga_de10_nano.h:15` in the fork), which makes
`arch_cpu_init()` call `hw_watchdog_init()` (`misc.c:317-326`) — the Designware L4WD0 with
`CONFIG_HW_WATCHDOG_TIMEOUT_MS 30000` — and pet it through `WATCHDOG_RESET()`. Linux then
inherits a *running* 30 s watchdog; the MiSTer kernel copes (`CONFIG_DW_WATCHDOG=y`,
`CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y`, `CONFIG_WATCHDOG_OPEN_TIMEOUT=0` in
`output/build/linux-6.18.51/.config`), and a hang before the driver binds reboots the board.
This build resolves `# CONFIG_WDT is not set` / `# CONFIG_WATCHDOG is not set`
(`.config:1846-1847`), `CONFIG_HW_WATCHDOG` is absent (in 2026.07 it is a hidden `bool`,
`drivers/watchdog/Kconfig:43-44`, selected only by legacy i.MX-class drivers — no fragment
line can turn it on for socfpga), and the DE10 device tree has
`&watchdog0 { status = "disabled"; }` (`arch/arm/dts/socfpga_cyclone5_de10_nano.dts:84`).
The fork's `#else` arm — "make sure it is not running … enabled in the preloader" — **is
carried by mainline verbatim**: the shared `arch/arm/mach-socfpga/misc.c:174-190` has the
identical `#ifdef CONFIG_HW_WATCHDOG hw_watchdog_init(); #else socfpga_per_reset(SOCFPGA_RESET(L4WD0), 1);
socfpga_per_reset(SOCFPGA_RESET(L4WD0), 0); #endif` block in `arch_cpu_init()` (the fork's is
`misc.c:319-336`), `misc.o` is `obj-y` for every socfpga (`arch/arm/mach-socfpga/Makefile:11`),
and the built ELF executes the `#else` arm — `objdump -d --disassemble=arch_cpu_init u-boot`
is exactly `bl socfpga_get_managers_addr`, then `bl socfpga_per_reset` with `r0=#0x106`,
`r1=#1`, then again with `r1=#0`, then `movs r0,#0` (`0x106` = `RSTMGR_DEFINE(1,6)` =
`RSTMGR_L4WD0`, `include/mach/reset_manager_gen5.h:36`) **[V]**. The SPL side is inert:
`CONFIG_SPL_WATCHDOG=y` resolves but `nm spl/u-boot-spl` has no `wdt`/`watchdog` symbol at
all (no driver behind it) **[V]**. So U-Boot proper *explicitly holds L4WD0 in reset and
releases it* — the watchdog Linux inherits is not merely unconfigured but deliberately
stopped — and **the effective boot differs: stock's kernel starts under a live watchdog,
ours does not.** *(Erratum: the first revision of this paragraph claimed the `#else` arm
"has no mainline gen5 counterpart" on the strength of a `grep -i watchdog
arch/arm/mach-socfpga/*.c` said to hit Arria10 only; the grep in fact hits 15 files including
`misc.c`, `misc_gen5.c`, `spl_gen5.c` and `reset_manager_gen5.c`, and the sentence was wrong.
The conclusion stands, more strongly.)*
Not a brick in either direction — a stopped watchdog cannot fire — but a "mirror stock" gap
and a lost safety net. **Not fixed here:** it needs `CONFIG_WDT`/`CONFIG_WDT_DESIGNWARE`/
`CONFIG_WATCHDOG`/`CONFIG_WATCHDOG_AUTOSTART`/`CONFIG_WATCHDOG_TIMEOUT_MSECS=30000` in the
fragment *and* a DT change (`status = "okay"`), and a wrong timeout is precisely a
"looks like a boot, then resets 30 s later" failure. Ordering note for whoever applies that
recipe: `CONFIG_HW_WATCHDOG` stays off, so the `#else` toggle above still runs — at
`arch_cpu_init` (`common/board_f.c:903`, pre-relocation) — and the `CONFIG_WDT` autostart
runs later, at `initr_watchdog` (`common/board_r.c:663`, post-relocation, gated on
`CONFIG_IS_ENABLED(WDT)`): reset-then-start, which is the order one wants **[V]** (source
order; the recipe itself is unbuilt). **[U]: owner's call**; missing inputs are the decision
and a board to observe the driver takeover.

### 11.5 The SPL and the mailbox (`0x1FFFF000–0x1FFFFFFF`)

Every CPU-side store the SPL makes to DDR, from the link map and `.config` **[V]**:

| What | Where | Source |
|---|---|---|
| SPL image + DTB, `.data`, `__u_boot_list`, `.bss` (16 B) | OCRAM `0xFFFF0000`–`0xFFFFACF0` | `readelf -S spl/u-boot-spl` |
| initial stack, `gd`, early malloc (`0x800`) | top of OCRAM: `_main` does `mov r0,#0; bic r0,#7; mov sp,r0` (`CONFIG_SPL_STACK=0x0` = wrap to the 4 GiB top = end of OCRAM), `board_init_f_alloc_reserve` puts `gd` at `0xFFFFF720` and malloc at `0xFFFFF800` | `objdump --disassemble=_main` |
| relocated stack + simple malloc after DDR is up | malloc `0x00700000`–`0x00800000`, `gd` and stack below `0x00700000` | `CONFIG_SPL_STACK_R_ADDR=0x00800000`, `SPL_STACK_R_MALLOC_SIMPLE_LEN=0x100000`, `common/spl/spl.c:924-941` |
| the loaded U-Boot proper | `0x01000000`–`0x010872xx` (`ih_load - 64`, 553,688 B) | `spl_legacy.c:57-62` |
| `get_ram_size(0, 1 GiB)` probes | `base + 2^k` words: `0x20000000, 0x10000000, … , 0x4, 0x0` — saved and restored | `sdram_gen5.c:608`, `common/memsize.c:60-97` |
| ECC scrub | none: `CFG_HPS_SDR_CTRLCFG_CTRLCFG_ECCEN 0` (patch 0003, `qts/sdram_config.h:17`) | no ECC init/scrub path exists in `sdram_gen5.c` — `grep -in ecc drivers/ddr/altera/sdram_gen5.c` hits only lines 550-553, which are the size computation's `_WITH_ECC` width adjust, not a scrub |

No power of two lies in `0x1FFFF000–0x1FFFFFFF` and every probe is restored; nothing else
lands within 496 MiB of the mailbox. U-Boot proper's pre-relocation stack is
`CUSTOM_SYS_INIT_SP_ADDR=0x800000` (the fork's was in OCRAM); its `dram_init()` reads the DT
(`misc.c:66 fdtdec_setup_mem_size_base`) where the fork probed with `get_ram_size` (same
power-of-two set, restored). Relocation and the 64 MiB malloc arena sit at the top of the
1 GiB in both trees. **The mailbox is read by `fpgacheck` before any load touches DDR below
it** (`mmcload` runs `fpgacheck` first). What stays **[U]**, exactly as it is for stock: that
DDR *contents* survive the `swcoldrstreq` reset window and the PHY-driven calibration —
the calibration's DRAM traffic is generated by the RW manager from `ac_rom_init`/
`inst_rom_init`, both proven byte-identical (§5), but the sequencer C that drives them has
nine years of change (plan §3.2a). Hardware only, and the same claim stock rests on.

### 11.6 The `ih_ep`/`ih_load` mixing hazard — where it is and is not written

Verified the mechanism it warns about **[V]**: mainline's SPL takes `entry_point =
image_get_ep(header)` (`common/spl/spl_legacy.c:57`), so our SPL over stock's payload (`ih_ep
= 0`) jumps to `0x0`; stock's SPL over ours reads `ih_load` and survives (parity §4 block 1).
Where a future flasher would read it (`git grep -n -i "ih_ep\|mixing"`):

| Place | Present? |
|---|---|
| `docs/uboot-mainline-port.md` §3.3, §6, §8 taxonomy | yes |
| this file, §7 | yes |
| `scripts/check-uboot-parity.sh` (prints the warning on every run; `test-uboot-parity.sh` fixture 6) | yes |
| `docs/boot-chain.md` §2 (the blob's layout spec) and §5 (`updateboot`) | **no** |
| `README.md`, `PLAN.md`, `TASKS.md` | **no** |
| `scripts/mk-sdcard.sh`, `scripts/check-sdcard.sh` headers (the tools that write and check the boot partition) | **no** |
| a written recovery procedure (plan §8 gate item 4) | does not exist yet |

**[U] → task U8 / owner:** one sentence in boot-chain §2 ("the `.sfp` is atomic; SPL and
uImage must come from the same build — mainline's SPL jumps to `ih_ep`, the fork's to
`ih_load`") and a line in `mk-sdcard.sh`'s header are the two places a person with a card
reader would actually look. Both files are outside this task's scope (and `boot-chain.md` was
being edited by a concurrent task at the time of this review — re-check after merge).

### 11.7 The QTS handoff — gate rerun, and the scalars proven by binary

`scripts/check-uboot-handoff.sh` rerun before and after patch 0006: exit **0** both times,
same fourteen offsets as §5 **[V]**.

Plan §3.2a and §5 above say the scalar defines "compile to instruction immediates and are
not greppable". **That is wrong, and usefully so.** In both trees the handoff scalars are
*data*: `arch/arm/mach-socfpga/wrap_sdram_config.c` and `wrap_pll_config.c` build `static const`
structs from the `qts/*.h` defines, and the SPL reads them at run time (`socfpga_get_sdram_config()`
etc.). Reading each struct's bytes out of the built SPL ELF's `.rodata` (`objcopy
--only-section=.rodata`, symbol addresses from `nm -S`) and searching SPL copy 0 of both images
**[V]** (`/mnt/source/uboot-wave-a/U9/`, python; all offsets are into SPL copy 0):

| Struct (`nm -S` size) | Built SPL | Stock SPL | Scalar inside it / result |
|---|---|---|---|
| `sdram_config` (148 B) | `0x9c68` | **`0xa384`** | byte-identical; word 22 `fpgaport_rst` = **`0x3fff`** (stock word at `0xa3dc`) |
| `cm_default_cfg` (108 B) | `0x8e28` | **`0x9240`** | byte-identical; word 17 `s2fuser1clk` = **`0x1ff`** (511), word 25 `s2fuser2clk` = **`0x4`** |
| `io_config` (16 B) | `0x9d34` | **`0xabc0`** | byte-identical |
| `misc_config` (20 B) | `0x9b84` | *not byte-searchable* | same twelve `u8` values; mainline's `struct socfpga_sdram_misc_config` inserts `u16 afi_clk_freq` (= 0) after the signature (`sdram_gen5.h`), the fork's has no such field — built `a0045555 0000 0108 0600 …`, stock `a0045555 0108 0600 …` at `0xabd0` |
| `rw_mgr_config` (59 B) | `0x9d74` | *not byte-searchable* | same 59 values; the first 34 bytes match at stock `0xa2d0`, bytes 40–58 match, bytes 34–39 are the same six values (`mrs1..3`, `mrs1..3_mirr`) in the two headers' different field order (mainline `mrs1, mrs2, mrs3, mrs1_mirr, mrs2_mirr, mrs3_mirr`; fork `mrs1, mrs1_mirr, mrs2, mrs2_mirr, mrs3, mrs3_mirr`) — field-by-field equal |
| `REG_FILE_INIT_SEQ_SIGNATURE` as LE u32 | `0x555504a0` @ `0x9b84`, once (= `misc_config`'s first word) | `0x555504a0` @ `0xabd0`, once | mainline's `0x555504a1` absent from **both** |

**Erratum (2026-09-14, after independent verification).** The first revision of this table
placed `misc_config`, `io_config` and `rw_mgr_config` at built offsets `0x9630`/`0x96b8`/`0x9a70`
and claimed matches in stock at `0x9b44`/`0x9bcc`/`0x9f84`. Those built offsets all fall inside
`iocsr_scan_chain3_table` (`0xffff9354`, 0x830 bytes, per `nm -S`), so the "matches" were
scan-chain fragments the handoff gate already checks, and the sentence "every struct is
byte-identical" was false for two of the five. The rows above are the corrected result
(`/mnt/source/uboot-wave-a/U9/fix2/structs.txt`, `rwmgr.txt`).

The three structs that are byte-identical between the two SPLs (`struct socfpga_sdram_config`,
`struct cm_config` and `struct socfpga_sdram_io_config` have the same layout, field for field,
in `mach/sdram.h` / `mach/clock_manager.h` (fork) and `mach/sdram_gen5.h` /
`clock_manager_gen5.h` (mainline)) include the two that carry the scalars, so
**`FPGAPORTRST=0x3FFF` and both s2f clock counts are pinned to the stock binary the same way
the seven tables are.** `misc_config` and `rw_mgr_config` carry the same values in a
layout mainline changed (an inserted `u16`; a reordered `mrs*` block), so they are equal
field for field **[V by binary + source]** but cannot be asserted by a byte search. This
upgrades §5's "[V by source, U by binary]" and §8 item 3's premise ("not greppable") to
**[V by binary]** for the scalars; what remains [U] there is only whether the *values* are
required, which the owner has already ruled out of scope (plan §9 item 3). Suggested
follow-up, not done here (script owned by U4b/U5): extend `scripts/lib/qts-tables.py` to pack
the **three** byte-identical structs (`sdram_config`, `cm_default_cfg`, `io_config`) and add them
to the gate — three more "found in both" assertions; `misc_config` and `rw_mgr_config` would
need a field-aware comparison and are not worth it.

### 11.8 `mt` — the same code in both binaries

Stock's command table (69 entries at `0x33410`, stride 28) gives `mt: maxargs=3 rep=1 cmd=0x10040a9`;
disassembled from `work/uboot-proper.bin` at that address (Thumb, `--adjust-vma=0x01000040`)
against our `do_mem_mt` **[V]** (addresses from the **current, post-0006** ELF; the first
revision of this section quoted the pre-0006 ELF, `do_mem_mt` at `0100eb34`, `memcmp` call at
`100eb66` — patch 0006 shifted the function by −0x4c, the instruction sequence is identical):

```
stock 10040ee:  bl   memcmp            ours 100eb1a:  bl   1050c00 <memcmp>
      10040f2:  subs r0, #0                 100eb1e:  subs r0, #0
      10040f4:  it   ne                     100eb20:  it   ne
      10040f6:  movne r0, #1                100eb22:  movne r0, #1
      10040f8:  add  sp, #12                100eb24:  add  sp, #8
      10040fa:  pop  {r4, r5, pc}           100eb26:  pop  {r4, r5, r6, pc}
```

Same `memcmp` → `0`/`1` sense; same `argc < 3 → -1` (`CMD_RET_USAGE`) and
`cmd_get_data_size < 0 → 1` early exits (`10040ac`/`10040c4` in stock; ours `100eb2c` `mov.w r0, #0xffffffff`
/ `100eb28` `movs r0, #1`; `do_mem_mt` is at `0100eae8` now, `0100eb34` before 0006). Hush
takes `then` on `0` in both parsers; the sandbox transcript in §11.3 is the execution proof.

### 11.9 SPL size, the check, and the one limit nobody in the tree enforces

* `spl/u-boot-spl.bin` = **46,386 B**; packed with the socfpga header and CRC = 46,400 B;
  link-time limit `tools/spl_size_limit` = **62,752** = `0x10000 − gd(224) − SPL_SYS_MALLOC_F_LEN(0x800)
  − SPL_SIZE_LIMIT_PROVIDE_STACK(0x200)`; headroom 16,352 B (26 %) — §6's numbers reproduce
  after the rebuild (SPL unchanged) **[V]**.
* **The check is wired and fatal [V by source]:** `CONFIG_SPL_SIZE_LIMIT=0x10000` ≠ `0x0`
  enables `SPL_SIZE_CHECK` (`Makefile:1167-1168`, the `ifneq` guard and its definition), which runs on `spl/u-boot-spl.bin`
  (`:2432-2434`); the `size_check` macro (`:449-460`) prints `exceeds file size limit` and
  `exit 1`. The 2017.03 tool's silent-truncation window (plan §3.5) is closed.
* **OCRAM layout at run time** (§11.5): image to `0xFFFFACF0`, initial stack from
  `0xFFFFF720` down, `gd`/malloc above it — 19,000 B of stack until DDR is up.
* **[U] — the BootROM's own maximum.** Neither `tools/socfpgaimage.c` (mainline caps at the
  64 KiB padded buffer, `sfp_max_size`) nor the fork's (`PADDED_SIZE 0x10000`) enforces the
  smaller preloader-image limit the Cyclone V HPS Boot ROM is documented to apply (the top of
  OCRAM is in use by the ROM while it copies the image in; the figure recalled is 60 KiB =
  `0xF000`, which is 15,040 B above today's 46,400). If that figure is right, the effective
  headroom is 15,040 B, not 16,352, and `SPL_SIZE_CHECK` alone would not catch an SPL between
  60 KiB and 61.3 KiB. Missing input: the Cyclone V HPS Technical Reference Manual, "Booting
  and Configuration" chapter. Worth a `SPL_SIZE_LIMIT`-style assertion in the parity script
  once the number is confirmed.

### 11.10 Reproducing the review's decisive steps

```
# (a) the call is emitted, and where
arm-buildroot-linux-gnueabihf-objdump -d --disassemble=arch_early_init_r output/build/uboot-2026.07/u-boot
# (b) env vs hush, in the 2026.07 sandbox (old parser, as the DE10 build)
cd /mnt/source/uboot-wave-a/U2c/u-boot-2026.07 && ./u-boot -c '<see /mnt/source/uboot-wave-a/U9/sandbox.txt>'
# (b) the fix
arm-buildroot-linux-gnueabihf-objdump -d --disassemble=env_get_bootm_mapsize output/build/uboot-2026.07/u-boot
# (e) the scalars, by binary
arm-buildroot-linux-gnueabihf-nm -S output/build/uboot-2026.07/spl/u-boot-spl | grep -E ' (sdram_config|cm_default_cfg|misc_config|io_config|rw_mgr_config)$'
# then search SPL copy 0 of both images for those bytes: python3 /mnt/source/uboot-wave-a/U9/fix2/structs.py
# (f) stock's mt
arm-buildroot-linux-gnueabihf-objdump -D -b binary -marm -Mforce-thumb --adjust-vma=0x01000040 \
    --start-address=0x10040a8 --stop-address=0x1004100 work/uboot-proper.bin
```

### 11.11 Observation — the parity script's ELF-less form on this artifact

Not a U9 defect, recorded for the U4a/U5 owners **[V]**: `scripts/check-uboot-parity.sh
output/images/u-boot-with-spl.sfp <stock>` *without* the third (ELF) argument exits 1 with
`CONTRACT VIOLATED` on the current artifact. The `bootcmd=` scan walks back through the
NUL-separated strings that precede `default_environment[]` in `.rodata` and anchors the blob
at payload offset `0x6ca6e` instead of the true `0x6cad5` (from `nm -S`, 1,150 B) — 0x67 bytes
early, so it "sees" 1,253 B / 31 entries, the extra ten being net-driver format strings
(`ethrotate`, `eth%d: %s`, …). With the ELF (release.yml's form and §4's) the same artifact
passes: `environment is byte-identical to stock: 1150 bytes, 21 entries`. The script already
prints its "a scan-only run would compare the wrong bytes" caveat; the owners may prefer the
ELF-less form to fail loudly on an ambiguous scan rather than compare. Transcript:
`/mnt/source/uboot-wave-a/U9/fix2/parity-noelf.txt`.

### 11.12 Observations from the third verification round — scope, and the carried patches' headers

**Scope attestation [V].** This review's only repo writes are two untracked paths:
`docs/verification/uboot-mainline.md` (this file) and
`board/mister/de10nano/patches/uboot/0006-*.patch` (a commit-message line in round 2). The
branch's `git status --short` also shows 22 *modified tracked* files (`uboot.env`,
`uboot.fragment`, `external.mk`, `scripts/ci-tests.sh`, README/PLAN/docs …) — those belong to
the concurrent U2/U3/U5/U8 tasks, and a shared working tree cannot prove by itself who wrote
what. What this review can offer instead: patches 0001–0005 carry the mtime at which U2g
placed them (`14:02:28`, all five identical; 0006 is `15:04:49`, round 2), the built artifact
is unchanged across all three rounds (`u-boot-with-spl.sfp` `4bf59acf…`, `u-boot.bin`
`ce860693…`, `u-boot-spl.bin` `ae00baa6…`), and no `make` was run in `output/` by this round.
Integrators who want a hard answer should diff the branch's tracked files against each
task's `files_written` list at merge time.

**The carried patches' provenance labels [V], no change made.** Patch 0004 has no line
beginning `Origin:`; 0003 and 0005 spell the field `Upstream:` rather than `Upstream status:`.
Checked against `CONTRIBUTING.md:50-56`, which mandates *content* — origin SHA, author,
upstream status, disposition, `Signed-off-by` — and whose own example header says
"Reason for carrying" where every patch in this repo says "Disposition". All five items are
present in all six patches: 0004's origin SHA `c0ed23f52e203d704c0b149408f2cc0b1bb48939`
("Implement simple memory test against value.", Sorgelig, 2017-04-07) sits under an
underlined `Origin` heading at lines 26-31, directly above `Author:`; 0003/0005's `Upstream:`
lines answer the "is it in mainline" question in full. The `Upstream:` spelling is also the
repo's *dominant* convention — `git grep -l '^Upstream:' board/mister/de10nano/linux-patches/`
→ 36 files, `'^Upstream status:'` → 2, `'^Origin:'` → 38 — and nothing in `scripts/`,
`.github/` or `docs/patch-provenance.md` greps for either literal label;
`scripts/lint-kernel-patches.sh` (which checks `git am`-ability and a non-empty mailinfo
author/subject) passes all six: `RESULT: PASS — all 6 patches in 1 series are git am-able`.
Not edited: the three files are other tasks' deliverables and the change would be cosmetic.
If the owner wants one spelling, it is a five-minute label edit that changes no diff body
and needs no rebuild.

**No finding is unlabelled.** Fixed: 11.2. Corrected after independent verification: 11.7
(three struct rows and its summary), 11.2/patch 0006 header (the header count), 11.8 (the
pre-0006 addresses), 11.4 (the false "no mainline counterpart" sentence — the L4WD0 reset
toggle *is* compiled and executed, with the erratum kept in place), 11.5 (the ECC row's
source cell pointed at the size computation, not a scrub). Open [U]: 11.1 (hardware,
unchanged), 11.2's clean-build and kernel observations, 11.4 (owner), 11.6 (U8/owner),
11.9's BootROM limit (TRM). 11.11 and 11.12 are observations for the script owners and the
integrator. Everything else **[V]** as marked.
