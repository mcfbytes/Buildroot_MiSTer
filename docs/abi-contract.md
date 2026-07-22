# The MiSTer userland ABI contract (P0.5)

**What MiSTer's userland requires of its kernel and its root filesystem.**

This is the document of record for the interface between `Main_MiSTer` (plus the rest of the
on-device userland) and the Linux kernel + rootfs beneath it. It exists because that interface
has never been written down: it is encoded only in a 5.15 kernel fork, a 900 KB C++ binary, and
a handful of shell scripts. Everything below is derived from those artefacts, not from memory.

**Every claim carries evidence.** A reviewer must be able to check any single line without
re-deriving it: a `file:line` at a pinned commit, a `readelf`/`debugfs` command they can re-run,
or a named file in `docs/stock-inventory/`.

**Every claim is marked MUST or SHOULD.**

| | Meaning |
|---|---|
| **MUST** | Breaking it breaks MiSTer — the binary does not run, the menu does not appear, a core cannot load, or a headline feature (video, audio, input, HDMI, update) dies. |
| **SHOULD** | Parity or quality. Breaking it produces a user-visible regression that a determined user could live with, or that affects a subset of hardware. Each SHOULD says who it hurts. |

§13 is the mechanical checklist. `scripts/check-abi.sh` (P2.2) and the hardware gates
(P1.13, P2.9, P3.13) are built from it.

---

## 0. Sources, and how to re-derive everything

| Artefact | Identity |
|---|---|
| Stock `MiSTer` binary | `work/extracted/files/MiSTer`, 952,584 B, sha256 `2e9b77de872a0bda0a2cb60b63259fe992a89aec838ce5ef435e3a72690caec0` (from `release_20250402.7z`) |
| Stock rootfs | `work/imgroot/` — `debugfs rdump` of `work/extracted/files/linux/linux.img` (see `docs/reference-materials.md` §3) |
| Main_MiSTer source | `work/Main_MiSTer`, **`14052d21612df6136992190c0d5d4cbccbd816a9`** (2026-07-12). All `Main:` citations are at this commit. |
| Kernel fork | `work/Linux-Kernel_MiSTer`, branch `MiSTer-v5.15`, **`f0fb626acadd07f0718934826b143b6e4c9ce81c`**. All `linux515:` citations are at this commit. |
| Upstream 6.18 | `work/linux-stable`, `linux-6.18.y` @ **v6.18.38**. All `linux618:` citations are at this commit. |
| Downloader | `work/Downloader_MiSTer`, **`915315668b9460b0fcdfc728be8254fe698c479f`**. All `dl:` citations are at this commit. |
| Stock kernel `.config` | `docs/stock-inventory/stock-linux.config` (4,246 lines, IKCONFIG-extracted) |
| Stock DTS | `docs/stock-inventory/stock.dts` |

> **Evidence-quality caveat, stated once.** The shipped binary is from release **20250402**; the
> Main_MiSTer source is at **HEAD (2026-07)**. They are not the same program. This document
> treats the contract as the **union** of the two: what the shipped ELF demands (proved from the
> ELF itself) *and* what current source demands (proved from `file:line`). Both must hold,
> because a user on our image runs a `MiSTer` binary they downloaded from
> `Distribution_MiSTer` — which tracks HEAD, not the release we happen to have.

Companion documents: **`docs/patch-provenance.md`** (P0.4 — the kernel-side patches that
implement half of this contract), **`docs/boot-chain.md`** (P0.8 — the cmdline, the memory map,
the kernel-config assertions), **`docs/downloader-contract.md`** (P0.6 — the update path),
**`docs/stock-inventory/`** (P0.3 — the evidence base).

---

## 1. Toolchain and processor ABI

### 1.1 The binary's own declaration — **MUST**

```console
$ readelf -h work/extracted/files/MiSTer
  Class:                             ELF32
  Data:                              2's complement, little endian
  Type:                              EXEC (Executable file)
  Machine:                           ARM
  Flags:                             0x5000400, Version5 EABI, hard-float ABI

$ readelf -p .interp work/extracted/files/MiSTer
  [     0]  /lib/ld-linux-armhf.so.3
```

```console
$ readelf -A work/extracted/files/MiSTer
Attribute Section: aeabi
File Attributes
  Tag_CPU_name: "7-A"
  Tag_CPU_arch: v7
  Tag_CPU_arch_profile: Application
  Tag_ARM_ISA_use: Yes
  Tag_THUMB_ISA_use: Thumb-2
  Tag_FP_arch: VFPv3
  Tag_Advanced_SIMD_arch: NEONv1
  Tag_ABI_PCS_wchar_t: 4
  Tag_ABI_FP_rounding: Needed
  Tag_ABI_FP_denormal: Needed
  Tag_ABI_FP_exceptions: Needed
  Tag_ABI_FP_number_model: IEEE 754
  Tag_ABI_align_needed: 8-byte
  Tag_ABI_align_preserved: 8-byte, except leaf SP
  Tag_ABI_enum_size: int
  Tag_ABI_VFP_args: VFP registers        <-- hard-float calling convention
  Tag_CPU_unaligned_access: v6
```

| # | Requirement | Level | Evidence |
|---|---|---|---|
| **T1** | 32-bit little-endian **ARM**, **ELF32**, `ET_EXEC` (non-PIE) | MUST | `readelf -h` above |
| **T2** | **ARMv7-A** instruction set (Cortex-A9 is the actual part) | MUST | `Tag_CPU_arch: v7`, `Tag_CPU_arch_profile: Application` |
| **T3** | **VFPv3** FP unit and **NEONv1** SIMD present and used | MUST | `Tag_FP_arch: VFPv3`, `Tag_Advanced_SIMD_arch: NEONv1` |
| **T4** | **EABIhf** — arguments passed in VFP registers | MUST | `Tag_ABI_VFP_args: VFP registers`; ELF flag `hard-float ABI` |
| **T5** | Dynamic loader at **`/lib/ld-linux-armhf.so.3`** | MUST | `.interp` above. Buildroot's glibc installs this name for `armhf`; a softfloat or `arm-linux-gnueabi` toolchain installs `ld-linux.so.3` and the binary will not start (`No such file or directory` from `execve`). |
| **T6** | An **`/etc/ld.so.cache`** exists (ldconfig run at image build) | SHOULD | Present in stock; observed being opened first in the qemu strace (§2.5). Without it the loader falls back to hard-coded search paths, which still work — but slowly, and any library outside `/lib`:`/usr/lib` is lost. |

**Consequence for P1.2.** Buildroot must be configured `armv7-a` / Cortex-A9 / NEON-VFPv3 /
EABIhf / glibc. A `neon-vfpv4` or `vfpv4` FP setting is *forward*-compatible (the Cortex-A9 has
neither), so it would produce a rootfs whose *libraries* the CPU cannot execute. Pin VFPv3+NEON.

> **Not verified.** I did not confirm the *shipped libraries* are all `Tag_FP_arch: VFPv3` (as
> opposed to something narrower). It does not matter for the contract — we build our own — but
> it means "stock ran with VFPv3 libs" is an inference, not a measurement.

### 1.2 glibc: the floor is **2.28**, not 2.31 — **MUST**

`PLAN.md` §3 says *"glibc (any version ≥ 2.31)"*. That is the version stock **ships**
(`work/imgroot/usr/lib/libc.so.6 -> libc-2.31.so`). It is not what the binary **requires**. The
binary's actual floor, from its version-requirements section:

```console
$ readelf -V work/extracted/files/MiSTer
Version needs section '.gnu.version_r' contains 6 entries:
  File: libgcc_s.so.1   -> GCC_3.5
  File: librt.so.1      -> GLIBC_2.4
  File: libm.so.6       -> GLIBC_2.4
  File: libpthread.so.0 -> GLIBC_2.4
  File: libstdc++.so.6  -> GLIBCXX_3.4, GLIBCXX_3.4.11, GLIBCXX_3.4.14, GLIBCXX_3.4.21,
                           CXXABI_1.3, CXXABI_1.3.9
  File: libc.so.6       -> GLIBC_2.4, GLIBC_2.7, GLIBC_2.9, GLIBC_2.17, GLIBC_2.28
```

**The highest glibc version node the binary asks for is `GLIBC_2.28`** (one symbol: `fcntl64`).
The next highest is `GLIBC_2.17` (`clock_gettime`). Everything else is baseline `GLIBC_2.4` —
which is simply glibc's ARM/EABI baseline version, i.e. "since forever".

| # | Requirement | Level |
|---|---|---|
| **T7** | The rootfs's `libc.so.6` provides version nodes up to **`GLIBC_2.28`** | MUST |
| **T8** | `libstdc++.so.6` provides **`GLIBCXX_3.4.21`** and **`CXXABI_1.3.9`** (⇒ GCC ≥ 5.1 with the C++11 ABI) | MUST |
| **T9** | `libgcc_s.so.1` provides **`GCC_3.5`** | MUST |

### 1.3 Why "newer glibc is fine" is true — and the one way it isn't

Newer is fine because of **symbol versioning**. glibc never removes a symbol; when behaviour
changes it adds a *new* version node and keeps the old definition as a *compat symbol*. A binary
that asks for `fcntl64@GLIBC_2.28` gets exactly the glibc-2.28 semantics of `fcntl64`, forever,
from any later glibc. That is the entire mechanism, and it is why running a 2025-vintage binary
on a 2026 glibc is unremarkable.

**But there is a trap, and it is the single most likely way P2.1/P2.2 fails.** Since **glibc
2.34**, `libpthread`, `librt`, `libdl` and `libanl` have been *merged into libc*. The files
still exist, but they are **version-placeholder stubs that no longer define the functions**:

```console
$ readelf -W --dyn-syms /lib/x86_64-linux-gnu/libpthread.so.0     # glibc 2.43
  ...  FUNC GLOBAL DEFAULT 14 __libpthread_version_placeholder@GLIBC_2.28
  ...  FUNC GLOBAL DEFAULT 14 __libpthread_version_placeholder@GLIBC_2.11
      (no pthread_create, no pthread_join)

$ readelf -V /lib/x86_64-linux-gnu/libpthread.so.0 | grep -oE 'Name: GLIBC_[0-9.]+' | sort -uV
  GLIBC_2.2.5  GLIBC_2.2.6  GLIBC_2.3.2 … GLIBC_2.4 … GLIBC_2.31     <-- version nodes ARE kept

$ readelf -W --dyn-syms /lib/x86_64-linux-gnu/libc.so.6 | grep -E ' (pthread_create|shm_open)@'
  pthread_create@GLIBC_2.2.5      <-- compat symbol, at its HISTORICAL version
  pthread_create@@GLIBC_2.34
  shm_open@GLIBC_2.2.5
  shm_open@@GLIBC_2.34
```

So the stock `MiSTer` binary still links against a modern glibc, but only because of a
three-part coincidence, all of which must hold:

1. `libpthread.so.0` / `librt.so.1` **exist as files** (the binary's `DT_NEEDED` names them, and
   the loader hard-fails on a missing `DT_NEEDED`);
2. those stubs still **define the version node `GLIBC_2.4`** (the ARM baseline), because the
   loader verifies `verneed` against the *named* file's `verdef`;
3. **`libc.so.6` exports the actual functions as compat symbols at `@GLIBC_2.4`** — the loader
   then resolves them from the global scope, not from the file the verneed named.

Exactly **five** symbols depend on (2)+(3), and P2.2 should name them explicitly:

| Library the binary names | Symbols it needs from it |
|---|---|
| `libpthread.so.0` @ `GLIBC_2.4` | `pthread_create`, `pthread_join`, `pthread_attr_setaffinity_np` |
| `librt.so.1` @ `GLIBC_2.4` | `shm_open`, `shm_unlink` |

*(Derived by mapping each undefined symbol's `.gnu.version_r` index back to the `DT_NEEDED`
entry it points at — `readelf -d` alone cannot do this. Reproduce with
**`scripts/abi/needed-symbols.py work/extracted/files/MiSTer`**; full output in §13.4.)*

**What actually breaks it:**

| Change | Effect |
|---|---|
| **musl** instead of glibc | Fatal and immediate. No symbol versioning, no `GLIBC_*` version nodes, no `libpthread.so.0` file, different `ld-linux` name. The binary will not even start. **Never an option.** |
| A glibc **older** than 2.28 | `fcntl64@GLIBC_2.28` unresolved → `symbol lookup error` at startup. |
| A glibc built **without** the compat stubs (some hardening/size configs drop them) | `libpthread.so.0: cannot open shared object file` or `version 'GLIBC_2.4' not found`. |
| A **SONAME major bump** in any of the twelve (§2) | `cannot open shared object file`. |
| `libstdc++` older than **GCC 5.1** | `GLIBCXX_3.4.21` / the `__cxx11` string ABI unresolved. |

> **Not verified.** The stub/compat mechanism above was confirmed on this workstation's
> **x86_64 glibc 2.43**, where the baseline version is `GLIBC_2.2.5`. On ARM the baseline is
> `GLIBC_2.4`, and I could not check an ARM glibc ≥ 2.34 directly (no ARM cross-toolchain and no
> ARM sysroot in `work/`). The mechanism is architecture-independent by construction, but
> **P2.2 must re-verify it against the real Buildroot ARM sysroot**, and P2.8's qemu-user smoke
> test is what actually proves it. Treat this as the highest-value assertion in the whole
> contract.

---

## 2. The `DT_NEEDED` set — the single hardest gate

### 2.1 Verbatim

```console
$ readelf -d work/extracted/files/MiSTer

Dynamic section at offset 0xd9eb8 contains 36 entries:
  Tag        Type                         Name/Value
 0x00000001 (NEEDED)                     Shared library: [libc.so.6]
 0x00000001 (NEEDED)                     Shared library: [libstdc++.so.6]
 0x00000001 (NEEDED)                     Shared library: [libm.so.6]
 0x00000001 (NEEDED)                     Shared library: [librt.so.1]
 0x00000001 (NEEDED)                     Shared library: [libfreetype.so.6]
 0x00000001 (NEEDED)                     Shared library: [libbz2.so.1.0]
 0x00000001 (NEEDED)                     Shared library: [libpng16.so.16]
 0x00000001 (NEEDED)                     Shared library: [libz.so.1]
 0x00000001 (NEEDED)                     Shared library: [libImlib2.so.1]
 0x00000001 (NEEDED)                     Shared library: [libbluetooth.so.3]
 0x00000001 (NEEDED)                     Shared library: [libpthread.so.0]
 0x00000001 (NEEDED)                     Shared library: [libgcc_s.so.1]
 …
```

Cross-check: `docs/stock-inventory/binaries-needed.md` § *"The stock `MiSTer` binary (THE ABI
contract…)"* lists the identical twelve.

### 2.2 The contract — **MUST, every row**

**Every SONAME below must exist in the built rootfs at the same major version.** The
"stock realname" column is what stock shipped (`ls -l work/imgroot/usr/lib/`); it is a *floor
for the feature set*, not a pin — a newer point/minor release of the same SONAME is expected and
is the point of the project.

| # | SONAME | Stock realname | Upstream project | Provided by |
|---|---|---|---|---|
| L1 | `libc.so.6` | `libc-2.31.so` | glibc | toolchain |
| L2 | `libm.so.6` | `libm-2.31.so` | glibc | toolchain |
| L3 | `libpthread.so.0` | `libpthread-2.31.so` | glibc (a **stub** on ≥ 2.34 — §1.3) | toolchain |
| L4 | `librt.so.1` | `librt-2.31.so` | glibc (a **stub** on ≥ 2.34 — §1.3) | toolchain |
| L5 | `libstdc++.so.6` | `libstdc++.so.6.0.28` | GCC | toolchain |
| L6 | `libgcc_s.so.1` | `libgcc_s.so.1` | GCC | toolchain |
| L7 | `libz.so.1` | `libz.so.1.2.11` | zlib | `BR2_PACKAGE_ZLIB` |
| L8 | `libbz2.so.1.0` | `libbz2.so.1.0.8` | bzip2 | `BR2_PACKAGE_BZIP2` |
| L9 | `libpng16.so.16` | `libpng16.so.16.37.0` | libpng | `BR2_PACKAGE_LIBPNG` |
| L10 | `libfreetype.so.6` | `libfreetype.so.6.17.4` | FreeType | `BR2_PACKAGE_FREETYPE` |
| L11 | `libImlib2.so.1` | `libImlib2.so.1.6.1` | imlib2 | `BR2_PACKAGE_IMLIB2` |
| L12 | `libbluetooth.so.3` | `libbluetooth.so.3.19.5` | BlueZ | `BR2_PACKAGE_BLUEZ5_UTILS` |

**Watch list — the two that can actually bite (for P0.7):**

* **`libbz2.so.1.0`** is *not* the usual `libbz2.so.1`. bzip2's own build installs
  `libbz2.so.1.0.8` and symlinks `libbz2.so.1.0` → it. Some distro packagings normalise this to
  `libbz2.so.1`. If Buildroot's bzip2 produces only `libbz2.so.1`, the `DT_NEEDED` on
  `libbz2.so.1.0` will not resolve. **Check this explicitly in P2.1.**
* **`libImlib2.so.1`** — imlib2 is not a fashionable package; its SONAME has been `.so.1` for
  20 years, but it also `dlopen`s loader plugins from `usr/lib/imlib2/loaders/*.so`
  (`png.so`, `jpeg.so`, `bmp.so`, …). Those are **not** `DT_NEEDED` and so will not be caught by
  a SONAME check — but `menu.png` / `menu.jpg` backgrounds silently stop working without them.
  See `docs/stock-inventory/shared-libraries.md` (the "plugin/dlopen" breakdown). **SHOULD**:
  ship the imlib2 loader set.

