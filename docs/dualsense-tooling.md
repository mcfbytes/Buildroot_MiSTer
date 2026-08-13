# DualSense tooling: `dualsensectl`, and why it does not replace the kernel patches

This document exists because of a specific, reasonable question: *can the Sony
DualSense kernel patches be replaced with udev rules and scripts that call
`dualsensectl`?*

The answer is **no** — not for the patches this image carries — and the reason
is worth writing down, because the patches look replaceable until you check
what actually consumes them. The tool was still added
(`package/dualsensectl`, `BR2_PACKAGE_DUALSENSECTL=y`), because it covers a
genuinely different surface: the parts of the controller the kernel driver
exposes no interface for at all.

## The patches in question

Four PlayStation patches live in `board/mister/de10nano/linux-patches/`, three
of them DualSense:

| Patch | What it does |
|---|---|
| `0033-hid-playstation-dualsense-player-id-led.patch` | replaces vanilla's five auto-assigned `:white:player-N` LED classdevs with stock MiSTer's single writable `<hid-dev>:player_id` (brightness 0–6) |
| `0037-hid-playstation-dualsense-mute-btn-z.patch` | reports mic-mute as `BTN_Z`, removes the in-kernel mic toggle, adds a userspace-owned `<hid-dev>:mute` LED |
| `0042-hid-playstation-stock-lightbar-led-names.patch` | registers stock's plain `:red`/`:green`/`:blue` lightbar classdevs beside mainline's multicolor node, and clears the player row at probe |
| `0022-hid-playstation-ds4-mac-fix.patch` | DualShock 4, not DualSense — out of scope here |

## Why userspace cannot stand in

### The consumer is Main_MiSTer, and its contract is sysfs paths

`get_led_path()` (`work/Main_MiSTer/input.cpp:2642-2659`) takes the input
device's sysfs path, truncates it at `/input/`, and appends `/leds` plus the
HID device's own name. `set_led()` then appends `:player_id/brightness`:

```c
sprintf(path, "/sys%s", input[dev].sysfs);
char *p = strstr(path, "/input/");
if (p) {
    *p = 0;
    char *id = strrchr(path, '/');
    strcpy(p, "/leds");
    if (add_id && id) strncat(p, id, p - id);
    return path;
}
```

So the LED class device must be **a child of the HID device**, named from it.
That rules out every userspace mechanism:

- **udev rules cannot create LED class devices at all.** They react to device
  events; they do not register kernel objects.
- **`uleds` (`CONFIG_LEDS_USERSPACE`, `/dev/uleds`) can** create an LED
  classdev from userspace with an arbitrary name — but it registers under the
  uleds misc device, i.e. `/sys/devices/virtual/leds/...`. `get_led_path()`
  builds a path under the *pad's* devpath and would never look there. (It is
  also not enabled in `board/mister/de10nano/linux.config`.)

### `0033` is load-bearing beyond the LED row

At `input.cpp:2702` the **return value** of the `:player_id` write is the
discriminator between the DualSense branch and the DualShock 4 fallback:

```c
if (set_led(led_path, ":player_id", (num > 5) ? 0 : num)) {
    //duslsense
    set_led(led_path, ":blue",  (num == 0) ? 128 : 64);
    ...
} else {
    //dualshock4
    ... color_code[num] ...
}
```

Drop `0033` and the failure is not "no player LEDs" — it is that every
DualSense silently takes the DualShock 4 colour-code path. `0042` is what makes
the three colour writes on the success branch land.

### `0037` (BTN_Z) is the hardest no

Vanilla handles the mic-mute button entirely in-kernel (`last_btn_mic_state`)
and never reports it to the input layer. There is no event for udev, for
`dualsensectl`, or for any userspace process to react to — only the raw HID
report carries the bit.

`dualsensectl` is output-only here: it can drive the mute LED, it cannot
manufacture an input event. A `hidraw`→`uinput` daemon could, but it would put
`BTN_Z` on a **separate** input device, and that breaks two things:

1. Main_MiSTer binds buttons per device, so the extra button lands on a
   phantom pad.
2. `BTN_Z` is `0x135`, between `BTN_Y` (`0x134`) and `BTN_TL` (`0x136`).
   evdev assigns joystick button indices in ascending code order, so the
   button's presence **on the same device** shifts every later
   `gamecontrollerdb` `bN` index. This is not theoretical: it is the
   regression seen when the RT beta series dropped `0037` (PS-button → OSD
   broke).

