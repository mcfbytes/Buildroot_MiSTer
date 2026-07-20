# RT / Linux-7.2 "beta" kernel variant

**Status: SCAFFOLD.** The wiring below is in place and its config/patch layering
is verified, but the variant has **never been built end-to-end or booted on
hardware**. It is intended for **developer testing of PREEMPT_RT and new-kernel
features**, not general use. WiFi via the out-of-tree Realtek drivers is
deliberately dropped on this variant (see §4).

---

## 1. Why 7.2, and why a separate kernel

The DE10-Nano's Cyclone V is a dual-core **Cortex-A9 (ARMv7-A, 32-bit)** — there
is no AArch64 path on this silicon. `PREEMPT_RT` for 32-bit ARM merged into
mainline in **Linux 7.1**, so on **7.2** `arch/arm/Kconfig` already
`select ARCH_SUPPORTS_RT` (verified) — meaning RT is a plain kconfig option here,
**no out-of-tree RT patch to carry**. `EXPERT=y` is inherited from
`linux.config`, so `CONFIG_PREEMPT_RT=y` is all it takes.

RT cannot be a boot-time toggle on ARM32 (no `PREEMPT_DYNAMIC`/static-calls), so
it must be a **separately compiled kernel image** — shipped as `zImage_dtb-rt`
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
| `configs/mister_rt.fragment` | Buildroot-config delta (kernel version → the 7.2 mainline line, currently `7.2-rc4`, via Buildroot's native `-rc` handling; beta patch dir; kernel-config fragment). Merged onto `mister_kernel_defconfig` via `merge_config.sh`. |
| `board/mister/de10nano/linux-rt.fragment` | **Kernel**-config delta layered on the shared `linux.config`: `CONFIG_PREEMPT_RT=y` — do not confuse the two fragment layers (RTL8814AU's in-kernel driver comes from `linux.config` itself, inherited — not duplicated here). |
| `board/mister/de10nano/linux-patches-beta/` | `series` file + **symlinks** to the shared `linux-patches/` — except `0001`, `0015` and `0031`, which are real re-anchored copies (Buildroot patches at `-F0`; their 6.18 context or APIs drifted on 7.x — see the series header). The shared 6.18 patches stay byte-identical to stock. Applies 29 of 31 patches. `0015` is re-INCLUDED: the earlier "upstreamed in 7.2" finding was wrong (7.2 has no `FAML`/`FAMR` controller types — its left/right *nescon* support is a different thing). The separate `linux-patches-upstream/` series (carried for the exported `Linux-Kernel_MiSTer` tree only, never applied by Buildroot — `docs/patch-provenance.md` §12) is unrelated to this count and is not applied to the beta either. |
| `Makefile` (`rt`, `rt-clean`, `rt-menuconfig`) | Builds into `output-rt/` (stage-1 initramfs first — its cpio is embedded into every kernel), reusing the shared dl/ccache; then stages the depmod'd module tree into `work/extra-modules-overlay/`, which the main defconfig's `BR2_ROOTFS_OVERLAY` folds into the ONE shipped `linux.img` at the next `make all`. The main `output/` is never touched by `make rt` itself. |

The kernel config is the same `linux.config` + a fragment, and the patch set is
symlinks + a `series` file — editing a shared patch or `linux.config` affects
both kernels automatically. The deliberate copies (the base defconfig's
toolchain/kernel stanzas; the two re-anchored patches) are machine-checked or
lockstep-annotated, not trusted: the sync script covers the former, and each
re-anchored patch carries a bracketed note naming its `linux-patches/`
original.

Adding a future kernel variant `foo`: `configs/mister_foo.fragment`, `foo`/
`foo-clean`/`foo-*` Makefile targets mirroring the `rt` ones, and one entry in
the CI workflows' `kernel:` matrix list. Everything else derives from the name.

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
module trees (`usr/lib/modules/6.18.38/` and `usr/lib/modules/7.2.0-rc3*/` —
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
`linux-rt.config`, `legal-info-rt.tar.gz` (the kernel GPL-source bundle) — in
`SHA256SUMS`, provenance-attested (the kernel binary), carried on the sdcard
installer's FAT payload as well, and deliberately NOT inside
`release_YYYYMMDD.7z` nor referenced by db.json.

## 6. What's verified vs unproven

| | Status |
|---|---|
| 7.2 has ARM32 `ARCH_SUPPORTS_RT` in-tree | ✅ verified (`arch/arm/Kconfig`) |
| Config layering (fragment → 7.2 config) resolves | ✅ verified (`merge_config.sh` + `olddefconfig`, clean) |
| `linux.config` reconciles to 7.2 (criticals survive) | ✅ **after a real fix (2026-07-18)**: the earlier full-config test masked a minimal-config trap — 7.x turned the HID drivers' LED `select`s into `depends on`, so `olddefconfig` silently dropped `NEW_LEDS`/`LEDS_CLASS` **and with them the whole HID controller stack** (`HID_PLAYSTATION`/`HID_NINTENDO` vanished from the config, no error). Fixed by making the LED foundation explicit in `linux.config` (`NEW_LEDS`/`LEDS_CLASS`/`LEDS_TRIGGERS`, no-ops on 6.18); all 19 critical symbols re-audited present |
| 29/31 *carried* patches apply to 7.2-rc4 at Buildroot's `patch -F0` (`linux-patches/`; the separate `linux-patches-upstream/` series is never applied to this variant — see §2) | ✅ re-verified on the rc3 → rc4 bump (2026-07-20) through Buildroot's own `apply-patches.sh`: 29/29 applied, exit 0, zero hunks taking fuzz (offsets shift, which `-F0` permits). Originally verified on rc3 through the real `linux-patch` stage (0015 + 0031 re-anchored; the old "28/31" figure was measured at `patch`'s default fuzz 2, which Buildroot forbids, and wrongly counted 0015 as upstreamed) |
| `xone` compiles on 7.2 | ✅ verified (not shipped by the kernel-only variant — §4) |
| **The RT kernel compiles and links** | ✅ verified 2026-07-18: local cross-build of the patched 7.2-rc3 tree (`CONFIG_PREEMPT_RT=y`) — zImage 8.57 MiB + DTB + 70 modules, zero errors. Two 7.x API ports were needed and live in beta-local patch copies — the shared 6.18 patches stay byte-identical to stock: `fbcon_update_vcs()`'s header moved into fbdev core (beta 0001, one-line include delta), and `exfat_remove_entries()` grew a `free_benign` arg (beta 0031). (Local build without the embedded initramfs cpio — CI's zImage will be larger.) **Not re-run locally for the rc3 → rc4 bump (2026-07-20)**: that bump re-verified patch application only, so the compile/link claim for the currently pinned rc4 rests on CI's kernel leg, not on a local build. |
| **Full `make rt` build (kernel-only; zImage links, modules depmod'd)** | ⏳ wired into CI (build.yml + release.yml `build-kernel` matrix, ADR 0021 as amended); **first green run pending** |
| **Module-tree merge into the one linux.img** | ⏳ wired (extra-modules overlay + CI merge assert); **first green run pending** |
| **RT kernel boots on the DE10-Nano** | ❌ **unproven** |
| **vsync/IRQ-40 latency under RT threaded IRQs** | ❌ **unproven** (the point of the exercise) |
| `rtw88_8814au` firmware (`rtw88/rtw8814a_fw.bin`) present | ✅ ships via `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88` |

## 7. TODO before this is more than a scaffold

1. Run `make rt` and fix whatever the first real 7.2 build surfaces.
2. Boot `zImage_dtb-rt` on hardware; confirm menu, video/audio/input, and that
   MiSTer_fb's IRQ-40 vsync still meets the 50 ms deadline under RT's threaded
   IRQs (expected to *tighten* pacing — measure it).
3. Optionally re-anchor patches `0030` and `0037` to 7.x and add them to the
   beta `series` (they were dropped only to keep the first build clean).
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
