# MiSTer Linux Modernization

**A reproducible, drop-in `linux.img` built from a modern Buildroot, with all kernel patches carried in-tree as Buildroot patch files.**

*This is a stub README for Phase 0 recon. The full community and user documentation is in progress (P4.9). Start with `PLAN.md` and `TASKS.md` for project context.*

---

## What is this?

MiSTer's operating system is currently distributed as an opaque archive containing a 375 MiB ext4 image built from **Buildroot 2021.02.4** with **glibc 2.31**, running **Linux 5.15.1** — a kernel forked in November 2021 that has never merged a single 5.15.y stable release. This project replaces that image with one built from **Buildroot 2026.02 LTS** and a **mainline 6.18 LTS kernel**, in a public repository, with CI and reproducible builds.

**Status: Phase 0 — Recon. Nothing builds yet.** We are triaging the kernel patch set, inventorying the stock image, and establishing the ABI contract.

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

## Key Files

- `PLAN.md` — Authoritative project plan, constraints, and design decisions
- `TASKS.md` — Execution contract: every task is self-contained with acceptance criteria
- `docs/verification/stock-release-20250402.md` — What the shipped stock release actually contains
- `docs/abi-contract.md` — The ABI guarantee the kernel and rootfs must honor (P0.5)
- `docs/patch-provenance.md` — Every kernel patch: origin, upstream status, disposition (P0.4)
- `docs/boot-chain.md` — U-Boot contract and kernel-config implications (P0.8)

---

## Contributing

This project is not ready for contributions yet. Phase 0 is underway. See `PLAN.md` §13 for risk discussion and sustainability requirements.

For the eventual contribution model, see `CONTRIBUTING.md` (P4.9).

---

## Current State

- Phase 0 exit criterion: Patch triage complete and human-reviewed (P0.9)
- Nothing is built; this is pure planning and inventory work
- Hardware testing gates each phase (see `PLAN.md` §12)
