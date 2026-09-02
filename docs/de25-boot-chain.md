# DE25-Nano boot chain — QSPI, SD, and the user experience

**Status:** desk research **complete** for D0.1 — synthesis pass 2026-08-21, adversarial
refutation pass 2026-08-21, **no hardware touched**. The six §8 questions are each either
resolved to **[V]** or explicitly parked with a named blocker and an inheriting task. §9 records
which claims survived refutation, which were amended, which remain contested, and which were
never challenged — read it before trusting any single row. What remains before flash-path code
runs on a real board: D2.2's first-contact hardware tests, in the order §6 fixes. Claims are
tagged **[V]** (verified against a named source) / **[U]** (unverified, with what is missing
named). Cross-refs: [`de25-nano-plan.md`](de25-nano-plan.md) §4.1,
[ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md), and — for the DE10 baseline this
is contrasted against — [`boot-chain.md`](boot-chain.md).

> **Three facts shaped this document and are carried through §1–§7, not just §8:** (a) the QSPI
> seam is **confirmed real** — the SDM cannot boot this board from the microSD socket (§8.1);
> (b) **RSU does not fit** the DE25's 16 MB flash at the vendor's own reference sizing (§8.4), so
> there is no *demonstrated* power-loss-safe QSPI update path on this board and QSPI writes are
> ruled out of anything shipped — as **policy chosen fail-closed**, not as a proven impossibility;
> (c) mainline U-Boot's environment can silently land **in QSPI** (§8.5) — §7 row 5.
>
> **And one fact the refutation pass added, which changes §5 and §6 materially:** Terasic **does**
> publish the factory QSPI image. `golden_top_hps.jic` ships inside the downloadable Resource
> Package, and the Getting Started Guide documents the restore procedure. The first pass's
> "no image exists to write" premise was wrong — it had never been checked by opening the archive.

**Sources.**

Retrieved 2026-08-19:
- Terasic **DE25-Nano User Manual**, rev. 2025-09-05 (51 pp., via DigiKey mirror
  `mm.digikey.com/…/P0804.pdf`) — cited as *UM* §/page. Re-read pp. 11–12, 41–44 on 2026-08-21;
  text re-extracted locally from the PDF this pass.
- Altera **Agilex 5 E-series GHRD Linux boot examples**, rel-25.1
  (`altera-fpga.github.io/rel-25.1/…/ug-linux-boot-agx5e-premium/`) — cited as *GHRD*.
- RocketBoards **Building Bootloader for Agilex 5** — cited as *RB-boot*. Re-read 2026-08-21.

Added 2026-08-21 (synthesis pass):
- Terasic **DE25-Nano resource page**, `terasic.com.tw/cgi-bin/page/archive.pl?…No=1384&PartNo=4`
  (the legacy `de25-nano.terasic.com/cd/` URL 302s here) — cited as *T-res*. Note: on the
  refutation pass this host was TLS-unreachable; the download list was re-verified via the
  `dl2.terasic.com/resources/de25-nano/` index instead.
- **"DE25 Nano — Build Linux image from scratch"**, `github.com/johnnyfan1979/public_doc`,
  linked from *T-res* — community-authored, **not** a Terasic statement — cited as *T-guide*.
  Its FSBL claim is now superseded by direct inspection of the vendor artifacts (below).
- Altera **HPS Remote System Update example, Agilex 5 E-series**, rel-25.1
  (`altera-fpga.github.io/rel-25.1/embedded-designs/agilex-5/e-series/premium/rsu/ug-rsu-agx5e-soc/`)
  — cited as *RSU-ex*.
- Mainline **U-Boot** at `master`: `configs/socfpga_agilex5_defconfig`, `common/spl/Kconfig`,
  `arch/arm/mach-socfpga/spl_soc64.c`, `env/env.c` — cited as *u-boot:path*.
- Local kernel tree `output/build/linux-6.18.44` — cited as `linux:path:line`. **Every kernel
  cite in this document was re-checked against that tree on 2026-08-21**; the ones that did not
  hold are recorded in §9.2.
- Altera **Agilex 5 Device Configuration User Guide** (813773) — **TOC level only**; section
  bodies on `intel.com` returned **HTTP 403**.

Added 2026-08-21 (refutation pass — vendor artifacts, opened and inspected, not merely listed):
- **`DE25-Nano_revA_v.1.0.0_ResourcePackage.zip`** (183,940,156 B, from
  `dl2.terasic.com/resources/de25-nano/`) — cited as *RP-A*. Contents referenced here were
  re-extracted and re-hashed by this pass from the local copy; the download itself was performed
  by a refuter leg, not by this pass.
- **`DE25_Nano_Getting_Started_Guide.pdf`** (footer date September 11, 2025), inside *RP-A* —
  cited as *GSG*. Text extracted locally 2026-08-21.
- The factory SPL, carved from *RP-A*'s `…/GHRD/software/u-boot/spl/u-boot-spl-dtb.hex` and
  decompiled — cited as *SPL-dtb*. Model string: `SoCFPGA Agilex5 Terasic DE25-Nano`.

**Sources we could not obtain** (recorded so nobody re-walks the dead ends): Intel doc
**813762 / 813763** (Agilex 5 boot overview / HPS booting UG) — 403 on `cdrdv2-public.intel.com`
and `intel.com`, on independent attempts across both passes; the Agilex 5 **Reset Manager**
pages (814346, 786901) — 403; **Intel 852610** (Agilex 5 quad-SPI flash layout) — 403, and it is
the document where an RSU *minimum* layout would live, which is why §8.4's residual stays open.
The first-pass version of this doc cited *Intel-boot* (813762) and *Intel-cfg* (667140, 704696);
those citations are **retained only where a second, retrievable source carries the same claim**,
and are otherwise downgraded to [U]. Nothing here is quoted from a document we did not open.

---

## 1. The headline answer

**The seam is real and it is permanent [V].** The first two boot-chain links — SDM firmware and
the FSBL — live in the board's 16 MB QSPI and are board-resident; everything after lives on the
SD card and changes per release. The escape hatch the first pass hoped for (SDM boots phase-1 +
FSBL straight off the microSD, everything-on-card, full DE10 parity) **does not exist on this
board**: the microSD socket is wired to the *HPS* SD/MMC controller, not to SDM_IO, and *UM*
Table 3-2 documents no SD/MMC MSEL scheme (§8.1). This is board-gated, not merely undocumented.

**Routine use never writes QSPI — and nothing we ship is permitted to, by policy [V for the
default flow; the rule is policy, not a mechanism].** The QSPI ships factory-programmed (*UM*
§3.1, *GSG*); in the HPS-first flow everything a user or a release touches — U-Boot proper, ATF
BL31, the fabric bitstream, kernel, rootfs — lives on the SD card (*GHRD*). Burning a fresh SD
card and inserting it is the whole workflow; the DIP switches stay at factory default;
new-card UX matches the DE10. **But "never writes QSPI" is a rule we must enforce, not a
property of the board**: mainline U-Boot's `socfpga_agilex5` build compiles in a *UBI*
environment fallback that resolves to QSPI (§8.5, §7 row 5); U-Boot's `mtd`/`ubi` commands are
in that defconfig (§7 row 11); Linux can drive the same flash as an ordinary MTD device (§7
row 10); and Terasic's own Resource Package ships one-click `.bat` files that erase and
reprogram it (§7 row 13). As of 2026-08-21 the rule is **enforced by documentation only** — see
§5 and §9.3.

**There is no *demonstrated* safe way to write QSPI in the field [V for the sizing datum;
[U] for impossibility].** RSU — Altera's power-loss-safe QSPI update framework, the thing §6 was
going to lean on — is sized by Altera's own Agilex 5 reference example at a **2 Gbit (256 MB)**
flash with three **16 MB** application slots. One slot is the DE25-Nano's entire flash (§8.4).
No sub-16 MB layout has been demonstrated or documented, and Intel's flash-layout UG (852610) is
403-blocked. So the §5 rule is: **nothing we ship writes QSPI**, adopted fail-closed. Posture 2
(§4) survives only as a one-time bench operation with a PC and JTAG attached, never as an
update-channel artifact.

