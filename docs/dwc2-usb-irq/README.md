# dwc2 research record (#205)

The main write-up is [`../dwc2-usb-irq.md`](../dwc2-usb-irq.md): the carried patches,
measurements, plan and options ledger. This folder keeps what is **not** carried, so nobody has
to rebuild it: the parked feature patches, the lab instrumentation, and what the hardware
experiments established.

Nothing here is built or applied by Buildroot.

## `parked/`: full-speed interrupt-channel chaining under `fs_ddma`

Three patches that keep a full-speed interrupt-IN channel running across URBs under
descriptor DMA, appending each new URB to the live descriptor list instead of halting and
re-arming the channel every time.

- **Base:** the full series through `0066`. They apply at `-F0` on 6.18.53 and 7.2.7, and
  `drivers/usb/dwc2` builds W=1-clean with them (checked 2026-09-25).
- **Gate:** `dma_desc_enable && INT endpoint && device speed != HIGH`, via a
  `dma_desc_int_chain` core parameter that `fs_ddma=1` turns on.
- **Rig result** (RT 7.2.7, Cyclone V, 1 kHz full-speed mouse): 2 URBs in flight 500 → ~964/s,
  4 URBs 666 → 1,000/s, 1 URB unchanged at 500/s. Five authorize cycles and 30 evdev open/close
  rounds per device were clean.
- **Why parked:** usbhid, xpad and btusb keep one interrupt URB in flight, so no common MiSTer
  device gains. `snd-usb-midi` keeps 7, so a USB MIDI device on interrupt endpoints would.
- **Design points already paid for** (details in the patch messages):
  - Interrupt descriptor lists must be coherent memory (`dmam_pool`). Descriptors are 8 bytes,
    so one cache line holds four; a streaming-mapping clean after an append can overwrite the
    core's write-back of a neighbour.
  - A running channel is only appended to after re-reading `HCCHAR.CHENA` under the lock.
  - BNA must be unmasked, and "BNA seen and `CHENA` clear" is treated as the stop (see
    hardware facts below). The channel is restarted from slot 0 out of `qtd_list`, or released.
  - The ring puts EOL on slot 63; the halt then re-arms at slot 0.
  - `endpoint_reset`, port/bus suspend and `qh_free_ddma` all stop a chained channel without
    waiting forever for a `ChHltd` that may never come.
- **Before carrying:** retest on the rig with the target device (for example a USB MIDI
  keyboard), and run with `CONFIG_DMA_API_DEBUG`.

## `lab/`: instrumentation (never ship)

### `dwc2-ddma-split-probe.patch`

A lab-only dwc2 build option (`CONFIG_USB_DWC2_DDMA_PROBE`) that lets split QHs past the
descriptor-DMA refusal on request and records every channel interrupt. It is what closed the
"descriptor DMA with splits" question.

- **Base:** 7.2.7 plus `0054`–`0059`. On the full series one hunk conflicts with `0065` in
  `dwc2_hcd_qh_free_ddma()`: move the probe's `dwc2_ddma_probe_free_guard()` call to just
  before `dwc2_desc_list_free()` in the no-leak branch.
- **Module parameters** (all default off, so the module then behaves like the carried series):
  - `ddma_force`: descriptor DMA without the speed cap;
  - `ddma_split_probe`: mask of endpoint types allowed to split under DDMA (1 control, 2 bulk,
    4 interrupt; isochronous always refused);
  - `ddma_split_schinfo`, `ddma_split_desc_maxp`, `ddma_split_retries`, `ddma_probe_trip`,
    `ddma_probe_halt_us`: how a split channel is programmed and when the probe gives up;
  - `ddma_probe_log`: 1 = log every DDMA channel interrupt, 2 = also buffer-DMA split
    channels, 4 = also channel starts;
  - `ddma_probe_cpu`: CPU for the register sampler's hrtimer.
- **debugfs** under `/sys/kernel/debug/usb/ffb40000.usb/`:
  - `ddma_probe`: counters plus a per-interrupt ring (time, HFNUM, HCINT, mask, HCCHAR,
    HCTSIZ, HCDMA, current descriptor words, queue tops);
  - `ddma_sampler`: an hrtimer register sampler for one channel (minimum period 20 µs);
  - `ddma_probe_ctl`: arm, stop, kill.
