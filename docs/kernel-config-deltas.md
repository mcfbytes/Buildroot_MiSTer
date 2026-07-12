# Kernel config deltas (P1.3 / constraints A3, A4, A5, A11)

How `board/mister/de10nano/linux.config` was derived, and **every** intentional divergence
from (a) the extracted stock 5.15 config and (b) the 6.18 `multi_v7_defconfig` baseline.

Every claim below is either a `file:line` in the pinned 6.18.38 tree, a line in the stock
config, or the literal output of a command reproduced here. Nothing is asserted from memory —
Phase 0's lesson was that plausible assumptions about this kernel keep turning out false, and
this task found **three more** that would have shipped silently.

## Sources

| Thing | Identity |
|---|---|
| Kernel | `linux-6.18.38` (current 6.18 longterm), from `https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.38.tar.xz` |
| **Kernel tarball SHA-256** | **`ac26e508abd56e9f8b89872b6e10c49fc823bcc70d8068a5d8504c1a7c4ff045`** — recomputed locally and matched byte-for-byte against kernel.org's published clearsigned `v6.x/sha256sums.asc` |
| Stock config | `docs/stock-inventory/stock-linux.config` — 4,246 lines, IKCONFIG-extracted from the shipped 5.15.1-MiSTer `zImage_dtb`. This is ground truth for what stock *ran*, not what someone believes it ran. |
| Baseline | `arch/arm/configs/multi_v7_defconfig` @ 6.18.38 |
| Deliverable | `board/mister/de10nano/linux.config` — 430 lines, `savedefconfig` output |
| kconfig host | host gcc 15.2.0 (Ubuntu). **No cross-compiler is required for any kconfig target** — `olddefconfig` / `savedefconfig` / `listnewconfig` only need `CC` to probe compiler capabilities. |

The kernel tree lives in gitignored `work/linux-6.18.38/` (standing rule 1). Only the
`.config` and this document are committed.

---

## 1. Method, and the exact commands

```sh
# 1. fetch + verify
cd work
curl -fsSLO https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.38.tar.xz
curl -fsSLO https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
sha256sum linux-6.18.38.tar.xz            # -> ac26e508...f045
grep -F linux-6.18.38.tar.xz sha256sums.asc   # -> ac26e508...f045   MATCH
tar xf linux-6.18.38.tar.xz

# 2. port the stock config forward
cp ../docs/stock-inventory/stock-linux.config work/kbuild/stockport/.config
cd linux-6.18.38
make ARCH=arm O=../kbuild/stockport listnewconfig     # 362 new symbols
make ARCH=arm O=../kbuild/stockport olddefconfig

# 3. apply the intentional divergences (§2)
./scripts/kconfig/merge_config.sh -m -O ../kbuild/stockport \
      ../kbuild/stockport/.config ../divergences.fragment
make ARCH=arm O=../kbuild/stockport olddefconfig

# 4. canonicalise
make ARCH=arm O=../kbuild/stockport savedefconfig
cp ../kbuild/stockport/defconfig ../../board/mister/de10nano/linux.config

# 5. baseline for comparison
make ARCH=arm O=../kbuild/multiv7 multi_v7_defconfig
```

**Round-trip proof (the deliverable is lossless).** `savedefconfig` emits a *minimal*
defconfig — every symbol at its default is elided. That is exactly how Buildroot consumes a
custom kernel config (copy to `.config`, then `olddefconfig`), so the round-trip is the
correct correctness check:

```sh
cp board/mister/de10nano/linux.config work/kbuild/roundtrip/.config
make ARCH=arm O=work/kbuild/roundtrip olddefconfig
diff -q work/kbuild/stockport/.config work/kbuild/roundtrip/.config
# -> files are identical
```

⚠ **Consequence for anyone writing a checker:** several load-bearing symbols
(`CONFIG_DEVMEM=y`, `# CONFIG_STRICT_DEVMEM is not set`, `# CONFIG_ARM_APPENDED_DTB is not
set`, `CONFIG_CMDLINE=""`) are **at their kconfig defaults on 32-bit ARM and therefore do
NOT appear in the 430-line defconfig.** `docs/boot-chain.md` §8.7's script must be run
against the **expanded `.config`**, not against `board/mister/de10nano/linux.config`. Running
it against the defconfig would fail every one of those `req` lines for the wrong reason. This
is a trap in its own right and P1.11/CI must not fall into it.

### Scale of the port

| | Symbols set |
|---|---|
| Stock 5.15 config | 1,170 |
| **Ours (6.18.38, expanded)** | **1,310** |
| `multi_v7_defconfig` (6.18.38, expanded) | 3,951 |
| Our `savedefconfig` output | 430 lines |
| Modules (`=m`) in ours | 43 |

`multi_v7_defconfig` sets **3× more symbols** than we do — it is a generic
"boot 40 different ARM SoCs" config. That is one reason it is the wrong starting point; §6
gives the reason that actually *forced* the decision.

---

## 2. Intentional divergences from the stock config

Nine changes. Every one is deliberate; every one is cited.

