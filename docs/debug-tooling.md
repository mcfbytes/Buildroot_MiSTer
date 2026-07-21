# On-device debug tooling — **temporary, isolated, revert-as-one-block**

> **Status: TEMPORARY.** Everything described here was added on request to
> support two open investigations — the field hard-hang (a board that dies with
> no serial output and needs a power cycle) and the still-unmeasured PREEMPT_RT
> wakeup latency (`docs/rt-beta-kernel.md`). It is **not** stock parity, it is
> **not** part of the P2.1 package manifest (`docs/package-manifest.md`), and it
> is expected to be removed once those close. §5 is the exact revert recipe.

---

## 1. What was added

Two edits, each wrapped in a matching `>>> DEBUG TOOLING <<<` / `>>> END DEBUG
TOOLING <<<` banner pair so both can be found with one grep and deleted with one
editor motion:

```
$ grep -rn "DEBUG TOOLING" configs/ board/
```

| Where | What |
| --- | --- |
| `configs/mister_de10nano_defconfig` | `BR2_PACKAGE_GDB` + `_GDB_SERVER` + `_GDB_DEBUGGER`, `BR2_PACKAGE_STRACE`, `BR2_PACKAGE_LINUX_TOOLS_PERF` (+ `_NEEDS_HOST_PYTHON3`), `BR2_PACKAGE_RT_TESTS` |
| `board/mister/de10nano/linux.config` | `CONFIG_COREDUMP=y` (was `# CONFIG_COREDUMP is not set`) |

Nothing else in the tree references any of it.

### 1.1 Versions this resolves to

| Tool | Version | Source |
| --- | --- | --- |
| gdb / gdbserver | 15.2 | `BR2_GDB_VERSION` default for a GCC >= 9 toolchain (`package/gdb/Config.in.host:77`) |
| strace | 7.0 | `package/strace/strace.mk` |
| perf | 6.18.39 | built from **our own kernel's** `tools/perf`, not a standalone release |
| rt-tests | 2.8 | `package/rt-tests/rt-tests.mk` |
| numactl | 2.0.19 | pulled in by rt-tests (`select`) |
| mpfr | 4.2.2 | pulled in by the full gdb (`select`) |

`numactl` and `mpfr` are **transitive** and are deliberately *not* listed in the
defconfig block — listing them would leave them enabled after the block is
deleted, which is exactly the residue this whole arrangement exists to avoid.

---

## 2. Why each one, and the non-obvious bits

### 2.1 gdb — server *and* full debugger

Both halves were asked for explicitly, and they serve different flows:

* **gdbserver** — the normal embedded flow: `gdbserver :2345 ./MiSTer` on the
  device, a host cross-gdb attaching over TCP.
* **the full on-device debugger** — opens a core file on the device itself with
  no host toolchain present. That is the realistic flow when a beta tester
  reports a hard hang: they can be walked through `gdb /media/fat/MiSTer core`
  over SSH without installing anything.

**The one real trap here.** `package/gdb/Config.in` has:

```kconfig
select BR2_PACKAGE_GDB_SERVER if \
    (!BR2_PACKAGE_GDB_DEBUGGER && !BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY)
```

so `BR2_PACKAGE_GDB=y` alone implies gdbserver — but that `select` **stops
firing the moment `GDB_DEBUGGER=y`**. Enabling the full debugger without also
listing `BR2_PACKAGE_GDB_SERVER=y` explicitly would therefore silently *remove*
gdbserver from the image. Both lines are present and neither is redundant.

`BR2_PACKAGE_GDB_DEBUGGER` requires `BR2_USE_WCHAR`, already satisfied here
(glibc + `BR2_ENABLE_LOCALE=y`). Its `select`s are GMP / MPFR / readline / zlib;
only MPFR is new.

`GDB_TUI` and `GDB_PYTHON` are **not** enabled — neither was requested and both
only add on-device weight.

### 2.2 strace

No dependencies at all on this toolchain. Nothing subtle.

### 2.3 perf — built from our own kernel tree

`BR2_PACKAGE_LINUX_TOOLS_PERF` selects the `BR2_PACKAGE_LINUX_TOOLS` meta-symbol,
which is **part of the `linux` package**, not a standalone one. Consequences:

* perf is rebuilt whenever the kernel is, and always matches the running kernel's
  `tools/perf` — no version skew;
