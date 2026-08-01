# Onboarding — opting in to the modernized Linux image

**Status: personal-use project.** This image is offered opt-in, to people who understand
they're running a personal, not-yet-sustainability-signed project (see
[ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md) and
[`beta-testing.md`](beta-testing.md)). Nothing about opting in is destructive or
irreversible — see [`rollback.md`](rollback.md) if you ever want back out.

This document is the exact, copy-pasteable procedure. It assumes you already have a
working MiSTer (any recent stock image) that updates itself normally.

**Both common updaters work, and you don't need to know which one you use.** Whether you
run `update_all.sh` (Update All, the most common choice) or `Scripts/update.sh`
(`Downloader_MiSTer` directly), the opt-in below is identical. Update All doesn't replace
the Downloader — it *runs* it, handing it the same `/media/fat/downloader.ini`, which is
the file the setup below adjusts. Where the two genuinely differ — who reboots you, and
which one accepts command-line options — it's called out explicitly at that point in the
text.

---

## What "opting in" actually does

MiSTer's own updater, `Downloader_MiSTer`, never talks to GitHub Releases directly. On
every run it fetches a small JSON document — a `db.json` — from whatever URL you've told
it about, and checks that document's `linux` entry against the `/MiSTer.version` file
baked into your currently running system. If they differ, it downloads and applies the
new Linux image automatically, on its own schedule, with no further action from you.

This project publishes exactly that kind of `db.json`, kept up to date by GitHub Actions
on every release, at a stable URL:

```
https://mcfbytes.github.io/Buildroot_MiSTer/db.json
```

But there is a catch, and it is the whole reason this page exists.

**The Downloader applies at most ONE Linux image per run.** The official
`distribution_mister` database always carries a `linux` entry too, and its version will
never match ours. So when both are configured, both are candidates for that single slot —
and the Downloader picks the one that appears **first in `downloader.ini`'s database
order**.

That is not a coin flip you might win. It is a loss every time: databases registered by
drop-in files are always merged *after* the ones in `downloader.ini` itself, and Update All
pins `[distribution_mister]` to the *top* of that file every time it rewrites it. On any
card Update All has ever touched, the official image wins deterministically, and a routine
`update_all.sh` run silently puts you back on the stock image. Nothing warns you; the
updater is doing exactly its job.

So this project does not try to win that race. It removes it:

1. **`update_linux = false`** in the `[MiSTer]` section of `/media/fat/downloader.ini`
   switches the Linux update off for *every* normal Downloader run — `update_all.sh` and
   `Scripts/update.sh` alike. Cores, ROMs, MRAs, Jotego, everything else keeps updating
   exactly as before. The official Linux image simply can no longer be applied, so it can
   no longer overwrite ours. There is nothing left to race.

2. **`Scripts/update_linux_modernization.sh`** runs the Downloader against its **own
   private configuration** — a separate ini naming one database, with the Linux update
   switched on. One candidate means nothing to sort and nothing to lose. It does not read
   your `downloader.ini`, so a hand-edited or broken one cannot stop your updates, and our
   updates cannot disturb your database list.

This is safe against Update All, verified against its source and then on real hardware:
Update All preserves the `[MiSTer]` section **verbatim** when it rewrites
`downloader.ini`, and it only ever sets the `UPDATE_LINUX` environment variable to
`false`, never to `true`. It cannot turn our setting back on.

And if something else does, this image puts it back. `/etc/init.d/S05mlm` re-checks the
setting on **every boot**, re-deploys the updater script onto the card, and records the
running version. So the failure mode is not "silently disabled forever" but "put back at
the next boot, and the fact that it happened is in
`Scripts/.config/mister_linux_modernization/boot.log`". Boot-time upkeep is also how a
card picks up a *corrected* updater script: a release archive can only carry
`files/linux/**` and can never write `Scripts/`, but it does carry `linux.img`, and
`linux.img` carries the canonical copy.

> **If you install this image by any means other than the setup below** — copying
> `linux.img` and `zImage_dtb` onto the card by hand, say — **your very next routine
> `update_all.sh` will quietly put stock back.** Do Step 1 and your image stays put.

