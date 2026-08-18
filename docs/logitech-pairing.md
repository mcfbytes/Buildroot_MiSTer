# Logitech pairing: `ltunify`, `mister-pair-logitech`, and why not Solaar

This document exists because of a specific, reasonable question: *should this
image ship software for pairing a Logitech device to a Unifying receiver?*

The answer is **yes, but only for one narrow thing** — the pairing handshake —
and the interesting part is how narrow it is. Almost everything a Logitech
keyboard or mouse does on this board is already handled by the kernel, with
nothing installed.

## 1. What already worked, before any of this

The kernel side is complete and matches stock exactly. From
`board/mister/de10nano/linux.config`, and confirmed in the resolved
`output/build/linux-6.18.*/.config`:

| Symbol | Value | What it buys |
|---|---|---|
| `CONFIG_HID_LOGITECH` | `y` | base Logitech quirk handling |
| `CONFIG_HID_LOGITECH_DJ` | `y` | **the receiver driver** |
| `CONFIG_HID_LOGITECH_HIDPP` | `y` | HID++ features, battery via `/sys/class/power_supply/hidpp_battery_N` |
| `CONFIG_LOGITECH_FF` | `y` | force feedback |
| `CONFIG_HIDRAW` | `y` | the raw node userspace pairing needs |

`CONFIG_HID_LOGITECH_HIDPP` is absent from our minimal defconfig and still
resolves to `y`, which is not luck: `HID_LOGITECH_DJ` `select`s it
(`drivers/hid/Kconfig:697`). This is the usual reminder that our `linux.config`
is `savedefconfig` output and an absent symbol is not an off symbol — read the
resolved `.config`.

`HID_LOGITECH_DJ` in particular is worth more than it looks. Its own Kconfig help
says what happens without it:

> Without this driver it will be handled by generic USB_HID driver and all
> incoming events will be multiplexed into a single mouse and a single keyboard
> device.

With it, each of the receiver's six slots enumerates as its own input device
with its own logical product ID — which is what Main_MiSTer identifies devices
by. So a Logitech keyboard/mouse combo that arrived pre-paired in its box works
on a stock-configured MiSTer with **no userspace at all**, and that is the
overwhelmingly common case. Logitech ships devices paired to their bundled
receiver.

## 2. The one gap: pairing

There is no kernel interface for the pairing handshake. No sysfs knob, no ioctl,
no `echo 1 > .../pair`. `hid-logitech-dj` drives already-paired devices and asks
the receiver what is paired; it has never had a way to *make* a pairing.

That matters in exactly three situations:

* the original receiver was lost or died, and you have a spare
* a bare dongle — second-hand, or paired to somebody else's keyboard
* a keyboard and a mouse you want on **one** dongle instead of two

All three are re-pairing, and all three are things you could equally do on a
desktop PC before bringing the receiver over. The reason to have it on-device is
that the desktop is not always there, and a MiSTer with no working keyboard is
not a machine you can easily fix from a MiSTer with no working keyboard.

## 3. Why not Solaar

Solaar is the better-known and genuinely better tool. It is actively maintained
(1.1.20, 2026-06-28), and it covers hardware ltunify does not — Bolt, Lightspeed,
and per-device feature configuration. It was rejected anyway, on packaging cost:

* **Its only entry point is the GUI one.** `setup.py` declares exactly one
  console script, `solaar = solaar.gtk:main`. `lib/solaar/gtk.py` imports
  `solaar.ui` at module level, and `lib/solaar/ui/__init__.py` does
  `import gi` / `gi.require_version("Gtk", "3.0")`. So `solaar pair` needs GTK 3
  resident even though it never opens a window. This image has **zero** X11 or
  GTK packages and no display server.
* **Two of its dependencies are not packaged either.** Buildroot 2026.05.1 has
  `python-pyudev`, `python-psutil`, `python-pyyaml`, `python-xlib`,
  `python-evdev`, `python-gobject`, `python-pycairo` and
  `python-typing-extensions` — but no `python-dbus` and no `python-hid-parser`.
* **Getting the CLI without the GUI means carrying a patch** against
  `solaar/gtk.py` to defer the `solaar.ui` import past CLI dispatch, and keeping
  it applying across upstream releases, forever, for a tool run maybe once in a
  MiSTer's life.

That is a display stack plus two new packages plus a carried patch, versus two C
files and `-lrt`. If Solaar ever grows a GUI-free entry point, this decision is
worth reopening; that is the recheck condition.

