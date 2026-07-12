# MiSTer Linux Modernization — Ultracode Task List

Companion to `PLAN.md` v2 (amendments A1–A9 folded into the plan; post-cutoff facts —
6.18 LTS status/EOL, Buildroot 2026.02, mainline DE10-Nano DTS — confirmed by the
maintainer, 2026-07-11). This file is the
execution contract: every task is self-contained, has explicit acceptance criteria, and
names the AI model sized to it. Work through phases in order; within a phase, tasks with
satisfied dependencies may run in parallel.

---

## 0. Conventions

### Model routing

| Tag | Model | Model ID | Use for |
|-----|-------|----------|---------|
| **[OPUS]** | Claude Opus 4.8 | `claude-opus-4-8` | Kernel forward-ports, DTS authoring, boot-chain analysis, initramfs design, ABI analysis, hard debugging |
| **[SONNET]** | Claude Sonnet 5 | `claude-sonnet-5` | Default implementation workhorse: Buildroot packages/configs, init scripts, CI workflows, test harnesses, technical docs |
| **[HAIKU]** | Claude Haiku 4.5 | `claude-haiku-4-5-20251001` | Mechanical work: inventories, boilerplate, templates, checksums, version-bump chores, doc formatting |

**Escalation rule:** if a task fails its acceptance criteria twice at its assigned tier,
escalate one tier (Haiku → Sonnet → Opus) and note why in the commit message.

### Task flags

- **[HW]** — requires physical DE10-Nano hardware; a human must execute the hardware step.
  The assigned model prepares artifacts, drives debugging from captured logs, and writes up
  results, but must **stop and hand off** at the physical step.
- **[NET]** — requires downloading external sources (kernel.org, GitHub, morrownr repos).
- **Size:** S (< half day), M (a day-ish), L (multi-day / iterative).

### Standing rules (apply to every task)

1. **No binaries in git. Ever.** Reference materials (stock image, tarballs) live in an
   untracked `work/` directory (add to `.gitignore` in P0.1).
2. Every kernel patch carries a provenance header: origin commit/URL, original author,
   upstream status, and a `Signed-off-by`. `docs/patch-provenance.md` is updated in the
   same commit that adds or modifies a patch.
3. Every task that changes build output ends with a successful `make` of the affected
   stage (or a documented reason it cannot run in the current environment).
4. Docs are updated in the same PR as the code they describe.
5. Kernel patches are GPLv2 (they modify the kernel); Buildroot-external-tree code follows
   the repo license. Note the layering in the repo README (P0.1).
6. Commit messages explain *why*; PRs reference task IDs from this file.
7. Check the box here (`- [x]`) only after acceptance criteria are verified, and commit
   the checkbox change with the work.

---

## A. Plan amendments (corrections discovered in review)

These have been folded into `PLAN.md` v2; they are retained here as the rationale record.
Each is cross-referenced from the task that implements it.

- **A1 — The initramfs mechanism in §5 is wrong as specified.**
  `BR2_TARGET_ROOTFS_INITRAMFS` embeds the *entire target rootfs* (~300 MB) into the
  kernel image — it cannot produce a ~200 KB shim. Use a **two-stage build**: a second,
  minimal Buildroot config (static BusyBox, `BR2_TARGET_ROOTFS_CPIO`) produces a tiny
  `rootfs.cpio`; the main build's kernel consumes it via `CONFIG_INITRAMFS_SOURCE`.
  The initramfs **must** be embedded in the zImage because the stock U-Boot boot command
  (kept byte-identical per §8) does not load a separate initrd. → P1.10
- **A2 — The initramfs `/init` must parse the kernel cmdline, not hardcode devices.**
  Since U-Boot is unchanged, the cmdline will still contain `root=$mmcroot
  loop=linux/linux.img ro rootwait`. `/init` must parse `root=` (the FAT/exFAT data
  partition — which existing `u-boot.txt` files may override, e.g. USB boot) and `loop=`
  (image path) from `/proc/cmdline`, implement `rootwait` semantics as a retry loop, and
  mount the data partition as **vfat or exfat** (MiSTer supports exFAT SD cards — both
  filesystems plus NLS codepages must be built-in, not modules). Failure path: drop to a
  serial rescue shell with a diagnostic banner. → P1.10
- **A3 — The appended-DTB boot chain is unstated in the plan.** Stock U-Boot loads a
  concatenated `zImage_dtb` (zImage + DTB) and passes bootargs via ATAGs. The kernel
  config needs `CONFIG_ARM_APPENDED_DTB=y` and (pending P0.8 confirmation)
  `CONFIG_ARM_ATAG_DTB_COMPAT=y`, and post-image must produce the concatenation. → P0.8,
  P1.3, P1.11
- **A4 — `/dev/mem` restrictions will silently break the FPGA path.** `fpga_io.cpp`
  mmaps hardcoded physical addresses. The kernel config must set `CONFIG_DEVMEM=y`,
  `CONFIG_STRICT_DEVMEM=n`, `CONFIG_IO_STRICT_DEVMEM=n`. Modern defconfigs enable
  STRICT_DEVMEM by default. → P1.3
