# minijail

`package/minijail` ships Google's [minijail](https://google.github.io/minijail/):
`/usr/bin/minijail0` and `/usr/lib/libminijailpreload.so`. It is in
the `mister-userspace` profile, so the DE10 image carries it. Its first users are the jailed
`S92transmission` and mistarr, whose design is mistarr's `docs/NONROOT-PLAN.md`.

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
