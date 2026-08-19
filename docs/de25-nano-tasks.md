# DE25-Nano tasks — ultracode execution plan

**Parent plan:** [`de25-nano-plan.md`](de25-nano-plan.md) · **Decision:**
[ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md).

This task list is written to be executed under **ultracode** (multi-agent Workflow
orchestration): invoke a task with the `ultracode` keyword, or run the whole active
phase as a sequence of one-workflow-per-task turns. Each task below specifies the
orchestration shape and the *smallest agent tier that can do the work honestly* —
over-tiering wastes tokens, under-tiering produces confident nonsense in exactly the
places (boot flow, flash paths) where this board can be bricked.

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

## Phase D0 — Recon (no gate; run any time; pure research)

### D0.1 Boot-chain contract dossier → `docs/de25-boot-chain.md`
The Agilex-5 analogue of `docs/boot-chain.md`, same rigor: SDM boot stages; exactly
which artifacts live in QSPI vs SD for an HPS-first boot; SD layout the SDM/FSBL
expects; U-Boot env location; warm-reboot story; what a power-loss-safe boot-firmware
field update looks like (the `updateboot` analogue — including whether QSPI is ever
written and the recovery path if it's interrupted). Primary sources: DE25-Nano User
Manual (DigiKey PDF P0804), Terasic System CD, Altera GSRD boot-example docs
(rel-24.x/25.x), RocketBoards Agilex-5 bootloader doc, mainline U-Boot + ATF source.
- **Status 2026-08-19:** a desk-research first pass exists —
  [`de25-boot-chain.md`](de25-boot-chain.md) (boot chain, QSPI/SD split, MSEL table,
  postures, brick inventory §7). **The task narrows to that doc's §8 Q1–Q6** (SDM-from-SD
  on this board incl. a Terasic inquiry, factory QSPI contents, FSBL→`u-boot.itb`
  contract, RSU sizing, env location, DDR-handoff coupling) plus the adversarial-verify
  pass over §7's brick-risk claims, which have not yet survived refutation.
- **Orchestration (narrowed):** 1 `sonnet` leg per open Q (≤6, medium) → 1 `opus`
  synthesis into the doc → `fable` adversarial verify (3 refuters, high) on §7.
  ~10 agents.
- **Accept:** every §8 Q resolved to [V] or explicitly parked with a named blocker
  (hardware-gated items hand off to D2.2); §7 survived refutation.

### D0.2 FPGA reconfig + shared-memory dossier → `docs/de25-fpga-reconfig.md`
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
Classify every patch in `board/mister/de10nano/linux-patches/` (36) and
`linux-patches-beta/` (40; audit the union once, note series membership) as
**portable-as-is / portable-with-rework / board-specific / superseded-upstream-by-6.18+**
for an arm64 Agilex target. Must consult `docs/patch-provenance.md` and
`docs/kernel-recon/`; provenance dispositions carry (e.g. 0037/BTN_Z is functional, not
cosmetic — dropping it breaks gamecontrollerdb indexing; any "drop" verdict needs the
provenance record cited).
- **Orchestration:** pipeline over ~44 unique patches — per patch 1 `sonnet` (low
  effort: read patch + provenance record, emit verdict via schema) → `opus` dedup +
  series-level synthesis → `fable` spot-verify every *portable* verdict that touches
  `arch/`, DTS, or Kconfig (expect ~6–10). ~55 agents total — run with the size
  guideline raised, or in two batches (main series, then beta delta).
- **Accept:** a table with one row per patch, verdict + one-line rationale + provenance
  cite; totals reconciled against the plan's "~28 portable / ~8 board" estimate, with
  deltas explained.

### D0.4 Upstream watch (recurring; NOT an ultracode task)
Monthly brief: MiSTer framework/aarch64 port signals, Terasic BSP/System-CD releases,
mainline `agilex5` movement, MiSTeX direction. Too small for a workflow — a scheduled
routine (`/schedule`, monthly) with 2–3 web-search legs appending dated entries to
`docs/de25-watch.md`. Trigger review: any entry that flips a D2/D3 gate gets surfaced,
not silently logged.

## Phase D1 — Readiness guards (no gate; opportunistic, cheap)

### D1.1 Coupling ledger → `docs/de25-readiness-ledger.md`
Inventory every hard-coded `de10nano` / `BR2_arm` / zImage-semantics site (survey found
~14 scripts, 4 CI files, 4 defconfig path lines, `external.mk`'s initramfs default) and
write the per-file "when you touch this, do this instead" instruction. Code changes are
**not** required — the ledger is the deliverable; zero-risk `BOARD=` variable
introductions may be proposed as a follow-up diff for separate review.
- **Orchestration:** 3 `haiku` inventory sweeps (scripts / CI / configs+mk, low) →
  per-hit 1 `sonnet` ledger entry (batched, ~4 agents) → 1 `opus` review pass. ~8 agents.
- **Accept:** ledger covers 100% of a fresh grep for `de10nano|BR2_arm|zImage` outside
  `board/mister/de10nano/` and `docs/`; each entry is actionable in one sentence.

### D1.2 Arch-assert generalization design (design only)
Spec (not implement) the per-board expected-symbol tables for
`scripts/check-kernel-defconfig-sync.sh` and the buildroot-build action's toolchain
fingerprint, so DE25's defconfig lands against ready guards rather than weakened ones.
- **Orchestration:** 1 `sonnet` (high) draft → 1 `opus` review. 2 agents (barely
  ultracode; fine to run inline).
- **Accept:** the design keeps both checks fail-closed for DE10 exactly as today.

### D1.3 Channel namespace reservation (docs only)
Cross-reference ADR 0027 §Decision-4's reserved names (tags `de25-YYYYMMDD`,
`db-de25nano.json`, db_id, updater script name, board-identity assertion) into
`docs/downloader-contract.md` (a short forward-pointer section) and
`docs/db-json-versioning.md`. 1 `sonnet` agent, inline; no workflow.

## Phase D2 — Bring-up (gate: hardware in hand) — produces L1

Hardware-in-the-loop work does not fan out; ultracode's role in D2 is the *design and
review* passes around each step, not the step itself. Every flash/QSPI-touching script
gets a `fable` adversarial review before it ever runs on the board (rule 2).

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

## Suggested first invocation

With no hardware and no framework, the only live work is D0 + D1. A reasonable single
opening move:

> ultracode — run D0.1 and D0.2 from docs/de25-nano-tasks.md as two sequential
> workflows, then D1.1. Standing rules 1–3 apply; tag everything [V]/[U].

D0.3 (⚠ size) is worth a dedicated turn with the size guideline raised. D0.4 is a
`/schedule` routine, not a workflow.
