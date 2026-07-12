# Verification of stock release `release_20250402.7z`

Date: 2026-07-11. Verified against the shipped artifact downloaded from
`MiSTer-devel/SD-Installer-Win64_MiSTer` (master), plus `Downloader_MiSTer` source (main).
This pre-executes parts of P0.2/P0.3/P0.6/P0.8 and settles every boot-chain uncertainty in
`PLAN.md`. Derived text artifacts are committed under `docs/stock-inventory/`; the binary
materials live in untracked `work/`.

## Artifact identity

| Item | Value | Matches plan? |
|---|---|---|
| MD5 | `8dc3acae7d758a80a363fbd7ad31d95d` | ✓ §10 db.json entry, byte-exact |
| Size | `93727644` | ✓ |
| `linux.img` | 393,216,000 bytes = 375 MiB exactly | ✓ |
| `linux.img` free space | 53,325,824 bytes ≈ 13.6 % free | ✓ ("93 % full") |

Archive layout: `files/linux/{linux.img, zImage_dtb, uboot.img, updateboot, MidiLink.INI,
ppp_options, u-boot.txt_example, _samba.sh, _user-startup.sh, _wpa_supplicant.conf,
gamecontrollerdb/, mt32-rom-data/, soundfonts/}` plus `files/{MiSTer, menu.rbf,
MiSTer_example.ini, Scripts/update.sh}` and a Windows `.exe`. The Downloader extracts
**only `files/linux/*`**; the rest serves the Windows SD installer.

## Boot chain (extracted from `uboot.img` — settles A3)

`uboot.img` = **four identical 64 KiB SPL copies** (offsets 0/64/128/192 KiB) + an
uncompressed uImage `U-Boot 2017.03+ for de10-nano` at offset 256 KiB (0x40000),
load address 0x1000040. Embedded environment, recovered verbatim:

```
loadaddr=0x01000000
fpgadata=0x02000000
core=menu.rbf
mmc_boot=1
mmcroot=/dev/mmcblk0p1
bootimage=/linux/zImage_dtb
bootcmd=mw 0xff709004 0x800; run mmcload; run mmcboot
mmcload=mmc rescan;run fpgacheck;run scrtest;load mmc 0:$mmc_boot $loadaddr $bootimage;
        setexpr.l fdt_addr $loadaddr + 0x2C;setexpr.l fdt_addr *$fdt_addr + $loadaddr
mmcboot=setenv bootargs console=ttyS0,115200 $v loop.max_part=8 mem=511M memmap=513M$511M
        root=$mmcroot loop=linux/linux.img ro rootwait;bootz $loadaddr - $fdt_addr
scrtest=if test -e mmc 0:$mmc_boot /linux/u-boot.txt;then load mmc 0:$mmc_boot $loadaddr
        /linux/u-boot.txt;env import -t $loadaddr;fi
fpgaload=load mmc 0:$mmc_boot $fpgadata $core;fpga load 0 $fpgadata $filesize;
         bridge enable;mw 0x1FFFF000 0;mw 0xFFD05054 0
fpgacheck=if mt 0x1FFFFF08 0xBEEFB001;then mw 0x1FFFFF08 0;if mt 0x1FFFF000 0x87654321;
          then mw 0x1FFFF000 0;env import -t 0x1FFFF004;run fpgaload;fi;else run fpgaload;fi
```

Conclusions (each previously an assumption, now fact):

1. **`zImage_dtb` is a plain concatenation.** U-Boot loads the whole file, then computes
   `fdt_addr = loadaddr + *(loadaddr + 0x2C)` — the zImage header's declared-size field —
   so the DTB must sit **exactly at the zImage's declared end**, which `cat zImage dtb`
   guarantees. Verified in the artifact: zImage declared size 7,360,840; DTB magic at
   exactly 7,360,840; DTB totalsize 20,017 reaches exactly end-of-file.
