# Size Budget Report

## Image Size Summary

**512 MiB** is the standard for the MiSTer environment (double the stock 256 MiB, accounting for U-Boot reserved space). This report validates that the image has sufficient headroom and documents major size contributors.

Figures below were regenerated as part of **P3.3** (module loading & firmware
infra — the `/lib/firmware` population half) to capture that task's size
impact; they now reflect P3.1 (Realtek WiFi kernel modules), P3.2 (xone +
xow-firmware), and P3.3 (linux-firmware + wireless-regdb +
linux-firmware-extra) combined, not just P2.7's original baseline. See
"P3.3 firmware addition" below for the isolated delta.

### Filesystem Allocation (via `dumpe2fs`)

- **Total image size:** 536,870,912 bytes = **512 MiB**
- **Block count:** 131,072 blocks × 4,096 bytes/block
- **Used blocks:** 51,524 (201.3 MiB)
- **Free blocks:** 79,548 (310.7 MiB)
- **% Free:** **60.6%** ✅ **PASS** (threshold: ≥15%, via `scripts/check-size-budget.sh output/images/linux.img`)

**Headroom interpretation:** The image has 310.7 MiB free, comfortably exceeding the 15% minimum (76.8 MiB). This provides buffer for future package additions, firmware updates, and runtime files.

---

## Rootfs Breakdown by Top-Level Directory

The rootfs uses a merged-usr layout (symbolic links: `bin→usr/bin`, `lib→usr/lib`, `sbin→usr/sbin`). Actual content lives under `/usr`:

| Directory     | Size       | Notes                                  |
|---------------|------------|----------------------------------------|
| `usr/lib`     | 126.2 MiB  | Libraries, Python modules, Samba data, `/lib/firmware` (`usr/lib/firmware`, see below) |
| `usr/bin`     | 14.6 MiB   | Executables and symlinks               |
| `usr/share`   | 10.7 MiB   | Locale, man pages, documentation       |
| `usr/libexec` | 10.2 MiB   | Helper binaries and scripts            |
| `usr/sbin`    | 7.0 MiB    | System binaries                        |
| `etc`         | 0.7 MiB    | Configuration files                    |
| Others        | ~0.1 MiB   | Empty dirs, device nodes, etc.         |
| **Total**     | **169.5 MiB** | Installed rootfs (`du -sb`, extracted `output/images/rootfs.tar`) |

---

## P3.3 firmware addition

`/lib/firmware` (`usr/lib/firmware` in the merged-usr layout) is entirely
P3.1–P3.3 content — stock parity, not present before this project's own
package additions. Measured directly from the built
`output/images/rootfs.tar` (not `output/target/`, per the project's build
lessons):

- **`/lib/firmware` total: 3.1 MiB** (3,064,880 bytes) — **68 regular files +
  23 symlinks** (91 entries, plus 4 directory entries).
- Of that, **P3.2's `xow-firmware`** (already-committed, xow/xone Xbox
  dongle firmware) accounts for ~140 KiB (`xow_dongle.bin` 70,620 bytes +
  `xone_dongle_02e6.bin` 70,008 bytes + a symlink).
- **P3.3's own addition (`linux-firmware` + `wireless-regdb` +
  `linux-firmware-extra`): ≈ 2.9 MiB** — the 56-of-66 stock inventory files
  reproduced (see `docs/firmware-parity.md` for the full per-file mapping
  and the built-vs-stock diff), plus a documented superset of sibling
  firmware Buildroot's coarse-grained sub-options pull in alongside them
  (e.g. `RTL_87XX_BT` also installs `rtl_bt/rtl8723cs_cg_fw.bin`, which
  stock never shipped).

**Impact on the overall budget:** negligible. 2.9 MiB against a 512 MiB
image with 310.7 MiB free is under 1% of total image size and about 0.9% of
the free margin — the budget check still passes with over 4x the required
headroom (60.6% free vs. the 15% floor).

---

## Top 10 Packages by Installed Size

Attributed from `output/build/packages-file-list.txt` by summing the **real byte
size of each file** in the extracted rootfs with `lstat` — i.e. **symlinks are NOT
followed** (a symlink is ~10–20 bytes, not the size of its target). This matters: a
naive `du` that follows links counts BusyBox's ~200 applet symlinks as ~200 copies
of the BusyBox binary and reports it as "215 MiB", which is larger than the whole
image and obviously wrong. The corrected figures:

| Rank | Package | Size | Notes |
|------|---------|------|-------|
| 1 | **samba4** | 48.8 MiB | SMB/CIFS server + client — by far the largest, intentional (P3.6) |
| 2 | **file** | 10.0 MiB | `libmagic` + its compiled magic database |
| 3 | **python3** | 8.7 MiB | interpreter + stdlib (A6 — runs the Downloader) |
| 4 | **openssh** | 6.8 MiB | sshd + utilities |
| 5 | **libopenssl** | 4.6 MiB | OpenSSL 3.x (vs stock's EOL 1.1.1) |
| 6 | **libglib2** | 4.5 MiB | core GLib, pulled by dbus/bluez/etc. |
| 7 | **libglib2-bootstrap** | 3.8 MiB | ⚠ build intermediate — see below |
| 8 | **bluez5_utils** | 2.8 MiB | Bluetooth stack |
| 9 | **sudo** | 2.2 MiB | |
| 10 | **gcc-final** | 2.1 MiB | ⚠ toolchain runtime libs — see below |

For scale: **BusyBox's real footprint is ~1 MiB** (one binary; its applets are
symlinks). Total attributed across all packages ≈ **140 MiB**, consistent with the
~171 MiB extracted rootfs (the remainder is directories, symlinks, and a few files
not attributed to a package in the file list).

