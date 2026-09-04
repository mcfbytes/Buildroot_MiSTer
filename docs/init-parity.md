# Init & config parity — stock vs. `rootfs-overlay/`

Task: **P2.3**. Depends on P0.3 (`docs/stock-inventory/etc-configs.md`) and P2.1 (full
package set). Consumed by P2.4 (read-only-root audit) and P2.9 (hardware boot).

> **⚠ UPDATE (P2.9 v2, 2026-07-12): this build is now usr-merged.** This document
> was written at P2.3 time, when the rootfs was **not** usr-merged, and several
> notes below justify adaptations (the `gpm` path, the `/etc/profile` `PATH`
> prefix) by that fact. **P2.9 v2 set `BR2_ROOTFS_MERGED_USR=y`** — because a
> non-usr-merged rootfs was the root cause of the SSH lockout on the first
> hardware boot (`/etc/pam.d/sshd` references `/lib/security/pam_unix.so`, which
> only exists via the `/lib -> /usr/lib` symlink). So `/lib`, `/bin`, `/sbin` are
> now symlinks into `/usr`, exactly like stock. **Consequence for this doc:** the
> `gpm`-path and `PATH`-prefix adaptations described below are now *redundant but
> harmless* (`/sbin/gpm` and `/usr/sbin/gpm` resolve to the same file), and are
> retained rather than reverted. The history is left intact below because it is
> how the usr-merge decision was reached.

