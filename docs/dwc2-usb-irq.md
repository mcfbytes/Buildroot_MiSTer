# dwc2 host: interrupt load, descriptor DMA and split transactions

Tracking issue: #205. Status as of 2026-09-25: patches `0054`–`0062` carried; M1 verified on hardware; the `fs_ddma` 1 kHz fix is in progress.

The DE10-Nano's only USB host is the Cyclone V HPS `snps,dwc2` core (DWC_otg 2.93a,
`ffb40000.usb`, IRQ 42 on CPU0). Every MiSTer USB device sits behind the on-board high-speed
hub, so full- and low-speed pads, keyboards and BT dongles are reached through the hub's
transaction translator with **split transactions**. In buffer DMA mode the driver sequences
those splits in software and keeps the SOF interrupt unmasked while any periodic endpoint
exists: 8,000 interrupts/s on the high-speed root port, whatever is plugged in.

## Measurements (hub + wired pad + BT dongle, menu idle, RT 7.2.7)

| Kernel | IRQ 42/s | IRQ-thread CPU | context switches/s |
|---|---|---|---|
| production (no series) | 9,415 | 20.6% | 37.9k |
| `0054`–`0058` | 9,575 | 16.2% | 29.0k |
| `0054`–`0059`, `dwc2.fs_ddma=1` | 100 | 0.73% | 10.7k |

- Hub alone under `fs_ddma=1`: 0 IRQ/s.
- The IRQ rate is a step function set by SOF; each device adds thread work on top
  (BT ≈ +1.4k IRQ/s and ~4 points; a high-speed 8 kHz mouse ≈ 42%).
- The whole cost lands on CPU0. Main_MiSTer pins itself to CPU1, so core timing is not
  directly affected; CPU0 work (file I/O, CD streaming, networking) runs ~1.4× slower.

## Patches

| Patch | Upstreamable | What |
|---|---|---|
| `0054-dwc2-ddma-keep-frame-list-while-periodic-qhs-remain` | yes (Fixes: 20f2eb9c4cf8) | DDMA freed the periodic frame list while other periodic QHs still used it |
| `0055-dwc2-ddma-frame-list-unmap-direction` | yes (Fixes: 95105a998dff) | frame list unmapped with the wrong DMA direction |
| `0056-dwc2-read-hfnum-for-current-frame` | yes | current-frame decisions read the live HFNUM |
| `0057-dwc2-ddma-no-sof-unmask-for-periodic-qhs` | yes (Fixes: 907a444718b8) | DDMA tracks frames in hardware; stop unmasking SOF for it |
| `0058-dwc2-host-single-irq-action` | yes | one IRQ action (common handler calls the HCD), so PREEMPT_RT wakes one IRQ thread, not two (−21% CPU) |
| `0059-dwc2-fs-ddma-param` | MiSTer-local | `dwc2.fs_ddma=1` opt-in: caps the port to full speed and enables descriptor DMA. High speed stays the default |
| `0060-dwc2-host-keep-periodic-qh-cadence` | yes (Fixes: fb616e3f837e) | a 1 kHz FS interrupt endpoint was polled every 2 ms in buffer mode; rig-measured 500 → 984 reports/s |
| `0061-dwc2-host-debugfs-hcd-stats` | with 0062 | M0: `hcd_stats` debugfs counters (SOF passes with and without work, complete-split window misses, split NAKs, halts per channel and type). Behaviour unchanged |
| `0062-dwc2-host-sof-holdoff-in-hardirq` | yes (needs 0058) | M1: the primary handler acks a SOF with nothing due and does not wake the IRQ thread. Buffer DMA only. Off switch: `echo 0 > /sys/kernel/debug/usb/ffb40000.usb/sof_holdoff` |

All carried in both the 6.18 and the RT/beta series (beta entries are symlinks), replayed at
`-F0` on 6.18.53 and 7.2.7. Not in the DE25-Nano series yet (same `snps,dwc2` core; to be
qualified on hardware).

`fs_ddma` can be flipped at runtime; it is sampled once per probe:

```sh
echo 1 > /sys/module/dwc2/parameters/fs_ddma
echo ffb40000.usb > /sys/bus/platform/drivers/dwc2/unbind
echo ffb40000.usb > /sys/bus/platform/drivers/dwc2/bind
```

Full speed on the root port means USB storage and high-speed devices run at 12 Mbit/s,
so it stays opt-in.

## Descriptor DMA with split transactions: closed

The original goal was descriptor (scatter/gather) DMA at high speed, with the hub's splits
done by the core. The core does not support that combination:

- Cyclone V HPS TRM ch. 18, HCINTn: in scatter/gather mode the ACK and NYET interrupts are
  "masked in the core", and those are exactly what drives SSPLIT/CSPLIT sequencing.
- Synopsys' own vendor driver (`dwc_otg_hcd_ddma.c`) and mainline `hcd_ddma.c` refuse splits;
  commits 8b3e233e8121 (Altera) and fbb9e22b15ad (Intel, acked by Synopsys) say so.
- Espressif's DWC_otg notes state scatter/gather has no split support:
  <https://docs.espressif.com/projects/esp-usb/en/latest/esp32s2/usb_host/usb_host_notes_dwc_otg.html>
