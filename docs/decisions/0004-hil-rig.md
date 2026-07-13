# ADR 0004 — Hardware-in-the-loop (HIL) release-gating rig

**Status:** Proposed (2026-07-13) — design only. The build is a human go/no-go
decision after Phase 3; this ADR exists to make that decision, not to pre-empt it.
**Impact:** P4.11 (this task); would add a `hil` job to P4.4's release workflow and a
self-hosted runner to the CI topology. Touches nothing in the shipped image — this is
test infrastructure, not a rootfs change.
**Implements / realizes:** constraint **A7** ("CI cannot boot the real image … optional
HIL rig later"), PLAN.md **§11** ("Real hardware gates each release — manually at first,
optionally automated later with a HIL rig (USB-SD-mux, power control, serial capture) as
a self-hosted runner"). Depends on P2.9 having established what "reaches the menu" means
on this board.
**Supersedes:** nothing. First ruling on hardware CI.

## Purpose & scope

Every phase exit gate in this project is *a hardware test, not a code review* (PLAN §12).
P1.13, P2.9, ADR 0016's v9 verification — each was a human writing a card, cold-booting a
DE10-Nano, and reading a serial log. That is exactly the step that container CI **cannot**
perform, and the gap is structural, not a matter of effort:

- **QEMU has no Cyclone V machine model** (A7). CI can (and does, in `scripts/ci-tests.sh`)
  run static SONAME/ABI checks, the stock `MiSTer` binary under a `qemu-user` chroot, and
  the initramfs `/init` on a *generic* QEMU ARM machine against synthetic disks. None of
  those exercises the real FPGA↔HPS bridge, `MiSTer_fb` on `/dev/fb0`, the audio-SPI path,
  U-Boot handing off our `zImage_dtb`, the SD controller on a 3.3 V slot, or the OSD
  actually rendering to HDMI. The project's central risk (PLAN §13: "`MiSTer_fb` /
  `/dev/mem` FPGA ABI breaks on 6.x") is only observable on silicon.
- **A container cannot cold-boot.** Half the parity bugs found so far were cold-boot- or
  read-only-root-specific (the `/run/lock` and merged-`/usr` bugs in P2.9; the async
  `rtw88` interface race in ADR 0016). These do not reproduce in a chroot.

A HIL rig closes that gap by doing mechanically what the maintainer does by hand: flash the
built image to an SD, hand it to a real DE10-Nano, cold-boot it, and assert from the serial
log that it **reaches the MiSTer menu with no panic/oops/abort**.

**Scope is deliberately narrow — one assertion, one board.** The rig validates *boot to
menu on the reference DE10-Nano*. It does **not** attempt the full §11 hardware matrix
(the Realtek dongle zoo, Bluetooth pairing, analog I/O board, MT-32, the SD-card
compatibility spread). Those need physical stimulus (a controller plugged, a BT device
paired, a specific dongle inserted) that a fixed rig cannot provide and that remain manual,
human-owned matrix checks. The rig automates the single most important, most automatable,
and most regression-prone assertion — "does it still boot?" — and nothing more.

### Why release-gating, not push-gating

- **Throughput.** A cold-boot cycle is ~60–120 s of boot plus flash + power-settle
  overhead; call it 3–5 min wall-clock per run, strictly serial (one board, one rig). That
  is fine a few times a release; it is a bottleneck on every push to a busy branch.
- **Wear & cost.** Every run cycles the SD-mux relay, the microSD connector, and the
  board's power. §"Failure modes" quantifies this — the mux and card are consumables, and
  per-push cycling burns them for near-zero marginal signal (most pushes are docs/CI/plan).
- **The real image only exists at release.** P4.1's per-commit CI builds and runs the
  container checks; the reproducible `linux.img`/`zImage_dtb` release assets are produced
  by P4.4's **tag-triggered** workflow. The artifact the rig should boot is a
  release-workflow output, so gating the release is where it naturally belongs.

So: container CI stays the fast, per-push gate; the HIL rig is the slow, per-release gate.

## What "boot to menu" means on this board (the assertion target)

The DE10-Nano (Cyclone V, dual Cortex-A9) boots stock U-Boot from the FAT/exFAT SD, which
loads our `zImage_dtb`; the embedded initramfs (ADR 0002) loop-mounts `linux.img` and
`switch_root`s into the Buildroot rootfs; BusyBox init starts services and a getty on
**`ttyS0` @ 115200 8N1**; the stock `MiSTer` binary then drives the OSD to HDMI. The
serial log the P1.13/P2.9 runs captured gives concrete, greppable markers for each stage:

| Stage | Positive marker (must appear) | Source |
|---|---|---|
| Initramfs ran, root switched | `[init] switching root` | ADR 0002 / p1-first-boot.md |
| Our rootfs (not stock) | `Welcome to Buildroot` / `PRETTY_NAME="Buildroot 2026.02.3"` | p2-menu.md |
| Services up | `Starting sshd: OK` | p2-menu.md |
| Serial console live | `login:` on `ttyS0` | p1-first-boot.md |
| **OSD ready — the definitive boot-to-menu marker** | **`Core name is "MENU"`** (plus `Using SD card as a root device`, `I/O Board type:`) | p2-menu.md |

Negative markers — **any** occurrence anywhere in the log fails the run:

```
Kernel panic     Oops      BUG:       Illegal instruction
segfault         SIGABRT   Call trace  Unable to handle kernel
```

(P2.9's v1→v2 diff shows why the negative set matters: v1 "reached the menu" yet spewed
9 `nfsrahead` SIGABRTs. A green boot-to-menu is *menu marker present AND panic set absent*,
not just the former.) The primary assertion is therefore text over the serial stream; an
HDMI-capture cross-check is a stretch option (§"Boot-to-menu assertion").

## Architecture

```
                       GitHub-hosted runner (P4.1/P4.4 build)
                       builds linux.img + zImage_dtb, uploads as artifacts
                                        │  (release tag only)
                                        ▼
   ┌───────────────────────── self-hosted runner: "mister-hil" ─────────────────────────┐
   │  small always-on Linux host (Raspberry Pi 4 / N100 mini-PC)                         │
   │  label: [self-hosted, mister-hil]                                                   │
   │                                                                                     │
   │   ┌──────────────┐    SD    ┌───────────────┐   card    ┌────────────────────────┐ │
   │   │  USB-SD-Mux  │◄────────►│  microSD card │◄─────────►│      DE10-Nano (DUT)     │ │
   │   │ host│dut│off │  (mux    │ (golden card) │  (mux to   │  Cyclone V, real HW      │ │
   │   └──────┬───────┘   to host│               │   dut)     └───────┬─────────┬────────┘ │
   │          │ USB              └───────────────┘                    │ 5V      │ UART     │
   │          │                                                       │ barrel  │ ttyS0    │
   │   ┌──────┴───────┐                             ┌─────────────────┴──┐  ┌───┴────────┐ │
   │   │  power ctrl  │─────────── switched 5V ─────►│  DE10 PSU (5V/4A) │  │ USB-serial │ │
   │   │ relay / plug │                              └────────────────────┘  │ 3.3V TTL   │ │
   │   └──────────────┘                                                      └─────┬──────┘ │
   │                                                                               │ USB    │
   │   assertion script: mux→host, flash, mux→dut, power-cycle, capture ttyS0, ────┘        │
   │   grep markers, cut power, upload serial.log, exit 0/1                                 │
   └────────────────────────────────────────────────────────────────────────────────────┘
```

### Components (concrete candidates)

1. **Runner host.** A small, always-on Linux box registered as a self-hosted GitHub Actions
   runner with a unique label (`mister-hil`). It does **not** build (the cloud runner does
   that); it only orchestrates flash/boot/assert, so a **Raspberry Pi 4 (4 GB)** or any
   idle **Intel N100 mini-PC** is ample. It hosts the three USB peripherals and the switched
   power.

2. **USB-SD-mux** — the crux. A device that owns the microSD electrically and switches it
   between the runner host (to flash) and the DUT (to boot), with an "off" state.
   - **Linux Automation "USB-SD-Mux"** (recommended). Mature, actively maintained, ships a
     clean CLI: `usbsdmux /dev/sg1 host|dut|off`. Presents the card as a normal block
     device to the host in `host` mode. ~$130.
   - **SDWire** (Tizen / Badger Embedded lineage) — the budget option, ~$50, same idea,
     fiddlier tooling and no built-in card power gating.
   The SD-mux is what makes hands-free flashing possible *and* what structurally prevents
   the P2.9 v1 corruption bug (see below).

3. **Controllable power** for cold-boot cycling. The DE10-Nano takes 5 V on a barrel jack.
   Options, cheapest-first:
   - **USB relay board** (2-channel, ~$15) in-line on the 5 V PSU output — driven over USB
     with `usbrelay`/`hidusb-relay-cmd`. Cleanest true cold cut.
   - **LAN smart plug** (TP-Link Kasa, or a Tasmota/ESPHome-flashed Sonoff, ~$15) switching
     the DE10 PSU at mains. Controlled over the LAN; slightly slower settle.
   - A networked **PDU** (e.g. a used APC AP79xx) is available but overkill for one board.
   A true power cut (not a soft reboot) is required: async-init races like ADR 0016's
   `rtw88` bug and firmware-load timing only surface from cold.

4. **Serial capture.** A 3.3 V TTL **USB-serial adapter** (FT232/CP2102/CH340, ~$10) on the
   DE10-Nano's HPS UART pins — the same `ttyS0` console the P1.13/P2.9 logs came from —
   captured at 115200 8N1 with `tio`/`picocom`/`pyserial`, timestamped, streamed to
   `serial.log`. This is the assertion's primary evidence and the artifact uploaded on both
   pass and fail.

### Flash strategy — golden card + parallel `_vN` image (cannot brick, cannot corrupt)

The rig keeps a **golden card image**: stock FAT/exFAT layout, byte-identical stock
`uboot.img`, and a `/media/fat` populated from `Distribution_MiSTer` (so `MiSTer` has a real
menu and a sample core to load). Each run does **not** rewrite the whole card. It:

1. `usbsdmux … host` — attach the card to the runner.
2. Mount the data partition and drop only the **candidate** files: the new `zImage_dtb` and
   the built image as `linux/linux_hil.img`, plus a `u-boot.txt` whose `loop=` points at
   `linux_hil.img` (the exact `_vN` parallel-image mechanism P2.9 adopted after the v1
   incident). `MiSTer.version` is written as exactly 6 bytes, no trailing newline (A10).
3. `usbsdmux … dut` — hand the card to the DE10-Nano.

Two properties fall out of this for free:

- **No brick.** The known-good stock `linux.img`/`u-boot.img` are never overwritten; a bad
  candidate boots the parallel image, and recovery is "flash the golden card again."
- **The P2.9 v1 corruption bug is structurally impossible here.** That bug was overwriting
  the *live loop-mount backing file* while it was mounted. On the rig the card is
  electrically detached from the DUT (mux in `host` mode) during every write and the DUT is
  powered off — there is no live mount to corrupt. The rig is safer than a human at a
  keyboard, not just faster.

### Boot-to-menu assertion

Primary (ship this): after power-on, stream `ttyS0` and, within a hard timeout
(e.g. 150 s), require the OSD marker `Core name is "MENU"` and the rootfs marker
`Welcome to Buildroot` to appear, and require **zero** hits from the negative marker set.
Optionally also assert `boot-to-menu wall-clock ≤ budget` (P2.9 records "≤ stock" as the
standing requirement; regressions here are user-visible).

Stretch (do not build first): a **USB HDMI capture dongle** (MS2109-class, ~$20) grabs a
frame with `ffmpeg`/v4l2 after the menu marker and checks it is non-black and matches the
OSD (histogram + template-match on the MiSTer logo, or OCR of the menu text). This catches
the one class serial can miss — `MiSTer` reports `Core name is "MENU"` but HDMI output is
actually dead (the exact `MiSTer_fb`/FPGA-bridge failure this project most fears). Worth
adding once the serial gate is proven, not before.

## CI wiring

The rig hangs off P4.4's **tag-triggered** release workflow, as one added job:

```yaml
on:
  push:
    tags: ['v*']            # release-gating: tags only, never per-push
  workflow_dispatch:
    inputs:
      hil_override: { type: boolean, default: false }   # documented manual bypass

jobs:
  build:            # P4.1/P4.4 — GitHub-hosted, containerized, reproducible
    ...
    # uploads linux.img, zImage_dtb (+ SHA256SUMS) as workflow artifacts

  hil:
    needs: build
    runs-on: [self-hosted, mister-hil]
    timeout-minutes: 15
    steps:
      - uses: actions/download-artifact@…   # linux.img + zImage_dtb hand-off
      - run: scripts/hil/run.sh             # mux→host, flash golden+candidate, mux→dut,
                                            # power-cycle, capture ttyS0, assert markers
      - uses: actions/upload-artifact@…     # serial.log (ALWAYS: if: always())
        with: { name: hil-serial-log }

  release:
    needs: [build, hil]                     # ← the gate: red hil ⇒ no Release
    if: needs.hil.result == 'success' || inputs.hil_override
    ...                                     # P4.4 asset assembly + attestation,
                                            # P4.5 db.json publish downstream
```

- **Artifact hand-off** is the standard `upload-artifact`→`download-artifact` path — the
  rig boots the *same bytes* the release will ship (and can re-verify the SHA256 before
  flashing).
- **Pass/fail reporting** is the `hil` job's exit code, surfaced as a required check on the
  tag, with `serial.log` attached to the run for triage (green or red). The release notes
  can link the HIL run.
- **Gating** is `release: needs: [build, hil]` — a failed boot-to-menu leaves the GitHub
  Release uncreated (or in draft). Because `db.json` publishing (P4.5) is downstream of the
  Release, a board that does not boot never reaches users' Downloaders.
- **Advisory vs blocking / the offline problem.** A single-board rig that is the sole
  required gate means *a dead Pi blocks all releases* — an availability trap for a
  single-maintainer project. The resolution: the `hil` job is a **required check with an
  explicit, logged human override** (`workflow_dispatch hil_override=true`, or a
  `release/skip-hil` label), because the maintainer is already the release approver (ADR
  0014). Green HIL is the default and the evidence; the override exists so a rig outage
  degrades to "boot it by hand and record that you did," never to "ship unbooted silently."

## Cost — rough BOM (2026 USD)

| Item | Candidate | ~Price |
|---|---|---|
| USB-SD-mux | Linux Automation USB-SD-Mux (SDWire ~$50 budget) | $130 |
| Runner host | Raspberry Pi 4 (4 GB) + PSU + case (reuse an idle box → $0) | $80 |
| Power control | USB relay board **or** Kasa/Tasmota smart plug | $15 |
| Serial capture | FT232/CP2102 USB-TTL adapter + jumpers | $10 |
| Golden microSD | decent-endurance card (consumable) | $12 |
| Cabling / 5 V PSU spare / mount / enclosure | — | $25 |
| **Core rig subtotal** | (assumes the daily-driver DE10-Nano is the DUT) | **≈ $270** |
| Dedicated DE10-Nano (so the rig doesn't tie up the dev board) | *optional* | +$150 |
| HDMI capture dongle (MS2109-class) | *stretch* | +$20 |
| **Fully-loaded** | dedicated board + HDMI check | **≈ $440** |

Recurring: negligible power for the always-on Pi; periodic replacement of the microSD and
(eventually) the SD-mux as consumables (see below); the maintainer's time keeping a finicky
USB rig alive.

## Failure modes & maintenance

| Failure mode | Effect | Mitigation / recovery |
|---|---|---|
| **SD-mux relay + microSD connector wear** | Both are mechanical/electrical consumables; insertion/switch cycles are finite | Flash only the small candidate files onto a golden card (not a full-card rewrite) → far fewer bytes/cycles; run release-gated (few cycles/yr), not per-push; track a cycle counter; budget one spare mux + spare cards |
| **Wedged boot / no markers** | Board hangs; assertion would hang | Hard per-run timeout (150 s boot, 15 min job); a `trap`/`finally` **always cuts power** even if the script crashes, so the board never sits hung; job exits FAIL with the partial `serial.log` attached |
| **Bad candidate image** | DUT won't boot | Cannot brick — golden `uboot.img`/`linux.img` untouched, candidate is the parallel `_vN` image; recovery = re-flash golden card (one `usbsdmux host` + `dd`) |
| **Runner offline** (Pi crashed, USB re-enumeration, DE10 hung) | `hil` job can't run → releases blocked | Documented `hil_override` bypass + fall back to a manual hardware boot recorded in the release notes; monitor the runner's registration; udev-pin device paths by serial so a re-enumeration doesn't swap `/dev/sg1`↔serial adapter |
| **Card corruption mid-write** | (The P2.9 v1 class) | Structurally impossible on the rig: card is muxed to the host and DUT is powered off during every write — no live mount exists |
| **Flaky serial (dropped bytes at 115200)** | False FAIL | Reliable USB-serial chip (FT232), short leads, common ground; assertion tolerant to line noise (grep, not exact frames); retry-once policy before declaring FAIL |
| **HDMI check false negatives** (stretch) | Menu present but capture flags black | Keep HDMI advisory/informational until proven; serial marker remains the authoritative gate |

**Owner.** Single-maintainer project ⇒ **@mcfbytes owns it** by default (ADR 0014's logic:
"if you are the only human … you *are* the named maintainer by default"). The rig lives on
his bench; recovery is re-flash the golden card / reboot the Pi / re-seat the mux — all
first-line, no second party. This ownership reality is itself an argument for keeping the
rig simple and its override honest.

## Recommendation & go/no-go

**Recommendation: DEFER the build. Adopt this design as the ready-to-execute plan, and
build it when a concrete trigger fires — not now.**

The honest cost/benefit for the project *as it stands today* (single maintainer, personal
use, ADR 0014's gate still deferred):

- **The benefit it adds is small right now.** The maintainer already boots every phase gate
  on real hardware by hand (P1.13, P2.9, ADR 0016). Releases are rare and human-initiated.
  The rig would automate a step that currently costs a few minutes of attention a handful of
  times a year, and the failure it guards against is caught anyway by the human who is
  already booting the board.
- **The cost is not small.** ~$270–440 up front, plus a second always-on machine, a
  finicky USB stack to keep alive, and consumables (mux, cards) that wear from use — all
  owned by the one person the project is trying to save time for. A rig that is red because
  the Pi rebooted, not because the image is broken, is negative value.

**The value inflects — and this ADR should be revisited — when either trigger fires:**

1. **Release cadence rises.** Once P4.6/P4.7 Renovate is merging 6.18.y stable bumps
   regularly, "the maintainer happened to boot this one" stops scaling. An automated,
   logged, reproducible boot-to-menu gate on each bump is exactly the §13 sustainability
   mechanization the plan wants, and the per-release throughput cost becomes worth paying.
2. **The project goes public** (ADR 0014's sustainability gate is signed and other people's
   devices consume `db.json`). At that point "boots on my bench" is no longer sufficient
   evidence: a release needs an attached, reproducible artifact proving *this specific
   image* reached the menu on real silicon. The HDMI-capture stretch goal graduates from
   nice-to-have to genuinely valuable here, because a dead-HDMI regression would otherwise
   reach users.

Until one of those fires, the responsible call is: manual hardware gating stays the release
gate; this design sits on the shelf, costed and wired, ready to stand up in an afternoon
when it earns its keep.

**Status remains Proposed.** The go/no-go is the maintainer's to record against the trigger
conditions above.
