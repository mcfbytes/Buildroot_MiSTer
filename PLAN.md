# MiSTer Linux Modernization Plan

**A reproducible, drop-in `linux.img` built from a modern Buildroot, with all kernel
patches carried in-tree as Buildroot patch files.**

Status: proposal / RFC
Target board: Terasic DE10-Nano (Cyclone V SoC, `armv7-a` Cortex-A9)

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
* **glibc** (any version ≥ 2.31; newer is fine and is the point)
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

* `mem=511M` is **load-bearing**: the top \~513 MB of DDR is reserved for the FPGA fabric
(core framebuffers, scaler, emulated RAM). Do not change.
* Root filesystem is mounted **read-only**. This is a good design — an immutable root with
writable state on `/media/fat` and tmpfs. **Preserve it.**
* `linux.img` is a file on the FAT partition, loop-mounted as root.

### Kernel ABI surface

* `MiSTer_fb` ioctl ABI (`drivers/video/fbdev/MiSTer_fb.c`)
* `MiSTer-audio-spi` (`sound/drivers/MiSTer-audio-spi.c`)
* `fpga_io.cpp` pokes the HPS↔FPGA bridges via `/dev/mem` at hardcoded Cyclone V addresses
* Cyclone V cpufreq/overclock driver

### Filesystem / runtime conventions

* `/media/fat` mount point
* `/media/fat/linux/MiSTer.version` — 6-char `YYMMDD`, compared by Downloader
* BusyBox init with `S01syslogd … S99user` script names
* ext4, volume label `rootfs`

---

## 4\. What has to change, and how hard each piece is

### 4.1 The kernel: smaller than it looks

The MiSTer 5.15 fork carries \~60 commits. Triaged:

|Class|Content|Disposition|
|-|-|-|
|**A. MiSTer core**|`MiSTer_fb.c`, `MiSTer-audio-spi.c`, Cyclone V cpufreq/overclock, `MiSTer_defconfig`|**Carry as patches.** The real work.|
|**B. `loop=` root patch**|`init/do_mounts.c` — adds a `loop=` cmdline param that mounts the FAT partition at `/root2`, loop-mounts `linux/linux.img` on `/dev/loop8`, and uses it as root|**DELETE — replace with an initramfs.** See §5.|
|**C. HID, now upstream**|NSO controllers, `hid-nintendo`, many `xpad` IDs|**Drop.** Mainline 6.18 has these.|
|**D. HID, still out-of-tree**|`xone`, GunCon 2/3, Fanatec, Flydigi Vader, remaining `xpad` IDs|**Carry** as patches, or as Buildroot kernel-module packages where an upstream exists.|
|**E. Realtek USB WiFi**|`rtl8188eu`, `rtl8188fu`, `rtl8812au`, `rtl8821au`, `rtl8821cu`, `rtl88x2bu`|**Re-source from morrownr upstream as Buildroot `kernel-module` packages.** Do not vendor.|
|**F. Misc quirks**|mmc LED, btusb VID/PIDs, usb-storage CD-ROM blacklist|Check upstream first; carry the remainder.|

**Class B is the one that will bite.** `init/do_mounts.c` was substantially refactored in the
6.x series (`mount_block_root` and friends are gone). Forward-porting that patch is both hard
*and unnecessary* — see §5.

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

The shipped image is fully legible: **626 shared libraries, 1,885 binaries, zero `.ko` files**
(everything is built into the kernel today). The SONAME list reads directly as a Buildroot
package list. We do not need Sorg's `.config`; we need the *requirements*, which we can derive.

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

**Replace it with a \~200 KB Buildroot-built initramfs** embedded in the kernel
(`BR2_TARGET_ROOTFS_INITRAMFS`) whose `/init` does:

```sh
mount -t vfat /dev/mmcblk0p1 /mnt/fat
losetup -r /dev/loop8 /mnt/fat/linux/linux.img
mount -o ro /dev/loop8 /newroot
# move the FAT mount into the new root so /media/fat is already there
mount --move /mnt/fat /newroot/media/fat
exec switch_root /newroot /sbin/init
```

Benefits:

* **Eliminates an out-of-tree patch to a hot, frequently-refactored core file.** This is the
single biggest reduction in long-term maintenance burden in the whole plan.
* Boot semantics become debuggable and testable in userspace.
* The `loop=` and `root=` cmdline args go away; `mem=511M` and `memmap=` stay.
* Buildroot builds it natively. No new tooling.

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
│   └── mister_de10nano_defconfig
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
├── .github/workflows/
│   ├── build.yml                      # build + upload Release assets
│   └── publish-db.yml                 # regenerate and publish db.json
└── docs/
    ├── abi-contract.md                # §3, expanded — the thing we must not break
    └── patch-provenance.md            # every patch: origin, upstream status, owner
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
BR2_TARGET_ROOTFS_INITRAMFS=y
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
* \[x] Two independent builders should get identical `linux.img` hashes (stretch: bit-for-bit)

