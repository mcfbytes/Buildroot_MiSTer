# MiSTer Linux Modernization — Ultracode Task List

Companion to `PLAN.md` **v3**, which has been **amended by the Phase 0 recon findings**
(`docs/phase0-review.md`). v2 said "the plan is authoritative and current — do not
're-correct' it"; Phase 0 then checked it against the *source* and a number of its claims
did not survive. Corrections are marked **[P0]** inline in both files and each carries its
evidence. **All five Phase 0 open questions were decided on 2026-07-12** — see
`docs/decisions/` (ADRs **0010–0014**). **Phase 1 is unblocked for development.** Two
consequences carry into it: ADR 0010 (drop the out-of-tree exfat driver) makes the P1.10
**vfat fallback a fail-to-boot requirement**, not a nicety (see **A2**, **A15**); and ADR
0014 leaves the sustainability gate **deferred, not waived** — it now blocks **P4.10
(publication)**, so until it is signed this is a **personal-use** project (§C).
This file is the execution contract: every task is self-contained, has explicit acceptance criteria, and
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

## A. Key constraints index (A1–A15)

Tasks cite these IDs as shorthand for load-bearing constraints that are easy to get wrong;
each entry points to where the full text lives. A1–A9 were verified against the shipped
stock release; **A10–A15 were added by Phase 0** after verifying against the source, and
several of them correct A1–A9.

- **A1 — Two-stage initramfs build.** A second, minimal Buildroot config (static
  BusyBox, `BR2_TARGET_ROOTFS_CPIO`) produces a tiny cpio the main build's kernel
  consumes via `CONFIG_INITRAMFS_SOURCE`. Never `BR2_TARGET_ROOTFS_INITRAMFS` — it
  embeds the entire ~300 MB rootfs. The initramfs must be embedded in the zImage;
  U-Boot never loads an initrd. [PLAN §5] → P1.10
- **A2 — Cmdline-driven `/init`.** Parse `root=` and `loop=` from `/proc/cmdline`
  (`u-boot.txt` is `env import -t` and can override any U-Boot variable — USB boot
  setups exist); implement `rootwait` as a retry loop; mount the data partition as vfat
  **or** exfat (both built-in, plus NLS codepages); on failure, diagnostic banner and
  serial rescue shell. [PLAN §5, §3] → P1.10

  **[ADR 0010] The vfat fallback is now load-bearing, not a nicety.** Stock's kernel does a
  single `init_mount(..., "exfat", ...)` (`init/do_mounts.c:667`) that mounts FAT32 *only*
  because the out-of-tree driver handles FAT12/16/32. **Mainline exfat cannot mount FAT32 at
  all** — and the rootfs is a file *on that partition*, so a hardcoded `-t exfat` does not
  lose a feature, it **fails to boot**. Try `exfat`, then fall back to `vfat`.
  The vfat mount **must** set UTF-8, spelled **`utf8=1`** — *not* `iocharset=utf8`, which
  `Documentation/filesystems/vfat.rst:72` explicitly deprecates. Equivalently set
  `CONFIG_FAT_DEFAULT_UTF8=y` (stock: not set). Leave `CONFIG_FAT_DEFAULT_IOCHARSET` and
  `codepage=437` **unchanged**. exfat needs nothing (utf8 is already its default).
  Without this, non-ASCII filenames mojibake and Main_MiSTer's stored paths
  (recents/favorites/MGL) stop resolving.
- **A3 — `zImage_dtb` boot chain.** Plain `cat zImage dtb`. U-Boot computes the DTB
  address from the zImage header's declared-size field at `+0x2C` and passes it to
  `bootz $loadaddr - $fdt_addr`, injecting bootargs via `/chosen` FDT fixup. No
  `CONFIG_ARM_APPENDED_DTB`, no ATAGs, no initrd. [PLAN §3] → P0.8, P1.3, P1.11
- **A4 — `/dev/mem` must stay unrestricted.** `CONFIG_DEVMEM=y`,
  `CONFIG_STRICT_DEVMEM=n`, `CONFIG_IO_STRICT_DEVMEM=n` — otherwise `fpga_io.cpp`'s
  mmap of the bridge addresses fails and the entire FPGA path dies. Stock has it off.
  **[P0: `STRICT_DEVMEM` is NOT default-y on 32-bit ARM (`default y if PPC || X86 ||
  ARM64 || S390`), and `multi_v7_defconfig` has no DEVMEM line — the assertion stands, but
  it is not a fight against a default.]** [PLAN §3] → P1.3
- **A5 — Module infrastructure is a parity requirement.** Stock ships 52 `.ko.xz`
  modules (WiFi, Bluetooth USB, xone; `CONFIG_MODULE_COMPRESS_XZ=y`) with
  `kmod`/`depmod`/`modprobe`, **eudev** hotplug, and **66** firmware files **[P0: not 72 —
  that figure counted 6 directories as files]**. Class D/E module packages reproduce that
  existing layout. **[P0: stock BUNDLES `xow_dongle.bin`** — there is no on-device fetch to
  reproduce; the only open question is whether *we* may redistribute it.**]**
  [PLAN §3, §4.1] → P3.3, P0.3
- **A6 — On-device Python is an ABI surface.** `Downloader_MiSTer` and many community
  scripts run on the target's interpreter (stock: 3.9; Buildroot 2026.05: **3.14**).
  Compatibility must be tested, not assumed. **[P0: now evidenced, not suspected —
  `Downloader_MiSTer` pins Python **3.9** in its own CI and builds against `python3.9-dev`.
  The updater that delivers our image has never been tested on any interpreter we would
  ship.]** [PLAN §3] → P3.9
- **A7 — CI cannot boot the real image.** QEMU has no Cyclone V SoC machine model.
  CI runs static ABI checks, the stock `MiSTer` binary under a qemu-user chroot, and
  the initramfs logic on a generic QEMU ARM machine; real hardware gates each
  *release* (optional HIL rig later). [PLAN §11] → P2.8, P1.12, P4.11
- **A8 — `LinuxUpdater` contract.** Version check: the running system's
  `/MiSTer.version` (rootfs root) vs the db entry's **last 6 chars**, inequality.
  A pinned on-demand `7za` extracts only `files/linux/*`; six user files are copied
  into the offline-mounted new image; `files/linux/` is rsynced over `/media/fat/linux/`;
  `updateboot` flashes `uboot.img` and wipes U-Boot's saved env **on every update**.
  **[P0: only FIVE of the six destinations are regular files. `/etc/resolv.conf` is a
  symlink into tmpfs, the Downloader's `copy()` follows it, and so that restore has never
  actually worked — see Q2.]** **[P0: the flash phase runs without `set -e` and ends in
  `touch`, so a failed `mv`/`rsync`/`updateboot` still reports success and still raises the
  reboot flag. The update is not atomic and its success signal cannot be trusted.]**
  [PLAN §10, §8, §3] → P0.6
- **A9 — ext4 generation must be pinned.** Fixed UUID, pinned feature set (stock:
  `HAS_JOURNAL`, `METADATA_CSUM`, `64BIT`, `FLEX_BG`), `SOURCE_DATE_EPOCH`,
  `BR2_REPRODUCIBLE=y`; verified by a double-build comparison in CI. [PLAN §9]
  → P2.5, P4.3

### Added by Phase 0 (see `docs/phase0-review.md`)

- **A10 — `/MiSTer.version` is exactly 6 bytes, no trailing newline.** The Downloader
  compares it with a bare `f.read()` and **no `.strip()`**. A single trailing `\n` never
  matches any db `version`, so the box **re-flashes on every Downloader run, forever.**
  Stock is exactly 6 bytes. [PLAN §3; `docs/downloader-contract.md`] → **P2.6**
- **A11 — `CONFIG_BLK_DEV_INITRD=y` is required, and stock has it OFF.**
  `CONFIG_INITRAMFS_SOURCE` depends on it, so porting the stock config via `olddefconfig`
  (as P1.3 literally instructs) yields a kernel with **no initramfs slot at all** — silently
  deleting the mechanism §5 uses to kill the `loop=` patch. This is the one intentional
  divergence from stock that P1.3 must make loudly. [PLAN §5; `docs/boot-chain.md`] → **P1.3, P1.10**
- **A12 — The audio ABI is `/dev/MrAudio` + `/etc/asound.conf` + a patched `snd-dummy`,
  not a card name.** Main_MiSTer contains **zero ALSA code**. `asound.conf` routes the
  default PCM through `type file → /dev/MrAudio` (created by `MiSTer-audio-spi.c`) with
  `slave.pcm { type hw card 0 }`, card 0 being a patched `snd-dummy`. Patch `0002-…` **must
  carry the `sound/drivers/dummy.c` hunks** or the system is silent.
  [PLAN §3; `docs/abi-contract.md`] → **P1.5**
