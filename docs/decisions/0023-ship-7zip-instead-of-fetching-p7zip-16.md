# ADR 0023 — Ship a static 7-Zip 26.02 as `/media/fat/linux/7za` instead of letting the Downloader fetch p7zip 16.02

**Status:** Accepted (2026-07-27) — decided by @mcfbytes
**Impact:** New `package/7zip/` (replaces the `BR2_PACKAGE_P7ZIP` selection);
`configs/mister_de10nano_defconfig`; `Config.in` (new menu);
`.github/workflows/release.yml` (one more `files/linux/` payload member);
`scripts/mk-sdcard.sh` + `docs/verification/sdcard-payload.md` (one more FAT
payload file); `scripts/ci-tests.sh`; `renovate.json` +
`.github/workflows/renovate-hash-sync.yml` +
`scripts/hash-sync-ip7z-src.sh` (renamed from `hash-sync-lzma-sdk.sh`).
**Relates to:** `docs/downloader-contract.md` §4 (the mechanism this changes,
and the hard archive-compatibility constraint it does **not** change),
ADR 0020 (the exFAT installer whose payload now carries the binary),
`package/lzma-sdk` (same upstream release asset, different half of it).

> **Update 2026-09-04 — the pin has moved; this ADR has not.** Everything
> below is the record as decided and verified on 2026-07-27, against 7-Zip
> **26.02**, and is deliberately left at that version: the verification
> section describes commands actually run then, and rewriting their output
> would falsify the record. The decision (ship 7-Zip from source instead of
> letting the Downloader fetch p7zip 16.02) is version-independent and still
> stands. The **current** pin is **26.03** — `package/7zip/7zip.mk` and
> `package/lzma-sdk/lzma-sdk.mk` are the source of truth for it.
>
> One behavior described below has since changed. The verification bullet
> "provenance lines beneath the first `sha256` line untouched" recorded the
> hash-sync's *original* rule: refresh the tarball hash only, and let a
> changed license file fail the build closed for a human to re-derive. The
> 26.03 bump showed that fail-closed lands as a red master rather than a red
> PR (it fires in `make legal-info`, at the end of an ~80-minute build), so
> `scripts/hash-sync-ip7z-src.sh` now also refreshes the hashes of the files
> named in each package's `*_LICENSE_FILES` and prints a diff of any that
> changed. See that script's header for the full rationale.

## 1. The problem

Nothing in the installed MiSTer image can extract a `.7z`, yet every Linux
update *is* a `.7z`. Upstream's answer is to download an extractor on demand:

```python
FILE_7z_util: Final[str] = '/media/fat/linux/7za'
FILE_7z_util_uninstalled: Final[str] = '/media/fat/linux/7za.gz'
def FILE_7z_util_uninstalled_description() -> SafeFetchInfo: return {
    'url': 'https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/raw/master/7za.gz',
    'hash': 'ed1ad5185fbede55cd7fd506b3c6c699',
    'size': 465600
}
```
— `Downloader_MiSTer/src/downloader/constants.py:89-95`, fetched by
`linux_updater.py:93-98` whenever that path does not exist.

Fetched and identified directly, not inferred from the URL:

```
$ md5sum 7za.gz
ed1ad5185fbede55cd7fd506b3c6c699  7za.gz          # matches the pin
$ file 7za
ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, ...
$ ./7za
7-Zip (a) [32] 16.02 : Copyright (c) 1999-2016 Igor Pavlov : 2016-05-21
p7zip Version 16.02 (locale=C.UTF-8,Utf16=on,HugeFiles=on,32 bits,32 CPUs LE)
```

So the binary that unpacks every OS update on every MiSTer is **p7zip 16.02,
dated 2016-05-21** — ten years of unreviewed archive-parsing code, reached over
the network, and **dynamically linked**. Three things are wrong with that:

1. **Age.** p7zip is dead upstream at 16.02; even the community fork
   (`p7zip-project`, which Buildroot packages) stopped at 17.06 in 2022.
   Meanwhile 7-Zip itself has had native Linux support since 21.01 and is at
   26.02. A 2016 archive parser is exactly the component you least want frozen.
