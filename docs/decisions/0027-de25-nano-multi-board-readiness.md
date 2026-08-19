# ADR 0027 — DE25-Nano ("MiSTer 2.0") readiness: same repo, staged, framework-gated

**Status:** Accepted (2026-08-19) — decided by @mcfbytes. No build-system, CI, or
release change is made by this ADR: acceptance commits the project to a *posture*
(same repo, staged plan, guarded couplings) and to the initial-deliverable scope in
Decision 6, not to any build work yet.
**Impact (when acted on):** `configs/`, `board/mister/`, `scripts/` (board
parameterization), `.github/` (a manual DE25 lane), `docs/` (this plan suite).
**Related:** [ADR 0021](0021-rt-kernel-first-class-ci.md) (the variant machinery this
generalizes), [ADR 0024](0024-mainline-uboot-capability-artifact.md) (from-source U-Boot —
a DE25 prerequisite), [ADR 0025](0025-update-linux-kill-switch-and-private-updater.md)
(the out-of-band update channel the DE25 design reuses), [ADR 0018](0018-db-json-version-is-release-date-driven.md)
(version scheme, carried over).
**Plan and task list:** [`docs/de25-nano-plan.md`](../de25-nano-plan.md),
[`docs/de25-nano-tasks.md`](../de25-nano-tasks.md).

---

## Context

