# ADR 0019 — Symlinks on exFAT via a carried mainline patch (amends ADR 0010)

**Status:** Accepted (2026-07-14) — decided by @mcfbytes
**Amends:** ADR 0010 (which stands otherwise — see §4)
**Impact:** `board/mister/de10nano/linux-patches/0031-exfat-samsung-symlinks.patch`

## 1. What ADR 0010 missed

ADR 0010 dropped Samsung's out-of-tree exfat driver on the finding that its
one distinguishing feature — symlinks on FAT/exFAT — "appears unused",
based on `find -type l` over every mounted volume of one live stock MiSTer
(n=1, and the ADR itself flagged that as insufficient for any public
release).

The finding was wrong in exactly the way the ADR warned it might be:
**MiSTer's arcade organizer builds its entire output tree out of symlinks.**
The `_arcade-organizer` script (distributed through the standard downloader
DBs) creates `_Arcade/_Organized/…` as thousands of symlinks pointing at the
real `.mra` files, on the exFAT data partition. On mainline exfat those
links degrade into regular files containing a path string (ADR 0010
§Consequence (d)); the organizer and every organized menu entry break.

### 1.1 Worse: the evidence method was mechanically blind

The `find … -type l` scan itself had a false-negative flaw, so "0 symlinks"
never meant what it appeared to mean:

* Stock ships **GNU findutils** at `usr/bin/find`
  (`docs/stock-inventory/binaries-needed-full.txt:103` — a real ELF, not a
  BusyBox link), which is what an interactive `find` resolves to.
* GNU find's `-type l` trusts the `d_type` that `readdir()` reports and
  only falls back to `lstat()` on `DT_UNKNOWN`.
* The Samsung driver's readdir reports **`DT_REG` for symlinks**
  (`work/Linux-Kernel_MiSTer/fs/exfat/exfat_super.c:424-425` —
  `(de.Attr & ATTR_SUBDIR) ? DT_DIR : DT_REG`; there is no `DT_LNK` case).

So on a stock kernel, GNU `find -type l` reports **zero symlinks on a card
full of them** — it never lstat()s anything the driver confidently labels a
regular file. (`busybox find` lstats every entry and is immune; `ls -l` and
the organizer itself use lstat and were never fooled.) Whether the n=1 card
actually had an organized tree is therefore unknowable from the recorded
evidence. Patch 0031's readdir emits `DT_LNK`, so the same one-liner is
reliable on the new kernel — but see §5.1 for what to tell users still on
stock.

## 2. Decision

Keep mainline exfat (everything in ADR 0010 §Rationale about not carrying a
20-file parallel filesystem still holds). Add **one carried kernel patch**
— `0031-exfat-samsung-symlinks.patch` — that teaches mainline exfat the
Samsung driver's on-disk symlink format. This is option (c) from
`docs/patch-provenance.md` §N1, which §3.8 left as "decision required".

The on-disk format (verified against the Samsung driver source,
`work/Linux-Kernel_MiSTer/fs/exfat/`):

* A symlink is an ordinary exFAT file dentry set whose attribute word
  carries the DOS "system" bit **0x0004** (`ATTR_SYMLINK` in Samsung's
  naming), alongside `ATTR_ARCHIVE`.
* The file's data is the target path, **not** NUL-terminated
  (`i_size == strlen(target)`).
* **0x0040** (`ATTR_SYMLINK_OLD`) is a legacy marker from older Samsung
  releases: honoured on read, upgraded to 0x0004 on the next attribute
  writeback, never written on create.

Cards written by the stock 5.15 kernel and by this kernel are
interchangeable in both directions.

## 3. Why this is cheap where the Samsung driver was expensive

The patch is ~165 lines across 6 files in `fs/exfat/`, and the mechanism
reuses vanilla VFS infrastructure rather than reimplementing it:
creation is `exfat_add_entry()` + `page_symlink()`, readback is
`page_get_link()` (whose `nd_terminate_link()` tolerates the on-disk
string having no NUL). All touched functions are stable, low-churn code;
the patch carries the same provenance header discipline as 0001–0030, and
its header documents the four sharp edges a multi-angle review surfaced
(in-core type normalization so eviction can free the target cluster, the
SET_ATTRIBUTES ioctl pinned against S_IFMT flips, readdir/lstat sharing
one linkness classifier, one shared attr predicate).

