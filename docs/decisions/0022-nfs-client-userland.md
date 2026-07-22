# ADR 0022 — Ship an NFS **client** userland (`nfs-utils`), server deliberately omitted

**Status:** Accepted (2026-07-21) — decided by @mcfbytes
**Supersedes:** `docs/netfs-parity.md` — the P3.10 line "**`nfs-utils` / `rpcbind` —
NOT added**"
**Impact:** P3.10 (network filesystem parity), P2.7 (size budget)

## Decision

1. **Add `nfs-utils`**, configured as a **client**, so `mount -t nfs` / `-t nfs4`
   works on the running image.
2. **Enable NFSv4/4.1/4.2** (`BR2_PACKAGE_NFS_UTILS_NFSV4=y`).
3. **Do not ship the NFS server** — `rpc.nfsd`, `rpc.mountd`, `exportfs`, the
   `S60nfs` init script, and `rpcbind` all stay out.
4. **Trim `lvm2`** to `dmsetup` + `libdevicemapper`; it is a transitive dependency,
   not a feature we want.
5. **Change nothing in the kernel.** The NFS client was already complete.

## Context — what P3.10 decided, and why this revisits it

P3.10 established that stock ships **no** kernel-mount helper for either network
filesystem: no `mount.cifs`, no `mount.nfs`, no `rpcbind`. It kept `cifs-utils` as a
deliberate beyond-parity convenience (community storage scripts call
`mount -t cifs`), and declined `nfs-utils` on the grounds that stock had no NFS
userland and no known MiSTer workflow needed it. It closed by noting that a user who
genuinely needs NFS "can add `nfs-utils` with a one-line defconfig change."

That reasoning was correct **for a parity milestone**. This ADR makes that change on
purpose, for a use case parity does not speak to: **running games off a remote host's
storage**, so the SD card stops being the capacity ceiling. NFS is the natural
protocol for that on a Linux client, and the asymmetry — we shipped the CIFS helper
but not the NFS one — was hard to defend once someone actually wanted the NFS half.

This follows the project's own framing (ADR 0013): *prove parity, then improve.*
Phase 3 parity is signed off, so a documented, deliberate addition is now exactly the
kind of change the project said it would make afterwards. Parity is a floor, not a
ceiling.

## What was already true — the kernel needed nothing

The interesting finding is that **no kernel work was required**; the request assumed
a gap that did not exist. Verified in the built `output/build/linux-6.18.39/.config`:

| Option | State | Note |
|---|---|---|
| `CONFIG_NFS_FS` | `y` | client core |
| `CONFIG_NFS_V2` / `V3` / `V4` | `y` | `NFS_V3` is `default y`, so it is absent from the *minimal* `linux.config` while still being on — read the resolved `.config`, not the defconfig |
| `CONFIG_NFS_V4_1` / `V4_2` | `y` | |
| `CONFIG_SUNRPC`, `SUNRPC_GSS` | `y` | selected by `NFS_FS` |
| `CONFIG_RPCSEC_GSS_KRB5` | `y` | kernel-side Kerberos already available |
| `CONFIG_LOCKD`, `LOCKD_V4` | `y` | NLM present in-kernel |
| `CONFIG_NFS_USE_KERNEL_DNS`, `DNS_RESOLVER` | `y` | |
| `CONFIG_NFSD` | **not set** | server — stays off, see below |

The single thing standing between this image and a working NFS mount was
**`/sbin/mount.nfs`**. `util-linux`'s `mount` dispatches a network filesystem by
exec'ing `/sbin/mount.<fstype>`, and there is no BusyBox fallback to catch it: this
image disables BusyBox's `mount` applet outright so util-linux wins deterministically
(`# CONFIG_MOUNT is not set` and `# CONFIG_FEATURE_MOUNT_NFS is not set` in the built
`busybox/.config`; the NFS feature is v2/v3-only regardless). So `mount -t nfs` failed
with *"helper program not found"* — a userland gap wearing a kernel gap's costume.

## Client-only, and why that takes an explicit line

`BR2_PACKAGE_NFS_UTILS_RPC_NFSD` is **`default y`** upstream. Simply selecting
`nfs-utils` and moving on would have:

- installed `rpc.nfsd`, `rpc.mountd`, `exportfs`, `fsidd` and an `S60nfs` init script,
- `select`ed `BR2_PACKAGE_RPCBIND` as a runtime dependency, and — the real trap —
- fired `NFS_UTILS_LINUX_CONFIG_FIXUPS`, whose `KCONFIG_ENABLE_OPT(CONFIG_NFSD)`
  would have switched the **in-kernel NFS server on** underneath our deliberate
  `# CONFIG_NFSD is not set`.

