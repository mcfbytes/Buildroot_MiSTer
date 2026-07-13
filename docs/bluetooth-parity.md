# Bluetooth parity (P3.5)

> Scope: `BR2_PACKAGE_BLUEZ5_UTILS` (+CLIENT, +TOOLS, +DEPRECATED,
> +PLUGINS_SIXAXIS) was already enabled by P2.1, and `S40bluetoothd` /
> `S45bluetooth` / `usr/bin/bluetoothd` were already authored by P2.3
> (rootfs overlay). This doc audits that work against stock for full
> parity, records one real gap found and fixed (adapter name / auto-power
> config), and lists what still needs a build and/or real hardware to
> confirm.

## 1. Version / SONAME

| | Stock | Ours |
|---|---|---|
| BlueZ version | unknown exact upstream version (image dated 2016-12-31; `libbluetooth.so.3.19.5`, a libtool version string, not a BlueZ release number) | **5.79** (`work/buildroot/package/bluez5_utils/bluez5_utils.mk:8`, Buildroot 2026.02.3's pinned version) |
| `libbluetooth` SONAME | `libbluetooth.so.3` (verified: `docs/stock-inventory/shared-libraries-full.txt`, `docs/stock-inventory/binaries-needed.md` DT_NEEDED list) | `libbluetooth.so.3` |
| `libbluetooth` real name | `libbluetooth.so.3.19.5` | `libbluetooth.so.3.19.15` |

**SONAME match confirmed against an actual build artifact**, not inferred:
main-checkout `output/target` (a build already run there, outside this
worktree — read-only, not built by this task) has `usr/lib/libbluetooth.so.3
-> libbluetooth.so.3.19.15`, and `readelf -d` on the real `.so` reports
`Library soname: [libbluetooth.so.3]`. BlueZ's `libbluetooth` SONAME has
been stable at major version 3 since the 4.x/5.x transition, so this was
expected, but it is now verified rather than assumed. **The orchestrator's
own integrated build should still re-check this** (see checklist below) —
the confirmation above comes from a separate, already-built tree on the
main checkout, not from a build of this branch's changes.

## 2. Init sequence

Stock's `/etc/init.d/S45bluetooth` is a **symlink to `/bin/bluetoothd`**,
which is itself a full start/stop/restart/reload/renew/hcireset control
script (verbatim capture: `docs/stock-inventory/etc-init-scripts-full.txt`
lines 302-396). It is the mechanism ADR 0015 (per-device SSH host keys)
explicitly cites and mirrors.

Ours reproduces this exactly, via P2.3's usr-merge (`BR2_ROOTFS_MERGED_USR=y`,
so `/bin` is itself a symlink to `usr/bin` in the built image, making
`etc/init.d/S45bluetooth -> /bin/bluetoothd` resolve to our
`usr/bin/bluetoothd`):

- `board/mister/de10nano/rootfs-overlay/usr/bin/bluetoothd` — **diffed
  byte-for-byte against the stock verbatim capture during this audit: 0
  differences.** Same `start`/`stop`/`restart`/`renew`/`reload`/`hcireset`
  shape, same `BLUETOOTHD_ARGS="-n -E -C"`, same ext4-image persistence
  idiom (see §3).
- `board/mister/de10nano/rootfs-overlay/etc/init.d/S45bluetooth` — symlink
  to `/bin/bluetoothd`, matching stock's shape exactly.
- `board/mister/de10nano/rootfs-overlay/etc/init.d/S40bluetoothd` —
  `BR2_PACKAGE_BLUEZ5_UTILS` installs its own `S40bluetoothd` unconditionally
  (`work/buildroot/package/bluez5_utils/S40bluetoothd`), which starts
  `bluetoothd` directly with **no** persistence step. Left alone, this would
  start `bluetoothd` a second time (racing the D-Bus name and the HCI socket
  against the real `S45bluetooth`) and would try to write pairing keys to
  `/var/lib/bluetooth` on the read-only rootfs, since that path isn't in
  `fstab` (not tmpfs). The overlay's `S40bluetoothd` is a documented no-op
  (`exit 0`) that overrides the package-installed file (rootfs overlay is
  applied after package install), so `bluetoothd` starts exactly once, by
  `S45bluetooth`, with storage mounted first. This is P2.3's fix, confirmed
  still correct.

**Bring-up mechanism (rfkill / hciconfig / bccmd / btattach):** stock's
`/bin/bluetoothd` does **none** of these. There is no `rfkill unblock`,
`hciconfig hci0 up`, `bccmd`, or `btattach` anywhere in stock's boot chain
for Bluetooth (checked the full verbatim script; the only device-specific
action is the unrelated `hcireset` case, an on-demand USB re-authorize
helper, not part of the boot path). Stock brings the adapter up entirely via
`bluetoothd`'s own `AutoEnable = true` in `/etc/bluetooth/main.conf` (see
§4) — HCI power-on happens over the kernel `mgmt` interface inside
`bluetoothd`, not from the init script. We now match this explicitly (§4).
No `bccmd`/`btattach` step is needed on this hardware — the DE10-Nano's
Bluetooth is a real HCI-over-USB/UART device enumerated by the kernel, not
one of the `btattach`-class serial-attach chips BlueZ's deprecated tools
target.

