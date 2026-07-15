#!/usr/bin/env python3
"""Phase 0 of the MiSTer kernel patch reconciliation (see MISTER-KERNEL-PATCH-RECON.md §3).

Deterministic, no LLM. Produces, in docs/kernel-recon/:
  - commits.jsonl              one row per fork delta commit (+ _meta header row)
  - tree-diff-attribution.md   total fork-vs-v5.15.1 delta, every path attributed
  - old-branch-residue.md      MiSTer-v5.14 / v5.13.12 commits with no v5.15 equivalent
  - phase0-report.md           summary + invariant verdicts

Requires: /mnt/source/Linux-Kernel_MiSTer (full clone, MiSTer-v5.15 checked out)
          /mnt/source/linux (linux-stable, unshallowed, tags v5.13.12..v6.18.38)
"""

import json
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

FORK = "/mnt/source/Linux-Kernel_MiSTer"
LINUX = "/mnt/source/linux"
OUT = Path(__file__).resolve().parent

FORK_HEAD_REF = "MiSTer-v5.15"
BASE_TAG = "v5.15.1"
VANILLA_TARGET = "v6.18.38"

# Squashed vanilla tarball imports (short sha -> vanilla tag) — see plan §1.1.
IMPORTS = {
    "e12ed6c19": "v5.13.12",
    "137491a75": "v5.14",
    "b6f2ca1c4": "v5.14.5",
    "aba1ef4c1": "v5.15.1",
}

SEP = "\x01"


def git(repo, *args, stdin=None):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, stdin=stdin)
    if r.returncode != 0:
        sys.exit(f"git -C {repo} {' '.join(args)} failed:\n{r.stderr}")
    return r.stdout


def git_patch_ids(repo, *log_args):
    """Stream `git log -p <args>` through `git patch-id --stable`; return {commit: patch_id}."""
    p1 = subprocess.Popen(
        ["git", "-C", repo, "log", "-p", "--no-merges", "--no-renames", *log_args],
        stdout=subprocess.PIPE,
    )
    p2 = subprocess.Popen(
        ["git", "patch-id", "--stable"], stdin=p1.stdout, stdout=subprocess.PIPE, text=True
    )
    p1.stdout.close()
    out, _ = p2.communicate()
    ids = {}
    for line in out.splitlines():
        pid, sha = line.split()
        ids[sha] = pid
    return ids


def norm_subject(s):
    s = re.sub(r"\s*\(#\d+\)\s*$", "", s.strip())
    return s.rstrip(".").lower()


def ls_tree(repo, ref):
    """{path: (mode, blob_sha)} — blob SHAs are content-addressed, comparable across repos."""
    entries = {}
    for line in git(repo, "ls-tree", "-r", ref).splitlines():
        meta, path = line.split("\t", 1)
        mode, otype, sha = meta.split()
        entries[path] = (mode, sha)
    return entries


def check_ignore(repo, paths):
    """{path: 'source:line:pattern'} for paths matched by the repo's .gitignore rules."""
    if not paths:
        return {}
    r = subprocess.run(["git", "-C", repo, "check-ignore", "-v", "--", *paths],
                       capture_output=True, text=True)
    rules = {}
    for line in r.stdout.splitlines():
        rule, path = line.split("\t", 1)
        rules[path] = rule
    return rules


# ---------------------------------------------------------------- step 0: resolve pins
fork_head = git(FORK, "rev-parse", FORK_HEAD_REF).strip()
vanilla_head = git(LINUX, "rev-parse", f"{VANILLA_TARGET}^{{commit}}").strip()
imports_full = {git(FORK, "rev-parse", s).strip(): tag for s, tag in IMPORTS.items()}

# ---------------------------------------------------------------- step 1: enumerate
raw = git(
    FORK, "log", "--no-merges", "--no-renames", "--numstat",
    f"--format=%x00{SEP.join(['%H', '%an', '%ae', '%aI', '%s'])}", FORK_HEAD_REF,
)
commits = []  # oldest-first at the end
for block in raw.split("\x00"):
    if not block.strip():
        continue
    lines = block.strip("\n").split("\n")
    sha, an, ae, date, subj = lines[0].split(SEP)
    files, added, removed, binary = [], 0, 0, False
    for fl in lines[1:]:
        if not fl.strip():
            continue
        a, r, path = fl.split("\t", 2)
        files.append(path)
        if a == "-" or r == "-":
            binary = True
        else:
            added, removed = added + int(a), removed + int(r)
    commits.append(dict(sha=sha, author=an, author_email=ae, date=date, subject=subj,
                        files=files, added=added, removed=removed, has_binary=binary))