| # | Symbol | Stock | **Ours** | Why | Authority |
|---|---|---|---|---|---|
| **D1** | `CONFIG_BLK_DEV_INITRD` | **not set** | **`y`** | `CONFIG_INITRAMFS_SOURCE` *depends on it*. Without this the kernel has **no initramfs slot at all**, silently deleting the mechanism PLAN §5 uses to remove the out-of-tree `loop=` patch. | **A11**; `docs/boot-chain.md` §8.2/I1; PLAN §5 |
| **D2** | `CONFIG_MODULE_COMPRESS` | *(did not exist)* | **`y`** | **New parent bool in 6.18.** See §3.1 — without it, `MODULE_COMPRESS_XZ` ceases to exist and A5's `.ko.xz` layout silently breaks. | **A5**; `kernel/module/Kconfig:343` |
| **D3** | `CONFIG_MODULE_COMPRESS_XZ` | `y` | `y` | Stock parity — but it only *survives* because of D2. | **A5** |
| **D4** | `CONFIG_LEDS_CLASS_MULTICOLOR` | not set | **`y`** | **New dependency in 6.18** for `HID_LOGITECH` and `HID_PLAYSTATION`. See §3.2. | `drivers/hid/Kconfig:643`, `:993` |
| **D5** | `CONFIG_NETFILTER_XTABLES_LEGACY`, `CONFIG_IP_NF_IPTABLES_LEGACY` | *(did not exist)* | **`y`** | **New gate in 6.18** for legacy iptables. Restores `IP_NF_FILTER` + `IP_NF_TARGET_REJECT`, which stock had and which stock's iptables userland needs. See §3.3. | `net/netfilter/Kconfig:761`; `net/ipv4/netfilter/Kconfig:187` |
| **D6** | `CONFIG_FAT_DEFAULT_UTF8` | **not set** | **`y`** | The vfat fallback must decode long filenames as UTF-8. Spelled `utf8=1`, **never** `iocharset=utf8` (`Documentation/filesystems/vfat.rst:72` deprecates the latter). | **ADR 0010(b)**; A2 |
| **D7** | `CONFIG_FAT_DEFAULT_IOCHARSET` | `"iso8859-1"` | `"iso8859-1"` *(unchanged — deliberately)* | ADR 0010 is explicit: **do not "helpfully" change this.** `utf8=1` and `iocharset=` are different knobs; `iocharset=utf8` takes the wrong (byte-at-a-time NLS) code path. Recorded here because leaving it alone *is* the decision. | **ADR 0010(b)** |
| **D8** | `CONFIG_NTFS3_FS` | *(no NTFS at all)* | **`m`** | Pure addition. **Module, not built-in** — it must not consume `zImage` budget (P1.11). Ships **disabled by default** until stock parity is demonstrated (P2.9). | **ADR 0013** |
| **D9** | `CONFIG_HID_LOGITECH{,_DJ,_HIDPP}`, `LOGITECH_FF`, `LOGIG940_FF`, `LOGIRUMBLEPAD2_FF`, `LOGIWHEELS_FF`, `HID_PLAYSTATION`, `PLAYSTATION_FF` | `y` | `y` | Stock parity — but they only survive because of D4. See §3.2. | stock config; §3.2 |

**D1 is the one the task text warned about. D2, D4/D9 and D5 are three more of the same
shape that nobody had found**, and they are the substance of this task. They are written up
in §3.

### What is *not* divergent, stated explicitly because it looks like it should be

* `CONFIG_INITRAMFS_SOURCE` is `""` in our config, and absent from the `savedefconfig` output
  (empty string is the default). **This is correct.** D1's job is to make the *slot exist*;
  **P1.10 owns the value**, which points at the stage-1 cpio. `docs/boot-chain.md` §8.2/I2
  asserts it non-empty — that assertion belongs to the P1.10 build, not to this file.
* All seven `CONFIG_RD_*` decompressors (`GZIP BZIP2 LZMA XZ LZO LZ4 ZSTD`) came on as
  defaults of D1. Left alone on purpose: they are a few KB, the `zImage` budget has ~9 MiB of
  headroom (`docs/boot-chain.md` §7.3), and trimming them creates a way for P1.10 to pick an
  `INITRAMFS_COMPRESSION` whose decompressor is missing — a self-inflicted brick. Noted as a
  size-trim opportunity for P1.11, not taken now.

---

## 3. The three silent losses `olddefconfig` would have shipped

This is the part of the task that was not on the checklist. Each of these is a symbol that
was **`=y` in stock**, that **vanished entirely** from the ported config, and that
`olddefconfig` removed **without a single line of output**. None of them would have failed a
build. All three would have failed on a user's desk.

The general shape — and the reason A11 is not a one-off — is:

> **When a 6.x kernel adds a new gating symbol above an existing one, `olddefconfig` sets the
> new gate to its default (usually `n`), which makes the old symbol invisible, which makes
> `olddefconfig` drop it from the output. The old symbol's `=y` in your source config is
> silently discarded.** `listnewconfig` reports the *new gate*, not the *lost leaf*, so
> reading `listnewconfig` output does not reveal the loss either.

The only way to find these is to diff the **enabled-symbol sets** before and after. That diff
is §4.

### 3.1 `MODULE_COMPRESS_XZ` — A5's `.ko.xz` layout, silently gone

Stock: `CONFIG_MODULE_COMPRESS_XZ=y`. After a faithful `olddefconfig`: **the symbol does not
exist in the output at all.**

6.18 added a parent bool that 5.15 did not have:

> `kernel/module/Kconfig:343-357`
> ```
> config MODULE_COMPRESS
> 	bool "Module compression"
> 	help
> 	  ...
> 	  If unsure, say N.
>
> choice
> 	prompt "Module compression type"
> 	depends on MODULE_COMPRESS
> ```

In 5.15 the compressors were a top-level `choice` (with a `MODULE_COMPRESS_NONE` member) and
`MODULE_COMPRESS_XZ` was directly selectable. In 6.18 the whole choice `depends on
MODULE_COMPRESS`, which **defaults to `n`** ("If unsure, say N"). The stock config contains no
`CONFIG_MODULE_COMPRESS` line — it *could not*, the symbol did not exist — so `olddefconfig`
set it `n`, the choice became invisible, and `MODULE_COMPRESS_XZ` was dropped.

