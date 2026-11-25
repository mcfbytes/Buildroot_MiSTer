# Our patches in Linux-Kernel_MiSTer

`reconciliation.md` goes from fork to us: one row per fork commit and what this build did with
it. This file goes the other way: every change this repo sent to `MiSTer-devel/Linux-Kernel_MiSTer`
(branch `MiSTer-v6.18`), what became of it, and how we still carry it. We build from the
kernel.org tarball plus `board/mister/de10nano/linux-patches/`, never from the fork. So a merged
patch stays in our series and a merged config line stays in `linux.config`. The fork commit
it became gets a `records/` row in the next fork-sync increment.

Last checked 2026-11-25. Fork `MiSTer-v6.18` head was `2917c67b8`, the same as `fork-sync.conf`.

## Sent

| PR | What | State | Fork commit | How we carry it |
|---|---|---|---|---|
| #93 | config: `LEDS_CLASS_MULTICOLOR` (hid-playstation, hid-logitech) | merged 2026-09-12 | `697bfee03` | `linux.config` |
| #94 | config: `IP_NF_FILTER` for legacy iptables | merged 2026-09-12 | `b033b3335` | `linux.config` |
| #95 | hid-nintendo: NSO N64/Genesis stock button mapping | merged 2026-09-12 | `d3aa7de23` | `0039` |
| #96 | hid-nintendo: " IMU" name suffix | closed; Main_MiSTer #1307 took the userspace side | — | `0040` retired |
| #97 | hid-nintendo: stock LED classdev names | closed; Main_MiSTer #1308 took the userspace side | — | `0041` retired |
| #98 | MiSTer_fb: `memremap()` NULL check | merged 2026-09-12 | `6a581bac4` | inside `0001` |
| #109 | rtw88: 8821c RFE type 7 | merged 2026-10-01 | `8ad2b5ad6` | `0067` |
| #110 | config: Broadcom, Redpine, AR9271 USB Wi-Fi | merged 2026-10-02 | `e24da5873` | `linux.config` |
| #111 | config: kernel-mode NEON, NEON AES/GHASH | merged 2026-10-05 | `aadd74ae4` | `linux.config` |
| #122 | UIO write-combine memtype + HPS<->FPGA UIO nodes, `UIO`/`UIO_PDRV_GENIRQ`, `CMDLINE_EXTEND` with `uio_pdrv_genirq.of_id=generic-uio` | open (2026-11-25) | — | `0045`, `0072`, `linux.config` |
| #123 | config: `HID_BETOP_FF`, `HID_BIGBEN_FF`, `HID_MEGAWORLD_FF`, `HID_STEELSERIES` | open (2026-11-25) | — | `linux.config` |

The maintainer's pattern from #96/#97: when a patch only restores a stock 5.15 name or string,
he takes a Main_MiSTer change that accepts mainline's name instead. Offer that side first.

## Held, not sent

- `0042` (stock PlayStation lightbar names) and `0033` (DualSense `:player_id`). The same class
  as #96/#97, so the Main_MiSTer route comes first. On the fork's own 6.18 kernel, stock Main's
  lightbar writes fail for both pads. The DualSense has no `:player_id`, so Main takes its DS4
  branch, and `<hid-dev>:red` does not exist because the fork names the LEDs `inputN:red`, or
  `inputN:rgb:indicator` for the DualSense. A Main change that also writes mainline's nodes
  would fix stock users and let both patches retire once a Main release ships it.
- `0060` (dwc2 periodic QH cadence): held for more testing on 6.18. It has run mostly with
  DDMA on 7.x.
- `0070` (MiSTer_fb mmap/flush/vsync-unlock/mode clip): to go as one fb series. It changes no
  stock behaviour Main relies on, but nothing public uses the flush ioctl yet.
- `0071` (24 MiB fb region): not for the fork. It breaks zaparoo-scanout's 8 MiB `reg` check.

## Others' fork PRs we carry

These are in `reconciliation.md` as fork commits: #91 → `0048`, #92 → `0049`, #105 → `0052`,
#106 → `0053`, #107 → `0037`, #114 → `0068`, #115 → `0069`, #121 → `0010`. Open #117 (UVC
config plus a `uvc_video.c` bandwidth cap) is already covered on the config side by our modular
`USB_VIDEO_CLASS`. Its `.c` hunk caps `dwMaxPayloadTransferSize` at 0x400 for compressed
formats, so two cameras can share one controller. We do not carry that hunk; see
`docs/sinden-lightgun.md`.
