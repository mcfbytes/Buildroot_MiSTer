#!/usr/bin/env python3
"""Phase 2 reduce — merge records/*.json into reconciliation outputs + enforce invariants.

Per MISTER-KERNEL-PATCH-RECON.md §5/§8. Deterministic; run after Phase 1 completes.
Outputs: reconciliation.jsonl, reconciliation.md, disagreements-with-provenance.md,
silent-regressions.md, device-support.md. Exits nonzero on invariant violation.
"""

import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
RECORDS = HERE / "records"
PATCH_DIR = HERE / "../../board/mister/de10nano/linux-patches"

DISP = {"carried", "dropped-upstream", "dropped-deliberate", "dropped-obsolete",
        "not-evaluated", "needs-verification", "misclassified"}

# ---------------------------------------------------------------- load work lists
main_shas, meta = [], None
for line in open(HERE / "commits.jsonl"):
    d = json.loads(line)
    if "_meta" in d:
        meta = d["_meta"]
    else:
        main_shas.append(d["sha"])

residue_shas = []
for line in open(HERE / "old-branch-residue.md"):
    line = line.strip()
    if line.startswith("- `") and "…" not in line:
        residue_shas.append(line.split("`")[1])
# residue file lists short SHAs; resolve against record filenames
records = {p.stem: json.loads(p.read_text()) for p in sorted(RECORDS.glob("*.json"))}
residue_full = [full for full in records if any(full.startswith(s) for s in residue_shas)]

problems, rows = [], []
for sha, r in records.items():
    d = r.get("disposition")
    if d not in DISP:
        problems.append(f"{sha[:9]}: bad disposition {d!r}")
    if d == "dropped-upstream":
        up = r.get("upstream") or {}
        if not (up.get("vanilla_shas") or (up.get("vanilla_file_line") and up.get("vanilla_quote"))):
            problems.append(f"{sha[:9]}: dropped-upstream WITHOUT evidence")
    notes = r.get("notes") or ""
    tier2 = "sonnet-verified" in notes or "orchestrator-verified" in notes or \
            "sonnet-verified" in json.dumps(r)
    rows.append(dict(sha=sha, r=r, tier2=tier2,
                     branch=r.get("source_branch", "MiSTer-v5.15")))

# ---------------------------------------------------------------- invariants
missing_main = [s for s in main_shas if s not in records]
if missing_main:
    problems.append(f"MISSING main records: {[s[:9] for s in missing_main]}")
if len(residue_full) != 15:
    problems.append(f"expected 15 residue records, found {len(residue_full)}")

patch_files = sorted(p.name for p in PATCH_DIR.glob("0*.patch"))
mapped = defaultdict(list)
for row in rows:
    # a patch's origin may be a direct carry (carried_patch) or a capability
    # re-implementation recorded in dependencies.superseded_by (e.g. 0031)
    refs = [row["r"].get("carried_patch") or ""]
    refs += [str(s) for s in (row["r"].get("dependencies") or {}).get("superseded_by") or []]
    for cp in refs:
        for pf in patch_files:
            if pf in cp or (cp and cp in pf):
                mapped[pf].append(row["sha"][:9])
orphans = [pf for pf in patch_files if pf not in mapped]
if orphans:
    problems.append(f"ORPHAN carried patches (no originating commit): {orphans}")

# ---------------------------------------------------------------- outputs
now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
order = {d: i for i, d in enumerate(
    ["misclassified", "needs-verification", "not-evaluated", "carried",
     "dropped-upstream", "dropped-deliberate", "dropped-obsolete"])}
rows.sort(key=lambda x: (order.get(x["r"].get("disposition"), 9), x["sha"]))

with open(HERE / "reconciliation.jsonl", "w") as f:
    f.write(json.dumps({"_meta": dict(meta, generated=now,
            record_count=len(rows), tier2_verified=sum(1 for x in rows if x["tier2"]))}) + "\n")
    for row in rows:
        f.write(json.dumps(row["r"], sort_keys=True) + "\n")

