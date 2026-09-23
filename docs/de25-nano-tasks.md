# DE25-Nano tasks — ultracode execution plan

**Parent plan:** [`de25-nano-plan.md`](de25-nano-plan.md) · **Decision:**
[ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md).

This task list is written to be executed under **ultracode** (multi-agent Workflow
orchestration): invoke a task with the `ultracode` keyword, or run the whole active
phase as a sequence of one-workflow-per-task turns. Each task below specifies the
orchestration shape and the *smallest agent tier that can do the work honestly* —
over-tiering wastes tokens, under-tiering produces confident nonsense in exactly the
places (boot flow, flash paths) where this board can be bricked.

> ## Execution status — 2026-08-22
>
> **Phase D0 and Phase D1 are COMPLETE.** Everything below them is either done, hardware-gated,
> or framework-gated. Nine owner decisions were taken across 2026-08-19 → 2026-08-22 and are
> recorded in [`de25-implementation-path.md`](de25-implementation-path.md) §1 — read those before
> planning any D2 work; several of them foreclose options this task list still describes as open.
>
> | Task | State | Deliverable |
> |---|---|---|
> | D0.1 | **done** 2026-08-21 | [`de25-boot-chain.md`](de25-boot-chain.md) — §8 Q1–Q6 closed or parked; §9 refutation record |
> | D0.2 | **done** 2026-08-21 | [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) — DP-9 **confirmed** |
> | D0.3 | **done** 2026-08-21 | [`de25-patch-portability.md`](de25-patch-portability.md) — all 40 patches |
> | D0.4 | **open** | not started; a `/schedule` routine, not a workflow |
> | D1.1 | **done** 2026-08-21 | [`de25-readiness-ledger.md`](de25-readiness-ledger.md) — 54 files, 65 rows |
> | D1.2 | **designed, NOT implemented** | design lives in the ledger §5; the code change is still owed |
> | D1.3 | **done** 2026-08-21 | forward-pointer sections in `downloader-contract.md` §13, `db-json-versioning.md` |
>
> **Two documents exist that this task list never anticipated**, both created 2026-08-22 from a
> third-party DE25-Nano that boots Linux to the MiSTer MENU (repos supplied by the owner as
> reference; nothing adopted):
> [`de25-reference-implementation.md`](de25-reference-implementation.md) — analysis of that board,
> partly salvaged from a spend-limited run and **partly unrefuted**, read its status header — and
> [`de25-implementation-path.md`](de25-implementation-path.md) — the settled implementation path:
> kernel 7.2, the minimal DTS node set, prior art, U-Boot shape, and the answer to how the fabric
> is reached from userspace.
>
> **The single biggest open risk is not in this task list:** binding the mainline FPGA-manager
> driver is proven, but *programming* the fabric through mainline `svc` is not, and one attempt on
> real silicon wedged a board. See `de25-implementation-path.md` §2.6 for the four-step hardware
> test that settles it. Run it before building anything that assumes it works.

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

---

> **Layout note (2026-09-11, ADR 0030):** file and target names in this document predate the
> refactor that replaced the fragment stacks with committed `configs/mister_*_defconfig` files and
> Kconfig profiles, moved the RT kernel into `package/linux-rt` (`output/build/linux-rt-*`, no
> `output-rt/`), the stage-1 initramfs into `package/mister-initramfs`, and retired the
> kernel-variant CI matrix, `scripts/list-kernel-variants.sh`, `check-kernel-defconfig-sync.sh`
> and `scripts/lib/board-expectations.sh`. Read the paths here as of their date; the current
> layout is README "Building it yourself" and `docs/ci.md` "The pipeline today".

## Phase D0 — Recon (no gate; run any time; pure research)

### D0.1 Boot-chain contract dossier → `docs/de25-boot-chain.md`
The Agilex-5 analogue of `docs/boot-chain.md`, same rigor: SDM boot stages; exactly
which artifacts live in QSPI vs SD for an HPS-first boot; SD layout the SDM/FSBL
expects; U-Boot env location; warm-reboot story; what a power-loss-safe boot-firmware
field update looks like (the `updateboot` analogue — including whether QSPI is ever
written and the recovery path if it's interrupted). Primary sources: DE25-Nano User
Manual (DigiKey PDF P0804), Terasic System CD, Altera GSRD boot-example docs
(rel-24.x/25.x), RocketBoards Agilex-5 bootloader doc, mainline U-Boot + ATF source.
- **DONE 2026-08-21.** The doc is now 690 lines. Q1 resolved **[V]**: the SDM *cannot* boot from
  the microSD on this board, so the QSPI seam is permanent. Q6 **[V]**: all DDR/pinmux handoff
  lives inside the QSPI bitstream. Q5 **[V]**: `saveenv` writes back to wherever the env loaded
  from, so a FAT miss lands in QSPI. The factory QSPI image is public and was downloaded and
  hashed (`golden_top_hps.jic`, 16,777,447 B, sha256 `e3d20c2d…b38a4`, independently re-verified).
  Q2/Q3/Q4 partial, parked with named blockers → D2.2. §7 survived a 3-lens refutation pass that
  amended 8 of 22 claims and added 7 new brick vectors; §9 records it.
  **Standing risk:** "no release writes QSPI" is enforced by prose only — `git grep` finds zero
  board-identity assertion outside `docs/`. ADR 0027 Decision 4 is unimplemented.
- ~~**Status 2026-08-19:** a desk-research first pass exists —
  [`de25-boot-chain.md`](de25-boot-chain.md) (boot chain, QSPI/SD split, MSEL table,
  postures, brick inventory §7). **The task narrows to that doc's §8 Q1–Q6** (SDM-from-SD
  on this board incl. a Terasic inquiry, factory QSPI contents, FSBL→`u-boot.itb`
  contract, RSU sizing, env location, DDR-handoff coupling) plus the adversarial-verify
  pass over §7's brick-risk claims, which have not yet survived refutation.~~
- **Orchestration (narrowed):** 1 `sonnet` leg per open Q (≤6, medium) → 1 `opus`
  synthesis into the doc → `fable` adversarial verify (3 refuters, high) on §7.
  ~10 agents.
- **Accept:** every §8 Q resolved to [V] or explicitly parked with a named blocker
  (hardware-gated items hand off to D2.2); §7 survived refutation.

### D0.2 FPGA reconfig + shared-memory dossier → `docs/de25-fpga-reconfig.md`
- **DONE 2026-08-21.** **DP-9 CONFIRMED** — fpga-region/DT-overlay is the Agilex-native idiom and
  the UIO doorbell patches 0043–0045 are not ported. Core-switching judged UX-viable at
  low-to-moderate confidence (desk only). Later corrected by the 2026-08-22 pass: *binding is not
  programming* — see the status block at the top of this file.
How core loading would actually work: `stratix10-soc` FPGA manager + SDM mailbox path
(read the in-tree driver), RBF formats, DT-overlay region flow, authentication/VAB
requirements if any, and — the highest-value unknown — expected **full-reconfiguration
latency** (docs + community reports; final numbers are hardware-gated → D2.5). Plus the
HPS↔FPGA memory semantics behind "jointly accessible": bridges, coherency, what a
MiSTer-style HPS-visible framebuffer would require. Feeds DP-9/DP-10 and the L0 watch.
- **Orchestration:** 4 `sonnet` legs (kernel driver read; Altera docs; community
  latency evidence; memory-architecture docs, medium) → 1 `opus` synthesis → `fable`
  verify (2 refuters) on the "core switching is/isn't UX-viable" conclusion. ~7 agents.
