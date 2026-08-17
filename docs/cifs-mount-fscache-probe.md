# `cifs_mount.sh` and the `fscache.ko` that stopped existing

## Summary

`Scripts_MiSTer/cifs_mount.sh` cannot mount anything on this image. It exits with

```
The current Kernel doesn't
support CIFS (SAMBA).
Please update your
MiSTer Linux system.
```

**Nothing is missing from the image.** CIFS support is complete and working; the
script is looking for the wrong thing. Its capability probe tests for module
*filenames*, and one of the five names it requires — `fscache.ko` — ceased to
exist in Linux 6.8 and cannot be produced by any kernel we will ever ship.

Because the message names the kernel and tells you to update it, this reads as an
image defect. It is not one, and no amount of updating fixes it: a *newer* kernel
is the thing that triggers it. Any MiSTer on a kernel ≥ 6.8 hits this, not just
ours.

We ship `Scripts/mount_smb.sh` in its place.

## Root cause

`cifs_mount.sh:107` and `:795-832`:

```sh
KERNEL_MODULES="md4.ko|md5.ko|des_generic.ko|fscache.ko|cifs.ko"
...
for KERNEL_MODULE in $KERNEL_MODULES; do
	if ! cat /lib/modules/$(uname -r)/modules.builtin | grep -q "…"
	then
		if ! lsmod | grep -q "${KERNEL_MODULE%.*}"
		then
			echo "The current Kernel doesn't"
			echo "support CIFS (SAMBA)."
			…
			exit 1
```

Every name must be found, or the script gives up. Against our built tree
(`output/target/lib/modules/6.18.40/modules.builtin`):

| probed name | present? | where |
|---|---|---|
| `cifs.ko` | ✅ | `kernel/fs/smb/client/cifs.ko` |
| `md4.ko` | ✅ | `kernel/crypto/md4.ko` |
| `md5.ko` | ✅ | `kernel/crypto/md5.ko` |
| `des_generic.ko` | ✅ | `kernel/crypto/des_generic.ko` |
| **`fscache.ko`** | ❌ | **nowhere — only `kernel/fs/netfs/netfs.ko`** |

Four of five. The loop fails on the fifth and exits 1.

### Why `fscache.ko` cannot come back

**Linux 6.8** merged `fs/fscache/` into `fs/netfs/` and, in the same move,
changed `CONFIG_FSCACHE` from `tristate` to `bool`. Side by side, from upstream:

| | v6.7 | v6.8 |
|---|---|---|
| directory | `fs/fscache/` | **gone** |
| Kconfig | `config FSCACHE` / **`tristate`**, `select NETFS_SUPPORT` | `config FSCACHE` / **`bool`**, `depends on NETFS_SUPPORT` |
| Makefile | `obj-$(CONFIG_FSCACHE) := fscache.o` | `netfs-$(CONFIG_FSCACHE) += fscache_cache.o fscache_cookie.o …` |
| product | **`fscache.ko`** | objects linked into **`netfs.ko`** |

The `tristate` → `bool` change is the decisive part, and it is stronger evidence
than the missing file: **a `bool` Kconfig symbol can only ever be `y` or `n`,
never `m`.** From 6.8 onward there is no configuration of any kind — not
`=y`, not `=m`, not a custom defconfig — under which fscache is a separate
module. `modules.builtin` lists modules; fscache is no longer one.

Our own tree agrees exactly: `linux-6.18.40/fs/netfs/Kconfig:33-35` has
`config FSCACHE` / `bool` / `depends on NETFS_SUPPORT`, `fs/netfs/Makefile` has
the `netfs-$(CONFIG_FSCACHE) +=` lines, and `linux-6.18.40/fs/fscache/` does not
exist.

Verified by bisecting the release tags directly — `fs/fscache/` is present at
v6.2…**v6.7** and absent from **v6.8** onward.

### Why it works on stock