**Recovery exists, is documented by the vendor, and needs a PC [V].** MSEL→`111` (JTAG) +
Quartus Programmer over the on-board USB-Blaster III, programming `golden_top_hps.jic` from the
Resource Package — *GSG* documents exactly this. What it needs: a PC with Quartus, the **correct
board revision's** package, and an archived copy (vendor URLs rot). What is still [U]: that the
published JIC matches, or boots, any given physical board (§6, D2.2).

## 2. Boot chain, link by link

1. **Power-on → SDM** (Secure Device Manager — hard microcontroller, boots first).
   MSEL[2:0] selects the configuration source (§4) **[V UM Table 3-2 / U for the SDM-internal
   sequence: doc 813762 unobtainable]**.
2. **SDM loads from QSPI** (AS Fast, the board default): its own firmware plus the *phase-1*
   "HPS-first" bitstream — HPS pin/DDR configuration only, with the **FSBL embedded**
   **[V GHRD, RB-boot]**. On the DE25-Nano that FSBL is **U-Boot SPL**, not ATF BL2 — now
   verified against the vendor's own artifact rather than the community guide: *RP-A* ships
   `…/GHRD/software/u-boot/spl/u-boot-spl-dtb.hex` (721,613 B) beside the JIC, and the DTB
   carved from it identifies as `model = "SoCFPGA Agilex5 Terasic DE25-Nano"` **[V RP-A,
   SPL-dtb]**. BL31 is folded into `u-boot.itb` instead. *(This supersedes the "U-Boot SPL or
   ATF BL2" hedge in the first pass and the "ATF BL2 as FSBL" row in
   [`de25-nano-plan.md`](de25-nano-plan.md) §1, which should be corrected there.)*
3. **All DDR/pinmux handoff data rides inside that QSPI bitstream [V RB-boot]:** *"For Agilex 5,
   all the handoff information created by the Quartus compilation is part of the configuration
   bitstream. The bsp-editor is not used, and the bootloader build flow does not depend on the
   Quartus outputs."* There is no DE10-style QTS handoff header compiled into a preloader we
   build. DDR is **QSPI-owned**; our build cannot change it (§8.6).
4. **FSBL initializes DDR, reads the SD card**: loads `u-boot.itb` — a FIT carrying ATF **BL31**
   + U-Boot proper + DTB — from the FAT partition **[V GHRD]**. Structurally this is mainline
   behaviour: `SPL_LOAD_FIT=y` makes `SPL_FS_LOAD_PAYLOAD_NAME` default to `"u-boot.itb"`
   (*u-boot:common/spl/Kconfig*), the FS-boot partition is `SYS_MMCSD_FS_BOOT_PARTITION`
   (default 1, same file), `spl_boot_mode()` returns `MMCSD_MODE_FS` when `SPL_FS_FAT` is set,
   and `board_boot_order()` honours `/chosen`'s `u-boot,spl-boot-order`
   (*u-boot:arch/arm/mach-socfpga/spl_soc64.c*) **[V]**. **The factory SPL's actual boot order is
   now known at the desk**: `u-boot,spl-boot-order = "/soc/mmc0@10808000",
   "/soc/spi@108d2000/flash@0", "/soc/nand@10b80000", "/memory"` (*SPL-dtb* line 429) — SD first,
   then QSPI, then NAND **[V]** — though that same DTB leaves the QSPI node `status = "disabled"`
   (*SPL-dtb* line 225), so the QSPI fallback should not in fact probe **[V, inspection]**.
   From here the chain is card-resident.
5. **U-Boot loads the phase-2 fabric bitstream** (`core.rbf`, `fpga load`) and the kernel from
   the same FAT partition; boots Linux from the rootfs partition **[V GHRD]**. (A U-Boot-less
   "ATF-to-Linux" variant exists in *GHRD*; noted, not pursued.) **Open, and possibly
   project-shaping:** whether a phase-2 `core.rbf` from *our* Quartus compilation may be paired
   with Terasic's factory phase-1 — see §7 row 15.
6. **Linux reconfigures the fabric at runtime** via the SDM mailbox — `stratix10-soc` FPGA
   manager + DT overlays, an explicit `COMMAND_RECONFIG` request, full or partial
   (`linux:include/linux/firmware/intel/stratix10-svc-client.h:145-151`,
   `linux:drivers/fpga/stratix10-soc.c:195`) — the eventual core-switching path; latency dossier
   is D0.2, delivered as [`de25-fpga-reconfig.md`](de25-fpga-reconfig.md) (the SMC/SDM path end
   to end, the DT and Kconfig a DE25 must author, the VAB unknown, and the HPS↔FPGA memory
   contract) **[V driver exists / U latency]**. **Caveat found this pass:** mainline
   `linux:arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi` (826 lines) contains **no
   `firmware { svc { … } }` node at all** — only the `service_reserved: svcbuffer@0` region at
   `:23` — whereas `linux:arch/arm64/boot/dts/intel/socfpga_agilex.dtsi:63-72` instantiates
   `intel,agilex-svc` + `intel,agilex-soc-fpga-mgr`. The driver match table accepts
   `intel,agilex-svc` (`linux:drivers/firmware/stratix10-svc.c:1133-1135`), so the code is
   present but **nothing probes it on Agilex 5 without DTS we write ourselves** (DP-9 work)
   **[V]**.

**No 0xA2 analogue [V].** The DE10's raw-partition-scanned-by-BootROM mechanism does not exist
here; the FSBL finds `u-boot.itb` **by name on a FAT filesystem** (*GHRD*, and the mainline
Kconfig defaults above). The partition-order lore in [`boot-chain.md`](boot-chain.md) §2 does
not transfer.

## 3. What lives where

| Artifact | Location | Owner / change cadence |
|---|---|---|
| SDM firmware | QSPI | Altera toolchain version; effectively never (posture §4) |
| Phase-1 HPS bitstream **incl. all DDR/pinmux handoff** | QSPI | board vendor design; effectively never; **not overridable from our build [V RB-boot]** |
| FSBL = **U-Boot SPL** (`u-boot-spl-dtb.hex`) | QSPI (embedded in the phase-1 JIC) | same **[V RP-A, SPL-dtb]** |
| `u-boot.itb` (ATF BL31 + U-Boot + DTB) | SD, FAT partition 1 | **ours, per release** |
| U-Boot environment | SD FAT (`uboot.env`, `mmc0:1`) — **but a UBI fallback in QSPI is compiled in by default** | ours; the fallback is a §7 hazard, not a feature **[V u-boot defconfig + RB-boot log]** |
| Phase-2 fabric bitstream (`core.rbf`) | SD, FAT | ours / eventually per-core — **pairing with phase-1 unproven, §7 row 15** |
| Kernel (`Image`/FIT), DTB | SD, FAT | ours, per release |
| Rootfs | SD | ours, per release |

Board facts (*UM* p.9, §3.2, §3.8.4): 128 Mbit (**16 MB**) QSPI, ASx4 — the part is named in
Terasic's own programming file as `SEC_Device(MT25QU128)`, on device `A5EB013BB23BE4SR1`
**[V RP-A `…/HDMI_ASx4/demo_batch/flash.cdf`]**; **USB-Blaster III on-board** (USB-C); 1 GB
LPDDR4 on HPS "shared with FPGA" — the factory SPL DTB's memory node reads
`reg = <0x0 0x80000000 0x0 0x40000000>` = 1 GiB at 0x8000_0000 **[V SPL-dtb]**; microSD socket
wired to the HPS. *UM* §3.8.4's "not only … external storage for the HPS but also … an
alternative boot option" is **resolved**: it means the FSBL/HPS reading `u-boot.itb` (step 4),
not a second SDM path (§8.1).

**OPN discrepancy, unresolved and worth carrying [U]:** *UM* p.8 prints `A5EB013BB23BE4SR1`
(twice), the demo `flash.cdf` targets `A5EB013BB23BE4SR1`, and the Terasic BSP build record says
`A5EB013BB23BE4SCS` **[V, all three read directly]**. Which OPN a given board carries is a
first-contact observation for D2.2 (Quartus auto-detect over JTAG), and it matters at exactly
one moment: choosing which JIC to program (§7 row 14).

## 4. MSEL and the "is QSPI writing required?" decision

