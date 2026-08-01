# ADR 0025 — Autodetect the timezone once, on first boot

**Status:** Accepted (2026-08-01) — decided by @mcfbytes
**Impact:** `board/mister/de10nano/rootfs-overlay/etc/init.d/S48timezone` (new),
`scripts/ci-tests.sh` / `scripts/test-timezone.sh`, and every user who flashes a
fresh card. It is the first unprompted outbound request this project *adds* — `ntpd`
already reaches the NTP pool at every boot, but that is stock's behaviour, not ours.
**Related:** [ADR 0015](0015-per-device-ssh-host-keys.md) (the other first-boot,
persist-to-FAT mechanism this mirrors), [ADR 0011](0011-resolv-conf-buildroot-default.md)
(read-only root, which is *why* the timezone has to live on the data partition).

## Decision

1. Ship `etc/init.d/S48timezone`. On a boot where **no timezone is set yet**, it asks a
   geo-IP service for the IANA zone of the box's public IP and copies the matching file
   from `/usr/share/zoneinfo/posix/` to `/media/fat/linux/timezone` — the file
   `/etc/localtime` already points at.
2. **One guess, spent when it is actually made.** The lookup is gated on two files on the
   data partition — the timezone itself, and a `timezone.autodetect` stamp — plus a
   default-route check. The stamp is written only when a provider **answered**: with a
   zone we could install, or with something unusable. *Being offline is not an answer*, so
   it does not spend the guess.
3. **Re-tried on the event, not on a timer.** `usr/lib/dhcpcd/dhcpcd-hooks/90-timezone`
   calls `S48timezone start` whenever dhcpcd brings an interface up with an address — so a
   box that was offline on its first boot gets its guess the moment the user finishes
   setting up Wi-Fi, on that boot or three boots later.
4. **Never overwrite a timezone that is already set**, whoever set it.
5. **No new package.** `curl` and the full zoneinfo set are already in the image.

## The problem

