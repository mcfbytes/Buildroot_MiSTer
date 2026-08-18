# azcopy — Azure Storage CLI on the MiSTer

`package/azcopy` builds Microsoft's [AzCopy](https://github.com/Azure/azure-storage-azcopy)
v10.32.7 for this image. It is the client for Azure Blob Storage, Azure Files and
Data Lake Storage Gen2, and it is here for one job: **off-device backup of the exFAT
data partition** — pushed straight from the board over the network it already has, with
no PC in the middle. Concretely, the directories worth backing up are the ones
Main_MiSTer writes and nothing else can regenerate: `/media/fat/saves`,
`savestates`, `screenshots` and `config` (`SAVE_DIR`, `SAVESTATE_DIR`,
`SCREENSHOT_DIR`, `CONFIG_DIR` in `work/Main_MiSTer/file_io.h`), plus the handful of
per-device files under `/media/fat/linux` that a Linux update overwrites.

`azcopy sync` is the subcommand that makes this worth doing. It is incremental (it
compares before it transfers) and restartable (job plan files survive a reboot), both
of which a 100 Mbit link driven by an 800 MHz dual-core Cortex-A9 rewards heavily.

Upstream Buildroot has no `azcopy` package — re-confirmed absent on the pinned
2026.05.1 tree on 2026-08-17; the only `az*` package there is `azure-iot-sdk-c` — so
this tree authors one. It is also **the first and only Go package in the tree**, which
has consequences of its own (§5).

> **The default image does not contain azcopy.** The package builds and is fully
> wired, but `configs/mister_de10nano_defconfig` leaves `BR2_PACKAGE_AZCOPY` unset,
> for the size reason in §1. To get azcopy onto a MiSTer today you either flip that
> line and rebuild, or drop the released binary onto `/media/fat` yourself — which is
> exactly how every test in §4 was run.

---

## 1. Size and cost — read this first

**The package is present but NOT enabled** in `configs/mister_de10nano_defconfig`, and
size is the only reason. At 39.1 MiB installed it would be the second-largest package
in the image after samba4, spending about a fifth of the free space `linux.img` has
left, for a tool most users will never run. It works — §4 is a transcript of it working
on real hardware — it just does not earn a permanent seat in a fixed 512 MiB
filesystem by default.

Turning it on is one line in the defconfig. The numbers below are what that line costs.

### The binary

| Measurement | Bytes | |
|---|---:|---|
| As `make azcopy` leaves it in `output/target/usr/bin/azcopy` | 58,254,356 | 55.6 MiB |
| **As installed, after Buildroot's strip** | **41,007,016** | **39.1 MiB** |
| gzip -9 (proxy for over-the-wire) | 13,179,592 | 12.6 MiB |
| xz -9 (proxy for the release `.7z`) | 8,670,004 | **8.3 MiB** |

**How these were produced.** These are the real artifact, not an estimate: `make azcopy`
was run against this branch in its own Buildroot output directory, and the numbers are
`ls -l` on what it installed. The strip line is the literal `STRIPCMD` from
`work/buildroot/package/Makefile.in:259` —
`arm-buildroot-linux-gnueabihf-strip --remove-section=.comment --remove-section=.note` —
which is what `work/buildroot/Makefile:785` runs over every target binary at
`target-finalize`; it was applied by hand here only because `make azcopy` on its own
stops short of `target-finalize`.

(For what it is worth, a standalone cross-build done earlier with the same go 1.26.3,
the same cross toolchain and the same flag set `pkg-golang.mk` passes landed on
**41,007,016 bytes after strip — the same number to the byte**, which is a decent sign
that neither measurement is an artifact of how it was taken.)

Two things are worth knowing about that strip. GNU `strip` with no mode flag defaults
to `--strip-all`, so the `--remove-section=` options are *additions* to a full strip,
not the whole of it — this is why the binary loses 17,247,340 bytes (16.4 MiB) rather
than the couple of hundred a literal reading of the command line would suggest. And Go
binaries survive it: what `strip` removes is `.symtab`/`.strtab` and the DWARF, while
the runtime's own `pclntab` lives in an allocated section it does not touch. That is
the theory; the check is that the stripped binary was run under `qemu-arm` against this
image's own sysroot and behaves identically to the unstripped one (§4).