## 4. What still stands from ADR 0010

Consequences (a)–(c) are untouched: the initramfs still tries `exfat` then
falls back to `vfat` with `utf8=1`, and still owns the `/media/fat`
bind-mount. Consequence (d)'s release-note warning is **narrowed, not
retired**: it no longer applies to exFAT cards, but still applies to
FAT32-formatted cards (see concession 1).

## 5. Concessions — read before relying on this

1. **exFAT only.** The Samsung driver also mounted FAT12/16/32 and gave
   them the same symlinks; mainline vfat has no symlink support and this
   patch does not add any. A FAT32-formatted card with an organized arcade
   tree still loses its symlinks. FAT32 MiSTer cards are rare (the SD-card
   images ship exFAT) but they exist; the detection one-liner is the
   mitigation — but per §1.1 it **must force lstat when run on a stock
   kernel**, because GNU find trusts the d_type the Samsung driver lies
   about. The corrected release-note one-liner is:
   `busybox find /media/fat /media/usb* -type l`
   (BusyBox lstats every entry; plain `find` on stock silently reports
   nothing).
2. **The "system" attribute is overloaded.** Any non-directory entry with
   attribute 0x0004 or 0x0040 presents as a symlink — including genuine
   Windows system files (e.g. `IndexerVolumeGuid` inside `System Volume
   Information`). Those become unreadable *as files* from Linux. This is
   bit-for-bit the behaviour every stock MiSTer kernel has had since 2021;
   matching it is the point. Nothing on a MiSTer accesses those files.
3. **A carried filesystem patch is reopened maintenance.** This is a
   partial walk-back of ADR 0010's "no unbudgeted fs maintenance" rationale
   — bounded, because it is ~165 lines against stable mainline code instead
   of a parallel driver, but real: every kernel bump must re-verify patch
   0031 applies and `fs/exfat` still behaves. That obligation is enforced
   by a runnable test, not a PR recipe: `scripts/test-initramfs.sh symlink`
   applies patch 0031 to the QEMU test kernel and asserts the full
   round-trip (hot + cold readback, `DT_LNK`, unlink, and the
   create+unlink cluster-leak regression that `fsck.exfat` provably does
   not catch), using `scripts/test-initramfs/test-symlink.c` in the guest.
4. **Not upstreamable.** Upstream exfat would reasonably reject overloading
   an attribute bit that Windows assigns to ordinary files. Do not plan on
   this patch ever disappearing into mainline.

## 6. Verification (2026-07-14, QEMU `-M virt`, patched 6.18.38)

* **Round-trip, 20/20 assertions** — static ARM test binary
  (`scripts/test-initramfs/test-symlink.c`) exercising the syscalls the
  organizer uses: `symlink()` (relative, absolute, dangling, EEXIST),
  `readlink()`, `lstat()` → `S_ISLNK`, open-through-link, `getdents64` →
  `DT_LNK`, `unlink()` (link dies, target survives) — all both hot-cache
  and after a full umount/remount (cold readback from disk). Now runnable
  as `scripts/test-initramfs.sh symlink`.
* **Cluster-leak regression caught and fixed** — the first cut leaked the
  target's cluster on same-mount create+delete (`__exfat_truncate()`
  type guard); reproduced empirically as an orphaned allocation-bitmap
  bit, which `fsck.exfat` 1.3.2 does **not** report (verified directly).
  Fixed by keeping `ei->type == TYPE_FILE`; the harness now trips on this
  via a `statvfs` free-space round-trip.
* **On-disk bytes are Samsung-exact** — image parsed offline: attr word
  `0x0024` (ARCHIVE|SYSTEM), stream `size == valid_size == strlen(target)`,
  payload contains no NUL, entry-set checksums valid, allocation bitmap
  audit exact (allocated == referenced, no orphans).
* **Stock-card direction proven independently** — a symlink the patched
  driver never wrote (regular file created in-guest, attribute bit and
  entry-set checksum patched in by hand offline, i.e. exactly what a
  Samsung-written card contains) lstats as a symlink, readlinks and
  follows correctly: 3/3.
* **`fsck.exfat -n` clean** after every driver-write phase.
* Patch applies cleanly after 0001–0030 (`fs/exfat` is untouched by them;
  sha256-identical to pristine), and the patched kernel builds with zero
  warnings in `fs/exfat`.