- **A13 — `/media/fat` semantics are an ABI surface.** Mounted **`sync,dirsync`** (fstab
  never re-mounts it) — mounting async is a power-off-corruption regression. Stock's
  out-of-tree exfat driver also gives it **symlinks** (via the FAT `ATTR_SYSTEM` bit, so
  they work on FAT32 too) and **UTF-8** FAT32 names; Main_MiSTer resolves those symlinks
  (`file_io.cpp:1592`). Mainline exfat/vfat provide neither.
  **[Q1 RESOLVED — ADR 0010: drop the driver.]** 0 symlinks found across `/media/fat` and
  every `/media/usb0..7` on a live stock MiSTer. Symlink support is therefore *not*
  carried; the **`sync,dirsync`** and **UTF-8** halves of this constraint still bind — see
  **A2**. `/media/fat` itself is a kernel **bind-mount** created by the very patch §5
  deletes (`init/do_mounts.c:677`), so the initramfs must recreate it.
  [PLAN §4.1 class G] → **P1.10**
- **A14 — Main_MiSTer never scans past `/dev/i2c-2`** (`smbus.cpp:214`). The ADV7513 HDMI
  transmitter must remain on `i2c-0..2`. **A fourth I²C adapter, or a bus reordering in the
  DTS we author, puts it out of reach and HDMI silently dies.**
  [`docs/abi-contract.md`] → **P1.7**
- **A15 — The rootfs is mounted read-only at boot; the loop DEVICE stays writable.**
  `ro` is in the cmdline and the kernel honours it (live `dmesg`, t=1.45s:
  `EXT4-fs (loop8): INFO: recovery required on readonly filesystem`). Two consequences the
  initramfs must preserve exactly:
  1. **Never `losetup -r`.** Stock's `/sys/block/loop8/ro == 0`. `/etc/profile:23` runs
     `mount -o remount,rw /` on **every login shell**, and a read-only loop *device* makes
     that remount fail — leaving a logged-in user with a permanently read-only rootfs, which
     stock is not. Read-only-ness belongs on the **mount**, not the device.
  2. **`/etc/resolv.conf` must stay a symlink into a tmpfs.** `S41dhcpcd`'s hook
     `20-resolv.conf` writes it *during boot, while `/` is read-only*. A regular file there
     is unwritable at exactly the moment it must be written. [ADR 0011]

  ⚠ **Observation trap:** because `/etc/profile` remounts `/` rw on login, SSHing in to
  check makes `mount` report `rw` and hides this entire constraint. **Use `dmesg`, not
  `mount`.** [PLAN §5, §3] → **P1.10, P2.3**

---

## Phase 0 — Bootstrap & Recon

Exit criterion: patch triage and ABI contract complete and human-reviewed (P0.9).

- [x] **P0.1 — Repository scaffolding** — [HAIKU] — Size S — Depends: —
  Create the §6 directory skeleton (empty dirs with `.gitkeep`), `.gitignore` (must
  exclude `work/`, `dl/`, `output*/`, `*.img`, `*.7z`), `.editorconfig`, and a README
  stub stating goals, license layering (GPLv3 repo / GPLv2 kernel patches / upstream
  package licenses), and a pointer to `PLAN.md` + this file.
  **Done when:** `git status` clean after scaffold commit; README renders; no binary or
  generated path can be accidentally committed (verify with a dry-run `git add` of a
  dummy `work/test.img`).

- [x] **P0.2 — Acquire reference materials** — [SONNET] [NET] — Size S — Depends: P0.1
  Into untracked `work/`: clone `MiSTer-devel/Linux-Kernel_MiSTer` (the 5.15 fork),
  `MiSTer-devel/Main_MiSTer` (need `fpga_io.cpp`, `brightness.cpp`, ioctl users),
  `MiSTer-devel/Downloader_MiSTer`, `MiSTer-devel/U-Boot_MiSTer`; download the current
  `release_YYYYMMDD.7z` from `MiSTer-devel/SD-Installer-Win64_MiSTer` (commit-pinned
  URL); extract it and inspect `linux.img` (note: `7z l/x` reads the ext4 image directly —
  no mount needed). *(Pre-seeded during plan verification: `work/` already holds the
  extracted release, and the stock kernel config, DTS, and U-Boot env are derived — see
  `docs/verification/stock-release-20250402.md`.)*
  **Done when:** `work/manifest.txt` lists every acquired artifact with URL, commit/tag,
  and SHA-256; stock rootfs content is browsable.

- [x] **P0.3 — Stock image inventory** — [SONNET] — Size M — Depends: P0.2
  Produce `docs/stock-inventory/`: (a) all shared libs with SONAMEs and versions;
  (b) all binaries with their `NEEDED` sets; (c) `/etc` configs verbatim-listed
  (init scripts S01–S99, inittab, fstab, smb.conf, wpa_supplicant, sshd_config, …);
  (d) `/lib/firmware` contents (72 files, per A5); (e) BusyBox applet list; (f) kernel
  config and DTS — **already extracted** to `docs/stock-inventory/stock-linux.config`
  (via IKCONFIG) and `docs/stock-inventory/stock.dts`; script the regeneration;
  (g) disk usage by top-level dir; (h) the 52 `.ko.xz` module list with dependencies.
  **Done when:** each list is a checked-in text/markdown file with a generation script
  in `scripts/inventory/` so it can be re-run against any image.

- [x] **P0.4 — Kernel commit triage (classes A–F)** — [OPUS] — Size L — Depends: P0.2
  **[P0: there is no `v5.15.1` tag — the fork has zero tags and no upstream ancestry,
  only squashed whole-tree imports. Baseline by content-diffing commit `aba1ef4c1` against
  a real kernel.org tarball; it is pristine, so the 109 commits after it are the delta.]**
  Enumerate every commit in the 5.15 fork not in upstream `v5.15.1`. For each: class
  (A–F per §4.1), files touched, original author/origin, upstream status in v6.18
  (cite the upstream commit if merged), and disposition (carry / drop / re-source).
  Deliver `docs/patch-provenance.md` with a summary table plus one subsection per
  carried patch.
  **Done when:** every fork commit is accounted for; each "drop — upstream" entry cites
  the mainline commit or subsystem; the carried set maps 1:1 to the planned
  `linux-patches/` filenames in §6.

- [x] **P0.5 — ABI contract document** — [OPUS] — Size M — Depends: P0.2, P0.3
  Expand §3 into `docs/abi-contract.md` with evidence: `readelf -d` output for the stock
  `MiSTer` binary; the `MiSTer_fb` ioctl numbers/structs extracted from source; the
  physical addresses and access patterns from `fpga_io.cpp`; every `/dev` node
  Main_MiSTer opens (grep the source); `/media/fat` layout assumptions;
  `MiSTer.version` format; init-script naming contract. Mark each item MUST / SHOULD.
  **Done when:** a reviewer can verify any single claim from the cited evidence without
  re-deriving it; doc cross-links P0.4 for kernel-side items.

- [x] **P0.6 — Downloader `LinuxUpdater` contract (A8)** — [SONNET] — Size S — Depends: P0.2
  Formalize the already-verified contract (`docs/verification/stock-release-20250402.md`)
  into `docs/downloader-contract.md`: exact db.json `linux` schema; MD5 hash scope;
  last-6-chars inequality version compare against the rootfs-root `/MiSTer.version`; the
  on-demand pinned `7za` fetch; `files/linux/*`-only extraction; the user-file restore
  into the mounted new image; the rsync + `updateboot` + swap + reboot-flag apply flow;
  failure handling; and the multi-db "only 1 can be processed" ordering rule with the
  exact `downloader.ini` incantation for users.
  **Done when:** doc quotes the relevant source lines (file:line at a pinned commit) for
  every claim; includes a worked example db.json entry.

- [x] **P0.7 — Package mapping** — [SONNET] — Size M — Depends: P0.3
  Map every stock SONAME and every user-facing binary to a Buildroot 2026.05 package
  (name + version). Flag: packages Buildroot lacks (candidates for `package/` in our
  tree), version jumps with known breaking changes (Samba 4.14→4.2x config syntax,
  OpenSSH policy changes, Python per A6), and anything in stock that should be dropped.
  Deliver `docs/package-manifest.md`.
  **Done when:** zero unmapped SONAMEs from the ABI contract; every gap has a
  disposition; the resulting `BR2_PACKAGE_*` list is included ready to paste.

- [x] **P0.8 — Boot chain analysis (A3)** — [OPUS] — Size M — Depends: P0.2
  The embedded environment has already been recovered from `uboot.img` (bootcmd /
  mmcload / mmcboot / scrtest / fpgaload / fpgacheck, `mmcroot=/dev/mmcblk0p1`, the
  DTB-address computation, `env import -t`, the warm-reboot RAM handshake — see the
  verification doc). Remaining: cross-check against `U-Boot_MiSTer` source; document the
  SPL layout (4 copies + uImage at 256 KiB), the sector-1 saved-env wipe by `updateboot`,
  and the FPGA preload path. Deliver `docs/boot-chain.md` with kernel-config implications
  (**no** `ARM_APPENDED_DTB` needed; bootargs via `/chosen` fixup) as a checklist P1.3
  consumes.
  **Done when:** the boot command is quoted verbatim and matched to source; every
  kernel-config implication is stated as a testable assertion.

