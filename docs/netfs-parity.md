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
- **`nfs-utils` / `rpcbind` — NOT added.** Stock shipped no NFS userland and there
  is no evidence any MiSTer workflow kernel-mounts NFS. Not adding them keeps us
  closer to stock and leaner. The kernel retains `CONFIG_NFS_FS=y`, so a user who
  genuinely needs NFS can add `nfs-utils` with a one-line defconfig change.

**On the task's "an nfs mount succeeds" done-criterion:** that rested on the
assumption stock had NFS userland; it did not. An NFS mount is *not* achievable
(and not tested) without `mount.nfs`, exactly as on stock. The achievable half —
a CIFS mount via `mount.cifs` — is our beyond-parity addition and is what the
integration build verifies.

## Kernel-side: stock and ours

| Subsystem | Stock (5.15) | Ours (6.18) | Userland helper shipped? | Note |
|---|---|---|---|---|
| **CIFS** | `CONFIG_CIFS=y` | `CONFIG_CIFS=y` | stock: **no**; ours: **yes** (`mount.cifs`, beyond-parity) | kernel builtin both |
| **NFS** | `CONFIG_NFS_FS=y` | `CONFIG_NFS_FS=y` | neither ships one | kernel builtin both |
| **NFS RPC** | `CONFIG_SUNRPC=y` | `CONFIG_SUNRPC=y` (selected by NFS_FS) | — | required by NFS |

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

**Ours adds one thing stock lacked:** `mount.cifs` (via `BR2_PACKAGE_CIFS_UTILS=y`,
cifs-utils 7.4). The `cifs-utils` smbtools sub-option (`smbinfo`, `smb2-quota`) is
left off — not needed for mounting.

## Defconfig status

```
BR2_PACKAGE_CIFS_UTILS=y          # mount.cifs — BEYOND parity (stock had none), kept as convenience
# (no BR2_PACKAGE_NFS_UTILS)      # NFS userland absent — matches stock
# (no BR2_PACKAGE_RPCBIND)        # NFS RPC daemon absent — matches stock
```

Kernel (`docs/kernel-config-deltas.md` §7): `CONFIG_CIFS=y`, `CONFIG_NFS_FS=y`,
`CONFIG_SUNRPC=y` — all built-in, matching stock.

## Integration verification

1. **`mount.cifs` present** — `/usr/sbin/mount.cifs` (or `/sbin/mount.cifs`) exists
   in the built image; `mount -t cifs …` fails with a *network/auth* error, not
   "helper program not found" or "unknown filesystem type."
2. **NFS userland absent (parity)** — no `mount.nfs` in the image; `CONFIG_NFS_FS=y`
   present in the kernel config. (An actual NFS mount is out of scope — no helper,
   same as stock.)
3. Both `CONFIG_CIFS` and `CONFIG_NFS_FS` remain `=y` in the built kernel.

## References

- `docs/stock-inventory/binaries-needed-full.txt` — full ELF inventory; `mount.cifs`,
  `mount.nfs`, `rpcbind` all absent; Samba client suite present.
- `docs/stock-inventory/stock-linux.config` — `CONFIG_CIFS=y`, `CONFIG_NFS_FS=y`,
  `CONFIG_SUNRPC=y`.
- `docs/kernel-config-deltas.md` §7 — network filesystems, built-in per stock.
- `work/buildroot/package/cifs-utils/` — cifs-utils 7.4.

## Decision audit trail

| Date | Finding | Action |
|---|---|---|
| 2026-07-13 | Stock ships neither `mount.cifs` nor `mount.nfs` (Samba client suite only); kernel has CIFS + NFS both `=y` | Keep `cifs-utils` as a **beyond-parity** convenience; do not add NFS userland |
| 2026-07-13 | Task "nfs mount succeeds" assumed stock NFS userland that doesn't exist | Reconcile: NFS stays kernel-only like stock; only the CIFS mount is verified |

## Implications for community tools

`mount -t cifs //host/share /media/...` works (our `mount.cifs` addition). NFS
mount scripts do **not** work out of the box — exactly as on stock, which also
lacked NFS userland. A user needing NFS adds `nfs-utils` themselves. This is
intentional, not a regression.
