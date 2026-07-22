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

**All of stock's filesystems automount**, matching stock:

- **vfat (FAT32)**, **exFAT**, **ext4** — native in-kernel filesystems here
  (`CONFIG_VFAT_FS=y`, `CONFIG_EXFAT_FS=y`, ext4), mounted directly via `mount(2)`.
  These are the formats MiSTer actually uses (exFAT is recommended for the main
  storage; FAT32 for smaller drives).
- **NTFS** (`fuseblk`, via `ntfs-3g`) — this works because the image now ships the
  **util-linux `mount`** (not BusyBox `mount`) plus a `/sbin/mount.ntfs → ntfs-3g`
  helper symlink, exactly like stock: util-linux `mount` dispatches `mount -t ntfs`
  to `/sbin/mount.ntfs`, which mounts the volume as `fuseblk`. Adopting util-linux
  `mount` was the reason for the broader util-linux switch documented in
  **[docs/util-linux-parity.md](util-linux-parity.md)** (stock shipped util-linux
  binaries, not BusyBox, for `mount`/`umount`/`blkid`/… — so we do too). BusyBox
  `mount` could not do this: it has no `/sbin/mount.<type>` helper dispatch
  (`CONFIG_FEATURE_MOUNT_HELPERS` was off), and kernel 6.18 dropped the legacy
  in-kernel `ntfs` filesystem (only `ntfs3`, a different name, remains). `fuseblk`
  is in the config list so the `remove` path also matches the ntfs-3g mount that
  shows up as type `fuseblk` in `/proc/mounts`.

## How it works

| Piece | Path | Source | Notes |
|-------|------|--------|-------|
| udev rule | `/lib/udev/rules.d/usbmount.rules` | usbmount pkg | `KERNEL=="sd*"`/`"ub*"`, `SUBSYSTEM=="block"`, `ACTION=="add"`/`"remove"` → `RUN+="/usr/share/usbmount/usbmount add\|remove"`. Same rule as stock. |
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

## How NTFS mounts (the `mount.ntfs` helper)

`usbmount` runs `mount -t "$ID_FS_TYPE" …`; for an NTFS volume udev reports
`ID_FS_TYPE=ntfs`, so it runs `mount -t ntfs`. The util-linux `mount` resolves
`-t ntfs` by exec'ing `/sbin/mount.ntfs`. ntfs-3g installs `mount.ntfs-3g` and
`mount.lowntfs-3g` but **not** the bare `mount.ntfs`, so this repo adds it via the
overlay (stock ships exactly this symlink):

```
board/mister/de10nano/rootfs-overlay/usr/sbin/mount.ntfs -> /usr/bin/ntfs-3g
```

(It lives under `usr/sbin` because this rootfs is merged-`/usr`, so `/sbin` is a
symlink to `/usr/sbin`; `/sbin/mount.ntfs` resolves there.) The `ntfs`/`fuseblk`
mount options in `usbmount.conf` (`nls=utf8,umask=111,gid=46`) are stock's verbatim
and are passed straight to ntfs-3g, same as on stock.

## Verification

- **Config resolves.** `make mister_de10nano_defconfig && make olddefconfig` (kconfig
  only, no compile) produces an `output/.config` with `BR2_PACKAGE_USBMOUNT=y` + the
  auto-`select`ed `BR2_PACKAGE_LOCKFILE_PROGS=y`/`BR2_PACKAGE_LIBLOCKFILE=y`, and all
  the util-linux program toggles (`…_MOUNT`, `…_BINARIES`, `…_AGETTY`, …) — i.e. the
  symbols are valid in Buildroot 2026.02.3, nothing is silently dropped, and the
  inline-commented defconfig still parses.
- **Source is fetchable + pinned.** `usbmount_0.0.22.tar.gz` downloads from Buildroot's
  backup mirror and matches the package's pinned
  `sha256 a2b8581534b6c92f0376d202639dbc28862d3834dac64c35bde752f84975527d`.
- **Kernel support present.** `CONFIG_VFAT_FS=y`, `CONFIG_EXFAT_FS=y`, ext4 built in;
  `CONFIG_NTFS3_FS=m` + `CONFIG_FUSE_FS=y` back the ntfs-3g/`fuseblk` path.
- **The util-linux `mount` swap** (which makes the NTFS helper dispatch work, and is
  itself stock parity) is covered in **[docs/util-linux-parity.md](util-linux-parity.md)**,
  including the BusyBox-applet de-confliction and the collision audit.
- **On-hardware smoke test (pending):** plug exFAT, FAT32, and NTFS USB sticks into a
  running DE10-Nano, confirm they appear under `/media/usb0…` and that the mountpoint
  is released on removal.
