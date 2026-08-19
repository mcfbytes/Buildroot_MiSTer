# DE25-Nano ("MiSTer 2.0") — readiness plan

**Governing decision:** [ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md)
(same repo, staged, framework-gated). **Task list (ultracode-targeted):**
[`de25-nano-tasks.md`](de25-nano-tasks.md). **Status:** pre-hardware, pre-framework.
Research snapshot 2026-08-19; every claim below is tagged **[V]** (verified this
session — repo file, pinned doc, or primary web source) or **[U]** (unverified /
to-be-established, with the task that pins it).

This document is the durable home for what we know, what we deliberately do not know
yet, and what "parity with existing MiSTer" would mean on this board. It is written to
survive being wrong about the SKU: if "MiSTer 2.0" lands on different Agilex-class
hardware, §1 and §4 are discarded and everything else transfers.

---

## 1. The board, and the delta from DE10-Nano

| | DE10-Nano (today) | DE25-Nano | Notes |
|---|---|---|---|
| SoC | Cyclone V SE 5CSEBA6U23I7 | Agilex 5 E-series A5EB013BB23B **[V]** | |
| Fabric | 110K LE | 138K LE, ~1.5× faster fabric **[V]** | +25% LE; more BRAM; 188 tensor blocks (irrelevant to cores, relevant to marketing) |
| HPS | 2× Cortex-A9 @ 800 MHz (ARMv7, 32-bit) | 2× Cortex-A76 + 2× Cortex-A55 (aarch64) **[V]** | big.LITTLE; enormous single-thread uplift for Main + ARM-assisted cores (ao486, PSX CD, N64 RSP-adjacent work) |
| HPS RAM | 1 GB DDR3, shared with FPGA via bridges | 1 GB LPDDR4 (HPS) + 1 GB LPDDR4 (FPGA), "jointly accessible when required" **[V spec / U semantics]** | The exact bridge/coherency semantics for a MiSTer-style shared framebuffer are **the** load-bearing unknown → task D0.2 |
| Core scratch RAM | Plug-in SDRAM module (user-supplied) | 128 MB SDRAM on-board, 16-bit **[V]** | Kills the add-on module ecosystem and its config permutations |
| Video out | HDMI via ADV7513 fed from fabric | "HDMI 2.0 transmitter, up to 1080p" **[V spec / U wiring]** | Transmitter part + whether HPS or fabric drives it: D0.1 |
| Analog / add-ons | GPIO → analog IO board etc. | 2× 40-pin GPIO, Arduino headers removed; **not pin-compatible with existing add-ons** (community consensus) **[V]** | The add-on story restarts from zero |
| Config/boot | BootROM → SPL in raw 0xA2 partition | SDM; QSPI 128 Mbit, ASx4; ATF BL2 as FSBL → BL31 → U-Boot **[V shape / U detail]** | No 0xA2 anywhere; SD-vs-QSPI split for each artifact: D0.1 |
| FPGA load from Linux | Memory-mapped fpgamgr (Main_MiSTer writes it directly) | `stratix10-soc` FPGA manager → SDM mailbox, DT overlays, RBF **[V]** | Reconfig latency unknown and core-switching-critical: D0.2 |
| Price | ~$135 (was) | $248 ($207 academic) **[V]** | |

Community/ecosystem status **[V]**: no working MiSTer port exists; the framework
maintainers have not adopted the board; forum consensus is "massive undertaking, not
binary- or pin-compatible." Mainline Linux has carried `socfpga_agilex5` arm64 DTs since
~6.6 with active additions through late 2025 (our 6.18 base has them). Mainline U-Boot
merged Agilex 5 boot support in 2025; Altera's `u-boot-socfpga` and ATF carry the
reference flow. Quartus Prime Pro ≥24.1 has a **no-cost** Agilex 5 E-series license.
Terasic ships a System CD with a GHRD (`golden_top`) — BSP quality unassessed **[U]**
(D0.1). MiSTeX (Hans Baier) is prior art for "portable MiSTer" but targets external-HPS
designs, not Agilex **[V]**.

## 2. The layer model — what "support" means here

- **L0 — the MiSTer framework port.** Main_MiSTer on aarch64, SDM-based core loading,
  a new `sys/` for cores, video/audio plumbing, the memory map. **Out of scope for this
  repo, permanently.** It is the gate for L2. We track it (D0.4); we do not build it.
