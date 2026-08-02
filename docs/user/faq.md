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

Practically: opt in once (see [`onboarding.md`](onboarding.md)), then run
`Scripts/update_linux_modernization.sh` whenever you want to pull a new release — it uses
the same on-device Downloader machinery official updates use, and a device already on the
current release is correctly recognised as such and left alone.

**Note that this image does *not* install itself during a routine `update_all.sh` run**,
by design. Opting in sets `update_linux = false`, which stops *every* normal run from
applying *any* Linux image — that is what keeps the official image from overwriting this
one, since the two would otherwise race for the single Linux update slot the Downloader
allows per run. Your cores keep updating exactly as before; only the Linux image is
gated, and only that one script lifts the gate.

---

<a id="reverted-to-stock"></a>
## I was running this image, ran my normal update, and it put stock back. Was that a bug?

No — and it's worth knowing why, because the same mechanism is what makes rollback safe.

The version check is a plain "is it different?" comparison. It has **no concept of newer
or older**: there is no date parsing and no `<`/`>` anywhere in it. So whenever the
official database is the only one offering a Linux entry, it sees that your version isn't
the official one and reinstalls stock — regardless of your version being "higher."

It happens whenever `update_linux` is **not** `false` on that card, because that setting
is the only thing standing between the official Linux entry and your image. The usual
causes:

- **The image was installed some other way** — copied on by hand, restored from a backup —
  without ever running `Scripts/update_linux_modernization.sh`, so the setting was never
  written. Run it once; see [`onboarding.md`](onboarding.md#step-1).
- **Something set `update_linux` back to `true`.** Boot-time upkeep repairs this on the
  next boot, so it should be self-correcting. Check with
  `Scripts/update_linux_modernization.sh --status`.
- **An updater launched under a different script name.** The Downloader derives which
  `.ini` it reads from the launcher's own filename, so a renamed copy (say
  `Scripts/mycopy.sh`) reads `/media/fat/mycopy.ini` — a file we have never written, where
  the Linux update defaults to on. `update.sh` and `update_all.sh` both reach
  `downloader.ini` and are unaffected; see
  [ADR 0025](../decisions/0025-update-linux-kill-switch-and-private-updater.md).

**How to tell it happened at all:** this image records the version it expects, and the
next boot after a revert prints a loud banner on the console and writes
`Scripts/.config/mister_linux_modernization/REVERTED`.

**The fix in every case:** run `Scripts/update_linux_modernization.sh`. It repairs the
setting and reinstalls the image. (If you *wanted* stock back, congratulations — you've
already done it. See [`rollback.md`](rollback.md).)

---

<a id="opted-in-nothing-happened"></a>
## I opted in, the update ran fine, and nothing happened. Why?

In order of how often it's the cause:

1. **You ran a *normal* update, not this project's script.** This is by far the most
   common reason, and it is intentional: `update_all.sh` and `Scripts/update.sh`
   deliberately apply no Linux image at all now. Run
   `Scripts/update_linux_modernization.sh` — that is the only thing that updates this
   image.
2. **You're already on this image.** Updates are offered once; if your `/MiSTer.version`
   already matches the current release, a run that changes nothing is the correct result.
   `--status` tells you both numbers side by side.
3. **The script reported "UPDATE DID NOT HAPPEN".** That is not the same as nothing
   happening — it means the Downloader ran, reported no error, and still installed no
   image. The usual cause is running out of space on `/media/fat` partway through
   extraction. The Downloader's exit code cannot report that (it does not inspect the
   Linux update's result at all), which is exactly why the script checks separately.
   Free some space and try again; the log named in that message says which phase failed.

The quickest way to distinguish these is a deterministic one-off run:
`/media/fat/Scripts/update.sh --run-only mister_linux_modernization`. If that installs the
image, the problem was #3 or #4. If it still does nothing, it's #1 or #2.

---

## My MiSTer picked its own timezone by itself. What was that?

