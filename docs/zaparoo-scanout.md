# zaparoo-scanout: the `zaparoo_scanout` kernel module

`package/zaparoo-scanout` builds Zaparoo's `zaparoo_scanout` out-of-tree kernel
module and ships it in DE10-Nano images as
`/usr/lib/modules/<kver>/updates/zaparoo_scanout.ko.xz`.

## 1. What it does

Loading the module registers the misc device `/dev/zaparoo-scanout` (mode
0600, opening it needs `CAP_SYS_RAWIO`). One open file at a time owns two
write-combined RGB565 framebuffer slots, each large enough for 1920x1080:

| Slot | Physical address | `mmap` offset |
|---|---|---|
| 0 | `0x23000000` | `0` |
| 1 | `0x23400000` | `8294400` |

Both slots sit above the `MiSTer_fb` device-tree aperture (`0x22000000`,
8 MiB) and above the `mem=511M` boundary, so Linux never manages that memory.
The ioctl `ZAPAROO_SCANOUT_GET_LAYOUT` (`_IOR('Z', 1, ...)`) returns a 64-byte
layout struct; the header is `kernel/scanout-slots/zaparoo_scanout_uapi.h` in the
source tree.

Since upstream commit `a1fdb653` (layout v2) the owner can also map the Menu
core's native video window at `0x3A000000` (3 MiB: one uncached control page,
then write-combined pixels), reserved on first map rather than at open. The
ioctl `ZAPAROO_SCANOUT_WAIT_NATIVE_VBLANK` waits up to 50 ms for the core's
`video_sync` pulse on GIC SPI 41 (`f2h_irq1`, next to `MiSTer_fb`'s SPI 40).
The interrupt is requested on the first wait and freed when the file is
released. Nothing else in the regular kernel's device tree uses SPI 41, and the
RT beta series keeps it free on purpose (`linux-patches-beta/0043`). The module
sends no FPGA commands and owns no DMA.

It is **not autoloaded**: there is no modalias, so the client loads it with
`modprobe zaparoo_scanout`.

## 2. Source and pin

- Upstream: [ZaparooProject/Menu_MiSTer](https://github.com/ZaparooProject/Menu_MiSTer),
  subdirectory `kernel/scanout-slots/`. It is derived from the MiSTer-MagiK
  scanout-slots module.
- The pin is a commit on `master`. Buildroot downloads the whole repository
  archive (~28 MB, mostly FPGA release binaries) and builds only that
  subdirectory (`ZAPAROO_SCANOUT_MODULE_SUBDIRS`).
- Renovate tracks the pin through the `ZaparooProject/Menu_MiSTer` regex
  manager, on a **monthly** schedule (the 1st, before 06:00), with the
  `driver-pin` label. `renovate-hash-sync.yml` refreshes the hash as for any
  other github-archive pin.

## 3. Local patch

`0001-zaparoo_scanout-accept-any-6.18-point-release.patch` replaces
`validate_platform()`'s comparison of `utsname()->release` against the literal
`"6.18.38-MiSTer"` with a check for the `6.18.` series. Without it the module
returns `-ENODEV` on every kernel except stock's, including the one it was
built for. The machine-compatible (`altr,socfpga-cyclone5`) and `MiSTer_fb`
`reg` checks stay, and they are what keep the module DE10-only.

This deviates from upstream's own policy, which qualifies exactly one stock
kernel build and asks that the module not be loaded on any other. The patch
keeps a fail-closed gate at the series boundary rather than dropping it:

- Vermagic already binds the `.ko` to the kernel it was compiled against, and
  Buildroot rebuilds it on every kernel bump.
- The one kernel-internal assumption the source documents is that the 6.18
  `mmap` path calls the driver before inserting the new VMA. That is mm-core
  behaviour; a longterm point release does not change it, but a series move
  could. A 7.x kernel therefore gets `-ENODEV` until this patch is revisited.
- The module is never autoloaded, so nothing loads it unless a client asks.

A 6.18 point release has not been hardware-tested with the module.

The `kernel_revision` modinfo field still names the upstream kernel commit
the source was written against; it does not describe this image's kernel.

## 4. Licence

The source is GPL-3.0-or-later (SPDX headers). The repository has no LICENSE
file, so the unpatched `zaparoo_scanout_uapi.h` stands in as the licence file.
Hash-sync refreshes only the tarball line, so a bump that edits that header
needs its hash line updated by hand (`make zaparoo-scanout-legal-info` fails
on the stale line).

Since `a1fdb653` the module declares `MODULE_LICENSE("GPL")` (it was
`"Proprietary"` before), because the vertical-sync wait needs GPL-only IRQ
exports. Loading it no longer sets the `P` taint flag; it still sets `O`
(out-of-tree). The source licence is unchanged; GPL-3.0-or-later is not
GPL-2.0-compatible, which is upstream's licensing question, not a build one.

## 5. Scope

- **DE10-Nano only.** Enabled in `configs/mister_de10nano_defconfig`, not in
  the `mister-drivers` profile ([buildroot-config.md §5.46](buildroot-config.md)).
- **Regular kernel only.** Like every out-of-tree module package here, it is
  built against `BR2_LINUX_KERNEL`, not the `linux-rt` variant, so it is
  absent when the board boots the RT kernel.
- CI asserts the `.ko.xz` is present in `rootfs.tar` (`scripts/ci-tests.sh`).