- **A5 — Moving Realtek/xone to module packages breaks the stock zero-module
  convention.** The image then needs `kmod`, `depmod` at build time, a hotplug/module
  autoload mechanism (mdev or udev rules), and a firmware inventory (`/lib/firmware`
  selections; xone additionally requires a proprietary firmware blob with redistribution
  constraints). None of this is in the plan. → P3.3, P0.3
- **A6 — The Python major-version jump is a userland ABI risk the plan ignores.**
  `Downloader_MiSTer` and many community scripts execute with the *on-device* Python.
  Stock ships 3.9 (EOL); Buildroot 2026.02 ships 3.13+. Compatibility must be tested,
  not assumed. → P3.9
- **A7 — "ABI smoke test on a hardware runner on every CI build" is not realistic at
  P0.** QEMU has no Cyclone V SoC machine model. Split validation: (a) CI runs static
  ABI checks + qemu-user dynamic-link tests of the stock `MiSTer` binary against the new
  rootfs + qemu-system tests of the initramfs logic on a generic ARM machine; (b) real
  hardware gates each *release*, manually at first, automated later via an optional HIL
  rig (USB-SD-mux + power relay + serial capture). → P2.8, P1.12, P4.11
- **A8 — The `LinuxUpdater` contract must be verified from source, not assumed.** The
  update is applied by the *currently installed* (old) system: 7z layout, extraction
  tooling present on the stock image, MD5 verification, version comparison semantics
  (inequality, not ordering), and the reboot flow all constrain our artifact. → P0.6
- **A9 — Reproducible ext4 needs explicit pinning.** 2026-era `mke2fs` defaults enable
  features and random seeds (UUID, hash_seed, timestamps) that break bit-for-bit
  reproducibility and could interact with older tooling. Pin filesystem features, UUID,
  and `SOURCE_DATE_EPOCH`; verify with a double-build comparison in CI. → P2.5, P4.3

---

## Phase 0 — Bootstrap & Recon

Exit criterion: patch triage and ABI contract complete and human-reviewed (P0.9).

- [ ] **P0.1 — Repository scaffolding** — [HAIKU] — Size S — Depends: —
  Create the §6 directory skeleton (empty dirs with `.gitkeep`), `.gitignore` (must
  exclude `work/`, `dl/`, `output*/`, `*.img`, `*.7z`), `.editorconfig`, and a README
  stub stating goals, license layering (GPLv3 repo / GPLv2 kernel patches / upstream
  package licenses), and a pointer to `PLAN.md` + this file.
  **Done when:** `git status` clean after scaffold commit; README renders; no binary or
  generated path can be accidentally committed (verify with a dry-run `git add` of a
  dummy `work/test.img`).

- [ ] **P0.2 — Acquire reference materials** — [SONNET] [NET] — Size S — Depends: P0.1
  Into untracked `work/`: clone `MiSTer-devel/Linux-Kernel_MiSTer` (the 5.15 fork),
  `MiSTer-devel/Main_MiSTer` (need `fpga_io.cpp`, `brightness.cpp`, ioctl users),
  `MiSTer-devel/Downloader_MiSTer`, `MiSTer-devel/U-Boot_MiSTer`; download the current
  `release_YYYYMMDD.7z` from `MiSTer-devel/SD-Installer-Win64_MiSTer` (commit-pinned
  URL); extract it and loop-mount `linux.img` read-only at `work/stockroot/`.
  **Done when:** `work/manifest.txt` lists every acquired artifact with URL, commit/tag,
  and SHA-256; stock rootfs is browsable at `work/stockroot/`.

- [ ] **P0.3 — Stock image inventory** — [SONNET] — Size M — Depends: P0.2
  Produce `docs/stock-inventory/`: (a) all shared libs with SONAMEs and versions;
  (b) all binaries with their `NEEDED` sets; (c) `/etc` configs verbatim-listed
  (init scripts S01–S99, inittab, fstab, smb.conf, wpa_supplicant, sshd_config, …);
  (d) `/lib/firmware` contents (per A5); (e) BusyBox applet list; (f) kernel config via
  `extract-ikconfig` on the stock zImage (fall back to the fork repo's
  `MiSTer_defconfig` if not embedded); (g) disk usage by top-level dir.
  **Done when:** each list is a checked-in text/markdown file with a generation script
  in `scripts/inventory/` so it can be re-run against any image.

- [ ] **P0.4 — Kernel commit triage (classes A–F)** — [OPUS] — Size L — Depends: P0.2
  Enumerate every commit in the 5.15 fork not in upstream `v5.15.1`. For each: class
  (A–F per §4.1), files touched, original author/origin, upstream status in v6.18
  (cite the upstream commit if merged), and disposition (carry / drop / re-source).
  Deliver `docs/patch-provenance.md` with a summary table plus one subsection per
  carried patch.
  **Done when:** every fork commit is accounted for; each "drop — upstream" entry cites
  the mainline commit or subsystem; the carried set maps 1:1 to the planned
  `linux-patches/` filenames in §6.

- [ ] **P0.5 — ABI contract document** — [OPUS] — Size M — Depends: P0.2, P0.3
  Expand §3 into `docs/abi-contract.md` with evidence: `readelf -d` output for the stock
  `MiSTer` binary; the `MiSTer_fb` ioctl numbers/structs extracted from source; the
  physical addresses and access patterns from `fpga_io.cpp`; every `/dev` node
  Main_MiSTer opens (grep the source); `/media/fat` layout assumptions;
  `MiSTer.version` format; init-script naming contract. Mark each item MUST / SHOULD.
  **Done when:** a reviewer can verify any single claim from the cited evidence without
  re-deriving it; doc cross-links P0.4 for kernel-side items.