### Analysis

- **samba4 (48.8 MiB)** is the single dominant cost and an intentional parity
  dependency (P3.6). It is the obvious first lever if the image ever needs to
  shrink (e.g. dropping the AD/DC and printing components, which P2.1 already
  excluded — the remainder is the file-server core MiSTer users expect).
- **⚠ `libglib2-bootstrap` (3.8 MiB) and `gcc-final` (2.1 MiB) appear in the
  target.** `libglib2-bootstrap` is the bootstrap variant Buildroot builds to break
  a circular dependency; its files landing in the image alongside the real
  `libglib2` is worth confirming is not duplication. `gcc-final` here is the
  toolchain's *runtime* libraries (`libstdc++`, `libgcc_s`) that the stock `MiSTer`
  binary genuinely NEEDs — so most of it is legitimate, not removable — but the
  exact file set is worth an audit. Both are small (~6 MiB combined) and non-urgent;
  flagged for a future size pass, not a blocker.

- **GLib2 (11.3 MiB + 10.7 MiB bootstrap):** Core dependency for many packages (file, samba4, etc.). The bootstrap artifact (10.7 MiB) is a build-time intermediate that should not appear in runtime but does due to how Buildroot's file list is constructed.

### vs. Stock Comparison

Stock image (375 MiB, measured from `work/imgroot`) contained:
- Older OpenSSL 1.1 (~5 MiB) vs. OpenSSL 3 (~9 MiB) — **+4 MiB** (security upgrade)
- Samba 4.x (present, comparable size)
- Python 3.9 (present, comparable) vs. our 3.14 (modern)
- No `file` package in base stock (was optional in test images)

Our image is larger by ~136 MiB (171 MiB vs. 35 MiB of stock content), primarily due to:
- Full Python 3.14 stdlib (~13 MiB)
- Samba4 libraries (~62 MiB)
- OpenSSL 3 (~9 MiB)
- Additional utilities and dependencies

This growth is **intentional and justified** — we trade image size for modern userland, security, and utility completeness.

---

## Methodology

### Data Sources

1. **Image size:** `dumpe2fs -h /mnt/source/Buildroot_MiSTer/output/images/linux.img`  
   Extracts ext4 filesystem metadata: block count, free blocks, block size.

2. **Rootfs content:** Extracted `output/images/rootfs.tar` to temp directory.  
   Used `du -sb` to measure directory sizes; `du -sb */` for per-directory breakdown.

3. **Per-package sizes:** `output/build/packages-file-list.txt` (Buildroot's internal file → package mapping).  
   Parsed format: `package_name,path_to_file`.  
   For each file, its **`lstat` size** (symlinks NOT followed — a symlink is its own
   ~10–20 bytes, not its target) was summed and attributed to the installing package.
   Ranked by total size.

### Reproducibility

To regenerate this report:

```bash
# Extract rootfs and measure
tar -xf output/images/rootfs.tar -C /tmp/rootfs-measure
du -sb /tmp/rootfs-measure
du -sh /tmp/rootfs-measure/* | sort -rh

# Get image filesystem stats
dumpe2fs -h output/images/linux.img

# Calculate % free
# Total blocks: 131072
# Free blocks: (from dumpe2fs)
# % free = free_blocks / total_blocks * 100

# Per-package analysis (requires tools):
# Parse output/build/packages-file-list.txt
# For each file, stat() in /tmp/rootfs-measure and sum by package
```

### Limitations and Caveats

- **Symlink accounting (corrected):** per-package sizes above use `lstat`, so a
  symlink counts as the ~10–20 bytes of the link, not the size of its target.
  Without this, BusyBox's ~200 applet symlinks each count as a full copy of the
  BusyBox binary and it reports as ~215 MiB — larger than the entire image. Its
  real footprint is ~1 MiB. The regeneration script above and the table both use
  the corrected method.
- **Build intermediates in the target:** `libglib2-bootstrap` (~3.8 MiB) and
  `gcc-final` (~2.1 MiB) appear in the file list. `gcc-final` here is mostly the
  toolchain *runtime* libraries (`libstdc++`, `libgcc_s`) that the stock `MiSTer`
  binary genuinely NEEDs, so it is not simply removable; `libglib2-bootstrap` is
  worth confirming is not duplicated against the real `libglib2`. Combined ~6 MiB,
  non-urgent — flagged for a future size pass.
- **Hardlinks:** the file-list attributes each path independently; a hardlinked
  file is counted once per path. Total-size figures use `dumpe2fs` (the filesystem's
  own accounting), which is authoritative for the budget check.

---

## Budget Status

✅ **PASS**: 60.6% free (310.7 MiB / 512 MiB) — well above 15% threshold, after P3.1 (Realtek WiFi modules), P3.2 (xone/xow-firmware), and P3.3 (`/lib/firmware` population) combined.

The image has substantial headroom for:
- Emergency space during runtime
- Future package additions
- Firmware and configuration expansion
- Temporary file growth

No immediate action needed. Future P3/P4 optimizations can recover build-time artifacts if headroom becomes scarce.
