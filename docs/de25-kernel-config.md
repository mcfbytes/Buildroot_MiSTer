# DE25-Nano kernel configuration — the diet, and the shared MiSTer driver set

**Status:** implemented 2026-09-02 on `feature/de25-wave2`. Supersedes the
`board/mister/de25nano/linux.fragment` era (wave 1, commit `6dd5604`), whose
load-bearing comments were folded into this document when that file was deleted.

**Files this document describes**

| File | Layer | What it is |
|---|---|---|
| [`board/mister/de25nano/linux.config`](../board/mister/de25nano/linux.config) | kernel `CONFIG_*` | the DE25's **base**: arm64 + Agilex 5 + boot path + FPGA stack + the "not a distro kernel" exclusions. A **minimal defconfig**, DE10 style. |
| [`board/mister/common/linux-mister.fragment`](../board/mister/common/linux-mister.fragment) | kernel `CONFIG_*` | the **arch-neutral MiSTer personality**, shared: input/HID, Bluetooth, Wi-Fi, USB, sound, filesystems, netfilter, LEDs, RTC. |
| [`configs/mister_de25nano_defconfig`](../configs/mister_de25nano_defconfig) | Buildroot `BR2_*` | names both of the above (§7). |
| [`scripts/check-kernel-fragment-noop.sh`](../scripts/check-kernel-fragment-noop.sh) | check | proves the fragment changes nothing on the DE10 (§6). |

---

## 1. The problem this closes

Wave 1 built the DE25 kernel as **arm64's in-tree `defconfig` plus a 38-symbol
delta fragment**. That was the right call for a bring-up board — arm64
`defconfig` is the configuration mainline actually CI-tests, so every symbol not
named tracked upstream for free — and it produced a green build.

It also produced a **generic distro kernel**, and — much more seriously — a
kernel that was **not a MiSTer kernel at all**. Nearly all of its 1,481 modules
were hardware the DE25 does not have and never will: ~50 unrelated arm64 SoC
families, PCI, ACPI, DRM/GPU, KVM, enterprise NICs, media capture. Meanwhile,
read out of that build's own resolved config
(`output-de25/build/linux-7.2.2/.config`):

```
# CONFIG_HIDRAW is not set          # CONFIG_INPUT_JOYDEV is not set
# CONFIG_UHID is not set            # CONFIG_INPUT_UINPUT is not set
# CONFIG_HID_NINTENDO is not set    # CONFIG_JOYSTICK_XPAD  (absent -> n)
# CONFIG_HID_PLAYSTATION is not set # CONFIG_HID_GUNCON2/3, HID_FTEC,
# CONFIG_LEDS_USER is not set       #   HID_GAMECUBE_ADAPTER: not set
# CONFIG_NLS_KOI8_R is not set      # CONFIG_MODULE_COMPRESS_XZ (absent -> n)
# CONFIG_AFFS_FS is not set         # CONFIG_ATARI_PARTITION (absent -> n)
# CONFIG_USBIP_CORE is not set      # CONFIG_HZ_1000 is not set  (250 Hz)
CONFIG_SECCOMP=y
```

That kernel could not have driven a single MiSTer controller: no `hidraw`, no
`joydev`, no `uinput`, no `hid-nintendo`, no `hid-playstation`, no `xpad`. Five
of the six patch-gated pad drivers were compiled into the tree by the carried
patches and then left switched off (only `HID_VADER4` happened to default on).
`CONFIG_SECCOMP=y` was not itself a fault — it is simply a divergence from the
DE10, and the fragment now brings the DE25 to the DE10's posture, which carries
a defconfig obligation described in §3.1. **None of this is visible in a green
build**, which is exactly why it survived wave 1.

The owner's framing: *"most module settings etc. should be the same for driver
support between the two kernels."* This is that, implemented and measured.

| | wave 1 (arm64 `defconfig` + delta fragment) | **wave 2 (this change)** | DE10-Nano, for reference |
|---|---|---|---|
| modules (`=m` symbols) | 1,481 | **92** | 92 |
| installed `.ko.xz` | 1,640 files, **90 MB** | **91 files, 2.44 MiB** | 91 files, 2.23 MiB |
| kernel image | `Image` 41.9 MB | **`Image` 20.7 MB** | `zImage` 9.0 MB (lz4) |

The module **name sets are now identical**: `comm` over the two boards'
installed `/lib/modules` trees gives 91 in common and **zero** on either side
alone.

## 2. The split, and the one rule that defines it

```
   board/mister/de25nano/linux.config          board/mister/de10nano/linux.config
   ┌──────────────────────────────┐            ┌──────────────────────────────┐
   │ arm64, Agilex 5 IP, boot     │            │ arm, Cyclone V IP, boot path,│
   │ path, FPGA/SDM stack,        │            │ MiSTer_fb + MiSTer audio,    │
   │ distro-cruft exclusions      │            │ Cyclone V FPGA mgr/bridges,  │
   │      (51 setting lines)      │            │ AND all of the shared set    │
   └──────────────┬───────────────┘            │ inline (475 setting lines)   │
                  │ merge_config -m            └──────────────┬───────────────┘
                  ▼                                           ┆ does NOT consume
   ┌────────────────────────────────────────────────┐         ┆ the fragment yet
   │ board/mister/common/linux-mister.fragment      │ ┄┄┄┄┄┄┄┄┘ (§6 is what
   │ input/HID · Bluetooth · Wi-Fi · USB · sound ·  │            makes adopting
   │ filesystems · netfilter · LEDs · RTC · block · │            it safe)
   │ modules · diagnostics      (409 setting lines) │
   └────────────────────────────────────────────────┘
```