- **Safety:** a trip counter, a dequeue watchdog and a kill path contain a wedged split
  channel. Never suspend with the probe loaded.

### `probe-log-analyze.py`

Decodes `ddma_probe` ring and `ddma_sampler` dumps into per-channel event sequences and
statistics. Usage: `probe-log-analyze.py [--decode] [--ddma 0|1] [--json] <dir|file>...`.

### `urbpoll.c`

A usbfs tool that detaches the class driver from one interface and keeps K interrupt-IN URBs
in flight on one endpoint. It measures the host's real polling cadence independent of the
class driver.

- Usage: `urbpoll <bus> <dev> <iface> <ep_hex> <maxp> <K> <seconds>`.
- Build as a static ARM binary with the Buildroot toolchain: `arm-buildroot-linux-gnueabihf-gcc -O2 -static -o urbpoll urbpoll.c`.

## Experiments and results

All on the DE10-Nano (DWC_otg 2.93a), RT 7.2.7 lab kernel with dwc2 as a module.

| Run | Setup | Result |
|---|---|---|
| E-1 | buffer DMA at high speed, split channels logged | calibration baseline for split timing |
| E0 | full-speed descriptor DMA, no splits | works; handshake bits (ACK, NAK, NYET) never latch in HCINT in S/G mode |
| E1a | high-speed descriptor DMA, split refusal intact | works for high-speed devices |
| E1b | high-speed DDMA, control splits allowed | SETUP retired at about the SSPLIT ACK with no visible CSPLIT; the DATA-IN stage never halted, moved no data and ignored CHDIS for 3 ms; the URB was dequeued after about 1 s and the probe's wedge/kill path had to recover the channel |
| E-1c | buffer-mode control-split calibration | a real SSPLIT ACK halt comes 28.6 µs into the microframe, against 27.4 µs in E1b, so E1b's SETUP completion was the start-split only |
| fs-2ms | `fs_ddma`, 1 kHz mouse | every poll exactly 2 frames apart, on a new channel each time: halt, giveback, resubmit and re-arm lands after the core has built the next frame |
| chain v1 | parked patches, first version | each chained channel delivered one report, then stopped for good (IRQ rate 0) |
| chain v2 | parked patches as committed | rates in the `parked/` section; no stall or leak |
| M1 | `0062`, high-speed buffer DMA | hub + pad idle IRQ-thread CPU 13.2% → 7.7%; no report loss |

## Hardware facts established

- **No splits under scatter/gather.** Handshakes are invisible in S/G mode (consistent with the
  Cyclone V TRM's HCINTn notes), and a split IN under DDMA hangs. Descriptor DMA is only usable
  when the root port runs at full speed with no hub TT in the path.
- **BNA stops a channel silently.** When the core fetches a descriptor with A=0 on a running
  non-isochronous periodic channel, it sets `XferCompl|BNA` and clears `HCCHAR.CHENA`, and does
  **not** raise `ChHltd`.
- **Descriptor prefetch.** After a short packet the core fetches the next descriptor
  immediately, so with a single URB in flight a chained full-speed interrupt endpoint still
  stops every URB and gets every other frame.
- **Data toggle** in `HCTSIZ` after a BNA stop is the next expected PID.
- **CHDIS** is ignored by a hung split channel under DDMA.
- **Split cadence in buffer mode:** a dwc2 bug, not the hardware (fixed by `0060`).

## Measurement lessons

- **Capture usbmon to RAM**, never to the SD card: stalled writes make usbmon drop events. One
  capture looked like completions without submits (a double giveback) until repeated from RAM.
- **Stop capture readers with SIGKILL or SIGTERM.** Background jobs in `sh` ignore SIGINT, so
  `timeout -s INT` never ends them.
- **An idle device sends nothing.** A mouse or pad that is not moving produces no reports; confirm
  movement before calling a silent endpoint a driver bug. Evdev readers that block on `read` never
  finish on an idle device.
- **IRQ-thread CPU:** read it from `/proc/<pid>/schedstat` run time, not tick sampling.
- **Hot-swapping `dwc2.ko` with a Realtek BT dongle attached** hit a NULL dereference in `btrtl`
  after a firmware command timeout and wedged the USB stack. Unplug BT dongles for module swaps.
- BusyBox `tar` has no `-z`; use `gzip -dc file | tar x`.