- [x] **P0.9 — Phase 0 review gate** — [HAIKU] + human — Size S — Depends: P0.3–P0.8
  Assemble a one-page summary of Phase 0 findings, open questions, and any newly
  discovered constraints beyond A1–A9 (fold those into `PLAN.md` and the section A index
  in the same PR). Human reviews and approves before Phase 1 starts.
  **Done when:** summary committed as `docs/phase0-review.md` with human sign-off noted.
  **Status:** summary committed; `PLAN.md` amended to v3; A-index extended to A14; the
  task texts Phase 0 proved wrong (P1.3, P1.5, P1.8, P1.9, P1.10, P2.6, P3.2) corrected.
  **The human sign-off is still OUTSTANDING** — the box above is checked for the *authoring*
  work only. **Phase 1 (P1.1) must not start until `docs/phase0-review.md`'s sign-off block
  is filled in and its five open questions (Q1–Q5) are decided.** Q1 (exFAT symlinks) is the
  biggest: it decides whether we carry an out-of-tree filesystem driver forward to 6.18 —
  a permanent maintenance burden the plan never budgeted for.

---

## Phase 1 — Buildroot skeleton & kernel

Exit criterion: 6.18 LTS kernel built by Buildroot from a pristine kernel.org tarball
boots to a serial console on real hardware (P1.13).

- [x] **P1.1 — BR2_EXTERNAL skeleton** — [SONNET] — Size S — Depends: P0.9
  `external.desc`, `external.mk`, `Config.in`, `configs/mister_de10nano_defconfig`
  (minimal, builds nothing yet), plus a top-level `Makefile`/script that downloads the
  pinned Buildroot 2026.05.x tarball, verifies its SHA-256, unpacks to `work/buildroot/`,
  and invokes it with `BR2_EXTERNAL` set. Buildroot is never vendored (G4/§6).
  **Reference:** `/mnt/source/sb-enema/Makefile` — a working 2026.02.3 pinned-tarball
  wrapper with `BR2_EXTERNAL`, `O=`, `BR2_DL_DIR`, and a `%:` target forwarding rule
  (add SHA-256 verification, which it lacks).
  **Done when:** `make menuconfig`-equivalent runs against the external tree from a
  clean checkout with only `work/` populated by the script.

- [x] **P1.2 — Toolchain & base defconfig** — [SONNET] [NET] — Size M — Depends: P1.1
  Set `armv7-a`/Cortex-A9/NEON-VFPv3/EABIhf/glibc. Evaluate internal toolchain vs a
  Bootlin external toolchain (build time vs reproducibility vs glibc version control);
  document the choice in `docs/decisions/0001-toolchain.md`. Produce a minimal booting
  rootfs config (BusyBox only).
  **Done when:** `make` completes producing `rootfs.tar`; a hello-world cross-compiled
  binary runs under `qemu-arm`; decision doc explains the trade-off.

- [x] **P1.3 — Kernel config derivation (A3, A4)** — [OPUS] — Size L — Depends: P0.8, P1.1
  Port the **exact extracted stock config** (`docs/stock-inventory/stock-linux.config`,
  4,246 lines from IKCONFIG) to 6.18 via `olddefconfig`, then audit every dropped/renamed
  symbol.
  **[P0 — A11, READ FIRST: `olddefconfig` of the stock config is a trap.]** Stock has
  `# CONFIG_BLK_DEV_INITRD is not set`, and `CONFIG_INITRAMFS_SOURCE` **depends on it** —
  so a faithful port hands P1.10 a kernel with **no initramfs slot at all**, silently
  removing the mechanism §5 uses to delete the `loop=` patch. **`BLK_DEV_INITRD=y` is a
  required, intentional divergence from stock.** Document it as such.
  Explicitly assert and document: `DEVMEM=y`, `STRICT_DEVMEM=n`,
  `IO_STRICT_DEVMEM=n` (A4 — stock verified); **no** `ARM_APPENDED_DTB` (A3 —
  U-Boot passes the DTB pointer); stock-parity items: `IKCONFIG=y`+`IKCONFIG_PROC=y`,
  `KERNEL_LZ4`, `MODULE_COMPRESS_XZ=y`, `BLK_DEV_LOOP=y` (`LOOP_MIN_COUNT=8`); built-in
  (not module): ext4, vfat, exfat, loop, NLS codepages (**incl. `CONFIG_NLS_UTF8`**), dwc2,
  usb-storage, HID core; cifs + nfs built-in per stock.
  **[ADR 0010] `CONFIG_VFAT_FS=y` is now load-bearing, not parity trivia** — it is the FAT32
  fallback for the initramfs, without which FAT32 cards fail to boot. Also set
  **`CONFIG_FAT_DEFAULT_UTF8=y`** (stock: not set) — an intentional divergence; leave
  `CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"` and `CONFIG_FAT_DEFAULT_CODEPAGE=437` unchanged.
  **[ADR 0013] NTFS: decided — build `ntfs3` as a MODULE (`=m`), and leave it disabled by
  default until stock parity is demonstrated.** Not built-in: it must not consume `zImage`
  budget (P1.11), and enabling features before parity is proven confounds "we broke it" with
  "we added it".
  Module support ON, signing OFF (A5); cpufreq
  governors matching stock. Deliver `board/mister/de10nano/linux.config`
  (savedefconfig) + `docs/kernel-config-deltas.md`.
  **Done when:** kernel builds from a pristine kernel.org 6.18.y tarball with this
  config; delta doc explains every intentional divergence from both the stock config and
  the 6.18 `multi_v7_defconfig` baseline.

- [x] **P1.4 — Forward-port `MiSTer_fb`** — [OPUS] — Size L — Depends: P0.4, P1.3
  Port `drivers/video/fbdev/MiSTer_fb.c` from 5.15 to 6.18 as
  `0001-fbdev-add-MiSTer_fb-driver.patch`. The **ioctl ABI and `/dev/fb0` semantics must
  be bit-identical** (P0.5 contract). Expect fbdev API churn (fb_ops changes, aperture
  helpers, deferred-io changes).
  **Done when:** patch applies clean to the pinned 6.18.y; driver compiles with no
  warnings; a provenance header cites the origin commit; ioctl numbers verified
  unchanged against the contract doc.

