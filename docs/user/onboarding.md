# Onboarding — opting in to the modernized Linux image

**Status: personal-use project.** This image is offered opt-in, to people who understand
they're running a personal, not-yet-sustainability-signed project (see
[ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md) and
[`beta-testing.md`](beta-testing.md)). Nothing about opting in is destructive or
irreversible — see [`rollback.md`](rollback.md) if you ever want back out.

This document is the exact, copy-pasteable procedure. It assumes you already have a
working MiSTer (any recent stock image) with `Downloader_MiSTer` running on its normal
schedule.

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
for why.

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

Do not power off during this phase. It normally takes well under a minute. Once it
finishes, the Downloader sets a reboot flag and — by default — automatically reboots the
system about 30 seconds later (longer than its usual 5-second post-run reboot wait, to
give you a moment to notice the message).

**A reboot is required** to actually run the new kernel; the flash phase alone does not
switch anything live. If you have automatic reboot disabled in your Downloader
configuration, reboot manually once the run finishes.

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
