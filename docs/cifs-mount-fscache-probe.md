# `cifs_mount.sh` and the `fscache.ko` that stopped existing

> **Status: fixed upstream, 2026-08-17.**
> [MiSTer-devel/Scripts_MiSTer#141](https://github.com/MiSTer-devel/Scripts_MiSTer/pull/141)
> — raised from this investigation, merged by sorgelig — replaces the module-name
> probe with the same `/proc/filesystems` test `mount_smb.sh` uses. A copy of
> `cifs_mount.sh` fetched today works on a 6.8+ kernel.
>
> **The fix does not reach existing cards on its own**, and that is not a
> criticism of it — nothing distributes `cifs_mount.sh` at all (see
> [How this file reaches a card](#how-this-file-reaches-a-card)). Every copy
> already sitting in a `Scripts/` folder stays broken until its owner
> re-downloads it by hand. We keep shipping `Scripts/mount_smb.sh`; the reasons
> are narrower now and are listed in
> [Why we still ship ours](#why-we-still-ship-ours).
>
> Everything below describes the bug **as it was**, and is kept because the
> mechanism is subtle, because it recurs in any script that probes
> `modules.builtin` by name, and because two further defects in the same code
> path are still open upstream.

## Summary

`Scripts_MiSTer/cifs_mount.sh`, in every copy predating 2026-08-17, cannot mount
anything on this image. It exits with

```
The current Kernel doesn't
support CIFS (SAMBA).
Please update your
MiSTer Linux system.
```

**Nothing is missing from the image.** CIFS support is complete and working; the
script was looking for the wrong thing. Its capability probe tested for module
*names* in `modules.builtin`, and one of the five it required — `fscache.ko` —
stopped being recorded there in Linux 6.8, and cannot be recorded there by any
kernel we will ever ship.

Note the thing being looked for is a **name in a manifest, not a file**. None of
the five has ever been a file on a MiSTer: all five are built in, and
`modules.builtin` is the list of *module targets that were compiled into the
kernel* rather than a directory listing. See
[Why the name disappeared](#why-the-name-disappeared) — that distinction is the
whole of this bug.

Because the message names the kernel and tells you to update it, this reads as an
image defect. It is not one, and no amount of updating fixes it: a *newer* kernel
is the thing that triggers it. Any MiSTer on a kernel ≥ 6.8 hit this, not just
ours — including sorgelig's own `MiSTer-v6.18` branch, whose `MiSTer_defconfig`
carries `CONFIG_CIFS=y` and `CONFIG_FSCACHE=y`. That is what made it worth
raising upstream rather than only working around here.

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

<a id="why-the-name-disappeared"></a>
### Why the name disappeared

First, the thing that makes this bug confusing: **none of the five probed names
has ever been a file on a MiSTer.** Stock ships 52 `.ko` modules and fscache,
cifs, md4, md5 and des_generic are not among them — all five are built into the
kernel. `modules.builtin` is the manifest of *module targets that were compiled
in*, so the probe is reading a list of names, not a directory.

That is exactly why it used to work. On 5.15:

```
config FSCACHE
	tristate ...                        <- a module target
obj-$(CONFIG_FSCACHE) := fscache.o
```

`tristate` set to `=y` means Kbuild builds fscache into the kernel **and records
the name** `kernel/fs/fscache/fscache.ko` in `modules.builtin`. No `.ko` is ever
produced; the name is in the manifest, and the probe finds it.

**Linux 6.8** merged `fs/fscache/` into `fs/netfs/` and, in the same move,
changed `CONFIG_FSCACHE` from `tristate` to `bool`:

| | v6.7 | v6.8 |
|---|---|---|
| directory | `fs/fscache/` | **gone** |
| Kconfig | `config FSCACHE` / **`tristate`**, `select NETFS_SUPPORT` | `config FSCACHE` / **`bool`**, `depends on NETFS_SUPPORT` |
| Makefile | `obj-$(CONFIG_FSCACHE) := fscache.o` — a module target | `netfs-$(CONFIG_FSCACHE) += fscache_*.o` — objects inside `netfs.o` |
| listed in `modules.builtin`? | **yes** | **no** |
| `.ko` file on disk? | no (it is `=y`) | no |

So the name did not move — it **stopped existing anywhere**. A `bool` symbol is
not a module target, so there is nothing for Kbuild to record, and `bool` can
only ever be `y` or `n`. From 6.8 onward there is no configuration of any kind
that puts `fscache.ko` back in that manifest, and **`CONFIG_FSCACHE=m` is not
available either** — which is the first thing anyone tries on reading this.

Verified by bisecting the release tags directly — `fs/fscache/` is present at
v6.2…**v6.7** and absent from **v6.8** onward — and against our own tree, whose
`fs/netfs/Kconfig` has `config FSCACHE` / `bool` / `depends on NETFS_SUPPORT`.

### Why it works on stock

Read straight out of the extracted stock rootfs,
`work/imgroot/usr/lib/modules/5.15.1-MiSTer/modules.builtin`:

```
13:kernel/fs/netfs/netfs.ko
14:kernel/fs/fscache/fscache.ko      <- the name the probe wants
45:kernel/fs/smbfs_common/cifs_arc4.ko
46:kernel/fs/smbfs_common/cifs_md4.ko
47:kernel/fs/cifs/cifs.ko
69:kernel/crypto/md4.ko
70:kernel/crypto/md5.ko
82:kernel/crypto/des_generic.ko
```

On 5.15, netfs and fscache are **two separate module targets**, both built in,
and all five probed names are listed — so the script runs. On 6.18 there is one
target, `netfs.ko`, and the fifth name is listed nowhere.

Worth noting what did *not* break it: cifs also moved, `fs/cifs/` →
`fs/smb/client/`. The probe survived that because it greps for a name substring
and the name was unchanged. It dies on fscache because there the name stopped
being recorded at all.

The script is not broken *by* us; it was written against a kernel generation that
has since moved on, and we are the first MiSTer image to cross the 6.8 boundary.

<a id="how-this-file-reaches-a-card"></a>
## How this file reaches a card — it doesn't, automatically

This is why fixing it upstream was necessary but not sufficient, and it was
checked rather than assumed:

- **There is no Scripts_MiSTer database.** No `db` branch, no `db.json.zip`
  (all three plausible URLs 404). It is a plain source repo, not a Downloader
  source.
- **`Distribution_MiSTer`'s `db.json` carries a curated subset** — 1435 files, of
  which 11 are `Scripts/`: `update.sh`, `wifi.sh`, `timezone.sh`, `rtc.sh`,
  `samba_on.sh`, `ini_settings.sh`, `fast_USB_polling_{on,off}.sh` and three
  `Scripts/.config/downloader/` files. **`cifs_mount.sh` is not among them.**
- **`update_all_db.json` carries 10 files**, all of Update_All's own; no
  `cifs_mount.sh`.
- **The stock release archive ships only `Scripts/update.sh`**
  (`docs/verification/stock-release-20250402.md`).

So `cifs_mount.sh` arrives on a card by hand — downloaded from GitHub, or
inherited from an old SD image — and nothing ever updates it in place. A fix in
the repo reaches only people who go and fetch it again.

> **Correction, recorded because an earlier revision of this document argued from
> it:** the original decision not to fork `cifs_mount.sh` was justified partly by
> "Update_All would overwrite our copy". That is **false** — no database carries
> the file, so a fork would never have been clobbered. The decision stands on its
> other grounds (991 lines of largely dead code, and the boot-entry behaviour we
> needed to differ on), but that particular reason was wrong.

<a id="why-we-still-ship-ours"></a>
## Why we still ship ours

After upstream #141, three reasons remain — and only three:

1. **It arrives automatically.** `install.sh`, `scripts/fetch-sdcard-payload.sh`
   and the updater's repair path all place `mount_smb.sh` on the card, so an SMB
   mount works with no hunting on GitHub. Per the section above, the upstream fix
   has no such route.
2. **The boot entry's `$1` guard is still missing upstream.** `S99user` invokes
   `/media/fat/linux/user-startup.sh` with `start`, `stop` **and** `restart`;
   upstream's `STARTUP_COMMAND` (`cifs_mount.sh:220`) is unguarded, so it also
   fires a mount during shutdown. Ours writes a `case "${1:-start}"` block.
3. **Its `/etc/init.d/S99cifs_mount` fallback cannot survive a Linux update**,
   which reflashes the whole rootfs. Only `/media/fat` persists. Ours writes to
   `user-startup.sh` only, with no init.d path at all.

Points 2 and 3 are open upstream; see the audit trail for their disposition.
Should they be fixed and a distribution route ever appear, this script's
justification narrows to nothing and it should be retired rather than defended.

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
| 2026-08-17 | Wording implied `fscache.ko` was a **file** that disappeared. It never was one — stock ships 52 `.ko`s and none of the five probed names is among them | Reworded throughout: `modules.builtin` lists module **targets compiled in**, not files. A `tristate` set to `=y` is recorded there; a `bool` is not recorded at all, and `CONFIG_FSCACHE=m` is unavailable |
| 2026-08-17 | Raised upstream as [Scripts_MiSTer#141](https://github.com/MiSTer-devel/Scripts_MiSTer/pull/141) (`+8/-40`, one file) — **merged by sorgelig** | Upstream now uses the same `/proc/filesystems` test. Verified before submitting that the unpatched file reproduces the bug and the patched one does not, that the message text and exit code are byte-identical, and that it still refuses a genuinely CIFS-less kernel |
| 2026-08-17 | Checked how `cifs_mount.sh` is distributed: **it isn't**. No Scripts_MiSTer db; `Distribution_MiSTer`'s 11 `Scripts/` entries exclude it; `update_all_db.json` excludes it; the stock archive ships only `update.sh` | Keep `mount_smb.sh`. The upstream fix cannot reach an existing card on its own, and automatic delivery is now reason #1 for ours. Earlier "Update_All would clobber a fork" reasoning retracted as false |
| 2026-08-17 | Two defects remain in upstream's boot path: unguarded `$1` in `STARTUP_COMMAND` (`:220`), and an `/etc/init.d/S99` fallback that a Linux update destroys | `$1` guard is a genuine one-line bug worth its own upstream PR. The init.d fallback is near-dead code (it only runs when `/etc/init.d/S99user` is absent) and removing it would be a robustness regression on systems that lack it — **not** worth a PR; recorded here instead |
| 2026-08-17 | Fixing it in place would mean forking a 991-line actively-maintained upstream script that Update_All can overwrite | Ship `mount_smb.sh` under our own name instead, by the same one route as our other Scripts (ADR 0026) |
| 2026-08-17 | Upstream's boot entry is unguarded on `$1` and its `/etc/init.d` fallback does not survive a rootfs reflash | Ours writes only a `$1`-guarded `user-startup.sh` block, and removes a stale `cifs_mount` entry when it installs its own |