**Impact if shipped:** `make modules_install` emits plain `.ko` instead of `.ko.xz`. Stock
ships 52 `.ko.xz` modules (A5) and the rootfs `depmod`/`modprobe` stack expects that layout.
Modules get bigger and the on-disk layout stops matching stock — a parity break that would
surface as "some dongles don't autoload" long after the config was written.

**Fix: D2 + D3.** Verified `CONFIG_MODULE_COMPRESS=y`, `CONFIG_MODULE_COMPRESS_XZ=y`,
`CONFIG_MODULE_COMPRESS_ALL=y`.

### 3.2 Logitech + PlayStation HID — an entire controller family, silently gone

Stock had all of: `HID_LOGITECH`, `HID_LOGITECH_DJ`, `HID_LOGITECH_HIDPP`, `LOGITECH_FF`,
`LOGIG940_FF`, `LOGIRUMBLEPAD2_FF`, `LOGIWHEELS_FF`, `HID_PLAYSTATION`, `PLAYSTATION_FF` — all
`=y`. After `olddefconfig`: **all nine gone.**

6.18 added a dependency neither driver had in 5.15:

> `drivers/hid/Kconfig:639-644`
> ```
> config HID_LOGITECH
> 	tristate "Logitech devices"
> 	depends on USB_HID
> 	depends on LEDS_CLASS
> 	depends on LEDS_CLASS_MULTICOLOR      <-- new
> 	default !EXPERT
> ```
> `drivers/hid/Kconfig:991-993`
> ```
> config HID_PLAYSTATION
> 	tristate "PlayStation HID Driver"
> 	depends on LEDS_CLASS_MULTICOLOR      <-- new
> ```

`CONFIG_LEDS_CLASS_MULTICOLOR` is `n` by default and stock never set it (in 5.15 it was
irrelevant to HID). So both drivers became invisible and were dropped, taking their
force-feedback sub-options with them.

