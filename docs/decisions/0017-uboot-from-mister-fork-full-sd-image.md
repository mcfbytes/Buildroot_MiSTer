# ADR 0017 — Phase 5 builds U-Boot from the MiSTer fork (submodule pin) and adds a full SD-card image; the mainline port is abandoned

**Status:** Accepted (2026-07-13) — decided by @mcfbytes
**Impact:** PLAN §2 (non-goals), §6 (repo layout), §8 (Phase 5 path), §9 (artifacts),
§12 (phase table), §13 (risks); TASKS Phase 5 (P5.1–P5.3 replaced by P5.1–P5.4);
`docs/boot-chain.md` §3.3 / N4 annotations. **No effect on Phases 1–4:** the default
release channel continues to ship the stock `uboot.img` byte-identical (P4.4), and
nothing this ADR introduces enters `release_*.7z` or the db.json channel.
**Supersedes:** PLAN §8's original "Phase 5 path" (mainline U-Boot port) and the former
TASKS P5.1–P5.3.

## The problem

Phase 5 as originally written ported MiSTer's boot behaviour to mainline U-Boot:
`socfpga_de10_nano_defconfig` plus re-implementations of everything the fork added —
`u-boot.txt` env-from-FAT (`env import -t`), the `fpgaload`/`fpgacheck` FPGA preload,
the MiSTer-only `mt` command (`docs/boot-chain.md` §3.3), the warm-reboot mailbox
handshake, and the pi-top GPIO quirk. Every one of those re-implementations is new code
in the single highest-blast-radius component of the system — a bad SPL presents as a
bricked board — and each must then be re-verified against a contract whose reference
implementation already exists, is public, and has been running on every shipped MiSTer
for years. That is reinventing a wheel, in the one place where a wobble bricks hardware.

Separately, the project has no from-scratch install story: we ship `linux.img` /
`zImage_dtb` through the Downloader onto an *already installed* card. A fresh card
still requires mr-fusion or the Windows SD installer.

## Decision

