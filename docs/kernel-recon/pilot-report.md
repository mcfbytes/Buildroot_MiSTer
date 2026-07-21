# Phase 1 pilot report — 20-commit sample

Run 2026-07-15. Fan-out: 20 Haiku 4.5 workers (one per commit, never grouped) + 8 tier-2
verifications (7 Sonnet 5 escalations + 1 orchestrator amendment with direct grep evidence).
Records in `records/<sha>.json`; all 20 validate against the schema with zero problems.

## Pass criteria (plan §9) — ALL PASS

| Criterion | Result |
|---|---|
| Schema captures everything without free-text overflow | ✅ 20/20 records well-formed, all keys present, invariants hold |
| Grounding contract blocks hallucinated SHAs | ✅ no fabricated vanilla SHA shipped; tier 2 caught 1 wrong SHA attribution, 3 bad device-ID sets, 2 copied-not-derived line citations before shipping |
| Canary `60e08955f` returns misclassified / contradicted / doc-disagreement | ✅ confirmed airtight by independent Sonnet re-derivation |

## Dispositions (20 commits)

| Disposition | n | Commits |
|---|---|---|
| carried | 10 | 0001 fb, 0002 audio, 0003 cpufreq (×2 commits), 0004 DT, 0014 gamecube, 0020 mmc-LED, 0026 EVIOCGRAB, 0027 mt76-IDs, 0028 dwc2 |
| dropped-deliberate | 4 | xone (→BR2 package), wifi mega-commit (→per-chipset BR2/mainline table), 80211-as-module, vt-9-ttys |
| dropped-upstream | 2 | hid-nintendo div-0 (vanilla `6eb04ca8c52e`), dualsense lightbar (superseded-better, multicolor classdev) |
| dropped-obsolete | 1 | edimax EW-7822ULC fix (superseded by mainline `rtw88_8822bu` + morrownr package that never had the bug) |
| **misclassified** | **2** | **dualsense mute `60e08955f` (canary), dualsense player-LED `f84543926` (NEW)** |
| not-evaluated | 1 | macvlan config enable (open decision, see findings) |

Provenance-doc disagreements: 4 (`60e08955f`, `f84543926`, `0d60c3482`, `115b1d1ae`) — all in
rows that grouped commits or asserted upstream coverage without verification.

## Headline findings

1. **NEW silent regression (carry candidate): `f84543926` "dualsense: add player id led control."**
   Main_MiSTer is co-designed against the fork's single `:player_id` LED
   (`input.cpp:2642-2726` constructs the exact fork naming); vanilla 6.18 exposes five
   `:white:player-N` classdevs instead and auto-assigns from IDA connect order. On vanilla the
   `:player_id` write fails and Main_MiSTer silently falls back to the DS4 RGB branch.
   Feature-loss, silent, userspace-coupled. `patch-provenance.md:337` wrongly grouped it as
   "now upstream, drop."
2. **Canary `60e08955f` confirmed, severity corrected.** The misclassification is real and
   airtight (the doc's two cited SHAs contain zero mute-related content; vanilla 6.18 still
   handles mute kernel-internally — no BTN_Z, no `:mute` classdev). However exhaustive grep
   found **no shipped Main_MiSTer consumer** of BTN_Z/`:mute` → severity is cosmetic today;
   it remains a carry-decision item, and the community framing should say exactly that.

   > **CORRECTION (2026-07-20): the "cosmetic, no consumer" call above was WRONG.** The grep
   > looked for a BTN_Z *symbol* consumer; the coupling is **positional, not by name**.
   > `BTN_Z` is `0x135`, between `BTN_WEST` (`0x134`) and `BTN_TL` (`0x136`), so declaring it
   > inserts an index into the `EV_KEY` capability bitmap and shifts every button from L1 up
   > by one. Main_MiSTer derives SDL-style `bN` indices by walking that bitmap
   > (`Main:gamecontroller_db.cpp:get_ctrl_index_maps`), and the shipped `gamecontrollerdb.txt`
   > `platform:MiSTer` PS5 rows are written for the BTN_Z-present layout (`guide:b11`,
   > `leftshoulder:b5`, `back:b9`, `start:b10`) vs upstream `platform:Linux` (`guide:b10`,
   > `leftshoulder:b4`, …) — an exact +1 offset that exists *because of* this patch.
   > Caught in the field on the 7.2-rc4 RT beta, whose series omitted `0037`: PS/Home acted
   > as Start and L3 opened the OSD. **Methodology fix:** a patch that adds or removes an
   > `EV_KEY`/`EV_ABS` capability is load-bearing for every SDL-style index map. Symbol greps
   > cannot establish "no consumer" for capability changes — check `gamecontrollerdb.txt`
   > `platform:MiSTer` rows instead. (Saved `input_<vid><pid>_v3.map` files store raw evdev
   > codes and are immune; only the gcdb auto-map path is affected.)
3. **Live config drift: `f0fb626ac` macvlan.** Stock enabled `CONFIG_MACVLAN=y` on 2026-07-08
   — after our stock-inventory snapshot was taken — and our `linux.config` has no MACVLAN line.
   Decision required (enable for stock-next parity or document a deliberate drop). Process
   finding: **config reconciliation must diff against fork-HEAD `MiSTer_defconfig`, not only
   the aged `stock-linux.config` snapshot.**
4. **`patch-provenance.md:337` is a defect cluster.** The one grouped row covered 4 commits;
   2 of them are now confirmed misclassified. The 4th commit in that row (`b76b4bc6a`
   "dualsense: leds config for player 6") must be treated as high-priority in the full run.
5. Minor: `linux.config` comment claiming mainline cannot drive RTL8812AU/8821AU is stale
   (mainline rtw88 support landed in 6.13); harmless (morrownr packages cover them) but worth
   a cleanup.

## What tier 2 caught (cheap-tier error taxonomy)

8 of 20 records (40%) received tier-2 verification; **all 8 needed corrections**, none of
which reversed a carried/dropped call incorrectly made — they fixed precision and semantics:

| Error class | Cases | Example |
|---|---|---|
| Disposition vocabulary misuse | 3 | "carried" for BR2-package coverage; "dropped-upstream" despite `equivalence=contradicted` |
| Device-ID hallucination/transposition | 3 | `054C:CE6E`/`05C5` → real `054C:0CE6`/`0DF2` |
| Citation copied from prior doc, not re-derived | 2 | provenance line numbers pasted into `vanilla_file_line` |
| `contradiction` flag misuse | 1 | set on a deliberate-drop record |
| Stock-vs-our-build context conflation | 1 | wifi drivers called "dead code/abandoned" |
| Equivalence overstated | 1 | byte-identical → equivalent (whitespace differs) |

Zero hallucinated vanilla SHAs survived to shipped records; one wrong SHA *attribution*
(`8e5198a12d64` cited for lightbar control it doesn't implement) was caught by tier 2.

## Recommendations for the full 108-commit run

- Keep the two-tier design; budget ~40% escalation rate.
- Worker instructions updated with pilot-lesson rules (see `worker-instructions.md` §Pilot
  lessons): strict "carried" semantics, contradiction-flag semantics, re-derive device IDs
  from ID tables, never copy citations from the provenance doc, separate stock-context from
  our-build-context, `contradicted ⇒ carry candidate`.
- Auto-escalate to Sonnet regardless of self-assessment: any commit whose provenance-doc entry
  is a **grouped row**, and any record asserting userspace coupling without a `path:line` cite.
- The old-branch residue (6 + 9 commits) runs with the same pipeline as an appendix.