2. **A network dependency inside the update path.** An update on a fresh card
   cannot proceed until an unrelated GitHub raw URL serves a 465 KiB file.
3. **It is dynamically linked**, and it lives on the *persistent* partition
   (`docs`: persistent state lives on `/media/fat`), so it outlives the rootfs
   that installed it.

We already vendor this exact upstream source: `package/lzma-sdk` pins
`ip7z/7zip` 26.02's release asset and compiles eight `C/` files into
`liblzma-sdk.so`. The application in `CPP/` was simply going unbuilt.

## 2. Decision

**Build upstream 7-Zip from the tarball we already pin, and ship it into
`/media/fat/linux/7za` ourselves, statically linked.** The Downloader's
existence check then never fires and no 2016 binary is ever fetched.

`package/7zip/` builds `CPP/7zip/Bundles/Alone2` once and takes two artifacts
out of it:

| Artifact | Linkage | Goes to |
|---|---|---|
| `7zz` (+ `7za` and `7zr` aliases) | dynamic | `$(TARGET_DIR)/usr/bin/` — the ordinary on-device archiver |
| `7zzs` | **static** | `$(BINARIES_DIR)/7za` — a payload artifact, not a rootfs file |

The payload artifact reaches the card by both routes that write it:

- `.github/workflows/release.yml` adds it to `release-stage/files/linux/`, so
  the Downloader's own flash-phase `rsync` lands it at `/media/fat/linux/7za`.
  That `rsync` has no `--delete` but **does** overwrite sources it carries, so
  every update replaces whatever binary a device already had.
- `scripts/mk-sdcard.sh` stages it at `mister-payload/linux/7za`, so a card
  flashed from `sdcard.img` has it from first boot and never fetches even once.

`BR2_PACKAGE_P7ZIP` / `_P7ZIP_7ZR` are deselected. Both `7za` **and** `7zr`
are aliased to `7zz`. The `7zr` alias was initially refused — in real 7-Zip
that name means the *reduced* 7z-only build — and that reasoning was reversed
on one checked fact: `usr/bin/7zr` is the **only** 7-Zip-family binary stock's
rootfs contains (no `7z`, no `7za`; verified against `work/imgroot`, and it is
itself p7zip 16.02). It is therefore the only such name a third-party MiSTer
script can portably call, and dropping it would be a silent parity regression
for a zero-byte symlink. "Misleading" can only mean *more* capable than the
name promises here, never less — the same argument already made for `7za`.

### Why static is a requirement, not an optimization

This is the load-bearing part of the decision. The binary sits on the
persistent partition and outlives the rootfs that placed it. Three ordinary
sequences hand it a glibc it was not linked against:

- a `u-boot.txt` `_vN` rollback to an older `linux.img` of ours;
- a rollback to a **stock** image (glibc ~2.32 against our 2.43);
- a stock user who once installed our release and later runs stock's
  Downloader — precisely when a working updater matters most.

