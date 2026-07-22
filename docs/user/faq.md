# Frequently asked questions

---

## Is this safe to run?

**This is a personal-use project.** It has not yet reached the sustainability
sign-off gate described in
[ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md): a named maintainer
has not yet committed, in writing, to tracking upstream `6.18.y` kernel security releases
through their end of life. Until that happens, this is offered opt-in, to people who
understand that posture — see [`beta-testing.md`](beta-testing.md) for the fuller
picture.

Hardware validation to date: **boot, Bluetooth (controller pairing), WiFi (WPA3 5 GHz
auto-connect), and the Downloader (HTTPS update) have all been confirmed on one real
DE10-Nano board.** Samba and MIDI are currently build- and CI-verified only — they have
not yet been exercised on real hardware. Treat anything not listed above as unverified in
practice until proven otherwise on your own hardware.

The kernel is pinned to **6.18.39**, and the 6.18 line **has booted on real hardware** —
from the CI-built artifact rather than a local build, with every out-of-tree module
present, Bluetooth firmware loading, and no kernel BUG/Oops/panic. WiFi is confirmed too:
the RTL8822BU auto-connects at boot to a **WPA3/SAE** network (PMF required), driven by
**mainline `rtw88`** rather than an out-of-tree driver.

One real bug has been found and fixed on hardware since then, and it is worth knowing
about because it explains why "it compiles and boots" is not the same as "it is correct":
early builds **auto-overclocked the board to 1.2 GHz**, because the carried overclock
driver was written for 5.15 and a kernel flag it relied on changed meaning in 6.18. It is
fixed — the default is 800 MHz and the overclock is opt-in again — but that is the class
of defect a five-year forward-port produces, and it is why the hardware list above is
deliberately short.

---

## What's the default root password, and is that a problem?

**The root password is stock parity: `1`.** This is not a bug and not something this
project changed — it's the same fixed, publicly known default password stock MiSTer has
always used, deliberately reproduced here (a hardcoded, fixed-salt password hash baked in
at build time, the same value stock uses). Root login is permitted over SSH and FTP with
this password, exactly as on stock. (Passwordless login is *not* permitted — an empty
password is explicitly refused.)

**Say this plainly: anyone who knows this widely-published default password, and who can
reach your MiSTer's SSH or FTP port, has root.** On a home network you trust, this is the
same posture the entire MiSTer community has run under for years. **If your MiSTer is
reachable from an untrusted network — a shared network, a network you don't control, or
anything exposed to the internet — changing the root password is strongly advised.**
Change it the same way you would on stock: log in and run `passwd`.

---

<a id="ssh-host-keys-changed"></a>
## My SSH client says the host key changed / warns about a possible attack. What's going on?

This is expected, and it's actually a security improvement over stock, not a regression.

**Stock MiSTer ships the exact same SSH host keys, baked into the image, on every single
device.** Anyone who has ever looked at a stock `linux.img` has those keys; there is no
way to change them from a stock image, and there is no host-key warning to protect you
from impersonation, because every stock box presents the same "valid-looking" key.

**This image generates a unique SSH host key per device, the first time it boots** (see
[ADR 0015](../decisions/0015-per-device-ssh-host-keys.md) for the full mechanism and
rationale — it mirrors the same approach stock already uses for Bluetooth pairing keys).
The key is generated once and then persists on the SD card's data partition across
ordinary reboots and future updates of this image.

The consequence: the very first time you connect to this image over SSH, your client will
refuse, because it remembers the *old* key (stock's shared key, or a previous device's
key) and this box is presenting a genuinely different one. This is your SSH client
correctly noticing that the server's identity changed — because it did. Clear the old
entry once, per client:

```sh
ssh-keygen -R mister.lan        # or: ssh-keygen -R <the box's IP address>
```

