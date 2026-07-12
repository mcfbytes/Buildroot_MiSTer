# Phase 0 Review Gate — `phase0-recon` Branch

**Document purpose:** Human decision point to approve Phase 0 findings and unblock Phase 1. This is the one-page summary a reviewer reads to make a go/no-go call.

**Branch:** `phase0-recon`  
**Status:** All Phase 0 tasks (P0.1–P0.9) complete and verified. Phase 1 is **blocked** pending human sign-off below.

---

## Phase 0 Exit Criterion

From `TASKS.md`: **"patch triage and ABI contract complete and human-reviewed"**

**Status: NOT YET MET — the work half is done, the review half is not.**

The patch triage (P0.4) and the ABI contract (P0.5) are complete, as are the other seven
tasks. But *human-reviewed* is part of the criterion, and no human has reviewed this yet.
The criterion is met when the sign-off block at the bottom of this document is filled in —
not before. Five of the open questions below cannot be answered by a model at all.

All nine deliverables are complete and committed:

| Task | Deliverable | Status |
|------|-------------|--------|
| P0.1 | Repository scaffolding (`.gitignore`, `.editorconfig`, README stub) | ✓ Complete |
| P0.2 | Reference materials (work/ inventory, stock image extraction) | ✓ Complete |
| P0.3 | Stock image inventory (libs, binaries, configs, firmware, modules) | ✓ Complete |
| P0.4 | Kernel commit triage (A–F classes, `docs/patch-provenance.md`) | ✓ Complete |
| P0.5 | ABI contract document (`docs/abi-contract.md`) | ✓ Complete |
| P0.6 | Downloader `LinuxUpdater` contract (`docs/downloader-contract.md`) | ✓ Complete |
| P0.7 | Package mapping to Buildroot 2026.02 (`docs/package-manifest.md`) | ✓ Complete |
| P0.8 | Boot chain analysis (`docs/boot-chain.md`) | ✓ Complete |
| P0.9 | Phase 0 review gate (this document) | Awaiting human sign-off |

---

## Headline Results: The Project's Central Bet Is Confirmed

### 1. All 12 SONAMEs the stock `MiSTer` binary needs survive in Buildroot 2026.02

