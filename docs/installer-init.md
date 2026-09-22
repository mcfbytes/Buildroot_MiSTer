# The SD-card installer `/init`

`board/mister/de10nano/installer-overlay/init` is PID 1 of the first-boot installer that
turns a freshly flashed `sdcard.img` into a full-size exFAT MiSTer card (TASKS P5.3,
PLAN §8, ADR 0017 §4, [ADR 0020][adr]). This page carries the explanation that used to
live in the script's own comments; the script keeps one- or two-line pointers into the
headings below.

> **THIS FILE CAN BRICK THE BOARD.** Read this page, [ADR 0020][adr] and
> `docs/boot-chain.md` §2.1/§3.1/§5 before touching a single line of it. Every edit must
> keep `shellcheck -s sh -x`, `dash -n`, `scripts/test-installer-splash.sh`,
> `scripts/test-installer-recovery.sh` and `scripts/test-sdcard-install.sh` passing.

## What it is

The shipped `sdcard.img` is a *small* dd/Etcher-writable card. On the first boot the
stock U-Boot (`uboot.img`, byte-identical, in the `0xA2` boot partition) loads
`/linux/zImage_dtb` off the FAT32 data partition (`p1`). On the pristine card that
`zImage_dtb` is the **installer** kernel: our kernel relinked with this initramfs
embedded. So `/init` runs entirely from RAM — the initramfs is a ramfs, so nothing done
to the SD card pulls the rug out from under the running system. That is the whole reason
the reformat-in-place trick works.

MiSTer's data partition is exFAT, which Linux cannot grow in place, so "auto-expand to
fill the card" is a **reformat**, exactly like mr-fusion
(`MiSTer-devel/mr-fusion`, `builder/scripts/S99install-MiSTer.sh`, which this script is
adapted from). Why: [ADR 0020 §1.1][adr-1.1].

It is plain POSIX sh / BusyBox ash — no bashisms. There is deliberately **no `set -e`**
(only `set -u`): every failure is handled explicitly, either by `rescue` or by a logged
warning, and nothing cosmetic may abort the install.

## The ten steps

These are exactly the steps the console splash counts off (`1/10` .. `10/10`), so they
are what a user with a serial cable sees. There is **one** numbering in the script, its
section markers, this page and [ADR 0020 §8.2][adr-8]; keep every reference on it, and
keep `SPLASH_TOTAL` equal to the highest `splash_step` call
(`scripts/test-installer-splash.sh` enforces that).

