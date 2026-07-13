# Boot chain analysis (P0.8 / constraint A3)

What runs between power-on and `/sbin/init` on a stock MiSTer, why each piece is shaped
the way it is, and exactly which of those facts constrain our kernel config, our
`zImage_dtb` assembly, and our initramfs.

Every claim below is either (a) a `file:line` at a pinned commit, (b) a byte offset in a
named artifact, or (c) a quoted script line. Nothing is asserted from memory.

## Sources

| Thing | Identity |
|---|---|
| U-Boot source | `work/U-Boot_MiSTer`, branch `MiSTer`, **`8dcc3484aac6f07314538e82530d446083085e12`** ("Adjust flag for cold boot.", 2021-11-12). All `u-boot:` citations are at this commit. |
| Kernel source | `work/Linux-Kernel_MiSTer`, branch `MiSTer-v5.15`, **`f0fb626acadd07f0718934826b143b6e4c9ce81c`**. All `linux:` citations are at this commit. |
| Main_MiSTer | `work/Main_MiSTer`, **`14052d21612df6136992190c0d5d4cbccbd816a9`**. |
| `uboot.img` | `work/extracted/files/linux/uboot.img`, 515,141 B, sha256 `e2d46cf9…62ba64` (see `docs/reference-materials.md`) |
| `zImage_dtb` | `work/extracted/files/linux/zImage_dtb`, 7,380,857 B, sha256 `a6c7b1be…dc8dae` |
| `updateboot` | `work/extracted/files/linux/updateboot`, 407 B |
| stock kernel `.config` | `work/stock-linux.config` (4,246 lines, IKCONFIG-extracted) |

Everything binary lives in gitignored `work/` (standing rule 1). Re-derive per
`docs/reference-materials.md`.

---

## 1. The chain, end to end

```
Cyclone V BootROM  (on-chip, immutable)
   │  scans the SD card's MBR for the first partition of type 0xA2,
   │  then reads a 64 KiB SPL image from its start. Four identical copies
   │  are stored back-to-back so a bad block/copy can be skipped.
   ▼
U-Boot SPL         (uboot.img @ 0/64/128/192 KiB, runs from on-chip RAM 0xFFFF0000)
   │  DDR calibration + pinmux + PLLs (QTS handoff headers), then loads
   │  U-Boot proper from partition_start + 0x200 sectors (= +256 KiB).
   ▼
U-Boot proper      (uImage @ uboot.img+0x40000, load/exec 0x01000040, relocates to top of DDR)
   │  bootcmd → mmcload → { fpgacheck ; scrtest ; load zImage_dtb ; compute fdt_addr }
   │          → mmcboot  → { setenv bootargs … ; bootz $loadaddr - $fdt_addr }
   ▼
Linux zImage       (loaded at 0x01000000; DTB pointer handed over in r2)
```

Two side effects happen *before* Linux starts and both are load-bearing:

* **The FPGA is already configured** (`menu.rbf` by default) and the HPS↔FPGA bridges are
  already enabled. Linux inherits a live fabric.
* **A 4 KiB window at `0x1FFFF000`** may have been read (and cleared) by U-Boot — it is the
  Main_MiSTer ⇄ U-Boot warm-reboot mailbox. Linux must never touch it. See §6.

---

## 2. `uboot.img`: SPL layout, verified byte-for-byte

`uboot.img` is U-Boot's `u-boot-with-spl.sfp` target, renamed. The recipe is literally four
`cat`s:

> `u-boot:Makefile:1068-1075`
> ```make
> ifneq ($(CONFIG_ARCH_SOCFPGA),)
> quiet_cmd_socboot = SOCBOOT $@
> cmd_socboot = cat	spl/u-boot-spl.sfp spl/u-boot-spl.sfp	\
> 			spl/u-boot-spl.sfp spl/u-boot-spl.sfp	\
> 			u-boot.img > $@ || rm -f $@
> u-boot-with-spl.sfp: spl/u-boot-spl.sfp u-boot.img FORCE
> 	$(call if_changed,socboot)
> endif
> ```

Verified in the shipped artifact:

| Offset | Size | Content | Verified |
|---|---|---|---|
| `0x00000` | 64 KiB | SPL copy 0 | sha256 of all four 64 KiB blocks identical |
| `0x10000` | 64 KiB | SPL copy 1 | ” |
| `0x20000` | 64 KiB | SPL copy 2 | ” |
| `0x30000` | 64 KiB | SPL copy 3 | ” |
| `0x40000` | 64 B | legacy uImage header | magic `0x27051956` ✓, header CRC ✓ |
| `0x40040` | 252,933 B | U-Boot proper (uncompressed ARM binary) | payload CRC32 `0xce778166` ✓ recomputed |
| — | | total | `0x40000 + 64 + 252,933 = 515,141` = exact file size ✓ |

**The SPL header.** `mkimage -T socfpgaimage` (`u-boot:scripts/Makefile.spl:288-289`) writes a
16-byte Altera "preloader" header at offset `0x40` *inside* each 64 KiB block
(`u-boot:tools/socfpgaimage.c:40-56`):

```c
#define HEADER_OFFSET   0x40
#define VALIDATION_WORD 0x31305341
#define PADDED_SIZE     0x10000
struct socfpga_header { u32 validation; u8 version; u8 flags;
                        u16 length_u32; u16 zero; u16 checksum; };
```

Read out of the artifact at `uboot.img+0x40`:
`41 53 30 31 | 00 | 00 | bf 2c | 00 00 | e0 01`
→ validation `0x31305341` ✓, version 0, flags 0, `length_u32` = 11,455 words = 45,820 bytes
(image + its 4-byte CRC), checksum `0x01e0`. A CRC32 word sits at offset 45,816 (`0xB2F8`)
per `u-boot:tools/socfpgaimage.c:119-121`, and everything from `0xB2FC` to `0xFFFF` is zero
padding — confirmed. The BootROM validates this header and the CRC before jumping in; that
is the *entire* reason the SPL must be `mkpimage`/`socfpgaimage`-wrapped and 64 KiB-padded.

**The uImage header** at `0x40000` (big-endian legacy format):

| Field | Value | Source of truth |
|---|---|---|
| magic | `0x27051956` | — |
| load / entry | `0x01000040` / `0x00000000` | `CONFIG_SYS_TEXT_BASE` = `0x01000040` (`u-boot:include/configs/socfpga_common.h:45`) |
| os / arch / type / comp | `17` (U-Boot) / `2` (ARM) / `5` (firmware) / `0` (none) | `MKIMAGEFLAGS_u-boot.img = -A $(ARCH) -T firmware -C none -O u-boot -a $(CONFIG_SYS_TEXT_BASE) …` (`u-boot:Makefile:955-957`) |
| name | `U-Boot 2017.03+ for de10-nano bo` (32-char truncation of `-n "U-Boot $(UBOOTRELEASE) for $(BOARD) board"`) | `u-boot:Makefile:957` |
| timestamp | `1743596165` = **2025-04-02 12:16:05 UTC** | matches `release_20250402` |

Version strings inside the payload: `U-Boot 2017.03+ (Apr 02 2025 - 20:16:03 +0800)` and
`U-Boot SPL 2017.03+ (Apr 02 2025 - 20:16:03)`, built with
`arm-none-linux-gnueabihf-gcc … 10.2.1 20201103` / `GNU ld … 2.35.1.20201028`.

### 2.1 Why the partition type must be 0xA2

The SPL finds U-Boot proper by *partition type*, not by a hardcoded LBA:

* `ARCH_SOCFPGA` unconditionally `select SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION`
  (`u-boot:arch/arm/Kconfig:792`).
* `SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION_TYPE` defaults `y` and
  `SYS_MMCSD_RAW_MODE_U_BOOT_PARTITION_TYPE` defaults **`0xa2`**
  (`u-boot:arch/arm/mach-socfpga/Kconfig:30-34`).
* `SYS_MMCSD_RAW_MODE_U_BOOT_USE_SECTOR` defaults `y` for `ARCH_SOCFPGA` and
  `SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR` defaults **`0x200`**
  (`u-boot:common/spl/Kconfig:91-97`, `:102-115`).
* `mmc_load_image_raw_partition()` walks MBR entries 1..4, takes the **first with
  `sys_ind == 0xa2`**, then loads from `info.start + 0x200` sectors
  (`u-boot:common/spl/spl_mmc.c:154-190`, the load at `:184-185`).

`0x200` sectors × 512 B = **262,144 B = 0x40000** — exactly where the uImage sits inside
`uboot.img`. So the contract is: *`uboot.img` is written raw to the start of the type-`0xA2`
partition, and everything else falls out of that.* Change the partition type and the board
does not boot; that is the whole recovery story for Phase 5.

