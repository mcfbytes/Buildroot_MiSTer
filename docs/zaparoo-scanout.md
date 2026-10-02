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
layout struct (ABI v1); the header is `kernel/scanout-slots/zaparoo_scanout_uapi.h`
in the source tree. The module sends no FPGA commands and owns no DMA or IRQ.

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

`0001-zaparoo_scanout-drop-the-hard-coded-kernel-release-check.patch` removes
`validate_platform()`'s comparison of `utsname()->release` against the literal
`"6.18.38-MiSTer"`. Without it the module returns `-ENODEV` on every other
kernel, including the one it was built for. Vermagic already binds the `.ko`
to its kernel. The machine-compatible (`altr,socfpga-cyclone5`) and
`MiSTer_fb` `reg` checks stay, and they are what keep the module DE10-only.

The `kernel_revision` modinfo field still names the upstream kernel commit
the source was written against; it does not describe this image's kernel.

## 4. Licence

The source is GPL-3.0-or-later (SPDX headers). The repository has no LICENSE
file, so the unpatched `zaparoo_scanout_uapi.h` stands in as the licence file.
Hash-sync refreshes only the tarball line, so a bump that edits that header
needs its hash line updated by hand (`make zaparoo-scanout-legal-info` fails
on the stale line).

The module declares `MODULE_LICENSE("Proprietary")`, so loading it sets the
kernel's `P` taint flag and the module can link only non-GPL-only exports.

## 5. Scope

- **DE10-Nano only.** Enabled in `configs/mister_de10nano_defconfig`, not in
  the `mister-drivers` profile ([buildroot-config.md §5.46](buildroot-config.md)).
- **Regular kernel only.** Like every out-of-tree module package here, it is
  built against `BR2_LINUX_KERNEL`, not the `linux-rt` variant, so it is
  absent when the board boots the RT kernel.
- CI asserts the `.ko.xz` is present in `rootfs.tar` (`scripts/ci-tests.sh`).
