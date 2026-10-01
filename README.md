# MiSTer Linux Modernization

**A complete, reproducible operating system for the MiSTer DE10-Nano:** kernel, root
filesystem, a real-time kernel variant, a flashable SD-card image, and the update channel
that delivers them. It is built in the open from a current Buildroot and a mainline LTS
kernel, with every MiSTer kernel change carried as a plain `.patch` file against a
pristine, hash-verified kernel.org tarball.

It is a **drop-in replacement.** The unmodified stock `MiSTer` binary and every existing core
run on it unchanged. (One requirement: **Main_MiSTer Release 20260912 or newer.** The
Switch controller's IMU/LED naming moved from the kernel into Main_MiSTer #1307/#1308, so an
older binary sees a phantom IMU pad and dark Switch LEDs.)

> **Status: personal use only.** It is validated on one real DE10-Nano. Nothing here is
> offered publicly until a named maintainer signs the sustainability commitment in
> [ADR 0014](docs/decisions/0014-sustainability-deferred-not-waived.md). If you try it
> anyway, read [`docs/user/beta-testing.md`](docs/user/beta-testing.md) first.

## Contents

- [Why this exists](#why-this-exists)
- [Stock vs. this image](#stock-vs-this-image)
- [**Install it on a real MiSTer**](#install-it-on-a-real-mister)
- [What is different, in detail](#what-is-different-in-detail)
- [What has been verified, and what has not](#what-has-been-verified-and-what-has-not)
- [Updates and the release channel](#updates-and-the-release-channel)
- [Building it yourself](#building-it-yourself)
- [How it is put together](#how-it-is-put-together)
- [Verification and CI](#verification-and-ci)
- [Documentation map](#documentation-map)
- [Contributing and licensing](#contributing-and-licensing)

---

## Why this exists

Stock MiSTer's OS ships as prebuilt tarballs. Its userland comes from **Buildroot
2021.02.4** (glibc 2.31, OpenSSL 1.1.1k), and nothing public turns source into those
tarballs. Release 20260907 moved stock's kernel from 5.15.1 to **6.18.38**, but it is pinned
at that one point release, the way 5.15.1 was for five years with no `.y` updates. The
userland outside the kernel, modules and firmware was byte-for-byte unchanged by that
release. There is no build recipe, no CI, no SBOM and no update path.

This project rebuilds all of it from **Buildroot 2026.08** and a **6.18 LTS kernel that
tracks the `.y` stable line**. It has reproducible builds, a signed-hash supply chain and a
per-commit reconciliation of the MiSTer kernel fork. It ships through the update channel
users already have, plus a real-time kernel and a flashable card image that stock has no
equivalent of.

The posture is **prove parity first, then improve**:

- Boot the unmodified stock `MiSTer` binary, and match stock's behaviour, not just its file list.
- Carry the smallest possible kernel delta, and hand each piece back to mainline when
  mainline can hold it. There is no separate kernel repository: the kernel is
  `{pinned tarball + ordered patch series}`.
- Make builds fully reproducible: pinned Buildroot, kernel and every source by hash, and an
  SBOM with every release.
- Never commit binaries to git; releases are GitHub Release assets.
- Distribute opt-in, through the stock on-device Downloader, with nobody's cooperation required.

## Stock vs. this image

Stock figures are from Release 20260907, re-measured 2026-09-10 from the extracted release
([`docs/stock-inventory/20260907/`](docs/stock-inventory/20260907/)).

| | Stock MiSTer | This image |
|---|---|---|
| **Kernel** | 6.18.38, pinned with no `.y` updates (5.15.1 from 2021 until 2026-09-07, likewise never updated) | 6.18 LTS, tracking every `.y` stable release via Renovate |
| **Kernel source** | A squashed-import fork with no shared history with mainline | Pristine kernel.org tarball plus a series of documented patch files |
| **Userland** | Buildroot 2021.02.4, glibc 2.31, gcc 10 era | Buildroot 2026.08, glibc 2.44, gcc 15.3 |
| **OpenSSL** | 1.1.1k, end-of-life since 2023-09-11 | 3.6.4 |
| **OpenSSH / Samba / Python** | 8.6p1 / 4.14.6 / 3.9.6 | 10.5p1 / 4.24.6 / 3.14.7 |
| **SSH host keys** | The same keys on every MiSTer, in the public download | Generated per device on first boot ([ADR 0015](docs/decisions/0015-per-device-ssh-host-keys.md)) |
| **SSH key login** | `authorized_keys` is lost on every Linux update | Read from the FAT card, so it survives updates |
| **`.7z` extractor for updates** | p7zip 16.02 (2016), fetched off the internet as `linux/7za` | 7-Zip 26.03, built from source and shipped ([ADR 0023](docs/decisions/0023-ship-7zip-instead-of-fetching-p7zip-16.md)) |
| **Wi-Fi** | Mainline drivers with firmware for most USB chips; no Broadcom, Redpine, `ath9k_htc` or Wi-Fi 6E | The same, plus those four families ([details](#wi-fi-and-bluetooth)) |
| **Bluetooth firmware** | Broad; missing the Realtek Wi-Fi 6 combo chips' Bluetooth | Broad; each side ships a few blobs the other lacks ([details](#wi-fi-and-bluetooth)) |
| **Filesystems** | Mainline exFAT and FAT; no NTFS; no way to repair exFAT | Same exFAT and FAT, plus NTFS and an on-device exFAT check and repair |
| **Timezone on a fresh card** | UTC until the user runs `timezone.sh` | Detected once, on the first network connection ([ADR 0025](docs/decisions/0025-first-boot-timezone-autodetect.md)) |
| **Image headroom** | 6.3% free in a 375 MiB image | 512 MiB image; CI fails a build that leaves under 15% free |
| **Build recipe** | Not published (`Linux_Image_creator_MiSTer` only re-packs a prebuilt tarball) | This repository |
| **Reproducible / SBOM** | No / none | Byte-identical builds, proven in CI; full `legal-info` with each release |
| **Dependency updates** | Manual | Renovate, for kernel, firmware and every package hash |
| **Real-time kernel** | No | `PREEMPT_RT` variant, built by CI, booted on hardware |
| **Fresh-card install** | Mr. Fusion or the Windows SD installer | `sdcard.img.xz`: flash it, and it expands to the card on first boot |

More detail, with citations: [`docs/version-delta.md`](docs/version-delta.md),
[`docs/verification/stock-release-20260907.md`](docs/verification/stock-release-20260907.md)
and [`docs/stock-reconciliation.md`](docs/stock-reconciliation.md). The build pins
(`BUILDROOT_VERSION` in the `Makefile`, the defconfigs, Buildroot's own `.mk` files) are the
ground truth for our versions, and each release's `legal-info` manifest lists them exactly;
the documents are dated readings.

---

<a id="install-it-on-a-real-mister"></a>
## Install it on a real MiSTer

**One command, run on the MiSTer over SSH.** It converts an ordinary install, including one
made with Mr. Fusion, without reflashing anything.

```sh
curl -fsSL https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/install.sh | bash
```

<a id="if-the-one-liner-seems-to-do-nothing"></a>
> **On a stock card that command fails silently**, and the pipeline still exits 0. Stock's
> `curl` cannot verify GitHub (`curl: (60)`): its one CA file, `cacert.pem`, works but is not
> in the layout curl searches by default. So fetch the installer with `-k` for that one
> request. The installer then checks the card's own CA bundle works and uses it for
> everything afterwards:
>
> ```sh
> curl -fsSLk https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/install.sh -o /tmp/mlm.sh \
>   && sh /tmp/mlm.sh
> ```
>
> To avoid `-k` entirely, download `install.sh` on another machine, check its `sha256sum`,
> and copy it to the card. `install.sh --bootstrap-ca` handles a card whose bundle is
> genuinely broken, and explains the trade-off first. **`wget` is not an alternative**: the
> MiSTer's BusyBox `wget` has no TLS. You only need this once, because this image ships a CA
> bundle in the layout curl expects.

To read before you run:

```sh
curl -fsSL https://raw.githubusercontent.com/mcfbytes/Buildroot_MiSTer/master/install.sh -o mlm.sh
less mlm.sh
sh mlm.sh --dry-run     # prints exactly what it would change, touches nothing
```

`--yes` skips the 10-second countdown; `--no-reboot` leaves the reboot to you.

**What it changes.** The installer prints this and pauses before doing anything.

| File | Change |
|---|---|
| `linux/linux.img`, `linux/zImage_dtb` | Replaced: the root filesystem and kernel |
| `linux/7za` | Replaced: 7-Zip 26.03 instead of the 2016 p7zip |
| `downloader.ini` | One key: `[MiSTer] update_linux = false`. Original saved to `linux/.mlm-backup/` |
| `Scripts/update_linux_modernization.sh` | Installed: updates this image from now on |
| `Scripts/check_storage.sh`, `Scripts/pair_logitech.sh` | Installed: [exFAT check](docs/decisions/0026-user-driven-exfat-fsck.md) and [Logitech pairing](docs/logitech-pairing.md) launchers |

Everything else under `linux/` is rewritten with byte-identical content, because the release
archive *is* stock's archive with those files swapped in; small files are backed up to
`linux/.mlm-backup/` first anyway. Expect two side effects that any Linux update causes:
the saved U-Boot environment is wiped by `updateboot`, and the SSH host key changes once (to
this device's own key).

**What it leaves alone:** `MiSTer.ini` and every core `.ini`, games, saves, `config/`, cores,
`linux/gamecontrollerdb/`, your live `u-boot.txt`, `wpa_supplicant.conf`,
`user-startup.sh` and `samba.sh`. Network identity (`linux/{hostname,hosts,interfaces,
resolv.conf,dhcpcd.conf,fstab}`) is copied into the new image before it goes live.

**Afterwards,** cores keep updating normally; `update_all.sh` and `Scripts/update.sh` just
stop touching the Linux image ([ADR 0025](docs/decisions/0025-update-linux-kill-switch-and-private-updater.md)).
Updating this image is one deliberate action:

```sh
/media/fat/Scripts/update_linux_modernization.sh            # update
/media/fat/Scripts/update_linux_modernization.sh --status   # where am I?
/media/fat/Scripts/update_linux_modernization.sh --restore-stock   # undo, then run a normal update
```

Full rollback procedure: [`docs/user/rollback.md`](docs/user/rollback.md).

**Other ways in:**

- **A fresh card:** flash `sdcard.img.xz` from a
  [release](https://github.com/mcfbytes/Buildroot_MiSTer/releases). It arrives configured,
  with Jotego's cores enabled ([`docs/user/sdcard-flashing.md`](docs/user/sdcard-flashing.md)).
- **By hand:** [`docs/user/onboarding.md`](docs/user/onboarding.md) walks through the same steps.

**On `curl | bash`:** you are running a remote script as root. It is the same trust model
MiSTer's own `update.sh` uses (HTTPS to GitHub). If that is not a trade you want, use the
download-and-read form or the by-hand route.

---

## What is different, in detail

### The kernel

The 6.18 LTS kernel is pinned by version and SHA-256 against kernel.org, and Renovate opens
a PR for every `.y` release. The exact patch level lives only in
`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` in `configs/mister_de10nano_defconfig`, because it
changes weekly.

**Every MiSTer kernel change is a reviewed patch file.** Every commit of the MiSTer kernel
fork (the 5.15 history, upstream's `MiSTer-v6.18` branch and older residue) was reconciled
one by one. Each has an evidence-backed disposition record, and each record was checked by
a second, independent review ([`docs/kernel-recon/`](docs/kernel-recon/)). What survives is a
series of patch files in `board/mister/de10nano/linux-patches/`. Everything else is either
already in mainline, replaced by a maintained package, or dropped by a recorded decision.
The reconciliation also caught gaps the original triage had missed (Joy-Con combining,
DualSense player-ID and mic-mute, stock NES/Famicom button mapping, fake-CSR Bluetooth
dongles), and those are now carried. A weekly workflow diffs upstream's fork and keeps an
issue updated with what is new. The series also carries this project's own fixes, for
example the dwc2 USB host work below and an rtw88 Wi-Fi fix. Some of these have been
contributed upstream to `Linux-Kernel_MiSTer`.

**The kernel can be exported back.** [`scripts/export-kernel-tree.sh`](scripts/export-kernel-tree.sh)
renders the pinned tarball plus series into a `Linux-Kernel_MiSTer`-style git tree,
deterministically, so upstream can consume the work without a second fork
([`docs/kernel-export.md`](docs/kernel-export.md)).

**Six latent bugs, found by reading the code.** All of them exist verbatim in every MiSTer
image shipped to date, and all are in MiSTer-original or fork-modified code, none in
mainline code.

| | Where | Bug | Status |
|---|---|---|---|
| B1 | GameCube adapter | Use-after-free on unplug: per-port work items never cancelled | Fixed |
| B2 | `MiSTer_fb` | `memremap()` failure checked with `IS_ERR()`; NULL falls through to an Oops | Fixed |
| B3 | MiSTer audio SPI | `ERR_PTR` returns checked against `NULL`; failures treated as success | Fixed |
| B4 | MiSTer audio SPI | Diagnostic string computed from a failed read | Fixed |
| B5 | Logitech K400 Fn | `SetFeature` sent to the wrong HID++ feature index | Fixed |
| B6 | Cyclone V cpufreq | `wait_for_fsm()` polls the wrong bit | Carried verbatim on purpose: fixing it changes live PLL timing |

Write-ups: [`docs/patch-provenance.md` §10](docs/patch-provenance.md).

### Security

- **OpenSSL 1.1.1k → 3.6.4.** Stock's TLS library has been end-of-life since September 2023.
- **Per-device SSH host keys.** Every stock MiSTer shares one set of host keys from the
  public download, so impersonating one produces no host-key warning. This image generates
  keys on first boot and keeps them on the FAT card
  ([ADR 0015](docs/decisions/0015-per-device-ssh-host-keys.md)).
- **SSH key login survives updates.** `sshd` also reads `/media/fat/config/authorized_keys`,
  which an OS update never touches. That is the same file `security_fixes.sh` uses, so an
  existing key keeps working ([FAQ](docs/user/faq.md#ssh-key-persist)).
- **Current network-facing software:** OpenSSH 10.5p1, Samba 4.24.6, BlueZ 5.86,
  wpa_supplicant 2.12, Python 3.14.7 ([compatibility notes](docs/python-compat.md)).
- **An update path.** Renovate tracks the kernel, firmware and every pinned package, and CI
  proves each bump still builds and passes the parity suite.
- **IPv6 is built in but off** until you opt in on the card (stock has none).

Deliberately unchanged: **the root password is still `1`**, for stock parity
([FAQ](docs/user/faq.md#whats-the-default-root-password-and-is-that-a-problem)). A
secure-by-default network posture is proposed in
[ADR 0031](docs/decisions/0031-secure-by-default-network-posture.md) and not yet adopted.

### Storage and everyday features

| Feature | Stock | This image |
|---|---|---|
| exFAT repair | None, though the card is never cleanly unmounted | **Scripts > check_storage.sh**: read-only scan, then a confirmed repair on next boot ([ADR 0026](docs/decisions/0026-user-driven-exfat-fsck.md)) |
| NTFS | Not supported | `ntfs3` plus `ntfs-3g`, with USB automount ([ADR 0013](docs/decisions/0013-ntfs3-and-all-ext4-variant.md)) |
| Logitech Unifying pairing | Not possible on the device | **Scripts > pair_logitech.sh** ([doc](docs/logitech-pairing.md)) |
| CIFS mounts | No `mount.cifs` | `cifs-utils` ([doc](docs/netfs-parity.md)) |
| BitTorrent | `rtorrent`, foreground TUI, no local peer discovery | `transmission-daemon`, off until you opt in on the card, state kept on the card ([doc](docs/bittorrent.md)) |
| ZeroCD Wi-Fi dongles | No `usb_modeswitch`, so they stay in CD mode | `usb_modeswitch` with the configs these dongles need |
| USB controller polling | A 1 kHz full-speed device is polled every 2 ms | Fixed in the dwc2 host driver: 500 → 984 reports/s measured ([doc](docs/dwc2-usb-irq.md)) |
| Off-device backup | None | `azcopy` packaged, not enabled by default ([doc](docs/azcopy.md)) |

<a id="wi-fi-and-bluetooth"></a>
### Wi-Fi and Bluetooth

Both images now use mainline drivers, and stock has closed most of its firmware gaps since
6.18 (Releases 20260907 and 20260912). The comparison below is per driver: for every Wi-Fi
and Bluetooth module in each image, does the firmware it requests actually ship? Stock is
measured from Release 20260912's `modules.tar.gz`, `firmware.tar.gz`, kernel config and base
rootfs (re-checked 2026-10-01). Background audits: [`docs/wifi-parity.md`](docs/wifi-parity.md),
[`docs/bluetooth-parity.md`](docs/bluetooth-parity.md).

**Most rows are build-verified only**: one Realtek chip has been tested on hardware.

| Chip family | Stock | This image | Verified |
|---|---|---|---|
| Realtek 802.11n/ac (`rtl8xxxu`, `rtw88`: RTL8188, 8710, 8811/8821, 8812, 8814, 8822, 8723DU) | With firmware | Same | **Hardware** (RTL8822BU, WPA3 5 GHz) |
| Realtek Wi-Fi 6 (RTL8851BU, 8852BU) | `rtw89` with firmware | Same | Build |
| Realtek Wi-Fi 6E (RTL8852CU/8832CU) | None | Out-of-tree `rtl8852cu-morrownr`, the only USB driver that exists | Build |
| AICSemi AIC8800 family (Tenda U2/U11, TX1U Nano…) | Driver and firmware | Same | Build |
| MediaTek (MT7601U, MT76x0U/x2U, MT7663U, MT7921U, MT7925U) | `mt76` with firmware | Same | Build |
| RTL8192DU | With firmware | Same | Build |
| Broadcom / Cypress (BCM43xx, CYW43xx) | None | `brcmfmac` with firmware | Build |
| Atheros AR9271/AR7010 | None | `ath9k_htc` with firmware | Build |
| Atheros AR9170 | `carl9170` without its firmware, so it fails | With firmware | Build |
| Atheros AR6003/AR6004 | `ath6kl`, partial firmware | Same | Build |
| Redpine RS9113/RS9116 | None | `rsi` with firmware | Build |
| Ralink RT73, Marvell (`mwifiex`, `libertas`) | Driver without firmware | Same (gap on both sides) | — |
| Bluetooth: Realtek | Missing the Wi-Fi 6 combo chips (RTL8851BU, 8852AU/BU/CU) | Has those; missing RTL8761CU and RTL8922AU | Pairing: **hardware** |
| Bluetooth: Qualcomm / Atheros | `ath3k` plus AR3012 configs; the full USB QCA rampatch set | `ath3k`; QCA Rome (6174A) only | Build |
| Bluetooth: MediaTek | MT7961, MT7925; no MT7922 | MT7961, MT7925; no MT7961 `1a` variant | Build |

Deliberate omissions: Qualcomm QCA9377 over USB (`ath10k_usb`), whose upstream Kconfig says
it "will not fully work" (stock ships it), plus four 2000s-era 802.11b/g drivers and a LiFi
driver. Two Bluetooth drivers (Intel, BCM2033) build without firmware because none exists
for hardware this board can host.

### The real-time kernel

`zImage_dtb-rt` is a `PREEMPT_RT` kernel on the 7.2.y line. 32-bit ARM RT is mainline since
7.1, so no out-of-tree RT patch is carried. It is built by the same `make` as the main
kernel, from the same config plus a fragment, and its modules ride inside the same
`linux.img`. Switching kernels is therefore a one-line `u-boot.txt` edit, with no rootfs
flash. It is a manual download from the Release page, never pushed by `db.json`. No
latency measurement has been taken yet, so it is for testing, not daily use
([ADR 0021](docs/decisions/0021-rt-kernel-first-class-ci.md),
[`docs/rt-beta-kernel.md`](docs/rt-beta-kernel.md)).

### The SD-card image

`sdcard.img.xz` is a complete, `dd`-able card. It ships small and uses mr-fusion's own
mechanism: a throwaway installer reformats the card to exFAT at its real size on first boot,
because Linux cannot grow exFAT in place. Install time depends on the card's write speed, not
its size. The installer shows progress on HDMI (using
[`itsalive`](https://github.com/mcfbytes/ItsAlive_MiSTer) to light the display without
Main_MiSTer) and on the serial console. It is reordered so an interrupted install is
recoverable rather than a brick. It is a separate release asset, never referenced by
`db.json`, because it writes the bootloader
([ADR 0020](docs/decisions/0020-sdcard-exfat-reformat-installer.md),
[payload inventory](docs/verification/sdcard-payload.md)).

### Deliberately identical to stock

Most of the work is invisible because parity is the goal. This image reproduces stock's
behaviour for:

- the `MiSTer` binary's ABI and every SONAME it links;
- the boot chain and the `uboot.img` (shipped byte-identical, fetched by hash);
- `/media/fat` mount flags (`sync,dirsync`: async would corrupt on power-off);
- the read-only root with its login-time `remount,rw`;
- mainline exFAT with the symlink extension (ADRs [0010](docs/decisions/0010-drop-out-of-tree-exfat.md), [0019](docs/decisions/0019-exfat-symlinks-carried-patch.md));
- the Bluetooth key store and RTC;
- MIDI/MT-32, Samba and SSH/FTP;
- BusyBox applet coverage and the init scripts;
- `/MiSTer.version` semantics and the Downloader contract.

Each has its own parity audit (see the [documentation map](#documentation-map)).

---

## What has been verified, and what has not

| Phase | State |
|---|---|
| 0: Recon and decisions | ✅ Complete |
| 1: Kernel and initramfs | ✅ Complete; boots on hardware from the CI-built artifact |
| 2: Rootfs and testing | ✅ Complete; menu and cores load on hardware |
| 3: Driver packages and hardware matrix | ✅ Complete for the hardware on the test board; the wider Wi-Fi/Bluetooth set is build-verified |
| 4: Release and sustainability | 🔄 In progress: CI/CD and `db.json` done; sustainability gate open |
| 5: Full SD image and U-Boot | 🔄 `sdcard.img` done and tested on hardware; mainline U-Boot builds but ships nowhere ([ADR 0024](docs/decisions/0024-mainline-uboot-capability-artifact.md)) |

<a id="hardware-validation-ledger"></a>
### Hardware validation ledger

This is everything tested on the one DE10-Nano. Anything not listed should be treated as
unverified. Logs are in [`docs/testlogs/`](docs/testlogs/).

| Subsystem | Status |
|---|---|
| Boot to the MiSTer menu, cores load | ✅ |
| Bluetooth firmware load and controller pairing | ✅ |
| Wi-Fi WPA3/SAE 5 GHz auto-connect (`rtw88`, RTL8822BU) | ✅ |
| Downloader over HTTPS, and a full `update_all.sh` run leaving the image untouched | ✅ |
| `PREEMPT_RT` kernel boots and runs MiSTer | ✅ |
| dwc2 USB polling fix (1 kHz input) | ✅ measured on the RT kernel |
| Samba, MIDI, most Wi-Fi/Bluetooth chips | ⚠️ Build/CI-verified only |
| `sdcard.img` flashed to a fresh card: installer, HDMI splash, first boot | ✅ |
| RT latency | ⏳ Not yet measured |

### Known limitations

- **One known regression:** the Logitech **G923 PlayStation variant** loses force feedback
  and range control (it still works as a joystick). The G923 Xbox variant and G29/G27/G25
  are fully supported ([`patch-provenance` §9](docs/patch-provenance.md)).
- **Forward-ported patches can change meaning silently.** Early builds auto-overclocked
  the board to 1.2 GHz and hung: a 5.15-era cpufreq patch applied and compiled cleanly on
  6.18, but a kernel flag's semantics had changed. That was fixed in PR #24, and it is why
  the delta is kept small and the hardware list honest.
- **RT has no latency evidence yet.**
- **Debug tooling is temporarily in the image** (`gdb`, `strace`, `perf`, `rt-tests`,
  core dumps). It costs image space and is designed to revert as one unit
  ([`docs/debug-tooling.md`](docs/debug-tooling.md)).
- **The sustainability gate is not met.** Nobody has yet committed in writing to tracking
  `6.18.y` through end-of-life ([ADR 0014](docs/decisions/0014-sustainability-deferred-not-waived.md)).
- **Package versions are not asserted by CI.** A Buildroot bump can move a package under a
  parity audit. That has happened: OpenSSH 10.4's fatal seccomp change once broke SSH on a
  shipped image. Parity documents note at the top when they are behind the pins.

---

## Updates and the release channel

Releases are GitHub Release assets:

- the Downloader set: `release_YYYYMMDD.7z`, `linux.img`, `zImage_dtb`, the kernel `.config`s,
  `legal-info.tar.gz`, `SHA256SUMS`;
- the `-rt` kernel files;
- `sdcard.img.xz`, which is published separately.

Updates come from a community `db.json` on GitHub Pages, read by the stock on-device
Downloader.

**Coexisting with the official channel** ([ADR 0025](docs/decisions/0025-update-linux-kill-switch-and-private-updater.md)):
the Downloader applies at most one Linux image per run, and when databases compete, the
official one wins. So rather than compete, the installer:

- sets `update_linux = false`, so no normal run applies any Linux image (cores, ROMs and
  MRAs still update);
- installs `update_linux_modernization.sh`, which runs the Downloader against a private ini
  naming only this project's database.

There is no daemon or boot script involved. On hardware, a full `update_all.sh` run
installed 379 cores and left `linux.img` and `zImage_dtb` byte-identical.

Versioning: the Downloader compares versions by string inequality, and reproducible builds
pin `SOURCE_DATE_EPOCH`, so `/MiSTer.version` is derived from the release date instead
([ADR 0018](docs/decisions/0018-db-json-version-is-release-date-driven.md)).

User docs: [onboarding](docs/user/onboarding.md) · [rollback](docs/user/rollback.md) ·
[FAQ](docs/user/faq.md) · [serial recovery](docs/user/serial-recovery.md) ·
[beta testing](docs/user/beta-testing.md)

---

## Building it yourself

This is a plain Buildroot br2-external. The wrapper `Makefile` fetches the pinned Buildroot
into `work/buildroot`, verifies it against upstream's GPG-signed manifest, and forwards
every target with `BR2_EXTERNAL` and `O=` set:

```sh
make mister_de10nano_defconfig  # configure the DE10-Nano image into output/
make                            # build (the first run bootstraps a toolchain: hours, not minutes)
make linux-menuconfig           # or menuconfig, linux-rt-menuconfig, legal-info, <pkg>-rebuild, help…
make sdcard                     # after make: the SD-card installer image
make O=output-de25 mister_de25nano_defconfig && make O=output-de25   # the DE25-Nano (or: make de25)
```

`make` produces `output/images/linux.img`, `zImage_dtb`, `zImage_dtb-rt` and the stage-1
`mister-initramfs.cpio`.

**The one non-standard part is package selection.** The defconfig enables three Kconfig
profiles (`BR2_PACKAGE_MISTER_USERSPACE`, `_FIRMWARE`, `_DRIVERS`), and their `select` lists
live in `package/mister-*/Config.in`, so both boards share one package set. To answer "why
is package X in my image?", look in `package/mister-userspace/Config.in`
([`docs/buildroot-config.md`](docs/buildroot-config.md)).

Things that will bite you otherwise:

- **Don't pass `-j`.** Buildroot's top level is not parallel-safe; packages build in
  parallel internally.
- **Re-run `make mister_de10nano_defconfig`** after `make clean` or after a pull that moves
  `BUILDROOT_VERSION`; a stale config stops at an interactive prompt. A pin move is best
  followed by `make distclean`.
- **Keep defconfigs canonical.** After editing, run `make savedefconfig`;
  `scripts/check-defconfigs.sh` (a CI lint) checks each defconfig reproduces itself and that
  every profile `select` lands.

| Target | What it does |
|---|---|
| `make linux-rt` | Rebuild only the RT kernel |
| `make mister-initramfs` | Rebuild the stage-1 cpio (then `make linux-rebuild all` to re-embed it) |
| `make savedefconfig` | Write the config back to `configs/` |
| `make buildroot-verify` / `buildroot-showsig` | Verify the Buildroot tarball / show upstream's signed manifest |
| `make legal-info` | Generate the SBOM |
| `make clean` / `distclean` | Buildroot's meanings, per `O=`; `dl/` is kept |

**Host requirements:** standard build tools (`gcc`, `make`, `bc`, `flex`, `bison`, `cpio`,
`rsync`, `unzip`, `wget`/`curl`, `python3`), plus `dtc`, `qemu-user`/`qemu-system-arm` and
`shellcheck` for the tests. If `/usr/bin/install` is uutils 0.8.0, which Buildroot rejects,
the Makefile shims GNU `install` in for Buildroot only; no `sudo` is needed.

---

## How it is put together

```
Makefile                   thin wrapper: fetch + verify Buildroot, forward everything else
configs/                   mister_de10nano_defconfig, mister_de25nano_defconfig,
                           mister_installer_defconfig  (rationale: docs/buildroot-config.md)
package/mister-{userspace,firmware,drivers}/   Kconfig profiles shared by both boards (ADR 0030)
package/                   drivers (Wi-Fi, xone…), libraries (libchdr, rcheevos…), linux-rt,
                           the stage-1 initramfs, itsalive, 7zip, munt, midilink…
linux/                     kernel extension that embeds the stage-1 initramfs
board/mister/de10nano/
  linux.config             minimal kernel defconfig (an absent CONFIG_X is not "off")
  linux-patches/           the carried 6.18 series
  linux-patches-beta/      the 7.2 (RT) series: symlinks into linux-patches/ plus re-anchored copies
  linux-patches-upstream/  what the exported tree needs but this image must not carry
  rootfs-overlay/          init scripts, sshd wiring, MiSTer-specific files
  installer-*/             the SD-card installer's /init and HDMI splash
board/mister/de25nano/     the DE25-Nano developer OS (aarch64)
scripts/                   test suite, hash sync, SD-card builder, kernel export
docs/                      ADRs, parity audits, kernel reconciliation, user docs
```

**Two kernels, one image.** The Cyclone V is 32-bit ARM, where `PREEMPT_RT` cannot be a
boot-time switch, so RT is a second kernel package (`package/linux-rt`) in the same build.
It hard-asserts `CONFIG_PREEMPT_RT=y` and installs its modules into the one `linux.img`.

**An initramfs instead of the `loop=` kernel patch.** Stock patches `init/do_mounts.c` so the
kernel itself mounts `/media/fat` and loop-mounts `linux.img`. Here, a small BusyBox
initramfs embedded in the kernel does that in a shell script. It retries with `rootwait`,
probes vfat then exFAT, and drops to a rescue shell on failure, so it is debuggable and is
one kernel patch fewer. It is also architecture-neutral: stock's patch calls `sys_ioctl()`
directly, which does not exist on arm64. Details:
[`docs/loop-boot-6.18.md`](docs/loop-boot-6.18.md), [`PLAN.md` §5](PLAN.md).

**DE25-Nano.** A bare developer OS for the Agilex 5 DE25-Nano (aarch64, 7.2 kernel) builds
from the same tree and shares the userspace profiles and most kernel patches. It has no
MiSTer binaries yet and its own manual CI lane. Start at
[`docs/de25-nano-overview.md`](docs/de25-nano-overview.md).

---

## Verification and CI

[`scripts/ci-tests.sh`](scripts/ci-tests.sh) runs the whole non-hardware suite and prints a
digest last. It covers:

- image contract checks (kernel, `linux.img`, size budget);
- QEMU boot tests of the initramfs `/init` across its failure paths, on both kernels;
- an ABI smoke test that runs the **stock `MiSTer` binary** under `qemu-user` against the
  built rootfs (it must link cleanly and die only at FPGA access);
- per-service parity assertions against the shipped `rootfs.tar`;
- a functional test of the timezone hook against hostile network answers.

[`scripts/check-abi.sh`](scripts/check-abi.sh) runs the full SONAME/loader checklist from
[`docs/abi-contract.md`](docs/abi-contract.md).

| Workflow | Trigger | Job |
|---|---|---|
| `build.yml` | push to `master`, PRs | Both kernels, the image, the parity and ABI suite, patch and defconfig lints |
| `release.yml` | `v*` tags | Clean rebuild, release archive, draft Release |
| `publish-db.yml` | release published | Regenerate and deploy `db.json` |
| `reproducibility.yml` | manual | Two independent builds must be byte-identical |
| `de25-build.yml` | manual | The DE25-Nano build |
| `renovate-hash-sync.yml` | Renovate PRs | Refresh companion hashes a version bump leaves stale |
| `renovate-validate.yml` | config changes | Catch an invalid Renovate config, which Renovate would otherwise skip silently |
| `fork-sync.yml` | weekly | Track new commits on upstream's kernel fork |
| `lint.yml` | push, PRs | `actionlint` and `shellcheck` |
| `cache-prune.yml` | PR closed, daily | Free the Actions cache a closed PR leaves behind |

Rationale and incident history: [`docs/ci.md`](docs/ci.md). Reproducibility:
[`docs/reproducibility.md`](docs/reproducibility.md). Renovate:
[`docs/renovate.md`](docs/renovate.md).

---

## Documentation map

| Start here | |
|---|---|
| [`PLAN.md`](PLAN.md) | Goals, ABI contract, design rationale, risks |
| [`TASKS.md`](TASKS.md) | Phase-by-phase plan with acceptance criteria |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Before changing anything |
| [`docs/user/`](docs/user/) | Running it on real hardware |
| [`docs/decisions/`](docs/decisions/) | The ADRs |

| Kernel | |
|---|---|
| [`docs/patch-provenance.md`](docs/patch-provenance.md) | Every carried patch: origin, upstream status, disposition |
| [`docs/kernel-recon/`](docs/kernel-recon/) | The per-commit reconciliation and its pipeline |
| [`docs/kernel-config-deltas.md`](docs/kernel-config-deltas.md) | Every kernel-config divergence from stock |
| [`docs/rt-beta-kernel.md`](docs/rt-beta-kernel.md) | The `PREEMPT_RT` 7.2 variant |
| [`docs/kernel-export.md`](docs/kernel-export.md) | Exporting to a `Linux-Kernel_MiSTer`-style tree |
| [`docs/dwc2-usb-irq.md`](docs/dwc2-usb-irq.md) | USB host interrupt load and polling fixes |

| Contracts | |
|---|---|
| [`docs/abi-contract.md`](docs/abi-contract.md) | What the stock binary needs from kernel and rootfs |
| [`docs/boot-chain.md`](docs/boot-chain.md) | The U-Boot contract |
| [`docs/downloader-contract.md`](docs/downloader-contract.md) | How the Downloader decides to update |
| [`docs/package-manifest.md`](docs/package-manifest.md) | Stock's SONAMEs mapped to packages |
| [`docs/stock-inventory/`](docs/stock-inventory/) | The audited stock inventory |
| [`docs/uboot-mainline-port.md`](docs/uboot-mainline-port.md) | Mainline U-Boot (in progress, ships nowhere) |
| [`docs/de25-nano-overview.md`](docs/de25-nano-overview.md) | DE25-Nano entry point |

**Parity audits:** [stock reconciliation](docs/stock-reconciliation.md) ·
[wifi](docs/wifi-parity.md) · [bluetooth](docs/bluetooth-parity.md) ·
[firmware](docs/firmware-parity.md) · [init](docs/init-parity.md) ·
[usb-automount](docs/usb-automount-parity.md) · [netfs](docs/netfs-parity.md) ·
[samba](docs/samba-parity.md) · [ssh-ftp](docs/ssh-ftp-parity.md) ·
[midi/mt32](docs/midi-mt32-parity.md) · [rtc](docs/rtc-parity.md) ·
[util-linux](docs/util-linux-parity.md)

**Engineering:** [version delta](docs/version-delta.md) · [size budget](docs/size-budget.md) ·
[Main_MiSTer shared libs](docs/main-shared-libs.md) · [DualSense tooling](docs/dualsense-tooling.md) ·
[debug tooling (temporary)](docs/debug-tooling.md)

---

## Contributing and licensing

Contributions open **once the Phase 4 publication gate is passed**. When they do, they
follow [`CONTRIBUTING.md`](CONTRIBUTING.md): patch provenance, DCO sign-off, reproducibility,
no vendored binaries, hash-pinned sources, and no behaviour changes hidden in build fixes
([`PLAN.md` §13](PLAN.md)).

- **Repository code:** GPLv3 ([`LICENSE`](LICENSE)).
- **Kernel patches** (`board/mister/*/linux-patches*/`): GPLv2.
- **Packages:** their upstream licenses; each release's `legal-info` is the authoritative SBOM.
- **MiSTer Kun artwork** (`installer-splash/`): the mascot by **HeWhoisRed**, remastered in
  8-bit form by [baxysquare/mister_kun](https://github.com/baxysquare/mister_kun). It is
  free to use and remix with attribution; see `installer-splash/upstream/LICENSE`. It is not
  GPLv3.