---

## 3. The U-Boot environment: **binary vs. source cross-check**

### 3.1 Result: zero divergence

I re-extracted the built-in environment directly from the shipped binary
(`work/uboot-proper.bin`, env blob at file offset `0x28018`–`0x28495`, 1,149 bytes of
NUL-separated `k=v` strings) and compared it to what the source at `8dcc3484` produces.

**Every variable, every value, and the ordering match exactly.** The order is dictated by
`u-boot:include/env_default.h:31-84` (the fixed prefix) followed by `:107-109`
(`CONFIG_EXTRA_ENV_SETTINGS` verbatim), and the binary reproduces that order literally:

| # | Variable (from the binary) | Defined at |
|---|---|---|
| 0 | `bootargs=console=ttyS0,115200 $v loop.max_part=8 mem=511M memmap=513M$511M` | `CONFIG_BOOTARGS`, `socfpga_de10_nano.h:22` (via `env_default.h:32`) |
| 1 | `bootcmd=mw 0xff709004 0x800; run mmcload; run mmcboot` | `CONFIG_BOOTCOMMAND`, `socfpga_de10_nano.h:23` |
| 2 | `bootdelay=0` | `CONFIG_BOOTDELAY=0`, `configs/socfpga_de10_nano_defconfig:57` |
| 3 | `baudrate=115200` | `CONFIG_BAUDRATE` |
| 4 | `bootfile=fitImage` | `socfpga_de10_nano.h:21` |
| 5 | `loadaddr=0x01000000` | `CONFIG_LOADADDR`, `socfpga_de10_nano.h:24` (via `env_default.h:83`) |
| 6 | `loadaddr=0x01000000` *(duplicate)* | `socfpga_de10_nano.h:41` — `CONFIG_EXTRA_ENV_SETTINGS` re-emits it |
| 7 | `bootimage=/linux/zImage_dtb` | `socfpga_de10_nano.h:42` |
| 8 | `fdt_addr=100` | `socfpga_de10_nano.h:43` |
| 9 | `fpgadata=0x02000000` | `socfpga_de10_nano.h:44` |
| 10 | `core=menu.rbf` | `socfpga_de10_nano.h:45` |
| 11 | `fpgacheck=…` | `socfpga_de10_nano.h:46` |
| 12 | `fpgaload=…` | `socfpga_de10_nano.h:47` |
| 13 | `scrtest=…` | `socfpga_de10_nano.h:48` |
| 14 | `ethaddr=02:03:04:05:06:07` | `socfpga_de10_nano.h:49` |
| 15 | `bootm $loadaddr - $fdt_addr` *(no `=`; malformed)* | `socfpga_de10_nano.h:50` |
| 16 | `mmc_boot=1` | `socfpga_de10_nano.h:51` ← `CONFIG_SYS_MMCSD_FS_BOOT_PARTITION 1` (`:36`) |
| 17 | `mmcroot=/dev/mmcblk0p1` | `socfpga_de10_nano.h:52` ← same macro |
| 18 | `v=loglevel=4` | `socfpga_de10_nano.h:53` |
| 19 | `mmcboot=…` | `socfpga_de10_nano.h:54` |
| 20 | `mmcload=…` | `socfpga_de10_nano.h:55-60` |

Notes on three entries that matter:

* **`v=loglevel=4`** — the verification doc listed `$v` in `bootargs` without recording its
  default. The *effective* default cmdline therefore contains `loglevel=4`. `u-boot.txt` is
  the file users override it with (`u-boot.txt_example` is exactly
  `v=loglevel=4 usbhid.jspoll=1 xpad.cpoll=1`).
* **`ethaddr=02:03:04:05:06:07`** — a fixed *fallback* MAC compiled in. Every board would
  present the same MAC unless `u-boot.txt` overrides `ethaddr`, which is precisely what
  `mr-fusion` writes at install time (PLAN §8). Under ADR 0017 the `u-boot.txt`
  machinery itself comes with the fork source; what Phase 5 must still reproduce is
  mr-fusion's per-board `ethaddr` *provisioning* — a first-boot write of
  `linux/u-boot.txt` with a unique MAC (P5.3).
* **Entry 15 has no `=`.** `"bootm $loadaddr - $fdt_addr\0"` in `CONFIG_EXTRA_ENV_SETTINGS`
  is a source bug — an orphaned string with no variable name, left over from an earlier edit
  of the file. It is present in the shipped binary's default-env blob. It is harmless: the
  default env is imported with `himport_r(…, sep='\0', …)`, and an entry with no `=` before
  the separator falls into the "delete candidate" branch
  (`u-boot:lib/hashtable.c:883-897`) — it tries to *delete* a variable literally named
  `bootm $loadaddr - $fdt_addr`, finds none, and no-ops. **No variable is created.** Its
  presence is, however, a fingerprint: it confirms the binary was built from *this* header,
  unmodified.

**Verdict: the shipped `uboot.img` was built from `U-Boot_MiSTer` at (or environment-identical
to) `8dcc3484`.** The last commit that touched `include/configs/socfpga_de10_nano.h` *is*
`8dcc3484` (2021-11-12); the binary was compiled 2025-04-02. Nothing in the environment was
patched post-build. There is **no divergence to flag** for P5, and the plan's claim that
shipping the stock `uboot.img` byte-identical is safe stands on solid ground: the binary is
what the source says it is.

### 3.2 Can we rebuild `uboot.img` byte-identically? **No — and we don't need to.**

Blocking factors, in order of severity:

1. **Build timestamp is compiled in and is not from `SOURCE_DATE_EPOCH`.** The binary's
   version string carries `+0800`; `u-boot:Makefile:1303-1312` only uses `SOURCE_DATE_EPOCH`
   when it is set, and when set it forces `date -u` (`+0000`). A `+0800` string therefore
   *proves* the shipped build did **not** set `SOURCE_DATE_EPOCH`. Reproducing it requires
   pinning both `SOURCE_DATE_EPOCH=1743596163` **and** `TZ=Asia/Shanghai` (or equivalent) —
   and even then the mkimage timestamp (`1743596165`, two seconds later) came from
   wall-clock at `mkimage` time, not from the compile.
2. **Exact toolchain.** Arm GNU Toolchain 10.2-2020.11 (`gcc 10.2.1 20201103`,
   `binutils 2.35.1.20201028`). Any other compiler reorders/reallocates code.
3. Build-path and `$(srctree)` leakage in `__FILE__`-style strings (not audited).