- [ ] **P0.6 — Downloader `LinuxUpdater` contract (A8)** — [SONNET] — Size S — Depends: P0.2
  Read `Downloader_MiSTer` source. Document in `docs/downloader-contract.md`: exact
  db.json `linux` schema; hash algorithm (MD5) and what it covers; version comparison
  semantics; where the 7z is downloaded, what extracts it (tool must exist on the *old*
  image), expected internal layout (`files/linux/…`), the apply/reboot flow, failure
  handling, and the multi-db "only 1 can be processed" ordering rule with the exact
  `downloader.ini` incantation for users.
  **Done when:** doc quotes the relevant source lines (file:line at a pinned commit) for
  every claim; includes a worked example db.json entry.

- [ ] **P0.7 — Package mapping** — [SONNET] — Size M — Depends: P0.3
  Map every stock SONAME and every user-facing binary to a Buildroot 2026.02 package
  (name + version). Flag: packages Buildroot lacks (candidates for `package/` in our
  tree), version jumps with known breaking changes (Samba 4.14→4.2x config syntax,
  OpenSSH policy changes, Python per A6), and anything in stock that should be dropped.
  Deliver `docs/package-manifest.md`.
  **Done when:** zero unmapped SONAMEs from the ABI contract; every gap has a
  disposition; the resulting `BR2_PACKAGE_*` list is included ready to paste.

- [ ] **P0.8 — Boot chain analysis (A3)** — [OPUS] — Size M — Depends: P0.2
  From `U-Boot_MiSTer` source (and `strings` on the stock `uboot.img`): extract the
  embedded boot command and environment; confirm how `zImage_dtb` is loaded and booted
  (`bootz` args), whether bootargs travel via ATAGs or a DT chosen node, the
  `u-boot.txt` env-from-FAT mechanism, and the `$mmcroot`/`$v` variable defaults.
  Deliver `docs/boot-chain.md` with the exact kernel-config implications
  (`ARM_APPENDED_DTB`, `ARM_ATAG_DTB_COMPAT`, cmdline handling) as a checklist P1.3
  consumes.
  **Done when:** the boot command is quoted verbatim from source; every kernel-config
  implication is stated as a testable assertion.

- [ ] **P0.9 — Phase 0 review gate** — [HAIKU] + human — Size S — Depends: P0.3–P0.8
  Assemble a one-page summary of Phase 0 findings, open questions, and any plan
  amendments beyond A1–A9. Human reviews and approves before Phase 1 starts.
  **Done when:** summary committed as `docs/phase0-review.md` with human sign-off noted.

---

## Phase 1 — Buildroot skeleton & kernel

Exit criterion: 6.18 LTS kernel built by Buildroot from a pristine kernel.org tarball
boots to a serial console on real hardware (P1.13).

- [ ] **P1.1 — BR2_EXTERNAL skeleton** — [SONNET] — Size S — Depends: P0.9
  `external.desc`, `external.mk`, `Config.in`, `configs/mister_de10nano_defconfig`
  (minimal, builds nothing yet), plus a top-level `Makefile`/script that downloads the
  pinned Buildroot 2026.02.x tarball, verifies its SHA-256, unpacks to `work/buildroot/`,
  and invokes it with `BR2_EXTERNAL` set. Buildroot is never vendored (G4/§6).
  **Done when:** `make menuconfig`-equivalent runs against the external tree from a
  clean checkout with only `work/` populated by the script.

- [ ] **P1.2 — Toolchain & base defconfig** — [SONNET] [NET] — Size M — Depends: P1.1
  Set `armv7-a`/Cortex-A9/NEON-VFPv3/EABIhf/glibc. Evaluate internal toolchain vs a
  Bootlin external toolchain (build time vs reproducibility vs glibc version control);
  document the choice in `docs/decisions/0001-toolchain.md`. Produce a minimal booting
  rootfs config (BusyBox only).
  **Done when:** `make` completes producing `rootfs.tar`; a hello-world cross-compiled
  binary runs under `qemu-arm`; decision doc explains the trade-off.

- [ ] **P1.3 — Kernel config derivation (A3, A4)** — [OPUS] — Size L — Depends: P0.8, P1.1
  Port the stock `MiSTer_defconfig` (5.15) to 6.18 via `olddefconfig`, then audit every
  dropped/renamed symbol. Explicitly assert and document: `DEVMEM=y`,
  `STRICT_DEVMEM=n`, `IO_STRICT_DEVMEM=n` (A4); `ARM_APPENDED_DTB` (+`ATAG_DTB_COMPAT`
  per P0.8) (A3); built-in (not module): ext4, vfat, exfat, loop
  (`BLK_DEV_LOOP`), NLS codepages, dwc2, usb-storage, HID core; module support ON with
  module signing OFF (A5); cifs, ntfs3, iso9660/udf per stock inventory; cpufreq
  governors matching stock. Deliver `board/mister/de10nano/linux.config`
  (savedefconfig) + `docs/kernel-config-deltas.md`.
  **Done when:** kernel builds from a pristine kernel.org 6.18.y tarball with this
  config; delta doc explains every intentional divergence from both the stock config and
  the 6.18 `multi_v7_defconfig` baseline.

