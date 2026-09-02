# DE25-Nano FPGA reconfiguration and the HPS↔FPGA memory contract

**Status:** desk research, 2026-08-21 — **no hardware touched**, nothing built, nothing
measured. This is the D0.2 deliverable ([`de25-nano-tasks.md`](de25-nano-tasks.md)), and it
has been through D0.2's adversarial refuter pass (§10). The DP-9 verdict (§8) and the
UX conclusion (§1) survived that pass; both were amended by it, and every number in §6 is
superseded the day D2.5 measures one. Claims are tagged **[V]** (verified against a named
source) / **[U]** (unverified, with the missing thing named). Cross-refs:
[`de25-nano-plan.md`](de25-nano-plan.md) §1, §6 (DP-9, DP-10), §7;
[`de25-boot-chain.md`](de25-boot-chain.md) §2 step 5 and §5;
[ADR 0027](decisions/0027-de25-nano-multi-board-readiness.md); and — for the DE10 baseline
contrasted against throughout — the carried patch series in
`board/mister/de10nano/linux-patches{,-beta}/`.

**Sources:**

- Mainline **Linux 6.18.44**, the tree this repo builds: `output/build/linux-6.18.44`.
  Cited as bare `file:line`. Every kernel line number below was opened and read on
  2026-08-21, including a re-verification pass after the refutation (§10). This is the
  authoritative source in this document — the only one that could be read in full.
- Carried DE10 patches: `board/mister/de10nano/linux-patches-beta/0043-dts-uio-doorbells.patch`,
  `0044-dts-uio-fpga-regions.patch`, `0045-uio-writecombine.patch`, and
  `linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch`.
- Terasic **DE25-Nano User Manual**, rev. 2025-09-05, 51 pp. — *UM*. **Read in full this
  session**: the DigiKey mirror `mm.digikey.com/Volume0/opasdata/d220001/medias/docus/7704/P0804.pdf`
  was fetched and text-extracted on 2026-08-21, so *UM* citations here are read-document
  citations, not snippets. Cited by section and by extracted quote.
- **Upstream Agilex-5 FPGA-manager series**, Khairul Anuar Romli (Altera), Nov 2025 —
  *A5-series*. Read on 2026-08-21 via the `lkml.iu.edu` hypermail mirror:
  `2511.1/03492.html` (driver, 2025-11-11), `2511.1/05879.html` (binding v3, 2025-11-14),
  `2511.1/05877.html` (DTS v3, 2025-11-14). Respun through v6 (2025-11-19). **Not in
  6.18.44.**
- Altera **Agilex 5 E-series GHRD Linux boot examples** (`altera-fpga.github.io`, rel-24.2
  / rel-25.1 as cited in [`de25-boot-chain.md`](de25-boot-chain.md)), retrieved
  2026-08-21 — *GHRD*.
- RocketBoards **Agilex 7 Configuring FPGA Fabric From Linux**, retrieved 2026-08-21 —
  *RB-A7*. Agilex **7**, not 5; used only where labelled as analogy.
- community.altera.com thread **312795** "Agilex 5 – HPS first – u-boot stuck if
  rebooting" (AXE5-Eagle) — *AXE5*. Direct fetch 403s; the log figures come from the
  draft's Wayback snapshot `20260215052804`, and the thread's **subject and resolution**
  were independently corroborated by search on 2026-08-21 (§6.1 row 4a).
- community.altera.com thread **314152** "Agilex 5 – configure FPGA from running linux via
  dt-overlay" (marked Solved) — *A5-overlay*. Direct fetch and the community.intel.com
  mirror both 403 on 2026-08-21; **search-snippet grade only**, tagged accordingly.
- Intel docs **683673** (Agilex Configuration UG), **813918** (Agilex 5 datasheet),
  **814346/813752** (Agilex 5 HPS TRM), **762191** (device security): **not read.**
  intel.com and docs.altera.com returned HTTP 403 or JS-only shells to every fetch
  attempted on 2026-08-21. Anything attributed to them here is search-snippet paraphrase
  and is tagged **[U]** on that ground alone, regardless of how plausible it reads.

---

## 1. The headline answer

**The mechanism is sound and is reported working on Agilex 5 silicon; the latency is
unmeasured; the authentication question is open and could be fatal; and there is dated
on-silicon evidence that *repeated* configuration is where this breaks
[V mechanism / U latency / U auth / U repeat].**

Reconfiguration on Agilex 5 is not a variant of the DE10's approach — it is a different
architecture. There is no memory-mapped FPGA manager for Main_MiSTer to write. The kernel
hands the bitstream to EL3 firmware over SMC, and the SDM writes the fabric; Linux never
parses the `.rbf` **[V, §2]**. For this manager, the only entry point to that path from
outside a kernel driver is applying a device-tree overlay **[V, §2.6]**.

Four things stand between that and a working core switch, in descending order of how much
they could hurt:

1. **VAB / bitstream authentication.** If Terasic's factory QSPI ships with authentication
   keys provisioned, the SDM will reject unsigned community bitstreams and MiSTer-style
   core switching does not exist on this board until a signing story is built. Nothing
   reachable this session settles this **[U, §5.2]** — the *UM*, now read in full, is
   completely silent on VAB, signing, authentication, QKY and efuses **[V, §5.2]**, which
   is weak evidence for a permissive default and no more. It is cheap to settle on
   hardware and expensive to be wrong about before buying hardware.
2. **Repeated reconfiguration.** MiSTer switches cores dozens of times a session. The one
   dated on-Agilex-5-silicon report in evidence is a thread whose *subject* is the system
   hanging when the fabric is configured a second time, with the LWH2F bridge implicated,
   described in-thread as a silicon issue with no fix and a `bridge enable 0x3b`
   workaround that skips the F2H bridge **[U, search-corroborated 2026-08-21, §6.1]**.
   That report is U-Boot-context, not the Linux overlay path, so it is not dispositive —
   but it is the opposite of an absence of evidence, and it promotes "does the region
   accept a second overlay cleanly" from an unmeasured curiosity to the first thing D2.5
   should try.
3. **Agilex 5 is absent from *this* kernel — but not from upstream.** 6.18.44 has no `svc`,
   `fpga-mgr` or `fpga-region` node in `socfpga_agilex5.dtsi` and no Agilex-5 compatible
   string anywhere in the stack **[V, §3.1]**. An Altera-authored series adding
   `intel,agilex5-soc-fpga-mgr` **with `intel,agilex-soc-fpga-mgr` as its declared DT
   fallback** was posted in Nov 2025 and reviewed by the FPGA maintainer **[V *A5-series*]**.
   That is the vendor asserting gen1 command-compatibility, and it means a DE25 board DTS
   written today against the unmodified 6.18.44 driver has a supported path (§3.1).
4. **There is no overlay loader in mainline.** The
   `/sys/kernel/config/device-tree/overlays/` workflow every vendor document and every
   working community report describes is `CONFIG_OF_CONFIGFS`, an out-of-tree patch that
   does not exist in 6.18.44 **[V absence / U provenance, §3.2]**. The DE25 needs its own
   plumbing here, exactly as the DE10 needed its own UIO wiring.

**UX viability.** MiSTer-style core switching is UX-viable on Agilex 5 at
**low-to-moderate confidence, on desk research only**, and the honest statement of *what*
is viable is narrower than "the user won't notice":

- The user **will** perceive every core switch. HDMI on this board is an ADV7513 wired to
  FPGA fabric pins with an FPGA-side I2C control bus **[V *UM* §3.7.3]**, so a full
  reconfiguration blanks the display until the new core reinitializes the transmitter and
  the monitor re-syncs. The supportable claim is **parity with the DE10**, where video is
  equally fabric-owned and a switch already blanks the screen — not imperceptibility. The
  DE10 baseline itself ("a few seconds") is **[U]**, unmeasured by anyone, and must be
  measured as D2.5's control before any comparison is quoted.
- What *does* hold is that the reconfiguration transaction is unlikely to be the dominant
  term. The kernel does no parsing or validation work proportional to core complexity — it
  copies a byte stream through four 512 KiB buffers **[V §2.4]** — so per-core kernel cost
  scales only with bitstream size at memcpy speed.
- Input survives the switch. The USB 2.0 OTG port is an **HPS** peripheral: a ULPI PHY
  driven by the USB 2.0 controller in the HPS **[V *UM* §3.8.5]**, so controllers and their
  HPS-side drivers are untouched by reconfiguration, exactly as on the DE10.
- Latency: nothing found measures it. The driver's timeouts (300 ms / 720 ms / a
  caller-supplied ceiling) are ceilings, not durations **[V, §2.4]**. The honest estimate
  for the reconfiguration transaction proper is **~10 ms to ~1 s**, with a real and
  in-evidence mechanism for a multi-second tail (§6.2), and the largest unmeasured risk is
  the *overlay* apply/remove cost — dynamic node creation and driver bind/unbind — not the
  SDM's fabric write.

