# ADR 0002 — Replace the `loop=` kernel patch with an embedded initramfs

**Status:** Proposed (2026-07-12) — derived during P1.10 implementation; **not yet
reviewed by a human, and not yet booted on hardware.** It *has* been booted under QEMU
(§8), on both FAT32 and exFAT, including the failure paths. Every claim below is marked
with how it was established. The ones still marked *unverified* are the ones that can
brick a board, and they are listed together in §8 so P1.13 can be pointed straight at
them.
**Implements:** TASKS.md **P1.10**; constraints **A1**, **A2**, **A13**, **A15**;
PLAN.md **§5**; `docs/boot-chain.md` §8 (I1–I3, L1–L2) and §9.
**Depends on:** **ADR 0010** (drop the out-of-tree exfat driver) — that decision is
what makes the vfat fallback a *boot* requirement rather than a nicety.
**Impact:** `configs/mister_initramfs_defconfig`,
`board/mister/de10nano/initramfs-overlay/init`,
`board/mister/de10nano/initramfs-busybox.config`, `external.mk`, top-level `Makefile`.
Creates a requirement on **P2.3** (§7) and on **P1.3** (§3).

---

## 1. Decision

Delete the stock kernel's `loop=` patch to `init/do_mounts.c` and do its job from a
**~370 KB initramfs embedded in the zImage**, built by a **second, minimal Buildroot
configuration** (static musl BusyBox → `BR2_TARGET_ROOTFS_CPIO`) that the main build's
kernel consumes through `CONFIG_INITRAMFS_SOURCE`.

## 2. Why — this is the single biggest maintenance-burden reduction in the plan

What we are deleting is not a driver in a quiet corner. It is a patch to
`init/do_mounts.c`, a core file upstream has since rewritten, in a fork that has **zero
upstream ancestry** (P0.4). Carrying it to 6.18 and then to every 6.18.y point release
until Dec 2028 is exactly the open-ended cost PLAN §13 identifies as how this project
dies. The stock hunk (fork `init/do_mounts.c:655-685`) is:

```c
err = init_mount("/dev/root", "/root2", "exfat",
                 MS_DIRSYNC | MS_SYNCHRONOUS | MS_NOATIME | MS_NODIRATIME, "");
err = create_dev("/dev/loop8", MKDEV(7, (loop_max_part()+1)*8));
sprintf(lname, "/root2/%s", loop_name);
err = loop_setup(lname, "/dev/loop8");
mount_block_root("/dev/loop8", root_mountflags);
err = init_mount("/root2", "/root/media/fat", "", MS_BIND, "");
```

Six lines of kernel that are, in userspace, six lines of shell. Moving them out also
makes the boot path **testable without hardware** (P1.12 boots the same cpio on a
generic QEMU ARM machine), which nothing about the kernel patch ever was.

## 3. Build mechanics — and the two ways to get them wrong

**Two Buildroot configs, two output directories, one cpio.**

| | main | stage 1 |
|---|---|---|
| defconfig | `mister_de10nano_defconfig` | `mister_initramfs_defconfig` |
| output | `output/` | `output-initramfs/` |
| libc | glibc, shared (ADR 0001 — the stock `MiSTer` binary needs it) | **musl, `BR2_STATIC_LIBS`** |
| init | BusyBox init + S-scripts (P2.3) | **none** — the kernel execs our `/init` |
| product | `linux.img`, `zImage_dtb` | `images/rootfs.cpio` |

The two rootfses have *opposite* requirements, which is why this is a whole second
config rather than a flag. Nothing in the initramfs is an ABI surface: it runs BusyBox,
calls `mount(2)`, and is erased from RAM by `switch_root` before `/sbin/init` starts.
It never meets Main_MiSTer. So it is free to be musl and static, and it should be —
`BR2_STATIC_LIBS` is not even *offered* with glibc (`Config.in:684`).

**Trap 1 — `BR2_TARGET_ROOTFS_INITRAMFS` (A1).** The option that sounds like what we
want embeds the *entire ~300 MB target rootfs* into the kernel image. Never set it.

