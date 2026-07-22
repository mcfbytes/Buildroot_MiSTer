# Package manifest — stock SONAME/binary → Buildroot mapping

Task: **P0.7**. Deliverable consumed directly by **P2.1** (full package set) and the
version-jump risk owners **P3.6** (Samba), **P3.7** (SSH/FTP), **P3.9** (Python).

> **Which Buildroot this describes (read first).** The mapping below was *established*
> against **2026.02.3** — that is the tree every "verified by reading the file" claim
> here was read from. **The image now ships Buildroot 2026.05.1** (bumped by hand in
> PR #54). Rows touched by that bump have been updated in place and say so inline; the
> clearest case is PCRE1, removed upstream in 2026.05 and consequently dropped here
> (see the `libpcre.so.1` / `libpcreposix.so.0` rows). Untouched rows still carry their
> 2026.02.3 provenance, which is the honest thing for them to carry — a version string
> re-typed without re-reading the file would be worth less than a dated one.
>
> **What is *not* trusted to this document:** the ABI contract itself. `scripts/check-abi.sh`
> re-derives the SONAME/loader checklist from the **built image** on every CI run, so
> the 12-SONAME guarantee is machine-verified against whatever Buildroot is actually
> pinned, whatever this file says.

**Buildroot ref this mapping was read from:** branch `2026.02.x` @ commit
`679b9ead7620bbf193620d1ebf56f53c1764d37a` = tag **`2026.02.3`**, cloned
`--depth 1` into `work/buildroot` (gitignored, not committed — standing rule 1).
GitLab canonical remote: `https://gitlab.com/buildroot.org/buildroot.git`.

**Method.** Every mapping below was verified by reading the actual file in the pinned
tree: the package's `package/<name>/Config.in` for the exact `BR2_PACKAGE_*` symbol
(and any load-bearing sub-options), and its `package/<name>/<name>.mk` for the
`<NAME>_VERSION` (or `<NAME>_VERSION_MAJOR`) that Buildroot 2026.02 actually ships.
Nothing here is from memory. Where a SONAME's major-version stability across the
version jump could not be settled from the Buildroot tree alone (bluez, imlib2,
libtiff, libffi), it was additionally cross-checked against current (2026) Arch/Debian
package metadata — cited inline.

Input set: the **251** distinct SONAMEs in `docs/stock-inventory/binaries-needed-union.txt`
(P0.3). **All 251 are accounted for below — zero unmapped.**

---

## Headline finding: the 12-SONAME ABI contract survives intact

PLAN §3 states the stock `MiSTer` binary's 12 `DT_NEEDED` entries are the load-bearing
ABI contract and "every one of these SONAMEs must be present with the same major
version." Verified against the pinned Buildroot 2026.02.3 tree (plus current-distro
cross-checks for the two riskiest ones):

