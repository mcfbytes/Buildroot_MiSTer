# Stock image inventory — generator scripts (P0.3)

This directory scripts the entire `docs/stock-inventory/` tree so it can be
regenerated from any rootfs image (the stock 2021.02.4-based `linux.img`
today, a Buildroot-built one in P2/P3 tomorrow) and diffed for parity.
**The scripts are the deliverable; the docs in `docs/stock-inventory/` are
their checked-in output.**

## Quick start

```sh
scripts/inventory/run-all.sh <linux.img-or-extracted-root> [zImage_dtb] [MiSTer-binary]
```

Example, against the pre-seeded stock materials from P0.2:

```sh
scripts/inventory/run-all.sh \
  work/extracted/files/linux/linux.img \
  work/extracted/files/linux/zImage_dtb \
  work/extracted/files/MiSTer
```

This regenerates every file under `docs/stock-inventory/` except
`stock-linux.config`/`stock.dts` themselves, which item (f)'s script
deliberately does **not** overwrite by default (see below) — it only
verifies that regenerating them from the given `zImage_dtb` reproduces the
committed copies, and writes its verification result to
`kernel-config-dts.md`.

**Nothing here requires root.** `debugfs rdump` (used to read an ext4 image
without mounting it) runs unprivileged; the "Operation not permitted while
changing ownership" lines it prints are benign (see `common.sh`) and do not
indicate a failed extraction.

## Requirements

`python3`, `readelf` (GNU binutils — reads ARM ELF on any host arch, not
just the target's), `debugfs` (e2fsprogs, only needed when the argument is
a raw image file rather than an already-extracted directory), `dtc`,
`qemu-arm`. All were confirmed present in this environment; `shellcheck` is
required only to re-lint the scripts themselves, not to run them.

## What each script does and what it writes

| Item | Script | Argument(s) | Writes |
|---|---|---|---|
| (a) shared libraries | `gen-shared-libs.sh` | rootfs image/dir | `shared-libraries.md`, `shared-libraries-full.txt` |
| (b) binaries + NEEDED | `gen-binaries.sh` | rootfs image/dir, `[extra ELF...]` | `binaries-needed.md`, `binaries-needed-full.txt`, `binaries-needed-union.txt` |
| (c) /etc configs | `gen-etc-configs.sh` | rootfs image/dir | `etc-configs.md`, `etc-init-scripts-full.txt` |
| (d) firmware | `gen-firmware.sh` | rootfs image/dir | `firmware.md` |
| (e) BusyBox applets | `gen-busybox.sh` | rootfs image/dir | `busybox-applets.md` |
| (f) kernel config + DTS | `gen-kernel-config-dts.sh` | `zImage_dtb` file, `[output-dir]` | `kernel-config-dts.md` (+ regenerated files in `output-dir`, default a scratch temp dir) |
| (g) disk usage | `gen-disk-usage.sh` | rootfs image/dir | `disk-usage.md` |
| (h) kernel modules | `gen-modules.sh` | rootfs image/dir | `modules.md` |

Every `rootfs image/dir` argument accepts either:
- a raw **ext4 image file** (e.g. `work/extracted/files/linux/linux.img`)
  — extracted internally and unprivileged via `debugfs -R "rdump / <tmp>"`
  into a temp directory that's cleaned up on exit, or
- an **already-extracted directory** (e.g. `work/imgroot`) — used as-is,
  no copy, for fast repeated runs during development.

`gen-binaries.sh`'s extra-ELF arguments and `gen-kernel-config-dts.sh`'s
`zImage_dtb` are how the stock `MiSTer` binary and kernel image (which ship
outside `linux.img`, in the release archive) get folded into the analysis.

### Shared implementation

- `common.sh` — sourced by every `gen-*.sh`: image/dir resolution
  (`mrl_extract_root`), a markdown doc header helper (`mrl_header`), tool
  presence checks (`mrl_require`), and the repo-root-relative output
  directory resolver (`mrl_out_dir`).
- `elf_scan.py` — walks a rootfs once and classifies every ELF regular file
  (binary / library / dlopen plugin / other) via `readelf -h`/`-d`; used by
  both (a) and (b) so the classification logic (and its evidence method)
  lives in exactly one place.
- `lz4_legacy.py` + `kernel_extract.py` — pure-Python decompressor for the
  Linux kernel's "legacy" LZ4 frame format and the IKCONFIG/DTB-carving
  logic for item (f). Written from scratch because this environment has no
  `lz4` CLI or Python `lz4` module (only the runtime shared library) —
  see `lz4_legacy.py`'s docstring for the exact format and why.
- `normalize-dts.py` — narrow, documented whitespace/hex-literal
  normalization used only to tell a real DTS content change apart from
  dtc-version-dependent cosmetic rendering differences (see
  `kernel-config-dts.md` for why this matters for the stock DTS).
- `build_*.py` — one per doc, doing the actual data processing; each
  `gen-*.sh` is a thin wrapper (argument handling, tool checks, doc header,
  writing the file to `docs/stock-inventory/`).

## Determinism

Every generator sorts its output (`LC_ALL=C`), never embeds a timestamp,
and never embeds a host-specific absolute path (e.g. the temp directory an
image was extracted into) — these files are meant to be diffed across
images (stock vs. a Buildroot build in P2/P3), so nondeterminism between
two runs against the *same* image would defeat the entire point. If you add
a new generator, keep this property: run it twice against the same input
and `diff` the output — it must be empty.

## Re-linting

```sh
shellcheck scripts/inventory/*.sh
```

Should report nothing. A few narrow, documented `shellcheck disable`
directives exist at the top of each `gen-*.sh` (markdown backticks in
`printf` format strings look like unexpanded shell variables to shellcheck;
`common.sh` is sourced via a runtime-computed path it can't follow
statically; `MRL_SCRIPT_NAME` is read by `common.sh`'s `mrl_header`, not the
file that sets it) — each has a comment explaining why it's safe.