### 2.3 The transitive closure — **MUST**

`libImlib2.so.1` itself pulls in one more library that is not in the binary's own `DT_NEEDED`:

```console
$ readelf -d work/imgroot/usr/lib/libImlib2.so.1.6.1 | grep NEEDED
 libfreetype.so.6  libbz2.so.1.0  libpng16.so.16  libz.so.1  libdl.so.2  libm.so.6  libc.so.6
```

**`libdl.so.2`** — also a glibc merge-stub on ≥ 2.34. Same three-part mechanism as §1.3.

### 2.4 Proof that the whole thing resolves — the P2.8 / P2.2 baseline

Run the stock binary against the stock rootfs under `qemu-arm` with the loader in trace mode.
**This is exactly P2.2's check**, and against the *stock* rootfs it is the known-good baseline:

```console
$ cd work && cp extracted/files/MiSTer /tmp/MiSTer.x && chmod +x /tmp/MiSTer.x
$ LD_TRACE_LOADED_OBJECTS=1 qemu-arm -L imgroot -E LD_TRACE_LOADED_OBJECTS=1 /tmp/MiSTer.x
	linux-vdso.so.1 (0x40801000)
	libc.so.6 => /usr/lib32/libc.so.6 (0x4083b000)
	libstdc++.so.6 => /usr/lib32/libstdc++.so.6 (0x40930000)
	libm.so.6 => /usr/lib32/libm.so.6 (0x40a72000)
	librt.so.1 => /usr/lib32/librt.so.1 (0x40ad9000)
	libfreetype.so.6 => /lib/libfreetype.so.6 (0x40aef000)
	libbz2.so.1.0 => /lib/libbz2.so.1.0 (0x40b9d000)
	libpng16.so.16 => /lib/libpng16.so.16 (0x40bbf000)
	libz.so.1 => /lib/libz.so.1 (0x40c00000)
	libImlib2.so.1 => /lib/libImlib2.so.1 (0x40c28000)
	libbluetooth.so.3 => /lib/libbluetooth.so.3 (0x40c7a000)
	libpthread.so.0 => /usr/lib32/libpthread.so.0 (0x40cb9000)
	libgcc_s.so.1 => /usr/lib32/libgcc_s.so.1 (0x40ce0000)
	/lib/ld-linux-armhf.so.3 (0x40810000)
	libdl.so.2 => /usr/lib32/libdl.so.2 (0x40d0b000)
```

**15 lines, zero `not found`.** The twelve `DT_NEEDED` of §2.1, plus the transitive
`libdl.so.2` (§2.3), plus the vDSO and the loader. *(The `/usr/lib32` prefix on some entries is
an artefact of the stock image's own `ld.so.cache`; irrelevant — what matters is that every
name resolved.)*

### 2.5 …and what happens next — the P2.8 whitelist

Run without the trace variable, the process goes all the way to its first hardware access:

```console
$ qemu-arm -L imgroot -strace /tmp/MiSTer.x
…
openat(AT_FDCWD,"/etc/ld.so.cache",O_RDONLY|O_CLOEXEC) = 3
openat(AT_FDCWD,"/lib/libfreetype.so.6",O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD,"/lib/libbz2.so.1.0",O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD,"/lib/libpng16.so.16",O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD,"/lib/libz.so.1",O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD,"/lib/libImlib2.so.1",O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
openat(AT_FDCWD,"/lib/libbluetooth.so.3",O_RDONLY|O_LARGEFILE|O_CLOEXEC) = 3
… libc / libstdc++ / libm / librt / libpthread / libgcc_s / libdl …
set_tid_address(…) = …
sched_setaffinity(0,128,0x407ffff8) = 0                    <-- main.cpp:48, pin to CPU 1
clone(CLONE_VM|CLONE_FS|…) = 296646                        <-- offload.cpp worker thread
openat(AT_FDCWD,"/dev/mem",O_RDWR|O_LARGEFILE|O_DSYNC|__O_SYNC|O_CLOEXEC) = -1 errno=13 (EACCES)
--- SIGSEGV {si_signo=SIGSEGV, si_code=1, si_addr=0x00706014} ---
```

**This is the exact failure signature P2.8 must whitelist**, and it is worth understanding
precisely, because "MiSTer segfaults" is otherwise an alarming thing to see in CI.

`/dev/mem` fails (we are not root, and this is not a Cyclone V), so `fpga_io_init()` returns
`-1` with `map_base == NULL` (`Main:fpga_io.cpp:534-535`). `main()` **ignores the return value**
(`Main:main.cpp:52`), prints its banner — which is why the strace shows `fstat64(1)`, stdio
setting up — and then reaches:

> `Main:main.cpp:65`
> ```c
> if (!is_fpga_ready(1))
> ```

* `is_fpga_ready(1)` → `fpga_gpi_read()` → `readl(SOCFPGA_MGR_ADDRESS + 0x14)`
  (`Main:fpga_io.cpp:519`, `:659`), i.e. a read of **`0xFF706014`**.
* `MAP_ADDR(x)` is `&map_base[((x) & 0xFFFFFF) >> 2]` (`Main:fpga_io.cpp:29`).
* With `map_base == NULL`, that is a load from **`0x00706014`** — **precisely the faulting
  address `si_addr` reports.**

So the segfault address is itself a fingerprint of the FPGA register plane, and CI can assert on
it. **Any failure *earlier* than the `/dev/mem` openat — a missing library, an unresolved
symbol, a wrong loader — is a hard regression.** Any failure at or after it is expected under
qemu-user.

*(`DISKLED_OFF` at `Main:main.cpp:54` is `#define DISKLED_OFF void()` — a no-op
(`Main:user_io.h:270`) — so it is not the faulting site, despite sitting between the two.)*

---

## 3. `/dev/mem` and the FPGA register plane — the load-bearing core

Everything MiSTer does with the FPGA — loading a core, reading buttons, talking to the running
core, painting the OSD, moving a framebuffer — goes through **one file descriptor on
`/dev/mem`** and `mmap()`. There is no other channel. Main_MiSTer uses **no** kernel FPGA
manager, **no** `/sys/class/fpga_bridge`, **no** kernel SPI device for its core protocol.

### 3.1 The one open, the one mmap primitive

> `Main:shmem.cpp:22`
> ```c
> memfd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
> ```
> `Main:shmem.cpp:30`
> ```c
> void *res = mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, address);
> ```

`shmem_map()` is the *only* `mmap` in the entire program:

```console
$ grep -rn 'mmap(' --include=*.cpp --include=*.h work/Main_MiSTer
work/Main_MiSTer/shmem.cpp:30:	void *res = mmap(0, size, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, address);
```

### 3.2 Every physical address mapped, and what it is — **MUST**

| Region | Size | Mapped at | Contents |
|---|---|---|---|
| **`0xFF000000`** | **`0x01000000`** (16 MiB) | `Main:fpga_io.cpp:534` (`FPGA_REG_BASE`/`FPGA_REG_SIZE`, `:26-27`) | **The entire Cyclone V L3/L4 peripheral region.** One mapping covers everything below. |
| `0x1FFFF000` | `0x1000` (4 KiB) | `Main:fpga_io.cpp:397`, `:595`; `Main:user_io.cpp:1308`, `:1342` | The **U-Boot ⇄ Main_MiSTer warm-reboot mailbox**. Full map in `docs/boot-chain.md` §6.3. |
| `0x22000000` | `1920*1080*4*3` = **24,883,200 B** | `Main:video.cpp:2417` (`FB_ADDR`, `:37`) | The **Linux framebuffer triple-buffer** in FPGA-visible DDR (§4). |
| `0x20000000 \| (addr & 0x1FFFFFFF)` | varies | `fpga_mem()` (`Main:shmem.h:12`); `Main:user_io.cpp:2852`, `support/*/*.cpp` | The **FPGA SDRAM window** — where ROMs, disk images, N64 RDRAM, Neo Geo assets etc. are DMA'd. |

Inside the single 16 MiB mapping (`MAP_ADDR(x) = &map_base[((x) & 0xFFFFFF) >> 2]`,
`Main:fpga_io.cpp:29`) the code reaches, using the Altera register map in
`Main:fpga_base_addr_ac5.h`:

| Physical | Symbol | Used for | Citation |
|---|---|---|---|
| `0xFF200000` … `0xFF3FFFFF` | `SOCFPGA_LWFPGASLAVES_ADDRESS` | **Lightweight HPS→FPGA bridge**, 2 MiB — the core's memory-mapped registers | `Main:fpga_io.cpp:523`, `:528` |
| `0xFF706010` | `SOCFPGA_MGR_ADDRESS + 0x10` | **FPGA manager GPO** — the *write* half of the software SPI to the core | `Main:fpga_io.cpp:514` |
| `0xFF706014` | `SOCFPGA_MGR_ADDRESS + 0x14` | **FPGA manager GPI** — the *read* half | `Main:fpga_io.cpp:519` |
| `0xFF706000` | `SOCFPGA_FPGAMGRREGS_ADDRESS` | FPGA manager control/status — `.rbf` reconfiguration state machine | `Main:fpga_io.cpp:35`, `:50-80` |
| `0xFFB90000` | `SOCFPGA_FPGAMGRDATA_ADDRESS` | FPGA manager **configuration data port** — the `.rbf` bitstream is streamed here by hand-written ARM assembly (`ldmia`/`stmia`) | `Main:fpga_io.cpp:235-256` |
| `0xFF800000` | `SOCFPGA_L3REGS_ADDRESS` | **NIC-301 `remap`** register — bridge enable/disable | `Main:fpga_io.cpp:384`, `:391` |
| `0xFFC25080` | `SOCFPGA_SDR_ADDRESS + 0x5080` | SDRAM controller **FPGA port enable** | `Main:fpga_io.cpp:382`, `:389` |
| `0xFFD05000` | `SOCFPGA_RSTMGR_ADDRESS` | Reset manager — `brg_mod_reset` (bridge resets) and `ctrl` (the reboot) | `Main:fpga_io.cpp:383`, `:390`, `:604` |
| `0xFFD08000` | `SOCFPGA_SYSMGR_ADDRESS` | System manager — `fpgaintfgrp_module` | `Main:fpga_io.cpp:388` |

**The core protocol.** `spi_w()` — used by literally every core interaction in `user_io.cpp`,
`menu.cpp`, `osd.cpp`, `video.cpp`, `audio.cpp` — is a **software SPI bit-banged over the FPGA
manager's GPO/GPI registers**:

> `Main:fpga_io.cpp:688-706`
> ```c
> uint16_t fpga_spi(uint16_t word)
> {
> 	uint32_t gpo = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE)) | word;
> 	fpga_gpo_write(gpo);                 /* -> writel(0xFF706010) */
> 	fpga_gpo_write(gpo | SSPI_STROBE);
> 	int gpi;
> 	do { gpi = fpga_gpi_read();          /* -> readl(0xFF706014) */
> 	     …
> ```

It is **not** a Linux SPI device. There is no `spidev` involved, no `/dev/spi*`, no kernel
driver. If `/dev/mem` cannot map `0xFF000000`, MiSTer has no way to talk to a core at all.

**Bridge control** is likewise done in userland, not via `/sys/class/fpga_bridge`:

> `Main:fpga_io.cpp:378-393`
> ```c
> static void do_bridge(uint32_t enable)
> {
> 	if (enable) {
> 		writel(0x00003FFF, (void*)(SOCFPGA_SDR_ADDRESS + 0x5080));
> 		writel(0x00000000, &reset_regs->brg_mod_reset);
> 		writel(0x00000019, &nic301_regs->remap);
> 	} else {
> 		writel(0, &sysmgr_regs->fpgaintfgrp_module);
> 		writel(0, (void*)(SOCFPGA_SDR_ADDRESS + 0x5080));
> 		writel(7, &reset_regs->brg_mod_reset);
> 		writel(1, &nic301_regs->remap);
> 	}
> }
> ```

Confirmed by exhaustive grep: Main_MiSTer touches **no** `/sys` path other than the four in §7.3
— in particular, nothing under `/sys/class/fpga_bridge` or `/sys/class/fpga_manager`.

### 3.3 The kernel-config consequence (A4) — **MUST**

| # | Symbol | Required | Stock |
|---|---|---|---|
| **D1** | `CONFIG_DEVMEM` | **`y`** | `CONFIG_DEVMEM=y` (`stock-linux.config:1852`) |
| **D2** | `CONFIG_STRICT_DEVMEM` | **not set** | `# CONFIG_STRICT_DEVMEM is not set` (`:4179`) |
| **D3** | `CONFIG_IO_STRICT_DEVMEM` | **not set / absent** | absent (it `depends on STRICT_DEVMEM`) |

**The precise mechanism on 6.18 ARM** (so P1.3 knows what it is defending against):

* `page_is_allowed()` in `linux618:drivers/char/mem.c:59-63` is compiled to `return 1` unless
  `CONFIG_STRICT_DEVMEM`.
* ARM selects `GENERIC_LIB_DEVMEM_IS_ALLOWED` (`linux618:arch/arm/Kconfig:77`), so
  `devmem_is_allowed()` is `linux618:lib/devmem_is_allowed.c:21-28`:
  ```c
  int devmem_is_allowed(unsigned long pfn)
  {
  	if (iomem_is_exclusive(PFN_PHYS(pfn))) return 0;
  	if (!page_is_ram(pfn))                 return 1;
  	return 0;
  }
  ```
* `iomem_is_exclusive()` → `resource_is_exclusive()` (`linux618:kernel/resource.c:1834`). With
  **`IO_STRICT_DEVMEM=y`** any *driver-claimed* (`IORESOURCE_BUSY`) region counts as exclusive.
  The 16 MiB mapping at `0xFF000000` spans the MMC, UART, I2C and SPI controllers — all
  claimed. **The mmap is refused. MiSTer dies.**
* `mmap` on ARM is *not* limited by `valid_phys_addr_range()`; it uses
  `valid_mmap_phys_addr_range()` (`linux618:arch/arm/mm/mmap.c:163-166`), which permits any pfn
  within `PHYS_MASK`. So `0xFF000000` and the above-`mem=511M` DDR are both reachable — **as
  long as the STRICT gates are off.**

> ### Correction to PLAN §3 / A4 (route to P0.9)
>
> PLAN §3 says *"Modern defconfigs enable STRICT_DEVMEM by default"*. On **32-bit ARM this is
> false**: `linux618:lib/Kconfig.debug:1876` reads `default y if PPC || X86 || ARM64 || S390` —
> ARM (32-bit) is **not** in the list, and 6.18's `arch/arm/configs/multi_v7_defconfig` contains
> **no** `DEVMEM` line at all (verified: `grep DEVMEM arch/arm/configs/multi_v7_defconfig` →
> empty). The *conclusion* (assert all three symbols explicitly) is unchanged and correct — but
> the stated reason is wrong, and a P1.3 engineer who goes looking for a `=y` to remove will not
> find one. **The real risk is a well-meaning hardening patch, not the defconfig.**

---

## 4. `MiSTer_fb`: the framebuffer ABI

> Read `docs/patch-provenance.md` §5 *(`0001-fbdev-add-MiSTer_fb-driver.patch`)* alongside this
> section. P1.4 owns the kernel half; this section is the contract it must satisfy.

### 4.1 The physical layout — **MUST**

