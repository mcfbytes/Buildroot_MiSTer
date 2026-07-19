# The `loop=` boot mechanism on 6.18: what breaks, what it costs, and what we did instead

**Audience:** whoever maintains `MiSTer-devel/Linux-Kernel_MiSTer`. This is the companion
to the `loop=` patch carried in
[`board/mister/de10nano/linux-patches-upstream/0100-init-support-for-init-loop-device.patch`](../board/mister/de10nano/linux-patches-upstream/0100-init-support-for-init-loop-device.patch),
which is included in the exported 6.18 tree.

**Short version.** Fork commit
[`3d95de58f`](https://github.com/MiSTer-devel/Linux-Kernel_MiSTer/commit/3d95de58f0334ffba30f7b81d88fbf5f2378f255)
("Support for init loop device.") does not apply to 6.18, and not because of context drift —
`patch` fuzz would not save it. Both halves of the code it hooks into were rewritten, and
three of the primitives it is built on no longer exist. Making it work again is a real
forward-port, not a re-anchor. We did that work and it is in the exported tree. Separately,
this Buildroot build does not use it: we boot the same card layout from a stock kernel with
no patch at all, via an initramfs. Both facts are useful to you, for different reasons.

---

## 1. Why `3d95de58f` cannot be applied to 6.18

Five independent reasons. Any one of them alone would require code changes.

### 1.1 `sys_ioctl()` and `sys_close()` are gone from init code

The patch's `loop_setup()` is built on them:

```c
if(sys_ioctl(device_fd, LOOP_SET_FD, (long)file_fd) < 0) { ... }
sys_close(file_fd);
```

Init-time work now goes through explicit helpers in `fs/init.c`, declared in
`<linux/init_syscalls.h>`: `init_mount()`, `init_mkdir()`, `init_umount()`, and friends.

**There is no `init_ioctl()`, and there cannot be a generic one** — an ioctl is
driver-defined, so there is nothing to wrap. Nor is there a back door: `vfs_ioctl()` is
static to `fs/ioctl.c`, and `do_vfs_ioctl()` carries a comment there saying it is *"not for
drivers and not intended to be `EXPORT_SYMBOL()`'d"*. `blkdev_ioctl()` is declared only in
`block/blk.h`, which is block-internal. `lo_ioctl()` is `static`.

So `LOOP_SET_FD` cannot be issued from `init/` at all on 6.18 without new plumbing.

### 1.2 `init/do_mounts.c` was refactored out from under the hook

The `#ifdef CONFIG_BLOCK` block inside `mount_root()` that the patch edits is now the body
of a separate `mount_block_root(char *root_device_name)`, and `mount_root()` has become a
`switch` over `ROOT_DEV` that dispatches to it. 5.15's `mount_block_root(name, flags)` — the
"mount this device as root, trying each filesystem" primitive — is 6.18's
`mount_root_generic(name, pretty_name, flags)`. The patch calls the old one twice.

Also, `root_device_name` is no longer a file-global; it is a parameter threaded down from
`prepare_namespace()`.

### 1.3 A silent behaviour change hiding inside that refactor

5.15's `prepare_namespace()` advanced `root_device_name` past its `/dev/` prefix before use.
**6.18's does not**, and no equivalent adjustment exists anywhere in the file (`grep -rn
'root_device_name += 5' init/` returns nothing). So the name now arrives fully qualified,
and the patch's bind-mount failure message — which prefixes a literal `/dev/` — would print

```
Failed to bind-mount /dev//dev/mmcblk0p1 to /root/media/fat : -2
```

on the real MiSTer command line. Cosmetic, but it is the kind of thing that survives a
"clean" apply and then confuses whoever hits the error path years later.

### 1.4 `-Wmissing-prototypes` is now global, and there is nowhere to put the prototype

Since `0fcb70851fbf` ("Makefile.extrawarn: turn on missing-prototypes globally") the
exported functions need a visible prototype or they warn. 6.18 has nowhere to put one:
there is no `include/linux/loop.h`, and no `drivers/block/loop.h` either — the driver's
private header was folded into `loop.c`, which reaches straight for `<uapi/linux/loop.h>`.

This matters more than it looks. The 5.15 patch got `LOOP_SET_FD` into `init/do_mounts.c`
via `#include <linux/loop.h>` *resolving to the UAPI header*. Any new `include/linux/loop.h`
shadows that on the include path (`LINUXINCLUDE` searches `include/` before `include/uapi/`),
so it has to re-include the UAPI header or the ioctl definitions silently disappear.

### 1.5 Two latent bugs in the original that 6.18 turns into hard failures

Worth fixing regardless of version, but 6.18 forces the issue:

- **Stack buffer overflow.** `sprintf(lname, "/root2/%s", loop_name)` into `char lname[32]`
  overflows for any `loop=` argument longer than 24 characters. That is reachable from the
  boot command line, bounded only by `COMMAND_LINE_SIZE`.
- **`CONFIG_BLK_DEV_LOOP=m` does not link.** `loop_max_part()` would live in a module that
  cannot possibly be loaded before the root filesystem is mounted, while
  `init/do_mounts.c` is always built in. The 5.15 patch links only because MiSTer's own
  config happens to set `=y`; `allmodconfig` would fail.

---

## 2. What in-kernel parity on 6.18 actually costs

This is what the carried patch does. It is offered as a starting point, not as something
you have to accept — if you would rather solve it differently, §1 is the part that matters
and this section is one worked answer.

| # | Change | Why |
|---|---|---|
| 1 | Export `loop_set_backing_fd()` from `drivers/block/loop.c` | The ioctl cannot be issued from `init/` (§1.1). The body is exactly `lo_ioctl()`'s `LOOP_SET_FD` case: a zeroed `struct loop_config` carrying only the backing descriptor, `BLK_OPEN_READ\|BLK_OPEN_WRITE` for the mode. Not passing `BLK_OPEN_EXCL` keeps `loop_configure()` on its `bd_prepare_to_claim()` path, so claim semantics match the userspace route. |
| 2 | Keep the descriptor half in `init/` | `loop_configure()` `fget()`s `config.fd`, and there is no way around that short of splitting `loop_configure()`. 5.15's `m_open()` is kept in substance — `get_unused_fd_flags()` + `fd_install()` — with its reference leak on the allocation-failure path fixed. |
| 3 | Restore `include/linux/loop.h` | Two declarations, re-including `<uapi/linux/loop.h>` so it is a strict superset of the header it now shadows (§1.4). |
| 4 | Move the hook into `mount_block_root()`, translate to `mount_root_generic()` | Same code at the same point in the boot (§1.2). Drop the literal `/dev/` from the failure message (§1.3). |
| 5 | Split the `loop=` body into `mount_loop_root()`, with an `IS_BUILTIN()` stub | So it compiles out under `CONFIG_BLK_DEV_LOOP=m` (§1.5). The stub panics with the reason rather than silently falling back to mounting `root=` — which would try to boot the exFAT data partition as root. |
| 6 | `sprintf` → `kasprintf` | Fixes the overflow (§1.5); slab is up long before `prepare_namespace()`. |
| 7 | Return real errnos, drop the post-failure `LOOP_CLR_FD` | `loop_configure()` unwinds its own partial state and leaves `lo_state == Lo_unbound`, so there is nothing to clear. |

**One thing that did *not* need changing**, checked rather than assumed: `/dev/loop8`'s minor
is still `(max_part + 1) * 8`, because `loop_add()` still assigns
`disk->first_minor = i << part_shift` with `part_shift` derived from `max_part`. Your
`loop_max_part()` export carries over verbatim.

### The dependency worth knowing about

`/dev/loop8` is one past `CONFIG_BLK_DEV_LOOP_MIN_COUNT`'s default of 8 devices, so the
driver has not created it. The `filp_open()` of the node is what brings it into existence:
`blkdev_get_no_open()` finds no inode, calls `blk_request_module()`, and that reaches
`loop_probe()`.

**In 6.18 that fallthrough is conditional on `CONFIG_BLOCK_LEGACY_AUTOLOAD`**, whose help
text calls it a historic feature and which `pr_warn_ratelimited()`s that it *"will be
removed"*. It is `default y`, so the boot works today. When that symbol goes, `loop=` stops
working, and it would surface as an unexplained `-ENXIO`. The carried patch names the symbol
in its open-failure path so that day produces an actionable message rather than a puzzle.

If you want to be ahead of it, raising `CONFIG_BLK_DEV_LOOP_MIN_COUNT` to 9 (or pointing
`loop=` at a lower-numbered device) removes the dependency entirely.

### Honest status of the carried patch

**Compile-tested only. It has never been booted.** A full `ARCH=arm` vmlinux links
warning-free with MiSTer's board config and carries `__ksymtab` entries for both new
symbols; `init/do_mounts.o` and `drivers/block/loop.o` also build warning-free under
`CONFIG_BLK_DEV_LOOP=m`. That is the ceiling of what this repo can prove, because the image
we build deliberately does not apply the patch — there is nothing here that exercises the
code at runtime.

That limitation is not theoretical. An earlier revision of this port was built on
`fs/init.c`'s `init_dup()`, which *looks* like the sanctioned helper and is not: despite the
name it does not return a descriptor. It allocates one, `fd_install()`s a reference of its
own, and returns `0`. It exists for `console_on_rootfs()`, whose callers only check for
failure. That version compiled cleanly and would have bound **fd 0** — which at that point
in the boot is `/dev/console`, since `console_on_rootfs()` runs in `kernel_init_freeable()`
before `prepare_namespace()`. `loop_configure()` would have `fget()`ed the console,
`loop_validate_file()` would have rejected the character device with `-EINVAL`, loop8 would
have stayed unbound, and mounting it as root would have panicked **on every boot**. It was
caught by review, not by the compiler.

So: please boot it before trusting it.

---

## 3. What we did instead, and why

Buildroot_MiSTer boots the identical card layout on a **stock kernel with no patch**, using
an initramfs. Recorded in
[`docs/decisions/0002-initramfs.md`](decisions/0002-initramfs.md); the disposition of your
commit is tracked as `carried-upstream-only` in
[`docs/kernel-recon/reconciliation.md`](kernel-recon/reconciliation.md) — carried for the
exported tree, deliberately not applied to our image. It is explicitly *not* a drop.

**We do not touch U-Boot.** `uboot.img` ships byte-identical, so the command line is
unchanged, `loop=linux/linux.img` and all:

```
console=ttyS0,115200 loglevel=4 loop.max_part=8 mem=511M memmap=513M$511M \
    root=/dev/mmcblk0p1 loop=linux/linux.img ro rootwait
```

The only thing that changes is **who consumes `loop=`**. A stock kernel parses it via
`__setup("loop=", ...)`. Ours never registers that handler, so the token reaches userspace
untouched on `/proc/cmdline`, and our `/init` parses it itself.

### The mapping, mechanism by mechanism

| Your kernel does | We do, with stock functionality |
|---|---|
| Mount `root=` as exFAT on `/root2` | `mount -t exfat` (mainline driver), falling back to `mount -t vfat` |
| `create_dev("/dev/loop8")` + `LOOP_SET_FD` open-coded | BusyBox `losetup -f` then `losetup <dev> <img>` — real userspace `losetup(8)`, never a hardcoded loop8 |
| `mount_block_root("/dev/loop8", flags)` | `mount -t ext4 <loopdev> /newroot`, autodetect fallback |
| `init_mount("/root2", "/root/media/fat", MS_BIND)` | `mount -o move /mnt/fat /newroot/media/fat` |
| `root_mountflags \|= MS_NOATIME\|MS_NODIRATIME` globally | the same flags as explicit `-o` mount options, on the mounts that want them |

Then `exec switch_root /newroot /sbin/init`.

### What it costs

- **+1.6% zImage.** The cpio is 258,560 bytes uncompressed, 133,586 gzipped into the image.
  Against U-Boot's 16 MiB load budget that leaves ~8.05 MiB of headroom. (`mem=511M` is
  irrelevant here — it constrains the FPGA mailbox, not this.)
