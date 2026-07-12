# Init & config parity — stock vs. `rootfs-overlay/`

Task: **P2.3**. Depends on P0.3 (`docs/stock-inventory/etc-configs.md`) and P2.1 (full
package set). Consumed by P2.4 (read-only-root audit) and P2.9 (hardware boot).

**Method.** Every stock file cited below was read from `work/imgroot/` (the extracted
stock `linux.img`, P0.3's ground truth). Every "current" / "package default" file was
read from `output/target/` **after** P2.1's full package-set build but **before**
this task's overlay was wired in, so the diffs are genuinely against what Buildroot's
packages install unprompted, not against a strawman. The overlay itself lives at
`board/mister/de10nano/rootfs-overlay/` and is wired via `BR2_ROOTFS_OVERLAY` in
`configs/mister_de10nano_defconfig` (added by this task; previously unset for the
full-rootfs build — only the initramfs defconfig had its own overlay).

Build verified: `make mister_de10nano_defconfig && make all` completed clean,
`output/images/rootfs.tar` (180 MB) and `output/images/zImage_dtb` (8,771,237 bytes,
`check-zimage-dtb.sh` all-pass) both produced. All claims below were checked against
`output/images/rootfs.tar`, extracted fresh, with the actual commands and output
reproduced in this task's report (not re-typed from memory).

**This took two build iterations, on purpose.** After the first successful build,
every absolute path referenced anywhere in the overlay was grep'ed out and checked
against the actually-extracted image (not assumed from stock's shape) — this caught
a real bug: `/etc/inittab`'s `gpm` line pointed at `/sbin/gpm`, copied verbatim from
stock, but this build's rootfs is not usr-merged the way stock's is, so `/sbin/gpm`
does not exist here (only `/usr/sbin/gpm` does) and the line would have silently
failed to spawn gpm on every boot. Fixed to `/usr/sbin/gpm`, rebuilt, re-verified —
see the `/etc/inittab` row below. Everything reported as PASS in this task's report
reflects the **second, corrected** build.

## Summary

| Status | Count | Meaning |
|---|---|---|
| identical | 6 | Byte-identical to stock, or functionally identical modulo cosmetic/tooling differences (documented per row) |
| adapted | 6 | Behavior intentionally differs from stock, for a stated reason |
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
| `S91smb` | **identical** (overlaid to restore stock's opt-in gate) | Byte-identical to stock. **Problem found and fixed:** the package's own default `S91smb` only guards on `/etc/samba/smb.conf` existing; stock has a **second** guard, `[ -f /media/fat/linux/samba.sh ] || exit 0`. Without it, shipping `/etc/samba/smb.conf` (done for config parity, see below) would make Samba **auto-start on every boot** — stock's actual behavior is opt-in (Samba only starts once the user/Downloader drops `samba.sh` onto the FAT partition). Reverted to stock's double-guard form, plus its extra `mkdir -p` calls and the `samba.sh` trailer call. |
| `S99user` | **identical** | Not present as a package default (no package provides a MiSTer-specific user hook). Added byte-identical to stock: calls `/media/fat/linux/user-startup.sh` if present. |

### Non-`S`-prefixed control scripts

`rcS` / `rcK` — **identical**, byte-for-byte (BusyBox init's own runlevel drivers,
package-provided, unchanged from stock).

### Extra init scripts beyond stock's 12-script list

P2.1's package set (a superset of stock's, per `docs/package-manifest.md` — ~5 years
newer, more packages) installs several init scripts stock never had:
`S01seedrng`, `S02sysctl`, `S11modules`, `S30rpcbind`, `S35iptables`, `S50crond`,
`S60nfs`. None of these conflict with anything above (verified by filename/number and
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
| `/etc/fstab` | **identical** | Byte-for-byte reproduction of stock (`diff` exit 0): ext4 `rw,noauto,noatime,nodiratime` root, tmpfs on `/tmp`, `/run`, `/dev/shm`, `/var/lib/samba`, `/var/db/dhcpcd`, plus `proc`/`devpts`/`sysfs`. |
| `/etc/hostname` | **identical** | `MiSTer\n` (7 bytes), byte-for-byte match. |
| `/etc/hosts` | **identical** | Byte-for-byte match (`127.0.1.1 MiSTer`). Buildroot's own finalize hook writes `127.0.1.1 buildroot` into `output/target/etc/hosts` **before** the overlay is copied (confirmed in the build log); the overlay copy runs later and wins — verified in the extracted image. |
| `/etc/network/interfaces` | **identical** | Byte-for-byte match: `lo` + `wlan0`/`wlan1` with the `wpa_supplicant -D nl80211,wext` pre-up hooks. No `eth0` stanza — matches stock exactly; wired ethernet is handled by dhcpcd's own default (manage-everything-not-explicitly-excluded) behavior, not ifupdown. |
| `/etc/dhcpcd.conf` | **identical** | Byte-for-byte match. The package's own default differs meaningfully (`#hostname`/`#clientid` instead of stock's enabled `hostname`/`clientid`, `duid` instead of stock's `#duid`, and is missing the `option rapid_commit` block) — all reverted to stock via the overlay. |
| `/etc/inittab` | **adapted** (3 documented deviations) | Full stock shape reproduced (`::sysinit:/media/fat/MiSTer &`, `/etc/resync &`, `rcS`, shutdown sequence) with: **(1)** the remount-rw sysinit line kept **commented out**, exactly as stock has it — Buildroot's own skeleton default inittab ships this line **uncommented**, which would remount `/` rw at every sysinit and defeat the whole read-only-root design (ADR 0011); confirmed this project's own finalize hook tries to uncomment it too (see below) and is overridden by the overlay running last. **(2)** the serial getty targets `ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100` instead of stock's `console` alias — this board's actual cmdline is `console=ttyS0,115200` (`docs/boot-chain.md`), and this build has no `agetty` (`BR2_PACKAGE_UTIL_LINUX_BINARIES` is not selected — package-set constraint), only BusyBox `getty`, whose argument parser (`loginutils/getty.c:parse_args`, read from `output/build/busybox-1.37.0/`) accepts either `tty baud` or `baud tty` order, so `getty -L ttyS0 115200 vt100` was verified against the actual source, not guessed. **(3)** `gpm` is invoked at `/usr/sbin/gpm`, not stock's `/sbin/gpm` — **a real bug caught during acceptance verification**: gpm is a real package (not a BusyBox applet, which lands under `/sbin` regardless of usr-merge), and this build's rootfs is not usr-merged (confirmed: `/sbin` is a real directory here, not `-> /usr/sbin` the way stock's `work/imgroot/sbin` is), so `/sbin/gpm` genuinely does not exist in this image — an inittab `sysinit` line pointing at it is an **absolute path**, so unlike `/etc/profile`'s `PATH` it gets no shell search at all; it would have silently failed to spawn on every single boot. Caught by exhaustively grep'ing every absolute path referenced anywhere in the overlay against the actually-built image (see the task report) — first build had this wrong; fixed and rebuilt before acceptance. **Also dropped:** `loadkeys /etc/kbd.map` and `setfont` — this BusyBox build has no `loadkeys` applet at all and `CONFIG_SETFONT` is explicitly not set (`output/build/busybox-1.37.0/.config`); keeping either line verbatim would just fail every boot (non-fatal to boot, but dead weight). `gpm -m /dev/input/mice -t imps2` itself **is** kept (just at the corrected path) — `BR2_PACKAGE_GPM=y` was deliberately selected in P2.1 for this, and the binary is present. |
| `/etc/profile` | **adapted** (1 documented deviation) | Full stock content reproduced (PATH, `PS1='$(pwd)# '`, `EDITOR=/bin/vi`, `/etc/profile.d/*.sh` sourcing, `LC_ALL=en_US.UTF-8`, and critically the login-time `mount -o remount,rw /` — this is how `/` ever becomes writable at all, matching stock and ADR 0011's own description of the mechanism). **Deviation:** `PATH` gains an explicit `/bin:/sbin:` prefix stock's literal string doesn't have. Stock's rootfs is usr-merged (`work/imgroot`: `/bin -> usr/bin`, `/sbin -> usr/sbin`), so its `PATH="/usr/bin:/usr/sbin"` already covered `/bin`/`/sbin` for free; this build is a plain (non-merged) Buildroot skeleton layout — confirmed via `readlink`, real directories, not symlinks — so omitting `/bin:/sbin` from `PATH` would silently drop most BusyBox applets from every interactive shell. Changing `BR2_ROOTFS_MERGED_USR` itself is a toolchain/skeleton-level decision, out of P2.3's scope ("do NOT disturb ... the package set"); fixing `PATH` in the overlay is the correct-altitude fix. This matches Buildroot's own skeleton default profile, which already does exactly this for the same reason. |
| `/etc/resync` | **identical** | Byte-for-byte match (53 bytes: `( while [ 1 ]; do sync; sleep 5; done ) &`). Executable bit set. |
| `/etc/proftpd.conf` | **identical, with a flagged security caveat** | Byte-for-byte reproduction of stock: `User root`/`Group root`, `RootLogin on`, anonymous `<Limit WRITE> AllowAll`, `Umask 000`. **Note, not acted on:** the package's own default `proftpd.conf` is meaningfully more hardened (`User nobody`, no root login, anonymous write denied). This project's task scope names exactly two sanctioned security improvements (resolv.conf's upstream default, ADR 0015's SSH host keys); silently hardening FTP as a third, undocumented one would change a well-known MiSTer workflow (anonymous/root FTP to `/media/fat`) without a maintainer decision or its own ADR. Shipped as stock parity; flagged here and in the task report as a candidate for a future ADR, not decided unilaterally. |
| `/etc/samba/smb.conf` | **identical** | Byte-for-byte reproduction of stock (276 lines). `S91smb`'s stock double-guard (see above) means Samba cannot auto-start regardless — `/media/fat/linux/samba.sh` will never exist on a fresh image. |
| Five regular user-files (`/etc/hostname`, `/etc/hosts`, `/etc/network/interfaces`, `/etc/dhcpcd.conf`, `/etc/fstab`) | **identical** | All five verified regular files (not symlinks) in the extracted image — Invariant A8 replacement per ADR 0011 (five regular files + one symlink, not six regular files). |
| `/media/fat` | **new (required)** | Did not exist before this task (P1.10's requirement, never fulfilled until now). Empty directory (marker file `.gitkeep` only) ships in the overlay so `/init`'s `mount -o move /mnt/fat /newroot/media/fat` has somewhere to move onto — `/` is read-only, so `/init` cannot `mkdir` it itself. |
| `/dev`, `/proc`, `/sys` | **identical (Buildroot skeleton default, unmodified)** | Not touched by this overlay at all (no `dev/`, `proc/`, or `sys/` directory anywhere under `board/mister/de10nano/rootfs-overlay/`) — Buildroot's own `system/skeleton/` already ships these as the P1.10 requirement expects. `/dev` is not literally empty (it carries the skeleton's static `fd`/`stdin`/`stdout`/`stderr` symlinks and `pts`/`shm`/`log` entries) but that is stock Buildroot behavior, harmless, and gets shadowed by the initramfs's `devtmpfs` `mount -o move` at boot regardless. |

## Known gap: USB-storage automount

Stock ships a whole `usbmount` subsystem (`etc/usbmount/`, `lib/udev/rules.d/usbmount.rules`,
a real Buildroot `usbmount` package) that auto-mounts USB storage on insert. **This
task did not reproduce it.** `BR2_PACKAGE_USBMOUNT` is not set in
`configs/mister_de10nano_defconfig` (confirmed: `grep USBMOUNT output/.config` →
`# BR2_PACKAGE_USBMOUNT is not set`) — P2.1's package manifest never selected it, and
P2.3's constraints are explicit: **"do NOT disturb ... the package set."** Shipping
`etc/usbmount/*` config without the package's udev rules and mount-helper binary
would be inert config for a mechanism that isn't there. This needs a P2.1-adjacent
follow-up (adding `BR2_PACKAGE_USBMOUNT=y`) before it can be closed — flagged loudly
here rather than silently left out. It does not affect SSH or networking (P2.3's
hard requirements), which is why it wasn't treated as a blocker.

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
