# RT / Linux-7.2 "beta" kernel variant

**Status: BUILT, BOOTED (on rc7, not on the pinned 7.2), UNMEASURED** (last
updated 2026-08-17; this header used to say "SCAFFOLD, never built or booted"
and was overtaken by §6).

**The pin left the `-rc` series on 2026-08-17.** Linux 7.2 released on
2026-08-16 and the variant now pins `7.2` — a plain mainline release, not a
snapshot. This is the destination §1 always named, not one more bump, and three
things changed with it: the artifact (a signed `linux-7.2.tar.xz` from the
kernel.org mirror, no longer a cgit `.tar.gz`), the hash provenance (kernel.org's
PGP-signed manifest instead of TOFU — and the signature was actually verified,
see `linux.hash`), and the kernel release string (`7.2.0-rc7` → **`7.2.0`**,
which is the module directory name too). From here the pin tracks **7.2.y**
point releases rather than mainline; it does not follow 7.3-rc1. See §10.

The variant builds end-to-end (`make rt`, **all 36 shared + 4 beta-local**
carried patches — **40 entries, and the series now drops nothing**; three of the
beta-local four are the UIO set (§8) and the fourth is the ramoops crash-record
reservation (§9)) and **boots and runs MiSTer on a
real DE10-Nano — confirmed 2026-07-20 on 7.2-rc4, and again 2026-08-14 on
7.2.0-rc7** (that build carried `0043` and is what the Wave-1 hardware pass ran
on; `0044`, `0045` and `0046` were all written after it — §8, §9). The build
figures on the rows below are from **7.2 final**, measured 2026-08-17 on the
34-entry series of that morning; the patch-application figures on the same rows
were re-measured later the same day and cover all **40**, `0046` and the
long-missing `0038`–`0042` included.
Two things are still **not**
done. The one that motivates the whole exercise: **no latency measurement has
been taken**, so there is currently no evidence RT improves anything for a
normal user. The other is a standing consequence of tracking an upstream line
at all: **the boot confirmation is version-specific and is re-opened by every
bump** — see the §6 row. Read "boots" as "booted on the version named there",
not "boots on whatever is pinned today". Today those do **not** coincide: rc7
booted, and **7.2 final has not been booted on hardware** — it is
patch-verified, DTS-verified and, as of 2026-08-17, **fully built** (`make rt`
green from clean, §6), but nobody has put it on a DE10-Nano. That gap is
expected to narrow rather than vanish, but it should narrow much more slowly
now, because the next bump is a 7.2.y point release rather than the next `-rc`.

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
| `configs/mister_rt.fragment` | Buildroot-config delta (kernel version → the 7.2 line, currently **`7.2`** — a plain mainline release since 2026-08-17, so Buildroot's `-rc` cgit-snapshot path in `linux/linux.mk` no longer applies and it fetches the ordinary `linux-7.2.tar.xz` from the `v7.x` mirror directory; beta patch dir; kernel-config fragment). Merged onto `mister_kernel_defconfig` via `merge_config.sh`. |
| `board/mister/de10nano/linux-rt.fragment` | **Kernel**-config delta layered on the shared `linux.config`: `CONFIG_PREEMPT_RT=y`, the `CONFIG_UIO*` + cmdline set the doorbells need (§8), and the `CONFIG_PSTORE*` set the ramoops node needs (§9) — do not confuse the two fragment layers (RTL8814AU's in-kernel driver comes from `linux.config` itself, inherited — not duplicated here; the same is true of the watchdog, §9.3). |
| `board/mister/de10nano/linux-patches-beta/` | `series` file + **symlinks** to the shared `linux-patches/` — except `0001`, `0015`, `0030` and `0037`, which are real re-anchored copies (Buildroot patches at `-F0`; their 6.18 context or APIs drifted on 7.x — see the series header). The shared 6.18 patches stay byte-identical to stock. Applies **all 36** shared patches in `linux-patches/` plus **four beta-local patches** (`0043-dts-uio-doorbells`, `0044-dts-uio-fpga-regions`, `0045-uio-writecombine` — see §8 — and `0046-dts-ramoops` — see §9; all real files in `linux-patches-beta/` only, kept out of the shared dir so the stock 6.18 build, which applies that entire directory via `BR2_LINUX_KERNEL_PATCH`, never sees them) — **40 entries, dropping nothing**. ✅ **The five-patch gap closed 2026-08-17**: `0038`–`0042` had landed in the shared dir on 2026-07-24 and gone unlisted here for three weeks, which contradicted the standing rule in §7 item 3 (`0039` remaps NSO N64/Genesis buttons; `0040`/`0041`/`0042` are Main_MiSTer-coupled evdev-name and LED-classdev-name parity patches). Measured rather than assumed, they needed **no re-anchor at all** — plain symlinks, clean at `-F0` on 7.2 final, and `drivers/hid/` compiles for ARM with all five in (§6). (`0031` was a fifth copy until 2026-07-25, when the *shared* patch was re-anchored onto context both trees agree on and the beta entry became a symlink again; the series header explains why that is the preferred move.) `0015` is re-INCLUDED: the earlier "upstreamed in 7.2" finding was wrong (7.2 has no `FAML`/`FAMR` controller types — its left/right *nescon* support is a different thing). The separate `linux-patches-upstream/` series (carried for the exported `Linux-Kernel_MiSTer` tree only, never applied by Buildroot — `docs/patch-provenance.md` §12) is unrelated to this count and is not applied to the beta either. |
| `Makefile` (`rt`, `rt-clean`, `rt-menuconfig`) | Builds into `output-rt/` (stage-1 initramfs first — its cpio is embedded into every kernel), reusing the shared dl/ccache; then stages the depmod'd module tree into `work/extra-modules-overlay/`, which the main defconfig's `BR2_ROOTFS_OVERLAY` folds into the ONE shipped `linux.img` at the next `make all`. The main `output/` is never touched by `make rt` itself. |

The kernel config is the same `linux.config` + a fragment, and the patch set is
symlinks + a `series` file — editing a shared patch or `linux.config` affects
both kernels automatically. The deliberate copies (the base defconfig's
toolchain/kernel stanzas; the four re-anchored patches) are machine-checked or
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
module trees (`usr/lib/modules/<main kver>/` and `usr/lib/modules/<rt kver>/`,
which is **`7.2.0`** on the current pin and was `7.2.0-rc*` before 2026-08-17 —
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
| **All 40 series entries** (all 36 shared + the 4 beta-local) apply to the pinned **7.2 final** at Buildroot's `patch -F0` (`linux-patches/`; the separate `linux-patches-upstream/` series is never applied to this variant — see §2) | ✅ **re-verified 2026-08-17 on the full 40-entry series**, through Buildroot's own `apply-patches.sh` against a freshly extracted pristine `linux-7.2.tar.xz` whose sha256 matched kernel.org's signed manifest (`f9fef3d1…`): **40/40 applied, exit 0, zero hunks taking fuzz** (80 hunks land at an offset, which `-F0` permits). No re-anchor was needed anywhere: the four re-anchored copies (0001, 0015, 0030, 0037) carry over unchanged and, with all four beta-local patches, land at **zero offset**. The offsets are concentrated where they always were (`0017` 18, `0031` 12, `0033` 5, `0042` 5). **This row now measures the whole series** — the standing "⚠ not evidence about `0038`–`0042`" caveat is retired, because those five are in the series as of the same day (§2). Three measurements were taken that day and each is a strict superset of the last: **34/34** on the rc7 → 7.2 bump (70 offsets), **35/35** once `0046` landed (70 offsets — identical distribution, so `0046` costs the rest of the series nothing), **40/40** with `0038`–`0042` symlinked in (80 offsets, the ten new ones all inside the five added patches). Earlier figures (31/31 on rc5; before that 29/29, and a bogus "28/31" measured at `patch`'s default fuzz 2, which Buildroot forbids) predate the 2026-07-20 `0037`/`0030` re-anchors and the beta-local set. ⚠ Applying is not building — see the next row |
| **`0038`–`0042` compile on 7.2** (the five that had been missing) | ✅ **verified 2026-08-17** — targeted ARM cross-compile of `drivers/hid/`, `drivers/leds/` and `fs/pstore/` on the 40-patch tree with the real config (`merge_config.sh` of `linux.config` + `linux-rt.fragment`, then `olddefconfig`): exit 0, **zero warnings, zero errors**, `hid-nintendo.o` and `hid-playstation.o` — the two files all five patch — both built, as did `fs/pstore/ram.o` for `0046`. `HID_NINTENDO`/`HID_PLAYSTATION`/`HID_SONY` and the `NEW_LEDS`/`LEDS_CLASS` foundation all resolved `=y`, so the 7.x `select`→`depends on` trap did not bite here either. ⚠ This is a subsystem compile, **not** a `make rt`: no zImage, no modules, no size measurement — see the `make rt` row |
| `xone` compiles on 7.2 | ✅ verified (not shipped by the kernel-only variant — §4) |
| **The RT kernel compiles and links** | ✅ **re-verified locally on rc5 (2026-07-28), and again on rc7** (the `output-rt` tree for the pinned 7.2-rc7 holds a linked `zImage`, `CONFIG_PREEMPT_RT=y`, kernel release `7.2.0-rc7`) — see the `make rt` row below, which is the same cross-build end to end. Two 7.x API ports were needed back on rc3 and still live in beta-local patch copies — the shared 6.18 patches stay byte-identical to stock: `fbcon_update_vcs()`'s header moved into fbdev core (beta 0001, one-line include delta), and `exfat_remove_entries()` grew a `free_benign` arg (that one was folded back into the shared patch on 2026-07-25, so beta 0031 is a symlink again). Unlike the rc3 → rc4 bump, which re-verified patch application only and left this row resting on CI, the rc4 → rc5 bump was built locally before the pin was pushed. ✅ **Re-verified on 7.2 final, 2026-08-17**, from a clean `make rt-clean` (both toolchains from scratch, no ccache): exit 0, kernel release string **`7.2.0`**, `CONFIG_PREEMPT_RT=y` in the built tree's `.config`, and `.applied_patches_list` records all **34** series entries as they stood that day — the first time the beta-local `0044`/`0045` have been through a real build rather than an apply-check. No 7.x API port was needed beyond the ones already carried. ⚠ `0046`, and then `0038`–`0042`, landed after this build and are **not** in it: the series is 40 entries now, and this row still measures 34 (§9.6). |
| **Full `make rt` build (kernel-only; zImage links, modules depmod'd)** | ✅ **verified locally on 7.2 final, 2026-08-17**, from a clean `make rt-clean`: exit 0, `CONFIG_PREEMPT_RT=y`, kernel release `7.2.0`, **`zImage_dtb` 9285012 bytes (7492204 bytes of headroom, 44.7%, under the 16 MiB U-Boot budget)**, all `check-zimage-dtb.sh` assertions pass (embedded DTB **21300 bytes** — byte-identical to the standalone `dtc` measurement in §8, reached exactly at EOF), **90 modules** depmod'd and the `7.2.0` tree staged into the extra-modules overlay. The 19 critical config symbols were re-audited present — notably the LED/HID foundation (`NEW_LEDS`/`LEDS_CLASS`/`LEDS_TRIGGERS` → `HID_PLAYSTATION`/`HID_NINTENDO`/`HID_SONY`/`HID_WIIMOTE`), i.e. **the 7.x `select`→`depends on` silent-drop trap did not recur**. Size across pins: rc4 9401461, rc5 10459749, 7.2 final 9285012 — the final release is ~1.17 MB *smaller* than rc5 and lands back near rc4, so rc5 looks like a transient in that tree rather than a growth trend; not investigated, and it moves the budget the safe way. Prior figures on this row were rc5's. Also wired into CI (build.yml + release.yml `build-kernel` matrix, ADR 0021 as amended) — though note CI could not run on this change, see below. ✅ Previously verified 2026-07-28 on **rc5** (the pin at the time) with the complete 31-patch series, from a clean `make rt-clean` (host toolchain rebuilt too, ~16 min on a 32-core box): exit 0, `CONFIG_PREEMPT_RT=y` present in the built tree's `.config`, `zImage_dtb` 10459749 bytes (6317467 bytes of headroom under the 16 MiB U-Boot budget), all `check-zimage-dtb.sh` assertions pass, 90 modules depmod'd and the `7.2.0-rc5` tree staged into the extra-modules overlay (the stale `7.2.0-rc4` tree was removed from both the overlay and `output/target/`, as the stamp mechanism intends). Prior figure on this row was rc4: 9401461 bytes, 7375755 of headroom. Also wired into CI (build.yml + release.yml `build-kernel` matrix, ADR 0021 as amended) |
| **Module-tree merge into the one linux.img** | ✅ **green** — the row's "first green run pending" was overtaken by CI run 29758320422 (2026-07-20, rc4: `build-kernel` + `build` both green, so the merge assert ran). Re-verified locally on rc5 (2026-07-28): after `make rt`, a `make all` produced `output/target/usr/lib/modules/` holding exactly `6.18.40` and `7.2.0-rc5` — two trees, no stale third — and `linux.img` passed every `check-linux-img.sh` assertion (512 MiB, pinned UUID/hash-seed, the 14-feature stock-derived set, ADR 0015 ssh-key checks) |
| **RT kernel boots on the DE10-Nano** | ⚠️ **NOT on the currently pinned 7.2 — re-opened 2026-08-17 by the rc7 → 7.2 bump.** ✅ **CONFIRMED 2026-07-20 on 7.2-rc4**, which booted and ran MiSTer on real hardware. That retired the single biggest open risk on the variant, and it is how the `0037` DualSense regression was caught: booting far enough to use a controller is what exposed the shifted PS5 button map (§7 item 3). ✅ **RE-CONFIRMED 2026-08-14 on 7.2-rc7** — the Wave-1 hardware pass ran on a `7.2.0-rc7 SMP PREEMPT_RT` kernel carrying `0043`, and the doorbell nodes enumerated and delivered events (that pass is also where H-1 and H-2 were found). Boot is a **per-version claim** and every bump re-opens it, which is exactly the state this row is in now: 7.2 final is patch-verified (**40/40** at `-F0`, `0046` and `0038`–`0042` included), DTS-verified, and **built** (`make rt` green from clean, 2026-08-17 — see the build rows above, which measured the 34-entry series those six postdate), but it has **not been booted**. Everything that can be checked without hardware has been checked and passed; none of it is a boot. This ✅ covers rc4 and rc7 and nothing else. It also does **not** cover `0044`, `0045`, `0046` or the newly-symlinked `0038`–`0042`, none of which were in the series when the rc7 kernel was built — §2, §8, §9 |
| **vsync/IRQ-40 latency under RT threaded IRQs** | ❌ **unproven** (the point of the exercise) — boot and general operation are confirmed, but the latency measurement that motivates RT has not been taken |
| `rtw88_8814au` firmware (`rtw88/rtw8814a_fw.bin`) present | ✅ ships via `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88` |

## 7. What is left

0. ~~Build the pinned 7.2 final.~~ **Done 2026-08-17** — `make rt` green from a
   clean `make rt-clean`, carrying the 34 series entries that existed that
   morning, including the beta-local UIO set (§6). `0046` and then `0038`–`0042`
   landed after it, so **the next `make rt` will be the first to build the
   40-entry series** — and it should be run before this variant is called
   green again. That is a build, not a re-verification of patch application:
   application is already measured on 7.2 final at the full 40, and
   `drivers/hid/` compiles with the five re-added patches in (§6).
   **Booting it is still open**, and it is now
   the only thing standing between this variant and the same status it had on rc7.
   `make rt-clean` is mandatory before `make rt` on a version bump — the old
   kernel tree survives in `output-rt/build/` otherwise and the `rt` recipe
   refuses to guess which of two trees to validate. Items 1 and 2 below record
   the same work on earlier `-rc`s; this was that work re-opened by the version
   change, not a new kind of task. It should be the last time it re-opens on a
   merge-window delta: from here the pin moves by 7.2.y point release (§10).
   Note this build was verified **locally only** — GitHub Actions was in a
   major outage on 2026-08-17, so no CI run exists for it.
1. ~~Run `make rt` and fix whatever the first real 7.2 build surfaces.~~
   **Done 2026-07-20** — green on the pinned rc4 with the complete 31-patch
   series (§6). Re-opened for 7.2 final by item 0.
2. ~~Boot `zImage_dtb-rt` on hardware; confirm menu, video/audio/input~~
   **Done 2026-07-20: it boots and runs MiSTer.** Still open, and the actual
   point of the exercise: confirm MiSTer_fb's IRQ-40 vsync still meets the
   50 ms deadline under RT's threaded IRQs (expected to *tighten* pacing —
   measure it).
3. ~~Optionally re-anchor patches `0030` and `0037` to 7.x~~ **Both done
   2026-07-20.** ~~And re-add `0038`–`0042`, which landed in the shared dir on
   2026-07-24 and were never listed in the beta series.~~ **Done 2026-08-17 —
   the beta series now genuinely drops nothing, 40 entries.** That gap sat open
   for three weeks on the assumption the five would need re-anchoring; measured,
   they needed none, and are plain symlinks like the rest (§2, §6). The lesson
   is the cheap one: *measure before assuming a patch needs work*. `0037` was
   never optional.
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
5. **Run the observability validation on hardware** (§9.5). Two things are
   waiting on it, and they are worth separating: whether the `0046` reservation
   actually populates `/sys/fs/pstore` across a warm reset — cheap, step 1, and
   a precondition for trusting any of it — and the genuinely open H-1 question
   of whether a watchdog warm reset clears a dangling AXI transaction (§9.4).
   Until the second is answered, the watchdog is infrastructure that is present
   and off by default, **not** a stated H-1 mitigation.

## 8. The three beta-local UIO patches (0043, 0044, 0045)

There is a fourth beta-local patch, `0046-dts-ramoops`, which is not part of
this set and has its own section (§9): it is observability rather than
FPGA interface, and it shares nothing with these three but the beta-local
constraint described immediately below.

Everything else in the beta series is a MiSTer patch the stock 6.18 build also
gets. These three are the exception: they exist **only** in
`linux-patches-beta/` and are listed only in that directory's `series`, so the
stock build never sees them and its DTS and `drivers/uio/` stay byte-identical
to what they were before this work. That asymmetry is deliberate and is the
constraint the set is written under — the shared `linux-patches/` directory has
no series file, so anything placed there reaches the stock kernel.

They are the kernel half of the Main_MiSTer rewrite's FPGA-interface work
(ADR-002-interim and ADR-003): stop polling the FPGA over the lightweight
bridge, and stop reaching the FPGA's memory through `/dev/mem`.

| Patch | What it adds |
|---|---|
| `0043-dts-uio-doorbells` | Eight interrupt-only `generic-uio` DTS nodes, `mister_doorbell1..8`, on **GIC SPI 48..55** (`f2h_irq8..15`), `IRQ_TYPE_LEVEL_HIGH`. A blocking `read()` on `/dev/uioN` replaces the cause-register spin. |
| `0044-dts-uio-fpga-regions` | Two reg-bearing, interrupt-less `generic-uio` nodes: `mister_lw_window` (the 2 MB lightweight-bridge register window) and `mister_ddr_aperture` (the 512 MiB DDR3 aperture shared with the FPGA over f2sdram). Named, size-bounded mappings instead of `/dev/mem`. |
| `0045-uio-writecombine` | `UIO_MEM_PHYS_WC` — a write-combining page attribute for UIO physical maps — plus the `uio_pdrv_genirq` property parse that selects it. `drivers/uio/uio.c`, `drivers/uio/uio_pdrv_genirq.c`, `include/linux/uio_driver.h`; 25 lines added, 1 changed. |

**The 0043 pool moved from SPI 41..48 to 48..55 (2026-08-14), and that is the
substantive change in this revision.** The original split rested on the premise
that SPI 40 was the only `f2h` line stock gateware drives. It is not: the stock
wrapper drives both low lines, `f2h_irq = {video_sync, HDMI_TX_VS}`
(`sys_top.v:573`), and a live capture on the board measured **60.17 Hz of
events on the SPI-41 node while the other seven pool nodes saw zero events
across 42 s of armed polling**. `uio_pdrv_genirq` cannot share an interrupt at
all — its probe fails outright when `IRQF_SHARED` is set, and a DT-probed node
sets no `irq_flags` — so that node was not merely collecting ~60 Hz of spurious
doorbell wakes, it was permanently denying the line to any future in-kernel
consumer. The node **names** did not move with the numbers, because they are
userspace ABI (`/sys/class/uio/uioN/name`); after the renumber
`mister_doorbell<N>` is a pool ordinal, and the line is `f2h_irq(N+7)` on GIC
SPI `N+47`.

**0044 + 0045 are one unlock in two halves, and the split is a safety
property.** UIO maps `UIO_MEM_PHYS` with unconditional `pgprot_noncached()`,
which on ARMv7 is strongly ordered — correct for registers, and a hard
throughput floor for bulk transfers (measured on silicon: ~100 MB/s write,
~54 MB/s read, 23.3 µs for a 2352-byte sector). `/dev/mem` cannot do better
here whatever flags are passed, because `mem=511M` puts both windows outside
the kernel memory map and ARM's `phys_mem_access_prot()` returns
`pgprot_noncached` unconditionally for `!pfn_valid` ranges (docs/boot-chain.md
§6.4). So 0045 adds the attribute and 0044 asks for it — on the **aperture node
only**, never on the register window, which is why they are two nodes rather
than one node with two maps. Applying 0044 without 0045 is safe: the property
is an unknown DT property, ignored, and the aperture maps strongly ordered.
**The failure direction is deliberate — slow, never cached.** A cached mapping
of memory the FPGA writes without snooping the A9 caches would be silent
corruption rather than lost throughput.

**No new kernel config symbol.** All three ride `CONFIG_UIO=y`,
`CONFIG_UIO_PDRV_GENIRQ=y` and the `uio_pdrv_genirq.of_id=generic-uio` cmdline
token that `board/mister/de10nano/linux-rt.fragment` already carries.
The fragment's comment block was updated in this same change (comment-only:
the stale SPI 41..48 range, the f2h_irq1..8 heading, and the patch-dir
pointer that predated the beta-local move). No `CONFIG_` symbol changed —
the fragment remains config-identical — but a stale allocation-map comment
in the file a maintainer opens first to learn what the RT line adds is exactly
what produced the wrong premise this whole revision corrects. **Needs the owner's
explicit comment-only exception**, which changes no generated config and cannot
perturb the stock build:

1. The section header reads "UIO doorbells: FPGA-to-HPS f2h_irq1..8" — the pool is
   `f2h_irq8..15`.
2. It points at `board/mister/de10nano/linux-patches/0043-dts-uio-doorbells.patch`
   "on GIC SPI 41..48". That path does not exist (0043 became beta-local), and
   41..48 is the exact range this revision retired.
3. The `CONFIG_UIO` justification says "linux-patches/ has no series file, so the
   stock 6.18 build applies every patch in it, this one included" — no longer true,
   and it contradicts 0043's own "applied only by the 7.2 beta series" and this
   section.

### Status

| | Status |
|---|---|
| All three apply to the pinned **7.2 final** at Buildroot's `patch -F0` | ✅ **re-verified 2026-08-17 on 7.2 final**, most recently as part of the full **40-entry** series run against a freshly extracted pristine `linux-7.2.tar.xz` whose sha256 matched kernel.org's signed manifest: exit 0, **zero hunks taking fuzz and zero offsets** for all three. Zero offset is the notable part — it means the release's context around `0004`'s output, `drivers/uio/` and the uio-howto is byte-identical to rc7's where these patches touch it, so the anchors recorded below are still literally correct rather than merely tolerated. ✅ Previously verified 2026-08-14 against `linux-7.2-rc7.tar.gz`, individually (`0004` → `0043` → `0044` → `0045`): every hunk landed at the line its header declares (0043 at 129, 0044 at 280, 0045 at 278/757/866/112/186/210/171). The 0044 anchor moved 271 → 280 back then because 0043's comment grew by 9 lines; both patches' `@@` counts and diffstats were recomputed rather than left to `patch`'s offset tolerance |
| The patched DTS compiles | ✅ **re-verified 2026-08-17 on 7.2 final** (`cpp` + `dtc 1.7.2`, DTB **21300 bytes — byte-count-identical to the rc7 measurement**, and the same 5 pre-existing `socfpga.dtsi` `simple_bus_reg` warnings, no new ones). ✅ Previously verified 2026-08-14 on rc7, where the decompiled assertions below were checked: `mister_doorbell1..8` carry `interrupts = <0x00 0x30..0x37 0x04>` — DT cells 48..55 (GIC INTID 80..87), trigger 4 = `IRQ_TYPE_LEVEL_HIGH`; `MiSTer_fb` still at cell 0x28 (40) trigger 1 = `EDGE_RISING`, untouched; `mister_lw_window@ff200000` = `<0xff200000 0x200000>` and `mister_ddr_aperture@20000000` = `<0x20000000 0x20000000>` with `mister,map-writecombine` present, both exporting bare names via `linux,uio-name`. **No new `dtc` warnings** — measured, not asserted: the warning set is byte-identical to the `0004`-only baseline (5 pre-existing `simple_bus_reg` warnings, all from upstream `socfpga.dtsi`) |
| `checkpatch.pl` on 0045 | ✅ 0 warnings, 0 checks on the code, unchanged by the review fixes. The 6 reported "Invalid commit separator" errors are checkpatch mistaking this repo's underlined header sections for the `---` separator (0043 and 0044 produce 9 and 11 of the same, and nothing else) |
| **The RT kernel builds with the three applied** | ✅ **YES, as of 2026-08-17** — this row was ❌ "apply-checks only, no `make rt` since 0044/0045 were written" until the rc7 → 7.2 build. That build carried all three: `.applied_patches_list` records 34 entries ending `0043` → `0044` → `0045`, the kernel linked, and `0045`'s `UIO_MEM_PHYS_WC` compiled into `drivers/uio/`. It is a **build**, not a probe — the row below is still ❌ |
| **The nodes probe and the WC mapping is faster** | ❌ **unproven, and it is the whole point.** 0043's nodes are hardware-proven (they enumerated and delivered events on rc7), but at the *old* numbering; the renumbered pool, both 0044 nodes and every `UIO_MEM_PHYS_WC` mapping are unexercised. The expectation for write-combining is 2-4× on writes; if it lands under 1.5× the mapping is not the bottleneck and the strongly-ordered floor is simply accepted |
| **Ordering under write-combining** | ❌ unproven, and a *new* hazard rather than an old one: a WC store is not globally visible when the instruction retires, so every publish-then-signal sequence over the aperture must fence before it rings a doorbell. Needs a cross-domain test (write a pattern via WC, raise a doorbell, verify the FPGA side saw all of it) — no host-side test can stand in for it |

**H-1 rule, carried into 0044's node comment because it is a correctness
precondition and not hygiene:** touching an lwhps2fpga offset that no fabric
slave decodes hard-hangs the HPS — no bus fault, no exception, no panic, no
console output, power-cycle-only recovery, confirmed three times on hardware
including once with a serial console attached that logged nothing. Mapping
`mister_lw_window` is safe; probing it is destructive, diagnostics included. A
consumer may touch only offsets a loaded core has declared. **All three
confirmed events were reads**; no write to an undecoded offset has ever been
issued on hardware, but a write also awaits a fabric response through this
mapping, so it is presumed equally lethal and the rule covers every access
type — the measured half is not a scope limit.

**Two preconditions the patches now state explicitly, because both are silent
when violated:**

- **Why `mister_lw_window` may never be write-combining is not (only) ordering.**
  WC is Normal memory, and ARMv7 permits speculative reads from Normal memory
  while forbidding them to Strongly-ordered memory. A WC mapping of a 2 MB window
  where undecoded reads hard-hang would let the CPU hang the board off a
  mispredicted path, with the program never issuing a bad access. Mapping that
  window is safe *because* it is strongly ordered. Fencing correctly does not buy
  back the right to relax it — which the earlier ordering-only rationale implied
  it might.
- **Mappings must be `MAP_SHARED`.** UIO does not check the flags (no `VM_SHARED`
  test anywhere in `drivers/uio/uio.c`), so a `MAP_PRIVATE` mmap is accepted,
  COWs on first write, and diverts every store into anonymous RAM the FPGA never
  sees — while reads still return real memory, so a read-back self-test through
  the same mapping still passes. Pre-existing UIO/`/dev/mem` behaviour, but 0044
  is where the mapping contract is being written down, so the flag is pinned in
  its node comment and belongs in the HAL's `map` contract too.

**Also decided here:** the doorbell spec's **OPEN-4** (node naming after the
renumber) is resolved in favour of keeping `mister_doorbell1..8` as pool
ordinals, with the rationale and the rejected alternative stated in 0043's
header. The spec's own OPEN register lives outside this repo and still needs
that closure recorded.

