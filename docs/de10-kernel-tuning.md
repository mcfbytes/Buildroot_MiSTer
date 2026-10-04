# DE10-Nano kernel tuning: kernel-mode NEON and `-mtune=cortex-a9`

Two codegen/config changes to the DE10-Nano kernel. Neither changes the ISA the kernel
may use, and both are meant to be justified by an A/B measurement on hardware (§3), not
assumed.

## 1. `CONFIG_KERNEL_MODE_NEON=y` (`board/mister/de10nano/linux.config`)

Stock and our config both had it off. `multi_v7_defconfig` has it on.

**What it does on 6.18.** It lets kernel code call `kernel_neon_begin()`. On 32-bit ARM the
callers are crypto, CRC and RAID code (`arch/arm/crypto/`, `lib/crypto/arm/`,
`lib/crc/arm/`, `lib/raid6/neon*`, `arch/arm/include/asm/xor.h`). **Memory copies are not
among them:** `memcpy`/`copy_{to,from}_user` in `arch/arm/lib/` are integer `ldm`/`stm` code
and nothing in them uses NEON. So this option does not speed up generic memory transfer.

What turns on with no further config, because the code is already built and only checks for
NEON at runtime:

- **SHA-1, SHA-256, SHA-512, ChaCha20, Poly1305, Curve25519** in `lib/crypto/arm/`. This
  covers SMB2 signing (HMAC-SHA256), the SMB 3.1.1 preauth hash (SHA-512), and anything
  else that hashes inside the kernel.
- `CONFIG_CRC32_ARCH=y` is the only symbol `olddefconfig` adds. The Cortex-A9 has neither
  the ARMv8 CRC32 instructions nor PMULL, so it falls back to the generic code at runtime.

Two more drivers are enabled because the rig showed a clear win (§3.4). Neither turns on
by itself: `CRYPTO_AES_ARM_BS` (bit-sliced NEON AES for ECB/CBC/CTR/XTS) and
`CRYPTO_GHASH_ARM_CE` (despite the name, it also has a NEON `vmull.p8` GHASH that runs on
ARMv7). Together they speed up the GCM/CCM half of SMB3 encryption (`seal`) and of
software Wi-Fi CCMP/GCMP. CMAC (SMB3 signing) still uses scalar `aes-arm`, because the
bit-sliced driver provides only block modes and no single-block cipher.

Cost: when the kernel uses NEON it saves the user's VFP state lazily, and it runs with
softirqs off (or with preemption off on PREEMPT_RT, `arch/arm/vfp/vfpmodule.c`). Nothing
uses NEON outside the users above.

## 2. `-mtune=cortex-a9` (`external.mk`, `LINUX_CFLAGS`)