- **Accept:** the reconfig path is described end-to-end with driver file:line cites; a
  latency estimate exists with explicit confidence bounds and a hw-measurement plan;
  DP-9's decided direction ("Agilex-native DTS/fpga-region idioms instead of carrying
  the UIO doorbell patches") is explicitly confirmed or refuted.

### D0.3 Kernel patch portability audit → `docs/de25-patch-portability.md`  **⚠ size**
Classify every patch in `board/mister/de10nano/linux-patches/` (37) and
`linux-patches-beta/` (40; audit the union once, note series membership) as
**portable-as-is / portable-with-rework / board-specific / superseded-upstream-by-6.18+**
for an arm64 Agilex target. Must consult `docs/patch-provenance.md` and
`docs/kernel-recon/`; provenance dispositions carry (e.g. 0037/BTN_Z is functional, not
cosmetic — dropping it breaks gamecontrollerdb indexing; any "drop" verdict needs the
provenance record cited).
- **Orchestration:** pipeline over ~45 unique patches — per patch 1 `sonnet` (low
  effort: read patch + provenance record, emit verdict via schema) → `opus` dedup +
  series-level synthesis → `fable` spot-verify every *portable* verdict that touches
  `arch/`, DTS, or Kconfig (expect ~6–10). ~55 agents total — run with the size
  guideline raised, or in two batches (main series, then beta delta).
- **Accept:** a table with one row per patch, verdict + one-line rationale + provenance
  cite; totals reconciled against the plan's "~28 portable / ~8 board" estimate, with
  deltas explained.
- **DONE 2026-08-21**, but **not in the shape specified above.** On owner direction the flat
  ~55-agent per-patch sweep was replaced with **triage-first**: 5 batched legs risk-rated all 40
  unique patches, only the RED (DE10/Cyclone-V-specific) set got a per-patch deep dive, plus one
  cross-cutting leg tracing vsync / framebuffer / f2h_irq / audio / doorbells as *mechanisms*
  rather than per-file. ~20 agents instead of ~55, and it fit the default size guideline.
  The doc adds a second verdict per patch the original task never asked for — **target series**
  (shared / de10-only / de25-only / drop) — serving the owner's standing goal of one repo building
  both boards off a shared base. Inventory established: **40 unique basenames**; 4 beta-only
  (0043–0046); 4 present in both series but **differing in content** (0001, 0015, 0030, 0037).
  **Prefer this shape for any future large audit.**

### D0.4 Upstream watch (recurring; NOT an ultracode task) — **STILL OPEN**
- Worth doing sooner than it looks: Altera took the DE25-Nano board file in-house on its default
  branch **11 days before we went looking**. This is exactly the signal class D0.4 exists to catch.
Monthly brief: MiSTer framework/aarch64 port signals, Terasic BSP/System-CD releases,
mainline `agilex5` movement, MiSTeX direction. Too small for a workflow — a scheduled
routine (`/schedule`, monthly) with 2–3 web-search legs appending dated entries to
`docs/de25-watch.md`. Trigger review: any entry that flips a D2/D3 gate gets surfaced,
not silently logged.

## Phase D1 — Readiness guards (no gate; opportunistic, cheap)

### D1.1 Coupling ledger → `docs/de25-readiness-ledger.md` — **DONE 2026-08-21**
- 54 files / 457 matching lines / 65 rows; 14 semantic blockers. Coverage reconciled against the
  canonical grep. **Use `git grep` for the reconciliation**, not `grep -r`: the wrapper `grep` in
  this environment honours `.gitignore` and returns 457 lines where GNU grep returns 15,796.
- **Three couplings ADR 0027's "four" did not anticipate:** `.github/workflows/lint.yml` hard-codes
  ~20 board paths and **fails silently** (a DE25 tree goes unlinted behind a green check — this is
  a live hole for the DE10 too); the `renovate.json` + `renovate-hash-sync.yml` bump axis (a new
  defconfig added without them lands a stale kernel pin); `release.yml`'s 13 coupled lines.
Inventory every hard-coded `de10nano` / `BR2_arm` / zImage-semantics site (survey found
~14 scripts, 4 CI files, 4 defconfig path lines, `external.mk`'s initramfs default) and
write the per-file "when you touch this, do this instead" instruction. Code changes are
**not** required — the ledger is the deliverable; zero-risk `BOARD=` variable
introductions may be proposed as a follow-up diff for separate review.
- **Orchestration:** 3 `haiku` inventory sweeps (scripts / CI / configs+mk, low) →
  per-hit 1 `sonnet` ledger entry (batched, ~4 agents) → 1 `opus` review pass. ~8 agents.
- **Accept:** ledger covers 100% of a fresh grep for `de10nano|BR2_arm|zImage` outside
  `board/mister/de10nano/` and `docs/`; each entry is actionable in one sentence.

### D1.2 Arch-assert generalization design (design only) — **DESIGNED, NOT IMPLEMENTED**
- The design has no separate deliverable file; it lives as a section of
  [`de25-readiness-ledger.md`](de25-readiness-ledger.md). It holds fail-closed for the DE10.
- **The code change is still owed, and D2.1 cannot land without it**: both guards hard-assert
  `^BR2_arm`, so an aarch64 defconfig cannot pass them as they stand.
Spec (not implement) the per-board expected-symbol tables for
`scripts/check-kernel-defconfig-sync.sh` and the buildroot-build action's toolchain
fingerprint, so DE25's defconfig lands against ready guards rather than weakened ones.
- **Orchestration:** 1 `sonnet` (high) draft → 1 `opus` review. 2 agents (barely
  ultracode; fine to run inline).
- **Accept:** the design keeps both checks fail-closed for DE10 exactly as today.

### D1.3 Channel namespace reservation (docs only) — **DONE 2026-08-21**
- `downloader-contract.md` §13 and a DE25 section in `db-json-versioning.md`.
Cross-reference ADR 0027 §Decision-4's reserved names (tags `de25-YYYYMMDD`,
`db-de25nano.json`, db_id, updater script name, board-identity assertion) into
`docs/downloader-contract.md` (a short forward-pointer section) and
`docs/db-json-versioning.md`. 1 `sonnet` agent, inline; no workflow.

## Phase D2 — Bring-up (gate: hardware in hand **per task, not per phase**) — produces L1

Hardware-in-the-loop work does not fan out; ultracode's role in D2 is the *design and
review* passes around each step, not the step itself. Every flash/QSPI-touching script
gets a `fable` adversarial review before it ever runs on the board (rule 2).