- [ ] **P1.4 — Forward-port `MiSTer_fb`** — [OPUS] — Size L — Depends: P0.4, P1.3
  Port `drivers/video/fbdev/MiSTer_fb.c` from 5.15 to 6.18 as
  `0001-fbdev-add-MiSTer_fb-driver.patch`. The **ioctl ABI and `/dev/fb0` semantics must
  be bit-identical** (P0.5 contract). Expect fbdev API churn (fb_ops changes, aperture
  helpers, deferred-io changes).
  **Done when:** patch applies clean to the pinned 6.18.y; driver compiles with no
  warnings; a provenance header cites the origin commit; ioctl numbers verified
  unchanged against the contract doc.

- [ ] **P1.5 — Forward-port `MiSTer-audio-spi`** — [OPUS] — Size M — Depends: P0.4, P1.3
  Port `sound/drivers/MiSTer-audio-spi.c` to 6.18 as `0002-…`. ALSA API churn expected.
  Card/device name exposed to userland must match stock (Main_MiSTer opens it by name).
  **Done when:** applies clean, compiles clean, provenance header present, ALSA card
  name verified against stock inventory.

- [ ] **P1.6 — Forward-port Cyclone V cpufreq/overclock** — [OPUS] — Size M — Depends: P0.4, P1.3
  Port the overclock/cpufreq driver as `0003-…`. Preserve the sysfs interface stock
  scripts/Main use (verify against P0.5).
  **Done when:** applies clean, compiles clean, sysfs paths documented and matching.

- [ ] **P1.7 — MiSTer DTS patch (§4.1a)** — [OPUS] — Size L — Depends: P0.4, P1.3
  Author `0004-dts-de10nano-MiSTer.patch` on top of mainline
  `socfpga_cyclone5_de10nano.dts`: enable `usb1`, `fpga_bridge0/1/2`, `spi0`
  (MiSTer,spi-audio), `spi1` (spidev node, coordinated with P1.8), `i2c2`, `uart1`
  (DMA props deleted), `MiSTer_fb` node (`reg = <0x22000000 0x800000>`, IRQ 40),
  gmac1 skews (`rgmii`, `txc-skew-ps`/`rxc-skew-ps`, `max-frame-size = <3800>`),
  i2c-gpio RTC bus (pcf8563/m41t81/mcp7941x), `gpio-leds` `hps_led0`,
  `regulator_3_3v`, mmc0 vmmc/vqmmc. Diff every value against the stock fork's DTS,
  not from memory.
  **Done when:** `dtbs` build passes with no new warnings from `dtc`; a node-by-node
  comparison table (stock DTS vs mainline vs ours) is committed to
  `docs/dts-comparison.md`.

- [ ] **P1.8 — spidev binding fix (§13 hazard)** — [SONNET] — Size S — Depends: P1.7
  Resolve the `altspi` catch-all binding: prefer changing the DTS compatible to one
  modern spidev accepts; only patch spidev's match table (`0005-…`) if no acceptable
  compatible exists. Document the choice.
  **Done when:** `/dev/spidev1.0` creation path is explained in the patch/DTS commit
  message; no `spidev: probed from DT without matching compatible` style warning
  expected (assert in P1.13 boot log).

- [ ] **P1.9 — Residual HID & quirk patches (classes D, F)** — [SONNET] — Size M — Depends: P0.4, P1.3
  Port the carried set: GunCon 2/3, Fanatec, Flydigi Vader, remaining xpad IDs,
  usb-storage Realtek CD-ROM blacklist, mmc LED, btusb VID/PIDs — *only* those P0.4
  confirmed absent from 6.18. Number them `0010+`/`0020+` per §6. Escalate any
  individual port to [OPUS] if the upstream driver was restructured.
  **Done when:** all patches apply and compile clean; each has a provenance header;
  P0.4's table updated with final patch filenames.

- [ ] **P1.10 — Initramfs: design & implement (A1, A2)** — [OPUS] — Size L — Depends: P0.8, P1.2
  Implement the two-stage build (A1): `configs/mister_initramfs_defconfig` (static
  BusyBox, cpio output, ~hundreds of KB) consumed by the main kernel via
  `CONFIG_INITRAMFS_SOURCE`. Write `/init` per A2: parse `root=`/`loop=` from
  `/proc/cmdline`, rootwait retry loop, vfat/exfat mount, `losetup -r`, ro mount of the
  loop device, `mount --move` of the data partition to `/newroot/media/fat`,
  `exec switch_root`; on any failure print a diagnostic banner and drop to a serial
  shell. Wire the two-stage sequencing into the top-level Makefile from P1.1.
  **Done when:** kernel image embeds the cpio; P1.12's QEMU test passes; `/init` is
  shell-checked (`shellcheck`) and under 200 lines; design recorded in
  `docs/decisions/0002-initramfs.md`.