Dynamically linked, it dies at `exec` with `GLIBC_2.xx not found` and the
update fails at its first `7za t`, in the one situation where you are trying to
recover. Static removes the failure mode outright. Stock's own binary *is*
dynamic and has gotten away with it only because stock's userland barely moves
(see `scripts/verify-stock-payload.sh`'s sysroot comment) — not a property we
have or want to depend on.

## 3. What this does NOT change

**Our release archive must still be extractable by the old pinned binary**, and
`docs/downloader-contract.md` §4's hard constraint stands unaltered. The reason
is a chicken-and-egg that shipping a new extractor cannot escape: the update
that *installs* our `7za` is itself unpacked by whatever `7za` was already
there. On a device that has never updated, that is p7zip 16.02. So
`release.yml`'s qemu-arm round-trip against the **exact** pinned 2016 binary
stays, and must keep passing. Self-healing is per-device and takes one update.

## 4. Evidence (verified, not assumed)

- **Behavioural equivalence on the real command pair.** `linux_updater.py`
  issues `7za t <archive>` then
  `7za x -y <archive> files/linux/* -o<dir>` — the wildcard reaching 7-Zip
  literally, since the on-device shell has no such directory to expand it
  against. Both binaries were run under `qemu-arm` on the same solid-LZMA2
  archive: both exited 0 on `t` and on `x`, and the extracted trees were
  **byte-identical**, with `files/MiSTer` correctly *not* extracted. That last
  part is the subtle one — a pattern-matching regression would extract the
  whole archive and no exit code would reveal it, so `scripts/ci-tests.sh` now
  asserts it directly.
- **The alias is safe.** 7-Zip does **not** dispatch on `argv[0]`: there is no
  basename/`argv[0]` inspection in `CPP/7zip/UI/Console/Main.cpp`. The
  `7zz`/`7za`/`7zr` distinction in p7zip and in upstream's own `Bundles/` is
  *which codecs were compiled in*, not a runtime mode. So `7za` is genuinely
  the full archiver.
- **Static linkage checked structurally**, not by parsing `file`: zero `INTERP`
  segments, zero `NEEDED` entries (`readelf -l` / `-d`).
- **The hash is enforced.** A deliberately corrupted `7zip.hash` was planted
  and the build failed closed —
  `ERROR: 7z2602-src.tar.xz has wrong sha256 hash` / `expected:` / `got:` —
  then restored and rebuilt. `BR2_DOWNLOAD_FORCE_CHECK_HASHES=y` is what makes
  that real.
- **The hash-sync generalization was fixture-tested**, not just written: both
  `.hash` files refreshed to the correct sha256, provenance lines beneath the
  first `sha256` line untouched, one outcome row per package.

## 5. Costs accepted

- **~2.9 MiB** on the data partition and ~1 MiB inside `release_*.7z`, against
  the 465 KiB gzipped binary it displaces. Traded for no network fetch in the
  update path and a decade of upstream fixes.
- **Rootfs grows** by the difference between `7zz` (~2.3 MiB) and the `7zr` it
  replaces, in exchange for full-format coverage (zip/tar/xz/zstd/wim/iso/…).
- **The unRAR license restriction is now in scope.** `7zz` compiles the Rar
  decoders, so `DOC/License.txt`'s "LGPL with unRAR license restriction"
  applies to what we ship — where `package/lzma-sdk`, compiling only
  public-domain `C/` files, escaped it. It is a
  no-reverse-engineering-of-the-RAR-compressor clause, not a
  no-redistribution one; upstream Buildroot ships `package/p7zip` under the
  identical string without `REDISTRIBUTE = NO`, and neither do we. Side effect
  worth naming: the image gains **RAR/RAR5 extraction**, which the defconfig's
  `unrar` exclusion note now reflects.
- **Two packages, one upstream tarball.** `lzma-sdk` and `7zip` are pinned
  independently (Buildroot's one-version-per-package rule keeps each `.hash`
  meaningful alone) but share a Renovate `depName`, so a bump raises **one PR
  touching both** and they cannot silently drift.
- **`-Werror` is dropped** from upstream's warning set (`-Wall -Wextra` kept).
  Correct for upstream's CI, wrong for a distribution build, where a toolchain
  bump would otherwise turn a new warning into a hard failure in a package
  nobody touched.
- **Two static-glibc NSS warnings at link** (`getgrgid`, `getpwuid`, from
  `FileStreams.cpp`'s owner/group property lookup). They affect `-slt`-style
  owner-name *display* only, never `t` or `x`, and the round-trip above is the
  evidence.

## 6. Consequences

- No MiSTer running our image ever downloads a 2016 archive parser again, and
  cards flashed from `sdcard.img` never do so even once.
- The extractor now updates on the same cadence as everything else, via
  Renovate, instead of being frozen by a hardcoded URL in third-party code.
- A user who rolls back to stock keeps a working, modern, static `7za` —
  strictly better than what stock would have given them.
- Rollback of this decision is a one-line defconfig change back to
  `BR2_PACKAGE_P7ZIP`, plus dropping the two payload copy lines. The
  Downloader's fetch path is still there and would simply resume.
