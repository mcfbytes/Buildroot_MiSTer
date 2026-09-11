# Reproducing the stock-style kernel tree from this repo's pins

**Purpose.** `MiSTer-devel/Linux-Kernel_MiSTer` is a *materialized* git tree: a pristine
kernel.org tarball as one squashed commit, MiSTer's changes as commits on top. This repo keeps
the same kernel as `{pinned tarball + hash}` plus an ordered patch series, and
`scripts/export-kernel-tree.sh` renders one form into the other. This document is about making
that rendered tree something the fork's maintainer can **build with his own process and test**,
from **our** pin (6.18.50 today, twelve stable releases past his 6.18.38 base), so that what we
contribute back is testable by him rather than only by us. It records what we can and cannot
know about what he wants, how the export now matches his conventions, and how to prove the
exported tree is the kernel Buildroot builds.

Companion files: `scripts/export-kernel-tree.sh` (the renderer; its header comment is the
design doc), `scripts/check-export-tree.sh` (the reproducibility proof, added 2026-09-11),
`board/mister/de10nano/linux-patches-upstream/README.md` (the second series), and the
generated `EXPORT.md` inside every exported tree (the build recipes, kept there because that is
where a reader of the tree looks).

---

## 1. What we know about upstream's process — and the one thing we could not read

### 1.1 PR #75, and what happened to it