- **L1 — a bring-up Linux.** Toolchain, ATF+U-Boot, kernel+DTS, SD image, serial
  console, network, FPGA reconfig proof. Entirely within this repo's competence, useful
  without L0 (kicking tires, upstream contributions), gated only on hardware.
- **L2 — MiSTer parity.** Everything in §5's matrix that depends on what L0 defines
  (fb/audio patches, core-loading integration, updateboot analogue, installer).
  Framework-gated.

## 3. The four ARM32 couplings (and only these)

Full inventory in ADR 0027 §Context. What each needs, when touched:

1. **`zImage_dtb` contract** (`board/mister/de10nano/post-image.sh`,
   `scripts/check-zimage-dtb.sh`, `docs/boot-chain.md` §7): the `cat zImage dtb` trick
   rides the ARM zImage header's end-offset field at 0x2C — arm64 `Image` has no such
   field. DE25 uses a FIT image (or separate `Image`+dtb per the boot flow D0.1 pins).
   The stage-1 initramfs embedding via `external.mk`'s `CONFIG_INITRAMFS_SOURCE` fixup
   is arch-neutral and carries over untouched **[V]**.
2. **0xA2 SD layout** (`genimage-sdcard.cfg`, `mk-sdcard.sh`, `check-sdcard.sh`):
   Cyclone-V-only. DE25 gets its own genimage config following the Agilex GSRD layout;
   partition-order lore does not transfer.
3. **Arch asserts** (`.github/actions/buildroot-build/action.yml` `^BR2_arm`/`^BR2_cortex`;
   `scripts/check-kernel-defconfig-sync.sh` sentinels): generalize to per-board expected
   symbol sets the moment a second board defconfig exists (D1.2) — they are correctness
   guards and must not be weakened to "any arch," only parameterized.
4. **`package/azcopy`**: armv7 release asset + two 32-bit-only patches (incl. the
   OABI-keyctl runtime blocker). aarch64 upstream assets exist; both patches drop out
   **[V asset naming / U runtime]** (D3.2 re-verifies on hardware — ADR-culture rule:
   a green build proves nothing about keyctl).

Everything else — 20 packages, ~44/48 overlay files, the variant machinery, docs
apparatus — is board-agnostic **[V, surveyed 2026-08-19]**.

## 4. Boot chain and update channel

### 4.1 Boot chain (mostly [U] — D0.1 produces `docs/de25-boot-chain.md`)

Known shape **[V]**: SDM boots first; ATF BL2 is the FSBL; BL31 stays resident (PSCI,
SMC); U-Boot proper; Linux. To pin down, with the same line-cited rigor as
`docs/boot-chain.md`: which artifacts live in QSPI vs SD for an "HPS-first" DE25 boot;
what the SDM demands of the SD layout; where U-Boot's environment lives and what the
warm-reboot/core-preload story becomes; what a *safe* field-update of boot firmware
looks like (the `updateboot` analogue) — including whether QSPI writes are ever needed
and how to make them power-loss-safe, since the stock DE10 `updateboot` habit of raw
`dd` + env wipe must not be cargo-culted onto a board where the failure mode is a brick
with no BootROM-from-SD fallback **[U]**.

### 4.2 Update channel (design fixed by ADR 0027; analysis [V] against the pinned Downloader)

- Per-board GitHub release tags: DE10 keeps bare `YYYYMMDD`; DE25 uses `de25-YYYYMMDD`.
  Both carry a conventionally-named `release_YYYYMMDD.7z` — the filename is never parsed
  on-device; only db.json's `hash`/`size`/`url`/`version[-6:]` are **[V]**.
- Second Pages doc `db-de25nano.json`, db_id `mister_linux_modernization_de25nano`,
  consumed only by a DE25-side updater script via the ADR 0025 private-ini mechanism.
  No device ever sees both dbs; there is no race to win or lose.
- `/MiSTer.version` stays exactly 6 bytes on both boards (full-file byte compare against
  `version[-6:]`) — board identity comes from `/proc/device-tree/compatible`, asserted
  by the updater **before** any flash step. The stock `updateboot` is board-fatal if
  crossed; the assertion is non-negotiable.
