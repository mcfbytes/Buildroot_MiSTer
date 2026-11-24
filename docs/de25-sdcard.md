# DE25-Nano SD card — layout, build, write, first boot

**Status:** D2.4's card half. The two-partition developer card (p1 FAT32, p2 ext4) booted on a
tester's board 10/10 on 2026-11-24 (issue #318). **The layout below replaced it on 2026-11-24 and
has not been on hardware yet:** the hidden p1 type, stage 1 and the DE25 installer are verified in
QEMU and statically only (§9).

Files this document describes:

| File | What it is |
|---|---|
| `board/mister/de25nano/genimage-sdcard.cfg` | the layout, as genimage input |
| `board/mister/de25nano/post-image.sh` | `BR2_ROOTFS_POST_IMAGE_SCRIPT`: generates `extlinux.conf`, stages the payload, runs genimage, runs the checker |
| `board/mister/de25nano/initramfs-overlay/usr/libexec/mister-installer/install` | the DE25 first-boot installer (§3) |
| `scripts/check-sdcard-de25.sh` | fail-closed static verification of the produced image |

Cross-refs: [`de25-boot-chain.md`](de25-boot-chain.md) §2/§3/§7/§8.3,
[`de25-implementation-path.md`](de25-implementation-path.md) §6/§6.3/§8 Q7,
[ADR 0029](decisions/0029-de25-implementation-path.md) D3/D4,
[`de25-nano-tasks.md`](de25-nano-tasks.md) "Testing on a borrowed board".

---

## 1. Layout

The DE10's two-stage card ([ADR 0029](decisions/0029-de25-implementation-path.md) D11): the
user-visible partition is exFAT, Linux is `linux/linux.img` on it, loop-mounted by the stage-1
initramfs, and `/media/fat` is that partition, so ROMs and settings are copied to the card from
a PC exactly as on a DE10. The one difference is forced by the boot firmware: the factory SPL
reads `u-boot.itb` from FAT on **partition 1**, so the boot partition comes first and the data
partition is p2, where the DE10 has data on p1 and its raw `0xA2` boot partition on p2.

`output-de25/images/sdcard-de25.img`, MBR, ~529 MiB, as shipped:

| # | Device | Type | Size | Filesystem | Contents |
|---|---|---|---|---|---|
| — | — | MBR at LBA 0 | 1 MiB gap | — | the gap also holds entry 3 |
| 3 | `/dev/mmcblk0p3` | `0xda` | 512 KiB at LBA 1024 | — | the installer flag ([`installer-init.md#the-flag`](installer-init.md#the-flag)); deleted by the first boot |
| 1 | `/dev/mmcblk0p1` | **`0x1c` (hidden FAT32 LBA)**, bootable | 512 MiB | FAT32, label **`DE25BOOT`** | `u-boot.itb`, `Image`, `socfpga_agilex5_de25nano.dtb`, `extlinux/extlinux.conf`, `mister-payload/linux/linux.img.gz` |
| 2 | `/dev/mmcblk0p2` | `0x0c` (FAT32 LBA) | 16 MiB | FAT, label **`MISTERSETUP`** | `README.txt` |

and after the first boot (§3):

| # | Device | Type | Size | Filesystem | Contents |
|---|---|---|---|---|---|
| 1 | `/dev/mmcblk0p1` | `0x1c`, bootable | 512 MiB | unchanged | unchanged |
| 2 | `/dev/mmcblk0p2` | `0x07` | the rest of the card | exFAT, label **`MiSTer_Data`** | `linux/linux.img` (= `rootfs.ext4`), plus the user's pre-seed files; `/media/fat` |

**There is no `0xA2` partition.** The `0xA2` type byte is the *Cyclone V BootROM's* raw-partition
contract ([`boot-chain.md`](boot-chain.md) §2.1) and has no meaning on Agilex 5: here the SDM
boots the FSBL out of QSPI and the FSBL reads a **filesystem** — "No 0xA2 analogue [V]",
[`de25-boot-chain.md`](de25-boot-chain.md) §2. `check-sdcard-de25.sh` fails the image if one
appears, because it is a reliable symptom of DE10 layout lore being transplanted.

**Nothing on this card references QSPI.** Not `extlinux.conf`, not a U-Boot script, not an
`fw_env.config`. A QSPI write on this board is brick-class with JTAG-and-a-PC recovery and no
RSU safety net (§6, §7 rows 1/5/10/11/12 of the boot-chain doc). The checker greps
`extlinux.conf` for `sf probe`, `ubi` and `mtd`; that grep is thin, and it is deliberately the
*only* automated enforcement that exists today — the wider rule is still policy enforced by
prose (boot-chain §5, §9.3).

### Why p1 is hidden, and why that is safe

On the DE10 a PC never sees the boot partition, because Windows does not mount type `0xA2`. p1
gets the same treatment from type **`0x1c`**, the hidden form of FAT32 LBA. Windows assigns drive
letters only to partition types it recognises (`0x01`, `0x04`, `0x06`, `0x07`, `0x0b`, `0x0c`,
`0x0e`), so p1 gets no letter and a user sees one drive, `MiSTer_Data`. Disk Management still
lists it. macOS and Linux desktops mount by probing the filesystem rather than the type byte, so
they may still show `DE25BOOT`. That is harmless, just less tidy.

The boot chain does not care about the type byte:

- U-Boot's MBR parser accepts any non-zero, non-extended type
  (`disk/part_dos.c` `part_get_info_extended()`: `pt->sys_ind != 0 && !is_extended(...)`, in
  v2026.07 and unchanged for many years, so the factory 2025.01 SPL has the same test). The SPL
  then probes FAT on partition 1 by content.
- The kernel's msdos partition parser creates `mmcblk0p1` for any non-extended type.
- distro boot scans only partitions with the **bootable** flag, which only p1 has. So U-Boot
  never searches the user-writable p2 for an `extlinux.conf` or a `boot.scr`. The checker
  asserts the flag.

**Not yet on hardware [U].** If the factory SPL turns out to reject `0x1c` (no evidence that it
would), the board stops at the SPL and the fix is one byte: `partition-type = 0xc` in
`genimage-sdcard.cfg` and `BOOT_PART_TYPE` in the checker.

### Why p1 is what it is

The factory U-Boot SPL — resident in QSPI, **never written by anything we ship** (ADR 0029 D4)
— loads a file called exactly `u-boot.itb` from a FAT filesystem on **partition-table entry 1**,
and places it at `CONFIG_SPL_LOAD_FIT_ADDRESS=0x82000000`
(`CONFIG_SPL_FS_FAT=y`, `SYS_MMCSD_FS_BOOT_PARTITION` default 1;
[`de25-boot-chain.md`](de25-boot-chain.md) §2 step 4, §8.3). Those three facts — FAT, entry 1,
that filename — are the **entire interface** between this card and the board's boot firmware.
Everything else on p1 is read later, by U-Boot proper, and is ours to arrange.

The kernel and DTB stay on p1 rather than moving to `linux/` on the exFAT partition as on the
DE10. That way U-Boot reads only FAT, and a damaged exFAT volume still boots to stage 1, which
can repair it (ADR 0026) or print a rescue banner. mainline U-Boot can read exFAT
(`CONFIG_FS_EXFAT=y` is already on), so moving them later is a boot-script change, not a
U-Boot one.

512 MiB is sized for room, not fit: the kernel is ~42 MiB and the payload's `linux.img.gz` is the
gzipped 512 MiB rootfs. The slack is there because a `core.rbf` and any boot-time fabric
bitstream have to live on this same FAT partition, and growing p1 later means re-writing every
card. **Room is not permission:** p1 is an *allow-list* in the checker, so a file that is not on
it fails the image. A `uboot.env` in particular is deliberately **not** shipped
([`de25-uboot.md`](de25-uboot.md) §10) — a seeded environment file silently overrides the
compiled-in one on every already-written card, so the next release's `bootcmd`/`bootargs` change
would be ignored forever. Adding a file to p1 means editing the genimage `files` list *and* the
checker's allow-list in the same commit.

### `extlinux.conf`

Generated by `post-image.sh` — it is not a checked-in file, and editing it on a card is a
debugging move rather than a fix. Today it says:

```
timeout 10
default de25

label de25
	menu label MiSTer DE25-Nano developer OS
	kernel /Image
	fdt /socfpga_agilex5_de25nano.dtb
	append root=/dev/mmcblk0p2 loop=linux/linux.img ro rootwait console=ttyS0,115200 earlycon mem=479M uio_pdrv_genirq.of_id=generic-uio
```

`root=`, `loop=` and `ro` are the DE10's own (`board/mister/de10nano/uboot.env` `mmcboot`), with
p2 for p1. The shared `/init` reads them from the command line and has no board-specific line.

`mem=479M` keeps Linux below the FPGA-shared LPDDR at `0x9df0_0000` and the `of_id` binds the
`/dev/mister` UIO nodes ([`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7);
`check-sdcard-de25.sh` asserts both.

`console=ttyS0,115200` is HPS **uart1** (`serial@10c02100`), aliased `serial0` with
`stdout-path = "serial0:115200n8"` in `board/mister/de25nano/socfpga_agilex5_de25nano.dts`. It is
the only enabled 8250 port, so it is `ttyS0` under any 8250 numbering rule; uart0 is the SoC
Development Kit's console and belongs to a different board. Getting this wrong produces a board
that looks **dead**, not one that prints an error — which is why the checker pins it.

---

## 2. History: the interim developer card

Until 2026-11-24 the card was p1 FAT32 (`0x0c`, 256 MiB) plus p2 = `rootfs.ext4` written
verbatim and mounted directly (`root=/dev/mmcblk0p2 rw`). There was no initramfs and no
installer. That kept the first hardware contact small, and it is the card the tester booted
(#318). ADR 0029 D11 (2026-09-03) had already chosen the DE10's two-stage layout as the target,
with the interim card to stay "until a board has booted it". Once the tester's board had booted
it, the interim card was replaced, before the first `de25-*` pre-release, so no published card
uses a layout users would have to discard.

---

## 3. The first-boot installer

`board/mister/de25nano/initramfs-overlay/usr/libexec/mister-installer/install` is a separate
script from the DE10's. It shares the flag
([`installer-init.md#the-flag`](installer-init.md#the-flag)), `install-flag`, the static
`mkfs.exfat`, the exFAT AU alignment and the MBR byte encoders. Stage 1's `/init` is the same
file on both boards: it resolves `root=` (p2), sees an armed flag, and execs the board's
installer.

**Why a separate installer, and why it is much simpler.** The DE10 installer has to rewrite the
partition its payload lives on: data p1 and the `0xA2` boot partition are both moved to fill the
card, so it stages the payload in RAM and has an unrecoverable state if power is cut during the
copy-back. On the DE25 the boot partition is p1 and **never moves**. It holds the payload
permanently (`mister-payload/linux/linux.img.gz`) and the installer mounts it read-only, so
**nothing the installer does can leave the card unbootable**:

1. Check the payload on p1 and test the gzip stream end to end before anything is written. A
   corrupt download stops here.
2. Classify p2 and act on its state:
   - **fresh:** FAT labelled `MISTERSETUP`. Install.
   - **resume:** exFAT `MiSTer_Data` with the in-progress token, or a p2 that already has the
     installer's full-card geometry but no readable filesystem (mkfs was cut short). Install.
   - **finish:** exFAT `MiSTer_Data`, no token, with `linux/linux.img`. Only the flag is left
     to spend.
   - **foreign:** anything else. Spend the flag and boot normally, never format.
3. Stash the user's pre-seed files from the setup volume into RAM: `wpa_supplicant.conf`,
   `_wpa_supplicant.conf`, `samba.sh`, `_samba.sh`, `Scripts/`, `config/`. These are the same
   names as the DE10's, and README.txt tells the user about them.
4. Rewrite MBR entry 2 to type `0x07`, from p2's shipped start to the end of the card (capped at
   the MBR's 32-bit limit). Every other MBR byte is kept, including entry 1's type and bootable
   flag. p1 is unmounted for the partition-table re-read, and the kernel's new view is checked
   against the intended start and size.
5. Run `mkfs.exfat -n MiSTer_Data` aligned to the card's erase-block size, then write the
   in-progress token and the pre-seed files to the card.
6. Copy the payload, and expand `linux.img.gz` to `linux/linux.img` through a `.part` name.
7. Apply the pre-seed files (same destinations as the DE10), then remove the token.
8. Spend the flag (the commit point), delete entry 3, and reboot.

Until step 8 the flag is armed, so a power cut at any point re-runs the install from the
untouched p1. That makes the DE10 installer's RAM budget, copy-back recovery and
`mister-payload.part` states unnecessary here.

**Not carried over from the DE10 (yet):**
- the free-space trim and its fake-capacity check;
- the HDMI and LED splash (no ItsAlive on this board: `BR2_PACKAGE_MISTER_INITRAMFS_ITSALIVE`
  is ARM-only);
- the per-board MAC in `linux/u-boot.txt`, which the DE25's U-Boot does not read.

Progress goes to the serial console only.

**Tested in QEMU** by `scripts/test-sdcard-install-de25.sh`, after `make de25` and
`scripts/test-initramfs.sh --board de25nano` (which builds the aarch64 test kernel around this
build's cpio). On a 2 GiB virtio card it runs four boots:
1. a fresh install with a pre-seeded `wpa_supplicant.conf`, power cut during the expand;
2. the resume. The host then checks that the MBR is as above, the flag is gone, p1 is
   byte-identical to the shipped image's, and p2 passes `fsck.exfat -n`;
3. a normal boot through stage 1 to `switch_root`;
4. a shell that checks `linux.img` against the payload and finds the pre-seed in `linux/`.

The payload on p1 is left in place after the install. It costs ~150 MiB of a partition users do
not see, and it is the source a future "reinstall" would use.

---

## 4. MBR, not GPT — and why that is a fail-closed choice

The only reader that matters for the partition table is Terasic's **factory** U-Boot SPL, and
the question is which partition drivers it was compiled with (`SPL_DOS_PARTITION` vs
`SPL_EFI_PARTITION`). What the dossier actually records:

- [`de25-boot-chain.md`](de25-boot-chain.md) §8.3 enumerates the SPL's compiled-in contract from
  the mainline `socfpga_agilex5_defconfig` — `SPL_LOAD_FIT`, `SPL_LOAD_FIT_ADDRESS=0x82000000`,
  `SPL_FS_FAT`, `SYS_MMCSD_FS_BOOT_PARTITION=1`, `SPL_FIT_SIGNATURE`, `ENV_IS_IN_FAT` — and **no
  partition-table symbol appears anywhere in it, in either direction**. The published factory SPL
  was carved only for its DTB (§8.2); nobody has read its binary for partition support. GPT is
  therefore **unproven, not disproven**.
- The one positive partition-table datum anyone has is **MBR**: a physical DE25-Nano has been
  observed booting from an MBR-partitioned card — *"Single active MBR partition, exFAT, spanning
  the card"*, [`de25-reference-implementation.md`](de25-reference-implementation.md):572 — under
  an SPL built from the **same U-Boot 2025.01 vendor tree** the factory SPL comes from (:212;
  both identify as `2025.01`, vendor=terasic).

Two partitions need nothing GPT offers. So the choice is: take the option with evidence behind
it. **If an SPL readback (boot-chain §5) ever proves `SPL_EFI_PARTITION` is compiled in, this
becomes a one-line change in `genimage-sdcard.cfg` — and a change that must be re-tested on
hardware, never waved through at a desk.**

---

## 5. Building the card

```sh
make de25
```

`BR2_ROOTFS_POST_IMAGE_SCRIPT` runs `board/mister/de25nano/post-image.sh` at the end of the
image step. It:

1. cross-checks that its own file names still match `genimage-sdcard.cfg` (drift between the two
   is a hard error, not a mystery three steps later);
2. asserts `Image`, the DTB, `rootfs.ext4` and `mister-install-flag.bin` exist, reporting **all**
   that are missing;
3. generates `$BINARIES_DIR/extlinux/extlinux.conf`, gzips `rootfs.ext4` into
   `mister-payload/linux/linux.img.gz` (`gzip -n`, so the build stays reproducible), and writes
   the setup volume's `README.txt`;
4. runs Buildroot's own `support/scripts/genimage.sh -c board/mister/de25nano/genimage-sdcard.cfg`;
5. hands `sdcard-de25.img` to `scripts/check-sdcard-de25.sh`, whose nonzero exit fails the build.

**The missing-`u-boot.itb` case.** Until D2.2 lands `BR2_TARGET_UBOOT` +
`BR2_TARGET_ARM_TRUSTED_FIRMWARE` there is no FIT in `output-de25/images/`, and a card without
one cannot boot. The **default is to fail the build**. `DE25_ALLOW_NO_UBOOT=1` downgrades that to
"skip the card, build succeeds", with four lines of warning — for kernel/rootfs iteration only:

```sh
DE25_ALLOW_NO_UBOOT=1 make de25
```

It is an opt-in and never a default, because a silently FIT-less image is exactly the artifact
somebody writes to a card and then debugs at a dead serial console for an hour.

To re-check an image without rebuilding:

```sh
scripts/check-sdcard-de25.sh output-de25/images/sdcard-de25.img
```

Exit codes: `0` all assertions pass, `1` a contract violation, `2` usage/IO/tooling error. Host
tools (`sfdisk`, mtools' `mdir`/`mcopy`/`mlabel`, `dumpe2fs`, `e2fsck`) are resolved from
`output-de25/host/{bin,sbin}` first and `PATH` second, so any machine that can build the image
can check it.

---

## 6. Writing the card

**Prebuilt cards.** Instead of building (§5), you can download a card from the newest
`de25-YYYYMMDD` pre-release on the repository's
[Releases page](https://github.com/mcfbytes/Buildroot_MiSTer/releases). Those releases are cut
by hand from `de25-build.yml` ([`ci.md#de25-manual-lane`](ci.md#de25-manual-lane)). They are
never offered by `db.json` and never marked "latest". Verify the download, then decompress:

```sh
sha256sum -c --ignore-missing SHA256SUMS
gh attestation verify sdcard-de25.img.xz --owner mcfbytes   # optional: build provenance
xz -d sdcard-de25.img.xz                                     # -> sdcard-de25.img
```

The same release also has the loose p1 files (`u-boot.itb`, `Image`,
`socfpga_agilex5_de25nano.dtb`). To update only the boot partition of a card that already
boots, copy those three over the files of the same name on `DE25BOOT`. It is hidden from Windows
(§1), so do this from the board itself (`mount /dev/mmcblk0p1 /mnt`) or from Linux.
`bl31.bin` is already inside `u-boot.itb`, so do not copy it on its own.

> **Writing erases the entire card.** All partitions, not just files. Identify the device with
> `lsblk` (Linux) or `diskutil list` (macOS) before you type it — getting this wrong overwrites
> the wrong disk.

```sh
sudo dd if=output-de25/images/sdcard-de25.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

Replace `/dev/sdX` with your card (on macOS `/dev/rdiskN`, after
`diskutil unmountDisk /dev/diskN`). Wait for the command to return fully before removing the
card. balenaEtcher and Raspberry Pi Imager work too — the image is a plain `dd`-able disk image.
Like the DE10's, it finishes installing itself on the first boot (§3), which takes a few minutes
and ends in a reboot. Copy ROMs to `MiSTer_Data` after that, not before: the setup volume is
erased, apart from the pre-seed files.

**Verify before you switch.** Same discipline this repo uses for every DE10 flash: **keep a
known-good card and do not overwrite it with an unproven build.** On this board that rule is
sharper than usual, for two reasons:

- The card is the *only* thing you can roll back. If a release ships a `u-boot.itb` the factory
  SPL cannot parse, the failure is **strand-class, not brick-class** — QSPI is untouched, so
  re-imaging with the *previous* card boots the board again (boot-chain §7 row 2). That escape
  hatch only exists if the previous card still exists.
- Without a serial console attached, a stranded-at-SPL board is **indistinguishable from a bad
  card**. Attach serial before you conclude anything (§7).

Use a second card for the new build, boot it, confirm §7's checklist, and only then reuse the
old one.

---

## 7. First-boot serial checklist

115200 8N1 on the board's UART header (HPS uart1). Watch for these, in order — each line that
does **not** appear localises the failure to one link of the chain
([`de25-boot-chain.md`](de25-boot-chain.md) §2):

| # | What you should see | If it is missing |
|---|---|---|
| 1 | **SPL banner and DDR init** — the factory SPL running out of QSPI, before anything on the card is read | Nothing on the card is implicated. Check power, the UART cable, and MSEL/SW5 at its factory default (`001`, AS Fast). A board whose QSPI was modified is a different board — §8. |
| 2 | **SPL loading `u-boot.itb`** from `mmc0` | The FAT/entry-1/filename contract failed. Confirm p1 is entry 1, FAT32, and holds `u-boot.itb` (the checker asserts all three) — then suspect the **partition-table type** (§3) or FIT signature policy (boot-chain §7 row 6). This is D0.1 Q3, and it has never been tested on hardware by anyone. |
| 3 | **The `U-Boot 2026.07 …` banner.** Note what you will *not* see: **no `NOTICE:  BL31:` lines**. TF-A's Agilex 5 platform prints on **UART0**, not the uart1 header this cable is on ([`de25-uboot.md`](de25-uboot.md) §5 on the uart0/uart1 split), so a silent BL31 is expected and is not evidence of anything | The FIT loaded but its contents did not run: an ATF/U-Boot pairing problem, not a card-layout one (implementation-path §8 Q5). |
| 4 | `Loading Environment from FAT` | **Stop and read boot-chain §7 rows 5/11/12 before proceeding.** `Loading Environment from UBI` means the U-Boot build has `ENV_IS_IN_UBI` compiled in, and the UBI attach path can **write QSPI on an environment LOAD**, with no `saveenv` anywhere. That is the brick-class hazard the whole posture is built around. |
| 5 | **U-Boot picking up `extlinux/extlinux.conf`** on `mmc 0:1` and reporting the `de25` label | The extlinux bootmeth did not find or parse the file. The checker proves the file is there and parses; what it cannot prove is U-Boot's **search path** and **mmc device number** — see §9. |
| 6 | Kernel `Booting Linux on physical CPU`, then `earlycon` output | Kernel loaded but the console argument is wrong, or `Image`/DTB mismatch. |
| 7 | **First boot only:** `[init] first-boot installer flag found`, then `[installer]` lines ending `installer flag spent` and a reboot (§3) | A `MiSTer INSTALLER: FAILED` banner names the step. p1 is untouched, so power-cycling re-runs it. |
| 7b | `[init] data partition mounted as exfat`, `[init] /media/fat = /dev/mmcblk0p2 (exfat)`, `[init] switching root` | A `MiSTer initramfs: BOOT FAILED` banner names the cause. "root device … did not appear" points at mmc0 under the SMMU (implementation-path §8 Q2), not at the card. |
| 8 | `Welcome to MiSTer DE25-Nano (developer OS)` and a login prompt on `ttyS0` | getty/console mismatch. |

**The framebuffer and the scaler (2026-11-24).** The image lays out LPDDR4 as the third-party
DE25 port does ([`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7), so its MENU
fabric and its Main_MiSTer build can be tried on this card. At a root shell:

| Check | Expect |
|---|---|
| `dmesg \| grep -i mister_fb` | `fb0: MiSTer_fb frame buffer device at 0xa0001000+0x7ff000`, then `no vsync IRQ in the DT node` |
| `cat /sys/class/graphics/fb0/name` | `MiSTer_fb` |
| `ls /proc/device-tree/reserved-memory/` | the six `mister-*` nodes, from `mister-ddr-low@9df00000` to `mister-core@b0000000` |
| `head -1 /proc/meminfo` | `MemTotal` under 479 MiB (`mem=479M`, less the kernel's own reservations) |
| `ls /dev/mister/` | `ddr-aperture ddr-low doorbell fb h2f-bridge irq lw-bridge ocram scaler`; if absent, check `ls /etc/udev/rules.d/` lists `65-mister-uio.rules` and `65-mister-uio-de25.rules` (this image's rootfs, not another) and that `udevd` runs |

The port's own boot service writes the scaler scratch base into the fabric's fbcfg mailbox once
its MENU fabric is up; this image has no such service, so with that fabric configured (and only
then: a read of an unconfigured fabric is an SError), do it by hand with BusyBox `devmem` (in the
image). Until it is written the port's ascal stays gated, so the menu picture needs it:

```
devmem 0x2001021c 32              # must print 0x5CA623FB, else stop: wrong or no fabric
devmem 0x20010200 32 0x9e000000   # the scaler scratch base
```

`itsalive hdmi` does the same two steps behind a fabric guard (it refuses, touching nothing, if
`/proc/cmdline` and `fpga0`'s state do not show a configured fabric), and `itsalive up` then
switches the scaler to `/dev/fb0`, a 1280x720 frame buffer on the fabric's 1080p output, so
`itsalive say hello` or fbcon's console shows on HDMI. `itsalive probe` reads only. Exit 10 is
the guard refusing, 15 a wrong MAGIC. Never run it while the port's Main or its `mister-fb`
service is running: two writers on one mailbox corrupt each other.

Log the whole session. Several of the dossier's open `[U]`s (Q3 in particular) are answered by
lines 2–3 of a single boot log, and that log is worth more than any further desk work.

---

## 8. If the board is borrowed — do this first

**The QSPI must hold the factory phase-1 image.** Our card ships `u-boot.itb` only and relies
entirely on the *factory SPL's* contract (FAT on partition 1, FIT at `0x82000000`, boot order
`mmc0`). A modified QSPI carries a **different SPL with a different contract** — the reference
board's, for example, is exFAT-aware and RSU-shaped — so a boot failure on such a board tells us
**nothing** about our image.

The full procedure, the restore command, the `golden_top_hps.jic` hash to verify first, and the
safety bar that gates any image leaving this machine are in
[`de25-nano-tasks.md`](de25-nano-tasks.md) → **"Testing on a borrowed board before we own one"**.
Read it before shipping anyone a card. The two rules that matter most:

- **Never run any Terasic demo's `flash_program.bat`**, and never run `flash_erase.bat` as a
  first step — it destroys the only known-good baseline that has ever existed for that board
  (boot-chain §6's ordering rule, §7 rows 13/16).
- **Record the board revision and the Resource Package version** with any result. A rev-A vs
  rev-B mismatch is silent and is §7 row 14.

---

## 9. What the checker proves, and what it cannot

`check-sdcard-de25.sh` asserts, from the image bytes alone: MBR (and no GPT signature at LBA 1),
exactly three entries (boot, data, flag), no `0xA2`; p1 = `0x1c`, bootable, ≥ 512 MiB and
genuinely FAT32 (read from the BPB, not trusted from the type byte), labelled `DE25BOOT` and
holding the boot files and the payload **and nothing else**; the payload gunzips to this build's
`rootfs.ext4` byte for byte, which is ext4 (`extent` present), labelled `rootfs` and
`e2fsck -fn`-clean; p2 = `0x0c`, 1 MiB-aligned after p1, labelled `MISTERSETUP` and holding only
`README.txt`; entry 3 = `0xda` at LBA 1024 for 1024 sectors, with this build's flag sector
there; that `u-boot.itb` is byte-identical to the build's own, that `dumpimage -l`
shows the §6.1 FIT contract (`uboot` at `0x80200000`, `atf` at `0x80000000`, `fdt-0`, a default
configuration signed `crc32`), and that the decompiled FIT declares no `rsa`/`required`/`sha<n>`
verification; `extlinux.conf` parses, names a default that resolves to a real label, names a
kernel and fdt that exist on p1, carries `root=/dev/mmcblk0p2`, `loop=linux/linux.img`, `ro`,
`console=ttyS0,115200` and `rootwait`, and mentions no flash machinery; and the whole image
within a size budget.

Two of those exist because a review found the checker passing cards that could not boot: it used
to treat extra p1 files as informational (so a `/boot.scr` carrying a flash-erase rode along —
distro boot runs `scan_dev_for_scripts` right after `scan_dev_for_extlinux`, so it executes the
moment extlinux fails), and it never opened `u-boot.itb` at all (so 4 KiB of `/dev/urandom`
under that name passed, as did a FIT re-signed `sha256,rsa2048` + `required = "conf"` — which the
keyless factory SPL would refuse on every boot).

It **cannot** prove any of the following, and none of them should be described as verified until
a board says so:

| Assumption | Owned by | How it gets settled |
|---|---|---|
| The factory SPL reads an **MBR** table | U-Boot track / D2.2 | §4. **Settled on hardware** by the tester's 10/10 boots (#318), for the type-`0x0c` card. |
| The factory SPL accepts a **hidden (`0x1c`)** p1 | §1 | `disk/part_dos.c` says yes; the first boot of this layout settles it. |
| Windows shows only `MiSTer_Data` | §1 | Insert an installed card in a Windows PC. |
| The installer works on the board's real SD controller and a real card | §3 | QEMU covers the logic (virtio disk, no `preferred_erase_size`); a first boot settles the rest. |
| ~~U-Boot's extlinux **search path**~~ — **SETTLED [V]** | — | Closed by the built environment, not inferred: `boot_prefixes="/ /boot/"` and `boot_syslinux_conf="extlinux/extlinux.conf"`, so `/extlinux/extlinux.conf` at the root of p1 is the **first** path tried ([`de25-uboot.md`](de25-uboot.md) §9.1, read from `u-boot-initial-env` of the shipped build). The card layout matches. |
| The card is **`mmc 0`** in U-Boot and **`mmcblk0`** in Linux | U-Boot track / DTS | The factory SPL's boot order names `/soc/mmc0@10808000` (boot-chain §2 step 4), and our DTS enables exactly one SD controller — but neither is a measurement. |
| `u-boot.itb` is the **only** file the SPL wants | frozen contract, boot-chain §8.3 | Already `[V]` at the Kconfig level; `[U]` against the factory flash. |
| ~~A `uboot.env` on p1 is needed~~ — **SETTLED: no** | — | [`de25-uboot.md`](de25-uboot.md) §10 traces the code path: with `ENV_IS_IN_UBI` off there is exactly one env driver compiled in, and a missing file makes `env_fat_load()` load the built-in environment and return `-EIO` with **no write anywhere**. Shipping one is a staleness hazard for no safety gain, so the checker's p1 allow-list now **rejects** `uboot.env`. |
| The image boots at all | nobody, yet | §6. |