## 2. The reconfiguration path, end to end

Follow a bitstream from the SD card to configured fabric. Every step is in this tree.

### 2.1 The file on disk

`request_firmware()` searches, in order: the runtime-settable `firmware_class.path`
parameter, `/lib/firmware/updates/<release>`, `/lib/firmware/updates`,
`/lib/firmware/<release>`, `/lib/firmware`
**[V `drivers/base/firmware_loader/main.c:471-483`]**. The parameter is
`module_param_string(path, …, 0644)`, i.e. writable at runtime through
`/sys/module/firmware_class/parameters/path` **[V same file :485]** — so cores can live on
`/media/fat` and be pointed at, rather than copied into the rootfs. That matters for a
board whose rootfs is reflashed wholesale (memory: persistent state lives on `/media/fat`).

### 2.2 The userspace call

Userspace applies a device-tree overlay whose fragment targets the `fpga-region` node and
carries `firmware-name`. `of-fpga-region.c` reads these properties off the overlay:

| Overlay property | Effect | Source |
|---|---|---|
| `firmware-name` | the `.rbf` to `request_firmware()` | `of-fpga-region.c:232-238` |
| `partial-fpga-config` | sets `FPGA_MGR_PARTIAL_RECONFIG` | `:223-224` |
| `external-fpga-config` | sets `FPGA_MGR_EXTERNAL_CONFIG` (already configured; skip) | `:226-227` |
| `encrypted-fpga-config` | sets `FPGA_MGR_ENCRYPTED_BITSTREAM` — **ignored by the Stratix10/Agilex manager** | `:229-230`; `stratix10-soc.c:186-193` |
| `config-complete-timeout-us` | the completion-poll ceiling; **effectively mandatory**, see §4.3 | `:246-247` |
| `region-{freeze,unfreeze}-timeout-us` | bridge timeouts; inert with no bridges | `:240-244` |

**[V all six rows.]** An overlay that adds a *child* region carrying `firmware-name` is
rejected outright **[V `:207-214`, `:162-172`]**, and a region that already has an overlay
applied rejects a second one with "Region already has overlay applied."
**[V `:203`, `:301`]**.

### 2.3 Overlay apply → program

`of-fpga-region.c` registers an overlay notifier at module init
**[V `:455`]**. The notifier acts on `OF_OVERLAY_PRE_APPLY` and `OF_OVERLAY_POST_REMOVE`
and explicitly ignores everything else **[V `:353-363`, `:375-379`]**. On `PRE_APPLY` it
builds the image info and calls `fpga_region_program_fpga()` **[V `:306`]**, which:

1. takes the region and locks the manager **[V `drivers/fpga/fpga-region.c:97-114`]**;
2. calls `fpga_bridges_disable()` — **a no-op when the bridge list is empty**, which it is
   on Agilex **[V `fpga-region.c:127`; `drivers/fpga/fpga-bridge.c:190-203` is a bare
   `list_for_each_entry`]**;
3. calls `fpga_mgr_load()` **[V `fpga-region.c:133`]**;
4. calls `fpga_bridges_enable()`, likewise a no-op **[V `fpga-region.c:139`;
   `fpga-bridge.c:166-181`]**.

### 2.4 Manager → SDM

`fpga_mgr_load()` dispatches on how the image was supplied; with a `firmware_name` it goes
to `fpga_mgr_firmware_load()` **[V `drivers/fpga/fpga-mgr.c:572-582`]**, which
`request_firmware()`s the whole file into kernel memory **[V `:536-548`]** and loads it.
Because `stratix10-soc.c` implements `.write` **[V `:394`]**, the fast path applies and the
buffer is passed straight through — no scatter-gather conversion
**[V `fpga-mgr.c:50-51`, `:480`]**. Then, in `drivers/fpga/stratix10-soc.c`:

| Step | What it does | Timeout | Line |
|---|---|---|---|
| `write_init` | `COMMAND_RECONFIG` (+ `COMMAND_RECONFIG_FLAG_PARTIAL` if asked); on OK, allocates **4 × 512 KiB** service-layer buffers | 300 ms | `:175-230`; sizes `:19-20`; alloc `:215-216`; timeout `include/linux/firmware/intel/stratix10-svc-client.h:68` |
| `write` | producer loop: fill a free buffer, `COMMAND_RECONFIG_DATA_SUBMIT`, reclaim via `COMMAND_RECONFIG_DATA_CLAIM` | 720 ms per buffer | `:250-262`, `:278-346`; timeout `stratix10-svc-client.h:69` |
| `write_complete` | poll `COMMAND_RECONFIG_STATUS` until `SVC_STATUS_COMPLETED` / `SVC_STATUS_ERROR` | caller-supplied (`config-complete-timeout-us`) | `:348-390` |

**[V all three rows.]** The manager binds by requesting the `SVC_CLIENT_FPGA` channel at
probe, failing with `couldn't get service channel (fpga)` if the service layer is not there
**[V `:412-417`]** — the exact string community reports quote when the DT is wrong (§3.1).

Two facts here are load-bearing for everything downstream: **Linux never parses the
bitstream** — it is a byte stream copied into buffers — and **every timeout above is a
ceiling, not a measurement**.

Note also what `write_complete` does *not* test: it clears `SVC_STATUS_COMPLETED` and
`SVC_STATUS_ERROR` and loops on anything else **[V `:376-388`]**, so a `SVC_STATUS_BUSY`
answer re-sends `COMMAND_RECONFIG_STATUS` against a decremented budget rather than failing.
That is the mechanism behind §6.2's multi-second tail.

### 2.5 Service layer → EL3 → fabric

`drivers/firmware/stratix10-svc.c` is not a mailbox driver. It marshals commands into
`INTEL_SIP_SMC_FPGA_CONFIG_*` SMCCC calls issued from a CPU-0-bound kthread
**[V `:835` `arm_smccc_smc`, `:856` `arm_smccc_hvc`]**. ATF at EL3 is what actually drives
the SDM. The shared DMA region used for the bitstream buffers is obtained by asking the
secure world: `INTEL_SIP_SMC_FPGA_CONFIG_GET_MEM` returns address and size
**[V `:696`]**, which is then `devm_memremap(…, MEMREMAP_WC)`'d into a genpool
**[V `:787`]**. The driver **never reads the DT `memory-region` property** — grep for it in
that file returns nothing **[V, 2026-08-21]**. The DT node's only job is to keep Linux off
that RAM; the binding requires it anyway **[V
`Documentation/devicetree/bindings/firmware/intel,stratix10-svc.yaml:51-64`]**.

The status poll is where multi-second behaviour is expressible: the service thread polls
`INTEL_SIP_SMC_FPGA_CONFIG_ISDONE` once per second — `FPGA_CONFIG_STATUS_TIMEOUT_SEC 30`
**[V `:40`]**, a countdown seeded at `:283` and an `msleep(1000)` at `:295` — and reports
`SVC_STATUS_BUSY` when the countdown expires **[V `:301`]**.

Bridge freeze/thaw during reconfiguration therefore happens **inside SDM/ATF, invisible to
Linux** — confirmed structurally by the absence of any `fpga-bridges` property on the
Agilex region node and of any arm64 Intel DTS reference to `altr,socfpga-*-bridge`
**[V `arch/arm64/boot/dts/intel/socfpga_agilex.dtsi:75-80`; grep across
`arch/arm64/boot/dts/intel/` returns nothing, 2026-08-21]**.

### 2.6 There is no second door — for this manager

The FPGA manager's sysfs surface is `name`, `state`, `status` — all `DEVICE_ATTR_RO`
**[V `drivers/fpga/fpga-mgr.c:655-657`]**. The region's is `compat_id`, likewise read-only
**[V `drivers/fpga/fpga-region.c:175`]**. Neither exposes a write path or an ioctl.

