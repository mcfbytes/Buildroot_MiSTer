# ADR 0036 — DE25-Nano: from a bare developer OS to a card that boots MiSTer; base generations

**Status:** Proposed (2026-11-28). The owner set the goal and took decisions D4, D5 and D6 on
2026-11-28. D3's generation 1 is a **candidate** until hash test 2 passes (§4).
**Amends:** [ADR 0027](0027-de25-nano-multi-board-readiness.md) Decision 6 and
[`de25-nano-plan.md`](../de25-nano-plan.md) §2 (the layer model's "out of scope, permanently");
[ADR 0029](0029-de25-implementation-path.md) **D1** and **D2**. **Extends**
[ADR 0035](0035-de25-own-qspi-image-first-boot-flash.md), which stays the record for the flash
image and its bench gates.
**Source of record:** issue #318 (bench results to 2026-11-27); the independent review of
2026-11-28; hash test 1 (2026-11-28, §4); [`de25-quartus.md`](../de25-quartus.md).

Evidence tags as in [`de25-quartus.md`](../de25-quartus.md): **[V]** verified here or on #318's
bench, **[P]** vendor page or file, **[S]** search-snippet grade, **[U]** unknown.

## 1. Context

**The goal moved; the governing documents did not.** The owner's goal, in their words: "for a user
to be able to flash an SD-card and boot MiSTer as they currently do with DE10-Nano without having
to mess with JTAG or anything else." Near term: a basic UI, and loading cores from userspace. A
separate self-hosted pipeline builds the RTL artifacts, so the Buildroot build of the DE25 image
stays in the open.

The documents still say otherwise:

| Document | Says | The tree does |
|---|---|---|
| [`de25-nano-plan.md`](../de25-nano-plan.md) §2 | the framework port is "out of scope for this repo, permanently" | `fpga/de25-base/` holds base-design HDL |
| ADR 0027 Decision 6 | early releases are a bare developer OS with no MiSTer binaries | still true of every published card; no longer the end state |
| ADR 0029 D1 | cores load through a DT overlay; U-Boot loading and RSU are out | U-Boot must load the boot core (ADR 0035 D2); the loader calls `fpga_mgr_load()` directly; RSU is back as an option (ADR 0035 D6) |
| ADR 0029 D2 | "no core loader" | `package/de25-fpga-load` |

**The fabric side has a binary interface the DE10 never had.** A core loads only over a phase-1
with the same HPS IO hash, and the hash moves with the base design and the Quartus version
(#318 T1). So "which Quartus" is an interface decision, to be made once, before anyone
publishes a core ([`de25-quartus.md`](../de25-quartus.md) §5).

**A board is coming to the owner's bench.** Until now every hardware result came from one remote
tester (#318).

## 2. Decision

**D1 — The goal is a card that boots MiSTer.** A user writes an SD card, powers on, and reaches a
MiSTer menu, with no PC step in the normal path. The bare developer OS of ADR 0027 Decision 6
stays what `de25-*` pre-releases ship until the pieces below exist; it is the first stage, not
the deliverable.

**D2 — What lives here, and what the image build may need.**

| Piece | Where | Built by |
|---|---|---|
| Linux image, U-Boot, TF-A, installer, loader module, user docs | this repo | the Buildroot build, in the open, **without Quartus** |
| Our base-design HDL (`fpga/de25-base/`) | this repo, as source | the RTL pipeline |
| Base pair (phase-1 `.jic`, boot `core.rbf`) and their manifest | release artifacts | **a separate self-hosted RTL pipeline**, with its owner's licences |
| Core template, Menu core, cores | their own repositories | their own builds, against a named base generation |
| A host program (a Main) | its own repository | its own build |

The Buildroot build consumes RTL artifacts as hash-pinned downloads, the way the DE10 build
takes the stock payload. It never runs Quartus and never needs a licence.

**D3 — Base generations.** A generation is the triple (exact Quartus build with patch level;
base design commit; HPS IO hash). The rules:

1. Publish the triple; never a version number alone.
2. **Candidate generation 1:** Quartus Prime Pro **26.3.0 Build 114**, no patches; Altera's
   `terasic-de25-nano-devkit/baseline-a55` at tag **`QPDS26.3_REL_BASELINE_PR`** (commit
   `8d88fc5`); HPS IO hash
   `DF9589F2122209AF6D453BEE8BA0DD18F3192FA556B0B6E245CD3CB1A8FE4B1F`. It becomes generation 1
   when hash test 2 passes (§4).
3. A core build fails if its `core.rbf` does not carry the generation's hash. The template fixes
   what Altera documents as hash inputs ([`de25-quartus.md`](../de25-quartus.md) §6).
4. Each published core carries a manifest: generation, hash, Quartus build, SHA-256. The loader
   and U-Boot refuse a mismatch with a readable message.
5. A generation is frozen for years. No Quartus update or patch is taken for convenience, and
   Altera's own later releases of the baseline are not followed.
6. A forced change is a new generation. Preferred bridge: two phase-1 images in the flash
   (RSU slots), so old cores keep loading while cores are rebuilt; otherwise a flag day
   ([`de25-quartus.md`](../de25-quartus.md) §7).
7. Nothing built against a generation is published before the generation is declared.

Why this base: it is Altera's own design for this board, already HPS-first with
`QSPI_OWNERSHIP HPS`; its licence is MIT-style with an Altera-devices-only condition, which
removes the Terasic-HDL question from ADR 0035 gate B7; and Altera publishes a prebuilt pair
with the same hash, so the generation has a public anchor **[P]**.

**D4 — Self-flash first** *(owner, 2026-11-28)*. "Self-flash first; anything else is pointless
for a broader userbase." The user path is the SD card plus the first-boot flash of ADR 0035 D4.
A JTAG flash is a bench and tester tool, and the documented recovery. Users are not asked to
flash over JTAG unless it is the only path, and they are told before the first boot what the
card does and what the JTAG fallback is. The release that first writes the flash needs all of:

- the write order and its measured exposed window (ADR 0035 gate B4);
- the first write done under the factory image, where the SDM owns the flash (gate B3);
- the reset after the write understood, and a power cycle asked for if one is needed (gate B8);
- a known-image gate: the installer writes only a board and a flash content it recognises;
- the user told beforehand ([`user/de25-first-boot.md`](../user/de25-first-boot.md)), and a
  signal on the board during the window;
- a power-cut campaign on the owner's board, and the recovery guide rehearsed end to end
  ([`user/de25-recovery.md`](../user/de25-recovery.md));
- our own SPL in the image (gate B6), so the published `.jic` has complete source.

**D5 — Two boards.** The owner's board takes everything destructive or visual: recovery drills,
every QSPI write experiment, the power-cut campaign, HDMI, the boot core, the first loader runs.
The tester's board is the second unit and, restored to factory, the "fresh user" for a
release-candidate card and the user docs. Order: [`de25-nano-tasks.md`](../de25-nano-tasks.md).

**D6 — Licences and the pipeline.**

- Building for the DE25 needs two free licences, each FIXED to one NIC and valid a year
  ([`de25-quartus.md`](../de25-quartus.md) §3). No shared NIC ID is suggested anywhere; each
  user and each runner has its own, and no `.dat` is shared or committed.
- The pipeline is open in its inputs (HDL, scripts, the pin, the installers' hashes) and its
  outputs (artifacts with `quartus_pfg -i` output, SHA-256s, compile reports). Anyone can
  rebuild with their own licences and compare the hash.
- The Quartus container we build is not published: Quartus is not ours to redistribute.
- On a public repository the licensed runner never runs a pull request from a fork: protected
  branches or manual dispatch only.
- Our own HDL stays GPL-3.0-or-later. Nothing we ship signs bitstreams or programs fuses
  (ADR 0035 §3).

## 3. Consequences

- **New tasks.** D2.13 (RTL pipeline and artifact contract), D2.14 (core template and a Menu
  core), D2.15 (a basic UI and core loading from userspace), D2.16 (the update path for the
  flash) join D2.9–D2.11 in [`de25-nano-tasks.md`](../de25-nano-tasks.md).
- **The first `.jic` anyone flashes defines an interface.** After generation 1 is declared,
  changing the Quartus build, the HPS IP or the HPS-bank pins is a new generation.
- **`de25-base-image.md` §1–§5's recipe** (Terasic's GHRD on 25.3.1) is no longer the base. It
  stays as a recipe for a factory-design image; the base is §7's.
- **A yearly chore:** the pipeline's licences expire.
- **ADR 0027's gate "an upstream framework exists"** no longer gates D2 work here. MiSTer-facing
  conventions still belong to the upstream project; this repo produces work upstream may adopt.

## 4. Evidence, and what would reverse D3

| Test | Result |
|---|---|
| **Hash test 1.** The unmodified baseline, compiled in `de25/quartus-pro:26.3.0.114-agilex5`, reproduces Altera's published hashes | **Pass [V 2026-11-28].** HPS IO hash `DF9589F2…`, IO hash `9E82C9A1…`, both identical to Altera's `ghrd.core.rbf`; timing met. Steps: [`de25-quartus.md`](../de25-quartus.md) §5 |
| **Hash test 2.** The baseline plus `de25_hdmi`, and a third design with clearly different fabric, keep the HPS IO hash and load over one phase-1 | **Not run.** Needs the owner's board for the load |

If test 2 fails and the template rules of rule 3 cannot fix it, D3's model changes: cores could
not be built independently, and the fallback is a base whose HPS bank is locked by a reused
partition, or a different loading model. That would re-open this ADR.

Also to read before D3 is accepted: whether the 26.3 release notes list `A5EB013BB23` under
*final* device support **[U]**.

## 5. Deliberately left open

1. **The video contract.** The adopted memory layout and ItsAlive's DE25 path expect the
   third-party port's `fbcfg` mailbox; our `de25_hdmi` block has its own register set
   ([`de25-base-image.md`](../de25-base-image.md) §2, §6). One contract for the boot core and
   the installer's picture is owed before generation 1's boot core ships.
2. **The loader's interface** (a bare name under `/lib/firmware` today), the **pairing guard**
   and the **quiesce contract**: D2.11.
3. **Where a minimal UI lives**: D2.15.
4. **RSU** for later updates and for a second generation: ADR 0035 gate B5, D2.16.
5. **Whether our base drops the Nios V/m**, and the second licence with it.
6. **Redistribution terms** for a built `.jic`: ADR 0035 gate B7.

## 6. Alternatives rejected

- **A JTAG flash as the first public install path, self-flash later.** Rejected by the owner
  (D4): a PC step excludes most users. JTAG stays the bench tool and the recovery.
- **Freeze on 25.3.1.** It is what `build-base-image.sh` pins, but Altera's baseline needs 26.3,
  Altera lists a phase-2 failure in HPS-first mode for 25.3.1 **[S: [KB 350657](https://community.altera.com/kb/knowledge-base/why-does-fpga-configuration-phase-2-fail-in-hps-first-boot-mode-on-agilex%e2%84%a2-5-and/350657)]**,
  and nothing of ours was ever compiled into an image with it.
- **Freeze on 25.1.1,** the only version with loads on hardware. No container, and the factory
  design it matches cannot take cores anyway.
- **Follow Altera's releases.** Every release is a new hash, so every release would be a flag
  day for every core.