Read straight out of the extracted stock rootfs,
`work/imgroot/usr/lib/modules/5.15.1-MiSTer/modules.builtin`:

```
13:kernel/fs/netfs/netfs.ko
14:kernel/fs/fscache/fscache.ko      <- the file the probe wants
45:kernel/fs/smbfs_common/cifs_arc4.ko
46:kernel/fs/smbfs_common/cifs_md4.ko
47:kernel/fs/cifs/cifs.ko
69:kernel/crypto/md4.ko
70:kernel/crypto/md5.ko
82:kernel/crypto/des_generic.ko
```

On 5.15, `netfs.ko` and `fscache.ko` are **two separate modules**, and all five
probed names resolve — so the script runs. On 6.18 there is one module,
`netfs.ko`, and the fifth name resolves nowhere.

Worth noting what did *not* break it: `cifs.ko` also moved, `fs/cifs/` →
`fs/smb/client/`. The probe survived that because it greps for a *filename*
substring and the filename was unchanged. It dies on fscache because there the
filename itself ceased to exist.

The script is not broken *by* us; it was written against a kernel generation that
has since moved on, and we are the first MiSTer image to cross the 6.8 boundary.

### fscache was never required for CIFS anyway

Optional CIFS caching is `CONFIG_CIFS_FSCACHE`, which is **`is not set` on both
stock and ours**. The probe's list is a 2019 artifact from when the script
downloaded `.ko` files from `MiSTer-devel/CIFS_MiSTer` (that code is still in the
file, commented out, at `:805-829`). It never described what CIFS actually needs.

| symbol | stock 5.15 | ours 6.18 |
|---|---|---|
| `CONFIG_CIFS` | `=y` | `=y` |
| `CONFIG_FSCACHE` | `=y` | `=y` |
| `CONFIG_NETFS_SUPPORT` | `=y` | `=y` |
| `CONFIG_CIFS_FSCACHE` | not set | not set |

The RT kernel tree (`7.2.0-rc5`) has the identical shape and fails identically.

## Everything else the script needs is present

Checked against `output/target`, so the fscache gate is the *only* thing standing
between `cifs_mount.sh` and a working mount:

`mount.cifs` (`usr/sbin`), `nmblookup`, `nslookup`, `realpath`, `awk`, `cmp`,
`iptables`, `ip`, `ping`, `/etc/init.d/S99user`, `/etc/init.d/S49ntp`.
`cifs_umount.sh` carries no such probe and is unaffected.

## Two further defects, found while confirming the above

Both are in the boot-automount path, and both are why our replacement does not
simply copy it:

1. **The `user-startup.sh` block is not guarded on `$1`.** `S99user` calls
   `/media/fat/linux/user-startup.sh` with `start`, `stop` **and** `restart`.
   Upstream appends an unconditional line, so the mount is also kicked off
   during shutdown. (It does not make `user-startup.sh` *fail* — the command is
   backgrounded and there is no `set -e` — it just runs when it should not.)

2. **The `/etc/init.d/S99cifs_mount` fallback is pointless on this image.** A
   Linux update reflashes the whole rootfs, so any `/etc/init.d` entry is
   destroyed by the next update. Only `/media/fat` survives, which is exactly
   why `user-startup.sh` is the right hook and the fallback is not.

Note also the ordering: upstream configures boot automount **before** the
capability gate, so a user who sets `MOUNT_AT_BOOT=true` gets the boot entry
installed and *then* the failure — leaving a card that retries a doomed mount at
every boot. Ours removes that entry when it installs its own.

## What we ship instead

`board/mister/de10nano/fat-payload/Scripts/mount_smb.sh` — a clean
reimplementation, not a fork. Same job, same ini keys, ~⅓ the size.

The gate that matters:

```sh
kernel_supports_cifs() {
	grep -qE '(^|[[:space:]])cifs$' /proc/filesystems && return 0
	modprobe cifs >/dev/null 2>&1 || return 1
	grep -qE '(^|[[:space:]])cifs$' /proc/filesystems
}
```