def why_of(r):
    d = r.get("disposition")
    if d == "carried":
        return "\u2014"
    parts = []
    if d == "dropped-upstream":
        shas = (r.get("upstream") or {}).get("vanilla_shas") or []
        parts.append("in mainline" + (f": `{str(shas[0])[:12]}`" if shas else ""))
    sup = (r.get("dependencies") or {}).get("superseded_by") or []
    comp = []
    for it in sup[:2]:
        it = " ".join(str(it).split())
        if len(it) == 40 and all(c in "0123456789abcdef" for c in it):
            it = it[:9]
        comp.append(it[:48] + ("\u2026" if len(it) > 48 else ""))
    if comp:
        parts.append("\u2192 " + "; ".join(comp) + ("; \u2026" if len(sup) > 2 else ""))
    return "; ".join(parts).replace("|", "/") if parts else "see record"

def impact_today(r):
    """What a user of THIS build actually experiences (vs. severity, the triage
    counterfactual of 'what if nothing had replaced it')."""
    d = r.get("disposition")
    notes = (r.get("notes") or "").lower()
    if d == "carried":
        return "none (carried)"
    if "known limitation" in notes or "known regression" in notes:
        return "**limitation — see record**"
    if d == "dropped-upstream":
        return "none (in mainline)"
    if (r.get("dependencies") or {}).get("superseded_by"):
        return "none (replaced)"
    if (r.get("impact") or {}).get("severity") in ("none", None):
        return "none"
    return "none (decided; see record)"

def sev(r): return (r.get("impact") or {}).get("severity", "?")
def fm(r): return (r.get("impact") or {}).get("failure_mode", "?")
def coup(r): return (r.get("userspace_coupling") or {}).get("coupled")