**This image looks up your timezone once**, the first time it connects to a network, and
writes it to `/media/fat/linux/timezone` — the file `/etc/localtime` points at, and the
same file the community `timezone.sh` script writes. Stock leaves that file missing, so a
fresh card runs on **UTC** forever unless you go and set it by hand; if you are anywhere
west of Greenwich, every save-state timestamp, screenshot name and OSD clock is quietly
wrong.

**What is sent.** A request to `ip-api.com` — the same service `timezone.sh`'s
"Automatic" mode uses — which sees your public IP and answers with a timezone name like
`America/New_York`. That is the whole exchange: the request carries nothing else, and
nothing is stored remotely. It happens **once**: once a provider has answered with a
timezone name, the box never asks again.

A captive portal — a hotel or airport login page, or an ISP that shows a search page for a
name that does not exist — does **not** count as an answer, even though it replies. Those
networks stop intercepting eventually, and the box would be stuck on UTC forever if a login
page could use up its one lookup.

**That first request is plain HTTP, not HTTPS.** ip-api.com's free tier does not offer TLS,
and it is the provider the community script already uses. So anyone who controls your
network can read that request, and can answer it in place of ip-api. What that buys them is
a wrong clock: the answer is only ever used to pick a file out of the zoneinfo already on
your card, and anything that is not a timezone this image ships is discarded unread. It
cannot become a download, a command, or a file of their choosing. A second provider,
`ipapi.co`, is tried over HTTPS when the first does not answer — which also covers networks
that block or intercept plain HTTP. If a cleartext request is not acceptable on your
network at all, opt out below and set the timezone by hand.

**It will never overwrite a timezone you set.** Run `timezone.sh`, or drop a zoneinfo
file at `/media/fat/linux/timezone` yourself, and that is final.

**To opt out before it ever runs**, create an empty file called `timezone.autodetect` in
the `linux` folder of your SD card, next to `wpa_supplicant.conf`. Nothing will be sent.
(That is the same file the box writes itself once a provider has answered — you can open
it, it explains itself.)

**If your box had no network on its first boot, nothing is lost.** Being offline is not an
answer, so the one guess is not spent — and nothing is even sent, because the lookup is not
something the box does at boot and then gives up on. It is attached to the moment the
network actually arrives, so with no network there is nothing to send and nothing to give
up on. That moment is when the box gets an address: finish setting up Wi-Fi, and it fires on that connection, whether that is
the same boot or three boots later. (It is a dhcpcd hook, sitting in the same place as the
one dhcpcd uses to update `/etc/resolv.conf`.) If you use a **static IP** set only in
`/etc/network/interfaces`, dhcpcd never runs and this never fires — set the timezone with
`timezone.sh`.

**One cosmetic wrinkle on the boot where it lands:** the menu clock can still show UTC
until you reboot once. The timezone is read by each program when it starts, and the MiSTer
menu starts before the lookup finishes. It is correct from the next boot on, permanently.

**To make it try again** after it has settled on something you do not want: delete both
`timezone` and `timezone.autodetect` from the `linux` folder, then reconnect or reboot — or just run
`timezone.sh`, which is quicker and lets you pick.

Full reasoning, including why geo-IP rather than something that talks to nobody:
[ADR 0025](../decisions/0025-first-boot-timezone-autodetect.md).

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

- [`onboarding.md`](onboarding.md) — how to opt in, and why there is no longer a multi-database race to lose
- [`rollback.md`](rollback.md) — how to get back to stock
- [`serial-recovery.md`](serial-recovery.md) — recovering a box that won't boot
- [`beta-testing.md`](beta-testing.md) — the broader personal-use/beta posture
- [ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md),
  [ADR 0015](../decisions/0015-per-device-ssh-host-keys.md),
  [ADR 0018](../decisions/0018-db-json-version-is-release-date-driven.md),
  [ADR 0025](../decisions/0025-first-boot-timezone-autodetect.md)