**Consequence for the plan (no change to the decision, only to the justification):** we must
ship `uboot.img` **byte-identical by copying the stock artifact**, not by rebuilding it. This
is already what PLAN §8 / TASKS P4.4 say ("shipped `uboot.img` hash equals the stock
release's"); this analysis is the proof that a rebuild could never satisfy that check. Store
the stock blob as a release input (fetched by hash from the pinned SD-Installer commit),
never as a build output. Because it is a binary, it cannot be committed (standing rule 1) —
CI must fetch it and verify sha256 `e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64`.

*(ADR 0017 does not change this: the default channel keeps the stock blob. Phase 5's
from-source build — same commit, `8dcc3484` — ships opt-in only and is validated by
behavioural parity (P5.2), not byte identity.)*

### 3.3 `mt` is a MiSTer-only U-Boot command (was a Phase-5 blocker; moot under ADR 0017)

`fpgacheck` uses `mt`, which is **not** an upstream U-Boot command. It was added by this fork
(`u-boot` commit `c0ed23f52e` "Implement simple memory test against value"):

> `u-boot:cmd/mem.c:158-180`, registered at `:1259-1263`
> ```c
> static int do_mem_mt(cmd_tbl_t *cmdtp, int flag, int argc, char * const argv[])
> {   …
>     rc = memcmp(buf, &val, size) ? 1 : 0;   /* 0 == equal == shell "true" */
> }
> U_BOOT_CMD(mt, 3, 1, do_mem_mt, "memory test against value", "[.b, .w, .l] address value");
> ```

So `if mt <addr> <val>; then …` means *"if the word at `addr` equals `val`"*. **Any mainline
U-Boot port must re-implement `mt` or rewrite `fpgacheck` without it** (e.g.
`setexpr` + `test`). *(ADR 0017 dissolved this blocker: Phase 5 now builds this fork
itself, so `mt` ships with it. The paragraph stands as part of the record of why the
mainline port was the more expensive path.)*

---

## 4. The boot command, verbatim, matched to source

Quoted from `u-boot:include/configs/socfpga_de10_nano.h:22-23` and `:40-60`, with the
`__stringify()` macros expanded to what the binary actually contains:

```
bootcmd   = mw 0xff709004 0x800; run mmcload; run mmcboot

mmcload   = mmc rescan;
            run fpgacheck;
            run scrtest;
            load mmc 0:$mmc_boot $loadaddr $bootimage;
            setexpr.l fdt_addr $loadaddr + 0x2C;
            setexpr.l fdt_addr *$fdt_addr + $loadaddr

mmcboot   = setenv bootargs console=ttyS0,115200 $v loop.max_part=8 mem=511M memmap=513M$511M
                           root=$mmcroot loop=linux/linux.img ro rootwait;
            bootz $loadaddr - $fdt_addr

scrtest   = if test -e mmc 0:$mmc_boot /linux/u-boot.txt;
            then load mmc 0:$mmc_boot $loadaddr /linux/u-boot.txt;
                 env import -t $loadaddr;
            fi

fpgacheck = if mt 0x1FFFFF08 0xBEEFB001;
            then mw 0x1FFFFF08 0;
                 if mt 0x1FFFF000 0x87654321;
                 then mw 0x1FFFF000 0; env import -t 0x1FFFF004; run fpgaload;
                 fi;
            else run fpgaload;
            fi

fpgaload  = load mmc 0:$mmc_boot $fpgadata $core;
            fpga load 0 $fpgadata $filesize;
            bridge enable;
            mw 0x1FFFF000 0;
            mw 0xFFD05054 0
```

Line by line:

* **`mw 0xff709004 0x800`** — GPIO1 (`SOCFPGA_GPIO1_ADDRESS = 0xff709000`,
  `u-boot:arch/arm/mach-socfpga/include/mach/base_addr_ac5.h:17`) `+0x04` is the DesignWare
  `gpio_swporta_ddr` (direction) register; `0x800` makes bit 11 an output. Added by commit
  `56104e0834` *"Switch TS3A5018 to SPI mode ASAP to prevent brightness screw on pi-top"* —
  it is an analog-switch/brightness workaround for the pi-top chassis, executed as early as
  possible. Nothing to do with the kernel; do not remove it in Phase 5.
* **`mmc rescan`** — re-probe the SD card.
* **`run fpgacheck`** — §6.
* **`run scrtest`** — load `/linux/u-boot.txt` from the FAT partition **to `$loadaddr`** and
  `env import -t` it. This happens *before* the kernel is loaded to the same address, so
  there is no conflict. Note that `env import -t <addr>` is called **without a size**: U-Boot
  then scans forward for a `'\n'` immediately followed by `'\0'`
  (`u-boot:cmd/nvedit.c:1049-1066`). A `u-boot.txt` **must therefore end with a newline**.
* **`load mmc 0:$mmc_boot $loadaddr $bootimage`** — reads the whole `zImage_dtb` (`mmc_boot=1`
  → MMC device 0, **partition 1**, the FAT/exFAT data partition) to `0x01000000`.
* **`setexpr.l fdt_addr $loadaddr + 0x2C` / `setexpr.l fdt_addr *$fdt_addr + $loadaddr`** —
  §7. This is A3.
* **`setenv bootargs …`** — builds the cmdline from `CONFIG_BOOTARGS` plus
  `root=$mmcroot loop=linux/linux.img ro rootwait`.
* **`bootz $loadaddr - $fdt_addr`** — boot a raw zImage, **no initrd** (`-`), with an explicit
  DTB pointer.

### 4.1 The effective default kernel command line

With no `u-boot.txt` present, the kernel receives exactly:

```
console=ttyS0,115200 loglevel=4 loop.max_part=8 mem=511M memmap=513M$511M root=/dev/mmcblk0p1 loop=linux/linux.img ro rootwait
```

(`$v` → `loglevel=4`, `$mmcroot` → `/dev/mmcblk0p1`.)

### 4.2 How bootargs actually reach the kernel: `/chosen` FDT fixup, not ATAGs

`bootz` runs the FDT state of `bootm`, which calls `image_setup_libfdt()`
(`u-boot:common/image-fdt.c:461`), which calls `fdt_chosen()`
(`u-boot:common/image-fdt.c:473`):

> `u-boot:common/fdt_support.c:275-304`
> ```c
> int fdt_chosen(void *fdt) {
>     nodeoffset = fdt_find_or_add_subnode(fdt, 0, "chosen");
>     str = getenv("bootargs");
>     if (str)
>         err = fdt_setprop(fdt, nodeoffset, "bootargs", str, strlen(str) + 1);
>     return fdt_fixup_stdout(fdt, nodeoffset);
> }
> ```

Then the jump into Linux:

> `u-boot:arch/arm/lib/bootm.c:365-378`
> ```c
> if (IMAGE_ENABLE_OF_LIBFDT && images->ft_len)
>         r2 = (unsigned long)images->ft_addr;   /* <-- DTB pointer */
> else
>         r2 = gd->bd->bi_boot_params;           /* <-- the ATAG path; NOT taken */
> …
> kernel_entry(0, machid, r2);
> ```

`images->ft_len` is non-zero (we passed `$fdt_addr`), so **`r2` is the DTB physical address
and no ATAG list is ever constructed**. This is the ARM DT boot protocol, full stop.

Corollary, verified in the artifact: the stock DTB's *static* `/chosen` is

```dts
chosen {
    bootargs = "earlyprintk";
    stdout-path = "serial0:115200n8";
};
```
(`work/stock.dts:951-954`) — and `fdt_chosen()` **overwrites** `bootargs` before boot. The
string `earlyprintk` never reaches the kernel, and would be inert anyway
(`# CONFIG_DEBUG_LL is not set`, no `CONFIG_EARLY_PRINTK` in `work/stock-linux.config`).
Do not carry `earlyprintk` forward as if it did anything.

---

## 5. `updateboot` — quoted in full, and its two consequences

The 407-byte script the Downloader runs on **every** linux update
(`work/extracted/files/linux/updateboot`, mode 0755, rsynced into `/media/fat/linux/`):

```sh
#!/bin/sh

if [ -f /media/fat/linux/uboot.img ]; then

	echo ""
	echo "Erasing u-boot saved environment"
	dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=1 count=1
	echo ""

	if [ -b /dev/mmcblk0p3 ]; then
		echo "Using old layout"
		dd if=/media/fat/linux/uboot.img of=/dev/mmcblk0p3
	else
		echo "Using new layout"
		dd if=/media/fat/linux/uboot.img of=/dev/mmcblk0p2
	fi
	
	echo ""
	echo "Done."
	echo ""
fi
```

Line by line:

| Line | Meaning |
|---|---|
| `if [ -f /media/fat/linux/uboot.img ]` | The whole script is a no-op if we ship no `uboot.img`. (Tempting; but the Downloader `rsync`s our `files/linux/` **over** `/media/fat/linux/`, and rsync without `--delete` would leave the *previous* `uboot.img` in place, so omitting it does not disable the flash — it silently re-flashes a stale one. Ship the stock blob.) |
| `dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=1 count=1` | Zeroes **sector 1** of the raw SD card = bytes 512–1023. |
| `if [ -b /dev/mmcblk0p3 ]` | Old MiSTer SD layout had the `0xA2` boot partition as **p3**; the current layout has it as **p2**. Presence of a third partition selects the old path. |
| `dd if=…/uboot.img of=/dev/mmcblk0p{2,3}` | Writes all 515,141 bytes to the **start of the `0xA2` partition** — which is exactly what §2.1 requires: SPL copies at partition-relative 0/64/128/192 KiB, uImage at partition-relative `0x40000` = sector `0x200`. |

### Consequence (a): whatever `uboot.img` we ship gets flashed — verified

There is no version check, no hash check, no opt-out. **On every linux update, the
`uboot.img` sitting in `/media/fat/linux/` is `dd`'d over the boot partition.** Combined with
the Downloader's `rsync -a` of `files/linux/` (A8), that means *our release archive's
`uboot.img` becomes the board's bootloader.* Shipping the stock blob byte-identical in v1 is
therefore not conservatism — it is the only way not to take the U-Boot blast radius in
Phase 1. ✔ Claim confirmed.

### Consequence (b): U-Boot's saved environment never survives — verified

`CONFIG_ENV_IS_IN_MMC` is set (`u-boot:include/configs/socfpga_de10_nano.h:33`) and

> `u-boot:include/configs/socfpga_common.h:200-207`
> ```c
> #if !defined(CONFIG_ENV_SIZE)
> #define CONFIG_ENV_SIZE         4096
> #endif
> #if defined(CONFIG_ENV_IS_IN_MMC) && !defined(CONFIG_ENV_OFFSET)
> #define CONFIG_SYS_MMC_ENV_DEV  0        /* device 0 */
> #define CONFIG_ENV_OFFSET       512      /* just after the MBR */
> ```

The saved environment lives at **byte offset 512 of `/dev/mmcblk0`** (i.e. sector 1), 4096
bytes long, whose **first four bytes are the CRC32** that validates it. `updateboot`'s
`dd … seek=1 count=1` (bs=512) zeroes bytes 512–1023 — destroying the CRC and the head of the
blob. On the next boot the CRC check fails and U-Boot falls back to `default_environment[]`
(`u-boot:common/env_common.c:35-42`, `:98-105`).

**Therefore the effective U-Boot environment is always `built-in defaults + u-boot.txt`.** No
`saveenv` state can persist across an update. ✔ Claim confirmed. Two things follow:

* Our `/init` (A2) can rely on the cmdline shape being *either* the compiled-in default *or*
  a `u-boot.txt`-modified variant of it — never some third saved-env variant.
* Any Phase-5 U-Boot must keep working with a **wiped** env area, because `updateboot` will
  keep wiping it. Do not design a Phase-5 feature that depends on `saveenv`.

---

## 6. The FPGA preload path and the warm-reboot mailbox

### 6.1 U-Boot's side

`fpgaload` = *"read `$core` (default `menu.rbf`) from the FAT partition to `$fpgadata`
(0x02000000), push it into the fabric, enable the bridges, then clear the mailbox."*

* `load mmc 0:$mmc_boot $fpgadata $core` — `$core` defaults to `menu.rbf`
  (`socfpga_de10_nano.h:45`), read from partition 1's root.
* `fpga load 0 $fpgadata $filesize` — configure the Cyclone V fabric.
* `bridge enable` — turn on HPS↔FPGA bridges (lwhps2fpga / hps2fpga / fpga2hps) so Linux and
  Main_MiSTer find a live fabric at `0xC0000000` / `0xFF200000`.
* `mw 0x1FFFF000 0` — clear the env-staging magic.
* `mw 0xFFD05054 0` — clear the Reset Manager's `tstscratch` register.
  `SOCFPGA_RSTMGR_ADDRESS = 0xffd05000` and `struct socfpga_reset_manager` places
  `tstscratch` at **+0x54** (`u-boot:arch/arm/mach-socfpga/include/mach/reset_manager.h:18-30`).
  This is vestigial: `tstscratch` *was* the cold-boot flag until commit `8dcc3484` moved the
  flag into DDR (see below). Harmless, still written.

`fpgacheck` is the dispatcher:

| `[0x1FFFFF08]` | `[0x1FFFF000]` | Action |
|---|---|---|
| `0xBEEFB001` | `0x87654321` | Consume both magics; `env import -t 0x1FFFF004` (pulls in a new `core=` and any core-specific vars); `run fpgaload` → **load the requested core** |
| `0xBEEFB001` | anything else | Consume the flag; **do nothing** — leave the currently-configured fabric alone (this is "reboot without changing core") |
| anything else | — | Cold boot → `run fpgaload` → **load `menu.rbf`** |

### 6.2 Main_MiSTer's side — the writer

The producer of those magics is `work/Main_MiSTer` @ `14052d2`:

> `Main_MiSTer:fpga_io.cpp:395-424`
> ```c
> static int make_env(const char *name, const char *cfg)
> {
>     void* buf = shmem_map(0x1FFFF000, 0x1000);       /* mmap via /dev/mem */
>     volatile char* str = (volatile char*)buf;
>     memset((void*)str, 0, 0xF00);
>     *str++ = 0x21; *str++ = 0x43; *str++ = 0x65; *str++ = 0x87;   /* LE u32 = 0x87654321 */
>     *str++='c'; *str++='o'; *str++='r'; *str++='e'; *str++='='; *str++='"';
>     for (…) *str++ = name[i];                        /* the .rbf path */
>     *str++ = '"'; *str++ = '\n';
>     FileLoad(cfg, (void*)str, 0);                    /* append the core's .cfg text */
>     shmem_unmap(buf, 0x1000);
> }
> ```
> `Main_MiSTer:fpga_io.cpp:588-606`
> ```c
> void reboot(int cold)
> {
>     sync();
>     fpga_core_reset(1);
>     usleep(500000);
>     void* buf = shmem_map(0x1FFFF000, 0x1000);
>     volatile uint32_t* flg = (volatile uint32_t*)buf;
>     flg += 0xF08/4;                                  /* -> 0x1FFFFF08 */
>     *flg = cold ? 0 : 0xBEEFB001;
>     shmem_unmap(buf, 0x1000);
>     writel(1, &reset_regs->ctrl);                    /* Reset Manager ctrl, 0xFFD05004 */
>     while (1) sleep(1);
> }
> ```

Callers: `fpga_load_rbf()` calls `make_env(name, cfg); do_bridge(0); reboot(0)` when a core
carries a `.cfg` (`Main_MiSTer:fpga_io.cpp:432-438`); `reboot(1)` (cold) is the plain
"Reboot" menu item (`menu.cpp:3079`, `:6854`, `user_io.cpp:3764`).

### 6.3 The full 4 KiB mailbox map

| Address | Size | Written by | Read by | Meaning |
|---|---|---|---|---|
| `0x1FFFF000` | 4 B | `make_env` (`fpga_io.cpp:403-406`) | `fpgacheck` (`mt 0x1FFFF000 0x87654321`) | "an env blob is staged" |
| `0x1FFFF004`–`0x1FFFFEFF` | ~3,836 B | `make_env` (`core="…"\n` + the core's `.cfg`) | `env import -t 0x1FFFF004` | the staged text env. `make_env` zeroes `0..0xF00` first, which is what terminates the import (`u-boot:cmd/nvedit.c:1049-1066` scans for `'\n'` then `'\0'`). |
| `0x1FFFFF00` | 4 B | `sdram_sz()` (`user_io.cpp:1304-1336`), magic `0x12,0x57` + 16-bit size | `sdram_sz(-1)` after reboot | SDRAM-module config, handed across the reboot **Main→Main** |
| `0x1FFFFF04` | 4 B | `altcfg()` (`user_io.cpp:1338-1360`), magic `0x34,0x99,0xBA` + alt | `altcfg(-1)` | alternate-core selection, **Main→Main** |
| `0x1FFFFF08` | 4 B | `reboot()` (`fpga_io.cpp:600`) | `fpgacheck` (`mt 0x1FFFFF08 0xBEEFB001`) | warm-reboot flag |

Note `make_env`'s `memset(str, 0, 0xF00)` stops at `0xF00` **on purpose** — it must not
clobber the `sdram_sz`/`altcfg`/reboot-flag words at `0xF00`/`0xF04`/`0xF08`.

Note also: `reboot()` writes **`1`** to `rstmgr.ctrl`. U-Boot's own header says
`RSTMGR_CTRL_SWWARMRSTREQ_LSB = 1` (`reset_manager.h:35`), i.e. bit **1** is the *warm* reset
request — so value `1` (bit 0) is `swcoldrstreq`, a **cold** hardware reset. The "warm" in
"warm reboot" is purely the *software* flag at `0x1FFFFF08`; both paths take the same
hardware reset, the SPL re-calibrates DDR, and the DRAM *contents* at `0x1FFFF000` survive
the reset window. That survival is exactly what commit `8dcc3484` ("Adjust flag for cold
boot") relies on — it replaced the old `tstscratch`-based flag (which a cold reset clears)
with a DDR-resident flag (which it does not).
*Not independently confirmed on hardware; asserted from source + the fact that the shipped
firmware depends on it.*

### 6.4 The arithmetic: why `mem=511M` is untouchable

Physical DDR on the DE10-Nano is 1 GiB (`PHYS_SDRAM_1_SIZE 0x40000000`,
`u-boot:include/configs/socfpga_de10_nano.h:18`), starting at `0x00000000`.

| | Address | Bytes | MiB |
|---|---|---|---|
| kernel's memory limit (`mem=511M`) | `0x1FF00000` | 535,822,336 | **511.00000** |
| **mailbox base** `0x1FFFF000` | `0x1FFFF000` | 536,866,816 | **511.99609** |
| **warm flag** `0x1FFFFF08` | `0x1FFFFF08` | 536,870,664 | **511.99976** |
| 512 MiB boundary | `0x20000000` | 536,870,912 | 512.00000 |
| `memmap=513M$511M` region | `0x1FF00000`–`0x40000000` | 511 MiB … 1024 MiB | (see below) |

**`0x1FFFF000` sits at 511.996 MiB — 1,044,480 bytes ABOVE the 511 MiB the kernel is told
about, in the last 4 KiB before the 512 MiB line.** It is not a near miss; the whole mailbox
lives in the reserved region by design.

The kernel *cannot* touch it. `mem=511M` is handled by `early_mem()`:

> `linux:arch/arm/kernel/setup.c:819-846`
> ```c
> static int __init early_mem(char *p) {
>     if (usermem == 0) {
>         usermem = 1;
>         memblock_remove(memblock_start_of_DRAM(),
>                         memblock_end_of_DRAM() - memblock_start_of_DRAM());
>     }
>     start = PHYS_OFFSET;
>     size  = memparse(p, &endp);
>     …
>     arm_add_memory(start, size);
>     return 0;
> }
> early_param("mem", early_mem);
> ```

It **discards every memory region the DTB advertised** (U-Boot fixes `/memory` up to the real
1 GiB) and adds back exactly `[0x00000000, 0x1FF00000)`. Anything at or above `0x1FF00000`
is not memory as far as memblock, the buddy allocator, and the kernel linear map are
concerned. The *only* way to reach `0x1FFFF000` from Linux is an explicit `/dev/mem` mmap —
which is precisely what `shmem_map()` does. (This is a second, independent reason A4 —
`DEVMEM=y`, `STRICT_DEVMEM=n` — is load-bearing.)

> ### Correction to PLAN §3 and to the verification doc
>
> **`memmap=513M$511M` does nothing on ARM.** `early_param("memmap", …)` exists only in
> `arch/x86/kernel/e820.c:989`, `arch/mips/kernel/setup.c:407`, and
> `arch/xtensa/mm/init.c:218`. There is **no `memmap=` parser under `arch/arm/`** — verified
> by grepping the entire 5.15 MiSTer tree. The argument is inert: the kernel does not
> recognise it, and passes it through to userspace as an init environment variable.
>
> **`mem=511M` is doing 100 % of the reservation work.** The plan's *conclusion* is unchanged
> and still right — keep the cmdline byte-identical, because it is what U-Boot emits and
> because `mem=511M` genuinely is untouchable — but the *stated reason* ("`mem=511M`/`memmap=`
> reserve the FPGA region") over-attributes it. P0.9 should fold this correction into
> PLAN §3 and A3's wording.

---

## 7. The `zImage_dtb` contract (A3) — what P1.11 must assert

### 7.1 The mechanism

```
setexpr.l fdt_addr $loadaddr + 0x2C      ; fdt_addr = 0x0100002C
setexpr.l fdt_addr *$fdt_addr + $loadaddr; fdt_addr = *(u32*)0x0100002C + 0x01000000
```

`+0x2C` in the ARM zImage header is `zimage_end` — the **declared size of the zImage**
(`arch/arm/boot/compressed/head.S`; the header is `magic` at `+0x24`, `start` at `+0x28`,
`end` at `+0x2C`, all little-endian). So U-Boot's DTB address is *the first byte after the
zImage*. A plain `cat zImage dtb` puts the DTB exactly there. **Nothing else does** — a single
byte of alignment padding breaks it silently (U-Boot would hand the kernel a pointer into
padding, and `bootz` fails with "Bad Linux ARM zImage magic!"-class errors or the kernel
dies with no console output).

### 7.2 Independently verified against the shipped artifact

Parsed from `work/extracted/files/linux/zImage_dtb` (7,380,857 bytes):

| Check | Value |
|---|---|
| `+0x24` (LE32) zImage magic | `0x016F2818` ✓ |
| `+0x28` (LE32) declared start | `0` |
| **`+0x2C` (LE32) declared end** | **`0x00705148` = 7,360,840** |
| byte 7,360,840 (BE32) | **`0xD00DFEED`** ✓ FDT magic sits exactly there |
| byte 7,360,844 (BE32) FDT `totalsize` | 20,017 |
| `7,360,840 + 20,017` | **= 7,380,857 = EOF exactly** ✓ |
| U-Boot's computed `fdt_addr` | `0x01000000 + 0x00705148` = **`0x01705148`** |

This independently reproduces the verification doc's numbers. ✔ No correction needed.

### 7.3 The size budget

`loadaddr = 0x01000000`, `fpgadata = 0x02000000` → the kernel blob may occupy at most
**16 MiB (16,777,216 bytes)** before it would overwrite the buffer U-Boot stages `menu.rbf`
into. (Ordering saves us in the *stock* flow — `fpgacheck`/`fpgaload` run *before* the kernel
`load` — but a blob past `0x02000000` would be clobbered by the *next* boot's `fpga load`
staging on a warm-reboot path, and in any case the kernel would be decompressing over the
FPGA staging area. Treat 16 MiB as hard.)

| | Bytes | MiB |
|---|---|---|
| Budget (`fpgadata − loadaddr`) | 16,777,216 | 16.000 |
| Stock `zImage_dtb` | 7,380,857 | 7.039 (44.0 % of budget) |
| **Headroom** | **9,396,359** | **8.961** |
| Top address of stock blob | `0x01709F79` | — |

**8.96 MiB of headroom.** Our kernel will be bigger (6.18 + an embedded ~200–500 KB
initramfs + `BLK_DEV_INITRD`), but not 9 MiB bigger. The budget is comfortable, not tight —
but P1.11 must still assert it, because an accidental `BR2_TARGET_ROOTFS_INITRAMFS` (A1's
failure mode: ~300 MB embedded) would blow it by a factor of 20 and this check would catch it
loudly at build time instead of as a mystery brick.

### 7.4 The scripted assertion → **`scripts/check-zimage-dtb.sh`**

Written, shellcheck-clean, POSIX `sh`, no Python dependency (`od` + shell arithmetic). Run it
on every build in `post-image.sh` (P1.11):

```
$ scripts/check-zimage-dtb.sh work/extracted/files/linux/zImage_dtb
ok   zImage magic 0x016f2818 present at +0x24
  zImage declared start (+0x28) = 0
  zImage declared end   (+0x2C) = 7360840   <- U-Boot's fdt_addr offset
  U-Boot computes fdt_addr = 0x01000000 + 0x00705148 = 0x01705148
ok   DTB magic 0xd00dfeed sits exactly at the declared end (7360840)
  DTB totalsize = 20017
ok   DTB totalsize reaches exactly EOF (7360840 + 20017 = 7380857)
ok   size 7380857 < 16 MiB budget (headroom 9396359 bytes, top addr 0x01709f79)
check-zimage-dtb.sh: all assertions passed
```

Exit 0 = contract holds; exit 1 = violated; exit 2 = usage/IO error. Both failure modes are
regression-tested: truncating the DTB by one byte and inserting 4 bytes of padding between
`zImage` and `dtb` each make it exit 1 with a specific message.

---

## 8. Kernel-config checklist for P1.3

Every row below was checked against `work/stock-linux.config` (the IKCONFIG-extracted stock
config) in this task. "Test" is a command that must pass against our generated
`board/mister/de10nano/linux.config` (or the built `.config`).

Shorthand: `have() { grep -qx "CONFIG_$1" "$CFG"; }` / `notset() { grep -qx "# CONFIG_$1 is not set" "$CFG"; }`

### 8.1 Boot-protocol assertions (A3)

| # | Symbol | Required | Evidence | Test |
|---|---|---|---|---|
| B1 | `CONFIG_ARM_APPENDED_DTB` | **not set** | Stock: `# CONFIG_ARM_APPENDED_DTB is not set`. U-Boot passes the DTB pointer explicitly in `r2` (`u-boot:arch/arm/lib/bootm.c:365-366`) — the appended-DTB mechanism (decompressor scans for `0xd00dfeed` immediately after `_edata` and relocates it itself) is **never entered**, because the kernel takes the DTB from `r2` first. Enabling it would be *harmless but actively misleading*: it would make the boot look like it depends on the concatenation being physically adjacent at runtime, when in fact it depends on U-Boot's `+0x2C` arithmetic. It would also silently mask a broken `cat` (the decompressor would find the DTB anyway) — the exact bug class §7 exists to catch. Keep it **off**. | `grep -qx '# CONFIG_ARM_APPENDED_DTB is not set' "$CFG"` |
| B2 | `CONFIG_ARM_ATAG_DTB_COMPAT` | **not set / absent** | Absent from stock (it depends on `ARM_APPENDED_DTB`). Purely an appended-DTB feature. | `! grep -q '^CONFIG_ARM_ATAG_DTB_COMPAT=' "$CFG"` |
| B3 | `CONFIG_USE_OF` | `y` | Stock `CONFIG_USE_OF=y`, `CONFIG_OF=y`. Mandatory: without it `IMAGE_ENABLE_OF_LIBFDT` on the U-Boot side is irrelevant — the kernel would ignore `r2`. | `grep -qx 'CONFIG_USE_OF=y' "$CFG"` |
| B4 | `CONFIG_ATAGS` | `y` (stock parity) — **inert either way** | Stock is `CONFIG_ATAGS=y`. **This is a nuance the verification doc's "No ATAG involvement" could be misread on:** ATAGs are *not used at boot* (r2 holds the DTB, `gd->bd->bi_boot_params` is not passed), but the symbol *is* enabled in the stock kernel — it defaults `y` (`linux:arch/arm/Kconfig:1628-1630`) and nobody turned it off. Setting it to `n` is also correct and saves a little text; setting it to `y` is stock parity. **Assert nothing about the boot path from this symbol** — assert B5/B6 instead. Recommendation: keep `=y` (minimise divergence), document that it is dead code. | `grep -qE '^(CONFIG_ATAGS=y\|# CONFIG_ATAGS is not set)$' "$CFG"` (informational) |
| B5 | `CONFIG_CMDLINE` | **`""`** | Stock: `CONFIG_CMDLINE=""`. This is the load-bearing one. `early_init_dt_scan_chosen()` copies `/chosen/bootargs` into `boot_command_line`, then: `linux:drivers/of/fdt.c:1158-1169` — with `CONFIG_CMDLINE` empty and neither `EXTEND` nor `FORCE` defined, the `else` branch runs `if (!data[0]) strlcpy(data, CONFIG_CMDLINE, …)`, i.e. **a no-op**, and the DT bootargs survive intact. | `grep -qx 'CONFIG_CMDLINE=""' "$CFG"` |
| B6 | `CONFIG_CMDLINE_FORCE` | **not set** | Absent in stock. If set, `linux:drivers/of/fdt.c:1162-1163` does `strlcpy(data, CONFIG_CMDLINE, …)` — **unconditionally replacing the bootloader cmdline**, destroying `root=`, `loop=`, `mem=511M` and `ro`. The board would not boot. *(Naming note for the task text: on ARM the symbol is `CMDLINE_FORCE`; there is no `CONFIG_CMDLINE_OVERRIDE` — that name belongs to other subsystems. `CMDLINE_FROM_BOOTLOADER` is the default member of a `choice` whose prompt only appears when `CMDLINE != ""` and which `depends on ATAGS` (`linux:arch/arm/Kconfig:1740-1743`) — which is why it is simply **absent** from the stock config rather than `=y`. Do not "fix" that absence.)* | `! grep -q '^CONFIG_CMDLINE_FORCE=y' "$CFG"` |
| B7 | `CONFIG_CMDLINE_EXTEND` | **not set** | Absent in stock. If set, `linux:drivers/of/fdt.c:1159-1161` appends `CONFIG_CMDLINE` to the bootloader's — harmless while `CMDLINE=""`, but it makes B5 load-bearing in a way that is easy to break later. Keep off. | `! grep -q '^CONFIG_CMDLINE_EXTEND=y' "$CFG"` |

### 8.2 Initramfs assertions (A1) — **contains the biggest surprise in this task**

| # | Symbol | Required | Evidence | Test |
|---|---|---|---|---|
| I1 | `CONFIG_BLK_DEV_INITRD` | **`y`** — a *required divergence from stock* | **Stock has `# CONFIG_BLK_DEV_INITRD is not set`.** (Verified: `work/stock-linux.config:170`.) Stock needs no initramfs because it patches `init/do_mounts.c` to do the loop-mount in-kernel — which is exactly the patch §5 deletes. `CONFIG_INITRAMFS_SOURCE` **depends on `BLK_DEV_INITRD`**, so P1.3 must turn this on. A pure `olddefconfig` port of the stock config will leave it **off** and `CONFIG_INITRAMFS_SOURCE` will silently not exist. This is the single most likely way for P1.3 to hand P1.10 a kernel with no initramfs in it. | `grep -qx 'CONFIG_BLK_DEV_INITRD=y' "$CFG"` |
| I2 | `CONFIG_INITRAMFS_SOURCE` | non-empty, → the stage-1 cpio | A1. U-Boot passes `-` for the initrd argument in `bootz $loadaddr - $fdt_addr` → **no external initrd is ever loaded**, so the initramfs must be *inside* the zImage. | `grep -q '^CONFIG_INITRAMFS_SOURCE=".\+"' "$CFG"` |
| I3 | `CONFIG_RD_*` decompressors | at least the one matching our cpio compression (or none, if the cpio is uncompressed) | Absent in stock (they depend on `BLK_DEV_INITRD`). Simplest: ship an **uncompressed** cpio and let the kernel's built-in `INITRAMFS_COMPRESSION` handle it. | build-time |
| I4 | Blob still < 16 MiB after embedding | see §7.3 | `scripts/check-zimage-dtb.sh` | `scripts/check-zimage-dtb.sh $BINARIES_DIR/zImage_dtb` |

### 8.3 Root-device assertions (A2) — `loop.max_part` vs `LOOP_MIN_COUNT` are **different things**

| # | Symbol | Required | Evidence |
|---|---|---|---|
| L1 | `CONFIG_BLK_DEV_LOOP` | **`y`** (built-in, not `m`) | Stock `CONFIG_BLK_DEV_LOOP=y`. It must be built in: the initramfs mounts the image before any module could be loaded. |
| L2 | `CONFIG_BLK_DEV_LOOP_MIN_COUNT` | `8` (stock parity) | Stock `=8`. |

**These two are routinely conflated. They are unrelated:**

* **`loop.max_part=8`** (kernel *cmdline*, a module parameter) → `linux:drivers/block/loop.c:2551-2564`:
  ```c
  part_shift = 0;
  if (max_part > 0) {
          part_shift = fls(max_part);            /* fls(8) == 4 */
          max_part = (1UL << part_shift) - 1;    /* adjusted to 15 */
  }
  ```
  Its real effects: (a) it **enables partition scanning on loop devices**, so a loop-mounted
  disk *image with a partition table* exposes `/dev/loopNpM`; (b) it sets `part_shift = 4`,
  so each loop device now owns **16 minors** and loop device *N* has first-minor `N << 4`.
  It says nothing about *how many* loop devices exist.

* **`CONFIG_BLK_DEV_LOOP_MIN_COUNT=8`** (compile-time) → the loop driver **pre-creates 8 loop
  devices at init: `loop0`…`loop7`**. It says nothing about partitions.

**Where `/dev/loop8` actually comes from** — and this matters for P1.10:

> `linux:init/do_mounts.c:669` (the MiSTer patch, commit `3d95de58f` "Support for init loop device.")
> ```c
> err = create_dev("/dev/loop8", MKDEV(7, (loop_max_part()+1)*8));
> ```
> `loop_max_part()` (a MiSTer export, `linux:drivers/block/loop.c:136-141`) returns the
> *adjusted* `max_part` = **15**, so the minor is `(15+1)*8 = 128` — and `128 >> part_shift(4)
> = 8`, i.e. loop device index **8**. It is *one past* the `MIN_COUNT=8` pre-created range
> (`loop0`…`loop7`), so it never collides with one; it is instantiated **on demand** when the
> node is opened, by `linux:drivers/block/loop.c:2437-2444`:
> ```c
> static void loop_probe(dev_t dev) { int idx = MINOR(dev) >> part_shift; …; loop_add(idx); }
> ```

**Consequences for P1.10 (A2):**

1. **Do not hardcode `/dev/loop8` in `/init`.** The name is an artifact of the kernel patch we
   are deleting, and its correct *minor* (128) is only correct while `loop.max_part` is in
   `8..15`. If a user's `u-boot.txt` changed `$v` in a way that dropped `loop.max_part`,
   `part_shift` would be 0 and loop8's minor would be 8, not 128 — a hardcoded `mknod … 7 128`
   would then create a node for loop device *16*.
2. **Use `losetup -f` / `/dev/loop-control` (`LOOP_CTL_GET_FREE`) instead.** Busybox `losetup
   -f` does the right thing and will simply pick `loop0`, which is pre-created. Grepping the
   stock rootfs (`work/imgroot/etc`, `usr/bin`, `usr/sbin`) and Main_MiSTer for `loop8` finds
   **zero** userland references — **nothing depends on the root loop device being loop8.**
   Confirmed safe to change.
3. Keep `loop.max_part=8` on the cmdline anyway (it comes from U-Boot; we do not control it,
   and partition scanning on loop devices is harmless).

### 8.4 Filesystem assertions (A2) — **and a second surprise: stock's "exfat" is not mainline's**

| # | Symbol | Required | Evidence |
|---|---|---|---|
| F1 | `CONFIG_EXT4_FS` | `y` | Stock `=y`. `linux.img` is ext4. Built-in — the initramfs mounts it. |
| F2 | `CONFIG_VFAT_FS` | `y` | Stock `=y` (`CONFIG_FAT_FS=y`, `# CONFIG_MSDOS_FS is not set`). |
| F3 | `CONFIG_EXFAT_FS` | `y` | Stock `=y`. |
| F4 | `CONFIG_NLS` + codepages | **14** symbols — see below | **[P1.3 CORRECTION: this row previously said "Stock exactly these" and listed only four (437, ISO8859-1, UTF8, ASCII). That was wrong.]** Stock actually carries **14** `CONFIG_NLS_*` symbols: `NLS_DEFAULT="iso8859-1"`, codepages **437, 855, 866, 936, 950, 1251**, `ISO8859_1`, `ISO8859_5`, `ISO8859_15`, `KOI8_R`, `KOI8_U`, `MAC_CYRILLIC`, `ASCII`, `UTF8` — i.e. full **Cyrillic** and **CJK** (936 = GBK, 950 = Big5) coverage. **Carry all 14.** Also `FAT_DEFAULT_CODEPAGE=437`, `FAT_DEFAULT_IOCHARSET="iso8859-1"` (do **not** change IOCHARSET — see ADR 0010; the UTF-8 knob is `FAT_DEFAULT_UTF8`). Built-in, not modules: a missing codepage makes the vfat mount fail *inside the initramfs*, before any module could be loaded. <br><br>Worth noting for ADR 0010: stock shipping GBK/Big5/Cyrillic codepages is evidence the upstream project **did** anticipate non-ASCII filenames on `/media/fat`, even though the maintainer's own card has none. It strengthens, not weakens, the case for `FAT_DEFAULT_UTF8=y` on the vfat fallback. |

> ### New constraint discovered — not in A1–A9. Route to P0.9 / P0.4.
>
> **MiSTer's `fs/exfat` is the old out-of-tree Samsung/"sdfat" driver, not mainline's
> `fs/exfat`.** Evidence:
>
> * `linux:fs/exfat/exfat_core.c:30` — `/*  PROJECT : exFAT & FAT12/16/32 File System */`
> * `linux:fs/exfat/exfat_super.c:2129-2135` — registers **two** filesystem types, `"texfat"`
>   *and* `"exfat"`. Mainline registers only `exfat`.
> * The stock config carries sub-options that **do not exist in mainline**:
>   `CONFIG_EXFAT_DISCARD=y`, `CONFIG_EXFAT_DELAYED_SYNC=y`, `CONFIG_EXFAT_KERNEL_DEBUG`,
>   `CONFIG_EXFAT_DEBUG_MSG`, `CONFIG_EXFAT_DEFAULT_CODEPAGE=437`.
> * Fork history: `8b6b8c2f5` "Remove original exFAT driver." → `df35bdb27` "Add exFAT with
>   symlinks support." → `99a2c80d0` "exfat: use ATTR_SYSTEM as symlink flag to preserve links
>   while copying on Windows or other OS."
>
> Three consequences:
>
> 1. **`-t exfat` currently mounts FAT32 too.** That is why the stock kernel patch can do
>    `init_mount("/dev/root", "/root2", "exfat", …)` unconditionally
>    (`linux:init/do_mounts.c:666`) on a FAT32 card. **Mainline `exfat` will not do this.**
>    → A2's `mount -t vfat || mount -t exfat` fallback is not defensive; it is **mandatory**.
>    Already in the plan ✔ — this is the proof.
> 2. **Symlink support on exFAT is lost.** MiSTer's driver implements symlinks via
>    `ATTR_SYSTEM`; mainline's does not. Users with symlinks on an exFAT `MiSTer_Data`
>    partition will see them as regular files. This is a **user-visible behaviour change** and
>    needs an explicit decision (carry the patch? document the regression?). P0.4 must class
>    this; P3.13's matrix must test an exFAT `MiSTer_Data` with symlinks.
> 3. The `texfat` alias disappears. Grepping the stock rootfs finds no user of it, but
>    community scripts might.

### 8.5 Console / serial

| # | Symbol | Required | Evidence |
|---|---|---|---|
| C1 | `CONFIG_SERIAL_8250=y`, `CONFIG_SERIAL_8250_CONSOLE=y`, `CONFIG_SERIAL_8250_DW=y`, `CONFIG_SERIAL_OF_PLATFORM=y` | all `y` | Stock: all four `=y`. `console=ttyS0,115200` on the cmdline + the DTB's `stdout-path = "serial0:115200n8"` (`work/stock.dts:953`) route the console to the DesignWare UART. This is the **only** debug channel for P1.13; if it regresses, first boot is blind. |
| C2 | `CONFIG_EARLY_PRINTK` / `CONFIG_DEBUG_LL` | **not set** (stock) — *optional* for us | Stock: `CONFIG_EARLY_PRINTK` absent, `# CONFIG_DEBUG_LL is not set`. The DTB's static `bootargs = "earlyprintk"` is (a) overwritten by U-Boot's `/chosen` fixup (§4.2) and (b) inert anyway. **Recommendation for P1.13 only:** temporarily enabling `DEBUG_LL` + `EARLY_PRINTK` + `DEBUG_UART_8250` (base `0xffc02000`) gives pre-`console=` output and is worth having in a debug branch during first-boot bring-up. Ship it **off**, for stock parity. |

### 8.6 Carried over from A4 / stock parity (re-verified here so P1.3 has one list)

| # | Symbol | Required | Stock value in `work/stock-linux.config` |
|---|---|---|---|
| P1 | `CONFIG_DEVMEM` | `y` | `CONFIG_DEVMEM=y` ✔ (A4; also the only route to the `0x1FFFF000` mailbox — §6.4) |
| P2 | `CONFIG_STRICT_DEVMEM` | **not set** | `# CONFIG_STRICT_DEVMEM is not set` ✔ |
| P3 | `CONFIG_IO_STRICT_DEVMEM` | **not set / absent** | absent (it depends on `STRICT_DEVMEM`) ✔ |
| P4 | `CONFIG_KERNEL_LZ4` | `y` | `CONFIG_KERNEL_LZ4=y` ✔ — and U-Boot's `CONFIG_LZ4=y` (`configs/socfpga_de10_nano_defconfig:61`) is irrelevant here (`bootz` never decompresses; the zImage self-extracts). Any `KERNEL_*` compressor works. |
| P5 | `CONFIG_IKCONFIG`, `CONFIG_IKCONFIG_PROC` | `y`, `y` | both `=y` ✔ — keep: it is how this whole analysis was possible, and how future maintainers audit *our* image. |
| P6 | `CONFIG_MODULES` | `y` | `=y` ✔ (A5) |
| P7 | `CONFIG_MODULE_COMPRESS_XZ` | `y` | `=y` ✔ (A5) |
| P8 | `CONFIG_MODULE_SIG` | **not set** | `# CONFIG_MODULE_SIG is not set` ✔ (A5 — out-of-tree modules) |

### 8.7 One-shot verification script sketch for P1.3

```sh
# scripts/check-kernel-config.sh <.config>   (P1.3 deliverable)
CFG=$1; rc=0
req()    { grep -qx "$1" "$CFG" || { echo "FAIL: expected '$1'"; rc=1; }; }
forbid() { grep -q  "$1" "$CFG" && { echo "FAIL: must not have '$1'"; rc=1; }; }

req    '# CONFIG_ARM_APPENDED_DTB is not set'   # B1
req    'CONFIG_USE_OF=y'                        # B3
req    'CONFIG_CMDLINE=""'                      # B5
forbid '^CONFIG_CMDLINE_FORCE=y'                # B6
forbid '^CONFIG_CMDLINE_EXTEND=y'               # B7
req    'CONFIG_BLK_DEV_INITRD=y'                # I1  <-- diverges from stock ON PURPOSE
grep -q '^CONFIG_INITRAMFS_SOURCE=".\+"' "$CFG" || { echo "FAIL: INITRAMFS_SOURCE empty"; rc=1; }  # I2
req    'CONFIG_BLK_DEV_LOOP=y'                  # L1
req    'CONFIG_BLK_DEV_LOOP_MIN_COUNT=8'        # L2
req    'CONFIG_EXT4_FS=y'; req 'CONFIG_VFAT_FS=y'; req 'CONFIG_EXFAT_FS=y'   # F1-F3
# F4 -- all 14 stock NLS symbols, not the 4 this checker used to assert.
for _nls in NLS_CODEPAGE_437 NLS_CODEPAGE_855 NLS_CODEPAGE_866 NLS_CODEPAGE_936 \
            NLS_CODEPAGE_950 NLS_CODEPAGE_1251 NLS_ISO8859_1 NLS_ISO8859_5 \
            NLS_ISO8859_15 NLS_KOI8_R NLS_KOI8_U NLS_MAC_CYRILLIC NLS_ASCII NLS_UTF8; do
	req "CONFIG_${_nls}=y"
done
req    'CONFIG_FAT_DEFAULT_UTF8=y'   # ADR 0010: the vfat FAT32 fallback must decode UTF-8
req    'CONFIG_SERIAL_8250_CONSOLE=y'; req 'CONFIG_SERIAL_8250_DW=y'
req    'CONFIG_SERIAL_OF_PLATFORM=y'                                          # C1
req    'CONFIG_DEVMEM=y'                                                      # P1 (A4)
req    '# CONFIG_STRICT_DEVMEM is not set'                                    # P2 (A4)
forbid '^CONFIG_IO_STRICT_DEVMEM=y'                                           # P3 (A4)
req    'CONFIG_MODULES=y'; req 'CONFIG_MODULE_COMPRESS_XZ=y'
forbid '^CONFIG_MODULE_SIG=y'                                                 # P6-P8 (A5)
exit $rc
```

---

## 9. What the initramfs replacement (§5) must preserve — A2's justification, for P1.10

The boot chain hands `/init` a command line and nothing else. Everything `/init` must
reproduce is *in* that command line, and **every token of it is user-overridable**, because
`scrtest` applies `u-boot.txt` with `env import -t` — which imports **any** variable, not just
`$v`.

| Cmdline token | Default | Overridable how | What `/init` must do |
|---|---|---|---|
| `root=$mmcroot` | `/dev/mmcblk0p1` | `u-boot.txt`: `mmcroot=/dev/sda1` (USB-boot setups exist in the wild) | **Parse `root=` from `/proc/cmdline`.** Never hardcode `mmcblk0p1`. |
| `loop=linux/linux.img` | `linux/linux.img` | `u-boot.txt`: `bootimage=…` does *not* change this, but `mmcboot` itself can be overridden wholesale | **Parse `loop=` from `/proc/cmdline`** and treat it as a path *relative to the mounted data partition*. |
| `ro` | present | `u-boot.txt` overriding `mmcboot` | Mount the loop device **read-only** (`losetup -r`, `mount -o ro`). Stock `/etc/fstab` has root `rw,noauto` — the read-only-ness comes **only** from this cmdline token. |
| `rootwait` | present | ” | **Implement as a retry loop.** The kernel's own `rootwait` is not in play once we use an initramfs — the kernel switches to `/init` immediately, and `root=` is *our* string to interpret. Slow USB/SD enumeration is the failure this guards against. |
| `mem=511M` | present | ” (users must not) | Nothing — but never emit a kernel/DTB that ignores it (§6.4). |
| `loop.max_part=8` | present | ” | Nothing. Do **not** infer `/dev/loop8` from it (§8.3). |
| `console=ttyS0,115200` | present | `u-boot.txt` can change `$v` only; `console=` is in `CONFIG_BOOTARGS` | `/init`'s rescue shell must land on this console. |
| `$v` | `loglevel=4` | `u-boot.txt` line 1 — **this is the documented user knob** (`u-boot.txt_example`: `v=loglevel=4 usbhid.jspoll=1 xpad.cpoll=1`) | Ignore; it is kernel/module params. But note it means **arbitrary extra tokens can appear in `/proc/cmdline`** — parse defensively, never positionally. |
| `memmap=513M$511M` | present | ” | Nothing — it is inert on ARM (§6.4). But **do not remove it**: it is emitted by a U-Boot we are not changing. |

Also preserved by construction, and worth stating so P1.10 does not "improve" them:

* **The data partition is mounted, then `mount --move`d to `/newroot/media/fat`.** Stock
  achieves the same with a bind mount (`linux:init/do_mounts.c:677`). `/media/fat` must exist
  and be the data partition when `/sbin/init` starts, or `/etc/inittab`'s
  `::sysinit:/media/fat/MiSTer &` fails instantly.
* **The data partition may be FAT32 *or* exFAT** — and on 6.18 those are two different
  filesystem drivers (§8.4). Try `vfat`, then `exfat`.
* **No initrd is loaded, ever** (`-` in `bootz`). The cpio must be embedded (A1/I1/I2).

---

## 10. Summary of corrections and new findings

**Corrections (fold into P0.9 → PLAN.md / the verification doc):**

1. **`memmap=513M$511M` is inert on ARM.** No `memmap=` parser exists under `arch/arm/`. Only
   `mem=511M` reserves anything. PLAN §3 and A3's wording attribute the reservation to both;
   the conclusion (don't touch the cmdline) is unchanged, the reason is not. (§6.4)
2. **The verification doc's env listing is a subset.** It omits `bootargs`, `bootdelay`,
   `baudrate`, `bootfile`, `fdt_addr=100`, **`v=loglevel=4`**, **`ethaddr=02:03:04:05:06:07`**,
   the duplicate `loadaddr`, and the malformed `"bootm $loadaddr - $fdt_addr"` entry. `$v`'s
   default and `ethaddr` both matter (§3.1). Not wrong — incomplete.
3. **"No ATAG involvement" needs a footnote:** the *boot path* uses no ATAGs (r2 = DTB), but
   stock ships `CONFIG_ATAGS=y`. Do not turn P1.3 into a hunt for a symbol that is
   legitimately `y`. (§8.1/B4)
4. `updateboot` writes to the **`0xA2` partition** (`p2`, or `p3` on the old layout) — not to
   a raw device offset. Both the plan and the verification doc say "raw boot partition", which
   is right, but §2.1 is the reason it works and it should be recorded. (§2.1, §5)

**New constraints, not covered by A1–A9 (candidates for A10/A11 in P0.9):**

* **N1 — `CONFIG_BLK_DEV_INITRD` is OFF in stock.** An `olddefconfig` port of the stock config
  will not offer `CONFIG_INITRAMFS_SOURCE` at all. P1.3 must flip it on explicitly. This is the
  highest-probability silent failure in Phase 1. (§8.2/I1)
* **N2 — stock's exFAT is the old out-of-tree driver that also mounts FAT12/16/32 and supports
  symlinks via `ATTR_SYSTEM`.** Mainline's does neither. Mandates A2's vfat-then-exfat
  fallback, and creates a real, user-visible regression risk (exFAT symlinks) that needs an
  explicit decision in P0.4/P3.13. (§8.4)
* **N3 — `/dev/loop8` is a kernel-patch artifact with a `part_shift`-dependent minor.** Nothing
  in userland depends on it. P1.10 must use `losetup -f`, not a hardcoded node. (§8.3)
* **N4 — `mt` is a MiSTer-only U-Boot command.** Any mainline U-Boot port must
  re-implement it or rewrite `fpgacheck`. (§3.3) *(Moot since ADR 0017: Phase 5 builds
  the fork, `mt` included.)*
* **N5 — `uboot.img` cannot be rebuilt byte-identically** (compiled-in `+0800` timestamp, no
  `SOURCE_DATE_EPOCH`, pinned 2020 Arm toolchain). It must be *fetched by hash*, never built.
  (§3.2) *(Under ADR 0017 this holds for the default channel; the Phase-5 from-source
  build is a separate opt-in artifact validated by behavioural parity, not byte identity.)*

**Not verified (open):**

* That DDR contents at `0x1FFFF000` genuinely survive the `swcoldrstreq` reset on real
  hardware. Asserted from source and from the fact that the shipped firmware depends on it;
  cannot be confirmed without a board. Nothing we do changes it either way.
* The SPL's own CRC32 (`u-boot:tools/socfpgaimage.c:119`) uses `pbl_crc32`, not the standard
  reflected CRC-32; I confirmed a non-zero CRC word sits at the header-declared offset
  (`0xB2F8`) followed by zero padding to 64 KiB, but did not recompute it. It does not matter:
  we ship the blob unmodified.
* Which of the two defconfigs (`configs/socfpga_de10_nano_defconfig` or the fork's own
  `configs/MiSTer_defconfig`, a full 835-line expanded `.config` renamed from
  `socfpga_de10-nano_minimal_defconfig` in 2018) produced the shipped binary. **It does not
  matter for the environment** — both set `CONFIG_SYS_CONFIG_NAME="socfpga_de10_nano"` and thus
  share `include/configs/socfpga_de10_nano.h`, and the extracted env matches it exactly. It
  *would* matter for a Phase-5 rebuild; P5.1 should start from `MiSTer_defconfig`.
