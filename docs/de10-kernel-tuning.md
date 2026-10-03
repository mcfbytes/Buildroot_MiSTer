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

Separate opt-in drivers that are **not** enabled here. Each is a measurement question
(§3.3), because the faster NEON path is not guaranteed on the A9's 64-bit NEON:
`CRYPTO_AES_ARM_BS` (bit-sliced AES; ECB/CBC/CTR/XTS) and `CRYPTO_GHASH_ARM_CE` (whose
NEON `vmull.p8` GHASH fallback runs on v7). Together they are the GCM/CCM half of SMB3
encryption (`seal`) and of software Wi-Fi CCMP/GCMP.

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
match what the hardware is. `AES_ARM_BS`/`GHASH_ARM_CE` are added (as `=y`, because a
module the crypto API never asks for is never loaded) only if 2–3 show a clear win.

### 3.4 Results

_Not yet run._