**Scoped claim (corrected in refutation, §10):** *for the stratix10/agilex SoC manager*,
applying an overlay is the only way in. Mainline at large has one other userspace door:
`drivers/fpga/dfl-fme-pr.c:146` reaches `fpga_region_program_fpga()` — and hence
`fpga_mgr_load()` — from a DFL FME partial-reconfiguration **ioctl** **[V, read
2026-08-21]**. That path binds only DFL-enumerated hardware with DFL's own region and
manager, so it is unreachable on this SoC; the earlier universal phrasing ("the only
mainline way in") was falsifiable as written and has been narrowed. The consequence for
the DE25 is unchanged, and it is why §3.2 (no loader exists) is a blocker rather than a
convenience.

## 3. The two gaps mainline does not fill

### 3.1 Agilex 5 is absent from 6.18.44 — and being added upstream

`socfpga_agilex5.dtsi` contains **no** `svc`, `fpga-mgr`, `fpga-region`, or bridge node.
It carries only a `reserved-memory` stub with no consumer **[V
`arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi:18-29`; whole file grepped for
`fpga`/`bridge`/`svc`, the only hits are stmmac's `agilex5` MAC compatibles and QSPI,
2026-08-21]**:

```dts
service_reserved: svcbuffer@0 {
        compatible = "shared-dma-pool";
        reg = <0x0 0x80000000 0x0 0x2000000>;   /* 32 MiB at 2 GiB */
        alignment = <0x1000>;
        no-map;
};
```

Nor does any compatible string in 6.18.44 name Agilex 5:

| Component | Strings it matches | Source |
|---|---|---|
| service layer driver | `intel,stratix10-svc`, `intel,agilex-svc` | `drivers/firmware/stratix10-svc.c:1133-1136` |
| service layer binding | same two | `Documentation/devicetree/bindings/firmware/intel,stratix10-svc.yaml:33-36` |
| FPGA manager driver | `intel,stratix10-soc-fpga-mgr`, `intel,agilex-soc-fpga-mgr` | `drivers/fpga/stratix10-soc.c:448-452` |
| FPGA manager binding | same two (`enum`) | `Documentation/devicetree/bindings/fpga/intel,stratix10-soc-fpga-mgr.yaml:22-25` |

**[V all four rows.]** No driver anywhere under `drivers/` mentions `agilex5` except the
stmmac Ethernet MAC **[V grep, 2026-08-21]**.

**What upstream is doing about it [V *A5-series*, read 2026-08-21].** Khairul Anuar Romli
(Altera) posted a series in Nov 2025, respun to v6 by 2025-11-19 and carrying a
`Reviewed-by:` from Xu Yilun:

- `fpga: stratix10-soc: Add support for Agilex5` (2025-11-11, `lkml.iu.edu/2511.1/03492.html`)
  is a **one-line** addition of `{.compatible = "intel,agilex5-soc-fpga-mgr"},` to
  `s10_of_match` — no behavioural change whatsoever.
- `dt-bindings: fpga: stratix10: add support for Agilex5` (v3, 2025-11-14,
  `.../05879.html`) restructures the `compatible` schema from a flat `enum` into a `oneOf`
  in which Agilex 5 is `intel,agilex5-soc-fpga-mgr` **with `intel,agilex-soc-fpga-mgr` as
  the declared fallback**.
- `arm64: dts: agilex5: add fpga-region and fpga-mgr nodes` (v3 2/2, 2025-11-14,
  `.../05877.html`) adds the `fpga-mgr` node under an `svc` block already carrying
  `method = "smc"`, `memory-region = <&service_reserved>` and `iommus = <&smmu 10>`, plus a
  top-level `fpga-region`.

Three consequences the plan should absorb:

1. The gen1 string is not a guess any more. The **vendor** publishes it as Agilex 5's
   DT-level fallback, and the driver change is a match-table entry only — so a DE25 DTS
   using `intel,agilex-soc-fpga-mgr` against the **unmodified 6.18.44 driver** is the
   configuration Altera is standardising, not a workaround. Whether it functions on
   silicon is still **[U]** (nobody in this document has run it), but the evidence class
   has moved from "inference from a shared binding enum" to "vendor-declared fallback,
   maintainer-reviewed".
2. The upstream DTS's `svc` node has `iommus = <&smmu 10>` and 6.18.44's
   `socfpga_agilex5.dtsi` has **no `smmu` node at all** **[V grep, 2026-08-21]**. The DE25
   board DTS must either omit that property or the DE25 must carry a newer DTSI. Whether
   omitting it is safe on Agilex 5 (does SDM DMA to the svc buffer traverse an SMMU that
   Linux must be told about?) is **[U]** — that is a concrete, cheap question for D0.3.
3. Whichever way the DE25 goes, it must author the `svc`/`fpga-mgr`/`fpga-region` nodes in
   a board file today, because none of the series is in 6.18.44.

*Record correction:* leg 2 of this task read the shared 6.18.44 binding enum as evidence
that the binding was intended to cover Agilex 5. That inference was unsupported by the YAML
text, which names neither Agilex 5 nor any intent, and it was demoted to **[U]** by the
refuter pass. The *A5-series* finding above independently supports the same conclusion from
a source that does say it — but it is a different, later document, and the demotion of the
original reasoning stands.

### 3.2 There is no generic overlay loader in mainline 6.18.44

`of_overlay_fdt_apply()` is exported **[V `drivers/of/overlay.c:1000`, `:1090`]** and has
exactly two non-test callers in this tree, both drivers applying a built-in overlay:
`drivers/misc/lan966x_pci.c:131` and `drivers/misc/rp1/rp1_pci.c:281` (plus KUnit helpers
in `drivers/of/of_kunit_helpers.c` and `unittest.c`) **[V grep, 2026-08-21]**. There is no
`configfs.c` in `drivers/of/`, and no source file mentions `device-tree/overlays` **[V]**.

Both callers apply exactly one overlay when their device probes and remove it when the
device goes away — `lan966x_pci.c:136`, `rp1_pci.c:299` and `:315` **[V]**. That is one
apply/remove per device lifetime. **MiSTer's pattern — dozens of apply/remove cycles per
session against a live region — has no mainline user at all**, so §11 row 4 is not merely
unmeasured, it is unexercised. Taken with the *AXE5* second-configuration hang (§6.1),
this belongs beside VAB in the headline conditions, and it is why the D2.5 plan (§6.3)
runs twenty iterations rather than one.

The `mkdir /sys/kernel/config/device-tree/overlays/0; echo … > path` workflow that *RB-A7*,
the Altera community threads and *A5-overlay* all describe is therefore **not a mainline
interface**. It is `CONFIG_OF_CONFIGFS`, named explicitly in the community kernel-config
recipe alongside `CONFIG_OF_OVERLAY`, `CONFIG_FPGA_MGR_STRATIX10_SOC`, `CONFIG_FPGA_BRIDGE`,
`CONFIG_FPGA_REGION` and `CONFIG_OF_FPGA_REGION` **[U — *A5-overlay*, snippet grade,
2026-08-21]**. Its provenance is Pantelis Antoniou's *"OF: DT-Overlay configfs interface"*
series, posted to LKML in 2014 (v3 `lkml.rescloud.iu.edu/1403.2/01461.html`, v8
`lkml.iu.edu/hypermail/linux/kernel/1410.3/03532.html`) and **never merged** — it survives
as a vendor-kernel carry **[U — the series exists and is dated; that the symbol vendors ship
descends from it is inference, and no vendor tree was opened this session]**.

Leg 2 of this task reported the configfs workflow as the practical Linux-side flow; leg 1
established from source that it does not exist here. Both are right about their own object,
and the DE25 must resolve the difference by choosing one of:

| Option | What it costs | Notes |
|---|---|---|
| (a) carry the out-of-tree `OF_CONFIGFS` patch | one more carried patch, unmerged since 2014, no upstream prospect | matches every vendor doc and the one working Agilex 5 community recipe, so vendor recipes work verbatim |
| (b) a small board driver exposing sysfs/ioctl over `of_overlay_fdt_apply()` | ~100 lines we own, plus a UAPI we own forever | mirrors how the DE10 got its UIO wiring; no upstream dependency |
| (c) preload the fabric in U-Boot only | no runtime core switching at all | acceptable for the L1 developer OS; **not** acceptable for MiSTer parity |

For the bare developer OS (ADR 0027 Decision 6), **(c) is sufficient and (a)/(b) are
optional** — this is the choice that lets D2 ship without solving overlay loading. Core
switching needs (a) or (b), and that is an L0/D2 decision, not one this task closes.

## 4. What a DE25 kernel and device tree must contain

### 4.1 Kconfig

| Symbol | Value | Dependency | Source |
|---|---|---|---|
| `CONFIG_ARCH_INTEL_SOCFPGA` | y | — | platform |
| `CONFIG_INTEL_STRATIX10_SERVICE` | y | `ARCH_INTEL_SOCFPGA && ARM64 && HAVE_ARM_SMCCC` | `drivers/firmware/Kconfig:142-144` |
| `CONFIG_FPGA` | y | — | `drivers/fpga/Kconfig:6` (`menuconfig FPGA`) |
| `CONFIG_FPGA_MGR_STRATIX10_SOC` | y | `ARCH_INTEL_SOCFPGA && INTEL_STRATIX10_SERVICE` | `drivers/fpga/Kconfig:61-63` |
| `CONFIG_FPGA_BRIDGE` | y | — (needed only because `FPGA_REGION` depends on it; no bridge driver is used) | `drivers/fpga/Kconfig:106` |
| `CONFIG_FPGA_REGION` | y | `FPGA_BRIDGE` | `drivers/fpga/Kconfig:145` |
| `CONFIG_OF_FPGA_REGION` | y | `OF && FPGA_REGION` | `drivers/fpga/Kconfig:153` |
| `CONFIG_OF_OVERLAY` | y | **not selected by `OF_FPGA_REGION`** — see below | `drivers/of/Kconfig:105-109` |
| `CONFIG_FW_LOADER` | y | default y | `drivers/base/firmware_loader/Kconfig:4-7` |

**[V all rows.]** `CONFIG_SOCFPGA_FPGA_BRIDGE` and `CONFIG_FPGA_MGR_SOCFPGA` are **Cyclone V
/ Arria 10 only** and must not be set **[V `drivers/fpga/Kconfig:15`, `:112`]**.

**The `OF_OVERLAY` trap [V].** `OF_FPGA_REGION` is `depends on OF && FPGA_REGION` with no
`select` **[V `drivers/fpga/Kconfig:153-155`]**, and with `OF_OVERLAY=n`,
`of_overlay_notifier_register()` is a static-inline stub returning 0
**[V real prototype `include/linux/of.h:1763`, stub `:1784`; `drivers/of/Makefile` builds
`overlay.o` only under `CONFIG_OF_OVERLAY`]**. The FPGA region driver therefore *registers
successfully at boot and its notifier can never fire*. A defconfig missing
`CONFIG_OF_OVERLAY` is silently non-functional — no error, no warning, no reconfiguration.
Given this repo's standing lesson that `linux.config` is a minimal defconfig and an absent
symbol is not necessarily off (memory: `linux-config-is-minimal-defconfig`), this belongs in
`scripts/check-kernel-defconfig-sync.sh`'s per-board sentinel set when D1.2 parameterizes it.

### 4.2 Device-tree nodes to author

Modelled on `socfpga_agilex.dtsi:63-80` **[V]** and cross-checked against the *A5-series*
DTS patch **[V]**, added by the DE25 board DTS on top of the in-tree
`socfpga_agilex5.dtsi` (which already provides `service_reserved`):

```dts
/ {
	firmware {
		svc {
			compatible = "intel,agilex-svc";   /* [U] gen1 string on Agilex 5 silicon */
			method = "smc";
			memory-region = <&service_reserved>;
			/* upstream's Agilex 5 svc node also has iommus = <&smmu 10>;
			   6.18.44's socfpga_agilex5.dtsi has no smmu node — §3.1 note 2 [U] */

			fpga_mgr: fpga-mgr {
				/* upstream will prefer:
				   compatible = "intel,agilex5-soc-fpga-mgr",
				                "intel,agilex-soc-fpga-mgr";
				   6.18.44's driver only matches the second — [V §3.1] */
				compatible = "intel,agilex-soc-fpga-mgr";
			};
		};
	};

	base_fpga_region: fpga-region {
		compatible = "fpga-region";
		#address-cells = <0x2>;
		#size-cells = <0x2>;
		fpga-mgr = <&fpga_mgr>;
	};
};
```

Writing the two-string form now is free and forward-compatible **at runtime**: 6.18.44
matches on the fallback, a newer kernel matches on the specific string. It is **not**
schema-clean today — the fpga-mgr binding has not adopted the `items`/`oneOf` form, so
`dtbs_check` warns on the two-string compatible until Khairul's series lands (see
[`de25-implementation-path.md`](de25-implementation-path.md) §2.5 and §8 Q4). Runtime
binding and CI cleanliness are separate claims; only the first holds now.

