# Network filesystem client parity (P3.10)

## Summary — the corrected picture

Stock's **kernel** supports **both** CIFS and NFS as filesystems (`CONFIG_CIFS=y`,
`CONFIG_NFS_FS=y`), but stock ships **no kernel-mount userland helper for either**
— there is no `mount.cifs` and no `mount.nfs` in the stock image (verified against
`docs/stock-inventory/binaries-needed-full.txt`; neither appears). Stock's network
*share* story is **Samba**: the `smbd` server (so other machines mount the MiSTer)
plus the Samba **client** suite (`smbclient`, `smbget`, `smbtree`, `smbcacls`,
`cifsdd`, …) — i.e. *userspace* SMB access, **not** kernel-mounting remote shares
onto the MiSTer.

Our position, and why it deviates on one point:

- **`cifs-utils` (`mount.cifs`) — kept, but this is BEYOND strict parity.** It was
  enabled back in P2.1; stock never shipped it. We keep it as a **deliberate,
  documented convenience**: community MiSTer storage scripts do use
  `mount -t cifs //host/share /media/...`, and `mount.cifs` is the helper that
  makes that work. Removing it would break those scripts for no benefit, so it
  stays — labelled here as an intentional improvement, not "parity."
- **`nfs-utils` — ADDED as a client (2026-07-21), superseding P3.10's original
  call.** See **[ADR 0022](decisions/0022-nfs-client-userland.md)**. P3.10 declined
  NFS userland and closed by noting that anyone who genuinely needed it "can add
  `nfs-utils` with a one-line defconfig change" — that change has now been made, on
  purpose, to support **running games off a remote host's storage** rather than the
  SD card. Like `mount.cifs`, this is a deliberate **beyond-parity** addition.
  **`rpcbind` is still NOT added**, and neither is the NFS server.
  > *Superseded P3.10 reasoning, preserved:* "Stock shipped no NFS userland and there
  > is no evidence any MiSTer workflow kernel-mounts NFS. Not adding them keeps us
  > closer to stock and leaner."

**On the task's "an nfs mount succeeds" done-criterion:** that criterion originally
assumed stock had NFS userland; it did not, and P3.10 reconciled it away. It is
achievable again for the opposite reason — we now ship `mount.nfs` ourselves. Both
halves, CIFS and NFS, are mountable.

**The kernel never needed changing for either.** The NFS client was already complete
(`NFS_FS/V2/V3/V4/V4_1/V4_2`, `SUNRPC`, `LOCKD_V4`, `RPCSEC_GSS_KRB5`,
`NFS_USE_KERNEL_DNS` — all `=y`); the only thing missing was the `/sbin/mount.nfs`
helper that `util-linux`'s `mount` execs. This is a userland gap that looked like a
kernel gap.

## Kernel-side: stock and ours

| Subsystem | Stock (5.15) | Ours (6.18) | Userland helper shipped? | Note |
|---|---|---|---|---|
| **CIFS** | `CONFIG_CIFS=y` | `CONFIG_CIFS=y` | stock: **no**; ours: **yes** (`mount.cifs`, beyond-parity) | kernel builtin both |
| **NFS** | `CONFIG_NFS_FS=y` | `CONFIG_NFS_FS=y` | stock: **no**; ours: **yes** (`mount.nfs`, beyond-parity, ADR 0022) | kernel builtin both |
| **NFS RPC** | `CONFIG_SUNRPC=y` | `CONFIG_SUNRPC=y` (selected by NFS_FS) | — | required by NFS |
| **NFS server** | `CONFIG_NFSD` **not set** | `CONFIG_NFSD` **not set** | neither | deliberately client-only, both sides |

Both filesystems are built-in (`=y`) in stock and ours, verified in
`docs/kernel-config-deltas.md` §7. **Neither kernel option may be dropped without
breaking parity** — the kernel side is symmetric even though stock's userland
covered neither.

