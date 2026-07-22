# MiSTer Linux Modernization

**A complete, reproducible operating system for the MiSTer DE10-Nano — kernel, root
filesystem, a real-time kernel variant, a flashable SD-card image, and the update channel
that delivers them.** Built in the open from a modern Buildroot and a mainline LTS kernel,
with every MiSTer kernel patch carried in-tree as a plain `.patch` file applied to a
pristine, hash-verified kernel.org tarball.

It is a **drop-in replacement**: the unmodified, stock `MiSTer` binary and every existing
core run on it unchanged.

## What ships

| Artifact | What it is |
|---|---|
| `linux.img` + `zImage_dtb` | The OS itself — rootfs and kernel, delivered as a normal update through the **stock on-device Downloader** |
| `zImage_dtb-rt` | A **`PREEMPT_RT` kernel variant**, built by CI. Its modules ride inside the same `linux.img`, so switching kernels is a one-line `u-boot.txt` edit in either direction — no rootfs flash |
| `sdcard.img.xz` | A **complete, flashable SD card** that self-expands to the card's real size on first boot — no mr-fusion, no Windows SD installer |
| `release_YYYYMMDD.7z` | The stock-layout release archive, byte-compatible with the Downloader's expectations |
| `legal-info.tar.gz` | A **full SBOM** — every package, version, license, and upstream source tarball |
| `SHA256SUMS` + attestations | Build provenance for the image assets |
| `db.json` | The **opt-in update channel**, served from GitHub Pages — add one file to your card and releases arrive like any official update |
| An exportable kernel tree | The carried series, rendered deterministically into `Linux-Kernel_MiSTer` layout so upstream can consume the work without a second fork |

> **Status — personal use only.** Phases 0–3 are complete with hardware validation on a
> real DE10-Nano; Phase 4 (release engineering & sustainability) is in progress. Nothing
> here will be offered publicly until the sustainability commitment in
> [ADR 0014](docs/decisions/0014-sustainability-deferred-not-waived.md) is signed by a
> named maintainer. If you are trying it anyway, read
> [`docs/user/beta-testing.md`](docs/user/beta-testing.md) first.

---

## Contents