Nothing else lands in the rootfs. `azcopy` is one binary with `DT_NEEDED` on
`libc.so.6` and `libresolv.so.2` only, both already present
(`output/target/lib/libresolv.so.2` — it is part of glibc, not a new package). The
Config.in `select`s `BR2_PACKAGE_CA_CERTIFICATES`, which is already `=y` in its own
right in the defconfig's crypto/TLS block, so that adds nothing either. The one other
new file is `/etc/profile.d/azcopy.sh` (§6), about 4 KiB of comments.

The non-obvious runtime dependency for a **cgo** Go binary is glibc's NSS plumbing —
without it name resolution fails at the first `*.blob.core.windows.net` lookup and the
symptom looks nothing like a missing library. Checked, and already satisfied:
`output/target/lib/libnss_files.so.2` and `libnss_dns.so.2` are both installed, and the
shipped `/etc/nsswitch.conf` has `hosts: files dns`.

### What it does to the image budget

Against `output/images/linux.img` as built on 2026-08-17 **without** azcopy. The
"before" row is not hand-derived — it is what `scripts/check-size-budget.sh` itself
prints for that image:

```
$ scripts/check-size-budget.sh output/images/linux.img
Image: output/images/linux.img
Total: 512 MiB (131072 blocks x 4096 bytes)
Used:  317 MiB
Free:  195 MiB
Free:  38.1%

PASS: 38.1% free (>= 15% required)
```

| | Blocks free | Free | % free | Budget (≥15%) |
|---|---:|---:|---:|---|
| Before | 49,991 | 195.3 MiB | 38.1% | PASS |
| After (projected: +10,012 blocks) | 39,979 | 156.2 MiB | **30.5%** | **PASS** |

So enabling it would still **pass** the budget, with roughly twice the margin it
requires (15% of 512 MiB is 76.8 MiB). "Would still pass" is not the same as "is worth
spending", and that distinction is why the defconfig leaves it off: **azcopy alone
spends about a fifth of the image's remaining free space**, on a fixed 512 MiB
filesystem with no growth path, for a feature that is useful to some owners and to no
core.

> The "after" row is arithmetic on the measured binary size, not a `dumpe2fs` of an
> image that contains it. Regenerate it from a real build before quoting it as a
> measurement — the same discipline `docs/size-budget.md` asks for, and for the same
> reason.

Note that `docs/size-budget.md`'s headline table is older than this and quotes 310.7
MiB free; the 195.3 MiB above is from a current build and is the number that matters
here. That document's own banner already flags its figures as stale.

### Why a file-transfer CLI is 39 MiB

Almost none of it is AzCopy. Measured, by linking each dependency tree on its own for
`GOARCH=arm GOARM=7` and stripping it exactly as Buildroot does:

| Binary | Stripped size | Marginal cost |
|---|---:|---:|
| `func main() {}` — empty Go program | 1,201,252 | — (Go runtime floor) |
| + Azure SDK (`azblob`) | 5,491,132 | +4.3 MB |
| + **Google Cloud Storage** (`cloud.google.com/go/storage`) | **27,587,988** | **+26.4 MB** |
| + S3 (`minio-go/v7`) | 4,215,156 | +3.0 MB |
| + GCS and S3 together | 28,048,340 | +26.8 MB |

**Google Cloud Storage support costs more than the entire rest of the binary.** It
pulls in gRPC, protobuf, OpenTelemetry, and — via gRPC's xDS load-balancing — the
**Envoy `go-control-plane` protos**, which alone contribute 3.3 MB of symbols, more
than AzCopy's own code (1.28 MB of symbols). None of it will ever execute on a MiSTer
backing up to Azure.

The ELF sections of the shipped binary say the same thing from the other side:

| Section | Size | |
|---|---:|---|
| `.text` | 18,846,352 | machine code |
| `.gopclntab` | 15,595,300 | Go's PC→function tables — needed for panics, stack traces and GC |
| `.rodata` | 5,886,584 | |