> **Correction 2026-08-22 — the gate was drawn at the wrong level.** Reading it as
> "all of D2 waits for hardware" is wrong and was costing real progress. Several D2 tasks
> never touch a board; only their *validation* does:
>
> | Task | Needs hardware? |
> |---|---|
> | **D2.1** defconfig builds green | **No.** Its own accept criterion is `make` green *locally*. Blocked only on D1.2's implementation. |
> | **D2.3** DTS authoring | **Partly.** Authoring + `dtc` + `dtbs_check` now; only *booting* it needs the board. The node set is specified in `de25-implementation-path.md` §3.1 and prior art exists upstream. |
> | **D2.4** genimage cfg + check script | **Partly.** Both are writable now, plus `u-boot.itb` can be built and its shape verified with `dumpimage` against the SPL contract. Cold-flash boot needs the board. |
> | **D2.6** manual CI lane | **No.** |
> | **D2.7** DP-1 ADR | **No.** |
> | **D2.2 / D2.5 / D2.8** | **Yes** — UART bring-up, measured reconfig latency, published attested artifacts. |
>
> Also doable now and not listed as a task anywhere: compile-testing the D0.3 *shared*-series
> patches against aarch64/7.2 (turns desk verdicts into compile-verified ones — the cheapest
> de-risk available for D3.1), writing the two kernel patches decisions 8 and 9 imply, writing and
> compile-testing the ~100-line overlay-trigger driver, and extending
> `scripts/test-initramfs.sh` to an aarch64 `qemu-system-aarch64 -M virt` path so the
> initramfs / loop-root / overlay-services userland is exercised with no board at all.

| Task | Deliverable | Accept | Orchestration |
|---|---|---|---|
| D2.1 | `configs/mister_de25nano_defconfig` (aarch64, minimal rootfs) builds green locally | `make` green; defconfig-sync guards extended per D1.2, still green for DE10 | 1 `opus` implementer + `sonnet` helpers; `/code-review` after |
| D2.2 | ATF+U-Boot from source; UART prompt on the board | prompt reached; env location documented; ADR 0024 machinery reused where possible | design: `opus`; review: judge panel (3 `opus`, one per boot-layout alternative from D0.1) if D0.1 left options open |
| D2.3 | kernel 6.18+ arm64 + authored DE25 DTS; boots to userland | serial login; eth0 up; DTS diffed against GHRD with rationale doc (house `dts-comparison.md` style) | DTS design: judge panel — 3 `sonnet` drafts (GHRD-faithful / mainline-socdk-based / minimal) → `opus` score+merge → `fable` verify |
| D2.4 | `genimage-sdcard-de25.cfg` + `check-sdcard-de25.sh` + flash procedure | image boots from cold flash; check script fail-closed | `sonnet` implement → `fable` adversarial review (flash path) |
| D2.5 | FPGA reconfig proof + **measured** full-reconfig latency | RBF loads via overlay from Linux; latency table (feeds DP-9, D0.2 [U]s resolved) | inline + 1 `opus` analysis of results |
| D2.6 | manual `workflow_dispatch` CI lane, cold-build, no cache slice | lane green once; documented cost per run; zero effect on PR path | 1 `sonnet` + `/code-review`; obey rule 4 |
| D2.7 | **DP-1 ADR** — formalize the accepted bare-developer-OS release scope (ADR 0027 Decision 6); the residual question is only when/whether MiSTer binaries join | ADR merged Proposed→Accepted by owner | 1 `opus` draft + 1 `fable` review — judge panel dropped; direction was decided on ADR 0027 acceptance |
| D2.8 | Developer-preview release lane: manual publish under `de25-YYYYMMDD` tags (sdcard image, kernel, rootfs, SHA256SUMS, provenance; **no db.json/updater** — that stays F-gated) | one draft release published with attested assets; zero PR-path impact | 1 `sonnet` + `/code-review`; obey rule 4 |

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

---

## Wave 1 — 2026-09-02 (pre-hardware)

Executed on branch `feature/de25-wave1` on top of the D0/D1 recon (PR #132). Agent sizing per
track: routine shell/CI edits on Sonnet, build/DTS/patch/ADR authoring on Opus, adversarial
verification on Fable, environment prep on Haiku.

| Track | Task | Deliverable | Status |
|---|---|---|---|
| 1 | D1.2 implement | `scripts/lib/board-expectations.sh`; `check-kernel-defconfig-sync.sh` + `buildroot-build/action.yml` table-driven, DE10 default byte-identical | **DONE** `1f9374c` — §5.6 checks 1/2/3/5 run; no-arg and BOARD=de10nano byte-identical; `bogus` exits 2 |
| 2 | D2.1 | `configs/mister_de25nano_defconfig`, `board/mister/de25nano/linux.fragment`, `make de25` family, external.mk initramfs-hook guard | **DONE** `6dd5604` — toolchain 8 min; **full build green**: `Image` 41.9 MB, ext4 rootfs, 34/34 patches applied at -F0, both carried patches compiled. Kernel is arm64 `defconfig` + fragment (1,481 modules, 90 MB) — a diet is wave-2 work |
| 3 | D2.3 desk half | `board/mister/de25nano/socfpga_agilex5_de25nano.dts` + `docs/de25-dts-rationale.md`; dtc + dtbs_check | **DONE** `d8ad032`+`ae86dbe` — dtc 0 warnings; dtbs_check 5 (all the fpga-mgr binding gap); **SMMU shipped disabled** after the Fable review (see below); `socfpga_agilex5_de25nano.dtb` (17,138 B) built through Buildroot via `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH` — note the `arm64/intel/…` include-prefix form, because Buildroot copies a custom DTS into the `dts/` root, not `dts/intel/` |
| 4 | patch series | `board/mister/de25nano/linux-patches/` (shared symlinks + 0101 sdhci-cadence 40-bit mask + 0102 svc match) | **DONE** `e47cb3e`+`6f50981` — 32 symlinks (3 to the 7.x-anchored beta copies, load-bearing) + 0101/0102; 0002 audio and 0047 excluded (README maps every row) |
| 5 | D4 ADR | `docs/decisions/0029-de25-implementation-path.md` (Proposed) | **DONE** `f156140` — Proposed; four source inconsistencies resolved explicitly; open decisions listed |
| 6 | ledger §6.5 | `lint.yml` board-agnostic, fails loudly on an empty set | **DONE** `6f55523` — discovery + empty-set guard; de10nano file set unchanged, verified by running both steps |

### What the Fable review changed (2026-09-02)

The adversarial pass on the DTS and the two patches produced one design-level finding that
inverts §3.1's default: **with the SMMU enabled, mainline `stratix10-svc` cannot program the
fabric** — it takes the SDM buffer from the `GET_MEM` SMC, keeps *physical* addresses in its
gen_pool and hands them to the SDM raw (no `iommu_map`/`dma_map` anywhere in the file), while
the dtsi's `iommus = <&smmu 10>` attaches the svc device to a translated default domain. Binding
and programming are different claims; SMMU-on satisfies only the first. Wave 1 therefore ships
`&smmu { status = "disabled"; }` with every `iommus` left in place (inert via `of_iommu`'s
`-ENODEV`), and the §2.6 fabric test runs in that shape first. SMMU-off is **unproven, not
disproven** (`de25-dts-rationale.md` U10). Other actions taken: `max-frequency = 25 MHz` on
mmc0 for first boot, the 1 GiB memory node downgraded from "measured" to "Terasic's U-Boot DTS
constant" (U-Boot rewrites `/memory` from IO96B anyway), a BL31 `GET_MEM`-vs-`service_reserved`
check added as U9 to run *before* the first reconfiguration attempt, and the uart1 console
promoted to [V].

### Testing on a borrowed board before we own one

A borrowed DE25-Nano can run our SD images, with one condition that follows directly from
[`de25-boot-chain.md`](de25-boot-chain.md) §2: **the QSPI must hold the factory phase-1
image.** Our card ships `u-boot.itb` only and relies on the *factory SPL's* contract (FAT on
partition 1, FIT at `0x82000000`, boot order `mmc0`). A modified QSPI carries a different SPL
with a different contract — the reference board's, for instance, is exFAT-aware and RSU-shaped —
so a boot failure there would tell us nothing about our image.