## 3. Pairing-state persistence — the key parity item

**Already correctly implemented by P2.3, verified during this audit.**

`bluetoothd` stores pairing/link keys under `/var/lib/bluetooth`. On this
image `/` is read-only at boot (ADR 0011/[A15]) and `/var/lib/bluetooth`
is not in `fstab`, so absent any action it would be unwritable and any
`mkdir`/pairing-key write inside `bluetoothd` would fail.

Stock's actual mechanism (reproduced verbatim in `usr/bin/bluetoothd`,
confirmed above): on `start`, create (if missing) a 64KiB×32 = 2MiB ext4
image at `/media/fat/linux/bluetooth` and loop-mount it at
`/var/lib/bluetooth` with `sync,dirsync,nodiratime,noatime`, **before**
starting `bluetoothd`. A `renew` action (`stop`; `rm` the image; `start`)
resets all pairings. This is the same shape ADR 0015 built the SSH
host-key mechanism from (`/media/fat/linux/ssh.ext4` -> `/etc/ssh_keys`) —
Bluetooth's is the original, SSH's the derived design.

Differences from stock: **none found.** The script is a byte-identical
reproduction (§2), so the persistence path, mount options, image size, and
`renew` semantics all match stock exactly.

One asymmetry worth naming explicitly (not a defect, a property of the
mechanism): unlike SSH's `S50sshd`, this script has **no ephemeral tmpfs
fallback** if the ext4 image can't be created or mounted (e.g., no
`/media/fat`, corrupt image, no free loop device) — `mkdir -p $MNTPATH;
mount ...` failing silently just leaves `bluetoothd` writing into the
read-only rootfs's `/var/lib/bluetooth`, which will fail. This is **stock's
own behavior**, verbatim — we did not add or remove this risk. Unlike SSH
(where a failed mount would be catastrophic — no host key means no way in
at all), a failed Bluetooth mount degrades to "pairings don't persist /
bluetoothd may misbehave" rather than "the box is unreachable," so keeping
strict stock parity here (no invented fallback) is the right call. Flagging
it so it's a known, deliberate choice rather than an oversight.

## 4. Deltas found — main.conf (fixed in this task)