`.gopclntab` scales with the *number of functions*, so a large dependency tree is taxed
twice: once for its code and again for its metadata. This is the ordinary reason Go
binaries are large, amplified here by a dependency nobody on this platform wants.

> One red herring, recorded so nobody else chases it: `go tool nm` reports a
> **33.5 MB** symbol, `crypto/internal/fips140/drbg.memory`. It costs **zero** bytes on
> disk — it lives in `.noptrbss` (`NOBITS`), so it is demand-zero virtual address space,
> not file content. It does mean the process reserves ~32 MiB of BSS, which is worth
> knowing on a 488 MiB board, but it explains nothing about the file size.

### Options for making it smaller

None of these are applied. They are here to be chosen from.

| # | Option | Est. result | Cost |
|---|---|---:|---|
| A | **Ship it as a release artifact, not in the image** (current choice) | 0 MiB in `linux.img`; 8.3 MiB xz download | None. No patch to carry, no build cost by default. |
| B | `-ldflags="-s -w"` | ~41.0 MiB — **no gain** | Measured: Buildroot's `strip` already removes the same symbol table and DWARF. Not worth doing. |
| C | **Patch out GCS support** | ~17–20 MiB | A permanently-carried patch across ~20 files, including credential handling. Must be rebased on every version bump. |
| D | **Patch out GCS *and* S3** | ~15–18 MiB | As C, slightly larger. Leaves an Azure-only azcopy. |
| E | UPX-compress the binary | ~10–14 MiB on disk | Decompresses to full size in RAM at every startup on a 488 MiB board, and Go + UPX is a fragile combination. Not recommended here. |

**On C/D, the honest price.** The GCS and S3 code is not confined to a few files that
could simply be deleted: 20 non-test files reference it, including ~1,200 lines of
GCS/S3-only sources plus 44 references inside `common/credentialFactory.go`, 12 in
`cmd/copy.go` and 11 in `common/fe-ste-models.go`. Upstream ships no build tag for
this, so there is nothing cheap to flip. A patch of that size, in credential-handling
code, carried against a project that releases roughly monthly, is a real maintenance
commitment — and this repo's own experience is that carried patches are the largest
maintenance cost it has. The size win is genuine and large; the price is a standing
obligation, not a one-off.

### Build cost

Selecting azcopy pulls in **host-go**, which Buildroot builds *from source* on an
x86_64 host (`BR2_PACKAGE_HOST_GO_SRC` is the default whenever
`BR2_PACKAGE_HOST_GO_BOOTSTRAP_STAGE5_ARCH_SUPPORTS`, per
`work/buildroot/package/go/Config.in.host`). That is a five-stage bootstrap before the
compiler you actually wanted: `host-go-bootstrap-stage1-1.4-bootstrap-20171003` (the
C-written Go 1.4) → `stage2-1.19.13` → `stage3-1.21.8` → `stage4-1.23.12` →
`stage5-1.25.10` → `host-go-1.26.3`.

**It is much cheaper than that description makes it sound, and an earlier revision of
this document overstated it.** Timed from `output/build/build-time.log` on a 32-core
host:

| Step | Wall time |
|---|---:|
| host-go bootstrap stages 1–5 | **3.0 min** |
| `host-go-src` (the real 1.26.3 compiler) + install | **1.2 min** |
| azcopy `go mod vendor`, module cache warm | **39 s** |
| azcopy compile + link + install | **12 s** |
| *(target toolchain, pulled in by `HOST_GO_DEPENDENCIES_CGO`)* | *~10 min — but the image build builds this anyway, so it is not incremental* |

So on top of a pipeline that already builds the toolchain, **azcopy adds roughly
4–5 minutes**, nearly all of it host-go. On a truly cold tree with no `dl/` cache the
vendoring is slower (it fetches ~1.7 GiB of modules with `GOPROXY=direct`), but CI
caches `dl/`, and once `azcopy-<ver>-go2.tar.gz` is in that cache the vendoring never
runs again until a version bump.

