# On-device debug tooling — **temporary, isolated, revert-as-one-block**

> **Status: TEMPORARY — and one of its two reasons has now closed.** Everything
> described here was added on request to support two investigations: the field
> hard-hang (a board that died with no serial output and needed a power cycle)
> and the still-unmeasured PREEMPT_RT wakeup latency
> (`docs/rt-beta-kernel.md`). It is **not** stock parity, it is **not** part of
> the P2.1 package manifest (`docs/package-manifest.md`), and it is expected to
> be removed once both close. §5 is the exact revert recipe.
>
> **Update 2026-07-21 — the field hard-hang is RESOLVED and is no longer a
> reason to keep this block.** Root cause: the board was **auto-overclocking
> itself to 1.2 GHz on boot**. The forward-ported socfpga cpufreq driver
> (`linux-patches/0003-cpufreq-cyclone5-de10nano-overclock.patch`) was written
> against 5.15, where `CPUFREQ_BOOST_FREQ` kept the governor off the boost rows
> by default while `scaling_max_freq` stayed writable up to 1.2 GHz; **on 6.18
> the default `policy->max` resolves differently**, so the overclock became
> default-**on** rather than opt-in. Fixed in PR #24 (`3fb7f81`, merged
> `83ae09a`): a proper `->set_boost`, the 1000/1200 MHz rows flagged boost-only,
> and an 800 MHz default. The board is stable and serial console is clean.
>
> That class of defect is the thing worth remembering: the bug was not in the
> patch's logic but in a **silent semantic change to a kernel flag across the
> version gap we forward-ported over** — it applied cleanly, compiled, and
> behaved differently. Any other 5.15-era patch we carry can fail the same way.
>
> **What that leaves:** only the RT latency measurement (`rt-tests`) still
> justifies this block. Do not cite the field hang as an open risk, and do not
> resurrect the discarded theories (`PANIC_ON_OOPS` + `panic_timeout=0` "silent
> brick", marginal SD-card contact, USB hub brownout) — each was plausible, some
> were separately fixed, none was the cause.

---

## 1. What was added

Two edits, each wrapped in a matching banner pair so both can be found with one
grep and deleted with one editor motion. The banners are, verbatim:

```
# >>> DEBUG TOOLING — TEMPORARY, REMOVE AS ONE BLOCK <<<
...
# >>> END DEBUG TOOLING <<<
```

(the opening banner in `linux.config` additionally carries a
`(docs/debug-tooling.md)` suffix). Because the opening and closing banners are
*not* mirror images, always search for the substring both share — never for a
full banner line:

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

**The host half of the gdbserver flow is not built by this branch.** Only the
*target* symbols were requested, so there is no `arm-linux-gdb` in `output/host/`.
If you want one, that is a separate knob in the Toolchain menu:

```
BR2_PACKAGE_HOST_GDB=y          # cross-gdb for the build host
```

Add it inside the debug block if you need it. It is a *host* package (it builds
into `output/host/`, ships nothing to the device) and it still matches the
`^BR2_PACKAGE_` fingerprint filter, so §4's "no cache eviction" conclusion holds
for it too. It was left out only because the on-device debugger already covers
the core-file flow, which is the one that matters for a field report.

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
  path, which sets no packages. RT gets `CONFIG_COREDUMP` but not a perf of its
  own — the single shipped `perf` is the one from the main 6.18.39 build, and it
  is what runs under the RT kernel too. The `perf_event_attr` ABI is
  size-versioned and stable in both directions, so a 6.18 perf works against a
  7.2 kernel; it will simply not know about anything added after 6.18. Good
  enough for cyclictest-adjacent work, and worth remembering before blaming the
  RT kernel for a perf feature that is merely missing from the tool.

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

**What this perf can and cannot do**, taken from the actual build log rather than
predicted — Buildroot passed:

```
NO_LIBELF=1 NO_DWARF=1 NO_LIBUNWIND=1 NO_DEMANGLE=1
NO_LIBTRACEEVENT=1 NO_NEWT=1 NO_SLANG=1 NO_LIBAUDIT=1
NO_LIBPYTHON=1 NO_LIBPERL=1
```

and perf's own feature probe reported `libelf: OFF`, `libnuma: on`, `zlib: on`.
So:

* ✅ `perf stat`, `perf record`/`report` with kernel symbols from
  `/proc/kallsyms`, hardware counters, NUMA-aware helpers (`libnuma` is on only
  because rt-tests dragged in numactl — a free side effect);
* ❌ userspace symbol resolution from ELF binaries, DWARF callchains,
  `perf probe`, C++ symbol demangling, tracepoint decoding, the TUI.

Each ❌ traces to one omitted package listed in §3 — `elfutils` is the one that
buys back most of that list.

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

#### ⚠ `hwlatdetect` ships broken — known, upstream, and not worth fixing here

`rt-tests.mk` installs the Python `hwlatdetect` as an absolute symlink:

```
/usr/bin/hwlatdetect -> /usr/lib/python3.14/site-packages//hwlatdetect.py
```

but this image is built with Buildroot's default `BR2_PACKAGE_PYTHON3_PYC_ONLY=y`,
whose target-finalize step byte-compiles every `.py` and **deletes the source**.
Verified on the built tree: `site-packages/` contains `hwlatdetect.pyc` and no
`hwlatdetect.py`, so the symlink dangles and running `hwlatdetect` on the device
gives `No such file or directory`. Every other rt-tests binary is a normal C
program and is completely unaffected — this is `hwlatdetect` alone.

It is left broken deliberately:

* the workaround is one command, since CPython runs a `.pyc` directly —
  `python3 /usr/lib/python3.14/site-packages/hwlatdetect.pyc`;
* fixing it properly means either flipping `BR2_PACKAGE_PYTHON3_PY_PYC` (a
  *global* change to how every Python file in the image is installed, to rescue
  one script) or a post-build hook to repoint the symlink — both far outside a
  block whose whole value is being deletable in one motion;
* and `hwlatdetect` measures SMI-induced hardware latency, which is an x86
  concern. On a Cortex-A9 there are no SMIs. It is close to the least useful
  thing in the package here.

`cyclictest` — the tool that actually motivated enabling rt-tests — is a plain
ELF binary and works normally.

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
  **process's CWD** — and for the MiSTer binary that CWD is **`/`, not
  `/media/fat`**. It is launched from `/etc/inittab` as

  ```
  ::sysinit:/media/fat/MiSTer &
  ```

  and BusyBox `init` runs with `/` as its working directory; the child inherits
  it, and `Main_MiSTer` never calls `chdir()` (checked — there is no `chdir` in
  its sources). So an unconfigured core lands in the **root of the loop-mounted
  512 MiB rootfs**: it is wiped by the next reflash, it eats the free space
  `scripts/check-size-budget.sh` guards, and a core of a process this size can be
  tens of MB.

  That makes redirecting `core_pattern` close to mandatory in practice rather
  than a nicety. The device-side one-liner, no rebuild needed:

  ```sh
  echo '/media/fat/core.%e.%p' > /proc/sys/kernel/core_pattern
  ```

  `/media/fat` is the FAT data partition, so it survives a rootfs reflash — but
  FAT has no sparse files, so the core is written at full size.

Neither knob is changed by this branch: both are runtime state, and persisting
them is a `rootfs-overlay` sysctl/init change that deserves its own commit — and
its own entry in this document — rather than riding along in a package-selection
one.

---

## 3. What is deliberately **not** enabled

Each of these would make one of the tools meaningfully better, and each was left
off to keep the revertible delta minimal. They are listed here so the trade-off
is a decision on the record rather than an oversight:

| Symbol | What it would buy | Why it is off |
| --- | --- | --- |
| `BR2_PACKAGE_ELFUTILS` | perf gains libelf/DWARF: userspace symbol resolution from ELF binaries, `perf probe`, build-id handling. **Without it perf builds `NO_LIBELF=1 NO_DWARF=1`** (`linux-tool-perf.mk.in:94-96`) and can only symbolize the kernel via `/proc/kallsyms`. | Not requested; a sizeable new package. **This is the most likely thing to want next** — enable it inside the debug block if perf output turns out to be unreadable. |
| `BR2_PACKAGE_LIBUNWIND` | `strace -k` (stack trace per syscall) and perf DWARF callchains. | Not requested. Confirmed off in the build: perf got `NO_LIBUNWIND=1`. |
| `BR2_PACKAGE_BINUTILS` / `BR2_PACKAGE_LIBTRACEEVENT` | perf C++ symbol demangling (`NO_DEMANGLE=1` today) and tracepoint decoding (`NO_LIBTRACEEVENT=1` today). | Not requested. Noted because `MiSTer` is C++, so unmangled symbols in a profile are the first thing you will hit after `elfutils`. |
| `BR2_PACKAGE_LINUX_TOOLS_PERF_TUI` | perf's interactive TUI (`slang` is already `=y`, so this is nearly free). | Not requested. |
| `BR2_PACKAGE_GDB_PYTHON` / `_TUI` | Python scripting / split-window gdb on the device. | Not requested; on-device weight. |
| `BR2_PACKAGE_LINUX_TOOLS_RTLA` | osnoise / timerlat tracers, complementing cyclictest. | Not requested; pulls in `libtracefs`. |
| `CONFIG_DEBUG_INFO` in the kernel | DWARF for the kernel: `perf` annotation against kernel source, `crash`-style analysis. | Enormous, and the cost lands in the **rootfs**, not where you would guess: `zImage` is unaffected (it is objcopy'd from a stripped `vmlinux`), but every shipped `.ko` grows by roughly an order of magnitude, and those live in `linux.img` under the §6 free-space budget. |

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
* **SD-card installer: no hard cap hit.** `scripts/mk-sdcard.sh` ships
  `linux.img` gzipped and sizes the FAT partition from measured staged content
  (`du -sk --apparent-size`), so a fatter rootfs grows `sdcard.img` rather than
  overflowing anything. The installer stream-decompresses, so the `mem=511M`
  ceiling is not approached either. Nothing to do — noted because "we made the
  rootfs bigger" invites the question.
* **Attack surface.** A passwordless-root image that now also ships a full
  debugger and `perf`. That is acceptable for a debugging branch on a device with
  no meaningful secrets, and is a further reason this is temporary.

---

## 5. How to revert

1. Delete the whole `DEBUG TOOLING` block from
   `configs/mister_de10nano_defconfig` — opening banner (`>>> DEBUG TOOLING —
   TEMPORARY, REMOVE AS ONE BLOCK <<<`) through closing banner
   (`>>> END DEBUG TOOLING <<<`), inclusive. See §1 for why the two banner lines
   are not mirror images.
2. In `board/mister/de10nano/linux.config`, replace the corresponding block with
   the single original line:

   ```
   # CONFIG_COREDUMP is not set
   ```
3. Drop the **D10** row from `docs/kernel-config-deltas.md` §2 and put its intro
   line back to "Nine changes. Every one is deliberate; every one is cited."
   (D10 is the only temporary row in that table; it is flagged ⚠ so it cannot be
   mistaken for a permanent divergence.)
4. `docs/package-manifest.md`, **two places**:
   * drop the "⚠ This list is deliberately not identical to the live defconfig"
     note directly under the ready-to-paste `BR2_PACKAGE_*` list — once the block
     is gone the manifest and the defconfig agree again, which is what that note
     says;
   * in the §5 Drop-list table, restore the `vim, zsh, joe, mc, screen, gdb` row
     to listing `gdb` among the tools that "remain **off**", and delete the
     `gdb is no longer off` sentence appended to it.
5. Delete this file, and its entry in `README.md`.
6. Rebuild:

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

Verify with **both** greps. The first catches the two config blocks; the second
catches the documentation residue (the D10 row, the manifest note and the README
entry all name the *file*, not the banner, so the first grep alone would pass
with every one of them still in place):

```sh
grep -rn "DEBUG TOOLING"  configs/ board/          # must return nothing
grep -rn "debug-tooling"  docs/ README.md          # must return nothing
```

---

## 6. Measured cost (this branch, as built)

From a full cold `make all` of this branch, measured with the same
`scripts/check-size-budget.sh` gate `docs/size-budget.md` uses (floor: ≥ 15 %
free of the 512 MiB image).

**`linux.img`: 264 MiB used, 248 MiB free — 48.4 % free. PASS**, comfortably
above the 15 % floor.

Per binary, stripped, as installed:

| Binary | Size |
| --- | --- |
| `usr/bin/gdb` | 7.7 MiB |
| `usr/bin/strace` | 2.1 MiB |
| `usr/bin/perf` | 2.5 MiB |
| `usr/bin/gdbserver` | 524 KiB |
| `usr/bin/cyclictest` | 52 KiB |
| the other 14 rt-tests binaries | ~1 MiB combined |

**Total delta: +15 MiB of `output/target`.**

That figure needs one correction to be honest, and it is the reason the raw
before/after percentages do not simply subtract. The master build this was
compared against had **two** kernel module trees staged (`6.18.39` *and* the
`7.2.0-rc4` RT tree from a previous `make rt`, 3.2 MiB), and this branch has only
`6.18.39` — no `make rt` was run in this worktree. Comparing the images
head-on (50.5 % free vs 48.4 %) therefore understates the debug tooling by
crediting it with the absent RT tree. The +15 MiB above is `du -sm output/target`
on both sides with the RT tree subtracted from master's, which is the
apples-to-apples number.

### 6.1 How to re-measure

```sh
scripts/check-size-budget.sh output/images/linux.img
du -sh output/target/usr/bin/{gdb,gdbserver,strace,perf,cyclictest}
```

### 6.2 Build verification actually performed

A full cold `make all` of this branch, in a dedicated worktree, from `origin/master`:

* both stages built clean (the only `Error … (ignored)` lines in the log are
  Buildroot's usual e2fsprogs/glibc/nettle doc-target noise, present on master too);
* `board/mister/de10nano/post-image.sh`'s own `check-linux-img.sh` passed every
  assertion — 512 MiB, label `rootfs`, both pinned UUID/hash-seed, the exact
  14-feature stock-derived ext4 feature set, and ADR 0015's no-`ssh_host_*` check;
* `check-initramfs` passed;
* `scripts/check-kernel-defconfig-sync.sh` passes (23 shared symbols agree);
* the built kernel `.config` carries `CONFIG_COREDUMP=y` **and**
  `CONFIG_ELF_CORE=y` — confirming §2.5's claim that ELF_CORE arrives free —
  alongside `CONFIG_PERF_EVENTS=y`, `CONFIG_ARM_PMU=y`, `CONFIG_HW_PERF_EVENTS=y`;
* all six tools are present in `output/target` (see §6 for sizes), with the one
  documented exception of `hwlatdetect`'s dangling symlink (§2.4).

Not verified: **nothing here has been run on hardware.** The image builds and
passes every static assertion; whether gdb opens a useful core off a real board,
and what cyclictest actually reports under the RT kernel, are the next steps and
the reason this branch exists.

### 6.3 Reproducibility

`BR2_REPRODUCIBLE=y` is on and `.github/workflows/reproducibility.yml` builds the
tree twice and compares. None of the four tools is known to embed a build
timestamp or path, but **none has been through that workflow yet either** — if a
byte-identical rebuild starts failing on this branch, one of these packages is
the first place to look, not the last.

---

## 7. Related documents

* `docs/rt-beta-kernel.md` — the RT variant whose latency rt-tests exists to measure
* `docs/kernel-config-deltas.md` — every intentional kernel-config divergence; `CONFIG_COREDUMP` is recorded there too
* `docs/package-manifest.md` — the stock-parity package set this block is explicitly *not* part of
* `docs/ci.md` — toolchain fingerprint / cache-key behaviour referenced in §4
* `docs/size-budget.md` — the 15 % free-space floor §6 is measured against
