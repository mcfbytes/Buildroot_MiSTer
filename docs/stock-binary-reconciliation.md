# Stock binary reconciliation — stock 20260907 vs. this image

Every path on the executable surface of stock `release_20260907` and of this
image, with each side's package and version. The full per-path table is
[`stock-inventory/20260907/binary-recon/binary-reconciliation.tsv`](stock-inventory/20260907/binary-recon/binary-reconciliation.tsv)
(1,365 rows). This page summarises it.

- **Current state**: the PR #283 build (Tier 1 + BlueZ providers, the
  `usr/bin/kill` fix and the gpm version fix). Generated 2026-11-01.
- **[Appendix](#appendix--pre-tier-1-audit-2026-10-31)**: the pre-Tier-1 audit
  that motivated PR #283. Kept as history; its counts describe the old image.

## Inputs and method

| | Stock | Ours |
|---|---|---|
| Image | `files/linux/linux.img` from the SHA-256-verified `release_20260907.7z` (`MiSTer.version` = `260907`), extracted with `debugfs rdump`. That is the shipped ext4, so `addon.tar` content is included | `output/images/rootfs.tar` from a local build of this branch (Buildroot 2026.08.1, kernel 6.18.60) |
| Build system | Buildroot 2021.02.4 (`/etc/os-release`), glibc 2.31 | Buildroot 2026.08.1, glibc 2.44 |
| Path → package | No package list ships, so attribution comes from three places: the BusyBox symlink target; the package that installs the same path (or basename) in ours; and per-path overrides proved from the binary (`stock-overrides.tsv`, 180 rows) | `output/build/packages-file-list.txt` (exact) + `BR2_ROOTFS_OVERLAY` |
| Package → version | Buildroot 2021.02.4 `package/*.mk`, replaced wherever the binary says otherwise (`stock-versions.json`) | `make show-info` |

**Scope.** Every file and symlink under `usr/bin`, `usr/sbin`, `usr/libexec`
and `libexec`; every ELF executable anywhere; and every executable script
anywhere outside `/etc` (init scripts are covered by
[init-parity.md](init-parity.md)). Merged-usr is normalised, so `/bin/x` means
`/usr/bin/x`. Shared libraries appear only when they are themselves runnable
(glibc, libcap). [`shared-libraries.md`](stock-inventory/20260907/shared-libraries.md)
is the library inventory.

**Verification.** Sonnet subagents checked the table against the binaries
themselves, using `qemu-arm -L <root> … --version`, `strings` and package
metadata:

- 94 packages were checked on both sides (`package-versions.tsv`).
- All 172 stock paths that had no package in ours were attributed one by one.
- An adversarial pass then tried to refute rows: all stock-only and ours-only
  rows, plus an 80-row sample of matched ones. Its corrections (renames,
  relocations, `rdisc`, `chcon`/`runcon`) are applied.

Versions marked `show-info / .mk` in the table below are the build system's
claim, not a banner. Most of them are ours-only packages with no stock
counterpart. About 55 of their banners were spot-checked, and all agreed.

**Regenerate** (data only, never executes either tree):

```sh
D=docs/stock-inventory/20260907/binary-recon
python3 scripts/inventory/binary_recon.py --stock <stock-root> --ours <ours-root> \
  --pkg-list output/build/packages-file-list.txt --show-info <(make -s show-info | sed 1d) \
  --stock-versions $D/stock-versions.json --stock-overrides $D/stock-overrides.tsv \
  --ours-overrides $D/ours-overrides.tsv --pairs $D/pairs.tsv \
  --stock-prefix-attr $D/stock-prefix-attr.tsv \
  --ours-overlay board/mister/de10nano/rootfs-overlay > $D/binary-reconciliation.tsv
```

`binary-reconciliation.tsv` has these columns: `path`, `status`, then for each
side `_kind`, `_target`, `_package`, `_version` and `_attribution`, then
`counterpart`.

## Headline (PR #283 build)

| Status | Rows | Meaning |
|---|---:|---|
| `same-provider` | **795** | Same path, same package on both sides (version differs) |
| `both-busybox` | 112 | BusyBox applet on both sides (1.33.1 → 1.38.0) |
| `real->busybox` | **6** | Stock had a real tool, ours has a BusyBox applet |
| `busybox->real` | 1 | `lsof`, a documented upgrade to lsof 4.99.6 |
| `provider-changed` | 13 | Same path, different provider (below) |
| `relocated-from` / `relocated-to` | 22 / 20 | Same tool under a renamed or moved path; the `counterpart` column pairs them |
| `stock-only` | **208** | Stock path with no counterpart in ours (dispositions below) |
| `ours-only` | 188 | Our path with no counterpart in stock |

Stock surface: 1,155 entries. Ours: 1,137. Pre-Tier-1, 114 stock-real paths
were BusyBox and 225 were missing; see the appendix.

### The 6 remaining real → BusyBox paths

| Path | Stock | Ours | Disposition |
|---|---|---|---|
| `/usr/bin/nc`, `/usr/bin/netcat` | GNU Netcat 0.7.1 | BusyBox 1.38.0 `nc` (`NC_SERVER`/`NC_EXTRA`/`NC_110_COMPAT` on) | Deliberate substitution, see [package-manifest.md §4c](package-manifest.md) |
| `/usr/bin/vi` | vim 8.2 | BusyBox `vi` | vim is a documented drop |
| `/usr/bin/xxd` | vim 8.2 (`xxd` V1.10) | BusyBox `xxd` | Comes with the vim drop |
| `/usr/bin/which` | GNU which 2.21 | BusyBox `which` | Open: Buildroot's `which` package exists but is not selected |
| `/usr/sbin/start-stop-daemon` | dpkg start-stop-daemon 1.18.10 | BusyBox | Documented substitution |

### The 13 provider changes

| Path | Stock | Ours |
|---|---|---|
| `/usr/bin/7zr` | p7zip 16.02 (real ELF) | 7-Zip 26.05 (symlink to `7zz`) |
| `/usr/bin/usbhid-dump` | prebuilt usbhid-dump 1.4 (no Buildroot package) | usbutils 019 |
| `/usr/sbin/midilink`, `/usr/sbin/mlinkutil` | MiSTer addon prebuilt, "MidiLink 3.3 BB7" | `package/midilink` @ `d6b3373`, the same banner |
| `/usr/sbin/mt32d` | prebuilt static munt 2.3.0 | `package/munt` munt_2_8_2 (dynamic libmt32emu 2.8.3) |
| `/usr/bin/bluetoothd` | MiSTer control script | Our overlay copy of it, launching through minijail |
| `/usr/bin/{m3u_play,timidity,vhd_mount}`, `/usr/sbin/{btctl,btpair,uartmode,vmode}` | MiSTer scripts | Our rootfs-overlay copies |

### The 208 stock-only paths

| Group | Paths | Disposition |
|---|---:|---|
| perl 5.32.1 | 30 | Documented drop |
| BlueZ 5.61 test scripts (`/usr/lib/bluez/test/*`) | 26 | Optional (`BR2_PACKAGE_BLUEZ5_UTILS_TEST`, needs Python D-Bus bindings); developer scripts, not shipped |
| BlueZ `btmgmt` | 1 | BlueZ builds it, but Buildroot 5.86 does not install it ([package-manifest.md §4f](package-manifest.md)) |
| vim 8.2 (`vim`, `ex`, `view`, `vimdiff`, `rview`, `rvim`, plus `share/vim` tool and macro scripts) | 17 | Documented drop |
| zsh 5.8 (+ 9 function scripts) | 10 | Documented drop |
| python-docutils 0.15.2 (`rst2*`), python-setuptools 44.0.0 (`easy_install*`), python-chardet 4.0.0 | 15 | Third-party Python modules not carried |
| python3 3.9 (`python3.9`, `smtpd.py.9`, `config-3.9` helpers) | 5 | Python 3.9 → 3.14 (`python3`/`python` present). Stock's `downloader_bin` is ABI-pinned to python3.9 (issue #187) |
| pppd 2.4.8 | 7 | Documented gap (package-manifest §4b) |
| vorbis-tools 1.4.2, modplugtools 0.5.3 | 8 | Documented gap (§4b) |
| S-Lang `slsh` 2.3.2 (+ 6 scripts) | 7 | Open: optional, unused by MiSTer scripts |
| e2tools 0.0.16.4 | 7 | Open: optional |
| libinput 1.16.4 Python measure/replay tools | 7 | Open: optional; ours ships the ELF tools |
| NTP 4.2.8p15 clients (`ntpq`, `ntpdc`, `ntpdate`, `ntptime`, `ntp-keygen`, `tickadj`) | 6 | Open: `ntpd` ships, but the NTP sub-options are off |
| MiSTer addon prebuilts (`adplay`, `archivemount`, `fpga`, `vgmplay`, `VGMPlay.ini`, `em`) | 6 | Documented declines; `em` (uEmacs/PK) is newly identified |
| xkbcommon 1.0.3 `xkbcli` (+ 3 libexec) | 4 | Open: optional |
| e2fsprogs 1.45.6 `e2scrub`, `e2scrub_all`, cron helper, `e4defrag` | 4 | Open: optional |
| samba 4.14.6 `findsmb`, `ctdbd_wrapper`, ctdb `06.nfs.script` | 3 | Dropped or renamed upstream by 4.24 (`mdfind` → `mdsearch` and `smnotify` → `ctdb_smnotify_helper` are paired as relocations) |
| iproute2 5.7.0 `ifcfg`, `routef`, `rtpr` | 3 | Removed upstream |
| libtasn1 4.17.0 `asn1*` | 3 | Open: optional tools |
| coreutils 8.32 `chcon`, `runcon` | 2 | SELinux tools; Buildroot builds them only with `BR2_PACKAGE_LIBSELINUX` |
| pcre 8.44 `pcregrep`, `pcretest` | 2 | PCRE2 substitution (`pcre2grep`, `pcre2test`) |
| ed 1.16 (`ed`, `red`), read-edid 3.0.2 (`get-edid`, `parse-edid`), dstat 0.8.0 (+ `dstat.py`) | 6 | Open: optional |
| util-linux `raw` 2.36.2 | 1 | Unbuildable with kernel headers ≥ 5.14 |
| iputils `rdisc` 20210202 | 1 | Removed from iputils |
| BusyBox `getty` | 1 | Documented: util-linux `agetty` |
| glibc `ldd` | 1 | Open: needs `BR2_PACKAGE_GLIBC_UTILS` |
| One each: `captest` (libcap-ng), `cpuload`, `dash`, `dbus-triggerd`, `edid-decode`, `fbgrab`, `fbv`, `fping`, `ftop`, `iostat`, `iotop`, `libhid-detach-device`, `lshw`, `memstat`, `mksh`, `netstat-nat`, `screen`, `unrar`, `rtorrent`, `xmlwf` (expat), `write_net_rules` (eudev), `alsaconf`, `ftpasswd` (proftpd), `unix_update` (linux-pam), `sample_approval.so` (sudo) | 25 | `screen`, `unrar`, `rtorrent` (→ transmission) and `libhid` are documented drops. The rest are optional or rejected in [§4f](package-manifest.md) |

### The 188 ours-only paths

All are attributed in the TSV. By package: nfs-utils 20 and samba4 19 (newer
Samba helpers); rt-tests 18; util-linux 11 (2.41-era tools); BusyBox 8
(`ascii`, `crc32`, `getfattr`, `ssl_server`, `traceroute6`, `tree`, `vmstat`,
`seedrng`); linux-tools 7 (`perf`); rootfs-overlay 7 (`mister-*` admin scripts,
jail launchers); iproute2 7; zstd 6; numactl 6; lrzsz 6; transmission 5; the
rest have 1–4 each. Two dangling symlinks are already documented:
`get_cyclictest_snapshot` and `hwlatdetect`.

## Findings from this pass (fixed in PR #283)

1. **`usr/bin/kill` had two installers.** Buildroot's `coreutils.mk` passes
   `--enable-install-program=kill,uptime`, and util-linux installs `kill` too.
   util-linux won only by install order, and nothing checked it. Stock's
   provider is util-linux. `external.mk` now drops `kill` from coreutils'
   install list whenever `BR2_PACKAGE_UTIL_LINUX_KILL=y`, and fails the build
   if `coreutils.mk` stops passing that exact option.
   - A second `--enable-no-install-program=kill` does not work: coreutils'
     configure aborts with "'kill' is both included and excluded".
   - `ci-tests.sh` asserts that `kill` is util-linux's ELF.
2. **gpm reported the build checkout's git tag as its version.** gpm's
   `autogen.sh` runs `git describe`. The release tarball has no `.git`, so git
   walked up into the Buildroot_MiSTer checkout, and `gpm -v` printed
   `gpm v2026.10.23-beta`. The build output therefore depended on the host's
   git state.
   - `board/mister/de10nano/patches/gpm/0002` makes autogen use the changelog,
     which gives `gpm 1.20.7`. `ci-tests.sh` asserts it.
   - Stock has the same class of leak. Its `jq` reports `jq-master-ba2b19c` and
     its `dtc` ends in `-gba2b19c8`, where `ba2b19c` is stock's own Buildroot
     tree describe (`/etc/os-release` `VERSION=-gba2b19c`). The table records
     the real source versions.
3. **coreutils path breakdown was miscounted in §4f.** The 105 paths are 84
   formerly BusyBox, 18 new, plus `[`, `kill` and `coreutils`. `chcon` and
   `runcon` are not built without libselinux.
4. **Local-build hygiene, not a repo defect.** The 6.18.60 kernel bump (#280)
   had left xone, rtl8852cu and aic8800 under `lib/modules/6.18.58`, and `perf`
   built from 6.18.58. The documented recipe was applied before this table was
   generated:
   - `<kmod>-dirclean`
   - remove the stale `linux-6.18.5{8,9}` build dirs
   - `make linux-rebuild all`

   `ci-tests.sh` then reported **389 passed, 0 failed**.

Appendix §E F1–F4 were fixed earlier in PR #283: the ifup/ifdown and util-linux
provider guards, the five util-linux collisions, and the getty/inittab text.
Still open, unchanged by this pass: the optional groups marked *Open* above,
plus the doc drift listed in appendix §G: F5 (wget NEEDED), F6 (stale `wget.mk`
citations), F7 (defconfig wording), BusyBox 1.37 text, 7-Zip 26.02 text and dead
`work/imgroot` citations.

## Per-package versions

Generated from the TSV, so the path counts are per side. Notes and evidence
for each package are in
[`package-versions.tsv`](stock-inventory/20260907/binary-recon/package-versions.tsv);
proof for each overridden path is in `stock-overrides.tsv`. Rows show a
version or snapshot hash as each source reports it.

| Package | Stock version (paths) | Ours version (paths) | Evidence |
|---|---|---|---|
| 7zip | — | 26.05 (3) | binary, both sides |
| alsa-lib | 1.2.4 (1) | 1.2.16.1 (1) | binary, both sides |
| alsa-utils | 1.2.4 (19) | 1.2.16 (18) | binary, both sides |
| bash | 5.0.18 (2) | 5.2.37 (2) | binary, both sides |
| bluez-tools | 97efd293491a (git snapshot) (5) | f65321736475429316f07ee94ec0deac8e46ec4a (5) | binary, both sides |
| bluez5_utils | 5.61 (46) | 5.86 (20) | binary, both sides |
| busybox | 1.33.1 (114) | 1.38.0 (126) | binary, both sides |
| bzip2 | 1.0.8 (11) | 1.0.8 (11) | binary, both sides |
| cifs-utils | — | 7.7 (3) | show-info / `.mk` |
| coreutils | 8.32 (107) | 9.10 (105) | binary, both sides |
| cpuload | 0.3 (1) | — | binary, per path |
| dash | 0.5.11.3 (1) | — | binary, per path |
| dbus | 1.12.20 (10) | 1.16.2 (10) | binary, both sides |
| dbus-cpp | 0.9.0 (2) | 0.9.0 (2) | binary, both sides |
| dbus-glib | 0.110 (1) | 0.114 (1) | binary, both sides |
| dbus-triggerd | ba3dbec805cb707c94c54de21666bf18b79bcc09 (1) | — | binary, per path |
| dhcpcd | 9.4.0 (2) | 10.2.4 (2) | binary, both sides |
| dialog | 1.3-20200327 (1) | 1.3-20251001 (1) | binary, both sides |
| dos2unix | 7.4.1 (4) | 7.5.5 (4) | binary, both sides |
| dosfstools | 4.1 (10) | 4.2 (10) | binary, both sides |
| dstat | 0.8.0 (1); 0.7.4 (1) | — | binary, per path |
| dtc | 1.6.0 (7) | 1.7.2 (7) | binary, both sides |
| dualsensectl | — | v0.7 (1) | show-info / `.mk` |
| e2fsprogs | 1.45.6 (27) | 1.47.4 (23) | binary, both sides |
| e2tools | 0.0.16.4 (7) | — | binary, per path |
| ed | 1.16 (2) | — | binary, per path |
| edid-decode | 188950472c19492547e298b27f9da0d72cf826df (1) | — | binary, per path |
| ethtool | 5.10 (1) | 7.1 (1) | binary, both sides |
| eudev | 3.2.9 (10) | 3.2.14 (11) | binary, both sides |
| evtest | — | 1.36 (1) | show-info / `.mk` |
| exfatprogs | 1.0.4 (3) | 1.2.9 (6) | binary, both sides |
| expat | 2.4.1 (1) | — | binary, per path |
| fbgrab | 1.4 (1) | — | binary, per path |
| fbv | 1.0b (1) | — | binary, per path |
| file | 5.38 (1) | 5.47 (1) | binary, both sides |
| findutils | 4.7.0 (5) | 4.10.0 (5) | binary, both sides |
| fluidsynth | 2.1.6 (1) | 2.5.7 (2) | binary, both sides |
| fping | 5.0 (1) | — | binary, per path |
| ftop | 1.0 (1) | — | binary, per path |
| gdb | 9.2 (4) | 16.3 (5) | binary, both sides |
| glibc | 2.31 (3) | 2.44-57-g34106fee698c83eb0af71d4d0381e66b399be746 (1) | binary, per path |
| gobject-introspection | 1.64.1 (5) | 1.86.0 (5) | binary, both sides |
| gpm | 1.20.7 (3) | 1.20.7 (3) | binary, both sides |
| gzip | 1.10 (14) | 1.14 (14) | binary, both sides |
| htop | 3.0.5 (git ce6d60e7def146c13d0b8bca4642e7401a0a8995) (1) | 3.5.1 (1) | binary, both sides |
| i2c-tools | 4.2 (11) | 4.4 (11) | binary, both sides |
| ifupdown | 0.8.16 (5) | 0.8.44 (6) | binary, both sides |
| imlib2 | 1.6.1 (2) | 1.12.5 (2) | binary, both sides |
| inotify-tools | 3.20.2.2 (2) | 3.20.2.2 (2) | binary, both sides |
| iostat | 2.2 (1) | — | binary, per path |
| iotop | 0.6 (1) | — | binary, per path |
| iperf3 | — | 3.21 (1) | show-info / `.mk` |
| iproute2 | 5.7.0 (iproute2-ss200602) (13); 5.7.0 (3) | 7.1.0 (20) | binary, both sides |
| iptables | 1.8.6 (16) | 1.8.11 (16) | binary, both sides |
| iputils | 20210202 (6) | 20250605 (5) | binary, both sides |
| iw | 5.9 (1) | 6.17 (1) | binary, both sides |
| jimtcl | 0.79 (2) | 0.83 (2) | binary, both sides |
| joe | 4.6 (5) | 4.6 (5) | binary, both sides |
| jq | a17dd3248a66 (git snapshot) (1) | 1.8.2 (1) | binary, both sides |
| kbd | 2.3.0 (25) | 2.9.0 (25) | binary, both sides |
| keyutils | — | 1.6.3 (4) | show-info / `.mk` |
| kmod | 28 (7) | 34.2 (7) | binary, both sides |
| less | 563 (1) | 704 (4) | binary, both sides |
| lftp | 4.9.2 (2) | 4.9.3 (2) | binary, both sides |
| libcap | — | 2.78 (2) | show-info / `.mk` |
| libcap-ng | 0.8.2 (4) | 0.9.3 (3) | binary, both sides |
| libcurl | 7.78.0 (1) | 8.22.0 (2) | binary, both sides |
| libdeflate | — | 1.25 (2) | show-info / `.mk` |
| libevdev | 1.11.0 (3) | 1.13.5 (3) | binary, both sides |
| libevent | 2.1.12 (1) | 2.1.13 (1) | binary, both sides |
| libfuse | — | 2.9.9 (1) | show-info / `.mk` |
| libgcrypt | 1.9.3 (3) | 1.12.2 (3) | binary, both sides |
| libglib2 | 2.66.8 (6) | 2.88.3 (10) | binary, both sides |
| libgpg-error | 1.41 (2) | 1.61 (2) | binary, both sides |
| libhid | 0.2.16 (1) | — | binary, per path |
| libinput | 1.16.4 (18) | 1.31.3 (15) | binary, both sides |
| liblockfile | — | 1.17 (1) | show-info / `.mk` |
| libminiupnpc | — | 2.3.3 (1) | show-info / `.mk` |
| libnatpmp | — | 20230423 (1) | show-info / `.mk` |
| libopenssl | 1.1.1k (1) | 3.6.5 (1) | binary, both sides |
| libpsl | — | 0.21.5 (2) | show-info / `.mk` |
| libtasn1 | 4.17.0 (3) | — | binary, per path |
| libutp | — | c95738b1a6644b919e5b64d3ea9736cfc5894e0b (1) | show-info / `.mk` |
| libxkbcommon | 1.0.3 (4) | — | binary, per path |
| libxml2 | 2.9.12 (2) | 2.15.4 (2) | binary, both sides |
| linux-pam | 1.5.1 (8) | 1.7.2 (8) | binary, both sides |
| linux-tools | — | 6.18.60 (7) | show-info / `.mk` |
| linuxconsoletools | 1.7.0 (14) | 1.8.1 (14) | binary, both sides |
| lockfile-progs | 0.1.18 (7) | 0.1.19 (7) | binary, both sides |
| lrzsz | 0.12.21rc (2) | 0.12.21rc (8) | binary, both sides |
| lshw | 02.19.2 (1) | — | binary, per path |
| lsof | — | 4.99.6 (1) | show-info / `.mk` |
| ltunify | — | b68dc9af6db53de231d5ac71f9b6ba2ff3057a68 (1) | show-info / `.mk` |
| lvm2 | — | 2.03.31 (4) | show-info / `.mk` |
| lzo | 2.10 (4) | 2.10 (4) | binary, both sides |
| lzop | 1.03 (1) | 1.04 (1) | binary, both sides |
| mc | 4.8.25 (70) | 4.8.33 (73) | binary, both sides |
| memstat | 1.0 (1) | — | binary, per path |
| memtool | 2018.03.0 (3) | 2018.03.0 (3) | binary, both sides |
| midilink | — | d6b337383d10dc5048b22eb5d27baf61826f6bb1 (2) | binary, both sides |
| minijail | — | linux-v2026.05.18 (1) | show-info / `.mk` |
| mksh | 59c (1) | — | binary, per path |
| modplugtools | 0.5.3 (2) | — | binary, per path |
| mpg123 | 1.25.15 (4) | 1.33.7 (4) | binary, both sides |
| mtdev | 1.1.6 (1) | 1.1.7 (1) | binary, both sides |
| munt | — | munt_2_8_2 (1) | binary, both sides |
| nano | 5.5 (1) | 9.0 (1) | binary, both sides |
| ncurses | 6.1 (10) | 6.6-20251231 (10) | binary, both sides |
| net-tools | 2.10-alpha (git 479bb4a7) (16) | 2.10 (16) | binary, both sides |
| netcat | 0.7.1 (2) | — | binary, per path |
| netstat-nat | 1.4.10 (1) | — | binary, per path |
| nettle | 3.7.3 (5) | 3.10.2 (5) | binary, both sides |
| newt | 0.52.21 (1) | 0.52.25 (1) | binary, both sides |
| nfs-utils | — | 2.9.1 (20) | show-info / `.mk` |
| nftables | — | 1.1.4 (1) | show-info / `.mk` |
| ntfs-3g | 2017.3.23 (19) | 2026.7.7 (19) | binary, both sides |
| ntp | 4.2.8p15 (7) | 4.2.8p18 (1) | binary, both sides |
| numactl | — | 2.0.19 (6) | show-info / `.mk` |
| openssh | 8.6p1 (12) | 10.6p1 (14) | binary, both sides |
| p7zip | 16.02 (1) | — | binary, per path |
| parted | 3.3 (2) | 3.6 (2) | binary, both sides |
| pcre | 8.44 (2) | — | binary, per path |
| pcre2 | — | 10.49 (2) | show-info / `.mk` |
| perl | 5.32.1 (30) | — | binary, per path |
| picocom | 3.1 (1) | 2024-07 (1) | binary, both sides |
| pppd | 2.4.8 (7) | — | binary, per path |
| proftpd | 1.3.6e (2) | 1.3.9d (1) | binary, both sides |
| python-chardet | 4.0.0 (1) | — | binary, per path |
| python-docutils | 0.15.2 (12) | — | binary, per path |
| python-setuptools | 44.0.0 (2) | — | binary, per path |
| python3 | 3.9.6 (7) | 3.14.8 (4) | binary, both sides |
| read-edid | 3.0.2 (2) | — | binary, per path |
| rsync | 3.1.3 (1) | 3.5.0 (2) | binary, both sides |
| rt-tests | — | 2.8 (18) | show-info / `.mk` |
| rtorrent | 0.9.8 (1) | — | binary, per path |
| samba4 | 4.14.6 (86) | 4.24.6 (102) | binary, both sides |
| screen | 4.8.0 (1) | — | binary, per path |
| slang | 2.3.2 (7) | — | binary, per path |
| socat | 1.7.4.1 (3) | 1.8.1.3 (7) | binary, both sides |
| spi-tools | 0.8.4 (2) | 1.0.2 (2) | binary, both sides |
| sqlite | — | 3.53.4 (1) | show-info / `.mk` |
| start-stop-daemon | 1.18.10 (1) | — | binary, per path |
| strace | — | 7.1 (2) | show-info / `.mk` |
| sudo | 1.9.5p2 (16) | 1.9.17p2 (16) | binary, both sides |
| tar | 1.32 (2) | 1.35 (2) | binary, both sides |
| tcpdump | — | 4.99.6 (1) | show-info / `.mk` |
| tmux | 3.1c (1) | 3.6b (1) | binary, both sides |
| transmission | — | 4.1.3 (5) | show-info / `.mk` |
| unrar | 5.9.4 (1) | — | binary, per path |
| unzip | 6.0 (1) | 6.0 (1) | binary, both sides |
| usb_modeswitch | 2.6.1 (3) | 2.6.2 (3) | binary, both sides |
| usbmount | 0.0.22 (1) | 0.0.22 (1) | show-info / `.mk` |
| usbutils | 013 (3) | 019 (4) | binary, both sides |
| util-linux | 2.36.2 (78) | 2.41.5 (88) | binary, both sides |
| vim | 8.2.0000 (19) | — | binary, per path |
| vorbis-tools | 1.4.2 (6) | — | binary, per path |
| wget | 1.20.3 (1) | 1.25.0 (1) | binary, both sides |
| which | 2.21 (1) | — | binary, per path |
| whois | 5.5.7 (2) | 5.6.5 (2) | binary, both sides |
| wireless_tools | 30.pre9 (5) | 30.pre9 (5) | binary, both sides |
| wpa_supplicant | 2.9 (3) | 2.12 (3) | binary, both sides |
| xz | 5.2.5 (23) | 5.8.4 (23) | binary, both sides |
| zip | 3.0 (4) | 3.0 (4) | binary, both sides |
| zsh | 5.8 (10) | — | binary, per path |
| zstd | — | 1.5.7 (6) | show-info / `.mk` |

## Appendix — pre-Tier-1 audit (2026-10-31)

> Read-only audit performed 2026-10-31 against the verified
> `release_20260907` image and the then-current `output/target`. This is the
> **pre-fix snapshot**: the audit itself made no repository changes. The
> Tier 1 + BlueZ provider fixes were implemented in PR #283 (open at the time
> this document was committed); the top of this page is the
> post-fix state.

### Scope and evidence

- **Stock**: the verified `release_20260907` `linux.img` (`MiSTer.version` =
  `260907`), i.e. `rootfs.tar.bz2` + `modules.tar.gz` + `firmware.tar.gz` +
  `addon.tar`.
- **Ours**: `output/target` (same tree as `output/images/rootfs.tar`).
- **Methods**: path/provider inventory of every file/symlink under `usr/bin`,
  `usr/sbin`, `usr/libexec`, `libexec` plus every ELF executable anywhere;
  symlink-chain resolution; BusyBox `--list` / `--list-full`; `readelf -h/-d`
  on all 1,512 ELF objects; qemu-arm execution for option/version checks; docs
  cross-check.
- **Baseline correction**: the initially supplied extracted tree was the
  **`rootfs.tar.bz2` member set only**, not the shipped image. It lacks
  `addon.tar` and therefore 25 executable-dir paths. Of those, 19 are shipped
  by us as real binaries (not BusyBox) and 6 are documented declines
  (`adplay`, `archivemount`, `fpga`, `vgmplay`, `VGMPlay.ini`, `mikmod`).
  Counts below are corrected to the shipped image.

### Headline matrix (pre-Tier-1)

| Relation | Count |
|---|---:|
| Stock real provider → ours BusyBox | **114** |
| Stock real/file provider → absent in ours | **225** (219 base-rootfs + 6 addon) |
| Stock BusyBox provider → absent in ours | **1** (`getty`) |
| Stock BusyBox provider → ours real binary | **1** (`lsof`, documented upgrade) |
| Both BusyBox | **111** |
| Same-path ELF↔ELF | **484 rows / 418 objects** |
| Same-path script↔script | **96** |
| Net-new ours paths | **195** after addon correction (all attributed) |

Stock executable-dir surface is **1,055** entries (1,030 executable-class),
identical between 20250402 and 20260907.

### A. 114 stock-real → BusyBox substitutions

| Stock provider | Rows | Baseline | Documented | At-risk/undocumented |
|---|---:|---:|---:|---:|
| GNU coreutils 8.32 | 85 | 77 | 8 (T5) | 0 |
| GNU findutils 4.7.0 | 2 | 0 | 0 | **2** |
| net-tools 2.10-alpha | 6 | 2 | 0 | **4** |
| net-tools hostname aliases | 2 | 2 | 0 | 0 |
| iputils 20210202 | 3 | 1 | 1 (`ping6`) | **1** |
| GNU gzip 1.10 | 3 | 0 | 3 | 0 |
| Info-ZIP UnZip 6.00 | 1 | 0 | 0 | **1** |
| less 563 | 1 | 0 | 0 | **1** |
| vim 8.2 | 1 | 0 | 1 (`vi`) | 0 |
| dos2unix 7.4.1 | 2 | 0 | 0 | **2** |
| GNU Netcat 0.7.1 | 2 | 0 | 2 (`nc`) | 0 |
| ncurses 6.1 (`clear`,`reset`) | 2 | 2 | 0 | 0 |
| whois 5.5.7 (`mkpasswd`) | 1 | 0 | 0 | **1** |
| GNU which 2.21 | 1 | 1 | 0 | 0 |
| xxd V1.10 | 1 | 1 | 0 | 0 |
| dpkg start-stop-daemon | 1 | 0 | 1 | 0 |
| **Total** | **114** | **86** | **16** | **12** |

The 86 baseline rows are BusyBox-as-base-userland, documented only at policy
level (`docs/package-manifest.md:503`,
`docs/buildroot-config.md:1474-1480`,
`docs/stock-reconciliation.md:531-536`); there is no per-path decision. The 16
documented rows are the T5 coreutils applets + `nc`/`netcat` + `vi` + `ping6` +
gzip/gunzip/zcat + `start-stop-daemon`.

#### 12 accidental/at-risk substitutions (no written decision; BusyBox rejects stock options)

| Path | Stock | Demonstrated BusyBox gap | Impact |
|---|---|---|---|
| `usr/bin/less` | less 563 | rejects `-p`, `-r`, `-k`; ignores `LESSKEY` | **Highest.** Main's `.txt` doc viewer execs `less` and Distribution ships `/media/fat/linux/lesskey` (`docs/abi-contract.md:992`, Main `menu.cpp:3384`); custom keys are silently ignored |
| `usr/bin/find` | GNU findutils 4.7.0 | rejects `-printf`, `-delete`, `-ls`, `-newermt` | Script-visible |
| `usr/bin/xargs` | GNU findutils 4.7.0 | rejects `-d` | Script-visible |
| `usr/bin/netstat` | net-tools 2.10-alpha | rejects `-p`, `-s`, `-i` | Network diagnostics |
| `usr/sbin/ifconfig` | net-tools 2.10-alpha | rejects `-s` | Network diagnostics |
| `usr/sbin/route` | net-tools 2.10-alpha | rejects `-V` | Network diagnostics |
| `usr/sbin/arp` | net-tools 2.10-alpha | rejects `-f` | Network diagnostics |
| `usr/bin/ping` | iputils 20210202 | rejects `-M` | Script-visible |
| `usr/bin/unzip` | Info-ZIP 6.00 | rejects `-P`; hard-dies on encrypted entries | Archival |
| `usr/bin/dos2unix` | dos2unix 7.4.1 | rejects `-k` | Low |
| `usr/bin/unix2dos` | dos2unix 7.4.1 | same | Low |
| `usr/bin/mkpasswd` | whois 5.5.7 | rejects `-R` | Low |

This is the same shape as the already-fixed GNU wget (#130) and GNU tar (#279)
regressions: stock's real ELF owned the path; BusyBox covers the name with a
narrower tool.

### B. 226 stock entries absent in ours

Of 226 absent entries: **207 executable/script/symlink** (71 accounted,
**136 unaccounted**) and 19 non-executable (2 libraries/plugins, 16 mc data
files, `VGMPlay.ini`).

#### Accounted (71 executable + 1 data)

| Group | Count | Disposition |
|---|---:|---|
| perl | 32 | documented drop |
| vim | 6 | documented drop |
| screen | 1 | documented drop |
| unrar | 1 | documented rejection |
| rtorrent | 1 | dropped; capability restored by transmission |
| getty | 1 | documented divergence; `agetty` present |
| libhid | 1 | documented drop |
| ppp | 7 | documented gap (§4b) |
| modplug | 1 | documented gap (§4b) |
| vorbis | 6 | documented gap (§4b) |
| pcre | 2 | PCRE2 substitution |
| Samba renames | 3 | `mdsearch`, `ctdb_smnotify_helper` |
| Python versioned | 3 | 3.9 → 3.14 |
| zsh | 1 | documented drop |
| addon declines | 5 | adplay, archivemount, fpga, vgmplay, mikmod (+ `VGMPlay.ini`) |

#### 136 unaccounted missing executables

| Group | Count | Examples |
|---|---:|---|
| coreutils | 21 | `pr`, `join`, `csplit`, `stdbuf`, `users`, `vdir`, `sha224sum`, `b2sum`, `basenc`, `numfmt`, `pathchk`, `pinky`, `ptx`, `sum`, `unexpand`, `chcon`, `runcon`, `dir`, `dircolors`, `fmt`, `coreutils` |
| Python third-party | 16 | `rst2*` (12), `easy_install`, `chardetect`, `dstat`, `iotop` |
| gzip helpers | 11 | `zgrep`, `zless`, `zcmp`, `zdiff`, `zmore`, `znew`, `zforce`, `gzexe`, `uncompress`, `zegrep`, `zfgrep` |
| ncurses target progs | 8 | `tic`, `infocmp`, `tput`, `tset`, `toe`, `tabs`, `captoinfo`, `infotocap` |
| e2tools | 7 | `e2cp`/`e2ls`/`e2mkdir`/`e2mv`/`e2rm`/`e2ln`/`e2tail` |
| libinput tools | 7 | measure/replay/analyze scripts |
| NTP clients | 6 | `ntpq`, `ntpdc`, `ntpdate`, `ntptime`, `ntp-keygen`, `tickadj` |
| net-tools | 6 | `mii-tool`, `rarp`, `raw`, `slattach`, `plipconfig`, `ipmaddr` |
| xkb | 4 | `xkbcli` + 3 libexec helpers |
| bluez | 3 | `btmon`, `btmgmt`, `hid2hci` |
| e2fsprogs | 3 | `e2scrub`, `e2scrub_all`, `e4defrag` |
| hostname aliases | 3 | `domainname`, `nisdomainname`, `ypdomainname` |
| iputils | 3 | `clockdiff`, `tracepath`, `rdisc` |
| iproute2 legacy | 3 | `ifcfg`, `routef`, `rtpr` |
| libtasn1 | 3 | `asn1Coding`, `asn1Decoding`, `asn1Parser` |
| mlocate | 3 | `locate`, `updatedb`, `frcode` |
| dos2unix aliases | 2 | `mac2unix`, `unix2mac` |
| ed | 2 | `ed`, `red` |
| misc | 19 | **`openssl` CLI**, `lshw`, `fping`, `dash`, `mksh`, `fbv`, `fbgrab`, `edid-decode`, `get-edid`, `parse-edid`, `xmlwf`, `em`, `ftop`, `memstat`, `cpuload`, `slsh`, `whois`, `alsaconf`, `ldd` |
| single-path groups | 6 | `captest`, `dbus-triggerd`, `ipcmk`, `netstat-nat`, `iostat`, `unix_update` |

Notable contradictions: `usr/bin/ipcmk` was claimed installed
(`docs/util-linux-parity.md:38`) but `UTIL_LINUX_IPCMK` was off;
`usr/sbin/alsaconf` is claimed never shipped
(`docs/buildroot-config.md:845-846`) but both stock images ship it;
`usr/bin/openssl` was absent because `BR2_PACKAGE_LIBOPENSSL_BIN` was off
(`output/.config:2450`) with no written decision.

### C. Applets, reverse substitutions, extras

- Stock BusyBox 1.33.1: **274** applets; ours 1.38.0: **260**.
  `274 − 37 + 23 = 260`.
- **37 stock-only applet paths**: 36 are answered by the same real package at
  the same path (util-linux, kbd, ifupdown, lsof, lsusb, mkdosfs, GNU wget,
  GNU tar, iproute2). **Only `getty` is lost**: stock `/usr/sbin/getty` was a
  BusyBox symlink used by stock's inittab
  (`console::respawn:/sbin/getty ...`); ours has no `getty`, only `agetty`,
  and our inittab calls agetty. The `busybox getty` spelling is gone.
- **23 ours-only applet paths**: 10 documented T5 substitutions;
  `ping6`/`traceroute6` documented (#188); `lsblk`/`uuidgen` are compiled in
  but shadowed by util-linux in both trees; `seedrng` is required by
  Buildroot's `S01seedrng`; **8 undocumented**: provider swaps `sha384sum`,
  `tsort`; new commands `vmstat`, `ascii`, `crc32`, `getfattr`, `ssl_server`,
  `tree`.
- **Reverse**: only `usr/bin/lsof` (stock BusyBox → ours real lsof 4.99.6),
  documented upgrade.
- **Extras**: 195 net-new paths after addon correction, all attributed (T5,
  debug/RT tooling, servers, addon/T3 payloads, mc 4.8.33, transmission, glib,
  lrzsz, socat helpers). Defects: `usr/libexec/mc/extfs.d/torrent` shebang
  points at the build-host Python; `usr/bin/get_cyclictest_snapshot` is a
  dangling symlink like the documented `hwlatdetect`; `ssl_server` is an
  undocumented BusyBox TLS listener.

### D. Same-path ELF metadata

- 484 same-path pairs / 418 distinct objects: 413 (98.8%) have a changed
  `DT_NEEDED` set.
- **No in-image runtime risk.** 101 stock SONAMEs are absent by name; all are
  either still provided under the same SONAME (15) or replaced by a present
  successor the rebuilt consumer NEEDs (86: Samba `samba4`→`private-samba`
  renames/merges, OpenSSL 1.1→3, libcrypt .1→.2, ntfs-3g .88→.90,
  libxml2 .2→.16, libndr .1→.6, Python 3.9→3.14, PCRE1→PCRE2). Zero with no
  successor.
- **Dangling NEEDED**: ours **0** (verified by SONAME/basename and loader
  reachability over all 1,512 ELF objects); stock has the 3 documented
  (`archivemount`: libarchive/libfuse; `libjack`: libdb-5.3), though its broken
  consumers are addon-only and not shipped.
- **PIE**: ours 538/538; stock 85/524. 342 EXEC→PIE, expected from
  `BR2_PIC_PIE=y`; interpreter path unchanged (`/lib/ld-linux-armhf.so.3`),
  glibc 2.31→2.44. `DT_RPATH`→`DT_RUNPATH` (new-dtags), harmless.
- Size: same-path total 48.7 MB → 55.2 MB (+13.4%); 31 outliers ≥2×/≤0.5×,
  11 with ≥200 KB delta.
- Metadata substitution candidates: `7zr` (p7zip 16.02 ELF → symlink to 7zz;
  binary reports 26.05, docs say 26.02), `socat` (→ `socat1`), `python3`
  3.9→3.14.

### E. Documented-collision audit failures

1. **F1** No CI guard for `usr/sbin/ifup`/`ifdown`.
2. **F2** No provider guard for any of the 25 util-linux paths; the only check
   (`flock`, `ci-tests.sh:1491`) is presence-only and a BusyBox symlink would
   pass.
3. **F3** Util-linux de-confliction was incomplete: BusyBox applets `fsck`,
   `lsblk`, `uuidgen`, `linux32`, `linux64` remained enabled while util-linux
   owned those paths. Util-linux won in this tree, but the fragment violated
   its own "turn off every colliding applet" policy
   (`docs/util-linux-parity.md:59-63,131-132`).
4. **F4** Fragment claim "stock ships the real util-linux ELF versions of all
   tools below" is false for `getty`: stock `/usr/sbin/getty -> ../bin/busybox`;
   util-linux's tool is `agetty`. `docs/util-linux-parity.md` also incorrectly
   says stock's inittab runs agetty; stock's inittab line 31 runs `/sbin/getty`.
5. **F5** Wget docs (`package-manifest.md:884`, `buildroot-config.md:905-906`)
   say libpsl/libidn2 are absent; built wget NEEDs `libpsl.so.5` and
   `libidn2.so.0`, banner `+psl +iri`.
6. **F6** Stale `wget.mk` line citations (actual 27/37/59/66/80 vs cited
   16/26/46/53/67).
7. **F7** "`BR2_PACKAGE_WGET=y` in the defconfig" is stale; it is selected by
   `package/mister-userspace/Config.in:99`.

### F. Stock drift 20250402 → 20260907

- Executable surface: **0 paths added, 0 removed, 0 type/symlink-target
  changes**; all 330 symlink targets identical.
- **41** userland files changed bytes. `stock-userland-added.txt` confirmed
  (5 paths). `stock-userland-changed.txt` is valid but incomplete: misses
  `libpython3.9.so.1.0`, perl `Config_heavy.pl`, and `pbr.json` (38 vs 41).
- Coverage of the 41: 22 covered, **1 BusyBox-only (`unzip`)**, **10 missing
  executables** — `ntpq`/`ntpdc`/`ntpdate`/`ntp-keygen`/`ntptime`
  **undocumented** (manifest maps only `ntpd`, `docs/package-manifest.md:494`;
  all NTP sub-options off), plus `perl`/`perlbug`/`perlthanks`/`vim`/
  `modplug123` (documented) — 4 SONAME-compatible library replacements, 2 n/a,
  2 expected (`MiSTer.version`, `etc/shadow`).

### G. Documentation drift found along the way

- `buildroot-config.md:1789` still says "three" BusyBox collisions (seven +
  wget + tar are recorded elsewhere).
- `package-manifest.md:503,661` say BusyBox 1.37.0; image is 1.38.0.
- `docs/dwc2-usb-irq/README.md:123` still says BusyBox tar has no `-z`
  (fixed in #282).
- `work/imgroot` citations are dead (`work/imgroot` does not exist); the
  shipped image is the authoritative reference.
- 7-Zip version: docs say 26.02; binary banner says 26.05.