Note the second trap in `HID_LOGITECH`: `default !EXPERT`. Our config has `CONFIG_EXPERT=y`
(inherited from stock's `CONFIG_EMBEDDED=y`, which `select`s it). So even with the
`LEDS_CLASS_MULTICOLOR` dependency satisfied, `HID_LOGITECH` would **still** have defaulted
to `n`. It must be set explicitly — which is why D9 lists all nine symbols rather than
relying on defaults.

**Impact if shipped:** every Logitech gamepad/wheel (incl. force feedback) and every
DualSense/DualShock-4 controller stops working. On a retro-gaming console. This is the
single most user-visible regression the naive port would have produced, and it is completely
silent — no build error, no warning, just controllers that do nothing.

**Fix: D4 + D9.** Verified all nine now `=y`.

### 3.3 Legacy iptables — `IP_NF_FILTER` + `IP_NF_TARGET_REJECT`, silently gone

Stock had `CONFIG_IP_NF_FILTER=y` and `CONFIG_IP_NF_TARGET_REJECT=y`, with
`CONFIG_IP_NF_IPTABLES=y`. After `olddefconfig`: `IP_NF_IPTABLES` **survives**, but the other
two **vanish**.

6.18 split legacy iptables behind a new gate:

> `net/ipv4/netfilter/Kconfig:184-187`
> ```
> config IP_NF_FILTER
> 	tristate "Packet filtering"
> 	default m if NETFILTER_ADVANCED=n || IP_NF_IPTABLES_LEGACY
> 	depends on IP_NF_IPTABLES_LEGACY          <-- new
> ```
> `net/ipv4/netfilter/Kconfig:14-18` — `IP_NF_IPTABLES_LEGACY` in turn
> `depends on NETFILTER_XTABLES_LEGACY` (`net/netfilter/Kconfig:761`), a bool that
> defaults `n`.
>
> `IP_NF_TARGET_REJECT` then `depends on IP_NF_FILTER || NFT_COMPAT`
> (`net/ipv4/netfilter/Kconfig:197`), so it falls with `IP_NF_FILTER`.

**Is this actually parity-relevant?** Yes — checked, not assumed. Stock ships the iptables
userland:

* `docs/stock-inventory/shared-libraries.md:221` — `libip4tc.so.2`
* `docs/stock-inventory/shared-libraries.md:387` — `libxtables.so.12`
* `docs/stock-inventory/shared-libraries.md:22` — **106** shared objects under `usr/lib/xtables`

`iptables-legacy` against a kernel with no `filter` table fails with *"Table does not exist
(do you need to insmod?)"*. Community scripts that firewall or NAT would break.

**Fix: D5.** Verified `NETFILTER_XTABLES_LEGACY=y`, `IP_NF_IPTABLES_LEGACY=y`,
`IP_NF_FILTER=y`, `IP_NF_TARGET_REJECT=y`.

---

## 4. Full audit: every symbol enabled in stock that is not enabled in ours

The diff that found §3. **86 symbols** were `=y`/`=m` in stock and are absent from the ported
config; **1** was demoted; **4** changed value. Every one is accounted for below — none is
unexplained.

### 4.1 Out-of-tree MiSTer code — expected absent, returns with its patch/package (23)

These are not upstream symbols. They exist only because the 5.15 fork carried the code
in-tree. They come back when the corresponding task lands, and **this config must not try to
set them** — kconfig would discard them.

| Symbols | Returns via |
|---|---|
| `FB_MISTER` | **P1.4** patch `0001-fbdev-add-MiSTer_fb-driver.patch` |
| `SND_MISTER_AUDIO` | **P1.5** patch `0002-…` |
| `ARM_SOCFPGA_CPUFREQ` | **P1.6** patch `0003-…` — confirmed **not in mainline 6.18** (`grep -rn SOCFPGA_CPUFREQ --include=Kconfig` → no match) |
| `HID_GUNCON2`, `HID_GUNCON3`, `HID_FTEC`, `HID_GAMECUBE_ADAPTER`, `HID_GAMECUBE_ADAPTER_FF` | **P1.9** |
| `JOYSTICK_XONE` | **P3.2** (Buildroot `kernel-module` package) |
| `RTL8188EU`, `RTL8188FU`, `RTL8812AU`, `RTL8821AU`, `RTL8821CU`, `RTL8822BU` | **P3.1** (morrownr Buildroot packages) |
| `EXFAT_DISCARD`, `EXFAT_DELAYED_SYNC`, `EXFAT_DEFAULT_CODEPAGE` | **never** — sub-options of the out-of-tree Samsung driver, **dropped by ADR 0010**. Mainline `EXFAT_FS=y` replaces it. |
| `FB_CMDLINE`, `FB_SYS_COPYAREA`, `FB_SYS_FILLRECT`, `FB_SYS_IMAGEBLIT` | **P1.4** — these are non-prompt symbols `select`ed *by* `FB_MISTER`. They vanished because the driver did, not because fbdev lost them. `FB_SYS_FILLRECT`/`FB_SYS_COPYAREA` still exist (`drivers/video/fbdev/core/Kconfig:61,69`); the modern aggregate is `FB_SYSMEM_HELPERS` (`:164`). **P1.4 should select `FB_SYSMEM_HELPERS`.** |

⚠ **Handoff to P1.4:** `CONFIG_FB_DEVICE=y` is a **new 6.18 symbol** (§5) and is what creates
the `/dev/fbN` nodes. It defaulted **on**, so `/dev/fb0` will exist — but it is now an
explicit symbol that can be turned off, and the ABI contract depends on it. Do not let it
drift.

### 4.2 Removed from the kernel entirely — no action possible, none needed (5)

| Symbol | Stock | Fate in 6.18 |
|---|---|---|
| `WIRELESS_EXT` | `y` | Still exists but is a **non-prompt `bool`** (`net/wireless/Kconfig:2-3`) — settable **only** by `select` from an in-tree driver. In stock, the *in-tree* Realtek drivers selected it. **Cannot be set from a defconfig** — proven: appending `CONFIG_WIRELESS_EXT=y` to `.config` and running `olddefconfig` drops it (0 occurrences remain). See the P3.1 handoff below. |
| `WEXT_SPY` | `y` | **Gone from the tree** (`grep -rn 'config WEXT_SPY' --include=Kconfig` → no match). |
| `LIB80211` | `m` | **Gone from the tree** (`grep -rn 'config LIB80211' --include=Kconfig` → no match). |
| `XZ_DEC_IA64` | `y` | Gone — IA-64 was removed from Linux. (6.18 defaults `XZ_DEC_ARM64`/`XZ_DEC_RISCV` on instead; minor size noise, see §5.) |
| `SMBFS_COMMON` | `y` | Restructured into `fs/smb/`. Our config has `CONFIG_SMBFS=y` (`fs/smb/Kconfig:8`) and `CONFIG_CIFS=y`. **cifs is built-in, per stock. ✔** |

> ⚠ **Handoff to P3.1 — the WEXT hazard, stated honestly.**
> The **kernel-side** WEXT plumbing is intact: `CONFIG_CFG80211_WEXT=y` survived the port and
> `select`s `WEXT_CORE` (`net/wireless/Kconfig:187-189`), so our config has
> `WEXT_CORE=y` + `WEXT_PROC=y` — same as stock.
> **But `CONFIG_WIRELESS_EXT` itself is now unset and cannot be set from a defconfig.** The
> morrownr Realtek drivers are compiled **out-of-tree**, so they cannot `select` it either.
> Any driver source that guards its WEXT paths with `#ifdef CONFIG_WIRELESS_EXT` will compile
> those paths **out**. This is not something P1.3 can fix and I have not verified whether the
> six morrownr drivers actually need it. **P3.1 must check this per-driver at build time**;
> if one does need it, the fix is a `select` in that package's Kbuild or a small kernel patch,
> not a defconfig line. Flagged rather than papered over.

### 4.3 Renamed / restructured — semantics preserved, **no divergence** (4 groups)

These look like regressions in the raw diff. They are not. Recorded so nobody "fixes" them.

| Stock (5.15) | Ours (6.18) | Why it is equivalent |
|---|---|---|
| `FORCE_MAX_ZONEORDER=11` | `ARCH_FORCE_MAX_ORDER=10` | Renamed **and the base changed from exclusive to inclusive** (mainline `23baf831a32c`). `include/linux/mmzone.h:29-34`: `MAX_PAGE_ORDER = CONFIG_ARCH_FORCE_MAX_ORDER` and `MAX_ORDER_NR_PAGES = 1 << MAX_PAGE_ORDER` → `1 << 10` = 1024 pages = **4 MiB**. In 5.15, `MAX_ORDER_NR_PAGES = 1 << (MAX_ORDER - 1)` = `1 << 10` = **4 MiB**. **Identical.** `10` is also the arch default (`arch/arm/Kconfig:1284`), so it does not even appear in our defconfig. |
| `CRYPTO_SHA1_ARM`, `CRYPTO_SHA256_ARM`, `CRYPTO_SHA512_ARM`, `ARM_CRYPTO` | `CRYPTO_LIB_SHA1_ARCH=y`, `CRYPTO_LIB_SHA256_ARCH=y`, `CRYPTO_LIB_SHA512_ARCH=y` | ARM crypto moved to `lib/crypto/` with `default y if ARM` (`lib/crypto/Kconfig:36,49`). **The ARM-accelerated implementations are still enabled, automatically.** No perf loss. |
| `CRYPTO_MANAGER_DISABLE_TESTS=y` | `# CONFIG_CRYPTO_SELFTESTS is not set` | Renamed **with inverted polarity** (`crypto/Kconfig:177-179`). Stock: tests *disabled*. Ours: tests *disabled*. **Same behaviour** — and it matters, because enabling them would add crypto self-test time to every boot, against a P2.9 gate that requires boot-to-menu ≤ stock. |
| `BASE_SMALL=0` | `# CONFIG_BASE_SMALL is not set` | Changed from `int` to `bool` upstream. `0` ≡ `n`. **Identical.** (This is the single "demoted" symbol in the audit.) |

`STACKPROTECTOR_PER_TASK=y` also disappeared (the ARM GCC plugin was removed upstream), but
`CONFIG_STACKPROTECTOR=y` and `CONFIG_STACKPROTECTOR_STRONG=y` **are both still set** —
verified. Stack protection is preserved; only the per-task-canary variant is gone. No action.

### 4.4 Internal / auto-generated symbols — noise (54)

Non-user-selectable symbols that kconfig or the build system sets: compiler-capability probes
(`CC_CAN_LINK`, `CC_HAS_ASM_GOTO`, `CC_HAS_SANCOV_TRACE_PC`, `AS_VFP_VMRS_FPINST`), arch
plumbing (`ARCH_HAS_PHYS_TO_DMA`, `DMA_OPS`, `DMA_REMAP`, `ARM_HAS_SG_CHAIN`, `HANDLE_DOMAIN_IRQ`,
`HAVE_FUTEX_CMPXCHG`, `HAVE_CONTEXT_TRACKING`, `ARCH_HAVE_CUSTOM_GPIO_H`, `ARCH_NR_GPIO`,
`ARCH_SUPPORTS_BIG_ENDIAN`, `SPLIT_PTLOCK_CPUS`, `SRCU`, `UNIX_SCM`, `KALLSYMS_BASE_RELATIVE`,
`PRINTK_SAFE_LOG_BUF_SHIFT`, `MDIO_DEVICE`, `MDIO_DEVRES`, `OF_NET`, `HW_CONSOLE`, `EMBEDDED`,
`BASE_FULL`, `CRC32_SLICEBY8`, `GCC_PLUGINS`, `GCC_PLUGIN_ARM_SSP_PER_TASK`,
`FTRACE_MCOUNT_RECORD`, `HAVE_HARDENED_USERCOPY_ALLOCATOR`, `CRYPTO_GF128MUL`, `CRYPTO_NULL2`,
`LSM` (inert — `CONFIG_SECURITY` is `n`, matching stock), `PANIC_ON_OOPS_VALUE`,
`BOOTPARAM_HUNG_TASK_PANIC_VALUE`, `PROC_PID_CPUSET`, `SND_HDA_PREALLOC_SIZE`, …).

Either removed upstream, folded into other symbols, or re-derived automatically. **No
user-visible effect.** These are why the raw "86 vanished" number is alarming and the real
number that mattered was **11** (§3).

### 4.5 The 4 changed values — all toolchain identity, all benign

`CC_VERSION_TEXT`, `GCC_VERSION`, `AS_VERSION`, `LD_VERSION` changed from the stock
`arm-none-linux-gnueabihf-gcc 10.2.1` to the host `gcc 15.2.0` used to *run kconfig*. These
are recorded by kbuild, not chosen by us; they will be overwritten with Buildroot's real
cross-toolchain identity when the kernel is actually compiled. **Not a divergence.**

---

## 5. The 362 newly-defaulted symbols

`make ARCH=arm listnewconfig` → **362** symbols that exist in 6.18 and did not in 5.15:
**41 default ON**, **311 default OFF**, **10 numeric/string**.

All 41 that came on were reviewed. Nothing hazardous; the ones that matter to us:

| New symbol | Value | Why it matters here |
|---|---|---|
| `FB_DEVICE` | `y` | **Creates the `/dev/fbN` nodes.** The `/dev/fb0` ABI (P0.5) now depends on this symbol existing and being on. Handoff to P1.4. |
| `BLOCK_LEGACY_AUTOLOAD` | `y` | Keeps the on-demand `loop_probe()` instantiation path alive. P1.10 uses `losetup -f` (`LOOP_CTL_GET_FREE`) per `docs/boot-chain.md` §8.3, so it does not *rely* on this — but it means both paths work. |
| `HID_SUPPORT` | `y` | New top-level gate above the whole HID stack. On. |
| `I2C_HID` | `y` | **Checked against A14** (Main_MiSTer never scans past `/dev/i2c-2`). `I2C_HID` lives in `drivers/hid/i2c-hid/Kconfig:2` — it is a **client/transport driver, not a bus adapter**. It registers **no i2c adapter** and therefore **cannot renumber `i2c-N`**. Confirmed the enabled i2c *adapter* set is byte-identical to stock (`I2C_DESIGNWARE_CORE`, `I2C_DESIGNWARE_PLATFORM`, `I2C_GPIO`, `I2C_CHARDEV`, `I2C_SMBUS` — no additions, no losses). **A14 is unaffected by this config.** The A14 risk lives entirely in the DTS (P1.7). |
| `VMAP_STACK`, `HARDEN_BRANCH_HISTORY`, `ARM_PAN` | `y` | New ARM defaults. `HARDEN_BRANCH_HISTORY` is a Spectre-BHB mitigation; Cortex-A9 is not a BHB-affected core, so this is near-free. Left at defaults. |
| `RANDSTRUCT_NONE` | `y` | No struct-layout randomisation — **required** for out-of-tree modules (A5) to have a stable struct ABI. Correct default; do not change. |
| `LEGACY_TIOCSTI`, `GPIO_SYSFS_LEGACY`, `DEVPORT` | `y` | Legacy userland compat, all on. Conservative, matches 5.15 behaviour. |
| `BLK_DEV_WRITE_MOUNTED` | `y` | Permits writes to a mounted block device. Needed for the updater's offline-image mount flow (A8). On by default. |
| `XZ_DEC_ARM64`, `XZ_DEC_RISCV` | `y` | Foreign-arch XZ BCJ filters. Pure size noise (a few KB). Size-trim candidate for P1.11; not taken (see §2). |

None of the 311 that defaulted off is one we need. Notably **no new hardening symbol
defaulted on that would threaten A4** — `STRICT_DEVMEM` remains `n` (see §6).

---

## 6. Divergence from the 6.18 `multi_v7_defconfig` baseline

The task asks this document to explain divergence from `multi_v7_defconfig` as well. The
honest answer is that `multi_v7_defconfig` **is not our baseline and could not have been** —
and the single line below is why.

| Symbol | `multi_v7` | **Ours** | Comment |
|---|---|---|---|
| **`ARM_APPENDED_DTB`** | **`y`** | **`n`** | 🚨 **`multi_v7_defconfig` sets it. A3/B1 forbids it.** U-Boot passes the DTB pointer explicitly in `r2` (`docs/boot-chain.md` §4.2), so the appended-DTB path is never taken — but leaving it on would **silently mask a broken `cat zImage dtb`** (the decompressor would find the DTB anyway), which is the exact bug class `scripts/check-zimage-dtb.sh` exists to catch. **Starting from `multi_v7_defconfig` would have violated A3 on line one.** This is the concrete reason the stock config is the correct baseline. |
| `STRICT_DEVMEM` | `n` | `n` | ✔ **Confirms the P0 finding**: `STRICT_DEVMEM` is *not* default-`y` on 32-bit ARM (`default y if PPC || X86 || ARM64 || S390`). A4 is an assertion, not a fight against a default — in *both* configs. |
| `DEVMEM` | `y` | `y` | ✔ A4 satisfied in both. |
| `EXFAT_FS` | **`n`** | `y` | multi_v7 has **no exFAT**. The data partition may be exFAT (A2) — the board would not boot. |
| `CIFS` | **`n`** | `y` | Stock has cifs built-in (P3.10). |
| `NTFS3_FS` | **`y` (built-in!)** | **`m`** | multi_v7 builds NTFS3 **into the kernel** — ADR 0013 requires a **module**, so it does not consume `zImage` budget (P1.11). |
| `FAT_DEFAULT_UTF8` | `n` | **`y`** | ADR 0010(b). |
| `KERNEL_LZ4` / `KERNEL_GZIP` | `n` / `y` | **`y`** / `n` | Stock parity (`docs/boot-chain.md` §8.6/P4). |
| `IKCONFIG`, `IKCONFIG_PROC` | `n` / — | **`y`**, **`y`** | Stock parity, and the mechanism that made this entire analysis possible (§8.6/P5). Keep. |
| `MODULE_COMPRESS{,_XZ}` | `n` / — | **`y`**, **`y`** | A5 — stock ships `.ko.xz`. |
| `LEDS_CLASS_MULTICOLOR` | `n` | **`y`** | §3.2 — multi_v7 would have dropped the Logitech/PlayStation drivers too. |
| `CPU_FREQ_DEFAULT_GOV_PERFORMANCE` | `n` | **`y`** | Stock parity (§7). |
| `IP_NF_FILTER` | — | **`y`** | §3.3. |
| `ARCH_INTEL_SOCFPGA`, `SMP`, `BLK_DEV_LOOP`, `BLK_DEV_LOOP_MIN_COUNT=8`, `EXT4_FS`, `VFAT_FS`, `NLS_UTF8`, `USB_DWC2`, `USB_STORAGE`, `NFS_FS`, `ATAGS` | `y` | `y` | Agree — no divergence. |

`multi_v7_defconfig` also sets **3,951** symbols to our **1,310**: it enables dozens of SoC
families, GPU drivers, and buses the DE10-Nano does not have. Using it would have inflated
the `zImage` against the 16 MiB budget (`docs/boot-chain.md` §7.3) for no benefit.

---

## 7. Stock-parity items explicitly re-verified (no divergence)

Checked because the task named them, and because "obviously it's still set" is exactly the
assumption Phase 0 kept disproving. All verified in the **expanded** `.config`.

| Constraint | Symbols | Result |
|---|---|---|
| **A4** — `/dev/mem` unrestricted | `DEVMEM=y`; `# STRICT_DEVMEM is not set`; `IO_STRICT_DEVMEM` absent (it `depends on STRICT_DEVMEM`) | ✔ survived `olddefconfig` untouched. Without this, `fpga_io.cpp`'s `/dev/mem` mmap fails and the entire FPGA path dies — **and** the `0x1FFFF000` warm-reboot mailbox becomes unreachable (`docs/boot-chain.md` §6.4). |
| **A3 / B1** — no appended DTB | `# CONFIG_ARM_APPENDED_DTB is not set`; `ARM_ATAG_DTB_COMPAT` absent | ✔ |
| **B5/B6/B7** — bootloader cmdline survives | `CONFIG_CMDLINE=""`; `CMDLINE_FORCE` **absent**; `CMDLINE_EXTEND` **absent** | ✔ `CMDLINE_FORCE` would `strlcpy()` over the bootloader cmdline (`drivers/of/fdt.c`), destroying `root=`, `loop=`, `ro` and `mem=511M` → **unbootable**. Per `docs/boot-chain.md` §8.1/B6, the *absence* of `CMDLINE_FROM_BOOTLOADER` is correct (it is a `choice` member gated on `CMDLINE != ""`), and has **not** been "fixed". |
| **B3/B4** | `USE_OF=y`; `ATAGS=y` (stock parity, dead code at boot) | ✔ |
| **A5** — modules | `MODULES=y`; `# MODULE_SIG is not set`; `MODULE_COMPRESS_XZ=y` (via D2) | ✔ signing **off** — required for out-of-tree modules. |
| **A1/A11** — initramfs | `BLK_DEV_INITRD=y` (D1); `INITRAMFS_SOURCE` now **exists** (`=""`, owned by P1.10) | ✔ |
| **L1/L2** — loop | `BLK_DEV_LOOP=y` (built-in — the initramfs mounts the image before any module could load); `BLK_DEV_LOOP_MIN_COUNT=8` | ✔ |
| **F1–F4** — filesystems, all **built-in** | `EXT4_FS=y`, `FAT_FS=y`, **`VFAT_FS=y`**, `EXFAT_FS=y`, `# MSDOS_FS is not set` | ✔ **`VFAT_FS=y` is load-bearing, not parity trivia** (ADR 0010(a)): mainline exfat cannot mount FAT32, and the rootfs is a file *on* that partition — without vfat, **FAT32 cards fail to boot.** |
| NLS codepages, built-in | `NLS_UTF8=y`, `NLS_CODEPAGE_437=y`, `NLS_ISO8859_1=y`, `NLS_ASCII=y` — **plus** `NLS_CODEPAGE_855/866/936/950/1251`, `NLS_ISO8859_5/15`, `NLS_KOI8_R/U`, `NLS_MAC_CYRILLIC`, `NLS_DEFAULT="iso8859-1"` | ✔ all preserved. **Correction to `docs/boot-chain.md` §8.4/F4**, which lists only 437/ISO8859-1/UTF-8/ASCII and says "Stock exactly these". Stock actually has **13** NLS codepages — the extra Cyrillic/CJK ones are real and are carried. A missing codepage makes the vfat mount fail *inside the initramfs*, before any module could load. |
| FAT defaults | `FAT_DEFAULT_CODEPAGE=437` (unchanged), `FAT_DEFAULT_IOCHARSET="iso8859-1"` (unchanged — D7), `FAT_DEFAULT_UTF8=y` (**changed** — D6) | ✔ |
| **C1** — serial console | `SERIAL_8250=y`, `SERIAL_8250_CONSOLE=y`, `SERIAL_8250_DW=y`, `SERIAL_OF_PLATFORM=y` | ✔ the only debug channel for P1.13. |
| Built-in, not modules | `USB_DWC2=y`, `USB_STORAGE=y`, `HID=y` | ✔ |
| Network filesystems | `CIFS=y`, `SMBFS=y`, `NFS_FS=y` — built-in per stock | ✔ (P3.10) |
| **cpufreq governors** | `CPU_FREQ=y`, `CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y`, `GOV_PERFORMANCE/POWERSAVE/USERSPACE/ONDEMAND/CONSERVATIVE/SCHEDUTIL=y`, `CPU_FREQ_STAT=y` | ✔ **byte-identical to stock, no intervention needed.** (The *driver*, `ARM_SOCFPGA_CPUFREQ`, arrives with P1.6 — §4.1.) |
| `KERNEL_LZ4=y`, `IKCONFIG=y`, `IKCONFIG_PROC=y`, `LOCALVERSION=""` | | ✔ stock parity. `IKCONFIG_PROC` is how a future maintainer audits *our* image, exactly as we audited stock's. |

---

## 8. Acceptance checklist (`docs/boot-chain.md` §8.7) — result

Run against the **expanded** `.config` (see the ⚠ in §1):

```
ok  # CONFIG_ARM_APPENDED_DTB is not set      ok  CONFIG_USE_OF=y
ok  CONFIG_CMDLINE=""                          ok  absent: ^CONFIG_CMDLINE_FORCE=y
ok  absent: ^CONFIG_CMDLINE_EXTEND=y           ok  CONFIG_BLK_DEV_INITRD=y
ok  CONFIG_BLK_DEV_LOOP=y                      ok  CONFIG_BLK_DEV_LOOP_MIN_COUNT=8
ok  CONFIG_EXT4_FS=y                           ok  CONFIG_VFAT_FS=y
ok  CONFIG_EXFAT_FS=y                          ok  CONFIG_NLS_CODEPAGE_437=y
ok  CONFIG_NLS_ISO8859_1=y                     ok  CONFIG_NLS_UTF8=y
ok  CONFIG_NLS_ASCII=y                         ok  CONFIG_SERIAL_8250_CONSOLE=y
ok  CONFIG_SERIAL_8250_DW=y                    ok  CONFIG_SERIAL_OF_PLATFORM=y
ok  CONFIG_DEVMEM=y                            ok  # CONFIG_STRICT_DEVMEM is not set
ok  absent: ^CONFIG_IO_STRICT_DEVMEM=y         ok  CONFIG_MODULES=y
ok  CONFIG_MODULE_COMPRESS_XZ=y                ok  absent: ^CONFIG_MODULE_SIG=y
ok  CONFIG_IKCONFIG=y                          ok  CONFIG_IKCONFIG_PROC=y
ok  CONFIG_KERNEL_LZ4=y                        ok  CONFIG_USB_DWC2=y
ok  CONFIG_USB_STORAGE=y                       ok  CONFIG_HID=y
ok  CONFIG_CIFS=y                              ok  CONFIG_NFS_FS=y
ok  CONFIG_FAT_DEFAULT_UTF8=y                  ok  CONFIG_FAT_DEFAULT_CODEPAGE=437
ok  CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"   ok  CONFIG_NTFS3_FS=m
ok  absent: ^CONFIG_NTFS3_FS=y

===> rc=0   (37/37)
```

`INITRAMFS_SOURCE` non-empty (§8.2/I2) and the `zImage` size budget (§8.2/I4) are **P1.10 and
P1.11 assertions**, not P1.3's — the slot exists, the value does not yet.

---

## 9. Handoffs

| To | Item |
|---|---|
| **P1.4** | `FB_SYS_*` are gone as standalone selects; select **`FB_SYSMEM_HELPERS`** (`drivers/video/fbdev/core/Kconfig:164`). `CONFIG_FB_DEVICE=y` is new and is what creates `/dev/fb0` — keep it on. |
| **P1.6** | `ARM_SOCFPGA_CPUFREQ` **is not in mainline 6.18** — patch `0003` must supply the Kconfig entry as well as the driver. |
| **P1.10** | Owns `CONFIG_INITRAMFS_SOURCE`. All seven `RD_*` decompressors are on, so any `INITRAMFS_COMPRESSION` choice will work. |
| **P1.11** | Size-trim candidates if the 16 MiB budget ever gets tight: `XZ_DEC_ARM64`, `XZ_DEC_RISCV`, and the six unused `RD_*` decompressors. Not taken now — ~9 MiB headroom. |
| **P3.1** | ⚠ **`CONFIG_WIRELESS_EXT` is unset and cannot be set from a defconfig** (non-prompt, `select`-only). `WEXT_CORE=y` via `CFG80211_WEXT`, so the kernel plumbing is there — but out-of-tree drivers guarding on `#ifdef CONFIG_WIRELESS_EXT` will compile those paths out. **Verify per-driver.** (§4.2) |
| **P1.7** | A14 is **not** at risk from this config — the i2c *adapter* set is identical to stock (§5). The risk is entirely in the DTS. |
| **`docs/boot-chain.md`** | §8.4/F4 understates the stock NLS set (13 codepages, not 4). §8.7's script must run against the expanded `.config`, not the `savedefconfig` output. (§7, §1) |

---

## 10. Compile proof — **DONE (with one documented gap)**

P1.2's cross-toolchain became available mid-task and the config was compiled for real.
The build started from the **committed deliverable**, exactly as Buildroot will consume it:

```sh
cp board/mister/de10nano/linux.config work/kbuild/proof/.config
cd work/linux-6.18.38
make ARCH=arm O=../kbuild/proof olddefconfig
make ARCH=arm O=../kbuild/proof \
     CROSS_COMPILE=.../output/host/bin/arm-buildroot-linux-gnueabihf- \
     Image dtbs modules -j"$(nproc)"
```

Toolchain: **`arm-buildroot-linux-gnueabihf-gcc (Buildroot 2026.02.3) 14.3.0`**.

| Target | Result |
|---|---|
| `vmlinux` | ✅ **linked**, 241,565,984 B (unstripped, with debug info) |
| `Image` | ✅ **`Kernel: arch/arm/boot/Image is ready`** — 17,826,268 B |
| `dtbs` | ✅ `socfpga_cyclone5_de10nano.dtb`, 19,011 B (the mainline DTB P1.7 will patch) |
| `modules` | ✅ **exit 0, 41 `.ko`, zero errors, zero warnings** |
| `ntfs3.ko` | ✅ present at `fs/ntfs3/ntfs3.ko` — **a module, not built-in.** ADR 0013 satisfied *in the built artifact*, not just in the config. |
| `zImage` | ⚠ **not produced — see below.** |

**Every symbol in this config compiles and links.** That includes the three §3 fixes, which
are the only symbols here that no previous MiSTer build has ever exercised on 6.18: the
Logitech/PlayStation HID drivers (via `LEDS_CLASS_MULTICOLOR`) and the legacy iptables
tables. Both built clean.

### The one gap: `zImage` needs a host `lz4` binary

The `zImage` target fails at the final compression step, and **only** there:

```
arch/arm/boot/compressed/Makefile:156: piggy_data   Error 127
```

**Error 127 is "command not found"** — not a compile error. `CONFIG_KERNEL_LZ4=y` (stock
parity, `docs/boot-chain.md` §8.6/P4) makes kbuild pipe `Image` through the `lz4` CLI, and
`lz4` is not installed on this host (`command -v lz4` → nothing; installing it needs root,
which this environment does not have). Everything *upstream* of that step — the entire kernel,
the decompressor stub, the ARM boot wrapper — compiled and linked, which is exactly why
`vmlinux` and `Image` exist above.

**This does not affect the real build path, and that was verified rather than assumed:**

> `work/buildroot/linux/linux.mk:99-100`
> ```make
> ifeq ($(BR2_LINUX_KERNEL_LZ4),y)
> LINUX_DEPENDENCIES += host-lz4
> ```

Buildroot **builds and supplies `host-lz4`** whenever the kernel is LZ4-compressed. The
missing tool is an artifact of invoking the kernel's Makefile standalone (which this task was
required to do — the top-level `make` belongs to P1.2), not a defect in the config.

**Honest statement of what is and is not proven:** the config compiles, links, and produces a
kernel image, a correct DTB, and 41 clean modules. The LZ4 *compression* of that image is the
single step not exercised here. It is a host-tool invocation with no dependency on any symbol
in this config, and P1.11 will exercise it on every build.

### Size signal for P1.11

The uncompressed `Image` is **17,826,268 B**. For reference, stock's *compressed* 5.15 zImage
is 7,360,840 B (`docs/boot-chain.md` §7.2). Our compressed `zImage` size **cannot be stated
until `lz4` runs** and is deliberately not guessed here — but the budget is 16 MiB
(`docs/boot-chain.md` §7.3), the initramfs (P1.10) still has to go *inside* it, and this
kernel is a 6.18 with more enabled than stock. **P1.11's `scripts/check-zimage-dtb.sh`
assertion is not a formality — run it and record the real number.** If it comes in tight, §9
lists the size-trim candidates.
