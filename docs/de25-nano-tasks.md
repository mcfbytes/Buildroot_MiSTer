# DE25-Nano tasks

**Goal and scope:** [ADR 0036](decisions/0036-de25-scope-and-base-generations.md) (Proposed).
**The flash image and its bench gates:** [ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md).
**Current state:** [`de25-nano-overview.md`](de25-nano-overview.md). **Parent plan (2026-08):**
[`de25-nano-plan.md`](de25-nano-plan.md), [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md).
**Everything before 2026-11-28** (Phases D0 and D1, Waves 1 to 6, the DU7 record):
[`de25-history.md`](de25-history.md).

> ## Status — 2026-11-28
>
> The OS layer is done and runs on a tester's board (#318). Cores load over an HPS-first flash
> image, from U-Boot and from Linux. Nothing of ours on the fabric or flash side has run on
> hardware yet: the base image, `de25-fpga-load`, the HDMI block, any QSPI write. The owner's
> own board is on order. Live work is the table in "Phase D2 — live tasks" and the order in
> "Critical path".

This list is written to be executed under **ultracode** (multi-agent Workflow orchestration).
Each task names the orchestration shape and the smallest agent tier that can do the work
honestly.

**Agent tier legend**

| Tier | Use for | Never for |
|---|---|---|
| `haiku` | mechanical inventory, single-file greps, format checks | anything requiring judgment |
| `sonnet` | standard research legs, per-patch/per-package analysis, drafting | final verdicts on load-bearing claims |
| `opus` | synthesis, design, cross-source reconciliation, code review | bulk fan-out legs (cost) |
| `fable` (session model) | adversarial verification of brick-risk / flash-path / boot-contract claims; DP judge synthesis | routine legs |

**Standing rules for every workflow in this plan**