On 2026-07-16 we exported our series onto the vanilla `v6.18.38` base commit the maintainer had
just created (`d9ac12a691`, parented on the `v5.15.1` spine point `aba1ef4c1`) and opened
`Linux-Kernel_MiSTer` PR #75: 38 commits — 31 carried patches, the upstream-only `loop=` patch,
`MiSTer_defconfig`, three vendored out-of-tree drivers (xone, rtl8812au, rtl8821au — the latter
two have since moved to mainline `rtw88` in our image), a `build-mister-modules.sh`, and
`EXPORT.md`. Between 2026-07-21 and 07-23 the maintainer instead forward-ported the series
himself (57 commits, `MiSTer-v6.18` @ `e8f065dbf8`, his own subjects and decomposition, the
fork's original author dates preserved where he cherry-picked) and the PR was closed. Stock
Release 20260907 was built from that branch (`fork-sync-2026-09/PLAN.md` §1.2).

**The review comments on PR #75 are not readable from the environment this document was
written in**: GitHub's API and web pages are blocked for repositories outside the session, and
the fork cannot be attached (cross-owner). Everything in §1.2 is therefore inferred from what
his branch and his release *do*, not from what he *said*. **Owner action:** open
https://github.com/MiSTer-devel/Linux-Kernel_MiSTer/pull/75, read the thread, and check each row
of §1.2 against it; anything he asked for that is not listed there is a gap in this document,
not in his process. In particular, confirm whether he wants (a) whole-tree PRs at all or
per-feature PRs against `MiSTer-v6.18`, (b) the DTS as a separate file (§1.2 row 3) or edits to
vanilla's, (c) the defconfig in full or minimized form, (d) vendored out-of-tree drivers in the
tree, and (e) anything about the `loop=` boot patch.

### 1.2 His conventions, observed — and how the export now matches them

Every row is measured from `MiSTer-v6.18` @ `c129b0fac` (2026-09-11) and from the Release
20260907 artifacts, not assumed.

| # | His convention (evidence) | PR #75 export | Export since 2026-09-11 |
|---|---|---|---|
| 1 | **Spine of pristine tarball commits**: `v6.18.38` = `d9ac12a691`, parent `aba1ef4c1` (`v5.15.1`); MiSTer commits hang off the spine point | replayed *onto* `d9ac12a691` (`--onto`), because we were on the same version | our pin is 6.18.50, so the export creates a new spine point: `--parent-repo <fork> --parent d9ac12a691…` makes a `v6.18.50` base commit whose diff against his base is **pure stable 6.18.38 → 6.18.50**, then replays our series. Same shape as his `v5.15.1 → v6.18.38` step |
| 2 | **One commit per feature**, original authorship where a contributor wrote it (53 of the **67** commits between `d9ac12a691` and `c129b0fac` are his; the rest carry Nolan Nicholson ×2, Kasper Olesen ×2, and one each from Takiiiiiiii, Stanislav Ponomarev, Porkchop Express, Nigel Shearman, Michael Huang, Martin Donlon, Julian Seitz, James McCarthy, Aurora, Alexey Melnikov — recounted by the Wave-4 audit 2026-09-11, which found the denominator stale at 62) | one commit per carried patch, original `From:` preserved by `git am` | unchanged; `scripts/lint-kernel-patches.sh` enforces `git am`-ability of every header |
| 3 | **DTS as his own file** `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts` (underscore), listed in that `Makefile`; vanilla's `socfpga_cyclone5_de10nano.dts` left untouched. The shipped 20260907 DTB is that file (its `compatible` is the pre-#85 pair `altr,socfpga-cyclone5`, `altr,socfpga`) | our `0004` patches **vanilla's** file, so `make …/socfpga_cyclone5_de10_nano.dtb` — his build target — **failed** in our tree | the export adds a generated, export-only commit providing `socfpga_cyclone5_de10_nano.dts` as a one-line `#include` of the patched vanilla file plus the `Makefile` entry. His target builds a DTB byte-identical to ours; Buildroot never sees the alias. `0004` still patches vanilla's file, which is where the change belongs for mainline |
| 4 | **Kernel version string `6.18.38-MiSTer`** (`lib/modules/6.18.38-MiSTer/` in `modules.tar.gz`) with `CONFIG_LOCALVERSION=""` in the shipped config — i.e. he passes `LOCALVERSION=-MiSTer` at build time | `EXPORT.md` documented `LOCALVERSION=` (empty), to match Buildroot's vermagic `6.18.38` | `EXPORT.md` now documents both: the **image-compatible** build (empty, modules interchangeable with our image) and the **stock-process** build (`-MiSTer`, producing the `zImage_dtb` + `modules.tar.gz` that `Linux_Image_creator_MiSTer/create_img.sh` consumes). They differ only in vermagic |
| 5 | **`arch/arm/configs/MiSTer_defconfig` in full resolved form** (header `Automatically generated file`, `CONFIG_CC_VERSION_TEXT` of his `arm-none-linux-gnueabihf-gcc 10.2`) | minimized form (our `linux.config` verbatim) | still minimized, deliberately — a full form bakes in the generating toolchain and ~4,000 default lines; `make ARCH=arm MiSTer_defconfig` resolves to the same configuration for his toolchain. `EXPORT.md` says how to produce the full form in one command if he prefers it |
| 6 | **Out-of-tree drivers vendored in-tree** (`drivers/hid/xone`; since 2026-09-11 also `drivers/net/wireless/aic8800`) | xone, rtl8812au, rtl8821au vendored as one commit each + `build-mister-modules.sh` | every kernel-module package the image enables is vendored the same way — **xone and rtl8852cu** today (the two Realtek 11ac forks were retired for mainline `rtw88` in v10). AIC8800 is deliberately absent even though the image now ships it from `package/aic8800` (D2 reversed 2026-09-10): the fork already vendors the same SDK snapshot at the same path, so exporting ours would collide with his copy — `MODULE_EXPORT_SKIP` in the script names it and the run announces the skip |
| 7 | **No `EXPORT.md`, no build script** in his tree | both present | both present; they are the last two commits so the "kernel" part of the log is unaffected, and `EXPORT.md`'s `git diff` one-liners show exactly which commits are ours |
| 8 | Artifact layout: `Linux_Image_creator_MiSTer/create_img.sh` untars `modules.tar.gz` with `--strip-components=2` into `/lib` (so every member must begin `./lib/`, as stock's does); `zImage_dtb` is not touched by that script at all — it is the file U-Boot loads from the card's FAT `linux/` directory, shipped beside the tarballs | not documented | the stock-process recipe in `EXPORT.md` produces both files in exactly that layout, including the leading `./` that `--strip-components=2` depends on (verified by a tar round-trip) |

Rows 3, 4 and 8 are the ones that decide whether **he can build our kernel with his own
commands and drop it into his image creator**. Before 2026-09-11 the answer was no (row 3
alone broke his `make` target). Now it is yes, modulo the review-thread items in §1.1.

### 1.3 Where the two trees still differ on purpose

Recorded so nobody "fixes" them backwards (details and evidence in
`docs/kernel-recon/fork-sync-2026-07.md` §3 and `fork-sync-2026-09/STATUS.md`):

- Our `0039`–`0042` (N64/Genesis button maps, IMU name suffix, LED classdev names, lightbar
  names) restore **stock 5.15** behaviour that his 6.18 port does not carry. (`0038`, the NSO
  Genesis Bluetooth PID normalization, he *does* have — measured in Wave 5, correcting the
  Wave 4 tree-diff's first reading.) Ready-to-send patches for the four, plus the `BTN_Z`
  scoping and the framebuffer `memremap()` check, are prepared under
  `docs/kernel-recon/fork-sync-2026-09/upstream-candidates/` — **prepared, not sent**.
- `BTN_Z` is DualSense-only in ours (as in stock 5.15); his port declares it for DualShock 4 too.
- His `spidev` `altspi` compatible and `vt.h` `MAX_NR_CONSOLES 63→9` are dropped in ours.
- His cpufreq port (#85) is not adopted; we keep `0003` (decision D1) and carry only its OCRAM
  reservation. His AIC8800 driver is not exported: the image builds the same SDK snapshot
  out-of-tree from `package/aic8800` (D2 reversed 2026-09-10), and his tree already has it.
- His tree keeps a second, separate DTS; ours patches vanilla's and provides his filename as an
  alias (row 3).

### 1.4 Deficiencies observed in `MiSTer-devel/Linux-Kernel_MiSTer` — what to raise upstream

Measured against `MiSTer-v6.18` @ `c129b0fac` and Release 20260907 during the 2026-09
increment. "Prepared" means a ready-to-send patch or comment exists under
`docs/kernel-recon/fork-sync-2026-09/upstream-candidates/`; nothing has been sent (owner decision).

| # | Deficiency | Evidence | Status upstream | Our artefact / suggested action |
|---|---|---|---|---|
| 1 | **Shipped release regressions.** Release 20260907 (= `aec7dc3aa`) ships with `mmap(/dev/fb0)` returning `-ENODEV` (Console Mode / SDL fbcon cannot start), no driver for RTL8811AU/8821AU (`CONFIG_RTW88_8821AU` off), and no cpufreq/overclock driver at all | shipped config + module list (`fork-sync-2026-09/evidence/`) | all three fixed on the branch after the release (#83, #81, #85) but **not yet in any shipped release** | nothing to submit; worth asking for a point release. Users on stock are affected until then |
| 2 | `MiSTer_fb.c` tests a `memremap()` result with `IS_ERR()`; `memremap()` returns NULL, so a failed mapping falls through to an oops with a stale `devm_ioremap_resource` message | `tree-diff-2026-09.md` F1; our `0001` has the correct check (README bug B2) | open | **prepared: `07-fbdev-mister-fb-memremap-null-check.patch`** |
| 3 | **PR #92 (open) regresses USB controllers that do not answer the first handshake**: the moved baudrate block is gated on `using_usb && !8bitdo` instead of on the first handshake having succeeded, so vanilla's "assume BLE pro controller, run at default baud" fallback becomes a fatal second handshake | code review of our `0049` (2026-09-11); vanilla `joycon_init()` quoted in the note | open PR | **prepared: `08-hid-nintendo-pr92-handshake-fallback.NOTE.md`** (review comment + one-variable fix); our `0049` carries the corrected form |
| 4 | Stock-5.15 controller behaviour the 6.18 port lost, all Main_MiSTer-coupled: NSO N64/Genesis button maps differ from stock (SDL `gamecontrollerdb` rows shift), IMU input device not named `" IMU"` (Main_MiSTer opens it as a phantom pad), LED classdevs not named `player1..4`/`home`, lightbar LEDs not named `:red/:green/:blue` | records `b00a72159`, `45283785a`, `60821059c`, `f84543926`; `tree-diff-2026-09.md` §b | open | **prepared: patches `02`–`05`** |
| 5 | `BTN_Z` declared in the shared PlayStation button table, so DualShock 4 gains a button stock 5.15 never exposed on it | `fork-sync-2026-07.md` §3 | open | **prepared: `06-hid-playstation-dualsense-btn-z-scoping.patch`** (behaviour change for DS4 users stated in the draft) |
| 6 | **AIC8800 driver vendored without a licence**: 139 files, 85 with a bare copyright line and no grant, 51 with nothing, 2 Apache-2.0 (`aic_br_ext.{c,h}`, GPLv2-incompatible), no `LICENSE`/`README`; needs ~60 firmware blobs that no shipped `firmware.tar.gz` contains; a `wext` shim; SDK snapshot `rwnx v6.4.3.0 - 1a4b0054d2M` | `memo-Q9-aic8800.md` §1.3, §2 | landed 2026-09-11 | not a patch: raise as an issue — name the upstream repo/commit, add its licence text, ship the firmware (or say where it comes from), consider out-of-tree packaging |
| 7 | cpufreq port (#85) open items by its own author: 1200 MHz long-duration untested, MiSTer Pi/SuperStation untested, "OSD movement during scripts" unexplained, boost-off harness not re-run; and its OCRAM `flags-sram` rationale is wrong (Main_MiSTer's flags are in DDR at `0x1FFFF000`) | `memo-Q4-cpufreq.md` §2, §6 | landed | none to submit; worth a note that the reservation is hygiene, not a Main_MiSTer requirement |
| 8 | Release 20260907's `firmware.tar.gz` ships modules without their firmware for RTL8814AU, RTL8822CU and RTL8723DU (`rtw88_*` modules present, `rtw8814a_fw.bin` / `rtw8822c_fw.bin` / `rtw8723d_fw.bin` absent) | Wave 4 audit (`audit-findings.md`) | shipped | a `Linux_Image_creator_MiSTer` issue, not a kernel patch |
| 9 | No tags or releases on the kernel repository; the shipped kernel is identifiable only by fingerprinting its config against branch commits (this repo had to diff the IKCONFIG against every candidate) | `fork-sync-2026-09/PLAN.md` §1.2 | process | suggest tagging the commit each release is built from |
| 10 | Pinned at 6.18.38 with no `.y` stable updates — the 5.15.1 pattern again (12 releases behind at time of writing) | `Makefile` `SUBLEVEL = 38` | process | suggest tracking `linux-6.18.y`; our export tree offers a ready 6.18.50 base (§2) |
| 11 | Non-upstreamable hacks carried in-tree: `spidev` `altspi` compatible (a DTS retarget to `rohm,dh2228fv` does the same with no driver change), `vt.h` `MAX_NR_CONSOLES 63→9` (no consumer; Main_MiSTer uses VT 1–2 only) | records `246984fce`, `b2a04cbfd` | landed | low value; mention if a cleanup pass is ever welcome |
| 12 | exFAT symlink support is a parallel implementation; ours reuses vanilla's `page_symlink()`/`page_get_link()` infrastructure with the same on-disk format | `0031` header; tree-diff exfat cluster (behaviourally identical) | landed | weaker candidate — offer only if he wants the smaller diff |

---

## 2. Regenerating the tree for the current pin

```bash
# once: a clone of the fork to hang the branch on (never modified by the export)
git clone https://github.com/MiSTer-devel/Linux-Kernel_MiSTer work/Linux-Kernel_MiSTer

# render: base commit = pristine linux-<pin> from kernel.org (hash-verified against
# board/mister/de10nano/patches/linux/linux.hash), parented on the fork's 6.18 spine point
scripts/export-kernel-tree.sh \
    --output work/export \
    --parent-repo work/Linux-Kernel_MiSTer \
    --parent d9ac12a691ead295c8bc6438754767b94c0f26a2 \
    --fork-sync "$(awk '$1=="MiSTer-v6.18"{print $2}' docs/kernel-recon/fork-sync.conf)"
```

The result is a branch `MiSTer-v6.18` and a tag `mister-<pin>` in `work/export`, with the
layout `EXPORT.md` describes. Re-running with unchanged inputs yields identical SHAs (the
script's determinism promise; verified in the dry run below). To publish, fetch that branch
into a fork you control and push from there — the script never touches a remote, and
**no PR is opened by anything in this repo**.

The `--parent` value is the newest pristine spine point in the fork. When the fork gains a
newer one (say a `v7.2.x` base for a future stock kernel), move it; the export refuses to
replay onto a commit that is not pristine or is a different version than the pin.

## 3. Proving the exported tree is the kernel we build

`scripts/check-export-tree.sh` is the reproducibility check:

```bash
scripts/check-export-tree.sh --export work/export \
    --build-dir output/build/linux-<pin> \
    --cross-compile "$PWD/output/host/bin/arm-buildroot-linux-gnueabihf-"
```

It verifies, and fails closed on:

1. the export is what it claims (tag, `EXPORT.md`, commit layout, version equal to the pin);
2. the tree at the **carried tip** — the commit before the upstream-only series — is
   **byte-identical** to Buildroot's patched kernel source (`output/build/linux-<pin>`), build
   outputs excluded. This is the statement "the exported tree *is* the shipped kernel";
3. `make ARCH=arm MiSTer_defconfig` in the export resolves to Buildroot's `.config`
   (compiler-identity symbols reported separately when the compilers differ);
4. unless `--no-build`: `zImage`, vanilla-named and alias-named DTBs build, and the two DTBs
   are byte-identical.

`--llvm` substitutes `LLVM=1` for a GNU cross prefix (the environment this was first run in
has clang but no GNU ARM toolchain). Wiring this into `build.yml` after the kernel leg, with
`--no-build` (the kernel is already built there), is the intended CI use; it is not wired yet.

## 4. Dry run, 2026-09-11 — why it is a stand-in

The first end-to-end run (results in §5) was performed against
**6.18.49**, not the 6.18.50 pin: the kernel.org tarball and the stable tag were unreachable
from the session (`docs/kernel-recon/fork-sync-2026-09/env.md`), so a synthetic tarball was
made with `git archive` of the 6.18.49 release commit and a scratch copy of the repo was
pinned to it. The mechanics are identical; the first run against the real 6.18.50 tarball
happens wherever `dl/linux/linux-6.18.50.tar.xz` is present (any machine that has built the
image, or CI).

## 5. Dry-run results (2026-09-11, 6.18.49 stand-in, clang/LLVM, no network)

Two things had to be substituted and are stated so nobody mistakes this for the real run:
the tarball was `git archive` of the 6.18.49 release commit (same tree content as kernel.org's,
different file mtimes — so the base commit's date, and hence its SHA, differ from what the real
tarball gives), and the two vendored driver tarballs (`xone`, `rtl8852cu-morrownr`) were
placeholders because GitHub downloads are blocked from the session — the vendoring path was
exercised, the driver contents were not.

| Step | Result |
|---|---|
| **Export script bug found and fixed** | It read `BR2_PACKAGE_*=y` from `configs/fragments/de10nano.fragment` only; the 2026-09 fragment split moved those lines to `de10nano-image.fragment`, so the script's own "zero kernel-module packages" guard would have **aborted every export since**. It now resolves the DE10 stack from `configs/fragments/stacks.mk` via `scripts/lib/config-stacks.sh` and reads all four fragments, last-wins |
| Export (`--parent d9ac12a691`, `--fork-sync c129b0fac`) | PASS, 48 commits: base `v6.18.49` → 40 carried → 1 upstream-only → defconfig → **DTS alias** → 2 vendored → build script → `EXPORT.md`; tag `mister-6.18.49` |
| Emulated Buildroot tree (tarball + `linux-patches/*.patch` at `-F0`) | 40/40 applied, offsets only (max +49), no fuzz |
| `check-export-tree.sh --build-dir … --llvm` | **PASS — 19 checks, 1 skipped**: 88,335 files byte-identical between the export's carried tip and the Buildroot-style tree; resolved configuration identical (3,744 symbols); `socfpga_cyclone5_de10_nano.dtb` (his name) and `socfpga_cyclone5_de10nano.dtb` (vanilla's) byte-identical, sha256 `199f14b1…3dae`, and equal to the build dir's DTB; `zImage` skipped only because the host lacks `lz4` for the final compression step (the tree compiled through `vmlinux` in an earlier full run) |
| Negative tests of the check | an edited file, an extra file, a deleted file and a permission change are each reported with the file list and FAIL |
| Determinism | two exports with identical inputs → identical tag commit (`2c530e74…`), all 50 `%H %s` lines equal |

**Not verified here, by construction:** the real 6.18.50 tarball and its signed hash; the real
driver sources; Buildroot's own `.config` (the check substituted `cp linux.config .config &&
make olddefconfig`, which is what Buildroot does); a `zImage` through `lz4`. All four are
covered the first time the two commands in §2–§3 run on a machine that has built the image.
Neither script is wired into CI yet (§3 says where it belongs).
