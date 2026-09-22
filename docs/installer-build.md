# Installer cpio build: post-build script, BusyBox config, and the splash test

**Task:** P5.3. Companion to `docs/decisions/0020-sdcard-exfat-reformat-installer.md`
(the installer's product decisions — the reformat itself, the console/LED
feedback, the HDMI splash) and `docs/installer-init.md` (`/init` itself). This
doc covers the three build-time pieces that assemble the installer's
`rootfs.cpio`, referenced from `configs/mister_installer_defconfig`
(`docs/buildroot-config.md` §9): `board/mister/de10nano/installer-post-build.sh`,
`board/mister/de10nano/installer-busybox.config`, and the unit test that
guards both, `scripts/test-installer-splash.sh`.

## `installer-post-build.sh`

Runs after the INSTALLER target filesystem is assembled, before the cpio is
generated (`BR2_ROOTFS_POST_BUILD_SCRIPT` in `configs/mister_installer_defconfig`).
It is a separate script from the DE10 image's own `post-build.sh`: nothing in
that one applies to a throwaway cpio with no `/etc/shadow` and no
`/MiSTer.version`. Like every post-build script in this tree it must stay
reproducible — no timestamps, no randomness.

### Splash frame rendering

`/init`'s splash section (ADR 0020 §9.2) feeds `itsalive image` a gzipped raw
BGRX8888 frame per video mode from `/usr/share/mister-installer/`. Those
frames are pure derivations of the PNGs in
`board/mister/de10nano/installer-splash/`, so they are rendered HERE, at
build time, rather than committed next to their source: two fewer binaries in
git, and a change to a PNG cannot ship with a stale frame. The converter
(`png2raw.py`) is pure Python 3, which Buildroot already needs on the host,
so this adds no new host dependency.

Hard-checked, not merely hoped: the script decompresses its own output and
checks the raw byte count is exactly `width * height * 4` for each mode.
`itsalive image` refuses a frame of the wrong size at run time — a failure
`test-installer-splash.sh` cannot see (it never runs the real `itsalive`; see
below) and a user would only meet as "the screen came up blank." Better to
fail the build.

### The util-linux trim

`/init` needs util-linux for `sfdisk`, and Buildroot has no finer knob than
`BR2_PACKAGE_UTIL_LINUX_BINARIES` (`--enable-all-programs`): ~60 static
binaries (`lsns`, `lscpu`, `swapon`, ...) and ~10 MB of the cpio's ~13 MB, and
nothing in the installer ever executes them. Every byte of it sits between
power-on and the splash picture twice over — U-Boot reads it off the card
inside `zImage_dtb`, then the kernel inflates it before `/init` can run.
Measured on a DE10-Nano (2026-09-22): gunzipping the cpio took 1.0 s of CPU
as built and 0.27 s trimmed (6.7 MB → 1.7 MB gzipped; cpio itself 13.3 MB →
3.3 MB). See also ADR 0020 §9.2, "black-screen time is a budget." So every
util-linux file NOT in `UTIL_LINUX_KEEP` goes.

The keep list is exactly the util-linux programs `/init` runs. Several of
those names shadow a BusyBox applet of the same name (`dmesg`, `findfs`,
...), so silently dropping one from the keep list would swap implementations
under `/init` rather than fail anything — instead, after the trim, the
script re-checks that every kept name still exists in the target under
`bin/`, `sbin/`, `usr/bin/` or `usr/sbin/`, and fails the build if one is
missing.

## `installer-busybox.config`

The installer's BusyBox config runs once, in RAM, on a brand-new card's first
boot, to sfdisk/dd-uboot.img/mkfs.exfat/copy-back/MAC-gen/reboot into the
real MiSTer (ADR 0020 §2, in the recoverable order ADR 0020 §8 fixed it
into). It shares stage 1's shape (static musl, tiny, RAM-resident, deleted at
handoff) closely enough that it started as a literal copy of
`board/mister/common/initramfs-busybox.config` (ADR 0002,
`docs/buildroot-config.md` §8.5) — diff against that file to see exactly what
changed.

