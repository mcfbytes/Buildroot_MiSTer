# DE25-Nano U-Boot — mainline `u-boot.itb`, and the config that makes a QSPI write impossible

**Status:** built and shape-verified on 2026-09-02; **never run on hardware**. Every claim below is
tagged **[V]** (read from source, or observed in this build) or **[U]** (unverified — the missing
input is named). Nothing here has touched a DE25-Nano.

This is D2.4's buildable half (`docs/de25-nano-tasks.md`, "What to do next" item 1). It delivers
`output-de25/images/u-boot.itb` and `output-de25/images/bl31.bin`, and it closes
[`de25-implementation-path.md`](de25-implementation-path.md) §8 **Q6** — in the negative.

Cross-refs: [`de25-implementation-path.md`](de25-implementation-path.md) §6.1–§6.3, §8 Q5/Q6/Q7;
[`de25-boot-chain.md`](de25-boot-chain.md) §2, §3, §5, §7 (brick-risk register), §8.3, §8.5;
[`de25-dts-rationale.md`](de25-dts-rationale.md) ("Console UART", "Memory");
[ADR 0029](decisions/0029-de25-implementation-path.md).

---

## 1. The one rule

The DE25-Nano's QSPI holds the SDM firmware, the phase-1 HPS bitstream (which carries **all** the
DDR and pinmux handoff data), and the factory U-Boot SPL that is this board's FSBL. The SDM cannot
boot from the microSD at all, so that flash is the only thing standing between the board and a
JTAG-and-a-PC recovery, and no power-loss-safe update path for it is demonstrated at this flash size
**[V `de25-boot-chain.md` §8.1, §8.4, §7 rows 1/7/8]**.

> **Nothing this build produces may write the QSPI, by any mechanism.**

§7 of this document is the audit that says whether that holds, symbol by symbol. §6.2 of
`de25-implementation-path.md` is why the guard has to be structural rather than procedural: the
danger is not `saveenv`, it is the environment **load** path.

---

## 2. Versions, and where their hashes come from

| Component | Pin | Why not Buildroot's own | Hash provenance |
|---|---|---|---|
| U-Boot | **v2026.07** (released 2026-07-07) | Buildroot 2026.05.2 ships 2026.04 | **Signed.** `ftp.denx.de/pub/u-boot/u-boot-2026.07.tar.bz2` + its `.sig`; `gpg --verify` → *Good signature from "Thomas Rini <trini@konsulko.com>"*, EDDSA key `F3CEA8743D60E0192F9B4C7A2BE2A0F50ABFE40A`, fetched by full fingerprint from keys.openpgp.org **[V, done 2026-09-02]** |
| TF-A | **v2.15.0** | Buildroot 2026.05.2 tops out at v2.12, which has **no Agilex 5 platform** — a custom version is the only route, not a preference | **TOFU, honestly labelled.** trustedfirmware.org publishes no release tarballs and no signed manifest. Anchored on annotated tag `v2.15.0` (object `9ad327a8…`) → commit `da738d5eae93af342fdc4995dd3c05acb4c9d757`, confirmed from a **second, independent clone**. The tag *is* PGP-signed (RSA `5D6F8960…`, Olivier Deprez/Arm) but that key is on **neither** keys.openpgp.org nor keyserver.ubuntu.com (both 404, 2026-09-02), so the signature could **not** be verified **[V that it is unverifiable today]** |

Both hash files live under the existing `BR2_GLOBAL_PATCH_DIR`
(`board/mister/de25nano/patches/`), the same mechanism the kernel's `linux.hash` uses —
`pkg-patch-hash-dirs` (`package/pkg-utils.mk:163`) searches `$(BR2_GLOBAL_PATCH_DIR)/<pkg>/` as well
as the package directory. Each file's header carries the full provenance story; read it before
changing a value.

`BR2_DOWNLOAD_FORCE_CHECK_HASHES=y` makes both **fail closed**, and the two failures have different
shapes worth knowing:

- **U-Boot**: `boot/uboot/uboot.hash` exists but only lists 2026.04, so `check-hash` finds a hash
  *file* and no matching *line* → exit 3, `ERROR: No hash found for u-boot-2026.07.tar.bz2`.
- **TF-A**: Buildroot ships no ATF hash file at all and explicitly excuses git-generated tarballs
  via `BR_NO_CHECK_HASH_FOR`. `BR2_DOWNLOAD_FORCE_CHECK_HASHES` **empties** that variable
  (`package/pkg-download.mk:119`), so the excuse does not apply and the same exit 3 results **[V]**.

**Filename gotcha, ATF only.** Buildroot's git backend names its tarball
`arm-trusted-firmware-v2.15.0-**git4**.tar.gz`, where `4` is `BR_FMT_VERSION_git` — the archive
*format* version. A Buildroot bump that changes it changes both the filename and the hash, and the
build fails closed until both are re-derived **[V]**.

**The version pairing (U-Boot 2026.07 + TF-A v2.15.0) is [U]** — this is ADR 0029 D4's "left open"
item, and building green does not close it. Terasic and Altera document only vendor forks
(`u-boot-socfpga socfpga_v2023.10` + `arm-trusted-firmware socfpga_v2.10.0`).

---

## 3. Files

| File | Role |
|---|---|
| `configs/fragments/de25nano.fragment` | the ATF/U-Boot/host-tools stanza (rationale: `docs/buildroot-config.md` §6.9, §6.10) |
| `board/mister/de25nano/uboot.fragment` | the U-Boot Kconfig delta on `socfpga_agilex5_defconfig` (§4) |
| `board/mister/de25nano/uboot-dts/socfpga_agilex5_de25nano.dts` | U-Boot board device tree (§5) |
| `board/mister/de25nano/uboot-dts/socfpga_agilex5_de25nano-u-boot.dtsi` | U-Boot additions: `stdout-path`, mmc caps, FIT tweaks (§5, §6) |
| `board/mister/de25nano/patches/uboot/0001-configs-socfpga_soc64-guard-mtdids-mtdparts-env.patch` | the one carried U-Boot patch (§8) |
| `board/mister/de25nano/patches/uboot/uboot.hash` | signed-provenance hash for the 2026.07 tarball |
| `board/mister/de25nano/patches/arm-trusted-firmware/arm-trusted-firmware.hash` | TOFU hash for the v2.15.0 git tarball |
| `Makefile` (`de25` recipe) | post-build assertions for `images/bl31.bin` and `images/u-boot.itb` |

**Why `uboot-dts/` is a subdirectory.** The U-Boot board file and the *kernel* board file share a
basename by convention (`socfpga_agilex5_de25nano.dts`) and are entirely different files: U-Boot's
`socfpga_agilex5.dtsi` and the kernel's are separate upstream files, U-Boot's `mmc0` is
`"altr,agilex5-sd6hc","cdns,sd6hc"` while the kernel has no `mmc0` at all and ours declares the
SD4HC form, and only U-Boot has `-u-boot.dtsi` machinery **[V]**. They must not share a directory.

---

## 4. The fragment, and why each block is there

The full file is `board/mister/de25nano/uboot.fragment`, and every line in it carries its own
comment; this section is the summary and the *evidence*, not a duplicate.

### 4.1 Board device tree