You'll see this same one-time warning again if you ever [roll back](rollback.md) to
stock (the key reverts to stock's shared key) or move between different MiSTer devices
running this image.

---

## What actually changed vs. stock?

| | Stock | This project |
|---|---|---|
| Kernel | **5.15.1** (forked Nov 2021; never took a single `5.15.y` stable update) | **6.18.39** LTS, on a stable `.y` line with ongoing security backports |
| Buildroot | **2021.02.4** | **2026.05.1** — roughly five years newer |
| glibc | **2.31** | **2.43** |
| OpenSSL | **1.1.1** (end-of-life since 2023-09-11 — no upstream fixes since) | **3.6.3** |
| WiFi drivers | Six out-of-tree vendor forks, no WPA3 for several chips | Mainline `rtw88`/`rtw89`/`rtl8xxxu`/`mt7921u` etc. where mainline covers the chip (kept as out-of-tree only for the handful of chips mainline still doesn't drive) — **WPA3/SAE hardware-verified working**, which the out-of-tree fork it replaces was not |
| USB controller/HID support | Stock's existing set | Broader — several additional mainline HID drivers (gamepad and input device support mainline gained since 2021) |

Full detail with citations: [`../version-delta.md`](../version-delta.md) (versions) and
[`../patch-provenance.md`](../patch-provenance.md) (kernel patch-by-patch disposition).

**One known regression, stated plainly:** the **Logitech G923 PlayStation-mode** wheel
loses force feedback and range control (steering, pedals, and buttons still work as a
plain joystick). This is a deliberate, documented trade-off — the G923 **Xbox** variant,
and all G29/G27/G25 wheels, are fully supported with force feedback intact. See
[`../patch-provenance.md`](../patch-provenance.md) §9.3 for the full reasoning.

---

## How do updates work? Will I get stuck in a re-flash loop?

No. Every release is offered exactly once. Earlier in this project's development, the
version scheme used to derive the published update version had a real bug that would have
caused exactly that loop (every Downloader run would have looked like a new update was
available, forever, re-flashing the bootloader each time). That has been fixed at the
source: the image's own internal version stamp and the published update version are now
both derived from the release's own tagged date, so they always agree, and a device that's
already up to date is correctly recognized as such on every subsequent run. See
[ADR 0018](../decisions/0018-db-json-version-is-release-date-driven.md) for the full
mechanism, if you're curious.

Practically: opt in once (see [`onboarding.md`](onboarding.md)), and future releases will
be offered normally, the same way official MiSTer updates are — no repeated re-flashing
between releases.

---

<a id="reverted-to-stock"></a>
## I was running this image, ran my normal update, and it put stock back. Was that a bug?

No — and it's worth knowing why, because the same mechanism is what makes rollback safe.

The version check is a plain "is it different?" comparison. It has **no concept of newer
or older**: there is no date parsing and no `<`/`>` anywhere in it. So whenever the
official database is the only one offering a Linux entry, it sees that your version isn't
the official one and reinstalls stock — regardless of your version being "higher."

That happens in exactly one situation: **our database wasn't configured on that card.**
Almost always that means the image was installed some other way — copied on by hand, or
restored from a backup — without doing [Step 1](onboarding.md#step-1). The updater then
has no idea this project exists; it just sees a system that doesn't match official and
fixes it.

The fix is the fix for everything else here: complete [Step 1](onboarding.md#step-1) and
your image is offered and kept normally. (If you *wanted* stock back, congratulations —
you've already done it. See [`rollback.md`](rollback.md).)

---

<a id="opted-in-nothing-happened"></a>
## I opted in, the update ran fine, and nothing happened. Why?

In order of how often it's the cause:

1. **Linux updates are switched off in your updater.** This is by far the most common
   reason, and it is completely silent — our database is fetched and parsed correctly,
   and its Linux entry is then ignored with no error or log line. See
   [`onboarding.md` Step 2](onboarding.md#step-2). It's a global switch, on by default,
   so this only bites people who turned it off at some point.
2. **You're already on this image.** Updates are offered once; if your `/MiSTer.version`
   already matches the current release, a run that changes nothing is the correct result.
3. **A different database won the Linux race.** Rare, but it's what the
   [ordering rule](onboarding.md#multi-db-ordering-rule) describes. Search your Downloader
   log for the `linux_multiple_dbs` warning — it names every database that lost.
4. **You used Update All's settings screen and chose "exit without saving, but run".**
   That specific run reads a temporary config from `/tmp` and won't see our database at
   all — see [the quirk note](onboarding.md#forcing-a-run). Any normal run afterwards is
   fine.

The quickest way to distinguish these is a deterministic one-off run:
`/media/fat/Scripts/update.sh --run-only mister_linux_modernization`. If that installs the
image, the problem was #3 or #4. If it still does nothing, it's #1 or #2.

---

<a id="how-to-report-a-bug"></a>
## How do I report a bug?

Please use the issue templates — they exist specifically to make sure the details needed
to actually diagnose a hardware-adjacent bug are included:

- **Bug Report** template — requires your `/MiSTer.version` (read the first 6 bytes of
  that file), a description of what went wrong, and kernel output (`dmesg`). A serial
  console log (see [`serial-recovery.md`](serial-recovery.md)) is optional but by far the
  most valuable thing you can attach if you have one, especially for anything boot-related.
- **Hardware Test Report** template — for reporting what does and doesn't work on your
  specific board/peripheral combination, even if nothing is actually broken. This is how
  the hardware compatibility matrix grows beyond the one board this project has been
  validated on so far.

Both templates are visible on the repository's Issues page. The more specific the
`MiSTer.version`, `dmesg` excerpt, and (if available) serial log, the faster any real
problem can be narrowed down — this project has one validated board and no dedicated
support staff, so a well-filled-out report genuinely determines whether a bug is fixable
at all.

---

## See also

- [`onboarding.md`](onboarding.md) — how to opt in, and the multi-database ordering rule
- [`rollback.md`](rollback.md) — how to get back to stock
- [`serial-recovery.md`](serial-recovery.md) — recovering a box that won't boot
- [`beta-testing.md`](beta-testing.md) — the broader personal-use/beta posture
- [ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md),
  [ADR 0015](../decisions/0015-per-device-ssh-host-keys.md),
  [ADR 0018](../decisions/0018-db-json-version-is-release-date-driven.md)