`arch/arm/Makefile` passes `-march=armv7-a` and no `-mtune`/`-mcpu`. Our toolchain is
configured `--with-cpu=cortex-a9`, but that default (and the Buildroot wrapper's
`-mcpu=cortex-a9`) is applied **only when no `-march`/`-mtune`/`-mcpu` is on the command
line** (`toolchain/toolchain-wrapper.c`, GCC's `OPTION_DEFAULT_SPECS`). So the kernel gets
GCC's tuning for bare `armv7-a`, and in GCC 15's `gcc/config/arm/arm-cpus.in` that is:

```
begin arch armv7-a
 tune for cortex-a53
```

That means the kernel is scheduled for an in-order ARMv8 core. Measured by building three
6.18 objects with their exact kernel command line plus each `-mtune`: the `.text` from the
default build is byte-different from `cortex-a9`, `cortex-a8` and `generic-armv7-a` builds.
`-mtune=cortex-a9` switches to the A9 cost tables and pipeline model.

- **`-mtune` changes scheduling and cost decisions only.** It never adds instructions the
  `-march` does not allow, so the binary stays valid on any ARMv7-A core.
- **`-march` chooses the instruction set**, so it decides where the binary can run.
- **`-mcpu=X` means `-march=<X's ISA>` plus `-mtune=X`.** It is not used here. When an
  explicit `-march` is also present, GCC keeps that `-march` and uses `-mcpu` only for
  tuning, so it adds nothing over `-mtune`. Measured on the same three objects:
  `-mcpu=cortex-a9` and `-march=armv7-a+mp+sec -mtune=cortex-a9` both produce `.text`
  byte-identical to `-mtune=cortex-a9`. The `-mcpu` build also prints
  `switch '-mcpu=cortex-a9' conflicts with switch '-march=armv7-a'` for every file. The A9's
  extra ISA bits (`mp` = `pldw`, `sec` = `smc`, fp16) gain nothing here. The compiler never
  emits the first two itself, and the kernel uses them in its own inline asm
  (`arch/arm/include/asm/processor.h`). fp16 does nothing in a soft-float kernel.
  Userspace already gets `-mcpu=cortex-a9` from the Buildroot toolchain wrapper.

`KCFLAGS` comes after the kernel's own flags. Buildroot passes it through
`LINUX_MAKE_FLAGS`, which `pkg-kernel-module.mk` (out-of-tree modules) and
`package/linux-rt` reuse, so all of them get the same tuning. The installer kernel
(`mister_installer_defconfig`, also `BR2_cortex_a9`) does too. The DE25 (`aarch64`) is
unaffected.

**Guarded in CI.** The "DE10 kernel tuning" section of `scripts/ci-tests.sh` asserts the three
symbols `=y` in both resolved configs (6.18 and RT), and `-mtune=cortex-a9` on a compile
line in both kernel trees.

## 3. A/B test plan

### 3.1 Builds (main clone, one commit, one toolchain)

| Build | Source | Test-only additions (not shipped) |
|---|---|---|
| **A** | `origin/master` | `CONFIG_CRYPTO_BENCHMARK=m` |
| **B** | this branch | `CONFIG_CRYPTO_BENCHMARK=m`, `CONFIG_CRYPTO_AES_ARM_BS=m`, `CONFIG_CRYPTO_GHASH_ARM_CE=m` |

Both builds use the same kernel version (6.18.55), toolchain and `output/`. The test-only
symbols go in through `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` in `output/.config`, so no
tracked file carries them. The out-of-tree kmod packages and `linux-rt` are rebuilt for
B, because Buildroot does not notice a `KCFLAGS` change. Artifacts: `linux.img` +
`zImage_dtb` for each.

### 3.2 Procedure on the rig

Back up `/media/fat/linux/{linux.img,zImage_dtb}`. Run **A → B → A**; the second A
catches drift such as a warming NAS or SD wear. Each boot gets the same bench script
with the cores idle at the menu (no FPGA core loaded). Report the median of 5 runs per
metric. Drop the page cache (`echo 3 > /proc/sys/vm/drop_caches`) before every I/O run.

### 3.3 Metrics, and which change each one isolates

| # | Metric | Command | Isolates |
|---|---|---|---|
| 1 | Hash throughput | `modprobe tcrypt mode=304 sec=1` (sha256), `303` (sha1), `318` (ghash) — dmesg | NEON lib code |
| 2 | AES modes, scalar vs bit-sliced | B only: `mode=500` with and without `aes-arm-bs` loaded | whether to ship `AES_ARM_BS` |
| 3 | AEAD | `mode=211` (gcm), `212` (ccm); B with and without `ghash-arm-ce` + `aes-arm-bs` | whether to ship them |
| 4 | SMB2 signed read | `mount -t cifs -o vers=2.1,sign`, `dd` 256 MiB to `/dev/null` | NEON (HMAC-SHA256) + tune |
| 5 | SMB3 signed / sealed read | `vers=3.1.1,sign` then `,seal`, same `dd` | tune (+ AES/GCM if shipped) |
| 6 | Scheduler / IPC | `perf bench sched pipe -l 200000`, `perf bench sched messaging -l 200` | tune |
| 7 | Network stack | `iperf3 -c <host> -t 20` and `-R` | tune |
| 8 | exFAT + block I/O | `dd` 256 MiB from SD, `time find /media/fat -type f | wc -l` (cold) | tune |
| 9 | Size | `zImage_dtb` bytes, `size vmlinux` | both |

None of 6–8 calls NEON code, so a difference there is the `-mtune` effect. 1–3 are pure
NEON. 4–5 mix both and are the ones a user would notice.

**Ship rule:** keep each change unless it measurably loses. A tie keeps both, because both
match what the hardware is. `AES_ARM_BS`/`GHASH_ARM_CE` are added only if 2–3 show a
clear win. They go in as `=y`. As modules they would also work: both declare
`crypto-gcm(aes)`/`crypto-ctr(aes)`/`crypto-ghash` aliases, and the crypto API
`request_module()`s them the first time an algorithm is instantiated, which is how round B
used them. But an algorithm instantiated before the rootfs is mounted would bind to the
scalar driver for good.

### 3.4 Results (2026-10-03, rig 192.168.0.160, 6.18.55, menu core idle)

Medians of 5 runs; round order A1 → B → A2. A1 and A2 agree on every metric, so the B
deltas are not drift. In round B the crypto API loaded the two test-only modules
(`aes-arm-bs`, `ghash-arm-ce`) on demand. "B, no drivers" is the same B boot after
unloading them and setting `kernel.modules_disabled=1`, which is the PR as first written.

| Metric | A1 | A2 | B | B, no drivers | B vs A |
|---|---|---|---|---|---|
| CIFS 3.1.1 `seal`, 256 MiB read | 26.88 s | 26.73 s | **17.37 s** | 26.85 s | **+54%** (drivers only) |
| CIFS 2.1 `sign`, 256 MiB read | 14.86 s | 14.78 s | **12.28 s** | 12.41 s | **+20%** (NEON SHA-256) |
| CIFS 3.1.1 `sign`, 256 MiB read | 19.23 s | 19.23 s | 18.97 s | — | +1% (AES-CMAC stays scalar) |
| CIFS 3.1.1 guest, 256 MiB read | 4.73 s | 4.78 s | 4.69 s | — | +1% |
| `iperf3` into rig | 505 Mbit/s | 506 Mbit/s | 515 Mbit/s | — | +2% |
| `iperf3` out of rig | 430 Mbit/s | 430 Mbit/s | 437 Mbit/s | — | +2% |
| `perf bench sched messaging` | 5.69 s | 5.62 s | 5.59 s | — | +1% |
| `perf bench sched pipe` | 15.5 µs | 17.9 µs | 16.2 µs | — | noise (A1/A2 differ by 15%) |
| SD read, 256 MiB | 11.30 s | 11.31 s | 11.32 s | — | 0 |
| exFAT `find` (34k files, cold) | 13.53 s | 13.54 s | 13.54 s | — | 0 |

`tcrypt`, 1-second samples at the largest block size (single runs, about ±10%):

| Algorithm | A1 | A2 | B |
|---|---|---|---|
| sha1 (`sha1-lib`) | 58 MB/s | 52 MB/s | **98 MB/s** |
| sha256 (`sha256-lib`) | 36 MB/s | 32 MB/s | **51 MB/s** |
| ghash: generic → `ghash-ce` (NEON p8) | 35 MB/s | 35 MB/s | **80 MB/s** |
| ctr(aes): `aes-arm` → `ctr-aes-neonbs` | 14–16 MB/s | 14–15 MB/s | **24–27 MB/s** |
| gcm(aes) | 10–12 MB/s | 10–12 MB/s | **17–20 MB/s** |
| ccm(aes) (CBC-MAC half stays scalar) | 10 MB/s | 9–10 MB/s | 12–13 MB/s |

**Disposition:**
- **Ship `KERNEL_MODE_NEON`.** SHA-1/SHA-256 are +40–80%, which shows up as +20% on
  SMB2-signed reads.
- **Ship `AES_ARM_BS` and `GHASH_ARM_CE`.** On this A9, bit-sliced AES beats the scalar
  driver, and they carry the whole +54% on SMB3 encrypted reads.
- **Ship `-mtune=cortex-a9`.** There is no regression anywhere, and B is ahead of both A
  rounds on network throughput (about +2%). That gain is small but holds in every run.
- **What does not change:** SMB 3.1.1 *signed* mounts, which Windows 11 24H2 now requires by
  default. The CIFS client signs those with AES-CMAC, a single-block cipher that stays on
  scalar `aes-arm`. AES-GMAC signing, which the GHASH driver would accelerate, was not
  negotiated.

The bench is the procedure in §3.2–3.3. It is driven by a throwaway script that is not
in the tree.
