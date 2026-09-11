# Memo Q9 — AIC8800 Wi-Fi/BT driver (`c129b0fac`): package, defer, or decline

**For:** the owner, deciding from this memo alone.
**Item:** `MiSTer-devel/Linux-Kernel_MiSTer` branch `MiSTer-v6.18`, commit
`c129b0fac34ad5d613bbec3f59d6036775e41c83`, Sorgelig, 2026-09-11, subject
"Add AIC8800 WiFi/BT driver." — the current fork HEAD.
**Record:** `docs/kernel-recon/records/c129b0fac34ad5d613bbec3f59d6036775e41c83.json`
(`change_type: out-of-tree-module`, `disposition: needs-verification` — this memo is the
input to the owner's decision, not the decision).

**Grounding caveat (env.md).** Every "vanilla 6.18" statement below is measured against
**6.18.49** (release commit `1c732c6b94f0faee1526bd375add2fe10cba2e26` on `linux-6.18.y`),
not the 6.18.50 the image pins — the gregkh mirror lags one release and kernel.org is blocked
from this session. Every 7.x statement is against **7.2.3** (`58e7295cfecaddec94629160386412e0f2b1e8fe`),
not 7.2.4. Mainline tip is **v7.3-rc2** (`50d05c7c76c96b90462f24debacca971d2e86713`; its
`Makefile` says `VERSION = 7 / PATCHLEVEL = 3 / EXTRAVERSION = -rc2`). Nothing in this memo
turns on a single stable release: the questions are "does mainline have this driver at all"
(no, in three trees) and "does this code compile and what is inside it" (measured directly).

---

## TL;DR — recommendation

**DEFER (option D).** ~~This was the recommendation and it was accepted as owner decision
D2.~~ **REVERSED 2026-09-10 — see §10: the driver and its firmware are now packaged.**
Read the rest of this memo as the analysis that produced the defer, not as current state.
The technical objection is gone — both modules compile **and modpost
clean** for 32-bit ARM (zero errors, zero warnings, `.ko`s in hand at 206,828 B of `.ko.xz`),
and the `rtl8852cu` `__aeabi_uldivmod` trap does **not** recur — but the supply objection is
decisive and unresolved:

> **The driver is inert without ~60 firmware blobs that no source we can verify supplies,
> and the vendor tree ships no license text at all.** Stock's own Release 20260907
> `firmware.tar.gz` contains 104 entries and **zero** of them are AIC files. Packaging today
> would ship a `.ko` that probes, fails to open `/lib/firmware/fmacfw_8800d80_u02.bin`, and
> bails — plus a source tarball with 85 files carrying a bare copyright line and no license
> grant, 2 files under Apache-2.0 (GPLv2-incompatible), and no `LICENSE` file for
> `*_LICENSE_FILES` to point at.

Both blockers are *answerable* — by identifying the upstream repo and its firmware
distribution — and neither needs hardware. That is why this is defer, not decline.

> **Addendum, 2026-09-10 (§9):** the network-gated questions have since been answered. The
> recommendation is unchanged, but three facts are now settled: stock has shipped **no**
> firmware and no release containing the module (§9.1), `linux-firmware` definitively does
> not carry AIC blobs (§9.2), and the exact vendor snapshot *is* identifiable with D80
> firmware publicly available — under a repackager's licence that does not resolve §1.3
> (§9.3). §9.4 adds a packaging trap neither this memo nor stock has accounted for: the
> blobs must live in `/lib/firmware/aic8800D80/`, **not** flat in `/lib/firmware/`.

---

## 1. Provenance and license

### 1.1 What it is

142 files, 82,330 insertions (the PLAN's §2.9 estimate of "143 files, ≈70 k" is close but
low; re-derive from `git -C <fork> show --numstat c129b0fac`):

| Path | Files | Added |
|---|---:|---:|
| `drivers/net/wireless/aic8800/aic8800_fdrv/` | 111 | 74,466 |
| `drivers/net/wireless/aic8800/aic_load_fw/` | 24 | 7,596 |
| `drivers/net/wireless/aic8800/aic_zlp_quirk/` | 2 | 235 |
| `drivers/net/wireless/aic8800/{Kconfig,Makefile}` | 2 | 27 |
| `drivers/net/wireless/{Kconfig,Makefile}` | 2 | 3 |
| `arch/arm/configs/MiSTer_defconfig` | 1 | 3 |

The defconfig hunk is exactly three lines:

```
+CONFIG_AIC8800=y
+CONFIG_AIC8800_WLAN_SUPPORT=m
+CONFIG_AIC_LOADFW_SUPPORT=m
```

`CONFIG_AIC_ZLP_QUIRK` is **not** set — it `depends on KPROBES`
(`aic8800/Kconfig:11-17`) and the fork defconfig has `# CONFIG_KPROBES is not set`
(`MiSTer_defconfig:568`), as does ours. So the third module is dead code in stock too.

### 1.2 Which vendor tree — identified as far as local evidence allows

This is the **RivieraWaves "rwnx" fullmac driver as re-badged by AICSemi** for the AIC8800
family. Three independent markers:

```c
/* aic8800_fdrv/rwnx_main.c:69-71 */
#define RW_DRV_DESCRIPTION  "RivieraWaves 11nac driver for Linux cfg80211"
#define RW_DRV_COPYRIGHT    "Copyright(c) 2015-2017 RivieraWaves"
#define RW_DRV_AUTHOR       "RivieraWaves S.A.S"
```

```c
/* aic_load_fw/aic_bluetooth_main.c:13-16 */
#define DRV_DESCRIPTION  "AIC BLUETOOTH"
#define DRV_COPYRIGHT    "Copyright(c) 2015-2020 AICSemi"
#define DRV_AUTHOR       "AICSemi"
```

**The exact upstream snapshot is stamped in the generated version header** — this is the
string a human should grep public repos for. Both copies
(`aic8800_fdrv/rwnx_version_gen.h`, `aic_load_fw/rwnx_version_gen.h`) are byte-identical:

```c
#define RWNX_VERS_REV "1a4b0054d2M (master)"
#define RWNX_VERS_MOD "6.4.3.0"
#define RWNX_VERS_BANNER "rwnx v6.4.3.0 - 1a4b0054d2M (master)"
#define RELEASE_DATE "2026_0123_5f7be68d"
```

Read that as: AICSemi SDK **v6.4.3.0**, generated from the vendor's own git at commit
`1a4b0054d2` on `master`, **with uncommitted local modifications** (the trailing `M` is
`git describe --dirty`'s marker), SDK release stamp `2026_0123_5f7be68d`.

**What a human must do with network access** (I could not, and did not clone anything — the
session has no GitHub API/HTML and the preamble forbids it):

1. `git grep -n '1a4b0054d2M'` and `git grep -n '2026_0123_5f7be68d'` in each candidate tree.
   A hit on `rwnx_version_gen.h` is a positive identification of the exact snapshot.
2. Failing that, grep for `RWNX_VERS_MOD "6.4.3.0"` (the SDK version) to find the right
   release, then diff `aic8800_fdrv/rwnx_main.c` (9,620 lines) for the delta.
3. Candidate public trees, in the order I would try them:
   - `github.com/radxa/aic8800` (Radxa's packaging of the AICSemi SDK — the tree most likely
     to carry a `LICENSE` file and a firmware directory),
   - `github.com/goecho/aic8800_linux_drvier` (note upstream's own typo in "drvier"),
   - the Rockchip / Orange Pi / Armbian vendor kernels, which carry
     `drivers/net/wireless/aic8800/` at the same paths.
4. **Also grep for the firmware**: `fmacfw_8800d80_u02.bin` is the single most distinctive
   filename (§2). A repo that carries both that blob and this source is the pin candidate.

> **Answered — see §9.3.** `goecho/aic8800_linux_drvier` is a byte-exact match on
> `RWNX_VERS_REV "1a4b0054d2M (master)"` / `RWNX_VERS_MOD "6.4.3.0"` and carries the D80
> firmware. `radxa/aic8800`, the first candidate listed below, is a 404.

Nothing in the tree names a repo: there is **no README, no LICENSE, no build script, no
`.txt`/`.md` of any kind** (`find . -iname '*readme*' -o -iname '*license*' -o -iname '*.sh'
-o -iname '*.md'` → empty). The only repo-shaped hints are two `.gitignore` files listing
kbuild artefacts, and the platform switches `CONFIG_PLATFORM_ROCKCHIP` /
`CONFIG_PLATFORM_ALLWINNER` / `CONFIG_PLATFORM_AMLOGIC` / `CONFIG_PLATFORM_HI` /
`CONFIG_PLATFORM_UBUNTU` in `aic_load_fw/Makefile:22-26`, i.e. an SBC-vendor lineage.

**It has been forward-ported well past its own release date.** The tree carries compat
guards up to `KERNEL_VERSION(7, 2, 0)` — e.g. `aic8800_fdrv/rwnx_tdls.c:118` and
`rwnx_main.c:2945,2957,3069` are `#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 1, 0)`, and
`rwnx_rx.c:1651` is `#if (LINUX_VERSION_CODE <= KERNEL_VERSION(6, 18, 0))`. A 2026-01-23 SDK
stamp cannot have anticipated 7.1/7.2, so **someone** (the vendor since, an intermediate
SBC tree, or Sorgelig) did that work. Identifying who is the same task as identifying the
repo, and it matters: those guards are why the build in §6 succeeds.

### 1.3 License sweep — the serious finding

Over the **139 files under `drivers/net/wireless/aic8800/`** (the 142-file commit minus the
three files outside that directory):

| Category | Count |
|---|---:|
| Files with an SPDX tag | **1** |
| Files with a GPL licence **notice** ("GNU General Public License" text) | **0** |
| Files with **Apache License 2.0** wording | **2** |
| Files with only a bare `Copyright` line and **no licence grant at all** | **85** |
| Files with **neither** a copyright line nor any licence | **51** |
| `MODULE_LICENSE(...)` declarations | **3**, all `"GPL"` |

The three `MODULE_LICENSE` sites (matching PLAN §2.9's expectation of three):

```
aic8800_fdrv/rwnx_main.c:9619            MODULE_LICENSE("GPL");
aic_load_fw/aic_bluetooth_main.c:82      MODULE_LICENSE("GPL");
aic_zlp_quirk/aic_zlp_quirk.c:230        MODULE_LICENSE("GPL");
```

The one SPDX tag is in the *third-party* quirk module, not the vendor code:

```c
/* aic_zlp_quirk/aic_zlp_quirk.c:1 */
// SPDX-License-Identifier: GPL-2.0
...
/* :228-231 */
MODULE_AUTHOR("Shen Mintao <cx330.shen@autocore.ai>");
MODULE_DESCRIPTION("AIC 8800D80 standard btusb ACL bulk TX ZLP quirk");
MODULE_LICENSE("GPL");
MODULE_VERSION("1.0");
```

— i.e. a kprobes-based USB zero-length-packet workaround authored at **AutoCore.ai**, a
third origin again distinct from RivieraWaves and AICSemi. It is the only file in the whole
commit that is unambiguously licensed.

**The non-GPL files.** `aic8800_fdrv/aic_br_ext.{c,h}` (1,686 lines) are **Apache-2.0**:

```c
/* aic_br_ext.c:1-17 */
/******************************************************************************
 *
 *  Copyright (C) 2019-2021 Aicsemi Corporation
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  ...
 ******************************************************************************/
```

Apache-2.0 is **incompatible with GPL-2.0-only**, which is what a Linux module linking
`MODULE_LICENSE("GPL")` is. Mitigating fact: `aic_br_ext.o` is **not compiled** —
`aic8800_fdrv/Makefile:85` sets `CONFIG_BR_SUPPORT = n` and `:209` gates the object on it —
so the shipped `.ko` does not contain Apache code. It would still be inside any source
tarball we redistribute, and it would still be in `legal-info`.

The remaining copyright holders, by frequency of the header line:

```
38  Copyright (C) RivieraWaves 2012-2019      9  Copyright (C) RivieraWaves 2011-2019
14  Copyright (C) AICSemi 2018-2020           7  Copyright (C) RivieraWaves 2016-2019
 6  Copyright (C) RivieraWaves 2014-2019      3  Copyright (C) 2020 AIC semiconductor.
 2  Copyright (C) RivieraWaves 2017-2019      2  Copyright (C) Aicsemi 2018-2024
 2  Copyright (C) 2019-2021 Aicsemi Corporation
 1  Copyright (c) 2012 Neratec Solutions AG   (rwnx_radar.c:9 — DFS pattern detector)
```

**Consequence for packaging.** `package/rtl8852cu-morrownr` sets
`RTL8852CU_MORROWNR_LICENSE = GPL-2.0` and `..._LICENSE_FILES = LICENSE`, with the LICENSE
file's own sha256 in the `.hash` (`821deb3a…`). **This tree has no file for
`_LICENSE_FILES` to name.** The only in-tree licence evidence is three
`MODULE_LICENSE("GPL")` macro calls, which are a kernel-ABI declaration, not a grant. A
package would either have to declare `LICENSE = GPL-2.0` on the strength of those macros
with an explanatory comment, or pin an upstream repo that *does* carry a LICENSE — another
reason identification (§1.2) is the gating task.

### 1.4 Binary blobs: none

`find … -exec file {}` over all 139 files returns **zero** non-text files. No `.bin`, no
`.fw`, no hex-table header. The two largest hex-constant concentrations are
`aicwf_compat_8800dc.c` (2,247 hex literals ≥4 digits) and `rwnx_main.c` (1,923); the
former's are named PHY register tables in C, e.g.
`aicwf_compat_8800dc.c:270 uint32_t ldpc_cfg_ram[] = {` and `:947 uint32_t agc_cfg_ram[] = {`.
Those are RF/PHY coefficient tables, not a firmware image.

**This is the exact inverse of `rtl8852cu-morrownr`**, whose ADR-0016 cost #3 is a ~15 MB
firmware C array welded into the `.ko`. Here the `.ko` is small (§6) precisely because the
firmware is *not* in it — which is §2's problem.

---

## 2. Firmware — the blocking finding

### 2.1 What it loads, and from where

`CONFIG_USE_FW_REQUEST` is **off** in both module Makefiles
(`aic8800_fdrv/Makefile:112`, `aic_load_fw/Makefile:15`, both `?= n`), so the compiled path
does **not** call `request_firmware()`. It calls `filp_open()` on a path it builds itself:

```c
/* aic8800_fdrv/rwnx_platform.c:674-691 */
	len = snprintf(path, FW_PATH_MAX_LEN, "%s/%s", aic_fw_path, name);
	...
	AICWFDBG(LOGINFO, "%s :firmware path = %s  \n", __func__, path);
	/* open the firmware file */
	fp = filp_open(path, O_RDONLY, 0);
```

`aic_fw_path` is not fdrv's own default — fdrv asks `aic_load_fw` for it at init:

```c
/* aic8800_fdrv/rwnx_utils.c:19-35 */
extern void get_fw_path(char* fw_path);
...
	memset(aic_fw_path, 0, 200);
	get_fw_path(aic_fw_path);
```

and `aic_load_fw` answers with `/lib/firmware`, because its Makefile turns the "Ubuntu"
platform on by default (`aic_load_fw/Makefile:26  CONFIG_PLATFORM_UBUNTU ?= y`, `:68-70`
adds `-DCONFIG_PLATFORM_UBUNTU`):

```c
/* aic_load_fw/aicbluetooth.c:145-152 */
#define FW_PATH_MAX 200
#if defined(CONFIG_PLATFORM_UBUNTU)
static const char* aic_default_fw_path = "/lib/firmware";
#else
static const char* aic_default_fw_path = "/vendor/etc/firmware";   /* Android */
#endif
char aic_fw_path[FW_PATH_MAX];
module_param_string(aic_fw_path, aic_fw_path, FW_PATH_MAX, 0660);
```

So the **subdirectories under `/lib/firmware`** are:

| Consumer | Path pattern | Source |
|---|---|---|
| `aic_load_fw` (BT + bootstrap FW) | `/lib/firmware/aic8800/<name>`, `/lib/firmware/aic8800D80/<name>`, `/lib/firmware/aic8800D80X2/<name>` — chosen per `chipid` | `aicbluetooth.c:326-330` |
| `aic8800_fdrv` (Wi-Fi) | `/lib/firmware/<name>` (flat) | `rwnx_platform.c:674` with `aic_fw_path = "/lib/firmware"` |
| `aic8800_fdrv`, 8800DC/DW only | `/lib/firmware/aic8800DC/<name>` | `rwnx_platform.c:1672  strcat(aic_fw_path, "/aic8800DC");` |

Both are overridable at load time via the `aic_fw_path` module parameter
(`aicbluetooth.c:152`, mode `0660`), which is the escape hatch a packaging effort would use
to normalise the layout.

### 2.2 Every filename it asks for

**80 distinct filenames** appear as string literals (`grep -rhoI '"[A-Za-z0-9_./-]*\.\(bin\|txt\|ini\)"'`).
Excluding the four macro-concatenation fragments (`".bin"`, `"_u02.bin"`, `"_h_u02.bin"`,
`".ihex"`), that is **~60 firmware blobs plus ~13 `.txt`/`.ini` config files**:

*Core per-chip firmware* — `fmacfw.bin`, `fmacfw_8800d80.bin`, `fmacfw_8800d80_u02.bin`,
`fmacfw_8800d80_u02_ipc.bin`, `fmacfw_8800d80_h_u02.bin`, `fmacfw_8800d80_h_u02_ipc.bin`,
`fmacfw_8800d80x2.bin`, `fmacfw_8800d80x2_ipc.bin`, `fmacfw_rf.bin`, `fmacfw_rf_8800d80.bin`,
`fmacfw_calib_8800d80n_u02.bin`, `fmacfw_cinit_8800d80n_u02.bin`,
`fmacfw_gaintbl_8800d80n.bin`, `fmacfw_gaintbl_8800dln.bin`,
`fmacfw_initvar_8800d80n.bin`, `fmacfw_initvar_8800dln.bin`,
`fmacfw_patch_8800d80n_u02.bin`, `fmacfw_patch_tbl_8800d80n_u02.bin`,
`lmacfw_rf_8800d80_u02.bin`, `lmacfw_rf_8800d80n.bin`, `lmacfw_rf_8800d80x2.bin`,
`lmacfw_rf_8800dc.bin`, `lmacfw_rf_8800dln.bin`, `host_wb_8800m80.bin`,
`host_wb_8800m80x2.bin`.

*ROM patches / ADID tables* — `fw_patch.bin`, `fw_patch_u03.bin`, `fw_patch_test.bin`,
`fw_patch_8800d80.bin`, `fw_patch_8800d80_u02.bin`, `fw_patch_8800d80x2_u03.bin`,
`fw_patch_8800d80x2_u05.bin`, `fw_patch_8800dc_u02.bin`, `fw_patch_8800dc_u02h.bin`,
`fw_patch_table.bin`, `fw_patch_table_u03.bin`, `fw_patch_table_8800d80.bin`,
`fw_patch_table_8800d80_u02.bin`, `fw_patch_table_8800d80x2_u03.bin`,
`fw_patch_table_8800d80x2_u05.bin`, `fw_patch_table_8800dc_u02.bin`,
`fw_patch_table_8800dc_u02h.bin`, `fw_adid.bin`, `fw_adid_u03.bin`,
`fw_adid_8800d80.bin`, `fw_adid_8800d80_u02.bin`, `fw_adid_8800d80x2_u03.bin`,
`fw_adid_8800d80x2_u05.bin`, `fw_adid_8800dc_u02.bin`.

*PHY/RAM images and misc* — `agcram.bin`, `ldpcram.bin`, `fcuram.bin`,
`aic_rf_calib.bin`, `aic_dpdresult_lite_8800dc.bin`, `calibmode_8800d80.bin`,
`fw_ble_scan.bin`, `fw_ble_scan_ad_filter.bin`, `m2d_ota.bin`, `fw.bin`
(`aic_load_fw/aic_bluetooth_main.c:12  #define DRV_CONFIG_FW_NAME "fw.bin"`).

*Text config* — `aic_userconfig{,_8800d80,_8800d80n,_8800d80x2,_8800dc,_8800dln,_8800dw}.txt`,
`aic_powerlimit_*.txt` (six variants), `rwnx_settings.ini`, `rwnx_trident.ini`,
`rwnx_karst.ini`.

The names our board would actually need depend on which dongle is plugged in; the Tenda
U11/U11 Pro path (`PRODUCT_ID_AIC8800D81`, §4) routes through the 8800D80 branch
(`aicwf_usb.c:2329-2337`), i.e. `fmacfw_8800d80_u02*.bin` + `fw_patch_8800d80_u02.bin` +
`fw_adid_8800d80_u02.bin` + `fw_patch_table_8800d80_u02.bin` + `lmacfw_rf_8800d80_u02.bin`.

### 2.3 Stock ships none of them — confirmed directly

Release 20260907's `firmware.tar.gz`
(sha256 `8a6ab6730e5a4b0ee978cae98a15fd8505e5605074cd34018adac0ac43359f78`, matching PLAN §1.1):

```
$ tar tzf firmware.tar.gz | wc -l
104
$ tar tzf firmware.tar.gz | grep -icE 'aic|fmacfw|fw_patch|fw_adid|8800'
0
```

Same result against the inventoried list
`evidence/stock-20260907-firmware.txt` (89 lines, zero `aic` matches), and against
`modules.tar.gz` (0 `aic` matches — the driver commit post-dates the release, exactly as
PLAN §2.9 says). The `Linux_Image_creator_MiSTer` repo at `d4e3f51ec` adds nothing since.
Searching the whole fork history: `git log --all -i --grep=aic` returns **only this one
commit** — no follow-up firmware commit exists yet on any fork branch.

**So as of today, on stock, this driver would be inert.** It is reasonable to expect
Sorgelig to ship the blobs in a later `firmware.tar.gz`; that has not happened yet.

### 2.4 Where firmware could come from — what I can and cannot verify here

> **All three bullets answered — see §9.** `linux-firmware`: no (§9.2). The vendor tree:
> found, D80 only, licence unresolved (§9.3). Stock, later: still the recommended path, and
> still not yet happened (§9.1) — plus the layout requirement in §9.4.

- **`linux-firmware` upstream: NOT VERIFIABLE FROM THIS SESSION.** The repo has no
  extracted Buildroot tree (`work/`, `output/`, `dl/` do not exist on this branch), so there
  is no `linux-firmware` checkout and hence no `WHENCE` to grep. `grep aic8800 $S/mainline`
  is not a substitute — `WHENCE` lives in the `linux-firmware` repo, not in the kernel tree,
  and that repo is not present. **I therefore state plainly: I could not check whether
  `linux-firmware` carries `aic8800/`.** A human should run
  `git grep -i aic8800 WHENCE` in `git.kernel.org/pub/scm/linux/firmware/linux-firmware.git`.
  My expectation, worth exactly nothing without that check, is that it does not — the
  mainline kernel has no driver to request it (§3), which is normally a precondition for
  `linux-firmware` acceptance.
- **The vendor tree.** The public `aic8800` SBC repos listed in §1.2 typically ship a
  `fw/` or `firmware/` directory alongside the driver. That is the realistic source, and
  it makes firmware redistributability a **question about that specific repo's licence
  file**, which is the same unanswered question as §1.3.
- **Stock, later.** If Release 2026xxxx ships the blobs, we could mirror stock's
  `firmware.tar.gz` the way `package/linux-firmware-extra` mirrors `linux-firmware`'s tree.
  That is the lowest-risk path and it costs nothing to wait for.

---

## 3. Mainline status — absent in all three trees

| Tree | Checked | `aic8800` | `aicwf` | `AICSemi` | `RivieraWaves` | `rwnx` |
|---|---|---|---|---|---|---|
| `torvalds/linux` **v7.3-rc2** (`50d05c7c76c9`) | `drivers/`, `net/`, `MAINTAINERS` | 0 | 0 | 0 | 0 | 0 |
| `linux-6.18.y` **6.18.49** (`1c732c6b94f0`) | same | 0 | 0 | 0 | 0 | 0 |
| `linux-7.2.y` **7.2.3** (`58e7295cfeca`) | same | 0 | 0 | 0 | 0 | 0 |

`find` for any file whose *name* contains `aic8800`/`aicwf`/`rwnx` also returns empty in all
three. **Absent** — case-insensitive, by symbol and by filename, not by path.

This is the ADR 0016 admissibility test and **AIC8800 passes it**: mainline cannot drive this
chip at all, over any bus, at tip. Same standing as RTL8852CU had in v10.2. Note the
asymmetry, though — for RTL8852C mainline had the chip HAL and lacked only the USB bus file,
so a mainline driver was plausibly one file away. For AIC8800 there is *nothing*: no HAL, no
staging entry, no `MAINTAINERS` line. A "wait for mainline" strategy has no visible horizon.

---

## 4. USB ID overlap — the ADR 0016 bind-conflict test: **zero conflicts**

The `#ifdef` structure matters. `aicwf_usb.h:14-75` partitions the PID defines on
`CONFIG_USB_BT`, and `aic8800_fdrv/Makefile:68` sets `CONFIG_USB_BT=y`, so the compiled table
is the `#else` branch — `aicwf_usb.c:2643-2683`, **41 entries**. `aic_load_fw/aicwf_usb.c:1848-1858`
adds **11** more (its own bootstrap table), and `aic_zlp_quirk.c:13-14` hard-codes one
(`0x368b:0x8d81`). Union: **46 unique VID:PIDs**, resolved from the `#define`s:

| Vendor | PIDs claimed |
|---|---|
| `a69c` (AICSemi v1) | `8800` `8801` `88dc` `88dd` `88de` `8d40` `8d41` `8d80` `8d81` `8d83` |
| `368b` (AICSemi v2) | `8870` `8871` `88df` `88e0` `88e1` `88e2` `88e3` `88e5` `8d45` `8d46` `8d47` `8d48` `8d49` `8d4a` `8d81` `8d83` `8d84` `8d85` `8d86` `8d88` `8d89` `8d8a` `8d8b` `8d8c` `8d8d` `8d90` `8d91` `8d92` `8d99` |
| `2604` (**Tenda**) | `0013` (Tenda) `0014` (**U2**) `001f` (**U11**) `0020` (**U11 Pro**) |
| `3625` (Tenda v2) | `0110` (TX1U Nano) |
| `2357` (TP-Link) | `014b` (Mercury) `014e` (TP-Link) |

**Result: 0 overlaps.** All 46 grepped one-by-one against `drivers/net/wireless/`,
`drivers/bluetooth/`, `drivers/usb/` and `drivers/net/usb/` in 6.18.49: `checked=46
overlaps=0`. Vendor-level, `0x368b` has **zero** occurrences anywhere in 6.18.49's
`drivers/net/wireless` + `drivers/bluetooth`, and the single `0xa69c` hit is a coefficient
value in `realtek/rtw89/rtw8852b_table.c:13964`, not a USB ID.

Two **near misses** worth writing down, in the same spirit as the `rtl8852cu` note:

- `drivers/net/wireless/realtek/rtw88/rtw8812au.c:76` claims **`2604:0012`** — one PID below
  the Tenda block above. Same vendor, different chip (an RTL8812AU Tenda dongle). If a
  future AIC ID were `2604:0012` we would have a fight; today we do not.
- `drivers/net/wireless/realtek/rtw89/rtw8851bu.c:23` **and** `drivers/bluetooth/btusb.c:528`
  both claim **`3625:010b`**; ours is `3625:0110`.

**An internal overlap does exist and a maintainer must understand it.** Six IDs appear in
*both* aic modules' tables — `a69c:8801`, `a69c:8d41`, `a69c:8d81`, `368b:8d81`,
`368b:8d91`, `368b:8d99` — and `368b:8d81` additionally in `aic_zlp_quirk`. This is by
design (two-stage bring-up: `aic_load_fw` claims the ROM-bootloader device, downloads the
image, the device re-enumerates and `aic8800_fdrv` claims it), but `aic_load_fw` uses plain
`USB_DEVICE()` while `aic8800_fdrv` uses `USB_DEVICE_AND_INTERFACE_INFO(..., 0xff,0xff,0xff)`
for three of the six, so the disambiguation is by interface class, not by PID. **Verify on
hardware that the two modules do not race**; it is not a question source reading can close.

### The Tenda angle (the demand hint)

`2604:0014` = Tenda **U2**, `2604:001f` = **U11**, `2604:0020` = **U11 Pro**,
`3625:0110` = **TX1U Nano** (`aicwf_usb.h:28-29,55-57`). These are the cheap Wi-Fi 6 (AX)
USB dongles now on every marketplace, and none of them has *any* driver in our image today
(§4 result: zero mainline coverage). That is the strongest demand signal available from
source alone: a MiSTer user who buys the currently-cheapest AX dongle gets nothing.

---

## 5. Kernel-config fit

### 5.1 Their Kconfig against our resolved config

```
aic8800/Kconfig:1-4          menuconfig AIC8800    bool "AIC wireless Support"    depends on USB
aic8800_fdrv/Kconfig:1-5     config AIC8800_WLAN_SUPPORT  tristate  depends on USB, depends on CFG80211
aic_load_fw/Kconfig:1-4      config AIC_LOADFW_SUPPORT    tristate  depends on USB
aic8800/Kconfig:11-13        config AIC_ZLP_QUIRK         tristate  depends on KPROBES
```

Resolved from `board/mister/de10nano/linux.config` after
`make -C <linux> O=<tmp> ARCH=arm LLVM=1 olddefconfig` on 6.18.49:

```
CONFIG_USB=y
CONFIG_CFG80211=m
CONFIG_MODULES=y
CONFIG_AEABI=y
CONFIG_DEBUG_FS=y
# CONFIG_NL80211_TESTMODE is not set
# CONFIG_KPROBES is not set
```

Both wanted symbols are satisfied. `AIC_ZLP_QUIRK` is **not buildable for us** —
`CONFIG_KPROBES` is unset in our config *and* in the fork defconfig, so that module is dead
on both sides and can be dropped from any packaging.

### 5.2 The `wext` shim: compiles out cleanly — **and the PLAN's premise is wrong**

PLAN §2.9 says "our kernel does not enable `CFG80211_WEXT` (select-only symbol)". That is a
carry-over from the `rtl*` package notes and it is **not true of this config**:

```
board/mister/de10nano/linux.config:145   CONFIG_CFG80211_WEXT=y
```

and it resolves (`CONFIG_WEXT_CORE=y`, `CONFIG_WEXT_PROC=y`, `CONFIG_CFG80211_WEXT=y` in the
olddefconfig output). `CFG80211_WEXT` is a *prompted* bool in 6.18
(`net/wireless/Kconfig:187-192`), not select-only. The select-only symbol is
`CONFIG_WIRELESS_EXT` (`net/wireless/Kconfig:2-3`, a bare `bool` with no prompt), and *that*
is what stays unset.

**Which is exactly the symbol the vendor Makefile keys on**, so the outcome is the one the
PLAN wanted, by a different route:

```make
# aic8800_fdrv/Makefile:118
CONFIG_USE_WIRELESS_EXT = y
...
# aic8800_fdrv/Makefile:140-142
ifneq ($(CONFIG_WIRELESS_EXT), y)
CONFIG_USE_WIRELESS_EXT = n
endif
...
# aic8800_fdrv/Makefile:224
$(MODULE_NAME)-$(CONFIG_USE_WIRELESS_EXT) += aicwf_wext_linux.o
# aic8800_fdrv/Makefile:348
ccflags-$(CONFIG_USE_WIRELESS_EXT) += -DCONFIG_USE_WIRELESS_EXT
```

`CONFIG_WIRELESS_EXT` is absent from our resolved `.config`, so `CONFIG_USE_WIRELESS_EXT`
flips to `n`: `aicwf_wext_linux.o` is dropped **and** the `-DCONFIG_USE_WIRELESS_EXT` define
is not passed. All 15 in-source uses are `#ifdef CONFIG_USE_WIRELESS_EXT` (in `rwnx_main.c`,
`rwnx_msg_rx.c`, `rwnx_msg_tx.c`, `rwnx_mod_params.c`, `rwnx_defs.h`) including the only
`ndev->wireless_handlers = …` assignment at `rwnx_main.c:2030`. **Verified, not predicted:**
the §6 build produced 36 objects and `aicwf_wext_linux.o` is not among them. Same clean
compile-out the `rtl*` package notes record, and it needs no wrapper and no kernel `select`
hack.

### 5.3 Feature `#ifdef`s our config changes, and platform switches

All of these are set *inside the driver's own Makefile*, independent of our kconfig, so they
are packaging decisions rather than surprises:

- **5 GHz is ON**: `Makefile:64 CONFIG_USE_5G = y` → `-DUSE_5G` (`:314`).
- **HE/AX compat shim is OFF**: `Makefile:71 CONFIG_HE_FOR_OLD_KERNEL = n` (likewise
  `CONFIG_VHT_FOR_OLD_KERNEL`, `CONFIG_WPA3_FOR_OLD_KERNEL`). These are shims for kernels
  predating native HE/VHT/SAE in `cfg80211`; on 6.18 they are correctly off, and the native
  `cfg80211` paths are used. So AX and WPA3 come from mac80211-era `cfg80211`, not from the
  vendor shim. (The commented-out `config USE_5G` / `config HE_FOR_OLD_KERNEL` stubs in
  `aic8800_fdrv/Kconfig:8-16` are dead.)
- **BT coexistence ON**: `:74 CONFIG_COEX = y`; **BT over USB ON**: `:68 CONFIG_USB_BT = y`
  (this is what selects the 41-entry ID table in §4).
- **Radar/DFS ON** (`:158 CONFIG_RWNX_RADAR ?= y` → `rwnx_radar.o`), **bridge/AP extensions
  OFF** (`:85 CONFIG_BR_SUPPORT = n` → the Apache files are not compiled), **SDIO OFF**
  (`:60`), **testmode** follows the kernel (`:213`, and ours is unset so `rwnx_testmode.o`
  is dropped).
- **debugfs follows OUR kernel, and that is a trap worth naming.** `Makefile:104` is
  `CONFIG_DEBUG_FS ?= n` — a *conditional* assignment against a **real kernel symbol**.
  kbuild has already set `CONFIG_DEBUG_FS=y` from our `.config`, so `?=` does nothing and
  `rwnx_debugfs.o` + `rwnx_fw_trace.o` **are** built (confirmed: both appear in the §6 object
  list; `rwnx_debugfs.c` alone is 2,738 lines). If we want them out, the package must pass
  `CONFIG_DEBUG_FS=n` on the kbuild command line — which would be wrong, since that variable
  is the kernel's. The clean fix is a one-line patch renaming the driver's private switch.
- **Platform switches are all inert for us.** `aic_load_fw/Makefile:22-26` offers
  `CONFIG_PLATFORM_{ROCKCHIP,ALLWINNER,AMLOGIC,HI}` — all `?= n` — and
  `CONFIG_PLATFORM_UBUNTU ?= y`, the last of which is what gives us `/lib/firmware` (§2.1).
  The Rockchip/Allwinner code they gate is real (`aicwf_usb.c:2266-2273` calls
  `rockchip_wifi_get_oob_irq()`; `aicwf_sdio.c` and `rwnx_platform.c:925,1045,1592` have
  Allwinner branches) but none of it compiles for us. `aic8800_fdrv/Makefile:77-81,95-99`
  additionally branch on `CONFIG_ARCH_SUN60IW2P1` (an Allwinner SoC), taking the `else`
  arms: `CONFIG_USB_ALIGN_DATA = y`, `CONFIG_USB_NO_TRANS_DMA_MAP = n`. Fine for us.
- `ANDROID_PLATFORM` is never defined, so the non-Android arms are taken everywhere
  (`rwnx_platform.c:1671,1810,1840`, `rwnx_msg_tx.c:5253`, …).

---

## 6. Build attempt — **it compiles for 32-bit ARM**

This is the decisive technical evidence, and it is the step that caught `rtl8852cu`'s
`__aeabi_uldivmod` only after that package had already been added.

**Method** (nothing written into any shared tree):

```bash
git -C $S/fork-6.18 archive c129b0fac drivers/net/wireless/aic8800 | tar -x -C $W/src
cp board/mister/de10nano/linux.config $W/kbuild/.config
make -C $S/linux O=$W/kbuild ARCH=arm LLVM=1 olddefconfig
make -C $S/linux O=$W/kbuild ARCH=arm LLVM=1 -j$(nproc) prepare modules_prepare   # → PREPARE_OK
make -C $S/linux O=$W/kbuild ARCH=arm LLVM=1 -j$(nproc) \
     M=$W/src/drivers/net/wireless/aic8800/aic8800_fdrv CONFIG_AIC8800_WLAN_SUPPORT=m modules
make -C $S/linux O=$W/kbuild ARCH=arm LLVM=1 \
     M=$W/src/drivers/net/wireless/aic8800/aic_load_fw  CONFIG_AIC_LOADFW_SUPPORT=m  modules
```

**What had to be set, and what did not.** I read both Makefiles first, as instructed. The
360-line `aic8800_fdrv/Makefile` is *not* a platform-selection maze in the `rtl8852cu` sense
— it is a long flat list of `CONFIG_* = y/n` feature switches (lines 5-138) feeding
`ccflags-$(CONFIG_*)` lines (227-359), with only two `ifdef` branches, both on
`CONFIG_ARCH_SUN60IW2P1`. Concretely:

| `rtl8852cu-morrownr` needed | AIC8800 needs |
|---|---|
| `CONFIG_RTL8852CU=m` on the command line, because `obj-$(CONFIG_RTL8852CU)` is only set by the driver's own `modules:` target, which Buildroot never invokes | **Same trap, same fix.** `aic8800_fdrv/Makefile:175` is `obj-$(CONFIG_AIC8800_WLAN_SUPPORT) := $(MODULE_NAME).o` and nothing in the file ever sets it (the in-tree path gets it from Kconfig). Must pass `CONFIG_AIC8800_WLAN_SUPPORT=m` (and `CONFIG_AIC_LOADFW_SUPPORT=m`) as `_MODULE_MAKE_OPTS`. |
| `KSRC=$(LINUX_DIR)`, because the tree still builds flags in `EXTRA_CFLAGS`, which 6.18 kbuild ignores, and its version probe shells out to the *host's* `/lib/modules/$(uname -r)/build` | **Not needed.** `aic8800_fdrv/Makefile:1` is already `ccflags-y += $(USER_EXTRA_CFLAGS)` and every flag line is `ccflags-*`. `grep -n 'EXTRA_CFLAGS\|KDIR\|KSRC\|uname\|^modules:'` over all four Makefiles returns exactly two hits: that `USER_EXTRA_CFLAGS` passthrough and a **commented-out** `#EXTRA_CFLAGS += -Wno-unused-variable` at `:3`. No `KDIR`/`KSRC` anywhere, no top-level `modules:` target, no `uname`, no host-kernel probe. The only `$(shell …)` is `:308 ifeq ($(shell test $(VERSION) -lt 4 …), 0)`, which reads kbuild's *own* `VERSION` (=6) rather than shelling out to the build host — the exact thing that broke `rtl8852cu`. |
| a patch for a 64-bit division | **Not needed** — see below. |
| one module, one `M=` directory | **Two modules, two directories, and an ordering constraint.** `aic8800_fdrv` imports nine `EXPORT_SYMBOL`s from `aic_load_fw`, so its modpost needs `KBUILD_EXTRA_SYMBOLS=<…>/aic_load_fw/Module.symvers` and `aic_load_fw` must be built first. This is the one genuine kbuild quirk here and it does **not** fit `pkg-kernel-module.mk`'s single `M=`. |

Nothing else. No hard-coded paths, no `uname` calls, no autodetect include.

**Result — `aic8800_fdrv`:**

- **36/36 objects compiled, 0 errors.** (`aic_priv_cmd aic_vendor aicwf_compat_8800d80
  aicwf_compat_8800d80n aicwf_compat_8800d80x2 aicwf_compat_8800dc aicwf_compat_8800dln
  aicwf_tcp_ack aicwf_txrxif aicwf_usb ipc_host md5 regdb rwnx_cfgfile rwnx_cmds
  rwnx_debugfs rwnx_dini rwnx_fw_trace rwnx_irqs rwnx_main rwnx_mesh rwnx_mod_params
  rwnx_msg_rx rwnx_msg_tx rwnx_pci rwnx_platform rwnx_radar rwnx_rx rwnx_strs rwnx_tdls
  rwnx_tx rwnx_txq rwnx_utils rwnx_v7 rwnx_wakelock usb_host`.) `aicwf_wext_linux.o` and
  `rwnx_testmode.o` correctly absent (§5.2).
- **4 warnings**, all clang quality nits, none fatal:
  - `rwnx_msg_tx.c:4257 warning: misleading indentation; statement is not part of the previous 'if'`
  - `rwnx_tx.c:1471 warning: variable 'msgbuf' is uninitialized when used here`
  - `aic_priv_cmd.c:324 warning: variable 'lvl_mod' is used uninitialized whenever 'if' condition is false`
  - `aicwf_usb.c:1821 warning: variable 'buf_align' is used uninitialized whenever 'if' condition is false`
    The last three are real (if narrow) latent bugs and are worth reporting upstream/to the
    fork; none is on a hot path we can reach without hardware.
- Link `LD [M] aic8800_fdrv.o` succeeded. Build time: **14 s** wall on this machine.

**Result — `aic_load_fw`:** 9/9 objects compiled, **0 warnings, 0 errors**, `LD [M]` OK.

**modpost — the `__aeabi_uldivmod` test: PASSED. Both `.ko`s link clean.**

A first pass stopped at "`Module.symvers` is missing" — `prepare`/`modules_prepare` do not
produce one — so I built the kernel proper (`make vmlinux`, then `make modules`, ~25 min) to
get a real 11,372-line `Module.symvers` and re-ran modpost against it. Both modules then
pass, with **one packaging lesson**:

```
$ make … M=<src>/aic_load_fw  CONFIG_AIC_LOADFW_SUPPORT=m modules
  LD [M]  aic_load_fw.ko                       exit=0, 0 errors, 0 warnings

$ make … M=<src>/aic8800_fdrv CONFIG_AIC8800_WLAN_SUPPORT=m modules
ERROR: modpost: "get_userconfig_txpwr_idx" [aic8800_fdrv.ko] undefined!
ERROR: modpost: "get_userconfig_txpwr_ofst" [aic8800_fdrv.ko] undefined!
ERROR: modpost: "get_testmode"              [aic8800_fdrv.ko] undefined!
ERROR: modpost: "get_fw_path"               [aic8800_fdrv.ko] undefined!
ERROR: modpost: "aicwf_prealloc_txq_alloc"  [aic8800_fdrv.ko] undefined!
ERROR: modpost: "set_testmode"              [aic8800_fdrv.ko] undefined!
ERROR: modpost: "get_flash_bin_size"        [aic8800_fdrv.ko] undefined!
ERROR: modpost: "get_flash_bin_crc"         [aic8800_fdrv.ko] undefined!
ERROR: modpost: "get_adap_test"             [aic8800_fdrv.ko] undefined!
                                            exactly 9 errors, and ZERO of them is a kernel symbol
```

**All nine are `aic_load_fw`'s own `EXPORT_SYMBOL`s** — this is the ordinary two-module
external-build problem, not a porting defect. Point the second build at the first's
`Module.symvers` and it is clean:

```
$ make … M=<src>/aic8800_fdrv CONFIG_AIC8800_WLAN_SUPPORT=m \
       KBUILD_EXTRA_SYMBOLS=<src>/aic_load_fw/Module.symvers modules
  LD [M]  aic8800_fdrv.ko                      exit=0, 0 errors, 0 warnings
```

**Both `.ko`s built. Zero modpost errors, zero modpost warnings, no undefined kernel
symbol anywhere.** *A package must either build both directories in one `M=` invocation or
pass `KBUILD_EXTRA_SYMBOLS` in the right order* — `pkg-kernel-module.mk` assumes a single
`M=`, so this needs custom `_BUILD_CMDS` and is the one genuine kbuild quirk of this driver
(the analogue of `rtl8852cu`'s `KSRC=`).

Independently of modpost, I enumerated every undefined symbol in both linked objects with
`llvm-nm -u` and filtered for libgcc/EABI helpers, which is the direct form of the
`rtl8852cu` question:

```
aic8800_fdrv.o : 235 undefined symbols; EABI helpers = __aeabi_idiv, __aeabi_uidiv
aic_load_fw.o  :  75 undefined symbols; EABI helpers = NONE
```

**Both of those helpers are exported to modules by the ARM kernel** —
`arch/arm/kernel/armksyms.c:135` `EXPORT_SYMBOL(__aeabi_idiv);` and `:141`
`EXPORT_SYMBOL(__aeabi_uidiv);`, inside `#ifdef CONFIG_AEABI` (`:134`), and our config has
`CONFIG_AEABI=y`. The one that killed `rtl8852cu`, **`__aeabi_uldivmod` (64-bit division),
is not referenced by this driver and is not in `armksyms.c` at all** (`grep` for it over
`arch/arm/` returns no `EXPORT_SYMBOL`). So **ADR 0016's fourth cost does not recur here.**
There is no 32-bit-ARM porting patch to write and no standing per-bump re-check of one.

**Module dependencies** (from the same symbol dump, useful for `depmod`/packaging):
`aic8800_fdrv` needs **9 symbols from `aic_load_fw`** — `get_fw_path`, `get_testmode`,
`set_testmode`, `get_adap_test`, `get_flash_bin_size`, `get_flash_bin_crc`,
`get_userconfig_txpwr_idx`, `get_userconfig_txpwr_ofst`, `aicwf_prealloc_txq_alloc` — and
**41 `cfg80211_*`/`ieee80211_*` symbols** from `cfg80211` (which is `=m` for us). So the
load order is `cfg80211` → `aic_load_fw` → `aic8800_fdrv`, and the two aic modules must
ship together or neither works.

**Size — measured on the real `.ko`s, not estimated:**

| Module | text | data | bss | `.ko` as linked | `--strip-debug` | `.ko.xz` |
|---|---:|---:|---:|---:|---:|---:|
| `aic8800_fdrv` | 479,170 | 26,581 | 13,654 | 9,434,308 | 755,344 | **177,816** |
| `aic_load_fw` | 49,699 | 1,264 | 432 | 1,389,572 | 93,292 | **29,012** |
| **total** | 528,869 | 27,845 | 14,086 | — | 848,636 | **206,828** |

**The on-image cost of the driver half is 206,828 bytes (~202 KiB) of `.ko.xz`** — about
**one ninth** of `rtl8852cu-morrownr`'s 1.8 MB `.ko.xz`, precisely because the firmware is
*not* linked in (§1.4). The flip side is §2: that firmware then has to come from somewhere
and ship as its own package, which `rtl8852cu` did not need, and ~60 blobs will dwarf
202 KiB.

---

## 7. Demand and value — what is knowable, and what is not

**Not reachable from this session, and I did not guess:** the fork's issues and PR
discussions, the MiSTer forum, Discord, and any GitHub HTML/API. So there is **no evidence
here about how many MiSTer users own an AIC8800 dongle.** If that matters to the decision, a
human must paste: (a) any fork issue or forum thread requesting AIC8800/Tenda U11 support,
(b) whether Sorgelig has said anything about shipping the firmware.

What *is* knowable locally:

1. **Sorgelig added it to `MiSTer-v6.18` HEAD**, so stock will almost certainly ship it in
   the next release, with or without us. That changes the question from "should this chip
   work on MiSTer" to "should *our* image match stock here" — a parity question, and parity
   arguments have historically won in this project.
2. **The Tenda U2 / U11 / U11 Pro / TX1U Nano IDs** (§4) are commodity ~£10 AX dongles. If
   a MiSTer user buys "the cheap Wi-Fi 6 stick" today there is a real chance it is one of
   these, and our image currently gives it **no driver at all**.
3. **Zero userspace coupling.** `grep -rniE 'aic8800|aicwf|a69c|368b|2604|0x8d81|/lib/firmware'`
   over `Main_MiSTer` (HEAD `6cda9cc546c4b32e256a19931128b82586253812`) returns exactly one
   hit and it is a false positive — `support/atari8bit/atari800.cpp:838
   #define AU_FULL_ROTATION 26042`. Nothing in MiSTer userspace knows this driver exists;
   the only userspace contract is `wpa_supplicant -D nl80211` over the standard `wlanN`
   netdev, same as every other WiFi driver in the image.

**The policy constraint (ADR 0016), restated so the decision cannot drift from it:** an
out-of-tree driver is admissible **only** for a chip mainline cannot drive (§3: satisfied,
in three trees), and **only as a Buildroot `kernel-module` package** — never as a 70–82 k-line
in-tree patch. A patch of this size in `board/mister/de10nano/linux-patches/` would make
`scripts/export-kernel-tree.sh`'s per-patch replay and `scripts/lint-kernel-patches.sh`
meaningless for that entry, which is PLAN §2.9's own reasoning and I found nothing to
contradict it. **In-tree carry is off the table regardless of which option below is chosen.**

---

## 8. Options

### (P) Package now — `package/aic8800` + `package/aic8800-firmware`

**Work.** Two Buildroot packages plus defconfig/doc wiring:

- `package/aic8800/{Config.in,aic8800.mk,aic8800.hash}`, modelled directly on
  `package/rtl8852cu-morrownr/`. `AIC8800_MODULE_MAKE_OPTS = CONFIG_AIC8800_WLAN_SUPPORT=m
  CONFIG_AIC_LOADFW_SUPPORT=m` **on one unwrapped line** — `scripts/export-kernel-tree.sh`
  lifts it with `sed -n "s/^${upper}_MODULE_MAKE_OPTS = //p"` and a `\`-continuation would
  capture a bare backslash (that constraint is documented in `rtl8852cu-morrownr.mk` and
  applies verbatim). No `KSRC=` needed (§6). Two modules from one source tree means either
  two `M=` invocations in a custom `_BUILD_CMDS`, or building the `aic8800/` parent directory
  with the parent `Makefile`'s `obj-$(CONFIG_…) += subdir/` lines — **verify which, the
  kernel-module infra's single `M=` assumes one directory.**
- `AIC8800_SITE = $(call github,<owner>,<repo>,$(AIC8800_VERSION))` with `AIC8800_VERSION`
  a **commit SHA** — which requires §1.2 to be finished first. **This is the gating item:
  today there is no repo to pin.**
- `AIC8800_LICENSE = GPL-2.0` (on the strength of three `MODULE_LICENSE("GPL")` macros,
  with a comment saying exactly that) and `AIC8800_LICENSE_FILES = <whatever the pinned repo
  has>` — **there is no licence file in the fork's copy** (§1.3), so this is another reason
  the pin must be a repo, not the fork.
- A firmware package: either a `linux-firmware-extra`-style copy-out (if `linux-firmware`
  turns out to carry `aic8800/`) or its own hash-pinned fetch from the vendor repo.
  **Undetermined (§2.4).**
- Renovate per `docs/renovate.md`: this joins the "driver commit-SHA pins" manager family —
  one `customManagers` regex over `package/aic8800/aic8800.mk`, `git-refs` datasource
  tracking upstream's default-branch HEAD via `currentDigest`, and the package name added to
  `HASH_SYNC_PACKAGES` so `renovate-hash-sync.yml`'s generic loop refreshes
  `aic8800.hash`. That takes the count from 10 driver pins to 11 (and to 12 if the firmware
  package is separately pinned), and both must be added to the workflow's `paths:` filter or
  nothing fires on a bump. The `.hash` file must be produced by
  `make aic8800-source` and hashing what lands in `dl/`, not by hashing a hand-download —
  the convention `rtl8852cu-morrownr.hash`'s header states.

**Supply-chain risk: HIGH, and higher than any existing package here.** Unknown upstream
(§1.2), no licence file (§1.3), no README stating a supported kernel range, no
`MAINTAINERS`-style contact, an SDK snapshot generated from a *dirty* working tree
(`1a4b0054dM`), and 51 of 139 files with neither a copyright line nor a licence. Compare
`rtl8852cu-morrownr`, whose worst supply fact was "upstream's README says 6.18 is only
community-supported" — we at least had a README to read.

**Image size: 206,828 B (~202 KiB) of `.ko.xz` for the two modules** — measured, §6. Cheap,
and ~9× cheaper than `rtl8852cu-morrownr`. **Plus** the firmware package: unmeasured, and
~60 blobs is not nothing; budget low single-digit MB until someone counts. Expect the
firmware to dominate this line item entirely.

**A maintainer must verify:** (1) the upstream repo and commit, by the `1a4b0054d2M` /
`2026_0123_5f7be68d` grep; (2) that that repo has a licence file and a firmware directory,
and that the firmware is redistributable; (3) on hardware, that `aic_load_fw` and
`aic8800_fdrv` do not race on the six shared USB IDs (§4); (4) the two-module build —
`pkg-kernel-module.mk` issues a single `M=`, and `aic8800_fdrv` will not modpost without
`aic_load_fw`'s `Module.symvers` (§6, nine undefined symbols), so this needs custom
`_BUILD_CMDS` doing two ordered `M=` passes with `KBUILD_EXTRA_SYMBOLS`; (5) the
`CONFIG_DEBUG_FS ?=` collision (§5.3) — decide whether to eat `rwnx_debugfs.o` or patch the
switch name; (6) a 7.2.x build for the RT variant (the 7.1/7.2 compat guards say it should
work; I did not compile it).

### (D) Defer — record stays `needs-verification`, nothing ships

**Work: ~zero now.** Write this memo and the record (done), open a tracked follow-up with the
two concrete questions (upstream repo identity + firmware source/licence), and let
`fork-sync.conf` advance without being blocked — PLAN §2.9 explicitly permits that, and
`needs-verification` is a disposition under the schema.

**Supply-chain risk: none taken.** **Image size: 0.**

**What we give up:** users with an AIC8800 dongle keep getting nothing, and if stock ships
the driver in the next release we are behind stock on that one axis. Both are recoverable at
any time — the build works (§6), so re-opening this is a packaging exercise, not a research
one.

**Re-open trigger, stated so it does not rot:** the moment *either* (a) stock's
`firmware.tar.gz` gains `fmacfw_*`/`fw_patch_*` entries, or (b) someone identifies the
upstream repo and it carries both a licence file and the firmware. Cheap to re-check: one
`tar tzf` and one `git grep`.

### (X) Decline

**Work: zero.** Record it as declined with this memo as the reason, and stop re-examining it
on every fork sync.

**Only defensible if** the owner is willing to say "we do not ship vendor Wi-Fi blobs of
unknown provenance, full stop" as a standing rule. That is a coherent position, but it is
**not** the position ADR 0016 currently takes (it kept `rtl8852cu-morrownr` on exactly the
"mainline can't drive this chip" ground AIC8800 also satisfies), so choosing X means
amending ADR 0016 rather than applying it. Declining on the *evidence* rather than on a rule
would be wrong: nothing here is disqualifying, several things are merely unknown.

### Recommendation

**(D) Defer.** Single strongest reason:

> **A package built today ships a module that cannot bring up an interface.** The driver
> reads ~60 firmware blobs from `/lib/firmware` (§2.2) and stock's own Release 20260907
> `firmware.tar.gz` contains **0 of 104** entries matching them (§2.3) — with no firmware
> commit anywhere in the fork's history — so the only thing option (P) can deliver right now
> is dead code plus a source tarball with no licence file. The build result (§6) removes the
> *technical* objection permanently and cheaply, which is exactly why deferring costs almost
> nothing: when the firmware and the upstream pin appear, this becomes a mechanical
> packaging job with the hard question already answered.

---

## 9. Addendum (2026-09-10) — the three network-gated questions, answered

**The recommendation is unchanged: defer.** Two of this memo's open questions are now
closed and a third is closed enough to change *why* we defer, not *whether*. The memo was
written without network access and names several things "a human must do with network
access"; they were done on 2026-09-10 from a session that has it. Findings in order of
decisiveness.

### 9.1 Stock ships nothing yet — the driver is inert on stock too

`MiSTer-devel/Linux-Kernel_MiSTer` re-fetched: `MiSTer-v6.18` HEAD is **still
`c129b0fac3`**, and `git log --all -i --grep=aic` over every ref returns that one commit.
No firmware commit has followed it.

`MiSTer-devel/Linux_Image_creator_MiSTer` — where stock's `firmware.tar.gz` actually lives
— has its newest commit at **`d4e3f51ec` "Release 20260907." (2026-09-07)**, which
*pre-dates* the driver commit. Nothing since.

**So "stock added AIC8800" means stock added the *source*.** No stock release ships either
the module or the blobs, and one that shipped the module today would behave exactly as §2.3
predicts. We are not behind stock in any way a user can observe, and §7.1's parity argument
therefore has no deadline attached to it.

### 9.2 `linux-firmware` does not carry it — confirmed in both trees

§2.4's first bullet is closed, with the answer the memo expected but could not check:

```
output/build/linux-firmware-20260410/WHENCE       0 hits  (aic8800|aicsemi|fmacfw|rwnx)
gitlab.com/kernel-firmware/linux-firmware @ main  0 hits  (same four strings)
torvalds/linux @ master  MAINTAINERS              0 hits  (aic8800)
```

There is no `aic8800/` directory in our pinned tree either. This will not change while
mainline has no driver to `request_firmware()` it, so `package/linux-firmware`'s
sub-options are permanently not the answer here.

### 9.3 The vendor snapshot is identified, and the D80 firmware exists publicly

§1.2 asked for a grep of `RWNX_VERS_REV` against candidate trees.
`goecho/aic8800_linux_drvier` — this memo's own second candidate, 98 stars, pushed
2026-09-07 — is a **revision match on the exact string**:

```
fork c129b0fac3  RWNX_VERS_REV "1a4b0054d2M (master)"  MOD "6.4.3.0"  RELEASE_DATE "2026_0123_5f7be68d"
goecho    HEAD   RWNX_VERS_REV "1a4b0054d2M (master)"  MOD "6.4.3.0"  RELEASE_DATE "2024_0420_24c7777c"
```

Same vendor git revision `1a4b0054d2`, same SDK version 6.4.3.0, different SDK packaging
date — the same rwnx snapshot re-released. Same layout, too
(`drivers/aic8800/{Kconfig,Makefile,aic8800_fdrv,aic_load_fw}`).

Its `fw/aic8800D80/` carries **every blob §2.2 names for the Tenda U11 / U11 Pro path**:

| File | Bytes |
|---|---:|
| `fmacfw_8800d80_u02.bin` | 327,620 |
| `fmacfw_8800d80_u02_ipc.bin` | 326,033 |
| `lmacfw_rf_8800d80_u02.bin` | 227,839 |
| `fw_patch_8800d80_u02.bin` | 25,300 |
| `fw_patch_table_8800d80_u02.bin` | 984 |
| `fw_adid_8800d80_u02.bin` | 1,708 |
| `calibmode_8800d80.bin` | 17,076 |
| `fw_ble_scan_ad_filter.bin` | 328,508 |
| `aic_userconfig_8800d80.txt` | 2,448 |

**`radxa/aic8800`, this memo's first-choice candidate, is a 404** — it does not exist.

**This does not unblock option (P), for three reasons worth stating explicitly:**

1. **The `LICENSE` is MIT, and that is a repackager's grant, not the vendor's.** §1.3's
   findings stand unchanged — the sources declare `MODULE_LICENSE("GPL")`, many files carry
   no grant at all, and two are Apache-2.0. A third party attaching MIT to an AICSemi SDK
   snapshot gives `*_LICENSE_FILES` something to point at while making the provenance claim
   *less* defensible, not more. The same objection applies to
   `Kiborgik/aic8800dc-linux-patched` (GPL-3.0 at repo level, on a tree whose modules
   declare GPLv2).
2. **Coverage is one chip variant.** Nine D80 files against §2.2's ~60. `Kiborgik/…`
   carries `fw/aic8800DC` and nothing else. Assembling a full set means pinning several
   unrelated strangers' repos — the opposite of the single-SHA pin every other package in
   this tree has.
3. **Still no hardware.** §4's two-module USB-ID race is unchanged and not closable by
   reading source.

### 9.4 New finding — the blobs do **not** go flat in `/lib/firmware`

Not asked by this memo; found while answering 9.1. It is a trap for whoever eventually
packages this — us *or* Sorgelig.

Because `CONFIG_USE_FW_REQUEST ?= n` in both Makefiles (§2.1) the driver never uses the
kernel firmware loader, so none of `/lib/firmware`'s normal search behaviour applies. It
`filp_open()`s a path it concatenates itself, and **both stages append a per-chip
subdirectory**:

- `aic_load_fw/aicbluetooth.c:145-150` — `CONFIG_PLATFORM_UBUNTU ?= y`
  (`aic_load_fw/Makefile:26`), so the compiled-in default is
  `aic_default_fw_path = "/lib/firmware"` (the `#else` is Android's
  `/vendor/etc/firmware`).
- `aic_load_fw/aicbluetooth.c:320-337` — `aic_fw_path` is a `module_param_string` that
  defaults to empty, so the `strlen(aic_fw_path) > 0` test fails and the
  `CONFIG_PLATFORM_UBUNTU` branch builds `"%s/%s/%s"` =
  `/lib/firmware/aic8800D80/<name>`, switched on `usb_dev->chipid`.
- `aic8800_fdrv/rwnx_utils.c:34-35` takes the bare `/lib/firmware` from `get_fw_path()`
  (`aicbluetooth.c:868-874`) and the per-variant init `strcat`s the subdir itself —
  `aicwf_compat_8800d80.c:43` `"/aic8800D80"`, `rwnx_platform.c:1672` `"/aic8800DC"`,
  `:1811` `"/aic8800D80N"`, `:1841` `"/aic8800DLN"`,
  `aicwf_compat_8800d80x2.c:44` `"/aic8800D80X2"`.

Both stages converge on **`/lib/firmware/aic8800D80/fmacfw_8800d80_u02.bin`**, which is
exactly goecho's `fw/aic8800D80/` layout.

**Consequence.** Dropping the blobs flat into `/lib/firmware/` — what
`package/linux-firmware-extra` and every other firmware in this image does, and the obvious
thing for a `firmware.tar.gz` to do — yields a driver that still fails, silently, with only
`firmware path = /lib/firmware/fmacfw_8800d80_u02.bin` in `dmesg` to say why. Any future
`package/aic8800-firmware` must install into the per-chip subdirectory. Equally, if a stock
release ships AIC blobs flat, that is a stock bug and not a layout to copy.

### 9.5 What this changes

Nothing in the recommendation. §8 deferred because a package built today ships dead code,
and that is still exactly true. What changed is that the **cheapest unblock path is now
concrete**:

> Wait for a stock release whose `firmware.tar.gz` contains the AIC blobs, then mirror them
> the way `package/linux-firmware-extra` mirrors `linux-firmware`, subject to 9.4's layout
> requirement. That converts §1.3's licence question into the same redistribution posture
> this image already accepts for every other blob it ships, rather than a novel one — and
> waiting costs nothing, because stock's own driver does not work until that happens either.

**Re-check trigger for the next fork sync:** `git -C <fork> log --all -i --grep=aic`
returning more than one commit, **or** any new commit on
`MiSTer-devel/Linux_Image_creator_MiSTer` after `d4e3f51ec`.

---

## 10. Decision REVERSED (2026-09-10) — packaged after all

**This memo's recommendation no longer describes what the image does.** Owner decision,
2026-09-10: package the driver and its firmware, licence ambiguity accepted rather than
resolved. `package/aic8800` ships both. Everything above stands as the analysis that
produced the original defer, and §9 stands as the follow-up that closed its open
questions; this section records why the conclusion flipped anyway.

**What the owner weighed**, neither of which is a §1.3 or §2 blocker being solved:

1. Stock is clearly heading for shipping the chip — 82 k lines do not get vendored
   speculatively — and §9.1 shows "wait for stock's `firmware.tar.gz`" had no visible end
   date. The wait costs our users a driver for an unbounded period.
2. MiSTer resellers bundle these dongles, so the failure mode is not "an unsupported
   cheap stick" but "the WiFi that came in the box does not work".

**What §9.3 got wrong, and it matters.** §9.3 named `goecho/aic8800_linux_drvier` as the
firmware source and judged coverage "one chip variant, nine D80 files against §2.2's
~60". That was the best source *found*, not the best source. The real one is
**`radxa-pkg/aic8800`** — the repository §1.2 guessed at as `radxa/aic8800` and §9.3
recorded as a 404, under a different org name. It carries:

- the **identical** SDK snapshot to stock (`RELEASE_DATE "2026_0123_5f7be68d"`, and its
  release tags spell `5.0+git20260123.5f7be68d-N`), so the file inventory matches stock's
  at 111/110 and 24/23 — unlike goecho's, which is an older drop missing the 8800D80N,
  8800D80X2 and 8800DLN variants entirely;
- **all six** firmware variant directories, 84 files, 6.6 MiB, in the per-chip layout
  §9.4 established the driver requires;
- a `debian/copyright` that at least states a position on `src/*`, and org maintenance
  with tagged releases rather than an individual's mirror.

**And a blocker this memo never identified.** §6 reported that the driver "compiles and
modpost clean for 32-bit ARM". That was measured against **stock's** copy, which is
pre-merged with kernel-API compat fixes — 186 `LINUX_VERSION_CODE` guards covering 6.17,
7.1 and 7.2. The **raw vendor SDK does not build on 6.18**: the cfg80211 `get_txpower` op
gained `radio_idx`/`link_id` in 6.17, and a control build of the pristine radxa tree fails
at `rwnx_main.c:6430` with an incompatible-pointer error. radxa keeps those fixes in
`debian/patches/`, which the package therefore applies. Had this memo's §6 result been
carried straight into a package built from any raw-SDK source, it would have been a green
finding attached to a tree that does not compile. Details, and the four patches
deliberately skipped: `docs/wifi-parity.md` §10.1.

**Current state:** built clean against the pinned 6.18.50, 194,112 bytes of `.ko.xz` plus
6.6 MiB of firmware, DE10 only, no hardware test yet. The record for this commit
(`docs/kernel-recon/records/c129b0fac34ad5d613bbec3f59d6036775e41c83.json`) is
dispositioned accordingly.

---

## Appendix — reproduction commands

```bash
S=<scratchpad>          # fork-6.18, linux (6.18.49), linux-7.2 (7.2.3), mainline (7.3-rc2), lic
git -C $S/fork-6.18 show --numstat --format="" c129b0fac | awk '{a+=$1;n++} END{print n" files, "a" ins"}'
git -C $S/fork-6.18 show c129b0fac -- arch/arm/configs/MiSTer_defconfig

# mainline absence (all three trees, all five strings)
for T in mainline linux linux-7.2; do for p in aic8800 aicwf AICSemi RivieraWaves rwnx; do
  echo "$T $p $(grep -ril "$p" $S/$T/drivers $S/$T/MAINTAINERS $S/$T/net 2>/dev/null | wc -l)"; done; done

# stock firmware
tar tzf $S/lic/firmware.tar.gz | wc -l
tar tzf $S/lic/firmware.tar.gz | grep -icE 'aic|fmacfw|fw_patch|fw_adid|8800'

# build — full sequence (§6). W = your own tmp dir; nothing is written into $S.
git -C $S/fork-6.18 archive c129b0fac drivers/net/wireless/aic8800 | tar -x -C $W/src
D=$W/src/drivers/net/wireless/aic8800
cp board/mister/de10nano/linux.config $W/kbuild/.config
K="make -C $S/linux O=$W/kbuild ARCH=arm LLVM=1 -j$(nproc)"
$K olddefconfig && $K prepare modules_prepare
$K vmlinux && $K modules                      # only to obtain Module.symvers (~25 min)
$K M=$D/aic_load_fw  CONFIG_AIC_LOADFW_SUPPORT=m  modules
$K M=$D/aic8800_fdrv CONFIG_AIC8800_WLAN_SUPPORT=m \
     KBUILD_EXTRA_SYMBOLS=$D/aic_load_fw/Module.symvers modules

# the rtl8852cu question, answered directly
llvm-nm -u $D/aic8800_fdrv/aic8800_fdrv.o | grep -E '__aeabi|__udiv|_uldivmod'
grep -n 'EXPORT_SYMBOL(__aeabi_' $S/linux/arch/arm/kernel/armksyms.c

# image cost
llvm-strip --strip-debug aic8800_fdrv.ko -o f.ko && xz -9 -c f.ko | wc -c
```