Terasic's **DE25-Nano** (announced 2025, ~$248) is the community's leading candidate for
a "MiSTer 2.0" board: an Altera **Agilex 5 E-series** SoC (A5EB013BB23B, 138K LE, ~1.5×
faster fabric than the DE10-Nano's Cyclone V), an HPS of **2× Cortex-A76 + 2× Cortex-A55
(aarch64)**, 1 GB LPDDR4 on the HPS plus 1 GB on the FPGA side, 128 MB SDRAM soldered
on-board (the DE10's add-on module, built in), HDMI 2.0 (to 1080p), and QSPI
configuration flash. The upstream software ecosystem is real: mainline Linux has carried
`socfpga_agilex5` arm64 device trees since ~6.6 (so our 6.18 base includes them),
mainline U-Boot gained Agilex 5 boot support in 2025, and Quartus Prime Pro has a
no-cost Agilex 5 E-series license — core development is not license-blocked.

Three facts frame what this project can and cannot do about it:

1. **No MiSTer framework exists for the board, and none is announced.** Main_MiSTer is
   an ARMv7 binary welded to Cyclone V physical addresses; core loading on Agilex 5 goes
   through the SDM mailbox (`stratix10-soc` FPGA manager + DT overlays), not a
   memory-mapped `fpgamgr`. Until upstream MiSTer (or a successor project) ports the
   framework, anything we build is a generic Agilex 5 Linux, not a MiSTer.
2. **This repo is already multi-target — on the wrong axis.** Four Buildroot output dirs
   share one tree, one `dl/`, one `BR2_EXTERNAL`, differing only in `O=` and defconfig
   (ADR 0021). The 20 custom packages, ~44 of 48 rootfs-overlay files, and the whole
   scripts/docs/renovate apparatus are board-agnostic. Exactly **four places are
   *semantically* ARM32/Cyclone-V**, not merely spelled `de10nano`: the `zImage_dtb`
   cat-concatenation contract (ARM zImage header offset 0x2C; no aarch64 analogue), the
   0xA2 BootROM SD layout, the `^BR2_arm`/`^BR2_cortex` asserts in
   `.github/actions/buildroot-build/action.yml` and
   `scripts/check-kernel-defconfig-sync.sh`, and the armv7-pinned `package/azcopy`.
3. **The update channel already bifurcates cleanly.** ADR 0025 took us off the
   Downloader's single shared Linux slot: each device pulls exactly one board-matched
   `db.json` via a private-ini updater. A second board is one more (db.json, updater
   script, release-tag namespace) triple — *no* arbitration point exists where DE10 and
   DE25 artifacts could meet on a device. The `release_YYYYMMDD.7z` name convention is
   never parsed on-device (only db.json's `hash`/`size`/`url`/`version[-6:]` are), so
   both boards can keep it under per-board release tags.

The genuine unknown is whether "MiSTer 2.0" devices will run `Downloader_MiSTer` at all.
That decides nothing here: the out-of-band channel works if they do, and an independent
pipeline replaces it if they don't.

## Decision

**Support the DE25-Nano, if and when it becomes a MiSTer target, from this repository —
as a new board axis on the existing variant machinery, not as a fork.** Concretely:

1. **Same repo, board axis.** A future `configs/mister_de25nano_defconfig`,
   `board/mister/de25nano/`, and per-board output dirs, mirroring how kernel variants
   hang off `configs/mister_<name>.fragment`. The names above are **reserved now** so
   docs and scripts can reference them stably.
2. **Staged and framework-gated.** No build work happens on acceptance. The plan
   ([`de25-nano-plan.md`](../de25-nano-plan.md)) defines phases with explicit triggers:
   recon and readiness guards are unconditional; **bring-up (D2) is gated on hardware in
   hand; parity (D3) is gated on an upstream framework existing.**
3. **Readiness guards, not speculative refactors.** We do not pre-build DE25 plumbing.
   We stop *deepening* the four couplings: any newly written or substantially rewritten
   script/CI step that would hard-code `de10nano`, `BR2_arm`, or zImage semantics takes
   a board parameter instead (task D1).
4. **The release-channel design is fixed now** (it is analysis, not code): per-board
   GitHub release tags (`YYYYMMDD` stays DE10's; DE25 uses `de25-YYYYMMDD`, each release
   carrying its own conventionally-named `release_YYYYMMDD.7z`), a second Pages document
   `db-de25nano.json` with its own `db_id`, a per-board updater script, and a
   **board-identity assertion before any flash step** — the stock `updateboot` raw-`dd`s
   the whole disk and is board-fatal if ever crossed. `/MiSTer.version` stays exactly six
   bytes on both boards (the Downloader compares the file's full contents against
   `version[-6:]`); board identity comes from the device tree, never from that file.
5. **CI stays cheap.** Any DE25 build lane is `workflow_dispatch`-only until the board
   is a real target; it does not enter the per-PR path and does not get a protected slice
   of the ~7 GB-of-10 GB cache budget ([docs/ci.md#cache-budget-and-sizing](../ci.md#cache-budget-and-sizing)) — cold
   builds are acceptable for a manual lane.
6. **The initial deliverable is a bare developer OS.** Early DE25 releases (on D2
   completion) ship **no MiSTer-specific binaries** — none exist for the board. The
   image keeps the DE10 image's footprint and conventions (two-stage initramfs, overlay
   services, exFAT state model) so developers can use it in their own testing
   workflows. U-Boot is built here from source, excluding MiSTer binaries; whether and
   when MiSTer binaries join is a future decision point, taken with community adoption
   — at which point assets load in the same way the DE10 pipeline overlays the stock
   payload today. These early artifacts publish as plain GitHub releases under the
   `de25-YYYYMMDD` tags; the db.json/updater channel stays framework-gated, since it
   presupposes the MiSTer downloader stack on-device. MiSTer-facing conventions
   ultimately belong to the upstream project owner (Sorgelig); this repo produces a
   theoretical work product that upstream may adopt, or not.

## Alternatives rejected

**A fork / separate repository.** Duplicates the 20 packages, the portable ~28-patch
HID/input kernel series, the overlay, renovate/hash-sync, and the docs culture — all of
which then drift. Its one concrete win (a separate Actions cache budget) is bought by
policy above. Revisit trigger, stated now: fork **iff** the DE25 side acquires a
different upstream framework/governance than MiSTer proper, or a shared repo's CI/cache
constraints demonstrably block DE10 work.

**Build a bring-up image now.** No consumer exists, the ecosystem is still moving
(kernel/U-Boot support actively landing through 2025–26), CI minutes are watched, and a
prebuilt-but-unmaintained board lane is worse than none. The plan keeps D2 one trigger
away instead.

**Do nothing until upstream moves.** The couplings would silently deepen — every new
script that hard-codes `de10nano` or zImage semantics raises the future port cost. The
guards in D1 are cheap precisely because they only apply to code being touched anyway.

## Consequences

- Nothing builds, nothing ships, no CI minutes are spent on acceptance. This ADR + the
  plan suite are the entire change.
- The namespace is reserved: `mister_de25nano_defconfig`, `board/mister/de25nano/`,
  release tags `de25-YYYYMMDD`, Pages `db-de25nano.json`, db_id
  `mister_linux_modernization_de25nano`.
- Future contributors touching the four coupling sites inherit a documented obligation
  (D1 guards) instead of an unwritten one.
- Initial dispositions for the plan's decision points were recorded by the owner on
  acceptance (plan §6): DP-4 and DP-5 decided, DP-1 and DP-9 decided in direction, the
  rest tabled. Tabled DPs still graduate to their own ADRs when their phase activates;
  MiSTer-facing calls rest with the upstream project owner.
- If "MiSTer 2.0" lands on different hardware than the DE25-Nano, the plan's
  board-specific recon (D0) is discarded but the readiness guards, channel design, and
  phase structure transfer as-is — they are keyed to "a second, aarch64 board," not to
  this SKU.