`libratbag`'s `lur-command` was the third candidate. Also not in Buildroot, and
`ratbagd` is a much heavier daemon aimed at gaming-mouse configuration.

## 4. Why `ltunify` needs a wrapper

`ltunify` is `package/ltunify`, pinned to master HEAD (`b68dc9af`, 2020-06-14 —
upstream is finished, see the `.mk` for why the commit and not the `v0.3` tag).
It is ~40 KiB installed and links nothing but libc.

It is also, run bare on this board, capable of three specific kinds of quiet
wrongness. `/usr/sbin/mister-pair-logitech` exists for these three reasons and
no others:

### 4.1 It picks the first hidraw node it finds

`open_hidraw()` (`ltunify.c:1158`) globs
`/sys/class/hidraw/hidraw*/device/driver`, filters on vendor `046d` and a
receiver driver name, and takes the first hit. The comment in the loop says so
outright: *"Assume that the first match is the receiver."*

That is wrong in two separate ways on this board.

**Two receivers.** Re-pairing is precisely the case where two are plugged in —
the old one and the new one. Pairing writes to whichever the glob returned first,
and nothing tells you which that was.

**One receiver, several nodes.** `hid-logitech-dj` claims more than one interface
per receiver, and how many survive to become hidraw nodes depends on the family
(`logi_dj_probe`, and the `no_dj_interfaces` switch above it):

| Family | `driver_data` | hidraw nodes |
|---|---|---|
| Unifying `c52b`/`c532` | `recvr_type_dj` | **one** — probe returns `-ENODEV` for any interface without a HID++ collection |
| Nano `c534` | `recvr_type_hidpp` | **two** — that `-ENODEV` guard is `recvr_type_dj`-only |
| Nano `c52f` | `recvr_type_mouse_only` | **two** |
| Lightspeed/Powerplay | `recvr_type_gaming_hidpp` | up to **three** |

So a per-node view shows one perfectly ordinary Nano dongle as two receivers.
ltunify papers over this with a hardcoded special case — skip interface 0 on
`c534` — which covers exactly one product.

The wrapper instead **groups hidraw nodes by physical USB device** and emits one
record per receiver. Within a group it picks the node that actually declares the
HID++ vendor collection (usage page `0xFF00`, usage `0x01` — the same
`rep->application == 0xff000001` test `logi_dj_probe` uses), falling back to the
highest interface number. That is ltunify's `c534` rule generalised to every
family, derived rather than hardcoded. The chosen node is then pinned with
ltunify's own `-d` flag.

With two receivers present and no answer readable, the wrapper refuses rather
than guessing.

### 4.2 It mishandles receivers it cannot drive — in both directions

| Product ID | Family | Driver on 6.18 | ltunify |
|---|---|---|---|
| `046d:c52b`, `c532` | Unifying | `logitech-djreceiver` | supported |
| `046d:c52f`, `c534` | Nano | `logitech-djreceiver` | supported |
| `046d:c548` | Bolt | **`hid-multitouch`** | **no** — different pairing protocol |
| `046d:c539`, `c53a`, `c53f`, `c543` | Lightspeed / Powerplay | `logitech-djreceiver` | **no** |
| `046d:c51b` | 27 MHz | `logitech-djreceiver` | **no** — predates HID++ |

The IDs come from the kernel's own `drivers/hid/hid-ids.h` and
`logi_dj_receivers[]`, not from a web page — and reading that table is what turns
up the asymmetry:

* **Lightspeed, Powerplay and 27 MHz receivers bind as `logitech-djreceiver`**,
  identically to Unifying ones. They pass ltunify's driver-name test and then
  fail at the register write, or sit there until the window times out.
* **Bolt is not in `logi_dj_receivers[]` at all.** On this kernel `c548` is
  claimed by `hid-multitouch`. So ltunify's driver-name test *rejects* it, and
  it prints `No Logitech Unifying Receiver device found` at somebody looking
  straight at the dongle in the port.

The wrapper therefore classifies by USB product ID **independently of which
driver claimed the device**, and only then looks for a node ltunify could use.
That is what lets a Bolt receiver be named and refused with a reason instead of
being invisible.

### 4.3 It always exits 0

This is the one that would have caused a real support burden. Read the bottom of
ltunify's `main()`: every command path that gets as far as opening the receiver
falls through to a single `return 0`. A pairing **timeout** exits 0.
`perform_pair()` returns `void`. "Device not found" exits 0. Even "Unhandled
command" exits 0.

