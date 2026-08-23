# DE25-Nano readiness ledger — every `de10nano` / `BR2_arm` / zImage site outside the board dir

**Status:** D1.1 complete 2026-08-21 — **docs only, no code changed**. This file is also the
home of **D1.2** (§5), which has no separate deliverable file of its own. Nothing here has
been applied: §6's diffs are *proposals for separate review*, not commits. Claims are tagged
**[V]** (a file was opened and the cited line read) / **[U]** (unverified, named as such).

**Cross-refs:** [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md) (the four
couplings, Decision 3's obligation), [`de25-nano-plan.md`](de25-nano-plan.md) §3 (the same
four, with what each needs), [`de25-nano-tasks.md`](de25-nano-tasks.md) §D1 (this task and its
accept criterion), [`de25-boot-chain.md`](de25-boot-chain.md) (D0.1's boot-flow research that
DP-2 depends on).

---

## 1. Why this document exists, and what it is *not*

A fresh grep for `de10nano|BR2_arm|zImage` outside `board/mister/de10nano/` and `docs/` hits
**55 files and 457 lines** (§7). Almost all of them are a **path** or a **name**. Exactly four
things in this repo are *semantically* ARM32/Cyclone-V — they encode a fact about the silicon
or the boot ROM that has no aarch64 analogue at all **[V** ADR 0027:42-46**]**:

| # | Coupling | Where it actually lives | Why it cannot be parameterized |
|---|---|---|---|
| (a) | `zImage_dtb` cat-concatenation contract | `scripts/check-zimage-dtb.sh`, `scripts/inventory/kernel_extract.py`, `board/mister/de10nano/post-image.sh` | U-Boot reads the DTB offset out of the ARM zImage header's declared-end field at `+0x2C` **[V** `check-zimage-dtb.sh:5-16`**]**; arm64 `Image` has no header field to read |
| (b) | 0xA2 BootROM SD partition layout | `board/mister/de10nano/genimage-sdcard.cfg:133`, `scripts/mk-sdcard.sh`, `scripts/check-sdcard.sh:92,203-212` | The Cyclone-V BootROM scans the MBR for `sys_ind == 0xA2` **[V** `genimage-sdcard.cfg:17-19`**]**; Agilex boots via SDM/FSBL from QSPI into a GSRD-shaped card |
| (c) | `^BR2_arm` / `^BR2_cortex` asserts | `.github/actions/buildroot-build/action.yml:190` **[V]**, `scripts/check-kernel-defconfig-sync.sh:83,129` **[V]** | Buildroot's arch symbols are mutually-exclusive Kconfig *choices*, not values a variable can carry |
| (d) | armv7-pinned `package/azcopy` | `package/azcopy/Config.in:64` (`depends on BR2_arm`) **[V]** | Gates a Go cross-build that only exists for 32-bit ARM |

Everything else — 51 of the 55 files — says `de10nano` because that is where the board's files
*live*, or says `zImage_dtb` because that is what today's only kernel artifact is *called*.
Those are cheap: a `BOARD=` variable, or a second sibling file, fixes them at the moment
someone touches them. **Collapsing the two classes together is the failure mode this ledger
exists to prevent** — it would either (i) invite someone to "generalize" the zImage header
parser, which is not generalizable, or (ii) inflate the DE25 port's apparent cost from four
real design decisions to fifty-five.

**Decision 3's obligation, restated:** we do not pre-build DE25 plumbing. We stop *deepening*
the four. Any newly written or substantially rewritten script/CI step that would hard-code
`de10nano`, `BR2_arm`, or zImage semantics takes a board parameter instead **[V** ADR
0027:74**]**.

---

## 2. The ledger — scripts

Severity: **semantic-blocker** = do not parameterize, a design decision is owed first;
**parameterize** = mechanical `BOARD=` substitution when next touched; **cosmetic** = a name
in prose, no action or a one-word reword.

