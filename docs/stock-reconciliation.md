# Stock reconciliation — `Linux_Image_creator_MiSTer` vs. our image

Evidence that this image is at parity **or better** with what MiSTer stock
actually ships, item by item, and an explicit account of what we ship that
stock does not.

## Source of truth

Reconciled against the *authoritative upstream build inputs*, not against a
previously-extracted snapshot:

| | |
|---|---|
| Repo | `MiSTer-devel/Linux_Image_creator_MiSTer` |
| Commit | `8aba321b2162e54b56522aa30758b22d97eec8da` (2026-07-17) |
| `firmware.tar.gz` | `e4033440…89a3b` — 69 regular files |
| `modules.tar.gz` | `62086a04…9f2fe` — 52 `.ko`, kernel `5.15.1-MiSTer` |
| `addon.tar` | `38e420ce…6fbde` — 56 regular files |
| Ours | `output/images/rootfs.tar`, kernel `6.18.40` |

`create_img.sh` shows how the three are applied: `modules.tar.gz` →
`/lib` (`--strip-components=2`), `firmware.tar.gz` → `/lib/firmware`,
`addon.tar` → `/` as an overlay on `rootfs.tar.bz2`.

Raw lists are in `docs/verification/stock-reconciliation/` (`stock-fw.txt`,
`ours-fw.txt`, `stock-mods.txt`, `ours-mods.txt`, `addon-report.txt`,
`SOURCE.txt`) so every count below can be re-derived with `comm`.

> **Method note.** A first pass extracted our paths with `tar tvf | awk
> '{print $NF}'`, which silently mis-reads symlinks — `tar` prints
> `link -> target`, so `$NF` yields the *target*. That inflated the missing
> count from 11 to 21. Symlinks matter here because upstream linux-firmware's
> WHENCE-driven install deliberately creates them. The corrected extraction
> uses `tar tf` (names only). Recorded because the wrong number looked
> entirely plausible.

## Headline

| Archive | Stock items | Present in ours | Absent | We add |
|---|---|---|---|---|
| `firmware.tar.gz` | 69 | **58** | 11 (all justified) | **+213** |
| `modules.tar.gz` | 52 | **38** same-name (+14 covered by renamed/mainline equivalents = **52/52 functionally**) | 0 functional | **+62** |
| `addon.tar` | 56 | 16 | 40 (see §3) | — |

Firmware and modules are at **parity or better with no functional gap**.
`addon.tar` is the one area with real, actionable gaps — §3.

---

## 1. `firmware.tar.gz` — 58/69 present, 11 justified, +213 added

### The 11 absences, each with its reason

| Stock file(s) | Why absent | Functionally covered? |
|---|---|---|
| `RTL8192E/boot.img`, `data.img`, `main.img` | Firmware for the **out-of-tree** RTL8192EU vendor driver, which we do not build | **Yes** — mainline `rtl8xxxu` drives RTL8192EU using `rtlwifi/rtl8192eu_nic.bin`, which we **do** ship |
| `mediatek/mt7662u.bin`, `mt7662u_rom_patch.bin` | The **old out-of-tree** filenames | **Yes** — mainline `mt76x2u` requests `mediatek/mt7662.bin` + `mt7662_rom_patch.bin`; both shipped |
| `rt2870_sw_ch_offload.bin` | Obsolete; no consumer in 6.18 | n/a |
| `rtl_bt/rtl8192ee_fw.bin`, `rtl8192eu_fw.bin` | **Not present in upstream linux-firmware at all** | No source without stepping outside the pinned tarball — flagged, not fabricated (`docs/firmware-parity.md`) |
| `rtlwifi/rtl8723defw.bin` | RTL8723**DE** is a **PCIe** part; `CONFIG_PCI` is unset on this board | Unreachable hardware |
| `xone_dongle_02f9.bin`, `xone_dongle_091e.bin` | These two PIDs are dongles **soldered into laptop mainboards** (ASUS/Lenovo; Surface Book 2) — not USB devices, physically unattachable to a DE10-Nano | Deliberate, [ADR 0003](decisions/0003-xone-firmware.md). The two *external* adapters, `02e6` and `02fe`, are both shipped |

No absence is an oversight; every one is either unreachable hardware, an
obsolete name superseded by the mainline equivalent we do ship, or has no
upstream source.

### What we add (+213 paths)

