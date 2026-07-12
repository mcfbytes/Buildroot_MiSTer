# ADR 0003 — Defer the multi-db race; test by direct SD copy (answers Q3)

**Status:** Accepted (2026-07-12) — decided by @mcfbytes
**Supersedes:** `docs/phase0-review.md` Q3; PLAN.md ledger #4
**Impact:** P4.5 (db.json publishing), P4.8 (user docs) — deferred to Phase 4

## Decision

Do not solve the Downloader multi-database ordering race now. Engage the
Downloader maintainers when we actually publish (Phase 4). Until then, test by
copying the built artifacts onto the SD card by hand and rebooting; roll back by
restoring the previous files from a PC.

## Why the test method is sound

The boot chain supports exactly this, and the recon evidence confirms it:

- The rootfs **is a file on the data partition** — `root=/dev/mmcblk0p1
  loop=linux/linux.img` (`docs/boot-chain.md:315`). Confirmed live: `/dev/loop8 on /`.
- U-Boot proper lives in the **raw `0xA2` partition** (`/dev/mmcblk0p2`, 3 MiB —
  verified live), which the SPL finds *by partition type*, not by filesystem
  (`docs/boot-chain.md:118-132`). Copying files onto p1 cannot touch it.

So swapping `linux/linux.img` + `linux/zImage_dtb` on p1 and rebooting is a
faithful test, and restoring the two previous files is a real rollback.

## Consequences — two hazards that are NOT covered by "just copy the files back"

### (a) `updateboot` can brick the boot partition, and file-restore will not undo it

`/media/fat/linux/updateboot` (`docs/boot-chain.md:370-408`) does:

```sh
if [ -f /media/fat/linux/uboot.img ]; then
        dd if=/media/fat/linux/uboot.img of=/dev/mmcblk0p2
```

It `dd`s straight over the raw `0xA2` partition. That is the **one** path that can
leave the board unbootable in a way that restoring files on p1 does not fix.

Note the trap documented at `boot-chain.md:400`: simply *not shipping* a
`uboot.img` does **not** disable this — Downloader `rsync`s our `files/linux/`
over `/media/fat/linux/` **without `--delete`**, so a stale `uboot.img` survives
and gets re-flashed. For hand-copy testing, do not invoke `updateboot`.

### (b) Get a serial console before Phase 1 kernel bring-up

The bootargs already specify `console=ttyS0,115200`. A kernel that dies before
framebuffer init produces a **black screen and nothing else** — no way to tell
"DTB wrong" from "rootfs not found" from "panic in init." Wiring up UART is the
single highest-leverage hour of prep for Phase 1, and it converts most P1 failures
from guesswork into a log.

### (c) Recommended, not required

`dd` a full byte-for-byte backup of the working card, and do P1 bring-up on a
*second* SD card. Cards are cheap; the known-good card should never be the one
under test.

## The race itself, restated for Phase 4

Only one database's `linux` entry is ever processed, and the winner is whichever
`db.json` fetches and parses first. Ours wins **only** because it is tiny next to
Distribution's multi-MB catalog. This is emergent, not guaranteed — keeping our
`db.json` minimal (empty `files`/`folders`) is therefore a **load-bearing design
rule, not an aesthetic preference**, until an explicit precedence rule exists
upstream.
