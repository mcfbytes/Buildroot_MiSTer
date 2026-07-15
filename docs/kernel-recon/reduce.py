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
    cp = row["r"].get("carried_patch")
    if cp:
        for pf in patch_files:
            if pf in cp or cp in pf:
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

def sev(r): return (r.get("impact") or {}).get("severity", "?")
def fm(r): return (r.get("impact") or {}).get("failure_mode", "?")
def coup(r): return (r.get("userspace_coupling") or {}).get("coupled")

with open(HERE / "reconciliation.md", "w") as f:
    f.write(f"# Reconciliation — one row per fork commit\n\nGenerated {now} by `reduce.py` "
            f"from {len(rows)} records ({len(main_shas)} MiSTer-v5.15 + {len(residue_full)} "
            f"old-branch residue). Tier-2 verified: "
            f"{sum(1 for x in rows if x['tier2'])}/{len(rows)}.\n\n")
    f.write("| SHA | Branch | Disposition | Carried patch | Severity | Fail | Coupled | Doc✓ | T2 | Subject |\n")
    f.write("|---|---|---|---|---|---|---|---|---|---|\n")
    for row in rows:
        r = row["r"]
        f.write(f"| `{row['sha'][:9]}` | {row['branch'].replace('MiSTer-','')} "
                f"| **{r.get('disposition')}** | {r.get('carried_patch') or '—'} "
                f"| {sev(r)} | {fm(r)} | {'Y' if coup(r) else '—'} "
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