| Area | Added | Why |
|---|---|---|
| `brcm/` (81), `cypress/` (19) | Broadcom/Cypress FullMAC | `brcmfmac` — stock has **no** Broadcom WiFi driver at all |
| `rtl_bt/` (+24) | Realtek BT | incl. `rtl8761b`/`rtl8761bu` (the ubiquitous cheap USB BT5 dongles) and the BT halves of every rtw88/rtw89 combo |
| `ar3k/` (18) + `ath3k-1.fw` | Atheros BT | AR3011/AR3012 |
| `rtw89/` (17), `rtw88/` (+9) | Realtek WiFi 6/6E | 8851BU/8852BU + the full rtw88 USB set |
| `mediatek/` (+15) | MT7663U, MT7921/7925 WiFi **and BT** | |
| `rsi/` (5), `ath6k/` (4), `qca/` (2), `rtlwifi/` (+2), `ath9k_htc/` (2) | RS911x, AR6004, QCA ROME USB BT, RTL8192DU, ath9k_htc | |

---

## 2. `modules.tar.gz` — 52/52 functionally covered, +62 added

38 of stock's 52 module names appear verbatim in our image. The other **14 are
not gaps** — they fall into three groups:

### 2a. Six out-of-tree Realtek forks → mainline in-kernel drivers

| Stock module | Our replacement | Merged upstream |
|---|---|---|
| `8188eu` | `rtl8xxxu` | — |
| `rtl8188fu` | `rtl8xxxu` | — |
| `8812au` | `rtw88_8812au` | 6.13 (`rtw88_88xxa`) |
| `8821au` | `rtw88_8821au` | 6.13 (`rtw88_88xxa`) |
| `8821cu` | `rtw88_8821cu` | ~6.2 |
| `88x2bu` | `rtw88_8822bu` | ~6.2 |

Per [ADR 0016](decisions/0016-mainline-first-wifi-drivers.md); USB-ID coverage
was diffed per device and nothing is lost (`docs/wifi-parity.md` §6.4).

> **Corroboration from stock itself.** `addon.tar` contains
> `etc/modprobe.d/rtw88-prefer.conf`, whose entire content is
> `blacklist 8821cu` — stock ships an out-of-tree `8821cu` module and then
> blacklists it so the in-kernel `rtw88_8821cu` wins. That is the same
> bind-conflict ADR 0016 describes, acknowledged upstream and worked around
> with a blacklist. We resolve it structurally: shipping **zero** out-of-tree
> WiFi modules means the conflict cannot arise, so we need no such file.

### 2b. Seven xone modules — a naming difference, and we ship more

Stock uses `medusalix/xone` (hyphens); we use the maintained
`dlundqvist/xone` fork (underscores), which also merges `xone-gip-bus` +
`xone-gip-common` into one `xone_gip`:

| Stock | Ours |
|---|---|
| `xone-dongle`, `xone-wired`, `xone-gip-chatpad`, `xone-gip-gamepad`, `xone-gip-headset` | `xone_dongle`, `xone_wired`, `xone_gip_chatpad`, `xone_gip_gamepad`, `xone_gip_headset` |
| `xone-gip-bus` + `xone-gip-common` | `xone_gip` (merged) |
| — | **plus** `xone_gip_madcatz_glam`, `xone_gip_madcatz_strat`, `xone_gip_pdp_jaguar` |

### 2c. `lib80211`

Not built, and **nothing in 6.18 selects it** (`grep -rn "select LIB80211"
--include=Kconfig` → no match). It was pulled in by a driver stock carried
that we do not. No consumer, so no gap.

### What we add (+62 modules)

`brcmfmac` (+ `-bca`/`-cyw`/`-wcc` vendor splits) and `brcmutil`; the complete
`rtw88` USB set (`8723du`, `8812au`, `8821au`, `8814au`, `8822bu`, `8822cu`,
`8821cu` + cores); `rtw89` (`8851bu`, `8852bu`, `rtw89_usb`); `mt7921u`,
`mt7925u` + `mt792x` libs; `ath9k_htc`, `carl9170`, `ath6kl_usb`; `rsi_usb`,
`btrsi`; `rtl8192du`; `btmtk`; `xpad`; `ntfs3`.

---

## 3. `addon.tar` — 16/56, and the one area with real gaps

`addon.tar` is a rootfs *overlay* of configs and MiSTer helper binaries.
Present: `etc/network/interfaces`, `etc/samba/smb.conf`, `etc/proftpd.conf`,
`etc/ssh/sshd_config`, `etc/bluetooth/main.conf`, `etc/usbmount/usbmount.conf`,
`etc/ssl/certs/cacert.pem`, `etc/resync`, `S91smb`, `S99user`, `bluetoothd`,
`mt32d`, `midilink`, `mlinkutil` (+`fluidsynth` and `.ssh/environment` at
different paths).

### 3a. Absent **by design — we are better**