### What was added on top of the stage-1 set, and why

Every stage-1 load-bearing symbol is retained unchanged (see that file for
their individual justifications, and the "inherited" list below for the ones
worth repeating here). Added for the installer:

- **`CONFIG_CP`** — `cp -a` copies `mister-payload/*` into tmpfs, then back
  onto the freshly reformatted exFAT partition (ADR 0020 §2). `-a` is on
  BusyBox `cp`'s base option string unconditionally (`coreutils/cp.c`:
  `"apdR"` is in `FILEUTILS_CP_OPTSTR`, not gated behind
  `FEATURE_CP_LONG_OPTIONS`), so — unlike stage 1's minimalism exercise — no
  extra `FEATURE_CP_*` symbol was needed or added.
- **`CONFIG_DD`** — writes the pinned stock `uboot.img` raw onto the 0xA2
  partition (ADR 0020 §2, last step). Only the base `if=`/`of=`/`bs=`/
  `count=`/`skip=`/`seek=` options are needed for a fixed-size blob written
  to a block device at a fixed offset; `FEATURE_DD_IBS_OBS` (which gates
  `ibs=`/`obs=`/`iflag=`/`oflag=`/`conv=`) is deliberately left off. Turn it
  on if a future `/init` revision wants `conv=fsync|notrunc`.
- **`CONFIG_REBOOT`** — the final handoff to the real, just-installed MiSTer
  (ADR 0020 §2 last step). `CONFIG_HALT` was already on in stage 1 (its
  rescue-shell banner never calls it) but `CONFIG_REBOOT` was not — these are
  independent booleans in the same BusyBox source file.
- **`CONFIG_BLOCKDEV`** — reads the target medium's geometry before
  sfdisk-repartitioning it (ADR 0020 §2: "reads the whole device's sector
  count"). `/sys/block/<dev>/size` is the primary source per the plan;
  `blockdev --getsize64` is the sanity-check/fallback path.
- **`CONFIG_HEXDUMP`** — turns `/dev/urandom` bytes into the random
  locally-administered MAC written to `linux/u-boot.txt` (ADR 0020 §2,
  "generates a random locally-administered MAC"). Picked over `CONFIG_AWK`:
  smaller, and `hexdump -e` is the standard idiom for "N random bytes as hex
  octets," exactly the job here. `/init` uses `hexdump` (not `od`, which is
  left off) for `gen_mac`.
- **`CONFIG_RM`** — deletes the payload's `linux/linux.img.gz` from the
  finished card once `/init` has expanded it to `linux/linux.img` (ADR 0020
  §3, step 5b). This was MISSING until PR #76, while `/init` called `rm -f`
  anyway: the call was a silent command-not-found no-op, so every installed
  card kept the whole ~80 MiB gzip forever. `rm -f` needs only this base
  symbol — `coreutils/rm.c`'s `getopt32` optstring `"fiRrv"` is
  unconditional and not gated behind any `FEATURE_RM_*`, exactly like
  `CONFIG_CP` above. It costs about a kilobyte (`rm.c` is 76 lines) in a
  376 KB binary inside a 13 MB RAM-resident initramfs — ~0.008% of the
  image — to stop wasting 80 MiB on the user's card. `/init` still verifies
  the file is gone afterwards and falls back to truncating it, so a future
  regression here degrades loudly instead of silently. `rm -rf` (the staged
  payload dir, after the commit point — ADR 0020 §8) uses the same base
  symbol: `-r`/`-R` are in that same optstring.
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
  forms are used). BusyBox's own Kconfig help prices the applet at 10 kb, in
  a ~376 KB binary inside a 13 MB RAM-resident initramfs — ~0.08% of the
  image, against a brick window that used to be the whole install. **Note
  `/init` relies on one non-obvious behaviour:** `mv` cannot rename over an
  existing NON-EMPTY directory (`rename(2)` gives `ENOTEMPTY` and `mv` only
  falls back to copy+delete for `EXDEV`), so it descends the one directory
  that collides — `linux/` — and moves its children individually.