- Rig experiments with a lab probe module:
  - handshakes never latch in S/G mode;
  - high-speed DDMA without splits works;
  - a split control SETUP retires at the SSPLIT ACK, then DATA-IN hangs and ignores CHDIS;
  - a buffer-mode calibration run matched the timing (SSPLIT ACK halt at 28.6 µs vs 27.4 µs).

Reopen only with new evidence (for example the licensed databook describing an S/G split mode).

## Plan

1. **Done:** `0054`–`0058` (−21% CPU), `0060` (2 ms repoll).
2. **In progress:** `fs_ddma` still delivers a 1 kHz FS mouse at 500 reports/s under DDMA.
   - Every poll is exactly 2 frames apart: the driver halts the channel on each completion, and the re-arm lands after the core has already scheduled the next frame.
   - Fix under development: keep an FS interrupt channel running and append descriptors to the live list.
   - First rig run: each chained channel delivered one report and then stopped. On a descriptor with A=0 this core raises `XferCompl|BNA` and clears `CHENA`, but **never raises `ChHltd`**; the driver waited for the halt forever.
   - The fix is being reworked to treat BNA with `CHENA` clear as the stop.
3. **Done: M0 + M1 (`0061`, `0062`).** Rig result, RT 7.2.7 lab kernel, high-speed buffer DMA:

   | Topology | M1 off | M1 on |
   |---|---|---|
   | hub + wired pad, idle: IRQ-thread CPU | 13.2% | **7.7%** |
   | same: context switches/s | 26.2k | 18.3k |
   | hub + pad + idle HS 8 kHz mouse: IRQ-thread CPU | 24.8% | 25.0% |

   - Half of all SOFs are acked in the hard IRQ with the pad attached (M0 showed 75% of thread SOF passes had no work).
   - Report rates and gaps for the pad and mouse are the same with M1 on and off. `cs_miss`, safety-net and race counters stayed 0; no warnings.
   - An HS mouse with five interrupt endpoints keeps a channel busy almost every microframe, so M1 cannot help there (M4b in the ledger).
   - The rig module also carried the in-progress `fs_ddma` chain patches (inert in buffer mode). `0061`/`0062` apply at `-F0` on `0054`–`0060` for 6.18.53 and 7.2.7.
4. **Gate for anything bigger:** on the M1 kernel with several devices on the hub, compare
   user-visible work (CD-streaming stutter, CHD/ROM load time, `update_all` duration) against
   "no USB load" (`fs_ddma=1` or devices unplugged). No visible difference → stop.

## Options ledger

Parked work, with the trigger that would reopen each. Update this table instead of starting a new list.

| Option | Size / risk | Expected gain | Reopen when |
|---|---|---|---|
| **M2** hard-IRQ split INT-IN engine (Raspberry Pi FIQ-style state machine) | 500–700 LOC, 2–3 weeks, high | 7–9% idle, 10–12% while playing; scales with the number of FS interrupt devices behind the hub | the §Plan gate shows a visible difference, or the DE25-Nano needs it. Preconditions: hard-IRQ latency on CPU0, COMPSPLT-only NAK re-arm, and early/late arm probes pass. Stop rule: two failed gate runs → ship M0+M1 only |
| **M2x** non-threaded fallback for M2 | +280–350 LOC, high | — | only if M2 misses line up with thread-busy windows |
| **M3** keep the channel pinned between URBs | 180–250 LOC, 1 week, medium | ~0.5–1 point; streaming pad 2 → 1 wake per report | after M2 |
| **M4a** split NAK retry for bulk/control (BT) | 250–600 LOC, 2–3 weeks, high | depends on M0's BT-bulk share (~2k IRQ/s of the floor) | M0 shows BT bulk dominates |
| **M4b** HS interrupt-IN NAK re-arm (2–8 kHz mice) | 120–350 LOC, 1–2 weeks, medium | 8 kHz mouse idle 42% → ≤ 10%; little while moving | high-speed gaming mice matter to users. Workaround: set the mouse to 1 kHz |
| **M5** hardening: lockdep + raw-lock nesting, 12 h soak, debugfs kill switch | ~80 LOC + scripts, low | — | ships with whichever of M2+ lands |
| **M6** lazy SOF on a hard hrtimer | 250–300 LOC, 2 weeks, medium–high | ~3–4% floor; the only way below 8k IRQ/s at high speed | the SOF hard-IRQ floor is still ≥ 1.5 points after M5, or the IRQ rate itself becomes a requirement |
| **PREEMPT_RT tuning** for dwc2 IRQ thread / softirq | unknown | RT pays the thread cost hardest | after M1 (its ONESHOT primary is the base) |
| **DE25-Nano** qualification | ~0 if the core revision matches | same plan applies | hardware arrives; also check whether an Agilex 5 USB 3 (dwc3/xHCI) port reaches a connector, which would do splits in hardware |
| FS cap by default | — | — | **declined**: high speed stays the default, `fs_ddma` is opt-in |

## Side issues found along the way

- `btrtl`: NULL dereference in `btrtl_download_firmware` after a vendor command 0xfc61 timeout,
  hit while hot-swapping `dwc2.ko` with a Realtek BT dongle attached. To report upstream separately.
- Under `fs_ddma=1` the first interrupt URB of a device can complete with Babble. Unexplained.
- Upstream: `0054`–`0058` and `0060` go to linux-usb as a series only after sustained rig time
  and owner approval.
