# minijail

`package/minijail` ships Google's [minijail](https://google.github.io/minijail/):
`/usr/bin/minijail0` and `/usr/lib/libminijailpreload.so`. It is in
the `mister-userspace` profile, so the DE10 image carries it. Its users are the jailed
`S92transmission`, `/usr/bin/bluetoothd` (`docs/bluetooth-parity.md` §11) and mistarr, whose
design is mistarr's `docs/NONROOT-PLAN.md`. Their fixed uids are in
`board/mister/de10nano/users.table`.

## Why minijail

The SD card is exFAT, mounted with no `uid=`/`gid=`, so every file on it is `root:root 0755`
and file permissions cannot separate one daemon from another (ADR 0031). What can is a mount
namespace with a bind-mount allow-list: the daemon runs as its own numeric uid with only
`CAP_DAC_OVERRIDE`, and sees only the paths it is given. minijail builds that view from one
command line, with a PID namespace, `no_new_privs`, capability bounding and rlimits, and it
needs none of the kernel features this image lacks.

## What the kernels have, and what that means for callers

| Feature | DE10 6.18 / RT 7.2 | Consequence |
|---|---|---|
| seccomp (`CONFIG_SECCOMP_FILTER`) | on since D13 (2026-10-04) | `-S` works; the build has no soft-fail, so a policy that does not compile fails closed. `-L` logs through the audit subsystem, which these kernels do not have, so prefer `return <errno>` rules to relying on kill |
| Landlock | on since D13, the only LSM | `--fs-path-*` is enforced; rules are applied after `-P`, so they name paths inside the jail |
| pids cgroup controller | on since D13; cgroup2 is mounted at `/sys/fs/cgroup` | put the caller's shell in a child cgroup before `exec minijail0` (minijail0 has no flag for it) |
| memory cgroup controller | off, deliberately (ADR 0031 amendment 2026-10-04) | use `-R` rlimits and `oom_score_adj` instead |
| user namespaces | off, deliberately | no `-U`/`-m`/`-M`; run as root and drop to a uid with `-u`/`-g` |

Mount, PID, IPC and UTS namespaces, ambient capabilities and `no_new_privs` are all present.
The DE25 kernel has the same set through the shared fragment.

## Jailing a daemon

An init script that jails a daemon declares the jail in
`/etc/minijail/<name>.conf` and sources `/usr/lib/mister/jail.sh` for the rest.
`/usr/bin/bluetoothd` (`docs/bluetooth-parity.md` §11), `S92transmission`
(`docs/bittorrent.md` §8.1), `S01syslogd` and `S02klogd` (below), and `/usr/libexec/mister/wpa-jail`
(`docs/wifi-parity.md` §15) are written this way.