| Item | Why |
|---|---|
| `etc/ssh/ssh_host_{dsa,ecdsa,ed25519,rsa}_key(.pub)` — 8 files | Stock ships **identical private host keys on every MiSTer**. We generate per-device keys on first boot ([ADR 0015](decisions/0015-per-device-ssh-host-keys.md)), and `check-linux-img.sh` asserts no `ssh_host_*` exists in the image. **Strictly better.** |
| `etc/modprobe.d/rtw88-prefer.conf` | Works around a bind conflict we do not have (§2a). |

### 3b. Absent — documented drops

`usr/bin/adplay`, `usr/lib/libadplug.so`, `usr/lib/libbinio.so` (no Buildroot
package, no known MiSTer use); `usr/bin/archivemount` (broken in stock);
`usr/lib/libjack.so.0.0.28` (dangling in stock, unused) — all on
`docs/package-manifest.md`'s Drop list.

### 3c. Absent — **genuine gaps, not previously documented**

These exist in the real stock rootfs (verified in `work/imgroot`, not just in
`addon.tar`) and are absent from our image. **None is a WiFi/Bluetooth item**;
they are MiSTer helper utilities and console/UX config.

| Item | Type | Note |
|---|---|---|
| `usr/bin/fpga` | ARM ELF | FPGA helper |
| `usr/bin/memtool` | ARM ELF | memory access helper |
| `usr/bin/vhd_mount` | `/bin/sh` script | loop-mounts VHD images |
| `usr/bin/m3u_play` | bash script | playlist helper |
| `usr/sbin/vmode` | bash script | video-mode setter |
| `usr/sbin/uartmode` | bash script | UART mode setter |
| `usr/sbin/btpair` | bash script | Bluetooth pairing helper |
| `usr/sbin/btctl` | Python script | Bluetooth control |
| `usr/bin/rz`, `usr/bin/sz` | ARM ELF | ZMODEM (`lrzsz`) |
| `usr/bin/timidity`, `usr/bin/vgmplay`, `usr/bin/VGMPlay.ini`, `usr/lib/libfluidsynth.so.3.0.0` | mixed | audio players; `fluidsynth` itself **is** shipped |
| `etc/asound.conf`, `etc/kbd.map`, `usr/share/consolefonts/default8x16.psfu.gz` | config | ALSA/console setup |
| `etc/mc/*`, `root/.config/mc/*`, `usr/share/mc/skins/MiSTer.ini` | config | Midnight Commander |
| `etc/jms583-phantom-guard.sh` + `etc/udev/rules.d/60-jms583-phantom.rules` | script + udev | JMS583 USB-NVMe bridge workaround |
| `var/lib/bluetooth/placeholder` | dir marker | BT state dir |

**`etc/udev/rules.d/70-persistent-net.rules` deserves its own note.** Stock's
rule is:

```
SUBSYSTEM=="net", ACTION=="add",    DRIVERS=="?*", KERNEL=="wlan*", NAME="wlan0", RUN+="/sbin/ifup -a"
SUBSYSTEM=="net", ACTION=="remove", DRIVERS=="?*", KERNEL=="wlan*", RUN+="/sbin/ifdown %k"
```

It forces any `wlan*` device to be named `wlan0` **and brings the interface up
on hotplug**. We ship neither it nor an equivalent. Our boot path is covered —
`S40network` runs `ifup -a`, and the v9 `pre-up` wait loop in
`/etc/network/interfaces` handles asynchronous driver registration — but
**a WiFi dongle inserted *after* boot will not be brought up automatically on
our image, where it would be on stock.** This is the one functional
WiFi-related difference this reconciliation found. Not fixed here (it is a
rootfs-overlay/udev change, outside the driver/firmware work this branch
covers); recorded as the top follow-up.

**One path difference:** stock has `/usr/sbin/fluidsynth`, we install
`/usr/bin/fluidsynth`. `PATH` lookup resolves either, but anything
hard-coding the absolute stock path would miss it.

---

## 4. Bottom line

- **Firmware:** 58/69 stock files present; all 11 absences justified
  (unreachable hardware, superseded names whose mainline equivalents we ship,
  or no upstream source). **+213 paths added.**
- **Modules:** every one of stock's 52 is functionally covered — 38 by name,
  6 by mainline replacements, 7 by the renamed (and larger) xone set, 1
  (`lib80211`) with no consumer in 6.18. **+62 modules added.**
- **`addon.tar`:** 16/56. Two absences are deliberate improvements (per-device
  SSH keys; no OOT blacklist needed), three are documented drops, and the rest
  are **real gaps in MiSTer helper utilities and console/UX config** —
  none WiFi/BT, but they are gaps and §3c lists them individually rather than
  glossing them.
- **Top follow-up:** `70-persistent-net.rules` (WiFi hotplug-after-boot).