~~⚠ **Out of this change's scope, for the owner:** `configs/mister_rt.fragment`
carries the same staleness in its comments — line 31 "Validated against
7.2-rc5" and line 54 "all 31 listed patches apply to 7.2-rc5" — while the
symbol on line 38 pins `7.2-rc7`.~~ **Fixed 2026-08-17** with the rc7 → 7.2
bump: both comments now describe the pinned version and the series, which
reached 35 entries when `0046` landed (§9).

## 9. Observability: the crash record (0046) and the watchdog open question

The Wave-1 hardware pass produced one finding that no amount of care would have
softened: **H-1 hung the board three times and left nothing behind.** No bus
fault, no exception, no panic (`panic=15` never fired), no network — and on the
third event, with a serial console attached and capturing, **zero bytes of
output**. Three investigations each had to rediscover by bisection what the
board had been doing. The finding's own conclusion was that "one DT node would
have said all of this on the first event".

This section is that node, plus the honest accounting of what it does and does
not buy, plus the one mitigation that could turn the failure class from
power-cycle-only into something recoverable — and the open question that stops
us from claiming it already does.

### 9.1 `0046-dts-ramoops` — what it reserves and why there

A `/reserved-memory` `ramoops` node at **`0x1FE00000`, size `0x100000`** — the
last mebibyte of RAM the kernel is allowed to touch.