404 of the fragment's 409 lines appear **verbatim** in the DE10's own file. The
other five are menu-gate sentinels — `USB`, `USB_HID`, `HID`, `INPUT`, `WLAN` —
which the DE10 gets from a Kconfig `default` or, in the USB case, from a
`select`; each was checked against the DE10's **resolved** config instead.
Base and fragment share **no** symbol: one home per symbol, 460 lines total,
zero duplication, so the Buildroot merge emits no warnings by construction.


**The rule.** A symbol belongs in the shared fragment if and only if:

1. it is **not** arch- or SoC-specific — anything naming an on-chip IP block
   (`8250_DW`, `I2C_DESIGNWARE_*`, `GPIO_DWAPB`, `DW_WATCHDOG`,
   `MMC_SDHCI_CADENCE`, `PL330`, the FPGA manager, the SoC clk/reset drivers)
   stays in the board's own file even when both boards happen to have the same
   IP; **and**
2. the **DE10's resolved `.config` has exactly that value**; **and**
3. the symbol **exists in both kernel trees** (DE10 is on 6.18.y, DE25 on 7.2.y).

Rule 2 is what makes the fragment a provable no-op on the DE10 (§6). Rule 3 is
what stops a version-skewed line from being a silent no-op on one board — see §9.

### Why "resolved `.config`", not "the DE10's defconfig"

Both, as it happens. All **475** setting lines in
`board/mister/de10nano/linux.config` were first verified to resolve to *exactly*
their stated value in `output/build/linux-6.18.48/.config` — they do, with zero
divergence — so any subset of that file is a no-op by construction. Symbols
added to the fragment that the DE10 defconfig does **not** name (§3.10's `USB`,
`HID`, `USB_HID`, `INPUT`, `WLAN` sentinels) were checked against the resolved
config directly.

---

## 3. The shared fragment, subsystem by subsystem

409 setting lines. Section numbers below match the section banners in the file.

### 3.1 Core kernel personality (§1 of the file)
`SYSVIPC`, `HIGH_RES_TIMERS`, the `TASK*`/`TASKSTATS`/`PROFILING`/`RELAY`
accounting set, `IKCONFIG` + `IKCONFIG_PROC`, `LOG_BUF_SHIFT=14`, `CGROUPS` +
`CPUSETS` + `NAMESPACES`, `BLK_DEV_INITRD`, `SYSFS_SYSCALL`, `EXPERT`.

* `IKCONFIG_PROC` gives `/proc/config.gz`, the only way to answer "what is
  actually in the kernel on this board" from the board itself — this project
  leans on it repeatedly.
* `HZ_1000` is a **MiSTer latency posture, not a default**: the generic
  `kernel/Kconfig.hz` choice defaults to `HZ_250`, so this is a real change on
  any base.
* `# CONFIG_SUSPEND is not set` — `SUSPEND` is `default y` wherever
  `ARCH_SUSPEND_POSSIBLE`, so the explicit off is required, not decorative.
* **`# CONFIG_SECCOMP is not set` is load-bearing, and it reaches into the
  Buildroot defconfig.** It is `default y` on arm64 (wave 1 had `SECCOMP=y`) and
  matches stock on the DE10. The coupling: `BR2_PACKAGE_OPENSSH_SANDBOX` is
  `default y` in Buildroot, and since openssh 10.4 a failed
  `prctl(PR_SET_SECCOMP)` is `fatal()` rather than `debug()` — so an image with
  SECCOMP off and the sandbox on gets an `sshd` that **binds and listens while
  killing every connection preauth**, password and key alike. The DE10 fixes
  that with `# BR2_PACKAGE_OPENSSH_SANDBOX is not set` in its own defconfig
  (commit `9824cd6`; the rationale is in that file at
  `configs/mister_de10nano_defconfig:806-828`).

  **Action for the DE25 defconfig:** it ships no `openssh` today (the DE25 is a
  bare BusyBox developer OS, ADR 0027), so nothing is broken now — but the day
  `BR2_PACKAGE_OPENSSH=y` is added there, `# BR2_PACKAGE_OPENSSH_SANDBOX is not
  set` must be added with it. It is a configure-time flag, so changing it later
  also needs `make openssh-dirclean` or the stale stamp ships the broken sshd.

### 3.2 Modules and the `.ko.xz` layout (§2)
`MODULES`, `MODULE_UNLOAD`, `MODULE_COMPRESS`, `MODULE_COMPRESS_XZ`.
The on-disk module layout is an **ABI contract**
([`abi-contract.md`](abi-contract.md)), not a size tweak;
[`kernel-config-deltas.md`](kernel-config-deltas.md) §3.1 records
`MODULE_COMPRESS_XZ` as one of three symbols `olddefconfig` silently dropped
once already.

### 3.3 Block layer, partitions, loop (§3)
`PARTITION_ADVANCED` + `ATARI_PARTITION` (MiSTer mounts Atari/Amiga-era disk
images), `BINFMT_MISC`, `BLK_DEV_LOOP` (how `.img`/`.vhd` media are mounted),
`BLK_DEV_RAM` at the DE10's 2 × 8 MiB geometry, `# CONFIG_IOSCHED_BFQ is not set`.

### 3.4 `/dev` and hotplug (§4)
`DEVTMPFS` + `DEVTMPFS_MOUNT` + `UEVENT_HELPER`/`UEVENT_HELPER_PATH`.