- **`CONFIG_DU` + `CONFIG_CUT`** — the RAM-budget check (ADR 0020 §2,
  "measure free RAM first ... copy the base and SKIP cores rather than
  OOM-bricking"). `/init` runs `du -sk "$SRC_PAYLOAD" | cut -f1` to size the
  full payload and the `_Console` cores subtree, then decides whether both
  fit the tmpfs budget. There is no clean POSIX-sh substitute for a
  recursive directory size here: `find`/`stat`/`wc` are all off too, so `du`
  is the applet built for the job and `cut` extracts its size field.
  (`basename`/`dirname` are handled with `${var%/*}`/`${var##*/}` parameter
  expansion in `/init` and are NOT built.)
- **`CONFIG_GUNZIP` + `CONFIG_ZCAT`** — the payload's `linux/linux.img.gz`
  decompress (ADR 0020 §3). `linux.img` is a 512 MiB apparent-size ext4
  image; on the shipped FAT32 partition that would be 512 MiB non-sparse,
  far larger than the `mem=511M` installer's whole RAM. So `mk-sdcard.sh`
  ships it gzipped (~80 MiB of real data) and `/init` streams
  `zcat linux/linux.img.gz > linux/linux.img` straight onto the
  freshly-formatted exFAT card AFTER copy-back — the full 512 MiB is
  materialised on disk, never in the RAM tmpfs. `zcat` is what `/init`
  calls; `gunzip` is its sibling applet (both share the one inflate core, a
  few KB) and is enabled for completeness. The kernel already carries its
  own, separate `CONFIG_RD_GZIP` (`external.mk`) — unrelated to these
  userspace applets.
- **`CONFIG_TIMEOUT`** — brackets every `itsalive` call in `/init`'s HDMI
  splash (ADR 0020 §9, issue #185, 2026-09-21). The splash's hard rule is
  that it can never fail — or hang — an install, and a tool that talks to
  the fabric over a mailbox and to the ADV7513 over I²C has more ways to
  wedge than a `printf`. `itsalive` bounds its own mailbox wait (exit 11),
  but nothing bounds a driver that never returns from an ioctl; `timeout N`
  is the belt, and `/init` routes every invocation through one wrapper that
  applies it. Only the base applet is needed — `timeout SECS PROG ARGS`,
  SIGTERM on expiry, exit status passed through otherwise — and its size is
  in the same class as `rm` (`coreutils/timeout.c` is ~100 lines).

### Overlap with util-linux

`configs/mister_installer_defconfig` also enables
`BR2_PACKAGE_UTIL_LINUX_BINARIES` for `sfdisk`, which as a side effect
installs its own `blkid`/`blockdev`/`dmesg`/`findfs`/`hexdump` binaries
alongside the BusyBox applets above. That is intentional, not a bug to
"clean up" — both sets are real, separate binaries; the installer's `/init`
is free to invoke whichever one and the redundancy costs a few KB, not
correctness. `sfdisk` itself has no BusyBox equivalent, which is why
util-linux is unavoidable here at all. The REST of that basic set (~50
programs `/init` never runs, ~10 MB) is what `installer-post-build.sh`
deletes (above); its `UTIL_LINUX_KEEP` names the survivors.

### Symbols inherited from stage 1 — load-bearing; do not drop without re-reading ADR 0002

- `CONFIG_STATIC` — no libc in the cpio (also forced by `BR2_STATIC_LIBS`).
- `CONFIG_LFS` — `allnoconfig` turns this OFF and the build then FAILS with
  "size of array 'BUG_off_t_size_is_misdetected' is negative" (`libbb.h:335`):
  Buildroot compiles BusyBox with `-D_FILE_OFFSET_BITS=64`, so `off_t` is
  64-bit, but `!CONFIG_LFS` makes BusyBox's `uoff_t` a 32-bit
  `unsigned long`. It is also simply correct: a MiSTer data partition is
  routinely >2 GB (the reference card is 238.7 GB) and `losetup`/`dd`/
  `sfdisk` have to do 64-bit arithmetic over it.
- `CONFIG_TAIL` — the rescue banner pipes `dmesg` into it; `ash` has no
  builtin.
- **`CONFIG_FEATURE_MOUNT_FLAGS` — the one that silently bricks you.**
  Without it BusyBox's `mount` does not know `sync`, `dirsync`, `noatime`,
  `nodiratime`, `move` or `bind` (`util-linux/mount.c:2320`
  `mount_options[]` is wrapped in `IF_FEATURE_MOUNT_FLAGS`). It would pass
  them through to the filesystem as *data*, and vfat/exfat use the new mount
  API, which rejects unknown parameters with `EINVAL`. Result: the data
  partition does not mount and the reformat cannot proceed. Applies here
  exactly as it does in stage 1.
- `CONFIG_LOSETUP` — reserved for parity with stage 1 / possible rescue use;
  the installer's own mounts are of real block devices.
- `CONFIG_SWITCH_ROOT` — NOT used by this `/init` (it reboots, it never
  switch_roots) but left enabled for rescue-shell parity with stage 1 and
  because it is nearly free.
- `CONFIG_CTTYHACK` + `CONFIG_SETSID` — give the rescue shell a controlling
  tty.
- `CONFIG_FINDFS` + `CONFIG_VOLUMEID` (+`EXT`, `FAT`, `EXFAT`) —
  belt-and-suspenders re-run guard (ADR 0020 §2.1): detect an
  already-installed card.
- `CONFIG_DMESG`/`LS`/`CAT` — the rescue banner's diagnostics.
- `CONFIG_ASH_TEST` — `ash`'s `[` builtin. See the kconfig trap below.
- `CONFIG_FEATURE_SH_MATH` — `$((arith))`. See the kconfig trap below.

### kconfig silently discards symbols it does not recognise

A wrong `CONFIG_` name does not warn, does not fail the build, and leaves no
trace in the cpio — it just quietly produces a BusyBox that cannot run
`/init`. Two of these shipped in stage 1's config and were caught ONLY by
booting the result under QEMU — the same trap applies here:

- `CONFIG_ASH_BUILTIN_TEST` / `_ECHO` / `_PRINTF` are the PRE-1.22
  spellings. 1.37 (and 1.38, pinned here) calls them `CONFIG_ASH_TEST` /
  `ASH_ECHO` / `ASH_PRINTF`. Under the old names `ash` has no `[` builtin,
  and `/init` dies on its very first test with
  `"/init: line 98: [: not found"` — while still printing a rescue banner
  that misleadingly blamed the kernel command line.
- It is `CONFIG_FEATURE_SH_MATH`, not `CONFIG_SH_MATH`. Without it `ash`
  will not even PARSE `/init`: `"syntax error: support for $((arith)) is
  disabled"` → pid 1 exits → instant kernel panic.

Re-verify every applet this file's `/init` calls is really in the cpio
(mirror stage 1's `make initramfs` artifact check / P1.12's QEMU harness)
after any BusyBox bump. Do not assume symbol names survived.

### How this file was generated, and how to regenerate it after a BusyBox bump

Hand-derived from `board/mister/common/initramfs-busybox.config`; NOT
regenerated verbatim by `make busybox-update-config` — do that, then
re-apply every addition listed above.

1. `make allnoconfig` in a pristine BusyBox tree at the version Buildroot
   pins (1.38.0 today) → 8 symbols on.
2. Force-enable exactly the symbols stage 1's `/init` needs, PLUS every
   addition listed above.
3. `make olddefconfig` (pulls in their mandatory sub-symbols).
4. Set `CONFIG_FEATURE_EDITING_MAX_LEN=1024` (`allnoconfig` leaves it 0,
   which makes the rescue shell's line editor useless), and `olddefconfig`
   again.

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