The address is forced from both ends (`docs/boot-chain.md` §6.4 has the
arithmetic):

| Address | What owns it |
|---|---|
| `0x1FE00000` | **this region**, 510 MiB |
| `0x1FF00000` | the `mem=511M` cap — `early_mem()` discards the DTB's memory node and adds back exactly `[0, 0x1FF00000)`. The token comes from stock U-Boot's `CONFIG_BOOTARGS`, which this tree does not own |
| `0x1FFFF000` | MiSTer's shmem mailbox (`Main_MiSTer fpga_io.cpp:398`) |
| `0x1FFFFF08` | MiSTer's warm-boot flag |
| `0x20000000` | the 512 MiB DDR3 aperture shared with the FPGA (`mister_ddr_aperture`, §8) |

So everything at or above the cap is already spoken for — by MiSTer userspace or
by the FPGA — and none of it is memory the kernel may reserve in the first
place. That leaves `[0, 0x1FF00000)`, and within it the **top is the only
placement that costs nothing**: a region lower down punches a hole the linear
map has to work around, while a region at the top merely shortens lowmem by
1 MiB. `0x1FE00000` is 2 MiB-aligned (`PMD_SIZE` on ARM without LPAE), so the
linear map still ends on a clean PMD boundary.

Checked free rather than assumed free: no CMA area exists (`CONFIG_DMA_CMA` is
not set, so `dma_contiguous_reserve()` reserves nothing); the only other static
reservation on this SoC is `socfpga_cyclone5.dtsi`'s `/memreserve/` of the first
4 KiB for the secondary-core trampoline; `MiSTer_fb` takes its memory from the
FPGA aperture (`MiSTer_fb@22000000`), not from kernel RAM; and no Main_MiSTer
`shmem_map()` call names an address in the range.

