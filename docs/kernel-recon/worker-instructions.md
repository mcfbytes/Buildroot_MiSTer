# Phase 1 worker instructions — MiSTer kernel patch reconciliation

You are reconciling **exactly ONE commit** from the MiSTer Linux kernel fork against vanilla
6.18.38 (plan: `MISTER-KERNEL-PATCH-RECON.md` §4). **Analyze ONLY your assigned commit. Never
group it with other commits** — grouping is the exact failure mode this project exists to fix.

## Get the diff

```
git -C /mnt/source/Linux-Kernel_MiSTer show --stat <sha>     # always start here
git -C /mnt/source/Linux-Kernel_MiSTer show <sha>            # full diff
```
If the diff is huge (thousands of lines, e.g. vendored drivers), do NOT read it all — use
`--stat`, sample representative files, and analyze at the directory/driver level.

## Resources (all read-only; write ONLY your one record file)

| What | Where | Use for |
|---|---|---|
| Vanilla 6.18.38 source + **full git history** | `/mnt/source/linux` (checked out at v6.18.38) | grep; `git log -S'<symbol>'`, `git log --grep`, `git log -- <path>` to find where functionality landed; the ONLY valid source of vanilla SHAs/quotes |
| Vanilla 5.15.1 base snapshot | `/mnt/source/linux-5.15.1` | what the fork patched — context for the original change |
| Fork repo | `/mnt/source/Linux-Kernel_MiSTer` (branch `MiSTer-v5.15`) | your commit and its neighbors |
| Carried patches | `/mnt/source/Buildroot_MiSTer/board/mister/de10nano/linux-patches/*.patch` (25 files, `0001`–`0031` with gaps) | is this commit carried? grep for symbols/strings from your diff |
| Our kernel config | `/mnt/source/Buildroot_MiSTer/board/mister/de10nano/linux.config` | kconfig reconciliation |
| Our Buildroot defconfig | `/mnt/source/Buildroot_MiSTer/configs/mister_de10nano_defconfig` | BR2 packages (some fork drivers now ship as out-of-tree kmod packages, e.g. xone, 8812au — grep `package/` and the defconfig) |
| Stock kernel config | `/mnt/source/Buildroot_MiSTer/docs/stock-inventory/stock-linux.config` | what stock shipped |
| Main_MiSTer userspace | `/mnt/source/Main_MiSTer` | userspace coupling: grep input event codes, ioctls, sysfs paths, /dev nodes |
| Prior art (**may be wrong**) | `/mnt/source/Buildroot_MiSTer/docs/patch-provenance.md` | record what it claims, then re-derive INDEPENDENTLY |

## Grounding contract (mandatory)

1. **No upstream claim without a quote.** A `dropped-upstream` disposition MUST cite a
   `file:line` in `/mnt/source/linux` AND quote the matching hunk, AND you must confirm the
   vanilla code does the *same thing* your commit does — same-filename or same-subject is NOT
   equivalence. If you cannot find and quote it, set `disposition="needs-verification"`.
   **Never write a vanilla SHA you did not obtain from a git command you ran in
   `/mnt/source/linux` during this task.** Model memory is not a source.
2. **If vanilla does something different** from your commit: `equivalence="contradicted"`,
   treat as a carry candidate, and if the provenance doc claimed it was upstream, set
   `disposition="misclassified"`.
3. `failure_mode="silent"` if dropping the commit produces no build/boot error — the feature
   just quietly disappears. Flag these prominently in `notes`.
4. `userspace_coupling.coupled=true` if Main_MiSTer (or userspace generally) depends on the
   behavior — input event codes, ioctls (e.g. EVIOCGRAB), sysfs attrs, /dev nodes, module
   params. Cite `path:line` in Main_MiSTer when found.
5. For `kconfig` changes the question is not "is it upstream" but: does each `CONFIG_*` still
   exist in 6.18 (grep Kconfig in `/mnt/source/linux`)? renamed? and is it set in OUR
   `linux.config` / provided by a BR2 package? `verification.method="config-grep"`.
