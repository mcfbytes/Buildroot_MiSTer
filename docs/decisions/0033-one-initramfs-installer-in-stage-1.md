# ADR 0033 — One initramfs: the SD-card installer moves into stage 1

**Status:** Proposed (2026-10-15, at the owner's direction: "one cpio initramfs, one
kernel build, one toolchain, one itsalive"). Built and QEMU-tested; **not yet run on a
DE10-Nano** — see [§7](#7-what-is-proven-and-what-is-not).
**Amends:** [ADR 0020](0020-sdcard-exfat-reformat-installer.md) (the installer is no
longer its own initramfs and kernel; its commit point and re-run guard change),
[ADR 0026](0026-user-driven-exfat-fsck.md) (its rule that `mkfs.exfat` never sits in
stage 1), [ADR 0002](0002-initramfs.md) (stage 1 gains a second job).
**Builds on:** [ADR 0030](0030-makefile-toward-vanilla-buildroot.md) Phase B, which already
moved stage 1 from a musl configuration into the main glibc build.
**Mechanics:** [`docs/installer-init.md`](../installer-init.md) (the script, the flag, the
card states), [`docs/installer-build.md`](../installer-build.md) (the build and `make sdcard`).

## 1. Context

Before this ADR, `sdcard.img` needed three things the shipped image did not:

1. **A second Buildroot configuration**, `configs/mister_installer_defconfig`: static musl,
   its own `O=output-installer`, so its own cross toolchain. On CI it was step 1 of
   `mk-sdcard.sh`: **19 min** (run 38261354093) and **29 min** (run 37182947808) of a
   ~90-minute release job. Locally it was a 9 GB build tree plus 1.1 GB of host tools.
2. **A second kernel**: `mk-sdcard.sh` relinked `output/`'s kernel around the installer
   cpio, captured the result, then relinked again to restore `output/`, behind an EXIT
   trap whose only job was to stop the installer kernel leaking into a Downloader release.
3. **A second copy of the kernel on the card**: the installer kernel at the FAT root and
   the real one inside `mister-payload/`. The install's commit point was renaming one
   over the other, and "which kernel is on `p1`" was the primary re-run guard.

Meanwhile stage 1 already carried most of the installer's needs: a static glibc BusyBox,
the static `mister-initramfs-exfatprogs` build (whose `mkfs.exfat` was built and thrown
away), and — on `feat/fsck-hdmi-splash` — a static glibc `itsalive` for the exFAT
repair's splash. The only thing in the way was ADR 0026's deliberate rule that a card
reformatter must not live in the boot path.

## 2. Decision

**One cpio, one kernel, one toolchain, one `itsalive`.** The installer script, a static
`mkfs.exfat` and the installer's splash frames go into the DE10-Nano's stage-1 cpio
(`BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER`; the script sits in the DE10's stage-1 board
overlay, `board/mister/de10nano/initramfs-overlay/`, layered over the common one by
`BR2_PACKAGE_MISTER_INITRAMFS_BOARD_OVERLAY`), and `configs/mister_installer_defconfig`,
`installer-busybox.config` and `installer-post-build.sh` are deleted. The kernel that
boots `sdcard.img` is byte-for-byte the kernel the Downloader ships, and `make sdcard`
is pure assembly of `make all`'s outputs.

**A flag on the card decides "install", and nothing else does** ([§3](#3-the-flag)).
Stage 1 asks a read-only probe about the boot disk right after `root=` appears; only the
exact answer `armed` `exec`s the installer. Every other answer, including any failure of
the probe itself, is the normal boot.

**The installer keeps the flag until it is done, and spending it (wiping the magic block)
is the commit point** ([§5](#5-what-changes-in-the-installer)).

**The partition table is written by the installer's own shell**, not `sfdisk`, so the
stage-1 cpio needs no util-linux ([§4](#4-why-shell-and-why-no-sfdisk)).

## 3. The flag

Both of:

- **MBR entry 3**: type `0xda`, start LBA 1024, 1024 sectors — inside the 1 MiB gap
  before `p1` that every MiSTer card has and none uses; and
- **the 512-byte block at LBA 1024** equal to `/usr/lib/mister/install-flag.bin`
  (`MiSTer first-boot installer flag v1 db4ad7b4-a222-4b41-9a8b-17d92131ada0\n`,
  zero-padded), the same file genimage writes into entry 3 of `sdcard.img`.

| Probe result | Meaning | Stage 1 |
|---|---|---|
| `absent` | no entry 3 at 1024/1024 of type `0xda` | normal boot |
| `spent` | entry 3 present, block is not the magic (a committed install, or a forged block) | normal boot (logged) |
| `armed` | both | `exec` the installer |

Rejected alternatives, and why:

- **A file on `p1`** (a marker in `mister-payload/`, say). Files get copied. A user who
  drags the contents of a freshly flashed `sdcard.img` onto their existing card, or
  restores a backup, would carry an armed marker onto a card full of their data. An MBR
  entry is not something a file manager copies.
- **A magic sector with no partition entry.** It survives every other tool: re-partition
  the card in Windows and the old magic is still sitting in the gap, armed. Requiring
  entry 3 as well means a *fresh* table disarms the card. It is not enough on its own —
  `fdisk`, GParted and Windows Disk Management keep entries the user does not touch —
  which is why the installer's `foreign` state (§5) disarms such a card instead of
  rescuing on it.
- **The MBR disk identifier.** Four bytes every partitioning tool randomises; too easy to
  collide with, and it gives the installer nothing to remove atomically.
- **A partition type alone** (entry 3 of type `0xda` without a magic). Plausible on a card
  a user partitioned themselves; the magic is what makes it ours.
- **A filled flag partition checked by `sha256`.** A hash compare is a compressed
  equality test; the probe already `cmp`s all 512 bytes against the copy in the cpio.
  Filling 512 KiB would make every boot read 1024× more and need a `sha256sum` applet,
  for no lower chance of a false match. Deliberate forgery is out of scope: anyone who
  can write raw sectors to the card already owns the board.

The flag's location costs nothing: the installer's final layout is the same `p1`/`p2` as
before, and the 512 KiB in the gap was unused. The only image-side change is
`genimage-sdcard.cfg`'s `align` going from 1M to 512K (genimage requires offsets aligned
to it), with `p1`'s 1M offset now stated explicitly.

## 4. Why shell, and why no `sfdisk`

The owner asked whether a Rust or C program would be less error-prone for the PID-1
steps, then said "I feel we can probably make our sh script robust enough and well
guarded". The weighing:

- The orchestration (mount, copy, `zcat`, `switch_root`, rescue) is the part that has
  been hardware-tested since ADR 0020; rewriting it would discard that validation for
  type safety in the part that has not been the problem.
- The genuinely byte-level, brick-class parts are three: reading the flag, writing the
  MBR, and spending the flag. Each is small. In shell they are made safe by checking
  instead of trusting: the new sector must be exactly 512 bytes before it is written, it
  is read back after a buffer-cache flush and compared, and after `blockdev --rereadpt`
  the kernel's own `/sys/block/<disk>/<part>/{start,size}` must show exactly the intended
  partitions before anything else runs.
- And it is tested against an oracle, which a hand-written Rust MBR writer would also
  need: `scripts/test-installer-mbr.sh` runs the script's MBR section on the shipped
  BusyBox (under `qemu-arm`) and requires the sector to be **byte-identical** to `sfdisk`
  (entries 1–2) and genimage (entry 3) at card sizes from 8 MiB to 2^32−1 sectors. It
  passed at every size on the first run.

Dropping `sfdisk` removed util-linux from the installer entirely: a static-glibc `sfdisk`
would have been a third util-linux build in the main configuration and ~1.2 MB in the
cpio (glibc's static overhead measured at ~490 KB per binary on `mkfs.exfat`: 103,420 B
musl vs 594,412 B glibc). `blkid`, `blockdev`, `findfs`, `dmesg`, `setsid` and `hexdump`
were already BusyBox applets.

Two bugs of the same kind turned up on the way. The installer's BusyBox had **32-bit
shell arithmetic** (`CONFIG_FEATURE_SH_MATH_64` off), so on a card past 1 TiB its sector
maths would have overflowed — a latent defect in the musl installer too. And with that
fixed, the first QEMU run of the merged installer failed *every* install with
`sh: 4294967295: out of range`: BusyBox's `[` is 32-bit unless `CONFIG_FEATURE_TEST_64`
is on, and the new "card is MBR-addressable" guard compares against 2^32−1. The MBR unit
test missed it because it runs only the MBR section; the recovery matrix caught it. The
merged BusyBox has both options, `verify.sh` fails the build without either, and the
installer refuses a card an MBR cannot address before writing anything.

## 5. What changes in the installer

- It is `exec`'d by stage 1 with the data partition as `$1`; stage 1 has already mounted
  `/proc`, `/sys`, `/dev` and resolved `root=`.
- It **re-checks the flag** immediately before the bootloader write, the MBR write,
  `mkfs.exfat` and the commit, and checks before anything is written that the cpio holds
  `mkfs.exfat` and the flag definition.
- **`uboot.img` goes to the end of the card before the MBR that points `p2` at it**, and
  is read back both times. ADR 0020's order (MBR, then `dd` to the new `p2`) left a window,
  including a 30-second re-read loop, in which the BootROM would have found an empty `p2`.
- Card states (full table in `docs/installer-init.md#card-states`): `fresh` (FAT32 with a
  complete payload), `resume` (exFAT `MiSTer_Data` **with an install token** the
  installer writes right after `mkfs`, and a complete payload), `finish` (exFAT, payload
  consumed, `linux/linux.img` and the kernel present). An exFAT card with a complete
  payload but no token is refused, not reformatted: the token is a second key on the
  only path that formats an exFAT partition.
- **`foreign`**: an armed card the installer did not make and cannot install from (an
  exFAT without the token or label, a FAT32 without a complete payload) has its flag
  spent — one write to LBA 1024, `p1` only ever mounted read-only — and reboots into a
  normal boot. The review that found it: a user who recreates `p1` in GParted keeps
  entry 3 and the magic, and would otherwise be stuck in a rescue whose only advice,
  re-flash, destroys their data.
- The **commit point** is wiping the flag's magic block (one verified 512-byte write that
  never touches sector 0), after the data partition is unmounted; removing entry 3 from
  the MBR follows as cleanup, and a failure there leaves a spent flag and a working card.
  ADR 0020's kernel rename is gone with the second kernel. Sector 0, which holds the
  `0xA2` entry the BootROM needs, is written twice per install: once in the repartition
  (unavoidable) and once in that cleanup.
- The user's **pre-seed** files are kept on the new card (`linux/.mister-preseed/`), so a
  `finish` or `resume` boot after a cut still applies them.
- **Recoverability improves**: a cut anywhere in step 10 used to halt on "already
  provisioned" or "interrupted while finishing; re-flash"; now it lands in `finish`, which
  completes the install without reformatting. The remaining re-flash windows are ADR
  0020's two (between `mkfs.exfat` and the kernel write-back; the copy-back), plus a torn
  write of sector 0 itself, which no ordering removes.
- The "already provisioned" halt is deleted: an installed card's flag is spent or gone,
  so it never reaches the installer.

## 6. Costs and consequences

| | Before | After |
|---|---|---|
| Buildroot configurations for the DE10 | 2 (`mister_de10nano`, `mister_installer`) | 1 |
| Toolchains built for a release | glibc + musl | glibc |
| Kernel links for `make sdcard` | 2 extra (relink, restore) | 0 |
| `mk-sdcard.sh` | 681 lines, 7 steps | 238 lines, 5 steps, no Buildroot call |
| Release job, sdcard step | 22–32 min | measured on the first release run |
| Stage-1 cpio | 2,539,008 B (1,296,953 gz), with `itsalive` | 3,237,888 B (1,649,943 gz) |
| Installer cpio | 3,266,048 B (musl), separate | — (inside the above) |
| DE10 `zImage_dtb` | 10,760,713 B | 11,119,737 B |

So every DE10 kernel grows by **359 KB** (measured on `zImage_dtb`) over the fsck-splash stage 1,
against the 16 MiB budget of `docs/boot-chain.md` §7.3. The RT kernel embeds the same
cpio and grows the same. The DE25 cpio gains the probe, the flag block and the extra
BusyBox applets, but not the installer.

What every boot (DE10 and DE25) now does that it did not: one fork of the probe, one
16-byte `hexdump` of MBR entry 3 and, only if that entry is exactly type `0xda` at LBA
1024/1024 sectors, one 512-byte `dd`+`cmp`. Nothing is written.

The real cost is the one ADR 0026 named: **the reformatter is now inside every DE10
kernel**. It is mitigated, not removed:

- `mkfs.exfat` is under `/usr/libexec/mister-installer/`, on no `PATH`, reachable only by
  absolute path from the installer script; `verify.sh` asserts no exfatprogs tool but
  `fsck.exfat` sits in any `bin`/`sbin` directory.
- `/init` never names it. The only route to it is `armed` from the probe, re-checked
  three more times before anything destructive.
- `scripts/test-installer-recovery.sh` scenarios D, I and J prove the negative on every
  run: a finished card, a payload-shaped card with no flag, and a card with entry 3 but a
  forged block all boot stage 1's normal path, and the MBR is byte-for-byte unchanged.
  L and N prove it for armed cards the installer did not make: the flag is spent, and
  the MBR and every byte of `p1` are unchanged.

Cards flashed from older `sdcard.img` releases carry the old installer kernel and are
unaffected; nothing here reads them.

## 7. What is proven, and what is not

Proven in QEMU (`-M virt`, virtio-blk) and on the host, on this branch (2026-10-15, all
green):

- `scripts/test-installer-mbr.sh` — the MBR writer, byte-identical to `sfdisk`/genimage,
  under the shipped BusyBox (`qemu-arm`) and under Ubuntu's 1.37.0 (the CI lint lane).
- `scripts/test-installer-recovery.sh` — 136 checks: a clean install plus every interrupt point
  (`uboot-staged`, `bootloader`, `recoverable`, `payload-partial`, `payload-copied`,
  `expanded`, `moved`, `committed`), the three never-touch cases, the two `foreign` cards
  and a re-armed installed card; a finished card boots to a marker `/sbin/init` through
  the normal stage-1 path, and the user's pre-seed survives a cut at `moved`.
- `package/mister-initramfs/verify.sh` at build time — applets, static binaries, the flag
  block, off-PATH `mkfs.exfat`, 64-bit maths, `ash -n` of all three scripts.
- `scripts/test-sdcard-install.sh` / `scripts/check-sdcard.sh` — the shipped
  `sdcard.img` end to end, after `make sdcard` on this branch, including a second boot
  that takes the normal stage-1 path.
- `scripts/test-initramfs.sh` — the stage-1 regression set (FAT32, exFAT, `fsck-request`,
  symlinks, label, non-ASCII, missing image, `rootwait`) is unchanged.
- `scripts/test-installer-splash.sh` and `scripts/check-defconfigs.sh`.

**Not proven: a DE10-Nano.** QEMU has no BootROM, SPL or U-Boot. The facts only hardware
can confirm: the BootROM still picks the `0xA2` entry with a `0xda` entry 3 present; the
stock U-Boot still boots `mmc 0:1`; `/sys/block/mmcblk0/mmcblk0p3` appears with the
expected geometry; and the install, the picture, the reboot into MiSTer and the next
Downloader update all behave as in QEMU. That run is owed before this is accepted.
