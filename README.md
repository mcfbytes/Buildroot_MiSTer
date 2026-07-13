# MiSTer Linux Modernization

**A reproducible, drop-in `linux.img` built from a modern Buildroot, with all kernel patches carried in-tree as Buildroot patch files.**

**Status: Phases 1–3 complete with hardware validation underway; Phase 4 in progress. This image is personal-use only until the sustainability commitment (ADR 0014) is signed by a named maintainer.**

Start with `PLAN.md` and `TASKS.md` for project context. Beta testers: see `docs/user/beta-testing.md`.

---

## What is this?

MiSTer's operating system is currently distributed as an opaque archive containing a 375 MiB ext4 image built from **Buildroot 2021.02.4** with **glibc 2.31**, running **Linux 5.15.1** — a kernel forked in November 2021 that has never merged a single 5.15.y stable release. This project replaces that image with one built from **Buildroot 2026.02 LTS** and a **mainline 6.18 LTS kernel**, in a public repository, with CI and reproducible builds.

### Project Status

- **Phase 0** (Reconnaissance & decisions): **Complete**. Patch triage, ABI contract verification, and all five open questions decided (see `docs/decisions/` ADRs 0010–0014).
- **Phase 1** (Kernel & initramfs): **Complete**. 24 patches apply cleanly to linux-6.18.38; `zImage_dtb` builds warning-free and boots under QEMU. Exit gate (P1.13): first hardware boot on DE10-Nano — **in progress**.
- **Phase 2** (Rootfs & testing): **Complete**. Buildroot 2026.02 LTS, glibc 2.42, reproducible ext4 image with full SBOM. Exit gate (P2.8): ABI contract verified on real hardware — in progress.
- **Phase 3** (Module packages & hardware matrix): **Complete**. WiFi, Bluetooth, controllers, and special devices packaged and tested. Exit gate (P3.13): hardware validation on DE10-Nano — **in progress**.
- **Phase 4** (Release & sustainability): **In progress**. Community governance files, CI/CD, beta-testing program, and publication gate.

**This is a personal-use project until Phase 4 exit** — sustainable maintenance is a gate (ADR 0014).

---

## Goals

| # | Goal |
|---|------|
| G1 | A `linux.img` + `zImage_dtb` that boots the **unmodified, stock** `MiSTer` binary |
| G2 | Modern kernel on a supported LTS with a real security-update path |
| G3 | Modern package set (Buildroot 2026.02 LTS) with a real security-update path |
| G4 | **No separate kernel repo.** All kernel patches live as `.patch` files in the Buildroot external tree and are applied to a pristine kernel.org tarball |
| G5 | Fully reproducible: pinned Buildroot, pinned kernel + hash, checked-in `.config`, published SBOM |
| G6 | Release artifacts published as **GitHub Release assets**. No binaries in git. Ever. |
| G7 | Opt-in distribution via a community `db.json` — zero cooperation required |

---

## What's different from the stock image

Beyond the kernel (5.15.1 → 6.18 LTS) and userland (Buildroot 2021.02 → 2026.02, glibc
2.31 → 2.42), the forward-port surfaced **six latent bugs that are live in every MiSTer
image shipped to date** — two of them memory-safety bugs. Five are fixed here; one is
deliberately carried unchanged pending hardware validation.

Notably, **all six live in MiSTer-original or fork-modified code. None is in mainline
code.** That is the clearest argument for this project's core posture: carry the smallest
possible delta against a pristine kernel.org tree, and hand each subsystem back to mainline
as soon as mainline can hold it. The fork's 109 commits are down to 24 carried patches.

Full detail, with evidence: [`docs/patch-provenance.md` §10](docs/patch-provenance.md) and
[`PLAN.md` §4](PLAN.md).

There is also one **known regression**: the Logitech G923 *PlayStation* variant loses force
feedback (steering, pedals and buttons still work). The Xbox variant and all G29/G27/G25
wheels are fully supported. See `docs/patch-provenance.md` §9.3.

---

## License Layering