**The config file** is minijail0's own `--config` format (`% minijail-config-file
v0`, then one long or short option per line; `minijail0 --gen-config <file>
<options>` writes one from a working command line). It holds what is
particular to the daemon: `u`, `g` and `c` (numeric, since the helper reads
them back for its self-check), the namespaces, the rlimits, the mounts and the
Landlock rules. Everything every jail gets is on the helper's command line:
`-T static -n --ambient`, the tmpfs root (`-P /run/<name>/root`), the seccomp
policy, `RLIMIT_CORE` 0, and `/media/fat/linux/timezone` at `/etc/localtime`
when it is a plain file (syslog takes each daemon's own timestamps).

**The script** sets `JAIL_NAME`, `JAIL_EXEC`, `JAIL_PIDS_MAX` and
`JAIL_PROBE`, optionally `JAIL_COMM` (the process name, for a BusyBox applet whose exe
is `/usr/bin/busybox` like every other), `JAIL_ARGS_MATCH` (a word sequence the command
line must contain, for one binary run once per interface), `JAIL_SECCOMP_RULES`, `JAIL_STOP_WAIT`,
`JAIL_STOP_KILL`, `JAIL_LOG_TAG` and `JAIL_OOM_SCORE_ADJ` (the header of
`jail.sh` lists them), calls `jail_init`, and then:

| Step | Helper | What it does |
|---|---|---|
| verbs | `jail_lock` | `flock` on `/run/<name>.lock`, so `start`/`stop`/`restart` never interleave; the daemon does not inherit it |
| start | `jail_running`, `jail_any_daemon` | ours is running (pidfile, start time and exe all match), or some other copy of the binary is |
| | `jail_prepare_root` | fresh tmpfs root with the merged-usr links; the script adds its own mount points after it |
| | `jail_prepare` | the seccomp policy (once per boot), the pids cgroup, and the Landlock probe; sets `JAIL_ERR` on failure |
| | `jail_launch` | `setsid "$0" run`, waits for the daemon, runs the `/proc` self-check, writes the pidfile; on failure kills what it started |
| `run` verb | `jail_run -- <command>` | joins the cgroup, closes every inheritable fd above 2, then `minijail0 ... -i -f` |
| stop | `jail_stop` | `SIGTERM` with `SIGCONT` alongside, `JAIL_STOP_WAIT` seconds, then `SIGKILL` if `JAIL_STOP_KILL=1` |
| any | `jail_exec <options> -- <command>` | one-off commands in the same view, e.g. writing a seed file as the daemon's uid |

**The seccomp policy** is generated from `minijail0 -H`, minijail's own
syscall table: every syscall is allowed except a shared deny list (mount and
namespace calls, ptrace, bpf, io_uring, keyrings, module and kexec loading,
clock setting, ...), which return `EPERM`. `JAIL_SECCOMP_RULES` replaces the
line for a named syscall with an argument filter, e.g. bluetoothd's socket
family list; a rule naming a syscall the table lacks fails the start. The
policy is cached in `/run/<name>/` for the boot, so a changed rule needs
`rm /run/<name>/seccomp.policy` (or a reboot) on a running system.

**The Landlock probe.** minijail silently skips Landlock when the kernel lacks
it, so `JAIL_PROBE` names a path inside the jail that the daemon's uid could
write by its file modes but no Landlock rule grants; the start writes it from
inside the jail and fails if the write succeeds.

**When the jail fails.** Each script decides, by what losing the daemon costs:

- **A daemon the user depends on falls back.** `bluetoothd` is how most people reach the
  OSD, `syslogd`/`klogd` are how anyone diagnoses anything, and `wpa_supplicant` is how a
  Wi-Fi-only box stays reachable; a jail that cannot be built, a probe that fails or a self-check that does not match
  starts it with `jail_launch_unjailed`, as root and exactly as stock does, logs the reason
  at `daemon.err` and prints `OK (UNJAILED: <reason>)`. A file on the card
  (`/media/fat/linux/bluetooth.nojail`) does the same on purpose, for a jail that starts but
  breaks a feature. Seccomp and Landlock requirements move with every upstream release, and
  a controller that stops working is a worse outcome than a daemon running as stock does.
- **An opt-in network service fails closed.** `S92transmission` listens on the network
  only because the user created its directory; if its jail cannot be built it does not
  start, and `ci-tests.sh` checks it never calls `jail_launch_unjailed`.

For the same reason a jail asks only for limits that cannot break a working daemon:
deny-list seccomp rules return an errno rather than kill, and the process ceiling is the
pids cgroup with headroom, not `RLIMIT_NPROC` 1 (it counts threads, so a release that adds
one would fail to start).

**Umask.** `jail_init` sets `umask 022`: a root login's umask on this image is
077, and the mount points the script and minijail create must be traversable
by the jail's uid.

## syslogd and klogd

BusyBox's `syslogd` and `klogd` have no option to drop root, so both run through the
helper. syslogd is the one worth it: it parses datagrams from every local process,
including the jailed daemons, which reach `/dev/log` through the host `/dev`, so as root
it was a way from a compromised jail back to root. klogd is cheap once syslogd's layout
exists.

| | syslogd (`S01syslogd`) | klogd (`S02klogd`) |
|---|---|---|
| uid/gid | 8424 `syslog` | 8425 `klog` |
| Capabilities | none | `CAP_SYSLOG`, to read the kernel log with `klogctl()` |
| Seccomp, beyond the shared list | `socket`/`socketpair`: `AF_UNIX` only | the same, and `syslog` only for actions 0, 1, 2, 7 and 8 (close, open, read, console on, console level: BusyBox's own calls), so it cannot read all of the buffer or clear it |
| Namespaces | mount, PID, IPC, **network** | the same |
| Writable | `/run/log` (noexec) | nothing |
| Landlock | rx `/usr`, ro `/etc`, rw `/dev/null`, full `/run/log` | rx `/usr`, ro `/etc` and `/run/log`, rw `/dev/null` |

**The socket.** syslogd binds `/dev/log` after following symlinks, so the scripts make
`/dev/log` on the host a link to `/run/log/log`, in a directory the `syslog` user owns
(0755, so every user can reach the socket); in the jails `/dev/log` is the same link.
`/run/log` is deliberately not `/run/syslogd`, the helper's own root-only state directory,
which holds the seccomp policy and pidfile and must never be writable from the jail.
bluetoothd's jail binds `/run/log` too, since its `/dev/log` is the same link.

**The log files** are `/run/log/messages` and `messages.0` (`syslogd -O`, created 0600
under a 077 umask), and stock's paths, `/tmp/messages` and `/tmp/messages.0` (`/var/log`
is a link to `/tmp`), are root-owned links to them. Reading `/var/log/messages` works as
before; rotation renames inside `/run/log`, so the links stay valid. The jail has no `/tmp`
at all. Before, it needed all of `/tmp` writable for two files, since Landlock grants
directories, not names; a compromised syslogd could then create files under names a root
process opens later (Main writes `/tmp/script` and has agetty run it). The start moves any
regular `/tmp/messages{,.0}` a root syslogd left into `/run/log` (removing the destination
first, so a link planted there is not followed) and re-owns them with `chown -h`. The root
fallback writes through `-O /run/log/messages` too once the links exist, since its
rotation would otherwise rename the links.

**Network namespace.** `/dev/log` is a path, and a path socket works across network
namespaces, so neither daemon needs the network. Remote logging (`syslogd -R`) would; it is
not configured, and `/etc/default/syslogd` is on the read-only root.

Both fall back to the root start when the jail fails (`/media/fat/linux/syslogd.nojail`
and `klogd.nojail` force it), logged at `syslog.err`.

## gpm

Stock starts gpm from `/etc/inittab` as root (`gpm -m /dev/input/mice -t imps2`); the line
now runs `/usr/libexec/mister/gpm-jail start`, which runs the same command in a jail.
Main_MiSTer does not use gpm (it reads `/dev/input/mouseN` itself); its users are `mc`
and ncurses programs such as `dialog` on the console, which is where the OSD runs scripts.

| | gpm (`gpm-jail`) |
|---|---|
| uid/gid | 8427 `gpm` |
| Capabilities | `CAP_SYS_ADMIN` only: every `TIOCLINUX` call from a process whose controlling tty is not that console needs it (`drivers/tty/vt/vt.c` `tioclinux()`), even drawing the pointer. Measured: without it gpm logs "You should be root to run gpm!" |
| Seccomp, beyond the shared list | `socket`/`socketpair`: `AF_UNIX` only; `ioctl` `TIOCSTI` refused, since the capability would otherwise let it type into the console's root shells (the OSD's script terminal logs in as root) |
| Namespaces | mount, PID, IPC, **network** |
| `/dev` | its own: `/dev/gpm` on the host, owned by the jail's uid, holding private `tty0`, `input/mice` and `null` nodes the start makes with `mknod`, the `gpmctl` socket gpm creates, and a `log` link; the host's `/dev/gpmctl` is a link to `gpm/gpmctl` |
| Landlock | rx `/usr`, ro `/etc` and `/run/log`, full `/dev` and `/var/run` (its pidfile, in the jail's own tmpfs) |

The shared deny list is what keeps `CAP_SYS_ADMIN` from being root in disguise: `mount`,
`umount2`, `unshare`, `setns`, `pivot_root`, `bpf`, `perf_event_open`, `keyctl`, `swapon`,
`quotactl`, `fanotify_init`, `open_by_handle_at` and the rest return `EPERM`, and the jail
holds no device but its own three. Measured inside the jail: `mount` and `unshare` fail,
`TIOCSTI` on `tty0` fails while `VT_GETSTATE` works, and there is no `/etc/shadow`, card or
network. What remains is gpm's job: the selection ioctls, including pasting the current
selection (screen text) into the console.

`board/mister/de10nano/patches/gpm/0001` makes this possible: gpm refused any non-zero
euid, and it always forked with `daemon()`, which in a PID namespace would end the
namespace with its first process. With `GPM_FOREGROUND` set it stays in the foreground and
logs to syslog as the daemon does; `-D` was no substitute, as it reports every mouse
movement on stderr. Measured on the rig: a libgpm client on a VT (`disable-paste` under
`openvt`) is served through `/dev/gpmctl`, and a `uinput` mouse's movement is read without
errors. Like the other console and system daemons it falls back to stock's root start when
the jail fails (`/media/fat/linux/gpm.nojail` forces it), logged at `daemon.err`.

## Shared /tmp

`/tmp` is shared by root and, since the daemons left root, by other users. The kernel's
protections against planting files there were all off (kernel defaults);
`/etc/sysctl.d/10-protected-tmp.conf` turns them on, at the values systemd-based
distributions ship:

| Sysctl | Value | Effect |
|---|---|---|
| `fs.protected_symlinks` | 1 | a link in a sticky world-writable directory is followed only by its owner, or when the directory's owner owns it |
| `fs.protected_hardlinks` | 1 | no hard links to files the caller cannot read and write |
| `fs.protected_regular` | 2 | `O_CREAT` does not open an existing file another user owns in a sticky world- or group-writable directory |
| `fs.protected_fifos` | 2 | the same for FIFOs |

Nothing on the image is affected: every file in `/tmp` on the rig, and every `/tmp` path in
Main_MiSTer's source (`CORENAME`, `FILESELECT`, `script`, ...), is root's, and the checks
only fire on another user's file. Measured on the rig: with the values set, root's
`open("/tmp/x", "w")` on a file uid 8424 created fails `EACCES`. `/dev/shm` is 0777 without
the sticky bit and is not covered. `/media/fat/linux/sysctl.conf` is applied after
`sysctl.d/` and can change them back.

## Build options

- `LIBDIR=/usr/lib`, so the compiled-in preload path is `/usr/lib/libminijailpreload.so`.
- Upstream defaults otherwise: `USE_seccomp` is not `no` (no `USE_SECCOMP_SOFTFAIL`), and
  `BLOCK_SYMLINKS_IN_BINDMOUNT_PATHS=no` (a ChromeOS policy; callers validate their own bind
  sources).
- The toolchain goes in through the environment, not the make command line, because the
  Makefile appends `-DPRELOADPATH` to `CPPFLAGS`.
- Upstream's `common.mk` adds `-O2`, `-ggdb3` and `-D_FORTIFY_SOURCE=3` after Buildroot's
  flags, so this package ignores `BR2_OPTIMIZE_*` and `BR2_FORTIFY_SOURCE_*` (Buildroot still
  strips it). Its hard-coded `-Werror` is removed in a post-patch hook, so a newer GCC's
  warnings cannot fail the image build.
- `libminijail.so` is built but not installed, and nothing is staged: `minijail0` and
  `libminijailpreload.so` each link the core objects statically, so no binary would load it.
  A future package that links libminijail should add a staging install with a SONAME.
- About 330 KB stripped for the two files; links only libcap and libc.

Callers should use `-T static` (jail set up in `minijail0`, then `execve`), which works the same
on stock's static musl build and needs no preload library inside the jail.

## Updating

Renovate watches `google/minijail` tags of the form `linux-vYYYY.MM.DD`, and
`renovate-hash-sync.yml` refreshes `minijail.hash`. Upstream publishes no checksums, so the
hash is computed from GitHub's archive tarball, which was checked byte-identical to the tag's
tree at the `linux-v2026.05.18` pin.