**These live in the fragment, not in the board base, and that is deliberate.**
They are arch-neutral and both boards need exactly this value, and the project's
standing rule is *one home per symbol* — duplicating a line into both files
creates two places to change it and one place to forget. The consequence is
stated at the top of the board file: **`linux.config` alone does not boot.** The
two files are a pair and the Buildroot defconfig always names both.

### 3.5 Networking core and netfilter (§5)
The DE10's exact set: `NET`/`PACKET`/`UNIX`/`INET`, `NET_KEY`(+`_MIGRATE`),
`IP_MULTICAST`, `IP_PNP{,_DHCP,_BOOTP,_RARP}`, `# CONFIG_IPV6 is not set`,
`NETWORK_PHY_TIMESTAMPING`, `VLAN_8021Q`(+`_GVRP`), and the legacy-iptables
netfilter block (conntrack + FTP/IRC/SIP helpers + the `xt_*` matches/targets +
`IP_NF_FILTER` + `IP_NF_TARGET_REJECT`).
`IP_NF_FILTER`/`IP_NF_TARGET_REJECT` are called out in the file because
[`kernel-config-deltas.md`](kernel-config-deltas.md) §3.3 records `olddefconfig`
silently dropping them and taking the whole legacy filter table with them.

### 3.6 Bluetooth (§6)
`BT`, `BT_RFCOMM`(+`_TTY`), **`BT_HIDP`** — the symbol that turns a paired
DS4/DualSense/Pro Controller into an input device — `BT_HCIBTUSB=m` with
`BT_HCIBTUSB_MTK=y`, `BT_HCIBCM203X=y`, `BT_ATH3K=m`.
`linux-patches/0036` (CSR clone LMP subver) rides on btusb and is carried by
both boards. See [`bluetooth-parity.md`](bluetooth-parity.md).

### 3.7 Wireless stack and the dongle set (§7, §9)
`CFG80211=m` / `MAC80211=m` (a Wi-Fi dongle is optional hardware; the stack is
~1 MiB resident when loaded), `CFG80211_WEXT` for the older tooling MiSTer
scripts use, and then **every driver the DE10 ships, chip for chip**: ath9k_htc /
carl9170 / ath6kl, brcmfmac, libertas + mwifiex, the whole mt76 USB family
(7601U, 76x0U, 76x2U, 7663U, 7921U, 7925U), rt2x00, rtlwifi + rtl8xxxu, and the
complete mainline **rtw88** (8822BU, 8821CU, 8822CU, 8814AU, 8723DU, 8821AU,
8812AU) and **rtw89** (8851BU, 8852BU) USB sets. ADR 0016 "mainline-first"; the
per-chip coverage table is [`wifi-parity.md`](wifi-parity.md) §6.

Two structural facts make this set safe to share:

* **Every `*_SDIO` bus driver is explicitly off.** `BRCMFMAC_SDIO` and
  `RSI_SDIO` are `default m` whenever `CONFIG_MMC=y` — which is true on both
  boards, for the SD card — so without the explicit off, `olddefconfig` builds
  SDIO Wi-Fi drivers for a slot neither board has. The DE10's own file learned
  this the hard way ("Verified: without this line it resolved to `=m`").
* **Every `*_PCIE`/`*E` sibling is unreachable** because neither board sets
  `CONFIG_PCI` — that exclusion lives in each board's base file.

`EEPROM_93CX6` is named explicitly: it is a `select`ed dependency of rt2x00 and
rtl8187 that is otherwise invisible, so its disappearance would be silent.

### 3.8 Network devices (§8)
`NETDEVICES`, `MACVLAN=y` and `TUN=y` (container/Docker networking, and the only
way to give an emulated NIC its own MAC over wireless — `=y` not `=m` because
the module directory does not match `uname -r`, so autoload is unreliable),
`MARVELL_PHY` + `MICREL_PHY`, the PPP set, `# CONFIG_USB_NET_DRIVERS is not set`,
and the 32 `# CONFIG_NET_VENDOR_* is not set` gates. Those gates are
`bool ... default y`: leaving them absent turns dozens of drivers back on.

The **PHY drivers are shared, the MAC is not**: which PHY part is fitted is a
DTS/MDIO-ID question and both boards carry both drivers, while `STMMAC_ETH` +
`STMMAC_PLATFORM` + the SoC glue (`DWMAC_SOCFPGA`) are board-file symbols.

### 3.9 Input (§10)
`INPUT`, `INPUT_MOUSEDEV`, **`INPUT_JOYDEV`**, **`INPUT_EVDEV`**,
**`INPUT_UINPUT`** — the three device classes `MiSTer_Main` and every
controller-mapping tool open, plus the node the pairing/remap helpers write
through. `MOUSE_PS2` and `KEYBOARD_ATKBD` are off (no PS/2 controller on either
board; Keyrah adapters arrive over USB HID). The classic serial/USB joystick set
(`iforce`, `warrior`, `magellan`, `spaceorb`, `spaceball`, `stinger`, `twidjoy`,
`zhenhua`) and `JOYSTICK_XPAD=m` with FF + LEDs.
`linux-patches/0026` (mousedev `EVIOCGRAB`) and `0025` (usbhid jspoll) ride here.

### 3.10 HID (§11) — every `hid-*` the DE10 enables
All 60-odd `HID_*` drivers verbatim, plus `HIDRAW`, `UHID`,
`HID_BATTERY_STRENGTH`, `HID_PID`, `USB_HIDDEV`, and the force-feedback
sub-options.

