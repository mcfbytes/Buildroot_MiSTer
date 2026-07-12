# ADR 0001 — Toolchain: Buildroot-internal, glibc, armv7-a/Cortex-A9/NEON/EABIhf

**Status:** Proposed (2026-07-12) — derived during P1.2 implementation; **not yet
reviewed by a human.** Unlike ADRs 0010–0014, which record decisions @mcfbytes
actually made, this one was reached by working the trade-off in the task text.
It is reversible (see "Left open, not closed" below) and nothing downstream is
blocked on ratifying it — but do not read the header as a human sign-off.
**Impact:** `configs/mister_de10nano_defconfig` (P1.2); every subsequent Buildroot
package build (P2.1+); the kernel toolchain choice is separate (P1.3 uses the
same triplet against a kernel.org tarball, not Buildroot's `BR2_LINUX_KERNEL`).

## Decision

1. **C library: glibc**, via **Buildroot's internal toolchain backend**
   (`BR2_TOOLCHAIN_BUILDROOT_GLIBC`, the default C library for that backend) —
   **not** a Bootlin external toolchain, and not musl/uClibc-ng.
2. **Arch/ABI:** `BR2_arm` + `BR2_cortex_a9` + `BR2_ARM_ENABLE_NEON` +
   `BR2_ARM_ENABLE_VFP` + `BR2_ARM_FPU_NEON` (⇒ gcc `-mfpu=neon`, VFPv3 with the
   32-register file NEON requires). EABIhf follows as Buildroot's own default
   once a CPU with an FPU is selected — no explicit line needed.
3. **Kernel headers: `BR2_KERNEL_HEADERS_6_18`**, matching the 6.18.y target
   kernel (P1.3), pinned explicitly since this defconfig builds no kernel of
   its own.

## Rationale

### Why glibc, not musl or uClibc-ng

Not a close call. `docs/abi-contract.md` §1.3: *"musl instead of glibc — Fatal
and immediate. No symbol versioning, no `GLIBC_*` version nodes, no
`libpthread.so.0` file, different `ld-linux` name. The binary will not even
start. Never an option."* PLAN.md §3 lists glibc as the only acceptable choice.
This is also explicitly a **non-goal to reconsider** per PLAN's own framing —
recorded here only so a future contributor sees the reasoning rather than a
bare Kconfig line.

### Why the Buildroot-internal toolchain over a Bootlin external toolchain

Evaluated on the four axes the task asks for, using this Buildroot tree
(2026.02.3, `work/buildroot`) as the source of truth for what each path
actually offers:

| Axis | Buildroot-internal | Bootlin external (`armv7-eabihf--glibc--{stable,bleeding-edge}-2025.08-1`) |
|---|---|---|
| **Build time** | Slower on a clean build — bootstraps binutils, a first-stage gcc, glibc headers/startfiles, then a second-stage gcc before any target package can compile. Paid once per distinct toolchain-config hash; Buildroot caches the result under `output/host` and does not repeat it on every `make`. | Faster — a prebuilt, hash-pinned `.tar.xz` is downloaded and extracted; no compiler bootstrap. |
| **Reproducibility** | Every component (binutils, gcc, glibc) is built from an upstream source tarball that Buildroot's own package `.hash` files pin and verify — the same "verify against a signed/published hash" discipline this repo's top-level `Makefile` already applies to the Buildroot tarball itself (P1.1). Some dependence on the *host's* gcc/binutils to bootstrap the cross-compiler, which is Buildroot's own long-standing, widely-exercised path. | Also hash-pinned in-tree (`toolchain/toolchain-external/toolchain-external-bootlin/toolchain-external-bootlin.hash:65-66`), and removes host-toolchain variance since the cross-compiler itself is prebuilt. Trades that for trusting a third-party prebuilt binary blob (Bootlin) rather than source Buildroot itself builds and verifies. |
| **glibc version control** | Locked to exactly what this pinned Buildroot release packages: `GLIBC_VERSION = 2.42-67-g4ebd33dd77e…` (`work/buildroot/package/glibc/glibc.mk:10`) — a single upstream git snapshot, one axis to track (bump Buildroot, glibc moves with it; already Renovate-tracked, P4.6). | Pinned independently by Bootlin's own `2025.08-1` release cadence — a **second** upstream project with its own version/release schedule to track and hash-verify, decoupled from the Buildroot version bump. Exact bundled glibc point version not independently verified here (not downloaded, since this path was not selected) — but Bootlin's toolchains are a reputable, actively maintained source and were confirmed via `Config.in.options` (`work/buildroot/toolchain/toolchain-external/toolchain-external-bootlin/Config.in.options:818-868`) to require GCC ≥ 14/15, i.e. a 2024+ toolchain generation — well past glibc 2.34. |
| **The 2.34 libpthread/librt-merge hazard** | Buildroot's glibc package installs the compat stub `.so` files (`libpthread.so.0`, `librt.so.1`, `libdl.so.2`) **unconditionally**, regardless of toolchain backend — `docs/abi-contract.md` cites `glibc.mk:188` for exactly this. Not a discriminator between the two paths; both resolve the hazard identically **provided** the built rootfs is actually checked (this task's acceptance item 3; P2.2 owns the full assertion). | Same — the hazard is a property of *which glibc version* ships, not of *how the toolchain got here*. Both paths ship glibc well past 2.34. |

