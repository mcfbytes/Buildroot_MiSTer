# Stock binary reconciliation — stock 20260907 vs. pre-Tier-1 image

> Read-only audit performed 2026-10-31 against the verified
> `release_20260907` image and the then-current `output/target`. This is the
> **pre-fix snapshot**: the audit itself made no repository changes. The
> Tier 1 + BlueZ provider fixes were implemented in PR #283 (open at the time
> this document was committed); see [Follow-up status](#follow-up-status-2026-11-01)
> for what that closes and what remains.

## Scope and evidence

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

## Headline matrix (pre-Tier-1)

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

## A. 114 stock-real → BusyBox substitutions

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

### 12 accidental/at-risk substitutions (no written decision; BusyBox rejects stock options)

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

## B. 226 stock entries absent in ours

Of 226 absent entries: **207 executable/script/symlink** (71 accounted,
**136 unaccounted**) and 19 non-executable (2 libraries/plugins, 16 mc data
files, `VGMPlay.ini`).

### Accounted (71 executable + 1 data)

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

### 136 unaccounted missing executables

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

## C. Applets, reverse substitutions, extras

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

## D. Same-path ELF metadata

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

## E. Documented-collision audit failures

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

## F. Stock drift 20250402 → 20260907

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

## G. Documentation drift found along the way

- `buildroot-config.md:1789` still says "three" BusyBox collisions (seven +
  wget + tar are recorded elsewhere).
- `package-manifest.md:503,661` say BusyBox 1.37.0; image is 1.38.0.
- `docs/dwc2-usb-irq/README.md:123` still says BusyBox tar has no `-z`
  (fixed in #282).
- `work/imgroot` citations are dead (`work/imgroot` does not exist); the
  shipped image is the authoritative reference.
- 7-Zip version: docs say 26.02; binary banner says 26.05.

## Follow-up status (2026-11-01)

Tier 1 + BlueZ were implemented in PR #283. In that build:

- **Provider substitutions:** 108 of the 114 are closed. Six remain:
  `nc`, `netcat` (deliberate BusyBox substitution), `vi` (vim drop), `which`,
  `xxd`, `start-stop-daemon`.
- **Missing paths:** the real/file absent count drops from 225 to **166**
  (160 base-rootfs + 6 documented addon declines); total absent entries
  226 → 167 including `getty`. Closed: coreutils 21, gzip 11, ncurses 8,
  OpenSSL CLI, `ipcmk`, net-tools 5 of 6 (`raw` remains unbuildable), iputils
  2 of 3 (`rdisc` remains), BlueZ `btmon`/`hid2hci`, and mlocate's
  `locate`/`updatedb`/`frcode` via findutils.
- **At-risk providers:** `less`, `find`, `xargs`, `netstat`, `ifconfig`,
  `route`, `arp`, `ping`, `unzip`, `dos2unix`, `unix2dos`, `mkpasswd` are all
  real packages now. `kill` resolves to util-linux as on stock.
- **Hygiene:** F3's five util-linux applet collisions are fixed; F1/F2 provider
  guards were added to `scripts/ci-tests.sh`; the false getty/stock-inittab
  claim and the five-applet util-linux text were corrected.
- **Still open:** optional NTP clients, e2tools/e4defrag/e2scrub, fping,
  ed/fbv/fbgrab/edid/xkb/libinput, lshw, dash/mksh; `btmgmt` (built by BlueZ,
  not installed by Buildroot 5.86); `raw` (unbuildable with headers ≥5.14);
  `rdisc` (not in iputils 20250605). Remaining doc drift: F5 wget NEEDED table,
  F6 stale `wget.mk` citations, F7 defconfig wording, BusyBox 1.37 text,
  7-Zip 26.02 text, dead `work/imgroot` citations.

The session-local manifests and per-slice reports were not committed; every
count here is reproducible from the two images with the methods above.