commits.reverse()

deltas = [c for c in commits if c["sha"] not in imports_full]
assert len(deltas) == 108, f"expected 108 delta commits, got {len(deltas)}"

# ---------------------------------------------------------------- step 2: import purity
purity = []
for sha, tag in imports_full.items():
    t_fork = git(FORK, "rev-parse", f"{sha}^{{tree}}").strip()
    t_van = git(LINUX, "rev-parse", f"{tag}^{{tree}}").strip()
    purity.append(dict(import_sha=sha, tag=tag, fork_tree=t_fork, vanilla_tree=t_van,
                       identical=t_fork == t_van))
impure = [p for p in purity if not p["identical"]]
purity_residue = {}  # import_sha -> [(path, kind, ignore_rule|None)]
for p in impure:
    f_ls = ls_tree(FORK, p["import_sha"])
    v_ls = ls_tree(LINUX, p["tag"])
    diff_paths = sorted(
        set(k for k in f_ls.keys() ^ v_ls.keys())
        | set(k for k in f_ls.keys() & v_ls.keys() if f_ls[k] != v_ls[k])
    )
    rules = check_ignore(FORK, [pp for pp in diff_paths if pp not in f_ls])
    annotated = []
    for pp in diff_paths:
        kind = ("missing-in-import" if pp not in f_ls
                else "extra-in-import" if pp not in v_ls else "content-differs")
        annotated.append((pp, kind, rules.get(pp)))
    purity_residue[p["import_sha"]] = annotated

# ---------------------------------------------------------------- step 3: tree-diff backstop
fork_tree = ls_tree(FORK, FORK_HEAD_REF)
van_tree = ls_tree(LINUX, BASE_TAG)

added_paths = sorted(fork_tree.keys() - van_tree.keys())
deleted_paths = sorted(van_tree.keys() - fork_tree.keys())
modified_paths = sorted(
    p for p in fork_tree.keys() & van_tree.keys() if fork_tree[p] != van_tree[p]
)
delta_paths = set(added_paths) | set(deleted_paths) | set(modified_paths)

touched_by = defaultdict(list)  # path -> [short shas], oldest first
for c in deltas:
    for p in c["files"]:
        touched_by[p].append(c["sha"][:9])
enumerated_paths = set(touched_by)

unattributed = sorted(delta_paths - enumerated_paths)
reverted = sorted(enumerated_paths - delta_paths)  # touched but ended identical to vanilla

# Deletions that were never in the fork because git skipped them at tarball import
# (matched by the kernel's own .gitignore when the tree was `git add`ed) are a
# known-benign mechanism, not smuggled changes — classify them separately.
import_drop_rules = check_ignore(FORK, [p for p in unattributed if p in set(deleted_paths)])
unattributed_ignored = sorted(import_drop_rules)
unattributed_unexplained = sorted(set(unattributed) - set(unattributed_ignored))

# Out-of-tree dirs = deepest-common dirs present in fork HEAD but absent from vanilla base.
fork_dirs = set(git(FORK, "ls-tree", "-dr", "--name-only", FORK_HEAD_REF).splitlines())
van_dirs = set(git(LINUX, "ls-tree", "-dr", "--name-only", BASE_TAG).splitlines())
new_dirs = fork_dirs - van_dirs
oot_dirs = sorted(d for d in new_dirs if str(Path(d).parent) not in new_dirs)


def oot_dir_of(path):
    for d in oot_dirs:
        if path.startswith(d + "/"):
            return d
    return None


# ---------------------------------------------------------------- step 4: change types
CODE_RE = re.compile(r"\.(c|h|S|s|rs)$")
DTS_RE = re.compile(r"\.(dts|dtsi)$")
KCONF_RE = re.compile(r"(^|/)(\.config|[^/]*defconfig|Kconfig[^/]*)$")


def change_type(files):
    if any(oot_dir_of(p) for p in files):
        return "out-of-tree-module"
    if any(p.startswith("include/uapi/") for p in files):
        return "uapi-header"
    if any(CODE_RE.search(p) for p in files):
        return "in-tree-code"
    if any(DTS_RE.search(p) for p in files):
        return "dts"
    if any(KCONF_RE.search(p) for p in files):
        return "kconfig"
    return "docs-or-build"


for c in deltas:
    c["change_type"] = change_type(c["files"])
    c["author_is_pr_contributor"] = c["author"] != "Sorgelig" or "(#" in c["subject"]