**The split.** ramoops carves the region in probe order — dmesg from the base,
then console, then pmsg, then ftrace (`fs/pstore/ram.c ramoops_probe`) — so
1 MiB becomes, with no remainder:

| Offset | Size | Area | Property |
|---|---|---|---|
| `0x1FE00000` | `0x0B8000` | dmesg, **23 records × 32 KiB** | `record-size = <0x8000>` |
| `0x1FEB8000` | `0x040000` | console, **256 KiB** | `console-size = <0x40000>` |
| `0x1FEF8000` | `0x008000` | pmsg, **32 KiB** | `pmsg-size = <0x8000>` |
| `0x1FF00000` | — | == the cap | — |

`dump_mem_sz = size − console − ftrace − pmsg` = `0x100000 − 0x40000 − 0x8000`
= `0xB8000`, and `0xB8000 / 0x8000 = 23` exactly.

- **`record-size` 32 KiB** must be a power of two — ramoops silently applies
  `rounddown_pow_of_two()` otherwise, wasting nearly half the dmesg area without
  logging anything. 32 KiB is sized against `PSTORE_DEFAULT_KMSG_BYTES` (10240),
  which caps a single kmsg dump: a whole dump fits with 3× headroom *before*
  `PSTORE_COMPRESS` deflates it, so a record is never what truncates a crash.
  23 retained records means a reboot loop does not immediately overwrite the
  first and most informative one.