- **Repository code** (Buildroot external tree, scripts, overlays): **GPLv3** (see `LICENSE` file)
- **Kernel patches** (under `board/mister/de10nano/linux-patches/`): **GPLv2** (they modify the Linux kernel, which is GPLv2)
- **Packages** carried in `package/`: inherit upstream licenses (typically GPLv2, BSD, MIT, etc.) — see `legal-info` artifacts in releases for the complete SBOM

---

## Getting Started

1. **Read the plan first**: `PLAN.md` §1–3 gives you the context and constraints.
2. **Read the task list**: `TASKS.md` has the phase-by-phase execution breakdown.
3. **For Phase 0 findings** (ABI contract, patch triage): see `docs/`

---

## Building (Phase 1, in progress)

Buildroot is **never vendored** into this repo (G4/G6). The top-level `Makefile`
downloads the pinned Buildroot release, verifies its SHA-256 against upstream's
GPG-signed release manifest, unpacks it under `work/`, and forwards every target
into it.

```sh
make                            # help (deliberately NOT a build — see below)
make mister_de10nano_defconfig  # load our config
make -j$(nproc)                 # build (first run bootstraps a cross-toolchain)
make buildroot-showsig          # print upstream's signed hash for the pinned release
```

`make` on its own prints help rather than building. Until the defconfig is
complete, a reflexive bare `make` would otherwise start a full **x86** toolchain
build that nothing in this project wants.

### Host requirements

Standard build tools (`gcc`, `make`, `bc`, `flex`, `bison`, `cpio`, `rsync`,
`unzip`, `wget`/`curl`, `python3`), plus `dtc`, `qemu-user`/`qemu-system-arm`,
and `shellcheck` for the test and inventory scripts.

**One sharp edge:** Buildroot refuses to build if `/usr/bin/install` is **uutils
coreutils 0.8.0** — it detects that exact version and rejects it
(`support/dependencies/dependencies.sh:193`, upstream bug
[uutils/coreutils#12166](https://github.com/uutils/coreutils/issues/12166)).
Debian/Ubuntu's `coreutils-from-uutils` package installs precisely that as the
default `install` and ships GNU's as `gnuinstall`.

You do **not** need to fix this yourself, and you should not need `sudo`: the
Makefile detects it and transparently shims a GNU `install` into `PATH` for
Buildroot only (`output/.hostshim/`), touching nothing outside this repo. It is
inert on a host whose `install` is already GNU. If no GNU `install` exists at
all, the build fails fast and tells you what to install.

---

## Technical Reference

- **`docs/abi-contract.md`** — The ABI guarantee the kernel and rootfs must honor
- **`docs/boot-chain.md`** — U-Boot contract and kernel-config implications
- **`docs/phase0-review.md`** — Detailed findings from Phase 0 reconnaissance
- **`docs/verification/stock-release-20250402.md`** — Stock image audit for reference
- **`docs/package-manifest.md`** — SONAME stability guarantees for the ABI contract

---

## Contributing

Contributions are welcome once the Phase 4 publication gate is passed. Until then, this is a personal-use project.

When open, all contributions must follow the discipline in **`CONTRIBUTING.md`**: patch provenance tracking, developer sign-off (DCO), and adherence to the standing rules from `TASKS.md` (reproducibility, no vendored binaries, hash-pinned upstream sources).

See `PLAN.md` §13 for sustainability requirements and risk discussion.

---

## Key Documentation

- **`PLAN.md`** — Goals (G1–G7), design rationale, risk analysis, and sustainability model
- **`TASKS.md`** — Phase-by-phase execution plan with acceptance criteria and model routing
- **`docs/patch-provenance.md`** — Every kernel patch: origin, upstream status, and disposition
- **`docs/decisions/`** — Architecture decision records (ADRs 0010–0014): open questions, trade-offs, and resolutions
- **`CONTRIBUTING.md`** — Patch discipline, standing rules, and developer sign-off requirements
- **`docs/user/beta-testing.md`** — Beta-tester guide (when available)
