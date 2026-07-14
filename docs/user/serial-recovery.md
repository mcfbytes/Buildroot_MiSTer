# Serial-console recovery — for a box that won't boot

If your MiSTer isn't reaching the menu after an update, this is the calm, methodical
path back. Most of the time the fix doesn't require touching the SD card's raw boot area
at all — read through the "what you'll see" section first so you know which tier of fix
you actually need before you do anything.

Nothing below is destructive if followed in order: connecting a serial cable is
read/observe-only, and Tier 1 recovery below only touches files on the FAT partition you
can already see from a normal computer.

---

## What you need

- A **USB-to-TTL serial adapter set to 3.3V logic levels** (an FTDI FT232-family cable, a
  CP2102 board, or similar — the same kind of cable used for Raspberry Pi console access).
  **Do not use an RS-232 adapter or a 5V-logic adapter** — the DE10-Nano's UART is 3.3V
  TTL, and 5V/RS-232 signaling can damage the board.
- Three wires: adapter TX → board RX, adapter RX → board TX, and a shared GND. **Never
  connect the adapter's 5V/VCC pin to the board.**
- A terminal program on your computer: `screen`, `minicom`, `picocom` (Linux/macOS), or
  PuTTY (Windows).

**On the physical pins:** the DE10-Nano's HPS UART is exposed on the `GPIO_0` 40-pin
expansion header. Community documentation for this board commonly cites `GPIO_0` pin 15
as UART TX and pin 16 as UART RX, with any GND pin on the same header (e.g. pin 9) usable
as ground. **Cross-check this against your specific board's silkscreen labeling or the
Terasic DE10-Nano User Manual's `GPIO_0` pinout diagram before connecting** — this project
verified the *software* side (baud rate, console device, DTB `stdout-path`) directly from
its own kernel/DTB/U-Boot configuration, but the *physical pin* mapping above is
general DE10-Nano hardware documentation, not something re-verified against this
project's own sources. Getting TX/RX backwards will not damage anything at matched 3.3V
logic levels — worst case, you'll simply see no data flow until you swap the two wires.

---

## Terminal settings

```
Baud rate:     115200
Data bits:     8
Parity:        None
Stop bits:     1
Flow control:  None
```

(This is verified directly from this project's own boot configuration: the kernel command
line carries `console=ttyS0,115200` and the device tree's `stdout-path` is
`"serial0:115200n8"` — both point at the same DesignWare 8250-family UART used since
stock.)

Connect *before* powering on the board, so you capture output from the very first
moment.

### Capturing a boot log

Pick whichever tool you have. Examples (replace `/dev/ttyUSB0` with your adapter's actual
device name — `dmesg | tail` after plugging it in will show you):

```sh
# minicom, with logging to a file
minicom -D /dev/ttyUSB0 -b 115200 -C bootlog.txt

# screen, with logging to a file
screen -L -Logfile bootlog.txt /dev/ttyUSB0 115200

# picocom, piped through tee
picocom -b 115200 /dev/ttyUSB0 | tee bootlog.txt
```

A captured log is the single most useful thing to attach to a bug report — see
[`faq.md`](faq.md#how-to-report-a-bug).

---

## What a healthy boot looks like, stage by stage

```
(silence — the on-chip BootROM produces no console output)
U-Boot SPL 2017.03+ (...)
U-Boot 2017.03+ (...)
DRAM: ...
MMC: ...
... FPGA/bridge init messages ...
Hit any key to stop autoboot ...
... "run mmcload" / "run mmcboot" style messages, u-boot.txt read if present ...
Starting kernel ...
[    0.000000] Linux version 6.18.38 ...
[    0.000000] Command line: root=/dev/loop... console=ttyS0,115200 ...
... normal kernel boot messages ...
(MiSTer menu appears on HDMI; the serial console typically shows a login prompt or
 stays quiet once userspace is up)
```

Use where the output **stops** to figure out which recovery tier you need:

| Where it stops | Likely cause | What to do |
|---|---|---|
| No output at all, ever, even at power-on | Wiring, adapter, or terminal settings — not a software problem yet | Re-check connections and settings above before assuming anything is broken |
| Stops during/after the `U-Boot SPL` / `U-Boot` banners, never reaches "Starting kernel" | Possible bad U-Boot flash or corrupted saved environment | **Tier 2**, below |
| Reaches "Starting kernel" but panics or hangs very early in the kernel log | Possible corrupted `linux.img` or `zImage_dtb` | **Tier 1**, below |
| Kernel boots fully, but MiSTer/the menu never appears | Something past this project's boot-chain scope (FPGA image, cores, etc.) | Capture the full log and file a bug report — see [`faq.md`](faq.md#how-to-report-a-bug) |

---

## Tier 1 recovery — restore the FAT-partition files (safe, no special tools)

This fixes the large majority of real-world "update went wrong" cases, because most
failure modes land in the kernel image or a bad boot-argument override, not in the
bootloader itself.

1. Power off. Remove the SD card and connect it to another computer via a USB card
   reader.
2. Mount the card's **first partition** (FAT32 — this is the `/media/fat` partition you
   already browse from the MiSTer menu).
