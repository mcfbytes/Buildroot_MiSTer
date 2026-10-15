# Installer build: what goes into stage 1, `make sdcard`, and the splash test

**Task:** P5.3. Companion to `docs/decisions/0020-sdcard-exfat-reformat-installer.md`
(the installer's product decisions — the reformat itself, the console/LED
feedback, the HDMI splash), `docs/decisions/0033-one-initramfs-installer-in-stage-1.md`
(why the installer is not its own build any more) and `docs/installer-init.md`
(the installer script itself). This doc covers the build-time pieces: how the
installer gets into the ONE stage-1 cpio, the BusyBox applets it relies on,
what `scripts/mk-sdcard.sh` does with the result, and the unit test that guards
the splash, `scripts/test-installer-splash.sh`.

Until ADR 0033 (2026-10-15) the installer was a second Buildroot configuration
(`configs/mister_installer_defconfig`: static musl, `O=output-installer`, its own
toolchain, BusyBox config and post-build script) whose cpio `mk-sdcard.sh`
relinked into a second kernel. All of that is deleted; `output-installer/` and
`output-installer-kernel/` no longer exist.

## How the installer gets into the image

`BR2_PACKAGE_MISTER_INITRAMFS_INSTALLER` (set in `configs/mister_de10nano_defconfig`;
ARM only, so the DE25 cannot set it; the splash frames come only with
`BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE`)
makes `package/mister-initramfs/mister-initramfs.mk` add four things to the stage-1
cpio, which the DE10 kernel embeds like any other stage 1 (ADR 0002):

| In the cpio | From |
|---|---|
| `/usr/libexec/mister-installer/install` | `board/mister/de10nano/initramfs-overlay/`, the DE10's `BR2_PACKAGE_MISTER_INITRAMFS_BOARD_OVERLAY` (its `usr/libexec/mister-installer/` only with the installer option) |
| `/usr/libexec/mister-installer/mkfs.exfat` | the static glibc `mister-initramfs-exfatprogs` build, stripped; **off PATH** (ADR 0033 §6) |
| `/usr/share/mister-installer/splash-<WxH>.raw.gz` | rendered from the PNGs in `board/mister/de10nano/installer-splash/` |
| `/usr/bin/itsalive` | `package/itsalive` (static glibc), the same binary the exFAT repair's splash uses (ADR 0026 §6) |

Everything else the installer runs is the shared stage-1 BusyBox. There is no
util-linux, no `sfdisk` (the MBR is written from shell, tested byte-identical to
`sfdisk` by `scripts/test-installer-mbr.sh`; ADR 0033 §4) and no second toolchain.

The same package also writes the installer **flag** magic block
(`/usr/lib/mister/install-flag.bin`, also installed to
`output/images/mister-install-flag.bin`) into every board's cpio, because every
board's `/init` runs the read-only probe. What the flag is and how the probe and
installer use it: `docs/installer-init.md#the-flag`.

`package/mister-initramfs/verify.sh` runs at the end of the package build and fails it
on any of: an applet the installer runs missing, `mkfs.exfat` or `itsalive` not
static, `mkfs.exfat` anywhere on a `bin`/`sbin` directory, a splash frame of the wrong
size, a flag block that is not one 512-byte magic sector, the installer and the probe
disagreeing on `FLAG_LBA`, 32-bit shell arithmetic, or the shipped `ash` unable to
parse `/init`, the probe or the installer (under `qemu-arm`). Its installer section
is skipped when the option is off, and the build fails if the installer tree is
present with it off.

### Splash frame rendering

