# RT / Linux-7.2 "beta" kernel variant

**Status: BUILT, BOOTED, UNMEASURED** (last updated 2026-07-28; this header used
to say "SCAFFOLD, never built or booted" and was overtaken by §6).

The variant builds end-to-end (`make rt`, green locally and in CI on the pinned
**7.2-rc5**, **32 of 37** carried patches — five landed after the series was last reviewed and are missing, see §2) and **boots and runs MiSTer on a
real DE10-Nano — confirmed 2026-07-20 on 7.2-rc4.** Two things are still **not**
done. The one that motivates the whole exercise: **no latency measurement has
been taken**, so there is currently no evidence RT improves anything for a
normal user. The other is a standing consequence of tracking mainline `-rc`:
**the boot confirmation is version-specific and the pin has moved since** — see
the §6 row. Read "boots" as "booted on rc4", not "boots on whatever is pinned
today".

It remains intended for **developer testing of PREEMPT_RT and new-kernel
features**, not general use. WiFi via the out-of-tree Realtek drivers is
deliberately dropped on this variant (see §4). §6 is the authoritative
verified-vs-unproven table; §7 is the remaining TODO.

---

## 1. Why 7.2, and why a separate kernel

The DE10-Nano's Cyclone V is a dual-core **Cortex-A9 (ARMv7-A, 32-bit)** — there
is no AArch64 path on this silicon. `PREEMPT_RT` for 32-bit ARM merged into
mainline in **Linux 7.1**, so on **7.2** `arch/arm/Kconfig` already
`select ARCH_SUPPORTS_RT` (verified) — meaning RT is a plain kconfig option here,
**no out-of-tree RT patch to carry**. `EXPERT=y` is inherited from
`linux.config`, so `CONFIG_PREEMPT_RT=y` is all it takes.

RT cannot be a boot-time toggle on ARM32 (no `PREEMPT_DYNAMIC`/static-calls), so
it must be a **separately compiled kernel image** — a manual GitHub-Release
download, never card payload (ADR 0021 item 4 as reversed 2026-07-27) —
shipped as `zImage_dtb-rt`
alongside the main 6.18 image and selected on-device (§5).

## 2. Structure — a kernel-only base defconfig plus a per-variant fragment

The main 6.18 image build is untouched. Since ADR 0021's **2026-07-18
amendment** the variant is a **kernel-only** Buildroot build (no userland): the
shared base `configs/mister_kernel_defconfig` — the main defconfig's toolchain
and kernel stanzas mirrored, `BR2_TARGET_ROOTFS_TAR` only, no packages — with
the per-variant fragment layered on at build time.