1. Every produced doc tags claims **[V]**/**[U]** with source (file:line, URL+date, or
   "measured on hw <date>"). An agent that can't source a claim returns it as [U] —
   fail closed, never fabricate (house rule; same posture as the RT TOFU-hash gates).
2. Any claim that will later justify a flash-path design, a hardware purchase, or a
   QSPI write gets an **adversarial verify leg** (2–3 refuters, majority kills).
3. The default workflow size guideline is ≤15 agents; tasks marked **⚠ size** exceed it
   deliberately — say so when launching ("dynamic workflow size" or batch it).
4. CI-costly steps stay out of workflows entirely (memory: Actions minutes are watched);
   agents produce scripts/configs, humans or manual dispatch run the expensive builds.

5. *(2026-11-28)* Anything that writes QSPI runs first on the **owner's** board, after the
   recovery drill (bench order, step 2), and never on the tester's board without asking.

---

## Done

One line each; the full record is [`de25-history.md`](de25-history.md).

| Task | Done | Deliverable |
|---|---|---|
| D0.1 Boot-chain dossier | 2026-08-21 | [`de25-boot-chain.md`](de25-boot-chain.md) |
| D0.2 FPGA reconfiguration dossier | 2026-08-21 | [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) |
| D0.3 Kernel patch portability | 2026-08-21 | [`de25-patch-portability.md`](de25-patch-portability.md) |
| D1.1 Coupling ledger | 2026-08-21 | [`de25-readiness-ledger.md`](de25-readiness-ledger.md) |
| D1.2 Arch-assert generalisation | 2026-09-02 (Wave 1, `1f9374c`) | `scripts/lib/board-expectations.sh` as it then was |
| D1.3 Channel namespace | 2026-08-21 | `downloader-contract.md` §13, `db-json-versioning.md` |
| D2.1 Defconfig builds | 2026-09-02 (Wave 1) | `configs/mister_de25nano_defconfig` |
| D2.2 TF-A and U-Boot; a prompt on the board | 2026-11-24 (#318, 10 of 10 cold boots) | [`de25-uboot.md`](de25-uboot.md) |
| D2.3 Kernel and DTS; boots to a login | 2026-11-24 (#318) | [`de25-dts-rationale.md`](de25-dts-rationale.md) |
| D2.4 SD card; the two-stage card boots on the factory flash | 2026-11-26 (#318, ADR 0035 B0) | [`de25-sdcard.md`](de25-sdcard.md) |
| D2.6 Manual CI lane | 2026-09-23 (Wave 5) | `de25-build.yml`, [`ci.md#de25-manual-lane`](ci.md#de25-manual-lane) |
| D2.7 DP-1 ADR | superseded | ADR 0029 D4, then ADR 0035 and ADR 0036 |
| D2.8 Developer-preview release lane | lane landed 2026-11-24; no `de25-*` pre-release published yet | [`ci.md#de25-manual-lane`](ci.md#de25-manual-lane) |
| D2.12 Package-patch parity | 2026-11-27 (`e0895dd`) | [`buildroot-config.md`](buildroot-config.md) §3.3 |

## Phase D2 — live tasks

Every flash- or QSPI-touching script gets a `fable` adversarial review before it runs on a
board (rule 2). **O** = the owner's board, **T** = the tester's board (#318), **D** = desk.

| Task | Deliverable | Accept | Orchestration |
|---|---|---|---|
| D0.4 | **Upstream watch** (recurring; a `/schedule` routine, not a workflow). Monthly: Altera's baseline and Quartus releases and knowledge-base entries for Agilex 5 HPS-first, Terasic's Resource Package, mainline `agilex5` movement, framework signals. *Still not started; it would have caught the 26.3 baseline sooner* | dated entries in `docs/de25-watch.md`; an entry that moves a gate is raised, not only logged | 2–3 web-search legs |
| D2.5 | FPGA reconfig proof + **measured** full-reconfig latency *(2026-11-26: proof done on #318's bench through a bench module, ~2.1 s per 1.58 MB load, 32 loads; the timing table and our own loader remain, see D2.11)* | RBF loads via overlay from Linux; latency table (feeds DP-9, D0.2 [U]s resolved) | inline + 1 `opus` analysis of results |
| D2.9 | **Menu at boot** (operator 2026-11-24), after the DE25 Template fork builds a Menu core: (1) the DE25 U-Boot default env gains a `core=`/`fpgaload` pair like `board/mister/de10nano/uboot.env:89-92` (`load mmc` + `fpga load` of a phase-2 Menu `*.core.rbf` from FAT; no `bridge enable`, no Cyclone V pokes: TF-A owns the bridges); (2) a phase-1/phase-2 hash or version check BEFORE `fpga load`, so a card paired with the wrong QSPI image refuses instead of wedging; (3) a failed load still boots Linux, fabric empty; (4) a release artifact that ships the MATCHED pair: the Menu `core.rbf` plus the phase-1 QSPI image (`.jic`/`.rpd`) from the same Quartus base compile, written once by the first-boot installer (ADR 0035 D4; JTAG is the fallback); (5) ItsAlive runs after U-Boot's load, as on the DE10. *2026-11-27:* item (1) is **mandatory**, not a convenience: an HPS-first image configures no fabric at power-on, and U-Boot `fpga load` is proven (#318 T1). A warm reboot keeps the loaded fabric, so the guard in (2) must also cover a core already running | cold boot with the pair: Menu configured before the kernel, `itsalive up` lights HDMI; the wrong pair refuses at the U-Boot guard | design: `opus`; the U-Boot env and guard get a `fable` adversarial review (flash and boot path) |
| D2.10 | **Our own QSPI image** ([ADR 0035](decisions/0035-de25-own-qspi-image-first-boot-flash.md), owner 2026-11-25). Bench gates first, in order: B0 the two-stage card on the factory flash; B1 fuse status; B2 #318's posture-2 plan plus warm reboots; B3 Linux writes QSPI via the SDM mailbox; B4 the write time; B5 an RSU fit; B6 our mainline SPL; B7 the SDM firmware licence. *2026-11-26: B0 (a)–(c) and B2 passed; D2 = HPS-first (ADR 0035 §5). 2026-11-27: B5 fits by size (the factory image uses ~3.3 MiB).* Then the installer's write-once, verify-before-reboot flash step, with an HPS LED pattern and a power-cut test | B0-B7 recorded on #318; the installer's QSPI step passes a power-cut harness | design: `opus`; the QSPI writer gets a `fable` adversarial review |
| D2.11 | *(module packaged 2026-11-27, `package/de25-fpga-load`; the pairing check and the bench run remain)* **Runtime core loader** ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) §12). Package `de25-fpga-load` (Appendix A of [`de25-vendor-kernel-delta.md`](de25-vendor-kernel-delta.md)) as an out-of-tree kmod. Add the HPS-IO-hash pairing check before a load, and settle the bridge-quiesce contract Main needs around a switch | the loader loads a matching core from `/lib/firmware`, refuses a mismatched one with a readable error, and survives §6.3's 20-load loop and 10 warm reboots on our image | design: `opus`; the loader gets a `fable` review |
| D2.13 | *(added 2026-11-28, ADR 0036 D2)* **RTL pipeline and artifact contract.** A self-hosted runner, with its owner's licences, builds the base pair (phase-1 `.jic`, boot `core.rbf`) from `fpga/de25-base/` and Altera's baseline, and publishes them with a manifest (generation, HPS IO hash, Quartus build, SHA-256, `quartus_pfg -i` output). A Buildroot package fetches them by hash. Never runs a pull request from a fork | `make de25` builds a card with the pinned pair and no Quartus; a second machine with its own licences reproduces the hash | design: `opus`; the runner's trigger rules get a `fable` review |
| D2.14 | *(added 2026-11-28)* **Core template and a Menu core** against generation 1, in their own repositories. The template carries the hash rules of [`de25-quartus.md`](de25-quartus.md) §6 and fails a build with the wrong hash. Settles the video contract (ADR 0036 §5 item 1) with the base design | a Menu core with generation 1's hash loads from U-Boot and from Linux and shows a picture | tracked here; built elsewhere |
| D2.15 | *(added 2026-11-28)* **A basic UI and core loading from userspace.** A minimal host on `/dev/fb0` that lists cores on the card and loads one through the loader. Any generation-1 core will do to demonstrate it; it does not wait for D2.14 | on the owner's board: pick a core, it loads, pick another, it loads; a wrong-generation core is refused with a readable message | design: `opus` |
| D2.16 | *(added 2026-11-28)* **The update path for the flash.** How a later release changes the phase-1 or adds a generation: an RSU layout (ADR 0035 B5), or a guarded rewrite. Not needed for the first release | a design note, then B5 on the owner's board | design: `opus`; `fable` review |

**Dated notes on the rows above (2026-11-28).**

- **D2.9.** Item (2)'s check must compare against the phase-1 that is *running*, which after a
  flash write may not be the one in the flash (ADR 0035 B8). Whether a refused load leaves the
  SDM healthy decides how strong the check must be: load a mismatched core several times, then a
  matching one (bench order, step 6).
- **D2.10.** Gates added or changed: **B2b** (hash across compiles; test 1 passed 2026-11-28,
  test 2 owed), **B3** (three accounts of the handover to reconcile), **B4** (write order and the
  exposed window), **B6** (our SPL before the first public `.jic`), **B8** (the reset after the
  write). The installer step also needs the known-image gate, the user told beforehand
  ([`user/de25-first-boot.md`](user/de25-first-boot.md), with measured times) and the recovery
  guide rehearsed ([`user/de25-recovery.md`](user/de25-recovery.md)). Self-flash is the user
  path (ADR 0036 D4).
- **D2.11.** The loader takes only a bare file name under `/lib/firmware`
  (`package/de25-fpga-load/src/de25-fpga-load.c`), and cores live in folders on the exFAT
  volume. Decide the interface a host needs (the bitstream as written data, or a path) before
  a host is written against it.

## Critical path

In order. Items 6 to 8 and 12 can run side by side on the owner's board once 5 is done; 9, 10
and 14 are desk work beside them.

| # | Where | What | Needs |
|---|---|---|---|
| 1 | D | Accept or amend ADR 0036; read the 26.3 release notes' device-support table and the Quartus licence's output-file clause | — |
| 2 | O | Recovery drill and factory archive (bench order, steps 1–2) | the board |
| 3 | O | ADR 0035 B0 (d) on Windows; B1, the fuse status | 2 |
| 4 | O | Altera's public 26.3 pair over JTAG; T1 at the U-Boot prompt; T3 through `de25-fpga-load`; the cold and warm matrix | 2 |
| 5 | D, O | Hash test 2 (B2b); declare base generation 1 | 1, 4 |
| 6 | O | `de25_hdmi` in the base design: logo, pixel phase, the framebuffer from `/dev/fb0`; the video contract | 5 |
| 7 | O | D2.9: U-Boot loads the boot core, the guard, a failed load still boots | 5 |
| 8 | O | D2.11: the loader's interface, a 20-load loop, a truncated file, settle times, the quiesce contract | 5 |
| 9 | D | D2.13: the RTL pipeline | 1, 5 |
| 10 | D | D2.14: the core template and a Menu core. The longest item; it sets the date | 5, 6 |
| 11 | D, O | D2.15: a basic UI | 6, 8 |
| 12 | O | D2.10 on the factory flash: B3, B4 on scratch space, B8, the ordered write, B6, the known-image gate, the LED pattern | 2, 5 |
| 13 | O | The power-cut campaign on the real installer step: at least 20 cuts at random points, each recovered by the documented procedure | 12 |
| 14 | D | The user docs filled with measured times | 2, 12, 13 |
| 15 | T | Acceptance: the board restored to factory, a release-candidate card, the user doc only, no serial. Then again with a deliberate power cut and the recovery guide | 13, 14 |
| 16 | D | ADR 0035 B7 closed; the first pre-release that writes the flash | 15 |
| 17 | later | D2.16 | 16 |

## Bench order — the owner's board, first sessions

1. **Before any write:** read the device and JTAG ID over JTAG; verify-only against
   `golden_top_hps.jic`; read the flash back and archive it; record the board revision, the
   device name and the SW5 positions ([`de25-boot-chain.md`](de25-boot-chain.md) §6's rule).
2. **Recovery drill:** flash the factory `.jic` back with the stand-alone Programmer, timed,
   with MSEL at `001` and at `111`. This becomes [`user/de25-recovery.md`](user/de25-recovery.md).
3. Boot the current card on the factory flash (B0); B0 (d) on a Windows PC; B1.
4. Altera's public pair over JTAG. Does its SPL load our `u-boot.itb` from the hidden p1? T1,
   then T3 with `de25-fpga-load`; cold boots and warm reboots.
5. Hash test 2, then the HDMI checks ([`de25-base-image.md`](de25-base-image.md) §5, §7).
6. A deliberately mismatched core, several times, then a matching one.
7. Back on the factory flash: read the flash from the HPS (B3); write, verify and time scratch
   data in the blank region above the image only (B4); the reset after a write (B8); the
   ordered real write; the power-cut campaign.

**The tester's board** stays the second unit and the Quartus 25.1.1 reference, and becomes the
factory-state acceptance board (critical path, item 15). Two cheap questions for it now: which
MSEL position its two JTAG flashes used, and `printenv qspi_clock` at the U-Boot prompt on the
factory flash (non-zero means the factory SPL already took the flash from the SDM).

## Open items from the RTL reviews

From the second review of `fpga/de25-base/` (2026-11-28; fixes in `c1d4e84`). These need a
Quartus compile or a board, and belong to items 5 to 8 above.

| ID | Open | Where it is written |
|---|---|---|
| H1 | **A core load and a warm reboot with the reader running** (`CTRL` 1). The rule "write `CTRL` 0, wait for idle" is in place; what happens without it has never been tried, and an abandoned burst may hang the HPS | [`de25-base-image.md`](de25-base-image.md) §6.1, [`de25-fabric-interface.md`](de25-fabric-interface.md) §4 |
| M4 | **1080p throughput.** Altera's adapter declares one outstanding read; check `STATUS` bit 0 after ten seconds at 1920×1080 and raise the adapter's capability if it underruns | [`de25-base-image.md`](de25-base-image.md) §7 |
| L5 | The bridge state after a truncated core; the bench result is still unreported | [`de25-fabric-interface.md`](de25-fabric-interface.md) §4 |
| L6 | The ADV7513 init has no I2C bus clear. Not damaging; open | [`de25-base-image.md`](de25-base-image.md) §1 |
| — | Needs a compile: Quartus elaboration of `rtl/`, timing at 100 and 148.5 MHz and the `.sdc` matches, the HDMI pins' bank and I/O standard, the 148.5 MHz IOPLL | [`de25-base-image.md`](de25-base-image.md) §7 |
| — | Needs a board: the ADV7513 ACK (`STATUS` bits 7, 8), F2SDRAM reads (`STATUS` bit 1), a rehearsed JTAG restore before any `.jic` of ours | bench order, steps 2 and 5 |

---

## Later phases

*(2026-11-28)* Written on 2026-08-19 with the gate "an upstream framework exists". ADR 0036
changes that for the work toward a booting card; these shapes stand for the parity work that
follows it.

## Phase D3 — Parity (gate: upstream framework exists) — produces L2

Scoped properly only when the gate opens (the framework defines fb/audio/core-loading).
Standing shapes, sized now so the plan is costable:

- **D3.1 Patch-series port** — pipeline per D0.3-portable patch: `sonnet` rebase leg →
  compile-check leg → `opus` review of the handful with conflicts. ~30–40 agents ⚠ size.
- **D3.2 Package audit on aarch64** — pipeline over the packages targeted at DE25:
  `haiku` build-config leg → `sonnet` verdict. azcopy is **excluded from the DE25 set**
  (owner disposition 2026-08-19: Microsoft publishes linux-arm64 binaries, so we do not
  package or publish it there; the DE10 armv7 pipeline is untouched). ~25 agents ⚠ size.
- **D3.3 Services/overlay parity** — one `sonnet` leg per existing `docs/*-parity.md`
  (~10), each re-deriving its subsystem for DE25 → `opus` synthesis. ~12 agents.
- **D3.4 Update channel implementation** — per plan §4.2. Small code, maximal care:
  `opus` implement → `fable` adversarial verify ×3 on the board-identity assertion and
  every flash step (this is the board-fatal path) → hardware dry-run with
  `--run-only` + a deliberately mismatched db to prove the assertion fires.
- **D3.5 Installer / full-SD analogue** — re-derive ADR 0020 for the D0.1 layout.
- **D3.6 RT evaluation on big.LITTLE** — measurement-first (cyclictest matrix across
  CPU/IRQ placements) before any variant fragment exists; feeds DP-6 ADR.

## Phase D4 — Decision points → ADRs

Owner dispositions were recorded on ADR 0027 acceptance (plan §6): DP-4/DP-5 decided,
DP-1/DP-9 decided in direction, the rest tabled. Only tabled DPs graduate here —
DP-2/3/8 with D3.4, DP-6 with D3.6, DP-10 with L0/community adoption; DP-9's direction
is validated by D0.2, and DP-1's residual (MiSTer-binary inclusion) waits on adoption,
per D2.7. Uniform shape for those that do graduate: **judge panel** — 3 `opus`
independent position drafts (different priors: conservative / mainline-first /
robustness-first) → `fable` synthesis into a Proposed ADR → owner decides. ~4–5 agents
per DP. Never batch multiple DPs into one workflow; each is a separate decision with
its own evidence base.
