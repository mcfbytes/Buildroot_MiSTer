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

## 2. The "thin shim" structure — no duplicated Buildroot config

The main 6.18 build is untouched. The variant is the base defconfig plus a small
fragment, layered at build time — mirroring the existing initramfs second-build.

| File | Role |
|---|---|
| `configs/mister_rt.fragment` | Buildroot-config delta (kernel version → 7.2-rc3 via Buildroot's native `-rc` handling; beta patch dir; kernel-config fragment; disable the 3 OOT WiFi packages). Merged onto `mister_de10nano_defconfig` via `merge_config.sh`. |
| `board/mister/de10nano/linux-rt.fragment` | Kernel-config delta layered on the shared `linux.config`: `CONFIG_PREEMPT_RT=y` (RTL8814AU's in-kernel driver comes from `linux.config` itself, inherited — not duplicated here). |
| `board/mister/de10nano/linux-patches-beta/` | `series` file + **symlinks** to the shared `linux-patches/` (single source of truth). Applies 28 of the 31 *carried* patches (§4 lists the 3 excluded) — the separate `linux-patches-upstream/` series (patches carried for the exported `Linux-Kernel_MiSTer` tree only, never applied by Buildroot; see `docs/patch-provenance.md` §12) is unrelated to this count and is not applied to the beta either. |
| `Makefile` (`rt`, `rt-clean`, `rt-menuconfig`) | Builds into `output-rt/`, reusing the shared toolchain/dl/ccache. The main `output/` is never touched. |

Nothing is copied: the kernel config is the same `linux.config` + a 2-line
fragment, and the patch set is symlinks + a `series` file. Editing a shared
patch or `linux.config` affects both builds automatically.

## 3. Kernel headers / userland ABI — unchanged

`BR2_KERNEL_HEADERS_6_18=y` is inherited from the base defconfig. That knob is
independent of the kernel *version* being built, so the RT variant's userland is
still compiled against **6.18 headers** — identical ABI. A 7.2 kernel runs that
userland fine (Linux never breaks userspace), and `PREEMPT_RT` is UAPI-transparent
(kernel-internal scheduling/locking; no new syscalls). If you build `rt` as a
full image, its rootfs is byte-for-byte the main build's userland.

## 4. WiFi on the beta

The three out-of-tree morrownr drivers (`rtl8812au`, `rtl8814au`, `rtl8821au`)
**do not build on 7.x**: Linux 7.1 refactored the cfg80211 op-table
(`net_device*` → `wireless_dev*`), and morrownr's drivers top out at kernel 7.0
(our pins are already at each repo's HEAD — there is no newer commit to bump to).
So they are disabled on this variant.

- **RTL8814AU** is recovered via the **in-kernel** `rtw88_8814au` driver (merged
  upstream in Linux 6.16). This is inherited from the shared `linux.config` — the
  main build migrated that chip in-kernel (`CONFIG_RTW88_8814AU=m`), so the beta
  gets it for free. Firmware `rtw88/rtw8814a_fw.bin` ships via
  `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88`.
- **RTL8812AU / RTL8821AU** have no clean in-kernel equivalent at their chipsets
  and are simply absent here. A developer testing RT can use ethernet or the
  in-kernel `rtw88`/`rtw89`/`rtl8xxxu` adapters that the base config already ships.
- `xone` (Xbox controllers) **builds clean on 7.2** and stays enabled.

If full OOT WiFi on the beta is ever wanted, carry a local
`#if LINUX_VERSION_CODE >= KERNEL_VERSION(7,1,0)` compat patch (reference:
`armbian/wifi-rtl8852bs` PR #5) and upstream it to morrownr — but gate it on the
version code so it stays inert on the shared 6.18 build.

## 5. Build & flash

```sh
make rt                       # -> output-rt/images/zImage_dtb  (the RT kernel)
cp output-rt/images/zImage_dtb  /media/fat/linux/zImage_dtb-rt
```

Select it on-device with a one-line edit to `/media/fat/linux/u-boot.txt`
(U-Boot imports it before loading the kernel — no U-Boot rebuild, stock
`uboot.img` unchanged):

```
bootimage=/linux/zImage_dtb-rt
```

Remove that line to roll back to the stock kernel. The rootfs (`linux.img`) is
shared — no rootfs change is needed to switch kernels.

## 6. What's verified vs unproven

| | Status |
|---|---|
| 7.2 has ARM32 `ARCH_SUPPORTS_RT` in-tree | ✅ verified (`arch/arm/Kconfig`) |
| Config layering (fragment → 7.2 config) resolves | ✅ verified (`merge_config.sh` + `olddefconfig`, clean) |
| `linux.config` reconciles to 7.2 (criticals survive) | ✅ verified |
| 28/31 *carried* patches apply to 7.2-rc3 (`linux-patches/`; excludes the separate `linux-patches-upstream/` series, which this variant does not apply at all — see §2) | ✅ verified |
| `xone` compiles on 7.2 | ✅ verified |
| **Full `make rt` build (kernel links, image builds)** | ❌ **unproven** |
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
4. Wire `zImage_dtb-rt` into `release.yml` as an extra asset in the *same*
   `release_YYYYMMDD.7z` (keep ONE `db.json`/`/MiSTer.version` — ADR 0018).

See also: the RT-feasibility and 7.2-port findings in the project memory / the
session that produced this scaffold.