- **`console-size` 256 KiB** is the largest share, deliberately, because it is
  the area that pays off for a *silent* failure. It is written as printk
  produces output, not on the crash path.
- **`pmsg-size` 32 KiB** is `/dev/pmsg0`, deliberately small: it is for "which
  offset am I about to touch", not for logging.
- **`ftrace-size` 0** is stated rather than omitted so the four numbers can be
  checked against the arithmetic without knowing the binding's defaults.
  `PSTORE_FTRACE` stays unset even though its dependencies are already met —
  `FUNCTION_TRACER=y` and `DEBUG_FS=y` come from the shared `linux.config` and
  survive the merge, and `PSTORE_FTRACE` only `depends on` them (it selects
  nothing) — because a fourth zone would shrink the three that serve H-1, for
  a per-function-call tracing job unrelated to it.
- **`ecc-size`** absent (0): Reed-Solomon ECC costs CPU per record write and
  defends against bit rot in DRAM that lost refresh — not against the failure
  that matters here, which is whether the last stores reached DRAM at all.
- **`max-reason = <3>`** is `KMSG_DUMP_EMERG`. The default is 2
  (`KMSG_DUMP_OOPS`); 3 additionally catches emergency restart at no cost, while
  4 or 5 would write a record on every clean shutdown and rotate real crashes
  out of a 23-deep ring inside a day of ordinary use.