**Trap 2 — the kernel has no initramfs slot at all unless P1.3 says so (A11).** Stock
ships `# CONFIG_BLK_DEV_INITRD is not set`, and `CONFIG_INITRAMFS_SOURCE` *depends on
it*, so a faithful `olddefconfig` port of the stock config silently deletes the entire
mechanism. `external.mk` force-enables `CONFIG_BLK_DEV_INITRD` for this reason even
though `board/mister/de10nano/linux.config` already has it — belt and braces on the
one failure that produces a kernel that boots and then panics on a FAT root.

### 3.1 Where the path is injected, and why not in the defconfig

`external.mk` appends to `LINUX_KCONFIG_FIXUP_CMDS` — the same mechanism Buildroot
itself uses for `BR2_TARGET_ROOTFS_INITRAMFS` (`linux/linux.mk:412-419`), just pointed
at a different, much smaller cpio.

The obvious alternative — `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` in the main
defconfig — was **rejected**: `package/pkg-kconfig.mk:19-20` makes
`make linux-update-defconfig` and `make linux-savedefconfig` **hard-fail** ("Unable to
perform when fragment files are set") the moment any fragment is configured, and those
are exactly the commands P1.3 uses to regenerate `linux.config`. It would also bake an
absolute build path into a committed defconfig.

Ordering is safe by inspection: Buildroot's `Makefile` includes `linux/linux.mk` at
line 553 and `$(BR2_EXTERNAL_MKS)` at line 564, and `LINUX_KCONFIG_FIXUP_CMDS` is
expanded lazily inside the `.stamp_kconfig_fixup_done` recipe. The append uses
Buildroot's `$(sep)` (a newline, `support/misc/utils.mk:103`) — a bare `+=` would
splice our first command onto the tail of linux.mk's last one.

### 3.2 Compression: uncompressed cpio, gzipped by the kernel

Stage 1 emits an **uncompressed** `.cpio` (`BR2_TARGET_ROOTFS_CPIO_NONE`, the default)
and `external.mk` sets `CONFIG_INITRAMFS_COMPRESSION_GZIP=y` + `CONFIG_RD_GZIP=y`.
Compressing it in stage 1 as well would compress it twice.

Setting the compression *explicitly* is deliberate: the `choice` in the kernel's
`usr/Kconfig` carries **no `default`**, so it silently resolves to whichever entry is
listed first upstream. That happens to be GZIP today. "Whatever upstream lists first"
is not something a boot path should depend on.

### 3.3 Sequencing

The top-level `Makefile` makes `initramfs` a hard prerequisite of `all`, and
`external.mk` **refuses to configure the kernel** if the cpio is not on disk (with a
message telling you to run `make initramfs`). `make check-initramfs` — run
automatically at the end of `make all` — asserts I1 and I2 against the *built* kernel
`.config`, because the failure it guards against is not loud: a kernel with
`CONFIG_INITRAMFS_SOURCE=""` boots fine, unpacks the kernel's own `default_cpio_list`,
finds no `/init`, falls through to `prepare_namespace()`, tries to mount
`root=/dev/mmcblk0p1` (a *FAT* partition) as a root filesystem, and panics — pointing
at the disk, not at the build.

## 4. What `/init` does

`board/mister/de10nano/initramfs-overlay/init` — 192 lines, `shellcheck`-clean under
`bash`, `sh` and `dash`.

1. `mount` `/proc`, `/sys`, **`/dev` (devtmpfs)**. Not optional: `CONFIG_DEVTMPFS_MOUNT`
   only mounts `/dev` from `prepare_namespace()`, which an initramfs boot *skips
   entirely*. Nothing below works without this.
2. Parse `/proc/cmdline` for `root=`, `loop=`, `ro`/`rw`, `rootwait[=N]`. **Never
   positionally** — `$v` (`u-boot.txt` line 1, the documented user knob) injects
   arbitrary extra tokens. Globbing is disabled first.
3. Resolve `root=`. Accepts a device path, or `UUID=`/`LABEL=` via BusyBox `findfs`
   (the kernel's `name_to_dev_t()` used to do this for us; with an initramfs the kernel
   never sees `root=` at all).
4. `rootwait` as a **retry loop**, 1 Hz, default 30 s for a bare `rootwait`.
5. Mount the data partition, **`exfat` first, then `vfat`** (§5).
6. `losetup -f` → attach `/mnt/fat/$loop=` → `mount -o ro` the loop device (§6).
7. `mount -o move /mnt/fat /newroot/media/fat` (§7).
8. `mount -o move` `/dev`, `/proc`, `/sys` into the new root (§7).
9. `exec switch_root /newroot /sbin/init`.

**On any failure: a diagnostic banner + a serial rescue shell, never a silent panic.**
The banner prints the cmdline, the parsed values, `/proc/partitions`,
`/proc/filesystems`, `/proc/mounts` and the last 25 `dmesg` lines, then respawns
`setsid cttyhack /bin/sh` forever (pid 1 exiting *is* a panic).

If `loop=` is absent, `root=` is mounted directly as the rootfs and no `/media/fat` is
created — this reproduces stock's `else` branch (`do_mounts.c:681`) rather than
inventing a new failure mode.

## 5. The mount options are an ABI surface, not taste

```
exfat: rw,sync,dirsync,noatime,nodiratime,fmask=0022,dmask=0022,errors=remount-ro
vfat : rw,sync,dirsync,noatime,nodiratime,fmask=0022,dmask=0022,errors=remount-ro,utf8=1
```

| Option | Why | Evidence |
|---|---|---|
| **exfat tried FIRST, vfat SECOND** | Mainline exfat **cannot mount FAT32**. The rootfs is a file *on this partition*, so a hardcoded `-t exfat` does not lose a feature — **it fails to boot** on any FAT32 card. Stock got away with one mount call only because its out-of-tree driver handled FAT12/16/32 too. | ADR 0010 (a) |
| `sync,dirsync` | Stock mounts `/media/fat` synchronously **from the kernel** (`MS_DIRSYNC\|MS_SYNCHRONOUS`) and `/etc/fstab` never re-mounts it. MiSTer users power the box off by pulling the plug; async here is a real corruption regression, not a tuning choice. | A13; fork `do_mounts.c:667` |
| `noatime,nodiratime` | Same kernel call: `MS_NOATIME\|MS_NODIRATIME`. Absent from PLAN §5's sketch; included here because the sketch is a sketch and the C is the contract. | fork `do_mounts.c:667` |
| `utf8=1` on vfat, and **nothing** on exfat | `Documentation/filesystems/vfat.rst:72` explicitly deprecates `iocharset=utf8`. Verified against the 6.18.38 parse tables: `fs/fat/inode.c` `vfat_param_spec[]` has **both** `fsparam_flag("utf8")` and `fsparam_bool("utf8")`, so `utf8=1` is accepted. exfat's `utf8` is `fs_param_deprecated` with a NULL type (`fs/exfat/super.c`) — passing it would be wrong; utf8 is already its default. | ADR 0010 (b) |
| `fmask=0022,dmask=0022` | Stock passes `""` and gets these from `current_umask()`. Passing them explicitly makes it deterministic instead of dependent on the shell's umask. | ADR 0010 (c) |
| `errors=remount-ro` | Both `fat_param_spec[]` and `exfat_parameters[]` accept it (`fat_param_errors[]` / `exfat_param_enums[]` both contain `remount-ro`). | ADR 0010 (c) |
| **`rw`** — the data partition is mounted **read-write** | See §6. This is not an oversight. | A15 |

## 6. `ro` belongs on the mount, never on the loop device (A15)

Two things must be simultaneously true, and they pull in opposite directions:

* the **rootfs mount** is read-only (`ro` on the cmdline; stock's `/etc/fstab` says
  `rw,noauto`, so the cmdline is the *only* source of the read-only-ness), **and**
* the **loop device** is writable — stock's `/sys/block/loop8/ro` is `0` — because
  `/etc/profile:23` runs `mount -o remount,rw /` on **every login shell**. A read-only
  loop *device* makes that remount fail, leaving a logged-in user with a permanently
  read-only rootfs, which stock is not.

So: **never `losetup -r`**, and mount the loop device `-o ro`.

This has a consequence that is easy to miss and that no amount of reading the PLAN
sketch reveals: **the data partition must therefore be mounted `rw`.** BusyBox's
`set_loop()` (`libbb/loop.c:203-210`) opens the backing file `O_RDWR`, and *silently
retries `O_RDONLY`* if that fails — and the kernel then marks the loop device
read-only. A read-only `/mnt/fat` would therefore produce a read-only loop device
through the back door, reintroducing exactly the state A15 forbids. (`/media/fat` is
read-write on stock anyway — saves, the Downloader and every core write to it.)

`losetup -f` allocates the device. **Not** a hardcoded `/dev/loop8`: loop8 is an
artifact of the deleted patch (`LOOP_MIN_COUNT=8` pre-creates loop0-7 *only*, so stock
had to `create_dev()` loop8 by hand), and nothing in the stock rootfs or Main_MiSTer
references it by name. In practice `losetup -f` returns `/dev/loop0`.

## 7. `/media/fat` exists here or nowhere

`init/do_mounts.c:677` bind-mounts the data partition to `/root/media/fat`. **Nothing
in `/etc` mounts it** — not `fstab`, not `inittab`, not Main_MiSTer (ADR 0010 (c)). It
is *entirely* a product of the patch we are deleting. If the initramfs does not
recreate it, `/media/fat` is an empty directory and `/etc/inittab`'s
`::sysinit:/media/fat/MiSTer &` fails instantly.

We use `mount -o move` rather than a bind: it leaves exactly one mount of the data
partition, and it is what hands the *same* mount (with the options above) to the new
root. **BusyBox `mount` has no `--move`** — no long options at all — so it is `-o move`.
PLAN §5's sketch says `mount --move`; that spelling would fail.

`/` is mounted read-only, so **`/init` cannot `mkdir` the mountpoint**. It checks for
`/newroot/media/fat` and drops to the rescue shell with a specific message if it is
missing.

> **Requirement on P2.3:** the rootfs image **must** contain `/media/fat` (and `/dev`,
> `/proc`, `/sys`) as empty directories. This is a new, hard requirement created by
> this ADR, and it is invisible until the box does not boot.

`/dev`, `/proc` and `/sys` are `mount -o move`d into the new root as well. `/dev` in
particular is **not optional**: stock's rootfs receives a kernel-mounted devtmpfs on
`/dev` via `prepare_namespace()`, which an initramfs boot skips, and stock's `/etc/fstab`
has **no `/dev` line at all**. Leave it behind and the new root gets an empty `/dev` —
no console, no eudev, no MiSTer. The rootfs re-mounts `/proc` (inittab) and `/sys`
(fstab) over the top; stacking is harmless.

## 8. What is verified, and what is not

**Verified by reading the source of the exact versions we ship** (6.18.38, BusyBox
1.37.0, Buildroot 2026.02.3), which is stronger than a QEMU pass but weaker than a boot:

* `utf8=1` is accepted by vfat and `errors=remount-ro` by both filesystems — parse
  tables quoted in §5.
* BusyBox `mount` understands `sync`, `dirsync`, `noatime`, `nodiratime` and `move`
  **only if `CONFIG_FEATURE_MOUNT_FLAGS=y`** (`util-linux/mount.c:2320`,
  `mount_options[]` is wrapped in `IF_FEATURE_MOUNT_FLAGS`). Without it BusyBox passes
  them to the filesystem as *data*, and vfat/exfat use the new mount API, which rejects
  unknown parameters with `EINVAL` → the data partition does not mount → the box does
  not boot. It is set in `initramfs-busybox.config`. **This is the config line most
  likely to be lost in a future BusyBox bump.**
* BusyBox `switch_root` requires `/init` to be a **regular file** and `/` to be
  ramfs/tmpfs (`util-linux/switch_root.c:240`). Buildroot's `fs/cpio/cpio.mk` installs
  its own `/init` only `if [ ! -e $(TARGET_DIR)/init ]`, so our overlay's wins — and
  the same hook is what `mknod`s `/dev/console` (c 5 1), which the kernel needs *before*
  `/init` runs or `/init` has no stdio and the rescue shell is unreachable. That hook is
  in the **non-static** device-creation branch only, which is why
  `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_DEVTMPFS` is a load-bearing line in the defconfig.
* `LINUX_KCONFIG_FIXUP_CMDS` really does receive our append: verified with
  `make printvars VARS=LINUX_KCONFIG_FIXUP_CMDS` against a config with
  `BR2_LINUX_KERNEL=y`.

**Verified by actually booting it.** A throwaway harness (`work/p1.10-qemu/run-test.sh`,
gitignored — **P1.12 should lift it**) builds a synthetic SD card (MBR; partition 1 FAT32
or exFAT; `linux/linux.img` = a 16 MiB ext4 whose `/sbin/init` asserts the invariants
from *inside* the booted system) and boots the **real stage-1 cpio**, embedded in a
generic ARM 6.18.38 kernel, on `qemu-system-arm -M virt` with the stock-shaped cmdline.
Results:

| case | result |
|---|---|
| **FAT32** card, `root=/dev/vda1 loop=linux/linux.img ro rootwait` | exfat attempted, falls back to **vfat**; `switch_root`; all 6 in-guest assertions PASS |
| **exFAT** card, same cmdline | mounts as **exfat** first try; `switch_root`; all 6 PASS |
| `root=LABEL=MISTERDATA` | resolved to `/dev/vda1` by `findfs`; boots; all 6 PASS |
| `linux.img` absent | **rescue shell**, message `loop image 'linux/linux.img' not found on /dev/vda1`. No panic. |
| `root=/dev/sdz9 rootwait=4` | retries 1 Hz for 4 s, then **rescue shell**: `root device '/dev/sdz9' did not appear after 4s`. No panic. |

The six in-guest assertions, checked by the marker init after `switch_root`: rootfs is
**ext4 and `ro`**; `/media/fat` **exists** and carries **`sync,dirsync,noatime`**;
`/media/fat` is **`rw`**; **`/sys/block/loop0/ro == 0`** (A15, checked directly rather
than through `mount`, per A15's observation trap); `/dev` is the **devtmpfs moved from
the initramfs**; `/proc` is mounted.

Separately, and worth recording because ADR 0010 predicted local testing would never
exercise it: mainline exfat **mounted read-write, and was written to**, with the exact
option string above, on this kernel — the exFAT card had to be populated from inside
QEMU (`rdinit=/bin/sh`) because mtools cannot write exFAT ("non DOS media") and we had
no root to loop-mount with.

**Embedding, measured** (real P1.3 kernel config, 6.18.38, `CONFIG_KERNEL_LZ4`):

```
stage-1 cpio (uncompressed) :   258,560 bytes
 -> gzipped by the kernel   :   133,586 bytes   (usr/initramfs_inc_data)
zImage without initramfs    : 8,593,816 bytes
zImage with initramfs       : 8,727,184 bytes   (+133,368, +1.6 %)
headroom under the 16 MiB U-Boot budget : 8,050,032 bytes
```

`zcat usr/initramfs_inc_data | cmp - output-initramfs/images/rootfs.cpio` → **identical**.
The blob linked into `vmlinux` between `__initramfs_start` and `__initramfs_size` *is*
our cpio.

*(The absolute zImage figures were taken from `board/mister/de10nano/linux.config` as it
stood mid-P1.10; P1.4-P1.9 have since added their driver symbols, so both numbers will
have moved. The **delta** — what the initramfs itself costs — does not depend on them.)*

**NOT verified — P1.13 (hardware) must check each of these:**

1. **Boot on the real Cyclone V, from U-Boot, with the real 511 MB memory map.** QEMU
   proves the *logic*; it proves nothing about `mem=511M`, the real SD stack's timing,
   or the zImage+DTB concatenation (P1.11).
2. **`/etc/profile`'s `mount -o remount,rw /` actually succeeds on a login shell.**
   This is the entire point of A15 and it cannot be observed without a real rootfs and a
   real login. ⚠ And note A15's **observation trap**: because `/etc/profile` remounts
   `/` rw on login, SSHing in to check makes `mount` report `rw` and hides the whole
   constraint. **Check `/sys/block/loopN/ro` and `dmesg`, not `mount`.**
3. **`cttyhack` gives the rescue shell a working controlling terminal on `ttyS0`.**
   Untested on the real console. If it does not, the fallback `/bin/sh` still gets
   stdio; you just lose Ctrl-C.
4. **Boot-time cost.** PLAN §5 predicts "a few hundred milliseconds". Unmeasured.
   P2.9's gate is "boot-to-menu ≤ stock" — this is where that gets spent.
5. **A real exFAT card.** The QEMU test uses an exFAT image built by `mkfs.exfat` on the
   host. The decision-maker's own card is 238.7 GB exFAT; nobody has yet mounted *that*
   with these options on 6.18.
6. **A FAT32 card.** Same. ADR 0010 notes the maintainer's card is exFAT, so **the vfat
   path will never be exercised by local testing** — which is exactly why it is written
   down, and why P1.12 tests it explicitly.

## 8a. The failure mode this task actually has: kconfig loses symbols silently

Worth its own heading, because it is the thing most likely to break this again and it is
invisible to every check except running the artifact.

The stage-1 BusyBox config is derived from `allnoconfig`, so **every** feature `/init`
needs is one we asked for by name. **kconfig does not warn about symbols it does not
recognise — `olddefconfig` simply drops them.** A misspelt `CONFIG_` name therefore
produces a BusyBox that builds cleanly, installs cleanly, yields a healthy-looking cpio,
and cannot run `/init`. Three landed here:

| what we wrote | what 1.37 calls it | how it failed |
|---|---|---|
| `CONFIG_ASH_BUILTIN_TEST` (pre-1.22 name) | `CONFIG_ASH_TEST` | ash had no `[` builtin. `/init: line 98: [: not found` — and the rescue banner it then printed *blamed the kernel command line*, which was fine. |
| `CONFIG_SH_MATH` | `CONFIG_FEATURE_SH_MATH` | ash would not **parse** `waited=$((waited + 1))`. pid 1 exited → `Kernel panic - not syncing: Attempted to kill init!` |
| `CONFIG_LFS` left off by `allnoconfig` | — | Hard build failure (`BUG_off_t_size_is_misdetected`), because Buildroot compiles BusyBox with `-D_FILE_OFFSET_BITS=64`. The only one of the three that was loud. |

`shellcheck` cannot see any of this: it checks the *language*, not the *interpreter we
ship*. So `make initramfs` now verifies the **artifact**:

* every applet `/init` invokes is present in the cpio (`INITRAMFS_REQUIRED_APPLETS`),
  plus `/init` itself and `/dev/console`;
* the cross-built BusyBox `ash` is run under `qemu-arm` with `ash -n` on the real
  `/init` — i.e. the shell we actually ship is made to parse the script we actually
  ship, at build time.

**After any BusyBox version bump, re-run `make initramfs` and believe its output, not
this file.**

## 9. Known gaps (deliberate, not oversights)

* **`root=PARTUUID=…` is not supported.** BusyBox's `resolve_mount_spec()`
  (`util-linux/volume_id/get_devname.c:306`) handles `UUID=` and `LABEL=` only. The
  kernel's own `name_to_dev_t()` did handle `PARTUUID=`, so this is a real, if narrow,
  regression for anyone who wrote one into `u-boot.txt`. Fix, if someone turns up: a
  `PARTUUID` branch reading `/sys/class/block/*/…`, or enable `blkid`.
* **`rootwait` is bounded (30 s), not infinite.** The kernel's is infinite. A bounded
  wait that ends in a rescue shell with `/proc/partitions` on screen is more debuggable
  than an unexplained hang, and it cannot brick anything — but it *is* a behaviour
  change. `rootwait=N` overrides it.
* **Symlinks on `/media/fat` are gone.** Not this ADR's doing — see ADR 0010 (d).

## 10. Alternatives rejected

| Alternative | Why not |
|---|---|
| Keep the `do_mounts.c` patch, forward-port it | The whole point. It is a patch to a core file upstream has rewritten, in a fork with no upstream ancestry, that must be re-verified on every 6.18.y bump until 2028. |
| `BR2_TARGET_ROOTFS_INITRAMFS` on the main config | Embeds the entire ~300 MB rootfs into the kernel (A1). |
| `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` | Breaks `make linux-update-defconfig`, which P1.3 needs (§3.1). |
| A separate initrd loaded by U-Boot | U-Boot passes `-` for the initrd argument of `bootz` and we are not changing U-Boot in v1 (§8/A3). The cpio must be *inside* the zImage. |
| glibc + `CONFIG_STATIC` for stage 1 | `BR2_STATIC_LIBS` is unavailable with glibc, and Buildroot would still copy the shared glibc into the cpio. musl is the mechanism Buildroot actually supports here. |
| A C `/init` | Nothing here is hot, and the failure mode we most need is *legibility on a serial console at 3am*. Shell wins. |