None of it is a rootfs cost: nothing from host-go ships.

It was left at the from-source default rather than switched to `host-go-bin` (which
downloads a pre-built toolchain tarball) because building compilers from source is the
posture this tree already takes everywhere else. If CI minutes become the binding
constraint, `BR2_PACKAGE_HOST_GO_BIN=y` is the lever — see
`docs/ci.md` for the cost-consciousness policy that would justify pulling it.

The vendored module set is the other half of the build cost, and it is not small.
AzCopy supports S3 and GCS as transfer *sources*, so `go.sum` drags in
`cloud.google.com/go`, the Google API client, gRPC and the Envoy control-plane protos
alongside the Azure SDK. Vendoring it left **1.7 GiB in `output/host/share/go-path/pkg/mod`**
on the first build of this branch, and put a **57 MiB `vendor/`** directory into the
source tree — which is most of why the `-go2` tarball this package pins (§5) is
18,664,891 bytes. None of it reaches the target (Go links only what is reachable), but
all of it is fetched on a cold build, and all of it is inside the hash.

### Turning it on, and turning it back off

Uncomment `BR2_PACKAGE_AZCOPY` in `configs/mister_de10nano_defconfig`. Turning it off
again is deleting that line: nothing in the image depends on azcopy — no init script
starts it, no other package links it, no parity test asserts it.
`BR2_PACKAGE_CA_CERTIFICATES` and
`BR2_PACKAGE_HOST_GO` are the only things its Config.in `select`s, and the first stays
`=y` on its own account while the second is build-time only.

---

## 2. Microsoft does not support 32-bit ARM

The v10.32.7 release publishes `azcopy_linux_amd64`, `azcopy_linux_arm64`, their `_se_`
siblings, macOS and Windows builds — and **nothing for `linux/arm` or `linux/386`.**
There is no upstream CI leg for the architecture this image targets and no support
statement covering it. Everything below follows from that.

Two defects had to be fixed before AzCopy would build and run on ARMv7. Both are in
this package's directory with full write-ups in their headers; the summary:

### `0001-ste-set-NFS-timestamps-the-way-this-file-already-does.patch` — build blocker

`ste/downloader-azureFiles_linux.go`'s `PutNFSProperties()` builds a
`[]syscall.Timeval` from a composite literal populated with `int64` values.
`syscall.Timeval`'s fields are `int64` on 64-bit Linux and `int32` on 32-bit Linux, so
this is a hard compile error under `GOARCH=arm`:

```
ste/downloader-azureFiles_linux.go:255:9: cannot use lastModifiedTimeSec
    (variable of type int64) as int32 value in struct literal
```

Fixed by doing what `setDates()` already does earlier in the *same file* for the SMB
equivalent: build a `unix.Timespec` and call `unix.UtimesNanoAt()`. `golang.org/x/sys/unix`
is already imported there for precisely that, and `syscall` then has no other user in
the file, so its import goes too.

This is **not** a pure refactor, and the patch header says so in detail: `utimensat`
takes nanoseconds where `utimes` took microseconds (so the sub-second truncation goes
away), and `unix.TimeToTimespec` returns `ERANGE` for a timestamp whose seconds do not
fit the target's field width instead of wrapping silently. Both changes apply on 64-bit
targets too, and both are improvements. Note the *obvious* one-line fix,
`syscall.NsecToTimeval()`, would have been wrong: it does `nsec += 999` and rounds every
inexact timestamp **up** to the next microsecond.

### `0002-vendor-keyctl-use-EABI-syscall-numbers-on-linux-arm.patch` — runtime blocker

`github.com/wastore/keyctl` (where AzCopy caches its OAuth token, in the kernel session
keyring) carries per-GOARCH syscall numbers. Its `sys_linux_arm.go` uses **OABI**
numbering — `0x900137`, `0x900135`, `0x90008b`, i.e. keyctl/add_key/setfsgid with ARM's
old-ABI `__NR_SYSCALL_BASE` of `0x900000` added. Go's `linux/arm` port is EABI, where
those are plainly 311 / 309 / 139.

