# Beta testing

**Short version:** this is a personal project offered opt-in. It is validated on one
DE10-Nano — mine. Everything it does is reversible in about a minute. If you run it and
tell me what happened, that is the single most useful thing anyone can do for it right
now.

---

## What "beta" means here, precisely

It does **not** mean "we think it works and haven't got round to the paperwork". It means
one specific, named thing is unmet:

**Nobody has committed, in writing, to tracking `6.18.y` kernel security releases through
that line's end of life.** That commitment is
[ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md), and until a named
maintainer signs it, this project does not get offered as something you should depend on.
Saying otherwise would be the one claim that undermines all the others.

That is a governance gap, not a "does it boot" gap. What follows is the "does it work"
picture, which is a separate question and is answered by evidence.

---

## What has actually been tested, and on what

Everything below was confirmed on **one real DE10-Nano**, booting **CI-built artifacts**
rather than a local build.

| Works, confirmed on hardware | |
|---|---|
| Boots to the MiSTer menu; cores load | ✅ |
| The unmodified, stock `MiSTer` binary runs | ✅ |
| All out-of-tree modules present; no kernel BUG/Oops/panic | ✅ |
| Bluetooth — firmware loads, controller pairs | ✅ |
| Wi-Fi — WPA3/SAE (PMF required), 5 GHz, auto-connect at boot, via mainline `rtw88` | ✅ |
| Downloader over HTTPS | ✅ |
| `update_all.sh` updates cores without disturbing this image | ✅ |
| `PREEMPT_RT` kernel variant boots and runs MiSTer | ✅ (on 7.2-rc4) |

| Builds and passes CI, but **no hardware has ever exercised it** | |
|---|---|
| Samba | ⚠️ |
| MIDI / MT-32 | ⚠️ |
| Most of the Wi-Fi/Bluetooth chipset table — Broadcom, MediaTek, Atheros, Redpine, Wi-Fi 6/6E | ⚠️ |
| The full `sdcard.img` flashed to a fresh card | ⚠️ |
| RT latency — **never measured**, so there is no evidence it improves anything | ⚠️ |

The authoritative, always-current version of this list is the **hardware validation
ledger** in the [README](../../README.md#hardware-validation-ledger). Treat anything not
listed there as unverified in practice.

**One known regression:** the Logitech **G923 PlayStation** variant loses force feedback
and range control (it still works as a plain joystick). The G923 Xbox variant and all
G29/G27/G25 wheels are unaffected.

---

## How to opt in

Follow [`onboarding.md`](onboarding.md). It is one script, and it configures the rest
itself.

The important property: **routine `update_all.sh` runs keep working normally** — cores,
ROMs, MRAs, Jotego — while this image stays put. Updating *this* image is a separate,
deliberate action (`Scripts/update_linux_modernization.sh`). Nothing happens to your
operating system that you did not ask for.

## How to get back out

[`rollback.md`](rollback.md). Two edits and a normal update run. It is safe at any time,
for any reason, and "I don't want to run this anymore" is a perfectly good reason — you do
not need to diagnose anything first.

Rollback is not a special code path: it is the same, well-exercised update mechanism
running in the other direction.

If the box will not boot at all, go to [`serial-recovery.md`](serial-recovery.md) instead.

---

## What to report

**"It just worked" reports are as valuable as bug reports** — arguably more so right now.
The tables above have a long "builds, never tested" column, and the only thing that moves
a row out of it is somebody plugging the hardware in. A one-line "RTL8812AU associated on
WPA2, no problems" is a real contribution.

Especially wanted, because I do not have the hardware:

- **Wi-Fi / Bluetooth dongles** that are not an RTL8822BU — Broadcom/Cypress,
  MediaTek MT7921/MT7925, Atheros `ath9k_htc`, Redpine, Realtek Wi-Fi 6
  (RTL8851BU/8852BU). Does it associate? Does firmware load? Does WPA3 work?
- **Samba** and **MIDI / MT-32**.
- **Controllers and wheels**, particularly ones with carried patches: GameCube adapters,
  Fanatec, GunCon 2/3, Wiimotes, NSO pads, DualSense, Flydigi.
- **USB storage** — exFAT, and the new NTFS support.
- **A fresh `sdcard.img` flash** onto a card that was not already a MiSTer.

### Where

GitHub Issues, using the templates:

- **Bug report** — <https://github.com/mcfbytes/Buildroot_MiSTer/issues/new?template=bug_report.yml>
- **Hardware test report** — <https://github.com/mcfbytes/Buildroot_MiSTer/issues/new?template=hardware_report.yml>

### What to include

1. **Your version.** `cat /MiSTer.version` (a 6-digit `YYMMDD`) and `uname -r`. Or just
   run `Scripts/update_linux_modernization.sh --status`, which prints both plus your
   update configuration.
2. **What you expected, and what happened instead.**
3. **The relevant log**, if there is one:
   - Update problems: `/media/fat/Scripts/.config/downloader/downloader.log`
   - Kernel problems: `dmesg` output, or a serial console capture if the box hangs before
     you can log in ([`serial-recovery.md`](serial-recovery.md) covers the wiring).
4. **The exact hardware**, for device reports — `lsusb` output is ideal, since the chipset
   is what matters and the marketing name on the box frequently isn't it.

See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for more detail.

---

## What you should expect from me

- No SLA, no guaranteed response window, and no promise this continues. That is what the
  unmet [ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md) gate means in
  practice, and pretending otherwise would be dishonest.
- Reports get read. Hardware reports get folded into the validation ledger with the result
  recorded either way — including the ones that say it didn't work.
- Anything genuinely dangerous (data loss, a box that won't boot) gets treated as the
  priority over everything else.

## See also

- [`onboarding.md`](onboarding.md) — opting in
- [`rollback.md`](rollback.md) — getting back to stock
- [`faq.md`](faq.md) — default credentials, SSH host keys, what changed vs stock
- [`serial-recovery.md`](serial-recovery.md) — if it won't boot at all
- [`sdcard-flashing.md`](sdcard-flashing.md) — the full-card image
