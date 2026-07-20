# CI / Release pipeline — refactor plan

Analysis only; no workflow files changed. Nothing here removes a feature, check,
assertion or trigger. Written to be executed by an `ultracode` session — each
item carries a recommended model and effort.

**Decisions taken:** item **A1** (composite action, not a reusable workflow);
item **H** promoted — terse YAML comments, long-form rationale relocated to a new
`docs/ci.md` with anchor pointers.

**Supporting data**, produced by a 33-agent verification pass and persisted for
the implementing session:

| File | Contents |
|---|---|
| `.ci-refactor/comment-triage.json` | All **232 comment blocks** across 8 files, each classified keep/split/move/drop with the exact replacement text and target anchor |
| `.ci-refactor/actions-semantics-verdicts.json` | 8 GitHub Actions semantics claims, each verified by 3 independent lenses (docs / adversarial-refute / real-world) |
| `.ci-refactor/docs-ci-structure.md` | Proposed 50-section `docs/ci.md` ToC, house-style rules, ranked load-bearing list |

---

## Where things stand

| File | Total | Comment | Code | Embedded shell |
|---|---|---|---|---|
| `release.yml` | 1105 | 463 (41%) | 577 | 417 |
| `build.yml` | 653 | 266 (40%) | 343 | 229 |
| `renovate-hash-sync.yml` | 607 | 267 (43%) | 299 | 301 |
| `publish-db.yml` | 340 | 123 (36%) | 195 | 115 |
| `reproducibility.yml` | 221 | 124 (56%) | 78 | 32 |
| `fork-sync.yml` | 146 | 55 (37%) | 76 | 54 |
| `renovate-validate.yml` | 103 | 39 (37%) | 52 | 24 |
| `actions/buildroot-build` | 850 | 494 (58%) | 315 | 273 |
| **Total** | **4025** | **1831** | **1935** | **1445** |

Two headline problems. **1,445 lines of shell live inside YAML**, unreachable by
shellcheck and unrunnable locally — in a repo that already has 21 extracted
scripts. And `build.yml`/`release.yml` carry a verified-identical overlap that
**has already drifted**: the two kernel-leg summary tables differ beyond the one
field that legitimately should, and the `::error::` string for the identical
kernel-tree guard is now worded differently in each file.

`buildroot-build` is the right pattern. Most of what follows is finishing it.

---

## Item A — extract the shared kernel leg *(decided: composite action)*

Measured with comments stripped: the two `build-kernel` jobs are **85 and 91 code
lines, 72 identical**. Real differences, all parameterisable:

| Difference | `build.yml` | `release.yml` |
|---|---|---|
| Gate wiring | `needs: gate` + `if:` | none |
| legal-info payload | excludes `sources/` | includes `sources/` (GPL) |
| legal-info guards | none | existence + 2 GiB cap |
| Summary table | Trigger / Commit / Packages | Tag |

**New action:** `.github/actions/kernel-leg/`, inputs `kernel`,
`full-legal-info`, `summary-context`.

**Verified viable.** The decision hinged on whether a composite action may contain
`uses:` steps calling `upload-artifact`. Verdict **CONFIRMED** (2 confirm /
1 partial) — and more persuasively, `buildroot-build` already proves it in-repo:
it calls `actions/cache/restore`, `cache/save` and `ccache-action` today. The
lone caveat was that GitHub's docs use `checkout` as the worked example rather
than naming those three; the in-repo precedent settles it.

**One design constraint carried over from the verification pass:** matrix job
`outputs:` collapse to last-leg-wins. The current design already avoids this by
passing kernel results as named artifacts — keep it that way. Do not "simplify"
`kver` transport into a job output.

*Model: **opus**, effort **high**. Semantics to negotiate (the legal-info
asymmetry is a real behavioural difference, not cosmetic), and it touches the
artifact contract feeding the release job.*

## Item B — three byte-identical post-build blocks

Verified identical with comments stripped:

- `Download kernel-variant artifacts` + `Populate the extra-modules overlay` (~25 lines)
- `Assert every kernel-variant module tree merged into the image` (~14 lines)
- `Run parity test suite` + `Upload parity-suite results` + `ABI / SONAME checker` (~28 lines)

Two composite actions: `merge-kernel-modules` (download + overlay + assert) and
`verify-image` (ci-tests + results upload + check-abi). Bonus:
`CI_TESTS_SKIP_QEMU_SYSTEM: "1"` is currently set in two places with a comment in
each saying they must match — becomes one input with one default.

*Model: **sonnet**, effort **medium**. Verified-identical source, no semantics to
negotiate. The safest structural win — good first move.*

## Item C — `release.yml` reports disk usage twice