---

## 10\. Distribution: the opt-in `db.json`

`Downloader_MiSTer`'s `LinuxUpdater` reads a top-level `linux` key from **any configured
database**, compares `version` against `/media/fat/linux/MiSTer.version`, and applies the
archive if they differ. The official entry looks like this:

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

Users add one database to `downloader.ini` and opt in.

**Known wrinkle:** `LinuxUpdater` warns `"Too many databases try to update linux. Only 1 can be processed"` — if both our db and the official Distribution db provide `linux`, only the
first wins. Document the exact `downloader.ini` ordering. This determines whether onboarding
is one line or a support thread.

**Rollback is trivial and must be documented prominently:** remove the db line, re-run the
Downloader, get the official `linux.img` back.

---

## 11\. Validation

### ABI smoke test (the gate for everything)

Boot the new image and run the **unmodified, stock `MiSTer` binary from `Distribution_MiSTer`**.
If it does not reach the menu, nothing else matters. This test comes first and runs on every CI
build against a hardware runner.

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
* Rootfs free space: ≥ 15%

---

## 12\. Phases

|Phase|Work|Exit criterion|
|-|-|-|
|**P0 — Recon**|Write `docs/abi-contract.md`. Triage all \~60 kernel commits into classes A–F with provenance. Derive the Buildroot package set from the shipped image.|Patch triage table is complete and reviewed|
|**P1 — Kernel**|Buildroot builds 6.18 LTS from kernel.org + `linux-patches/`. Forward-port `MiSTer_fb`, audio-spi, cpufreq. Replace `loop=` with the initramfs (§5).|Boots to a serial console on real hardware|
|**P2 — Rootfs**|Buildroot 2026.02 rootfs, glibc, SONAME parity. Read-only root preserved.|**Stock `MiSTer` binary reaches the menu.**|
|**P3 — Parity**|WiFi, Bluetooth, Samba, FTP, SSH, MIDI. CI + release artifacts + SBOM.|Hardware matrix (§11) green|
|**P4 — Beta**|Publish `db.json`. Recruit testers. Document rollback.|Sustained opt-in use, no P1 bugs|
|**P5 — U-Boot**|*Optional.* Mainline U-Boot via Buildroot (§8).|Separate opt-in; recovery procedure documented|

Sequential. Each phase's exit criterion is a hardware test, not a code review.

---

## 13\. Risks

|Risk|Severity|Mitigation|
|-|-|-|
|`MiSTer_fb` / `/dev/mem` FPGA ABI breaks on 6.x|**High**|P2's exit criterion *is* this test. Fail fast.|
|Realtek USB WiFi drivers don't build on 6.18|High|Source from morrownr upstream, who track modern kernels. Do not vendor 2021 copies.|
|**`spidev` binding hazard** — `brightness.cpp` opens `/dev/spidev1.0`, which comes from a `spibri@0 { compatible = "altspi"; }` node. **There is no `altspi` driver anywhere in MiSTer's kernel** — `spidev` is binding it as a catch-all. Modern kernels restrict spidev's DT matching.|Medium|Change the compatible to one spidev accepts, or patch spidev's match table (`0005-…`). Trivial to fix, easy to miss — presents as silent loss of I/O-board brightness control.|
|DTS gaps (§4.1a) — missing USB, FPGA bridges, RTC bus|High|Carried as `0004-dts-de10nano-MiSTer.patch`. Drivers all exist mainline; this is config, not code.|
|Rootfs exceeds the image budget|Medium|Grow `linux.img` to 512 MiB; audit assumptions about 400 MB.|
|Boot regression from the initramfs|Low|Measurable; budget in §11.|
|Bricking via U-Boot|**Critical**|Deferred to P5, opt-in, recovery documented.|
|Community fragmentation / abandonment|**High**|Be strictly drop-in. Ship a working artifact before making an argument. **If nobody will commit to tracking 6.18.y stable for years, do not start.**|

That last one is not a joke. A stale fork is worse than no fork, because it splits the
"which `linux.img` are you on?" support surface across a volunteer community. The entire
value proposition of this project is *sustained* maintenance. If that is not on offer,
the honest move is to publish the patch triage and the ABI contract as documentation and
stop there — that alone would be a real contribution.

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