2. **`CONFIG_ARM_APPENDED_DTB is not set`** in the stock kernel. U-Boot passes the DTB
   pointer explicitly (`bootz $loadaddr - $fdt_addr`) and injects `bootargs` into
   `/chosen` via standard FDT fixup (the DTB's static `bootargs` is just `earlyprintk`).
   No ATAG involvement.
3. **No initrd is ever loaded** (`-` in `bootz`) — an initramfs must be embedded in the
   zImage (`CONFIG_INITRAMFS_SOURCE`), as planned.
4. **Bootargs confirmed verbatim** as PLAN §3, with `mmcroot=/dev/mmcblk0p1` default and
   `mmc_boot=1` (FAT partition = partition 1).
5. **`u-boot.txt` is applied with `env import -t`** — it can override *any* variable
   (`v`, `mmcroot`, `core`, even `bootcmd`), not just `$v`. The `/init` cmdline-parsing
   design (A2) is therefore mandatory, not defensive.
6. **U-Boot pre-loads the FPGA** (`core=menu.rbf`) before Linux and enables the bridges.
7. **Warm-reboot handshake**: `fpgacheck` reads magic values and can `env import -t
   0x1FFFF004` **from RAM** — Main_MiSTer stages a core name/env in the reserved memory
   window and reboots. This lives just below 512 MiB, inside the `mem=511M`/`memmap`
   reserved region — one more reason those arguments are untouchable.

## Kernel (extracted from `zImage_dtb` — settles A4 and more)

Banner: `Linux version 5.15.1-MiSTer (saar@Gryphon) (arm-none-linux-gnueabihf-gcc …)`.
zImage payload is **LZ4** (`CONFIG_KERNEL_LZ4=y`); `CONFIG_IKCONFIG=y` +
`CONFIG_IKCONFIG_PROC=y`, so the exact build config is embedded — extracted to
`docs/stock-inventory/stock-linux.config` (4,246 lines). Key facts:

| Symbol | Stock value | Implication |
|---|---|---|
| `CONFIG_DEVMEM=y`, `# CONFIG_STRICT_DEVMEM is not set` | verified | A4 confirmed: keep STRICT_DEVMEM off on 6.18 |
| `CONFIG_ARM_APPENDED_DTB` | **not set** | A3 corrected (see above) |
| `CONFIG_VFAT_FS=y`, `CONFIG_EXFAT_FS=y` | built-in | initramfs can mount either without modules |
| `CONFIG_CIFS=y` (+`ALLOW_INSECURE_LEGACY`), `CONFIG_NFS_FS=y` | built-in | parity |
| NTFS (any driver) | **absent** | stock has no NTFS; adding ntfs3 would be an opt-in improvement |
| `CONFIG_BLK_DEV_LOOP=y`, `LOOP_MIN_COUNT=8` | built-in | `/dev/loop8` exists at boot |
| `CONFIG_MODULES=y`, `CONFIG_MODULE_COMPRESS_XZ=y` | 48 `=m` symbols | see modules below |

## Modules & firmware (corrects the plan's "zero `.ko`" claim)

The image ships **52 `.ko.xz` modules** under `/usr/lib/modules/5.15.1-MiSTer/` with full
`modules.dep`/`modules.alias` metadata: all WiFi (mac80211 stack, mt76*, rt2x00*, rtlwifi,
rtl8xxxu, plus out-of-tree `8188eu`, `rtl8188fu`, `8812au`, `8821au`, `8821cu`, `88x2bu`),
Bluetooth USB (`btusb`, `btintel`, `btbcm`, `btrtl`, `ath3k`), and `xone` (7 modules).
Everything else is built in. `/usr/lib/firmware` holds **72 files** (mediatek, ralink,
realtek WiFi + `rtl_bt`, one brcm BT patch, `regulatory.db`). Toolchain shipped:
`kmod`, `depmod`, `modprobe`, **`udevd`** (eudev — S10udev; hotplug is udev, not mdev).

Consequence: shipping classes D/E as Buildroot `kernel-module` packages **reproduces the
existing runtime layout** — module infra is a parity requirement, not new machinery.

## Rootfs facts

* glibc **2.31** (`libc-2.31.so`) ✓, Python **3.9** ✓, ext4 label `rootfs` ✓.
* ext4 features (pinning reference for reproducible images): `HAS_JOURNAL`,
  `METADATA_CSUM`, `64BIT`, `FLEX_BG`, `EXTENTS`, fixed UUID
  `50ef310c-47b9-4c1c-a2fe-d0202d02b6b4`.
* Init scripts (complete set): `S01syslogd S02klogd S10udev S30dbus S40network S41dhcpcd
  S45bluetooth S49ntp S50proftpd S50sshd S91smb S99user` — FTP is **proftpd**; sshd is
  OpenSSH; dbus present.
* `/etc/inittab` launches **`/media/fat/MiSTer &` from `::sysinit`** (plus `/etc/resync`);
  the MiSTer binary is not started by an S-script.
* fstab: root `rw,noauto` (the `ro` comes from the kernel cmdline); tmpfs on `/tmp`,
  `/run`, `/dev/shm`, `/var/lib/samba`, `/var/db/dhcpcd`.
* **`/MiSTer.version` sits at the rootfs root** (contents `250402`) — baked into the image
  at build time. Since `linux.img` *is* the root filesystem, the Downloader reads the
  running system's own `/MiSTer.version`. It is **not** under `/media/fat/linux/`.

## Downloader `LinuxUpdater` contract (verified from source — settles A8)

From `src/downloader/linux_updater.py` + `constants.py` @ main (2026-07):

1. Multiple dbs offering `linux`: **first wins**, others warned+ignored (exactly as §10).
2. Version check: running system's `/MiSTer.version` vs `linux['version'][-6:]` —
   **last 6 characters, inequality** (not ordering).
3. Extraction tool: a **pinned ARM `7za`** downloaded on demand to `/media/fat/linux/7za`
   from the SD-Installer repo (`7za.gz`, MD5 `ed1ad5185fbede55cd7fd506b3c6c699`). Nothing
   in the installed image performs the extraction.
4. Flow: `7za t` (integrity) → extract **only `files/linux/*`** to
   `/media/fat/linux.update/` → *user-file restore*: mount the **new** `linux.img` ext4
   read-write and copy `/media/fat/linux/{hostname,hosts,interfaces,resolv.conf,
   dhcpcd.conf,fstab}` over `/etc/{hostname,hosts,network/interfaces,resolv.conf,
   dhcpcd.conf,fstab}` inside it → move `linux.img` aside as `linux.img.new` → `rsync -a`
   the rest of `files/linux/` over `/media/fat/linux/` (excluding `gamecontrollerdb/`) →
   **run `/media/fat/linux/updateboot`** → swap `linux.img.new` into place → raise
   `/tmp/downloader_needs_reboot_after_linux_update`.
5. `updateboot` (shipped in the archive, rsynced into place): **erases U-Boot's saved
   environment** (`dd if=/dev/zero of=/dev/mmcblk0 seek=1 count=1`) and **`dd`-writes
   `uboot.img`** to the raw boot partition (`mmcblk0p2`, or `p3` on the old layout) — on
   **every** linux update.

Consequences for us:

* Our `files/linux/` must carry the same auxiliary payload (`updateboot`, templates, …),
  because `rsync` replaces `/media/fat/linux/` content with whatever we ship.
* Shipping the stock `uboot.img` byte-identical is **load-bearing**: whatever we ship gets
  flashed. And no saved-env state survives an update — the effective U-Boot environment is
  always built-in defaults + `u-boot.txt`.
* The six user-file destinations must remain **regular files** at those exact paths in our
  image (no symlink-into-tmpfs schemes), or the offline restore breaks.
* Our archive must be extractable by that pinned `7za` build (the current release uses
  LZMA2 + BCJ2 — same encoder family is safe).

## Reproduction

All binary materials in `work/` (gitignored). To re-derive:
`work/release_20250402.7z` → `7z x`; kernel config via LZ4-decompressing the zImage
payload and reading the `IKCFG_ST` gzip block; DTB carved at the zImage's declared end;
U-Boot env via `strings` on the uImage payload at offset 0x40040; rootfs inspected with
`7z l/x` on the ext4 image (no mount needed). Scripted regeneration is task P0.3.