**Sentinels.** `HID` and `USB_HID` are `default y` but are the single point of
failure for the entire controller story, so they are named — an upstream
demotion then shows up as a merge warning rather than as a board with no pads.

**Six patch-gated symbols**: `HID_GUNCON2` (0010), `HID_GUNCON3` (0011),
`HID_FTEC` (0012), `HID_VADER4` (0013), `HID_GAMECUBE_ADAPTER` +
`_FF` (0014). These do not exist in a stock tree. Both boards carry 0010–0014
(the DE25's entries are symlinks into the DE10's series,
`board/mister/de25nano/linux-patches/README.md`). **If either board ever drops
one of those patches, the corresponding line here becomes a silent no-op on that
board** — `olddefconfig` discards unknown symbols without a word.

The *behavioural* HID patches both boards carry (0016–0019, 0022–0024,
0032–0035, 0037–0042) add no Kconfig symbols and need no lines of their own —
they change what an already-enabled driver does.

### 3.11 USB host (§12)
`USB` itself, `USB_ACM`, `USB_STORAGE`, `USB_UAS`, the `USBIP` trio (the debug
rig forwards a controller from a host PC — [`debug-tooling.md`](debug-tooling.md)),
the USB-serial adapters (CH341/CP210x/FTDI/PL2303 + generic + simple),
`USB_ANNOUNCE_NEW_DEVICES`, `USB_DYNAMIC_MINORS`, and the PHY shims
`USB_ULPI_BUS` / `USB_ULPI` / **`NOP_USB_XCEIV`**.

**`CONFIG_USB` has no `default` in Kconfig at all.** On the DE10 it is currently
switched on only as a side effect of `select USB` inside `MOUSE_APPLETOUCH` /
`MOUSE_BCM5974` / `MOUSE_SYNAPTICS_USB` — far too fragile to leave implicit for
the bus every MiSTer peripheral arrives on. `NOP_USB_XCEIV` is required by
*both* boards' DTs (`usb-nop-xceiv`).

The **host controller driver** is board-specific and is not here: `USB_DWC2` on
both boards today, but that is an SoC fact, not a shared one.

### 3.12 SCSI / USB mass storage (§13)
`SCSI` + `BLK_DEV_SD` + `BLK_DEV_SR` as the transport USB storage rides on, with
`# CONFIG_SCSI_LOWLEVEL is not set` keeping every actual HBA driver out.

### 3.13 Sound (§14)
`SOUND`, `SND`, `SND_OSSEMUL`, `SND_HRTIMER`, `SND_SEQUENCER`(+`_OSS`),
`SND_DUMMY`, **`SND_USB_AUDIO`**. USB DACs and headsets are the arch-neutral
half of MiSTer's audio story; the DE10's own codec path (`SND_MISTER_AUDIO`,
from `linux-patches/0002`) is patch-gated and board-specific — see §5.

### 3.14 I2C, GPIO, LEDs, RTC, regulators, watchdog core, hwrng (§15)
Cores and userland ABIs only: `I2C` + `I2C_CHARDEV` + `I2C_SMBUS` + `I2C_GPIO`
(with `# CONFIG_I2C_HELPER_AUTO is not set`), `GPIOLIB` + `GPIO_SYSFS`,
`WATCHDOG`, `REGULATOR` + `REGULATOR_FIXED_VOLTAGE`, `HW_RANDOM`, the LED class
set (`LEDS_CLASS_MULTICOLOR` is what hid-playstation and hid-nintendo register
player/lightbar LEDs through — patches 0032/0033/0041/0042;
`LEDS_BRIGHTNESS_HW_CHANGED` is what 0029 teaches leds-gpio to report;
`LEDS_USER` is `/dev/uleds`), and the three I2C RTC parts MiSTer add-on boards
fit ([`rtc-parity.md`](rtc-parity.md)).

### 3.15 Filesystems (§16)
`EXT4_FS`, `VFAT_FS` + `FAT_DEFAULT_UTF8`, **`EXFAT_FS`** (ADR 0010 dropped the
out-of-tree driver; `linux-patches/0031` adds the Samsung-symlink behaviour on
both boards), `NTFS3_FS=m`, `FUSE_FS` + `CUSE`, `FSCACHE`, `ISO9660`/`JOLIET`/
`ZISOFS`/`UDF` for CD images, `AFFS_FS` for Amiga media, `TMPFS`, `CONFIGFS_FS`,
`# CONFIG_DNOTIFY is not set`, the NFS client (ADR 0022) and CIFS/SMB
([`netfs-parity.md`](netfs-parity.md), [`samba-parity.md`](samba-parity.md)),
and the full NLS codepage set.

`NLS_UTF8` is **not optional** with exfat: its default `iocharset` is `utf8`, and
a missing codepage fails the **mount at runtime**, not the build.

`ext4`/`vfat`/`exfat` are boot-path filesystems and are `=y` — see §3.4 for why
they live in the fragment rather than the board base.

### 3.16 Keys and crypto (§17)
`ENCRYPTED_KEYS`, `INIT_STACK_NONE`, and the generic-C algorithms CIFS / NFS /
PPP-MPPE need (`NULL`, `DES`, `CTS`, `XTS`, `SEQIV`, `ECHAINIV`, `MD4`, `MD5`,
`SHA1`, `CRC32C`). **No arch accelerators**: those are per-arch symbol names
(`CRYPTO_AES_ARM` vs `CRYPTO_AES_ARM64_*`) and belong in a board file if wanted.