| file:line | coupling | sev | when you touch this, do this instead |
|---|---|---|---|
| `scripts/check-zimage-dtb.sh:3,7-10,14-15,27,66-81` | The whole script asserts the U-Boot↔ARM-zImage contract: magic `0x016f2818` at `+0x24`, DTB offset read from `+0x2C` **[V]** | semantic-blocker | Leave it ARM-only forever and write a wholly new checker for whatever DP-2 picks — there is no offset to parameterize on aarch64. |
| `scripts/inventory/kernel_extract.py:3-22,41-95,135-150` (whole 180-line module) | Parses the same ARM zImage self-relocating header to carve `zImage_dtb` apart **[V]** | semantic-blocker | Write a separate `kernel_extract_fit.py` selected by board rather than adding an aarch64 branch to this parser. |
| `scripts/mk-sdcard.sh:29-63,107-131,190,316-541,711` | Builds the installer card around both (a) and (b): snapshots/relinks/restores `output/images/zImage_dtb`, then runs genimage on the 0xA2 `genimage-sdcard.cfg` **[V]** | semantic-blocker | Give DE25 its own card-assembly script against its own genimage config once DP-2 and the Agilex GSRD layout are pinned; do not thread an arch branch through this one. |
| `scripts/check-sdcard.sh:10-21,51,73,91-92,113,203-212` | Asserts MBR p1=FAT32-LBA / p2=type `0xA2` ≥1 MiB and that the 0xA2 head is the pinned `uboot.img` **[V]** | semantic-blocker | This is coupling (b) in assertion form — write a sibling checker for the Agilex layout instead of relaxing these constants. |
| `scripts/test-sdcard-install.sh:8-10,60,67,70,77-78,139-154` | QEMU install test builds and boots an ARM `zImage` end to end (`ARCH=arm`, `arm-buildroot-linux-gnueabihf-`, `multi_v7_defconfig`, `arch/arm/boot/zImage`) **[V]** | semantic-blocker | Write a dedicated aarch64 install-test script once DP-2 fixes the DE25 payload format; do not bolt an `if aarch64` branch onto this harness. |
| `scripts/test-initramfs.sh:46,60,67,83,90,94,174,191,217-221,275,365` | Same shape: `qemu-system-arm -M virt` + `multi_v7_defconfig` + `arch/arm/boot/zImage`, because QEMU has no Cyclone-V model **[V]** | semantic-blocker | Mirror this script for `qemu-system-aarch64 -M virt` as its own file (the cpio itself is arch-neutral **[V** plan §3 item 1**]**); *separately*, `:83`'s hardcoded `configs/mister_de10nano_defconfig` version read is a mechanical `BOARD` substitution. |
| `scripts/export-kernel-tree.sh:63,159-160,706-707,917-918,933-938,977,991,1025,1124-1126,1154-1155,1176,1184` | Every recipe it emits (header, `EXPORT.md`, `build-mister-modules.sh`, `README.md`) hardcodes `ARCH=arm`, `arm-linux-gnueabihf-`, and the `zImage` target **[V]** | semantic-blocker | Write a second export path for the Agilex kernel when D2 gates it — this script exports *the DE10's* patch series and `MiSTer_defconfig`, so an `ARCH=` flag would be a lie. |
| `scripts/check-kernel-defconfig-sync.sh:83,129` | Sentinel + family loops asserting `BR2_arm`/`BR2_cortex_a9`/`BR2_ARM_` **[V]** — ADR 0027 coupling (c) | semantic-blocker | Do not widen the sentinel set; adopt §5's per-board expected-symbol table so DE25 gets its own row rather than a loosened shared check. |
| `scripts/check-kernel-defconfig-sync.sh:61-62` | `MAIN_DEFCONFIG`/`KERNEL_DEFCONFIG` hardcode the two de10nano filenames **[V]** | parameterize | Take `BOARD` (env or `$1`, default `de10nano`) and compose both paths from it — see §6.1. |
| `scripts/check-linux-img.sh:8,14,41` | Pins the ext4 feature set/label/UUID against `configs/mister_de10nano_defconfig` by name **[V]** | parameterize | Read the pinned contract from `configs/mister_${BOARD}_defconfig`; the ext4 assertions themselves are arch-neutral and carry over. |
| `scripts/hash-sync-kernel.sh:12,53,134,196,223` | Reads the kernel version from `configs/mister_de10nano_defconfig` and writes `board/mister/de10nano/patches/linux/linux.hash` **[V]** | parameterize | Both paths are board-scoped data, not arch facts — compose them from `BOARD` when this script is next touched. |
| `scripts/lint-kernel-patches.sh:53,67` | `DEFCONFIG` hardcodes `configs/mister_de10nano_defconfig`; lints the series named in it **[V]** | parameterize | Same `BOARD` substitution; the provenance-header lint itself is board-agnostic and should lint every board's series. |
| `scripts/fetch-sdcard-payload.sh:8-12,53,361` | Comments describe overlaying our `linux.img`/`zImage_dtb`; `:361` reads `board/mister/de10nano/fat-payload` **[V]** | parameterize | `:361` is a `BOARD` path substitution; the `zImage_dtb` mentions are naming that follows whatever DP-2 names the DE25 payload. |
| `scripts/ci-tests.sh:80,110-113,202,932,1059-1095,1200-1221,1301-1360,1595,1763` | `$IMAGES/zImage_dtb` plus ~12 `board/mister/de10nano/...` reference paths in assertions and their failure messages **[V]** | parameterize | Compose the board dir once from `BOARD` at the top and use it throughout; every individual assertion here is arch-neutral. |
| `scripts/check-fork-sync.sh:8-9,115-116` | Names `linux-patches/` and `linux-patches-upstream/` under `board/mister/de10nano/` in code and in generated prose **[V]** | parameterize | Board-scope the two directory paths; the carried/upstream-only taxonomy is board-independent. |
| `scripts/verify-stock-payload.sh:474` | `must` list includes `files/linux/zImage_dtb` — the stock DE10 payload's own filename **[V]** | cosmetic | Leave it: this verifies *stock MiSTer's* published payload, which will never contain an aarch64 artifact. |
| `scripts/list-kernel-variants.sh:44` | Comment notes the variant probe looks for `output-main/images/zImage_dtb` **[V]** | cosmetic | Reword to the board's image name only if/when the variant registry itself grows a board axis. |
| `scripts/ci-lib.sh:37` | Comment explains a size helper's GPL reasoning by naming `zImage_dtb` **[V]** | cosmetic | No action; `ci_lib_sz` is a byte-counter with no format knowledge. |
| `scripts/test-timezone.sh:5,56` | `SRC` points at the dhcpcd hook under `board/mister/de10nano/rootfs-overlay/` **[V]** | parameterize | `BOARD` path substitution; the hook and its test are arch-neutral. |
| `scripts/test-installer-splash.sh:4,25` | `INIT` defaults to `board/mister/de10nano/installer-overlay/init` **[V]** | parameterize | Same substitution — note `:25` already accepts `$1`, so the default value is the only hardcode. |
| `scripts/test-initramfs/qemu-test-kernel.config:8` | Comment says this fragment is *not* `board/mister/de10nano/linux.config` and never will be **[V]** | cosmetic | No action; a DE25 QEMU harness brings its own fragment (see the `test-initramfs.sh` row). |
| `scripts/test-initramfs/marker-init.c:10` | Comment points at the real init it stands in for **[V]** | cosmetic | No action. |
| `scripts/inventory/gen-kernel-config-dts.sh:2,5,34,140,143` | Usage/prose take a `<zImage_dtb>` argument and document the extraction method **[V]** | cosmetic | Rename the argument to the payload's actual name if this is ever pointed at a DE25 artifact; the `dtc` half is format-agnostic. |
| `scripts/inventory/run-all.sh:2,13,31,73` | Optional 2nd argument named `zImage_dtb`, feeding item (f) **[V]** | cosmetic | Same reword-only note. |
| `scripts/inventory/README.md:12,20,27,53,65` | Documents that argument and the stock artifacts it reads **[V]** | cosmetic | Reword alongside the two scripts above. |
| `scripts/inventory/lz4_legacy.py:3,105` | Docstrings say "zImage"; the decoder itself handles the kernel-generic legacy LZ4 frame magic `0x184C2102` **[V]** | cosmetic | **Reuse this module as-is** for any DE25 payload compressed the same way — only the docstrings' `zImage` wording needs updating. |