`release.yml:918` duplicates a step `buildroot-build/action.yml:836` already runs
with `if: always()`. Pre-composite-action leftover. Delete the workflow copy.

*Model: **haiku**, effort **low**.*

## Item D — single source of truth for the kernel matrix *(promoted)*

`kernel: [rt]` at `build.yml:202` and `release.yml:149` must agree. Both files'
headers claim "adding a variant = one matrix entry" — it is two.

This was going to be free under A2. With A1 chosen it stays a real invariant, so
it becomes required rather than optional. Derive the list from
`configs/mister_*.fragment` in the `gate` job and consume via `fromJSON`, which
makes the existing claim true: adding a fragment genuinely becomes the only step.

*Model: **sonnet**, effort **medium**. `fromJSON` matrix wiring plus a gate output;
needs care that a doc-only run still yields a well-formed empty matrix.*

## Item E — move embedded shell into `scripts/`

The biggest quality lever, and it matches how this repo already works —
`ci-tests.sh`, `check-abi.sh`, `check-sdcard.sh` are all extracted and
shellcheck-able. The workflows are the exception.

Ranked:

1. **`release.yml`'s stock-archive chain** (~120 lines, 6 steps): fetch, verify
   MD5/SHA/size, `7z t`, extract, re-verify `uboot.img`/`updateboot`, ARM-7za
   round trip, member-list check. Most contract-critical code in the repo, and
   currently untestable without pushing a tag. As
   `scripts/verify-stock-payload.sh` it runs on a laptop.
   *Model: **opus**, effort **high** — protects the on-device Downloader.*
2. **`renovate-hash-sync.yml`'s four refresh steps** (~250 lines). Its own header
   admits three of four have never run against a real PR, and documents a bug
   where a broken URL went green three times because the failure path is only a
   `::warning::`. Extracted, each becomes testable against a fixture.
   *Model: **sonnet**, effort **high**; one script per case, then an adversarial
   verify pass at **opus**/high on the warn-vs-fail semantics.*
3. **`publish-db.yml`'s asset resolution** (~60 lines of `jq`/`sed`).
   *Model: **sonnet**, effort **medium**.*

Leave `gate`'s diff logic and `status`'s truth table inline — genuinely workflow
logic, and they read fine.

## Item F — lint the workflows *(claim softened)*

Nothing lints 3,175 lines of workflow YAML or 1,445 lines of shell today.