* it is *not* built by the kernel-only `mister_kernel_defconfig` / `make rt`
  path, which sets no packages. RT gets `CONFIG_COREDUMP` but not perf; the
  shipped perf comes from the main 6.18.39 build and is what runs under either
  kernel.

**`_NEEDS_HOST_PYTHON3` is mandatory here, not cosmetic.** Since ~6.0 perf
generates `pmu-events.c` at build time by running
`tools/perf/pmu-events/jevents.py`, and 6.18.39 still ships that script (verified
present in the unpacked tree). Without the symbol Buildroot never appends
`host-python3` to `PERF_DEPENDENCIES`
(`package/linux-tools/linux-tool-perf.mk.in:11-12`) and the build is left at the
mercy of whatever `python3` the host happens to have.

**The kernel side needs nothing from us.**
`linux-tool-perf.mk.in:199` force-enables `CONFIG_PERF_EVENTS` at kconfig-fixup
time, and in this tree that fixup is already a no-op — `CONFIG_PERF_EVENTS=y`,
`CONFIG_ARM_PMU=y` and `CONFIG_HW_PERF_EVENTS=y` all resolve on by kconfig
default and are live in the built `.config` today. They are absent from
`linux.config` only because `savedefconfig` omits defaults.

**Hardware counters really work**, they are not silently downgraded to software
events: `socfpga.dtsi` carries

```dts
pmu: pmu@ff111000 {
        compatible = "arm,cortex-a9-pmu";
        interrupts = <0 176 4>, <0 177 4>;
        interrupt-affinity = <&cpu0>, <&cpu1>;
        ...
};
```

i.e. a Cortex-A9 PMU node with a per-CPU interrupt for each of the two cores, so
`perf stat` returns real cycle/instruction counts.

### 2.4 rt-tests

`cyclictest` and friends — the standard PREEMPT_RT latency harness, and the thing
that finally answers the open TODO in `docs/rt-beta-kernel.md`: the RT kernel
boots on hardware, but its wakeup latency has never been measured. `select`s
`numactl`. `hwlatdetect` is a Python script and installs because
`BR2_PACKAGE_PYTHON3=y`.

Note `BR2_PACKAGE_LINUX_TOOLS_RTLA` (osnoise/timerlat tracers) is **not**
enabled — not requested, and it would pull in `libtracefs`.

### 2.5 `CONFIG_COREDUMP`

**A deliberate divergence from stock.** Stock's own config has
`# CONFIG_COREDUMP is not set` (`docs/stock-inventory/stock-linux.config:721`),
and so did ours until now. Without it the kernel cannot dump core at all, so a
crashing `MiSTer` binary leaves nothing for gdb to open — which would make
shipping gdb close to pointless.

`CONFIG_ELF_CORE` (`init/Kconfig`, `depends on COREDUMP`, `default y`) is what
actually writes the ELF core file. It turns on for free and **must not** get a
line of its own: it is invisible to kconfig while `COREDUMP` is off, so a
`savedefconfig` round-trip would drop any line added for it.

`linux.config` is shared with `configs/mister_kernel_defconfig`, so the RT/beta
kernel gets coredumps too. That is wanted — RT is the variant under active
on-hardware investigation.

#### Using it on the device

`CONFIG_COREDUMP=y` only makes cores *possible*; nothing here changes the
defaults, so out of the box:

* `ulimit -c` is `0` — raise it (`ulimit -c unlimited`) in the shell or init
  script that launches the process you want to dump;
* `/proc/sys/kernel/core_pattern` is `core`, i.e. a file named `core` in the
  process's CWD. For `MiSTer_Main` that is `/media/fat`, which is the FAT data
  partition and survives a rootfs reflash — convenient, but note FAT has no
  sparse files and a core of the MiSTer process is tens of MB.

Neither is changed by this branch. If a future investigation wants cores
collected automatically, that is a `rootfs-overlay` sysctl change and should get
its own commit — and its own entry in this document.

---

## 3. What is deliberately **not** enabled

Each of these would make one of the tools meaningfully better, and each was left
off to keep the revertible delta minimal. They are listed here so the trade-off
is a decision on the record rather than an oversight:

| Symbol | What it would buy | Why it is off |
| --- | --- | --- |
| `BR2_PACKAGE_ELFUTILS` | perf gains libelf/DWARF: userspace symbol resolution from ELF binaries, `perf probe`, build-id handling. **Without it perf builds `NO_LIBELF=1 NO_DWARF=1`** (`linux-tool-perf.mk.in:94-96`) and can only symbolize the kernel via `/proc/kallsyms`. | Not requested; a sizeable new package. **This is the most likely thing to want next** — enable it inside the debug block if perf output turns out to be unreadable. |
| `BR2_PACKAGE_LIBUNWIND` | `strace -k` (stack trace per syscall) and perf DWARF callchains. | Not requested. |
| `BR2_PACKAGE_LINUX_TOOLS_PERF_TUI` | perf's interactive TUI (`slang` is already `=y`, so this is nearly free). | Not requested. |
| `BR2_PACKAGE_GDB_PYTHON` / `_TUI` | Python scripting / split-window gdb on the device. | Not requested; on-device weight. |
| `BR2_PACKAGE_LINUX_TOOLS_RTLA` | osnoise / timerlat tracers, complementing cyclictest. | Not requested; pulls in `libtracefs`. |
| `CONFIG_DEBUG_INFO` in the kernel | kernel-symbol-accurate profiling and `crash`-style analysis. | Enormous (`vmlinux` grows by an order of magnitude) and the kernel is size-constrained by the `mem=511M` cap and the FAT partition. |

---

## 4. Cost and blast radius

* **CI cross-toolchain cache: unaffected.** The whole defconfig block is
  `BR2_PACKAGE_*` lines, and `.github/actions/buildroot-build`'s toolchain
  fingerprint filters `^($|BR2_PACKAGE_|BR2_LINUX_KERNEL)` out before hashing
  (`docs/ci.md#toolchain-fingerprint`). Adding these therefore does **not** evict
  `br-host-*` and does **not** force a cold ~3 h rebuild. `linux.config` is not
  part of that fingerprint either.
* **`scripts/check-kernel-defconfig-sync.sh`: unaffected.** It compares only
  symbols *defined in both* defconfigs and the `BR2_arm` / `BR2_ARM_` /
  `BR2_cortex` / `BR2_KERNEL_HEADERS` / `BR2_TOOLCHAIN_BUILDROOT_` choice
  families. Package symbols are one-sided by design and exempt.
* **Image size.** Measured, not estimated — see §6.
* **Attack surface.** A passwordless-root image that now also ships a full
  debugger and `perf`. That is acceptable for a debugging branch on a device with
  no meaningful secrets, and is a further reason this is temporary.

---

## 5. How to revert

1. Delete the `>>> DEBUG TOOLING <<<` … `>>> END DEBUG TOOLING <<<` block from
   `configs/mister_de10nano_defconfig`.
2. In `board/mister/de10nano/linux.config`, replace the corresponding block with
   the single original line:

   ```
   # CONFIG_COREDUMP is not set
   ```
3. Delete this file, and its entry in `README.md`.
4. Rebuild:

   ```sh
   make mister_de10nano_defconfig    # re-resolve output/.config from the defconfig
   make all
   ```

   A kernel-config change forces a kernel rebuild on its own. The package
   removals do not need a `make clean`: Buildroot leaves stale files in
   `output/target/`, but the rootfs image is regenerated from it and
   `target-finalize` re-runs — if you want to be certain nothing survives,
   `rm -rf output/target && make all` is the cheap belt-and-braces version (it
   rebuilds no packages, only re-installs them).

Verify with:

```sh
grep -rn "DEBUG TOOLING" configs/ board/ docs/    # must return nothing
```

---

## 6. Measured cost (this branch, as built)

<!-- filled in from the verification build; see the branch's build log -->

| Item | Before | After | Delta |
| --- | --- | --- | --- |
| `linux.img` free space | _(pending)_ | _(pending)_ | _(pending)_ |

---

## 7. Related documents

* `docs/rt-beta-kernel.md` — the RT variant whose latency rt-tests exists to measure
* `docs/kernel-config-deltas.md` — every intentional kernel-config divergence; `CONFIG_COREDUMP` is recorded there too
* `docs/package-manifest.md` — the stock-parity package set this block is explicitly *not* part of
* `docs/ci.md` — toolchain fingerprint / cache-key behaviour referenced in §4
* `docs/size-budget.md` — the 15 % free-space floor §6 is measured against