## 3. The ledger — CI

| file:line | coupling | sev | when you touch this, do this instead |
|---|---|---|---|
| `.github/actions/buildroot-build/action.yml:190-195` | Toolchain-fingerprint sentinel requires `^BR2_arm` and `^BR2_cortex` or the build fails loud **[V]** — coupling (c) | semantic-blocker | Adopt §5's `BOARD_FINGERPRINT_SENTINELS` row lookup with a validated `board` input; never add a second arch string beside these, and never soften the assert to a warning. |
| `.github/actions/buildroot-build/action.yml:152,154` | `fp_defconfig` branches on `variant` only, and hardcodes `configs/mister_de10nano_defconfig` for `main` **[V]** | parameterize | The board and variant axes are orthogonal — resolve the defconfig from `BOARD` *and* `VARIANT` rather than adding a third literal filename. |
| `.github/actions/buildroot-build/action.yml:166` | `pd="board/mister/de10nano/patches/$d"` for the toolchain-patch hash **[V]** | parameterize | Board-scope the path; the deny-list filter at `:158`/`:181` stays global policy and must not be board-keyed. |
| `.github/actions/kernel-leg/action.yml:4,21,131,146-167,177,198` | Stages `output-$KERNEL/images/zImage_dtb` as `zImage_dtb-$KERNEL` and renders it into the job summary and the `bootimage=` instructions **[V]** | parameterize | The artifact *name* follows DP-2; take the image filename from a board-scoped variable so this shared action does not need a second copy. |
| `.github/actions/README.md:6` | Table row describes kernel-leg's staged artifact as `zImage_dtb + .config + modules tar` **[V]** | cosmetic | Reword when the action above is generalized. |
| `.github/workflows/build.yml:225,258,276,305` | Reads and uploads `output/images/zImage_dtb` and reports its size **[V]** | parameterize | Same: source the image filename from the board's config rather than a literal, when this step is next rewritten. |
| `.github/workflows/release.yml:184,232,285,357-367,453-454,552,665,796-832,856,869,898,921` | The whole release surface — asset names, `SHA256SUMS`, attestation globs, the variant round-trip check, and `make mister_de10nano_defconfig` at `:665` **[V]** | parameterize | ADR 0027 Decision 4 reserves a separate `de25-YYYYMMDD` tag namespace, so a DE25 release is a *second* set of assets, not a rename — keep this job DE10's and give the board axis its own asset naming when D2 gates it. |
| `.github/workflows/lint.yml:17,37-61,165-199,221` | 20+ `board/mister/de10nano/...` shellcheck targets and path filters **[V]** | parameterize | Glob `board/mister/*/...` (or enumerate boards) rather than adding a duplicated second block — this is the highest-value pure-path fix in the repo. |
| `.github/workflows/reproducibility.yml:90,156` | Hashes `linux.img zImage_dtb` and names them in the bisect hint **[V]** | parameterize | Take the artifact list from the board's config; the double-build comparison logic is board-agnostic. |
| `.github/workflows/renovate-hash-sync.yml:71,303,417` | Path filter + `git add` on `configs/mister_de10nano_defconfig` and `board/mister/de10nano/patches/linux/linux.hash` **[V]** | parameterize | Board-scope both paths, or the DE25 kernel bump will land with a stale hash and no CI signal. |
| `renovate.json:38,111,113` | `fileMatch` and its long rationale pin `configs/mister_de10nano_defconfig` (and `mister_kernel_defconfig`) by literal name **[V]** | parameterize | Add the DE25 defconfig to the same manager's file list — one PR touching every board is the intent, and a per-board manager would recreate exactly the half-the-repo bump this comment documents. |

## 4. The ledger — configs, packages, top level