```
CONFIG_DEFAULT_DEVICE_TREE="socfpga_agilex5_de25nano"
```

`scripts/Makefile.dts` does `dtb-y += $(CONFIG_DEFAULT_DEVICE_TREE).dtb` **[V]**, so a `.dts` that
appears in no `arch/arm/dts/Makefile` list is still built. That is what makes carrying a board file
possible **without patching U-Boot**. Buildroot's `BR2_TARGET_UBOOT_CUSTOM_DTS_PATH` is a plain
`cp -f <list> arch/$(UBOOT_ARCH)/dts/` **[V `boot/uboot/uboot.mk`]**, so it happily takes both the
`.dts` and the `-u-boot.dtsi`.

### 4.2 The environment block — the reason this task exists

```
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
# CONFIG_ENV_IS_IN_UBI is not set
# CONFIG_ENV_IS_IN_SPI_FLASH is not set
# CONFIG_ENV_IS_IN_NAND is not set
# CONFIG_ENV_IS_IN_MMC is not set
```

The stock `socfpga_agilex5_defconfig` compiles in **both** FAT and UBI. The hazard is not `saveenv`:
`env_ubi_load()` calls `ubi_part()` **unconditionally** at `env/ubi.c:128` whenever the FAT load
fails, and a UBI attach against a **blank** MTD partition succeeds and then *writes a layout volume*
via `create_empty_lvol()` → `create_vtbl()` **[V, `de25-implementation-path.md` §6.2, traced there
against v2026.07 sources]**. A missing `uboot.env` plus a blank QSPI `root` partition therefore
writes boot flash on the very first `env_load()`, with no user action.

The last three lines are stated even though nothing sets them today: they are what a future
Buildroot or U-Boot default flip would have to get past, and `ENV_IS_IN_SPI_FLASH` would put the
environment *directly* in the QSPI.

### 4.3 QSPI: three locks on one door

Driver, stack, commands — see the audit table in §7. Summary: `CADENCE_QSPI` is the only route from
U-Boot to this flash and it is compiled out; the SPI-NOR stack above it is compiled out; every
command that could reach either is compiled out; MTD and UBI are compiled out.

### 4.4 DRAM — a coupling no earlier document names

**New finding, and it is load-bearing.** `arch/arm/mach-socfpga/misc.c` `dram_init()` has two
branches **[V, v2026.07]**:

```c
#if CONFIG_IS_ENABLED(HANDOFF) && IS_ENABLED(CONFIG_ARCH_SOCFPGA_AGILEX5)
	ho = bloblist_find(BLOBLISTT_U_BOOT_SPL_HANDOFF, sizeof(*ho));
	if (!ho)
		return log_msg_ret("Missing SPL hand-off info", -ENOENT);
	gd->ram_size = ho->ram_bank[0].size;
#else
	if (fdtdec_setup_mem_size_base() != 0)
		return -EINVAL;
#endif
```

The bloblist that branch looks for is written by **our** SPL at **our** `CONFIG_BLOBLIST_ADDR`. Our
SPL never runs — the factory SPL does, and it is a Terasic build of U-Boot 2025.01 whose
`BLOBLIST_ADDR` is a compiled-in constant that appears in no artifact we can read. Mainline's socdk
uses `0x7e000`; the reference DE25 tree uses `0x72000` **[V, both defconfigs read]**. If they
disagree, `dram_init()` returns `-ENOENT`, U-Boot dies in its first initcalls, and the failure looks
exactly like a bad card. `bloblist_init()` does *not* save us: on a bad magic at the fixed address
it logs a warning and creates a **new, empty** bloblist **[V `common/bloblist.c`]**, so the handoff
blob is simply absent.

So the fragment sets `# CONFIG_HANDOFF is not set`, `dram_init()` takes the `fdtdec` branch, and the
size comes from the `/memory` node in our own `u-boot.dtb`. Self-contained; no dependency on a
Terasic constant. The cost is that 1 GiB @ `0x8000_0000` is a *declared* value.

**Fallback if the hardware says otherwise:** `include/handoff.h` is **byte-identical** between the
reference 2025.01-lineage tree and v2026.07 (`diff -q` → identical) **[V]**, so re-enabling
`CONFIG_HANDOFF=y` with `CONFIG_BLOBLIST_ADDR=0x72000` is a viable second attempt. Try the DTS
constant first.

### 4.4b …and the bloblist goes with it, which removes a latent overlap

With `HANDOFF` off nothing in this build reads or writes a bloblist, so
`# CONFIG_BLOBLIST is not set` as well. That is not tidiness. The stock defconfig sets
`BLOBLIST_FIXED` with `ADDR = 0x7e000`, `SIZE = 0x1000`, i.e. the on-chip-RAM region
`0x7E000..0x7EFFF`. TF-A v2.15.0's Agilex 5 platform puts its **secondary-CPU handshake words at the
top of that same page** **[V]**:

```
PLAT_HANDOFF_OFFSET = 0x0007F000                 agilex5/socfpga_plat_def.h:30
BL_DATA_LIMIT       = PLAT_HANDOFF_OFFSET
PLAT_CPUID_RELEASE  = BL_DATA_LIMIT - 16 = 0x7EFF0
PLAT_SEC_ENTRY      = BL_DATA_LIMIT -  8 = 0x7EFF8   common/platform_def.h:125-128
```

and `bl31_plat_setup.c:59` writes `PLAT_SEC_ENTRY`. The declared bloblist region covers both words.

**Today the overlap is benign** — U-Boot writes only the ~32-byte bloblist header at `0x7E000` and
never grows into the last 16 bytes of the page. But "benign because nothing currently fills the
buffer" is a property of today's blob set, not a guarantee, and what it guards against is a
secondary CPU jumping to a clobbered entry point. Deleting a region nothing uses is strictly better
than reasoning about how full it gets.

**Checked, not assumed [V]:** with `BLOBLIST` off the config still resolves to `SPL=y`,
`SPL_ATF=y`, `BINMAN=y`, a full U-Boot build completes, and `u-boot.itb` is still produced.
`BLOBLIST_FIXED`, `BLOBLIST_ADDR`, `BLOBLIST_SIZE`, `SPL_BLOBLIST`, `HANDOFF` and `SPL_HANDOFF` all
disappear from the resolved config. The `# CONFIG_HANDOFF is not set` line is kept anyway: the two
lines record two separate decisions, and if a future bump makes something `select BLOBLIST` again,
the HANDOFF line is still what keeps `dram_init()` off the factory SPL's bloblist.

### 4.5 SPL — §8 Q6, answered

`de25-implementation-path.md` §6.1 reasoned from the Kconfig graph that `# CONFIG_SPL is not set`
would "genuinely eliminate SPL compilation", flagged **[U]**, "the first thing to check at first
build". **It does not work, and Q6 closes in the negative [V]:**

```
config ARCH_SOCFPGA_AGILEX5
        select BINMAN if SPL_ATF        # arch/arm/mach-socfpga/Kconfig
```

`SPL_ATF` sits inside `menu "SPL configuration options" depends on SPL` (`common/spl/Kconfig:19-20`),
so turning `SPL` off takes `SPL_ATF` with it and `BINMAN` is never selected — and `CONFIG_BINMAN` is
a bool **with no prompt** (`dts/Kconfig:15`), so it cannot be turned back on from a defconfig or a
fragment; kconfig drops the line. No binman, no `u-boot.itb`, and the U-Boot build is otherwise
green.

