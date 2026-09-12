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
> of PR #35 — 8814au (→ in-kernel `rtw88_8814au`) moved to mainline; ~~only the
> 11ac chips with no mainline USB driver — 8812au, 8821au — remain out-of-tree
> morrownr packages~~ (**superseded twice, see below**). (2) The §1 and §4 claims
> that `/etc/network/interfaces` is **byte-identical** to stock are no longer true:
> each `wlan` stanza gained a `pre-up` wait-for-`wlan0` loop (deliberate — the
> mainline `rtw88`/`rtw89` USB drivers register `nl80211` asynchronously). The
> userland-parity findings below (bash/dialog/wireless-tools/iproute2, the
> nl80211-first path) are unaffected.
>
> **Update (v10, §6.4 below):** 8812au and 8821au also moved to mainline
> (`rtw88_8812au`/`rtw88_8821au`, the shared `RTW88_88XXA` core landed in
> 6.13) and their morrownr packages were deselected. That took the
> out-of-tree count to **zero** — briefly true, and no longer.
>
> **Update (v10.2, §8 below):** the exhaustive USB audit (§7) found one chip
> mainline still cannot drive on this board at all — RTL8852CU/RTL8832CU
> Wi-Fi 6E, whose only mainline bus file (`rtw8852ce.c`) needs `CONFIG_PCI`,
> which this board does not have. `package/rtl8852cu-morrownr` was added and
> is the current count: **one** out-of-tree WiFi driver, not zero and not
> six. Anywhere else in this document that says "zero out-of-tree drivers"
> is describing the v10 state and is superseded by this note.
>
> **Update (§10 below, 2026-09-11):** stock's `MiSTer-v6.18` fork HEAD added an AIC8800
> Wi-Fi/BT out-of-tree driver. Owner decision **D2: defer, no package** — it compiles
> clean, but is inert without ~60 unverified firmware blobs and ships no license file.
> ~~The out-of-tree count stays **one** (`rtl8852cu-morrownr`); AIC8800 is not packaged.~~
> **SUPERSEDED — see §10.1 and §11.**
>
> **Update (2026-09-10, §10.1 and §11):** two decisions reversed the state above.
> (1) **D2 is REVERSED**: `package/aic8800` now ships the driver *and* its firmware,
> sourced from `radxa-pkg/aic8800` — the same AICSemi SDK snapshot stock vendored, which
> unlike stock also publishes the blobs. (2) The seven **deselected** Realtek fork
> packages were **deleted**. So the out-of-tree WiFi driver count is **two**
> (`rtl8852cu-morrownr`, `aic8800`) and the count of out-of-tree WiFi packages that exist
> but are not built is **zero**, down from seven.

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
| `/etc/network/interfaces` | `wlan0`/`wlan1` `iface … inet manual` with `pre-up wpa_supplicant -s -B -P /run/wpa_supplicant.$IFACE.pid -i $IFACE -D nl80211,wext -c /media/fat/linux/wpa_supplicant.conf`, `post_up sleep 2`, `post-down killall -q wpa_supplicant` | `board/mister/de10nano/rootfs-overlay/etc/network/interfaces` | **Adapted (v9, revised).** Stock's content, plus a header comment and two `pre-up` lines per `wlan` stanza: a `[ -e /sys/class/net/$IFACE ]` device-presence guard and the `i=0; while [ $i -lt 20 ] && ! iw dev $IFACE info …` wait loop behind it — `diff` against `work/imgroot/etc/network/interfaces` exits 1 with exactly 47 added lines (43 comment + 4 code) and zero removals. Every stock directive is reproduced unchanged; nothing is removed. Authored by P2.3 (then byte-identical), diverged by `4cf2fc7` (v9); the guard was added later to stop `S40network`'s `ifup -a` burning the full 20 s on an absent `wlan1` (§9). `docs/init-parity.md:150` carries the same row. |
| `/etc/init.d/S40network` | `ifup -a` / `ifdown -a` (ifupdown-scripts package default) | Not overlaid — `BR2_PACKAGE_IFUPDOWN_SCRIPTS`'s own Kconfig default (`default y if BR2_ROOTFS_SKELETON_DEFAULT`, `work/buildroot/package/ifupdown-scripts/Config.in`) auto-selects it; our defconfig sets neither `BR2_PACKAGE_SYSTEMD_NETWORKD` nor `BR2_PACKAGE_NETIFRC` (the two symbols that would suppress it) and leaves `BR2_ROOTFS_SKELETON_DEFAULT` at Buildroot's own default (y) | **Identical**, confirmed byte-for-byte by P2.3 (`docs/init-parity.md:63`); re-confirmed the selecting conditions still hold in this defconfig. |
| `/etc/init.d/S41dhcpcd` | starts `dhcpcd` globally (no `-i`) | Package default, not overlaid; `BR2_PACKAGE_DHCPCD=y` (defconfig line 807, P2.1) | **Functionally identical** (P2.3 finding, `docs/init-parity.md:64`) — only the PID-file path differs, an artifact of the newer dhcpcd release, not a decision point. |
| `/etc/dhcpcd.conf` | `hostname`, `clientid`, `option rapid_commit`, etc. enabled | `board/mister/de10nano/rootfs-overlay/etc/dhcpcd.conf` | **Identical.** `diff` exit 0 (re-verified this task). Authored by P2.3. |
| `wpa_supplicant` binary + `-D nl80211,wext` | present | `BR2_PACKAGE_WPA_SUPPLICANT=y` + `_NL80211=y` + `_WEXT=y` (defconfig lines 745-747, P2.1) | **Identical** package selection; both driver backends stock's command line names are compiled in. |
| Control-interface path wpa_supplicant actually uses at runtime | `ctrl_interface=/run/wpa_supplicant` (from the shipped `files/linux/_wpa_supplicant.conf` template, the file a user renames to `wpa_supplicant.conf`) | Same — `/run` is our `fstab`'s tmpfs (`tmpfs /run tmpfs mode=0755,nosuid,nodev 0 0`) | **Identical**, and satisfies the read-only-root constraint (A15/ADR 0011) — the socket lives on tmpfs, never on `/`. |
| `/etc/wpa_supplicant.conf` (package's own upstream sample, `ctrl_interface=/var/run/wpa_supplicant`, `ap_scan=1`, `network={key_mgmt=NONE}`) | present (`work/imgroot/etc/wpa_supplicant.conf`) — confirmed **dead weight**: grepped every stock init script and `/etc/network/interfaces` for `etc/wpa_supplicant` — zero references. It is the package's own installed default, never read by anything. | Installed automatically by `WPA_SUPPLICANT_INSTALL_TARGET_CMDS` (`work/buildroot/package/wpa_supplicant/wpa_supplicant.mk:283-287`, installs `package/wpa_supplicant/wpa_supplicant.conf` verbatim and uncomments its `ctrl_interface` line) | **Identical for free** — same package, same install rule, no overlay action needed. |
| **Operative** config file, `/media/fat/linux/wpa_supplicant.conf` | lives on the FAT **data** partition, delivered by the SD-card installer/Downloader from the `_wpa_supplicant.conf` template, not by the rootfs build | Out of rootfs scope — same "shipped by `Distribution_MiSTer`, not by us" pattern as every other `/media/fat/linux/*` file (`docs/abi-contract.md` §7.6). Our `board/mister/de10nano/rootfs-overlay/media/fat/.gitkeep` (P1.10) only establishes the empty mount point `/init` moves the FAT partition onto. | **N/A to this task** — nothing to author here. |

No `eth0` stanza exists in `/etc/network/interfaces` on stock or on ours —
wired ethernet is brought up by `dhcpcd`'s own default "manage everything
not explicitly excluded" behavior, not by `ifupdown` (`docs/init-parity.md:144`,
re-confirmed).

**Net result: zero rootfs-overlay changes needed for this layer.** Every
`BR2_PACKAGE_WPA_SUPPLICANT*`/`DHCPCD` symbol P2.1 already set is still
correct, and every file P2.3 wrote still reproduces stock's directives.
Verified, not assumed — `diff` was re-run against `work/imgroot` in this
task: `/etc/dhcpcd.conf` is byte-identical (exit 0); `/etc/network/interfaces`
is stock plus v9's additive `pre-up` lines and their header comment (exit 1,
47 added lines, nothing removed — see the row above).

## 2. The `wifi.sh` contract itself