| file:line | coupling | sev | when you touch this, do this instead |
|---|---|---|---|
| `package/azcopy/Config.in:64` | `depends on BR2_arm` gates the package to 32-bit ARM **[V]** | semantic-blocker | **Leave it exactly as is** — this decision is already taken, not pending: the DE25 package set drops azcopy entirely because Microsoft ships an official arm64 binary **[V** plan:139**]**. Do not add a `BR2_aarch64` alternative. |
| `package/azcopy/Config.in:22,51`, `azcopy.mk:19,143`, `azcopy-profile.sh:19,24`, `azcopy.hash:34` | Prose naming the defconfig / the overlay dir / the `make` line **[V]** | cosmetic | No action. The armv7-specific *content* is `Config.in:64` plus the two vendored patches (`0001` GOARCH=arm Timeval, `0002` ARM OABI→EABI keyctl), neither of which is in these files. |
| `configs/mister_kernel_defconfig:31-32` | `BR2_arm=y` / `BR2_cortex_a9=y`, held byte-identical to the main defconfig by the lockstep check named in this file's own header at `:13-20` **[V]** | semantic-blocker | Add a parallel DE25 kernel-variant defconfig with its own lockstep target; never loosen these two in place. |
| `configs/mister_kernel_defconfig:93` | `BR2_LINUX_KERNEL_ZIMAGE=y` **[V]** — coupling (a) at the Kconfig level | semantic-blocker | The aarch64 image format is DP-2's call (`Image`/FIT); it belongs in a DE25 kernel-variant config, not in a branch here. |
| `configs/mister_kernel_defconfig:95` | `BR2_LINUX_KERNEL_INTREE_DTS_NAME="intel/socfpga/socfpga_cyclone5_de10nano"` **[V]** | semantic-blocker | DP-9 says DE25 uses Agilex-native DTS idioms, so its config supplies its own DTS name entirely. |
| `configs/mister_kernel_defconfig:62,89,91,123` | `BR2_GLOBAL_PATCH_DIR` / `LINUX_KERNEL_PATCH` / `CUSTOM_CONFIG_FILE` / `ROOTFS_POST_IMAGE_SCRIPT` embed `board/mister/de10nano/` **[V]** | parameterize | Pure path substitution — a DE25 sibling repeats the pattern with its own board dir. |
| `configs/mister_de10nano_defconfig:105-106` | `BR2_arm=y` / `BR2_cortex_a9=y` **[V]** | cosmetic | Not one of the four: this file is inherently *board-owned*. DE25 gets `configs/mister_de25nano_defconfig` with its own arch stanza; these lines are never edited. |
| `configs/mister_de10nano_defconfig:151,153` | `BR2_LINUX_KERNEL_ZIMAGE=y`, Cyclone-V in-tree DTS name **[V]** | cosmetic | Same reasoning — board-owned file, DE25 sets its own values in its own copy. |
| `configs/mister_de10nano_defconfig:122-124,143,147,149,830` | Six board-dir paths (post-build, post-image, global patch dir, overlay, kernel patches, kernel config, busybox fragment) **[V]** | cosmetic | Do not make these generic *inside this file*; each board's defconfig points at its own `board/mister/<board>/` tree. |
| `configs/mister_de10nano_defconfig:1,83` | The filename in the header comment and one prose mention **[V]** | cosmetic | No action. |
| `configs/mister_initramfs_defconfig:28-29` | `BR2_arm=y` / `BR2_cortex_a9=y`; the file's own `:26-27` says arch here only has to match "the same silicon as the main build" **[V]** | semantic-blocker | A DE25 initramfs is a new sibling defconfig with the aarch64 arch + core stanza, not a widened symbol here. |
| `configs/mister_initramfs_defconfig:5,56,59,84` | Prose plus busybox-config / overlay / post-build-script paths under the board dir **[V]** | parameterize | Path substitution only — no arch semantics in any of the three. |
| `configs/mister_installer_defconfig:60-64` | `BR2_arm=y` / `BR2_cortex_a9=y` / NEON / VFP / FPU_NEON for the throwaway installer OS **[V]** | cosmetic | Board-owned file: DE25 gets its own installer defconfig if and when its installer flow is designed (which DP-2 and coupling (b) gate anyway). |
| `configs/mister_installer_defconfig:109,116` | Installer busybox config + installer overlay under the board dir **[V]** | cosmetic | Same — the DE25 copy repeats the pattern. |
| `configs/mister_rt.fragment:23,62,100,105,108` | Kernel-patch dir, RT fragment path, and the hash coupling all name `board/mister/de10nano/`; `:100` records a `zImage_dtb` build check **[V]** | parameterize | Board-scope the three paths when the RT variant is next touched; note DP-6 says RT on big.LITTLE must be re-evaluated, not assumed to port. |
| `Makefile:69` | `INITRAMFS_INIT := $(ROOT_DIR)/board/mister/de10nano/initramfs-overlay/init` **[V]** | parameterize | Take the board dir from a `BOARD` make variable defaulting to `de10nano` — see §6.2. |
| `Makefile:330` | `$(BR_MAKE) mister_de10nano_defconfig` in the `.config` recipe **[V]** | parameterize | Drive the defconfig name off the same `BOARD` variable so `make BOARD=de25nano` is the whole invocation surface — see §6.2. |
| `Makefile:393,436,450,541,628,654,701,886` | Eight more board-dir paths and error strings, incl. `:701` invoking `board/mister/de10nano/post-image.sh` **[V]** | parameterize | Same `BOARD` substitution; `:701` is the one that actually *runs* something, so it moves with `:69`/`:330` in the same diff. |
| `Makefile:80,139-140,294,421-451,484-578,684-720,784-788` | ~20 `zImage`/`ZIMAGE_DTB_*` references: the RT variant's artifact, the initramfs-inside-the-zImage invariant, the `zimage-dtb` target and its help text **[V]** | parameterize | The `zimage-dtb` target is coupling (a)'s make front-end — when a board axis lands, give DE25 its own image-assembly target rather than making this one arch-aware. |
| `Makefile:15,685-686,740` | Comments and `make help` naming `mister_de10nano_defconfig` and `post-image.sh` **[V]** | cosmetic | Update *together with* `:330` if that is parameterized, so the help text does not go stale; no independent action. |
| `external.mk:47-78` | The `CONFIG_INITRAMFS_SOURCE` fixup is arch-agnostic kconfig machinery; only `:57` and `:77` say "zImage" in prose **[V]** | cosmetic | **Reuse this block unchanged** for aarch64 — `Image` embeds an initramfs identically; reword two comments at most. Plan §3 item 1 already records this as carrying over **[V]**. |
| `external.mk:32,36` | Comments naming the defconfig and `linux.config` to explain a `pkg-kconfig.mk` constraint **[V]** | cosmetic | The constraint applies to any board's defconfig; reword to "the board's defconfig" or leave. |
| `Config.in:20` | Comment pointing at `board/mister/de10nano/linux.config` as the partner list for the WiFi driver menu **[V]** | cosmetic | No Kconfig symbol here is board-specific (packages are sourced via `$BR2_EXTERNAL_MISTER_PATH`); update the pointer only if a DE25 `linux.config` grows an equivalent list. |
| `package/dualsensectl/Config.in:26` | Comment cites patches `0033/0037/0042` in the board's `linux-patches/` **[V]** | cosmetic | These input/HID patches are classified arch-neutral and expected to port as-is (**[V** plan:135**]**); reword the path when the DE25 series exists. |
| `package/7zip/7zip.mk:178` | Comment names `{linux.img, zImage_dtb}` as what the two exFAT writers consume **[V]** | cosmetic | Reword to the DE25 payload name if 7-Zip is carried over; no build logic depends on it. |
| `install.sh:69-74,93-114,370` | Fetches `board/mister/de10nano/fat-payload/Scripts/*` over raw.githubusercontent and prints `/media/fat/linux/zImage_dtb` in its summary **[V]** | parameterize | Board-scope the three URL defaults; note the printed payload names follow DP-2 and Decision 4's separate `db-de25nano.json` namespace. |
| `CONTRIBUTING.md:42,45,101,138,163,203` | Prose naming the two kernel-patch dirs, the defconfig, and the licence of `linux-patches/*.patch` **[V]** | cosmetic | Add a third bullet for `board/mister/de25nano/linux-patches/` alongside these rather than abstracting the paths into board-generic prose. |
| `README.md` (18 lines), `PLAN.md` (23), `TASKS.md` (22), `MISTER-KERNEL-PATCH-RECON.md` (6) | Repo-root narrative docs describing the DE10 build, its artifacts, and the kernel-patch recon **[V** line lists in §7 workfile**]** | cosmetic | These describe *the DE10 product as built today* and stay accurate as-is; a DE25 gets its own sections or its own docs, per ADR 0027's staged framing. No edit is owed by D1. |