There is also no knob — no module parameter, no sysfs attribute, no udev
property — to stop vanilla's in-kernel toggle from firing on every press. It
would keep muting the mic and flipping the LED underneath whatever userspace
did.

## What `dualsensectl` *is* good for

Everything the kernel driver has no interface for. This is why the package was
added rather than dismissed:

- adaptive trigger effects (feedback, weapon, bow, galloping, machine,
  vibration, and the raw per-zone forms)
- audio routing between internal speaker and headphone jack, output volume,
  rumble/trigger attenuation
- microphone mode (`chat`/`asr`/`both`) and microphone volume
- player/mic LED dimming (`led-brightness`)
- controller power-off over Bluetooth
- firmware info, battery level

None of these has a sysfs interface, and none overlaps with what the patches
provide.

## Packaging decisions, and their reasons

**Pin.** `v0.7` (2025-02-08), upstream's newest release tag. Upstream Buildroot
2026.05.1 has no `dualsensectl` package. Build system is meson — this is the
external tree's first `$(eval $(meson-package))`.

**Dependencies.** Straight from upstream's `meson.build`:
`libudev` → `udev`, `dbus-1` → `dbus`, `hidapi-hidraw` → `hidapi`. Both `dbus`
and `libusb` (hidapi's other leg) were already in the defconfig, so the new
**libraries** are **hidapi** and **libgudev**. The
`dbus` use is narrow: `power-off` asks BlueZ over the system bus to
`Disconnect` the pad (`main.c:422-491`); nothing else touches D-Bus.

**One non-obvious transitive effect: glibc's gconv modules.** `hidapi`'s
`Config.in` carries `select BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_COPY if
BR2_TOOLCHAIN_USES_GLIBC` (it converts USB string descriptors at runtime).
That symbol was off, and `BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_LIST` is empty, so
enabling `dualsensectl` copies **all 253** gconv charset modules (~6.4 MiB
apparent, more after ext4 block rounding) into a target that had
**no `/usr/lib/gconv` at all** — glibc had been building them into the sysroot
all along with nothing installing them.

This is kept rather than trimmed to a guessed subset, because it closes a gap
this repo had already flagged. `docs/package-manifest.md` §1 lists the gconv
modules in stock's own SONAME inventory (`libCNS`, `libGB`, `libJIS`,
`libKSC`, …), and its "Not recommended to drop (tempting by size, but
load-bearing)" list names `gconv/` explicitly — *"needed for any non-ASCII
filename over SMB"*. So the image was missing a documented stock-parity
requirement and this restores it. `scripts/ci-tests.sh` now asserts the
modules are present so the gain cannot silently disappear if this package is
ever turned off. Pinning a minimal charset list would risk silently breaking
exactly the SMB filename case the manifest calls out; ~6.4 MiB is about 3% of
the last measured 222 MiB of free image space.

The hidraw backend is the one that matters — hidapi's libusb backend cannot
see a Bluetooth-connected pad at all.

**No automatic invocation — no init script, no udev rule.** `dualsensectl` and
`hid-playstation` both write `DS_OUTPUT` reports to the same pad. The driver
only writes when one of its `update_*` flags is set, so they do not contend
continuously, but fields they both own — the lightbar above all, which
Main_MiSTer drives through the `:red`/`:green`/`:blue` classdevs `0042`
registers — are last-writer-wins. An operator running a command from a shell
is a deliberate act; a udev rule firing one behind Main_MiSTer's back would be
a race nobody asked for.

**No udev permission rule either**, despite upstream's README suggesting one.
That rule (`MODE="0660"`, `TAG+="uaccess"`) exists to hand desktop seat users
access to the hidraw node. This image has one account — root, empty password
(`BR2_TARGET_GENERIC_ROOT_PASSWD=""`), no `BR2_ROOTFS_USERS` table — and root
already opens the default `0600 root:root` hidraw node. logind/elogind is not
installed, so `TAG+="uaccess"` would be inert, and `MODE="0660"` would widen
permissions only for a group nothing is a member of.

## If you are here to shrink the patch set

One honest trim exists, and it is small: **nothing writes `:mute`**. Grepping
`work/Main_MiSTer/`, `work/Downloader_MiSTer/` and `board/` finds the string
only inside `0037` itself. That classdev exists purely for stock-ABI parity,
so `0037` could shrink to just the `BTN_Z` reporting plus removal of the
in-kernel toggle.

That is a patch diet, not a `dualsensectl` substitution, and it does move the
image off stock parity — weigh it against `docs/stock-reconciliation.md`
before acting.