Everything below is cited to the actual fetched script,
`other_authors/wifi.sh` @ `master`
(<https://raw.githubusercontent.com/MiSTer-devel/Scripts_MiSTer/master/other_authors/wifi.sh>).

> **RE-CHECKED 2026-08-01 against the currently-pinned `wifi.sh`, and three rows were
> wrong.** This table was written against the RetroPie-derived `wifi.sh` v1.x. The pin in
> `scripts/fetch-sdcard-payload.sh` (`PINNED_WIFI_SH_COMMIT`) now resolves to upstream's
> **v2.3.0 rewrite** — 3070 lines against the old ~200 — which manages `wpa_supplicant`
> itself instead of delegating to `ifup`/`ifdown`. The rows below are corrected; every
> `wifi.sh:NN` citation still refers to **v1.x** line numbers and means nothing in v2.3.0,
> so they are marked rather than retyped against a file nobody re-audited line by line.
>
> **The conclusion this table exists to support is unchanged, and was re-verified on
> hardware:** every tool the new version needs is already in the image — `wpa_cli`
> (`BR2_PACKAGE_WPA_SUPPLICANT_CLI=y`, defconfig:772), `wpa_supplicant`, `dhcpcd`,
> `udhcpc`, `iwgetid`, `iwlist`, `dialog`, `bash`, `ip`. The only one absent is
> `dhclient`, and it is the **third** DHCP fallback (`wifi.sh:2027`), tried only after
> `dhcpcd` (`:2021`) and `udhcpc` (`:2024`) have both failed — both of which we ship. No
> package changes are required; the four packages this analysis added are still exactly
> the right four.

| `wifi.sh` dependency | Where in the script | Stock provides | We provided before this task | Status |
|---|---|---|---|---|
| `bash` interpreter | `wifi.sh:1`, `#!/usr/bin/env bash` | `usr/bin/bash` (`docs/stock-inventory/20250402/binaries-needed-full.txt:25`) | **Nothing** — `BR2_PACKAGE_BASH` was not set anywhere in the defconfig | **Gap — fixed.** `BR2_PACKAGE_BASH=y` added. |
| `dialog` (all its menus/inputboxes/infoboxes) | `wifi.sh:25` (`printMsgs`) and every interactive function | `usr/bin/dialog` (`binaries-needed-full.txt:76`) | **Nothing** | **Gap — fixed.** `BR2_PACKAGE_DIALOG=y` added. |
| `ifup wlan0` / `ifdown wlan0` | v1.x: the primary bring-up/tear-down path (`wifi.sh:36-42`, `_set_interface_wifi()`). **v2.3.0 deliberately avoids it** and drives `wpa_supplicant` directly (`:2044`) | ifupdown-scripts | Already present (§1) | **No gap either way** — still shipped and still used by the boot path (`/etc/network/interfaces`), just no longer by `wifi.sh`. |
| `ip link set wlan0 up/down` (fallback only if `ifup`/`ifdown` fail) | `wifi.sh:37,41`, same function | `usr/sbin/ip` (real iproute2, linked against `libcap.so.2` — `binaries-needed-full.txt:461`, not a BusyBox applet) | **Nothing** — no `BR2_PACKAGE_IPROUTE2` | **Gap — fixed.** `BR2_PACKAGE_IPROUTE2=y` added. |
| `iwlist wlan0 scan` (SSID/encryption-type scan) | `wifi.sh:84`, `list_wifi()` | `usr/sbin/iwconfig` present (same wireless-tools package installs `iwlist`/`iwgetid`/`iwspy`/`iwpriv` alongside it — `binaries-needed-full.txt:465`) | **Nothing** — no `BR2_PACKAGE_WIRELESS_TOOLS` | **Gap — fixed.** `BR2_PACKAGE_WIRELESS_TOOLS=y` (+`_IWCONFIG=y`, default) added. |
| `iwgetid -r` (poll for a successful association) | `wifi.sh:195`, `gui_connect_wifi()` | same wireless-tools package | **Nothing** | **Same fix as above.** |
| `/media/fat/linux/wpa_supplicant.conf` — the file `wifi.sh` reads/writes directly (`remove_wifi()` at `wifi.sh:47`, `set_wifi_country()` at `wifi.sh:66-71`, `create_config_wifi()` at `wifi.sh:180-184`) | same FAT-partition path stock's `/etc/network/interfaces` reads via `-c` | n/a (FAT partition) | n/a (FAT partition) | **Already aligned** — `wifi.sh` and the boot-time `pre-up wpa_supplicant … -c /media/fat/linux/wpa_supplicant.conf` hook operate on the exact same file, so both agree on the config regardless of which one applies it. **The stated reason has changed, the outcome has not:** v1.x relied on toggling the interface so the `pre-up` hook would re-exec `wpa_supplicant`; v2.3.0 instead launches `wpa_supplicant -B … -c "$WPA_CONF"` itself (`:2044`), guarded by a `wpa_cli ping` probe so it will not double-spawn against our boot-time instance. Same file, same path, still aligned. |
| `/sys/class/net/wlan0/` (interface-presence check) | `wifi.sh:89` | sysfs | sysfs (`fstab`: `sysfs /sys sysfs defaults 0 0`) | **No gap** — standard devtmpfs/sysfs, appears automatically once P3.1/P3.3's driver+firmware bring up the netdev; not a rootfs-config item. |
| `wpa_cli` | v1.x: not called. **v2.3.0: called 13 times**, including the `wpa_cli ping`/`PONG` probe that gates `reload_wpa_supplicant()` | — | — | **No gap** — `BR2_PACKAGE_WPA_SUPPLICANT_CLI=y` (defconfig:772) already ships `/usr/sbin/wpa_cli`; confirmed present on hardware. (This row previously read "not called anywhere in the script", which was true of v1.x and is false of the pinned version.) |
| `udhcpc`/direct `dhcpcd` invocation | v1.x: not called. **v2.3.0 calls all three in order** — `dhcpcd -n` (`:2021`), `udhcpc -n -q -i` (`:2024`), `dhclient` (`:2027`) — each under a timeout, taking the first that succeeds | — | — | **No gap** — we ship `dhcpcd` and `udhcpc`, so the chain succeeds at step 1 or 2 and never reaches `dhclient` (which we do not ship, deliberately: it is ISC's client and adding it to satisfy an unreachable third fallback would be dead weight). The global `S41dhcpcd` daemon still handles the boot path as before. (This row previously read "not called anywhere in the script".) |

Three genuinely new Buildroot packages were needed
(`configs/mister_de10nano_defconfig`, new "P3.4: WiFi userland
parity (`wifi.sh` contract)" section): `BR2_PACKAGE_BASH`,
`BR2_PACKAGE_DIALOG`, `BR2_PACKAGE_WIRELESS_TOOLS` (+`_IWCONFIG`, its own
default-y sub-option, listed for clarity per this file's existing
convention), and `BR2_PACKAGE_IPROUTE2`. Their transitive Kconfig
dependencies were checked, not assumed:

- `bash` (`work/buildroot/package/bash/Config.in`): `select
  BR2_PACKAGE_NCURSES` + `select BR2_PACKAGE_READLINE` — both already `=y`
  in this defconfig; `depends on BR2_PACKAGE_BUSYBOX_SHOW_OTHERS` — already
  `=y` (defconfig line 640, a P2.1 addition originally needed for a
  different package but satisfies this too).
- `dialog` (`work/buildroot/package/dialog/Config.in`): `select
  BR2_PACKAGE_NCURSES` (already `=y`); `select BR2_PACKAGE_LIBICONV if
  !BR2_ENABLE_LOCALE` — `BR2_ENABLE_LOCALE` is already `=y` (glibc default
  for this toolchain, per the existing comment at defconfig lines 296-305), so
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
  **`wext` is not required for basic association** — it is stock's own
  belt-and-suspenders fallback ordering, reproduced unchanged, not a gap.
  `iwlist`/`iwgetid`'s WEXT dependency (§2) is a separate, narrower
  question (scan/status *display* only, not association) worth the same
  build-time confirmation.

In-tree drivers (`rtlwifi`, `mwifiex`/`mwifiex_usb`, per
`docs/stock-inventory/20250402/modules.md:37,64-65`) are mac80211/cfg80211 clients
by construction — `nl80211` is their native, primary control path in any
kernel from this era; no separate check needed.

## 4. Files touched by this task

- **Edited** `configs/mister_de10nano_defconfig` — added the "P3.4: WiFi
  userland parity (`wifi.sh` contract)" section (lines 774-783):
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
  (`/etc/network/interfaces` lines 17/25) should make `ifup wlan0`/`wlan1`
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

### 6.4 The complete mainline `rtw88` USB set — and the end of the *`rtw88`* fork era

> Section title kept, with one word inserted. It read "the end of the fork era"
> until v10.2, which is no longer true of the image as a whole: §8 adds
> `rtl8852cu-morrownr` back for a Wi-Fi 6E chip mainline drives only over PCIe.
> Everything *this* section says about `rtw88` still holds — none of the chips
> below reverted.

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

## 7. v10.1 — exhaustive USB WiFi driver audit

> ⚠ **Version staleness (noted 2026-08-01).** This sweep was run against **6.18.40**; the
> tree is now pinned to **6.18.41**. Every `6.18.40` string below is left as measured.
> **The specific unchecked question** is whether the USB-WiFi symbol count is still 36 —
> i.e. whether 6.18.41 added or removed a prompted `depends on … USB` symbol under
> `drivers/net/wireless/`. A `.y` bump on the same stable line normally does not, and no
> driver family below has been reported changed; nothing else in §7 was re-verified.

§6 closed the gaps that were asked for by name. This section is the
**systematic sweep** behind them: every USB WiFi driver 6.18.40 offers,
checked against what this image builds, so the answer to "is any dongle
family unsupported?" is evidence rather than recollection.

**Method.** Two independent enumerations, cross-checked against each other:

1. Parse every `Kconfig` under `drivers/net/wireless/` for prompted
   `tristate`/`bool` symbols carrying a `depends on … USB` — **36 symbols**.
2. Find every directory containing a `MODULE_DEVICE_TABLE(usb, …)` and map it
   back to the `CONFIG_` symbols in its `Makefile`.

(2) surfaced no driver family absent from (1), so the 36 are the complete set.
A first attempt with a hand-rolled `awk` block-parser returned only 4 and was
discarded — worth recording, because a plausible-looking sweep that silently
under-reports is exactly how a gap survives an audit.

### Result: 27 of 36 built before this round, 30 after

**Added in v10.1** — the non-ancient drivers that were missing:

| Symbol | Chip | Firmware | Note |
|---|---|---|---|
| `RTL8192DU` | RTL8192DU 802.11n dual-band | `rtlwifi/rtl8192dufw.bin` (31 KB) via `linux-firmware-extra` | Requested by name. **Not** an `rtl8xxxu` chip — that driver has no 8192DU support, so nothing in-tree bound it. Buildroot's `_RTL_81XX` ships the PCIe `rtl8192defw.bin` but not the USB one: the same "`e` has a toggle, `u` does not" gap as `mt7610e`/`mt7610u`. |
| `ATH6KL_USB` | AR6003/AR6004 802.11n | `ath6k/AR6004/hw1.2`+`hw1.3` (132 KB) via `_ATHEROS_6004` | `ath6kl_core` + USB bus driver only. |
| `RSI_USB` | Redpine RS9113/RS9116 802.11n | `rsi/rs911{3,6}*` (1.3 MB) via `_REDPINE_RS9113` + `_RS9116` | Both toggles needed — `rsi_91x_hal.c:35` requests `rs9116_wlan.rps`. **The most marginal addition this round**: RS911x is mostly an industrial/IoT module rather than a consumer dongle. Upstream marks it `default m`. Cheap and it works, so it is in; drop `CONFIG_WLAN_VENDOR_RSI`/`RSI_91X`/`RSI_USB` plus those two `BR2_` symbols to revert. |

### Deliberately NOT added, with reasons

| Symbol | Why not |
|---|---|
| `ATH10K_USB` | **Upstream says it does not work.** Its Kconfig prompt is literally "Atheros ath10k USB support (**EXPERIMENTAL**)" and the help text reads "Currently work in progress and **will not fully work**." Building it would let it claim QCA9377 USB IDs and then fail — strictly worse than no driver binding, because nothing else gets a chance. This is the one genuinely modern (802.11ac) driver left unbuilt, and the reason is upstream's own assessment, not ours. Revisit if that warning is ever dropped. |
| `AR5523` | 802.11a/b/g, ~2004 — ancient, out of scope for this round. |
| `AT76C50X_USB` | 802.11b, ~2001 — ancient. |
| `P54_USB` | Prism54 USB, 802.11g, ~2004 — ancient. |
| `ZD1211RW` | ZyDAS ZD1211, 802.11g, ~2005 — ancient. See the consistency note below. |
| `PLFXLC` | pureLiFi X/XL/XC. **Not WiFi** — Light Fidelity (optical) hardware that happens to live under `drivers/net/wireless/`. No MiSTer relevance. |

> **Consistency note on the "ancient" line.** This image *does* build four
> drivers of exactly that vintage — `RT2500USB`, `RT73USB`, `RTL8187` (all
> 802.11g, 2004–2005) and `LIBERTAS`. That is not an inconsistent standard: all
> four are **stock-parity** items, present because MiSTer's 5.15 stock kernel
> shipped them (`docs/stock-inventory/20250402/modules.md` lists `rt2500usb`, `rt73usb`,
> `rtl8187`, `rtl8192cu`). The four ancient drivers left off were never in stock
> and have no other claim. If you would rather have blanket coverage of the
> 802.11g era, `ZD1211RW` is the obvious one-line addition (~100 KB, no
> firmware sub-option needed); it was left off only because the brief said to
> ignore truly ancient hardware.

### Bus-driver completeness (rtw88 / rtw89)

Re-checked exhaustively, not just for the chips named in §6:

- **rtw88** — all seven `RTW88_*U` USB parts are built. The five `RTW88_*E`
  PCIe parts are unreachable (`CONFIG_PCI` unset) and the five `RTW88_*S` SDIO
  parts have no slot.
- **rtw89** — `RTW89_8851BU` + `RTW89_8852BU` are built, and those are the
  *only* USB variants the tree defines. Every other `RTW89_*` chip
  (`8852A`, `8852BT`, `8852C`, `8922A`) exists solely in a `…E` PCIe form.

So no USB part of either driver family is unbuilt.

> ⚠️ **But "no USB *symbol* unbuilt" is not the same as "no USB *dongle*
> unsupported", and for one chip the two diverge.** `RTW89_8852C` is a chip HAL
> with a PCIe bus file only (`rtw8852ce.c`; there is no `rtw8852cu.c`), yet
> **RTL8852CU / RTL8832CU USB dongles are real, on sale, and Wi-Fi 6E** — MSI
> AXE5400, TP-Link Archer TX50UH / TXE70UH, Mercusys MA86XH. Mainline defines
> no symbol for them, so they fell through the symbol-based sweep above:
> nothing was "unbuilt", because nothing existed to build. Reading the line
> "exists solely in a `…E` PCIe form" as *closed* was the audit's one blind
> spot. **This was the last open USB WiFi gap, and §8 closes it.**

### One trap this audit exposed

`RSI_SDIO` is `default m` under `CONFIG_MMC=y` — enabling `RSI_91X` silently
pulled in a second bus driver for a slot this board does not have. Caught by
resolving `linux.config` through `olddefconfig` in a scratch tree *before*
building, and fixed with an explicit `# CONFIG_RSI_SDIO is not set`. This is
the third instance of the same trap (`BRCMFMAC_SDIO` in §6.1, `ATH6KL_SDIO`
which happened to default off, and this one), so `ci-tests.sh` now asserts all
three SDIO bus drivers are absent from the image rather than trusting the
config file to stay correct.

## 8. v10.2 — RTL8852CU: the gap mainline cannot close, and the fork that does

> ⚠ **Version staleness (noted 2026-08-01).** The mainline-gap table below was checked
> against **6.18.40**; the pin is now **6.18.41**, and the `6.18.40` strings are left as
> measured. **The one unchecked question** is whether
> `drivers/net/wireless/realtek/rtw89/` has since gained an `rtw8852cu.c` (a USB bus file
> for the 8852C HAL). If it ever does, this section's entire justification collapses and
> `package/rtl8852cu-morrownr` should be dropped for the in-kernel driver, per ADR 0016.
> Nothing else here was re-run.

§7 closed every gap that had an in-kernel driver waiting to be switched on.
This one has none, so closing it means shipping an out-of-tree driver again —
the first since v10 emptied the list. Maintainer decision, 2026-07-27.

### The gap, verified rather than recalled

| Question | Answer, checked against `output/build/linux-6.18.40/` |
|---|---|
| Does mainline know the chip? | **Yes** — `RTW89_8852C`, with `rtw8852c.c`, `rtw8852c_rfk.c`, `rtw8852c_rfk_table.c`, `rtw8852c_table.c` all present under `drivers/net/wireless/realtek/rtw89/`. |
| Does mainline have a USB bus file for it? | **No.** That directory has `rtw8852ce.c` (PCIe) and **no `rtw8852cu.c`**. For contrast it *does* have `rtw8851bu.c` and `rtw8852bu.c`, so this is 8852C-specific, not "rtw89 lacks USB". |
| What does Kconfig offer? | Only `RTW89_8852CE`, "Realtek 8852CE PCI wireless network (Wi-Fi 6E) adapter", `depends on PCI` — `drivers/net/wireless/realtek/rtw89/Kconfig:113-122`. |
| Is that reachable here? | **No** — this board has no PCIe (`CONFIG_PCI` unset). |
| Net effect before v10.2 | An RTL8852CU dongle bound **nothing**. Not a degraded driver, not a slow one: none. |

That is exactly the condition [ADR 0016](decisions/0016-mainline-first-wifi-drivers.md)
names as its one permitted exception, so the same unchanged rule that emptied
the exception list in v10 re-populates it here with one entry.

### What ships

`BR2_PACKAGE_RTL8852CU_MORROWNR=y` → `package/rtl8852cu-morrownr/`, a
`kernel-module` package pinned to
[morrownr/rtl8852cu-20251113](https://github.com/morrownr/rtl8852cu-20251113)
commit `1530c38e5b1be6d1e96a31cf4f3602a9c23f2465` (HEAD == `refs/heads/main` at
pin time), hash-verified. It builds one module, `8852cu.ko`, into
`usr/lib/modules/$KVER/updates/`.

One patch is carried: `0001-mac_ax-use-div_u64-for-64-bit-division-on-32-bit-arch.patch`
swaps a plain `u64 / 1000` in `phl/hal_g6/mac/mac_ax/fwcmd.c` for the kernel's
`div_u64()`; without it the module fails at `modpost` on ARM32 with
`"__aeabi_uldivmod" [8852cu.ko] undefined!`. Every version bump must re-check it.

Chips: **RTL8852CU / RTL8832CU** — Wi-Fi 6E, 2×2, 2.4/5/**6** GHz.

### Bind-conflict check — clean, but read the warning

The fork's source tree is multi-chip (`Makefile:70-76` carries switches for
8852B, 8852BP, 8852BT, 8851B, 8852C, 8852D, 8842A) and its USB ID table is
`#ifdef`-partitioned per chip (`os_dep/linux/usb_intf.c:143-202`). Upstream
enables **only** `CONFIG_RTL8852C`, so the built module claims nine IDs:

| ID | Device |
|---|---|
| `0bda:c85a`, `0bda:c832`, `0bda:c85d` | Realtek reference |
| `0db0:991d` | MSI AXE5400 |
| `2c4e:0127` | Mercusys MA86XH |
| `3574:6251` | Sihai Lianzong |
| `35b2:0502` | TP-Link Archer TXE70UH |
| `35bc:0101` | TP-Link Archer TX50UH V1 |
| `35bc:0102` | TP-Link Archer TXE70UH(EU) V1 |

All nine were grepped against `drivers/net/wireless/` and `drivers/bluetooth/`
in the pinned tree: **zero matches**. Two near-misses are close enough to be
worth recording — `rtw89_8852bu` holds `35bc:0100` and `35bc:0108`, and `btusb`
holds `2c4e:0128`.

> ⚠️ **Do not enable another chip switch in that Makefile.** The blocks that are
> compiled *out* are precisely the colliding ones: the 8852B block lists
> `0bda:b832/b83a/b852/b85a/a85b`, every one of which mainline's `rtw8852bu.c`
> claims; the 8851B block lists `0bda:b851` (mainline `rtw8851bu.c`) and
> `3574:6211` (mainline `mt76/mt7921/usb.c`). Turning either on recreates the
> load-order-dependent bind fight ADR 0016 exists to prevent.

(Upstream's own `supported-device-IDs` file lists only eight of the nine — it
omits `2c4e:0127`, which `usb_intf.c:184` does carry. The source is
authoritative; the doc lags.)

### No firmware sub-option needed

Unlike mainline `rtw89` (which needs `BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW89` →
`rtw89/*.bin`, already on for 8851BU/8852BU), this vendor tree links its
firmware in as a C array: `Makefile:96` sets `CONFIG_FILE_FWIMG = n`,
`include/autoconf.h:128` defines `LOAD_FW_HEADER_FROM_DRIVER`, and the image is
`phl/hal_g6/mac/fw_ax/rtl8852c/hal8852c_fw.c` — one 13.7 MB generated `.c`. So
there is nothing to add to `/lib/firmware`, and nothing that can fail at
`request_firmware()` — the failure mode §6.2/§6.3 were about. The trade is
size: ~15 MB of the ~67 MB source tree is firmware arrays, so expect a large
`.ko`. **Measured: 1.8 MB as shipped** (`8852cu.ko.xz`; ADR 0016 v10.2).

### The build quirk this package must work around

`EXTRA_CFLAGS` no longer exists in 6.18 kbuild (zero hits across
`output/build/linux-6.18.40/scripts/` and the top-level `Makefile`), and this
tree still writes all its flags there. It translates them itself —
`ccflags-y := $(EXTRA_CFLAGS)` at `Makefile:927-934` — but only when a
kernel-version probe says ≥ 6.15, and that probe shells out to
`$(MAKE) -s -C $(KSRC) kernelversion` with `KSRC` set by
`platform/autodetect.mk:18` to `/lib/modules/$(uname -r)/build`: **the build
host's running kernel**, which in a cross build is wrong and usually absent.
When the probe fails, the translation is skipped and every flag is dropped —
including `-I$(src)/include` and the `-DCONFIG_RTL8852C` that selects the chip.
The package therefore passes `KSRC=$(LINUX_DIR)` alongside `CONFIG_RTL8852CU=m`
in `MODULE_MAKE_OPTS`; a make command-line assignment beats the `:=` in
`autodetect.mk`. Full reasoning, plus the two alternatives that were rejected,
is in `package/rtl8852cu-morrownr/rtl8852cu-morrownr.mk`.

### Honest caveats

- **Built, not run.** The ARMv7 compile is verified: the first real `make all` died at
  `modpost: "__aeabi_uldivmod" [8852cu.ko] undefined!` (a `u64 / 1000` in
  `phl/hal_g6/mac/mac_ax/fwcmd.c`), fixed by the carried
  `0001-mac_ax-use-div_u64-for-64-bit-division-on-32-bit-arch.patch` and re-verified by
  a dirclean rebuild (commit `4c68ae0`); `scripts/ci-tests.sh` now asserts
  `usr/lib/modules/$KVER/updates/8852cu.ko.xz` ships. **No hardware test has been done.**
- **Weaker upstream assurance than the older forks had.** Upstream's
  `README.md:74-75` declares "Kernels: 5.15 - 6.14 (Realtek)" and
  "Kernels: 6.15 - 7.1 (community support)" — 6.18.40 is in the *community*
  band. `package/rtl8812au`, by contrast, was pinned to a commit whose own
  message read "support from kernels 6.17-7.0". Treat a break on a kernel bump
  as expected maintenance.
- **Maintenance cost is back.** Out-of-tree means per-kernel compat work and no
  `mac80211` — the WPA3/SAE argument that drove the 8822bu switch (§6.4, ADR
  0016) does not apply in our favour here. It is accepted because the
  alternative is no driver at all.
- **Revert is one line**: drop `BR2_PACKAGE_RTL8852CU_MORROWNR=y` from the
  defconfig. Nothing in `linux.config` pairs with it — there is no in-kernel
  driver to turn back on.

## 9. T2 — WiFi hotplug (`etc/udev/rules.d/70-persistent-net.rules` closed)

`docs/stock-reconciliation.md` §3c named this the top follow-up: stock ships
`etc/udev/rules.d/70-persistent-net.rules`, we shipped neither it nor an
equivalent, and a WiFi dongle plugged in *after* boot was never brought up
(the boot path — `S40network` → `ifup -a`, plus the v9 `pre-up` wait loop
added to `/etc/network/interfaces`, §1 above — was already fine). This
section records what closed it and, more importantly, the two places the fix
deliberately does **not** match stock's literal rule text, both checked
against this image's actual `eudev`/kernel rather than assumed.

### What ships

- `board/mister/de10nano/rootfs-overlay/etc/udev/rules.d/70-persistent-net.rules`
  — the udev rule (mode 644), heavily commented with the reasoning below and
  its file:line citations.
- `board/mister/de10nano/rootfs-overlay/etc/wifi-hotplug.sh` — the async
  `ifup`/`ifdown` dispatcher the rule's `RUN+=` calls (mode 755).

**Where stock's copy was read, and what it actually contains.** The path is
an `addon.tar` entry — `docs/verification/stock-reconciliation/addon-report-20250402.txt:25`
lists it among that tar's 56 files (marked `ABSENT` there, i.e. absent from
*our* image when that report was generated — which is what this task changes),
and the tar's `sha256` is recorded in
`docs/verification/stock-reconciliation/SOURCE-20250402.txt`. `addon.tar` itself is
**not** unpacked anywhere under `work/`, so the bytes below were read from
the extracted stock rootfs instead:
`work/imgroot/etc/udev/rules.d/70-persistent-net.rules` (450 bytes, mode
`0666`). It is **not** only the two rules — it opens with a five-line
`write_net_rules` banner ("This file was automatically generated by the
`/usr/lib/udev/write_net_rules` program, run by the
`persistent-net-generator.rules` rules file. … change only the value of the
`NAME=` key."). That banner is itself provenance: `write_net_rules` emits
MAC-address-matched rules, not `KERNEL=="wlan*"` + `NAME="wlan0"` + `RUN+=`,
so stock's copy is a generated file that was subsequently hand-edited. Its
two active rules, verbatim (stock's own single-space spacing):

```
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", KERNEL=="wlan*", NAME="wlan0", RUN+="/sbin/ifup -a"
SUBSYSTEM=="net", ACTION=="remove", DRIVERS=="?*", KERNEL=="wlan*", RUN+="/sbin/ifdown %k"
```

### Divergence 1 — no `NAME="wlan0"`

Checked, not assumed, whether `NAME=` on a `SUBSYSTEM=="net"` add rule is
even still honoured by this image's eudev (3.2.14): **yes.** eudev 3.2.14
implements `NAME=`-driven netif rename via `SIOCSIFNAME`, and the path that
actually *compiles* in this image is
`output/build/eudev-3.2.14/src/udev/udev-event.c:1003-1012` (the `#else`
arm) → `rename_netif()` (`:883-885`) → `rename_netif_dev_fromname_toname()`
(`:813-881`) → `ioctl(sk, SIOCSIFNAME, &ifr)` (`:827`). *(No claim is made
here about what systemd-udev does or when eudev forked from it: there is no
systemd source anywhere under `work/` or `output/build/`, so neither is
checkable from this tree. Only the above is, and only the above is
load-bearing.)* A rule in `70-` runs before eudev's own default
`/lib/udev/rules.d/80-net-name-slot.rules`, which explicitly backs off once a
`NAME` has already been assigned (`NAME!="", GOTO="net_name_slot_end"`,
that file's line 5) — so `NAME="wlan0"` here would have worked exactly as it
does on stock. It was left out anyway, for these reasons:

1. **It contradicts this image's two-adapter support — though in *this*
   build the damage is bounded, and the honest version is narrower than it
   first looks.**
   `board/mister/de10nano/rootfs-overlay/etc/network/interfaces` has defined
   both `auto wlan0` and `auto wlan1` since the very first rootfs-overlay
   commit (`c1965694`, P2.3) — this image already supports two concurrent
   WiFi adapters, addressed by the kernel's own sequential `wlan%d`
   numbering. Stock's rule asserts the opposite: that every `wlan*` device
   is *the* adapter and belongs at the single literal name `wlan0`.

   Traced rather than assumed, here is what that actually does. With a first
   adapter already holding `wlan0`, `SIOCSIFNAME` on the second (`wlan1`)
   device fails `EEXIST`; `rename_netif_dev_fromname_toname()` logs `Error
   changing net interface name` (`udev-event.c:874-875`) and returns < 0;
   `udev_event_execute_rules()` logs one `could not rename interface …`
   warning (`:1008-1010`) and **skips** `udev_device_rename()`; the device
   keeps its kernel name `wlan1`, which still matches the `auto wlan1`
   stanza. So reproducing stock's `NAME=` would be a per-event failed-rename
   warning for zero benefit — not a renaming catastrophe. Reason 2 is the
   load-bearing one.

   It is **not** harmless in general, and that is worth recording because it
   is one Kconfig symbol away: eudev's collision-avoidance machinery (rename
   to `rename_%s`, then to `<base><128-ifindex>`, retrying for 90 s —
   `udev-event.c:829-873` and `:948-1001`) genuinely would produce a name
   matching *neither* `auto` stanza. It is compiled **out** here —
   `output/build/eudev-3.2.14/config.h:5` is
   `/* #undef ENABLE_RULE_GENERATOR */`, because `output/.config:1447` has
   `# BR2_PACKAGE_EUDEV_RULES_GEN is not set` and
   `work/buildroot/package/eudev/eudev.mk:40-44` therefore passes
   `--disable-rule-generator`. Anyone who enables that symbol converts
   stock's `NAME=` from "noisy no-op" into a real two-adapter regression.
   Not renaming at all is correct under either setting.
2. **It is a no-op on this hardware's actual USB topology, so there is
   nothing to gain by adding it back.** eudev's `net_id` builtin
   (`output/build/eudev-3.2.14/src/udev/udev-builtin-net_id.c`) only
   populates `ID_NET_NAME_ONBOARD`/`_SLOT`/`_PATH` — the only properties
   `80-net-name-slot.rules` consults — via `names_pci()`, which requires a
   PCI ancestor anywhere in the device's parent chain
   (`net_id.c:276-294`, `udev_device_get_parent_with_subsystem_devtype(dev,
   "pci", NULL)`; falls straight to `goto out` with nothing set if none
   exists). The DE10-Nano's two USB controllers are memory-mapped platform
   devices, not PCI: `output/build/linux-6.18.40/arch/arm/boot/dts/intel/
   socfpga/socfpga.dtsi:940` (`usb0: usb@ffb00000 { compatible =
   "snps,dwc2"; }`) and `:953` (`usb1: usb@ffb40000`, same compatible) — this
   SoC has no PCI bus at all. So a USB WiFi dongle here never gets a
   predictable-name property in the first place, and `80-net-name-slot.rules`
   is a permanent no-op for it regardless of what our rule does. This matches
   the hardware-verified behaviour already on record in commit `4cf2fc7`
   ("RTL8822BU auto-connects WPA3 5GHz at boot" via the plain `wlan0` stanza,
   no rename involved) and the hardcoded `ifup wlan0` / `ip link set wlan0`
   in Scripts_MiSTer's `other_authors/wifi.sh` (§2 table above, lines 133-134
   of this file; `wifi.sh:36-42`) — both already assume the kernel-assigned
   name is the name that sticks.

### Divergence 2 — targeted, asynchronous `RUN+=` instead of `ifup -a`

**When this rule actually runs, verified against `S10udevd`.** `S10udevd`
coldplugs every device already present at boot — `udevadm trigger
--type=devices --action=add`, `package/eudev/S10udevd:42` (`:41` is the
`--type=subsystems` trigger; `:42` is the devices one) — so the "add" uevent
for a boot-time-present `wlan0`/`wlan1` fires during ordinary startup, not
only on post-boot insertion. It does **not** run in parallel with
`S40network`, though: `S10udevd:43` then runs
`udevadm settle --timeout=$SETTLE_TIMEOUT` (`SETTLE_TIMEOUT=30`,
`S10udevd:22`), which blocks `rcS` until udev's event queue drains. The rule
therefore completes *inside* `S10udevd`, several init scripts **before**
`S40network` starts. What races `S40network`'s `ifup -a` is the *detached*
`ifup` the helper leaves behind.

**That overlap is safe, verified against the actual mechanism, not just
argued.** `ifupdown` itself serializes and de-duplicates:

- `lock_interface()` (`output/build/ifupdown-0.8.44/main.c:189-230`) takes an
  exclusive **POSIX record lock** — `struct flock lock = {.l_type = F_WRLCK,
  …}` at `main.c:203`, `fcntl(fd, F_SETLK, &lock)` at `:205` with a blocking
  `fcntl(fd, F_SETLKW, &lock)` fallback at `:208`. It is **not** `flock(2)`:
  grep the whole `ifupdown-0.8.44` tree and there is no `flock()` call in it.
  The lock file is per-interface, under `RUN_DIR` (`"/run/network/"`,
  `header.h:100` — tmpfs per `etc/fstab`, so it is writable even while `/`
  itself is still read-only at boot, ADR 0011's mechanism), and the recorded
  state is read only **after** the lock is acquired (`main.c:217-226`).
- The lock is held for the entire up-sequence and released only at function
  exit (`main.c:1439-1440`); the state file is written near the *start* of a
  successful `up` (`main.c:1206`), while still holding the lock.
- A second `ifup` for the same interface blocks in `F_SETLKW`, and once
  unblocked sees the state the first invocation already wrote — taking the
  no-op path (`"interface %s already configured"`, `main.c:1140-1148`)
  instead of launching a second `wpa_supplicant`.

Whichever of the two racing invocations wins, exactly one `wpa_supplicant`
ends up running. (One pre-existing, out-of-lane behaviour this makes newly
*reachable* rather than introduces: `post-down killall -q wpa_supplicant` in
each `/etc/network/interfaces` stanza kills **every** `wpa_supplicant`
process, not just the one for the interface being brought down — so
unplugging one dongle while a second is associated will also kill the
second's `wpa_supplicant`. This is existing `interfaces` file behaviour
(P2.3/v9), not something T2 changed; flagged here because hotplug `ifdown` is
the first caller that can trigger it without a human at the console.)

**Targeting `%k` instead of stock's `-a`, and going through
`etc/wifi-hotplug.sh` instead of calling `ifup`/`ifdown` directly, are the
same fix for one root cause.** Each `wlan0`/`wlan1` stanza's `pre-up` loop
polls `iw dev $IFACE info` for up to 20s while the driver finishes
registering the `nl80211` interface (§1 table, v9 change). `ifup -a` brings
up every `auto` stanza, so plugging in **one** dongle (say `wlan0`) would
also run `ifup wlan1` if `wlan1` is configured but has no device present —
20 wasted seconds waiting for a device that will never appear, on every
single-dongle hotplug. Naming the interface that actually fired (`%k`, which
— per Divergence 1 — is also its permanent name) avoids that.

**The boot path had the identical bug, and needed its own fix.** `%k` only
narrows the *hotplug* caller; `S40network` still runs a literal `ifup -a`, so on
every boot of a single-dongle box the `wlan1` stanza polled its full 20 s for a
device that will never appear — with `S41dhcpcd`, `S49ntp`, `S50sshd` and
Main_MiSTer all serialised behind it in `rcS`. Measured, not estimated: running
the stanza's exact loop against an absent interface takes 20 s. The fix is a
`pre-up [ -e /sys/class/net/$IFACE ]` guard ahead of the loop in each stanza
(§1 table). It is safe precisely *because* this rule exists: a dongle that is
merely slow rather than absent still gets its `add` uevent, and this rule fires
on udev's boot-time coldplug (`S10udevd`'s `udevadm trigger`) as well as on
later insertion, so bring-up for a late device is event-driven rather than
polled. The v9 loop stays behind the guard as a cheap safety net for the narrow
case it was written for — netdev present, `nl80211` not yet ready.

**Why the detach matters is a boot-time regression avoided, not hygiene.**
`udevadm settle --timeout=30` (`S10udevd:43`, above) waits on precisely the
event this rule creates. A non-detached `RUN+=` would hold that event open
for the whole bring-up — the ≤20 s `iw dev` `pre-up` loop plus the stanza's
own `post_up sleep 2` — so **every** boot with WiFi hardware present would
stall `rcS` for >20 s, and any event chain that exceeds 30 s makes `settle`
give up and print `udevadm settle failed` before continuing. Detaching keeps
the udev event short and moves the wait off the boot path entirely.
Secondarily, it frees the worker: occupancy stacks, since a hub with two
dongles fires two concurrent "add" events.

What the detach is *not* is a rescue from the event timeout: eudev's default
per-event timeout is 180 s
(`output/build/eudev-3.2.14/src/udev/udevd.c:72`,
`arg_event_timeout_usec = 180 * USEC_PER_SEC`; unmodified by `etc/udev/
udev.conf` or `package/eudev/S10udevd` in this image), so a 20 s wait would
never have been killed. `etc/wifi-hotplug.sh` does it with `setsid` +
redirected std fds + background `&` — `setsid` verified present as a real
util-linux binary (`output/target/usr/bin/setsid`, an ARM ELF;
`board/mister/de10nano/busybox.fragment`'s `# CONFIG_SETSID is not set`
disables BusyBox's applet specifically because util-linux's wins, listed in
the defconfig's `BR2_PACKAGE_UTIL_LINUX_BINARIES` comment). The redirections
are load-bearing rather than cosmetic in this build: at the shipped udev log
level (`src/shared/log.c:42` defaults `log_max_level` to `LOG_INFO`, and
nothing lowers it — `output/target/etc/udev/udev.conf:6` leaves
`#udev_log="info"` commented, `S10udevd:23` passes `UDEVD_ARGS=""`, and the
cmdline at `docs/boot-chain.md:323` carries no `udev.log-priority=`)
`udev_event_spawn()` creates **both** pipes (`udev-event.c:726`, `:733` —
the `log_get_max_level() >= LOG_INFO` disjunct is true even though `RUN+=`
passes `result == NULL` at `:1087`) and `spawn_read()` (`:787`) epoll-loops
until every writer closes. A backgrounded grandchild still holding a write
end would block the worker for the full bring-up regardless of the `&`. See
`etc/wifi-hotplug.sh`'s own header for the full trace.

### Kept identical to stock

`SUBSYSTEM=="net"`, the `DRIVERS=="?*"` guard, `KERNEL=="wlan*"`, and the
remove rule addressing the interface by `%k` (stock's remove rule never had
the `NAME=` problem — it always used the kernel name).

### Verified present in this image (not assumed)

`output/target/usr/sbin/ifup` — a 72536-byte ARM ELF;
`output/target/usr/sbin/ifdown` → `/usr/sbin/ifup` (same binary, dispatches
on `argv[0]`). `output/target/sbin` is itself a symlink to `usr/sbin`
(`BR2_ROOTFS_MERGED_USR=y`), so stock's `/sbin/ifup` and `/sbin/ifdown`
spellings resolve to those same two entries. `output/target/usr/sbin/iw` — a
264720-byte ARM ELF, from `BR2_PACKAGE_IW=y` at
`configs/mister_de10nano_defconfig`; without it the `pre-up` loop's
`iw dev` would be a permanent 20 s no-op.

### Verify-on-hardware (adds to §5's checklist)

- **[HW]** Plug a WiFi dongle in **after** boot with a
  `/media/fat/linux/wpa_supplicant.conf` already staged: confirm the
  interface associates without a reboot (`dmesg`/`iwgetid -r`/DHCP lease),
  within the pre-up loop's ≤20s window.
- **[HW]** With two dongles: boot with one attached (gets `wlan0`), then hot
  plug the second (should register as `wlan1`, per the kernel's own
  sequential numbering, and come up automatically without disturbing the
  first).
- **[HW]** Unplug a dongle: confirm `ifdown` runs (`wpa_supplicant` for that
  interface stops, `dmesg` shows the "remove" uevent processed) and — per
  the flagged pre-existing behaviour above — confirm/record whether a second,
  still-associated adapter's `wpa_supplicant` also gets killed by the shared
  `killall -q wpa_supplicant` in `post-down`.
- **[HW]** Boot with WiFi hardware already attached: confirm no double
  `wpa_supplicant` (e.g. `pgrep -c wpa_supplicant` == number of configured,
  present interfaces) despite `S40network` and the udev coldplug both firing
  `ifup` for the same interface.
- **[BUILD]** `scripts/ci-tests.sh` asserts, against `rootfs.tar`: both
  `etc/udev/rules.d/70-persistent-net.rules` and `etc/wifi-hotplug.sh` are
  present; the rule file's mode is exactly `-rw-r--r--` (644 — udev must read
  it, nothing should execute it); and the script is executable (any `-r?x`
  mode, since `RUN+=` `exec`s it directly and udev does not go through a
  shell). It does **not** pin the script to exactly 755.

---

## 10. AIC8800 (stock 6.18, 2026-09-11) — deferred by owner decision D2

Stock's `MiSTer-v6.18` fork HEAD, commit `c129b0fac34ad5d613bbec3f59d6036775e41c83`
("Add AIC8800 WiFi/BT driver.", Sorgelig, 2026-09-11), added an out-of-tree AIC8800
Wi-Fi/Bluetooth combo driver — the RivieraWaves "rwnx" fullmac driver as re-badged by
AICSemi, 142 files / 82,330 insertions across `drivers/net/wireless/aic8800/`. Full
analysis: [`docs/kernel-recon/fork-sync-2026-09/memo-Q9-aic8800.md`](kernel-recon/fork-sync-2026-09/memo-Q9-aic8800.md).
**Owner decision D2 (2026-09-11): defer — no package.** This image does not carry it.

### Why defer, not package or decline

The technical objection is gone: both kernel modules (`aic8800_fdrv`, `aic_load_fw`)
**compile and modpost clean for 32-bit ARM** — zero errors, zero warnings, 206,828 bytes
of `.ko.xz` — and the driver passes the ADR 0016 admissibility test cleanly (mainline has
no AIC8800 HAL, no staging entry, no `MAINTAINERS` line, in any of the three trees this
increment checked; zero USB-ID bind conflicts against the 46 VID:PIDs the two modules
claim, checked one-by-one against `drivers/net/wireless/`, `drivers/bluetooth/`,
`drivers/usb/` and `drivers/net/usb/`).

The **supply objection is decisive and unresolved**:

- **No firmware, and no way to source it.** The driver reads roughly 60 firmware blobs
  from `/lib/firmware` at runtime, none of which exist in upstream `linux-firmware`, in
  this project's pinned tree, or — checked directly for this increment — in **stock's own
  Release 20260907 `firmware.tar.gz`** (89 files, none of them `fmacfw_*`/`fw_patch_*` or
  any other AIC-matching name; see
  [`docs/kernel-recon/fork-sync-2026-09/evidence/stock-20260907-firmware.txt`](kernel-recon/fork-sync-2026-09/evidence/stock-20260907-firmware.txt)).
  A package built today would ship a `.ko` that probes, fails at `request_firmware()`, and
  never brings an interface up — precisely the "driver without firmware reads as broken
  hardware" failure mode this document's §6 exists to prevent, except with **no known fix**
  rather than a one-line Buildroot sub-option.
- **No license.** 51 of 139 vendor source files carry neither a copyright line nor a
  license grant; where a license does appear it is a bare `MODULE_LICENSE("GPL")` comment
  with no accompanying `LICENSE` file for a Buildroot package's `*_LICENSE_FILES` to point
  at; 2 files are Apache-2.0 (GPLv2-incompatible) mixed into an otherwise-GPL tree. The
  vendor tree also carries no identified upstream repository to pin by commit SHA — the
  fork's copy is an SDK snapshot with no `README`, no supported-kernel-range statement, and
  no maintainer contact.

Both blockers are answerable in principle — identify the real upstream repository and its
firmware distribution — and neither needs hardware to resolve, which is why this is a
**defer**, not a decline: declining now would mean amending ADR 0016's "mainline can't
drive this chip" admissibility ground (which AIC8800 satisfies, same as `rtl8852cu` did),
not applying it.

### Hardware this leaves uncovered

Resolved from the driver's own `#define`s (`aicwf_usb.h`), the most concrete demand
signal available without shipping anything: **Tenda U2** (`2604:0014`), **Tenda U11**
(`2604:001f`), **Tenda U11 Pro** (`2604:0020`), and **Tenda TX1U Nano** (`3625:0110`) —
commodity ~£10 Wi-Fi 6 (AX) USB dongles with no driver anywhere in this image today (the
§4/§7 audits above cover every mainline USB Wi-Fi driver and none claims these IDs). A
MiSTer user who buys the current cheapest AX dongle on the market gets nothing from either
stock's 6.18 kernel or this image.

### What would unblock it

Per the memo's stated re-open trigger: **either** (a) stock's own `firmware.tar.gz` gains
`fmacfw_*`/`fw_patch_*`-style entries in a future release (cheap to re-check: one `tar tzf`
against a new release, same evidence-list method this increment used), **or** (b) someone
identifies the real upstream repository for this vendor tree and confirms it carries both
a license file and the firmware blobs, redistributable. Either would turn packaging
`package/aic8800` + a firmware package into a mechanical exercise — the hard technical
question (does it build) is already answered — modelled on `package/rtl8852cu-morrownr/`,
with the caveats the memo records for a future implementer: the two-module build needs
ordered `M=` passes (`aic8800_fdrv` will not modpost without `aic_load_fw`'s
`Module.symvers`), and hardware verification is still needed that the two modules' six
overlapping USB IDs (disambiguated by interface class, not PID, for three of the six)
don't race during the ROM-bootloader-to-application-firmware re-enumeration handoff.

**Out-of-tree WiFi driver count in this image is unaffected: still one**
(`package/rtl8852cu-morrownr`, §8). AIC8800 is not packaged, so it does not change that
count, and stock does not ship it either (`c129b0fac` is on the fork's `MiSTer-v6.18`
branch, ahead of Release 20260907's build point — stock's own shipped `modules.tar.gz`
evidence has **no** `aic8800*.ko.xz`, confirmed against
[`evidence/stock-20260907-modules.txt`](kernel-recon/fork-sync-2026-09/evidence/stock-20260907-modules.txt)).

### Update 2026-09-10 — the memo's open questions, answered (decision unchanged)

Memo Q9 was written without network access and deferred three checks to "a human with
network access". They were run on 2026-09-10; full write-up in
[`memo-Q9-aic8800.md`](kernel-recon/fork-sync-2026-09/memo-Q9-aic8800.md) §9. **Owner
decision D2 (defer, no package) stands** — nothing found flips it — but three facts are now
settled and one new packaging trap was discovered.

1. **Stock still ships nothing, so stock's driver is inert too.** The fork's
   `MiSTer-v6.18` HEAD is *still* `c129b0fac3`, with no follow-up firmware commit on any
   ref. `MiSTer-devel/Linux_Image_creator_MiSTer` — where `firmware.tar.gz` actually lives
   — has its newest commit at `d4e3f51ec` "Release 20260907." (2026-09-07), which
   **pre-dates** the driver commit. "Stock added AIC8800" means stock added the *source*;
   no stock release carries the module or the blobs. We are not behind stock in any way a
   user can observe.
2. **`linux-firmware` definitively does not carry it.** Zero hits for
   `aic8800|aicsemi|fmacfw|rwnx` in our pinned `linux-firmware-20260410/WHENCE` and in
   upstream `kernel-firmware/linux-firmware` at `main`; no `aic8800/` directory in either.
   Expected — mainline has no driver to `request_firmware()` it — and it closes
   `package/linux-firmware` sub-options as a route.
3. **The vendor snapshot is identified; D80 firmware is public; the licence question is
   not resolved.** `goecho/aic8800_linux_drvier` matches the fork byte-for-byte on
   `RWNX_VERS_REV "1a4b0054d2M (master)"` / `RWNX_VERS_MOD "6.4.3.0"` and ships
   `fw/aic8800D80/` containing every blob the Tenda U11/U11 Pro path needs. But its
   repo-level `LICENSE` is MIT over sources that declare `MODULE_LICENSE("GPL")` and
   include Apache-2.0 files — a repackager's grant, not the vendor's, which makes the §1.3
   provenance claim *less* defensible rather than more. Coverage is also D80 only (9 files
   vs ~60); the 8800DC blobs live in a different stranger's repo again. (`radxa/aic8800`,
   the memo's first-choice candidate, is a 404.)

**New finding — firmware layout.** `CONFIG_USE_FW_REQUEST` is `n` in both module Makefiles,
so the driver bypasses the kernel firmware loader entirely and `filp_open()`s a path it
builds itself, appending a **per-chip subdirectory** in both bring-up stages
(`aic_load_fw/aicbluetooth.c:320-337` and `aic8800_fdrv`'s per-variant `strcat`s). The
blobs must therefore live at **`/lib/firmware/aic8800D80/…`**, not flat in
`/lib/firmware/`. Dropping them flat — which is what `package/linux-firmware-extra` and
every other firmware in this image does — produces a driver that still fails, silently,
logging only `firmware path = /lib/firmware/fmacfw_8800d80_u02.bin`. Any future
`package/aic8800-firmware` must honour the subdirectory; if a stock release ever ships
these blobs flat, that is a stock bug, not a layout to mirror.

**Cheapest unblock path, restated:** wait for a stock release whose `firmware.tar.gz`
carries the AIC blobs, then mirror them the way `package/linux-firmware-extra` mirrors
`linux-firmware` (subject to the layout requirement above). That reduces the licence
question to the redistribution posture this image already accepts for every other blob it
ships. Waiting costs nothing, because stock's driver does not work until that happens
either. **Re-check trigger:** more than one `-i --grep=aic` hit in the fork, or any new
`Linux_Image_creator_MiSTer` commit after `d4e3f51ec`.

---

## 10.1 AIC8800 — decision D2 REVERSED, packaged (2026-09-10)

**Owner decision, 2026-09-10: package it, licence ambiguity and all.** The reasoning is
recorded here because it overrides what §10 above says, and §10 is left standing as the
analysis that produced the original defer.

Two things moved the decision, neither of them a resolution of the §10 blockers:

1. **Stock is clearly heading for shipping the chip.** Sorgelig did not add 82 k lines to
   his kernel fork speculatively. Waiting for his `firmware.tar.gz` (§10's recommended
   path) means our users have no driver for as long as he takes, for no benefit — and
   §9.1 of the memo establishes he has shipped nothing yet, so "wait for stock" had no
   visible end date.
2. **Resellers bundle these dongles.** A MiSTer bought as a kit can arrive with an
   AIC8800 stick in the box. That turns "unsupported cheap dongle" into "the WiFi that
   came with the machine does not work", which is a materially worse failure than the
   one §10 was protecting against.

### What changed technically since §10 was written

§10's two blockers were *firmware supply* and *licence*. The first is genuinely solved;
the second is accepted rather than solved.

**Firmware: solved, from a source §10 did not find.** The memo looked for
`radxa/aic8800` and got a 404. The actual repository is **`radxa-pkg/aic8800`** (210
stars, org-maintained, tagged releases, last pushed 2026-09-02), and it is a match on
the exact string §10 said to grep for:

| | `RWNX_VERS_REV` | `RWNX_VERS_MOD` | `RELEASE_DATE` |
|---|---|---|---|
| stock `c129b0fac3` | `1a4b0054d2M (master)` | `6.4.3.0` | `2026_0123_5f7be68d` |
| `radxa-pkg` `516e3b08` | `1a4b0054d2M (master)` | `6.4.3.0` | `2026_0123_5f7be68d` |

Its own release tags spell out the same stamp (`5.0+git20260123.5f7be68d-8`). File
inventories match too — 111/110 in `aic8800_fdrv`, 24/23 in `aic_load_fw`, the difference
being the `.gitignore` stock added when vendoring. **So the chip coverage we ship is the
chip coverage stock ships**, including the newer 8800D80N / 8800D80X2 / 8800DLN variants
that the other public mirrors (`goecho/aic8800_linux_drvier` and friends) predate.

And it ships **all six firmware variant directories** — `aic8800`, `aic8800D80`,
`aic8800D80N`, `aic8800D80X2`, `aic8800DC`, `aic8800DLN`, 84 files, 6.6 MiB — in exactly
the per-chip layout §9.4 established the driver requires.

**Licence: accepted, not resolved.** `debian/copyright` is the most authoritative
statement that exists ("Files: src/* — License: GPL-2"; the packaging is GPL-3+), and
`AIC8800_LICENSE_FILES` points at it rather than the repo's top-level GPL-3 `LICENSE`,
which would misdescribe the driver. Underneath that the §1.3 findings are unchanged:
many vendor files carry a bare copyright line with no grant, two are Apache-2.0 in an
otherwise-GPL tree, and there is no upstream AICSemi repository — every public copy is a
re-published SDK drop. The firmware blobs have no licence text of their own and are
redistributed on the same footing as `xow_dongle.bin` (ADR 0003) and
`BCM20702A1-0b05-17cb.hcd` (`package/bcm20702-firmware`). This is recorded rather than
fixed, because it cannot be fixed from outside AICSemi.

### The vendor patch series — load-bearing, and partly skipped

`radxa-pkg` ships the **raw** SDK under `src/` and applies its own quilt series from
`debian/patches/` at build time. `package/aic8800` does the same in a `POST_EXTRACT`
hook. This is not cosmetic:

> **The pristine tree does not build on 6.18.** Measured, as a control:
> `rwnx_main.c:6430: error: initialization of 'int (*)(struct wiphy *, struct
> wireless_dev *, int, unsigned int, int *)' from incompatible pointer type` — the
> cfg80211 `get_txpower` op gained `radio_idx`/`link_id` in 6.17.
> `fix-linux-6.17-build.patch` is what fixes it.

**How stock gets away without the series:** it doesn't need it — stock's vendored copy is
already pre-merged. Sorgelig's `rwnx_main.c` carries **186 `LINUX_VERSION_CODE` guards**
covering 6.17, 7.1 and 7.2, with `radio_idx` appearing three times behind three 6.17
guards. He took his copy from a tree that had the fixes folded in; radxa keeps them
separate. Same destination, different packaging — and our copy ends up marginally
*ahead*, because radxa also carries `fix-linux-6.19-build.patch` (stock has no 6.19
guard) and USB disconnect-callback hardening stock lacks.

Four patches are **deliberately skipped**, and only these four:
`fix-{usb,sdio,pcie}-firmware-path.patch` and `fix-sdio-per-chip-firmware-path.patch`.
They relocate firmware into Debian's `/lib/firmware/aic8800_fw/{USB,SDIO,PCIE}/` layout;
we keep the vendor default `/lib/firmware/<variant>/`, which is what stock's in-kernel
copy uses. `AIC8800_CHECK_FW_PATH` asserts that outcome after patching, so a reshuffled
series that moves the path fails the build closed instead of silently installing blobs
where nothing looks.

One more wrinkle worth recording: four vendor files under `aic_load_fw/` ship **CRLF**
while every radxa patch is LF, and plain `patch` rejects those hunks (`patch -l` does not
rescue it). Left alone that silently loses the debug-log-level reduction, leaving
`aic_load_fw` at `LOGERROR|LOGINFO|LOGDEBUG|LOGTRACE` — a dmesg flood on every hotplug.
The package normalises the tree to LF first, after which all 23 non-skipped patches apply
with zero fuzz.

### Verified

Built against the **pinned 6.18.50** (not the stale 6.18.49 in `output/`), `ARCH=arm`,
the image's own gcc 14.4 toolchain:

| | |
|---|---|
| vendor series | `applied=23 skipped=4 failed=0` |
| build | exit 0, **0 errors**, 15 warnings (9 fall-through, 5 `-Wrestrict`, 1 unused label — all vendor code) |
| modules | `aic_load_fw.ko` + `aic8800_fdrv.ko` |
| image cost | **194,112 bytes** of `.ko.xz` (165,800 + 28,312) + 6.6 MiB firmware |
| firmware path after patching | `/lib/firmware` (vendor default, asserted) |
| debug level | `LOGERROR` in both modules |

**Install layout — the one genuinely surprising thing.** This package's `M=` directory is
the *parent* of two module subdirectories, so `modules_install` writes
`updates/aic_load_fw/aic_load_fw.ko.xz` and `updates/aic8800_fdrv/aic8800_fdrv.ko.xz` —
**not** the flat `updates/<name>.ko.xz` every other out-of-tree package here produces.
Measured with a real `modules_install`, and `scripts/ci-tests.sh` asserts the nested
paths; an assertion written to the flat shape would fail forever.

### Still not done

- **No hardware test.** Nobody has plugged an AIC8800 dongle into a MiSTer. §4's
  two-module USB-ID race (six IDs shared between `aic_load_fw` and `aic8800_fdrv`,
  disambiguated by interface class for three of them) is unchanged and not closable by
  reading source.
- **DE10 only.** `BR2_PACKAGE_AIC8800=y` is in `de10nano-image.fragment`, not
  `image-common.fragment`, because the modules have only been built for 32-bit ARM. A
  DE25 enablement needs an aarch64 build first; radxa builds this driver for arm64
  Rockchip targets, so it is expected to work, but expected is not measured.
- **Not in the kernel export.** `scripts/export-kernel-tree.sh` lists `aic8800` in
  `MODULE_EXPORT_SKIP`: stock already vendors its own copy at the same path, so exporting
  ours would collide and offer upstream something it has. It would also need the exporter
  to learn `MODULE_SUBDIRS` and the patch series, which nothing else there uses.

---

## 11. The deselected Realtek fork packages were deleted (2026-09-10)

Seven packages — `rtl8188eu-aircrack-ng`, `rtl8188fu`, `rtl8812au`, `rtl8814au-morrownr`,
`rtl8821au-morrownr`, `rtl8821cu-morrownr`, `rtl88x2bu` — were removed from the tree.

**Why they existed:** §6.4 and ADR 0016's v9/v10 updates moved every one of their chips
onto an in-kernel driver (`rtl8xxxu` for 8188eu/8188fu/8710bu, `rtw88_8821cu`,
`rtw88_8822bu`, `rtw88_8812au`, `rtw88_8821au`, `rtw88_8814au`). The packages were kept
anyway, sourced but permanently `# ... is not set`, as a "one-line revert" fallback if a
mainline driver ever disappointed on specific hardware.

**Why they are gone:** the fallback was never used, and each package was not free. Every
one carried a Renovate custom manager raising PRs for a driver the image does not build,
an entry in `renovate-hash-sync.yml`'s `HASH_SYNC_PACKAGES`, a path filter in that same
workflow, a row in `scripts/export-kernel-tree.sh`'s `MODULE_PATH`, and a `.hash` file to
keep current. Owner decision, 2026-09-10: the Renovate noise is a real ongoing cost and
the fallback is imaginary.

**The fallback still exists, in git.** A `--diff-filter=D` log over
`package/rtl8812au/` restores any of them complete with their pins, hashes and patches.
That is a better fallback than a permanently-disabled package, because it cannot silently
rot.

### The deletion criterion, and the measurement that satisfies it

The rule applied was narrow: **delete only a package whose chips are now fully driven by
vanilla Linux**; keep anything that might still add value. "Fully driven" was measured,
not assumed, because §6.4's subset proof covered only the 88xxa pair (8812au/8821au) and
the same question was open for the other five.

Method: extract each fork's USB ID table at its pinned commit, and compare against the IDs
the image *actually builds* — taken from the modalias strings of the built `.ko` files in
the pinned 6.18.50 tree, not from a source grep, so it reflects exactly which `CONFIG_*`
are enabled. The image claims **972 distinct USB IDs across 85 built wireless/BT modules**.

| Deleted package | IDs in its table | Claimed by nothing the image builds |
|---|---:|---:|
| `rtl8188eu-aircrack-ng` | 39 | **0** |
| `rtl8188fu` | 1 | **0** |
| `rtl8812au` | 44 | **0** |
| `rtl8814au-morrownr` | 66 | **0** |
| `rtl8821au-morrownr` | 55 | **0** |
| `rtl8821cu-morrownr` | 31 | **0** |
| `rtl88x2bu` | 31 | **0** |

**Every ID every one of them claimed is claimed by a module this image builds.** Nothing
is lost, for any dongle, by any of the seven deletions.

`rtl8188fu` is worth a note because it nearly escaped the audit: its table does not use
the `USB_DEVICE(0x…, 0x…)` shape the other six do, so a regex written for them extracted
zero IDs and reported "inconclusive" rather than "covered" — the right failure, but only
because the script distinguished the two. It carries exactly **one** entry,
`USB_DEVICE_AND_INTERFACE_INFO(0x0BDA, 0xF179, …)`, and `rtl8xxxu.ko` claims `0bda:f179`
(it links `8188f.o`, confirmed in the built tree alongside `8188e.o`, `8710b.o` and the
rest). If you re-run this audit, do not trust a zero-ID extraction as a pass.

**What this changes elsewhere:**

| Where | Before | After |
|---|---|---|
| `package/` | 22 packages | 15 |
| `renovate.json` custom managers | 24 | 18 (7 removed, `aic8800` added) |
| `HASH_SYNC_PACKAGES` | 15 entries | 9 |
| `Config.in` WiFi menu | 8 sourced, 1 enabled | 2 sourced, 2 enabled |
| `de10nano-image.fragment` | 6 `is not set` + 1 `=y` | 2 `=y` |
| out-of-tree WiFi drivers built | 1 | 2 |

`scripts/ci-tests.sh` keeps its "redundant out-of-tree forks must not come back"
assertion for 8812au/8821au even though the packages are gone: the bind-fight it guards
against does not need a Buildroot package to happen — vendoring into
`board/mister/de10nano/linux-patches/` or restoring from git history reaches it too.

## 12. Coverage audit — what is still missing after AIC8800 (2026-09-10)

Method: enumerate every chip family under `drivers/net/wireless/` in the pinned
**6.18.50** tree that has a USB bus file, then check the plausible cheap-dongle chipsets
against it by name in both the `rtl*` and `rtw*` spellings mainline uses. (A first pass
searching only `rtl*` produced false negatives — mainline calls these files `rtw8814au.c`,
not `rtl8814au.c`. Worth knowing before re-running this. A second trap: grepping a built
kernel tree without `--include` filters matches `.cmd` build artefacts and reported 1197
bogus `aic8800` hits against a tree that has none.)

**`rtw89` chip HALs with no USB bus file** — the shape of the RTL8852CU gap:

| HAL | USB | PCIe |
|---|---|---|
| `rtw8851b` | yes | yes |
| `rtw8852a` | **no** | yes |
| `rtw8852b` | yes | yes |
| `rtw8852c` | **no** | yes |
| `rtw8922a` | **no** | yes |

`rtw8852c` is the gap `rtl8852cu-morrownr` fills. `rtw8852a` and `rtw8922a` are PCIe-only
HALs for parts that are not sold as USB dongles in any volume (RTL8922A is Wi-Fi 7 and
currently a laptop/M.2 part); this board has no PCIe, so neither is reachable regardless.

**Chips with no mainline driver at all:**

| Chip | Status |
|---|---|
| AICSemi AIC8800 family | **now shipped** (`package/aic8800`) |
| RTL8852CU / RTL8832CU | **shipped** (`package/rtl8852cu-morrownr`) |
| **RTL8733BU / RTL8731BU** | **real gap — not acted on, see below** |
| SSV6051 / SSV6155, ESP8089, BCM43143 | no driver, and not USB dongle parts (SDIO, embedded in cheap tablets/SBCs) — out of scope |

**RTL8733BU is the one genuine remaining gap, and it is a weak candidate.** It is a
Wi-Fi 5 1x1 part; mainline has nothing for it in any spelling. But every out-of-tree
driver is an individually-maintained low-star fork (`libc0607/rtl8733bu-20230626` 8
stars, `OpenIPC/realtek-wlan` 9, `wirenboard/rtl8733bu` 4; **no morrownr fork exists**),
with no tagged releases and no vendor-org packaging. That is far weaker provenance than
either driver this image ships — `radxa-pkg/aic8800` is an org with tagged releases and
210 stars, and morrownr is the established Realtek fork maintainer. The chip also shows
up mainly in FPV modules rather than the retail dongle aisle, so the demand argument that
carried AIC8800 (§10.1) does not transfer.

**Recommendation: leave it.** Revisit if either a morrownr fork appears or a user reports
the chip. Everything else a MiSTer user is likely to buy — Realtek 8188/8192/8812/8814/
8821/8822/8852B/8851B, MediaTek MT7601U/MT76x0/MT76x2/MT7663/MT7921/MT7925, Broadcom
FullMAC, Ralink rt2x00, Marvell mwifiex — is driven in-kernel today.