---

## 5. Semantic blockers — the four, and what each is waiting on

D1.2 has no separate deliverable file; §5.1–§5.7 below **are** D1.2.

| # | Blocker | Design decision owed | Owner |
|---|---|---|---|
| (a) | zImage header / `zImage_dtb` concatenation | What container a DE25 kernel+DT payload ships in (FIT by default, or `Image`+dtb) | **DP-2** (plan:168), pinned against D0.1's boot flow ([`de25-boot-chain.md`](de25-boot-chain.md)) |
| (b) | 0xA2 BootROM SD layout | The Agilex GSRD-shaped partition layout and its own genimage config | **D2.2** on-hardware, informed by D0.1 §4–§5's QSPI/SD seam |
| (c) | `^BR2_arm`/`^BR2_cortex` asserts | How the board axis plugs into the shared build action and the lockstep check | **D1.2 = §5.1–§5.7 below**, implemented at **D2.1** |
| (d) | armv7 `package/azcopy` | *Already decided* — azcopy is dropped from the DE25 set (MS ships arm64 binaries) | closed; no work owed |

Note that (a) and (b) are *not* blocked on this repo at all — they are blocked on hardware and
on DP-2. Only (c) has design work that can be done cold, which is why D1.2 exists and why it is
the only one of the four with a spec below.

### 5.1 What exists today (verbatim)

**`scripts/check-kernel-defconfig-sync.sh`** — paths **[V :61-62]** `configs/mister_de10nano_defconfig`
and `configs/mister_kernel_defconfig`; sentinel assert **[V :83]**
`for must in BR2_arm BR2_cortex_a9 BR2_KERNEL_HEADERS BR2_TOOLCHAIN_BUILDROOT_CXX` (`rc=1` if any
is absent, `:84-89`); family name-set assert **[V :129]**
`for family in BR2_arm BR2_ARM_ BR2_cortex BR2_KERNEL_HEADERS BR2_TOOLCHAIN_BUILDROOT_` (`rc=1` on
set inequality, `:130-139`). Exit taxonomy is documented in its own header **[V :54-55]**:
0 = lockstep, 1 = drift/sentinel-loss, 2 = usage/IO error (already used for a missing input at `:65`).

**`.github/actions/buildroot-build/action.yml`** — fingerprint source **[V :151-155]**
(`fp_defconfig` selected by `VARIANT`, not by board); deny-list filter **[V :158,:181]** stripping
`^($|BR2_PACKAGE_|BR2_LINUX_KERNEL)`, which is board-invariant *policy* and stays global;
sentinel assert **[V :190-195]** `for must in '^BR2_arm' '^BR2_cortex'` → `::error::` + `exit 1`.
`:166`'s `board/mister/de10nano/patches/$d` is a *path* hardcode, handled in §3, not here.