- Two escape hatches, in order of likelihood: (a) MiSTer 2.0 keeps `Downloader_MiSTer` →
  everything above applies; (b) it doesn't → the DE25 channel is free of the 7z contract
  entirely and DP-8 (below) opens.

## 5. Parity matrix

"Parity" = a DE25 user gets what a DE10 user gets from this project today. Effort:
S(mall)/M(edium)/L(arge)/XL. Gate: H(ardware, D2) / F(ramework, D3) / —(none).

| Subsystem | DE10 today | DE25 path | Effort | Gate |
|---|---|---|---|---|
| Toolchain | Buildroot gcc, cortex-a9/NEON | `BR2_aarch64` + cortex-a76.a55; glibc unchanged | S | — |
| Two-stage initramfs | static-musl cpio embedded via kconfig fixup | identical mechanism (arch-neutral) | S | — |
| Boot firmware | stock `uboot.img` hash-pinned (ADR 0017/0024) | ATF + mainline U-Boot **from source** — no stock artifact exists to pin; ADR 0024's capability work becomes the prerequisite | L | H |
| Kernel base | mainline 6.18 armv7 + 36-patch series | same tree, arm64 target; base `socfpga_agilex5` DTs in-tree | M | H |
| Board DTS | in-tree `socfpga_cyclone5_de10nano` + carried patch | **authored by us** from GHRD (no in-tree DE25 DTS yet [U]) | L | H |
| Kernel patches — input/HID (~28) | carried, arch-neutral | port as-is; series shared, applied per-board (D0.3 classifies all 36+40 patch-by-patch) | M | — |
| Kernel patches — board (~8: MiSTer_fb, audio SPI, DTS, overclock…) | carried | meaningless until L0 defines fb/audio; do not port speculatively | XL | F |
| FPGA load | U-Boot preload + Main's mailbox/fpgamgr | `stratix10-soc` + SDM; latency + mechanism dossier first (D0.2) | XL | F |
| Video (vmode, fb) | MiSTer_fb + ascal in fabric | undefined until L0 | XL | F |
| Rootfs packages (20) | armv7 | rebuild on aarch64; azcopy loses both patches; per-pkg audit D3.2 | M | H |
| Rootfs overlay & services (S40…S99, samba/ssh/ftp/ntp per parity docs) | shipped | carries over ~44/48 files; udev/vmode/uartmode board-touching remainder re-derived | S | H |
| Wi-Fi/BT | 8 Realtek OOT pkgs + bcm firmware | same packages, aarch64 rebuild (no onboard radio on either board) | M | H |
| OOT kmods (xone…) | per-kernel stamping traps known | same traps, new kernel tree; dirclean discipline carries | M | H |
| Storage (exFAT `/media/fat`, symlink-out state model) | ADR 0019/0015 etc. | model carries wholesale; installer analogue is F-gated | M | F |
| RT variant | `output-rt`, fragment-registered, CI matrix | evaluate on big.LITTLE (DP-6) — do not assume it ports 1:1 | L | H |
| sdcard installer (mr-fusion style) | `feature/full-sdcard-image` | re-derive for Agilex layout after D0.1 | L | F |
| Update channel | ADR 0025 private updater | §4.2; one more (db, updater, tag) triple | M | F |
| CI | gate → kernel-matrix → build; ~3h20m cold | manual `workflow_dispatch` lane only; no cache slice | M | H |
| Reproducibility & provenance | double-build, attestations, SHA256SUMS | same machinery, second lane | S | H |
| Docs/ADR culture | 27 ADRs, parity-doc suite | this plan is its first artifact | — | — |

## 6. Decision points (future ADRs, deliberately undecided)

Where the DE25 could be *better* than parity. Each is a numbered DP so tasks and future
ADRs can cite them; none is decided here.

- **DP-1 · Reference-image posture.** On DE10 we shadow a stock image (byte-identical
  uboot.img, parity docs, rollback-to-stock). On DE25 **there is no stock to shadow** —
  whatever ships first *is* the reference. Freedom (mainline-first everywhere, no
  bug-for-bug compatibility) and responsibility (we own recovery stories) both follow.
  This inverts many standing constraints and deserves its own ADR early in D2.