This is not a graceful `ENOSYS`. It takes the process out:

```
$ azcopy login status
SIGILL: illegal instruction
PC=0x1edf4 m=0 sigcode=4
goroutine 1 gp=0x4804148 m=0 mp=0x27226f8 [syscall]:
syscall.Syscall6(0x900137, 0x0, 0xfffffffd, 0x1, 0x0, 0x0, 0x0)
        syscall/syscall_linux.go:96 +0x8
github.com/wastore/keyctl.keyctl(0x0, {0x5093a5c, 0x2, 0x2})
        github.com/wastore/keyctl@v0.3.1/sys_linux.go:114 +0x16c
```

Every `azcopy login*` subcommand goes through it. With the three constants corrected:

```
$ azcopy login status
INFO: You are currently not logged in. Please login using 'azcopy login'
```

The sibling files for 386, arm64 and the ppc variants were read and are all correct;
only `arm` is wrong, and it is wrong by exactly the OABI base, so it was evidently
transcribed from an OABI table. Neither this patch nor 0001 has been sent upstream.

**Neither patch may be dropped on a version bump because "the build went green."** 0001
is load-bearing for the build and will announce itself. 0002 is not — a build with 0002
missing compiles perfectly and then kills itself the first time anyone logs in.

---

## 3. The 32-bit hazard that is *not* patched

`sync/atomic`'s documented caveat applies here in full:

> On ARM, 386, and 32-bit MIPS, it is the caller's responsibility to arrange for
> 64-bit alignment of 64-bit words accessed atomically via the primitive atomic
> functions.

This is real on this target and not theoretical. Compiled for `GOARCH=arm`,
`unsafe.Alignof(int64(0))` is **4**, and in `struct { a int32; b int64 }` the `int64`
lands at offset 4 — verified by forcing the compiler to print both constants. A 64-bit
atomic on a field at a non-8-aligned offset panics at runtime with
`unaligned 64-bit atomic operation`.

AzCopy has **107 sites** doing 64-bit atomics on the address of a struct field or slice
element (`grep -c 'atomic\.\(Add\|Load\|Store\|Swap\|CompareAndSwap\)\(Int64\|Uint64\)(&'`
over the non-vendored tree). Auditing all 107 by hand was not attempted. What was done
instead is in §4: run the code and see.

Nothing hit the panic in anything that was exercised. That is evidence, not proof, and
the honest statement is that **a long-running real transfer on real hardware is the
test that has not happened yet.** If a user ever reports `unaligned 64-bit atomic
operation` from azcopy, this section is the first place to look and the fix is to
reorder the offending struct's fields (put the 64-bit field first) in a third patch.

---

## 4. What was actually tested

**It was run on a real DE10-Nano**, against a real Azure Storage account, on
2026-08-17. The board was a MiSTer on kernel `7.2.0 #1 SMP PREEMPT_RT`, 488 MiB of
usable RAM, exFAT data partition on `/media/fat`, wired eth0. The binary tested was
the stripped ARMv7 artifact `make azcopy` produced, copied to
`/media/fat/azcopy-test/azcopy`.

Authentication used an **account SAS generated off-box** — the storage account key
never went onto the MiSTer.

| # | What | Result |
|---|---|---|
| 1 | `azcopy --version` on the board | `azcopy version 10.32.7` |
| 2 | `azcopy make` (create container) | `Successfully created the resource.` |
| 3 | `azcopy copy --recursive`, 9 files / 131.5 MiB from exFAT → Blob | **137,887,744 B in 48.3 s**, 9/9 completed, 0 failed |
| 4 | `azcopy list` | all 9 blobs, correct sizes |
| 5 | `azcopy sync`, nothing changed | **0 transfers, 0 bytes** — incremental works |
| 6 | `azcopy sync` after touching one 512 KiB file | **exactly 1 transfer, 524,288 B** |
| 7 | `azcopy copy` Blob → exFAT, 120 MiB | md5 `36c76d88…` **identical** to the source |
| 8 | `azcopy copy --recursive` → **Azure Files** over HTTPS | 5 files + 1 folder, completed; `azcopy list` on the share correct |
| 9 | `azcopy remove --recursive` | 3 blobs removed, 6 remaining |
| 10 | Job plan files on **exFAT** | four `*.steV20` files written and memory-mapped, 640 KiB; `azcopy jobs list` reads them back |
| — | OOM kills during any of it (`dmesg`) | **none** |