**Config.** `linux-rt.fragment` gains exactly four symbols, each justified in
place: `CONFIG_PSTORE`, `CONFIG_PSTORE_RAM`, `CONFIG_PSTORE_CONSOLE`,
`CONFIG_PSTORE_PMSG`. All `=y`, not `=m` — the failures worth recording are as
likely during boot as after it. `REED_SOLOMON*` arrive by `select`;
`PSTORE_COMPRESS=y` is inherited as a Kconfig default; `PSTORE_FTRACE` stays
unset. Beta-only for the same reason as the UIO set: the node lives only in the
beta series, so setting these on stock would give that kernel a pstore
subsystem with nothing to bind to — and putting the *node* on stock would
reserve 1 MiB of every user's RAM for a subsystem that is not compiled in.

### 9.2 What it buys, stated precisely

The honest version matters more than the flattering one, because the flattering
one would get this node trusted for a job it cannot do.

**For an H-1-class hang there is no kmsg dump to take.** The kernel never
reaches its die path, `kmsg_dump()` is never called, and the 23 dmesg records
stay empty for exactly the failure that motivated the node.

What survives is:

- **the console area** — everything printk emitted up to the hang, including the
  tail that was still sitting in the UART FIFO when the port stopped being
  serviced; and
- **the pmsg area** — whatever the userspace tool wrote to `/dev/pmsg0` before
  it made the fatal access. A probe tool that writes *"about to read LW +0x14"*
  before issuing the read converts a silent brick into a named offset, which is
  the single fact all three H-1 investigations spent their time recovering by
  bisection.

The dmesg records are for the ordinary oops and panic this board can also
produce, which today are equally unrecoverable if it never gets far enough to
write them to the card. Both jobs are wanted; that is why the region is split
three ways rather than given whole to either.

**And there is a hard limit.** DRAM keeps its contents across a *warm* reset,
and neither U-Boot nor the kernel writes this range on the way back up (U-Boot
loads the zImage at `0x01000000` and relocates itself to the top of the full
1 GiB; the kernel reserves the region before the allocator runs). A **power
cycle** is different: refresh stops and the contents decay over seconds. H-1
hangs were power-cycle-only recoveries — so for that exact failure this node
yields a **best-effort** record, not a guaranteed one.

That limit is the entire reason the next subsection exists. A best-effort record
still beats three empty logs, but the way to make it reliable is to stop needing
the power cycle.

**Harvesting.** Nothing appears by itself:

```sh
mount -t pstore pstore /sys/fs/pstore
ls /sys/fs/pstore          # dmesg-ramoops-N, console-ramoops-0, pmsg-ramoops-0
```

Records persist until removed with `rm`, which is what frees the slot for the
next crash — a harvest step that forgets to delete will eventually stop
recording new ones.

### 9.3 The watchdog: already present, deliberately inert, and NOT patched

**There is no `0047`, and that is a finding rather than an omission.** The
obvious next move after 0046 is "add a watchdog patch". It was checked against
the kernel source before being written, and every piece already exists:

| Piece | Where it already is |
|---|---|
| DT nodes | `arch/arm/boot/dts/intel/socfpga/socfpga.dtsi` — `watchdog0@ffd02000` and `watchdog1@ffd03000`, `compatible = "snps,dw-wdt"`, both `status = "disabled"` there |
| Node enabled | `arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5.dtsi` — `&watchdog0 { status = "okay"; };`, upstream, included by our `.dts` |
| Driver | shared `board/mister/de10nano/linux.config` — `CONFIG_WATCHDOG=y`, `CONFIG_DW_WATCHDOG=y` (and `WATCHDOG_CORE=y` by `select`) |

So **`/dev/watchdog0` exists on both kernels today**, stock 6.18 included. There
was nothing to enable, so nothing was invented: no patch, and **no symbol added
to `linux-rt.fragment`** — only a `NOTE` recording the check so the next person
does not add `CONFIG_DW_WATCHDOG=y` a second time and conclude they enabled
something.

**A bound driver that is never opened does nothing, and that is the safe
default.** This is a property of the code, not an assumption:

- `dw_wdt_probe()` never calls `dw_wdt_arm_system_reset()`. In a running system
  the `WDT_EN` bit in `WDOG_CONTROL_REG` is set only by `dw_wdt_start()`, which
  the watchdog core reaches from `open()` on the chardev. (The one other writer
  is `dw_wdt_restart()`, the driver's registered restart handler — it runs only
  on the reboot path, when the system is already resetting by intent; it is a
  mechanism for an orderly restart, not a change in unfed boot behaviour.)
  Probe writes the timeout register and registers the device; the counter is
  not armed.
- `CONFIG_WATCHDOG_OPEN_TIMEOUT=0` — the core does **not** start an
  "open me within N seconds or reset" timer.