Auditing `/etc/bluetooth/main.conf` (stock's full verbatim text is in
`docs/stock-inventory/etc-configs.md` lines 767-898) against the
bluez5_utils-5.79 package's own compiled-in default (`output/target
/etc/bluetooth/main.conf` on the main checkout's existing build) found
**two settings stock sets explicitly that our image was leaving at the
package default**, because no `main.conf` existed in the overlay before
this task:

| Setting | Stock | BlueZ 5.79 package default (uncommented → active) | Gap |
|---|---|---|---|
| `[General] Name` | `Name = MiSTer` | `#Name = BlueZ` → adapter advertises as `BlueZ 5.79` | **User-visible**: pairing UI on a phone/controller would show "BlueZ 5.79" instead of "MiSTer". |
| `[Policy] AutoEnable` | `AutoEnable = true` (stock's own comment: "Defaults to 'false'" on stock's BlueZ version) | `#AutoEnable=true` (BlueZ 5.79's own comment: "Defaults to 'true'") | **Behaviorally probably fine either way** on 5.79, since upstream's compiled default flipped to `true` since stock's BlueZ version was released — but leaving it unset means correctness depends on an upstream default that happens to agree with stock today, not on anything we assert or would notice if it regressed. |

**Fix:** added `board/mister/de10nano/rootfs-overlay/etc/bluetooth/main.conf`
— the full BlueZ 5.79 package-default file (kept complete, all other
options left as commented documentation, matching this repo's existing
`etc/ssh/sshd_config` overlay style of "keep the upstream default file,
annotate the deltas") — with exactly these two lines uncommented and set
to stock's values, each with a comment explaining why.

No other settings in stock's `main.conf` were set (everything else was
commented / default), so no further deltas exist there.

## 5. sixaxis plugin — packaging shape changed upstream (not a gap)

Stock ships PS3-controller BT pairing as a **loadable plugin**:
`usr/lib/bluetooth/plugins/sixaxis.so` (`docs/stock-inventory
/shared-libraries.md:523`), dlopen'd by `bluetoothd` at runtime from
`PLUGINDIR`.

In BlueZ 5.79, `--enable-sixaxis` (set via `BR2_PACKAGE_BLUEZ5_UTILS_
PLUGINS_SIXAXIS=y`, already on) compiles `plugins/sixaxis.c` **directly
into the `bluetoothd` binary** as a builtin plugin — confirmed by reading
the generated `Makefile` in the main checkout's existing build
(`plugins/bluetoothd-sixaxis.o` linked into `src_bluetoothd`) and by
`strings` on the built `bluetoothd`, which contains the `sixaxis_init` /
`sixaxis_exit` / `sixaxis_sdp_cb` symbols and plugin-descriptor string
directly. **No `usr/lib/bluetooth/plugins/` directory exists in the built
image at all** — there's nothing to put there anymore; upstream BlueZ
moved (some time between stock's version and 5.79) toward compiling
"internal" plugins straight into the daemon rather than shipping them as
separate `.so` files. Builtin plugins register themselves automatically
unless explicitly disabled (`DisablePlugins=` in `main.conf`, which we
don't set, or `-P`/`--noplugin` on the command line, which
`BLUETOOTHD_ARGS="-n -E -C"` doesn't pass) — so sixaxis support is active
by default, functionally equivalent to stock, just packaged differently.
**No action needed**, but noting it here so a future auditor doesn't go
looking for a missing `sixaxis.so` and conclude support was dropped.

## 6. D-Bus policy — location changed upstream, verified correct

`bluez5_utils.mk` passes `--with-dbusconfdir=/usr/share`, so the D-Bus
system-bus policy lands at `/usr/share/dbus-1/system.d/bluetooth.conf`
rather than `/etc/dbus-1/system.d/`. Checked this isn't a
Buildroot/packaging mistake: the built `/etc/dbus-1/system.conf` itself
documents `/usr/share/dbus-1/system.d/*.conf` as the correct modern
location "for upstream or distribution-wide defaults" (vs. `/etc/dbus-1/
system.d` for local sysadmin overrides), and `wpa_supplicant.conf` follows
the identical convention right next to it. **No divergence, no action
needed** — this is D-Bus's own current packaging convention, not something
either stock or our overlay controls.

## 7. Files touched by this task

- **Added** `board/mister/de10nano/rootfs-overlay/etc/bluetooth/main.conf`
  (§4 — the only functional change this task made).
- **Added** this doc.
- **No defconfig changes.** `BR2_PACKAGE_BLUEZ5_UTILS` and its four
  sub-options were already correct from P2.1; this audit found no missing
  or wrong Kconfig symbol.
- **No changes** to `usr/bin/bluetoothd`, `S40bluetoothd`, or
  `S45bluetooth` — audited and confirmed byte-identical to stock / correct
  as authored by P2.3.

## 8. Verify-in-build / verify-on-hardware checklist (for the orchestrator)

Everything below needs the integrated build and, where marked **[HW]**,
real hardware — nothing here was fabricated as "confirmed" without a
build; items not marked [BUILD]/[HW] were confirmed by reading this
worktree's files and the main checkout's pre-existing (separately built)
`output/` tree, which is a real build but not one this task ran or that
includes this task's `main.conf` change.

- **[BUILD]** `libbluetooth.so.3` present in the *integrated* build's
  `output/target/usr/lib/`, with this task's changes included (the SONAME
  check in §1 used a build that predates this task's `main.conf` addition
  — should be unaffected, since `main.conf` isn't linked into anything,
  but re-check as routine hygiene).
- **[BUILD]** New `etc/bluetooth/main.conf` actually lands at
  `/etc/bluetooth/main.conf` in `output/target` (i.e. the overlay
  correctly overrides the package-installed default — same mechanism
  already proven for `S40bluetoothd`, but confirm for this new file too).
- **[BUILD]** `dmesg`/boot log: `bluetoothd` starts successfully on the
  read-only root (per ADR 0011, use `dmesg`/boot console output to reason
  about boot-time state, not a post-login `mount` — logging in remounts
  `/` rw and would hide a real problem). Confirm no "Failed to mount
  /var/lib/bluetooth" / no ext4 or D-Bus errors in the boot log.
- **[BUILD or HW]** `bluetoothctl show` (or equivalent D-Bus query)
  reports `Name: MiSTer` and `Powered: yes` **without any manual
  `hciconfig`/`rfkill` intervention** — confirms the `main.conf` fix
  actually takes effect and `AutoEnable` really brings hci0 up
  automatically, matching stock.
- **[HW]** Pairing-DB persistence across reboot (this task's "done-when",
  called out as P3.13 in the task brief): pair a BT device, reboot, confirm
  it's still paired (`bluetoothctl paired-devices` unchanged, and the
  device reconnects without re-pairing). This needs the actual FAT data
  partition + `/media/fat/linux/bluetooth` image round-trip and cannot be
  verified in a build sandbox.
- **[HW]** Sixaxis / PS3 controller pairing over BT actually works via the
  now-builtin plugin (functional equivalent of stock's loadable
  `sixaxis.so`, per §5) — the plugin's presence in `bluetoothd`'s binary
  was confirmed by static inspection (`strings`, linked object in the
  Makefile), not by exercising it against real hardware.
- **[BUILD]** `usr/share/dbus-1/system.d/bluetooth.conf` is present and
  `dbus-daemon --system` accepts it at boot (no D-Bus policy-parse
  errors in the log) — sanity-check only, no change expected (§6).
