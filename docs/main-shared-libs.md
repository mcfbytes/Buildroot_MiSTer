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

A **sixth** library, `rcheevos`, is built and shipped from that same menu but
is **not part of this refactor** and is tracked separately below. The
distinction is worth keeping: the five replace code Main already vendors, so
each one's success condition is "Main stops carrying a copy". rcheevos
replaces nothing — it adds a capability the image did not have, and nothing
links it yet.

## The five packages

| Package | Provider | SONAME | Headers | pkg-config | Notes |
|---|---|---|---|---|---|
| zstd (`BR2_PACKAGE_ZSTD`) | upstream Buildroot | `libzstd.so.1` | `zstd.h` (top-level `/usr/include`) | `libzstd.pc` | Also installs the `zstd` CLI — upstream has no sub-option to omit it. Needed by libchdr (CHD v5 zstd hunks) and flips minizip-ng's `MZ_ZSTD=ON`. |
| minizip (`BR2_PACKAGE_MINIZIP`) | upstream Buildroot | `libminizip-ng.so.4` | `include/minizip-ng/` | `minizip-ng.pc` | This IS **minizip-ng 4.0.3** (zlib-ng/minizip-ng), NOT the classic zlib-contrib API (that is `BR2_PACKAGE_MINIZIP_ZLIB`, a separate package — see the row below). Buildroot forces `-DMZ_COMPAT=OFF`, so there is **no `zip.h`/`unzip.h` compat layer** — the native `mz_zip.h` API is retained for an eventual Main port. Feature set under our defconfig: bzip2 + openssl (pkcrypt/wzaes) + lzma-via-xz + zlib + zstd; no iconv (locale on). |
| minizip-zlib (`BR2_PACKAGE_MINIZIP_ZLIB`) | upstream Buildroot | `libminizip.so.1` | `include/minizip/` | `minizip.pc` | The **classic zlib-contrib minizip** (zlib 1.3.1 `contrib/minizip`, autotools), `select`s zlib. **Enabled for backward compatibility**: the current Main_MiSTer shared-lib cleanup links `libminizip.so.1` (a `NEEDED` in the `MiSTer` binary) via the `zip.h`/`unzip.h` API (`zipOpen`/`unzOpen`), so the target must ship it. Coexists with minizip-ng — distinct SONAME (`.so.1` vs `-ng.so.4`) and non-overlapping symbols (`zipOpen`/`unzOpen` vs `mz_*`), so both load conflict-free. |
| lzma-sdk (`BR2_PACKAGE_LZMA_SDK`) | BR2_EXTERNAL (`package/lzma-sdk`) | `liblzma-sdk.so.26.03` | `include/lzma-sdk/` (13 headers, Main's vendored `lib/lzma` set 1:1) | `lzma-sdk.pc` | 7-Zip LZMA SDK 26.03, built `-DZ7_ST` (single-threaded — same as Main's vendored build). **The SONAME is the full SDK version, deliberately**: upstream gives no ABI guarantees between releases and the API embeds caller-allocated structs (`CLzmaDec` by value), so a silent struct-layout change is memory corruption, not an error. A full-version SONAME turns every SDK bump into a *loud* ABI event — an old binary refuses to load with a clean linker error. That matters here because the `MiSTer` binary lives on `/media/fat` and **survives rootfs reflashes**; stale-binary-meets-new-rootfs is the expected failure mode. NOT xz-utils' `liblzma.so.5` — entirely different API. |
| libchdr (`BR2_PACKAGE_LIBCHDR`) | BR2_EXTERNAL (`package/libchdr`) | `libchdr.so.0` (real file `libchdr.so.0.3`) | `include/libchdr/` | `libchdr.pc` | Commit-pinned past `v0.3.0` (the tag can't configure against Buildroot's zstd — no `Findzstd` pkg-config fallback yet). Built against **system zlib/zstd/lzma-sdk** via our patches 0001–0003; the header-only **dr_flac stays bundled** (header-only by design, and `libchdr_flac.c` pokes drflac internals — no `.so` exists to unbundle to). Exports **`chd_*` only** (upstream's version script `src/link.T`), so no `mz_*` or other symbol collision with minizip-ng et al. **"System zlib" here is zlib-ng in `ZLIB_COMPAT` mode** (`BR2_PACKAGE_ZLIB_NG`, defconfig compression block): same `libz.so.1`, same `zlib.h`, so nothing changes at link or `pkg-config` time — and it is the whole point of unbundling, since a *shared* libchdr is what actually reaches system zlib (stock's static libchdr decodes through its own vendored miniz instead). Measured on the rig: CHD audio-hunk decode p90 −10 to −11 %, LZMA-dominated data hunks unchanged (`harness/rig/chd-decode-optimization.md` in Main_MiSTer). |