| # | SONAME | Same major in 2026.02? | Evidence |
|---|---|---|---|
| 1 | `libc.so.6` | **yes** | glibc 2.42; `libc.so.6` is symbol-versioned and has never bumped its SONAME (this is *why* glibc ABI compat works at all — old binaries linked against `libc.so.6` from 1997 still run against today's glibc) |
| 2 | `libstdc++.so.6` | **yes** | GCC 14.3.0 (default); frozen at `.so.6` since GCC 3.4 (2004) |
| 3 | `libm.so.6` | **yes** | glibc 2.42, same file as libc |
| 4 | `librt.so.1` | **yes** | glibc 2.42 |
| 5 | `libpthread.so.0` | **yes** | glibc 2.42 — note: glibc ≥2.34 merged pthread into `libc.so.6` itself, but still installs an empty `libpthread.so.0` compat stub, so the SONAME still resolves for anything that `DT_NEEDS` it |
| 6 | `libgcc_s.so.1` | **yes** | GCC 14.3.0 toolchain runtime |
| 7 | `libfreetype.so.6` | **yes** | `BR2_PACKAGE_FREETYPE` 2.14.3; frozen at `.so.6` since FreeType 2.0 |
| 8 | `libbz2.so.1.0` | **yes** | `BR2_PACKAGE_BZIP2` 1.0.8, unchanged since 2000 |
| 9 | `libpng16.so.16` | **yes** | `BR2_PACKAGE_LIBPNG` 1.6.58 — the "16" is libpng's parallel-install branch tag, part of the package's identity |
| 10 | `libz.so.1` | **yes** | `BR2_PACKAGE_LIBZLIB` 1.3.2 (default provider under the `BR2_PACKAGE_ZLIB` choice) |
| 11 | `libImlib2.so.1` | **yes** | `BR2_PACKAGE_IMLIB2` 1.12.5. **Specifically checked per the task's flag** — current Arch `imlib2` 1.12.6-1 sonames page still lists only `libImlib2.so.1` |
| 12 | `libbluetooth.so.3` | **yes** | `BR2_PACKAGE_BLUEZ5_UTILS` 5.79. **Specifically checked per the task's flag** — current Arch `bluez-libs` package `Provides: libbluetooth.so=3`; Debian/Ubuntu still name the runtime package `libbluetooth3` at recent bluez versions |

**No project-threatening ABI break exists in this set.** This is the single most
important fact this task turned up: nothing forces a redesign of the ABI-parity
strategy in PLAN §3. The two libraries PLAN itself flagged as most likely to have
moved (bluez, imlib2) did not move.

Two *non-critical* SONAMEs elsewhere in the 251-set **did** bump major version
(`libtiff.so.5→6`, `libffi.so.7→8`) plus one big one (OpenSSL `.so.1.1`→`.so.3`,
not in the 12-set either). None of these matter for us because we rebuild every
consumer from source against the new libraries — a version bump only bites when a
*pre-built* binary expects the old SONAME, and the only pre-built binary we carry
forward unmodified is `MiSTer` itself, whose 12 dependencies are all confirmed above.
See the per-library notes in the tables below.

---

## 1. SONAME → Buildroot package (all 251, zero unmapped)

Columns: **SONAME** | **stock realfile** (version hint, from `shared-libraries.md`) |
**Buildroot package** (`BR2_PACKAGE_*` symbol, cited from `Config.in`) |
**BR 2026.02.3 version** (cited from the package's `.mk`) | **major bump?** | **notes**.

### Toolchain (glibc + gcc) — produced by the toolchain build, not `package/`

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `ld-linux-armhf.so.3` | `ld-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libc.so.6` | `libc-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libm.so.6` | `libm-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libpthread.so.0` | `libpthread-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc ≥2.34 merged pthread into libc; `.so.0` kept as an empty compat stub so this SONAME still resolves |
| `librt.so.1` | `librt-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libdl.so.2` | `libdl-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libresolv.so.2` | `libresolv-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libutil.so.1` | `libutil-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libcrypt.so.1` | `libcrypt-2.31.so` | glibc (internal toolchain) | 2.42 | no | glibc; SONAME symbol-versioned, never bumps (PLAN §3) |
| `libgcc_s.so.1` | `libgcc_s.so.1` | gcc (internal toolchain, `BR2_GCC_VERSION_14_X`) | 14.3.0 | no | libgcc; SONAME frozen at 1 since GCC 3.x |
| `libstdc++.so.6` | `libstdc++.so.6.0.28` | gcc (internal toolchain, `BR2_INSTALL_LIBSTDCPP`) | 14.3.0 | no | libstdc++; SONAME frozen at 6 since GCC 3.4 (2004) |
| `libatomic.so.1` | `libatomic.so.1.2.0` | gcc (internal toolchain) | 14.3.0 | no | part of libgcc's runtime libs |

### glibc iconv/gconv charset modules

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libCNS.so` | `libCNS.so` | glibc iconv/gconv modules (`BR2_ENABLE_LOCALE=y`) | 2.42 | n/a | built automatically with glibc when locale support is enabled; not a separate package |
| `libGB.so` | `libGB.so` | glibc iconv/gconv modules (`BR2_ENABLE_LOCALE=y`) | 2.42 | n/a | built automatically with glibc when locale support is enabled; not a separate package |
| `libISOIR165.so` | `libISOIR165.so` | glibc iconv/gconv modules (`BR2_ENABLE_LOCALE=y`) | 2.42 | n/a | built automatically with glibc when locale support is enabled; not a separate package |
| `libJIS.so` | `libJIS.so` | glibc iconv/gconv modules (`BR2_ENABLE_LOCALE=y`) | 2.42 | n/a | built automatically with glibc when locale support is enabled; not a separate package |
| `libJISX0213.so` | `libJISX0213.so` | glibc iconv/gconv modules (`BR2_ENABLE_LOCALE=y`) | 2.42 | n/a | built automatically with glibc when locale support is enabled; not a separate package |
| `libKSC.so` | `libKSC.so` | glibc iconv/gconv modules (`BR2_ENABLE_LOCALE=y`) | 2.42 | n/a | built automatically with glibc when locale support is enabled; not a separate package |

### Compression

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libz.so.1` | `libz.so.1.2.11` | `BR2_PACKAGE_LIBZLIB` (via `BR2_PACKAGE_ZLIB` provider choice) | 1.3.2 | no | zlib SONAME has never bumped |
| `libbz2.so.1.0` | `libbz2.so.1.0.8` | `BR2_PACKAGE_BZIP2` | 1.0.8 | no | unchanged since bzip2 1.0 (2000) |
| `liblzma.so.5` | `liblzma.so.5.2.5` | `BR2_PACKAGE_XZ` | 5.8.3 | no |  |
| `liblzo2.so.2` | `liblzo2.so.2.0.0` | `BR2_PACKAGE_LZO` | 2.10 | no |  |

### Graphics / fonts / image codecs

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libfreetype.so.6` | `libfreetype.so.6.17.4` | `BR2_PACKAGE_FREETYPE` | 2.14.3 | no | SONAME frozen at 6 since FreeType 2.0 |
| `libpng16.so.16` | `libpng16.so.16.37.0` | `BR2_PACKAGE_LIBPNG` | 1.6.58 | no | the "16" is the libpng 1.6 parallel-install branch tag, baked into the SONAME by design |
| `libjpeg.so.8` | `libjpeg.so.8.2.2` | `BR2_PACKAGE_JPEG_TURBO` (default `jpeg` provider on ARM/NEON) | 3.1.2 | no | **verified**: Buildroot builds jpeg-turbo with `-DWITH_JPEG8=ON` (`package/jpeg-turbo/jpeg-turbo.mk`), i.e. libjpeg-8 ABI compat mode → `libjpeg.so.8`, matching stock exactly (Debian's default jpeg-turbo build instead targets `.so.62`; Buildroot deliberately does not) |
| `libtiff.so.5` | `libtiff.so.5.6.0` | `BR2_PACKAGE_TIFF` | 4.7.1 | **YES** | libtiff bumped its SONAME **5→6** (confirmed: Debian trixie/forky ship `libtiff6` for 4.7.x). Not one of the 12 MiSTer-binary-critical libs; used internally by imlib2's TIFF loader plugin, which we rebuild together, so this is not a parity break for us — flag only for anyone dlopen'ing libtiff directly |
| `libgif.so.7` | `libgif.so.7.2.0` | `BR2_PACKAGE_GIFLIB` | 6.1.2 | no | giflib SONAME has been 7 since the 5.x series and stays 7 through the 6.x series |
| `libImlib2.so.1` | `libImlib2.so.1.6.1` | `BR2_PACKAGE_IMLIB2` | 1.12.5 | no | **verified** (Arch `imlib2` sonames page, 1.12.6-1): still `libImlib2.so.1` — one of the 12 critical SONAMEs, confirmed safe |
| `libxkbcommon.so.0` | `libxkbcommon.so.0.0.0` | `BR2_PACKAGE_LIBXKBCOMMON` | 1.9.2 | no |  |
| `libSDL2-2.0.so.0` | `libSDL2-2.0.so.0.14.0` | `BR2_PACKAGE_SDL2` | 2.32.10 | no | SDL2 bakes "2.0" into the SONAME by convention regardless of point release |

### Audio

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libasound.so.2` | `libasound.so.2.0.0` | `BR2_PACKAGE_ALSA_LIB` | 1.2.15.3 | no |  |
| `libatopology.so.2` | `libatopology.so.2.0.0` | `BR2_PACKAGE_ALSA_LIB` | 1.2.15.3 | no | same package as libasound |
| `libao.so.4` | `libao.so.4.1.0` | `BR2_PACKAGE_LIBAO` | 1.2.2 | no |  |
| `libvorbis.so.0` | `libvorbis.so.0.4.9` | `BR2_PACKAGE_LIBVORBIS` | 1.3.7 | no |  |
| `libvorbisenc.so.2` | `libvorbisenc.so.2.0.12` | `BR2_PACKAGE_LIBVORBIS` | 1.3.7 | no |  |
| `libvorbisfile.so.3` | `libvorbisfile.so.3.3.8` | `BR2_PACKAGE_LIBVORBIS` | 1.3.7 | no |  |
| `libogg.so.0` | `libogg.so.0.8.4` | `BR2_PACKAGE_LIBOGG` | 1.3.6 | no |  |
| `libmpg123.so.0` | `libmpg123.so.0.44.12` | `BR2_PACKAGE_MPG123` | 1.33.4 | no |  |
| `libout123.so.0` | `libout123.so.0.2.2` | `BR2_PACKAGE_MPG123` | 1.33.4 | no |  |
| `libid3tag.so.0` | `libid3tag.so.0.3.0` | `BR2_PACKAGE_LIBID3TAG` | 0.16.3 | no |  |
| `libmodplug.so.1` | `libmodplug.so.1.0.0` | `BR2_PACKAGE_LIBMODPLUG` | git snapshot d1b97ed… | no | upstream unmaintained since ~2018; Buildroot tracks a post-release git snapshot, ABI frozen |
| `libfluidsynth.so.3` | `libfluidsynth.so.3.0.0` | `BR2_PACKAGE_FLUIDSYNTH` (+`BR2_PACKAGE_FLUIDSYNTH_ALSA_LIB` for the ALSA seq MIDI backend, P3.8) | 2.4.7 | no |  |

### Crypto / TLS

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libcrypto.so.1.1` | `libcrypto.so.1.1` | `BR2_PACKAGE_LIBOPENSSL` (via `BR2_PACKAGE_OPENSSL` provider choice) | 3.6.2 | **YES** | OpenSSL 1.1→3.x: SONAME `libcrypto.so.1.1`→`libcrypto.so.3`. See risk table — not one of the 12 MiSTer-critical libs; every consumer is rebuilt against 3.x, so this is not a parity break, only relevant to any pre-built third-party `.so` a community script might ship |
| `libssl.so.1.1` | `libssl.so.1.1` | `BR2_PACKAGE_LIBOPENSSL` | 3.6.2 | **YES** | `libssl.so.1.1`→`libssl.so.3`, same as above |
| `libgnutls.so.30` | `libgnutls.so.30.29.1` | `BR2_PACKAGE_GNUTLS` | 3.8.13 | no |  |
| `libhogweed.so.6` | `libhogweed.so.6.4` | `BR2_PACKAGE_NETTLE` | 3.10.2 | no |  |
| `libnettle.so.8` | `libnettle.so.8.4` | `BR2_PACKAGE_NETTLE` | 3.10.2 | no |  |
| `libgmp.so.10` | `libgmp.so.10.4.1` | `BR2_PACKAGE_GMP` | 6.3.0 | no |  |
| `libtasn1.so.6` | `libtasn1.so.6.6.1` | `BR2_PACKAGE_LIBTASN1` | 4.21.0 | no |  |
| `libgcrypt.so.20` | `libgcrypt.so.20.3.3` | `BR2_PACKAGE_LIBGCRYPT` | 1.12.0 | no |  |
| `libgpg-error.so.0` | `libgpg-error.so.0.31.1` | `BR2_PACKAGE_LIBGPG_ERROR` | 1.61 | no |  |
| `libssh2.so.1` | `libssh2.so.1.0.1` | `BR2_PACKAGE_LIBSSH2` | 1.11.1 | no |  |

### Networking / D-Bus / GLib

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libcurl.so.4` | `libcurl.so.4.7.0` | `BR2_PACKAGE_LIBCURL` (+`BR2_PACKAGE_LIBCURL_CURL` for the CLI, +`BR2_PACKAGE_LIBCURL_OPENSSL` for TLS-backend parity) | 8.20.0 | no | stock 7.78.0 → 8.20.0, no SONAME change (curl has never bumped `libcurl.so.4`) |
| `libdbus-1.so.3` | `libdbus-1.so.3.19.13` | `BR2_PACKAGE_DBUS` | 1.14.10 | no |  |
| `libdbus-c++-1.so.0` | `libdbus-c++-1.so.0.0.0` | `BR2_PACKAGE_DBUS_CPP` | 0.9.0 | no | package literally builds `libdbus-c++-$(VER).tar.gz` — same upstream project as stock |
| `libdbus-glib-1.so.2` | `libdbus-glib-1.so.2.3.4` | `BR2_PACKAGE_DBUS_GLIB` | 0.114 | no |  |
| `libevent-2.1.so.7` | `libevent-2.1.so.7.0.1` | `BR2_PACKAGE_LIBEVENT` | 2.1.12 | no |  |
| `libevent_core-2.1.so.7` | `libevent_core-2.1.so.7.0.1` | `BR2_PACKAGE_LIBEVENT` | 2.1.12 | no |  |
| `libnl-3.so.200` | `libnl-3.so.200.26.0` | `BR2_PACKAGE_LIBNL` | 3.11.0 | no |  |
| `libnl-genl-3.so.200` | `libnl-genl-3.so.200.26.0` | `BR2_PACKAGE_LIBNL` | 3.11.0 | no |  |
| `libnl-route-3.so.200` | `libnl-route-3.so.200.26.0` | `BR2_PACKAGE_LIBNL` | 3.11.0 | no |  |
| `libip4tc.so.2` | `libip4tc.so.2.0.0` | `BR2_PACKAGE_IPTABLES` | 1.8.11 | no |  |
| `libip6tc.so.2` | `libip6tc.so.2.0.0` | `BR2_PACKAGE_IPTABLES` | 1.8.11 | no |  |
| `libxtables.so.12` | `libxtables.so.12.3.0` | `BR2_PACKAGE_IPTABLES` | 1.8.11 | no |  |
| `libgio-2.0.so.0` | `libgio-2.0.so.0.6600.8` | `BR2_PACKAGE_LIBGLIB2` | 2.86.5 | no |  |
| `libglib-2.0.so.0` | `libglib-2.0.so.0.6600.8` | `BR2_PACKAGE_LIBGLIB2` | 2.86.5 | no |  |
| `libgobject-2.0.so.0` | `libgobject-2.0.so.0.6600.8` | `BR2_PACKAGE_LIBGLIB2` | 2.86.5 | no |  |
| `libgmodule-2.0.so.0` | `libgmodule-2.0.so.0.6600.8` | `BR2_PACKAGE_LIBGLIB2` | 2.86.5 | no |  |
| `libgirepository-1.0.so.1` | `libgirepository-1.0.so.1.0.0` | `BR2_PACKAGE_GOBJECT_INTROSPECTION` | 1.84.0 | no |  |

### util-linux / e2fsprogs / disk & fs tools

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libblkid.so.1` | `libblkid.so.1.1.0` | `BR2_PACKAGE_UTIL_LINUX_LIBBLKID` | 2.41.4 | no |  |
| `libfdisk.so.1` | `libfdisk.so.1.1.0` | `BR2_PACKAGE_UTIL_LINUX_LIBFDISK` | 2.41.4 | no |  |
| `libmount.so.1` | `libmount.so.1.1.0` | `BR2_PACKAGE_UTIL_LINUX_LIBMOUNT` | 2.41.4 | no |  |
| `libsmartcols.so.1` | `libsmartcols.so.1.1.0` | `BR2_PACKAGE_UTIL_LINUX_LIBSMARTCOLS` | 2.41.4 | no |  |
| `libuuid.so.1` | `libuuid.so.1.3.0` | `BR2_PACKAGE_UTIL_LINUX_LIBUUID` | 2.41.4 | no |  |
| `libext2fs.so.2` | `libext2fs.so.2.4` | `BR2_PACKAGE_E2FSPROGS` | 1.47.3 | no |  |
| `libe2p.so.2` | `libe2p.so.2.3` | `BR2_PACKAGE_E2FSPROGS` | 1.47.3 | no |  |
| `libcom_err.so.2` | `libcom_err.so.2.1` | `BR2_PACKAGE_E2FSPROGS` | 1.47.3 | no | distinct from Samba's bundled `libcom_err-samba4.so.0` |
| `libparted.so.2` | `libparted.so.2.0.2` | `BR2_PACKAGE_PARTED` | 3.6 | no |  |
| `libntfs-3g.so.88` | `libntfs-3g.so.88.0.0` | `BR2_PACKAGE_NTFS_3G` | 2022.10.3 | no |  |
| `libkmod.so.2` | `libkmod.so.2.3.6` | `BR2_PACKAGE_KMOD` | 33 | no |  |
| `libinotifytools.so.0` | `libinotifytools.so.0.4.1` | `BR2_PACKAGE_INOTIFY_TOOLS` | 3.20.2.2 | no |  |
| `libjq.so.1` | `libjq.so.1.0.4` | `BR2_PACKAGE_JQ` | 1.8.1 | no |  |
| `libexpat.so.1` | `libexpat.so.1.8.1` | `BR2_PACKAGE_EXPAT` | 2.8.1 | no |  |
| `libpopt.so.0` | `libpopt.so.0.0.1` | `BR2_PACKAGE_POPT` | 1.19 | no |  |
| `libreadline.so.8` | `libreadline.so.8.1` | `BR2_PACKAGE_READLINE` | 8.3 | no |  |
| `libhistory.so.8` | `libhistory.so.8.1` | `BR2_PACKAGE_READLINE` | 8.3 | no |  |
| `libncursesw.so.6` | `libncursesw.so.6.1` | `BR2_PACKAGE_NCURSES` **+ `BR2_PACKAGE_NCURSES_WCHAR`** | 6.6 | no | the **`w`** = wide-char build; needs `BR2_PACKAGE_NCURSES_WCHAR=y`. Bare `BR2_PACKAGE_NCURSES` ships the NARROW `libncurses.so.6`, NOT this SONAME. Was shipped narrow by omission and restored (see defconfig comment at `BR2_PACKAGE_NCURSES_WCHAR`). |
| `libformw.so.6` | `libformw.so.6.1` | `BR2_PACKAGE_NCURSES` **+ `BR2_PACKAGE_NCURSES_WCHAR`** | 6.6 | no | wide-char; same `BR2_PACKAGE_NCURSES_WCHAR` requirement as `libncursesw.so.6` |
| `libmenuw.so.6` | `libmenuw.so.6.1` | `BR2_PACKAGE_NCURSES` **+ `BR2_PACKAGE_NCURSES_WCHAR`** | 6.6 | no | wide-char; same `BR2_PACKAGE_NCURSES_WCHAR` requirement as `libncursesw.so.6` |
| `libpanelw.so.6` | `libpanelw.so.6.1` | `BR2_PACKAGE_NCURSES` **+ `BR2_PACKAGE_NCURSES_WCHAR`** | 6.6 | no | wide-char; same `BR2_PACKAGE_NCURSES_WCHAR` requirement as `libncursesw.so.6` |
| `libslang.so.2` | `libslang.so.2.3.2` | `BR2_PACKAGE_SLANG` | 2.3.3 | no |  |
| `libnewt.so.0.52` | `libnewt.so.0.52.21` | `BR2_PACKAGE_NEWT` | 0.52.23 | no |  |
| `libgpm.so.2` | `libgpm.so.2.1.0` | `BR2_PACKAGE_GPM` | 1.20.7 | no |  |

### USB / input

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libusb-0.1.so.4` | `libusb-0.1.so.4.4.4` | `BR2_PACKAGE_LIBUSB_COMPAT` | 0.1.8 (compat shim over libusb-1.0) | no |  |
| `libusb-1.0.so.0` | `libusb-1.0.so.0.3.0` | `BR2_PACKAGE_LIBUSB` | 1.0.30 | no |  |
| `libevdev.so.2` | `libevdev.so.2.3.0` | `BR2_PACKAGE_LIBEVDEV` | 1.13.5 | no |  |
| `libinput.so.10` | `libinput.so.10.13.0` | `BR2_PACKAGE_LIBINPUT` | 1.31.1 | no |  |
| `libmtdev.so.1` | `libmtdev.so.1.0.0` | `BR2_PACKAGE_MTDEV` | 1.1.7 | no |  |

### Bluetooth

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libbluetooth.so.3` | `libbluetooth.so.3.19.5` | `BR2_PACKAGE_BLUEZ5_UTILS` (+`_PLUGINS_SIXAXIS`, `_DEPRECATED` for hciconfig/hcitool/sdptool/rfcomm/l2ping/hcidump parity) | 5.79 | no | **verified**: Arch's current `bluez-libs` package still `Provides: libbluetooth.so=3` — one of the 12 critical SONAMEs, confirmed safe |

### PAM / capabilities

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libpam.so.0` | `libpam.so.0.85.1` | `BR2_PACKAGE_LINUX_PAM` | 1.7.2 | no |  |
| `libpam_misc.so.0` | `libpam_misc.so.0.82.1` | `BR2_PACKAGE_LINUX_PAM` | 1.7.2 | no |  |
| `libcap.so.2` | `libcap.so.2.48` | `BR2_PACKAGE_LIBCAP` | 2.78 | no |  |
| `libcap-ng.so.0` | `libcap-ng.so.0.0.0` | `BR2_PACKAGE_LIBCAP_NG` | 0.8.5 | no |  |

### lftp (bundled internal libs)

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `liblftp-jobs.so.0` | `liblftp-jobs.so.0.0.0` | `BR2_PACKAGE_LFTP` | 4.9.2 | no | bundled internal libs of the lftp package, same version as stock |
| `liblftp-network.so` | `liblftp-network.so` | `BR2_PACKAGE_LFTP` | 4.9.2 | no | bundled internal libs of the lftp package, same version as stock |
| `liblftp-pty.so` | `liblftp-pty.so` | `BR2_PACKAGE_LFTP` | 4.9.2 | no | bundled internal libs of the lftp package, same version as stock |
| `liblftp-tasks.so.0` | `liblftp-tasks.so.0.0.0` | `BR2_PACKAGE_LFTP` | 4.9.2 | no | bundled internal libs of the lftp package, same version as stock |

### Misc small libraries

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libfdt.so.1` | `libfdt-1.6.0.so` | `BR2_PACKAGE_DTC` | 1.7.2 | no |  |
| `libsudo_util.so.0` | `libsudo_util.so.0.0.0` | `BR2_PACKAGE_SUDO` | 1.9.17p2 | no |  |
| `libffi.so.7` | `libffi.so.7.1.0` | `BR2_PACKAGE_LIBFFI` | 3.4.8 | **YES** | libffi bumped **7→8** (confirmed: Debian bookworm/sid ship `libffi8` for 3.4.x). Used by Python ctypes, GLib closures, Samba's Python bindings; rebuilt together so not a parity break for us, flagged for completeness |
| `libi2c.so.0` | `libi2c.so.0.1.1` | `BR2_PACKAGE_I2C_TOOLS` | 4.4 | no |  |
| `libjim.so.0.79` | `libjim.so.0.79` | `BR2_PACKAGE_JIMTCL` | 0.83 | no | installs as `libjim.so.$(JIMTCL_VERSION)` — version *is* the SONAME by this package's convention; needed by `jimsh` and, notably, `usb_modeswitch_dispatcher` (3G/LTE modem mode-switching), not just an obscure shell |
| `liblockfile.so.1` | `liblockfile.so.1.0` | `BR2_PACKAGE_LIBLOCKFILE` | 1.17 | no |  |
| `libtorrent.so.21` | `libtorrent.so.21.0.0` | `BR2_PACKAGE_LIBTORRENT` | 0.15.3 | **YES (likely)** | rakshasa's libtorrent (rtorrent's library, distinct from libtorrent-rasterbar); SONAME has moved past 21 in this version range per Debian's experimental packaging (`libtorrent27`). **Recommend dropping `rtorrent`/`libtorrent` entirely (see Drop list) — nothing MiSTer-side uses it**, so the exact soname doesn't matter |
| `libxml2.so.2` | `libxml2.so.2.9.12` | `BR2_PACKAGE_LIBXML2` | 2.15.3 | no |  |
| `libmagic.so.1` | `libmagic.so.1.0.0` | `BR2_PACKAGE_FILE` | 5.46 | no |  |
| `libpcre.so.1` | *(not provided)* | — | — | no | **Intentional parity deviation (Buildroot 2026.05).** PCRE1 was removed upstream (EOL/unmaintained; now a `Config.in.legacy` stub). Nothing in this image needs `libpcre.so.1`: the stock `MiSTer` binary does not link it (no `-lpcre`, verified against `origin/master`), Python uses its built-in `sre` engine, and 2026.05's `slang` dropped its pcre module. The only stock consumers were `wget`/`zsh`, neither of which we build. `libpcre2-8.so.0` (PCRE2) is provided as the modern replacement, pulled by `libglib2`/`libselinux` and listed explicitly in the defconfig. |
| `libpcreposix.so.0` | *(not provided)* | — | — | no | Dropped with PCRE1 (same row above) — it is PCRE1's POSIX wrapper. PCRE2 ships its own `libpcre2-posix.so.3`. |
| `libudev.so.1` | `libudev.so.1.6.3` | `BR2_PACKAGE_EUDEV` | 3.2.14 | no | eudev, not systemd-udev — matches PLAN §3 ("hotplug is eudev, not mdev") |

### Python (on-device interpreter — A6 ABI surface)

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libpython3.9.so.1.0` | `libpython3.9.so.1.0` | `BR2_PACKAGE_PYTHON3` | 3.14.5 | **YES (intentional, A6)** | stock 3.9 (EOL) → 3.14.5. This is the on-device Python ABI surface (A6) — see risk table, owner P3.9 |

### Already-broken / dangling in stock (P0.3 finding)

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libarchive.so.13` | — | `BR2_PACKAGE_LIBARCHIVE` exists (3.8.7) | 3.8.7 | n/a | package itself is fine, but the *consumer*, `archivemount`, has **no Buildroot package** — see Gaps. Already dangling in stock (P0.3); recommend dropping the tool rather than packaging it |
| `libfuse.so.2` | — | `BR2_PACKAGE_LIBFUSE` exists (2.9.9) | 2.9.9 | n/a | package itself is fine (would satisfy this SONAME); same disposition as above — the gap is `archivemount`, not libfuse |
| `libdb-5.3.so` | — | `BR2_PACKAGE_BERKELEYDB` exists (5.3.28) | 5.3.28 | n/a | package itself is fine and *would* satisfy this SONAME exactly (5.3), but the consumer `libjack.so.0.0.28` (JACK1) is dangling/unused in stock and nothing NEEDs it in turn — see Drop list |

### True gaps — no Buildroot package exists

| SONAME | stock realfile | Buildroot package | version | bump? | notes |
|---|---|---|---|---|---|
| `libhid.so.0` | `libhid.so.0.0.0` | **GAP — no Buildroot package** | — | n/a | legacy `libhid` (USB-HID-via-libusb-0.1) project; only consumer is `libhid-detach-device`, an obscure CLI tool. Recommend dropping the tool (see Gaps/Drop) |
| `libadplug.so` | — | **GAP — no Buildroot package** | — | n/a | AdPlug (AdLib music emulation library); only consumer is `adplay`. Recommend dropping (see Gaps/Drop) |
| `libbinio.so` | — | **GAP — no Buildroot package** | — | n/a | AdPlug's binary-I/O helper lib; same consumer/disposition as libadplug |

### Samba (bundled monolithic build — `BR2_PACKAGE_SAMBA4`, version 4.23.8)

Buildroot's `samba4` package (`package/samba4/samba4.mk`, `SAMBA4_VERSION = 4.23.8`,
cited) configures with
`--bundled-libraries='!asn1_compile,!compile_et'` — i.e. **everything except two
small host-side codegen tools is bundled and built as part of the samba4 tree**,
exactly reproducing the ~120-library sprawl stock ships (bundled talloc, tdb, tevent,
ldb, and a bundled Heimdal Kerberos implementation — Buildroot carries a separate
`heimdal` package too, but samba4 does not use it; it builds its own copy). This single
`BR2_PACKAGE_SAMBA4=y` line is therefore responsible for **125 of the 251 SONAMEs**
below — do not read this as 125 separate packages.

The 5 `cpython-39-x86-64-linux-gnu`-tagged entries are Samba's own Python bindings;
the Python ABI tag is baked into the filename by Samba's own waf build, so under our
target Python (3.14, see below) these files would be named e.g.
`libpyldb-util.cpython-314-arm-linux-gnueabihf.so.2` — **not** byte-identical to the
stock string, but that's expected and harmless: nothing outside Samba's own runtime
ever references the literal old filename. (Note also that stock's own tag says
`x86-64` on an ARM device — an artifact of MiSTer-devel's build pipeline, not
something to reproduce.) Whether these get built at all is controlled by
`BR2_PACKAGE_PYTHON3` being enabled (which we need anyway for A6/P3.9), *not* by
`BR2_PACKAGE_SAMBA4_AD_DC` — recommend leaving `SAMBA4_AD_DC` **off** regardless (see
Drop list): it only gates the Active-Directory-domain-controller-specific pieces,
which MiSTer's standalone file-server role never uses.

| SONAME | stock realfile | notes |
|---|---|---|
| `libCHARSET3-samba4.so` | `libCHARSET3-samba4.so` |  |
| `libLIBWBCLIENT-OLD-samba4.so` | `libLIBWBCLIENT-OLD-samba4.so` |  |
| `libMESSAGING-SEND-samba4.so` | `libMESSAGING-SEND-samba4.so` |  |
| `libMESSAGING-samba4.so` | `libMESSAGING-samba4.so` |  |
| `libaddns-samba4.so` | `libaddns-samba4.so` |  |
| `libads-samba4.so` | `libads-samba4.so` |  |
| `libasn1-samba4.so.8` | `libasn1-samba4.so.8.0.0` |  |
| `libasn1util-samba4.so` | `libasn1util-samba4.so` |  |
| `libauth-samba4.so` | `libauth-samba4.so` |  |
| `libauth-unix-token-samba4.so` | `libauth-unix-token-samba4.so` |  |
| `libauth4-samba4.so` | `libauth4-samba4.so` |  |
| `libauthkrb5-samba4.so` | `libauthkrb5-samba4.so` |  |
| `libcli-cldap-samba4.so` | `libcli-cldap-samba4.so` |  |
| `libcli-ldap-common-samba4.so` | `libcli-ldap-common-samba4.so` |  |
| `libcli-ldap-samba4.so` | `libcli-ldap-samba4.so` |  |
| `libcli-nbt-samba4.so` | `libcli-nbt-samba4.so` |  |
| `libcli-smb-common-samba4.so` | `libcli-smb-common-samba4.so` |  |
| `libcli-spoolss-samba4.so` | `libcli-spoolss-samba4.so` |  |
| `libcliauth-samba4.so` | `libcliauth-samba4.so` |  |
| `libclidns-samba4.so` | `libclidns-samba4.so` |  |
| `libcluster-samba4.so` | `libcluster-samba4.so` |  |
| `libcmdline-contexts-samba4.so` | `libcmdline-contexts-samba4.so` |  |
| `libcmdline-credentials-samba4.so` | `libcmdline-credentials-samba4.so` |  |
| `libcom_err-samba4.so.0` | `libcom_err-samba4.so.0.25` |  |
| `libcommon-auth-samba4.so` | `libcommon-auth-samba4.so` |  |
| `libctdb-event-client-samba4.so` | `libctdb-event-client-samba4.so` |  |
| `libdbwrap-samba4.so` | `libdbwrap-samba4.so` |  |
| `libdcerpc-binding.so.0` | `libdcerpc-binding.so.0.0.1` |  |
| `libdcerpc-samba-samba4.so` | `libdcerpc-samba-samba4.so` |  |
| `libdcerpc-samba4.so` | `libdcerpc-samba4.so` |  |
| `libdcerpc-server-core.so.0` | `libdcerpc-server-core.so.0.0.1` |  |
| `libdcerpc.so.0` | `libdcerpc.so.0.0.1` |  |
| `libevents-samba4.so` | `libevents-samba4.so` |  |
| `libflag-mapping-samba4.so` | `libflag-mapping-samba4.so` |  |
| `libgenrand-samba4.so` | `libgenrand-samba4.so` |  |
| `libgensec-samba4.so` | `libgensec-samba4.so` |  |
| `libgpo-samba4.so` | `libgpo-samba4.so` |  |
| `libgse-samba4.so` | `libgse-samba4.so` |  |
| `libgssapi-samba4.so.2` | `libgssapi-samba4.so.2.0.0` |  |
| `libhcrypto-samba4.so.5` | `libhcrypto-samba4.so.5.0.1` |  |
| `libhdb-samba4.so.11` | `libhdb-samba4.so.11.0.2` |  |
| `libheimbase-samba4.so.1` | `libheimbase-samba4.so.1.0.0` |  |
| `libhttp-samba4.so` | `libhttp-samba4.so` |  |
| `libhx509-samba4.so.5` | `libhx509-samba4.so.5.0.0` |  |
| `libidmap-samba4.so` | `libidmap-samba4.so` |  |
| `libinterfaces-samba4.so` | `libinterfaces-samba4.so` |  |
| `libiov-buf-samba4.so` | `libiov-buf-samba4.so` |  |
| `libkrb5-samba4.so.26` | `libkrb5-samba4.so.26.0.0` |  |
| `libkrb5samba-samba4.so` | `libkrb5samba-samba4.so` |  |
| `libldb-cmdline-samba4.so` | `libldb-cmdline-samba4.so` |  |
| `libldb-key-value-samba4.so` | `libldb-key-value-samba4.so` |  |
| `libldb-tdb-err-map-samba4.so` | `libldb-tdb-err-map-samba4.so` |  |
| `libldb-tdb-int-samba4.so` | `libldb-tdb-int-samba4.so` |  |
| `libldb.so.2` | `libldb.so.2.3.0` |  |
| `libldbsamba-samba4.so` | `libldbsamba-samba4.so` |  |
| `liblibcli-lsa3-samba4.so` | `liblibcli-lsa3-samba4.so` |  |
| `liblibcli-netlogon3-samba4.so` | `liblibcli-netlogon3-samba4.so` |  |
| `liblibsmb-samba4.so` | `liblibsmb-samba4.so` |  |
| `libmessages-dgm-samba4.so` | `libmessages-dgm-samba4.so` |  |
| `libmessages-util-samba4.so` | `libmessages-util-samba4.so` |  |
| `libmsghdr-samba4.so` | `libmsghdr-samba4.so` |  |
| `libmsrpc3-samba4.so` | `libmsrpc3-samba4.so` |  |
| `libndr-krb5pac.so.0` | `libndr-krb5pac.so.0.0.1` |  |
| `libndr-nbt.so.0` | `libndr-nbt.so.0.0.1` |  |
| `libndr-samba-samba4.so` | `libndr-samba-samba4.so` |  |
| `libndr-samba4.so` | `libndr-samba4.so` |  |
| `libndr-standard.so.0` | `libndr-standard.so.0.0.1` |  |
| `libndr.so.1` | `libndr.so.1.0.1` |  |
| `libnetapi.so.0` | `libnetapi.so.0` |  |
| `libnetif-samba4.so` | `libnetif-samba4.so` |  |
| `libnpa-tstream-samba4.so` | `libnpa-tstream-samba4.so` |  |
| `libnss-info-samba4.so` | `libnss-info-samba4.so` |  |
| `libpopt-samba3-cmdline-samba4.so` | `libpopt-samba3-cmdline-samba4.so` |  |
| `libpopt-samba3-samba4.so` | `libpopt-samba3-samba4.so` |  |
| `libposix-eadb-samba4.so` | `libposix-eadb-samba4.so` |  |
| `libprinting-migrate-samba4.so` | `libprinting-migrate-samba4.so` |  |
| `libpyldb-util.cpython-39-x86-64-linux-gnu.so.2` | `libpyldb-util.cpython-39-x86-64-linux-gnu.so.2.3.0` | Python-ABI-tagged internal binding, see paragraph above |
| `libpytalloc-util.cpython-39-x86-64-linux-gnu.so.2` | `libpytalloc-util.cpython-39-x86-64-linux-gnu.so.2.3.2` | Python-ABI-tagged internal binding, see paragraph above |
| `libregistry-samba4.so` | `libregistry-samba4.so` |  |
| `libreplace-samba4.so` | `libreplace-samba4.so` |  |
| `libroken-samba4.so.19` | `libroken-samba4.so.19.0.1` |  |
| `libsamba-cluster-support-samba4.so` | `libsamba-cluster-support-samba4.so` |  |
| `libsamba-credentials.so.1` | `libsamba-credentials.so.1.0.0` |  |
| `libsamba-debug-samba4.so` | `libsamba-debug-samba4.so` |  |
| `libsamba-errors.so.1` | `libsamba-errors.so.1` |  |
| `libsamba-hostconfig.so.0` | `libsamba-hostconfig.so.0.0.1` |  |
| `libsamba-modules-samba4.so` | `libsamba-modules-samba4.so` |  |
| `libsamba-net.cpython-39-x86-64-linux-gnu-samba4.so` | `libsamba-net.cpython-39-x86-64-linux-gnu-samba4.so` | Python-ABI-tagged internal binding, see paragraph above |
| `libsamba-passdb.so.0` | `libsamba-passdb.so.0.28.0` |  |
| `libsamba-policy.cpython-39-x86-64-linux-gnu.so.0` | `libsamba-policy.cpython-39-x86-64-linux-gnu.so.0.0.1` | Python-ABI-tagged internal binding, see paragraph above |
| `libsamba-python.cpython-39-x86-64-linux-gnu-samba4.so` | `libsamba-python.cpython-39-x86-64-linux-gnu-samba4.so` | Python-ABI-tagged internal binding, see paragraph above |
| `libsamba-security-samba4.so` | `libsamba-security-samba4.so` |  |
| `libsamba-sockets-samba4.so` | `libsamba-sockets-samba4.so` |  |
| `libsamba-util.so.0` | `libsamba-util.so.0.0.1` |  |
| `libsamba3-util-samba4.so` | `libsamba3-util-samba4.so` |  |
| `libsamdb-common-samba4.so` | `libsamdb-common-samba4.so` |  |
| `libsamdb.so.0` | `libsamdb.so.0.0.1` |  |
| `libsecrets3-samba4.so` | `libsecrets3-samba4.so` |  |
| `libserver-id-db-samba4.so` | `libserver-id-db-samba4.so` |  |
| `libserver-role-samba4.so` | `libserver-role-samba4.so` |  |
| `libsmb-transport-samba4.so` | `libsmb-transport-samba4.so` |  |
| `libsmbclient-raw-samba4.so` | `libsmbclient-raw-samba4.so` |  |
| `libsmbclient.so.0` | `libsmbclient.so.0.7.0` |  |
| `libsmbconf.so.0` | `libsmbconf.so.0` |  |
| `libsmbd-base-samba4.so` | `libsmbd-base-samba4.so` |  |
| `libsmbd-shim-samba4.so` | `libsmbd-shim-samba4.so` |  |
| `libsocket-blocking-samba4.so` | `libsocket-blocking-samba4.so` |  |
| `libsys-rw-samba4.so` | `libsys-rw-samba4.so` |  |
| `libtalloc-report-printf-samba4.so` | `libtalloc-report-printf-samba4.so` |  |
| `libtalloc-report-samba4.so` | `libtalloc-report-samba4.so` |  |
| `libtalloc.so.2` | `libtalloc.so.2.3.2` |  |
| `libtdb-wrap-samba4.so` | `libtdb-wrap-samba4.so` |  |
| `libtdb.so.1` | `libtdb.so.1.4.3` |  |
| `libtevent-util.so.0` | `libtevent-util.so.0.0.1` |  |
| `libtevent.so.0` | `libtevent.so.0.10.2` |  |
| `libtime-basic-samba4.so` | `libtime-basic-samba4.so` |  |
| `libtrusts-util-samba4.so` | `libtrusts-util-samba4.so` |  |
| `libutil-cmdline-samba4.so` | `libutil-cmdline-samba4.so` |  |
| `libutil-reg-samba4.so` | `libutil-reg-samba4.so` |  |
| `libutil-setid-samba4.so` | `libutil-setid-samba4.so` |  |
| `libutil-tdb-samba4.so` | `libutil-tdb-samba4.so` |  |
| `libwbclient.so.0` | `libwbclient.so.0.15` |  |
| `libwinbind-client-samba4.so` | `libwinbind-client-samba4.so` |  |
| `libwind-samba4.so.0` | `libwind-samba4.so.0.0.0` |  |
| `libxattr-tdb-samba4.so` | `libxattr-tdb-samba4.so` |  |

**Total rows across all tables above: 251 — matches the 251-SONAME input set exactly.**

---

## 2. User-facing binaries → packages

The daemons and tools stock ships that users/scripts depend on directly (not just
via SONAME), pulled from `docs/stock-inventory/etc-configs.md`'s init-script list and
`binaries-needed-full.txt`'s `/usr/bin`, `/usr/sbin` paths — not guessed.

| Role | Stock | Buildroot package | BR 2026.02.3 version | Init script (P2.3 parity) |
|---|---|---|---|---|
| SMB/CIFS file server | Samba 4.14.6 (`smbd`, `nmbd`) | `BR2_PACKAGE_SAMBA4` | 4.23.8 | `S91smb` |
| SSH server | OpenSSH 8.6p1 (`sshd`) | `BR2_PACKAGE_OPENSSH` | 10.2p1 | `S50sshd` |
| FTP server | ProFTPD (stock ships it, exact version not in IKCONFIG) | `BR2_PACKAGE_PROFTPD` | 1.3.8d | `S50proftpd` |
| Bluetooth stack | bluez 5.61 (`bluetoothd`) | `BR2_PACKAGE_BLUEZ5_UTILS` | 5.79 | `S45bluetooth` → symlink to `/bin/bluetoothd` control script (P0.3 finding) |
| WiFi supplicant | wpa_supplicant 2.x | `BR2_PACKAGE_WPA_SUPPLICANT` (+`_NL80211`, +`_WEXT` — stock's `/etc/network/interfaces` passes `-D nl80211,wext`, both drivers must be built) | 2.11 | invoked from `ifupdown` `pre-up` in `/etc/network/interfaces`, not its own S-script |
| DHCP client | dhcpcd | `BR2_PACKAGE_DHCPCD` | 10.2.4 | `S41dhcpcd` |
| NTP daemon | `ntpd` (classic ntp.org, not chrony/openntpd) | `BR2_PACKAGE_NTP` | 4.2.8p18 | `S49ntp` |
| D-Bus | dbus | `BR2_PACKAGE_DBUS` | 1.14.10 | `S30dbus` |
| udev / hotplug | eudev (**not** systemd-udev, **not** mdev — PLAN §3) | `BR2_PACKAGE_EUDEV` | 3.2.14 | `S10udev` |
| Software synth for MIDI/MT-32 | FluidSynth | `BR2_PACKAGE_FLUIDSYNTH` (+`_ALSA_LIB` for the ALSA-seq MIDI backend) | 2.4.7 | none — driven directly by the `MiSTer` binary, not a daemon; see note below |
| CIFS client mount | `mount.cifs` | `BR2_PACKAGE_CIFS_UTILS` | 7.4 | none (on-demand, P3.10) |
| NFS client mount | NFS utils | `BR2_PACKAGE_NFS_UTILS` | 2.8.6 | none (on-demand, P3.10) |
| On-device interpreter | Python 3.9 | `BR2_PACKAGE_PYTHON3` | **3.14.5** | n/a — see A6 risk entry |
| File sync (Downloader/updater rsync-based steps) | rsync | `BR2_PACKAGE_RSYNC` | 3.4.3 | n/a |
| HTTP client (Downloader, scripts) | curl 7.78.0 | `BR2_PACKAGE_LIBCURL` +`_CURL` (installs the CLI, off by default) +`_OPENSSL` (TLS backend parity — stock's `curl` links `libcrypto`/`libssl`, not GnuTLS) | 8.20.0 | n/a |
| Init/shell userland | BusyBox 1.33.1 (274 applets) | `BR2_PACKAGE_BUSYBOX` | 1.37.0 | provides `rcS`/`rcK`, most of `/bin` |
| Privilege elevation | sudo | `BR2_PACKAGE_SUDO` | 1.9.17p2 | n/a |
| Bluetooth legacy tools (`hciconfig`, `hcitool`, `sdptool`, `rfcomm`, `l2ping`, `hcidump`) | present in stock | `BR2_PACKAGE_BLUEZ5_UTILS_DEPRECATED=y` | 5.79 | upstream bluez gates these behind this option now |
| PS3 controller pairing | `sixaxis.so` bluez plugin | `BR2_PACKAGE_BLUEZ5_UTILS_PLUGINS_SIXAXIS=y` | 5.79 | pulls in `_PLUGINS_HID` transitively (`select`, don't set separately) |

**MT-32 / soundfont note (P3.8):** `MidiLink.INI`, `mt32-rom-data/`, and `soundfonts/`
are **not** Linux userland — they are data files shipped under `files/linux/` on the
FAT partition (per `docs/verification/stock-release-20250402.md`'s archive-layout
listing) that the `MiSTer` binary itself reads directly via `libfluidsynth.so.3` and
its own built-in MT-32 emulation. There is no separate Buildroot package for MT-32
ROM handling — it's a data/asset parity concern (carry the files forward unmodified),
not a package-mapping concern. `MidiLink.INI` itself configures the Windows-side
MidiLink companion app, not anything running on-device.

---

## 3. Version-jump risk table

This is the point of the task. For each package with a meaningful jump: the
*specific* breaking changes, grounded in the actual stock config (`etc-configs.md`)
or the actual consumer source (`Downloader_MiSTer`), and an owning task.

### Samba 4.14.6 → 4.23.8 (owner: P3.6)

Nine major releases apart. Read against the **verbatim stock `smb.conf`**
(`docs/stock-inventory/etc-configs.md`):

- **SMB1 already off by default since Samba 4.11** (`client/server min protocol =
  SMB2_02`) — stock is already 4.14, so this is not a *new* regression from our jump.
  Stock's `smb.conf` never sets `server min protocol`, so both stock and our rebuild
  fall through to the same SMB2-minimum default. Any DOS/Win9x-era "nostalgia"
  client that needed SMB1 was **already broken on stock 4.14.6**; this is a
  pre-existing condition, not something we introduce.
- **`unix extensions` — not set in stock's smb.conf, default applies both sides. But
  Samba 4.23 changes what that default means**: Samba 4.23's release notes add a new
  *`smb3 unix extensions`* parameter and enable **SMB3 POSIX extensions by default**
  (distinct from the old SMB1-era `unix extensions`, which stock also never sets)
  — i.e. neither version has the admin setting anything, but 4.23's default behavior
  for POSIX-aware clients (recent Linux/macOS SMB3 clients) differs from 4.14's. Net
  effect is more-correct permission/symlink semantics for modern clients connecting
  over SMB3 — a likely-positive but **untested** behavior change. P3.6 should verify
  file permissions/symlinks through the `[sdcard]`/`[usb0-7]` shares from a modern
  Linux client specifically.
- **Guest/anonymous access** (`public = yes` / `writeable = yes` on `[sdcard]`,
  `[usb0]`–`[usb7]`, `[tmp]`): stock never sets `map to guest`, so both versions use
  Samba's long-standing default (`Never` — guest mapping only for explicit guest-user
  logins, not failed auth). This directive's meaning has not changed across the jump.
  `writeable` (the stock spelling, vs. the more common `writable`) is a long-standing
  Samba synonym in both versions — confirmed still accepted, no rename risk.
- **`valid users`/`invalid users`/`read list`/`write list` now hard-fail the tree
  connect on unresolvable names as of 4.21** (previously silently skipped) — stock's
  shipped `smb.conf` sets **none** of these on any active share, so this doesn't fire
  for the shipped config, but **any user-customized smb.conf that added one of these
  directives could newly fail to start** — worth a callout in the FAQ (P4.8), not a
  code fix.
- **`server role = standalone server`, `workgroup`, `server string`, `log file`,
  `max log size`, `dns proxy`** — all still valid, unchanged parameters in 4.23.
- **`nmbd` (NetBIOS/WINS)** is still built and shipped in Samba 4.23 (not yet removed
  upstream as of this release), so NetBIOS name resolution/browsing parity is
  preservable if desired — but it's increasingly legacy upstream and a reasonable
  candidate to drop if modern clients (mDNS/Explorer's SMB-over-QUIC-adjacent
  discovery, or just typing the IP/`.local` name) suffice; P3.6's call.
- **Recommendation for P3.6**: ship the stock `smb.conf` close to verbatim (same
  shares, same `public`/`writeable` flags), explicitly test file creation/permission
  behavior on the SMB3-POSIX-by-default change, and treat AD DC / ADS (`samba-tool`,
  domain join) as explicitly out of scope (see Drop list — `SAMBA4_AD_DC` should stay
  off).

### OpenSSH 8.6p1 → 10.2p1 (owner: P3.7)

- **`ssh-rsa` (RSA/SHA-1) signatures disabled by default since OpenSSH 8.8** (2021).
  RSA *keys* still work automatically via RFC 8332 SHA-256/512 signatures on any
  reasonably modern client; only clients/libraries that hard-code the legacy SHA-1
  RSA signature scheme (old libssh2/paramiko builds, ancient PuTTY) will fail unless
  `PubkeyAcceptedAlgorithms` is widened. Low risk for interactive users, worth a FAQ
  line for anyone scripting against MiSTer's sshd with an old SSH library.
- **`scp` defaults to the SFTP protocol instead of legacy scp/rcp since OpenSSH 9.0**
  (2022). Stock's `sshd_config` already enables `Subsystem sftp
  /usr/libexec/sftp-server` (verbatim, `etc-configs.md`), so the server side is
  already compatible either way — this only matters if a MiSTer-side script *invokes*
  `scp` as a client against some *other*, very old SFTP-less server, which is not a
  pattern used anywhere in the stock image.
- **`PermitRootLogin`: upstream compiled-in default changed `yes`→`prohibit-password`
  back in OpenSSH 7.0 (2015)** — already true for stock's 8.6p1, so irrelevant to this
  jump specifically. What matters (and does **not** change with the version bump,
  because it's an explicit config line, not a default): stock's shipped
  `sshd_config` **explicitly sets `PermitRootLogin yes`** (verbatim,
  `etc-configs.md`), and P0.3 additionally found `/etc/passwd`/`/etc/shadow` ship a
  **fixed, publicly-known default root password** with root as the only
  login-capable account. **P3.7 must carry `PermitRootLogin yes` forward for parity
  (per the task's own instruction: keep parity, don't silently harden) — meaning the
  version jump does nothing to fix this exposure, it simply comes along for the
  ride.** This combination (root login enabled + fixed default password) must be
  documented prominently in the user-facing FAQ (P4.8), exactly as P0.3 flagged.
- **Host keys**: stock ships baked-in DSA/ECDSA/Ed25519/RSA host keys shared byte-for-byte
  across every never-regenerated stock installation (P0.3 finding, `etc-configs.md`).
  OpenSSH 10.x still generates/accepts DSA host keys for backward compat but has
  refused to *offer* `ssh-dss` client/server auth by default since ~7.0 — again
  pre-existing on stock 8.6p1, not new. P3.7 needs to decide (and document, per P2.4)
  whether we regenerate fresh host keys at first boot or ship a fixed set — either
  way, document the choice in the FAQ per the fingerprint-reuse caveat P0.3 raised.

### Python 3.9 → 3.14.5 (owner: P3.9, constraint A6)

Buildroot 2026.02.3's `python3` package (`package/python3/python3.mk`,
`PYTHON3_VERSION_MAJOR = 3.14`, `PYTHON3_VERSION = 3.14.5`) ships **3.14.5** — newer
even than PLAN's estimate of "3.13+". There is no legacy-version toggle in Buildroot's
`python3` package (single `BR2_PACKAGE_PYTHON3` symbol, no version choice); a 3.9 target
would have to be a custom out-of-tree package, which is not recommended (EOL, no
security fixes upstream).

**`Downloader_MiSTer` itself declares Python 3.9 as its own target**, verified from
its checked-out source (`work/Downloader_MiSTer`, cloned by P0.3):
- `.github/actions/setup-python/action.yml`: `description: 'Setup Python 3.9'`,
  `python-version: '3.9'` — its entire CI matrix runs against 3.9, not a range.
- `src/Dockerfile.nuitka`: installs `python3.9-dev` and runs `python3.9 -m pip install
  'nuitka~=2.8.4' …` to build the compiled/packaged binary distribution.

This is exactly the risk A6 describes, now with hard evidence: the tool that *is* the
system's own updater has never been run, tested, or CI-validated against anything
newer than 3.9. Concretely, 3.9→3.14 removes/changes, among others:
- `distutils` — **removed** in 3.12 (deprecated since 3.10). Any community script
  still doing `from distutils import ...` (common in older setup.py-style tooling)
  breaks outright.
- `imp` — **removed** in 3.12 (use `importlib`).
- `asynchat`, `asyncore`, `smtpd` — **removed** in 3.12 (deprecated since 3.6/3.10).
- `cgi`, `cgitb` — **removed** in 3.13.
- `typing.io`/`typing.re` submodules — removed 3.13.
- broader syntax/semantics deprecations across five major releases (3.10 pattern
  matching is additive so not a risk; f-string parsing changes in 3.12; stricter
  `asyncio` loop-policy changes; etc).

**Action for P3.9 (already scoped correctly in TASKS.md)**: run `Downloader_MiSTer`'s
own test suite under `qemu-arm` + the *target* Python, and smoke-test popular
community scripts (`update_all`, etc.). Per the task's own framing, the correct fix
for real incompatibilities is **reporting them upstream to `Downloader_MiSTer` /
community script authors**, not silently pinning an EOL interpreter — Buildroot
2026.02 gives us no easy way to pin 3.9 even if we wanted to.

### bluez 5.61 → 5.79 (owner: P3.5) — confirmed safe

`libbluetooth.so.3` unchanged (see headline finding). Behavior-level: bluez5's
`main.conf` schema (verbatim stock config uses `FastConnectable`, `Privacy`,
`JustWorksRepairing`, `AutoEnable` — all still valid keys in current bluez) has been
stable across this range; no known breaking `main.conf` schema change. The bigger
P3.5 item is behavioral/packaging, not ABI: current bluez5_utils gates the classic
CLI tools (`hciconfig`, `hcitool`, `sdptool`, `rfcomm`, `l2ping`, `hcidump`) — all
present in stock — behind `BR2_PACKAGE_BLUEZ5_UTILS_DEPRECATED`, and the PS3
`sixaxis.so` plugin behind its own explicit option (both in the paste list, §6).

### curl 7.78.0 → 8.20.0 (owner: P3.9/general) — confirmed safe

`libcurl.so.4` has never bumped its SONAME in curl's history; this is a large version
jump with essentially zero ABI risk. Behaviorally, curl 8.x removed a handful of very
old protocol/TLS-backend combinations and defaults to HTTP/2 more aggressively, none
of which affect the plain HTTPS `GET`/download usage `Downloader_MiSTer` and
community update scripts rely on.

### BusyBox 1.33.1 → 1.37.0 (owner: whoever owns rootfs-overlay, P2.3)

Four years of BusyBox releases. No applet in the 274-applet stock list
(`docs/stock-inventory/busybox-applets.md`) has been removed in that span; this is a
routine bump. The one item worth a deliberate look in P2.3: BusyBox `init`'s
`inittab`/`rcS`/`rcK` semantics stock relies on (`::sysinit`, backgrounding with `&`,
the `[ ! -f "$i" ]` symlink-following guard that makes `S45bluetooth`'s symlink trick
work) are unchanged in current BusyBox — confirm during P2.3, not a version-jump risk
per se.

### Secondary SONAME bumps worth flagging (none in the 12-critical set, no action required)

| Library | Stock | BR 2026.02.3 | Bump | Why it doesn't matter here |
|---|---|---|---|---|
| OpenSSL | 1.1.1 (`libcrypto/libssl.so.1.1`) | 3.6.2 (`BR2_PACKAGE_LIBOPENSSL`) | `.so.1.1`→`.so.3` | Every consumer (curl, samba4, wpa_supplicant, gnutls's fallback, lftp, rtorrent-if-kept) is rebuilt from source against 3.x in the same build. OpenSSL 1.1 is EOL upstream (Sept 2023) regardless. Only matters if a community script ships a pre-built ARM `.so` linked against 1.1 — none are known to. |
| libtiff | 4.x → `.so.5` | 4.7.1 → `.so.6` (confirmed via Debian `libtiff6`) | 5→6 | Only consumed internally by imlib2's TIFF loader plugin, rebuilt together. |
| libffi | 3.x → `.so.7` | 3.4.8 → `.so.8` (confirmed via Debian `libffi8`) | 7→8 | Consumed by Python ctypes, GLib, Samba's Python glue — all rebuilt together. |

---

## 4. Gaps — stock things with no Buildroot package

Every gap below has a disposition (task's done-when criterion).

| Item | Consumer | Buildroot package? | Disposition | Owner |
|---|---|---|---|---|
| `libhid` (`libhid.so.0`) | `libhid-detach-device` | **none** | Drop the tool. Legacy USB-HID-via-libusb-0.1 project, superseded everywhere by `libusb`/`hidapi`; nothing MiSTer-specific uses it | rootfs package list (P2.1) |
| AdPlug (`libadplug.so`, `libbinio.so`) | `adplay` | **none** | Drop the tool. AdLib/OPL music player CLI; not part of any MiSTer audio path (FluidSynth + ALSA handle that) | rootfs package list (P2.1) |
| `archivemount` | (itself, needs `libarchive.so.13`+`libfuse.so.2`) | **none** (both of its *dependencies*, `libarchive` and `libfuse`, DO exist in Buildroot — `BR2_PACKAGE_LIBARCHIVE` 3.8.7, `BR2_PACKAGE_LIBFUSE` 2.9.9 — but `archivemount` the tool itself is not packaged by Buildroot) | Drop. Already **dangling/non-functional in stock** per P0.3 — reproducing a broken binary faithfully is not a goal. If ever wanted, it's a straightforward `package/` addition (FUSE + libarchive glue, small C source) — file as a future community request, not a P0.7 blocker | Gaps list only, no Phase-3 task currently owns it |
| Realtek out-of-tree WiFi (11ac: `8812au`, `8821au`) | kernel modules, class E | none (by design — morrownr forks) | **Not this task's gap** — owned by P3.1/v9 as Buildroot `kernel-module` packages sourced from morrownr. v9 moved `8188eu`/`rtl8188fu` (→ in-kernel `rtl8xxxu`), `8821cu` (→ `rtw88_8821cu`) and `88x2bu` (→ `rtw88_8822bu`) to mainline; PR #35 later moved `8814au` (→ in-kernel `rtw88_8814au`) the same way, leaving only `8812au` and `8821au` out-of-tree (no mainline USB driver). See [ADR 0016](decisions/0016-mainline-first-wifi-drivers.md) | P3.1/v9 |
| `xone` (Xbox Wireless) | kernel modules, class D | none (out-of-tree upstream project) | **Closed by P3.2** — `package/xone` (driver, `dlundqvist/xone` fork) + `package/xow-firmware` + `package/cabextract` (dongle firmware, Microsoft-sourced at build time, `docs/decisions/0003-xone-firmware.md`) | P3.2 |
| MT-32 ROM / soundfont data | `MiSTer` binary's built-in synth, via `libfluidsynth.so.3` | n/a — not software, it's asset data (`mt32-rom-data/`, `soundfonts/`) shipped under `files/linux/` | Carry forward unmodified as static assets, not a rootfs package concern | P3.8 |

---

## 5. Drop list — what stock ships that we should not

The rootfs is **93% full** (297/347 MiB per PLAN §4.2, confirmed 13.6% free by
`docs/verification/stock-release-20250402.md`) and we must land ≥15% free in a 512 MiB
image (PLAN §11/P2.7). A modern package set will not shrink on its own
(PLAN §4.2), so every dropped package is real budget. From
`docs/stock-inventory/disk-usage.md`:

| Item | Size (stock) | Why drop | Disposition |
|---|---|---|---|
| `archivemount` + would-be `libfuse`/`libarchive` fix | small, but see above | already broken in stock (dangling deps), zero known users | drop entirely, don't fix |
| `adplay`/AdPlug/libbinio | small | no Buildroot package, no known MiSTer use | drop |
| `libhid-detach-device`/libhid | small | no Buildroot package, obscure/superseded API | drop |
| JACK1 (`libjack.so.0.0.28`) + its dangling `libdb-5.3.so` need | small | dangling in stock (P0.3), nothing NEEDs `libjack` itself either — completely unused; MiSTer's audio path is ALSA-direct + FluidSynth, not JACK | drop; if a future use case needs JACK, Buildroot's modern `jack2` (1.9.22) is available and would not have this dangling-dependency problem at all |
| `rtorrent` + `libtorrent` (rakshasa) | binary + lib | nothing in MiSTer's ecosystem uses a BitTorrent client on-device; the SONAME has also drifted past stock's `.so.21` in this version range (Debian ships `libtorrent27` for 0.15.7) so it isn't even a clean 1:1 carry-forward | drop |
| Samba AD DC/ADS (`BR2_PACKAGE_SAMBA4_AD_DC`, `_ADS`) | ~ several MB of python/jansson/openldap deps, per samba4's own `SAMBA4_DEPENDENCIES` gating | MiSTer is a standalone SMB file server, never a domain controller or AD member; leave both sub-options **off** | space + attack-surface reduction |
| `python3.9/` site-packages weight (largest single `/usr/lib` consumer per `disk-usage.md`) | 35.84 MiB | not a drop of the interpreter itself (needed, A6) | P3.9/P2.7 should audit which stock-bundled *site-packages* (if any beyond stdlib) are actually MiSTer-specific vs. generic distro cruft, and whether Buildroot's `python3` install-strip options (`.pyc` optimization, docstring stripping — both selectable in `python3.mk`) are enabled |
| `perl5/` (1484 files) | 27.48 MiB | stock's own init/service scripts are all shell, not Perl — no known MiSTer-specific Perl dependency | audit whether anything MiSTer-specific needs Perl at all; if nothing does, this is the single largest pure-drop candidate in the image — flag for P2.1/P2.7 to verify no hidden Perl dependency (e.g. some util-linux or e2fsprogs helper script) before cutting |
| `vim`, `zsh`, `joe`, `mc` (Midnight Commander), `screen`, `gdb` | ~15 MiB combined (vim 9.13, zsh 4.22, joe 0.3+0.28, mc 1.1+1.1, screen 0.27, gdb 0.4) | interactive power-user shell tools with no MiSTer-specific role; BusyBox's `vi`/`ash` cover the minimum needed for on-device editing/debugging | **RESOLVED (2026-07-14):** `joe` and `nano` are now **enabled** (`BR2_PACKAGE_JOE=y`, `BR2_PACKAGE_NANO=y`) — people SSH in to edit `wpa_supplicant.conf`/`MiSTer.ini`, and BusyBox `vi` is a hostile way to do that. Note `nano` is also in stock (`binaries-needed-full.txt:218`) and was missing from this row. `vim`, `zsh`, `mc`, `screen` remain **off** — `vim` is the heavy one, though its `libgpm` dep is already satisfied (`BR2_PACKAGE_GPM=y`) if full parity is later wanted. **`gdb` is no longer off** (2026-07-21): it is enabled, with gdbserver and the full debugger, by the temporary `DEBUG TOOLING` block — see `docs/debug-tooling.md`. That is *not* a reversal of this row's reasoning (gdb still has no MiSTer-specific role in a shipping image); it is a debugging branch that reverts as one unit, and this row goes back to reading "off" when it does |
| `/usr/share/zoneinfo` full tzdata, `/usr/share/consolefonts`+`/usr/share/keymaps` | ~2.6 MiB (zoneinfo 1.57, fonts+keymaps ~1) | stock's `/timezone` is fixed to `Etc/UTC` anyway; console fonts/keymaps beyond the one stock actually uses are unused | **RESOLVED (2026-07-14) — zoneinfo is now ENABLED (`BR2_TARGET_TZ_INFO=y`, zonelist `default`), reversing the trim.** This row's own caveat is exactly what bit: tzdata was never enabled, so the image shipped with **no `/usr/share/zoneinfo` at all** and no `TZ=` value could resolve. The "stock is fixed to `Etc/UTC` anyway" premise was also wrong — it conflated `/etc/timezone` (a label, indeed `Etc/UTC`) with `/etc/localtime` (the file glibc actually reads), which in stock is a **symlink to `/media/fat/linux/timezone`** on the FAT data partition. That indirection is stock's timezone-*persistence* mechanism: the rootfs is reflashed wholesale on update, so a timezone stored inside it cannot survive. We now ship that same symlink from the rootfs-overlay (it deliberately overwrites the `../usr/share/zoneinfo/Etc/UTC` symlink `BR2_TARGET_LOCALTIME` installs, which would NOT persist). Stock's zoneinfo is plain Buildroot tzdata at the default zonelist (both `posix/` and `right/` subtrees present), so this is a 1:1 reproduction, not a judgement call. Guarded by `scripts/ci-tests.sh` §"Timezone parity". `consolefonts`/`keymaps` remain **off**. ⚠️ **The 1.57 MiB in the Size column understates the real image cost by ~3×.** It is the *apparent* size (sum of file bytes, 1,642,867 B — the units `disk-usage.md` reports). On the ext4 image, zoneinfo's 1,191 mostly-tiny zone files each round up to a 4 KiB block, so actual *block* usage is ~4.9 MB. For size-budget decisions against the fixed 512 MiB image, use block usage, not the byte column — this gap applies to any many-small-files directory in that table. Either way it is not a concern here: ~290 MB of the image is free. |

**Not recommended to drop** (tempting by size, but load-bearing): `python3.9/`
stdlib itself (A6), `samba/` core (15.4 MiB, the actual file-server), `gconv/`
(5.49 MiB, needed for any non-ASCII filename over SMB), `modules/` (24.1 MiB, WiFi/BT
— classes D/E, P3.1-3.3), `firmware/` (2.43 MiB, same).

---

## 6. Ready-to-paste `BR2_PACKAGE_*` list (for P2.1)

Grouped to match the tables above. Comments mark every non-obvious line — the naming
gotchas the task specifically warned about (`LIBOPENSSL` not `OPENSSL`, `LIBCURL` not
`CURL`, `LIBZLIB` not `ZLIB`, etc.), sub-options needed for stock parity that aren't
pulled in by default, and places where a Buildroot `select` already drags in a
dependency transitively so P2.1 shouldn't also set it by hand.

```
# --- toolchain ---
# glibc is the internal-toolchain default; no separate symbol needed beyond the
# normal BR2_TOOLCHAIN_BUILDROOT_* / architecture choice made in P1.x. Enable locale
# support so glibc builds its gconv charset modules (libCNS.so, libGB.so, etc. —
# needed for non-ASCII filenames over SMB):
BR2_ENABLE_LOCALE=y
BR2_TOOLCHAIN_BUILDROOT_CXX=y          # libstdc++ (MiSTer binary, samba4, rtorrent-if-kept)

# --- compression ---
BR2_PACKAGE_ZLIB=y                      # meta-prompt
BR2_PACKAGE_LIBZLIB=y                   # NOT "BR2_PACKAGE_ZLIB" alone -- concrete provider
BR2_PACKAGE_BZIP2=y
BR2_PACKAGE_XZ=y
BR2_PACKAGE_LZO=y

# --- graphics / fonts ---
BR2_PACKAGE_FREETYPE=y
BR2_PACKAGE_LIBPNG=y
BR2_PACKAGE_JPEG=y                       # meta-prompt
BR2_PACKAGE_JPEG_TURBO=y                 # default on ARM/NEON; builds -DWITH_JPEG8=ON
                                          # -> libjpeg.so.8, matching stock exactly
BR2_PACKAGE_TIFF=y
BR2_PACKAGE_GIFLIB=y
BR2_PACKAGE_IMLIB2=y                     # critical ABI-contract SONAME (libImlib2.so.1)
BR2_PACKAGE_LIBXKBCOMMON=y
BR2_PACKAGE_SDL2=y

# --- audio ---
BR2_PACKAGE_ALSA_LIB=y                   # provides libasound + libatopology together
BR2_PACKAGE_LIBAO=y
BR2_PACKAGE_LIBVORBIS=y                  # provides vorbis + vorbisenc + vorbisfile together
BR2_PACKAGE_LIBOGG=y
BR2_PACKAGE_MPG123=y                     # provides libmpg123 + libout123 together
BR2_PACKAGE_LIBID3TAG=y
BR2_PACKAGE_LIBMODPLUG=y
BR2_PACKAGE_FLUIDSYNTH=y
BR2_PACKAGE_FLUIDSYNTH_ALSA_LIB=y         # ALSA-seq MIDI backend -- needed for stock's
                                          # ALSA MIDI device list to match (P3.8)

# --- crypto / TLS ---
BR2_PACKAGE_OPENSSL=y                     # meta-prompt
BR2_PACKAGE_LIBOPENSSL=y                  # NOT "BR2_PACKAGE_OPENSSL" alone -- concrete
                                          # provider. 1.1->3.6.2, SONAME .so.1.1->.so.3,
                                          # harmless (everything rebuilt together, see risk table)
BR2_PACKAGE_GNUTLS=y
BR2_PACKAGE_LIBGCRYPT=y
BR2_PACKAGE_LIBSSH2=y
# nettle, gmp, libtasn1, libgpg-error, libffi are all pulled in transitively as
# dependencies of gnutls/gcrypt/samba4/python3 -- do not set separately.

# --- networking / D-Bus / GLib ---
BR2_PACKAGE_LIBCURL=y
BR2_PACKAGE_LIBCURL_CURL=y                # installs the `curl` CLI binary -- off by
                                          # default, stock ships it, community scripts use it
BR2_PACKAGE_LIBCURL_OPENSSL=y              # TLS backend parity: stock's curl links
                                          # libcrypto/libssl, not GnuTLS
BR2_PACKAGE_DBUS=y
BR2_PACKAGE_DBUS_CPP=y                    # dbusxx-introspect; low-value but zero-cost parity
BR2_PACKAGE_DBUS_GLIB=y
BR2_PACKAGE_LIBEVENT=y
BR2_PACKAGE_LIBNL=y
BR2_PACKAGE_IPTABLES=y
BR2_PACKAGE_LIBGLIB2=y
BR2_PACKAGE_GOBJECT_INTROSPECTION=y

# --- util-linux / e2fsprogs / disk & fs tools ---
BR2_PACKAGE_UTIL_LINUX=y
BR2_PACKAGE_UTIL_LINUX_LIBBLKID=y          # each lib sub-option defaults to "n" --
BR2_PACKAGE_UTIL_LINUX_LIBFDISK=y           # must be listed explicitly or the
BR2_PACKAGE_UTIL_LINUX_LIBMOUNT=y           # corresponding SONAME won't be built
BR2_PACKAGE_UTIL_LINUX_LIBSMARTCOLS=y
BR2_PACKAGE_UTIL_LINUX_LIBUUID=y
BR2_PACKAGE_E2FSPROGS=y
BR2_PACKAGE_PARTED=y
BR2_PACKAGE_NTFS_3G=y                       # stock has no NTFS driver at all (kernel side);
                                            # this is userland-only parity for exFAT/NTFS
                                            # USB drives via FUSE, matches stock's ntfs-3g
BR2_PACKAGE_KMOD=y
BR2_PACKAGE_INOTIFY_TOOLS=y
BR2_PACKAGE_JQ=y
BR2_PACKAGE_EXPAT=y
BR2_PACKAGE_POPT=y
BR2_PACKAGE_READLINE=y
BR2_PACKAGE_NCURSES=y
BR2_PACKAGE_SLANG=y
BR2_PACKAGE_NEWT=y
BR2_PACKAGE_GPM=y
BR2_PACKAGE_LIBARCHIVE=y                    # keep the library (samba4 can use it); do NOT
                                            # package archivemount itself -- see Drop list
BR2_PACKAGE_LIBFUSE=y                        # ditto -- real dependents may want it even
                                            # though archivemount itself is dropped

# --- USB / input ---
BR2_PACKAGE_LIBUSB=y
BR2_PACKAGE_LIBUSB_COMPAT=y                 # legacy libusb-0.1 API shim -- still NEEDed
                                            # by name (libusb-0.1.so.4) in stock's binary set
BR2_PACKAGE_LIBEVDEV=y
BR2_PACKAGE_LIBINPUT=y
BR2_PACKAGE_MTDEV=y

# --- Bluetooth ---
BR2_PACKAGE_BLUEZ5_UTILS=y
BR2_PACKAGE_BLUEZ5_UTILS_DEPRECATED=y        # hciconfig/hcitool/sdptool/rfcomm/l2ping/
                                             # hcidump -- all present in stock, gated by
                                             # this option upstream now
BR2_PACKAGE_BLUEZ5_UTILS_PLUGINS_SIXAXIS=y   # PS3 controller BT pairing (selects
                                             # _PLUGINS_HID transitively -- don't set that too)

# --- PAM / capabilities ---
BR2_PACKAGE_LINUX_PAM=y
BR2_PACKAGE_LIBCAP=y
BR2_PACKAGE_LIBCAP_NG=y

# --- misc small libraries / tools ---
BR2_PACKAGE_DTC=y                            # libfdt
BR2_PACKAGE_SUDO=y
BR2_PACKAGE_I2C_TOOLS=y                       # for the i2c-gpio RTC add-on, P3.11
BR2_PACKAGE_JIMTCL=y                          # NOT just an obscure shell -- usb_modeswitch's
                                              # dispatcher (3G/LTE modem support) needs it
BR2_PACKAGE_LIBLOCKFILE=y
BR2_PACKAGE_LIBXML2=y
BR2_PACKAGE_FILE=y                            # libmagic
# PCRE1 removed upstream in Buildroot 2026.05 (EOL); nothing in the image needs
# libpcre.so.1 (see the libpcre rows above). PCRE2 is the replacement:
BR2_PACKAGE_PCRE2=y                           # libpcre2-8.so.0 -- PCRE1 replacement
BR2_PACKAGE_EUDEV=y                           # NOT mdev -- PLAN §3 explicit requirement

# --- lftp ---
BR2_PACKAGE_LFTP=y                            # provides all 4 bundled liblftp-*.so together

# --- Python (A6) ---
BR2_PACKAGE_PYTHON3=y                         # 3.14.5 -- no legacy-version toggle exists in
                                              # Buildroot 2026.02; see P3.9 risk entry

# --- Samba (single package covers ~125 of the 251 SONAMEs, see section 1) ---
BR2_PACKAGE_SAMBA4=y
# Deliberately NOT set (standalone file server only, not a domain controller/member):
#   BR2_PACKAGE_SAMBA4_AD_DC
#   BR2_PACKAGE_SAMBA4_ADS
#   BR2_PACKAGE_SAMBA4_SMBTORTURE

# --- daemons / user-facing binaries (section 2) ---
BR2_PACKAGE_OPENSSH=y
BR2_PACKAGE_PROFTPD=y
BR2_PACKAGE_WPA_SUPPLICANT=y
BR2_PACKAGE_WPA_SUPPLICANT_NL80211=y          # default y already, listed for clarity
BR2_PACKAGE_WPA_SUPPLICANT_WEXT=y             # stock's interfaces file passes
                                              # "-D nl80211,wext" -- both drivers needed
BR2_PACKAGE_DHCPCD=y
BR2_PACKAGE_NTP=y                             # classic ntpd, matches stock -- NOT chrony/openntpd
BR2_PACKAGE_CIFS_UTILS=y
BR2_PACKAGE_NFS_UTILS=y
BR2_PACKAGE_RSYNC=y
BR2_PACKAGE_BUSYBOX=y                         # 1.37.0, always on; stock parity for the
                                              # 274-applet set is a P2.3 config concern, not
                                              # a package-selection one

# --- explicitly NOT carried forward (Drop list, section 5) ---
#   archivemount (broken in stock; its deps libarchive/libfuse ARE kept above for others)
#   adplay / adplug / binio          -- no Buildroot package, no known MiSTer use
#   libhid / libhid-detach-device    -- no Buildroot package, superseded API
#   jack1/jack2 (libjack)            -- dangling in stock, unused by MiSTer
#   rtorrent / libtorrent            -- unused BitTorrent client, SONAME already drifted
```

> ⚠ **This list is deliberately not identical to the live defconfig.**
> `configs/mister_de10nano_defconfig` currently also carries a bannered
> `DEBUG TOOLING` block — gdb (+ gdbserver + full debugger), strace,
> perf and rt-tests — which is **temporary and out of scope for this manifest**: it is
> not stock parity and never claimed to be. Do **not** reconcile the two by
> adding those symbols here, and do **not** "fix" the defconfig by deleting the
> block. See `docs/debug-tooling.md`; it goes away as one unit when the
> investigations that justify it close, at which point the two agree again.
> (The field hard-hang half **closed 2026-07-21**; the RT-latency measurement
> is still outstanding, so the block stays for now.)

---

## Summary for the report

- **Buildroot ref this mapping was read from**: branch `2026.02.x` @
  `679b9ead7620bbf193620d1ebf56f53c1764d37a` = tag `2026.02.3`. **The image now ships
  2026.05.1** — see the note at the top of this document for what that does and does not
  change.
- **12/12 critical ABI-contract SONAMEs (PLAN §3) confirmed at the same major version**
  in Buildroot 2026.02.3, including the two PLAN flagged as highest-risk
  (`libbluetooth.so.3`, `libImlib2.so.1`) — cross-checked against current Arch/Debian
  packaging as an independent sanity check. **No project-threatening finding here.**
- **0 of 251 SONAMEs unmapped** — every one has a package, a toolchain/glibc
  attribution, or an explicit gap-with-disposition.
- **3 confirmed already-broken-in-stock dangling dependencies** (P0.3):
  `archivemount`'s `libarchive.so.13`+`libfuse.so.2`, and `libjack.so.0.0.28`'s
  `libdb-5.3.so`. All three: the *library* side generally does exist in Buildroot, but
  recommend dropping the *broken consumer* rather than reproducing it.
- **3 true gaps with zero Buildroot package**: `libhid`/`libhid-detach-device`,
  `libadplug`+`libbinio`/`adplay`. All three: obscure, unused by MiSTer, drop.
- **Top version-jump risks**: Samba 4.14→4.23 (config/behavior audit, owner P3.6),
  OpenSSH 8.6→10.2 combined with the pre-existing `PermitRootLogin yes` +
  fixed-default-password posture (owner P3.7, document don't silently fix), Python
  3.9→3.14 against `Downloader_MiSTer`'s own 3.9-pinned CI (owner P3.9, A6).