- **Restore is the same tool he already used to modify it**: Quartus Programmer over the on-board
  USB-Blaster III, `quartus_pgm -m jtag -c 1 -o "pvi;golden_top_hps.jic"`, from the Resource
  Package (`…/GHRD/output_files/program_qspi_flash/`). Verify the file first:
  `golden_top_hps.jic` is 16,777,447 B, sha256 `e3d20c2d…38a4` (full hash in boot-chain §8).
- **Doing this on a borrowed board also closes an open [U] of ours**: that the *published* JIC boots a
  physical board at all (boot-chain §8, "an archived copy"). Record the board revision.
- **Safety bar before any image reaches him** (rule 2 of this plan): a `fable` adversarial pass on
  the U-Boot env fragment proving `CONFIG_ENV_IS_IN_UBI` is off (implementation-path §6.2 —
  a *load-path* QSPI write, not a save-path one) and that nothing in the image can write QSPI.
- What he can answer for us, in order: factory SPL boots our FIT (D0.1 Q3) → kernel reaches a
  serial login on our DTS (D2.3) → mmc0 under SMMU (§8 Q2) → the §2.6 fabric-programming test.

## Wave 2 — 2026-09-02 (pre-hardware) — DONE, on `feature/de25-wave2`

Goal: a card that can go into a borrowed board. Same agent sizing as wave 1; two `fable`
adversarial passes (config refactor; boot path) before anything is called done.

