# P2.9 — Stock `MiSTer` binary reaches the menu on our rootfs: **PASS**

**Date:** 2026-07-12
**Board:** Terasic DE10-Nano (Cyclone V), real hardware
**Kernel:** `6.18.33` (our build, `zImage_dtb_mrl`)
**Rootfs:** **our `linux.img` v2** — Buildroot 2026.02.3, glibc 2.42, our 24-patch kernel's 42 modules
**Userland tested:** the **stock, unmodified** `MiSTer` binary (`Version 260707`) from `/media/fat`

> **This is the Phase 2 exit gate AND the project's central bet. It passed.** The
> unmodified stock `MiSTer` binary runs on a five-years-newer userland
> (Buildroot 2021.02→2026.02, glibc 2.31→2.42) and reaches the menu on HDMI.

## G1 confirmed — "no MiSTer binary needs rebuilding"

Serial + HDMI, on our rootfs:

```
Version 260707
Using SD card as a root device
I/O Board type: digital
Core name is "MENU"
```

The stock binary started, identified the I/O board, found SDRAM config 3, loaded
the MENU core, and drove HDMI — confirmed on the monitor. Its 200 versioned
symbol imports had already been proven to resolve against our glibc 2.42
(highest requirement `GLIBC_2.28`); this is that proof, executed on silicon.

## Assertions

| Assertion | Result | Evidence |
|---|---|---|
| Stock `MiSTer` binary reaches the menu | **PASS** | `Core name is "MENU"`, HDMI confirmed |
| Boots our rootfs (not stock) | **PASS** | `Welcome to Buildroot`; `PRETTY_NAME="Buildroot 2026.02.3"`, glibc 2.42 |
| Loop-mounts the **parallel** image (stock `linux.img` untouched) | **PASS** | `[init] loop /dev/loop0 -> /mnt/fat/linux/linux_v2.img` |
| `mem=511M` honoured (FPGA owns top of DDR) | **PASS** | kernel sees 491 MiB; 35 MiB used at menu |
| SSH reachable as `root` | **PASS** | `root:1` authenticates over the network (see usr-merge fix) |
| Networking | **PASS** | `eth0` DHCP → 192.168.0.161 (MAC pinned) |
| Per-device SSH host keys generated on first boot | **PASS** | `Checking for SSH host key storage` → keys on `/etc/ssh_keys` (ADR 0015) |
| **A15** loop device writable, mount ro | **PASS** | `/sys/block/loop0/ro == 0` |
| Clean dmesg | **PASS** | **0** aborts/segfaults (v1 had 9 `nfsrahead` SIGABRTs) |

## This was v2 — v1 found three real parity bugs, all fixed here

The first full-rootfs boot (v1) reached the menu but exposed three bugs; v2 fixed
each, confirmed by diffing the two serial logs and by live inspection:

| Bug (v1) | v2 fix | Confirmed on hardware |
|---|---|---|
| **SSH locked out** — `/etc/pam.d/sshd` references `/lib/security/pam_unix.so`, absent on our split layout, so PAM could not load `pam_unix` and rejected every login. `root:1` was correct all along. | `BR2_ROOTFS_MERGED_USR=y` (matches stock) | `/lib→usr/lib`, `/bin→usr/bin`, `/sbin→usr/sbin`; `root:1` authenticates over SSH |
| **`/var/lock` unwritable** on the read-only root (`/run/lock` never created) — sshd/cron lock `touch` failed | `mkdir -p /run/lock` in inittab | `/run/lock` exists with `sshd`, `subsys`; `Starting sshd: OK` with no error |
| **NFS server** (`S60nfs`) failing + `nfsrahead` SIGABRT spam + rpcbind — stock ships none | dropped `BR2_PACKAGE_NFS_UTILS` (auto-drops rpcbind) | no NFS/rpcbind processes; 0 dmesg aborts |

## My process error, recorded so it is not repeated

The v1 flash overwrote `linux.img` **while it was the live loop-mount backing
file**, corrupting the running filesystem mid-copy (`Illegal instruction` on
`sleep`/`sync`). The correct method — used for v2 and from now on — writes a
**separate** file (`linux_v2.img`) and boots it via a U-Boot `mmcboot` override
(`loop=linux/linux_v2.img`), so the running/stock image is never touched and
rollback is one line in `u-boot.txt`.

## Known-cosmetic, deferred (none fatal, all tracked)

- `seedrng: can't create directory /var/lib/seedrng` — read-only root; `urandom-scripts` is a transitive dep. → full **P2.4** writable-paths audit.
- `wpa_supplicant ... usage` on wlan bring-up — no Wi-Fi modules yet anyway. → **P3.1** (`WIRELESS_EXT` / wpa 2.11).
- `sh: uartmode: not found` — stock ships `/usr/sbin/uartmode` (a MiSTer helper); we do not yet. Parity gap for a later pass.
- `dhcpcd: sandbox unavailable: seccomp` — stock has `SECCOMP` off too; enabling it is the beyond-parity security pass.
- **`/MiSTer.version` MISSING** — **P2.6 / A10.** The Downloader compares this file with a bare `f.read()` (no `.strip()`); absent or newline-terminated ⇒ re-flash on every run. Must be exactly 6 bytes, no trailing newline. Not exercised by a boot test, but required before the image is fit for the update channel.
- Bluetooth re-pair needed (bluez 5.79 vs stock's older) — investigate; likely a one-time re-pair.

## Bottom line

**Phase 2's exit gate is met on hardware.** The image boots, the stock binary
reaches the menu, SSH and networking work, and the three v1 regressions are
fixed. The remaining items are cosmetic or documentation/parity polish, tracked
for their proper tasks.