**Verified by resolving the config both ways, not merely reasoned [V]:** the same fragment plus one
extra `# CONFIG_SPL is not set` line, run through `merge_config.sh` + `olddefconfig` against
`socfpga_agilex5_defconfig`, gives

```
# CONFIG_SPL is not set
CONFIG_SPL_ATF   <absent from the resolved config>
CONFIG_BINMAN    <absent from the resolved config>
```

against `CONFIG_SPL=y` / `CONFIG_SPL_ATF=y` / `CONFIG_BINMAN=y` as shipped. That is the worst failure shape available, which is why the Makefile now asserts the FIT
exists (§9) and the fragment carries a "do not re-open this" comment.

**So SPL is compiled and nothing of it is shipped.** That is enforced positively, not by omission:
`BR2_TARGET_UBOOT_SPL` is not set, so `UBOOT_INSTALL_IMAGES_CMDS` copies no `spl/*` file
**[V `boot/uboot/uboot.mk`]**, and `images/` contains no SPL artifact (§9). The factory SPL in QSPI
is untouched, which is the posture-1 contract.

### 4.6 Filesystems and boot

`CONFIG_FS_FAT` / `CONFIG_CMD_FAT` (already implied by `BOOT_DEFAULTS_CMDS`, restated because the
env and the boot path both depend on them); `CONFIG_FS_EXFAT=y` (mainline gained `fs/exfat` in
`b86a651b64`, 2025-03-17 — after the reference board's 2025.01 base, which is exactly why that
project hand-rolled libexfat; §8 Q7's p2-filesystem decision is now free of any U-Boot change);
`CONFIG_DISTRO_DEFAULTS=y` (already y, restated because upstream marks it deprecated and this line
is where a future migration to `BOOTSTD_DEFAULTS` starts); and a sane `CONFIG_BOOTARGS` replacing
the stock ramdisk/`nosmp`/Simics string.

---

## 5. The board device tree — why not reuse `socfpga_agilex5_socdk`

Mainline v2026.07 has **no** DE25-Nano board: `board/terasic/` has de0-nano-soc, de1-soc, de10-nano,
de10-standard and sockit, and there is no `configs/*de25*` anywhere in the tree **[V]**. The choice
was therefore between reusing the SoC Development Kit's device tree and carrying a minimal board
file. **Reuse is not viable, for one line:**

```
socfpga_agilex5_socdk.dts:   serial0 = &uart0;      <- SoCDK console
DE25-Nano:                   serial0 = &uart1;      <- the board's USB-UART header
```

`de25-dts-rationale.md` settles the DE25's console as uart1 **[V]**, and the reference DE25 U-Boot
tree aliases `serial0 = &uart1` **[V]**. A device tree cannot be overridden from Kconfig, so booting
socdk's DTB on this board gives a console on a pin nobody wired — a board that looks dead. That is
the whole justification; everything else in our board file follows from keeping it minimal.

**What we author (both files together are ~1 screen of actual device tree):**

| Node | Value | Why |
|---|---|---|
| `aliases/serial0` | `&uart1` | the reason the file exists |
| `aliases/mmc0` | `&mmc` | `UCLASS_MMC` carries `DM_UC_FLAG_SEQ_ALIAS`; "0" is load-bearing in `ENV_FAT_DEVICE_AND_PART="0:1"`, in `bootcmd_mmc0`, and in every `load mmc 0:1` on the card. With one controller the answer is 0 anyway — writing it down stops a future second device renumbering it |
| `/memory` | `<0 0x80000000 0 0x40000000>` (1 GiB) | §4.4. Node name has **no** unit address because `fdtdec_setup_mem_size_base()` looks it up by the literal path `/memory` **[V `lib/fdtdec.c:1084`]** |
| `osc1` | `clock-frequency = <25000000>` | the SoC dtsi declares the fixed clock with no rate; the whole tree, including the UART divisor, hangs off it |
| `&uart1` | `status = "okay"` + `bootph-all` | the dtsi ships it disabled; `socfpga_agilex5-u-boot.dtsi` marks `&uart0` `bootph-all`, not uart1, and without the marking there is no pre-relocation console — the exact window a bring-up failure would be diagnosed in |
| `&mmc` | `okay`, `no-mmc`, `no-sdio`, `disable-wp`, `bus-width = <4>`, `cap-sd-highspeed`, `max-frequency = <50000000>`, `bootph-all` | see below |

### 5.1 The `&mmc` block — board facts vs SoC facts, treated differently

Those are two different categories and the block splits them deliberately.

**BOARD facts we do not take from socdk.** socdk declares `sd-uhs-sdr50`/`sd-uhs-sdr104` with
`vqmmc-supply = <&sd_io_1v8_reg>`, whose GPIO is `<&portb 3>` — a **SoC Development Kit wiring
fact**. Driving the wrong GPIO to switch SD bus voltage is a way to break a card, not a way to go
faster, and the reference DE25 tree declares no vqmmc regulator either **[V]**. So: no UHS modes,
no voltage switching, no regulator phandles.

**SoC facts we do take from socdk.** An earlier draft of this file omitted socdk's `cdns,*` timing
properties on the argument that `drivers/mmc/sdhci-cadence6.c` carries a built-in default for every
one of them. That is true and it was the wrong conclusion: **the driver's defaults are a fallback,
not a validated configuration.** For SD high speed they are

```
cdns,phy-dqs-timing-delay-sd-hs      0x00380004
cdns,phy-gate-lpbk-ctrl-delay-sd-hs  0x01A00040
cdns,phy-dq-timing-delay-sd-hs       0x00000001
cdns,ctrl-hrs07-* / cdns,ctrl-hrs16-*   (no entry at all)
```

**[V `drivers/mmc/sdhci-cadence6.c:75-135`]** — values that no validated Agilex 5 board ships.
socdk's, which are the only Agilex 5 SD timings anyone has run on silicon, are `0x780001`,
`0x81a40040`, `0x10000001`, `hrs16 = 0x101`, `hrs07 = 0xA0001`
**[V `arch/arm/dts/socfpga_agilex5_socdk-u-boot.dtsi:122-134`]**. These are *controller* delays, not
board wiring, so they transfer. We now copy the `sd-ds` and `sd-hs` stanzas verbatim, with the
source named in the file.

**Speed: default speed only, 25 MHz.** `cap-sd-highspeed` is **not** set and `max-frequency` is
`<25000000>`, so U-Boot proper never leaves DS mode — the slowest and most forgiving SD timing there
is. The cost is nothing that matters: 4-bit DS is about 12.5 MB/s, so the 20 MB `Image` costs under
two seconds, once, per boot. The `sd-hs` values are still declared so that lifting the cap is a
one-line change rather than a research task.

**This is the first knob to turn if the card misbehaves.** The symptoms to watch for on the first
boot are: `Retrieving file: /Image` stalling or timing out; `mmc_load_image_raw` / `sdhci` timeout
messages; a CRC or checksum complaint from extlinux or from `booti`; or a kernel that starts and
then panics on a corrupt initramfs/rootfs read. Any of those is a timing problem until proven
otherwise, and the order of attack is:

1. **Already at the safest setting** (DS, 25 MHz, socdk PHY values) — that is what ships.
2. If it still fails, try the *driver-default* PHY values (delete the `cdns,*` lines) — that
   isolates "socdk's timings are wrong for this board" from "the card or the socket is the problem".
3. Only then suspect the card itself; `dd if=/dev/mmcblk0 of=/dev/null bs=1M` from Linux is the
   independent check, because it exercises the kernel's driver rather than U-Boot's.

**Lifting it, once a full `dd` of the card reads clean under Linux and U-Boot has booted reliably a
few times:** re-add `cap-sd-highspeed;` and set `max-frequency = <50000000>;` in
`socfpga_agilex5_de25nano-u-boot.dtsi`. That is the whole change — the `sd-hs` PHY block it needs is
already there. Re-test a cold boot and a `Retrieving file:` of the kernel before keeping it. Going
beyond 50 MHz means UHS, which means a `vqmmc` regulator, which means establishing the DE25's real
1.8 V switch GPIO on hardware — a different and much larger job.

**Deliberate omissions:** no `&qspi` and no flash node (the node stays at the dtsi's `disabled`
default, so even a hypothetically-present driver would not probe — the second lock on §7's door);
no `&nand`; no `&gmac0`/PHY (U-Boot does not need ethernet to load a kernel, and the DE25's PHY
address in U-Boot terms is unverified); no LEDs, watchdogs, timers, i2c, i3c, usb, spi0/spi1.

**`socfpga_agilex5_de25nano-u-boot.dtsi` must `#include "socfpga_agilex5-u-boot.dtsi"`** — that is
what pulls in `socfpga_soc64_fit-u-boot.dtsi`, the binman description that *is* `u-boot.itb`.
Without it the build produces a working U-Boot binary and **no FIT at all** **[V]**. Every label
that file references (`clkmgr`, `i2c0-3`, `mmc`, `porta`, `portb`, `qspi`, `rst`, `sdr`, `sysmgr`,
`uart0`, `watchdog0`) is defined in the SoC `.dtsi`, so a minimal board file is enough **[V,
checked]**.

It does **not** carry socdk's `u-boot,spl-boot-order`: that property is read by `board_boot_order()`
in SPL, our SPL never runs, and the factory SPL's order is already known and fixed —
`"/soc/mmc0@10808000", "/soc/spi@108d2000/flash@0", "/soc/nand@10b80000", "/memory"`
**[V `de25-boot-chain.md` §2]**. Restating it would describe a decision we do not get to make, and
it references `&flash0`, which this board file deliberately does not declare.

---

## 5b. What the build produced

`make de25`, 2026-09-02, green **[V]**:

| `output-de25/images/` | Size | From |
|---|---|---|
| `u-boot.itb` | 728,168 B (`sha256 49f1c7dd…`, clean build 2026-09-02) | binman, U-Boot v2026.07 |
| `bl31.bin` | 53,304 B (`sha256 863073b2…`) | TF-A v2.15.0, `PLAT=agilex5` |
| `Image` | 20,711,432 B | Linux 7.2.2 (see §12b — the kernel-config switch landed in this pass's defconfig edit) |
| `socfpga_agilex5_de25nano.dtb` | 17,138 B | kernel DTS (D2.3, unchanged here) |
| `rootfs.ext4` → `rootfs.ext2` | 256 MiB | D2.1, unchanged here |

The FIT's `Created:` timestamp is `Sun Aug 23 16:00:00 2026` — `SOURCE_DATE_EPOCH` from
`BR2_REPRODUCIBLE=y`, not wall-clock, so the artifact is reproducible **[V]**. Confirmed in
practice: repeated `make de25` runs, hours apart and with a full kernel reconfigure between them,
produced byte-identical artifacts — `bl31.bin` is
`sha256 863073b2c0a9489ae04cbf077b5496975f7aa7f925a8397fad705bcb3c390bf1` across every run, and
`u-boot.itb` is byte-stable **within a build tree** — verified twice: two runs in the wave-2 tree
(728,176 B) and, after a full `distclean`, two runs in the clean tree including a
`uboot-dirclean` rebuild (728,168 B, `sha256 49f1c7dd…`) **[V]**. It is **not yet shown to be
byte-stable across clean trees [U]**: the wave-2 tree's FIT and the clean tree's FIT differ by
8 bytes, all of it inside the `uboot` payload (650,056 → 650,048 B; `atf` and `fdt-0` identical
in size and BL31 identical in hash), with the same resolved Buildroot config. The version string
is not the cause (it carries only the pinned `SOURCE_DATE_EPOCH` date). The boot contract is
unaffected — load addresses, config node, crc32-only signature and DTB are what the checker
asserts, not the hash — but the D2.8 release lane should pin this down with two clean CI builds
before it publishes attested hashes. (History: 731,728 B before the review fixes, 728,176 B
after `CONFIG_BLOBLIST` came out and the mmc node grew.)

**Housekeeping done in the same pass:** `images/socfpga_agilex5_socdk.dtb` was a stale leftover from
before D2.3 (mtime predating this build by hours, from when the defconfig still pointed at
mainline's socdk placeholder). Buildroot never removes a stale artifact from `images/`, the
Makefile's `*.dtb` glob printed it as though it were current, and the card-image step could plausibly
have copied it. Deleted. **Worth a guard**: nothing in the build detects this class of leftover.

### 5b.1 Two build-cost facts worth knowing before someone thinks the build hung

- **`BR2_TARGET_UBOOT_USE_BINMAN=y` drags in a Rust toolchain.** It selects
  `host-python-jsonschema`, which needs `host-python-rpds-py`, which is a Rust extension, which
  needs `host-rust-bin`. On a cold host tree that is the single longest step of the whole DE25
  build and it looks nothing like a bootloader **[V, observed]**.
- **`BR2_PACKAGE_HOST_UBOOT_TOOLS_FIT_SUPPORT` is not `default y`, and without it `dumpimage` is
  silent.** `dumpimage -l u-boot.itb` printed *nothing* and exited **0** — a verification step that
  always passes and never checks anything. That is a worse failure than a crash. Found on the first
  build; the symbol is now in the defconfig with a comment saying why **[V]**.

## 6. The FIT — checked against the factory SPL contract

### 6.1 What `dumpimage` says

```
FIT description: FIT with firmware and bootloader
Created:         Sun Aug 23 16:00:00 2026
 Image 0 (uboot)
  Description:  U-Boot SoC64
  Created:      Sun Aug 23 16:00:00 2026
  Type:         Standalone Program
  Compression:  uncompressed
  Data Size:    654016 Bytes = 638.69 KiB = 0.62 MiB
  Architecture: AArch64
  Load Address: 0x80200000
  Entry Point:  unavailable
  Hash algo:    crc32
  Hash value:   1806e9a2
 Image 1 (atf)
  Description:  ARM Trusted Firmware
  Created:      Sun Aug 23 16:00:00 2026
  Type:         Firmware
  Compression:  uncompressed
  Data Size:    53304 Bytes = 52.05 KiB = 0.05 MiB
  Architecture: AArch64
  OS:           ARM Trusted Firmware
  Load Address: 0x80000000
  Hash algo:    crc32
  Hash value:   690a1fc1
 Image 2 (fdt-0)
  Description:  socfpga_agilex5_de25nano
  Created:      Sun Aug 23 16:00:00 2026
  Type:         Flat Device Tree
  Compression:  uncompressed
  Data Size:    23176 Bytes = 22.63 KiB = 0.02 MiB
  Architecture: Unknown Architecture
  Hash algo:    crc32
  Hash value:   89c5e5a4
 Default Configuration: 'board-0'
 Configuration 0 (board-0)
  Description:  board_0
  Kernel:       unavailable
  Firmware:     atf
  FDT:          fdt-0
  Loadables:    uboot
  Sign algo:    crc32:dev
  Sign value:   unavailable
  Timestamp:    unavailable
```

### 6.2 Contract check, term by term

| §6.1 contract term | Required | Observed | |
|---|---|---|---|
| image `uboot` | `u-boot-nodtb.bin`, `type=standalone`, `arch=arm64`, `load = 0x80200000` (`CONFIG_TEXT_BASE`) | Standalone Program, AArch64, `0x80200000` | **[V]** |
| image `atf` | `bl31.bin`, `type=firmware`, `os=arm-trusted-firmware`, `load = entry = 0x80000000` | Firmware, OS "ARM Trusted Firmware", load `0x80000000`, and `entry = <0x80000000>` — read from the decompiled FIT, not assumed (`dumpimage -l` does not print `entry` for a firmware image) | **[V]** |
| image `fdt-0` | `u-boot.dtb`, description `"socfpga_socdk"` → **rename per board** | Flat Device Tree, description `socfpga_agilex5_de25nano` | **[V]** |
| config `board-0` | `default`; `firmware="atf" loadables="uboot" fdt="fdt-0"` | exactly that | **[V]** |
| signature | `algo = "crc32"`, no keys | `Sign algo: crc32:dev`, `Sign value: unavailable`; **no rsa anywhere in the file** | **[V]** |

**The whole FIT structure, decompiled (`dtc -I dtb -O dts`), contains ZERO occurrences of `rsa`,
`required` or `sha*`** — `grep -icE 'rsa|required|sha[0-9]'` → `0` **[V]**. The only integrity
material in the file is three `hash { algo = "crc32"; value = <...>; }` nodes and one
`signature { algo = "crc32"; key-name-hint = "dev"; sign-images = "atf","uboot","fdt-0"; }`.

The signature term is the one that could strand every board. The factory SPL is built with
`CONFIG_SPL_FIT_SIGNATURE=y` **[V `de25-boot-chain.md` §8.3]**, but the DTB carved from Terasic's
published SPL carries **no `/signature` node and no keys** **[V, same source]**, so
`fit_config_verify_required_sigs()` finds nothing required and an unsigned FIT is accepted. A
key-requiring FIT would fail on every board. Ours has a `crc32` integrity declaration and nothing
else — which is what the contract asks for.

Also settled at the desk and worth restating: `board_fit_config_name_match()` matches each
configuration node's **`description`** (`"board_%u"` from `socfpga_get_board_id()`), and
`fit_find_config_node()` falls back to `/configurations/default` when nothing matches, so a
**single-config FIT boots correctly regardless of board ID** **[V `de25-implementation-path.md`
§6.1]**. We leave `board-0`'s description at upstream's `board_0` for exactly that reason.

### 6.3 Address map — does anything collide?

The SPL stages the whole FIT at `CONFIG_SPL_LOAD_FIT_ADDRESS = 0x82000000` and then copies each
image to its `load` address **[V]**.

| Region | Range | Size |
|---|---|---|
| BL31 (`atf`, load = entry) | `0x8000_0000` → | 53,304 B (0xD038) |
| BL31 limit (TF-A `socfpga_plat_def.h:150`) | `0x8200_0000` | — |
| U-Boot proper (`uboot`, load) | `0x8020_0000` → | 650,048 B (0x9EB40) |
| FIT staging (SPL load address) | `0x8200_0000` → | 728,168 B (0xB1C68) total |
| DRAM (declared) | `0x8000_0000` – `0xBFFF_FFFF` | 1 GiB |

**No collision [V]:** BL31 ends far below `0x8020_0000`; U-Boot proper at `0x8020_0000` plus its
size ends far below `0x8200_0000`; the staged FIT starts at `0x8200_0000`, above both, and U-Boot
relocates itself to the top of DRAM immediately afterwards. `TF-A`'s `BL31_LIMIT` (`0x8200_0000`) is
exactly the FIT staging base, so the two never overlap even in principle.

The runtime kernel addresses are above all of it: `kernel_addr_r=0x82000000`,
`fdt_addr_r=0x86000000`, `scriptaddr=0x81000000` **[V, read from the built default environment]** —
by the time U-Boot proper loads a kernel there, the FIT staging copy is dead.

---

## 7. QSPI-write audit

The standard is [`de25-boot-chain.md`](de25-boot-chain.md) §7, rows 1, 5, 10, 11, 12. Values read
from the **resolved** `output-de25/build/uboot-2026.07/.config` — not from the fragment, because the
fragment is a request and kconfig is the answer.

**Read "off" precisely.** For most rows below the symbol is not merely `# ... is not set`: it is
**absent from the resolved config entirely**, because once `CADENCE_QSPI` and the SPI-NOR stack go,
the dependencies of `CMD_SF`, `SPI_FLASH*`, `DM_MTD`, `MTD_UBI`, `CMD_MTD`, `CMD_MTDPARTS`,
`CMD_UBIFS`, `ENV_IS_IN_UBI`, `ENV_IS_IN_SPI_FLASH` and `ENV_IS_IN_NAND` are unmet and kconfig drops
them. That is strictly stronger than "not set" — there is no line to flip **[V, observed]**. The
short form the task's checklist asks for:

```
$ grep -E 'CONFIG_ENV_IS_IN|CONFIG_SPL=|CONFIG_CMD_UBI|CONFIG_MTD|CONFIG_CMD_SF|CONFIG_CADENCE_QSPI' \
      output-de25/build/uboot-2026.07/.config
CONFIG_SPL=y
# CONFIG_CMD_UBI is not set
# CONFIG_ENV_IS_IN_EEPROM is not set
CONFIG_ENV_IS_IN_FAT=y
# CONFIG_ENV_IS_IN_EXT4 is not set
# CONFIG_ENV_IS_IN_FLASH is not set
# CONFIG_ENV_IS_IN_MMC is not set
# CONFIG_ENV_IS_IN_NVRAM is not set
# CONFIG_ENV_IS_IN_REMOTE is not set
# CONFIG_MTD is not set
# CONFIG_CADENCE_QSPI is not set
```

`CONFIG_ENV_IS_IN_UBI`, `CONFIG_CMD_SF` and every `SPI_FLASH*` symbol do not appear in that output
**because they no longer exist in the config at all**.

| Symbol | State | Can it write QSPI? | Verdict |
|---|---|---|---|
| `CONFIG_ENV_IS_IN_UBI` | **off** | **Yes — on LOAD, with no user action.** `env_ubi_load()` → `ubi_part()` → UBI attach on a blank MTD → `create_vtbl()` writes a layout volume | closed. §7 row 12's mandatory guard |
| `CONFIG_ENV_IS_IN_SPI_FLASH` | **off** (absent) | Yes — the environment would live in the QSPI | closed |
| `CONFIG_ENV_IS_IN_NAND` / `_MMC` | **off** | no (wrong media) / no | stated so a default flip cannot re-open them silently |
| `CONFIG_ENV_IS_IN_FAT` | **on**, `"0:1"` | no — SD only | the only env location. §5's fifth contract term |
| `CONFIG_CADENCE_QSPI` | **off** | **Yes — this is the only controller driver that reaches the flash** | closed. Lock 1 |
| `CONFIG_DM_SPI_FLASH` / `CONFIG_SPI_FLASH` | **off** (absent) | yes, via `sf`/MTD | closed. Lock 2 |
| `CONFIG_SPI_FLASH_MTD` | **off** | yes | closed |
| `CONFIG_SPI_FLASH_STMICRO` / `_SPANSION` | **off** | the actual `MT25QU128` chip driver | closed |
| `CONFIG_CMD_SF` | **off** | **Yes — `sf erase` / `sf write`.** Note it is `default y if DM_SPI_FLASH`, so it is **on** in the stock config | closed. Lock 3 |
| `CONFIG_CMD_SF_TEST` | **off** | yes — and its help text says "The test is destructive" | closed |
| `CONFIG_CMD_MTD` | **off** | **Yes — `mtd erase` / `mtd write`.** On in the stock config | closed |
| `CONFIG_CMD_MTDPARTS` | **off** | indirectly | closed |
| `CONFIG_CMD_UBI` | **off** | **Yes — `ubi part` auto-formats a blank MTD.** On in the stock config | closed |
| `CONFIG_CMD_UBIFS` | **off** | yes | closed |
| `CONFIG_MTD` / `CONFIG_DM_MTD` / `CONFIG_MTD_UBI` | **off** | the layers the above sit on | closed. Needed the §8 patch |
| `CONFIG_MTD_RAW_NAND` / `CONFIG_CMD_NAND` | **off** | no (no NAND on this board) | closed anyway |
| `CONFIG_SPL_SPI_LOAD`, `SPL_SPI_FLASH_MTD`, `SPL_DM_SPI_FLASH`, `SPL_MTD` | **off** | our SPL never runs, so these are inert either way | closed for tidiness |
| **`bootcmd_qspi`** (default env) | **absent** | **YES, AND THIS IS THE SHARPEST FINDING.** The stock `BOOTENV_DEV_QSPI` body in `include/configs/socfpga_soc64_common.h` is literally `"ubi detach; sf probe && … env select UBI; saveenv && ubi part root && …"` — a QSPI write *inside the default boot command*, reached by falling through `distro_bootcmd`. It is gated on `IS_ENABLED(CONFIG_CMD_SF)`, so turning `CMD_SF` off deletes the boot target **and** the env string | closed **[V, `boot_targets=mmc0` in the built default env]** |
| **`bootcmd_nand`** (default env) | **absent** | same shape, `env select UBI; saveenv; ubi part root` | closed (gated on `CMD_NAND`) |
| `linux_qspi_enable` (default env) | **present** | **Correction to an earlier draft of this table, which said "nothing invokes it".** Something does: `board_prep_linux()` in `arch/arm/mach-socfpga/board.c:194-197` runs `run_command(env_get("linux_qspi_enable"), 0)` on **every FIT-kernel boot**. The argument is the *gate*, not the caller — that block is `if (use_fit && IS_ENABLED(CONFIG_CADENCE_QSPI))`, and `CADENCE_QSPI` is compiled out, so the call site does not exist in our binary **[V, read]**. Belt-and-braces even if it did: the variable's body starts `if sf probe`, and `sf` is not a command here. (We boot via extlinux, not a FIT kernel, so `use_fit` would also be false — but that is the weakest of the three arguments and is not what this row rests on.) | **inert, and it is the Kconfig gate that makes it so** |
| `CONFIG_QSPI_BOOT` | **on** (inherited) | no. Despite the name it is a `boot/Kconfig` media choice consumed **only** by NXP Layerscape and i.MX code — every reference is under `arch/arm/cpu/armv8/fsl-layerscape`, `arch/arm/cpu/armv7/ls102xa` or `arch/arm/mach-imx` **[V, tree-wide grep]** | **inert, argued** |
| `CONFIG_SPI` / `CONFIG_DESIGNWARE_SPI` | **on** | no. A different controller (spi0/spi1 general-purpose pins), not the Cadence QSPI block behind the SDM | **inert, argued** |
| RSU (`cmd/rsu.c`, `CONFIG_CMD_RSU`) | **does not exist** in mainline v2026.07 | — | not applicable **[V, no such file]** |
| `CONFIG_SOCFPGA_SECURE_VAB_AUTH` | **off** | no | — |
| `CONFIG_BLOBLIST` | **off** | not QSPI — but it declared `0x7E000..0x7EFFF`, which covers TF-A's `PLAT_CPUID_RELEASE` (`0x7EFF0`) and `PLAT_SEC_ENTRY` (`0x7EFF8`) | closed. §4.4b — a latent RAM overlap, not a flash one, removed rather than argued |

**Second lock, outside Kconfig:** our board device tree declares no `&qspi` flash node and leaves
the controller at the SoC dtsi's `status = "disabled"`, so even a driver that somehow returned would
have nothing to bind to (§5).

**Third lock, outside U-Boot:** §7 row 11 — a Linux-side `fw_setenv` with an `fw_env.config` naming
an MTD device bypasses everything above. Nothing in this build ships `fw_setenv`
(`configs/fragments/de25nano.fragment` has no packages at all), but that is an accident of scope, not
a guard. §5's proposed release-blocking CI check ("the DE25 U-Boot config has `ENV_IS_IN_UBI` unset
and ships no QSPI-write command set") is still **unimplemented**; this table is what it should
assert.

---

## 8. The one carried U-Boot patch

`board/mister/de25nano/patches/uboot/0001-configs-socfpga_soc64-guard-mtdids-mtdparts-env.patch`.

Turning MTD off breaks the build:

```
include/configs/socfpga_soc64_common.h:133:19: error: expected '}' before 'CONFIG_MTDIDS_DEFAULT'
```

`CFG_EXTRA_ENV_SETTINGS` references `CONFIG_MTDIDS_DEFAULT` and `CONFIG_MTDPARTS_DEFAULT`
unconditionally in **all three** of its variants, and those symbols are
`depends on MTD || SPI_FLASH` (`cmd/Kconfig`) **[V]** — so they simply do not exist once a board
compiles the flash stack out. The patch wraps the two lines in a macro that expands to nothing when
neither symbol is defined. No functional change for any board that has MTD or SPI_FLASH; genuinely
upstreamable (not yet submitted).

**The alternative, if the owner prefers zero patches:** put `CONFIG_MTD=y` back. With no MTD device
driver compiled in (`CADENCE_QSPI`, all `SPI_FLASH_*`, `MTD_RAW_NAND` off) and no command that can
reach it (`CMD_MTD`, `CMD_MTDPARTS`, `CMD_UBI`, `CMD_SF` off), MTD would register zero devices and
be inert. That is a defensible row in §7 — it is just a weaker one than "absent from the binary",
and the consequence class here is brick-with-JTAG-recovery. **This is an owner call**; it is a
one-line change either way.

---

## 9. Boot flow as shipped

```
power-on
  -> SDM (hard microcontroller) reads QSPI  [factory, never ours]
     -> phase-1 HPS bitstream: pinmux + DDR handoff + the FSBL
        -> factory U-Boot SPL (Terasic, U-Boot 2025.01)
           - initialises DDR, prints its "DDR:" lines
           - reads /u-boot.itb from FAT partition 1 of the microSD
             (SPL_FS_LOAD_PAYLOAD_NAME under SPL_LOAD_FIT; boot partition 1)
           - stages the FIT at 0x82000000, copies:
                atf   -> 0x80000000   (and enters it)
                uboot -> 0x80200000
                fdt-0 -> passed to U-Boot as its control DTB
              -> BL31 (TF-A v2.15.0) -> U-Boot proper (v2026.07)   [ours]
                 - console on uart1 @115200 8N1 (serial0)
                 - DRAM from /memory in its own DTB (1 GiB @ 0x80000000)
                 - env from mmc 0:1 /uboot.env  (FAT; absent is fine, see §10)
                 - bootcmd = "run distro_bootcmd", boot_targets = "mmc0"
                   -> scans mmc 0, partition 1
                   -> finds /extlinux/extlinux.conf   (prefix "/" is tried first)
                   -> loads /Image and /socfpga_agilex5_de25nano.dtb
                   -> booti with the extlinux "append" line as bootargs
                      -> Linux 7.2.2, root=/dev/mmcblk0p2
```

### 9.1 The exact environment we ship

Read from `u-boot-initial-env` of this build — not inferred **[V]**:

```
bootcmd=run distro_bootcmd
distro_bootcmd=for target in ${boot_targets}; do run bootcmd_${target}; done
boot_targets=mmc0
bootcmd_mmc0=devnum=0; run mmc_boot
boot_prefixes=/ /boot/
boot_syslinux_conf=extlinux/extlinux.conf
bootdelay=5
bootargs=console=ttyS0,115200 root=/dev/mmcblk0p2 rw rootwait
kernel_addr_r=0x82000000
fdt_addr_r=0x86000000
scriptaddr=0x81000000
mmcroot=/dev/mmcblk0p2
```

(Read with `make u-boot-initial-env` in `output-de25/build/uboot-2026.07` — the shipped build tree,
not a scratch copy. `mtdids` and `mtdparts` are **absent** from the environment, which is the visible
effect of the §8 patch.)

`boot_targets` is **`mmc0` and nothing else** — the `qspi` and `nand` targets are gone with
`CMD_SF`/`CMD_NAND`, which is what deletes `bootcmd_qspi`'s embedded `saveenv`-into-QSPI (§7).

`scan_dev_for_extlinux` tries `${prefix}extlinux/extlinux.conf` with `boot_prefixes = "/ /boot/"`,
so **`/extlinux/extlinux.conf` at the root of partition 1 is found first** **[V]** — which matches
the card layout.

### 9.2 Card contract (D2.4's other half — confirmations for that track)

| Item | Confirmed | Note |
|---|---|---|
| p1 FAT32, MBR (no GPT), label `DE25BOOT` | **yes** | U-Boot reads FAT on an MBR/DOS partition table; `CONFIG_DOS_PARTITION` is on. The label is not used by anything in U-Boot |
| p1 holds `u-boot.itb`, `Image`, `socfpga_agilex5_de25nano.dtb`, `/extlinux/extlinux.conf` | **yes** | `/extlinux/...`, **not** `/boot/extlinux/...` — and `/` is the first prefix tried, so root-level is also the faster path |
| append `root=/dev/mmcblk0p2 rw rootwait console=ttyS0,115200 earlycon` | **yes** | extlinux's `append` **replaces** `bootargs` entirely; the fragment's `CONFIG_BOOTARGS` is only a hand-boot fallback |
| SD enumerates as **`mmc 0`** | **yes**, and now pinned | the board DTS declares `aliases { mmc0 = &mmc; }`; `boot_targets=mmc0`, `bootcmd_mmc0=devnum=0`, `ENV_FAT_DEVICE_AND_PART="0:1"` all agree |
| kernel format | **`Image`**, uncompressed | unchanged from D2.1 (`BR2_LINUX_KERNEL_IMAGE=y`). Nothing here needs `Image.gz`, and switching it would change three files at once |
| **MBR boot flag** | **already correct** | `scan_dev_for_boot_part` runs `part list mmc 0 -bootable devplist` and only falls back to `devplist=1` when **nothing** is bootable **[V, from the built env]**, so the flag is not inert — it *selects* which partition gets scanned. `genimage-sdcard.cfg` sets `bootable = "true"` on **p1 only** **[V, read]**, which is the right answer. The rule to keep: p1 bootable or nothing bootable; never p2 |
| `/extlinux/extlinux.conf` content | **matches** | `post-image.sh` generates `timeout 10` / `default de25` / `kernel /Image` / `fdt /socfpga_agilex5_de25nano.dtb` / `append root=/dev/mmcblk0p2 rw rootwait console=ttyS0,115200 earlycon` **[V, read]** — the same console and root this fragment's fallback `CONFIG_BOOTARGS` names |
| `uboot.env` on p1 | **not shipped, and should not be** | §10 |

---

## 10. The environment file — no seed, and the trace that says why

The question is whether a missing `uboot.env` on p1 is dangerous. **It is not, once
`ENV_IS_IN_UBI` is off, and the code path is short enough to state in full [V, v2026.07]:**

1. `env_fat_load()` (`env/fat.c`) does exactly two things on a missing file: prints
   `Unable to read "uboot.env" from mmc0:1...` and calls `env_set_default(NULL, 0)`, which loads the
   **built-in** environment into RAM. The only I/O it performs is `file_fat_read`. It returns
   `-EIO`. **No write, anywhere.**
2. `env_load()` (`env/env.c:172`) iterates the linker list. With `ENV_IS_IN_UBI` off there is
   **exactly one** driver compiled in, so there is no second location to fall through to —
   `env/ubi.c` is not in the binary at all.
3. On total failure `env_load()` sets `best_prio = 0` and `gd->env_load_prio = 0`
   (`env/env.c:222-227`), i.e. FAT. A later `saveenv` therefore prints
   `Saving Environment to FAT...` and **creates** the file on p1 — which is §7 row 5's assertion,
   satisfied without shipping anything.

**Recommendation: do not ship a seeded `uboot.env`.** A frozen copy on the card silently *overrides*
the compiled-in default environment forever after, so the next release's `bootcmd`, `bootargs` or
`boot_targets` change would be ignored on every already-written card — a staleness hazard we would
be adding for no safety benefit, since the branch it was meant to guard is not in the binary. If the
owner overrules this, the recipe is
`mkenvimage -s 0x2000 -o uboot.env <text>` (`CONFIG_ENV_SIZE=0x2000`), with
`BR2_TARGET_UBOOT_INITIAL_ENV=y` producing the exact default text to feed it. **Note that
`mkenvimage` is not built today** — it needs `BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE=y`, which is
deliberately off; only `FIT_SUPPORT` is on, for `dumpimage`.

---

## 11. First-boot serial expectations

Bring-up is a **read-the-console** exercise; nothing below is automatable yet.

**Capture the `DDR:` lines.** They come from the *factory* SPL's
`drivers/ddr/altera/sdram_agilex5.c`, which derives `hw_size` from `io96b_ctrl->overall_size`, caps
the DT-declared size at it, and prints
`DDR: Warning: DRAM size from device tree (...) exceeds the actual hardware capacity(...)` on a
mismatch **[V `de25-dts-rationale.md`, "Memory"]**. They are the **only** authority on this board's
real DRAM size — every "1 GiB" in this project is a vendor declaration awaiting exactly this
readout. A `DDR: Warning` means the constant in
`board/mister/de25nano/uboot-dts/socfpga_agilex5_de25nano.dts` (and the matching one in the kernel
DTS) is wrong.

Then, in order:

| Expect | Means |
|---|---|
| any output at all on uart1 @115200 8N1 | the alias/`stdout-path` pair is right. **Silence here is the failure this board file exists to prevent** |
| **NO `NOTICE:  BL31: v2.15.0…` lines** | **expected — absence is not failure.** TF-A's Agilex 5 platform registers its console at `PLAT_INTEL_UART_BASE`, which is `PLAT_UART0_BASE = 0x10C02000` **[V `plat/intel/soc/common/include/platform_def.h:156`, `plat/intel/soc/agilex5/include/socfpga_plat_def.h:154`, `bl31_plat_setup.c:61`]** — that is **uart0**, not the DE25's header UART at `0x10C02100`. So BL31 runs and says nothing on the cable you are watching. Do not read a missing BL31 banner as "BL31 did not run"; the thing that proves BL31 ran is the U-Boot banner on the next line, because U-Boot is BL33 and only BL31 gets there. (If you need BL31's own output, uart0 is exposed on the HPS header pins, or `PLAT_INTEL_UART_BASE` can be re-pointed in a TF-A rebuild — neither is needed for a normal bring-up.) |
| `U-Boot 2026.07 …` banner | the FIT parsed, BL31 ran, BL33 entered — i.e. the whole §2 pairing works. This is the [U] that only hardware closes |
| `DRAM:  1 GiB` | `dram_init()` took the `fdtdec` branch (§4.4). If instead U-Boot dies before the banner with `Missing SPL hand-off info`, `CONFIG_HANDOFF` came back on |
| `Loading Environment from FAT... ` then either `OK` or `Unable to read "uboot.env" from mmc0:1...` | §10. **`Loading Environment from UBI` must NEVER appear.** If it does, stop and do not boot again until the config is fixed — that message means the QSPI is being attached |
| `MMC:  mmc0@10808000: 0` | the SD controller bound and is device 0 |
| `Scanning mmc 0:1...` / `Found /extlinux/extlinux.conf` | §9's boot path |
| `Retrieving file: /Image` … `Retrieving file: /socfpga_agilex5_de25nano.dtb` | the card layout matches |
| `Starting kernel ...` | hand-off to Linux 7.2.2 |

**Do not** run `saveenv`, `sf`, `mtd` or `ubi` on the first session. The first three do not exist in
this build; typing them should produce `Unknown command` — which is itself a useful confirmation of
§7 and is worth capturing in the log.

---

## 12. Status ledger

| Claim | Tag |
|---|---|
| The build produces `images/u-boot.itb` and `images/bl31.bin` from mainline sources | **[V]** — this build |
| The FIT matches the §6.1 factory-SPL contract: images, load addresses, default config, crc32-only signature, no keys | **[V]** — `dumpimage`, §6 |
| No load or save path in this U-Boot can write the QSPI | **[V, config-traced]** — §7 |
| The stock `BLOBLIST_FIXED` region overlapped TF-A's secondary-CPU handshake words, and no longer exists in this build | **[V]** — §4.4b |
| U-Boot's SD access uses socdk's silicon-validated Agilex 5 PHY timings, at default speed only | **[V, config-traced]** — §5.1. Whether those timings suit *this* board is **[U]** until hardware |
| `# CONFIG_SPL is not set` does not work; SPL is compiled and nothing of it is shipped | **[V]** — §4.5, closes §8 Q6 |
| `boot_targets` contains only `mmc0`, and `bootcmd_qspi`'s embedded `saveenv` is gone | **[V]** — built default env |
| U-Boot 2026.07 + TF-A v2.15.0 boot this board under the factory SPL | **[U]** — needs hardware. ADR 0029 D4 |
| The factory SPL accepts our unsigned crc32 FIT | **[U]** — the *published* SPL DTB has no keys **[V]**; the *programmed* flash is unread |
| The SD controller works with our conservative `&mmc` block | **[U]** — needs hardware |
| DRAM is 1 GiB at `0x8000_0000` | **[U, vendor declaration]** — the `DDR:` lines settle it |
| The TF-A v2.15.0 tag signature is authentic | **[U]** — signing key not published on any reachable keyserver |
| Nothing else in the release writes QSPI (Linux side, `fw_setenv`, updater) | **[policy, unenforced]** — `de25-boot-chain.md` §5 |

---

## 12b. One change here that is not about U-Boot

The DE25's Buildroot configuration (`configs/fragments/de25nano.fragment`) is shared by three
tracks working in parallel, and the kernel track deliberately did not touch it — the kernel-config
commit's message says *"The defconfig switch (custom config + fragment, delete
de25nano/linux.fragment) lands with the U-Boot track's defconfig edit."* So this pass also lands
it:

```
# BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG is not set
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=".../board/mister/de25nano/linux.config"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=".../board/mister/common/linux-mister.fragment"
```

Rationale, measurements and per-subsystem justification are that track's
([`de25-kernel-config.md`](de25-kernel-config.md)), not this one's.
`board/mister/de25nano/linux.fragment` is referenced by nothing once this lands and is `git rm`'d
in the same commit.

---

## 13. Owner decisions this raises

1. **The carried U-Boot patch (§8)** vs putting `CONFIG_MTD=y` back and arguing inertness. One line
   either way.
2. **`CONFIG_HANDOFF` off + a declared 1 GiB (§4.4)** vs `CONFIG_BLOBLIST_ADDR=0x72000` and taking
   the measured size from the factory SPL. Recommendation: as shipped; revisit only if the board
   reports the wrong size.
3. **The `&mmc` block (§5.1)** — socdk's silicon-validated PHY timings, but default speed only at
   25 MHz. It is the first knob to turn if the card misbehaves, and §5.1 has both the diagnosis
   order and the one-line lift back to 50 MHz high speed. Faster than that needs the DE25's real
   vqmmc GPIO, which is a hardware-session observation.
4. **No seeded `uboot.env` (§10).**
5. **`CONFIG_FS_EXFAT=y`** anticipates §8 Q7 resolving toward exFAT on p2. If p2 stays ext4 forever,
   this line can go.
6. **`DISTRO_DEFAULTS` is deprecated upstream.** Migrating to `BOOTSTD_DEFAULTS` is a separate,
   testable change; doing it now would mean bring-up debugs two new things at once.
7. **The §5 CI check** ("`ENV_IS_IN_UBI` unset and no QSPI-write command set") is still
   unimplemented. §7 is the assertion list it should encode.