`/proc/filesystems` lists every registered filesystem type, so this is correct
whether `cifs` is built in (our case) or a module, on any kernel version, and it
cannot go stale when the kernel reorganizes its source tree. `cifs` and `smb3`
are both registered at init — `fs/smb/client/cifsfs.c:2056-2060`.

Also dropped as dead weight: the `.ko` download block, the NetBIOS `iptables`
hole-punching (this image ships no `/etc/iptables.conf`, so `S35iptables`
installs no rules and there is nothing to punch through), the NTP-restart
workaround, and the `S99` init fallback.

Kept: `SERVER`/`SHARE`/`SHARE_DIRECTORY`/`USERNAME`/`PASSWORD`/`DOMAIN`/
`LOCAL_DIR`/`ADDITIONAL_MOUNT_OPTIONS`/`WAIT_FOR_SERVER`/`MOUNT_AT_BOOT`, the
single-connection + bind-mount mode, `LOCAL_DIR="*"`, DNS-then-NetBIOS
resolution, and boot automount. Added: `--umount`, and an ini parsed as data
rather than sourced.

**Migration costs nothing.** An existing `cifs_mount.ini` is read as a fallback,
and enabling boot automount removes any `cifs_mount` boot entry it finds, since
both would target the same mount points.

## Auto-mounting: what it takes, and why nothing else is needed

Short answer: setting `MOUNT_AT_BOOT=true` is the whole of it. The mount lands
*after* Main_MiSTer has already started, and that is fine — verified against both
ends of the mechanism rather than assumed.

**Main_MiSTer starts before the network, and before our boot entry.** From the
image's own `/etc/inittab`:

```
::sysinit:/media/fat/MiSTer &        <- backgrounded, FIRST
::sysinit:/etc/resync &
::sysinit:/etc/init.d/rcS            <- S40network … S99user, all of it, AFTER
```

So the ordering is: MiSTer → networking → `S99user` → `user-startup.sh` → our
mount. There is no arrangement of init scripts that gets a network mount up
before MiSTer, and stock has exactly the same ordering — `cifs_mount.sh`'s boot
mount ran after MiSTer too.

**That does not matter, because the lookup is live.** `findPrefixDir()`
(`Main_MiSTer/file_io.cpp:975`) calls `isPathDirectory()` on each candidate at
the moment you browse, not during a startup scan — its callers are
`findGamesDir()`/`findDocsDir()` from `menu.cpp` and `game_docs.cpp`. A share
that appears thirty seconds into the boot is picked up the first time you open a
core's folder. **No restart, no rescan, nothing to configure.**

**`LOCAL_DIR="cifs"` is not arbitrary.** That is the search order in
`file_io.cpp:975-1060`:

```
/media/usb0..5/[<prefix>/]<dir>
/media/network/[<prefix>/]<dir>
/media/fat/cifs/[<prefix>/]<dir>     <- CIFS_DIR, file_io.h:169
/media/fat/[<prefix>/]<dir>
```

`/media/fat/cifs` is checked **before** `/media/fat`, so a share mounted there
shadows the local `games/` for any system it provides and falls through to local
storage for any it does not. Keep the default unless you want the
directory-per-system layout, which is what the pipe-separated `LOCAL_DIR` form
and `LOCAL_DIR="*"` are for.

`/media/network` is a mount point Main_MiSTer also honours — and one that
**nothing in stock or in this image ever creates**. It is not a gap: `cifs` is
the conventional target and the one the community scripts use.

**Unmounting at shutdown needs no hook from us.** `/etc/inittab` ends with
`::shutdown:/bin/umount -a -r`, so init tears the mounts down. This is why the
script adds no `rcK`/`if-down.d` counterpart — there is nothing for one to do.