6. For vendored/third-party code capture `license_provenance` (author, license header, origin
   project) — it gates whether we can carry or upstream it.

## Output

Write **one JSON object** (pretty-printed) to
`/mnt/source/Buildroot_MiSTer/docs/kernel-recon/records/<full-sha>.json` — nothing else, no
other file writes. Schema (use `null` where inapplicable; keep every key):

```json
{
  "sha": "<full sha>",
  "subject": "<verbatim>",
  "author": "<name>", "author_is_pr_contributor": false,
  "date": "YYYY-MM-DD",
  "subsystem": "<hid|input|fbdev|sound|cpufreq|dts|mmc|usb|net-wireless|bt|fs|kconfig|...>",
  "change_type": "<from your assignment row>",
  "files": ["..."], "added": 0, "removed": 0,
  "is_backport_of_vanilla": false,

  "disposition": "carried | dropped-upstream | dropped-deliberate | dropped-obsolete | not-evaluated | needs-verification | misclassified",
  "carried_patch": "<00xx-*.patch or null>",
  "carried_mode": "clean-apply | re-implemented | null",

  "upstream": {
    "vanilla_shas": [],
    "vanilla_file_line": null,
    "vanilla_quote": null,
    "equivalence": null
  },

  "verification": { "method": "source-grep | diff | cherry-patch-id | config-grep | needs-hardware", "confidence": "high | medium | low", "contradiction": false },
  "agrees_with_provenance_doc": null,
  "provenance_doc_ref": null,

  "impact": {
    "effect_if_absent": "<concrete user-visible effect>",
    "affected_hardware": [], "device_ids": ["VVVV:PPPP"],
    "severity": "boot-critical | feature-loss | cosmetic | none",
    "failure_mode": "loud | silent"
  },
  "userspace_coupling": { "coupled": false, "interface": null, "main_mister_ref": null },
  "forward_port": { "applies_to_6_18": null, "conflicts": null, "effort": null },
  "dependencies": { "depends_on": [], "superseded_by": [], "duplicate_of": [] },
  "license_provenance": null,
  "notes": "<key reasoning, silent-regression flag, anything the auditor must know>"
}
```

`equivalence` values: `byte-identical | equivalent | superseded-better | partial | contradicted`.
`carried` + also-in-vanilla is possible — if a carried patch duplicates something now upstream,
say so in `notes`.

## Pilot lessons (mandatory — these were the actual first-pass errors)

- **"carried" strictly means a `00xx-*.patch` exists in `linux-patches/` — name it.** Coverage
  via a BR2 package or a mainline driver is `dropped-deliberate`/`dropped-obsolete` with
  `superseded_by` naming the package/driver, never "carried".
- **`equivalence="contradicted"` ⇒ carry candidate** (`misclassified` if the provenance doc
  claimed upstream coverage). Never pair `contradicted` with `disposition="dropped-upstream"`.
  The `superseded-better` grade requires EVIDENCE of zero userspace coupling to the fork
  interface (grep Main_MiSTer and cite the absence).
- **`verification.contradiction` flag** is only for "an upstream-coverage claim turned out to
  not match vanilla" — never set it on deliberate drops where vanilla differing is expected.
- **Device IDs: re-derive every VID:PID** from the driver's ID table / `hid-ids.h` in the
  actual checkout. Transposed/misremembered IDs were the most common first-pass error.
- **Never copy `file:line` from patch-provenance.md** or any prior doc into your record —
  re-derive against the live checkout and quote what is actually there.
- **Keep contexts separate**: what the commit did in the STOCK 5.15 fork vs how OUR 6.18 build
  covers it. "Not enabled in our config" does not mean the commit was dead code in stock.

## Final message

End your final message with exactly one line:
`ESCALATE: yes — <reason>` or `ESCALATE: no`
Escalate=yes if ANY of: disposition is `dropped-upstream` or `needs-verification` or
`misclassified`; `verification.confidence="low"`; `verification.contradiction=true`; your
commit's patch-provenance.md entry is a GROUPED row (multiple commits in one row); you assert
userspace coupling without a Main_MiSTer `path:line` citation; or you could not complete any
grounding step.