1. Mount the shipped FAT32 `p1` **read-only** and work out which
   [state](#the-four-card-states) the card is in.
2. Read the payload: check it is complete, and capture any user
   [pre-seed](#pre-seed) dropped at the FAT root before first boot.
3. Copy `mister-payload/` into a RAM tmpfs, **alongside** the installer's own
   `/linux/zImage_dtb` and the FAT root's `/menu.rbf` — the two files that let a
   half-finished card boot back into this installer.
4. `sfdisk` the **whole** card to full size: `p1` = exFAT data filling the card minus a
   small reserved tail, `p2` = type `0xA2` for U-Boot ([layout](#partition-layout)).
5. `dd` `uboot.img` raw to the new `0xA2` `p2` **immediately** — seconds after the
   repartition the card can reach U-Boot again.
6. `mkfs.exfat -n MiSTer_Data` the new `p1` and mount it `-t exfat` (in-kernel driver,
   ADR 0019 — no FUSE, unlike mr-fusion).
7. Write the installer's **own** `zImage_dtb` and `menu.rbf` onto the fresh `p1` before
   any payload byte — from this instant a power cut boots straight back into the
   installer rather than into nothing.
8. Copy the payload back out of RAM into `mister-payload.part/` and, once complete,
   **rename** it to `mister-payload/` (a directory-entry update, which is what makes a
   partial copy detectable on the next boot).
9. `zcat mister-payload/linux/linux.img.gz > linux/linux.img` straight onto the card —
   the 512 MiB image lands on disk, never in RAM ([RAM budget](#ram-budget)) — with the
   payload left complete for the whole decompression.
10. [Commit](#commit-phase): drop the redundant `.gz`, rename the payload's entries into
    their final places, apply the pre-seed, write a unique per-board [MAC](#per-board-mac)
    into `linux/u-boot.txt`, rename the **real** kernel over `linux/zImage_dtb` as the
    very last act, then `sync` and `reboot -f`.

Because step 10 puts the real kernel at `/linux/zImage_dtb`, the next boot loads MiSTer,
not this installer. That kernel swap is the **primary** re-run guard
([ADR 0020 §2.1][adr-2.1]); the [card-state checks](#the-re-run-guard) are belt.

## Recoverability

Why steps 5 and 7 sit where they do (issue #185) is [ADR 0020 §8][adr-8]; the short
version: the old order (`dd uboot.img` last, no kernel on `p1` until the copy-back) made
the entire ~1-minute install one unbroken brick window, and it coincided with the minute
in which the board looks dead. The current order attacks the harm rather than the
visibility; the [HDMI splash](#hdmi-splash) separately shrinks the temptation to pull
the power.

### The four card states

At any instant a power cut can happen, the card is in exactly one of four
self-describing states, and the next boot's "what is on this card?" block reads which
([ADR 0020 §8.3][adr-8]). Read this before changing any condition there.

| On the card | Next boot |
|---|---|
| `mister-payload/` present and complete | full, unattended re-install. The normal interrupted state; costs one more run |
| `mister-payload.part/` instead | halt ("INTERRUPTED … re-flash"): the copy-back's source lived in RAM and is gone, and a reboot would loop forever |
| neither, and no `linux/linux.img` | halt: formatted but never populated (cut between `mkfs.exfat` and the copy-back); same reason |
| neither, `linux/linux.img` present | halt with the "already provisioned" banner |

The **commit point** is the single `mv` of the real `linux/zImage_dtb` over the
installer's own. Before it the card boots this installer; after it, MiSTer.

Two windows still cost a re-flash — `mkfs.exfat` until the installer kernel lands on
`p1` (a few seconds; the only hard one), and the commit phase — both stated exactly in
[ADR 0020 §8.3.1][adr-8.3.1]. The first does **not** start at `sfdisk`: `sfdisk` only
rewrites the MBR and the new `p1` still starts at LBA 2048, so the shipped FAT32 is
intact under the enlarged entry and an interrupt there simply re-runs
(`scripts/test-installer-recovery.sh` proves it). **Do not put anything slow inside
either window.**

### The recovery files

The FAT root's own `linux/zImage_dtb` is the kernel running this very script, and
`menu.rbf` is what U-Boot's `fpgaload` puts in the fabric ([ADR 0020 §7][adr-7]).
Neither is part of `mister-payload/`. They are staged in RAM in their own directory
(`$RAM_INSTALLER`, separate from `$RAM_PAYLOAD`) so the payload's copy-back glob can
never pick them up — a separate directory rather than a naming convention, so no
accident can. Step 7 writes both onto the freshly formatted partition before anything
else, which turns "mid-install" from a brick into a card that simply runs the installer
again. Neither is fatal by absence — a card without them still installs, it just
cannot recover from an interruption — so both are probed and warned about, never
assumed. Cost: ~15 MB written once; the real kernel is renamed over the installer's at
the commit point, so nothing of it survives a completed install.

### The re-run guard

**Already provisioned** = exFAT, labelled `MiSTer_Data`, a real `linux/linux.img`, and
**no payload directory under either name**. Re-running would destroy a good card, so it
stops. The no-payload-directory clause is load-bearing: without it the guard fires
mid-commit, on a card that still has a complete payload and would have finished by
itself ([ADR 0020 §8.4][adr-8.4]).

The halt is deliberately **not** `rescue()`: its "FAILED / Nothing is installed" banner
would be wrong (the card *is* installed). This throwaway OS cannot hand off to MiSTer,
and a reboot would loop into the same installer, so it prints an accurate message, parks
the LED solid on and respawns a console shell.

When no payload exists under either name, there are three causes and three messages,
most specific first — "wrong card?" on a card that is plainly ours, halfway through our
own install, sends a user hunting for a hardware fault:

- `linux/linux.img` present → interrupted at its very last step;
- exFAT labelled `MiSTer_Data` → interrupted before the payload was copied;
- otherwise → "wrong card?".

## Load-bearing facts

Get one of these wrong and you brick a card.

- **Partition slots are fixed.** Shipped and final cards both use `p1` = data,
  `p2` = `0xA2`: the stock U-Boot's compiled-in env has `mmcroot=/dev/mmcblk0p1` and
  `load mmc 0:1 ... $bootimage`, i.e. it *always* reads the kernel from partition 1
  (`docs/boot-chain.md` §3.1 entries 16–17, §4), and the BootROM independently scans the
  MBR for the first `0xA2` partition (§2.1). The final `sfdisk` table must reproduce
  this. That is also why `/init` refuses a `root=` that is not `p1` of its disk.
- **The `0xA2` partition moves.** Repartitioning creates a new, empty `p2`; until
  `dd uboot.img` succeeds the card cannot boot. It is the single most brick-critical
  step, it is done from the verified RAM copy, its exit status is checked, and on failure
  it is a loud `rescue` with a re-flash hint — never a reboot into a brick. It is the
  **first** thing after `sfdisk`; do not let an edit push it back down the file.
- **`u-boot.txt` must end in a newline.** U-Boot's `env import -t` (no size argument)
  scans for `\n` followed by `\0` (`docs/boot-chain.md` §4, U-Boot
  `cmd/nvedit.c:1049-1066`). The MAC `printf` supplies it.
- **Memory is capped at 511 MiB** — see [RAM budget](#ram-budget).
- **Defensive like the stage-1 init** (`board/mister/common/initramfs-overlay/init`):
  early `proc`/`sys`/`dev` mounts, the device taken from the command line (never
  hardcoded), and on any fatal error a banner and a respawning [rescue shell](#rescue).
  PID 1 must never exit — that is an instant kernel panic.
- **Never repartition the wrong disk.** The whole-disk device is the
  `/sys/block/<disk>/` directory that contains the data partition's directory —
  authoritative across mmcblk/sd/nvme/usb, with no name parsing. Partition nodes then
  follow the kernel's rule: `p<N>` when the disk name ends in a digit (`mmcblk0p1`,
  `nvme0n1p1`), else `<N>` (`sda1`).

### Partition layout

`p1` runs from the 1 MiB-aligned start (`P1_START_SECTORS=2048`, matching both
`sfdisk`'s default and `genimage-sdcard.cfg`'s `align = 1M`) to the reserved tail;
`p2` is **exactly** `RESERVED_SECTORS=8192` 512-byte sectors (4 MiB; `uboot.img` is
~503 KiB) at the very end, matching `genimage-sdcard.cfg`'s `size = 4M` byte-for-byte.
`label: dos` forces a fresh MBR (never GPT) whatever the shipped card carried;
`type=7` is exFAT/NTFS (mr-fusion parity), `type=a2` the SPL partition.

All three numbers are computed explicitly. mr-fusion's empty-field form
(`; size; 07` / `; ; a2`) let `sfdisk` auto-place `p1` at LBA 2048 and gave `p2` "the
rest" — `RESERVED_SECTORS` *minus* the 2048-sector start offset (6144 sectors), so the
boot partition came out 3 MiB instead of 4 and drifted with `p1`'s alignment.

### RAM budget

The stock `uboot.img`'s `mmcboot` hardcodes `mem=511M memmap=513M$511M` as a literal,
so the installer sees ~511 MiB, not the board's 1 GiB, and no shipped
`linux/u-boot.txt` can lift that ([ADR 0020 §3][adr-3], `docs/boot-chain.md` §4). The
payload transits RAM, so it must fit. `linux.img` (512 MiB apparent size, non-sparse on
FAT32) ships as `linux.img.gz` (~80 MiB) and is only expanded onto the exFAT card in
step 9. The rest of the base (~60 MB: MiSTer, `menu.rbf`, soundfonts, scripts, the real
kernel) fits with a wide margin; the optional `_Console` cores (~150–200 MB) may not.

Peak RAM use is the tmpfs copy (the copy-back target is the card). The tmpfs is sized
to `MemAvailable - RAM_RESERVE_KB` (96 MiB kept for the kernel and the script's own
working set), so a mis-estimate fails with a clean `ENOSPC` instead of OOM-hanging the
box. A real `du` of each piece then decides: if the full payload does not fit, the base
is copied and `_Console` is **skipped** with a loud message (`update_all.sh` on the
installed card fetches cores anyway); if even the base does not fit, `rescue`. The two
[recovery files](#the-recovery-files) (installer kernel ~11 MB, `menu.rbf` ~2.4 MB) live
outside `$SRC_PAYLOAD`, so they are measured explicitly and counted in the **base** —
~13 MB against ~400 MB of headroom, and never skipped; the cores give way first.

One harmless wrinkle: `du` reports **allocated** blocks, and a re-run reads the payload
off the full-size exFAT this installer made (128 KiB clusters on a 64 GB card) rather
than the shipped FAT32 (32 KiB), so the same tree measures bigger on the second pass.
The error is in the safe direction — a re-run can only skip cores a first run kept,
never the reverse.

The RAM copy's boot-critical files (`linux/linux.img.gz`, `linux/zImage_dtb`,
`linux/uboot.img`) are verified **before** anything on disk is destroyed; if that trips,
the card is still a bootable installer.

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

Terminal states: `splash_fail` (from `rescue` and the "interrupted" halt) and
`splash_halt_ok` (already provisioned) stop the heartbeat and leave the LED **solid
on**; `splash_done` draws the completion banner and puts the LED out. All three also
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
by `installer-post-build.sh`, from the PNGs in `board/mister/de10nano/installer-splash/`
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
installer does not ship. The installer BusyBox (`installer-busybox.config`) has no
`touch`, `kill`, `usleep`, `date`, `seq`, `tr`, `basename`, `dirname` or `od`, and its
`sleep` is integer-only: `CONFIG_FEATURE_FANCY_SLEEP` is off, so `sleep 0.2` would parse
as 0 and **busy-spin a core** for the whole install. Consequently:

- the heartbeat child is stopped by truncating a flag file with `: >` (a pure shell
  redirection) and reaped with the ash builtin `wait` — not `kill` (no applet, and ash's
  builtin `kill` is gated behind `CONFIG_KILL`) and not `rm`;
- elapsed time is read from `/proc/uptime` with the `read` builtin — not `date`;
- the bar is built by string concatenation in a loop — not `seq`/`tr`/`printf`;
- every frame delay is a whole number of seconds;
- ASCII art is emitted as `printf '%s\n' 'line' 'line' ...` (printf reuses the format
  per argument), so no line is ever escape-processed. Do not switch it to a heredoc or
  to escapes in a format string;
- paths are peeled with POSIX `${var%/*}` / `${var##*/}` in place of
  `basename`/`dirname`, and the MAC uses `hexdump` instead of `od`;
- the HDMI half is the one deliberate exception: it needs `timeout` (`CONFIG_TIMEOUT`,
  costed in `installer-busybox.config`'s header) and `zcat`, which the `linux.img`
  expansion already ships.

The budget covers **applets**, not shell builtins: `true` and `false` are unconditional
ash builtins (`shell/ash.c` builtintab, outside any `#if`), so `|| true` is safe even
though `CONFIG_TRUE` is off — that symbol governs only `/bin/true`.

The budget is real but not fixed: `rm` (~1 KB) was added in PR #76 because `/init`
genuinely needed it, and `mv` for the recoverable ordering (the `.part` rename and the
commit renames are what make a partial copy detectable and keep the commit from
re-writing 150+ MiB) — [ADR 0020 §8.5 and Consequences][adr-cons]. If a future revision
needs an applet, turn its `CONFIG_` symbol on in `installer-busybox.config` and justify
it in that file's header; do not contort the shell around its absence. Check the symbol
exists in the BusyBox being built: kconfig silently discards unknown symbols, so a typo
reads as "not set".

## External programs

Beyond the stage-1 BusyBox applet set:

| Program | Source |
|---|---|
| `sfdisk` | `BR2_PACKAGE_UTIL_LINUX` + `_BINARIES` (`configs/mister_installer_defconfig`) |
| `mkfs.exfat` | `BR2_PACKAGE_EXFATPROGS` |
| `itsalive` | `BR2_PACKAGE_ITSALIVE` — **optional** at run time: probed for, every call under `timeout`, every status only logged |
| `sh` (ash + test + math), `mount`, `umount`, `mkdir`, `printf`, `sleep`, `sync`, `findfs`, `setsid`, `cttyhack`, `cat`, `ls`, `tail`, `dmesg` | BusyBox, already in stage-1's set |
| `cp`, `du`, `dd`, `cut`, `reboot`, `blkid`, `blockdev`, `hexdump`, `rm`, `mv`, `timeout`, `zcat` | BusyBox, added by `installer-busybox.config` |

`blkid`/`blockdev`/`hexdump` may come from BusyBox or util-linux; only `sfdisk` and
`mkfs.exfat` must be real external binaries. The console/LED half of the splash adds
**nothing** to this list (shell builtins plus `printf` and `sleep`); the HDMI half adds
exactly `itsalive` and `timeout`.

## Step notes

### Command line

Same discipline as stage-1: command-line driven, never positional, never globbing
(`set -f` around the word split, which *is* the parse). It is parsed before anything is
drawn because the HDMI mode knob lives there; the parse is pure shell, and the checks
that can fail on its result (`root=`) wait until the console splash is up to say so.
`root=` names the data partition (`p1`) as a device path or `LABEL=`/`UUID=` via
`findfs`, and `/init` waits up to `DEV_WAIT` (30) seconds for slow SD/USB enumeration.

### Source mount

Read-only: only `mister-payload/` is ever read from it, and a partition about to be
destroyed must not be dirtied. `exfat` is tried before `vfat` (stock-init ordering); the
shipped card is FAT32 so `vfat` wins, but exfat-first lets the re-run guard recognise an
installed card.

### Pre-seed

Optional files a user dropped at the root of the FAT card before first boot, mirroring
mr-fusion's pre-seed hooks: `wpa_supplicant.conf`, `_wpa_supplicant.conf`, `samba.sh`,
`_samba.sh`, `Scripts/`, `config/`. They are copied to `/run/preseed` in step 2 (before
the source is unmounted) and laid onto the finished card in step 10 — the Wi-Fi and
Samba files into `linux/` (both Samba names land as `linux/_samba.sh`), the two
directories merged onto the root with `cp -a`. Absence is normal; every failure is a
logged warning, never fatal.

### Per-board MAC

Every board otherwise shares the compiled-in fallback `ethaddr` `02:03:04:05:06:07`
(`docs/boot-chain.md` §3.1 entry 14). `/init` generates a random **locally-administered,
unicast** MAC: first octet `|= 0x02` (local-admin bit set) and `&= 0xFE` (multicast bit
cleared) — the arithmetic equivalent of mr-fusion's `b="2,6,a,e"` low-nibble trick,
readable and awk-free. The six random bytes come from `hexdump -n6 -e '6/1 "%02x "'
/dev/urandom`, the idiom `installer-busybox.config` picked over `CONFIG_AWK`;
word-splitting its hex-only output into `$1..$6` is the point, and there is nothing to
glob. A failure is not fatal (the board boots with the shared fallback) but is logged
loudly so it can be fixed by hand. The file ends in a newline (see
[load-bearing facts](#load-bearing-facts)).

## Commit phase

Step 10 is renames, and the last of them is what turns the card from an installer into
a MiSTer ([ADR 0020 §8.3.1][adr-8.3.1]).

**The window opens at the `rm` of `linux/linux.img.gz`, not at the first rename.** That
`rm` is what first makes `mister-payload/` incomplete, and incomplete is what the next
boot's completeness probe keys on; from there to the final `mv` the card is neither
re-runnable nor installed (it boots the installer, which halts honestly). Every
operation in the phase is therefore a directory-entry update — fractions of a second.
Do not put anything slow in it, and do not add a write above that `rm` expecting it to
be outside the window; it would not be. Likewise the `zcat` of step 9 deliberately
leaves the `.gz` in place so the longest step of the install stays fully re-runnable.

**The `.gz` removal is verified.** Until PR #76 this `rm -f` was a silent
command-not-found no-op (`# CONFIG_RM is not set`), so every installed card kept the
whole ~80 MiB gzip, and once there was a splash it also printed `rm: not found` across
it. The real lesson was not "rm was missing" but "an unchecked cleanup silently no-opped
for a whole release", so `/init` now checks the file is gone and otherwise truncates it
and says so — releasing the blocks either way.

**Moves, never copies.** The bytes are already on this filesystem; rewriting 150+ MiB
would hand back every second the reorder bought. Two collisions are expected, both
because step 7 already wrote there:

- `linux/` — an existing **non-empty directory**. `rename(2)` refuses that
  (`ENOTEMPTY`) and BusyBox `mv` does not fall back, so this one directory is descended
  and its children moved individually.
- `menu.rbf` — an existing regular file. `rename(2)` replaces it silently, and it is
  byte-identical anyway ([ADR 0020 §7][adr-7]); `mv -f` so BusyBox never prompts.

`linux/zImage_dtb` is skipped there on purpose: it **is** the commit point. After the
moves, `linux/linux.img` and `linux/uboot.img` are verified; the pre-seed and MAC follow.

**The commit point** is one rename of the payload's `linux/zImage_dtb` over the
installer's. Everything else is already in place and flushed; nothing slow, conditional
or able to half-succeed goes between the `sync` before it and the `sync` after it.

**Housekeeping strictly after.** The now-empty payload directory is removed only after
the commit: before it, "payload dir gone" plus "installer kernel still in place" would
look provisioned to the re-run guard while still booting the installer — worse than a
stray directory. If the removal fails the card is already a working MiSTer that never
runs this again, so it is logged as clutter, not treated as a defect
([ADR 0020 §8.4][adr-8.4]).

Finally the data filesystem is synced and unmounted and `/init` calls `reboot -f` — the
direct `reboot(2)` syscall. Plain `reboot` would try to signal an init process, but
`/init` *is* PID 1 and there is no init to signal, so it would hang. If `reboot` ever
returns, `rescue` runs rather than falling off the end of PID 1.

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
the harness kernel, leaving the installer cpio and `/init` byte-for-byte unchanged. The
token only chooses **which** point to stop at; without the marker it is logged and
ignored.

| Tag | Stops after |
|---|---|
| `bootloader` | `uboot.img` is in the new `0xA2` partition |
| `recoverable` | the installer's own kernel is back on the new `p1` |
| `payload-partial` | part of the copy-back, so `mister-payload.part/` stays |
| `payload-copied` | the copy-back is renamed to `mister-payload/` |
| `expanded` | `linux/linux.img` exists — the state that fooled the old re-run guard |

All five are exercised by that harness; keep it that way — a tag nothing stops at is a
branch nothing tests.

## Rescue

Every fatal error calls `rescue "<message>"`. It first runs `splash_fail` — stopping the
heartbeat before printing (a running child would redraw its status line over the
banner), parking the LED solid on (instead of cheerfully blinking "all is well" next to a
failed install) and replacing the HDMI picture with a "FAILED — re-flash" message. It
then prints everything a serial-console user needs to tell **where** it died (the
`$stage` string, updated before each phase), what the card looks like now (command
line, `root=`, disk, data partition and filesystem type, new `p1`/`p2`, whether cores
were kept, `/proc/partitions`, `/proc/mounts`, the last 25 kernel messages) and how to
recover: re-flash `sdcard.img` with Etcher or `dd` — **required** if the card had
already been reformatted.

Both the failure path and the benign halts end in `respawn_shell`, which respawns
`setsid cttyhack /bin/sh` forever: PID 1 must never exit.

[adr]: decisions/0020-sdcard-exfat-reformat-installer.md
[adr-1.1]: decisions/0020-sdcard-exfat-reformat-installer.md#11-why-grow-the-filesystem-does-not-work
[adr-2.1]: decisions/0020-sdcard-exfat-reformat-installer.md#21-re-run-safety-is-structural-not-a-flag
[adr-3]: decisions/0020-sdcard-exfat-reformat-installer.md#3-the-ram-transit-constraint-and-the-finding-that-resolves-it
[adr-6]: decisions/0020-sdcard-exfat-reformat-installer.md#6-first-boot-feedback-a-console-ui-plus-one-led-deliberately-not-a-picture
[adr-7]: decisions/0020-sdcard-exfat-reformat-installer.md#7-menurbf-ships-at-the-fat-root-so-the-fpga-is-configured-during-the-install
[adr-8]: decisions/0020-sdcard-exfat-reformat-installer.md#8-the-install-is-reordered-so-the-card-is-recoverable-in-seconds-not-at-the-end
[adr-8.3.1]: decisions/0020-sdcard-exfat-reformat-installer.md#831-what-is-left-stated-exactly
[adr-8.4]: decisions/0020-sdcard-exfat-reformat-installer.md#84-the-re-run-guard-had-to-be-re-keyed
[adr-8.6]: decisions/0020-sdcard-exfat-reformat-installer.md#86-how-it-is-tested
[adr-9]: decisions/0020-sdcard-exfat-reformat-installer.md#9-the-hdmi-splash-itsalive-paints-the-picture-6-said-we-could-not
[adr-9.3]: decisions/0020-sdcard-exfat-reformat-installer.md#93-the-hard-rule-extended
[adr-cons]: decisions/0020-sdcard-exfat-reformat-installer.md#consequences