- [ ] **P1.11 — `zImage_dtb` assembly (A3)** — [SONNET] — Size S — Depends: P1.3, P1.7
  `post-image.sh` step: concatenate zImage + our DTB into `zImage_dtb` exactly as stock
  U-Boot expects (per P0.8). Sanity-check size against U-Boot's load regions.
  **Done when:** artifact produced on every build; a scripted check confirms the DTB
  magic at the expected offset and total size within the documented budget.

- [ ] **P1.12 — QEMU initramfs logic test (A7)** — [SONNET] — Size M — Depends: P1.10
  CI-runnable test: build the same initramfs cpio into a generic ARM kernel
  (`qemu-system-arm -M virt` or similar), attach a crafted disk image containing a
  FAT partition with `linux/linux.img` (a tiny ext4 with a marker `/sbin/init`), boot
  with the stock-shaped cmdline, and assert the marker init runs. Cover: exFAT variant,
  missing image (must reach rescue shell), `root=` override, slow-device rootwait.
  **Done when:** `scripts/test-initramfs.sh` runs green locally and in CI (wired in
  P4.1); all four cases asserted.

- [ ] **P1.13 — [HW] First hardware boot** — human + [OPUS] — Size L — Depends: P1.4–P1.12
  Human writes `zImage_dtb` (+ stock `uboot.img`, stock FAT layout, our tiny test
  `linux.img`) to an SD card, captures the full serial boot log. Model analyzes the log,
  drives fixes, iterates. Assert: U-Boot loads our kernel unmodified; initramfs finds
  and switches root; serial getty on ttyS0; USB enumerates; `/dev/spidev1.0`,
  `/dev/fb0`, ALSA card, FPGA bridge sysfs, gmac link all present.
  **Done when:** boot log with all assertions checked is committed to
  `docs/testlogs/p1-first-boot.md`. **This is the Phase 1 exit gate.**

---

## Phase 2 — Rootfs

Exit criterion: the **unmodified stock `MiSTer` binary reaches the menu** on hardware
(P2.9).

- [ ] **P2.1 — Full package set** — [SONNET] — Size M — Depends: P0.7, P1.2
  Apply P0.7's `BR2_PACKAGE_*` list to the defconfig. Resolve selection conflicts and
  missing deps. Confirm every ABI-contract SONAME (§3) is produced at the same major
  version.
  **Done when:** full rootfs builds; P2.2's checker passes.

- [ ] **P2.2 — SONAME parity checker** — [SONNET] — Size S — Depends: P2.1
  `scripts/check-abi.sh`: (a) verify every SONAME from `docs/abi-contract.md` exists in
  the built rootfs at the same major version; (b) run the stock `MiSTer` binary's
  dynamic-link resolution against the new rootfs via `qemu-arm` +
  `LD_TRACE_LOADED_OBJECTS` style check; fail on any unresolved symbol/library.
  **Done when:** script exits nonzero on a deliberately broken rootfs (test that) and
  zero on the real one; wired into CI later (P4.1).

- [ ] **P2.3 — Rootfs overlay: init & config parity** — [SONNET] — Size L — Depends: P0.3, P2.1
  Recreate stock init behavior in `rootfs-overlay/`: S01–S99 scripts (same names, same
  ordering contract), inittab (getty on ttyS0 115200), fstab (ro root, tmpfs for
  /tmp,/var,/run, `/media/fat` mountpoint), hostname `MiSTer`, profile, network config,
  and the USB-storage automount mechanism found in P0.3 (mdev/usbmount — match stock
  behavior of `/media/usb0-7`). Diverge from stock only with a documented reason.
  **Done when:** a diff report `docs/init-parity.md` lists every stock init script with
  status: identical / adapted (why) / dropped (why).

- [ ] **P2.4 — Read-only root audit** — [SONNET] — Size M — Depends: P2.3
  Boot-test (QEMU-user chroot where possible, hardware in P2.9) that every daemon and
  script functions with `/` mounted ro: enumerate writable-path expectations
  (`/etc/resolv.conf`, samba state, ssh host keys, bluetooth pairing db, wpa state) and
  route each to tmpfs or `/media/fat` exactly as stock does.
  **Done when:** `docs/writable-paths.md` lists every writable path with its
  destination; no daemon writes to `/` at runtime.

- [ ] **P2.5 — Image generation, reproducible (A9)** — [SONNET] — Size M — Depends: P2.1
  `genimage.cfg` + mke2fs config: 512 MiB ext4, volume label `rootfs`, **pinned**
  filesystem feature set, fixed UUID, `SOURCE_DATE_EPOCH` honored, deterministic
  file ordering. Enable `BR2_REPRODUCIBLE`.
  **Done when:** two clean builds from the same commit produce byte-identical
  `linux.img` (verify locally; CI job in P4.3); image mounts ro on the 6.18 kernel.

- [ ] **P2.6 — `post-build.sh`: version stamping** — [HAIKU] — Size S — Depends: P2.5
  Write `MiSTer.version` (6-char `YYMMDD`) into the release file tree per the P0.6
  contract, and an `/etc/os-release` identifying this distribution + build commit.
  **Done when:** both files present in output with correct format; format asserted by a
  test in `scripts/`.