So exit status carries no information, and any wrapper that trusted it would
report success for a pairing that never happened. `mister-pair-logitech` instead
reads the six pairing slots **before and after** and diffs them. That works
because ltunify's slot list reflects *paired*, not *powered on* — its own field
is `bool device_present; // whether the device is paired` (`ltunify.c:212`).

The diff is the success signal, and it is also what produces the useful failure
message: when nothing changed, the tool says so and lists the actual causes
(device not power-cycled in the window, flat batteries, it is a Bluetooth device,
it is a Bolt device).

**The same quirk bites the slot read itself, which is subtler.** When ltunify
cannot talk to the receiver, `list` writes `Unable to request a list of paired
devices` to stderr and still exits 0, emitting no `idx=` lines — byte for byte
what a receiver with six empty slots produces. Taking that at face value would be
worse than useless: it reports "all six slots are free" for a receiver that is
full, skips the slots-full pre-check, and then blames flat batteries for what was
really an unreadable receiver.

So the read is gated on the `Connected devices:` banner, which ltunify's `main()`
only reaches inside `if (get_all_devices(fd))` — present if and only if the slot
table was genuinely read. A failed read aborts `pair` and `unpair` outright,
quoting ltunify's own stderr; in `list` it is reported per receiver and the other
receivers are still shown, since `list` is what you run to find out what is wrong.

Each command reads the slot table **once** and reuses it for the display, the
slots-full check and the diff baseline. Reading it repeatedly would let the list
printed on screen disagree with the list the diff was computed against — and a
transient failure on only the first read would produce the worst outcome
available: an empty baseline, so every device already on the receiver reappears
under "New:" beneath a headline of "Paired."

## 5. Shape on the card

Same shape ADR 0026 established for `check_storage.sh`, for the same reason:

```
/media/fat/Scripts/pair_logitech.sh   <- shim, ~10 lines of logic
        exec
/usr/sbin/mister-pair-logitech        <- the tool, in the read-only rootfs
        drives
/usr/bin/ltunify                      <- the pinned upstream binary
```

The tool is version-locked to the ltunify build whose command grammar it drives
and whose exit-status quirk it works around. Both ship inside one `linux.img`
and cannot drift. A `Scripts/` copy updated on its own could invoke a flag the
installed ltunify does not have, and the failure would land in the middle of a
pairing window.

All three of this project's `Scripts/` entries arrive by one route and are
treated as one set by `install.sh`, `uninstall.sh --remove-script`,
`scripts/fetch-sdcard-payload.sh` and the updater's
`ensure_companion_scripts()`.

### It must work with no keyboard attached

Load-bearing, and it shapes the CLI. If the keyboard being paired is the only
keyboard, then at the moment this runs there is no keyboard — the user reached
the Scripts menu with a gamepad.

So the no-argument default is **pair**, and with exactly one usable receiver it
completes without asking anything. Prompts appear only where a choice genuinely
cannot be inferred, and where no answer can be read the tool refuses instead of
guessing. Everything else it can do (`list`, `unpair`, `info`, `receiver`) is for
an SSH session, where typing is possible.

`unpair` is the one operation that asks for confirmation even in the
single-receiver case: pairing is additive and harmless, while unpairing the
keyboard you are typing on is a way to strand yourself. **Without an answer it
does not proceed** — falling through when stdin is not a terminal would make a
destructive operation the default for every pipeline and boot script, which is
the opposite of the posture everything else here takes. `--yes` is the way to
say "I have decided" ahead of time; nothing else is.

`--yes` therefore means one thing and not another, and the two need stating
together because the same flag reaches both:

* a **confirmation** — "unpair slot 2?" — is taken as yes;
* a **choice with no safe default** — which of two receivers you meant — still
  fails. Answering a yes/no is not the same as inventing which dongle was
  intended.

(On a console with no keyboard attached, stdin *is* a terminal but nothing can be
typed. The prompt times out to No and changes nothing, which is the right
outcome for that case.)

## 6. What is deliberately not shipped

* **`42-logitech-unify-permissions.rules`**, which upstream's `make install`
  would drop in. It hands *desktop seat users* access to the receiver's hidraw
  node through `TAG+="uaccess"`, which needs logind/elogind — not installed. Its
  `MODE="0660", GROUP="plugdev"` line is commented out upstream anyway. This
  image has one account, root, which already opens the default `0600 root:root`
  node. Same call, same reasoning, as `package/dualsensectl`. `scripts/ci-tests.sh`
  asserts its absence so a future "fix ltunify.mk to use `make install`" fails
  loudly.