- [What ships](#what-ships)
- [The one-paragraph version](#the-one-paragraph-version)
- [Stock vs. this image, at a glance](#stock-vs-this-image-at-a-glance)
- [Project status](#project-status)
- [What this improves](#what-this-improves)
  - [1. The kernel: five years of stable releases, and a way back to mainline](#1-the-kernel-five-years-of-stable-releases-and-a-way-back-to-mainline)
  - [2. Six latent bugs found and fixed](#2-six-latent-bugs-found-and-fixed)
  - [3. Security posture](#3-security-posture)
  - [4. Storage, filesystems, and networking](#4-storage-filesystems-and-networking)
  - [5. Build, release, and supply-chain engineering](#5-build-release-and-supply-chain-engineering)
  - [6. Things that are deliberately identical to stock](#6-things-that-are-deliberately-identical-to-stock)
- [What is *not* better — the honest list](#what-is-not-better--the-honest-list)
- [How it is put together](#how-it-is-put-together)
  - [Repository layout](#repository-layout)
  - [Two kernels, one image](#two-kernels-one-image)
  - [The initramfs that deleted a kernel patch](#the-initramfs-that-deleted-a-kernel-patch)
  - [The full SD-card image](#the-full-sd-card-image)
- [Building it yourself](#building-it-yourself)
- [Verification & CI](#verification--ci)
- [Releases & distribution](#releases--distribution)
- [Goals](#goals)
- [Documentation map](#documentation-map)
- [Contributing](#contributing)
- [License layering](#license-layering)

---

## The one-paragraph version

MiSTer's operating system ships as an opaque archive containing a **375 MiB ext4 image**
(93% full) built from **Buildroot 2021.02.4** with **glibc 2.31**, running **Linux
5.15.1** — a kernel forked in November 2021 that has **never merged a single 5.15.y
stable release**. There is no public build recipe, no CI, no SBOM, and no update path for
any of it. This project rebuilds the whole thing from **Buildroot 2026.05.1** and a
**mainline 6.18 LTS kernel** in a public repository, with reproducible builds, a
signed-hash supply chain, an eight-workflow CI pipeline, and a per-commit reconciliation
of the entire kernel fork — then ships it through the same update channel users already
have, alongside a real-time kernel variant and a flashable card image that stock has no
equivalent of. All of it boots the **unmodified, stock `MiSTer` binary** and every
existing core.

The core posture: **prove parity first, then improve.** Carry the smallest possible delta
against a pristine kernel.org tree, and hand each subsystem back to mainline as soon as
mainline can hold it.

---

## Stock vs. this image, at a glance

| | Stock MiSTer | This project |
|---|---|---|
| **Kernel** | 5.15.1, forked Nov 2021, **zero** `5.15.y` stable updates ever merged; 5.15 EOL Oct 2026 | **6.18.39 LTS**, on a live `.y` line with security backports |
| **Kernel delta** | 108 commits on a squashed-import fork with no shared ancestry with mainline — so no `merge-base`, and no per-commit disposition | **31 patch files** against a pristine tarball, each with provenance, upstream status, and an evidence-backed record |
| **Buildroot** | 2021.02.4 | **2026.05.1** (~5 years of upstream work) |
| **glibc / gcc** | 2.31 / gcc 10-era | **2.43 / 14.4.0** |
| **OpenSSL** | **1.1.1 — EOL since 2023-09-11**, no upstream fixes since | **3.6.3** |
| **OpenSSH** | 8.6p1 | **10.3p1** |
| **Samba** | ~4.14 | **4.24.3** |
| **Python** | 3.9 | **3.14.6** |
| **SSH host keys** | **Identical on every MiSTer on Earth**, baked into the public download, dated 2016 | **Generated per device on first boot**, persisted to the FAT card ([ADR 0015](docs/decisions/0015-per-device-ssh-host-keys.md)) |
| **Wi-Fi drivers** | Six out-of-tree vendor forks; several chips have no WPA3 | **Mainline-first** (`rtw88`/`rtw89`/`rtl8xxxu`/`mt7921u`…), out-of-tree only where mainline still can't drive the chip. **WPA3/SAE verified on hardware** ([ADR 0016](docs/decisions/0016-mainline-first-wifi-drivers.md)) |
| **NTFS** | Not supported at all | `ntfs3` in-kernel module + `ntfs-3g` automount |
| **Image size** | 375 MiB, **13.6% free** ("93% full") | 512 MiB, **~60% free** — ~50% with the temporary debug block currently in tree ([`docs/size-budget.md`](docs/size-budget.md)) |
| **Rootfs build recipe** | Not published — the image is distributed as a finished artifact | This repository |
| **Reproducible** | No published recipe, so unverifiable | **Byte-identical across independent builds**, proven by CI ([`docs/reproducibility.md`](docs/reproducibility.md)) |
| **SBOM / license manifest** | None published | Full `legal-info` bundle published with every release |
| **Dependency updates** | Manual, ad-hoc | **Renovate**, covering kernel pins, firmware, and every package hash |
| **Real-time kernel** | No | **`PREEMPT_RT` variant** built by CI, booted on hardware |

Every number in that table is sourced. The versions come from the *shipped artifacts* on
both sides — stock from the extracted stock `linux.img`, ours read off the built tree.

**On version drift, since this table cites documents that can lag it.** The ground truth
for "ours" is always the build pins — `BUILDROOT_VERSION` in the `Makefile` and
`configs/mister_de10nano_defconfig` — plus whatever Buildroot's own `.mk` files resolve
to at that pin. The documents below are **dated analyses**, not a live mirror of those
pins: a Renovate bump or a Buildroot line bump moves a package without rewriting the
prose that reasoned about it. Where a document is behind the pin it now says so at the
top, and lists what has and has not been re-checked. **Nothing in CI asserts package
versions**, so that gap is closed by reading, not by a test — see
[the honest list](#what-is-not-better--the-honest-list).

Full detail with citations: [`docs/version-delta.md`](docs/version-delta.md) (the stack,
re-read most recently), [`docs/package-manifest.md`](docs/package-manifest.md) (the
251-SONAME mapping, established against Buildroot 2026.02.3),
[`docs/verification/stock-release-20250402.md`](docs/verification/stock-release-20250402.md)
(the stock side, fixed forever — stock does not move).

---

## Project status

| Phase | State | What that means |
|---|---|---|
| **0 — Recon & decisions** | ✅ Complete | Patch triage, ABI-contract verification, five open questions decided (ADRs 0010–0014) |
| **1 — Kernel & initramfs** | ✅ Complete | 6.18 LTS pinned; all 31 patches apply cleanly; `zImage_dtb` builds warning-free, boots under QEMU **and on real hardware** — from the **CI-built artifact**, not a local build |
| **2 — Rootfs & testing** | ✅ Complete | Buildroot 2026.05.1, glibc 2.43, reproducible ext4 image with full SBOM; menu and cores load on hardware — the ABI contract holds *in practice*, not just on paper |
| **3 — Module packages & HW matrix** | ✅ Complete | Wi-Fi, Bluetooth, controllers and special devices packaged and hardware-validated; the remaining matrix rows (Samba, MIDI) are build/CI-verified only |
| **4 — Release & sustainability** | 🔄 In progress | CI/CD, `db.json` distribution, beta program, governance, publication gate |
| **5 — Full SD image & U-Boot** | 🔄 Partially landed | `sdcard.img` builds, and `release.yml` verifies it with `scripts/check-sdcard.sh` ([ADR 0020](docs/decisions/0020-sdcard-exfat-reformat-installer.md)); U-Boot-from-source (P5.1/P5.2) not started, and the SD image has not been flashed to a fresh card on hardware (P5.4) |

### Hardware validation ledger

Validated on **one real DE10-Nano**, booting CI-built artifacts:

| Subsystem | Status |
|---|---|
| Boot to MiSTer menu, cores load | ✅ Confirmed |
| All out-of-tree modules present, no BUG/Oops/panic | ✅ Confirmed |
| Bluetooth — firmware load + controller pairing | ✅ Confirmed |
| Wi-Fi — **WPA3/SAE (PMF required)** 5 GHz auto-connect via mainline `rtw88` | ✅ Confirmed |
| Downloader over HTTPS | ✅ Confirmed |
| **`PREEMPT_RT` kernel (7.2-rc4) boots and runs MiSTer** | ✅ Confirmed 2026-07-20 |
| Samba, MIDI | ⚠️ Build/CI-verified only — **not** exercised on hardware |
| RT latency measurement | ⏳ Not yet taken |

Test logs live in [`docs/testlogs/`](docs/testlogs/). Anything not listed above should be
treated as unverified in practice.

---

## What this improves

### 1. The kernel: five years of stable releases, and a way back to mainline

Stock forked Linux 5.15.1 in November 2021 and **never took a single subsequent 5.15.y
stable release**. 5.15 itself reaches end-of-life in October 2026. This project tracks
**6.18 LTS** (currently 6.18.39), pinned by version and SHA-256 against kernel.org, with
Renovate opening a PR on every `.y` bump.

The interesting part is not the version number — it's the **shape of the delta**. The
fork's **123 reconciled commits** (108 on the shipped `MiSTer-v5.15` branch plus 15
residue commits that existed only on the older v5.14/v5.13.12 branches) are down to
**31 carried patch files**. Every remaining drop is either verifiably in mainline 6.18,
replaced by a maintained package, or recorded as a deliberate decision.

**Every commit in the fork was independently reconciled**, each with a machine-readable,
evidence-backed disposition record, **100% of them verified by a second independent
review pass** ([`docs/kernel-recon/`](docs/kernel-recon/)). That reconciliation caught and
closed several silent gaps the original triage had misclassified — Joy-Con combining, the
DualSense player-ID and mic-mute/`BTN_Z` interfaces, stock NES/Famicom A/B button mapping,
Pro-Controller-clone tolerance, fake-CSR Bluetooth dongle detection, and two config drifts
(macvlan, `xpad`-as-module) — now carried as patches `0032`–`0037` plus config parity.

Because the kernel is *stored* as `{pinned tarball + ordered series}` rather than as a
materialized tree, [`scripts/export-kernel-tree.sh`](scripts/export-kernel-tree.sh) can
render it back into a `Linux-Kernel_MiSTer`-style git tree deterministically — the export
is a **build output**, not a second source of truth, so upstream can consume the work
without this repo forking the kernel a second time. A separate
`linux-patches-upstream/` series carries what that exported tree needs but our image
deliberately does not (the `loop=` boot patch — see below).

### 2. Six latent bugs found and fixed

These are **not** forward-porting regressions. Every one is present verbatim in the 5.15
fork, and therefore in **every MiSTer image shipped to date**. They surfaced only because
forward-porting forces you to actually read code that has been copied forward untouched
since 2021.

| | Where | The bug | Status |
|---|---|---|---|
| **B1** | GameCube adapter | **Use-after-free on unplug.** Teardown cancels the rumble work item but never the four per-port `work_connect` items, then `kfree()`s the adapter the handler `container_of()`s back into. Same defect on the probe error path. | ✅ Fixed |
| **B2** | `MiSTer_fb` | **`memremap()` returns `NULL` on failure, not an `ERR_PTR`** — the code tests `IS_ERR()`, which is false for NULL, so a failed mapping falls through with `screen_base` unset. Oops on the first fbcon draw. | ✅ Fixed |
| **B3** | MiSTer audio SPI | `class_create()`/`device_create()` return `ERR_PTR`, never `NULL` — so the `== NULL` checks are dead code and a *failed* `device_create()` was treated as success. | ✅ Fixed |
| **B4** | MiSTer audio SPI | Bogus diagnostics on SPI failure: the ring length is computed from a `-1` read, so the status string you read to diagnose a broken SPI link is itself wrong — precisely when you need it. | ✅ Fixed |
| **B5** | Logitech K400 Fn | The fork's own patch reuses `SetFeature` at the wrong feature index, writing the wrong HID++ feature. | ✅ Fixed |
| **B6** | Cyclone V cpufreq | `wait_for_fsm()` passes a *mask* where `wait_on_bit()` wants a *bit number*, so it polls bit 1 instead of bit 0 — and does a plain `test_bit()` on `__iomem`. Harmless today only because the call returns immediately. | ⚠️ **Carried verbatim, deliberately** |

B6 is not fixed on purpose: making it actually *wait* changes the timing of a live PLL
reprogramming sequence, and a forward-port is the wrong place to smuggle in an untested
change to clock sequencing. It is recorded, not hidden.

Notably, **all six live in MiSTer-original or fork-modified code. None is in mainline
code.** That is the sharpest argument for the small-delta posture this project takes.

Full write-up with the reasoning for each: [`docs/patch-provenance.md` §10](docs/patch-provenance.md).

### 3. Security posture

- **OpenSSL 1.1.1 → 3.6.3.** Stock ships a TLS library that has been **end-of-life since
  2023-09-11** and has received no upstream fixes since. This is the single strongest
  security argument for the whole project, and it is a plain, checkable fact.
- **Per-device SSH host keys.** Every stock MiSTer ships the *same* host keys, baked into
  the public release archive, dated 2016-12-31, on a read-only root that makes
  `ssh-keygen -A` a no-op. The private host key of every MiSTer on Earth is public and
  identical — so SSH server impersonation is trivial and produces **no host-key warning**.
  This image generates unique keys on first boot and persists them to an ext4 image on the
  FAT partition, **reusing stock's own proven mechanism** for Bluetooth pairing keys.
  ([ADR 0015](docs/decisions/0015-per-device-ssh-host-keys.md))
- **OpenSSH 8.6p1 → 10.3p1**, **Samba ~4.14 → 4.24.3**, **BlueZ → 5.79**,
  **wpa_supplicant 2.9 → 2.11** — the network-facing surface, several release cycles of
  hardening each.
- **Python 3.9 → 3.14.6** — the on-device interpreter that runs the Downloader and
  community scripts (compatibility tested; see [`docs/python-compat.md`](docs/python-compat.md)).
- **An actual update path.** Renovate tracks the kernel, firmware, and every pinned
  package; CI proves each bump still builds and still passes the parity suite. Stock's
  security model is "the image is frozen."

What has *not* changed: **the root password is still `1`**, deliberately, for stock
parity. That is publicly known and always has been. See
[the FAQ](docs/user/faq.md#whats-the-default-root-password-and-is-that-a-problem) for the
plain-language version of what that means on an untrusted network.

### 4. Storage, filesystems, and networking

| Capability | Stock | Here |
|---|---|---|
| **exFAT** | Out-of-tree Samsung driver (also handled FAT12/16/32) | **Mainline `exfat`**, with the Samsung symlink extension carried as patch `0031` ([ADR 0010](docs/decisions/0010-drop-out-of-tree-exfat.md), [ADR 0019](docs/decisions/0019-exfat-symlinks-carried-patch.md)) |
| **NTFS** | Not supported | `ntfs3` module + `ntfs-3g` automount via util-linux `mount` ([ADR 0013](docs/decisions/0013-ntfs3-and-all-ext4-variant.md)) |
| **USB automount** | Debian `usbmount` 0.0.24 | Buildroot `usbmount`, functionally identical, **plus NTFS** ([`docs/usb-automount-parity.md`](docs/usb-automount-parity.md)) |
| **CIFS kernel mounts** | No `mount.cifs` shipped | `cifs-utils` included — a deliberate, documented **beyond-parity** addition for community storage scripts ([`docs/netfs-parity.md`](docs/netfs-parity.md)) |
| **Wi-Fi** | Six out-of-tree vendor forks | Mainline drivers wherever mainline covers the chip; out-of-tree kept only for the rest. **WPA3/SAE proven working** where the fork it replaced could not do WPA3 at all |

### 5. Build, release, and supply-chain engineering

This is the half of the project that has no stock counterpart at all, because stock
publishes no build recipe.

- **No vendored Buildroot, ever.** The `Makefile` downloads the pinned release, verifies
  its SHA-256 against **upstream's GPG-signed release manifest**, unpacks it under
  `work/`, and forwards every target into it. A hash mismatch refuses to unpack and tells
  you — at length — why pasting the new hash in is the wrong fix.
- **Byte-identical reproducible builds.** Two independent builds of the same commit
  produce identical `linux.img` and `zImage_dtb`, and a dedicated CI workflow exists to
  prove it. This is what makes the four layered build caches trustworthy as *inputs only*.
  ([`docs/reproducibility.md`](docs/reproducibility.md))
- **Full SBOM.** Every release ships `legal-info.tar.gz`: `manifest.csv` (package,
  version, license, upstream URL), license texts, and the upstream source tarball of
  every package conveyed — the GPL accompanying-source obligation, discharged properly.
- **Provenance attestation** on the release images.
- **No binaries in git. Ever.** Firmware, payloads, and stock blobs are fetched at build
  time, pinned by commit or release **and** hash.
- **Renovate** ([`renovate.json`](renovate.json), [`docs/renovate.md`](docs/renovate.md))
  with a companion hash-sync workflow, because several pins need a *companion* hash that
  a naive version bump would leave stale. Kernel `-rc` bumps **fail closed** on a missing
  hash by design, requiring a human pin.

### 6. Things that are deliberately identical to stock

Parity is a feature, and most of the work is invisible for exactly that reason. This image
reproduces stock's behaviour — not merely its file list — for: the `MiSTer` binary's ABI
and every SONAME it links, the boot chain and U-Boot contract, `/media/fat` mount flags
(`sync,dirsync,noatime,nodiratime` — mounting async would be a real power-off corruption
regression), the read-only root with the login-time `remount,rw`, the Bluetooth key store,
the firmware set, the init-script set, `busybox` applet coverage, the RTC, MIDI/MT-32,
Samba, SSH/FTP, `/MiSTer.version` semantics, and the Downloader's update contract.

Each of those has its own audited parity document — see the
[documentation map](#documentation-map). The `uboot.img` in the default release channel is
shipped **byte-identical to stock's**, fetched by hash.

---

## What is *not* better — the honest list

- **One known regression.** The Logitech **G923 *PlayStation* variant** loses force
  feedback and range control; steering, pedals and buttons still work as a plain joystick.
  The G923 **Xbox** variant and all G29/G27/G25 wheels are fully supported with force
  feedback intact. ([`docs/patch-provenance.md` §9.3](docs/patch-provenance.md))
- **Not all hardware is validated.** Samba and MIDI are build- and CI-verified only. One
  board, one set of peripherals. The matrix in [`docs/testlogs/p3-matrix.md`](docs/testlogs/p3-matrix.md)
  is the truth; this README is a summary of it.
- **This forward-port has already shipped one real bug, on hardware.** Early builds
  **auto-overclocked the board to 1.2 GHz on boot** and produced hard hangs. The carried
  socfpga overclock patch was written against 5.15, where `CPUFREQ_BOOST_FREQ` kept the
  governor off the boost rows by default; on 6.18 the default `policy->max` resolves
  differently, so the overclock became default-**on**. It applied cleanly, compiled clean,
  and behaved differently. Fixed in PR #24 — proper `->set_boost`, boost-only 1000/1200 MHz
  rows, 800 MHz default — and the board has been stable since. **The lesson generalises:
  any other 5.15-era patch we carry can have the same class of defect**, and no amount of
  CI catches a silent semantic change to a kernel flag. This is the strongest argument
  for the small-delta posture, and the reason the hardware list stays short.
- **RT is a developer variant.** `PREEMPT_RT` boots and runs on hardware, but **no latency
  measurement has been taken yet** — so there is currently *no evidence* it improves
  anything for a normal user. It exists for testing, not for daily driving.
- **Debug tooling is temporarily in-tree.** `gdb`/`strace`/`perf`/`rt-tests` and
  `CONFIG_COREDUMP` are enabled for two investigations. One of them — a field hard-hang —
  **closed on 2026-07-21**; the RT latency measurement has not been taken, so the block
  stays for now. It costs image size and diverges from stock's config, and is designed to
  revert as one unit. ([`docs/debug-tooling.md`](docs/debug-tooling.md))
- **The sustainability gate is not met.** Nobody has yet signed up, in writing, to track
  `6.18.y` security releases through end-of-life. Until that happens this is a personal
  project, and saying otherwise would be the one claim that undermines all the others.
  ([ADR 0014](docs/decisions/0014-sustainability-deferred-not-waived.md))
- **Version numbers drift, and two parity analyses are currently behind the pins.**
  Every figure here was read off the built tree at the time of writing, but **nothing in
  CI asserts a package version**, so a Renovate or Buildroot-line bump can move a package
  out from under the document that reasoned about it. That has already happened: the
  Buildroot 2026.05.1 bump moved **Samba 4.23.8 → 4.24.3** and **ProFTPD 1.3.8d →
  1.3.9a** without re-running the P3.6 / P3.7 audits that gated those packages. Both
  documents now say so at the top, with the specific unchecked question named. The
  defconfig and `Makefile` pins are the ground truth; the prose is a dated reading of it.

---

## How it is put together

### Repository layout

```
Makefile                 wrapper: fetches + hash-verifies Buildroot, forwards targets
Config.in / external.mk  BR2_EXTERNAL definition for the 16 in-tree packages
configs/                 mister_de10nano_defconfig  (the shipped image)
                         mister_kernel_defconfig    (kernel-only base, shared by variants)
                         mister_rt.fragment         (PREEMPT_RT / 7.x delta)
                         mister_initramfs_defconfig (stage-1 cpio)
                         mister_installer_defconfig (SD-card installer cpio)
board/mister/de10nano/
  linux.config           minimal kernel defconfig  (an absent CONFIG_X is NOT "off")
  linux-patches/         the 31 carried MiSTer kernel patches, + series
  linux-patches-beta/    symlinks to the above + 5 re-anchored real copies for 7.x
  linux-patches-upstream/what the exported tree carries but our image must not
  rootfs-overlay/        init scripts, sshd wiring, MiSTer-specific files
  post-build.sh          /MiSTer.version stamping, parity fixups
  post-image.sh          linux.img assembly + contract checks
package/                 16 packages: Realtek Wi-Fi, xone, libchdr, lzma-sdk, midilink, munt…
scripts/                 the verification suite, hash-sync, SD-card builder, kernel export
docs/                    ADRs, parity audits, the kernel reconciliation, user docs
.github/                 8 workflows + 4 composite actions
```

### Two kernels, one image

The DE10-Nano's Cyclone V is a dual-core **Cortex-A9 (ARMv7-A, 32-bit)** — there is no
AArch64 path on this silicon, and `PREEMPT_RT` cannot be a boot-time toggle on ARM32. So
RT must be a separately compiled kernel image. `PREEMPT_RT` for 32-bit ARM merged into
mainline in **Linux 7.1**, which means on 7.2 it is a plain kconfig option with **no
out-of-tree RT patch to carry**.

The design ([ADR 0021](docs/decisions/0021-rt-kernel-first-class-ci.md)): `make rt` runs a
**kernel-only** Buildroot build into `output-rt/`, hard-asserting `CONFIG_PREEMPT_RT=y` in
the result, then stages its depmod'd module tree into an overlay that the next `make all`
folds into the **one shipped `linux.img`**. You get `zImage_dtb` and `zImage_dtb-rt` as
separate boot images, both of whose modules live in the same rootfs, selected on-device
via `u-boot.txt`. CI builds the variant on **every gated run**, so a PR that breaks
`make rt` goes red instead of rotting silently.

### The initramfs that deleted a kernel patch

Stock patches `init/do_mounts.c` so the **kernel itself** parses a `loop=` boot parameter,
mounts `/media/fat`, and loop-mounts `linux/linux.img` as the root filesystem. That is a
patch to the most delicate part of early boot, carried forever, for a job userspace does
better.

This project replaces it with a **two-stage boot**: a tiny BusyBox initramfs, embedded in
the kernel via `CONFIG_INITRAMFS_SOURCE`, does the mount dance in a shell script — with
`rootwait` retries, vfat-then-exfat probing, and a rescue shell on failure. One patch
deleted, one whole class of boot failure made debuggable.

The details matter more than they look: `-o sync,dirsync` is not a tuning choice (async
would be a real power-off-corruption regression), the loop **device** must stay writable
even though the rootfs is mounted read-only (or `/etc/profile`'s login-time
`remount,rw` breaks), and `mount -o move` is required because BusyBox `mount` has no long
options. All of it is annotated in [`PLAN.md` §5](PLAN.md) and
[`docs/loop-boot-6.18.md`](docs/loop-boot-6.18.md).

### The full SD-card image

`make sdcard` produces a complete, `dd`-able `sdcard.img` — a two-partition MBR with the
data partition on `p1` and a type-`0xA2` partition carrying `uboot.img` raw at its start,
per the SPL contract. The image ships **small**, so the compressed asset stays small and
the write is fast; a throwaway installer OS then **reformats the card to exFAT at the
device's real size on first boot** — because Linux cannot grow exFAT in place, and exFAT
is what every mr-fusion'd card in the wild uses. That is not an invention: it is
mr-fusion's own mechanism, adopted rather than replaced, per the standing principle of
reusing a proven reference implementation in anything on the boot path.
([ADR 0020](docs/decisions/0020-sdcard-exfat-reformat-installer.md))

It ships as a **separate release asset**, never inside `release_*.7z` and never referenced
by `db.json`, because its blast radius is the bootloader. The payload it installs is
inventoried against real mr-fusion output in
[`docs/verification/sdcard-payload.md`](docs/verification/sdcard-payload.md).

---

## Building it yourself

```sh
make                            # prints help — deliberately NOT a build
make mister_de10nano_defconfig  # load the config
make all                        # build (first run bootstraps a cross-toolchain — hours, not minutes)
```

Two things that will bite you otherwise:

- **`make` on its own prints help rather than building.** A reflexive bare `make` in a
  Buildroot tree with no config starts a full **x86** toolchain build that nothing here
  wants. Use `make all` — it runs the stage-1 initramfs build first, then the image.
- **Do not pass `-j`.** Buildroot's top level is not parallel-safe; it parallelises each
  package internally, defaulting to your CPU count. CI runs a bare `make all`.

### Useful targets

| Target | What it does |
|---|---|
| `make all` | The shipped image: `linux.img` + `zImage_dtb` |
| `make rt` | Kernel-only `PREEMPT_RT` build → `zImage_dtb-rt` + module overlay |
| `make sdcard` | Full `sdcard.img(.xz)` — run **after** `make rt` then `make all` |
| `make initramfs` | Stage-1 cpio only, and print its size |
| `make menuconfig` / `linux-menuconfig` | Interactive Buildroot / kernel config |
| `make savedefconfig` | Write the config back to the defconfig (**always** do this after editing) |
| `make buildroot-verify` | Download + SHA-256-verify the pinned Buildroot tarball |
| `make buildroot-showsig` | Print upstream's GPG-signed manifest — the *only* valid hash source |
| `make legal-info` | Generate the SBOM |
| `make clean` / `distclean` | Buildroot's own meanings, applied across every output dir (`dl/` is kept — it's a shared cache) |

### Host requirements

Standard build tools (`gcc`, `make`, `bc`, `flex`, `bison`, `cpio`, `rsync`, `unzip`,
`wget`/`curl`, `python3`), plus `dtc`, `qemu-user`/`qemu-system-arm`, and `shellcheck` for
the test and inventory scripts.

**One sharp edge.** Buildroot refuses to build if `/usr/bin/install` is **uutils coreutils
0.8.0** — it detects that exact version and rejects it (upstream bug
[uutils/coreutils#12166](https://github.com/uutils/coreutils/issues/12166)).
Debian/Ubuntu's `coreutils-from-uutils` package installs precisely that as the default
`install`. You do **not** need to fix this yourself and you should not need `sudo`: the
Makefile detects it and transparently shims a GNU `install` into `PATH` for Buildroot only
(`work/.hostshim/`), touching nothing outside this repo. It is inert on a host whose
`install` is already GNU, and fails fast with a clear message if no GNU `install` exists
at all.

---

## Verification & CI

Nothing here is asserted by hand. The parity claims above are backed by scripts that run
on every push and pull request.

### The test suite

[`scripts/ci-tests.sh`](scripts/ci-tests.sh) is one command that runs the whole
non-hardware suite and prints a self-contained digest last (`| tail -n 30` tells you what
broke and why, without grepping):

- the image-contract checks — `check-zimage-dtb.sh`, `check-linux-img.sh`,
  `check-size-budget.sh`
- the structural initramfs checks, plus a **full QEMU boot test of the initramfs `/init`**
  (booted six times, across the failure paths)
- an ABI smoke test running the **stock `MiSTer` binary** under `qemu-user` against the
  built rootfs: dynamic linking must resolve clean, and it must die at FPGA access and not
  one instruction earlier
- per-service parity assertions harvested from each Phase 3 parity document, checked
  against the shipped `rootfs.tar` — not against `output/target/`

Alongside it, [`scripts/check-abi.sh`](scripts/check-abi.sh) runs the full
SONAME/loader checklist from [`docs/abi-contract.md`](docs/abi-contract.md). The overlap on
the two highest-value gates is deliberate.

### The pipeline

| Workflow | Trigger | Job |
|---|---|---|
| `build.yml` | push to `master`, every PR | Kernel-variant matrix, then the image, then the parity + ABI suite — plus the patch-header lint and the kernel-defconfig sync check |
| `release.yml` | `v*` tags | Rebuilds from scratch (never adopts a CI run), assembles `release_YYYYMMDD.7z`, drafts the GitHub Release |
| `publish-db.yml` | release *published* | Regenerates `db.json`, schema-checks it, deploys it to GitHub Pages |
| `reproducibility.yml` | manual dispatch | Proves two independent builds are byte-identical. Manual on purpose: it is a double build, and its input caches are only warm after `build.yml` has run |
| `renovate-hash-sync.yml` | Renovate PRs | Refreshes companion hashes a version bump leaves stale |
| `renovate-validate.yml` | config changes | An invalid Renovate config makes Renovate skip the repo **silently** — this is the only signal you would ever get |
| `fork-sync.yml` | weekly | Diffs the last-reconciled fork commits against upstream's live HEADs and keeps one issue updated with the backport queue |
| `lint.yml` | push, PR | `actionlint` over the workflows, `shellcheck` over `scripts/**` and the composite actions' `run:` bodies |

The full rationale, incident history, and measured numbers live in
[`docs/ci.md`](docs/ci.md) — the workflows keep the imperative and the run ID, that
document keeps the narrative and the "we tried X and it failed."

---

## Releases & distribution

Release artifacts are published as **GitHub Release assets**; no binaries live in git.
The main set is seven files (the Downloader-contract set: the `release_YYYYMMDD.7z`,
`linux.img`, `zImage_dtb`, both `.config`s, `legal-info.tar.gz`, `SHA256SUMS`), plus three
`-rt` files per kernel variant, plus the separately contracted `sdcard.img.xz`.

Distribution is **opt-in and requires zero cooperation from anyone**: a community
`db.json`, served from GitHub Pages, that the standard on-device Downloader reads. Add one
file to your card and future releases arrive the same way official updates do; remove it
and the next official update puts stock back. Rolling back is always safe.

One subtlety worth calling out because getting it wrong bricks the update loop: stock's
Downloader compares versions with a **strict string inequality**, not an ordering, and
`/MiSTer.version` is derived from `SOURCE_DATE_EPOCH` — which reproducible builds pin to a
constant. Two releases from the same Buildroot pin would therefore have carried an
*identical* version string, and a user would never be offered the newer one. Both the
image stamp and the published version now derive from the tagged release date instead.
([ADR 0018](docs/decisions/0018-db-json-version-is-release-date-driven.md),
[`docs/db-json-versioning.md`](docs/db-json-versioning.md))

Start here if you want to run it: [`docs/user/onboarding.md`](docs/user/onboarding.md) ·
[`docs/user/rollback.md`](docs/user/rollback.md) ·
[`docs/user/faq.md`](docs/user/faq.md) ·
[`docs/user/serial-recovery.md`](docs/user/serial-recovery.md)

---

## Goals

| # | Goal |
|---|------|
| G1 | A `linux.img` + `zImage_dtb` that boots the **unmodified, stock** `MiSTer` binary |
| G2 | Modern kernel on a supported LTS with a real security-update path |
| G3 | Modern package set (Buildroot 2026.05) with a real security-update path |
| G4 | **No separate kernel repo.** All kernel patches live as `.patch` files in the Buildroot external tree, applied to a pristine kernel.org tarball |
| G5 | Fully reproducible: pinned Buildroot, pinned kernel + hash, checked-in `.config`, published SBOM |
| G6 | Release artifacts published as **GitHub Release assets**. No binaries in git. Ever. |
| G7 | Opt-in distribution via a community `db.json` — zero cooperation required |

---

## Documentation map

**Start here**

| Document | Read it when |
|---|---|
| [`PLAN.md`](PLAN.md) | You want the goals, the ABI contract, the design rationale, and the risk analysis |
| [`TASKS.md`](TASKS.md) | You want the phase-by-phase execution plan with acceptance criteria |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | You are about to change something |
| [`docs/user/`](docs/user/) | You are running this on real hardware |

**The kernel**

| Document | Contents |
|---|---|
| [`docs/patch-provenance.md`](docs/patch-provenance.md) | Every carried patch: origin, upstream status, disposition |
| [`docs/kernel-recon/`](docs/kernel-recon/) | The full per-commit reconciliation — 123 evidence-backed records, the ledger, the silent-regression triage, and the reproducible pipeline that produced them |
| [`docs/kernel-config-deltas.md`](docs/kernel-config-deltas.md) | Every kernel-config divergence from stock, and why |
| [`docs/rt-beta-kernel.md`](docs/rt-beta-kernel.md) | The `PREEMPT_RT` / 7.x variant |
| [`docs/loop-boot-6.18.md`](docs/loop-boot-6.18.md) | Why the fork's `loop=` patch cannot be ported to 6.18, what porting it would cost, and what we did instead — written for whoever maintains the fork |
| [`MISTER-KERNEL-PATCH-RECON.md`](MISTER-KERNEL-PATCH-RECON.md) | The task spec the reconciliation was executed from |

**The contracts we must not break**

| Document | Contents |
|---|---|
| [`docs/abi-contract.md`](docs/abi-contract.md) | What the kernel and rootfs must honor for the stock binary to run |
| [`docs/boot-chain.md`](docs/boot-chain.md) | U-Boot contract and its kernel-config implications |
| [`docs/downloader-contract.md`](docs/downloader-contract.md) | How the on-device Downloader decides to update |
| [`docs/package-manifest.md`](docs/package-manifest.md) | All 251 stock SONAMEs mapped to a package, with major-bump flags |
| [`docs/stock-inventory/`](docs/stock-inventory/) | The audited inventory of the stock image everything above is measured against |

**Parity audits** — one per subsystem:
[bluetooth](docs/bluetooth-parity.md) ·
[wifi](docs/wifi-parity.md) ·
[firmware](docs/firmware-parity.md) ·
[init](docs/init-parity.md) ·
[usb-automount](docs/usb-automount-parity.md) ·
[netfs](docs/netfs-parity.md) ·
[samba](docs/samba-parity.md) ·
[ssh-ftp](docs/ssh-ftp-parity.md) ·
[midi/mt32](docs/midi-mt32-parity.md) ·
[rtc](docs/rtc-parity.md) ·
[util-linux](docs/util-linux-parity.md)

**Engineering**

| Document | Contents |
|---|---|
| [`docs/ci.md`](docs/ci.md) | The pipeline, the caching traps, and the incident index |
| [`docs/reproducibility.md`](docs/reproducibility.md) | What byte-identical means here, and the four mechanisms that deliver it |
| [`docs/renovate.md`](docs/renovate.md) | What Renovate manages, the automerge posture, the hash rules a human must follow |
| [`docs/size-budget.md`](docs/size-budget.md) | Image headroom and where the bytes go |
| [`docs/version-delta.md`](docs/version-delta.md) | Five years of upstream movement, package by package |
| [`docs/main-shared-libs.md`](docs/main-shared-libs.md) | Shared-library coverage for `Main_MiSTer` |
| [`docs/debug-tooling.md`](docs/debug-tooling.md) | ⚠ **temporary** — the debug block and how to revert it as one unit |
| [`docs/decisions/`](docs/decisions/) | 16 ADRs: the open questions, the trade-offs, and who decided what |

---

## Contributing

Contributions are welcome **once the Phase 4 publication gate is passed**. Until then this
is a personal-use project.

When it opens, all contributions must follow the discipline in
[`CONTRIBUTING.md`](CONTRIBUTING.md): patch provenance tracking, developer sign-off (DCO),
and the standing rules from `TASKS.md` — reproducibility, no vendored binaries,
hash-pinned upstream sources, and no behaviour changes smuggled into build fixes.

See [`PLAN.md` §13](PLAN.md) for the sustainability requirements and the risk discussion
behind the gate.

---

## License layering

- **Repository code** (Buildroot external tree, scripts, overlays) — **GPLv3**, see [`LICENSE`](LICENSE)
- **Kernel patches** (`board/mister/de10nano/linux-patches*/`) — **GPLv2**, because they modify the Linux kernel
- **Packages** in `package/` — inherit their upstream licenses (GPLv2, BSD, MIT, …); the `legal-info` artifact in each release is the complete, authoritative SBOM
