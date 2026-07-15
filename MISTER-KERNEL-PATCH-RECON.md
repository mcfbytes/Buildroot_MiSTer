# MiSTer Kernel Patch Reconciliation

A parallelizable task spec for a **full, independent reconciliation of every commit** in
`MiSTer-devel/Linux-Kernel_MiSTer` (the MiSTer kernel fork) against this repo
(`Buildroot_MiSTer`), which is moving from the forked kernel to a **vanilla 6.18.38** kernel
plus a small set of carried patches.

> **Why this exists.** The community is concerned that "important" kernel deltas will be silently
> left behind in the move to vanilla. That concern is justified: our existing
> `docs/patch-provenance.md` already contains at least one confirmed misclassification —
> commit `60e08955fe23c2a1d57834f7dc31860395542e4a` ("dualsense: give mute button and led to
> system") was grouped with genuinely-upstream DualSense LED/lightbar commits and marked
> **Class C "now upstream, drop"**, but it is **not** in vanilla (verified against the real
> `v6.18` tag): it maps the DualSense mic-mute button to `BTN_Z` and exposes the mute LED as a
> writable `led_classdev`. Neither exists upstream. It was **not carried**, so it is a live,
> previously-undocumented regression. This reconciliation exists to find every such case
> **systematically and with hard evidence.**

---

## 0. Objective & definition of done

Produce a machine-readable, human-auditable reconciliation record with **one row per fork
commit**, where every row states:

1. **What the commit does** (subject, subsystem, files).
2. **Its disposition** in the vanilla-based build — carried, dropped-because-upstream,
   dropped-deliberate, dropped-obsolete, not-yet-evaluated, or **misclassified**.
3. **Hard evidence** for that disposition:
   - if **carried** → which `00xx-*.patch` file, and whether it applies cleanly to 6.18 or was
     re-implemented;
   - if **dropped-because-upstream** → the **vanilla commit ID(s)** that supersede it **and** a
     `file:line` in the 6.18 tree **and a quoted matching hunk**, plus an equivalence grade;
   - if **dropped-deliberate/obsolete** → the concrete reason (code path removed, replaced by
     initramfs, etc.).
4. **Risk** if the functionality is absent, and whether the failure is **loud** (build/boot
   breaks) or **silent** (a feature just quietly disappears — the dangerous class).

**Done** = every fork commit has exactly one disposition backed by cited evidence; every carried
`00xx` patch maps back to ≥1 commit (no orphans); every disagreement with the current
`docs/patch-provenance.md` is surfaced; and the silent-regression triage list is complete.

**Non-negotiable principle:** treat `docs/patch-provenance.md` as a **hypothesis to be tested,
not a source of truth.** Independently re-derive each disposition and *diff* against the doc. The
doc's failure mode was confident, uncited claims; do not reproduce it.

---

## 1. Inputs & references

| Ref | What | Where |
|---|---|---|
| **Fork** | `MiSTer-devel/Linux-Kernel_MiSTer` — the commits to reconcile | Local full clone: `/mnt/source/Linux-Kernel_MiSTer`. Pinned HEAD (`MiSTer-v5.15`): `f0fb626acadd07f0718934826b143b6e4c9ce81c`. Vanilla base: **v5.15.1** (see §1.1) |
| **Vanilla** | Target kernel **6.18.38** | Local linux-stable clone: `/mnt/source/linux`. Pinned `v6.18.38` = `2aa1767b5e96f79560675d55bc0da08ea36fff29`; version also pinned at `configs/mister_de10nano_defconfig:77`. **Must be unshallowed first** (see §1.2) |
| **This repo** | Carried patches + prior-art doc | `board/mister/de10nano/linux-patches/*.patch` (25 files, `0001`–`0031`, with gaps — see §8); `docs/patch-provenance.md`; `docs/stock-inventory/stock-linux.config` |
| **Userspace** | `MiSTer-devel/Main_MiSTer` — for userspace-coupling cross-ref | https://github.com/MiSTer-devel/Main_MiSTer |

**Grounding requirement:** every worker MUST have read access to a **real vanilla 6.18 source
tree** (checked out at `v6.18.38`) *with full git history* to grep, `git log -S`, and quote.
Claims are verified against source, never from model memory.

### 1.1 Fork repo structure — it is NOT a git fork (verified)

`Linux-Kernel_MiSTer` shares **no ancestry** with Linus's or the stable tree — it was bootstrapped
by bulk-importing kernel source tarballs. Its entire `MiSTer-v5.15` history is **113 commits**:

- **4 squashed vanilla imports**: root `e12ed6c19` ("v5.13.12"), `137491a75` ("v5.14"),
  `b6f2ca1c4` ("v5.14.5"), `aba1ef4c1` ("v5.15.1");
- **1 merge commit** (`4e98a68d1`, PR #42 — its content commits are ordinary commits);
- **108 non-merge MiSTer delta commits** — the actual reconciliation work list.

The fork's true vanilla base is therefore **tag `v5.15.1`** (confirmed: HEAD `Makefile` says
`5.15.1`; stock never took later 5.15.x stable updates). `git merge-base` against any vanilla ref
returns nothing — do not use it (§3 replaces it).

Two older branches exist and were **rebuilt, not merged**, at each version bump:
`MiSTer-v5.14` (62 non-merge commits unreachable from `MiSTer-v5.15`) and `MiSTer-v5.13.12`
(52). Most are the same patches re-applied with new SHAs, but the residue includes genuine drops
(e.g. the wholesale `dwc2: port from socfpga-v4.19` replacement, `Enable Logitech D-Input
drivers`) — see the old-branch sweep in §3.

### 1.2 Local tree setup (one-time, before Phase 0)

The recon works off **two separate repos** — the fork and vanilla are never mixed into one
object store. (Git *could* hold both disjoint histories in one repo, but keeping them apart is
clearer: anything found under `/mnt/source/linux` is vanilla **by construction**, so provenance
of a quote is never ambiguous.)

```bash
# 1. Unshallow vanilla — the clone at /mnt/source/linux is depth-1, which breaks
#    `git log -S`, vanilla-SHA citation, and patch-id matching. Full history (~5 GB):
git -C /mnt/source/linux fetch --unshallow origin
git -C /mnt/source/linux fetch origin --tags

# 2. Add a second worktree of vanilla pinned at the fork's base, v5.15.1 — a plain
#    directory to diff the fork tree against, without touching the 6.18.38 checkout:
git -C /mnt/source/linux worktree add /mnt/source/linux-5.15.1 v5.15.1
```

Cross-tree comparisons need no shared git history:

- **tree-level diffs** are plain GNU diff between working trees:
  `diff -ruN -x .git /mnt/source/linux-5.15.1 /mnt/source/Linux-Kernel_MiSTer`;
- **patch-id matching** compares hashes as text — `git -C <repo> show <sha> | git patch-id
  --stable` runs per-repo and the resulting ids are directly comparable across repos.

Worker-facing paths: vanilla 6.18.38 source + full history = `/mnt/source/linux`; vanilla
5.15.1 base snapshot = `/mnt/source/linux-5.15.1`; fork = `/mnt/source/Linux-Kernel_MiSTer`.

---

## 2. Architecture — map-reduce with a mandatory audit

The unit of work is a **single commit**; per-commit analyses are independent, so Phase 1 fans out
across many cheap models. The serial parts are the deterministic enumeration up front and the
aggregation/audit at the end.

```
Phase 0  Enumerate (deterministic, no LLM, run once)  ──►  commits.jsonl  (master work list)
Phase 1  Map: one job per commit (Haiku ─► Sonnet)    ──►  records/<sha>.json  (fan-out)
Phase 2  Reduce (deterministic + 1 model)             ──►  reconciliation.{jsonl,md} + invariants
Phase 3  Audit (Opus / deep multi-agent)              ──►  verified reconciliation + findings
```

> **The hard part is grounding and verification, not the fan-out.** A cheap model will happily
> invent a plausible upstream SHA. Every design rule below exists to prevent that.

---

## 3. Phase 0 — Canonical enumeration (deterministic, run once)

Machine-generated and **complete** — this is the list the community concern is actually about, so
it must not be LLM-derived.

1. **Enumerate the work list.** There is no merge-base (§1.1) — the work list is simply every
   non-merge commit on `MiSTer-v5.15` **minus the 4 squashed vanilla imports**
   (`e12ed6c19`, `137491a75`, `b6f2ca1c4`, `aba1ef4c1`) = **108 commits**:
   ```
   git -C /mnt/source/Linux-Kernel_MiSTer log --no-merges --format='%H%x09%an%x09%ad%x09%s' MiSTer-v5.15
   ```
   For each, also capture files touched and `+/-` line counts (`--numstat`).
2. **Verify import purity.** A squashed import could smuggle non-vanilla changes invisibly.
   For each import commit, extract its tree (`git -C /mnt/source/Linux-Kernel_MiSTer archive
   <import-sha> | tar -x -C <scratch>`) and GNU-diff it against the corresponding vanilla tag's
   tree; any residue beyond the earlier delta commits re-applied on top is itself a **finding**
   and joins the work list as a synthetic entry.
3. **Tree-diff completeness backstop (the "nothing left behind" proof).** Commit enumeration
   alone cannot prove completeness against squashed imports. The full working-tree diff
   ```
   diff -ruN -x .git /mnt/source/linux-5.15.1 /mnt/source/Linux-Kernel_MiSTer
   ```
   **is** the total fork delta, independent of commit structure. Attribute every changed path
   (and, for shared files, every hunk) to ≥1 enumerated commit via
   `git -C /mnt/source/Linux-Kernel_MiSTer log aba1ef4c1..MiSTer-v5.15 -- <path>`; any
   unattributable hunk is automatically a finding. This converts the claim from "we looked at
   every commit" to **"we accounted for every byte of divergence from vanilla 5.15.1"** — the
   claim the community actually wants.
4. **Deterministic "already upstream" pre-filter.** Before any LLM runs, auto-classify backports
   of vanilla commits. Note `git cherry` against the whole vanilla range is impractical (~300k
   commits, disjoint histories); instead compute `git patch-id --stable` for each of the 108
   delta commits and compare against patch-ids of vanilla commits **touching the same paths** in
   `v5.15.1..v6.18.38` (patch-ids are plain hashes — comparable across the two repos as text),
   plus subject/author matching against the vanilla changelog:
   ```
   git -C /mnt/source/Linux-Kernel_MiSTer show <fork-sha> | git patch-id --stable
   git -C /mnt/source/linux log --format=%H v5.15.1..v6.18.38 -- <paths>   # candidate pool
   ```
   Commits that match are provisionally `dropped-upstream (backport)` **with a concrete vanilla
   SHA** and skip straight to a lighter verification. This removes a large chunk of hallucination
   surface.
5. **Old-branch sweep (appendix work list).** `MiSTer-v5.14` has 62 and `MiSTer-v5.13.12` has 52
   non-merge commits unreachable from `MiSTer-v5.15` (branches were rebuilt per version, not
   merged). Match them to v5.15-branch commits by patch-id, then subject; the **residue** —
   commits with no v5.15 equivalent (known examples: the wholesale `dwc2: port from
   socfpga-v4.19` replacement, later reduced to the single unaligned-IN fix we carry as `0028`;
   `Enable Logitech D-Input drivers`) — gets Phase 1 analysis as an appendix. This preempts the
   follow-up question "did anything get lost between MiSTer's own branches?"
6. **Mechanical change-type tag** per commit, from the file list:
   `in-tree-code` / `kconfig` (`.config`/Kconfig) / `dts` / `out-of-tree-module` (e.g.
   `drivers/hid/xone/**`, wifi vendor dirs) / `uapi-header` / `docs-or-build`.

**Output — `commits.jsonl`**, one object per commit:
`{ sha, subject, author, author_is_pr_contributor, date, files[], added, removed, change_type,
prefilter_disposition|null, prefilter_vanilla_sha|null }`
plus a metadata header record pinning `fork_head=f0fb626acadd…`, `vanilla=2aa1767b5e96…
(v6.18.38)`, `base=v5.15.1` for reproducibility, and `tree-diff-attribution.md` (step 3) and
the old-branch residue list (step 5).

---

## 4. Phase 1 — Per-commit analysis (fan-out)

**Work unit = exactly ONE commit. NEVER group commits.** Grouping is precisely what produced the
`60e08955f` misattribution — a genuinely-upstream feature set absorbed one MiSTer-specific
behavioral commit and the whole group was stamped "drop."

### 4.1 What each worker receives
- the full fork diff for its one commit (`git show <sha>`);
- the `commits.jsonl` row (change-type, prefilter hint);
- the carried-patch inventory (`board/mister/de10nano/linux-patches/`) so it can check "is this
  carried?";
- read access to the **vanilla 6.18 source tree** and the vanilla git log (to grep/quote/`log -S`);
- read access to Main_MiSTer source (for the userspace-coupling dimension);
- the output schema (§4.4) and the grounding contract (§4.3).

### 4.2 Two-tier model routing (cost control)
- **Haiku, first pass:** identity, files, subsystem, change-type, and *obvious* dispositions
  (carried → name the `00xx`; clean backport already confirmed in Phase 0).
- **Escalate to Sonnet** whenever the disposition is **`dropped-because-upstream`** (requires real
  source verification), when a contradiction is suspected, or when Haiku's confidence is `low`.
- **Never** let a `dropped-because-upstream` verdict ship from the cheap tier without source
  verification.

### 4.3 Grounding contract (anti-hallucination — mandatory)
- **No upstream SHA without a quote.** A `dropped-because-upstream` row MUST include a `file:line`
  in the 6.18 tree and a **quoted matching hunk**. If you cannot find and quote it, the
  disposition is `needs-verification`, not a guess.
- **Verify the claim actually matches.** Confirm the vanilla code does the *same thing* the fork
  commit does — do not match on filename or subject alone. (The `60e08955f` bug: the cited
  vanilla commits were real but did something *different*.) If vanilla does something different,
  grade it `contradicted` and treat as a **carry candidate**.
- **Distrust the prior doc.** If `docs/patch-provenance.md` already has an entry, record what it
  claims but re-derive independently and set `agrees_with_provenance_doc: true|false`.
- Prefer `git log -S'<symbol>'` / `-G` in the vanilla tree to locate where functionality landed.
- **Search by symbol/string, never by old path.** Between 5.15 and 6.18 files were moved and
  renamed (HID drivers, staging graduations, etc.). A miss at the fork-era path is **not**
  evidence of absence — grep the whole tree for the symbol before concluding anything.

### 4.4 Per-commit output schema (`records/<sha>.json`)
```json
{
  "sha": "60e08955fe23c2a1d57834f7dc31860395542e4a",
  "subject": "dualsense: give mute button and led to system.",
  "author": "Sorgelig", "author_is_pr_contributor": false,
  "date": "2021-07-10",
  "subsystem": "hid", "change_type": "in-tree-code",
  "files": ["drivers/hid/hid-playstation.c"], "added": 52, "removed": 27,
  "is_backport_of_vanilla": false,

  "disposition": "misclassified",
    // one of: carried | dropped-upstream | dropped-deliberate | dropped-obsolete
    //         | not-evaluated | needs-verification | misclassified
  "carried_patch": null,                 // e.g. "0026-input-mousedev-eviocgrab.patch" if carried
  "carried_mode": null,                  // "clean-apply" | "re-implemented" | null

  "upstream": {                          // required iff disposition implies upstream coverage
    "vanilla_shas": [],                  // MUST be empty if none genuinely matches
    "vanilla_file_line": "drivers/hid/hid-playstation.c:1486 (v6.18)",
    "vanilla_quote": "btn_mic_state = ...; mic_muted = !ds->mic_muted; /* toggle */  // internal, not BTN_Z",
    "equivalence": "contradicted"        // byte-identical | equivalent | superseded-better | partial | contradicted
  },

  "verification": { "method": "source-grep", "confidence": "high", "contradiction": true },
  "agrees_with_provenance_doc": false,
  "provenance_doc_ref": "patch-provenance.md:337 (grouped Class C 'drop')",

  "impact": {
    "effect_if_absent": "DualSense mic-mute button never reaches userspace as BTN_Z; mute LED not userspace-controllable",
    "affected_hardware": ["Sony DualSense 054c:0ce6"],
    "device_ids": ["054c:0ce6"],
    "severity": "feature-loss",          // boot-critical | feature-loss | cosmetic | none
    "failure_mode": "silent"             // loud | silent
  },
  "userspace_coupling": {                // the "importance" signal
    "coupled": true,
    "interface": "input event code BTN_Z",
    "main_mister_ref": "<path:line in Main_MiSTer if found, else null>"
  },
  "forward_port": { "applies_to_6_18": true, "conflicts": "none (deleted block still present verbatim)", "effort": "low" },
  "dependencies": { "depends_on": [], "superseded_by": [], "duplicate_of": [] },
  "license_provenance": null,            // for vendored / third-party-PR code
  "notes": "Carry candidate. Grouped-conflation error in provenance doc."
}
```

### 4.5 Per-commit worker prompt (template)
```
You are reconciling ONE commit from the MiSTer Linux kernel fork against vanilla 6.18.38.
Analyze ONLY the commit below. Do not group it with any other commit.

COMMIT DIFF:
<git show output>

You have read access to:
- the vanilla 6.18.38 source tree + full git history at /mnt/source/linux (grep/view/`git log -S`)
- the vanilla 5.15.1 base snapshot at /mnt/source/linux-5.15.1
- the fork repo at /mnt/source/Linux-Kernel_MiSTer
- carried patches at board/mister/de10nano/linux-patches/
- Main_MiSTer source at <path>
- docs/patch-provenance.md (PRIOR ART — record but independently re-derive; may be wrong)

Produce ONE JSON object matching the schema in §4.4. RULES:
1. If you claim the functionality is in vanilla, you MUST cite a 6.18 file:line AND quote the
   matching hunk, AND confirm it does the SAME thing (not just same file/subject). Otherwise set
   disposition="needs-verification". Never invent a vanilla SHA.
2. If vanilla does something DIFFERENT from the commit, set equivalence="contradicted" and treat
   as a carry candidate (disposition often "misclassified" if the doc says otherwise).
3. Set failure_mode="silent" if dropping it fails quietly (no build/boot error, feature just
   missing) — flag these prominently.
4. Set userspace_coupling.coupled=true if Main_MiSTer or any userspace depends on this behavior
   (input codes, ioctls, sysfs, /dev nodes). Cite the Main_MiSTer reference if found.
5. Output ONLY the JSON object.
```

---

## 5. Phase 2 — Reduce (deterministic + one model)

Merge `records/*.json` into `reconciliation.jsonl` and a sorted `reconciliation.md` table, then
**enforce invariants** (fail the run if violated):

- **Completeness:** every commit in `commits.jsonl` has exactly one record with a non-null
  disposition. No gaps.
- **No orphan patches:** every carried `00xx-*.patch` maps back to ≥1 commit. Any patch with no
  originating commit is itself a finding.
- **Single disposition:** no commit carries two conflicting dispositions.
- **Evidence present:** every `dropped-upstream` row has `vanilla_shas` **or**
  `vanilla_file_line`+`vanilla_quote`; otherwise it is downgraded to `needs-verification`.
- **Tree-diff attribution closed:** every path/hunk in the Phase 0 §3.3 total-delta diff is
  attributed to ≥1 record; unattributed hunks fail the run (something escaped enumeration).
- **Old-branch residue covered:** every Phase 0 §3.5 residue commit has an appendix record.
- **Doc diff:** emit `disagreements-with-provenance.md` — every row where
  `agrees_with_provenance_doc=false`. Each is a candidate `60e08955f`-class error.

---

## 6. Phase 3 — Audit (deep pass)

A higher-tier reviewer (Opus / deep multi-agent, e.g. `ultracode`) re-verifies, at minimum:
- **every** `dropped-upstream` row (the dangerous class — re-quote the vanilla hunk and confirm
  equivalence);
- every `severity ∈ {boot-critical, feature-loss}` **and** `failure_mode = silent` row;
- every `confidence = low` and every `contradiction = true` row;
- a random 10% sample of the rest for calibration.

Audit output amends the record in place and appends an `audit_findings.md`.

---

## 7. Dimensions reference

### 7.1 Core schema (per §4.4)

| Group | Fields |
|---|---|
| **Identity** | sha · subject · author (+ real author vs Sorgelig-account / PR contributor) · date · files · ±lines · series/parent |
| **Classification** | subsystem · change_type (in-tree-code / kconfig / dts / out-of-tree-module / uapi-header / docs-build) · backport-of-vanilla vs fork-original |
| **Disposition** | carried (→ which `00xx`, clean-apply vs re-implemented) / dropped-upstream / dropped-deliberate / dropped-obsolete / not-evaluated / needs-verification / **misclassified** |
| **Upstream evidence** | vanilla_shas · vanilla_file_line (6.18) · **vanilla_quote** · equivalence: byte-identical / equivalent / superseded-better / partial / **contradicted** |
| **Verification** | method (source-grep / diff / cherry-patch-id / needs-hardware) · confidence · contradiction flag · agrees_with_provenance_doc |
| **Impact / risk** | effect_if_absent · affected_hardware & device_ids · severity (boot-critical→cosmetic) · **failure_mode (loud/silent)** |
| **Forward-port** | applies_to_6_18 · conflicts · effort |
| **Dependencies** | depends_on / superseded_by / duplicate_of |

### 7.2 Extra dimensions — these identify which patches are *important*

- **Silent-vs-loud failure** (`impact.failure_mode`). Loud failures announce themselves at
  build/boot; silent ones (a feature quietly vanishing — `60e08955f` is the archetype) are the
  entire community risk. This is the primary triage key.
- **Userspace / Main_MiSTer coupling** (`userspace_coupling`). The single best proxy for
  "important." A kernel delta that exists to serve userspace (input event codes, ioctls like
  `EVIOCGRAB`, sysfs, `/dev` nodes — e.g. `BTN_Z`, `QUIRK_DS4TOUCH`) is exactly what users rely
  on. A hit here means "must not drop silently." Cross-reference Main_MiSTer.
- **UAPI/ABI surface touched.** Flag separately — these break userspace, not just features.
- **Device-ID inventory** (byproduct). Many commits just add a `VID:PID`. Emit a flat
  `device-support.md` (fork vs vanilla-6.18 vs our-build) — trivially verifiable and directly
  reassuring to the community.
- **Config reconciliation is its own axis.** For `kconfig` changes the question is not "is it
  upstream" but "does this `CONFIG_*` still exist / was it renamed / is it set in our defconfig" —
  verify against 6.18 Kconfig + `configs/mister_de10nano_defconfig`, not the source tree.
- **Provenance & license.** For vendored / third-party-PR code (xone, wifi vendor drivers,
  Fanatec, etc.), capture author + license — gates whether we can carry *or* upstream it.

---

## 8. Deliverables

1. `commits.jsonl` — canonical fork-commit manifest (Phase 0).
2. `records/<sha>.json` — one per commit (Phase 1).
3. `reconciliation.jsonl` + `reconciliation.md` — merged, sorted table (Phase 2).
4. `disagreements-with-provenance.md` — every divergence from `docs/patch-provenance.md`.
5. `silent-regressions.md` — every `failure_mode=silent` with `severity ≥ feature-loss`,
   sorted by impact. **The headline deliverable for the community.**
6. `device-support.md` — controller/dongle support matrix (fork vs vanilla vs our-build).
7. `tree-diff-attribution.md` — the Phase 0 §3.3 total-delta diff with every hunk attributed to
   a commit record; the mechanical proof that enumeration was complete.
8. `old-branch-sweep.md` — appendix: `MiSTer-v5.14` / `MiSTer-v5.13.12` residue commits (things
   dropped between MiSTer's own branches) with dispositions.
9. `audit_findings.md` — Phase 3 results.

The final report must also explain the **carried-patch numbering gaps** (`0005`–`0009`, `0021`
are absent from `board/mister/de10nano/linux-patches/`) — otherwise the community will ask what
was in them.

---

## 9. Pilot first (de-risk before the full parallel spend)

Before the full fan-out, run Phase 1 on a **~15–20 commit sample** deliberately spanning the hard
cases: at least one known-misclassified (`60e08955f` — confirmed reachable on `MiSTer-v5.15`),
one clean backport, one deliberate-drop, one out-of-tree module, one kconfig-only, one DTS, and
one userspace-coupled input commit. (At 108 total commits the pilot is ~18% of the run — cheap
insurance for schema validation before spending the rest.)
Validate that:
- the schema captures everything without free-text overflow;
- the grounding contract actually blocks hallucinated SHAs (spot-check every cited vanilla hunk);
- `60e08955f` comes back `misclassified` with `equivalence=contradicted` and
  `agrees_with_provenance_doc=false` (this is the canary — if the pilot passes it, the pipeline
  works).

Only after the pilot passes should the full 108-commit run (plus the old-branch residue
appendix) proceed.