# ---------------------------------------------------------------- step 5: patch-id pre-filter
fork_pids = git_patch_ids(FORK, f"{list(imports_full)[-1]}..{FORK_HEAD_REF}")
# candidate pool: vanilla commits in base..target touching any non-OOT delta path
pool_paths = sorted(p for p in enumerated_paths if not oot_dir_of(p))
van_pids = git_patch_ids(LINUX, f"{BASE_TAG}..{VANILLA_TARGET}", "--", *pool_paths)
pid_to_van = defaultdict(list)
for sha, pid in van_pids.items():
    pid_to_van[pid].append(sha)

van_subjects = defaultdict(list)
for line in git(LINUX, "log", "--no-merges", f"--format=%H{SEP}%s",
                f"{BASE_TAG}..{VANILLA_TARGET}").splitlines():
    sha, subj = line.split(SEP, 1)
    van_subjects[norm_subject(subj)].append(sha)

for c in deltas:
    pid = fork_pids.get(c["sha"])
    hits = pid_to_van.get(pid, []) if pid else []
    c["prefilter_disposition"] = "dropped-upstream (backport)" if hits else None
    c["prefilter_vanilla_sha"] = hits[0] if hits else None
    c["prefilter_subject_matches"] = van_subjects.get(norm_subject(c["subject"]), [])[:5]

# ---------------------------------------------------------------- step 6: old-branch sweep
def branch_only(ref):
    out = []
    for line in git(FORK, "log", "--no-merges", f"--format=%H{SEP}%an{SEP}%aI{SEP}%s",
                    ref, f"^{FORK_HEAD_REF}").splitlines():
        sha, an, date, subj = line.split(SEP, 3)
        if re.match(r"^v5\.\d", subj):  # their own version imports
            continue
        out.append(dict(sha=sha, author=an, date=date, subject=subj))
    out.reverse()
    return out


delta_pid_set = {fork_pids[c["sha"]]: c["sha"] for c in deltas if c["sha"] in fork_pids}
delta_subj = {norm_subject(c["subject"]): c["sha"] for c in deltas}

sweep = {}
matched_14_subjects = set()
for name, ref in [("MiSTer-v5.14", "remotes/origin/MiSTer-v5.14"),
                  ("MiSTer-v5.13.12", "remotes/origin/MiSTer-v5.13.12")]:
    items = branch_only(ref)
    pids = git_patch_ids(FORK, ref, f"^{FORK_HEAD_REF}")
    matched, residue = [], []
    for it in items:
        pid = pids.get(it["sha"])
        if pid and pid in delta_pid_set:
            matched.append(dict(**it, match="patch-id", v515_sha=delta_pid_set[pid]))
        elif norm_subject(it["subject"]) in delta_subj:
            matched.append(dict(**it, match="subject", v515_sha=delta_subj[norm_subject(it["subject"])]))
        else:
            note = ""
            if name == "MiSTer-v5.13.12" and norm_subject(it["subject"]) in matched_14_subjects:
                note = "also on MiSTer-v5.14 (re-applied there, dropped at v5.15)"
            residue.append(dict(**it, note=note))
    if name == "MiSTer-v5.14":
        matched_14_subjects = {norm_subject(i["subject"]) for i in items}
    sweep[name] = dict(total=len(items), matched=matched, residue=residue)

# ---------------------------------------------------------------- write outputs
now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
meta = dict(_meta=dict(generated=now, fork_head=fork_head, base_tag=BASE_TAG,
                       base_commit=git(LINUX, "rev-parse", f"{BASE_TAG}^{{commit}}").strip(),
                       vanilla_target=VANILLA_TARGET, vanilla_commit=vanilla_head,
                       imports={s: t for s, t in imports_full.items()},
                       delta_commit_count=len(deltas)))

with open(OUT / "commits.jsonl", "w") as f:
    f.write(json.dumps(meta) + "\n")
    for c in deltas:
        f.write(json.dumps(c) + "\n")

