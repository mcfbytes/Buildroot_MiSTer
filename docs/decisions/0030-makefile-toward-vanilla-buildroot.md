# ADR 0030 — Shrinking the wrapper Makefile toward vanilla Buildroot

**Status:** Accepted in direction (2026-09-11) — the owner accepted Phases B and C, the Makefile
and CI rewrite, the Kconfig profile package in place of Buildroot-config fragments (§5.7), and
Option G subject to its image-identity proof. **Landed:** Phases B and C (PR #166), then the
profiles + committed defconfigs + thin Makefile (branch `feat/vanilla-buildroot-defconfigs`);
each verified resolved-config-identical and `ci-tests.sh` green. Open: rig boot of both kernels,
Option G.
**Supersedes nothing.** Would amend [ADR 0002](0002-initramfs.md) (Phase B) and
[ADR 0021](0021-rt-kernel-first-class-ci.md) (Phase C) if those phases are accepted.
**Constraint:** the shipped artifacts stay byte-for-byte what they are today (`linux.img`,
`zImage_dtb`, `zImage_dtb-rt`, the sdcard images, the release asset set). Target names may change;
what is in the middle may change.
**Sources of record:** the wrapper `Makefile` (1,302 lines, read in full), `external.mk`, the pinned
Buildroot 2026.08 tree under `work/buildroot`, `.github/`, `scripts/`, and the ADRs cited inline.
Every Buildroot claim below was checked against that tree, not recalled.

---

## 0. The interface goal (owner's framing, 2026-09-11)

"Vanilla" here means the **same Makefile interface as a basic Buildroot project**: someone who
knows Buildroot should be able to clone this repo and type what they would type anywhere else. The
1,302-line Makefile with ~60 project-specific targets is the barrier. So the yardstick for every
option below is the newcomer's session, not the line count.

| Task | Today | Goal |
|---|---|---|
| Configure the DE10 image | `make de10nano-defconfig` | `make mister_de10nano_defconfig` |
| Build it | `make all` (bare `make` prints help) | `make` |
| Build the RT kernel | `make rt` **before** `make all`, `make rt-clean` on bumps | nothing — it is part of `make` |
| Build stage 1 | `make initramfs` (implicit in `all`) | nothing — it is a package |
| Kernel menuconfig | `make linux-menuconfig`; `make rt-menuconfig` for RT | `make linux-menuconfig`; `make linux-rt-menuconfig` |
| Configure and build the DE25 | `make de25nano-defconfig && make de25` | `make O=output-de25 mister_de25nano_defconfig && make O=output-de25` |
| Clean one tree | `make clean` (all six at once, or fails) | `make clean` / `make O=output-de25 clean` |
| Regenerate a stale config after a Buildroot bump | `make rt-defconfig` (added today), `de10nano-defconfig`, … | `make mister_de10nano_defconfig` |
| Find out what a target does | read 1,300 lines | Buildroot's manual |

The only thing the newcomer must learn that Buildroot does not teach is that the Buildroot tree is
fetched and hash-verified for them into `work/buildroot`. Everything else is Buildroot's own
vocabulary, including `O=` for the second board.

### 0.1 The end-state Makefile, sketched

Roughly this, plus comments and the pin block. It is the manual's "custom top Makefile" idiom with
the fetch step in front of it:

```make
BUILDROOT_VERSION ?= 2026.08
BUILDROOT_SHA256  ?= d678e810abf877d04513e03ca2c99f992dd49118b9c2e18d6e25f5f58fa8c5cd

O               ?= $(CURDIR)/output
export BR2_DL_DIR ?= $(CURDIR)/dl
BR              := $(CURDIR)/work/buildroot
BR_STAMP        := $(BR)/.stamp-$(BUILDROOT_VERSION)
BR_MAKE          = $(MAKE) -C $(BR) O=$(O) BR2_EXTERNAL=$(CURDIR)

.PHONY: all buildroot-unpack
all: $(BR_STAMP)
	$(BR_MAKE) all

$(BR_STAMP):
	scripts/fetch-buildroot.sh $(BUILDROOT_VERSION) $(BUILDROOT_SHA256) $(BR)   # download, verify, unpack
	touch $@
buildroot-unpack: $(BR_STAMP)

Makefile: ;
%: $(BR_STAMP)
	$(BR_MAKE) $@
```

What is *not* in it, and where it went:

- Six invocation variables, five `.config` rules, five `-defconfig` targets: gone; `make <name>_defconfig`
  and `O=` are Buildroot's.
- `initramfs`, `check-initramfs`, `initramfs-verify`, `de25-initramfs*`: Phase B's package and its
  post-build hook.
- `rt`, `rt-clean`, the overlay, the stamps, `rt-legal-info`, `rt-external-deps`: Phase C's package.
- The PREEMPT_RT proof, the DE25 artifact assertions, the cpio applet checks: package post-build
  hooks and `board/mister/*/post-image.sh`, which is where Buildroot puts such checks.
- `clean`/`distclean` across six trees: with one or two trees, Buildroot's own, per `O=`. `dl/` is
  outside every `O=` and survives as before.
- `help`: Buildroot's `make help`, plus a ten-line `README` block naming the two defconfigs.
- `hostshim`: stays as a script the fetch step calls once, not a Makefile concept.
- The `%:` hazards: with no fragment prerequisites and no included makefiles, only `Makefile: ;` is
  needed, which is exactly what Buildroot's own generated wrapper carries.

Bare `make` becomes a build, as in Buildroot. On an unconfigured tree Buildroot's own message
appears ("Please configure Buildroot first"); the wrapper can prefix a one-line hint naming
`make mister_de10nano_defconfig`. The Makefile's help-by-default was premised on a defconfig with no
architecture, and its own comment marks that premise as expired.

---

## 1. What the wrapper does today, and how much of it is wrapper

The Makefile drives **six** Buildroot output trees, one per configuration:

| Tree | Configuration | Why it is separate |
|---|---|---|
| `output/` | DE10 image (`common de10nano image-common de10nano-image`) | the product |
| `output-initramfs/` | stage-1 cpio (`initramfs-common initramfs-de10nano`), static musl BusyBox | a different libc needs a different toolchain, so a different `O=` |
| `output-initramfs-de25/` | the same stage 1 for aarch64 | different architecture |
| `output-rt/` | kernel-only PREEMPT_RT (`common de10nano kernel-only` + `mister_rt.fragment`) | a different kernel configuration in the same toolchain |
| `output-installer/` | sdcard installer cpio (`mister_installer_defconfig`) | static musl again, plus extra packages |
| `output-de25/` | DE25 developer OS | different architecture |

Its responsibilities, sized by lines (comments included, since the comments are where the
load-bearing reasons live):

| Responsibility | Lines | Vanilla Buildroot equivalent |
|---|---|---|
| Pin, download, SHA-verify, unpack Buildroot into `work/buildroot` | ~110 | none — Buildroot assumes it is already there |
| Build one `BR_MAKE_*` invocation per tree (six copies) | ~40 | Buildroot's own generated `$(O)/Makefile` forwards to the source tree with `O=` remembered |
| Generate each `.config` from a fragment stack (`merge_config.sh` + `olddefconfig`) and the `*-defconfig` regenerate targets | ~120 | `make <name>_defconfig` from `configs/` — whole files only, no stacking |
| Orchestrate stage 1 before the kernel, stage RT modules into an overlay, stamps, `rt-clean`'s double removal | ~200 | none — one configuration per tree, no cross-tree dependencies |
| Post-build assertions (`check-initramfs`, `initramfs-verify`, PREEMPT_RT proof, DE25 artifact existence) | ~250 | post-build / post-image hook scripts |
| `clean` / `distclean` across six trees, extra-modules overlay lifecycle | ~60 | `make -C output clean` per tree |
| `help`, `br-help`, tombstone targets, `require-tools`, hostshim | ~150 | `make help` |
| Per-tree `menuconfig` / `busybox-menuconfig` / `linux-menuconfig` wrappers | ~40 | `make -C <tree> menuconfig` |
| The `%:` catch-all plus the four empty rules that keep it from recursing or loading a config into the wrong tree | ~40 | Buildroot's `$(O)/Makefile` uses `$(MAKECMDGOALS)`, which has neither hazard |
| `sdcard`, `zimage-dtb`, `installer` pass-throughs | ~30 | scripts / post-image hook (already the case) |

Roughly 60% of the file exists because six configurations are orchestrated from one place, and
roughly 25% is assertion code that Buildroot's hook points could host. The pin/verify/unpack block
is the only part with no Buildroot-native home at all.

### 1.1 What must survive any restructuring

The three research passes (Buildroot mechanisms, CI and script consumers, design docs) converged on
this list. Anything not here is negotiable.

**Artifact and boot (from ADR 0002, 0021, 0026, 0029; `docs/boot-chain.md`):**
- The stage-1 cpio is inside the zImage. U-Boot passes `-` for the initrd and never loads one.
- `BR2_TARGET_ROOTFS_INITRAMFS` is never set on an image config (A1: it embeds the whole rootfs).
- `zImage_dtb` under 16 MiB, enforced by `scripts/check-zimage-dtb.sh` from the post-image hook.
- The main rootfs is glibc (stock `MiSTer` links against it), so stage 1 is a *second* configuration
  today rather than a flag.
- One `linux.img` carries every kernel variant's module tree.
- The RT kernel is proved RT (`CONFIG_PREEMPT_RT=y` in the built `.config`) and its module tree is
  depmod'd; `merge_config.sh` only warns when a symbol is dropped.
- The DE25 kernel embeds nothing until D11 is closed, and never the armv7 cpio.
- Buildroot is pinned by version and SHA-256 taken from the signed manifest, verified before unpack,
  with a version-qualified stamp; `SOURCE_DATE_EPOCH` derives from that pinned tree.

**CI and script contract (from `.github/` and `scripts/`, cited in the research notes):**
- `BUILDROOT_VERSION ?=` and `BUILDROOT_SHA256 ?=` as single greppable lines in the root `Makefile`.
  Four regexes and Renovate read them; the hash-sync rewrites the SHA line in place.
- `configs/fragments/stacks.mk` in its one-line-per-stack shape; three check scripts parse it as text.
- Repo-root output directory names: `output/`, `output-<variant>/`, `output-initramfs*/`,
  `output-installer/`, `output-de25/`, `work/buildroot`, `work/.hostshim`, `work/extra-modules-overlay`,
  `dl/`. Cache keys, artifact tars and every checker are built on them.
- Targets invoked by name from outside: `hostshim`, `de10nano-defconfig`, `all`, `<variant>`,
  `<variant>-legal-info`, `<variant>-external-deps`, `buildroot-unpack`, `check-initramfs`,
  `initramfs-verify`, `de25-initramfs-verify`, plus forwarded Buildroot targets (`legal-info`,
  `external-deps`, `olddefconfig`, `azcopy`, `<pkg>-dirclean`, `linux-rebuild`).
- Command-line and environment pass-through into Buildroot (`BR2_CCACHE*`, `AZCOPY_GO_ENV`,
  `MISTER_INITRAMFS_CPIO`, `MISTER_VERSION`).
- The release asset set: seven main files, `zImage_dtb-<v>` / `linux-<v>.config` /
  `legal-info-<v>.tar.gz` per variant, sdcard images, azcopy. `SHA256SUMS` is the variant registry
  for the publish job.
- `output/.config` has no file prerequisites (menuconfig edits survive); CI regenerates it with
  `de10nano-defconfig` unconditionally.

**Make-semantics hazards the current shape created (and which a different shape can simply avoid):**
the `%:` catch-all recursing on `Makefile`, forwarding a fragment path into Buildroot with the wrong
`O=`, `clean` falling through to one tree, `distclean` leaving `.config` behind, `-j` ordering of the
hostshim. None of these is a requirement; they are scars of the current design.

---

## 2. What vanilla Buildroot 2026.08 offers (checked in the pinned tree)

- **External defconfigs.** `make <name>_defconfig` searches every `BR2_EXTERNAL` tree's `configs/`
  (`Makefile:1049-1060`). `make list-defconfigs` lists them. Whole files only.
- **No fragment stacking for the Buildroot config.** There is no `BR2_CONFIG_FRAGMENT_FILES`. The
  upstream precedent for stacking is `utils/test-pkg:174`, which calls
  `support/kconfig/merge_config.sh` with `CONFIG_=""` on a base plus fragments — exactly what the
  wrapper does. `support/scripts/check-dotconfig.py` asserts every line of a defconfig survived into
  `.config`; upstream CI runs it after every `make <name>_defconfig`.
- **Generated forwarding Makefile.** After the first configure, Buildroot writes `$(O)/Makefile`
  (`support/scripts/mkmakefile`), so `make -C output <anything>` works with `BR2_EXTERNAL` remembered
  in `$(O)/.br2-external.mk`. `BR2_DL_DIR` and `BR2_CCACHE_DIR` are honoured from the environment
  before `.config` is read (`Makefile:201-208`). This is the mechanism that makes a thin wrapper
  possible: the wrapper is needed for the *first* command per tree, not for the rest.
- **The manual's own wrapper** (`docs/manual/customize-directory-structure.adoc:114-153`) is
  fifteen lines: `%: configs/%` → `make -C buildroot O=output/<name> $@`. It handles only
  `<name>_defconfig` goals and leaves everything else to `make -C output/<name>`.
- **Kernel dependency injection from an external.** `LINUX_DEPENDENCIES` cannot be extended from
  `external.mk` (too late: `linux/linux.mk:700` has already expanded them). It *can* from
  `$(BR2_EXTERNAL)/linux/linux-ext-*.mk`, included at `linux/linux.mk:643-644` before the eval.
  `LINUX_KCONFIG_FIXUP_CMDS` and `<PKG>_LINUX_CONFIG_FIXUPS` work from `external.mk` because the
  fixup block expands at recipe time. This is the hook that lets a package produce the cpio and
  make the kernel depend on it.
- **Same package, two configs.** `boot/barebox` builds a second barebox (`barebox-aux`) from the same
  source with a different config inside one tree (`boot/barebox/barebox.mk:8-29,192-195`). The
  kconfig-package infrastructure (`package/pkg-kconfig.mk`) is available to external packages and
  gives `<pkg>-menuconfig`, fragment merging, and patch application from `BR2_GLOBAL_PATCH_DIR`
  for free. This is the precedent for a second kernel package.
- **Toolchain reuse across trees.** `make sdk` produces a relocatable toolchain
  (`support/misc/relocate-sdk.sh`); a second tree consumes it with `BR2_TOOLCHAIN_EXTERNAL_PATH`.
- **Hooks.** `BR2_ROOTFS_POST_BUILD_SCRIPT`, `POST_FAKEROOT`, `POST_IMAGE` (space-separated lists,
  exported `BR2_CONFIG`, `TARGET_DIR`, `BINARIES_DIR`, `HOST_DIR`, `BR2_EXTERNAL_<NAME>_PATH`). The DE10
  already uses post-build and post-image; the assertions the Makefile carries could live there.
- **Things Buildroot cannot do:** two toolchains in one tree; embed a cpio built elsewhere without
  an external's help; delete from an overlay (`SYSTEM_RSYNC` has no `--delete`); make a bare `make`
  on an unconfigured tree do anything but error; `distclean` a non-default `O=`.

---

## 3. Two measurements that decide the shape

**3.1 Stage 1 built with the main glibc toolchain.** The same `initramfs-busybox.config`, same
BusyBox 1.38.0 source with Buildroot's patches, linked `-static` with the DE10's own
`arm-buildroot-linux-gnueabihf-gcc` (the toolchain in `output/host`):

| | musl static (today) | glibc static (measured 2026-09-11) |
|---|---|---|
| `busybox` | 263,308 B | 942,660 B |
| cpio today | 424,448 B | ≈ 1,100,000 B (estimate: BusyBox delta only) |
| gzipped inside the kernel | ≈ 134 KB (ADR 0002 §7) | ≈ 350–400 KB (estimate) |
| headroom under 16 MiB after the change | 7.47 MB (RT), more for main | ≈ 7.2 MB |

ADR 0002 rejected glibc for stage 1 on two grounds: `BR2_STATIC_LIBS` is not offered with glibc, and
"Buildroot would still copy the shared glibc into the cpio". Both hold for a *Buildroot
configuration* and neither holds for a *package* that builds one static binary into its own staging
directory and produces the cpio itself. The size cost is real but small against the budget.

**3.2 CI already serialises RT.** In the last green master run the RT kernel job ran 19 min and the
image job waited for it, then ran 3 h 05 min. A second kernel compiled *inside* the main build
replaces that 19-minute leg with roughly a kernel compile on a warm ccache. Wall clock is neutral to
slightly better; the parallelism ADR 0021 originally wanted was already given up in its 2026-07-18
amendment.

---

## 4. Options

Each option is independent of the others except where stated. "Makefile after" is an estimate of
the wrapper's size with comments kept at today's density.

### Option A — Mechanical consolidation, no behaviour change

Keep every tree, every target name and every assertion; remove the duplication.

- One `br_make` function taking the `O=` directory; the six `BR_MAKE_*` variables go.
- One table of trees (name, `O=` dir, stack) and pattern rules `%-defconfig`, `%-menuconfig`,
  `%-clean` derived from it. The five hand-written copies of each go.
- Move every assertion body into `scripts/` (`assert-rt-kernel.sh`, `assert-de25-artifacts.sh`;
  `initramfs-verify` and `check-initramfs` already have the shape of scripts). The Makefile calls
  them. `ci-tests.sh` keeps calling the targets, which keep their names.
- Replace the `%:` catch-all with Buildroot's own idiom: forward `$(MAKECMDGOALS)` through one
  `_all` rule. The four empty rules and the recursion hazard disappear with it.
- Fix the one inconsistency found: `$(INSTALLER_OUTPUT_DIR)/.config` is the only config rule with a
  real file prerequisite and no hostshim ordering.

Makefile after: ≈ 400 lines. Risk: low; every consumer in §1.1 is untouched. This is the floor and
should happen regardless of what else is chosen.

### Option B — Stage 1 becomes a package of the main build (amends ADR 0002)

A br2-external package `mister-initramfs` builds a static BusyBox with the main toolchain from
`board/mister/common/initramfs-busybox.config`, lays down the `/init` overlay, runs today's
post-build trimming, and installs `mister-initramfs.cpio` into `$(BINARIES_DIR)`. A
`linux/linux-ext-mister-initramfs.mk` in the external adds it to `LINUX_DEPENDENCIES`; the existing
`LINUX_KCONFIG_FIXUP_CMDS` block points `CONFIG_INITRAMFS_SOURCE` at it. The verify checks (applet
list, forbidden binaries, `/dev/console`, `ash -n /init` under qemu) become the package's
post-build hook, failing the package.

Removes: `output-initramfs/`, `output-initramfs-de25/`, the `initramfs*` and `de25-initramfs*`
targets, `check-initramfs` (the kernel fixup now cannot run without the cpio, so the assertion is
structural), the initramfs host cache in CI, the `initramfs-common`/`initramfs-*` stacks and their
two golden lines. `make all` is `make -C output all`.

The DE25 gets the same package for aarch64 for free; the D11 switch becomes one Kconfig line in the
DE25 stack instead of a six-file commit. `mk-sdcard.sh`'s installer relink keeps working: the
`MISTER_INITRAMFS_CPIO` override becomes a package variable override.

Cost: the cpio grows by roughly 700 KB uncompressed (§3.1), the `arch`-gated fixup in `external.mk`
becomes a `BR2_PACKAGE_MISTER_INITRAMFS` gate (ADR 0002 rejected a bool because it moved the
toolchain-fingerprint cache key; that cost is paid once). The stage-1 cpio was byte-reproducible via
`BR2_REPRODUCIBLE`; a package build inherits the same setting from the main config.

Makefile after (with A): ≈ 250 lines. Risk: medium. New package code (~120 lines) replaces ~350
lines of Makefile plus two stacks; the risk is concentrated in one reviewable package.

### Option C — RT kernel becomes a second kernel package of the main build (amends ADR 0021)

A kconfig-package `linux-rt` in the external, modelled on barebox-aux: same tarball as the
`linux` package's 7.2.x pin via `BR2_GLOBAL_PATCH_DIR`'s `linux-rt/` (a symlink to
`linux-patches-beta/`, whose `series` file Buildroot's `apply-patches.sh` honours), the RT kernel
config fragment, `zImage` + DTB concatenated to `$(BINARIES_DIR)/zImage_dtb-rt`, and
`modules_install` into `$(TARGET_DIR)`. The PREEMPT_RT proof and the depmod'd-tree check become the
package's post-build hook. `linux-rt-menuconfig` comes with the infrastructure.

Removes: `output-rt/`, the extra-modules overlay and its stamp, `rt-clean`'s two-place deletion (no
overlay means no rsync-never-deletes problem), the `rt` before `all` ordering rule, `rt-defconfig`,
`rt-menuconfig`, `rt-external-deps`, `rt-legal-info`, the `build-kernel` matrix job, the
`kernel-leg` and `merge-kernel-modules` actions, and the per-variant host cache. One `make -C output
all` produces both kernels and the one `linux.img` natively.

Changes the release contract: `legal-info-rt.tar.gz` folds into `legal-info.tar.gz` (the single
`legal-info` covers every package), and `linux-rt.config` is read from
`output/build/linux-rt-*/.config`. The publish job's variant registry (derived from `SHA256SUMS`)
needs a matching edit. The `configs/mister_<variant>.fragment` registry becomes a Kconfig option per
variant; `scripts/list-kernel-variants.sh` reads Kconfig instead of the filesystem.

Cost: ~150 lines of package `.mk` reimplementing what `linux.mk` does for the second kernel (patch,
configure with fragments, build `zImage` and modules, install). `make rt` alone is no longer a
thing; locally an RT-less build is `BR2_PACKAGE_LINUX_RT=n`. CI wall clock is neutral (§3.2).

Makefile after (with A and B): ≈ 150 lines. Risk: medium-high, mostly in CI rewiring (three
actions and two workflows) rather than in the build itself.

### Option D — Generated defconfigs committed next to the fragments

Keep `configs/fragments/` as the source of truth, but generate `configs/mister_<stack>_defconfig`
(the `savedefconfig` of the merged stack) and commit it. A CI check regenerates and diffs; upstream's
`check-dotconfig.py` runs after every `make <name>_defconfig`, as in upstream's own CI.

Gains: `make -C work/buildroot O=$PWD/output BR2_EXTERNAL=$PWD mister_de10nano_defconfig` is fully
vanilla, with no wrapper involved. The golden-hash mechanism becomes redundant: the resolved change
that the DE25 uClibc regression hid behind an opaque hash on the 2026.08 bump would have appeared as
a reviewable diff in the committed defconfig. `savedefconfig` round-trips to a file whose diff is
the change.

Cost: two representations in git; every fragment edit must regenerate (a pre-commit hook or the CI
diff enforces it). The `-defconfig` regenerate targets stay only as aliases.

Makefile impact: neutral; this is about where the config generator lives, not how large the
Makefile is. Independent of A–C.

### Option E — Buildroot as a git submodule instead of a pinned tarball

Rejected on project grounds, recorded for completeness. The pinned, signed-manifest-verified tarball
is the settled pattern (G4/G6, TASKS standing rule 1; the U-Boot submodule proposal in ADR 0017 was
superseded by ADR 0024 in favour of the same idiom). Renovate, the hash-sync case 6 and three
scripts are built on the two pin lines. A submodule would move ~110 lines out of the Makefile at the
price of re-deriving `SOURCE_DATE_EPOCH` and the supply-chain story. Not recommended.

### Option F — Share the toolchain between the trees that remain (`make sdk`)

Only relevant if C is *not* taken: `output-rt` would consume `output/`'s relocated SDK as an
external toolchain, removing the 16-minute toolchain rebuild and the per-variant host cache. It is a
config change (`BR2_TOOLCHAIN_EXTERNAL_*` in `mister_rt.fragment`) plus one `make prepare-sdk` step,
and adds a dependency of the RT tree on the main tree's host directory. Strictly worse than C for
simplicity; listed as the fallback if C is refused.

---

## 5. Recommendation (revised 2026-09-11 after the owner's answers)

The owner answered Q1 and Q2 the same day: a glibc-static stage 1 is acceptable, and moving RT
into the main build serially is *wanted*, on the grounds that the pipeline leans too hard on
GitHub's best-effort cache and a cache miss can rebuild a toolchain more than once per run. CI
simplification is in scope for this workstream. That changes the plan in three ways.

**One correction to the premise first.** The 16 MiB kernel budget has nothing to do with SD card
size. It is U-Boot's memory map: the kernel is loaded at `0x01000000` and `menu.rbf` is staged at
`0x02000000`, so a `zImage_dtb` past 16 MiB overwrites the FPGA bitstream buffer
(`docs/boot-chain.md` §7.3). The conclusion stands, because the measured headroom is 7.4 MB on the
larger RT kernel and stage 1 is fixed-purpose, but the reasoning to carry forward is "RAM layout",
not "card size".

### 5.1 Phase A is folded away

A standalone consolidation pass would refactor the six-tree orchestration that Phases B and C then
delete. With B and C accepted in principle, the Makefile is rewritten once, at the end, around what
remains. What A contributed survives as rules for that rewrite: one invocation function, a table of
trees, assertions in scripts or hooks, Buildroot's `$(MAKECMDGOALS)` forwarding idiom instead of `%:`.

### 5.2 Order of work

1. **B — stage 1 as a package** (`package/mister-initramfs/`, `linux/linux-ext-mister-initramfs.mk`,
   ADR 0002 amendment). Deletes `output-initramfs*`, two stacks, the initramfs host cache. Gate:
   boot on the rig plus the eight `test-initramfs.sh` cases plus the `zcat usr/initramfs_inc_data |
   cmp` identity check. The DE25 gets the aarch64 build of the same package; D11 stays closed until
   the owner says otherwise, now as one Kconfig line.
2. **C — RT as `package/linux-rt/`** (kconfig-package, barebox-aux pattern, ADR 0021 amendment).
   Deletes `output-rt`, the overlay, the stamps, `build-kernel`, `kernel-leg`,
   `merge-kernel-modules`, the variant host and dl caches. One `make all` yields both kernels and the
   one `linux.img`. Release assets: `legal-info-rt.tar.gz` folds into `legal-info.tar.gz`;
   `zImage_dtb-rt` and `linux-rt.config` are still published, now read from `output/`.
3. **Makefile rewrite** to the thin form (§5.4), same PR as the CI rewrite below or the one after.
4. **D — committed generated defconfigs**, at any point; it is orthogonal.

### 5.3 CI after B and C

Today the composite build action holds **seven** caches (tarball, main dl, variant dl, main host
toolchain, variant host toolchain, initramfs host toolchain, ccache) across 640 lines, plus the
kernel leg and module-merge actions (353 lines) and a matrix job. After B and C:

- **Four caches**: tarball, dl, one host toolchain, ccache. The toolchain fingerprint machinery
  keys one cache instead of three, or goes entirely with Option G below.
- **One build job** in `build.yml` (`gate → lint-config → build → status`); the `build-kernel`
  matrix, `kernel-leg` and `merge-kernel-modules` are deleted. `release.yml` loses the same matrix
  and the per-variant asset staging; the publish job's variant registry becomes a fixed list.
- **Worst case on a cache miss is one toolchain build**, because there is one tree. Today it is up
  to three.
- `list-kernel-variants.sh` reads Kconfig symbols instead of `configs/mister_*.fragment`; the two
  `hashFiles()` lists and their `check_hashfiles` assertions shrink to one.

### 5.4 Option G — the toolchain as a pinned, hash-verified artifact instead of a cache

This is the lever that removes the dependence on caching rather than reducing it. Buildroot has a
first-class, vanilla mechanism for it: a br2-external can ship a **toolchain package**
(`provides/toolchains.in` plus `toolchain/toolchain-external-mister/` using
`toolchain-external-package`, `docs/manual/customize-outside-br.adoc` "toolchains"), which is a
normal package with `_SITE`, `_SOURCE` and a `.hash` file, so the download is hash-verified like
every other package. The upstream ARM and Bootlin toolchains are packaged exactly this way
(`toolchain/toolchain-external/toolchain-external-arm-arm/` ships a `.hash`). Note that the *other*
route, `BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD` with a custom URL, explicitly cannot verify hashes
(`toolchain-external-custom.mk:11`) and is not proposed.

Shape:
- A `toolchain.yml` workflow, manual or triggered by a Buildroot pin change, runs `make sdk` on a
  kernel-only-style config and publishes `arm-buildroot-linux-gnueabihf_sdk-buildroot.tar.gz` plus
  its sha256 as assets of a `toolchain-YYYYMMDD` release. The same for the DE25's aarch64 SDK.
- The image config selects that toolchain package; its `.hash` pins the bytes. Buildroot checks the
  declared gcc, glibc and kernel-headers properties against the SDK at configure time and fails on
  mismatch, so a stale pin cannot go unnoticed.
- The build job downloads ~100 MB instead of restoring a ~1 GB cache or compiling for 20 minutes.
  A fresh local clone gets a first build in minutes.

Costs and the one open risk:
- "No binaries in git" is respected (a release asset, like azcopy), but the project now ships a
  toolchain it built. The SDK is built from the pinned Buildroot with the pinned config, so its
  inputs are pinned; the bump discipline is "Buildroot pin moves → toolchain release first".
- **Artifact identity must be measured, not assumed.** An external-toolchain build installs the
  target libc from the SDK's sysroot (`copy_toolchain_lib_root`) rather than through the internal
  glibc package's install rules. The bytes of `libc.so` are the same, but which locale, gconv and
  debug files land in the image can differ. The gate for G is a `linux.img` content diff against an
  internal-toolchain build of the same commit, with any difference explained or eliminated before
  the switch. If it cannot be made identical, G is dropped and the single host cache stays.
- Reproducibility (A9) keeps its meaning: same pinned inputs, same output. The
  `.br-toolchain-fingerprint` file and its sentinels become unnecessary.

Recommendation: do G **after** C, as its own PR with the identity measurement in the PR body. It is
the largest single CI simplification available, and the one that answers the stated worry directly.

### 5.5 Target mapping if everything lands

| Today | After |
|---|---|
| `make de10nano-defconfig` | `make mister_de10nano_defconfig` (CI alias kept for one release) |
| `make all` | `make all` (forwards to `output/`) — unchanged name |
| `make initramfs`, `make check-initramfs`, `make initramfs-verify` | gone; the package fails the build instead |
| `make rt`, `rt-defconfig`, `rt-menuconfig`, `rt-clean`, `rt-legal-info`, `rt-external-deps` | gone; `make linux-rt-menuconfig`, `BR2_PACKAGE_LINUX_RT` |
| `make de25`, `de25nano-defconfig`, `de25-*` | `make mister_de25nano_defconfig`; `make -C output-de25 all`; assertions in `board/mister/de25nano/post-image.sh` (already the card's hook) |
| `make de25-initramfs*` | gone; `BR2_PACKAGE_MISTER_INITRAMFS=y` in the DE25 stack when D11 closes |
| `make installer*` | unchanged (`mk-sdcard.sh` owns it) |
| `make clean` / `distclean` | loop over the trees that exist; `dl/` kept |
| `make buildroot-unpack`, `buildroot-verify`, `buildroot-showsig`, `hostshim` | unchanged (CI contract) |
| `make <anything else>` | forwarded to `output/` as today |

End state: one DE10 tree, one DE25 tree, one installer tree driven by `mk-sdcard.sh`; a wrapper of
roughly 150 lines whose only non-vanilla job is pin/verify/unpack; a build workflow with one build
job and four caches, or three if G lands.

### 5.6 Touch list per phase (from the consumer map)

- **B:** `package/mister-initramfs/`, `linux/linux-ext-mister-initramfs.mk`, `external.mk` (fixup
  gate), `configs/fragments/` (delete two stacks, add one symbol), `golden.sha256`,
  `.github/actions/buildroot-build/action.yml` (drop the initramfs host cache and the
  `INITRAMFS_DE10NANO` stack reads), `scripts/ci-tests.sh` (drop three target calls),
  `scripts/test-initramfs.sh` (cpio path), `scripts/mk-sdcard.sh` (override variable name),
  `docs/decisions/0002-initramfs.md` amendment, README build section.
- **C:** `package/linux-rt/`, `board/mister/de10nano/patches/linux-rt` symlink, `configs/fragments/`
  (variant symbol), `.github/workflows/build.yml` and `release.yml` (drop `build-kernel`, adjust
  assets), delete `kernel-leg` and `merge-kernel-modules` actions, `scripts/list-kernel-variants.sh`,
  `docs/decisions/0021` amendment, `docs/rt-beta-kernel.md` §5.
- **Makefile rewrite + CI:** `Makefile`, `.github/actions/buildroot-build/action.yml` (four caches),
  `docs/ci.md`, README.
- **D:** `scripts/gen-defconfigs.sh` (new), `configs/mister_*_defconfig` (generated),
  `scripts/check-config-fragments.sh` (diff instead of hash), `lint.yml`.
- **G:** `toolchain/toolchain-external-mister/`, `provides/toolchains.in`, `.github/workflows/toolchain.yml`
  (new), `configs/fragments/de10nano.fragment` (toolchain selection), the identity measurement.

---

### 5.7 Sharing between the DE10 and the DE25: what the shared layers actually contain

The owner's stated direction (2026-09-11) is two architectures with a nearly identical userspace and
similar kernels, maintained in one place. Whether the fragment generator is the right tool for that
depends on what the shared lines *are*, so they were counted:

| Layer | symbols | `BR2_PACKAGE_*` | everything else |
|---|---|---|---|
| `common` (shared by all stacks) | 7 | 0 | 7 (toolchain C++, hash check, kernel on, DTS, reproducible, merged-usr) |
| `image-common` (shared DE10/DE25) | 31 | 31 | 0 |
| `de10nano-image` | 228 | 213 | 15 (ext4 sizing/UUID, eudev, bash, locale, timezone, overlay, post-build) |
| `de10nano` | 16 | 1 | 15 (arch, toolchain, kernel pin, patches, DTS, post-image) |
| `de25nano` | 46 | 6 | 40 (arch, toolchain, kernel, U-Boot, TF-A, card) |

The userspace that is to be shared is **packages**, overwhelmingly. Buildroot shares packages
between boards natively, without a generator: a **profile package** in the external's `Config.in`
(`BR2_PACKAGE_MISTER_USERSPACE`, a bool that `select`s the package set) — the same shape as any
upstream package that pulls in its dependencies, visible in `make menuconfig` under "External
options" as one checkbox. Board-only packages (`aic8800`, `azcopy`, later the MiSTer binaries) stay
as explicit lines in the board's defconfig or in a second, explicitly named profile
(`BR2_PACKAGE_MISTER_DE10_EXTRAS`), which turns `docs/buildroot-config.md`'s rule 5 ("no DE10
package reaches the DE25 without a decision") from a review convention into Kconfig structure.

The rest of the sharing already uses Buildroot's list-valued options and needs no generator:

- **Kernel drivers:** `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` pointing at
  `board/mister/common/linux-mister.fragment` — the DE25 stack does this today; the DE10 would adopt
  it, keeping a per-SoC base `linux.config` under each board. Known cost, already accepted for the
  DE25: `linux-update-defconfig` refuses to round-trip a fragment-built config, so edits go through
  `linux-diff-config` and a hand fold.
- **Overlay, patches, hook scripts:** `BR2_ROOTFS_OVERLAY`, `BR2_GLOBAL_PATCH_DIR`,
  `BR2_ROOTFS_POST_*_SCRIPT` are space-separated lists; `board/mister/common/` plus
  `board/mister/<board>/` is the manual's documented layering
  (`customize-directory-structure.adoc` §"layered customizations").

What cannot be shared natively is the non-package remainder: about 20 system-level lines (rootfs
size and UUID, locale, timezone, shell, device manager, reproducibility, hash checking). Those are
duplicated in the two defconfigs, and one lint asserts the named list agrees between them. That is
the whole cost, and it is smaller than the generator, the golden hash and the stack lockstep checks
it replaces.

**Caveat to document for newcomers (owner, 2026-09-11).** This *is* a departure from a plain
Buildroot project in one respect: in a plain project every top-level package choice is a line in
the defconfig, whereas here the shared userspace is one `BR2_PACKAGE_MISTER_USERSPACE` line whose
contents live in `package/mister-userspace/Config.in`. That is idiomatic Kconfig, but a reader
looking for "why is `bluez5_utils` in my image" must know to look in the profile, not the
defconfig. Three pointers cover it: the profile's own Kconfig help text (visible in `menuconfig`),
a README paragraph under "Building it yourself", and a two-line note at the top of the wrapper
Makefile. Nothing else in the build differs from the manual's description.

**Recommendation for Q3:** retire the Buildroot-config fragment layer once B and C land, and move
the sharing to the profile package plus the list-valued options. Two committed defconfigs of
roughly 50 lines each become the only source; `make mister_de10nano_defconfig` is fully vanilla;
`savedefconfig` round-trips; `make menuconfig` shows the shared userspace as one option. Keep
`check-config-fragments.sh` only as the ~20-line shared-remainder diff. Caveat to mirror in the
profile: `select` force-enables a package even when its own `depends on` is unmet (kconfig warns),
so arch-limited packages must not be selected unconditionally; that is exactly why they belong in
the board defconfig or an arch-gated profile.

## 6. Questions for the owner

1. ~~Is a larger compressed kernel acceptable (Phase B)?~~ **Yes, 2026-09-11.**
2. ~~Is losing the separate RT legal-info asset and the parallel kernel job acceptable (Phase C)?~~
   **Yes, 2026-09-11**; serial RT is wanted for cache reasons.
3. **Fragments after B and C** — see §5.7: the shared userspace is packages, which a Kconfig
   profile shares natively; recommendation is to retire the fragment generator for two plain
   defconfigs plus the profile. Owner to confirm.
4. Keep the `output-<name>` directory names? Recommended yes.
5. **New:** Option G, the toolchain as a hash-verified release asset. Yes in principle, subject to
   the image-identity measurement?

---

## 7. Research notes (where each claim came from)

- Buildroot mechanisms: `work/buildroot/Makefile` 33-87, 189-208, 599-609, 973-984, 1043-1070,
  1086-1090, 1139-1151; `support/scripts/mkmakefile`; `support/kconfig/merge_config.sh`;
  `utils/test-pkg:174`; `support/scripts/check-dotconfig.py`; `linux/linux.mk` 408-420, 643-644,
  700-716; `package/pkg-kconfig.mk`; `boot/barebox/barebox.mk` 8-29, 192-195;
  `docs/manual/customize-directory-structure.adoc` 114-153.
- Consumers: `.github/actions/buildroot-build/action.yml` 182-306, 456-542;
  `.github/workflows/release.yml` 243-300, 460-467, 674-737, 800-898;
  `scripts/lib/config-stacks.sh`; `scripts/check-config-fragments.sh` 172-305, 426-491;
  `scripts/mk-sdcard.sh` 29-46, 101-175, 351-482; `scripts/ci-tests.sh` 26-28, 269-312.
- Constraints: ADR 0002 §3, §7, §8a, §10; ADR 0021 §2-4 and its 2026-07-18/07-27 amendments;
  ADR 0026; ADR 0029 D11; `docs/boot-chain.md` §7.3, §8.2; `docs/buildroot-config.md` §1, §5.1,
  §7, §8, §11; `external.mk` 32-135, 140-174.
- Measurements: static glibc BusyBox built 2026-09-11 in `/mnt/source/bb-static-measure`; CI job
  times from run 34560109238.