**Correction to the previous draft:** I claimed actionlint runs shellcheck over
`run:` blocks, so adding it would cover the embedded shell. That verified
**PARTIAL on all three lenses** — the integration is real but conditional
(shellcheck must be present, coverage of `run:` blocks is not the same as
shellcheck's own analysis, and configuration affects what is actually checked).

So: add actionlint for the YAML, and rely on plain `shellcheck scripts/*.sh` for
shell coverage as E lands. **Prototype actionlint locally before writing any
claim about its coverage into `docs/ci.md`.**

*Model: **sonnet**, effort **medium** — mostly wiring, but verify actual coverage
empirically rather than trusting the claim.*

## Item G — repeated helpers

`sz()` defined 4× (`build.yml` 247, 449; `release.yml` 186, 890); the 2 GiB guard
twice in `release.yml`; the legal-info tarball pattern 3×. Fold into whatever
`scripts/ci-lib.sh` emerges from E.

*Model: **haiku**, effort **low** (after E lands).*

---

## Item H — terse YAML, `docs/ci.md` for the rest *(decided)*

Every one of the **232 comment blocks** was triaged. Full data in
`.ci-refactor/comment-triage.json`.

| File | Blocks | keep | split | move | drop | Before | After |
|---|---|---|---|---|---|---|---|
| `buildroot-build/action.yml` | 47 | 14 | 29 | 4 | 0 | 494 | 114 |
| `release.yml` | 68 | 25 | 39 | 4 | 0 | 463 | 170 |
| `build.yml` | 37 | 12 | 19 | 6 | 0 | 266 | 116 |
| `renovate-hash-sync.yml` | 31 | 8 | 15 | 8 | 0 | 267 | 41 |
| `reproducibility.yml` | 15 | 8 | 6 | 1 | 0 | 124 | 55 |
| `publish-db.yml` | 16 | 1 | 12 | 3 | 0 | 123 | 47 |
| `fork-sync.yml` | 13 | 8 | 4 | 1 | 0 | 55 | 25 |
| `renovate-validate.yml` | 5 | 2 | 3 | 0 | 0 | 39 | 14 |
| **Total** | **232** | **78** | **127** | **27** | **0** | **1831** | **582** |

**1,249 comment lines (68%) relocate; zero are deleted.** No agent proposed a
single `drop` across 232 blocks — the "relocate, never delete" constraint held.
The dominant category is `split` (127), which is the right shape: a sharp
one-line warning survives at the code, the story moves.

### House style (apply in order, first match wins)

- **R1 — Terse-and-local stays.** ≤5 content lines making a single point about the
  code immediately below: leave verbatim, no pointer.
- **R2 — The imperative stays; its proof moves.** Any block with `MUST`/`NEVER`/
  "load-bearing"/"TRAP", or warning against a tempting simplification, is split:
  imperative + the run ID that makes it credible compressed to 1–3 lines inline,
  ending `See docs/ci.md#<anchor>.`
- **R3 — Pure description moves whole.** If the step's own `if:`/`key:`/name
  already states the fact, delete the prose rather than pointer it.
- **R4 — Say it once.** Reasoning appearing in ≥2 places gets exactly one docs
  section; every site carries the same anchor. Never "see the comment above".
- **R5 — Numbers live in docs.** Measured GB/minute figures and inventories move;
  an incident's run ID stays inline as the credential for R2.

### Load-bearing knowledge — Tier 0 (silent failures)

Exact inline text in the triage JSON. Ranked by blast radius × silence:

1. **`#gh-repo-bug`** — a green ~9h build silently produces *no release*.
2. **`#mister-version-coupling`** — breaks update-offer logic for every subscribed device.
3. **`#toolchain-fingerprint`** (deny-list) — the cortex-a9 silent-miscompile.
4. **`#release-draft-gate`** — removing `draft:` turns CI into an unreviewed fleet-wide push.
5. **`#toolchain-save-policy`** — a poisoned toolchain persisting across runs.

*Models: **sonnet**/high for per-file mechanical application of the triage JSON
(the classification decisions are already made); **opus**/high to author
`docs/ci.md` itself — it is the knowledge-preservation artifact and the one place
where losing nuance is unrecoverable. Final adversarial read at **opus**/xhigh:
"what knowledge was lost between the old comment and the new
comment+section pair?"*

---

## Risks found during verification

Three are new since the last draft and are genuine pre-work:

1. **14 dangling in-file references.** `buildroot-build` alone has four ("see
   above", "see the comment above the caches", "see the long comment above the
   restore steps"), plus `release.yml`'s "same comments as build.yml's step of
   the same name". Every one breaks under a relocation pass. **Sweep and convert
   to anchors before applying any split.** Verified by grep, list reproducible via
   the command in this repo's history.
2. **Latent `nullglob` dependency.** `release.yml:528` (`Stage kernel-variant
   assets`) relies on `cp` failing on a zero-match glob — which only works because
   that step does *not* set `nullglob`. Two other steps in the same file do set it
   (212, 367). Each `run:` block is its own shell, so **the guard holds today**;
   it would die silently if someone added `nullglob` there. Worth an explicit
   inline comment, and it argues for E (in a real script this is testable).
3. **Spec conflict in the triage data.** 2 of 232 blocks are tagged both
   `loadBearing: true` and `category: move` — i.e. load-bearing knowledge with no
   surviving inline warning. Those two should be `split`. Resolve before applying.

Plus, from the semantics verification, one thing to check by hand: **the
refactor is safe for branch protection only because the required check is the
top-level `status` aggregator**, not an inner job name. If anyone later makes an
inner job required, that breaks. Worth confirming whether this repo uses classic
branch protection or Rulesets — I could not determine that from the tree.

**Item I — action pins: no change.** 10× `checkout`, 8× `upload-artifact` at
identical SHAs looks like duplication but `renovate-hash-sync.yml:251` explains
it is deliberate — identical pins mean Renovate tracks one dependency and updates
every copy in one PR. Noted so it does not get "fixed" later.

---

## Additional items surfaced by the verification pass

### J — Audit the warn-and-skip paths *(functional, not cosmetic — recommend doing this first)*

**All 9 `::warning::`-and-continue paths in the entire pipeline are in
`renovate-hash-sync.yml`.** That file's own header says it plainly: *"Read every
warn-and-skip path below as 'this can go green without doing anything'"* — and
documents a real occurrence, where a malformed URL let the job report SUCCESS
three times while silently leaving `linux.hash` stale.

This is a correctness issue that a code-quality pass would otherwise walk past.
Minimum viable fix: a job-summary line — `refreshed N, skipped K, failed 0` — so
a silent no-op is visible without opening the log. Stronger fix: decide per path
whether "couldn't fetch" should actually be a failure. Three of the four cases
have never run against a real PR, so the blast radius is unmeasured.

*Model: **opus**, effort **high**. This is a judgement call about failure
semantics per path, not a mechanical edit. Pairs naturally with E-2 (extracting
those steps to scripts makes each one testable).*

### K — Incident index

Seven distinct run IDs / bug refs are scattered across the comments
(`29669946883`, `29534917900`, `29529993731`, `29300460591`, `29293209070`, `#41`,
`#42`), **five of them duplicated across two files**. A single table in
`docs/ci.md` — run ID → what happened → which section — makes the institutional
memory searchable instead of grep-able. Cheap, and it is the payoff that makes H
worth doing rather than just tidier.

*Model: **sonnet**, effort **medium**. Falls out of H at near-zero marginal cost.*

### L — Separate "verification status" from "design rationale"

**Five of eight files carry a "never been run end-to-end / UNPROVEN / HONESTLY
UNMEASURED" header.** These are *status*, not rationale, and they go stale on a
completely different clock — the day the first green kernel-leg run happens,
several become wrong, and nothing will prompt anyone to update them.

Pull them into one "CI verification status" table (in `docs/ci.md`, or arguably
`TASKS.md`), leaving the code with none. One place to update after a real run.
Two concrete follow-ups already queued behind it: `build-kernel`'s 240-minute
timeout is explicitly a guess in *both* files, and `reproducibility.yml` has never
executed at all.

*Model: **sonnet**, effort **medium**.*

### M — Pilot H on a small file before the big ones

`renovate-validate.yml` (5 blocks) or `publish-db.yml` (16 blocks, and a striking
**1-of-16 keep ratio** — almost entirely long-form) are self-contained, low blast
radius, and exercise the full R1–R5 rule set. Prove the house style and the anchor
scheme there, get it reviewed, then apply to the 47- and 68-block files with the
conventions already settled.

*Model: **sonnet**, effort **medium**; review the pilot at **opus** before scaling.*

### N — Split `#stock-payload-sourcing`

The proposed section absorbs 8–9 heterogeneous call sites (G6 no-binaries rule,
hash pins, the deliberately-floating ARM 7za URL, host-vs-ARM 7za, verification
ordering, extraction pattern, LZMA2-vs-BCJ2). That is more than one section can
carry. Split into `#stock-payload-sourcing` (where it comes from, why it is not
vendored, the pins) and `#stock-payload-verification` (ordering, both 7za
binaries, extraction, archive format).

### O — Leave `fork-sync.yml` and `renovate-validate.yml` largely alone

Keep ratios of 8/13 and 2/5, small and single-purpose. They are already close to
the target style. Resist churning them for consistency's sake — noted so a
sweeping pass does not touch them gratuitously.

### P — `.github/actions/README.md` once there are four

After A and B there will be four composite actions (`buildroot-build`,
`kernel-leg`, `merge-kernel-modules`, `verify-image`). A short "which one to use
when, and what each owns" note prevents a fifth being added redundantly — the
exact failure mode that produced the original three-way copy-paste.

*Model: **haiku**, effort **low**.*

## Sequencing

**Pre-work** (blocking, cheap): resolve the 2 `loadBearing`+`move` conflicts;
sweep the 14 dangling references. *haiku/low, opus/medium for the sweep.*

**Then:** `J → C + G → F → B → A → D → E → M → H (+ K, L, N, P)`.

J moves to the front because it is the only *functional* defect in the set — the
rest is code quality. M (pilot H on a small file) gates the big H application.
K, L, N and P are all sub-items of H and cost almost nothing once it is underway.

**On `.ci-refactor/`:** it is worktree-local scratch today. Either keep it
uncommitted, or commit it on the refactor branch and delete it when H lands —
but do not let it become a permanent second source of truth alongside
`docs/ci.md`.

H lands last deliberately — the comment triage is keyed to current line numbers,
and A/B/D move large blocks of code. Either re-run the triage after the
structural work, or accept a line-number reconciliation pass. **Re-running is
cheaper and I'd recommend it**; the triage script is `.ci-refactor/`-adjacent and
the classification logic is stable, so a re-run mostly reproduces the same
decisions against new line numbers.

## Honest accounting

Items A–G remove roughly **150–200 duplicated code lines** and collapse four
"these two copies must agree" invariants to zero. E moves ~430 lines from
unlintable YAML into testable scripts. H moves 1,249 comment lines into a
`docs/ci.md` that will land at **1,100–1,500 lines** once prose connective tissue
is added.

**Net repo-wide this is not a line-count win**, and should not be sold as one:
roughly +1,300 doc lines against −1,249 comment lines and −200 duplicated code
lines. The win is that the workflow files become skimmable, every trap keeps a
one-line guard at the code, and eight duplicated explanations become eight single
sources of truth that can no longer drift apart.

No feature, guard, assertion or trigger is removed by any item.
