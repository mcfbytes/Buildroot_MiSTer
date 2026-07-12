# ADR 0015 — Per-device SSH host keys (a deliberate, security-improving divergence from stock)

**Status:** Accepted (2026-07-12) — decided by @mcfbytes
**Impact:** P2.3 (overlay), P2.4 (writable-path audit), P2.5 (reproducible image),
and **every downstream user of this image.** This is the most user-visible
behavioural change in the rootfs.
**Supersedes:** nothing; adds to the withdrawn-A8 / read-only-root story
([ADR 0011](0011-resolv-conf-buildroot-default.md), [A15]).

## The problem, stated plainly

**Every stock MiSTer on Earth ships the *same* SSH host keys.**

Verified: the stock `linux.img` bakes `/etc/ssh/ssh_host_{rsa,ecdsa,ed25519,dsa}_key`
into the image (dated 2016-12-31), on a real read-only `/`. `S50sshd` runs
`ssh-keygen -A`, which is a **no-op** because the keys already exist. Those keys
ship inside the public `release_YYYYMMDD.7z` download. So the private host keys of
every MiSTer are public, identical, and unchangeable.

Consequences for a user: trivial SSH server impersonation / MITM on any network
where an attacker can redirect `mister.lan`, and no host-key warning to tip the
user off (every box presents the same key, so it always "matches").

## Why we cannot just copy stock

- **Committing private keys to a public git repo** is unacceptable, and would make
  *our* users share keys too — the same bug with a new coat of paint.
- **Generating keys at build time** breaks P2.5's byte-identical-build requirement
  (`BR2_REPRODUCIBLE`) and still bakes *one* key set into an image many people flash.
- **A read-only `/`** means `ssh-keygen -A` cannot write to `/etc/ssh` at boot. So
  "just generate on first boot" needs a *writable, persistent* home for the keys.

## The decision

**Generate SSH host keys on first boot, unique per device, and persist them to an
ext4 image on the FAT data partition — mirroring stock's OWN Bluetooth mechanism.**

Stock already solved exactly this shape of problem: Bluetooth pairing keys also
need real Unix permissions on a permission-less FAT card, so stock's
`/bin/bluetoothd` wrapper does:

```sh
BTIMG=/media/fat/linux/bluetooth
if [ ! -f $BTIMG ]; then dd if=/dev/zero of=$BTIMG bs=64k count=32; mkfs.ext4 $BTIMG; fi
mount -o sync,dirsync,nodiratime,noatime $BTIMG /var/lib/bluetooth
```

We do the same for SSH. An `S49sshd`-style overlay (before `S50sshd`) will:

1. Create `/media/fat/linux/ssh.ext4` (a small ext4 image) if absent — **exactly
   the `dd` + `mkfs.ext4` idiom stock uses for Bluetooth**, so it is not a new
   mechanism, just a second consumer of a proven one.
2. `mount` it at `/etc/ssh_keys` (a writable dir; the read-only `/` only needs the
   empty mount point to preexist in the image — see [A15]/P2.3).
3. On first boot only, `ssh-keygen -A` into it (keys land with `0600`, because
   ext4 has real permissions — the whole point).
4. `sshd_config` points `HostKey` at `/etc/ssh_keys/ssh_host_*`.

### On CRNG / entropy — checked, not assumed

`ssh-keygen` draws from `getrandom()`, which **blocks until the CRNG is seeded**;
it cannot emit a low-entropy key. So even the worst case is safe-but-slow, never
weak. And it is not even slow here: measured on our 6.18.33 kernel on real
hardware, `random: crng init done` fires at **~2.17 s**, long before `S50sshd`
runs. (There is a `/dev/hwrng` node but no backend on the Cyclone V; the seed comes
from interrupt/jitter entropy, which is sufficient and already done by boot.) No
`rngd`/`haveged` needed. If a future board proved slower, the fix is to gate key
generation on `getrandom()` readiness, not to pre-seed from anything non-blocking.

## Why this is strictly better than stock

| | Stock | Ours |
|---|---|---|
| Host keys | one set, shared by all devices, **public** | **unique per device**, generated locally |
| In the image / git | private keys baked in | **nothing secret** — image has no keys |
| Reproducible build | n/a (keys make it non-reproducible anyway) | **preserved** — keys are runtime state, not build output |
| Survives image update | keys are in the image, so they change with it | keys live on `/media/fat`, **survive re-flash** |
| exFAT permission trap | n/a | avoided — keys live on ext4, `sshd` accepts `0600` |

## ⚠ User-visible consequence — MUST be in the release notes (P4.8/P4.9)

**On first boot of this image, the SSH host key CHANGES** (from stock's shared key
to a fresh per-device key). Any existing SSH client that has connected to this
MiSTer before will refuse to connect with a **host-key-mismatch** warning
(`REMOTE HOST IDENTIFICATION HAS CHANGED`). The user must run **once**:

```sh
ssh-keygen -R mister.lan     # and/or -R <the MiSTer's IP>
```

This is expected and correct — it is the client noticing, accurately, that the
server's identity changed. It is a one-time action per client. Document it
prominently; it will otherwise generate "SSH is broken after updating" reports.

## Consequences for other tasks

- **P2.3** implements the `S49sshd` overlay + the `sshd_config` HostKey paths + the
  empty `/etc/ssh_keys` mount point in the image.
- **P2.4** lists `/etc/ssh_keys` (→ `/media/fat/linux/ssh.ext4`) in
  `docs/writable-paths.md`, alongside the Bluetooth precedent it copies.
- **P2.5** must confirm the image contains **no** `ssh_host_*` private keys (a
  reproducible-build *and* a security assertion — add it to the check).