- [x] **P1.5 — Forward-port `MiSTer-audio-spi`** — [OPUS] — Size M — Depends: P0.4, P1.3
  Port `sound/drivers/MiSTer-audio-spi.c` to 6.18 as `0002-…`. ALSA API churn expected.
  **[P0 CORRECTION — this task's original premise was false.]** It previously read *"Card/
  device name exposed to userland must match stock (Main_MiSTer opens it by name)."*
  **Main_MiSTer contains zero ALSA code and never opens a card by name.** The real contract
  (A12, `docs/abi-contract.md`) is: `/etc/asound.conf` routes the default PCM through
  `type file → /dev/MrAudio` (the chrdev this driver creates) with
  `slave.pcm { type hw card 0 }`, where card 0 is a **patched `snd-dummy`**. So `0002-…`
  **must also carry the `sound/drivers/dummy.c` hunks** (fork commit `333d49b95`) — omit
  them and the system is silent.
  **Done when:** applies clean, compiles clean, provenance header present, the `/dev/MrAudio`
  node is created with stock's name/permissions, the patched `snd-dummy` card 0 accepts
  S16_LE/48000/2ch, and stock's `/etc/asound.conf` opens the default PCM unmodified.

- [x] **P1.6 — Forward-port Cyclone V cpufreq/overclock** — [OPUS] — Size M — Depends: P0.4, P1.3
  Port the overclock/cpufreq driver as `0003-…`. Preserve the sysfs interface stock
  scripts/Main use (verify against P0.5).
  **Done when:** applies clean, compiles clean, sysfs paths documented and matching.

- [x] **P1.7 — MiSTer DTS patch (§4.1a)** — [OPUS] — Size L — Depends: P0.4, P1.3
  **Done 2026-07-12.** `board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch`;
  evidence in **`docs/dts-comparison.md`**. `dtbs` builds with **zero new `dtc` warnings**
  (default flags *and* `W=1`); the built DTB was decompiled and diffed node-by-node against
  `docs/stock-inventory/stock.dts` with every divergence justified. **A14 proven**: exactly
  three i²C adapters (`i2c0`, `i2c2`, `i2c_gpio` — stock's, byte-identical), **no `i2c`
  aliases** ⇒ `i2c_add_adapter()` allocates dynamically from `__i2c_first_dynamic_bus_num == 0`
  ⇒ the numbers can only be **{0,1,2}**; no adapter can be ≥ 3. The fork's shared
  `socfpga.dtsi` hunk is **not** carried (i2c1 is `disabled`; the property is never read).
  P1.6's request for an `&osc1` rate was **checked and retracted** — mainline's
  `socfpga_cyclone5.dtsi:13-18` already sets it, and the built DTB matches stock exactly.
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

- [x] **P1.8 — spidev binding fix (§13 hazard)** — [SONNET] — Size S — Depends: P1.7
  **Done 2026-07-12, inside P1.7 — there is no `0005` patch and no code change at all.**
  `0004`'s `spi1` child uses **`compatible = "rohm,dh2228fv"`**, which is already in 6.18's
  `spidev_dt_ids[]` *and* `spidev_spi_ids[]`, so mainline spidev binds it unpatched. It still
  lands on SPI bus 1 / CS 0 (no `spi` aliases ⇒ `spi_register_controller()` numbers
  controllers dynamically in probe order, `spi@fff00000` → 0, `spi@fff01000` → 1) ⇒
  **`/dev/spidev1.0`**, which is what `Main_MiSTer/brightness.cpp` opens. `spidev_of_check()`
  rejects only the literal string `"spidev"` in DT and is satisfied. Rationale and the full
  creation path: `docs/dts-comparison.md` §5; `docs/patch-provenance.md` §5.
  **The `0005` numbering slot stays empty — do not renumber `0010`+.**
  Remaining: the P1.13 boot-log assertion that `/dev/spidev1.0` exists.
  **[P0: `altspi` is NOT a catch-all binding.]** It is an explicit one-line entry in
  `spidev_dt_ids[]` (`drivers/spi/spidev.c:699`, fork commit `246984fce`). Since we author
  our own DTS, **retarget the compatible to one mainline spidev already accepts and drop
  patch `0005` entirely.** Note it drives a **pi-top hub** (brightness/lid), not MiSTer's
  own I/O board. Document the choice.
  **Done when:** `/dev/spidev1.0` creation path is explained in the patch/DTS commit
  message; no `spidev: probed from DT without matching compatible` style warning
  expected (assert in P1.13 boot log).

- [x] **P1.9 — Residual HID & quirk patches (classes D, F)** — [SONNET] — Size M — Depends: P0.4, P1.3
  Port the carried set: GunCon 2/3, Fanatec, Flydigi Vader, remaining xpad IDs,
  usb-storage Realtek CD-ROM blacklist, mmc LED, btusb VID/PIDs — *only* those P0.4
  confirmed absent from 6.18. Number them `0010+`/`0020+` per §6. Escalate any
  individual port to [OPUS] if the upstream driver was restructured.
  **[P0] `0026-input-mousedev-eviocgrab` is a core input-subsystem patch, not a HID quirk
  — assign it to [OPUS].** Main_MiSTer both `EVIOCGRAB`s evdev and reads mousedev.
  **[P0] Two carried patches are dead weight — drop them:** the `dwc2/core.c` hunk is a
  provable no-op, and the `vt.h MAX_NR_CONSOLES` edit buys a few KB (only 3 consoles are
  used). **[P0] Keep the `leds-gpio` patch** — Main_MiSTer polls `brightness_hw_changed`
  to drive the on-screen disk LED.
  **Done when:** all patches apply and compile clean; each has a provenance header;
  P0.4's table updated with final patch filenames.

- [x] **P1.10 — Initramfs: design & implement (A1, A2)** — [OPUS] — Size L — Depends: P0.8, P1.2
  Implement the two-stage build (A1): `configs/mister_initramfs_defconfig` (static
  BusyBox, cpio output, ~hundreds of KB) consumed by the main kernel via
  `CONFIG_INITRAMFS_SOURCE`. Write `/init` per A2: parse `root=`/`loop=` from
  `/proc/cmdline`, rootwait retry loop, then:

  * **Mount the data partition trying `exfat` FIRST, then falling back to `vfat` (A2/ADR
    0010).** Mainline exfat **cannot mount FAT32**, and the rootfs is a file *on* this
    partition — so a hardcoded `-t exfat` does not lose a feature, it **fails to boot**.
  * **`sync,dirsync` (A13)** — stock mounts `/media/fat` sync and fstab never re-mounts it;
    async is a power-off-corruption regression. Plus `fmask=0022,dmask=0022`.
  * **The vfat fallback must set `utf8=1` — NOT `iocharset=utf8` (A2/ADR 0010).**
    `Documentation/filesystems/vfat.rst:72` deprecates the latter. exfat needs nothing.
  * **`losetup -f` to pick the device, and NEVER `losetup -r` (A15).** loop8 is an artifact
    (`LOOP_MIN_COUNT=8` pre-creates loop0-7 only; nothing references loop8 by name), so
    allocate with `-f`. But the loop **device must stay writable**: stock's
    `/sys/block/loop8/ro == 0`, and `/etc/profile:23` runs `mount -o remount,rw /` on every
    login shell — a read-only loop *device* makes that remount fail, leaving a logged-in
    user with a permanently read-only rootfs, which stock is not. **Read-only-ness belongs
    on the `mount -o ro`, not on the device.**
  * `mount --move` the data partition to `/newroot/media/fat` — stock's kernel creates this
    as a **bind-mount** (`init/do_mounts.c:677`) and *nothing in `/etc` mounts it*, so if
    the initramfs does not recreate it, `/media/fat` simply will not exist.
  * `exec switch_root`; on any failure print a diagnostic banner and drop to a serial
    shell. Wire the two-stage sequencing into the top-level Makefile from P1.1.
  **Reference:** `/mnt/source/sb-enema` builds a `BR2_TARGET_ROOTFS_CPIO` image on
  Buildroot 2026.05 (x86_64, busybox init, kernel+busybox config fragments) — the same
  output mechanism as stage 1 here.
  **Done when:** kernel image embeds the cpio; P1.12's QEMU test passes; `/init` is
  shell-checked (`shellcheck`) and under 200 lines; design recorded in
  `docs/decisions/0002-initramfs.md`.

- [x] **P1.11 — `zImage_dtb` assembly (A3)** — [SONNET] — Size S — Depends: P1.3, P1.7
  `post-image.sh` step: concatenate zImage + our DTB into `zImage_dtb` with plain `cat`
  (verified correct: U-Boot computes the DTB address as `loadaddr + *(loadaddr+0x2C)`,
  i.e. exactly the zImage's declared end). Sanity-check size against U-Boot's load
  regions (`loadaddr=0x01000000`, `fpgadata=0x02000000` — the kernel blob must stay
  under 16 MiB or the FPGA load address needs revisiting).
  **Done when:** artifact produced on every build; a scripted check asserts the zImage
  header's declared size equals the zImage file length, the DTB magic sits exactly
  there, and total size is within budget.

- [x] **P1.12 — QEMU initramfs logic test (A7)** — [SONNET] — Size M — Depends: P1.10
  CI-runnable test: build the same initramfs cpio into a generic ARM kernel
  (`qemu-system-arm -M virt` or similar), attach a crafted disk image containing a
  FAT partition with `linux/linux.img` (a tiny ext4 with a marker `/sbin/init`), boot
  with the stock-shaped cmdline, and assert the marker init runs. Cover: exFAT variant,
  missing image (must reach rescue shell), `root=` override, slow-device rootwait.
  **Done when:** `scripts/test-initramfs.sh` runs green locally and in CI (wired in
  P4.1); all four cases asserted.

- [x] **P1.13 — [HW] First hardware boot** — human + [OPUS] — Size L — Depends: P1.4–P1.12
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

- [x] **P2.1 — Full package set** — [SONNET] — Size M — Depends: P0.7, P1.2
  Apply P0.7's `BR2_PACKAGE_*` list to the defconfig. Resolve selection conflicts and
  missing deps. Confirm every ABI-contract SONAME (§3) is produced at the same major
  version.
  **Done when:** full rootfs builds; P2.2's checker passes.

- [x] **P2.2 — SONAME parity checker** — [SONNET] — Size S — Depends: P2.1
  `scripts/check-abi.sh`: (a) verify every SONAME from `docs/abi-contract.md` exists in
  the built rootfs at the same major version; (b) run the stock `MiSTer` binary's
  dynamic-link resolution against the new rootfs via `qemu-arm` +
  `LD_TRACE_LOADED_OBJECTS` style check; fail on any unresolved symbol/library.
  **Done when:** script exits nonzero on a deliberately broken rootfs (test that) and
  zero on the real one; wired into CI later (P4.1).
  **Done:** `scripts/check-abi.sh` implements the ABI/loader subset of §13.1
  (A-1..A-12, A-24, A-25 static; A-10/A-22 under qemu-user, SKIP when the gitignored
  stock binary is absent). Verified: 15/15 PASS on the built `output/target` (glibc
  2.42), exit 1 on a rootfs with a SONAME removed. Wired into `build.yml`
  (`scripts/check-abi.sh output`). The init/config-parity rows of §13.1 (A-13..A-21,
  A-23) are deliberately **out of scope** here — they belong to P2.3/P2.4 and are
  asserted by `ci-tests.sh`'s Phase-3 section, several with documented divergences
  from stock's exact strings.

- [x] **P2.3 — Rootfs overlay: init & config parity** — [SONNET] — Size L — Depends: P0.3, P2.1
  Recreate stock init behavior in `rootfs-overlay/`: the verified S-script set
  (S01syslogd, S02klogd, S10udev, S30dbus, S40network, S41dhcpcd, S45bluetooth, S49ntp,
  S50proftpd, S50sshd, S91smb, S99user); inittab (**launches `/media/fat/MiSTer` from
  `::sysinit`, backgrounded**, plus `/etc/resync` and getty on ttyS0 115200);
  stock-parity fstab (root `rw,noauto` — the `ro` comes from the cmdline; tmpfs on /tmp,
  /run, /dev/shm, /var/lib/samba, /var/db/dhcpcd); hostname `MiSTer`; profile; ifupdown
  `/etc/network/interfaces` + dhcpcd; **eudev** (stock uses udev, not mdev); and the
  USB-storage automount mechanism found in P0.3.

  **⚠ [CORRECTED — the original text here was WRONG and would break DNS.]** It said all
  six user-file destinations *"must be regular files (A8)"*. **Invariant A8 is WITHDRAWN**
  (PLAN §3). **Five** are regular files — `/etc/hostname`, `/etc/hosts`,
  `/etc/network/interfaces`, `/etc/dhcpcd.conf`, `/etc/fstab`.
  **`/etc/resolv.conf` MUST be a SYMLINK into a tmpfs** ([ADR 0011](docs/decisions/0011-resolv-conf-buildroot-default.md)).
  Not for parity — for correctness: `/` is mounted **read-only** at boot (confirmed on
  hardware, P1.13), and `S41dhcpcd`'s `20-resolv.conf` hook writes `/etc/resolv.conf`
  *during* boot. A regular file there is **unwritable at exactly the moment it must be
  written.** Ship **Buildroot's own skeleton default** (`/etc/resolv.conf ->
  ../run/resolv.conf`) — prefer the upstream default over code we maintain. The Downloader's
  restore of that one file stays a silent no-op, exactly as on stock; that is *deliberate*
  parity, not an oversight.

  **⚠ HARD REQUIREMENT from P1.10:** the image **must contain `/media/fat`, `/dev`, `/proc`
  and `/sys` as empty directories.** `/` is read-only, so `/init` **cannot create its own
  mount points** — it rescues to a serial shell if they are missing. Stock has all four.

  Diverge from stock only with a documented reason.
  **Done when:** a diff report `docs/init-parity.md` lists every stock init script with
  status: identical / adapted (why) / dropped (why).

- [ ] **P2.4 — Read-only root audit** — [SONNET] — Size M — Depends: P2.3
  Boot-test (QEMU-user chroot where possible, hardware in P2.9) that every daemon and
  script functions with `/` mounted ro: enumerate writable-path expectations
  (`/etc/resolv.conf`, samba state, ssh host keys, bluetooth pairing db, wpa state) and
  route each to tmpfs or `/media/fat` exactly as stock does.
  **Done when:** `docs/writable-paths.md` lists every writable path with its
  destination; no daemon writes to `/` at runtime.

- [x] **P2.5 — Image generation, reproducible (A9)** — [SONNET] — Size M — Depends: P2.1
  `genimage.cfg` + mke2fs config: 512 MiB ext4, volume label `rootfs`, **pinned**
  filesystem feature set (stock reference: `HAS_JOURNAL`, `METADATA_CSUM`, `64BIT`,
  `FLEX_BG`), fixed UUID (stock ships one), `SOURCE_DATE_EPOCH` honored, deterministic
  file ordering. Enable `BR2_REPRODUCIBLE`. Must remain mountable rw by the updater's
  user-file restore (A8).
  **Done when:** two clean builds from the same commit produce byte-identical
  `linux.img` (verify locally; CI job in P4.3); image mounts ro on the 6.18 kernel.

- [x] **P2.6 — `post-build.sh`: version stamping** — [HAIKU] — Size S — Depends: P2.5
  Write `MiSTer.version` (6-char `YYMMDD`) **at the rootfs root of the image**
  (`/MiSTer.version` — verified location; the Downloader reads the running system's own
  copy), and an `/etc/os-release` identifying this distribution + build commit.
  **[P0 — A10: exactly 6 bytes, NO trailing newline.]** The Downloader compares this file
  with a bare `f.read()` and **no `.strip()`**. A single `\n` — which `echo` adds by
  default — never matches any db `version`, so the box **re-flashes on every Downloader
  run, forever.** Use `printf '%s'`, not `echo`.
  **Done when:** both files present in the image with correct format and location; the
  test in `scripts/` asserts `/MiSTer.version` is **exactly 6 bytes** and that its last
  byte is not `\n`.

- [x] **P2.7 — Size budget report** — [HAIKU] — Size S — Depends: P2.1
  Report rootfs usage by package (Buildroot's `make graph-size` + a markdown summary).
  Assert ≥ 15 % free in the 512 MiB image (§11 budget); flag the top 10 growth items vs
  stock.
  **Done when:** `docs/size-budget.md` committed; CI-runnable check script asserts the
  15 % floor.

- [x] **P2.10 — Version-delta doc: five years of upstream fixes** — [SONNET] — Size S — Depends: P2.1
  Produce `docs/version-delta.md`: stock (Buildroot **2021.02.4**) vs ours (**2026.05.1**)
  for every package, the version jump, and the security/maintenance value. This is a
  headline win — stock froze the whole userland ~5 years ago — and it directly serves
  **G2/G3** (a real security-update path) and the release notes (P4.9).
  Data: `docs/package-manifest.md` already carries a stock→ours version column; exact
  built point-versions come from `output/build/<pkg>-<ver>/` after P2.1. Known headliners:
  glibc 2.31→2.42, kernel 5.15.1→6.18.33 (both hardware-verified), OpenSSL 1.1→3, plus
  ALSA, BlueZ, Samba, SSH/FTP, Python 3.9→3.14.
  **⚠ Do NOT fabricate CVE numbers.** State version deltas (factual) and the general
  "~5 years of upstream maintenance" framing (true). Cite a specific CVE only if actually
  looked up and confirmed applicable. A verifiable "N major jumps, ~5 years of fixes"
  beats an unverifiable "fixes 47 CVEs" — overclaiming destroys the credibility this doc
  exists to build.
  **Done when:** `docs/version-delta.md` committed — headline table + full per-package
  stock→ours table sorted by biggest jump + a call-out of the security-relevant movers.

- [ ] **P2.8 — qemu-user smoke of the stock binary (A7)** — [SONNET] — Size M — Depends: P2.2
  In CI-runnable form: chroot into the built rootfs under `qemu-arm`, execute the stock
  `MiSTer` binary, and assert it advances past dynamic linking and early init (it will
  fail at `/dev/mem`/FPGA access — capture and whitelist that exact failure signature).
  Any earlier failure (linker, missing lib, glibc symbol) is a hard fail.
  **Done when:** test distinguishes "died at FPGA access (expected)" from "died earlier
  (regression)" and is wired into `scripts/`.

- [x] **P2.9 — [HW] Stock `MiSTer` binary reaches the menu** — human + [OPUS] — Size L — Depends: P1.13, P2.1–P2.8
  Full image on hardware with a real `/media/fat` populated from `Distribution_MiSTer`.
  Assert: menu appears on HDMI; boot-to-menu time ≤ stock (measure both); free RAM at
  menu ≥ stock; a sample core loads and runs; framebuffer, audio, and input all work.
  Model triages from serial logs and `MiSTer` stderr.
  **Done when:** results + timings committed to `docs/testlogs/p2-menu.md`. **This is
  the Phase 2 exit gate and the project's central bet — fail fast here.**

---

## Phase 3 — Parity

Exit criterion: hardware matrix (§11) green (P3.13).

- [x] **P3.1 — Realtek WiFi module packages** — [SONNET] [NET] — Size L — Depends: P2.1
  Buildroot `kernel-module` packages under `package/` for `rtl8188eu`, `rtl8188fu`,
  `rtl8812au`, `rtl8821au`, `rtl8821cu`, `rtl88x2bu`, each sourced from the morrownr
  upstream (commit-pinned, hash-verified). Do not vendor code (§4.1 class E).
  **Done when:** all six build against the pinned 6.18.y; `.ko`s land in
  `/lib/modules/$(uname -r)/`; each package has a hash file and license entry.

  **Result:** all six build clean and `depmod`-index (`modules.dep`/`modules.alias`,
  confirmed autoload-ready). **[P0: two deviate from morrownr, documented per this
  task's own allowance]** — morrownr carries neither RTL8188EU nor RTL8188FU;
  `rtl8188eu` is sourced from `aircrack-ng/rtl8188eus` and `rtl8188fu` from
  `kelebek333/rtl8188fu`, the most actively maintained forks available. **[P0:
  package names deviate for 3 of 6]** — Buildroot 2026.05.1 upstream now ships its
  own same-named `rtl8188eu`/`rtl8821au`/`rtl8821cu` packages (different forks, not
  discovered until this task actually loaded the defconfig) — ours are
  `rtl8188eu-aircrack-ng`/`rtl8821au-morrownr`/`rtl8821cu-morrownr` to avoid a
  Kconfig-symbol/Make-namespace collision; `rtl8812au`/`rtl8821au`(→`-morrownr`)/
  `rtl8821cu`(→`-morrownr`)/`rtl88x2bu` are unmodified morrownr sources.
  `rtl8188eu-aircrack-ng` needed 3 small local patches (ccflags-y/EXTRA_CFLAGS
  kbuild compat, a cfg80211_ops multi-radio API signature update, and a
  from_timer/del_timer_sync rename) beyond what morrownr-family drivers needed —
  its pin predates an open, unmerged upstream PR (#319) covering the same 6.18/6.19
  drift; documented in the patch files and the package .mk. All six: `#ifdef
  CONFIG_WIRELESS_EXT` gates only legacy iwconfig/iwpriv paths, never the
  cfg80211/nl80211 registration path `wpa_supplicant -D nl80211` uses — confirmed
  by reading the source, not assumed; no wext wrapper/kernel `select` hack needed
  or added. **Unverified without hardware (P3.13/P3.4):** association, throughput,
  and monitor-mode behavior against a real dongle of each chip.

- [x] **P3.2 — xone package** — [SONNET] [NET] — Size M — Depends: P3.1
  Package `xone` similarly. Handle its firmware requirement explicitly: document the
  redistribution status. **[P0: stock BUNDLES it.** `xow_dongle.bin` is present in stock's
  66-file firmware set (`docs/stock-inventory/firmware.md`) — there is no on-device fetch
  to reproduce. Parity means shipping it; the open question is only whether *we* may
  redistribute it.**]**
  **Done when:** module builds; firmware path documented in
  `docs/decisions/0003-xone-firmware.md`; behavior matches stock.

  **Result:** `package/xone` builds 9 `.ko` clean against 6.18.33 with **zero compat
  patches needed** — sourced from `dlundqvist/xone` (the actively-maintained fork;
  `medusalix/xone`, what stock vendored, is explicitly "in maintenance mode" per its own
  README, one commit in 19 months before this pin), which already carries
  `LINUX_VERSION_CODE`-gated shims through 6.16 (`from_timer`→`timer_container_of`,
  `del_timer_sync`→`timer_delete_sync`, `device_driver`/`shutdown`/`bus_match` signature
  churn) that turned out to cover 6.18 too — verified empirically by an actual build, not
  assumed. **The P3.1 `obj-$(CONFIG_...)` gotcha does NOT apply here**: this Kbuild uses
  unconditional `obj-m := ...`, never gated behind a CONFIG symbol, so no
  `XONE_MODULE_MAKE_OPTS` shim was needed (checked, not assumed — see `package/xone/xone.mk`).
  Vermagic `6.18.33 SMP mod_unload ARMv7 p2v8` confirmed on the module **extracted from
  `output/images/rootfs.tar`** (not just `output/target`), matching target exactly; `xone_dongle`
  correctly resolves `cfg80211`+`xone_gip` deps via `modules.dep`; 33 xone-related entries in
  `modules.alias` (4 dongle USB PIDs, 5 wired-controller USB VIDs, GIP class-match aliases).

  **Firmware (the ADR 0003 question): DECIDED by the maintainer, not left open by this
  task.** Redistribute `xow_dongle.bin` for stock parity, sourced fresh from Microsoft's own
  official driver `.cab` (Windows Update CDN) at **build time**, hash-pinned at both the
  `.cab` and the extracted-firmware-blob layer, **never committed to git** (G6). New packages:
  `package/cabextract` (host-only, from cabextract.org.uk upstream, same author/site as this
  tree's existing `libmspack`) and `package/xow-firmware` (fetches, extracts, double-hash-
  verifies, installs). Installed under **two names**: `xow_dongle.bin` (stock's literal
  filename, byte-for-byte parity — 70,620 bytes, matches `docs/stock-inventory/firmware.md`
  exactly) **and** a symlinked `xone_dongle_02fe.bin` (what the *actual driver packaged here*
  requests at runtime — `dlundqvist/xone` moved to a per-PID firmware-naming scheme stock's
  older fork never used; shipping only the stock name would satisfy a filename diff but leave
  the real driver unable to find its firmware). Both hash gates independently proven to hard-fail
  on tampering (wrong `.cab` hash → Buildroot's standard MITM-style abort; wrong extracted-blob
  hash → `sha256sum -c` failure), then restored and reverified clean. Full analysis, the
  rejected alternatives, and the residual-risk framing: `docs/decisions/0003-xone-firmware.md`
  (**Status: Accepted**, not the originally-anticipated Proposed — the maintainer ruled on
  this mid-task rather than leaving it for later review).

  Full `make all` run (not a targeted rebuild): both `check-zimage-dtb.sh` and
  `check-linux-img.sh` pass, all assertions green, no regressions. `rootfs.tar` grew by
  ~140 KiB (9 small `.ko.xz` + one 70,620-byte firmware blob); `linux.img` still 61.3% free
  (well above the 15% floor). **Unverified without hardware (P3.13):** dongle pairing,
  wired-controller input, force feedback, LED/battery/audio sysfs paths — the build/link/
  depmod/vermagic/autoload/firmware-delivery chain is fully verified; device *function* is not.

- [x] **P3.3 — Module loading & firmware infra (A5, parity)** — [SONNET] — Size M — Depends: P3.1
  Reproduce the verified stock layout: `kmod` + `depmod` at image build, **eudev**
  hotplug autoload (modules.alias-driven), xz-compressed module install
  (`CONFIG_MODULE_COMPRESS_XZ=y` parity), and `/lib/firmware` populated from
  linux-firmware filtered to the stock 72-file inventory plus new module needs.
  **Done when:** plugging a supported dongle (verified on HW in P3.13) autoloads the
  right module; firmware list documented; image size impact recorded in P2.7's report.

  **Result: module-autoload half already done pre-task (kmod+depmod xz support,
  modules.dep/modules.alias populated — see the P3.3 (core) commit). This pass covers only
  `/lib/firmware` population.** `configs/mister_de10nano_defconfig` gained
  `BR2_PACKAGE_LINUX_FIRMWARE` + 9 sub-options (`MEDIATEK_MT7601U/MT7610E/MT7650/MT76X2E`,
  `RALINK_RT2XX`, `RTL_81XX/RTL_87XX/RTL_87XX_BT/RTL_88XX_BT`), `BR2_PACKAGE_WIRELESS_REGDB`
  (a separate package from linux-firmware for `regulatory.db`/`.p7s`), and
  `BR2_PACKAGE_LINUX_FIRMWARE_EXTRA` (new `package/linux-firmware-extra`, a small satellite
  package covering 4 files — `mediatek/mt7610u.bin`, `mediatek/mt7622pr2h.bin`,
  `mediatek/mt7668pr2h.bin`, `rtlwifi/rtl8723befw_36.bin` — that no Buildroot sub-option
  installs despite a confirmed in-tree 6.18.33 driver consumer; hash-pinned against the
  *same* linux-firmware tarball/hash the sibling package already uses, not a new source).

  **Build-verified against `output/images/rootfs.tar`** (not just `output/target`): **56 of
  the 66 stock inventory files present** — several via linux-firmware's own WHENCE-driven
  symlink pass (not obvious from Config.in alone; e.g. `rtl_bt/rtl8723d_config.bin` →
  `rtl8821c_config.bin`, `rtlwifi/rtl8192eefw.bin` → `rtl8192eu_nic.bin`), corrected mid-task
  after the first build attempt revealed it. **10 not reproduced**, each individually
  justified in `docs/firmware-parity.md`: 3 (`RTL8192E/*`) obsolete — the consuming driver
  (`drivers/staging/rtl8192e`) was deleted from the kernel in 6.13, and upstream
  linux-firmware has since dropped the firmware too (confirmed via `tar tf` on the actual
  pinned tarball, not assumed); 2 (`mediatek/mt7662u*.bin`) superseded — the in-tree
  `mt76x2u` driver requests the already-shipped top-level `mt7662*.bin` names instead; 2
  (`rtl_bt/rtl8192ee_fw.bin`/`rtl8192eu_fw.bin`) exist upstream but have zero in-tree
  consumer (BT chip-ID table entry removed); 1 (`rtlwifi/rtl8723defw.bin`) has no in-tree
  driver at all (would need a new out-of-tree package, out of scope); 2
  (`brcm/BCM20702A1-0b05-17cb.hcd`, `rt2870_sw_ch_offload.bin`) flagged for review — **not
  fabricated a source** — neither exists in the pinned upstream linux-firmware tarball nor is
  requested by any in-tree driver by that literal name.

  First `make all` attempt failed (`tar: ... Not found in archive`) — `linux-firmware-extra`'s
  custom `EXTRACT_CMDS` didn't account for the tarball's `linux-firmware-<version>/` wrapper
  directory; fixed (member paths wrapper-prefixed + `--strip-components=1`, matching the
  sibling package's own pattern) and rebuilt clean (`make linux-firmware-extra-dirclean &&
  make all`, exit 0). Both `check-zimage-dtb.sh` and `check-linux-img.sh` pass, all
  assertions green. Module-autoload machinery re-verified with no regression:
  `modules.dep`/`modules.alias` grew (57/977 lines) vs. pre-P3.3, not shrank. `/lib/firmware`
  totals 3.1 MiB in the built image (68 regular files + 23 symlinks); P3.3's own addition is
  ≈2.9 MiB against a 512 MiB image — `linux.img` still 60.6% free (well above the 15% floor).
  `docs/size-budget.md` regenerated with current post-P3.1/P3.2/P3.3 figures.
  **Unverified without hardware (P3.13):** actual dongle-plug autoload behavior — the
  build/depmod/vermagic/firmware-delivery chain is fully verified in the image; device
  *function* is not.

- [x] **P3.4 — WiFi userland parity** — [SONNET] — Size S — Depends: P3.3
  `wpa_supplicant` config/paths matching stock so `wifi.sh` and existing user configs
  work unchanged.
  **Done when:** `wifi.sh` from the current Distribution runs unmodified against the
  new rootfs (static analysis + [HW] confirmation in P3.13).

- [x] **P3.5 — Bluetooth parity** — [SONNET] — Size M — Depends: P2.1
  bluez package (library must provide `libbluetooth.so.3`), init script, pairing-state
  persistence per P2.4.
  **Done when:** SONAME check passes; `bluetoothd` starts on ro root; pairing DB
  persists across reboot ([HW] in P3.13).

- [x] **P3.6 — Samba parity** — [SONNET] — Size M — Depends: P2.3
  Modern Samba with stock-equivalent `smb.conf` (audit 4.14 → current syntax/behavior
  changes: SMB1 defaults, guest access, unix extensions). Preserve share layout and
  discoverability behavior users expect.
  **Done when:** config diff documented; `smbd`/`nmbd` (or modern equivalents) start on
  ro root; share is browsable from Windows/macOS ([HW]/LAN check in P3.13).

- [x] **P3.7 — SSH & FTP parity** — [SONNET] — Size S — Depends: P2.3
  Match stock daemon choices (verified: OpenSSH `sshd` + **proftpd**), host-key
  persistence per P2.4, and
  stock auth behavior (document the default-credential posture; keep parity, note the
  risk in the FAQ rather than silently hardening).
  **Done when:** both daemons start on ro root; keys persist; behavior documented.

- [x] **P3.8 — MIDI / MT-32 parity** — [SONNET] — Size S — Depends: P2.1
  fluidsynth/mt32 userland per P0.3 inventory; ALSA seq config as stock.
  **Done when:** packages present at compatible versions; ALSA MIDI device list matches
  stock ([HW] confirmation in P3.13).

- [x] **P3.9 — Python & Downloader compatibility (A6)** — [SONNET] — Size M — Depends: P2.1
  Run `Downloader_MiSTer`'s test suite (it has one) under the target Python via
  qemu-user chroot. Smoke-test a sample of popular community scripts (update_all, etc.)
  for 3.9→3.13 breakage (removed stdlib modules, syntax). Report incompatibilities
  upstream rather than pinning old Python; document any that block.
  **Done when:** Downloader suite green on-target-Python; findings in
  `docs/python-compat.md`.

- [x] **P3.10 — Network filesystem client parity** — [HAIKU] — Size S — Depends: P1.3, P2.1
  `mount.cifs` (cifs-utils) + NFS client utils per stock inventory, so community
  cifs/NFS mount scripts run unchanged. Kernel side was asserted in P1.3.
  **Done when:** a cifs and an nfs mount succeed from the running image (loop-back test
  acceptable pre-hardware).

- [x] **P3.11 — RTC parity** — [SONNET] — Size S — Depends: P1.7, P2.3
  hctosys/init integration for the i2c-gpio RTC add-on; graceful no-op without the
  board.
  **Done when:** boot with no RTC shows no errors; with RTC ([HW] in P3.13) system time
  is set from it.

- [x] **P3.12 — CI-runnable parity test suite** — [SONNET] — Size M — Depends: P3.1–P3.11
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

### Phase 3 follow-ups (discovered during P3.3–P3.12 review)

- [x] **P3.14 — BCM20702 Bluetooth dongle firmware** — [SONNET] [NET] — Size S — Depends: P3.3, P3.5
  Stock ships `brcm/BCM20702A1-0b05-17cb.hcd` (patch RAM for BCM20702-based BT dongles —
  common ASUS USB-BT400 & generics; `CONFIG_BT_HCIBTUSB_BCM=y`), but it is **not** in
  mainline linux-firmware, so P3.3 left it as a flagged gap. Source it via the **same
  vendor-firmware pattern approved for xow** (ADR 0003): a hash-pinned build-time fetch
  (e.g. `winterheart/broadcom-bt-firmware`), never a committed blob. **Needs maintainer OK
  to redistribute a second vendor firmware** (flagged, not yet approved).

- [x] **P3.15 — General ALSA userland parity** — [SONNET] — Size S — Depends: P2.1
  Stock ships the full ALSA CLI suite (`alsactl`, `alsamixer`, `amixer`, `aplay`,
  `arecord`, `alsabat`, `alsaloop`, `alsatplg`, `alsaucm`); our image has only the MIDI
  subset (P3.8 correctly stayed in scope). `alsactl` in particular is mixer save/restore.
  Enable the matching `BR2_PACKAGE_ALSA_UTILS_*` options. (`aserver` has no Buildroot
  sub-option — document as an accepted gap.) See `docs/midi-mt32-parity.md` §5.

- [ ] **Downloader `downloader.sh` python3.9 path** — note, no action in this tree — Depends: —
  `downloader.sh` hardcodes `/usr/bin/python3.9` to select its Nuitka fast-path; on our
  `python3.14` it falls back to pure-Python (functional after the P3.9 ssl/zlib fix, just
  slower first run). Lives on `/media/fat`, delivered by the Downloader system — not our
  rootfs to patch; resolves when the Downloader updates its launcher. See
  `docs/python-compat.md`.

- [ ] **Branch/PR reconciliation before master merge** — housekeeping — Depends: —
  `phase3-parity` carries P2.10 (duplicated with PR #5) and P2.7 (superseded by
  cf36ce7, was PR #6). Close PRs #5/#6 as superseded when `phase3-parity` merges to
  `master`, or reconcile history first.

---

## Phase 4 — Release engineering, CI & distribution

Exit criterion: beta users successfully opt in via `db.json` and can roll back (P4.10).

- [ ] **P4.1 — CI build workflow** — [SONNET] — Size L — Depends: P1.10, P2.5
  `.github/workflows/build.yml`: pinned container image (digest, not tag); two-stage
  build (initramfs config, then main); run `scripts/ci-tests.sh` (P3.12) and the ABI
  checker (P2.2); upload build artifacts on every push; hard timeout budget documented.

  **⚠ CACHING IS NON-OPTIONAL — a cold Buildroot build is 30–60 min; a warm one must be
  minutes.** Cache FOUR things with `actions/cache` (pin the action by commit SHA):
  1. **The Buildroot release tarball** — key on `BUILDROOT_VERSION` (it changes rarely).
  2. **The `dl/` download cache** — key on `BUILDROOT_VERSION` + `hashFiles(defconfig)`,
     with a `restore-keys` prefix on just `BUILDROOT_VERSION` so a partial cache still
     hydrates. **Our `dl/` is already at the repo root (not under `output/`)**, so it
     survives `make clean` — do NOT move it under `output/`, which CI/clean wipes.
  3. **The Buildroot host toolchain** (`output/host` + the per-build stamps) — key on
     `BUILDROOT_VERSION` + `hashFiles(defconfig, linux.config, linux-patches/**)` so a
     kernel-config or patch change correctly busts it. This is the big win: it skips the
     cross-compiler bootstrap.
  4. **ccache** — use a ccache GitHub action, and pass Buildroot the flags to actually
     use it: `make … BR2_CCACHE=y BR2_CCACHE_DIR=$GITHUB_WORKSPACE/.ccache
     BR2_CCACHE_USE_BASEDIR=y`. (`USE_BASEDIR` rewrites absolute paths so the cache is
     relocatable across runners — without it the cache mostly misses.)

  Mind the **10 GB GitHub cache ceiling** — document an evict policy or an external
  mirror if the four caches together approach it.
  **Done when:** clean-cache and warm-cache runs both green; warm run < 60 min (target:
  minutes, given the toolchain + ccache caches) or the budget is re-documented with
  rationale.

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
  Verify the 7z extracts with the Downloader's **pinned `7za`** (P0.6), and that
  `files/linux/` carries the full stock auxiliary payload (`updateboot`, config
  templates, `u-boot.txt_example`, …) — the updater rsyncs it over `/media/fat/linux/`,
  and `updateboot` flashes whatever `uboot.img` we ship (must be byte-identical stock).
  **Done when:** a draft release from a test tag contains all assets; attestation
  verifies with `gh attestation verify`; 7z layout byte-compared against the contract;
  shipped `uboot.img` hash equals the stock release's.

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
  `renovate.json` to manage: the Buildroot 2026.05.x tarball version + SHA-256
  (custom/regex manager over the pin file from P1.1), morrownr package commit pins (git
  datasource), CI container image digests, and GitHub Actions versions. Every Renovate
  PR must trigger the full CI suite (build, patch-apply, ABI checks, reproducibility).
  Automerge stays OFF — a human reviews green PRs. **Reference:**
  `/mnt/source/sb-enema/renovate.json` — a working custom regex manager for
  `BUILDROOT_VERSION` (github-tags datasource, `allowedVersions` pinned to `2026.05.x`);
  use it as the template.
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

## Phase 5 — Full SD-card image + U-Boot from source (deferred; do not start before Phase 4 exit)

**Rewritten 2026-07-13 per [ADR 0017](docs/decisions/0017-uboot-from-mister-fork-full-sd-image.md).**
The mainline U-Boot port is abandoned: Phase 5 builds the proven fork
(`MiSTer-devel/u-boot_MiSTer`, U-Boot 2017.03) from source, pinned as a **git
submodule**, and adds a **full flashable SD-card image** (kernel + `linux.img` +
bootloader + mr-fusion-parity payload) so a fresh card can be written without
mr-fusion or the Windows SD installer. §8's posture is unchanged: highest blast
radius, everything here is opt-in, separate from `linux.img` updates, gated on a
drilled recovery procedure. **The default channel keeps shipping the stock
`uboot.img` byte-identical (P4.4) — nothing in this phase changes that.**

- [ ] **P5.1 — [NET] U-Boot submodule + from-source build** — [SONNET] — Size M — Depends: P4.10
  Add the `u-boot/` git submodule → `MiSTer-devel/u-boot_MiSTer` pinned at
  **`8dcc3484aac6f07314538e82530d446083085e12`** — simultaneously the `MiSTer` branch
  HEAD (verified 2026-07-13; unmoved since 2021) and the exact commit the shipped
  `uboot.img` was proven built from (boot-chain §3.1). Set `shallow = true` in
  `.gitmodules`; CI checkouts gain `submodules: true`. Wire into Buildroot:
  `BR2_TARGET_UBOOT` + `UBOOT_OVERRIDE_SRCDIR` pointing at the submodule (via
  `BR2_PACKAGE_OVERRIDE_FILE`; fall back to `BR2_TARGET_UBOOT_CUSTOM_TARBALL`
  generated from the submodule if the override rsync misbehaves). Start from the
  fork's own `MiSTer_defconfig` (boot-chain §10: both defconfigs share the env
  header, but `MiSTer_defconfig` is the likelier shipped one). Output
  `u-boot-with-spl.sfp`, renamed `uboot.img`. A 2017.03 tree may not compile under
  2026 toolchains: carry **build fixes only** in `uboot-patches/` (each with a
  provenance header per standing rule 2 — never behaviour changes); worst case, pin
  the Arm GNU 10.2-2020.11 toolchain stock used (boot-chain §3.2). The artifact is a
  build output only at this point — shipped nowhere.
  **Done when:** CI builds `uboot.img` from the submodule; the SPL socfpga header
  validates (validation word, length, checksum per boot-chain §2); layout is
  4×64 KiB SPL copies + uImage at `0x40000`; size fits the `0xA2` partition.

- [ ] **P5.2 — Behavioural-parity validation of the built U-Boot** — [OPUS] — Size M — Depends: P5.1
  Byte identity is impossible (boot-chain §3.2) — prove behavioural parity instead.
  Script the stock-vs-built comparison: the default-environment blob **must match
  boot-chain §3.1's 20 entries verbatim** (including the malformed entry-15
  fingerprint); uImage header fields (load/entry `0x01000040`, os/arch/type); `mt`
  present in the command table; version-string and timestamp diffs enumerated and
  individually explained. Any *unexplained* delta fails the task.
  **Done when:** `docs/verification/uboot-from-source.md` records the full diff list
  with per-item explanations and a PASS verdict; the comparison script lives in
  `scripts/` and runs in CI.

- [ ] **P5.3 — [NET] Full SD-card image (`sdcard.img`)** — [SONNET] — Size L — Depends: P1.10, P2.5, P4.4 (P5.1 + P5.2 for the built-U-Boot variant)
  genimage post-image step producing a complete, dd-able card image: MBR; **p1** =
  FAT32 data partition; **p2** = type **`0xA2`**, ≥ 1 MiB, with `uboot.img` written
  raw at its start (SPL contract, boot-chain §2.1). **p1 payload parity target: "a
  card as mr-fusion leaves it, plus Update_All."** First inventory what
  [`MiSTer-devel/mr-fusion`](https://github.com/MiSTer-devel/mr-fusion) installs (at
  a pinned release) into `docs/verification/sdcard-payload.md`, then reproduce it:
  the P0.6 `files/linux/` payload (`linux.img`, `zImage_dtb`, `uboot.img`,
  `updateboot`, config templates, `u-boot.txt_example`), `menu.rbf` + the stock
  `MiSTer` binary + the standard folder tree, the base `Scripts/` set mr-fusion
  ships (Downloader script, WiFi setup script), **plus a recent
  [`Scripts/update_all.sh`](https://github.com/theypsilon/Update_All_MiSTer)** —
  a single self-updating file that runs the Downloader under the hood; no further
  on-card dependencies (verified against its README; re-verify at implementation).
  All payload files fetched at build time, pinned by commit/release + hash, never
  committed (standing rule 1). Reproduce mr-fusion's per-board `ethaddr`
  provisioning: a first-boot mechanism writes `linux/u-boot.txt` with a unique
  locally-administered MAC (else every board shares the compiled-in fallback
  `02:03:04:05:06:07`, boot-chain §3.1 entry 14); mirror mr-fusion's optional
  pre-seeding hooks (`wpa_supplicant.conf`, `samba.sh`, user `Scripts/`). Default
  the embedded `uboot.img` to the **stock blob** (fetched by hash per P4.4); the
  P5.1 build goes in only behind an explicit build flag — change one variable at a
  time. Published as a separate release asset (`sdcard.img.xz`), **never** part of
  `release_*.7z` and never referenced by db.json.
  **Done when:** CI loop-mounts the image and asserts partition types/offsets
  (`sfdisk -d`), the FAT payload inventory against `sdcard-payload.md`, and `cmp`
  of p2's head against `uboot.img`; the image's FAT + `linux.img` pass the P1.12
  QEMU initramfs harness; flashing instructions documented.

- [ ] **P5.4 — [HW] SD image + built U-Boot hardware matrix & recovery drill** — human + [OPUS] — Size L — Depends: P5.2, P5.3
  (a) Flash `sdcard.img` (stock-blob variant) to a fresh card → boots to menu;
  first-boot `ethaddr` provisioning verified (unique MAC, survives reboot);
  `update_all.sh` completes a run. (b) The built-U-Boot variant → boots to menu;
  `u-boot.txt` override honored; warm-reboot core handoff works; an `updateboot`
  flash + env-wipe cycle leaves the board bootable. (c) Execute the documented
  brick-recovery procedure from an actually-bricked state at least once before any
  user sees either artifact.
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

**Status: DEFERRED, NOT WAIVED — [ADR 0014](docs/decisions/0014-sustainability-deferred-not-waived.md)
(2026-07-12).** Phase 1+ proceeds **for personal use**. The gate now blocks **P4.10
(publication)**, not Phase 1 development.

> **Unsigned ⇒ personal use only.** Do not publish an image, a `db.json`, or a Downloader
> entry that other people's devices consume until a named human has signed.

Two things this gate is **not**, recorded because both are easy to assume:

* It is **not discharged by `git commit -s`.** That adds a `Signed-off-by:` trailer — a
  Developer Certificate of Origin attestation about the provenance of *one patch*. (`-S`,
  separately, is a GPG signature proving *who authored* a commit.) Neither says anything
  about who will still be tracking 6.18.y in 2028. What §C asks for is one sentence in the
  README naming a person. Sign off on commits if you like; it does not move this gate.
* It is **not something Claude can hold.** Claude can do the authoring, and that genuinely
  changes the labour estimate — but it has no continuity between sessions (it cannot watch
  6.18.y or notice a CVE), no hardware (verifying a stable bump means booting a DE10-Nano),
  and cannot be paged. Renovate is a *mechanism*, not an owner: a bot whose PRs nobody
  merges or tests is a stale fork with extra steps. The gate asks for **accountability and
  continuity**, which is precisely the part a model cannot supply.

The failure mode this guards against is not a decision — it is **drift**: reaching a working
image, sharing it because it works, and never revisiting. **P4.10 must re-read ADR 0014.**