`/etc/localtime` is a symlink to `/media/fat/linux/timezone` (stock parity — the rootfs is
reflashed wholesale, so the timezone has to live on the FAT data partition to survive; see
[`docs/init-parity.md`](../init-parity.md) and the defconfig's tzdata block). On a fresh
card **that file does not exist**, so glibc silently falls back to UTC.

Silently is the operative word: the clock is *right*, it is just labelled wrong, so
nothing looks broken. Save-state and screenshot timestamps, `ls -l`, the OSD clock, syslog
and ntpd's own lines are all off by the local UTC offset until the user goes and finds
`timezone.sh` in the community Scripts repo. Most never do — for anyone west of Greenwich
the OSD clock is simply wrong, forever, on an otherwise perfectly configured box.

Stock has the same gap. Fixing it is a deliberate divergence.

## Why this shape

**Same mechanism as the community script, not a new one.** MiSTer-devel's
`Scripts_MiSTer/timezone.sh` (v1.4) already has an "Automatic" mode: query `ip-api.com`,
then `cp /usr/share/zoneinfo/posix/$TZ /media/fat/linux/timezone`. We use the same
provider, the same destination, and the same file format, so autodetection and a by-hand
`timezone.sh` run are interchangeable and either can overwrite the other. Inventing a
different mechanism would have meant two competing sources of truth for one file.

**Geo-IP, because the alternatives do not exist here.** The board has no RTC battery, no
GPS, no user locale to infer from, and no way to ask the user at boot (`Main_MiSTer` owns
the framebuffer; there is no first-run wizard to hook). DHCP option 100/101 (RFC 4833)
would be ideal and needs no third party — approximately no home router sends it.

**Once — but "once" means once we actually got to ask.** Autodetection is a *first-boot
event*, not a boot-time behaviour: a box that phones out on every boot for the rest of its
life, re-litigating a decision the user may have made by hand, is exactly what this must
not become. But spending the guess on a boot where there was no network to ask over would
be worse than useless, and that boot is *the common case*: a MiSTer card is flashed,
booted, and only then does the user write `wpa_supplicant.conf`. So the stamp is written
when a provider answered — usefully or not — and never merely because we tried.

**Triggered by dhcpcd, not by polling harder.** `S48` runs seconds after `S41dhcpcd`, and
no amount of waiting at S48 helps a box whose network appears three boots later.
`usr/lib/dhcpcd/dhcpcd-hooks/90-timezone` — the same extension point dhcpcd's own
`20-resolv.conf` and `30-hostname` use — calls `S48timezone start` on `BOUND`/`RENEW`/the
IPv6 equivalents, so the lookup happens the moment an address exists. S48 still tries
directly when a default route is *already* there (a wired box, or a static address), with
a short ~1 minute window to cover DNS lagging the route.

**Nothing on a box with no network.** `start` checks `/proc/net/route` for a default route
and returns before backgrounding anything if there is none: no query, no console line, no
stamp. And `start` never blocks regardless — it backgrounds the lookup, asserted by the
test suite, since a blocking lookup would stall `rcS` and therefore the whole boot.

## Trust and privacy — the honest version

This makes **one lookup, on one boot**, to a third party that necessarily sees the box's
public IP. Nothing else is sent — the request has no payload; the public IP the packet
already carries *is* the query — and nothing is stored remotely. ("One lookup" is up to 36
identical requests if the network is still coming up: the retry loop stops at the first
answer, and every retry carries the same nothing.)

- **It is opt-out-able before it ever runs.** `touch /media/fat/linux/timezone.autodetect`
  on the card (or setting a timezone by hand) means nothing is ever sent. The stamp file
  says so in its own body, which is why the body is prose rather than a marker byte.
- **`ip-api.com`'s free tier is HTTP-only**, so the request is in the clear and a hostile
  network can answer it. The blast radius is a wrong timezone. The answer is validated
  against the zoneinfo we actually ship before it is used as a path — no `..`, no absolute
  path, no shell metacharacters, no zone we do not have — so a hostile answer cannot
  become an arbitrary file read or a command. `scripts/test-timezone.sh` asserts each of
  those rejections, and the two that could pass vacuously are mutation-checked: with the
  guard removed they fail, which is the only thing that makes them evidence.
- An HTTPS provider (`ipapi.co`) is tried second, which also covers networks that block or
  intercept plain HTTP.

Stock's posture is not a useful baseline here: the Downloader fetches and executes updates
over the network by design. But "the box already talks to the internet" is not a licence
to add traffic silently, hence the disclosure above, the FAQ entry, and the opt-out.

## What it does not do

- **It cannot fix the clock of a process that is already running.** glibc reads
  `/etc/localtime` once and caches it, and `Main_MiSTer` starts from inittab's `sysinit`,
  *before* `rcS`. So on the very first boot the OSD clock stays UTC until the next reboot.
  Everything is correct from then on, permanently. Restarting `Main_MiSTer` underneath the
  user to close a one-boot cosmetic gap is not a trade worth making.
- **A box that is *never* online never gets a timezone.** Obvious, but worth stating: the
  guess is never spent, so nothing accumulates and nothing is retried in the background —
  the default-route check means an offline boot costs three `stat()` calls.
- **It does not touch `/etc/timezone`** (a label file nothing reads, `Etc/UTC`, stock
  parity) — `/` is read-only at that point in boot anyway.

## Alternatives considered

| Alternative | Why not |
|---|---|
| Ship a fixed non-UTC default | There is no correct one. UTC is at least honestly neutral. |
| Prompt the user at first boot | Nowhere to prompt: `Main_MiSTer` owns the display, and the serial console is not a user-facing surface. |
| DHCP option 100/101 (RFC 4833) | Correct, private, needs no third party — and effectively no consumer router emits it. Worth revisiting as a *preferred* source if that ever changes. |
| Retry on every boot until it succeeds | Rejected on the maintainer's instruction, and rightly: it turns a first-boot event into permanent boot-time behaviour. The dhcpcd hook gets the same coverage from an event instead of a timer. |
| Spend the guess on any *attempt*, offline or not | The first boot of a MiSTer is routinely offline — flash, boot, *then* configure Wi-Fi. That would burn the guess on precisely the boot that never had a chance. |
| A longer poll at S48 instead of the hook | Cannot cover a network configured on a later boot at all, and costs a background process minutes of retries on every offline boot to cover less. |
| Write `Etc/UTC` on failure instead of a stamp | Would make "we tried and failed" indistinguishable from "the user chose UTC", and would silently pin a real decision. |
| Bundle `timezone.sh` and tell users to run it | That is today's situation. It is exactly what nobody does. |

## Verification

`scripts/test-timezone.sh` — a sandboxed functional test (no build, no board, no network:
paths rewritten into a temp dir, `curl` stubbed; `/proc/net/route` and the dhcpcd hook
stubbed too). 15 cases / 60 assertions covering the
happy path, the never-overwrite rule (including that an *empty* timezone file counts as
unset, so a half-written card self-heals), the once-and-only-once contract, the opt-out
stamp, seven classes of hostile answer, both providers in order *and* the HTTPS fallback
actually taking over when the first provider is down, the degraded paths, the
offline-does-not-spend-the-guess rule and its inverse, the default-route gate, the
one-lookup-at-a-time lock, which dhcpcd reasons fire the hook (and that it returns to
dhcpcd rather than `exit`ing its hook run), and the "`start` must not block boot" property.

`scripts/ci-tests.sh`'s Timezone section runs it **twice** — once under the host shell,
once under the target's own BusyBox `ash` via `qemu-arm`, since this is a boot-path script
and dash-accepts-it is not the same claim as ash-accepts-it — and additionally asserts the
script ships executable and that `curl`, its one runtime dependency, is still in the image.

**Not yet verified on hardware**: the on-device first-boot path (real card, real DHCP)
has not been exercised. That belongs to the next hardware validation pass.