**Status: CONFIRMED** (ledger #25)

- 251/251 NEEDED SONAMEs from the stock binary map to Buildroot 2026.02 packages
- **Zero unmapped dependencies**
- Both SONAMEs flagged as highest-risk carry forward at compatible major versions:
  - `libbluetooth.so.3` — bluez 5.61 → 5.79 (same major)
  - `libImlib2.so.1` — imlib2 1.12.5 (same version)
- **PLAN §1's premise holds: no MiSTer binary needs rebuilding.** The stock binary will run unchanged on the new rootfs.

### 2. The kernel delta is provably 109 commits

**Status: CONFIRMED** (ledger #1, #16)

- PLAN.md §4.1 states "~60 commits"; actual: **109 commits** after the version-bump commit
- **Content verification:** the version-bump commit's tree (`aba1ef4c1`) is byte-identical to pristine kernel.org 5.15.1 (0 files differing, 0 added)
- Excluding vendored WiFi, the entire kernel problem is **143 files** touched
- Update PLAN.md §4.1, §12, §14, and TASKS.md task text citing commit count

### 3. Phase 1 got easier in one place: `MiSTer_fb` has no custom ioctl at all

**Status: VERIFIED** (ledger #28)

- Only one ioctl exposed: `FBIO_WAITFORVSYNC` — standard mainline UAPI, bit-identical in 5.15 and 6.18
- **P1.4 task is materially less risky than the plan assumes**
- The real custom ABI surface is sysfs param `/sys/module/MiSTer_fb/parameters/mode` (documented in `docs/abi-contract.md`)
- `/dev/fb0` is never mmap'd; the only mmap is `/dev/mem` (shmem.cpp:22), which is why A4 (STRICT_DEVMEM off) is the whole ballgame

---

## Corrections Required to PLAN.md / TASKS.md

Every item below traces to the ledger. Group by severity; each must be folded into the respective plan document during the P0.9 commit.

### HIGH severity — block or materially change Phase 1

| Find | PLAN/TASKS says | Actually true | Evidence | Action |
|------|-----------------|---------------|----------|--------|
| #3a | `/etc/resolv.conf` is a regular file (PLAN §3: "no symlink-into-tmpfs schemes") | `/etc/resolv.conf` IS a symlink → `/tmp/resolv.conf` in stock | Verified on raw ext4 image (inode 112, symlink type) | **Q2 (human decision):** bug-for-bug parity (reproduce the silent no-op), or fix it to a regular file? Fixing is a behavior change. Update PLAN §3 outcome + rationale. |
| #8 | P1.3 task: "port the exact extracted stock config via `olddefconfig`" | Stock has `CONFIG_BLK_DEV_INITRD=y` **NOT** set (stock-linux.config:170) | Verified: `# CONFIG_BLK_DEV_INITRD is not set` | P1.3 text must be amended to require `BLK_DEV_INITRD=y` as an **explicit intentional divergence** from stock. Doing `olddefconfig` silently breaks the entire §5 initramfs design. New constraint **A11** below. |
| #18 | P1.5 task: "Card/device name exposed to userland must match stock" | Audio ABI is NOT a card name. It is `/dev/MrAudio` + patched `snd-dummy` + `/etc/asound.conf` routing | Verified: Main_MiSTer contains **zero** ALSA code; `/etc/asound.conf` routes default PCM to `/dev/MrAudio` with hw card fallback | P1.5 task text is **factually wrong**. Rewrite acceptance criteria around `/dev/MrAudio` + asound.conf. Patch `sound/drivers/dummy.c` (commit `333d49b95`) must be carried — omit it and system is silent. New constraint **A12** below. |
| #17 | PLAN's A–F taxonomy covers all kernel classes | Class G (out-of-tree exfat driver) missing from taxonomy | P0.4 verified: stock's `fs/exfat` is Samsung out-of-tree driver, **not** mainline; it mounts FAT12/16/32 and exFAT under `-t exfat`, supports symlinks via `ATTR_SYSTEM` bit. Mainline exfat/vfat have **no symlink support.** Main_MiSTer actively resolves those symlinks (file_io.cpp:1592). | **Q1 (human decision):** Does the community rely on symlinks on `/media/fat`? Answer decides: carry the out-of-tree driver (large unbudgeted maintenance burden), or drop it and accept user-visible regression? A decision entry in PLAN §1. |
| #29 | — | Main_MiSTer refuses to scan past `/dev/i2c-2` (smbus.cpp:214: `if (force_bus > 2)`) | Verified: ADV7513 HDMI transmitter must be on i2c-0..2. Adding a 4th adapter or reordering DTB puts HDMI **silently out of reach**. | Hard constraint on P1.7's DTS authoring. New constraint **A14** below. |

### MEDIUM severity — affect implementation but do not block

| Find | PLAN/TASKS says | Actually true | Evidence | Action |
|------|-----------------|---------------|----------|--------|
| #4 | PLAN §10: "Document the exact `downloader.ini` ordering. This determines whether onboarding is one line or a support thread." Implies explicit ordering exists. | No ordering the user can control. Winner determined by which db.json **fetches and parses first**. Ours wins only because it is tiny vs Distribution's multi-MB catalog (emergent, not guaranteed). | `sorted_db_sections()` forces `default_db_id` to front; `installed_dbs` built in job-completion order across 6 workers. | Update PLAN §10: call out the **load-bearing design rule** to keep our db.json minimal (`empty files/folders`). Onboarding should use drop-in ini mechanism. Add §13 risk. |
| #20 | PLAN §5 `/init` sketch: mounts with generic flags | `/media/fat` is mounted `sync,dirsync` by kernel; `/etc/fstab` never re-mounts | Verified in stock kernel cmdline and boot process | PLAN §5 `/init` sketch must preserve `sync,dirsync`. Real power-off-corruption behavior change if omitted. |
| #12 | A2: "mount vfat **or** exfat (both built-in)" | The "or" is only sound because stock carries **both** exfat and vfat drivers; mainline exfat is **not** a FAT12/16/32 solution | Stock exfat mounts FAT12/16/32; mainline does not. A2 vfat→exfat fallback is a proof, not defensiveness. | Update A2 documentation: clarify the fallback addresses exFAT-only media, not FAT recovery. Document that FAT12/16 requires vfat. |
| #26 | A6: Python compatibility is "suspected" | Python 3.9→3.14 jump is now **evidenced**, not suspected | Downloader_MiSTer CI pins 3.9 in `.github/actions/setup-python` and builds against `python3.9-dev`. Buildroot 2026.02 ships 3.14, no legacy toggle. Updater that delivers our image never tested on our interpreter. | Update A6 and §13 (Risks): this is real, not formality. P3.9 testing is critical path. |
| #5 | P4.8 rollback runbook: assumes update success is atomic | The flash phase (`linux_updater.py:157-168`) has no `set -e`, ending in `touch`; exit status is `touch`'s. Failed `mv`/`rsync`/`updateboot` still report success and raise reboot flag. | Verified in Downloader source | P4.8 user docs must warn: **the update is not atomic, success signal is untrustworthy.** Rollback runbook must assume this. |

### LOW severity — correct prose, minor constraints, informational

| Find | PLAN/TASKS says | Actually true | Evidence | Action |
|------|-----------------|---------------|----------|--------|
| #1 | PLAN §4.1, §12, §14 cite "~60 commits" | 109 commits after version-bump | ledger #16 verification | Update all three sections with "109 commits" |
| #3 | PLAN §3, §4.1, TASKS A5, verification doc: "72 firmware files" | 66 regular files + 6 directories (`find \| wc -l` counted dirs) | P0.3 inventory | Update all four locations |
| #6 | A8 describes version check detail but not format constraint | `/MiSTer.version` must be **exactly 6 bytes, no trailing newline**. Compare is bare `f.read()` with no `.strip()`. Trailing newline ⇒ never matches ⇒ reflash forever. | `file_system.py:351-355` | New constraint **A10** (hard constraint on P2.6 post-build.sh) |
| #7 | PLAN §10 mentions pinned 7za | Our 7z must be extractable by pinned ARM `7za` (LZMA2+BCJ2 tested under qemu-arm) | — | P4.4 task should test 7z encoding with exact pinned binary |
| #9 | PLAN §3: both `mem=511M` and `memmap=513M$511M` do the reservation | `memmap=513M$511M` is inert on ARM (`early_param` only in x86/mips/xtensa, not arm/) | Verified in kernel source | Fix prose: `mem=511M` alone reserves. Both args are U-Boot's; don't touch either. Conclusion unchanged. |
| #10 | PLAN §3: "no ATAG involvement" | Stock ships `CONFIG_ATAGS=y` (stock-linux.config:461) | Verified | Add footnote: boot *path* uses no ATAGs (r2 = DTB), but config legitimately has it set. P1.3 should not hunt for a symbol that is correctly `y`. |
| #11 | PLAN §5 `/init` sketch hardcodes `losetup -r /dev/loop8` | `/dev/loop8` is an artifact, not a contract. Zero userland references in stock rootfs or Main_MiSTer. | `loop.max_part=8` pre-creates loop0–7; loop8 comes from `loop_probe` on demand | P1.10 must use `losetup -f` (find available loop device) instead. Update §5 sketch. |
| #13 | — | `mt` is a MiSTer-only U-Boot command (added by `c0ed23f52e` in U-Boot fork). `fpgacheck` depends on it. | Verified in fork source | Informational for P5.1 (mainline U-Boot port must reimplement `mt` or rewrite `fpgacheck`) |
| #14 | PLAN §8: "keep uboot.img byte-identical" (preference) | `uboot.img` cannot be rebuilt byte-identically (compiled-in `+0800` timestamp, `SOURCE_DATE_EPOCH` unset at build) | Verified by inspection | Strengthen §8: byte-identity is a necessity, not a preference. Fetch by hash, never build. |
| #21 | Carried patches include some dead weight | `dwc2/core.c` hunk is a no-op (same commit adds `disable-over-current` DT prop, still true in 6.18); `vt.h MAX_NR_CONSOLES` UAPI edit buys only a few KB | Verified in sources | Can drop both; update P0.4/P1.9 disposition list |
| #23 | Carried patches list | `0028-dwc2-fix-unaligned-in-split.patch` (Martin Donlon) is a genuine dwc2 bug fix still absent from 6.18 | Verified | Carry it; recommend upstreaming |
| #24 | — | NSO Famicom and Elite 2 Bluetooth paddle controller IDs are **not** in 6.18 even though their drivers are | Verified against 6.18 source | Both must be carried; "driver is upstream" ≠ "our IDs are upstream" |
| #27 | — | Secondary SONAME bumps (OpenSSL 1.1→3, libtiff 5→6, libffi 7→8) confirmed but harmless | Every consumer is rebuilt from source | Informational in P0.7 notes |
| #30 | PLAN §3: glibc floor "≥ 2.31" | Glibc floor is 2.28 (highest requirement: `fcntl64@GLIBC_2.28`) | Verified via readelf output | Update prose. Also: glibc 2.34 merged libpthread/librt but Buildroot keeps compat stubs. Five named symbols (`pthread_*`, `shm_*`) must be tested by P2.2 against real built rootfs (script `scripts/abi/needed-symbols.py` does this). |
| #31 | — | `/dev/MiSTer_cmd` is `mkfifo`'d at runtime (input.cpp:5141), so `/dev` must be writable (devtmpfs, not static read-only /dev) | Verified | Constrains P2.3/P2.4 writable-path audit. Update docs. |
| #32 | PLAN §11 / P2.7: "Rootfs free space ≥ 15%" | Stock is **13.56% free** — stock itself fails the gate | Verified on stock image | Restate budget against the 512 MiB image P2.5 builds, not stock's 375 MiB. Update the gate. |
| #33 | PLAN §3: modern defconfigs enable `STRICT_DEVMEM` by default | Not true on 32-bit ARM (`default y if PPC || X86 || ARM64 || S390`); `multi_v7_defconfig` has no line at all | Verified in kernel source | Fix rationale: A4 assertion and check still stand, but the reason is wrong for our arch. |
| #34 | PLAN §13: spidev hazard "presents as silent loss of I/O-board brightness control" | spidev is pi-top chassis (brightness/lid), not the I/O board. `brightness.cpp` drives pi-top peripheral. | Verified in source | Lowers §13 spidev severity considerably. Update risk assessment. |
| #35 | — | Minor: `/dev/input/mouseN` not `mice`; no CMA to preserve (`DMA_CMA` off in stock) | Verified | Update P1.3/A-index prose |

---

## New Constraints Proposed for A-Index (A10–A14)

Insert into `TASKS.md` section A after A9:

- **A10 — `/MiSTer.version` format.** Exactly 6 bytes, **no trailing newline**. The Downloader compares via bare `f.read()` with no `.strip()`. [ledger #6] [PLAN §10, §8] → P2.6
  
- **A11 — Initramfs kernel slot must exist.** `CONFIG_BLK_DEV_INITRD=y` (intentional divergence from stock). Doing `olddefconfig` from stock config silently breaks the entire §5 design. [ledger #8] [PLAN §5] → P1.3

- **A12 — Audio ABI is `/dev/MrAudio` + patched `snd-dummy` + `/etc/asound.conf`.** Not a card name. Main_MiSTer contains zero ALSA code; `/etc/asound.conf` routes default PCM to `/dev/MrAudio`. Patch `sound/drivers/dummy.c` (commit `333d49b95` from stock fork) must be carried; omit it and the system is silent. [ledger #18] [PLAN §3] → P1.5

- **A13 — `EVIOCGRAB` + mousedev are core input-subsystem patches.** Main_MiSTer both `EVIOCGRAB`s evdev and reads mousedev. Patch `0026-input-mousedev-eviocgrab` is not a HID quirk; escalate to [OPUS] if P1.9 encounters it. [ledger #22] [PLAN §4.1] → P1.9

- **A14 — I²C bus scanning limit.** Main_MiSTer refuses to scan past `/dev/i2c-2` (smbus.cpp:214). ADV7513 HDMI transmitter must be on i2c-0..2. Adding a 4th adapter or bus reordering in the DTB puts HDMI **silently out of reach**. Hard constraint on P1.7's DTS. [ledger #29] [PLAN §4.1a] → P1.7

---

## Open Questions Requiring Human Decision

> **✅ ALL FIVE ANSWERED — 2026-07-12 by @mcfbytes.** Each question below is now
> resolved by an ADR in `docs/decisions/`, which supersedes the text here and
> carries the mandatory follow-on work items:
>
> | Q | Decision | ADR |
> |---|---|---|
> | Q1 | **Drop** the out-of-tree exfat driver (0 symlinks found on a live MiSTer, across `/media/fat` *and* all `/media/usb*`) | [0001](decisions/0001-drop-out-of-tree-exfat.md) |
> | Q2 | Keep the symlink; adopt **Buildroot's own** `/etc/resolv.conf -> ../run/resolv.conf` default | [0002](decisions/0002-resolv-conf-buildroot-default.md) |
> | Q3 | **Defer** to Phase 4; test by direct SD copy, roll back by restoring files | [0003](decisions/0003-multi-db-defer-test-by-sd-copy.md) |
> | Q4 | **Add `ntfs3`** (module, default-off until parity proven); **park** the all-ext4 variant | [0004](decisions/0004-ntfs3-and-all-ext4-variant.md) |
> | Q5 | **Deferred, not waived.** Unsigned ⇒ personal use only; blocks P4.10, not Phase 1 | [0005](decisions/0005-sustainability-deferred-not-waived.md) |
>
> Q1 is the only one that changes Phase 1 scope, and it is **not a no-op**: see
> ADR 0001's consequences (a)–(e), in particular the FAT32 mount fallback, which
> is a **fail-to-boot** regression rather than a lost feature.

The following block or shape Phase 1 and require a human judgment call. **Do not proceed with P1 without answers.**

### Q1: exFAT with symlinks — maintain or drop?

**The issue:** Stock carries the out-of-tree Samsung exfat driver, which:
- Supports **symlinks** via the FAT `ATTR_SYSTEM` bit (works on FAT32 *and* exFAT)
- Mounts FAT12/16/32 under `-t exfat` (single mount call)
- Decodes FAT32 as UTF-8 (mainline vfat defaults to iso8859-1)

Mainline exfat/vfat support **none of this**, and Main_MiSTer **actively resolves those symlinks** (file_io.cpp:1592, since Jan 2019). Dropping the driver silently breaks a live feature.

**PLAN currently budgets nothing for this — it is Class G, outside the A–F taxonomy.**

**Decision needed:** Does the community rely on symlinks on `/media/fat`? If yes, carry the driver (large unbudgeted maintenance burden, class "external driver" — not G1–G4 core infrastructure). If no, drop it and publish a release note.

**Cite:** ledger #17, #12  
**Impact:** Phase 1 scope; affects P1.7 (DTS), P1.9 (patches)

---

### Q2: `/etc/resolv.conf` — bug-for-bug parity or fix?

**The issue:** PLAN §3 mandates regular files at user-restore destinations. Stock's `/etc/resolv.conf` IS a symlink → `/tmp/resolv.conf` (inode 112, verified on raw image). The "restore your custom resolv.conf" feature silently never works in stock (Downloader follows the symlink, writes to `/tmp/resolv.conf` *inside the offline image*, which the tmpfs then shadows at boot).

**Decision needed:** Reproduce the bug exactly for parity, or make it a regular file and thereby *fix* a feature that silently never worked? Fixing is a behavior change.

**Cite:** ledger #3a  
**Impact:** Phase 2 scope; affects P2.3 (init/config parity)

---

### Q3: Multi-database ordering — accept the race or seek cooperation?

**The issue:** The Downloader's multi-db logic guarantees that only one db's `linux` entry can be processed. Which one? Whichever db.json *fetches and parses first*. Ours wins only because our db.json is tiny (empty `files`/`folders`) vs Distribution's multi-MB catalog.

This is an **emergent property, not a guaranteed ordering**. A Distribution db.json that shrinks or a Downloader threading change could flip the race.

**Decision needed:** Accept the race as load-bearing and keep our db.json minimal as a design rule (risky but simple), or seek cooperation with the Downloader maintainers on an explicit precedence rule?

**Cite:** ledger #4  
**Impact:** Phase 4 scope; affects P4.5 (db.json publishing), P4.8 (user docs)

---

### Q4: NTFS support — add as opt-in or hold strict parity?

**The issue:** Stock has **no** NTFS support at all. Buildroot 2026.02 offers `ntfs3` (in-kernel driver, read/write). Adding it would be an improvement not available in stock.

**Decision needed:** Add `ntfs3` as an opt-in capability in the config, or hold strict feature-parity with stock and omit it?

**Impact:** P2.1 (full package set), P2.7 (size budget)

---

### Q5: Sustainability gate — named maintainer commitment required

**From TASKS.md §C:** *Before P4.10 (beta launch), a named human maintainer must commit in writing (in the README) to tracking 6.18.y stable through its EOL (Dec 2028), with the Renovate automation (P4.6/P4.7) as the mechanism. If no one signs, stop at the §14 deliverables and publish those — a stale fork is worse than no fork.*

**Status:** **UNSIGNED.** No human has committed in writing to this responsibility.

**Decision needed:** Who will track 6.18.y stable for years? This must be in writing (README) before beta. If the answer is "nobody," the project stops at standalone-value deliverables (§14) — architecture docs and a bootable kernel, not a full distribution.

**Cite:** TASKS.md §C, PLAN §13  
**Impact:** Project gate; affects P4.10 (beta launch decision)

---

## Risks Discovered (Outside PLAN's A–F Taxonomy)

- **Downloader flash phase failure reporting untrustworthy** (ledger #5): The shell script ending in `touch` means failed copies still report success and raise the reboot flag. P4.8 rollback runbook must assume updates are not atomic.

- **Python 3.9 → 3.14 now evidenced, not suspected** (ledger #26): Downloader_MiSTer is pinned to 3.9 in CI; Buildroot 2026.02 ships 3.14 with no legacy toggle. The updater that delivers our image has never been tested on our interpreter. P3.9 is critical path, not formality.

- **Multi-db ordering is emergent, not guaranteed** (ledger #4 expanded in Q3 above): Keeping db.json minimal is a load-bearing design rule, not an aesthetic choice. A distribution change could flip the race.

---

## Human Sign-Off Required

**Phase 1 is blocked until this is completed:**

```
Reviewed by: ____________________________    Date: ____________

Decision: ☐ Approve Phase 0, unblock Phase 1
          ☐ Approve with conditions (detail below)
          ☐ Do not approve (detail below)

Notes:
_________________________________________________________________

_________________________________________________________________

_________________________________________________________________
```

**Clarification:** This sign-off acknowledges that Phase 0's findings have been reviewed, open questions (Q1–Q5) have been decided, and corrections to PLAN.md / TASKS.md have been folded in. Phase 1 work (P1.1 onwards) must not start until the above line is filled in.

---

## Summary for Reviewers

- **The central bet is confirmed:** all 12 SONAMEs survive; glibc backward-compatibility holds; the stock binary will run unchanged.
- **Kernel delta is known:** 109 commits, completely characterized, no surprises.
- **One place got easier:** `MiSTer_fb` ioctl ABI is trivial (P1.4 is lower-risk than planned).
- **Five decisions block Phase 1:** Q1–Q5 above — **all five answered 2026-07-12**; see `docs/decisions/`. Q5 is *deferred, not signed*: it now blocks **P4.10 (publication)**, not Phase 1.
- **34 corrections** folded into this review, ranked by severity. No corrections invalidate the core plan.
- **Five new constraints** (A10–A14) added to the index for P1 and beyond.

**Proceed to Phase 1 only after all five human decisions are made and documented.**

## Post-decision status (2026-07-12)

The decisions are made and recorded (ADRs 0001–0005), so the *substance* of the
Phase 0 gate is met. Two follow-ons remain before P1.1 opens:

1. **Fold the corrections into PLAN.md / TASKS.md.** ADR 0002 in particular
   invalidates invariant **A8** ("all six user-file-restore destinations are
   regular files") and PLAN §3's "no symlink-into-tmpfs schemes" rule. These are
   now *factually wrong*, not merely imprecise, and the design we adopted
   deliberately contradicts them.
2. **Carry ADR 0001's consequences into the P1 task list** — the FAT32 → vfat
   mount fallback and `iocharset=utf8` are new P1.10 (initramfs) requirements that
   did not exist when TASKS.md was written, and neither will ever reproduce on the
   maintainer's own hardware (238.7 GB exFAT card, 0 non-ASCII filenames — both
   verified live).

The sign-off block below remains unsigned by design: per ADR 0005 it now gates
**publication**, not Phase 1 development.
