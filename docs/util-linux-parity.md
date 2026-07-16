# util-linux binaries parity

## Summary

Stock MiSTer ships the **real util-linux programs** — `mount`, `umount`, `blkid`,
`fdisk`, `dmesg`, `agetty`, `hwclock`, `lsblk`, `findmnt`, and ~70 others — as
util-linux **2.36.2** ELF binaries (verified by the embedded `util-linux 2.36.2`
version string in `work/imgroot/{bin,sbin,usr/bin,usr/sbin}`). It is **not** a
BusyBox-minimal userland: stock has ~984 real ELF binaries against ~222 BusyBox
applet symlinks.

Earlier phases of this project used BusyBox applets for these tools and shipped only
the util-linux *libraries* (`libblkid`/`libmount`/`libuuid`/`libsmartcols`/`libfdisk`,
for SONAME parity). The P2.1 defconfig note justified that with *"stock's
mount/fdisk/dmesg etc. are covered by BusyBox"* — which was **wrong about what stock
shipped**: stock's `mount` is util-linux, not BusyBox.

This change makes the image ship the util-linux programs stock shipped (util-linux
**2.41.4** here — same tools, newer version). The trigger was **USB automount**: NTFS
drives only auto-mount if `mount -t ntfs` can dispatch to the `ntfs-3g` helper, and
**only util-linux `mount` does that** — BusyBox `mount` has no `/sbin/mount.<type>`
helper dispatch (`CONFIG_FEATURE_MOUNT_HELPERS` was off). See
[docs/usb-automount-parity.md](usb-automount-parity.md).

Image size is not a constraint: the image is 512 MiB with ~310 MiB free
(`docs/size-budget.md`), and the util-linux *libraries* these programs link against
are already built and shipped — so the programs add only their own small binaries,
no new libraries.

## What is enabled

In `configs/mister_de10nano_defconfig`, next to the existing util-linux library
selections:

| Symbol | Programs |
|--------|----------|
| `BR2_PACKAGE_UTIL_LINUX_BINARIES` | basic set: `blkid`, `blockdev`, `blkdiscard`, `chcpu`, `choom`, `col*`, `column`, `ctrlaltdel`, `dmesg`, `fdisk`/`sfdisk`/`cfdisk`, `fincore`, `findfs`, `findmnt`, `flock`, `fsfreeze`, `fstrim`, `getopt`, `hexdump`, `ipcmk`, `isosize`, `ldattach`, `look`, `lsblk`, `lscpu`, `lsipc`, `lslocks`, `lsns`, `mcookie`, `mkfs`, `mkswap`, `namei`, `prlimit`, `readprofile`, `renice`, `rev`, `rtcwake`, `script*`, `setarch` (+`linux32`/`linux64`/`uname26`), `setsid`, `swaplabel`, `swapon`/`swapoff`, `uuidgen`, `uuidparse`, `whereis`, `wipefs` |
| `BR2_PACKAGE_UTIL_LINUX_MOUNT` | `mount`, `umount` — the functional core (helper dispatch to `mount.ntfs`) |
| `BR2_PACKAGE_UTIL_LINUX_MOUNTPOINT` | `mountpoint` |
| `BR2_PACKAGE_UTIL_LINUX_AGETTY` | `agetty` — the serial console (see below) |
| `BR2_PACKAGE_UTIL_LINUX_HWCLOCK` | `hwclock` |
| `BR2_PACKAGE_UTIL_LINUX_FSCK` | `fsck` |
| `BR2_PACKAGE_UTIL_LINUX_PARTX` | `addpart`, `delpart`, `partx`, `resizepart` |
| `BR2_PACKAGE_UTIL_LINUX_SCHEDUTILS` | `chrt`, `ionice`, `taskset` |
| `BR2_PACKAGE_UTIL_LINUX_IRQTOP` | `irqtop`, `lsirq` |
| `BR2_PACKAGE_UTIL_LINUX_KILL` | `kill` |
| `BR2_PACKAGE_UTIL_LINUX_MORE` | `more` |
| `BR2_PACKAGE_UTIL_LINUX_NEWGRP` | `newgrp` |
| `BR2_PACKAGE_UTIL_LINUX_NOLOGIN` | `nologin` |
| `BR2_PACKAGE_UTIL_LINUX_RENAME` | `rename` |
| `BR2_PACKAGE_UTIL_LINUX_SETTERM` | `setterm` |
| `BR2_PACKAGE_UTIL_LINUX_SWITCH_ROOT` | `switch_root` |