- **DP-2 · FIT image + verified boot.** The zImage_dtb replacement is a FIT by default;
  FIT signing (and ATF/SDM authenticated-boot features) would give the update channel
  integrity the DE10 never had. Cost: key management for a hobbyist project.
- **DP-3 · A/B rootfs slots.** DE10's `mem=511M` + single `linux.img` forced the
  fragile swap-then-reboot flow (§10 of the downloader contract: flash-phase errors are
  masked). With 1 GB HPS RAM and no 511M cap, an A/B `linux.img` pair with a U-Boot
  bootcount fallback becomes feasible — the single biggest robustness upgrade available.
- **DP-4 · 64-bit userland throughout.** Not optional (the HPS is aarch64) but has
  follow-ons worth deciding once: time64/Y2038 done, keyctl-OABI class of bugs gone,
  and any 32-bit-compat shims for ported framework code explicitly rejected or scoped.
- **DP-5 · Crypto extensions.** A76/A55 carry AES/SHA — hash verification (updater,
  check scripts, azcopy) gets ~an order of magnitude faster; consider defaulting
  stronger hashes where the Downloader contract doesn't pin MD5.
- **DP-6 · RT and CPU topology.** Main_MiSTer pins itself to CPU1 on DE10 (2 cores).
  On 2+2 big.LITTLE the right shape is undecided: cores/Main on A76s with housekeeping
  isolated to A55s? `isolcpus`/`irqaffinity` layout? Revisit the "no irqbalance"
  decision with 4 CPUs. Measurement-first, on hardware.
- **DP-7 · KVM.** A76 does virtualization; almost certainly out of scope for a games
  device, but note it exists before someone asks (containers for server-side tooling,
  e.g. GroovyMiSTer-adjacent services).
- **DP-8 · Native update mechanism.** If MiSTer 2.0 does *not* adopt
  `Downloader_MiSTer`, we are free of the 7z/`files/linux/*`/MD5 contract and DP-2/DP-3
  compose into a properly signed, A/B, delta-friendly channel. Decide only when the
  framework's direction is known.
- **DP-9 · UIO/doorbell + FPGA-region DTS as first-class.** The RT beta series' UIO
  doorbell/fpga-region patches (0043–0045) are bolt-ons on DE10; on Agilex, DT-overlay
  regions are the *native* reconfiguration idiom — the DE25 kernel config could make
  that the designed-in interface rather than a variant extra.
- **DP-10 · Display pipeline ownership.** If the HDMI 2.0 transmitter is HPS-reachable
  [U, D0.1], a kernel DRM path for menus/OSD becomes possible independent of the fabric
  scaler — a real architectural fork from the DE10's everything-through-ascal design.
  L0's call ultimately, but our recon feeds it.

## 7. Risks and open unknowns

- **The framework never arrives** → sunk cost is bounded to D0/D1 (docs + guards that
  improve the repo anyway). This is the design goal of the gating.
- **SDM full-reconfig latency** [U, D0.2] — MiSTer users switch cores constantly; if
  reconfig is seconds-slow or requires signed bitstreams in practice, the UX premise
  changes. This is the highest-value single unknown.
- **Shared-memory semantics** [U, D0.2] — a MiSTer-style HPS-visible framebuffer/scaler
  needs cache-coherent (or well-managed) FPGA↔HPS access; "jointly accessible when
  required" is marketing until measured.
- **Board revision churn / SKU risk** — pre-adoption hardware; recon cites revision and
  date on every claim, per house rules.
- **Two-front maintenance** — mitigated by the gates, the manual CI lane, and the fork
  trigger in ADR 0027 (revisit if DE25 acquires separate governance).

## 8. Sequencing

```
D0 recon (anytime, cheap)  ──►  D1 guards (opportunistic, with any touch of the 4 couplings)
        │
        ▼ trigger: hardware in hand
D2 bring-up (L1: toolchain→ATF/U-Boot→kernel/DTS→SD image→FPGA-reconfig proof→manual CI lane)
        │
        ▼ trigger: upstream framework port exists (D0.4 watch)
D3 parity (L2: patch port, packages, channel, installer, RT eval)  ──►  DP ADRs as reached
```

Task-level breakdown, agent sizing, and acceptance criteria:
[`de25-nano-tasks.md`](de25-nano-tasks.md).