### 5.2 Table shape, location, and key

A new sourced-only data file, `scripts/lib/board-expectations.sh`, following the house
convention of `scripts/ci-lib.sh` (sourced from `run:` blocks — **[V]** `build.yml:247,320`,
`kernel-leg/action.yml:102`) and `scripts/lib/hash-sync-common.sh`. **One file, not a copy per
consumer** — this guard exists because copied stanzas drift; the table must not repeat that
mistake against itself.

```bash
# scripts/lib/board-expectations.sh — sourced, not executed.
# Per-board expected-symbol tables for the arch/toolchain guards in
# scripts/check-kernel-defconfig-sync.sh and
# .github/actions/buildroot-build/action.yml. Adding a board means adding a
# row here; there is deliberately no fallback row and no wildcard match.

# Arch-independent sentinels/families every board shares (KERNEL_HEADERS is a
# choice under package/linux-headers, TOOLCHAIN_BUILDROOT_CXX is under
# package/gcc — neither varies by board, so neither is duplicated per row).
BOARD_COMMON_SENTINELS="BR2_KERNEL_HEADERS BR2_TOOLCHAIN_BUILDROOT_CXX"
BOARD_COMMON_FAMILIES="BR2_KERNEL_HEADERS BR2_TOOLCHAIN_BUILDROOT_"

declare -A BOARD_ARCH_SENTINELS=(
  [de10nano]="BR2_arm BR2_cortex_a9"
  [de25nano]="BR2_aarch64 BR2_cortex_a76_a55"   # [U] — CPU choice is D2.1's call
)
declare -A BOARD_ARCH_FAMILIES=(
  [de10nano]="BR2_arm BR2_ARM_ BR2_cortex"
  [de25nano]="BR2_aarch64 BR2_ARM_ BR2_cortex"  # [U] — BR2_ARM_ likely empty-set
                                                # on both sides; harmless if so
)
declare -A BOARD_FINGERPRINT_SENTINELS=(
  [de10nano]="^BR2_arm ^BR2_cortex"
  [de25nano]="^BR2_aarch64 ^BR2_cortex"          # [U]
)
```

**Why an explicit BOARD string key, not something derived:**

- *Not the defconfig filename stem* — that conflates the **board** axis with the **variant**
  axis the action already has (`main` vs a kernel-only flavor, **[V :103-129]**), which are
  orthogonal. `mister_kernel_defconfig` carries no board name at all today; that is a
  single-board assumption in a *filename*, a §3/§4 path fact, not a table fact.
- *Not derived by reading `BR2_arm` vs `BR2_aarch64` back out and picking a generic 32/64-bit
  row* — that is precisely the failure the accept criterion forbids: a third board sharing an
  architecture would silently inherit an existing row, and "forgot to add a board" would be
  indistinguishable from "this board intentionally matches." Each row must be an **affirmative,
  reviewed claim**, not an inference.
- An explicit key makes a **missing entry a hard error**: under `set -u`, an unset associative
  key is already an unbound-variable error, and the design additionally requires an explicit
  `[ -z "${BOARD_ARCH_SENTINELS[$BOARD]+set}" ]` check so the message *names the missing board*
  instead of surfacing a bare bash trace. Both consumers use the same idiom.

### 5.3 The DE10 row

| | Sentinels | Families |
|---|---|---|
| common (all boards) | `BR2_KERNEL_HEADERS`, `BR2_TOOLCHAIN_BUILDROOT_CXX` | `BR2_KERNEL_HEADERS`, `BR2_TOOLCHAIN_BUILDROOT_` |
| `de10nano` (arch) | `BR2_arm`, `BR2_cortex_a9` | `BR2_arm`, `BR2_ARM_`, `BR2_cortex` |

Merged (arch row first, then common), this reproduces **[V]** the exact four sentinels at `:83`
and the exact five families at `:129`, in that order — byte-identity is what makes §5.6's
migration check meaningful. Fingerprint row `^BR2_arm ^BR2_cortex` reproduces **[V :190]**.

### 5.4 The DE25 row, honestly

| | Sentinels | Families |
|---|---|---|
| `de25nano` (arch) | `BR2_aarch64` **[V]**, `BR2_cortex_a76_a55` **[U]** | `BR2_aarch64`, `BR2_ARM_` **[U]**, `BR2_cortex` |

- `BR2_aarch64` **[V]** — a live Buildroot arch choice at `work/buildroot/arch/Config.in:54`,
  sibling of `BR2_arm` under the same choice (`:411`). Upstream's
  `configs/qemu_aarch64_ebbr_defconfig:1` sets only `BR2_aarch64=y` and no `BR2_ARM_*` **[V]**,
  consistent with that family bucket being legitimately empty on both sides — which the
  set-equality check accepts (empty == empty).
- `BR2_cortex_a76_a55` **[U]** — the symbol exists (`work/buildroot/arch/Config.in.arm:474`,
  "cortex-A76/A55 big.LITTLE") and matches the HPS's 2×A76 + 2×A55 per ADR 0027, but whether
  `configs/mister_de25nano_defconfig` actually selects it (versus a generic `cortex-a53`
  fallback) is **D2.1's decision**. Treat this cell as a placeholder to confirm or correct when
  D2.1 lands the real defconfig.
- `BR2_cortex` as a *family prefix* carries over **[V]** — both 32- and 64-bit cores live in the
  same `BR2_cortex_*` namespace under `arch/Config.in.arm` (`:204` A9, `:474` A76/A55); there is
  no separate `Config.in.aarch64` file **[V]**.