1. **Do not port to mainline U-Boot.** Build the proven fork —
   [`MiSTer-devel/u-boot_MiSTer`](https://github.com/MiSTer-devel/u-boot_MiSTer)
   (U-Boot 2017.03) — from source instead.

2. **Pin it as a git submodule** at `u-boot/`, commit
   `8dcc3484aac6f07314538e82530d446083085e12`. That commit is simultaneously
   (a) the `MiSTer` branch HEAD (verified 2026-07-13 via `git ls-remote`; the branch
   has not moved since 2021-11-12), and (b) **the exact commit the shipped `uboot.img`
   was proven to be built from** (`docs/boot-chain.md` §3.1 — the malformed
   env-entry-15 fingerprint). A submodule is a gitlink pointer, not a binary, so
   standing rule 1 ("no binaries in git") holds; and it records the pin in *our* tree,
   so the full-image build stays reproducible even if the upstream branch moves or the
   repo disappears. **The submodule is added in P5.1, not before** — there is no
   reason to make every clone and CI checkout fetch a U-Boot tree during Phases 1–4.
   (`shallow = true` in `.gitmodules` to keep even that fetch small.)

3. **Validate by behavioural parity, not byte identity.** A byte-identical rebuild is
   impossible (`docs/boot-chain.md` §3.2: compiled-in non-UTC timestamp, exact Arm GNU
   10.2-2020.11 toolchain). The built `uboot.img` must instead match stock on: the
   4×64 KiB SPL + uImage layout and offsets, socfpga SPL header validation, uImage
   header fields, the **default-environment blob** (all 20 entries of boot-chain §3.1,
   including the malformed entry-15 fingerprint), and presence of `mt`. Every
   remaining diff (timestamps, toolchain codegen) is enumerated and individually
   explained in `docs/verification/uboot-from-source.md`; an unexplained delta is a
   failure (P5.2).

4. **Add a full SD-card image deliverable** (`sdcard.img`, genimage post-image): MBR;
   p1 = FAT32 data partition; p2 = type `0xA2` with `uboot.img` raw at its start (the
   SPL contract, boot-chain §2.1). **p1's payload parity target is "a card as
   [mr-fusion](https://github.com/MiSTer-devel/mr-fusion) leaves it, plus
   Update_All":** the P0.6 `files/linux/` payload, `menu.rbf` + the stock `MiSTer`
   binary + the standard folder tree, mr-fusion's base `Scripts/` set (Downloader
   script, WiFi setup script), and a recent
   [`Scripts/update_all.sh`](https://github.com/theypsilon/Update_All_MiSTer) — a
   single self-updating file that drives the Downloader, so it adds no further
   on-card dependencies. All payload files are fetched at build time, pinned by
   commit/release + hash, never committed. The image must reproduce mr-fusion's
   per-board `ethaddr` provisioning (first-boot write of `linux/u-boot.txt` with a
   unique locally-administered MAC; the compiled-in fallback is the shared
   `02:03:04:05:06:07`, boot-chain §3.1 entry 14). Published as a separate release
   asset (`sdcard.img.xz`), never in `release_*.7z`, never referenced by db.json.

5. **The default channel is untouched, and the SD image defaults to the stock blob.**
   P4.4 keeps shipping the stock `uboot.img` byte-identical, fetched by hash.
   `sdcard.img` embeds that same stock blob by default; the P5.1 from-source build
   goes in only behind an explicit build flag, after the P5.4 hardware matrix and a
   drilled recovery procedure — change one variable at a time.

## Alternatives considered

- **Mainline U-Boot port (the old plan).** Strictly more new code in the
  brick-the-board component; must re-implement behaviours the fork already has (`mt`
  and the mailbox handshake are not upstream and never will be). The real cost of
  choosing the fork instead: U-Boot 2017.03 forever forgoes upstream fixes. Accepted,
  because the exposure is a boot-once code path with no persistent attack surface —
  `updateboot` wipes the saved env on every update (boot-chain §5b), the effective env
  is always defaults + `u-boot.txt`, and stock has shipped this exact binary for
  years. If a mainline port ever becomes worthwhile, this ADR does not preclude it —
  it just stops it from being the *first* step.
- **`BR2_TARGET_UBOOT_CUSTOM_GIT` pointing at GitHub.** Pins the same commit, but the
  pin lives only in a Buildroot config string and the source stays outside our tree —
  a deleted or force-pushed upstream breaks the build with no local recourse. The
  submodule keeps GitHub as the fetch origin *and* records the pin as a gitlink,
  which Renovate can manage (git-submodules datasource) so any future drift is a
  visible PR.
- **Vendoring the source tree.** Same pin, but imports ~60 MB of third-party history
  into the repo and pollutes patch provenance. The submodule achieves the pin without
  the import.

## Consequences

- TASKS P5.1–P5.3 are replaced by P5.1–P5.4 (submodule + build; behavioural-parity
  validation; `sdcard.img`; hardware matrix + recovery drill).
- `docs/boot-chain.md` §3.3's "Phase 5 blocker" (the `mt` command) dissolves — the
  fork ships it. §3.3 and constraint N4 are annotated, not rewritten: they remain the
  record of why the mainline port was the more expensive path.
- Buildroot wiring is `UBOOT_OVERRIDE_SRCDIR` → the submodule (via
  `BR2_PACKAGE_OVERRIDE_FILE`), since Buildroot has no "custom local directory"
  source option for U-Boot (2026.02: `CUSTOM_VERSION`/`CUSTOM_TARBALL`/`CUSTOM_GIT`
  only). Fallback: a `CUSTOM_TARBALL` generated from the submodule.
- New risk (PLAN §13): a 2017.03 tree may not build under a 2026 toolchain. Contained:
  build fixes only in `uboot-patches/` with provenance headers, never behaviour
  changes; worst case, pin the Arm GNU 10.2-2020.11 toolchain stock used.
- The full-SD-image path owns mr-fusion's install-time responsibilities, most
  importantly per-board `ethaddr` provisioning at first boot.
- CI checkouts need `submodules: true` from P5.1 onward.