- `CONFIG_WATCHDOG_NOWAYOUT` is **not** set, so a clean close (the `V` magic
  character) stops the timer; a feeder can be started and stopped at will.
- `watchdog_stop_on_reboot()` is called in probe, so an orderly reboot stops it.
- `CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED=y` covers the one case where the
  hardware *is* already counting at probe (a bootloader that armed it): the core
  adopts it (`WDOG_HW_RUNNING`) and pings it from a kernel worker until
  userspace opens the device — so even then it does not reset the board on its
  own.

The net effect is that arming the watchdog is a **userspace opt-in**: open
`/dev/watchdog0` and feed it. Boot behaviour is unchanged when nothing does.

### 9.4 OPEN QUESTION (H-1): does a warm reset actually clear a dangling AXI transaction?

The reason to want the watchdog for H-1 specifically is that it does not depend
on a working CPU: the L4 watchdog is clocked from `osc1` and counts down whether
or not the cores are making progress, so a feeder that dies with the CPU is
exactly the trigger wanted.

**What is not known is whether its reset recovers this particular failure.** In
an H-1 hang the CPU is stalled waiting for a read response from the lwhps2fpga
interconnect that will never arrive, and the symptoms (both cores dead, no
network) point at the L3 interconnect being blocked rather than one core being
stuck. A watchdog warm reset resets the CPUs; whether it also resets the
*bridge* — and so retires the outstanding transaction — depends on what the
reset manager asserts on a watchdog event, and we have not established that on
this silicon.

The three outcomes are materially different and none is currently ruled out:

1. **Warm reset recovers.** The board reboots to a shell, and pstore is readable
   with the pmsg breadcrumb intact. H-1 stops being power-cycle-only, and 0046's
   record becomes reliable rather than best-effort for this class.
2. **Warm reset fires but the board re-wedges** during U-Boot or early kernel, at
   the first bridge access. The stall survived the reset; the watchdog is no help
   for H-1 (still useful for ordinary hangs), and external power control remains
   the only mitigation class — which is what the Wave-1 finding already suspected.
3. **The reset never happens.** Something about the stalled state prevents the
   reset from completing. Worth knowing, and it would close the question hardest.

Until this is settled, **do not describe the watchdog as an H-1 mitigation** —
describe it as infrastructure that is present, off by default, and untested
against H-1.

### 9.5 On-device test plan for §9.4

Destructive by construction: it deliberately hangs the board. Run it with MiSTer
stopped, a known core loaded, and a **serial console attached and logging** —
the network is the first thing to die, so anything the test learns arrives over
the wire or not at all. `lw-latency` refuses to run without `--offset` **and** an
explicit `--core-decodes-this` attestation, which this test supplies knowingly.

**Step 0 — prove the instrument before trusting it (no hang yet).**
Otherwise a null result in step 2 is unattributable.

- `ls /dev/watchdog0`; read `/sys/class/watchdog/watchdog0/{state,timeout,bootstatus}`
  and the boot `dmesg` line, to establish whether the bootloader left the timer
  running (the `WATCHDOG_HANDLE_BOOT_ENABLED` case) or whether it is idle.
- Open the device, set a short timeout (15 s), feed it, then **stop feeding
  without closing cleanly**. The board must reset at ≈T+timeout. This proves the
  timer, the reset path, and the timeout value — with no bus stall anywhere near
  it. If this fails, stop: everything after it is uninterpretable.

**Step 1 — prove pstore across a warm reset.**

- `mount -t pstore pstore /sys/fs/pstore`, `rm -f /sys/fs/pstore/*`.
- Write a known string to `/dev/pmsg0`; `echo c > /proc/sysrq-trigger` (panic).
- After the reboot: `dmesg-ramoops-0` must hold the panic and `pmsg-ramoops-0`
  the string. This calibrates *both* frontends on a failure the kernel survives
  long enough to record, so step 2 can attribute any absence to the hang rather
  than to a broken reservation.

**Step 2 — the experiment: hang with the watchdog fed.**

- Feeder running with a short timeout (15 s), pstore mounted and emptied.
- Write a breadcrumb naming the exact target to `/dev/pmsg0`, e.g.
  `H1-TEST lw-latency --offset 0x00 t=<timestamp>`, and **`fsync`/`write()`
  before** the hazardous call — pmsg is a plain write, so ordering is the
  caller's job.
- Trigger the hang (undecoded LW offset, menu core loaded).
- Record, from the serial console and a wall clock:
  - **(a)** does a reset occur at ≈T+timeout?
  - **(b)** if it resets: does U-Boot print? does the kernel boot? does a shell
    come back? → outcome 1 if yes;
  - **(c)** if it resets and then dies again: **where** — U-Boot banner then
    silence (bridge stall survived, killed at the first bridge touch) vs no
    output at all (the reset did not take) → outcome 2 vs 3;
  - **(d)** if nothing happens by T+3×timeout → outcome 3.
- On any successful boot: read all of `/sys/fs/pstore` and record whether the
  pmsg breadcrumb survived, and how much console history came back with it.

**Step 3 — the power-cycle comparison (the control).**

Repeat the *identical* hang with **no feeder running**, then recover by pulling
power, and compare against step 2:

- **Recovery:** power cycle always works (already known). The delta being
  measured is solely whether the warm reset also worked.
- **Record survival:** this is the part that cannot be inferred. Compare
  `/sys/fs/pstore` contents after a warm reset (step 2) against after a power
  cycle, with the interval between power-off and power-on recorded — DRAM decays
  over seconds, so a fast cycle may preserve the breadcrumb and a slow one will
  not. Run it at a few intervals (immediate, 10 s, 60 s) to find where the
  record stops being readable on this board. That number is what tells a future
  operator whether "pull power fast" is worth doing at all.

**Step 4 — is the recovered state actually clean?** Only if step 2 gave outcome
1: after the watchdog recovery, run the Wave-1 A1/A2 probes (`mmio-probe`,
`gpi-sample`) and then trigger H-1 a *second* time. A recovery that boots but
cannot survive a repeat is outcome 2 wearing outcome 1's clothes.

**What each result changes.** Outcome 1: the watchdog becomes a documented
development mitigation, an opt-in feeder is worth shipping for the RT line, and
0046's record is upgraded from best-effort to reliable for this class. Outcomes
2 and 3: record it plainly, stop proposing the feeder as an H-1 answer, and
leave external power control as the only mitigation class — with 0046 still
earning its place, because a best-effort record beats three empty logs.

### 9.6 Status

