# ADR 0031 — Secure-by-default network posture: capability parity, closed defaults

**Status:** Provisionally accepted (2026-10-04, @mcfbytes; proposed 2026-09-11). Tier 1
items 5 and 6 and the amendments below are implemented; the 2026-10-08 amendment answers
Q1 ("gate it") with a card state file (absent is stock, a new SD card is hardened) and
does Tier 1 items 1 and 7 in a changed form; the second 2026-10-08 amendment adds FTP
modes to that file (item 3 in `lan`/`off`, item 4 declined). The other Tier 1 items,
Tier 2, Q2 and Q3 are paused, to be picked up later under this acceptance; each still
needs its rig check before it is claimed. The plan that acts on it is
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
  and is CI-asserted (`docs/ssh-ftp-parity.md` §1.3). Since issue #183 it lives at
  `/media/fat/config/authorized_keys`, the location `security_fixes.sh` already used.

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

1. **Key present ⇒ password auth off.** If `/media/fat/config/authorized_keys` (or
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

- **Q1 — the one visible break. ANSWERED 2026-10-08: gate it** on new SD cards only, by a
  card state file rather than by comparing hashes; see the amendment of that date. The original question follows.
  With Tier 1 only, a fresh card still accepts
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

---

## Amendment, 2026-09-21 — `transmission-daemon` (issue #186)

**Status of this amendment:** the disposition below is *implemented*; the rest of this
ADR remains Proposed and nothing in Tier 1-3 is acted on by it. A new listening daemon
arriving while the posture decision is still open is exactly the case where a quiet
`select` would be wrong, so it is dispositioned here instead.

`BR2_PACKAGE_TRANSMISSION` + `_DAEMON` are now in the userspace profile
(`docs/buildroot-config.md` §5.10, `docs/bittorrent.md`). Transmission is a BitTorrent
client: it wants an RPC port, a peer port, and a UPnP/NAT-PMP port mapping, and its
upstream defaults hand it all three.

**What upstream would have shipped.** Read from the source, not from the manual:

- `rpc-bind-address` defaults to **`0.0.0.0`** (`libtransmission/rpc-server.h:67`), not to
  loopback. The `rpc-whitelist` default of `127.0.0.1,::1` (`transmission.h:136`) is a
  *rejection* at the HTTP layer, not an absence — the socket is open on every interface
  and a scan finds it. `daemon/daemon.cc:407` turns RPC on unconditionally for the daemon.
- `rpc-authentication-required` defaults to `false` (`rpc-server.h:61`), which is exactly
  as safe as the bind address it sits behind, and no safer.
- `port-forwarding-enabled` defaults to `true` (`session.h:429`), i.e. the box asks the
  router for a WAN mapping on first run.

**Disposition.** The daemon ships **off**, and when it is on it is closed:

1. **Off by default, opened by a file on the card.** The overlay `S92transmission` exits 0
   unless `/media/fat/linux/transmission` exists. On a fresh image nothing runs and the
   listening-socket set is unchanged from the audit above (`22`, `21`, `123`, `68`). This
   is the `samba.sh` pattern this ADR's Decision section already names, and it adds no new
   mechanism.
2. **RPC bound to `127.0.0.1`**, seeded into `settings.json` on first opt-in. The whitelist
   is kept as well, belt and braces, but the bind is what makes the acceptance item
   "nothing new listens on a non-loopback interface unless the user explicitly enables it"
   true rather than nearly true. Remote control is over SSH, or an SSH port-forward for the
   web UI.
3. **Authentication off, and that is deliberate** — it is safe *only* because of item 2,
   and the two are documented as moving together. Note the reason a password would be poor
   protection here anyway: `settings.json` lives on exFAT, mounted `fmask=0022`, so it is
   world-readable with no modes available — the same constraint that put `/etc/shadow` on
   `ssh.ext4` in Tier 1 item 2 rather than on the card.
4. **Port forwarding off.** A games console should not punch a hole in its owner's router
   because a daemon was switched on. DHT, LPD and PEX all still work without it; what is
   lost is inbound peers, i.e. seeding throughput.
5. **Peer limits cut to 120 global / 30 per torrent** (upstream 200/50). Not a security
   item — the kernel is booted `mem=511M`, so this is resource containment on a box where
   Main_MiSTer is the tenant that matters.
6. **Not root (2026-10-04).** The daemon runs in a minijail as uid 8422 with
   `CAP_DAC_OVERRIDE` only, `no_new_privs`, and a mount view holding its own state and the
   directories the operator grants; the script refuses to start it unjailed
   (`docs/bittorrent.md` §8.1). The socket set below is unchanged — the jail shares the host
   network namespace — but what a compromised daemon can reach is bounded.

**What this does not close, and is accepted.** Once the operator opts in, the daemon adds
**three** listening sockets, and only the first is loopback (measured, not predicted —
`netstat -tuln` on the rig, 2026-09-21):

```
tcp  127.0.0.1:9091   RPC          <- the one this disposition moved off 0.0.0.0
tcp  0.0.0.0:51413    peer port
udp  0.0.0.0:51413    peer port (uTP)
udp  0.0.0.0:6771     Local Peer Discovery, the 239.192.152.143 group
```

The peer port and the LPD socket are **genuine listening sockets on every interface**. That
is not avoidable for a BitTorrent client, it is the feature — LPD in particular is the
requirement that chose this package over rtorrent, and it is a LAN multicast listener by
definition. It is also the first service this image ships
that *wants* unsolicited inbound traffic, which sharpens Tier 1 item 6 and Tier 2: there is
no filter table on the RT kernel to put in front of it, and when nftables lands the default
ruleset will need a hole for this port that is present only while the daemon is opted in.
Recorded here so that lands as a decision rather than as a surprise.

**Regression oracle.** On a fresh image, `netstat -tuln` must be unchanged from the table in
"What the image does today". After `mkdir /media/fat/linux/transmission` and a start, the
only additions must be the four sockets above, and `9091` must be bound to `127.0.0.1` —
never `0.0.0.0:9091`, which is what an unseeded `settings.json` would give. Verified on the
rig 2026-09-21 (`docs/testlogs/2026-09-21-transmission-rig.md` §6).

---

## Amendment, 2026-09-23 — IPv6 (issue #188)

**Status of this amendment:** step 1 below is *implemented*; step 2 waits on a default-deny
ruleset and on the owner (Tier 1 item 6, nftables, landed 2026-10-04).

**The finding.** IPv6 was absent from every kernel this repo builds because stock had it
off, not because anyone decided so. Stock sets `# CONFIG_IPV6 is not set` against a
`default y`. Almost everything else was already v6-ready: BusyBox `FEATURE_IPV6`,
`dhcpcd.conf`'s `slaac private`, `sshd_config` on both families, and the `ip6tables`
userland.

**Why this belongs in this ADR.** Today the board is shielded from the internet largely
by accident, through IPv4 NAT. SLAAC hands out a globally routable address as soon as any
router on the segment advertises a prefix. Turning IPv6 on without a firewall would change
"unreachable because of NAT" into "reachable from the internet" for every item in *What the
image does today*, and users would not know it had happened.

**Decision — dual-stack, never v6-only, in two steps.**

1. **Capable but administratively off (implemented).** `CONFIG_IPV6=y` in both DE10
   kernels and the shared DE25 fragment, plus the legacy `ip6tables` filter set that
   mirrors the v4 one (`docs/kernel-config-deltas.md` D11). `etc/sysctl.d/ipv6.conf` sets
   `disable_ipv6=1` on `all` and `default` and `0` on `lo`, so `::1` works and no other
   interface ever gets an address, including hot-plugged dongles. The opt-in is a card
   file, which is this ADR's existing pattern: `/etc/sysctl.conf` is a symlink to
   `/media/fat/linux/sysctl.conf`, applied by the stock `S02sysctl` after `sysctl.d/`, and
   silently skipped when absent. **FTP stays IPv4-only** (`UseIPv6 off`, unchanged) even
   after an opt-in, because anonymous FTP is writable. sshd, Samba and ntpd follow the
   opt-in. The DE25-Nano has no overlay, so its kernel's IPv6 is live, but that image runs
   no network daemon and does not bring `eth0` up, so nothing is exposed.
2. **Default-on (not implemented).** This needs a default-deny inbound v6 ruleset first.
   The 6.18 kernel has the `ip6tables` filter table from step 1. The RT kernel cannot have
   one: `NETFILTER_XTABLES_LEGACY` `depends on !PREEMPT_RT` upstream, which is the same
   reason it has no v4 filter table. So flipping the default is gated on Tier 1 item 6
   (nftables, whose `inet` family covers both), and on the owner.

**Why dual-stack.** Main_MiSTer's OSD shows only `AF_INET` addresses
(`menu.cpp:680-681`), and `mister.lan` exists only because the router registers the
DHCPv4 hostname. On a v6-only network both would go blank. Dual-stack keeps both working,
and the change stays purely additive. The `menu.cpp` filter is an upstream report, to send
only when the owner approves.

**Regression oracle.** On a fresh image with no card file, `ip -6 addr` shows only
`::1/128` on `lo`, and `netstat -tuln` is unchanged from the table above. CI asserts the
sysctl file, the symlink, `::1` in `/etc/hosts`, `ping6`/`traceroute6`, `UseIPv6 off`, and
`CONFIG_IPV6=y` in both resolved kernel configs. Checked in a private network namespace
on the image's own userland: the stock `S02sysctl` leaves `lo=0 eth0=1 wlan0=1` by default
and `0 0 0` with an opt-in file, including a CRLF-terminated one. **Not yet checked on the
rig.**

---

## Amendment, 2026-10-04 — kernel sandboxing and nftables (Tier 1 items 5 and 6, plus three additions)

**Status of this amendment:** *implemented* (branch `feat/kernel-hardening`; kernel deltas
D13 and D14 in `docs/kernel-config-deltas.md`). Verified by build, `scripts/ci-tests.sh` and
a QEMU boot of the image's own `linux.img` on the new 6.18.55 kernel; **the rig boot this
ADR's Verification section requires is still owed**.

**Decision.** In both DE10 kernels and the shared DE25 fragment:

1. **Tier 1 item 5, as written.** `CONFIG_SECCOMP=y` (with `SECCOMP_FILTER`) and
   `BR2_PACKAGE_OPENSSH_SANDBOX` back to Buildroot's `y`, in one change. OpenSSH's pre-auth
   child now runs seccomp-filtered as the `sshd` user for the first time on this image, and
   dhcpcd's privilege-separated processes, which filter themselves when the kernel allows,
   do too. CI asserts the pair together. No compatibility patch for a kernel without
   seccomp: kernel and rootfs always ship together, so that pairing is not supported.
2. **Added: Landlock** (`SECURITY` + `SECURITY_LANDLOCK`, the only LSM; `INTEGRITY` off). A
   process that does not create a ruleset pays one early-return check per file hook.
3. **Added: the pids cgroup controller**, with cgroup2 mounted at `/sys/fs/cgroup` by
   `/etc/fstab`. Nothing is placed in a child group unless its init script does so.
4. **Added: `CONFIG_JUMP_LABEL`**, a general kernel optimisation rather than a security
   feature, on the 6.18 kernel. Upstream ARM removes it under `PREEMPT_RT` on SMP
   (`arch/arm/Kconfig:87` in 7.2.9) because each branch flip patches kernel text under
   `stop_machine()`, a latency spike RT exists to avoid. So the RT kernel builds without
   it. On the 6.18 kernel the same mechanism pauses both cores, including Main_MiSTer's
   CPU1, once per patched site when a key flips. Outside tracing, the keys a running board
   can flip are few and one-off (first iptables use, a timestamping socket, delay
   accounting; counts in D13). **Release gate:** a rig cyclictest on CPU1 while each of
   those flips must show no stall worth a frame; if it does, this item is reverted on its
   own.

**Not taken, deliberately.**

- **Memory cgroup controller.** It charges every page-cache and slab allocation on the
  box, so Main_MiSTer's ROM and CHD reads pay for one daemon's limit. `oom_score_adj` and
  rlimits stand in.
- **User namespaces.** Unprivileged user namespaces are a large, repeatedly exploited
  attack surface, and nothing here needs them: minijail runs as root and drops to a uid.
- **Tier 3's hardening options** (`HARDENED_USERCOPY`, `INIT_ON_ALLOC_DEFAULT_ON`, ...)
  stay in Tier 3, unchanged.

**Main_MiSTer.** Seccomp and Landlock act only on a process that installs a filter or a
ruleset, and Main installs neither; the pids controller acts only on members of a child
cgroup, and Main is in the root group. None of the three adds work to Main's loop on CPU1.
The kernel grows by about 58 KB compressed. A before/after measurement on the rig (boot
time, cyclictest on both CPUs, a core load) is owed with the rig boot above.

**First user.** `S92transmission` now adds a seccomp deny-list policy, Landlock rules and a
`pids.max` 64 cgroup to its jail, and checks the filter and the cgroup in `/proc` before it
reports success (`docs/bittorrent.md` §8.1).

**Second user (2026-10-08).** `bluetoothd` leaves root: uid 8423 with `CAP_NET_ADMIN` and
`CAP_NET_BIND_SERVICE` only (upstream's own unit's set), the same seccomp, Landlock and
pids pieces. Unlike transmission it falls back to stock's root start when the jail fails,
loudly, since losing it loses the controllers (`docs/bluetooth-parity.md` §11).

**wpa_supplicant (2026-10-08).** One jail per interface, uid 8426, `CAP_NET_ADMIN` and
`CAP_NET_RAW` (a `wpa_cli` patch gives its reply socket to group `wpa`), no network
namespace; falls back to the root start (`docs/wifi-parity.md` §15).

**Tier 1 item 6, as written** (decided with the acceptance above, same branch; kernel
delta D14). `NF_TABLES` with the `inet` family, conntrack, limit, log and reject in every
kernel, and the `nftables` package, beside the legacy tables, which stay. No ruleset
ships. A card file, `/media/fat/linux/nftables.conf`, is loaded by Buildroot's
`S35nftables` when present (`docs/user/faq.md`). The RT motivation lapsed: on 2026-10-04
the owner decided to retire the PREEMPT_RT kernel. nftables is still the base for Tier 2
and for the IPv6 default-on step, because one `inet` table covers both families and
upstream now gates the legacy tables behind `NETFILTER_XTABLES_LEGACY`.

**What this changes elsewhere in the ADR.** Tier 1 items 5 and 6 are done. With the RT
kernel retired, read "both kernels" in the Verification section and in the plan as the
6.18 kernel plus whichever newer kernel line is built beside it. The IPv6 amendment's step
2 now waits only on a default-deny ruleset and on the owner.

---

## Amendment, 2026-10-08 — one card state file; absent is stock, a new SD card is hardened (Q1 answered; Tier 1 items 1 and 7; Tier 2's marker, generalised)

**Status of this amendment:** *implemented* (branch `feat/root-login-opt-in`). Verified on
the image's own userland under qemu-arm and with throwaway `sshd`/`proftpd` instances on
the rig (details in `docs/ssh-ftp-parity.md` §1.4). **A rig boot of a built image is
still owed.**

**The owner's answers** (2026-10-08). Q1: "make the default wide-open configuration (root
login with password `1`) opt-in via script. root can default to ssh only auth or as you see
fit, maybe mandatory ssh key on the exfat partition and no login if it's not there." Then,
the same day, on how it reaches users: "this update needs to hit the sdcard only by
default and regular users will have to keep their existing configuration if they upgrade
to this Buildroot_MiSTer. Perhaps we need a generic security script which stores its
state -- by default if state is absent it can be assumed to be unhardened and follow
stock. sdcard will ship with a hardened state."