That last one is a Buildroot package quietly rewriting the kernel config, and it is
the reason the `# BR2_PACKAGE_NFS_UTILS_RPC_NFSD is not set` line in the defconfig is
load-bearing rather than decorative. A games console has no business exporting
filesystems; the server stays off on both the userland and kernel sides.

## NFSv4 drags in `lvm2` — trimmed rather than swallowed

Buildroot hard-couples `--enable-nfsv4` to `--enable-blkmapd` and therefore to
`lvm2` (+ `keyutils`). `blkmapd` serves the **pNFS block layout**, which no home NAS
uses — but the coupling is not separable without patching the package, and carrying a
local patch to save a few hundred KB is a poor trade against `CONTRIBUTING.md`'s
standing preference for upstream conventions and minimal carried divergence.

The cost is contained instead: `BR2_PACKAGE_LVM2_STANDARD_INSTALL` is turned off, so
only `dmsetup` and `libdevicemapper` are installed rather than the full LVM suite,
and `libaio` is avoided entirely. We ship the library `blkmapd` links against, not a
volume manager.

## Consequences and accepted limitations

- **NFSv3 file locking (NLM) is unavailable.** No `rpcbind`, no `rpc.statd`. v3
  mounts still read and write fine; anything needing `flock`/`fcntl` locks across the
  wire needs `-o nolock`, or — better — **use NFSv4**, whose locking is part of the
  protocol and needs no auxiliary daemon. Recommending v4 is the point of enabling it.
- **`sec=sys` only.** `BR2_PACKAGE_NFS_UTILS_GSS` is off, so no `rpc.gssd` and no
  Kerberos-authenticated mounts. The kernel side (`RPCSEC_GSS_KRB5=y`) is already
  there, so this is a one-option userland reversal if anyone needs it — at the cost of
  pulling in `libkrb5`.
- **`rpc.idmapd` ships but nothing starts it.** No init script is installed in a
  client-only configuration. This is fine for the target use case: with `AUTH_SYS` the
  kernel defaults to passing numeric uid/gid straight through
  (`nfs4_disable_idmapping`), so v4 mounts behave correctly without it. Named-domain
  idmapping (`user@domain`) would need an init script — deliberately deferred.
- **`keyutils` now enters the image**, and `cifs-utils` picks it up automatically
  (`cifs-utils.mk` adds the dependency whenever `BR2_PACKAGE_KEYUTILS=y`), gaining a
  `cifs.upcall` binary. It is inert while `CONFIG_CIFS_UPCALL` stays unset — noted
  here because it is a real cross-package side effect of this ADR, not a silent one.
- **Mount options are not configured for you.** No `/etc/fstab` entries and no
  automount are added; this ADR ships the capability, not a policy.

## CIFS/SMB: examined, no change needed

Mounting a remote SMB/Samba share already works end to end and was verified, not
assumed: `CONFIG_CIFS=y` and `CONFIG_SMBFS=y` in the kernel, `mount.cifs` from
`BR2_PACKAGE_CIFS_UTILS=y` in userland.

The unset CIFS sub-options — `CIFS_XATTR`, `CIFS_UPCALL`, `CIFS_DFS_UPCALL`,
`CIFS_FSCACHE` — were considered and **deliberately left alone**. They serve
extended attributes, Kerberos/SPNEGO, and Active-Directory DFS referrals: none are
needed to mount a home NAS share with a username and password, and enabling them
would be an unjustified divergence from the stock kernel config in a repo whose
kernel deltas are individually audited (`docs/kernel-config-deltas.md`). They remain
available if an AD-domain use case ever appears.

## Alternatives considered

- **NFSv3-only** (skip `BR2_PACKAGE_NFS_UTILS_NFSV4`) — avoids `lvm2` and `keyutils`
  entirely and is the leanest option. Rejected: NFSv4 was specifically what was asked
  for, it is the better protocol for this workload (locking in-protocol, single port,
  no portmapper), and v3 without `statd` is the configuration with the *worse*
  locking story, not the better one.
- **Ship `rpcbind` + `rpc.statd` + a hand-written init script** for full v3 locking —
  rejected for now as more moving parts and another always-running daemon for a
  capability NFSv4 provides without any of it. Revisit if a v3-only server shows up.
- **Patch `nfs-utils` to decouple `--enable-nfsv4` from `blkmapd`** — rejected as
  fighting the framework for a few hundred KB, against this repo's stated preference
  for upstream Buildroot conventions.