Note what is *not* there: no `fpga-bridges` property, and no bridge nodes at all — the
Cyclone V shape (`fpga_bridge0..3` at `0xff400000`/`0xff500000`/`0xff600000`/`0xffc25080`
plus `fpgamgr@ff706000` and a `base_fpga_region` at `:90`,
`arch/arm/boot/dts/intel/socfpga/socfpga.dtsi:90,526-561` **[V]**) has no Agilex analogue
and must not be transliterated.

One practical warning from the one working community report: the base DT must not describe
fabric peripherals that the *pre-switch* bitstream does not implement — *A5-overlay*'s
resolution involved stripping fabric-side nodes (LEDs, a `soc@0` section, a USB node) from
the main DT before the overlay would apply, and the characteristic failure is
`OF: overlay: find target, node: /fragment@0, path '/soc/base_fpga_region' not found`
**[U, snippet grade, 2026-08-21]**. For MiSTer this generalises to: the *base* DT describes
only HPS-side hardware; everything fabric-side arrives with the core's overlay (§7.3).

### 4.3 The overlay a core switch applies

```dts
/dts-v1/;
/plugin/;

&base_fpga_region {
	#address-cells = <0x2>;
	#size-cells = <0x2>;
	firmware-name = "cores/minimig.core.rbf";
	config-complete-timeout-us = <30000000>;   /* mandatory in practice — see below */

	/* per-core child nodes describing what this bitstream exposes,
	   if the DE25 ends up carrying core-specific DT fragments — §7.3 */
};
```

**`config-complete-timeout-us` is effectively mandatory on this manager [V code / U
consequence].** `fpga_image_info_alloc()` uses `devm_kzalloc`, so the field defaults to 0
**[V `drivers/fpga/fpga-mgr.c:115`]**; `of-fpga-region.c:246-247` overwrites it only if the
property exists; `stratix10-soc.c:356` does `usecs_to_jiffies(0)` → 0 and passes that to
`wait_for_completion_timeout()` **[V `:356-370`]**. An overlay omitting the property will
**almost always** fail immediately with `timeout waiting for RECONFIG_COMPLETED` /
`-ETIMEDOUT` rather than waiting — *almost*, because `wait_for_completion_timeout(x, 0)`
returns non-zero if the completion is already signalled, so a callback landing in the window
between `reinit_completion()`/send and the wait would let it through **[V code / U
consequence — corrected from "will fail" during refutation]**. This is inferred from source,
not executed: it is a one-line experiment at D2.5, and it should be run more than once for
exactly that race. It also explains why both *RB-A7*'s Agilex 7 example and the *A5-overlay*
working recipe set 30 s.

## 5. RBF formats and the authentication question

### 5.1 Formats

- HPS-first splits the design into a **phase-1** `<design>.periph.rbf` (periphery + HPS
  pin/DDR bring-up, FSBL embedded, built with `quartus_pfg -o hps=on -o hps_path=…`,
  QSPI-resident) and a **phase-2** `<design>.core.rbf` (the fabric image, SD-resident)
  **[V *GHRD*, retrieved 2026-08-21; matches `de25-boot-chain.md` §2 steps 2-5]**.
- **Linux does not parse either.** `request_firmware()` reads the file whole and
  `stratix10-soc.c` copies it into service-layer buffers verbatim **[V §2.4]**. Format
  compatibility — RBF version, Quartus version, device match — is entirely an SDM/ATF
  concern, and any mismatch surfaces in Linux only as an SVC error status. That is a
  diagnosability cost worth writing down before D2.5 debugging starts.
- **Partial reconfiguration** is expressible (`partial-fpga-config` →
  `COMMAND_RECONFIG_FLAG_PARTIAL` **[V `of-fpga-region.c:223-224`;
  `stratix10-soc.c:186-193`]**) but whether Agilex 5 E-series supports PR, and whether a
  MiSTer-style core would ever want it rather than full reconfiguration, is **[U]** and out
  of scope here.
- **Encryption:** `encrypted-fpga-config` sets a flag this driver ignores
  **[V `stratix10-soc.c:186-193` — only `FPGA_MGR_PARTIAL_RECONFIG` is tested]**. Encrypted
  bitstreams are handled transparently by SDM or not at all; the Linux property is inert
  here.
- No cross-version compatibility requirement between the QSPI-resident phase-1 image and an
  SD-resident phase-2 `core.rbf` was found stated anywhere; a direct fetch of the *GHRD*
  boot-examples page returned "not addressed in this document" for that question
  **[U, retrieved 2026-08-21]**. This corroborates — it does not resolve —
  [`de25-boot-chain.md`](de25-boot-chain.md) §5's treatment of version skew as a
  project-side risk managed by convention.

### 5.2 VAB / authentication — the project-defining unknown

What is supported by a source: once QKY/efuse authentication keys are provisioned on an
Agilex device, the SDM will no longer accept a configuration bitstream that is unsigned or
signed with the wrong key; U-Boot's VAB validates SHA384-signed FIT images (U-Boot, ATF,
kernel, DTB) through the SDM **[U — Altera Community thread 317341 and the u-boot-list VAB
series (mail-archive msg399550/397090/399718), search-snippet only; intel.com doc 762191
§Device Security returned HTTP 403 on 2026-08-21]**.

What is **not** established, and is the question that decides whether this board can host
MiSTer at all:

1. Does an **unprovisioned** Agilex 5 accept unsigned bitstreams? The converse of the quote
   above implies yes, but no source states it. **[U]**