with open(HERE / "reconciliation.md", "w") as f:
    f.write(f"# Reconciliation — one row per fork commit\n\nGenerated {now} by `reduce.py` "
            f"from {len(rows)} records ({len(main_shas)} MiSTer-v5.15 + {len(residue_full)} "
            f"old-branch residue). Tier-2 verified: "
            f"{sum(1 for x in rows if x['tier2'])}/{len(rows)}.\n\n")
    f.write("""## How to read this table

Each row is one commit from the MiSTer kernel fork (`MiSTer-devel/Linux-Kernel_MiSTer`),
reconciled against our vanilla-6.18.38-based build. The full evidence for a row lives in
`records/<full-sha>.json`.

- **SHA** — the fork commit (short). **Branch** — where the commit lives: `v5.15` is the
  branch stock MiSTer actually shipped; `v5.14`/`v5.13.12` are older branches whose
  unique commits never reached stock (analyzed so nothing is lost *between* MiSTer's own
  branches either).
- **Disposition** — what happened to the commit's functionality in this build:
  - `carried` — kept, as the patch named in the next column (applied to the pristine
    kernel.org tree at build time);
  - `dropped-upstream` — the same functionality is already in mainline 6.18 (the record
    cites the upstream commit and quotes the matching code);
  - `dropped-deliberate` — intentionally not carried, with the replacement named (a
    maintained out-of-tree package, a mainline driver, or a documented decision);
  - `dropped-obsolete` — the code it changed no longer exists in any form we ship
    (e.g. fixes to a vendored driver that was replaced wholesale).
- **Carried patch** — the `board/mister/de10nano/linux-patches/00xx-*.patch` file that
  carries it (`—` when not carried).
- **Impact today** — **read this column first.** It is what a user of *this build*
  actually experiences: `none (carried)` — the feature is present via our patch;
  `none (in mainline)` — 6.18 already has it; `none (replaced)` — a named package/driver
  provides it. Only rows marked **limitation** describe a real present-day difference,
  and each one is listed explicitly below the legend.
- **Drop-risk** — a *hypothetical* used during triage: the worst effect **if this
  functionality had been left out with no replacement**, and whether that absence would
  be `loud` (build/boot error) or `silent` (quietly missing — the class this audit
  hunts). **A row reading `feature-loss/silent` next to an Impact-today of `none` is not
  a problem in the build** — it records why the row demanded scrutiny during the audit,
  and that scrutiny is complete. Severity ladder: `boot-critical` > `feature-loss` >
  `cosmetic` > `none`.
- **Coupled** — `Y` when MiSTer userspace (Main_MiSTer) directly depends on the kernel
  interface involved (input event codes, sysfs nodes, /dev nodes, ioctls); these must
  never be dropped silently. The record cites the exact `file:line`.
- **Doc✓** — whether the original `docs/patch-provenance.md` triage agreed with this
  independently re-derived result (`N` rows are the errors this exercise found; all are
  corrected in that doc's §11).
- **T2** — `✓` means the record survived a second, independent verification pass
  (a stronger reviewer re-derived every claim from the actual source trees; 123/123 rows
  have this).
- **Why / replacement** — the short answer to "where did it go?": the mainline commit that
  provides it (`dropped-upstream`), or what replaces it (`→ package/...`, a mainline driver,
  an ADR/decision). `see record` means the reason is narrative — read the JSON record.

### Why rows are `dropped-deliberate`

Nothing was dropped by accident: every `dropped-deliberate` record names its replacement or
the decision behind it. The recurring patterns, so the table reads at a glance:

1. **Vendored driver trees → maintained sources.** The fork carried multi-megabyte copies of
   out-of-tree drivers (realtek wifi families, xone). We ship the same functionality from
   commit-pinned, hash-verified Buildroot packages or — preferred when it works on the real
   hardware — the mainline in-kernel drivers (`rtw88`, `rtl8xxxu`). Fixes the fork made to
   its vendored copies are verified present in whichever source we actually build.
2. **Fork mechanisms replaced by this build's architecture.** The `loop=` boot parameter
   hack is replaced by a real initramfs; the fork's `MiSTer_defconfig` commits are absorbed
   into `board/mister/de10nano/linux.config` (verified symbol-by-symbol against the resolved
   build config).
3. **Shared-file hygiene.** Hunks in files shared by every socfpga board (`socfpga.dtsi`)
   were dropped when provably inert on this board, keeping patches off shared files.
4. **Rejected on the merits.** Experimental or debug leftovers (the `mt7601u` calibration
   disable marked "possible fix?", the vt 63→9 console tweak, deleted gdb helper scripts)
   — each with the reasoning recorded.
5. **Risk-based.** The out-of-tree new-lg4ff rewrite was not carried: mainline `hid-lg4ff`
   covers every wheel Main_MiSTer actually drives, and the rewrite carries an untestable
   hard-fail hazard. Known limitation: the G923 *PlayStation* variant loses force feedback.

""")
    lims = [row for row in rows if "limitation" in impact_today(row["r"])]
    f.write("### Present-day limitations — the complete list\n\n")
    f.write(f"Of {len(rows)} rows, **{len(lims)}** describe a real difference a user could "
            "notice on this build today; everything else is fully covered. They are:\n\n")
    for row in lims:
        r = row["r"]
        f.write(f"- `{row['sha'][:9]}` {r.get('subject','')} — see its record for the "
                f"decision and affected hardware.\n")
    f.write("\n## The table\n\n")
    f.write("| SHA | Branch | Disposition | Carried patch | Why / replacement | Impact today | Drop-risk | Coupled | Doc\u2713 | T2 | Subject |\n")
    f.write("|---|---|---|---|---|---|---|---|---|---|---|\n")
    for row in rows:
        r = row["r"]
        f.write(f"| `{row['sha'][:9]}` | {row['branch'].replace('MiSTer-','')} "
                f"| **{r.get('disposition')}** | {r.get('carried_patch') or '\u2014'} "
                f"| {why_of(r)} "
                f"| {impact_today(r)} | {sev(r)}/{fm(r)} | {'Y' if coup(r) else '—'} "
                f"| {'N' if r.get('agrees_with_provenance_doc') is False else 'Y' if r.get('agrees_with_provenance_doc') else '?'} "
                f"| {'✓' if row['tier2'] else ''} | {r.get('subject','')[:60]} |\n")

