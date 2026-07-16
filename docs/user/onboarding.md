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
what makes the drop-in file below discoverable either way. Where the two genuinely differ
— where a setting lives, who reboots you, and which one accepts the `--run-only` option —
it's called out explicitly at that point in the text.

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

Adding a small file to your SD card tells the Downloader to also poll that URL. That's
the entire opt-in.

---

<a id="step-1"></a>
## Step 1 — add the drop-in database file

**Recommended: a drop-in file, not an edit to your existing `downloader.ini`.** The
Downloader auto-discovers any `*.ini` file matching `/media/fat/downloader_*.ini` or
`/media/fat/downloader/*.ini` and treats each one as an additional database. Using this
mechanism means you never touch your existing `downloader.ini` at all — nothing to get
wrong, nothing to merge back if you later remove it.

Create this file on the SD card's FAT partition (either path works; pick one):

```
/media/fat/downloader_mister_linux_modernization.ini
```

or

```
/media/fat/downloader/mister_linux_modernization.ini
```

with exactly this content:

```ini
[mister_linux_modernization]
db_url = https://mcfbytes.github.io/Buildroot_MiSTer/db.json
```

That's the whole file. Two lines. No other keys are required.

**Alternative (if you'd rather keep one file):** append the same two lines as a new
section anywhere inside your existing `/media/fat/downloader.ini`. Its position in the
file — above or below `[distribution_mister]`, first or last — makes **no difference to
the outcome**. Don't spend time experimenting with section order; see the next section
for why. Update All rewrites `downloader.ini` from time to time, but it only manages the
databases it knows about — a section it doesn't recognize, like ours, is left alone. (It
may reformat the file and drop comments *inside* our section; the drop-in file above
avoids that entirely, which is one more reason to prefer it.)

---

<a id="step-2"></a>
## Step 2 — check that Linux updates aren't switched off

**If you skip this and Linux updates are disabled, opting in does nothing at all — and
nothing tells you so.** Our database gets fetched and parsed correctly, and its Linux
entry is then silently ignored. No error, no warning, no log line. This is the single
most likely reason for "I followed the guide and nothing happened."

- **Update All users:** open Update All's settings screen and make sure the option to
  update Linux is **on**. It is on by default, so if you've never touched it, you're
  fine. If you turned it off at some point, our image can never install.
- **`Scripts/update.sh` (Downloader directly) users:** this is controlled by
  `update_linux` in the `[MiSTer]` section of `/media/fat/downloader.ini`. It defaults to
  true; if that line is present and set false, our image can never install.

This switch is global — it is not per-database. There is no way for our database to
opt itself back in, which is exactly why it's worth checking once, now.

---

<a id="multi-db-ordering-rule"></a>
## The multi-db ordering rule (read this — it's the difference between "it just works" and a support thread)

`Downloader_MiSTer` only ever applies **one** Linux update per run, even if multiple
configured databases each carry a `linux` entry. If more than one does, it logs:

```
Too many databases try to update linux. Only 1 can be processed. Ignoring: <db_id, ...>
```

and picks whichever database's own small JSON document **finished downloading and
parsing first** — a genuine race between concurrent worker threads, not a queue you can
control from `downloader.ini`.

**The natural assumption — that putting our section above or below
`[distribution_mister]` decides which one wins — is wrong.** Section order in
`downloader.ini` has no bearing on which database's fetch completes first; the Downloader
concurrently fetches every configured database (six threads by default) and races them.

**What actually decides it, reliably, in practice: document size.** `distribution_mister`'s
own catalog is a multi-megabyte, multi-thousand-entry community database. This project's
`db.json` carries nothing but a `db_id`, a timestamp, and the `linux` entry — a few hundred
bytes. A sub-kilobyte document finishes downloading and parsing before a multi-megabyte one,
in virtually every real network condition, independent of thread-scheduling luck. That's why
this project deliberately keeps its `db.json` minimal forever, and it's also why the drop-in
mechanism above is the right way to opt in: it adds our tiny database alongside
`distribution_mister` without disturbing anything else in your configuration.

**If you ever suspect the wrong database won** (e.g. you don't see the update you expect,
or you see one you didn't expect), check the Downloader's own log
(`Scripts/.config/downloader/<mode>.log` on the SD card) for the `linux_multiple_dbs`
warning line above — it names every database that lost the race, by id. That line is the
single most useful piece of information to include in a bug report (see
[`faq.md`](faq.md#how-to-report-a-bug)).

---

<a id="forcing-a-run"></a>
## Forcing a run of just this database (optional)

If you don't want to wait for a scheduled run, or you want to take the race above out of
the picture entirely, you can tell the Downloader to run **only** this database:

```
/media/fat/Scripts/update.sh --run-only mister_linux_modernization
```

This skips every other database, so there is only one Linux entry to consider and nothing
to race — it is the deterministic way to pull our image, and the right thing to use when
reproducing a problem for a bug report.

Two caveats:

- **This is a `Downloader_MiSTer` option, not an Update All one.** `update_all.sh` does
  not pass options through to the Downloader, so `update_all.sh --run-only ...` does
  nothing useful. Use `Scripts/update.sh` as shown above. This does not change or
  conflict with your Update All setup in any way — it's just a one-off run.
- **It updates *only* Linux this time.** Cores, ROMs and everything else your normal
  update would fetch are skipped for that run. Your next normal `update_all.sh` picks
  them up again as usual.

The "Linux updates are switched off" gate from [Step 2](#step-2) still applies here —
`--run-only` cannot override it.

### One Update All quirk worth knowing

If you open Update All's **settings screen** and choose the option that exits *without
saving* but still runs, that particular run is driven from a temporary configuration file
in `/tmp` rather than your real `/media/fat/downloader.ini`. Drop-in files are looked for
next to whichever configuration file is in use — so for that one run, our database is not
seen and no Linux update happens.

This is harmless and self-correcting: any normal run afterwards behaves as documented.
But if you've just opted in, went through the settings screen, and saw nothing happen,
this is very likely why — run it again normally, or use the `--run-only` command above.

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
switch anything live. Who performs that reboot depends on how you update — this is the
one place the two updaters genuinely differ:

- **`update_all.sh` (Update All):** Update All explicitly *forbids* the Downloader from
  rebooting and handles it itself once its whole run (not just the Linux part) is done.
  So you will **not** see the Downloader's own 30-second reboot countdown. Update All
  reboots automatically by default; if you turned its auto-reboot off, it prints
  "You should reboot" and leaves it to you.
- **`Scripts/update.sh` (Downloader directly):** the Downloader sets a reboot flag and,
  by default, reboots about 30 seconds after the run finishes — a longer pause than its
  usual 5-second wait, to give you a moment to read the message.

Either way, if nothing reboots on its own, just reboot manually. Nothing is in a
half-applied state while you wait: the new kernel simply isn't running yet.

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
