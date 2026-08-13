# ADR 0026 — exFAT repair is user-driven and runs once, in the initramfs; never automatic

**Status:** Accepted (2026-08-13) — decided by @mcfbytes
**Impact:** `configs/mister_initramfs_defconfig` (adds `BR2_PACKAGE_EXFATPROGS`),
`board/mister/de10nano/initramfs-overlay/init`, `board/mister/de10nano/initramfs-busybox.config`
(adds `CONFIG_RM`), new files `board/mister/de10nano/initramfs-post-build.sh`,
`board/mister/de10nano/rootfs-overlay/usr/sbin/mister-fsck-exfat`,
`board/mister/de10nano/fat-payload/Scripts/check_storage.sh`; `Makefile` (`initramfs-verify`),
`scripts/fetch-sdcard-payload.sh`, `.github/workflows/lint.yml`.

## 1. The problem

`/media/fat` is exFAT, mounted `rw,sync,dirsync,noatime,nodiratime,…,errors=remount-ro`
(the initramfs `/init`). Three facts, each verified in the source of the kernel and the
tools we actually ship, combine into a slow leak:

**(a) exFAT has no journal.** Creating a file is: allocate a cluster → set the allocation
bitmap → write the FAT chain → write the dentry set. `sync,dirsync` makes each of those
steps durable — but it does not make the *sequence* atomic. A power cut in between leaves
a lost cluster, a cross-link, or an orphaned dentry. No sync policy can fix that; only a
journal or a repair pass can.

**(b) The volume is never cleanly unmounted, so it is permanently marked dirty.**
`exfat_set_volume_dirty()` is called at the start of every modifying operation
(`fs/exfat/inode.c:43,186`; `namei.c:570,626,666,926,967,1088,1343`; `file.c:159`). It is
cleared in exactly two places: `exfat_put_super()` (`super.c:49`) and `exfat_reconfigure()`
(`super.c:763`). Nothing clears it when an operation finishes. And this box has no clean
shutdown path a user would ever take — the OSD's own **Reboot** is
`sync(); …; writel(1, &reset_regs->ctrl)` (`Main:fpga_io.cpp:588-605`), a direct write to
the HPS reset controller that never calls `reboot(2)`, never signals init, and never
reaches the `::shutdown` entries that would `umount -a -r`. So the dirty flag is set within
seconds of every boot and is still set at the next mount.

Worse, it then becomes permanent: `super.c:512` latches
`vol_flags_persistent = vol_flags & (VOLUME_DIRTY | MEDIA_FAILURE)` at mount time and
`exfat_set_vol_flags()` ORs it back into every later update, so once a volume is mounted
dirty the flag can never be cleared for that mount's lifetime — not even by a clean
unmount. Only `fsck.exfat` clears it.

**(c) `/etc/resync` is not the safety net it looks like.** The stock 5-second `sync` loop
does nothing for `/media/fat` that the mount options have not already done more strongly:
exfat has **no `.sync_fs`** operation (`exfat_sops`, `super.c:207-215`), so `sync(2)`'s two
`sync_fs_one_sb` passes are no-ops for it; `sync_bdevs()` only does
`filemap_fdatawrite`/`fdatawait` and never issues a flush; and every `write()` under
`SB_SYNCHRONOUS` already ends in `exfat_file_fsync()` (`file.c:581`) =
`__generic_file_fsync` + `sync_blockdev` + `blkdev_issue_flush`. It is kept for stock
parity (ABI contract I3) and is harmless, but it is not part of the answer here.

Net: damage is rare per power cut — `sync,dirsync` shrinks each inconsistency window to
the gap between individual buffer writes — but nothing ever repairs it, so it accumulates
without bound over the life of a card.

## 2. Why the repair cannot be automatic, and cannot be concurrent

**It can only run in the initramfs.** The root filesystem is `linux/linux.img`, a file
*on* the partition being checked (`/init`: mount data partition → `losetup` the image →
mount as `/newroot` → `mount -o move` to `/media/fat`), and `/media/fat/MiSTer` — the
Main_MiSTer binary itself — is another file on it. Once the system is up, the block device
can never be released.

**Mounting read-only does not help.** `fsck.exfat`'s repair mode opens `O_RDWR|O_EXCL`
(`exfatprogs lib/libexfat.c:147`), and a mounted filesystem holds an *exclusive* bdev claim
regardless of `ro` — `fs/super.c:1617` passes the superblock as the holder to
`bdev_file_open_by_dev()`. A userspace `O_EXCL` open then fails `-EBUSY`. Even defeating
that would be unsound: the kernel caches the allocation bitmap (`sbi->vol_amap`), dentries
and the bdev page cache, so repairing underneath a live mount converts a fix into
corruption.

