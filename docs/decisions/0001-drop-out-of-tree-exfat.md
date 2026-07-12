# ADR 0001 — Drop the out-of-tree exfat driver (answers Q1)

**Status:** Accepted (2026-07-12) — decided by @mcfbytes
**Supersedes:** `docs/phase0-review.md` Q1; PLAN.md ledger #17, #12
**Impact:** P1.7 (DTS), P1.9 (patches), P1.3 (kernel config), **P1.10 (initramfs) — new**

## Decision

Drop Samsung's out-of-tree `fs/exfat` driver. Use **mainline exfat + mainline vfat**.

## Rationale

Carrying an out-of-tree filesystem driver across 6.18 and then tracking it to
Dec 2028 is precisely the unbudgeted, open-ended maintenance burden that
PLAN §13 identifies as the way this project dies. The feature it buys —
symlinks on `/media/fat` via the FAT `ATTR_SYSTEM` bit — appears unused.

Evidence gathered from a live stock MiSTer (`MiSTer.lan`, 5.15.1-MiSTer,
2026-07-12), not just the SD card's main partition but **every** mounted
volume:

```
/media/fat: 0 symlinks     /media/usb0..usb7: 0 symlinks     /media/rootfs: 0 symlinks
```

This also aligns with the standing project principle: **prefer an upstream /
Buildroot default over carrying code we must maintain ourselves.**

**Evidence is n=1.** One card, one user. It is sufficient to proceed for
personal use; it is *not* sufficient to claim the community does not rely on
this. Before any public release (P4.10), either widen the evidence or ship
the detection script in Consequence (d).

## Consequences — mandatory work items

These are the reasons dropping the driver is *not* a no-op. Each is cheap; each
is easy to miss.

### (a) FAT32 media must still mount — or the device does not boot

Stock's driver mounts **FAT12/16/32 under `-t exfat`** (one mount call, one
driver). Mainline exfat **cannot mount FAT32 at all**.

This is not "FAT32 users lose symlinks." The root filesystem *is a file on that
partition* — `root=/dev/mmcblk0p1 loop=linux/linux.img` (`docs/boot-chain.md:315`).
If the partition does not mount, **the device does not boot.**

Today the kernel mounts it with filesystem autodetection. Under the §5 design we
delete that patch (see (c)) and mount it ourselves from the initramfs, so the
initramfs mount logic **must try `exfat`, then fall back to `vfat`** — never
hardcode `-t exfat`.

Kernel side is already free: stock has `CONFIG_VFAT_FS=y` and `CONFIG_NLS_UTF8=y`.

*(The decision-maker's card is a 238.7 GB exFAT partition — MBR type `07`,
verified live — so this failure mode will never appear in local testing. That is
exactly why it is written down.)*

### (b) The vfat fallback must pass `iocharset=utf8` explicitly

Stock FAT32 media decodes as **UTF-8**, because the out-of-tree exfat driver
handles FAT32 and its default is utf8 (`CONFIG_EXFAT_DEFAULT_IOCHARSET="utf8"`).

Mainline vfat's default is **iso8859-1** (`CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"`,
verified in the stock config). Falling back to vfat without `iocharset=utf8`
silently mojibakes every non-ASCII filename — and because Main_MiSTer stores
*paths* in recents/favorites/MGL, those entries stop resolving. Games "disappear."

The test card has **0 non-ASCII filenames** (verified live), so this will not
surface in local testing either.

### (c) `/media/fat` is a kernel bind-mount created by the patch we are deleting

`init/do_mounts.c:677` in the fork:

```c
err = init_mount("/root2", "/root/media/fat", "", MS_BIND, "");
```

The patched kernel mounts `mmcblk0p1` at `/root2`, loop-mounts
`/root2/linux/linux.img` as `/root`, then **bind-mounts `/root2` to
`/root/media/fat`**. Nothing in `/etc` mounts `/media/fat` — not `fstab`, not
`inittab`, not Main_MiSTer. It is *entirely* a product of the patch §5 removes.

So the initramfs must reproduce: mount p1 → loop-mount `linux/linux.img` →
bind/move p1 to `/media/fat` → `switch_root`. **We** now own these mount options.

Preserve the behaviourally meaningful ones from the live mount:
`sync,dirsync` (write-through — MiSTer users power the device off by pulling the
plug), `fmask=0022,dmask=0022`, `errors=remount-ro`.

### (d) Existing symlinks degrade silently, not loudly

Under mainline exfat, an `ATTR_SYSTEM` symlink presents as a **regular file whose
contents are the target path string**. Main_MiSTer will load that as if it were a
ROM and get garbage rather than a clean error. If we ever publish, ship a release
note plus a one-liner users can run before upgrading:
`find /media/fat /media/usb* -type l`.

### (e) Non-issue, recorded so nobody re-raises it

The live mount shows `namecase=0`. This is **not** an option anyone passes — it is
the out-of-tree driver echoing its own default via `show_options()`
(`fs/exfat/exfat_super.c:1696`), and mainline exfat has no such parameter. Mainline
exfat is case-insensitive/case-preserving per the exFAT spec, matching
`casesensitive=0`. Nothing to do.
