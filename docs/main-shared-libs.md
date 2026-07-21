# Main_MiSTer shared libraries — Buildroot providers

Workstream: the **Main_MiSTer shared-lib refactor** (no task ID — referenced
by name). Main_MiSTer today vendors several compression/container libraries
as source copies under its own `lib/` directory and statically compiles them
into the `MiSTer` binary. This refactor has Main stop vendoring
`lib/{lzma,zstd,miniz,libchdr}` and instead link Buildroot-provided **shared**
libraries, built once, shipped in the rootfs, and shared with anything else
that needs them. This document is the reference for that refactor's actual
consumer: which package provides what, under which SONAME/header-dir/pkg-config
name, and how Main's vendored dirs map onto them.

Three of the five packages are upstream Buildroot, enabled straight from
`configs/mister_de10nano_defconfig` (compression block); the other two are
authored in this tree under `package/` and sourced via the
"Main_MiSTer shared libraries" menu in the top-level `Config.in`.

## The five packages

| Package | Provider | SONAME | Headers | pkg-config | Notes |
|---|---|---|---|---|---|
| zstd (`BR2_PACKAGE_ZSTD`) | upstream Buildroot | `libzstd.so.1` | `zstd.h` (top-level `/usr/include`) | `libzstd.pc` | Also installs the `zstd` CLI — upstream has no sub-option to omit it. Needed by libchdr (CHD v5 zstd hunks) and flips minizip-ng's `MZ_ZSTD=ON`. |
| minizip (`BR2_PACKAGE_MINIZIP`) | upstream Buildroot | `libminizip-ng.so.4` | `include/minizip-ng/` | `minizip-ng.pc` | This IS **minizip-ng 4.0.3** (zlib-ng/minizip-ng), NOT the classic zlib-contrib API (that is `BR2_PACKAGE_MINIZIP_ZLIB`, a separate package — see the row below). Buildroot forces `-DMZ_COMPAT=OFF`, so there is **no `zip.h`/`unzip.h` compat layer** — the native `mz_zip.h` API is retained for an eventual Main port. Feature set under our defconfig: bzip2 + openssl (pkcrypt/wzaes) + lzma-via-xz + zlib + zstd; no iconv (locale on). |
| minizip-zlib (`BR2_PACKAGE_MINIZIP_ZLIB`) | upstream Buildroot | `libminizip.so.1` | `include/minizip/` | `minizip.pc` | The **classic zlib-contrib minizip** (zlib 1.3.1 `contrib/minizip`, autotools), `select`s zlib. **Enabled for backward compatibility**: the current Main_MiSTer shared-lib cleanup links `libminizip.so.1` (a `NEEDED` in the `MiSTer` binary) via the `zip.h`/`unzip.h` API (`zipOpen`/`unzOpen`), so the target must ship it. Coexists with minizip-ng — distinct SONAME (`.so.1` vs `-ng.so.4`) and non-overlapping symbols (`zipOpen`/`unzOpen` vs `mz_*`), so both load conflict-free. |
| lzma-sdk (`BR2_PACKAGE_LZMA_SDK`) | BR2_EXTERNAL (`package/lzma-sdk`) | `liblzma-sdk.so.26.02` | `include/lzma-sdk/` (13 headers, Main's vendored `lib/lzma` set 1:1) | `lzma-sdk.pc` | 7-Zip LZMA SDK 26.02, built `-DZ7_ST` (single-threaded — same as Main's vendored build). **The SONAME is the full SDK version, deliberately**: upstream gives no ABI guarantees between releases and the API embeds caller-allocated structs (`CLzmaDec` by value), so a silent struct-layout change is memory corruption, not an error. A full-version SONAME turns every SDK bump into a *loud* ABI event — an old binary refuses to load with a clean linker error. That matters here because the `MiSTer` binary lives on `/media/fat` and **survives rootfs reflashes**; stale-binary-meets-new-rootfs is the expected failure mode. NOT xz-utils' `liblzma.so.5` — entirely different API. |
| libchdr (`BR2_PACKAGE_LIBCHDR`) | BR2_EXTERNAL (`package/libchdr`) | `libchdr.so.0` (real file `libchdr.so.0.3`) | `include/libchdr/` | `libchdr.pc` | Commit-pinned past `v0.3.0` (the tag can't configure against Buildroot's zstd — no `Findzstd` pkg-config fallback yet). Built against **system zlib/zstd/lzma-sdk** via our patches 0001–0003; the header-only **dr_flac stays bundled** (header-only by design, and `libchdr_flac.c` pokes drflac internals — no `.so` exists to unbundle to). Exports **`chd_*` only** (upstream's version script `src/link.T`), so no `mz_*` or other symbol collision with minizip-ng et al. |

## How Main links these

Against the Buildroot staging sysroot, by pkg-config name — no hardcoded
paths: `libzstd`, `minizip` (classic), `minizip-ng`, `lzma-sdk`, `libchdr`.
All five set `INSTALL_STAGING = YES`, so headers + the unversioned dev symlink
land in staging and `pkg-config --cflags --libs <name>` against
`output/staging` resolves everything — for the classic one that is
`pkg-config --cflags --libs minizip` → `-I/usr/include/minizip -lminizip`.
On the target, zstd/minizip/minizip-ng/libchdr (infra-installed) ship the
versioned `.so` plus the usual unversioned symlink (Buildroot's
target-finalize prunes headers/`.pc`/`.a`, not `.so` symlinks); lzma-sdk's
hand-written install ships only `liblzma-sdk.so.26.02` — its filename is
the SONAME, which is all the runtime linker needs.

Note that `minizip` and `minizip-ng` are alternatives, not a pair: Main links
the **classic** `minizip` (`libminizip.so.1`) today, and `minizip-ng` is built
and staged only so the eventual native-`mz_zip.h` port has something to link.
Both are shipped, but a given binary links one or the other.

Mapping from Main's vendored `lib/` dirs to their replacements
(user decision 2026-07-17 for the miniz row: refactor to zlib + minizip):

| Main `lib/` dir | Replacement | Status |
|---|---|---|
| `lib/lzma` | `lzma-sdk` (`liblzma-sdk.so.26.02`) | this workstream |
| `lib/zstd` | `zstd` (`libzstd.so.1`) | this workstream |
| `lib/libchdr` | `libchdr` (`libchdr.so.0`) | this workstream |
| `lib/miniz` | port to zlib + classic minizip (`libminizip.so.1`, `zip.h`/`unzip.h` API) for backward compatibility; minizip-ng (`libminizip-ng.so.4`) stays available for a future native-`mz_zip.h` port | this workstream |
| `lib/bluetooth` | `bluez5_utils` (`libbluetooth.so.3`) | already shipped |
| `lib/imlib2` | `imlib2` (`libImlib2.so.1`) | already shipped |
| `lib/md5` | OpenSSL `libcrypto` — or keep static (tiny) | Main-side call |
| `lib/libco` | **keep static** — hot-path `co_switch`, ~50 lines of ARM asm; a shared-lib indirection buys nothing and costs a PLT hop | decided |

## What this does NOT change (yet)

- **`scripts/check-abi.sh` is deliberately untouched.** Its SONAME contract
  list asserts what the *stock* `MiSTer` binary needs today. The five new
  SONAMEs get added there **when Main actually links them** — asserting them
  as ABI-contract members before any shipped binary DT_NEEDs them would be
  a false contract. That includes `libminizip.so.1`: the in-progress
  shared-lib cleanup DT_NEEDs it, but the *stock* binary still vendors
  `lib/miniz`, so the contract list stays as-is until that Main ships. Until then, `scripts/ci-tests.sh`'s
  "Main_MiSTer shared libraries" section asserts presence-in-rootfs
  (wildcarded versions, so Renovate bumps don't go stale-red — the PR #35
  lesson, commit `1341c93`).
- **`mister_initramfs_defconfig` / installer defconfigs are deliberately
  unchanged** — static busybox, no ABI surface, nothing there links any of
  these.
- Renovate manages both new pins (`lib-pin` label); hashes auto-refresh via
  `renovate-hash-sync.yml` (generic loop for libchdr, a bespoke
  release-asset step for lzma-sdk). See `docs/renovate.md`.
