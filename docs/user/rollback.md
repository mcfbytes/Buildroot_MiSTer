# Rollback — getting back to the stock image

**This is designed to be trivial, and it is safe to do at any time, for any reason —
"I just don't want to run this anymore" is a perfectly good reason.** You do not need to
diagnose a problem first. Read this calmly; there is no time pressure unless your box is
already in a bad state (if it won't boot at all, go to
[`serial-recovery.md`](serial-recovery.md) instead — this page assumes your box currently
boots).

---

## The procedure

1. **Remove the opt-in database file.** Delete (or rename to not end in `.ini`, if you'd
   rather keep a copy) whichever file you created in
   [`onboarding.md`](onboarding.md#step-1):

   ```
   /media/fat/downloader_mister_linux_modernization.ini
   ```

   or

   ```
   /media/fat/downloader/mister_linux_modernization.ini
   ```

   If you instead added the section manually inside your existing `downloader.ini`,
   delete just that `[mister_linux_modernization]` block.

2. **Re-run the Downloader.** Either run `Scripts/update.sh` from the MiSTer menu, or
   simply wait for its next scheduled run.

3. **Reboot** once it finishes (same as any update — see below for what to expect).

That's the whole procedure. No SD card removal, no re-flashing, no special tools.

---

## Why this actually works, not just "probably"

With our database gone, `distribution_mister` is the only configured database left that
carries a `linux` entry — there's no multi-database race to lose (see
[`onboarding.md`](onboarding.md#multi-db-ordering-rule)
for what that race is, when our entry is present). The Downloader compares your currently
running `/MiSTer.version` against the official entry's version. Because this project's
build stamps a different version than the current official release, that comparison is
guaranteed to differ — the check is a plain string **inequality**, with no concept of
"upgrade" vs. "downgrade" built in. A different string is a different string, so the
official update proceeds automatically, restoring the stock image.

**Rollback is not a special code path.** It is the exact same apply mechanism as any other
Linux update, just running in the direction back to stock:

1. The official `release_YYYYMMDD.7z` is fetched and integrity-checked.
2. Its `files/linux/*` contents are extracted.
3. If any of the six recognized configuration files exist on your card (see below), they
   are copied into the new image before it goes live.
4. The rest of `files/linux/` — including a fresh, official `updateboot` and `uboot.img` —
   is synced onto `/media/fat/linux/`.
5. **`updateboot` runs and re-flashes the bootloader** (see below — this happens on every
   update, not just rollback).
6. The new `linux.img` is swapped in and a reboot is scheduled.

Because it's the same mechanism, it has exactly the same reliability characteristics as
any update you've already trusted enough to opt into. There's nothing rollback-specific
that could go wrong differently.

---

## What `updateboot` actually does (every update, not just rollback)

`updateboot` is a small script shipped inside every Linux update — ours and stock's alike
— and it runs unconditionally whenever a `uboot.img` is present, which it always is on a
real card. It does two things, every single time:

1. **Zeroes 512 bytes at the very start of the SD card**, wiping whatever U-Boot
   environment was previously saved there. Nothing you've customized in a *saved* U-Boot
   environment survives an update — the effective environment after any update is always
   just the built-in defaults plus whatever `u-boot.txt` sets on the FAT partition (if you
   use one). This is expected, not a bug, and it's identical behavior on stock.
2. **Re-flashes `uboot.img` directly onto the boot partition** via `dd` — whatever image
   shipped in that update, official or ours, becomes the active bootloader immediately.

There is no rollback-specific bootloader step; this is just what every Linux update does,
and rolling back to stock puts stock's own `uboot.img` back in place the same way ours
went in.

---

## The six files that are preserved across every update (rollback included)

Before a new image goes live, the Downloader copies these files — if they exist on your
current `/media/fat/linux/` — into the *new*, not-yet-active image, so your local network
identity survives the swap:

| Source (on your SD card) | Destination (inside the new image) |
|---|---|
| `/media/fat/linux/hostname` | `/etc/hostname` |
| `/media/fat/linux/hosts` | `/etc/hosts` |
| `/media/fat/linux/interfaces` | `/etc/network/interfaces` |
| `/media/fat/linux/resolv.conf` | `/etc/resolv.conf` |
| `/media/fat/linux/dhcpcd.conf` | `/etc/dhcpcd.conf` |
| `/media/fat/linux/fstab` | `/etc/fstab` |

This applies symmetrically to rollback: whatever you've customized in those six files
carries forward into the restored stock image too.

---

## A note on trust: the "success" message is not proof

The Downloader's own update script has a known gap: the final flash step isn't written to
propagate a failure from an earlier command (`mv`, `rsync`, or `updateboot` itself) through
to its own exit status — the script's last line is an unconditional `touch`, which almost
always succeeds regardless of what happened before it. In practice this means "the
Downloader reported success" is **not proof that the update fully applied**, in either
direction.

**The reliable check is what actually boots.** After rollback, reboot and confirm
`/MiSTer.version` now reads the stock release's `YYMMDD` (check the date against the
official release you expect to be on) — not just that the Downloader printed a success
message. If the box doesn't come back up at all, go to
[`serial-recovery.md`](serial-recovery.md).

---

## One more thing you'll notice: your SSH host key changes again

This image generates a unique SSH host key per device on first boot (unlike stock, which
ships an identical key on every device — see
[ADR 0015](../decisions/0015-per-device-ssh-host-keys.md)). Rolling back to stock means
your box goes back to presenting stock's shared key, which is *different* from the
per-device key it was presenting a moment ago. Your SSH client will show a one-time
host-key-mismatch warning, exactly as it did the first time you opted in. This is expected
— see [`faq.md`](faq.md#ssh-host-keys-changed) for the one-line fix
(`ssh-keygen -R <host-or-ip>`).

---

## See also

- [`serial-recovery.md`](serial-recovery.md) — if the box won't boot after an update or a rollback
- [`onboarding.md`](onboarding.md) — the opt-in procedure this reverses
- [`faq.md`](faq.md) — SSH host keys, default credentials, how updates work
- [`../downloader-contract.md`](../downloader-contract.md) §7, §8, §10, §11.4 — the full, source-cited mechanism behind everything on this page