| Track | Deliverable | Result |
|---|---|---|
| U-Boot + TF-A (D2.4 desk half) | mainline U-Boot v2026.07 + TF-A v2.15.0 as Buildroot packages; `board/mister/de25nano/uboot.fragment`, `uboot-dts/`; `docs/de25-uboot.md` | `u-boot.itb` built by binman and `dumpimage`-verified against the factory SPL contract (crc32 only, no keys; addresses disjoint). QSPI write paths compiled OUT (`CMD_SF`/`MTD`/`UBI`/`ENV_IS_IN_UBI` absent from the resolved config; verified again in the binary's strings). Stock's default boot command contains a `saveenv && ubi part root` leg — gone with `CMD_SF`. `HANDOFF` and `BLOBLIST` off (factory SPL, not ours, runs first). §8 Q6 closed negative: `# CONFIG_SPL is not set` removes the FIT. SD PHY: SoCDK-validated delays, default-speed 25 MHz for first contact. |
| SD card image (D2.4 other half) | `genimage-sdcard.cfg`, `post-image.sh`, `scripts/check-sdcard-de25.sh`, `docs/de25-sdcard.md` | MBR, p1 FAT32 `DE25BOOT` (`u-boot.itb`, `Image`, dtb, `extlinux/extlinux.conf`), p2 = ext4 rootfs written directly (**interim** p2 decision). Checker opens the FIT, allow-lists p1, rejects the DE10 card and every mutated card. `make de25` asserts the card exists and passed. |
| Kernel diet + shared fragment | `board/mister/common/linux-mister.fragment`, `board/mister/de25nano/linux.config`, `scripts/check-kernel-fragment-noop.sh`, `docs/de25-kernel-config.md` | 1,481 → 92 modules, 90 MB → 2.4 MiB, `Image` 41.9 → 20.7 MB; installed module name set identical to the DE10's. Fragment proven a **no-op on the DE10 6.18 tree** (mechanical check; wire it after the DE10 kernel build step). The wave-1 arm64-defconfig kernel had joydev/uinput/hidraw and the pad drivers OFF — invisible in a green build. |
| Config refactor (owner option 2) | `configs/fragments/*` stacks, monoliths deleted, comments → `docs/buildroot-config.md`, `scripts/check-defconfigs.sh` + golden hashes, `lint-config` CI job | PR #137. DE10 resolved config identical old vs new (two independent proofs); fingerprint residue byte-identical; 30+ mutations exercised; kernel-pin bumps don't move the golden, Buildroot bumps warn and are auto-refreshed by hash-sync case 8. |

### What the boot-path `fable` pass established (for the borrowed-board owner)

No brick-class or boot-blocking finding. Verified in the built artefacts, not the config: no QSPI
command or driver in U-Boot proper; BL31 issues no QSPI/RSU command at boot; the kernel has no
MTD/spi-nor/RSU driver and its DTB has no flash node; the FIT is unsigned-crc32 at the addresses
the factory SPL expects; nothing writes anything a power cycle does not clear. First-boot
expectations worth knowing: ~~BL31 prints on UART0, so **no `NOTICE: BL31` lines on the header
UART** is normal~~ (superseded 2026-09-14: the carried TF-A console patch routes BL31 to the
header UART, so its banner is now expected — `de25-uboot.md` §11); capture the SPL's `DDR:` lines (the only real DRAM-size measurement); if
`Retrieving file: /Image` stalls, the SD PHY timing in `uboot-dts/` is the first knob
(`de25-uboot.md` §5.1).

### Still open after wave 2

- ~~p2 filesystem / DE10-style two-stage layout~~ **Decided 2026-09-03 (ADR 0029 D11):** the
  two-stage layout is the target; the plain ext4 card stays until hardware. ~~Owed before the
  switch: an aarch64 stage-1 initramfs stack + its QEMU test path.~~ **Delivered 2026-09-06
  (wave 3 below).** Still owed before the switch: the 7.x re-anchor of patch 0031.
- The DE25 kernel pin has no Renovate manager and shares `linux.hash` by symlink with the DE10
  registry, so an rt bump replaces the 7.2.y hash line rather than adding one. **This happened on
  2026-09-02** (rt 7.2.2 -> 7.2.3): the DE25 pin was moved to 7.2.3 in the same series of commits
  and the series/config were re-verified there (34/34 patches at `-F0`, 460 symbols 0 dropped,
  `docs/de25-kernel-config.md` §8). ~~Still needs its own Renovate manager, or a hash-sync rule that
  keeps every line a fragment still pins, so the next bump is not manual.~~ **Done 2026-09-14:**
  the DE25 pin (`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`, now **7.2.5**) is matched by the same
  Renovate manager as the DE10's RT pin (`renovate.json`, depName `kernel-rt-7.2`), and
  `board/mister/de25nano/patches/linux/linux.hash` is a symlink to `package/linux-rt/linux-rt.hash`,
  so one PR moves both and the `rt` hash-sync case covers both. Found because `make de25` had been
  failing closed since the RT bump to 7.2.5 (no 7.2.3 hash line) and, separately, since ADR 0030
  (`package/linux-rt` registered a rule on the shared `linux.config` even when disabled — fixed in
  `linux-rt.mk`). At 7.2.5 all 34 DE25 kernel patches apply with offsets and no fuzz; the full
  `make de25` is green and `check-sdcard-de25.sh` passes.
- ~~DE25 selects no `linux-firmware`~~ **Decided 2026-09-03 (ADR 0029 D12):** mirror the DE10
  set via a shared `image-common` fragment (PR in flight); seccomp stays off as on the DE10.
- Patch 0002 (MiSTer audio) still excluded; `openssh` will need `_SANDBOX` off when added.

## Wave 3 — 2026-09-06 (pre-hardware) — the aarch64 stage 1 and its QEMU leg

Goal: ADR 0029 D11's owed pre-hardware work — the stage-1 initramfs built for aarch64 and a
QEMU path that boots it — done sequentially in the main tree (owner request: single file).

| Track | Deliverable | Result |
|---|---|---|
| Stage 1 as a fragment stack | `package/mister-initramfs` + `initramfs-de10nano` / `initramfs-de25nano`; `configs/mister_initramfs_defconfig` deleted; `/init`, `initramfs-busybox.config`, `initramfs-post-build.sh` moved to `board/mister/common/`; `INITRAMFS_*_FRAGMENTS` in `stacks.mk`; golden lines for both; checker (f) arch lockstep | DE10 stage-1 resolved config identical old vs new on Buildroot 2026.08 bar `BR2_DEFCONFIG`, the `-dirty` suffix and the three moved paths (5,240 lines). Existing four golden lines unchanged. `BR_INITRAMFS_HOST_KEY` now hashes the stack via `config_stack_files` (one cold CI cache, once). |
| `make de25` with `BR2_LINUX_KERNEL_EXT_MISTER_INITRAMFS=y` in the DE25 defconfig family | `de25-initramfs`, `-verify` (the DE10 `initramfs-verify` recipe with three variables re-pointed, parse under `qemu-aarch64`), `-clean`, `-defconfig`, `-menuconfig`, `-busybox-menuconfig`; `output-initramfs-de25/` in clean/distclean/help | aarch64 musl toolchain + cpio in 6 min from nothing; 466,944-byte cpio, static aarch64 BusyBox; verify OK (19 applets + fsck.exfat + 5 trimmed + /init + /dev/console + ash parses /init). NOT embedded in the DE25 kernel (D11 interim); `external.mk` comment carries the switch. |
| `scripts/test-initramfs.sh --board de25nano` | board switch (`--board` / `TEST_INITRAMFS_BOARD`); per-board cpio, QEMU binary/machine (`-M virt -cpu cortex-a76`), cross compiler (the stage-1 build's own musl toolchain — no `make de25` needed), kernel version pin, 0031 source, caches (`work/test-initramfs-de25*`); test kernel = `board/mister/de25nano/linux.config` + `linux-mister.fragment` + the unchanged harness fragment; kernel tarball default now prefers `dl/linux/` | Whole run incl. the 7.2.3 kernel build: 4 m 16 s; one case re-run 5.5 s. **7/8 PASS**; `symlink` FAIL = a real kernel Oops (below). DE10 leg byte-for-byte unchanged in behaviour. `ci-tests.sh` gained the DE25 leg (skips when no DE25 cpio was built). |

**Finding (the point of the exercise).** Patch 0031's `exfat_symlink` → `page_symlink()` →
`a_ops->write_begin` = NULL → `Oops: pc 0x0`, kernel panic, on the first symlink created. 7.x
exFAT is iomap-based and has no `write_begin`/`write_end` (6.18.49 has both). Not an aarch64 bug;
not an `/init` bug; a 7.x carry bug in 0031 that the RT kernel shares and nothing had ever
run. Recorded in ADR 0002 §8b, `docs/rt-beta-kernel.md` §6, the DE25 patch README.

| Track | Deliverable | Result |
|---|---|---|
| 0031 re-anchor for 7.x | `linux-patches-beta/0031-exfat-samsung-symlinks.patch` is a real file again (the fifth re-anchor; the shared 6.18 patch untouched); `de25nano/linux-patches/0031` symlink → the beta copy; `series` note updated | `exfat_symlink_write_target()`: clusters via `exfat_map_cluster()` (7.x signature) under `s_lock`, sectors via buffer heads, `sync_blockdev_range()`, then `valid_size`/`zeroed_size`/`i_size`. Applies at `-F0` to pristine 7.2.3 (12/12); arm compile clean with `output-rt`'s `.config`; **aarch64 leg 8/8** from a fresh source tree (4 m 04 s). |

## Wave 4 — 2026-09-14 (pre-hardware) — U-Boot desk work

The DE25's remaining U-Boot desk work runs as the DU-series of
[`docs/uboot-tasks.md`](uboot-tasks.md) (wave A landed as `933a2d2`). This section logs the DE25
half of wave A (DU1, DU2, DU6, verbatim returns in the wave-A results file, outside the repo) and
the **DU7 boot-path re-review** — the wave-2 `fable` checklist above, re-run against the
`BR2_TARGET_UBOOT_LATEST_VERSION`-pinned artifact. No board, no rebuild: every claim is
**[V]** (observed, where) or **[U]** (not observed, missing input named). The DU2 hook's
wording of "verified" is a build-time assertion, not a boot.

### Wave A — DE25 results (DU1, DU2, DU6)

| Task | Deliverable | Result |
|---|---|---|
| DU1 — drop the redundant U-Boot pin | `configs/mister_de25nano_defconfig` → `BR2_TARGET_UBOOT_LATEST_VERSION=y`; `board/mister/de25nano/patches/uboot/uboot.hash` removed; `de25-uboot.md` §2 row rewritten | `u-boot.itb` byte-identical before and after the switch (`uboot-dirclean uboot` each side): 725,568 B, `sha256 f4e5c924dc20b51b2347dfd5786f7de23613ebfd445bd80009fcb19be6b1963e` **[V, DU1 + its verifier's independent clean-tree rebuild]**; after the board-local hash file went, Buildroot's own `boot/uboot/uboot.hash` line (`78e8bfc3…`) satisfied `BR2_DOWNLOAD_FORCE_CHECK_HASHES` **[V, build log]**; defconfig canonical by `savedefconfig` diff (LATEST_VERSION and `BUILD_SYSTEM_KCONFIG` are now defaults and drop out) **[V]**. `scripts/check-defconfigs.sh` itself was **not** run (shared-dir rule during the fan-out); its five assertions were replicated in scratch by the verifier **[U as the literal Done-when]**. Verifier also found the FIT timestamp moved with the Buildroot bump (`SOURCE_DATE_EPOCH` is `BR2_VERSION_EPOCH`), so `de25-uboot.md` §6.1's listing is stale — confirmed below. Doc drift still owed: `docs/buildroot-config.md` §6.9's "the pin has not moved yet" paragraph, `docs/uboot-mainline-port.md` §3.6's reference to the deleted hash file, `de25-uboot.md` §3's file-table row. |
| DU2 — §7 as a build assertion | `external.mk` `MISTER_UBOOT_DE25_QSPI_AUDIT` (`UBOOT_POST_BUILD_HOOKS`, guarded on `BR2_TARGET_UBOOT_BOARD_DEFCONFIG=socfpga_agilex5`); `scripts/ci-tests.sh` "DE25-Nano — QSPI-write audit, Linux side" section | Three checks per build: the **fragment text**, the **resolved `.config`** (every §7 symbol absent or unset, `ENV_IS_IN_FAT=y`), and `strings u-boot.itb` (eleven erase/write/probe verbs, one pinned exemption). Round 1 failed verification on three counts, all fixed: the literal Done-when (`CONFIG_ENV_IS_IN_UBI=y` in the fragment) was vacuous because kconfig drops the request (`depends on MTD_UBI`/`CMD_UBI`) — hence the fragment-text check, which now fails it; the `linux_qspi_enable` carve-out was widened to "any line starting `linux_qspi_enable=`" and is now pinned to **one line, one verb, exact head**; and the `de25-boot-chain.md` §5 bullet was *not* flipped to [V] but to "partially enforced" (the board-identity assertion in the updater still has no code). Positive and negative builds are in the DU2 logs (`build-restore.log:170` PASS; `negative-test-run.log:623-630` FAILED naming both docs, `Error 1`/`Error 2`) **[V]**. |
| DU6 — TF-A tag signature | `board/mister/de25nano/patches/arm-trusted-firmware/arm-trusted-firmware.hash` header (sha256 line byte-identical) | Round 1 concluded "no reachable channel, TOFU" and cited a WKD URL whose hu-part was **wrong** (fabricated); the verifier found the key itself. Fix round: key fetched from `https://github.com/odeprez.gpg`, `git tag -v v2.15.0` → *Good signature from "Olivier Deprez <olivier.deprez@arm.com>"*, RSA-4096 `5D6F 8960 43AD EFDF 7B76 BFAA 89C0 8CFD B867 3E0C`, in both the Buildroot download cache checkout and a fresh mirror clone **[V]**; GitHub reports the tag `verified: true`. Trust anchor stated honestly: the tagger's self-published GitHub key — **not** a project keyring, keyserver or WKD hit (both keyservers re-confirmed 404; the corrected WKD URLs redirect and return nothing) — so "the `odeprez` account is the real Olivier Deprez" is **[U]**. Bonus: the hashed `-git4` tarball is the signed tag's tree bar four uninitialised `contrib/` submodule gitlinks **[V, `diff -r`]**. Doc drift owed: `de25-uboot.md` §2's TF-A row and §12's "signature is authentic **[U]**" row still say unverifiable. |

(DU3, wave B, has since landed in `de25-uboot.md` §5b: the FIT is byte-stable across clean trees
and moves only with the toolchain's `git describe` banner. Not part of this pass.)

### DU7 — the wave-2 boot-path checklist, re-run against `f4e5c924…`

**Artifact identity.** `output-de25/images/u-boot.itb` 725,568 B
`sha256 f4e5c924dc20b51b2347dfd5786f7de23613ebfd445bd80009fcb19be6b1963e`, byte-identical to
`build/uboot-2026.07/u-boot.itb`; produced by the build in the DU2 restore log (`>>> uboot 2026.07
Building` → hook PASS at `:170` → `Installing to images directory`; `.stamp_built` 13:05:44.75,
the file 13:05:44.69) **[V]**. `images/bl31.bin` 53,304 B
`sha256 2052e4c9a62c1a2a947ee20886c6419eb5f802a1338bd12e22a99c916cc0250c`, identical to the TF-A
tree's `build/agilex5/release/bl31.bin` **[V]**. Resolved config
`build/uboot-2026.07/.config` `sha256 ce84f68e…`.

| Wave-2 claim | This pass | |
|---|---|---|
| No QSPI command or driver in U-Boot proper | **Resolved `.config`:** the hook's §7 regex (`^CONFIG_(ENV_IS_IN_UBI\|…\|BLOBLIST)=`) has zero hits; `# CONFIG_CADENCE_QSPI is not set`, `# CONFIG_MTD is not set`, `# CONFIG_CMD_UBI is not set`, `# CONFIG_BLOBLIST is not set`; `ENV_IS_IN_UBI`, `CMD_SF`, `SPI_FLASH*`, `DM_SPI_FLASH`, `MTD_UBI` have no line at all; `CONFIG_ENV_IS_IN_FAT=y`, `mmc` `0:1` `uboot.env`. **Linked binary** (`nm` on the ELF's linker lists): 104 commands, none named `sf`/`ubi`/`ubifs`/`mtd`/`mtdparts`/`nand`/`rsu`; 43 DM drivers, none matching `qspi`/`spi_flash`/`mtd`/`nand`; **the only env driver is `fat`**; the only symbol containing `qspi` is `cm_get_qspi_controller_clk_hz` — a clock-manager register read that `arch_misc_init()` (`misc_soc64.c:106`) folds into the `qspi_clock` env string. `strings` of the FIT has **0** lines equal to any of those command names. `sspi` (`CMD_SPI`) is present, but the only SPI bus driver is `dw_spi` (`spi_generic_drv` on top): the Cadence controller behind the SDM has no driver in the binary to be reached through. | **[V]** |
| FIT is unsigned crc32 at the factory SPL's addresses | `dumpimage -l` (the build's own `tools/dumpimage`, 2026.07 — `host/bin/dumpimage` does not exist because the tree was rebuilt through `uboot` only): `uboot` Standalone Program, AArch64, **load `0x80200000`**, 647,448 B, crc32 `0559fc8a`; `atf` Firmware, OS ARM Trusted Firmware, **load `0x80000000`**, 53,304 B, crc32 `efc1cf2a` (`entry = <0x80000000>` in the decompiled FIT); `fdt-0` Flat Device Tree, description **`socfpga_agilex5_de25nano`**, 23,584 B, crc32 `64e75874`; default configuration **`board-0`**, `firmware = "atf"`, `loadables = "uboot"`, `fdt = "fdt-0"`, **`Sign algo: crc32:dev`, `Sign value: unavailable`**; `dtc -I dtb -O dts` → `grep -icE 'rsa\|required\|sha[0-9]'` = **0**. Every §6.2 contract term holds. **Drift from §6.1's listing:** `Created:` is now `Fri Sep  4 10:16:40 2026` (Buildroot 2026.08's epoch, not 2026.05.2's `Aug 23`) and the `uboot`/`fdt-0` payloads are 647,448/23,584 B (were 654,016/23,176) — a stale listing, not a changed contract. Address map recomputed: BL31 `0x8000_0000`–`0x8000_D038`; U-Boot `0x8020_0000`–`0x8029_E118`; FIT staging `0x8200_0000`+`0xB1240`; no overlap, `BL31_LIMIT` = staging base as before. | **[V]** |
| BL31 issues no QSPI/RSU command at boot | `bl31_platform_setup()` (`plat/intel/soc/agilex5/bl31_plat_setup.c:166-191`) is the delay timer, the GICv3 init, `mailbox_init()` (`SIP_SVC_V3`) and `mailbox_hps_stage_notify(SSBL)`. The one QSPI string in `bl31.bin` (`MBOX: 0x%x: QSPI address not 4K aligned`) is `socfpga_sip_svc.c:1242`, inside an SMC handler. `mailbox_rsu_status` is linked, but its only callers are the SMC RSU-status/DCMF handlers; `mailbox_rsu_update` runs from the PSCI reset path **only** if `intel_rsu_update_address` was set by an `RSU_UPDATE` SMC first; `ros_qspi_get_ssbl_offset` is BL2-only and no `ros_` symbol is in `bl31.elf`. | **[V]** |
| Kernel has no MTD/spi-nor/RSU driver; DTB has no flash node | **Not re-run.** `output-de25/` currently holds no `Image`, no `.dtb` and no `linux-7.x` build directory (DU1/DU2 rebuilt it through `uboot` only; `images/` is `u-boot.itb` + `bl31.bin`). Wave 2's [V] stands for the 2026-09-02 kernel; the next `make de25` should repeat the check (`board/mister/de25nano/linux.config` has not changed since wave 3, but that is a config, not a binary). | **[U]** — no kernel in the tree |
| Nothing writes anything a power cycle does not clear | The only env driver is `fat` on our SD card (`mmc 0:1`, `uboot.env`) — not flash. `objdump`: `env_save` has exactly **one** caller, `do_env_save` (the interactive `saveenv`); `env_fat_save` is reached from nowhere else. The built default env is `bootcmd=run distro_bootcmd`, `boot_targets=mmc0 `, `bootcmd_mmc0=devnum=0; run mmc_boot`; `bootcmd_qspi`/`bootcmd_nand` absent; the string `saveenv` occurs once, as the command name beside its help text. `# CONFIG_EFI_LOADER is not set` (no `ubootefi.var` on the card), `# CONFIG_BOOTCOUNT_LIMIT is not set`, `# CONFIG_ENV_OVERWRITE is not set`. Precisely: nothing writes *unless a person types `saveenv`*, and then to the card's FAT, which a re-`dd` clears. | **[V]** |

### The three additions DU7 asked for

**1. Does the DU2 hook fire on the DE25 tree and not the DE10's?** Yes, by `make` evaluation
with an **absolute** `O=` (see the finding below for why that matters), nothing built:

```
$ make O=/mnt/source/Buildroot_MiSTer/output-de25 printvars VARS='UBOOT_%_HOOKS MISTER_UBOOT_% UBOOT_KCONFIG_FRAGMENT_FILES BR2_TARGET_UBOOT_BOARD_DEFCONFIG'
BR2_TARGET_UBOOT_BOARD_DEFCONFIG="socfpga_agilex5"
MISTER_UBOOT_DE25_QSPI_AUDIT=	@set -eu; cfg='./.config'; itb='./u-boot.itb'; frags='…/board/mister/de25nano/uboot.fragment'; …
UBOOT_KCONFIG_FRAGMENT_FILES=/mnt/source/Buildroot_MiSTer/board/mister/de25nano/uboot.fragment
UBOOT_POST_BUILD_HOOKS=MISTER_UBOOT_DE25_QSPI_AUDIT
$ make O=/mnt/source/Buildroot_MiSTer/output printvars VARS='…same…'
BR2_TARGET_UBOOT_BOARD_DEFCONFIG="socfpga_de10_nano"
MISTER_UBOOT_DE10_CONFIG_AUDIT=	@set -eu; …            ← U3's hook, working tree, not the DE25 one
UBOOT_KCONFIG_FRAGMENT_FILES=/mnt/source/Buildroot_MiSTer/board/mister/de10nano/uboot.fragment
UBOOT_POST_BUILD_HOOKS=MISTER_UBOOT_DE10_CONFIG_AUDIT
```

No `MISTER_UBOOT_DE25_*` variable exists on the DE10 tree and no `MISTER_UBOOT_DE10_*` on the DE25
tree **[V]**. That the hook *executes* inside the stamp recipe, not merely that it is wired, is
the DU2 restore log (PASS line between `Building` and `Installing`), and the current `external.mk`
body is the one that ran there (`git diff HEAD -- external.mk` is a single appended hunk — the
DE10 block; the DE25 block is as committed) **[V]**.

**Finding (method, not product) — a relative `O=` evaluates an empty tree.** The wrapper
`Makefile`'s `%:` rule forwards `O=$(O)` verbatim into `make -C work/buildroot`, and Buildroot
canonicalises `O` against *its own* directory, so the documented form `make O=output-de25 …`
(`Makefile:9`, `:82`) resolves to `work/buildroot/output-de25` — which exists, is empty, and has
no `.config` (`make O=output-de25 printvars VARS=O` → `O=/mnt/source/Buildroot_MiSTer/work/buildroot/output-de25`;
`BR2_DEFCONFIG` prints nothing). Every `printvars` claim gathered with a relative `O` — the
"[V, evaluated 2026-09-14]" in `external.mk`'s DE25 comment, the DU2 verifier's DE10-inertness
line, and by the timestamps (14:18) the U3 agent's own check — was therefore **vacuous: it prints
nothing for *any* variable on either tree.** With an absolute `O` the real answer agrees on the
point that matters (no DE25 hook on the DE10), but the comment's literal text ("prints neither
`UBOOT_POST_BUILD_HOOKS` nor any `MISTER_UBOOT_*`") is now false on two counts. `make de25` and
`make all` pass an absolute `O` and are unaffected. Owed: fix the wrapper (`$(abspath $(O))`) or
the docs, and re-word that comment — outside DU7's file scope. The empty
`work/buildroot/output{,-de25}/` directories are the footprint; left in place.

**2. Is the `linux_qspi_enable` carve-out exactly one line with one verb?** Yes:
`strings images/u-boot.itb | grep -E '<the 11 verbs>'` returns **one** line (4624,
`linux_qspi_enable=if sf probe; then echo Enabling QSPI at Linux DTB...;fdt addr ${fdt_addr}; …`)
and that line contains **one** verb (`sf probe`) **[V]**. The make-expanded hook body (lifted
from `printvars`, run with `sh -c` in the real build directory — a verbatim execution, not a
replica, and not a rebuild) prints `PASS -- fragment, resolved .config and u-boot.itb all clean`;
four mutated scratch copies of the inputs each fail on the intended check: the fragment plus
`CONFIG_ENV_IS_IN_UBI=y` (the literal DU2 Done-when) fails at check 1 naming the fragment and
both docs; `.config` plus `CONFIG_CMD_SF=y` fails at check 2; the FIT plus an appended
`bootcmd_qspi=… ubi part root` fails at check 3; the FIT plus a *second* line with the exempt
head fails at check 3 (`nallowed > 1`) **[V]**. Two honest limits: the strings check is a tripwire,
not the lock — `sf` is not a command in this binary, so any such string is inert, and the lock is
check 2's proof that `CADENCE_QSPI`/`CMD_SF` are absent; and on the SPL side
`CONFIG_SPL_SPI=y`, `CONFIG_SPL_SPI_FLASH_SUPPORT=y`, `CONFIG_SPL_SPI_FLASH_TINY=y` resolve **on**
(outside the hook's `^CONFIG_` anchor by design, and contrary to the fragment's comment at
lines 127-133 that the SPL block removes the stack), but `spl/u-boot-spl` links no
`cadence_qspi`/`spi_flash` symbol and `images/` holds only `u-boot.itb` and `bl31.bin` — our SPL
ships nowhere, as §4.5 already says **[V]**. Cosmetic; noted for DU4's fragment pass.

**3. Does `scripts/ci-tests.sh`'s DE25 section behave on the real `output-de25/target`?** The
section (helpers `:141-169` + the section `:480-520`, extracted verbatim) against the real target —
a 7.7 MB skeleton from a `uboot`-only build, zero `fw_env.config`, no `fw_setenv`/`libubootenv` —
prints `PASS  DE25 rootfs: no fw_env.config shipped -- nothing to audit`. Synthetic trees: a
`/dev/mtd0` line → `FAIL … de25-boot-chain.md section 7 row 11 …` with the offending line
echoed; a FAT-path file whose only `ubi` is in a `#` comment → PASS (the comment filter works);
no tree → SKIP. `shellcheck` and `bash -n` clean **[V]**. Limit: the real target exercised only the
trivial branch; the check has not yet seen a fully populated DE25 rootfs **[U until the next
`make de25`]**.

### Verdict and drift list

No brick-class or boot-blocking finding. Every wave-2 U-Boot and BL31 claim re-verifies against
`f4e5c924…` / `2052e4c9…`; the two kernel-side legs are **[U]** for want of a kernel in the tree,
not for any contrary evidence; the DU2 hook fires where it should, executes where it should, and
its carve-out is as narrow as its comment says. One method finding (relative `O=`) invalidates the
*evidence* behind an `external.mk` comment without changing its conclusion. Documentation now
behind the artifacts, for whoever next edits each file: `de25-uboot.md` §6.1 (timestamp, two
payload sizes), §2 TF-A row and §12 TF-A row (DU6 verified the signature), §3 file table
(`uboot.hash` gone); `external.mk` DE25 comment (relative-`O` evidence; the DE10 tree now has a
hook); `docs/buildroot-config.md` §6.9; `docs/uboot-mainline-port.md` §3.6.

## Wave 5 — 2026-09-23 (pre-hardware): re-verify at 7.2.7, identity check, manual CI lane

Branch `feat/de25-prehw-verify`. Evidence is from a from-scratch `make de25` on the workstation
(24 min; logs outside the repo).

| Item | Result |
|---|---|
| `make de25` at the current pin (kernel **7.2.7**, after #203's IPv6 change) | Green. **34/34** patches in `.applied_patches_list`, no fuzz or failed hunks; 92 modules **[V]** |
| DU7's two kernel legs, [U] above for want of a kernel | Resolved `.config`: `MTD`, `SPI_CADENCE_QUADSPI`, `INTEL_STRATIX10_RSU` not set; `MTD_SPI_NOR`, `MTD_UBI` absent; no mtd/spi-nor/quadspi/rsu module. DTB: `spi@108d2000` `status = "disabled"` with no child, zero `jedec,spi-nor`/`partition` nodes; `svc` → `fpga-mgr` ← `fpga-region` wired. **[V]** — both legs closed |
| `check-sdcard-de25.sh` | All assertions pass on `sdcard-de25.img` (537,919,488 B) **[V]** |
| `ci-tests.sh` DE25 section on a *populated* rootfs | `PASS DE25 rootfs: no fw_env.config shipped` against the real 71 MB target (DU7 addition 3's [U] closed); whole suite 211/0/6 **[V]** |
| `test-initramfs.sh --board de25nano` | **8/8** on 7.2.7, with the stage-1 package built alone (the card still does not embed it, D11) **[V]** |
| FIT | `u-boot.itb` 725,560 B: uboot@`0x80200000`, atf@`0x80000000`, `fdt-0`, `board-0`, `crc32:dev`, unsigned — contract unchanged; hashes move with the toolchain banner as §5b says |
| ADR 0027 Decision 4 | **Code now exists, on the DE10 side:** `assert_board` in `install.sh` and the updater (see `downloader-contract.md` §13). It was run on the DE10 rig (7.2.6), where it reads `terasic,de10-nano`/`altr,socfpga-cyclone5`/`altr,socfpga` and accepts. The DE25 updater must carry the same block keyed on `intel,socfpga-agilex5` |
| DU7's relative-`O=` finding | Fixed in the wrapper (`override O := $(abspath $(O))`); `make O=output-de25 printvars` now evaluates the real tree |
| CI | `de25-build.yml`, `workflow_dispatch` only ([`ci.md#de25-manual-lane`](ci.md#de25-manual-lane)). D1.2 (a board parameter for `buildroot-build`) is deliberately **not** done: the manual lane does not use the action |

## What to do next — 2026-08-22

D0 and D1 are done; the opening move this section used to describe has been executed. The live
work now, in the order that unblocks the most:

Waves 1 and 2 executed items 1–5 of the original list and the first three of the wave-1 list.
Remaining, in unblock order:

1. **Hardware session** on a borrowed board (QSPI at factory): factory SPL boots our FIT → serial
   login → SD under the 25 MHz cap → `dd` the card clean → lift to 50 MHz → the §2.6 fabric
   test, SMMU-off first.
2. ~~**`scripts/test-initramfs.sh` aarch64 path** (`qemu-system-aarch64 -M virt`) and the aarch64
   initramfs itself, which the two-stage layout will need.~~ **DONE 2026-09-06** (wave 3).
   What it surfaced, and what the same PR fixed: **patch 0031 (exFAT Samsung symlinks) Oopsed
   on symlink creation on every 7.x kernel** — `page_symlink()` calls
   `a_ops->write_begin`, which 7.x exFAT (iomap) no longer has (ADR 0002 §8b). Affected the DE25
   AND the DE10's RT 7.2.3 kernel (same patch file by symlink). ~~Re-anchor 0031 for 7.x (write
   the link target without `page_symlink`), in `linux-patches-beta/` as a beta-local copy and
   pointed to from the DE25 series; the aarch64 leg's `symlink` case is the acceptance test —
   it is the ONLY place 0031-on-7.x is executed rather than compiled.~~ **DONE 2026-09-06:**
   beta-local copy, DE25 series relinked, aarch64 leg 8/8, arm compile clean on the RT config.
   ~~Remaining: the first `ln -s` on an RT-booted DE10 (32-bit 7.x is still compile-only).~~
   **2026-09-11:** executed as 32-bit ARM by `scripts/test-initramfs.sh --kernel rt` (7.2.4,
   `symlink`/`exfat`/`fsck-request` pass; the 6.18-form patch on 7.2.4 reproduces the Oops),
   after the rig, still on a pre-rewrite RT 7.2.3, panicked on the Arcade Organizer's first
   symlink (ADR 0002 §8b). Hardware boot of the fixed RT kernel still owed.
3. **Owner decisions still open**: a Renovate manager for the DE25 kernel pin; upstream
   submission of 0101/0102; patch 0002 (audio). Hardware is expected after the owner's vacation
   (ordered on return).
   **2026-09-14:** the DE25 U-Boot's remaining *desk* work (the §7 QSPI-audit CI check, the
   redundant custom version pin now that Buildroot 2026.08 bundles 2026.07, FIT cross-tree
   reproducibility, the TF-A signature, `docs/de25-uboot.md` §13's seven decisions) is planned
   as the DU-series in [`docs/uboot-tasks.md`](uboot-tasks.md), alongside the DE10's.
4. **Stand up D0.4** as a `/schedule` routine.

Sequencing note learned the hard way on 2026-08-21: when a research phase feeds a claim set that a
later phase must refute, run them **sequentially**, not in parallel. D0.1 was first launched with
its Q-legs and refuters concurrent; 17 of the 22 brick-risk claims turned out to be *generated by*
the Q findings, so the refuters would have attacked a claim set that no longer existed. Resequenced
and re-run, the refuters killed or amended 8. Parallelising a verify stage against the stage that
produces what it verifies is a false economy.