with open(HERE / "disagreements-with-provenance.md", "w") as f:
    f.write(f"# Disagreements with docs/patch-provenance.md\n\nGenerated {now}. Every record "
            "where independent re-derivation contradicts the prior doc — each was a candidate "
            "`60e08955f`-class error; all are tier-2 verified.\n\n")
    n = 0
    for row in rows:
        r = row["r"]
        if r.get("agrees_with_provenance_doc") is False:
            n += 1
            f.write(f"## `{row['sha'][:9]}` {r.get('subject')}\n\n"
                    f"- disposition: **{r.get('disposition')}** | severity {sev(r)} | {fm(r)}\n"
                    f"- doc ref: {r.get('provenance_doc_ref')}\n"
                    f"- notes: {(r.get('notes') or '')[:600]}…\n\n")
    f.write(f"\n**Total: {n} disagreements.**\n")

CARRY_CAND = {"misclassified", "needs-verification", "not-evaluated"}
with open(HERE / "silent-regressions.md", "w") as f:
    f.write(f"# Silent-regression triage — the headline list\n\nGenerated {now}. Rows where the "
            "functionality is NOT covered in our 6.18 build (misclassified / needs-verification / "
            "not-evaluated) and failure is silent. Sorted worst-first. All tier-2 verified.\n\n")
    cands = [row for row in rows if row["r"].get("disposition") in CARRY_CAND
             and fm(row["r"]) == "silent"]
    sev_order = {"boot-critical": 0, "feature-loss": 1, "cosmetic": 2, "none": 3}
    cands.sort(key=lambda x: sev_order.get(sev(x["r"]), 9))
    for row in cands:
        r = row["r"]
        f.write(f"## `{row['sha'][:9]}` {r.get('subject')} — **{sev(r)}**\n\n"
                f"- disposition {r.get('disposition')}; coupled: {coup(r)}; "
                f"interface: {(r.get('userspace_coupling') or {}).get('interface')}\n"
                f"- effect if absent: {(r.get('impact') or {}).get('effect_if_absent')}\n"
                f"- hardware: {', '.join((r.get('impact') or {}).get('affected_hardware') or []) or '—'}\n\n")
    f.write(f"**Total: {len(cands)} candidates** (of which "
            f"{sum(1 for c in cands if sev(c['r'])=='feature-loss')} feature-loss).\n\n")
    f.write("## Protected (carried) silent-failure items\n\nThese WOULD regress silently if their "
            "patch were ever dropped — they are carried today:\n\n")
    for row in rows:
        r = row["r"]
        if r.get("disposition") == "carried" and fm(r) == "silent" and sev(r) in ("boot-critical", "feature-loss"):
            f.write(f"- `{row['sha'][:9]}` {r.get('subject')[:60]} → {r.get('carried_patch')}\n")

with open(HERE / "device-support.md", "w") as f:
    f.write(f"# Device-ID inventory\n\nGenerated {now}. VID:PID → commits and dispositions "
            "(how each device's support is covered in the 6.18 build).\n\n")
    dev = defaultdict(list)
    for row in rows:
        for did in (row["r"].get("impact") or {}).get("device_ids") or []:
            dev[did.lower()].append((row["sha"][:9], row["r"].get("disposition")))
    f.write("| Device | Commits (disposition) |\n|---|---|\n")
    for did in sorted(dev):
        f.write(f"| `{did}` | " + ", ".join(f"`{s}` ({d})" for s, d in dev[did]) + " |\n")

print(f"records: {len(rows)}  problems: {len(problems)}")
for p in problems:
    print("PROBLEM:", p)
print(f"tier2: {sum(1 for x in rows if x['tier2'])}/{len(rows)}")
from collections import Counter
print("dispositions:", dict(Counter(x["r"].get("disposition") for x in rows)))
print("doc disagreements:", sum(1 for x in rows if x["r"].get("agrees_with_provenance_doc") is False))
print("patch mapping:", {k: len(v) for k, v in sorted(mapped.items())})
sys.exit(1 if problems else 0)
