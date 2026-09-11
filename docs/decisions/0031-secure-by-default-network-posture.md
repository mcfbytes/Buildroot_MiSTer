# ADR 0031 — Secure-by-default network posture: capability parity, closed defaults

**Status:** Proposed (2026-09-11) — for @mcfbytes to accept, amend, or reject. Nothing in
the build changes until accepted; the plan that acts on it is
[`docs/security-hardening-plan.md`](../security-hardening-plan.md).
**Supersedes:** the "keep parity, note the risk in the FAQ rather than silently hardening"
posture recorded against P3.7 in `TASKS.md`, and the same sentiment in
`board/mister/de10nano/post-build.sh` ("hardening ... is the beyond-parity security pass
tracked separately, to be done AFTER parity is proven"). Parity is proven; this is that pass.
**Related:** [ADR 0015](0015-per-device-ssh-host-keys.md) (the `ssh.ext4` persistence
volume this design reuses), [ADR 0011](0011-resolv-conf-buildroot-default.md) (read-only
root and the login-time remount), [ADR 0021](0021-rt-kernel-first-class-ci.md) (the RT
kernel variant, where one finding below is a regression), [ADR 0025](0025-update-linux-kill-switch-and-private-updater.md)
(the update channel's trust model), [`docs/ssh-ftp-parity.md`](../ssh-ftp-parity.md)
(the parity audit whose findings this ADR acts on).

---

## Context

Stock MiSTer was never secure by default, and did not need to be: it runs fine with no
network at all, and most boards sit on a home LAN. Two things have changed. This image is
now good enough that people put it in venues, on WiFi the operator does not control, and
some of those operators would like a box that is safe even if it ends up reachable from the
internet. And this image, unlike stock, is *rebuilt from source with a maintained kernel and
package set*, so it is the one place in the ecosystem where a better default can actually be
shipped.

### What the image does today

Everything below was verified on 2026-09-11 against the HIL rig (beta `260904`, RT kernel
7.2.3, `192.168.0.160`) or against the resolved build configs under `output/` and
`output-rt/`, not read from documentation.

**Listening sockets** (`netstat -tuln` on the rig): `tcp/22` sshd, `tcp/21` proftpd,
`udp/123` ntpd, `udp/68` dhcpcd. Nothing else. Samba is opt-in (`S91smb` exits unless
`/media/fat/linux/samba.sh` exists) and was not running.

**What an attacker on the same network gets, tested from the build host:**

| Test | Result |
|---|---|
| `ssh root@rig`, password `1` | login accepted |
| `ftp://root:1@rig/` | `230 User root logged in` |
| `ftp://anonymous:x@rig/` | `230 Anonymous access granted, restrictions apply` |

- The root hash is pinned by `post-build.sh` and is identical on every device. It lives in
  `/etc/shadow` **inside `linux.img`**, so an update resets any changed password back to
  `1`. The FAQ currently tells people to "log in and run `passwd`" without saying that this
  is undone by the next update. The operators who did the right thing are the ones being
  silently reset.
- FTP is cleartext. On venue WiFi the root password is in the first packet of every FTP
  session. It is also guessable in one attempt.
- `proftpd.conf` runs the daemon as root with `DefaultRoot /`, so an FTP login is a root
  shell over the whole filesystem, not just the card. The `<Anonymous>` block is live
  (the `ftp` user and `/home/ftp` exist) and grants `<Limit WRITE> AllowAll` into a
  directory that lives inside the root filesystem image.
- **Any write to the card is root code execution at next boot.** `/etc/inittab` runs
  `/media/fat/MiSTer`; `S99user` runs `/media/fat/linux/user-startup.sh`; `S91smb` runs
  `/media/fat/linux/samba.sh`; `Scripts/*.sh` run from the OSD. Hardening sshd while
  leaving FTP at root:`1` therefore changes nothing. The two must move together.
- `sshd -T`: `PermitRootLogin yes`, `PasswordAuthentication yes`,
  `KbdInteractiveAuthentication yes`, `AllowTcpForwarding yes`, `PermitOpen any`,
  `MaxAuthTries 6`, `LoginGraceTime 120`. A box with a known password is a TCP pivot into
  the venue network.
- **A firewall is impossible on the RT kernel.** The image ships `iptables` (legacy), but on
  the rig `iptables -S` fails: `can't initialize iptables table 'filter': Table does not
  exist`. The resolved 7.2.4 RT config contains no `CONFIG_IP_NF_FILTER` symbol at all;
  the 6.18.50 config still has it. Neither kernel has `CONFIG_NF_TABLES`. This is a
  regression on the RT channel independent of any posture decision.
- `CONFIG_SECCOMP` is off in both kernels (stock parity), which is why
  `BR2_PACKAGE_OPENSSH_SANDBOX` had to be disabled (see `docs/ssh-ftp-parity.md`, header
  warning). Turning it on is invisible to MiSTer and re-arms the OpenSSH pre-auth sandbox.
- Kernel hardening that *is* on: `STRICT_KERNEL_RWX`, `STRICT_MODULE_RWX`,
  `STACKPROTECTOR`. Off: `HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `SLAB_FREELIST_*`,
  `STRICT_DEVMEM`, `SECURITY` (no LSM), `MODULE_SIG`. `DEVMEM=y` is required: Main_MiSTer
  maps the FPGA bridges through `/dev/mem`.

**What is already right, and must not regress:**

- Userspace hardening: `BR2_PIC_PIE`, `BR2_RELRO_FULL`, `BR2_SSP_STRONG`,
  `BR2_FORTIFY_SOURCE_1`. `dhcpcd` runs with privsep. `ntpd` has `restrict default
  nomodify nopeer noquery limited kod`, so it is not an amplifier.
- Per-device SSH host keys (ADR 0015). `PermitEmptyPasswords no`. OpenSSH 10.x
  `PerSourcePenalties` is on by default.
- The updater fetches over HTTPS, checks MD5 and size (the Downloader's contract), and
  **deliberately never falls back to `--insecure`**
  (`update_linux_modernization.sh`, `probe_curl_ssl`). There are no signatures anywhere in
  the MiSTer update ecosystem; that is a parity fact, not a gap this project can close
  alone.
- `authorized_keys` on the FAT partition already survives updates, satisfies `StrictModes`,
  and is CI-asserted (`docs/ssh-ftp-parity.md` §1.3).

### The tension

"Safe on the public internet" and "root:`1` over cleartext FTP by default" are mutually
exclusive. No amount of sshd tuning resolves that, because FTP write access to the card is
root at next boot. So the real decision is not *which knobs* but *what "parity" means*.

## Decision

**Parity of capability, not parity of defaults.** Every stock feature stays reachable: root
SSH, FTP, Samba, `user-startup.sh`, Scripts. But the image ships *closed* where being open
requires a shared secret, and the operator opens it with a file on the card. That is the
pattern the project already uses for Samba (`samba.sh`), boot hooks (`user-startup.sh`),
and SSH keys (`authorized_keys`), so it adds no new mechanism, only new files.

Concretely, in three tiers. Tier 1 is intended to be accepted with this ADR; Tier 2 needs
the owner's answer to Q1 below; Tier 3 is recorded so it is not re-discovered.

### Tier 1 — invisible to a stock-style user

1. **Key present ⇒ password auth off.** If `/media/fat/linux/authorized_keys` (or
   `/root/.ssh/authorized_keys`) is non-empty at sshd start, `S50sshd` passes
   `-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no`. Implemented in the
   init script, not `sshd_config`, because a `Match` block cannot test for a file. Lockout
   is recoverable by pulling the card, which is the same recovery path as every other
   card-file misconfiguration. Opt-out: an empty marker file
   `/media/fat/linux/sshd_allow_password`, for people who use a key from one machine and a
   password from another.
2. **Persist `/etc/shadow` across updates.** The persisted copy lives on the ADR 0015
   `ssh.ext4` volume, **not** on exFAT: the initramfs mounts the card `fmask=0022`, so a
   file there is world-readable, and a hash must not be. `ssh.ext4` is machine-written
   state with real permissions, which is exactly its design brief. Design constraint to
   respect: `passwd` (BusyBox and PAM's `unix_update` alike) writes a temp file and
   `rename()`s it into place. A symlink is silently replaced by a real file once `/` is
   remounted rw at login; a file bind-mount makes the rename fail `EBUSY`. So this ships
   with a `mister-passwd` wrapper that updates both copies, and a boot-time restore. The
   plain `passwd` failing loudly under a bind mount is the *preferred* failure mode over
   the symlink's silent one. Needs a rig test before it is claimed.
3. **Remove anonymous FTP.** Delete the `<Anonymous>` block; nothing in the MiSTer world
   uses it, and it is writable.
4. **Chroot FTP to `/media`.** `DefaultRoot /media` keeps every real use (the card at
   `/media/fat`, sticks at `/media/usb0-7`) and stops an FTP session being a
   whole-filesystem root shell. ProFTPD still runs as root, because the FAT mount has no
   `uid=` option and only root can write the card; dropping its privileges is Tier 3.
5. **`CONFIG_SECCOMP=y` in both kernels; re-enable `BR2_PACKAGE_OPENSSH_SANDBOX`.**
   Both must land in the same change, on both boards, or the fragment warning in
   `de25nano.fragment` applies in reverse.
6. **nftables in both kernels (`CONFIG_NF_TABLES` + the `nft` family) and the
   `nftables` package.** Fixes the RT regression and is the prerequisite for Tier 2. The
   default ruleset is permissive; shipping nftables is not the same as shipping a policy.
7. **`AllowTcpForwarding no`, `X11Forwarding no` explicit.** Nobody tunnels through a
   MiSTer; a compromised one should not be a pivot.
8. **Fix the FAQ now**: say that `passwd` does not survive an update until item 2 lands.

### Tier 2 — the `hardened` profile, opt-in by one card file

`/media/fat/linux/hardened` (empty marker) switches, at boot:

- FTP off entirely (SFTP over the existing `Subsystem sftp` is the replacement; every
  common client speaks it).
- sshd key-only, regardless of item 1's heuristic.
- Samba, if enabled, requires a valid user (`map to guest = never`, `valid users = root`).
- nftables: default drop inbound; allow established, `22/tcp` rate-limited, ICMP echo,
  DHCP client and NTP replies. Everything else including `21`, `137-139/445` unless the
  corresponding service is on.

Also in Tier 2, and independent of the marker: **drop inbound from non-RFC1918 sources by
default.** A box that ends up with a public address, or behind a stray port-forward, is
then safe with zero cost on any LAN. This does **not** help the venue-WiFi case, which is
still RFC1918; that is what the marker is for.

### Tier 3 — recorded, not scheduled

- Kernel: `HARDENED_USERCOPY`, `SLAB_FREELIST_RANDOM`/`HARDENED`, `FORTIFY_SOURCE`,
  `INIT_ON_ALLOC_DEFAULT_ON`, `STRICT_DEVMEM`. Each needs a rig boot and a latency check
  on the RT channel, because Main_MiSTer's `/dev/mem` bridge mapping and the SPI/UIO
  paths are exactly what these touch. Not free, not obviously safe.
- ProFTPD unprivileged: requires the card mounted with a `uid=`/`gid=` for a non-root
  service user, which ripples into `StrictModes` (§1.3 of the parity doc), Main_MiSTer's
  own writes, and the exFAT reformat installer (ADR 0020).
- Signed release archives (minisign) verified by `update_linux_modernization.sh` before
  the Downloader is invoked. Ecosystem-level; needs a design because the Downloader
  fetches and applies in one run.
- Re-audit ProFTPD at 1.3.9d. `docs/ssh-ftp-parity.md` still marks it unaudited since
  1.3.8d.
- Bluetooth `JustWorksRepairing = always` / `Privacy = off` (stock parity, controller
  convenience). Leave unless a venue reports a problem.

## Open questions for the owner

- **Q1 — the one visible break.** With Tier 1 only, a fresh card still accepts
  root:`1` over FTP and SSH, because that is what a first-time user expects. The
  alternative is to also gate *password* logins on the password having been changed from
  the default (compare root's hash against the well-known `$5$MiSTer618$...` value at
  boot). That makes the image safe out of the box at the cost of the stock first-run
  experience: a new user must drop `authorized_keys` on the card or set a password on the
  serial console before any remote login works. The FAQ already documents the
  `authorized_keys` route as the *easier* one. **Recommendation: gate it.** But it is a
  product decision, and this ADR does not make it.
- **Q2 — should the RFC1918 inbound rule be on by default (Tier 2, second half)?**
  Recommendation: yes, it has no LAN cost.
- **Q3 — `mister-passwd` vs. teaching plain `passwd` to persist.** The wrapper is honest
  and small; a PAM-level hook would be cleaner but is more machinery on a read-only root.

## Consequences

- One new persisted file on `ssh.ext4` and up to three new marker files on the card:
  `sshd_allow_password`, `hardened`, and the existing `authorized_keys`. All documented in
  one FAQ entry, "Locking down a MiSTer on a network you don't trust".
- `scripts/ci-tests.sh` grows assertions for every Tier 1 item so that none of them can
  silently regress the way `OPENSSH_SANDBOX` did (the shipped `proftpd.conf` has no
  `<Anonymous>` block, `DefaultRoot` is `/media`, `sshd_config` sets forwarding off,
  the kernel has `CONFIG_SECCOMP=y` and `CONFIG_NF_TABLES`, the `nftables` binary is in
  the rootfs).
- The RT channel gets a working firewall for the first time.
- Both parity docs (`ssh-ftp-parity.md`, `samba-parity.md`) gain a "deliberate
  divergences" section listing each change against stock, so the divergence stays
  reviewable rather than becoming folklore.
- `TASKS.md` P3.7's "note the risk rather than silently hardening" is superseded; the
  hardening is not silent, it is this ADR.

## Verification

Each Tier 1 item is claimed only after the corresponding check in
[`docs/security-hardening-plan.md`](../security-hardening-plan.md) passes on the rig, on
**both** the 6.18 and RT kernels. The three tests in the table above are the regression
oracle: after Tier 1 with Q1 answered "gate", all three must fail on a fresh card; with
Q1 answered "keep", the anonymous row must fail and the other two must still pass.