### 5.5 The toolchain-fingerprint equivalent

Only `:190-195` becomes per-board: replaced by a lookup into
`BOARD_FINGERPRINT_SENTINELS[$BOARD]`, with a new `board` input defaulting to `"de10nano"`,
validated exactly the way `variant` already is at **[V :112-123]** — an unrecognized board hits
the same `::error::` + `exit 1` idiom that file already uses for an unrecognized variant.
The deny-list filter (`:158`/`:181`) and the toolchain-patch hash (`:165-170`) stay **global,
unchanged policy**; `:166`'s board path is a §3 path fix, deliberately out of scope here.

### 5.6 Migration — zero behaviour change for DE10, and how a reviewer proves it

Both consumers take a `BOARD` that **defaults to `de10nano`**. No caller passes one today (the
three call sites in the script's own header **[V :46-52]**; the action's implicit default), so
every existing invocation resolves to the merged common+de10nano row, defined to be textually
identical, in the same order, to today's literal `for … in …` lists. No filename selection
logic changes.

1. `scripts/check-kernel-defconfig-sync.sh` with no args, before vs. after — stdout must be
   byte-identical, specifically the `OK — $shared shared BR2_ symbol(s) agree, …` line
   **[V :155]** with the same `$shared` count.
2. `BOARD=de10nano scripts/check-kernel-defconfig-sync.sh` vs. the no-arg run — must **also** be
   byte-identical, proving the default and the explicit path are one code path, not two that can
   quietly diverge.
3. A deliberately broken kernel defconfig (drop `BR2_cortex_a9=y`) must still fail identically,
   with the same sentinel-missing text **[V :85-87]** modulo table-driven wording, so the
   message keeps pointing readers at that file's LOCKSTEP header.
4. For the action: diff the `Toolchain fingerprint (N lines):` block **[V :196-197]** between a
   pre- and post-change run of the same ref on `variant: main` — line count, content, order must
   match exactly. Nothing about `fp_defconfig` or the deny-list moves, so only the sentinel
   *implementation* can differ, never its inputs or its log.
5. **New test:** an unknown `board:` (e.g. `bogus`) must fail at the same early point the unknown-
   variant check fails **[V :107-121]**, with an `::error::` naming the unknown board — this is
   the fail-closed property, exercised directly.

### 5.7 Fail-closed statement, and the risks to it

Both guards keep exactly their current DE10 behaviour — identical sentinel sets, identical
family sets, identical exit codes 0/1/2, identical `::error::`/`exit 1` idiom — under the
default. The only new failure surface is a *third* outcome, an unrecognized board, designed to
fail loudly (script: exit 2, its existing usage/IO class **[V :55]**; action: `::error::` +
`exit 1`, matching the unknown-variant precedent **[V :119-122]**). **No path in this design
turns either assert into a warning, and no path lets an unrecognized board proceed with an empty
or inherited expectation set.**

Named risks, so a reviewer can check them rather than take the claim:

1. The DE25 CPU sentinel is **[U]** — the symbol matches the SoC, the defconfig's actual choice
   is D2.1's.
2. Whether an aarch64 defconfig ever populates `BR2_ARM_*` is unverified beyond one upstream
   example. If the guess is wrong the bucket is simply always-empty on both sides, which still
   *passes correctly* — cosmetic, not fail-open.
3. This design does not resolve the **file-path axis** (what the DE25 defconfigs are named, how
   `fp_defconfig`/`VARIANT` compose with a board) — deliberately left to §3/§4 and D2.1. An
   implementer who wires `BOARD` through without adding `configs/mister_de25nano_defconfig`
   fails at the file-existence check **[V :65]** rather than at the table: still fail-closed,
   just at a different line than intended.
4. **This is a design, not a merged diff.** The "no behaviour change" claim rests on the default
   semantics being implemented *exactly* as specified. A sloppy implementation — `BOARD`
   defaulting to the empty string, or an unknown key falling through to the last array entry —
   would silently destroy the property this design exists to guarantee. §5.6's checks 1, 2 and 5
   are the ones that catch that, and a reviewer must actually run them.

---

## 6. Proposed follow-up diffs — **proposals only, NOT made by this task**

Zero-risk `BOARD=` introductions, offered for **separate review**. Nothing below has been
applied; no script, config, workflow, or package file was modified by D1.1. Each is
behaviour-neutral while `BOARD=de10nano` remains the only value, and each should be reviewed and
landed on its own merit, not as a batch.

### 6.1 `scripts/check-kernel-defconfig-sync.sh:61-62`

```sh
BOARD="${BOARD:-de10nano}"
MAIN_DEFCONFIG="$ROOT/configs/mister_${BOARD}_defconfig"
KERNEL_DEFCONFIG="$ROOT/configs/mister_kernel_defconfig"   # see §5.2 on the variant axis
```

### 6.2 `Makefile:69` and `Makefile:330`

```make
BOARD ?= de10nano
INITRAMFS_INIT := $(ROOT_DIR)/board/mister/$(BOARD)/initramfs-overlay/init
```

```make
$(OUTPUT_DIR)/.config: | $(BR_STAMP)
	@mkdir -p $(OUTPUT_DIR)
	$(BR_MAKE) mister_$(BOARD)_defconfig
```

If `:330` lands, `Makefile:15` and `Makefile:740`'s help text move in the **same** commit, or the
documented invocation goes stale.

### 6.3 `configs/mister_kernel_defconfig:62,89,91,123` and `configs/mister_initramfs_defconfig:56,59,84`