## The sixth library: rcheevos (not part of the refactor)

| Package | Provider | SONAME | Headers | pkg-config | Notes |
|---|---|---|---|---|---|
| rcheevos (`BR2_PACKAGE_RCHEEVOS`) | BR2_EXTERNAL (`package/rcheevos`) | `librcheevos.so.12.5.0` | `include/rcheevos/` (15 from upstream's `include/`, plus `rc_version.h` from `src/`) | `rcheevos.pc` | RetroAchievements' own client library — achievement/leaderboard evaluation, the RetroAchievements web API marshalling (`rapi`), game-identification hashing (`rhash`), and `rc_client`. Tag-pinned `v12.5.0`. **No consumer links it yet**; it is shipped so one can. 273 KiB as shipped (279,580 bytes, stripped; the staging copy is 330 KiB unstripped). Upstream ships no Unix build system, so the package compiles it directly like `lzma-sdk`. Three sources are excluded (`rc_libretro.c` needs `<libretro.h>`; `rc_client_external.c` and `rc_client_raintegration.c` are empty translation units without their Windows/external-ABI defines). |

Two properties of this one are worth knowing before linking it:

- **The SONAME is the full version, and here that is not a precaution —
  upstream has changed caller-allocated public struct layouts in *patch*
  releases.** `v10.7.1` added `char owns_self;` to the public `rc_runtime_t`;
  `v10.3.3` inserted `const char* display_name;` into the *middle* of
  `rc_api_login_response_t`; `v6.0.1` redefined `RC_ALIGNMENT` from `8` to
  `sizeof(void*)`, which changes padding library-wide on a 32-bit target like
  this one. Minor releases do it too (`v12.4.0` grew `rc_client_user_t`).
  Derived by diffing `include/` across all 55 upstream tags. Same
  `/media/fat` stale-binary hazard as `lzma-sdk`, with harder evidence: every
  bump must be a clean refuse-to-load, so every bump is a rebuild-your-
  consumer event.
- **It is built `-DRC_SHARED -fvisibility=hidden`, so only the 264
  `RC_EXPORT`-annotated entry points are exported** (477 without). This is
  not tidiness: the suppressed symbols include `md5_init`/`md5_append`/
  `md5_finish` and six `AES_*` entry points, and ELF interposition is
  first-definition-wins, so exporting those into a process that has its own
  md5 — which Main does, `lib/md5` — is a silent wrong-function bind rather
  than a link error. It is the same guarantee libchdr gets from its version
  script, obtained a different way. Patch `0001` is load-bearing for it:
  `rc_util.h` is the one public header upstream left un-annotated, so without
  it nine declared entry points would be hidden and the installed headers
  would promise an API the `.so` does not export.

`rcheevos.pc` carries **`-DRC_CLIENT_SUPPORTS_HASH` and `-DRC_IMPORT` in its
`Cflags`**, and a consumer must not drop them: the first gates *public header
declarations* (`rc_client.h` lines 265 and 333, the
`rc_client_begin_identify_and_load_game` family), so without it a consumer's
`rc_client.h` hides functions the `.so` genuinely exports.

### Its two vendored files, and why neither is unbundled

rcheevos has no `deps/` or `third_party/` directory, so it *looks* like it is
all upstream's own code. It is not, quite: two vendored third-party
implementations are compiled into the shipped `.so`, and both carry their own
grant, which is why `RCHEEVOS_LICENSE` is `MIT, Zlib (md5), Unlicense
(tiny-AES-c)` and not plain MIT.

| File | Origin | Used by | Unbundle to `/usr/lib`? |
|---|---|---|---|
| `src/rhash/md5.{c,h}` | L. Peter Deutsch / Aladdin, 1999–2002; the notice is the **zlib licence verbatim** (upstream Buildroot spells this same file `Zlib (md5)` in `package/rtty`) | 12 files across `rhash`, `rapi` and the runtime | **No** — see below |
| `src/rhash/aes.{c,h}` | `kokke/tiny-AES-c` @ `f06ac37`, "with unused code excised", Unlicense | `hash_encrypted.c` only | **No** — the question is whether to compile it at all |

**md5 → OpenSSL `libcrypto.so.3`** (which this image already ships) was
considered and **rejected**. OpenSSL 3.x deprecates the low-level
`MD5_Init`/`MD5_Update`/`MD5_Final` API in favour of `EVP`, which is a
different shape from the incremental `md5_init`/`md5_append`/`md5_finish` that
rcheevos threads through 12 files — so this is an invasive, permanently-carried
patch re-validated on every monthly bump. The maintenance argument that
normally justifies unbundling does not apply either: `md5.c` has changed
**twice in rcheevos's entire history** (last 2023-02-23) and `md5.h` **once**
(2020-01-04), and MD5 here is content identification, not security, so there is
no CVE stream to track. The one argument that survives is **performance** —
OpenSSL has hand-written ARM assembly MD5 where this is plain C, which could
matter when hashing a full disc image. That is **unmeasured and deliberately
left so**: it cannot be timed honestly under `qemu-arm` (which JITs asm and C
alike), it needs the rig, and nothing links rcheevos yet. Revisit it with a
real measurement when a consumer exists, not before.

**aes** is not an unbundling question at all. `hash_encrypted.c` is **entirely
Nintendo 3DS** — every function in it is `rc_hash_nintendo_3ds*` (CIA/NCCH/3DSX
container decryption) — so on a board with no 3DS core the honest option is not
"link a different AES" but `-DRC_HASH_NO_ENCRYPTED`, which upstream supports as
a first-class switch. **Measured: that saves 8,088 bytes** (279,580 → 271,492
stripped). It is left **on**, for two reasons: 8 KB is noise against the size
budget, and narrowing a library that nothing links yet is the wrong default,
since a consumer cannot turn it back on without a rebuild. Note it would not
reduce "AES in the image" anyway — `libcrypto.so.3` ships a much larger one.
If it is ever wanted off, the define is **ABI-visible** (it gates declarations
in `include/rc_hash.h` lines 100–126 and 141), so it must go in `rcheevos.pc`'s
`Cflags` as well as the build, exactly like `RC_CLIENT_SUPPORTS_HASH`.

Nothing else is vendored: `hash_zip.c` walks the zip central directory and
never inflates, so there is no bundled zlib/miniz to unbundle — unlike
`libchdr`, whose whole patch series exists for that.

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
hand-written install ships only `liblzma-sdk.so.26.03` — its filename is
the SONAME, which is all the runtime linker needs.

Note that `minizip` and `minizip-ng` are alternatives, not a pair: Main links
the **classic** `minizip` (`libminizip.so.1`) today, and `minizip-ng` is built
and staged only so the eventual native-`mz_zip.h` port has something to link.
Both are shipped, but a given binary links one or the other.

Mapping from Main's vendored `lib/` dirs to their replacements
(user decision 2026-07-17 for the miniz row: refactor to zlib + minizip):

| Main `lib/` dir | Replacement | Status |
|---|---|---|
| `lib/lzma` | `lzma-sdk` (`liblzma-sdk.so.26.03`) | this workstream |
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
- **The stage-1 initramfs stacks / installer defconfig are deliberately
  unchanged** — static busybox, no ABI surface, nothing there links any of
  these.
- Renovate manages all three BR2_EXTERNAL pins (`lib-pin` label); hashes
  auto-refresh via `renovate-hash-sync.yml` (generic loop for libchdr and
  rcheevos, a bespoke release-asset step for lzma-sdk). See
  `docs/renovate.md`.
- **rcheevos has no Main-side mapping row above and should not get one**
  until something links it. `scripts/check-abi.sh` stays untouched for it for
  the same reason it does for the other five, only more so — no shipped
  binary DT_NEEDs `librcheevos.so.12.5.0`. Its only CI cover is the
  presence-in-rootfs assertion in `scripts/ci-tests.sh`, which is deliberate:
  a library with no consumer has no other way to fail visibly.