Two knobs worth knowing if a boot mount is flaky rather than absent, both
settable in the ini: `BOOT_START_DELAY_SECONDS` (default 8) and
`NETWORK_READY_TIMEOUT_SECONDS` (default 45, waiting for a *global-scope IPv4
address*, not merely an interface being up). A box that associates to WiFi
slowly is the usual reason to raise them.

## Verification

`scripts/test-mount-smb.sh` — 43 cases in a throwaway sandbox, no build, no
board, no network. It pins the regression directly (a sandbox with *no*
`modules.builtin` at all still mounts), the `$1` guard (by running the generated
`user-startup.sh` with `stop` and asserting nothing mounts, then with `start` and
asserting something does), ini-as-data (a password containing `$ # space "`
survives; a `PATH=` line in the ini is ignored), and the failure counter.

Wired into `scripts/ci-tests.sh`'s P3.10 section, which additionally asserts
`cifs.ko` is in `modules.builtin` for every kernel tree built, and prints a NOTE
if `fscache.ko` ever reappears — so a kernel bump that changed this assumption
would surface rather than pass silently.

The generated `user-startup.sh` block is syntax-checked under dash, bash, and the
target's own BusyBox ash via `qemu-arm` — the shell that actually runs it.

## References

- `board/mister/de10nano/fat-payload/Scripts/mount_smb.sh` — the replacement.
- `scripts/test-mount-smb.sh` — its harness.
- [`docs/netfs-parity.md`](netfs-parity.md) — the CIFS/NFS parity position.
- [`docs/user/faq.md`](user/faq.md) — the user-facing version of this.
- Upstream: <https://github.com/MiSTer-devel/Scripts_MiSTer/blob/master/cifs_mount.sh>
- `work/imgroot/usr/lib/modules/5.15.1-MiSTer/modules.builtin` — the extracted
  stock rootfs; lines 13-14 are `netfs.ko` and `fscache.ko` as separate modules.
- Linux **6.8** `fs/fscache` → `fs/netfs` merge, verified against upstream:
  [`fs/fscache/Kconfig` @ v6.7](https://raw.githubusercontent.com/torvalds/linux/v6.7/fs/fscache/Kconfig)
  (`tristate`) and
  [`fs/netfs/Kconfig` @ v6.8](https://raw.githubusercontent.com/torvalds/linux/v6.8/fs/netfs/Kconfig)
  (`bool`); `fs/fscache/` returns 404 from the GitHub contents API at v6.8 and
  200 at v6.7.
- Patch series: "netfs, fscache: Move fs/fscache/* into fs/netfs/" (David
  Howells), <https://lkml.iu.edu/hypermail/linux/kernel/2312.2/06364.html>.

## Decision audit trail

| Date | Finding | Action |
|---|---|---|
| 2026-08-17 | `cifs_mount.sh` reports "The current Kernel doesn't support CIFS" on this image; four of its five probed module names resolve, `fscache.ko` cannot | Root-caused to the Linux 6.8 `fscache`→`netfs` merge. **Not an image defect** — `CONFIG_CIFS=y`, `CONFIG_FSCACHE=y`, `mount.cifs` all present |
| 2026-08-17 | First pass recorded the merge as landing in Linux **6.3**. Wrong — corrected to **6.8** | Re-verified from primary sources rather than recollection: tag bisect of `fs/fscache/` (present v6.2-v6.7, absent v6.8+), the `tristate`→`bool` Kconfig change, and stock's own `modules.builtin`. The conclusion is unchanged and now rests on the Kconfig type, which is stronger than a file listing |
| 2026-08-17 | Fixing it in place would mean forking a 991-line actively-maintained upstream script that Update_All can overwrite | Ship `mount_smb.sh` under our own name instead, by the same one route as our other Scripts (ADR 0026) |
| 2026-08-17 | Upstream's boot entry is unguarded on `$1` and its `/etc/init.d` fallback does not survive a rootfs reflash | Ours writes only a `$1`-guarded `user-startup.sh` block, and removes a stale `cifs_mount` entry when it installs its own |