- [ ] **P2.7 — Size budget report** — [HAIKU] — Size S — Depends: P2.1
  Report rootfs usage by package (Buildroot's `make graph-size` + a markdown summary).
  Assert ≥ 15 % free in the 512 MiB image (§11 budget); flag the top 10 growth items vs
  stock.
  **Done when:** `docs/size-budget.md` committed; CI-runnable check script asserts the
  15 % floor.

- [ ] **P2.8 — qemu-user smoke of the stock binary (A7)** — [SONNET] — Size M — Depends: P2.2
  In CI-runnable form: chroot into the built rootfs under `qemu-arm`, execute the stock
  `MiSTer` binary, and assert it advances past dynamic linking and early init (it will
  fail at `/dev/mem`/FPGA access — capture and whitelist that exact failure signature).
  Any earlier failure (linker, missing lib, glibc symbol) is a hard fail.
  **Done when:** test distinguishes "died at FPGA access (expected)" from "died earlier
  (regression)" and is wired into `scripts/`.

- [ ] **P2.9 — [HW] Stock `MiSTer` binary reaches the menu** — human + [OPUS] — Size L — Depends: P1.13, P2.1–P2.8
  Full image on hardware with a real `/media/fat` populated from `Distribution_MiSTer`.
  Assert: menu appears on HDMI; boot-to-menu time ≤ stock (measure both); free RAM at
  menu ≥ stock; a sample core loads and runs; framebuffer, audio, and input all work.
  Model triages from serial logs and `MiSTer` stderr.
  **Done when:** results + timings committed to `docs/testlogs/p2-menu.md`. **This is
  the Phase 2 exit gate and the project's central bet — fail fast here.**

---

## Phase 3 — Parity

Exit criterion: hardware matrix (§11) green (P3.13).

- [ ] **P3.1 — Realtek WiFi module packages** — [SONNET] [NET] — Size L — Depends: P2.1
  Buildroot `kernel-module` packages under `package/` for `rtl8188eu`, `rtl8188fu`,
  `rtl8812au`, `rtl8821au`, `rtl8821cu`, `rtl88x2bu`, each sourced from the morrownr
  upstream (commit-pinned, hash-verified). Do not vendor code (§4.1 class E).
  **Done when:** all six build against the pinned 6.18.y; `.ko`s land in
  `/lib/modules/$(uname -r)/`; each package has a hash file and license entry.

- [ ] **P3.2 — xone package** — [SONNET] [NET] — Size M — Depends: P3.1
  Package `xone` similarly. Handle its firmware requirement explicitly: document the
  redistribution status; if not redistributable, implement the same on-device fetch
  mechanism stock uses (check P0.3 inventory for how stock handles it today).
  **Done when:** module builds; firmware path documented in
  `docs/decisions/0003-xone-firmware.md`; behavior matches stock.

- [ ] **P3.3 — Module loading & firmware infra (A5)** — [SONNET] — Size M — Depends: P3.1
  Add `kmod`, run `depmod` at image build, hotplug autoload via mdev (or udev if stock
  parity demands — per P0.3), and populate `/lib/firmware` from the linux-firmware
  package filtered to the P0.3 inventory plus new module needs.
  **Done when:** plugging a supported dongle (verified on HW in P3.13) autoloads the
  right module; firmware list documented; image size impact recorded in P2.7's report.

- [ ] **P3.4 — WiFi userland parity** — [SONNET] — Size S — Depends: P3.3
  `wpa_supplicant` config/paths matching stock so `wifi.sh` and existing user configs
  work unchanged.
  **Done when:** `wifi.sh` from the current Distribution runs unmodified against the
  new rootfs (static analysis + [HW] confirmation in P3.13).

- [ ] **P3.5 — Bluetooth parity** — [SONNET] — Size M — Depends: P2.1
  bluez package (library must provide `libbluetooth.so.3`), init script, pairing-state
  persistence per P2.4.
  **Done when:** SONAME check passes; `bluetoothd` starts on ro root; pairing DB
  persists across reboot ([HW] in P3.13).

- [ ] **P3.6 — Samba parity** — [SONNET] — Size M — Depends: P2.3
  Modern Samba with stock-equivalent `smb.conf` (audit 4.14 → current syntax/behavior
  changes: SMB1 defaults, guest access, unix extensions). Preserve share layout and
  discoverability behavior users expect.
  **Done when:** config diff documented; `smbd`/`nmbd` (or modern equivalents) start on
  ro root; share is browsable from Windows/macOS ([HW]/LAN check in P3.13).

- [ ] **P3.7 — SSH & FTP parity** — [SONNET] — Size S — Depends: P2.3
  Match stock daemon choices (per P0.3 inventory), host-key persistence per P2.4, and
  stock auth behavior (document the default-credential posture; keep parity, note the
  risk in the FAQ rather than silently hardening).
  **Done when:** both daemons start on ro root; keys persist; behavior documented.

- [ ] **P3.8 — MIDI / MT-32 parity** — [SONNET] — Size S — Depends: P2.1
  fluidsynth/mt32 userland per P0.3 inventory; ALSA seq config as stock.
  **Done when:** packages present at compatible versions; ALSA MIDI device list matches
  stock ([HW] confirmation in P3.13).

- [ ] **P3.9 — Python & Downloader compatibility (A6)** — [SONNET] — Size M — Depends: P2.1
  Run `Downloader_MiSTer`'s test suite (it has one) under the target Python via
  qemu-user chroot. Smoke-test a sample of popular community scripts (update_all, etc.)
  for 3.9→3.13 breakage (removed stdlib modules, syntax). Report incompatibilities
  upstream rather than pinning old Python; document any that block.
  **Done when:** Downloader suite green on-target-Python; findings in
  `docs/python-compat.md`.

- [ ] **P3.10 — Network filesystem client parity** — [HAIKU] — Size S — Depends: P1.3, P2.1
  `mount.cifs` (cifs-utils) + NFS client utils per stock inventory, so community
  cifs/NFS mount scripts run unchanged. Kernel side was asserted in P1.3.
  **Done when:** a cifs and an nfs mount succeed from the running image (loop-back test
  acceptable pre-hardware).

- [ ] **P3.11 — RTC parity** — [SONNET] — Size S — Depends: P1.7, P2.3
  hctosys/init integration for the i2c-gpio RTC add-on; graceful no-op without the
  board.
  **Done when:** boot with no RTC shows no errors; with RTC ([HW] in P3.13) system time
  is set from it.

- [ ] **P3.12 — CI-runnable parity test suite** — [SONNET] — Size M — Depends: P3.1–P3.11
  Consolidate P2.2/P2.8/P1.12 and per-service start checks into one
  `scripts/ci-tests.sh` (chroot + qemu-user + qemu-system where applicable) so
  regressions are caught without hardware.
  **Done when:** single command runs the full non-hardware suite green from a fresh
  build.

- [ ] **P3.13 — [HW] Full hardware matrix** — human + [SONNET] — Size L — Depends: P3.1–P3.12
  Execute §11's matrix: boot time, HDMI/analog/VGA, controller zoo, BT pairing, each
  Realtek dongle, Samba/SSH/FTP from real clients, MIDI/MT-32, save states, CHD cores,
  exFAT `MiSTer_Data`, `update.sh`/`wifi.sh`/popular scripts, SD spread. Model prepares
  the run sheet, human executes, model compiles results and files defects.
  **Done when:** `docs/testlogs/p3-matrix.md` shows every row pass/fail with notes;
  all fails triaged into tasks. **Phase 3 exit gate: all green or accepted-with-issue.**

---

## Phase 4 — Release engineering, CI & distribution

Exit criterion: beta users successfully opt in via `db.json` and can roll back (P4.10).

- [ ] **P4.1 — CI build workflow** — [SONNET] — Size L — Depends: P1.10, P2.5
  `.github/workflows/build.yml`: pinned container image (digest, not tag); two-stage
  build (initramfs config, then main); cache `dl/` and ccache (mind the 10 GB GitHub
  cache ceiling — evict policy or external mirror documented); run
  `scripts/ci-tests.sh` (P3.12) and the ABI checker (P2.2); upload build artifacts on
  every push; hard timeout budget documented.
  **Done when:** clean-cache and warm-cache runs both green; warm run < 60 min or the
  budget is re-documented with rationale.

- [ ] **P4.2 — SBOM / legal-info** — [HAIKU] — Size S — Depends: P4.1
  `make legal-info` on every build; archive as an artifact; include in releases.
  **Done when:** `legal-info.tar.gz` attached to CI runs; spot-check that kernel,
  glibc, and one morrownr package appear with correct licenses.

- [ ] **P4.3 — Reproducibility verification (A9)** — [SONNET] — Size M — Depends: P2.5, P4.1
  CI job: build twice from the same commit (separate runners), compare
  `linux.img`/`zImage_dtb` hashes; fail on mismatch. Document any residual
  nondeterminism and its fix in `docs/reproducibility.md`.
  **Done when:** double-build job green on two consecutive commits.

- [ ] **P4.4 — Release workflow + provenance** — [SONNET] — Size M — Depends: P4.1–P4.3
  Tag-triggered workflow producing GitHub Release assets exactly per §9:
  `release_YYYYMMDD.7z` (internal layout per P0.6 contract), `linux.img`, `zImage_dtb`,
  `SHA256SUMS`, `buildroot.config`, `linux.config`, `legal-info.tar.gz`. Attach GitHub
  artifact attestations (`actions/attest-build-provenance`) for the image assets.
  Verify the 7z extracts with the stock image's extraction tool (P0.6).
  **Done when:** a draft release from a test tag contains all assets; attestation
  verifies with `gh attestation verify`; 7z layout byte-compared against the contract.

- [ ] **P4.5 — db.json generation & publishing** — [SONNET] — Size M — Depends: P0.6, P4.4
  `publish-db.yml`: on release, regenerate `db.json` with the `linux` entry (MD5, size,
  release-asset URL, `YYMMDD` version) per the P0.6 schema; publish via GitHub Pages
  (stable URL). Include a schema self-check against a vendored copy of the Downloader's
  expectations.
  **Done when:** published db.json passes the Downloader's own validation (run it in
  CI); URL is stable across releases.