Throughput was ~2.85 MB/s (≈23 Mbit/s) for the upload — that is a Cortex-A9 doing
TLS, not a link limit.

**Memory, measured during the 132 MiB upload:**

| | Peak `used` | Low-water `free` |
|---|---:|---:|
| Idle baseline | 44 MiB | — |
| With `AZCOPY_BUFFER_GB=0.125` (§6) | 175 MiB | 66 MiB |
| With AzCopy's own default | 199 MiB | **9 MiB** |

So azcopy's working set on this board is ~130 MiB with the cap. The uncapped run
cost ~24 MiB more and drove free memory down to 9 MiB — and note this payload was
*smaller than the default 1 GiB cap*, so it could not demonstrate the cap's real
purpose. The 0.125 setting exists for a full `/media/fat` backup, where the source
does exceed 1 GiB and nothing but that cap stands between AzCopy and the OOM killer.
That case remains untested; do not read the table above as proving it safe.

### Also verified on the board (not azcopy)

- **CIFS/SMB3 client works.** A throwaway `smbd` on the board, mounted back over
  loopback with `mount -t cifs //127.0.0.1/test -o username=…,vers=3.0`: mount
  succeeded and a file read through it md5-matched the original. The kernel offers
  `cmac(aes)`, `ccm(aes)`, `hmac(sha512)` — everything SMB3 signing and encryption
  needs. A first attempt with `-o guest` failed `mount error(95)`; that is SMB3
  correctly refusing guest auth, **not** an image defect.
- **Azure Files over SMB is not reachable from this network.** Port 445 outbound is
  blocked — confirmed from both the MiSTer *and* the development host, so it is the
  ISP/network, not the image. Azure Files offers no alternate SMB port. This is why
  test 8 above goes over HTTPS via azcopy instead, which is the equivalent that does
  work.

### Earlier, under qemu-arm (kept because it covers what hardware did not)

Go's ARM runtime does its own 64-bit-alignment check in software, so an unaligned
64-bit atomic faults under qemu exactly as it would on the board.

| What | Result |
|---|---|
| `azcopy login status` | fails with SIGILL **before** patch 0002; after it, the correct `not logged in` answer and exit 1 |
| `go test ./common/... ./ste/... ./sddl/... ./traverser/...`, GOARCH=arm | `common/parallel`, `sddl`, `traverser` **ok**; `common` and `ste` fail on tests that demand live `ACCOUNT_NAME`/`ACCOUNT_KEY` and **fail identically on amd64** |
| stripped vs unstripped | identical output and exit codes across `--version`, `env`, `jobs list`, `login status` |
| `unaligned 64-bit atomic operation` panics | **zero**, across everything above and everything on hardware |

### What is still NOT tested

- **`azcopy login` end to end.** Patch 0002 fixed the crash and `login status`
  answers correctly, but no device-code login against a real tenant was performed,
  so the keyring path it takes *on success* is still unproven. All hardware testing
  used SAS.
- **A backup larger than the 1 GiB buffer cap**, which is the case §6's
  `AZCOPY_BUFFER_GB` exists for.
- **`azcopy jobs resume` across a reboot.** Plan files demonstrably survive on
  exFAT (test 10) and `jobs list` reads them, but no interrupted job was resumed.
- **Long-running transfers.** §3's alignment hazard is a tail risk that a 48-second
  upload exercises far less than an hours-long one.

## 5. Version pinning, and why the hash is unusual