Same substitution pattern applied to the board-dir path prefix only. **Lower confidence:**
Buildroot defconfigs are not make files and do not expand a `BOARD` variable — these two rows
most likely resolve as *sibling files per board* (as §4 says for `mister_de10nano_defconfig`
itself) rather than as a substitution. Do not land 6.3 without settling that first.

### 6.4 `scripts/test-initramfs.sh:83`, `scripts/check-linux-img.sh:41`, `scripts/hash-sync-kernel.sh:196`, `scripts/lint-kernel-patches.sh:67`

All four read a pinned value out of `configs/mister_de10nano_defconfig` by literal name. Each
takes `BOARD="${BOARD:-de10nano}"` and composes the path — four independent one-line diffs, no
shared state, reviewable in isolation.

### 6.5 `.github/workflows/lint.yml:37-61,165-199`

Replace ~20 literal `board/mister/de10nano/...` entries with `board/mister/*/...` globs. The
highest-value pure-path fix in the repo, and the one most likely to silently *stop linting* a
DE25 tree if it is skipped.

---

## 7. Coverage reconciliation

Command run from the repo root, 2026-08-21:

```sh
git grep -nE 'de10nano|BR2_arm|zImage' \
  -- ':(exclude)board/mister/de10nano/' ':(exclude)docs/'
```

`git grep` is the canonical form because it searches **tracked files only**, which is what the
accept criterion means and what makes the counts below reproducible on any machine. The raw-grep
equivalent needs every ignored tree excluded by hand and still varies by grep implementation:

```sh
grep -rEn 'de10nano|BR2_arm|zImage' \
  --exclude-dir=.git --exclude-dir=output --exclude-dir=output-initramfs \
  --exclude-dir=output-rt --exclude-dir=dl --exclude-dir=buildroot \
  --exclude-dir=work --exclude-dir=.claude . \
  | grep -vE '^(\./)?(board/mister/de10nano/|docs/)'
```

| | count |
|---|---|
| Matching lines | 457 |
| Distinct files hit | **54** |
| Files with a ledger row | **54** (100%) |
| Files deliberately omitted | **0** |
| §2 scripts | 25 files → 26 rows |
| §3 CI | 9 files (8 under `.github/` + `renovate.json`) → 11 rows |
| §4 configs / packages / top-level | 20 files → 28 rows |
| **Total rows** | **65** |
| Severity: semantic-blocker | 14 rows |
| Severity: parameterize | 26 rows |
| Severity: cosmetic | 25 rows |

Rows exceed files because several files carry rows at more than one severity
(`configs/mister_kernel_defconfig` and `Makefile` carry four each,
`.github/actions/buildroot-build/action.yml` three); the four repo-root narrative docs share
one row. 14 + 26 + 25 = 65 = 26 + 11 + 28, so every row is severity-tagged and no file is
counted twice.

**Grep-hygiene notes, so a future re-run reconciles:**

- **Use `git grep`.** The raw-grep form's result depends on which grep is installed. `ugrep`
  (and `rg`) honour `.gitignore` by default and therefore skip `work/` and `.claude/`; GNU grep
  does not, and without `--exclude-dir=work --exclude-dir=.claude` it returns **15 796** lines
  instead of 457 — `work/U-Boot_MiSTer` alone carries 102 files matching `zImage`, and
  `.claude/worktrees` holds whole repo copies. A reconciliation that silently depends on the
  operator's grep is not a reconciliation; verified both ways 2026-08-21.
- The `^(\./)?` alternation matters in the raw-grep form — `ugrep` emits paths *without* a
  leading `./`, so the exclusion filter published in earlier drafts (`^\./(…)`) silently matched
  nothing and pulled ~200 `docs/` and board-dir lines back in.
- `board/mister/de10nano/` and `docs/` are excluded **by the accept criterion**, not by
  convenience: the board dir is by definition board-owned (that is the axis ADR 0027 Decision 1
  creates), and `docs/` describes the DE10 as built rather than constraining a DE25 port.
  `README.md`, `PLAN.md`, `TASKS.md` and `MISTER-KERNEL-PATCH-RECON.md` are the same class of
  content that happens to sit at the repo root; they get one shared cosmetic row in §4 rather
  than a row per line.

**Three things the "four couplings" framing did not anticipate**, surfaced by the full sweep:

1. **`.github/workflows/lint.yml` is the single largest path hardcode in the repo** (~20 literal
   board paths, `:37-61` and `:165-199`) and it is *silent* when wrong: a DE25 tree simply would
   not be linted, with a green check. ADR 0027 §Context's survey did not name it.
2. **`renovate.json` + `renovate-hash-sync.yml` form a fourth path axis** — the dependency-bump
   machinery pins the defconfig *and* the kernel hash file by literal name, and
   `renovate.json:111` documents that a manager covering only some of the files "bumps half the
   repo and leaves the copy behind" **[V]**. A DE25 defconfig added without touching these lands
   with a stale kernel pin and no CI signal — the same class of bug that comment was written
   about, one axis over.
3. **`.github/workflows/release.yml` is far more coupled than the survey's "4 CI files" implied**
   (13 hit lines spanning asset names, `SHA256SUMS`, attestation globs, and a variant round-trip
   check). This is not a blocker — ADR 0027 Decision 4 already reserves a separate
   `de25-YYYYMMDD` tag namespace, so DE25 releases are a *second* asset set — but the cost is
   real and belongs in D2's estimate, not discovered during it.

Nothing in the sweep contradicted the four couplings, and no *fifth* semantic coupling was
found: every one of the 51 non-(a)-(d) files is a path, a name, or prose.
