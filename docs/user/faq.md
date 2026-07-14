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

The kernel is pinned to **6.18.38**. The hardware validation above ran on **6.18.33**, the
immediately prior 6.18.y patch release, via an earlier build — the jump to 6.18.38 is a
patch-level bump within the same stable series and is expected to behave identically, but
it has not itself been re-confirmed on real hardware as of this writing (CI builds and
tests it; a hardware re-boot on 6.18.38 is pending).

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
| Kernel | **5.15.1** (forked Nov 2021; never took a single `5.15.y` stable update) | **6.18.38** LTS, on a stable `.y` line with ongoing security backports |
| Buildroot | **2021.02.4** | **2026.02.3** — roughly five years newer |
| glibc | **2.31** | **2.42** |
| OpenSSL | **1.1.1** (end-of-life since 2023-09-11 — no upstream fixes since) | **3.6.2** |
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