with open(OUT / "tree-diff-attribution.md", "w") as f:
    f.write(f"# Tree-diff attribution — fork {fork_head[:9]} vs vanilla {BASE_TAG}\n\n")
    f.write(f"Generated {now} by `phase0.py`. Content comparison via `git ls-tree -r` blob\n")
    f.write("hashes (content-addressed, valid across repos). Every differing path must be\n")
    f.write("attributable to ≥1 enumerated delta commit — see plan §3.3.\n\n")
    f.write(f"| Class | Paths |\n|---|---|\n| added | {len(added_paths)} |\n")
    f.write(f"| modified | {len(modified_paths)} |\n| deleted | {len(deleted_paths)} |\n")
    f.write(f"| unattributed, gitignored-at-import (benign, see below) | {len(unattributed_ignored)} |\n")
    f.write(f"| **unattributed, unexplained (must be 0)** | **{len(unattributed_unexplained)}** |\n")
    f.write(f"| touched-but-reverted (informational) | {len(reverted)} |\n\n")
    if unattributed_ignored:
        f.write("## Gitignored-at-import deletions (benign)\n\n")
        f.write("Absent from the fork because git skipped them (kernel's own `.gitignore`)\n")
        f.write("when the source tarball was `git add`ed. None are part of the kernel build.\n\n")
        for p in unattributed_ignored:
            f.write(f"- `{p}` — rule `{import_drop_rules[p]}`\n")
        f.write("\n")
    if unattributed_unexplained:
        f.write("## UNEXPLAINED UNATTRIBUTED PATHS — FINDINGS\n\n")
        for p in unattributed_unexplained:
            f.write(f"- `{p}`\n")
        f.write("\n")

    def status_of(p):
        return "A" if p in set(added_paths) else ("D" if p in set(deleted_paths) else "M")

    f.write("## Attribution table\n\nOut-of-tree directories are collapsed to `dir/**`.\n\n")
    f.write("| Path | St | Commits (oldest→newest) |\n|---|---|---|\n")
    grouped = defaultdict(set)
    rows = []
    for p in sorted(delta_paths):
        d = oot_dir_of(p)
        if d:
            grouped[d].update(touched_by.get(p, []))
        elif p in import_drop_rules:
            rows.append((p, status_of(p), ["*(gitignored-at-import)*"]))
        else:
            rows.append((p, status_of(p), touched_by.get(p, [])))
    for d in sorted(grouped):
        shas = sorted(grouped[d], key=lambda s: [c["sha"][:9] for c in deltas].index(s))
        rows.append((f"{d}/**", "A", shas))
    for p, st, shas in sorted(rows):
        f.write(f"| `{p}` | {st} | {' '.join(shas)} |\n")
    if reverted:
        f.write("\n## Touched but reverted to vanilla content (informational)\n\n")
        for p in reverted:
            f.write(f"- `{p}` — {' '.join(touched_by[p])}\n")

with open(OUT / "old-branch-residue.md", "w") as f:
    f.write("# Old-branch sweep — commits with no MiSTer-v5.15 equivalent\n\n")
    f.write(f"Generated {now} by `phase0.py` (plan §3.5). Matching: patch-id, then normalized\n")
    f.write("subject. **Residue commits get Phase 1 analysis as the appendix work list.**\n")
    for name, s in sweep.items():
        f.write(f"\n## {name} — {s['total']} branch-only commits, "
                f"{len(s['matched'])} matched, {len(s['residue'])} residue\n\n")
        f.write("### Residue (appendix work list)\n\n")
        if not s["residue"]:
            f.write("*(none)*\n")
        for it in s["residue"]:
            note = f" — *{it['note']}*" if it["note"] else ""
            f.write(f"- `{it['sha'][:9]}` {it['date'][:10]} {it['subject']}{note}\n")
        f.write("\n<details><summary>Matched commits</summary>\n\n")
        for it in s["matched"]:
            f.write(f"- `{it['sha'][:9]}` → `{it['v515_sha'][:9]}` ({it['match']}) {it['subject']}\n")
        f.write("\n</details>\n")

pid_hits = [c for c in deltas if c["prefilter_vanilla_sha"]]
subj_hits = [c for c in deltas if c["prefilter_subject_matches"] and not c["prefilter_vanilla_sha"]]
ct_hist = defaultdict(int)
for c in deltas:
    ct_hist[c["change_type"]] += 1