`package/azcopy/azcopy.hash` pins `azcopy-10.32.7-go2.tar.gz`, which **is not the
tarball GitHub serves.** Buildroot's Go infrastructure sets
`AZCOPY_DOWNLOAD_POST_PROCESS = go`, so `support/download/go-post-process` unpacks the
GitHub archive, runs `go mod vendor` inside it, and repacks the result
deterministically (POSIX tar, sorted file list, fixed mtime, `--owner=0 --group=0`,
`gzip -6 -n` — see `mk_tar_gz` in `support/download/helpers`). Only that repacked
tarball is ever hashed. This is a feature: it means the pin certifies the entire
vendored dependency set, not just the AzCopy sources, and it sidesteps GitHub's
historically unstable archive gzip output.

It also means two things you have to remember:

1. **`scripts/hash-sync-github-packages.sh` cannot cover this package.** That script's
   method is `curl <archive-url> | sha256sum`, which for azcopy yields the hash of the
   pre-vendoring tarball: a plausible-looking wrong value that would land a green bump
   PR and then fail the build on master at download time. azcopy is therefore
   deliberately **absent** from `HASH_SYNC_PACKAGES` in
   `.github/workflows/renovate-hash-sync.yml`. Do not add it.
2. **Renovate still proposes bumps** (`renovate.json` has a custom manager over
   `AZCOPY_VERSION`), and every one of those PRs must be blessed by a human who
   regenerates the hash. **What enforces that is worth being precise about, because the
   obvious answers are all wrong here:** this workflow does not (azcopy is excluded from
   it), and neither does the image build — azcopy is not enabled in the defconfig, so
   `build.yml` never compiles it and never exercises the pin. A version-only bump would
   otherwise go entirely green carrying a hash that matches nothing, and the breakage
   would surface much later, to whoever first enables the package.

   The gate is the **`azcopy version/hash pin consistency` step in
   `.github/workflows/lint.yml`**. It fails any PR where `AZCOPY_VERSION` and the tarball
   filename on `azcopy.hash`'s `sha256` line disagree — which a version bump without a
   regenerated hash always does. It needs no toolchain, no Go and no network, and it
   fires on a hand edit as readily as on a Renovate bump. Renovate additionally labels
   these PRs `needs-manual-hash`, which is a signal to the reviewer, not the enforcement.

   It cannot catch "same version, different bytes"; nothing cheap can. That case is
   caught at download time by `BR2_DOWNLOAD_FORCE_CHECK_HASHES`, the moment anyone builds
   the package.

The regeneration recipe lives in `azcopy.hash`'s own header, next to the value it
produces, so it cannot drift away from it. Two things about it are worth repeating
here because they are counter-intuitive and were established by hitting them, not by
reading the manual:

- **Turning `BR2_DOWNLOAD_FORCE_CHECK_HASHES` off does not let you compute the hash by
  downloading and running `sha256sum`.** That option only governs files with *no* hash
  listed; a hash that *is* listed is checked regardless. The stale value fails the
  download, and Buildroot then **deletes** the mismatching file, so `dl/` is empty
  afterwards.
- **The failure message is the recipe.** Buildroot prints
  `ERROR: got     : <sha256>` for the file it just built and threw away. That is the
  value to paste in — no build ever has to run with hash checking disabled.

This was not theory: the pin in this commit was produced exactly that way. The first
`make azcopy-source` on this branch failed closed against a placeholder of zeros and
printed `c04793e0…`; pasting that in and re-running passed with the check on.

**`go mod vendor` has now been run three separate times on this tree and produced a
byte-identical tarball every time** (the third deliberately, with the `dl/` copy deleted
and the module cache warm — 39 s). That is a real, if single-host, data point that
Buildroot's `mk_tar_gz` repack is as deterministic as it claims, which is the property
this whole pin rests on.

Also on every bump: re-run the ARMv7 build and re-check that both patches still apply —
0002 in particular patches a vendored file, so a `go.mod` bump of
`github.com/wastore/keyctl` will make it fail to apply, which is the desired loud
failure.

---

## 6. Runtime configuration on this board

`/etc/profile.d/azcopy.sh` sets three defaults. Read that file
(`package/azcopy/azcopy-profile.sh` in the tree) — its comments are the authority; this
is the summary.

