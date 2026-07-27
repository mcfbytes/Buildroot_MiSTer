# WiFi userland parity (P3.4)

> Scope: `wpa_supplicant` (+`_NL80211`, +`_WEXT`) was already enabled by
> P2.1, and `/etc/network/interfaces` / `/etc/dhcpcd.conf` were already
> authored byte-identical to stock by P2.3 (rootfs overlay). The kernel WiFi
> drivers (P3.1 Realtek out-of-tree + in-tree) and firmware (P3.3) are done.
> This task audits the full userland chain against stock and against the
> actual `wifi.sh` script, and closes one real gap it found: three binaries
> `wifi.sh` execs (`bash`, `dialog`, wireless-tools' `iwlist`/`iwgetid`) plus
> the real `ip` (iproute2) it falls back to were not in the package set at
> all.

> **Update (v9 — [ADR 0016](decisions/0016-mainline-first-wifi-drivers.md)):**
> two facts this doc records have since changed. (1) The P3.1 driver set is no
> longer six out-of-tree forks: 8188eu/8188fu (→ in-kernel `rtl8xxxu`), 8821cu
> (→ `rtw88_8821cu`), 8822bu (→ `rtw88_8822bu`, hardware-verified WPA3) and — as
> of PR #35 — 8814au (→ in-kernel `rtw88_8814au`) moved to mainline; only the
> 11ac chips with no mainline USB driver — 8812au, 8821au — remain out-of-tree
> morrownr packages. (2) The §1 claim that
> `/etc/network/interfaces` is **byte-identical** to stock is no longer true:
> each `wlan` stanza gained a `pre-up` wait-for-`wlan0` loop (deliberate — the
> mainline `rtw88`/`rtw89` USB drivers register `nl80211` asynchronously). The
> userland-parity findings below (bash/dialog/wireless-tools/iproute2, the
> nl80211-first path) are unaffected.

## 0. Correction to the task premise — there is no `wifi.sh` in the base image

The task brief (and `TASKS.md` P3.4/P3.13) describe `wifi.sh` as "a MiSTer
Distribution script." **This is not accurate for the base rootfs/release
image.** Searched exhaustively for a literal `wifi.sh`:

- `work/extracted/` (the actual `SD-Installer-Win64_MiSTer` release archive
  contents, `docs/reference-materials.md` §1-2) — only `files/Scripts/update.sh`.
  Full `7z l work/release_20250402.7z | grep -i wifi` → one hit,
  `files/linux/_wpa_supplicant.conf` (a config **template**, not a script).
- `work/imgroot/` (the actual extracted stock rootfs, `linux.img`) — zero
  files named `wifi.sh` or `wifi*` anywhere.
- `work/Main_MiSTer/` (the frontend binary source, commit `14052d2`) — zero
  references; grepped for `wifi` project-wide, the only hit is an unrelated
  character-ROM glyph comment (`charrom.cpp:45`, `// 29 [0x1d] wifi`, a font
  glyph name).
- `work/Downloader_MiSTer/` — zero references.

**What `wifi.sh` actually is:** a real, third-party community script,
`MiSTer-devel/Scripts_MiSTer`, `other_authors/wifi.sh`
(<https://github.com/MiSTer-devel/Scripts_MiSTer/blob/master/other_authors/wifi.sh>,
adapted from The RetroPie Project, per its own header comment). It is
**user-invoked from Main_MiSTer's OSD Scripts menu** (an interactive
`dialog`-driven SSID-scan-and-connect helper), not a boot-time daemon
script, and it ships onto `/media/fat/Scripts/` via the Downloader/Scripts
database — never through our rootfs build, exactly the same "lives on
`/media/fat`, shipped by `Distribution_MiSTer`, not by us" pattern
`docs/abi-contract.md` §7.6 documents for every other `Scripts/*.sh`. The
full 207-line script was fetched and read directly (network access
confirmed available in this environment) for this audit; every path/flag/
binary claim below is cited to an exact line number in it.