The installer's splash section (ADR 0020 §9.2) feeds `itsalive image` a gzipped raw
BGRX8888 frame per video mode from `/usr/share/mister-installer/`. Those frames are
pure derivations of the PNGs in `board/mister/de10nano/installer-splash/`, so they
are rendered at build time by `mister-initramfs.mk` (`png2raw.py`, the same converter
the exFAT repair's frames use), rather than committed next to their source: two
fewer binaries in git, and a change to a PNG cannot ship with a stale frame. The
converter is pure Python 3, which Buildroot already needs on the host.

Hard-checked, not merely hoped: `verify.sh` decompresses each frame and checks the
raw byte count is exactly `width * height * 4` for each mode. `itsalive image`
refuses a frame of the wrong size at run time — a failure
`test-installer-splash.sh` cannot see (it never runs the real `itsalive`; see
below) and a user would only meet as "the screen came up blank." Better to
fail the build.

### Black-screen time is still a budget

The installer's cpio is no longer a separate artefact, but its bytes still sit
between power-on and the splash picture twice over — U-Boot reads them off the card
inside `zImage_dtb`, then the kernel inflates them before `/init` can run. The old
installer cpio had to be trimmed for this (util-linux's ~60 static binaries were 13.3
MB of cpio, 1.0 s of CPU to gunzip on a DE10-Nano, 0.27 s once trimmed; measured
2026-09-22). The merged stage-1 cpio is 3,237,888 B (1,649,943 B gzip -9); the
previous stage 1, with `itsalive`, was 2,539,008 B (1,296,953 gz). The old musl
installer cpio was 3,266,048 B. Anything added to it from here costs boot time on
every DE10 boot, not just the first. See ADR 0020 §9.2 and ADR 0033 §6.

## BusyBox applets

There is one BusyBox config for every stage-1 cpio:
`board/mister/common/initramfs-busybox.config` (ADR 0002, `docs/buildroot-config.md`
§8.5). The installer used to have its own, derived from it
(`installer-busybox.config`, deleted); its additions were folded in. Each applet's
one-line reason is in that file's header; the longer history is here.

### What the installer added on top of the stage-1 set, and why

Every older stage-1 symbol is unchanged (see the file for their justifications).
Added for the installer (ADR 0033): `DD` (+`FEATURE_DD_IBS_OBS`), `CMP`, `WC`,
`HEXDUMP`, `BLOCKDEV`, `BLKID` (+`FEATURE_BLKID_TYPE`), `CP`, `MV`, `DU`, `CUT`,
`REBOOT`, `FEATURE_SH_MATH_64` and `FEATURE_TEST_64`. `RM`, `ZCAT` and `TIMEOUT` were already on for
the exFAT repair; `GUNZIP`'s sibling `zcat` is what the installer calls.

- **`CONFIG_CP`** — `cp -a` copies `mister-payload/*` into tmpfs, then back
  onto the freshly reformatted exFAT partition (ADR 0020 §2). `-a` is on
  BusyBox `cp`'s base option string unconditionally (`coreutils/cp.c`:
  `"apdR"` is in `FILEUTILS_CP_OPTSTR`, not gated behind
  `FEATURE_CP_LONG_OPTIONS`), so no extra `FEATURE_CP_*` symbol is needed.
- **`CONFIG_DD` + `CONFIG_FEATURE_DD_IBS_OBS`** — writes the pinned stock
  `uboot.img` raw onto the 0xA2 partition, and the MBR and the flag wipe with
  `conv=notrunc,fsync` (ADR 0020 §2; ADR 0033 §4). `conv=` is gated behind
  `FEATURE_DD_IBS_OBS`, which the old installer config left off and the merged one
  needs. The probe's 512-byte read at LBA 1024 uses `dd` too.
- **`CONFIG_CMP`, `CONFIG_WC`** — the probe compares the flag block against
  `install-flag.bin`, and the MBR writer checks its sector is exactly 512 bytes and
  reads it back before trusting the write (ADR 0033 §4).
- **`CONFIG_REBOOT`** — the final handoff to the real, just-installed MiSTer
  (ADR 0020 §2 last step). `CONFIG_HALT` was already on in stage 1 (its
  rescue-shell banner never calls it) but `CONFIG_REBOOT` was not — these are
  independent booleans in the same BusyBox source file.
- **`CONFIG_BLOCKDEV`** — reads the target medium's geometry before
  repartitioning it, flushes buffers, and `--rereadpt` makes the kernel re-read the
  new table (ADR 0020 §2, ADR 0033 §4). `/sys/block/<dev>/size` is the primary
  source; `blockdev --getsize64` is the sanity-check/fallback path.
- **`CONFIG_BLKID`** — `volume_label` reads the label `blkid` reports, for the
  card-state decision (`docs/installer-init.md#card-states`).
- **`CONFIG_HEXDUMP`** — turns `/dev/urandom` bytes into the random
  locally-administered MAC written to `linux/u-boot.txt` (ADR 0020 §2,
  "generates a random locally-administered MAC"), and reads the one MBR byte the
  probe checks. Picked over `CONFIG_AWK`: smaller, and `hexdump -e` is the standard
  idiom for "N bytes as hex octets." The scripts use `hexdump` (not `od`, which is
  left off).