| Constant | Value | Source |
|---|---|---|
| `FB_ADDR` | `0x20000000 + 32 MiB` = **`0x22000000`** | `Main:video.cpp:37` — *"512mb + 32mb (Core's fb)"* |
| `FB_SIZE` | `1920 * 1080` = 2,073,600 **pixels** (×4 B = 8,294,400 B) | `Main:video.cpp:36` |
| Main_MiSTer's mapping | `shmem_map(FB_ADDR, FB_SIZE * 4 * 3)` = **24,883,200 B** at `0x22000000` | `Main:video.cpp:2417` |
| DTS node | `MiSTer_fb { compatible = "MiSTer_fb"; reg = <0x22000000 0x800000>; interrupts = <0 40 1>; }` | `docs/stock-inventory/stock.dts:993-997` |
| `/dev/fb0` pixels start at | `fb_res->start + 4096` = **`0x22001000`** | `linux515:drivers/video/fbdev/MiSTer_fb.c:265-266` |
| Buffer *n* base (Main_MiSTer's view) | `FB_ADDR + (FB_SIZE*4*n) + (n ? 0 : 4096)` | `Main:video.cpp:3574` |

Read that table carefully, because **the plan's mental model is wrong in one important way**:

> ### Correction — Main_MiSTer does **not** mmap `/dev/fb0`
>
> The P0.5 task text (and the natural reading of PLAN §3) assumes Main_MiSTer maps the
> framebuffer through the fbdev node. **It does not.** The only `mmap` in the program is on
> `/dev/mem` (§3.1), and the framebuffer is reached at its **raw physical address
> `0x22000000`** (`Main:video.cpp:2417`). `/dev/fb0` is opened for **exactly one purpose** — the
> vsync ioctl — and closed immediately (`Main:video.cpp:3856-3868`).
>
> Two consequences, both good news for P1.4:
> * The `fb_mmap` / sysmem-vs-iomem fops question that `docs/patch-provenance.md` §5 calls *"the
>   single most likely place P1.4 breaks"* is **not load-bearing for Main_MiSTer**. It is still
>   load-bearing for **fbcon** (`CONFIG_FRAMEBUFFER_CONSOLE=y`, `stock-linux.config:2529`),
>   which is what paints the text console MiSTer switches to for scripts and the doc viewer
>   (§7.4). So it still has to work — but the failure mode is "the script terminal is blank",
>   not "the menu never appears".
> * The three buffers Main_MiSTer uses (24.9 MB) **overrun the 8 MiB the `MiSTer_fb` DT node
>   claims**. That is intentional: only buffer 0 (1920×1080×4 + 4096 = 8,298,496 B ≤ 8 MiB) is
>   the fbdev framebuffer. Buffers 1 and 2 are OSD/menu backgrounds that only Main_MiSTer knows
>   about, reached purely through `/dev/mem`. **`reg = <0x22000000 0x800000>` is exactly right
>   and must not be "fixed" upward.**

All of this lives at 544 MiB physical, i.e. **far above the `mem=511M` line** — so the kernel's
page allocator never owns it and `/dev/mem` is the only way in. See `docs/boot-chain.md` §6.4.

### 4.2 The ioctl — **MUST, bit-exact**

`MiSTer_fb` implements exactly **one** ioctl (`linux515:drivers/video/fbdev/MiSTer_fb.c:111-133`):

```c
static int fb_ioctl(struct fb_info *info, unsigned int cmd, unsigned long arg)
{
	switch (cmd)
	{
	case FBIO_WAITFORVSYNC:
		if (get_user(ioarg, (u32 __user *)arg)) { ret = -EFAULT; break; }
		ret = fb_wait_for_vsync(ioarg);
		break;
	default:
		ret = -ENOTTY;
	}
	return ret;
}
```

| Property | Value |
|---|---|
| **Name** | `FBIO_WAITFORVSYNC` |
| **Definition** | `_IOW('F', 0x20, __u32)` |
| **Numeric value** | **`0x40044620`** |
| dir / type / nr / size | `_IOC_WRITE` (1) / `'F'` = `0x46` / `0x20` / `4` |
| **Argument** | pointer to a `__u32` that **must be 0** |
| **Returns** | `0` on a vsync; `-ETIMEDOUT` after 50 ms (`VSYNC_TIMEOUT_MSEC`, `MiSTer_fb.c:29`); `-ENODEV` if `*arg != 0` (`:101`); `-ENOTTY` for any other `cmd` (`:128`) |

**`FBIO_WAITFORVSYNC` is a *standard mainline* ioctl, not a MiSTer invention** — and it is
**byte-identical in 5.15 and 6.18**:

```console
$ grep -n FBIO_WAITFORVSYNC work/linux-5.15.1/include/uapi/linux/fb.h \
                            work/linux-stable/include/uapi/linux/fb.h
work/linux-5.15.1/include/uapi/linux/fb.h:37:#define FBIO_WAITFORVSYNC	_IOW('F', 0x20, __u32)
work/linux-stable/include/uapi/linux/fb.h:38:#define FBIO_WAITFORVSYNC	_IOW('F', 0x20, __u32)
```

Value re-derivable from the `_IOC` encoding `(dir<<30)|(size<<16)|(type<<8)|nr`, or from the
real headers:

```console
$ printf '#include <stdio.h>\n#include <linux/fb.h>\nint main(){printf("0x%%08lX\\n",(unsigned long)FBIO_WAITFORVSYNC);}\n' \
   > /tmp/f.c && gcc -o /tmp/f /tmp/f.c && /tmp/f
0x40044620
```

Because the type is a fixed-width `__u32`, **the number is architecture-independent** — 32-bit
ARM and 64-bit x86 agree. **There is no ioctl-number drift risk in P1.4.** The only thing P1.4
can break is the *semantics*: the 50 ms timeout, the `arg != 0 ⇒ -ENODEV` rule, and the fact
that the wait is driven by the FPGA's **IRQ 40** (`irq_handler()` → `frame_count++` →
`wake_up_interruptible(&vs_wait)`, `MiSTer_fb.c:49-54`). Lose the IRQ and every
`FBIO_WAITFORVSYNC` returns `-ETIMEDOUT` after 50 ms — a hard 20 fps cap on the menu, with no
error message.

Consumer:

> `Main:video.cpp:3856-3868`
> ```c
> int fb = open("/dev/fb0", O_RDWR | O_CLOEXEC);
> int zero = 0;
> if (ioctl(fb, FBIO_WAITFORVSYNC, &zero) == -1) { … }
> t1 = getus();
> ioctl(fb, FBIO_WAITFORVSYNC, &zero);
> t2 = getus();
> close(fb);
> ```

### 4.3 The real custom ABI: `/sys/module/MiSTer_fb/parameters/*` — **MUST**

This — not the ioctl — is where the MiSTer-specific framebuffer ABI actually lives.

| Path | Mode | Format | Kernel side | Userland side |
|---|---|---|---|---|
| `/sys/module/MiSTer_fb/parameters/**mode**` | **0664 RW** | five unsigned ints, `"%u %u %u %u %u"` = **`format rb width height stride`** | `module_param_cb(mode, &param_ops, NULL, 0664)`, `MiSTer_fb.c:376`; `mode_set()` `:340-359`; `mode_get()` `:361-370` | `Main:video.cpp:3548-3552` (`fprintf(fp, "%d %d %d %d %d\n", 8888, 1, w, h, w*4)`) and `Main:video.cpp:4390-4391` (`system("echo %d %d %d %d %d >/sys/module/MiSTer_fb/parameters/mode")`) |
| `…/width`, `…/height`, `…/stride`, `…/format`, `…/rb`, `…/frame_count`, `…/res_count` | 0444 RO | `uint` | `module_param(…, uint, 0444)`, `MiSTer_fb.c:32-38` | not read by Main_MiSTer; community scripts do |

Writing `mode`:
1. `console_lock()` + `lock_fb_info()`;
2. **`memset(fb_base, 0, resource_size(fb_res))`** (`:347`) — the whole 8 MiB is wiped;
3. `sscanf(val, "%u %u %u %u %u", &format, &rb, &width, &height, &stride)` (`:349`);
4. `setup_fb_info()` recomputes `bits_per_pixel`, the RGB bitfields and `fix.smem_len`;
5. `fb_set()` → `fb_pan_display` + `fb_set_cmap` + `fb_add_videomode` + **`fbcon_update_vcs()`** (`:336`);
6. `res_count++` (`:355`).

`format` values the driver understands (`MiSTer_fb.c:173-224`): **`8`** (palettised, 8 bpp,
`FB_VISUAL_PSEUDOCOLOR`), **`565`** and **`1555`** (16 bpp), and **anything else ⇒ `8888`**
(32 bpp; the driver *rewrites* `format` to `8888`). `rb` non-zero swaps the red and blue field
offsets. Defaults if never set: `640×480`, `stride = (width*4 + 255) & ~255`
(`MiSTer_fb.c:147-149`).

**MUST for P1.4:** the five-field string, the field order, the `0664` mode, the format codes,
the wipe-on-write, and the read-only parameter names. The word `mode` is written by
`system("echo …")` from a `/bin/sh` — so the file must also be **writable by root via a plain
shell redirect**, which means it must be a real sysfs attribute, not a debugfs node.

### 4.4 Kernel config for the framebuffer — **MUST**

| Symbol | Stock | Why |
|---|---|---|
| `CONFIG_FB=y` | `:2493` | |
| `CONFIG_FB_MISTER=y` | `:2505` | the driver, built in (no module load before `/media/fat/MiSTer` starts) |
| `CONFIG_FRAMEBUFFER_CONSOLE=y` | `:2529` | fbcon — the script/doc terminal (§7.4) |
| `CONFIG_VT=y`, `CONFIG_VT_CONSOLE=y`, `CONFIG_VT_HW_CONSOLE_BINDING=y` | `:1782-1786` | `/dev/tty0`, `VT_ACTIVATE` |

---

## 5. Every `/dev` node Main_MiSTer opens

Derived exhaustively:

```console
$ grep -rn '/dev' --include=*.cpp --include=*.h work/Main_MiSTer     # then filtered by hand
```

There are **no** dynamically-constructed `/dev` paths beyond the four templated ones below
(`/dev/input/%s`, `/dev/i2c-%d`, `/dev/serial/by-id/…`, and the `CMD_FIFO` macro), so this table
is complete for Main_MiSTer @ `14052d2`.

| Node | Opened at | How | Purpose | Provided by | Level |
|---|---|---|---|---|---|
| **`/dev/mem`** | `Main:shmem.cpp:22` | `open(O_RDWR\|O_SYNC\|O_CLOEXEC)` + `mmap` | **Everything.** FPGA registers, core protocol, `.rbf` load, framebuffer, SDRAM window, reboot mailbox (§3) | `CONFIG_DEVMEM=y` + `STRICT_DEVMEM=n` + `IO_STRICT_DEVMEM=n` (A4) | **MUST** |
| **`/dev/fb0`** | `Main:video.cpp:3856` | `open(O_RDWR)`, `ioctl(FBIO_WAITFORVSYNC)`, `close` | Frame pacing only (§4.2). **Never mmap'd.** | `MiSTer_fb` platform driver, DT `compatible="MiSTer_fb"` @ `0x22000000`, IRQ 40 → `0001-…patch` (P1.4) | **MUST** |
| **`/dev/tty0`** | `Main:video.cpp:4251` | `open(O_RDONLY)`, `ioctl(VT_ACTIVATE)`, `ioctl(VT_WAITACTIVE)` | Switch VTs for the framebuffer terminal / doc viewer | `CONFIG_VT=y` + `CONFIG_VT_CONSOLE=y` + fbcon | **MUST** |
| **`/dev/input/event*`** | `Main:input.cpp:5171-5181` (`opendir("/dev/input")`, `strncmp(de->d_name,"event",5)`) | `open(O_RDWR)`; `EVIOCGID`, `EVIOCGNAME`, `EVIOCGUNIQ`, `EVIOCGBIT`, `EVIOCGABS`, `EVIOCGKEY`, `EVIOCGEFFECTS`, `EVIOCSFF`, `EVIOCRMFF`, **`EVIOCGRAB`**; `write()` of `EV_LED` events | All controllers, keyboards, wheels, guns; rumble; keyboard LEDs | `CONFIG_INPUT_EVDEV=y` (`:1573`) + eudev (`60-evdev.rules`, `60-persistent-input.rules`) | **MUST** |
| **`/dev/input/mouse*`** | same loop, `strncmp(de->d_name,"mouse",5)` | `open(O_RDWR)`; `write()` of the ImPS/2 sequence `f3 c8 f3 64 f3 50`, then `read()` expecting `0xFA` (`Main:input.cpp:5240-5247`) | Mouse + **scroll wheel** in the OSD | `CONFIG_INPUT_MOUSEDEV=y` (`:1568`) + eudev (`70-mouse.rules`) | **MUST** |
| **`/dev/uinput`** | `Main:input.cpp:2045` | `open(O_WRONLY\|O_NDELAY)`; `UI_SET_EVBIT`, `UI_SET_KEYBIT`×256, `write(uinput_user_dev)`, `UI_DEV_CREATE`, `UI_DEV_DESTROY` | Main_MiSTer's **own virtual keyboard** — synthesises key events for OSD/menu button combos | `CONFIG_INPUT_UINPUT=y` (`:1734`) | **MUST** |
| **`/dev/MiSTer_cmd`** | `Main:input.cpp:4051`, `:5140-5144` | **`unlink()` + `mkfifo(0666)` + `open(O_RDWR\|O_NONBLOCK)`**, polled `POLLIN` | The **command FIFO**: the documented way for `/media/fat/Scripts` and community tools to drive the menu (`load_core …`, `mount_image …`, …) | Main_MiSTer creates it — but this means **`/dev` must be writable** ⇒ `CONFIG_DEVTMPFS=y` + `CONFIG_DEVTMPFS_MOUNT=y` (`:1103-1104`) | **MUST** |
| **`/dev/i2c-0`, `-1`, `-2`** | `Main:smbus.cpp:226` (`sprintf(str, "/dev/i2c-%d", bus)`), scanned `0..2` | `open(O_RDWR)`; `ioctl(I2C_SLAVE)`, `ioctl(I2C_SMBUS)` | **ADV7513 HDMI transmitter** (§6), plus the SMBus battery gauge | `CONFIG_I2C_CHARDEV=y` (`:1865`) + `CONFIG_I2C_DESIGNWARE_PLATFORM=y` (`:1889`) + the DT i2c nodes | **MUST** |
| **`/dev/spidev1.0`** | `Main:brightness.cpp:74` | `open(O_RDWR)`; `SPI_IOC_WR_MODE`, `SPI_IOC_WR_BITS_PER_WORD`, `SPI_IOC_WR_MAX_SPEED_HZ`, `SPI_IOC_MESSAGE(1)` @ 9600 Hz, 8 bpw, mode 0 | **pi-top hub brightness/lid/shutdown** — *not* the MiSTer I/O board (§5.1) | `CONFIG_SPI_SPIDEV=y` (`:1961`) + a DT `spi1` child whose `compatible` spidev accepts | **SHOULD** |
| **`/dev/urandom`** | `Main:video.cpp:3910`, `Main:support/n64/n64.cpp:360` | `open(O_RDONLY)` + `read()` | Menu background randomisation; N64 IPL seed | kernel core | **MUST** |
| **`/dev/null`** | `Main:cfg.cpp:458` | `fopen("w")` | stdout suppression when `MiSTer.ini` disables logging | kernel core | **MUST** |
| `/dev/midi1` | `Main:menu.cpp:3681`, `:3690` | **`stat()` only** | Presence probe: "is a USB MIDI interface attached?" → offers MidiLink *USB* mode | `CONFIG_SND_RAWMIDI=y` (`:2546`) + `CONFIG_SND_USB_AUDIO=y` (`:2582`) | **SHOULD** |
| `/dev/ttyUSB0` | `Main:menu.cpp:3681`, `:3690`; `Main:user_io.cpp:1277` | **`stat()` only** | Presence probe: USB-serial adapter → offers MidiLink *USB-serial* / UART modes | `CONFIG_USB_SERIAL*` (`:2838-2848`) | **SHOULD** |
| `/dev/serial/by-id/usb-<name>_<id>-if00` | `Main:input.cpp:4674-4681` | `fopen("r+")` + `fprintf("M0x9")` | Puts certain USB-serial **light guns / adapters** into MiSTer-compatible mode | eudev's `60-serial.rules` (the `by-id` symlink farm) | **SHOULD** |

Also used, and easy to overlook:

| Path | Opened at | Purpose | Requires | Level |
|---|---|---|---|---|
| **`/dev/input`** (the *directory*) | `Main:input.cpp:1561` — `inotify_add_watch(mfd, "/dev/input", IN_MODIFY\|IN_CREATE\|IN_DELETE)` | **Hotplug detection.** This is how a controller plugged in at runtime is noticed. | `CONFIG_INOTIFY_USER=y` (`:3470`) **and** that eudev creates/removes nodes *in that directory* (not, say, in `/dev` flat) | **MUST** |
| **`/proc/bus/input/devices`** | `Main:input.cpp:4098` | Parsed for `P: Phys`, `U: Uniq`, `S: Sysfs`, `H: Handlers` to **merge** the several evdev nodes a single physical device exposes, and to find each device's sysfs path (used for LEDs and `bcdDevice`) | `CONFIG_PROC_FS=y` + `CONFIG_INPUT` proc support | **MUST** |
| `/proc/<pid>/exe` | `Main:fpga_io.cpp:614` | `readlink()` — how MiSTer re-execs itself when a core requires a different `main` binary | `CONFIG_PROC_FS=y` | **MUST** |

### 5.1 `/dev/spidev1.0` — the correction, and why it is SHOULD and not MUST

`docs/patch-provenance.md` §N2 and TASKS P1.8 describe the loss of `/dev/spidev1.0` as *"silent
loss of **I/O-board** brightness control"*. **It is not the I/O board.** Read `brightness.cpp`:

* the file's header is `Copyright 2016 rricharz` / *"MiSTer port. Copyright 2018 Sorgelig"* —
  rricharz is the author of the **pi-top** hub tooling;
* the bit masks are `LIDBITMASK`, `SCREENOFFMASK`, `SHUTDOWNMASK`, `BRIGHTNESSMASK`
  (`brightness.cpp:38-42`) — a laptop lid, a screen-off bit and a shutdown request;
* the code literally says *"send 0xFF and receive current status of **pi-top-hub**"*
  (`brightness.cpp:179`) and *"the state is stored on **pi-top-hub**"* (`:197`);
* the only callers are the two keyboard keys `0xBE`/`0xBF` (`Main:user_io.cpp:4216-4224`);
* and U-Boot's very first instruction, `mw 0xff709004 0x800`, comes from commit `56104e0834`
  *"Switch TS3A5018 to SPI mode ASAP to prevent brightness screw **on pi-top**"*
  (`docs/boot-chain.md` §4).

So: SPI1 → the **pi-top chassis hub**, an aftermarket laptop-style enclosure for the DE10-Nano.
Losing `/dev/spidev1.0` costs those users their brightness/lid keys. It costs everyone else
nothing. Hence **SHOULD**, not MUST — with the caveat that it fails *silently* (the probe just
never happens; `open()` returns `ENOENT`; `printf("Unable to open SPI device")` goes to a log
nobody reads), so **P1.13 must assert `/dev/spidev1.0` exists in the boot log**, as
`docs/patch-provenance.md` §5 already says.