**Method.** Every stock file cited below was read from `work/imgroot/` (the extracted
stock `linux.img`, P0.3's ground truth). Every "current" / "package default" file was
read from `output/target/` **after** P2.1's full package-set build but **before**
this task's overlay was wired in, so the diffs are genuinely against what Buildroot's
packages install unprompted, not against a strawman. The overlay itself lives at
`board/mister/de10nano/rootfs-overlay/` and is wired via `BR2_ROOTFS_OVERLAY` in
`configs/fragments/de10nano-image.fragment` (added by this task; previously unset for the
full-rootfs build — only the initramfs defconfig had its own overlay).

Build verified: `make de10nano-defconfig && make all` completed clean,
`output/images/rootfs.tar` (180 MB) and `output/images/zImage_dtb` (8,771,237 bytes,
`check-zimage-dtb.sh` all-pass) both produced. All claims below were checked against
`output/images/rootfs.tar`, extracted fresh, with the actual commands and output
reproduced in this task's report (not re-typed from memory).

**This took two build iterations, on purpose.** After the first successful build,
every absolute path referenced anywhere in the overlay was grep'ed out and checked
against the actually-extracted image (not assumed from stock's shape) — this caught
a real bug: `/etc/inittab`'s `gpm` line pointed at `/sbin/gpm`, copied verbatim from
stock, but this build's rootfs was **at the time** not usr-merged the way stock's is,
so `/sbin/gpm` did not exist here (only `/usr/sbin/gpm` did) and the line would have
silently failed to spawn gpm on every boot. Fixed to `/usr/sbin/gpm`, rebuilt,
re-verified. (P2.9 v2 later set `BR2_ROOTFS_MERGED_USR=y`, so `/sbin/gpm` would
resolve today — but `/usr/sbin/gpm` is the binary's real path in either layout, so
it is kept as an accepted permanent deviation rather than reverted to stock's.)
See the `/etc/inittab` row below. Everything reported as PASS in this task's report
reflects the **second, corrected** build.

## Summary

| Status | Count | Meaning |
|---|---|---|
| identical | 8 | Byte-identical to stock, or functionally identical modulo cosmetic/tooling differences (documented per row) |
| adapted | 4 | Behavior intentionally differs from stock, for a stated reason |
| dropped | 0 | — |

All 12 of the verified stock S-scripts are represented in the built image, either
directly or by an equivalent the package set already installs.

## Per-script table (the 12 verified stock scripts)

| Script | Status | Notes |
|---|---|---|
| `S01syslogd` | **identical** | Package's own script (BusyBox `syslogd` via the busybox package). Same `DAEMON`/`PIDFILE`/args; only cosmetic difference is `start-stop-daemon`'s modern long-option spelling (`--start --background --make-pidfile` vs. stock's `-b -m -S -q`) — same flags, same daemon invocation (`syslogd -n`). Not overlaid. |
| `S02klogd` | **identical** | Same as above, for `klogd`. Not overlaid. |
| `S10udev` | **adapted** (filename) | eudev's own package-generated `S10udevd` (confirmed present, `BR2_PACKAGE_EUDEV=y` + `BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV=y`, both already set by P2.1 — **not** mdev) does the identical job: `udevd` + `udevadm trigger --type=subsystems/devices --action=add` + `udevadm settle --timeout=30`, line-for-line the same shape as stock's `S10udev`. We deliberately do **not** add a duplicate `S10udev` — that would start a second `udevd` instance racing the first over the same netlink socket. Not overlaid. |
| `S30dbus` | **adapted** (filename) | dbus's own package script `S30dbus-daemon` does the same job (`dbus-uuidgen --ensure`, `mkdir -p /run/dbus /tmp/dbus`, `dbus-daemon --system`). Same reasoning as `S10udev` — not duplicated, to avoid a second `dbus-daemon --system` racing for the bus name. Not overlaid. |
| `S40network` | **identical** | Byte-for-byte identical to stock (`diff` exit 0) — `ifup -a` / `ifdown -a` via ifupdown. Not overlaid. |
| `S41dhcpcd` | **identical** | Filename matches stock exactly. Content is functionally identical (same start/stop/reload logic); the only difference is `PIDFILE=/var/run/dhcpcd/pid` vs. stock's `/var/run/dhcpcd.pid`, which reflects this newer dhcpcd's own pidfile convention, not a P2.3 decision — reverting to stock's path would risk it not matching what this dhcpcd binary actually writes. Not overlaid. |
| `S45bluetooth` | **adapted** (mechanism reproduced, package default neutralized) | Stock's real file is a **symlink** to `/bin/bluetoothd`, which does the ext4-image persistence trick for `/var/lib/bluetooth` (BT pairing keys) that ADR 0015 explicitly mirrors for SSH host keys. Reproduced **byte-identical** (`diff` exit 0) at `bin/bluetoothd`, with `etc/init.d/S45bluetooth` a symlink to it — exactly stock's shape. **Problem found and fixed:** `BR2_PACKAGE_BLUEZ5_UTILS` installs its own `S40bluetoothd`, which starts `bluetoothd` directly with **no** persistence step — on our read-only `/`, `/var/lib/bluetooth` (not in fstab, so not tmpfs) would be unwritable, and running it would race the real `S45bluetooth` over the D-Bus name and the HCI socket. `etc/init.d/S40bluetoothd` is overlaid to a documented no-op stub so bluetoothd starts exactly once, correctly. |
| `S49ntp` | **identical** (overlaid to fix a real bug) | Byte-identical to stock's script (`ntpd -g`, runs as root). **Problem found and fixed:** the package's own default `S49ntp` runs `ntpd -u ntp:ntp -g` — dropping privileges to an `ntp` user that **does not exist** in this build's `/etc/passwd` (verified: `grep '^ntp:' output/target/etc/passwd` → no match). Left as the package default, `ntpd` would fail to start on every boot, silently breaking time sync forever. Reverted to stock's root-run form via the overlay. |
| `S50proftpd` | **identical** | Byte-for-byte identical to stock (`diff` exit 0). Not overlaid. |
| `S50sshd` | **adapted** (ADR 0015) | Stock's simple shape (`ssh-keygen -A`; bare `/usr/sbin/sshd`; `touch /var/lock/sshd`) is kept, but `ssh-keygen -A` is replaced with the ADR 0015 per-device mechanism: create/mount `/media/fat/linux/ssh.ext4` at `/etc/ssh_keys` (mirrors `bin/bluetoothd`'s own ext4-image idiom almost line for line), then generate the three key types individually into it if missing. See "SSH host keys" below for the full mechanism and why. |
| `S91smb` | **identical** (overlaid to restore stock's opt-in gate) | Byte-identical to stock. **Problem found and fixed:** the package's own default `S91smb` only guards on `/etc/samba/smb.conf` existing; stock has a **second** guard, `[ -f /media/fat/linux/samba.sh ] \|\| exit 0`. Without it, shipping `/etc/samba/smb.conf` (done for config parity, see below) would make Samba **auto-start on every boot** — stock's actual behavior is opt-in (Samba only starts once the user/Downloader drops `samba.sh` onto the FAT partition). Reverted to stock's double-guard form, plus its extra `mkdir -p` calls and the `samba.sh` trailer call. |
| `S99user` | **identical** | Not present as a package default (no package provides a MiSTer-specific user hook). Added byte-identical to stock: calls `/media/fat/linux/user-startup.sh` if present. |

### Non-`S`-prefixed control scripts

`rcS` / `rcK` — **identical**, byte-for-byte (BusyBox init's own runlevel drivers,
package-provided, unchanged from stock).

### Extra init scripts beyond stock's 12-script list

P2.1's package set (a superset of stock's, per `docs/package-manifest.md` — ~5 years
newer, more packages) installs several init scripts stock never had:
`S01seedrng`, `S02sysctl`, `S11modules`, `S35iptables`, `S50crond`. (This list also
carried `S30rpcbind` and `S60nfs` when P2.3 ran, while `nfs-utils` still built its
default-`y` server half; ADR 0022 made NFS client-only and `rpcbind` was never selected,
so neither script exists today — `scripts/ci-tests.sh` now asserts both **absent**.) None
of these conflict with anything above (verified by filename/number and
by the daemons they start), none write to `/` at runtime, and none are required by
any P2.3 acceptance item. Left as package defaults; not in scope for this task
beyond this note. Flagged here for the record, per "diverge from stock only with a
documented reason" — these aren't a P2.3 divergence at all, they're P2.1's broader
package manifest showing up in `/etc/init.d`, and are out of this task's remit (its
constraint is explicitly "do NOT disturb ... the package set").

## SSH host keys — ADR 0015, as implemented

Folded into `etc/init.d/S50sshd` rather than a separate `S49sshd` (ADR 0015 offers
both shapes; folding avoids a second file and keeps the ordering trivial to read):

1. `KEYIMG=/media/fat/linux/ssh.ext4`, `KEYDIR=/etc/ssh_keys`.
2. If `$KEYIMG` doesn't exist: `dd if=/dev/zero of="$KEYIMG" bs=64k count=32` then
   `mkfs.ext4 "$KEYIMG"` — the **exact** idiom `bin/bluetoothd` uses for
   `/media/fat/linux/bluetooth`, including no `-F` flag on `mkfs.ext4`, matching the
   proven-in-the-field stock precedent rather than second-guessing it.
3. `mkdir -p "$KEYDIR"` (safe no-op since the dir already ships in the overlay —
   `mkdir -p` on an existing directory needs no write access, so this is safe even
   though `/` is read-only) then `mount -o sync,dirsync,noatime,nodiratime "$KEYIMG" "$KEYDIR"`.
4. For each of `rsa ecdsa ed25519`: if `$KEYDIR/ssh_host_${kt}_key` doesn't exist,
   `ssh-keygen -q -t "$kt" -N '' -f "$KEYDIR/ssh_host_${kt}_key"`. **Not** `ssh-keygen
   -A -f "$KEYDIR"` — `-A`'s `-f` argument is a *prefix* ahead of the whole compiled-in
   `/etc/ssh/ssh_host_*` path (`ssh-keygen(1)`), so `-A -f /etc/ssh_keys` would land
   keys at `/etc/ssh_keys/etc/ssh/ssh_host_rsa_key`, not the flat
   `/etc/ssh_keys/ssh_host_rsa_key` the ADR and `sshd_config` both specify. Generating
   per-type avoids the gotcha entirely and is naturally idempotent (first-boot-only)
   without a separate flag file.
   **DSA is deliberately not generated** (stock had it; we don't): DSA is deprecated,
   OpenSSH 10.2p1 does not even offer `-t dsa` support in a default build, and
   `sshd_config`'s `HostKey` list (below) never references it.
5. `sshd_config` (`etc/ssh/sshd_config`, overlaid from the current package default —
   not stock's much older sshd_config, to keep every other OpenSSH 10.2p1-era default
   current) sets:
   ```
   HostKey /etc/ssh_keys/ssh_host_rsa_key
   HostKey /etc/ssh_keys/ssh_host_ecdsa_key
   HostKey /etc/ssh_keys/ssh_host_ed25519_key
   ```
   plus stock-parity `PermitRootLogin yes` and `PermitUserEnvironment yes` (both were
   commented/off in the package default).
6. `etc/ssh_keys/.gitkeep` ships the empty mount point in the overlay (git cannot
   track empty directories; this repo's own convention — see
   `uboot-patches/.gitkeep`, `linux-patches/.gitkeep`, `patches/.gitkeep` — already
   uses marker files for exactly this).
7. Verified **zero** `ssh_host_*` files anywhere in the built and extracted image
   (see the report's Check 3).

On CRNG timing: not re-verified on this build (that requires hardware, P2.9's job);
ADR 0015 cites a hardware-measured `crng init done` at ~2.17 s on this same kernel,
well before `S50sshd` runs, and `ssh-keygen`'s `getrandom()` blocks-until-seeded
regardless, so the worst case is slow, never weak.

## Other config files

| File | Status | Notes |
|---|---|---|
| `/etc/resolv.conf` | **identical (Buildroot default, kept)** | Symlink `-> ../run/resolv.conf` — Buildroot's own skeleton default, per ADR 0011. **Not overlaid on purpose** — overlaying it as a regular file would break DNS (see the ADR). Verified still a symlink after the full build (Check 1). |
| `/etc/fstab` | **adapted** (2 additive deviations) | All of stock's entries reproduced verbatim (this row said "identical / byte-for-byte, `diff` exit 0" and was stale — two tmpfs lines stock does not have were appended later: `tmpfs /var/cache/samba tmpfs mode=0755 0 0` per P3.6 / `docs/samba-parity.md` §3, asserted by `scripts/ci-tests.sh`, and `tmpfs /var/lib/seedrng tmpfs mode=0700 0 0` for BusyBox `S01seedrng`. `diff` against `work/imgroot/etc/fstab` now exits 1 with exactly those two lines plus a 6-line explanatory comment, and zero removals): ext4 `rw,noauto,noatime,nodiratime` root, tmpfs on `/tmp`, `/run`, `/dev/shm`, `/var/lib/samba`, `/var/db/dhcpcd`, plus `proc`/`devpts`/`sysfs`. |
| `/etc/hostname` | **identical** | `MiSTer\n` (7 bytes), byte-for-byte match. |
| `/etc/hosts` | **identical** | Byte-for-byte match (`127.0.1.1 MiSTer`). Buildroot's own finalize hook writes `127.0.1.1 buildroot` into `output/target/etc/hosts` **before** the overlay is copied (confirmed in the build log); the overlay copy runs later and wins — verified in the extracted image. |
| `/etc/network/interfaces` | **adapted (v9)** (1 additive deviation) | `lo` + `wlan0`/`wlan1` with the `wpa_supplicant -D nl80211,wext` pre-up hooks, all of stock's directives reproduced unchanged. No `eth0` stanza — matches stock exactly; wired ethernet is handled by dhcpcd's own default (manage-everything-not-explicitly-excluded) behavior, not ifupdown. **This row said "identical / byte-for-byte" until now and was stale:** P2.3 authored it byte-identical, but `4cf2fc7` (v9) added a header comment plus one `pre-up i=0; while [ $i -lt 20 ] && ! iw dev $IFACE info >/dev/null 2>&1; do sleep 1; i=$((i+1)); done` line per `wlan` stanza, because USB WiFi drivers that register `nl80211` asynchronously (mainline `rtw88`/`rtw89`) otherwise lose the race and `wpa_supplicant` fails with "interface not found" on a cold boot. **Revised since:** each stanza also gained a `pre-up [ -e /sys/class/net/$IFACE ]` device-presence guard ahead of that loop, because `S40network`'s `ifup -a` processes *every* `auto` stanza — so on the ordinary single-dongle box the `wlan1` stanza polled the full 20 s for a device that never appears, serialising `S41dhcpcd`/`S49ntp`/`S50sshd`/Main_MiSTer behind it on every WiFi boot (measured: 20 s). A device that is merely late is brought up by its own `add` uevent via `70-persistent-net.rules` → `etc/wifi-hotplug.sh`, which fires on udev's boot-time coldplug as well as on later insertion, so the guard costs no coverage. `diff` against `work/imgroot/etc/network/interfaces` now exits 1 with exactly 47 added lines (a 43-line header comment plus the guard and the loop in each of the two `wlan` stanzas) and zero removals. See `docs/wifi-parity.md` §1 and §9. |
| `/etc/dhcpcd.conf` | **identical** | Byte-for-byte match. The package's own default differs meaningfully (`#hostname`/`#clientid` instead of stock's enabled `hostname`/`clientid`, `duid` instead of stock's `#duid`, and is missing the `option rapid_commit` block) — all reverted to stock via the overlay. |
| `/etc/inittab` | **adapted** (3 documented deviations) | Full stock shape reproduced (`::sysinit:/media/fat/MiSTer &`, `/etc/resync &`, `rcS`, shutdown sequence) with: **(1)** the remount-rw sysinit line kept **commented out**, exactly as stock has it — Buildroot's own skeleton default inittab ships this line **uncommented**, which would remount `/` rw at every sysinit and defeat the whole read-only-root design (ADR 0011); confirmed this project's own finalize hook tries to uncomment it too (see below) and is overridden by the overlay running last. **(2)** the serial console runs `ttyS0::respawn:/sbin/agetty --nohostname -L ttyS0 115200 vt100` — util-linux `agetty`, matching stock (whose inittab also uses `agetty --nohostname`), now that `BR2_PACKAGE_UTIL_LINUX_AGETTY` is enabled (see `docs/util-linux-parity.md`). It still targets `ttyS0` explicitly rather than stock's `console` alias, because this board's actual cmdline is `console=ttyS0,115200` (`docs/boot-chain.md`). agetty treats a numeric positional argument as the baud rate, so `ttyS0 115200` and `115200 ttyS0` are equivalent; the port-first order is kept for continuity with the previous BusyBox `getty` line. (Earlier revisions used BusyBox `getty` because `BR2_PACKAGE_UTIL_LINUX_BINARIES` was not selected — that constraint no longer holds; the overlapping BusyBox `getty` applet is now disabled so `agetty` is the console.) **(3)** `gpm` is invoked at `/usr/sbin/gpm`, not stock's `/sbin/gpm` — originally **a real bug caught during acceptance verification**: gpm is a real package (not a BusyBox applet, which lands under `/sbin` regardless of usr-merge), and when this row was first written (P2.3) the rootfs was **not** usr-merged — `/sbin` was a real directory, not `-> /usr/sbin` the way stock's `work/imgroot/sbin` is — so `/sbin/gpm` genuinely did not exist in the image. An inittab `sysinit` line is an **absolute path**, so unlike `/etc/profile`'s `PATH` it gets no shell search at all; it would have silently failed to spawn on every single boot. Caught by exhaustively grep'ing every absolute path referenced anywhere in the overlay against the actually-built image (see the task report) — first build had this wrong; fixed and rebuilt before acceptance. **Since P2.9 v2** (`7be9ee5`) set `BR2_ROOTFS_MERGED_USR=y`, that premise no longer holds: this build is now usr-merged like stock (verified: `output/target/sbin -> usr/sbin`), so `/sbin/gpm` *would* resolve today. **The deviation is kept anyway, deliberately.** Buildroot builds gpm with `--prefix=/usr`, so the binary's real path is `/usr/sbin/gpm` in *either* layout (gpm's own file list: `gpm,./usr/sbin/gpm`) — stock's binary is at that same physical path, and stock's inittab only reaches it through the `/sbin -> usr/sbin` compat symlink that exists solely because stock is usr-merged. So our path is correct in both layouts and stock's is correct in only one; ours survives an unmerge, stock's would break on one. Given P2.3 already got bitten by exactly that (the unmerged build had no `/sbin/gpm` at all), pointing at the real path rather than a merge-dependent alias is the more durable choice, even though a future unmerge is unlikely. This is an **accepted permanent deviation from stock**, not a cleanup waiting to happen. **Also dropped — later RESTORED, guarded (T3, 2026-07-27):** `loadkeys /etc/kbd.map` and `setfont` were dropped by P2.3 because this BusyBox build has no `loadkeys` applet at all and `CONFIG_SETFONT` is explicitly not set (still true — re-verified in `output/build/busybox-1.38.0/.config`; busybox's `loadkmap` applet is not a substitute, it reads binary bkeymap, not stock's text keymap); keeping either line verbatim would just fail every boot. T3 vendored stock's `etc/kbd.map` (it blanks the F12/Mute/Vol± keycodes Main_MiSTer consumes via evdev) and restored both lines wrapped in `[ -x /usr/bin/... ]` guards: with the parallel T5 task's `BR2_PACKAGE_KBD` (the same package stock's own loadkeys/setfont came from) the lines do stock's exact job, without it they are silent no-ops instead of boot errors. See the inittab's own note 3 and `docs/stock-reconciliation.md` §3c. `gpm -m /dev/input/mice -t imps2` itself **is** kept (just at the corrected path) — `BR2_PACKAGE_GPM=y` was deliberately selected in P2.1 for this, and the binary is present. |
| `/etc/passwd` (root's shell) + `/bin/sh` | **identical (since issue #144)** | Stock: `root:x:0:0:root:/root:/bin/bash` and `/bin/sh -> bash`. Until 2026-09-03 this build shipped Buildroot's defaults — BusyBox ash as `/bin/sh` and root on `/bin/sh` — because no fragment set `BR2_SYSTEM_BIN_SH`, and no row here recorded it. Found while chasing #142 (WinSCP), which was a separate `/etc/profile` defect but whose error text ("BASH is recommended") pointed at the shell. Fixed with `BR2_SYSTEM_BIN_SH_BASH=y` in `de10nano-image.fragment`: Buildroot's skeleton finalize hook both re-links `/bin/sh` and rewrites root's passwd shell from that one symbol, so the result matches stock with no overlay or post-build edit. `docs/buildroot-config.md` §5.19 has the rationale; `scripts/ci-tests.sh` asserts both halves. |
| `/etc/profile` | **adapted** (2 documented deviations) | Full stock content reproduced (PATH, `PS1='$(pwd)# '`, `EDITOR=/bin/vi`, `/etc/profile.d/*.sh` sourcing, `LC_ALL=en_US.UTF-8`, and critically the login-time `mount -o remount,rw /` — this is how `/` ever becomes writable at all, matching stock and ADR 0011's own description of the mechanism). **Deviation:** `PATH` gains an explicit `/bin:/sbin:` prefix stock's literal string doesn't have. Stock's rootfs is usr-merged (`work/imgroot`: `/bin -> usr/bin`, `/sbin -> usr/sbin`), so its `PATH="/usr/bin:/usr/sbin"` already covered `/bin`/`/sbin` for free. When this deviation was introduced (P2.3) *this* build was a plain (non-merged) skeleton layout, so omitting `/bin:/sbin` from `PATH` would have silently dropped most BusyBox applets from every interactive shell; changing `BR2_ROOTFS_MERGED_USR` was then out of P2.3's scope ("do NOT disturb ... the package set"), making the overlay `PATH` the correct-altitude fix. **Since P2.9 v2** (`7be9ee5`) set `BR2_ROOTFS_MERGED_USR=y` — the change that fixed the `/lib/security/pam_unix.so` SSH lockout — this build is usr-merged too, so the `/bin:/sbin:` prefix is now redundant. It is kept because it is harmless (the paths resolve to the same directories) and matches Buildroot's own skeleton default profile. The file's own header comment records the same history. **Deviation 2 (2026-09-03, issue #142):** stock's trailing bare `resize >/dev/null` is guarded as `[ "$PS1" ] && [ -z "$SSH_CONNECTION" ] && resize >/dev/null`. `resize` is the BusyBox applet: it writes a cursor-position query to stderr and reads the reply from stdin under a 3 s alarm. On the serial console that is the only way the shell learns the window size, so it stays. Over SSH it is redundant (sshd propagates the client's window size through the pty) and, for a client that opens the login shell **without** a pty, actively broken: WinSCP's SCP mode and its terminal window receive the escape bytes on stderr and lose their first command to `resize`'s `scanf`, which WinSCP reports as "Error skipping startup message. Your shell is probably incompatible with the application" (forum report: https://misterfpga.org/viewtopic.php?p=113698#p113698). SFTP, PuTTY and command-line scp were never affected. Stock has the identical defect — verified on `release_20250402`'s `linux.img` (same profile line, `resize -> busybox` 1.33.1) by running stock's own busybox under `qemu-arm` on a pty: identical bytes, next input line swallowed. `SSH_CONNECTION` rather than `SSH_TTY` because sshd sets the former for every session and the latter only when a pty is allocated. Verified on a board: no-pty login shell, pty login shell and `bash -l` are all clean; a simulated console login (SSH vars cleared) still runs `resize`. |
| `/usr/lib/dhcpcd/dhcpcd-hooks/90-timezone` | **added (divergence, [ADR 0025](decisions/0025-first-boot-timezone-autodetect.md))** | Stock has no equivalent, and that is the gap it closes: `/etc/localtime` points at `/media/fat/linux/timezone`, which **does not exist on a fresh card**, so glibc falls back to UTC silently and permanently. The first time dhcpcd brings an interface up with an address, this asks `ip-api.com` for the zone of the box's public IP and copies `/usr/share/zoneinfo/posix/<Zone>` to that path — the *same* provider, destination and file format as the community `Scripts_MiSTer/timezone.sh` "Automatic" mode, so the two are interchangeable. No new package (`curl` and tzdata were already in the image). **Note this adds no init script**: an earlier revision had an `S48timezone` as well, but on a DHCP box the lease has usually not landed by S48, so it was near-redundant with this hook — and it carried a `/proc/net/route` check whose IPv6 arm silently matched the kernel's own `ip6_null_entry`. A static-IP box configured only in `/etc/network/interfaces` never runs dhcpcd and so never autodetects; accepted deliberately, since setting a static address is already a by-hand act. Properties worth stating because they are the design: the guess is spent **once, and only when it was actually made** (gated on the timezone file *and* on a `timezone.autodetect` stamp written only when a provider answered *with a zone name*, so neither being offline nor a captive portal's HTTP 200 burns it), it **never overwrites** a timezone anyone has already set (re-checked immediately before the write, not only at the gate), and it **delays nothing** — the body is a backgrounded subshell, which also keeps it from leaking a single variable or function into dhcpcd's shell. Sourced, not executed (`dhcpcd-run-hooks`: `. "$hook"`), hence no shebang, no exec bit, and no `exit` — an `exit` here would end dhcpcd's whole hook run and take `20-resolv.conf`/`30-hostname` with it. Zone names arrive off the network, so they are validated against the shipped zoneinfo before being used as a path; `scripts/test-timezone.sh` asserts each rejection, and mutation-checks the two that could otherwise pass vacuously. |
| `/usr/lib/dhcpcd/dhcpcd-hooks/91-ntp-kick` | **added (divergence)** | Stock has no equivalent. The gap: this board has no RTC, so a cold boot starts at the epoch, and `S49ntp` launches `ntpd -g` at a fixed point in `rcS` whether or not a network exists — which on the common path it does not, since WiFi association plus DHCP normally completes well after S49. ntpd survives that in one half and not the other. The **interface** half heals itself: ntpd is built with `HAVE_RTNETLINK` (`config.h:786`), so an address appearing is a netlink event and `ntp_io.c:1980` → `ntp_peer.c:763` `refresh_all_peerinterfaces` reattaches peers within ~3 s. The **DNS** half does not: for a `server <hostname>` line the peer is created *only* in the DNS callback (`ntp_config.c:4459-4463` → `peer_name_resolved`), and at S49 there is no `/etc/resolv.conf` — `20-resolv.conf` writes it in this very hook pass — so resolution fails and **no peers exist at all** for the rescan to reattach. The clock then waits on ntpd's DNS retry backoff and nothing else: `libntp/ntp_intres.c` `manage_dns_retry_interval` walks 2-3-4-6-8-12-16-24-32-48-64 s (`config.h:1313` leaves `IGNORE_DNS_ERRORS` undefined, so `DNSFLAGS` is 0 and `retmax` is 64, not 1024), putting attempts at t = 2, 5, 9, 15, 23, 35, 51, 75, 107, 155, 219, 283 … s after ntpd started. Measured cost of the next-slot wait: a few seconds on a wired box, 10-20 s on a typical WiFi boot, 30 s to a couple of minutes when the network turns up late. This restarts ntpd once, when an address actually arrives, so it re-resolves against the `resolv.conf` that now exists; `/etc/ntp.conf`'s `iburst` and `S49ntp`'s `-g` then give correct time within ~10-15 s. **Not `sntp`**: `BR2_PACKAGE_NTP_SNTP` would also install Buildroot's `S48sntp` (`package/ntp/ntp.mk:110-114`), which runs sntp at boot one script *before* ntpd with no network, and would have to be suppressed — not worth ~10 s. **Not `service_condcommand`** (which `50-ntp.conf` uses): dhcpcd's `detect_init` finds no systemctl/rc-service/invoke-rc.d/service/sv here and falls through to its `/etc/init.d` branch, which tests `[ -x /etc/init.d/ntpd ]` — ours is `S49ntp` — and `service_status` then runs `$x/$1 status`, a verb `S49ntp` has no case for; both fail silently. The hook calls the script directly. **Not a udev rule**: a `net` `add` uevent fires when the netdev is *created*, before association, lease, route or `resolv.conf`, which would reproduce the bug one layer down. Design properties: fires **at most once per boot** (`mkdir /run/ntp-kick` is the atomic test-and-set, on a tmpfs, so it re-arms each boot — two interfaces can `BOUND` at the same moment, and restarting ntpd more than once would discard its accumulated clock discipline for nothing); **never starts an ntpd that is not running**, so a by-hand or `/etc/default/ntpd` disable stands; and the stamp is claimed **last**, after every gate, so a pass that bails out leaves the one kick available — which is what makes the wired-box ordering case correct, where `S41dhcpcd` blocks until the first lease and so fires this hook *before* `S49ntp` has started ntpd at all. Backgrounded subshell (`S49ntp restart` contains a `sleep 1`), sourced not executed — no shebang, no exec bit, no `exit`. A static-IP box never runs dhcpcd and never gets kicked; accepted, the same gap ADR 0025 accepts, and ntpd's own backoff still converges there. **Acquisition reasons only** — `BOUND`/`REBOOT` and their `*6` forms, deliberately *not* `RENEW`/`REBIND` as `90-timezone` matches: dhcpcd picks those two only when `state->old` is non-NULL (`src/dhcp.c:2499-2513`), i.e. the address was already there. Matching them combines badly with the re-armable stamp — a renewal arriving hours into the session would restart an ntpd that had been synchronised the whole time, and the wired ordering case makes that reachable rather than theoretical, since it always bails out first and leaves the kick armed. Nothing is lost: WiFi associating late, a dongle plugged in later and an AP returning are all *new* leases, hence `BOUND`; and an address that merely changes under a `RENEW`/`REBIND` needs no kick, because ntpd holds peers by then and the `HAVE_RTNETLINK` path reattaches them in ~3 s. (Found in review of PR #147.) `scripts/test-ntp-kick.sh` asserts the behaviour in 38 sandboxed cases (run twice by `ci-tests.sh`: host shell, and the target's own BusyBox ash under qemu-arm), mutation-checked against dropping the once-per-boot gate, the liveness check, the narrowed reason set, the process-identity check and the pid-0 rejection. The liveness probe is `start-stop-daemon -K -t -q -p <pidfile> -x /usr/sbin/ntpd`, which checks identity as well: the pidfile cannot outlive a boot (tmpfs), but a crashed ntpd within one boot leaves one, and a long-running box can wrap `pid_max` and reuse that pid — restarting then would have `S49ntp`'s stock `stop()` (`start-stop-daemon -K -p` with no `-x`) SIGTERM an unrelated process, and this hook is the first automatic caller of that script. A pidfile containing `0` is rejected explicitly, because `kill -0 0` signals the process group and the probe itself was measured to succeed on it. Both behaviours measured on ours (BusyBox 1.38.0) and stock's (1.33.1). (Found in review of PR #147.) |
| `/usr/lib/dhcpcd/dhcpcd-hooks/` (the set) | **pinned (build-host independence)** | dhcpcd's `configure` chooses which hooks to install by probing the **build host** for `ntpd`/`chronyd`/`systemd-timesyncd`/`ypbind`, and Buildroot's `dhcpcd.mk` passes no `--with-hooks`, so the image inherited whatever daemons the build machine happened to have: a GitHub runner produced `50-ntp.conf`, a developer box with timesyncd produced `50-timesyncd.conf` — with a green build both times (found 2026-09-02 by diffing a CI image against a local one). `external.mk` now appends `--with-hooks=ntp.conf --with-eghooks=yp.conf` to `DHCPCD_CONFIG_OPTS`, which reproduces the canonical CI image exactly (`01-test`, `20-resolv.conf`, `30-hostname`, `50-ntp.conf`, plus our `90-timezone` and `91-ntp-kick`; `50-yp.conf` stays an example under `/usr/share/dhcpcd/hooks`), and `scripts/check-linux-img.sh` asserts that exact set. `50-ntp.conf` is the right hook to pin given we ship classic `ntpd` (stock parity), though it is **inert in this image**: it merges DHCP-offered servers into `/etc/ntp.conf`, and `etc/dhcpcd.conf` leaves `option ntp_servers` commented out exactly as stock does, so it is never offered any. It is pinned because its *presence* is what proves `configure` did not probe the build host — not because it runs. Its `service_condcommand ntpd restart` could not work here either; see the `91-ntp-kick` row. Upstream-worthy: Buildroot's `dhcpcd.mk` should pass `--with-hooks` itself. |
| `/etc/resync` | **identical** | Byte-for-byte match (53 bytes: `( while [ 1 ]; do sync; sleep 5; done ) &`). Executable bit set. |
| `/etc/proftpd.conf` | **identical, with a flagged security caveat** | Byte-for-byte reproduction of stock: `User root`/`Group root`, `RootLogin on`, anonymous `<Limit WRITE> AllowAll`, `Umask 000`. **Note, not acted on:** the package's own default `proftpd.conf` is meaningfully more hardened (`User nobody`, no root login, anonymous write denied). This project's task scope names exactly two sanctioned security improvements (resolv.conf's upstream default, ADR 0015's SSH host keys); silently hardening FTP as a third, undocumented one would change a well-known MiSTer workflow (anonymous/root FTP to `/media/fat`) without a maintainer decision or its own ADR. Shipped as stock parity; flagged here and in the task report as a candidate for a future ADR, not decided unilaterally. |
| `/etc/samba/smb.conf` | **identical** | Byte-for-byte reproduction of stock (276 lines). `S91smb`'s stock double-guard (see above) means Samba cannot auto-start regardless — `/media/fat/linux/samba.sh` will never exist on a fresh image. |
| Five regular user-files (`/etc/hostname`, `/etc/hosts`, `/etc/network/interfaces`, `/etc/dhcpcd.conf`, `/etc/fstab`) | **identical** | All five verified regular files (not symlinks) in the extracted image — Invariant A8 replacement per ADR 0011 (five regular files + one symlink, not six regular files). |
| `/media/fat` | **new (required)** | Did not exist before this task (P1.10's requirement, never fulfilled until now). Empty directory (marker file `.gitkeep` only) ships in the overlay so `/init`'s `mount -o move /mnt/fat /newroot/media/fat` has somewhere to move onto — `/` is read-only, so `/init` cannot `mkdir` it itself. |
| `/dev`, `/proc`, `/sys` | **identical (Buildroot skeleton default, unmodified)** | Not touched by this overlay at all (no `dev/`, `proc/`, or `sys/` directory anywhere under `board/mister/de10nano/rootfs-overlay/`) — Buildroot's own `system/skeleton/` already ships these as the P1.10 requirement expects. `/dev` is not literally empty (it carries the skeleton's static `fd`/`stdin`/`stdout`/`stderr` symlinks and `pts`/`shm`/`log` entries) but that is stock Buildroot behavior, harmless, and gets shadowed by the initramfs's `devtmpfs` `mount -o move` at boot regardless. |
| `/etc/udev/rules.d/70-persistent-net.rules` | **adapted** (2 documented deviations) | Added by T2; stock ships this exact path (an `addon.tar` entry — `docs/verification/stock-reconciliation/addon-report.txt:25`; bytes read from `work/imgroot/etc/udev/rules.d/70-persistent-net.rules`, 450 bytes). It is what brings a WiFi dongle up when it is plugged in *after* boot. Both of stock's rules are reproduced, keeping `SUBSYSTEM=="net"`, the `DRIVERS=="?*"` guard and `KERNEL=="wlan*"`, with two deliberate divergences: **(1)** stock's `NAME="wlan0"` is dropped — it collapses every `wlan*` device onto one literal name, contradicting this image's `auto wlan0` **and** `auto wlan1` stanzas, and buys nothing on a board with no PCI bus for eudev's `net_id` builtin to derive a predictable name from; **(2)** `RUN+=` calls `/etc/wifi-hotplug.sh <up\|down> %k` instead of `/sbin/ifup -a` / `/sbin/ifdown %k`, so the bring-up is targeted at the interface whose uevent fired and is detached from the udev worker. Full reasoning with file:line citations lives in the rule file's own header comment and `docs/wifi-parity.md` §9. `scripts/ci-tests.sh` asserts the path, mode 644, and that `NAME="wlan0"` has not been reintroduced. |
| `/etc/wifi-hotplug.sh` | **new (no stock counterpart)** | Added by T2, mode 755. The async `ifup`/`ifdown` dispatcher the rule above calls — `setsid` + redirected std fds + `&`, so the ≤20 s `pre-up` `iw dev` wait never occupies a udev worker. That matters at boot rather than merely being tidy: `package/eudev/S10udevd:43` runs `udevadm settle --timeout=30` right after the coldplug trigger, so a blocking `RUN+=` would stall `rcS` for the whole bring-up on every boot with WiFi hardware present. Stock has no equivalent file (it calls `ifup`/`ifdown` straight from `RUN+=`); this is a deviation in *mechanism*, not in behavior. See `docs/wifi-parity.md` §9, Divergence 2. |

## Closed gap: USB-storage automount

Stock ships a whole `usbmount` subsystem (`etc/usbmount/`, `lib/udev/rules.d/usbmount.rules`,
a real Buildroot `usbmount` package) that auto-mounts USB storage on insert. **P2.3 did
not reproduce it**: `BR2_PACKAGE_USBMOUNT` was not set — P2.1's package manifest never
selected it, and P2.3's constraints were explicit (**"do NOT disturb ... the package
set."**), so shipping `etc/usbmount/*` config alone would have been inert config for a
mechanism that wasn't there. It was flagged here rather than silently left out, and did
not affect SSH or networking (P2.3's hard requirements), which is why it wasn't a blocker.

**This gap is now closed.** `BR2_PACKAGE_USBMOUNT=y` is set in
`configs/fragments/de10nano-image.fragment`, the stock-tuned `usbmount.conf` ships in the overlay,
and util-linux `mount` plus a `mount.ntfs -> ntfs-3g` helper make NTFS drives mount the
way they do on stock. See **`docs/usb-automount-parity.md`** for the full picture.

## Shellcheck

Two scripts were genuinely authored/adapted by this task and both are shellcheck-clean:

```
$ shellcheck -s sh etc/init.d/S50sshd etc/init.d/S40bluetoothd
(no output — clean)
```

Files that are **byte-for-byte reproductions of stock** (`etc/init.d/S91smb`,
`etc/resync`, `bin/bluetoothd`, `etc/profile`) do trip a handful of shellcheck style
findings (legacy backticks, unquoted expansions, `[ $? = 0 ]` instead of checking the
command directly — `SC2006`/`SC2086`/`SC2181`/`SC2161`/`SC2231`). These were
**deliberately left unmodified**: the whole point of these entries is byte-identical
fidelity to the verified stock ground truth in `work/imgroot/`, and "fixing" their
style would mean they were no longer what they claim to be. Only the scripts this
task actually wrote new logic for are held to the shellcheck-clean bar.
