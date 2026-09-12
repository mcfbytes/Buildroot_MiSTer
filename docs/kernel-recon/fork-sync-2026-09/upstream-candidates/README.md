# Wave 5 — upstream candidates for MiSTer-devel/Linux-Kernel_MiSTer

> **Outcome (2026-09-12).** Sent as Linux-Kernel_MiSTer PRs #95 (candidate 2), #96 (3), #97 (4)
> and #98 (7), plus config PRs #93/#94. #95 and #98 merged. **#96 and #97 were closed**: the
> maintainer took the userspace alternatives instead (Main_MiSTer #1307/#1308, in Release
> 20260912), so the source patches for candidates 3 and 4 — `0040`, `0041` — were **retired from
> this repo's series** the same day. The `03-*`/`04-*` files below are kept as the record of what
> was offered; the regeneration table's rows for them no longer resolve. Candidates 5 and 6 are
> still unsent.

**Purpose: these patches are PREPARED, not sent.** No network push, no PR was opened
from this session (the environment has no `gh`/GitHub API access, and pushing is out of
scope for this wave per `PLAN.md` §5.2). Everything here is a ready-to-apply artifact
under this repo's own tree, for the owner to review and send at their discretion — in
particular, **after reading the PR #75 thread** on `MiSTer-devel/Linux-Kernel_MiSTer`
(a prior discussion on this fork about carrying MiSTer-specific behavioural patches
upstream; not accessible from this session — GitHub HTML/API is unreachable here) to
judge how the maintainer feels about this class of change before any of these are
actually opened as PRs.

All seven candidates target `MiSTer-v6.18` at
`c129b0fac34ad5d613bbec3f59d6036775e41c83` (the commit stock Release 20260907 ships).
None of them touch this repo's own tree, `$S/fork-6.18`, or `$S/linux` — they are
standalone patches meant to apply to a **checkout of his tree**, not ours (his tree's
independently forward-ported drivers have different surrounding context than ours).

## Candidate table

| # | Candidate | Strength | Applies alone (`patch -p1 -F0` / `git am`) | Compiles (`W=1`) | Overlaps |
|---|---|---|---|---|---|
| 1 | NSO Genesis BT PID normalization | **N/A — already fixed on his tree** | — | — | — |
| 2 | NSO N64/Genesis stock button mapping | Strong (stock-5.15 parity, `bN`-index coupling) | Clean, 0 offset | Clean, 0 new warnings | Shares `hid-nintendo.c` with 3, 4 |
| 3 | IMU input-device name suffix | Weak/cosmetic (naming only) | Clean, 0 offset | Clean, 0 new warnings | Shares `hid-nintendo.c` with 2, 4 |
| 4 | Stock LED classdev names (player1-4/home) | Weak/cosmetic (naming only) | Clean, 0 offset | 1 new warning, harmless (see below) | Shares `hid-nintendo.c` with 2, 3 |
| 5 | Stock lightbar LED names + probe-time clear | Weak/cosmetic (naming; player-LED clear was already present on his tree) | Clean, 0 offset | Clean, 0 new warnings | Shares `hid-playstation.c` with 6 |
| 6 | BTN_Z scoped to DualSense only | Strong (stock-parity correctness; DS4 behavioural change, see its `.PR.md`) | Clean, 0 offset | Clean, 0 new warnings | Shares `hid-playstation.c` with 5 |
| 7 | `MiSTer_fb.c` `memremap()`/`IS_ERR` bug (F1) | N/A — bug-fix quality, not a stock-5.15 restoration | Clean, 0 offset | Clean, 0 warnings | Independent (`MiSTer_fb.c`) |

**All six patches (2–7) also verified applying together, in this numbered order, in one
pass** — `patch -p1 -F0` and `git am` both — onto a single fresh `c129b0fac` checkout,
producing output byte-identical to the individually-verified copies. The only offsets
(all well within `-F0`, zero fuzz) come from earlier patches in the same file shifting
line numbers for later ones:

- **02 → 03 → 04** (`drivers/hid/hid-nintendo.c`): 03 needs a +17-line offset after 02;
  04 needs a +27-line offset after 02+03. Each still applies alone (0 offset) to a
  pristine extract.
- **05 → 06** (`drivers/hid/hid-playstation.c`): 06 needs +23/+71-line offsets after 05.
  Each still applies alone (0 offset) to a pristine extract.
- **07** (`drivers/video/fbdev/MiSTer_fb.c`) is fully independent of the other six.