**Decision.**

1. **One state file on the card:** `/media/fat/linux/security.conf`, plain `key=value`
   lines. It is **parsed, never sourced**, by one shared reader,
   `/usr/lib/mister/security.sh` (`security_get KEY`), so any later daemon can use the
   same file. The last line for a key wins; `#` starts a comment; values are
   case-insensitive; CRLF is tolerated (the file is edited from Windows PCs).
2. **Absent means stock, everywhere.** No file, no key, or a value that is not allowed
   (with a `WARNING` in the boot log) gives the key's stock value. An existing user who
   updates has no file, so nothing changes: root password login over SSH and FTP exactly
   as before. The image's own `sshd_config` and `proftpd.conf` stay stock for the same
   reason; every hardened behaviour is a command-line addition made by the init script.
3. **The SD card image ships the hardened state.** `fetch-sdcard-payload.sh` stages
   `board/mister/de10nano/fat-payload/linux/security.conf` into the card payload. That is
   the only place it is shipped: `install.sh`, `update_linux_modernization.sh`, the
   Downloader database, the release archive and `linux.img` never carry or write it, and
   CI asserts that the rootfs does not contain it and that the update-path scripts do not
   mention it.
4. **Keys, first value stock:**

   | Key | Values | Not stock means |
   |---|---|---|
   | `ssh_password` | `yes` \| `no` | `S50sshd` adds `-o PermitRootLogin=prohibit-password -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no`. SSH takes a key from `/media/fat/config/authorized_keys` (or `/root/.ssh/authorized_keys`). With no key sshd still runs and prints `NO REMOTE LOGIN`. |
   | `ssh_forwarding` | `stock` \| `limited` | `-o AllowTcpForwarding=local -o "PermitOpen=127.0.0.1:9091 localhost:9091" -o AllowStreamLocalForwarding=no -o X11Forwarding=no`: only Transmission's loopback web UI can be forwarded (Tier 1 item 7, changed; not `no`, because the 2026-09-21 amendment made `ssh -L 9091:…` the way to reach it). |
   | `ftp` | `stock` \| `off` | `S50proftpd` does not start proftpd, so port 21 is closed. `lan` and two more FTP keys: see the second amendment of this date. |

   A new SD card ships `ssh_password=no`, `ssh_forwarding=limited`, `ftp=off` (and, since
   the second amendment, `ftp_drop_caps=yes`).
