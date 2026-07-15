# Full-run orchestration state (working notes — NOT a deliverable)

Updated: 2026-07-15 (Fable orchestrator). All 103 Haiku workers launched (88 main + 15 residue).
Records land in `records/<sha>.json`. Tier-2 = Sonnet 5 only (user directive: no Fable/Opus workers).

## Escalation queues

### A. Individual Sonnet — HIGH-STAKES contradiction / coupled-regression claims
- [ ] fc09a292a — 8821cu EDUP efuse workaround claimed ABSENT from mainline rtw88 (confirmed silent per-device regression?)
- [ ] 45283785a — nintendo :combo LED fork-only + Main_MiSTer reads it (input.cpp:4704) — coupled silent regression candidate
- [ ] 8a100f2ed — new-lg4ff wholesale rewrite; claim "wheels lose FF entirely" is suspect (vanilla lg4ff has FF_CONSTANT for G25/27/29) — verify what's actually lost vs provenance §9.3
- [ ] b76b4bc6a — misclassified, 3rd defect in provenance row 337 (player-6 LEDs, unreachable from userspace)
- [ ] b02a4a011 — CSR clones lmp_subver 0x2512 gap — needs-verification
- [ ] 60821059c — nintendo home-LED non-fatal probe — vanilla-vs-fork contradiction, needs-verification
- [ ] 9bdab534b — nintendo calibration: "dropped-upstream + contradicted" semantics violation, different defaults
- [ ] e40563ae1 — m41t81 compatible-string contradiction ("stm,"→ later fixed by 2548c2978; over-flagged?)
- [ ] 246984fce — split disposition + ltcmode GPIO LED omission undocumented
- [ ] 077c2c317 — split carry (DTS carried / driver dropped-as-no-op) — verify no-op equivalence argument

### B. Batch Sonnet — dropped-upstream SHA verification (mechanical; one agent per batch, PER-RECORD verdicts)
- [ ] batch-up-1: 9a8cb6a93 (f5554725f304), adbaaea91 (f5554725f304), 409f81077 (e23c69e33248 + xone-exclusion interplay), 6eec2a515 (21617de3b464), e155f6a2f (94f18bb19945)
- [ ] batch-up-2: a10f4246f (c7577014b74c), 3fb48dc16 (4fd6d4907961), e2c082ef9 (a3dc32c635ba + usb_modeswitch), 1412bd707 (74cb485f68eb + doc-name discrepancy), 71c583074 (split; c7622a4e44d9)
- [ ] batch-up-3: c4ec5cb40 (2af16c1f846b, big driver), ae9313e22 (vocabulary: config-enable ≠ dropped-upstream), f9c64d8cd DONE in pilot — skip
- [ ] later arrivals with dropped-upstream: add here (watch af27afc4c UAPI, 5c410e935, kconfig stragglers, residue workers)

### C. Batch Sonnet — grouped-row-only carried/deliberate records (verify patch-hunk mapping claims, per-record verdicts)
- [ ] batch-grp-dts: 1337de1fd, c4d12c768, 7d2df2d2d, 6827e7644, f52690120, 071d9092e, 2548c2978 (all → 0004)
- [ ] batch-grp-input: fc8f3c2c6, b745ce6d9 (0019), 52a56ae3d (0026), 15968bc26/0d7778d1f/47dc53a22 (0023), f3c75eb02/a2242dd85 (0017)
- [ ] batch-grp-vendored: 99a2c80d0/5220d6686/7f7148c1f/8b6b8c2f5/858322ce6 (exfat), c708f2222/5a7965488/d776ddb4e no-esc (xone), 43fbb63ae/2371fb1aa/143ce187e/3740d5b88/993b82e31 no-esc (realtek)
- [ ] batch-grp-defconfig: 215e6e662, d788e7ab9, 0d7b4fc7e, 5391b8171, 316288a3d (+ arrivals 1a1f208fa, 97a398176, 9f59d13d5)
- [ ] 43c52e9ef — verify §9.3 hard-fail risk analysis acceptance (goes with batch-grp-vendored or individual)

## After all verifications: Phase 2 reduce
- validate all ~123 records (pilot validator script pattern), enforce invariants (completeness vs commits.jsonl
  + residue list; single disposition; dropped-upstream evidence; tree-diff attribution already done Phase 0)
- emit reconciliation.{jsonl,md}, disagreements-with-provenance.md, silent-regressions.md, device-support.md
- commit records in one batch + reduce outputs; then Phase 3 audit per plan §6

## Running findings list (for silent-regressions.md)
- **45283785a Joy-Con :combo LED — VERIFIED, WORST-CASE**: Joy-Con combining totally+silently broken
  on 6.18; Main_MiSTer's ONLY pairing path (input.cpp 4704/4715 read, 4822-23 write, bind at 4729-30)
  gated on fork LED; no manual fallback. misclassified (row 334). Carry candidate #1.
- f84543926 player_id LED (pilot, confirmed, coupled). Carry candidate #2.
- b02a4a011 CSR 0x2512 — VERIFIED structural gap in vanilla (all range checks top out 0x22bb);
  hardware-gated carry candidate; provenance doc had already flagged (agrees=true); confidence medium.
- b76b4bc6a player-6 — VERIFIED cosmetic; depends_on f84543926 only; rides that carry decision.
- fc09a292a EDUP efuse — VERIFIED: absent from mainline rtw88 AND morrownr package; silent RF
  misconfig for bad-efuse units; hardware-gated needs-verification carry candidate.
- 8a100f2ed lg4ff — FALSE POSITIVE, removed: vanilla lg4ff covers all fork wheel IDs; Main_MiSTer
  Logitech path uses only FF_AUTOCENTER (the FF_SPRING cite was the Fanatec branch). severity=none.
  (G923-PS variant gap belongs to 43c52e9ef, already dropped-deliberate per §9.3.)
- macvlan config drift (pilot, orchestrator-confirmed)
- ltcmode GPIO LED — NON-FINDING: fork commented the node out 4 days after adding it; never shipped
- 60821059c home-LED registration failure still FATAL in vanilla (partial equivalence) — narrow
  clone-hardware carry candidate (Pro Controller / right Joy-Con only); misclassified row 334
- 60e08955f mute BTN_Z (pilot, confirmed, cosmetic — no consumer)
- 97a398176 JOYSTICK_XPAD y-vs-m drift (pending verify, defconfig batch)
- possible NFS_V3 config gap (pending verify, defconfig batch #4)


## CARRY DECISIONS EXECUTED (2026-07-15, user-directed)
- 0032 combo LED (45283785a), 0033 player_id+player6 (f84543926+b76b4bc6a), 0034 NES/Famicom A/B
  (e155f6a2f partial), 0035 home-LED non-fatal (60821059c), 0036 btusb CSR 0x2512 (b02a4a011 partial)
- linux.config: +CONFIG_MACVLAN=y; CONFIG_JOYSTICK_XPAD y->m (stock parity)
- fc09a292a EDUP efuse: dropped-deliberate per user (stay on mainline rtw88); documented limitation
- verification: full `make linux-dirclean linux-rebuild` PASSED (all 30 patches applied by buildroot,
  zImage+dtb installed, xpad.ko present, MACVLAN=y in resolved .config); series-applies check on
  pristine v6.18.38 PASSED; per-object cross-compile clean (no warnings)
- remaining open: 60e08955f mute/BTN_Z (misclassified, cosmetic, no consumer) — user decision pending
- next: full `make all` before flashing (kmod-package trap does not apply — same kernel version);
  Phase 3 audit; provenance-doc corrections (15 rows)