The one compile-time note: after candidate 4, `drivers/hid/hid-nintendo.o` picks up a
new Clang warning, `-Wunneeded-internal-declaration` on `joycon_player_led_names[]`.
The array is still used to size `JC_NUM_LEDS` via `ARRAY_SIZE` (a compile-time
constant), but its string contents are no longer read at runtime after the name format
changes to `"%s:player%d"`, so Clang notices it no longer needs the backing storage.
This is compile-time-only with no functional effect, and it is the same idiom this
repo's own carried `0041-hid-nintendo-stock-led-classdev-names.patch` uses (reproduced
with a minimal standalone test: a `static const char *[]` array referenced only via
`sizeof`/`ARRAY_SIZE` triggers the same warning under Clang regardless of which tree it
lives in).

## Regeneration — these are derived from this repo's own carried patches

Every candidate here is a re-anchoring of a change this repo already carries in
`board/mister/de10nano/linux-patches/`, ported by hand onto his tree's differing
context (his file has independently-ported surrounding code, not ours) and re-verified
from scratch against `c129b0fac`. If the carried series changes, regenerate the
matching candidate from its new content rather than hand-editing the `.patch` file here.

| Candidate | Source patch in this repo |
|---|---|
| 1 (no patch) | `board/mister/de10nano/linux-patches/0038-hid-nintendo-nso-genesis-bt-pid.patch` |
| 2 | `board/mister/de10nano/linux-patches/0039-hid-nintendo-nso-n64-genesis-stock-button-mapping.patch` |
| 3 | `board/mister/de10nano/linux-patches/0040-hid-nintendo-imu-name-suffix.patch` |
| 4 | `board/mister/de10nano/linux-patches/0041-hid-nintendo-stock-led-classdev-names.patch` |
| 5 | `board/mister/de10nano/linux-patches/0042-hid-playstation-stock-lightbar-led-names.patch` |
| 6 | `board/mister/de10nano/linux-patches/0037-hid-playstation-dualsense-mute-btn-z.patch` |
| 7 | `board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch` (the correct-form reference; F1 itself has no carried-patch origin — see `tree-diff-2026-09.md` §5) |

Candidates 5 and 6 are each a *subset* of their source patch's content: his tree already
independently implements the rest of `0037`'s and `0042`'s changes (the `":mute"` LED,
mic-mute→`BTN_Z` reporting, the single `":player_id"` classdev, and the player-LED clear
at probe are all already present on `c129b0fac` — see each `.patch` file's commit
message for the exact grep evidence). Only the residual gaps are ported.

## How to apply to a fork checkout

```sh
# from a checkout of MiSTer-devel/Linux-Kernel_MiSTer, branch MiSTer-v6.18,
# at c129b0fac34ad5d613bbec3f59d6036775e41c83 (or later, with -F0/offset tolerance)
cd /path/to/Linux-Kernel_MiSTer
git checkout MiSTer-v6.18

git am /path/to/Buildroot_MiSTer/docs/kernel-recon/fork-sync-2026-09/upstream-candidates/02-hid-nintendo-nso-n64-genesis-stock-button-mapping.patch
# 03-/04- (IMU name, LED names): do NOT re-offer -- closed upstream as #96/#97, see the note at the top
git am /path/to/Buildroot_MiSTer/docs/kernel-recon/fork-sync-2026-09/upstream-candidates/05-hid-playstation-stock-lightbar-led-names.patch
git am /path/to/Buildroot_MiSTer/docs/kernel-recon/fork-sync-2026-09/upstream-candidates/06-hid-playstation-dualsense-btn-z-scoping.patch
git am /path/to/Buildroot_MiSTer/docs/kernel-recon/fork-sync-2026-09/upstream-candidates/07-fbdev-mister-fb-memremap-null-check.patch
```

Each is also independently `git am`-able on its own against a fresh `c129b0fac`
checkout — apply only the subset you want.

## How to push to a fork branch

```sh
git checkout -b upstream-candidates-2026-09   # or one branch per candidate, your choice
git push <your-fork-remote> upstream-candidates-2026-09
```

No PR-creation command is given here deliberately — opening the PR(s) is the owner's
decision, made after reading the PR #75 thread referenced above.

## Files in this directory

- `01-hid-nintendo-nso-genesis-bt-pid.NOTE.md` — why candidate 1 produced no patch.
- `0N-<slug>.patch` (N = 2–7) — the patch itself, `git am`-able, `From:` line carrying
  the original 5.15-origin author where one exists (candidate 7 has none: it's a fresh
  finding, not a stock-5.15 restoration, so it's authored and signed solely by
  Michael C. Ferguson).
- `0N-<slug>.PR.md` — proposed PR title + body for that candidate, written for his
  repo's audience.
- This `README.md`.