This mirrors several premise corrections already on record for this project
(`docs/phase0-review.md` #18/#29, `docs/abi-contract.md` X1) — a task brief
described a mechanism that doesn't literally exist as named, and the
resolution is to identify the *actual* mechanism and verify parity against
that, not to manufacture a file that was never shipped. **The TASKS.md text
itself is out of this task's lane to edit** (explicit hard constraint); this
section is the evidence trail for that correction, for whoever next touches
`TASKS.md`/`PLAN.md`.

Despite the imprecise name, the *intent* of P3.4 — "make sure the thing the
MiSTer community actually uses to configure WiFi keeps working unmodified on
our rootfs" — is completely well-formed once `wifi.sh` is understood as this
real, externally-hosted script. Interestingly, P3.1's already-merged package
comments (`package/rtl8188eu-aircrack-ng/rtl8188eu-aircrack-ng.mk:52`,
`rtl8188fu/rtl8188fu.mk:33`, `rtl8812au/rtl8812au.mk:33`,
`rtl8821au-morrownr/rtl8821au-morrownr.mk:45`,
`rtl8821cu-morrownr/rtl8821cu-morrownr.mk:44`, `rtl88x2bu/rtl88x2bu.mk:31`)
already use the same "MiSTer's wifi.sh" shorthand — inherited from the same
task-brief convention — while independently reaching the correct technical
conclusion (nl80211/nothing-needs-wext). This doc is the first to actually
locate and read the file itself.

## 1. The boot-time contract: `/etc/network/interfaces` + `ifupdown` + `wpa_supplicant`

This is the mechanism that is actually always-on and that both `wifi.sh`
and the plain "type your SSID into `_wpa_supplicant.conf`, reboot" manual
path (stock's own README-level instructions) both depend on.

| Contract element | Stock (`work/imgroot`) | Ours | Status |
|---|---|---|---|
| `/etc/network/interfaces` | `wlan0`/`wlan1` `iface … inet manual` with `pre-up wpa_supplicant -s -B -P /run/wpa_supplicant.$IFACE.pid -i $IFACE -D nl80211,wext -c /media/fat/linux/wpa_supplicant.conf`, `post_up sleep 2`, `post-down killall -q wpa_supplicant` | `board/mister/de10nano/rootfs-overlay/etc/network/interfaces` | **Identical.** `diff` exit 0 against `work/imgroot/etc/network/interfaces` (re-verified this task). Authored by P2.3; `docs/init-parity.md:144` already recorded this. |
| `/etc/init.d/S40network` | `ifup -a` / `ifdown -a` (ifupdown-scripts package default) | Not overlaid — `BR2_PACKAGE_IFUPDOWN_SCRIPTS`'s own Kconfig default (`default y if BR2_ROOTFS_SKELETON_DEFAULT`, `work/buildroot/package/ifupdown-scripts/Config.in`) auto-selects it; our defconfig sets neither `BR2_PACKAGE_SYSTEMD_NETWORKD` nor `BR2_PACKAGE_NETIFRC` (the two symbols that would suppress it) and leaves `BR2_ROOTFS_SKELETON_DEFAULT` at Buildroot's own default (y) | **Identical**, confirmed byte-for-byte by P2.3 (`docs/init-parity.md:63`); re-confirmed the selecting conditions still hold in this defconfig. |
| `/etc/init.d/S41dhcpcd` | starts `dhcpcd` globally (no `-i`) | Package default, not overlaid; `BR2_PACKAGE_DHCPCD=y` (defconfig line 409, P2.1) | **Functionally identical** (P2.3 finding, `docs/init-parity.md:64`) — only the PID-file path differs, an artifact of the newer dhcpcd release, not a decision point. |
| `/etc/dhcpcd.conf` | `hostname`, `clientid`, `option rapid_commit`, etc. enabled | `board/mister/de10nano/rootfs-overlay/etc/dhcpcd.conf` | **Identical.** `diff` exit 0 (re-verified this task). Authored by P2.3. |
| `wpa_supplicant` binary + `-D nl80211,wext` | present | `BR2_PACKAGE_WPA_SUPPLICANT=y` + `_NL80211=y` + `_WEXT=y` (defconfig lines 405-407, P2.1) | **Identical** package selection; both driver backends stock's command line names are compiled in. |
| Control-interface path wpa_supplicant actually uses at runtime | `ctrl_interface=/run/wpa_supplicant` (from the shipped `files/linux/_wpa_supplicant.conf` template, the file a user renames to `wpa_supplicant.conf`) | Same — `/run` is our `fstab`'s tmpfs (`tmpfs /run tmpfs mode=0755,nosuid,nodev 0 0`) | **Identical**, and satisfies the read-only-root constraint (A15/ADR 0011) — the socket lives on tmpfs, never on `/`. |
| `/etc/wpa_supplicant.conf` (package's own upstream sample, `ctrl_interface=/var/run/wpa_supplicant`, `ap_scan=1`, `network={key_mgmt=NONE}`) | present (`work/imgroot/etc/wpa_supplicant.conf`) — confirmed **dead weight**: grepped every stock init script and `/etc/network/interfaces` for `etc/wpa_supplicant` — zero references. It is the package's own installed default, never read by anything. | Installed automatically by `WPA_SUPPLICANT_INSTALL_TARGET_CMDS` (`work/buildroot/package/wpa_supplicant/wpa_supplicant.mk:283-287`, installs `package/wpa_supplicant/wpa_supplicant.conf` verbatim and uncomments its `ctrl_interface` line) | **Identical for free** — same package, same install rule, no overlay action needed. |
| **Operative** config file, `/media/fat/linux/wpa_supplicant.conf` | lives on the FAT **data** partition, delivered by the SD-card installer/Downloader from the `_wpa_supplicant.conf` template, not by the rootfs build | Out of rootfs scope — same "shipped by `Distribution_MiSTer`, not by us" pattern as every other `/media/fat/linux/*` file (`docs/abi-contract.md` §7.6). Our `board/mister/de10nano/rootfs-overlay/media/fat/.gitkeep` (P1.10) only establishes the empty mount point `/init` moves the FAT partition onto. | **N/A to this task** — nothing to author here. |

No `eth0` stanza exists in `/etc/network/interfaces` on stock or on ours —
wired ethernet is brought up by `dhcpcd`'s own default "manage everything
not explicitly excluded" behavior, not by `ifupdown` (`docs/init-parity.md:144`,
re-confirmed).

**Net result: zero rootfs-overlay changes needed for this layer.** Every
file P2.3 already wrote is still byte-identical to stock, and every
`BR2_PACKAGE_WPA_SUPPLICANT*`/`DHCPCD` symbol P2.1 already set is still
correct. This was verified, not assumed — `diff` was re-run against
`work/imgroot` for `/etc/network/interfaces` and `/etc/dhcpcd.conf` in this
task.

## 2. The `wifi.sh` contract itself

Everything below is cited to the actual fetched script,
`other_authors/wifi.sh` @ `master`
(<https://raw.githubusercontent.com/MiSTer-devel/Scripts_MiSTer/master/other_authors/wifi.sh>).

| `wifi.sh` dependency | Where in the script | Stock provides | We provided before this task | Status |
|---|---|---|---|---|
| `bash` interpreter | `wifi.sh:1`, `#!/usr/bin/env bash` | `usr/bin/bash` (`docs/stock-inventory/binaries-needed-full.txt:25`) | **Nothing** — `BR2_PACKAGE_BASH` was not set anywhere in the defconfig | **Gap — fixed.** `BR2_PACKAGE_BASH=y` added. |
| `dialog` (all its menus/inputboxes/infoboxes) | `wifi.sh:25` (`printMsgs`) and every interactive function | `usr/bin/dialog` (`binaries-needed-full.txt:76`) | **Nothing** | **Gap — fixed.** `BR2_PACKAGE_DIALOG=y` added. |
| `ifup wlan0` / `ifdown wlan0` (primary bring-up/tear-down path) | `wifi.sh:36-42`, `_set_interface_wifi()` | ifupdown-scripts | Already present (§1) | **No gap.** |
| `ip link set wlan0 up/down` (fallback only if `ifup`/`ifdown` fail) | `wifi.sh:37,41`, same function | `usr/sbin/ip` (real iproute2, linked against `libcap.so.2` — `binaries-needed-full.txt:461`, not a BusyBox applet) | **Nothing** — no `BR2_PACKAGE_IPROUTE2` | **Gap — fixed.** `BR2_PACKAGE_IPROUTE2=y` added. |
| `iwlist wlan0 scan` (SSID/encryption-type scan) | `wifi.sh:84`, `list_wifi()` | `usr/sbin/iwconfig` present (same wireless-tools package installs `iwlist`/`iwgetid`/`iwspy`/`iwpriv` alongside it — `binaries-needed-full.txt:465`) | **Nothing** — no `BR2_PACKAGE_WIRELESS_TOOLS` | **Gap — fixed.** `BR2_PACKAGE_WIRELESS_TOOLS=y` (+`_IWCONFIG=y`, default) added. |
| `iwgetid -r` (poll for a successful association) | `wifi.sh:195`, `gui_connect_wifi()` | same wireless-tools package | **Nothing** | **Same fix as above.** |
| `/media/fat/linux/wpa_supplicant.conf` — the file `wifi.sh` reads/writes directly (`remove_wifi()` at `wifi.sh:47`, `set_wifi_country()` at `wifi.sh:66-71`, `create_config_wifi()` at `wifi.sh:180-184`) | same FAT-partition path stock's `/etc/network/interfaces` reads via `-c` | n/a (FAT partition) | n/a (FAT partition) | **Already aligned** — `wifi.sh` and the boot-time `pre-up wpa_supplicant … -c /media/fat/linux/wpa_supplicant.conf` hook operate on the exact same file, which is why `wifi.sh` never has to invoke `wpa_supplicant` or `wpa_cli` itself: writing the file and toggling the interface (`ifup`/`ifdown`) is enough to make the `pre-up` hook re-exec `wpa_supplicant` with the new config. |
| `/sys/class/net/wlan0/` (interface-presence check) | `wifi.sh:89` | sysfs | sysfs (`fstab`: `sysfs /sys sysfs defaults 0 0`) | **No gap** — standard devtmpfs/sysfs, appears automatically once P3.1/P3.3's driver+firmware bring up the netdev; not a rootfs-config item. |
| `wpa_cli` | **not called anywhere in the script** | — | — | **N/A** — confirms the task brief's "whether it calls wpa_cli" question: no, it does not. |
| `udhcpc`/direct `dhcpcd` invocation | **not called anywhere in the script** | — | — | **N/A** — DHCP is handled entirely by the already-running global `dhcpcd` daemon (`S41dhcpcd`) picking up the now-admin-up `wlan0`, same as stock. |

Three genuinely new Buildroot packages were needed
(`configs/mister_de10nano_defconfig:463-467`, new "P3.4: WiFi userland
parity (`wifi.sh` contract)" section): `BR2_PACKAGE_BASH`,
`BR2_PACKAGE_DIALOG`, `BR2_PACKAGE_WIRELESS_TOOLS` (+`_IWCONFIG`, its own
default-y sub-option, listed for clarity per this file's existing
convention), and `BR2_PACKAGE_IPROUTE2`. Their transitive Kconfig
dependencies were checked, not assumed:

- `bash` (`work/buildroot/package/bash/Config.in`): `select
  BR2_PACKAGE_NCURSES` + `select BR2_PACKAGE_READLINE` — both already `=y`
  in this defconfig; `depends on BR2_PACKAGE_BUSYBOX_SHOW_OTHERS` — already
  `=y` (defconfig line 359, a P2.1 addition originally needed for a
  different package but satisfies this too).
- `dialog` (`work/buildroot/package/dialog/Config.in`): `select
  BR2_PACKAGE_NCURSES` (already `=y`); `select BR2_PACKAGE_LIBICONV if
  !BR2_ENABLE_LOCALE` — `BR2_ENABLE_LOCALE` is already `=y` (glibc default
  for this toolchain, per the existing comment at defconfig line ~224), so
  this select is a no-op.
- `wireless_tools` (`work/buildroot/package/wireless_tools/Config.in`): no
  hard dependencies beyond the toolchain; `_IWCONFIG` sub-option (default
  `y`) is what actually builds `iwconfig`/`iwlist`/`iwspy`/`iwpriv`/`iwgetid`.
- `iproute2` (`work/buildroot/package/iproute2/Config.in`): `depends on
  BR2_TOOLCHAIN_HEADERS_AT_LEAST_3_4` — trivially satisfied by a 6.18-era
  toolchain.

None of these four touch the kernel, firmware, or any P3.1/P3.3 file —
strictly userland package selection, in this task's lane.

## 3. Driver backend confirmation (`-D nl80211,wext`)

Stock's `/etc/network/interfaces` passes `-D nl80211,wext` — try `nl80211`
first, fall back to `wext`. P3.1's already-merged analysis (identical
finding independently reached and documented across all six out-of-tree
Realtek packages —
`package/rtl8188eu-aircrack-ng/rtl8188eu-aircrack-ng.mk:43-55`,
`package/rtl8188fu/rtl8188fu.mk:24-35`, `package/rtl8812au/rtl8812au.mk:23-38`,
`package/rtl8821au-morrownr/rtl8821au-morrownr.mk:37-47`,
`package/rtl8821cu-morrownr/rtl8821cu-morrownr.mk:36-46`,
`package/rtl88x2bu/rtl88x2bu.mk:23-33`) is:

- Every one of these drivers registers `rtw_cfg80211_ops` /
  `wiphy_register()` (`os_dep/linux/ioctl_cfg80211.c`) **unconditionally**
  — the `nl80211` path always works, on every dongle.
- The `#ifdef CONFIG_WIRELESS_EXT` code in each driver (legacy Wireless-
  Extensions ioctl table, `os_dep/linux/os_intfs.c`'s
  `dev->wireless_handlers`, and `iwconfig`-style signal stats in
  `ioctl_linux.c`) is **not** the same thing `wpa_supplicant -D wext` (or
  this project's `wireless-tools`) actually needs at the kernel level, and
  our kernel does not define `CONFIG_WIRELESS_EXT` (a non-prompt,
  select-only symbol in 6.18, P1.3 finding) — so that vendor-driver code
  simply compiles out.
- What *does* matter for `iwlist`/`iwconfig`/`iwgetid` (§2) and for
  `wpa_supplicant -D wext` to have any chance of working against a
  cfg80211-registered device is a **different**, kernel-side Kconfig
  symbol: `CONFIG_CFG80211_WEXT`, cfg80211's own WEXT ioctl compatibility
  shim (translates legacy `SIOCG/SIOCSIW*` ioctls onto the same
  `wiphy`/`cfg80211_ops` every driver already registers for `nl80211`,
  driver-code-agnostic). This is out of P3.4's lane to change (kernel
  config is P1.3/P3.1 territory).
  **RESOLVED at integration (orchestrator):** `CONFIG_CFG80211_WEXT=y` is
  present in both stock's `stock-linux.config` **and** our resolved build
  (`output/build/linux-6.18.33/.config`) — it is a Kconfig default that
  `savedefconfig` omits from `board/.../linux.config`, so it was there all
  along. The WEXT compat shim is live, so `iwlist`/`iwgetid` and
  `wpa_supplicant -D wext` have a working path against the cfg80211-only
  Realtek drivers. No kernel change needed.
  Even without it, since `nl80211` is listed first in `-D nl80211,wext` and
  is confirmed to always work on every P3.1 driver,
  **`wext` is not required for basic association** — it is stock's own Since `nl80211` is listed first in
  `-D nl80211,wext` and is confirmed to always work on every P3.1 driver,
  **`wext` is not required for basic association** — it is stock's own
  belt-and-suspenders fallback ordering, reproduced unchanged, not a gap.
  `iwlist`/`iwgetid`'s WEXT dependency (§2) is a separate, narrower
  question (scan/status *display* only, not association) worth the same
  build-time confirmation.

In-tree drivers (`rtlwifi`, `mwifiex`/`mwifiex_usb`, per
`docs/stock-inventory/modules.md:37,64-65`) are mac80211/cfg80211 clients
by construction — `nl80211` is their native, primary control path in any
kernel from this era; no separate check needed.

## 4. Files touched by this task

- **Edited** `configs/mister_de10nano_defconfig` — added the "P3.4: WiFi
  userland parity (`wifi.sh` contract)" section (lines 424-467):
  `BR2_PACKAGE_BASH=y`, `BR2_PACKAGE_DIALOG=y`, `BR2_PACKAGE_WIRELESS_TOOLS=y`
  (+`_IWCONFIG=y`), `BR2_PACKAGE_IPROUTE2=y`. No other defconfig lines
  changed.
- **Added** this doc.
- **No rootfs-overlay changes.** `/etc/network/interfaces` and
  `/etc/dhcpcd.conf` (P2.3) audited and re-confirmed byte-identical to
  stock; no overlay file needed for `bash`/`dialog`/`wireless-tools`/
  `iproute2` (none ship a config file anything here depends on).
- **No `TASKS.md`/`PLAN.md`/`docs/size-budget.md`/`docs/package-manifest.md`
  changes** — explicitly out of this task's lane per the hard constraints;
  §0 above is the evidence trail for whoever next touches those.
- **No firmware or kernel changes** — P3.1/P3.3's territory, not touched.

## 5. Verify-in-build / verify-on-hardware checklist (for the orchestrator)

Everything below needs the integrated build and, where marked **[HW]**,
real hardware — this worktree has no `output/` tree (author-only
constraint) and did not run `make`. Items not marked [BUILD]/[HW] were
confirmed by reading `work/imgroot`, the fetched `wifi.sh` source, and this
worktree's files directly.

- **[BUILD]** `bash`, `dialog`, `iwconfig`/`iwlist`/`iwgetid`, and `ip` all
  land in `output/target/usr/bin`, `/usr/bin`, `/usr/sbin`, `/usr/sbin`
  respectively, and are dynamically linked against libraries already in
  the image (`libncursesw.so.6`, `libreadline.so.8`, `libhistory.so.8`,
  `libcap.so.2`) — confirm no missing-SONAME surprises at link time.
- **[BUILD]** `/etc/network/interfaces` and `/etc/dhcpcd.conf` in
  `output/target/etc/` still match this worktree's overlay exactly (the
  overlay-wins-over-package-default mechanism already proven for other
  files, e.g. `docs/init-parity.md`'s dhcpcd.conf entry) — sanity check
  only, no change expected.
- **[BUILD]** `dmesg`/boot log: `wpa_supplicant` does **not** start at boot
  on a fresh image with no `/media/fat/linux/wpa_supplicant.conf` present
  — the `pre-up [ -f /media/fat/linux/wpa_supplicant.conf ]` guard
  (`/etc/network/interfaces` line 8/15) should make `ifup wlan0`/`wlan1`
  a silent no-op, not an error, on a read-only root with no FAT config
  yet. Confirms P2.3's guard logic survives unmodified.
- **[BUILD]** With a `/media/fat/linux/wpa_supplicant.conf` staged (e.g.
  the renamed `_wpa_supplicant.conf` template) before boot: `wpa_supplicant`
  starts successfully on the read-only root (per ADR 0011, use
  `dmesg`/boot console output, not a post-login `mount`, to avoid the
  `/etc/profile` rw-remount masking the real read-only-root state), its
  control socket appears at `/run/wpa_supplicant/wlan0` (tmpfs, not on
  `/`), and its PID file appears at `/run/wpa_supplicant.wlan0.pid`.
- **[BUILD]** Confirm `CONFIG_CFG80211_WEXT` in the built kernel `.config`
  (§3) — determines whether `iwlist`/`iwconfig`/`iwgetid`'s legacy ioctls
  have a live path against the P3.1 Realtek drivers and the in-tree
  drivers. If unset, `iwlist`/`iwgetid` will return nothing/fail even
  though `nl80211`-based association still works fine — `wifi.sh`'s scan
  menu (`list_wifi()`) and its post-connect confirmation
  (`gui_connect_wifi()`'s `iwgetid -r` poll) would be affected, though the
  actual WiFi connection would still succeed underneath. Flag as a defect
  against P1.3/P3.1 if `CONFIG_CFG80211_WEXT` turns out unset — **not** a
  P3.4 rootfs-package problem (the binaries are correctly present either
  way).
- **[HW]** (P3.13, this task's own "done when" per `TASKS.md`) Run the
  actual `wifi.sh` from `/media/fat/Scripts/` on real hardware, unmodified:
  scan finds real SSIDs (`iwlist`), pick a network, enter a password,
  confirm `gui_connect_wifi()` reports success (`iwgetid -r` resolves) and
  the interface gets a DHCP lease. Test against at least one P3.1 Realtek
  USB dongle and, if available, the DE10-Nano's own in-tree-supported
  adapter, to exercise both driver families.
- **[HW]** Manual (non-`wifi.sh`) path: rename `_wpa_supplicant.conf` →
  `wpa_supplicant.conf` on the FAT partition by hand, edit SSID/PSK,
  reboot, confirm association — the "existing user configs work unchanged"
  half of `TASKS.md` P3.4's done-when, independent of the community
  script.

## 6. v10 — Broadcom/Cypress, MT7663U firmware, ar3k, and the last two forks retired

> Scope of this section: a driver/firmware-coverage change, not a userland
> one. Nothing in §1–§5 above changes — no rootfs-overlay file, no
> `wpa_supplicant`/`dhcpcd`/`wifi.sh` dependency, no `/etc` file. It is
> recorded here because §3 and the defconfig already point readers at this
> doc for "which driver binds which dongle" questions.

### 6.1 Broadcom / Cypress USB WiFi (new)

`CONFIG_WLAN_VENDOR_BROADCOM` was off, so `brcmfmac` — the FullMAC driver for
every BCM43xx/CYW43xx USB dongle — was not built at all. Now on:

| Symbol | Value | Why |
|---|---|---|
| `CONFIG_WLAN_VENDOR_BROADCOM` | `y` | vendor gate; nothing below is selectable without it |
| `CONFIG_BRCMFMAC` | `m` | the FullMAC driver itself |
| `CONFIG_BRCMFMAC_USB` | `y` | the only bus a dongle arrives on here |
| `CONFIG_BRCMFMAC_SDIO` | **explicitly off** | `default y` whenever `CONFIG_MMC=y` (it is — the boot SD card), so it must be written out or `olddefconfig` re-enables it. `linux.config` is a *minimal* defconfig; an absent symbol is not an off symbol. The DE10-Nano exposes no SDIO slot a WiFi module could sit in. |
| `CONFIG_BRCMFMAC_PCIE` | unreachable | `depends on PCI`; `CONFIG_PCI is not set` on this board |
| `CONFIG_BRCMSMAC` | off | the 11n SoftMAC half — PCIe/BCMA only, same reason |

Firmware: `BR2_PACKAGE_LINUX_FIRMWARE_BRCM_BCM43XX` + `_BCM43XXX`. Between
them they install the four BCM43xx **USB** parts `brcmfmac` drives —
`brcm/brcmfmac43143.bin`, `brcmfmac43236b.bin`, `brcmfmac43242a.bin`,
`brcmfmac43569.bin` — plus `brcmfmac4373.bin`. Each also `select`s its
Cypress counterpart (`_CYPRESS_CYW43XX` / `_CYW43XXX`); Cypress bought
Broadcom's IoT line, so `cypress/cyfmac*` is the same silicon under the later
vendor name, and newer dongles ask for the `cyfmac` name. Those selects fire
automatically — confirmed in `output/.config`, not assumed.

**Size cost, measured on the built image** (not estimated — `du` on
`output/target/usr/lib/firmware` after `make all`): `brcm/` is 9.5 MiB and
`cypress/` 5.5 MiB, so these four options add **≈15 MiB**. Most of it is
SDIO/PCIe siblings that *cannot* be used on this board — Buildroot's
sub-options are coarse per-family groupings, the same "documented superset"
already accepted throughout `docs/firmware-parity.md`. The USB-only subset is
≈2.2 MiB, so a curated `linux-firmware-extra` member list could reclaim
≈13 MiB if the budget ever tightens.

It does not need to now — `scripts/check-size-budget.sh output/images/linux.img`
on this build reports **287 MiB used / 225 MiB free / 44.0% free, PASS**
(floor is 15%).

> ⚠️ `docs/size-budget.md`'s "`/lib/firmware` total: 3.1 MiB, 68 regular files"
> line is **stale** — it predates v9's `RTL_RTW89`, whose `rtw89/` directory
> alone is 25 MiB, larger than every v10 addition combined. The directory is
> now **49 MiB across 188 regular files + 67 symlinks**. That doc should be
> regenerated from a current build rather than trusted; flagged here rather
> than edited, since it is a generated report.

### 6.2 MT7663U firmware (driver was already on, firmware was missing)

`CONFIG_MT7663U=m` was already set, but **no** `BR2_PACKAGE_LINUX_FIRMWARE_*`
sub-option installs any `mt7663` file (Buildroot's MediaTek options stop at
MT7601U/MT7610E/MT76X2E/MT7921/MT7925). The driver therefore probed and then
failed at `request_firmware()`. Four files now ship via
`package/linux-firmware-extra`:

| File | Role |
|---|---|
| `mediatek/mt7663pr2h.bin` | ROM patch, offload/v3 path (`MT7663_OFFLOAD_ROM_PATCH`) |
| `mediatek/mt7663_n9_v3.bin` | N9 firmware paired with it (`MT7663_OFFLOAD_FIRMWARE_N9`) |
| `mediatek/mt7663pr2h_rebb.bin` | ROM patch, fallback path (`MT7663_ROM_PATCH`) |
| `mediatek/mt7663_n9_rebb.bin` | N9 firmware paired with it (`MT7663_FIRMWARE_N9`) |

All four are `MODULE_FIRMWARE()`-declared in
`drivers/net/wireless/mediatek/mt76/mt7615/usb.c`. `mt7663_load_rom_patch()`
(`mt7615/mcu.c`) tries one ROM patch, logs `"%s not found, switching to %s"`
and tries the other, then selects the N9 blob **to match whichever patch
bound** — so shipping only one pair leaves a live fallback path broken.
Both pairs are shipped.

> **Note on the requested filename.** The task asked for
> `mt7663pr2h_rxd.bin`. No such file exists — not in the pinned 6.18.40 kernel
> (the only `mt7663*` firmware strings are the four `#define`s at
> `mt7615/mt7615.h:48-51`; a tree-wide grep for `mt7663pr2h_rxd` returns
> nothing) and not in linux-firmware 20260410 (`mediatek/` carries
> `mt7663_n9_rebb.bin`,
> `mt7663_n9_v3.bin`, `mt7663pr2h.bin`, `mt7663pr2h_rebb.bin` — no `_rxd`
> variant). The four files above are what MT7663U actually loads. Same
> "identify the real mechanism rather than manufacture the named file" posture
> as §0.

### 6.3 ar3k / ath3k Atheros Bluetooth firmware (driver was already on)

Same shape as §6.2: `CONFIG_BT_ATH3K=m` was already built, but **no** firmware
for it was installed, so every AR3011/AR3012 dongle failed at
`request_firmware()`. Now enabled:

- `BR2_PACKAGE_LINUX_FIRMWARE_AR3011` → `ath3k-1.fw`, matching
  `#define ATH3K_FIRMWARE "ath3k-1.fw"` (`drivers/bluetooth/ath3k.c:18`).
- `BR2_PACKAGE_LINUX_FIRMWARE_AR3012_USB` → the `ar3k/*.dfu` patch and config
  RAM images, matching the paths `ath3k.c` builds at runtime:
  `snprintf(..., "ar3k/AthrBT_0x%08x.dfu", ...)` (line 378) and
  `snprintf(..., "ar3k/ramps_0x%08x_%d%s", ...)` (line 440).

Path shapes verified against the driver, and the files confirmed present in
the extracted linux-firmware tree — not assumed from upstream naming.

### 6.4 The complete mainline `rtw88` USB set — and the end of the fork era

Three `RTW88_*U` chips mainline offers were not built. All three now are:

| Symbol | Chip | Firmware (already shipping via `_RTL_RTW88`'s `rtw88/rtw*.bin` glob) |
|---|---|---|
| `CONFIG_RTW88_8723DU` | RTL8723DU 11n | `rtw88/rtw8723d_fw.bin` |
| `CONFIG_RTW88_8821AU` | RTL8811AU/RTL8821AU 11ac | `rtw88/rtw8821a_fw.bin` |
| `CONFIG_RTW88_8812AU` | RTL8812AU 11ac | `rtw88/rtw8812a_fw.bin` |

No new firmware option was needed — Buildroot installs the whole
`rtw88/rtw*.bin` glob, and all three blobs were already on the image,
unused.

Every `RTW88_*` chip option 6.18 offers is now either built or structurally
unreachable:

- **built** — all seven USB parts: 8822BU, 8822CU, 8821CU, 8814AU (already)
  + 8723DU, 8821AU, 8812AU (new).
- **unreachable** — the PCIe siblings (`RTW88_8822BE/8822CE/8723DE/8821CE/8814AE`)
  all `depends on PCI`, and `CONFIG_PCI is not set` on this board.
- **deliberately off** — the SDIO siblings (`RTW88_8822BS/8822CS/8723DS/8723CS/8821CS`)
  are selectable (`CONFIG_MMC=y`) but the DE10-Nano's only MMC host drives the
  boot SD card; there is no slot for an SDIO WiFi module. Left off as dead
  weight. Flip them on in `linux.config` if that ever changes.

**This retires the last two out-of-tree WiFi forks.** ADR 0016 kept
`package/rtl8812au` and `package/rtl8821au-morrownr` on the sole grounds that
mainline had no USB driver for RTL8812AU / RTL8811AU / RTL8821AU. That is no
longer true: the shared `rtw88_88xxa` core (`RTW88_88XXA`, `rtw88xxa.c`)
landed upstream in 6.13, **after** ADR 0016 was written. Both packages are now
deselected in the defconfig (kept sourced, one-line revert), for the same
reasons that drove the 8822BU and 8814AU switches: mainline goes through
`mac80211` so WPA3/SAE/PMF behave correctly, and the forks need hand-written
compat patches at every kernel bump.

#### USB-ID coverage diff — nothing is lost

The obvious risk in dropping a vendor fork is a dongle that only the fork's ID
table claimed. Measured rather than assumed, by extracting both tables:

- the two forks (`os_dep/linux/usb_intf.c`) list **57** IDs;
- mainline `rtw8812au.c` + `rtw8821au.c` list **50**;
- the 50 are a **strict subset** of the 57 — mainline claims nothing the forks
  did not.

Every one of the 7 remaining IDs is claimed by a *different* in-kernel driver
this image already builds. The forks' tables simply over-claimed IDs belonging
to other chips; mainline attributes them correctly:

| ID | Fork claimed it as 88xxa | Mainline driver that actually owns it | Built? |
|---|---|---|---|
| `056e:400b` | yes | `rtw88_8814au` | ✅ `CONFIG_RTW88_8814AU=m` |
| `056e:400d` | yes | `rtw88_8814au` | ✅ |
| `0b05:1817` | yes | `rtw88_8814au` (ASUS USB-AC68, 4×4 RTL8814AU) | ✅ |
| `2001:331a` | yes | `rtw88_8814au` | ✅ |
| `7392:a834` | yes | `rtw88_8814au` | ✅ |
| `07b8:8179` | yes | `rtl8xxxu` (RTL8188EUS) | ✅ `CONFIG_RTL8XXXU=m` |
| `13b1:0043` | yes | `rtw88_8822bu`/`8822cu` (Linksys WUSB6300 **v2**, RTL8822BU) | ✅ |

`13b1:0043` is the instructive one: only the WUSB6300 **v1** (`13b1:003f`) is a
true RTL8812AU, and mainline's `rtw8812au.c` does carry `003f`. The fork
claimed both revisions for its 8812au driver, which would have bound the v2's
RTL8822BU silicon to the wrong driver.

**Net effect: identical or better device coverage**, with correct per-chip
attribution. Verified by grepping the pinned kernel tree for each ID.

If some unlisted dongle ever needs a manual bind, mainline supports the
standard sysfs escape hatch without rebuilding anything:
`echo <vid> <pid> > /sys/bus/usb/drivers/rtw88_8812au/new_id`.

### 6.5 Verify-on-hardware checklist (v10 additions)

- **[HW]** A BCM43xx/CYW43xx **USB** dongle enumerates, `brcmfmac` binds,
  firmware loads without a `request_firmware` failure in `dmesg`, and
  `wpa_supplicant -D nl80211` associates.
- **[HW]** An MT7663U dongle: confirm in `dmesg` which ROM-patch path bound
  (the `"not found, switching to"` line tells you), and that the paired N9
  blob loaded.
- **[HW]** An AR3011 or AR3012 Bluetooth dongle: `ath3k` loads `ath3k-1.fw`
  (AR3011) or the `ar3k/*.dfu` pair (AR3012), the device re-enumerates, and
  `hciconfig` shows the HCI interface come up.
- **[HW]** **Regression-critical** — an RTL8812AU and an RTL8811AU/8821AU
  dongle, the two chips whose driver *changed* in this branch. Confirm
  `rtw88_8812au`/`rtw88_8821au` bind (not the old fork), association works,
  and — the reason for the switch — WPA3/SAE succeeds where the fork failed
  with `status_code=1`.
- **[HW]** An RTL8814AU dongle still binds `rtw88_8814au` with the forks now
  gone (it did before; the forks were claiming 5 of its IDs, so this confirms
  removing them changed nothing for it).