**Decision driver, beyond the table:** this repository already has a strong,
explicit house preference for "build/verify from pinned upstream source over
trusting a third-party prebuilt artifact" — see the top-level `Makefile`'s
extended commentary on why `BUILDROOT_SHA256` must come from Buildroot's own
GPG-signed release manifest and never from `sha256sum`-ing a tarball you just
downloaded. Choosing the Bootlin path would introduce a *second*, independently
versioned upstream binary-blob dependency into a project whose stated posture
(TASKS.md standing rule 1: *"No binaries in git. Ever."*, and by clear
extension, minimize trusted binary inputs generally) already leans hard the
other way. The internal toolchain keeps every bit that ends up on the target
traceable to a source tarball Buildroot itself fetched and hash-verified.

The build-time cost is real but bounded and already budgeted: the task's own
acceptance text warns the full `make` "may take 20-60 min. That is expected" —
a window that already assumes a toolchain bootstrap, not just a rootfs
assembly. It is a one-time-per-config cost, not a per-build tax.

**Left open, not closed:** because both paths land on glibc well past 2.34,
switching to a Bootlin toolchain later would not be an ABI break. If build-time
iteration speed becomes a real bottleneck for the CI matrix (P4.1), revisit —
but that is a build-infrastructure optimization, not a project requirement,
and it is not this task's job to pre-empt it.

### Why `BR2_ARM_FPU_NEON`, not `BR2_ARM_FPU_VFPV3D16` or `BR2_ARM_FPU_NEON_VFPV4`

The stock binary's own `readelf -A` (`docs/abi-contract.md:71-90`, reproduced
in PLAN.md §3) shows both `Tag_FP_arch: VFPv3` **and**
`Tag_Advanced_SIMD_arch: NEONv1` set together. Buildroot's Cortex-A9 support
(`work/buildroot/arch/Config.in.arm:204-210`) only *may* have NEON and *may*
have VFPv3 (`select BR2_ARM_CPU_MAYBE_HAS_NEON` / `_MAYBE_HAS_VFPV3`) — so both
`BR2_ARM_ENABLE_NEON` and `BR2_ARM_ENABLE_VFP` must be set explicitly, or
Buildroot's default-FPU-strategy choice falls back to plain `BR2_ARM_FPU_VFPV2`
(`arch/Config.in.arm:619-621`), which is NEON-less and wrong.

Among the FPU strategies Cortex-A9 can reach, `BR2_ARM_FPU_NEON` is the one
Buildroot maps to `-mfpu=neon` (`arch/Config.in.arm:943`), which is VFPv3 with
the 32-register file NEON architecturally requires — reproducing the stock
binary's tags exactly. `BR2_ARM_FPU_VFPV3D16` alone would drop NEON entirely
(wrong — NEON is a hard MUST per T3). `BR2_ARM_FPU_NEON_VFPV4` would target
VFPv4, which the Cortex-A9 does not implement — `docs/abi-contract.md:101-103`
calls this out explicitly as *forward*-compatible only, i.e. it would produce
libraries the CPU cannot execute. `BR2_ARM_FPU_NEON` is the only option that is
both correct and matches silicon.

This reference Buildroot tree's own `configs/terasic_de10nano_cyclone5_defconfig`
(`work/buildroot/configs/terasic_de10nano_cyclone5_defconfig:1-5`) confirms the
same arch/FPU triple independently — `BR2_arm` / `BR2_cortex_a9` /
`BR2_ARM_ENABLE_NEON` / `BR2_ARM_ENABLE_VFP` / `BR2_ARM_FPU_NEON` — for the
same silicon family (Cyclone V HPS). It was **not** blindly inherited: it also
pins a `5.11`-era `altera-opensource/linux-socfpga` kernel, a barebox
bootloader, and an EXT2 rootfs/genimage flow — none of which apply here. We
control the kernel (P1.3) and boot chain (§8) ourselves and diverge
deliberately; only the arch/FPU stanza was cross-checked and reused.

## Consequences

- Every clean `work/` (a fresh checkout, or a CI cache miss) pays the
  toolchain-bootstrap time cost. P4.1 (CI) should cache `output/host` across
  runs to avoid rebuilding the cross-compiler on every job — noted here so
  that task doesn't have to rediscover it.
- A glibc version bump is not an independent lever — it moves only when
  `BUILDROOT_VERSION` in the top-level `Makefile` is bumped (already
  Renovate-tracked per P4.6). This is treated as a feature (fewer independently
  moving upstream versions to reason about), not a limitation.
- The kernel headers version (`BR2_KERNEL_HEADERS_6_18`) must be kept in sync
  by hand if P1.3's kernel target version ever changes — there is no automatic
  link between the two, since this defconfig does not build the kernel.