- **An extra boot stage.** Predicted at a few hundred milliseconds. **Unmeasured.**
- **`root=PARTUUID=` regression.** BusyBox `findfs` handles `UUID=`/`LABEL=` only; your
  `name_to_dev_t()` handled `PARTUUID=`. Narrow, but real.
- **Bounded `rootwait`.** Yours is infinite; ours defaults to 30s and then drops to a rescue
  shell. More debuggable, but it is a behaviour change.

### What it buys

- **No `init/do_mounts.c` patch to forward-port.** §1 is the argument for this: that file
  gets rewritten, and every rewrite is a re-port on a boot-critical path.
- **Testable without hardware.** `scripts/test-initramfs.sh` boots the real cpio under QEMU
  across seven cases (fat32, exfat, symlinks, `LABEL=`, non-ASCII filenames, missing image,
  `rootwait` timeout) and asserts both successful `switch_root` *and* correct failure
  behaviour. Nothing about the in-kernel path was ever testable that way.
- **Failures are recoverable.** Every error path in the kernel version is `pr_emerg()` then
  carry on, ending in a panic. Ours prints a diagnostic banner — parsed cmdline,
  `/proc/partitions`, `/proc/filesystems`, `/proc/mounts`, last 25 dmesg lines — and drops
  to a respawning serial shell. The QEMU harness machine-checks the absence of
  `Kernel panic` in the negative cases.

### The honest caveat

**This has been verified under QEMU, not on real hardware.** As of writing, this build has
not been booted on a real DE10-Nano. Treat the comparison as "two designs, one of them
tested in an emulator", not as a recommendation from a running system.

---

## 4. What we are actually suggesting

Nothing, forcefully. Both mechanisms are in the exported tree's history and you can take
either view:

- **Keep `loop=` in-kernel.** The carried patch is a working starting point, needs a boot
  test, and §2's table is the maintenance surface you are signing up for on each rebase.
- **Move to an initramfs later.** §3 is a worked example that keeps your card layout, your
  U-Boot, and your command line exactly as they are. The cost is one extra build stage; the
  benefit is that `init/do_mounts.c` stops being your problem.

The reason the patch is in the exported tree at all is that a 6.18 branch without it would
not boot any stock MiSTer — deleting it to keep our two trees identical would have been the
wrong trade.