So the ordering is forced, not chosen: unmounted, to completion, before anything else
exists. The only available lever is **frequency**.

**And the dirty flag is not a usable trigger.** Per §1(b) it is set at essentially every
mount, so "fsck if dirty" means "fsck on every boot". The cost of that is not theoretical:
`fsck.exfat`'s cost is O(files), not O(volume) — measured, an empty 64 GB volume checks in
**2 ms**, because it reads cluster chains on demand — with cluster-granularity read
amplification, so a card with thousands of directories pays a full cluster read per
directory. Tens of seconds on a loaded card, minutes on a full one.

**With no way to say so.** The initramfs cannot display anything. U-Boot's `fpgaload` does
load `menu.rbf`, so the FPGA *is* configured — but `/dev/fb0` (MiSTer_fb) is inert until
Main_MiSTer programs the frame reader via `/dev/MiSTer_cmd`, and the kernel console is
`console=ttyS0,115200` only. `fsck.exfat` compounds it by printing nothing at all until it
finishes (`exfat_show_info()`, `fsck/fsck.c:1833`). A user watching an unexplained black
screen power-cycles — and power-cycling mid-repair is how a lost cluster becomes an
unbootable card. **An automatic repair would be a net safety regression.**

## 3. Decision

Repair happens only when the user asks for it, and the asking happens where there is a
screen.

1. **Check while running, on screen.** `fsck.exfat -n` opens the device `O_RDONLY`
   (`libexfat.c:147`), so a read-only scan is safe against the live mount.
   `/usr/sbin/mister-fsck-exfat` runs it, times it, and shows the output. MiSTer Scripts get
   a real HDMI text console — `menu.cpp:3373` calls `video_fb_enable(1)`, then `:3402`
   `execl("/sbin/agetty", "-a", "root", "-l", "/tmp/script", …, "-L", "tty2", "linux")`.
2. **Clean → stop.** No reboot, no marker. This is where most runs end.
3. **Errors → explain and ask.** Show the findings, state that the screen will be black,
   quote the duration *measured on this card* by the scan that just ran, warn against
   powering off, and require the user to type `YES`. The prompt is `read -r -t 120` and
   times out to NO — a MiSTer is often driven by a gamepad with no keyboard attached, and
   the tool may also be run non-interactively; every one of those paths must end in
   "changed nothing".
4. **Marker, then reboot.** Confirmation writes `/media/fat/linux/.fsck-request`.
5. **The initramfs obeys, exactly once.** It tests for the marker after the mount it
   already performs, **deletes it before running the repair**, then `umount` →
   `fsck.exfat -p` → remount, and records the outcome in `.fsck-result` for the tool to
   report next time.

### 3.1 The decisions inside the decision

**Delete-before-repair.** Exactly-once is the safety property. If the repair wedges, or the
user power-cycles through it anyway, the next boot must come up normally rather than
re-entering the same repair forever — an automatic retry loop here is indistinguishable
from a brick. One request, one attempt. This is the only reason `CONFIG_RM` was added to
the stage-1 BusyBox.

**`-p`, not `-y`.** Preen repairs what is unambiguous and leaves the rest for a human,
which is the right default for a filesystem full of someone else's save games. A `-p` run
that reports `4` (errors left) is a report, not a failure.

**Fail open, always.** Not exFAT, `fsck.exfat` missing, `umount` refused, any exit code at
all — log it, record it, boot anyway. A card we could not repair is still a card the user
wants their games off. The single exception is a data partition that will not *remount*
after the repair, which drops to the existing `rescue()` shell because there is no system
left to boot into.

**Zero cost on a normal boot.** The default path adds one `test -f` against a mount that
already happens: no probe, no scan, no new BusyBox applet on the hot path. Boots that
schedule nothing are byte-for-byte what they were before.

**The tool lives in the rootfs, not in `Scripts/`.** Two reasons. It is the tool you reach
for when `/media/fat` is damaged, and anything stored there is unavailable in exactly that
case. And it speaks a protocol to the initramfs: both ends ship inside one `linux.img` and
therefore cannot drift, whereas a `Scripts/` copy updated on its own could write a marker
that the running initramfs never acts on — silently doing nothing on a box the user was
just told is about to repair itself. `Scripts/check_storage.sh` is a shim that `exec`s it
and says something useful if the image underneath is not ours.

**`linux/.fsck-request`, not a card-root marker.** Keeps it out of the user's way in
Windows. The trade-off, accepted: a volume damaged badly enough that `linux/` is unreadable
cannot ask for its own repair — but that case fails the mount first and lands in `rescue()`
anyway.