5. **One tool.** `/usr/sbin/mister-security` (in the image, versioned with the init
   scripts it drives): `status`, `harden`, `stock`, `set KEY VALUE`, and a gamepad dialog
   with the two presets and each key on its own. It validates the value, rewrites the file
   through a same-directory rename, `sync`s, and restarts only the services whose keys
   changed. `Scripts/security.sh` is its launcher on the card, delivered like the other
   Scripts (ADR 0026: install.sh, the sdcard image, and the updater's create-only repair).
   The launcher only runs the tool; it never writes the state file by itself.
6. **The console keeps `root:1`.** Root's shadow entry is not locked. The serial console
   is the recovery path for someone with a keyboard and no key; physical access already
   wins on this board, because the card is removable and the OSD runs any script as root.

**Why a state file, not Q1's hash comparison or one marker.** Gating on "the hash is still
the default" would turn password login back on for anyone who ran `passwd`, and `passwd` is
undone by the next update (Tier 1 item 2 is not done). An earlier draft of this amendment
used one marker file that turned stock *on*, with hardening as the image default; that
changed every upgrader's login on the update that brought it, which the owner rejected.
Keys in one file can grow (Tier 2's `hardened` marker becomes "the hardened preset") and
make "absent" mean the same thing for every key.

**Why invalid values fall back to stock.** Consistency with "absent is stock": the boot log
and `mister-security status` show the warning. The other choice, falling back to the
hardened value, could lock a user out of SSH over a typo. Recorded as an owner question.

**What this supersedes.** Tier 1 item 1 ("key present ⇒ password off", with an
`sshd_allow_password` opt-out) is replaced by `ssh_password`; there is no
`sshd_allow_password` file. Plan task S11 is done in this form, without its dependency on
S2. Tier 2's `/media/fat/linux/hardened` marker becomes the `harden` preset of this file.

**Visible changes, stated for release notes.**

- **Updating:** none. With no `security.conf` everything is stock.
- **New SD card:** SSH is key-only, forwarding is limited and there is no FTP server until
  the user runs **Scripts > security.sh** and picks *Stock* (or changes one key), or puts a
  key on the card for SSH.

**Follow-up, not done here.**

- **A password that survives an update** (Tier 1 item 2, Q3). The natural next step is a
  `mister-security` action that sets a new password and stores the hash on `ssh.ext4`,
  never on exFAT (`fmask=0022`), with the boot-time restore and the `rename()` constraint
  described in item 2.
- Samba keeps its own password database and is untouched; `S91smb` is opt-in already.

**Regression oracle.** With no `security.conf` the three tests in "What the image does
today" all pass, as on stock. With the SD card's file: `ssh root@rig` with password `1` —
refused (`publickey` only); `ftp://root:1@rig/` — connection refused (no server);
anonymous FTP — connection refused. CI (`scripts/ci-tests.sh`, section "ADR 0031 —
security.conf") asserts the stock `sshd_config`, both init scripts, the parser's results
under the target's BusyBox for an absent, the shipped and a malformed file, and runs the
target's own `sshd -T` under qemu-arm in both states.

## Amendment, 2026-10-08 (second) — FTP modes in `security.conf` (Tier 1 items 3 and 4 decided; Tier 3 "ProFTPD unprivileged" in part)

**Status of this amendment:** *implemented* (branch `feat/proftpd-hardening`, stacked on
the amendment above). Verified with a throwaway proftpd built with `mod_cap` on the rig
(details in `docs/ssh-ftp-parity.md` §1.5). **A rig boot of a built image is still owed.**

**The owner's answers** (2026-10-08), on the FTP options prepared for this:

1. No generated or default FTP password: FTP works only after the user allows it through
   the security script.
2. "Drop root after login; the user will have to opt-in via the unhardening script. I'd
   still like to allow regular root FTP since this is how I'm transferring kernels and new
   linux.img files to the rig." Then: "Anyone opening up FTP is choosing to do so -- and we
   can add mod_cap, it's a good option for anyone who actually wants to use it." So the
   capability drop is its own key, not part of stock.
3. No write-deny list on boot-time paths (`linux/`, `Scripts/`, `MiSTer`, `menu.rbf`),
   "not yet anyway".
4. No FTPS / `mod_tls`: SCP and SFTP are the encrypted path.
5. The password hash stays where it is.

And on the chroot: "there is little point though in restricting FTP to /media/fat -- any
attacker would still be able to overwrite the MiSTer binary, which is run as root by
default ... So we might as well open the whole thing up." So there is **no chroot and no
read-deny** on `*.ext4`.

**Decision.** Two more keys and one more `ftp` value, all read by `S50proftpd` and turned
into `-D` defines for the one `proftpd.conf`:

| Key | Values (first is stock) | What it does |
|---|---|---|
| `ftp` | `stock` \| `lan` \| `off` | `stock`: stock's config, with two changes nobody can notice: `ServerIdent on "MiSTer FTP"` and an explicit `MaxLoginAttempts 3` (proftpd's default). `lan`: root with the system password, plus: no `<Anonymous>` block, `<Limit LOGIN>` allows only 127/8, 10/8, 172.16/12, 192.168/16 and 169.254/16 (others are dropped before the banner), `Umask 022`, `PassivePorts 50000 50099`, `TimeoutLogin 60`, `MaxClientsPerHost 10`, `AllowStoreRestart on`, `WtmpLog off`, `SITE CHMOD` denied. `off`: not started. |
| `ftp_allow_any` | `no` \| `yes` | With `ftp=lan`, `yes` drops the `<Limit LOGIN>` address list, for a remote setup (VPN with a non-private range, a port-forward). |
| `ftp_drop_caps` | `no` \| `yes` | Works with `ftp=stock` and `ftp=lan`. `S50proftpd` starts proftpd under `minijail0 -c 0x4cb -B 0x2c` (bounding set CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID, NET_BIND_SERVICE; `SECBIT_NOROOT` locked), the pre-auth processes run as `nobody`, and `mod_cap` (`BR2_PACKAGE_PROFTPD_MOD_CAP=y`) cuts each logged-in session to CHOWN, DAC_OVERRIDE, FOWNER and NET_BIND_SERVICE. `no` sets `CapabilitiesEngine off`, so the server is stock. |

The `harden` preset (and a new SD card) sets `ftp=off` and `ftp_drop_caps=yes`, so a user
who later turns FTP on gets the reduced capabilities unless they also pick `stock`. The
`stock` preset sets `ftp=stock` and `ftp_drop_caps=no`. With no file, all three keys are
stock. There is still no "set a password" step: FTP uses root's system password.

**What the boundaries are, honestly.** For FTP the real boundaries are the credential
(root's password, sent in clear text) and the network scope (`lan`'s address list, the
user's own network). The capability drop is defence in depth only. A logged-in session is
still uid 0 and owns every file on the card, so it can replace `/media/fat/MiSTer`, which
runs as root at the next start; nothing here prevents that, and nothing could while root
FTP is allowed. What the drop removes from a hijacked session (a proftpd bug exploited
after login, or a stolen password used for more than file transfer) is everything that
needs a capability outside the six: loading modules, raw devices (`/dev/mem`, the FPGA
bridge), mount, network administration, ptrace of processes holding more capabilities,
and changing the clock. Because the bounding set is locked with `SECBIT_NOROOT`, a program the session
manages to execute does not get those back either (minijail also sets
`no_new_privs`). Measured on the rig: a uid-0 shell
started inside the same jail has `CapEff 0` and `mount` fails.

**Why not a chroot or a read-deny on `*.ext4`.** The research for this amendment showed a
path-preserving chroot to `/media` works, but write access to the card is root at the
next boot (`MiSTer`, `linux/user-startup.sh`, `Scripts/`), so a chroot keeps out only what
a determined user can reach anyway. Same for the host keys in `ssh.ext4`: anyone who can
write the card can replace the keys' consumer. Both were dropped at the owner's request.

**Why `nobody` and minijail, not `RootRevoke`.** `RootRevoke on` breaks active mode for
root sessions (the data connection comes from port 20). `mod_cap` keeps
CAP_NET_BIND_SERVICE for it; active transfers were checked from a privileged test port.

**Tier 1 items 3 and 4.** Item 3 (anonymous FTP) is gone in `lan` and in `off`; in `stock`
it stays, because stock has it and an upgrader must see no change. Item 4 (chroot) is
declined, for the reason above. Tier 3's "ProFTPD unprivileged" is done in the form above
(pre-auth `nobody`, session capabilities cut), not by remounting the card with a `uid=`.

**Regression oracle.** With no `security.conf`: anonymous login and root:`1` both work
(stock). With the SD card's file: connection refused. With `ftp=lan`: root:`1` works from
the LAN and is dropped from other addresses, anonymous gets `530`, `SITE CHMOD` gets `550`.
CI (`scripts/ci-tests.sh`, section "ADR 0031 — proftpd per security.conf mode") checks the
active directives for every define set, the init script's defines and jail line, that the
target proftpd has `mod_cap.c`, and runs `proftpd -t` for each mode under qemu-arm.
