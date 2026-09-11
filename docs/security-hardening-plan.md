# Security hardening plan (ADR 0031)

**Decision:** [ADR 0031](decisions/0031-secure-by-default-network-posture.md) — Proposed,
not yet accepted. **Nothing here is scheduled until it is.** This file is the task list
that acts on the ADR, in the same shape as `de25-nano-tasks.md`: one task per change,
each with a "done when" that is a check on the rig or in CI, not a claim.

**Ground truth as of 2026-09-11** is the "What the image does today" section of the ADR.
Re-run its three login tests before starting; if any result differs, update the ADR first.

**Standing rules for every task below**

- Every change lands on **both** the 6.18 and the RT kernel and on **both** boards where
  the symbol exists. The RT channel is where the firewall regression was found; do not
  test on one and claim the other.
- Every change that touches a shipped config file gets a `scripts/ci-tests.sh` assertion
  on the **shipped** artifact (`rootfs.tar`, the resolved kernel `.config`), not on the
  overlay source. This is the lesson of `BR2_PACKAGE_OPENSSH_SANDBOX`.
- Every change adds a row to the "deliberate divergences from stock" table in the relevant
  parity doc (`ssh-ftp-parity.md`, `samba-parity.md`, `kernel-config-deltas.md`).
- Rig verification uses the key in `mister_rig_ed25519`; remember OpenSSH's
  `PerSourcePenalties` will ban the host after a few failed password attempts, so run the
  negative tests **last** and from a fresh connection.
- The `golden.sha256` line for every affected stack is regenerated in the same PR.

---

## Tier 1 — invisible to a stock-style user

### S1 — Key present ⇒ password auth off — Size S — Depends: none

`S50sshd`: before starting sshd, if `/media/fat/linux/authorized_keys` or
`/root/.ssh/authorized_keys` exists and contains at least one non-comment line, and
`/media/fat/linux/sshd_allow_password` does **not** exist, append
`-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no` to the sshd invocation.
Log one line to the console either way so the boot log says which mode was chosen.

**Done when:**
- Rig with `authorized_keys` present: `ssh -o PreferredAuthentications=password root@rig`
  is refused with "Permission denied (publickey)"; key login works.
- Rig with the file removed: password login works as before.
- Rig with both `authorized_keys` and `sshd_allow_password`: password login works.
- `sshd -T` on the rig reports the chosen mode.
- CI: a shell-level test of the decision function (extract it into a sourced helper so
  `ci-tests.sh` can call it against a temp dir).
- FAQ entry updated; `ssh-ftp-parity.md` divergence row added.

### S2 — Persist `/etc/shadow` on `ssh.ext4` — Size M — Depends: none (S1 independent)

Design per ADR 0031 Tier 1 item 2. Suggested shape, to be validated on the rig:

1. `S50sshd` already mounts `ssh.ext4` at `/etc/ssh_keys`. Rename nothing; add a
   `shadow` file there. (Renaming the volume to `persist.ext4` is tempting but breaks
   every existing card; do not.)
2. Boot restore, in the same script after the mount succeeds: if
   `/etc/ssh_keys/shadow` exists and differs from `/etc/shadow`, `mount -o remount,rw /`,
   copy it in with `0640 root:root`, `mount -o remount,ro /`. Remount only when it
   differs so a normal boot never writes the rootfs image.
3. `/usr/sbin/mister-passwd`: runs `passwd "$@"`, then copies `/etc/shadow` to
   `/etc/ssh_keys/shadow` with the same mode. Print where it saved and why.
4. Plain `passwd` still works for the running image and is lost on update, as today.
   Decide (Q3) whether to also symlink `passwd` → `mister-passwd`; the plan assumes not.

If the tmpfs fallback in `S50sshd` fires (no `ssh.ext4` mount), skip the restore and warn,
exactly like host keys.

**Done when:**
- On the rig: `mister-passwd`, set a new password, `ssh` with it works; reflash the same
  image; the new password still works; `1` is refused.
- The rootfs image is byte-identical before and after a boot where the persisted hash
  already matches (`md5sum /media/fat/linux/linux.img` from the initramfs or another
  host) — proves the remount path did not fire.
- `ls -l /etc/shadow` is `0640` on the rig after restore.
- `check-linux-img.sh` still asserts no private key material in the image.
- FAQ: replace "log in and run `passwd`" with `mister-passwd` and say why.

### S3 — Remove anonymous FTP — Size XS — Depends: none

Delete the `<Anonymous ~ftp>` block from `proftpd.conf`. Leave the `ftp` system user
(Buildroot creates it; removing it is a different diff with no benefit).

**Done when:** `curl ftp://anonymous:x@rig/` returns `530`; CI asserts the shipped
`proftpd.conf` contains no `<Anonymous`.

### S4 — Chroot FTP to `/media` — Size XS — Depends: S3

`DefaultRoot /media`. Verify that `/media/fat` and `/media/usb0` are both reachable and
writable over FTP as root, and that `/etc` is not.

**Done when:** `curl ftp://root:PW@rig/fat/` lists the card; `ftp://root:PW@rig/../etc/`
fails; CI asserts `^DefaultRoot[[:space:]]+/media$`.

### S5 — `CONFIG_SECCOMP=y` + OpenSSH sandbox — Size S — Depends: none

Both `linux.config` files (de10nano, de25nano) and the RT fragment if it overrides;
`BR2_PACKAGE_OPENSSH_SANDBOX=y` in `de10nano-image.fragment`; delete the "must stay off"
warnings in both fragments and in `ssh-ftp-parity.md` and replace them with the reason
it is now on. This is one PR, both symbols, or it ships a listening-but-dead sshd.