| | Status |
|---|---|
| `0046` applies to the pinned **7.2 final** at Buildroot's `patch -F0` | ✅ **re-verified 2026-08-17 on 7.2 final** — full **40-entry** series through Buildroot's own `apply-patches.sh` against a freshly extracted pristine `linux-7.2.tar.xz` (sha256 `f9fef3d1…`, the value `linux.hash` transcribes from kernel.org's PGP-signed manifest): **40/40, exit 0, zero fuzz**, and `0046` lands at the line its header declares with **zero offset**. An intermediate 35-entry run showed the offset distribution unchanged from the pre-`0046` 34-entry one, so `0046` costs the rest of the series nothing (§6). ✅ Previously verified 2026-08-14 on **7.2-rc7**, the pin at the time, same shape against `linux-7.2-rc7.tar.gz`. This row was re-opened by the rc7 → 7.2 bump and is closed again |
| `0046` is independent of `0043`/`0044` | ✅ **verified** — it anchors on `memory@0`, which sits above everything those two insert and which no patch in the series modifies. Applied to a `0004`-only tree it lands at the same line, zero offset |
| The patched DTS compiles | ✅ **re-verified 2026-08-17 on 7.2 final** (`cpp` + `dtc 1.7.2`, exit 0). DTB **21300 → 21574 bytes** — the same 274-byte delta and the same absolute size as on rc7, and 21300 is exactly what §6's `make rt` row measured for the pre-`0046` series. The dtc warning set is **byte-identical** to the pre-`0046` baseline — the same five pre-existing `simple_bus_reg` warnings from upstream `socfpga.dtsi`, no new `unit_address_vs_reg` |
| The node is in the DTB as intended | ✅ decompiled: `reserved-memory` with `#address-cells`/`#size-cells` = 1 and `ranges`, holding `ramoops@1fe00000` with `reg = <0x1fe00000 0x100000>`, `record-size 0x8000`, `console-size 0x40000`, `pmsg-size 0x8000`, `ftrace-size 0`, `max-reason 3`. `memory@0`, `MiSTer_fb@22000000`, the eight doorbells and both UIO region nodes unchanged |
| The four `PSTORE` symbols survive `olddefconfig` | ✅ **verified** — `merge_config.sh` (`linux.config` + `linux-rt.fragment`) then `make ARCH=arm olddefconfig` on the pristine tree: all four stay `=y`, `REED_SOLOMON`/`_ENC8`/`_DEC8` arrive by `select`, `PSTORE_COMPRESS=y` and `PSTORE_DEFAULT_KMSG_BYTES=10240` are inherited, `PSTORE_FTRACE` stays unset. This is the check the LED `select`→`depends on` trap of §6 exists to demand |
| The watchdog needs no patch and no symbol | ✅ **verified from source, not assumed** — DT node enabled upstream in `socfpga_cyclone5.dtsi`, `CONFIG_WATCHDOG=y` + `CONFIG_DW_WATCHDOG=y` already in the shared `linux.config`, resolved `=y` in the same `olddefconfig` run alongside `WATCHDOG_CORE=y`, `WATCHDOG_HANDLE_BOOT_ENABLED=y`, `WATCHDOG_OPEN_TIMEOUT=0`, `WATCHDOG_NOWAYOUT` unset |
| **The RT kernel builds with `0046` applied** | ❌ **not yet** — apply-check, DTS compile and config-merge only. §6's green `make rt` row is the **34-entry** series from 2026-08-17, taken before `0046` existed; no `make rt` has run with it in |
| **The reservation survives a real boot** | ❌ **unproven.** Nothing here has run on hardware: that `pfn_valid()` is true for the region and ramoops takes the `vmap()` write-combining path, that the region does not collide with anything the running kernel wants, and that `/sys/fs/pstore` populates at all are all read off the source. §9.5 step 1 is the cheapest possible first confirmation |
| **Records survive a warm reset** | ❌ unproven — §9.5 step 1 |
| **Records survive a power cycle, and for how long** | ❌ unproven, and expected to be a *duration*, not a yes/no — §9.5 step 3 |
| **A watchdog warm reset clears an H-1 AXI stall** | ❌ **THE open question** — §9.4. Do not describe the watchdog as an H-1 mitigation until §9.5 answers it |

## 10. What the pin tracks, and why that changed at 7.2

Until 2026-08-17 this pin followed **mainline**: whatever `kernel.org`'s
`releases.json` called `moniker=mainline`, which for the whole life of the
variant meant a rolling `7.2-rcN`. That was the right target while 7.2 was in
development and it stopped being right the moment 7.2 shipped, because mainline
does not stay on a release — it becomes `7.3-rc1` within about two weeks. Left
alone, the automation would have proposed dragging the variant off the line it
had just spent months reaching, back into permanent `-rc` churn, roughly a
fortnight after arriving.

**The pin now tracks the 7.2 line: `7.2`, then `7.2.1`, `7.2.2`, …** Moving to
7.3 or later is a deliberate human edit in two places (`renovate.json`'s
`kernelStable72` datasource and the matching `allowedVersions`), which is the
same shape the 6.18 longterm pin has always had. §1's reasoning is unchanged
and is what makes 7.2 a destination rather than a waypoint: `PREEMPT_RT` for
ARM32 landed in 7.1, so any 7.x is sufficient, and there is nothing the variant
needs from 7.3 that 7.2 lacks.

Three consequences worth having written down:

1. **The bump cadence drops sharply.** `-rc`s arrive weekly; 7.2.y point
   releases arrive every week or two at first and then taper. More to the
   point, each one is a backported-fixes release rather than a merge-window's
   worth of churn, so the "boot is re-opened by every bump" tax (§6) gets much
   cheaper to pay even though it does not go away.
2. **The hash is now auto-refreshed**, where it was always manual before. Not a
   relaxation: an `-rc` is a cgit snapshot kernel.org signs nothing for, so its
   hash could only ever be hand-written TOFU, whereas `linux-7.2.tar.xz` is
   covered by the signed `sha256sums.asc`. `hash-sync-kernel.sh --pin=rt` does
   it, and still refuses any `-rc` outright. See
   [`docs/renovate.md`](renovate.md) and
   [`docs/ci.md#renovate-hash-sync-not-automated`](ci.md#renovate-hash-sync-not-automated).
3. **There is a silent tripwire at end-of-life.** When the 7.2 line is dropped
   from `releases.json`, the datasource filter matches nothing and Renovate
   reports `no-result` — a silent no-op, not an error. The pin simply stops
   being managed, with no PR and no red X to notice. If this pin has been
   still for a long stretch, check the dependency dashboard rather than
   assuming upstream has been quiet; that is the moment to choose the next
   line deliberately.

See also: the RT-feasibility and 7.2-port findings in the project memory / the
session that produced this scaffold.
