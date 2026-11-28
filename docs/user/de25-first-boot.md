# DE25-Nano: the first boot

> **Draft, 2026-11-28. This describes a release that does not exist yet.**
>
> - **Cards you can build or download today do not write the board's flash.** They boot on a
>   factory board, install Linux onto the card and give a serial login. There is no picture and
>   no cores. To write one, see [`../de25-sdcard.md`](../de25-sdcard.md) §6.
> - The first boot described below (a card that rewrites the board's flash once) is the plan of
>   [ADR 0035](../decisions/0035-de25-own-qspi-image-first-boot-flash.md). It has not been built
>   or tested. Every time and every light pattern below is **TBD** until it has been measured
>   on a board; none is a guess dressed as a number.
> - This page is written now so that the release cannot ship without it.

## The short version

1. The DE25-Nano starts from a small flash chip on the board, not from the SD card. As shipped
   by Terasic, that chip holds a start-up image that cannot load MiSTer cores.
2. **The first time you boot a MiSTer card, the card replaces that start-up image.** It does
   this once. It takes about **TBD (gate B4)**.
3. **Do not unplug the board during that step.** If power is lost at the wrong moment, the board
   will not start until you restore the flash from a PC over USB
   ([`de25-recovery.md`](de25-recovery.md)). That recovery always works; nothing on the board is
   damaged for good.
4. After it, the board behaves like a DE10-Nano: the card is everything, and a new card or a
   normal update leaves the flash alone. A rare update that must rewrite the start-up image (a
   new "base generation") will say so before it starts.

## What changes, and how to undo it

| | Before (factory) | After |
|---|---|---|
| The flash holds | Terasic's start-up image and demo design | MiSTer's start-up image |
| Terasic's own demo SD cards | boot | **may no longer boot** (TBD: to be tried) |
| MiSTer cards | boot to a serial login only; no picture, no cores | boot to the menu |
| Going back | — | restore Terasic's image from a PC: [`de25-recovery.md`](de25-recovery.md), about TBD minutes |

The card writes only a board it recognises: a DE25-Nano whose flash holds Terasic's factory
image or an older MiSTer one. On anything else it changes nothing.

## What you need

- A DE25-Nano and its power supply.
- A microSD card. Size: TBD.
- A computer to write the card.
- An HDMI display.
- **Have these to hand, in case:** a USB-C cable and a PC running Windows or Linux
  ([`de25-recovery.md`](de25-recovery.md)). You do not need them for a normal install.

You do **not** need Quartus, a licence, a JTAG adapter or a serial cable.

## Steps

1. **Write the card.** Download the card image from the release page, check its SHA-256, and
   write it with balenaEtcher, Raspberry Pi Imager or `dd`. Writing erases the whole card.
2. **Optional: Wi-Fi and settings.** The card shows one small volume, `MISTERSETUP`. Files you
   put there before the first boot are kept: `wpa_supplicant.conf`, `samba.sh`, `Scripts/`,
   `config/`.
3. **Leave the board's switches alone.** SW5 (MSEL) stays as shipped. No switch needs moving,
   now or later.
4. **Use a power source you trust for the next few minutes.** Not a USB port that sleeps, not a
   power strip someone may switch off.
5. **Insert the card and power on.**
6. **Wait.** The screen stays dark during the flash step: the factory image cannot drive HDMI.
   What you can see:

   | Stage | The board's HPS LED | HDMI | Lasts |
   |---|---|---|---|
   | Starting | TBD | dark | TBD |
   | **Writing the flash: do not unplug** | TBD (a distinct pattern) | dark | TBD (gate B4) |
   | Flash written and checked | TBD | dark | — |
   | Installing Linux onto the card | TBD | progress on screen | TBD |
   | Done | TBD | the MiSTer menu | — |

7. **If the board asks for it, unplug it and plug it back in** once the "written and checked"
   pattern shows. Whether this step exists is **TBD (gate B8)**: the board may be able to
   restart itself into the new image, or it may need its power removed once.
8. The card then finishes installing itself and restarts. Copy your files to `MiSTer_Data`
   after that, not before.

## If something goes wrong

| What you see | What it means | What to do |
|---|---|---|
| Power was lost during "installing Linux" | nothing is harmed | power on again; the install starts over |
| Power was lost during "writing the flash", and the board now starts normally | the write had not reached the critical part, or had finished | power on again; the card checks the flash and carries on |
| Power was lost during "writing the flash", and the board no longer starts, with any card | the flash is half written | [`de25-recovery.md`](de25-recovery.md). The board is not damaged |
| The "do not unplug" pattern never ends (longer than TBD) | TBD | TBD |
| Dark screen after "done" | TBD | TBD |
| The card reports that it does not recognise the board's flash (TBD: how it shows this without a screen) | the flash holds something other than Terasic's image or ours | restore Terasic's image first ([`de25-recovery.md`](de25-recovery.md)), then boot the card again |

## Afterwards

- New cards and updates behave as on a DE10-Nano. They do not write the flash.
- A much later release may need a newer start-up image. That would be announced, and would
  follow the same rules as this page.
- To return the board to factory state, for resale or for Terasic's demos:
  [`de25-recovery.md`](de25-recovery.md).

## The text on the card (`MISTERSETUP/README.txt`)

Proposed for the release that writes the flash. Today's cards carry a shorter text
(`board/mister/de25nano/post-image.sh`), which is right for them.

```
MiSTer for the DE25-Nano -- this card is not installed yet.

READ THIS FIRST. The first boot changes the board, once:

  * It replaces the start-up image in the board's flash chip, so that
    the board can load MiSTer cores. This takes about TBD.
  * While it does, the screen is dark and the HPS LED shows TBD.
    DO NOT UNPLUG THE BOARD until that pattern stops.
  * If power is lost during that step the board may not start. It is
    not damaged: restore it from a PC with a USB-C cable.
    Guide:  <URL of docs/user/de25-recovery.md>
  * Afterwards, Terasic's own demo cards may not boot. The same guide
    puts the factory image back.

Then it grows this partition to fill the card, formats it exFAT (label
MiSTer_Data), installs Linux onto it and restarts. If power is lost
during THAT part, just power on again.

Optional: files placed here before the first boot are kept --
wpa_supplicant.conf (Wi-Fi), samba.sh, and Scripts/ or config/.
Everything else on this partition is erased by the install.

Recovery files (not on this card; download them on a PC):
  MiSTer flash image    <release URL>     SHA-256 <hash>
  Terasic factory image <Terasic's URL>   SHA-256 <hash>
```

## For the people preparing that release

This page is done when every TBD above is replaced by something measured, and a person who has
never seen the board has followed it, with no serial cable, on a board restored to factory
state ([`../de25-nano-tasks.md`](../de25-nano-tasks.md), critical path, items 14 and 15).