**Done when:** rig boots both kernels; `ssh` works; `dmesg`/`logread` shows no sandbox
failure; `sshd -T` unchanged; `zcat /proc/config.gz | grep SECCOMP=y`; CI asserts both
the kernel symbol and the Buildroot symbol are set together (fail if only one is).

### S6 — nftables in both kernels + `nftables` package — Size S — Depends: none

Kernel: `CONFIG_NF_TABLES`, `NFT_CT`, `NFT_LIMIT`, `NFT_REJECT`, `NF_TABLES_INET`,
`NFT_COMPAT` optional. Buildroot: `BR2_PACKAGE_NFTABLES=y`. Keep `iptables` for now;
drop it in a later cleanup once nothing in `Scripts/` or community scripts is found to
call it. Ship **no ruleset** in this task; a permissive `nft` install is the deliverable.

**Done when:** on the rig, both kernels: `nft list ruleset` succeeds (empty), and
`nft add table inet t` / `nft delete table inet t` round-trips. CI asserts
`CONFIG_NF_TABLES=y` in both resolved kernel configs and `usr/sbin/nft` in `rootfs.tar`.
`kernel-config-deltas.md` gains the rows. Note the RT-channel regression as fixed.

### S7 — sshd: forwarding off — Size XS — Depends: none

`AllowTcpForwarding no`, `X11Forwarding no` explicit in `sshd_config`. Keep
`PermitUserEnvironment yes` (MiSTer scripts rely on it, per the parity doc).

**Done when:** `ssh -L 8080:localhost:80 root@rig` reports "administratively
prohibited"; `sshd -T | grep allowtcpforwarding` says `no`; CI asserts the line.

### S8 — FAQ correction — Size XS — Depends: none — **done in the ADR PR**

The FAQ told users to run `passwd` without saying an update reverts it. Corrected in the
same PR as ADR 0031 so the doc is honest even if nothing else lands.

---

## Tier 2 — the `hardened` profile (needs Q1/Q2 answered)

### S9 — RFC1918-only inbound by default — Size S — Depends: S6

New `S35nftables` (before network): `inet filter input` with `ct state established,
related accept`, `iif lo accept`, accept from `10/8`, `172.16/12`, `192.168/16`,
`169.254/16`, ICMP echo, DHCP replies, NTP replies; default `drop`. IPv6 is off in the
kernel today, so no v6 rules yet; add them the day `CONFIG_IPV6` turns on (CI assertion
tying the two).

**Done when:** from the LAN everything works unchanged; from a non-RFC1918 source
(simulate with a second interface or a `nft` counter) inbound `22` is dropped. CI
asserts the ruleset file is present and `nft -c -f` parses it in the QEMU leg.

### S10 — `/media/fat/linux/hardened` marker — Size M — Depends: S1, S6, S9

At boot, if the marker exists: `S50proftpd` exits 0 without starting; `S50sshd` forces
key-only regardless of S1; `S91smb` adds `map to guest = never` and `valid users = root`
via an include; `S35nftables` loads the strict set (default drop inbound, `22/tcp`
rate-limited with `limit rate 6/minute`, ICMP echo, DHCP/NTP replies).

**Done when:** all four behaviours verified on the rig with and without the marker; the
three ADR login tests all fail with the marker present; removing the marker and
rebooting restores every service. One FAQ entry, "Locking down a MiSTer on a network
you don't trust", covers S1, S2, and S10 together.

### S11 — Gate password logins on a changed password (Q1, if accepted) — Size S — Depends: S2

At boot, if root's hash in the (restored) `/etc/shadow` equals the shipped
`$5$MiSTer618$...` value and `sshd_allow_password` is absent: sshd key-only, and
`proftpd` does not start. Console prints a one-line explanation with the two ways out
(`authorized_keys` on the card, or `mister-passwd` on the serial console).

**Done when:** fresh card: all three ADR login tests fail; after `mister-passwd`: SSH
and FTP with the new password work; after dropping `authorized_keys`: key SSH works and
FTP still needs the password change. Release notes carry this as the one visible
change from stock.

---

## Tier 3 — recorded, not scheduled

| Item | Blocker | Note |
|---|---|---|
| Kernel `HARDENED_USERCOPY`, `SLAB_FREELIST_*`, `FORTIFY_SOURCE`, `INIT_ON_ALLOC` | Rig boot + RT latency run each | Main_MiSTer's `/dev/mem` and SPI paths are what these touch |
| `STRICT_DEVMEM` | Must confirm every bridge MMIO range Main_MiSTer maps is non-RAM | `IO_STRICT_DEVMEM` is a separate, stricter question |
| ProFTPD unprivileged | Card mount needs `uid=`/`gid=`; ripples into `StrictModes`, ADR 0020 installer | Not before S2–S4 have settled |
| Signed release archives | Downloader fetches and applies in one run | Needs a design; ecosystem has no precedent |
| ProFTPD 1.3.9d re-audit | Reading time | `ssh-ftp-parity.md` still says "unaudited" |
| Bluetooth `JustWorksRepairing`/`Privacy` | None | Stock parity, leave unless a venue reports it |
| Drop `iptables` package | Confirm no community script uses it | After S6 has shipped one release |

---

## Suggested PR grouping

1. **This PR:** ADR 0031 + this plan + S8. Docs only.
2. **PR "sshd posture":** S1 + S7. Overlay + CI only, no rebuild of anything but the
   rootfs.
3. **PR "ftp posture":** S3 + S4. Same.
4. **PR "kernel: seccomp + nftables":** S5 + S6. Kernel rebuild on both channels and both
   boards; the golden lines move; needs a rig boot on each kernel before merge.
5. **PR "persist shadow":** S2. The only one with a genuinely new mechanism; rig test is
   mandatory and the PR description carries the before/after reflash transcript.
6. Tier 2 after Q1/Q2 are answered, one PR per task.
