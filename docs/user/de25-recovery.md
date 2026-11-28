# DE25-Nano: restoring the board's flash from a PC

> **Draft, 2026-11-28. Not yet rehearsed by this project.** The procedure is Terasic's own, from
> the board's Getting Started Guide, and a tester has used it twice on one board (#318). The
> project's own timed run on a second board is still owed, and so is every item marked **TBD**
> below. Until then, treat Terasic's guide as the authority where the two differ.

## When you need this

- The board shows no sign of life with any SD card, after a first boot that was interrupted
  ([`de25-first-boot.md`](de25-first-boot.md)).
- You want the board back in factory state: for Terasic's demos, for resale, or because a
  MiSTer card said it did not recognise the flash.

**The board is not damaged in any of these cases.** The flash chip can always be rewritten over
the board's own USB port. Nothing MiSTer ships changes the chip's fuses or keys, which are the
only things that could not be undone.

## What you need

| | |
|---|---|
| A PC | Windows or Linux, 64-bit. Not a Mac: Altera publishes no macOS version |
| A USB-C cable | a data cable, to the board's **USB-Blaster** port (TBD: which connector, with a photo) |
| The Programmer | Altera's free **Quartus Prime Pro Programmer and Tools**, version 25.1.1 or newer (TBD: the version this project's run used). It is a separate, much smaller download than Quartus, and needs **no licence** |
| A flash image (`.jic`) | Terasic's factory image, or MiSTer's, below |

You do not need a JTAG adapter: one is built into the board.

## The image

| Image | Where | Check |
|---|---|---|
| **Terasic's factory image**, `golden_top_hps.jic` | inside Terasic's DE25-Nano *Resource Package* (from Terasic's DE25-Nano resources page), under `…/GHRD/output_files/program_qspi_flash/` | for the revA v1.0.0 package: 16,777,447 bytes, SHA-256 `e3d20c2d066761fd02897422ba361aa19faafcd0240dd2782965754cc61b38a4` |
| **MiSTer's image** | the release page, once a release has one (none exists yet) | the SHA-256 on the release page and in the card's `README.txt` |

**Use the package for your board revision.** Terasic publishes one per revision (revA, revB);
the revision is printed on the board (TBD: where). The wrong revision's image writes without an
error and then does not start the board; writing the right one fixes that.

**Which to choose.** Either restores a board that will not start. With Terasic's image the
board is as shipped, and a MiSTer card's first boot will write the flash again. With MiSTer's
image the board is ready for MiSTer cards with no further flash step.

## Steps

1. **Install the Programmer.** On Windows, also install the USB-Blaster III driver that comes
   with it (TBD: exact steps, checked on a clean machine).
2. **Check the image's SHA-256** against the table above or the release page.
3. **Power the board and connect the USB-C cable** to the USB-Blaster port. No SD card is
   needed.
4. **The MSEL switch (SW5): TBD.** Terasic's guide names no switch change. Altera's manual for
   the chip describes a JTAG-only position (`111`), and the factory position is `001`. The
   project's own run will settle whether `001` is enough. If the next step fails with the
   switches as shipped, set SW5 to `111`, repeat it, and set SW5 **back to `001`** afterwards:
   the board does not start from its flash at `111`.
5. **Program.** In the folder holding the `.jic`:

   ```
   quartus_pgm -m jtag -c 1 -o "pvi;golden_top_hps.jic"
   ```

   This programs the flash through the chip and verifies it. It takes about TBD minutes. Terasic's package runs the same command from `flash_program.bat`.
6. **Wait for it to report success.** If the cable is pulled or the PC sleeps part-way, nothing
   is lost: run the command again.
7. **Unplug the board's power, wait a few seconds, and plug it back in.** The chip reads its
   flash when power arrives; a reset button may not make it read the new image.
8. Insert an SD card and power on.

## If it does not work

| What you see | Try |
|---|---|
| The Programmer finds no cable | another cable (many USB-C cables carry no data); the right connector on the board; the driver (step 1) |
| It finds the cable but no device | board power; SW5 (step 4) |
| "Verify" fails | run it again; then download the image again and re-check its SHA-256 |
| It succeeds but the board does not start | SW5 back at `001`? The right revision's package? A full power cycle (step 7)? |
| Anything else | open an issue with the Programmer's full output, the board revision and the SW5 positions |

## Do not

- **Do not run `flash_erase.bat`** from Terasic's package as a first step. It erases the flash
  and leaves the board with nothing to start from until you program an image.
- **Do not run a `flash_program.bat` from one of the package's demo folders.** Those write a
  demo design with no boot loader. Use only the one under `GHRD/output_files/program_qspi_flash/`.
- **Do not use any tool or guide that programs fuses, keys or "secure boot"** on this board.
  That cannot be undone.

## For developers

The same procedure, with its sources and the reasons for each warning, is in
[`../de25-boot-chain.md`](../de25-boot-chain.md) §6 and §7. Before a first write on a board,
read its flash back and keep the copy ([`../de25-nano-tasks.md`](../de25-nano-tasks.md), bench
order, step 1).