**It is installed by the package, not by the rootfs overlay**, so it exists only in
images built with `BR2_PACKAGE_AZCOPY=y`. If you are running a *downloaded* binary from
`/media/fat` — the default way to have azcopy on a MiSTer today — this file is not on
your system and none of these defaults apply. Set them yourself; that is why the table
below gives the values and not just the rationale.

| Variable | Value | Why |
|---|---|---|
| `AZCOPY_JOB_PLAN_LOCATION` | `/media/fat/linux/azcopy/plans` | AzCopy defaults to `$HOME/.azcopy`, i.e. the rootfs — which a Linux update reflashes wholesale, taking every resumable job with it, and which is a fixed 512 MiB filesystem that plan files can fill. |
| `AZCOPY_LOG_LOCATION` | `/media/fat/linux/azcopy/logs` | Same two reasons; logs are verbose by default. |
| `AZCOPY_BUFFER_GB` | `0.125` (128 MiB) | **Not cosmetic.** `getMaxRamForChunks()` (`jobsAdmin/JobsAdmin.go`) computes 0.5 GiB per logical CPU capped at 1 GiB for 32-bit builds; with 2 cores that is 1.0 GiB, on a board that boots with `mem=511M`. The upstream default limit is roughly twice the machine's entire RAM. |

AzCopy creates both directories itself (`common/init.go`'s `InitializeFolders()` →
`os.MkdirAll`), so there is no init script and nothing to pre-create.

**The profile.d mechanism only covers login shells.** `/etc/profile` sources
`/etc/profile.d/*.sh`, which gets you a console login, an interactive `ssh mister`, and
anything launched from one. It does **not** cover `ssh mister azcopy ...` — a
non-login, non-interactive shell reads no profile — nor anything started by init. This
image has no `pam_env` in `/etc/pam.d/sshd` and no `/etc/environment`, and editing the
authentication stack to close an environment-variable gap is not a trade worth making.
If you drive azcopy non-interactively, set the three variables in your own script; they
are the entire content of the profile.d file and are meant to be copied.

`AZCOPY_CONCURRENCY_VALUE` is deliberately left alone — AzCopy fixes it at 32
connections for machines with ≤4 CPUs (`ste/concurrency.go`, `getMainPoolSize()`),
which is more than a 100 Mbit link needs, but the memory that costs is already bounded
by the buffer cap, and choosing a number without measuring on the board would be
guessing.

**It does not phone home.** Worth stating because older AzCopy v10 did, and an
appliance quietly contacting Microsoft on every backup would be a thing to know about:
in v10.32.7 the update check is behind a `--check-version` flag that
`cmd/root.go:368` declares with a default of `false`, and `cmd/root.go:203` is the only
place that consults it. Nothing on this image passes it.

---

## 7. Credentials

Not the image's business, and nothing is configured. The options, in rough order of how
well they suit an appliance:

- **SAS token in the URL** — `azcopy sync /media/fat "https://acct.blob.core.windows.net/container?<SAS>"`.
  No login, no keyring, no token cache; the credential is scoped and expires. This is
  the path that requires none of the machinery patch 0002 fixes, and the one to reach
  for first on a headless board.
- **`azcopy login --identity`** — only if the board somehow reaches an IMDS endpoint,
  which on a MiSTer it does not. Listed for completeness.
- **`azcopy login`** (device code) — works, in the sense that the keyring path no
  longer crashes (§2), but the end-to-end flow is untested here (§4). Note the token
  cache lives in the kernel session keyring, which does not survive a reboot.
- **`AZCOPY_AUTO_LOGIN_TYPE` + a service principal secret** — a long-lived secret in an
  environment variable on an appliance with an empty root password and a Samba share
  over the whole card. Think about where that file lives before doing it.

---

## 8. See also

- `package/azcopy/azcopy.mk` — the package, and the header explaining the Go
  infrastructure's behaviour
- `package/azcopy/azcopy.hash` — the hash and its regeneration recipe
- `docs/size-budget.md` — the image size budget this spends into
- `docs/package-manifest.md` — the stock-parity package mapping (azcopy is not part of
  stock parity; it is an addition)
- `docs/renovate.md` — the bump automation, and which packages its hash-sync covers
