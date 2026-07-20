# docs/ci.md — Structure, Policy, and Implementation Spec

> ## ⚠️ CORRECTION — read before using this document
>
> This is a **spec for authoring `docs/ci.md`**, not `docs/ci.md` itself. Do not
> rename it into place: it contains agent-facing instructions, disagreement
> callouts and process accounting that must not ship to maintainers.
>
> **The paragraph below is WRONG, and so are §4-D and §5.** The synthesis agent
> was handed a truncated view of the triage data (the orchestrating script capped
> its input at 90k chars — my bug, not a triage failure). Corrected facts:
>
> * **All 8 files were triaged successfully.** None failed, none truncated.
> * **232 blocks total**, every one classified, with complete `totals` for each file.
> * `build.yml` (37 blocks), `reproducibility.yml` (15), `publish-db.yml` (16),
>   `fork-sync.yml` (13), `renovate-validate.yml` (5) **were triaged** — ignore
>   every "(unverified feeder)" marker and every "never triaged" claim below.
> * `renovate-hash-sync.yml` was **not** truncated: 31 blocks, 267 → 41 lines.
> * **Real totals: 1831 → 582 inline comment lines (−1249, −68%). Zero drops.**
>
> §5's "verified subtotal (2 files)" and §4-D items 15–16 are artifacts of the
> truncation. Authoritative data: `.ci-refactor/comment-triage.json`.
>
> Everything else — the 50-section ToC (§1), the R1–R5 house style (§2), the
> ranked load-bearing list (§3), and §4-A/B/C — was derived from the blocks the
> agent *could* see and from the verification pass, and stands.

---

## 1. docs/ci.md table of contents

Ordered for a single top-to-bottom read: orientation → the shared recipe → caching (the biggest trap cluster) → release → auxiliary workflows → conventions → incident index.

### Part I — Orientation

| # | Section | Anchor | Scope (one line) | Fed by |
|---|---|---|---|---|
| 1 | Pipeline map | `#pipeline-map` | The workflows, their jobs, and who triggers whom (build.yml, release.yml, publish-db.yml, reproducibility.yml, renovate-hash-sync.yml). | *new prose* + release.yml header |
| 2 | Why one shared build recipe | `#why-shared-recipe` | The five-failed-run consolidation incident (ENOSPC, missing defconfig, busted toolchain caches); why no workflow may fork a private copy. | action.yml 1–10 |
| 3 | Caller vs recipe ownership boundary | `#recipe-boundary` | Where the composite action's responsibility starts and ends; what callers own. | action.yml 11–16, 59–64 (both **kept inline**; docs restates as the canonical contract) |
| 4 | No `container:`, and why disk reclaim must run first | `#no-container-disk-reclaim` | **MERGED**: the same reasoning in action.yml, release.yml, build.yml, reproducibility.yml. ~30GB reclaim, output/ is 24GB, ENOSPC run 29295920820. | action.yml 110–119; release.yml 269–272; reproducibility.yml 107–112 *(unverified feeder)* |

### Part II — Variants

| # | Section | Anchor | Scope | Fed by |
|---|---|---|---|---|
| 5 | Variants: main vs kernel-only | `#variants` | What a variant is, the `configs/mister_<name>.fragment` registry-by-existence rule, what derives from the name, how to add one. | action.yml 39–58, 155–165, 177–181; release.yml 127–135, 140–143 |
| 6 | Kernel-variant matrix design | `#kernel-variant-matrix` | Why the matrix ships full legal-info (GPL source) not an SBOM; why no MISTER_VERSION derivation in the kernel leg. | release.yml 127–139 |
| 7 | Build step & fail-in-CI-not-on-device | `#build-step` | `make all` under one ccache; the Makefile's hard config assertion (`CONFIG_PREEMPT_RT=y`) as a CI-side gate. | action.yml 622–631, 641–650 |
| 8 | Configuring Buildroot | `#configure-buildroot` | Why `.config` is regenerated unconditionally every run; the stale-config incident (run 29293209070). | action.yml 604–616 |