- **libstdc++ is a toolchain option, not a package.** `BR2_TOOLCHAIN_BUILDROOT_CXX`
  is set here in P1.2 rather than deferred to P2.1's package set, because
  `docs/abi-contract.md` §2.2 rows L5/L6 list `libstdc++.so.6` and
  `libgcc_s.so.1` as *toolchain*-provided, and T8 makes `GLIBCXX_3.4.21` +
  `CXXABI_1.3.9` a MUST. Main_MiSTer is C++; a toolchain without it is not a
  candidate. P2.1 still owns the ten actual *packages* (L7-L12).
- **Changing any toolchain option requires `make clean`.** Buildroot will not
  rebuild an already-built toolchain on a config change — it silently reuses
  the existing package stamps and produces a rootfs that does not match the
  defconfig. This was hit for real while doing P1.2 (adding
  `BR2_TOOLCHAIN_BUILDROOT_CXX` to an incremental build exited 0 and produced
  no `libstdc++` and no `g++`). Any future toolchain change must be validated
  from a clean `output/`.

## Verification (the P1.2 acceptance run — actually executed, not asserted)

Built from a clean `output/` with `make mister_de10nano_defconfig && make -j32`
(exit 0), producing `output/images/rootfs.tar` (5,785,600 B, 380 entries).
Toolchain tuple: `arm-buildroot-linux-gnueabihf`, **GCC 14.3.0**, **glibc 2.42**.

| Check | Requirement | Result |
|---|---|---|
| `readelf -h` on target `/bin/busybox` | T1: ELF32, little-endian, ARM, hard-float | `ELF32` / `2's complement, little endian` / `ARM` / `Flags: 0x5000400, Version5 EABI, hard-float ABI` — **byte-identical flags to the stock binary** (`abi-contract.md:63`) |
| `readelf -A` on same | T2/T3/T4 | `Tag_CPU_name: "7-A"`, `Tag_CPU_arch: v7`, `Tag_CPU_arch_profile: Application`, `Tag_FP_arch: VFPv3`, `Tag_Advanced_SIMD_arch: NEONv1`, `Tag_ABI_VFP_args: VFP registers` — **exact match to `abi-contract.md:71-90`** |
| glibc version | T7: floor `GLIBC_2.28` | **2.42** — clears the floor by a wide margin |
| Dynamic loader | T5: `/lib/ld-linux-armhf.so.3` | present |
| **2.34 merge hazard, leg 1** | stub *files* exist | `libpthread.so.0` (7,548 B), `librt.so.1` (5,424 B), `libdl.so.2` (5,372 B) — sizes confirm they are placeholder stubs |
| **leg 2** | stubs define version node `GLIBC_2.4` | both `libpthread.so.0` and `librt.so.1` define `GLIBC_2.4` |
| **leg 3** | `libc.so.6` exports the 5 symbols as compat `@GLIBC_2.4` | all five present: `pthread_create@GLIBC_2.4`, `pthread_join@GLIBC_2.4`, `pthread_attr_setaffinity_np@GLIBC_2.4`, `shm_open@GLIBC_2.4`, `shm_unlink@GLIBC_2.4` |
| T8 | `GLIBCXX_3.4.21` + `CXXABI_1.3.9` | both present in `libstdc++.so.6.0.33` |
| T9 | `GCC_3.5` in `libgcc_s.so.1` | present |
| hello-world under `qemu-arm` | runs | C (pthread + shm) and C++ (`std::string` `__cxx11` ABI + `std::thread`) both compiled with the produced toolchain and ran to exit 0 under `qemu-arm -L output/target` |

> **This closes a caveat `docs/abi-contract.md` §1.3 left open.** That section
> verified the stub/compat mechanism only on the *workstation's x86_64 glibc
> 2.43* (baseline `GLIBC_2.2.5`) and explicitly recorded: *"on ARM the baseline
> is `GLIBC_2.4`, and I could not check an ARM glibc ≥ 2.34 directly (no ARM
> cross-toolchain and no ARM sysroot in `work/`)… P2.2 must re-verify it
> against the real Buildroot ARM sysroot."* **That ARM sysroot now exists, and
> all three legs hold on it.** P2.2 should still assert this in CI against the
> real `MiSTer` binary (this run proves the mechanism, not the binary), but the
> "highest-value assertion in the whole contract" is no longer resting on an
> x86_64 analogy.

**Not verified by this task** (deliberately out of scope, flagged so nobody
assumes otherwise): the ten `DT_NEEDED` *packages* L7-L12 (zlib, bzip2, libpng,
freetype, imlib2, bluez) are not in this defconfig, so the full 15-line
`LD_TRACE_LOADED_OBJECTS` resolution of `abi-contract.md` §2.4 was **not**
reproduced — that is P2.1/P2.2. In particular the two flagged hazards
(`libbz2.so.1.0`'s unusual SONAME, and imlib2's `dlopen`ed loader plugins)
remain open. Nothing here forecloses them.
