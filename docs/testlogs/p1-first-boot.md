# P1.13 — First hardware boot: **PASS**

**Date:** 2026-07-12
**Board:** Terasic DE10-Nano (Cyclone V), real hardware
**Kernel:** `6.18.33` — built by Buildroot from a hash-verified pristine kernel.org tarball, 24 MiSTer patches applied
**Artifact:** `output/images/zImage_dtb`, 8,771,237 B, sha256 `6b5706e82744d09953663604f49cb1ff619834120927e1da1af812660552826a`
**Rootfs:** **stock `linux.img`, unmodified** (glibc 2.31, MiSTer `Version 260707`)
**Serial:** `ttyS0` @ 115200 8N1 via the board's FT232R UART-to-USB (USB Mini-B)

> **This is the Phase 1 exit gate, and it is met.** The kernel, DTS, and initramfs
> all work on real silicon. HDMI is up and the MiSTer menu renders.

## Why this test was designed the way it was

Our kernel was booted against the **stock, unmodified userland**, with the stock
`zImage_dtb` and `linux.img` left untouched on the card. The kernel was loaded
under a different filename via a `bootimage=` override appended to
`/media/fat/linux/u-boot.txt` (U-Boot's `scrtest` does `env import -t` *before*
`mmcload` reads `$bootimage`).

That isolates the variable: **only the kernel changed.** It also makes rollback
free — remove one line from `u-boot.txt`, or hold ESC at power-on for the U-Boot
prompt. Nothing stock was overwritten.

## Assertions

| # | Assertion | Result | Evidence |
|---|---|---|---|
| 1 | U-Boot loads our kernel unmodified | **PASS** | `reading /linux/zImage_dtb_mrl` → `8771237 bytes read` |
| 2 | **A3** — U-Boot finds the appended DTB at the zImage's declared end | **PASS** | `Booting using the fdt blob at 0x1858770` — **exactly** the address `check-zimage-dtb.sh` predicted (`0x01000000 + 0x00858770`) |
| 3 | Initramfs finds the data partition | **PASS** | `[init] data partition mounted as exfat` |
| 4 | **A15** — `losetup -f`, not `loop8`; device writable, mount read-only | **PASS** | `[init] loop device /dev/loop0 -> …(writable device, ro mount)`; `/sys/block/loop0/ro == 0` |
| 5 | Initramfs recreates `/media/fat` (nothing in `/etc` mounts it) | **PASS** | `[init] /media/fat = /dev/mmcblk0p1 (exfat)` |
| 6 | `switch_root` into the stock rootfs | **PASS** | `[init] switching root` → BusyBox init → `Welcome to MiSTer` |
| 7 | Serial getty on `ttyS0` | **PASS** | `login:` prompt on serial |
| 8 | **A14 — ADV7513 reachable: `i2c-0..2` exist, `i2c-3` does NOT** | **PASS** | `/dev/i2c-{0,1,2}` only. `i2c-0`/`i2c-1` = Synopsys DesignWare, `i2c-2` = `i2c_gpio` — the exact ordering P1.7 proved structurally. **HDMI confirmed on-screen.** |
| 9 | **P1.4** `/dev/fb0` + `MiSTer_fb` sysfs ABI | **PASS** | `/dev/fb0` (0660 root:video); all 8 params present; `mode` is **0664**, matching stock |
| 10 | **P1.5** `/dev/MrAudio` + patched `snd-dummy` as card 0 | **PASS** | `/dev/MrAudio` (0600 root:root — the permissions P1.5 derived from `devtmpfs` defaults *before* ever seeing hardware); `/proc/asound/cards` → `0 [Dummy]` |
| 11 | **P1.6** cpufreq overclock ABI | **PASS** | `cpuinfo_max_freq = 1200000` while `scaling_available_frequencies = 800000 400000` — the driver ceiling above the table max, exactly the mechanism P1.6 described. **No `boost` file**, confirming P1.6's correction that one never existed. |
| 12 | **P1.8** `/dev/spidev1.0` via a mainline-accepted compatible | **PASS** | Node present; **no** `spidev: probed from DT without matching compatible` warning |
| 13 | **A4** `/dev/mem` unrestricted (the whole FPGA path depends on it) | **PASS** | `/dev/mem` (0640 root:kmem); FPGA bridges `br0`/`br1`/`br2` present; Main_MiSTer loaded the MENU core |
| 14 | `mem=511M` honoured — the FPGA owns the top of DDR | **PASS** | Kernel sees **491 MiB**, not 1024. Had `mem=` been ignored, the kernel would have scribbled on FPGA memory. |
| 15 | gmac1 link (the RGMII skews) | **PASS** | `eth0` up at **1000 Mb** |
| 16 | USB enumerates | **PASS** | Full tree through the hub: `1-1.1`, `1-1.2`, `1-1.3` |
| 17 | **Clean dmesg** | **PASS** | **Zero** errors, warnings, oops, BUG, or call traces (see `p1-first-boot-dmesg.txt`) |

