# MiSTer Linux Modernization Plan

**A reproducible, drop-in `linux.img` built from a modern Buildroot, with all kernel
patches carried in-tree as Buildroot patch files.**

Status: v3 (2026-07-12) — **amended by the Phase 0 recon findings** (`docs/phase0-review.md`).
v2's claims were verified against the shipped stock release; Phase 0 then verified them
against the *source*, and a number did not survive. Every correction is marked
**[P0]** inline and carries its evidence. Task-level execution plan in `TASKS.md`.
Target board: Terasic DE10-Nano (Cyclone V SoC, `armv7-a` Cortex-A9)

> **Phase 0 headline:** the central bet holds. All 12 SONAMEs the stock `MiSTer` binary
> needs survive at the same major version in Buildroot 2026.02 (`docs/package-manifest.md`),
> so §1's "nothing needs rebuilding" premise is now *confirmed* rather than assumed.
> **Five questions still need a human decision before Phase 1 starts — see
> `docs/phase0-review.md`.**

---

## 1\. Summary

MiSTer's operating system is currently distributed as an opaque 94 MB archive
(`release_YYYYMMDD.7z`) containing a 375 MiB ext4 image built from **Buildroot 2021.02.4**
with **glibc 2.31**, running **Linux 5.15.1** — a kernel forked in November 2021 that has
**never merged a single 5.15.y stable release**. The Buildroot configuration that produces
it is not published anywhere.

This plan replaces that image with one built from **Buildroot 2026.02 LTS** and a
**mainline 6.18 LTS kernel**, in a public repository, with CI, with release artifacts
published as GitHub Release assets rather than committed blobs.

> \*\*Hard deadline: Linux 5.15 reaches end-of-life in December 2026.\*\* MiSTer's kernel base
> stops receiving \*any\* upstream security fixes in roughly five months. This is not a
> hygiene argument; it is a date on a calendar.

**The critical enabling insight:** the stock `MiSTer` binary is a normal dynamically-linked
`armhf` glibc ELF. glibc is backward-compatible. A rootfs with a *newer* glibc runs binaries
built against an *older* one. Therefore **no MiSTer binary, no core helper, and nothing in
`Distribution_MiSTer` needs to be rebuilt.** We change the OS underneath and everything above
it keeps working.

**The critical enabling mechanism:** `Downloader_MiSTer` already applies OS updates from a
`linux` entry in *any* configured database. We ship our image through the project's own
hash-verified update channel. **No permission, no fork of the cores, no fork of `Main_MiSTer`.**

---

## 2\. Goals

|#|Goal|
|-|-|
|G1|A `linux.img` + `zImage_dtb` that boots the **unmodified, stock** `MiSTer` binary|
|G2|Modern kernel on a supported LTS with a real security-update path|
|G3|Modern package set (Buildroot 2026.02 LTS) with a real security-update path|
|G4|**No separate kernel repo.** All kernel patches live as `.patch` files in the Buildroot external tree and are applied to a pristine kernel.org tarball|
|G5|Fully reproducible: pinned Buildroot, pinned kernel + hash, checked-in `.config`, published SBOM|
|G6|Release artifacts published as **GitHub Release assets**. No binaries in git. Ever.|
|G7|Opt-in distribution via a community `db.json` — zero cooperation required|

### Non-goals

* Not forking cores, `Main_MiSTer`, `Menu_MiSTer`, or `Distribution_MiSTer`.
* Not switching to musl/Alpine. **This would break every prebuilt binary in the ecosystem.**
* Not switching to a mutable package manager (apt/apk). The image-based update model is
*correct* and should be preserved; the problem is the unpublished config, not the paradigm.
* Not replacing U-Boot in v1. See §8.

---

## 3\. The ABI contract (what we must not break)

Captured by inspecting `release_20250402.7z`. Anything below is load-bearing.

### Toolchain / ABI

* `arm`, `cortex-a9`, NEON, VFPv3, **EABIhf**
* **glibc** — **[P0: the floor is 2.28, not 2.31.]** The binary's highest versioned
requirement is `fcntl64@GLIBC_2.28` (`scripts/abi/needed-symbols.py`). Newer is fine and is
the point. **The real hazard the plan originally missed:** glibc **2.34 merged libpthread
and librt into libc**, yet the stock binary still `DT_NEEDED`s `libpthread.so.0` and
`librt.so.1`. Buildroot still installs the compat stubs (`glibc.mk:188`), so this resolves
— but the five symbols that must come through the merge (`pthread_create`, `pthread_join`,
`pthread_attr_setaffinity_np`, `shm_open`, `shm_unlink`) are named in
`docs/abi-contract.md`, and **P2.2 asserts them against a real built rootfs** rather than
trusting the reasoning.
* Stock `MiSTer` binary `NEEDED`: `libc.so.6`, `libstdc++.so.6`, `libm.so.6`, `librt.so.1`,
`libpthread.so.0`, `libgcc_s.so.1`, `libfreetype.so.6`, `libbz2.so.1.0`, `libpng16.so.16`,
`libz.so.1`, `libImlib2.so.1`, `libbluetooth.so.3`

  → **Every one of these SONAMEs must be present with the same major version.** Modern
Buildroot provides all of them.

### Boot / memory

```
bootargs = console=ttyS0,115200 $v loop.max_part=8 mem=511M memmap=513M$511M \\
           root=$mmcroot loop=linux/linux.img ro rootwait
```