| File | Role |
|---|---|
| `configs/mister_kernel_defconfig` | The kernel-only base, shared by every kernel variant. Its toolchain/kernel stanzas are a **copy** of `mister_de10nano_defconfig`'s, held in lockstep by `scripts/check-kernel-defconfig-sync.sh` (CI runs it before every kernel build and as a lint). With no fragment it builds the main 6.18 kernel. |
| `configs/mister_rt.fragment` | Buildroot-config delta (kernel version → the 7.2 mainline line, currently `7.2-rc5`, via Buildroot's native `-rc` handling; beta patch dir; kernel-config fragment). Merged onto `mister_kernel_defconfig` via `merge_config.sh`. |
| `board/mister/de10nano/linux-rt.fragment` | **Kernel**-config delta layered on the shared `linux.config`: `CONFIG_PREEMPT_RT=y` — do not confuse the two fragment layers (RTL8814AU's in-kernel driver comes from `linux.config` itself, inherited — not duplicated here). |
| `board/mister/de10nano/linux-patches-beta/` | `series` file + **symlinks** to the shared `linux-patches/` — except `0001`, `0015`, `0030` and `0037`, which are real re-anchored copies (Buildroot patches at `-F0`; their 6.18 context or APIs drifted on 7.x — see the series header). The shared 6.18 patches stay byte-identical to stock. Applies **32 of the 37** patches in `linux-patches/` (the 32nd is `0043-dts-uio-doorbells`, added 2026-08-08 — see the series header). ⚠ **It currently drops five**: `0038`, `0039`, `0040`, `0041`, `0042` (all landed 2026-07-24, after the series was last reviewed) have no entry and no symlink. That contradicts the standing rule in §7 item 3 — `0039` remaps NSO N64/Genesis buttons and `0040`/`0041`/`0042` are Main_MiSTer-coupled evdev-name and LED-classdev-name parity patches. Re-anchor or symlink them into `linux-patches-beta/series`; do not leave them out. (`0031` was a fifth copy until 2026-07-25, when the *shared* patch was re-anchored onto context both trees agree on and the beta entry became a symlink again; the series header explains why that is the preferred move.) `0015` is re-INCLUDED: the earlier "upstreamed in 7.2" finding was wrong (7.2 has no `FAML`/`FAMR` controller types — its left/right *nescon* support is a different thing). The separate `linux-patches-upstream/` series (carried for the exported `Linux-Kernel_MiSTer` tree only, never applied by Buildroot — `docs/patch-provenance.md` §12) is unrelated to this count and is not applied to the beta either. |
| `Makefile` (`rt`, `rt-clean`, `rt-menuconfig`) | Builds into `output-rt/` (stage-1 initramfs first — its cpio is embedded into every kernel), reusing the shared dl/ccache; then stages the depmod'd module tree into `work/extra-modules-overlay/`, which the main defconfig's `BR2_ROOTFS_OVERLAY` folds into the ONE shipped `linux.img` at the next `make all`. The main `output/` is never touched by `make rt` itself. |

The kernel config is the same `linux.config` + a fragment, and the patch set is
symlinks + a `series` file — editing a shared patch or `linux.config` affects
both kernels automatically. The deliberate copies (the base defconfig's
toolchain/kernel stanzas; the two re-anchored patches) are machine-checked or
lockstep-annotated, not trusted: the sync script covers the former, and each
re-anchored patch carries a bracketed note naming its `linux-patches/`
original.

Adding a future kernel variant `foo`: `configs/mister_foo.fragment` plus
`foo`/`foo-clean`/`foo-*` Makefile targets mirroring the `rt` ones (`main` is
reserved — it's `buildroot-build`'s full-image variant name, not available
for a kernel-only one; `scripts/list-kernel-variants.sh` refuses it). What
that buys automatically, with nothing to edit:

- **The CI build matrix itself.** `configs/mister_*.fragment` is the registry
  (the same existence check `.github/actions/buildroot-build/action.yml`
  already runs), and `build.yml`/`release.yml` each derive their `kernel:`
  matrix from it via `scripts/list-kernel-variants.sh`, so both pick `foo` up
  automatically instead of each carrying its own hand-typed matrix literal.
- **`release.yml`'s release-asset list and provenance-attestation
  `subject-path`.** The attestation's `subject-path` is globbed off
  `dist/zImage_dtb-*`, and the release-asset list is derived per-variant from
  the variant names recorded in `dist/SHA256SUMS` (the `publish` job has no
  checkout, so `scripts/list-kernel-variants.sh` is not on disk there). A
  dedicated verify step asserts, **by name and for every variant**, that all
  three files are present before either is used — so a partial loss (one file
  gone, or one whole variant's three gone while another variant's remain)
  fails the job instead of publishing a release short a variant's worth of
  assets. That per-variant assert is also what covers the attestation:
  `actions/attest-build-provenance` globs its whole `subject-path` set as a
  unit and only errors when the *combined* match set is empty, which the
  always-present `dist/linux.img` guarantees it never is. With that in place,
  `foo`'s three files are picked up, hashed into `SHA256SUMS`, and attested
  without a code change.

What still needs a hand-edit for a new variant, because it is genuinely
per-variant prose or a genuinely single-slot design, not registry-derived
plumbing:

- **The release-notes text** in `release.yml`'s `publish` job — the
  human-readable paragraph describing what the variant *is* (a real-time
  kernel, in this case) is written for a human reader, not derived from a
  filename.
- ~~**The sdcard installer's bonus kernel.**~~ **No longer applicable
  (2026-07-27).** `scripts/mk-sdcard.sh` used to ship exactly one extra kernel
  on the card's FAT payload (`MISTER_RT_ZIMAGE` → `zImage_dtb-rt`). It ships
  **none**: `$MISTER_RT_ZIMAGE` is deleted, and every variant kernel — RT
  included — is a manual GitHub-Release download (ADR 0021 item 4, reversed).
  So there is nothing here for a variant registry to infer either way, and
  adding a future variant no longer raises a "which one goes on the card"
  question at all. The card's `linux.img` still carries every variant's
  MODULE tree, which is what makes the download-and-drop-in workflow work.

## 3. Kernel headers / userland ABI — unchanged

`BR2_KERNEL_HEADERS_6_18=y` is inherited from the base defconfig. That knob is
independent of the kernel *version* being built, so the RT variant's userland is
still compiled against **6.18 headers** — identical ABI. A 7.2 kernel runs that
userland fine (Linux never breaks userspace), and `PREEMPT_RT` is UAPI-transparent
(kernel-internal scheduling/locking; no new syscalls). There is no separate RT
userland at all: the RT kernel boots the SAME `linux.img` as the main kernel.

## 4. WiFi on the beta

The three out-of-tree morrownr drivers (`rtl8812au`, `rtl8814au`, `rtl8821au`)
**do not build on 7.x**: Linux 7.1 refactored the cfg80211 op-table
(`net_device*` → `wireless_dev*`), and morrownr's drivers top out at kernel 7.0
(our pins are already at each repo's HEAD — there is no newer commit to bump to).
So this variant has no OOT WiFi modules (the kernel-only base builds no
packages, and even a 7.x tree could not compile them).

- **RTL8814AU** is recovered via the **in-kernel** `rtw88_8814au` driver (merged
  upstream in Linux 6.16). This is inherited from the shared `linux.config` — the
  main build migrated that chip in-kernel (`CONFIG_RTW88_8814AU=m`), so the beta
  gets it for free. Firmware `rtw88/rtw8814a_fw.bin` ships via
  `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88`.
- **RTL8812AU / RTL8821AU** have no clean in-kernel equivalent at their chipsets
  and are simply absent here. A developer testing RT can use ethernet or the
  in-kernel `rtw88`/`rtw89`/`rtl8xxxu` adapters that the base config already ships.
- `xone` (Xbox controllers) **compiles clean on 7.2**, but since the 2026-07-18
  kernel-only restructure the variant build has **no packages**, so no 7.2
  `xone` (or any other OOT) module ships — the RT kernel's module tree is
  in-tree-only. Xbox-dongle users testing RT lose xone until a variant
  OOT-module story exists (open item in ADR 0021's amendment).

If full OOT WiFi on the beta is ever wanted, carry a local
`#if LINUX_VERSION_CODE >= KERNEL_VERSION(7,1,0)` compat patch (reference:
`armbian/wifi-rtl8852bs` PR #5) and upstream it to morrownr — but gate it on the
version code so it stays inert on the shared 6.18 build.

## 5. Build & flash

```sh
make rt                       # -> output-rt/images/zImage_dtb (the RT kernel)
                              #    + its module tree staged into the overlay
make all                      # -> linux.img now carries BOTH module trees
# 1. install THAT linux.img on the device first — the normal Linux update
#    path (replace /media/fat/linux/linux.img): it is the rootfs the RT
#    module tree lives in, and an older on-device image has only 6.18 modules
# 2. then put the RT kernel next to it:
cp output-rt/images/zImage_dtb  /media/fat/linux/zImage_dtb-rt
```

Select it on-device with a one-line edit to `/media/fat/linux/u-boot.txt`
(U-Boot imports it before loading the kernel — no U-Boot rebuild, stock
`uboot.img` unchanged):

```
bootimage=/linux/zImage_dtb-rt
```

Remove that line to roll back to the stock kernel. **Switching needs no rootfs
flash in either direction** — u-boot.txt is the entire switch — *provided the
on-device `linux.img` is one built with both trees* (step 1 above; for release
users, this release's `linux.img`): the ONE `linux.img` carries both kernels'
module trees (`usr/lib/modules/<main kver>/` and `usr/lib/modules/7.2.0-rc*/` —
the second tree is ~5-8 MB in a 512 MiB image with ~268 MB free). Skip step 1
against an older image and `zImage_dtb-rt` boots with NO 7.2 modules to load:
WiFi and the rest of the modular driver set silently stay dead, presenting as
broken peripherals rather than as the missing-module-tree mistake it is.
There is no `linux-rt.img` anymore.

**CI builds this variant too (ADR 0021 as amended 2026-07-18).** Every gated
`build.yml` run includes a `build-kernel` matrix leg for it, which uploads a
`kernel-rt-<sha>` inter-job artifact (kernel, config, depmod'd modules tar,
manifest-only SBOM); the `build` job then merges the module tree into the one
image it ships. Releases (`release.yml`, same shape but serial before the main
build) ship the RT set as three separate first-class assets: `zImage_dtb-rt`,
`linux-rt.config`, `legal-info-rt.tar.gz` (the RT kernel's applied patches +
SBOM; its upstream source is referenced by `manifest.csv`, not bundled — see
docs/ci.md#legal-info-2gib-cap) — in
`SHA256SUMS`, provenance-attested (the kernel binary), **not** on the sdcard
installer's FAT payload (it was, from 2026-07-18 to 2026-07-27; ADR 0021 item 4
was reversed — an unvalidated real-time kernel does not belong on every user's
card, and nothing on the card referenced it), and deliberately NOT inside
`release_YYYYMMDD.7z` nor referenced by db.json.

## 6. What's verified vs unproven

| | Status |
|---|---|
| 7.2 has ARM32 `ARCH_SUPPORTS_RT` in-tree | ✅ verified (`arch/arm/Kconfig`) |
| Config layering (fragment → 7.2 config) resolves | ✅ verified (`merge_config.sh` + `olddefconfig`, clean) |
| `linux.config` reconciles to 7.2 (criticals survive) | ✅ **after a real fix (2026-07-18)**: the earlier full-config test masked a minimal-config trap — 7.x turned the HID drivers' LED `select`s into `depends on`, so `olddefconfig` silently dropped `NEW_LEDS`/`LEDS_CLASS` **and with them the whole HID controller stack** (`HID_PLAYSTATION`/`HID_NINTENDO` vanished from the config, no error). Fixed by making the LED foundation explicit in `linux.config` (`NEW_LEDS`/`LEDS_CLASS`/`LEDS_TRIGGERS`, no-ops on 6.18); all 19 critical symbols re-audited present |
| **31 of the 36** carried patches apply to 7.2-rc5 at Buildroot's `patch -F0` (⚠ `0038`–`0042` are not in the beta series at all — see §2; this row measures only the 31 that are) (`linux-patches/`; the separate `linux-patches-upstream/` series is never applied to this variant — see §2) | ✅ **re-verified on the rc4 → rc5 bump (2026-07-28)** through Buildroot's own `apply-patches.sh` against a pristine 7.2-rc5 tarball: 31/31 applied, exit 0, zero hunks taking fuzz (70 hunks land at an offset, which `-F0` permits). No re-anchor was needed for rc5, so all four beta-local copies (0001, 0015, 0030, 0037) carry over unchanged. **This row measures only the 31 patches the series lists** — it is not evidence about `0038`–`0042`, which have no series entry and so were never offered to `patch` at all. Nothing dropped a patch that was already *in* the series; the omission happened upstream of this check, when five patches landed in `linux-patches/` on 2026-07-24 and the beta series was not updated to match. Earlier figures on this row (29/29, and before that a bogus "28/31" measured at `patch`'s default fuzz 2, which Buildroot forbids) predate the 2026-07-20 `0037`/`0030` re-anchors |
| `xone` compiles on 7.2 | ✅ verified (not shipped by the kernel-only variant — §4) |
| **The RT kernel compiles and links** | ✅ **re-verified locally on the pinned rc5 (2026-07-28)** — see the `make rt` row below, which is the same cross-build end to end. Two 7.x API ports were needed back on rc3 and still live in beta-local patch copies — the shared 6.18 patches stay byte-identical to stock: `fbcon_update_vcs()`'s header moved into fbdev core (beta 0001, one-line include delta), and `exfat_remove_entries()` grew a `free_benign` arg (that one was folded back into the shared patch on 2026-07-25, so beta 0031 is a symlink again). Unlike the rc3 → rc4 bump, which re-verified patch application only and left this row resting on CI, the rc4 → rc5 bump was built locally before the pin was pushed. |
| **Full `make rt` build (kernel-only; zImage links, modules depmod'd)** | ✅ **verified locally 2026-07-28** on the pinned **rc5** with the complete 31-patch series, from a clean `make rt-clean` (host toolchain rebuilt too, ~16 min on a 32-core box): exit 0, `CONFIG_PREEMPT_RT=y` present in the built tree's `.config`, `zImage_dtb` 10459749 bytes (6317467 bytes of headroom under the 16 MiB U-Boot budget), all `check-zimage-dtb.sh` assertions pass, 90 modules depmod'd and the `7.2.0-rc5` tree staged into the extra-modules overlay (the stale `7.2.0-rc4` tree was removed from both the overlay and `output/target/`, as the stamp mechanism intends). Prior figure on this row was rc4: 9401461 bytes, 7375755 of headroom. Also wired into CI (build.yml + release.yml `build-kernel` matrix, ADR 0021 as amended) |
| **Module-tree merge into the one linux.img** | ✅ **green** — the row's "first green run pending" was overtaken by CI run 29758320422 (2026-07-20, rc4: `build-kernel` + `build` both green, so the merge assert ran). Re-verified locally on rc5 (2026-07-28): after `make rt`, a `make all` produced `output/target/usr/lib/modules/` holding exactly `6.18.40` and `7.2.0-rc5` — two trees, no stale third — and `linux.img` passed every `check-linux-img.sh` assertion (512 MiB, pinned UUID/hash-seed, the 14-feature stock-derived set, ADR 0015 ssh-key checks) |
| **RT kernel boots on the DE10-Nano** | ✅ **CONFIRMED 2026-07-20 — on 7.2-rc4**, which boots and runs MiSTer on real hardware. That retired the single biggest open risk on the variant, and it is how the `0037` DualSense regression was caught: booting far enough to use a controller is what exposed the shifted PS5 button map (§7 item 3). ⚠ **The currently pinned rc5 has not been booted** (bumped 2026-07-28). Boot is a per-version claim and every `-rc` bump re-opens it; the bump verified the tarball, the patch series, and a full local `make rt`, none of which is evidence about boot. Do not read the ✅ as covering the current pin |
| **vsync/IRQ-40 latency under RT threaded IRQs** | ❌ **unproven** (the point of the exercise) — boot and general operation are confirmed, but the latency measurement that motivates RT has not been taken |
| `rtw88_8814au` firmware (`rtw88/rtw8814a_fw.bin`) present | ✅ ships via `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88` |

## 7. What is left

1. ~~Run `make rt` and fix whatever the first real 7.2 build surfaces.~~
   **Done 2026-07-20** — green on the pinned rc4 with the complete 31-patch
   series (§6).
2. ~~Boot `zImage_dtb-rt` on hardware; confirm menu, video/audio/input~~
   **Done 2026-07-20: it boots and runs MiSTer.** Still open, and the actual
   point of the exercise: confirm MiSTer_fb's IRQ-40 vsync still meets the
   50 ms deadline under RT's threaded IRQs (expected to *tighten* pacing —
   measure it).
3. ~~Optionally re-anchor patches `0030` and `0037` to 7.x~~ **Both done
   2026-07-20; the beta series now drops nothing.** `0037` was never optional.
   It was dropped as "cosmetic", but
   `BTN_Z` (`0x135`) sits between `BTN_WEST` and `BTN_TL`, so declaring it
   shifts every higher gamepad button one index up in the `EV_KEY` capability
   bitmap. Main_MiSTer resolves gamecontrollerdb's SDL-style `bN` indices off
   that bitmap (`Main:gamecontroller_db.cpp:get_ctrl_index_maps`), and the shipped
   `gamecontrollerdb.txt` `platform:MiSTer` PS5 rows encode the BTN_Z-present
   layout (`guide:b11`, `leftshoulder:b5`, `back:b9`, `start:b10`). Omitting
   the patch slid the whole DualSense map by one: PS/Home acted as Start and
   L3 opened the OSD. `0030` (one `dev_err`→`dev_dbg` in
   `i2c-designware-master.c`) genuinely is cosmetic, but was re-anchored and
   added too: a series that drops nothing is far easier to reason about and to
   defend upstream than one that drops "only the harmless ones", and the
   `0037` episode is the standing evidence that we cannot always tell which
   those are. Both re-anchored copies now live in `linux-patches-beta/`.
   **Rule this established:** any patch that adds or removes an `EV_KEY`/
   `EV_ABS` capability is load-bearing for every SDL-style index map — never
   classify one as cosmetic on a symbol grep alone. Default to re-anchoring
   rather than dropping.
4. ~~Wire `zImage_dtb-rt` into `release.yml`~~ **Done (ADR 0021, amended
   2026-07-18):** the RT kernel ships as separate first-class release assets
   and its modules ride inside the one `linux.img` (§5). Still OPEN: whether
   `zImage_dtb-rt` should additionally go *inside* `release_YYYYMMDD.7z` /
   gain a db.json entry — that pushes an RT KERNEL at every
   Downloader-subscribed device and stays a human decision (ADR 0021's open
   question; the amendment notes the modules-in-image change strengthens the
   eventual case, since a Downloader-updated device would now get kernel and
   modules coherently).

See also: the RT-feasibility and 7.2-port findings in the project memory / the
session that produced this scaffold.