2. Does **Terasic's factory QSPI image on the DE25-Nano** ship with keys provisioned?
   **The *UM* rev. 2025-09-05 was read in full this session and contains zero occurrences
   of VAB, authentication, signing, QKY, efuse or secure boot [V — text extracted from the
   DigiKey mirror and grepped, 2026-08-21].** Silence is weak evidence for a permissive
   default and is not proof; a board manual would not necessarily mention provisioning
   either way.

The evidence base supports "very likely permissive out of the box" and supports nothing
stronger. Because a wrong answer here invalidates the entire core-switching premise —
not the schedule, the premise — this should be settled *before* hardware money is
committed if a document can be obtained, and in the first hour of D2.5 otherwise.

## 6. Latency

### 6.1 Evidence classes, kept apart

| # | Evidence | Class | What it actually says | Tag |
|---|---|---|---|---|
| 1 | Config time = bitstream ÷ (config clock × bus width); ~250 MHz internal config clock off OSC_CLK_1 | vendor figure, **unread** | a formula, no Agilex-5 numbers to put in it | **[U]** doc 683673 403'd, snippet paraphrase, 2026-08-21 |
| 2 | Agilex 5 datasheet "Configuration Bit Stream Sizes" table exists; A5EB013 row unread | vendor figure, **unread** | nothing usable | **[U]** doc 813918 is a JS SPA, 2026-08-21 |
| 3 | AXE5-Eagle `design.core.rbf` = 2,568,192 bytes (A5ED065/A5ED043, 656K/334K LE) | community report, dated | one real Agilex-5 bitstream size, on a **larger** die than A5EB013 (138K LE) | **[V]** *AXE5* via Wayback 20260215052804 (draft's copy; not re-fetchable 2026-08-21) |
| 4 | Same log: `2568192 bytes read in 124 ms (19.8 MiB/s)` then `FPGA reconfiguration OK!`, **no timestamp for the `fpga load` step** | community report, dated, **U-Boot context** | the 124 ms is the eMMC read; the SDM write is untimed but drew no comment. Bounds at most the SDM-write phase — **not** the Linux overlay transaction | **[V figure / U applicability]** as above |
| 4a | **The same thread's subject is the failure, not the success**: the system hangs when `core.rbf` is configured a second time or after a warm reboot; the LWH2F bridge is implicated; described in-thread as a silicon issue with no fix; workaround is `bridge enable 0x3b` to skip enabling the F2H bridge, possibly with F2H disabled in the Quartus design too | community report, adverse | dated on-Agilex-5-silicon evidence *against* repeated configuration — in U-Boot, not the Linux overlay path | **[U]** search-corroborated 2026-08-21 (thread 312795 title + resolution); primary 403, Wayback unreachable this session |
| 5 | Driver ceilings: 300 ms request, 720 ms/buffer, 4 × 512 KiB in flight | source, exact | upper bounds the firmware authors chose; **not durations** | **[V]** `stratix10-soc.c:19-20`; `stratix10-svc-client.h:68-69` |
| 6 | *RB-A7* overlay sets `config-complete-timeout-us = 30000000`; the *A5-overlay* working recipe sets the same | analogy (Agilex **7**) + ceiling | a 30 s safety ceiling; the one dmesg timestamp on that page is time-since-boot | **[U]** retrieved 2026-08-21 |
| 7 | Service-layer status poll: `msleep(1000)` per iteration, `FPGA_CONFIG_STATUS_TIMEOUT_SEC 30`, `SVC_STATUS_BUSY` on expiry, which `write_complete` does not test and so re-sends | source, exact | **any configuration not complete at the first status poll quantizes to ≥1 s** | **[V]** `stratix10-svc.c:40,283,295,301`; `stratix10-soc.c:376-388` |
| 8 | DE10 core switch "a few seconds", dominated by SD read + Main_MiSTer reinit | inference, **unmeasured** | plausible, and the baseline this is compared against — but nobody has measured the DE10 split either | **[U]** unsourced inference; D2.5 should measure the DE10 control |

Note what rows 5 and 6 are not: a 720 ms per-buffer timeout does not mean a buffer takes
720 ms, and a 30 s completion ceiling does not mean configuration takes 30 s. Reading
either as a duration is the most likely way this section gets misquoted downstream.

Row 4a was added by the refutation pass. The draft cited *AXE5* only for its favourable
timing figure while the thread is, in substance, an adverse report about exactly the
condition (§11 row 4) the draft called "completely unmeasured". Citing the favourable half
of the only on-silicon source in evidence was a selective read and is corrected here.

### 6.2 The estimate

First-principles arithmetic over rows 1 and 3 (a **[U]** clock times a **[V]** size, so the
product is **[U]**): 2.5 MB at 250 MHz × 4–8 lanes ≈ 500 MB/s–1 GB/s gives 2–5 ms of raw
fabric write. Add mailbox round-trips, DMA handshakes, and the fact that A5EB013 is a
smaller die whose MiSTer-scale bitstream plausibly lands at 1–4 MB (compression tracks used
content more than LE count **[U, general property]**).

| Phase | Estimate | Basis | Confidence |
|---|---|---|---|
| Storage read of a 1–4 MB `.rbf` | 50–500 ms | row 4 (measured on Agilex 5, different medium, U-Boot) | medium |
| `request_firmware` + copy into 4 × 512 KiB buffers | < 50 ms | arithmetic over row 5's buffer geometry | medium-low |
| SDM fabric write proper | 2–300 ms, **or ≥1 s in ≥1 s quanta if not done at the first status poll** | rows 1 + 3 arithmetic; row 7 for the quantization | **low** |
| Overlay apply/remove: node create/destroy, driver bind/unbind | **unmeasured, no bound, and unexercised by any mainline user** (§3.2) | nothing found | **none** |
| Userspace teardown/reinit | framework-defined, L0 | — | n/a |

**Stated as one range: the reconfiguration transaction (overlay apply → fabric running) is
~10 ms to ~1 s, low confidence, with a pessimistic tail to a few seconds.** That tail is not
hand-waving: row 7 is a concrete in-tree mechanism for it — the service layer polls
configuration status once per second, so anything not finished when the first
`ISDONE` lands costs a whole second, and a `SVC_STATUS_BUSY` answer is silently retried
rather than surfaced. *The draft's sentence "nothing in the evidence puts it above one
second" was refuted on the draft's own citations and has been deleted.* Row 4 remains the
strongest single favourable signal and it is both an absence-of-complaint argument and a
U-Boot measurement that cannot speak to the overlay half of the transaction.

The real risk is still the row with no bound. The DE10 switches cores by writing a
memory-mapped register from userspace; the DE25 would tear down and rebuild a slice of the
live device tree on every switch. That is categorically heavier, it has no mainline
precedent at MiSTer's cycle frequency (§3.2), there is dated on-silicon evidence of a
second-configuration hang on a related path (row 4a), and it is the thing D2.5 must
actually measure.

### 6.3 D2.5 hardware-measurement plan (runnable)

Prerequisite: a DE25 board booted to Linux with §4's DT and defconfig, an overlay loader
per §3.2, and one `core.rbf` built for A5EB013.

```sh
# 0. Establish that the stack bound at all.
ls -d /sys/class/fpga_manager/*/ && cat /sys/class/fpga_manager/fpga0/name
cat /sys/class/fpga_manager/fpga0/state          # expect "operating"/"unknown", not absent
ls -d /sys/class/fpga_region/*/
dmesg | grep -iE 'stratix10|svc|fpga'            # record the SMC/shared-mem probe lines.
                                                 # "couldn't get service channel (fpga)"
                                                 # means the svc node is wrong (§2.4)

# 1. Record the bitstream size — the missing input to §6.2's arithmetic.
stat -c '%n %s' /lib/firmware/cores/*.rbf

# 2. Isolate the storage read from the SDM write (drop caches, then warm).
cp /media/fat/cores/x.core.rbf /lib/firmware/cores/
sync; echo 3 > /proc/sys/vm/drop_caches
S=$(date +%s.%N); cat /lib/firmware/cores/x.core.rbf > /dev/null; E=$(date +%s.%N)
echo "cold read: $(echo "$E-$S" | bc)"           # repeat warm; the delta is the read cost

# 3. Time the reconfiguration transaction itself, warm cache, 20 iterations.
for i in $(seq 20); do
  S=$(date +%s.%N)
  <apply overlay>                                 # the §3.2 loader, whichever option won
  E=$(date +%s.%N); echo "apply $i $(echo "$E-$S" | bc)"
  S=$(date +%s.%N)
  <remove overlay>
  E=$(date +%s.%N); echo "remove $i $(echo "$E-$S" | bc)"
done
# Report min/median/max for apply and remove separately. Iteration 1 vs 2..20 is THE
# question (§6.1 row 4a): does the region accept a second overlay cleanly, does HPS->fabric
# access still work after the second configuration, and does anything leak? Watch dmesg for
# the OF property-leak warnings community reports mention, and probe an LWH2F-window read
# after every switch, not just the first.

# 4. Kernel-side attribution for one run.
echo 1 > /sys/kernel/debug/tracing/events/enable   # or: dynamic_debug on drivers/fpga
dmesg -c >/dev/null; <apply overlay>; dmesg | ts   # 'Requesting full reconfiguration' ->
                                                   # 'RECONFIG_COMPLETED' is the SDM window.
                                                   # A window that is a near-exact multiple
                                                   # of 1 s means row 7's poll dominated.

# 5. The authentication question (§5.2) — do this FIRST, it is binary.
#    Load an unsigned, locally built core.rbf. If SDM rejects it, everything above is moot.

# 6. Failure-mode checks worth one run each.
#    - overlay WITHOUT config-complete-timeout-us -> expect -ETIMEDOUT (§4.3); run it
#      several times, the zero-jiffy wait has a benign race
#    - a truncated .rbf -> confirm the error is diagnosable, not a hang
#    - apply an overlay while one is already applied -> expect "Region already has overlay
#      applied" (of-fpga-region.c:203)
```

Deliverable: a table of min/median/max for read, apply, remove, and SDM window; the
bitstream size; and a yes/no on unsigned acceptance. That table replaces §6.2 wholesale and
resolves five of §11's rows. **A DE10 control run** instrumenting `fpga_io.cpp`'s core-load
path is not optional garnish — §1's "parity with the DE10" claim is unfalsifiable until the
DE10 baseline is a number rather than "a few seconds". Do it in the same session.

## 7. HPS↔FPGA memory semantics

### 7.1 What Linux can see

Nothing. Unlike Cyclone V — four address-bearing bridge nodes with real windows and two
in-tree bridge drivers **[V `arch/arm/boot/dts/intel/socfpga/socfpga.dtsi:526-561`;
`drivers/fpga/altera-hps2fpga.c`, `altera-fpga2sdram.c`]** — the Agilex family exposes no
bridge device to Linux at all **[V §2.5]**. Bridge control is SDM/ATF's. Whatever apertures
exist are things a board DTS must *declare* from documentation, not things the kernel
discovers. The *AXE5* report (§6.1 row 4a) is a reminder that this invisibility cuts both
ways: when a bridge misbehaves after a second configuration, Linux has no driver, no sysfs
and no error path through which to notice.

### 7.2 What the documentation says (weakly)

Agilex 5's HPS reportedly presents three MPU-visible H2F windows totalling 256 GB (1 GB at
`0x0_4000_0000`, 15 GB at `0x4_4000_0000`, 240 GB at `0x44_0000_0000`) with LWH2F at
`0x0_2000_0000`, and carries a CCU whose F2H/F2SDRAM datapaths are steerable per
transaction via an AXUSER signal the fabric master drives — meaning **coherency is opt-in
at fabric-IP design time, not a SoC-wide guarantee** **[U — Intel HPS TRM 814346/813752
returned HTTP 403 to every fetch on 2026-08-21; these are search-snippet paraphrases
corroborated across snippets but the primary document was never read]**. *Leg 4 of this task
tagged the address windows [V]; they are demoted to [U] here on the house rule that a
snippet is not a read document, and both refuters upheld the demotion. F2H and F2SDRAM
window addresses and widths were not recovered at all.*

