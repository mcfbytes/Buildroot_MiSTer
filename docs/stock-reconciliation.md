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
| `addon.tar` | 56 | **34 at the stock path** (+5 covered at a different path/mechanism) | 17, **every one a documented decision** (see §3) | — |

Firmware and modules are at **parity or better with no functional gap**.
`addon.tar` was the one area with real, actionable gaps; **T2 and T3 closed
them** — §3c is now a disposition table, not a gap list. The 17 remaining
absences are the deliberate ones: §3a (we are better), §3b (documented drops),
plus two documented declines (vgmplay) and one genuinely sourceless binary
(`fpga`).

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
> with a blacklist. We resolve it structurally for every chip in *this*
> table: shipping **zero** out-of-tree modules for the six chips stock's fork
> covers means the conflict cannot arise for any of them, so we need no such
> file.
>
> **This paragraph predates `rtl8852cu-morrownr` and is otherwise stale —
> corrected, not deleted.** The image now ships **one** out-of-tree WiFi
> module, `8852cu.ko` (RTL8852CU/RTL8832CU Wi-Fi 6E — none of the six chips
> in this section; not a stock module at all, so it does not appear in either
> archive's count above). It does not reopen the bind-conflict this
> corroboration describes: `rtw89` has no in-kernel USB driver for the 8852C
> chip to fight with (`docs/wifi-parity.md` §8, ADR 0016's v10.2 update) — the
> conflict class this paragraph is about only exists where an in-kernel
> driver claims the *same* USB IDs, and here none does. See
> `docs/wifi-parity.md` §8 for the full gap analysis, and note its own honest
> caveat: `8852cu.ko` has been added by source inspection only — **not yet
> built or hardware-tested**.

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

> **+62 is a real build's count, and predates `rtl8852cu-morrownr`.** This
> list (and `docs/verification/stock-reconciliation/ours-mods.txt`, its
> source) was generated from a built `output/images/rootfs.tar` under a
> commit that came before the out-of-tree `8852cu.ko` module existed. That
> module is a genuine 63rd addition-beyond-stock in the same shape as this
> list — a chip stock never shipped a driver for at all — but this document
> does not bump +62 to +63 for it, because that would assert a module count
> from a build that has not been run (`docs/wifi-parity.md` §8: "not built or
> run yet"). Re-run the extraction in
> `docs/verification/stock-reconciliation/SOURCE.txt` after the next real
> build and fold it in then.

---

## 3. `addon.tar` — 34/56 at the stock path, every absence a decision

`addon.tar` is a rootfs *overlay* of configs and MiSTer helper binaries.
Present since before T3: `etc/network/interfaces`, `etc/samba/smb.conf`,
`etc/proftpd.conf`, `etc/ssh/sshd_config`, `etc/bluetooth/main.conf`,
`etc/usbmount/usbmount.conf`, `etc/ssl/certs/cacert.pem`, `etc/resync`,
`S91smb`, `S99user`, `bluetoothd`, `mt32d`, `midilink`, `mlinkutil`
(+`.ssh/environment` at a different path). T2 closed the WiFi hotplug rule;
**T3 closed the rest of §3c** — see the disposition table there.

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

### 3c. Formerly "genuine gaps" — **closed by T3** (disposition per item)

These existed in stock and were absent from our image until T3 (2026-07-27).

**Where stock's bytes were read, precisely.** Most items were cross-checked
against the extracted stock rootfs — `work/imgroot`, from the 2025-04-02
release — and not only against `addon.tar`. **Two items were not, and cannot
be:** `etc/jms583-phantom-guard.sh` and
`etc/udev/rules.d/60-jms583-phantom.rules` do **not** exist in `work/imgroot`
at all (`work/imgroot/etc/udev/rules.d/` holds only
`70-persistent-net.rules`, and `grep -r jms583 work/` returns nothing). They
exist only in the pinned `addon.tar`, which dates both `2026-07-02` — i.e.
they *post-date* the 2025-04-02 release whose rootfs was extracted into
`work/imgroot`, so their absence there is expected rather than a discrepancy.
Their bytes were verified against that archive (`sha256 38e420ce…6fbde`,
pinned in [`SOURCE.txt`](verification/stock-reconciliation/SOURCE.txt); the
archive is **not** unpacked anywhere under `work/` — see `docs/wifi-parity.md`
§9), so these are the only two rows whose sourcing cannot be re-derived from
the checked-in tree alone.

**Method.** Every vendored file was read in full, its interpreter and every
binary it calls verified against the *built* image (`output/target/`, the busybox/kernel
sources, and `work/Main_MiSTer` for the callers) before shipping. Buckets:
**(A)** existing Buildroot package enabled, **(B)** file vendored into
`board/mister/de10nano/rootfs-overlay/` (byte-identical to
`addon.tar`/`work/imgroot` unless marked *adapted*), **(C)** would need a new
package, **(D)** infeasible. `scripts/ci-tests.sh` §"T3" asserts everything
marked CLOSED here.

| Item | Bucket | Disposition |
|---|---|---|
| `usr/sbin/btctl` | **B + A — CLOSED** | Vendored byte-identical (`python3 -m py_compile` clean). This is what makes the OSD's Bluetooth **Pair** button work at all: Main popen()s `/usr/sbin/btpair` (`work/Main_MiSTer/menu.cpp:7102`) and runs `btctl disconnect <mac>` (`input.cpp:5581`). Its imports (`dbus`, `dbus.service`, `dbus.mainloop.glib`, `gi.repository.GLib`) need dbus-python + PyGObject — exactly what stock ships for its python3.9 (verified in `work/imgroot/.../site-packages/`) — so `BR2_PACKAGE_DBUS_PYTHON=y` + `BR2_PACKAGE_PYTHON_GOBJECT=y` are now set (defconfig, Python section; gobject-introspection was already on, so the heavy part was pre-paid). Shebang `/usr/bin/python` resolves (`usr/bin/python -> python3` in the target). |
| `usr/sbin/btpair` | **B — CLOSED** | Vendored byte-identical; bash (shipped), drives `btctl pair`. Called by absolute path from Main (above), so the stock path `/usr/sbin/btpair` is load-bearing. |
| `usr/sbin/uartmode` | **B — CLOSED, one caveat** | Vendored byte-identical. Main invokes `uartmode %d` (`user_io.cpp:1175`) and stats `/tmp/uartmode*` (`user_io.cpp:1147-1152`) — without this script the OSD's UART/MIDI mode switch was a silent no-op. Every callee verified in the target: bash, killall, taskset, agetty, midilink, mt32d, fluidsynth, mpg123. **Caveat:** mode 1 (PPP) additionally needs `pppd`, which stock's *base rootfs* ships (`work/imgroot/usr/sbin/pppd`) but our package set does not — a `rootfs.tar.bz2`-level omission that `docs/package-manifest.md` never dispositioned (flagged there, out of §3c's addon scope). Modes 0/2–5 (kill/console/MIDI×2/UDP) are fully functional; mode 1 without `/media/fat/linux/ppp_options` cleanly prints "skip pppd" and exits. |
| `usr/sbin/vmode` | **B — CLOSED** | Vendored byte-identical. Writes `fb_cmd0/fb_cmd1` to `/dev/MiSTer_cmd` — a FIFO **Main creates** (`input.cpp:4051`), commands handled at `input.cpp:6236` — and polls `/sys/module/MiSTer_fb/parameters/res_count`, which exists because `CONFIG_FB_MISTER=y` and `MiSTer_fb.c:38` declares `module_param(res_count, uint, 0444)`. bash + busybox `usleep` both present. |
| `usr/bin/vhd_mount` | **B — CLOSED** | Vendored byte-identical. Mechanism verified end-to-end on *our* stack: busybox `losetup` attaches, the cmdline's `loop.max_part=8` (`docs/boot-chain.md:155`) makes `/dev/loop1p1` appear, busybox `mount` mounts it on `/media/rootfs` — which must pre-exist on a read-only `/`, so the overlay now ships `media/rootfs/` (`.gitkeep` idiom, same as `/media/fat`). Stock's image has the same dir (`work/imgroot/media/rootfs`). |
| `usr/bin/m3u_play` | **B — CLOSED** | Vendored byte-identical. mp3 branch works (`mpg123` shipped); the vgm/vgz branches reference `vgmplay`, deliberately not shipped (below) — on a vgm playlist the script prints `vgmplay: not found`, exactly the graceful-degradation stock had for absent optional players. |
| `usr/bin/timidity` | **B — CLOSED (recon error corrected)** | The first reconciliation pass classified this "audio player (mixed)" as if it were TiMidity++ needing a new package. **It is a 22-line `/bin/sh` wrapper** (read from `addon.tar`): fluidsynth (ALSA-seq, `/media/fat/linux/soundfonts/SC-55.sf2`) + `aplaymidi --port 128 $MC_EXT_SELECTED`. Both callees shipped; `$MC_EXT_SELECTED` is exported by mc on every ext.ini action (`mc-4.8.33 src/filemanager/ext.c:205`), so it also works with mc 4.8.33's stock `[midi]` handler (whose `sound.sh` execs `timidity` — i.e. this wrapper). Its `function ctrl_c()` bashism is legal in our `/bin/sh`: since issue #144 `/bin/sh` is bash, as on stock (`BR2_SYSTEM_BIN_SH_BASH=y`, `docs/buildroot-config.md` §5.19), and bash accepts `function` in POSIX mode — this file was written for bash all along, and the earlier note that busybox 1.38 ash's `CONFIG_ASH_BASH_COMPAT=y` happened to tolerate it described the accommodation, not the design. Vendored byte-identical. |
| `usr/bin/vgmplay`, `usr/bin/VGMPlay.ini` | **C — DECLINED, documented** | Real gap, deliberate decline. VGMPlay (vgmrips/vgmplay, GPL) has no Buildroot package; writing one here could not be build-verified (T3 runs under a no-build constraint), and an untested C package is a worse outcome than an honest absence — it risks breaking `make all` for a niche feature (VGM chiptune playback inside mc). Cost of absence: mc's vgm handler and `m3u_play`'s vgm branch print `not found`; nothing else references it. Revisit as its own small task if VGM playback is ever asked for: pin a release tarball, `Makefile`-type package, install `VGMPlay.ini` beside the binary (it looks for its ini next to `argv[0]`). |
| `usr/bin/memtool` | **A — CLOSED** | Not a sourceless blob after all: strings on the stock ELF are pengutronix memtool's exact usage text, and `addon.tar`'s `usr/bin/md`/`mw` are symlinks → `memtool` (argv[0] dispatch — `memtool.c:475` in the pinned 2018.03.0 tarball switches on `basename(argv[0])`). `BR2_PACKAGE_MEMTOOL=y` (Buildroot's own package, same upstream, 2018.03.0 — upstream's last release, confirmed against pengutronix's release directory). The package installs only the `memtool` binary, so stock's `md`/`mw` symlinks are reproduced in the overlay. |
| `usr/bin/fpga` | **D — INFEASIBLE, precisely bounded** | Stripped ARM ELF; **no public source found**: GitHub code search for its distinctive strings finds only `Main_MiSTer/fpga_io.cpp` (which shares the literal `"FPGA: Unaligned data, realign to 32bit boundary."`, `fpga_io.cpp:352`) and u-boot's `drivers/fpga/socfpga.c`; no MiSTer-devel repo builds a standalone `fpga` binary. It is a dev-era peek/poke + RBF loader (`Usage(1): %s { address } [ data ]`, `Usage(2): %s { rbf_file }`, mmaps `/dev/mem`). Shipping the blob violates rule G6; recreating it from `fpga_io.cpp` would be new, untestable systems code. **Intent is covered**: core loading = `echo load_core <file> > /dev/MiSTer_cmd` (Main, `input.cpp:6238-6242` — and mc's Enter-on-`.rbf` now does exactly that); peek/poke = `memtool md`/`mw` (above) or busybox `devmem`. Same documentation standard as `docs/firmware-parity.md`'s no-upstream-source firmware. |
| `usr/bin/rz`, `usr/bin/sz` | **A — CLOSED (T5, 2026-07-27)** | `BR2_PACKAGE_LRZSZ=y` — confirmed resolved `=y` in `output/.config` after `make de10nano-defconfig` (`lrzsz.mk` installs exactly `$(TARGET_DIR)/usr/bin/rz` and `.../sz`, matching stock's paths exactly, plus **six** bonus compat symlinks — `lrz`/`rb`/`rx` → `rz` and `lsz`/`sb`/`sx` → `sz`, `lrzsz.mk:21-26` — stock's `addon.tar` does not have). |
| `usr/lib/libfluidsynth.so.3.0.0` | **covered (better version)** | The fluidsynth package ships `libfluidsynth.so.3.3.7` + the `libfluidsynth.so.3` SONAME link (verified in target) — same SONAME stock's addon symlinks resolve to, newer revision. Nothing links the full `3.0.0` filename. |
| `usr/sbin/fluidsynth` (path diff) | **CLOSED (compat symlink)** | Stock installs the ELF at `/usr/sbin/`, our package at `/usr/bin/`. No shipped caller uses the absolute stock path — midilink builds the command `fluidsynth …` via PATH (`output/build/midilink-*/main.c:154`), the timidity wrapper and `uartmode`'s `killall` go by name, Main never references it — but third-party user scripts may hardcode it, so the overlay adds `usr/sbin/fluidsynth -> /usr/bin/fluidsynth` (same idiom as the existing `usr/sbin/mount.ntfs` link) and the difference is gone outright. |
| `etc/asound.conf` | **B — CLOSED** | Vendored byte-identical. This is not optional polish: it routes ALSA's `!default` pcm through a 48 kHz S16_LE `file` plugin writing raw into `/dev/MrAudio`, the in-kernel MiSTer SPI audio ring (`CONFIG_SND_MISTER_AUDIO=y`; device created at `sound/drivers/MiSTer-audio-spi.c:231`) that Main/core mix into HDMI/analog out. **Not** because `hw:0` is missing — `hw:0` exists and *must*: `MiSTer-audio-spi.c` is a chardev SPI driver with no ALSA card at all, so the only card is the patched `snd-dummy` (`CONFIG_SND_DUMMY=y`, `board/mister/de10nano/linux.config:391`, built in; `enable[0]=1` at `sound/drivers/dummy.c:51` registers it as card 0), and this file's own innermost slave is `type hw; card 0` — the `type file` plugin *duplicates* the stream, so card 0 has to accept S16_LE/48 kHz/2ch or the default pcm fails to open outright ([`docs/abi-contract.md`](abi-contract.md) §8.2(a), §8.2(c) — "`CONFIG_SND_DUMMY=y` … *and it must be card 0*", MUST). The real cost of omitting `asound.conf` is that ALSA's default resolves to that dummy card, which discards the samples: the system is **silently mute** (`docs/phase0-review.md:128`, "omit it and the system is silent"). No package installs `/etc/asound.conf` (verified in target), so no shadowing. |
| `etc/kbd.map` | **B — CLOSED, loader now ALSO present (T5, 2026-07-27)** | Vendored byte-identical (70-byte text keymap). It blanks VC keycodes 88/113/114/115 = F12/Mute/Vol-/Vol+ — the keys Main consumes via evdev for OSD/volume — so the framebuffer console stops double-acting on them. The stock `loadkeys`/`setfont` inittab lines are restored **guarded** (`[ -x /usr/bin/loadkeys ] && …`); `BR2_PACKAGE_KBD=y` now resolves `=y` in `output/.config` (T5), so the guard is live and these lines do stock's exact job on every boot, not just a silent no-op. busybox's `loadkmap` applet is *not* a substitute (binary bkeymap format, not this text file). |
| `usr/share/consolefonts/default8x16.psfu.gz` | **covered (T5, 2026-07-27); exact filename not confirmed** | A compressed font is a binary (G6: not vendorable), and it does not need to be: kbd 2.9.0's own `data/consolefonts/` ships `default8x16.psfu` and installs it to `/usr/share/consolefonts` (`data/Makefile.am:45-49`), which is also the path stock's setfont hardcodes (strings on `work/imgroot/usr/bin/setfont`). `BR2_PACKAGE_KBD=y` now resolves `=y` in `output/.config` (T5). Whether the *installed* filename ends up `default8x16.psfu` or (matching stock exactly) `default8x16.psfu.gz` depends on whether gzip is on the build host at kbd's configure time (`configure.ac`'s `enable_compress=auto` checks for `"gzip -n"` and compresses the font data if found — virtually always true, but not verified against a real build for this task). It does not matter functionally either way: `setfont`'s own lookup (`kbd-2.9.0 src/libkfont/setfont.c:417` -> `kbdfile_find()` -> `maybe_pipe_open()`, `src/libkbdfile/kbdfile.c:241-267`) tries the bare name and then every configured decompressor's suffix before giving up, transparently piping through the decompressor if a compressed variant is what it finds — so bare `setfont` (our guarded inittab line, stock parity) resolves either filename identically. Confirm the actual installed filename in `output/target/usr/share/consolefonts/` on the next real build if it ever matters precisely. |
| `etc/mc/*`, `root/.config/mc/*`, `usr/share/mc/skins/MiSTer.ini` | **A + B — CLOSED (format port)** | `BR2_PACKAGE_MC=y` (4.8.33; stock ran 4.8.25). Vendored byte-identical: the `MiSTer.ini` skin, `root/.config/mc/ini` (`skin=MiSTer`, stock's layout prefs; obsolete keys like `fish_*` are ignored harmlessly) and `panels.ini` (right panel opens on `/media/fat`). **Adapted, not copied** (each file's header documents every delta): `etc/mc/mc.ext.ini` and `etc/mc/filehighlight.ini` — upstream **replaced the `mc.ext` format with `mc.ext.ini` in 4.8.29** (mc-4.8.33 `NEWS:191` "Version 4.8.29", `NEWS:203` "Port mc.ext to INI format and rename to mc.ext.ini", `NEWS:205` "There is no fallback to previous mc.ext format" — *not* 4.8.28, whose section at `NEWS:249` still lists plain `mc.ext` bugfixes), so stock's `mc.ext` would be ignored by 4.8.33; the overlay ships the 4.8.33 package default re-derived with one inserted MiSTer block (Enter on `.rbf` → `load_core` via `/dev/MiSTer_cmd`; `.vhd` → `vhd_mount`; `.wav` → `aplay`; `.m3u` → `m3u_play` — stock's exact `Open=` commands) and rbf/vgm highlighting. Both overlay copies deliberately shadow the same paths the mc package installs — the identical mechanism stock's `addon.tar` used on *its* mc files. Stock's `mc.default.keymap`/`mc.menu`/etc. were never addon items (they came from stock's own mc package) and are supplied by ours. **Runtime caveat, parity-preserving:** mc creates *three* XDG dirs at startup — `~/.config/mc`, `~/.cache/mc`, `~/.local/share/mc` (`lib/mcconfig/paths.c:183-188` → `mc_config_mkdir()` `:104-112`) — and **exits** if any cannot be created (`src/main.c:315-320`). Only the first is vendored, and `/` is mounted `ro` (`docs/boot-chain.md:323`; the `inittab:53` remount is commented out), so mc depends on `/etc/profile:31`'s `mount -o remount,rw /` having run — i.e. on at least one login shell since boot. mc launched from a Main_MiSTer *Scripts* entry on a fresh boot would fail with `Cannot create /root/.cache/mc directory`. **Stock is identical** (its addon ships the same two files and nothing under `~/.cache`, and its `/etc/profile:23` has the same remount), so this is recorded, not "fixed": shipping empty dirs would diverge from stock and the overlay's rsync `--chmod=u=rwX,go=rX` would create them `0755` where mc wants `0700`. Related out-of-scope note: stock's base rootfs also ships `modplug123`/`mikmod`/`ogg123`, which mc's stock handlers reference; they are a package-manifest matter, not addon items, and are flagged in `docs/package-manifest.md`'s follow-ups rather than smuggled in here. |
| `etc/jms583-phantom-guard.sh` + `etc/udev/rules.d/60-jms583-phantom.rules` | **B — CLOSED** | Both vendored byte-identical (guard 755 executable — the rule execs it directly via `setsid` inside `RUN+="/bin/sh -c …"`; rule 644). POSIX sh, `dash -n` clean; callees (`setsid`, `readlink -f`, sysfs scsi_device paths) all present on this image. Deletes the never-ready phantom LUN a JMS583 USB-NVMe bridge exposes for its empty slot, which otherwise stalls SCSI shutdown. |
| `var/lib/bluetooth/placeholder` | **covered structurally** | The placeholder file exists only to keep `var/lib/bluetooth/` alive inside stock's tar. Here bluez 5.79's own install creates the directory in the image (`install -dm700 $(DESTDIR)$(statedir)`, `Makefile.am:32,36` — mode 0700, verified in target), and `/usr/bin/bluetoothd` (stock-identical, shipped since P2.3) mounts the persistent ext4 image from `/media/fat/linux/bluetooth` over it before bluetoothd starts. A placeholder file would add nothing and shadow nothing; not shipped. |

**`addon.tar`'s symlink entries.** These are excluded from the 56-regular-file
count, so they are dispositioned here. `tar tvf` on the pinned archive reports
exactly **56 regular files, 29 directories, 12 symlinks**, and all **12** are
accounted for below (the count is stated so a future edit that drops one is
visibly wrong — an earlier revision of this paragraph listed only 11, silently
omitting `S45bluetooth`):

| # | Symlink | Disposition |
|---|---|---|
| 1–3 | `usr/bin/md` → `memtool`, `usr/bin/mw` → `memtool`, `usr/bin/play` → `aplay` | **Reproduced in the overlay.** Both targets ship. `play` is what mc's stock `sound.sh open common` branch execs for au/voc/snd files, and alsa-utils `aplay` natively plays voc/wav/raw/au — the alias is functional, not cosmetic. |
| 4–8 | `etc/localtime`, `etc/ssl/cert.pem`, `usr/sbin/mount.ntfs`, `usr/lib/libfluidsynth.so`, `usr/lib/libfluidsynth.so.3` | **Already covered** (overlay or package). |
| 9–10 | `usr/lib/libjack.so`, `usr/lib/libjack.so.0` | Fall with the §3b `libjack` drop. |
| 11 | `etc/init.d/S45bluetooth` → `/bin/bluetoothd` | **Already covered** — see [`docs/init-parity.md`](init-parity.md), `S45bluetooth` row. Stock's init entry *is* this symlink; its target is `addon.tar`'s own `usr/bin/bluetoothd` (an `EXACT` row in `verification/stock-reconciliation/addon-report.txt`) because stock is usr-merged (`work/imgroot/bin -> usr/bin`; both paths and the overlay's copy hash to `db7c5095…`). The overlay reproduces that exact shape, plus a documented no-op stub at `etc/init.d/S40bluetoothd` so bluez's own init script cannot start a second `bluetoothd`. |
| 12 | `usr/bin/mikmod` → `modplug123` | **Not shipped.** Its target does not exist on this image (`docs/package-manifest.md` §4b), and a dangling symlink is strictly worse than an absent one. |

**`etc/udev/rules.d/70-persistent-net.rules` — CLOSED (T2).** Stock's rule is:

```
SUBSYSTEM=="net", ACTION=="add",    DRIVERS=="?*", KERNEL=="wlan*", NAME="wlan0", RUN+="/sbin/ifup -a"
SUBSYSTEM=="net", ACTION=="remove", DRIVERS=="?*", KERNEL=="wlan*", RUN+="/sbin/ifdown %k"
```

It forces any `wlan*` device to be named `wlan0` and brings the interface up
on hotplug. At the time this section was first written we shipped neither it
nor an equivalent — a WiFi dongle inserted *after* boot was never brought up,
where it would be on stock.

T2 closed this with an **adapted**, not verbatim, equivalent:
`board/mister/de10nano/rootfs-overlay/etc/udev/rules.d/70-persistent-net.rules`
+ `etc/wifi-hotplug.sh`. Two deliberate divergences, both verified against
this image's actual eudev/kernel rather than assumed — full citations live in
the rule file's own header comment, `docs/wifi-parity.md` §9:

- **No `NAME="wlan0"`.** Stock's hardcode-to-one-name contradicts this
  image's existing two-adapter support (`auto wlan0` **and** `auto wlan1` in
  `/etc/network/interfaces` since P2.3). In *this* build the damage is
  bounded — `BR2_PACKAGE_EUDEV_RULES_GEN` is unset, so eudev's
  collision-avoidance temp-rename machinery is compiled out and a second
  adapter's rename simply fails `EEXIST`, logs one warning and keeps its
  kernel name `wlan1` — but it is one Kconfig symbol away from producing a
  name matching neither stanza, and it buys nothing: the DE10-Nano's USB
  controllers are memory-mapped `snps,dwc2` platform devices, not PCI, so
  eudev's `net_id` builtin never has a PCI ancestor to compute a predictable
  name from and `80-net-name-slot.rules` is a permanent no-op for our USB
  WiFi dongles regardless. (eudev 3.2.14 still *implements* NAME=-driven
  netif rename via `SIOCSIFNAME` — this is a correctness choice for our
  topology, not a capability gap.)
- **`RUN+=` goes through an async helper (`etc/wifi-hotplug.sh`), targeting
  the specific interface (`%k`) instead of stock's blanket `ifup -a`.** The
  per-stanza `pre-up` wait loop (up to 20s, polling `iw dev $IFACE info`)
  means `-a` would also block on any `auto`-but-not-present second adapter.
  eudev's default 180s event timeout means this was never a "getting the
  worker killed" risk; the real reason to detach is that `S10udevd:43` runs
  `udevadm settle --timeout=30` right after the coldplug trigger, so a
  blocking `RUN+=` would stall `rcS` for the whole >20s bring-up on **every**
  boot with WiFi hardware present. Because `settle` drains the queue first,
  the rule completes inside `S10udevd`, before `S40network` — what overlaps
  `S40network`'s own boot-time `ifup -a` is the detached `ifup`. That overlap
  is safe because `ifupdown` itself serializes on a per-interface state file
  under `/run/network/` (tmpfs) using an exclusive POSIX record lock (`fcntl`
  `F_SETLK`/`F_SETLKW`, `main.c:203-215` — not `flock(2)`) and no-ops if the
  interface is already configured.

Verified present in the built image: `usr/sbin/ifup` (72536-byte ARM ELF) and
`usr/sbin/ifdown -> /usr/sbin/ifup` (same binary, dispatching on `argv[0]`);
`output/target/sbin` is itself a symlink to `usr/sbin` (`BR2_ROOTFS_MERGED_USR=y`),
so stock's `/sbin/…` spellings resolve to those same entries. `usr/sbin/iw`
(264720-byte ARM ELF, `BR2_PACKAGE_IW=y` at
`configs/fragments/de10nano-image.fragment`). Not yet tested on real hardware —
see `docs/wifi-parity.md` §9's checklist.

The former "**one path difference**" (stock `/usr/sbin/fluidsynth` vs our
`/usr/bin/fluidsynth`) is closed by the compat symlink — see the
`usr/sbin/fluidsynth` row in the table above.

### 3c-bis. Latent defects **inside** stock's own scripts — carried deliberately

Automated review of PR #68 flagged three defects in the vendored helpers.
All three are **in stock's bytes**, not in our vendoring: `diff` against
`work/imgroot/usr/sbin/{uartmode,btpair,vmode}` is empty for each. They are
recorded here, and **deliberately not fixed**, because "vendored
byte-identical" in the table above is the whole point — `scripts/ci-tests.sh`
asserts the stock marker in each file, every other MiSTer runs these exact
bytes, and their callers already cope with the behaviour. Patching them would
be a silent divergence in the direction this document exists to prevent.
Precedent for how a real divergence gets made instead: ADR 0016's
`/etc/network/interfaces` `pre-up` line — one deviation, argued and recorded.

| Script:line | Claim | Verdict on the claim |
|---|---|---|
| `uartmode:34` — `if [ -z $localip ]` | Reviewer: unquoted, so an empty `localip` yields `[ -z ]`, "a syntax error / wrong evaluation", and the PPP branch will not fall back to `0.0.0.0`. | **Claim is wrong; the code works.** `[ -z ]` is a POSIX *one-argument* test — true iff that single argument is a non-empty string — and `-z` is non-empty, so it returns TRUE and the fallback branch *is* taken. Verified empirically. The real (latent, unhit) risk is word-splitting if `localip` ever held whitespace; it is assigned from an `ifconfig \| sed` pipeline that yields one token or nothing. |
| `btpair:10` — "devices(s)" | Reviewer: grammatical typo in a user-facing prompt. | **Correct, and purely cosmetic.** Stock's wording, shown in stock's UI. |
| `vmode:95-102` — the confirmation poll | Reviewer: the polling is inverted — on success the test goes false and `\|\| exit 1` fires, so the script exits non-zero on success and prints `failed!` regardless. | **Correct — a real bug in stock.** Traced: while `res_count` is *unchanged* the test is true and the script sleeps; the moment it *changes* (i.e. the mode switch is confirmed — the success case) the test goes false and `\|\| exit 1` fires. If it never changes, control falls through to the unconditional `exit 1` on the last line. So `vmode` exits `1` on **both** paths, and `echo -n . failed!` prints "failed!" as an argument on the fifth line either way. Harmless in practice only because callers ignore its status. **Worth reporting upstream to MiSTer-devel**; not ours to diverge on. |

---

## 4. Bottom line

- **Firmware:** 58/69 stock files present; all 11 absences justified
  (unreachable hardware, superseded names whose mainline equivalents we ship,
  or no upstream source). **+213 paths added.**
- **Modules:** every one of stock's 52 is functionally covered — 38 by name,
  6 by mainline replacements, 7 by the renamed (and larger) xone set, 1
  (`lib80211`) with no consumer in 6.18. **+62 modules added**, not counting
  the not-yet-built `8852cu.ko` (below).
- **Out-of-tree WiFi drivers: stock ships 6, we ship 1.** All six chips stock
  drove out-of-tree now bind a mainline `mac80211` driver (§2a); the one
  exception, `rtl8852cu-morrownr` (RTL8852CU/RTL8832CU Wi-Fi 6E), is for a
  chip that has **no stock driver at all** — it is not one of stock's 6, and
  it does not reopen the bind-conflict class stock worked around with
  `rtw88-prefer.conf` (§2a's corroboration note, `docs/wifi-parity.md` §8).
  Sourced and defconfig-selected; **not yet built or hardware-tested.**
- **`addon.tar`:** 34/56 at the stock path (14 pre-T3, +18 closed by T2/T3,
  +2 closed by T5: `rz`/`sz`), 5 covered at a different path or mechanism
  (`mc.ext`→`mc.ext.ini` format port, `libfluidsynth.so.3` newer revision,
  `var/lib/bluetooth/` shipped by bluez's own install, `.ssh/environment`,
  +1 by T5: the console font, filename not confirmed against a real build
  but functionally covered either way — see §3c). The **17 permanent absences
  are all decisions, individually documented**: 9× §3a (per-device SSH keys +
  no OOT blacklist — we are better), 5× §3b drops, vgmplay+ini declined with
  reasoning, and `usr/bin/fpga` — the one genuinely sourceless binary, its
  intent covered by `load_core` via `/dev/MiSTer_cmd` and memtool/devmem
  (§3c).
- **`70-persistent-net.rules` (WiFi hotplug-after-boot): CLOSED (T2)** — see
  §3c for the adapted rule and its two verified, documented divergences from
  stock's literal text.
- **OSD features un-broken by T3**, previously silent no-ops on this image:
  Bluetooth pairing from the OSD (`/usr/sbin/btpair` + `btctl`) and the
  UART/MIDI mode switch (`uartmode`). Both were stock scripts Main_MiSTer
  invokes that simply did not exist here.

---

## 5. Utility binaries (T5) — full-image `/bin`,`/sbin`,`/usr/bin`,`/usr/sbin` diff

A different, broader comparison than §1-§4: not the three archives
`create_img.sh` applies on top of a base rootfs, but a filename diff of
**stock's whole executable-path set** (`work/imgroot/{bin,sbin,usr/bin,
usr/sbin}`) against `output/images/rootfs.tar`. This is the source of the
"stock ships it, we don't" gaps that are neither firmware nor kernel modules
nor an `addon.tar` overlay item — ordinary userland utilities.

**315 raw differences, most of them noise**: a full Perl install (`perl5/`,
1484 files — package-manifest.md §5's largest pure-drop candidate, and stays
dropped, see that row), python3.9-versioned script names our python3.14
naturally doesn't reproduce byte-for-byte, and GNU long-form duplicates of
BusyBox applets this image already covers under a different provider (the
util-linux block in `board/mister/de10nano/busybox.fragment` and
`docs/util-linux-parity.md`).

**What T5 changed** (full binary/package table: `docs/package-manifest.md`
§4c) — three groups. Most of it *is* a real stock gap closed, but not all of
it, and the exceptions are called out inline rather than folded into the
headline: `nc` is a substitution, `lsof` an upgrade, and four packages are
net-new beyond stock.

1. **Nine BusyBox applets** (`stat`, `timeout`, `tac`, `shuf`, `comm`,
   `split`, `expand`, `groups`, `nc`) that BusyBox 1.38.0 supports but this
   image's config had off. `stat`/`timeout` matter most in practice —
   ordinary shell scripts use both. **Eight are a true 1:1 reproduction**:
   stock ships them as GNU coreutils (`work/imgroot/usr/bin/{stat,timeout,
   tac,shuf,comm,split,expand,groups}` are all symlinks → `coreutils`), and
   the BusyBox applets take the same names at the same paths. **`nc` is a
   deliberate substitution, not a reproduction** — stock's provider is *not*
   BusyBox: `work/imgroot/usr/bin/netcat` is a separate 34376-byte ARM ELF
   whose strings read "GNU netcat %s, a rewrite of the famous networking
   tool." / "netcat (The GNU Netcat) %s", i.e. GNU Netcat, exactly what
   Buildroot's own `package/netcat` builds (`netcat.mk:7`,
   `NETCAT_VERSION = 0.7.1`), with `usr/bin/nc` a symlink → `netcat` beside
   it. BusyBox's `nc` is a different implementation with a different option
   set; the trade is ~11 kB of applet instead of a whole extra package, and
   it is accepted for ad-hoc on-device network poking. Stock's *second* name
   is preserved too: `CONFIG_NETCAT=y` (BusyBox's own alias applet,
   `networking/nc.c:17-21`, `default n` upstream) is set alongside
   `CONFIG_NC=y` so `usr/bin/netcat` is not a command-not-found — see
   `board/mister/de10nano/busybox.fragment`'s T5 block, guarded in
   `scripts/ci-tests.sh` §T5.
2. **`wpa_cli`/`wpa_passphrase`** — sub-options of the already-built
   `wpa_supplicant` package.
3. **21 packages** spanning process/file inspection (`htop`, `lsof`),
   USB/input (`usbutils`, `linuxconsoletools`' joystick + force-feedback
   tooling), filesystem tools (`dosfstools`, `exfatprogs`), serial/terminal
   (`picocom`, `lrzsz`, `tmux`), network diagnostics (`ethtool`, `socat`),
   archival (`7zip` / `7zz`, `zip`, `lzop`), hardware buses (`spi-tools`),
   Bluetooth CLI (`bluez-tools`), and console/keyboard (`kbd`).

   Two caveats on that list, both verified against `work/imgroot` rather
   than assumed:

   - **`lsof` is an upgrade, not parity restoration.** Stock's
     `usr/bin/lsof` is a symlink → `../../bin/busybox`, i.e. stock ships the
     BusyBox applet. Enabling `BR2_PACKAGE_LSOF` *and* turning
     `CONFIG_LSOF` off is a deliberate divergence from stock in favour of
     the real lsof (network sockets, `-p`, `-i`) — recorded as such, not a
     closed gap.
   - **Four T5 additions are not in stock at all** and so are not "gaps
     closed": `strace` (promoted from the temporary `DEBUG TOOLING` block to
     permanent), `evtest`, `tcpdump`, `iperf3`. `find work/imgroot -name X`
     returns nothing for any of the four, and none appears in this section's
     own 315-difference stock-only name set. They are net-new debugging and
     network-diagnostic tooling this image chose to carry beyond stock. Every
     *other* package named above does have a real stock counterpart at a
     verified path (`usr/bin/{htop,tmux,picocom,socat,zip,lzop,spi-config,
     spi-pipe,bt-adapter,7zr,jstest,fftest,lsusb,rz,sz,loadkeys,setfont}`,
     `usr/sbin/{ethtool,mkfs.fat,mkfs.exfat}`).
   - **The `7zr` counterpart is matched by a NEWER binary under a different
     name (updated 2026-07-27, ADR 0023).** Stock's `usr/bin/7zr` exists and is
     real, but re-identifying it rather than just confirming its path shows what
     it is: `7-Zip (a) [32] 16.02 : Copyright (c) 1999-2016 Igor Pavlov :
     2016-05-21`, i.e. **p7zip 16.02**, 973,392 bytes, dynamically linked. We
     now ship upstream 7-Zip **26.02** as `usr/bin/7zz`, aliased from **both**
     `7za` and `7zr` — so stock's own path is still answered, by a ten-years-
     newer superset, and this row is parity-**plus** with no filename cost.
     (Stock has no `7za` and no `7z` at all, so those names are new here.)
     Worth stating
     because stock is stale in *two* places at once: that rootfs `7zr` **and**
     the separately-downloaded `/media/fat/linux/7za`, which is the same
     p7zip 16.02 build fetched over the network (`docs/downloader-contract.md`
     §4). We replace both.

**Two real oversights found and fixed along the way, not new gaps**:
`BR2_PACKAGE_NTFS_3G=y` had been on since P2.1 but its `NTFSPROGS`
sub-option (which is what actually gates `mkfs.ntfs`/`ntfsfix`) was never
set, so those two binaries had never shipped despite ntfs-3g itself being
enabled; and `BR2_PACKAGE_DTC=y` had likewise been library-only (`libfdt`)
since P2.1, with the separate `DTC_PROGRAMS` sub-option that actually
installs the `dtc` CLI never set. Both fixed in place next to their
existing lines in the defconfig.

**A genuine BusyBox/real-package collision class, found and fixed**: seven
BusyBox applets that were already **on** turned out to install to the exact
path a T5 package's real binary also wants — `lsof`, `lsusb`, `mkdosfs`
(dosfstools' compat symlink), and `chvt`/`deallocvt`/`openvt`/`setkeycodes`
(all four from kbd). Same non-deterministic "last install wins" hazard
`docs/util-linux-parity.md` and the ifup/ifdown fix already document for
this image; same fix — the BusyBox applet is turned off in
`board/mister/de10nano/busybox.fragment` so the real package's binary is the
one that lands, deterministically. `scripts/ci-tests.sh` §"T5" asserts the
real package won each one.

**Deliberately still absent** (maintainer decision, not oversights —
`docs/package-manifest.md` §5 has the full reasoning for each): `perl`
(anyone who needs it can build their own image from this repo), `vim`
(BusyBox `vi` + `nano` already cover on-device editing), `screen` (`tmux`,
added by T5, is this image's multiplexer — not both), the on-device *target*
`gdb` as a permanent package (host `gdb` + `gdbserver` is judged the better
shape; a target debugger is 4-8 MB — note the temporary `DEBUG TOOLING`
block ships one anyway for the still-open RT-latency work, `docs/debug-
tooling.md`, which is a separate, dated decision), `ltrace` (narrow,
frequently broken on ARM; `strace` supersedes it here), and `unrar`
(non-free RARLAB licence — MiSTer release archives are `.7z`, not `.rar`, and
`7zip`/`7zz` closes that gap instead; note `7zz` does bring RAR/RAR5
*extraction* with it under the far weaker unRAR restriction, ADR 0023 §5).

Not measured against a real build for this task (no build was run, per the
task's own constraint): the exact installed size of kbd's font/keymap data
trees (estimated ~1.5-2.5 MiB compressed from ~5.5 MiB of uncompressed
source — see the defconfig's `BR2_PACKAGE_KBD` comment) and the exact
installed filename of the default console font (`default8x16.psfu` vs.
stock's `default8x16.psfu.gz` — functionally identical either way, see the
`etc/kbd.map`/consolefonts rows in §3c). Confirm both against
`output/target/` on the next real build.