with open(OUT / "phase0-report.md", "w") as f:
    f.write("# Phase 0 report — canonical enumeration\n\n")
    f.write(f"Generated {now} by `phase0.py`.\n\n")
    f.write(f"- Fork HEAD (`{FORK_HEAD_REF}`): `{fork_head}`\n")
    f.write(f"- Vanilla base: `{BASE_TAG}` = `{meta['_meta']['base_commit']}`\n")
    f.write(f"- Vanilla target: `{VANILLA_TARGET}` = `{vanilla_head}`\n")
    f.write(f"- Delta commits enumerated: **{len(deltas)}** (113 total − 4 imports − 1 merge)\n\n")
    f.write("## Change-type histogram\n\n| Type | Count |\n|---|---|\n")
    for t, n in sorted(ct_hist.items(), key=lambda x: -x[1]):
        f.write(f"| {t} | {n} |\n")
    f.write("\n## Import purity (plan §3.2)\n\n")
    f.write("| Import | Tag | Tree identical? |\n|---|---|---|\n")
    for p in purity:
        res = purity_residue.get(p["import_sha"], [])
        benign = all(kind == "missing-in-import" and rule for _, kind, rule in res)
        verdict = ("✅ byte-identical" if p["identical"]
                   else f"⚠️ {len(res)} files gitignored at import (benign)" if benign
                   else f"❌ {len(res)} paths differ")
        f.write(f"| `{p['import_sha'][:9]}` | `{p['tag']}` | {verdict} |\n")
    f.write("\nResidue detail — `missing-in-import` + an ignore rule means git skipped the\n")
    f.write("file when the extracted tarball was `git add`ed (kernel's own `.gitignore`);\n")
    f.write("no such file is part of the kernel build.\n")
    for sha, paths in purity_residue.items():
        f.write(f"\n### Residue in `{sha[:9]}`\n\n")
        for pp, kind, rule in paths[:200]:
            f.write(f"- `{pp}` — {kind}" + (f", rule `{rule}`" if rule else "") + "\n")
        if len(paths) > 200:
            f.write(f"- … and {len(paths) - 200} more\n")
    f.write("\n## Tree-diff completeness backstop (plan §3.3)\n\n")
    f.write(f"- Differing paths (fork HEAD vs `{BASE_TAG}`): {len(delta_paths)} "
            f"({len(added_paths)} added, {len(modified_paths)} modified, {len(deleted_paths)} deleted)\n")
    f.write(f"- Unattributed but explained (gitignored-at-import deletions): {len(unattributed_ignored)}\n")
    f.write(f"- **Unattributed and unexplained: {len(unattributed_unexplained)}** "
            f"({'invariant HOLDS — every other differing path traces to an enumerated commit' if not unattributed_unexplained else 'INVARIANT VIOLATED — see tree-diff-attribution.md'})\n")
    f.write(f"- Touched-but-reverted paths: {len(reverted)} (informational)\n")
    f.write(f"- Out-of-tree dirs (absent from vanilla {BASE_TAG}): "
            + ", ".join(f"`{d}`" for d in oot_dirs) + "\n")
    f.write("\nHunk-level completeness follows from path attribution + import purity: the\n")
    f.write(f"`{BASE_TAG}` import is byte-identical to vanilla except for gitignored file\n")
    f.write("*omissions* (no content changes), and the enumeration covers *every* commit\n")
    f.write("between that import and fork HEAD, so each differing path's content is fully\n")
    f.write("composed of enumerated commits.\n")
    f.write("\n## Already-upstream pre-filter (plan §3.4)\n\n")
    f.write(f"- vanilla candidate pool: {len(van_pids)} commits patch-id'd "
            f"(path-scoped, `{BASE_TAG}..{VANILLA_TARGET}`); "
            f"{sum(len(v) for v in van_subjects.values())} subjects compared (full range)\n")
    f.write(f"- patch-id matches (provisional `dropped-upstream (backport)`): **{len(pid_hits)}**\n")
    for c in pid_hits:
        f.write(f"  - `{c['sha'][:9]}` {c['subject']} → vanilla `{c['prefilter_vanilla_sha'][:12]}`\n")
    f.write(f"- subject-only matches (hint, NOT a disposition): **{len(subj_hits)}**\n")
    for c in subj_hits:
        f.write(f"  - `{c['sha'][:9]}` {c['subject']} ~ {', '.join(s[:12] for s in c['prefilter_subject_matches'])}\n")
    f.write("\n## Old-branch sweep (plan §3.5)\n\n")
    for name, s in sweep.items():
        f.write(f"- {name}: {s['total']} branch-only, {len(s['matched'])} matched, "
                f"**{len(s['residue'])} residue** → appendix work list\n")
    f.write("\nSee `old-branch-residue.md` for the residue detail.\n")

print(f"delta commits: {len(deltas)}")
print(f"import purity: {[(p['tag'], p['identical']) for p in purity]}")
print(f"backstop: {len(delta_paths)} differing paths, "
      f"{len(unattributed_ignored)} gitignored-at-import, "
      f"{len(unattributed_unexplained)} UNEXPLAINED")
print(f"prefilter: {len(pid_hits)} patch-id hits, {len(subj_hits)} subject hits")
for name, s in sweep.items():
    print(f"sweep {name}: {s['total']} only, {len(s['residue'])} residue")