* **`read-dev-usbmon`**, upstream's usbmon-capture debugging tool. It needs
  `CONFIG_USB_MON` (not enabled) and its `hidraw.c` helper is described by
  upstream's own README as "currently unusable, it does not process data
  correctly". `LTUNIFY_BUILD_CMDS` builds only the `ltunify` target so it never
  appears; also asserted absent.
* **Any automatic invocation.** No init script, no udev rule, nothing on the boot
  path. Pairing is a deliberate act, and a receiver being plugged in is not
  consent to rewrite its slot table.

## 7. Verification

### Package

Cross-compiled for ARMv7 with the toolchain and the exact flags
`TARGET_CONFIGURE_OPTS` passes (`-O2 -g0 -D_FORTIFY_SOURCE=1`, gcc 14.4 /
glibc 2.43):

* **Clean build, zero warnings.** The v0.3 tag is not clean under the same
  flags — it emits the `fscanf` `warn_unused_result` warning at
  `ltunify.c:1217` — which is the whole reason the `.mk` pins master HEAD.
* **30,216 bytes stripped.** The cheapest package in the image.
* **`NEEDED: libc.so.6` and nothing else.** `-lrt` resolves to nothing extra on
  glibc 2.43, where librt is merged into libc.
* **`read-dev-usbmon` correctly not built**, and `ltunify --version` reports the
  pinned SHA rather than an empty string.

`make mister_de10nano_defconfig` against the external tree resolves
`BR2_PACKAGE_LTUNIFY=y`, leaves `BR2_PACKAGE_LIBEXECINFO` unselected (correct on
a glibc toolchain), and `LTUNIFY_SOURCE` matches the filename on the `.hash`
line character for character.

### Wrapper

Off-hardware, against synthetic `/sys/class/hidraw` trees and a stub `ltunify`,
**50 scenarios across six rigs** pass. The rigs reproduce the multi-node reality
above — including report descriptors with and without the HID++ collection — so
the grouping is exercised, not assumed:

| Rig | Contents | What it proves |
|---|---|---|
| A | 13 nodes: Unifying, Bolt-on-`hid-multitouch`, two Nanos, Lightspeed, a DualSense, a **wired** Logitech mouse, a `logitech-djdevice` child | grouping into 5 receivers; wired 046d hardware and DJ children excluded; HID++ node chosen; naming a sibling node resolves to it |
| B | Bolt + Lightspeed only | both families named and refused, one reason each |
| C | no Logitech hardware | the "not found" path |
| D | one Unifying receiver | **pairs with no prompt at all** — the no-keyboard case |
| E | one Nano receiver, two nodes | seen as **one** receiver, not two |
| F | Unifying PID bound to a driver ltunify cannot use | the "should not be reachable" guard fires with a real message |

Plus, across those: pairing success and timeout distinguished by slot diff (the
only way to tell, given the always-exit-0 behaviour), the unpair round-trip, and
argument validation.

A further eight scenarios drive the stub's `list` into the always-exit-0 failure
mode described in §4.3 — both permanently and on the first call only — and assert
that an unreadable receiver never reads as "all six slots are free", never sails
past the slots-full pre-check, never reports pre-existing devices as newly
paired, and never turns into "slot N is already free" during an unpair.

Eight more cover the `--yes`/confirmation rule above, driven through a real pty
so the typed `y`/`n` path is exercised rather than mocked: `unpair` without a
terminal and without `--yes` refuses **and the slot is asserted still paired**;
`--yes` proceeds and the slot is asserted gone; a typed `n` changes nothing; and
`--yes` still refuses to pick between two receivers.

That covers the enumeration and decision logic, which is where the wrapper's
value is.

### Not yet done

**No hardware test.** Nobody has run this against a physical Unifying receiver.
The HID++ register traffic is entirely ltunify's, unmodified and unpatched, but
"ltunify still works against a 2026 kernel's `hid-logitech-dj`" is a claim this
project has not tested, and the enumeration was exercised against a synthetic
sysfs rather than a real one. The on-device test is: plug in a Unifying
receiver, run `mister-pair-logitech list` and check it reports the receiver and
its slots, then pair a device and confirm the slot diff reports it.

**No full image build.** The package was validated by direct cross-compile and a
Kconfig pass, not by a `make all` that puts `/usr/bin/ltunify` into a
`rootfs.tar`. The `ci-tests.sh` assertions added for it therefore have not run
against a real build yet; the first CI run on this branch is what exercises them.