This reproduces stock's util-linux program set. `login`, `su`, and `sulogin` are
**not** enabled from util-linux — stock's `login` is a BusyBox symlink
(`bin/login -> ../bin/busybox`), so those stay BusyBox here too.

## BusyBox de-confliction

When two packages install a program at the same path, the last install wins
non-deterministically. So — the same idiom this tree already uses for `ifup`/`ifdown`
— every BusyBox applet that util-linux now provides is turned **off** in
`board/mister/de10nano/busybox.fragment`, so the util-linux binary is the one that
lands:

```
# CONFIG_BLKID / DMESG / FDISK / FLOCK / FSFREEZE / FSTRIM / GETOPT / GETTY /
# HEXDUMP / HWCLOCK / KILL / MKSWAP / MORE / MOUNT / MOUNTPOINT / NOLOGIN /
# READPROFILE / RENICE / SETARCH / SETSID / SWAPON / SWAPOFF / SWITCH_ROOT /
# UMOUNT / CHRT  ... is not set
```

**Collision audit.** The disable list was derived by intersecting the BusyBox applets
actually installed in the built rootfs with the full set of programs util-linux
installs (basic set + the enabled toggles). Every disabled applet has a confirmed
util-linux replacement; applets with **no** util-linux equivalent are left ON. Two
that look like they might collide but do **not**:

- **`setpriv`** — BusyBox provides it; util-linux would only install it under
  `BR2_PACKAGE_UTIL_LINUX_SETPRIV`, which is **not** enabled — so no collision, and
  `setpriv` stays BusyBox.
- **`setsid`** — this one *does* collide (util-linux ships it in the basic set), so
  BusyBox `SETSID` is disabled. (The initramfs `/init` also uses `setsid`, but that is
  the **separate** stage-1 BusyBox — `board/mister/de10nano/initramfs-busybox.config`
  — and is untouched by this fragment.)

## The serial console: BusyBox `getty` → util-linux `agetty`

Stock's inittab runs `agetty --nohostname`. With `agetty` now available, the inittab
serial line changes from BusyBox `getty` to match:

```
# was:  ttyS0::respawn:/sbin/getty  -L ttyS0 115200 vt100
# now:  ttyS0::respawn:/sbin/agetty --nohostname -L ttyS0 115200 vt100
```

It still targets `ttyS0` explicitly (not stock's `console` alias) because this board's
cmdline is `console=ttyS0,115200`. `agetty` treats the numeric positional argument as
the baud rate, so `ttyS0 115200` and `115200 ttyS0` are equivalent. `agetty` execs
`/bin/login` (BusyBox login, as on stock) after the prompt. See
[docs/init-parity.md](init-parity.md) deviation (2).

> ⚠️ This changes the serial console that the field-hang diagnostics rely on. `agetty`
> is the stock configuration and is well-tested, but the console line is the thing to
> watch on the first hardware boot after this change.

## `hwclock`

`hwclock` moves from BusyBox to util-linux (`BR2_PACKAGE_UTIL_LINUX_HWCLOCK=y`,
BusyBox `CONFIG_HWCLOCK` off), matching stock. This is implementation-only: as
[docs/rtc-parity.md](rtc-parity.md) documents, `hwclock` is **not** wired into boot
(no `S05rtc`; the kernel's `RTC_HCTOSYS` sets the clock), so this only changes the
binary used for manual/debug `hwclock` calls.

## Deliberate divergences

- **`raw`** — stock shipped `/sbin/raw`, but util-linux's `raw` option
  `depends on !BR2_TOOLCHAIN_HEADERS_AT_LEAST_5_14`, and our 6.18 headers are ≥ 5.14
  (the `raw(8)` char-device interface was removed from the kernel in 5.14). It is
  unbuildable and obsolete; there is no BusyBox `raw` either, so nothing is lost.
- **`login`/`su`/`sulogin`** — stock's are BusyBox; kept BusyBox here.

## Verification

- **kconfig resolves cleanly.** `make mister_de10nano_defconfig && make olddefconfig`
  (no compile) lands all 16 enabled util-linux program toggles in `output/.config`
  with nothing silently dropped; the 25 BusyBox `# CONFIG_… is not set` fragment lines
  all target symbols confirmed present in the built BusyBox `.config` (so none is a
  silent no-op).
- **Collision audit** performed as above — every disabled BusyBox applet has a
  util-linux replacement; no un-handled collision remains.
- **Full image build + on-hardware boot (pending CI / hardware):** confirm
  `/usr/bin/mount` and friends are the util-linux ELF binaries (not BusyBox symlinks),
  that the serial console still gives a login prompt via `agetty`, and that an NTFS USB
  stick auto-mounts under `/media/usbN`.