If the AXUSER/CCU story holds, the consequence for MiSTer is concrete and unpleasant: a
frame reader or DMA master in the fabric must be *built* to assert coherency, and the HPS
side cannot assume cache maintenance is free. That is a gateware-design constraint, i.e. an
L0 constraint, and it is precisely the "jointly accessible when required" phrase from plan
§1 refusing to mean anything until measured.

### 7.3 What a MiSTer-style framebuffer would require

The DE10 shape, for reference: `MiSTer_fb` is a plain fbdev platform driver that
`memremap()`s a fixed window — `reg = <0x22000000 0x800000>` (8 MiB), IRQ SPI 40 — publishes
`/dev/fb0` with pixels at `+4096`, and turns the FPGA's per-frame interrupt into
`FBIO_WAITFORVSYNC` **[V `board/mister/de10nano/linux-patches/0001-fbdev-add-MiSTer_fb-driver.patch:6-11,31-45`]**.

Ported to DE25 that needs four things, three of which are not this repo's to decide:

| Requirement | Status |
|---|---|
| An HPS-visible DRAM window the fabric can write | **LPDDR4A** is the bank that can implement the HPS hard EMIF — *UM* §3.7.4: "The I/O bank where LPDDR4A is located can implement the Intel Agilex 5 FPGA EMIF IP with the Hard Processor Subsystem (HPS). If no HPS EMIF IP is used in a system, the LPDDR4A bank can be used for the EMIF IP of the FPGA", and the HPS feature list reads "1GB LPDDR4 (32-bit data bus), share with FPGA" **[V *UM* p.7, §3.7.4]**. Putting the framebuffer in LPDDR4B would force the HPS to read *through* H2F into the fabric's own EMIF — the reverse direction, structurally worse, unprecedented in MiSTer's model. |
| A `/reserved-memory` `no-map` node over that window, plus the window's address | needs the GHRD; address is **[U]** |
| A per-frame interrupt from fabric to HPS | **the doorbell problem again** — see §8. `simplefb` has no vsync-interrupt concept and cannot serve `FBIO_WAITFORVSYNC` **[U — inferred from `drivers/video/fbdev/simplefb.c`'s static-buffer binding, not from an explicit statement]**, so a forward-ported `MiSTer_fb` beats DRM/simplefb for this ABI |
| Coherency or an explicit cache-maintenance discipline | **[U]**, §7.2 |

The port cost is plausibly DT content and a window rather than a rewrite: the ioctl ABI is
mainline UAPI with a fixed-width `__u32` argument and is architecture-independent
**[V patch header, ABI section]**. *This is an inference, not a verified audit* — the cited
patch lines establish the ABI's architecture-independence and list the 6.18 API churn, not
that the driver body is free of arm32 assumptions; the refuter pass flagged the original
**[V]** as leaning past its citation and it is restated as inference here. Everything
expensive is upstream of the driver either way.

### 7.4 DP-10 — closable now

DP-10's premise is "**if** the HDMI 2.0 transmitter is HPS-reachable". It is not, and the
premise is doubly wrong: the transmitter is fabric-owned, and it is not a 2.0-class part.

- *UM* §3.7.3 is filed under **§3.7 "Peripherals Connected to the FPGA"**, not §3.8
  "Peripherals Connected to the Hard Processor System", whose subsections are exhaustively
  push-buttons/LEDs, Gigabit Ethernet, UART-to-USB, micro SD, USB 2.0 OTG and the
  accelerometer — **no HDMI** **[V *UM* contents pp.1-2, §3.8]**.
- The video path is FPGA pins: `HDMI_TX_D0..D23` and the clocks are FPGA pin assignments
  (Table 3-13), and the control bus is `HDMI_I2C_SCL PIN_BT1` / `HDMI_I2C_SDA PIN_BW2`,
  FPGA pins, alongside a separate `HPS_I2C_SCL/SDA` pair for the HPS controller (Table 3-7)
  **[V *UM* §3.6, §3.7.3]**.
- **Capability footnote:** *UM* §3.7.3 says the ADV7513 "incorporates HDMI v1.4 features,
  including 3D video support and 165MHz support for all video formats up to 1080p and
  UXGA", while Terasic's own feature bullet on p.7 says "HDMI 2.0 Output Port (Support
  1080P)" **[V both, *UM*]**. That is an internal contradiction in the manual; the body
  text describing the actual part is the primary figure, and this project's docs (including
  the D0.2 brief) inherited the marketing "2.0". Use v1.4 / 165 MHz / 1080p.
- The MIPI D-PHY connector (§3.7.7) is likewise fabric-wired **[V *UM*]**.

**DP-10's stated unknown is answered: the display transmitter is fabric-owned and
1.4-class, so the "kernel DRM path independent of the fabric scaler" fork does not exist on
this board.** DP-10 stays tabled — but tabled with its question closed rather than open,
and plan §6's "[U, D0.1]" tag on it can be retired.

One residual **[U]**: *UM* §3.6 refers to "Figure 3-13 Control mechanism for the I2C
multiplexer" and says the board's I2C devices "are connected to the HPS and FPGA I2C bus
independently". The figure is an image and was not readable from the extracted text, so
whether the ADV7513's *control* I2C can be muxed onto the HPS bus is not settled. It does
not change the verdict: the 24-bit video bus and clocks are unambiguously FPGA pins, so
there is no HPS-side scanout regardless of who owns the I2C.