## Userland inventory (from the stock image)

**Stock ships NO kernel-mount helpers** — confirmed absent from
`binaries-needed-full.txt`: `mount.cifs` ✗, `mount.nfs` ✗, `rpcbind` ✗,
`nfs-utils`/`showmount`/`nfsstat` ✗. Stock's SMB userland is Samba's own tools:
`smbclient`, `smbget`, `smbtree`, `smbcacls`, `smbcquotas`, `smbspool`,
`smbstatus`, `smbcontrol`, `smbpasswd`, `cifsdd` — userspace SMB, not `mount -t
cifs`.

**Ours adds two things stock lacked:** `mount.cifs` (via `BR2_PACKAGE_CIFS_UTILS=y`,
cifs-utils 7.4) and, since ADR 0022, `mount.nfs` (via `BR2_PACKAGE_NFS_UTILS=y`,
nfs-utils 2.9.1). The `cifs-utils` smbtools sub-option (`smbinfo`, `smb2-quota`) is
left off — not needed for mounting.

## Defconfig status

```
BR2_PACKAGE_CIFS_UTILS=y                        # mount.cifs — BEYOND parity (stock had none)
BR2_PACKAGE_NFS_UTILS=y                         # mount.nfs  — BEYOND parity (ADR 0022)
BR2_PACKAGE_NFS_UTILS_NFSV4=y                   # NFSv4/4.1/4.2 (+ nfsidmap, blkmapd)
# BR2_PACKAGE_NFS_UTILS_RPC_NFSD is not set     # CLIENT ONLY — upstream default is y
# BR2_PACKAGE_LVM2_STANDARD_INSTALL is not set  # lvm2 is a blkmapd dep; keep dmsetup only
# (no BR2_PACKAGE_RPCBIND)                      # still absent — no NFSv3 NLM locking
```

Kernel (`docs/kernel-config-deltas.md` §7): `CONFIG_CIFS=y`, `CONFIG_NFS_FS=y`,
`CONFIG_SUNRPC=y` — all built-in, matching stock. **ADR 0022 changed no kernel
options**; `CONFIG_NFSD` remains unset on both sides.

## Integration verification

Verified against `output/target` after building `nfs-utils` (2026-07-21):

1. **`mount.cifs` present** — `/usr/sbin/mount.cifs` (or `/sbin/mount.cifs`) exists
   in the built image; `mount -t cifs …` fails with a *network/auth* error, not
   "helper program not found" or "unknown filesystem type."
2. **`mount.nfs` present** — `/usr/sbin/mount.nfs` (setuid, ARM 32-bit EABI5), with
   `mount.nfs4`, `umount.nfs`, `umount.nfs4` symlinks beside it. `/sbin` is a
   usr-merge symlink to `usr/sbin`, so the helper resolves on both paths.
   Client tools present: `showmount`, `nfsstat`, `nfsidmap`, `rpc.idmapd`, `nfsconf`.
3. **NFS *server* absent** — `rpc.nfsd`, `rpc.mountd`, `exportfs`, `/etc/init.d/S60nfs`
   and `rpcbind` all confirmed **not** installed; `CONFIG_NFSD` still unset.
4. **`lvm2` trimmed** — `dmsetup` installed, no `lvm` binary, `libaio` not pulled in.
5. Both `CONFIG_CIFS` and `CONFIG_NFS_FS` remain `=y` in the built kernel.

Items 1–3 and the `CONFIG_NFSD` half of item 5 are **gated in CI**, in
`scripts/ci-tests.sh`'s "P3.10 — Network filesystem client parity" section: the
helpers are asserted present in `rootfs.tar`, `rpc.nfsd`/`rpc.mountd`/`exportfs`/
`S60nfs`/`rpcbind` are asserted absent, and `CONFIG_NFSD` is asserted unset in the
**resolved** `output/build/linux-*/.config` rather than in `configs/linux.config`
(a minimal defconfig, where an absent symbol may still be on, and which a package's
`LINUX_CONFIG_FIXUPS` would not touch anyway). That section previously asserted the
*opposite* — no `mount.nfs`, per P3.10's original call — and failed this branch's
first build by reporting the new feature as a regression; it was inverted, not
deleted, because the client-only shape is the part worth holding onto.