- **`CONFIG_RM`** — deletes the payload's `linux/linux.img.gz` from the
  finished card once the installer has expanded it to `linux/linux.img` (ADR 0020
  §3, step 5b). This was MISSING until PR #76, while the script called `rm -f`
  anyway: the call was a silent command-not-found no-op, so every installed
  card kept the whole ~80 MiB gzip forever. `rm -f` needs only this base
  symbol — `coreutils/rm.c`'s `getopt32` optstring `"fiRrv"` is
  unconditional and not gated behind any `FEATURE_RM_*`, exactly like
  `CONFIG_CP` above. The installer still verifies the file is gone afterwards and
  falls back to truncating it, so a future regression degrades loudly instead of
  silently. `rm -rf` (the staged payload dir, after the commit point — ADR 0020 §8)
  uses the same base symbol: `-r`/`-R` are in that same optstring.
- **`CONFIG_MV`** — the recoverable install ordering (ADR 0020 §8, issue
  #185). Two jobs, and neither has a workable substitute here: (a) the
  copy-back writes into `mister-payload.part/` and RENAMES it to
  `mister-payload/` only once complete, which is the single fact that lets
  the next boot tell "a payload worth re-installing from" apart from "half a
  payload and no source left"; (b) the commit phase moves the payload's
  entries from that directory to their final places at the card root, and a
  rename is what keeps that phase from re-writing 150+ MiB — copying instead
  would hand back every second the reorder bought and would widen the very
  window it exists to close. `mv -f` needs only this base symbol:
  `coreutils/mv.c`'s `getopt32long` optstring `"finTt:v"` is unconditional
  and `OPT_FORCE` is not gated behind any `FEATURE_MV_*` (the long-option
  names are, and this config has `CONFIG_LONG_OPTS` off, so only the short
  forms are used). **Note the installer relies on one non-obvious behaviour:**
  `mv` cannot rename over an existing NON-EMPTY directory (`rename(2)` gives
  `ENOTEMPTY` and `mv` only falls back to copy+delete for `EXDEV`), so it
  descends the one directory that collides — `linux/` — and moves its children
  individually.
- **`CONFIG_DU` + `CONFIG_CUT`** — the RAM-budget check (ADR 0020 §2,
  "measure free RAM first ... copy the base and SKIP cores rather than
  OOM-bricking"). The installer runs `du -sk "$SRC_PAYLOAD" | cut -f1` to size the
  full payload and the `_Console` cores subtree, then decides whether both
  fit the tmpfs budget. There is no clean POSIX-sh substitute for a
  recursive directory size here: `find`/`stat` are off too, so `du`
  is the applet built for the job and `cut` extracts its size field.
  (`basename`/`dirname` are handled with `${var%/*}`/`${var##*/}` parameter
  expansion and are NOT built.)
- **`CONFIG_ZCAT`** — the payload's `linux/linux.img.gz`
  decompress (ADR 0020 §3). `linux.img` is a 512 MiB apparent-size ext4
  image; on the shipped FAT32 partition that would be 512 MiB non-sparse,
  far larger than the `mem=511M` installer's whole RAM. So `mk-sdcard.sh`
  ships it gzipped (~80 MiB of real data) and the installer streams
  `zcat linux/linux.img.gz > linux/linux.img` straight onto the
  freshly-formatted exFAT card AFTER copy-back — the full 512 MiB is
  materialised on disk, never in the RAM tmpfs. The kernel already carries its
  own, separate `CONFIG_RD_GZIP` (`external.mk`) — unrelated to this userspace applet.
- **`CONFIG_TIMEOUT`** — brackets every `itsalive` call in the HDMI
  splash (ADR 0020 §9, issue #185, 2026-09-21). The splash's hard rule is
  that it can never fail — or hang — an install, and a tool that talks to
  the fabric over a mailbox and to the ADV7513 over I²C has more ways to
  wedge than a `printf`. `itsalive` bounds its own mailbox wait (exit 11),
  but nothing bounds a driver that never returns from an ioctl; `timeout N`
  is the belt, and the installer routes every invocation through one wrapper
  that applies it.
- **`CONFIG_FEATURE_SH_MATH_64`** — the installer's sector arithmetic. With it off,
  `$((...))` is 32-bit and a card past 1 TiB overflows (a latent defect of the old
  musl installer too). `verify.sh` fails the build without it (ADR 0033 §4).
- **`CONFIG_FEATURE_TEST_64`** — the same for `[ a -le b ]`. With it off, `[` rejects
  any operand past 2^31−1 with "out of range" — including the installer's own
  `MBR_MAX_SECTORS` guard, so *every* install failed. `verify.sh` checks this one too.

`blkid`, `blockdev`, `dmesg`, `findfs` and `hexdump` are only BusyBox applets now.
The old installer also carried util-linux's own copies of those names beside them
(a side effect of building util-linux for `sfdisk`); with util-linux gone there is
exactly one implementation of each.

### Symbols from stage 1 — load-bearing; do not drop without re-reading ADR 0002

The installer runs on the same applets as the rest of stage 1, so everything in the
config's header is load-bearing for it too. The ones that bit the installer:

- `CONFIG_LFS` — `allnoconfig` turns this OFF and the build then FAILS with
  "size of array 'BUG_off_t_size_is_misdetected' is negative" (`libbb.h:335`):
  Buildroot compiles BusyBox with `-D_FILE_OFFSET_BITS=64`, so `off_t` is
  64-bit, but `!CONFIG_LFS` makes BusyBox's `uoff_t` a 32-bit
  `unsigned long`. It is also simply correct: a MiSTer data partition is
  routinely >2 GB (the reference card is 238.7 GB).
- **`CONFIG_FEATURE_MOUNT_FLAGS` — the one that silently bricks you.**
  Without it BusyBox's `mount` does not know `sync`, `dirsync`, `noatime`,
  `nodiratime`, `move` or `bind` (`util-linux/mount.c:2320`
  `mount_options[]` is wrapped in `IF_FEATURE_MOUNT_FLAGS`). It would pass
  them through to the filesystem as *data*, and vfat/exfat use the new mount
  API, which rejects unknown parameters with `EINVAL`. Result: the data
  partition does not mount and the reformat cannot proceed.
- `CONFIG_CTTYHACK` + `CONFIG_SETSID` — give the rescue shell a controlling tty.
- `CONFIG_FINDFS` + `CONFIG_VOLUMEID` (+`EXT`, `FAT`, `EXFAT`) — resolve `root=`
  (and, for the installer, tell the card's filesystem apart).
- `CONFIG_TAIL`, `CONFIG_DMESG`/`LS`/`CAT` — the rescue banner's diagnostics.
- `CONFIG_ASH_TEST` — `ash`'s `[` builtin. See the kconfig trap below.
- `CONFIG_FEATURE_SH_MATH` — `$((arith))`. See the kconfig trap below.

### kconfig silently discards symbols it does not recognise

A wrong `CONFIG_` name does not warn, does not fail the build, and leaves no
trace in the cpio — it just quietly produces a BusyBox that cannot run
`/init`. Two of these shipped in stage 1's config and were caught ONLY by
booting the result under QEMU:

- `CONFIG_ASH_BUILTIN_TEST` / `_ECHO` / `_PRINTF` are the PRE-1.22
  spellings. 1.37 (and 1.38, pinned here) calls them `CONFIG_ASH_TEST` /
  `ASH_ECHO` / `ASH_PRINTF`. Under the old names `ash` has no `[` builtin,
  and `/init` dies on its very first test with
  `"/init: line 98: [: not found"` — while still printing a rescue banner
  that misleadingly blamed the kernel command line.
- It is `CONFIG_FEATURE_SH_MATH`, not `CONFIG_SH_MATH`. Without it `ash`
  will not even PARSE `/init`: `"syntax error: support for $((arith)) is
  disabled"` → pid 1 exits → instant kernel panic.

`verify.sh` is the guard now: it checks that every applet the installer calls is
really in the tree, and that `ash -n` parses all three scripts. After a BusyBox bump
add any new applet to its lists rather than assuming symbol names survived.

### Regenerating the config after a BusyBox bump

`board/mister/common/initramfs-busybox.config` is hand-derived; NOT regenerated
verbatim by `make busybox-update-config` — do that, then re-apply every addition
listed above and in the file's header.

1. `make allnoconfig` in a pristine BusyBox tree at the version Buildroot
   pins (1.38.0 today) → 8 symbols on.
2. Force-enable exactly the symbols stage 1's scripts need, PLUS every
   installer addition listed above.
3. `make olddefconfig` (pulls in their mandatory sub-symbols).
4. Set `CONFIG_FEATURE_EDITING_MAX_LEN=1024` (`allnoconfig` leaves it 0,
   which makes the rescue shell's line editor useless), and `olddefconfig`
   again.

## `make sdcard` (`scripts/mk-sdcard.sh`)

Pure assembly of `make all`'s outputs — no Buildroot call, no kernel build, no
relink. It needs `output/images/{linux.img,zImage_dtb,7za,mister-initramfs.cpio,
mister-install-flag.bin}` and the host tools genimage, mtools, dosfstools, xz, gzip
and cmp. Five steps:

1. **Fetch and stage the stock payload** (`scripts/fetch-sdcard-payload.sh`, hash-pinned;
   `docs/verification/sdcard-payload.md`).
2. **Overlay our outputs**: our `linux.img` gzipped to `linux/linux.img.gz` (so the 512
   MiB image never transits the installer's RAM), `7za`, and the kernel. The kernel
   goes at the FAT root as `linux/zImage_dtb`, where U-Boot loads it, and it is
   **byte-identical to `output/images/zImage_dtb`**, the one the Downloader ships;
   `mister-payload/linux/zImage_dtb` no longer exists. `menu.rbf` is copied to the
   FAT root too (U-Boot's `fpgaload` reads it from there, ADR 0020 §7).
3. **Build the FAT32 `vfat`** with the payload (`mkfs.vfat` + `mcopy`), sized to the
   content plus slack.
4. **genimage** (`board/mister/de10nano/genimage-sdcard.cfg`): `p1` the FAT32 (1M offset),
   `p2` type `0xA2` carrying the stock `uboot.img`, and `p3` the installer flag
   (`align = 512K`, so it can sit at LBA 1024 in the gap before `p1`). The script then
   reads LBA 1024 of the result back and requires it to equal the flag block.
5. **Publish** `sdcard.img` and `sdcard.img.xz` (`sdcard-full.img` with
   `SDCARD_CORES=1`).

**The guard.** Because the card has only one kernel, that kernel must carry the
installer. `mk-sdcard.sh` refuses to run unless `mister-initramfs.cpio` contains
`usr/libexec/mister-installer/install` AND the kernel build's
`usr/initramfs_inc_data` decompresses to exactly the current
`output/images/mister-initramfs.cpio` AND `zImage_dtb` is not older than that file. A
stale kernel (an installer change that `make all` never relinked into the kernel) is
an error telling you to run `make linux-rebuild all`, never a silently wrong card.

**Cost.** The old step 1 (the musl installer build) took 19 min (release run
38261354093) and 29 min (run 37182947808) of a ~87–91 min release build job; the two
kernel relinks took about a minute each (older docs said ~15 min each way; that was
stale). The new sdcard step's duration will be measured on the first release run.
`docs/ci.md#sdcard-timing-6h-cap` has the CI side.

Checking the result: `scripts/check-sdcard.sh` (static: partition layout, the `0xA2` head, the flag, the payload inventory)
and `scripts/test-sdcard-install.sh` (boots the image in QEMU through a full install
and a second boot).

## `scripts/test-installer-splash.sh`

### Why a separate test

The splash lives inside a PID-1 `/init` that can brick a board, and its only
other coverage is `scripts/test-sdcard-install.sh` (ADR 0020 §8.6) — which
needs a fully built `sdcard.img` and boots QEMU twice. That is far too slow
and too heavy to catch an ordinary shell mistake. This test needs no build
artifacts, no QEMU and no privilege: it extracts the splash section verbatim
from `/init`, sources it under a POSIX shell against a STUBBED `/proc/uptime`
and `/sys/class/leds` tree, and asserts the behaviour directly. It runs in
about a second, so it can gate every PR.

The HDMI half (ADR 0020 §9.4) is tested the same way: `/init` only ever
reaches `itsalive` through one wrapper and four retargetable paths, so the
binary is replaced by a RECORDING STUB whose exit status per subcommand the
test sets, and the assertions are on what `/init` did with each answer — see
ADR 0020 §9.4 for the scenario list (absent binary, no-bitstream, other `up`
failures, a hang, the happy path, the 480p knob, a missing frame, and the
three terminal states).

### What it cannot tell you

It exercises the splash in isolation, not the install flow that calls it.
That the steps fire in the right order, against real hardware, with a real
LED — and that the stub's answers are the ones the real `itsalive` gives on
a DE10-Nano — is `test-sdcard-install.sh`'s job (ADR 0020 §8.6) and
ultimately P5.4's. See `docs/installer-init.md` for what the splash section
itself does and ADR 0020 §9 for the picture.