> **Already flashed our `sdcard.img`?** Then all of this is already done for you — the
> card ships with `downloader.ini` and the updater script in place, and this image's
> boot-time upkeep keeps them that way. Skip to [Step 2](#step-2) and just confirm with
> `Scripts/update_linux_modernization.sh --status`.

---

<a id="step-1"></a>
## Step 1 — install the updater script

Download **one file** to your SD card and run it. It configures everything else itself.

```
/media/fat/Scripts/update_linux_modernization.sh
```

Get it from the repository (over SSH, or by copying it onto the card from a PC):

```sh
curl -fL -o /media/fat/Scripts/update_linux_modernization.sh \
  https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/board/mister/de10nano/fat-payload/Scripts/update_linux_modernization.sh
chmod +x /media/fat/Scripts/update_linux_modernization.sh
```

Then run it once. From the MiSTer menu it appears in **Scripts** as
`update_linux_modernization`; over SSH it is just:

```sh
/media/fat/Scripts/update_linux_modernization.sh
```

On that first run it will:

1. **Set `update_linux = false`** in the `[MiSTer]` section of
   `/media/fat/downloader.ini`. This is a surgical edit — it changes that one key and
   leaves every other byte, section and comment of your file alone, and it does **not**
   add or remove any of your databases.

   The one exception is if you have no `downloader.ini` at all, in which case it creates
   one — and that file also declares `[distribution_mister]`, the official database. It
   has to: Update All seeds its defaults only when `downloader.ini` is absent, so creating
   a file with no databases in it would suppress that seeding and quietly leave you with
   no core updates at all.
2. **Generate its own private configuration** under
   `/media/fat/Scripts/.config/mister_linux_modernization/`, naming our database and
   nothing else. This is regenerated on every run, so it can never go stale, and it is
   deliberately *not* placed in `/media/fat` — the Downloader looks for drop-in databases
   in whichever directory the ini it was given sits in, so an ini there would pull your
   whole database list into what is meant to be a Linux-only run.
3. **Update the Linux image** from our database, then reboot if a new one was installed.

Every one of those steps is idempotent. Re-running the script is always safe, and it
re-checks (and repairs) the configuration each time before it updates — so if anything
ever knocks the setup out of shape, running the script puts it back.

Useful flags:

| Flag | What it does |
|---|---|
| *(none)* | Check, update if a newer release exists, reboot afterwards |
| `--no-reboot` | Same, but never reboots — prints what to do instead |
| `--force` | Run the update even when the installed and published versions match |
| `--setup-only` | Repair the configuration and stop. No download |
| `--status` | Report only. Changes nothing |
| `--restore-stock` | Hand the Linux image back to the official database ([rollback](rollback.md)) |

It also honours two files on the card: `linux/no_auto_reboot` (never reboot) and
`linux/no_linux_modernization` (opt out of boot-time upkeep entirely).

---

<a id="step-2"></a>
## Step 2 — confirm it took

```sh
/media/fat/Scripts/update_linux_modernization.sh --status
```

The line that matters is **Official Linux updates: DISABLED** — that is the protection
being in place, not a problem:

```
MiSTer Linux Modernization -- status

  Installed Linux image : 260731
  Kernel                : 6.18.41
  Latest published      : 260731
                          (up to date)

  Official Linux updates: DISABLED   <- this image is protected
  downloader.ini        : /media/fat/downloader.ini
  Update channel        : https://mcfbytes.github.io/Buildroot_MiSTer/db.json
  Boot-time upkeep      : on
  Last run log          : /media/fat/Scripts/.config/downloader/mister_linux_modernization.log
```

If it instead says `Official Linux updates: true` (or anything other than `DISABLED`),
you are **not** protected and a routine `update_all.sh` could replace this image. Run the
script with `--setup-only` to fix it.

`/MiSTer.version` is the release date as `YYMMDD`; compare it against the newest release
on the [Releases page](https://github.com/mcfbytes/Buildroot_MiSTer/releases) to see
whether you are current.

> **Note the inversion, if you have read older versions of this page.** `update_linux`
> being **false** is now the *correct, wanted* state. Earlier revisions of this document
> told you to make sure Linux updates were switched **on**, because back then our image
> arrived through a normal Downloader run and had to win a race to do it. It no longer
> works that way, and `update_linux = true` now means the **official** image can overwrite
> ours on any routine update.

---

<a id="multi-db-ordering-rule"></a>
## Why there is no longer a race to lose

`Downloader_MiSTer` only ever applies **one** Linux update per run, even if several
configured databases each carry a `linux` entry. When more than one does, it logs:

```
Too many databases try to update linux. Only 1 can be processed. Ignoring: <db_id, ...>
```

and picks whichever database's document **finished downloading and parsing first** — a
genuine race between concurrent worker threads, not a queue you can control from
`downloader.ini`. Section order makes no difference; the Downloader fetches every
configured database concurrently and races them.

**This project used to try to win that race**, by keeping its `db.json` to a few hundred
bytes so it would parse before `distribution_mister`'s multi-megabyte catalog. That works
most of the time. "Most of the time" is not good enough for something whose failure mode
is silently reverting the user's operating system, so it is no longer how any of this
works.

Instead, `update_linux = false` means **no** database gets the Linux slot during a normal
run — not ours, not the official one. The contest is cancelled rather than entered. The
only thing that applies a Linux image is
`Scripts/update_linux_modernization.sh`, which asks for exactly one database by name
(`--run-only mister_linux_modernization`) and so has no one to race.

Two consequences worth knowing:

- **You should never see the `linux_multiple_dbs` warning again.** If you do, something
  has re-enabled `update_linux`; run `update_linux_modernization.sh --status` to check,
  and the script itself will repair it.
- **`db.json` no longer has to stay tiny to be correct.** It still is small, but that is
  now a nice property rather than the thing holding the mechanism up.

If an update ever does something you didn't expect, the Downloader's own log
(`Scripts/.config/downloader/downloader.log` on the SD card) is the thing to include in a
bug report (see [`faq.md`](faq.md#how-to-report-a-bug)).

---

<a id="forcing-a-run"></a>
## What the updater script actually runs

Nothing in `update_linux_modernization.sh` is magic. Stripped of the checks, it is one
command against a private configuration file:

```sh
# /media/fat/Scripts/.config/mister_linux_modernization/mister_linux_modernization.ini
#   [MiSTer]
#   update_linux = true
#   file_checking = exhaustive
#
#   [mister_linux_modernization]
#   db_url = https://mcfbytes.github.io/Buildroot_MiSTer/db.json

DOWNLOADER_INI_PATH=/media/fat/Scripts/.config/mister_linux_modernization/mister_linux_modernization.ini \
UPDATE_LINUX=true ALLOW_REBOOT=0 \
  /tmp/dont_download.sh --run-only mister_linux_modernization
```

- **The private ini** declares one database and turns the Linux update on for this run
  only. Your `downloader.ini` is never read, so nothing you have done to it can break our
  updates and nothing we do can disturb your database list.
- **It lives in a directory of its own**, not in `/media/fat`. The Downloader discovers
  drop-in databases by globbing the directory the ini it was handed sits in — an ini
  dropped in `/media/fat` would pull in every `downloader_*.ini` on the card and turn a
  Linux-only check into a full core update.
- **`--run-only`** is a fail-closed assertion rather than a mere filter. If the private ini
  were ever missing or empty, the Downloader would auto-add `distribution_mister` (it does
  that whenever the base ini declares no databases) and the run would install the *stock*
  image. With `--run-only`, an unconfigured id is rejected long before the Linux update is
  reached.

Three things worth knowing:

- **This cannot delete anything of yours.** Skipping a database is not removing it.
  Downloader only removes a database's files through its explicit *uninstall* command, and
  the local store — one shared file, whichever ini was used — is loaded whole and saved
  whole. Databases not in this run are carried as non-current and their path claims veto
  deletion.
- **`--run-only` cannot override `update_linux` on its own.** That is what
  `UPDATE_LINUX=true` is for. `Scripts/update.sh --run-only mister_linux_modernization`
  without it does nothing at all, silently, because the global switch is still off.
- **It updates *only* Linux.** Cores, ROMs and everything else are skipped for that run.
  Your next normal `update_all.sh` picks them up as usual.

---

## What you should see on a successful update

The Downloader prints a distinct, deliberately alarming-sounding banner whenever it
touches the Linux image — this is normal, not an error, and appears for *any* Linux
update, official or ours:

```
======================================================================================
Hold your breath: updating the Kernel, the Linux filesystem, the bootloader and stuff.
Stopping this will make your SD unbootable!
...
```

Do not power off during this phase. It normally takes well under a minute.

**A reboot is required** to actually run the new kernel; the flash phase alone does not
switch anything live.

- **`update_linux_modernization.sh` (the normal way):** the Downloader sets a reboot flag
  and reboots about 30 seconds after the run finishes — a longer pause than its usual 5
  seconds, to give you time to read the message. Pass `--no-reboot` and it will instead
  tell you a reboot is needed and leave it to you.
- **`update_all.sh`** never reboots you for *our* Linux image, because with
  `update_linux = false` it never applies one. (It still reboots for its own reasons, e.g.
  after a core update, exactly as it always has.)

If nothing reboots on its own, just reboot manually. Nothing is in a half-applied state
while you wait: the new kernel simply isn't running yet.

After rebooting:

- Expect a **one-time SSH host-key warning** the next time you connect over SSH — this
  image generates a unique host key per device on first boot, unlike stock's shared key.
  See [`faq.md`](faq.md#ssh-host-keys-changed) for the one-line fix.
- You can confirm the update actually took by checking `/MiSTer.version` (its content
  should now be a 6-digit `YYMMDD` matching the release you expected — see the release's
  GitHub page for that date).

If something looks wrong after an update, don't panic — [`rollback.md`](rollback.md) is a
short, calm procedure back to the stock image, and the update mechanism is designed so
that rollback uses the exact same, well-tested code path as any other update.

---

## See also

- [`rollback.md`](rollback.md) — how to get back to stock
- [`serial-recovery.md`](serial-recovery.md) — if the box doesn't boot at all after an update
- [`faq.md`](faq.md) — default credentials, SSH host keys, what changed vs. stock, how updates work, how to report a bug
- [`beta-testing.md`](beta-testing.md) — the broader personal-use/beta posture this project is under
- [`../downloader-contract.md`](../downloader-contract.md) — the full, source-cited technical contract this document summarizes