### Size cost (measured, pre-strip upper bound)

| Package | Installed | Note |
|---|---|---|
| `sqlite` | 2.76 MiB | unconditional `nfs-utils` dep; **1.7 MiB of it is the unused `sqlite3` CLI** |
| `nfs-utils` | 1.00 MiB | |
| `lvm2` | 0.64 MiB | trimmed to `dmsetup` + `libdevicemapper` |
| `keyutils` | 0.12 MiB | |
| **Total** | **≈4.5 MiB** | ~1.4% of the 310.7 MiB free margin (`docs/size-budget.md`) |

Figures exclude headers/`.a`/man pages and are taken *before* Buildroot's strip and
finalize steps, so the on-image cost is lower.

## References

- `docs/stock-inventory/binaries-needed-full.txt` — full ELF inventory; `mount.cifs`,
  `mount.nfs`, `rpcbind` all absent; Samba client suite present.
- `docs/stock-inventory/stock-linux.config` — `CONFIG_CIFS=y`, `CONFIG_NFS_FS=y`,
  `CONFIG_SUNRPC=y`.
- `docs/kernel-config-deltas.md` §7 — network filesystems, built-in per stock.
- `work/buildroot/package/cifs-utils/` — cifs-utils 7.4.
- `work/buildroot/package/nfs-utils/` — nfs-utils 2.9.1; note `BR2_PACKAGE_NFS_UTILS_RPC_NFSD`
  is `default y` and its `NFS_UTILS_LINUX_CONFIG_FIXUPS` would `KCONFIG_ENABLE_OPT(CONFIG_NFSD)`.
- `docs/decisions/0022-nfs-client-userland.md` — the client-only NFS decision.

## Decision audit trail

| Date | Finding | Action |
|---|---|---|
| 2026-07-13 | Stock ships neither `mount.cifs` nor `mount.nfs` (Samba client suite only); kernel has CIFS + NFS both `=y` | Keep `cifs-utils` as a **beyond-parity** convenience; do not add NFS userland |
| 2026-07-13 | Task "nfs mount succeeds" assumed stock NFS userland that doesn't exist | Reconcile: NFS stays kernel-only like stock; only the CIFS mount is verified |
| 2026-07-21 | Remote-storage use case (games served from a NAS) needs a real NFS mount; kernel client was already complete, only `mount.nfs` was missing | **Supersede the 2026-07-13 call:** add `nfs-utils` **client-only** ([ADR 0022](decisions/0022-nfs-client-userland.md)); server + `rpcbind` still excluded |
| 2026-07-21 | CIFS/SMB mounting audited on the same pass | **No change needed** — `CONFIG_CIFS=y` + `mount.cifs` already work; `CIFS_XATTR`/`UPCALL`/`DFS_UPCALL` left unset as AD/Kerberos-only features |

## Implications for community tools

`mount -t cifs //host/share /media/...` works (our `mount.cifs` addition), and since
ADR 0022 `mount -t nfs4 host:/export /media/...` works too. Neither is configured for
you: no `/etc/fstab` entries and no automount are added, and there is no NFS *server*.

Two limits worth knowing before filing a bug:

- **Prefer NFSv4.** With no `rpcbind`/`rpc.statd`, NFSv3 has no NLM file locking —
  v3 mounts still read and write, but lock-dependent workloads need `-o nolock`.
  NFSv4 carries locking in the protocol and needs no auxiliary daemon.
- **`sec=sys` only.** No `rpc.gssd`, so Kerberos-authenticated mounts are not
  available even though the kernel has `RPCSEC_GSS_KRB5=y`.
