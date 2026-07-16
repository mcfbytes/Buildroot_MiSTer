# USB mass-storage automount parity

## Summary

Stock MiSTer auto-mounts USB drives with the Debian **`usbmount`** package: a udev
`RUN+=` rule fires `/usr/share/usbmount/usbmount` on every `sd*`/`ub*` block-device
`add`/`remove`, and the script mounts the volume on the first free
`/media/usb0`…`/media/usb7` (and unmounts + tears the mountpoint down on removal).

This build ships the **same tool** — Buildroot's `usbmount` package
(`BR2_PACKAGE_USBMOUNT=y`). Buildroot packages usbmount **0.0.22**, patched to read
the filesystem type/UUID/label from **udev's `ID_FS_*` environment** instead of
shelling out to `blkid`; that makes it functionally identical to the **0.0.24**
script in the stock image (which was already patched the same way). The udev rule,
the `/media/usbN` mountpoints, and the `mount.d`/`umount.d` model-symlink hooks are
all identical.

**What works out of the box:** hotplug automount of **vfat (FAT32)**, **exFAT**, and
**ext4** — the formats MiSTer actually uses (exFAT is the recommended format for the
main storage; FAT32 for smaller drives). All three are native in-kernel filesystems
here (`CONFIG_VFAT_FS=y`, `CONFIG_EXFAT_FS=y`, ext4), so BusyBox `mount(2)` mounts
them directly with no userland helper.

**One documented gap — NTFS:** on stock, NTFS drives mount via `ntfs-3g` because
stock ships a **util-linux `mount`** binary plus a `/sbin/mount.ntfs → ntfs-3g`
helper symlink, and util-linux `mount` dispatches `mount -t ntfs` to that helper.
This build uses **BusyBox `mount`** with helper dispatch disabled
(`CONFIG_FEATURE_MOUNT_HELPERS` is not set) and ntfs-3g installs `mount.ntfs-3g`
(not the bare `mount.ntfs`). So `mount -t ntfs` here hits the `mount(2)` syscall,
which fails (kernel 6.18 dropped the legacy read-only in-kernel `ntfs`; only
`ntfs3` — a different fs name — remains, as a module). The `usbmount` script logs
the failed mount and moves on; nothing hangs, and the other filesystems are
unaffected. See **Making NTFS mount too** below for the one-time change that closes
this if a maintainer decides NTFS automount is worth it. `ntfs` and `fuseblk` are
kept in the config list anyway for stock parity (and so the `remove` path matches
an ntfs-3g `fuseblk` mount if helper support is later added).

## How it works

| Piece | Path | Source | Notes |
|-------|------|--------|-------|
| udev rule | `/lib/udev/rules.d/usbmount.rules` | usbmount pkg | `KERNEL=="sd*"`/`"ub*"`, `SUBSYSTEM=="block"`, `ACTION=="add"`/`"remove"` → `RUN+="/usr/share/usbmount/usbmount add|remove"`. Same rule as stock. |
| script | `/usr/share/usbmount/usbmount` | usbmount pkg | Reads `ID_FS_USAGE`/`ID_FS_TYPE`/`ID_FS_UUID` from the udev env, honours `/etc/fstab` first, else mounts the first free `/media/usbN`. |
| config | `/etc/usbmount/usbmount.conf` | **rootfs-overlay** (this repo) | Stock-tuned; overrides the package default — see below. |
| hooks | `/etc/usbmount/{mount,umount}.d/00_*_model_symlink` | usbmount pkg | Create/remove a vendor-model symlink under `/var/run/usbmount`. Same as stock. |
| mountpoints | `/media/usb0`…`/media/usb7` | usbmount pkg | `mkdir`'d at install. |

Runtime dependencies are all satisfied: **eudev** provides udev
(`BR2_PACKAGE_HAS_UDEV`); `usbmount` `select`s **`lockfile-progs`** (→ `liblockfile`,
already enabled) for the `lockfile-create` serialisation in the add path; and
`run-parts`, `logger`, and `expr` are BusyBox applets that are all built in.