**Only `fsck.exfat` ships in stage 1.** `BR2_PACKAGE_EXFATPROGS` has no per-binary
sub-options, so `initramfs-post-build.sh` deletes the other five. Every byte here is a byte
of zImage (`CONFIG_INITRAMFS_SOURCE`, inside the 16 MiB budget `check-zimage-dtb.sh`
enforces), and that is **476,876 bytes** (measured, stripped) of static ARM binaries for
tools stage 1 cannot invoke — `mkfs.exfat` least of all, one `sh` typo from the boot path of
the very partition it would reformat. `make initramfs-verify` asserts both directions
against the built cpio.

**Measured cost of the whole change:** the cpio goes to **422,400 bytes** (226,254 gzipped),
of which `fsck.exfat` is 116,564. `bin/rm` is free — BusyBox applets are symlinks to the one
binary. Against a 16 MiB load budget for `zImage_dtb`, that is noise.

## 4. Alternatives rejected

**Switch the data partition to ext4** (or f2fs/btrfs). This genuinely fixes the root cause
— a journal replays at mount in milliseconds, O(journal) not O(files), needing no fsck and
no clean unmount — and would also give native symlinks (ADR 0019's `ATTR_SYSTEM` patch).
Rejected on interop: Windows and macOS cannot mount ext4, and card-in-a-PC is the universal
onboarding path and the fallback when networking is broken. Every existing MiSTer card is
exFAT, and this image is positioned as a drop-in stock replacement. There is no third
option: FAT32 is strictly worse (no journal, 4 GB cap); NTFS journals and Windows writes it,
but macOS is read-only and the stock `uboot.img` has **zero** NTFS support (verified: no
NTFS strings in the binary, against `ext4load`/`ext4ls`/`ext4fs_*` which are all present),
so it could not even load `menu.rbf`. No filesystem is both PC-writable and journaled.

**Repair in place without rebooting** — tear down to a tmpfs maintenance root, release the
loop-mounted rootfs, fsck, and return. Rejected: it needs PID 1 to re-exec out of a root
filesystem every process is running from, which BusyBox init cannot do and ABI contract I6
mandates we keep; and even done perfectly it cannot resume — it would re-`losetup`, remount
and `exec` init, restarting every daemon and Main_MiSTer, i.e. a reboot that skips U-Boot,
for ~10–20 s, using the most dangerous code path in the system. Its one genuine benefit is
that never resetting the FPGA would keep the frame reader scanning, so the picture would
survive; that is a display problem with a cheaper answer (below), not a reason to take this
on.

**Automatic fsck gated on the dirty flag.** §2. Fires on nearly every boot, for a
multi-minute black screen, to catch a rare event.

**A background read-only scan on the booted system** to set the marker on evidence rather
than on user request. Deferred, not rejected: `-n` is safe on a live mount, so this is
possible, but it costs the same wall-clock as the repair walk, contends for SD I/O during
play, and throws false positives because the filesystem moves underneath it. Worth
revisiting as a rare, idle-time job.

**An HDMI "please wait" screen during the repair.** Deferred, and tracked separately. It is
feasible on the reboot path — the FPGA *is* configured by U-Boot, and what is missing is
the sequence in `video_fb_enable()` (`Main:video.cpp:3557-3600`): `spi_uio_cmd_cont(UIO_SET_FBUF)`
then ten `spi_w()` writes (enable+format, base address lo/hi, width, height, scaled
L/R/T/B, stride). Three unknowns need scoping first: the scaled-window values come from
Main_MiSTer's live video state, the loaded core must support the HPS framebuffer, and
ADV7513 transmitter programming is also Main_MiSTer's job. Not a dependency for this ADR —
and by making the repair user-initiated and announced, this ADR removes the *urgency* of
solving it.

## 5. Consequences

* A user with a healthy card who runs `Scripts/check_storage.sh` gets a read-only scan, a
  clean verdict, and no reboot.
* A user with a damaged card gets the findings, a duration measured on their own card, an
  explicit warning about the black screen, and a repair they consented to by typing `YES`.
* A user who never runs it is exactly where they are today, at zero boot cost — except that
  the tool now exists when they need it.
* HPS_LED is on-board, so a fully enclosed case still sees nothing during the repair; serial
  users see everything. Same limitation ADR 0020 §6 records for the installer.
* Existing installs get `/usr/sbin/mister-fsck-exfat` with the Linux image and can run it
  over SSH. Only fresh `sdcard.img` cards get the `Scripts/` menu entry staged
  automatically; adding it to `install.sh` is deliberately out of scope here — that script
  is the update-channel opt-in, a separate concern with its own `uninstall.sh` contract.
