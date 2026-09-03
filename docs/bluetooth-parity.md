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
| BlueZ version | unknown exact upstream version (image dated 2016-12-31; `libbluetooth.so.3.19.5`, a libtool version string, not a BlueZ release number) | **5.79** (`work/buildroot/package/bluez5_utils/bluez5_utils.mk:8`, Buildroot 2026.05.1's pinned version) |
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

- `board/mister/de10nano/rootfs-overlay/usr/bin/bluetoothd` — **byte-for-byte
  against the stock verbatim capture when this audit ran: 0 differences.**
  Same `start`/`stop`/`restart`/`renew`/`reload`/`hcireset` shape, same
  `BLUETOOTHD_ARGS="-n -E -C"`, same ext4-image persistence idiom (see §3).
  **One deviation has since been added, in `stop()` only — see §3.1.** Every
  other line, and the whole verb set, remains stock's.
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
reproduction (§2) apart from the `stop()` wait described next, so the
persistence path, mount options, image size, and `renew` semantics all match
stock exactly.

### 3.1 The one deviation: `stop()` waits for the daemon to exit

`start-stop-daemon -K` only sends SIGTERM and returns; it does not wait. Stock
unmounts on the very next line, so the `umount` races a `bluetoothd` that still
has `/var/lib/bluetooth` open — it fails `EBUSY` and leaves the loop mount up
over a possibly-dirty ext4 image.

This is **reachable from the OSD, not merely at shutdown**. `renew`
(`Main:menu.cpp:7166`, an ABI entry point per `docs/abi-contract.md` §7.6) runs
`stop` → `umount` → `rm $BTIMG` → `start`, so losing the race deletes the image
file while it is still loop-mounted. Stock hedges with fixed sleeps — `sleep 2`
in `renew`, `sleep 1` in `restart` — which is a guess, not a wait.

The fix is upstream Buildroot's, from `package/bluez5_utils/S40bluetoothd`'s
`stop()`: poll `start-stop-daemon --stop --test` until the process is gone, then
remove the pidfile. One change from upstream — **ours is bounded** (50 × 0.1 s =
5 s, then unmount anyway). Upstream's loop is infinite, which on this board would
hang an OSD menu item forever if `bluetoothd` ever ignored SIGTERM; giving up
after 5 s is no worse than stock's behaviour today and correct in every other
case.

Verified by **running** the binaries under `qemu-arm`, not by reading them —
including stock's, since upstream MiSTer builds on a much older Buildroot and
its BusyBox is a different vintage. Stock's `/usr/bin/busybox`, extracted from
`rootfs.tar.bz2` in `MiSTer-devel/Linux_Image_creator_MiSTer`, is **v1.33.1
(2022-12-24)**; ours is 1.38.0.

| | stock 1.33.1 | ours 1.38.0 |
|---|---|---|
| `start-stop-daemon -K -t -q -p` on a live pid | exit 0 | exit 0 |
| …on a reaped pid | exit 1 | exit 1 |
| …stderr on the reaped-pid probe | `warning: killing process N: No such process` | identical |
| `sleep 0.1` | works, ~0.1 s | works, ~0.1 s |

Two things follow. `-t` is in the base option string, not behind
`CONFIG_FEATURE_START_STOP_DAEMON_FANCY`, and fractional `sleep` is built into
both — so **this same code is valid on stock**, which matters because the intent
is to hand it upstream.

And the `2>/dev/null` is **load-bearing**, on both. This is the part that is
easy to get wrong by reading the source: on the final probe — the one that ends
the loop — `start-stop-daemon` writes `warning: killing process N: No such
process` to stderr, *not* gated on `-q`, because BusyBox's pidfile reader does
not check liveness before building `found_procs`, so the dead pid reaches the
`bb_perror_msg` branch (`:391`) rather than the silent `!G.found_procs` path
(`:381-385`). An earlier draft of this section claimed the opposite from a
source read; running both binaries against a reaped pid disproved it. Without
the redirect, every `stop`/`restart`/`renew` would emit a spurious warning.

Loop behaviour, measured against our BusyBox: dead pid in the pidfile → 0
iterations, 44 ms; a daemon that exits 0.6 s after SIGTERM → 5 iterations,
0.61 s; a daemon that never exits → 50 iterations, then proceeds.

**This is a divergence from stock and the intent is to remove it by fixing
stock.** `usr/bin/bluetoothd` is not tracked as source upstream — it ships
inside `addon.tar`, a binary blob committed to
`MiSTer-devel/Linux_Image_creator_MiSTer` (`docs/verification/
stock-reconciliation/addon-report.txt:33`, `usr/bin/bluetoothd  EXACT`) — so the
upstream route is a report against that repo rather than an ordinary source PR.
Until then this row is the record that we are one `stop()` ahead of stock.

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

> **Later correction (see §10):** the plugin being *active* was necessary but
> not sufficient — a DS3 still could not connect over Bluetooth, because
> BlueZ 5.79's `ClassicBondedOnly=true` default rejects it before the plugin
> matters. That is fixed in §10 by a backported upstream patch series, not by
> weakening the setting.

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

## 9. Bluetooth firmware audit (v10.2)

`docs/wifi-parity.md` §7 audited USB **WiFi** drivers against their firmware and
found two drivers built with none at all. This section applies the same method
to **Bluetooth**, and found the same class of gap.

**Method.** For every `CONFIG_BT_*` driver this image builds, extract the
firmware path strings it requests (`MODULE_FIRMWARE()`, literal
`request_firmware()` arguments, and the `snprintf` format strings the drivers
build names from at runtime), then check each against the shipped
`/lib/firmware`.

Drivers built: `btusb` (with `_BCM`/`_MTK`/`_RTL` vendor support), `btintel`,
`btbcm`, `btrtl`, `btmtk`, `ath3k`, `bcm203x`, `btrsi`.

### Gaps found and closed

| Driver | Missing firmware | Now via | Note |
|---|---|---|---|
| `btmtk` | `mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin` | `_MEDIATEK_MT7921_BT` | **The notable one.** We already shipped `WIFI_RAM_CODE_MT7961*` for the *WiFi* half of the MT7921AU combo dongle, so that dongle's WiFi worked and its Bluetooth did not. We created that asymmetry by enabling `_MEDIATEK_MT7921` without its `_BT` sibling. |
| `btmtk` | `mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin` | `_MEDIATEK_MT7922_BT` | `btusb` carries MT7922 USB IDs, so this is a reachable USB path, not only the M.2 part. |
| `btmtk` | `mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin` | `_MEDIATEK_MT7925_BT` | Same asymmetry as MT7961, for the MT7925U combo. |
| `btusb` (QCA) | `qca/rampatch_usb_00000302.bin`, `qca/nvm_usb_00000302.bin` | `_QUALCOMM_6174A_BT` | QCA ROME 6174A over USB. `btusb`'s QCA path is **self-contained** — 0 references to `CONFIG_BT_QCA` — so the driver was already able to drive these; firmware was the only missing piece. |
| `btbcm` | `brcm/BCM-0bb4-0306.hcd` | `linux-firmware-extra` | The **only** `.hcd` upstream linux-firmware carries, and `linux-firmware.mk` has no `.hcd` glob at all, so no sub-option installs it. `btbcm` builds `brcm/BCM%s.hcd` with `%s = "-<vid>-<pid>"`, which is exactly this name. |

Total ≈1.7 MB.

### Already correct (verified, not assumed)

- **Realtek** — 38 files in `rtl_bt/`, including `rtl8761b_fw.bin` /
  `rtl8761bu_fw.bin`. That matters: RTL8761B/BU are the chips in the
  ubiquitous cheap USB Bluetooth 5 dongles. Also covered: 8822b/cu, 8851bu,
  8852au/bu/btu/cu — the BT halves of every rtw88/rtw89 combo we drive.
  ⚠ **Firmware coverage is not the same as device coverage**, and the RTL8761BU
  family is where that bites: every one of these dongles is a different
  VID:PID sold under a different brand, and `btusb`'s `quirks_table` has to
  name each one before `btrtl` is ever reached to load the firmware above. A
  missing row looks exactly like a dead dongle and logs nothing. First
  instance, 2026-08-24: `2c4e:0115` (Mercusys MA530 / MA550H) — in mainline
  since 7.2, never backported to 6.18.y, so we carry
  `board/mister/de10nano/linux-patches/0047-btusb-mercusys-ma530-2c4e-0115.patch`
  (`docs/patch-provenance.md`, "`0047` — the first BACKPORT"). Expect more of
  these, and expect them to arrive as user reports rather than as build
  failures.
- **MediaTek legacy** — `mt7622pr2h.bin`, `mt7663pr2h.bin`, `mt7668pr2h.bin`
  already shipped via `linux-firmware-extra` (`mt7663pr2h.bin` arrived with the
  v10 MT7663U work and does double duty as that combo's BT companion).
- **Atheros** — `ath3k-1.fw` + 18 `ar3k/*.dfu`, added in v10.
- **Broadcom** — `brcm/BCM20702A1-0b05-17cb.hcd` via `package/bcm20702-firmware`
  (upstream linux-firmware does not carry it).
- **Redpine** — the `rsi/*.rps` blobs added in v10.1 serve `btrsi` as well as
  `rsi_usb`; RS911x firmware is combined WLAN+BT.
- **CSR** (`CSR8510` and friends, the other very common cheap dongle) needs no
  firmware at all — `btusb` drives it generically.

### Deliberately NOT shipped

- **Intel** (`BR2_PACKAGE_LINUX_FIRMWARE_IBT`, `intel/ibt-*`) — **30 MB**, and
  Intel Bluetooth controllers ship essentially only on M.2 WiFi+BT combo cards,
  which this board cannot host. There is no realistic external Intel BT USB
  dongle. `CONFIG_BT_INTEL` is nevertheless built because `CONFIG_BT_HCIBTUSB`
  `select`s it unconditionally — it cannot be turned off while `btusb` is on.
  So this is a **deliberate** driver-without-firmware, in contrast to the
  ath3k/mt7663/btmtk cases above, which were accidental. One defconfig line to
  reverse if an Intel BT dongle ever matters.
- **`_QUALCOMM_9377_BT`** — its two files are `qca/rampatch_00230302.bin` /
  `nvm_00230302.bin`, the **non-USB** names, which only the UART path
  (`hci_qca`, `CONFIG_BT_HCIUART`, not built) requests. No consumer here.
- **`bcm203x`** (`CONFIG_BT_HCIBCM203X=y`, BCM2033) — needs
  `BCM2033-MD.hex`/`BCM2033-FW.bin`, which upstream linux-firmware does not
  carry at all. A ~2003 device with no available source; noted rather than
  fabricated, same posture as the three dropped files in
  `docs/firmware-parity.md`.

`scripts/ci-tests.sh` now asserts the MediaTek BT, QCA USB BT, both `.hcd`s and
the rtl8761b/bu pair are present in the shipped image, so none of this can
regress silently.

---

## 10. HID transport and DS3/SIXAXIS over Bluetooth (added 2026-08-13)

A later change than the P3.5 audit above, and the first thing in this doc to
touch `input.conf`. Two settings, one backported patch series, one open
hardware test. §5 explains why the sixaxis *plugin* is already active; this
section is about why, until now, that plugin still could not get a DS3
connected over Bluetooth.

### What we were running before

We shipped no `input.conf` at all, so both settings sat at BlueZ 5.79's
compiled-in defaults, read from `profiles/input/device.c:92-93`:

```c
static uhid_state_t uhid_state = UHID_ENABLED;
static bool classic_bonded_only = true;
```

Neither default was what we wanted, for different reasons.

### `UserspaceHID` — now `false` (kernel HIDP)

`UHID_ENABLED` is the **opposite of stock**: stock's BlueZ 5.61 defaulted
`uhid_enabled = false`, so MiSTer has always run kernel HIDP. Three reasons to
go back:

1. **bluetoothd leaves the per-report data path.** Under uhid,
   `profiles/input/device.c:1258` registers `intr_watch_cb()` as a glib
   main-loop watch on the L2CAP interrupt channel; it fires for *every* input
   report and copies it back into the kernel through `uhid_send_input_report()`
   (`device.c:386`). A DualSense in full BT report mode is ~250 Hz, so that is
   ~250 daemon wakeups per second per pad — visible as bluetoothd CPU, and it
   was noticed in the field before it was explained. With HIDP,
   `ioctl_connadd()` (`device.c:919`) hands both L2CAP sockets to the kernel
   via `HIDPCONNADD` and bluetoothd drops out of the data path entirely,
   polling only `HIDPGETCONNINFO` and tearing down with `HIDPCONNDEL`.
2. **It matters more on the RT variant** (`docs/rt-beta-kernel.md`). uhid puts
   a `SCHED_OTHER` glib main loop in the input path, preemptible by any RT
   task, so controller latency inherits bluetoothd's scheduling jitter — and
   `Main_MiSTer` pins itself to CPU1 and spins, so bluetoothd contends on CPU0.
   **This is a mechanistic argument, not a measurement**; the RT latency
   numbers are still outstanding.
3. **It repairs `bt_auto_disconnect`.** `Main_MiSTer` identifies BT pads with
   `strstr(sysfs, "bluetooth")` (`input.cpp:4156`), which never matches uhid's
   `/sys/devices/virtual/misc/uhid/…` path. The clean fix is upstream —
   `input.cpp:5200` already reads `bustype` from `EVIOCGID`, so
   `bustype == BUS_BLUETOOTH` would work on both transports — but this repo
   does not build `Main_MiSTer`, so this is the only lever available here.
   `MiSTer.ini` ships `bt_auto_disconnect=0`, so nothing regresses today.

**What it does not cost: Bluetooth LE.** HIDP is BR/EDR-only, and
`profiles/input/hog.c:257-264` reads `UserspaceHID` *only* to test for the
`persist` value — it never disables uhid for LE. BLE HID devices keep using
uhid regardless. What is given up is `persist` mode for BR/EDR (new in 5.79)
and future BlueZ-side fixes to the BR/EDR HID path. Judged acceptable because
our device quirks live in the `hid-*` kernel drivers, which **both** paths
share.

**Safe because `CONFIG_BT_HIDP=y`** — verified in the *resolved* kernel
`.config`, not in `board/mister/de10nano/linux.config` (a minimal defconfig,
where an absent symbol proves nothing). Without it this setting would strand
BR/EDR HID entirely, so `scripts/ci-tests.sh` asserts it.

### `ClassicBondedOnly` — pinned to `true`, and the DS3 fixed properly

`true` is already the compiled-in default; pinning it explicitly is a guard,
because this is exactly the line every retro-gaming distro flips to `false` to
make the PS3 pad work. Doing that drops the encryption requirement for **every
BR/EDR HID device** on the system, re-exposing **CVE-2023-45866**
(unauthenticated HID injection).

Instead, `board/mister/de10nano/patches/bluez5_utils/` carries upstream's
**four-commit** `CablePairing` series (BlueZ 5.83, Ludovico de Nittis /
Collabora) plus one unrelated HID fix, applied through
`BR2_GLOBAL_PATCH_DIR`:

| Patch | Upstream commit | Role |
|---|---|---|
| `0001` | `20ea34e7` | adds the `CablePairing` D-Bus property |
| `0002` | `56516d6c` | sixaxis plugin sets it during USB cable pairing |
| `0003` | `c5dffe0` | adds `btd_adapter_has_cable_pairing_devices()` — **the one originally missed** |
| `0004` | `ba101f47` | input server listens at `BT_IO_SEC_LOW`, re-raises to `BT_IO_SEC_MEDIUM` for everything *except* a `CablePairing` device |
| `0005` | `e2324f7a` | [bluez#1710](https://github.com/bluez/bluez/pull/1710) — HID report-descriptor off-by-one (5.87). Unrelated to DS3 |

Net effect: a cable-paired DS3 connects, and every other BR/EDR HID device
keeps encryption enforced. Upstream closed
[bluez#688](https://github.com/bluez/bluez/issues/688) with this series,
noting DS3 now works *"with limited exposure to CVE-2023-45866 and without
changing `ClassicBondedOnly=false`"*.

`0005` is carried separately because it is squarely in the path every
Bluetooth pad here takes — upstream's own commit message names the DualSense
(`playstation 0005:054C:0CE6.0014: unknown main item tag 0x0`). Upstream calls
it benign (the kernel's parser ignores the stray item), so it is a correctness
fix rather than a repair for a user-visible fault. It applies **regardless of
transport** despite the commit message mentioning UHID: the bug is in the SDP
extraction that fills `struct hidp_connadd_req`, which runs *before* the
uhid/kernel-HIDP branch.

#### The bug this series already had once

The first cut carried **three** commits and omitted `0003`. It applied cleanly
— `patch` was perfectly happy — while leaving `profiles/input/manager.c`
calling a `btd_adapter_has_cable_pairing_devices()` that nothing defined: an
unconditional compile failure under gcc 14.4's
`-Wimplicit-function-declaration`. **"The series applies" and "the series
builds" are different claims**, and only the second one matters. Anyone
re-deriving this series from the issue thread must walk the parent chain.

#### Why not simply run a newer bluez?

Overriding `BLUEZ5_UTILS_VERSION` to 5.87 was implemented and then abandoned,
because it cannot build. `package/bluez5_utils/` ships **four patches of its
own**, and `pkg-patch-hash-dirs` (`pkg-utils.mk:164`) always includes
`$(PKGDIR)`, so they are applied to whatever version is built. Against 5.87,
with the exact flags `apply-patches.sh:119` uses, three report *"Reversed (or
previously applied) patch detected"* (they went upstream between 5.79 and
5.87) and one conflicts — and that script runs under `set -e`, so the build
dies at `.stamp_patched`. No override target ≥ 5.83 avoids this, because the
patches went upstream *before* the version we need.

Two further problems came with it: `bluez5_utils-headers` (not optional —
`package/python3/Config.in:13` selects it) reads
`bluez-$(BLUEZ5_UTILS_VERSION).tar.xz` **lazily from the other package**, so
it would fetch 5.87 against a hash file listing only 5.79 — invisible locally,
since its stale `.stamp_downloaded` short-circuits the step, and fatal only on
a clean CI build. And `_DL_VERSION` is `:=` (`pkg-generic.mk:498`), evaluated
before `external.mk`, so `legal-info` and CVE metadata would report 5.79 for a
5.87 build.

Salvaging it needed a `_PKGDIR` redirect to suppress Buildroot's patches (which
also relocates the hash lookup, requiring its `COPYING` lines to be duplicated)
plus a headers hash file plus a `_DL_VERSION` override — three fights with the
package machinery, and the `_PKGDIR` redirect would **silently drop** any
future Buildroot patch for bluez. `BR2_GLOBAL_PATCH_DIR` is the mechanism
Buildroot actually provides for this, it needs no workarounds, and it fails
*loudly*. Forking the package into `package/` was also considered and rejected:
it would mean owning a ~200-line `.mk` plus Config.in with every sub-option
forever, and fixing each reverse-dependency.

**These patches are not a MiSTer delta.** They exist solely because Buildroot
2026.05.1 pins bluez5_utils 5.79 (`bluez5_utils.mk:8`), which predates 5.83.
**Delete the whole directory** on the first Buildroot bump that lands ≥ 5.83.

**Deliberately not version-scoped.** `pkg-patches-dirs`
(`package/pkg-utils.mk:166-170`) will prefer a `$(dir)/$(VERSION)` subdirectory
if one exists, so these could have been filed under
`patches/bluez5_utils/5.79/` and would then stop applying by themselves on any
version bump. That was rejected: it converts a *loud* failure into a *silent*
one. Unscoped, a bump to ≥ 5.83 makes the patches fail to apply and the build
goes red, which is the signal that tells a human to delete this directory; a
bump to some 5.8x still below 5.83 likewise fails loudly rather than quietly
shipping an image with DS3 support removed. Failing closed is the same posture
this repo takes on the kernel hash pins.

**Migration trap.** `plugins/sixaxis.c`'s `setup_device()` short-circuits on an
already-trusted device, so a DS3 that was cable-paired under the *old* BlueZ
never acquires the property and will still fail to connect. Such a pad must be
re-paired: `bluetoothctl remove <MAC>`, then cable-pair again.

### Verification status

- **[VERIFIED]** All five patches apply **in Buildroot's real order** — i.e.
  *after* `package/bluez5_utils/`'s own four patches, not against a pristine
  tarball — using the exact flags `apply-patches.sh:119` uses
  (`patch -F0 -g0 -p1 -t -N`): no fuzz, no rejects. Hunk offsets do occur and
  are expected for a backport; an earlier revision of this doc claimed "no
  offsets", which was reading `patch --dry-run`'s exit status (0 whether or not
  hunks moved).
- **[VERIFIED]** Every symbol the series introduces resolves afterwards —
  `btd_adapter_has_cable_pairing_devices`, `device_is_cable_pairing`,
  `device_set_cable_pairing`, `server_set_cable_pairing`,
  `get_necessary_sec_level` each have ≥1 reference and exactly one definition.
  This is the check that would have caught the missing `0003`, and a plain
  apply-check never could.
- **[VERIFIED]** Both claimed behaviours are present in the patched tree:
  `server_set_cable_pairing` in `profiles/input/server.c`, and
  `rd_size = d->unitSize - 1` in `profiles/input/device.c`.

  > An earlier revision of this line cited `BT_IO_SEC_LOW` as the marker. That
  > was **vacuous**: the string is already in pristine 5.79
  > (`profiles/input/server.c:274`) and is in fact the line patch `0004`
  > replaces, so it distinguished nothing. `server_set_cable_pairing` is
  > introduced only by the series and appears nowhere in the unpatched tarball.
- **[VERIFIED]** The series **compiles**. All six files it touches
  (`src/device.c`, `src/adapter.c`, `plugins/sixaxis.c`,
  `profiles/input/{device,manager,server}.c`) cross-compile clean for ARM with
  this repo's own `arm-buildroot-linux-gnueabihf-gcc` 14.4 under
  `-Wall -Werror=implicit-function-declaration` — the exact error class the
  originally-missing `0003` would have tripped. Run against a copy of the real
  configured build tree with Buildroot's own four patches already applied, then
  ours on top.
- **[VERIFIED]** `CONFIG_BT_HIDP=y` and `CONFIG_UHID=y` in the resolved kernel
  `.config`.
- **[CI]** `ci-tests.sh` asserts both `input.conf` values, `CONFIG_BT_HIDP`,
  and that `server_set_cable_pairing` reached the built source tree — so the
  series silently ceasing to apply cannot produce a green build.

  > **`.stamp_patched` is the trap here.** Buildroot never revisits it, so
  > adding or changing patches on an already-built tree is a silent no-op: an
  > incremental `make all` over an `output/` that predates this branch ships a
  > `bluetoothd` with no CablePairing support, indistinguishable in every
  > shipped file from a correct build. Run `make bluez5_utils-dirclean` after
  > touching anything in `board/mister/de10nano/patches/bluez5_utils/`.
- **[HW — NOT DONE]** DS3/SIXAXIS USB cable-pair, then connect over Bluetooth.
  This is the actual claim of the change and it has **not** been tested on
  hardware.
- **[HW — NOT DONE]** Confirm the bluetoothd CPU drop with a DualSense
  connected, and that DS4/DualSense/Switch pads still pair and their LED nodes
  still appear where `Main_MiSTer`'s `get_led_path()` expects (they should —
  the `hid-*` drivers bind identically on both transports).