## The config override

`usbmount`'s behaviour is driven by `/etc/usbmount/usbmount.conf`. Buildroot's
upstream 0.0.22 default is too narrow for MiSTer:

```
# upstream 0.0.22 default
FILESYSTEMS="vfat ext2 ext3 ext4 hfsplus"      # no exfat, no ntfs
FS_MOUNTOPTIONS=""
```

So this repo ships stock's tuned config at
`board/mister/de10nano/rootfs-overlay/etc/usbmount/usbmount.conf`, which reproduces
the stock image verbatim:

```
FILESYSTEMS="vfat exfat ext4 ntfs fuseblk"
MOUNTOPTIONS="sync,noexec,nodev,noatime,nodiratime"
FS_MOUNTOPTIONS="-fstype=ntfs,nls=utf8,umask=111,gid=46 -fstype=fuseblk,nls=utf8,umask=111,gid=46"
```

The rootfs overlay is copied over the target at `target-finalize`, **after** package
installation, so this file wins over the one the `usbmount` package installs. (Same
overlay-overrides-package mechanism this tree already uses for `smb.conf`, `inittab`,
etc.)

## Making NTFS mount too (optional, not done here)

Two ingredients are needed, and both are deliberately **out of scope** for this
change because they touch broader, already-settled decisions:

1. **A helper-capable `mount`.** Either enable BusyBox
   `CONFIG_FEATURE_MOUNT_HELPERS=y` in `board/mister/de10nano/busybox.fragment`
   (additive: BusyBox `mount` then execs `/sbin/mount.<type>` when such a helper
   exists, and still falls back to `mount(2)` otherwise — but it can subtly change
   `mount -t cifs`, which BusyBox currently handles with its own built-in
   `FEATURE_MOUNT_CIFS`), **or** enable `BR2_PACKAGE_UTIL_LINUX_BINARIES` to get the
   real util-linux `mount` (exactly stock — but that reverses the P2.1 decision to
   keep util-linux binaries off, and swaps `/bin/mount`, `getty`, etc.).
2. **A `mount.ntfs` helper.** ntfs-3g here installs `mount.ntfs-3g`/`mount.lowntfs-3g`
   but not the bare `mount.ntfs` stock symlinks. Add
   `ln -sf /usr/bin/ntfs-3g /sbin/mount.ntfs` via the overlay (stock ships exactly
   this symlink).

Given exFAT/FAT32 cover the real MiSTer USB use case and NTFS is a minority format,
this was left as a documented follow-up rather than reversing a deliberate
system-wide `mount` decision for it.

## Verification

- **Config resolves.** `make mister_de10nano_defconfig && make olddefconfig` (kconfig
  only, no compile) with the edited defconfig produces an `output/.config` containing
  `BR2_PACKAGE_USBMOUNT=y` **and** the auto-`select`ed `BR2_PACKAGE_LOCKFILE_PROGS=y`
  / `BR2_PACKAGE_LIBLOCKFILE=y` — i.e. the symbol is valid in Buildroot 2026.02.3, no
  dependency is silently unsatisfied, and the inline-commented defconfig still parses.
- **Source is fetchable + pinned.** `usbmount_0.0.22.tar.gz` downloads from Buildroot's
  backup mirror and matches the package's pinned
  `sha256 a2b8581534b6c92f0376d202639dbc28862d3834dac64c35bde752f84975527d`.
- **Kernel support present.** `CONFIG_VFAT_FS=y`, `CONFIG_EXFAT_FS=y`, ext4 built in;
  `CONFIG_NTFS3_FS=m` + `CONFIG_FUSE_FS=y` (for the ntfs-3g/fuseblk path once a helper
  is wired up).
- **On-hardware smoke test (pending):** plug an exFAT and a FAT32 USB stick into a
  running DE10-Nano, confirm they appear under `/media/usb0`/`/media/usb1`, and
  confirm the mountpoint is released on removal.