3. In its `linux/` directory, restore known-good copies of:
   - `linux.img`
   - `zImage_dtb`
   - `uboot.img` (see the note below on what this file does and doesn't fix)
   - `u-boot.txt`, if you were using one — if you suspect a *bad custom* `u-boot.txt` is
     the problem (it can override arbitrary U-Boot environment variables, not just the
     documented `$v` knob), the simplest fix is to delete or rename it and let the board
     boot on built-in defaults.

   "Known good" means either: a copy from a previous release of this project you know
   booted successfully, or the `files/linux/` contents from the official stock
   `release_YYYYMMDD.7z` archive (the same one the official SD-Installer uses).
4. Unmount cleanly, re-insert the card, and power on.

**A note on `uboot.img` specifically:** this file living on the FAT partition is a
*staged copy* — it's what an already-running Linux system's `updateboot` script reads and
`dd`s onto the SD card's raw boot area the next time an update runs. Restoring this FAT
file by itself does **not** undo a boot-area write that already happened; it only matters
for a *future* update. If U-Boot itself is what's broken (Tier 2 below), fixing this file
alone will not help — the raw write already happened, and the board can't get far enough
to run `updateboot` again to fix itself.

---

## Tier 2 recovery — the bootloader itself (rare)

If Tier 1 doesn't help — specifically, if you *never* see the `U-Boot SPL` / `U-Boot`
banners on serial, even after restoring the FAT files above — the SD card's raw boot
area (a small partition at the very start of the card, outside the FAT filesystem
entirely, that the SoC's on-chip boot ROM reads directly) needs to be rewritten. This is
not something a FAT-file swap can fix, because it lives outside the FAT filesystem
altogether.

This project deliberately ships `uboot.img` byte-identical to the stock image (see
`docs/downloader-contract.md` §8) — it has not modified U-Boot at all in this phase. That
means the **official MiSTer SD-Installer tool** (the same tool used to set up a stock SD
card from scratch) writes exactly the correct boot area for this project's images too.
Re-run that installer against the affected card; it rewrites the raw boot region
independently of whatever Linux image is (or isn't) currently working, so a bricked
Linux install doesn't prevent it from succeeding.

If you don't have a working stock SD-Installer set up already, treat this as the same
first-time setup process any new MiSTer user goes through — the officially documented
MiSTer installation guide covers it, and this project's Linux image can be re-applied
afterward via [`onboarding.md`](onboarding.md) once the card is bootable again.

---

## After you're back up

Whether Tier 1 or Tier 2 got you booting again, please consider filing a bug report with
whatever serial log you captured — see [`faq.md`](faq.md#how-to-report-a-bug). Boot
failures are exactly the class of problem this project's hardware validation is still
thin on, and a real log from a real failure is the most useful thing you can contribute.

---

## See also

- [`rollback.md`](rollback.md) — if the box boots fine but you just want back to stock
- [`onboarding.md`](onboarding.md) — re-opting-in once you're back on a working card
- [`faq.md`](faq.md) — how to report a bug, what changed vs. stock
- [`../boot-chain.md`](../boot-chain.md) — the full, source-cited boot sequence this page summarizes
