# The SD-card installer

`board/mister/de10nano/initramfs-overlay/usr/libexec/mister-installer/install` is the
first-boot installer that turns a freshly flashed `sdcard.img` into a full-size exFAT
MiSTer card (TASKS P5.3, PLAN §8, ADR 0017 §4, [ADR 0020][adr]). Since [ADR 0033][adr33]
it is not a separate initramfs or kernel: it lives inside the ONE stage-1 cpio every
DE10-Nano kernel embeds, and the stage-1 `/init` hands the card to it only when the card
carries the [installer flag](#the-flag). This page carries the explanation that used to
live in the script's own comments; the script keeps one- or two-line pointers into the
headings below.

> **THIS FILE CAN BRICK THE BOARD.** Read this page, [ADR 0020][adr], [ADR 0033][adr33]
> and `docs/boot-chain.md` §2.1/§3.1/§5 before touching a single line of it. Every edit
> must keep `shellcheck -s sh -x`, `scripts/test-installer-splash.sh`,
> `scripts/test-installer-mbr.sh`, `scripts/test-installer-recovery.sh` and
> `scripts/test-sdcard-install.sh` passing.

## What it is

The shipped `sdcard.img` is a *small* dd/Etcher-writable card: FAT32 `p1` (the payload),
the `0xA2` boot partition `p2` (`uboot.img`, byte-identical), and the flag as entry 3. On
the first boot the stock U-Boot loads `/linux/zImage_dtb` off `p1` — **the same kernel**
the Downloader ships. Its stage-1 `/init` mounts `/proc`, `/sys` and `/dev`, waits for
`root=`, asks `/usr/lib/mister/install-flag` about the disk, and on the exact answer
`armed` `exec`s this script as PID 1 with the data partition as `$1`. Everything runs
from RAM — the initramfs is a ramfs, so nothing done to the SD card pulls the rug out
from under the running system. That is the whole reason the reformat-in-place trick
works.

MiSTer's data partition is exFAT, which Linux cannot grow in place, so "auto-expand to
fill the card" is a **reformat**, exactly like mr-fusion
(`MiSTer-devel/mr-fusion`, `builder/scripts/S99install-MiSTer.sh`, which this script is
adapted from). Why: [ADR 0020 §1.1][adr-1.1].

It is plain POSIX sh / BusyBox ash — no bashisms. There is deliberately **no `set -e`**
(only `set -u`): every failure is handled explicitly, either by `rescue` or by a logged
warning, and nothing cosmetic may abort the install.

## The flag

The one thing that decides "install" versus "boot". It is **both** of:

- MBR **entry 3**: type `0xda` ("non-FS data"), start LBA **1024**, **1024** sectors
  (512 KiB) — inside the gap before `p1` (LBA 2048), which no MiSTer card uses; and
- the 512-byte block at **LBA 1024** equal, byte for byte, to
  `/usr/lib/mister/install-flag.bin` (`MiSTer first-boot installer flag v1 <uuid>\n`,
  zero-padded; `package/mister-initramfs/mister-initramfs.mk` writes it, and
  `scripts/mk-sdcard.sh` puts the same file on the image through genimage).

The numbers live in one place, `/usr/lib/mister/install-flag.conf`, which both the probe
and the installer source; `verify.sh` fails the build if either script sets a `FLAG_*`
value itself, and `mk-sdcard.sh` checks the assembled image's entry 3 and LBA 1024
against the copies **inside the embedded cpio**, so `genimage-sdcard.cfg` cannot drift.

`install-flag state DISK` reads it without writing anything and prints one word. It
reads entry 3 from the MBR bytes, not from sysfs: the kernel adds partitions one at a
time, so `/init` can see `p1`'s node before `p3` exists. (`install-flag probe PART`
does the disk lookup and the state in one call, for `/init`.)

| It finds | It prints | `/init` does |
|---|---|---|
| no partition 3, or not at 1024/1024, or not type `0xda` | `absent` | boots normally |
| entry 3 as above, but the block is not the magic | `spent` | logs it, boots normally (a committed install, or a forged/stale block) |
| entry 3 as above **and** the magic block | `armed` | `exec`s the installer |

Anything else — a missing node, an unreadable sector, a crash of the probe — ends up as
`absent` or `spent`, because `/init` compares the output against the literal `armed`
and nothing else. Every board's stage 1 carries the probe; only the DE10-Nano's carries
the installer, so an armed flag on a DE25 card is a clear rescue message, not a guess.

