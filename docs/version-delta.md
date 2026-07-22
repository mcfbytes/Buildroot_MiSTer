# Version delta — five years of upstream fixes (P2.10)

Stock MiSTer froze its entire userland at **Buildroot 2021.02.4** (glibc 2.31,
Linux 5.15.1) and has taken **no `.y` stable updates** on the kernel and few on the
packages since. This project rebases the whole stack on **Buildroot 2026.05.1** —
roughly **five years** of upstream security and correctness work, on a base with a
real update path (Renovate-tracked, P4.6/P4.7).

This is a headline reason the project exists (goals **G2/G3**: a real
security-update path), and it belongs in the release notes.

> **A note on honesty.** This document states **version deltas**, which are facts,
> and the **general** "~5 years of upstream maintenance" framing, which is true and
> defensible. It deliberately does **not** enumerate specific CVE numbers or claim a
> count of "N CVEs fixed" — those are not verified here, and an unverifiable count
> would undermine the very credibility this document exists to build. One
> end-of-life fact *is* cited because it is public and load-bearing (OpenSSL 1.1.1: <https://openssl-library.org/news/timeline/index.html>).

## The stack

> **Ours-side figures last re-read off the built tree on 2026-07-22** (kernel from
> `configs/mister_de10nano_defconfig`; package versions from `output/build/`). They move
> whenever Renovate lands a bump — when in doubt, the defconfig and `Makefile` pins are
> the ground truth and this table is a summary of them.

| Component | Stock (2021.02.4) | Ours (2026.05.1) | Note |
|---|---|---|---|
| Buildroot | **2021.02.4** | **2026.05.1** | ~5 years of the whole distro |
| Linux kernel | **5.15.1** (forked Nov 2021, **never merged a single 5.15.y**) | **6.18.39** LTS (hardware-validated on 6.18.33 and 6.18.38, prior patch releases) | on a stable `.y` line with security backports |
| glibc | **2.31** | **2.43** | backward-compatible; every stock binary still runs (proven on hardware) |
| gcc (toolchain) | 10.x era | **14.4.0** | |

The kernel jump is the sharpest: stock forked 5.15.1 and **never took any of the subsequent 5.15.y stable releases**, and 5.15 itself reaches EOL in **Oct 2026** (per kernel.org).

## Security-relevant userland movers

Versions are from the *shipped* artifacts: stock from the extracted stock
`linux.img` (`work/imgroot`), ours from the built packages.

| Package | Stock | Ours | Why it matters |
|---|---|---|---|
| **OpenSSL** | **1.1.1** (`libssl.so.1.1`) | **3.6.3** (`libssl.so.3`) | **OpenSSL 1.1.1 reached end-of-life on 2023-09-11** — stock ships a TLS library that has received **no** upstream fixes for ~2 years. This is the single strongest security argument. Major SONAME bump `1.1 → 3`. |
| **OpenSSH** | **8.6p1** | **10.3p1** | the network login surface; ~4 years and several release cycles of hardening |
| **Samba** | ~4.14 | **4.24.3** | SMB file sharing, network-facing; ~9 major-minor releases |
| **BlueZ** | 5.x (`libbluetooth.so.3`) | **5.79** | Bluetooth stack |
| **wpa_supplicant** | 2.9 | **2.11** | Wi-Fi auth |
| **Python** | **3.9** | **3.14.6** | on-device interpreter (A6) — 3.9 is itself near EOL; runs the Downloader and community scripts (compatibility tested in P3.9) |
| **dbus** | — | **1.14.10** | |

## Multimedia / library set (SONAME-compatible, still newer)

Every one of these is at a compatible major version (the ABI contract, P0.5) yet
carries years of fixes:

| Package | Ours | | Package | Ours |
|---|---|---|---|---|
| freetype | 2.14.3 | | libpng | 1.6.58 |
| Imlib2 | 1.12.5 | | alsa-lib | 1.2.15.3 |
| fluidsynth | 2.4.7 | | dbus | 1.14.10 |

## The full per-package mapping

`docs/package-manifest.md` (P0.7) carries the complete table — all 251 stock
SONAMEs mapped to a Buildroot package with its version and whether the
major bumped. The three deliberate major bumps flagged there (OpenSSL `1.1→3`,
`libtiff.so.5→6`, `libffi.so.7→8`) are handled; every other SONAME carries forward
at the same major version, which is *why* the unmodified stock `MiSTer` binary runs
unchanged (confirmed on hardware, `docs/testlogs/p2-menu.md`).

## Where we now stand *ahead* of upstream-frozen stock

The point is not just "newer once." Stock has **no** mechanism to move — the
Buildroot config that builds it is unpublished and the kernel fork takes no stable
updates. This project pins every input by hash, builds reproducibly, and wires
**Renovate** over the kernel (`board/mister/de10nano/patches/linux/linux.hash`) and Buildroot
(`BUILDROOT_VERSION`/`BUILDROOT_SHA256`) version stanzas (P4.6/P4.7), so `.y`
security bumps become a reviewed, testable PR rather than a manual re-fork. That
maintainability — not any single version number — is the deliverable.