### 3.17 Diagnostics (§18)
`PRINTK_TIME`, `DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT`, `MAGIC_SYSRQ`, `DEBUG_FS`,
`FUNCTION_TRACER`, and the P3.13 crash/hang triage set: `PANIC_ON_OOPS` +
`SOFTLOCKUP_DETECTOR` + `WQ_WATCHDOG` + `DETECT_HUNG_TASK`. On a board with a
serial console and no display, a kernel that limps after an oops is strictly
worse than one that panics loudly.

---

## 4. The DE25 base — what is on, and why

Section numbers match the banners in `board/mister/de25nano/linux.config`.
51 setting lines.

| § | Group | Notes |
|---|---|---|
| 1 | identity | `LOCALVERSION_AUTO` off (the version string must not depend on a git tree being present — [`reproducibility.md`](reproducibility.md)); `DEFAULT_HOSTNAME="de25"`. |
| 2 | platform / topology | `ARCH_INTEL_SOCFPGA`; `NR_CPUS=4` (2×A76 + 2×A55 — arm64 defaults to **512**); `HOTPLUG_CPU`. |
| 3 | **exclusions** | see §5 below. |
| 4 | SoC clocks | `CLK_INTEL_SOCFPGA` + `CLK_INTEL_SOCFPGA64`. **There is no `CONFIG_CLK_AGILEX5`** — `clk-agilex5.o` is built by the SOCFPGA64 symbol (`drivers/clk/socfpga/Makefile:5-7`), and the driver only exists from v6.19, which is why this board is pinned to 7.2 and not 6.18 ([`de25-implementation-path.md`](de25-implementation-path.md) §5.1). |
| 5 | reset | `RESET_SIMPLE`. The board DTS gives `mmc0` `resets = <&rst SDMMC_RESET>` and the rstmgr is `altr,stratix10-rst-mgr`, matched by `drivers/reset/reset-simple.c:137` — **not** `reset-socfpga.c`, which is `default ARM && ARCH_INTEL_SOCFPGA`, i.e. the DE10's 32-bit path. With no reset provider `mmc0` probe-defers forever with nothing in dmesg naming the reason. |
| 6 | sysmgr, SRAM | `MFD_ALTERA_SYSMGR` — dwmac-socfpga reads the PHY interface mode through `altr,sysmgr-syscon`, so gmac0 does not come up without it. `SRAM` for `ocram@0` (`mmio-sram`). |
| 7 | console | the 8250/8250_DW group on **uart1** (uart0 is the SoCDK's). `=y`, never `=m`: a console that is a module does not exist at panic time. |
| 8 | SD boot | `MMC` → `MMC_SDHCI` → `MMC_SDHCI_PLTFM` → `MMC_SDHCI_CADENCE`, all `=y` because there is **no initramfs** on this board, so a driver that is a module cannot be loaded before the root filesystem it is needed to reach exists. |
| 9 | IOMMU | `ARM_SMMU_V3=y` kept even though the board DTS ships `&smmu { status = "disabled"; }` — so the SMMU-on leg of the §2.6 fabric test is a one-line DTS change with **no kernel rebuild** ([`de25-dts-rationale.md`](de25-dts-rationale.md) §4). |
| 10 | Ethernet MAC | `STMMAC_ETH` + `STMMAC_PLATFORM` + `DWMAC_SOCFPGA`, all `=y`. `DWMAC_SOCFPGA` is `default ARCH_INTEL_SOCFPGA` but tristate, so it would follow `STMMAC_ETH` to `=m` without these lines. |
| 11 | FPGA stack | `FPGA` + `FPGA_BRIDGE` + `FPGA_REGION` + `OF_FPGA_REGION` + `FPGA_MGR_STRATIX10_SOC` + `INTEL_STRATIX10_SERVICE` + `FW_LOADER` + **`OF_OVERLAY`**; `INTEL_STRATIX10_RSU` off. See §4.1 below. |
| 12 | low-speed IP | `GPIO_DWAPB`, `I2C_DESIGNWARE_CORE`/`_PLATFORM`, `DW_WATCHDOG`, and the SPI group (`SPI`, `SPI_DESIGNWARE`, `SPI_DW_MMIO`, `SPI_SPIDEV`, `SPI_MEM` off). |
| 13 | USB controller | `USB_DWC2` + `USB_DWC2_HOST`. Verified against the dtsi, not assumed: `usb0@10b00000` is `compatible = "snps,dwc2"` with a `usb-nop-xceiv` phy (`socfpga_agilex5.dtsi:161-163,483-492`) — **dwc2, not dwc3, not xhci**. |

### 4.1 The two traps in the FPGA group, restated

**`OF_OVERLAY` is the single most important line in the base file.**
`OF_FPGA_REGION` is `depends on OF && FPGA_REGION` with **no `select
OF_OVERLAY`**, and with `OF_OVERLAY=n`, `of_overlay_notifier_register()` is a
static-inline stub returning 0. The region driver therefore *registers
successfully at boot, prints nothing wrong, and its notifier can never fire*. A
kernel missing that line is silently non-functional for core loading: no error,
no warning, no reconfiguration ([`de25-fpga-reconfig.md`](de25-fpga-reconfig.md)
§4.1, tagged **[V]** there).

**`INTEL_STRATIX10_RSU` is off as a posture choice, not an oversight.** It drives
SDM commands that rewrite the QSPI boot firmware. `de25-boot-chain.md`'s
posture-1 contract is that the factory QSPI image is never written by anything we
ship — the QSPI seam is permanent on this board and an interrupted write is a
brick with no recovery path. Not shipping the driver is strictly stronger than
relying on there being no `intel,stratix10-rsu` DT node.

`FPGA_BRIDGE=y` is required even though **no bridge driver is used** — the
Cyclone V `fpga_bridge0..3` shape has no Agilex analogue and must not be
transliterated — purely because `FPGA_REGION depends on FPGA_BRIDGE`.
`FPGA_MGR_SOCFPGA` and `SOCFPGA_FPGA_BRIDGE` are **Cyclone V / Arria 10 only**
and must never appear in this file.

---

## 5. What is deliberately OFF, and why

### 5.1 In the DE25 base — the five exclusions that do the diet

The other ~50 arm64 SoC families (`ARCH_ROCKCHIP`, `ARCH_QCOM`, `ARCH_MEDIATEK`,
…) need **no lines at all**: they are `default n`, and it was arm64's in-tree
`defconfig` — not Kconfig — that switched them on. Writing a minimal defconfig
removes them by construction. The five below are different: each is `default y`
or reachable by default, so each needs saying.

| Off | Why |
|---|---|
| `EFI` | the DE25 boots via the factory SPL → `u-boot.itb` FIT contract; there is no UEFI in that chain. **This also forecloses ACPI**: on arm64 `ARCH_SUPPORTS_ACPI` is `select`ed only by `EFI` (`arch/arm64/Kconfig:2473`), so with `EFI=n` the entire ACPI menu is structurally unreachable and needs no line of its own. |
| `PCI` | no host bridge is wired and none is in the DTS. Load-bearing for the shared Wi-Fi set: it is what makes every `RTW88_*E` / `BRCMFMAC_PCIE` / ath10k-PCIe sibling unreachable. |
| `VIRTUALIZATION` | `default y` on arm64; nothing here runs guests. |
| `COMPAT` | 32-bit EL0. Buildroot builds one ABI and it is aarch64. |
| `DRM` + `FB` + `MEDIA_SUPPORT` | no display path exists on the DE25 in wave 1, and DRM alone is ~40 MB of modules. |

### 5.2 DE10 symbols deliberately **not** put in the shared fragment

Every one of these is a judgement call, and each is listed here so the next
reader can overturn it with evidence rather than rediscover it.

| DE10 symbol(s) | Why not shared |
|---|---|
| `FB`, `FB_MISTER`, `FRAMEBUFFER_CONSOLE{,_DETECT_PRIMARY}` | `FB_MISTER` comes from `linux-patches/0001`, which the DE25 **does not carry** — it targets the Cyclone V fabric-memory aperture. Naming it would make a line that is a driver on one board and a silent no-op on the other. Until an Agilex 5 framebuffer path exists there is nothing for fbdev to drive. |
| `SND_MISTER_AUDIO` | same shape: `linux-patches/0002`, not carried on the DE25 (its exclusion is an open owner decision, tasks item 5). |
| `CMA`, `CMA_AREAS=7` | not driver support; on the DE10 it is stock-parity carry-over and nothing on the DE25 (no fbdev, no DRM, no V4L) allocates from it. `CMA_SIZE_MBYTES` would reserve DRAM for no consumer. **Revisit the moment a DE25 framebuffer lands.** |
| `CPU_FREQ` + its six governors, `CPU_IDLE`, `CPU_IDLE_GOV_MENU` | the DE10's cpufreq exists to host the Cyclone V overclock driver (`linux-patches/0003`); mainline 7.2 has **no cpufreq driver for Agilex 5** and the board DTS has no OPP table or idle-states, so the whole subsystem would be a userland-visible interface with nothing behind it. |
| `COREDUMP` | the DE10's own file marks this a **temporary** debug divergence from stock, to be reverted as one block ([`debug-tooling.md`](debug-tooling.md)). Carrying a temporary divergence into a shared file entrenches it. (It is `default y` in `fs/Kconfig.binfmt` anyway, so the DE25 gets it regardless.) |
| `FRAME_WARN=1024` | word-size dependent — 1024 is the 32-bit default and would emit `-Wframe-larger-than` noise on arm64, where the default is 2048. |
| `KERNEL_LZ4` | arm64 does not select `HAVE_KERNEL_LZ4`; there is no self-decompressing arm64 kernel. `Image` vs `Image.gz` is a separate open decision (tasks item 3). |
| `LOCALVERSION_AUTO`, `DEFAULT_HOSTNAME` | identity, per board. |
| `SMP`, `NR_CPUS`, `HOTPLUG_CPU` | topology, per board. |
| `SRAM` | binds an `mmio-sram` DT node; that is SoC description, so it sits in each board's own file. |
| `MMC` | boot path **and** SoC: the DE10's host is `MMC_DW`, the DE25's is `MMC_SDHCI_CADENCE`. Splitting the core away from the host would put half a boot path in each file. |
| `STMMAC_ETH`, `OF_OVERLAY`, `FPGA*`, `DMADEVICES`/`PL330_DMA`, `MFD_ALTERA_SYSMGR`, all `SERIAL_8250*`, `SPI*`, `I2C_DESIGNWARE_*`, `GPIO_DWAPB`, `DW_WATCHDOG` | on-chip IP or SoC glue; rule 1. (`OF_OVERLAY` is `=y` on both boards, so moving it to the fragment later would still be a no-op — it lives in the base because the trap that makes it load-bearing is an FPGA-stack fact.) |
| `ARM_THUMBEE`, `UACCESS_WITH_MEMCPY`, `ARM_MODULE_PLTS`, `VFP`, `NEON`, `ARM_CPUIDLE`, `ARM_SOCFPGA_CPUFREQ`, `CRYPTO_AES_ARM`, `UNWINDER_FRAME_POINTER`, `DEBUG_USER`, `SND_ARM` | ARM32-only symbols. `SND_ARM` is the subtle one: it still exists in 7.2 but is `depends on ARM`, so on arm64 the line is silently discarded. |
| `NET_VENDOR_CIRRUS`, `NET_VENDOR_FARADAY` | same trap — both are `depends on ARM`. Caught by the survival check in §8, not by inspection. |

### 5.3 Not enabled on the DE25 even though the SoC has the hardware

* **`DW_AXI_DMAC`** — `dmac0`/`dmac1` are `altr,agilex5-axi-dma`,`snps,axi-dma-1.01a`
  (`socfpga_agilex5.dtsi:334,353`). The only DT consumers of their `dmas`
  properties are `spi0`/`spi1`, both `status = "disabled"` in the base DTS, so
  the driver would build and bind with nothing to serve. Wave-1's build did not
  have it either. Enable it the day a fabric or SPI DMA consumer is enabled.
* **`I3C`** — `altr,agilex5-dw-i3c-master` nodes exist but the board DTS does not
  enable them.
* **`PINCTRL`** — Agilex 5 pinmux is done by the factory SPL; mainline has no
  Agilex 5 pinctrl driver and the DTS has no pin nodes.

---

## 6. The DE10 no-op proof

`scripts/check-kernel-fragment-noop.sh` is the claim of §2 rule 2, executed.

It deliberately runs kconfig **twice**, because resolving a config outside
Buildroot's environment cannot reproduce toolchain-derived string symbols
exactly (`CONFIG_CC_VERSION_TEXT` comes back empty — the compiler wrapper is
invoked through kconfig's `$(shell,…)`):

```
CONTROL : tree/.config                    -> olddefconfig -> control/.config
TEST    : tree/.config + fragment (merge) -> olddefconfig -> test/.config
```

Same kconfig binary, same `srctree`, same `ARCH`, same compiler — so every
environment-derived difference cancels and **control vs test is exact**. The
check fails on any `is redefined by fragment` line and on any diff.

Result, run against the live DE10 tree on 2026-09-02 (verbatim in the wave-2
report): `merge_config.sh` printed **zero** redefinition lines, and
`diff control/.config test/.config` was **empty**. Against the tree's own
`.config` the only difference is `CONFIG_CC_VERSION_TEXT`, which the control run
reproduces identically — hence the two-run design.

### 6.1 The merge_config prose trap

`merge_config.sh` resolves a symbol's "new value" with
`grep -w CONFIG_<SYM> <fragment>`, which matches **prose as well as settings**.
A comment in the fragment that names a symbol the fragment also sets therefore
produces a **false** `Value of CONFIG_<SYM> is redefined by fragment` warning on
every single build. This happened once during authoring (a sentinel comment for
the USB symbol) and is now rule 5 in the fragment's header: **name symbols in
comments without the `CONFIG_` prefix.** The check script enforces it.

---

## 7. Buildroot wiring

```
# BR2_LINUX_KERNEL_USE_ARCH_DEFAULT_CONFIG is not set
BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(BR2_EXTERNAL_MISTER_PATH)/board/mister/de25nano/linux.config"
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL_MISTER_PATH)/board/mister/common/linux-mister.fragment"
```

Note the symbol name: `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`, **not**
`BR2_LINUX_KERNEL_USE_DEFCONFIG` (that one names an in-tree defconfig and takes
a bare name in `BR2_LINUX_KERNEL_DEFCONFIG`, `linux/linux.mk:360-361`).

### 7.1 Firmware — enabled drivers with no blobs

The DE25 defconfig currently selects **no** `BR2_PACKAGE_LINUX_FIRMWARE_*` at
all, while the shared fragment now builds the whole DE10 Wi-Fi/Bluetooth driver
set. Those drivers will bind and then fail at `request_firmware()`. That is not
a regression — wave 1 had exactly the same drivers as `=m` from arm64
`defconfig`, also without firmware — but it is now a *deliberate* set, so the
decision should be explicit. The DE10's 29 firmware
selections (`configs/mister_de10nano_defconfig:1221-1366`, **52 MB** installed
at `/lib/firmware`) are the menu to copy from; see
[`firmware-parity.md`](firmware-parity.md) and [`wifi-parity.md`](wifi-parity.md).
This is an **owner decision**, not a config fact: the initial DE25 scope is a
bare developer OS (ADR 0027), and the firmware set is tens of MB of rootfs.

---

## 8. Verification — what was actually measured

Method (reproducible; the survival check is the important half):

```sh
# 1. Resolve the pair in a pristine, patched 7.2.2 tree.
tar xf dl/linux/linux-7.2.2.tar.xz
cd linux-7.2.2
for p in board/mister/de25nano/linux-patches/*.patch; do patch -p1 -F0 -i "$p"; done
cp board/mister/de25nano/linux.config .config
ARCH=arm64 scripts/kconfig/merge_config.sh -m -O . .config \
        board/mister/common/linux-mister.fragment
make ARCH=arm64 olddefconfig

# 2. THE SURVIVAL CHECK. merge_config only WARNS when a symbol is dropped and
#    olddefconfig discards unknown or unsatisfiable symbols in SILENCE, so a
#    typo in either file is a no-op, never an error. Every asked-for line must
#    appear verbatim in the resolved .config.
cat board/mister/de25nano/linux.config board/mister/common/linux-mister.fragment |
  grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set)' |
  while read -r l; do grep -qxF "$l" .config || echo "DROPPED: $l"; done
```

**Result 2026-09-02: 460 asked-for symbols (51 base + 409 fragment), zero
dropped** — verified twice, once in the pristine scratch tree above and once
against the real Buildroot build's resolved config
(`output-de25k/build/linux-7.2.2/.config`, after Buildroot's own
`LINUX_KCONFIG_FIXUP_CMDS` step). The two resolutions differ by 35 lines, every
one of them a toolchain-identity symbol (`CC_VERSION_TEXT`, `GCC_VERSION`,
`AS_VERSION`, `LD_VERSION`, `CC_HAS_*`) — the scratch run used the host gcc.

`merge_config.sh` printed **zero** warnings inside the Buildroot build too:
base and fragment share no symbol (§2), so there is nothing to redefine.

Four candidates were removed during authoring because they did *not* survive,
and each removal is a finding:

| Removed | Reason |
|---|---|
| `# CONFIG_ACPI is not set` | unreachable once `EFI=n`; documented in §5.1 instead. |
| `# CONFIG_SERIAL_8250_DEPRECATED_OPTIONS is not set` | the symbol was **removed upstream** between 6.18 and 7.2. |
| `# CONFIG_NET_VENDOR_CIRRUS is not set` | `depends on ARM`. |
| `# CONFIG_NET_VENDOR_FARADAY is not set` | `depends on ARM`. |

## 9. Version skew — the two symbols the fragment must not name

The DE10 is on 6.18.y and the DE25 on 7.2.y, and the fragment must be valid in
both. Two symbols in the DE10's defconfig are 6.18-only and are therefore
**absent from the fragment**, though the DE10's own file keeps them (which is
still a no-op — the fragment simply does not mention them):

* **`CONFIG_NFS_V4_1`** — removed as a separate symbol after 6.18; NFSv4.1 is
  unconditional in 7.x, where `fs/nfs/Kconfig` offers only `NFS_V4_0` and
  `NFS_V4_2`. The fragment sets `NFS_V4` and `NFS_V4_2`, which is the same
  capability on both trees.
* **`CONFIG_NF_CT_PROTO_UDPLITE`** — the UDP-Lite conntrack protocol was removed
  from `net/netfilter/Kconfig` after 6.18. It was `is not set` on the DE10 anyway.

## 10. Per-kernel-bump re-check list

Run **all** of these on any kernel version bump on either board. Each catches a
failure mode that is otherwise silent.

1. **The survival check (§8 step 2)** on the bumped board. This is the one that
   catches a symbol renamed, removed, or newly gated behind an unmet dependency.
   Zero `DROPPED:` lines, or an explanation per line in §9.
2. **`scripts/check-kernel-fragment-noop.sh`** after the DE10 kernel build.
   A DE10 bump can change a symbol's resolved value (a `default` flip upstream)
   and silently break the shared-driver-set claim.
3. **Re-read `docs/de25-patch-portability.md`'s six patch-gated HID symbols**
   (§3.10). If a patch stops applying and is dropped, its symbol becomes a
   silent no-op on that board.
4. **`grep -c '=m' <tree>/.config`** and the installed `/lib/modules` size.
   A large jump means an upstream `default` flipped somewhere the minimal
   defconfig does not name — the exact failure the wave-1 config had wholesale.
5. **Check the five §5.1 exclusions are still `not set`** in the resolved config.
   `EFI` in particular gates ACPI transitively; if upstream ever changes what
   selects `ARCH_SUPPORTS_ACPI`, the ACPI menu comes back with no warning.
6. **Confirm `RESET_SIMPLE` is still `y`.** Its `default` clause names
   `(ARCH_INTEL_SOCFPGA && ARM64)` explicitly; an upstream refactor of that line
   turns `mmc0` into a permanent probe-defer with no diagnostic.
7. **Confirm the sentinels resolved to the value asked for**, not merely that
   they are present: `OF_OVERLAY`, `USB`, `HID`, `USB_HID`, `INPUT`, `WLAN`,
   `SECCOMP` (off), `MODULE_COMPRESS_XZ`.

## 11. CI wiring

`check-kernel-fragment-noop.sh` **needs a configured, built kernel tree** (it
uses that tree's own `scripts/kconfig/conf` and `merge_config.sh`). It therefore
does **not** belong in the lint job, which runs on a bare checkout.

* **Where:** the DE10 image build job, as a step *after* the kernel is built and
  *before* (or alongside) the artifact upload. `output/build/linux-[0-9]*/` is
  then guaranteed to exist and to be unique, so the script needs no arguments.
* **Cost:** two `conf --olddefconfig` runs plus a `diff` — **a few seconds**, no
  compilation, no download, no cache impact. Actions-minute cost is effectively
  zero next to the build it rides on (memory: CI minutes are watched).
* **Not on a fresh runner alone.** On a *developer* machine with several kernel
  trees under `output/build/` the script fails closed by design (the Makefile
  `rt` recipe's "never the first glob match" rule) and needs `--tree`. In CI
  there is exactly one tree.
* **Optional second call** for the RT variant: `--tree output-rt/build/linux-*`,
  same argument shape. The fragment is not consumed there today, so this is only
  worth adding if the RT kernel ever adopts it.