## 8. DP-9 — verdict

**Confirmed on the decision. Refuted on the rationale. The scope must be narrowed in the
record.** Both refuters upheld this split verdict; neither refuted it.

DP-9 as written: *"the DE25 (including any RT variant) adopts the Agilex-native idioms:
DTS/fpga-region configuration in place of the carried UIO doorbell patches, provided D0.2
confirms that is the proper architecture. The beta-series UIO patches (0043–0045) are not
ported by default."* That sentence contains two claims. They have different answers.

**Claim A — fpga-region is the proper reconfiguration architecture: CONFIRMED [V].** Not
merely native — *sole*, for this manager. There is no memory-mapped FPGA manager on Agilex
to write (§2.5); the manager's and region's sysfs are read-only and there is no ioctl on
this path (§2.6); the only route to `fpga_mgr_load()` from userspace on this SoC is an
overlay apply (§2.3). A "port the DE10 approach" alternative does not exist to be weighed.
The *A5-series* upstream patches (§3.1) are Altera standardising exactly this shape for
Agilex 5, which is independent confirmation from the vendor.

Separately, patches 0043 and 0044 are *literally* unportable: 0043 allocates Cyclone V GIC
SPI cells 48..55 for `f2h_irq8..15`, and 0044 names `0xff200000 + 0x200000` (the lwhps2fpga
window) and `0x20000000 + 0x20000000` (the DDR3 f2sdram aperture) **[V patch texts, read
2026-08-21]**. None of those addresses or interrupt numbers exists on Agilex 5, whose base
DTSI has no bridge nodes at all (§3.1). "Not ported by default" is the only correct
disposition, and it would be correct even if fpga-region did not exist.

**Claim B — fpga-region stands "in place of" 0043–0045: REFUTED [V].** The overlay notifier
fires on `OF_OVERLAY_PRE_APPLY` and `OF_OVERLAY_POST_REMOVE` and explicitly declines
everything else **[V `of-fpga-region.c:353-379`]**. It has nothing to say about how a
*running* core signals the HPS, or how the HPS reaches that core's registers and shared
memory. That is exactly and only what 0043 (blocking `read()` on `/dev/uioN` replacing a
cause-register spin) and 0044/0045 (named, size-bounded, optionally write-combined
apertures replacing `/dev/mem`) were written to do **[V patch rationale sections]**. All
four D0.2 research legs reached this independently, no leg dissented, and both refuters
confirmed it against the source.

Patch **0045** deserves separate mention: it is a generic, arch-independent UIO kernel
feature (`UIO_MEM_PHYS_WC = 6` in `include/linux/uio_driver.h`, an `else if` in
`uio_mmap_physical`, property parsing in `uio_pdrv_genirq`) fixing a page-attribute
throughput floor measured at ~100 MB/s write / ~54 MB/s read on Cyclone V **[V patch body,
read 2026-08-21]**. Normal-NC vs Device-nGnRnE is the same distinction on ARMv8, and nothing
in this task shows the floor disappears on Agilex 5's HPS↔FPGA path. DP-9 does not settle
0045's question and should not be cited as having done so.

**What the record should say instead.** DP-9's proviso is met, narrowed to: *the DE25 adopts
DTS/fpga-region as its bitstream-loading architecture; the carried UIO patches 0043–0045 are
not ported, because 0043/0044 encode Cyclone-V-only addresses and interrupt numbers and
0045 has nothing to attach to until a GHRD exists.* The **runtime HPS↔FPGA signaling and
aperture contract is not decided by DP-9 and is not closed by D0.2.** It is gated on L0
(a Main_MiSTer aarch64 HAL) and on a GHRD defining the topology, and its likely answers are
(a) a doorbell-style UIO binding again, re-derived for Agilex 5, (b) per-core DT fragments
shipped alongside each `.rbf` and applied by the same overlay, or (c) a native binding once
Intel documents one. That deserves its own DP rather than being absorbed into DP-9's
confirmation — an accepted-and-forgotten DP-9 would leave the project believing a solved
problem where it has an unexamined one.

**Record edit this document does not make — action item.** Both refuters made the
"confirmed" enum conditional on the narrowing landing as an actual edit to
[`de25-nano-plan.md`](de25-nano-plan.md) §6, whose DP-9 bullet still reads "in place of the
carried UIO doorbell patches", and on a new DP being opened for the runtime
signaling/aperture/coherency contract (§11 row 11). **That edit has not been made here** —
D0.2's brief scoped this task to writing this dossier and adding one cross-link to
[`de25-boot-chain.md`](de25-boot-chain.md), and unilaterally rewriting a plan decision
record is outside it. It is recorded as a blocking follow-up: until it lands, plan §6 reads
as having settled a problem D0.2 explicitly found unsettled.

**Confirming DP-9 because it was written down would have been the failure mode here.** It
survives because the alternative architecture does not exist, not because the plan said so;
and half its sentence does not survive at all.

## 9. Where this task's legs disagreed

Recorded so the disagreements are not silently resolved by whoever reads this next.

| Subject | Disagreement | Resolution here |
|---|---|---|
| Userspace overlay loading | Leg 2: the practical flow is `/sys/kernel/config/device-tree/overlays/`. Leg 1: `of_overlay_fdt_apply` has no generic caller in this tree. | Both correct about their object. Mainline 6.18.44 has no such interface **[V]**; vendor kernels carry `CONFIG_OF_CONFIGFS`, descended from a 2014 series never merged **[U provenance]**. §3.2. |
| `intel,agilex-soc-fpga-mgr` on Agilex 5 | Leg 2 read the 6.18.44 binding enum as intent to cover Agilex 5. Legs 1 and 4 found no Agilex-5 string anywhere. | Leg 2's *reasoning* is unsupported and stays demoted to **[U]**; its *conclusion* is now independently supported by the Nov-2025 *A5-series*, which declares the gen1 string as Agilex 5's fallback. §3.1. |
| Agilex 5 H2F/LWH2F windows | Leg 4 tagged them **[V]** from corroborated search snippets. | Demoted to **[U]** — the TRM was never read (403). Both refuters upheld. §7.2. |
| Whether DP-9's proviso is met | Legs 1 and 4 leaned "met only for loading"; legs 2 and 3 leaned "met, with the doorbell purpose merely unaddressed". | Same finding, different emphasis. Resolved as §8's split verdict, which both refuters upheld. |

## 10. Refutation record

**Pass ran 2026-08-21, two refuters, both against the pre-adversarial draft of this
document.**

**Lenses.** (1) *Evidence-chain* — re-open every cited file at every cited line, check the
source says what is attributed to it, hunt for drifted or fabricated citations and for
selective reads. (2) *UX viability, adversarial* — argue as hard as the evidence permits
that core switching is **not** viable on Agilex 5 (latency tail, blackout and peripheral
loss during reconfiguration, overlay apply/remove reliability at MiSTer switch frequency,
authentication, driver rebind), then judge whether that case wins; and separately, whether
dropping 0043–0045 for fpga-region idioms is actually sufficient.

**Outcome.** Neither conclusion was overturned. The UX-viability conclusion **survives**;
the DP-9 split verdict **survives**. Both survived unanimously — no minority refutation to
carry — but both were amended, and the amendments are substantive rather than cosmetic.

**Verification I did myself before writing (2026-08-21).** I re-opened, at the cited lines,
`stratix10-soc.c`, `of-fpga-region.c`, `fpga-mgr.c`, `fpga-region.c`, `fpga-bridge.c`,
`stratix10-svc.c`, `dfl-fme-pr.c`, `firmware_loader/main.c`, the four Kconfig files,
`include/linux/of.h`, both binding YAMLs, `socfpga_agilex5.dtsi`, `socfpga_agilex.dtsi` and
`socfpga.dtsi`, plus the four DE10 patch texts. Corrections applied to line numbers the
draft got slightly wrong: `fpga_bridges_disable` is at `fpga-bridge.c:190` (draft said 181);
`fpga_image_info_alloc`'s `devm_kzalloc` is at `fpga-mgr.c:115` (draft cited a range);
`stratix10-svc.c`'s compatible table is at `:1133-1136` (draft said 1134-1135); the manager
match table runs to `:452`; `CONFIG_FPGA` is a `menuconfig` at `drivers/fpga/Kconfig:6`. No
fabricated citation was found in the draft. I also fetched and text-extracted the *UM* PDF
myself, upgrading four claims from snippet grade to read-document grade, and found the
*A5-series* upstream patches, which neither the draft nor either refuter had.

**Corrections accepted and applied.**

