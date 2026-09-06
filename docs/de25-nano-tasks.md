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

A friend's DE25-Nano can run our SD images, with one condition that follows directly from
[`de25-boot-chain.md`](de25-boot-chain.md) §2: **the QSPI must hold the factory phase-1
image.** Our card ships `u-boot.itb` only and relies on the *factory SPL's* contract (FAT on
partition 1, FIT at `0x82000000`, boot order `mmc0`). A modified QSPI carries a different SPL
with a different contract — the reference board's, for instance, is exFAT-aware and RSU-shaped —
so a boot failure there would tell us nothing about our image.

- **Restore is the same tool he already used to modify it**: Quartus Programmer over the on-board
  USB-Blaster III, `quartus_pgm -m jtag -c 1 -o "pvi;golden_top_hps.jic"`, from the Resource
  Package (`…/GHRD/output_files/program_qspi_flash/`). Verify the file first:
  `golden_top_hps.jic` is 16,777,447 B, sha256 `e3d20c2d…38a4` (full hash in boot-chain §8).
- **Doing this on his board also closes an open [U] of ours**: that the *published* JIC boots a
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
| Config refactor (owner option 2) | `configs/fragments/*` stacks, monoliths deleted, comments → `docs/buildroot-config.md`, `scripts/check-config-fragments.sh` + golden hashes, `lint-config` CI job | PR #137. DE10 resolved config identical old vs new (two independent proofs); fingerprint residue byte-identical; 30+ mutations exercised; kernel-pin bumps don't move the golden, Buildroot bumps warn and are auto-refreshed by hash-sync case 8. |

### What the boot-path `fable` pass established (for the borrowed-board owner)

No brick-class or boot-blocking finding. Verified in the built artefacts, not the config: no QSPI
command or driver in U-Boot proper; BL31 issues no QSPI/RSU command at boot; the kernel has no
MTD/spi-nor/RSU driver and its DTB has no flash node; the FIT is unsigned-crc32 at the addresses
the factory SPL expects; nothing writes anything a power cycle does not clear. First-boot
expectations worth knowing: BL31 prints on UART0, so **no `NOTICE: BL31` lines on the header
UART** is normal; capture the SPL's `DDR:` lines (the only real DRAM-size measurement); if
`Retrieving file: /Image` stalls, the SD PHY timing in `uboot-dts/` is the first knob
(`de25-uboot.md` §5.1).

### Still open after wave 2

- ~~p2 filesystem / DE10-style two-stage layout~~ **Decided 2026-09-03 (ADR 0029 D11):** the
  two-stage layout is the target; the plain ext4 card stays until hardware. Owed before the
  switch: an aarch64 stage-1 initramfs stack + its QEMU test path.
- The DE25 kernel pin has no Renovate manager and shares `linux.hash` by symlink with the DE10
  registry, so an rt bump replaces the 7.2.y hash line rather than adding one. **This happened on
  2026-09-02** (rt 7.2.2 -> 7.2.3): the DE25 pin was moved to 7.2.3 in the same series of commits
  and the series/config were re-verified there (34/34 patches at `-F0`, 460 symbols 0 dropped,
  `docs/de25-kernel-config.md` §8). Still needs its own Renovate manager, or a hash-sync rule that
  keeps every line a fragment still pins, so the next bump is not manual.
- ~~DE25 selects no `linux-firmware`~~ **Decided 2026-09-03 (ADR 0029 D12):** mirror the DE10
  set via a shared `image-common` fragment (PR in flight); seccomp stays off as on the DE10.
- Patch 0002 (MiSTer audio) still excluded; `openssh` will need `_SANDBOX` off when added.

## What to do next — 2026-08-22

D0 and D1 are done; the opening move this section used to describe has been executed. The live
work now, in the order that unblocks the most:

Waves 1 and 2 executed items 1–5 of the original list and the first three of the wave-1 list.
Remaining, in unblock order:

1. **Hardware session** on a borrowed board (QSPI at factory): factory SPL boots our FIT → serial
   login → SD under the 25 MHz cap → `dd` the card clean → lift to 50 MHz → the §2.6 fabric
   test, SMMU-off first.
2. **`scripts/test-initramfs.sh` aarch64 path** (`qemu-system-aarch64 -M virt`) and the aarch64
   initramfs itself, which the two-stage layout will need.
3. **Owner decisions still open**: a Renovate manager for the DE25 kernel pin; upstream
   submission of 0101/0102; patch 0002 (audio). Hardware is expected after the owner's vacation
   (ordered on return), so the aarch64 initramfs stack and its QEMU path are the pre-hardware
   work that remains. Item 2 above should be done before the board arrives.
4. **Stand up D0.4** as a `/schedule` routine.

Sequencing note learned the hard way on 2026-08-21: when a research phase feeds a claim set that a
later phase must refute, run them **sequentially**, not in parallel. D0.1 was first launched with
its Q-legs and refuters concurrent; 17 of the 22 brick-risk claims turned out to be *generated by*
the Q findings, so the refuters would have attacked a claim set that no longer existed. Resequenced
and re-run, the refuters killed or amended 8. Parallelising a verify stage against the stage that
produces what it verifies is a false economy.