*(The MiSTer I/O board's own LEDs and buttons are driven over the FPGA GPO/GPI software SPI —
`fpga_set_led()` `:563`, `fpga_get_buttons()` `:569`, `fpga_get_io_type()` `:577` — i.e. through `/dev/mem`,
not spidev.)*

### 5.2 ioctl request numbers, for the record

All of these are **architecture-independent** (their argument types are fixed-width or
pointer-free), which is why none of them is a forward-port hazard:

| ioctl | Definition | Value | User |
|---|---|---|---|
| `FBIO_WAITFORVSYNC` | `_IOW('F', 0x20, __u32)` | **`0x40044620`** | `video.cpp:3859`, `:3867` |
| `EVIOCGRAB` | `_IOW('E', 0x90, int)` | `0x40044590` | `input.cpp:4828`, `:5528`, `:5631`, `:6463` |
| `EVIOCGID` | `_IOR('E', 0x02, struct input_id)` | `0x80084502` | `input.cpp:5195` |
| `EVIOCGEFFECTS` | `_IOR('E', 0x84, int)` | `0x80044584` | `input.cpp:5222` |
| `EVIOCRMFF` | `_IOW('E', 0x81, int)` | `0x40044581` | `input.cpp:4871` |
| `UI_DEV_CREATE` / `UI_DEV_DESTROY` | `_IO('U', 1)` / `_IO('U', 2)` | `0x5501` / `0x5502` | `input.cpp:2061`, `:2076` |
| `UI_SET_EVBIT` / `UI_SET_KEYBIT` | `_IOW('U', 100/101, int)` | `0x40045564` / `0x40045565` | `input.cpp:2057-2058` |
| `SPI_IOC_MESSAGE(1)` | `_IOW('k', 0, char[32])` | `0x40206B00` | `brightness.cpp:66` |
| `SPI_IOC_WR_MODE` | `_IOW('k', 1, __u8)` | `0x40016B01` | `brightness.cpp:80` |
| `SPI_IOC_WR_BITS_PER_WORD` | `_IOW('k', 3, __u8)` | `0x40016B03` | `brightness.cpp:82` |
| `SPI_IOC_WR_MAX_SPEED_HZ` | `_IOW('k', 4, __u32)` | `0x40046B04` | `brightness.cpp:84` |
| `I2C_SLAVE` / `I2C_SMBUS` | `_IO`-style, historic | `0x0703` / `0x0720` | `smbus.cpp:234`, `:72` |
| `VT_ACTIVATE` / `VT_WAITACTIVE` | historic | `0x5606` / `0x5607` | `video.cpp:4253-4254` |

*(Regenerate with the `gcc` snippet in §13.4. Two ioctls Main_MiSTer also uses — `EVIOCSFF` and
`BLKGETSIZE64` — have **size-dependent** encodings because their argument structs contain a
pointer / `size_t`. Their 32-bit-ARM values are therefore **not** the ones a 64-bit host prints;
I have deliberately not quoted numbers I could not compile for ARM. They are not a hazard: both
are mainline UAPI, unchanged between 5.15 and 6.18, and the kernel and userland compute them
from the same headers.)*

---

## 6. HDMI over I²C — the surface nobody thinks about

The DE10-Nano's HDMI output is an **ADV7513** transmitter that Main_MiSTer configures
**itself**, over `i2c-dev`. There is no kernel DRM/HDMI driver in the picture.

| Device | Address | Opened at |
|---|---|---|
| ADV7513 **main** register map | `0x39` | `Main:video.cpp:1448` — `i2c_open(0x39, 0, -1, &adv_bus)` |
| ADV7513 **EDID** register map | `0x3f` | `Main:video.cpp:1461` |
| ADV7513 **packet/SPD** map | `0x38` | `Main:video.cpp:1467` |
| ADV7513 **CEC** map | `0x3C` | `Main:hdmi_cec.cpp:36`, `:1036` |
| SMBus **battery gauge** | `0x0B` | `Main:battery.cpp:67` — `i2c_open(0x0B, 1)` (portable/pi-top builds) |

The bus is **discovered by scanning**, and the scan is **capped at bus 2**:

> `Main:smbus.cpp:212-227`
> ```c
> int i2c_open(int dev_address, int is_smbus, int force_bus, int *found_bus)
> {
> 	// only /dev/i2c-0..2 exist; an out-of-range pin hint means "not found"
> 	if (force_bus > 2) { printf("i2c_open: invalid bus %d …"); return -1; }
> 	int bus_first = (force_bus >= 0) ? force_bus : 0;
> 	int bus_last  = (force_bus >= 0) ? force_bus : 2;
> 	for (int bus = bus_first; bus <= bus_last; bus++) { sprintf(str, "/dev/i2c-%d", bus); … }
> ```

Stock creates exactly three I²C adapters — verified in `docs/stock-inventory/stock.dts`:

| DT node | Address | `status` | Children |
|---|---|---|---|
| `i2c@ffc04000` (HPS I2C0) | — | **okay** | `adxl345@53` |
| `i2c@ffc05000` (HPS I2C1) | — | disabled | — |
| `i2c@ffc06000` (HPS I2C2) | — | **okay** | — |
| `i2c@ffc07000` (HPS I2C3) | — | disabled | — |
| `i2c_gpio` (bit-banged, `&portb 22/23`) | — | okay | `pcf8563@0x51`, `m41t81@0x68`, `mcp7941x@0x6F` — the RTC add-on board |

⇒ `/dev/i2c-0`, `/dev/i2c-1`, `/dev/i2c-2`. Which one carries the ADV7513 is resolved at
runtime; Main_MiSTer prints `Opened /dev/i2c-N for device 0x39` (`smbus.cpp:260`).

### **MUST — for P1.7 (DTS)**

> **The ADV7513 must be reachable on `/dev/i2c-0`, `-1`, or `-2`.** If our DTB enables a
> *fourth* adapter, or changes the probe order such that the HDMI bus lands on `/dev/i2c-3`,
> `i2c_open()` **refuses to look**, `hdmi_main_fd` stays `-1`, and Main_MiSTer prints
> `"ADV7513 not found on i2c bus! HDMI won't be available!"` (`Main:video.cpp:1451`) — **and the
> board outputs no HDMI**. The number and ordering of I²C adapters is therefore itself part of
> the ABI. Assert `/dev/i2c-0..2` exist and `/dev/i2c-3` does not, in P1.13's boot log.

### **MUST — kernel**

`CONFIG_I2C=y`, `CONFIG_I2C_CHARDEV=y`, `CONFIG_I2C_DESIGNWARE_PLATFORM=y`, plus `i2c-gpio`
(`stock-linux.config:1862-1889`). Note the fork also carries a cosmetic
`i2c-designware-master.c` `dev_err`→`dev_dbg` patch (`docs/patch-provenance.md` F-5) that only
silences boot spam when the RTC add-on is absent — cosmetic, **SHOULD**.

---

## 7. Input, LEDs, and the rest of the runtime surface

### 7.1 `EVIOCGRAB` + mousedev — the coexistence requirement — **MUST**

Main_MiSTer **exclusively grabs** every evdev device while the OSD is open or the core wants
raw input:

> `Main:input.cpp:5528`, `:6463`
> ```c
> ioctl(pool[i].fd, EVIOCGRAB, (grabbed | user_io_osd_is_visible()) ? 1 : 0);
> ```

**And it simultaneously reads `/dev/input/mouseN`** (`Main:input.cpp:5171-5181`, `:5240-5247`).
Under a stock kernel those two are mutually exclusive: `EVIOCGRAB` routes all events to the
grabbing handle *only*. MiSTer works around it with a **core input-subsystem patch**:

> `linux515:drivers/input/input.c` (fork commit `2ac0aa1e8`, *"input: support for mouseX and mice
> in EVIOCGRAB mode"*), inside `input_pass_values()`:
> ```c
>  handle = rcu_dereference(dev->grab);
>  if (handle) {
>  	count = input_to_handler(handle, vals, count);
> +	list_for_each_entry_rcu(handle, &dev->h_list, d_node)
> +		if (handle->open) {
> +			if(!strncmp(handle->name, "mouse", 5)) {
> +				count = input_to_handler(handle, vals, count);
> +				if (!count) break;
> +			}
> +		}
>  } else {
> ```

**Without this patch, Main_MiSTer starves itself**: it grabs the evdev node, and the
`/dev/input/mouseN` fd it is polling in the same `poll()` array goes silent. The menu mouse
stops working. (`gpm`, launched from `/etc/inittab` on `/dev/input/mice`, depends on the same
thing.) This is `0026-input-mousedev-eviocgrab.patch`, and `docs/patch-provenance.md` §6 is right
to route it to **[OPUS]** — it is not a HID quirk, it is a core-input patch, and
`input_pass_values()` has churned since 5.15.

### 7.2 `/sys/class/leds/hps_led0/brightness_hw_changed` — **has a consumer** — SHOULD

`docs/patch-provenance.md` **Q6** asks whether anything reads this, and says *"if nothing does,
drop [the `leds-gpio` patch]"*. **Something does.** Answer for P0.9: **keep the patch.**

> `Main:input.cpp:4052`
> ```c
> #define LED_MONITOR "/sys/class/leds/hps_led0/brightness_hw_changed"
> ```
> `Main:input.cpp:5146-5147` — added to the main `poll()` set with `POLLPRI`:
> ```c
> pool[NUMDEV + 2].fd = open(LED_MONITOR, O_RDONLY | O_CLOEXEC);
> pool[NUMDEV + 2].events = POLLPRI;
> ```
> `Main:input.cpp:6270-6277` — the consumer:
> ```c
> if ((pool[NUMDEV + 2].fd >= 0) && (pool[NUMDEV + 2].revents & POLLPRI))
> {
> 	static char status[16];
> 	if (read(pool[NUMDEV + 2].fd, status, sizeof(status) - 1) && status[0] != '0')
> 	{
> 		if (sysled_is_enabled || video_fb_state()) DISKLED_ON;
> 	}
> 	lseek(pool[NUMDEV + 2].fd, 0, SEEK_SET);
> }
> ```

**The chain:** the DTS gives `hps_led0` `linux,default-trigger = "mmc0"`, so SD-card activity
toggles the physical HPS LED. The MiSTer `leds-gpio` patch (`b62efee23`, 6 lines) sets
`LED_BRIGHT_HW_CHANGED` and calls `led_classdev_notify_brightness_hw_changed()` on every change,
which makes the sysfs attribute `POLLPRI`-wakeable. Main_MiSTer polls it and **mirrors SD
activity onto the core's on-screen disk LED**.

Requires `CONFIG_LEDS_BRIGHTNESS_HW_CHANGED=y` (stock `:2970`) — a **mainline** option
(`linux618:drivers/leds/Kconfig:49`); only the `leds-gpio.c` notification hook is out-of-tree.
Without the patch: `open()` returns `-1`, `fd` stays `-1`, the poll entry is skipped, and the
on-screen disk LED simply never lights. **Cosmetic ⇒ SHOULD**, but it is a 6-line patch with a
proven consumer; there is no reason to drop it.

*(Related, and also SHOULD: `0020-mmc-no-led-on-send-status.patch` (`2d39e76d1`) stops the LED
from flickering on every `MMC_SEND_STATUS` poll. Without it the "disk activity" signal becomes
meaningless noise — the LED is on permanently.)*

### 7.3 The complete `/sys` surface

```console
$ grep -rn '/sys' --include=*.cpp --include=*.h work/Main_MiSTer | grep -v '^work/Main_MiSTer/lib/'
input.cpp:77:    snprintf(path, sizeof(path), "/sys%s", sysfs);              # <dev>/bcdDevice
input.cpp:2647:  sprintf(path, "/sys%s", input[dev].sysfs);                  # <dev>/…/leds/<id>::<name>/brightness
input.cpp:4052:  #define LED_MONITOR "/sys/class/leds/hps_led0/brightness_hw_changed"
input.cpp:4926:  sprintf(path, "/sys%s/device/range", input[dev].sysfs);     # wheel rotation range
menu.cpp:6820:   open("/sys/block/mmcblk0/device/cid", O_RDONLY);            # SD card ID, shown in the menu
video.cpp:3548:  fopen("/sys/module/MiSTer_fb/parameters/mode", "wt");
video.cpp:4390:  system("echo … >/sys/module/MiSTer_fb/parameters/mode");
```

| Path | Level | Note |
|---|---|---|
| `/sys/module/MiSTer_fb/parameters/mode` | **MUST** | §4.3 |
| `/sys/class/leds/hps_led0/brightness_hw_changed` | SHOULD | §7.2 |
| `/sys<devpath>/…/leds/<id>::<name>/brightness` | SHOULD | DualSense / DS4 player-number LEDs, controller lightbars. `get_led_path()` walks the sysfs path from `/proc/bus/input/devices`. Loses colour/number LEDs if absent. |
| `/sys<devpath>/device/range` | SHOULD | Force-feedback wheel rotation range (Logitech/Fanatec) |
| `/sys<devpath>/…/bcdDevice` | SHOULD | USB device revision, used for controller-DB matching |
| `/sys/block/mmcblk0/device/cid` | SHOULD | SD-card identity in the menu's *"Info"* screen |

**Note the absence** of `/sys/class/fpga_bridge`, `/sys/class/fpga_manager`, and anything under
`/sys/devices/system/cpu/cpufreq`. The cpufreq/overclock driver's sysfs
(`docs/patch-provenance.md` §5, `0003-…`) is consumed by **community scripts on `/media/fat`**,
not by Main_MiSTer — which makes it a **SHOULD** from Main_MiSTer's point of view and a **MUST**
from the users' (people overclock their boards and will notice instantly).

### 7.4 Virtual terminals — **MUST**

Main_MiSTer forks an `agetty` on **tty2** to run scripts and the document viewer:

> `Main:menu.cpp:3391-3402` (and identically `:7016-7022`)
> ```c
> unlink("/tmp/script");
> FileSave("/tmp/script", cmd, strlen(cmd));       /* a #!/bin/bash script */
> ttypid = fork();
> if (!ttypid) {
> 	setsid();
> 	execl("/sbin/agetty", "/sbin/agetty", "-a", "root", "-l", "/tmp/script",
> 	      "--nohostname", "-L", "tty2", "linux", NULL);
> ```

and switches to it with `VT_ACTIVATE`/`VT_WAITACTIVE` on `/dev/tty0` (`Main:video.cpp:4251-4254`).

Requirements: **`/dev/tty0`, `/dev/tty1`, `/dev/tty2` must all exist** (`/etc/inittab` already
puts a getty on `tty1`), `CONFIG_VT` + `CONFIG_FRAMEBUFFER_CONSOLE`, `/sbin/agetty`, and a
`/bin/bash` (the generated script's shebang).

> This settles `docs/patch-provenance.md` **F-3 / Q7**: the fork's `MAX_NR_CONSOLES 63 → 9`
> `vt.h` patch (`b2a04cbfd`) is safe to **drop** — nine is far more than the three consoles the
> contract needs, and mainline's 63 is more still. Dropping it removes a UAPI-header patch for
> free. ✔ *Recommend drop.*

### 7.5 The `/tmp` IPC surface — **MUST**

Main_MiSTer's interface to `/media/fat/Scripts` and to MidiLink is a set of **marker files in
`/tmp`**. `/tmp` is a **tmpfs** (`/etc/fstab`), and these files are how a read-only-root system
does IPC. Community scripts read and write them; they are as much an ABI as any ioctl.

| File | Written / read by | Meaning |
|---|---|---|
| `/tmp/CORENAME`, `/tmp/RBFNAME` | `Main:user_io.cpp:1167-1168` | current core name / `.rbf` path |
| `/tmp/STARTPATH`, `/tmp/CURRENTPATH`, `/tmp/FULLPATH`, `/tmp/FILESELECT` | `Main:menu.cpp:1531`, `:2621-2623`, `:5356-5358`, `:6020-6022`; `Main:user_io.cpp:1484` | the **file-browser IPC** used by scripts that ask the user to pick a file |
| `/tmp/GAMEID` | `Main:user_io.cpp:1390`, `:2546` | current game identifier |
| `/tmp/OSD_VISIBLE` | `Main:user_io.cpp:4177` | `"1"`/`"0"` |
| `/tmp/UART_SPEED` | `Main:user_io.cpp:1172` | current UART baud |
| `/tmp/uartmode1` … `/tmp/uartmode6` | `Main:user_io.cpp:1147-1152` (`stat`) | UART mode, set by the `uartmode` helper |
| `/tmp/ML_FSYNTH`, `ML_MUNT`, `ML_USBMIDI`, `ML_UDP`, `ML_TCP`, `ML_UDP_ALT`, `ML_TCP_ALT`, `ML_SERMIDI`, `ML_USBSER` | `Main:user_io.cpp:1254-1288` | **MidiLink mode selection** (§8.3) |
| `/tmp/ML_SOUNDFONT` | `Main:user_io.cpp:1212` | selected SoundFont path |
| `/tmp/script` | `Main:menu.cpp:3392`, `:7017` | the shell script `agetty` is about to run (§7.4) |
| `/tmp/logo.png` | `Main:video.cpp:3999-4027` | the built-in logo, extracted so imlib2 can load it from a path |
| `/tmp/combo_id`, `/tmp/debug.txt`, `/tmp/downloader_needs_reboot_after_linux_update`, `/tmp/MiSTer_downloader_needs_reboot` | `Main:input.cpp:4817`; `Main:cfg.cpp:439`; `dl:src/downloader/constants.py:107-108` | misc |

### 7.6 External programs Main_MiSTer `exec`s / `system()`s — **MUST**

These must exist on `PATH` (or at the absolute path shown) in the rootfs:

| Command | Called from | Purpose |
|---|---|---|
| `/bin/sh` (implicitly, via `system()`) | everywhere | |
| `/bin/bash` | `Main:menu.cpp:3389` (the generated script's shebang) | |
| **`/sbin/agetty`** | `Main:menu.cpp:3402`, `:7022` | script / doc terminal on tty2 |
| **`uartmode <n>`** | `Main:user_io.cpp:1175-1176` | stock: `/usr/sbin/uartmode` (+ `/sbin/uartmode`) |
| **`btctl disconnect <mac>`** | `Main:input.cpp:5582-5586` | stock: `/usr/sbin/btctl` |
| **`/bin/bluetoothd hcireset`** / **`renew`** | `Main:menu.cpp:1106`, `:7166` | stock's BT control script (also `/etc/init.d/S45bluetooth` → symlink to it) |
| `hciconfig hci0 reset` | `Main:menu.cpp:7101` | bluez-utils |
| `mount`, `grep`, `wc` | `Main:user_io.cpp:1456` (`"exit $(mount \| grep \"%s\" \| wc -c)"` — the `waitmount` INI option) | busybox |
| `echo` + shell redirect to sysfs | `Main:video.cpp:4390-4391` | §4.3 |
| `less` | `Main:menu.cpp:3384` | `.txt` doc viewer |
| `/media/fat/linux/pdfviewer`, `/media/fat/linux/glow`, `/media/fat/linux/lesskey` | `Main:menu.cpp:3380-3389` | doc viewer — **these live on the FAT partition, not in the rootfs**, and are shipped by `Distribution_MiSTer`, not by us |

### 7.7 SMP — **MUST**

```c
/* Main:main.cpp:42-48 */
// Always pin main worker process to core #1 as core #0 is the
// hardware interrupt handler in Linux.  This reduces idle latency
// in the main loop by about 6-7x.
CPU_SET(1, &set);
sched_setaffinity(0, sizeof(set), &set);
```

and the `offload` worker thread is pinned to **CPU 0** — *"Set affinity to core #0 since main
runs on core #1"* — with **`pthread_attr_setaffinity_np()`** (`Main:offload.cpp:80-84`), which is
one of the five glibc-merged symbols of §1.3. Stock: `CONFIG_SMP=y`, `CONFIG_NR_CPUS=2`, `CONFIG_HZ=1000`,
`CONFIG_PREEMPT_NONE=y` (`stock-linux.config:408-434`, `:97`). **Both Cortex-A9 cores must come
up.** A kernel that boots single-core (e.g. a broken PSCI/SMP-op port) will still run
MiSTer — `sched_setaffinity` to a nonexistent CPU returns `EINVAL` and is ignored — but with a
documented **6-7× latency regression in the main loop**, which is exactly the kind of thing
P2.9's "boot-to-menu time ≤ stock" gate exists to catch. Assert `nproc == 2` in P1.13.

---

## 8. The audio ABI — and the correction to TASKS P1.5

> **TASKS.md P1.5 says:** *"Card/device name exposed to userland must match stock (**Main_MiSTer
> opens it by name**)."* and *"**Done when:** … ALSA card name verified against stock inventory."*
>
> **This premise is false.** `Main_MiSTer` contains **zero** ALSA code:
>
> ```console
> $ grep -rniE 'mraudio|alsa|snd_pcm|asound|libasound' work/Main_MiSTer \
>       --include=*.cpp --include=*.h --include=Makefile | grep -v '/lib/'
> (no output)
> ```
>
> `Main:audio.cpp` sets volume and audio filters **through the FPGA software SPI**
> (`spi_uio_cmd(UIO_SET_AFILTER)` etc.), i.e. through `/dev/mem` — not through ALSA. Core audio
> (the actual game sound) never touches Linux at all: it goes FPGA → I²S/HDMI in hardware.
>
> **Do not "verify the ALSA card name against what Main_MiSTer opens".** There is nothing to
> verify. `docs/patch-provenance.md` §N4 reached the same conclusion independently; this section
> is the full, traced contract. **P0.9 should correct P1.5's task text.**

### 8.1 What the audio path actually is

```
  a userland program that plays sound
  (fluidsynth │ mt32d │ midilink │ aplay │ timidity │ mpg123 │ vgmplay │ …)
            │  libasound.so.2
            ▼
  /etc/asound.conf   pcm.!default = plug → rate(48000, S16_LE) → file("/dev/MrAudio") → hw:0
            │                                   │                        │
            │                                   │                        └── the "slave" that
            │                                   │                            ALSA needs in order
            │                                   │                            to have a real card
            │                                   ▼
            │                          write() to /dev/MrAudio
            │                                   │  MiSTer-audio-spi.c
            │                                   ▼
            │                     512 KiB dma_alloc_coherent ring
            │                     + spi_write(MrBufferInfo{addr,len,ptr})
            │                                   ▼
            │                              the FPGA fabric
            ▼
   ALSA card 0 = a **patched snd-dummy** (S16_LE / 48 kHz / 2ch / 32 KiB buffer)
```

### 8.2 The three parts, each a MUST

**(a) `/dev/MrAudio` — a character device, dynamic major.**
`linux515:sound/drivers/MiSTer-audio-spi.c`. It is an **SPI driver**
(`compatible = "MiSTer,spi-audio"`, DT node `&spi0/spiusb@0`) that is **not an ALSA driver at
all** — no PCM, no card, no substream. On probe it:

* `dma_alloc_coherent(&spi->dev, 512*1024, …)` — a 512 KiB ring (~2.6 s of audio) (`:17`, `:174`);
* `alloc_chrdev_region(&major, 0, 1, "MrAudio_proc")` (`:186`);
* `class_create(THIS_MODULE, "MrAudio_sys")` (`:192`);
* `device_create(myclass, NULL, major, NULL, "MrAudio")` → **`/dev/MrAudio`** (`:198`);
* `cdev_add(&mycdev, major, 1)` (`:208`).

`write()` (`:97-132`) takes **raw PCM, length truncated to a multiple of 4 bytes**
(`userBufLen & ~3`, `:105` — i.e. one stereo S16_LE frame), copies it into the ring, and
`spi_write()`s a 16-byte descriptor to the FPGA:

```c
typedef struct Info { unsigned int addr; unsigned int len; unsigned int ptr;
                      unsigned int reserved; } Info_t;   /* MiSTer-audio-spi.c:30-36 */
```

`read()` (`:73-95`) returns a one-line status string
(`"rptr: %6d, wptr: %6d, len: %6d, comp: %1d\n"`, `:67`) — a debugging aid, and part of the ABI
only in the sense that nothing may break it.

| Property | Value | Level |
|---|---|---|
| Node name **`/dev/MrAudio`** | `DRIVER_NAME` (`MiSTer-audio-spi.c:15`) | **MUST** |
| Accepts raw **S16_LE, 48 kHz, stereo** `write()`s | driven by `asound.conf`'s `rate` plugin | **MUST** |
| Write length must be 4-byte aligned; > 512 KiB ⇒ `-EFAULT` | `:105`, `:110` | **MUST** |
| Sysfs class name `MrAudio_sys`; chrdev region name `MrAudio_proc` | `:192`, `:186` | SHOULD (cosmetic; nothing parses them) |
| Major number | **dynamic** — nothing may hard-code it | **MUST** (i.e. must stay dynamic; devtmpfs creates the node) |

**(b) `/etc/asound.conf` — the glue, and the actual ABI.** Verbatim
(`work/imgroot/etc/asound.conf`, 433 bytes):

```
pcm.!default
{
    type plug
    slave.pcm
    {
        type rate
        slave
        {
            format S16_LE
            rate 48000
            pcm
            {
                type file
                file "/dev/MrAudio"
                format "raw"
                slave.pcm
                {
                    type hw
                    card 0
                }
            }
        }
    }
}

pcm.front pcm.default
```

**P2.3 must ship this file byte-for-byte.** Note what it implies:
* ALSA's `type file` plugin **duplicates** the stream: it writes the raw PCM to the named file
  *and* passes it to `slave.pcm`. So **card 0 must exist and must accept S16_LE/48000/2ch** —
  otherwise the whole default PCM fails to open and nothing plays, even though `/dev/MrAudio`
  is perfectly happy.
* The card is a **sink**: snd-dummy discards it. It exists only so ALSA has a real device to
  hang timing off.

**(c) ALSA card 0 = a patched `snd-dummy`.** Fork commit `333d49b95` patches
`linux515:sound/drivers/dummy.c`:

* `static bool fake_buffer = 1` → **`0`** — so the dummy card presents a real (if discarded)
  ring buffer, which the `type file` chain needs;
* a `model_MiSTer` (S16_LE, 48 kHz, 2 ch, 32 KiB buffer) is added and **force-selected** as the
  default (`dummy->model = m = &model_MiSTer;`).

The **card names are snd-dummy's own, unmodified**: `card->driver` = `"Dummy"`, `shortname` =
`"Dummy"`, `longname` = `"Dummy 1"` (`dummy.c:1095-1097`).

| Requirement | Level |
|---|---|
| `CONFIG_SND_MISTER_AUDIO=y` (`stock-linux.config:2564`) | **MUST** |
| `CONFIG_SND_DUMMY=y` (`:2566`) — *and it must be **card 0*** | **MUST** |
| `dummy.c`'s `fake_buffer = 0` + `model_MiSTer` **must ship inside `0002-…patch`** | **MUST** |
| `CONFIG_SND_PCM`, `SND_TIMER`, `SND_HRTIMER`, `SND_RAWMIDI`, `SND_SEQUENCER`, `SND_USB_AUDIO`, `SND_OSSEMUL`, `SND_SEQUENCER_OSS` (`:2542-2582`) | **MUST** (MIDI/MT-32 parity) |

> **Correction to `docs/patch-provenance.md` §5 (`0002-…`), minor.** It says *"CMA sizing must
> be preserved"*. Stock has **`# CONFIG_DMA_CMA is not set`**
> (`stock-linux.config:3935`) — there is no CMA pool for coherent DMA at all. MrAudio's 512 KiB
> `dma_alloc_coherent()` comes from the page allocator (an order-7 allocation, done once at
> probe). `CONFIG_CMA=y` is on (`:742`) but unused by this path. **There is no CMA size to
> preserve.** Nothing to do — just don't go looking for a knob that isn't there.

### 8.3 Who actually writes to `/dev/MrAudio`

Nothing in the rootfs mentions `/dev/MrAudio` except `asound.conf`:

```console
$ grep -rl 'MrAudio' work/imgroot
work/imgroot/etc/asound.conf
```

So the writer is **whatever process opens ALSA's default PCM**. On stock that is:

| Writer | Path | Links `libasound.so.2`? |
|---|---|---|
| **`midilink`** | `/usr/sbin/midilink` | yes (`docs/stock-inventory/binaries-needed-full.txt:470`) |
| **`mt32d`** (munt / MT-32 emulation) | `/usr/sbin/mt32d` | yes (`:481`) |
| **`fluidsynth`** (General MIDI, SoundFonts) | `/usr/sbin/fluidsynth` | **no** — it links `libfluidsynth.so.3` (`:443`), which links libasound |
| `aplay`, `amidi`, `speaker-test`, `timidity`, `mpg123`, `vgmplay`, `adplay`, … | `/usr/bin/*` | yes |

**The control plane is the `/tmp/ML_*` marker files** (§7.5): Main_MiSTer's *Audio & Video →
MidiLink* menu writes exactly one of `/tmp/ML_FSYNTH`, `/tmp/ML_MUNT`, `/tmp/ML_USBMIDI`,
`/tmp/ML_UDP`, `/tmp/ML_TCP`, `/tmp/ML_UDP_ALT`, `/tmp/ML_USBSER`
(`Main:user_io.cpp:1264-1288`), then runs `uartmode <n>` (`Main:user_io.cpp:1175-1176`), and the
`midilink` daemon reacts by starting fluidsynth or mt32d and pointing its output at the ALSA
default PCM — which is `/dev/MrAudio`.

**Therefore the audio contract for P1.5 is:**

1. `/dev/MrAudio` exists and accepts raw S16_LE/48 kHz/stereo `write()`s;
2. ALSA **card 0** exists and accepts S16_LE/48000/2ch (the patched snd-dummy);
3. `/etc/asound.conf` ships verbatim (P2.3);
4. `libasound.so.2` + fluidsynth + munt/mt32d + midilink are present (P3.8).

**Nothing about a "card name Main_MiSTer opens".** Nothing about ALSA PCM API churn in the
MiSTer driver — it is a chrdev, and the only ALSA-facing code is snd-dummy, which upstream
maintains. **P1.5 is materially easier than the task list assumes.**

---

## 9. `/media/fat` — mount point, filesystem semantics, layout

### 9.1 The mount point — **MUST**

```c
/* Main:file_io.cpp:1107-1112 */
const char *getStorageDir(int dev)
{
	static char path[32];
	if (!dev) return "/media/fat";
	sprintf(path, "/media/usb%d", usbnum);
	return path;
}
```

**`/media/fat` must be the data partition when `/sbin/init` starts.** `/etc/inittab`'s
`::sysinit:/media/fat/MiSTer &` runs before anything else could mount it. On stock this is done
*by the kernel* (the class-B `init/do_mounts.c` patch bind-mounts it); on ours it is the
initramfs's job (`mount --move` to `/newroot/media/fat`, A2/P1.10). See `docs/boot-chain.md` §9.

`/media/usb0` … `/media/usb7` — **SHOULD** — are created by **usbmount**, triggered by eudev:

```
# work/imgroot/usr/lib/udev/rules.d/usbmount.rules
KERNEL=="sd*", SUBSYSTEM=="block", ACTION=="add", RUN+="/usr/share/usbmount/usbmount add"
```
```
# work/imgroot/etc/usbmount/usbmount.conf
MOUNTPOINTS="/media/usb0 … /media/usb7"
FILESYSTEMS="vfat exfat ext4 ntfs fuseblk"
MOUNTOPTIONS="sync,noexec,nodev,noatime,nodiratime"
```

*(Note `ntfs`/`fuseblk` in that list even though the stock kernel has **no NTFS support** —
harmless dead config. P1.3's "should we add ntfs3?" question has its answer here: stock users
have never had NTFS on USB, whatever this file says.)*

Main_MiSTer treats a `/media/usbN` as usable only if it is a **real mountpoint** — it compares
`st_dev` against `/media`'s and `statfs()`es it (`Main:file_io.cpp:1139-1183`).

### 9.2 Filesystem semantics — the part that is easy to get wrong

`docs/patch-provenance.md` §N1 established that stock's `fs/exfat` is **not mainline's**: it is
the out-of-tree Samsung/`exfat-nofuse` driver. Three properties of it are visible to userland,
and are therefore part of the `/media/fat` ABI:

#### (a) **Symlinks work on `/media/fat`, on FAT32 *and* exFAT** — SHOULD (argued below)

* Kernel side: `linux515:fs/exfat/exfat_super.c:676` `exfat_symlink()`, `:1088` `.symlink`,
  `:1111` `exfat_symlink_inode_operations`. The link is flagged with the FAT **`ATTR_SYSTEM`
  (0x04)** directory-entry attribute — the driver aliases it as
  `#define ATTR_SYMLINK 0x0004` (`linux515:fs/exfat/exfat_api.h:65`, `:75`); fork commit
  `99a2c80d0`, *"use ATTR_SYSTEM as symlink flag to preserve links while copying on Windows or
  other OS"*.
  Because `ATTR_SYSTEM` is a generic FAT directory-entry attribute, **this works on FAT32 too.**
* Mainline has **none of it**: `grep symlink linux-6.18.38/fs/exfat/*.c` → empty; vfat likewise.
* **Main_MiSTer actively consumes it:**

  > `Main:file_io.cpp:1592-1608`
  > ```c
  > // Handle (possible) symbolic link type in the directory entry
  > else if (de->d_type == DT_LNK || de->d_type == DT_REG)
  > {
  > 	sprintf(full_path + path_len, "/%s", de->d_name);
  > 	struct stat entrystat;
  > 	if (!stat(full_path, &entrystat))
  > 	{
  > 		if (S_ISREG(entrystat.st_mode))      de->d_type = DT_REG;
  > 		else if (S_ISDIR(entrystat.st_mode)) de->d_type = DT_DIR;
  > 	}
  > }
  > ```
  > i.e. it `stat()`s `DT_LNK` entries and folds them into `DT_REG`/`DT_DIR` so the file browser
  > shows them as ordinary files and folders. Added January 2019 by Sorgelig
  > (`Main_MiSTer` commit `325f6b6`, *"Improved handling of symbolic links"*).

**Why SHOULD and not MUST — the argument.** Losing symlinks does not stop MiSTer from booting,
loading a core, or reaching the menu; the browser simply stops following links. But: this code
was written *deliberately*, seven years ago, in response to users who symlink `games/` onto
USB/network storage — the DE10-Nano's SD card is small and its games are not. Community
`update_all` / `MiSTer_Batch_Control` guides recommend it. So the population hurt by removing it
is **unknown but non-trivial**, and the failure is silent and confusing (a `games` folder that
"exists" but is empty).

**I cannot determine the size of that population from the repositories.** It requires a human
asking the community. This is `docs/patch-provenance.md` **Q2** and it is still open. Until it
is answered, treat symlink support as a **SHOULD that we should assume is a MUST** — i.e. do not
let P1.10 quietly assume it away. The three options (accept the regression / forward-port the
Samsung driver / add `ATTR_SYSTEM` symlinks to mainline exfat as a small carried patch) are laid
out in `docs/patch-provenance.md` §N1; **option (c) is the only one that both preserves the ABI
and keeps the patch set sane**, and it is plausibly upstreamable.

#### (b) **Filename encoding is UTF-8** — SHOULD (high)

Stock mounts FAT32 *and* exFAT through the one driver with
`CONFIG_EXFAT_DEFAULT_IOCHARSET="utf8"` (`stock-linux.config:3515`). Mainline **vfat** defaults
to `CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"` (also stock's value — but stock's vfat driver is
never used for `/media/fat`). If P1.10 mounts FAT32 with mainline vfat and default options,
**every non-ASCII filename decodes differently**: mojibake in the browser, and — worse — a
mismatch against any UTF-8 path already recorded in a `.cfg`, a recent-files list or a
`gamecontrollerdb` entry. **P1.10 must mount with `-o iocharset=utf8`** (and/or set
`CONFIG_FAT_DEFAULT_UTF8=y`). Cheap; just do it.

#### (c) **`sync,dirsync` — the mount options** — SHOULD (high)

The kernel mounts the data partition with `MS_DIRSYNC | MS_SYNCHRONOUS | MS_NOATIME |
MS_NODIRATIME` (`linux515:init/do_mounts.c:666`, quoted in `docs/patch-provenance.md` §4.1), and
**`/etc/fstab` has no `/media/fat` entry at all** (verified: `work/imgroot/etc/fstab`, §10.2).
So those are the only flags it ever has.

Belt and braces on top: `/etc/inittab` starts **`/etc/resync`**, which is:

```sh
#!/bin/sh
( while [ 1 ]; do sync; sleep 5; done ) &
```

**Everything MiSTer writes — saves, save-states, screenshots, configs — is flushed
synchronously, and a global `sync()` runs every five seconds anyway.** This is not a performance
tunable; it is the design of a device users switch off at the wall. If P1.10's `/init` mounts
`/media/fat` async, the observable change is *"my save was lost when I pulled the power"* —
which will be blamed on the kernel, correctly.

**P1.10 must mount `/media/fat -o sync,dirsync,noatime,nodiratime,iocharset=utf8`** (and **not**
`ro` — only the *root* is read-only). This is `docs/patch-provenance.md` **N3/Q3**.

### 9.3 Layout assumptions — **MUST**

Everything Main_MiSTer expects under the storage root (`/media/fat`, or `/media/usbN` if the
user relocated it):

| Path | Constant | Purpose |
|---|---|---|
| `MiSTer.ini`, `MiSTer_alt_1.ini`, `MiSTer_alt_2.ini`, `MiSTer_alt_3.ini` | `Main:cfg.cpp:521-565` | main config, plus three "alt" slots selected by holding the OSD button at boot |
| `menu.rbf` | `Main:fpga_io.cpp:443`, `:506` | the menu core — U-Boot also preloads it (`core=menu.rbf`) |
| `config/` | `CONFIG_DIR` (`Main:file_io.h:122`) | per-core `.cfg`, `device.bin` (which storage root to use) |
| `games/` | `GAMES_DIR` (`:168`) | |
| `saves/`, `savestates/`, `screenshots/` | `:106`, `:109`, `:112` | **written at runtime** ⇒ `/media/fat` must be **rw** |
| `filters/`, `filters_audio/`, `gamma/`, `shadow_masks/`, `presets/` | `:163-167` | scaler/audio coefficient files |
| `cifs/`, `docs/` | `:169-170` | |
| **`linux/`** | — | the updater's rsync target: `linux.img`, `zImage_dtb`, `uboot.img`, `updateboot`, `u-boot.txt_example`, `user-startup.sh`, `wpa_supplicant.conf`, `gamecontrollerdb/`, `soundfonts/`, `mt32-rom-data/`, `MidiLink.INI`, `pdfviewer`, `glow`, `lesskey` |
| `Scripts/` | — | community scripts; `S99user` runs `linux/user-startup.sh` |
| `linux/gamecontrollerdb/` | `GCDB_DIR` (`Main:gamecontroller_db.cpp:476`) | SDL controller database |

*(The full shipped `files/linux/` inventory is in `docs/downloader-contract.md`; the FAT-side
release layout is `files/{MiSTer, MiSTer_example.ini, menu.rbf, Scripts/, linux/}`.)*

---

## 10. Rootfs and runtime conventions

### 10.1 `/MiSTer.version` — **MUST, and this one is a foot-gun**

```console
$ ls -l work/imgroot/MiSTer.version
-rw-r--r-- 1 … 6 Apr  2  2025 work/imgroot/MiSTer.version
$ xxd work/imgroot/MiSTer.version
00000000: 3235 3034 3032                           250402
```

**Exactly 6 bytes. `YYMMDD`. ASCII. No trailing newline. At the rootfs root — `/MiSTer.version`,
not `/media/fat/linux/MiSTer.version`.**

Why the newline matters — the Downloader compares with a **bare `f.read()`**:

> `dl:src/downloader/linux_updater.py:102-103`
> ```python
> def get_current_linux_version(self):
>     return self._file_system.read_file_contents(FILE_MiSTer_version) \
>            if self._file_system.is_file(FILE_MiSTer_version) else 'unknown'
> ```
> `dl:src/downloader/file_system.py:351-355`
> ```python
> def read_file_contents(self, path: str) -> str:
>     full_path = self._path(path)
>     with open(full_path, 'r') as f:
>         return f.read()          # <-- NO .strip()
> ```
> `dl:src/downloader/linux_updater.py:74`
> ```python
> if current_linux_version == linux['version'][-6:]:
>     return                       # already up to date
> ```
> `dl:src/downloader/constants.py:87`
> ```python
> FILE_MiSTer_version: Final[str] = '/MiSTer.version'
> ```

`"250402\n" != "250402"`. **A single trailing newline makes the comparison never match, so the
Downloader re-downloads and re-flashes the same 94 MB image on every single run, forever.** No
error, no warning — just a permanent, self-inflicted update loop for every user who onboards.

**P2.6's `post-build.sh` must write it with `printf '%s' "$VERSION" > .../MiSTer.version`, never
`echo`.** The test is one line:

```sh
[ "$(wc -c < "${TARGET_DIR}/MiSTer.version")" -eq 6 ] || exit 1
```

*(A missing `/MiSTer.version` is equally bad in a quieter way: `get_current_linux_version()`
returns the literal string `'unknown'`, which never equals a real `version[-6:]`, so **the update
also runs every time**. See `docs/downloader-contract.md` §3.)*

### 10.2 Init, inittab, fstab — **MUST**

**`/etc/inittab`** (verbatim, `docs/stock-inventory/etc-configs.md`). The load-bearing lines:

```
::sysinit:/bin/mount -t proc proc /proc
#::sysinit:/bin/mount -o remount,rw /            <-- commented out: root stays READ-ONLY
::sysinit:/bin/mkdir -p /dev/pts /dev/shm
::sysinit:/bin/mount -a
::sysinit:/media/fat/MiSTer &                    <-- THE LAUNCH. sysinit, backgrounded.
::sysinit:/etc/resync &                          <-- sync(); sleep 5; forever
::sysinit:/sbin/swapon -a
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/etc/init.d/rcS                        <-- the S-scripts run AFTER MiSTer starts
::sysinit:/bin/loadkeys /etc/kbd.map
::sysinit:/bin/setfont
console::respawn:/sbin/agetty --nohostname -L  console  xterm
console::respawn:/sbin/agetty --nohostname -L tty1 linux
::sysinit:/sbin/gpm -m /dev/input/mice -t imps2
::shutdown:/etc/init.d/rcK
::shutdown:/sbin/swapoff -a
::shutdown:/bin/umount -a -r
```

| # | Requirement | Level |
|---|---|---|
| **I1** | **`/media/fat/MiSTer` is launched from `::sysinit`, backgrounded (`&`)** — *not* from an init script, *not* as `respawn` | **MUST** |
| **I2** | It starts **before** `rcS` — i.e. before syslog, udev, network, dbus. The menu comes up while the services are still starting. **This is why boot-to-menu is fast, and P2.9 measures exactly this.** | **MUST** |
| **I3** | `/etc/resync` runs (the 5-second global `sync` loop) | **MUST** |
| **I4** | Serial getty on `console` **and** a getty on `tty1` — `tty2` is left free for Main_MiSTer (§7.4) | **MUST** |
| **I5** | `gpm` on `/dev/input/mice`, ImPS/2 protocol | SHOULD |
| **I6** | BusyBox init (not systemd, not sysvinit) — the `::sysinit` / `respawn` / `shutdown` action set above is BusyBox's | **MUST** |

**`/etc/fstab`** (verbatim):

```
/dev/root	/		ext4	rw,noauto,noatime,nodiratime	0	1
proc		/proc		proc	defaults	0	0
devpts		/dev/pts	devpts	defaults,gid=5,mode=620,ptmxmode=0666	0	0
tmpfs		/dev/shm	tmpfs	mode=0777	0	0
tmpfs		/tmp		tmpfs	mode=1777	0	0
tmpfs		/run		tmpfs	mode=0755,nosuid,nodev	0	0
sysfs		/sys		sysfs	defaults	0	0
tmpfs		/var/lib/samba	tmpfs	mode=1777	0	0
tmpfs		/var/db/dhcpcd	tmpfs	mode=0750	0	0
```

| # | Requirement | Level |
|---|---|---|
| **F1** | **Root is read-only.** Note the fstab line says `rw,noauto` — the read-only-ness comes **only from the `ro` token on the kernel command line**, and `mount -a` never touches `/` because of `noauto`. Do not "fix" the fstab. | **MUST** |
| **F2** | **No `/media/fat` entry.** The data partition's mount options are whatever mounted it (§9.2c). | **MUST** (i.e. do not add one) |
| **F3** | tmpfs on `/tmp` (**mode 1777** — the IPC files of §7.5), `/run`, `/dev/shm` (mode 0777 — `shm_open` from librt), `/var/lib/samba`, `/var/db/dhcpcd` | **MUST** |
| **F4** | `/dev` is **devtmpfs**, auto-mounted by the kernel (`CONFIG_DEVTMPFS_MOUNT=y`) and **writable** (Main_MiSTer `mkfifo`s `/dev/MiSTer_cmd` into it) | **MUST** |

**The init-script naming contract.** `/etc/init.d/rcS` runs every `/etc/init.d/S??*` in sorted
order with `start`; `rcK` runs them in reverse with `stop`. The verified stock set
(`docs/stock-inventory/etc-configs.md`, 14 entries):

```
S01syslogd  S02klogd  S10udev  S30dbus  S40network  S41dhcpcd
S45bluetooth  S49ntp  S50proftpd  S50sshd  S91smb  S99user
(+ rcK, rcS)
```

| # | Requirement | Level |
|---|---|---|
| **S1** | The `S<NN><name>` naming and the **numeric ordering** above (udev before dbus before network before dhcpcd…) | **MUST** |
| **S2** | **`S45bluetooth` is a *symlink* to `/bin/bluetoothd`**, not an inline script (P0.3's finding). `/bin/bluetoothd` is both the init script *and* the thing Main_MiSTer `system()`s for `hcireset`/`renew` (§7.6). It loop-mounts a 2 MiB ext4 image at `/media/fat/linux/bluetooth` onto `/var/lib/bluetooth` — that is how BT pairings survive a read-only root. | **MUST** (P3.5) |
| **S3** | **`S99user` runs `/media/fat/linux/user-startup.sh {start\|stop\|restart}`** if present — the documented user hook | **MUST** |
| **S4** | Hotplug is **eudev** (`/sbin/udevd -d`, `S10udev`), **not mdev** | **MUST** |

### 10.3 The user-file restore contract (A8) — **and the `resolv.conf` correction**

On every linux update the Downloader mounts the *new* `linux.img` read-write and copies six
files from `/media/fat/linux/` into it:

> `dl:src/downloader/constants.py:96-104`
> ```python
> FILE_Linux_user_files: Final[list[tuple[str, str]]] = [
>     ('/media/fat/linux/hostname',    '/etc/hostname'),
>     ('/media/fat/linux/hosts',       '/etc/hosts'),
>     ('/media/fat/linux/interfaces',  '/etc/network/interfaces'),
>     ('/media/fat/linux/resolv.conf', '/etc/resolv.conf'),
>     ('/media/fat/linux/dhcpcd.conf', '/etc/dhcpcd.conf'),
>     ('/media/fat/linux/fstab',       '/etc/fstab'),
> ]
> ```

PLAN §3 / A8 say **"these six destinations must remain regular files"**. That is true of five of
them. It is **not true of `/etc/resolv.conf` in stock**, and it has never been true:

```console
$ debugfs -R "stat /etc/resolv.conf" work/extracted/files/linux/linux.img
Inode: 112   Type: symlink    Mode:  0777   Size: 18
Fast link dest: "../tmp/resolv.conf"
```

*(Independently re-verified for this document, directly against the raw ext4 image — not against
the extracted tree. Same inode 112 P0.3 reports in `docs/stock-inventory/etc-configs.md`.)*

| Destination | Type in stock | A8 says | Reality |
|---|---|---|---|
| `/etc/hostname` | regular file | regular | ✔ |
| `/etc/hosts` | regular file | regular | ✔ |
| `/etc/network/interfaces` | regular file | regular | ✔ |
| **`/etc/resolv.conf`** | **symlink → `../tmp/resolv.conf`** | regular | ✘ **contradicts A8** |
| `/etc/dhcpcd.conf` | regular file | regular | ✔ |
| `/etc/fstab` | regular file | regular | ✔ |

**And the consequence is that the feature does not work.** The Downloader's copy is:

> `dl:src/downloader/file_system.py:377-385`
> ```python
> def copy(self, source: str, target: str) -> None:
>     with open(full_source, 'rb') as fsource, open(full_target, 'wb') as ftarget:
> ```

`open(target, 'wb')` **follows** a symlink; it does not replace it. Run against the
*offline-mounted, unbooted* new image — where `/tmp` is an ordinary empty ext4 directory, not a
live tmpfs — the restore writes the user's custom `resolv.conf` to **`/tmp/resolv.conf` inside
the image**. On the next boot, `tmpfs on /tmp` shadows it instantly.

> ### **"Restore your custom `/etc/resolv.conf`" has been a no-op on every MiSTer, forever.**
>
> Not a bug we introduced, not a bug we can hit — a latent bug in the *stock* system that P0.3
> found and this document is confirming. It is *probably* harmless by original design: the
> symlink exists so `dhcpcd` can rewrite DNS on a read-only root, and a static `resolv.conf` on
> a DHCP-managed console is rare. But it means one sixth of the A8 contract is fictional.

**This forces a decision on us, and it is a genuine fork in the road:**

| Option | Consequence |
|---|---|
| **(a) Bug-for-bug parity** — ship `/etc/resolv.conf` as a symlink to `../tmp/resolv.conf` | Zero behaviour change. The restore stays a no-op. Anyone who reads A8 and expects it to work will be wrong, exactly as they are today. |
| **(b) Make it a regular file** | The restore starts working — we would be **fixing a feature that has silently never worked**. But: a read-only root then has **no writable `/etc/resolv.conf`** for `dhcpcd` to update, so DNS-from-DHCP breaks unless P2.4 provides another mechanism (bind-mount a tmpfs file over it, point `dhcpcd` elsewhere via `dhcpcd.conf`, or run `resolvconf`). And a user who *does* have a stale `/media/fat/linux/resolv.conf` lying around from years ago would suddenly find it taking effect — a behaviour change they might notice, and might not like. |

**Recommendation: (a) for v1**, with the bug documented in the FAQ (P4.8) and a note in P2.3.
"Fixing" a five-year-old latent bug in the same release that swaps the kernel is how you turn one
bisect into two. But this is **not my call** — it is a product decision. **Route to P0.9.**

### 10.4 The read-only root and its writable escape hatches — **MUST**

Everything that needs to write goes to tmpfs or to `/media/fat`. P2.4 owns the full audit; the
ones this contract depends on:

| Writer | Destination | Mechanism |
|---|---|---|
| Main_MiSTer's IPC files | `/tmp` (tmpfs, 1777) | §7.5 |
| Main_MiSTer's `/dev/MiSTer_cmd` | `/dev` (devtmpfs) | §5 |
| saves / savestates / screenshots / configs | `/media/fat` (rw, `sync`) | §9.3 |
| `dhcpcd` leases | `/var/db/dhcpcd` (tmpfs) | fstab |
| Samba state | `/var/lib/samba` (tmpfs) | fstab |
| **BlueZ pairing DB** | `/var/lib/bluetooth` ← **loop-mounted 2 MiB ext4 at `/media/fat/linux/bluetooth`** | `/bin/bluetoothd start` (§10.2, S2) |
| `resolv.conf` | `/tmp/resolv.conf` (tmpfs), via the `/etc/resolv.conf` symlink | §10.3 |
| `wpa_supplicant` config | **`/media/fat/linux/wpa_supplicant.conf`** (read from there by `/etc/network/interfaces`) | `etc-configs.md` |
| SSH host keys | baked into the image (**shared by every install of a release** — see `etc-configs.md`'s note) | P3.7 |

### 10.5 The image itself — **the 512 MiB figure is wrong**

```console
$ ls -l work/extracted/files/linux/linux.img
-rw-r--r-- 1 … 393216000 Apr  2  2025 linux.img
$ dumpe2fs -h work/extracted/files/linux/linux.img
Filesystem volume name:   rootfs
Filesystem UUID:          50ef310c-47b9-4c1c-a2fe-d0202d02b6b4
Filesystem features:      has_journal ext_attr resize_inode dir_index filetype extent 64bit
                          flex_bg sparse_super large_file huge_file dir_nlink extra_isize
                          metadata_csum
Default mount options:    user_xattr acl
Inode count:              96000
Block count:              96000
Block size:               4096
Reserved block count:     4800
Free blocks:              13019
```

| Fact | Value | vs. the plan |
|---|---|---|
| Image size | **393,216,000 B = 375.00 MiB** | PLAN §11 / TASKS **P2.5 say "512 MiB"**. ✘ |
| Volume label | `rootfs` | ✔ matches |
| Fixed UUID | `50ef310c-47b9-4c1c-a2fe-d0202d02b6b4` | ✔ A9 |
| Feature set | the 14 above | A9 abbreviates to four (`HAS_JOURNAL`, `METADATA_CSUM`, `64BIT`, `FLEX_BG`); **the full list is what `mke2fs` must be pinned to** |
| Free space | 13,019 / 96,000 blocks = **13.56 %** | TASKS **P2.7 asserts "≥ 15 % free"** — **stock itself would fail that check.** ✘ |

Both are **corrections for P0.9**, not blockers: we can build a 512 MiB image if we want the
headroom (nothing in the boot chain or the updater cares — the Downloader `dd`s nothing, it
`7za`-extracts a file and swaps it). But P2.5 and P2.7 must be written against a real number, and
P2.7's floor must not be one stock fails.

### 10.6 On-device Python (A6) — **MUST**

Stock ships **Python 3.9** (`work/imgroot/usr/bin/python3.9`; 66 C extensions under
`usr/lib/python3.9/`, per `docs/stock-inventory/shared-libraries.md`). Buildroot 2026.02 ships
3.13+.

`Downloader_MiSTer` — the mechanism by which **our own update reaches users** — runs on the
target's interpreter. So does `update_all` and a large fraction of `/media/fat/Scripts`. **The
interpreter is an ABI surface, and it is the one surface where a regression can make the system
un-updatable.** P3.9 owns the testing; the contract is:

* a `python3` on `PATH` that runs `Downloader_MiSTer`'s test suite green;
* the standard library modules the Downloader and popular scripts import (it is pure-stdlib —
  `subprocess`, `json`, `tempfile`, `os.path`, `typing`, `io`, `hashlib`, `ssl`, `urllib`);
* **`ssl` with working CA certificates** — the Downloader fetches over HTTPS.

### 10.7 Modules and firmware (A5) — **MUST**

The contract, at the level the *ABI* cares about (P3.3 owns the implementation):

| # | Requirement | Evidence | Level |
|---|---|---|---|
| **K1** | `CONFIG_MODULES=y`, `CONFIG_MODULE_SIG` **not set** (out-of-tree modules) | `stock-linux.config:639`; no `CONFIG_MODULE_SIG=y` anywhere in it | **MUST** |
| **K2** | `CONFIG_MODULE_COMPRESS_XZ=y` — modules are `.ko.xz`; `kmod`/`modprobe` must be built with xz support | `:648`; `docs/stock-inventory/modules.md` | **MUST** |
| **K3** | **52** `.ko.xz` modules under `/usr/lib/modules/<kver>/`, 382 built-ins | `docs/stock-inventory/modules.md` | SHOULD (the *set* is a parity target, not an ABI) |
| **K4** | **Autoload is table-driven**: `depmod` at image build → `modules.alias` (915 lines) → eudev matches the kernel's `MODALIAS` uevent → `modprobe`. **No hardcoded module list anywhere.** | `docs/stock-inventory/modules.md` | **MUST** |
| **K5** | `/usr/lib/firmware` — **66 regular files** | `docs/stock-inventory/firmware.md` | **MUST** (for the devices that need it) |

> **Correction, already made by P0.3 and repeated here so it stops propagating:** PLAN §3, §4.1,
> TASKS **A5**, and the verification doc all say **"72 firmware files"**. The real count of
> regular files is **66**. The 72 comes from `find /usr/lib/firmware | wc -l` — 66 files + 5
> subdirectories + the directory itself. `docs/stock-inventory/firmware.md` is authoritative.

---

## 11. What is *not* in the contract (so nobody guards it)

Stated explicitly, because each of these is a plausible thing to over-engineer:

* **No `/sys/class/fpga_bridge`, no `/sys/class/fpga_manager`.** Main_MiSTer configures the FPGA
  and the bridges by hand through `/dev/mem` (§3.2). The DTS `fpga_bridge0/1/2` nodes are stock
  parity (and U-Boot's `bridge enable` runs before Linux), but nothing in userland uses their
  sysfs.
* **No ALSA in Main_MiSTer** (§8).
* **No `mmap` of `/dev/fb0`** (§4.1).
* **No cpufreq access from Main_MiSTer** — only from community scripts (§7.3).
* **Nothing depends on the root loop device being `loop8`.** Verified across
  `work/imgroot/etc`, `/usr/bin`, `/usr/sbin` and Main_MiSTer: zero references.
  (`docs/boot-chain.md` §8.3.) `/init` must use `losetup -f`.
* **Nothing parses `/proc/mounts` or `/etc/mtab`** — no `getmntent` in Main_MiSTer. So
  `mount --move` vs. the kernel's `MS_BIND` is a free choice.
* **`memmap=513M$511M` on the kernel command line is inert on ARM** — there is no `memmap=`
  parser under `arch/arm/`. `mem=511M` does 100 % of the reservation. (`docs/boot-chain.md`
  §6.4.) Do not remove it from the cmdline — we do not control U-Boot — but do not model it.
* **`earlyprintk` in the DTB's static `/chosen/bootargs` never reaches the kernel** — U-Boot's
  `fdt_chosen()` overwrites `bootargs`. (`docs/boot-chain.md` §4.2.)

---

## 12. Cross-references to the kernel side (P0.4)

Every kernel-side item this contract depends on, and who owns it:

| ABI surface | Kernel patch | Task | P0.4 §|
|---|---|---|---|
| `/dev/fb0`, `FBIO_WAITFORVSYNC`, `/sys/module/MiSTer_fb/parameters/*` | `0001-fbdev-add-MiSTer_fb-driver.patch` | **P1.4** | §5 |
| `/dev/MrAudio` + the **patched `dummy.c`** | `0002-sound-add-MiSTer-audio-spi.patch` | **P1.5** | §5, N4 |
| cpufreq/overclock sysfs (community scripts) — OC is via **`scaling_max_freq`** up to `cpuinfo_max_freq` = `1200000`; there is **no** `…/cpu/cpufreq/boost` file (see the P1.6 correction in `patch-provenance.md` §5) | `0003-cpufreq-cyclone5-de10nano-overclock.patch` | **P1.6** | §5 |
| `MiSTer_fb` DT node @ `0x22000000`/IRQ 40; `spi0` → `MiSTer,spi-audio`; `spi1` → spidev; `i2c0`/`i2c2`; `usb1`; bridges; `hps_led0` | `0004-dts-de10nano-MiSTer.patch` | **P1.7** | §5 |
| `/dev/spidev1.0` | retarget the DTS `compatible` (preferred) **or** `0005-spidev-accept-altspi-compatible.patch` | **P1.8** | N2, §5 |
| `EVIOCGRAB` + mousedev coexistence | `0026-input-mousedev-eviocgrab.patch` | **P1.9** [OPUS] | §6 |
| `brightness_hw_changed` on `hps_led0` | `0029-leds-gpio-brightness-hw-changed.patch` | **P1.9** | F-2 / **Q6 — answered here: keep it** |
| disk-LED not flickering on `SEND_STATUS` | `0020-mmc-no-led-on-send-status.patch` | **P1.9** | F-1 |
| symlinks + UTF-8 on `/media/fat` | **decision required** — class G | **P0.9** → P1.3/P1.10 | N1 / **Q1, Q2** |
| `DEVMEM=y` / `STRICT_DEVMEM=n` / `IO_STRICT_DEVMEM=n` | *(config, not a patch)* | **P1.3** | — (`docs/boot-chain.md` §8.6) |

---

## 13. The checklist

The thing `scripts/check-abi.sh` (P2.2) and the hardware gates (P1.13 / P2.9 / P3.13) are built
from. **Every row says how to test it.**

### 13.1 Static — checkable in CI, no hardware (P2.2)

| # | MUST/SHOULD | Assertion | Test |
|---|---|---|---|
| A-1 | MUST | Toolchain is `armv7-a` + NEON + VFPv3 + EABIhf | `readelf -A "$ROOTFS/usr/bin/busybox"` ⇒ `Tag_CPU_arch: v7`, `Tag_FP_arch: VFPv3`, `Tag_Advanced_SIMD_arch: NEONv1`, `Tag_ABI_VFP_args: VFP registers` |
| A-2 | MUST | Dynamic loader is `/lib/ld-linux-armhf.so.3` | `test -e "$ROOTFS/lib/ld-linux-armhf.so.3"` |
| A-3 | MUST | All **12** SONAMEs of §2.2 present at the same major | for each: `test -e "$ROOTFS/usr/lib/$soname"` **and** `readelf -d` of the realname shows a matching `DT_SONAME` |
| A-4 | MUST | `libdl.so.2` present (transitive via imlib2) | as above |
| A-5 | MUST | `libbz2.so.**1.0**` — not `libbz2.so.1` | `test -e "$ROOTFS/usr/lib/libbz2.so.1.0"` |
| A-6 | MUST | glibc provides version node `GLIBC_2.28` | `readelf -V "$ROOTFS/usr/lib/libc.so.6" \| grep -q 'Name: GLIBC_2.28'` |
| A-7 | MUST | `libstdc++.so.6` provides `GLIBCXX_3.4.21` **and** `CXXABI_1.3.9` | `readelf -V` ⇒ both present |
| A-8 | MUST | `libpthread.so.0` and `librt.so.1` **exist as files** and define version node `GLIBC_2.4` | `readelf -V "$ROOTFS/usr/lib/libpthread.so.0" \| grep -q 'Name: GLIBC_2.4'` (same for librt) |
| A-9 | MUST | `libc.so.6` exports the five merged symbols at `@GLIBC_2.4`: `pthread_create`, `pthread_join`, `pthread_attr_setaffinity_np`, `shm_open`, `shm_unlink` | `readelf -W --dyn-syms "$ROOTFS/usr/lib/libc.so.6" \| grep -cE '(pthread_create\|pthread_join\|pthread_attr_setaffinity_np\|shm_open\|shm_unlink)@GLIBC_2\.4'` ⇒ **5**. Derive the required list for *any* binary with `scripts/abi/needed-symbols.py`. |
| A-10 | MUST | **Every** `DT_NEEDED` of the stock `MiSTer` binary resolves against the built rootfs | `LD_TRACE_LOADED_OBJECTS=1 qemu-arm -L "$ROOTFS" -E LD_TRACE_LOADED_OBJECTS=1 ./MiSTer` ⇒ exactly 15 lines, **none** containing `not found` (§2.4). *(Do **not** invoke the loader directly — `qemu-arm … ld-linux-armhf.so.3 --list` segfaults under qemu-user. The env-var form is the one that works, and it is the check TASKS P2.2 asks for.)* |
| A-11 | MUST | `/MiSTer.version` is **exactly 6 bytes** at the image root | `[ "$(wc -c < "$ROOTFS/MiSTer.version")" -eq 6 ]` |
| A-12 | MUST | `/MiSTer.version` content is six ASCII digits, byte-exact | `[ "$(od -An -tx1 "$ROOTFS/MiSTer.version" \| tr -d ' \n')" = "$(printf '%s' "$VERSION" \| od -An -tx1 \| tr -d ' \n')" ]` — a **byte** comparison. Do **not** use `grep`, `read`, or `$(cat …)`: all three swallow a trailing newline and will happily pass a file that bricks the updater (§10.1). |
| A-13 | MUST | `/etc/asound.conf` byte-identical to stock | `sha256sum` against the pinned reference |
| A-14 | MUST | Five of the six A8 destinations are **regular files** | `for f in hostname hosts network/interfaces dhcpcd.conf fstab; do [ -f "$ROOTFS/etc/$f" ] && [ ! -L "$ROOTFS/etc/$f" ]; done` |
| A-15 | **open** | `/etc/resolv.conf` — symlink (parity) or regular file (fix)? | **decide at P0.9** (§10.3), then assert whichever we chose |
| A-16 | MUST | `/etc/fstab` has **no** `/media/fat` entry | `! grep -q '/media/fat' "$ROOTFS/etc/fstab"` |
| A-17 | MUST | `/etc/fstab` root line is `rw,noauto,…` | `grep -qE '^/dev/root\s+/\s+ext4\s+rw,noauto' "$ROOTFS/etc/fstab"` |
| A-18 | MUST | tmpfs on `/tmp` (**1777**), `/run`, `/dev/shm`, `/var/lib/samba`, `/var/db/dhcpcd` | grep the fstab |
| A-19 | MUST | `/etc/inittab` launches `/media/fat/MiSTer` from `::sysinit`, backgrounded | `grep -qF '::sysinit:/media/fat/MiSTer &' "$ROOTFS/etc/inittab"` |
| A-20 | MUST | The 12 S-scripts of §10.2 exist, with those exact names | `ls "$ROOTFS/etc/init.d/"` |
| A-21 | MUST | Helper binaries present: `/sbin/agetty`, `/bin/bash`, `uartmode`, `btctl`, `/bin/bluetoothd`, `hciconfig`, `less`, `gpm` | `test -x` each |
| A-22 | MUST | **P2.8:** stock `MiSTer` under `qemu-arm` in the new rootfs reaches `openat("/dev/mem") = -1 EACCES` and then `SIGSEGV @ 0x00706014` | `qemu-arm -L "$ROOTFS" -strace ./MiSTer 2>&1 \| grep -q 'openat.*"/dev/mem"'` **and** no earlier failure. Anything before that openat is a **hard fail** (§2.5). |
| A-23 | MUST | `python3` present; `Downloader_MiSTer`'s suite green on it | P3.9 |
| A-24 | MUST | Firmware: **66** regular files under `/usr/lib/firmware` (+ whatever new modules need) | `find "$ROOTFS/usr/lib/firmware" -type f \| wc -l` |
| A-25 | MUST | `modules.alias` regenerated by `depmod` at image build | `test -s "$ROOTFS/usr/lib/modules/$KVER/modules.alias"` |

### 13.2 Kernel config — checkable at build time (P1.3; extends `docs/boot-chain.md` §8)

| # | MUST/SHOULD | Symbol | Value |
|---|---|---|---|
| C-1 | MUST | `CONFIG_DEVMEM` | `y` |
| C-2 | MUST | `CONFIG_STRICT_DEVMEM` | **not set** |
| C-3 | MUST | `CONFIG_IO_STRICT_DEVMEM` | **not set** |
| C-4 | MUST | `CONFIG_FB`, `CONFIG_FB_MISTER` | `y`, `y` (built-in) |
| C-5 | MUST | `CONFIG_FRAMEBUFFER_CONSOLE`, `CONFIG_VT`, `CONFIG_VT_CONSOLE` | `y` |
| C-6 | MUST | `CONFIG_SND_MISTER_AUDIO`, `CONFIG_SND_DUMMY` | `y`, `y` |
| C-7 | MUST | `CONFIG_SND_PCM`, `SND_TIMER`, `SND_HRTIMER`, `SND_RAWMIDI`, `SND_SEQUENCER`, `SND_USB_AUDIO` | `y` |
| C-8 | MUST | `CONFIG_INPUT_EVDEV`, `INPUT_MOUSEDEV`, `INPUT_JOYDEV`, `INPUT_UINPUT` | `y` |
| C-9 | MUST | `CONFIG_INOTIFY_USER` | `y` |
| C-10 | MUST | `CONFIG_I2C`, `CONFIG_I2C_CHARDEV`, `CONFIG_I2C_DESIGNWARE_PLATFORM` | `y` |
| C-11 | SHOULD | `CONFIG_SPI`, `CONFIG_SPI_SPIDEV` | `y` |
| C-12 | MUST | `CONFIG_DEVTMPFS`, `CONFIG_DEVTMPFS_MOUNT` | `y` |
| C-13 | MUST | `CONFIG_TMPFS`, `CONFIG_PROC_FS`, `CONFIG_SYSFS` | `y` |
| C-14 | MUST | `CONFIG_SMP`, `CONFIG_NR_CPUS` | `y`, `2` |
| C-15 | SHOULD | `CONFIG_LEDS_CLASS`, `CONFIG_LEDS_GPIO`, `CONFIG_LEDS_BRIGHTNESS_HW_CHANGED`, `CONFIG_LEDS_TRIGGERS` | `y` |
| C-16 | MUST | `CONFIG_MODULES=y`, `CONFIG_MODULE_COMPRESS_XZ=y`, `CONFIG_MODULE_SIG` not set | |
| C-17 | MUST | `CONFIG_EXT4_FS`, `CONFIG_VFAT_FS`, `CONFIG_EXFAT_FS`, `CONFIG_BLK_DEV_LOOP` | `y` (built-in) |
| C-18 | MUST | NLS: `NLS_CODEPAGE_437`, `NLS_ISO8859_1`, `NLS_UTF8`, `NLS_ASCII` | `y` |
| C-19 | SHOULD | `CONFIG_USB_SERIAL*`, `CONFIG_SND_USB_AUDIO` (for `/dev/ttyUSB0`, `/dev/midi1` probes) | `y` |

*(C-1..C-3 duplicate `docs/boot-chain.md` §8.6 P1–P3 deliberately: this is the checklist a
reviewer of the ABI doc will read, and it must be complete on its own.)*

### 13.3 Hardware — P1.13 / P2.9 / P3.13

| # | MUST/SHOULD | Assertion | How |
|---|---|---|---|
| H-1 | MUST | `/dev/mem` mappable: MiSTer starts and reaches the menu | P2.9 |
| H-2 | MUST | `/dev/fb0` exists; `FBIO_WAITFORVSYNC` returns 0 (not `-ETIMEDOUT`) ⇒ **IRQ 40 is wired** | `dmesg \| grep 'MiSTer_fb'` shows `IRQ=`; menu is not capped at 20 fps |
| H-3 | MUST | `/sys/module/MiSTer_fb/parameters/mode` is writable and round-trips | `echo "8888 1 640 480 2560" > … ; cat …` |
| H-4 | MUST | `/dev/MrAudio` exists; ALSA **card 0** exists and accepts S16_LE/48000/2ch | `ls -l /dev/MrAudio`; `aplay -l`; `speaker-test -c2 -r48000 -fS16_LE` |
| H-5 | MUST | `/dev/i2c-0`, `-1`, `-2` exist; `/dev/i2c-3` does **not**; MiSTer logs `Opened /dev/i2c-N for device 0x39` | serial log + `ls /dev/i2c-*` |
| H-6 | MUST | HDMI output appears | P2.9 |
| H-7 | SHOULD | `/dev/spidev1.0` exists; **no** `spidev: probed from DT without matching compatible`-class warning | `ls /dev/spidev*`; `dmesg` |
| H-8 | MUST | `/dev/input/event*` **and** `/dev/input/mouse*` exist; mouse moves the OSD cursor **while the OSD is open** (⇒ the `EVIOCGRAB`/mousedev patch works) | P3.13 |
| H-9 | MUST | `/dev/uinput` exists | `ls -l /dev/uinput` |
| H-10 | MUST | `/dev/MiSTer_cmd` is created by MiSTer at startup | `ls -l /dev/MiSTer_cmd` |
| H-11 | SHOULD | `/sys/class/leds/hps_led0/brightness_hw_changed` exists; the on-screen disk LED flickers on SD access | P3.13 |
| H-12 | MUST | `nproc` == 2 | serial console |
| H-13 | MUST | `/media/fat` is mounted, **rw**, with `sync,dirsync,noatime,nodiratime` | `grep /media/fat /proc/mounts` |
| H-14 | MUST | `/` is mounted **ro** | `grep ' / ' /proc/mounts` |
| H-15 | SHOULD | A symlink on `/media/fat` resolves in the file browser | P3.13 — **pending the Q1/Q2 decision** |
| H-16 | SHOULD | A non-ASCII filename on `/media/fat` renders correctly | P3.13 |
| H-17 | MUST | tty2 works: a script from the menu opens a terminal and its output is visible | P3.13 |
| H-18 | MUST | Boot-to-menu time ≤ stock | P2.9 (§10.2/I2 is why it is fast) |

### 13.4 Re-deriving the evidence in this document

Everything above can be regenerated from `work/`. These are the commands the rest of the
document refers back to.

**The stock binary's ABI surface** (§1, §2):

```sh
B=work/extracted/files/MiSTer
readelf -h "$B"                 # ELF32 / ARM / hard-float ABI
readelf -A "$B"                 # Tag_CPU_arch, Tag_FP_arch, Tag_ABI_VFP_args
readelf -p .interp "$B"         # /lib/ld-linux-armhf.so.3
readelf -d "$B" | grep NEEDED   # the twelve SONAMEs
readelf -V "$B"                 # the version_r section: the glibc/libstdc++ floors
```

**Which library each versioned symbol comes from** (§1.3 — the `libpthread`/`librt` five):

```console
$ scripts/abi/needed-symbols.py work/extracted/files/MiSTer
libc.so.6          GLIBC_2.17       1  clock_gettime
libc.so.6          GLIBC_2.28       1  fcntl64
libc.so.6          GLIBC_2.4      135  __aeabi_atexit, __assert_fail, __ctype_b_loc, ...
libc.so.6          GLIBC_2.7        2  __isoc99_fscanf, __isoc99_sscanf
libc.so.6          GLIBC_2.9        1  inotify_init1
libgcc_s.so.1      GCC_3.5          2  __aeabi_unwind_cpp_pr0, __aeabi_unwind_cpp_pr1
libm.so.6          GLIBC_2.4        8  atan2f, floorf, fmaxf, fminf, hypotf, nearbyintf, ...
libpthread.so.0    GLIBC_2.4        3  pthread_attr_setaffinity_np, pthread_create, pthread_join
librt.so.1         GLIBC_2.4        2  shm_open, shm_unlink
libstdc++.so.6     CXXABI_1.3       8  __cxa_begin_catch, __cxa_end_catch, ...
libstdc++.so.6     CXXABI_1.3.9     1  _ZdlPvj
libstdc++.so.6     GLIBCXX_3.4     26  _ZNSirsERi, _ZNSt12__basic_fileIcED1Ev, ...
libstdc++.so.6     GLIBCXX_3.4.11   1  _ZNKSt5ctypeIcE13_M_widen_initEv
libstdc++.so.6     GLIBCXX_3.4.14   1  _ZSt25__throw_bad_function_callv
libstdc++.so.6     GLIBCXX_3.4.21   8  _ZNKSt7__cxx1112basic_string...5rfindEcj, ...
```

Those 15 rows **are** the ABI floor of §1.2 and §1.3, machine-generated. The two rows that
matter most are `libpthread.so.0` and `librt.so.1`: five symbols that a glibc ≥ 2.34 no longer
puts in those files (§1.3). `--symbols` prints the full lists. The script maps each undefined
symbol back to the `DT_NEEDED` entry its version index points at — something `readelf -d`
alone cannot tell you, and something P2.2's checker needs.

**The ioctl numbers** (§5.2) — from the *real* kernel headers, not from memory:

```sh
cat > /tmp/ioc.c <<'EOF'
#include <stdio.h>
#include <linux/fb.h>
#include <linux/spi/spidev.h>
#include <linux/input.h>
#include <linux/uinput.h>
int main(void){
  printf("FBIO_WAITFORVSYNC        = 0x%08lX\n", (unsigned long)FBIO_WAITFORVSYNC);
  printf("SPI_IOC_MESSAGE(1)       = 0x%08lX\n", (unsigned long)SPI_IOC_MESSAGE(1));
  printf("SPI_IOC_WR_MODE          = 0x%08lX\n", (unsigned long)SPI_IOC_WR_MODE);
  printf("SPI_IOC_WR_BITS_PER_WORD = 0x%08lX\n", (unsigned long)SPI_IOC_WR_BITS_PER_WORD);
  printf("SPI_IOC_WR_MAX_SPEED_HZ  = 0x%08lX\n", (unsigned long)SPI_IOC_WR_MAX_SPEED_HZ);
  printf("EVIOCGRAB                = 0x%08lX\n", (unsigned long)EVIOCGRAB);
  printf("EVIOCGID                 = 0x%08lX\n", (unsigned long)EVIOCGID);
  printf("EVIOCGEFFECTS            = 0x%08lX\n", (unsigned long)EVIOCGEFFECTS);
  printf("EVIOCRMFF                = 0x%08lX\n", (unsigned long)EVIOCRMFF);
  printf("UI_DEV_CREATE            = 0x%08lX\n", (unsigned long)UI_DEV_CREATE);
  printf("UI_SET_EVBIT             = 0x%08lX\n", (unsigned long)UI_SET_EVBIT);
  return 0;
}
EOF
gcc -o /tmp/ioc /tmp/ioc.c && /tmp/ioc
```

Every value printed by that program is **architecture-independent** (fixed-width argument
types), which is why a host build is sufficient evidence. `EVIOCSFF` and `BLKGETSIZE64` are
**not** in the list, deliberately: their encodings depend on `sizeof(struct ff_effect)` /
`sizeof(size_t)`, so a host build would print the *wrong* numbers for 32-bit ARM (§14.4).

**The image and the six user files** (§10.1, §10.3, §10.5):

```sh
IMG=work/extracted/files/linux/linux.img
xxd work/imgroot/MiSTer.version                     # 6 bytes, no 0x0a
dumpe2fs -h "$IMG"                                  # label, UUID, feature set, block count
debugfs -R "stat /etc/resolv.conf" "$IMG"           # inode 112, symlink -> ../tmp/resolv.conf
```

---

## 14. Open questions and corrections for P0.9

Nothing below has been actioned. `PLAN.md` and `TASKS.md` are untouched by this task, per the
standing rules.

### 14.1 Corrections to `PLAN.md` / `TASKS.md`

| # | Where | Says | Reality | Severity |
|---|---|---|---|---|
| **X1** | **TASKS P1.5** ("Card/device name exposed to userland must match stock (Main_MiSTer opens it by name)"; "ALSA card name verified against stock inventory") | Main_MiSTer opens an ALSA card by name | **Main_MiSTer contains zero ALSA code.** The contract is `/dev/MrAudio` + `/etc/asound.conf` + a **patched snd-dummy as card 0**. The acceptance criterion as written cannot be met because there is nothing to verify. **Rewrite P1.5's task text** (§8). | **HIGH** |
| **X2** | **PLAN §3** ("all six [user-file destinations] must remain regular files") + **A8** | six regular files | **Five** are regular files; **`/etc/resolv.conf` is a symlink to `../tmp/resolv.conf`** (inode 112, re-verified against the raw image). And because the Downloader's `copy()` follows symlinks, **the "restore your custom resolv.conf" step has always been a no-op** (§10.3). | **HIGH** (it forces a decision — see Q-A) |
| **X3** | **PLAN §11**, **TASKS P2.5** ("512 MiB ext4"), **P2.7** ("≥ 15 % free in the 512 MiB image") | 512 MiB, ≥ 15 % free | Stock `linux.img` is **375.00 MiB** (393,216,000 B) and has **13.56 %** free — **stock would fail P2.7's own check.** Pick a real size and a floor stock passes (§10.5). | MEDIUM |
| **X4** | **PLAN §3 / A4** ("Modern defconfigs enable STRICT_DEVMEM by default") | ARM defconfigs turn it on | **False on 32-bit ARM.** `STRICT_DEVMEM` is `default y if PPC \|\| X86 \|\| ARM64 \|\| S390` (`linux618:lib/Kconfig.debug:1876`) and 6.18's `multi_v7_defconfig` has no `DEVMEM` line at all. The *assertion* stays; the *rationale* is wrong, and a P1.3 engineer will waste time hunting a symbol that isn't there. The real risk is a hardening patch, not the defconfig (§3.3). | MEDIUM |
| **X5** | **PLAN §3** ("glibc … ≥ 2.31") | 2.31 floor | The **binary's** floor is **`GLIBC_2.28`**; 2.31 is merely what stock *ships*. The number is harmless, but the *reason* matters: what will actually break us is the **glibc ≥ 2.34 libpthread/librt merge** (§1.3), which the plan does not mention at all and which is the single highest-risk item in P2.1/P2.2. | MEDIUM |
| **X6** | **PLAN §3 / §4.1 / A5**, verification doc ("72 firmware files") | 72 | **66** regular files. Already corrected by `docs/stock-inventory/firmware.md`; repeated here because three documents still say 72 (§10.7). | LOW |
| **X7** | **`docs/patch-provenance.md` §5 (`0002-…`)** ("CMA sizing must be preserved") | there is CMA sizing to preserve | Stock has **`# CONFIG_DMA_CMA is not set`**. MrAudio's 512 KiB `dma_alloc_coherent()` comes from the page allocator. No CMA knob exists (§8.2). | LOW |
| **X8** | **`docs/patch-provenance.md` §N2**, **TASKS P1.8** ("silent loss of **I/O-board** brightness") | I/O board | It is the **pi-top chassis hub** (lid/screen-off/shutdown/brightness over SPI1). The I/O board's LEDs and buttons go over the FPGA GPO/GPI, not spidev. Severity drops from "a MiSTer feature" to "a pi-top accessory feature" — but the *silence* of the failure is unchanged, so keep the P1.13 assertion (§5.1). | LOW |
| **X9** | **`docs/patch-provenance.md` §6** ("Without the patch, grabbing starves `/dev/input/mice`") | `/dev/input/mice` | Main_MiSTer opens `/dev/input/**mouse**N` (`strncmp(de->d_name, "mouse", 5)` — `mice` does not match). `/dev/input/mice` is what **`gpm`** uses (from inittab). Both depend on the patch; the *primary* victim is Main_MiSTer's own OSD mouse (§7.1). Cosmetic wording fix. | LOW |

### 14.2 Questions answered by this task

| P0.4 ref | Question | **Answer** |
|---|---|---|
| **Q6** (F-2) | *"`leds-gpio` `brightness_hw_changed`: no consumer found in Main_MiSTer. Confirm at P0.5, then drop if truly unused."* | **There IS a consumer.** `Main:input.cpp:4052` + `:5146` + `:6270-6277` — it is polled `POLLPRI` and drives the on-screen disk-activity LED. **Keep `0029-leds-gpio-brightness-hw-changed.patch`.** (§7.2) |
| **Q7** (F-3, partial) | *"`vt.h` `MAX_NR_CONSOLES 63 → 9`: recommend dropping. Confirm."* | **Safe to drop.** The contract needs exactly three consoles: `tty0` (VT control), `tty1` (getty), `tty2` (Main_MiSTer's script/doc terminal). Mainline's 63 is fine. (§7.4) |

### 14.3 Questions still open

| # | Question | Owner | Severity |
|---|---|---|---|
| **Q-A** | **`/etc/resolv.conf`: reproduce the stock symlink (bug-for-bug parity, the restore stays a no-op) — or make it a regular file and thereby *fix* a feature that has silently never worked?** Fixing it means P2.4 must find another writable-DNS mechanism for a read-only root, *and* it means a user's forgotten `/media/fat/linux/resolv.conf` suddenly takes effect. My recommendation is **parity for v1 + a FAQ entry**, but this is a product call, not an engineering one. | **P0.9 (human)** → P2.3, P2.4 | **HIGH** |
| **Q-B** | **Do people actually use symlinks on `/media/fat`?** (= `docs/patch-provenance.md` **Q2**, restated because this document is where the consumer is proved: `Main:file_io.cpp:1592-1608` resolves `DT_LNK` deliberately, and has since 2019.) If the answer is "essentially nobody", the exfat decision (Q1) collapses to "accept the regression + release note". If it is "a meaningful minority", we need the `ATTR_SYSTEM` symlink patch on mainline exfat. **I cannot answer this from the repositories. It needs a human to ask the community.** | **human** | **HIGH** |
| **Q-C** | **Image size and free-space floor** (X3). 375 MiB with 13.6 % free, or grow to 512 MiB? The updater does not care. But P2.7's assertion must be against a number stock could pass. | P0.9 → P2.5, P2.7 | MEDIUM |
| **Q-D** | **The glibc ≥ 2.34 stub mechanism (§1.3) was verified on x86_64, not ARM.** P2.2 must re-verify `libpthread.so.0`/`librt.so.1` version nodes and libc's five `@GLIBC_2.4` compat symbols against the real Buildroot ARM sysroot. If Buildroot's glibc is ever built in a configuration that drops the compat stubs, **the stock binary will not start and nothing else in the project matters.** Treat A-8/A-9 as the highest-value rows in the checklist. | P2.2 | MEDIUM |
| **Q-E** | **I²C adapter numbering** (§6). Main_MiSTer refuses to scan past `/dev/i2c-2`. Our DTB must not create a fourth adapter or reorder the existing three, or HDMI dies silently. P1.7 must assert this; **I could not determine from the schematics *which* physical bus the ADV7513 is on** (Main_MiSTer discovers it at runtime and stock's DTS enables `i2c0` + `i2c2` + `i2c-gpio`), so the assertion has to be "≤ 3 adapters, ADV7513 answers on one of 0/1/2", not a specific bus. | P1.7, P1.13 | MEDIUM |
| **Q-F** | `/media/fat` mount options (`sync,dirsync`) — reproduce, or switch to async and document the power-off-corruption trade-off? (= `docs/patch-provenance.md` **Q3**; restated because §9.2c adds the `/etc/resync` evidence: stock is *doubly* paranoid about flushing, which reads like a deliberate response to real corruption reports.) **Recommendation: reproduce.** | P1.10 | MEDIUM |

### 14.4 Things I could not verify

Stated so nobody mistakes them for verified:

* **The ARM glibc ≥ 2.34 compat-symbol mechanism** (§1.3, Q-D) — mechanism confirmed on x86_64
  glibc 2.43; no ARM cross-toolchain or ARM sysroot ≥ 2.34 available in this environment.
* **`EVIOCSFF` and `BLKGETSIZE64` numeric ioctl values on 32-bit ARM** (§5.2) — their encodings
  depend on `sizeof(struct ff_effect)` / `sizeof(size_t)`, which I could not compile for ARM. I
  have deliberately left the numbers out rather than quote a 64-bit host's values. Both are
  mainline UAPI and unchanged 5.15 → 6.18, so they are not a hazard; they are simply not
  *evidenced* here.
* **Which physical I²C bus carries the ADV7513** (Q-E).
* **Whether every stock shared library is VFPv3** (§1.1) — only the `MiSTer` binary was checked.
* **The size of the community that uses symlinks on `/media/fat`** (Q-B) — not determinable from
  source.