| # | From | Correction | Where |
|---|---|---|---|
| 1 | R1 | *AXE5* is not a neutral timing datapoint — the thread's subject is a second-configuration hang. Add as adverse evidence. | §6.1 row 4a, §1 item 2, §6.2, §6.3 step 3 |
| 2 | R1 | Delete "nothing in the evidence puts it above one second"; the `msleep(1000)`/30 s status poll is an in-evidence multi-second mechanism. | §2.5, §6.1 row 7, §6.2 |
| 3 | R1 | Scope "the only mainline path to `fpga_mgr_load()`" to this manager; `dfl-fme-pr.c:146` is a userspace-ioctl counterexample. | §2.6 |
| 4 | R1 + R2 | Drop "HDMI 2.0" for the ADV7513; the *UM* body says v1.4 / 165 MHz / 1080p, and the manual contradicts itself. | §7.4 |
| 5 | R1 | Soften "will fail" to "will almost always fail" for a missing `config-complete-timeout-us`; a benign race exists. | §4.3, §6.3 step 6 |
| 6 | R1 | The `MiSTer_fb` port-cost **[V]** leans past its citation; restate as inference. | §7.3 |
| 7 | R2 | "Very unlikely to be perceived" is over-written; every switch blanks fabric-owned HDMI. Claim parity with the DE10 instead, and flag that the DE10 baseline is itself unmeasured. | §1, §6.3 |
| 8 | R2 | Add the two *UM*-verified peripheral facts: USB 2.0 OTG is HPS-side (input survives); HDMI is fabric-side (display does not). Cite the fetchable mirror. | §1, §7.4 |
| 9 | R2 | Both `of_overlay_fdt_apply()` callers apply once per device lifetime; MiSTer's cycling has no mainline precedent. | §3.2 |
| 10 | R2 | Scope *AXE5* to the SDM-write phase; it is a U-Boot measurement, not the Linux overlay transaction. | §6.1 row 4, §6.2 |
| 11 | R2 | "No per-core kernel work proportional to core complexity" → "no parsing or validation work"; the copy is size-proportional. | §1 |

One refinement of my own to correction 9: R2 wrote that the two callers "never remove"
their overlay. They do — `lan966x_pci.c:136`, `rp1_pci.c:299,315` **[V]** — on device
teardown. The accurate statement, used above, is *one* apply/remove per device lifetime,
never repeated cycling in service. R2's conclusion is unaffected.

**Correction not applied, and why.** R2's requirement that the DP-9 narrowing "must land as
an actual edit to `docs/de25-nano-plan.md` §6" and that a new DP be opened is **sound and
accepted in substance, but out of this task's scope to execute**: D0.2's brief is this
dossier plus one cross-link in `de25-boot-chain.md`, and rewriting a decision record in the
plan unilaterally — while another agent may be editing those docs — is not mine to do here.
It is carried as an explicit blocking action item in §8 and as §11 row 11 rather than
dropped. Anyone accepting §8's "confirmed" enum inherits that edit.

**Not challenged by either refuter** (i.e. verified and undisputed, so quotable): the
SMCCC-to-EL3 architecture and `GET_MEM` shared-buffer discovery; the full
overlay→program→load→SDM sequence; the buffer geometry and every timeout being a ceiling;
the ignored `encrypted-fpga-config` flag; the zero-default `config_complete_timeout_us`
chain; the bareness of `socfpga_agilex5.dtsi`; the absence of any Agilex-5 compatible in
6.18.44; the absence of a mainline overlay loader; the `OF_OVERLAY` non-select trap; the
whole Kconfig table; the firmware search path; the Cyclone-V-only content of 0043/0044 and
the generic nature of 0045; and the demotion of the H2F window map to **[U]**.

**Still contested / weakest links after the pass.** (a) *AXE5* could not be re-fetched by
either refuter or by me (403 live, Wayback unreachable from this environment); its figures
rest on the draft's Wayback snapshot and its adverse subject on 2026-08-21 search
corroboration. (b) *A5-overlay* (thread 314152) is snippet-grade only and is doing real work
in §3.2 and §4.2 — it is the only report of the Linux overlay path actually working on
Agilex 5, and it has not been read directly. (c) Everything attributed to Intel documents
remains unread and **[U]**.

## 11. Open [U] — how each is settled, and who inherits it

| # | Unknown | How it gets settled | Inherits |
|---|---|---|---|
| 1 | Does the factory DE25-Nano QSPI ship with VAB/QKY keys provisioned — i.e. will unsigned community `.rbf` load? | Load a locally built unsigned `core.rbf` and observe SDM accept/reject; or obtain and fully read Intel doc 762191 / the Agilex 5 Configuration UG (both 403 on 2026-08-21). The *UM* is now read and is silent, which is weak permissive evidence only | **D2.5** (first hour); a doc fetch is worth attempting before hardware purchase |
| 2 | Do `intel,agilex-svc` / `intel,agilex-soc-fpga-mgr` bind and function on Agilex 5 silicon? | Substantially de-risked by the *A5-series* fallback declaration (§3.1) but not proven: author §4.2's DT, boot, check `/sys/class/fpga_manager/` and the probe dmesg. Desk follow-up: check whether the series landed in a post-6.18 kernel and what else it dragged in | **D2.5**; the mainline-landing check is desk work for **D0.3** |
| 3 | Measured reconfiguration latency: storage read vs overlay apply vs SDM write vs overlay remove | §6.3, steps 2–4, 20 iterations. Watch for SDM windows that are near-exact 1 s multiples (§6.1 row 7) | **D2.5** |
| 4 | Does the region accept repeated overlay apply/remove cycles cleanly — no leaks, no second-switch failure, HPS→fabric access still alive afterwards? | §6.3 step 3, iterations 2..20, with an LWH2F-window read after every switch. **Raised in priority**: no mainline user cycles overlays (§3.2) and *AXE5* reports a second-configuration hang on Agilex 5 (§6.1 row 4a) | **D2.5** |
| 5 | Does an overlay omitting `config-complete-timeout-us` fail immediately? | §6.3 step 6, several runs (benign race, §4.3) | **D2.5** |
| 6 | Which overlay-loader option — carry `OF_CONFIGFS`, write a board driver, or U-Boot-preload only | Design decision once §3.2's options are costed; classify the configfs patch against `docs/patch-provenance.md` (origin is the 2014 Antoniou series; the shipping form was not located) | **D2** (design), **D0.3** may classify the patch |
| 7 | Actual A5EB013 `core.rbf` size, and the SDM's internal config clock/bus width | Build a GHRD-based `core.rbf` in Quartus Prime Pro and `stat` it; read the Agilex 5 datasheet PDF locally rather than the JS docs site | **D2.5** / desk, whenever a PDF mirror is found |
| 8 | Agilex 5 F2H and F2SDRAM window addresses and widths | Read Intel HPS TRM 814346/813752 directly — needs an authenticated fetch, a mirror, or a human-supplied PDF | **D0.1/D2.2** recon; blocks §7.3 |
| 9 | Is fabric access to HPS LPDDR4A coherent by default, or must the fabric master assert CCU/ACE-Lite via AXUSER? | Same TRM chapter, then measure on hardware once a GHRD test image exists | **D2.2/D2.5**; plan §7 calls this the highest-value unknown and it stays that way |
| 10 | Does the 0045 write-combine throughput floor reproduce on Agilex 5/ARMv8? | Map the shared aperture Device-nGnRnE vs Normal-NC and measure streaming read/write each way — the same test that produced the DE10's ~100/~54 MB/s | **D2.5**; feeds the DP that replaces DP-9's Claim B |
| 11 | What runtime doorbell/aperture mechanism the DE25 uses (the actual purpose of 0043–0045) | Gated on L0's register-access model and on a GHRD; not resolvable by desk research. **Needs its own DP**, plus the plan §6 DP-9 wording edit (§8) | **L0 watch (D0.4)** → its own DP, *not* DP-9 |
| 12 | Does Terasic's GHRD wire LPDDR4A to the HPS hard EMIF by default, or is that a per-design Platform Designer choice? *UM* §3.7.4 says the bank *can*, and that the FPGA may claim it if the HPS does not | Inspect the System CD's `golden_top` / `.qsys` once obtained | **D0.1** (BSP quality already flagged unassessed) |
| 13 | Phase-1/phase-2 version-skew tolerance across Quartus/SDM versions | Not stated in any reachable Altera doc; treat as project-side convention per `de25-boot-chain.md` §5 until a doc says otherwise | **D0.1 Q2**, **D2.2** |
| 14 | Does the Agilex 5 `svc` node need `iommus = <&smmu 10>` (upstream has it; 6.18.44's DTSI has no `smmu` node)? | Read the *A5-series* DTS patch against whichever DTSI it targets; test both forms on hardware | **D0.3** desk, **D2.5** confirm |
| 15 | Can the ADV7513's control I2C be muxed onto the HPS bus (*UM* Figure 3-13, not text-extractable)? | Read the figure from the PDF as an image, or the System CD schematic | **D0.1**; does not change DP-10 (§7.4) |