*UM* Table 3-2 (p.11) documents exactly **two** configuration schemes; SW5 is a 4-pin DIP with
only MSEL0–2 wired (SW5.4 = N/A) **[V, UM text re-extracted 2026-08-21]**:

| MSEL[2:0] | Scheme | Meaning |
|---|---|---|
| `001` | AS Fast | FPGA configured from QSPI Flash (**factory default**, pre-programmed) |
| `111` | JTAG | configure via on-board USB-Blaster III |

There is **no SD/MMC configuration scheme** for this board, and — unlike the first pass's
assertion — we no longer claim Agilex 5 silicon has one: the Agilex 5 Device Configuration UG
(813773) lists AVST, AS, JTAG and CvP at TOC level with no SD/MMC section, and the
original-generation Agilex guide that does document SD/MMC is a **different device family**
**[U on the silicon question — 813773's body is 403-blocked; see §8.1]**. The board-level answer
does not depend on it.

Three postures for the QSPI-resident links, one to be chosen (this graduates with the DP-1 ADR
at D2.7; the recommendation below is not yet a decision):

1. **Pin to factory QSPI; never write it** — **recommended for v1, and chosen fail-closed, not
   forced.** *(Amended: the first synthesis called it "close to forced" on the strength of an
   impossibility that is not proven — see §9.2.)* The exact analogue of the DE10 "stock
   `uboot.img`, byte-identical" posture. Our SD payload must be loadable by Terasic's shipped
   SPL. The name+location contract is the stable interface **[V GHRD, u-boot Kconfig]**; whether
   *their* SPL build accepts *our* FIT is **[U → D2.2 first test]**. The sharpest sub-risk was
   **FIT signature enforcement** — mainline `socfpga_agilex5_defconfig` sets
   `CONFIG_SPL_FIT_SIGNATURE=y` **[V, defconfig re-fetched 2026-08-21]** — and it now looks
   **defused**: the DTB carved from Terasic's published SPL contains **no `/signature` node and
   no key material** (`grep -i 'signature|required|rsa|key-name|algo'` over the decompiled DTS:
   zero hits) **[V SPL-dtb, inspected 2026-08-21]**, and U-Boot's SPL accepts unsigned FITs when
   the control DTB requires no keys. Residual: whether the factory-programmed flash matches the
   published build (§7 row 6).
2. **Ship our own QSPI image** (SDM fw + phase-1 + our FSBL): full control of the SPL/DDR
   handoff, at the cost of a QSPI flash per board at onboarding. **This is a bench-only
   operation** — PC + Quartus Prime Pro + JTAG, MSEL to `111` and back — because no
   power-loss-safe update mechanism is demonstrated to fit the 16 MB flash (§6, §8.4). It is not
   shipped through the update channel in any form.
3. **Hybrid**: start at 1; fall back to 2 only if the factory SPL proves incompatible, as a
   documented one-time bench step performed with a PC attached — **not** RSU-protected, because
   RSU is not available here.

**Revisit trigger for the DP-1 ADR:** if a sub-16 MB RSU layout is ever *proven* (§8.4 residual —
phase-1 image size plus Intel 852610's minima), posture 2/3 becomes technically shippable and the
decision must be re-opened rather than treated as settled by impossibility.

**How tightly does posture 1 pin us to Terasic?** Tighter than the first pass implied
(§8.2/§8.3/§8.6): we inherit their SPL binary, their DDR/pinmux handoff (which lives in the
bitstream and is not ours to change), and whatever FIT policy their SPL was built with. Their
published build record for the shipped BSP is Quartus Pro **25.1.1**, ATF **2.12.0**, U-Boot
**2025.01**, kernel **6.12.11-lts**, device `A5EB013BB23BE4SCS` **[V T-res]**. What we control is
exactly one interface: a FIT named `u-boot.itb` on the FAT boot partition. That is a thin
contract — which is the good news and the whole risk at once.

## 5. The version-skew seam (the one gotcha to engineer away)

QSPI side: SDM firmware + U-Boot SPL + DDR/pinmux handoff (board-resident, static, **not
reproducible from our tree**). SD side: everything else (ours, per release). Failure mode: a
release whose `u-boot.itb` the resident SPL cannot load — the DE25 equivalent of the DE10's
`zImage_dtb` contract break, except the user cannot see or fix it by re-imaging the card *if*
the mismatch is QSPI-side. Release discipline that keeps this impossible:

- **Every DE25 release records which factory QSPI it is tested against.** *(Amended: the
  synthesis pass wrote "there is no System CD to cite a revision of". Two refuters showed that is
  wrong in a way that matters — Terasic's own *GSG* still instructs the reader to "Copy the
  factory code from the path: **System CD**\Demonstration\SoC_FPGA\GHRD\output_files\
  program_qspi_flash\" **[V GSG, text extracted 2026-08-21]**, and *UM* §3.8.6 likewise cites a
  "system CD". The **Resource Package is the System CD's current incarnation**, and it carries a
  version.)* The identity handles to record are: **board revision** (rev A / rev B), the
  **Resource Package version** (revA/revB v1.0.0 — the CD-revision analogue), the **Linux Console
  BSP** version (v1.1) and its build record above, the Terasic fork tags `de25_nano_revA_v1.0`,
  and the **silicon OPN as read over JTAG** (§3) **[V T-res, GSG, T-guide]**.
- **A factory-QSPI image hash *is* obtainable — the first pass's "no `.jic` is published" was
  wrong.** *(Amended: three refuters independently opened the published archive, which no
  research leg had done.)* *RP-A* contains
  `Demonstration/SoC_FPGA/GHRD/output_files/golden_top_hps.jic` — **16,777,447 B, sha256
  `e3d20c2d066761fd02897422ba361aa19faafcd0240dd2782965754cc61b38a4`** — beside
  `golden_top_hps.sof` (1,474,367 B) and the programming scripts. **Re-hashed by this pass from
  the local copy of the archive, 2026-08-21 [V]**. What remains genuinely [U] is whether any
  *physical* board's flash equals it: no readback procedure is documented by Terasic, whose
  scripts are write-side only. Two candidate ways to close it, both for D2.2: (a) `quartus_pgm`
  **verify-only** against this JIC — the vendor's own `flash_program.bat` already uses the `pv`
  action letters (`-o "pvi;golden_top_hps.jic"`) **[V RP-A, read directly]**; (b) an HPS-side MTD
  read, which is the family-standard path — mainline ships the controller node
  (`linux:arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi:476-488`, `intel,socfpga-qspi`), the
  driver is in our tree (`linux:drivers/spi/spi-cadence-quadspi.c:2213`), and the SoCDK board DTS
  demonstrates the flash+partitions pattern
  (`linux:arch/arm64/boot/dts/intel/socfpga_agilex5_socdk.dts:68-97`) **[V]** — noting that the
  SoC `.dtsi` ships the node `status = "disabled"`, so this is an opt-in we would have to make
  (and §7 row 10 is the reason to make it read-only if at all). **Do not write "hash-pinned" in
  DE25 release docs until a verify or a readback has actually succeeded on hardware.**
- **The SPL→`u-boot.itb` interface is a frozen contract with four terms — and the first synthesis
  named the wrong Kconfig symbol for the first of them.** *(Amended: all three refuters caught
  it.)* The terms are: **(1) the FS-boot partition, governed by
  `CONFIG_SYS_MMCSD_FS_BOOT_PARTITION` (int, default 1, *u-boot:common/spl/Kconfig*) on the SPL
  boot device (`spl_boot_device()` → `BOOT_DEVICE_MMC1`, *u-boot:arch/arm/mach-socfpga/
  spl_soc64.c*) — *not* `ENV_FAT_DEVICE_AND_PART`, which places U-Boot proper's environment file
  and merely happens to also read `"0:1"`; (2) the filename `u-boot.itb`
  (`SPL_FS_LOAD_PAYLOAD_NAME`, default under `SPL_LOAD_FIT`) — present verbatim as a string in
  Terasic's shipped SPL binary; (3) FIT format / config-node selection; (4) signature policy
  (`SPL_FIT_SIGNATURE`)** **[V, defconfig and Kconfig re-fetched 2026-08-21]**. The environment
  file's location (`ENV_FAT_DEVICE_AND_PART="0:1"`) is a **separate, fifth** contract term, and
  it belongs to §7 row 5, not here. Freezing the wrong symbol would let a future partition-layout
  change validate green against the env setting while the resident SPL looks elsewhere. Changes
  to any term are release-blocking findings.
- **DDR is not ours.** Our `u-boot.itb` must not assume it may re-init or re-tune DDR; the
  handoff is inside the QSPI bitstream **[V RB-boot]**. Any future need to change DDR settings is
  a posture-2 event (bitstream rebuild + bench flash), not a release.
- **No release writes QSPI, by any mechanism, including the U-Boot environment (§7 row 5).**
  This is the load-bearing rule of the document, and its exact status as of 2026-08-21 is:
  **a policy, enforced by prose only.** The "guards" refutation lens verified, and this pass
  re-states without softening, that **ADR 0027 Decision 4's board-identity assertion has no
  implementation anywhere in the tree** — no shipped script reads `/proc/device-tree/compatible`
  or otherwise checks board identity; `ADR 0027` lines 80-83, `de25-nano-tasks.md` 120/155 and
  `downloader-contract.md` 1208-1215 are all design prose. Nothing today would stop DE10 flash
  semantics being cargo-culted onto a DE25 tree except the accident that no DE25 tree exists yet.
  **Before the first DE25 release:** (a) implement the identity assertion in the updater *and* in
  any `updateboot` analogue; (b) add a release-blocking CI check that the DE25 U-Boot config has
  `ENV_IS_IN_UBI` unset and ships no QSPI-write command set; (c) only then may "no release writes
  QSPI" be tagged **[V]** rather than "[policy, unenforced]". If a QSPI update is ever shipped
  (posture 2/3) it is a separate, explicit, documented **bench** procedure — the `updateboot`
  analogue **must not** be a cargo-culted raw `dd`: the DE10 habit (whole-disk `dd` + env wipe,
  [`downloader-contract.md`](downloader-contract.md) §8) is release-fatal here even though, per
  §7 row 3, it cannot physically reach QSPI.

## 6. QSPI update safety and the unbrick path

- **RSU does not fit this board's flash at reference sizing [V]; that it cannot fit at *any*
  sizing is [U].** RSU (Remote System Update) is Altera's power-loss-safe QSPI update framework —
  a factory fallback image plus application image slots, with the SDM falling back automatically
  on a corrupt or interrupted image. Altera's own Agilex 5 E-series SoC RSU example is built on a
  **2 Gbit (256 MB)** QSPI (`QSPI02G`), with a ~7 MB factory image and **three 16 MB application
  slots** plus BOOT_INFO/SPT/CPB overhead **[V RSU-ex]**. **One application slot alone is the
  DE25-Nano's entire 16 MB flash**, which must additionally already hold the factory phase-1
  image. The first pass's rule — *"any future QSPI-writing flow uses RSU or does not exist"* —
  therefore resolves to its second branch in practice: **nothing we ship writes QSPI.** Honest
  statement of what is *not* proven: those are the *example's* choices, not documented minima;
  the RSU layout is user-authored via `quartus_pfg` partitions; and this pass measured the
  factory JIC's non-`0xFF` content at **3,007,196 bytes (2.87 MiB)** out of a 16,777,447 B
  container (`golden_top_hps.sof` itself is 1,474,367 B) **[V, measured locally 2026-08-21 —
  with the caveat that a JIC is a container and non-`0xFF` density is a proxy for programmed
  extent, not a proven image size]**. A hand-tuned sub-16 MB layout is therefore **unproven, not
  disproven**. Blocker and owner in §8.4.
- **The kernel-side RSU code exists; the Agilex 5 device tree does not wire it up.** *(Amended:
  the synthesis pass said RSU's absence is "a flash-geometry problem, not a software-support
  problem" — two refuters showed that understates it, and one of its cites was wrong.)*
  `linux:drivers/firmware/stratix10-rsu.c` is present, and `COMMAND_RSU_*` sits at
  `linux:include/linux/firmware/intel/stratix10-svc-client.h:153-159` — **not** `:152-156` as
  first written (`:152` is the `/* for RSU */` comment) **[V, re-checked line-by-line this
  pass]**. But adopting RSU on this board needs three things beyond the driver: a flash big
  enough (unproven, above), an **RSU-formatted flash layout** (BOOT_INFO/SPT/CPB written by
  `quartus_pfg`) which the factory image does not have — i.e. a posture-2 bench reflash *first* —
  and a **device tree that instantiates the SDM service node**, which mainline Agilex 5 does not
  ship (§2 step 6) **[V]**. Nobody should read "the driver is there" as "a bigger flash makes
  this a software toggle".
- **The board is recoverable at a bench, and the payload to recover it with is published [V].**
  *(Amended: the synthesis pass's "you must have an image to write, and Terasic publishes none"
  was refuted by all three lenses, by opening the archive.)* The USB-Blaster III is on-board
  (*UM* §3.2); *GSG* documents the restore verbatim — connect USB-C to the Blaster III
  connector, copy the factory code from `…/GHRD/output_files/program_qspi_flash\`, run
  `flash_program.bat`, which is `quartus_pgm.exe -m jtag -c 1 -o "pvi;..\golden_top_hps.jic"`
  **[V GSG + RP-A, both read directly 2026-08-21]**. The real conditions are therefore: **a PC
  with Quartus Programmer; the correct board revision's package; and an archived copy** (the
  vendor URL is the single point of failure, and the local copy in the session scratchpad is
  currently the project's only one — move it somewhere durable). Still [U] and owned by D2.2:
  that the published JIC actually boots a physical board, and that factory flash equals it.
  Note also that *GSG* names no MSEL change in the restore procedure — whether `001` suffices or
  `111` is required is **[U → D2.2]**.
- **D2.2 ordering rule, fail-closed** (this exists because the vendor scripts make erase-first
  the path of least resistance — `flash_erase.bat` is `quartus_pgm … -o "ri;…"` **[V RP-A]**):
  (1) `quartus_pgm` **verify-only** against `golden_top_hps.jic`, to learn whether factory ==
  published; (2) attempt a readback/dump and archive it; (3) only then any write. **Never run
  `flash_erase.bat` as step one** — it destroys the only known-good baseline that has ever
  existed for that board.
- Net: the *boot-firmware* layer has no pull-the-card recovery (the DP-3 caveat in
  [`de25-nano-plan.md`](de25-nano-plan.md) §6 stands): recovery is bench-only and needs a PC — but
  it is no longer blocked on an image we do not have.

## 7. What would brick or strand the board (fail-closed inventory, desk-research level)

Rows 1–9 are the synthesis inventory as adjudicated; rows 10–16 were added by the refutation
pass. No row has been deleted. Severity vocabulary: **brick-class** = needs JTAG + PC;
**strand-class** = fixed by re-imaging the SD card.

| # | Action | Consequence | Guard |
|---|---|---|---|
| 1 | Raw/partial QSPI overwrite, interrupted | **Brick-class.** No SDM config → no boot from AS; recover only via JTAG + PC + a JIC in hand | §5 rule: nothing we ship writes QSPI; RSU is not available as mitigation (§6) |
| 2 | Shipping `u-boot.itb` the resident SPL can't parse | **Strand-class**, not brick-class: QSPI is untouched, so re-imaging the card with the *previous* release or Terasic's BSP card boots the board — but re-imaging with the *same* release fails identically, and without a serial console it is indistinguishable from a bad card | frozen four-term SPL contract (§5, corrected symbols) + a per-release factory-QSPI boot test. **Recorded objection** (guards lens): that test matrix exists nowhere — no DE25 hardware, no CI lane, no test doc. It must be created at D2.2 before the first release |
| 3 | Porting DE10 `updateboot` semantics (raw `dd`, env wipe at fixed sectors) | **Strand-class, and the first synthesis overstated it.** *(Amended — all three lenses.)* The `dd` leg writes garbage at Agilex-meaningless offsets **on the SD card only**: `/dev/mmcblk*` is the HPS SD/MMC controller; QSPI is a physically separate Cadence controller behind the SDM (`linux:…/socfpga_agilex5.dtsi:476-488`, `spi@108d2000`). No sector arithmetic on `mmcblk0` can reach boot flash. The **env-wipe leg** is the one that can — via row 5 or row 11 | board-identity assertion before any flash step (ADR 0027 §Decision 4 — **unimplemented**, §5), plus rows 5 and 11 |
| 4 | MSEL switched away from `001` by a user following DE10-era lore | No boot until switched back; no damage | docs: "switches stay at default". **Recorded objection** (guards lens): that sentence appears in **no user-facing document** — `docs/user/` has zero DE25 or MSEL content; today the rule lives only in this developer doc. Writing it into the DE25 user docs is a first-release blocker, not an existing guard |
| 5 | **`saveenv` (or any env write) with `ENV_IS_IN_UBI` compiled in and no `uboot.env` on FAT** | **Brick-class.** `env_save()` targets the location the env *loaded* from; on FAT-miss that is the **UBI volume in QSPI** → a routine operation writes boot flash | build our U-Boot with `CONFIG_ENV_IS_IN_UBI=n`; ship a valid `uboot.env` on FAT; assert the boot log says `Saving Environment to FAT` (§8.5) |
| 6 | **Factory SPL built with FIT signature required; we ship an unsigned `u-boot.itb`** | Every release strands at SPL on every board — indistinguishable from a bad card to the user | D2.2 first test before any release. **Recorded objection** (completeness lens, and this pass agrees on the evidence): the DTB carved from Terasic's *published* SPL carries **no `/signature` node and no keys** (*SPL-dtb*, inspected 2026-08-21), so this drops from "posture-1 killer" to a routine first-contact check. Residual is only the published-build-vs-factory-flash gap |
| 7 | **Any QSPI write attempted with no archived known-good JIC** | *(Amended — all three lenses: the premise was false.)* The JTAG path is **not** empty-handed: `golden_top_hps.jic` is published (§5) and *GSG* documents the restore. The real exposures are vendor **link-rot**, **wrong-revision** substitution (row 14), and the fact that the published JIC's bootability is untested | archive both revisions' Resource Packages **with hashes** now, locally and durably; verify before erase (§6 ordering rule); never rely on the vendor URL staying live |
| 8 | **Posture-2 QSPI flash performed as a field/OTA step** | **Brick-class today.** *(Amended — all three lenses: state the rule, not an impossibility.)* No power-loss-safe layout for 16 MB is **demonstrated or documented** (§8.4 residual; the measured ~2.87 MiB phase-1 payload makes a custom layout plausible but unproven), so a power cut mid-write leaves JTAG-only recovery for an end user | posture 2 is bench-only, PC-attached, documented one-time; never an update-channel artifact. Revisit only if §8.4's residual resolves in RSU's favour |
| 9 | Assuming our `u-boot.itb` can set/repair DDR or pinmux | It cannot — the handoff is inside the QSPI bitstream **[V RB-boot]**; a "fix it in U-Boot" reflex produces silent misconfiguration or no boot | treat DDR/pinmux as QSPI-owned; any change is a bitstream rebuild + bench flash (§5) |
| 10 | **Shipping a DTB that exposes the QSPI as a writable MTD, then any root shell / porting script running `flash_erase /dev/mtdX` or an mtd write** | **Brick-class, and it bypasses every guard aimed at `dd` and env semantics** — one userspace command from a healthy booted system erases SDM firmware + phase-1 | Our DTS omits the QSPI node, or enables it **read-only**. Precise state today: the SoC `.dtsi` ships `spi@108d2000` **disabled** (`linux:…/socfpga_agilex5.dtsi:476-488`) and it is the *board* DTS that enables it with writable `fixed-partitions` (`linux:…/socfpga_agilex5_socdk.dts:68-97`) **[V]** — so this is a hazard we would have to opt into, including if we opt in for the §5 readback. Audit Terasic's kernel DTB for the same at D2.2. [U] whether the SDM grants HPS access to the flash on this board — D2.2 |
| 11 | **Shipping `fw_setenv`/libubootenv with an `fw_env.config` that names an MTD device** (copied from a reference BSP, or a DE10 env-wipe habit ported) | **Brick-class and silent**: Linux-side env writes reach QSPI without U-Boot involved, headless, repeatedly. Row 5's `ENV_IS_IN_UBI=n` does **not** protect this path — `fw_setenv` does not consult U-Boot's compiled-in drivers | if shipped at all, `fw_env.config` names only the FAT-partition `uboot.env` file; CI greps the rootfs for MTD-pointing env configs |
| 12 | **Booting a U-Boot with `ENV_IS_IN_UBI` against a QSPI whose `root` MTD partition is blank**: the env **load** path runs `ubi part root`, and a UBI attach on an empty MTD auto-formats it | Worse than row 5 — QSPI is written on an environment *load* miss, with no user action at all, destroying the pristine-factory baseline before it can be hashed | same guard as row 5, promoted from prudent to mandatory: `CONFIG_ENV_IS_IN_UBI=n`. **[U] mechanism:** U-Boot's `ubi_part` auto-format-on-attach behaviour was **not** verified this pass — named missing input: read `env/ubi.c` + `cmd/ubi.c` in a U-Boot checkout. Note the SoCDK DTS does define a partition literally labelled `root` (`linux:…/socfpga_agilex5_socdk.dts:91-93`), matching `ENV_UBI_PART="root"` **[V]** |
| 13 | **A user runs a Terasic *demo*'s `flash_program.bat`** from the same Resource Package our docs will point them at | **Strand-class-with-a-bench-recovery.** These demos ship full-flash **fabric-only** JICs and a one-click programming flow: `…/FPGA/HDMI_ASx4/demo_batch/golden_top.jic` (16,777,447 B) with `flash.cdf` = `ActionCode(Cfg) Device PartName(A5EB013BB23BE4SR1) … File("golden_top.jic") … SEC_Device(MT25QU128)` **[V RP-A, read directly]**. Programming one **erases the HPS-first factory image — SPL and all** — so SD Linux boot is dead until the *GSG* restore is run at a bench. This is a **vendor-sanctioned, user-facing QSPI write path entirely outside our control** | user docs: the only QSPI rule is "never run any demo `flash_program.bat`"; our recovery page carries the *GSG* restore recipe and the per-revision factory JIC hash so support can walk a user back |
| 14 | **Recovery or bench flash with the wrong board revision's or wrong OPN's JIC** | Programming succeeds (JTAG validates little beyond the die) but the DDR/pinmux handoff inside the bitstream is wrong for the board → no boot or subtly wrong DDR, **and the original factory image is now gone**. The recovery attempt manufactures row 7's state. Terasic ships revA and revB packages separately; *UM* prints OPN `…SR1` while the BSP record says `…SCS` (§3) | archive both revisions with hashes, keyed to device + board revision; read the OPN over JTAG (Quartus auto-detect) and the revision off the PCB before any write; forbid "any Agilex 5 JIC" substitution. Desk follow-up: diff the revA/revB GHRD projects |
| 15 | **Shipping a phase-2 `core.rbf` from our own Quartus compilation against the factory phase-1 resident in QSPI** | Altera doctrine for split (HPS-first) configuration is that periphery and core images come from the **same** Quartus compilation. If that holds here, every boot-time fabric design we ship is pinned to Terasic's exact factory compile — a **project-shaping constraint on the whole core-switching model**, and a strand-at-U-Boot failure when violated. **[U]** — consistently reported across Altera-derived sources but the authoritative UG (813773) is 403-blocked | D0.2/D2.2: (a) test a self-recompiled GHRD `core.rbf` against the untouched factory QSPI; (b) test whether runtime `COMMAND_RECONFIG` full reconfiguration is compilation-independent — that decides whether core switching routes through U-Boot phase-2 at all or must be Linux-runtime-only. Until answered, treat boot-time phase-2 as pinned to the factory compilation |
| 16 | **Running `flash_erase.bat` (or `flash_program.bat`, which erases) as the first act of a D2.2 bench session** | The factory content — never dumped, never compared — is destroyed first; if the published JIC then fails to boot this board, no known-good image has ever existed for it | the §6 ordering rule, written into the D2.2 task *before* hardware arrives: verify-only → readback/archive → only then write |

## 8. Resolved questions (D0.1 close-out)

**Provenance note.** Six research legs were run, one per question. **Q4 and Q6 returned
placeholder content** ("test", claim text `a`, source `b`) and were **discarded in full**; the
answers below for those two are sourced independently. One Q5 citation
(`stratix10-svc.c:172-191` for `COMMAND_RECONFIG`) **does not hold** — that range is
`svc_pa_to_va()` in our tree; corrected line numbers are used above and re-verified this pass.
One Q5 source (an Intel PDF cited with section numbers 14.3.3.3–14.3.3.5 under a document number
that does not match that title) **could not be re-retrieved** (403); its section and page numbers
are **dropped**, not repeated, and the claim they supported is carried as [U].

### 8.1 Q1 — Can the SDM boot from SD/MMC on this board? — **RESOLVED: no [V]**

Board-gated, not merely undocumented. Three independent facts close it:

- *UM* Table 3-23 names the microSD socket's HPS-side signals `HPS_SD_CLK`, `HPS_SD_CMD`,
  `HPS_SD_DATA[0..3]` — HPS peripheral pins, the same class as `HPS_USB_*` / `HPS_UART_*`,
  **not** SDM_IO configuration pins **[V UM, text re-extracted 2026-08-21]**.
- *UM* Table 3-2 lists exactly two MSEL schemes (`001` AS Fast, `111` JTAG); SW5 wires only
  MSEL0–2 **[V UM]**. No strap selects an SD/MMC scheme.
- *UM* §3.8.4 — *"It serves not only as an external storage for the HPS but also as an
  alternative boot option for the DE25-Nano board."* — is the FSBL-reads-SD step (§2 step 4), not
  a second SDM path **[V UM]**. *RB-boot*'s own "boot from SD card" example sets MSEL to **JTAG**,
  never to an SD value **[V RB-boot]**. Corroborating at the artifact level: the factory SPL's
  `u-boot,spl-boot-order` starts at `/soc/mmc0@10808000` — the *HPS* MMC controller, reached only
  after the SDM has already configured the device from QSPI **[V SPL-dtb:429]**.

Residual [U], non-blocking: whether Agilex 5 *silicon* has an SD/MMC configuration scheme at all
(813773's body is 403-blocked; only its TOC was readable, showing AVST/AS/JTAG/CvP), and whether
the `HPS_SD_*` pins are mux-capable to SDM_IO at the device level (would need the board's
pin-planner file or Terasic confirmation). **Neither changes the answer**, because Table 3-2
offers no strap to select such a scheme even if it exists.

Optional hardening question for Terasic: *"Does the microSD socket connect only to the HPS
SD/MMC peripheral (Table 3-23), or is it also routed to SDM_IO? Is there any MSEL/SW5 value
beyond 001/111?"*

### 8.2 Q2 — Factory QSPI contents — **LARGELY RESOLVED [V]; parked only on the dump.**

*(Substantially upgraded by the refutation pass, which opened the published archive that the
research legs had only read the index of.)*

- The branded "System CD" is no longer a separate download — `de25-nano.terasic.com/cd/` 302s to
  the resource page **[V]** — but the **name survives in Terasic's own current documentation**,
  and the **Resource Package is what it now denotes** (*GSG*'s restore path begins `System CD\`)
  **[V GSG]**. Downloads are: User Manual (revA/revB), **Resource Packages** revA/revB v1.0.0,
  and a **Linux Console microSD BSP** v1.1 **[V `dl2.terasic.com/resources/de25-nano/` index]**.
- **The factory QSPI image *is* published**: `golden_top_hps.jic`, 16,777,447 B, sha256
  `e3d20c2d066761fd02897422ba361aa19faafcd0240dd2782965754cc61b38a4`, in
  *RP-A* `Demonstration/SoC_FPGA/GHRD/output_files/` **[V, re-hashed locally this pass]**, with
  `golden_top_hps.sof` (1,474,367 B) and `program_qspi_flash/{flash_program,flash_erase}.bat`
  beside it. *GSG* names this tree as "the factory code" **[V]**.
- The BSP's description block gives its build record verbatim: device `A5EB013BB23BE4SCS`,
  Quartus **25.1.1 Pro**, ATF branch **2.12.0**, U-Boot branch **2025.01**, kernel
  **6.12.11-lts**, Ubuntu 22.04.3 **[V T-res]** — the **SD-side** record; no QSPI/factory build
  record is itemised on the page **[V, absence observed]**.
- **FSBL identity: U-Boot SPL [V, now vendor-sourced]** — *RP-A* ships
  `…/GHRD/software/u-boot/spl/u-boot-spl-dtb.hex` (721,613 B); the DTB carved from it declares
  `model = "SoCFPGA Agilex5 Terasic DE25-Nano"` **[V SPL-dtb]**. *T-guide*'s account of the
  build (embed the hex into the GHRD Quartus project, `sof_with_hps` → `sof_to_jic`; BL31 into
  `u-boot.itb`; Terasic forks tagged `de25_nano_revA_v1.0`) is now corroborated by the artifacts
  rather than resting on a community page **[V for the artifacts; U for the process narrative]**.
- Whether the Resource Package contains the GHRD project — the first pass's open [U] — is
  **resolved yes**: `Demonstration/SoC_FPGA/GHRD/` with `output_files/` and `software/u-boot/`
  **[V, archive listed]**.

**PARKED — blocker:** *no readback/dump procedure for SDM-mediated QSPI is documented by
Terasic* (its scripts are write-side only) — so we can hash the **published** image but not yet
a **board's** image. Two candidate closures, both in §5, both **inheriting D2.2**:
`quartus_pgm` verify-only against the published JIC, or an HPS-side MTD read from a QSPI-enabled
DTB (weighing §7 row 10 first).

### 8.3 Q3 — Will the factory SPL boot a mainline-built `u-boot.itb`? — **PARKED on hardware; structure resolved [V], and two of three blockers closed at the desk.**

Structure, mainline-defined **[V, `u-boot:` at `master`, re-fetched 2026-08-21]**:
`configs/socfpga_agilex5_defconfig` sets `CONFIG_SPL_LOAD_FIT=y`,
`CONFIG_SPL_LOAD_FIT_ADDRESS=0x82000000`, `CONFIG_SPL_FS_FAT=y`, `CONFIG_SPL_ATF=y`,
`CONFIG_SPL_ATF_NO_PLATFORM_PARAM=y`, `CONFIG_ENV_IS_IN_FAT=y`,
`CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"`, **`CONFIG_SPL_FIT_SIGNATURE=y`**, and also
`CONFIG_CMD_MTD=y` / `CONFIG_CMD_UBI=y` (§7 row 11). `common/spl/Kconfig` defaults
`SPL_FS_LOAD_PAYLOAD_NAME` to `"u-boot.itb"` whenever `SPL_LOAD_FIT=y`, and
`SYS_MMCSD_FS_BOOT_PARTITION` to 1. `arch/arm/mach-socfpga/spl_soc64.c` gives `spl_boot_device()`
→ `BOOT_DEVICE_MMC1`, `board_boot_order()` reading `/chosen`'s `u-boot,spl-boot-order`, and
`spl_boot_mode()` → `MMCSD_MODE_FS`.

Blocker status:
1. Whether Terasic's SPL was built from mainline or their fork (BSP record: U-Boot **2025.01**),
   and **whether its DTB carries required signature keys** — **closed at the desk for the
   published build: it does not** (no `/signature` node, no keys, *SPL-dtb*) **[V]**. Residual:
   published build vs factory-programmed flash **[U → D2.2]**.
2. The `u-boot,spl-boot-order` baked into their handoff DT — **closed [V]**:
   `"/soc/mmc0@10808000", "/soc/spi@108d2000/flash@0", "/soc/nand@10b80000", "/memory"`
   (*SPL-dtb*:429), with the QSPI node itself `status = "disabled"` in that DTB (*SPL-dtb*:225).
3. `board_fit_config_name_match()` for socfpga/agilex5 (multi-config-node selection): still not
   located — `board/socfpga/socfpga.c` 404'd over the web. **[U]** — a desk loose end, resolvable
   by reading a local U-Boot checkout rather than fetching files one at a time.

**Inherits: D2.2** (the actual boot test, plus blocker 1's residual), and a trivial desk
follow-up for blocker 3.

### 8.4 Q4 — Does RSU fit in 16 MB? — **RESOLVED to the decision-relevant answer: not at reference sizing [V]. Impossibility NOT established; residual parked.**

*(Leg output discarded as placeholder; sourced independently.)* Altera's rel-25.1 **HPS Remote
System Update example for Agilex 5 E-series** is built on a **2 Gbit (256 MB)** QSPI
(`QSPI02G`), with a ~**7 MB** factory image and **three 16 MB** application slots, plus
BOOT_INFO / SPT0-1 / CPB0-1 overhead **[V RSU-ex]**. The DE25-Nano has **16 MB total**, already
occupied by the factory phase-1 image. A single reference application slot is the whole device.

*Honesty about what this source is:* the page was read through a fetch summariser and the offset
column it returned is internally inconsistent (SPT0 at `0x910000` sits outside the stated 2.1 MB
BOOT_INFO region). **The offsets are not relied on** — only device size, factory-image size and
per-slot size, which are mutually consistent and decisive on their own.

**PARKED — residual blocker, and the refutation pass sharpened it in the direction of *doubt*:**
the reference sizes are an example's choices, not documented minima; RSU layouts are user-authored
via `quartus_pfg`; and the phase-1 payload is now measured — `golden_top_hps.sof` is 1,474,367 B
and the JIC's non-`0xFF` content is 2.87 MiB **[V, measured 2026-08-21]** — which makes
"factory + one small application slot inside 16 MB" arithmetically plausible. Named missing
inputs: (a) **Intel 852610** (Agilex 5 quad-SPI flash layout), the document where minima would
live — **403-blocked**; (b) confirmation that a JIC's non-`0xFF` extent is a fair proxy for its
programmed size. **Inherits: a follow-on desk task or D2.1. Until it lands, §6's conclusion
("nothing we ship writes QSPI") stands as policy and §7 rows 1/8 are the operative guards — but
it must not be written into the DP-1 ADR as a proven impossibility (§9.2).**

### 8.5 Q5 — U-Boot environment location and the warm-reboot story — **Env: RESOLVED [V], and it is §7 rows 5/11/12. Warm reboot: PARKED [U].**

**Environment.** Mainline `socfpga_agilex5_defconfig` compiles in **two** env locations:
`CONFIG_ENV_IS_IN_FAT=y` (`ENV_FAT_DEVICE_AND_PART="0:1"`) **and** `CONFIG_ENV_IS_IN_UBI=y`
(`ENV_UBI_PART="root"`, `ENV_UBI_VOLUME="env"`), with `ENV_SIZE=0x2000`; there is no
`ENV_IS_IN_MMC` and no `ENV_IS_IN_SPI_FLASH` **[V, defconfig re-fetched and re-read 2026-08-21]**.
Precedence is observable in *RB-boot*'s own boot log: `Loading Environment from FAT... Unable to
read "uboot.env" from mmc0:1...` then `Loading Environment from UBI...` → `Select Environment on
UBI: OK` **[V RB-boot]** — FAT first, UBI as fallback, and on a QSPI-boot posture that UBI volume
lives **in QSPI**.

The hazard is in `env_save()`, not the defconfig: `env_load()` records `gd->env_load_prio` for
the driver that **succeeded**, and `env_save()` does
`env_driver_lookup(ENVOP_SAVE, gd->env_load_prio)` — **`saveenv` writes back to wherever the
environment was read from** (*u-boot:env/env.c*) **[V]**. FAT env present → saves to FAT (safe).
FAT env absent **and** a UBI `env` volume reachable → **`saveenv` writes QSPI**. Both fail →
`best_prio = 0`, the highest-priority driver.

- In our posture-1 SD flow the *intent* is FAT-only, and whether the factory QSPI even contains a
  UBI volume named `env` is **[U → D2.2]**. The defence must not depend on that: build with
  **`CONFIG_ENV_IS_IN_UBI=n`** and ship a valid `uboot.env`, so the dangerous branch is
  unreachable by construction. **§7 row 5** — and see rows 11 and 12 for the two paths that
  `ENV_IS_IN_UBI=n` alone does **not** close.
- Which of `fat`/`ubi` is priority 0 is set by linker-list ordering, not by `env/Makefile` order;
  *RB-boot*'s log shows FAT first in practice **[V empirically / U as a read-the-linker-script
  claim]**.

**Warm reboot / core preload — PARKED.** No SDM-mailbox or DDR-resident-flag mechanism analogous
to the DE10's Main_MiSTer ⇄ U-Boot mailbox at `0x1FFFF000`
([`boot-chain.md`](boot-chain.md) §6) is documented in any source we opened (*GHRD*, *RB-boot*,
*UM*, *GSG*) — an **absence observed**, not a documented negative **[U]**. What is positively
established: deliberate runtime fabric reconfiguration on this family is an explicit mailbox
request through `stratix10-svc`/`stratix10-soc`
(`linux:drivers/fpga/stratix10-soc.c:195`) **[V]** — Linux-mediated, not a U-Boot
`fpgacheck`-style dispatcher — **and it does not probe at all on mainline Agilex 5 DTs** (§2 step
6) **[V]**. The first-pass leg's claim that an HPS warm reset leaves fabric configuration
untouched is carried **[U]**: the document it cited could not be re-retrieved (403) and its
identification was internally inconsistent, so its section/page numbers are dropped rather than
repeated. **Blocker:** Agilex 5 boot/reset documentation (813762/813763, 814346, 786901) is
403-blocked on every mirror tried. **Inherits: D2.2** — trigger an HPS warm reset and observe
whether the fabric image survives; on the same run, confirm which env location our build loads
from and saves to.

### 8.6 Q6 — DDR-handoff coupling: how tightly does posture 1 pin us to Terasic? — **RESOLVED at the structural level [V]; magnitude parked.**

*(Leg output discarded as placeholder; sourced independently.)* **All of it is QSPI-side.**
*RB-boot* states it plainly for this family: *"For Agilex 5, all the handoff information created
by the Quartus compilation is part of the configuration bitstream. The bsp-editor is not used,
and the bootloader build flow does not depend on the Quartus outputs."* **[V RB-boot]**. Two
consequences pull in opposite directions and both matter:

- **Good:** our bootloader build needs **no** Quartus handoff artefacts — no DE10-style
  `qts-filter`/handoff-header step, nothing to keep in sync per board revision. The DE10's
  "SPL carries QTS handoff headers" model does **not** transfer
  ([`boot-chain.md`](boot-chain.md) §1).
- **Binding:** DDR and pinmux configuration is **not ours to change** under posture 1. We inherit
  Terasic's memory timings, pin assignments and HPS-first handoff exactly as compiled into the
  factory JIC. Any change is a posture-2 bitstream rebuild + bench flash (§4, §7 row 9). The same
  coupling is what makes §7 rows 14 and 15 dangerous.

**PARKED — residual:** the *magnitude* of what is inherited (which specific DDR parameters,
whether rev A and rev B differ in it, whether a rev-B board's factory bitstream would mis-handoff
to a rev-A-built payload) is **[U]**. Named missing input: a diff of the two revisions' GHRD
projects — **now desk-obtainable, since both Resource Packages are downloadable and revA is
already in hand**. **Inherits: D2.1/D2.2**, and it is a live argument for recording board revision
in every DE25 release's test matrix (§5) *and* in the recovery kit (§7 row 14).

### 8.7 Accept criterion for D0.1 — **met**

The criterion was: every §8 question either resolved to **[V]** or explicitly parked with a
**named blocker** and a **named inheriting task**. Status:

| Q | Outcome | Blocker if parked | Inherits |
|---|---|---|---|
| Q1 SDM-from-SD | **RESOLVED [V]** — no | (silicon-level residual, non-blocking) | — |
| Q2 factory QSPI | **RESOLVED [V]** for contents + published image hash; **PARKED** for a board's own image | no vendor-documented readback procedure | D2.2 (verify-only, then readback) |
| Q3 SPL accepts our FIT | **PARKED** (structure [V]; blockers 1–2 closed at desk) | needs the real board; `board_fit_config_name_match()` unread | D2.2 + trivial desk follow-up |
| Q4 RSU in 16 MB | **RESOLVED [V]** at reference sizing; **PARKED** on impossibility | Intel 852610 (403); JIC-extent proxy unvalidated | desk task / D2.1 |
| Q5 env location | **RESOLVED [V]**; warm-reboot **PARKED** | 813762/813763, 814346, 786901 all 403 | D2.2 |
| Q6 DDR coupling | **RESOLVED [V]** structurally; magnitude **PARKED** | revA/revB GHRD diff not yet done (desk-obtainable) | D2.1/D2.2 |

Every hardware-gated item is handed to **D2.2**, and D2.2 now inherits an explicit ordering rule
(§6) so that its first QSPI-touching act cannot be destructive.

## 9. Refutation record

### 9.1 What ran

An adversarial refutation pass ran **2026-08-21** against the §5–§7 claim set (21 claims), with
three independent lenses:

1. **Mechanism** — is the described Agilex 5 / DE25 hardware-firmware behaviour real; is JTAG
   recovery genuinely sufficient in every listed failure mode; is "no RSU / JTAG-only recovery"
   stated at the right strength. Re-derived every claim from primary sources where reachable.
2. **Guards** — for each claim, does the named guard exist *today*, is it mechanically enforced
   or merely written intention, and can a well-meaning contributor bypass it unnoticed. Read the
   named flash scripts end-to-end and grepped the tree for any board-identity assertion.
3. **Severity/completeness** — is each consequence over- or under-stated, and what is missing
   from the inventory entirely.

Two of the three lenses **downloaded and opened the published Terasic Resource Package** — which
no research leg had done, and which is where several first-pass "nothing is published" claims
died. Adjudication rule applied here: **AMEND** = a majority of refuters refuted it → rewritten
to the corrected form; **OPEN CONCERN** = exactly one refuter objected → the claim is kept and
the objection recorded in-line, naming the lens; **STANDS** = left alone.

### 9.2 Amended (majority-refuted, rewritten above)

| Claim | What changed |
|---|---|
| §5 no-System-CD | "No System CD exists to cite a revision of" → **the name survives in Terasic's own *GSG*/*UM* and denotes the Resource Package**; record the package version as the CD-revision analogue |
| §5 no-QSPI-hash | "No `.jic` published; a hash is unobtainable" → **the factory JIC is published and hashed** (`golden_top_hps.jic`, sha256 `e3d20c2d…`). Only a *board's* image remains unhashed; HPS-side MTD readback added as a second candidate route |
| §5 four-term-contract | Term 1 cited the wrong Kconfig symbol: `ENV_FAT_DEVICE_AND_PART` is the **environment file's** location; the SPL payload partition is **`SYS_MMCSD_FS_BOOT_PARTITION`** (default 1). Corrected, with the env location split out as a separate fifth term |
| §6 RSU-kernel-side-exists | Line range corrected (`stratix10-svc-client.h:153-159`, not `:152-156`) and the framing fixed: RSU also needs an **RSU-formatted flash layout** and a **DT node mainline Agilex 5 does not ship** — not "geometry only" |
| §6 unbrickable-conditional | "You must have an image and Terasic publishes none" → **the image is published and the restore is documented (*GSG*)**; the real conditions are a Quartus PC, the right board revision, and an archive against link-rot |
| §7 row 3 | "Worst case hits QSPI-adjacent state" had **no mechanism** — `mmcblk*` and the QSPI controller are physically separate. Row is now **strand-class**, with the env-tooling leg named as the actual QSPI-reaching path |
| §7 row 7 | Premise false (see no-QSPI-hash); rewritten around link-rot, wrong-revision substitution, and untested bootability |
| §7 row 8 | "No power-loss-safe framework fits 16 MB" [V] → **"none is demonstrated or documented"**; the guard is kept as **policy**, not as a consequence of a proven impossibility |
| §4 posture-1-forced | "Close to forced" → **chosen fail-closed**, with a recorded revisit trigger; the signature risk that would have forced it now tests negative on the published SPL |

**Citation defects found and fixed** (house rule 1 is load-bearing, so these are logged):
`stratix10-svc.c:172-191` for `COMMAND_RECONFIG` — wrong, that range is `svc_pa_to_va()`;
`stratix10-svc-client.h:152-156` for `COMMAND_RSU_*` — wrong, the enum entries are `:153-159`;
`stratix10-soc.c:186-196` — the actual `COMMAND_RECONFIG` send is `:195`. All three re-checked
against `/mnt/source/Buildroot_MiSTer/output/build/linux-6.18.44` by this pass.

### 9.3 Open concerns (single-refuter objections — kept, not dropped)

| Claim | Lens | Objection, recorded verbatim in substance |
|---|---|---|
| §5 no-release-writes-QSPI | Guards | The rule exists; **the guard does not, except as sentences.** No shipped script reads `/proc/device-tree/compatible`; ADR 0027 Decision 4, `de25-nano-tasks.md` and `downloader-contract.md` are all prose; no CI check pins a future DE25 U-Boot to `ENV_IS_IN_UBI=n`. Tag it [V] only after (a) the identity assertion exists as code and (b) a release-blocking CI check exists. **Carried in §5, final bullet.** |
| §7 row 2 | Guards | Consequence overstated (**strand-class**, card-recoverable, since QSPI is untouched) and the "per-release factory-QSPI test matrix" exists nowhere. **Carried in the row.** |
| §7 row 4 | Guards | "Switches stay at default" appears in **no user-facing doc**; `docs/user/` has zero DE25/MSEL content. It is a task, not a guard. **Carried in the row.** |
| §7 row 6 | Severity | Antecedent is desk-testable and tests **negative**: the published SPL's DTB has no signature keys, so this drops from posture-1 killer to a first-contact check. **Carried in the row** (this pass independently re-inspected the DTS and agrees). |

### 9.4 Stood unchallenged by every lens

§5 seam-exists; §5 DDR-not-ours; §6 RSU-does-not-fit (at reference sizing); §6 RSU-residual;
§7 rows 1, 5, 5-residual, 9; §2/§3 FSBL-is-SPL.

### 9.5 What has *not* been challenged, and by whom

A reader must be able to tell survival from silence. **Not covered by any lens this pass:**

- **§1–§3 and §8 as prose.** The refutation targeted the §5–§7 claim set. §2's step list, §3's
  table and §8's parked-question wording were re-derived by this synthesis, not attacked.
- **The new §7 rows 10–16.** They are the refuters' own missing-vector findings, so nothing has
  refuted *them*. Rows 10, 13, 14, 16 rest on artifacts this pass re-verified directly; **row 12's
  UBI auto-format mechanism is explicitly [U]** and row 15's same-compilation doctrine is **[U]**
  on a 403-blocked UG. Treat both as hypotheses with named tests, not findings.
- **Everything Terasic-page-sourced during the mechanism lens.** `terasic.com.tw` was
  TLS-unreachable from the refuting environment, so *T-res* claims **stand unchallenged rather
  than re-proven**; the `dl2.terasic.com` index and the archive contents *were* independently
  verified.
- **Every Intel-document claim.** 813762, 813763, 813773 (body), 814346, 786901, 852610 — all
  403 on every attempt across both passes. Nothing in this document quotes them.
- **Everything on hardware.** No board has been touched. Every [V] here is a document, a source
  file, or a vendor artifact — none is a measurement.

## 10. Corrections owed to sibling documents

- [`de25-nano-plan.md`](de25-nano-plan.md) §1 lists **ATF BL2 as the FSBL**; it is **U-Boot SPL**
  (§2 step 2, §8.2) **[V]**.
- [`de25-nano-plan.md`](de25-nano-plan.md) §6's DP-3 caveat stands and hardens: boot-firmware
  recovery is bench-only and needs a PC — but it is *not* blocked on an unobtainable image (§6).
- The DP-1 ADR (D2.7) must record posture 1 as **chosen fail-closed**, with "a proven sub-16 MB
  RSU layout" as its explicit revisit trigger — **not** as forced by impossibility (§4, §9.2).
- ADR 0027 Decision 4's board-identity assertion needs an implementation task with a release-block
  attached, not another restatement (§5, §9.3).
