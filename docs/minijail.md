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
`/usr/bin/bluetoothd` is the first script written this way
(`docs/bluetooth-parity.md` §11).

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
`JAIL_PROBE`, optionally `JAIL_SECCOMP_RULES`, `JAIL_STOP_WAIT`,
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
  OSD; a jail that cannot be built, a probe that fails or a self-check that does not match
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