## Side-by-side against a **stock** boot on the same board

The maintainer captured a stock (`5.15.1-MiSTer`) boot from the same board, same
SD card, same `Main_MiSTer` build — saved as `p1-first-boot-serial-stock.txt`.
This turns "these messages are stock parity" from an inference into evidence.

**Every log line that looks like a problem appears in the stock boot too:**

| Line | Stock 5.15 | Ours 6.18 | Verdict |
|---|---|---|---|
| `*** Warning - bad CRC, using default environment` | ✅ | ✅ | U-Boot, *before* any kernel loads. Identical. |
| `rtc-pcf8563 2-0051: pcf8563_probe: write error` | ✅ (**plus** an extra `write_block_data: err=-6` line) | ✅ | Identical — and stock is the *noisier* of the two. No RTC add-on board is fitted; both kernels probe and fail. Confirms `i2c-2` is the RTC bus, as P1.7 predicted. |
| `dhcpcd: sandbox unavailable: seccomp` ×2 | ✅ | ✅ | Both have `# CONFIG_SECCOMP is not set`. Identical. |
| `ttyS1: 31250` ×2 | ✅ | ✅ | Main_MiSTer setting the MIDI baud. Identical. |
| `FileOpenEx … /media/fat/config/device.bin … No such file` | ✅ | ✅ | Identical. |
| `Failed to bring up wlanN` | wlan1 only | wlan0 **and** wlan1 | **Expected.** Stock has its `5.15.1-MiSTer` Wi-Fi modules; we have none (see below). |

**The only structural difference is the one we designed in:** stock has no
`[init]` lines because it loop-mounts the rootfs *inside the kernel* via the
out-of-tree `init/do_mounts.c` patch. We replaced that with a userspace initramfs
(PLAN §5) — which is the single biggest reduction in long-term maintenance burden
in the plan, and the `[init]` lines are it working.

### G1 — the central bet — is confirmed on silicon

Both boots run **`Version 260707`**: the *same, unmodified, stock* `MiSTer`
binary. On our kernel it starts, identifies the I/O board, finds SDRAM config 3,
loads the `MENU` core, and drives HDMI. PLAN §1's premise — *"no MiSTer binary
needs rebuilding"* — is no longer an argument. It ran.

### A3 holds on both kernels

U-Boot derives the DTB address from the zImage's declared size. The arithmetic is
exact in both cases:

```
stock: zImage 7,360,840 + DTB 20,017 = 7,380,857  -> fdt @ 0x1705148  ✓
ours : zImage 8,750,960 + DTB 20,277 = 8,771,237  -> fdt @ 0x1858770  ✓
```

and `0x1858770` is precisely what `scripts/check-zimage-dtb.sh` predicted at build
time, before the board ever saw the file.

*(Note on `SECCOMP`: we match stock, so this is not a regression. But stock being
insecure is not a reason for us to be. Enabling it is a defensible Phase 2
improvement now that parity is proven — filed, and deliberately **not** changed
mid-validation.)*

## Known and expected: no kernel modules

`lsmod` is empty. The stock rootfs ships modules for `5.15.1-MiSTer` only, and we
are `6.18.33` — so **Wi-Fi, Bluetooth and `xone` are unavailable in this test.**
This is expected and not a defect: it is precisely the variable this test holds
fixed. Ethernet was used instead, and works at gigabit.

**Phase 2/3 build our own rootfs with matching `6.18.33` modules.** Until then, a
stock-rootfs boot is Ethernet-only.

## What this does and does not prove

**Proved on silicon:** the boot chain (U-Boot → zImage_dtb → initramfs →
switch_root), the DTS (i2c numbering/A14, gmac skews, FPGA bridges, SPI, the
framebuffer node), all three MiSTer drivers, the memory reservation, and the ABI
surface Main_MiSTer actually consumes — it ran, found its core, and drove HDMI.

**Not proved:** anything requiring modules (Wi-Fi, BT, `xone`); the FAT32 and
non-ASCII paths (this card is exFAT with **zero** non-ASCII names across all
45,366 entries — which is *why* `scripts/test-initramfs.sh` exists); audio
actually reaching the FPGA (the `/dev/MrAudio` chrdev exists and card 0 is
correct, but no sound was played); the G923 regression; and B6, the deliberately
unfixed `wait_for_fsm()` bit/mask bug in `socfpga-cpufreq` — the CPU is running
at 1.2 GHz, so the PLL path evidently works, but that bug is latent by
construction and this boot does not exercise it.
