# ADR 0025 — Autodetect the timezone once, on first boot

**Status:** Accepted (2026-08-01) — decided by @mcfbytes
**Impact:** `board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/90-timezone` (new),
`scripts/ci-tests.sh` / `scripts/test-timezone.sh`, and every user who flashes a
fresh card. It is the first unprompted outbound request this project *adds* — `ntpd`
already reaches the NTP pool at every boot, but that is stock's behaviour, not ours.
**Related:** [ADR 0015](0015-per-device-ssh-host-keys.md) (the other first-boot,
persist-to-FAT mechanism this mirrors), [ADR 0011](0011-resolv-conf-buildroot-default.md)
(read-only root, which is *why* the timezone has to live on the data partition).

## Decision

1. Ship **one file**, `usr/lib/dhcpcd/dhcpcd-hooks/90-timezone`. The first time dhcpcd
   brings an interface up with an address and **no timezone is set yet**, it asks a geo-IP
   service for the IANA zone of the box's public IP and copies the matching file from
   `/usr/share/zoneinfo/posix/` to `/media/fat/linux/timezone` — the file `/etc/localtime`
   already points at. No init script, no boot-time path.
2. **One guess, spent when it is actually made.** The lookup is gated on two files on the
   data partition — the timezone itself, and a `timezone.autodetect` stamp. The stamp is
   written only when a provider **answered with a zone
   name**: one we install, or one we do not ship (asking again tomorrow will not help).
   *Being offline is not an answer, and neither is HTTP 200* — see the captive-portal note
   below.
3. **Driven by the event, not by a timer.** The trigger *is* dhcpcd's address event — so a
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

**A dhcpcd hook, not an init script.** The event we want is "this box now has a network",
and dhcpcd already publishes it — on the same extension point its own `20-resolv.conf` and
`30-hostname` use. An init script can only ask "is there a network *right now*, a few
seconds into boot", which is the wrong question twice over: on a DHCP box the lease has
usually not landed by S48, and on the normal MiSTer card the first boot has no network at
all.

This started as *both* — an `S48timezone` plus a hook that called it — and the init script
was removed on review. On DHCP it was near-redundant (at S48 there is usually no route, so
it did nothing and the hook did the work), and it earned its keep only for static-IP boxes,
which never run dhcpcd. That gap is **accepted deliberately**: configuring a static address
is already a by-hand act, and running `timezone.sh` is the same kind of act. The redundant
path also carried its own bug — a `/proc/net/route` check whose IPv6 arm matched the
kernel's always-present `ip6_null_entry` (the `::/0` *unreachable* route on `lo`), so it
reported a route on any IPv6-enabled box with no connectivity at all. One trigger, one
file. The retry window inside the hook is small on purpose — 3 rounds x 2 providers, and
`20-resolv.conf` has already run in the same hook pass so DNS is configured — because
further retries come free with the next address event.

**A captive portal must not spend the guess.** This is the sharp edge of "spend it when a
provider answered", and it is worth stating because the obvious implementation gets it
wrong: a hotel/airport/school portal — and an ISP that serves a search page for NXDOMAIN —
answers the request with a perfectly good HTTP 200 carrying HTML. Treating a 200 as "we
asked and got something" would spend the one guess on precisely the network that stops
intercepting an hour later, stranding the box on UTC for the life of the card. So the guess
is spent only once the body *parses as a zone name*: HTML is not an answer, it is
interference. `scripts/test-timezone.sh` asserts both halves, and the assertion is
mutation-checked — with the guard reverted, it fails.

**Nothing on a box with no network.** The hook cannot fire without an address, so an
offline box does nothing at all: no query, no console line, no stamp, no process. And it
never blocks — the body is a backgrounded subshell, so dhcpcd, which waits on its hook run,
is not held up. Being *sourced* makes two more things correctness properties rather than
style: it must not `exit` (that would end dhcpcd's whole hook run, taking `20-resolv.conf`
and `30-hostname` with it) and it must not leak a variable or function into dhcpcd's shell.
The subshell answers both at once, and the suite asserts both.

## Trust and privacy — the honest version

This makes **one lookup, on one boot**, to a third party that necessarily sees the box's
public IP. Nothing else is sent — the request has no payload; the public IP the packet
already carries *is* the query — and nothing is stored remotely. ("One lookup" is up to 12
identical requests if the network is still coming up — 6 rounds x 2 providers: the retry
loop stops at the first answer, and every retry carries the same nothing.)

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
  a box that never connects never fires the hook at all.
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
| Keeping an init script *as well as* the hook, for static-IP boxes | Two triggers for one event, where the second fires almost never (at S48 a DHCP lease has usually not landed) and needed a route check that was itself buggy. Anyone who sets a static address by hand can set a timezone by hand. |
| Write `Etc/UTC` on failure instead of a stamp | Would make "we tried and failed" indistinguishable from "the user chose UTC", and would silently pin a real decision. |
| Bundle `timezone.sh` and tell users to run it | That is today's situation. It is exactly what nobody does. |

## Verification

`scripts/test-timezone.sh` — a sandboxed functional test (no build, no board, no network:
paths rewritten into a temp dir, `curl` stubbed, and the hook sourced exactly as
`dhcpcd-run-hooks` sources it — under `$TZ_TEST_SH`, so the target CI legs genuinely parse
and run it as the target's own shells). 16 cases / 60 assertions covering the
happy path, the never-overwrite rule (including that an *empty* timezone file counts as
unset, so a half-written card self-heals, and that a timezone set *while the lookup runs*
is not clobbered), the once-and-only-once contract, the opt-out stamp, nine classes of
hostile answer, both providers in order *and* the HTTPS fallback actually taking over when
the first is down, the captive-portal rule and its inverse, the one-lookup-at-a-time lock,
which dhcpcd reasons fire it and which do not, `if_up` handled as data rather than executed
(unset, empty and junk all read as not-up), that it returns to its caller instead of
`exit`ing dhcpcd's hook run, that it leaks nothing into the shell that sourced it, and that
the sourcing shell returns while the lookup is still in flight.

`scripts/ci-tests.sh`'s Timezone section runs it **three times** — once under the host
shell, once under the target's own `bash --posix` via `qemu-arm`, once under the target's
BusyBox `ash` — since this is a boot-path script and dash-accepts-it is not the same claim
as the-box's-shell-accepts-it — and additionally asserts the script ships executable and
that `curl`, its one runtime dependency, is still in the image. (Addendum 2026-09-03: this
ADR originally said *twice*, host + ash, because `/bin/sh` was BusyBox ash at the time.
Issue #144 made `/bin/sh` bash as on stock, so the shell that actually sources this hook
on the box is bash in POSIX mode; the ash leg is kept as the stricter interpreter.)

**Not yet verified on hardware**: the on-device first-boot path (real card, real DHCP)
has not been exercised. That belongs to the next hardware validation pass.