- [ ] **P4.6 — Renovate onboarding (final pipeline-hardening step)** — [SONNET] — Size M — Depends: P4.1, P4.4
  **Sequence after P4.8/P4.9, immediately before beta launch** — automate a pipeline
  only once it is stable and trusted (PLAN.md §9). Onboard Renovate and configure
  `renovate.json` to manage: the Buildroot 2026.02.x tarball version + SHA-256
  (custom/regex manager over the pin file from P1.1), morrownr package commit pins (git
  datasource), CI container image digests, and GitHub Actions versions. Every Renovate
  PR must trigger the full CI suite (build, patch-apply, ABI checks, reproducibility).
  Automerge stays OFF — a human reviews green PRs.
  **Done when:** a real or synthetic Renovate PR for a Buildroot point release opens
  with passing CI; the pin file's regex manager is covered by a Renovate config test.

- [ ] **P4.7 — Kernel 6.18.y bumps via Renovate** — [SONNET] — Size M — Depends: P4.6
  Add a Renovate custom datasource over kernel.org's `releases.json` that bumps
  `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` and the tarball hash together in one PR. CI
  proving the carried patches still apply is the whole point — this is the §13
  sustainability mitigation, mechanized.
  **Done when:** a synthetic 6.18.y bump PR opens correctly with passing CI and a
  changelog snippet of upstream fixes in the PR body.

