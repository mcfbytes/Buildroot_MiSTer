# Flashing `sdcard.img.xz` — a fresh MiSTer card from a single image

**This is the from-scratch install path.** If you already have a working MiSTer and just
want this project's Linux image on it, you don't need this page at all — that's what
[`onboarding.md`](onboarding.md) is for, and it's a two-line file, not a re-flash.

`sdcard.img.xz` is a complete, bootable SD-card image: write it to a blank card, put the
card in the DE10-Nano, power on, and a few minutes later you have a working MiSTer
running this project's Linux — the same way
[mr-fusion](https://github.com/MiSTer-devel/mr-fusion) sets up a card, but landing this
image instead of stock. It is published as its own release asset, separate from the
normal `release_YYYYMMDD.7z` update channel, and it is never delivered through the
Downloader (see [ADR 0020](../decisions/0020-sdcard-exfat-reformat-installer.md) for the
design).

Two variants may be attached to a release:

- **`sdcard.img.xz`** — the default: the base system, `menu.rbf`, the standard scripts
  (`update.sh`, `update_all.sh`, `wifi.sh`), and nothing else. Smallest download.
- **`sdcard-full.img.xz`** — the same, plus a snapshot of the `_Console` cores baked in,
  so console cores work before your first update run. Everything below applies to both;
  they differ only in what's pre-loaded.

**No BIOS files, ROMs, or games are included in either variant**, and never will be. The
expectation is that you run `Scripts/update_all.sh` after first boot to fetch current
cores, and supply your own game files as usual.

---

## What you need

- An SD card (or USB drive, if your setup boots from one) of **2 GB or larger**. There
  is no upper limit and no benefit to matching sizes — the first boot expands to fill
  whatever you give it, whether that's 8 GB or 1 TB.
- A card reader and a computer.
- A flashing tool: **balenaEtcher**, **Raspberry Pi Imager**, or plain `dd`.

> **Flashing erases the entire card.** Everything on it — all partitions, not just
> files — is destroyed. Back up anything you care about first, and double-check you've
> selected the right device before writing.

---

## Step 1 — flash the image

You do not need to decompress the `.xz` file for the two graphical tools; both handle it
directly.

**balenaEtcher:** *Flash from file* → select `sdcard.img.xz` → select your card →
*Flash*. Etcher verifies the write automatically when it finishes.

**Raspberry Pi Imager:** *Choose OS* → *Use custom* → select `sdcard.img.xz` → choose
your card → write. (Skip any OS-customization prompts — they're for Raspberry Pi OS and
don't apply here.)

**`dd` (Linux/macOS):** first identify the card's device name with `lsblk` (Linux) or
`diskutil list` (macOS) — getting this wrong writes over the wrong disk. Then:

```sh
xz -dc sdcard.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

replacing `/dev/sdX` with your card (on macOS, `/dev/rdiskN`, after
`diskutil unmountDisk /dev/diskN`). Wait for the command to return fully before removing
the card.

When flashing finishes, your computer will see a small FAT32 partition on the card. That
is expected — it is not the final layout, just the installer and its payload. If you
want to pre-configure anything, now is the moment (see Step 2); otherwise eject the card
and move on to Step 3.

---

<a id="pre-seed"></a>
## Step 2 (optional) — pre-seed the card before first boot

After flashing and before the first boot, you can drop files onto the card's FAT32
partition from your computer, and the installer will carry them onto the finished card
in the places MiSTer expects. Place them at the top level of the partition:

| You drop | It becomes | Effect |
|---|---|---|
| `wpa_supplicant.conf` | `linux/wpa_supplicant.conf` | WiFi credentials ready on the very first real boot |
| `samba.sh` | `linux/_samba.sh` | Samba file sharing enabled |
| `Scripts/` (a folder) | merged into `Scripts/` | Your own scripts alongside the bundled ones |
| `config/` (a folder) | merged into `config/` | Pre-made MiSTer configuration |

This mirrors mr-fusion's pre-seed behaviour, so anything you're used to preparing for an
mr-fusion card works the same way here. All of it is optional — a bare flashed card
works fine and you can configure everything later over the network or on the card
directly.

---

## Step 3 — first boot: the one-time auto-expand

Insert the card, connect the board, and power on. **The first boot is special**: a small
one-time installer runs instead of MiSTer, and it rebuilds the card to its full size.
Concretely, it:

1. copies its payload into RAM, along with its own copy of the installer,
2. re-partitions the card to use **all** of its capacity,
3. **writes the bootloader straight away**, so the card can boot again within seconds,
4. formats the data partition as **exFAT**, labelled `MiSTer_Data` (the standard MiSTer
   layout — the finished card is exactly what mr-fusion would have produced),
5. puts the installer itself back on the card, so that if it is interrupted from here
   on, the next power-on simply runs the install again,
6. copies everything back and expands the system image,
7. merges any [pre-seeded files](#pre-seed) and generates a **unique network MAC
   address** for your board (stock's fallback is the same shared address on every device,
   which causes conflicts when two MiSTers share a network),
8. swaps in the real MiSTer kernel as its very last act, and reboots into it.

Two things to know while it runs:

- **The screen stays blank the whole time.** U-Boot loads the menu core into the FPGA
  before Linux starts (same as any boot), but nothing configures video output until the
  MiSTer software runs — and the installer never runs it. So there is nothing to
  show during the install. This is normal. If you have a
  [serial console](serial-recovery.md) attached you can watch every step, but you don't
  need one.
- **It takes a few minutes — please don't power off.** Larger cards and the `-full`
  variant take a little longer. The board reboots by itself when it's done; the first
  thing you'll see on screen is the MiSTer menu.

**If you do lose power part-way through** (or pull the card), you have not ruined it.
Step 3 above means the card can still boot, and step 5 means it boots back into the
installer, which starts over by itself — you lose a couple of minutes, nothing else. In
the one narrow case where the interruption landed while the files were still being
copied, the installer tells you so on the serial console and asks you to re-flash
`sdcard.img`; re-flashing is all that is ever needed, and the board itself is never at
risk.

Why a reformat instead of a resize: MiSTer's data partition is exFAT, and exFAT cannot
be grown in place. The rebuild-through-RAM approach is the same mechanism mr-fusion has
used reliably for years. It runs exactly once — after it completes, the installer no
longer exists on the card, and every subsequent boot is a normal MiSTer boot.

---

## Step 4 — after first boot

Run **`Scripts/update_all.sh`** from the MiSTer menu to fetch current cores and bring
everything up to date. The card ships with a working base, not a current one.

> **No caveat here any more — the card ships already configured.** It carries a
> `downloader.ini` with `[MiSTer] update_linux = false`, which stops every normal update
> run from applying *any* Linux image, so `update_all.sh` cannot replace this project's
> Linux with stock. Cores, ROMs, MRAs and Jotego update exactly as usual; the Linux image
> is simply left alone. This image also re-checks that setting on every boot, so it stays
> that way.
>
> Updating *this project's* Linux is a separate, deliberate action: run
> **`Scripts > update_linux_modernization`**. Confirm the card's state at any time with
> `Scripts/update_linux_modernization.sh --status`, which should report
> `Official Linux updates: DISABLED`.
>
> (Earlier revisions of this page warned that your first `update_all.sh` would revert you
> to stock. That was true of the older opt-in mechanism and is no longer true of a card
> flashed from this image — see
> [ADR 0025](../decisions/0025-update-linux-kill-switch-and-private-updater.md).)

Also expected on a fresh card:

- **SSH host keys are generated per device on first boot** (unlike stock's shared
  keys), so your SSH client may warn about a changed key if it has talked to a MiSTer
  before. See [`faq.md`](faq.md#ssh-host-keys-changed) for the one-line fix.
- The default root password is stock parity (`1`) — see
  [`faq.md`](faq.md#whats-the-default-root-password-and-is-that-a-problem).

---

## If first boot fails

First, the reassuring part: **nothing about this process can brick the board.** The
DE10-Nano stores nothing internally — everything lives on the card — so re-flashing the
card (Step 1) always returns you to a known-good starting point, no matter what state
the install was left in. Re-flash and try again is the universal reset button here, and
it's safe to reach for at any point.

If the board hasn't rebooted into the MiSTer menu after ~10 minutes:

1. **Power off, re-flash the card, and try once more.** Transient SD-card write errors
   are the most common cause, and a second attempt usually just works. Trying a
   different card is the next-cheapest experiment — cheap or aging cards are the usual
   culprit.
2. **If it fails the same way twice**, the installer is designed to fail loudly, not
   silently: on any error it prints a clear banner explaining what went wrong and drops
   to a rescue shell on the serial console instead of half-writing the card. A
   [serial console](serial-recovery.md) capture of that banner is the single most useful
   thing you can attach to a bug report — see
   [`faq.md`](faq.md#how-to-report-a-bug).

---

## See also

- [`onboarding.md`](onboarding.md) — opting in to updates for this image (do this before
  your first `update_all.sh` if you want to keep this Linux)
- [`faq.md`](faq.md) — default credentials, SSH host keys, what changed vs. stock
- [`serial-recovery.md`](serial-recovery.md) — the serial console referenced above
- [`rollback.md`](rollback.md) — getting back to stock (with this card: simply run
  `update_all.sh` without opting in)
- [ADR 0020](../decisions/0020-sdcard-exfat-reformat-installer.md) — the technical
  design of the installer, for the curious