* `mem=511M` is **load-bearing**: the top of DDR is reserved for the FPGA fabric (core
framebuffers, scaler, emulated RAM) and for the warm-reboot mailbox at `0x1FFFF000`
(= 511.996 MiB, i.e. *above* the 511 MiB the kernel is told about). Do not change.
**[P0: `memmap=513M$511M` is inert on ARM.** `early_param("memmap")` is defined only in
`arch/x86`, `arch/mips` and `arch/xtensa` — **there is no parser under `arch/arm/`**.
`mem=511M` alone does 100% of the reservation. Both args still must not be touched (they
are U-Boot's, and we do not modify U-Boot in v1), but the reservation is attributable to
`mem=`, not to `memmap=`.**]**
* Root filesystem is mounted **read-only**. This is a good design — an immutable root with
writable state on `/media/fat` and tmpfs. **Preserve it.**
* `linux.img` is a file on the FAT partition, loop-mounted as root.
* The kernel is booted as a **concatenated `zImage_dtb`** (zImage + appended DTB). *Verified
from the extracted U-Boot environment* (see `docs/verification/stock-release-20250402.md`):
U-Boot loads the whole file, computes the DTB address from the zImage header's declared-size
field (`setexpr.l fdt_addr $loadaddr + 0x2C; setexpr.l fdt_addr *$fdt_addr + $loadaddr`),
injects `bootargs` into the DTB's `/chosen` node via standard FDT fixup, and runs
`bootz $loadaddr - $fdt_addr` — **no initrd, ever**. Consequences: plain `cat zImage dtb`
is the correct assembly (the DTB must sit exactly at the declared zImage end, which `cat`
guarantees); `CONFIG_ARM_APPENDED_DTB` is **not needed** (stock does not set it); and
anything added at boot time — the initramfs of §5 — must be embedded in the zImage.
* The data partition may be **FAT32 or exFAT**, and existing `u-boot.txt` setups may point
`root=` at other devices (USB boot) — `u-boot.txt` is applied with `env import -t`, so it can
override **any** U-Boot variable (default `mmcroot=/dev/mmcblk0p1`), not just `$v`. Both
filesystems, plus NLS codepages, must be built-in (stock: `CONFIG_VFAT_FS=y`,
`CONFIG_EXFAT_FS=y`).
* U-Boot also pre-loads the FPGA (`core=menu.rbf`) before Linux, and supports a warm-reboot
handshake with Main_MiSTer through reserved RAM at `0x1FFFF000` (`env import -t` from RAM) —
one more reason `mem=511M`/`memmap=513M$511M` are untouchable.

### Kernel ABI surface

Full detail with evidence in `docs/abi-contract.md` (P0.5).

* **`MiSTer_fb`** — **[P0: there is no custom ioctl.]** The driver exposes exactly one
ioctl, `FBIO_WAITFORVSYNC`, which is **standard mainline UAPI, byte-identical in 5.15 and
6.18**. This plan previously treated the "MiSTer_fb ioctl ABI" as a bit-level contract to
preserve; there is no custom number to preserve, and **P1.4 carries no ioctl-drift risk.**
The actual custom surface is the sysfs parameter `/sys/module/MiSTer_fb/parameters/mode`.
`/dev/fb0` is **never mmap'd**.
* **Audio** — **[P0: the ABI is not a card name.]** Main_MiSTer contains **zero ALSA
code**. Audio reaches hardware via `/etc/asound.conf`, which routes the default PCM through
`type file → /dev/MrAudio` (created by `MiSTer-audio-spi.c`) with `slave.pcm { type hw
card 0 }` — card 0 being a **patched `snd-dummy`**. The `sound/drivers/dummy.c` hunks are
therefore load-bearing: omit them and the system is silent.
* `fpga_io.cpp` pokes the HPS↔FPGA bridges via `/dev/mem` at hardcoded Cyclone V addresses.
The single `mmap` in the entire program is `/dev/mem` (`shmem.cpp:22`).

  → requires `CONFIG_DEVMEM=y` with `CONFIG_STRICT_DEVMEM=n` and `CONFIG_IO_STRICT_DEVMEM=n`.
*(Verified: stock has `CONFIG_DEVMEM=y` and `# CONFIG_STRICT_DEVMEM is not set`.)*
**[P0: the rationale here was wrong — `STRICT_DEVMEM` is *not* default-y on 32-bit ARM
(`default y if PPC || X86 || ARM64 || S390`), and `multi_v7_defconfig` has no DEVMEM line at
all. The assertion still must be checked; it just isn't a fight against a default.]**
* **[P0, new MUST] Main_MiSTer refuses to scan past `/dev/i2c-2`** (`smbus.cpp:214`). The
ADV7513 HDMI transmitter lives on one of `i2c-0..2`. **A fourth I²C adapter, or a bus
reordering in the DTS we author in P1.7, puts it out of reach and HDMI silently dies.**
* Cyclone V cpufreq/overclock driver

### Filesystem / runtime conventions

* `/media/fat` mount point
* **`/MiSTer.version` at the rootfs root** — 6-char `YYMMDD` (e.g. `250402`), **baked into
`linux.img` at build time**. Because `linux.img` *is* the running root filesystem, the
Downloader reads the live system's own `/MiSTer.version` and updates when it differs from the
last 6 characters of the db entry's `version`. *(Note: it is **not**
`/media/fat/linux/MiSTer.version` — a common misconception.)*
* **User-file restore contract:** on every linux update the Downloader mounts the *new*
`linux.img` read-write and copies `/media/fat/linux/{hostname,hosts,interfaces,resolv.conf,dhcpcd.conf,fstab}`
over the corresponding files under `/etc` inside the image. Networking is ifupdown-style
`/etc/network/interfaces` + `dhcpcd`.

  **[P0: "all six must remain regular files — no symlink-into-tmpfs schemes" was wrong.
  Stock is itself a symlink-into-tmpfs scheme for one of them.]** Five are regular files.
  **`/etc/resolv.conf` is a symlink to `../tmp/resolv.conf`** (verified on the raw ext4
  image: inode 112, `Type: symlink`). Because the Downloader's `copy()` **follows** the
  symlink, a user's custom `resolv.conf` is written to `/tmp/resolv.conf` *inside the
  offline image* — which the tmpfs mount over `/tmp` then shadows at boot. **That restore
  step has therefore never worked, on any MiSTer, ever.**
  ⇒ Open question **Q2** (`docs/phase0-review.md`): reproduce the bug for bug-for-bug
  parity, or make it a regular file and thereby *fix* a feature that has silently never
  worked? Fixing it is a real behavior change. **Needs a human decision.**
* BusyBox init with `S01syslogd … S99user` script names (verified set: syslogd, klogd,
**udev**, dbus, network, dhcpcd, bluetooth, ntp, **proftpd**, sshd, smb, user). The stock
`MiSTer` binary is launched from **`/etc/inittab` `::sysinit`** (backgrounded), not from an
init script. Hotplug is **eudev**, not mdev.
* ext4, volume label `rootfs`
* **On-device Python is an ABI surface**: `Downloader_MiSTer` and many community scripts run
with the target's interpreter. Stock ships 3.9 (EOL); Buildroot 2026.02 ships 3.13+.
Compatibility must be tested, not assumed.
* Stock ships **52 xz-compressed kernel modules** (`CONFIG_MODULE_COMPRESS_XZ=y`) under
`/usr/lib/modules/5.15.1-MiSTer/` — every WiFi driver, Bluetooth USB, and `xone` — plus
**66 firmware files** *(P0: the "72" figure counted 6 directories as files)* and the full module toolchain (`kmod`, `depmod`, `modprobe`, `udevd`).
Module infrastructure is an existing convention to keep at parity; shipping classes D/E as
Buildroot module packages reproduces the stock runtime layout exactly.

---

## 4\. What has to change, and how hard each piece is

### 4.1 The kernel: smaller than it looks

**[P0: the fork carries 109 commits, not ~60.]** And the baseline is now *proven*: the
fork has no upstream git ancestry at all (zero tags; its history is squashed whole-tree
imports), but content-diffing its version-bump commit `aba1ef4c1` against a hash-verified
kernel.org `linux-5.15.1` shows **0 files differing and 0 added** — so the 109 commits
after it are provably the complete MiSTer delta. Excluding the two vendored WiFi trees,
**the entire kernel problem is 143 files.** Full triage with per-commit provenance:
`docs/patch-provenance.md` (P0.4). Triaged:

|Class|Content|Disposition|
|-|-|-|
|**A. MiSTer core**|`MiSTer_fb.c`, `MiSTer-audio-spi.c`, Cyclone V cpufreq/overclock, `MiSTer_defconfig`|**Carry as patches.** The real work.|
|**B. `loop=` root patch**|`init/do_mounts.c` — adds a `loop=` cmdline param that mounts the FAT partition at `/root2`, loop-mounts `linux/linux.img` on `/dev/loop8`, and uses it as root|**DELETE — replace with an initramfs.** See §5.|
|**C. HID, now upstream**|NSO controllers, `hid-nintendo`, many `xpad` IDs|**Drop.** Mainline 6.18 has these.|
|**D. HID, still out-of-tree**|`xone`, GunCon 2/3, Fanatec, Flydigi Vader, remaining `xpad` IDs|**Carry** as patches, or as Buildroot kernel-module packages where an upstream exists.|
|**E. Realtek USB WiFi**|`rtl8188eu`, `rtl8188fu`, `rtl8812au`, `rtl8821au`, `rtl8821cu`, `rtl88x2bu`|**Re-source from morrownr upstream as Buildroot `kernel-module` packages.** Do not vendor.|
|**F. Misc quirks**|mmc LED, btusb VID/PIDs, usb-storage CD-ROM blacklist|Check upstream first; carry the remainder.|
|**G. exfat replacement** **[P0 — new class, not in the original taxonomy]**|The fork **replaces mainline exfat with the out-of-tree Samsung driver**|**DECISION REQUIRED — see below.**|

**[P0] Class G is the largest unbudgeted finding in Phase 0.** Stock's `fs/exfat` is not
mainline's. The Samsung out-of-tree driver:

* supports **symlinks**, stored in the FAT `ATTR_SYSTEM` bit — so they work on **FAT32 as
well as exFAT**;
* mounts FAT12/16/32 *and* exFAT under a single `-t exfat` (which is why the `loop=` patch
gets away with one mount call);
* decodes FAT32 filenames as **UTF-8** (mainline `vfat` defaults to iso8859-1 ⇒ mojibake).

**Mainline exfat and vfat have no symlink support whatsoever — and Main_MiSTer actively
resolves symlinks on `/media/fat`** (`file_io.cpp:1592`, `de->d_type == DT_LNK`, since Jan
2019). Dropping this driver silently breaks a live, user-facing feature that nothing in
this plan budgeted for.

⇒ Open question **Q1** (`docs/phase0-review.md`): **does the community actually rely on
symlinks on `/media/fat`?** That answer decides whether we carry a large out-of-tree
filesystem driver forward to 6.18 (a substantial, permanent maintenance burden that would
materially change this project's cost) or drop it and ship a known regression.
**This is the single most important human decision in Phase 0.**

**Class B is the one that will bite.** `init/do_mounts.c` was substantially refactored in the
6.x series (`mount_block_root` and friends are gone). Forward-porting that patch is both hard
*and unnecessary* — see §5.

**Classes D and E are already modules in the stock image** — the 5.15 fork builds them `=m`
(52 `.ko.xz` under `/usr/lib/modules`, `CONFIG_MODULE_COMPRESS_XZ=y`) with
`kmod`/`depmod`/`udevd` and **66** firmware files shipped *(P0: not 72)* — including
`xow_dongle.bin`, so **stock already bundles xone's firmware rather than fetching it**,
which settles P3.2's redistribution question. Re-sourcing them as Buildroot
`kernel-module` packages reproduces the existing runtime layout; what must be kept at parity
is the module toolchain, udev-driven autoload, and the firmware inventory (xone's firmware
additionally has redistribution constraints).

### 4.1a The device tree: mainline's DE10-Nano DTS is *not* sufficient

Mainline gained `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts` in January 2025
(\~v6.14). It is deliberately minimal — the submitter's commit message says it is *"enough to
make the board boot to Linux with the rootfs on a micro SD card."* That is all it does.

|Node|Mainline DTS|MiSTer needs|
|-|-|-|
|`mmc0`, `uart0`, `gpio0-2`, `i2c0` (adxl345), `gmac1`|enabled|✓ (but different gmac1 skews: `rgmii` + explicit `txc-skew-ps`/`rxc-skew-ps`, `max-frame-size = <3800>`)|
|`\&usb1`|**absent**|**required** — no USB means no controllers, no keyboard|
|`\&fpga_bridge0/1/2`|**absent**|**required**|
|`MiSTer_fb` (`reg = <0x22000000 0x800000>`, IRQ 40)|absent|required|
|`\&spi0` → `MiSTer,spi-audio`|absent|required|
|`\&spi1` → `spibri@0` → `/dev/spidev1.0`|absent|required (see §13, spidev hazard)|
|`\&i2c2`, `\&uart1` (DMA props deleted)|absent|required|
|`i2c-gpio` bus + RTC (`pcf8563`/`m41t81`/`mcp7941x`)|absent|required (RTC add-on board)|
|`gpio-leds` `hps_led0`, `regulator_3_3v`, mmc0 vmmc/vqmmc|absent|required|

**Crucially, every one of these is a device-tree gap, not a driver gap.** Mainline's
`socfpga.dtsi` already *defines* `fpga_bridge0/1/2`, `usb1` (`snps,dwc2`), `spi0`, `spi1`,
`i2c2`, and `uart1` — they are simply not enabled for this board. The drivers (dwc2,
socfpga fpga-bridge, spi-dw, i2c-gpio, gpio-leds, the RTCs, stmmac) have all been mainline
for years.

**Disposition: carry our own DTS as a patch in `linux-patches/`**, based on mainline's and
adding the nodes above. Same mechanism as the driver patches. No extra machinery.

### 4.2 The rootfs: recoverable by inspection

The shipped image is fully legible: **626 shared libraries, 1,885 binaries, and 52 `.ko.xz`
kernel modules** (WiFi, Bluetooth USB, xone — everything else is built in). The SONAME list
reads directly as a Buildroot package list. Better still, the kernel carries
`CONFIG_IKCONFIG=y`, so **the exact stock kernel config is extractable from the shipped
zImage** — we have it, along with the exact stock DTB (`docs/stock-inventory/`).

Shipped versions today — the reason this project exists:

|Component|Shipped|Status|
|-|-|-|
|Linux|5.15.**1** (Nov 2021)|\~190 stable releases behind|
|glibc|2.31 (Feb 2020)||
|Samba|4.14.6|long EOL|
|curl|7.78.0||
|OpenSSH|8.6p1||
|BusyBox|1.33.1||
|bluez|5.61||
|Python|3.9|EOL|

This box runs an SMB server, an FTP server, and SSH, and people put it on home networks.

**Size:** the rootfs is **93% full** (297 MB used of 347 MB). A modern package set will not
shrink. Budget for a 512 MiB `linux.img` and audit what assumes 400 MB.

---

## 5\. Key design decision: kill the `loop=` patch with an initramfs

Today the kernel is patched to loop-mount `linux/linux.img` from within `init/do_mounts.c`.
This is a patch to a core kernel file that upstream has since rewritten.

**Replace it with a \~200 KB embedded initramfs.** Two build mechanics matter and are easy
to get wrong:

* **Not `BR2_TARGET_ROOTFS_INITRAMFS`** — that option embeds the *entire target rootfs*
(\~300 MB) into the kernel image. Instead, a **second, minimal Buildroot config**
(`configs/mister_initramfs_defconfig`: static BusyBox, `BR2_TARGET_ROOTFS_CPIO`) produces a
tiny cpio that the main build's kernel consumes via `CONFIG_INITRAMFS_SOURCE`. CI sequences
the two builds.
* The initramfs **must be embedded in the zImage**: the stock U-Boot boot command (kept
byte-identical, §8) never loads a separate initrd.

And `/init` must be **cmdline-driven, not hardcoded**. U-Boot is unchanged, so the cmdline
still carries `root=$mmcroot loop=linux/linux.img ro rootwait` — and existing `u-boot.txt`
setups override `$mmcroot` (USB boot). `/init` parses `root=` (the data partition, FAT32
**or exFAT**) and `loop=` (image path) from `/proc/cmdline`, implements `rootwait` as a
retry loop, and on any failure prints a diagnostic banner and drops to a serial rescue
shell. In sketch:

```sh
# real script parses root=/loop= from /proc/cmdline, retries until the
# device appears (rootwait), tries vfat then exfat, rescue shell on failure
#
# [P0] -o sync,dirsync is NOT optional: stock mounts /media/fat sync,dirsync
# from the kernel and /etc/fstab never re-mounts it. Mounting async here would
# be a real power-off-corruption regression, not a tuning choice.
mount -t vfat -o sync,dirsync "$rootdev" /mnt/fat || \
  mount -t exfat -o sync,dirsync "$rootdev" /mnt/fat

# [P0] Use losetup -f, NOT a hardcoded /dev/loop8. loop8 is an artifact, not a
# contract: LOOP_MIN_COUNT=8 pre-creates loop0-7 only (loop8 is instantiated on
# demand), and nothing in the stock rootfs or Main_MiSTer references it by name.
loopdev="$(losetup -f)"
losetup -r "$loopdev" "/mnt/fat/$looppath"
mount -o ro "$loopdev" /newroot

# move the data-partition mount so /media/fat is already there
mount --move /mnt/fat /newroot/media/fat
exec switch_root /newroot /sbin/init
```

Benefits:

* **Eliminates an out-of-tree patch to a hot, frequently-refactored core file.** This is the
single biggest reduction in long-term maintenance burden in the whole plan.
* Boot semantics become debuggable and testable in userspace — the same cpio boots under a
generic QEMU ARM machine in CI against synthetic FAT/exFAT disks (§11).
* The `loop=` and `root=` args keep their exact stock semantics, so every existing
`u-boot.txt` keeps working; `mem=511M` and `memmap=` stay untouched.
* Buildroot builds it natively as a second minimal config. The only new machinery is
sequencing two builds.

Cost: the kernel `zImage` grows slightly; boot gains a few hundred milliseconds.
Worth it several times over.

---

## 6\. Repository layout

A single `BR2_EXTERNAL` tree. Buildroot itself is fetched, never vendored.

```
mister-linux/
├── external.desc
├── external.mk
├── Config.in
├── configs/
│   ├── mister_de10nano_defconfig
│   └── mister_initramfs_defconfig     # stage-1 tiny static-BusyBox cpio (§5)
├── board/mister/de10nano/
│   ├── linux.config                   # full kernel config (make savedefconfig)
│   ├── linux-patches/                 # → BR2_LINUX_KERNEL_PATCH
│   │   ├── 0001-fbdev-add-MiSTer_fb-driver.patch
│   │   ├── 0002-sound-add-MiSTer-audio-spi.patch
│   │   ├── 0003-cpufreq-cyclone5-overclock.patch
│   │   ├── 0004-dts-de10nano-MiSTer.patch      # §4.1a — usb1, bridges, fb, spi, rtc
│   │   ├── 0005-spidev-accept-altspi-compatible.patch
│   │   ├── 0010-hid-guncon2.patch
│   │   ├── 0011-hid-guncon3.patch
│   │   ├── 0012-hid-fanatec.patch
│   │   ├── 0013-hid-flydigi-vader.patch
│   │   └── 0020-usb-storage-blacklist-realtek-cdrom.patch
│   ├── uboot-patches/                 # empty in v1
│   ├── rootfs-overlay/
│   │   ├── etc/init.d/S??…            # BusyBox init scripts (parity with stock)
│   │   ├── etc/fstab
│   │   └── media/fat/                 # mount point
│   ├── initramfs-overlay/
│   │   └── init                       # the switch_root script from §5
│   ├── genimage.cfg
│   ├── post-build.sh                  # writes MiSTer.version
│   ├── post-image.sh                  # assembles release_YYYYMMDD.7z
│   └── readme.md
├── package/
│   ├── rtl8812au/                     # Buildroot kernel-module packages
│   ├── rtl8821cu/
│   ├── rtl88x2bu/
│   ├── rtl8188eu/
│   ├── rtl8188fu/
│   └── xone/
├── scripts/                           # inventory generators, ABI checker, CI test suite
├── .github/workflows/
│   ├── build.yml                      # build + upload Release assets
│   └── publish-db.yml                 # regenerate and publish db.json
├── renovate.json                      # dependency automation — §9, final hardening step
└── docs/
    ├── abi-contract.md                # §3, expanded — the thing we must not break
    ├── patch-provenance.md            # every patch: origin, upstream status, owner
    ├── boot-chain.md                  # U-Boot contract: zImage_dtb, ATAGs, u-boot.txt env
    ├── downloader-contract.md         # LinuxUpdater: 7z layout, MD5, version semantics
    └── decisions/                     # ADRs: toolchain, initramfs, xone firmware, HIL rig
```

### How kernel patches work without a kernel repo (G4)

```
BR2_LINUX_KERNEL=y
BR2_LINUX_KERNEL_CUSTOM_VERSION=y
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.xx"
BR2_LINUX_KERNEL_PATCH="$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/linux-patches"
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de10nano/linux.config"
BR2_LINUX_KERNEL_DTS_SUPPORT=y
BR2_LINUX_KERNEL_INTREE_DTS_NAME="intel/socfpga/socfpga_cyclone5_de10nano"
# NOT BR2_TARGET_ROOTFS_INITRAMFS — that would embed the whole rootfs (§5).
# The stage-1 cpio from mister_initramfs_defconfig is wired in via
# CONFIG_INITRAMFS_SOURCE in linux.config.
```

Buildroot downloads a **signed, hash-verified kernel.org tarball** and applies our patch
directory on top. Bumping 6.18.38 → 6.18.39 is a one-line change and CI tells us if a patch
stopped applying. That is the entire point: **stable updates become mechanical instead of
manual.**

Note: mainline gained `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts` in
January 2025 (landed \~v6.14), so 6.18 has it. But it is **not sufficient on its own** — see
§4.1a. We base our DTS on it and patch in the missing nodes.

---

## 7\. Kernel version choice: **6.18 LTS**, pinned from kernel.org

### Do not use Buildroot's default kernel

Buildroot 2026.02.3 sets `BR2_LINUX_KERNEL_LATEST_VERSION` to **6.19.14**. **6.19 is not an
LTS and is already end-of-life** — it released 8 Feb 2026, its last stable was 6.19.14 on
22 Apr 2026, and 7.0/7.1 have shipped since. That default has received no security fixes for
months.

This is not a Buildroot defect. `BR2_LINUX_KERNEL_LATEST_VERSION` means *"newest kernel at the
time this branch was cut"* — it is not a recommendation, and Buildroot's LTS guarantee covers
**Buildroot's own package infrastructure and package security fixes**, not your kernel choice.
Buildroot expects boards to pin, and nearly every in-tree board defconfig does.

**We always pin: `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`.**

### Which LTS

Greg Kroah-Hartman revised the longterm EOL dates on 25 Feb 2026:

|Kernel|EOL|Notes|
|-|-|-|
|**6.18**|**Dec 2028**|LTS. DE10-Nano DTS in-tree. Altera maintains `socfpga-6.18.x-lts`.|
|6.12|Dec 2028|LTS. Also CIP "Super LTS" (10-year, limited patches).|
|6.6|Dec 2027|LTS|
|6.1|Dec 2027|LTS|
|**5.15**|**Dec 2026**|← MiSTer's current base. Dead in \~5 months.|

**Recommendation: 6.18 LTS.** The EOL extension erased 6.12's longevity advantage — both now
run to Dec 2028 — so take the newer tree. 6.18 additionally has the DE10-Nano DTS in-tree as a
starting point, and Altera's `socfpga-6.18.x-lts` branch exists as a cross-check if a
Cyclone V-specific fix is ever needed.

### Why mainline and *not* Altera's tree

Altera's `linux-socfpga` adds `ALTERA_SYSID`, `ALTERA_ILC`, `OF_CONFIGFS`, and
`FB_ALTERA_VIP_FB2_PLAT`. **MiSTer uses none of them.** Cyclone V SoC support — clk, pinctrl,
reset, fpga-mgr, fpga-bridge, dw\_mmc, dwc2, stmmac, spi-dw — has been mainline for a decade.
The vendor tree buys us nothing and costs us a dependency that lags upstream stable.

**Use pristine kernel.org tarballs + `linux-patches/`.** Bumping 6.18.38 → 6.18.39 becomes a
one-line change, and CI tells us immediately if a patch stopped applying.

---

## 8\. U-Boot: deliberately deferred

The request was for a modern U-Boot. Here is the honest assessment.

**v1 keeps `uboot.img` byte-identical**, carried forward from `U-boot_MiSTer` (a fork of
U-Boot 2017.03).

Rationale:

* **Highest blast radius, lowest user benefit.** A bad SPL — wrong DDR calibration, wrong
pinmux — presents to the user as a bricked board. This is the *first* thing that runs.
* The kernel↔U-Boot contract here is `bootz` + FDT + a cmdline. It is **version-agnostic**.
A 6.18 `zImage` boots fine off the 2017 SPL. The two problems are genuinely decoupled;
coupling them is a self-inflicted wound.
* MiSTer's U-Boot has custom behaviour that must be reproduced before it can be replaced —
at minimum the `u-boot.txt` environment-from-FAT mechanism (this is how the per-board
`ethaddr` gets set; `mr-fusion` writes it during install).

*Verified from the shipped artifacts* (`docs/verification/stock-release-20250402.md`):
`uboot.img` is four identical 64 KiB SPL copies plus a `U-Boot 2017.03+ for de10-nano`
uImage at offset 256 KiB. The environment is baked in (`bootcmd`/`mmcload`/`mmcboot`, plus
`fpgaload`/`fpgacheck` — U-Boot pre-loads `menu.rbf` into the FPGA and supports a
warm-reboot core handoff via reserved RAM), and `u-boot.txt` is applied with
`env import -t`. Critically, **the Downloader runs `updateboot` on every linux update**,
which `dd`-writes the shipped `uboot.img` over the raw boot partition and **erases U-Boot's
saved environment at sector 1**. Two consequences: shipping the stock `uboot.img`
byte-identical is load-bearing (whatever we ship gets flashed), and no state survives in the
saved environment — the effective env is always built-in defaults + `u-boot.txt`.

**Phase 5 path**, once everything else is stable and hardware-tested:

* Mainline U-Boot has `socfpga_de10_nano_defconfig` and `board/terasic/de10-nano/` with QTS
handoff headers for DDR/pinmux/PLL.
* Buildroot builds it: `BR2_TARGET_UBOOT` + `BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME="u-boot-with-spl.sfp"`

  * a `uboot-patches/` directory, exactly mirroring the kernel model.
* Must port: `u-boot.txt` env loading, the FPGA/bridge init, and the boot script.
* **Gate on:** a hardware test matrix and a documented recovery procedure. Ship behind an
explicit opt-in flag, separate from the `linux.img` update.

Change one variable at a time.

---

## 9\. Release engineering (G5, G6)

### Build

* GitHub Actions, containerized, pinned base image.
* Cache Buildroot `dl/` and `ccache` between runs.
* `make legal-info` on every build → SBOM + license manifest as a release artifact.
*(Note: the current image ships no manifest, no `.config`, and no legal-info at all.)*
* GitHub artifact attestations (`actions/attest-build-provenance`) on the image assets, so
anyone can verify a downloaded `linux.img` came from this repo's CI at a given commit.

### Artifacts — **GitHub Release assets, never committed**

```
release_YYYYMMDD.7z         # files/linux/{linux.img,zImage_dtb,uboot.img}
linux.img
zImage_dtb
SHA256SUMS
buildroot.config            # exact, reproducible
linux.config
legal-info.tar.gz           # SBOM
```

The repo stays under \~10 MB. For contrast, `SD-Installer-Win64_MiSTer` is **5.8 GB** of
committed archives, `Distribution_MiSTer` is 1.9 GB, and `Main_MiSTer` carries **95 committed
binaries (67 MB) with no CI at all**.

### Reproducibility checklist

* \[x] Buildroot version pinned (2026.02.x LTS)
* \[x] Kernel version + upstream hash pinned; patches in-tree
* \[x] `BR2_DOWNLOAD_DIR` populated from upstream; no vendored tarballs
* \[x] `buildroot.config` and `linux.config` published with every release
* \[x] ext4 generation pinned: fixed UUID, pinned filesystem feature set, `SOURCE_DATE_EPOCH`,
`BR2_REPRODUCIBLE=y` — 2026-era `mke2fs` defaults (random UUID/hash seed, new features) break
determinism unless pinned *(stock reference: `HAS_JOURNAL`, `METADATA_CSUM`, `64BIT`,
`FLEX_BG`, fixed UUID)*
* \[x] Two independent builders get identical `linux.img` hashes — enforced by a CI job that
builds twice and compares

### Dependency automation — the final hardening step

Once the pipeline is stable and trusted, **Renovate** keeps every moving part current
automatically. This mechanizes the sustainability commitment of §13:

* Buildroot 2026.02.x tarball version + SHA-256 (custom/regex manager over the pin file)
* Kernel 6.18.y version + hash (custom datasource over kernel.org's `releases.json`)
* morrownr driver packages and other commit pins (git datasource)
* CI container image digests and GitHub Actions versions

Every Renovate PR gets the full CI treatment — build, patch-apply, ABI checks, double-build
reproducibility — so a stable bump that breaks a carried patch is caught in the PR, never on
user hardware. Deliberately sequenced last: automate a pipeline only after it has earned
trust.

---

## 10\. Distribution: the opt-in `db.json`

`Downloader_MiSTer`'s `LinuxUpdater` reads a top-level `linux` key from **any configured
database**, compares `version` (last 6 characters) against the running system's
`/MiSTer.version`, and applies the archive if they differ. The official entry looks like
this:

```json
"linux": {
  "hash": "8dc3acae7d758a80a363fbd7ad31d95d",
  "size": 93727644,
  "url": ".../SD-Installer-Win64_MiSTer/b8531c78.../release_20250402.7z",
  "version": "250402"
}
```

Note it is **commit-pinned and MD5-verified** — the Downloader does supply-chain hygiene
properly. We publish an identically-shaped entry pointing at our GitHub Release asset.

The full updater contract has been **verified from `Downloader_MiSTer` source and the shipped
artifacts** (`docs/verification/stock-release-20250402.md`):

* Version check: the running system's `/MiSTer.version` vs the **last 6 characters** of the
db entry's `version` — *inequality*, not ordering.
* Extraction: a **pinned ARM `7za`** the Downloader fetches on demand from the SD-Installer
repo (MD5-verified) — nothing in the installed image performs it. Only `files/linux/*` is
extracted; the rest of the archive serves the Windows SD installer.
* Apply: user files are copied *into* the new image (§3 contract), `files/linux/` is rsynced
over `/media/fat/linux/` (so `updateboot` and the config templates ship with us),
**`updateboot` flashes `uboot.img`**, then `linux.img` is swapped into place and a reboot
flag is raised.

Users add one database to `downloader.ini` and opt in.

**Known wrinkle — [P0: worse than "document the ordering". There IS no ordering.]**
`LinuxUpdater` warns `"Too many databases try to update linux. Only 1 can be processed"`
and takes `_linux_descriptions[0]`. v2 of this plan said "document the exact
`downloader.ini` ordering". **No such ordering exists, and the user cannot control it:**

* `sorted_db_sections()` forces `default_db_id` — i.e. **`distribution_mister`** — to the
**front** of the push queue;
* `installed_dbs` is appended in **job-completion order** across six concurrent workers,
not in `downloader.ini` order;
* a db's job completes as soon as *its own* `db.json` is fetched and parsed.

⇒ **The winner is whichever `db.json` parses first.** Ours wins only because it is tiny
against Distribution's multi-megabyte catalog. That is an **emergent property of relative
payload size, not a guarantee** — and it could flip if Distribution's db shrinks or the
Downloader's threading changes.

Two consequences, both load-bearing:
1. **Keeping our `db.json` minimal (empty `files`/`folders`) is a design rule, not an
aesthetic preference.** It is the only thing that wins us the race.
2. **Onboarding uses the Downloader's drop-in ini mechanism** (`/media/fat/downloader_*.ini`
or `/media/fat/downloader/*.ini`) rather than an edit to the user's `downloader.ini`.

Full source citations: `docs/downloader-contract.md` (P0.6). See also open question **Q3**.

**[P0] The update is not atomic, and its success signal cannot be trusted.** The flash-phase
shell script (`linux_updater.py:157-168`) runs **without `set -e`** and ends in `touch`, so
its exit status is `touch`'s. **A failed `mv`, `rsync`, or `updateboot` still reports
success and still raises the reboot flag.** P4.8's rollback runbook must assume a "successful"
update may have half-failed.

**Rollback is trivial and must be documented prominently:** remove the db line, re-run the
Downloader, get the official `linux.img` back. (It works precisely *because* the version
check is an inequality, not an ordering — a "downgrade" is just a different string.)

---

## 11\. Validation

### ABI smoke test (the gate for everything)

Boot the new image and run the **unmodified, stock `MiSTer` binary from `Distribution_MiSTer`**.
If it does not reach the menu, nothing else matters. This test comes first.

**CI vs hardware split.** QEMU has no Cyclone V machine model, so per-commit CI cannot boot
the real image. CI instead runs: (a) static SONAME/ABI checks of the built rootfs against the
contract; (b) the stock `MiSTer` binary under a `qemu-arm` chroot of the new rootfs — it must
get past dynamic linking and early init, failing only at the whitelisted FPGA-access point;
(c) the initramfs cpio booted on a generic QEMU ARM machine against synthetic FAT/exFAT
disks. **Real hardware gates each release** — manually at first, optionally automated later
with a HIL rig (USB-SD-mux, power control, serial capture) as a self-hosted runner.

### Hardware matrix

* Boot to menu; **boot time to menu must not regress** (users notice)
* HDMI output across resolutions; analog I/O board; VGA
* USB controllers (xpad, xone, hid-nintendo, GunCon, Fanatec, Flydigi)
* Bluetooth pairing
* WiFi across the Realtek dongle zoo — **the single most likely regression area**
* Samba, SSH, FTP
* MIDI / MT-32 (fluidsynth, soundfonts)
* Save states, CHD/CD cores, `exFAT` mount of `MiSTer_Data`
* `update.sh`, `wifi.sh`, and a sample of popular community scripts
* SD card compatibility spread

### Regression budget

* Boot-to-menu time: ≤ current
* Free RAM at menu: ≤ current
* Rootfs free space: ≥ 15% **of the 512 MiB image we build** — **[P0: state the budget
against our image, not stock's. Stock's 375 MiB rootfs is only 13.56% free, so "≥ 15%"
measured against stock would fail on stock itself.]**

---

## 12\. Phases

|Phase|Work|Exit criterion|
|-|-|-|
|**P0 — Recon**|Write `docs/abi-contract.md`. Triage all \~60 kernel commits into classes A–F with provenance. Derive the Buildroot package set from the shipped image.|Patch triage table is complete and reviewed|
|**P1 — Kernel**|Buildroot builds 6.18 LTS from kernel.org + `linux-patches/`. Forward-port `MiSTer_fb`, audio-spi, cpufreq. Replace `loop=` with the initramfs (§5).|Boots to a serial console on real hardware|
|**P2 — Rootfs**|Buildroot 2026.02 rootfs, glibc, SONAME parity. Read-only root preserved.|**Stock `MiSTer` binary reaches the menu.**|
|**P3 — Parity**|WiFi, Bluetooth, Samba, FTP, SSH, MIDI. CI + release artifacts + SBOM.|Hardware matrix (§11) green|
|**P4 — Beta**|Publish `db.json`. Recruit testers. Document rollback. Final pipeline hardening: Renovate dependency automation (§9).|Sustained opt-in use, no P1 bugs|
|**P5 — U-Boot**|*Optional.* Mainline U-Boot via Buildroot (§8).|Separate opt-in; recovery procedure documented|

Sequential. Each phase's exit criterion is a hardware test, not a code review.

The task-level breakdown — per-task model assignments, dependencies, and acceptance
criteria — lives in `TASKS.md`.

---

## 13\. Risks

|Risk|Severity|Mitigation|
|-|-|-|
|`MiSTer_fb` / `/dev/mem` FPGA ABI breaks on 6.x|**High**|P2's exit criterion *is* this test. Fail fast.|
|Realtek USB WiFi drivers don't build on 6.18|High|Source from morrownr upstream, who track modern kernels. Do not vendor 2021 copies.|
|**`spidev` binding hazard** — **[P0: mis-described.]** `altspi` is **not** a catch-all bind: it is an explicit one-line entry in `spidev_dt_ids[]` (`drivers/spi/spidev.c:699`, added by fork commit `246984fce`). The hazard is still real on 6.18 — an unlisted compatible means spidev never probes ⇒ no `/dev/spidev1.0` — but the fix is cleaner than feared.|Low **[P0: was Medium]**|**Since we author our own DTS (§4.1a), retarget the compatible to one mainline spidev already accepts and delete patch `0005` entirely.** Also **[P0]**: this drives a **pi-top hub** (brightness/lid), *not* MiSTer's own I/O board — the original "silent loss of I/O-board brightness control" was the wrong peripheral, which lowers the blast radius considerably.|
|**[P0] exFAT symlinks (class G, §4.1)** — stock's out-of-tree exfat driver supports symlinks on `/media/fat`; Main_MiSTer resolves them; mainline exfat/vfat cannot.|**High**|**Unbudgeted.** Open question **Q1** — needs a human answer on whether the community relies on it. Carrying the driver forward to 6.18 is a large, permanent maintenance burden; dropping it ships a user-visible regression.|
|**[P0] `CONFIG_BLK_DEV_INITRD` is OFF in stock** — and `CONFIG_INITRAMFS_SOURCE` depends on it.|**High**|P1.3's own instruction ("port the stock config via `olddefconfig`") would produce a kernel with **no initramfs slot at all**, silently removing the mechanism §5 depends on to delete the `loop=` patch. Now constraint **A11**; P1.3 must turn it on as an explicit divergence.|
|**[P0] The Downloader's flash phase cannot report its own failure** (no `set -e`; script ends in `touch`).|Medium|Not fixable by us — it is in the shipped updater. P4.8's rollback runbook must assume a reported-successful update may have half-failed. Argues for a serial-console recovery guide.|
|**[P0] Python 3.9 → 3.14** — `Downloader_MiSTer` pins **3.9** in its own CI and builds against `python3.9-dev`. It has never been tested on any interpreter we would ship.|Medium **[P0: was a suspicion (A6), now evidenced]**|P3.9 is a real gate, not a formality. Report incompatibilities upstream rather than pinning an EOL Python.|
|DTS gaps (§4.1a) — missing USB, FPGA bridges, RTC bus|High|Carried as `0004-dts-de10nano-MiSTer.patch`. Drivers all exist mainline; this is config, not code.|
|Rootfs exceeds the image budget|Medium|Grow `linux.img` to 512 MiB; audit assumptions about 400 MB.|
|Boot regression from the initramfs|Low|Measurable; budget in §11.|
|Bricking via U-Boot|**Critical**|Deferred to P5, opt-in, recovery documented.|
|Community fragmentation / abandonment|**High**|Be strictly drop-in. Ship a working artifact before making an argument. **If nobody will commit to tracking 6.18.y stable for years, do not start.**|

That last one is not a joke. A stale fork is worse than no fork, because it splits the
"which `linux.img` are you on?" support surface across a volunteer community. The entire
value proposition of this project is *sustained* maintenance — which is why §9 ends by
handing routine bumps to Renovate + CI, reducing the steady-state cost to reviewing green
PRs. If even that is not on offer, the honest move is to publish the patch triage and the
ABI contract as documentation and stop there — that alone would be a real contribution.

---

## 14\. What lands first

If this stalls at P1, it should still have been worth doing. Three deliverables have
standalone value and are hard for anyone to object to:

1. **`docs/abi-contract.md`** — the first written description of what MiSTer's userland
actually requires of its kernel and rootfs. Nobody has this.
2. **`docs/patch-provenance.md`** — every one of the \~60 kernel commits classified, with its
upstream status. This is the map nobody has drawn.
3. **A 6.18 LTS kernel tree, built by Buildroot from a pristine tarball, that boots the board.**

Publish those. Let the artifact make the argument.