- [ ] **P4.8 — User documentation** — [SONNET] — Size M — Depends: P0.6, P4.5
  `docs/user/`: onboarding (the exact `downloader.ini` edit **including the multi-db
  ordering rule** — this determines whether onboarding is one line or a support
  thread, §10); prominent rollback runbook (remove db line, re-run Downloader);
  serial-console recovery guide; FAQ covering the default-credential posture (P3.7),
  what changed vs stock, and how to report bugs with logs.
  **Done when:** a naive-user walkthrough of onboarding and rollback has been executed
  verbatim from the docs by someone who didn't write them ([HW]-adjacent, human).

- [ ] **P4.9 — Community & governance files** — [HAIKU] — Size S — Depends: P0.1
  Full README (goals, status, quick links), `CONTRIBUTING.md` (patch provenance rules,
  standing rules from this file, DCO), issue templates (bug report requiring
  `MiSTer.version`, dmesg, serial log; hardware-matrix report template), beta-tester
  guide stub for P4.10.
  **Done when:** all files render; issue template enforces the required fields.

- [ ] **P4.10 — Beta launch** — human + [HAIKU] — Size M — Depends: P3.13, P4.4–P4.9
  Publish the db.json announcement per plan §12 P4; recruit testers; triage rota;
  weekly status notes. Model drafts announcements and digests feedback; human posts and
  makes ship/hold calls.
  **Done when:** sustained opt-in use with zero P1-severity bugs over an agreed window
  (define the window in the launch note). **Phase 4 exit gate.**

- [ ] **P4.11 — Optional: HIL rig design (A7)** — [OPUS] design, human build — Size L — Depends: P2.9
  Design doc for a hardware-in-the-loop runner: USB-SD-mux, power control, serial
  capture, boot-to-menu assertion, wired as a self-hosted runner gating releases (not
  every push). Include cost, failure modes, and maintenance owner. Build is a human
  decision after Phase 3.
  **Done when:** `docs/decisions/0004-hil-rig.md` reviewed; build go/no-go recorded.

---

## Phase 5 — U-Boot (deferred; do not start before Phase 4 exit)

Per §8: highest blast radius, lowest user benefit. Opt-in, separate from `linux.img`
updates, gated on recovery documentation.

- [ ] **P5.1 — Mainline U-Boot port design** — [OPUS] — Size L — Depends: P4.10
  Port plan for `socfpga_de10_nano_defconfig` + `u-boot.txt` env-from-FAT (the
  `ethaddr` mechanism `mr-fusion` depends on), FPGA/bridge init, boot script parity —
  all against the P0.8 boot-chain doc. `uboot-patches/` mirrors the kernel model.
  **Done when:** design doc enumerates every stock U-Boot behavior with a port
  disposition, and defines the brick-recovery procedure.

- [ ] **P5.2 — U-Boot build + opt-in packaging** — [SONNET] — Size L — Depends: P5.1
  `BR2_TARGET_UBOOT` + `u-boot-with-spl.sfp`; shipped as a separate, explicitly opt-in
  artifact never included in the default `release_*.7z`.
  **Done when:** artifact builds reproducibly; release plumbing keeps it out of the
  default update path (test the Downloader flow to prove it).

- [ ] **P5.3 — [HW] U-Boot hardware matrix & recovery drill** — human + [OPUS] — Size L — Depends: P5.2
  Boot matrix across board revisions and SD cards; execute the documented recovery
  procedure from an actually-bricked state at least once before any user sees this.
  **Done when:** matrix + a successful real recovery drill logged in
  `docs/testlogs/p5-uboot.md`.

---

## B. Standalone-value checkpoint (plan §14)

If the project stalls, these must still be published — they are complete after Phase 1:
`docs/abi-contract.md` (P0.5), `docs/patch-provenance.md` (P0.4), and the bootable
6.18 kernel recipe (P1.13). Tag that state `milestone/standalone-value` so it is
findable even if nothing else ships.

## C. Sustainability gate (plan §13, final risk)

Before P4.10 (beta launch), a named human maintainer must commit in writing (in the
README) to tracking 6.18.y stable through its EOL (Dec 2028), with the Renovate
automation (P4.6/P4.7) as the mechanism. **If no one signs, stop at the §14 deliverables
and publish those** — a stale fork is worse than no fork.