### Part III — Caching (read this part in order; the sections are interdependent)

| # | Section | Anchor | Scope | Fed by |
|---|---|---|---|---|
| 9 | Cache inventory & budget | `#cache-budget-and-sizing` | The 5 input caches, GitHub's 10GB/repo LRU ceiling, cold vs warm sizes, why a small cache is *not* a broken ccache, why eviction is safe. | action.yml 17–32, 33–38, 350–367 |
| 10 | WS_FP: the workspace-path fingerprint | `#ws-fp` | Cross-toolchains bake absolute paths and are **not** relocatable; why ccache is the exception. | action.yml 139–147, 528–532 |
| 11 | Toolchain fingerprint: deny-list, not allow-list | `#toolchain-fingerprint` | The cortex-a9 silent-miscompile incident; the exclusion set; which defconfig each variant fingerprints; the intentional `grep` exit-1 under `pipefail`; the sentinel assert. | action.yml 197–232, 233–238, 250–253, 262–278, 286–289 |
| 12 | Cache keys: compute once, consume twice | `#cache-keys` | Why keys are computed in one step and consumed by restore+save; per-variant `br-<name>-host-` namespaces; never share entries. | action.yml 299–311, 316–325 |
| 13 | **Cache coupling: #2 (dl/) and #3 (toolchain)** | `#cache-coupling` | The flagship trap. Toolchain stamps lie about dl/'s contents; restoring #3 without #2 cost run 29534917900 (46 min). Where the `if:` enforces it. | action.yml 391–423, 481–496, 505–517, 673–680 |
| 14 | The dl/ cache | `#dl-cache` | Lives at repo root so `make clean` can't wipe it; keyed on full defconfig with version-only restore-keys. | action.yml 435–443 |
| 15 | Variant dl/ fallback to main | `#variant-dl-fallback` | Why falling back to main's dl/ is safe *despite* §13's coupling hazard (subset/superset stamp reasoning). | action.yml 454–469 |
| 16 | dl/ completeness before save | `#dl-completeness` | The immutable-key stub lock-in trap; why a size floor fails (run 29534917900); the `BR2_CCACHE=y` oracle flag (158 vs 163 files); the basename filter's assumptions. | action.yml 682–695, 696–701, 702–720, 728–736 |
| 17 | Cache save policy | `#cache-save-policy` | **MERGED**: dl/ saves via `always()`, toolchains save GREEN-ONLY (implicit `success()`); a half-built `output/host` with stamps is a poisoned toolchain. Includes `#dl-cache-save` (the `\|\|` key resolution keeping a variant's save in its own namespace). | action.yml 369–390, 771–782, 797–815 |
| 18 | ccache key naming | `#ccache-key` | Why `append-timestamp: false` must never be set; hit-rate decay under an immutable key. | action.yml 544–556 |

### Part IV — Release

| # | Section | Anchor | Scope | Fed by |
|---|---|---|---|---|
| 19 | Release consumers | `#release-consumers` | The three downstream actors: human, on-device Downloader_MiSTer, RT beta opt-in. | release.yml 5–31 |
| 20 | Rebuild, don't adopt | `#rebuild-not-adopt` | Why release.yml rebuilds *and* re-verifies from the tagged commit instead of reusing build.yml's run/artifacts. | release.yml 32–40, 41–48, 418–426 |
| 21 | **MiSTer.version / filename / db.json coupling** | `#mister-version-coupling` | The version is deliberately decoupled from the git tag and driven by `/MiSTer.version` (ADR 0018); three values must agree byte-for-byte. | release.yml 76–89, 333–339, 535–557 |
| 22 | Tag convention (unratified) | `#tag-convention` | `v*` is not yet ratified. | release.yml 76–89 |
| 23 | Stock payload sourcing & verification order | `#stock-payload-sourcing` | **MERGED (8 call sites)**: G6 no-binaries-in-git; the hash pins; the deliberately floating ARM 7za URL; verify-fully-before-extracting; host 7za vs pinned ARM 7za; LZMA2-not-BCJ2; the Downloader-mirroring extraction pattern. | release.yml 49–66, 301–306, 316–324, 380–386, 601–607, 644–650, 669–676, 692–696, 700–705 |
| 24 | Open decision: third-party payload dependency | `#stock-payload-open-decision` | Unratified reliance on a third-party git blob (mt32-rom-data, soundfonts). | release.yml 67–75 |
| 25 | dist/ layout contract | `#dist-layout` | The 7 Downloader-contract assets + per-variant extras + sdcard images; publish uploads verbatim; the glob-must-match staging rule. | release.yml 456–466, 523–527 |
| 26 | legal-info and the 2 GiB asset cap | `#legal-info-2gib-cap` | `host-sources/` must stay excluded — with it the archive measured 2109 MiB vs GitHub's 2 GiB per-asset hard cap. | release.yml 486–503, 513–514 |
| 27 | ABI check in a clean checkout | `#release-abi-check` | Stock-binary gates A-10/A-22 silently SKIP here because `work/` is gitignored — not a broken check. | release.yml 447–452 |
| 28 | sdcard: standalone assets | `#sdcard-contract` | Never inside `release_YYYYMMDD.7z`, never referenced by db.json (ADR 0017/0020). | release.yml 793–805 |
| 29 | sdcard timing and the 6-hour cap | `#sdcard-timing-6h-cap` | 355-min timeout; sdcard steps reuse `output/` (relink only); the from-scratch design that overran 360 min and never published. | release.yml 278–292 |
| 30 | Full-sdcard manual dispatch | `#manual-full-sdcard-dispatch` | Dispatch against a **tag** or publish silently no-ops; the skip/reuse condition; `--clobber` partial refresh. | release.yml 99–105, 807–821, 867–871 |
| 31 | Publish job scope & the draft gate | `#publish-job-scope` + `#release-draft-gate` | Why publish is a separate job with elevated scopes; the tag-ref guard; **the draft state is the human-approval gate before publish-db.yml offers the update to every subscribed device**. | release.yml 939–947, 953–956, 993–1002 |
| 32 | Provenance attestation scope | `#attest-provenance-scope` | Only the shipped binaries are attested, not dist/ metadata. | release.yml 979–984 |
| 33 | The GH_REPO bug | `#gh-repo-bug` | `gh` ignores `$GITHUB_REPOSITORY`; without `GH_REPO` a green ~9h build produces no release, silently. Inherited from origin/master. | release.yml 1006–1019 |
| 34 | Release asset array | `#release-assets-array` | RT assets unconditional (fail loud), sdcard assets conditional; upsert not create-only. | release.yml 1025–1035, 1053–1058 |
| 35 | Retired two-image design | `#old-two-image-design-retired` | Historical contrast, explains three "no longer needed" absences in release.yml. | release.yml 136–139, 778–783, 965–969 |

### Part V — Renovate hash sync

| # | Section | Anchor | Scope | Fed by |
|---|---|---|---|---|
| 36 | Why it exists & trigger design | `#renovate-hash-sync-overview` | Renovate bumps a pin but cannot compute the companion sha256; same-repo Renovate PRs only; fork exclusion; idempotency. | renovate 5–12, 73–80, 178–182 |
| 37 | Safety model, cases 1–4 | `#renovate-hash-sync-safety-model` | Why each of packages / kernel / lzma-sdk / sdcard is safe to auto-refresh. | renovate 13–52 |
| 38 | Deliberately not automated | `#renovate-hash-sync-not-automated` | BUILDROOT_SHA256 (signed-manifest-only trust), cabextract, linux-firmware-extra, xow-firmware, and `mister_rt.fragment` (TOFU-pinned -rc, no signed manifest). | renovate 54–71, 121–127 |
| 39 | Manual dispatch escape hatch | `#renovate-hash-sync-dispatch-trap` | Run 29669946883 replayed old code 3×; the `branch` input is *not* the ref you dispatch from. | renovate 82–96, 144–156 |
| 40 | Branch-name validation | `#renovate-hash-sync-branch-validation` | Default-branch refusal; `check-ref-format`; **rejecting** (not normalising) `refs/heads/x` and `heads/x`. | renovate 198–201, 213–215, 221–235 |
| 41 | Branch name is attacker-controlled | `#branch-name-injection` | **MERGED** with release.yml's `EXTRA_APT`-via-env rule: never interpolate untrusted values through `${{ }}` into a shell. | renovate 189–193, 602; action.yml 574–577 |
| 42 | Kernel step traps | `#renovate-hash-sync-kernel-grep-bug` | Bug #42: unanchored grep matched a defconfig comment → 2-line `$kver` → malformed URL; the load-bearing `\|\| true` under `set -euo pipefail`; the `awk -v` backslash-eating regex trap; fail-loud-not-skip. | renovate 351–359, 360–365, 373–376, 435–438 |
| 43 | RT-line clobber | `#renovate-hash-sync-rt-line-clobber` | Match the major series; first-line or extension-only matching clobbered the RT entry (verified reproduction). | renovate 403–420 |
| 44 | Companion .hash file contract | `#companion-hash-first-line-only` | **MERGED (3 call sites)**: only the FIRST sha256 line is machine-owned; everything else is human-owned. | renovate 264–277, 336–339, 454–468 |
| 45 | Verification status | `#renovate-hash-sync-verification-status` | Only the kernel step is proven (PR #41); a green run can mean "silently skipped" (bug #42). | renovate 98–110 |

### Part VI — Conventions and index

| # | Section | Anchor | Scope | Fed by |
|---|---|---|---|---|
| 46 | apt dependencies | `#apt-deps` + `#release-apt-packages` | Per-package rationale tables: Buildroot's mandatory set + repo extras (build), host-only release-assembly tools (release). | action.yml 566–573; release.yml 390–397 |
| 47 | Artifact naming: the `/` trap | `#artifact-naming-slash-trap` | **MERGED (3+ call sites)**: `upload-artifact` rejects `/` in names and every branch here is slash-named — artifacts are sha-named. | release.yml 248–254, 439–441, 928–930; build.yml *(unverified feeder — its equivalent step carries no comment)* |
| 48 | Pin conventions | `#pin-conventions` | One `actions/checkout` SHA pin across all workflows so Renovate tracks one dependency. | renovate 251–254 |
| 49 | Shared-template refactor: the semantics we rely on | `#shared-template-semantics` | What is confirmed vs partial about composite actions and reusable workflows (see §4). | verification pass |
| 50 | Incident index | `#incident-index` | Table: run ID / bug ID → what happened → which section. | all files |

---

## 2. House style: what stays inline vs what moves

Five mechanical rules. Applied in order; first match wins.

**R1 — Terse-and-local stays.** A comment block of **≤5 content lines** that makes a **single** point about the **code immediately below it** stays verbatim. Do not touch it, do not add a pointer. *(This is why 14/47 blocks in action.yml and 25/72 in release.yml are `keep`.)*

**R2 — An imperative stays; its proof moves.** Any block containing a directive a future edit could violate — `MUST`, `NEVER`, `do NOT`, "load-bearing", "TRAP", a warning against a tempting simplification — is **split**: the imperative (plus the run ID / bug number that makes it credible) is compressed to **1–3 lines inline**; the narrative, the measurements, the mechanism walkthrough, and the "we tried X and it failed" reasoning move to docs. The inline remainder must end with `See docs/ci.md#<anchor>.`

**R3 — Pure description moves whole.** A block that only explains *what* the step does or *why* it is designed that way, with no action an editor must avoid, is replaced by a **one-line pointer**. If a step's own `if:`, `key:`, or name already states the fact, delete the prose entirely rather than pointer it.

**R4 — Say it once, across all files.** If the same reasoning appears in ≥2 files (or ≥2 places in one file), it gets **exactly one** docs section; every call site carries a short warning + the same anchor. Never `see the comment above` / `see build.yml's step` — cross-file and in-file textual references go stale on reorder; anchors do not.

**R5 — Numbers and inventories live in docs.** Measured GB/minute figures, file counts, package-by-package rationale, and asset enumerations belong in docs tables — *except* an incident's identifying run ID or bug number, which stays inline as the credential for R2's imperative. Pinned constants (hashes, URLs, sizes) stay in code as code; their prose justification moves.

**Formatting invariants for the implementing agent:** preserve the `#####` banner rules around section-header comments; keep `# shellcheck disable=` directives untouched (functional, not prose); anchors are lowercase-kebab and must match §1 exactly.

---

## 3. Load-bearing items, ranked

Ranked by *blast radius × silence* — how bad the failure is, times how likely it is to go unnoticed. Text in `code` is the exact inline remainder that must survive.

**Tier 0 — silent, ships wrong bits to devices or publishes nothing**

1. **`#gh-repo-bug`** — release.yml:1006. A green ~9h build produces no release at all. `GH_REPO required: no checkout here, and gh ignores $GITHUB_REPOSITORY — without it every `gh release` call dies at repo-resolution and a green ~9h build silently produces NO release.`
2. **`#mister-version-coupling`** — release.yml:76, 333, 535. Breaks the Downloader's update-offer logic for every subscribed device. `LOAD-BEARING: release_YYYYMMDD.7z / SHA256SUMS / db.json version must all equal the /MiSTer.version this job just baked (ADR 0018) — do not decouple.`
3. **`#toolchain-fingerprint` (deny-list)** — action.yml:197. Wrong `-mcpu` with no cache bust; miscompiled binaries that build green. `DENY-list, not ALLOW-list: an allow-list once silently missed BR2_cortex_a9=y (wrong -mcpu, no cache bust).`
4. **`#release-draft-gate`** — release.yml:993. Removing `draft:` turns CI into an unreviewed fleet-wide push. `Created as a DRAFT, deliberately: publish-db.yml only fires on a published (non-draft) release — this is the human-approval gate between "CI built an image" and "every subscribed MiSTer is offered it".`
5. **`#toolchain-save-policy`** — action.yml:797. A poisoned toolchain persists across runs. `GREEN BUILDS ONLY. No always() here on purpose (implicit success() gate); a half-built output/host WITH its stamps is a poisoned toolchain.`

**Tier 1 — expensive or lock-in failures, loud-ish but costly**

6. **`#cache-coupling`** — action.yml:391 (+481, +505). Cost 46 min once already. `#2 (dl/) and #3 (host toolchain) restores are COUPLED — never restore #3 without #2; its stamps lie about dl/'s contents (cost run 29534917900, 46min).`
7. **`#dl-completeness` (stub lock-in)** — action.yml:682. Immutable key permanently poisoned. `TRAP: a partial dl/ save LOCKS a stub into the immutable cache key forever (exact hits skip the repair save).`
8. **`#dl-completeness` (no size floor)** — action.yml:696. `Do NOT use a size floor for dl/ completeness — a 2GB floor passed run 29534917900 while missing the exact file legal-info needed.`
9. **`#dl-completeness` (oracle flag)** — action.yml:702. `MUST pass the same BR2_CCACHE=y as the build — omitting it undercounts dl/'s needs by 5 files (158 vs 163, misses ccache itself).`
10. **`#legal-info-2gib-cap`** — release.yml:486. First real tag push would have failed at upload. `host-sources/ MUST stay excluded — with it the archive hit 2109 MiB, over GitHub's 2 GiB per-asset cap.`
11. **`#no-container-disk-reclaim`** — action.yml:110. `MUST run first — reclaims ~30GB preinstalled toolchains so output/ (24GB) fits (ENOSPC killed run 29295920820). No `container:` here.`
12. **`#sdcard-timing-6h-cap`** — release.yml:278. `355 min: sdcard steps REUSE output/ (relink only, ~15 min each way) — do NOT reintroduce a from-scratch sdcard build; an earlier design that did overran GitHub's 360-min cap and the release never published.`
13. **`#configure-buildroot`** — action.yml:604. `Regenerate output/.config UNCONDITIONALLY every run — a stale cached one can silently override a defconfig change (run 29293209070 died here after a 52min stage 1).`
14. **`#renovate-hash-sync-rt-line-clobber`** — renovate:403. `Match the major series (linux-<major>.*), never the first sha256 line — that clobbered the RT entry (verified).`
15. **`#renovate-hash-sync-kernel-grep-bug`** — renovate:351. `ANCHOR THIS GREP + tail -1 — an unanchored match returns TWO lines (defconfig quotes the value in a comment) and broke the URL (bug #42).`

**Tier 2 — correctness/security rules that a "simplification" pass would remove**

16. `#ws-fp` — action.yml:139. `WS_FP keys the toolchain caches on the workspace path — cross-toolchains bake in absolute paths (NOT relocatable).`
17. `#cache-keys` (namespaces) — action.yml:316. `each variant gets its own br-<name>-host- namespace — NEVER share entries (absolute O= paths baked in).`
18. `#branch-name-injection` — renovate:189, 602 and action.yml:574. `EXTRA_APT goes through env, not ${{ }} interpolation — avoids the Actions script-injection footgun.` / `Resolved once as a shell var, not inline ${{ }} — closes a script-injection vector.`
19. `#renovate-hash-sync-branch-validation` — renovate:221. `REJECT ref-namespace forms (refs/heads/x, heads/x) rather than normalise — both resolve to x and would bypass the check below.`
20. `#ccache-key` — action.yml:544. `Do NOT set append-timestamp: false — the key is immutable, so the first save would own it forever and the hit rate would decay.`
21. `#toolchain-fingerprint` (pipefail) — action.yml:262. `grep exit 1 (zero matches) is CORRECT here under pipefail — `|| [ $? -eq 1 ]` tolerates it; a real grep failure (exit >=2) still aborts.`
22. `#renovate-hash-sync-kernel-grep-bug` (`|| true`) — renovate:360. `|| true is load-bearing here — without it, set -euo pipefail aborts silently on no-match.`
23. `#renovate-hash-sync-kernel-grep-bug` (awk) — renovate:435. `Match by exact string, not a regex rebuilt inside awk -v — awk -v eats backslash escapes (\. -> any char).`
24. `#dl-cache` — action.yml:435. `dl/ lives at repo root (survives make clean) — NEVER move it under output/.`
25. `#release-assets-array` — release.yml:1025, 1053. RT unconditional / sdcard conditional asymmetry + upsert.
26. `#artifact-naming-slash-trap` — release.yml:248 (+2). `sha-named, not ref_name — upload-artifact REJECTS '/' in names, and every branch here is slash-named.`
27. `#stock-payload-sourcing` (floating 7za URL) — release.yml:316. `URL is a floating branch ref BY DESIGN (matches the real Downloader's own unpinned source) — the MD5 check below is the actual security control.`
28. `#stock-payload-sourcing` (verify-then-extract) — release.yml:601. `MUST fully verify (MD5+size+7z CRC) BEFORE extracting a byte.`
29. `#variants` (validate once) / `#build-step` (Makefile hard-assert) / `#variant-dl-fallback` (safe despite coupling) / `#7z-slt-parsing` / `#sdcard-contract` / `#attest-provenance-scope` / `#publish-job-scope` (tag guard) / `#renovate-hash-sync-verification-status` (green ≠ correct) / `#rebuild-not-adopt` / `#renovate-hash-sync-dispatch-trap` / `#stock-payload-open-decision` — all keep a 1–3 line warning per their triage `replacement` field.

---

## 4. Disagreements and relocation risks — needs human review

**A. Triage-internal inconsistencies (must be resolved before implementation)**

1. **`loadBearing` is used inconsistently across agents.** release.yml's agent marked block 41–48 (`rebuild-not-adopt` continuation) `loadBearing: false` while its own rationale calls it "a real past incident … the first real tag push would have failed here"; renovate's agent marked block 82–96 `loadBearing: true` *and* category `move` — i.e. load-bearing knowledge with **no surviving inline warning**. Decide: does `move` + `loadBearing: true` ever co-occur? Recommendation: **no** — it should be `split`, or the flag is wrong. Affected: renovate 82–96 (mitigated only because the duplicate at 144–156 is `split`), release 594–596 (`keep` + `loadBearing: true`, harmless).
2. **`#stock-payload-sourcing` is absorbing 8 heterogeneous call sites** (G6 rationale, pin values, ARM-7za floating ref, host-vs-ARM 7za, verify order, extraction pattern, overlay semantics, LZMA2-vs-BCJ2). That is a section a new maintainer cannot hold in their head. Recommend splitting into `#stock-payload-sourcing` (where it comes from, why not vendored, the pins) and `#stock-payload-verification` (order, both 7za binaries, extraction, archive format).
3. **release.yml block 301–306 is `move`, but the pins it sits on are the operative security control.** The rationale says "let the env block carry the detail" — verify the env block actually self-documents, or the pointer strands the reader.

**B. Value depends on physical adjacency — relocate with care or not at all**

4. **action.yml 262–278 (`grep` exit 1 under pipefail)** — the warning is only comprehensible next to the `|| [ $? -eq 1 ]` it explains. Keep the inline text *at that exact line*, not at the top of the step.
5. **renovate 360–365 (`|| true`)** and **435–438 (`awk -v`)** — same class: single-token footguns. If the surrounding code is ever reformatted, these comments must move with the token, not the block.
6. **action.yml 286–289 (sentinel assert)** is `keep` but its text says "see above" — and "above" (197–232) is being gutted by a `split`. **This inline reference will dangle.** Must be repointed to `#toolchain-fingerprint`.
7. **Same dangling-pointer problem, flagged by the agent itself:** release.yml 673–680 ("see the long comment above the restore steps") and renovate 121–127 (points at line 418, which is itself being split). Sweep for *all* in-file "see above/below" references before applying any split.
8. **release.yml 523–527 (glob-must-match)** — the safety property is that `cp`'s own exit code catches a zero-match glob. That is only true if `nullglob` is *not* set in that step. Verify against release.yml 210–211, which deliberately sets `nullglob` in a *different* step. If a future edit sets it shell-wide, this guard silently dies. **Flag as an active latent risk, not just a docs question.**

**C. Verified-semantics caveats that must be written into `#shared-template-semantics`**

9. **`checkrun-naming` — PARTIAL (0 confirmed / 2 partial).** Do **not** state flatly that the refactor is safe for branch protection. It is safe *only because* the required check is the top-level `status` aggregator, not an inner matrix-leg job name. Document that dependency explicitly; if anyone later makes an inner job a required check, the refactor breaks it. Also unverified: whether this repo uses classic branch protection or Rulesets — **needs a human to check.**
10. **`reusable-artifacts` — PARTIAL.** Run-scoped artifact visibility is confirmed for same-repo/same-run only. Document the failure mode: "run just the kernel leg for debugging" via standalone `workflow_dispatch` produces artifacts the release job cannot see. v4's per-leg unique-name requirement is a hard 409, so it surfaces immediately — say so, so nobody over-engineers around it.
11. **`matrix-call` — CONFIRMED but with a real trap.** Matrix `outputs:` collapse to last-leg-wins. Since the whole point is "a later job consumes it," the docs must state: **pass kernel-leg results as named artifacts, never as matrix job outputs.**
12. **`local-actions` — CONFIRMED, tightly scoped.** `uses: ./…` resolves against the *caller's* checkout. Document the three breakages: cross-repo invocation, appending `@ref` to a local path, and any job missing its own `actions/checkout`.
13. **`needs-result` — PARTIAL.** The `continue-on-error` restriction and the `workflow_call`-outputs `.result` limitation are solid; the "malformed input → false success" report (#123803) is a single unverified community report. Document as "test for this," not as fact.
14. **`actionlint-shellcheck` — PARTIAL (0/3 confirmed).** No claim about lint coverage of the refactored layout should be asserted in docs. **Needs an actual local `actionlint` run against a prototype before anything is written down.**

**D. Blocked on missing input**

15. **The renovate-hash-sync triage JSON is truncated mid-block** (cuts off inside the step-3 lzma-sdk rationale at line ~454–468). Sections 36–45 above are reconstructed from the visible blocks only; there is **no `totals` object and no `proposedDocSections` list** for this file. Re-run that triage before implementing Part V.
16. **`build.yml` and `reproducibility.yml` were never triaged**, yet 6+ sections cite them as feeders and release.yml repeatedly says "same comments as build.yml's step." Either triage them in the same pass or accept that the merge in §1 (#4, #47) is one-sided and will leave build.yml's copies un-deduplicated.

---

## 5. Honest totals

| File | Comment lines before | After (inline) | Removed from code | Blocks: keep / move / split / drop |
|---|---|---|---|---|
| `.github/actions/buildroot-build/action.yml` | 494 | 114 | **−380 (−77%)** | 14 / 4 / 29 / 0 (47 blocks) |
| `.github/workflows/release.yml` | 463 | 170 | **−293 (−63%)** | 25 / 4 / 39 / 0 (68 blocks) |
| `.github/workflows/renovate-hash-sync.yml` | **unknown — JSON truncated** | unknown | unknown | ≥9 / ≥6 / ≥12 / 0 (27 blocks visible, list incomplete) |
| **Verified subtotal (2 files)** | **957** | **284** | **−673 (−70%)** | 39 / 8 / 68 / 0 |

**Renovate estimate (explicitly a guess, not from data):** the 27 visible blocks span roughly 300–350 comment lines with a keep/move/split mix similar to release.yml, suggesting ~110–130 lines retained and ~200 relocated. **Do not put this number in the PR description without re-running the triage.**

**What lands in docs/ci.md:**

- **50 sections**, from 92+ triaged comment blocks across 3 files — a ~45% reduction in topic count purely from the merges (`#no-container-disk-reclaim` absorbs 3 files; `#stock-payload-sourcing` absorbs 9 call sites; `#artifact-naming-slash-trap` 3; `#companion-hash-first-line-only` 3; `#old-two-image-design-retired` 3; `#branch-name-injection` 3; `#cache-coupling` 4; `#dl-completeness` 4).
- **Relocated prose from the 2 measured files: ~673 lines.** Expect docs/ci.md to land at **900–1,200 lines** — relocated prose expands under prose formatting (headings, tables, the incident index, and the ~15 lines of new connective tissue per section that turn a code comment into a readable paragraph). Add renovate's share and a realistic target is **1,100–1,500 lines**.
- **Net repo-wide:** roughly +1,300 doc lines against −870 comment lines. This is **not** a line-count win and should not be sold as one. The win is: 3 workflow files become skimmable, every trap keeps a one-line guard at the code, and 8 duplicated explanations become 8 single sources of truth that can no longer drift apart.