Why two parts: a file can be copied onto another card, but an MBR entry cannot; and an
entry with no magic behind it is just a partition. Neither can arm the installer alone.
Repartitioning does **not** reliably disarm a card — SD Card Formatter and a fresh
table drop entry 3, but `fdisk`, GParted and Windows Disk Management keep entries the
user does not touch, and none of them touch LBA 1024. That is what the
[`foreign`](#card-states) state is for: an armed card the installer did not make is
disarmed and booted normally, never reformatted and never left in a rescue loop.

The installer **keeps** the flag through the whole install — its own MBR write
reproduces entry 3 unchanged — because the flag is also what brings an interrupted card
back into it. Wiping the magic block is the [commit point](#commit-phase).

The installer re-asks the probe immediately before every destructive step (the
bootloader write, the MBR write, `mkfs.exfat`, the commit) instead of trusting what it
saw at the start.

## The ten steps

These are exactly the steps the console splash counts off (`1/10` .. `10/10`), so they
are what a user with a serial cable sees. There is **one** numbering in the script, its
section markers, this page and [ADR 0020 §8.2][adr-8]; keep every reference on it, and
keep `SPLASH_TOTAL` equal to the highest `splash_step` call
(`scripts/test-installer-splash.sh` enforces that).

1. Find the whole disk from `$1`, re-check the flag, mount `p1` **read-only** and work
   out which [state](#card-states) the card is in.
2. Check the kernel at the FAT root, and capture any user [pre-seed](#pre-seed) dropped
   there before first boot (or, on `resume`, the copy an earlier run kept on the card).
3. Copy `mister-payload/` into a RAM tmpfs, **alongside** the FAT root's
   `/linux/zImage_dtb` and `/menu.rbf` — the two files that let a half-finished card
   boot back into this installer.
4. Write `uboot.img` raw to where the new `0xA2` `p2` **will** be — the last 4 MiB of
   the card, which on a fresh card is outside every partition (checked) — and read it
   back. The partition table is still the shipped one.
5. Write a new MBR for the **whole** card: `p1` = exFAT data filling the card minus a
   small reserved tail, `p2` = type `0xA2` over the bootloader just written, entry 3 =
   the flag, unchanged ([layout](#partition-layout)); re-read it, check the kernel sees
   exactly that, and compare `p2`'s head with `uboot.img` again through the new node.
   There is no instant at which the MBR points the BootROM at an empty `p2`.
6. `mkfs.exfat -n MiSTer_Data` the new `p1` and mount it `-t exfat` (in-kernel driver,
   ADR 0019 — no FUSE, unlike mr-fusion).
7. Write the [install token](#card-states), the kernel and `menu.rbf` onto the fresh `p1`
   before any payload byte — from this instant a power cut boots straight back into the
   installer (the flag is still armed) rather than into nothing.
8. Keep the pre-seed on the card (`linux/.mister-preseed/`), then copy the payload back
   out of RAM into `mister-payload.part/` and, once complete,
   **rename** it to `mister-payload/` (a directory-entry update, which is what makes a
   partial copy detectable on the next boot).
9. `zcat mister-payload/linux/linux.img.gz > linux/linux.img` straight onto the card —
   the 512 MiB image lands on disk, never in RAM ([RAM budget](#ram-budget)) — with the
   payload left complete for the whole decompression.
10. [Commit](#commit-phase): drop the redundant `.gz`, move the payload's entries into
    their final places, apply the pre-seed, write a unique per-board [MAC](#per-board-mac)
    into `linux/u-boot.txt`, remove the payload directory, the pre-seed copy and the
    token, unmount, and **spend** the flag (wipe the magic block) as the very last act;
    then remove entry 3 from the MBR as cleanup and `reboot -f`.

Because step 10 spends the flag, the next boot is stage 1's normal one. Nothing about
the card's files decides that; the flag does.

## Recoverability

Why steps 5 and 7 sit where they do (issue #185) is [ADR 0020 §8][adr-8]; the short
version: the old order (`dd uboot.img` last, no kernel on `p1` until the copy-back) made
the entire ~1-minute install one unbroken brick window, and it coincided with the minute
in which the board looks dead. The current order attacks the harm rather than the
visibility; the [HDMI splash](#hdmi-splash) separately shrinks the temptation to pull
the power.

### Card states

The installer only ever runs on an **armed** card. On one, a power cut at any instant
leaves exactly one of these states, and step 1 reads which. Read this before changing
any condition there.

| On the (armed) card | State | Next boot |
|---|---|---|
| FAT32 `p1`, `mister-payload/` complete | `fresh` | full install |
| exFAT `MiSTer_Data` **with the install token**, `mister-payload/` complete | `resume` | full, unattended re-install; the normal interrupted state, costs one more run |
| exFAT, payload no longer complete, `linux/linux.img` and `linux/zImage_dtb` present | `finish` | finish step 10 only — **no reformat** |
| `mister-payload.part/` instead of `mister-payload/` | — | halt ("INTERRUPTED … re-flash"): the copy-back's source lived in RAM and is gone |
| exFAT `MiSTer_Data` **with the token**, nothing complete, no `linux/linux.img` | — | rescue: "interrupted before the payload was copied; re-flash" (a card this installer formatted, with no user data on it) |
| anything else — an exFAT without the token or label, a FAT32 without a complete payload | `foreign` | **spend the flag** (one write to LBA 1024; `p1` was only ever mounted read-only) and reboot into a normal boot |

"Complete" means `linux/linux.img.gz` and `linux/uboot.img` both present and non-empty.

The **install token** (`linux/.mister-install-in-progress`) is written in step 7, right
after `mkfs.exfat`, and removed in step 10 before the commit. It is the second key on the
`resume` path — the only path that formats an exFAT partition — so that even an armed
flag cannot get an exFAT the installer did not itself create reformatted. `finish` does
not need it: it never formats, and without the token it does nothing but spend the
flag (which is what any card that reaches it with an armed flag needs).

`foreign` exists because the flag can outlive the card it was put on: a user who flashes
`sdcard.img` and then deletes and recreates `p1` in GParted or `fdisk` keeps entry 3 and
the magic. Without it every boot would land in a rescue whose only advice, "re-flash", would
destroy what they had copied on since. Instead the installer leaves the card exactly as it
is apart from the 512-byte magic block, which both keys say is the installer's own.

Two windows still cost a re-flash — `mkfs.exfat` until the kernel lands on `p1` in step
7 (a few seconds; the only hard one), and the copy-back of step 8 (`mister-payload.part/`)
— both stated in [ADR 0020 §8.3.1][adr-8.3.1]. The first does **not** start at the MBR
write: it only rewrites sector 0 and the new `p1` still starts at LBA 2048, so the
shipped FAT32 is intact under the enlarged entry and an interrupt there simply re-runs
(`scripts/test-installer-recovery.sh` scenario F proves it). The old third window — the
commit phase, where a cut halted on "already provisioned" — is gone: a cut anywhere in
step 10 lands in `finish`. **Do not put anything slow inside either remaining window.**

### The boot files

The FAT root's own `linux/zImage_dtb` is the kernel running this very script, and
`menu.rbf` is what U-Boot's `fpgaload` puts in the fabric ([ADR 0020 §7][adr-7]).
Neither is part of `mister-payload/`. They are staged in RAM in their own directory
(`$RAM_BOOT`, separate from `$RAM_PAYLOAD`) so the payload's copy-back glob can never pick
them up — a separate directory rather than a naming convention, so no accident can. Step
7 writes both onto the freshly formatted partition before anything else, which turns
"mid-install" from a brick into a card that simply runs the installer again. The kernel
is **required** (a card it could not boot again is not reformatted); `menu.rbf` is only
warned about. There is no second kernel: since ADR 0033 the kernel written back in step 7
*is* the installed system's kernel, and the payload carries none.

## Load-bearing facts

Get one of these wrong and you brick a card.

- **Partition slots are fixed.** Shipped and final cards both use `p1` = data,
  `p2` = `0xA2`: the stock U-Boot's compiled-in env has `mmcroot=/dev/mmcblk0p1` and
  `load mmc 0:1 ... $bootimage`, i.e. it *always* reads the kernel from partition 1
  (`docs/boot-chain.md` §3.1 entries 16–17, §4), and the BootROM independently scans the
  MBR for the first `0xA2` entry (§2.1) — entry 3 is `0xda`, so it is never a candidate.
  The installer's MBR must reproduce this. That is also why it refuses a data partition
  that is not `p1` of its disk.
- **The `0xA2` partition moves.** So `uboot.img` is written to its new place (step 4,
  from the verified RAM copy, read back) **before** the MBR that names it (step 5): the
  BootROM never sees a `p2` without a bootloader in it. The new `p2` must not overlap any
  partition the card has now (it may *be* the current `p2`, on `resume`); the installer
  checks that before writing a byte. Do not let an edit move the bootloader write after
  the MBR write.
- **Sector 0 is written as few times as possible.** It holds the `0xA2` entry the
  BootROM needs, and SD cards do not promise a power-cut-atomic write. The install writes
  it once in step 5 (unavoidable) and once more in step 10 to remove entry 3 — after the
  commit, as cleanup, so a failure there leaves a spent flag and a working card. The
  commit itself and the `foreign` path write only LBA 1024.
- **`u-boot.txt` must end in a newline.** U-Boot's `env import -t` (no size argument)
  scans for `\n` followed by `\0` (`docs/boot-chain.md` §4, U-Boot
  `cmd/nvedit.c:1049-1066`). The MAC `printf` supplies it.
- **Memory is capped at 511 MiB** — see [RAM budget](#ram-budget).
- **Defensive like the stage-1 init** (`board/mister/common/initramfs-overlay/init`),
  which already mounted `/proc`, `/sys` and `/dev` and resolved `root=` before handing
  over: the installer checks those mounts are there rather than redoing them, takes the
  device from `$1` (never hardcoded), and on any fatal error prints a banner and drops to
  a respawning [rescue shell](#rescue). PID 1 must never exit — that is an instant
  kernel panic.
- **Never repartition the wrong disk.** The whole-disk device is the
  `/sys/block/<disk>/` directory that contains the data partition's directory
  (`install-flag disk`) — authoritative across mmcblk/sd/nvme/usb, with no name parsing.
  Partition nodes then follow the kernel's rule: `p<N>` when the disk name ends in a
  digit (`mmcblk0p1`, `nvme0n1p1`), else `<N>` (`sda1`).
- **Sector arithmetic is 64-bit.** A 2 TB card is past 2^31 sectors, so the stage-1
  BusyBox has `CONFIG_FEATURE_SH_MATH_64` (for `$((...))`) and `CONFIG_FEATURE_TEST_64`
  (for `[ -le ]`); `verify.sh` fails the build without either, and
  the installer refuses (before writing anything) a card larger than the 2^32−1 sectors
  an MBR can address.

### Partition layout

`p1` runs from the 1 MiB-aligned start (`P1_START_SECTORS=2048`, matching
`genimage-sdcard.cfg`'s `offset = 1M`) to the reserved tail; `p2` is **exactly**
`RESERVED_SECTORS=8192` 512-byte sectors (4 MiB; `uboot.img` is ~503 KiB) at the very
end, matching `genimage-sdcard.cfg`'s `size = 4M` byte-for-byte; entry 3 is the
[flag](#the-flag), rewritten unchanged; entry 4 is empty. `type=7` is exFAT/NTFS
(mr-fusion parity), `0xa2` the SPL partition. No entry is marked bootable.

The table is written **by the script itself**, not `sfdisk` (ADR 0033 §4): the stage-1
cpio carries no util-linux. The MBR section (between `>>> MBR SECTION BEGIN` and
`END`) builds the sector from octal escapes — boot code (bytes 0–439) kept from the old
sector, a fresh random disk identifier (as `sfdisk` gives a new label), four 16-byte
entries with CHS computed the way libfdisk does for 255 heads × 63 sectors (`FE FF FF`
past cylinder 1023), and `55 AA`. `mbr_commit` checks the sector is exactly 512 bytes,
writes it with one `dd conv=notrunc,fsync`, flushes the buffer cache and reads it back
with `cmp`; then `blockdev --rereadpt` and `/sys/block/<disk>/<part>/{start,size}` must
show exactly the three intended partitions, and `p2` must hold `uboot.img`, before step 6 runs.
`scripts/test-installer-mbr.sh` runs that section on the shipped BusyBox and requires
it to be byte-identical to `sfdisk` (entries 1–2) and genimage (entry 3) at card sizes
from 8 MiB to the 2^32−1-sector limit.

All three numbers are computed explicitly. mr-fusion's empty-field form
(`; size; 07` / `; ; a2`) let `sfdisk` auto-place `p1` at LBA 2048 and gave `p2` "the
rest" — `RESERVED_SECTORS` *minus* the 2048-sector start offset (6144 sectors), so the
boot partition came out 3 MiB instead of 4 and drifted with `p1`'s alignment.

### RAM budget

The stock `uboot.img`'s `mmcboot` hardcodes `mem=511M memmap=513M$511M` as a literal,
so the installer sees ~511 MiB, not the board's 1 GiB, and no shipped
`linux/u-boot.txt` can lift that ([ADR 0020 §3][adr-3], `docs/boot-chain.md` §4). The
payload transits RAM, so it must fit. `linux.img` (512 MiB apparent size, non-sparse on
FAT32) ships as `linux.img.gz` (~140 MiB) and is only expanded onto the exFAT card in
step 9. The rest of the base (~50 MB: MiSTer, `menu.rbf`, soundfonts, scripts) fits with
a wide margin; the optional `_Console` cores (~150–200 MB) may not.

Peak RAM use is the tmpfs copy (the copy-back target is the card). The tmpfs is sized
to `MemAvailable - RAM_RESERVE_KB` (96 MiB kept for the kernel and the script's own
working set), so a mis-estimate fails with a clean `ENOSPC` instead of OOM-hanging the
box. A real `du` of each piece then decides: if the full payload does not fit, the base
is copied and `_Console` is **skipped** with a loud message (`update_all.sh` on the
installed card fetches cores anyway); if even the base does not fit, `rescue`. The two
[boot files](#the-boot-files) (kernel ~11 MB, `menu.rbf` ~2.4 MB) live outside
`$SRC_PAYLOAD`, so they are measured explicitly and counted in the **base** and never
skipped; the cores give way first. The merged stage-1 cpio itself occupies ~3.2 MB of
the initramfs.

One harmless wrinkle: `du` reports **allocated** blocks, and a re-run reads the payload
off the full-size exFAT this installer made (128 KiB clusters on a 64 GB card) rather
than the shipped FAT32 (32 KiB), so the same tree measures bigger on the second pass.
The error is in the safe direction — a re-run can only skip cores a first run kept,
never the reverse.

The RAM copy's boot-critical files (`linux/linux.img.gz`, `linux/uboot.img`, the
kernel) are verified **before** anything on disk is destroyed; if that trips, the card is
still a bootable installer.

## First-boot splash

On a pristine card the install takes tens of seconds (about a minute on a real 64 GB
card) during which the board looks dead: no menu and, without a serial adapter, no
output. A user reasonably concludes it has hung and pulls the power — very likely during
the reformat. Everything in the splash section exists to make "it is working, wait"
observable. Background: [ADR 0020 §6][adr-6] (console + LED) and [§9][adr-9] (HDMI).

It has three channels:

1. **HDMI picture** via `itsalive` — [below](#hdmi-splash).
2. **Console progress UI** on the serial console, the documented triage channel.
3. **The HPS LED** — [below](#led).

The section between `# >>> SPLASH SECTION BEGIN` and `# >>> SPLASH SECTION END` is
extracted verbatim by `scripts/test-installer-splash.sh` and sourced under a POSIX
shell against a stubbed `/proc/uptime`, `/sys/class/leds` and a recording `itsalive`
stub. It must therefore reference nothing defined outside it, and the marker lines and
the retargeted variable names (`SPLASH_FLAG`, `SPLASH_HDMI_*`) must keep their exact
spelling. Every splash variable is pre-initialised so `set -u` is safe even if
`rescue()` fires during the early mounts, before `splash_init`; `splash_tty=0` until
proven otherwise keeps every drawing routine a no-op until then.

### A splash must never be able to fail an install

The hard rule ([ADR 0020 §6][adr-6], extended in [§9.3][adr-9.3]). No `set -e`; every
LED write is guarded and the sysfs paths are probed, never assumed; the heartbeat child
is stopped by a means that cannot hang the parent; every `itsalive` call is bracketed by
`timeout` and its exit status is only logged. If none of it can draw, the install still
runs to completion exactly as before.

### Console progress UI

Banner, ten numbered steps, a bar, percentage, elapsed time and a spinner. The status
line (`SPLASH_BAR_CELLS=28`, sized so it fits 80 columns) is rewritten in place with
`\r` and erased to end-of-line (`\033[K`) so a shorter label leaves no debris; `log()`
clears it, prints, and redraws it. The bar is pre-rendered once per step; per-second
frames only redraw the spinner and the clock. When stdout is not a tty (a captured
log), `splash_step` prints one plain line per step instead of animating, so log files
stay readable.

Elapsed time comes from `/proc/uptime` (`"1234.56 5678.90"`, split by `read`). The
spinner characters are always emitted as `printf '%s' <char>`, never as a bare format
string: `-` would be eaten as an option and the backslash escape-processed. The
backslash is written `"\\"` rather than `'\'` — identical in POSIX sh, but the quoted
form does not trip SC1003.

### LED

`/sys/class/leds/hps_led0` (DTS `gpio-leds hps0`, `&portb 24`,
`linux-patches/0004-dts-de10nano-MiSTer.patch`) is HPS-side GPIO driven by the kernel's
`gpio-leds` driver, so unlike the eight fabric-side `LED0..7` (which nothing in this
initramfs drives) it needs no bitstream. It is the only install-time signal a user with
no serial cable **and** no picture can see (a dark HDMI, or any installer before
2026-09-21), so it carries the state:

| LED | Meaning |
|---|---|
| blinking ~0.5 Hz | installing; all is well, leave it alone |
| solid on | **stopped and wants attention**: the install failed, or the card was already installed (the console and screen say which). The *only* state that means trouble, so nothing on the healthy path may park the LED lit |
| off | between two long phases, or finished and rebooting. Only long steps carry a heartbeat, so brief dark gaps are normal; the reboot into MiSTer tells "finished" apart |

The LED is taken off its DTS default `mmc0` trigger (`trigger=none`) for the duration,
on purpose: erratic activity flicker is indistinguishable from an ordinary boot, a
metronome is not. Nothing persists — `linux,default-trigger = "mmc0"` is re-applied at
probe, so the installed card gets its SD activity light back on the next boot. After
completion the LED stays dark until the installed system's own `mmc0` trigger lights it.

Only `hps_led*` is considered: other `/sys/class/leds` entries on a MiSTer belong to USB
gamepads (patches 0032/0033/0042, plus hid-nintendo's mainline-named player LEDs), and
blinking a user's controller to report SD-card progress would be nonsense. The LED is a
surface-mount part inside most cases — a known limitation, [ADR 0020 §6][adr-6].

### Heartbeat

`splash_tick` draws one frame (spinner, clock, LED toggle). It is called two ways: inline
from the polling loops that already `sleep 1` (so they animate for free, with no child
process), and from a background heartbeat child that brackets each long, silent,
blocking command (the RAM copy, the `dd`, the copy-back, the `zcat`).

The child runs while `$SPLASH_FLAG` (`/run/splash.run`) is non-empty. `splash_pulse_stop`
**truncates** the flag with `: >` and only then reaps the child with `wait` — and only
if the truncation is *observed* to have worked: otherwise the child would never exit and
a bare `wait` would hang the installer forever, which a cosmetic bug must not be able to
do. `/run` is ramfs, so that fallback is close to unreachable; it costs one `[`.

The child toggled the LED in a subshell, so the parent's `splash_led_on` is stale
afterwards; the stop re-asserts a known state, and that state is **off**, never on. The
short steps between two long ones are not bracketed, so whatever is parked there is
what the LED shows across them, and parking it on would light the "stopped, wants a
human" signal in the middle of a healthy install. `splash_step` always stops the
heartbeat first so the child can never interleave with what is printed next.

Terminal states: `splash_fail` (from `rescue` and the "interrupted" halt) stops the
heartbeat and leaves the LED **solid on**; `splash_done` draws the completion banner and
puts the LED out. Both also
replace the HDMI picture with text, because an "installing" picture that outlives the
install tells a user with no serial cable to keep waiting for a board that has stopped.

### HDMI splash

What changed to make a picture possible — `menu.rbf` at the FAT root configures the
fabric ([ADR 0020 §7][adr-7]); `itsalive` (`package/itsalive`,
[ItsAlive_MiSTer](https://github.com/mcfbytes/ItsAlive_MiSTer)) performs Main_MiSTer's
own register sequences without Main (video PLL and timings over the fabric mailbox, the
ADV7513 over I²C, then `UIO_SET_FBUF` to point the frame reader at `/dev/fb0`); and the
`ttyS0`-only console is irrelevant because the artwork is blitted straight into
`/dev/fb0` — is [ADR 0020 §9.1][adr-9]. The tool was verified on a DE10-Nano on
2026-09-21 with no Main on the card (ItsAlive_MiSTer
`docs/testlogs/2026-09-21-rig-first-light.md`).

**What is drawn.** A full-screen image — MiSTer Kun, "INSTALLING...", "DO NOT POWER
OFF", "it reboots itself when done" — pre-rendered per mode (1280×720, or 640×480) as
gzipped raw BGRX8888 into `/usr/share/mister-installer/splash-<WxH>.raw.gz` at build time
by `package/mister-initramfs/mister-initramfs.mk`, from the PNGs in `board/mister/de10nano/installer-splash/`
(sources and licence there). Per mode because the tool blits raw pixels and neither
scales nor decodes. `zcat | itsalive image -` means the raw frame (3.6 MB at 720p) never
exists uncompressed anywhere but the tool's stdin; `image` exiting 0 means the bytes
reached `/dev/fb0`, which after a successful `up` is the screen. If the frame is missing
or refused, a few lines of text go up instead. Progress is **not** mirrored to the
screen: the console UI and a blit fight over the same pixels, and "do not power off,
wait a minute" is the whole message.

**When.** `splash_hdmi_init` is the first thing `/init` does once `/proc`, `/sys` and
`/dev` are mounted and the command line is parsed (the mode knob lives there) — ahead of
the serial banner and the LED, because every moment before `up` is black screen for a
user with no serial cable. The fabric already holds `menu.rbf` from U-Boot, so nothing
later makes success more likely. Its log lines print plain because `splash_tty` is still
0. The console splash comes up right after, once `/proc` (uptime), `/sys` (the LED) and
`/run` (the heartbeat flag) exist. The picture stays until the reboot or a terminal
state.

**Call order.** `up` goes first and **alone** on the happy path: it carries the same
bitstream guard and exit codes as `probe` (ItsAlive_MiSTer `ARCHITECTURE.md` §7 guards
`hdmi`, `fb` and `up`), so a `probe` in front would only add a second exec and a second
I²C bus scan between power-on and the picture. `probe` runs **after** a failed `up`,
because its one line per finding ("no bitstream", "ADV7513 not found") is the diagnosis
a serial user needs when the screen stays dark. Not after a timeout (124): a wedged tool
gets one `SPLASH_HDMI_TIMEOUT` of the install's time, not two. After `up`, fbcon's
`cursor_blink` is set to 0, or fbcon would repaint a blinking cursor block over the
artwork about once a second; the knob does not survive the reboot, so it is set every
boot and never restored.

**HDMI is as optional as the LED.** The binary may be absent (a config without
`BR2_PACKAGE_ITSALIVE`), the fabric may hold no bitstream (QEMU, or a card whose
`menu.rbf` went missing — exit 10), the sink may reject the mode, or the tool may fail
in a way nobody predicted. So:

- `splash_hdmi_run` is the **only** way the script invokes `itsalive`; it returns 127
  when the binary is absent and otherwise the tool's (or `timeout`'s) status. Never call
  the binary directly — the timeout lives in that wrapper.
- `SPLASH_HDMI_TIMEOUT=15` seconds per call. `itsalive` bounds its own mailbox wait far
  tighter (exit 11); the bracket is the belt for the failure it did not foresee.
- The tool's stderr ("adv7513: 92 registers written", "no bitstream in the fabric") goes
  to `/run/splash-hdmi.out` and is replayed as `[installer] hdmi:` log lines, in order and
  without tearing the status line.
- `splash_hdmi_say` (`itsalive say`, painted by fbcon onto `/dev/tty1`) is a no-op until
  `up` has succeeded — before that `/dev/tty1` is a console nothing scans out. `--clear`
  erases the picture first and is passed only by the terminal states.

A missing picture costs the user a minute of doubt; a splash that could hang PID 1 would
cost them the card.

**The one knob.** `mister_installer_video=480p` on the kernel command line picks
`--mode 480p` and the 640×480 frame, for a sink that will not take 720p. A user reaches
it through `linux/u-boot.txt`'s `$v` on the shipped card (`docs/user/sdcard-flashing.md`).
It is harmless by construction — it picks between two video modes and nothing else — so,
unlike the [test hook](#test-hook), the command line alone is an acceptable gate. Any
other value is logged and 720p is used.


## Applet budget

Read this before editing the splash — several obvious implementations need applets the
stage-1 BusyBox does not ship. It (`board/mister/common/initramfs-busybox.config`, the
one BusyBox config every board's cpio uses since ADR 0033) has no `touch`, `kill`,
`usleep`, `date`, `seq`, `tr`, `basename`, `dirname` or `od`, and its `sleep` is
integer-only: `CONFIG_FEATURE_FANCY_SLEEP` is off, so `sleep 0.2` would parse as 0 and
**busy-spin a core** for the whole install. Consequently:

- the heartbeat child is stopped by truncating a flag file with `: >` (a pure shell
  redirection) and reaped with the ash builtin `wait` — not `kill` (no applet, and ash's
  builtin `kill` is gated behind `CONFIG_KILL`);
- elapsed time is read from `/proc/uptime` with the `read` builtin — not `date`;
- the bar is built by string concatenation in a loop — not `seq`/`tr`/`printf`;
- every frame delay is a whole number of seconds;
- ASCII art is emitted as `printf '%s\n' 'line' 'line' ...` (printf reuses the format
  per argument), so no line is ever escape-processed. Do not switch it to a heredoc or
  to escapes in a format string;
- paths are peeled with POSIX `${var%/*}` / `${var##*/}` in place of
  `basename`/`dirname`, and the MAC and disk id use `hexdump` instead of `od`;
- the MBR is assembled with `printf` octal escapes (BusyBox `printf` emits `\000` as a
  real NUL), so no `xxd`/`od` is needed there either.

The budget covers **applets**, not shell builtins: `true` and `false` are unconditional
ash builtins (`shell/ash.c` builtintab, outside any `#if`), so `|| true` is safe even
though `CONFIG_TRUE` is off — that symbol governs only `/bin/true`.

The budget is real but not fixed. ADR 0033 added `dd` (with `CONFIG_FEATURE_DD_IBS_OBS`
for `conv=notrunc,fsync`), `cmp`, `wc`, `hexdump`, `blockdev`, `blkid`, `cp`, `mv`, `du`,
`cut`, `reboot` and 64-bit shell maths — every one of them a few KB, and now on every
board's cpio. If a future revision needs another, turn its `CONFIG_` symbol on in that
file, list it in its header, and add it to `package/mister-initramfs/verify.sh`'s
installer applet list; do not contort the shell around its absence. Check the symbol
exists in the BusyBox being built: kconfig silently discards unknown symbols, so a typo
reads as "not set" — and `verify.sh` is what catches it.

## External programs

Beyond BusyBox, the installer runs exactly two binaries, both in the stage-1 cpio:

| Program | Where | Source |
|---|---|---|
| `mkfs.exfat` | `/usr/libexec/mister-installer/mkfs.exfat` — **off every PATH**, called by absolute path | `package/mister-initramfs-exfatprogs` (static, glibc), copied only with `BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER` |
| `itsalive` | `/usr/bin/itsalive` | `package/itsalive` (static, glibc) — **optional** at run time: probed for, every call under `timeout`, every status only logged. The exFAT repair uses the same binary |

`verify.sh` asserts that no exfatprogs tool but `fsck.exfat` sits in any `bin`/`sbin`
directory (ADR 0026), that `mkfs.exfat` is present and static under
`/usr/libexec/mister-installer/`, and that the installer directory does not exist at all
when the option is off. The partition table needs no program ([layout](#partition-layout));
the volume label is read with BusyBox `blkid`.

## Step notes

### Command line

Same discipline as stage-1: command-line driven, never positional, never globbing
(`set -f` around the word split, which *is* the parse). It is parsed before anything is
drawn because the HDMI mode knob lives there. `root=` is no longer read here: stage 1
resolved it (device path, or `LABEL=`/`UUID=` via `findfs`, with the `rootwait` loop) and
passes the block device as `$1`, which the installer checks is a block device and `p1`
of its disk.

### Source mount

Read-only: only `mister-payload/` and the two boot files are ever read from it, and a
partition about to be destroyed must not be dirtied. `exfat` is tried before `vfat`
(stock-init ordering); the shipped card is FAT32 so `vfat` wins, but exfat-first lets a
`resume` or `finish` card be recognised.

### Pre-seed

Optional files a user dropped at the root of the FAT card before first boot, mirroring
mr-fusion's pre-seed hooks: `wpa_supplicant.conf`, `_wpa_supplicant.conf`, `samba.sh`,
`_samba.sh`, `Scripts/`, `config/`. They are copied to `/run/preseed` in step 2 (before
the source is unmounted) and laid onto the finished card in step 10 — the Wi-Fi and
Samba files into `linux/` (both Samba names land as `linux/_samba.sh`), the two
directories merged onto the root with `cp -a`. Absence is normal; every failure is a
logged warning, never fatal. Because the FAT root they came from is reformatted in
step 6, step 8 keeps a copy on the new card in `linux/.mister-preseed/` before the
payload: step 10 applies them **from that copy**, so a `finish` boot after a cut still
applies them, and a `resume` boot captures them from there instead of the (gone) FAT
root. Step 10 removes the copy with the token.

### Per-board MAC

Every board otherwise shares the compiled-in fallback `ethaddr` `02:03:04:05:06:07`
(`docs/boot-chain.md` §3.1 entry 14). The installer generates a random
**locally-administered, unicast** MAC: first octet `|= 0x02` (local-admin bit set) and
`&= 0xFE` (multicast bit cleared) — the arithmetic equivalent of mr-fusion's
`b="2,6,a,e"` low-nibble trick, readable and awk-free. The six random bytes come from
`hexdump -n6 -e '6/1 "%02x "' /dev/urandom`; word-splitting its hex-only output into
`$1..$6` is the point, and there is nothing to glob. An existing `linux/u-boot.txt` is
kept, so a `finish` boot after a cut does not change a MAC the first attempt already
wrote. A failure is not fatal (the board boots with the shared fallback) but is logged
loudly so it can be fixed by hand. The file ends in a newline (see
[load-bearing facts](#load-bearing-facts)).

## Commit phase

Step 10 is `finish_install`, and it is also the whole of a `finish` boot, so every part
of it is idempotent.

**The `.gz` removal is verified.** Until PR #76 this `rm -f` was a silent
command-not-found no-op, so every installed card kept the whole gzip, and once there was
a splash it also printed `rm: not found` across it. The real lesson was not "rm was
missing" but "an unchecked cleanup silently no-opped for a whole release", so the
installer checks the file is gone and otherwise truncates it and says so — releasing the
blocks either way. Removing it is also what moves the card from `resume` to `finish`:
before it a cut re-installs, after it a cut only finishes.

**Moves, never copies.** The bytes are already on this filesystem; rewriting 150+ MiB
would hand back every second the reorder bought. Two collisions are expected, both
because step 7 already wrote there:

- `linux/` — an existing **non-empty directory**. `rename(2)` refuses that
  (`ENOTEMPTY`) and BusyBox `mv` does not fall back, so this one directory is descended
  and its children moved individually.
- `menu.rbf` — an existing regular file. `rename(2)` replaces it silently, and it is
  byte-identical anyway ([ADR 0020 §7][adr-7]); `mv -f` so BusyBox never prompts.

After the moves, `linux/linux.img`, `linux/uboot.img` and `linux/zImage_dtb` must all be
present and non-empty; the pre-seed and MAC follow, then the payload directory, the
pre-seed copy and the install token are removed (a failure there is logged clutter, not
a defect).

**The commit point** is spending the flag. The data partition is synced and unmounted
first, the flag is re-checked as armed, and `flag_spend` zeroes the block at LBA 1024
(`dd conv=notrunc,fsync`, buffer cache flushed) and requires the probe to answer
`spent`. It never touches sector 0. Before it, the next boot finishes this install;
after it, the next boot is stage 1's normal one, whatever the files on `p1` look like.

**Housekeeping strictly after.** `flag_remove_entry` rewrites sector 0 with bytes
478–493 zeroed — one 512-byte write through `mbr_commit`, verified by reading it back —
so the finished card has the stock two partitions. A failure is only a warning: a spent
entry 3 already boots normally. The table is re-read and the probe must not say `armed`
(a `rescue` if it somehow does). Then the completion banner, `sync`, and `reboot -f` — the direct `reboot(2)`
syscall. Plain `reboot` would try to signal an init process, but the installer *is*
PID 1 and there is no init to signal, so it would hang. If `reboot` ever returns,
`rescue` runs rather than falling off the end of PID 1.

## Test hook

`stop_after TAG` simulates a power cut at a named point, so that
`scripts/test-installer-recovery.sh` can prove the [recoverability](#recoverability)
invariants: it syncs, reboots immediately (`reboot -f`, with `rescue` if that returns)
and leaves the card in exactly the state that point should leave it in.

**The command line is not the gate.** An earlier revision fired on the
`mister_installer_stop_after=` token alone and called that "inert on real hardware". It
is not: `mmcboot` interpolates `$v` into bootargs, `scrtest` imports `/linux/u-boot.txt`
off `p1` before `mmcboot` runs, the shipped `p1` is FAT32 any user can write to, and a
stop at `recoverable` or `payload-partial` leaves a card needing a re-flash — the exact
harm the ordering removes ([ADR 0020 §8.6][adr-8.6]). **The gate is a marker file in the
initramfs, `/.installer-test-hook`**, which no shipped image contains:
`scripts/lib/installer-qemu-kernel.sh` appends it as a second cpio archive when it builds
the harness kernel, leaving the shipped cpio byte-for-byte unchanged. The token only
chooses **which** point to stop at; without the marker it is logged and ignored.

| Tag | Stops after | Next boot (scenario) |
|---|---|---|
| `uboot-staged` | `uboot.img` is at the end of the card, before the MBR write | `fresh` again (K) |
| `bootloader` | the new MBR, with `uboot.img` verified in the new `0xA2` partition | `fresh` again (F) |
| `recoverable` | the kernel and token are back on the new `p1` | rescue, re-flash (C) |
| `payload-partial` | part of the copy-back, so `mister-payload.part/` stays | halt, re-flash (B) |
| `payload-copied` | the copy-back is renamed to `mister-payload/` | `resume` (A) |
| `expanded` | `linux/linux.img` exists, payload still complete | `resume` (E) |
| `moved` | the payload moved into place, before the commit | `finish` (G) |
| `committed` | flag block wiped, entry 3 not yet removed | normal boot, probe says `spent` (H) |

All eight are exercised by that harness; keep it that way — a tag nothing stops at is a
branch nothing tests. Scenarios D, I and J then prove the other direction: a finished
card, a payload-shaped card without the flag, and one with a forged flag block all go
through stage 1's normal path and the MBR is never written. L and N are the `foreign`
cards (an exFAT with a payload but not this installer's label, and a `p1` the user
reformatted): the flag is spent, the MBR and every byte of `p1` are unchanged, and the
next boot is the normal one. M is an installed card armed again: `finish` with nothing
to move, then a normal boot.

## Rescue

Every fatal error calls `rescue "<message>"`. It first runs `splash_fail` — stopping the
heartbeat before printing (a running child would redraw its status line over the
banner), parking the LED solid on (instead of cheerfully blinking "all is well" next to a
failed install) and replacing the HDMI picture with a "FAILED — re-flash" message. It
then prints everything a serial-console user needs to tell **where** it died (the
`$stage` string, updated before each phase), what the card looks like now (command
line, disk, data partition and filesystem type, the card state, `p1`/`p2`/flag nodes,
whether cores were kept, `/proc/partitions`, `/proc/mounts`, the last 25 kernel
messages) and how to recover: re-flash `sdcard.img` with Etcher or `dd` — **required** if
the card had already been reformatted.

Both the failure path and the interrupted-copy halt end in `respawn_shell`, which
respawns `setsid cttyhack /bin/sh` forever: PID 1 must never exit.

[adr]: decisions/0020-sdcard-exfat-reformat-installer.md
[adr33]: decisions/0033-one-initramfs-installer-in-stage-1.md
[adr-1.1]: decisions/0020-sdcard-exfat-reformat-installer.md#11-why-grow-the-filesystem-does-not-work
[adr-3]: decisions/0020-sdcard-exfat-reformat-installer.md#3-the-ram-transit-constraint-and-the-finding-that-resolves-it
[adr-6]: decisions/0020-sdcard-exfat-reformat-installer.md#6-first-boot-feedback-a-console-ui-plus-one-led-deliberately-not-a-picture
[adr-7]: decisions/0020-sdcard-exfat-reformat-installer.md#7-menurbf-ships-at-the-fat-root-so-the-fpga-is-configured-during-the-install
[adr-8]: decisions/0020-sdcard-exfat-reformat-installer.md#8-the-install-is-reordered-so-the-card-is-recoverable-in-seconds-not-at-the-end
[adr-8.3.1]: decisions/0020-sdcard-exfat-reformat-installer.md#831-what-is-left-stated-exactly
[adr-8.6]: decisions/0020-sdcard-exfat-reformat-installer.md#86-how-it-is-tested
[adr-9]: decisions/0020-sdcard-exfat-reformat-installer.md#9-the-hdmi-splash-itsalive-paints-the-picture-6-said-we-could-not
[adr-9.3]: decisions/0020-sdcard-exfat-reformat-installer.md#93-the-hard-rule-extended
[adr-cons]: decisions/0020-sdcard-exfat-reformat-installer.md#consequences
